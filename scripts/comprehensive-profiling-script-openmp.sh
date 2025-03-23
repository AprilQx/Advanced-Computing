#!/bin/bash

# Profiling script for OpenMP heat diffusion benchmark
# Creates comprehensive performance analysis for threaded execution

# Create directories
mkdir -p profiling_results_omp/{gprof,valgrind,thread_scaling,cache}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting OpenMP profiling...${NC}"

# Create build directory
mkdir -p build
cd build

# Configure and build
echo -e "${BLUE}Configuring and building...${NC}"

# First, build normal optimized version
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4

# Build version with gprof profiling
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_CXX_FLAGS="-pg"
make -j4 

#=====================
# 1. GPROF Profiling
#=====================
echo -e "${BLUE}Running gprof profiling...${NC}"

# Run with small grid for quick profiling
./heat_diffusion_openmp_benchmark --width 500 --height 500 --frames 100 --runs 1

# Generate gprof report
gprof ./heat_diffusion_openmp_benchmark gmon.out > ../profiling_results_omp/gprof/gprof_report.txt

#=====================
# 2. Thread Scaling Tests
#=====================
echo -e "${BLUE}Running thread scaling tests...${NC}"

# Get the number of available CPU cores
NUM_CORES=$(nproc)
echo -e "${YELLOW}System has ${NUM_CORES} CPU cores available${NC}"

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
    ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 100 --runs 1 --threads $THREADS > \
        ../profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt
done

# Increasing grid size with thread count (weak scaling)
echo -e "${YELLOW}Running weak scaling tests...${NC}"
for THREADS in "${THREAD_COUNTS[@]}"; do
    # Scale problem size with thread count - keep work per thread constant
    BASE_SIZE=500
    SIZE=$(echo "sqrt($BASE_SIZE * $BASE_SIZE * $THREADS)" | bc)
    
    echo -e "Testing with ${THREADS} threads, grid size ${SIZE}x${SIZE}..."
    export OMP_NUM_THREADS=$THREADS
    ./heat_diffusion_openmp_benchmark --width $SIZE --height $SIZE --frames 100 --runs 1 --threads $THREADS > \
        ../profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt
done

#=====================
# 3. VALGRIND Tools
#=====================
echo -e "${BLUE}Running Valgrind profiling...${NC}"

# Reset OMP_NUM_THREADS to use all cores for Valgrind tests
export OMP_NUM_THREADS=$NUM_CORES

# Return to optimized build for other profiling
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4

# 3.1 Cachegrind (cache profiling)
echo -e "${YELLOW}Running cachegrind...${NC}"
valgrind --tool=cachegrind ./heat_diffusion_openmp_benchmark --width 100 --height 100 --frames 100 --runs 1 > \
    ../profiling_results_omp/valgrind/cachegrind_output.txt 2>&1

# Find the cachegrind output file
CACHEGRIND_FILE=$(ls cachegrind.out.*)
if [ -n "$CACHEGRIND_FILE" ]; then
    cg_annotate $CACHEGRIND_FILE > ../profiling_results_omp/valgrind/cachegrind_report.txt
fi

# 3.2 Callgrind (call graph generation)
echo -e "${YELLOW}Running callgrind...${NC}"
valgrind --tool=callgrind ./heat_diffusion_openmp_benchmark --width 100 --height 100 --frames 100 --runs 1 > \
    ../profiling_results_omp/valgrind/callgrind_output.txt 2>&1

# Find the callgrind output file
CALLGRIND_FILE=$(ls callgrind.out.*)
if [ -n "$CALLGRIND_FILE" ]; then
    callgrind_annotate $CALLGRIND_FILE > ../profiling_results_omp/valgrind/callgrind_report.txt
fi

# 3.3 Massif (heap profiling)
echo -e "${YELLOW}Running massif...${NC}"
valgrind --tool=massif ./heat_diffusion_openmp_benchmark --width 100 --height 100 --frames 100 --runs 1 > \
    ../profiling_results_omp/valgrind/massif_output.txt 2>&1

# Find the massif output file
MASSIF_FILE=$(ls massif.out.*)
if [ -n "$MASSIF_FILE" ]; then
    ms_print $MASSIF_FILE > ../profiling_results_omp/valgrind/massif_report.txt
fi

#=====================
# 4. Cache Size Impact Test
#=====================
echo -e "${BLUE}Running cache size impact tests...${NC}"

# Test different grid sizes to see how they affect cache performance
for SIZE in 100 256 512 1024 2048; do
    echo -e "${YELLOW}Testing grid size ${SIZE}x${SIZE}${NC}"
    
    # Use reduced iterations for larger grids
    if [ $SIZE -gt 1000 ]; then
        FRAMES=20
    else 
        FRAMES=50
    fi
    
    export OMP_NUM_THREADS=$NUM_CORES  # Use all cores
    ./heat_diffusion_openmp_benchmark --width $SIZE --height $SIZE --frames $FRAMES --runs 1 > \
        ../profiling_results_omp/cache/size_${SIZE}.txt
done

#=====================
# 5. NUMA Effects Test (if applicable)
#=====================
echo -e "${BLUE}Checking for NUMA architecture...${NC}"

# Only run NUMA tests if numactl is available and system has multiple NUMA nodes
if command -v numactl &> /dev/null && numactl --hardware | grep -q "available"; then
    NUMA_NODES=$(numactl --hardware | grep "available" | awk '{print $2}')
    
    if [ "$NUMA_NODES" -gt 1 ]; then
        echo -e "${YELLOW}Detected NUMA system with ${NUMA_NODES} nodes. Running NUMA tests...${NC}"
        mkdir -p ../profiling_results_omp/numa
        
        # Test with threads restricted to each NUMA node
        for NODE in $(seq 0 $((NUMA_NODES-1))); do
            echo -e "Testing with threads restricted to NUMA node ${NODE}..."
            numactl --cpunodebind=$NODE ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 100 --runs 1 > \
                ../profiling_results_omp/numa/node${NODE}.txt
        done
        
        # Test with threads on all nodes but memory allocation on node 0
        echo -e "Testing with memory on node 0, computation on all nodes..."
        numactl --membind=0 ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 100 --runs 1 > \
            ../profiling_results_omp/numa/mem_node0_cpu_all.txt
        
        # Test with interleaved memory allocation
        echo -e "Testing with interleaved memory allocation..."
        numactl --interleave=all ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 100 --runs 1 > \
            ../profiling_results_omp/numa/interleaved.txt
    else
        echo -e "${YELLOW}This is not a NUMA system or only has one NUMA node. Skipping NUMA tests.${NC}"
    fi
else
    echo -e "${YELLOW}NUMA tools not available. Skipping NUMA tests.${NC}"
fi

#=====================
# 6. Generate Summary
#=====================
echo -e "${GREEN}Generating summary...${NC}"
cd ..

echo "OPENMP BENCHMARK PROFILING SUMMARY" > profiling_results_omp/summary.txt
echo "=================================" >> profiling_results_omp/summary.txt
echo "" >> profiling_results_omp/summary.txt

# Add thread scaling results
echo "Thread Scaling Results:" >> profiling_results_omp/summary.txt
echo "Strong Scaling (Fixed Problem Size):" >> profiling_results_omp/summary.txt
for THREADS in "${THREAD_COUNTS[@]}"; do
    if [ -f profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt ]; then
        echo "  ${THREADS} threads:" >> profiling_results_omp/summary.txt
        grep "Average Iteration Time:" profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt >> profiling_results_omp/summary.txt 2>/dev/null
        grep "Performance:" profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt | grep -i "cell updates" >> profiling_results_omp/summary.txt 2>/dev/null
    fi
done
echo "" >> profiling_results_omp/summary.txt

echo "Weak Scaling (Problem Size Scaled with Thread Count):" >> profiling_results_omp/summary.txt
for THREADS in "${THREAD_COUNTS[@]}"; do
    if [ -f profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt ]; then
        echo "  ${THREADS} threads:" >> profiling_results_omp/summary.txt
        grep "Grid Size:" profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt >> profiling_results_omp/summary.txt 2>/dev/null
        grep "Average Iteration Time:" profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt >> profiling_results_omp/summary.txt 2>/dev/null
        grep "Performance:" profiling_results_omp/thread_scaling/weak_scaling_${THREADS}threads.txt | grep -i "cell updates" >> profiling_results_omp/summary.txt 2>/dev/null
    fi
done
echo "" >> profiling_results_omp/summary.txt

# Add parallel efficiency calculation
echo "Parallel Efficiency:" >> profiling_results_omp/summary.txt

# Find the single-thread timing
if [ -f profiling_results_omp/thread_scaling/strong_scaling_1threads.txt ]; then
    SINGLE_THREAD_TIME=$(grep "Average Iteration Time:" profiling_results_omp/thread_scaling/strong_scaling_1threads.txt | awk '{print $4}')
    
    for THREADS in "${THREAD_COUNTS[@]}"; do
        if [ $THREADS -ne 1 ] && [ -f profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt ]; then
            THREAD_TIME=$(grep "Average Iteration Time:" profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt | awk '{print $4}')
            
            # Calculate efficiency if we have valid numbers
            if [[ $SINGLE_THREAD_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $THREAD_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                EFF=$(echo "scale=2; ($SINGLE_THREAD_TIME / ($THREADS * $THREAD_TIME)) * 100" | bc)
                echo "  ${THREADS} threads efficiency: ${EFF}%" >> profiling_results_omp/summary.txt
            fi
        fi
    done
fi
echo "" >> profiling_results_omp/summary.txt

# Add gprof summary
echo "Top functions from gprof:" >> profiling_results_omp/summary.txt
head -n 20 profiling_results_omp/gprof/gprof_report.txt >> profiling_results_omp/summary.txt 2>/dev/null
echo "" >> profiling_results_omp/summary.txt

# Add cache statistics
echo "Cache statistics (cachegrind):" >> profiling_results_omp/summary.txt
if [ -f profiling_results_omp/valgrind/cachegrind_report.txt ]; then
    grep "I   refs" profiling_results_omp/valgrind/cachegrind_report.txt >> profiling_results_omp/summary.txt 2>/dev/null
    grep "D   refs" profiling_results_omp/valgrind/cachegrind_report.txt >> profiling_results_omp/summary.txt 2>/dev/null
    grep "D1  miss rate" profiling_results_omp/valgrind/cachegrind_report.txt >> profiling_results_omp/summary.txt 2>/dev/null
    grep "LL miss rate" profiling_results_omp/valgrind/cachegrind_report.txt >> profiling_results_omp/summary.txt 2>/dev/null
fi
echo "" >> profiling_results_omp/summary.txt

# Add memory usage information
echo "Memory usage (massif):" >> profiling_results_omp/summary.txt
if [ -f profiling_results_omp/valgrind/massif_report.txt ]; then
    grep "peak:" profiling_results_omp/valgrind/massif_report.txt >> profiling_results_omp/summary.txt 2>/dev/null
fi
echo "" >> profiling_results_omp/summary.txt

# Add cache size impact analysis
echo "Cache Size Impact (Different Grid Sizes):" >> profiling_results_omp/summary.txt
for SIZE in 100 256 512 1024 2048; do
    if [ -f profiling_results_omp/cache/size_${SIZE}.txt ]; then
        echo "  Grid size ${SIZE}x${SIZE}:" >> profiling_results_omp/summary.txt
        grep "Grid Size:" profiling_results_omp/cache/size_${SIZE}.txt >> profiling_results_omp/summary.txt 2>/dev/null
        grep "Average Iteration Time:" profiling_results_omp/cache/size_${SIZE}.txt >> profiling_results_omp/summary.txt 2>/dev/null
        grep "Memory Usage:" profiling_results_omp/cache/size_${SIZE}.txt >> profiling_results_omp/summary.txt 2>/dev/null
    fi
done
echo "" >> profiling_results_omp/summary.txt

# Add NUMA effects summary if applicable
if [ -d profiling_results_omp/numa ]; then
    echo "NUMA Effects:" >> profiling_results_omp/summary.txt
    
    # Compare performances across NUMA configurations
    for FILE in profiling_results_omp/numa/*.txt; do
        if [ -f "$FILE" ]; then
            FILENAME=$(basename "$FILE" .txt)
            echo "  Configuration: ${FILENAME}" >> profiling_results_omp/summary.txt
            grep "Average Iteration Time:" "$FILE" >> profiling_results_omp/summary.txt 2>/dev/null
            grep "Performance:" "$FILE" | grep -i "cell updates" >> profiling_results_omp/summary.txt 2>/dev/null
        fi
    done
    echo "" >> profiling_results_omp/summary.txt
fi

# Calculate speedup graphs
echo "Speedup Analysis:" >> profiling_results_omp/summary.txt
if [ -f profiling_results_omp/thread_scaling/strong_scaling_1threads.txt ]; then
    SINGLE_TIME=$(grep "Average Iteration Time:" profiling_results_omp/thread_scaling/strong_scaling_1threads.txt | awk '{print $4}')
    
    echo "  Thread count | Speedup (vs 1 thread)" >> profiling_results_omp/summary.txt
    echo "  -------------|----------------------" >> profiling_results_omp/summary.txt
    
    for THREADS in "${THREAD_COUNTS[@]}"; do
        if [ -f profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt ]; then
            THREAD_TIME=$(grep "Average Iteration Time:" profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt | awk '{print $4}')
            
            # Calculate speedup if we have valid numbers
            if [[ $SINGLE_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $THREAD_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                SPEEDUP=$(echo "scale=2; $SINGLE_TIME / $THREAD_TIME" | bc)
                echo "  ${THREADS} threads | ${SPEEDUP}x" >> profiling_results_omp/summary.txt
            fi
        fi
    done
fi
echo "" >> profiling_results_omp/summary.txt

echo -e "${GREEN}OpenMP profiling complete! Results in profiling_results_omp/ directory.${NC}"

# Show quick summary on screen
echo -e "${BLUE}Quick Results:${NC}"
if [ -f profiling_results_omp/thread_scaling/strong_scaling_1threads.txt ]; then
    TIME_1=$(grep "Average Iteration Time:" profiling_results_omp/thread_scaling/strong_scaling_1threads.txt | awk '{print $4}')
    echo -e "  Single thread time: ${TIME_1} ms"
fi

for THREADS in "${THREAD_COUNTS[@]}"; do
    if [ $THREADS -ne 1 ] && [ -f profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt ]; then
        TIME=$(grep "Average Iteration Time:" profiling_results_omp/thread_scaling/strong_scaling_${THREADS}threads.txt | awk '{print $4}')
        
        # Calculate speedup
        if [[ $TIME_1 =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $TIME =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            SPEEDUP=$(echo "scale=2; $TIME_1 / $TIME" | bc)
            echo -e "  ${THREADS} threads time: ${TIME} ms (${SPEEDUP}x speedup)"
        else
            echo -e "  ${THREADS} threads time: ${TIME} ms"
        fi
    fi
done

echo -e "${GREEN}See full details in profiling_results_omp/summary.txt${NC}"