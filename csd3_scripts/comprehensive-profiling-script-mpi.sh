
module purge
module load rhel8/default-icl
module load intel/oneapi/2022.1.0/itac
PROJECT_DIR="/home/xx823/Advanced-Computing" 
# Create directories
RESULTS_DIR="/home/xx823/Advanced-Computing/profiling_results_mpi_csd3"
mkdir -p ${RESULTS_DIR}/{scaling,communication,placement}



# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting MPI profiling on CSD3 Icelake...${NC}"
cd ${PROJECT_DIR}
# Create build directory
mkdir -p build
cd build

# Configure and build
echo -e "${BLUE}Configuring and building with Intel MPI...${NC}"

# Build with normal optimization
CC=mpiicc CXX=mpiicpc cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-march=icelake-server -O3"
make -j 76 heat_diffusion_mpi_benchmark

# Verify the executable exists
if [ ! -f "heat_diffusion_mpi_benchmark" ]; then
    echo -e "${YELLOW}Error: heat_diffusion_mpi_benchmark was not built correctly${NC}"
    echo "Please check your build configuration and try again."
    exit 1
fi


#=====================
# 2. Intel Trace Analyzer and Collector (ITAC) profiling
#=====================
echo -e "${BLUE}Running Intel Trace Analyzer profiling...${NC}"

# Return to optimized build
CC=mpiicc CXX=mpiicpc cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-march=icelake-server -O3"
make -j 76 heat_diffusion_mpi_benchmark

# Try to load ITAC module
if module load intel/oneapi/2022.1.0/itac &> /dev/null; then
    mkdir -p ${RESULTS_DIR}/itac
    
    # Run with ITAC tracing
    mpirun -trace -n 16 ./heat_diffusion_mpi_benchmark --size 500 --iterations 50 --runs 1
    
    # Generate trace summary
    if [ -f *.stf ]; then
        traceanalyzer -config=profile *.stf -o ${RESULTS_DIR}/itac/trace_profile.txt
    fi
else
    echo -e "${YELLOW}Intel Trace Analyzer not available. Skipping ITAC profiling.${NC}"
fi

#=====================
# 3. MPI-specific profiling
#=====================
echo -e "${BLUE}Running MPI-specific profiling...${NC}"

# MPI strong scaling test
echo -e "${YELLOW}Running strong scaling test...${NC}"
for RANKS in 1 2 4 8 16 32 64 128; do
    echo -e "Testing with ${RANKS} MPI ranks..."
    
    # Ensure we don't exceed available resources
    if [ $RANKS -le 152 ]; then
        mpirun -n $RANKS ./heat_diffusion_mpi_benchmark --size 1000 --iterations 100 --runs 1 > ${RESULTS_DIR}/scaling/strong_scaling_${RANKS}ranks.txt
    else
        echo "Skipping ${RANKS} ranks test (exceeds allocated processors)"
    fi
done

# Weak scaling test (increase problem size with number of ranks)
echo -e "${YELLOW}Running weak scaling test...${NC}"
for RANKS in 1 2 4 8 16 32 64 128; do
    # Ensure we have a square number of ranks for 2D decomposition if your code supports it
    # Adjust the size calculation based on your actual decomposition strategy
    BASE_SIZE=100
    SIZE=$(echo "scale=0; sqrt($BASE_SIZE * $BASE_SIZE * $RANKS)" | bc -l)  # Scale problem with ranks for 2D decomposition
    
    echo -e "Testing with ${RANKS} MPI ranks, grid size ${SIZE}x${SIZE}..."
    
    # Ensure we don't exceed available resources
    if [ $RANKS -le 152 ]; then
        mpirun -n $RANKS ./heat_diffusion_mpi_benchmark --size $SIZE --iterations 100 --runs 1 > ${RESULTS_DIR}/scaling/weak_scaling_${RANKS}ranks.txt
    else
        echo "Skipping ${RANKS} ranks test (exceeds allocated processors)"
    fi
done

#=====================
# 4. Process Placement Tests
#=====================
echo -e "${BLUE}Running process placement tests...${NC}"

# Different process placement strategies
for PLACEMENT in "scatter" "bunch" "core"; do
    echo -e "${YELLOW}Testing with -genv I_MPI_PIN_PROCESSOR_LIST=${PLACEMENT}${NC}"
    
    mpirun -n 8 -genv I_MPI_PIN_PROCESSOR_LIST=${PLACEMENT} ./heat_diffusion_mpi_benchmark --size 500 --iterations 100 --runs 1 > ${RESULTS_DIR}/placement/placement_${PLACEMENT}.txt
done

# Test across nodes (1 node vs 2 nodes with same total ranks)
echo -e "${YELLOW}Testing single-node vs multi-node performance${NC}"
# 8 ranks on 1 node
mpirun -n 8 -ppn 8 -host $(hostname) ./heat_diffusion_mpi_benchmark --size 500 --iterations 100 --runs 1 > ${RESULTS_DIR}/placement/single_node_8ranks.txt

# Get two node hostnames
NODES=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n 2 | paste -sd "," -)
if [[ $(echo $NODES | tr -cd ',' | wc -c) -eq 1 ]]; then
    # 8 ranks across 2 nodes (4 per node)
    mpirun -n 8 -ppn 4 -host $NODES ./heat_diffusion_mpi_benchmark --size 500 --iterations 100 --runs 1 > ${RESULTS_DIR}/placement/multi_node_8ranks.txt
fi

#=====================
# 5. Communication Pattern Analysis
#=====================
echo -e "${BLUE}Running MPI communication analysis...${NC}"

# Analyze data distribution & scaling impact
for GRID_SIZE in 100 400 1000 2000; do
    echo -e "${YELLOW}Testing grid size ${GRID_SIZE} with different rank counts...${NC}"
    
    for PROCS in 1 2 4 8 16 32; do
        # Check if we have enough processors
        if [ $PROCS -le 152 ]; then
            echo -e "Running with ${PROCS} ranks on ${GRID_SIZE}x${GRID_SIZE} grid..."
            mpirun -n $PROCS ./heat_diffusion_mpi_benchmark --size $GRID_SIZE --iterations 100 --runs 1 > \
                ${RESULTS_DIR}/communication/grid${GRID_SIZE}_ranks${PROCS}.txt
        fi
    done
done



#=====================
# 6. Generate Summary
#=====================
echo -e "${GREEN}Generating summary...${NC}"

echo "MPI PROFILING SUMMARY (CSD3 ICELAKE)" > ${RESULTS_DIR}/summary.txt
echo "=================================" >> ${RESULTS_DIR}/summary.txt
echo "" >> ${RESULTS_DIR}/summary.txt

# Add system information
echo "System Information:" >> ${RESULTS_DIR}/summary.txt
echo "  Architecture: Icelake (Intel Xeon 8360Y)" >> ${RESULTS_DIR}/summary.txt
echo "  Cores: 76 per node" >> ${RESULTS_DIR}/summary.txt
echo "  Memory: 256GB/512GB per node" >> ${RESULTS_DIR}/summary.txt
echo "  MPI Implementation: Intel MPI" >> ${RESULTS_DIR}/summary.txt
echo "  Date: $(date)" >> ${RESULTS_DIR}/summary.txt
echo "" >> ${RESULTS_DIR}/summary.txt

# Add scaling results
echo "Strong Scaling Results:" >> ${RESULTS_DIR}/summary.txt
for RANKS in 1 2 4 8 16 32 64 128; do
    if [ -f ${RESULTS_DIR}/scaling/strong_scaling_${RANKS}ranks.txt ]; then
        echo "  ${RANKS} ranks:" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/scaling/strong_scaling_${RANKS}ranks.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt

echo "Weak Scaling Results:" >> ${RESULTS_DIR}/summary.txt
for RANKS in 1 2 4 8 16 32 64 128; do
    if [ -f ${RESULTS_DIR}/scaling/weak_scaling_${RANKS}ranks.txt ]; then
        BASE_SIZE=100
        SIZE=$(echo "scale=0; sqrt($BASE_SIZE * $BASE_SIZE * $RANKS)" | bc -l)
        echo "  ${RANKS} ranks (${SIZE}x${SIZE} grid):" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/scaling/weak_scaling_${RANKS}ranks.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt

# Add gprof summary from rank 0 (most representative)
if [ -f ${RESULTS_DIR}/gprof/gprof_report_rank_0.txt ]; then
    echo "Top functions from gprof (rank 0):" >> ${RESULTS_DIR}/summary.txt
    head -n 20 ${RESULTS_DIR}/gprof/gprof_report_rank_0.txt >> ${RESULTS_DIR}/summary.txt
    echo "" >> ${RESULTS_DIR}/summary.txt
fi

# Add process placement comparison
echo "Process Placement Analysis:" >> ${RESULTS_DIR}/summary.txt
for PLACEMENT in "scatter" "bunch" "core"; do
    if [ -f ${RESULTS_DIR}/placement/placement_${PLACEMENT}.txt ]; then
        echo "  Placement strategy: ${PLACEMENT}" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/placement/placement_${PLACEMENT}.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done

if [ -f ${RESULTS_DIR}/placement/single_node_8ranks.txt ] && [ -f ${RESULTS_DIR}/placement/multi_node_8ranks.txt ]; then
    echo "  Single node vs Multi-node (8 ranks):" >> ${RESULTS_DIR}/summary.txt
    echo "    Single node:" >> ${RESULTS_DIR}/summary.txt
    grep "Average Iteration Time:" ${RESULTS_DIR}/placement/single_node_8ranks.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    echo "    Multi node:" >> ${RESULTS_DIR}/summary.txt
    grep "Average Iteration Time:" ${RESULTS_DIR}/placement/multi_node_8ranks.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
fi
echo "" >> ${RESULTS_DIR}/summary.txt

# Analyze communication patterns
echo "MPI Communication Pattern Analysis:" >> ${RESULTS_DIR}/summary.txt
echo "--------------------------------" >> ${RESULTS_DIR}/summary.txt
echo "" >> ${RESULTS_DIR}/summary.txt

echo "Grid Size Scaling with Fixed Rank Count (16 ranks):" >> ${RESULTS_DIR}/summary.txt
for SIZE in 100 400 1000 2000; do
    if [ -f ${RESULTS_DIR}/communication/grid${SIZE}_ranks16.txt ]; then
        echo "  Grid ${SIZE}x${SIZE}:" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/communication/grid${SIZE}_ranks16.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Performance:" ${RESULTS_DIR}/communication/grid${SIZE}_ranks16.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt

echo "Rank Scaling with Fixed Grid Size (1000x1000):" >> ${RESULTS_DIR}/summary.txt
for RANKS in 1 2 4 8 16 32; do
    if [ -f ${RESULTS_DIR}/communication/grid1000_ranks${RANKS}.txt ]; then
        echo "  ${RANKS} ranks:" >> ${RESULTS_DIR}/summary.txt
        grep "Average Iteration Time:" ${RESULTS_DIR}/communication/grid1000_ranks${RANKS}.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
        grep "Performance:" ${RESULTS_DIR}/communication/grid1000_ranks${RANKS}.txt >> ${RESULTS_DIR}/summary.txt 2>/dev/null
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt


# Calculate parallel efficiency
echo "Parallel Efficiency:" >> ${RESULTS_DIR}/summary.txt
if [ -f ${RESULTS_DIR}/scaling/strong_scaling_1ranks.txt ] && [ -f ${RESULTS_DIR}/scaling/strong_scaling_4ranks.txt ]; then
    # Average Iteration Time
    TIME_1=$(grep "Average Iteration Time:" ${RESULTS_DIR}/scaling/strong_scaling_1ranks.txt | awk '{print $4}')
    TIME_4=$(grep "Average Iteration Time:" ${RESULTS_DIR}/scaling/strong_scaling_4ranks.txt | awk '{print $4}')
    
    # Calculate efficiency if we have valid numbers
    if [[ $TIME_1 =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $TIME_4 =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        EFF=$(echo "scale=2; $TIME_1 / (4 * $TIME_4) * 100" | bc)
        echo "  4 ranks efficiency: ${EFF}%" >> ${RESULTS_DIR}/summary.txt
    else
        echo "  Could not calculate efficiency (missing or invalid timing data)" >> ${RESULTS_DIR}/summary.txt
    fi
fi

# Add efficiency for more ranks if available
for RANKS in 8 16 32 64 128; do
    if [ -f ${RESULTS_DIR}/scaling/strong_scaling_${RANKS}ranks.txt ] && [ -f ${RESULTS_DIR}/scaling/strong_scaling_1ranks.txt ]; then
        TIME_1=$(grep "Average Iteration Time:" ${RESULTS_DIR}/scaling/strong_scaling_1ranks.txt | awk '{print $4}')
        TIME_N=$(grep "Average Iteration Time:" ${RESULTS_DIR}/scaling/strong_scaling_${RANKS}ranks.txt | awk '{print $4}')
        
        if [[ $TIME_1 =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $TIME_N =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            EFF=$(echo "scale=2; $TIME_1 / ($RANKS * $TIME_N) * 100" | bc)
            echo "  ${RANKS} ranks efficiency: ${EFF}%" >> ${RESULTS_DIR}/summary.txt
        fi
    fi
done
echo "" >> ${RESULTS_DIR}/summary.txt

echo -e "${GREEN}MPI profiling complete! Results in ${RESULTS_DIR}/ directory.${NC}"

# Show quick summary on screen
echo -e "${BLUE}Quick Results:${NC}"
if [ -f ${RESULTS_DIR}/scaling/strong_scaling_1ranks.txt ]; then
    TIME_1=$(grep "Average Iteration Time:" ${RESULTS_DIR}/scaling/strong_scaling_1ranks.txt | awk '{print $4}')
    echo -e "  Single rank time: ${TIME_1} ms"
fi

for RANKS in 2 4 8 16 32 64 128; do
    if [ -f ${RESULTS_DIR}/scaling/strong_scaling_${RANKS}ranks.txt ]; then
        TIME=$(grep "Average Iteration Time:" ${RESULTS_DIR}/scaling/strong_scaling_${RANKS}ranks.txt | awk '{print $4}')
        echo -e "  ${RANKS} ranks time: ${TIME} ms"
    fi
done

echo -e "${GREEN}See full details in ${RESULTS_DIR}/summary.txt${NC}"