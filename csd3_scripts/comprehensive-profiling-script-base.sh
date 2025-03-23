# Create directories
RESULTS_DIR="./profiling_results_base_csd3"
mkdir -p ${RESULTS_DIR}/{gprof,valgrind}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting profiling on CSD3 Icelake...${NC}"

# Create build directory
mkdir -p build
cd build

# Configure and build with Intel compiler
echo -e "${BLUE}Configuring and building with Intel compiler...${NC}"

# First, build normal optimized version
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx -DCMAKE_CXX_FLAGS="-march=icelake-server -O3"
make -j 76

# Build version with gprof profiling
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx -DCMAKE_CXX_FLAGS="-march=icelake-server -pg"
make -j 76

#=====================
# 1. GPROF Profiling
#=====================
echo -e "${BLUE}Running gprof profiling...${NC}"

# Run with small grid for quick profiling
./heat_diffusion_benchmark --size 100 --iterations 100

# Generate gprof report
gprof ./heat_diffusion_benchmark gmon.out > ${RESULTS_DIR}/gprof/gprof_report.txt

#=====================
# 2. VALGRIND Tools
#=====================
echo -e "${BLUE}Running Valgrind profiling...${NC}"

# Load valgrind module if available on CSD3
module load valgrind/latest || echo "Valgrind module not found, using system valgrind if available"

# Return to optimized build for other profiling
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx -DCMAKE_CXX_FLAGS="-march=icelake-server -O3"
make -j 76

# Check if valgrind is available
if command -v valgrind &> /dev/null; then
    # 2.1 Cachegrind (cache profiling)
    echo -e "${YELLOW}Running cachegrind...${NC}"
    valgrind --tool=cachegrind ./heat_diffusion_benchmark --size 100 --iterations 100 > ${RESULTS_DIR}/valgrind/cachegrind_output.txt

    # Find the cachegrind output file
    CACHEGRIND_FILE=$(ls cachegrind.out.*)
    if [ -n "$CACHEGRIND_FILE" ]; then
        cg_annotate $CACHEGRIND_FILE > ${RESULTS_DIR}/valgrind/cachegrind_report.txt
    fi

    # 2.2 Callgrind (call graph generation)
    echo -e "${YELLOW}Running callgrind...${NC}"
    valgrind --tool=callgrind ./heat_diffusion_benchmark --size 100 --iterations 100 > ${RESULTS_DIR}/valgrind/callgrind_output.txt

    # Find the callgrind output file
    CALLGRIND_FILE=$(ls callgrind.out.*)
    if [ -n "$CALLGRIND_FILE" ]; then
        callgrind_annotate $CALLGRIND_FILE > ${RESULTS_DIR}/valgrind/callgrind_report.txt
    fi

    # 2.3 Massif (heap profiling)
    echo -e "${YELLOW}Running massif...${NC}"
    valgrind --tool=massif ./heat_diffusion_benchmark --size 500 --iterations 100 > ${RESULTS_DIR}/valgrind/massif_output.txt

    # Find the massif output file
    MASSIF_FILE=$(ls massif.out.*)
    if [ -n "$MASSIF_FILE" ]; then
        ms_print $MASSIF_FILE > ${RESULTS_DIR}/valgrind/massif_report.txt
    fi
else
    echo -e "${YELLOW}Valgrind not available on this system. Skipping Valgrind profiling.${NC}"
fi

#=====================
# 3. Intel VTune Profiling (Alternative to Valgrind on Intel systems)
#=====================
echo -e "${BLUE}Running Intel VTune profiling...${NC}"

# Try to load VTune module
if module load vtune &> /dev/null || module load intel/vtune/latest &> /dev/null; then
    mkdir -p ${RESULTS_DIR}/vtune
    
    # Hotspots analysis
    vtune -collect hotspots -result-dir ${RESULTS_DIR}/vtune/hotspots ./heat_diffusion_benchmark --size 100 --iterations 100
    
    # Memory access analysis
    vtune -collect memory-access -result-dir ${RESULTS_DIR}/vtune/memory ./heat_diffusion_benchmark --size 100 --iterations 100
    
    # Generate reports
    vtune -report summary -result-dir ${RESULTS_DIR}/vtune/hotspots -format text -report-output ${RESULTS_DIR}/vtune/hotspots_summary.txt
    vtune -report summary -result-dir ${RESULTS_DIR}/vtune/memory -format text -report-output ${RESULTS_DIR}/vtune/memory_summary.txt
else
    echo -e "${YELLOW}Intel VTune not available. Skipping VTune profiling.${NC}"
fi

#=====================
# 4. Performance Scaling Tests
#=====================
echo -e "${BLUE}Running performance scaling tests...${NC}"

# Test different grid sizes
for SIZE in 100 200 500 1000 2000; do
    echo -e "${YELLOW}Testing grid size ${SIZE}x${SIZE}${NC}"
    
    # Adjust iterations for larger grids
    if [ $SIZE -gt 1000 ]; then
        ITER=50
    elif [ $SIZE -gt 500 ]; then
        ITER=100
    else 
        ITER=200
    fi
    
    # Measure time and output
    ./heat_diffusion_benchmark --size $SIZE --iterations $ITER > ${RESULTS_DIR}/benchmark_${SIZE}.txt 2>&1
done

#=====================
# 5. Generate Summary
#=====================
echo -e "${GREEN}Generating summary...${NC}"

echo "COMPREHENSIVE PROFILING SUMMARY (CSD3 ICELAKE)" > ${RESULTS_DIR}/summary.txt
echo "=======================================" >> ${RESULTS_DIR}/summary.txt
echo "" >> ${RESULTS_DIR}/summary.txt

# Add system information
echo "System Information:" >> ${RESULTS_DIR}/summary.txt
echo "  Architecture: Icelake (Intel Xeon 8360Y)" >> ${RESULTS_DIR}/summary.txt
echo "  Cores: 76 per node" >> ${RESULTS_DIR}/summary.txt
echo "  Memory: 256GB/512GB per node" >> ${RESULTS_DIR}/summary.txt
echo "  Date: $(date)" >> ${RESULTS_DIR}/summary.txt
echo "" >> ${RESULTS_DIR}/summary.txt

# Add gprof summary
if [ -f "${RESULTS_DIR}/gprof/gprof_report.txt" ]; then
    echo "Top functions from gprof:" >> ${RESULTS_DIR}/summary.txt
    head -n 20 ${RESULTS_DIR}/gprof/gprof_report.txt >> ${RESULTS_DIR}/summary.txt
    echo "" >> ${RESULTS_DIR}/summary.txt
fi

# Add cache summary from cachegrind if available
if [ -f "${RESULTS_DIR}/valgrind/cachegrind_report.txt" ]; then
    echo "Cache statistics (cachegrind):" >> ${RESULTS_DIR}/summary.txt
    grep "I   refs" ${RESULTS_DIR}/valgrind/cachegrind_report.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    grep "D   refs" ${RESULTS_DIR}/valgrind/cachegrind_report.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    grep "D1  miss rate" ${RESULTS_DIR}/valgrind/cachegrind_report.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    grep "LL miss rate" ${RESULTS_DIR}/valgrind/cachegrind_report.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    echo "" >> ${RESULTS_DIR}/summary.txt
fi

# Add memory summary from massif if available
if [ -f "${RESULTS_DIR}/valgrind/massif_report.txt" ]; then
    echo "Memory usage (massif):" >> ${RESULTS_DIR}/summary.txt
    grep "peak:" ${RESULTS_DIR}/valgrind/massif_report.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    echo "" >> ${RESULTS_DIR}/summary.txt
fi

# Add VTune summary if available
if [ -f "${RESULTS_DIR}/vtune/hotspots_summary.txt" ]; then
    echo "Intel VTune Hotspots Summary:" >> ${RESULTS_DIR}/summary.txt
    head -n 30 ${RESULTS_DIR}/vtune/hotspots_summary.txt >> ${RESULTS_DIR}/summary.txt
    echo "" >> ${RESULTS_DIR}/summary.txt
fi

# Add performance for different grid sizes
echo "Performance by grid size:" >> ${RESULTS_DIR}/summary.txt
for SIZE in 100 200 500 1000 2000; do
    if [ -f "${RESULTS_DIR}/benchmark_${SIZE}.txt" ]; then
        echo "Grid size ${SIZE}x${SIZE}:" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time" ${RESULTS_DIR}/benchmark_${SIZE}.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Performance:" ${RESULTS_DIR}/benchmark_${SIZE}.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Memory Usage:" ${RESULTS_DIR}/benchmark_${SIZE}.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        echo "" >> ${RESULTS_DIR}/summary.txt
    fi
done

echo -e "${GREEN}Profiling complete! Results in ${RESULTS_DIR}/ directory.${NC}"