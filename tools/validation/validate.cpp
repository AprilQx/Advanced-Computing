/**
 * @file validate.cpp
 * @brief Standalone validation tool for heat diffusion simulation
 * 
 * Compares output files from baseline and optimized implementations
 * to ensure they produce identical results within specified tolerance.
 */

 #include "validator.h"
 #include <iostream>
 #include <string>
 #include <cstdlib>
 #include <cstring>
 #include <vector>
 #include <filesystem>

 #include <vector>
#include <string>
#include <algorithm>  // For std::sort
 
 /**
  * @brief Print usage instructions for the program
  * @param programName Name of the executable
  */
 void printUsage(const char* programName) {
     std::cout << "Usage: " << programName << " [OPTIONS]\n"
               << "Options:\n"
               << "  --help                 Show this help message\n"
               << "  --baseline DIR         Baseline output directory (required)\n"
               << "  --optimized DIR        Optimized output directory (required)\n"
               << "  --tolerance TOL        Tolerance for floating point comparisons (default: 1e-10)\n"
               << "  --max-frames N         Maximum number of frames to compare (default: all)\n"
               << "  --checksum-only        Only compare checksums, not full frames\n"
               << "  --frame FRAME          Compare specific frame (can be used multiple times)\n"
               << std::endl;
 }
 
 /**
  * @brief Calculate checksums for all frames in a directory
  * 
  * @param directory Directory containing frame files
  * @return Vector of checksums for each frame
  */
 std::vector<double> calculateChecksums(const std::string& directory) {
     std::vector<double> checksums;
     std::vector<std::string> files;
     
     // Get all frame files
     for (const auto& entry : std::filesystem::directory_iterator(directory)) {
         if (entry.path().extension() == ".txt") {
             files.push_back(entry.path().filename().string());
         }
     }
     
     // Sort files to ensure consistent order
     std::sort(files.begin(), files.end());
     
     // Calculate checksums
     for (const auto& file : files) {
         std::string path = directory + "/" + file;
         double checksum = validator::calculateFileChecksum(path);
         checksums.push_back(checksum);
         
         std::cout << "Frame " << file << ": checksum = " << checksum << std::endl;
     }
     
     return checksums;
 }
 
 /**
  * @brief Compare checksums between baseline and optimized implementations
  * 
  * @param baselineChecksums Checksums from baseline implementation
  * @param optimizedChecksums Checksums from optimized implementation
  * @param tolerance Maximum allowed difference between corresponding checksums
  * @return true if all checksums match within tolerance, false otherwise
  */
 bool compareChecksums(const std::vector<double>& baselineChecksums,
                      const std::vector<double>& optimizedChecksums,
                      double tolerance) {
     
     if (baselineChecksums.size() != optimizedChecksums.size()) {
         std::cerr << "Number of frames mismatch: " 
                   << baselineChecksums.size() << " vs " 
                   << optimizedChecksums.size() << std::endl;
         return false;
     }
     
     bool all_match = true;
     int compared = 0;
     int failed = 0;
     
     for (size_t i = 0; i < baselineChecksums.size(); ++i) {
         double diff = std::abs(baselineChecksums[i] - optimizedChecksums[i]);
         
         if (diff > tolerance) {
             std::cerr << "Checksum mismatch for frame " << i << ": "
                       << baselineChecksums[i] << " vs " << optimizedChecksums[i]
                       << " (diff: " << diff << ")" << std::endl;
             all_match = false;
             failed++;
         }
         
         compared++;
     }
     
     std::cout << "Compared " << compared << " checksums, "
               << failed << " failed" << std::endl;
               
     return all_match;
 }
 
 /**
  * @brief Main function for validation tool
  * 
  * @param argc Number of command line arguments
  * @param argv Array of command line arguments
  * @return Exit code (0 for success, non-zero for failure)
  */
 int main(int argc, char* argv[]) {
     // Default settings
     std::string baselineDir = "";
     std::string optimizedDir = "";
     double tolerance = validator::TOLERANCE;
     int maxFrames = 0;
     bool checksumOnly = false;
     std::vector<std::string> specificFrames;
     
     // Parse command line arguments
     for (int i = 1; i < argc; i++) {
         std::string arg = argv[i];
         
         if (arg == "--help") {
             printUsage(argv[0]);
             return 0;
         } else if (arg == "--baseline" && i + 1 < argc) {
             baselineDir = argv[++i];
         } else if (arg == "--optimized" && i + 1 < argc) {
             optimizedDir = argv[++i];
         } else if (arg == "--tolerance" && i + 1 < argc) {
             tolerance = std::atof(argv[++i]);
         } else if (arg == "--max-frames" && i + 1 < argc) {
             maxFrames = std::atoi(argv[++i]);
         } else if (arg == "--checksum-only") {
             checksumOnly = true;
         } else if (arg == "--frame" && i + 1 < argc) {
             specificFrames.push_back(argv[++i]);
         } else {
             std::cerr << "Unknown option: " << arg << std::endl;
             printUsage(argv[0]);
             return 1;
         }
     }
     
     // Check required arguments
     if (baselineDir.empty() || optimizedDir.empty()) {
         std::cerr << "Error: Both --baseline and --optimized directories must be specified" << std::endl;
         printUsage(argv[0]);
         return 1;
     }
     
     // Perform validation
     bool success = false;
     
     if (checksumOnly) {
         // Compare checksums only
         std::cout << "Comparing checksums..." << std::endl;
         
         auto baselineChecksums = calculateChecksums(baselineDir);
         auto optimizedChecksums = calculateChecksums(optimizedDir);
         
         success = compareChecksums(baselineChecksums, optimizedChecksums, tolerance);
     } else if (!specificFrames.empty()) {
         // Compare specific frames
         std::cout << "Comparing specific frames..." << std::endl;
         
         success = true;
         for (const auto& frame : specificFrames) {
             std::string baselinePath = baselineDir + "/" + frame;
             std::string optimizedPath = optimizedDir + "/" + frame;
             
             if (!std::filesystem::exists(baselinePath)) {
                 std::cerr << "Baseline frame not found: " << baselinePath << std::endl;
                 success = false;
                 continue;
             }
             
             if (!std::filesystem::exists(optimizedPath)) {
                 std::cerr << "Optimized frame not found: " << optimizedPath << std::endl;
                 success = false;
                 continue;
             }
             
             auto baselineGrid = validator::loadGrid(baselinePath);
             auto optimizedGrid = validator::loadGrid(optimizedPath);
             
             std::cout << "Comparing frame " << frame << "..." << std::endl;
             if (!validator::compareGrids(baselineGrid, optimizedGrid, tolerance)) {
                 success = false;
             }
         }
     } else {
         // Compare all frames
         std::cout << "Comparing all frames..." << std::endl;
         success = validator::compareFrames(baselineDir, optimizedDir, tolerance, maxFrames);
     }
     
     // Report result
     if (success) {
         std::cout << "\nValidation SUCCESSFUL: Results match within tolerance" << std::endl;
         return 0;
     } else {
         std::cerr << "\nValidation FAILED: Results differ" << std::endl;
         return 1;
     }
 }