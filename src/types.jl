# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Definition of types and structures.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export TelemetryDatabase, TelemetrySource, TelemetryPacket

"""
    abstract type TelemetrySource end

Abstract type for the telemetry sources.
"""
abstract type TelemetrySource end

"""
    struct TelemetryPacket{T <: TelemetrySource}

Telemetry packet obtained from the source `T`.

# Fields

- `timestamp::DateTime`: The timestamp of the telemetry packet.
- `raw::Vector{UInt8}`: The raw telemetry data encapsulated in a vector of
    `UInt8`.
- `metadata::Dict{String, Any}`: A dictionary to hold meta data about the
    telemetry packet.
"""
@kwdef struct TelemetryPacket{T <: TelemetrySource}
    timestamp::DateTime
    raw::Vector{UInt8}
    metadata::Dict{String, Any} = Dict{String, Any}()
end

"""
    struct TelemetryVariableDescription

Describe a variable in the telemetry database.

# Fields

- `alias::Union{Nothing, Symbol}`: An alias of the variable.
- `default_view::Symbol`: Select the default view for this variable during
    processing. For the list of available options, see
    [`process_telemetries`](@ref). (**Default** = `:processed`)
- `dependencies::Union{Nothing, Vector{Symbol}}`: A vector containing a list of
    dependencies required to obtain the processed value of this variable. If it
    is `nothing`, then the variable does not have dependencies.
- `description::String`: A description about the variable.
- `endianess::Symbol`: `:littleendian` or `:bigendian` to indicate the endianess
    of the variable.
- `label::Symbol`: The variable label.
- `position::Int`: The position of the variable in the unpacked telemetry frame.
- `size::Int`: The number of bytes of the variable.
- `btf::Function`: The bit transfer function to preprocess the raw telemetry
  frame.
- `tf::Function`: The transfer function to obtain the processed value.
"""
@kwdef struct TelemetryVariableDescription
    alias::Union{Nothing, Symbol}
    default_view::Symbol
    dependencies::Union{Nothing, Vector{Symbol}}
    description::String
    endianess::Symbol
    label::Symbol
    position::Int
    size::Int
    btf::Function
    tf::Function
end

"""
    struct TelemetryDatabase{F1 <: Function, F2 <: Function}

Defines a telemetry database.

# Fields

- `label::String`: The database label.
- `get_telemetry_timestamp::F1`: The function to get the timestamp of a
    telemetry packet.
- `unpack_telemetry::F2`: The function to unpack the telemetry packet, obtaining
    the data that will be passed to the transfer functions.
- `variables::OrderedDict{Symbol, TelemetryVariableDescription}`: The telemetry
    variables.
"""
@kwdef struct TelemetryDatabase{F1 <: Function, F2 <: Function}
    label::String
    get_telemetry_timestamp::F1
    unpack_telemetry::F2
    variables::Dict{Symbol, TelemetryVariableDescription} =
        Dict{Symbol, TelemetryVariableDescription}()
end
