## Description #############################################################################
#
# Functions to get variables from the database.
#
############################################################################################

export get_default_database, get_variable_description, search_variables
export @searchvar

"""
    get_default_database() -> Any

Get the default database. This function throws an error if it is not defined yet.
"""
function get_default_database()
    !isassigned(_DEFAULT_TELEMETRY_DATABASE) &&
        error("The default telemetry database has not been assigned.")

    return _DEFAULT_TELEMETRY_DATABASE[]
end

"""
    get_variable_description(
        label::Symbol,
        database::TelemetryDatabase
    ) -> TelemetryVariableDescription

Get the description of a variable with `label` in `database`. Notice that `label` can also
be the variable alias. The database is validated before resolution. A missing label or alias
throws `KeyError`; an invalid or ambiguous database throws `ArgumentError`.
"""
function get_variable_description(label::Symbol, database::TelemetryDatabase)
    index = _build_database_index(database)
    return _get_variable_description(label, database, index)
end

"""
    _build_database_index(database::TelemetryDatabase) -> DatabaseIndex

Validate `database.variables` and build a fresh alias map and deterministic canonical-label
vector. The result is ephemeral because callers can directly mutate the public dictionary.
"""
function _build_database_index(database::TelemetryDatabase)
    # Revalidate on every call because the public variables dictionary can change directly.
    return _build_database_index(database.variables)
end

function _build_database_index(
    variables::AbstractDict{Symbol, TelemetryVariableDescription}
)
    # Sort canonical labels so validation and all-variable processing are deterministic.
    canonical_labels = collect(keys(variables))
    sort!(canonical_labels; by = string)
    canonical_set = Set(canonical_labels)

    # Validate descriptors before aliases so malformed canonical entries fail first.
    for label in canonical_labels
        variable_desc = variables[label]
        label === variable_desc.label || throw(ArgumentError(
            "Database key :$label does not match descriptor label :$(variable_desc.label)."
        ))
        _validate_variable_description(variable_desc)
    end

    # Detect alias conflicts only after the complete canonical label set is known.
    aliases = Dict{Symbol, Symbol}()
    for label in canonical_labels
        alias = variables[label].alias
        isnothing(alias) && continue

        alias === :timestamp && throw(ArgumentError(
            "The alias :timestamp is reserved."
        ))
        alias in canonical_set && throw(ArgumentError(
            "Alias :$alias conflicts with variable label :$alias."
        ))
        haskey(aliases, alias) && throw(ArgumentError(
            "Alias :$alias is ambiguous between variables :$(aliases[alias]) and :$label."
        ))
        aliases[alias] = label
    end

    return DatabaseIndex(aliases, canonical_labels)
end

"""
    _validate_variable_description(variable_desc::TelemetryVariableDescription) -> Nothing

Validate the local invariants of a variable descriptor.
"""
function _validate_variable_description(variable_desc::TelemetryVariableDescription)
    # Validate local descriptor invariants separately from dictionary-level alias conflicts.
    label = variable_desc.label

    label === :timestamp && throw(ArgumentError(
        "The variable label :timestamp is reserved."
    ))

    variable_desc.endianess in (:littleendian, :bigendian) || throw(ArgumentError(
        "Invalid endianness :$(variable_desc.endianess) for variable :$label; " *
        "expected :littleendian or :bigendian."
    ))

    variable_desc.default_view in _SUPPORTED_VARIABLE_VIEWS || throw(ArgumentError(
        "Unsupported default view :$(variable_desc.default_view) for variable :$label."
    ))

    _validate_variable_range(
        variable_desc.position,
        variable_desc.size,
        variable_desc.dependencies,
        label
    )
    return nothing
end

"""
    _validate_variable_range(position, size, dependencies, label) -> Nothing

Validate the frame-backed or derived-only position and size convention.
"""
function _validate_variable_range(position, size, dependencies, label::Symbol)
    # Reserve zero position and size exclusively for dependency-backed derived variables.
    if iszero(position) && iszero(size)
        if isnothing(dependencies) || isempty(dependencies)
            throw(ArgumentError(
                "Derived-only variable :$label must have at least one dependency."
            ))
        end
    elseif position <= 0 || size <= 0
        throw(ArgumentError(
            "Frame-backed variable :$label must have positive position and size; " *
            "derived-only variables must use position 0 and size 0."
        ))
    end

    return nothing
end

"""
    _get_variable_description(label, database, index) -> TelemetryVariableDescription

Resolve a canonical label or alias using an already validated ephemeral index.
"""
function _get_variable_description(
    label::Symbol,
    database::TelemetryDatabase,
    index::DatabaseIndex
)
    # Prefer canonical labels, then resolve aliases through the validated ephemeral index.
    canonical_label = if haskey(database.variables, label)
        label
    elseif haskey(index.aliases, label)
        index.aliases[label]
    else
        throw(KeyError(label))
    end

    return database.variables[canonical_label]
end
