/**
 * @file heat_diffusion_benchmark_hybrid.cpp
 * @brief Benchmark for 2D Heat Diffusion Simulation with Hybrid MPI+OpenMP parallelization
 */


 #include "../src/hybrid/optimized_heat_diffusion_hybrid.h"
 #include <iostream>
 #include <chrono>
 #include <iomanip>
 #include <vector>
 #include <algorithm>
 #include <numeric>
 #include <cmath>
 #include <mpi.h>
 #include <omp.h>
 
 // For memory usage reporting
 #include <sys/resource.h>
 
 #ifdef __APPLE__
 #include <mach/mach.h>
 #endif
 
 // Function to get memory usage in KB - cross-platform
 long getMemoryUsage() {
 #ifdef __APPLE__
     // macOS - use Mach kernel APIs for more accurate reporting
     struct mach_task_basic_info info;
     mach_msg_type_number_t size = MACH_TASK_BASIC_INFO_COUNT;
     
     if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &size) == KERN_SUCCESS) {
         // Convert from bytes to KB
         return info.resident_size / 1024;
     }
     return 0;
 #else
     // Linux implementation
     struct rusage usage;
     getrusage(RUSAGE_SELF, &usage);
     return usage.ru_maxrss;
 #endif
 }
 
 // Function to calculate standard deviation
 double calculateStdDev(const std::vector<double>& values, double mean) {
     double variance = 0.0;
     for (const auto& value : values) {
         double diff = value - mean;
         variance += diff * diff;
     }
     return std::sqrt(variance / values.size());
 }
 
 int main(int argc, char* argv[]) {
     // Initialize MPI with thread support for OpenMP
     int provided;
     MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
     
     // Check if MPI provides the required level of thread support
     int rank, size;
     MPI_Comm_rank(MPI_COMM_WORLD, &rank);
     MPI_Comm_size(MPI_COMM_WORLD, &size);
     
     if (rank == 0 && provided < MPI_THREAD_FUNNELED) {
         std::cerr << "Warning: MPI implementation does not provide required thread support level." << std::endl;
     }
     
     // Default values
     int gridSize = 1000;
     int iterations = 1000;
     bool saveOutput = false;
     int numRuns = 10;  // Run the benchmark 10 times
     int requestedRanks = -1;  // Default: no specific rank count requested
     int numThreads = 0;  // Default: use system default for OpenMP threads
     
     // Parse command line arguments
     for (int i = 1; i < argc; i++) {
         std::string arg = argv[i];
         if (arg == "--size" && i + 1 < argc) {
             gridSize = std::stoi(argv[++i]);
         } else if (arg == "--iterations" && i + 1 < argc) {
             iterations = std::stoi(argv[++i]);
         } else if (arg == "--save") {
             saveOutput = true;
         } else if (arg == "--runs" && i + 1 < argc) {
             numRuns = std::stoi(argv[++i]);
         } else if (arg == "--ranks" && i + 1 < argc) {
             requestedRanks = std::stoi(argv[++i]);
         } else if (arg == "--threads" && i + 1 < argc) {
             numThreads = std::stoi(argv[++i]);
         }
     }
     
     // Validate the number of ranks if specified
     if (requestedRanks > 0 && size != requestedRanks) {
         if (rank == 0) {
             std::cerr << "Error: Benchmark requested " << requestedRanks 
                      << " ranks but is running with " << size << " ranks." << std::endl;
             std::cerr << "Please run with: mpirun -n " << requestedRanks 
                      << " ./heat_diffusion_hybrid_benchmark [other options]" << std::endl;
         }
         MPI_Finalize();
         return 1;
     }
     
     // Set OpenMP threads if requested
     if (numThreads > 0) {
         omp_set_num_threads(numThreads);
     }
     
     // Get actual number of threads that will be used
     int actualThreads = 1;  // Default to 1 in case OpenMP is not enabled
     #pragma omp parallel
     {
         #pragma omp master
         {
             actualThreads = omp_get_num_threads();
         }
     }
     
     if (rank == 0) {
         std::cout << "Running benchmark with grid size " << gridSize << "x" << gridSize 
                  << " for " << iterations << " iterations"
                  << " across " << numRuns << " runs"
                  << " using " << size << " MPI ranks and " << actualThreads << " OpenMP threads per rank"
                  << " (total " << size * actualThreads << " parallel units)"
                  << (saveOutput ? " (with output)" : " (no output)") << std::endl;
         
         // Print OpenMP environment info
         char* omp_num_threads = getenv("OMP_NUM_THREADS");
         std::cout << "OpenMP environment: "
                  << "OMP_NUM_THREADS=" << (omp_num_threads ? omp_num_threads : "not set")
                  << ", Max threads available=" << omp_get_max_threads()
                  << ", Using=" << actualThreads << std::endl;
     }
     
     // Variables to store aggregated statistics
     std::vector<double> totalSimTimes;
     std::vector<double> setupTimes;
     std::vector<double> avgIterTimes;
     std::vector<double> minIterTimes;
     std::vector<double> maxIterTimes;
     std::vector<double> perfMetrics;
     std::vector<long> memoryUsages;
     std::vector<double> checksums;
     
     for (int run = 0; run < numRuns; run++) {
         if (rank == 0) {
             std::cout << "\n=== Run " << (run + 1) << " of " << numRuns << " ===" << std::endl;
         }
         
         // Record initial memory usage
         long initialMemory = getMemoryUsage();
         
         // Create simulation
         auto startSetup = std::chrono::high_resolution_clock::now();
         HybridHeatDiffusion2D simulation(gridSize, gridSize, 0.1, saveOutput, numThreads);
         auto endSetup = std::chrono::high_resolution_clock::now();
         
         // Record memory after setup
         long afterSetupMemory = getMemoryUsage();
         
         // Record simulation time with detailed per-iteration timing
         std::vector<double> iterationTimes;
         iterationTimes.reserve(iterations);
         
         auto totalStart = std::chrono::high_resolution_clock::now();
         
         for (int i = 0; i < iterations; i++) {
             auto iterStart = std::chrono::high_resolution_clock::now();
             simulation.update();
             auto iterEnd = std::chrono::high_resolution_clock::now();
             
             double iterTime = std::chrono::duration<double, std::milli>(iterEnd - iterStart).count();
             iterationTimes.push_back(iterTime);
             
             // Optionally report progress every 100 iterations
             if (rank == 0 && i > 0 && i % 100 == 0) {
                 std::cout << "  Completed " << i << "/" << iterations << " iterations" << std::endl;
             }
         }
         
         auto totalEnd = std::chrono::high_resolution_clock::now();
         
         // Calculate timing statistics
         double totalSimTime = std::chrono::duration<double, std::milli>(totalEnd - totalStart).count();
         double setupTime = std::chrono::duration<double, std::milli>(endSetup - startSetup).count();
         
         double minTime = *std::min_element(iterationTimes.begin(), iterationTimes.end());
         double maxTime = *std::max_element(iterationTimes.begin(), iterationTimes.end());
         double avgTime = totalSimTime / iterations;
         
         // Get final memory usage
         long finalMemory = getMemoryUsage();
         long memoryIncrease = finalMemory - initialMemory;
         
         // Calculate performance metric (cell updates per second)
         double perfMetric = (gridSize * gridSize * iterations / totalSimTime * 1000);
         
         // Get checksum
         double checksum = simulation.getChecksum();
         
         // Store results for this run
         totalSimTimes.push_back(totalSimTime);
         setupTimes.push_back(setupTime);
         avgIterTimes.push_back(avgTime);
         minIterTimes.push_back(minTime);
         maxIterTimes.push_back(maxTime);
         perfMetrics.push_back(perfMetric);
         memoryUsages.push_back(memoryIncrease);
         checksums.push_back(checksum);
         
         // Print individual run results (only on rank 0)
         if (rank == 0) {
             std::cout << "Run " << (run + 1) << " Results:" << std::endl;
             std::cout << "  Setup Time: " << setupTime << " ms" << std::endl;
             std::cout << "  Total Simulation Time: " << totalSimTime << " ms" << std::endl;
             std::cout << "  Average Iteration Time: " << avgTime << " ms" << std::endl;
             std::cout << "  Min/Max Iteration Time: " << minTime << "/" << maxTime << " ms" << std::endl;
             std::cout << "  Performance: " << perfMetric << " cell updates per second" << std::endl;
             std::cout << "  Memory Usage Increase: " << memoryIncrease << " KB" << std::endl;
             std::cout << "  Checksum: " << checksum << std::endl;
         }
     }
     
     // Only rank 0 calculates and prints aggregate statistics
     if (rank == 0) {
         // Calculate aggregate statistics
         double avgTotalSimTime = std::accumulate(totalSimTimes.begin(), totalSimTimes.end(), 0.0) / numRuns;
         double avgSetupTime = std::accumulate(setupTimes.begin(), setupTimes.end(), 0.0) / numRuns;
         double avgIterTime = std::accumulate(avgIterTimes.begin(), avgIterTimes.end(), 0.0) / numRuns;
         double avgMinIterTime = std::accumulate(minIterTimes.begin(), minIterTimes.end(), 0.0) / numRuns;
         double avgMaxIterTime = std::accumulate(maxIterTimes.begin(), maxIterTimes.end(), 0.0) / numRuns;
         double avgPerfMetric = std::accumulate(perfMetrics.begin(), perfMetrics.end(), 0.0) / numRuns;
         double avgMemoryUsage = std::accumulate(memoryUsages.begin(), memoryUsages.end(), 0.0) / numRuns;
         
         // Calculate standard deviations
         double stdDevTotalSimTime = calculateStdDev(totalSimTimes, avgTotalSimTime);
         double stdDevSetupTime = calculateStdDev(setupTimes, avgSetupTime);
         double stdDevIterTime = calculateStdDev(avgIterTimes, avgIterTime);
         double stdDevPerfMetric = calculateStdDev(perfMetrics, avgPerfMetric);
         
         // Identify best and worst runs
         int bestRunIndex = std::min_element(totalSimTimes.begin(), totalSimTimes.end()) - totalSimTimes.begin();
         int worstRunIndex = std::max_element(totalSimTimes.begin(), totalSimTimes.end()) - totalSimTimes.begin();
         
         // Check if all checksums are the same (numerical stability)
         bool stable = std::adjacent_find(checksums.begin(), checksums.end(), 
                                         [](double a, double b) { return std::abs(a - b) > 1e-10; }) == checksums.end();
         
         // Print aggregate results
         std::cout << "\n=== AGGREGATE BENCHMARK RESULTS (" << numRuns << " RUNS) ===" << std::endl;
         std::cout << "Grid Size: " << gridSize << "x" << gridSize << " (" 
                  << gridSize*gridSize << " cells)" << std::endl;
         std::cout << "Iterations per Run: " << iterations << std::endl;
         std::cout << "Parallel Configuration: " << size << " MPI ranks × " << actualThreads 
                  << " OpenMP threads = " << (size * actualThreads) << " total parallel units" << std::endl;
         
         std::cout << "\nTiming Statistics:" << std::endl;
         std::cout << "  Average Setup Time: " << avgSetupTime << " ms (StdDev: " << stdDevSetupTime << " ms)" << std::endl;
         std::cout << "  Average Total Simulation Time: " << avgTotalSimTime << " ms (StdDev: " << stdDevTotalSimTime << " ms)" << std::endl;
         std::cout << "  Average Iteration Time: " << avgIterTime << " ms (StdDev: " << stdDevIterTime << " ms)" << std::endl;
         std::cout << "  Average Min/Max Iteration Time: " << avgMinIterTime << "/" << avgMaxIterTime << " ms" << std::endl;
         
         std::cout << "\nPerformance Statistics:" << std::endl;
         std::cout << "  Average Performance: " << std::fixed << std::setprecision(2) << (avgPerfMetric / 1e6) 
                  << " million cell updates per second (StdDev: " << (stdDevPerfMetric / 1e6) << ")" << std::endl;
         std::cout << "  Cell updates per second per parallel unit: " 
                  << std::fixed << std::setprecision(2) << (avgPerfMetric / 1e6 / (size * actualThreads)) 
                  << " million" << std::endl;
         std::cout << "  Best Run: Run " << (bestRunIndex + 1) << " (" << totalSimTimes[bestRunIndex] << " ms)" << std::endl;
         std::cout << "  Worst Run: Run " << (worstRunIndex + 1) << " (" << totalSimTimes[worstRunIndex] << " ms)" << std::endl;
         std::cout << "  Coefficient of Variation: " << (stdDevTotalSimTime / avgTotalSimTime * 100) << "%" << std::endl;
         
         std::cout << "\nMemory Usage:" << std::endl;
         std::cout << "  Average Memory Increase: " << avgMemoryUsage << " KB" << std::endl;
         std::cout << "  Average Memory Per Rank: " << (avgMemoryUsage / size) << " KB" << std::endl;
         
         std::cout << "\nNumerical Stability:" << std::endl;
         std::cout << "  Checksum consistency: " << (stable ? "Stable" : "Unstable") << std::endl;
         std::cout << "  Final checksum: " << checksums.back() << std::endl;
         
         // Output in CSV format for scripted analysis
         std::cout << "\nCSV Format (for data collection):" << std::endl;
         std::cout << "grid_size,iterations,mpi_ranks,omp_threads,total_units,avg_time_ms,stddev_ms,performance_mcups,memory_kb,checksum" << std::endl;
         std::cout << gridSize << "," 
                  << iterations << "," 
                  << size << "," 
                  << actualThreads << "," 
                  << (size * actualThreads) << "," 
                  << avgTotalSimTime << "," 
                  << stdDevTotalSimTime << "," 
                  << (avgPerfMetric / 1e6) << "," 
                  << avgMemoryUsage << "," 
                  << checksums.back() 
                  << std::endl;
     }
     
     // Finalize MPI
     MPI_Finalize();
     return 0;
 }