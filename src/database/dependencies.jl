## Description #############################################################################
#
# Functions to obtain the dependencies of each variable.
#
############################################################################################

# Obtain the topological sort of the dependency graph. Hence, we obtain a ordered list of
# variables that must be processed before processing the one with label `variable_label`.
function _dependency_topological_sort(variable_label::Symbol, database::TelemetryDatabase)
    sorted = Symbol[]
    visited = Symbol[]

    var_deps = get_variable_description(variable_label, database).dependencies

    isnothing(var_deps) && return nothing

    for var in var_deps
        _dependency_visit!(visited, sorted, var, database)
    end

    return sorted
end

# Auxiliary function to perform the topological sort.
function _dependency_visit!(
    visited::Vector{Symbol},
    sorted::Vector{Symbol},
    variable_label::Symbol,
    database::TelemetryDatabase
)
    if variable_label ∉ visited
        push!(visited, variable_label)

        var_deps = get_variable_description(variable_label, database).dependencies

        if !isnothing(var_deps)
            for var in var_deps
                _dependency_visit!(visited, sorted, var, database)
            end
        end

        push!(sorted, variable_label)
    else
        if variable_label ∉ sorted
            error("Cyclic dependency found (variable $variable_label).")
        end
    end

    return nothing
end
