## Description #############################################################################
#
# Functions to save the telemetry obtained from the sources.
#
############################################################################################

export load_telemetry, save_telemetry

"""
    load_telemetry(filename::String) -> Vector{TelemetryPacket}

Load the telemetry packets in `filename`. Files use gzip-compressed Julia `Serialization`
and must be treated as trusted input. Serialization depends on the Julia minor and
serialized type layouts; cross-version compatibility is not guaranteed. Deserialization and
validation failures propagate, and default packets are updated only after successful
validation.
"""
function load_telemetry(filename::String)
    tms = open(filename) do file_stream
        stream = GzipDecompressorStream(file_stream)

        try
            try
                deserialize(stream)
            catch error
                if error isa KeyError
                    try
                        @error(
                            """
                            Key $(error.key) was not found.
                            Load the source package before reading the file.
                            """,
                            exception = (error, catch_backtrace())
                        )
                    catch
                    end
                end
                rethrow()
            end
        finally
            try
                close(stream)
            catch
            end
        end
    end

    tms isa Vector{<:TelemetryPacket} ||
        throw(ArgumentError("The file does not contain a vector of telemetry packets."))
    set_default_telemetry_packets!(tms)

    return tms
end

"""
    _atomic_replace_file(source::String, destination::String) -> Nothing

Atomically replace `destination` with a same-filesystem temporary file at `source`.
"""
function _atomic_replace_file(source::String, destination::String)
    # Rename directly within the destination filesystem for atomic replacement semantics.
    error_code = ccall(:jl_fs_rename, Int32, (Cstring, Cstring), source, destination)

    if error_code < 0
        # Preserve the operating system error code instead of replacing it with a fallback.
        message = "rename($(repr(source)), $(repr(destination)))"
        Base.uv_error(message, error_code)
    end

    return nothing
end

"""
    save_telemetry(
        tms::Vector{TelemetryPacket{T}},
        prefix::String = string(T)
    ) where T<:TelemetrySource -> Nothing

Save the telemetry packets in `tms` to a file. The filename is built using `prefix` together
with the first and last packet timestamps:

    <prefix>_<timestamp of the first packet>_<timestamp of the last packet>

The timestamp format is `yyyy-mm-ddTHH-MM-SS`. If `prefix` is omitted, the source type is
used. The gzip stream is finalized in a temporary file in the destination directory before
an atomic replacement. Failures remove the temporary file and preserve an existing
destination. The output remains Julia- and type-layout-dependent trusted data, not a stable
cross-version interchange format.
"""
function save_telemetry(
    tms::Vector{TelemetryPacket{T}},
    prefix::String = string(T)
) where T <: TelemetrySource
    # TODO: Should we use JLD instead?

    if isempty(tms)
        @warn "The telemetry vector is empty!"
    else
        t₀ = Dates.format(first(tms).timestamp, "yyyy-mm-ddTHH-MM-SS")
        t₁ = Dates.format(last(tms).timestamp,  "yyyy-mm-ddTHH-MM-SS")

        filename = prefix * "_" * t₀ * "_" * t₁ * ".ser.gz"

        @info "Saving the telemetry to the file $filename..."

        temporary_filename, file_stream = mktemp(
            dirname(abspath(filename));
            cleanup = false,
        )
        stream = nothing
        moved = false

        try
            stream = GzipCompressorStream(file_stream)

            try
                serialize(stream, tms)
            catch
                try
                    close(stream)
                catch
                end
                rethrow()
            end

            close(stream)
            stream = nothing
            _atomic_replace_file(temporary_filename, filename)
            moved = true
        finally
            if stream !== nothing && isopen(stream)
                try
                    close(stream)
                catch
                end
            end

            if isopen(file_stream)
                try
                    close(file_stream)
                catch
                end
            end

            if !moved && isfile(temporary_filename)
                rm(temporary_filename; force = true)
            end
        end
    end

    return nothing
end
