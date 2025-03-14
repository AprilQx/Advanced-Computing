/**
 * @file optimized_heat_diffusion.h
 * @brief 2D Heat Diffusion Simulation with customizable block sizes
 * 
 * Modified version of the heat diffusion class that exposes methods and members
 * needed for block size optimization.
 */

 #ifndef OPTIMIZED_HEAT_DIFFUSION_H
 #define OPTIMIZED_HEAT_DIFFUSION_H
 
 #include <string>
 #include "../../include/Array_2D/Array_2D.h"
 
 /**
  * @class OptimizedHeatDiffusion2D
  * @brief Class implementing optimized 2D heat diffusion simulation with block processing
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
 
 protected:
     /**
      * @brief Get access to the diffusion rate
      * @return The diffusion rate constant
      */
     double getDiffusionRate() const { return diffusionRate; }
     
     /**
      * @brief Get the width of the grid
      * @return The width of the grid
      */
     int getWidth() const { return width; }
     
     /**
      * @brief Get the height of the grid
      * @return The height of the grid
      */
     int getHeight() const { return height; }
     
     /**
      * @brief Get access to the temperature grid
      * @return Reference to the temperature grid
      */
     Array_2D<double>& getTemperature() { return temperature; }
     
     /**
      * @brief Get access to the next temperature grid
      * @return Reference to the next temperature grid
      */
     Array_2D<double>& getNextTemperature() { return nextTemperature; }
     
     /**
      * @brief Swap the temperature buffers
      */
     void swapBuffers() { temperature.swap(nextTemperature); }
 
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
      * @brief Virtual destructor for polymorphism
      */
     virtual ~OptimizedHeatDiffusion2D() = default;
     
     /**
      * @brief Updates the simulation by one timestep with block processing
      */
     virtual void update();
 
     /**
      * @brief Get a checksum of the current temperature state
      * @return Sum of all temperatures in the grid
      */
     double getChecksum() const;
 };
 
 #endif // OPTIMIZED_HEAT_DIFFUSION_H