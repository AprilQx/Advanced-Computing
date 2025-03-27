#!/bin/bash

# Improved MPI profiling script that addresses path issues
# Designed to run inside Docker containers

# Allow MPI to run as root in Docker
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create directories
mkdir -p /app/profiling_results_mpi/{gprof,valgrind,scaling,communication}

echo -e "${GREEN}Starting MPI profiling...${NC}"

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
make -j4 heat_diffusion_mpi_benchmark

# Verify the executable exists
if [ ! -f "heat_diffusion_mpi_benchmark" ]; then
    echo -e "${YELLOW}Error: heat_diffusion_mpi_benchmark was not built correctly${NC}"
    echo "Please check your build configuration and try again."
    exit 1
fi

#=====================
# 1. GPROF Profiling (each MPI rank will generate its own profile)
#=====================
echo -e "${BLUE}Running gprof profiling...${NC}"

# Run with small grid for quick profiling
mpirun -n 4 ./heat_diffusion_mpi_benchmark --height 100 --width 100 --iterations 100 --runs 1

# Generate gprof report for each rank
echo -e "${YELLOW}Looking for gprof data files...${NC}"

# First look for rank-specific gmon.out files
if ls gmon.out.* 2>/dev/null; then
    for gmon in gmon.out.*; do
        # Extract rank number from filename
        if [[ $gmon =~ .*\.([0-9]+)$ ]]; then
            RANK="${BASH_REMATCH[1]}"
            gprof ./heat_diffusion_mpi_benchmark $gmon > ../profiling_results_mpi/gprof/gprof_report_rank_${RANK}.txt
            echo -e "${YELLOW}Created gprof report for rank ${RANK}${NC}"
        fi
    done
# If no rank-specific files found, try the default gmon.out
elif [ -f "gmon.out" ]; then
    echo -e "${YELLOW}No rank-specific gmon files found, using default gmon.out${NC}"
    gprof ./heat_diffusion_mpi_benchmark gmon.out > ../profiling_results_mpi/gprof/gprof_report_combined.txt
    echo -e "${YELLOW}Created combined gprof report${NC}"
else
    echo -e "${YELLOW}Warning: No gprof data files found!${NC}"
    echo -e "${YELLOW}Make sure your executable was compiled with -pg flag${NC}"
    echo -e "${YELLOW}and the execution completed successfully.${NC}"
fi

#=====================
# 2. MPI-specific profiling
#=====================
echo -e "${BLUE}Running MPI-specific profiling...${NC}"

# Return to optimized build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4

# MPI scaling test
echo -e "${YELLOW}Running strong scaling test...${NC}"
for RANKS in 1 2 4 8 10; do
    echo -e "Testing with ${RANKS} MPI ranks..."
    
    # Ensure we don't exceed available resources
    if [ $RANKS -le $(nproc) ]; then
        mpirun -n $RANKS ./heat_diffusion_mpi_benchmark --height 1000 --width 1000 --iterations 50 --runs 1 > ../profiling_results_mpi/scaling/strong_scaling_${RANKS}ranks.txt
    else
        echo "Skipping ${RANKS} ranks test (exceeds available processors)"
    fi
done

# Weak scaling test (increase problem size with number of ranks)
echo -e "${YELLOW}Running weak scaling test...${NC}"
for RANKS in 1 2 4 8 10; do
    BASE_SIZE=500
    SIZE=$(echo "sqrt($BASE_SIZE * $BASE_SIZE * $THREADS)" | bc) # Scale problem with ranks
    SIZE=${SIZE%.*} # Remove decimal part

    echo -e "Testing with ${RANKS} MPI ranks, grid size ${SIZE}x${SIZE}..."
    
    # Ensure we don't exceed available resources
    if [ $RANKS -le $(nproc) ]; then
        mpirun -n $RANKS ./heat_diffusion_mpi_benchmark ---width $SIZE --height $SIZE --iterations 100 --runs 1 > ../profiling_results_mpi/scaling/weak_scaling_${RANKS}ranks.txt
    else
        echo "Skipping ${RANKS} ranks test (exceeds available processors)"
    fi
done

#=====================
# 3. MPI Communication Analysis
#=====================
echo -e "${BLUE}Running MPI communication analysis...${NC}"

# Add specific tests for MPI communication patterns
echo -e "${BLUE}Running MPI communication pattern tests...${NC}"

# Analyze data distribution & scaling impact
for GRID_SIZE in 100 400 1000; do
    echo -e "${YELLOW}Testing grid size ${GRID_SIZE} with different rank counts...${NC}"
    
    for PROCS in 1 2 4 8; do
        # Check if we have enough processors
        if [ $PROCS -le $(nproc) ]; then
            echo -e "Running with ${PROCS} ranks on ${GRID_SIZE}x${GRID_SIZE} grid..."
            mpirun -n $PROCS ./heat_diffusion_mpi_benchmark --height $GRID_SIZE --width $GRID_SIZE --iterations 100 --runs 1 > \
                ../profiling_results_mpi/communication/grid${GRID_SIZE}_ranks${PROCS}.txt
        fi
    done
done

#=====================
# 4. VALGRIND with MPI ranks
#=====================
echo -e "${BLUE}Running Valgrind on a single MPI rank...${NC}"

# Note: Running valgrind with MPI can be tricky - we'll run on just one rank
valgrind --tool=cachegrind mpirun -n 1 ./heat_diffusion_mpi_benchmark --height 100 --width 100 --iterations 100 --runs 1 > ../profiling_results_mpi/valgrind/cachegrind_output.txt 2>&1

# Find the cachegrind output file
CACHEGRIND_FILE=$(ls cachegrind.out.*)
if [ -n "$CACHEGRIND_FILE" ]; then
    cg_annotate $CACHEGRIND_FILE > ../profiling_results_mpi/valgrind/cachegrind_report.txt
fi

#=====================
# 5. Generate Summary
#=====================
echo -e "${GREEN}Generating summary...${NC}"
cd ..

echo "MPI PROFILING SUMMARY" > profiling_results_mpi/summary.txt
echo "====================" >> profiling_results_mpi/summary.txt
echo "" >> profiling_results_mpi/summary.txt

# Add scaling results
echo "Strong Scaling Results:" >> profiling_results_mpi/summary.txt
for RANKS in 1 2 4 8 16; do
    if [ -f profiling_results_mpi/scaling/strong_scaling_${RANKS}ranks.txt ]; then
        echo "  ${RANKS} ranks:" >> profiling_results_mpi/summary.txt
        # Only grab the line with StdDev info to avoid duplicates
        grep "Average Iteration Time:.*StdDev" profiling_results_mpi/scaling/strong_scaling_${RANKS}ranks.txt | sort -u >> profiling_results_mpi/summary.txt 2>/dev/null
        
        # If no StdDev lines found, fall back to the regular ones and sort them unique
        if [ $? -ne 0 ]; then
            grep "Average Iteration Time:" profiling_results_mpi/scaling/strong_scaling_${RANKS}ranks.txt | sort -u >> profiling_results_mpi/summary.txt 2>/dev/null
        fi
    fi
done
# Add gprof summary from rank 0 (most representative)
if [ -f profiling_results_mpi/gprof/gprof_report_rank_0.txt ]; then
    echo "Top functions from gprof (rank 0):" >> profiling_results_mpi/summary.txt
    head -n 20 profiling_results_mpi/gprof/gprof_report_rank_0.txt >> profiling_results_mpi/summary.txt
    echo "" >> profiling_results_mpi/summary.txt
fi

# Analyze communication patterns
echo "MPI Communication Pattern Analysis:" >> profiling_results_mpi/summary.txt
echo "--------------------------------" >> profiling_results_mpi/summary.txt
echo "" >> profiling_results_mpi/summary.txt

echo "Grid Size Scaling with Fixed Rank Count (4 ranks):" >> profiling_results_mpi/summary.txt
for SIZE in 100 400 1000; do
    if [ -f profiling_results_mpi/communication/grid${SIZE}_ranks4.txt ]; then
        echo "  Grid ${SIZE}x${SIZE}:" >> profiling_results_mpi/summary.txt
        grep "Average Iteration Time:" profiling_results_mpi/communication/grid${SIZE}_ranks4.txt >> profiling_results_mpi/summary.txt 2>/dev/null
        grep "Performance:" profiling_results_mpi/communication/grid${SIZE}_ranks4.txt >> profiling_results_mpi/summary.txt 2>/dev/null
    fi
done
echo "" >> profiling_results_mpi/summary.txt

echo "Rank Scaling with Fixed Grid Size (400x400):" >> profiling_results_mpi/summary.txt
for RANKS in 1 2 4 8; do
    if [ -f profiling_results_mpi/communication/grid400_ranks${RANKS}.txt ]; then
        echo "  ${RANKS} ranks:" >> profiling_results_mpi/summary.txt
        grep "Average Iteration Time:" profiling_results_mpi/communication/grid400_ranks${RANKS}.txt >> profiling_results_mpi/summary.txt 2>/dev/null
        grep "Performance:" profiling_results_mpi/communication/grid400_ranks${RANKS}.txt >> profiling_results_mpi/summary.txt 2>/dev/null
    fi
done
echo "" >> profiling_results_mpi/summary.txt

# Calculate parallel efficiency
echo "Parallel Efficiency:" >> profiling_results_mpi/summary.txt
if [ -f profiling_results_mpi/scaling/strong_scaling_1ranks.txt ] && [ -f profiling_results_mpi/scaling/strong_scaling_4ranks.txt ]; then
    # Average Iteration Time: 
    TIME_1=$(grep "Average Iteration Time:" profiling_results_mpi/scaling/strong_scaling_1ranks.txt | awk '{print $4}')
    TIME_4=$(grep "Average Iteration Time:" profiling_results_mpi/scaling/strong_scaling_4ranks.txt | awk '{print $4}')
    
    # Calculate efficiency if we have valid numbers
    if [[ $TIME_1 =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ $TIME_4 =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        EFF=$(echo "scale=2; $TIME_1 / (4 * $TIME_4) * 100" | bc)
        echo "  4 ranks efficiency: ${EFF}%" >> profiling_results_mpi/summary.txt
    else
        echo "  Could not calculate efficiency (missing or invalid timing data)" >> profiling_results_mpi/summary.txt
    fi
fi
echo "" >> profiling_results_mpi/summary.txt

echo -e "${GREEN}MPI profiling complete! Results in profiling_results_mpi/ directory.${NC}"

# Show quick summary on screen
echo -e "${BLUE}Quick Results:${NC}"
if [ -f profiling_results_mpi/scaling/strong_scaling_1ranks.txt ]; then
    TIME_1=$(grep "Average Iteration Time:" profiling_results_mpi/scaling/strong_scaling_1ranks.txt | awk '{print $4}')
    echo -e "  Single rank time: ${TIME_1} ms"
fi

for RANKS in 2 4 8 16; do
    if [ -f profiling_results_mpi/scaling/strong_scaling_${RANKS}ranks.txt ]; then
        TIME=$(grep "Average Iteration Time:" profiling_results_mpi/scaling/strong_scaling_${RANKS}ranks.txt | awk '{print $4}')
        echo -e "  ${RANKS} ranks time: ${TIME} ms"
    fi
done

echo -e "${GREEN}See full details in profiling_results_mpi/summary.txt${NC}"