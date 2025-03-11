/**
 * @file HeatDiffusion.cpp
 * @brief Implementation of the HeatDiffusion class
 */

#include "heat_diffusion.h"
#include <iostream>
#include <fstream>
#include <numeric>
#include <cstdlib>



HeatDiffusion::HeatDiffusion(int w, int h, double rate, bool save) 
    : width(w), height(h), diffusionRate(rate), saveOutput(save) {
    // Initialize grids with ambient temperature (20°C)
    temperature = std::vector<std::vector<double>>(height, std::vector<double>(width, 20.0));
    nextTemperature = temperature;

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


void HeatDiffusion::update() {
    static int frameCount = 0;
    
    // Calculate new temperatures using the heat equation
    for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
            // Discrete Laplacian operator
            double laplacian = 
                temperature[y+1][x] + temperature[y-1][x] + 
                temperature[y][x+1] + temperature[y][x-1] - 
                4 * temperature[y][x];

            nextTemperature[y][x] = temperature[y][x] + diffusionRate * laplacian;
        }
    }

    // Swap buffers
    temperature.swap(nextTemperature);
    
    saveFrame(frameCount);
    frameCount++;
}

double HeatDiffusion::getChecksum() const {
    double sum = 0.0;
    for (const auto& row : temperature) {
        sum += std::accumulate(row.begin(), row.end(), 0.0);
    }
    return sum;
}

void HeatDiffusion::saveFrame(int frameNumber) {
    if (!saveOutput) return;
    
    system("mkdir -p output");
    std::string filename = "output/base/frame_" + std::to_string(frameNumber) + ".txt";
    std::ofstream outFile(filename);
    
    if (outFile.is_open()) {
        for (const auto& row : temperature) {
            for (const auto& temp : row) {
                outFile << temp << " ";
            }
            outFile << "\n";
        }
        outFile.close();
    }
}