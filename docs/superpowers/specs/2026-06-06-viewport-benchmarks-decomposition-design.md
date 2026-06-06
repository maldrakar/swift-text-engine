# Viewport Benchmarks Decomposition Design

Date: 2026-06-06

## Context

This design is Slice 8 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

The product brief requires stable scroll performance on large documents,
strict viewport virtualization, external document storage, memory evidence that
core-owned layout and virtualization state does not grow linearly with document
size, iOS/WASM source compatibility, and regression benchmarks that can block
merge when performance degrades.

Slices 1 through 7 built and verified the current fixed-height path:

- fixed-height viewport virtualization;
- document/source provider traversal;
- synthetic pipeline benchmark gate;
- realistic large-text provider benchmark;
- GitHub Actions wiring for host tests and the synthetic benchmark gate;
- deferred GitHub ruleset configuration for `main`;
- deterministic core-owned memory-shape diagnostic and CI wiring.

Slice 7 completed its approved product behavior, but the post-slice review
found one confirmed maintainability issue: `Sources/ViewportBenchmarks/main.swift`
grew to 1,005 lines and now mixes CLI parsing, synthetic benchmarks, realistic
provider fixtures, memory-shape diagnostics, output formatting, and process
entry in one file.

Slice 8 fixes that benchmark-target shape before adding any new benchmark mode,
memory profiler, hosted-runner calibration, or variable-height layout work.

## Goal

Split `Sources/ViewportBenchmarks/main.swift` into focused Swift files without
changing benchmark behavior.

The executable should remain the same tool from a caller's perspective:

```text
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
```

The invalid flag combinations, usage text, output keys, scenario names,
budgets, checksum formulas, workflow commands, and process exit behavior stay
unchanged.

## Non-Goals

Slice 8 does not:

- change `TextEngineCore` source or public API;
- change `Tests`;
- change `Package.swift`;
- change `.github/workflows/swift-ci.yml`;
- add a new benchmark or diagnostic mode;
- add RSS, heap, malloc, allocation-count, or peak-memory measurement;
- enforce realistic-provider p95/p99 budgets;
- retry GitHub rulesets or legacy branch protection;
- add cross-target CI jobs;
- start variable-height layout or invalidation work;
- change benchmark budget values, scenario names, output keys, or error text.

## Selected Approach

Use a concern-based split.

The alternative phase-based split would separate parsing, scenarios,
operations, runners, formatting, and entrypoint. That reduces file size, but
mode-specific logic would be spread across multiple files.

The alternative minimal split would move only CLI parsing and memory-shape code.
That is a smaller diff, but it leaves `main.swift` with too many unrelated
responsibilities and only partially closes the Slice 7 review finding.

The concern-based split is the best fit because future slices are likely to
touch one benchmark concern at a time: allocation/RSS observation,
realistic-provider budget calibration, hosted-runner samples, or additional
memory diagnostics.

## Architecture

`ViewportBenchmarks` remains one executable target. Swift files inside the
target share module-internal declarations, so this slice should not need new
public API. Implementation may add explicit `internal` only where it improves
readability or resolves compiler diagnostics.

The target should be organized as:

- `main.swift`
- `BenchmarkOptions.swift`
- `BenchmarkModels.swift`
- `BenchmarkSupport.swift`
- `SyntheticBenchmarks.swift`
- `RealisticProviderBenchmark.swift`
- `MemoryShapeDiagnostics.swift`
- `BenchmarkProgram.swift`

`main.swift` becomes the small process entry. It performs the macOS 13.0
availability check, passes command-line arguments to `runProgram`, and exits
through `Darwin.exit` when the returned code is non-zero.

`BenchmarkProgram.swift` owns top-level dispatch:

- parse options through `BenchmarkOptions.parse`;
- dispatch `.pipeline` and `.rangeOnly` to synthetic benchmarks;
- dispatch `.realisticProvider` to the realistic-provider benchmark;
- dispatch `.memoryShape` to the memory-shape diagnostic;
- print parse failures with the existing `error=<message>` prefix and usage
  text;
- translate success or failure to process exit code.

`BenchmarkOptions.swift` owns CLI contract:

- `BenchmarkMode`;
- parse result enum;
- `BenchmarkOptions`;
- usage text;
- mutually exclusive flag checks.

`BenchmarkModels.swift` owns shared value types used by more than one benchmark
concern:

- `BenchmarkScenario`;
- `RealisticProviderScenario`;
- `BenchmarkSummary`;
- `BenchmarkOperationResult`.

Memory-shape-only types stay in `MemoryShapeDiagnostics.swift` because they are
not shared across benchmark modes.

`BenchmarkSupport.swift` owns reusable mechanics:

- `nanoseconds(_:)`;
- `percentile(_:numerator:denominator:)`;
- `deterministicScrollOffset(sample:maxOffset:)`;
- generic provider traversal through `runProviderOperation`.

It should not own scenario definitions, mode-specific output, or process
dispatch.

`SyntheticBenchmarks.swift` owns the synthetic pipeline and range-only
benchmark concern:

- `SyntheticLineSource`;
- `benchmarkScenarios()`;
- `runRangeOnlyOperation(input:)`;
- `runPipelineOperation(input:source:)`;
- synthetic scenario execution;
- `runSyntheticBenchmarks(options:)`.

`RealisticProviderBenchmark.swift` owns the large-text provider benchmark
concern:

- `RealisticLinePayload`;
- `RealisticDocumentStorage`;
- `RealisticLineSource`;
- `realisticProviderScenarios()`;
- `runRealisticProviderOperation(input:source:)`;
- realistic scenario execution;
- `runRealisticProviderBenchmarks()`.

`MemoryShapeDiagnostics.swift` owns the deterministic memory-shape concern:

- memory-shape provider kind;
- memory-shape scenarios;
- traversal result and summary types;
- middle-of-document scroll offset helper;
- expected visible and buffered line helpers;
- core-owned byte estimate;
- range boundedness and traversal counters;
- memory-shape scenario execution;
- memory-shape formatting;
- invariant aggregation and `runMemoryShapeDiagnostics()`.

`SyntheticLineSource` remains in `SyntheticBenchmarks.swift` even though
memory-shape diagnostics use it for the synthetic provider case. It is a
target-internal benchmark fixture; duplicating it or creating a separate
fixtures file for one shared type would add unnecessary structure.

## Data Flow

The runtime flow remains unchanged:

1. `main.swift` checks `macOS 13.0`.
2. `main.swift` calls `runProgram(arguments:)` with
   `CommandLine.arguments.dropFirst()`.
3. `runProgram` calls `BenchmarkOptions.parse`.
4. Successful parse dispatches through `runBenchmarks(options:)`.
5. Synthetic `.pipeline` and `.rangeOnly` modes call
   `runSyntheticBenchmarks(options:)`.
6. `.realisticProvider` calls `runRealisticProviderBenchmarks()`.
7. `.memoryShape` calls `runMemoryShapeDiagnostics()`.
8. Each runner prints the same line-oriented output as before.
9. The Boolean result becomes exit code `0` or `1`.

Latency values remain naturally variable. Behavioral verification should focus
on stable contract fields: mode names, provider names, scenario names, output
keys, budget fields, gate fields, invariant fields, deterministic memory-shape
values, invalid CLI failures, and process exit codes.

## Error Handling

CLI error handling remains unchanged.

`BenchmarkOptions.parse` returns `.failure(message)` for unknown arguments and
invalid combinations. `runProgram` prints:

```text
error=<message>
```

then prints the usage text and returns exit code `1`.

The invalid combinations stay the same:

- `--range-only --gate`;
- `--realistic-provider --gate`;
- `--memory-shape --gate`;
- `--range-only --realistic-provider`;
- `--range-only --memory-shape`;
- `--realistic-provider --memory-shape`;
- any unknown argument.

Runtime preconditions stay unchanged. The realistic storage fixture still
requires positive line count and `lineBytes >= 8`. Impossible mode-dispatch
branches may keep their existing `preconditionFailure` behavior.

## Testing And Verification

Slice 8 verification should prove that the refactor is behavior-preserving.

Required local commands:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
```

Required invalid CLI check:

```text
swift run -c release ViewportBenchmarks -- --memory-shape --gate
```

Expected result: non-zero exit and the unchanged error:

```text
error=--memory-shape cannot be combined with --gate
```

Required repository-shape checks:

```text
rg -n "Run synthetic benchmark gate|Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml
git diff -- Sources/TextEngineCore Tests Package.swift .github/workflows/swift-ci.yml
wc -l Sources/ViewportBenchmarks/*.swift
```

Expected results:

- workflow status names and commands are unchanged;
- no diff exists under `Sources/TextEngineCore`, `Tests`, `Package.swift`, or
  `.github/workflows/swift-ci.yml`;
- `main.swift` is reduced to a small entrypoint;
- the new files have focused responsibilities.

No new XCTest target coverage is required for this slice unless implementation
finds a low-risk test seam that can be added without changing executable
behavior. The command matrix is the primary proof because this target is a
benchmark harness.

Cross-target `TextEngineCore` compile verification is not required for this
slice if the no-diff check proves core source is unchanged. If implementation
touches `TextEngineCore`, this design is violated and the slice should stop for
redesign instead of expanding scope.

## Completion Criteria

Slice 8 is complete when:

- `Sources/ViewportBenchmarks/main.swift` is split into the files named in this
  design;
- `main.swift` contains only process entry responsibilities;
- all existing benchmark modes compile and run;
- invalid CLI behavior remains unchanged;
- synthetic gate and memory-shape diagnostics still pass;
- workflow YAML is unchanged;
- `TextEngineCore`, `Tests`, and `Package.swift` are unchanged;
- verification results are recorded in a new document under
  `docs/superpowers/verification/`;
- a post-slice review can confirm that Slice 8 paid down the Slice 7
  maintainability finding without changing product behavior.

## Future Work

After this decomposition, the next product-oriented slice can choose one of
these without starting from an overgrown benchmark entrypoint:

- allocator-level memory observation such as RSS, heap, allocation-count, or
  peak-memory diagnostics;
- realistic-provider budget calibration;
- hosted-runner benchmark variance sampling;
- cross-target CI for `TextEngineCore`;
- variable-height layout foundation.

GitHub rulesets or branch protection should remain deferred until repository
state changes or the user explicitly prioritizes operational merge enforcement
again.
