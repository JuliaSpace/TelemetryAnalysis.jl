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
    get_variable_description(label::Symbol, database::TelemetryDatabase) -> TelemetryVariableDescription

Get the description of a variable with `label` in `database`. Notice that `label` can also
be the variable alias. If the variable is not found, the function returns `nothing`.
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
