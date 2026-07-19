## Description #############################################################################
#
# Functions to fetch the telemetry from the sources.
#
############################################################################################

export get_default_telemetry_packets, get_default_telemetry_source
export get_telemetry, init_telemetry_source, set_default_telemetry_packets!

"""
    get_default_telemetry_packets() -> Any

Get the default telemetry packets. This function throws an error if they are not defined
yet.
"""
function get_default_telemetry_packets()
    !isassigned(_DEFAULT_TELEMETRY_PACKETS) &&
        error("The default telemetry packets have not been assigned.")

    return _DEFAULT_TELEMETRY_PACKETS[]
end

"""
    get_default_telemetry_source() -> Any

Get the default telemetry source. This function throws an error if it is not defined yet.
"""
function get_default_telemetry_source()
    !isassigned(_DEFAULT_TELEMETRY_SOURCE) &&
        error("The default telemetry source has not been assigned.")

    return _DEFAULT_TELEMETRY_SOURCE[]
end

"""
    get_telemetry(source::T, start_time::DateTime, end_time::DateTime) ->
        Vector{TelemetryPacket{T}} where T <: TelemetrySource

Get the telemetry data using the `source` between `start_time` and `end_time`.

    get_telemetry(source::T, start_time::DateTime, interval::Unitful.Quantity) ->
        Vector{TelemetryPacket{T}} where T <: TelemetrySource

Get the telemetry data using the `source` from `start_time` up to `start_time + interval`.
`interval` must have time units. It is converted with `uconvert(Unitful.ms, interval)` and
must be finite, nonnegative, within `Int64`, and exactly representable as a whole number of
milliseconds. Fractional milliseconds are rejected without rounding or tolerance. The
following units are exported:

- `s` for seconds;
- `m` for minutes;
- `h` for hours; and
- `d` for days.

If `source` is omitted, the default telemetry source is used. For more information, see
[`set_default_telemetry_source!`](@ref).

Some sources may also implement the simplified version of this function:

    get_telemetry(source::T) -> Vector{TelemetryPacket{T}} where T <: TelemetrySource

where all the available telemetry will be fetched.

!!! note
    The telemetry obtained from this function is selected as the default telemetry packet
    collection.

# Returns

- `Vector{TelemetryPacket{T}}`: The fetched telemetry packets.
"""
function get_telemetry(
    source::T,
    start_time::DateTime,
    end_time::DateTime
) where T<:TelemetrySource
    @info "Fetching the telemetry between $start_time and $end_time [Source type: $T]"

    start_timestamp = now()
    result = _api_get_telemetry(source, start_time, end_time)
    return _finalize_telemetry_fetch(result, T, start_timestamp)
end

"""
    _finalize_telemetry_fetch(result, ::Type{T}, start_timestamp) ->
        Vector{TelemetryPacket{T}}

Validate a source result, report its packet count, and publish it as the default collection.
"""
function _finalize_telemetry_fetch(result, ::Type{T}, start_timestamp::DateTime) where T
    # Centralize source result validation before logging or mutating default packet state.
    packets = result::Vector{TelemetryPacket{T}}
    num_packets = length(packets)

    if num_packets > 0
        @info "$num_packets packets fetched in $(canonicalize(now() - start_timestamp))."
    else
        @warn "No packets were found."
    end

    # Publish defaults only after the complete source result satisfies the packet contract.
    set_default_telemetry_packets!(packets)

    return packets
end

function get_telemetry(
    source::TelemetrySource,
    start_time::DateTime,
    interval::Unitful.Quantity
)
    milliseconds = ustrip(uconvert(Unitful.ms, interval))
    isfinite(milliseconds) || throw(ArgumentError("The interval must be finite."))
    milliseconds >= 0 || throw(ArgumentError("The interval must not be negative."))
    Δt = Millisecond(Int64(milliseconds))
    end_time = start_time + Δt
    return get_telemetry(source, start_time, end_time)
end

function get_telemetry(source::T) where T<:TelemetrySource
    @info "Fetching all available telemetry [Source type: $T]"

    start_timestamp = now()
    result = _api_get_telemetry(source)
    return _finalize_telemetry_fetch(result, T, start_timestamp)
end

function get_telemetry(start_time::DateTime, end_time::DateTime)
    return get_telemetry(get_default_telemetry_source(), start_time, end_time)
end

function get_telemetry(start_time::DateTime, interval::Unitful.Quantity)
    return get_telemetry(get_default_telemetry_source(), start_time, interval)
end

get_telemetry() = get_telemetry(get_default_telemetry_source())

"""
    set_default_telemetry_packets!(tmpackets::Vector{TelemetryPacket}) -> Nothing

Set the default telemetry packets to `tmpackets`.
"""
function set_default_telemetry_packets!(tmpackets::Vector{TelemetryPacket{T}}) where T
    _DEFAULT_TELEMETRY_PACKETS[] = tmpackets
    return nothing
end
