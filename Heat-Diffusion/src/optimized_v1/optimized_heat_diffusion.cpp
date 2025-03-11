/**
 * @file optimized_heat_diffusion.cpp
 * @brief Implementation of the optimized heat diffusion simulation
 */

 #include "optimized_heat_diffusion.h"
 #include <iostream>
 #include <fstream>
 #include <cstdlib>
 #include <algorithm>
 #include <cmath>
 
 OptimizedHeatDiffusion::OptimizedHeatDiffusion(int w, int h, double rate, bool save) 
     : width(w), height(h), diffusionRate(rate), saveOutput(save), frameCount(0) {
     
     // Allocate flat arrays for temperature grids
     temperature = new double[width * height];
     nextTemperature = new double[width * height];
     
     // Initialize with ambient temperature (20°C)
     for (int i = 0; i < width * height; ++i) {
         temperature[i] = 20.0;
         nextTemperature[i] = 20.0;
     }
     
     // Set up initial conditions - hot spot in the middle (100°C)
     int centerX = width  *0.5;
     int centerY = height *0.5;
     for (int y = centerY - 3; y <= centerY + 3; y++) {
         for (int x = centerX - 3; x <= centerX + 3; x++) {
             if (y >= 0 && y < height && x >= 0 && x < width) {
                 temperature[idx(y, x)] = 100.0;
             }
         }
     }
 }
 
  OptimizedHeatDiffusion::~OptimizedHeatDiffusion() {
          delete[] temperature;
      delete[] nextTemperature;
  }
 
 void OptimizedHeatDiffusion::update() {
     // Calculate new temperatures using the heat equation with optimized memory access
     for (int y = 1; y < height - 1; y++) {
         // Pre-compute row offsets to reduce index calculations
         const int rowOffset = y * width;
         const int topRowOffset = (y - 1) * width;
         const int bottomRowOffset = (y + 1) * width;
         
         for (int x = 1; x < width - 1; x++) {
             // Discrete Laplacian operator with flattened array indexing
             const double laplacian = 
                 temperature[topRowOffset + x] +          // Top
                 temperature[bottomRowOffset + x] +       // Bottom
                 temperature[rowOffset + x + 1] +         // Right
                 temperature[rowOffset + x - 1] -         // Left
                 4.0 * temperature[rowOffset + x];        // Center (4x)
             
             // Update the cell in the next timestep buffer
             nextTemperature[rowOffset + x] = temperature[rowOffset + x] + diffusionRate * laplacian;
         }
     }
 
    // Swap buffers using a temporary pointer (very fast)
     // Swap buffers using pointer swap (very fast)
    double* temp = temperature;
    temperature = nextTemperature;
    nextTemperature = temp;
     
     saveFrame(frameCount);
     frameCount++;
 }
 
 double OptimizedHeatDiffusion::getChecksum() const {
     double sum = 0.0;
     const int totalSize = width * height;
     
     // Use manual loop unrolling for better performance
     const int unrollFactor = 4;
     const int limit = totalSize - (totalSize % unrollFactor);
     
     int i = 0;
     for (; i < limit; i += unrollFactor) {
         sum += temperature[i] + temperature[i+1] + temperature[i+2] + temperature[i+3];
     }
     
     // Handle remaining elements
     for (; i < totalSize; ++i) {
         sum += temperature[i];
     }
     
     return sum;
 }
 
 void OptimizedHeatDiffusion::saveFrame(int frameNumber) {
    if (!saveOutput) return;
    
    system("mkdir -p output/optimised");
    std::string filename = "output/optimised/frame_" + std::to_string(frameNumber) + ".txt";
    std::ofstream outFile(filename);
    
    if (outFile.is_open()) {
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                outFile << temperature[y * width + x] << " ";
            }
            outFile << "\n";
        }
        outFile.close();
    }
}
