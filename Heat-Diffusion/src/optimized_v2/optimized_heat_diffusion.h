/**
 * @file optimized_heat_diffusion.h
 * @brief 2D Heat Diffusion Simulation using 2D arrays with cache blocking
 */

 #ifndef OPTIMIZED_HEAT_DIFFUSION_H
 #define OPTIMIZED_HEAT_DIFFUSION_H
 
 #include <string>
 
 /**
 * @class OptimizedHeatDiffusion2D
 * @brief Class implementing optimized 2D heat diffusion simulation with 2D arrays
 */
 class OptimizedHeatDiffusion2D {
 private:
     int width, height;              ///< Dimensions of the simulation grid
     double diffusionRate;           ///< Thermal diffusivity coefficient
     double** temperature;          ///< Current temperature grid (2D array)
     double** nextTemperature;      ///< Buffer for next timestep (2D array)
     bool saveOutput;                ///< Flag to control whether to save output files
     int frameCount;                ///< Counter for frames
 
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
      * @brief Destructor to free allocated memory
      */
     ~OptimizedHeatDiffusion2D();
 
     /**
      * @brief Updates the simulation by one timestep with cache blocking
      */
     void update();
 
     /**
      * @brief Get a checksum of the current temperature state
      * @return Sum of all temperatures in the grid
      */
     double getChecksum() const;
 
     /**
      * @brief Saves the current temperature grid to a file
      * @param frameNumber The current frame number for the output filename
      */
     void saveFrame(int frameNumber);
 };
 
 #endif // OPTIMIZED_HEAT_DIFFUSION_2D_H