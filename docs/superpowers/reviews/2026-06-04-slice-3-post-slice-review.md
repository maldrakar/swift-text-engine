# Slice 3 Post-Slice Review

Date: 2026-06-04

## Scope Reviewed

This review covers Slice 3: headless pipeline benchmark and regression gate.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/specs/2026-06-01-headless-pipeline-benchmark-regression-gate-design.md`
- `docs/superpowers/plans/2026-06-03-headless-pipeline-benchmark-regression-gate.md`
- `Sources/ViewportBenchmarks/main.swift`
- `Sources/TextEngineCore/ViewportVirtualizer.swift`
- `Sources/TextEngineCore/LineGeometryCursor.swift`
- `Sources/TextEngineCore/DocumentLineCursor.swift`
- `docs/superpowers/verification/2026-06-03-headless-pipeline-benchmark-regression-gate.md`
- local git commit history

No separate PR notes were found in the repository.

## Product Brief Alignment

The product brief asks for a headless text rendering engine core that computes geometry and virtualizes the visible area while staying independent from UI frameworks.

Slice 3 narrows that product goal to performance verification for the current fixed-height headless pipeline. This was the right follow-up to Slice 2 because the core already had fixed-height viewport ranges, buffered geometry traversal, and a provider cursor, but no release-mode gate measuring those pieces together.

Slice 3 directly addresses these brief requirements:

- Stable scroll-performance work is now expressed as measurable p95/p99 budgets.
- The benchmark covers 1k, 100k, and 1M logical line scenarios.
- The measured pipeline includes range computation, buffered geometry traversal, and buffered provider traversal.
- The gate command exits non-zero when any scenario exceeds its absolute latency budget.
- Output is line-oriented and grep-friendly for CI integration.
- Core-owned work remains proportional to the buffered range, not total document size.
- `TextEngineCore` remains Foundation-free and independent from benchmark support code.
- Cross-target `TextEngineCore` compatibility remains verified for host, iOS, WASM, and embedded WASM library-target checks.

Slice 3 does not yet prove these brief requirements:

- A repository CI workflow actually blocks merge on benchmark regressions.
- Performance on realistic `String`, UTF-8, file-backed, rope, piece-table, or editor-buffer storage.
- Performance on >10 MB text payloads.
- Memory or allocation regression budgets.
- Variable-height layout, text shaping, rasterization, or UI-framework integration.

Those remain out of scope for this slice.

## Delivered Design

The Slice 3 design extended the existing `ViewportBenchmarks` executable instead of adding benchmark logic to `TextEngineCore`.

The executable now supports:

- default pipeline benchmark mode
- `--range-only` diagnostic mode
- `--gate` budget enforcement for pipeline mode
- `--help`
- invalid CLI rejection for unknown flags and `--range-only --gate`

The pipeline data flow is:

1. Build a `ViewportInput` for a deterministic scroll offset.
2. Call `ViewportVirtualizer.compute(_:)`.
3. Traverse `ViewportVirtualizer.geometry(for:lineHeight:)`.
4. Traverse `ViewportVirtualizer.lines(for:in:)` over a synthetic line source.
5. Fold range, geometry, and provider values into a checksum.
6. Record per-operation sample latency.
7. Compare p95 and p99 against scenario budgets in gate mode.

The benchmark target owns timing, option parsing, synthetic provider data, output formatting, budget comparison, and process-exit behavior.

## Implementation Assessment

The implementation matches the approved design and keeps the slice boundary clean.

Strengths:

- `TextEngineCore` was not changed for benchmark support.
- The default benchmark now measures the full fixed-height core-side traversal path.
- `--range-only` preserves the old Slice 1 diagnostic path.
- Gate output includes both measured values and budgets.
- Gate mode reports all scenario results before returning process status.
- The synthetic provider stores only `lineCount` and returns lightweight integer payloads.
- The checksum depends on range fields, geometry values, provider indexes, and provider payloads.
- Invalid CLI usage is explicit and exits non-zero.

Important design choices:

- The gate uses conservative absolute budgets rather than checked-in baseline comparisons.
- Budgets apply only to pipeline mode, not range-only mode.
- The benchmark remains executable-only and macOS-host oriented because it uses `ContinuousClock` and `Darwin.exit`.
- Provider payloads are integers so this slice measures core traversal overhead rather than real storage behavior.

Those choices fit Slice 3. They also mean the benchmark is a strong core-side gate, not a complete product-performance proof.

## Test And Verification Assessment

Slice 3 intentionally does not add XCTest latency assertions. That is correct: debug test execution is not a representative performance environment.

The saved verification record covers:

- `swift test`
- `swift build -c release`
- default pipeline benchmark
- range-only benchmark
- gate benchmark
- help output
- invalid CLI combinations
- unknown CLI flags
- WASM `TextEngineCore` compile
- embedded WASM `TextEngineCore` compile
- iOS device direct module compile
- iOS simulator direct module compile

Fresh host verification was also rerun for this review on 2026-06-04:

- `swift test`: pass, 39 XCTest tests, 0 failures.
- `swift run -c release ViewportBenchmarks -- --gate`: pass.

Fresh gate output:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1277 p99_ns=1362 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5035 p99_ns=5226 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16436 p99_ns=17572 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

The local gate has substantial headroom:

- `1k_lines_20_visible_overscan_0`: p95 is about 6.4% of budget; p99 is about 2.7% of budget.
- `100k_lines_80_visible_overscan_5`: p95 is about 10.1% of budget; p99 is about 5.2% of budget.
- `1m_lines_200_visible_overscan_50`: p95 is about 16.4% of budget; p99 is about 8.8% of budget.

Interpretation caveat: these are host-local numbers for synthetic provider traversal. They do not include real document storage, file IO, text shaping, rasterization, UI rendering, or CI machine variance.

## Commit History Notes

The Slice 3 commit history is compact:

- `docs: design headless pipeline benchmark gate`
- `docs: plan headless pipeline benchmark gate`
- `feat: add headless pipeline benchmark gate`
- `docs: record headless pipeline benchmark verification`

The implementation commit is a single executable-target change. The verification commit records the expected host, CLI, and cross-target checks.

No correction commits were needed after the benchmark gate implementation.

## Risks And Gaps

### Merge Blocking Is Prepared, Not Wired

The product brief asks for regression benchmarks that block merge on performance degradation. Slice 3 provides the command that can block merge:

```text
swift run -c release ViewportBenchmarks -- --gate
```

However, the repository has no CI workflow yet, so this is still a local gate rather than an actual repository merge blocker.

### Synthetic Provider Does Not Prove Real Storage

The benchmark includes provider cursor traversal, but the provider returns integer payloads derived from the requested index. That is useful for isolating core traversal cost, but it does not prove behavior for `String`, UTF-8 slices, memory-mapped files, ropes, piece tables, or editor buffers.

The product brief explicitly names 100k+ lines and >10 MB documents. Slice 3 proves large line counts, but not >10 MB payload behavior.

### Memory Is Still Reasoned More Than Measured

The implementation shape supports O(1) benchmark provider storage and O(buffered line count) traversal, but there is no automated allocation or resident-memory gate.

This is acceptable for Slice 3, but the next storage or CI slice should avoid turning memory claims into permanent prose-only assertions.

### Budgets Are Conservative Absolute Limits

The current budgets are intentionally loose. They are good enough to catch accidental O(total document size) work, but they are not calibrated to CI hardware variance or a checked-in baseline.

Budgets should be tightened only after the target CI/runtime environment is known.

### Benchmark Executable Has Host Assumptions

`ViewportBenchmarks` imports `Darwin` and uses `ContinuousClock`. That is fine for the current gate executable, and cross-target verification correctly applies to `TextEngineCore`, not the benchmark target.

If later slices need portable benchmark tooling, that should be a deliberate target split rather than accidental benchmark code migration into the core.

## Lessons For Slice 4

1. Keep the benchmark gate executable outside `TextEngineCore`.

Slice 3 succeeded because performance infrastructure did not leak into the embedded-compatible core.

2. Choose one remaining product risk, not several.

The next slice should not combine CI wiring, real storage adapters, memory profiling, and variable-height layout. Each has different failure modes.

3. Do not start variable-height layout until the next performance proof is chosen.

Variable-height layout will make invalidation, prefix sums, and measurement caches part of the product surface. Starting that before deciding how to test realistic storage or CI variance would make regressions harder to attribute.

4. Keep real storage outside the core.

If Slice 4 touches realistic document data, it should use a benchmark or fixture target. It should not add file, rope, or piece-table ownership to `TextEngineCore`.

5. Turn local guarantees into enforced guarantees when the environment is known.

If the repository has a stable CI provider, the Slice 3 gate is ready to wire in. If the CI provider is not known, realistic provider proof is a lower-assumption next step.

## Slice 4 Candidate Options

### Option A: CI Wiring For The Benchmark Gate

Add repository CI configuration that runs the release benchmark gate and blocks merge on failure.

Suggested scope:

- Add one CI workflow for host SwiftPM verification.
- Run `swift test`.
- Run `swift run -c release ViewportBenchmarks -- --gate`.
- Record the intended Swift/Xcode/macOS runner assumptions.
- Keep cross-target compile checks either in the same workflow only if the toolchains are available or explicitly out of scope.
- Do not add baseline comparison or budget tightening in the same slice.

This directly closes the remaining merge-blocking part of the product brief, but it depends on knowing which CI system and runner shape the project will actually use.

### Option B: Realistic Provider Benchmark Outside Core

Add a non-core benchmark or fixture that models a realistic large document source and runs the existing fixed-height pipeline against it.

Suggested scope:

- Keep `TextEngineCore` unchanged.
- Add a benchmark-only provider that represents 100k+ lines and at least 10 MB of text payload.
- Prefer a lightweight reference-backed provider shape so `DocumentLineCursor` does not copy large storage by value.
- Measure provider-boundary overhead separately from the synthetic provider path.
- Keep file IO, async loading, caching, ropes, and piece tables out of scope unless one representation is deliberately chosen as the fixture.
- Record benchmark output and memory expectations.

This closes the largest remaining product-performance gap after Slice 3 without needing CI-provider decisions.

### Option C: Allocation Or Memory Regression Gate

Add a focused memory/allocation check for the current fixed-height pipeline.

Suggested scope:

- Prove the benchmark provider does not allocate document-sized storage.
- Add a repeatable allocation or peak-memory measurement strategy for host runs.
- Keep budgets conservative.
- Avoid real storage adapter design in the same slice.

This strengthens the memory side of the product brief, but measurement tooling can be platform-specific and noisy. It is better after either CI assumptions or realistic provider shape is clearer.

### Option D: Variable-Height Layout Foundation

Begin the next major product capability: mapping logical line indexes to measured heights and invalidating layout ranges.

Suggested scope:

- Design a minimal variable-height index structure.
- Preserve fixed-height fast path behavior.
- Define update/invalidation semantics.
- Add tests for prefix-height lookup, offset-to-line mapping, and localized invalidation.

This moves functionality forward, but it is the highest-risk option. It should wait until either CI gating or realistic provider behavior is settled.

## Recommended Slice 4 Selection

Recommended: Option B, realistic provider benchmark outside core, unless a concrete CI provider is already decided.

Reasoning:

- Slice 3 already created a local merge-blocking command, but the repository has no CI configuration or CI-provider context.
- The product brief still names stable scroll performance on 100k+ lines and >10 MB documents; Slice 3 proves large line counts, not large text payload behavior.
- A realistic provider benchmark can reuse the Slice 3 gate machinery while keeping storage outside `TextEngineCore`.
- This option keeps variable-height layout out of the picture until fixed-height provider performance is better understood.

If the CI provider is already known outside the repository, choose Option A instead. In that case Slice 4 should be deliberately small: host CI workflow plus `swift test` plus `swift run -c release ViewportBenchmarks -- --gate`, with no baseline comparison or storage work.

## Slice 3 Review Conclusion

Slice 3 is a clean completion of the fixed-height headless pipeline benchmark gate. It upgrades the benchmark from range-only timing to a full core-side traversal measurement, adds explicit p95/p99 budgets, preserves the old diagnostic path, and produces a command that can fail on regression.

The slice still stops short of an actual repository merge blocker because no CI workflow exists. It also intentionally uses a synthetic provider, so it does not yet prove >10 MB document behavior.

The most natural next product slice is a realistic provider benchmark outside `TextEngineCore`, unless the CI environment is already decided and ready for a narrow gate-wiring slice.
