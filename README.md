# TelemetryAnalysis.jl

This package defines an API to fetch and process telemetry packets from satellites.

Notice that this package does not provide a complete set of functionalities by itself. The
user must add other packages that use the API defined here to implement the required
functions.

## Application Programming Interface (API)

This section defines the API of **TelemetryAnalysis.jl**.

## Sources

A source must fetch telemetry and encapsulate it in a `Vector{TelemetryPacket}`. It is
defined using a structure with supertype `TelemetrySource`.

```julia
struct MyTelemetrySource <: TelemetrySource
    ...
end
```

It must implement two functions as follows.

```julia
function TelemetryAnalysis._api_init_telemetry_source(
    ::Type{T},
    vargs...;
    kwargs...,
) where T <: TelemetrySource
```

This function initializes the source of type `T`. The arguments and keywords can be selected
arbitrarily depending on the source's characteristics. It must return an object of type `T`
after successful initialization, or `nothing` when initialization is not completed.

It is advisable to document the arguments and keywords by extending the documentation of the
object `init_telemetry_source`.

```julia
function TelemetryAnalysis._api_get_telemetry(
    source::T,
    start_time::DateTime,
    end_time::DateTime,
)::Vector{TelemetryPacket{T}} where T <: TelemetrySource
```

This function must fetch the telemetry from the source between `start_time` and `end_time`.
It must encapsulate each packet in a `TelemetryPacket` and return a
`Vector{TelemetryPacket{T}}`.

Some sources may also implement the simplified version of `_api_get_telemetry` that fetches
all the packets available:

```julia
function TelemetryAnalysis._api_get_telemetry(
    source::T,
)::Vector{TelemetryPacket{T}} where T <: TelemetrySource
```

### Registering the source for interactive use

If the user calls the function `init_telemetry_source()`, the system will provide a list of
registered sources for the user. However, this functionality requires that the source
defines the API function:

```julia
function TelemetryAnalysis._api_init_telemetry_source(
    ::Type{T},
) where T <: TelemetrySource
```

**without** any other argument or keyword. Hence, it must obtain the information from the
user interactively, or define it statically.

A source can be registered for interactive use by:

```julia
@register_interactive_source <Source structure>
```

## Databases

A database must define three pieces of information:

1. How to get the timestamp from the telemetry packet;
2. How to unpack the telemetry packet into raw data; and
3. The variables inside the telemetry packet.

The database object is created by the function:

```julia
create_telemetry_database(label::String; kwargs...)
```

where `label` defines the database label. The available keywords are:

- `get_telemetry_timestamp::Function`: A function that must return the timestamp of a
  telemetry packet. The API is:

    `get_telemetry_timestamp(tmpacket::TelemetryPacket)::DateTime`

    (**Default** = `_default_get_telemetry_timestamp`)
- `unpack_telemetry::Function`: A function that must return an `AbstractVector{UInt8}` with
  the telemetry frame unpacked, which will be passed to the transfer functions. If the frame
  is not valid, it must return `nothing`. The function API must be:

    `unpack_telemetry(tmpacket::TelemetryPacket)::AbstractVector{UInt8}`

    (**Default** = `_default_unpack_telemetry`)

After creating the database, frame-backed variables can be added using:

```julia
add_variable!(
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
    endianess::Symbol = :littleendian,
)
```

Derived-only variables use the overload with required dependencies:

```julia
add_variable!(
    database::TelemetryDatabase,
    label::Symbol,
    tf::Function;
    alias::Union{Nothing, Symbol} = nothing,
    default_view::Symbol = :processed,
    dependencies::Vector{Symbol},
    description::String = "",
    endianess::Symbol = :littleendian,
)
```

- `database::TelemetryDatabase`: Database.
- `label::Symbol`: Variable label in the database.
- `position::Integer`: Variable position in the telemetry database.
- `size::Integer`: Size of the variable.
- `tf::Function`: Variable transfer function. For more information, see section
  [`Transfer function`](@ref).
- `btf::Function`: Bit transfer function. For more information, see section
  [`Bit transfer function`](@ref).
- `rtf::Function`: Raw transfer function. For more information, see section
  [`Raw transfer function`](@ref).

!!! note
    The `position` and `size` can be omitted if the variable is obtained only by the
    processed values of other variables. In this case, the keyword `dependencies` must not
    be `nothing` and must contain at least one dependency.

This function allows the following keywords:

- `alias::Union{Nothing, Symbol}`: An alias of the variable. In this case, the function
  [`get_variable_description`](@ref) will also consider this alias when searching.
  (**Default** = `nothing`)
- `default_view::Symbol`: Select the default view for this variable during processing. For
  the list of available options, see [`process_telemetry_packets`](@ref).
  (**Default** = `:processed`)
- `dependencies::Union{Nothing, Vector{Symbol}}`: A vector containing a list of dependencies
  required to obtain the processed value of this variable. If it is `nothing`, then the
  variable does not have dependencies. It is required as a nonempty `Vector{Symbol}` for a
  derived-only variable. (**Default for frame-backed variables** = `nothing`)
- `description::String`: A description of the variable. (**Default** = `""`)
- `endianess::Symbol`: `:littleendian` or `:bigendian` to indicate the endianness of the
  variable. (**Default** = `:littleendian`)

### Bit transfer function

The bit transfer function must have the following signature:

```julia
function btf(frame::AbstractVector{UInt8})::AbstractVector{UInt8}
```

Its purpose is to obtain the `frame` from the telemetry and extract the bits related to the
current telemetry variable. The `frame` is a set of bytes obtained from the variable
parameters `position`, `size`, and `endianess`. Callback byte views are ephemeral and
read-only; callbacks must not mutate or retain them.

### Raw transfer function

The purpose of the raw transfer function is to obtain the telemetry `byte_array` created
with the `btf` and process it into a raw value. This value will be used in the transfer
function to obtain the processed variable data.

The raw transfer function can have one of the following signatures:

```julia
function rtf(byte_array::AbstractVector{UInt8})
```

or

```julia
function rtf(byte_array::AbstractVector{UInt8}, processed_variables::Dict{Symbol, Any})
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
signature must be used if the transfer function depends on other variables.

Callbacks may consume only dependencies declared by the current variable. The
`processed_variables` context uses canonical variable labels as keys. Ordering among
unrelated callbacks is not guaranteed, and each required byte, raw, and processed stage
executes at most once per successfully processed packet.

## Packet metadata migration

`TelemetryPacket` metadata now defaults to `nothing`, avoiding an empty dictionary
allocation for every packet:

```julia
packet = TelemetryPacket{MyTelemetrySource}(
    timestamp = now(),
    data = UInt8[0x01],
)
@assert packet.metadata === nothing
```

Callers that require mutation by indexing must provide storage explicitly:

```julia
packet = TelemetryPacket{MyTelemetrySource}(
    timestamp = now(),
    data = UInt8[0x01],
    metadata = Dict{String, Any}(),
)
packet.metadata["station"] = "ground-1"
```

`hasmetadata(packet)` is true only for a nonempty metadata dictionary.
`getmetadata(packet, key, default)` returns `default` for missing metadata or keys and
never attaches storage. `with_metadata(packet, metadata)` creates a new packet, copies the
supplied metadata into a `Dict{String, Any}`, and shares the original packet's data vector.

## Processing and persistence contracts

Explicit variable selections preserve request order. Processing all variables uses lexical
canonical-label order. Concrete output-name collisions are rejected before processing, and a
`:byte_array` output is an owned `Vector{UInt8}`. Packets whose unpack callback returns
`nothing` are omitted. Output rows are sorted by timestamp; equal timestamps preserve the
original input order.

Quantity intervals passed to `get_telemetry` are converted exactly to milliseconds. They
must be finite, nonnegative, within `Int64`, and represent a whole number of milliseconds;
values are never rounded or accepted using a tolerance.

Telemetry files use Julia `Serialization` inside gzip and must be treated as trusted input.
Serialization is Julia-minor- and type-layout-dependent, so files are not promised to work
across Julia minors or structural package changes. In particular, old package versions need
not read packets written with the new metadata layout. Loads propagate deserialization and
validation failures without changing defaults. Saves finalize a temporary file in the
destination directory and then atomically replace the destination; a failed save preserves
an existing destination.
