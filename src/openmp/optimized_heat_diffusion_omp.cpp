/**
 * @file openmp_heat_diffusion.cpp
 * @brief Implementation of heat diffusion using OpenMP parallelization
 */

 #include "optimized_heat_diffusion_omp.h"
 #include <iostream>
 #include <fstream>
 #include <cstdlib>
 #include <algorithm>
 #include <cmath>
 #include <omp.h>
 #include "../../include/Array_2D/Array_2D.h"
 
 OpenMPHeatDiffusion2D::OpenMPHeatDiffusion2D(int w, int h, double rate, bool save, int threads)
     : width(w), 
       height(h), 
       diffusionRate(rate), 
       temperature(h, w),
       nextTemperature(h, w),
       saveOutput(save), 
       frameCount(0),
       numThreads(threads) {
     
    // Set number of threads if specified
    if (threads > 0) {
        // Set thread count only if explicitly provided
        omp_set_num_threads(threads);
        numThreads = threads;
    } else {
        // Use system default or environment variable setting
        numThreads = omp_get_max_threads();
    }
    
    // Verify thread count
    int actual_threads = 0;
    #pragma omp parallel
    {
        #pragma omp master
        {
            actual_threads = omp_get_num_threads();
        }
    }
    numThreads = actual_threads; // Store the actual number of threads being used
    std::cout << "OpenMP initialized with " << numThreads << " threads" << std::endl;
     
     
     // Initialize with ambient temperature (20°C)
     temperature.fill(20.0);
     nextTemperature.fill(20.0);
     
     // Set up initial conditions - hot spot in the middle (100°C)
     int centerX = width / 2;
     int centerY = height / 2;
     
     // This initialization can also be parallelized
     #pragma omp parallel for collapse(2)
     for (int y = centerY - 3; y <= centerY + 3; y++) {
         for (int x = centerX - 3; x <= centerX + 3; x++) {
             if (y >= 0 && y < height && x >= 0 && x < width) {
                 temperature(y, x) = 100.0;
             }
         }
     }
 }
 
 void OpenMPHeatDiffusion2D::update() {
     // Pre-compute constants
     const double diffusionFactor = diffusionRate;
     const int maxRow = height - 1;
     const int maxCol = width - 1;
     // Get direct pointers to the underlying arrays for faster access
     double* temp_data = temperature.getData();
     double* next_data = nextTemperature.getData();
     
     // Parallelize the main computation loop with OpenMP
     #pragma omp parallel for 
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
     
     // Swap buffers - not parallelized as it's a simple pointer swap
     temperature.swap(nextTemperature);
     
     // Save frame if output is enabled
     saveFrame(frameCount);
     frameCount++;
 }
 
 double OpenMPHeatDiffusion2D::getChecksum() const {
     double sum = 0.0;
     
     // Parallelize checksum calculation with a reduction
     #pragma omp parallel for reduction(+:sum)
     for (int y = 0; y < height; ++y) {
         for (int x = 0; x < width; ++x) {
             sum += temperature(y, x);
         }
     }
     
     return sum;
 }
 
 void OpenMPHeatDiffusion2D::saveFrame(int frameNumber) {
     if (!saveOutput) return;
     
     static bool dirCreated = false;
     if (!dirCreated) {
         system("mkdir -p output/openmp");
         dirCreated = true;
     }
     
     std::string filename = "output/openmp/frame_" + std::to_string(frameNumber) + ".txt";
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
 
 void OpenMPHeatDiffusion2D::setNumThreads(int threads) {
    if (threads > 0) {
        numThreads = threads;
        omp_set_num_threads(numThreads);
        
        // Verify the thread count was set correctly
        int actual_threads = 0;
        #pragma omp parallel
        {
            #pragma omp master
            {
                actual_threads = omp_get_num_threads();
            }
        }
        numThreads = actual_threads; // Update with actual count
    } else {
        // Reset to system default
        numThreads = omp_get_max_threads();
        omp_set_num_threads(numThreads);
    }
}

int OpenMPHeatDiffusion2D::getNumThreads() const {
    // Simply return the stored thread count
    // This is more efficient than creating a parallel region just to check
    return numThreads;
}