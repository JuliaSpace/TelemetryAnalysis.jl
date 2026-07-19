## Description #############################################################################
#
# Defines telemetry processing, dependency, formatting, and output-view benchmarks.
#
############################################################################################

using BenchmarkTools

pushfirst!(LOAD_PATH, dirname(@__DIR__))
using TelemetryAnalysis
using Dates

"""
    BenchmarkSource

Telemetry source marker used by benchmark packets.

# Fields

This marker has no fields.
"""
struct BenchmarkSource <: TelemetrySource end

const BYTES = collect(reinterpret(UInt8, UInt64.(1:128)))

"""Create `count` representative packets for processing benchmarks."""
# Build deterministic timestamps and byte payloads for repeatable benchmark inputs.
function benchmark_packets(count)
    return [
        TelemetryPacket{BenchmarkSource}(;
            timestamp = DateTime(2024) + Millisecond(index),
            data = UInt8[mod1(byte, 251) for byte in 1:64],
        )
        for index in 1:count
    ]
end

"""Create the database used by the view and dependency-chain benchmarks."""
# Build isolated and chained variables to measure dependency-planning workloads.
function benchmark_database()
    # Expose packet bytes directly as the deterministic unpacked frame.
    database = create_telemetry_database(
        "benchmark"; unpack_telemetry = packet -> packet.data)
    add_variable!(database, :single, 1, 1, identity)
    for index in 1:6
        label = Symbol(:chain, index)
        dependencies = index == 1 ? nothing : [Symbol(:chain, index - 1)]
        # Accumulate prior processed values to force execution of each chain dependency.
        transfer = (raw, context) -> isnothing(dependencies) ? first(raw) :
            first(raw) + context[first(dependencies)].processed
        add_variable!(database, label, index, 1, transfer; dependencies)
    end
    return database
end

"""Create a database with `count` independent variables."""
# Build isolated variables to measure scaling without dependency edges.
function variable_database(count)
    # Expose packet bytes directly so variable count is the changing workload.
    database = create_telemetry_database(
        "variables-$count"; unpack_telemetry = packet -> packet.data)
    for index in 1:count
        add_variable!(database, Symbol(:variable, index), index, 1, first)
    end
    return database
end

"""Create a diamond graph with one shared base and two intermediate variables."""
# Build a shared-dependency diamond to benchmark non-chain execution planning.
function diamond_database()
    # Expose packet bytes directly as the common frame for every diamond node.
    database = create_telemetry_database(
        "diamond"; unpack_telemetry = packet -> packet.data)
    add_variable!(database, :diamond_base, 1, 1, first)
    # Consume the shared base from each independent diamond branch.
    add_variable!(database, :diamond_left, 2, 1,
        (raw, context) -> first(raw) + context[:diamond_base].processed;
        dependencies = [:diamond_base])
    add_variable!(database, :diamond_right, 3, 1,
        (raw, context) -> first(raw) + context[:diamond_base].processed;
        dependencies = [:diamond_base])
    # Join both branch results at the diamond top.
    add_variable!(database, :diamond_top, 4, 1,
        (raw, context) -> context[:diamond_left].processed +
            context[:diamond_right].processed;
        dependencies = [:diamond_left, :diamond_right])
    return database
end

const PACKETS = benchmark_packets(1)
const PACKETS_16 = benchmark_packets(16)
const PACKETS_64 = benchmark_packets(64)
const PACKETS_128 = benchmark_packets(128)
const DATABASE = benchmark_database()
const DATABASE_1 = variable_database(1)
const DATABASE_8 = variable_database(8)
const DATABASE_32 = variable_database(32)
const DIAMOND_DATABASE = diamond_database()
const REVERSE_CHAIN = reverse([Symbol(:chain, index) for index in 1:6])
const DIAMOND_REQUEST = [:diamond_top, :diamond_right, :diamond_left, :diamond_base]
const OUTPUT_VIEWS = [
    :single => :byte_array,
    :chain1 => :byte_array_bin,
    :chain2 => :byte_array_hex,
    :chain3 => :raw,
    :chain4 => :processed,
]

"""
    run_benchmarks(; smoke = false)

Run warmed formatting, processing, dependency, and output-view benchmarks. Smoke mode uses a
small bounded sample count and is enabled with `TELEMETRY_BENCHMARK_SMOKE=true`.
"""
# Run each scenario with interpolated inputs and a bounded smoke-mode budget.
function run_benchmarks(; smoke = false)
    # Keep smoke execution short while retaining samples for parsing and setup checks.
    samples = smoke ? 5 : 100
    seconds = smoke ? 0.2 : 5.0
    # Interpolate global inputs so benchmark timing excludes global lookup overhead.
    scenarios = [
        "binary-1024" => (@benchmarkable byte_array_to_binary($BYTES)),
        "hex-1024" => (@benchmarkable byte_array_to_hex($BYTES)),
        "one-variable" => (@benchmarkable process_telemetry_packets(
            $PACKETS, [:single]; database = $DATABASE, show_progress = false)),
        "packets-16" => (@benchmarkable process_telemetry_packets(
            $PACKETS_16, [:single]; database = $DATABASE, show_progress = false)),
        "packets-128" => (@benchmarkable process_telemetry_packets(
            $PACKETS_128, [:single]; database = $DATABASE, show_progress = false)),
        "variables-1" => (@benchmarkable process_telemetry_packets(
            $PACKETS, collect(keys($DATABASE_1.variables)); database = $DATABASE_1,
            show_progress = false)),
        "variables-8" => (@benchmarkable process_telemetry_packets(
            $PACKETS, collect(keys($DATABASE_8.variables)); database = $DATABASE_8,
            show_progress = false)),
        "variables-32" => (@benchmarkable process_telemetry_packets(
            $PACKETS, collect(keys($DATABASE_32.variables)); database = $DATABASE_32,
            show_progress = false)),
        "reverse-chain" => (@benchmarkable process_telemetry_packets(
            $PACKETS, $REVERSE_CHAIN; database = $DATABASE, show_progress = false)),
        "diamond-reverse" => (@benchmarkable process_telemetry_packets(
            $PACKETS, $DIAMOND_REQUEST; database = $DIAMOND_DATABASE,
            show_progress = false)),
        "output-views" => (@benchmarkable process_telemetry_packets(
            $PACKETS, $OUTPUT_VIEWS; database = $DATABASE, show_progress = false)),
        "packets-64-threads-$(Threads.nthreads())" =>
            (@benchmarkable process_telemetry_packets(
                $PACKETS_64, $REVERSE_CHAIN; database = $DATABASE,
                show_progress = false)),
    ]

    for (name, scenario) in scenarios
        trial = run(scenario; samples, seconds)
        estimate = median(trial)
        println(name, ": time_ns=", estimate.time, ", memory=", estimate.memory,
            ", allocs=", estimate.allocs)
    end
    return nothing
end

run_benchmarks(; smoke = get(ENV, "TELEMETRY_BENCHMARK_SMOKE", "false") == "true")
