/**
 * @file heat_diffusion_benchmark.cpp
 * @brief Benchmark for 2D Heat Diffusion Simulation (simplified single run)
 */

 #include "../src/base/heat_diffusion.h"
 #include <iostream>
 #include <chrono>
 #include <iomanip>
 #include <vector>
 #include <algorithm>
 #include <numeric>
 #include <cmath>
 
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
 
 int main(int argc, char* argv[]) {
     // Default values
     int gridSize = 100;
     int iterations = 100;
     bool saveOutput = false;
     
     // Parse command line arguments
     for (int i = 1; i < argc; i++) {
         std::string arg = argv[i];
         if (arg == "--size" && i + 1 < argc) {
             gridSize = std::stoi(argv[++i]);
         } else if (arg == "--iterations" && i + 1 < argc) {
             iterations = std::stoi(argv[++i]);
         } else if (arg == "--save") {
             saveOutput = true;
         }
     }
     
     std::cout << "Running benchmark with grid size " << gridSize << "x" << gridSize 
               << " for " << iterations << " iterations"
               << (saveOutput ? " (with output)" : " (no output)") << std::endl;
     
     // Record initial memory usage
     long initialMemory = getMemoryUsage();
     
     // Create simulation
     auto startSetup = std::chrono::high_resolution_clock::now();
     HeatDiffusion simulation(gridSize, gridSize, 0.1, saveOutput);
     auto endSetup = std::chrono::high_resolution_clock::now();
     
     // Record memory after setup
     long afterSetupMemory = getMemoryUsage();
     
     // Record simulation time with detailed per-iteration timing
     std::vector<double> iterationTimes;
     iterationTimes.reserve(iterations);
     
     auto totalStart = std::chrono::high_resolution_clock::now();
     
     for (int i = 0; i < iterations; i++) {
         simulation.update();
     }
     
     auto totalEnd = std::chrono::high_resolution_clock::now();
     
     // Calculate timing statistics
     double totalSimTime = std::chrono::duration<double, std::milli>(totalEnd - totalStart).count();
     double setupTime = std::chrono::duration<double, std::milli>(endSetup - startSetup).count();
     
 
     
     // Get final memory usage
     long finalMemory = getMemoryUsage();
     long memoryIncrease = finalMemory - initialMemory;
     
     // Calculate performance metric
     double perfMetric = (gridSize * gridSize * iterations / totalSimTime * 1000);
     
     // Get checksum
     double checksum = simulation.getChecksum();
     
     // Print results
     std::cout << "\n=== BENCHMARK RESULTS ===" << std::endl;
     std::cout << "Grid Size: " << gridSize << "x" << gridSize << " (" 
               << gridSize*gridSize << " cells)" << std::endl;
     std::cout << "Iterations: " << iterations << std::endl;
     std::cout << "\nTiming Statistics:" << std::endl;
     std::cout << "  Setup Time: " << setupTime << " ms" << std::endl;
     std::cout << "  Total Simulation Time: " << totalSimTime << " ms" << std::endl;
     std::cout << "\nPerformance Statistics:" << std::endl;
     std::cout << "  Performance: " << perfMetric << " cell updates per second" << std::endl;
     std::cout << "\nMemory Usage:" << std::endl;
     std::cout << "  Memory Increase: " << memoryIncrease << " KB" << std::endl;
     std::cout << "\nNumerical Stability:" << std::endl;
     std::cout << "  Checksum: " << checksum << std::endl;
     
     return 0;
 }