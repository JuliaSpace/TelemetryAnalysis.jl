# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions to process variables in the database.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export process_telemetries

"""
    process_telemetries(tmpackets::Vector{TelemetryPacket{T}}, database::TelemetryDatabase) where T <: TelemetrySource

Process the telemetry packets `tmpackets` using the `database`, returning the
processed values of **all** registered telemetries.

    process_telemetries(tmpackets::Vector{TelemetryPacket{T}}, database::TelemetryDatabase, telemetries::AbstractVector{Symbol}) where T <: TelemetrySource

Process the telemetry packets `tmpackets` using the `database`, converting the
processed values in `telemetries`.

    process_telemetries(tmpackets::Vector{TelemetryPacket{T}}, database::TelemetryDatabase, telemetries::Vector{Pair{Symbol, Symbol}}) where T <: TelemetrySource

Process the telemetry packets `tmpackets` using the `database`. The output
variables are indicated in `telemetries`. It must be a vector of pairs
indicating the telemetry and how the value is written to the output. For
example, `:C001 => :raw` adds the raw value of telemetry `C001`, whereas
`:C001 => :processed` adds the processed value of the same variable.

The acceptable values for the output format are:

- `:processed`: Processed value obtained by the transfer function.
- `:raw`: A `Vector{UInt8}` with the raw value.
- `:raw_hex`: A string with the raw value represented in hexadecimal.
- `:raw_bin`: A string with the raw value represented in binary.

# Return

This function returns a `DataFrame` in which the columns are the selected
values. The column names are the variable labels. If the raw value a variable
must be added, the column will be named `<variable_name>_raw`.
"""
function process_telemetries(
    tmpackets::Vector{TelemetryPacket{T}},
    database::TelemetryDatabase
) where T <: TelemetrySource
    return process_telemetries(
        tmpackets,
        database,
        keys(database.variables) |> collect
    )
end

function process_telemetries(
    tmpackets::Vector{TelemetryPacket{T}},
    database::TelemetryDatabase,
    telemetries::AbstractVector{Symbol}
) where T <: TelemetrySource
    return process_telemetries(
        tmpackets,
        database,
        [t => :processed for t in telemetries]
    )
end

function process_telemetries(
    tmpackets::Vector{TelemetryPacket{T}},
    database::TelemetryDatabase,
    telemetries::Vector{Pair{Symbol, Symbol}}
) where T <: TelemetrySource
    # Assembles the columns given the user selections.
    cols = [
        (
            last(t) ∈ (:raw, :raw_hex, :raw_bin) ?
                Symbol(string(first(t)) * "_raw") :
                first(t)
        ) => Any[]
        for t in telemetries
    ]

    output = DataFrame(:timestamp => DateTime[], cols...)

    # Check if the database supports the current telemetry source.
    if !applicable(database.unpack_telemetry, tmpackets |> first)
        error("The selected database does not support telemetries from $(T).")
    end

    for tmpacket in tmpackets
        # Unpack the telemetry frame.
        unpacked_frame = database.unpack_telemetry(tmpacket)
        unpacked_frame === nothing && continue

        # Ask for the packet timestamp.
        timestamp = database.get_telemetry_timestamp(tmpacket)

        processed_variables = Dict{Symbol, Any}()

        output_dict = Dict{Symbol, Any}(
            :timestamp => timestamp
        )

        for (variable_label, type) in telemetries
            variable_desc = database.variables[variable_label]

            raw_value = _get_variable_raw_telemetry(
                unpacked_frame,
                variable_desc
            )

            if type == :raw
                output_dict[Symbol(string(variable_label) * "_raw")] = raw_value
            elseif type == :raw_hex
                output_dict[Symbol(string(variable_label) * "_raw")] =
                    raw_value |> _raw_to_hex
            elseif type == :raw_bin
                output_dict[Symbol(string(variable_label) * "_raw")] =
                    raw_value |> _raw_to_binary
            else

                # We need to process all the dependencies first before computing
                # the processed value.
                deps = _dependency_topological_sort(variable_label, database)

                for var in deps
                    if !haskey(processed_variables, var)
                        dep_var_desc = get_variable_description(var, database)

                        dep_raw_value = _get_variable_raw_telemetry(
                            unpacked_frame,
                            dep_var_desc
                        )

                        dep_processed_value = _process_telemetry_variable(
                            processed_variables,
                            dep_raw_value,
                            dep_var_desc
                        )

                        processed_variables[var] = dep_processed_value
                    end
                end

                processed_value = _process_telemetry_variable(
                    processed_variables,
                    raw_value,
                    variable_desc
                )

                processed_variables[variable_label] = processed_value
                output_dict[variable_label] = processed_value
            end
        end

        push!(output, output_dict)
    end

    @info "$(nrow(output)) packets out of $(length(tmpackets)) were processed correctly."

    # Sort the dataframe using the timestamp and convert the columns to improve
    # analysis performance.
    sort!(output, :timestamp)

    return identity.(output)
end

#                                   Private
# ==============================================================================

function _get_variable_raw_telemetry(
    unpacked_frame::AbstractVector{UInt8},
    variable_desc::TelemetryVariableDescription
)
    # Get the raw value from the telemetry frames.
    initial_byte = variable_desc.position
    end_byte     = initial_byte + (variable_desc.size - 1)
    raw          = @view unpacked_frame[initial_byte:end_byte]

    if variable_desc.endianess == :bigendian
        return reverse(raw)
    else
        return raw
    end
end

# Compute the processed value of a telemetry variable.
function _process_telemetry_variable(
    processed_variables::Dict{Symbol, Any},
    unpacked_frame::AbstractVector{UInt8},
    variable_desc::TelemetryVariableDescription
)
    # Check which method signature must be called to processed the value.
    if applicable(variable_desc.tf, unpacked_frame, processed_variables)
        processed_value = variable_desc.tf(unpacked_frame, processed_variables)
    else
        processed_value = variable_desc.tf(unpacked_frame)
    end

    return processed_value
end
