#!/bin/bash

# Profiling script to run INSIDE a Docker container
# No Docker commands - just profiling tools

# Create directories
mkdir -p /app/profiling_results_optimised/{gprof,valgrind}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting profiling inside container...${NC}"

# Create build directory
cd /app
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
./heat_diffusion_optimized_benchmark --size 100 --iterations 100

# Generate gprof report
gprof ./heat_diffusion_optimized_benchmark gmon.out > /app/profiling_results_optimised/gprof/gprof_report.txt

#=====================
# 2. VALGRIND Tools
#=====================
echo -e "${BLUE}Running Valgrind profiling...${NC}"

# Return to optimized build for other profiling
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4

# 2.1 Cachegrind (cache profiling)
echo -e "${YELLOW}Running cachegrind...${NC}"
valgrind --tool=cachegrind ./heat_diffusion_optimized_benchmark --size 100 --iterations 100 > /app/profiling_results_optimised/valgrind/cachegrind_output.txt

# Find the cachegrind output file
CACHEGRIND_FILE=$(ls cachegrind.out.*)
cg_annotate $CACHEGRIND_FILE > /app/profiling_results_optimised/valgrind/cachegrind_report.txt

# 2.2 Callgrind (call graph generation)
echo -e "${YELLOW}Running callgrind...${NC}"
valgrind --tool=callgrind ./heat_diffusion_optimized_benchmark --size 100 --iterations 100 > /app/profiling_results_optimised/valgrind/callgrind_output.txt

# Find the callgrind output file
CALLGRIND_FILE=$(ls callgrind.out.*)
callgrind_annotate $CALLGRIND_FILE > /app/profiling_results_optimised/valgrind/callgrind_report.txt

# 2.3 Massif (heap profiling)
echo -e "${YELLOW}Running massif...${NC}"
valgrind --tool=massif ./heat_diffusion_optimized_benchmark --size 500 --iterations 100 > /app/profiling_results_optimised/valgrind/massif_output.txt

# Find the massif output file
MASSIF_FILE=$(ls massif.out.*)
ms_print $MASSIF_FILE > /app/profiling_results_optimised/valgrind/massif_report.txt


#=====================
# 3. Performance Scaling Tests
#=====================
echo -e "${BLUE}Running performance scaling tests...${NC}"

# Test different grid sizes
for SIZE in 100 200 500 1000; do
    echo -e "${YELLOW}Testing grid size ${SIZE}x${SIZE}${NC}"
    
    # Adjust iterations for larger grids
    if [ $SIZE -gt 500 ]; then
        ITER=100
    else 
        ITER=100
    fi
    
    # Measure time and output
    valgrind --tool=cachegrind ./heat_diffusion_optimized_benchmark --size $SIZE --iterations $ITER > \
        /app/profiling_results_optimised/valgrind/benchmark_${SIZE}.txt 2>&1
done

#=====================
# 4. Generate Summary
#=====================
echo -e "${GREEN}Generating summary...${NC}"

echo "COMPREHENSIVE PROFILING SUMMARY" > /app/profiling_results_optimised/summary.txt
echo "===============================" >> /app/profiling_results_optimised/summary.txt
echo "" >> /app/profiling_results_optimised/summary.txt

# Add gprof summary
echo "Top functions from gprof:" >> /app/profiling_results_optimised/summary.txt
head -n 20 /app/profiling_results_optimised/gprof/gprof_report.txt >> /app/profiling_results_optimised/summary.txt
echo "" >> /app/profiling_results_optimised/summary.txt

# Add cache summary
echo "Cache statistics (cachegrind):" >> /app/profiling_results_optimised/summary.txt
grep "I   refs" /app/profiling_results_optimised/valgrind/cachegrind_report.txt >> /app/profiling_results_optimised/summary.txt 2>/dev/null
grep "D   refs" /app/profiling_results_optimised/valgrind/cachegrind_report.txt >> /app/profiling_results_optimised/summary.txt 2>/dev/null
grep "D1  miss rate" /app/profiling_results_optimised/valgrind/cachegrind_report.txt >> /app/profiling_results_optimised/summary.txt 2>/dev/null
grep "LL miss rate" /app/profiling_results_optimised/valgrind/cachegrind_report.txt >> /app/profiling_results_optimised/summary.txt 2>/dev/null
echo "" >> /app/profiling_results_optimised/summary.txt

# Add memory summary
echo "Memory usage (massif):" >> /app/profiling_results_optimised/summary.txt
grep "peak:" /app/profiling_results_optimised/valgrind/massif_report.txt >> /app/profiling_results_optimised/summary.txt 2>/dev/null
echo "" >> /app/profiling_results_optimised/summary.txt

# Add performance for different grid sizes
echo "Performance by grid size:" >> /app/profiling_results_optimised/summary.txt
for SIZE in 100 200 500 1000; do
    echo "Grid size ${SIZE}x${SIZE}:" >> /app/profiling_results_optimised/summary.txt
    grep "Average Iteration Time" /app/profiling_results_optimised/valgrind/benchmark_${SIZE}.txt >> /app/profiling_results_optimised/summary.txt 2>/dev/null
    grep "Performance:" /app/profiling_results_optimised/valgrind/benchmark_${SIZE}.txt >> /app/profiling_results_optimised/summary.txt 2>/dev/null
    grep "Memory Usage:" /app/profiling_results_optimised/valgrind/benchmark_${SIZE}.txt >> /app/profiling_results_optimised/summary.txt 2>/dev/null
    echo "" >> /app/profiling_results_optimised/summary.txt
done

echo -e "${GREEN}Profiling complete! Results in /app/profiling_results_optimised/ directory.${NC}"