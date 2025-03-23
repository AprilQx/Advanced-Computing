/**
 * @file optimized_heat_diffusion_hybrid.h
 * @brief Hybrid MPI+OpenMP Parallelized 2D Heat Diffusion Simulation
 */

 #ifndef OPTIMIZED_HEAT_DIFFUSION_HYBRID_H
 #define OPTIMIZED_HEAT_DIFFUSION_HYBRID_H
 
 #include <string>
 #include <mpi.h>
 #include <omp.h>
 #include "../../include/Array_2D/Array_2D.h"
 
 /**
  * @class HybridHeatDiffusion2D
  * @brief Class implementing a hybrid MPI+OpenMP parallelized 2D heat diffusion simulation
  */
 class HybridHeatDiffusion2D {
 private:
     int globalWidth, globalHeight;   ///< Dimensions of the full simulation grid
     int localWidth, localHeight;     ///< Dimensions of local subdomain for this MPI rank
     int startRow, startCol;          ///< Starting indices for local subdomain
     double diffusionRate;            ///< Thermal diffusivity coefficient
     Array_2D<double> temperature;    ///< Current temperature grid (with ghost cells)
     Array_2D<double> nextTemperature; ///< Buffer for next timestep (with ghost cells)
     bool saveOutput;                 ///< Flag to control whether to save output files
     int frameCount;                  ///< Counter for tracking frames
     int numThreads;                  ///< Number of OpenMP threads per MPI rank
     
     int rank;                        ///< MPI rank of this process
     int worldSize;                   ///< Total number of MPI processes
     int dims[2];                     ///< Dimensions of the process grid
     MPI_Comm cartComm;               ///< Cartesian communicator
     int neighbors[4];                ///< Ranks of neighbors: 0=north, 1=east, 2=south, 3=west
     
     // MPI datatypes for halo exchange
     MPI_Datatype haloRowType;        ///< Datatype for a row of the halo
     MPI_Datatype haloColType;        ///< Datatype for a column of the halo
 
     /**
      * @brief Initialize MPI communication patterns and subdomain decomposition
      */
     void initMPI();
     
     /**
      * @brief Exchange ghost cells with neighboring processes
      */
     void exchangeHalos();
     
     /**
      * @brief Gather all subdomain data to rank 0 for checksum or output
      * @param gatheredData Full temperature grid (only valid on rank 0)
      */
     void gatherGrid(double* gatheredData);
 
     /**
      * @brief Set up OpenMP environment
      */
     void setupOpenMP();
 
 public:
     /**
      * @brief Constructor for the HybridHeatDiffusion2D simulation
      * @param w Width of the global simulation grid
      * @param h Height of the global simulation grid
      * @param rate Thermal diffusivity coefficient
      * @param save Flag to control whether output files are saved
      * @param threads Number of OpenMP threads per MPI rank (0 = use system default)
      */
     HybridHeatDiffusion2D(int w, int h, double rate, bool save = true, int threads = 0);
     
     /**
      * @brief Destructor to free allocated memory and finalize MPI datatypes
      */
     ~HybridHeatDiffusion2D();
 
     /**
      * @brief Updates the simulation by one timestep
      */
     void update();
 
     /**
      * @brief Get a checksum of the current temperature state
      * @return Sum of all temperatures in the entire grid (same on all processes)
      */
     double getChecksum();
 
     /**
      * @brief Saves the current temperature grid to a file (rank 0 only)
      * @param frameNumber The current frame number for the output filename
      */
     void saveFrame(int frameNumber);
     
     /**
      * @brief Get the number of OpenMP threads being used per MPI rank
      * @return Number of OpenMP threads
      */
     int getNumThreads() const;
     
     /**
      * @brief Set the number of threads to use for OpenMP parallelization
      * @param threads Number of threads (0 = use default)
      */
     void setNumThreads(int threads);
 };
 
 #endif // OPTIMIZED_HEAT_DIFFUSION_HYBRID_H