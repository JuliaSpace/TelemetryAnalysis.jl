TelemetryAnalysis.jl Changelog
==============================

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
  `@serchvar` was highly improved. It is now case-insensitive and it also considers the
  variable labels during searching.
- ![Enhancement][badge-enhancement] We added a REAMDE.md describing the package.

Version 1.0.0
-------------

- Initial stable version.

[badge-breaking]: https://img.shields.io/badge/BREAKING-red.svg
[badge-deprecation]: https://img.shields.io/badge/Deprecation-orange.svg
[badge-feature]: https://img.shields.io/badge/Feature-green.svg
[badge-enhancement]: https://img.shields.io/badge/Enhancement-blue.svg
[badge-bugfix]: https://img.shields.io/badge/Bugfix-purple.svg
[badge-info]: https://img.shields.io/badge/Info-gray.svg
