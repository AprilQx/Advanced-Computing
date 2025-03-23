/**
 * @file main_hybrid.cpp
 * @brief Main program for Hybrid MPI+OpenMP parallelized heat diffusion simulation
 */

 #include "optimized_heat_diffusion_hybrid.h"
 #include <iostream>
 #include <chrono>
 #include <string>
 #include <cstdlib>
 #include <cstring>
 #include <numeric>
 #include <vector>
 #include <cmath>
 #include <algorithm>
 #include <mpi.h>
 #include <omp.h>
#include "../../include/Array_2D/Array_2D.h"
 // Forward declarations
 void printUsage(const char* programName);
 void runSimulation(int width, int height, double diffusionRate, int totalFrames, bool saveOutput, int numThreads);
 
 /**
  * @brief Main function running the hybrid MPI+OpenMP parallelized heat diffusion simulation
  */
 int main(int argc, char* argv[]) {
     // Initialize MPI with thread support required by OpenMP
     int provided;
     MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
     
     // Check if MPI provides the required level of thread support
     int rank, worldSize;
     MPI_Comm_rank(MPI_COMM_WORLD, &rank);
     MPI_Comm_size(MPI_COMM_WORLD, &worldSize);
     
     if (rank == 0) {
         if (provided < MPI_THREAD_FUNNELED) {
             std::cerr << "Warning: MPI implementation does not provide required thread support level." << std::endl;
         }
     }
     
     // Default settings
     int width = 1000;
     int height = 1000;
     double diffusionRate = 0.1;
     int totalFrames = 1000;
     bool saveOutput = false;
     std::string outputDir = "output/hybrid";
     int numThreads = 0; // 0 means use system default
     
     // Parse command line arguments (rank 0 will do this and broadcast)
     if (rank == 0) {
         for (int i = 1; i < argc; i++) {
             std::string arg = argv[i];
             
             if (arg == "--help") {
                 printUsage(argv[0]);
                 MPI_Abort(MPI_COMM_WORLD, 0);
                 return 0;
             } else if (arg == "--width" && i + 1 < argc) {
                 width = std::atoi(argv[++i]);
             } else if (arg == "--height" && i + 1 < argc) {
                 height = std::atoi(argv[++i]);
             } else if (arg == "--rate" && i + 1 < argc) {
                 diffusionRate = std::atof(argv[++i]);
             } else if (arg == "--frames" && i + 1 < argc) {
                 totalFrames = std::atoi(argv[++i]);
             } else if (arg == "--threads" && i + 1 < argc) {
                 numThreads = std::atoi(argv[++i]);
             } else if (arg == "--output") {
                 saveOutput = true;
             } else if (arg == "--output-dir" && i + 1 < argc) {
                 outputDir = argv[++i];
             } else {
                 std::cerr << "Unknown option: " << arg << std::endl;
                 printUsage(argv[0]);
                 MPI_Abort(MPI_COMM_WORLD, 1);
                 return 1;
             }
         }
         
         // Validate arguments
         if (width <= 0 || height <= 0) {
             std::cerr << "Error: Grid dimensions must be positive" << std::endl;
             MPI_Abort(MPI_COMM_WORLD, 1);
             return 1;
         }
         
         if (diffusionRate <= 0) {
             std::cerr << "Error: Diffusion rate must be positive" << std::endl;
             MPI_Abort(MPI_COMM_WORLD, 1);
             return 1;
         }
         
         if (totalFrames <= 0) {
             std::cerr << "Error: Number of frames must be positive" << std::endl;
             MPI_Abort(MPI_COMM_WORLD, 1);
             return 1;
         }
     }
     
     // Broadcast parameters to all processes
     MPI_Bcast(&width, 1, MPI_INT, 0, MPI_COMM_WORLD);
     MPI_Bcast(&height, 1, MPI_INT, 0, MPI_COMM_WORLD);
     MPI_Bcast(&diffusionRate, 1, MPI_DOUBLE, 0, MPI_COMM_WORLD);
     MPI_Bcast(&totalFrames, 1, MPI_INT, 0, MPI_COMM_WORLD);
     MPI_Bcast(&numThreads, 1, MPI_INT, 0, MPI_COMM_WORLD);
     MPI_Bcast(&saveOutput, 1, MPI_C_BOOL, 0, MPI_COMM_WORLD);
     
     // Print OpenMP environment info on rank 0
     if (rank == 0) {
         // Check environment variables
         char* omp_num_threads = getenv("OMP_NUM_THREADS");
         if (omp_num_threads) {
             std::cout << "OMP_NUM_THREADS environment variable: " << omp_num_threads << std::endl;
         } else {
             std::cout << "OMP_NUM_THREADS environment variable not set" << std::endl;
         }
         
         std::cout << "Max OpenMP threads available: " << omp_get_max_threads() << std::endl;
         std::cout << "OpenMP thread count requested: " << (numThreads > 0 ? numThreads : omp_get_max_threads()) << std::endl;
     }
     
     // Run the simulation
     runSimulation(width, height, diffusionRate, totalFrames, saveOutput, numThreads);
     
     // Clean MPI termination
     if (rank == 0) {
         std::cout << "Simulation complete. Finalizing MPI..." << std::endl;
     }
     
     MPI_Barrier(MPI_COMM_WORLD);
     MPI_Finalize();
     
     return 0;
 }
 
 /**
  * @brief Run the simulation and collect performance statistics
  */
 void runSimulation(int width, int height, double diffusionRate, int totalFrames, bool saveOutput, int numThreads) {
     int rank, worldSize;
     MPI_Comm_rank(MPI_COMM_WORLD, &rank);
     MPI_Comm_size(MPI_COMM_WORLD, &worldSize);
     
     // Create output directory if needed (only rank 0)
     if (saveOutput && rank == 0) {
         system("mkdir -p output/hybrid");
     }
     
     // Print simulation parameters (only rank 0)
     if (rank == 0) {
         std::cout << "Running Hybrid MPI+OpenMP heat diffusion simulation with parameters:" << std::endl
                   << "  Grid size: " << width << "x" << height << std::endl
                   << "  Diffusion rate: " << diffusionRate << std::endl
                   << "  Total frames: " << totalFrames << std::endl
                   << "  Number of MPI processes: " << worldSize << std::endl
                   << "  OpenMP threads per MPI process: " << (numThreads > 0 ? numThreads : omp_get_max_threads()) << std::endl
                   << "  Total parallel units: " << worldSize * (numThreads > 0 ? numThreads : omp_get_max_threads()) << std::endl
                   << "  Output: " << (saveOutput ? "enabled" : "disabled") << std::endl;
     }
     
     const int numRuns = 5; // Run multiple times to get better performance statistics
     std::vector<double> runTimes;
     
     for (int run = 0; run < numRuns; run++) {
         if (rank == 0) {
             std::cout << "Starting run " << run + 1 << " of " << numRuns << std::endl;
         }
         
         // Create simulation instance
         HybridHeatDiffusion2D simulation(width, height, diffusionRate, saveOutput, numThreads);
         
         // Synchronize before timing
         MPI_Barrier(MPI_COMM_WORLD);
         
         // Record start time
         auto startTime = std::chrono::high_resolution_clock::now();
         
         // Run simulation for specified number of frames
         for (int i = 0; i < totalFrames; i++) {
             simulation.update();
             
             // Optional: report progress every 100 frames
             if (rank == 0 && (i+1) % 100 == 0) {
                 std::cout << "Completed " << (i+1) << " frames of " << totalFrames << std::endl;
             }
         }
         
         // Synchronize to ensure all processes are finished
         MPI_Barrier(MPI_COMM_WORLD);
         
         // Record end time and calculate duration
         auto endTime = std::chrono::high_resolution_clock::now();
         double totalSimTime = std::chrono::duration<double, std::milli>(endTime - startTime).count();
         
         // Store the time in milliseconds
         runTimes.push_back(totalSimTime);
         
         // Calculate checksum to verify correctness
         double checksum = simulation.getChecksum();
         
         // Print results for this run (only rank 0)
         if (rank == 0) {
             std::cout << "Run " << (run + 1) << " completed in " << totalSimTime << " ms" << std::endl;
             std::cout << "Final temperature checksum: " << checksum << std::endl;
         }
         
         // Give MPI some time to clean up
         MPI_Barrier(MPI_COMM_WORLD);
     }
     
     // Calculate statistics (only rank 0)
     if (rank == 0 && !runTimes.empty()) {
         double totalTime = std::accumulate(runTimes.begin(), runTimes.end(), 0.0);
         double meanTime = totalTime / numRuns;
         
         // Calculate standard deviation
         double variance = 0.0;
         for (const auto& time : runTimes) {
             variance += std::pow(time - meanTime, 2);
         }
         double stdDev = std::sqrt(variance / numRuns);
         
         // Find min and max times
         double minTime = *std::min_element(runTimes.begin(), runTimes.end());
         double maxTime = *std::max_element(runTimes.begin(), runTimes.end());
         
         // Output statistics
         std::cout << "\nPerformance Statistics over " << numRuns << " runs:" << std::endl;
         std::cout << "  MPI Processes: " << worldSize << std::endl;
         std::cout << "  OpenMP Threads per Process: " << numThreads << std::endl;
         std::cout << "  Total Parallel Units: " << worldSize * numThreads << std::endl;
         std::cout << "  Average time: " << meanTime << " ms" << std::endl;
         std::cout << "  Standard deviation: " << stdDev << " ms" << std::endl;
         std::cout << "  Minimum time: " << minTime << " ms" << std::endl;
         std::cout << "  Maximum time: " << maxTime << " ms" << std::endl;
         
         // Calculate frames per second
         double fps = totalFrames / (meanTime / 1000.0);
         std::cout << "  Average frames per second: " << fps << std::endl;
     }
    }

 /**
  * @brief Print usage instructions for the program
  * @param programName Name of the executable
  */
 void printUsage(const char* programName) {
    std::cout << "Usage: " << programName << " [OPTIONS]\n"
              << "Options:\n"
              << "  --help                 Show this help message\n"
              << "  --width WIDTH          Set grid width (default: 100)\n"
              << "  --height HEIGHT        Set grid height (default: 100)\n"
              << "  --rate RATE            Set diffusion rate (default: 0.1)\n"
              << "  --frames FRAMES        Set number of frames to simulate (default: 100)\n"
              << "  --output               Enable output file generation\n"
              << "  --output-dir DIR       Directory for output files (default: output/mpi)\n"
              << std::endl;
}