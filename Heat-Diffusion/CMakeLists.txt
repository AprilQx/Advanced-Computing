cmake_minimum_required(VERSION 3.10)
project(heat_diffusion)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)  # Raised to 17 for filesystem support
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(MPI REQUIRED)

# Force the use of mpicxx for compilation of MPI code on macOS
if(APPLE)
    set(CMAKE_CXX_COMPILER mpicxx)
endif()

# On macOS, we may need to add special handling for MPI
if(APPLE)
    # Check if we're using Open MPI (common on macOS via Homebrew/MacPorts)
    execute_process(
        COMMAND ${MPICC} --showme:version
        OUTPUT_VARIABLE MPI_VERSION_OUTPUT
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    
    if(MPI_VERSION_OUTPUT MATCHES "Open MPI")
        message(STATUS "Using Open MPI on macOS")
        # Add any Mac-specific Open MPI flags if needed
    endif()
endif()


# Add include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/tools
                    ${CMAKE_CURRENT_SOURCE_DIR}/src
                    ${CMAKE_CURRENT_SOURCE_DIR}/include)

# Set output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

# Platform detection for CSD3
set(CSD3_PLATFORM FALSE)
if(UNIX AND NOT APPLE)
    # Check specific platform - CSD3 detection
    execute_process(
        COMMAND hostname
        OUTPUT_VARIABLE HOSTNAME
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    
    if(HOSTNAME MATCHES ".*csd3.*" OR HOSTNAME MATCHES ".*login-q.*")
        message(STATUS "CSD3 platform detected: ${HOSTNAME}")
        set(CSD3_PLATFORM TRUE)
    endif()
endif()

# Find MPI for CSD3 optimized version
if(CSD3_PLATFORM)
    find_package(MPI)
    if(MPI_FOUND)
        message(STATUS "MPI found: ${MPI_CXX_LIBRARIES}")
        include_directories(${MPI_INCLUDE_PATH})
    else()
        message(WARNING "MPI not found on CSD3, optimized version may not work properly")
    endif()
    
    # Find OpenMP for CSD3
    find_package(OpenMP)
    if(OpenMP_CXX_FOUND)
        message(STATUS "OpenMP found")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
    else()
        message(WARNING "OpenMP not found on CSD3, optimized version may not work properly")
    endif()
endif()

# Define separate flag lists for different targets
set(BASE_FLAGS_LIST "-O3")
set(DEV_FLAGS_LIST "-g")
set(BENCHMARK_FLAGS_LIST "")

# Option to customize benchmark compilation
# option(DISABLE_DENORMALS "Disable denormal floating point numbers in benchmarks" ON)
# option(ENABLE_LOOP_UNROLLING "Enable aggressive loop unrolling in benchmarks" ON)
# option(ENABLE_AUTO_VECTORIZATION "Enable auto-vectorization in benchmarks" ON)
# option(DISABLE_MATH_ERRNO "Disable setting errno for math functions in benchmarks" ON)

# # Compiler-specific optimization flags for macOS
# if(APPLE)
#     # Detect Apple Clang version
#     execute_process(COMMAND ${CMAKE_CXX_COMPILER} --version OUTPUT_VARIABLE clang_full_version_string)
#     string(REGEX REPLACE ".*clang version ([0-9]+\\.[0-9]+).*" "\\1" CLANG_VERSION_STRING ${clang_full_version_string})
    
#     # Use appropriate architecture flags for Apple Silicon / Intel
#     execute_process(COMMAND uname -m OUTPUT_VARIABLE ARCH OUTPUT_STRIP_TRAILING_WHITESPACE)
#     if(${ARCH} STREQUAL "arm64")
#         # Apple Silicon optimizations
#         list(APPEND BASE_FLAGS_LIST "-mcpu=apple-m1")
#         message(STATUS "Detected Apple Silicon (ARM64)")
#     else()
#         # Intel Mac optimizations
#         list(APPEND BASE_FLAGS_LIST "-march=native")
#         message(STATUS "Detected Intel Mac (${ARCH})")
#     endif()
    
#     # Add fast math option
#     # option(USE_FAST_MATH "Enable fast math optimizations" ON)
#     # if(USE_FAST_MATH)
#     #     list(APPEND BASE_FLAGS_LIST "-ffast-math")
#     # endif()
# # CSD3-specific flags
# elseif(CSD3_PLATFORM)
#     # Determine specific CPU architecture on CSD3
#     if(HOSTNAME MATCHES ".*icelake.*" OR HOSTNAME MATCHES ".*login-q.*")
#         list(APPEND BASE_FLAGS_LIST "-march=icelake-server")
#         message(STATUS "Using CSD3 Icelake optimizations")
#     elseif(HOSTNAME MATCHES ".*cclake.*")
#         list(APPEND BASE_FLAGS_LIST "-march=cascadelake")
#         message(STATUS "Using CSD3 Cascade Lake optimizations")
#     elseif(HOSTNAME MATCHES ".*ampere.*")
#         list(APPEND BASE_FLAGS_LIST "-march=znver3")
#         message(STATUS "Using CSD3 Ampere optimizations")
#     else()
#         list(APPEND BASE_FLAGS_LIST "-march=native")
#         message(STATUS "Using generic optimizations for CSD3")
#     endif()
    
#     option(USE_FAST_MATH "Enable fast math optimizations" ON)
#     if(USE_FAST_MATH)
#         list(APPEND BASE_FLAGS_LIST "-ffast-math")
#     endif()
# else()
#     # Non-Apple compiler flags
#     if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
#         list(APPEND BASE_FLAGS_LIST "-march=native")
#         option(USE_FAST_MATH "Enable fast math optimizations" ON)
#         if(USE_FAST_MATH)
#             list(APPEND BASE_FLAGS_LIST "-ffast-math")
#         endif()
#     elseif(CMAKE_CXX_COMPILER_ID MATCHES "Intel")
#         list(APPEND BASE_FLAGS_LIST "-xHost")
#     elseif(MSVC)
#         set(BASE_FLAGS_LIST "/O3" "/Ot" "/GL")
#         set(DEV_FLAGS_LIST "/Zi" "/DEBUG")
#         set(BENCHMARK_FLAGS_LIST "")
#     endif()
# endif()

# Add additional benchmark-specific optimizations
# if(NOT MSVC)
    
#     # Add useful reporting flags for debugging benchmark performance
#     option(ENABLE_OPTIMIZATION_REPORTS "Enable optimization reports for benchmarks" OFF)
#     if(ENABLE_OPTIMIZATION_REPORTS)
#         if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
#             list(APPEND BENCHMARK_FLAGS_LIST "-fopt-info-vec-all")
#         elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
#             list(APPEND BENCHMARK_FLAGS_LIST "-Rpass=loop-vectorize")
#             list(APPEND BENCHMARK_FLAGS_LIST "-Rpass-missed=loop-vectorize")
#         elseif(CMAKE_CXX_COMPILER_ID MATCHES "Intel")
#             list(APPEND BENCHMARK_FLAGS_LIST "-qopt-report=5")
#             list(APPEND BENCHMARK_FLAGS_LIST "-qopt-report-phase=vec")
#         endif()
#     endif()
# endif()

# Source files for main program
set(BASE_SOURCES
    src/base/heat_diffusion.cpp
    src/base/main.cpp
)

# Source files for optimized program
set(OPTIMIZED_SOURCES_v1
    src/optimized_v1/optimized_heat_diffusion.cpp
    src/optimized_v1/main_optimized.cpp
)

# Source files for optimized program
set(OPTIMIZED_SOURCES_v2
    src/optimized_v2/optimized_heat_diffusion.cpp
    src/optimized_v2/main_optimized.cpp
)

# Benchmark sources
set(BENCHMARK_SOURCES
    benchmark/heat_diffusion_benchmark_timing.cpp
    src/base/heat_diffusion.cpp
)

# MPI implementation sources
set(MPI_SOURCES
    src/mpi/main_mpi.cpp  # Using proper main file instead of header
    src/mpi/optimized_heat_diffusion_mpi.cpp
    src/base/heat_diffusion.cpp  # Include the base implementation for validation
)


# Optimized benchmark sources
set(OPTIMIZED_BENCHMARK_SOURCES_v1
    benchmark/heat_diffusion_benchmark_optimised_timing_v1.cpp
    src/optimized_v1/optimized_heat_diffusion.cpp
)


# Optimized benchmark sources
set(OPTIMIZED_BENCHMARK_SOURCES_v2
    benchmark/heat_diffusion_benchmark_optimised_timing_v2.cpp
    src/optimized_v2/optimized_heat_diffusion.cpp
)

# Validation tool sources
set(VALIDATION_SOURCES
    tools/validate.cpp
)

# Test validation sources
set(TEST_VALIDATION_SOURCES
    tools/test_validation.cpp
)

# Add filesystem library linking for GCC 8.5
if(CMAKE_COMPILER_IS_GNUCXX AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS 9.0)
    message(STATUS "GCC version less than 9.0, linking with stdc++fs for filesystem support")
    set(FILESYSTEM_LIBRARIES stdc++fs)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang" AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS 9.0 AND NOT APPLE)
    message(STATUS "Clang version less than 9.0, linking with stdc++fs for filesystem support")
    set(FILESYSTEM_LIBRARIES stdc++fs)
else()
    set(FILESYSTEM_LIBRARIES "")
endif()

# Convert lists to strings for display only
string(REPLACE ";" " " BASE_FLAGS_STR "${BASE_FLAGS_LIST}")
string(REPLACE ";" " " DEV_FLAGS_STR "${DEV_FLAGS_LIST}")
string(REPLACE ";" " " BENCHMARK_FLAGS_STR "${BENCHMARK_FLAGS_LIST}")

# Main executables - use development flags (includes debug info)

#base
add_executable(heat_diffusion ${BASE_SOURCES})
target_compile_options(heat_diffusion PRIVATE ${BASE_FLAGS_LIST} ${DEV_FLAGS_LIST})
if(FILESYSTEM_LIBRARIES)
    target_link_libraries(heat_diffusion PRIVATE ${FILESYSTEM_LIBRARIES})
endif()


#v1
add_executable(heat_diffusion_optimized_v1 ${OPTIMIZED_SOURCES_v1})
target_compile_options(heat_diffusion_optimized_v1 PRIVATE ${BASE_FLAGS_LIST} ${DEV_FLAGS_LIST})
if(FILESYSTEM_LIBRARIES)
    target_link_libraries(heat_diffusion_optimized_v1 PRIVATE ${FILESYSTEM_LIBRARIES})
endif()


#v2
add_executable(heat_diffusion_optimized_v2 ${OPTIMIZED_SOURCES_v2})
target_compile_options(heat_diffusion_optimized_v2 PRIVATE ${BASE_FLAGS_LIST} ${DEV_FLAGS_LIST})
if(FILESYSTEM_LIBRARIES)
    target_link_libraries(heat_diffusion_optimized_v2 PRIVATE ${FILESYSTEM_LIBRARIES})
endif()


#mpi
add_executable(heat_diffusion_mpi ${MPI_SOURCES})
target_compile_options(heat_diffusion_mpi PRIVATE ${BASE_FLAGS_LIST} ${DEV_FLAGS_LIST})
target_link_libraries(heat_diffusion_mpi PRIVATE MPI::MPI_CXX)
if(FILESYSTEM_LIBRARIES)
    target_link_libraries(heat_diffusion_mpi PRIVATE ${FILESYSTEM_LIBRARIES})
endif()

# Benchmark executables - use benchmark flags (no debug info, additional optimizations)
add_executable(heat_diffusion_benchmark ${BENCHMARK_SOURCES})
target_compile_options(heat_diffusion_benchmark PRIVATE ${BASE_FLAGS_LIST} ${BENCHMARK_FLAGS_LIST})
if(FILESYSTEM_LIBRARIES)
    target_link_libraries(heat_diffusion_benchmark PRIVATE ${FILESYSTEM_LIBRARIES})
endif()

add_executable(heat_diffusion_optimized_benchmark_v1 ${OPTIMIZED_BENCHMARK_SOURCES_v1})
target_compile_options(heat_diffusion_optimized_benchmark_v1 PRIVATE ${BASE_FLAGS_LIST} ${BENCHMARK_FLAGS_LIST})
if(FILESYSTEM_LIBRARIES)
    target_link_libraries(heat_diffusion_optimized_benchmark_v1 PRIVATE ${FILESYSTEM_LIBRARIES})
endif()


add_executable(heat_diffusion_optimized_benchmark_v2 ${OPTIMIZED_BENCHMARK_SOURCES_v2})
target_compile_options(heat_diffusion_optimized_benchmark_v2 PRIVATE ${BASE_FLAGS_LIST} ${BENCHMARK_FLAGS_LIST})
if(FILESYSTEM_LIBRARIES)
    target_link_libraries(heat_diffusion_optimized_benchmark_v2 PRIVATE ${FILESYSTEM_LIBRARIES})
endif()


# Validation tools - use development flags
add_executable(validate ${VALIDATION_SOURCES})
target_compile_options(validate PRIVATE ${BASE_FLAGS_LIST} ${DEV_FLAGS_LIST})
if(FILESYSTEM_LIBRARIES)
    target_link_libraries(validate PRIVATE ${FILESYSTEM_LIBRARIES})
endif()

add_executable(test_validation ${TEST_VALIDATION_SOURCES})
target_compile_options(test_validation PRIVATE ${BASE_FLAGS_LIST} ${DEV_FLAGS_LIST})
if(FILESYSTEM_LIBRARIES)
    target_link_libraries(test_validation PRIVATE ${FILESYSTEM_LIBRARIES})
endif()

# Option to enable validation (default on )
option(ENABLE_VALIDATION "Enable validation mode for simulations" on)
if(ENABLE_VALIDATION)
    target_compile_definitions(heat_diffusion PRIVATE ENABLE_VALIDATION)
    target_compile_definitions(heat_diffusion_optimized_v1 PRIVATE ENABLE_VALIDATION)
    target_compile_definitions(heat_diffusion_optimized_v2 PRIVATE ENABLE_VALIDATION)
    target_compile_definitions(heat_diffusion_mpi PRIVATE ENABLE_VALIDATION)
    message(STATUS "Validation mode enabled for heat_diffusion")
endif()

# Create output directories
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/output/base)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/output/optimised)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/output/mpi)

# macOS-specific mkdir command for scripts
if(APPLE)
    set(MKDIR_COMMAND "mkdir -p")
else()
    set(MKDIR_COMMAND "mkdir -p")
endif()



# Install targets
install(TARGETS 
        heat_diffusion 
        heat_diffusion_optimized_v1 
        heat_diffusion_optimized_v2 
        heat_diffusion_mpi 
        validate 
        test_validation 
        heat_diffusion_benchmark 
        heat_diffusion_optimized_benchmark_v1 
        heat_diffusion_optimized_benchmark_v2
        RUNTIME DESTINATION bin)



# Enable testing
enable_testing()

# Add test for validation
add_test(NAME ValidateSelf
         COMMAND validate --baseline ${CMAKE_CURRENT_SOURCE_DIR}/test/reference
                         --optimized ${CMAKE_CURRENT_SOURCE_DIR}/test/reference
                         --tolerance 1e-15)

# Add validation test for MPI version
add_test(NAME ValidateMPI
COMMAND validate --baseline ${CMAKE_BINARY_DIR}/output/base
                --optimized ${CMAKE_BINARY_DIR}/output/mpi
                --tolerance 1e-10)



add_custom_target(run_mpi
COMMAND mpirun -np 4 --oversubscribe $<TARGET_FILE:heat_diffusion_mpi>
DEPENDS heat_diffusion_mpi
WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
COMMENT "Running MPI version with 4 processes (macOS)"
)
# Print status information
message(STATUS "========== Configuration Summary ==========")
message(STATUS "Operating System: ${CMAKE_SYSTEM_NAME}")
if(CSD3_PLATFORM)
    message(STATUS "Platform: CSD3 (${HOSTNAME})")
elseif(APPLE)
    message(STATUS "Platform: macOS (${ARCH})")
else()
    message(STATUS "Platform: Generic")
endif()
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "Compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "C++ standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "Base flags: ${BASE_FLAGS_STR}")
message(STATUS "Development flags: ${DEV_FLAGS_STR}")
message(STATUS "Benchmark flags: ${BENCHMARK_FLAGS_STR}")
message(STATUS "Filesystem libraries: ${FILESYSTEM_LIBRARIES}")
message(STATUS "MPI support: ${MPI_FOUND}")
if(CSD3_PLATFORM)
    message(STATUS "OpenMP support: ${OpenMP_CXX_FOUND}")
endif()
message(STATUS "==========================================")