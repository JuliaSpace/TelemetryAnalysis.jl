# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to IO.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export get_user_option

"""
    get_user_option(text::String, options::AbstractVector)

Get the user option. `text` is the information shown to the user and `options`
is a vector with the options. This function returns the selection index w.r.t.
`options`, or -1 if the user did not select an option.
"""
function get_user_option(text::String, options::AbstractVector)
    hascolor = get(stdout, :color, false)
    cr = (hascolor ? string(crayon"reset")       : "")
    cy = (hascolor ? string(crayon"yellow bold") : "")
    return request(cy * text * cr, RadioMenu(options, pagesize = 5))
end

#                                  Julia API
# ==============================================================================

# TelemetryPacket
# ==============================================================================

function show(io::IO, tmpacket::TelemetryPacket{T}) where T <: TelemetrySource
    num_bytes = length(tmpacket.raw)
    print(io, "TelemetryPacket {$T} (Timestamp = $(tmpacket.timestamp), $(num_bytes) bytes)")
    return nothing
end

function show(
    io::IO,
    ::MIME"text/plain",
    tmpacket::TelemetryPacket{T}
) where T<:TelemetrySource
    # Colors.
    hascolor = get(io, :color, false)
    cr = (hascolor ? string(crayon"reset")       : "")
    cy = (hascolor ? string(crayon"yellow bold") : "")
    cb = (hascolor ? string(crayon"blue bold")   : "")

    num_bytes = length(tmpacket.raw)
    println(io, "TelemetryPacket{$T}:")
    println(io, cy * "    Timestamp" * cr * " : " * string(tmpacket.timestamp))
    print(  io, cy * "     Raw data" * cr * " : " * string(num_bytes) * " bytes")
    aux =       cy * "     Metadata" * cr * " : "

    if !isempty(tmpacket.metadata)
        keys_str   = tmpacket.metadata |> keys |> collect
        field_size = maximum(textwidth.(keys_str))

        for (k, v) in tmpacket.metadata
            println(io)
            padding = field_size - textwidth(k)
            print(io, aux * cb * string(k) * cr * " "^padding * " => " * string(v))
            aux = "                "
        end
    end

    return nothing
end

# TelemetryDatabase
# ==============================================================================

function show(io::IO, db::TelemetryDatabase)
    num_variables = length(db.variables)
    print(io, "TelemetryDatabase: $(db.label) ($num_variables variables)")
    return nothing
end

function show(io::IO, ::MIME"text/plain", db::TelemetryDatabase)
    # Colors.
    hascolor = get(io, :color, false)
    cr = (hascolor ? string(crayon"reset")       : "")
    cy = (hascolor ? string(crayon"yellow bold") : "")
    cc = (hascolor ? string(crayon"cyan")        : "")

    num_variables = length(db.variables)
    println(io, "TelemetryDatabase:")
    println(io, cy * "                        Label" * cr * " : " * db.label)
    println(io, cy * "          Number of variables" * cr * " : " * string(num_variables))
    println(io, cy * "       Get timestamp function" * cr * " : " * cc * string(db.get_telemetry_timestamp))
    print(  io, cy * "    Unpack telemetry function" * cr * " : " * cc * string(db.unpack_telemetry))

    return nothing
end

# TelemetryVariableDescription
# ==============================================================================

function show(io::IO, var::TelemetryVariableDescription)
    print(io, "TelemetryVariableDescription: $(var.label)")
    isnothing(var.alias) || print(io, " ($(var.alias))")
    return nothing
end

function show(io::IO, ::MIME"text/plain", var::TelemetryVariableDescription)
    # Colors.
    hascolor = get(io, :color, false)
    cr = (hascolor ? string(crayon"reset")       : "")
    cy = (hascolor ? string(crayon"yellow bold") : "")
    cc = (hascolor ? string(crayon"cyan")        : "")

    alias_str = !isnothing(var.alias) ? " ($(var.alias))" : ""
    endianess_str = var.endianess == :bigendian ? "Big endian" : "Little endian"

    println(io, "TelemetryVariableDescription:")
    println(io, cy * "                Label" * cr * " : " * string(var.label) * alias_str)
    println(io, cy * "          Description" * cr * " : " * var.description)
    println(io, cy * "            Endianess" * cr * " : " * endianess_str)
    println(io, cy * "             Position" * cr * " : " * string(var.position))
    println(io, cy * "                 Size" * cr * " : " * string(var.size) * " bytes")
    print(  io, cy * "    Transfer function" * cr * " : " * cc * string(var.tf))

    return nothing
end
