#!/bin/bash
# Standalone validation script for comparing baseline and optimized implementations

# Exit on error
set -e

# Default settings
GRID_WIDTH=100
GRID_HEIGHT=100
DIFFUSION_RATE=0.1
TOTAL_FRAMES=100
BASELINE_DIR="baseline"
BASELINE_OUTPUT="baseline_output"
OPTIMIZED_DIR="optimized"
OPTIMIZED_OUTPUT="optimized_output"
TOLERANCE=1e-10
MAX_FRAMES=0
CHECKSUM_ONLY=0

# Print usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --help                 Show this help message"
    echo "  --width WIDTH          Set grid width (default: 100)"
    echo "  --height HEIGHT        Set grid height (default: 100)"
    echo "  --rate RATE            Set diffusion rate (default: 0.1)"
    echo "  --frames FRAMES        Set number of frames to simulate (default: 100)"
    echo "  --baseline-dir DIR     Baseline build directory (default: baseline)"
    echo "  --baseline-output DIR  Baseline output directory (default: baseline_output)"
    echo "  --optimized-dir DIR    Optimized build directory (default: optimized)"
    echo "  --optimized-output DIR Optimized output directory (default: optimized_output)"
    echo "  --tolerance TOL        Tolerance for floating point comparisons (default: 1e-10)"
    echo "  --max-frames N         Maximum number of frames to compare (default: all)"
    echo "  --checksum-only        Only compare checksums, not full frames"
    echo "  --skip-run             Skip running simulations (use existing output)"
    exit 1
}

# Parse command line arguments
SKIP_RUN=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            usage
            ;;
        --width)
            GRID_WIDTH="$2"
            shift 2
            ;;
        --height)
            GRID_HEIGHT="$2"
            shift 2
            ;;
        --rate)
            DIFFUSION_RATE="$2"
            shift 2
            ;;
        --frames)
            TOTAL_FRAMES="$2"
            shift 2
            ;;
        --baseline-dir)
            BASELINE_DIR="$2"
            shift 2
            ;;
        --baseline-output)
            BASELINE_OUTPUT="$2"
            shift 2
            ;;
        --optimized-dir)
            OPTIMIZED_DIR="$2"
            shift 2
            ;;
        --optimized-output)
            OPTIMIZED_OUTPUT="$2"
            shift 2
            ;;
        --tolerance)
            TOLERANCE="$2"
            shift 2
            ;;
        --max-frames)
            MAX_FRAMES="$2"
            shift 2
            ;;
        --checksum-only)
            CHECKSUM_ONLY=1
            shift
            ;;
        --skip-run)
            SKIP_RUN=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "=== Heat Diffusion Simulation Validation ==="
echo "Grid size: ${GRID_WIDTH}x${GRID_HEIGHT}"
echo "Diffusion rate: ${DIFFUSION_RATE}"
echo "Total frames: ${TOTAL_FRAMES}"
echo "Tolerance: ${TOLERANCE}"
echo

if [[ $SKIP_RUN -eq 0 ]]; then
    # Run baseline simulation
    echo "=== Running baseline simulation ==="
    mkdir -p "$BASELINE_OUTPUT"
    "${BASELINE_DIR}/heat_diffusion" --width "$GRID_WIDTH" --height "$GRID_HEIGHT" \
        --rate "$DIFFUSION_RATE" --frames "$TOTAL_FRAMES" \
        --output-dir "$BASELINE_OUTPUT"

    # Run optimized simulation
    echo "=== Running optimized simulation ==="
    mkdir -p "$OPTIMIZED_OUTPUT"
    "${OPTIMIZED_DIR}/heat_diffusion" --width "$GRID_WIDTH" --height "$GRID_HEIGHT" \
        --rate "$DIFFUSION_RATE" --frames "$TOTAL_FRAMES" \
        --output-dir "$OPTIMIZED_OUTPUT"
else
    echo "=== Skipping simulation runs, using existing output ==="
fi

# Run validation
echo "=== Validating results ==="

VALIDATE_ARGS="--baseline $BASELINE_OUTPUT --optimized $OPTIMIZED_OUTPUT --tolerance $TOLERANCE"

if [[ $MAX_FRAMES -gt 0 ]]; then
    VALIDATE_ARGS="$VALIDATE_ARGS --max-frames $MAX_FRAMES"
fi

if [[ $CHECKSUM_ONLY -eq 1 ]]; then
    VALIDATE_ARGS="$VALIDATE_ARGS --checksum-only"
fi

"${BASELINE_DIR}/validate" $VALIDATE_ARGS

# Check validation result
if [[ $? -eq 0 ]]; then
    echo "=== Validation successful! ==="
    echo "The optimized implementation produces the same results as the baseline."
else
    echo "=== Validation failed! ==="
    echo "The optimized implementation produces different results than the baseline."
    exit 1
fi