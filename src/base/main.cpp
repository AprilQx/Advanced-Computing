/**
 * @file main.cpp
 * @brief Main program for the heat diffusion simulation
 * 
 * This file contains the main function that creates and runs
 * the heat diffusion simulation with command line argument support.
 */

 #include "heat_diffusion.h"
 #include <iostream>
 #include <chrono>
 #include <filesystem>
 #include <string>
 #include <cstdlib>
 #include <cstring>
#include <numeric>

#include <cmath>     // For pow, sqrt
#include <algorithm> 
 
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
               << "  --output            Enable output file generation\n"
               << "  --output-dir DIR       Directory for output files (default: output)\n"
               << std::endl;
 }
 
 /**
  * @brief Main function running the heat diffusion simulation
  * 
  * Creates a heat diffusion simulation with parameters specified via
  * command line arguments and runs it for the specified number of frames.
  * 
  * @param argc Number of command line arguments
  * @param argv Array of command line arguments
  * @return Exit code (0 for success)
  */
 int main(int argc, char* argv[]) {
     // Default settings
     int width = 100;
     int height = 100;
     double diffusionRate = 0.1;
     int totalFrames = 100;
     bool saveOutput = false;
     std::string outputDir = "output/base";
     int numRuns = 10;
     std::vector<double> runTimes;
     
     // Parse command line arguments
     for (int i = 1; i < argc; i++) {
         std::string arg = argv[i];
         
         if (arg == "--help") {
             printUsage(argv[0]);
             return 0;
         } else if (arg == "--width" && i + 1 < argc) {
             width = std::atoi(argv[++i]);
         } else if (arg == "--height" && i + 1 < argc) {
             height = std::atoi(argv[++i]);
         } else if (arg == "--rate" && i + 1 < argc) {
             diffusionRate = std::atof(argv[++i]);
         } else if (arg == "--frames" && i + 1 < argc) {
             totalFrames = std::atoi(argv[++i]);
         } else if (arg == "--output") {
             saveOutput = true;
         } else if (arg == "--output-dir" && i + 1 < argc) {
             outputDir = argv[++i];
         } else {
             std::cerr << "Unknown option: " << arg << std::endl;
             printUsage(argv[0]);
             return 1;
         }
     }
     
     // Validate arguments
     if (width <= 0 || height <= 0) {
         std::cerr << "Error: Grid dimensions must be positive" << std::endl;
         return 1;
     }
     
     if (diffusionRate <= 0) {
         std::cerr << "Error: Diffusion rate must be positive" << std::endl;
         return 1;
     }
     
     if (totalFrames <= 0) {
         std::cerr << "Error: Number of frames must be positive" << std::endl;
         return 1;
     }
     
     // Print simulation parameters
     std::cout << "Running heat diffusion simulation with parameters:" << std::endl
               << "  Grid size: " << width << "x" << height << std::endl
               << "  Diffusion rate: " << diffusionRate << std::endl
               << "  Total frames: " << totalFrames << std::endl
               << "  Output: " << (saveOutput ? outputDir : "disabled") << std::endl;
     
     // Create output directory if needed
     if (saveOutput) {
         std::filesystem::create_directories(outputDir);
     }
     

     for (int run = 0; run < numRuns; run++) {
        
        // Create and run simulation
        HeatDiffusion simulation(width, height, diffusionRate, saveOutput);
        
         // Record start time
        auto startTime = std::chrono::high_resolution_clock::now();
        for (int i = 0; i < totalFrames; i++) {
            simulation.update();
        }
        
        // Record end time and calculate duration
        auto endTime = std::chrono::high_resolution_clock::now();
        double totalSimTime = std::chrono::duration<double, std::milli>(endTime - startTime).count();
        
        // Store the time in milliseconds
        runTimes.push_back(totalSimTime);
        
        std::cout << "Run " << (run + 1) << " completed in " << totalSimTime << " ms" << std::endl;
        std::cout << "Final temperature checksum: " << simulation.getChecksum() << std::endl;
    }
    
        // Calculate statistics
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
        std::cout << "  Average time: " << meanTime << " ms" << std::endl;
        std::cout << "  Standard deviation: " << stdDev << " ms" << std::endl;
        std::cout << "  Minimum time: " << minTime << " ms" << std::endl;
        std::cout << "  Maximum time: " << maxTime << " ms" << std::endl; 
     
     return 0;
    }