## Description #############################################################################
#
# Definition of types and structures.
#
############################################################################################

export TelemetryDatabase, TelemetryVariableDescription, TelemetrySource
export TelemetryPacket, getmetadata, hasmetadata, with_metadata
export default_bit_transfer_function

# Preserve the ephemeral frame view for the default bit conversion.
default_bit_transfer_function(frame::AbstractVector{UInt8}) = frame

# Preserve the byte representation for the default raw conversion.
default_raw_transfer_function(frame::AbstractVector{UInt8}) = frame

const _SUPPORTED_VARIABLE_VIEWS = (
    :byte_array,
    :byte_array_bin,
    :byte_array_hex,
    :processed,
    :raw,
)

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
- `metadata::Union{Nothing, Dict{String, Any}}`: Optional metadata about the telemetry
    packet; pass a dictionary explicitly when mutable metadata is required.
    (**Default**: `nothing`)
"""
@kwdef struct TelemetryPacket{T<:TelemetrySource}
    timestamp::DateTime
    data::Vector{UInt8}
    metadata::Union{Nothing, Dict{String, Any}} = nothing
end

"""
    hasmetadata(packet::TelemetryPacket) -> Bool

Return `true` only when `packet` has a nonempty metadata dictionary.
"""
function hasmetadata(packet::TelemetryPacket)
    # Inspect the optional dictionary directly without allocating a normalized replacement.
    metadata = packet.metadata
    return metadata !== nothing && !isempty(metadata)
end

"""
    getmetadata(packet::TelemetryPacket, key, default = nothing) -> Any

Return the metadata value for `key`, or `default` when the packet has no metadata or the key
is absent. This function does not create or attach a metadata dictionary.
"""
function getmetadata(packet::TelemetryPacket, key, default = nothing)
    # Read through `nothing` without creating or attaching metadata storage.
    metadata = packet.metadata
    return metadata === nothing ? default : get(metadata, key, default)
end

"""
    with_metadata(packet::TelemetryPacket, metadata) -> TelemetryPacket

Return a new packet with the same source type, timestamp, and data. `nothing` remains
`nothing`; an `AbstractDict` is copied into a mutable `Dict{String, Any}`. The original
packet and input dictionary are not mutated.

The `nothing` default is a structural layout change. Older package versions are not required
to deserialize packets written with this layout.
"""
function with_metadata(
    packet::TelemetryPacket{T},
    metadata::Union{Nothing, AbstractDict},
) where T <: TelemetrySource
    # Normalize dictionaries to the declared mutable type without sharing caller storage.
    normalized = metadata === nothing ? nothing : Dict{String, Any}(metadata)
    # Share packet data intentionally because only the metadata value is being replaced.
    return TelemetryPacket{T}(;
        timestamp = packet.timestamp,
        data = packet.data,
        metadata = normalized,
    )
end

"""
    struct TelemetryVariableDescription

Describe a variable in the telemetry database.

# Fields

- `alias::Union{Nothing, Symbol}`: An alias of the variable.
- `default_view::Symbol`: Select the default view for this variable during processing. For
    the list of available options, see [`process_telemetry_packets`](@ref).
- `dependencies::Union{Nothing, Vector{Symbol}}`: A vector containing a list of dependencies
    required to obtain the processed value of this variable. If it is `nothing`, the
    variable does not have dependencies.
- `description::String`: A description about the variable.
- `endianess::Symbol`: `:littleendian` or `:bigendian` to indicate the endianness of the
    variable.
- `label::Symbol`: Variable label.
- `position::Int`: Variable position in the unpacked telemetry frame.
- `size::Int`: Number of bytes of the variable.
- `tf::Function`: Transfer function to obtain the processed value.
- `btf::Function`: Bit transfer function to obtain the variable byte array data from the
    telemetry frame. Its byte input is an ephemeral, read-only `AbstractVector` view and
    must not be mutated or retained.
- `rtf::Function`: Raw transfer function to obtain the raw value from the byte array. Its
    byte input is ephemeral and read-only and must not be mutated or retained. It can be an
    `AbstractVector` view, including when the default bit transfer function is used.
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
- `variables::Dict{Symbol, TelemetryVariableDescription}`: Telemetry variables.
    (**Default**: `Dict{Symbol, TelemetryVariableDescription}()`)
- `_variable_dependencies::Dict{Symbol, Union{Nothing, Vector{Symbol}}}`: Legacy dependency
    storage retained for layout compatibility; processing does not consult it.
    (**Default**: `Dict{Symbol, Union{Nothing, Vector{Symbol}}}()`)
"""
@kwdef struct TelemetryDatabase{F1 <: Function, F2 <: Function}
    label::String
    get_telemetry_timestamp::F1
    unpack_telemetry::F2
    variables::Dict{Symbol, TelemetryVariableDescription} =
        Dict{Symbol, TelemetryVariableDescription}()

    # == Private fields ====================================================================

    # Retained for public layout compatibility. Processing does not persist dependency plans
    # while `variables` remains publicly mutable.
    _variable_dependencies::Dict{Symbol, Union{Nothing, Vector{Symbol}}} =
        Dict{Symbol, Union{Nothing, Vector{Symbol}}}()
end

"""
    DatabaseIndex

Ephemeral validated index of a telemetry database. It maps aliases to canonical labels and
stores canonical labels in deterministic lexical order. An index is built fresh for public
resolution and processing because `TelemetryDatabase.variables` is publicly mutable.

# Fields

- `aliases::Dict{Symbol, Symbol}`: Map from each alias to its canonical variable label.
- `canonical_labels::Vector{Symbol}`: Canonical labels in deterministic lexical order.
"""
struct DatabaseIndex
    aliases::Dict{Symbol, Symbol}
    canonical_labels::Vector{Symbol}
end

# Mark execution of the bit transfer function that produces the byte-array stage.
const _STAGE_BYTE = UInt8(0x01)

# Mark execution of the raw transfer function that consumes the byte-array stage.
const _STAGE_RAW = UInt8(0x02)

# Mark execution of the transfer function that produces the processed stage.
const _STAGE_PROCESSED = UInt8(0x04)

# Combine the byte and raw flags because raw output requires both preceding stages.
const _STAGES_THROUGH_RAW = _STAGE_BYTE | _STAGE_RAW

# Combine every flag because processed output requires the complete callback pipeline.
const _STAGES_THROUGH_PROCESSED = _STAGES_THROUGH_RAW | _STAGE_PROCESSED

"""
    AbstractExecutionNode

Abstract boundary for heterogeneous internal execution nodes.
"""
abstract type AbstractExecutionNode end

"""
    ExecutionNode

Internal variable executor whose callback fields retain their concrete callable types.

# Fields

- `label::Symbol`: Canonical variable label.
- `variable_desc::TelemetryVariableDescription`: Validated public variable descriptor.
- `btf::B`: Concrete bit transfer callback.
- `rtf::R`: Concrete raw transfer callback.
- `tf::F`: Concrete processed transfer callback.
"""
struct ExecutionNode{B, R, F} <: AbstractExecutionNode
    label::Symbol
    variable_desc::TelemetryVariableDescription
    btf::B
    rtf::R
    tf::F
end

"""
    OutputSpec

Precomputed mapping from one requested view to its canonical value and output name.

# Fields

- `canonical_label::Symbol`: Canonical label supplying the requested value.
- `node_index::Int`: Index of the supplying node in the execution plan.
- `view::Symbol`: Requested output view.
- `output_name::Symbol`: Validated output column name.
"""
struct OutputSpec
    canonical_label::Symbol
    node_index::Int
    view::Symbol
    output_name::Symbol
end

"""
    ExecutionPlan

Fresh uncached processing plan containing topologically ordered nodes and output mappings.

# Fields

- `nodes::Vector{AbstractExecutionNode}`: Topologically ordered heterogeneous executors.
- `stage_masks::Vector{UInt8}`: Required cumulative stage mask for each node.
- `outputs::Vector{OutputSpec}`: Requested outputs in user-visible column order.
"""
struct ExecutionPlan
    nodes::Vector{AbstractExecutionNode}
    stage_masks::Vector{UInt8}
    outputs::Vector{OutputSpec}
end

"""
    PacketExecutionState

Mutable values created independently for each packet while executing a plan.

# Fields

- `byte_arrays::Vector{Any}`: Node-indexed bit transfer results.
- `raw_values::Vector{Any}`: Node-indexed raw transfer results.
- `processed_values::Vector{Any}`: Node-indexed processed transfer results.
- `context::Dict{Symbol, Any}`: Fresh canonical-label callback context for the packet.
"""
struct PacketExecutionState
    byte_arrays::Vector{Any}
    raw_values::Vector{Any}
    processed_values::Vector{Any}
    context::Dict{Symbol, Any}
end

# Allocate uninitialized node slots because stage masks determine which slots are written.
PacketExecutionState(node_count::Int) = PacketExecutionState(
    Vector{Any}(undef, node_count),
    Vector{Any}(undef, node_count),
    Vector{Any}(undef, node_count),
    Dict{Symbol, Any}()
)
