/**
 * @file block_size_optimizer.cpp
 * @brief Program to find optimal cache block sizes for the heat diffusion simulation
 * 
 * This program tests different block sizes from 1 to 1024 to find the combination 
 * that yields the best performance for the heat diffusion simulation.
 */

 #include "../src/optimized_v3/optimized_heat_diffusion.h"
 #include <iostream>
 #include <vector>
 #include <chrono>
 #include <algorithm>
 #include <iomanip>
 #include <fstream>
 
 // Modified version of OptimizedHeatDiffusion2D that accepts block sizes
 class BlockSizeTestDiffusion : public OptimizedHeatDiffusion2D {
 private:
     int blockSizeX;
     int blockSizeY;
 
 public:
     BlockSizeTestDiffusion(int w, int h, double rate, int bsx, int bsy)
         : OptimizedHeatDiffusion2D(w, h, rate, false), blockSizeX(bsx), blockSizeY(bsy) {}
 
     void update() {
         // Pre-compute constants outside all loops
         const double diffusionFactor = getDiffusionRate();
         const int width = getWidth();
         const int height = getHeight();
         const int maxRow = height - 1;
         const int maxCol = width - 1;
 
         // Get direct pointers to the underlying arrays for faster access
         double* temp_data = getTemperature().getData();
         double* next_data = getNextTemperature().getData();
         
         // Cache blocking implementation with variable block sizes
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
         
         // Swap buffers using the base class method
         swapBuffers();
     }
 };
 
 // Structure to hold benchmark results
 struct BenchmarkResult {
     int blockSizeX;
     int blockSizeY;
     double runtime;
     
     BenchmarkResult(int x, int y, double t) : blockSizeX(x), blockSizeY(y), runtime(t) {}
     
     bool operator<(const BenchmarkResult& other) const {
         return runtime < other.runtime;
     }
 };
 
 int main() {
     // Simulation parameters
     int width = 10000;               // Larger grid to better observe cache effects
     int height = 10000;
     double diffusionRate = 0.1;
     int totalFrames = 10000;           // Reduced frame count for faster benchmarking
     
     std::cout << "Running block size optimization for heat diffusion simulation" << std::endl;
     std::cout << "Grid size: " << width << "x" << height << std::endl;
     std::cout << "Diffusion rate: " << diffusionRate << std::endl;
     std::cout << "Frames per test: " << totalFrames << std::endl;
     
     // Store all results
     std::vector<BenchmarkResult> results;
     
     // Block sizes to test (powers of 2 plus some intermediate values)
     std::vector<int> blockSizes;
     
     // Generate block sizes to test
     // Adding powers of 2 and some values in between
     for (int i = 1; i <= 512; i *= 2) {
         blockSizes.push_back(i);
         if (i < 256) blockSizes.push_back(i + i/2); // Add 1.5x the power of 2 (e.g., 3, 6, 12, 24...)
     }
     
     // Add some specific values known to be good for cache optimization
     blockSizes.push_back(16);
     blockSizes.push_back(32);
     blockSizes.push_back(64);
     blockSizes.push_back(128);
     blockSizes.push_back(144);  // Your current value
     blockSizes.push_back(256);
     
     // Sort and remove duplicates
     std::sort(blockSizes.begin(), blockSizes.end());
     blockSizes.erase(std::unique(blockSizes.begin(), blockSizes.end()), blockSizes.end());
     
     std::cout << "Testing " << blockSizes.size() * blockSizes.size() << " different block size combinations..." << std::endl;
     
     // Create a results file
     std::ofstream resultsFile("block_size_results.csv");
     resultsFile << "BlockSizeX,BlockSizeY,Runtime(ms)" << std::endl;
     
     // Test all combinations of block sizes
     int testCount = 0;
     int totalTests = blockSizes.size() * blockSizes.size();
     
     for (int bsizeX : blockSizes) {
         for (int bsizeY : blockSizes) {
             testCount++;
             std::cout << "Testing block size " << bsizeX << "x" << bsizeY 
                       << " (" << testCount << "/" << totalTests << ")" << std::flush;
             
             // Create simulation with current block sizes
             BlockSizeTestDiffusion simulation(width, height, diffusionRate, bsizeX, bsizeY);
             
             // Warmup (to eliminate JIT, cache, and other first-run effects)
             for (int i = 0; i < 3; i++) {
                 simulation.update();
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
             
             // Store results
             results.emplace_back(bsizeX, bsizeY, totalSimTime);
             
             // Output to console and file
             std::cout << " - " << totalSimTime << " ms" << std::endl;
             resultsFile << bsizeX << "," << bsizeY << "," << totalSimTime << std::endl;
         }
     }
     
     resultsFile.close();
     
     // Sort results by runtime (fastest first)
     std::sort(results.begin(), results.end());
     
     // Output top 10 results
     std::cout << "\nTop 10 Block Sizes (fastest):" << std::endl;
     std::cout << "+----------+----------+----------------+" << std::endl;
     std::cout << "| BlockSizeX | BlockSizeY | Runtime (ms) |" << std::endl;
     std::cout << "+----------+----------+----------------+" << std::endl;
     
     for (int i = 0; i < std::min(10, static_cast<int>(results.size())); i++) {
         std::cout << "| " << std::setw(8) << results[i].blockSizeX 
                   << " | " << std::setw(8) << results[i].blockSizeY 
                   << " | " << std::setw(12) << std::fixed << std::setprecision(2) << results[i].runtime 
                   << " |" << std::endl;
     }
     std::cout << "+----------+----------+----------------+" << std::endl;
     
     // Output the optimal block size
     std::cout << "\nOptimal block size: " << results[0].blockSizeX << "x" << results[0].blockSizeY << std::endl;
     std::cout << "Runtime: " << results[0].runtime << " ms" << std::endl;
     
     // Compare with your current 144x144 setting
     auto currentIt = std::find_if(results.begin(), results.end(), 
                                [](const BenchmarkResult& r) { 
                                    return r.blockSizeX == 144 && r.blockSizeY == 144; 
                                });
     if (currentIt != results.end()) {
         int currentRank = std::distance(results.begin(), currentIt) + 1;
         std::cout << "\nCurrent block size (144x144) performance:" << std::endl;
         std::cout << "Rank: " << currentRank << " of " << results.size() << std::endl;
         std::cout << "Runtime: " << currentIt->runtime << " ms" << std::endl;
         
         double improvement = (currentIt->runtime - results[0].runtime) / currentIt->runtime * 100.0;
         std::cout << "Potential improvement: " << std::fixed << std::setprecision(2) << improvement << "%" << std::endl;
     }
     
     std::cout << "\nResults saved to block_size_results.csv" << std::endl;
     
     return 0;
 }