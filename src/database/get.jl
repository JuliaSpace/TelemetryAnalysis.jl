# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions to get variables from the database.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export get_default_database, get_variable_description, search_variables
export @searchvar

"""
    get_default_database()

Get the default database. This function throws an error if it is not defined
yet.
"""
function get_default_database()
    !isassigned(_DEFAULT_TELEMETRY_DATABASE) &&
        error("The default telemetry database has not been assigned.")

    return _DEFAULT_TELEMETRY_DATABASE[]
end

"""
    get_variable_description(label::Symbol, database::TelemetryDatabase)

Get the description of a variable with `label` in `database`. Notice that
`label` can also be the variable alias. If the variable is not found, the
function returns `nothing`.
"""
function get_variable_description(label::Symbol, database::TelemetryDatabase)
    if haskey(database.variables, label)
        return database.variables[label]
    else
        for (k, v) in database.variables
            if v.alias == label
                return v
            end
        end
    end

    throw(KeyError(label))
end

"""
    search_variables(str::AbstractString[, database::TelemetryDatabase])

Search for variables registered in `database` in which their alias or
description contains `str`.

If `database` is not provided, the default one is used.
"""
function search_variables(str::AbstractString)
    return search_variables(str, get_default_database())
end

function search_variables(str::AbstractString, database::TelemetryDatabase)
    # Prepare the crayons to highlight the output if `stdout` supports it.
    hascolor = get(stdout, :color, false)
    cr = (hascolor ? string(crayon"reset")       : "")
    cy = (hascolor ? string(crayon"yellow bold") : "")
    cc = (hascolor ? string(crayon"cyan")        : "")

    # Vector to store the keys of the variables that matches the search pattern.
    varnames = Symbol[]

    # Search the variables.
    for (k, v) in database.variables
        alias_match = !isnothing(v.alias) && contains(String(v.alias), str)
        desc_match  = !isnothing(v.description) && contains(v.description, str)
        (alias_match || desc_match) && push!(varnames, k)
    end

    # Print the result.
    if !isempty(varnames)
        println("Variables found:")

        for v in varnames
            var = database.variables[v]
            alias = var.alias
            desc = var.description

            output_str = "    $cy$v$cr"

            if !isnothing(alias)
                output_str *= " ($cc$alias$cr)"
            end

            if !isnothing(desc) && !isempty(desc)
                output_str *= ": $desc"
            end

            println(output_str)
        end
    else
        println("No variable was found!")
    end

    return nothing
end

"""
    @searchvar(pattern)

Search variables in the default database in which their alias or description
contains `pattern`. `pattern` can be either a `Symbol` or an `AbstractString`.
"""
macro searchvar(pattern)
    if (pattern isa Symbol)
        str = "$pattern"
    elseif (pattern isa AbstractString)
        str = pattern
    else
        throw(ArgumentError("`pattern` must be a symbol or a string."))
    end

    return esc(quote
        search_variables($str)
    end)
end
