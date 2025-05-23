using Plots
using FilePathsBase

const STOCK_GC_FRAGMENTATION_PATHS = [
    "logs/fragmentation_benchmark_julia-stock.log",
    "logs/inference_benchmark_julia-stock.log"
]

const MMTK_JULIA_VERSIONS = [
    "julia-immix",
    "julia-immix-non-moving",
    "julia-immix-always-moving",
    "julia-immix-max-moving"
]

const MMTK_GC_FRAGMENTATION_PATHS = vcat([
    "logs/fragmentation_benchmark_$(ver).log"
    for ver in MMTK_JULIA_VERSIONS
], [
    "logs/inference_benchmark_$(ver).log"
    for ver in MMTK_JULIA_VERSIONS
])

function ensure_output_dir(path)
    mkpath(dirname(path))
end

function parse_stock_gc_fragmentation_logs()
    for path in STOCK_GC_FRAGMENTATION_PATHS
        fragmentation_benchmark = occursin("fragmentation_benchmark", path)

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

        benchmark_type = fragmentation_benchmark ? "fragmentation_benchmark" : "inference_benchmark"
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

        fragmentation_benchmark = occursin("fragmentation_benchmark", path)
        sticky = occursin("sticky", path)

        if fragmentation_benchmark
            julia_version = match(r"logs/fragmentation_benchmark_julia-([^\.]+)", path)[1]
        else
            julia_version =   match(r"logs/inference_benchmark_julia-([^\.]+)", path)[1]
        end

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

        gc_name = sticky ? "MMTk Sticky Immix" : "MMTk Immix"
        benchmark_type = fragmentation_benchmark ? "fragmentation_benchmark" : "inference_benchmark"
        base_path = "plots/$julia_version"
        ensure_output_dir("$base_path/")

        plot(utilization,
            title="$gc_name Utilization (IMMIX space)",
            xlabel="GC Iteration", ylabel="Utilization (%)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_utilization_immix.png")

        plot(fragmentation,
            title="$gc_name Fragmentation (IMMIX space)",
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

        fragmentation_benchmark = occursin("fragmentation_benchmark", path)
        sticky = occursin("sticky", path)

        if fragmentation_benchmark
            julia_version = match(r"logs/fragmentation_benchmark_julia-([^\.]+)", path)[1]
        else
            julia_version =   match(r"logs/inference_benchmark_julia-([^\.]+)", path)[1]
        end

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

        gc_name = sticky ? "MMTk Sticky Immix" : "MMTk Immix"
        benchmark_type = fragmentation_benchmark ? "fragmentation_benchmark" : "inference_benchmark"
        base_path = "plots/$julia_version"
        ensure_output_dir("$base_path/")

        plot(utilization,
            title="$gc_name Utilization (NonMoving space)",
            xlabel="GC Iteration", ylabel="Utilization (%)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_utilization_nonmoving.png")

        plot(fragmentation,
            title="$gc_name Fragmentation (NonMoving space)",
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

        fragmentation_benchmark = occursin("fragmentation_benchmark", path)
        sticky = occursin("sticky", path)
        if fragmentation_benchmark
            julia_version = match(r"logs/fragmentation_benchmark_julia-([^\.]+)", path)[1]
        else
            julia_version = match(r"logs/inference_benchmark_julia-([^\.]+)", path)[1]
        end

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

        gc_name = sticky ? "MMTk Sticky Immix" : "MMTk Immix"
        benchmark_type = fragmentation_benchmark ? "fragmentation_benchmark" : "inference_benchmark"
        base_path = "plots/$julia_version"
        ensure_output_dir("$base_path/")

        plot(utilization,
            title="$gc_name Utilization (IMMIX + NonMoving)",
            xlabel="GC Iteration", ylabel="Utilization (%)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_utilization_combined.png")

        plot(fragmentation,
            title="$gc_name Fragmentation (IMMIX + NonMoving)",
            xlabel="GC Iteration", ylabel="Fragmentation (MB)", legend=false, grid=true)
        savefig("$base_path/$(benchmark_type)_fragmentation_combined.png")
    end
end

# Run all parsing functions
parse_stock_gc_fragmentation_logs()
parse_mmtk_immixspace_gc_fragmentation_logs()
parse_mmtk_nonmoving_gc_fragmentation_logs()
parse_mmtk_gc_fragmentation_logs()
