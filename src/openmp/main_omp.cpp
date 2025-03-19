/**
 * @file main_openmp.cpp
 * @brief Test program for the OpenMP-parallelized heat diffusion 
 */

 #include "optimized_heat_diffusion_omp.h"
 #include <iostream>
 #include <vector>
 #include <chrono>
 #include <numeric>
 #include <cmath>
 #include <algorithm>
 #include <omp.h>
 #include "../../include/Array_2D/Array_2D.h"
 
 int main(int argc, char* argv[]) {
     // Default settings
     int width = 100;                // Grid width
     int height = 100;               // Grid height
     double diffusionRate = 0.1;     // Diffusion rate
     int totalFrames = 100;          // Number of frames to simulate
     bool saveOutput = false;        // Disable output files for benchmark
     int runs = 10;                  // Number of runs for statistics
     int numThreads = 8;             // Number of threads (0 = use system default)

    char* omp_num_threads = getenv("OMP_NUM_THREADS");
    if (omp_num_threads) {
        std::cout << "OMP_NUM_THREADS environment variable: " << omp_num_threads << std::endl;
    } else {
        std::cout << "OMP_NUM_THREADS environment variable not set" << std::endl;
    }
     
     // Parse command line arguments
     for (int i = 1; i < argc; i++) {
         std::string arg = argv[i];
         
         if (arg == "--width" && i + 1 < argc) {
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
         } else if (arg == "--runs" && i + 1 < argc) {
             runs = std::atoi(argv[++i]);
         }
     }
     
     // Create simulation with specified number of threads
     OpenMPHeatDiffusion2D simulation(width, height, diffusionRate, saveOutput, numThreads);
     
     // Print simulation parameters
     std::cout << "Running OpenMP heat diffusion simulation with parameters:" << std::endl
               << "  Grid size: " << width << "x" << height << std::endl
               << "  Diffusion rate: " << diffusionRate << std::endl
               << "  Total frames: " << totalFrames << std::endl
               << "  Using " << simulation.getNumThreads() << " OpenMP threads" << std::endl
               << "  Output: " << (saveOutput ? "enabled" : "disabled") << std::endl;
     
     // Timing statistics
     std::vector<double> runtimes;
     
     // Run multiple benchmark iterations
     for (int run = 1; run <= runs; ++run) {
         // Reset the simulation for each run (if runs > 1)
         if (run > 1) {
             simulation = OpenMPHeatDiffusion2D(width, height, diffusionRate, saveOutput, numThreads);
         }
         
         // Record start time
         auto startTime = std::chrono::high_resolution_clock::now();
         
         // Run simulation for specified number of frames
         for (int i = 0; i < totalFrames; i++) {
             simulation.update();
         }
         
         // Record end time and calculate duration
         auto endTime = std::chrono::high_resolution_clock::now();
         double totalSimTime = std::chrono::duration<double, std::milli>(endTime - startTime).count();
         
         // Store runtime in ms
         double runtime = totalSimTime;
         runtimes.push_back(runtime);
         
         // Report performance
         std::cout << "Run " << run << " completed in " << runtime << " ms" << std::endl;
         std::cout << "Final temperature checksum: " << simulation.getChecksum() << std::endl;
     }
     
     // Calculate statistics
     double totalTime = std::accumulate(runtimes.begin(), runtimes.end(), 0.0);
     double meanTime = totalTime / runs;
     
     double sumSquaredDiff = 0.0;
     for (double time : runtimes) {
         sumSquaredDiff += (time - meanTime) * (time - meanTime);
     }
     double stdDev = std::sqrt(sumSquaredDiff / runs);
     
     double minTime = *std::min_element(runtimes.begin(), runtimes.end());
     double maxTime = *std::max_element(runtimes.begin(), runtimes.end());
     
     // Report statistics
     std::cout << "Performance Statistics over " << runs << " runs:" << std::endl;
     std::cout << "  Average time: " << meanTime << " ms" << std::endl;
     std::cout << "  Standard deviation: " << stdDev << " ms" << std::endl;
     std::cout << "  Minimum time: " << minTime << " ms" << std::endl;
     std::cout << "  Maximum time: " << maxTime << " ms" << std::endl;
     
     return 0;
 }