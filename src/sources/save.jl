# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==========================================================================================
#
#   Functions to save the telemetry obtained from the sources.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export load_telemetry, save_telemetry

"""
    load_telemetry(filename::String) -> Vector{TelemetryPacket}

Load the telemetries in the file `filename`.
"""
function load_telemetry(filename::String)
    stream = GzipDecompressorStream(open(filename))
    tms = nothing

    try
        tms = deserialize(stream)
        set_default_telemetry_packet(tms)
    catch e
        if e isa KeyError
            @error(
                """
                Key $(e.key) was not found.
                The package that implements the source must be loaded before reading the file.
                Try executing `using $(e.key.name)` first.
                """,
                exception = (e, catch_backtrace())
            )
        else
            rethrow(e)
        end

    finally
        close(stream)
    end

    return tms
end

"""
    save_telemetry(tms::Vector{TelemetryPacket{T}}, prefix::String = string(T)) where T<:TelemetrySource -> Nothing

Save the telemetries in the vector `tms` to a file. The filename is built using `prefix`
together with the timestamp of the telemetries:

    <prefix>_<timestamp of the first telemetry>_<timestamp of the last telemetry>

The format of timestamp if `yyyy-mm-ddTHH-MM-SS`. If `prefix` is omitted, "T" is used.
"""
function save_telemetry(
    tms::Vector{TelemetryPacket{T}},
    prefix::String = string(T)
) where T <: TelemetrySource
    # TODO: Should we use JLD instead?

    if isempty(tms)
        @warn "The vector with telemetries is empty!"
    else
        t₀ = Dates.format(first(tms).timestamp, "yyyy-mm-ddTHH-MM-SS")
        t₁ = Dates.format(last(tms).timestamp,  "yyyy-mm-ddTHH-MM-SS")

        filename = prefix * "_" * t₀ * "_" * t₁ * ".ser.gz"

        @info "Saving the telemetries to the file $filename..."

        stream = GzipCompressorStream(open(filename, "w"))
        serialize(stream, tms)
        close(stream)
    end

    return nothing
end
