# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   API functions to implement a new source.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _api_init_telemetry_source(::Type{T}, vargs...; kwargs...)

API function to initialize a telemetry source of type `T`.

This function must return an object of type `T` if the initialization was
successful or `nothing` otherwise.
"""
function _api_init_telemetry_source(
    ::Type{T},
    vargs...;
    kwargs...
) where T <: TelemetrySource
    error("`init_telemetry_source` is not implemented for the source $(T).`")
end

"""
    _api_get_telemetry(source::T, start_time::DateTime, end_time::DateTime)

API function to get telemetry from `source` between `start_time` and `end_time`.

This function must return an object
"""
function _api_get_telemetry(
    source::T,
    start_time::DateTime,
    end_time::DateTime
) where T <: TelemetrySource
    error("`get_telemetry` is not implemented for the source $(T).`")
end
