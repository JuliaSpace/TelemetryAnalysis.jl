Application programming interface
=================================

This document describes the application programming interface (API) of
TelemetryAnalysis.jl

## Sources

A source must fetch telemetry and encapsulate it in a `Vector{TelemetryPacket}`.
It is defined using a structure with supertype `TelemetrySource`.

```
struct MyTelemetrySource <: TelemetrySource
    ...
end
```

It must implement two functions as follows.

```
function TelemetryAnalysis._api_init_telemetry_source(::Type{T}, vargs...; kwargs...)::T
```

This function initializes the source of type `T`. The arguments and keywords can
be selected arbitrary depending on the source's characteristic. The function
must return an object of type `T`.

It is advisable to document the arguments and keywords by extending the
documentation of the object `init_telemetry_source`.

```
function TelemetryAnalysis._api_get_telemetry(source::T, start_time::DateTime, end_time::DateTime)::Vector{TelemetryPacket}
```

This function must fetch the telemetry from the source between `start_time` and
`end_time`. It must return encapsulate each packet in a `TelemetryPacket` and
return a `Vector{TelemetryPacket}`.

### Registering the source for interactive use

If the user calls the function `init_telemetry_source()`, the system will
provide a list of registered sources for the user. However, this functionality
requires that the source defines the API function:

```
function _api_init_telemetry_source(::Type{T})
```

**without** any other argument or keyword. Hence, it must obtain the information
from the user interactively, or define it statically.

A source can be registered for interactive use by:

```
@register_interactive_source <Source structure>
```
