/**
 * @file optimized_heat_diffusion_omp.h
 * @brief 2D Heat Diffusion Simulation using OpenMP Parallelization
 * 
 * This header file defines the OpenMPHeatDiffusion2D class which implements
 * a heat diffusion simulation with OpenMP parallelization.
 */

 #ifndef OPENMP_HEAT_DIFFUSION_H
 #define OPENMP_HEAT_DIFFUSION_H
 
 #include <string>
 #include <omp.h>
 #include "../../include/Array_2D/Array_2D.h"
 
 /**
  * @class OpenMPHeatDiffusion2D
  * @brief Class implementing OpenMP-parallelized 2D heat diffusion simulation
  */
 class OpenMPHeatDiffusion2D {
 private:
     int width, height;              ///< Dimensions of the simulation grid
     double diffusionRate;           ///< Thermal diffusivity coefficient
     Array_2D<double> temperature;   ///< Current temperature grid
     Array_2D<double> nextTemperature; ///< Buffer for next timestep
     bool saveOutput;                ///< Flag to control whether to save output files
     int frameCount;                 ///< Counter for frames
     int numThreads;                 ///< Number of OpenMP threads to use
 
     /**
      * @brief Saves the current temperature grid to a file
      * @param frameNumber The current frame number for the output filename
      */
     void saveFrame(int frameNumber);
 
 public:
     /**
      * @brief Constructor for the OpenMP-parallelized HeatDiffusion simulation
      * @param w Width of the simulation grid
      * @param h Height of the simulation grid
      * @param rate Thermal diffusivity coefficient
      * @param save Flag to control whether output files are saved
      * @param threads Number of OpenMP threads to use (0 = use system default)
      */
     OpenMPHeatDiffusion2D(int w, int h, double rate, bool save = true, int threads = 0);
     
     /**
      * @brief Updates the simulation by one timestep using OpenMP parallelization
      */
     void update();
 
     /**
      * @brief Get a checksum of the current temperature state
      * @return Sum of all temperatures in the grid
      */
     double getChecksum() const;
     
     /**
      * @brief Set the number of threads to use for OpenMP parallelization
      * @param threads Number of threads (0 = use default)
      */
     void setNumThreads(int threads);
     
     /**
      * @brief Get the number of threads being used
      * @return Number of OpenMP threads
      */
     int getNumThreads() const;
 };
 
 #endif // OPENMP_HEAT_DIFFUSION_H