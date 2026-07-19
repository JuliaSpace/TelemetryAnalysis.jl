## Description #############################################################################
#
# Functions to build fresh telemetry execution plans.
#
############################################################################################

"""
    _build_execution_plan(telemetries, database, index) -> ExecutionPlan

Build a fresh execution plan for the requested telemetry views. The plan resolves aliases,
computes the recursive dependency union, and topologically orders every required variable
before packet processing starts.
"""
function _build_execution_plan(
    telemetries::Vector{Pair{Symbol, Symbol}},
    database::TelemetryDatabase,
    index::DatabaseIndex
)
    # Merge cumulative stage requirements by canonical label while retaining output order.
    stage_masks = Dict{Symbol, UInt8}()
    discovery_order = Symbol[]
    outputs = OutputSpec[]

    for (requested_label, view) in telemetries
        view in _SUPPORTED_VARIABLE_VIEWS || throw(ArgumentError(
            "Unsupported view :$view for telemetry :$requested_label. " *
            "Supported views are $(join(_SUPPORTED_VARIABLE_VIEWS, ", "))."
        ))

        variable_desc = _get_variable_description(requested_label, database, index)
        canonical_label = variable_desc.label
        if !haskey(stage_masks, canonical_label)
            stage_masks[canonical_label] = UInt8(0)
            push!(discovery_order, canonical_label)
        end
        stage_masks[canonical_label] |= _required_stage_mask(view)
        push!(outputs, OutputSpec(
            canonical_label,
            0,
            view,
            _output_name(requested_label, view)
        ))
    end

    _validate_output_names(outputs)

    _expand_dependency_union!(stage_masks, discovery_order, database, index)
    ordered_labels = _topological_order(
        discovery_order,
        stage_masks,
        database,
        index
    )

    nodes = AbstractExecutionNode[]
    ordered_masks = UInt8[]
    sizehint!(nodes, length(ordered_labels))
    sizehint!(ordered_masks, length(ordered_labels))
    for label in ordered_labels
        variable_desc = _get_variable_description(label, database, index)
        push!(nodes, _execution_node(variable_desc))
        push!(ordered_masks, stage_masks[label])
    end

    # Resolve output indices only after dependency ordering fixes final node positions.
    node_indices = Dict(node.label => index for (index, node) in pairs(nodes))
    resolved_outputs = [
        OutputSpec(
            output.canonical_label,
            node_indices[output.canonical_label],
            output.view,
            output.output_name
        )
        for output in outputs
    ]

    return ExecutionPlan(nodes, ordered_masks, resolved_outputs)
end

"""
    _validate_output_names(outputs) -> Nothing

Reject concrete output-name collisions in the current request.
"""
function _validate_output_names(outputs::Vector{OutputSpec})
    # Seed timestamp ownership so requested columns cannot collide with the fixed column.
    owners = Dict{Symbol, Int}(:timestamp => 0)
    for (selection_index, output) in pairs(outputs)
        if haskey(owners, output.output_name)
            throw(ArgumentError(
                "Output column :$(output.output_name) collides between selections " *
                "$(owners[output.output_name]) and $selection_index."
            ))
        end
        owners[output.output_name] = selection_index
    end
    return nothing
end

"""
    _required_stage_mask(view::Symbol) -> UInt8

Return the cumulative callback stages required by an output view.
"""
function _required_stage_mask(view::Symbol)
    # Return cumulative masks because each later callback consumes the preceding stage.
    if view in (:byte_array, :byte_array_bin, :byte_array_hex)
        return _STAGE_BYTE
    elseif view === :raw
        return _STAGES_THROUGH_RAW
    else
        return _STAGES_THROUGH_PROCESSED
    end
end

"""
    _output_name(label::Symbol, view::Symbol) -> Symbol

Return the output column name under the current public naming rules.
"""
function _output_name(label::Symbol, view::Symbol)
    # Apply the public suffix rules without reserving names outside this request.
    if view in (:byte_array, :byte_array_bin, :byte_array_hex)
        return Symbol(string(label) * "_byte_array")
    elseif view === :raw
        return Symbol(string(label) * "_raw")
    else
        return label
    end
end

"""
    _expand_dependency_union!(stage_masks, discovery_order, database, index) -> Nothing

Include every declared dependency through its processed stage. Each variable's outgoing
edges are expanded at most once.
"""
function _expand_dependency_union!(
    stage_masks::Dict{Symbol, UInt8},
    discovery_order::Vector{Symbol},
    database::TelemetryDatabase,
    index::DatabaseIndex
)
    # Use an index queue over discovery order for deterministic linear traversal.
    expanded = Set{Symbol}()
    queue_index = 1
    while queue_index <= length(discovery_order)
        label = discovery_order[queue_index]
        queue_index += 1
        label in expanded && continue
        stage_masks[label] & _STAGE_RAW == 0 && continue
        push!(expanded, label)

        variable_desc = _get_variable_description(label, database, index)
        dependencies = variable_desc.dependencies
        isnothing(dependencies) && continue
        for dependency in dependencies
            dependency_desc = _resolve_dependency(dependency, label, database, index)
            canonical_dependency = dependency_desc.label
            # Promote every dependency through processed and revisit byte-only discoveries.
            if !haskey(stage_masks, canonical_dependency)
                stage_masks[canonical_dependency] = UInt8(0)
                push!(discovery_order, canonical_dependency)
            elseif stage_masks[canonical_dependency] & _STAGE_RAW == 0
                push!(discovery_order, canonical_dependency)
            end
            stage_masks[canonical_dependency] |= _STAGES_THROUGH_PROCESSED
        end
    end

    return nothing
end

"""
    _resolve_dependency(dependency, owner, database, index)

Resolve a dependency to its canonical descriptor or throw a contextual `KeyError`.
"""
function _resolve_dependency(
    dependency::Symbol,
    owner::Symbol,
    database::TelemetryDatabase,
    index::DatabaseIndex
)
    # Add owner context for missing references while preserving other validation errors.
    try
        return _get_variable_description(dependency, database, index)
    catch error
        if error isa KeyError
            throw(KeyError(
                "Dependency :$dependency required by variable :$owner is missing."
            ))
        end
        rethrow()
    end
end

"""
    _topological_order(discovery_order, stage_masks, database, index) -> Vector{Symbol}

Topologically order the required dependency graph using three-state visitation.
"""
function _topological_order(
    discovery_order::Vector{Symbol},
    stage_masks::Dict{Symbol, UInt8},
    database::TelemetryDatabase,
    index::DatabaseIndex
)
    # Visit roots in deterministic discovery order; each edge is handled by three-state DFS.
    states = Dict{Symbol, UInt8}()
    ordered_labels = Symbol[]
    for label in discovery_order
        _topological_visit!(
            label,
            states,
            ordered_labels,
            stage_masks,
            database,
            index
        )
    end
    return ordered_labels
end

"""
    _topological_visit!(label, states, ordered_labels, stage_masks, database, index)

Visit one required variable, rejecting cycles deterministically.
"""
function _topological_visit!(
    label::Symbol,
    states::Dict{Symbol, UInt8},
    ordered_labels::Vector{Symbol},
    stage_masks::Dict{Symbol, UInt8},
    database::TelemetryDatabase,
    index::DatabaseIndex
)
    # States 0, 1, and 2 mean unseen, active, and complete, respectively.
    state = get(states, label, UInt8(0))
    state == 0x02 && return nothing
    state == 0x01 && error("Cyclic dependency detected at variable :$label.")
    states[label] = UInt8(1)

    if stage_masks[label] & _STAGE_RAW != 0
        dependencies = _get_variable_description(label, database, index).dependencies
        if !isnothing(dependencies)
            for dependency in dependencies
                dependency_desc = _resolve_dependency(dependency, label, database, index)
                _topological_visit!(
                    dependency_desc.label,
                    states,
                    ordered_labels,
                    stage_masks,
                    database,
                    index
                )
            end
        end
    end

    states[label] = UInt8(2)
    push!(ordered_labels, label)
    return nothing
end

"""
    _execution_node(variable_desc) -> ExecutionNode

Capture a public descriptor's callbacks in a concretely parameterized internal node.
"""
function _execution_node(variable_desc::TelemetryVariableDescription)
    # Capture public callbacks in parametric fields for specialized packet execution.
    return ExecutionNode(
        variable_desc.label,
        variable_desc,
        variable_desc.btf,
        variable_desc.rtf,
        variable_desc.tf
    )
end
