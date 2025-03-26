#!/bin/bash

# Comprehensive profiling script for hybrid MPI+OpenMP heat diffusion simulation
# Designed to run inside Docker containers with proper path handling

# Allow MPI to run as root in Docker
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create directories
mkdir -p /app/profiling_results_hybrid/{gprof,valgrind,scaling,communication,thread_scaling,process_thread_balance}

echo -e "${GREEN}Starting Hybrid MPI+OpenMP profiling...${NC}"

# Go to project root where CMakeLists.txt is located
cd /app

# Create build directory if it doesn't exist
if [ ! -d "build" ]; then
    mkdir -p build
fi

# Enter build directory
cd build

# Configure and build
echo -e "${BLUE}Configuring and building...${NC}"

# Build with normal optimization
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4 heat_diffusion_hybrid_benchmark

# Verify the executable exists
if [ ! -f "heat_diffusion_hybrid_benchmark" ]; then
    echo -e "${YELLOW}Error: heat_diffusion_hybrid_benchmark was not built correctly${NC}"
    echo "Please check your build configuration and try again."
    exit 1
fi

#=====================
# 1. Environment Check
#=====================
echo -e "${BLUE}Checking hybrid execution environment...${NC}"
# Get the number of available CPU cores
NUM_CORES=$(nproc)
echo -e "${YELLOW}System has ${NUM_CORES} CPU cores available${NC}"

# Try to get OpenMP information
echo -e "${YELLOW}Creating OpenMP test program...${NC}"
cat > openmp_test.c << EOF
#include <stdio.h>
#include <omp.h>
int main() {
    printf("OpenMP version: %d\n", _OPENMP);
    printf("OpenMP max threads: %d\n", omp_get_max_threads());
    return 0;
}
EOF
gcc -fopenmp openmp_test.c -o openmp_test
if [ -f "openmp_test" ]; then
    ./openmp_test
    rm openmp_test openmp_test.c
else
    echo -e "${YELLOW}Failed to compile OpenMP test program${NC}"
fi

# Check MPI environment
echo -e "${YELLOW}Checking MPI environment...${NC}"
MPIRUN_PATH=$(which mpirun)
if [ -n "$MPIRUN_PATH" ]; then
    echo -e "mpirun found at: $MPIRUN_PATH"
    echo -e "MPI implementation: $(mpirun --version | head -n 1)"
else
    echo -e "${YELLOW}Warning: mpirun not found in PATH${NC}"
fi

#=====================
# 2. GPROF Profiling
#=====================
echo -e "${BLUE}Running gprof profiling...${NC}"

# Build with profiling enabled
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_CXX_FLAGS="-pg"
make -j4 heat_diffusion_hybrid_benchmark

# Run with small grid for quick profiling - 2 MPI ranks, 2 threads per rank
export OMP_NUM_THREADS=2
mpirun -n 2 ./heat_diffusion_hybrid_benchmark --size 500 --iterations 50 --runs 1 --threads 2

# Generate gprof report for each rank
for gmon in gmon.out.*; do
    # Extract rank number from filename if present
    if [[ $gmon =~ .*\.([0-9]+)$ ]]; then
        RANK="${BASH_REMATCH[1]}"
    else
        RANK="combined"
    fi
    
    gprof ./heat_diffusion_hybrid_benchmark $gmon > ../profiling_results_hybrid/gprof/gprof_report_rank_${RANK}.txt
    echo -e "${YELLOW}Created gprof report for rank ${RANK}${NC}"
done

#=====================
# 3. Thread-Process Balance Tests
#=====================
echo -e "${BLUE}Running thread-process balance tests...${NC}"

# Build optimized version again
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4 heat_diffusion_hybrid_benchmark

# Define test combinations of processes and threads
# Keep total cores constant (processes * threads = constant)
declare -a COMBINATIONS=(
    "1:$NUM_CORES"  # 1 process with all threads
    "$NUM_CORES:1"  # All processes with 1 thread each (pure MPI)
)

# Add intermediate combinations if we have enough cores
if [ $NUM_CORES -ge 4 ]; then
    COMBINATIONS+=("2:$((NUM_CORES/2))")  # 2 processes with half threads each
    COMBINATIONS+=("$((NUM_CORES/2)):2")  # Half processes with 2 threads each
fi

if [ $NUM_CORES -ge 8 ]; then
    COMBINATIONS+=("4:$((NUM_CORES/4))")  # 4 processes with quarter threads each
fi

# Test different process:thread combinations
echo -e "${YELLOW}Testing different process:thread combinations...${NC}"
for COMBO in "${COMBINATIONS[@]}"; do
    # Split into processes and threads
    PROCS=$(echo $COMBO | cut -d':' -f1)
    THREADS=$(echo $COMBO | cut -d':' -f2)
    
    echo -e "Testing with ${PROCS} processes and ${THREADS} threads per process (total cores: $((PROCS*THREADS)))..."
    
    export OMP_NUM_THREADS=$THREADS
    mpirun -n $PROCS ./heat_diffusion_hybrid_benchmark --size 1000 --iterations 50 --runs 1 --threads $THREADS > \
        ../profiling_results_hybrid/process_thread_balance/procs${PROCS}_threads${THREADS}.txt 2>&1
    
    # Check if the run was successful
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: Run with ${PROCS} processes and ${THREADS} threads failed${NC}"
    fi
done

#=====================
# 4. Strong Scaling Tests
#=====================
echo -e "${BLUE}Running strong scaling tests...${NC}"

# Define configurations to test
declare -a STRONG_CONFIGS=(
    # Format: "processes:threads"
    "1:1"    # Baseline: 1 process, 1 thread
    "1:2"    # 1 process, 2 threads
    "1:4"    # 1 process, 4 threads
    "2:1"    # 2 processes, 1 thread each
    "2:2"    # 2 processes, 2 threads each
    "4:1"    # 4 processes, 1 thread each
    "4:2"    # 4 processes, 2 threads each
)

# Limit tests based on available cores
for CONFIG in "${STRONG_CONFIGS[@]}"; do
    PROCS=$(echo $CONFIG | cut -d':' -f1)
    THREADS=$(echo $CONFIG | cut -d':' -f2)
    TOTAL_CORES=$((PROCS * THREADS))
    
    if [ $TOTAL_CORES -le $NUM_CORES ]; then
        echo -e "Running strong scaling test with ${PROCS} processes and ${THREADS} threads per process..."
        
        export OMP_NUM_THREADS=$THREADS
        mpirun -n $PROCS ./heat_diffusion_hybrid_benchmark --size 1000 --iterations 50 --runs 1 --threads $THREADS > \
            ../profiling_results_hybrid/scaling/strong_p${PROCS}_t${THREADS}.txt 2>&1
        
        # Check if the run was successful
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}Warning: Strong scaling run with ${PROCS} processes and ${THREADS} threads failed${NC}"
        fi
    else
        echo -e "${YELLOW}Skipping configuration p${PROCS}_t${THREADS} (requires ${TOTAL_CORES} cores, only ${NUM_CORES} available)${NC}"
    fi
done

#=====================
# 5. Weak Scaling Tests
#=====================
echo -e "${BLUE}Running weak scaling tests...${NC}"

# Base problem size for 1 process, 1 thread
BASE_SIZE=500

for CONFIG in "${STRONG_CONFIGS[@]}"; do
    PROCS=$(echo $CONFIG | cut -d':' -f1)
    THREADS=$(echo $CONFIG | cut -d':' -f2)
    TOTAL_CORES=$((PROCS * THREADS))
    
    if [ $TOTAL_CORES -le $NUM_CORES ]; then
        # Scale problem size with total cores
        SIZE=$(echo "sqrt($BASE_SIZE * $BASE_SIZE * $TOTAL_CORES)" | bc)
        SIZE=${SIZE%.*} # Remove decimal part
        
        echo -e "Running weak scaling test with ${PROCS} processes, ${THREADS} threads, grid size ${SIZE}x${SIZE}..."
        
        export OMP_NUM_THREADS=$THREADS
        mpirun -n $PROCS ./heat_diffusion_hybrid_benchmark --size $SIZE --iterations 50 --runs 1 --threads $THREADS > \
            ../profiling_results_hybrid/scaling/weak_p${PROCS}_t${THREADS}.txt 2>&1
        
        # Check if the run was successful
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}Warning: Weak scaling run with ${PROCS} processes and ${THREADS} threads failed${NC}"
        fi
    fi
done

#=====================
# 6. Thread Affinity Tests
#=====================
echo -e "${BLUE}Running thread affinity tests...${NC}"
mkdir -p ../profiling_results_hybrid/affinity

# Test different thread binding strategies with a balanced hybrid configuration
# Choose a reasonable configuration based on available cores
if [ $NUM_CORES -ge 8 ]; then
    PROCS=2
    THREADS=4
elif [ $NUM_CORES -ge 4 ]; then
    PROCS=2
    THREADS=2
else
    PROCS=1
    THREADS=$NUM_CORES
fi

# Test different thread binding strategies
OMP_BINDING_TYPES=("close" "spread" "master")
for BIND in "${OMP_BINDING_TYPES[@]}"; do
    echo -e "Testing with OMP_PROC_BIND=${BIND}..."
    export OMP_NUM_THREADS=$THREADS
    export OMP_PROC_BIND=$BIND
    
    mpirun -n $PROCS ./heat_diffusion_hybrid_benchmark --size 1000 --iterations 50 --runs 1 --threads $THREADS > \
        ../profiling_results_hybrid/affinity/bind_${BIND}.txt 2>&1
    
    # Check if the run was successful
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: OpenMP binding run with binding ${BIND} failed${NC}"
    fi
done

# Reset binding for further tests
unset OMP_PROC_BIND

#=====================
# 7. VALGRIND with MPI rank (for 1 rank only)
#=====================
echo -e "${BLUE}Running Valgrind on a single MPI rank with multiple threads...${NC}"

# Note: Running valgrind with MPI+OpenMP can be tricky - we'll run on just one rank
export OMP_NUM_THREADS=4
valgrind --tool=cachegrind mpirun -n 1 ./heat_diffusion_hybrid_benchmark --size 200 --iterations 10 --runs 1 --threads 4 > \
    ../profiling_results_hybrid/valgrind/cachegrind_output.txt 2>&1

# Find the cachegrind output file
CACHEGRIND_FILE=$(ls cachegrind.out.*)
if [ -n "$CACHEGRIND_FILE" ]; then
    cg_annotate $CACHEGRIND_FILE > ../profiling_results_hybrid/valgrind/cachegrind_report.txt
fi

#=====================
# 8. MPI Communication Pattern Analysis
#=====================
echo -e "${BLUE}Running MPI communication pattern analysis...${NC}"

# Test communication patterns with different grid sizes
for GRID_SIZE in 200 500 1000; do
    echo -e "${YELLOW}Testing grid size ${GRID_SIZE} with fixed hybrid configuration...${NC}"
    
    # Use a balanced configuration
    PROCS=2
    THREADS=2
    
    export OMP_NUM_THREADS=$THREADS
    mpirun -n $PROCS ./heat_diffusion_hybrid_benchmark --size $GRID_SIZE --iterations 50 --runs 1 --threads $THREADS > \
        ../profiling_results_hybrid/communication/grid${GRID_SIZE}_p${PROCS}_t${THREADS}.txt 2>&1
    
    # Check if the run was successful
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: Communication pattern test with grid size ${GRID_SIZE} failed${NC}"
    fi
done

#=====================
# 9. Test Different MPI Thread Support Levels
#=====================
echo -e "${BLUE}Testing different MPI thread support levels...${NC}"
mkdir -p ../profiling_results_hybrid/thread_support

# This test requires recompilation with different thread support levels
# We'll test with a balanced hybrid configuration
PROCS=2
THREADS=2

# Save a copy of the original benchmark for backup
cp heat_diffusion_hybrid_benchmark heat_diffusion_hybrid_benchmark.bak

# Test different thread support levels
THREAD_LEVELS=("MPI_THREAD_SINGLE" "MPI_THREAD_FUNNELED" "MPI_THREAD_SERIALIZED" "MPI_THREAD_MULTIPLE")
for LEVEL in "${THREAD_LEVELS[@]}"; do
    echo -e "${YELLOW}Testing with thread support level: ${LEVEL}${NC}"
    
    # Recompile with specific thread support level
    # This assumes you have a way to configure the thread support level during compilation
    # Modify this to match your project's build system
    cmake .. -DCMAKE_BUILD_TYPE=Release -DMPI_THREAD_LEVEL=${LEVEL}
    make -j4 heat_diffusion_hybrid_benchmark
    
    if [ -f "heat_diffusion_hybrid_benchmark" ]; then
        export OMP_NUM_THREADS=$THREADS
        mpirun -n $PROCS ./heat_diffusion_hybrid_benchmark --size 1000 --iterations 50 --runs 1 --threads $THREADS > \
            ../profiling_results_hybrid/thread_support/${LEVEL}.txt 2>&1
    else
        echo -e "${YELLOW}Failed to compile with thread support level: ${LEVEL}${NC}"
    fi
done

# Restore original benchmark binary
mv heat_diffusion_hybrid_benchmark.bak heat_diffusion_hybrid_benchmark

#=====================
# 10. Dynamic Thread Adjustment Test
#=====================
echo -e "${BLUE}Testing dynamic thread adjustment...${NC}"
mkdir -p ../profiling_results_hybrid/dynamic_threads

# Test