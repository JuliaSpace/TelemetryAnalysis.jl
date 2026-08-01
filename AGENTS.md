# AGENTS.md

Instructions for coding agents working on TelemetryAnalysis.jl, a Julia package for analyzing satellite telemetry.

## Package Structure

- Requires Julia 1.10 or newer (`[compat]` in `Project.toml`).
- Entrypoint is `src/TelemetryAnalysis.jl`. Include order matters: `types.jl` first, then the constants defined in the entrypoint, then `io.jl`, `misc.jl`, `database/*.jl`, and `sources/*.jl`. New code can only reference symbols defined earlier in this order.
- `Crayons` and `Dates` are re-exported via Reexport; `d`, `h`, `m`, `s` are exported Unitful time-unit aliases.
- Tests are organized by feature, not by source file: `test/runtests.jl` includes `transfer_functions.jl`, `processing.jl`, `database.jl`, `misc.jl`, `sources.jl`, `persistence.jl`, and `packets.jl` inside one top-level `@testset`, after loading shared helpers from `test/helpers.jl` (test sources, packet constructors, shared state).
- `test/fixtures/` holds version-specific legacy serialization fixtures (`julia-1.10/`, `julia-1.12/`), regenerated with `test/fixtures/generate.jl`.
- Test-only dependencies are declared via `[extras]`/`[targets]` in `Project.toml` (currently only `Test`); everything else the tests use is a runtime dependency.
- `benchmark/` has its own environment (`benchmark/Project.toml`, BenchmarkTools only) and loads the package via `LOAD_PATH`; see `benchmark/README.md`. Do not commit `benchmark/Manifest.toml`.
- No `Manifest.toml` is committed; dependencies resolve fresh from `[compat]`.

## Commands

- Instantiate: `julia --project=. -e 'using Pkg; Pkg.instantiate()'`
- Full test suite: `julia --project=. -e 'using Pkg; Pkg.test()'`
- Focused test file (helpers must be loaded first): `julia --project=. -e 'using Test, TelemetryAnalysis; include("test/helpers.jl"); include("test/<file>.jl")'`
- Benchmarks: `julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'` then `julia --project=benchmark benchmark/benchmarks.jl` (set `TELEMETRY_BENCHMARK_SMOKE=true` for a bounded validation run).
- Format: `julia -e 'using JuliaFormatter; format(".")'` — no `--project=.` (JuliaFormatter is not a project dependency; it must be installed in the default environment). Check for changes afterwards with `git diff --exit-code`.
- Use generous timeouts: the first `Pkg.instantiate()`/`Pkg.test()` triggers precompilation and can run for minutes while printing little — that is not a hang.

## Code Style

- Formatting is defined by `.JuliaFormatter.toml` (Blue style plus alignment options and other overrides) — that file is the source of truth; run JuliaFormatter instead of formatting by hand. CI does not enforce formatting.
- 92-character line width.
- Every file starts with a `## Description ###...###` header block stating its purpose.
- Section separators are full-width `###...###` boxes with a centered title (see `src/TelemetryAnalysis.jl`).
- Public functions, types, and even test helpers get docstrings with a signature line and, where applicable, `# Fields` / argument sections.
- Match the existing `@testset "Name" begin ... end` style; test files assume they run inside the top-level testset from `runtests.jl`.

## CI

- `ci.yml` tests Julia 1.10 and the latest stable 1.x on ubuntu-latest (x64), macos-latest (arm64), and windows-latest (x64), with coverage uploaded to Codecov. `ci-nightly.yml` runs the same matrix on Julia nightly.
- CI runs `julia-buildpkg` then `julia-runtest`; `Pkg.test()` alone reproduces it locally (there is no `deps/build.jl`).

## Not Configured

- No docs build (`docs/` does not exist), no pre-commit hooks, no package extensions, no test-name selector (run files, not named tests), no CI format-check job.
