#!/bin/bash

# Configuration
FLAGS=("-O0" "-O1" "-O2" "-O3" "-Ofast")
GRID_SIZES=(200 500 1000)
ITERATIONS=1000
RUNS=3

# Get absolute path to project root
PROJECT_ROOT="/app"
RESULTS_DIR="${PROJECT_ROOT}/scripts/compiler_flags_results"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# CSV header
echo "Grid Size,Flag,Average Time (ms),Performance (MCUPS),Memory Usage (KB)" > "${RESULTS_DIR}/results.csv"

for size in "${GRID_SIZES[@]}"; do
    for flag in "${FLAGS[@]}"; do
        echo "Testing grid size $size with flag $flag"
        
        # Clean build directory
        rm -rf "${PROJECT_ROOT}/build"
        mkdir -p "${PROJECT_ROOT}/build"
        cd "${PROJECT_ROOT}/build"
        
        # Use CMAKE_BUILD_TYPE=None to prevent default optimization flags
        # Then explicitly set the optimization flag we want to test
        cmake "${PROJECT_ROOT}" -DCMAKE_BUILD_TYPE=None -DCMAKE_CXX_FLAGS="$flag"
        
        # Verify the compiler flags being used (optional but helpful)
        echo "Verifying compiler flags..."
        make VERBOSE=1 heat_diffusion_benchmark | grep "CXX" | head -n 1
        
        make heat_diffusion_benchmark
        
        # Run benchmark
        if [ -f "./heat_diffusion_benchmark" ]; then
            output=$(./heat_diffusion_benchmark --width $size --height $size --frames $ITERATIONS --runs $RUNS)
            
            # Extract metrics
            avg_time=$(echo "$output" | grep "Average Iteration Time:" | awk '{print $4}')
            performance=$(echo "$output" | grep "Average Performance:" | awk '{print $3}')
            memory=$(echo "$output" | grep "Average Memory Increase:" | awk '{print $4}')
            
            # Save to CSV
            echo "$size,$flag,$avg_time,$performance,$memory" >> "${RESULTS_DIR}/results.csv"
        else
            echo "Error: heat_diffusion_benchmark executable not found"
            echo "$size,$flag,ERROR,ERROR,ERROR" >> "${RESULTS_DIR}/results.csv"
        fi
        
        # Return to scripts directory for next iteration
        cd "${PROJECT_ROOT}/scripts"
    done
done

echo "Data collection complete. Results in ${RESULTS_DIR}/results.csv"