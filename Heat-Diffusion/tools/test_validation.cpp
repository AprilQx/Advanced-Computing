/**
 * @file test_validation.cpp
 * @brief Test program for the validation system
 * 
 * This program generates test data to verify that the validator
 * correctly identifies matching and non-matching simulation results.
 */

 #include <iostream>
 #include <fstream>
 #include <filesystem>
 #include <string>
 #include <vector>
 #include <cmath>
 #include <random>
 #include <cstdlib>
 
 /**
  * @brief Generate simulated heat diffusion output files
  * 
  * @param directory Output directory
  * @param width Grid width
  * @param height Grid height
  * @param frameCount Number of frames to generate
  * @param addError If true, introduces errors in the data
  * @param errorMagnitude Scale of errors to introduce
  */
 void generateTestData(const std::string& directory, 
                       int width, 
                       int height, 
                       int frameCount,
                       bool addError = false,
                       double errorMagnitude = 0.0) {
     
     // Create directory if it doesn't exist
     std::filesystem::create_directories(directory);
     
     // Random number generator for errors
     std::random_device rd;
     std::mt19937 gen(rd());
     std::uniform_real_distribution<> errorDist(-errorMagnitude, errorMagnitude);
     
     // Generate frames
     for (int frame = 0; frame < frameCount; ++frame) {
         std::string filename = directory + "/frame_" + std::to_string(frame) + ".txt";
         std::ofstream outFile(filename);
         
         if (!outFile.is_open()) {
             std::cerr << "Failed to create file: " << filename << std::endl;
             continue;
         }
         
         // Generate a simple heat pattern
         for (int y = 0; y < height; ++y) {
             for (int x = 0; x < width; ++x) {
                 // Create a pattern that changes over frames
                 double centerX = width / 2.0;
                 double centerY = height / 2.0;
                 double distance = std::sqrt(std::pow(x - centerX, 2) + std::pow(y - centerY, 2));
                 double decay = std::exp(-distance / 10.0);
                 double value = 20.0 + 80.0 * decay * std::exp(-frame / 20.0);
                 
                 // Add error if requested
                 if (addError) {
                     // Only add errors to some cells to make them detectable
                     if (x % 5 == 0 && y % 5 == 0) {
                         value += errorDist(gen);
                     }
                 }
                 
                 outFile << value << " ";
             }
             outFile << std::endl;
         }
         
         outFile.close();
     }
 }
 
 /**
  * @brief Main function
  */
 int main(int argc, char* argv[]) {
     // Default settings
     int width = 50;
     int height = 50;
     int frameCount = 5;
     std::string baseDir = "validation_test_base";
     std::string matchingDir = "validation_test_match";
     std::string nonMatchingDir = "validation_test_error";
     double errorMagnitude = 1e-6;  // Small error
     
     // Parse command-line arguments
     for (int i = 1; i < argc; i++) {
         std::string arg = argv[i];
         
         if (arg == "--width" && i + 1 < argc) {
             width = std::atoi(argv[++i]);
         } else if (arg == "--height" && i + 1 < argc) {
             height = std::atoi(argv[++i]);
         } else if (arg == "--frames" && i + 1 < argc) {
             frameCount = std::atoi(argv[++i]);
         } else if (arg == "--error" && i + 1 < argc) {
             errorMagnitude = std::atof(argv[++i]);
         }
     }
     
     // Generate the test data
     std::cout << "Generating test data..." << std::endl;
     std::cout << "Grid size: " << width << "x" << height << ", Frames: " << frameCount << std::endl;
     
     // Base data
     generateTestData(baseDir, width, height, frameCount);
     
     // Matching data (identical to base)
     generateTestData(matchingDir, width, height, frameCount);
     
     // Non-matching data (with errors)
     generateTestData(nonMatchingDir, width, height, frameCount, true, errorMagnitude);
     
     std::cout << "Test data generated." << std::endl;
     
     // Run validation tests
     std::cout << "\nTesting validation with matching data (should PASS):" << std::endl;
     std::string matchCmd = "./validate --baseline " + baseDir + " --optimized " + matchingDir;
     int matchResult = std::system(matchCmd.c_str());
     
     std::cout << "\nTesting validation with non-matching data (should FAIL):" << std::endl;
     std::string errorCmd = "./validate --baseline " + baseDir + " --optimized " + nonMatchingDir;
     int errorResult = std::system(errorCmd.c_str());
     
     // Report results
     std::cout << "\nValidation Test Results:" << std::endl;
     std::cout << "Matching data test: " << (matchResult == 0 ? "PASSED" : "FAILED") << std::endl;
     std::cout << "Non-matching data test: " << (errorResult != 0 ? "PASSED" : "FAILED") << std::endl;
     
     // Clean up
     if (matchResult == 0 && errorResult != 0) {
         std::cout << "\nAll validation tests passed!" << std::endl;
         
         // Clean up test directories
         std::filesystem::remove_all(baseDir);
         std::filesystem::remove_all(matchingDir);
         std::filesystem::remove_all(nonMatchingDir);
         
         return 0;
     } else {
         std::cerr << "\nValidation tests failed!" << std::endl;
         return 1;
     }
 }