/**
 * @file optimized_heat_diffusion_mpi.cpp
 * @brief Implementation of the MPI-parallelized heat diffusion simulation using Flat2D
 */

 #include "optimized_heat_diffusion_mpi.h"
 #include <iostream>
 #include <fstream>
 #include <cstdlib>
 #include <algorithm>
 #include <cmath>
 #include <mpi.h>
 #include <limits>
 
 OptimizedHeatDiffusionMPI::OptimizedHeatDiffusionMPI(int w, int h, double rate, bool save) 
     : globalWidth(w), globalHeight(h), diffusionRate(rate), saveOutput(save), frameCount(0), 
       temperature(1, 1), nextTemperature(1, 1) { // Temporary initialization, will be properly sized in initMPI
     
     // Initialize MPI
     MPI_Comm_rank(MPI_COMM_WORLD, &rank);
     MPI_Comm_size(MPI_COMM_WORLD, &worldSize);
     
     // Setup domain decomposition
     initMPI();
     
     // Re-instantiate the arrays with correct size (including ghost cells)
     temperature = Array_2D<double>(localHeight+2, localWidth+2);
     nextTemperature = Array_2D<double>(localHeight+2, localWidth+2);
     
     // Initialize all cells with ambient temperature (20°C)
     temperature.fill(20.0);
     nextTemperature.fill(20.0);
     
     // Set up initial conditions - hot spot in the middle of the global domain
     int centerX = globalWidth / 2;
     int centerY = globalHeight / 2;
     
     // Check if this process's domain contains any part of the hot spot
     for (int localY = 0; localY < localHeight; localY++) {
         int globalY = startRow + localY;
         for (int localX = 0; localX < localWidth; localX++) {
             int globalX = startCol + localX;
             
             // Check if this cell is part of the hot spot (radius of 3)
             if (std::abs(globalY - centerY) <= 3 && std::abs(globalX - centerX) <= 3) {
                 temperature(localY+1, localX+1) = 100.0;
             }
         }
     }
 
     if (saveOutput) {
         saveFrame(0);
     }
      
     // Initial halo exchange to ensure all processes have consistent boundary data
     exchangeHalos();
 }
 
 OptimizedHeatDiffusionMPI::~OptimizedHeatDiffusionMPI() {
     // Check if MPI is still initialized before freeing MPI resources
     int finalized;
     MPI_Finalized(&finalized);
     if (!finalized) {
         // Only free MPI resources if MPI hasn't been finalized yet
         MPI_Type_free(&haloRowType);
         MPI_Type_free(&haloColType);
         
         // Free the Cartesian communicator if it's not MPI_COMM_WORLD
         if (cartComm != MPI_COMM_WORLD) {
             MPI_Comm_free(&cartComm);
         }
     }
 }
 
 void OptimizedHeatDiffusionMPI::initMPI() {
     // Create a 2D Cartesian process grid
     dims[0] = dims[1] = 0;  // Let MPI decide the dimensions
     MPI_Dims_create(worldSize, 2, dims);
     
     if (rank == 0) {
         std::cout << "Creating a " << dims[0] << "x" << dims[1] 
                 << " process grid for " << worldSize << " processes" << std::endl;
     }
     
     // Create the Cartesian communicator
     int periods[2] = {0, 0};  // Non-periodic boundaries
     MPI_Cart_create(MPI_COMM_WORLD, 2, dims, periods, 1, &cartComm);
     
     // Get coordinates in the Cartesian grid
     int coords[2];
     MPI_Cart_coords(cartComm, rank, 2, coords);
     
     // Calculate local domain size (divide the global domain among processes)
     localHeight = globalHeight / dims[0];
     localWidth = globalWidth / dims[1];
     
     // Handle remainder for non-divisible domain sizes (last row/column gets extras)
     if (coords[0] == dims[0] - 1) {
         localHeight += globalHeight % dims[0];
     }
     if (coords[1] == dims[1] - 1) {
         localWidth += globalWidth % dims[1];
     }
     
     // Calculate global starting indices
     startRow = coords[0] * (globalHeight / dims[0]);
     startCol = coords[1] * (globalWidth / dims[1]);
     
     // Get neighbor ranks (MPI_PROC_NULL is automatically assigned for boundary processes)
     MPI_Cart_shift(cartComm, 0, 1, &neighbors[0], &neighbors[2]);  // North and South
     MPI_Cart_shift(cartComm, 1, 1, &neighbors[3], &neighbors[1]);  // West and East
 
     // For row exchange (horizontal halos)
     MPI_Type_contiguous(localWidth, MPI_DOUBLE, &haloRowType);
     MPI_Type_commit(&haloRowType);
     
     // For column exchange (vertical halos)
     MPI_Type_vector(localHeight, 1, localWidth+2, MPI_DOUBLE, &haloColType);
     MPI_Type_commit(&haloColType);
     
     if (rank == 0) {
         std::cout << "Domain decomposition: Global size = " << globalWidth << "x" << globalHeight 
                 << ", Process grid = " << dims[0] << "x" << dims[1] << std::endl;
     }
     
     MPI_Barrier(cartComm);
     std::cout << "Rank " << rank << " has local domain size " << localWidth << "x" << localHeight 
             << " starting at global position (" << startCol << "," << startRow << ")" << std::endl;
     std::cout << "Rank " << rank << " neighbors: N=" << neighbors[0] << ", E=" << neighbors[1]
             << ", S=" << neighbors[2] << ", W=" << neighbors[3] << std::endl;
 }
 
 void OptimizedHeatDiffusionMPI::exchangeHalos() {
     MPI_Request requests[8];
     int reqCount = 0;
     
     // Send to north, receive from south
     // MPI_PROC_NULL will be automatically ignored for boundary processes
     MPI_Isend(&temperature(1, 1), 1, haloRowType, 
              neighbors[0], 0, cartComm, &requests[reqCount++]);
     MPI_Irecv(&temperature(localHeight+1, 1), 1, haloRowType, 
              neighbors[2], 0, cartComm, &requests[reqCount++]);
     
     // Send to south, receive from north
     MPI_Isend(&temperature(localHeight, 1), 1, haloRowType, 
              neighbors[2], 1, cartComm, &requests[reqCount++]);
     MPI_Irecv(&temperature(0, 1), 1, haloRowType, 
              neighbors[0], 1, cartComm, &requests[reqCount++]);
     
     // Send to east, receive from west
     MPI_Isend(&temperature(1, localWidth), 1, haloColType, 
              neighbors[1], 2, cartComm, &requests[reqCount++]);
     MPI_Irecv(&temperature(1, 0), 1, haloColType, 
              neighbors[3], 2, cartComm, &requests[reqCount++]);
     
     // Send to west, receive from east
     MPI_Isend(&temperature(1, 1), 1, haloColType, 
              neighbors[3], 3, cartComm, &requests[reqCount++]);
     MPI_Irecv(&temperature(1, localWidth+1), 1, haloColType, 
              neighbors[1], 3, cartComm, &requests[reqCount++]);
     
     // Wait for all communications to complete
     MPI_Waitall(reqCount, requests, MPI_STATUSES_IGNORE);
 }
 
 void OptimizedHeatDiffusionMPI::update() {
     // Exchange halos to get boundary data from neighboring processes
     exchangeHalos();
     
     // Calculate new temperatures using the heat equation with optimized memory access
     // Skip the ghost cells in the calculation (but use them)
     for (int y = 0; y < localHeight; y++) {
         for (int x = 0; x < localWidth; x++) {
             // Discrete Laplacian operator with Flat2D array indexing including ghost cells
             const double laplacian = 
                 temperature(y, x+1) +         // Top (y-1+1, x+1)
                 temperature(y+2, x+1) +       // Bottom (y+1+1, x+1)
                 temperature(y+1, x+2) +       // Right (y+1, x+1+1)
                 temperature(y+1, x) -         // Left (y+1, x-1+1)
                 4.0 * temperature(y+1, x+1);  // Center (y+1, x+1) (4x)
             
             // Update the cell in the next timestep buffer
             nextTemperature(y+1, x+1) = temperature(y+1, x+1) + diffusionRate * laplacian;
         }
     }
 
     // Swap buffers
     temperature.swap(nextTemperature);
     
     if (saveOutput) {
         saveFrame(frameCount);
        if (frameCount % 10 == 0) {
            saveHaloVisualization(frameCount / 10);
        }
     }
     frameCount++;
 }
 
 double OptimizedHeatDiffusionMPI::getChecksum() {
     // Calculate local sum first
     double localSum = 0.0;
     
     for (int y = 0; y < localHeight; y++) {
         for (int x = 0; x < localWidth; x++) {
             localSum += temperature(y+1, x+1);
         }
     }
     
     // Reduce to get global sum
     double globalSum = 0.0;
     MPI_Allreduce(&localSum, &globalSum, 1, MPI_DOUBLE, MPI_SUM, cartComm);
     
     return globalSum;
 }
 
 void OptimizedHeatDiffusionMPI::gatherGrid(double* gatheredData) {
     // Create an array to receive counts from each process (only needed on rank 0)
     int* recvcounts = nullptr;
     int* displs = nullptr;
     
     if (rank == 0) {
         recvcounts = new int[worldSize];
         displs = new int[worldSize];
     }
     
     // Determine how many elements to receive from each process
     int localElements = localWidth * localHeight;
     MPI_Gather(&localElements, 1, MPI_INT, recvcounts, 1, MPI_INT, 0, cartComm);
     
     // Calculate displacements for gathered data (only on rank 0)
     if (rank == 0) {
         displs[0] = 0;
         for (int i = 1; i < worldSize; i++) {
             displs[i] = displs[i-1] + recvcounts[i-1];
         }
     }
     
     // Pack local data into a contiguous buffer (excluding ghost cells)
     double* sendBuffer = new double[localWidth * localHeight];
     int idx = 0;
     for (int y = 0; y < localHeight; y++) {
         for (int x = 0; x < localWidth; x++) {
             sendBuffer[idx++] = temperature(y+1, x+1);
         }
     }
     
     // Gather all data to rank 0
     MPI_Gatherv(sendBuffer, localWidth * localHeight, MPI_DOUBLE,
                gatheredData, recvcounts, displs, MPI_DOUBLE, 0, cartComm);
     
     // Clean up
     delete[] sendBuffer;
     if (rank == 0) {
         delete[] recvcounts;
         delete[] displs;
     }
 }
 
 void OptimizedHeatDiffusionMPI::saveFrame(int frameNumber) {
     if (!saveOutput) return;
     
     // Allocate buffer for full grid on rank 0
     double* fullGrid = nullptr;
     if (rank == 0) {
         fullGrid = new double[globalWidth * globalHeight];
     }
     
     // Gather the local grids to rank 0
     gatherGrid(fullGrid);
     
     // Only rank 0 writes to file
     if (rank == 0) {
         system("mkdir -p output/mpi");
         std::string filename = "output/mpi/frame_" + std::to_string(frameNumber) + ".txt";
         std::ofstream outFile(filename);
         
         if (outFile.is_open()) {
             // Reorder the data for output (due to domain decomposition)
             double* orderedGrid = new double[globalWidth * globalHeight];
             std::fill_n(orderedGrid, globalWidth * globalHeight, 0.0);
             
             // Reconstruct the full grid with proper ordering of data
             for (int p = 0; p < worldSize; p++) {
                 // Get coordinates of this process
                 int coords[2];
                 MPI_Cart_coords(cartComm, p, 2, coords);
                 
                 // Calculate domain information for this process
                 int pStartRow = coords[0] * (globalHeight / dims[0]);
                 int pStartCol = coords[1] * (globalWidth / dims[1]);
                 int pHeight = globalHeight / dims[0];
                 int pWidth = globalWidth / dims[1];
                 
                 // Adjust for remainder
                 if (coords[0] == dims[0] - 1) pHeight += globalHeight % dims[0];
                 if (coords[1] == dims[1] - 1) pWidth += globalWidth % dims[1];
                 
                 // Calculate starting index in the gathered data
                 int dataIdx = 0;
                 for (int i = 0; i < p; i++) {
                     int icoords[2];
                     MPI_Cart_coords(cartComm, i, 2, icoords);
                     
                     int iHeight = globalHeight / dims[0];
                     int iWidth = globalWidth / dims[1];
                     
                     if (icoords[0] == dims[0] - 1) iHeight += globalHeight % dims[0];
                     if (icoords[1] == dims[1] - 1) iWidth += globalWidth % dims[1];
                     
                     dataIdx += iHeight * iWidth;
                 }
                 
                 // Copy this process's data to the ordered grid
                 for (int y = 0; y < pHeight; y++) {
                     for (int x = 0; x < pWidth; x++) {
                         int globalIdx = (pStartRow + y) * globalWidth + (pStartCol + x);
                         orderedGrid[globalIdx] = fullGrid[dataIdx++];
                     }
                 }
             }
             
             // Write the ordered grid to file
             for (int y = 0; y < globalHeight; y++) {
                 for (int x = 0; x < globalWidth; x++) {
                     outFile << orderedGrid[y * globalWidth + x] << " ";
                 }
                 outFile << "\n";
             }
             
             outFile.close();
             delete[] orderedGrid;
         }
         
         delete[] fullGrid;
     }
 }

 void OptimizedHeatDiffusionMPI::saveHaloVisualization(int frameNumber) {
    if (!saveOutput) return;
    
    // Create directory for halo visualization
    if (rank == 0) {
        system("mkdir -p output/mpi_halos");
    }
    MPI_Barrier(cartComm);
    
    // Each process saves its own local domain with halos
    std::string filename = "output/mpi_halos/rank_" + std::to_string(rank) + 
                           "_frame_" + std::to_string(frameNumber) + ".txt";
    std::ofstream outFile(filename);
    
    if (outFile.is_open()) {
        // Write local grid dimensions and global position
        outFile << "# Rank: " << rank << ", Position: (" << startCol << "," << startRow 
                << "), Size: " << localWidth << "x" << localHeight << std::endl;
        outFile << "# Domain with halos: " << (localWidth+2) << "x" << (localHeight+2) << std::endl;
        outFile << "# Neighbors: N=" << neighbors[0] << ", E=" << neighbors[1] 
                << ", S=" << neighbors[2] << ", W=" << neighbors[3] << std::endl;
        outFile << "# Format: 'h' marks halo cells, numbers are temperature values" << std::endl;
        
        // Write the entire local grid including halos
        for (int y = 0; y < localHeight + 2; y++) {
            for (int x = 0; x < localWidth + 2; x++) {
                // Mark halo cells with 'h' prefix
                bool isHalo = (y == 0 || y == localHeight + 1 || 
                               x == 0 || x == localWidth + 1);
                
                if (isHalo) {
                    outFile << "h" << temperature(y, x) << " ";
                } else {
                    outFile << temperature(y, x) << " ";
                }
            }
            outFile << std::endl;
        }
        outFile.close();
    }
    
    // Now also create a consolidated visualization on rank 0
    if (rank == 0) {
        // Allocate buffer for full grid
        double* fullGrid = new double[globalWidth * globalHeight];
        
        // Gather the local grids to rank 0 (reusing existing method)
        gatherGrid(fullGrid);
        
        // Create a visualization that shows the domain decomposition
        std::string fullFilename = "output/mpi_halos/full_decomposition_frame_" + 
                                   std::to_string(frameNumber) + ".txt";
        std::ofstream fullFile(fullFilename);
        
        if (fullFile.is_open()) {
            // Write header information
            fullFile << "# Heat diffusion at frame " << frameNumber << std::endl;
            fullFile << "# Domain decomposition: " << dims[0] << "x" << dims[1] << " process grid" << std::endl;
            fullFile << "# Global size: " << globalWidth << "x" << globalHeight << std::endl;
            fullFile << "# Process boundaries are marked with | and --- characters" << std::endl;
            
            // Create a visualization with process boundaries
            for (int y = 0; y < globalHeight; y++) {
                // Check if this is a process boundary row
                bool isBoundaryRow = false;
                for (int p = 1; p < dims[0]; p++) {
                    if (y == p * (globalHeight / dims[0])) {
                        isBoundaryRow = true;
                        break;
                    }
                }
                
                // If it's a boundary row, draw a line
                if (isBoundaryRow) {
                    for (int x = 0; x < globalWidth; x++) {
                        fullFile << "--- ";
                    }
                    fullFile << std::endl;
                }
                
                // Write the data row
                for (int x = 0; x < globalWidth; x++) {
                    // Check if this is a process boundary column
                    bool isBoundaryCol = false;
                    for (int p = 1; p < dims[1]; p++) {
                        if (x == p * (globalWidth / dims[1])) {
                            isBoundaryCol = true;
                            break;
                        }
                    }
                    
                    // If it's a boundary column, mark it
                    if (isBoundaryCol) {
                        fullFile << "| ";
                    }
                    
                    // Write the temperature value
                    fullFile << fullGrid[y * globalWidth + x] << " ";
                }
                fullFile << std::endl;
            }
            
            fullFile.close();
        }
        
        delete[] fullGrid;
    }
}