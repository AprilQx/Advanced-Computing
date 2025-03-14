/**
 * @file optimized_heat_diffusion.cpp
 * @brief Implementation of heat diffusion using flat array access
 */

 #include "optimized_heat_diffusion.h"
 #include <iostream>
 #include <fstream>
 #include <cstdlib>
 #include <algorithm>
 #include <cmath>
  #include "../../include/Array_2D/Array_2D.h"

 
 OptimizedHeatDiffusion2D::OptimizedHeatDiffusion2D(int w, int h, double rate, bool save)
     : width(w), 
       height(h), 
       diffusionRate(rate), 
       temperature(h, w),
       nextTemperature(h, w),
       saveOutput(save), 
       frameCount(0) {
     
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
 
 void OptimizedHeatDiffusion2D::update() {
     // Pre-compute constants
     const double diffusionFactor = diffusionRate;
     const int maxRow = height - 1;
     const int maxCol = width - 1;
     
     // Get direct pointers to the underlying arrays for faster access
     double* temp_data = temperature.getData();
     double* next_data = nextTemperature.getData();
     
     // Direct flat array access implementation
     for (int y = 1; y < maxRow; y++) {
         // Pre-compute row offsets once per row for efficiency
         const int row_idx = y * width;
         const int row_above_idx = (y-1) * width;
         const int row_below_idx = (y+1) * width;
         
         for (int x = 1; x < maxCol; x++) {
             // Center element
             const double center = temp_data[row_idx + x];
             
             // Discrete Laplacian operator using direct array access
             const double laplacian = 
                 temp_data[row_below_idx + x] +  // below
                 temp_data[row_above_idx + x] +  // above
                 temp_data[row_idx + (x+1)] +    // right
                 temp_data[row_idx + (x-1)] -    // left
                 4.0 * center;                   // center
             
             // Update next temperature
             next_data[row_idx + x] = center + diffusionFactor * laplacian;
         }
     }
     
     // Swap buffers
     temperature.swap(nextTemperature);
     
     // Save frame if output is enabled
     saveFrame(frameCount);
     frameCount++;
 }
 
 double OptimizedHeatDiffusion2D::getChecksum() const {
     double sum = 0.0;
     
     // Use direct row-major traversal for checksum calculation
     for (int y = 0; y < height; ++y) {
         for (int x = 0; x < width; ++x) {
             sum += temperature(y, x);
         }
     }
     
     return sum;
 }
 
 void OptimizedHeatDiffusion2D::saveFrame(int frameNumber) {
     if (!saveOutput) return;
     
     static bool dirCreated = false;
     if (!dirCreated) {
         system("mkdir -p output/optimized");
         dirCreated = true;
     }
     
     std::string filename = "output/optimized/frame_" + std::to_string(frameNumber) + ".txt";
     std::ofstream outFile(filename);
     
     if (outFile.is_open()) {
         for (int y = 0; y < height; ++y) {
             for (int x = 0; x < width; ++x) {
                 outFile << temperature(y, x) << " ";
             }
             outFile << "\n";
         }
         outFile.close();
     }
 }