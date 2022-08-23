# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions to get variables from the database.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export get_variable_description

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
