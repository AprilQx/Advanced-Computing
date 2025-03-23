#!/bin/bash

# Improved profiling script for OpenMP heat diffusion benchmark
# Designed to run inside Docker containers with proper path handling

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create directories
mkdir -p /app/profiling_results_omp/{gprof,valgrind,thread_scaling,cache}

echo -e "${GREEN}Starting OpenMP profiling...${NC}"

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

# First, build normal optimized version
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4 heat_diffusion_openmp_benchmark

# Verify the executable exists
if [ ! -f "heat_diffusion_openmp_benchmark" ]; then
    echo -e "${YELLOW}Error: heat_diffusion_openmp_benchmark was not built correctly${NC}"
    echo "Please check your build configuration and try again."
    exit 1
fi

#=====================
# 1. OpenMP Environment Check
#=====================
echo -e "${BLUE}Checking OpenMP environment...${NC}"
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

#=====================
# 2. GPROF Profiling
#=====================
echo -e "${BLUE}Running gprof profiling...${NC}"

# Build with profiling enabled
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_CXX_FLAGS="-pg"
make -j4 heat_diffusion_openmp_benchmark

# Run with small grid for quick profiling - single thread for cleaner profile
export OMP_NUM_THREADS=1
./heat_diffusion_openmp_benchmark --width 500 --height 500 --frames 50 --runs 1

# Generate gprof report
gprof ./heat_diffusion_openmp_benchmark gmon.out > /app/profiling_results_omp/gprof/gprof_report.txt

#=====================
# 3. Thread Scaling Tests
#=====================
echo -e "${BLUE}Running thread scaling tests...${NC}"

# Build optimized version again
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4 heat_diffusion_openmp_benchmark

# Test different thread counts (1, 2, 4, 8, 16, etc. up to NUM_CORES)
THREAD_COUNTS=(1)
for ((i=2; i<=NUM_CORES; i*=2)); do
    if [ $i -le $NUM_CORES ]; then
        THREAD_COUNTS+=($i)
    fi
done
# Add the full core count if not already in the list
if [[ ! " ${THREAD_COUNTS[@]} " =~ " ${NUM_CORES} " ]]; then
    THREAD_COUNTS+=($NUM_CORES)
fi

# Fixed grid size test (strong scaling)
echo -e "${YELLOW}Running strong scaling tests...${NC}"
for THREADS in "${THREAD_COUNTS[@]}"; do
    echo -e "Testing with ${THREADS} threads..."
    export OMP_NUM_THREADS=$THREADS
    ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 50 --runs 1 --threads $THREADS > \
        /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt 2>&1
    
    # Check if the run was successful
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: OpenMP run with ${THREADS} threads failed${NC}"
    fi
done

# Increasing grid size with thread count (weak scaling)
echo -e "${YELLOW}Running weak scaling tests...${NC}"
for THREADS in "${THREAD_COUNTS[@]}"; do
    # Scale problem size with thread count - keep work per thread constant
    BASE_SIZE=500
    SIZE=$(echo "sqrt($BASE_SIZE * $BASE_SIZE * $THREADS)" | bc)
    SIZE=${SIZE%.*} # Remove decimal part
    
    echo -e "Testing with ${THREADS} threads, grid size ${SIZE}x${SIZE}..."
    export OMP_NUM_THREADS=$THREADS
    ./heat_diffusion_openmp_benchmark --width $SIZE --height $SIZE --frames 50 --runs 1 --threads $THREADS > \
        /app/profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt 2>&1
    
    # Check if the run was successful
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: OpenMP run with ${THREADS} threads failed on ${SIZE}x${SIZE} grid${NC}"
    fi
done

#=====================
# 4. Thread Affinity Tests
#=====================
echo -e "${BLUE}Running thread affinity tests...${NC}"
mkdir -p /app/profiling_results_omp/affinity

# Test different thread binding strategies
OMP_BINDING_TYPES=("close" "spread" "master")
for BIND in "${OMP_BINDING_TYPES[@]}"; do
    echo -e "Testing with OMP_PROC_BIND=${BIND}..."
    export OMP_NUM_THREADS=$NUM_CORES
    export OMP_PROC_BIND=$BIND
    
    ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 50 --runs 1 > \
        /app/profiling_results_omp/affinity/bind_${BIND}.txt 2>&1
    
    # Check if the run was successful
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: OpenMP run with binding ${BIND} failed${NC}"
    fi
done

# Reset binding for further tests
unset OMP_PROC_BIND

#=====================
# 5. VALGRIND Tools
#=====================
echo -e "${BLUE}Running Valgrind profiling...${NC}"

# 5.1 Cachegrind (cache profiling) - use single thread for clearer results
echo -e "${YELLOW}Running cachegrind...${NC}"
export OMP_NUM_THREADS=1
valgrind --tool=cachegrind ./heat_diffusion_openmp_benchmark --width 200 --height 200 --frames 5 --runs 1 > \
    /app/profiling_results_omp/valgrind/cachegrind_output.txt 2>&1

# Find the cachegrind output file
CACHEGRIND_FILE=$(ls cachegrind.out.*)
if [ -n "$CACHEGRIND_FILE" ]; then
    cg_annotate $CACHEGRIND_FILE > /app/profiling_results_omp/valgrind/cachegrind_report.txt
fi

# 5.2 Callgrind (call graph generation) - use single thread for clearer results
echo -e "${YELLOW}Running callgrind...${NC}"
export OMP_NUM_THREADS=1
valgrind --tool=callgrind ./heat_diffusion_openmp_benchmark --width 200 --height 200 --frames 5 --runs 1 > \
    /app/profiling_results_omp/valgrind/callgrind_output.txt 2>&1

# Find the callgrind output file
CALLGRIND_FILE=$(ls callgrind.out.*)
if [ -n "$CALLGRIND_FILE" ]; then
    callgrind_annotate $CALLGRIND_FILE > /app/profiling_results_omp/valgrind/callgrind_report.txt
fi

# 5.3 Massif (heap profiling) - can use multiple threads
echo -e "${YELLOW}Running massif...${NC}"
export OMP_NUM_THREADS=$NUM_CORES
valgrind --tool=massif ./heat_diffusion_openmp_benchmark --width 500 --height 500 --frames 10 --runs 1 > \
    /app/profiling_results_omp/valgrind/massif_output.txt 2>&1

# Find the massif output file
MASSIF_FILE=$(ls massif.out.*)
if [ -n "$MASSIF_FILE" ]; then
    ms_print $MASSIF_FILE > /app/profiling_results_omp/valgrind/massif_report.txt
fi

#=====================
# 6. Cache Size Impact Test
#=====================
echo -e "${BLUE}Running cache size impact tests...${NC}"

# Test different grid sizes to see how they affect cache performance
for SIZE in 100 256 512 1024 2048; do
    echo -e "${YELLOW}Testing grid size ${SIZE}x${SIZE}${NC}"
    
    # Use reduced iterations for larger grids
    if [ $SIZE -gt 1000 ]; then
        FRAMES=10
    else 
        FRAMES=20
    fi
    
    export OMP_NUM_THREADS=$NUM_CORES  # Use all cores
    ./heat_diffusion_openmp_benchmark --width $SIZE --height $SIZE --frames $FRAMES --runs 1 > \
        /app/profiling_results_omp/cache/size_${SIZE}.txt 2>&1
    
    # Check if the run was successful
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: Run with grid size ${SIZE}x${SIZE} failed${NC}"
    fi
done

#=====================
# 7. NUMA Effects Test (if applicable)
#=====================
echo -e "${BLUE}Checking for NUMA architecture...${NC}"

# Only run NUMA tests if numactl is available and system has multiple NUMA nodes
if command -v numactl &> /dev/null; then
    if numactl --hardware 2>&1 | grep -q "available"; then
        NUMA_NODES=$(numactl --hardware 2>&1 | grep "available" | awk '{print $2}')
        
        if [ "$NUMA_NODES" -gt 1 ]; then
            echo -e "${YELLOW}Detected NUMA system with ${NUMA_NODES} nodes. Running NUMA tests...${NC}"
            mkdir -p /app/profiling_results_omp/numa
            
            # Test with threads restricted to each NUMA node
            for NODE in $(seq 0 $((NUMA_NODES-1))); do
                echo -e "Testing with threads restricted to NUMA node ${NODE}..."
                numactl --cpunodebind=$NODE ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 20 --runs 1 > \
                    /app/profiling_results_omp/numa/node${NODE}.txt 2>&1
            done
            
            # Test with threads on all nodes but memory allocation on node 0
            echo -e "Testing with memory on node 0, computation on all nodes..."
            numactl --membind=0 ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 20 --runs 1 > \
                /app/profiling_results_omp/numa/mem_node0_cpu_all.txt 2>&1
            
            # Test with interleaved memory allocation
            echo -e "Testing with interleaved memory allocation..."
            numactl --interleave=all ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 20 --runs 1 > \
                /app/profiling_results_omp/numa/interleaved.txt 2>&1
        else
            echo -e "${YELLOW}This is not a NUMA system or only has one NUMA node. Skipping NUMA tests.${NC}"
        fi
    else
        echo -e "${YELLOW}NUMA hardware detection failed. Skipping NUMA tests.${NC}"
    fi
else
    echo -e "${YELLOW}NUMA tools not available. Skipping NUMA tests.${NC}"
fi

#=====================
# 8. Generate Summary
#=====================
echo -e "${GREEN}Generating summary...${NC}"

echo "OPENMP BENCHMARK PROFILING SUMMARY" > /app/profiling_results_omp/summary.txt
echo "=================================" >> /app/profiling_results_omp/summary.txt
echo "" >> /app/profiling_results_omp/summary.txt

# Add OpenMP environment info
if [ -f "openmp_test" ]; then
    echo "OpenMP Environment:" >> /app/profiling_results_omp/summary.txt
    ./openmp_test >> /app/profiling_results_omp/summary.txt
    echo "Processor cores: $(nproc)" >> /app/profiling_results_omp/summary.txt
    echo "" >> /app/profiling_results_omp/summary.txt
fi

# Add thread scaling results
echo "Thread Scaling Results:" >> /app/profiling_results_omp/summary.txt
echo "Strong Scaling (Fixed Problem Size):" >> /app/profiling_results_omp/summary.txt
for THREADS in "${THREAD_COUNTS[@]}"; do
    if [ -f /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt ]; then
        echo "  ${THREADS} threads:" >> /app/profiling_results_omp/summary.txt
        grep "Average Iteration Time:" /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
        grep "Performance:" /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt | grep -i "cell updates" >> /app/profiling_results_omp/summary.txt 2>/dev/null
    fi
done
echo "" >> /app/profiling_results_omp/summary.txt

echo "Weak Scaling (Problem Size Scaled with Thread Count):" >> /app/profiling_results_omp/summary.txt
for THREADS in "${THREAD_COUNTS[@]}"; do
    if [ -f /app/profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt ]; then
        SIZE=$(echo "sqrt(500 * 500 * $THREADS)" | bc)
        SIZE=${SIZE%.*} # Remove decimal part
        echo "  ${THREADS} threads (${SIZE}x${SIZE} grid):" >> /app/profiling_results_omp/summary.txt
        grep "Grid Size:" /app/profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
        grep "Average Iteration Time:" /app/profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
        grep "Performance:" /app/profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt | grep -i "cell updates" >> /app/profiling_results_omp/summary.txt 2>/dev/null
    fi
done
echo "" >> /app/profiling_results_omp/summary.txt

# Add thread affinity results
echo "Thread Affinity Results:" >> /app/profiling_results_omp/summary.txt
for BIND in "${OMP_BINDING_TYPES[@]}"; do
    if [ -f /app/profiling_results_omp/affinity/bind_${BIND}.txt ]; then
        echo "  OMP_PROC_BIND=${BIND}:" >> /app/profiling_results_omp/summary.txt
        grep "Average Iteration Time:" /app/profiling_results_omp/affinity/bind_${BIND}.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
        grep "Performance:" /app/profiling_results_omp/affinity/bind_${BIND}.txt | grep -i "cell updates" >> /app/profiling_results_omp/summary.txt 2>/dev/null
    fi
done
echo "" >> /app/profiling_results_omp/summary.txt

# Add parallel efficiency calculation
echo "Parallel Efficiency:" >> /app/profiling_results_omp/summary.txt

# Find the single-thread timing
if [ -f /app/profiling_results_omp/thread_scaling/strong_scaling_1threads.txt ]; then
    SINGLE_THREAD_TIME=$(grep "Average Iteration Time:" /app/profiling_results_omp/thread_scaling/strong_scaling_1threads.txt | awk '{print $4}')
    
    for THREADS in "${THREAD_COUNTS[@]}"; do
        if [ $THREADS -ne 1 ] && [ -f /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt ]; then
            THREAD_TIME=$(grep "Average Iteration Time:" /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt | awk '{print $4}')
            
            # Calculate efficiency if we have valid numbers
            if [[ $SINGLE_THREAD_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $THREAD_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                EFF=$(echo "scale=2; ($SINGLE_THREAD_TIME / ($THREADS * $THREAD_TIME)) * 100" | bc)
                SPEEDUP=$(echo "scale=2; $SINGLE_THREAD_TIME / $THREAD_TIME" | bc)
                echo "  ${THREADS} threads: efficiency ${EFF}%, speedup ${SPEEDUP}x" >> /app/profiling_results_omp/summary.txt
            fi
        fi
    done
fi
echo "" >> /app/profiling_results_omp/summary.txt

# Add gprof summary
echo "Top functions from gprof:" >> /app/profiling_results_omp/summary.txt
head -n 20 /app/profiling_results_omp/gprof/gprof_report.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
echo "" >> /app/profiling_results_omp/summary.txt

# Add cache statistics
if [ -f /app/profiling_results_omp/valgrind/cachegrind_report.txt ]; then
    echo "Cache statistics (cachegrind):" >> /app/profiling_results_omp/summary.txt
    grep "I   refs" /app/profiling_results_omp/valgrind/cachegrind_report.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
    grep "D   refs" /app/profiling_results_omp/valgrind/cachegrind_report.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
    grep "D1  miss rate" /app/profiling_results_omp/valgrind/cachegrind_report.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
    grep "LL miss rate" /app/profiling_results_omp/valgrind/cachegrind_report.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
    echo "" >> /app/profiling_results_omp/summary.txt
fi

# Add memory usage information
if [ -f /app/profiling_results_omp/valgrind/massif_report.txt ]; then
    echo "Memory usage (massif):" >> /app/profiling_results_omp/summary.txt
    grep "peak:" /app/profiling_results_omp/valgrind/massif_report.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
    echo "" >> /app/profiling_results_omp/summary.txt
fi

# Add cache size impact analysis
echo "Cache Size Impact (Different Grid Sizes):" >> /app/profiling_results_omp/summary.txt
for SIZE in 100 256 512 1024 2048; do
    if [ -f /app/profiling_results_omp/cache/size_${SIZE}.txt ]; then
        echo "  Grid size ${SIZE}x${SIZE}:" >> /app/profiling_results_omp/summary.txt
        grep "Grid Size:" /app/profiling_results_omp/cache/size_${SIZE}.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
        grep "Average Iteration Time:" /app/profiling_results_omp/cache/size_${SIZE}.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
        grep "Memory Usage:" /app/profiling_results_omp/cache/size_${SIZE}.txt >> /app/profiling_results_omp/summary.txt 2>/dev/null
    fi
done
echo "" >> /app/profiling_results_omp/summary.txt

# Add NUMA effects summary if applicable
if [ -d /app/profiling_results_omp/numa ]; then
    echo "NUMA Effects:" >> /app/profiling_results_omp/summary.txt
    
    # Compare performances across NUMA configurations
    for FILE in /app/profiling_results_omp/numa/*.txt; do
        if [ -f "$FILE" ]; then
            FILENAME=$(basename "$FILE" .txt)
            echo "  Configuration: ${FILENAME}" >> /app/profiling_results_omp/summary.txt
            grep "Average Iteration Time:" "$FILE" >> /app/profiling_results_omp/summary.txt 2>/dev/null
            grep "Performance:" "$FILE" | grep -i "cell updates" >> /app/profiling_results_omp/summary.txt 2>/dev/null
        fi
    done
    echo "" >> /app/profiling_results_omp/summary.txt
fi

# Calculate speedup graphs
echo "Speedup Analysis:" >> /app/profiling_results_omp/summary.txt
if [ -f /app/profiling_results_omp/thread_scaling/strong_scaling_1threads.txt ]; then
    SINGLE_TIME=$(grep "Average Iteration Time:" /app/profiling_results_omp/thread_scaling/strong_scaling_1threads.txt | awk '{print $4}')
    
    echo "  Thread count | Speedup (vs 1 thread)" >> /app/profiling_results_omp/summary.txt
    echo "  -------------|----------------------" >> /app/profiling_results_omp/summary.txt
    
    for THREADS in "${THREAD_COUNTS[@]}"; do
        if [ -f /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt ]; then
            THREAD_TIME=$(grep "Average Iteration Time:" /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt | awk '{print $4}')
            
            # Calculate speedup if we have valid numbers
            if [[ $SINGLE_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $THREAD_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                SPEEDUP=$(echo "scale=2; $SINGLE_TIME / $THREAD_TIME" | bc)
                echo "  ${THREADS} threads | ${SPEEDUP}x" >> /app/profiling_results_omp/summary.txt
            fi
        fi
    done
fi
echo "" >> /app/profiling_results_omp/summary.txt

echo -e "${GREEN}OpenMP profiling complete! Results in /app/profiling_results_omp/ directory.${NC}"

# Show quick summary on screen
echo -e "${BLUE}Quick Results:${NC}"
if [ -f /app/profiling_results_omp/thread_scaling/strong_scaling_1threads.txt ]; then
    TIME_1=$(grep "Average Iteration Time:" /app/profiling_results_omp/thread_scaling/strong_scaling_1threads.txt | awk '{print $4}')
    if [[ $TIME_1 =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "  Single thread time: ${TIME_1} ms"
    fi
fi

for THREADS in "${THREAD_COUNTS[@]}"; do
    if [ $THREADS -ne 1 ] && [ -f /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt ]; then
        TIME_N=$(grep "Average Iteration Time:" /app/profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt | awk '{print $4}')
        
        # Calculate speedup
        if [[ $TIME_1 =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $TIME_N =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            SPEEDUP=$(echo "scale=2; $TIME_1 / $TIME_N" | bc)
            EFF=$(echo "scale=2; ($SPEEDUP / $THREADS) * 100" | bc)
            echo -e "  ${THREADS} threads time: ${TIME_N} ms (${SPEEDUP}x speedup, ${EFF}% efficiency)"
        elif [[ $TIME_N =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo -e "  ${THREADS} threads time: ${TIME_N} ms"
        fi
    fi
done

echo -e "${GREEN}See full details in /app/profiling_results_omp/summary.txt${NC}"