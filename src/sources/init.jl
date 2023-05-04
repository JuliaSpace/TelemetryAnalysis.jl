# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==========================================================================================
#
#   Functions related to the initialization of sources.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export @register_interactive_source
export init_telemetry_source, set_default_telemetry_source!

"""
    @register_interactive_source(source)

Register `source` as interactive. Hence, it will be listed as an option if the user calls
`init_telemetry_source()`.
"""
macro register_interactive_source(source)

    expr = :(
        if $(esc(source)) <: TelemetrySource
            if $(esc(source)) ∉ _INTERACTIVE_SOURCES
                push!(_INTERACTIVE_SOURCES, $(esc(source)))
            end

            return nothing
        else
            error("$($(esc(source))) is not a TelemetrySource")
        end
    )

    return expr
end

"""
    init_telemetry_source([::Type{T}, vargs...; kwargs...]) where T<:TelemetrySource -> Union{T, Nothing}

Initialize the telemetry source `T`. If all arguments and keywords are omitted, the function
selects the source interactively.

The arguments `vargs...` and keywords `kwargs...` to initialize the source depends on the
source type.

This function returns an object of type `T` if the initialization was successful or
`nothing` otherwise.

!!! note
    If the source is correctly initialized, it is select as the default source.
"""
function init_telemetry_source()
    if isempty(_INTERACTIVE_SOURCES)
        @warn "There is no registered interactive sources."
        return nothing
    end

    choice = get_user_option("Select the source:", string.(_INTERACTIVE_SOURCES))

    if choice == -1
        @warn "No source was selected."
        return nothing
    end

    return init_telemetry_source(_INTERACTIVE_SOURCES[choice])
end

function init_telemetry_source(::Type{T}, vargs...; kwargs...) where T<:TelemetrySource
    @info "Initializing a telemetry source of type $T..."

    source = _api_init_telemetry_source(T, vargs...; kwargs...)::Union{Nothing, T}

    if isnothing(source)
        @warn "The telemetry source was not initialized."
    else
        set_default_telemetry_source!(source)
    end

    return source
end

"""
    set_default_telemetry_source!(source::T) where T<:TelemetrySource -> Nothing

Set the default telemetry source to `source`.
"""
function set_default_telemetry_source!(source::T) where T<:TelemetrySource
    _DEFAULT_TELEMETRY_SOURCE[] = source
    return nothing
end
