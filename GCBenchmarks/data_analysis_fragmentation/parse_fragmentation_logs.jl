using Plots
using FilePathsBase

# === Accept folder path from ARGS ===
if length(ARGS) < 1
    error("Please provide a directory path as an argument.")
end

const LOG_DIR = ARGS[1]

# === Find all .log files under the directory ===
function find_log_files(dir::String)
    return [joinpath(root, file) for (root, _, files) in walkdir(dir) for file in files if endswith(file, ".log")]
end

const ALL_LOG_PATHS = find_log_files(LOG_DIR)

# === Partition into stock vs MMTk ===
const STOCK_GC_FRAGMENTATION_PATHS = filter(path -> occursin("julia-stock", path), ALL_LOG_PATHS)
const MMTK_GC_FRAGMENTATION_PATHS = filter(path -> !occursin("julia-stock", path), ALL_LOG_PATHS)

function ensure_output_dir(path)
    mkpath(dirname(path))
end

function parse_log_filename(filename::String)
    basename = split(Base.basename(filename), '.')[1]
    parts = split(basename, "_julia-")
    if length(parts) != 2
        error("Filename format is incorrect: $filename")
    end
    benchmark_name = parts[1]
    build_name = parts[2]
    return benchmark_name, build_name
end

function parse_stock_gc_fragmentation_logs()
    for path in STOCK_GC_FRAGMENTATION_PATHS
        lines = readlines(path)
        utilization = Float64[]
        fragmentation = Float64[]
        for line in lines
            if occursin("Utilization in pool allocator", line)
                push!(utilization, 100.0 * parse(Float64, match(r"([0-9]+.[0-9]+)", line)[1]))
                live_bytes = parse(Int, match(r"([0-9]+) live bytes", line)[1])
                pages_bytes = parse(Int, match(r"([0-9]+) bytes in pages", line)[1])
                fragmentation_in_mb = (pages_bytes - live_bytes) / 1024 / 1024
                push!(fragmentation, fragmentation_in_mb)
            end
        end

        benchmark_type, build_name = parse_log_filename(path)
        base_path = "plots/julia-stock"
        ensure_output_dir("$base_path/")

        plot(utilization,
            title="Stock GC Pool Allocator Utilization",
            xlabel="GC Iteration", ylabel="Utilization (%)", legend=false, grid=true)
        savefig("$base_path/stock_gc_$(benchmark_type)_utilization.png")

        plot(fragmentation,
            title="Stock GC Pool Allocator Fragmentation",
            xlabel="GC Iteration", ylabel="Fragmentation (MB)", legend=false, grid=true)
        savefig("$base_path/stock_gc_$(benchmark_type)_fragmentation.png")
    end
end

function parse_mmtk_immixspace_gc_fragmentation_logs()
    for path in MMTK_GC_FRAGMENTATION_PATHS
        if !isfile(path)
            @warn "Skipping missing file: $path"
            continue
        end

        benchmark_type, julia_version = parse_log_filename(path)
        lines = readlines(path)

        utilization = Float64[]
        fragmentation = Float64[]

        for line in lines
            if occursin("Utilization in space \"immix\"", line)
                push!(utilization, parse(Float64, match(r"([0-9]+.[0-9]+) %", line)[1]))
                live_bytes = parse(Int, match(r"([0-9]+) live bytes", line)[1])
                total_bytes = parse(Int, match(r"([0-9]+) total bytes", line)[1])
                fragmentation_in_mb = (total_bytes - live_bytes) / 1024 / 1024
                push!(fragmentation, fragmentation_in_mb)
            end
        end

        base_path = "plots/$julia_version"
        ensure_output_dir("$base_path/")

        plot(utilization,
            title="$julia_version Utilization (IMMIX space)",
            xlabel="GC Iteration", ylabel="Utilization (%)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_utilization_immix.png")

        plot(fragmentation,
            title="$julia_version Fragmentation (IMMIX space)",
            xlabel="GC Iteration", ylabel="Fragmentation (MB)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_fragmentation_immix.png")
    end
end

function parse_mmtk_nonmoving_gc_fragmentation_logs()
    for path in MMTK_GC_FRAGMENTATION_PATHS
        if !isfile(path)
            @warn "Skipping missing file: $path"
            continue
        end

        benchmark_type, julia_version = parse_log_filename(path)
        lines = readlines(path)

        utilization = Float64[]
        fragmentation = Float64[]

        for line in lines
            if occursin("Utilization in space \"nonmoving\"", line)
                push!(utilization, parse(Float64, match(r"([0-9]+.[0-9]+) %", line)[1]))
                live_bytes = parse(Int, match(r"([0-9]+) live bytes", line)[1])
                total_bytes = parse(Int, match(r"([0-9]+) total bytes", line)[1])
                fragmentation_in_mb = (total_bytes - live_bytes) / 1024 / 1024
                push!(fragmentation, fragmentation_in_mb)
            end
        end

        base_path = "plots/$julia_version"
        ensure_output_dir("$base_path/")

        plot(utilization,
            title="$julia_version Utilization (NonMoving space)",
            xlabel="GC Iteration", ylabel="Utilization (%)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_utilization_nonmoving.png")

        plot(fragmentation,
            title="$julia_version Fragmentation (NonMoving space)",
            xlabel="GC Iteration", ylabel="Fragmentation (MB)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_fragmentation_nonmoving.png")
    end
end

function parse_mmtk_gc_fragmentation_logs()
    for path in MMTK_GC_FRAGMENTATION_PATHS
        if !isfile(path)
            @warn "Skipping missing file: $path"
            continue
        end

        benchmark_type, julia_version = parse_log_filename(path)

        lines = readlines(path)
        utilization = Float64[]
        fragmentation = Float64[]

        did_immixspace = false
        did_nonmoving = false
        live_bytes_immixspace = 0
        live_bytes_nonmoving = 0
        total_bytes_immixspace = 0
        total_bytes_nonmoving = 0

        for line in lines
            if occursin("Utilization in space \"immix\"", line)
                live_bytes_immixspace = parse(Int, match(r"([0-9]+) live bytes", line)[1])
                total_bytes_immixspace = parse(Int, match(r"([0-9]+) total bytes", line)[1])
                did_immixspace = true
            end
            if occursin("Utilization in space \"nonmoving\"", line)
                live_bytes_nonmoving = parse(Int, match(r"([0-9]+) live bytes", line)[1])
                total_bytes_nonmoving = parse(Int, match(r"([0-9]+) total bytes", line)[1])
                did_nonmoving = true
            end

            if did_immixspace && did_nonmoving
                total_live = live_bytes_immixspace + live_bytes_nonmoving
                total_allocated = total_bytes_immixspace + total_bytes_nonmoving
                push!(utilization, 100.0 * total_live / total_allocated)
                push!(fragmentation, (total_allocated - total_live) / 1024 / 1024)

                did_immixspace = false
                did_nonmoving = false
            end
        end

        base_path = "plots/$julia_version"
        ensure_output_dir("$base_path/")

        plot(utilization,
            title="$julia_version Utilization (IMMIX + NonMoving)",
            xlabel="GC Iteration", ylabel="Utilization (%)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_utilization_combined.png")

        plot(fragmentation,
            title="$julia_version Fragmentation (IMMIX + NonMoving)",
            xlabel="GC Iteration", ylabel="Fragmentation (MB)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_fragmentation_combined.png")
    end
end

# Run all parsers
parse_stock_gc_fragmentation_logs()
parse_mmtk_immixspace_gc_fragmentation_logs()
parse_mmtk_nonmoving_gc_fragmentation_logs()
parse_mmtk_gc_fragmentation_logs()
