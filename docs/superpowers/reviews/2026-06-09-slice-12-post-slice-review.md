# Slice 12 Post-Slice Review

Date: 2026-06-09

## Scope Reviewed

This review covers Slice 12: hosted baseline-relative realistic-provider
observation.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/reviews/2026-06-08-slice-11-post-slice-review.md`
- `docs/superpowers/specs/2026-06-08-hosted-baseline-relative-realistic-observation-design.md`
- `docs/superpowers/plans/2026-06-08-hosted-baseline-relative-realistic-observation.md`
- `docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md`
- `.github/workflows/swift-ci.yml`
- `.github/scripts/realistic-relative-observation.sh`
- `docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md` (for the
  still-active branch-protection blocker)
- PR #6 metadata and GitHub Actions run metadata for the calibration, final
  pull-request, and post-merge heads
- local git commit history for Slice 12
- fresh local host tests, release build, synthetic gate, ungated and gated
  realistic-provider runs, memory-shape diagnostic, RSS memory-observation
  diagnostic, helper self-test, workflow scan, and non-goal diff checks

No `AGENTS.md`, `CLAUDE.md`, or top-level `README.md` project-conventions file
is present in the repository, so review uses the product brief, existing slice
documents, and universal review heuristics.

## Product Brief Alignment

The product brief asks for a headless text rendering engine core with stable
scroll performance on 100k+ lines and >10 MB documents, strict virtualization,
external document storage, bounded core-owned memory, iOS/WASM source
compatibility, and regression benchmarks that block merge when performance
degrades.

Slice 11 closed with hosted evidence that a direct absolute realistic-provider
p95 gate is too close to `macos-latest` variance for safe CI enforcement, and
recommended a same-runner baseline-relative comparison instead. Slice 12 starts
that baseline-relative path, but deliberately merges as observation-only.

Slice 12 directly advances the brief's regression-benchmark requirement for the
>10 MB realistic path:

- It adds a pull-request-only `Swift CI` step that measures the realistic
  100,000-line, 11.2 MB provider benchmark on both the base SHA and the head SHA
  inside one hosted job.
- It compares head against base under shared runner conditions, which maps to
  "regression" better than a fixed absolute threshold on a variable hosted
  runner.
- It uses ungated `--realistic-provider` runs, so the local absolute budget is
  not turned into a hosted CI failure mode.
- It keeps the existing stable gates (`Run host tests`, `Run synthetic benchmark
  gate`, `Run memory shape diagnostic`, `Run RSS memory observation
  diagnostic`) unchanged.
- It freezes a promotion rule so a later slice can enable blocking only after a
  wider, independent no-op-equivalent evidence base exists.

Slice 12 intentionally does not yet prove or enforce:

- a blocking hosted realistic-provider regression gate;
- automatic promotion from observational to blocking;
- repository settings that require any `Swift CI` check before `main` changes;
- RSS, heap, malloc, allocation-count, or peak-memory hard budgets;
- cross-target CI for iOS, WASM, or embedded WASM;
- storage adapters such as memory-mapped files, ropes, piece tables, or editor
  buffers;
- variable-height layout, localized invalidation, shaping, rasterization, or
  UI-framework integration.

Those remain out of scope for Slice 12.

## Delivered Design

Slice 12 is an infrastructure and verification slice. It made no `TextEngineCore`,
`ViewportBenchmarks`, `Tests`, or `Package.swift` changes. The merged diff from
the prior `main` head (`114b780`) to the merge commit (`7c32928`) is:

```text
 .github/scripts/realistic-relative-observation.sh  |  327 ++++++
 .github/workflows/swift-ci.yml                     |   37 +
 ...sted-baseline-relative-realistic-observation.md | 1136 ++++++++++++++++++++
 ...seline-relative-realistic-observation-design.md |  385 +++++++
 ...sted-baseline-relative-realistic-observation.md |  481 +++++++++
 5 files changed, 2366 insertions(+)
```

The implementation matches the approved plan exactly.

### Helper

`.github/scripts/realistic-relative-observation.sh` runs the existing ungated
realistic-provider benchmark in caller-provided base and head source
directories, parses `p95_ns`/`p99_ns`, computes per-side medians and ratios, and
prints one stable key-value observation line. Notable design points:

- `RUN_ORDER` is the predeclared interleaved sequence
  `base, head, head, base, base, head, head, base` (median-of-4 per side).
- `--self-test` exercises field extraction, positive-integer validation, even
  and odd median, ratio, max, and `clean`/`above_threshold` classification
  without running the benchmark.
- Base-side incompatibility (`unknown argument --realistic-provider`, missing
  line, or missing fields) yields `observation=skipped_base_unsupported` and
  exit 0, while head-side problems and any other base command failure yield
  `observation=infrastructure_failure` and exit 2.
- The helper never uses `--realistic-provider --gate` and emits no
  `budget_*`/`gate=` fields, so the local absolute budget cannot leak into the
  hosted relative signal.

### Workflow

`.github/workflows/swift-ci.yml` keeps the four stable steps and adds, after
them:

```yaml
      - name: Observe realistic provider relative performance
        if: github.event_name == 'pull_request'
        continue-on-error: true
        env:
          REALISTIC_RELATIVE_OBSERVATION_THRESHOLD: "1.221556"
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
```

Checkout was changed to `fetch-depth: 0`. The step fetches all refs, verifies
both commit objects exist, creates detached base/head worktrees under
`RUNNER_TEMP`, and invokes the helper. The step is `pull_request`-only and
`continue-on-error: true`, so on `push` to `main` it is skipped and on PRs it
cannot fail the overall run. The threshold constant is the calibrated
`1.221556`, not the `1.50` sampling placeholder from the plan.

### Threshold

The threshold was derived by the pre-data rule from five accepted no-op
samples:

```text
max_noop_ratio=1.163387
candidate_threshold=1.221556
observation_threshold=1.221556
threshold_eligible_for_future_blocking=true
```

`candidate_threshold = max_noop_ratio * 1.05` is below the `1.50` ceiling, so it
is formally eligible for future blocking evaluation, but see Risks for why it is
not yet safe to enforce.

PR #6 merged on 2026-06-09T13:56:41Z with merge commit `7c32928`.

## Verification Evidence Reviewed

The Slice 12 verification document records passing local checks, five hosted
no-op samples (run `27169643767`, attempts 1-5), the threshold calculation, the
final workflow state, and a final hosted PR run.

Fresh local verification for this review on 2026-06-09 (Swift 6.2.1):

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

Result: pass (three `gate=pass` lines).

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 ... p95_ns=1315 p99_ns=1442 ... budget_p95_ns=20000 budget_p99_ns=50000 gate=pass
mode=pipeline scenario=100k_lines_80_visible_overscan_5 ... p95_ns=5343 p99_ns=5796 ... budget_p95_ns=50000 budget_p99_ns=100000 gate=pass
mode=pipeline scenario=1m_lines_200_visible_overscan_50 ... p95_ns=17201 p99_ns=17582 ... budget_p95_ns=100000 budget_p99_ns=200000 gate=pass
```

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Result: pass, ungated, no budget/gate fields.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5553 p99_ns=5699 failures=0 checksum=756321289736960
```

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Result: pass, gated smoke check still available locally.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text ... p95_ns=5574 p99_ns=5768 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass (three `invariant=pass` lines, `core_owned_bytes=74`).

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Result: pass (three `observation=pass` lines).

```text
.github/scripts/realistic-relative-observation.sh --self-test
```

Result: `self_test=pass`.

Workflow and non-goal checks:

```text
rg -n -- "--realistic-provider --gate" .github/workflows/swift-ci.yml .github/scripts/realistic-relative-observation.sh
```

Result: no output, exit code `1`.

```text
rg -n -- "budget_p95_ns|budget_p99_ns| gate=" .github/scripts/realistic-relative-observation.sh
```

Result: no output, exit code `1`.

```text
rg -n "REALISTIC_RELATIVE_OBSERVATION_THRESHOLD" .github/workflows/swift-ci.yml
```

Result: `1.221556` on the env line and reused on the helper invocation.

GitHub Actions metadata rechecked during this review:

- The five accepted no-op samples are attempts 1-5 of a single run
  (`27169643767`) at head `203bcf4`, base `cd907a8`. All five share run image
  `macos15` and CPU `Apple M1 (Virtual)`. They are correlated reruns, not
  independent run IDs (recorded as a calibration limitation in the verification
  document).
- The verification document's `Final Hosted PR Verification` records run
  `27177155119` at head `45fa749` with `max_ratio=1.194201` (only ~2.3% below
  the threshold) and adds a thin-headroom note.
- The actual final pre-merge head was `9b64fea`, not `45fa749`. Its run
  `27191517176` succeeded with `observation=clean`,
  `max_ratio=0.991476`, `observation_threshold=1.221556`, and a 3m40s job
  duration (`07:43:05Z` to `07:46:45Z`), well within `timeout-minutes: 20`.
  This run is itself a clean no-op-equivalent sample with wide headroom.
- The post-merge `main` push run `27211239070` at `7c32928` succeeded. On
  `push` the observation step is correctly skipped by the
  `if: github.event_name == 'pull_request'` guard, so only the stable gates ran.

Non-goal diff check:

```text
git diff 114b780 7c32928 -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Result: no output. No core, benchmark-code, test, or manifest changes.

## Git History

The Slice 12 planning and implementation sequence is:

```text
c3e311f docs: design hosted baseline-relative realistic observation
765c315 docs: revise hosted relative observation design
b4ae0de docs: plan hosted baseline-relative realistic observation
cd907a8 docs: harden slice 12 plan after review
8ffe78b ci: add realistic relative observation helper
203bcf4 ci: observe realistic relative performance
45fa749 docs: record hosted relative observation verification
6c16422 docs: update hosted relative observation final run
9b64fea docs: note thin threshold headroom in slice 12 verification
7c32928 Merge pull request #6 from arthurbanshchikov/slice-12-hosted-baseline-relative-realistic-observation
```

The design -> revise -> plan -> harden -> implement -> verify ordering is clean.
The two trailing documentation commits (`6c16422`, `9b64fea`) refine the
verification record after the first verification commit, which is the expected
shape for recording hosted evidence inside the same branch.

## Code Review Findings

No confirmed P0/P1/P2/P3 code findings were found for Slice 12.

The implementation matches the approved design:

- the observation runs on the same hosted job for base and head;
- median-of-4 per side with the predeclared interleaved run order;
- ungated `--realistic-provider`, never `--realistic-provider --gate`;
- `continue-on-error: true`, `pull_request`-only;
- infrastructure failures exit non-zero and are visible but non-fatal in
  Slice 12; `clean`, `above_threshold`, and `skipped_base_unsupported` exit
  zero;
- the calibrated threshold replaced the sampling placeholder before merge;
- existing stable CI steps remain present and ordered;
- Swift source, tests, package manifest, and benchmark budgets are untouched.

## Risks And Gaps

### Calibration Threshold Rests On Correlated Reruns With Thin Headroom

The threshold `1.221556` is derived from five reruns of a single run ID, taken
the same day on identical runner image and CPU. Those samples under-estimate
true cross-run, cross-day variance. The recorded final run `45fa749` produced
`max_ratio=1.194201`, only ~2.3% below the threshold, on source that is
benchmark-equivalent to base. The actual final merged head `9b64fea` produced a
much cleaner `max_ratio=0.991476`. That ~0.99 to ~1.19 spread on identical
benchmark-executed source confirms the signal is still noisy and the threshold
is not yet safe to enforce. The verification document is honest about this.

### Realistic-Provider Regression Enforcement Is Still Not Blocking

Slice 12 observes the relative signal; it does not enforce it. The brief's
">10 MB realistic path blocks merge on degradation" requirement is now
*measured in CI* but still not *enforced in CI*. The frozen promotion rule
requires at least 10 clean no-op-equivalent samples accumulated across different
days or runner allocations before blocking can be enabled, and only five
correlated reruns exist today.

### Repository Branch Protection Remains Externally Blocked

Even a perfect blocking step only blocks merges if repository policy requires
the check. Slice 6 documented that GitHub rulesets are unavailable for this
private repository:

```text
Upgrade to GitHub Pro or make this repository public to enable this feature.
```

That blocker is unchanged. Until the repository becomes public or moves to a
plan with rulesets/branch protection, no `Swift CI` check (not even the stable
synthetic gate) can actually block a merge. This means promoting the relative
gate to "blocking" would, today, only fail a non-required check, not gate
`main`.

### Verification Final-Run Record Lags The Merged Head

The verification document records `45fa749` (run `27177155119`,
`max_ratio=1.194201`) as the final hosted run, but two later commits
(`6c16422`, `9b64fea`) followed and the true merged head `9b64fea` ran as
`27191517176` with a clean `max_ratio=0.991476`. This is the same one-commit-lag
pattern flagged in the Slice 11 review and is inherent to recording a final run
inside the same commit chain. It is a documentation-accuracy note, not a defect:
the worst recorded sample drives the thin-headroom warning, while the actual
merged head was clean with wide headroom.

### Cross-Target CI Still Does Not Run On GitHub

`TextEngineCore` iOS/WASM/embedded WASM compatibility remains locally verified
only. Slice 12 correctly skipped cross-target work because no core source
changed, but the brief's iOS/WASM success criterion is still not continuously
enforced. This becomes important before the next public core API change.

### Variable-Height Layout Remains The Largest Deferred Capability

The fixed-height proof envelope is now effectively complete: synthetic gate,
realistic-provider observation, memory-shape invariant, and RSS observation.
Variable-height line indexing and localized invalidation remain the largest
unbuilt functional capability and the clearest remaining product value. It needs
public API and invalidation design and must not be mixed with benchmark
enforcement.

## Lessons For Slice 13

1. The relative-gate thread is now blocked on two external constraints, not on
   engineering. Promotion needs independent no-op-equivalent samples gathered
   across days (wall-clock-bound), and merge-blocking needs repository
   rulesets that are unavailable on the current private/free repository. Do not
   spend Slice 13 trying to "finish" enforcement that external state prevents.

2. If the regression thread continues, the next useful step is widening the
   no-op-equivalent evidence base with independent runs and recalibrating the
   threshold with real headroom, while staying nonblocking. That is honest
   progress toward the frozen promotion bar without merging a fragile gate.

3. Cross-target CI is best landed before the next public core API change.
   Variable-height layout is that change, so cross-target CI is a natural
   de-risking precursor rather than an afterthought.

4. Keep recording final hosted runs against the actual merged head, or note
   explicitly that the recorded run lags by the trailing documentation commits.

5. Do not mix variable-height layout with benchmark enforcement, repository
   policy, or cross-target setup in one slice. Each needs its own design and
   review.

## Slice 13 Candidate Options

### Option A: Variable-Height Layout Foundation

Start the next major core capability: variable-height line indexing and
localized invalidation.

Suggested scope:

- Define the smallest height-index or measurement-cache boundary.
- Preserve the current fixed-height fast path and public behavior.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests for height changes.
- Repeat host, iOS, WASM, and embedded WASM verification for the public core API
  or portability-sensitive source changes.
- Keep realistic-provider CI enforcement, branch protection, storage adapters,
  and memory-budget enforcement out of scope.

This is the strongest functional-value candidate. It is the deliberate pivot
from proof closure to functional expansion and carries the most public-API and
invalidation design risk.

### Option B: Cross-Target CI For `TextEngineCore`

Move existing local portability checks into GitHub Actions before the next
public core API change.

Suggested scope:

- Add the cheapest reliable iOS compile check for `TextEngineCore` (high
  confidence on `macos-latest`).
- Investigate hosted-runner setup for WASM and embedded WASM Swift SDKs; record
  exact runner images, toolchain versions, and any skipped targets with reasons.
- Keep `ViewportBenchmarks` host-only.
- Do not change public core API in the same slice.

This is a bounded, low-risk infrastructure slice that converts the brief's
iOS/WASM "compiles without source changes" criterion from local-only into
continuous CI proof, and it de-risks Option A.

### Option C: Independent No-Op Evidence Expansion And Threshold Recalibration

Continue the baseline-relative thread without enforcing it, by replacing the
five correlated reruns with independent samples.

Suggested scope:

- Collect no-op-equivalent samples from separate hosted workflow run IDs across
  different days and runner allocations, plus opportunistic doc/helper-only PR
  traffic.
- Recompute `max_noop_ratio`, `candidate_threshold`, and `observation_threshold`
  with the real distribution and explicit headroom.
- Update only the workflow threshold constant; keep the step nonblocking.
- Track progress toward the frozen 10-sample promotion bar.

This is honest progress toward future blocking, but it is wall-clock-heavy,
low-code, and does not itself close the enforcement gap. It pairs with a later
promotion slice, which is still gated by the branch-protection blocker.

### Option D: Storage Adapter / Provider Expansion

Exercise the proven provider contract with a non-synthetic storage shape.

Suggested scope:

- Add one storage adapter (for example a memory-mapped file, rope, or piece
  table) behind the existing provider/source abstraction.
- Prove the core stays provider-agnostic and core-owned memory stays bounded.
- Reuse the memory-shape and realistic-provider diagnostics for the new adapter.
- Keep variable-height layout and CI enforcement out of scope.

This adds functional breadth, but the provider contract is already proven, so it
is less urgent than variable-height layout.

### Option E: Memory Hard-Budget Or Allocator Signal

Extend the memory-proof thread from observation toward a stable budget.

Suggested scope:

- Investigate a focused malloc, peak-RSS, or allocation-count signal for the
  host executable that is stable enough for a threshold.
- Keep any new output observational unless stability is demonstrated.
- Do not change realistic-provider budgets or core layout behavior.

This continues the memory thread but is lower priority than functional
expansion or de-risking the next API change.

### Not A Slice 13 Candidate: Repository Required Status Check

Requiring `Swift CI` for `main` remains externally blocked for this private
repository (Slice 6: "Upgrade to GitHub Pro or make this repository public").
It should not be a Slice 13 engineering target until the repository becomes
public or moves to a plan with rulesets/branch protection. Likewise, directly
promoting the relative gate to blocking is not yet eligible under the frozen
rule and would not actually block merge while branch protection is unavailable.

## Recommended Slice 13 Selection

Recommended: Option B, cross-target CI for `TextEngineCore`, sequenced as the
de-risking precursor to Option A (variable-height layout) in a following slice.

Reasoning:

- The regression-enforcement thread (Slices 10-12) is now paused on external
  constraints: independent-sample accumulation is wall-clock-bound, and
  merge-blocking is blocked by the unavailable private-repository rulesets.
  Pushing further on enforcement yields little until repository state changes.
- The fixed-height proof envelope is effectively complete, so the highest
  engineering value now is functional expansion, and variable-height layout is
  that expansion.
- Variable-height layout changes the public core API and is portability
  sensitive. The Slice 11 lesson is to land cross-target CI before the next
  public core API change. Doing Option B first means the variable-height slice
  can rely on continuous iOS/WASM portability proof instead of local-only
  checks, across what will likely be a multi-slice effort.
- Option B is bounded, low-risk, touches no public core API, and directly
  converts a brief success criterion from local-only verification into
  continuous CI enforcement.

Choose Option A directly instead if the project prefers immediate functional
value and accepts running iOS/WASM portability checks locally during the
variable-height work rather than in CI first. Choose Option C only if the
project wants to keep investing in the relative-gate thread despite the external
enforcement blocker. Choose Option D or Option E only if breadth or
memory-signal work is explicitly more valuable right now than the next core
capability.

## Slice 12 Review Conclusion

Slice 12 cleanly completes its approved scope. It starts the baseline-relative
hosted realistic-provider path, merges as nonblocking observation with a
calibrated threshold, keeps the stable gates and core source untouched, and
freezes a disciplined promotion rule. The slice should be counted as the
foundation of hosted relative regression observation and an honest, evidence
-backed deferral of enforcement, not as a blocking regression gate.

Slice 13 should usually pivot toward functional expansion by first landing
cross-target CI for `TextEngineCore` as the infrastructure precursor to
variable-height layout, unless the project explicitly chooses to keep widening
relative-gate evidence, add a storage adapter, or extend the memory signal.
