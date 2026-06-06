# Slice 7 Post-Slice Review

Date: 2026-06-06

## Scope Reviewed

This review covers Slice 7: core-owned memory shape diagnostic and CI wiring.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/reviews/2026-06-06-slice-6-post-slice-review.md`
- `docs/superpowers/specs/2026-06-06-core-owned-memory-shape-design.md`
- `docs/superpowers/plans/2026-06-06-core-owned-memory-shape.md`
- `Sources/ViewportBenchmarks/main.swift`
- `.github/workflows/swift-ci.yml`
- `docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md`
- local git commit history
- fresh local host tests, benchmarks, memory-shape diagnostic, workflow scan,
  and cross-target core compile checks

No `AGENTS.md`, `CLAUDE.md`, or top-level `README.md` project-conventions file
is present in the repository, so code review uses the product brief, existing
slice documents, and universal review heuristics.

## Product Brief Alignment

The product brief asks for a headless text rendering engine core with stable
scroll performance, strict virtualization, external document storage, iOS/WASM
source compatibility, and regression benchmarks that block merge when
performance degrades.

Slice 7 narrows that product goal to deterministic evidence for the memory
ownership claim in the current fixed-height path. The slice adds:

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

The new command reports modelled memory-shape fields for synthetic and
realistic-provider scenarios, separates core-owned fields from provider-owned
document bytes, and exits non-zero when deterministic invariants fail. The
existing GitHub Actions workflow now runs this diagnostic after the synthetic
benchmark gate.

Slice 7 directly addresses these brief requirements:

- The current fixed-height core has a source-controlled diagnostic proving that
  reported core-owned state does not grow with total line count for the same
  visible and overscan shape.
- The diagnostic checks both 100,000-line and 1,000,000-line synthetic
  scenarios.
- The realistic-provider scenario keeps the 11.2 MB document payload classified
  as provider-owned memory, not core-owned memory.
- Strict virtualization remains tied to the buffered range: all memory-shape
  scenarios report `visible_lines=80`, `buffered_lines=90`, and
  `touched_lines=90`.
- The diagnostic has CI coverage through the existing `Swift CI` workflow.
- `TextEngineCore`, `Tests`, and `Package.swift` are unchanged in the Slice 7
  diff.
- Host, WASM, embedded WASM, iOS device, and iOS simulator compile checks for
  `TextEngineCore` still pass locally.

Slice 7 does not yet prove these brief requirements:

- RSS, heap, malloc, allocation-count, or peak-memory budgets.
- Repository settings that require `Swift CI` before `main` can change.
- Realistic-provider p95/p99 budgets.
- Hosted-runner variance for the realistic-provider benchmark.
- File-backed, memory-mapped, rope, piece-table, or editor-buffer storage.
- Variable-height layout, localized invalidation, text shaping, rasterization,
  or UI-framework integration.

Those remain out of scope for Slice 7.

## Delivered Design

The Slice 7 design adds one host-only diagnostic mode to `ViewportBenchmarks`.
The CLI surface is now:

```text
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
```

The invalid combination:

```text
swift run -c release ViewportBenchmarks -- --memory-shape --gate
```

correctly prints a clear error and exits non-zero.

The memory-shape diagnostic covers three scenarios:

- `100k_lines_80_visible_overscan_5`, synthetic provider;
- `1m_lines_80_visible_overscan_5`, synthetic provider;
- `100k_lines_10mb_text`, realistic large-text provider.

The first two scenarios deliberately use the same visible and overscan shape.
That is the important comparison: total line count changes from 100,000 to
1,000,000, but `core_owned_bytes` stays equal.

The workflow integration is intentionally narrow:

```yaml
- name: Run memory shape diagnostic
  run: swift run -c release ViewportBenchmarks -- --memory-shape
```

The job name remains:

```text
Host tests and benchmark gate
```

That preserves the status-check context Slice 6 planned to require later.

## Implementation Assessment

The implementation matches the approved Slice 7 scope and preserves the core
boundary.

Strengths:

- `TextEngineCore` did not gain benchmark fixtures, storage adapters, Darwin
  imports, Foundation dependencies, or diagnostic-only public API.
- The diagnostic lives entirely in the host-only `ViewportBenchmarks`
  executable.
- The 100k and 1m synthetic memory-shape scenarios report the same
  `core_owned_bytes=74`.
- The realistic-provider scenario reports `document_bytes=11200000` and
  `provider_owned_bytes=11200000`.
- All memory-shape summaries report `invariant=pass`.
- The diagnostic output is line-oriented and grep-friendly.
- CLI parsing rejects unsupported memory-shape flag combinations.
- CI now runs the memory-shape command immediately after the existing synthetic
  benchmark gate.
- The Slice 7 source diff does not touch `Sources/TextEngineCore`, `Tests`, or
  `Package.swift`.

Important design choices:

- The byte estimate is a deterministic ownership model, not a process memory
  profiler.
- The diagnostic checks the ownership boundary and buffered traversal shape,
  not allocator behavior.
- `benchmark_owned_bytes=0` means the diagnostic is not reporting the executable
  target's transient bookkeeping as a product invariant.
- The realistic 11.2 MB fixture remains a provider-owned benchmark payload, not
  core-owned state.

Those choices fit Slice 7. The slice turns a product-brief memory claim into
repeatable repository evidence without pretending to be a full memory profiler.

## Code Review Finding

### P1 / `maintainability`: `ViewportBenchmarks/main.swift` Crossed 1,000 Lines

Slice 7 grew `Sources/ViewportBenchmarks/main.swift` from 621 lines at
`82a829d` to 1,005 lines at `fafdf49`.

Evidence:

```text
git show 82a829d:Sources/ViewportBenchmarks/main.swift | wc -l
     621
git show fafdf49:Sources/ViewportBenchmarks/main.swift | wc -l
    1005
```

The trigger is the new memory-shape diagnostic block in
`Sources/ViewportBenchmarks/main.swift`, especially the scenario, traversal,
summary, formatting, and runner helpers added around lines 153-887.

Production impact:

- The benchmark executable now mixes CLI parsing, synthetic latency benchmarks,
  realistic-provider fixture code, memory-shape modelling, output formatting,
  and process entry in one file.
- The next benchmark or diagnostic slice will be harder to review safely
  because unrelated benchmark concerns share one 1,000-line surface.
- More modes added in the same file will make it easier to break an existing
  CLI path while changing a different diagnostic.

Suggested fix:

- Split `ViewportBenchmarks` before adding another benchmark mode.
- Keep behavior identical, but move focused units into separate files such as
  `BenchmarkOptions.swift`, `BenchmarkScenarios.swift`,
  `SyntheticBenchmarks.swift`, `RealisticProviderBenchmark.swift`, and
  `MemoryShapeDiagnostics.swift`.
- Leave `main.swift` as a small entry point that parses arguments, dispatches a
  mode, and exits.

This is not a correctness failure in Slice 7, but it is a real maintainability
blocker for the next slice.

## Test And Verification Assessment

Fresh local verification was run for this review on 2026-06-06.

Host tests:

```text
swift test
```

Result: pass, 39 XCTest tests, 0 failures.

Release build:

```text
swift build -c release
```

Result: pass.

Default pipeline benchmark:

```text
swift run -c release ViewportBenchmarks
```

Result: pass.

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1354 p99_ns=1533 failures=0 checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5208 p99_ns=5503 failures=0 checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17152 p99_ns=18173 failures=0 checksum=18852477646272000
```

Range-only benchmark:

```text
swift run -c release ViewportBenchmarks -- --range-only
```

Result: pass.

```text
mode=range_only scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=9 failures=0 checksum=5114982400
mode=range_only scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=9 failures=0 checksum=511488422400
mode=range_only scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=9 failures=0 checksum=5114881152000
```

Synthetic benchmark gate:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Result: pass.

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1292 p99_ns=1396 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5694 p99_ns=6229 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17963 p99_ns=18554 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

The fresh synthetic gate still has substantial headroom:

- `1k_lines_20_visible_overscan_0`: p95 is about 6.5% of budget; p99 is about
  2.8% of budget.
- `100k_lines_80_visible_overscan_5`: p95 is about 11.4% of budget; p99 is
  about 6.2% of budget.
- `1m_lines_200_visible_overscan_50`: p95 is about 18.0% of budget; p99 is
  about 9.3% of budget.

Realistic provider benchmark:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Result: pass.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=6042 p99_ns=6541 failures=0 checksum=756321289736960
```

Memory-shape diagnostic:

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass.

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
```

Invalid memory-shape gate:

```text
swift run -c release ViewportBenchmarks -- --memory-shape --gate
```

Result: expected non-zero exit.

```text
error=--memory-shape cannot be combined with --gate
```

Workflow scan:

```text
rg -n "Run synthetic benchmark gate|Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml
```

Result: pass.

```text
18:    name: Host tests and benchmark gate
35:      - name: Run synthetic benchmark gate
38:      - name: Run memory shape diagnostic
39:        run: swift run -c release ViewportBenchmarks -- --memory-shape
```

Core source non-goal check:

```text
git diff 82a829d..fafdf49 -- Sources/TextEngineCore Package.swift Tests
```

Result: no output.

Cross-target `TextEngineCore` verification:

```text
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
```

Result: all pass. The iOS device and simulator compiles emitted no stdout or
stderr and exited successfully.

## Commit History Notes

The Slice 7 implementation history is:

- `docs: design core-owned memory shape diagnostic`
- `docs: plan core-owned memory shape diagnostic`
- `feat: add memory shape diagnostic`
- `ci: run memory shape diagnostic`
- `docs: record memory shape verification`

The final Slice 7 implementation diff from the Slice 6 deferral commit
`82a829d` to the Slice 7 verification commit `fafdf49` contains:

```text
.github/workflows/swift-ci.yml
Sources/ViewportBenchmarks/main.swift
docs/superpowers/plans/2026-06-06-core-owned-memory-shape.md
docs/superpowers/specs/2026-06-06-core-owned-memory-shape-design.md
docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md
```

The current `main` history also contains `docs: add slice 6 post-slice review`
after the Slice 7 verification commit. That is a documentation ordering
blemish, not a source-code risk for Slice 7.

## Risks And Gaps

### Benchmark Executable Is Now Too Large

`Sources/ViewportBenchmarks/main.swift` crossed the 1,000-line ceiling during
Slice 7. This is the only confirmed code-review finding in this post-slice
review.

The immediate Slice 7 behavior is correct, but the next benchmark or diagnostic
change should not pile more code into this file. The benchmark target needs a
small decomposition slice before more feature work lands there.

### Memory Shape Is Deterministic, Not Allocator-Level

The diagnostic proves a structural ownership invariant. It does not measure
RSS, heap, malloc traffic, peak memory, or allocation count.

That is acceptable for Slice 7 because the approved design was deliberately
deterministic. It still leaves allocator-level memory evidence as a future
slice.

### Realistic Provider Still Uses A Simple In-Memory Fixture

The large-text provider is useful because it makes caller-owned document bytes
visible and keeps access fixed-width and deterministic. It does not prove a
production representation such as a memory-mapped file, rope, piece table, or
editor buffer.

### CI Still Covers Host Only

The workflow runs host tests, the synthetic benchmark gate, and the memory-shape
diagnostic. Cross-target checks remain local verification, not GitHub Actions
jobs.

### Merge Blocking Is Still Repository-Setting Dependent

Slice 7 improved the `Swift CI` job, but Slice 6 already showed that repository
rulesets are blocked for the current private repository state. The workflow can
fail, but the repository has not proven that a failing check blocks `main`.

### Variable-Height Layout Remains Deferred

The fixed-height path now has stronger performance and memory-shape evidence.
Variable-height layout remains the largest functional expansion and should not
be mixed with benchmark executable cleanup.

## Lessons For Slice 8

1. Fix the benchmark target shape before adding another mode.

`ViewportBenchmarks/main.swift` now contains too many concerns. More benchmark
or diagnostic work in the same file will make future reviews noisier and risk
accidental CLI regressions.

2. Keep decomposition behavior-preserving.

The Slice 8 cleanup should not change latency budgets, memory-shape fields,
scenario definitions, workflow commands, or public `TextEngineCore` API.

3. Treat Slice 7 as a baseline, not the end of memory work.

The deterministic ownership model is valuable. It should become the stable
baseline for later RSS, heap, allocation-count, or peak-memory diagnostics.

4. Do not retry blocked GitHub rulesets without a repository-state change.

Rulesets remain a known external blocker. Slice 8 should not spend source-code
time on the same blocked path.

5. Repeat cross-target checks only when core source or API changes.

Benchmark-target-only cleanup can keep cross-target verification lightweight by
proving `TextEngineCore` source remains unchanged.

## Slice 8 Candidate Options

### Option A: Benchmark Executable Decomposition

Split `Sources/ViewportBenchmarks/main.swift` into focused files without
changing behavior.

Suggested scope:

- Move CLI parsing and mode definitions into `BenchmarkOptions.swift`.
- Move shared scenario definitions and summary formatting into focused support
  files.
- Move synthetic pipeline/range-only benchmark code into
  `SyntheticBenchmarks.swift`.
- Move realistic-provider storage/source/runner code into
  `RealisticProviderBenchmark.swift`.
- Move memory-shape scenario, traversal, invariant, and output code into
  `MemoryShapeDiagnostics.swift`.
- Keep `main.swift` as a small entry point.
- Re-run host tests, all benchmark modes, invalid CLI checks, workflow scan, and
  a no-diff check for `Sources/TextEngineCore`, `Tests`, and `Package.swift`.
- Do not change budget values, output keys, scenario names, checksums, workflow
  commands, or public core API.

This is the strongest Slice 8 candidate because it resolves the confirmed
maintainability finding before more benchmark work accumulates.

### Option B: Allocation Or RSS Observation

Add a host-side observational memory diagnostic beyond the deterministic model.

Suggested scope:

- Measure RSS, peak RSS, malloc statistics, or allocation counts with a clearly
  documented tool boundary.
- Keep the first version observational unless variance is understood.
- Reuse the Slice 7 scenario names and ownership fields.
- Keep CI hard budgets out of scope unless the measurement is stable.
- Avoid production storage adapters and variable-height layout.

This builds directly on Slice 7, but it should wait until the benchmark
executable is easier to modify safely.

### Option C: Cross-Target CI For `TextEngineCore`

Move the existing local iOS/WASM compile checks into GitHub Actions where
runner support is reliable.

Suggested scope:

- Add the cheapest reliable iOS compile check for `TextEngineCore`.
- Investigate hosted-runner support for `swift-6.2.1-RELEASE_wasm` and
  `swift-6.2.1-RELEASE_wasm-embedded`.
- Keep `ViewportBenchmarks` host-only.
- Do not change public core API in the same slice.

This improves compatibility confidence, but it is less urgent than resolving
the new benchmark-target maintainability debt.

### Option D: Realistic Provider Budget Calibration

Calibrate p95/p99 budgets for the realistic-provider benchmark.

Suggested scope:

- Run repeated local realistic-provider samples.
- Optionally gather hosted-runner samples through a temporary diagnostic run.
- Decide whether `--realistic-provider --gate` should become valid or whether a
  separate gate flag is clearer.
- Keep allocation/RSS diagnostics and variable-height layout out of scope.

This strengthens Slice 4, but hard budgets are easier to add after the
benchmark executable is decomposed.

### Option E: Variable-Height Layout Foundation

Start the next major core capability: variable-height line indexing and
localized invalidation.

Suggested scope:

- Define the smallest height-index or measurement-cache boundary.
- Preserve the fixed-height fast path.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests.
- Repeat host, iOS, WASM, and embedded WASM verification for any public core API
  changes.

This is the most meaningful product expansion, but it should wait until Slice 7
cleanup is complete. Variable-height layout will add new state and complexity;
it should not begin with the benchmark target already overgrown.

### Option F: Legacy Branch Protection Instead Of Rulesets

Design and verify a narrow legacy branch-protection rule for `main`, if GitHub
allows it for the current private repository.

Suggested scope:

- Inspect current branch protection through the GitHub API.
- Require the existing `Host tests and benchmark gate` context.
- Require pull requests only if that is accepted repository policy.
- Record API readback.
- Keep Swift source, benchmark code, workflow YAML, and rulesets unchanged.

This could close the operational enforcement gap, but it is an external
repository-policy slice and should not displace source-controlled cleanup unless
merge enforcement is now the top priority.

## Recommended Slice 8 Selection

Recommended: Option A, benchmark executable decomposition.

Reasoning:

- Slice 7 is behaviorally correct and verified, but it introduced a real
  maintainability blocker by pushing `main.swift` over 1,000 lines.
- Every likely next product option touches `ViewportBenchmarks` again:
  allocation/RSS observation, realistic-provider budgets, hosted-runner samples,
  or additional diagnostics.
- A behavior-preserving decomposition is small, verifiable, and protects future
  slices from mixing unrelated benchmark concerns in one file.
- It keeps product behavior stable while paying down exactly the debt Slice 7
  introduced.

After Option A, the next product-oriented candidate should be Option B
allocation/RSS observation if memory proof remains the priority, or Option E
variable-height layout if functional expansion becomes the priority.

Defer Option C until CI setup cost is clear. Defer Option D until the benchmark
target is decomposed. Defer Option F until GitHub repository enforcement is
explicitly selected again.

## Slice 7 Review Conclusion

Slice 7 completes its approved product scope. The project now has a
source-controlled deterministic memory-shape diagnostic, CI runs it after the
synthetic benchmark gate, and fresh local verification passed across host
tests, benchmark modes, memory-shape output, invalid CLI behavior, workflow
scan, and cross-target `TextEngineCore` compilation.

The slice should not be treated as allocator-level memory proof or repository
merge-blocking proof. Its one confirmed code-review issue is maintainability:
the benchmark executable crossed 1,000 lines. Before adding more benchmark or
diagnostic behavior, Slice 8 should decompose `ViewportBenchmarks` without
changing behavior.
