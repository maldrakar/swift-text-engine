# Slice 11 Post-Slice Review

Date: 2026-06-08

## Scope Reviewed

This review covers Slice 11: hosted realistic-provider gate CI calibration.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/reviews/2026-06-07-slice-10-post-slice-review.md`
- `docs/superpowers/specs/2026-06-08-hosted-realistic-provider-gate-ci-design.md`
- `docs/superpowers/plans/2026-06-08-hosted-realistic-provider-gate-ci.md`
- `.github/workflows/swift-ci.yml`
- `docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md`
- PR #4 metadata and GitHub Actions run metadata for the calibration and final
  pull-request heads
- local git commit history for Slice 11
- fresh local host tests, release build, synthetic gate, realistic-provider
  gate, memory-shape diagnostic, RSS memory-observation diagnostic, workflow
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

Slice 11 targets the open hosted-runner evidence gap left by Slice 10. Slice 10
made the realistic 100,000-line, 11.2 MB provider benchmark locally gateable:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Slice 10 correctly did not keep that command in GitHub Actions because the only
pull-request run evaluated a branch head where the temporary step had already
been removed. Slice 11 fixes that process weakness by collecting hosted
pull-request samples from a head commit that still contains the workflow step.

Slice 11 directly addresses these project needs:

- A calibration PR head contained a separate `Run realistic provider benchmark
  gate` workflow step.
- Three accepted macOS hosted-runner samples were collected from that same head
  SHA.
- Each accepted sample ran the realistic-provider gate step and printed
  `gate=pass` with the existing `budget_p95_ns=20000` and
  `budget_p99_ns=50000`.
- The final CI enforcement decision followed the approved 70% margin policy.
- The final workflow kept existing host tests, synthetic benchmark gate,
  memory-shape diagnostic, and RSS memory observation behavior.
- `TextEngineCore`, `Sources/ViewportBenchmarks`, `Tests`, and `Package.swift`
  are unchanged.

Slice 11 intentionally does not yet prove or enforce:

- a hosted realistic-provider gate in the final `Swift CI` workflow;
- repository settings that require `Swift CI` before `main` can change;
- RSS, heap, malloc, allocation-count, or peak-memory hard budgets;
- checked-in or same-runner baseline-relative benchmark comparison;
- cross-target CI for iOS, WASM, or embedded WASM;
- storage adapters such as memory-mapped files, ropes, piece tables, or editor
  buffers;
- variable-height layout, localized invalidation, shaping, rasterization, or
  UI-framework integration.

Those remain out of scope for Slice 11.

## Delivered Design

Slice 11 was an infrastructure and verification slice. It made no final source
or benchmark-code changes.

The calibration workflow step was added only on the PR calibration head:

```yaml
      - name: Run realistic provider benchmark gate
        run: swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

The accepted hosted samples came from:

```text
run_id=27156757711
event=pull_request
head_branch=slice-11-hosted-realistic-provider-gate-ci
head_sha=428a5b72d09112d2ef191a323af281862149bdcb
```

The three accepted realistic-provider output lines were:

```text
sample=1 p95_ns=15664 p99_ns=21660 gate=pass
sample=2 p95_ns=15553 p99_ns=21366 gate=pass
sample=3 p95_ns=19745 p99_ns=25845 gate=pass
```

The approved decision policy required:

```text
max_hosted_p95_ns <= 14000
max_hosted_p99_ns <= 35000
```

The actual hosted maxima were:

```text
max_hosted_p95_ns=19745
max_hosted_p99_ns=25845
p95_margin_ok=false
p99_margin_ok=true
ci_enforcement=deferred
workflow_step_final_state=not_added
workflow_dispatch_final_state=absent
```

That outcome is conservative and matches the approved design. The hosted
samples all passed the current absolute benchmark budgets, but the slowest p95
sample consumed 98.7% of the `20000` ns budget. Keeping that as a PR failure
step would be too close to the cliff for normal hosted-runner variance.

The final workflow state is:

```text
35:      - name: Run synthetic benchmark gate
38:      - name: Run memory shape diagnostic
41:      - name: Run RSS memory observation diagnostic
```

There is no final `workflow_dispatch` trigger and no final
`--realistic-provider --gate` workflow step.

PR #4 was merged on 2026-06-08 with merge commit:

```text
959b1de87f66a732197af5640f198e574899a3aa
```

The final PR-head Swift CI run also passed after the defer and verification
commits:

```text
run_id=27159042924
head_sha=b0952202a830f112d287912969ad38c35e44ef6e
conclusion=success
steps=Run host tests; Run synthetic benchmark gate; Run memory shape diagnostic; Run RSS memory observation diagnostic
```

## Verification Evidence Reviewed

The Slice 11 verification document records passing local preflight and final
local verification for:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

It also records the three accepted hosted samples, the failed p95 margin check,
the deferred enforcement decision, the final workflow scan, and source-boundary
checks.

Fresh local verification for this review on 2026-06-08:

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
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1278 p99_ns=1362 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5223 p99_ns=5463 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16811 p99_ns=17954 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Result: pass.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5523 p99_ns=5779 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
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
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1818624 rss_after_provider_setup_bytes=1818624 rss_after_core_operation_bytes=2015232 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=196608 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=2097152 rss_after_core_operation_bytes=2097152 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=13336576 rss_after_core_operation_bytes=13336576 rss_page_size_bytes=16384 rss_provider_delta_bytes=11239424 rss_core_operation_delta_bytes=0 observation=pass checksum=596788650
```

Workflow and non-goal checks:

```text
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate|workflow_dispatch|Run synthetic benchmark gate|Run memory shape diagnostic|Run RSS memory observation diagnostic" .github/workflows/swift-ci.yml
```

Result:

```text
35:      - name: Run synthetic benchmark gate
38:      - name: Run memory shape diagnostic
41:      - name: Run RSS memory observation diagnostic
```

```text
git diff -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift .github/workflows/swift-ci.yml
```

Result: no output.

GitHub metadata was also rechecked during this review:

- attempts 1, 2, and 3 of run `27156757711` all executed
  `Run realistic provider benchmark gate` at head
  `428a5b72d09112d2ef191a323af281862149bdcb`;
- final PR-head run `27159042924` completed successfully at head
  `b0952202a830f112d287912969ad38c35e44ef6e` without the realistic-provider
  step.

## Git History

The Slice 11 planning and implementation sequence is:

```text
d50d721 docs: design hosted realistic provider gate ci
d854915 docs: revise hosted realistic provider gate ci design
2572894 docs: plan hosted realistic provider gate ci
428a5b7 ci: add realistic provider gate calibration step
0bee2ea ci: defer hosted realistic provider gate
b095220 docs: record hosted realistic gate ci verification
959b1de Merge pull request #4 from arthurbanshchikov/slice-11-hosted-realistic-provider-gate-ci
```

The implementation branch had one temporary workflow-add commit and one
explicit defer commit:

```text
428a5b7 ci: add realistic provider gate calibration step
.github/workflows/swift-ci.yml | 3 +++

0bee2ea ci: defer hosted realistic provider gate
.github/workflows/swift-ci.yml                                      |   3 -
docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md | 213 +++++++++++++++++++++
```

The final merged diff from the Slice 11 plan commit adds only the verification
document:

```text
docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md | 244 +++++++++++++++++++++
```

That is expected because the workflow calibration step was deliberately removed
before merge.

## Code Review Findings

No confirmed P0/P1/P2/P3 code findings were found for Slice 11.

The implementation matches the approved design:

- hosted samples were collected from a pull-request head that still contained
  the realistic-provider gate step;
- each accepted sample includes run attempt metadata, head SHA, step evidence,
  and the exact realistic-provider output line;
- the decision policy was applied without loosening benchmark budgets;
- final CI enforcement was deferred because `p95_margin_ok=false`;
- the final workflow does not contain a branch-only `workflow_dispatch` trigger;
- existing CI steps remain present and ordered;
- Swift source, tests, package manifest, and benchmark budgets are untouched.

## Risks And Gaps

### Hosted Absolute P95 Margin Is Not CI-Safe

The hosted samples passed the absolute gate, but the slowest sample reported:

```text
p95_ns=19745
budget_p95_ns=20000
```

That is below the current budget but above the approved `14000` ns margin
threshold. The final workflow correctly excludes the realistic-provider gate,
but the data says the current absolute hosted signal is too close to its budget
for low-noise CI enforcement.

### Realistic-Provider CI Enforcement Is Still Deferred

The local `--realistic-provider --gate` command remains useful and stable on
this host, but `Swift CI` still does not run it in the final workflow. The
brief's >10 MB realistic-provider latency proof is therefore source-controlled
locally but not yet automated in CI.

### Merge Blocking Remains Repository-Policy Dependent

Even a perfectly stable workflow step only blocks merges if repository policy
requires the corresponding status check. Slice 11 did not change rulesets or
legacy branch protection, and that was correctly outside scope.

### Baseline-Relative Regression Gating Is Still Missing

Slice 11 shows why absolute hosted p95/p99 budgets are a weak enforcement
shape: runner speed and variance can consume nearly all of the p95 budget even
when the code has not changed. The project still lacks a same-runner baseline
comparison that can distinguish actual regressions from slow hardware.

### Cross-Target CI Still Does Not Run On GitHub

Earlier slices locally verified iOS, WASM, and embedded WASM compatibility for
`TextEngineCore`. Slice 11 correctly skipped cross-target checks because no
core source changed. Continuous cross-target CI remains useful before or during
the next public core API change.

### Variable-Height Layout Remains Deferred

The fixed-height path has strong local proof and useful hosted evidence, but
variable-height layout and localized invalidation remain the largest functional
expansion. That work should not be mixed with another benchmark-enforcement
slice.

## Lessons For Slice 12

1. Do not repeat the same absolute hosted gate.

Slice 11 already collected valid hosted evidence. The evidence says the
absolute p95 budget is too close on `macos-latest` for direct CI enforcement
under the approved margin policy. Re-running the same three-sample procedure is
unlikely to change the engineering answer.

2. Separate local budgets from hosted regression semantics.

The local `20000`/`50000` ns realistic-provider budgets remain useful as a
developer smoke gate. Hosted CI needs a shape that compares equivalent runner
conditions or first proves a lower-variance signal.

3. Preserve the calibration discipline.

Any Slice 12 CI work should keep Slice 11's stronger evidence rules: record run
IDs, attempts, head SHAs, exact output lines, final workflow state, and whether
the reported step actually ran.

4. Keep repository policy separate from benchmark mechanics.

Making `Swift CI` fail and making a failing `Swift CI` block merge are different
operations. Slice 12 should choose one explicitly rather than bundling both.

5. Do not mix variable-height layout with benchmark enforcement.

Variable-height layout needs public API and invalidation design. Benchmark CI
work needs runner and comparison design. Combining them would make both harder
to review.

## Slice 12 Candidate Options

### Option A: Hosted Baseline-Relative Realistic Regression Gate

Design and implement a same-runner comparison for the realistic-provider
benchmark instead of enforcing the current absolute p95/p99 values directly on
hosted runners.

Suggested scope:

- Define a pull-request-only hosted comparison between base SHA and head SHA
  for `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`
  or a narrower machine-readable variant of that command.
- Run both measurements on the same GitHub runner job where practical.
- Choose a regression threshold from repeated no-op or documentation-only
  hosted samples.
- Fail CI only when head meaningfully regresses against base, not when the
  runner is globally slow.
- Keep the existing local absolute budgets unchanged.
- Record run IDs, head/base SHAs, raw p95/p99 values, ratio or delta, and the
  final enforcement decision.
- Keep branch protection, cross-target CI, memory hard budgets, storage
  adapters, and variable-height layout out of scope.

This is the strongest Slice 12 candidate if the priority is still the product
brief's regression-benchmark requirement for the >10 MB realistic path.

### Option B: Hosted Realistic Benchmark Variance Study

Keep CI observational and collect a wider hosted sample set before choosing any
enforcement shape.

Suggested scope:

- Run repeated hosted realistic-provider samples across fresh runs and reruns.
- Compare p95/p99 variance, runner image, toolchain version, and job duration.
- Decide whether changing iterations, operations per sample, warmup, or output
  format can produce a lower-noise signal.
- Do not add a failing CI step unless the study produces a clear policy.

This is safer than Option A if the project wants more measurement evidence
before implementing comparison mechanics, but it does not itself close the CI
regression gate.

### Option C: Variable-Height Layout Foundation

Start the next major core capability: variable-height line indexing and
localized invalidation.

Suggested scope:

- Define the smallest height-index or measurement-cache boundary.
- Preserve the current fixed-height fast path and public behavior.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests for height changes.
- Repeat host, iOS, WASM, and embedded WASM verification for public core API or
  portability-sensitive source changes.
- Keep realistic-provider CI enforcement, branch protection, storage adapters,
  and memory-budget enforcement out of scope.

This is the strongest Slice 12 candidate if the project deliberately wants to
shift from proof closure to functional expansion.

### Option D: Cross-Target CI For `TextEngineCore`

Move existing local portability checks into GitHub Actions where runner support
is reliable.

Suggested scope:

- Add the cheapest reliable iOS compile check for `TextEngineCore`.
- Investigate hosted-runner setup for WASM and embedded WASM Swift SDKs.
- Keep `ViewportBenchmarks` host-only.
- Do not change public core API in the same slice.
- Record exact runner images, toolchain versions, and skipped targets if any
  SDK is unavailable.

This improves continuous portability confidence, but it is best timed before or
with the next public core API change.

### Option E: Required Status Check Or Legacy Branch Protection

Close the operational merge-blocking gap for the checks that are already stable.

Suggested scope:

- Inspect current branch protection and ruleset state through the GitHub API.
- If legacy branch protection is available, require the existing `Swift CI`
  status context.
- Record API readback after any change.
- Keep Swift source, benchmark code, workflow YAML, and performance budgets
  unchanged.

This is valuable only if repository enforcement is explicitly the next
priority. It will not make the realistic-provider gate run in CI unless paired
with a separate benchmark-enforcement slice.

### Option F: Memory Observation Variance Or Allocator Signal

Extend the RSS observation layer into a variance study or a better allocator
signal.

Suggested scope:

- Repeat `--memory-observation` locally and on hosted runners if available.
- Decide whether RSS is too noisy for thresholds.
- Investigate a focused malloc, peak RSS, or allocation-count signal for the
  host executable if it can be collected reliably.
- Keep any new output observational unless stability is demonstrated.
- Do not change realistic-provider latency budgets or core layout behavior.

This continues the memory-proof thread, but it is less urgent than fixing the
hosted regression signal for realistic-provider latency.

## Recommended Slice 12 Selection

Recommended: Option A, hosted baseline-relative realistic regression gate.

Reasoning:

- Slice 11 did not fail to collect evidence; it collected the right evidence
  and proved that direct absolute hosted p95 enforcement is too fragile.
- The product brief asks for regression benchmarks that block performance
  degradation. A same-runner base-vs-head comparison maps to regression better
  than a fixed absolute threshold on a variable hosted runner.
- This keeps the fixed-height proof thread focused without changing
  `TextEngineCore` public API or starting variable-height layout.
- It can preserve the local `--realistic-provider --gate` command while adding
  a CI-specific enforcement shape.
- It creates a cleaner handoff to repository policy work: first make the
  realistic-provider CI check meaningful and low-noise, then require the status
  check if repository settings allow it.

Choose Option B instead only if the team wants one more measurement-only slice
before building comparison mechanics. Choose Option C instead only if the
project is ready to accept functional/API risk and leave the hosted
realistic-provider regression gap open. Choose Option E only if repository
policy is the immediate operational priority.

## Slice 11 Review Conclusion

Slice 11 cleanly completes its approved scope. It fixes the Slice 10 sampling
sequencing problem, collects three valid hosted pull-request samples from a
head that contained the realistic-provider gate step, applies the approved 70%
margin policy, and correctly keeps the final workflow free of a noisy
absolute realistic-provider gate.

The slice should be counted as hosted evidence and an evidence-backed defer
decision, not as CI enforcement. Slice 12 should usually move to a
baseline-relative hosted realistic-provider regression gate unless the project
explicitly chooses measurement-only variance work, repository policy, or
variable-height layout.
