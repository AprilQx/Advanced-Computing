#!/bin/bash
# Comprehensive profiling script for hybrid MPI+OpenMP heat diffusion simulation
# Designed for Cambridge CSD3 Icelake nodes with Intel toolchain

# Load required modules for CSD3
module purge
module load rhel8/default-icl
module load intel/oneapi/2022.1.0/itac

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set up directories correctly
SCRIPT_DIR="$(pwd)"
PROJECT_DIR="/home/xx823/Advanced-Computing"

# Create results directory in a location where you have permissions
RESULTS_DIR="${PROJECT_DIR}/profiling_results_hybrid"
mkdir -p ${RESULTS_DIR}/{vtune,scaling,communication,process_thread_balance,affinity,placement}

echo -e "${GREEN}Starting Hybrid MPI+OpenMP profiling on CSD3 Icelake nodes...${NC}"

# First, check if the PROJECT_DIR exists
if [ ! -d "${PROJECT_DIR}" ]; then
    echo -e "${YELLOW}Error: Project directory ${PROJECT_DIR} does not exist!${NC}"
    echo "Please create this directory or modify the script to point to your correct project location."
    exit 1
fi

# Go to project root where CMakeLists.txt is located
cd ${PROJECT_DIR}

# Check if CMakeLists.txt exists in the current directory
if [ ! -f "CMakeLists.txt" ]; then
    echo -e "${YELLOW}Error: CMakeLists.txt not found in ${PROJECT_DIR}${NC}"
    echo "Please make sure you're in the correct project directory that contains CMakeLists.txt."
    exit 1
fi

# Create build directory if it doesn't exist
mkdir -p build
cd build

# Configure and build with Intel compilers
echo -e "${BLUE}Configuring and building with Intel compilers...${NC}"

# Use Intel compilers
export CC=icc
export CXX=icpc
export MPICC=mpiicc
export MPICXX=mpiicpc

# Build with normal optimization
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=icc -DCMAKE_CXX_COMPILER=icpc
make -j8 heat_diffusion_benchmark_hybrid

# Verify the executable exists
if [ ! -f "heat_diffusion_benchmark_hybrid" ]; then
    echo -e "${YELLOW}Error: heat_diffusion_benchmark_hybrid was not built correctly${NC}"
    echo "Please check your build configuration and try again."
    exit 1
fi


#=====================
# 1. Environment Check
#=====================
echo -e "${BLUE}Checking CSD3 Icelake hybrid execution environment...${NC}"
# Get the number of available CPU cores (adjust for CSD3 Icelake nodes)
NUM_CORES=$SLURM_NTASKS
if [ -z "$NUM_CORES" ]; then
    # If not running under SLURM, determine cores from system
    NUM_CORES=$(nproc)
fi
echo -e "${YELLOW}Using ${NUM_CORES} CPU cores for testing${NC}"

# Try to get OpenMP information
echo -e "${YELLOW}Creating OpenMP test program...${NC}"
cat > openmp_test.c << EOF
#include <stdio.h>
#include <omp.h>
int main() {
    printf("OpenMP version: %d\n", _OPENMP);
    printf("OpenMP max threads: %d\n", omp_get_max_threads());
    printf("Number of sockets: %d\n", omp_get_num_places());
    return 0;
}
EOF
icc -qopenmp openmp_test.c -o openmp_test
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
    echo -e "${YELLOW}Warning: mpirun not found in PATH. Checking for Intel MPI alternatives...${NC}"
    if command -v mpiexec.hydra &> /dev/null; then
        echo -e "Intel MPI found: $(mpiexec.hydra -version | head -n 1)"
        # Use Intel MPI launcher
        MPIRUN_CMD="mpiexec.hydra"
    else
        echo -e "${YELLOW}Warning: No MPI launcher found. Using srun for MPI execution.${NC}"
        MPIRUN_CMD="srun"
    fi
fi

# Set default MPI launcher if not already set
if [ -z "$MPIRUN_CMD" ]; then
    MPIRUN_CMD="mpirun"
fi
echo -e "Using MPI launcher: $MPIRUN_CMD"

# Print node information
echo -e "${YELLOW}Node information:${NC}"
sinfo -N -l | grep icelake

# Print node topology
echo -e "${YELLOW}Node topology:${NC}"
srun -N 2 lstopo-no-graphics --if png > /dev/null 2>&1

#=====================
# 2. Process Placement Tests (Focus on 2-node scenarios)
#=====================
echo -e "${BLUE}Running process placement tests focusing on 2-node communication...${NC}"
mkdir -p ${RESULTS_DIR}/placement

# Get node hostnames from SLURM
NODE_LIST=$(scontrol show hostnames $SLURM_JOB_NODELIST)
NODE_COUNT=$(echo "$NODE_LIST" | wc -l)

if [ $NODE_COUNT -lt 2 ]; then
    echo -e "${YELLOW}Warning: Less than 2 nodes available, skipping multi-node tests${NC}"
else
    FIRST_NODE=$(echo "$NODE_LIST" | head -n 1)
    SECOND_NODE=$(echo "$NODE_LIST" | head -n 2 | tail -n 1)
    TWO_NODES="${FIRST_NODE},${SECOND_NODE}"
    
    echo -e "${YELLOW}Running tests on two nodes: ${TWO_NODES}${NC}"
    
    # Pure MPI tests with different process distributions
    
    # Test 1: 76 processes on first node
    echo -e "${YELLOW}Test 1: 76 processes on first node${NC}"
    $MPIRUN_CMD -n 76 -host $FIRST_NODE ./heat_diffusion_benchmark_hybrid \
        --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 1 > \
        $PROJECT_DIR/profiling_results_hybrid/placement/single_node_76ranks.txt 2>&1
    
    # Test 2: 76 processes on second node
    echo -e "${YELLOW}Test 2: 76 processes on second node${NC}"
    $MPIRUN_CMD -n 76 -host $SECOND_NODE ./heat_diffusion_benchmark_hybrid \
        --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 1 > \
        $PROJECT_DIR/profiling_results_hybrid/placement/single_node_76ranks_second.txt 2>&1
    
    # Test 3: 152 processes across 2 nodes (76 per node)
    echo -e "${YELLOW}Test 3: 152 processes across 2 nodes (76 per node)${NC}"
    $MPIRUN_CMD -n 152 -ppn 76 -host $TWO_NODES ./heat_diffusion_benchmark_hybrid \
        --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 1 > \
        $PROJECT_DIR/profiling_results_hybrid/placement/multi_node_152ranks.txt 2>&1
    
    # Test 4: 128 processes across 2 nodes (64 per node)
    echo -e "${YELLOW}Test 4: 128 processes across 2 nodes (64 per node)${NC}"
    $MPIRUN_CMD -n 128 -ppn 64 -host $TWO_NODES ./heat_diffusion_benchmark_hybrid \
        --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 1 > \
        $PROJECT_DIR/profiling_results_hybrid/placement/multi_node_128ranks.txt 2>&1
    
    # Hybrid mode tests
    
    # Test 5: 38 processes with 2 threads each across 2 nodes (19 processes per node)
    echo -e "${YELLOW}Test 5: 38 processes with 2 threads each across 2 nodes${NC}"
    export OMP_NUM_THREADS=2
    $MPIRUN_CMD -n 38 -ppn 19 -host $TWO_NODES ./heat_diffusion_benchmark_hybrid \
        --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 2 > \
        $PROJECT_DIR/profiling_results_hybrid/placement/multi_node_hybrid_38ranks_2threads.txt 2>&1
    
    # Test 6: 19 processes with 4 threads each across 2 nodes (9-10 processes per node)
    echo -e "${YELLOW}Test 6: 19 processes with 4 threads each across 2 nodes${NC}"
    export OMP_NUM_THREADS=4
    $MPIRUN_CMD -n 19 -ppn 10 -host $FIRST_NODE -ppn 9 -host $SECOND_NODE ./heat_diffusion_benchmark_hybrid \
        --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 4 > \
        $PROJECT_DIR/profiling_results_hybrid/placement/multi_node_hybrid_19ranks_4threads.txt 2>&1
    
    # Test 7: 8 processes with 19 threads each across 2 nodes (4 processes per node)
    echo -e "${YELLOW}Test 7: 8 processes with 19 threads each across 2 nodes${NC}"
    export OMP_NUM_THREADS=19
    $MPIRUN_CMD -n 8 -ppn 4 -host $TWO_NODES ./heat_diffusion_benchmark_hybrid \
        --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 19 > \
        $PROJECT_DIR/profiling_results_hybrid/placement/multi_node_hybrid_8ranks_19threads.txt 2>&1
    
    # Test 8: 4 processes with 38 threads each across 2 nodes (2 processes per node)
    echo -e "${YELLOW}Test 8: 4 processes with 38 threads each across 2 nodes${NC}"
    export OMP_NUM_THREADS=38
    $MPIRUN_CMD -n 4 -ppn 2 -host $TWO_NODES ./heat_diffusion_benchmark_hybrid \
        --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 38 > \
        $PROJECT_DIR/profiling_results_hybrid/placement/multi_node_hybrid_4ranks_38threads.txt 2>&1
    
    # Test 9: 2 processes with 76 threads each across 2 nodes (1 process per node)
    echo -e "${YELLOW}Test 9: 2 processes with 76 threads each across 2 nodes${NC}"
    export OMP_NUM_THREADS=76
    $MPIRUN_CMD -n 2 -ppn 1 -host $TWO_NODES ./heat_diffusion_benchmark_hybrid \
        --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 76 > \
        $PROJECT_DIR/profiling_results_hybrid/placement/multi_node_hybrid_2ranks_76threads.txt 2>&1
    
    # Inter-node communication tests with different fabric settings
    echo -e "${YELLOW}Running inter-node communication fabric tests${NC}"
    
    # Test baseline config with different fabrics - Use 16 processes, 4 threads per process
    export OMP_NUM_THREADS=4
    for FABRIC in "shm:ofi" "shm:dapl" "shm:tcp"; do
        echo -e "${YELLOW}Testing with I_MPI_FABRICS=${FABRIC} across 2 nodes${NC}"
        export I_MPI_FABRICS=$FABRIC
        
        $MPIRUN_CMD -n 16 -ppn 8 -host $TWO_NODES ./heat_diffusion_benchmark_hybrid \
            --height 5000 --width 5000 --iterations 1000 --runs 1 --threads 4 > \
            $PROJECT_DIR/profiling_results_hybrid/placement/multi_node_fabric_${FABRIC// /_}.txt 2>&1
    done
    unset I_MPI_FABRICS
    
    # Test different message sizes to analyze communication patterns
    echo -e "${YELLOW}Testing different problem sizes to analyze communication patterns${NC}"
    
    # Use a balanced hybrid configuration (8 processes, 8 threads per process)
    export OMP_NUM_THREADS=8
    
    for SIZE in 1000 2000 4000 8000; do
        echo -e "${YELLOW}Testing problem size ${SIZE}x${SIZE} across 2 nodes${NC}"
        $MPIRUN_CMD -n 16 -ppn 8 -host $TWO_NODES ./heat_diffusion_benchmark_hybrid \
            --height $SIZE --width $SIZE --iterations 100 --runs 1 --threads 8 > \
            $PROJECT_DIR/profiling_results_hybrid/placement/multi_node_size_${SIZE}.txt 2>&1
    done
fi

#=====================
# 3. Thread Affinity Tests on Icelake
#=====================
echo -e "${BLUE}Running thread affinity tests optimized for Icelake...${NC}"
mkdir -p $PROJECT_DIR/profiling_results_hybrid/affinity

# Use standard configuration for affinity tests
PROCS=8
THREADS=8

# Test different Intel OpenMP thread binding strategies with Icelake optimizations
OMP_BINDING_TYPES=("scatter" "compact" "balanced")
KMP_AFFINITY_TYPES=("compact" "scatter" "balanced" "disabled")

for BIND in "${OMP_BINDING_TYPES[@]}"; do
    echo -e "Testing with OMP_PLACES=cores OMP_PROC_BIND=${BIND}..."
    export OMP_NUM_THREADS=$THREADS
    export OMP_PLACES=cores
    export OMP_PROC_BIND=$BIND
    
    $MPIRUN_CMD -n $PROCS ./heat_diffusion_benchmark_hybrid --height 5000 --width 5000 --iterations 100 --runs 1 --threads $THREADS > \
        $PROJECT_DIR/profiling_results_hybrid/affinity/omp_bind_${BIND}.txt 2>&1
done

# Test Intel-specific KMP_AFFINITY variable
for BIND in "${KMP_AFFINITY_TYPES[@]}"; do
    echo -e "Testing with KMP_AFFINITY=${BIND}..."
    export OMP_NUM_THREADS=$THREADS
    unset OMP_PLACES
    unset OMP_PROC_BIND
    export KMP_AFFINITY=$BIND
    
    $MPIRUN_CMD -n $PROCS ./heat_diffusion_benchmark_hybrid --height 5000 --width 5000 --iterations 100 --runs 1 --threads $THREADS > \
        $PROJECT_DIR/profiling_results_hybrid/affinity/kmp_affinity_${BIND}.txt 2>&1
done

# Test with explicit placement to specific cores on Icelake
echo -e "Testing with explicit core binding..."
export OMP_NUM_THREADS=$THREADS
export KMP_AFFINITY=verbose
export I_MPI_PIN_PROCESSOR_LIST=allcores
$MPIRUN_CMD -n $PROCS ./heat_diffusion_benchmark_hybrid --height 5000 --width 5000 --iterations 50 --runs 1 --threads $THREADS > \
    $PROJECT_DIR/profiling_results_hybrid/affinity/explicit_binding.txt 2>&1

# Reset affinity settings
unset OMP_PLACES
unset OMP_PROC_BIND
unset KMP_AFFINITY

#=====================
# 4. Strong Scaling Tests for Icelake
#=====================
echo -e "${BLUE}Running strong scaling tests optimized for Icelake...${NC}"
mkdir -p $PROJECT_DIR/profiling_results_hybrid/scaling

# Define Icelake-specific configurations to test
declare -a STRONG_CONFIGS=(
    # Format: "processes:threads"
    "1:1"    # Baseline: 1 process, 1 thread
    "1:76"   # 1 process, 76 threads (full node)
    "2:38"   # 2 processes, 38 threads each
    "4:19"   # 4 processes, 19 threads each
    "8:9"    # 8 processes, ~9 threads each
    "19:4"   # 19 processes, 4 threads each
    "38:2"   # 38 processes, 2 threads each
    "76:1"   # 76 processes, 1 thread each (pure MPI, single node)
)

# Multi-node configurations
if [ $NODE_COUNT -ge 2 ]; then
    STRONG_CONFIGS+=(
        "2:76"   # 2 processes, 76 threads each (1 per node)
        "4:38"   # 4 processes, 38 threads each (2 per node)
        "8:19"   # 8 processes, 19 threads each (4 per node)
        "16:9"   # 16 processes, 9 threads each (8 per node)
        "38:4"   # 38 processes, 4 threads each (19 per node)
        "76:2"   # 76 processes, 2 threads each (38 per node)
        "152:1"  # 152 processes, 1 thread each (pure MPI, dual node)
    )
fi

# Problem size for strong scaling (fixed for all tests)
PROBLEM_SIZE=5000

# Run tests for each configuration
for CONFIG in "${STRONG_CONFIGS[@]}"; do
    PROCS=$(echo $CONFIG | cut -d':' -f1)
    THREADS=$(echo $CONFIG | cut -d':' -f2)
    TOTAL_CORES=$((PROCS * THREADS))
    
    if [ $TOTAL_CORES -le $NUM_CORES ]; then
        echo -e "Running strong scaling test with ${PROCS} processes and ${THREADS} threads per process..."
        
        export OMP_NUM_THREADS=$THREADS
        export I_MPI_PIN_DOMAIN=numa
        
        # For multi-node tests, distribute processes evenly
        if [ $PROCS -le $NUM_CORES/2 ]; then
            $MPIRUN_CMD -n $PROCS ./heat_diffusion_benchmark_hybrid --height $PROBLEM_SIZE --width $PROBLEM_SIZE --iterations 50 --runs 1 --threads $THREADS > \
                $PROJECT_DIR/profiling_results_hybrid/scaling/strong_p${PROCS}_t${THREADS}.txt 2>&1
        else
            # Distribute across nodes explicitly for larger process counts
            if [ $NODE_COUNT -ge 2 ]; then
                PPN=$((PROCS / NODE_COUNT))
                $MPIRUN_CMD -n $PROCS -ppn $PPN -host $TWO_NODES ./heat_diffusion_benchmark_hybrid --height $PROBLEM_SIZE --width $PROBLEM_SIZE --iterations 50 --runs 1 --threads $THREADS > \
                    $PROJECT_DIR/profiling_results_hybrid/scaling/strong_p${PROCS}_t${THREADS}.txt 2>&1
            else
                $MPIRUN_CMD -n $PROCS ./heat_diffusion_benchmark_hybrid --height $PROBLEM_SIZE --width $PROBLEM_SIZE --iterations 50 --runs 1 --threads $THREADS > \
                    $PROJECT_DIR/profiling_results_hybrid/scaling/strong_p${PROCS}_t${THREADS}.txt 2>&1
            fi
        fi
        
        # Check if the run was successful
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}Warning: Strong scaling run with ${PROCS} processes and ${THREADS} threads failed${NC}"
        fi
    else
        echo -e "${YELLOW}Skipping configuration p${PROCS}_t${THREADS} (requires ${TOTAL_CORES} cores, only ${NUM_CORES} available)${NC}"
    fi
done

#=====================
# 5. Generate Summary
#=====================
echo -e "${BLUE}Generating summary report...${NC}"

# Create summary file
SUMMARY_FILE="$PROJECT_DIR/profiling_results_hybrid/summary.txt"
echo "# Heat Diffusion Simulation Profiling Summary for CSD3 Icelake (2-Node)" > $SUMMARY_FILE
echo "Date: $(date)" >> $SUMMARY_FILE
echo "" >> $SUMMARY_FILE

# System information
echo "## System Information" >> $SUMMARY_FILE
echo "- Job ID: $SLURM_JOB_ID" >> $SUMMARY_FILE
echo "- Nodes: $SLURM_JOB_NUM_NODES" >> $SUMMARY_FILE
echo "- Node Names: $(scontrol show hostnames $SLURM_JOB_NODELIST | tr '\n' ' ')" >> $SUMMARY_FILE
echo "- CPU Cores Total: $NUM_CORES" >> $SUMMARY_FILE
echo "- CPU Cores Per Node: 76 (Icelake)" >> $SUMMARY_FILE
if [ -f "openmp_test" ]; then
    echo "- OpenMP Info: $(./openmp_test | tr '\n' ' ')" >> $SUMMARY_FILE
fi
echo "- MPI Implementation: $($MPIRUN_CMD --version | head -n 1)" >> $SUMMARY_FILE
echo "- Intel Compiler: $(icc --version | head -n 1)" >> $SUMMARY_FILE
echo "" >> $SUMMARY_FILE

# Process placement summary for 2-node tests
echo "## Process Placement Tests (2-Node Focus)" >> $SUMMARY_FILE
echo "Testing different process distributions on 2 Icelake nodes:" >> $SUMMARY_FILE

# Pure MPI tests
RESULT_FILE="$PROJECT_DIR/profiling_results_hybrid/placement/single_node_76ranks.txt"
if [ -f "$RESULT_FILE" ]; then
    TIME=$(grep "Total Simulation Time:" $RESULT_FILE | head -n 1)
    if [ -n "$TIME" ]; then
        echo "- 76 processes on single node: $TIME" >> $SUMMARY_FILE
    else
        echo "- 76 processes on single node: Completed" >> $SUMMARY_FILE
    fi
else
    echo "- 76 processes on single node: Failed or not run" >> $SUMMARY_FILE
fi

RESULT_FILE="$PROJECT_DIR/profiling_results_hybrid/placement/multi_node_152ranks.txt"
if [ -f "$RESULT_FILE" ]; then
    TIME=$(grep "Total Simulation Time:" $RESULT_FILE | head -n 1)
    if [ -n "$TIME" ]; then
        echo "- 152 processes across 2 nodes (76 per node): $TIME" >> $SUMMARY_FILE
    else
        echo "- 152 processes across 2 nodes (76 per node): Completed" >> $SUMMARY_FILE
    fi
else
    echo "- 152 processes across 2 nodes (76 per node): Failed or not run" >> $SUMMARY_FILE
fi

# Hybrid mode tests
HYBRID_TESTS=(
    "38:2"
    "19:4"
    "8:19"
    "4:38"
    "2:76"
)

echo "" >> $SUMMARY_FILE
echo "Hybrid mode performance across 2 nodes:" >> $SUMMARY_FILE

for TEST in "${HYBRID_TESTS[@]}"; do
    PROCS=$(echo $TEST | cut -d':' -f1)
    THREADS=$(echo $TEST | cut -d':' -f2)
    
    RESULT_FILE="$PROJECT_DIR/profiling_results_hybrid/placement/multi_node_hybrid_${PROCS}ranks_${THREADS}threads.txt"
    if [ -f "$RESULT_FILE" ]; then
        TIME=$(grep "Total Simulation Time:" $RESULT_FILE | head -n 1)
        if [ -n "$TIME" ]; then
            echo "- $PROCS processes with $THREADS threads each: $TIME" >> $SUMMARY_FILE
        else
            echo "- $PROCS processes with $THREADS threads each: Completed" >> $SUMMARY_FILE
        fi
    else
        echo "- $PROCS processes with $THREADS threads each: Failed or not run" >> $SUMMARY_FILE
    fi
done

# Fabric tests
echo "" >> $SUMMARY_FILE
echo "Inter-node fabric performance tests:" >> $SUMMARY_FILE
for FABRIC in "shm:ofi" "shm:dapl" "shm:tcp"; do
    SAFE_FABRIC="${FABRIC// /_}"
    RESULT_FILE="$PROJECT_DIR/profiling_results_hybrid/placement/multi_node_fabric_${SAFE_FABRIC}.txt"
    if [ -f "$RESULT_FILE" ]; then
        TIME=$(grep "Total Simulation Time:" $RESULT_FILE | head -n 1)
        if [ -n "$TIME" ]; then
            echo "- I_MPI_FABRICS=${FABRIC}: $TIME" >> $SUMMARY_FILE
        else
            echo "- I_MPI_FABRICS=${FABRIC}: Completed" >> $SUMMARY_FILE
        fi
    else
        echo "- I_MPI_FABRICS=${FABRIC}: Failed or not run" >> $SUMMARY_FILE
    fi
done

# Communication patterns with different problem sizes
echo "" >> $SUMMARY_FILE
echo "Communication patterns with different problem sizes:" >> $SUMMARY_FILE
for SIZE in 1000 2000 4000 8000; do
    RESULT_FILE="$PROJECT_DIR/profiling_results_hybrid/placement/multi_node_size_${SIZE}.txt"
    if [ -f "$RESULT_FILE" ]; then
        TIME=$(grep "Total Simulation Time:" $RESULT_FILE | head -n 1)
        PERF=$(grep "Performance:" $RESULT_FILE | head -n 1)
        
        if [ -n "$TIME" ] && [ -n "$PERF" ]; then
            echo "- Size ${SIZE}x${SIZE}: $TIME, $PERF" >> $SUMMARY_FILE
        else
            echo "- Size ${SIZE}x${SIZE}: Completed" >> $SUMMARY_FILE
        fi
    else
        echo "- Size ${SIZE}x${SIZE}: Failed or not run" >> $SUMMARY_FILE
    fi
done

# Thread affinity summary
echo "" >> $SUMMARY_FILE
echo "## Thread Affinity Tests" >> $SUMMARY_FILE
echo "Testing OpenMP thread binding strategies with $PROCS processes and $THREADS threads:" >> $SUMMARY_FILE
for BIND in "${OMP_BINDING_TYPES[@]}"; do
    RESULT_FILE="$PROJECT_DIR/profiling_results_hybrid/affinity/omp_bind_${BIND}.txt"
    if [ -f "$RESULT_FILE" ]; then
        TIME=$(grep "Total Simulation Time:" $RESULT_FILE | head -n 1)
        
        if [ -n "$TIME" ]; then
            echo "- OMP_PROC_BIND=$BIND: $TIME" >> $SUMMARY_FILE
        else
            echo "- OMP_PROC_BIND=$BIND: Completed" >> $SUMMARY_FILE
        fi
    else
        echo "- OMP_PROC_BIND=$BIND: Failed or not run" >> $SUMMARY_FILE
    fi
done

echo "Testing Intel KMP_AFFINITY settings with $PROCS processes and $THREADS threads:" >> $SUMMARY_FILE
for BIND in "${KMP_AFFINITY_TYPES[@]}"; do
    RESULT_FILE="$PROJECT_DIR/profiling_results_hybrid/affinity/kmp_affinity_${BIND}.txt"
    if [ -f "$RESULT_FILE" ]; then
        TIME=$(grep "Total Simulation Time:" $RESULT_FILE | head -n 1)
        
        if [ -n "$TIME" ]; then
            echo "- KMP_AFFINITY=$BIND: $TIME" >> $SUMMARY_FILE
        else
            echo "- KMP_AFFINITY=$BIND: Completed" >> $SUMMARY_FILE
        fi
    else
        echo "- KMP_AFFINITY=$BIND: Failed or not run" >> $SUMMARY_FILE
    fi
done

# Strong scaling summary
echo "" >> $SUMMARY_FILE
echo "## Strong Scaling Tests" >> $SUMMARY_FILE
echo "Fixed problem size (${PROBLEM_SIZE}×${PROBLEM_SIZE}), varying process and thread counts:" >> $SUMMARY_FILE
for CONFIG in "${STRONG_CONFIGS[@]}"; do
    PROCS=$(echo $CONFIG | cut -d':' -f1)
    THREADS=$(echo $CONFIG | cut -d':' -f2)
    
    RESULT_FILE="$PROJECT_DIR/profiling_results_hybrid/scaling/strong_p${PROCS}_t${THREADS}.txt"
    if [ -f "$RESULT_FILE" ]; then
        # Extract time and performance if available
        TIME=$(grep "Total Simulation Time:" $RESULT_FILE | head -n 1)
        PERF=$(grep "Performance:" $RESULT_FILE | head -n 1)
        
        if [ -n "$TIME" ] && [ -n "$PERF" ]; then
            echo "- $PROCS processes × $THREADS threads: $TIME, $PERF" >> $SUMMARY_FILE
        else
            echo "- $PROCS processes × $THREADS threads: Completed" >> $SUMMARY_FILE
        fi
    else
        echo "- $PROCS processes × $THREADS threads: Not tested" >> $SUMMARY_FILE
    fi
done

# Key findings and recommendations
echo "" >> $SUMMARY_FILE
echo "## Key Findings and Recommendations" >> $SUMMARY_FILE
echo "Please review the detailed results to identify:" >> $SUMMARY_FILE
echo "1. Optimal process-thread balance for CSD3 Icelake hardware" >> $SUMMARY_FILE
echo "2. Most efficient communication pattern between the 2 nodes" >> $SUMMARY_FILE
echo "3. Impact of Intel-specific thread affinity settings on performance" >> $SUMMARY_FILE
echo "4. Best fabric option for inter-node communication" >> $SUMMARY_FILE
echo "5. Scaling characteristics with different MPI/OpenMP combinations" >> $SUMMARY_FILE
echo "6. Performance impact of different problem sizes on communication patterns" >> $SUMMARY_FILE

echo -e "${GREEN}Summary generated: ${SUMMARY_FILE}${NC