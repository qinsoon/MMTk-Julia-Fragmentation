#!/bin/bash

set -xe

CLEAN_BUILD=1

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

MMTK_JULIA_FRAGMENTATION_ROOT=$(realpath "../..")

FRAGMENTATION_BENCHMARKS_DIR=$MMTK_JULIA_FRAGMENTATION_ROOT/GCBenchmarks/benches/fragmentation/synthetic
INFERENCE_BENCHMARKS_DIR=$MMTK_JULIA_FRAGMENTATION_ROOT/GCBenchmarks/benches/compiler/inference

MMTK_JULIA_DIR=$MMTK_JULIA_FRAGMENTATION_ROOT/mmtk-julia

timestamp=$(date +"%Y-%m-%d_%H-%M-%S")

print_green "Creating logs directory"
LOGS_DIR=$(pwd)/logs-$timestamp
mkdir -p $LOGS_DIR

print_green "Creating plots directory"
rm -fr plots
mkdir -p plots

# Small function to encapsulate the commands to build Julia (i.e. make -C ../mmtk-julia clean && make cleanall && make -j
function build_julia {
    print_green "Building $1"
    cd $MMTK_JULIA_FRAGMENTATION_ROOT/$1
    if [ "$CLEAN_BUILD" = "1" ]; then
        make -C $MMTK_JULIA_DIR clean
        make cleanall
    fi
    MMTK_JULIA_DIR=$MMTK_JULIA_DIR make
    cd - > /dev/null
    print_green "Successfully built $1"
}

function run_benchmarks {
    # Get the path to the Julia binary
    cd $MMTK_JULIA_FRAGMENTATION_ROOT/$1
    JULIA_BIN_PATH=$(pwd)/julia
    cd - > /dev/null

    # Run the fragmentation benchmark
    print_green "Running fragmentation benchmark with $1 (PATTERN 1)"
    cd $FRAGMENTATION_BENCHMARKS_DIR
    rm -f Manifest.toml
    $JULIA_BIN_PATH --project=. -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()'
    MMTK_COUNT_LIVE_BYTES_IN_GC=true JL_GCBENCH_KEEP_ALIVE_PATTERN=1 $JULIA_BIN_PATH --project=. exploit_free_list.jl 2>&1 | tee $LOGS_DIR/fragmentation_benchmark_pattern_1_$1.log
    cd - > /dev/null

    print_green "Running fragmentation benchmark with $1 (PATTERN 2)"
    cd $FRAGMENTATION_BENCHMARKS_DIR
    rm -f Manifest.toml
    $JULIA_BIN_PATH --project=. -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()'
    MMTK_COUNT_LIVE_BYTES_IN_GC=true JL_GCBENCH_KEEP_ALIVE_PATTERN=2 $JULIA_BIN_PATH --project=. exploit_free_list.jl 2>&1 | tee $LOGS_DIR/fragmentation_benchmark_pattern_2_$1.log
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
    # MMTK_STRESS_FACTOR=209715200
    # MMTK_COUNT_LIVE_BYTES_IN_GC=true $JULIA_BIN_PATH --project=. --hard-heap-limit=1200MB inference_benchmarks.jl 2>&1 | tee $LOGS_DIR/inference_benchmark_$1.log
    MMTK_COUNT_LIVE_BYTES_IN_GC=true $JULIA_BIN_PATH --project=. inference_benchmarks.jl 2>&1 | tee $LOGS_DIR/inference_benchmark_$1.log
    # MMTK_MIN_HSIZE=1200 MMTK_MAX_HSIZE=1200 MMTK_COUNT_LIVE_BYTES_IN_GC=true $JULIA_BIN_PATH --project=. inference_benchmarks.jl 2>&1 | tee $LOGS_DIR/inference_benchmark_$1.log
    cd - > /dev/null
}

function parse_fragmentation_logs {
    print_green "Parsing fragmentation logs"
    STOCK_JULIA_BIN_PATH=$MMTK_JULIA_FRAGMENTATION_ROOT/julia-stock/julia
    $STOCK_JULIA_BIN_PATH --project=. -e 'using Pkg; Pkg.instantiate()'
    $STOCK_JULIA_BIN_PATH --project=. parse_fragmentation_logs.jl $LOGS_DIR

    cp -r plots $LOGS_DIR
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
MAKE_USER_CONTENTS["julia-immix-non-moving"]="WITH_THIRD_PARTY_GC=MMTK
MMTK_PLAN=Immix
MMTK_MOVING=0
MMTK_ALWAYS_MOVING=0
MMTK_MAX_MOVING=0
MMTK_DUMP_FRAGMENTATION=1
USE_BINARYBUILDER_MMTK_JULIA=0"
MAKE_USER_CONTENTS["julia-immix-max-moving"]="WITH_THIRD_PARTY_GC=MMTK
MMTK_PLAN=Immix
MMTK_MOVING=1
MMTK_ALWAYS_MOVING=1
MMTK_MAX_MOVING=1
MMTK_DUMP_FRAGMENTATION=1
USE_BINARYBUILDER_MMTK_JULIA=0"

function ensure_repo_exists_and_configured {
    VARIANT=$1
    VARIANT_DIR=$MMTK_JULIA_FRAGMENTATION_ROOT/$VARIANT
    JULIA_REPO_URL="https://github.com/mmtk/julia.git"
    JULIA_REF="mmtk-support-moving-upstream"

    if [ "$CLEAN_BUILD" = "1" ]; then
        rm -rf $VARIANT_DIR
    fi

    if [ ! -d "$VARIANT_DIR" ]; then
        print_green "Cloning $VARIANT from $JULIA_REPO_URL (branch: $JULIA_BRANCH)"
        git clone $JULIA_REPO_URL $VARIANT_DIR
        git -C $VARIANT_DIR checkout $JULIA_REF
    else
        print_green "$VARIANT already exists, skipping clone"
    fi

    MAKE_USER_PATH="$VARIANT_DIR/Make.user"
    print_green "Setting up Make.user for $VARIANT"
    echo "${MAKE_USER_CONTENTS[$VARIANT]}" > "$MAKE_USER_PATH"
}

function ensure_binding_exists {
    BINDING_REPO_URL="https://github.com/mmtk/mmtk-julia.git"
    BINDING_REF="mmtk-support-moving-upstream"

    if [ "$CLEAN_BUILD" = "1" ]; then
        rm -rf $MMTK_JULIA_DIR
    fi

    if [ ! -d "$MMTK_JULIA_DIR" ]; then
        print_green "Cloning binding from $BINDING_REPO_URL (branch: $BINDING_REF)"
        git clone $BINDING_REPO_URL $MMTK_JULIA_DIR
        git -C $MMTK_JULIA_DIR checkout $BINDING_REF
    else
        print_green "Binding already exists, skipping clone"
    fi
}

# Ensure all required Julia variants are checked out and configured
ensure_binding_exists

ensure_repo_exists_and_configured julia-stock
ensure_repo_exists_and_configured julia-immix-non-moving
ensure_repo_exists_and_configured julia-immix-max-moving

# Build Julia
build_julia julia-stock
build_julia julia-immix-non-moving
build_julia julia-immix-max-moving

# Run the benchmarks for all GC implementations
export RUST_BACKTRACE=1
run_with_retries julia-stock
run_with_retries julia-immix-non-moving
run_with_retries julia-immix-max-moving

# Parse the logs
parse_fragmentation_logs

print_green "All benchmarks completed successfully"
