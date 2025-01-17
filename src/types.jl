## Description #############################################################################
#
# Definition of types and structures.
#
############################################################################################

export TelemetryDatabase, TelemetryVariableDescription, TelemetrySource
export TelemetryPacket
export default_bit_transfer_function

default_bit_transfer_function(frame::AbstractVector{UInt8}) = frame
default_raw_transfer_function(frame::AbstractVector{UInt8}) = frame

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
- `data::Vector{UInt8}`: The telemetry data encapsulated in a vector of `UInt8`.
- `metadata::Dict{String, Any}`: A dictionary to hold meta data about the telemetry packet.
"""
@kwdef struct TelemetryPacket{T<:TelemetrySource}
    timestamp::DateTime
    data::Vector{UInt8}
    metadata::Dict{String, Any} = Dict{String, Any}()
end

"""
    struct TelemetryVariableDescription

Describe a variable in the telemetry database.

# Fields

- `alias::Union{Nothing, Symbol}`: An alias of the variable.
- `default_view::Symbol`: Select the default view for this variable during processing. For
    the list of available options, see [`process_telemetries`](@ref).
    (**Default** = `:processed`)
- `dependencies::Union{Nothing, Vector{Symbol}}`: A vector containing a list of dependencies
    required to obtain the processed value of this variable. If it is `nothing`, the
    variable does not have dependencies.
- `description::String`: A description about the variable.
- `endianess::Symbol`: `:littleendian` or `:bigendian` to indicate the endianess of the
    variable.
- `label::Symbol`: Variable label.
- `position::Int`: Variable position in the unpacked telemetry frame.
- `size::Int`: Number of bytes of the variable.
- `btf::Function`: Bit transfer function to obtain the variable byte array data from the
    telemetry frame.
- `rtf::Function`: Raw transfer function to obtain the raw value from the byte array.
- `tf::Function`: Transfer function to obtain the processed value.
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
    tf::Function
    btf::Function
    rtf::Function
end

"""
    struct TelemetryDatabase{F1 <: Function, F2 <: Function}

Defines a telemetry database.

# Fields

- `label::String`: Database label.
- `get_telemetry_timestamp::F1`: Function to get the timestamp of a telemetry packet.
- `unpack_telemetry::F2`: Function to unpack the telemetry packet, obtaining the data that
    will be passed to the transfer functions.
- `variables::OrderedDict{Symbol, TelemetryVariableDescription}`: Telemetry variables.
"""
@kwdef struct TelemetryDatabase{F1 <: Function, F2 <: Function}
    label::String
    get_telemetry_timestamp::F1
    unpack_telemetry::F2
    variables::Dict{Symbol, TelemetryVariableDescription} =
        Dict{Symbol, TelemetryVariableDescription}()

    # == Private fields ====================================================================

    # This field caches the dependency vector of each variable sorted in topological order.
    # It is build when a variable is processed.
    _variable_dependencies::Dict{Symbol, Union{Nothing, Vector{Symbol}}} =
        Dict{Symbol, Union{Nothing, Vector{Symbol}}}()
end
