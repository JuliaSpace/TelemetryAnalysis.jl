# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==========================================================================================
#
#   Functions to process variables in the database.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export process_telemetry_packets

"""
    process_telemetry_packets([tmpackets::Vector{TelemetryPacket{T}}]; database::TelemetryDatabase, kwargs...) where T <: TelemetrySource -> DateFrame

Process the telemetry packets `tmpackets` using the `database`, returning the processed
values of **all** registered telemetries. If `tmpackets` are not passed, the default
telemetry packets will be used.

    process_telemetry_packets([tmpackets::Vector{TelemetryPacket{T}},] telemetries::AbstractVector; database::TelemetryDatabase, kwargs...) where T <: TelemetrySource -> DataFrame

Process the telemetry packets `tmpackets` using the `database`. The elements in
`telemetries` can be a `Symbol` with the telemetry label or a `Pair{Symbol, Symbol}`. In the
former, the default view will be used. In the latter, the variable view will be as specified
by the second symbol in the pair.  For more information, see the section below.

If `tmpackets` are not passed, the default telemetry packets will be used.

    process_telemetry_packets([tmpackets::Vector{TelemetryPacket{T}},] telemetries::Vector{Pair{Symbol, Symbol}}; database::TelemetryDatabase, kwargs...) where T <: TelemetrySource -> DataFrame

Process the telemetry packets `tmpackets` using the `database`. The output variables are
indicated in `telemetries`. It must be a vector of pairs indicating the telemetry and how
the value is written to the output. For example, `:C001 => :raw` adds the raw value of
telemetry `C001`, whereas `:C001 => :processed` adds the processed value of the same
variable.

The acceptable values for the output format are:

- `:byte_array`: `Vector{UInt8}` with the telemetry byte array.
- `:byte_array_bin`: String with the raw value represented in binary.
- `:byte_array_hex`: String with the raw value represented in hexadecimal.
- `:processed`: Processed value obtained from the transfer function.
- `:raw`: Telemetry raw value.

If `tmpackets` are not passed, the default telemetry packets will be used.

!!! info
    If the keyword argument `database` is not passed, the default database is used.

# Keywords

- `show_progress::Bool`: If `true`, a progress bar is shown while processing the
    telemetries. (**Default** = `true`)

# Return

- `DataFrame`: A `DataFrame` in which the columns are the selected values. The column names
    are the variable labels.
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
    return process_telemetry_packets(
        tmpackets,
        keys(database.variables) |> collect;
        database,
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
    return process_telemetry_packets(
        tmpackets,
        [
            begin
                if t isa Pair{Symbol, Symbol}
                    t
                else
                    t => get_variable_description(t, database).default_view
                end
            end
            for t in telemetries
        ];
        database,
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
    # Assembles the columns given the user selections.
    cols = [
        (
            if last(t) ∈ (:byte_array, :byte_array_bin, :byte_array_hex)
                Symbol(string(first(t)) * "_byte_array")
            elseif last(t) === :raw
                Symbol(string(first(t)) * "_raw")
            else
                first(t)
            end
        ) => Any[]
        for t in telemetries
    ]

    output = DataFrame(:timestamp => DateTime[], cols...)

    # Check if the database supports the current telemetry source.
    if !applicable(database.unpack_telemetry, tmpackets |> first)
        error("The selected database does not support telemetries from $(T).")
    end

    # Re-entrant lock for operations that must not be executed concurrently.
    thread_lock = ReentrantLock()

    # Progress meter.
    progress = Progress(length(tmpackets); color = :reset, enabled = show_progress)

    Threads.@threads for tmpacket in tmpackets
        # Unpack the telemetry frame.
        unpacked_frame = database.unpack_telemetry(tmpacket)
        unpacked_frame === nothing && continue

        # Ask for the packet timestamp.
        timestamp = database.get_telemetry_timestamp(tmpacket)

        processed_variables = Dict{Symbol, Any}()

        output_dict = Dict{Symbol, Any}(:timestamp => timestamp)

        for (variable_label, type) in telemetries
            variable_desc = get_variable_description(variable_label, database)

            # Obtain the telemetry frame using the following information:
            #   - Position;
            #   - Size; and
            #   - Endianess.
            var_frame = _get_variable_telemetry_frame(unpacked_frame, variable_desc)

            # Convert the telemetry frame to the byte array.
            byte_array = variable_desc.btf(var_frame)

            if type == :byte_array
                output_dict[Symbol(string(variable_label) * "_byte_array")] = byte_array

            elseif type == :byte_array_bin
                output_dict[Symbol(string(variable_label) * "_byte_array")] =
                    byte_array |> byte_array_to_binary

            elseif type == :byte_array_hex
                output_dict[Symbol(string(variable_label) * "_byte_array")] =
                    byte_array |> byte_array_to_hex

            else
                # We need to process all the dependencies first before computing the
                # processed value.
                #
                # First, we check if we already computed the dependencies for this variable
                # in the database. If not, we perform a topological sort to obtain the
                # process order.
                if !haskey(database._variable_dependencies, variable_label)
                    deps = _dependency_topological_sort(variable_label, database)
                    lock(thread_lock)
                    database._variable_dependencies[variable_label] = deps
                    unlock(thread_lock)
                else
                    deps = database._variable_dependencies[variable_label]
                end

                if !isnothing(deps)
                    for var in deps
                        if !haskey(processed_variables, var)
                            dep_var_desc = get_variable_description(var, database)

                            # Obtain the telemetry frame using the following information:
                            #   - Position;
                            #   - Size; and
                            #   - Endianess.
                            dep_var_frame = _get_variable_telemetry_frame(
                                unpacked_frame,
                                dep_var_desc
                            )

                            # Convert the telemetry frame to the byte array.
                            dep_byte_array = dep_var_desc.btf(dep_var_frame)

                            # Convert the byte array to the raw value.
                            dep_raw_value =  _raw_telemetry_variable(
                                processed_variables,
                                dep_byte_array,
                                dep_var_desc
                            )

                            # Obtain the variable processed value.
                            dep_processed_value = _process_telemetry_variable(
                                processed_variables,
                                dep_raw_value,
                                dep_var_desc
                            )

                            # Add in the dictionary.
                            processed_variables[var] = (;
                                raw = dep_raw_value,
                                processed = dep_processed_value
                            )
                        end
                    end
                end

                # Convert the byte array to the raw value.
                raw_value =  _raw_telemetry_variable(
                    processed_variables,
                    byte_array,
                    variable_desc
                )

                if type == :raw
                    output_dict[Symbol(string(variable_label) * "_raw")] = raw_value

                else

                    # Obtain the variable processed value.
                    processed_value = _process_telemetry_variable(
                        processed_variables,
                        raw_value,
                        variable_desc
                    )

                    processed_variables[variable_label] = (;
                        raw = raw_value,
                        processed = processed_value
                    )

                    output_dict[variable_label] = processed_value
                end
            end
        end

        next!(progress)
        lock(thread_lock)
        push!(output, output_dict)
        unlock(thread_lock)
    end

    finish!(progress)

    @info "$(nrow(output)) packets out of $(length(tmpackets)) were processed correctly."

    # Sort the DataFrame using the timestamp and convert the columns to improve analysis
    # performance.
    sort!(output, :timestamp)

    return identity.(output)
end

############################################################################################
#                                    Private Functions
############################################################################################

function _get_variable_telemetry_frame(
    unpacked_frame::AbstractVector{UInt8},
    variable_desc::TelemetryVariableDescription
)
    # Get the telemetry frame for the variable.
    initial_byte = variable_desc.position
    end_byte     = initial_byte + (variable_desc.size - 1)
    var_frame    = @view unpacked_frame[initial_byte:end_byte]

    if variable_desc.endianess == :bigendian
        return reverse(var_frame)
    else
        return var_frame
    end
end

# Compute the processed value of a telemetry variable.
function _process_telemetry_variable(
    processed_variables::Dict{Symbol, Any},
    raw::Any,
    variable_desc::TelemetryVariableDescription
)
    # Check which method signature must be called to processed the value.
    if applicable(variable_desc.tf, raw, processed_variables)
        processed_value = variable_desc.tf(raw, processed_variables)
    else
        processed_value = variable_desc.tf(raw)
    end

    return processed_value
end

# Compute the raw value of a telemetry variable.
function _raw_telemetry_variable(
    processed_variables::Dict{Symbol, Any},
    byte_array::Vector{UInt8},
    variable_desc::TelemetryVariableDescription
)
    # Check which method signature must be called to obtain the telemetry variable raw
    # value.
    if applicable(variable_desc.rtf, byte_array, processed_variables)
        raw_value = variable_desc.rtf(byte_array, processed_variables)
    else
        raw_value = variable_desc.rtf(byte_array)
    end

    return raw_value
end
