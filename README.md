# Heat Diffusion Simulation Project

## Overview
This project implements and optimizes a 2D heat diffusion simulation using the finite difference method. The codebase includes multiple implementations with different parallelization strategies:
   1. Sequential baseline implementation
   2. Optimized implementations (multiple versions)
   3. OpenMP parallelized implementation
   4. MPI parallelized implementation
   5. Hybrid MPI+OpenMP implementation

## Project Structure
The project is organized as follows:

* **src/base**: Baseline implementation
* **src/optimized_v[1-3]**: Optimized sequential implementations
* **src/openmp**: OpenMP-parallelized implementation
* **src/mpi**: MPI-parallelized implementation
* **src/hybrid**: Hybrid MPI+OpenMP implementation
* **include**: Common header files and utility classes
* **benchmark:** Performance benchmarking code
* **tools**: Validation tools and utilities
* **scripts**: Profiling and benchmarking scripts

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


## Profiling Tools Used in the Heat Diffusion Project

Note that we utilised gprof and Valgrind Suite in the docker environment, and utilised Vtune for profiling on csd3.


1. **gprof (GNU Profiler)**
   - Function-level profiling to identify hotspots in sequential code execution.
   - Found in profiling scripts: `comprehensive-profiling-script-*.sh`
   - Output stored in: `profiling_results_*/gprof/`

2. **Valgrind Suite**
    * Cachegrind
         - Cache usage analysis to identify memory access patterns and cache misses.
        - Output stored in:  `profiling_results_*/valgrind/cachegrind_*`
    * Callgrind
        - Call graph generation and execution profiling.
        - Output in: `profiling_results_*/valgrind/callgrind_*`
    * Massif
        - Heap profiling to analyze memory usage over time.
        - Output in profiling_results_*/valgrind/massif_*

3. **VTune (Intel)**
   - Advanced performance profiling for Intel processors.
   - Output in: `profiling_results_*_csd3/vtune/`
   
4. **Custom Timing Benchmarking**
   * Comprehensive performance measurements across implementations
   * Test configuration:
     * Grid size: 1000×1000 (or `1000×1000`)
     * Iterations: 1000
     * Sample size: 10 runs
   * Metrics collected:
     * Average setup time
     * Average total runtime for 1000 iterations
     * Average time per iteration
   * Platform-specific measurements:
     * Memory usage tracking for Apple ARM-based architectures
     
5. **MPI-Specific Profiling**
   * Purpose: Analyze MPI communication patterns and scaling
   * Usage in the project:
     * Scripts: `comprehensive-profiling-script-mpi.sh`
     * Output in: `profiling_results_mpi/communication/` and `profiling_results_mpi/scaling/`
   * Analysis includes:
     * Strong scaling tests (fixed problem size)
     * Weak scaling tests (problem size scales with process count)
     * Communication patterns with different grid sizes

6. **OpenMP-Specific Profiling**
   * Purpose: Thread scaling and behavior analysis
   * Usage in the project:
     * Scripts: `comprehensive-profiling-script-openmp.sh`
     * Output in: `profiling_results_omp/thread_scaling/` and `profiling_results_omp/affinity/`
   * Analysis includes:
     * Thread scaling tests
     * Thread affinity impacts
     * Scheduling strategy comparisons

7. **Block Size Optimizer**
   * Purpose: Custom tool to find optimal cache block sizes
   * Usage in the project:
     * Source: `tools/block_size_optimizer.cpp`
     * Script: `scripts/block_size_optimizer.sh`

## 

