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
* **.gitignore**: Configuration file for Git to exclude build artifacts, temporary files, and IDE-specific files from version control
* **Doxyfile**: Doxygen configuration file for automatic code documentation generation from source comments
* **Dockerfile**: Container definition for consistent development and profiling environment across platforms
* **CMakelists.txt**: Main build system configuration file defining compilation targets, dependencies, and platform-specific settings
* **Results** Obtained experimental results.

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
The OpenMP implementation uses shared-memory parallelism to distribute the computation across multiple threads on a single node. Highly recommend to use non-mac systems for reproducibilities.

### MPI Implementation
The MPI implementation uses distributed-memory parallelism with domain decomposition to distribute the computation across multiple processes, which can run on different nodes.

### Hybrid Implementation

The hybrid implementation combines MPI and OpenMP to leverage both distributed and shared memory parallelism:

- MPI handles communication between different nodes or compute units
- OpenMP manages parallelism within each node using multiple threads

This approach is particularly well-suited for modern HPC architectures that feature compute nodes with multiple CPU cores. The hybrid model allows us to:

- Use MPI for coarse-grained parallelism across nodes
- Use OpenMP for fine-grained parallelism within nodes


## Building the Project

### Prerequisites

* C++ compiler with C++17 support (g++ 8.0+, clang 7.0+ or equivalent)
* CMake 3.15 or higher
* OpenMP support (included in most modern compilers)
* MPI implementation (OpenMPI, Intel MPI, or MPICH)
* LibOMP for Mac system for implementation of openmp (Highly recommend to use the docker file/csd3 scripts provided to test and deploy)

### Build Instructions
```bash
# Create build directory
mkdir build && cd build

# Configure build
cmake ..

#If we wish to make all
make

#Or
# Build specific targets
make heat_diffusion          # Build baseline version
make heat_diffusion_optimized_v1 # Build optimized version using flat array
make heat_diffusion_optimized_v2 # Build optimized version using flat 2D array
make heat_diffusion_optimized_v3 # Build optimized version using flat 2D array with cache blocking
make heat_diffusion_openmp   # Build OpenMP version 
make heat_diffusion_mpi    # Build MPI version
make heat_diffusion_hybrid   # Build hybrid version

#benchmark
make heat_diffusion_benchmark
make heat_diffusion_optimized_benchmark_v1
make heat_diffusion_optimized_benchmark_v2
make heat_diffusion_optimized_benchmark_v3
make heat_diffusion_openmp_benchmark
make heat_diffusion_mpi_benchmark
make heat_diffusion_benchmark_hybrid

#utilities
make validate #validate the accuracy between two approach
make block_size_optimizer
```
### CMake Build System

The project uses CMake as its build system, which provides a platform-independent way to configure and build the project. Here's an overview of how the CMakeLists.txt is structured:

**Platform Detection**

* Automatically detects and configures for different platforms: macOS, Linux, and CSD3
* Sets up appropriate compiler flags and library paths based on the detected platform
* Special handling for OpenMP on macOS (which requires additional setup)
* Automatic detection of CSD3 environment to optimize builds for the HPC system

**Compiler Configuration**

Sets C++17 as the required standard for all builds
Configures compiler flags for different build types:

* Base flags (-O3) for all builds
* Development flags (-g) for builds with debugging information
* Benchmark flags (optimized for performance testing)

**Build Targets**

The CMakeLists.txt defines the following main build targets:

*Base implementation:*
* `heat_diffusion`: Original implementation
* `heat_diffusion_benchmark`: Benchmark version of base implementation

*Optimized sequential implementations:*
* `heat_diffusion_optimized_v1`, `heat_diffusion_optimized_v2`, `heat_diffusion_optimized_v3`: Progressive optimization versions
* Corresponding benchmark versions: `heat_diffusion_optimized_benchmark_v1`, etc.

*Parallel implementations:*
* `heat_diffusion_openmp`: OpenMP parallelized version
* `heat_diffusion_mpi`: MPI parallelized version
* `heat_diffusion_hybrid`: Hybrid MPI+OpenMP implementation
* Corresponding benchmark versions

*Validation tools:*
* `validate`: Tool for validating optimization correctness
* `test_validation`: Test suite for the validation tool
* `block_size_optimizer`: Tool for finding optimal cache block sizes

**Special Handling for macOS**

The project includes special configuration for macOS, which requires additional setup for certain libraries:

*OpenMP on macOS:*
* Detects LibOMP installed via Homebrew (typically at `/opt/homebrew/Cellar/libomp/`)
* Sets custom compiler flags `-Xpreprocessor -fopenmp` required for Clang on macOS
* Sets include paths and library paths manually since macOS Clang doesn't natively support OpenMP

*MPI on macOS:*
* Forces the use of `mpicxx` compiler wrapper for MPI code
* Detects Open MPI installation (common on macOS via Homebrew/MacPorts)
* Adds macOS-specific MPI flags if needed

## 📣 Running Heat Diffusion Simulation
After successful compilation, you can run the different versions of the heat diffusion simulation with various command-line options. Below are instructions for running each implementation.


### Command Line Options for Non-benchmarks
All non-benchmark implementations support these basic options:

```
  --help                 Show help message
  --width WIDTH          Set grid width (default: 100)
  --height HEIGHT        Set grid height (default: 100)
  --rate RATE            Set diffusion rate (default: 0.1)
  --frames FRAMES        Set number of frames to simulate (default: 100)
  --output               Enable output file generation
  --output-dir DIR       Directory for output files
```
### Running the Baseline Implementation
```
./build/heat_diffusion [OPTIONS]
```
Example:
```
./build/heat_diffusion --width 500 --height 500 --frames 1000 --output
```

### Running the Optimized Implementations
```
./build/heat_diffusion_optimized_v1 [OPTIONS]  # Flat array version
./build/heat_diffusion_optimized_v2 [OPTIONS]  # Flat 2D array version
./build/heat_diffusion_optimized_v3 [OPTIONS]  # Cache blocked version
```
### Running the OpenMP Implementation
```
./build/heat_diffusion_openmp [OPTIONS] [--threads NUM_THREADS]
```
The --threads option sets the number of OpenMP threads to use.

### Running the MPI Implementation
```
mpirun -n NUM_PROCESSES ./build/heat_diffusion_mpi [OPTIONS]
```

### Running the Hybrid MPI+OpenMP Implementation
```
mpirun -np NUM_PROCESSES ./build/heat_diffusion_hybrid [OPTIONS] [--threads NUM_THREADS]
```

Example:
```
# Run with 4 MPI processes, each using 4 OpenMP threads
export OMP_NUM_THREADS=4
mpirun -np 4 ./build/heat_diffusion_hybrid --width 2000 --height 2000
```

## 📣 Using Validation and Optimization Tools
In addition to the simulation implementations, the project includes specialized utilities for validation and performance optimization.
### Validation Tool
The validate utility compares the outputs of different implementations to ensure they produce consistent results within acceptable numerical precision

**Validation Tool Actual Usage**
```
# Basic usage
./build/validate --baseline DIR1 --optimized DIR2

# Example: Compare outputs from two different runs
./build/validate --baseline output/base --optimized output/optimized_v1
```

**Available Options**
```
--help                 Show help message
--baseline DIR         Baseline output directory (required)
--optimized DIR        Optimized output directory (required)
--tolerance TOL        Tolerance for floating point comparisons (default: 1e-10)
--max-frames N         Maximum number of frames to compare (default: all)
--checksum-only        Only compare checksums, not full frames
--frame FRAME          Compare specific frame (can be used multiple times)
```

**How the Validation Works**
1. First, run two different implementations with output enabled:
```
   # Run baseline with output
./build/heat_diffusion --width 500 --height 500 --frames 100 --output --output-dir output/base

# Run optimized with same parameters
./build/heat_diffusion_optimized_v1 --width 500 --height 500 --frames 100 --output --output-dir output/optimized_v1
```

2. Then compare the generated output files:
```
./build/validate --baseline output/base --optimized output/optimized_v1   
```

**Additional Usage Examples**
```
# Compare only checksums (faster)
./build/validate --baseline output/base --optimized output/optimized_v2 --checksum-only

# Compare with custom tolerance
./build/validate --baseline output/openmp --optimized output/mpi --tolerance 1e-8

# Compare only specific frames
./build/validate --baseline output/base --optimized output/hybrid --frame frame_50.txt --frame frame_99.txt
```



### Block Size Optimizer

The Block Size Optimizer is a specialized tool that helps determine the optimal cache block sizes for the cache-blocked implementation (optimized_v3) of the heat diffusion simulation. This tool can significantly improve performance by finding block sizes that best utilize your CPU's cache hierarchy.

**Using the Block Size Optimizer**
```
# Basic usage
./build/block_size_optimizer

# With custom parameters
./build/block_size_optimizer --width 2048 --height 2048 --min 8 --max 256 --step 8
```

**Available Options**
```
--help               Show help message
--width WIDTH        Grid width to use for testing (default: 1000)
--height HEIGHT      Grid height to use for testing (default: 1000)
--iterations ITERS   Number of simulation steps to run per test (default: 1000)
--runs RUNS          Number of times to repeat each test (default: 3)
--min MIN            Minimum block size to test (default: 4)
--max MAX            Maximum block size to test (default: 512)
--step STEP          Step size between block sizes (default: varies)
--output FILE        Output results to specified file (default: block_size_results.csv)
```
**How the Optimizer Works**


The Block Size Optimizer:

1. Creates a series of block sizes to test based on the min/max/step parameters
2. Tests all combinations of block sizes in both X and Y dimensions
3. For each combination, runs the simulation for a specified number of iterations
4. Measures the execution time for each block size combination
5. Ranks all combinations from fastest to slowest
Outputs the top results and saves all data to a CSV file

**Understanding the Results**

The tool outputs:

1. A table showing the top 10 best-performing block sizes
2. The single optimal block size combination with its runtime
3. Comparison with the current default block size (144x144)
4. Potential performance improvement percentage
5. A CSV file with all tested combinations for further analysis

**Using on HPC Systems (CSD3)**

The project includes a SLURM script for running the optimizer on HPC systems:
```
# Submit the optimizer job to SLURM
sbatch scripts/block_size_optimizer.sh
```

The script is pre-configured for the CSD3 cluster with appropriate resource requests and module loading.

**Guidelines for Choosing Block Sizes**

Optimal block sizes typically depend on:

1. **CPU Cache Sizes**: Best block sizes often relate to L1/L2/L3 cache sizes
2. **Problem Size**: Different grid dimensions may benefit from different block sizes
3. **Hardware Architecture**: Different CPU models have different optimal values
4. **Memory Access Patterns**: The heat diffusion stencil pattern favors certain sizes

## 📣 Running Heat Diffusion Benchmarks
The project includes comprehensive benchmark executables for all implementations. Benchmarks run multiple trials and report detailed performance statistics

### Common Benchmark Options
All benchmark executables share these command-line options:
```
--width WIDTH          Set grid width (default: 1000)
--height HEIGHT        Set grid height (default: 1000)
--iterations ITERS     Number of iterations to run (default: 1000)
--runs RUNS            Number of benchmark runs (default: 10)
--save                 Enable output file generation (disabled by default)
```

### Running Sequential Implementation Benchmarks
```
# Base implementation benchmark
./build/heat_diffusion_benchmark

# Optimized implementation benchmarks
./build/heat_diffusion_optimized_benchmark_v1
./build/heat_diffusion_optimized_benchmark_v2
./build/heat_diffusion_optimized_benchmark_v3
```
Example with options:
```
./build/heat_diffusion_optimized_benchmark_v3 --width 2000 --height 2000 --iterations 500 --runs 5
```

### Running OpenMP Implementation Benchmark
```
./build/heat_diffusion_openmp_benchmark [--threads NUM_THREADS]
```
* --threads NUM_THREADS: Number of OpenMP threads to use
  
```
# Run with 8 threads
./build/heat_diffusion_openmp_benchmark --threads 8

# Use OMP_NUM_THREADS environment variable
export OMP_NUM_THREADS=6
./build/heat_diffusion_openmp_benchmark
```
### Running MPI Implementation Benchmark

```
mpirun -np NUM_PROCESSES ./build/heat_diffusion_mpi_benchmark
```
The MPI benchmark adds the option:
* --ranks RANKS: Expected number of MPI ranks (validates against actual running ranks)

```
mpirun -np 4 ./build/heat_diffusion_mpi_benchmark --width 2000 --height 2000
```
### Running Hybrid MPI+OpenMP Implementation Benchmark

```
mpirun -np NUM_PROCESSES ./build/heat_diffusion_benchmark_hybrid [--threads THREADS]
```
### Benchmark Output
Each benchmark reports detailed statistics including:

* Setup time and simulation time
* Per-iteration timing statistics
* Performance metrics (cell updates per second)
* Memory usage (on supported mac platforms)
* Numerical stability verification

## Using Docker for Development and Profiling

The project includes Docker configuration to provide a consistent development and profiling environment across different platforms. This is especially useful for macOS users who need Linux-specific profiling tools.

### Docker Setup

```bash
# Build the Docker image
docker build -t hpc-benchmark-env .

# Run the container interactively with current directory mounted
docker run -it --rm -v $(pwd):/app hpc-benchmark-env
```
Once inside the container, you'll have access to all development and profiling tools
```
# Navigate to the mounted project directory
cd /app

# Build the project
mkdir -p build && cd build
cmake ..
make -j$(nproc)

# Run simulations
./heat_diffusion_optimized_v3 --width 500 --height 500

# Run MPI simulations
# Allow MPI to run as root in Docker
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
mpirun -np 4 ./heat_diffusion_mpi --width 1000 --height 1000
```

## Using CSD3 for Development and Profiling
Here's how to run the heat diffusion simulation scripts on CSD3.
**Connecting to CSD3**
```
# Connect to CSD3 via SSH
ssh username@login.hpc.cam.ac.uk
```
**Running Scripts on CSD3**

Basic SLURM Job Submission:
```
#To run base/optimized_v[1/2/3]/openmp/mpi benchmark
sintr -A MPHIL-DIS-SL2-CPU  -t 01:00:00 -p icelake -N 1 -n 38

#To run hybrid on two nodes
sintr -A MPHIL-DIS-SL2-CPU  -t 01:00:00 -p icelake -N 2 -n 76
```

**Setting up the Environment**

```
# Clone the repository (if needed)
git clone <repository-url>
cd Coursework

#set the correct module to run
module purge
module load rhel8/default-icl

# Build the project
mkdir -p build && cd build
cmake ..
make -j8
```
The project includes pre-configured SLURM scripts for CSD3:

```
# Submit the block size optimization job
 ./scripts/block_size_optimizer.sh

# Submit comprehensive profiling job
./scripts/comprehensive-profiling-script.sh

# Submit OpenMP-specific profiling job
./scripts/comprehensive-profiling-script-openmp.sh

# Submit MPI-specific profiling job
./scripts/comprehensive-profiling-script-mpi.sh

# Then run executable, for example:
./heat_diffusion_benchmark --width 2000 --height 2000 --iterations 1000
./heat_diffusion_optimized_benchmark_v3 --width 2000 --height 2000 --iterations 1000
export OMP_NUM_THREADS=76 && ./heat_diffusion_openmp_benchmark --width 2000 --height 2000 --iterations 1000
mpirun -n 76 ./heat_diffusion_mpi_benchmark --width 2000 --height 2000 --iterations 1000

# Run with 2 MPI processes (1 per node) and 76 threads each 
export OMP_NUM_THREADS=76
mpirun -n 2 -ppn 1 ./heat_diffusion_benchmark_hybrid --width 5000 --height 5000 --iterations 1000

#optimal configuration
$srun -n 19 --nodes=2 --ntasks-per-node=10 --cpus-per-task=4 ./heat_diffusion_benchmark_hybrid --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 4 
```


## Documentation with Doxygen
This project is configured with comprehensive Doxygen documentation support. Here's how to use it:
### Generating Documentation
```
# Generate documentation using Doxygen
doxygen Doxyfile

# Or if you're using Docker
docker run -it --rm -v $(pwd):/app hpc-benchmark-env bash -c "cd /app && doxygen Doxyfile"

# Or generate documentation through CMake
cd build
make docs
```

### Viewing HTML Documentation

```
# Open HTML documentation (macOS)
open docs/html/index.html

# Open HTML documentation (Linux)
xdg-open docs/html/index.html
```
### Viewing PDF Documentation
```
# Generate PDF from LaTeX files
cd docs/latex
make

# Open the PDF (macOS)
open refman.pdf

# Open the PDF (Linux)
xdg-open refman.pdf
```

If you encounter LaTeX compilation errors, you can still view the HTML documentation which contains the same information in a more accessible format.

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

