/**
 * @file optimized_heat_diffusion_2d.cpp
 * @brief Implementation of heat diffusion using 2D arrays with cache blocking
 * 
 *  *
 * Optimizations:
 * - Cached row access
 * - Const references and pre-computed constants
 * - Optimized memory access patterns
 * - Optional output to reduce benchmark overhead
 * - Performance statistics reporting
 */


 #include "optimized_heat_diffusion.h"
 #include <iostream>
 #include <fstream>
 #include <cstdlib>
 #include <algorithm>
 #include <cmath>
 #include <chrono>
 #include "../../include/Array_2D/Array_2D.h"
 
 OptimizedHeatDiffusionD::OptimizedHeatDiffusionD(int w, int h, double rate, bool save)
     : width(w), height(h), diffusionRate(rate),temperature(h,w),nextTemperature(h,w), saveOutput(save), frameCount(0) {
     
     // Initialize with ambient temperature (20°C)
     temperature.fill(20.0);
     nextTemperature.fill(20.0);
     
     
     // Set up initial conditions - hot spot in the middle (100°C)
     int centerX = width / 2;
     int centerY = height / 2;
     for (int y = centerY - 3; y <= centerY + 3; y++) {
         for (int x = centerX - 3; x <= centerX + 3; x++) {
             if (y >= 0 && y < height && x >= 0 && x < width) {
                 temperature(y, x) = 100.0;
             }
         }
     }
 }
 

 
 void OptimizedHeatDiffusionD::update() {
     // Try smaller block sizes for this problem size
     // These can be tuned for your specific hardware
     const int blockSizeY = 512; //BUGS!!!!!!!!!!!
     const int blockSizeX = 1;
     
     // Pre-compute constants outside all loops
     const double diffusionFactor = diffusionRate;
     const int maxRow = height - 1;
     const int maxCol = width - 1;

     // Get direct pointers to the underlying arrays for faster access
     double* temp_data = temperature.getData();
     double* next_data = nextTemperature.getData();
     
     // Cache blocking implementation
     for (int yBlock = 1; yBlock < maxRow; yBlock += blockSizeY) {
         const int yEnd = std::min(yBlock + blockSizeY, maxRow);
         
         for (int xBlock = 1; xBlock < maxCol; xBlock += blockSizeX) {
             const int xEnd = std::min(xBlock + blockSizeX, maxCol);
             
             // Process each cell within the block
             for (int y = yBlock; y < yEnd; y++) {
                const int row_idx = y * width;
                const int row_above_idx = (y-1) * width;
                const int row_below_idx = (y+1) * width;
                 for (int x = xBlock; x < xEnd; x++) {
                    // Center element
                    const double center = temp_data[row_idx + x];
                     // Discrete Laplacian operator
                     const double laplacian = 
                        temp_data[row_below_idx + x] +  // below
                        temp_data[row_above_idx + x] +  // above
                        temp_data[row_idx + (x+1)] +    // right
                        temp_data[row_idx + (x-1)] -    // left
                        4.0 * center;                   // center
                    
                            
                     // Update the cell in the next timestep buffer
                     next_data[row_idx + x] = center + diffusionFactor * laplacian;
                 }
             }
         }
     }
     
     // Swap buffers using a temporary pointer (very fast)
     temperature.swap(nextTemperature);
     
     saveFrame(frameCount);
     frameCount++;
 }
 
 double OptimizedHeatDiffusionD::getChecksum() const {
     double sum = 0.0;
     
     // Use cache-aware traversal for checksum calculation
     for (int y = 0; y < height; ++y) {
         for (int x = 0; x < width; ++x) {
             sum += temperature(y,x);
         }
     }
     
     return sum;
 }
 
 void OptimizedHeatDiffusionD::saveFrame(int frameNumber) {
     if (!saveOutput) return;
     
     static bool dirCreated = false;
     if (!dirCreated) {
         system("mkdir -p output/optimised_2d");
         dirCreated = true;
     }
     
     std::string filename = "output/optimised_2d/frame_" + std::to_string(frameNumber) + ".txt";
     std::ofstream outFile(filename);
     
     if (outFile.is_open()) {
         for (int y = 0; y < height; ++y) {
             for (int x = 0; x < width; ++x) {
                 outFile <<  temperature(y,x) << " ";
             }
             outFile << "\n";
         }
         outFile.close();
     }
 }