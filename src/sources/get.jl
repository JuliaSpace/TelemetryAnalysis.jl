# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions to fetch the telemetry from the sources.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export get_telemetry, init_telemetry_source

"""
    get_telemetry(source::T, start_time::DateTime, end_time::DateTime)

Get the telemetry data using the `source` between `start_time` and `end_time`.

    get_telemetry(::Type{T}, start_time::DateTime, interval)

Get the telemetry data using the `source` from `start_time` up to `start_time +
interval`. `interval` must be a number with a time unit. The following units are
exported:

- `s` for seconds;
- `m` for minutes;
- `h` for hours; and
- `d` for day.

If `source` is omitted, the default telemetry source is used. For more
information, see [`set_default_telemetry_source`](@ref).

!!! note
    The telemetry obtained from this function is selected as the default
    telemetry packet.

# Returns

This function returns a `Vector{TelemetryPacket{T}}` with the telemetry packets.
"""
function get_telemetry(
    source::T,
    start_time::DateTime,
    end_time::DateTime
) where T <: TelemetrySource
    @info "Fetching the telemetry between $start_time and $end_time [Source type: $T]"

    t_0 = now()
    packets = _api_get_telemetry(source, start_time, end_time)::Vector{TelemetryPacket{T}}
    t_f = now()

    num_packets = length(packets)

    if num_packets > 0
        @info "$num_packets packets fetched in $(canonicalize(t_f - t_0))."
    else
        @warn "No packets were found."
    end

    set_default_telemetry_packet(packets)

    return packets
end

function get_telemetry(
    source::TelemetrySource,
    start_time::DateTime,
    interval::Unitful.Quantity
)
    Δt = Second(uconvert(s, interval))
    end_time = start_time + Δt
    return get_telemetry(source, start_time, end_time)
end

function get_telemetry(start_time::DateTime, end_time::DateTime)
    !isassigned(_DEFAULT_TELEMETRY_SOURCE) &&
        error("The default telemetry source has not been assigned.")

    return get_telemetry(_DEFAULT_TELEMETRY_SOURCE[], start_time, end_time)
end

function get_telemetry(start_time::DateTime, interval::Unitful.Quantity)
    !isassigned(_DEFAULT_TELEMETRY_SOURCE) &&
        error("The default telemetry source has not been assigned.")

    return get_telemetry(_DEFAULT_TELEMETRY_SOURCE[], start_time, interval)
end

"""
    set_default_telemetry_packet(tmpacket::Vector{TelemetryPacket})

Set the default telemetry packet to `tmpacket`.
"""
function set_default_telemetry_packet(tmpacket::Vector{TelemetryPacket{T}}) where T
    _DEFAULT_TELEMETRY_PACKETS[] = tmpacket
    return nothing
end
