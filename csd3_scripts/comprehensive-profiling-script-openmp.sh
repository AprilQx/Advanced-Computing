# Load required modules for CSD3

module load cmake/latest
module load  intel/oneapi/2022.1.0/vtune/2022.1.0
PROJECT_DIR="/home/xx823/Advanced-Computing" 
# Create directories
RESULTS_DIR="/home/xx823/Advanced-Computing/profiling_results_omp_csd3"
mkdir -p ${RESULTS_DIR}/{vtune,thread_scaling,affinity,cache,scheduling}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting OpenMP profiling on CSD3 Icelake...${NC}"

# Get the number of available CPU cores
NUM_CORES=76  # Hard-coded for icelake
echo -e "${YELLOW}System has ${NUM_CORES} CPU cores available${NC}"

cd ${PROJECT_DIR}
# Create build directory
mkdir -p build
cd build

# Configure and build
echo -e "${BLUE}Configuring and building with Intel compiler...${NC}"

# First, build normal optimized version
CC=icc CXX=icpc cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-march=icelake-server -O3 -qopenmp"
make -j 76 heat_diffusion_openmp_benchmark

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

# Create OpenMP test program
echo -e "${YELLOW}Creating OpenMP test program...${NC}"
cat > openmp_test.c << EOF
#include <stdio.h>
#include <omp.h>
#include <sched.h>

int main() {
    printf("OpenMP version: %d\n", _OPENMP);
    printf("OpenMP max threads: %d\n", omp_get_max_threads());
    printf("OpenMP number of processors: %d\n", omp_get_num_procs());
    printf("OpenMP dynamic adjustment: %s\n", omp_get_dynamic() ? "enabled" : "disabled");
    
    // Print thread binding info
    #pragma omp parallel
    {
        #pragma omp single
        {
            printf("OpenMP num threads: %d\n", omp_get_num_threads());
        }
        
        printf("Thread %d of %d is running on processor %d\n", 
               omp_get_thread_num(), omp_get_num_threads(), sched_getcpu());
    }
    
    return 0;
}
EOF

icc -qopenmp openmp_test.c -o openmp_test
if [ -f "openmp_test" ]; then
    # Save output to file
    export OMP_NUM_THREADS=8  # Use a smaller number for clearer output
    ./openmp_test > ${RESULTS_DIR}/openmp_info.txt
    echo -e "${YELLOW}OpenMP information saved to ${RESULTS_DIR}/openmp_info.txt${NC}"
    # Show a brief summary
    grep "OpenMP" ${RESULTS_DIR}/openmp_info.txt
else
    echo -e "${YELLOW}Failed to compile OpenMP test program${NC}"
fi


#=====================
# 3. Thread Scaling Tests
#=====================
echo -e "${BLUE}Running thread scaling tests...${NC}"

# Build optimized version again
CC=icc CXX=icpc cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-march=icelake-server -O3 -qopenmp"
make -j 76 heat_diffusion_openmp_benchmark

# Test different thread counts
THREAD_COUNTS=(1 2 4 8 16 32 64 76)

# Fixed grid size test (strong scaling)
echo -e "${YELLOW}Running strong scaling tests...${NC}"
for THREADS in "${THREAD_COUNTS[@]}"; do
    echo -e "Testing with ${THREADS} threads..."
    export OMP_NUM_THREADS=$THREADS
    ./heat_diffusion_openmp_benchmark --width 2000 --height 2000 --frames 1000 --runs 1 --threads $THREADS > \
        ${RESULTS_DIR}/thread_scaling/strong_scaling_${THREADS}threads.txt 2>&1
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
        ${RESULTS_DIR}/thread_scaling/weak_scaling_${THREADS}threads.txt 2>&1
done

#=====================
# 4. Thread Affinity Tests
#=====================
echo -e "${BLUE}Running thread affinity tests...${NC}"

# Test different thread binding strategies with Intel OpenMP
OMP_BINDING_TYPES=("close" "spread" "master")
for BIND in "${OMP_BINDING_TYPES[@]}"; do
    echo -e "Testing with KMP_AFFINITY=${BIND}..."
    export OMP_NUM_THREADS=76
    export KMP_AFFINITY=$BIND
    
    ./heat_diffusion_openmp_benchmark --width 2000 --height 2000 --frames 50 --runs 1 > \
        ${RESULTS_DIR}/affinity/bind_${BIND}.txt 2>&1
done

# Additional test with explicit places
echo -e "Testing with explicit places..."
export OMP_NUM_THREADS=32
export OMP_PLACES=cores
export OMP_PROC_BIND=close
./heat_diffusion_openmp_benchmark --width 2000 --height 2000 --frames 50 --runs 1 > \
    ${RESULTS_DIR}/affinity/explicit_places.txt 2>&1

# Reset affinity settings
unset KMP_AFFINITY
unset OMP_PLACES
unset OMP_PROC_BIND

#=====================
# 5. Intel VTune Profiling (Alternative to Valgrind)
#=====================
echo -e "${BLUE}Running Intel VTune profiling...${NC}"

# Try to load VTune module
if module load intel/oneapi/2022.1.0/vtune/2022.1.0 &> /dev/null ; then
    # Clean up previous results and create fresh directories
    rm -rf ${RESULTS_DIR}/vtune/threading ${RESULTS_DIR}/vtune/hotspots ${RESULTS_DIR}/vtune/memory
    mkdir -p ${RESULTS_DIR}/vtune/threading ${RESULTS_DIR}/vtune/hotspots ${RESULTS_DIR}/vtune/memory
    
    # Threading analysis with user-mode sampling only
    echo -e "${YELLOW}Running threading analysis...${NC}"
    export OMP_NUM_THREADS=16  # Lower thread count for profiling
    vtune -collect-without-driver -collect threading -result-dir ${RESULTS_DIR}/vtune/threading ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 100 --runs 1
    
    # Hotspots analysis with user-mode sampling only
    echo -e "${YELLOW}Running hotspots analysis...${NC}"
    export OMP_NUM_THREADS=16
    vtune -collect-without-driver -collect hotspots -result-dir ${RESULTS_DIR}/vtune/hotspots ./heat_diffusion_openmp_benchmark --width 1000 --height 1000 --frames 100 --runs 1
    
    # Generate reports (only if data was collected)
    if [ -d "${RESULTS_DIR}/vtune/threading" ]; then
        vtune -report summary -result-dir ${RESULTS_DIR}/vtune/threading -format text -report-output ${RESULTS_DIR}/vtune/threading_summary.txt
    fi
    
    if [ -d "${RESULTS_DIR}/vtune/hotspots" ]; then
        vtune -report summary -result-dir ${RESULTS_DIR}/vtune/hotspots -format text -report-output ${RESULTS_DIR}/vtune/hotspots_summary.txt
        # Use the correct parameter for top-hotspots
        vtune -report hotspots -result-dir ${RESULTS_DIR}/vtune/hotspots -format text -report-output ${RESULTS_DIR}/vtune/top_hotspots.txt
    fi
else
    echo -e "${YELLOW}Intel VTune not available. Skipping VTune profiling.${NC}"
fi

#=====================
# 6. Cache Size Impact Test
#=====================
echo -e "${BLUE}Running cache size impact tests...${NC}"

# Test different grid sizes to see how they affect cache performance
for SIZE in 100 256 512 1024 2048 4096; do
    echo -e "${YELLOW}Testing grid size ${SIZE}x${SIZE}${NC}"
    
    # Use reduced iterations for larger grids
    if [ $SIZE -gt 2000 ]; then
        FRAMES=5
    elif [ $SIZE -gt 1000 ]; then
        FRAMES=10
    else 
        FRAMES=20
    fi
    
    export OMP_NUM_THREADS=1  # Single thread for clearer cache behavior
    ./heat_diffusion_openmp_benchmark --width $SIZE --height $SIZE --frames $FRAMES --runs 1 > \
        ${RESULTS_DIR}/cache/size_${SIZE}_single.txt 2>&1
        
    export OMP_NUM_THREADS=76  # Full parallelism
    ./heat_diffusion_openmp_benchmark --width $SIZE --height $SIZE --frames $FRAMES --runs 1 > \
        ${RESULTS_DIR}/cache/size_${SIZE}_parallel.txt 2>&1
done



#=====================
# 8. Scheduling Policy Tests
#=====================
echo -e "${BLUE}Running scheduling policy tests...${NC}"
# Test different OpenMP scheduling strategies
export OMP_NUM_THREADS=76
for SCHEDULE in "static" "dynamic" "guided" "auto"; do
    echo -e "${YELLOW}Testing with OMP_SCHEDULE=${SCHEDULE}${NC}"
    
    # Test with default chunk size
    export OMP_SCHEDULE=$SCHEDULE
    ./heat_diffusion_openmp_benchmark --width 2000 --height 2000 --frames 1000 --runs 1 > \
        ${RESULTS_DIR}/scheduling/schedule_${SCHEDULE}.txt 2>&1
    
    # Test with specific chunk size (except for auto)
    if [ "$SCHEDULE" != "auto" ]; then
        for CHUNK in 1 10 100; do
            export OMP_SCHEDULE="${SCHEDULE},${CHUNK}"
            ./heat_diffusion_openmp_benchmark --width 2000 --height 2000 --frames 1000 --runs 1 > \
                ${RESULTS_DIR}/scheduling/schedule_${SCHEDULE}_chunk${CHUNK}.txt 2>&1
        done
    fi
done

# Reset scheduling
unset OMP_SCHEDULE

#=====================
# 9. Generate Summary
#=====================
echo -e "${GREEN}Generating summary...${NC}"

echo "OPENMP BENCHMARK PROFILING SUMMARY (CSD3 ICELAKE)" > ${RESULTS_DIR}/summary.txt
echo "==========================================" >> ${RESULTS_DIR}/summary.txt
echo "" >> ${RESULTS_DIR}/summary.txt

# Add system information
echo "System Information:" >> ${RESULTS_DIR}/summary.txt
echo "  Architecture: Icelake (Intel Xeon 8360Y)" >> ${RESULTS_DIR}/summary.txt
echo "  Cores: ${NUM_CORES} per node" >> ${RESULTS_DIR}/summary.txt
echo "  Memory: 256GB/512GB per node" >> ${RESULTS_DIR}/summary.txt
echo "  Date: $(date)" >> ${RESULTS_DIR}/summary.txt
echo "" >> ${RESULTS_DIR}/summary.txt

# Add OpenMP environment info
if [ -f "${RESULTS_DIR}/openmp_info.txt" ]; then
    echo "OpenMP Environment:" >> ${RESULTS_DIR}/summary.txt
    grep "OpenMP" ${RESULTS_DIR}/openmp_info.txt >> ${RESULTS_DIR}/summary.txt
    echo "" >> ${RESULTS_DIR}/summary.txt
fi

# Add thread scaling results
echo "Thread Scaling Results:" >> ${RESULTS_DIR}/summary.txt
echo "Strong Scaling (Fixed Problem Size 2000x2000):" >> ${RESULTS_DIR}/summary.txt
for THREADS in "${THREAD_COUNTS[@]}"; do
    if [ -f "${RESULTS_DIR}/thread_scaling/strong_scaling_${THREADS}threads.txt" ]; then
        echo "  ${THREADS} threads:" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/thread_scaling/strong_scaling_${THREADS}threads.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Performance:" ${RESULTS_DIR}/thread_scaling/strong_scaling_${THREADS}threads.txt | grep -i "cell updates" >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt

echo "Weak Scaling (Problem Size Scaled with Thread Count):" >> ${RESULTS_DIR}/summary.txt
for THREADS in "${THREAD_COUNTS[@]}"; do
    if [ -f "${RESULTS_DIR}/thread_scaling/weak_scaling_${THREADS}threads.txt" ]; then
        BASE_SIZE=500
        SIZE=$(echo "sqrt($BASE_SIZE * $BASE_SIZE * $THREADS)" | bc)
        SIZE=${SIZE%.*} # Remove decimal part
        echo "  ${THREADS} threads (${SIZE}x${SIZE} grid):" >> ${RESULTS_DIR}/summary.txt
        grep "Grid Size:" ${RESULTS_DIR}/thread_scaling/weak_scaling_${THREADS}threads.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Average Iteration Time:" ${RESULTS_DIR}/thread_scaling/weak_scaling_${THREADS}threads.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Performance:" ${RESULTS_DIR}/thread_scaling/weak_scaling_${THREADS}threads.txt | grep -i "cell updates" >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt

# Add thread affinity results
echo "Thread Affinity Results:" >> ${RESULTS_DIR}/summary.txt
for BIND in "${OMP_BINDING_TYPES[@]}"; do
    if [ -f "${RESULTS_DIR}/affinity/bind_${BIND}.txt" ]; then
        echo "  KMP_AFFINITY=${BIND}:" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/affinity/bind_${BIND}.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Performance:" ${RESULTS_DIR}/affinity/bind_${BIND}.txt | grep -i "cell updates" >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done

if [ -f "${RESULTS_DIR}/affinity/explicit_places.txt" ]; then
    echo "  Explicit Places (OMP_PLACES=cores, OMP_PROC_BIND=close):" >> ${RESULTS_DIR}/summary.txt
    grep "Average Iteration Time:" ${RESULTS_DIR}/affinity/explicit_places.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    grep "Performance:" ${RESULTS_DIR}/affinity/explicit_places.txt | grep -i "cell updates" >> ${RESULTS_DIR}/summary.txt 2>/dev/null
fi
echo "" >> ${RESULTS_DIR}/summary.txt

# Add scheduling policy results
echo "Scheduling Policy Results:" >> ${RESULTS_DIR}/summary.txt
for SCHEDULE in "static" "dynamic" "guided" "auto"; do
    if [ -f "${RESULTS_DIR}/scheduling/schedule_${SCHEDULE}.txt" ]; then
        echo "  OMP_SCHEDULE=${SCHEDULE}:" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/scheduling/schedule_${SCHEDULE}.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Performance:" ${RESULTS_DIR}/scheduling/schedule_${SCHEDULE}.txt | grep -i "cell updates" >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
    
    # Add chunk size results
    if [ "$SCHEDULE" != "auto" ]; then
        for CHUNK in 1 10 100; do
            if [ -f "${RESULTS_DIR}/scheduling/schedule_${SCHEDULE}_chunk${CHUNK}.txt" ]; then
                echo "  OMP_SCHEDULE=${SCHEDULE},${CHUNK}:" >> ${RESULTS_DIR}/summary.txt
                grep "Average Iteration Time:" ${RESULTS_DIR}/scheduling/schedule_${SCHEDULE}_chunk${CHUNK}.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
                grep "Performance:" ${RESULTS_DIR}/scheduling/schedule_${SCHEDULE}_chunk${CHUNK}.txt | grep -i "cell updates" >> ${RESULTS_DIR}/summary.txt 2>/dev/null
            fi
        done
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt

# Add block size optimization results
echo "Block Size Optimization:" >> ${RESULTS_DIR}/summary.txt
echo "  Single Thread Results:" >> ${RESULTS_DIR}/summary.txt
for BLOCK in 8 16 32 64 128 256; do
    if [ -f "${RESULTS_DIR}/block_size/block_${BLOCK}_single.txt" ]; then
        echo "    Block Size ${BLOCK}:" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/block_size/block_${BLOCK}_single.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done

echo "  Parallel Results (76 threads):" >> ${RESULTS_DIR}/summary.txt
for BLOCK in 8 16 32 64 128 256; do
    if [ -f "${RESULTS_DIR}/block_size/block_${BLOCK}_parallel.txt" ]; then
        echo "    Block Size ${BLOCK}:" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/block_size/block_${BLOCK}_parallel.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt


# Add VTune summary if available
if [ -f "${RESULTS_DIR}/vtune/hotspots_summary.txt" ]; then
    echo "VTune Hotspots Summary:" >> ${RESULTS_DIR}/summary.txt
    grep -A 20 "Top Hotspots" ${RESULTS_DIR}/vtune/top_hotspots.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    echo "" >> ${RESULTS_DIR}/summary.txt
fi

if [ -f "${RESULTS_DIR}/vtune/threading_summary.txt" ]; then
    echo "VTune Threading Summary:" >> ${RESULTS_DIR}/summary.txt
    grep -A 10 "Threading Issue" ${RESULTS_DIR}/vtune/threading_summary.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    echo "" >> ${RESULTS_DIR}/summary.txt
fi

# Add cache size impact analysis
echo "Cache Size Impact (Different Grid Sizes):" >> ${RESULTS_DIR}/summary.txt
echo "  Single Thread:" >> ${RESULTS_DIR}/summary.txt
for SIZE in 100 256 512 1024 2048 4096; do
    if [ -f "${RESULTS_DIR}/cache/size_${SIZE}_single.txt" ]; then
        echo "    Grid size ${SIZE}x${SIZE}:" >> ${RESULTS_DIR}/summary.txt
        grep "Grid Size:" ${RESULTS_DIR}/cache/size_${SIZE}_single.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Average Iteration Time:" ${RESULTS_DIR}/cache/size_${SIZE}_single.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Memory Usage:" ${RESULTS_DIR}/cache/size_${SIZE}_single.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done

echo "  Full Parallelism (76 threads):" >> ${RESULTS_DIR}/summary.txt
for SIZE in 100 256 512 1024 2048 4096; do
    if [ -f "${RESULTS_DIR}/cache/size_${SIZE}_parallel.txt" ]; then
        echo "    Grid size ${SIZE}x${SIZE}:" >> ${RESULTS_DIR}/summary.txt
        grep "Grid Size:" ${RESULTS_DIR}/cache/size_${SIZE}_parallel.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Average Iteration Time:" ${RESULTS_DIR}/cache/size_${SIZE}_parallel.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Memory Usage:" ${RESULTS_DIR}/cache/size_${SIZE}_parallel.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt

# Calculate parallel efficiency
echo "Parallel Efficiency:" >> ${RESULTS_DIR}/summary.txt
if [ -f "${RESULTS_DIR}/thread_scaling/strong_scaling_1threads.txt" ]; then
    SINGLE_TIME=$(grep "Average Iteration Time:" ${RESULTS_DIR}/thread_scaling/strong_scaling_1threads.txt | awk '{print $4}')
    
    for THREADS in "${THREAD_COUNTS[@]}"; do
        if [ $THREADS -ne 1 ] && [ -f "${RESULTS_DIR}/thread_scaling/strong_scaling_${THREADS}threads.txt" ]; then
            THREAD_TIME=$(grep "Average Iteration Time:" ${RESULTS_DIR}/thread_scaling/strong_scaling_${THREADS}threads.txt | awk '{print $4}')
            
            # Calculate efficiency if we have valid numbers
            if [[ $SINGLE_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $THREAD_TIME =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                SPEEDUP=$(echo "scale=2; $SINGLE_TIME / $THREAD_TIME" | bc)
                EFF=$(echo "scale=2; ($SPEEDUP / $THREADS) * 100" | bc)
                echo "  ${THREADS} threads: speedup ${SPEEDUP}x, efficiency ${EFF}%" >> ${RESULTS_DIR}/summary.txt
            fi
        fi
    done
fi
echo "" >> ${RESULTS_DIR}/summary.txt

echo -e "${GREEN}OpenMP profiling complete! Results in ${RESULTS_DIR}/ directory.${NC}"

# Show quick summary on screen
echo -e "${BLUE}Quick Results:${NC}"
if [ -f "${RESULTS_DIR}/thread_scaling/strong_scaling_1threads.txt" ]; then
    TIME_1=$(grep "Average Iteration Time:" ${RESULTS_DIR}/thread_scaling/strong_scaling_1threads.txt | awk '{print $4}')
    if [[ $TIME_1 =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "  Single thread time: ${TIME_1} ms"
    fi
fi

for THREADS in "${THREAD_COUNTS[@]}"; do
    if [ $THREADS -ne 1 ] && [ -f "${RESULTS_DIR}/thread_scaling/strong_scaling_${THREADS}threads.txt" ]; then
        TIME_N=$(grep "Average Iteration Time:" ${RESULTS_DIR}/thread_scaling/strong_scaling_${THREADS}threads.txt | awk '{print $4}')
        
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

echo -e "${GREEN}See full details in ${RESULTS_DIR}/summary.txt${NC}"