#!/bin/bash

# Print line in green
function print_green {
    echo -e "\033[0;32m$1\033[0m"
}
# Print line in red
function print_red {
    echo -e "\033[0;31m$1\033[0m"
}

# Abort if we're not running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    print_red "This script is only supported on Linux."
    exit 1
fi
# Abort if we're not running on x86_64
if [[ "$(uname -m)" != "x86_64" ]]; then
    print_red "This script is only supported on x86_64."
    exit 1
fi

MMTK_JULIA_FRAGMENTATION_ROOT=../..

FRAGMENTATION_BENCHMARKS_DIR=$MMTK_JULIA_FRAGMENTATION_ROOT/GCBenchmarks/benches/fragmentation/synthetic
INFERENCE_BENCHMARKS_DIR=$MMTK_JULIA_FRAGMENTATION_ROOT/GCBenchmarks/benches/compiler/inference

print_green "Creating logs directory"
rm -fr logs
mkdir -p logs
LOGS_DIR=$(pwd)/logs

print_green "Creating plots directory"
rm -fr plots
mkdir -p plots

# Small function to encapsulate the commands to build Julia (i.e. make -C ../mmtk-julia clean && make cleanall && make -j
function build_julia {
    print_green "Building $1"
    cd $MMTK_JULIA_FRAGMENTATION_ROOT/$1
    make -C ../mmtk-julia clean
    make cleanall
    MMTK_JULIA_DIR=$(pwd)/../mmtk-julia make
    cd - > /dev/null
    print_green "Successfully built $1"
}

function run_benchmarks {
    # Build Julia
    build_julia $1

    # Get the path to the Julia binary
    cd $MMTK_JULIA_FRAGMENTATION_ROOT/$1
    JULIA_BIN_PATH=$(pwd)/julia
    cd - > /dev/null

    # Run the fragmentation benchmark
    print_green "Running fragmentation benchmark with $1"
    cd $FRAGMENTATION_BENCHMARKS_DIR
    rm -f Manifest.toml
    $JULIA_BIN_PATH --project=. -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()'
    MMTK_COUNT_LIVE_BYTES_IN_GC=true $JULIA_BIN_PATH --project=. exploit_free_list.jl 2>&1 | tee $LOGS_DIR/fragmentation_benchmark_$1.log
    cd - > /dev/null

    # Run the inference benchmark
    print_green "Running inference benchmark with $1"
    rm -f Manifest.toml
    cd $INFERENCE_BENCHMARKS_DIR
    $JULIA_BIN_PATH --project=. -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()'
    # When setting a fixed heap size add those variables below:
    # Use 1.10 * minheap for stress copying version (1090)
    # MMTK_MIN_HSIZE=1200 MMTK_MAX_HSIZE=1200 
    # If using stress, then set the heap size to 3072 (stress will force a GC every 50MB allocated)
    # MMTK_MIN_HSIZE=3072 MMTK_MAX_HSIZE=3072 MMTK_STRESS_FACTOR=52428800 
    MMTK_COUNT_LIVE_BYTES_IN_GC=true $JULIA_BIN_PATH --project=. inference_benchmarks.jl 2>&1 | tee $LOGS_DIR/inference_benchmark_$1.log
    cd - > /dev/null
}

function parse_fragmentation_logs {
    print_green "Parsing fragmentation logs"
    STOCK_JULIA_BIN_PATH=$MMTK_JULIA_FRAGMENTATION_ROOT/julia-stock/julia
    $STOCK_JULIA_BIN_PATH --project=. -e 'using Pkg; Pkg.instantiate()'
    $STOCK_JULIA_BIN_PATH --project=. parse_fragmentation_logs.jl
}

function run_with_retries {
    retries=0
    max_retries=10
    while true; do
        print_green "Running benchmarks with $1 (attempt $((retries + 1)))"
        run_benchmarks $1
        if [ $? -eq 0 ]; then
            break
        else
            ((retries++))
            if [ $retries -ge $max_retries ]; then
                print_red "Failed to run benchmarks with $1 after $max_retries retries"
                exit 1
            fi
            print_red "Failed to run benchmarks with $1, retrying..."
        fi
    done
}

# Define the Julia variants and their Make.user contents
declare -A MAKE_USER_CONTENTS
MAKE_USER_CONTENTS["julia-stock"]=""
MAKE_USER_CONTENTS["julia-immix"]="WITH_THIRD_PARTY_GC=MMTK
MMTK_PLAN=Immix
MMTK_MOVING=1
MMTK_ALWAYS_MOVING=0
MMTK_MAX_MOVING=0
USE_BINARYBUILDER_MMTK_JULIA=0"
MAKE_USER_CONTENTS["julia-immix-non-moving"]="WITH_THIRD_PARTY_GC=MMTK
MMTK_PLAN=Immix
MMTK_MOVING=0
MMTK_ALWAYS_MOVING=0
MMTK_MAX_MOVING=0
USE_BINARYBUILDER_MMTK_JULIA=0"
MAKE_USER_CONTENTS["julia-immix-always-moving"]="WITH_THIRD_PARTY_GC=MMTK
MMTK_PLAN=Immix
MMTK_MOVING=1
MMTK_ALWAYS_MOVING=1
MMTK_MAX_MOVING=0
USE_BINARYBUILDER_MMTK_JULIA=0"
MAKE_USER_CONTENTS["julia-immix-max-moving"]="WITH_THIRD_PARTY_GC=MMTK
MMTK_PLAN=Immix
MMTK_MOVING=1
MMTK_ALWAYS_MOVING=1
MMTK_MAX_MOVING=1
USE_BINARYBUILDER_MMTK_JULIA=0"

function ensure_repo_exists_and_configured {
    VARIANT=$1
    VARIANT_DIR=$MMTK_JULIA_FRAGMENTATION_ROOT/$VARIANT
    JULIA_REPO_URL="https://github.com/mmtk/julia.git"
    JULIA_BRANCH="mmtk-support-moving-upstream"

    if [ ! -d "$VARIANT_DIR" ]; then
        print_green "Cloning $VARIANT from $JULIA_REPO_URL (branch: $JULIA_BRANCH)"
        git clone --branch $JULIA_BRANCH --single-branch $JULIA_REPO_URL $VARIANT_DIR
    else
        print_green "$VARIANT already exists, skipping clone"
    fi

    MAKE_USER_PATH="$VARIANT_DIR/Make.user"
    print_green "Setting up Make.user for $VARIANT"
    echo "${MAKE_USER_CONTENTS[$VARIANT]}" > "$MAKE_USER_PATH"
}

# Ensure all required Julia variants are checked out and configured
ensure_repo_exists_and_configured julia-stock
ensure_repo_exists_and_configured julia-immix
ensure_repo_exists_and_configured julia-immix-non-moving
ensure_repo_exists_and_configured julia-immix-always-moving
ensure_repo_exists_and_configured julia-immix-max-moving

# Run the benchmarks for all GC implementations
# RUST_BACKTRACE=1 run_with_retries julia-immix
RUST_BACKTRACE=1 run_with_retries julia-immix-non-moving
# RUST_BACKTRACE=1 run_with_retries julia-immix-always-moving
RUST_BACKTRACE=1 run_with_retries julia-immix-max-moving
# run_with_retries julia-stock

# Parse the logs
parse_fragmentation_logs

print_green "All benchmarks completed successfully"
