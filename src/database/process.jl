## Description #############################################################################
#
# Functions to process variables in the database.
#
############################################################################################

export process_telemetry_packets

"""
    process_telemetry_packets(
        [tmpackets::Vector{TelemetryPacket{T}}];
        database::TelemetryDatabase,
        kwargs...
    ) where T <: TelemetrySource -> DataFrame

Process the telemetry packets `tmpackets` using the `database`, returning the processed
values of **all** registered variables in lexical canonical-label order. If `tmpackets`
are not passed, the default telemetry packets will be used.

    process_telemetry_packets(
        [tmpackets::Vector{TelemetryPacket{T}},]
        telemetries::AbstractVector;
        database::TelemetryDatabase,
        kwargs...
    ) where T <: TelemetrySource -> DataFrame

Process the telemetry packets `tmpackets` using the `database`. The elements in
`telemetries` can be a `Symbol` with the telemetry label or a `Pair{Symbol, Symbol}`. In the
former, the default view will be used. In the latter, the variable view will be as specified
by the second symbol in the pair.  For more information, see the section below.

If `tmpackets` are not passed, the default telemetry packets will be used.

    process_telemetry_packets(
        [tmpackets::Vector{TelemetryPacket{T}},]
        telemetries::Vector{Pair{Symbol, Symbol}};
        database::TelemetryDatabase,
        kwargs...
    ) where T <: TelemetrySource -> DataFrame

Process the telemetry packets `tmpackets` using the `database`. The output variables are
indicated in `telemetries`. It must be a vector of pairs indicating the telemetry and how
the value is written to the output. For example, `:C001 => :raw` adds the raw value of
telemetry `C001`, whereas `:C001 => :processed` adds the processed value of the same
variable.

The acceptable values for the output format are:

- `:byte_array`: Owned `Vector{UInt8}` with the telemetry byte array.
- `:byte_array_bin`: String with the raw value represented in binary.
- `:byte_array_hex`: String with the raw value represented in hexadecimal.
- `:processed`: Processed value obtained from the transfer function.
- `:raw`: Telemetry raw value.

If `tmpackets` are not passed, the default telemetry packets will be used.

Explicit selections preserve their requested order. Concrete output-name collisions are
rejected before packet processing. Each required byte, raw, and processed callback stage
executes at most once per successfully processed packet; ordering among unrelated callbacks
is not guaranteed. Packets whose unpack callback returns `nothing` are omitted. Output rows
are sorted by timestamp, with equal timestamps retaining their original input order.

!!! info

    If the keyword argument `database` is not passed, the default database is used.

# Keywords

- `show_progress::Bool`: If `true`, a progress bar is shown while processing the
    telemetries. (**Default** = `true`)

# Return

- `DataFrame`: A `DataFrame` in which the columns are the selected values. The column names
    are the variable labels. For empty packet vectors, `timestamp` has element type
    `DateTime`; output columns use `Any` because their result types cannot be inferred
    without processing a packet.
"""
function process_telemetry_packets(;
    database::TelemetryDatabase = get_default_database(),
    show_progress::Bool = true
)
    return process_telemetry_packets(
        get_default_telemetry_packets();
        database,
        show_progress
    )
end

function process_telemetry_packets(
    tmpackets::Vector{TelemetryPacket{T}};
    database::TelemetryDatabase = get_default_database(),
    show_progress::Bool = true
) where T <: TelemetrySource

    index = _build_database_index(database)

    telemetries = Pair{Symbol, Symbol}[
        label => database.variables[label].default_view
        for label in index.canonical_labels
    ]

    return _process_telemetry_packets(
        tmpackets,
        telemetries,
        database,
        index,
        show_progress
    )
end

function process_telemetry_packets(
    telemetries::AbstractVector;
    database::TelemetryDatabase = get_default_database(),
    show_progress::Bool = true
)
    return process_telemetry_packets(
        get_default_telemetry_packets(),
        telemetries;
        database,
        show_progress
    )
end

function process_telemetry_packets(
    tmpackets::Vector{TelemetryPacket{T}},
    telemetries::AbstractVector;
    database::TelemetryDatabase = get_default_database(),
    show_progress::Bool = true
) where T <: TelemetrySource
    index = _build_database_index(database)
    selections = Pair{Symbol, Symbol}[
        if telemetry isa Pair{Symbol, Symbol}
            telemetry
        else
            telemetry => _get_variable_description(
                telemetry,
                database,
                index
            ).default_view
        end
        for telemetry in telemetries
    ]

    return _process_telemetry_packets(
        tmpackets,
        selections,
        database,
        index,
        show_progress
    )
end

function process_telemetry_packets(
    telemetries::Vector{Pair{Symbol, Symbol}};
    database::TelemetryDatabase = get_default_database(),
    show_progress::Bool = true
)
    return process_telemetry_packets(
        get_default_telemetry_packets(),
        telemetries;
        database,
        show_progress
    )
end

function process_telemetry_packets(
    tmpackets::Vector{TelemetryPacket{T}},
    telemetries::Vector{Pair{Symbol, Symbol}};
    database::TelemetryDatabase = get_default_database(),
    show_progress::Bool = true
) where T <: TelemetrySource
    index = _build_database_index(database)

    return _process_telemetry_packets(
        tmpackets,
        telemetries,
        database,
        index,
        show_progress
    )
end

"""
    _process_telemetry_packets(tmpackets, telemetries, database, index, show_progress)

Process validated telemetry selections using one ephemeral database index.
"""
function _process_telemetry_packets(
    tmpackets::Vector{TelemetryPacket{T}},
    telemetries::Vector{Pair{Symbol, Symbol}},
    database::TelemetryDatabase,
    index::DatabaseIndex,
    show_progress::Bool
) where T <: TelemetrySource
    plan         = _build_execution_plan(telemetries, database, index)
    packet_count = length(tmpackets)

    # Allocate packet-indexed columns so threads write disjoint slots without output locks.
    timestamps     = Vector{DateTime}(undef, packet_count)
    output_storage = [Vector{Any}(undef, packet_count) for _ in plan.outputs]

    # Use one independently writable flag per packet; packed bits complicate threaded writes.
    validity = Vector{Bool}(undef, packet_count)
    fill!(validity, false)

    # Check if the database supports the current telemetry source.
    if !isempty(tmpackets) && !applicable(database.unpack_telemetry, first(tmpackets))
        error("The selected database does not support telemetries from $(T).")
    end

    # Progress meter.
    progress = Progress(packet_count; color = :reset, enabled = show_progress)

    Threads.@threads for packet_index in eachindex(tmpackets)
        tmpacket = tmpackets[packet_index]

        # Unpack the telemetry frame.
        unpacked_frame = database.unpack_telemetry(tmpacket)

        if unpacked_frame === nothing
            next!(progress)
            continue
        end

        # Ask for the packet timestamp.
        timestamps[packet_index] = database.get_telemetry_timestamp(tmpacket)

        state = PacketExecutionState(length(plan.nodes))

        for node_index in eachindex(plan.nodes)
            _execute_node!(
                state,
                plan.nodes[node_index],
                unpacked_frame,
                node_index,
                plan.stage_masks[node_index]
            )
        end

        for output_index in eachindex(plan.outputs)
            output_storage[output_index][packet_index] = _output_value(
                state,
                plan.outputs[output_index]
            )
        end

        validity[packet_index] = true
        next!(progress)
    end

    finish!(progress)

    # Filter validity before reading any timestamp or output slot left uninitialized.
    valid_indices = _stable_valid_indices(validity, timestamps)

    # Defer DataFrame construction until threaded writes and stable ordering are complete.
    output = _build_output_dataframe(
        timestamps,
        output_storage,
        valid_indices,
        plan.outputs
    )

    @info "$(nrow(output)) packets out of $packet_count were processed correctly."
    return output
end

"""
    _execute_node!(state, node, unpacked_frame, node_index, stage_mask) -> Nothing

Execute the required stages for one concrete-callback node.
"""
function _execute_node!(
    state::PacketExecutionState,
    node::ExecutionNode{B, R, F},
    unpacked_frame::AbstractVector{UInt8},
    node_index::Int,
    stage_mask::UInt8
) where {B, R, F}
    # Execute one cumulative stage mask so duplicate outputs share all callback results.
    variable_frame = _get_variable_telemetry_frame(
        unpacked_frame,
        node.variable_desc
    )

    byte_array = _execute_btf(node, variable_frame)

    if !(byte_array isa AbstractVector{UInt8})
        throw(ArgumentError(
            "Bit transfer callback for variable :$(node.label) must return an " *
            "AbstractVector{UInt8}; received $(typeof(byte_array))."
        ))
    end

    state.byte_arrays[node_index] = byte_array

    stage_mask & _STAGE_RAW == 0 && return nothing
    raw_value = _execute_rtf(node, byte_array, state.context)
    state.raw_values[node_index] = raw_value

    stage_mask & _STAGE_PROCESSED == 0 && return nothing
    processed_value = _execute_tf(node, raw_value, state.context)
    state.processed_values[node_index] = processed_value

    # Publish processed values under canonical labels for downstream callback contexts.
    state.context[node.label] = (; raw = raw_value, processed = processed_value)
    return nothing
end

"""
    _execute_btf(node, variable_frame)

Invoke a node's concretely typed bit transfer callback.
"""
function _execute_btf(node::ExecutionNode{B, R, F}, variable_frame) where {B, R, F}
    return node.btf(variable_frame)
end

"""
    _execute_rtf(node, byte_array, context)

Invoke a node's concretely typed raw callback while preserving `applicable` semantics.
"""
function _execute_rtf(
    node::ExecutionNode{B, R, F},
    byte_array,
    context::Dict{Symbol, Any}
) where {B, R, F}
    # Prefer the context-aware callback whenever both supported signatures are applicable.
    if applicable(node.rtf, byte_array, context)
        return node.rtf(byte_array, context)
    else
        return node.rtf(byte_array)
    end
end

"""
    _execute_tf(node, raw_value, context)

Invoke a node's concretely typed processed callback while preserving `applicable` semantics.
"""
function _execute_tf(
    node::ExecutionNode{B, R, F},
    raw_value,
    context::Dict{Symbol, Any}
) where {B, R, F}
    # Prefer the context-aware callback whenever both supported signatures are applicable.
    if applicable(node.tf, raw_value, context)
        return node.tf(raw_value, context)
    else
        return node.tf(raw_value)
    end
end

"""
    _output_value(state, output_spec)

Materialize one requested output from packet execution state.
"""
function _output_value(state::PacketExecutionState, output_spec::OutputSpec)
    node_index = output_spec.node_index
    view       = output_spec.view

    # Copy byte output so rows do not retain callback-owned or frame-backed storage.
    if view === :byte_array
        return Vector{UInt8}(state.byte_arrays[node_index])
    elseif view === :byte_array_bin
        return byte_array_to_binary(state.byte_arrays[node_index])
    elseif view === :byte_array_hex
        return byte_array_to_hex(state.byte_arrays[node_index])
    elseif view === :raw
        return state.raw_values[node_index]
    else
        return state.processed_values[node_index]
    end
end

"""
    _stable_valid_indices(validity, timestamps) -> Vector{Int}

Return valid packet indices in stable timestamp order. Avoid sorting when they are already
ordered.
"""
function _stable_valid_indices(validity::Vector{Bool}, timestamps::Vector{DateTime})
    valid_indices = findall(validity)

    # Detect chronological input in one pass and return without allocating a permutation.
    already_sorted = true

    for index in 2:length(valid_indices)
        previous = valid_indices[index - 1]
        current = valid_indices[index]
        if timestamps[current] < timestamps[previous]
            already_sorted = false
            break
        end
    end

    already_sorted && return valid_indices

    # MergeSort preserves original packet order for equal timestamps.
    permutation = sortperm(
        valid_indices;
        by = index -> timestamps[index],
        alg = Base.Sort.MergeSort
    )

    return valid_indices[permutation]
end

"""
    _build_output_dataframe(timestamps, storage, valid_indices, outputs) -> DataFrame

Filter packet-indexed storage, narrow homogeneous columns once, and construct owned output.
"""
function _build_output_dataframe(
    timestamps::Vector{DateTime},
    storage::Vector{Vector{Any}},
    valid_indices::Vector{Int},
    outputs::Vector{OutputSpec}
)
    # Gather valid slots before narrowing so uninitialized packet slots are never read.
    output_timestamps = DateTime[timestamps[index] for index in valid_indices]
    columns           = Pair{Symbol, AbstractVector}[:timestamp => output_timestamps]

    for output_index in eachindex(outputs)
        values = Any[storage[output_index][index] for index in valid_indices]
        push!(columns, outputs[output_index].output_name => _narrow_output_column(values))
    end

    # Transfer ownership of newly allocated columns without another DataFrame-level copy.
    return DataFrame(columns; copycols = false)
end

"""
    _narrow_output_column(values::Vector{Any}) -> AbstractVector

Narrow a nonempty output column to a common non-converting type join, retaining `Any` when
necessary.
"""
function _narrow_output_column(values::Vector{Any})
    isempty(values) && return values

    # Join types without numeric promotion so original value representations remain intact.
    element_type = Union{}
    for value in values
        element_type = Base.promote_typejoin(element_type, typeof(value))
    end
    element_type === Any && return values

    narrowed_values = Vector{element_type}(undef, length(values))
    for index in eachindex(values)
        narrowed_values[index] = values[index]
    end

    return narrowed_values
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _get_variable_telemetry_frame(unpacked_frame, variable_desc)

Return an ephemeral read-only view of a variable frame. Little-endian variables use a
forward view, big-endian variables use a negative-stride view, and derived-only variables
use a parent-backed empty view starting at `firstindex(unpacked_frame)`. Descriptor
positions are logical one-based byte offsets, independent of the vector's native indices.
"""
function _get_variable_telemetry_frame(
    unpacked_frame::AbstractVector{UInt8},
    variable_desc::TelemetryVariableDescription
)
    # Anchor at the parent's first index before translating logical one-based positions.
    first_frame_index = firstindex(unpacked_frame)
    position = variable_desc.position
    size = variable_desc.size

    if iszero(variable_desc.size)
        # Return an empty view so derived variables preserve parent ownership and axes.
        iszero(position) || throw(ArgumentError(
            "Derived-only variable :$(variable_desc.label) must use position 0 and size 0."
        ))
        return @view unpacked_frame[first_frame_index:(first_frame_index - 1)]
    end

    if position < 1 || size < 1
        throw(ArgumentError(
            "Frame-backed variable :$(variable_desc.label) must have positive position " *
            "and size."
        ))
    end

    frame_length = length(unpacked_frame)
    if position > frame_length
        throw(ArgumentError(
            "Variable :$(variable_desc.label) starts at logical byte $position, but the " *
            "unpacked frame contains $frame_length bytes."
        ))
    end

    available_length = frame_length - position + 1
    if size > available_length
        throw(ArgumentError(
            "Variable :$(variable_desc.label) requests $size bytes from logical byte " *
            "$position, but only $available_length bytes are available."
        ))
    end

    # Derive native indices only after validating the logical frame range.
    initial_byte = first_frame_index + (position - 1)
    end_byte = initial_byte + (size - 1)

    if variable_desc.endianess == :bigendian
        # Reverse with a negative-stride view so big-endian extraction remains zero-copy.
        return @view unpacked_frame[end_byte:-1:initial_byte]
    else
        # Preserve logical byte order while returning a zero-copy forward view.
        return @view unpacked_frame[initial_byte:end_byte]
    end
end
