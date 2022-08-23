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

    get_telemetry(::Type{T}, start_time::DateTime, interval::Int; unit::Symbol = :s)

Get the telemetry data using the `source` from `start_time` up to `start_time +
interval`. The unit of `interval` can be set by the keyword `unit`, and the
following values are valid:

- `:s`: Seconds;
- `:m`: Minutes;
- `:h`: Hours; or
- `:d`: Days.

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
    interval::Int;
    unit::Symbol = :s
)
    end_time = begin
        if unit == :d
            start_time + Dates.Day(interval)
        elseif unit == :h
            start_time + Dates.Hour(interval)
        elseif unit == :m
            start_time + Dates.Minute(interval)
        else
            start_time + Dates.Second(interval)
        end
     end

    return get_telemetry(source, start_time, end_time)
end

function get_telemetry(start_time::DateTime, end_time::DateTime)
    !isassigned(_DEFAULT_TELEMETRY_SOURCE) &&
        error("The default telemetry source has not been assigned.")

    return get_telemetry(_DEFAULT_TELEMETRY_SOURCE[], start_time, end_time)
end

function get_telemetry(start_time::DateTime, interval::Int; unit::Symbol = :s)
    !isassigned(_DEFAULT_TELEMETRY_SOURCE) &&
        error("The default telemetry source has not been assigned.")

    return get_telemetry(_DEFAULT_TELEMETRY_SOURCE[], start_time, interval; unit)
end

"""
    set_default_telemetry_packet(tmpacket::Vector{TelemetryPacket})

Set the default telemetry packet to `tmpacket`.
"""
function set_default_telemetry_packet(tmpacket::Vector{TelemetryPacket{T}}) where T
    _DEFAULT_TELEMETRY_PACKETS[] = tmpacket
    return nothing
end
