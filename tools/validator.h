/**
 * @file validator.h
 * @brief Standalone validation utilities for heat diffusion simulation
 *
 * Provides functions to validate that optimized implementations
 * produce the same results as the baseline implementation.
 * Designed to be used independently from the main simulation code.
 */

 #ifndef VALIDATOR_H
 #define VALIDATOR_H
 
 #include <vector>
 #include <string>
 #include <fstream>
 #include <cmath>
 #include <sstream>
 #include <iostream>
 #include <iomanip>
 #include <filesystem>
 #include <algorithm> 
 
 namespace validator {
 
 /**
  * @brief Tolerance for floating point comparisons
  */
 constexpr double TOLERANCE = 1e-10;
 
 /**
  * @brief Load temperature grid from file
  * 
  * @param filename Input filename
  * @return Loaded temperature grid
  */
 std::vector<std::vector<double>> loadGrid(const std::string& filename) {
     std::vector<std::vector<double>> grid;
     std::ifstream inFile(filename);
     
     if (!inFile.is_open()) {
         std::cerr << "Failed to open file: " << filename << std::endl;
         return grid;
     }
     
     std::string line;
     while (std::getline(inFile, line)) {
         std::vector<double> row;
         std::istringstream iss(line);
         double value;
         
         while (iss >> value) {
             row.push_back(value);
         }
         
         if (!row.empty()) {
             grid.push_back(row);
         }
     }
     
     inFile.close();
     return grid;
 }
 
 /**
  * @brief Validates if two temperature grids are equivalent within tolerance
  * 
  * @param grid1 First temperature grid
  * @param grid2 Second temperature grid
  * @param tolerance Maximum allowed difference between corresponding elements
  * @return true if grids are equivalent, false otherwise
  */
 bool compareGrids(const std::vector<std::vector<double>>& grid1, 
                  const std::vector<std::vector<double>>& grid2,
                  double tolerance = TOLERANCE) {
     
     if (grid1.size() != grid2.size()) {
         std::cerr << "Grid height mismatch: " << grid1.size() << " vs " << grid2.size() << std::endl;
         return false;
     }
     
     for (size_t y = 0; y < grid1.size(); ++y) {
         if (grid1[y].size() != grid2[y].size()) {
             std::cerr << "Grid width mismatch at row " << y << ": " 
                       << grid1[y].size() << " vs " << grid2[y].size() << std::endl;
             return false;
         }
         
         for (size_t x = 0; x < grid1[y].size(); ++x) {
             double diff = std::abs(grid1[y][x] - grid2[y][x]);
             if (diff > tolerance) {
                 std::cerr << "Value mismatch at (" << x << "," << y << "): " 
                           << grid1[y][x] << " vs " << grid2[y][x] 
                           << " (diff: " << diff << ")" << std::endl;
                 return false;
             }
         }
     }
     
     return true;
 }
 
 /**
  * @brief Compare saved frames between baseline and optimized implementation
  * 
  * @param baseline_dir Directory containing baseline frames
  * @param optimized_dir Directory containing optimized frames
  * @param tolerance Maximum allowed difference between corresponding elements
  * @param max_frames Maximum number of frames to compare (0 for all)
  * @return true if all frames match, false otherwise
  */
 bool compareFrames(const std::string& baseline_dir, 
                   const std::string& optimized_dir,
                   double tolerance = TOLERANCE,
                   int max_frames = 0) {
     
     // Ensure directories exist
     if (!std::filesystem::exists(baseline_dir)) {
         std::cerr << "Baseline directory not found: " << baseline_dir << std::endl;
         return false;
     }
     
     if (!std::filesystem::exists(optimized_dir)) {
         std::cerr << "Optimized directory not found: " << optimized_dir << std::endl;
         return false;
     }
     
     // Get list of frames from baseline directory
     std::vector<std::string> baseline_frames;
     for (const auto& entry : std::filesystem::directory_iterator(baseline_dir)) {
         if (entry.path().extension() == ".txt") {
             baseline_frames.push_back(entry.path().filename().string());
         }
     }
     
     if (baseline_frames.empty()) {
         std::cerr << "No frames found in baseline directory" << std::endl;
         return false;
     }
     
     // Sort frame files to ensure correct order
     std::sort(baseline_frames.begin(), baseline_frames.end());
     
     // Limit number of frames if requested
     if (max_frames > 0 && max_frames < static_cast<int>(baseline_frames.size())) {
         baseline_frames.resize(max_frames);
     }
     
     bool all_match = true;
     int compared_frames = 0;
     int failed_frames = 0;
     
     // Compare each frame
     for (const auto& frame : baseline_frames) {
         std::string baseline_path = baseline_dir + "/" + frame;
         std::string optimized_path = optimized_dir + "/" + frame;
         
         if (!std::filesystem::exists(optimized_path)) {
             std::cerr << "Optimized frame not found: " << optimized_path << std::endl;
             all_match = false;
             failed_frames++;
             continue;
         }
         
         auto baseline_grid = loadGrid(baseline_path);
         auto optimized_grid = loadGrid(optimized_path);
         
         if (!compareGrids(baseline_grid, optimized_grid, tolerance)) {
             std::cerr << "Frame mismatch: " << frame << std::endl;
             all_match = false;
             failed_frames++;
         }
         
         compared_frames++;
     }
     
     std::cout << "Compared " << compared_frames << " frames, "
               << failed_frames << " failed" << std::endl;
               
     return all_match;
 }
 
 /**
  * @brief Calculate checksum for a temperature grid
  * 
  * @param grid Temperature grid
  * @return Checksum value (sum of all elements)
  */
 double calculateChecksum(const std::vector<std::vector<double>>& grid) {
     double sum = 0.0;
     for (const auto& row : grid) {
         for (const auto& val : row) {
             sum += val;
         }
     }
     return sum;
 }
 
 /**
  * @brief Calculate checksum for a file containing a temperature grid
  * 
  * @param filename Input filename
  * @return Checksum value (sum of all elements)
  */
 double calculateFileChecksum(const std::string& filename) {
     auto grid = loadGrid(filename);
     return calculateChecksum(grid);
 }
 
 } // namespace validator
 
 #endif // VALIDATOR_H