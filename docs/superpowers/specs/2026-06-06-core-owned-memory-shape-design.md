# Core-Owned Memory Shape Design

Date: 2026-06-06

## Status

Approved design, written for user review.

## Source Context

This design is Slice 7 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slice 1 delivered fixed-height viewport range calculation and buffered geometry
traversal. Slice 2 delivered the generic document/source provider contract.
Slice 3 added the synthetic fixed-height pipeline benchmark gate. Slice 4 added
an opt-in realistic-provider benchmark with a deterministic 100,000-line,
11.2 MB text payload. Slice 5 wired the synthetic benchmark gate into GitHub
Actions. Slice 6 documented that GitHub rulesets are blocked for the current
private repository state.

The largest remaining source-controlled product-brief gap is memory evidence.
The brief requires memory owned by the layout and virtualization core to avoid
linear growth with document size. The current architecture is designed for that:
range computation is scalar, geometry traversal is cursor-based, document
traversal is provider-based, and large document storage remains caller-owned.
This slice turns that design claim into a deterministic diagnostic and CI check.

## Scope

Add a `ViewportBenchmarks` diagnostic mode that reports fixed-height
core-owned memory shape for synthetic and realistic-provider scenarios, then
run that diagnostic in the existing GitHub Actions workflow.

The diagnostic separates:

- memory and state owned by `TextEngineCore`;
- caller/provider-owned realistic document payload;
- benchmark-owned sample and scenario bookkeeping.

This slice keeps `TextEngineCore` source and public API unchanged unless
implementation discovers a required compatibility fix. The diagnostic logic
stays in the host-only `ViewportBenchmarks` executable target.

## Goals

- Define what counts as core-owned memory for the current fixed-height path.
- Report deterministic memory-shape fields for 100,000-line and 1,000,000-line
  synthetic scenarios.
- Report deterministic memory-shape fields for the existing realistic-provider
  scenario with at least 100,000 lines and at least 10 MB of provider-owned
  payload.
- Prove that core-owned state stays bounded by scalar range/cursor state and
  buffered traversal, not total document line count or document bytes.
- Keep caller-owned realistic storage separate from core-owned fields.
- Make output line-oriented and grep-friendly.
- Make the diagnostic exit non-zero when deterministic invariants fail.
- Add the diagnostic command to `.github/workflows/swift-ci.yml` after the
  existing synthetic benchmark gate.
- Record local verification and the exact diagnostic output for the slice.

## Non-Goals

- RSS, resident-memory, `malloc`, or heap-allocation hard budgets.
- CI branch protection, GitHub rulesets, or legacy branch protection.
- Realistic-provider latency budgets or `--realistic-provider --gate`.
- File-backed storage, memory-mapped files, ropes, piece tables, or editor
  buffer storage.
- Async loading, prefetch, caching, or background document generation.
- Variable-height layout or localized invalidation.
- Text shaping, bidi, font fallback, rich text, rasterization, or UI adapters.
- Moving benchmark fixtures or storage adapters into `TextEngineCore`.
- Making `ViewportBenchmarks` compile under embedded WASM.

## Architecture

`TextEngineCore` remains a pure headless core. It owns only the fixed-height
range and cursor types that already exist:

- `VirtualRange`
- `LineGeometryCursor`
- `DocumentLineCursor`
- transient `LineGeometry`
- transient `DocumentLineCursorElement`

The new diagnostic mode lives in `Sources/ViewportBenchmarks/main.swift`. It
constructs representative scenarios, computes one deterministic viewport range
per scenario, derives the buffered line count, and reports the memory-shape
classification for that operation.

The diagnostic is structural, not a system profiler. It does not ask the
allocator how much memory the process currently owns. Instead it reports the
parts that matter for the product invariant:

1. core-owned scalar state;
2. core-touched buffered traversal count;
3. provider-owned document bytes;
4. benchmark-owned sample storage or scenario bookkeeping.

The workflow integration remains narrow. The existing `Swift CI` job already
runs host tests and the synthetic benchmark gate. Slice 7 adds one deterministic
command:

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

The workflow should fail if this command exits non-zero. It should not parse
RSS output, enforce system memory budgets, or require GitHub repository
settings changes.

## Components

### BenchmarkMode

Add a new executable-only mode:

- `pipeline`: default full traversal benchmark with the synthetic provider.
- `rangeOnly`: diagnostic range recompute benchmark.
- `realisticProvider`: full traversal benchmark with a large text provider.
- `memoryShape`: deterministic memory-shape diagnostic.

### BenchmarkOptions

Extend command-line parsing:

- no flags: run `pipeline`;
- `--range-only`: run `rangeOnly`;
- `--gate`: run `pipeline` and enforce existing synthetic latency budgets;
- `--realistic-provider`: run `realisticProvider`;
- `--memory-shape`: run `memoryShape`;
- `--help`: print usage and exit successfully.

Unknown flags return non-zero. `--memory-shape --gate` is invalid in this
slice because memory-shape invariants are deterministic and owned by the
diagnostic mode itself. `--memory-shape` also cannot be combined with
`--range-only` or `--realistic-provider`.

### MemoryShapeScenario

Executable-only scenario metadata for deterministic memory-shape runs.

Expected fields:

- scenario name;
- provider kind, either synthetic or realistic;
- line count;
- optional document bytes;
- line height;
- viewport height;
- overscan before and after;
- deterministic scroll offset selection.

Required scenarios:

- 100,000 synthetic lines with the same visible and overscan shape as the
  existing `100k_lines_80_visible_overscan_5` benchmark;
- 1,000,000 synthetic lines with the same visible and overscan shape as the
  100,000-line comparison scenario;
- the existing realistic-provider `100k_lines_10mb_text` shape.

Using the same visible and overscan shape for the 100,000-line and 1,000,000
line synthetic comparison is important. It lets the diagnostic show that
core-owned state does not change merely because total line count grows.

### MemoryShapeSummary

Executable-only summary produced for one scenario.

Expected fields:

- mode;
- scenario;
- provider;
- line count;
- optional document bytes;
- visible line count;
- buffered line count;
- core-owned byte estimate;
- provider-owned byte estimate;
- benchmark-owned byte estimate;
- touched line count;
- invariant result;
- checksum.

The byte estimates are deterministic model estimates. They are not process RSS.
They should be based on Swift type sizes where practical, for example
`MemoryLayout<T>.size`, and on explicit scenario data for provider-owned
payload bytes.

### MemoryShapeInvariant

Internal invariant checks that make the diagnostic command useful in CI.

Expected checks:

- `buffered_lines` equals `bufferEndExclusive - bufferStart`.
- `touched_lines` equals `buffered_lines` for geometry traversal and provider
  traversal.
- `provider_owned_bytes` is zero for synthetic scenarios.
- `provider_owned_bytes` equals realistic storage document bytes for the
  realistic scenario.
- the two synthetic comparison scenarios with the same viewport and overscan
  shape report the same `core_owned_bytes`.
- no valid scenario reports missing provider lines.

The command exits `0` only when all scenario invariants pass. It exits non-zero
after printing all summaries if any invariant fails.

## Data Flow

Per scenario:

1. Create synthetic provider metadata or realistic provider storage.
2. Build a deterministic `ViewportInput`.
3. Call `ViewportVirtualizer.compute(_:)`.
4. Derive visible and buffered line counts from the returned `VirtualRange`.
5. Traverse geometry and provider cursors for the buffered range only.
6. Fold range fields, cursor counts, and provider payload metadata into a
   checksum.
7. Classify memory shape as core-owned, provider-owned, and benchmark-owned.
8. Validate deterministic invariants.
9. Print one key-value summary line.

The realistic-provider document may allocate the existing 11.2 MB fixture
before the diagnostic prints its summary. That allocation is intentionally
classified as provider-owned, not core-owned.

## CLI Behavior

Memory-shape diagnostic:

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Invalid memory-shape gate:

```text
swift run -c release ViewportBenchmarks -- --memory-shape --gate
```

The invalid command prints a clear error and exits non-zero.

Existing commands keep their current behavior:

```text
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
```

## Output Format

Output stays line-oriented and grep-friendly.

Example:

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 core_owned_bytes=160 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=90160
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 core_owned_bytes=160 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=900160
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 core_owned_bytes=160 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=11300160
```

The numbers above are illustrative. Exact byte estimates are
implementation-defined but deterministic. Verification should record actual
local output instead of inventing values in prose.

## Workflow Integration

Update `.github/workflows/swift-ci.yml` by adding one step after the existing
synthetic benchmark gate:

```yaml
- name: Run memory shape diagnostic
  run: swift run -c release ViewportBenchmarks -- --memory-shape
```

The existing job name remains `Host tests and benchmark gate`. This avoids
changing the status-check context that Slice 6 planned to require later.

The workflow does not parse diagnostic output. The executable owns invariant
checking and process exit behavior.

## Error Handling And Edge Cases

- Unknown CLI flags produce an explicit error and non-zero exit status.
- `--memory-shape --gate` is invalid.
- `--memory-shape --range-only` is invalid.
- `--memory-shape --realistic-provider` is invalid.
- Viewport computation failure in a required scenario prints a failure summary
  and makes the command exit non-zero.
- Missing provider lines within a computed buffered range increment failure
  accounting and make the command exit non-zero.
- Empty documents are not part of memory-shape scenarios; empty behavior
  remains covered by core tests.

## Testing

Latency assertions should not be added to XCTest. The memory-shape diagnostic is
verified through the release executable because it belongs to the benchmark
target and is intended to run in CI.

Existing `TextEngineCore` tests should remain unchanged unless implementation
discovers an actual core compatibility issue.

Optional focused XCTest coverage may be added only if implementation extracts
memory-shape logic into testable pure helpers. It is acceptable to keep the
first implementation in the benchmark executable and verify through CLI output.

## Verification

The slice verification record should include:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-shape --gate
rg -n "Run memory shape diagnostic|--memory-shape" .github/workflows/swift-ci.yml
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
```

The invalid `--memory-shape --gate` command is expected to exit non-zero.

Cross-target compile verification still targets `TextEngineCore` only.
`ViewportBenchmarks` remains host-oriented because it uses `Darwin.exit`,
`ContinuousClock`, and benchmark-only diagnostics.

## Performance And Memory Expectations

Expected deterministic shape:

- range computation: O(1) with respect to total document size;
- geometry traversal: O(buffered line count);
- provider traversal: O(buffered line count);
- core-owned persistent storage: none beyond caller-visible value/cursor state;
- synthetic provider-owned payload: zero document-sized storage;
- realistic provider-owned payload: at least 10 MB outside `TextEngineCore`;
- per-operation work must not scan or copy the full document.

The diagnostic should make the 100,000-line and 1,000,000-line synthetic
comparison explicit. With the same visible and overscan shape, total line count
may change range scalar values, but it must not change the reported
core-owned byte estimate.

No RSS, heap, or allocation budget is enforced in this slice. Those can be
added later after the deterministic ownership boundary is established.

## Acceptance Criteria

Slice 7 is complete when:

- `ViewportBenchmarks` supports `--memory-shape`.
- `--memory-shape` prints key-value summaries for required synthetic and
  realistic-provider scenarios.
- The summaries separate core-owned, provider-owned, and benchmark-owned
  fields.
- The 100,000-line and 1,000,000-line synthetic comparison proves identical
  core-owned byte estimates for the same visible and overscan shape.
- The realistic-provider summary reports provider-owned document bytes and does
  not classify the 11.2 MB payload as core-owned.
- The diagnostic exits non-zero when deterministic invariants fail.
- `--memory-shape --gate` exits non-zero with a clear error.
- `.github/workflows/swift-ci.yml` runs `swift run -c release
  ViewportBenchmarks -- --memory-shape` after the existing synthetic benchmark
  gate.
- The workflow job name remains `Host tests and benchmark gate`.
- `TextEngineCore` remains Foundation-free and does not gain storage fixture or
  diagnostic code.
- Verification records host tests, release build, benchmark modes, memory-shape
  output, workflow scan, invalid CLI behavior, and cross-target core compile
  checks.

## Open Decisions For Later Slices

- Whether to add RSS, heap, or allocation measurements as observational output.
- Whether to turn memory diagnostics into hard memory budgets.
- Whether to calibrate realistic-provider latency budgets.
- Whether to run realistic-provider latency benchmarks in CI.
- Whether to add branch protection or ruleset enforcement when GitHub
  repository capabilities allow it.
- Whether to model a production storage representation such as UTF-8 slices,
  memory-mapped files, ropes, piece tables, or editor buffers.
- When to begin variable-height layout and invalidation.
