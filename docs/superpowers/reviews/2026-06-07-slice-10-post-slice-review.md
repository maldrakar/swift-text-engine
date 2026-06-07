# Slice 10 Post-Slice Review

Date: 2026-06-07

## Scope Reviewed

This review covers Slice 10: realistic-provider gate calibration.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/reviews/2026-06-07-slice-9-post-slice-review.md`
- `docs/superpowers/specs/2026-06-07-realistic-provider-gate-calibration-design.md`
- `docs/superpowers/plans/2026-06-07-realistic-provider-gate-calibration.md`
- `Sources/ViewportBenchmarks/BenchmarkModels.swift`
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- `Sources/ViewportBenchmarks/BenchmarkSupport.swift`
- `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`
- `.github/workflows/swift-ci.yml`
- `docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md`
- local git commit history for Slice 10
- fresh local host tests, release build, synthetic gate, realistic-provider
  observational run, realistic-provider gate, memory-shape diagnostic, RSS
  memory-observation diagnostic, representative invalid CLI checks, workflow
  scan, and non-goal diff checks

No `AGENTS.md`, `CLAUDE.md`, or top-level `README.md` project-conventions file
is present in the repository, so review uses the product brief, existing slice
documents, and universal review heuristics.

## Product Brief Alignment

The product brief asks for a headless text rendering engine core with stable
scroll performance on 100k+ lines and >10 MB documents, strict virtualization,
external document storage, bounded core-owned memory, iOS/WASM source
compatibility, and regression benchmarks that block merge when performance
degrades.

Slice 10 addresses the remaining source-controlled latency-proof gap for the
existing fixed-height, large-text provider path. Before this slice, the
synthetic benchmark gate enforced p95/p99 budgets, while the realistic 100,000
line, 11.2 MB provider benchmark was observational only. Slice 10 makes this
command valid:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

The new gate uses calibrated local budgets:

```text
budget_p95_ns=20000
budget_p99_ns=50000
```

Slice 10 directly addresses these project needs:

- The existing realistic 100,000-line, 11.2 MB large-text provider benchmark
  now has p95/p99 budgets.
- `--realistic-provider` remains observational by default and does not print
  budget or gate fields.
- `--realistic-provider --gate` prints `budget_p95_ns`, `budget_p99_ns`, and
  `gate=pass|fail`.
- The gate exits non-zero when traversal failures or p95/p99 budget failures
  occur.
- The synthetic gate, memory-shape diagnostic, and RSS observation diagnostic
  keep their existing behavior.
- `TextEngineCore`, `Tests`, and `Package.swift` are unchanged.

Slice 10 intentionally does not yet prove or enforce:

- hosted-runner realistic-provider gate stability;
- a GitHub Actions realistic-provider gate step;
- repository settings that require `Swift CI` before `main` can change;
- RSS, heap, malloc, allocation-count, or peak-memory hard budgets;
- checked-in baseline-relative benchmark gating;
- cross-target CI for iOS, WASM, or embedded WASM;
- file-backed, memory-mapped, rope, piece-table, or editor-buffer storage;
- variable-height layout, localized invalidation, text shaping, rasterization,
  or UI-framework integration.

Those remain out of scope for Slice 10.

## Delivered Design

The public benchmark command surface is now:

```text
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

The Slice 10 source change is intentionally small:

- `BenchmarkModels.swift` adds p95/p99 budget fields to
  `RealisticProviderScenario`, matching the existing synthetic
  `BenchmarkScenario` shape.
- `BenchmarkOptions.swift` allows `--realistic-provider --gate`, updates usage
  text, and keeps range-only, memory-shape, and memory-observation gate
  combinations invalid.
- `BenchmarkProgram.swift` passes `options.enforceGate` into
  `runRealisticProviderBenchmarks(enforceGate:)`.
- `RealisticProviderBenchmark.swift` stores the calibrated budgets on the
  existing `100k_lines_10mb_text` scenario, reuses `BenchmarkSummary` and
  `formatSummary`, and returns failure only when gated summaries fail or
  ungated traversal records missing-provider failures.
- `.github/workflows/swift-ci.yml` is unchanged in the final tree after the
  temporary realistic-provider gate step was removed.

The resulting `ViewportBenchmarks` file sizes are:

```text
      54 Sources/ViewportBenchmarks/BenchmarkModels.swift
     119 Sources/ViewportBenchmarks/BenchmarkOptions.swift
      28 Sources/ViewportBenchmarks/BenchmarkProgram.swift
      98 Sources/ViewportBenchmarks/BenchmarkSupport.swift
     391 Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
     360 Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
     197 Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
     173 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
      10 Sources/ViewportBenchmarks/main.swift
    1430 total
```

Slice 10 preserves the Slice 8 decomposition. `main.swift` remains process
entry only, and the realistic-provider gate logic stays in the
realistic-provider benchmark file.

## Verification Evidence Reviewed

The Slice 10 verification document records passing results for:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

It also records a temporary forced-failure check with budgets set to `1`,
which exited non-zero with `gate=fail`, followed by restoration of the
selected `20000` and `50000` budgets.

The verification document records the hosted-runner decision:

```text
ci_enforcement=deferred
reason=hosted-samples-unavailable
hosted_gate_samples_recorded=0
workflow_step_final_state=not_added
```

GitHub access existed and the feature branch was pushed, but branch-specific
Swift CI run queries returned no runs. The workflow triggers on pull requests
and pushes to `main`, so the branch push did not provide same-environment
hosted-runner samples.

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
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1292 p99_ns=1368 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5215 p99_ns=5390 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17051 p99_ns=17736 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Result: pass, with no budget or gate fields.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5498 p99_ns=5680 failures=0 checksum=756321289736960
```

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Result: pass.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5432 p99_ns=5604 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass.

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
```

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Result: pass.

```text
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1818624 rss_after_provider_setup_bytes=1818624 rss_after_core_operation_bytes=2015232 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=196608 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=2097152 rss_after_core_operation_bytes=2097152 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=13336576 rss_after_core_operation_bytes=13336576 rss_page_size_bytes=16384 rss_provider_delta_bytes=11239424 rss_core_operation_delta_bytes=0 observation=pass checksum=596788650
```

Representative invalid CLI checks:

```text
swift run -c release ViewportBenchmarks -- --range-only --gate
```

Result: expected non-zero exit with:

```text
error=--range-only cannot be combined with --gate
```

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape
```

Result: expected non-zero exit with:

```text
error=--realistic-provider cannot be combined with --memory-shape
```

```text
swift run -c release ViewportBenchmarks -- --memory-observation --gate
```

Result: expected non-zero exit with:

```text
error=--memory-observation cannot be combined with --gate
```

```text
swift run -c release ViewportBenchmarks -- --unknown
```

Result: expected non-zero exit with:

```text
error=unknown argument --unknown
```

Workflow scan:

```text
rg -n "Run synthetic benchmark gate|Run memory shape diagnostic|Run RSS memory observation diagnostic|Run realistic provider benchmark gate|--realistic-provider --gate|--memory-observation" .github/workflows/swift-ci.yml
```

Result:

```text
35:      - name: Run synthetic benchmark gate
38:      - name: Run memory shape diagnostic
41:      - name: Run RSS memory observation diagnostic
42:        run: swift run -c release ViewportBenchmarks -- --memory-observation
```

Non-goal check:

```text
git diff dc83ca9..HEAD -- Sources/TextEngineCore Tests Package.swift
```

Result: no output.

## Git History

The Slice 10 commit sequence is:

```text
8dd6ecf docs: design realistic provider gate calibration
9d2966a docs: clarify realistic gate enforcement constraints
dc83ca9 docs: plan realistic provider gate calibration
807e63c feat: gate realistic provider benchmark
2cf4b62 ci: run realistic provider benchmark gate
0e5ef82 ci: defer realistic provider benchmark gate
9a3ea6e docs: record realistic provider gate verification
```

The Slice 10 source implementation commit is focused:

```text
807e63c feat: gate realistic provider benchmark
4 files changed, 15 insertions(+), 12 deletions(-)
```

It changes only:

```text
Sources/ViewportBenchmarks/BenchmarkModels.swift
Sources/ViewportBenchmarks/BenchmarkOptions.swift
Sources/ViewportBenchmarks/BenchmarkProgram.swift
Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
```

The temporary workflow-enforcement commit was explicitly reverted by the
defer commit:

```text
0e5ef82 ci: defer realistic provider benchmark gate
.github/workflows/swift-ci.yml | 3 ---
```

The branch merged by PR #2 also includes the Slice 9 post-slice review commits
before the Slice 10 design commits. That makes the merge diff contain a prior
review document, but it does not alter the Slice 10 source or workflow outcome.

## Code Review Findings

No confirmed P0/P1/P2/P3 code findings were found for Slice 10.

The implementation matches the approved design:

- `--realistic-provider --gate` is valid and uses the existing `--gate`
  meaning instead of adding a redundant top-level mode.
- Ungated `--realistic-provider` output remains observational and omits budget
  and gate fields.
- Gated realistic-provider output reuses `BenchmarkSummary`, `passesGate`, and
  `formatSummary`.
- The synthetic gate, memory-shape diagnostic, and RSS observation diagnostic
  keep their prior CLI boundaries.
- Final workflow state does not include the realistic-provider gate step
  because hosted-runner evidence was unavailable.
- Core source, tests, and package manifest are untouched.

## Risks And Gaps

### Hosted-Runner Enforcement Is Still Deferred

Slice 10 created the local gateable command, but the final GitHub Actions
workflow does not run it. That is the right conservative outcome given the
recorded evidence: hosted-runner samples were not collected, and the design
explicitly prohibited adding the workflow step based only on local samples.

This means the realistic-provider p95/p99 gate is source-controlled but not
yet automated in CI.

### The Calibration Attempt Was Inconclusive

The verification document records `hosted-samples-unavailable` because the
pushed feature branch did not produce branch-specific Swift CI runs. The
workflow currently runs on pull requests and pushes to `main`, not on arbitrary
feature branch pushes.

The next hosted-runner slice should not repeat a branch-only push as the
sampling mechanism. It needs an actual pull request run, a deliberate
`workflow_dispatch` calibration entrypoint, or a temporary calibration workflow
with documented cleanup.

### Local Budgets Are Conservative But Local-Only

The selected `20000`/`50000` ns budgets have wide margin against local samples
around 5.4 to 5.8 microseconds. That is useful for developer machines, but it
does not prove macOS hosted-runner variance or queue/load sensitivity.

### Merge Blocking Remains Repository-Setting Dependent

`Swift CI` already runs host tests, the synthetic benchmark gate, memory-shape
diagnostics, and RSS memory observation. Slice 10 does not change the external
repository-policy gap: a failing workflow only blocks merge if repository
settings require that status check.

### Cross-Target CI Still Does Not Run On GitHub

Earlier slices locally verified iOS, WASM, and embedded WASM compatibility for
`TextEngineCore`. Slice 10 correctly skipped cross-target checks because core
source did not change. Continuous cross-target CI remains useful before or
during the next public core API change.

### Variable-Height Layout Remains Deferred

The fixed-height path now has synthetic latency gates, realistic-provider
coverage, a local realistic-provider gate, deterministic memory-shape evidence,
and RSS observation. Variable-height layout remains the largest functional
expansion and should not be mixed with CI calibration or repository-policy
work.

## Lessons For Slice 11

1. Do not repeat the Slice 10 hosted-sampling mechanism.

A feature-branch push is not enough under the current workflow triggers. If
hosted-runner evidence is the next goal, the slice should use a pull request
run, `workflow_dispatch`, or a temporary calibration workflow with the run IDs
recorded in verification.

2. Keep CI enforcement conditional on hosted evidence.

The local gate is useful, but the workflow should only run
`--realistic-provider --gate` after same-environment samples show enough
margin. Do not convert local values directly into a hosted-runner failure step.

3. Separate proof closure from functional expansion.

Realistic-provider CI enforcement, branch protection, cross-target CI, and
variable-height layout are different kinds of work. Slice 11 should choose one
priority explicitly.

4. Treat repository merge blocking as operational policy, not benchmark code.

Adding a workflow step does not make it a required status check. Branch
protection or rulesets need their own explicit slice and readback evidence.

5. Preserve the fixed-height fast path before adding variable-height state.

If Slice 11 starts variable-height layout, it needs fixed-height compatibility
tests and cross-target compile checks. It should not also change benchmark
budgets or workflow enforcement.

## Slice 11 Candidate Options

### Option A: Hosted-Runner Realistic Gate Calibration And CI Wiring

Collect same-environment hosted-runner samples for the new realistic-provider
gate and add the workflow step only if the samples support enforcement.

Suggested scope:

- Add or use a deliberate hosted sampling path: a pull request run,
  `workflow_dispatch`, or a temporary calibration workflow.
- Run at least three macOS hosted-runner samples of
  `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`.
- Record run IDs, p95/p99 values, conclusions, and the exact workflow trigger
  used.
- Add a final `Run realistic provider benchmark gate` workflow step only if
  hosted samples stay within the existing `20000`/`50000` ns budgets.
- If hosted variance is too high or samples still cannot be collected, leave
  workflow enforcement deferred and record the reason.
- Keep Swift source, memory budgets, branch protection, cross-target CI, and
  variable-height layout out of scope.

This is the strongest Slice 11 candidate if the priority is finishing the
fixed-height performance-proof envelope.

### Option B: Variable-Height Layout Foundation

Start the next major core capability: variable-height line indexing and
localized invalidation.

Suggested scope:

- Define the smallest height-index or measurement-cache boundary.
- Preserve the current fixed-height fast path and public behavior.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests for height changes.
- Repeat host, iOS, WASM, and embedded WASM verification for public core API
  or portability-sensitive source changes.
- Keep realistic-provider CI enforcement, branch protection, storage adapters,
  and memory-budget enforcement out of scope.

This is the strongest Slice 11 candidate if the project deliberately wants to
shift from fixed-height proof to functional expansion.

### Option C: Cross-Target CI For `TextEngineCore`

Move existing local portability checks into GitHub Actions where runner support
is reliable.

Suggested scope:

- Add the cheapest reliable iOS compile check for `TextEngineCore`.
- Investigate hosted-runner setup for WASM and embedded WASM Swift SDKs.
- Keep `ViewportBenchmarks` host-only.
- Do not change public core API in the same slice.
- Record exact runner images, toolchain versions, and skipped targets if any
  SDK is unavailable.

This improves continuous portability confidence, but it is best timed before
or with the next public core API change.

### Option D: Legacy Branch Protection Or Required Checks

Close the operational merge-blocking gap if GitHub allows it for the current
repository state.

Suggested scope:

- Inspect current branch protection and ruleset state through the GitHub API.
- If legacy branch protection is available, require the existing `Swift CI`
  status context.
- Record API readback after any change.
- Keep Swift source, benchmark code, workflow YAML, and performance budgets
  unchanged.

This is valuable only if repository enforcement is explicitly the next
priority.

### Option E: Memory Observation Variance Or Allocator Signal

Extend the RSS observation layer into a variance study or a better
allocator-level signal.

Suggested scope:

- Repeat `--memory-observation` locally and on hosted runners if available.
- Decide whether RSS is too noisy for thresholds.
- Investigate a focused malloc, peak RSS, or allocation-count signal for the
  host executable if it can be collected reliably.
- Keep any new output observational unless stability is demonstrated.
- Do not change realistic-provider latency budgets or core layout behavior.

This continues the memory-proof thread, but it is less urgent than closing the
hosted-runner gap for the realistic-provider gate unless memory-budget
enforcement is explicitly selected.

## Recommended Slice 11 Selection

Recommended: Option A, hosted-runner realistic gate calibration and CI wiring.

Reasoning:

- Slice 10 intentionally stopped at a local gate because hosted-runner samples
  were unavailable. The direct remaining gap is the same gate in the same CI
  environment that will report regressions.
- This ties directly to the brief's requirement for stable scroll performance
  on 100k+ lines and >10 MB documents, and to automated regression detection.
- The implementation risk is lower than variable-height layout because it can
  avoid core source and public API changes.
- The work is bounded: either hosted samples support the existing budgets and
  the workflow gains a step, or enforcement stays deferred with stronger
  evidence.
- It should fix the process weakness found in Slice 10 by using a real PR run,
  `workflow_dispatch`, or a temporary calibration workflow instead of a
  branch-only push.

Choose Option B instead only if the project is ready to shift from proof
closure to functional expansion. Choose Option D instead only if repository
merge blocking is the immediate priority. Defer Option C until portability CI
is needed for the next public core API change, and defer Option E unless memory
budget enforcement is explicitly selected.

## Slice 10 Review Conclusion

Slice 10 cleanly completes its approved source-controlled scope. It makes the
existing realistic large-text provider benchmark gateable, preserves
observational output by default, keeps unrelated benchmark modes stable, leaves
core source and tests untouched, and correctly defers CI enforcement because no
hosted-runner samples were available.

The slice should be counted as local realistic-provider latency-gate support,
not as hosted CI enforcement or merge blocking. Slice 11 should usually collect
hosted-runner evidence and wire the realistic-provider gate into CI if the data
supports it, unless the project explicitly chooses variable-height layout or
repository policy work next.
