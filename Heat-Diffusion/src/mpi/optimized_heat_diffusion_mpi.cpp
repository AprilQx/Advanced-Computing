/**
 * @file optimized_heat_diffusion_mpi.cpp
 * @brief Implementation of the MPI-parallelized heat diffusion simulation
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
     : globalWidth(w), globalHeight(h), diffusionRate(rate), saveOutput(save), frameCount(0) {
     
     // Initialize MPI
     MPI_Comm_rank(MPI_COMM_WORLD, &rank);
     MPI_Comm_size(MPI_COMM_WORLD, &worldSize);
     
     // Setup domain decomposition
     initMPI();
     
     // Allocate flat arrays for temperature grids (including ghost cells)
     temperature = new double[(localWidth+2) * (localHeight+2)];
     nextTemperature = new double[(localWidth+2) * (localHeight+2)];
     
     // Initialize all cells with ambient temperature (20°C)
    std::fill_n(temperature, (localWidth+2) * (localHeight+2), 20.0);
    std::fill_n(nextTemperature, (localWidth+2) * (localHeight+2), 20.0);
     
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
                 temperature[idx(localY, localX)] = 100.0;
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
    // Free allocated memory
    delete[] temperature;
    delete[] nextTemperature;
    
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
     // Try to find a good decomposition (as square as possible)
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
     
     // Create derived datatypes for halo exchange
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
     MPI_Isend(&temperature[idx(0, 0)], 1, haloRowType, 
              neighbors[0], 0, cartComm, &requests[reqCount++]);
     MPI_Irecv(&temperature[idx(localHeight, 0)], 1, haloRowType, 
              neighbors[2], 0, cartComm, &requests[reqCount++]);
     
     // Send to south, receive from north
     MPI_Isend(&temperature[idx(localHeight-1, 0)], 1, haloRowType, 
              neighbors[2], 1, cartComm, &requests[reqCount++]);
     MPI_Irecv(&temperature[idx(-1, 0)], 1, haloRowType, 
              neighbors[0], 1, cartComm, &requests[reqCount++]);
     
     // Send to east, receive from west
     MPI_Isend(&temperature[idx(0, localWidth-1)], 1, haloColType, 
              neighbors[1], 2, cartComm, &requests[reqCount++]);
     MPI_Irecv(&temperature[idx(0, -1)], 1, haloColType, 
              neighbors[3], 2, cartComm, &requests[reqCount++]);
     
     // Send to west, receive from east
     MPI_Isend(&temperature[idx(0, 0)], 1, haloColType, 
              neighbors[3], 3, cartComm, &requests[reqCount++]);
     MPI_Irecv(&temperature[idx(0, localWidth)], 1, haloColType, 
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
             // Discrete Laplacian operator with flattened array indexing including ghost cells
             const double laplacian = 
                 temperature[idx(y-1, x)] +      // Top
                 temperature[idx(y+1, x)] +      // Bottom
                 temperature[idx(y, x+1)] +      // Right
                 temperature[idx(y, x-1)] -      // Left
                 4.0 * temperature[idx(y, x)];   // Center (4x)
             
             // Update the cell in the next timestep buffer
             nextTemperature[idx(y, x)] = temperature[idx(y, x)] + diffusionRate * laplacian;
         }
     }
 
     // Swap buffers using pointer swap (very fast)
     std::swap(temperature, nextTemperature);
     
     if (saveOutput) {
        saveFrame(frameCount);
    }
     frameCount++;
 }
 
 

 double OptimizedHeatDiffusionMPI::getChecksum() {
    // Calculate local sum first
    double localSum = 0.0;
    
    for (int y = 0; y < localHeight; y++) {
        for (int x = 0; x < localWidth; x++) {
            localSum += temperature[idx(y, x)];
        }
    }
    
    // Reduce to get global sum
    double globalSum = 0.0;
    MPI_Allreduce(&localSum, &globalSum, 1, MPI_DOUBLE, MPI_SUM, cartComm);
    
    return globalSum;
}
 
 void OptimizedHeatDiffusionMPI::gatherGrid(double* localData, double* gatheredData) {
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
             sendBuffer[idx++] = localData[this->idx(y, x)];
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
     gatherGrid(temperature, fullGrid);
     
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