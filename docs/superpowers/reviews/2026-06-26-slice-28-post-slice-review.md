# Slice 28 Post-Slice Review

Date: 2026-06-26

## Scope Reviewed

This review covers Slice 28: the **line-query CI gate promotion**. It adds the
already-existing `--line-query --gate` benchmark path as a new **blocking** step
in the required `Host tests and benchmark gate` hosted job — the **sixth**
contiguous blocking latency gate — so a runtime regression in the inverse
vertical position-query path (`ViewportVirtualizer.lineAt(y:metrics:)`, shipped in
Slice 27) now fails the job. It was the Slice 27 review's recommended Option A and
the user-selected one-shot blocking rollout.

This is a pure CI/governance slice. Unlike Slice 26 — which folded in the
`deterministicIndex` hardening because the Slice 25 review flagged a latent crash
class in the promoted benchmark — the Slice 27 review found **no P0/P1/P2 and no
actionable P3** in the line-query benchmark, so Slice 28 promotes it **unchanged**.
It changes no `TextEngineCore` source, no `TextEngineReferenceProviders`
provider/algorithm, no benchmark Swift source (no scenario, budget, helper, or
mode edit), no tests, and no package metadata. It closes the single
regression-protection gap the Slice 27 review identified.

The slice was delivered through **two** PRs, both now merged:

- PR #50 (`slice-28-line-query-ci-gate-promotion`), title *"Slice 28: promote
  line-query benchmark to a blocking hosted gate"*, final head
  `c26765cab17a93036bddc34d279037a845fd329d` (`c26765c`), merged to `main` as
  `3bbb74accb58662bd444146ba9a5c815caa73e3f` (`3bbb74a`) — the workflow step, the
  `AGENTS.md` update, the spec, the plan, and the verification record's local
  sections.
- PR #51 (`slice-28-post-merge-verification`), title *"Record Slice 28 post-merge
  proof"*, merged as `9cfe9f08d2428cab56f9c20c1abccb19dbfe2d4f` (`9cfe9f0`,
  current `main` HEAD) — the docs-only follow-up that filled the hosted evidence
  (PR-head run + post-merge push run).

**Both PRs are merged at review time**, so `main`'s verification record carries
real hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-25-line-query-ci-gate-promotion-design.md`
- `docs/superpowers/plans/2026-06-25-line-query-ci-gate-promotion.md`
- `docs/superpowers/verification/2026-06-25-line-query-ci-gate-promotion.md`
- `docs/superpowers/reviews/2026-06-24-slice-27-post-slice-review.md`
- `.github/workflows/swift-ci.yml` (host job)
- `AGENTS.md` (CI section)
- PR #50 / #51 metadata, hosted run evidence (step-level conclusions), merge
  parentage, and the merged Slice 28 diff

The reviewed Slice 28 range (PR #49 merge base → current `main` HEAD), excluding
this review document itself, is:

```text
b694b73..9cfe9f0
```

This is confined to `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`.
A fresh name-only diff confirms it does **not** touch `Sources/TextEngineCore`,
`Sources/TextEngineReferenceProviders`, `Sources/ViewportBenchmarks`, `Tests/**`,
or `Package.swift`.

## Product Brief Alignment

The brief requires regression benchmarks to block merge on performance
degradation (*"Регрессионные бенчмарки блокируют merge при деградации
производительности"*). Before this slice that principle held for five of the six
latency paths — synthetic pipeline, static variable-height, variable-height
mutation, structural-mutation, and bulk-structural-mutation gates all ran blocking
in hosted CI. The inverse vertical position-query path, added in Slice 27, was
proven **locally only**: the host job stayed green regardless of `lineAt` runtime
because the benchmark was never invoked in the workflow.

Slice 28 closes exactly that gap. The hosted job already runs `swift test`, so the
*correctness and algorithmic-shape* guarantees were already enforced
(`LineAtQueryCountTests` bounds the `offset(ofLine:)` probe count at O(log N) and
proves the clamp branches skip the binary search; `LineAtTests` plus the
equivalence oracle cover the half-open boundary). What the unit tests do **not**
catch is a *runtime budget/latency* regression — a constant-factor slowdown, an
added allocation, or a cache-unfriendly change that preserves query count and
correctness but degrades wall-clock p95/p99. That was the enforcement gap, and it
is now closed: the brief's "benchmark gates block merge" principle now holds for
**all six** latency paths.

This also completes the project's established "functional slice adds a local gate →
promotion slice wires CI" rhythm for the **fifth** time (variable-height → Slice
15, variable-height-mutation → Slice 21, structural-mutation → Slice 24,
bulk-structural-mutation → Slice 26, line-query → this slice). The change is fully
in keeping with the brief's hard constraints: it touches only workflow YAML and
docs, introduces no dependency, and leaves the Foundation-free core and all
architecture invariants untouched.

## Delivered Design

Merged Slice 28 diff (`b694b73..9cfe9f0`):

```text
 .github/workflows/swift-ci.yml                     |   4 +
 AGENTS.md                                          |   9 +-
 .../2026-06-25-…-ci-gate-promotion.md (verification)| 350 +++++++++++++++
 .../2026-06-25-…-ci-gate-promotion-design.md (spec) | 481 ++++++++++++++++++++
 .../2026-06-25-…-ci-gate-promotion.md (plan)        | 279 ++++++++++++
 5 files changed, 1119 insertions(+), 4 deletions(-)
```

### The workflow step (the core of the slice)

A single new step in the `host-tests-and-benchmark-gate` job, inserted between the
bulk-structural-mutation gate and the memory-shape diagnostic
(`.github/workflows/swift-ci.yml:110`):

```yaml
      - name: Run line query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate
```

This is correct against every spec decision:

- **No `continue-on-error`** → it is a true blocking gate (Decision 1, one-shot
  promotion with no transient observation step). Confirmed by the fresh Ruby
  workflow-invariant assertion below.
- **Invokes the executable-owned gate path** (`--line-query --gate`), not a
  YAML-duplicated threshold → budgets stay single-sourced in
  `Sources/ViewportBenchmarks/LineQueryBenchmark.swift` (Decision 2).
- **Positioned after the bulk gate, before memory-shape** → all six blocking
  latency gates stay contiguous and fail before lower-priority diagnostics
  (Decision 4). Verified by the assertion's `i_bulk < i_lq < i_mem` ordering check
  and a fresh `grep` (steps 12 → 13 → 14 in the hosted logs).
- **Same `docs_only_pr != 'true'` guard** as every adjacent gate → docs-only PRs
  still skip it via the trusted lightweight path (Decision 6).
- **No `shell: bash` override** → a single one-line command with no pipes
  (Decision 7).
- **Required context names unchanged** (`Host tests and benchmark gate`,
  `iOS cross-target compile`, `WASM cross-target observation`) → the job becomes
  stricter without a ruleset or required-context change (Decision 5).

### No bundled hardening (the clean distinction from Slice 26)

This is what makes Slice 28 a *pure* promotion, simpler than Slice 26. The Slice
27 review found no actionable defect in the line-query benchmark, and the
benchmark builds its sample `y` values from non-negative `sample % …` arithmetic
and the shared `deterministicScrollOffset` helper — it derives no array index from
a wrapping signed multiply, so it carries no analog of the `deterministicIndex`
crash class. The spec (Decision / "No bundled hardening") correctly scoped any
code change out, and the merged diff confirms it: **zero** lines of Swift changed.
A fresh `git diff --name-only b694b73..HEAD -- Sources Tests Package.swift` is
empty.

### `AGENTS.md` (durable guidance)

The CI section's host-job bullet now lists `→ --line-query --gate (blocking)`
after the bulk-structural-mutation gate and before `--memory-shape`
(`AGENTS.md:109`), and the "fail the job on perf regression" sentence now names
the line-query gate alongside the other five (`AGENTS.md:113-114`). The
command-list local invocation (`AGENTS.md:78`) and the benchmark-flags lists
already carried the mode from Slice 27 and were correctly left unchanged. The
docs-only, iOS, WASM, ruleset, and bypass-caveat wording is unchanged.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `9cfe9f0`)

- `git diff --name-only b694b73..HEAD -- Sources Tests Package.swift` → **empty**
  (no core, provider, benchmark, test, or manifest surface touched).
- `git diff --check b694b73..HEAD` → no output, exit `0`.
- `rg -n "Foundation" Sources/TextEngineCore Sources/TextEngineReferenceProviders`
  → no matches, exit `1`.
- Ruby workflow-invariant assertion (step exists, invokes `--line-query --gate`,
  not `continue-on-error`, ordered `bulk < line-query < memory-shape`) →
  `workflow_assertions_ok`, exit `0`.
- `swift run -c release ViewportBenchmarks -- --line-query --gate` → all five
  scenarios `gate=pass`, 0 failures; **all five checksums byte-identical** to the
  recorded baseline (`641440000`, `63985556480`, `639841600000`, `63985600000`,
  `639841547520`).
- `swift run -c release ViewportBenchmarks -- --gate` → all three synthetic
  scenarios `gate=pass`; checksums match the record (`1319670707200`,
  `570448232307200`, `18852477646272000`).
- `swift test` → **124 XCTest tests, 0 failures**, plus the expected empty Swift
  Testing harness line `0 tests in 0 suites`. Unchanged from the Slice 27
  baseline, as expected for a slice that adds no test and changes no behavior.

### Fresh local line-query numbers (macOS arm64, this review)

| Scenario | p95 (ns) | Budget p95 | Headroom |
| --- | ---: | ---: | ---: |
| uniform_1k         | 18    | 30,000  | ~1,667× |
| uniform_100k       | 27    | 60,000  | ~2,222× |
| uniform_1m         | 37    | 120,000 | ~3,243× |
| balanced_tree_100k | 770   | 300,000 | ~390×   |
| balanced_tree_1m   | 1,496 | 600,000 | ~401×   |

Consistent with the Slice 27 review's recorded macOS numbers (run-to-run noise
aside); the tightest path (balanced_tree_1m) sits ~401× under budget locally.

### Hosted Linux x86_64 budget-fit (the load-bearing evidence for this slice)

Decision 3 bet that the macOS-calibrated budgets would hold on hosted Linux, with
the one-shot PR-head run **being** that evidence. The line-query benchmark had
**never run in hosted CI** before this slice, so these are the first hosted Linux
x86_64 numbers for the mode:

| Scenario | macOS local p95 | PR-head p95 | Post-merge p95 | Budget p95 |
| --- | ---: | ---: | ---: | ---: |
| uniform_1k         | 18    | 33    | 25    | 30,000  |
| uniform_100k       | 27    | 47    | 54    | 60,000  |
| uniform_1m         | 37    | 79    | 40    | 120,000 |
| balanced_tree_100k | 770   | 1,413 | 1,094 | 300,000 |
| balanced_tree_1m   | 1,496 | 2,456 | 1,778 | 600,000 |

Hosted Linux is meaningfully slower and noisier than macOS arm64 (the balanced
tree p95 roughly doubled), exactly as in prior promotions. Even so, the tightest
hosted scenario (balanced_tree_1m at ~2,456 p95 on the PR-head run) sits **~244×
under budget**, and every p99 clears its budget by a comparable margin. This is by
far the most generous of the five promotions: Slice 26's tightest hosted scenario
cleared at ~4.9×, where this one clears at ~244×. The one-shot blocking promotion
was unambiguously the right call — Decision 3's "stop and re-derive Linux budgets"
escape hatch was nowhere near triggered. All five checksums on both hosted runs
equal the local baseline, confirming the inverse-query path is deterministic
across platforms.

### Hosted runs (verified live via `gh`, at step-log level not just job conclusion)

Both runs re-verified via `gh` during this review — and, per the project's "a
green job can hide a dead `continue-on-error` step" lesson, the new gate was
checked at the **step** level, not just the job conclusion:

- **PR #50 final-head run `28183651687`** (head `c26765c`, event
  `pull_request`): conclusion `success`; all three required jobs `success`
  (`Host tests and benchmark gate` `83479679111`, `iOS cross-target compile`
  `83479679002`, `WASM cross-target observation` `83479679034`). In the host job,
  step 12 `Run bulk structural mutation benchmark gate` = `success`, **step 13
  `Run line query benchmark gate` = `success`**, step 14 `Run memory shape
  diagnostic` = `success`.
- **Post-merge push run `28184592976`** on merge commit `3bbb74a` (event `push`,
  branch `main`): conclusion `success`; all three required jobs `success`
  (`83482961743` / `83482961767` / `83482961817`). The host job again shows steps
  12 → 13 → 14 with `Run line query benchmark gate` = `success`, and the PR-only
  realistic-provider observation correctly `skipped` on the push event. **This is
  the merged-code evidence anchor for Slice 28**: the new gate is a real blocking
  step that ran on merged code and passed, not a masked one. Merge parentage
  confirms `3bbb74a`'s second parent is `c26765c`, so the proof anchors the
  actually-merged head.

PR #51 was a docs-only follow-up touching only the verification record, so it
legitimately took the trusted docs-only path; the workflow YAML has not changed
since `3bbb74a`, so run `28184592976` still represents current `main`'s workflow
behavior.

## Git History

Reviewed Slice 28 commits (PR #50 → #51):

```text
7848fdc docs: add line-query CI gate promotion design
d752d00 docs: address spec review for line-query gate promotion
74a312b docs: add line-query CI gate promotion implementation plan
9cf7056 ci: promote line-query benchmark to a blocking hosted gate
179a91b docs: document line-query gate as blocking in AGENTS.md CI section
c26765c docs: record local verification for line-query gate promotion
3bbb74a Merge pull request #50 …
3163005 docs: record slice 28 post-merge proof
9cfe9f0 Merge pull request #51 …
```

Clean, incremental, one-logical-step-per-commit with correct conventional-commit
prefixes: `docs:` for spec/plan/guidance/verification, `ci:` for the single
workflow step. The spec-correction commit precedes the plan, the workflow change
is isolated in its own `ci:` commit, the `AGENTS.md` doc update is separate, and
local verification is separate from implementation. The two-PR split
(implementation + local proof, then post-merge proof) is the standard pattern.

## Code Review Findings

Reviewing across workflow correctness, scope discipline, evidence integrity, and
policy concerns:

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, the gate is blocking and proven green at step level on
merged code, the scope is clean (zero Swift), and Foundation/core invariants are
intact.

### P2 / Production Readiness

None. As in Slice 26, the verification record carries **no evidence-accuracy
defect**: the PR-head proof was recorded only in the post-merge follow-up (PR #51)
against the stable final head `c26765c`, and the source-bearing PR #50 was never
described as taking the docs-only shortcut.

### P3 / Minor But Valid

**1. Spec/implementation primitive-naming drift, still open (carried from Slice 25
P3 #3 / Slice 26 P3 #1).** The bulk-edits spec names the join primitive
`join(_:_:)` while the implementation ships `join3`/`join2`. This is a
provider-doc hygiene item unrelated to CI; Slice 28 touches no provider source or
spec, so it is correctly **not** a Slice 28 defect — but it remains an open item
with no home slice yet. A one-line cross-reference in the bulk-edits spec would
retire it whenever a provider-touching slice next opens.

No P3 changes whether the merged result is correct; #1 is pre-existing hygiene
this slice legitimately deferred.

## Risks And Gaps

### Budgets remain macOS-derived after this slice

Promotion confirmed the macOS budgets fit hosted Linux but did not re-derive
Linux-native budgets. That matches the standing project posture for all six gates
and is acceptable. With six latency gates now on hosted Linux, the accumulated
x86_64 evidence makes a dedicated Linux budget re-baseline viable future work,
explicitly out of scope here.

### Balanced-tree line queries remain O(log²N)

This slice protects the current line-query path against regression; it does not
improve its asymptotics. The `balanced_tree` scenarios still exercise the generic
O(log²N) query over the mutable provider (each of the O(log N) `offset(ofLine:)`
probes in the outer binary search is itself O(log N) on `BalancedTreeLineMetrics`).
The numbers are correct and ~244×+ under budget even hosted, but provider-native
prefix search (Slice 27 review Option B) remains the structural way to reach a
single O(log N) tree descent. It is now the natural highest-value follow-up,
because the path it would optimize is finally CI-protected and measurable against
this gate.

### The whole vertical-query surface is now CI-protected — no governance debt remains

With this slice, all six latency paths (synthetic, static + mutating
variable-height, single + bulk structural mutation, and the inverse vertical
position-query) run under blocking hosted regression protection. There is no
remaining CI gap forcing another governance slice; the functional → gate-promotion
cadence has drained for the fifth time. The next slice has no CI debt forcing its
hand.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative
observation remains PR-only `continue-on-error`; the `Main` ruleset keeps its
documented bypass-actor shape (the admin user can still bypass required checks).
None were in scope for Slice 28.

## Lessons For The Next Slice

1. **The clean-evidence convention held for a second consecutive slice.** Slice 26
   broke the recurring stale-on-write defect by recording the PR-head proof only
   in the post-merge follow-up against the stable final head and never
   mis-classifying the source-bearing PR as docs-only. Slice 28 followed the same
   discipline and again landed with **no correction PR and no evidence-accuracy
   defect**. This is now the proven default for every source/workflow-touching
   slice — keep it.
2. **A pure promotion should stay pure.** Slice 26 correctly folded in a hardening
   because the prior review found a real latent crash class. Slice 28 correctly
   did **not** fold anything in, because the Slice 27 review found none — the spec
   explicitly justified zero Swift changes, and the merged diff proves it. Resist
   the urge to bundle drive-by edits into a governance slice when there is no
   evidence-backed reason; scope discipline is what keeps these slices auditable.
3. **One-shot promotion is the right default across the entire headroom range.**
   The five promotions now span ~4.9× (Slice 26, hosted) to ~244× (this slice,
   hosted) tightest-scenario headroom, and one-shot blocking succeeded at both
   extremes with Decision 3's stop-and-retune as the standing net. Reserve
   observe-then-block only for a genuinely thin-margin gate, not as a default
   ceremony.
4. **The functional → gate-promotion cadence has now completed five full cycles.**
   The CI/governance backlog opened by functional work is fully drained again. The
   engine is free to advance under complete regression protection — the next slice
   should be a genuine capability increment, not more governance.

## Slice 29 Candidate Options

### Option A: Provider-native prefix search (Slice 27 review Option B)

Add an optional provider-native y→line primitive so `BalancedTreeLineMetrics` can
answer "line containing offset" in one O(log N) tree descent instead of the
generic O(log²N) binary search over O(log N) `offset(ofLine:)` probes. Highest
algorithmic value, and uniquely well-positioned now: the path it optimizes is the
one Slice 28 just put under a blocking gate, so the improvement is directly
measurable against `--line-query --gate` (and must stay equal to the generic query
via an equivalence oracle). It changes the provider/core contract, so it needs a
careful compatibility design (optional protocol requirement with a generic
fallback).

### Option B: Geometry-bearing vertical query (Slice 27 review Option C)

Add a richer query returning line index plus y/height or within-line fraction,
useful for tap-to-caret flows. Wider public API surface; should be a new
method/result type, not a new `LineQuery` case.

### Option C: Horizontal / wrap-aware next capability (Slice 27 review Option D)

Advance toward x/y point queries, wrapping, or visual rows — the largest product
leap toward realistic editing of 100k+ line / >10 MB documents, and the largest
design surface. Needs a fresh brainstorm + spec.

### Option D: Promote WASM cross-target to blocking (Slice 27 review Option E)

Provision a pinned, version-matched WASM Swift SDK in hosted CI and flip the WASM
job from observational to blocking for both `TextEngineCore` and
`TextEngineReferenceProviders`. The strongest standing infra item; infra-gated on
stable SDK provisioning.

### Option E: Linux-native budget re-baseline

With six latency gates now on hosted Linux, re-derive Linux-native budgets from the
accumulated x86_64 evidence and retire the macOS-calibration caveat. Low product
value, useful hygiene; cleanest if folded into a slice that already runs the gates
hosted.

## Recommended Slice 29 Selection

Recommended Slice 29 is **Option A — provider-native prefix search**.

The reasoning: the project has now completed five full "functional slice → gate
promotion" cycles, and with Slice 28 the entire latency surface — including the
inverse vertical position-query path — runs under blocking hosted regression
protection. **There is no remaining CI/governance gap forcing another infra
slice**, so the next slice should be a genuine capability increment. Among the
functional options, provider-native prefix search is uniquely well-timed: it
deepens the exact path that was just shipped (Slice 27) and just protected (Slice
28), turning the `balanced_tree` y→line query from O(log²N) to a single O(log N)
tree descent. That makes it the highest algorithmic value, it has a clean
equivalence oracle (must equal the generic query), and — crucially — its win is
directly measurable against the brand-new `--line-query --gate`, which already
carries the `balanced_tree_100k` / `balanced_tree_1m` scenarios that would benefit.

Because Option A changes the provider/core contract (an optional protocol
requirement with a generic fallback so existing providers keep working), it should
**start with a brainstorm and spec** rather than a drive-by — the increment needs
to be pinned (how the optional primitive stays Foundation-free / Embedded-
compatible, how the generic fallback is preserved, and what the equivalence oracle
and benchmark deltas look like). The A-vs-C call (deepen the existing vertical
query vs. open the horizontal/wrap axis) is a genuine product decision worth
surfacing to the user; given the just-protected line-query path and zero CI debt,
Option A is the consistent next step, with Option C the larger product direction
once the vertical axis is asymptotically optimal, and Option D the strongest pick
if the preference is to close the last standing infra item instead.

## Slice 28 Review Conclusion

Slice 28 delivered the intended governance increment cleanly: the
`--line-query --gate` benchmark now runs as the **sixth** blocking latency gate in
the required host job, so runtime regressions in `ViewportVirtualizer.lineAt` —
the inverse vertical position-query introduced in Slice 27 — block merge, sitting
contiguously after the bulk gate and before the memory-shape diagnostic. The
macOS-calibrated budgets held on hosted Linux x86_64 with the most generous margin
of the series (~244× under budget at the tightest hosted scenario), decisively
validating the one-shot promotion and never approaching Decision 3's escape hatch.
The change is correctly scoped — **zero Swift changed** (no core, provider,
benchmark, test, or manifest surface; required contexts, docs-only behavior, and
ruleset all unchanged) — and verified at the step level on both the final PR-head
run and the post-merge push run, with all five checksums byte-identical across
local, PR-head, and merged-code runs.

The review found **no P0, P1, or P2 issues** against the merged result, and — for
the second consecutive slice — **no evidence-accuracy defect**: Slice 28 again
recorded the PR-head proof only in the post-merge follow-up against the stable
final head and never mis-classified the source-bearing PR as docs-only. The one
open P3 (spec/code primitive-naming drift) is pre-existing hygiene this slice
legitimately deferred. With all six latency gates now CI-protected and no
governance debt remaining, Slice 28 cleanly closes the CI/governance arc and hands
off to a return to new-capability functional work — most naturally provider-native
prefix search, which would optimize the very path this slice just protected.
