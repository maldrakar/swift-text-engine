# Realistic Provider Benchmark Design

Date: 2026-06-04

## Status

Approved design, written for user review.

## Source Context

This design is Slice 4 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slice 1 delivered fixed-height viewport range calculation and buffered
geometry traversal. Slice 2 delivered a generic document/source provider
contract and buffered document line cursor. Slice 3 delivered a release-mode
benchmark gate for the fixed-height pipeline using a synthetic integer
provider.

The Slice 3 post-slice review identified two remaining performance-proof gaps:
the repository does not yet have CI wiring, and the current benchmark proves
large line counts but not behavior against a realistic text payload. CI is not
chosen yet and is planned after the main implementation, so Slice 4 focuses on
the realistic provider proof outside `TextEngineCore`.

## Scope

Extend the existing `ViewportBenchmarks` executable with an opt-in realistic
provider benchmark mode.

The new mode represents a deterministic large text document with at least
100,000 lines and at least 10 MB of text payload, then runs the existing
fixed-height headless pipeline against a lightweight provider handle.

This slice keeps `TextEngineCore` unchanged unless implementation discovers a
required compatibility fix. Benchmark-only storage and provider types stay in
the `ViewportBenchmarks` executable target.

## Goals

- Prove the provider boundary can work against a large text payload without
  moving storage into `TextEngineCore`.
- Represent at least 100,000 logical lines and at least 10 MB of deterministic
  text payload.
- Keep realistic provider storage outside timed per-operation samples.
- Model the provider as a lightweight handle over reference-backed storage so
  `DocumentLineCursor` does not copy the large document by value.
- Traverse only the buffered range returned by `ViewportVirtualizer.compute(_:)`
  for each operation.
- Measure the fixed-height pipeline against the realistic provider separately
  from the Slice 3 synthetic provider gate.
- Preserve the existing default synthetic pipeline benchmark, `--range-only`
  diagnostic mode, and `--gate` behavior.
- Keep output line-oriented and grep-friendly.
- Record verification commands and benchmark output for the slice.

## Non-Goals

- CI configuration.
- Checked-in baselines or percentage-based regression comparison.
- Adding realistic provider budgets to `--gate`.
- File IO, memory-mapped files, ropes, piece tables, or editor-buffer storage.
- Async loading, prefetch, caching, or background document generation.
- Variable-height layout.
- Text shaping, bidi, font fallback, rich text, rasterization, or UI adapters.
- Moving storage adapters or benchmark fixtures into `TextEngineCore`.
- Making `ViewportBenchmarks` compile under embedded WASM.

## Architecture

`TextEngineCore` remains the pure headless core. Slice 4 extends only the
benchmark executable that already imports and exercises the public core API.

The current default benchmark remains the Slice 3 synthetic pipeline:

1. Compute a fixed-height `VirtualRange`.
2. Traverse buffered geometry.
3. Traverse buffered provider lines over a synthetic integer provider.
4. Enforce p95 and p99 budgets only in `--gate` mode.

The new realistic provider benchmark is a separate CLI mode selected by
`--realistic-provider`. It uses the same fixed-height pipeline, but swaps the
provider fixture for a large reference-backed text document.

The separation is intentional. The synthetic provider gate measures core-side
scroll-frame traversal cost with conservative budgets. The realistic provider
mode proves that the provider boundary can sit in front of a large text payload
while touching only buffered lines. It records performance data but does not
enforce budgets until CI hardware and variance are known.

## Components

### BenchmarkMode

Add a new executable-only mode:

- `pipeline`: default full traversal benchmark with the synthetic provider.
- `rangeOnly`: diagnostic range recompute benchmark.
- `realisticProvider`: full traversal benchmark with a large text provider.

### BenchmarkOptions

Extend command-line parsing:

- no flags: run `pipeline`.
- `--range-only`: run `rangeOnly`.
- `--gate`: run `pipeline` and enforce existing synthetic budgets.
- `--realistic-provider`: run `realisticProvider`.
- `--help`: print usage and exit successfully.

Unknown flags return non-zero. `--realistic-provider --gate` is invalid in this
slice because realistic-provider budgets are intentionally not calibrated yet.
`--range-only --gate` remains invalid.

### RealisticDocumentStorage

Benchmark-only reference type that owns deterministic large text storage.

Expected responsibilities:

- own a contiguous deterministic UTF-8 byte payload of at least 10 MB;
- expose the logical line count;
- expose line metadata needed by the provider without requiring a full-document
  copy;
- be built once before timed samples begin.

The initial fixture uses fixed-width generated lines so the provider can map
line index to byte range in O(1). That keeps this slice focused on the provider
boundary over a large payload rather than on production storage representation.

### RealisticLineSource

Benchmark-only `DocumentLineSource` implementation.

Expected shape:

- lightweight value or reference handle that points to `RealisticDocumentStorage`;
- `lineCount` delegates to storage;
- `line(at:)` validates the requested index and returns `.missing` for invalid
  indexes;
- `line(at:)` returns payload metadata for the requested line without copying
  the large document.

This component exists to exercise the Slice 2 provider cursor against realistic
large storage while avoiding accidental large value copies when the cursor stores
the source.

### RealisticLinePayload

Small benchmark-only payload returned by `RealisticLineSource`.

The payload should be enough to prove that line content metadata came from the
large document, but small enough to avoid measuring repeated heap allocation or
full `String` line copying unless a later slice deliberately chooses to measure
that.

Expected fields:

- `byteOffset`;
- `byteLength`;
- `firstByte`;
- `middleByte`;
- `lastByte`.

### RealisticProviderScenario

Scenario metadata for realistic-provider runs:

- scenario name;
- line count;
- target document byte count;
- line height;
- viewport height;
- overscan before and after.

The initial slice has one required realistic scenario: 100,000 lines with at
least 10 MB of UTF-8 payload. Larger scenarios are left to later calibration
work.

### BenchmarkSummary Output

The existing line-oriented output format remains. Realistic-provider output
must include these fields:

- `mode=realistic_provider`;
- `provider=large_text`;
- `scenario`;
- `iterations`;
- `operations_per_sample`;
- `line_count`;
- `document_bytes`;
- `line_bytes`;
- `p95_ns`;
- `p99_ns`;
- `failures`;
- `checksum`.

Exact latency values are machine-specific and must not be hard-coded in tests or
docs except as recorded verification output.

## Data Flow

For `--realistic-provider`, document construction happens before timing starts.
The measured operation is viewport pipeline traversal against already-owned
large document storage.

Per-scenario setup:

1. Create `RealisticDocumentStorage`.
2. Create a lightweight `RealisticLineSource` handle for that storage.
3. Compute scenario document height and maximum scroll offset.

Per-operation flow:

1. Choose a deterministic scroll offset from the operation index.
2. Build `ViewportInput` using `source.lineCount`.
3. Call `ViewportVirtualizer.compute(_:)`.
4. If range computation succeeds, fold range fields into checksum.
5. Traverse `ViewportVirtualizer.geometry(for:lineHeight:)` for the buffered
   range and fold geometry fields into checksum.
6. Traverse `ViewportVirtualizer.lines(for:in:)` over `RealisticLineSource`.
7. For each line payload, fold line index and payload metadata into checksum.
8. Count any unexpected missing line as a failure.

The checksum must depend on range, geometry, provider indexes, and realistic
payload metadata so the optimizer cannot remove the measured work.

## CLI Behavior

Default synthetic benchmark:

```text
swift run -c release ViewportBenchmarks
```

Range-only diagnostic benchmark:

```text
swift run -c release ViewportBenchmarks -- --range-only
```

Synthetic benchmark gate:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Realistic provider benchmark:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Invalid realistic provider gate:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

The invalid command prints a clear error and exits non-zero.

## Error Handling And Edge Cases

- Unknown CLI flags produce an explicit error and non-zero exit status.
- `--range-only --gate` remains invalid.
- `--realistic-provider --gate` is invalid for this slice.
- Realistic provider construction failures should be represented in benchmark
  executable code without changing `TextEngineCore`.
- Provider requests outside `0..<lineCount` return `.missing`.
- Any missing line within a valid computed buffered range increments benchmark
  failure accounting.
- Empty documents are not part of realistic-provider scenarios; empty range
  behavior remains covered by core tests.

## Testing

Latency assertions should not be added to XCTest because debug test execution is
not representative for benchmark behavior.

Functional test additions are optional. If realistic fixture code remains in
`Sources/ViewportBenchmarks/main.swift`, Slice 4 should verify it through release
executable runs rather than over-structuring the package. If implementation
extracts fixture logic into a separate testable module, focused tests may cover
deterministic storage size, line count, missing-index behavior, and lightweight
provider payload generation.

Existing `TextEngineCore` tests should remain unchanged unless implementation
discovers an actual core compatibility issue.

## Verification

The slice verification record should include:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --json
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
```

The invalid CLI commands should be recorded as expected non-zero exits.

Cross-target compile verification still applies to `TextEngineCore` because core
compatibility is a product invariant. `ViewportBenchmarks` remains host-oriented
because it uses `ContinuousClock`, `Darwin.exit`, and benchmark-only storage.

## Performance And Memory Expectations

Expected timed complexity for the realistic-provider mode:

- range computation: O(1) with respect to total document size;
- geometry traversal: O(buffered line count);
- provider traversal: O(buffered line count), plus O(1) provider metadata lookup
  per requested line;
- cursor-owned memory: O(1), excluding caller-owned storage;
- realistic storage: at least 10 MB, owned outside `TextEngineCore`;
- per-operation work must not scan or copy the full document.

The benchmark should separate setup from timed samples. Creating the 10 MB
fixture may allocate document-sized storage, but that allocation belongs to the
benchmark provider, not the core or per-scroll operation.

No realistic-provider p95/p99 budget is enforced in Slice 4. The recorded output
becomes a baseline for later CI calibration or memory/allocation work.

## Acceptance Criteria

Slice 4 is complete when:

- `ViewportBenchmarks` supports `--realistic-provider`.
- The realistic provider benchmark represents at least 100,000 lines and at
  least 10 MB of text payload.
- Realistic provider setup is outside timed per-operation samples.
- The provider source passed to `DocumentLineCursor` is lightweight and does not
  copy the large document by value.
- Timed traversal uses only the buffered range returned by
  `ViewportVirtualizer.compute(_:)`.
- Existing default, `--range-only`, and `--gate` behavior remain intact.
- `--realistic-provider --gate` exits non-zero with a clear error.
- Output is line-oriented and includes provider/document shape fields.
- `TextEngineCore` remains Foundation-free and does not gain storage fixture
  code.
- Verification records host tests, release build, all benchmark modes, invalid
  CLI behavior, and cross-target core compile checks.

## Open Decisions For Later Slices

- Whether to wire synthetic and realistic provider benchmarks into a chosen CI
  system.
- Whether to calibrate realistic-provider p95/p99 budgets after CI hardware is
  known.
- Whether to add allocation or peak-memory gates.
- Whether to model a specific production storage representation such as UTF-8
  slices, memory-mapped files, ropes, piece tables, or editor buffers.
- Whether to split benchmark support into separate modules if fixture code grows
  beyond a single executable file.
- When to begin variable-height layout and invalidation.
