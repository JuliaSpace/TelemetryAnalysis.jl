## Description #############################################################################
#
# Functions related to the creation of databases.
#
############################################################################################

export create_telemetry_database
export add_variable!
export set_default_telemetry_database!

"""
    create_telemetry_database(label::String; kwargs...) -> TelemetryDatabase

Create a telemetry database with `label`.

# Keywords

- `get_telemetry_timestamp::Function`: A function that must return the timestamp of a
    telemetry packet. The API is:

    `get_telemetry_timestamp(tmpacket::TelemetryPacket)::DateTime`

    (**Default** = `_default_get_telemetry_timestamp`)
- `unpack_telemetry::Function`: A function that must return a `AbstractVector{UInt8}` with
    the telemetry frame unpacked, which will be passed to the transfer functions. If the
    frame is not valid, it must return `nothing`. The function API must be:

    `unpack_telemetry(tmpacket::TelemetryPacket)::AbstractVector{UInt8}`

    (**Default** = `_default_unpack_telemetry`)
"""
function create_telemetry_database(
    label::String;
    get_telemetry_timestamp::Function = _default_get_telemetry_timestamp,
    unpack_telemetry::Function = _default_unpack_telemetry,
)
    database = TelemetryDatabase(;
        label                   = label,
        get_telemetry_timestamp = get_telemetry_timestamp,
        unpack_telemetry        = unpack_telemetry,
    )

    set_default_telemetry_database!(database)

    return database
end

"""
    add_variable!(database::TelemetryDatabase, label::Symbol, position::Integer, size::Integer, tf::Function, btf::Function = default_bit_transfer_function, rtf::Function = default_raw_transfer_function; kwargs...) -> Nohting

Add a variable to the `database`.

# Args

- `database::TelemetryDatabase`: Database.
- `label::Symbol`: Variable label in the database.
- `position::Int`: Variable position in the telemetry database.
- `size::Int`: Size of the variable.
- `tf::Function`: Variable transfer function. For more information, see section `Transfer
    function`.
- `btf::Function`: The bit transfer function for the variable.
    (**Default** = `default_bit_transfer_function`)
- `rtf::Function`: The raw transfer function for the variable.
    (**Default** = `default_raw_transfer_function`)

!!! note
    The `position` and `size` can be omitted if the variable is obtained only by the
    processed values of other variables. In this case, the keyword `dependencies` must not
    be `Nothing`.

# Keywords

- `alias::Union{Nothing, Symbol}`: An alias of the variable. In this case, the function
    [`get_variable_description`](@ref) will also consider this alias when searching.
    (**Default** = `nothing`)
- `default_view::Symbol`: Select the default view for this variable during processing. For
    the list of available options, see [`process_telemetries`](@ref).
    (**Default** = `:processed`)
- `dependencies::Union{Nothing, Vector{Symbol}}`: A vector containing a list of dependencies
    required to obtain the processed value of this variable. If it is `nothing`, then the
    variable does not have dependencies. (**Default** = `nothing`)
- `description::String`: A description about the variable.
- `endianess::Symbol`: `:littleendian` or `:bigendian` to indicate the endianess of the
    variable. (**Default** = `:littleendian`)

# Bit transfer function

The bit transfer function must have the following signature:

```julia
function btf(frame::AbstractVector{UInt8})::AbstractVector{UInt8}
```

Its purpose is to obtain the `frame` from the telemetry and process to the bits related to
the current telemetry variable. The `frame` is a set of bytes obtained from the variable
parameters `position`, `size`, and `endianess`.

# Raw transfer function

The purpose of the raw transfer function is to obtain the telemetry `byte_array` created
with the `btf` and process to a raw value. This value will be used in the transfer function
to obtain the variable processed data.

The raw transfer function can have one of the following signatures:

```julia
function rtf(byte_array::AbstractVector{UInt8})
```

or

```julia
function rtf(byte_array::AbstractVector{UInt8}, processed_variables::Dict{Symbol, Any})
```

# Transfer function

The variable transfer function can have one of the following signatures:

```julia
function tf(raw::Any)
```

Return the processed value of the variable given the `raw` information, obtained from the
raw transfer function.

```julia
function tf(raw::Any, processed_variables::Dict{Symbol, Any})
```

Return the processed value of the variable given the `raw` information, obtained from the
raw transfer function, and the set of processed variables in `processed_variables`. This
signature must be used if the transfer function depends on others variables.
"""
function add_variable!(
    database::TelemetryDatabase,
    label::Symbol,
    position::Integer,
    size::Integer,
    tf::Function,
    btf::Function = default_bit_transfer_function,
    rtf::Function = default_raw_transfer_function;
    alias::Union{Nothing, Symbol} = nothing,
    default_view::Symbol = :processed,
    dependencies::Union{Nothing, Vector{Symbol}} = nothing,
    description::String = "",
    endianess::Symbol = :littleendian
)
    label == :timestamp && error("A variable cannot have the label `:timestamp`.")

    if isempty(description)
        description = "Variable $label"
    end

    database.variables[label] = TelemetryVariableDescription(
        alias,
        default_view,
        dependencies,
        rstrip(description, '\n'),
        endianess,
        label,
        position,
        size,
        tf,
        btf,
        rtf
    )
    return nothing
end

function add_variable!(
    database::TelemetryDatabase,
    label::Symbol,
    tf::Function;
    alias::Union{Nothing, Symbol} = nothing,
    default_view::Symbol = :processed,
    dependencies::Vector{Symbol},
    description::String = "",
    endianess::Symbol = :littleendian
)
    label == :timestamp && error("A variable cannot have the label `:timestamp`.")

    if isempty(dependencies)
        error("A derived variable must have dependencies.")
    end

    if isempty(description)
        description = "Variable $label"
    end

    return add_variable!(
        database,
        label,
        0,
        0,
        tf;
        alias,
        default_view,
        dependencies,
        description,
        endianess
    )
end

function add_variable!(database::TelemetryDatabase, tvd::TelemetryVariableDescription)
    add_variable!(
        database,
        tvd.label,
        tvd.position,
        tvd.size,
        tvd.tf,
        tvd.btf,
        tvd.rtf;
        alias = tvd.alias,
        default_view = tvd.default_view,
        dependencies = tvd.dependencies,
        description = tvd.description,
        endianess = tvd.endianess
    )
    return nothing
end

"""
    set_default_telemetry_database!(database::TelemetryDatabase) -> Nothing

Set the default telemetry database to `database`.
"""
function set_default_telemetry_database!(database::TelemetryDatabase)
    _DEFAULT_TELEMETRY_DATABASE[] = database
    return nothing
end

############################################################################################
#                                    Private Functions
############################################################################################

function _default_unpack_telemetry(tmpacket::TelemetryPacket{T}) where T<:TelemetrySource
    return true
end

function _default_get_telemetry_timestamp(tmpacket::TelemetryPacket{T}) where T<:TelemetrySource
    return tmpacket.timestamp
end
