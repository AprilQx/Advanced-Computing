#!/bin/bash
#SBATCH -J heat_diff      # Job name
#SBATCH -A MPHIL-DIS-SL2-CPU  # Account code (update this to your account)
#SBATCH -p icelake        # Partition (queue)
#SBATCH -N 1              # Number of nodes
#SBATCH -n 4              # Number of MPI tasks
#SBATCH -c 8              # Cores per task (for OpenMP)
#SBATCH -t 00:30:00       # Time limit (HH:MM:SS)
#SBATCH -o heat_diff_%j.out  # Output file
#SBATCH -e heat_diff_%j.err  # Error file

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set project directory - update this to your directory
PROJECT_DIR="/home/xx823/Advanced-Computing" 

echo -e "${GREEN}Setting up environment on CSD3...${NC}"


#=====================
# 1. Baseline and Optimized Implementations
#=====================


# Go to project directory
cd ${PROJECT_DIR}

# Create and navigate to build directory
echo -e "${BLUE}Building project...${NC}"
mkdir -p build
cd build

# Configure and build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j 8

echo -e "${GREEN}Build complete! Running examples...${NC}"

# Set OpenMP threads
export OMP_NUM_THREADS=8
export OMP_PLACES=cores
export OMP_PROC_BIND=close

echo -e "\n${BLUE}1. Running baseline implementation:${NC}"
./heat_diffusion --width 500 --height 500 --frames 100

echo -e "\n${BLUE}2. Running optimized v1 implementation:${NC}"
./heat_diffusion_optimized_v1 --width 500 --height 500 --frames 100

echo -e "\n${BLUE}3. Running optimized v2 implementation:${NC}"
./heat_diffusion_optimized_v2 --width 500 --height 500 --frames 100

echo -e "\n${BLUE}4. Running optimized v3 implementation (cache blocked):${NC}"
./heat_diffusion_optimized_v3 --width 1000 --height 1000 --frames 100

echo -e "\n${BLUE}5. Running OpenMP implementation:${NC}"
./heat_diffusion_openmp --width 1000 --height 1000 --frames 100 --threads 8


#=====================
# 2. MPI and Hybrid MPI+OpenMP Implementations
#=====================
# Load Intel MPI module
module purge
module load rhel8/default-icl

cd ${PROJECT_DIR}
# Create build directory
mkdir -p build
cd build

# Configure and build
echo -e "${BLUE}Configuring and building with Intel MPI...${NC}"

# Build with normal optimization
CC=mpiicc CXX=mpiicpc cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-march=icelake-server -O3"
make -j 76 heat_diffusion_mpi_benchmark

echo -e "\n${BLUE}6. Running MPI implementation:${NC}"
mpirun -np 4 ./heat_diffusion_mpi --width 1000 --height 1000 --frames 100

echo -e "\n${BLUE}7. Running Hybrid MPI+OpenMP implementation:${NC}"
mpirun -np 4 ./heat_diffusion_hybrid --width 2000 --height 2000 --frames 100

echo -e "\n${GREEN}All examples completed!${NC}"