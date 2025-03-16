/**
 * @file main_mpi.cpp
 * @brief MacOS-compatible main program for MPI-parallelized heat diffusion simulation
 */

 #include "optimized_heat_diffusion_mpi.h"
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
 
 // Forward declarations
 void printUsage(const char* programName);
 void runSimulation(int width, int height, double diffusionRate, int totalFrames, bool saveOutput);
 
 /**
  * @brief Main function running the MPI-parallelized heat diffusion simulation
  */
 int main(int argc, char* argv[]) {
     // Initialize MPI with only thread support necessary
     MPI_Init(&argc, &argv);
     
     int rank, worldSize;
     MPI_Comm_rank(MPI_COMM_WORLD, &rank);
     MPI_Comm_size(MPI_COMM_WORLD, &worldSize);
     
     // Default settings
     int width = 1000;
     int height = 1000;
     double diffusionRate = 0.1;
     int totalFrames = 1000;
     bool saveOutput = false;
     std::string outputDir = "output/optimised";
     
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
     MPI_Bcast(&saveOutput, 1, MPI_C_BOOL, 0, MPI_COMM_WORLD);
     
     // Print simulation parameters (only rank 0)
     if (rank == 0) {
         std::cout << "Running MPI-parallelized heat diffusion simulation with parameters:" << std::endl
                   << "  Grid size: " << width << "x" << height << std::endl
                   << "  Diffusion rate: " << diffusionRate << std::endl
                   << "  Total frames: " << totalFrames << std::endl
                   << "  Number of MPI processes: " << worldSize << std::endl
                   << "  Output: " << (saveOutput ? "enabled" : "disabled") << std::endl;
     }
     
     // Create output directory if needed (only rank 0)
     if (saveOutput && rank == 0) {
         system("mkdir -p output/mpi");
     }
     
     // Run the simulation
     runSimulation(width, height, diffusionRate, totalFrames, saveOutput);
     
     // Clean MPI termination (use specialized approach for macOS)
     if (rank == 0) {
         std::cout << "Simulation complete. Finalizing MPI..." << std::endl;
     }
     
     MPI_Barrier(MPI_COMM_WORLD);
     MPI_Finalize();
     
     if (rank == 0) {
         std::cout << "MPI finalized successfully." << std::endl;
     }
     
     return 0;
 }
 
 /**
  * @brief Run the simulation and collect performance statistics
  */
 void runSimulation(int width, int height, double diffusionRate, int totalFrames, bool saveOutput) {
     int rank, worldSize;
     MPI_Comm_rank(MPI_COMM_WORLD, &rank);
     MPI_Comm_size(MPI_COMM_WORLD, &worldSize);
     
     const int numRuns = 10; // Run multiple times to get performance statistics
     std::vector<double> runTimes;
     
     for (int run = 0; run < numRuns; run++) {
         if (rank == 0) {
             std::cout << "Starting run " << run + 1 << " of " << numRuns << std::endl;
         }
         
         // Create simulation instance
         OptimizedHeatDiffusionMPI simulation(width, height, diffusionRate, saveOutput);
         
         // Synchronize before timing
         MPI_Barrier(MPI_COMM_WORLD);
         
         // Record start time
         auto startTime = std::chrono::high_resolution_clock::now();
         
         // Run simulation for specified number of frames
         for (int i = 0; i < totalFrames; i++) {
             simulation.update();
         }
         
         // Synchronize to ensure all processes are finished
         MPI_Barrier(MPI_COMM_WORLD);
         
         // Record end time and calculate duration
         auto endTime = std::chrono::high_resolution_clock::now();
         double totalSimTime = std::chrono::duration<double, std::milli>(endTime - startTime).count();
         
         // Store the time in milliseconds
         runTimes.push_back(totalSimTime);
         
         // Print results for this run (only rank 0)
         if (rank == 0) {
             std::cout << "Run " << (run + 1) << " completed in " << totalSimTime << " ms" << std::endl;
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
         std::cout << "\nPerformance Statistics over " << numRuns << " runs with " << worldSize << " MPI processes:" << std::endl;
         std::cout << "  Average time: " << meanTime << " ms" << std::endl;
         std::cout << "  Standard deviation: " << stdDev << " ms" << std::endl;
         std::cout << "  Minimum time: " << minTime << " ms" << std::endl;
         std::cout << "  Maximum time: " << maxTime << " ms" << std::endl;
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