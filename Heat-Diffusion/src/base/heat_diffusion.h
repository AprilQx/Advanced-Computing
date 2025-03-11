/**
 * @file HeatDiffusion.h
 * @brief 2D Heat Diffusion Simulation using the Finite Difference Method
 * 
 * This header defines the HeatDiffusion class for simulating heat diffusion
 * on a 2D grid using the heat equation: ∂T/∂t = α∇²T
 */


#ifndef HEAT_DIFFUSION_H
#define HEAT_DIFFUSION_H

#include <vector>
#include <string>

/**
* @class HeatDiffusion
* @brief Class implementing the 2D heat diffusion simulation
* 
* Uses a double-buffered grid approach to update temperatures and
* implements the explicit finite difference method for the heat equation.
*/
class HeatDiffusion {
private:
   int width, height;              ///< Dimensions of the simulation grid
   double diffusionRate;           ///< Thermal diffusivity coefficient
   std::vector<std::vector<double>> temperature;    ///< Current temperature grid
   std::vector<std::vector<double>> nextTemperature; ///< Buffer for next timestep
   bool saveOutput;                ///< Flag to control whether to save output files


public:
   /**
    * @brief Constructor for the HeatDiffusion simulation
    * @param w Width of the simulation grid
    * @param h Height of the simulation grid
    * @param rate Thermal diffusivity coefficient
    * @param save Flag to control whether output files are saved
    * 
    * Initializes the temperature grids and sets up initial conditions
    * with a hot spot in the center of the grid.
    */
   HeatDiffusion(int w, int h, double rate, bool save = true);

   /**
    * @brief Updates the simulation by one timestep
    * 
    * Implements the finite difference method:
    * T(t+dt) = T(t) + α * [T(x+1,y) + T(x-1,y) + T(x,y+1) + T(x,y-1) - 4T(x,y)]
    * 
    * Uses double buffering to properly update all cells simultaneously.
    * Saves the temperature grid every 10 timesteps if saveOutput is true.
    */
   void update();

   /**
    * @brief Get a checksum of the current temperature state
    * @return Sum of all temperatures in the grid
    * 
    * Useful for validation of simulation correctness across different implementations.
    */
   double getChecksum() const;

    /**
    * @brief Saves the current temperature grid to a file
    * @param frameNumber The current frame number for the output filename
    * 
    * Creates a space-separated text file containing the temperature values.
    * Files are saved in the 'output' directory with names 'frame_X.txt'
    * where X is the frame number.
    */
   void saveFrame(int frameNumber);
};

#endif // HEAT_DIFFUSION_H