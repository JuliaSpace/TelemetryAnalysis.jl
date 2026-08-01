TelemetryAnalysis.jl Changelog
==============================

Version 3.0.1
-------------

- ![Info][badge-info] The package now uses JuliaFormatter with a committed configuration,
  and the entire codebase was formatted accordingly.
- ![Info][badge-info] We fixed some docstrings.
- ![Info][badge-info] We added instructions for coding agents (AGENTS.md and CLAUDE.md).

Version 3.0.0
-------------

- ![BREAKING][badge-breaking] `TelemetryPacket.metadata` now defaults to `nothing` instead
  of an empty dictionary. Callers that require mutable metadata must pass a
  `Dict{String, Any}` explicitly.
- ![BREAKING][badge-breaking] SIMD.jl is no longer a dependency and is no longer
  re-exported.
- ![BREAKING][badge-breaking] The misspelled `endianess` field and keyword were renamed to
  `endianness` in `TelemetryVariableDescription` and `add_variable!`.
- ![Feature][badge-feature] We added the metadata helpers `hasmetadata`, `getmetadata`, and
  `with_metadata`.
- ![Enhancement][badge-enhancement] `byte_array_to_binary` and `byte_array_to_hex` write
  their output directly, drastically reducing allocations.
- ![Enhancement][badge-enhancement] Packet processing now builds a fresh execution plan
  before threaded work, executes each byte, raw, and processed stage at most once per
  packet, and writes lock-free packet-indexed output columns, reducing processing time and
  allocations. Output rows are sorted by timestamp, and equal timestamps keep the original
  packet order.
- ![Enhancement][badge-enhancement] `add_variable!` validates the new variable
  incrementally instead of rebuilding the whole database index, making database
  construction much faster for large databases.
- ![Enhancement][badge-enhancement] Packet processing allocations were further reduced by
  reusing node slot buffers across packets, sorting valid indices in place, and gathering
  output columns in a single pass.
- ![Bugfix][badge-bugfix] The variable table printed by `@searchvar` is no longer cropped
  vertically.
- ![Bugfix][badge-bugfix] `tf_uint64` now decodes all eight bytes, and `checkbit` supports
  signed and arbitrary-precision integers while validating the bit position.
- ![Bugfix][badge-bugfix] The default unpack function now returns the packet data, full
  telemetry dumps update the default packet collection, quantity intervals are converted
  exactly to milliseconds, and gzip persistence uses exception-safe cleanup with atomic
  file replacement.
- ![Bugfix][badge-bugfix] Malformed telemetry selections, inexact quantity intervals,
  cyclic dependencies, and invalid `analyze_byte_array` orders now throw a descriptive
  `ArgumentError`.
- ![Bugfix][badge-bugfix] ProgressMeter.jl v1.7 or later is now required so threaded
  progress updates are thread-safe.
- ![Info][badge-info] The package now has a test suite and a benchmark environment.
- ![Info][badge-info] The README now documents the source API together with the
  processing, metadata, interval, and persistence contracts.

Version 2.1.0
-------------

- ![Info][badge-info] Julia 1.10 is now the minimum supported version.
- ![Info][badge-info] PrettyTables.jl was updated to v3.

Version 2.0.3
-------------

- ![Enhancement][badge-enhancement] We added compat bounds for stdlibs.
- ![Enhancement][badge-enhancement] General improvements in the source code.

Version 2.0.2
-------------

- ![Bugfix][badge-bugfix] We fixed the conversion of variable `alias` in `@searchvar`.
- ![Bugfix][badge-bugfix] The bit transfer function can output any `AbstractVector{UInt8}`.

Version 2.0.1
-------------

- ![Bugfix][badge-bugfix] We fixed a possible racing condition when processing the
  telemetries using multiple threads.

Version 2.0.0
-------------

- ![BREAKING][badge-breaking] The function `process_telemetries` was renamed to
  `process_telemetry_packets`.
- ![BREAKING][badge-breaking] The function `set_default_telemetry_packet` was renamed to
  `set_default_telemetry_packets!`.
- ![BREAKING][badge-breaking] The function `set_default_telemetry_source` was renamed to
  `set_default_telemetry_source!`.
- ![Feature][badge-feature] We added the support for the raw transfer functions.
- ![Enhancement][badge-enhancement] We added a progress bar to show the process status.
- ![Enhancement][badge-enhancement] The variable search functionality provided by the macro
  `@searchvar` was highly improved. It is now case-insensitive and it also considers the
  variable labels during searching.
- ![Enhancement][badge-enhancement] We added a README.md describing the package.

Version 1.0.0
-------------

- Initial stable version.

[badge-breaking]: https://img.shields.io/badge/Breaking-DC2626?style=flat-square
[badge-deprecation]: https://img.shields.io/badge/Deprecation-D97706?style=flat-square
[badge-feature]: https://img.shields.io/badge/Feature-16A34A?style=flat-square
[badge-enhancement]: https://img.shields.io/badge/Enhancement-0284C7?style=flat-square
[badge-bugfix]: https://img.shields.io/badge/Bugfix-DB2777?style=flat-square
[badge-info]: https://img.shields.io/badge/Info-475569?style=flat-square
