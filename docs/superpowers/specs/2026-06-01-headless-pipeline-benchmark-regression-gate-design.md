# Headless Pipeline Benchmark And Regression Gate Design

Date: 2026-06-01

## Status

Approved design, written for user review.

## Source Context

This design is Slice 3 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slice 1 delivered fixed-height viewport range calculation and buffered line
geometry traversal. Slice 2 delivered a generic document/source provider
contract and a buffered document line cursor. The Slice 2 post-slice review
identified the largest remaining product-brief gap as the absence of a
merge-blocking benchmark gate and the absence of a benchmark for the full
headless traversal path.

This slice measures and gates the current fixed-height headless pipeline:
viewport range computation, buffered geometry traversal, and buffered provider
line traversal. It does not add new rendering or layout capabilities.

## Scope

Extend the existing `ViewportBenchmarks` executable so it can measure the full
headless pipeline by default and fail when conservative absolute latency
budgets are exceeded.

The gate is a local command ready for future CI integration:

```text
swift run -c release ViewportBenchmarks -- --gate
```

This slice does not add a CI configuration file.

## Goals

- Measure `ViewportVirtualizer.compute(_:)` plus buffered geometry cursor
  traversal plus buffered provider cursor traversal.
- Keep `TextEngineCore` unchanged unless implementation discovers a required
  compatibility fix.
- Keep benchmark-only types inside the `ViewportBenchmarks` executable target.
- Preserve the existing range-only benchmark as a diagnostic mode.
- Make pipeline benchmark output grep-friendly with key-value fields.
- Add `--gate` mode with per-scenario absolute p95 and p99 latency budgets.
- Return a non-zero process exit code when any gate budget fails.
- Report all scenario failures in one run rather than failing fast.
- Keep the provider fixture synthetic so this slice measures core traversal
  rather than real storage design.
- Record verification commands and benchmark output for the slice.

## Non-Goals

- CI configuration.
- Checked-in baseline comparison.
- Percentage-based regression comparison.
- Real file, rope, piece-table, or editor-buffer storage adapters.
- Provider prefetch, caching, or async loading.
- Variable-height layout.
- Text shaping, bidi, font fallback, rich text, rasterization, or UI adapters.
- Memory or allocation profiling gates.
- Benchmarking real `String` storage or >10 MB text payloads.
- Making `ViewportBenchmarks` compile under embedded WASM.

## Architecture

`TextEngineCore` remains a pure headless core. The benchmark executable imports
the core and exercises the public API in the same order a renderer-side adapter
would use it after Slice 2:

1. Compute a `VirtualRange` from `ViewportInput`.
2. Traverse `ViewportVirtualizer.geometry(for:lineHeight:)`.
3. Traverse `ViewportVirtualizer.lines(for:in:)`.

The benchmark target owns all timing, option parsing, synthetic provider data,
budget comparison, output formatting, and process-exit behavior.

The default benchmark mode becomes the full pipeline. The old Slice 1
range-only benchmark remains available through `--range-only` for diagnostics
and baseline comparison.

`--gate` applies only to the full pipeline in this slice. Combining
`--range-only` and `--gate` is invalid because this slice's product risk is the
full core-side scroll-frame traversal path, not the older range-only path.

## Components

### BenchmarkMode

Internal executable-only mode:

- `pipeline`: default full traversal benchmark.
- `rangeOnly`: old range recompute benchmark.

### BenchmarkOptions

Internal executable-only options parsed from command-line arguments:

- no flags: run pipeline benchmark.
- `--gate`: run pipeline benchmark and enforce budgets.
- `--range-only`: run the range-only diagnostic benchmark.
- `--help`: print usage and exit successfully.

Unknown flags and invalid flag combinations return non-zero exit status.

### SyntheticLineSource

Benchmark-only `DocumentLineSource` implementation.

It must not store an array of all lines. It should return a lightweight payload
derived from the requested index, such as an `Int`, so provider traversal work
is included without measuring storage allocation or `String` behavior.

### BenchmarkScenario

The existing scenario type should be extended or replaced with fields for:

- scenario name
- line count
- line height
- viewport height
- overscan before and after
- p95 budget in nanoseconds
- p99 budget in nanoseconds

Scenarios should continue to cover:

- about 1k lines, 20 visible lines, 0 overscan
- about 100k lines, 80 visible lines, 5 lines of overscan before and after
- about 1M lines, 200 visible lines, 50 lines of overscan before and after

### BenchmarkSummary

The benchmark summary should include:

- mode
- scenario name
- iteration count
- operations per sample
- p95 nanoseconds
- p99 nanoseconds
- checksum
- gate status when gate mode is active
- budget fields when gate mode is active

### GateResult

The gate result aggregates all scenario summaries.

Expected behavior:

- pass when every scenario is within both p95 and p99 budget
- fail when any scenario exceeds either budget
- print every scenario result before returning the final process status

## Data Flow

For each scenario, the benchmark computes a maximum scroll offset from line
count, line height, and viewport height. Each operation chooses a deterministic
offset from the operation index so repeated runs exercise top, middle, and
bottom regions without requiring random number APIs.

Pipeline operation flow:

1. Build `ViewportInput`.
2. Call `ViewportVirtualizer.compute(_:)`.
3. If computation succeeds, update the checksum with range fields.
4. Traverse `LineGeometryCursor` for the buffered range and update the
   checksum with geometry fields.
5. Traverse `DocumentLineCursor` for the same buffered range and update the
   checksum with line indexes and payloads.
6. If computation fails unexpectedly, update failure accounting and make gate
   mode fail.

The checksum is part of the benchmark contract. It should depend on range,
geometry, and provider traversal values so the optimizer cannot remove the work
being measured.

Range-only operation flow remains equivalent to the existing Slice 1 benchmark:
compute the range and update the checksum from range fields only.

## CLI Behavior

Default benchmark:

```text
swift run -c release ViewportBenchmarks
```

Runs pipeline mode and prints one key-value line per scenario.

Range-only diagnostic benchmark:

```text
swift run -c release ViewportBenchmarks -- --range-only
```

Runs only the old range recompute path and prints one key-value line per
scenario. No budgets are enforced.

Gate:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Runs pipeline mode, prints one key-value line per scenario with budget fields
and `gate=pass` or `gate=fail`, then exits with status `0` only when all
scenarios pass.

Invalid combination:

```text
swift run -c release ViewportBenchmarks -- --range-only --gate
```

Prints usage or a clear error and exits non-zero.

## Output Format

Output stays grep-friendly and line-oriented.

Normal pipeline example:

```text
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=1200 p99_ns=1800 checksum=...
```

Gate example:

```text
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=1200 p99_ns=1800 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=...
```

Range-only example:

```text
mode=range_only scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=9 checksum=...
```

The exact latency values are machine-specific and must not be hard-coded in
tests or docs except as recorded verification output.

## Initial Gate Budgets

The initial budgets are conservative absolute limits, not local-baseline
comparisons.

They are intentionally much higher than the current range-only nanosecond
baseline, because the new pipeline traverses buffered geometry and provider
lines. They remain low enough to catch accidental O(total document size) work
or unexpectedly expensive per-buffer traversal.

Initial per-operation budgets:

| Scenario | p95 budget | p99 budget |
| --- | ---: | ---: |
| `1k_lines_20_visible_overscan_0` | 20,000 ns | 50,000 ns |
| `100k_lines_80_visible_overscan_5` | 50,000 ns | 100,000 ns |
| `1m_lines_200_visible_overscan_50` | 100,000 ns | 200,000 ns |

The largest p95 budget is equal to the Slice 1 design target of 100 us. The
largest p99 budget remains below the Slice 1 design target of 250 us. These
budgets may be tightened in a later slice after CI hardware and variance are
known.

## Error Handling

- Unknown CLI flag: print usage or a clear error and exit non-zero.
- `--help`: print usage and exit `0`.
- `--range-only --gate`: print usage or a clear error and exit non-zero.
- Unexpected viewport computation failure in a scenario: record the failure in
  the checksum/failure accounting and make gate mode fail.
- Empty documents are not part of benchmark scenarios; empty behavior remains
  covered by core tests.

## Testing And Verification

Latency assertions should not live in XCTest because debug/test execution is
not representative for this benchmark. The performance gate is verified by
release executable runs.

Functional verification commands:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --help
swift run -c release ViewportBenchmarks -- --range-only --gate
```

The invalid-combination command is expected to exit non-zero.

Because `TextEngineCore` public API should remain unchanged in this slice, the
cross-target compile verification from Slice 2 should be repeated for the core
library target:

```text
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
xcrun swiftc -target arm64-apple-ios17.0 -sdk <iphoneos-sdk> -parse-as-library -emit-module Sources/TextEngineCore/*.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk <iphonesimulator-sdk> -parse-as-library -emit-module Sources/TextEngineCore/*.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
```

If a toolchain or SDK is unavailable, the verification record must identify it
as a blocker rather than silently omitting the check.

## Performance And Memory Expectations

Expected complexity:

- range computation: O(1) with respect to total document size
- geometry traversal: O(buffered line count)
- provider traversal: O(buffered line count)
- synthetic provider owned storage: O(1)
- benchmark-owned scenario storage: O(number of scenarios)
- samples storage: O(iterations)

The benchmark must not allocate document-sized arrays for the synthetic
provider. The largest scenario may use a 1M line count, but the measured work
must stay proportional to the buffered range.

## Acceptance Criteria

Slice 3 is complete when:

- `ViewportBenchmarks` defaults to full pipeline measurement.
- `--range-only` preserves the old range recompute benchmark path.
- `--gate` enforces per-scenario absolute p95 and p99 budgets for pipeline
  mode.
- Gate mode prints all scenario results and returns non-zero if any scenario
  exceeds budget.
- Output remains key-value and includes `mode`.
- Gate output includes budgets and pass/fail status.
- The provider fixture is synthetic and does not store document-sized payloads.
- `TextEngineCore` remains Foundation-free and independent of benchmark
  support code.
- Verification records passing host tests, release build, normal benchmark,
  range-only benchmark, gate run, and cross-target core compile checks.
- No CI configuration is added in this slice.

## Open Decisions For Later Slices

- Whether to add checked-in baseline comparison on top of absolute budgets.
- Whether to wire the gate into a specific CI system.
- Whether to add allocation or memory regression checks.
- Whether to benchmark realistic storage adapters in a separate target.
- Whether to add provider-boundary benchmarks using `String` or UTF-8 payloads.
- Whether to tighten budgets after CI hardware variance is known.
