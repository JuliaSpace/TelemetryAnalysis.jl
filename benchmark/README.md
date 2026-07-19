# Benchmarks

The benchmark dependencies are intentionally isolated from the package test target. Set up
the environment from the repository root with:

```sh
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'
```

Run the full suite with one or multiple threads:

```sh
JULIA_NUM_THREADS=1 julia --project=benchmark benchmark/benchmarks.jl
JULIA_NUM_THREADS=4 julia --project=benchmark benchmark/benchmarks.jl
```

For a bounded validation run, set `TELEMETRY_BENCHMARK_SMOKE=true`. Results are warmed
BenchmarkTools medians and include elapsed nanoseconds, allocated bytes, and allocation
counts. The thread scenario name records the active thread count.

Do not commit `benchmark/Manifest.toml`; benchmark dependency resolution remains separate
from package tests and may use compatible versions available in the local Julia environment.
