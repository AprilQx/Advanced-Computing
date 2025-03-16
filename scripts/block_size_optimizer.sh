#!/bin/bash
#SBATCH -J heat_diff_opt          # Job name
#SBATCH -A  MPHIL-DIS-SL2-CPU        # Replace with your account code
#SBATCH -p icelake                # Partition (queue) - icelake nodes
#SBATCH -N 1                      # Number of nodes
#SBATCH -n 1                      # Number of tasks (processes)
#SBATCH -c 1                      # Number of cores per task (for single thread)
#SBATCH -t 01:00:00               # Time limit (HH:MM:SS)
#SBATCH -o heat_diff_%j.out       # Standard output file (%j expands to jobid)
#SBATCH -e heat_diff_%j.err       # Standard error file

# Display information about the job
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Start time: $(date)"

# Load necessary modules
module purge
module load gcc/13.3.0/7ukda7ns            # Or any preferred compiler
      # For build process

# Navigate to your project directory
cd Advanced-Computing/build # Replace with your actual project path


# Build the project with optimizations

rm -rf *
make ..
./block_size_optimizer

# Print job completion information
echo "End time: $(date)"