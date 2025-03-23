module load  intel/oneapi/2022.1.0/vtune/2022.1.0
PROJECT_DIR="/home/xx823/Advanced-Computing" 
# Create directories
RESULTS_DIR="/home/xx823/Advanced-Computing/profiling_results_optimised_csd3"


# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting profiling on CSD3 Icelake...${NC}"
cd ${PROJECT_DIR}
# Create build directory
mkdir -p build
cd build

# Configure and build with Intel compiler
echo -e "${BLUE}Configuring and building with Intel compiler...${NC}"

# First, build normal optimized version
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx -DCMAKE_CXX_FLAGS="-march=icelake-server -O3"
make -j 76


#=====================
# 3. Intel VTune Profiling (Alternative to Valgrind on Intel systems)
#=====================
echo -e "${BLUE}Running Intel VTune profiling...${NC}"

# Try to load VTune module
if module load intel/oneapi/2022.1.0/vtune/2022.1.0  &> /dev/null ; then
    mkdir -p ${RESULTS_DIR}/vtune
    
    # Hotspots analysis
    vtune -collect hotspots -result-dir ${RESULTS_DIR}/vtune/hotspots ./heat_diffusion_optimized_benchmark_v2 --size 1000 --iterations 1000
    
    # Memory access analysis
    vtune -collect memory-access -result-dir ${RESULTS_DIR}/vtune/memory ./heat_diffusion_optimized_benchmark_v2 --size 1000 --iterations 1000
    
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
    ./heat_diffusion_optimized_benchmark_v2 --size $SIZE --iterations $ITER > ${RESULTS_DIR}/benchmark_${SIZE}.txt 2>&1
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