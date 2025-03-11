/**
 * @file main.cpp
 * @brief Test program for the 2D array with cache blocking implementation
 */

 #include "optimized_heat_diffusion.h"
 #include <iostream>
 #include <vector>
 #include <chrono>
 #include <numeric>
 #include <cmath>
 
 int main(int argc, char* argv[]) {
     // Default settings
     int width = 100;                // increased grid size to see cache effects
     int height = 100;
     double diffusionRate = 0.1;
     int totalFrames = 100;
     bool saveOutput = false;        // Disable output files for benchmark
     int runs = 10;                  // Number of runs for statistics
     
     // Print simulation parameters
     std::cout << "Running optimized heat diffusion simulation with parameters:" << std::endl
               << "  Grid size: " << width << "x" << height << std::endl
               << "  Diffusion rate: " << diffusionRate << std::endl
               << "  Total frames: " << totalFrames << std::endl
               << "  Output: " << (saveOutput ? "enabled" : "disabled") << std::endl;
     
     // Timing statistics
     std::vector<double> runtimes;
     
     // Run multiple benchmark iterations
     for (int run = 1; run <= runs; ++run) {
         // Create simulation
         OptimizedHeatDiffusion2D simulation(width, height, diffusionRate, saveOutput);
         
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