/**
 * @file optimized_heat_diffusion.h
 * @brief 2D Heat Diffusion Simulation using Flat Array Access
 * 
 * This header file defines the OptimizedHeatDiffusion2D class which implements
 * a heat diffusion simulation with optimized flat array access patterns.
 */

 #ifndef OPTIMIZED_HEAT_DIFFUSION_H
 #define OPTIMIZED_HEAT_DIFFUSION_H
 
 #include <string>
 #include "../../include/Array_2D/Array_2D.h"
 
 /**
  * @class OptimizedHeatDiffusion2D
  * @brief Class implementing optimized 2D heat diffusion simulation with flat array access
  */
 class OptimizedHeatDiffusion2D {
 private:
     int width, height;              ///< Dimensions of the simulation grid
     double diffusionRate;           ///< Thermal diffusivity coefficient
     Array_2D<double> temperature;   ///< Current temperature grid
     Array_2D<double> nextTemperature; ///< Buffer for next timestep
     bool saveOutput;                ///< Flag to control whether to save output files
     int frameCount;                 ///< Counter for frames
 
     /**
      * @brief Saves the current temperature grid to a file
      * @param frameNumber The current frame number for the output filename
      */
     void saveFrame(int frameNumber);
 
 public:
     /**
      * @brief Constructor for the optimized HeatDiffusion simulation
      * @param w Width of the simulation grid
      * @param h Height of the simulation grid
      * @param rate Thermal diffusivity coefficient
      * @param save Flag to control whether output files are saved
      */
     OptimizedHeatDiffusion2D(int w, int h, double rate, bool save = true);
     
     /**
      * @brief Updates the simulation by one timestep with flat array access
      */
     void update();
 
     /**
      * @brief Get a checksum of the current temperature state
      * @return Sum of all temperatures in the grid
      */
     double getChecksum() const;
 };
 
 #endif // OPTIMIZED_HEAT_DIFFUSION_H