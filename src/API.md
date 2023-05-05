Application programming interface
=================================

This document describes the application programming interface (API) of
TelemetryAnalysis.jl

## Sources

A source must fetch telemetry and encapsulate it in a `Vector{TelemetryPacket}`.
It is defined using a structure with supertype `TelemetrySource`.

```julia
struct MyTelemetrySource <: TelemetrySource
    ...
end
```

It must implement two functions as follows.

```julia
function TelemetryAnalysis._api_init_telemetry_source(::Type{T}, vargs...; kwargs...)::T
```

This function initializes the source of type `T`. The arguments and keywords can
be selected arbitrarily depending on the source's characteristic. The function
must return an object of type `T`.

It is advisable to document the arguments and keywords by extending the
documentation of the object `init_telemetry_source`.

```julia
function TelemetryAnalysis._api_get_telemetry(source::T, start_time::DateTime, end_time::DateTime)::Vector{TelemetryPacket}
```

This function must fetch the telemetry from the source between `start_time` and
`end_time`. It must return encapsulate each packet in a `TelemetryPacket` and
return a `Vector{TelemetryPacket}`.

Some sources may also implement the simplified version of `_api_get_telemetry`
that fetches all the packets available:

```julia
function TelemetryAnalysis._api_get_telemetry(source::T)::Vector{TelemetryPacket}
```

### Registering the source for interactive use

If the user calls the function `init_telemetry_source()`, the system will
provide a list of registered sources for the user. However, this functionality
requires that the source defines the API function:

```julia
function _api_init_telemetry_source(::Type{T})
```

**without** any other argument or keyword. Hence, it must obtain the information
from the user interactively, or define it statically.

A source can be registered for interactive use by:

```julia
@register_interactive_source <Source structure>
```

## Databases

A database must define three information:

1. How to get the timestamp from the telemetry packet;
2. How to unpack the telemetry packet into raw data; and
3. The variables inside the telemetry packet.

The database object is created by the function:

```julia
create_telemetry_database(label::String; kwargs...)
```

where `label` defined the database label. The available keywords are:

- `get_telemetry_timestamp::Function`: A function that must return the timestamp
    of a telemetry packet. The API is:

    `get_telemetry_timestamp(tmpacket::TelemetryPacket)::Bool`

    (**Default** = `_default_get_telemetry_timestamp`)
- `unpack_telemetry::Function`: A function that must return a
    `AbstractVector{UInt8}` with the telemetry frame unpacked, which will be
    passed to the transfer functions. If the frame is not valid, it must return
    `nothing`. The function API must be:

    `unpack_telemetry(tmpacket::TelemetryPacket)::AbstractVector{UInt8}`

    (**Default** = `_default_unpack_telemetry`)

After creating the database, the variables can be added using the function:

```julia
add_variable!(database::TelemetryDatabase, label::Symbol, [position::Int, size::Int,] tf::Function; kwargs...)
```

- `database::TelemetryDatabase`: Database.
- `label::Symbol`: Variable label in the database.
- `position::Int`: Variable position in the telemetry database.
- `size::Int`: Size of the variable.
- `btf::Function`: Bit transfer function. For more information, see section
  [`Bit transfer function`](@ref).
- `tf::Function`: Variable transfer function. For more information, see section
    [`Transfer function`](@ref).

!!! note
    The `position` and `size` can be omitted if the variable is obtained only by
    the processed values of other variables. In this case, the keyword
    `dependencies` must not be `Nothing`.

This function allows the following keywords:

- `alias::Union{Nothing, Symbol}`: An alias of the variable. In this case, the
    function [`get_variable_description`](@ref) will also consider this alias
    when searching. (**Default** = `nothing`)
- `default_view::Symbol`: Select the default view for this variable during
    processing. For the list of available options, see
    [`process_telemetries`](@ref). (**Default** = `:processed`)
- `dependencies::Union{Nothing, Vector{Symbol}}`: A vector containing a list of
    dependencies required to obtain the processed value of this variable. If it
    is `nothing`, then the variable does not have dependencies.
    (**Default** = `nothing`)
- `description::String`: A description about the variable.
- `endianess::Symbol`: `:littleendian` or `:bigendian` to indicate the endianess
    of the variable. (**Default** = `:littleendian`)

### Bit transfer function

The bit transfer function must have the following signature:

```julia
function btf(frame::Vector{UInt8})::AbstractVector{UInt8}
```

Its purpose is to obtain the `frame` from the telemetry and process to the bits related to
the current telemetry variable. The `frame` is a set of bytes obtained from the variable
parameters `position`, `size`, and `endianess`.

### Raw transfer function

The purpose of the raw transfer function is to obtain the telemetry `byte_array` created
with the `btf` and process to a raw value. This value will be used in the transfer function
to obtain the variable processed data.

The raw transfer function can have one of the following signatures:

```julia
function rtf(byte_array::Vector{UInt8})
```

or

```julia
function rtf(byte_array::Vector{UInt8}, processed_variables::Dict{Symbol, Any})
```

### Transfer function

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
