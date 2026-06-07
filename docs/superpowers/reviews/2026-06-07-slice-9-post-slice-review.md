# Slice 9 Post-Slice Review

Date: 2026-06-07

## Scope Reviewed

This review covers Slice 9: RSS memory observation diagnostic and CI wiring.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/reviews/2026-06-06-slice-8-post-slice-review.md`
- `docs/superpowers/specs/2026-06-07-rss-memory-observation-design.md`
- `docs/superpowers/plans/2026-06-07-rss-memory-observation.md`
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`
- `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`
- `.github/workflows/swift-ci.yml`
- `docs/superpowers/verification/2026-06-07-rss-memory-observation.md`
- local git commit history for Slice 9
- fresh local host tests, release build, synthetic gate, memory-shape
  diagnostic, RSS memory-observation diagnostic, invalid RSS gate check,
  workflow scan, and non-goal diff checks

No `AGENTS.md`, `CLAUDE.md`, or top-level `README.md` project-conventions file
is present in the repository, so review uses the product brief, existing slice
documents, and universal review heuristics.

## Product Brief Alignment

The product brief asks for a headless text rendering engine core with stable
scroll performance on 100k+ lines and >10 MB documents, strict virtualization,
external document storage, bounded core-owned memory, iOS/WASM source
compatibility, and regression benchmarks that block merge when performance
degrades.

Slice 9 targets the remaining memory-proof gap for the current fixed-height
path. Slice 7 added deterministic memory-shape evidence. Slice 8 decomposed the
benchmark executable so another diagnostic could be added without growing
`main.swift`. Slice 9 adds the first process-level RSS observation layer:

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Slice 9 directly addresses these project needs:

- RSS snapshots are recorded for the existing 100,000-line synthetic,
  1,000,000-line synthetic, and 100,000-line >10 MB realistic-provider memory
  scenarios.
- Output separates `core_owned_bytes_model` from `provider_owned_bytes`, so the
  realistic 11.2 MB document payload is not misreported as core memory.
- RSS is captured before provider setup, after provider setup, and after one
  deterministic core operation.
- The diagnostic records `rss_page_size_bytes`, making the page-granularity
  limitation visible in output.
- The command exits non-zero if RSS collection or deterministic traversal
  invariants fail.
- `.github/workflows/swift-ci.yml` now runs the RSS observation after
  `--memory-shape`.
- `TextEngineCore`, `Tests`, and `Package.swift` are unchanged by Slice 9.
- `main.swift` remains a 10-line process entrypoint.

Slice 9 intentionally does not yet prove or enforce:

- RSS, heap, malloc, allocation-count, or peak-memory hard budgets.
- Exact attribution of RSS deltas to core-owned bytes.
- Realistic-provider p95/p99 budgets or `--realistic-provider --gate`.
- Repository settings that require `Swift CI` before `main` can change.
- Cross-target CI for iOS, WASM, or embedded WASM.
- File-backed, memory-mapped, rope, piece-table, or editor-buffer storage.
- Variable-height layout, localized invalidation, text shaping, rasterization,
  or UI-framework integration.

Those remain out of scope for Slice 9.

## Delivered Design

The public benchmark command surface is now:

```text
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

The implementation keeps the Slice 8 concern split:

- `BenchmarkOptions.swift` owns `.memoryObservation`, usage text, and invalid
  flag combinations.
- `BenchmarkProgram.swift` dispatches `.memoryObservation` to
  `runMemoryObservationDiagnostics()`.
- `SyntheticBenchmarks.swift` keeps a precondition branch for impossible
  synthetic benchmark dispatch.
- `MemoryObservationDiagnostics.swift` owns Darwin RSS snapshots, scenario
  execution, lifetime retention, summary formatting, and pass/fail aggregation.
- `.github/workflows/swift-ci.yml` runs the new observational command after the
  deterministic memory-shape diagnostic.

The new diagnostic deliberately reuses `memoryShapeScenarios()` so
memory-shape and RSS outputs are comparable. The scenario order is:

```text
100k_lines_80_visible_overscan_5
1m_lines_80_visible_overscan_5
100k_lines_10mb_text
```

The realistic-provider scenario runs last, which avoids its >10 MB provider
allocation polluting the synthetic baselines.

`MemoryObservationDiagnostics.swift` is host-specific and imports `Darwin`.
That stays within the approved boundary because `ViewportBenchmarks` is already
a host-only executable target; `TextEngineCore` remains dependency-free and
Foundation-free.

The resulting `ViewportBenchmarks` file sizes are:

```text
      52 Sources/ViewportBenchmarks/BenchmarkModels.swift
     122 Sources/ViewportBenchmarks/BenchmarkOptions.swift
      28 Sources/ViewportBenchmarks/BenchmarkProgram.swift
      98 Sources/ViewportBenchmarks/BenchmarkSupport.swift
     391 Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
     360 Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
     193 Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
     173 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
      10 Sources/ViewportBenchmarks/main.swift
    1427 total
```

The target grew because Slice 9 added a real diagnostic, but the growth is in a
focused file rather than the process entrypoint.

## Verification Evidence Reviewed

The Slice 9 verification document records passing results for:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
swift run -c release ViewportBenchmarks -- --memory-observation --gate
swift run -c release ViewportBenchmarks -- --memory-observation --range-only
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-observation --memory-shape
```

All four invalid `--memory-observation` combinations exited non-zero with clear
errors, and the workflow scan confirms:

```text
38:      - name: Run memory shape diagnostic
41:      - name: Run RSS memory observation diagnostic
42:        run: swift run -c release ViewportBenchmarks -- --memory-observation
```

Fresh local verification for this review on 2026-06-07:

```text
swift test
```

Result: pass, 39 XCTest tests, 0 failures.

```text
swift build -c release
```

Result: pass.

```text
swift run -c release ViewportBenchmarks -- --gate
```

Result: pass.

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1251 p99_ns=1323 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4978 p99_ns=5248 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16607 p99_ns=17844 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass.

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
```

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Result: pass.

```text
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1835008 rss_after_provider_setup_bytes=1835008 rss_after_core_operation_bytes=2031616 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=196608 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=2080768 rss_after_provider_setup_bytes=2080768 rss_after_core_operation_bytes=2080768 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=13336576 rss_after_core_operation_bytes=13336576 rss_page_size_bytes=16384 rss_provider_delta_bytes=11239424 rss_core_operation_delta_bytes=0 observation=pass checksum=596788650
```

```text
swift run -c release ViewportBenchmarks -- --memory-observation --gate
```

Result: expected non-zero exit with:

```text
error=--memory-observation cannot be combined with --gate
```

Workflow and non-goal checks:

```text
rg -n "Run memory shape diagnostic|Run RSS memory observation diagnostic|--memory-observation" .github/workflows/swift-ci.yml
git diff 3609333..a426b9a -- Sources/TextEngineCore Tests Package.swift
```

Result: workflow order is correct; non-goal diff has no output.

## Git History

The Slice 9 commit sequence is:

```text
3609333 docs: design rss memory observation
fb0277f docs: plan rss memory observation
8fb2186 feat: add rss memory observation diagnostic
ed1ad2d ci: run rss memory observation
a426b9a docs: record rss memory observation verification
```

The Slice 9 source and CI implementation commit is focused:

```text
8fb2186 feat: add rss memory observation diagnostic
4 files changed, 423 insertions(+), 1 deletion(-)
```

It changes only:

```text
Sources/ViewportBenchmarks/BenchmarkOptions.swift
Sources/ViewportBenchmarks/BenchmarkProgram.swift
Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
```

The full Slice 9 range from the Slice 7 review commit through Slice 9
verification adds the design, plan, source diagnostic, workflow step, and
verification document:

```text
.github/workflows/swift-ci.yml
Sources/ViewportBenchmarks/BenchmarkOptions.swift
Sources/ViewportBenchmarks/BenchmarkProgram.swift
Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
docs/superpowers/plans/2026-06-07-rss-memory-observation.md
docs/superpowers/specs/2026-06-07-rss-memory-observation-design.md
docs/superpowers/verification/2026-06-07-rss-memory-observation.md
```

Current `main` contains the later `docs: add slice 8 post-slice review` commit
above Slice 9 verification. That is another documentation ordering blemish, but
it does not alter the Slice 9 source scope or diagnostic behavior.

## Code Review Findings

No confirmed P0/P1/P2/P3 code findings were found for Slice 9.

The implementation matches the approved design:

- RSS collection is isolated in the host-only benchmark executable.
- The core library does not import Darwin or Foundation.
- `--memory-shape` output is unchanged.
- `--memory-observation` is a separate mode, not a mixed extension of
  `--memory-shape`.
- The realistic-provider allocation remains provider-owned in output.
- The post-operation RSS snapshot is taken inside explicit lifetime retention
  for the source, computed range, traversal results, and checksum.
- The diagnostic fails on collection or invariant failures, but not on numeric
  RSS growth alone.
- CI runs the RSS diagnostic without parsing RSS or enforcing noisy thresholds.
- Invalid CLI combinations are rejected with clear existing-style errors.

## Risks And Gaps

### RSS Is Useful But Weak Evidence

RSS is process-level, allocator-dependent, and page-granular. On this machine
the diagnostic reports `rss_page_size_bytes=16384`, while the deterministic
core-owned model is `74` bytes. That means RSS can catch page-scale or
document-sized mistakes, but it cannot validate the exact core-owned model.

Slice 9 correctly keeps RSS observational. Turning these values into hard
budgets needs repeated local and hosted-runner samples, and perhaps a better
allocator-level signal.

### Realistic Provider Latency Is Still Ungated

The project now has realistic-provider latency output, deterministic memory
shape, and RSS observation for the 100,000-line >10 MB fixture. It still does
not have calibrated p95/p99 budgets for that realistic-provider path.

This is the most direct remaining source-controlled proof gap for the product
brief's "100k+ lines / >10 MB" scroll-performance requirement.

### Merge Blocking Remains Repository-Setting Dependent

The `Swift CI` workflow runs host tests, the synthetic benchmark gate,
memory-shape diagnostics, and RSS memory observation. Slice 6 showed that
GitHub rulesets were blocked for the current private repository state. Slice 9
does not change that operational gap.

### Cross-Target CI Still Does Not Run On GitHub

Earlier slices locally verified iOS, WASM, and embedded WASM compatibility for
`TextEngineCore`. Slice 9 correctly skipped cross-target checks because core
source did not change. Continuous cross-target CI remains useful before or
during the next public core API change.

### Variable-Height Layout Remains Deferred

The fixed-height path now has strong synthetic latency gates, realistic-provider
coverage, deterministic memory-shape evidence, and RSS observation. The largest
functional expansion is still variable-height layout and localized invalidation,
but it will add state and public API risk.

## Lessons For Slice 10

1. Do not convert Slice 9 RSS values directly into hard budgets.

The first RSS output is valuable review data, not a stable gate. If memory
budgets are pursued, the slice should first gather repeated local and
hosted-runner samples and define which RSS or allocator signal is actually
stable enough to enforce.

2. Use the new memory evidence to unblock realistic-provider budget work.

The realistic-provider benchmark was intentionally left ungated until memory
shape and runner behavior were clearer. After Slices 7 and 9, the memory side
has enough evidence to make latency-budget calibration the next low-risk proof
slice.

3. Keep the fixed-height proof and variable-height expansion separate.

Variable-height layout should not be mixed with RSS budgets or
realistic-provider budget calibration. It needs its own design, invalidation
tests, compatibility checks, and public API review.

4. Preserve the benchmark file boundaries.

Any Slice 10 benchmark work should stay in the relevant focused file or add one
new narrow file. `main.swift` should remain process entry only.

5. Do not retry repository rulesets without a repository-state change.

Rulesets remain externally blocked. Legacy branch protection is still possible,
but it should be selected explicitly as an operational slice.

## Slice 10 Candidate Options

### Option A: Realistic Provider Budget Calibration

Calibrate p95/p99 budgets for the realistic-provider benchmark and decide how
it should become gateable.

Suggested scope:

- Run repeated local `--realistic-provider` samples.
- Gather hosted-runner samples if the existing GitHub Actions workflow can
  expose enough data without making CI noisy.
- Choose whether `--realistic-provider --gate` should become valid or whether a
  separate explicit gate mode is clearer.
- Add conservative budgets only if variance supports them.
- Preserve existing synthetic gate budgets and RSS output.
- Keep variable-height layout, storage adapters, branch protection, and RSS hard
  budgets out of scope.

This is the strongest Slice 10 candidate if the priority is completing the
fixed-height proof envelope from the product brief.

### Option B: Memory Observation Variance And Allocator Signal

Extend Slice 9 from one RSS observation to a variance study or a better
allocator-level signal.

Suggested scope:

- Repeat `--memory-observation` locally and, if possible, on hosted runners.
- Decide whether RSS is too noisy for any threshold.
- Investigate a focused malloc, peak RSS, or allocation-count signal for the
  host executable if it can be collected reliably.
- Keep any new output observational unless stability is demonstrated.
- Do not change `TextEngineCore` or realistic-provider latency budgets.

This continues the memory-proof thread, but it is less compelling than
realistic-provider latency calibration unless RSS budget enforcement is the
explicit next priority.

### Option C: Variable-Height Layout Foundation

Start the next major core capability: variable-height line indexing and
localized invalidation.

Suggested scope:

- Define the smallest height-index or measurement-cache boundary.
- Preserve the fixed-height fast path and current public behavior.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests for height changes.
- Repeat host, iOS, WASM, and embedded WASM verification for any public core API
  or portability-sensitive source changes.
- Keep realistic-provider budget calibration and memory-budget enforcement out
  of scope.

This is the strongest Slice 10 candidate if the project now wants functional
expansion more than completing fixed-height benchmark gates.

### Option D: Cross-Target CI For `TextEngineCore`

Move existing local compatibility checks into GitHub Actions where runner
support is reliable.

Suggested scope:

- Add the cheapest reliable iOS compile check for `TextEngineCore`.
- Investigate hosted-runner setup for WASM and embedded WASM Swift SDKs.
- Keep `ViewportBenchmarks` host-only.
- Do not change public core API in the same slice.

This improves portability confidence, but it is best timed with the next public
core API change or when CI setup cost is known to be low.

### Option E: Legacy Branch Protection Instead Of Rulesets

Design and verify a narrow legacy branch-protection rule for `main`, if GitHub
allows it for the current private repository.

Suggested scope:

- Inspect current branch protection through the GitHub API.
- Require the existing `Host tests and benchmark gate` context.
- Require pull requests only if that matches repository policy.
- Record API readback.
- Keep Swift source, benchmark code, workflow YAML, and rulesets unchanged.

This could close the operational merge-blocking gap, but it should only be
chosen if repository enforcement is explicitly the next priority.

## Recommended Slice 10 Selection

Recommended: Option A, realistic provider budget calibration.

Reasoning:

- The fixed-height path now has synthetic p95/p99 gates, deterministic
  memory-shape evidence, and RSS observation. The biggest remaining
  source-controlled proof gap is calibrated latency for the existing >10 MB
  realistic-provider path.
- This ties directly to the brief's requirement for stable scroll performance
  on 100k+ lines and >10 MB documents.
- It is smaller and lower-risk than variable-height layout, and it does not
  depend on GitHub repository settings.
- It uses the benchmark decomposition from Slice 8 and the memory evidence from
  Slices 7 and 9 without mixing in new core API.
- It can remain calibration-first if hosted-runner variance is too noisy for a
  hard gate in one slice.

Choose Option C instead only if the project deliberately wants to shift from
fixed-height proof to functional expansion. Defer Option B unless memory-budget
enforcement is explicitly selected. Defer Option D until the next public core
API change or until GitHub runner setup is cheap. Defer Option E until
repository enforcement is selected again or GitHub repository capabilities
change.

## Slice 9 Review Conclusion

Slice 9 cleanly completes its approved scope. It adds a host-only
`--memory-observation` diagnostic, records RSS snapshots beside deterministic
memory-shape fields, keeps provider-owned document bytes separate from the core
model, wires the command into CI without hard RSS budgets, and preserves
`TextEngineCore`, tests, package manifest, and `main.swift`.

The slice should be counted as observational process-memory evidence, not as a
hard memory-budget gate. Slice 10 should usually calibrate realistic-provider
p95/p99 budgets unless the project explicitly chooses to begin variable-height
layout.
