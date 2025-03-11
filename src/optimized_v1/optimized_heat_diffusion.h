/**
 * @file optimized_heat_diffusion.h
 * @brief Optimized 2D Heat Diffusion Simulation using the Finite Difference Method
 */

 #ifndef OPTIMIZED_HEAT_DIFFUSION_H
 #define OPTIMIZED_HEAT_DIFFUSION_H
 
 #include <string>
 
 /**
 * @class OptimizedHeatDiffusion
 * @brief Class implementing an optimized 2D heat diffusion simulation
 */
 class OptimizedHeatDiffusion {
 private:
    int width, height;              ///< Dimensions of the simulation grid
    double diffusionRate;           ///< Thermal diffusivity coefficient
    double* temperature;            ///< Current temperature grid (flat array)
    double* nextTemperature;        ///< Buffer for next timestep (flat array)
    bool saveOutput;                ///< Flag to control whether to save output files
    int frameCount;                 ///< Counter for tracking frames
 
    /**
     * @brief Get array index from 2D coordinates
     * @param y Row index
     * @param x Column index
     * @return Linear index in the flat array
     */
    inline int idx(int y, int x) const {
        return y * width + x;
    }
 
 public:
    /**
     * @brief Constructor for the OptimizedHeatDiffusion simulation
     * @param w Width of the simulation grid
     * @param h Height of the simulation grid
     * @param rate Thermal diffusivity coefficient
     * @param save Flag to control whether output files are saved
     */
    OptimizedHeatDiffusion(int w, int h, double rate, bool save = true);
    
    /**
     * @brief Destructor to free allocated memory
     */
    ~OptimizedHeatDiffusion();
 
    /**
     * @brief Updates the simulation by one timestep
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
 
 #endif // OPTIMIZED_HEAT_DIFFUSION_H