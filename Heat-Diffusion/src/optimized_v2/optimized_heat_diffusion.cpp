/**
 * @file optimized_heat_diffusion_2d.cpp
 * @brief Implementation of heat diffusion using 2D arrays with cache blocking
 */

 #include "optimized_heat_diffusion.h"
 #include <iostream>
 #include <fstream>
 #include <cstdlib>
 #include <algorithm>
 #include <cmath>
 
 OptimizedHeatDiffusion2D::OptimizedHeatDiffusion2D(int w, int h, double rate, bool save)
     : width(w), height(h), diffusionRate(rate), saveOutput(save), frameCount(0) {
     
     // Allocate 2D arrays for temperature grids
     temperature = new double*[height];
     nextTemperature = new double*[height];
     
     for (int i = 0; i < height; ++i) {
         temperature[i] = new double[width];
         nextTemperature[i] = new double[width];
         
         // Initialize with ambient temperature (20°C)
         for (int j = 0; j < width; ++j) {
             temperature[i][j] = 20.0;
             nextTemperature[i][j] = 20.0;
         }
     }
     
     // Set up initial conditions - hot spot in the middle (100°C)
     int centerX = width / 2;
     int centerY = height / 2;
     for (int y = centerY - 3; y <= centerY + 3; y++) {
         for (int x = centerX - 3; x <= centerX + 3; x++) {
             if (y >= 0 && y < height && x >= 0 && x < width) {
                 temperature[y][x] = 100.0;
             }
         }
     }
 }
 
 OptimizedHeatDiffusion2D::~OptimizedHeatDiffusion2D() {
     // Free memory
     for (int i = 0; i < height; ++i) {
         delete[] temperature[i];
         delete[] nextTemperature[i];
     }
     delete[] temperature;
     delete[] nextTemperature;
 }
 
 void OptimizedHeatDiffusion2D::update() {
     // Try smaller block sizes for this problem size
     // These can be tuned for your specific hardware
     const int blockSizeY = 16;
     const int blockSizeX = 16;
     
     // Pre-compute constants outside all loops
     const double diffusionFactor = diffusionRate;
     const int maxRow = height - 1;
     const int maxCol = width - 1;
     
     // Cache blocking implementation
     for (int yBlock = 1; yBlock < maxRow; yBlock += blockSizeY) {
         const int yEnd = std::min(yBlock + blockSizeY, maxRow);
         
         for (int xBlock = 1; xBlock < maxCol; xBlock += blockSizeX) {
             const int xEnd = std::min(xBlock + blockSizeX, maxCol);
             
             // Process each cell within the block
             for (int y = yBlock; y < yEnd; y++) {
                 for (int x = xBlock; x < xEnd; x++) {
                     // Discrete Laplacian operator
                     const double laplacian = 
                         temperature[y+1][x] + 
                         temperature[y-1][x] + 
                         temperature[y][x+1] + 
                         temperature[y][x-1] - 
                         4.0 * temperature[y][x];
                     
                     // Update the cell in the next timestep buffer
                     nextTemperature[y][x] = temperature[y][x] + diffusionFactor * laplacian;
                 }
             }
         }
     }
     
     // Swap buffers using a temporary pointer (very fast)
     double** temp = temperature;
     temperature = nextTemperature;
     nextTemperature = temp;
     
     saveFrame(frameCount);
     frameCount++;
 }
 
 double OptimizedHeatDiffusion2D::getChecksum() const {
     double sum = 0.0;
     
     // Use cache-aware traversal for checksum calculation
     for (int y = 0; y < height; ++y) {
         for (int x = 0; x < width; ++x) {
             sum += temperature[y][x];
         }
     }
     
     return sum;
 }
 
 void OptimizedHeatDiffusion2D::saveFrame(int frameNumber) {
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
                 outFile << temperature[y][x] << " ";
             }
             outFile << "\n";
         }
         outFile.close();
     }
 }