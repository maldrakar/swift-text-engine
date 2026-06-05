# Slice 4 Post-Slice Review

Date: 2026-06-05

## Scope Reviewed

This review covers Slice 4: realistic provider benchmark outside
`TextEngineCore`.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/specs/2026-06-04-realistic-provider-benchmark-design.md`
- `docs/superpowers/plans/2026-06-04-realistic-provider-benchmark.md`
- `Sources/ViewportBenchmarks/main.swift`
- `Sources/TextEngineCore/ViewportVirtualizer.swift`
- `Sources/TextEngineCore/DocumentLineCursor.swift`
- `Sources/TextEngineCore/DocumentLineTypes.swift`
- `docs/superpowers/verification/2026-06-04-realistic-provider-benchmark.md`
- local git commit history

No separate PR notes were found in the repository.

## Product Brief Alignment

The product brief asks for a headless text rendering engine core that computes
geometry and virtualizes the visible area while staying independent from UI
frameworks.

Slice 4 narrows that product goal to a realistic large-text provider proof for
the existing fixed-height headless pipeline. This was the right follow-up to
Slice 3 because the project already had a synthetic release-mode benchmark gate,
but it did not yet exercise the provider boundary against a >10 MB text payload.

Slice 4 directly addresses these brief requirements:

- Stable scroll-performance proof now includes a 100,000-line realistic text
  payload.
- The realistic fixture represents 11,200,000 bytes of deterministic UTF-8 text.
- Document storage stays outside `TextEngineCore`.
- The provider source passed through `DocumentLineCursor` is a lightweight
  handle over reference-backed storage.
- Timed work remains limited to the buffered viewport range.
- `TextEngineCore` remains Foundation-free and does not gain storage fixtures.
- Existing host tests, synthetic benchmark gate, and cross-target core compile
  verification remain recorded.

Slice 4 does not yet prove these brief requirements:

- A repository CI workflow actually blocks merge on benchmark regressions.
- Realistic-provider p95/p99 budgets are enforced by `--gate`.
- Allocation, peak-memory, or resident-memory budgets are measured.
- File-backed, memory-mapped, rope, piece-table, or editor-buffer storage works
  with the provider contract.
- Variable-height layout, text shaping, rasterization, or UI-framework
  integration.

Those remain out of scope for this slice.

## Delivered Design

The Slice 4 design extended the existing `ViewportBenchmarks` executable with an
opt-in realistic provider mode:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

The existing default synthetic benchmark, `--range-only` diagnostic benchmark,
and `--gate` behavior remain intact. `--gate` still applies only to the
synthetic pipeline. The realistic provider mode deliberately rejects
`--realistic-provider --gate` because its budgets are not calibrated yet.

The realistic data flow is:

1. Build deterministic `RealisticDocumentStorage` before timing begins.
2. Create `RealisticLineSource`, a small provider handle that stores one
   reference to that storage.
3. For each operation, compute a fixed-height `VirtualRange`.
4. Traverse buffered geometry.
5. Traverse buffered provider lines through `DocumentLineCursor`.
6. Fold range, geometry, line indexes, and realistic payload metadata into a
   checksum.
7. Report line-oriented benchmark output with provider and document shape
   fields.

The benchmark target owns the large fixture and all timing behavior. The core
continues to expose only the generic viewport, geometry, and document-line
cursor APIs.

## Implementation Assessment

The implementation matches the approved design and keeps the slice boundary
clean.

Strengths:

- `TextEngineCore` was not changed for realistic storage support.
- Realistic provider code appears only in `Sources/ViewportBenchmarks/main.swift`.
- The fixture represents `line_count=100000`, `document_bytes=11200000`, and
  `line_bytes=112`.
- Document construction happens before timed samples begin.
- `RealisticLineSource` is a lightweight value containing a reference to
  `RealisticDocumentStorage`, so cursor storage does not copy the byte payload.
- Provider lookup returns small metadata instead of copying full `String` lines.
- The checksum depends on realistic payload metadata, not just line indexes.
- The synthetic gate path keeps its existing budgets and pass/fail output.
- Invalid CLI combinations and unknown flags continue to return non-zero exits.

Important design choices:

- Fixed-width generated lines allow O(1) index-to-byte-offset lookup.
- The benchmark models large text payload access, not production storage
  behavior.
- No realistic-provider budget is enforced yet.
- The executable remains host-oriented because it uses `ContinuousClock` and
  `Darwin.exit`.

Those choices fit Slice 4. The slice proves that the current provider boundary
can sit in front of a large text payload while preserving strict virtualization,
but it is not a full storage-adapter or CI proof.

## Test And Verification Assessment

Slice 4 intentionally does not add XCTest latency assertions. That remains the
right choice because debug test execution is not representative for benchmark
behavior.

The saved verification record covers:

- `swift test`
- `swift build -c release`
- default synthetic pipeline benchmark
- range-only benchmark
- synthetic gate benchmark
- realistic provider benchmark
- invalid CLI combinations
- unknown CLI flags
- WASM `TextEngineCore` compile
- embedded WASM `TextEngineCore` compile
- iOS device direct module compile
- iOS simulator direct module compile

Fresh host verification was also rerun for this review on 2026-06-05:

- `swift test`: pass, 39 XCTest tests, 0 failures.
- `swift run -c release ViewportBenchmarks -- --gate`: pass.
- `swift run -c release ViewportBenchmarks -- --realistic-provider`: pass.
- `git diff 48730e1..27e77c3 -- Sources/TextEngineCore Tests/TextEngineCoreTests Package.swift`: no diff.
- `rg -n "RealisticDocumentStorage|RealisticLineSource|realisticProvider|realistic_provider" Sources`: matches only `Sources/ViewportBenchmarks/main.swift`.

Fresh synthetic gate output:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1362 p99_ns=1527 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5347 p99_ns=5682 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17280 p99_ns=19652 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

Fresh realistic provider output:

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5796 p99_ns=6055 failures=0 checksum=756321289736960
```

The fresh synthetic gate still has substantial headroom:

- `1k_lines_20_visible_overscan_0`: p95 is about 6.8% of budget; p99 is about 3.1% of budget.
- `100k_lines_80_visible_overscan_5`: p95 is about 10.7% of budget; p99 is about 5.7% of budget.
- `1m_lines_200_visible_overscan_50`: p95 is about 17.3% of budget; p99 is about 9.8% of budget.

The realistic provider run is close to the synthetic 100k scenario on this host,
but it should be treated as a baseline observation rather than a budgeted
guarantee. It still does not include file IO, production storage mutation,
shaping, rasterization, UI rendering, or CI runner variance.

## Commit History Notes

The Slice 4 commit history is compact:

- `docs: design realistic provider benchmark`
- `docs: plan realistic provider benchmark`
- `perf: add realistic provider benchmark mode`
- `docs: record realistic provider benchmark verification`

The implementation commit modifies only the benchmark executable. The
verification commit records host, benchmark, invalid CLI, and cross-target core
checks.

The current branch also contains the later Slice 3 post-slice review commit.
That commit is documentation-only and does not affect the Slice 4 implementation
assessment.

## Risks And Gaps

### Merge Blocking Is Still Local

The product brief asks for regression benchmarks that block merge on performance
degradation. Slice 3 created a local synthetic gate command, and Slice 4
preserved it:

```text
swift run -c release ViewportBenchmarks -- --gate
```

However, the repository still has no CI workflow, so the gate does not yet block
repository merges.

### Realistic Provider Has No Gate Budget

The realistic provider benchmark records p95/p99 values but deliberately does
not enforce them. That is correct for Slice 4 because CI hardware and variance
are not known, but it means realistic-provider performance remains observational.

### Memory Is Still Reasoned More Than Measured

The implementation shape is memory-conscious: storage is outside the core,
cursor-owned provider state is a lightweight handle, and timed traversal is
bounded by the buffered range. But there is no automated allocation, peak-memory,
or resident-memory measurement.

This is now one of the most important remaining product-brief gaps.

### Real Storage Representations Remain Untested

The benchmark uses deterministic in-memory bytes with fixed-width lines. That is
useful for isolating provider-boundary behavior over a large payload, but it does
not prove a production representation such as UTF-8 slices, memory-mapped files,
ropes, piece tables, or editor buffers.

### Variable-Height Layout Is Still Deferred

The fixed-height pipeline is now better protected, but variable-height layout
will introduce new data structures, offset lookup semantics, invalidation, and
possibly memory growth risks. It should be a deliberate slice rather than an
incidental change mixed with CI or memory work.

## Lessons For Slice 5

1. Choose one enforcement gap.

After Slice 4, the project has strong local benchmark commands but weak
repository-level enforcement. Slice 5 should not combine CI wiring, realistic
budgets, memory profiling, storage adapter design, and variable-height layout.

2. Keep benchmark and storage fixtures outside `TextEngineCore`.

Slice 4 succeeded because realistic document storage stayed in the executable
target. That boundary should hold until the project deliberately introduces a
separate storage or adapter target.

3. Treat realistic-provider numbers as baseline data.

The fresh realistic provider run is useful, but it is a local host measurement.
It should not become a hard budget until the runtime environment and variance
are understood.

4. Do not start variable-height layout casually.

Variable-height layout will change the core's data model and performance risks.
It should enter only after the next enforcement decision is made.

5. Preserve cross-target verification for public core API changes.

Slice 4 did not change public core API. Any future slice that does should repeat
the host, iOS, WASM, and embedded WASM core checks.

## Slice 5 Candidate Options

### Option A: CI Wiring For Existing Synthetic Gate

Add repository CI configuration that runs the existing host verification and
synthetic release benchmark gate.

Suggested scope:

- Add one CI workflow for the chosen provider and runner.
- Run `swift test`.
- Run `swift run -c release ViewportBenchmarks -- --gate`.
- Document Swift, Xcode, macOS, and runner assumptions.
- Keep realistic-provider budgets, memory profiling, and cross-target CI
  expansion out of scope unless the runner already supports them.

This directly closes the remaining merge-blocking part of the product brief, but
it depends on choosing a concrete CI provider and runner shape.

### Option B: Allocation Or Peak-Memory Verification

Add a focused host-side memory or allocation proof for the current fixed-height
pipeline and realistic provider benchmark.

Suggested scope:

- Measure that core-owned work does not grow linearly with total document size.
- Include the realistic provider scenario so the 11.2 MB caller-owned fixture is
  visible but separated from per-operation core work.
- Keep budgets conservative and record tool limitations.
- Avoid production storage adapters and variable-height layout.

This closes the largest remaining non-CI proof gap from the product brief. It is
more independent than CI if the repository's CI provider is not yet known.

### Option C: Realistic Provider Budget Calibration

Calibrate p95/p99 budgets for `--realistic-provider` and optionally allow a
realistic-provider gate mode.

Suggested scope:

- Rerun realistic-provider samples enough times to understand local variance.
- Decide whether `--realistic-provider --gate` should become valid or whether a
  separate flag is clearer.
- Keep budgets conservative.
- Do not add CI wiring or memory profiling in the same slice.

This strengthens the realistic benchmark introduced by Slice 4, but hard budgets
are less useful before the execution environment is known.

### Option D: Variable-Height Layout Foundation

Begin the next major core capability: variable-height line indexing and
invalidation.

Suggested scope:

- Define a minimal height index or measurement-cache boundary.
- Preserve the fixed-height fast path.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests.

This moves product functionality forward, but it is the highest-risk option. It
should wait until either CI enforcement or memory proof is stronger.

## Recommended Slice 5 Selection

Recommended: Option A, CI wiring for the existing synthetic benchmark gate, if a
concrete CI provider and runner can be chosen now.

Reasoning:

- The product brief explicitly says regression benchmarks should block merge on
  performance degradation.
- Slice 3 already created a local gate command.
- Slice 4 preserved that command while adding a realistic large-text benchmark.
- Turning the existing gate into an actual repository merge blocker is now the
  most direct remaining brief requirement.

If the CI provider is still unknown, choose Option B instead: allocation or
peak-memory verification. That option is independent of CI-provider decisions
and closes the remaining memory-proof gap while keeping `TextEngineCore` clean.

Defer Option C until CI or memory assumptions are clearer. Defer Option D until
the project has stronger enforcement around the fixed-height pipeline.

## Slice 4 Review Conclusion

Slice 4 is a clean completion of the realistic provider benchmark proof. It
extends `ViewportBenchmarks` with an opt-in large-text provider mode, represents
100,000 lines and 11.2 MB of deterministic UTF-8 payload, keeps storage outside
`TextEngineCore`, and preserves the existing synthetic benchmark gate.

The slice still stops short of actual repository merge blocking, memory or
allocation measurement, and production storage representation. It also
intentionally avoids realistic-provider gate budgets until the execution
environment is known.

The most natural next product slice is CI wiring for the existing synthetic
benchmark gate if the CI provider is known. Otherwise, the next best slice is a
focused memory or allocation verification pass for the current fixed-height
pipeline and realistic provider benchmark.
