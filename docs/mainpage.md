# Heat Diffusion Simulation Project

## Overview
This project implements and optimizes a 2D heat diffusion simulation using the finite difference method. The codebase includes multiple implementations with different parallelization strategies:
   1. Sequential baseline implementation
   2. Optimized implementations (multiple versions)
   3. OpenMP parallelized implementation
   4. MPI parallelized implementation
   5. Hybrid MPI+OpenMP implementation

## Heat Diffusion Theory
The heat diffusion equation, also known as the heat equation, is a partial differential equation that describes how temperature changes over time in a solid medium:

 $$ \frac{\partial T}{\partial t} = \alpha \nabla^2 T  $$

where:
*  T  is the temperature
* t is time
* $ \alpha $ is the thermal diffusivity coefficient
* $\nabla^2 $ is the Laplacian operator

In 2D, the discrete form of this equation using the finite difference method is:

$$ T_{i,j}^{n+1} = T_{i,j}^n + \alpha \cdot (T_{i+1,j}^n + T_{i-1,j}^n + T_{i,j+1}^n + T_{i,j-1}^n - 4 \cdot T_{i,j}^n) $$

## Project Structure
The project is organized as follows:

* src/base: Baseline implementation
* src/optimized_v[1-3]: Optimized sequential implementations
* src/openmp: OpenMP-parallelized implementation
* src/mpi: MPI-parallelized implementation
* src/hybrid: Hybrid MPI+OpenMP implementation
* include: Common header files and utility classes
* benchmark: Performance benchmarking code
* tools: Validation tools and utilities
* scripts: Profiling and benchmarking scripts

## Implementation Approaches

### Baseline Implementation
The baseline implementation uses a straightforward approach with vectors of vectors to represent the temperature grid and implements the heat equation using nested loops.

### Optimized Implementations
The optimized versions improve on the baseline with:

* Memory layout optimizations
* Data Sturcture (Flat 2D Array)
* Cache-efficient data access patterns
* Loop optimization techniques

### OpenMP Implementation
The OpenMP implementation uses shared-memory parallelism to distribute the computation across multiple threads on a single node.

### MPI Implementation
The MPI implementation uses distributed-memory parallelism with domain decomposition to distribute the computation across multiple processes, which can run on different nodes.

### Hybrid Implementation

The hybrid implementation combines MPI and OpenMP to leverage both distributed and shared memory parallelism:

- MPI handles communication between different nodes or compute units
- OpenMP manages parallelism within each node using multiple threads

This approach is particularly well-suited for modern HPC architectures that feature compute nodes with multiple CPU cores. The hybrid model allows us to:

- Use MPI for coarse-grained parallelism across nodes
- Use OpenMP for fine-grained parallelism within nodes

