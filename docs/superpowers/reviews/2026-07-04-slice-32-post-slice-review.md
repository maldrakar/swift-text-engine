# Slice 32 Post-Slice Review

Date: 2026-07-04

## Scope Reviewed

This review covers Slice 32: the **line-geometry-query CI gate promotion**. It
wires the already-existing `--line-geometry-query --gate` benchmark path (shipped
**local-only** in Slice 31) into the required `Host tests and benchmark gate`
hosted job as a new **blocking** step — the **seventh** contiguous blocking
latency gate — so a runtime regression in the geometry-bearing vertical
position-query path (`ViewportVirtualizer.lineGeometryAt(y:metrics:)`) now fails
the job. It was the Slice 31 review's recommended **Option A** and the
user-selected one-shot blocking rollout.

This is a pure CI/governance slice. Like Slice 28 (its structural twin) — and
unlike Slice 26, which folded in the `deterministicIndex` overflow hardening the
Slice 25 review had flagged — the Slice 31 review found **no P0/P1/P2 and no
actionable P3** in the promoted benchmark, so Slice 32 promotes it **unchanged**.
It changes no `TextEngineCore` source, no `TextEngineReferenceProviders`
provider/algorithm, no benchmark Swift source (no scenario, budget, helper, or
mode edit), no tests, and no package metadata. It closes the single
regression-protection gap the Slice 31 review identified.

The slice was delivered through **two** PRs, both now merged:

- PR #62 (`slice-32-line-geometry-query-ci-gate-promotion`), title *"Slice 32:
  promote line-geometry-query benchmark to a blocking hosted gate"*, final head
  `6942ea4c0ae9c01aca1645f0d49f59780c8fee94` (`6942ea4`), merged to `main` as
  `86cd14a2461ed308eabb4f950bf484f53eb862da` (`86cd14a`) by `maldrakar` at
  2026-07-04T07:21:09Z — the workflow step, the `AGENTS.md` update, the spec, the
  plan, and the verification record's local sections.
- PR #63 (`slice-32-post-merge-verification`), title *"Record Slice 32 post-merge
  proof"*, merged as `492fe215c71137ed05c4f1133df64ed0b8346864` (`492fe21`,
  current `main` HEAD) by `maldrakar` at 2026-07-04T11:34:54Z — the docs-only
  follow-up (`c95bb63`) that filled the verification record's `Hosted Proof`
  section with the real PR-head and merged-code push runs.

**Both PRs are merged at review time**, so `main`'s verification record carries
real hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-07-03-line-geometry-query-ci-gate-promotion-design.md`
- `docs/superpowers/plans/2026-07-03-line-geometry-query-ci-gate-promotion.md`
- `docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md`
- `docs/superpowers/reviews/2026-07-02-slice-31-post-slice-review.md`
- `.github/workflows/swift-ci.yml` (host job)
- `AGENTS.md` (CI section)
- PR #62 / #63 metadata, hosted run evidence (step-level conclusions), merge
  parentage, and the merged Slice 32 diff

The reviewed Slice 32 range (PR #61 review merge → current `main` HEAD), excluding
this review document itself, is:

```text
dd6dc27..492fe21
```

`git merge-base dd6dc27 492fe21` returns `dd6dc27`, confirming the Slice 31 review
merge (PR #61, `dd6dc27`) is a clean ancestor and the range captures exactly the
Slice 32 work. Merge parentage confirmed via `git rev-list --parents`: `86cd14a`
(PR #62)'s parents are the base `dd6dc27` and the verified PR head `6942ea4`;
`492fe21` (PR #63) merges the post-merge-proof commit `c95bb63` onto `86cd14a`.
A fresh name-only diff confirms the range is confined to
`.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**` — it does **not**
touch `Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders`,
`Sources/ViewportBenchmarks`, `Tests/**`, or `Package.swift`.

## Product Brief Alignment

The brief requires regression benchmarks to block merge on performance
degradation (*"Регрессионные бенчмарки блокируют merge при деградации
производительности"*). Before this slice that principle held for six of the seven
latency paths — synthetic pipeline, static variable-height, variable-height
mutation, structural-mutation, bulk-structural-mutation, and line-query gates all
ran blocking in hosted CI. The geometry-bearing vertical position-query path,
added in Slice 31, was proven **locally only**: the host job stayed green
regardless of `lineGeometryAt` runtime because the benchmark was never invoked in
the workflow.

Slice 32 closes exactly that gap. The hosted job already runs `swift test`, so the
*correctness and algorithmic-shape* guarantees were already enforced
(`LineGeometryAtQueryCountTests` bounds the `offset(ofLine:)` probe count and
proves the composed query dispatches to `lineAt`'s native index search then takes
exactly two ordered geometry probes; `LineGeometryAtTests` plus the balanced-tree
equivalence oracle cover the half-open boundary and fraction behavior across a
scroll sweep and after mutations). What the unit tests do **not** catch is a
*runtime budget/latency* regression — a constant-factor slowdown, an added
allocation, or a cache-unfriendly change that preserves query count and
correctness but degrades wall-clock p95/p99. That was the enforcement gap, and it
is now closed: the brief's "benchmark gates block merge" principle now holds for
**all seven** latency paths.

This also completes the project's established "functional slice adds a local gate →
promotion slice wires CI" rhythm for the **sixth** time (variable-height → Slice
15, variable-height-mutation → Slice 21, structural-mutation → Slice 24,
bulk-structural-mutation → Slice 26, line-query → Slice 28, line-geometry-query →
this slice). The change is fully in keeping with the brief's hard constraints: it
touches only workflow YAML and docs, introduces no dependency, and leaves the
Foundation-free core and all architecture invariants untouched.

## Delivered Design

Merged Slice 32 diff (`dd6dc27..492fe21`):

```text
 .github/workflows/swift-ci.yml                     |   4 +
 AGENTS.md                                          |   7 +-
 .../2026-07-03-…-ci-gate-promotion.md (verification)| 357 +++++++++++++++
 .../2026-07-03-…-ci-gate-promotion-design.md (spec) | 521 ++++++++++++++++++++
 .../2026-07-03-…-ci-gate-promotion.md (plan)        | 229 +++++++++
 5 files changed, 1115 insertions(+), 3 deletions(-)
```

### The workflow step (the core of the slice)

A single new step in the `host-tests-and-benchmark-gate` job, inserted between the
line-query gate and the memory-shape diagnostic
(`.github/workflows/swift-ci.yml:114`):

```yaml
      - name: Run line geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-geometry-query --gate
```

This is correct against every spec decision:

- **No `continue-on-error`** → it is a true blocking gate (Decision 1, one-shot
  promotion with no transient observation step). Confirmed by the fresh Ruby
  workflow-invariant assertion below.
- **Invokes the executable-owned gate path** (`--line-geometry-query --gate`), not
  a YAML-duplicated threshold → budgets stay single-sourced in
  `Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift` (Decision 2).
- **Positioned after the line-query gate, before memory-shape** → all seven
  blocking latency gates stay contiguous and fail before lower-priority
  diagnostics (Decision 4). Verified by the assertion's `line-query <
  line-geometry-query < memory-shape` ordering check (steps 13 → 14 → 15 in the
  hosted logs). This ordering also buys differential diagnosis: because
  `lineGeometryAt` composes over `lineAt`, a line-query **pass** with a
  line-geometry-query **fail** localizes the regression to the geometry delta (the
  two `offset(ofLine:)` probes, box construction, fraction arithmetic) rather than
  to `lineAt` itself.
- **Same `docs_only_pr != 'true'` guard** as every adjacent gate → docs-only PRs
  still skip it via the trusted lightweight path (Decision 6).
- **No `shell: bash` override** → a single one-line command with no pipes
  (Decision 7).
- **Required context names unchanged** (`Host tests and benchmark gate`,
  `iOS cross-target compile`, `WASM cross-target observation`) → the job becomes
  stricter without a ruleset or required-context change (Decision 5).

### No bundled hardening (the clean distinction from Slice 26)

This is what makes Slice 32 a *pure* promotion, simpler than Slice 26. The Slice
31 review found no actionable defect in the line-geometry-query benchmark, and the
benchmark builds its sample `y` values from non-negative `sample % …` arithmetic
and the shared `deterministicScrollOffset` helper — it derives no array index from
a wrapping signed multiply, so it carries no analog of the `deterministicIndex`
crash class. The spec ("No bundled hardening") correctly scoped any code change
out, and the merged diff confirms it: **zero** lines of Swift changed. A fresh
`git diff --name-only dd6dc27..HEAD -- Sources Tests Package.swift` is empty.

### `AGENTS.md` (durable guidance)

The CI section's host-job bullet now lists `→ --line-geometry-query --gate
(blocking)` after the line-query gate and before `--memory-shape`
(`AGENTS.md:124`), and the "fail the job on perf regression" sentence now names
the line-geometry-query gate alongside the other six (`AGENTS.md:128-129`). The
command-list local invocation and the benchmark-flags lists already carried the
`--line-geometry-query` mode from Slice 31 and were correctly left unchanged. The
docs-only, iOS, WASM, ruleset, and bypass-caveat wording is unchanged. The
architecture paragraph's description of `lineGeometryAt` (added in Slice 31) is
untouched, as it should be — Slice 32 changes the *governance* of the path, not
the path.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `492fe21`)

- `git diff --name-only dd6dc27..HEAD -- Sources Tests Package.swift` → **empty**
  (no core, provider, benchmark, test, or manifest surface touched).
- `git diff --check dd6dc27..HEAD` → no output, exit `0` (no whitespace errors).
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- Ruby workflow-invariant assertion (step exists, invokes `--line-geometry-query
  --gate`, not `continue-on-error`, shares its siblings' docs-only guard, ordered
  `line-query < line-geometry-query < memory-shape`, three required job contexts
  unchanged) → `workflow_assertions_ok`, exit `0`.
- `swift build -c release` → `Build complete!` (exit 0).
- `swift test` → **160 tests, 0 failures**, plus the expected empty Swift Testing
  harness line (`0 tests in 0 suites`). Unchanged from the Slice 31 baseline, as
  expected for a slice that adds no test and changes no behavior.
- `swift run -c release ViewportBenchmarks -- --line-geometry-query --gate` → all
  five scenarios `gate=pass`, 0 failures; **all five checksums byte-identical** to
  the recorded baseline (`160641440000`, `267505512960`, `799841600000`,
  `223985600000`, `852321495040`).
- `swift run -c release ViewportBenchmarks -- --line-query --gate` → all five
  scenarios `gate=pass`; all five checksums byte-identical to the record
  (`641440000`, `63985556480`, `639841600000`, `63985600000`, `639841547520`) —
  confirming this slice touched no shared search/provider path, so `lineAt` (which
  `lineGeometryAt` composes over) is unaffected.
- `swift run -c release ViewportBenchmarks -- --gate` → all three synthetic
  scenarios `gate=pass`; checksums match the record (`1319670707200`,
  `570448232307200`, `18852477646272000`).

### Fresh local line-geometry-query numbers (macOS arm64, this review)

| Scenario | p95 (ns) | Budget p95 | Headroom |
| --- | ---: | ---: | ---: |
| uniform_1k         | 18  | 30,000  | ~1,667× |
| uniform_100k       | 20  | 60,000  | ~3,000× |
| uniform_1m         | 21  | 120,000 | ~5,714× |
| balanced_tree_100k | 128 | 300,000 | ~2,344× |
| balanced_tree_1m   | 177 | 600,000 | ~3,390× |

Consistent with the Slice 31 review's recorded macOS numbers (run-to-run noise
aside); the timing rows are non-reproducible, but the five deterministic checksums
are byte-identical to the record, and every scenario sits well over ~1,600× under
budget locally.

### Hosted Linux x86_64 budget-fit (the load-bearing evidence for this slice)

Decision 3 bet that the macOS-calibrated budgets would hold on hosted Linux, with
the one-shot PR-head run **being** that evidence. The line-geometry-query benchmark
had **never run in hosted CI** before this slice (Slice 31 kept it local-only), so
these are the first hosted Linux x86_64 numbers for the mode:

| Scenario | macOS local p95 | PR-head p95 | Post-merge p95 | Budget p95 |
| --- | ---: | ---: | ---: | ---: |
| uniform_1k         | 18  | 31  | 31  | 30,000  |
| uniform_100k       | 20  | 41  | 73  | 60,000  |
| uniform_1m         | 21  | 47  | 47  | 120,000 |
| balanced_tree_100k | 128 | 368 | 371 | 300,000 |
| balanced_tree_1m   | 177 | 424 | 430 | 600,000 |

Hosted Linux is slower and noisier than macOS arm64 (the balanced-tree p95 roughly
tripled), exactly as in prior promotions. Even so, the tightest hosted scenario
(`balanced_tree_100k` at ~368 p95 on the PR-head run) sits **~815× under budget**,
and every p99 clears its budget by a comparable margin. This is the **most generous
of the six promotions**: Slice 28's tightest hosted scenario cleared at ~244×,
where this one clears at ~815×. Notably, the balanced-tree line-geometry queries
run *faster* hosted (~368–430 ns) than line-query did at its own Slice 28
promotion (~1,413–2,456 ns) despite doing strictly more work (two extra
`offset(ofLine:)` probes) — because the intervening Slices 29/30 turned
balanced-tree `lineAt` into a single native O(log N) descent, so the composed
geometry query inherits that native path. The vertical-axis optimization arc
(29→30) paid a visible dividend right here. The one-shot blocking promotion was
unambiguously the right call — Decision 3's "stop and re-derive Linux budgets"
escape hatch was nowhere near triggered. All five checksums on both hosted runs
equal the local baseline, confirming the geometry query is deterministic across
platforms.

### Hosted runs (verified live via `gh`, at step-log level not just job conclusion)

Both runs re-verified via `gh` during this review — and, per the project's "a green
job can hide a dead `continue-on-error` step" lesson, the new gate was checked at
the **step** level, not just the job conclusion:

- **PR #62 final-head run `28646126162`** (head `6942ea4`, event `pull_request`):
  conclusion `success`; all three required jobs `success` (`Host tests and
  benchmark gate` `84953008029`, `iOS cross-target compile` `84953008041`, `WASM
  cross-target observation` `84953008021`). In the host job, step 5 `Complete
  docs-only PR` = `skipped` (correctly **not** docs-only — the PR changes workflow
  YAML), steps 8–14 are all seven blocking latency gates `success`, **step 14 `Run
  line geometry query benchmark gate` = `success`** (ran, not skipped, not
  `continue-on-error`), and step 17 `Observe realistic provider relative
  performance` ran `success` on the PR event.
- **Post-merge push run `28698965663`** on merge commit `86cd14a` (event `push`,
  branch `main`): conclusion `success`; all three required jobs `success` (`Host`
  `85113612405`, `iOS` `85113612417`, `WASM` `85113612451`). The host job again
  shows step 5 `Complete docs-only PR` `skipped`, steps 8–14 all seven gates
  `success` including **step 14 `Run line geometry query benchmark gate` =
  `success`**, and step 17 realistic-provider observation correctly `skipped` on
  the `push` event (it is the PR-only `continue-on-error` observation). **This is
  the merged-code evidence anchor for Slice 32**: the new gate is a real blocking
  step that ran on merged code and passed, not a masked one. Merge parentage
  confirms `86cd14a`'s second parent is `6942ea4`, so the proof anchors the
  actually-merged head.

PR #63 was a docs-only follow-up touching only the verification record, so it
legitimately took the trusted docs-only path; the workflow YAML has not changed
since `86cd14a`, so run `28698965663` still represents current `main`'s workflow
behavior.

## Git History

Reviewed Slice 32 commits (PR #62 → #63):

```text
3f1d2c2 docs: add line-geometry-query CI gate promotion design
2a03ff8 docs: refine line-geometry-query promotion spec per review
7825381 docs: add line-geometry-query CI gate promotion plan
ec6ffd3 ci: promote line-geometry-query benchmark to a blocking hosted gate
9ff696c docs: document line-geometry-query gate as blocking in AGENTS.md CI section
6102265 docs: record local verification for line-geometry-query gate promotion
6942ea4 docs: refresh line-geometry-query verification scope evidence
86cd14a Merge pull request #62 …
c95bb63 docs: record slice 32 post-merge proof
492fe21 Merge pull request #63 …
```

Clean, incremental, one-logical-step-per-commit with correct conventional-commit
prefixes: `docs:` for spec/plan/guidance/verification, `ci:` for the single
workflow step. The spec took two rounds (`3f1d2c2` add → `2a03ff8` refine per
review) before the plan, the workflow change is isolated in its own `ci:` commit
(`ec6ffd3`), the `AGENTS.md` doc update is separate (`9ff696c`), and local
verification is separate from implementation (`6102265`). The one extra `docs:`
commit — `6942ea4` "refresh … verification scope evidence" — updated the
verification record's own `git diff --name-only main...HEAD` scope block so it
reflected the final tree that included the verification file itself; a benign
self-referential-evidence adjustment that moved the PR head to `6942ea4`, which is
exactly the head the PR-head run `28646126162` tested. The two-PR split
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

None. The verification record carries **no evidence-accuracy defect**: the hosted
proof (PR-head run + post-merge push run) was recorded only in the post-merge
follow-up (PR #63, `c95bb63`) against the stable final head `6942ea4`, and the
source-bearing PR #62 was never described as taking the docs-only shortcut (the
record explicitly notes it is *not* docs-only because it changes workflow YAML).

### P3 / Minor But Valid

**1. Spec/implementation primitive-naming drift, still open (carried from Slice 25
P3 #3 / Slice 26 P3 #1 / Slice 28 P3 #1).** The bulk-edits spec names the join
primitive `join(_:_:)` while the implementation ships `join3`/`join2`. This is a
provider-doc hygiene item unrelated to CI; Slice 32 touches no provider source or
spec, so it is correctly **not** a Slice 32 defect — but it remains an open item
with no home slice yet. A one-line cross-reference in the bulk-edits spec would
retire it whenever a provider-touching slice next opens.

No P3 changes whether the merged result is correct; #1 is pre-existing hygiene this
slice legitimately deferred.

## Risks And Gaps

### The whole vertical-query surface is now CI-protected — no governance debt remains

With this slice, all seven latency paths (synthetic; static + mutating
variable-height; single + bulk structural mutation; and the vertical
position-query pair — `lineAt` since Slice 28 and `lineGeometryAt` now) run under
blocking hosted regression protection. There is **no remaining CI gap** forcing
another governance slice; the functional → gate-promotion cadence has drained for
the sixth time. The next slice has no CI debt forcing its hand and is free to be a
genuine capability increment.

### Budgets remain macOS-derived after this slice

Promotion confirmed the macOS budgets fit hosted Linux but did not re-derive
Linux-native budgets. That matches the standing project posture for all seven
gates and is acceptable. With seven latency gates now on hosted Linux, the
accumulated x86_64 evidence makes a dedicated Linux budget re-baseline viable
future work (Slice 31 review Option E), explicitly out of scope here.

### Balanced-tree line-geometry queries carry inherited constant-factor costs

This slice protects the current line-geometry-query path against regression; it
does not improve its asymptotics. `lineGeometryAt` composes over `lineAt` plus two
`offset(ofLine:)` probes, so the balanced-tree scenarios pay ~5 O(log N) descents
where a provider-native one-walk `(index, top, bottom)` hook would fold them to ~2
(Slice 31 review Option B), and `FenwickLineMetrics` (not exercised by this
benchmark) stays O(log²N). Those are constant-factor / inherited costs. They are
now, however, CI-protected and directly measurable against this gate's
`balanced_tree_100k` / `balanced_tree_1m` scenarios — which makes Option B the
natural, gate-backed follow-up if the constant is ever worth trimming.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative
observation remains PR-only `continue-on-error`; the `Main` ruleset keeps its
documented bypass-actor shape (the admin user can still bypass required checks).
None were in scope for Slice 32.

## Lessons For The Next Slice

1. **The clean-evidence convention held again.** The recurring stale-on-write
   evidence defect (recording PR-head proof against a still-moving head, or
   mis-classifying a source-bearing PR as docs-only) stayed absent: Slice 32
   recorded the hosted proof only in the post-merge follow-up (PR #63) against the
   stable final head `6942ea4` and explicitly flagged PR #62 as *not* docs-only.
   This is now the proven default for every source/workflow-touching slice — keep
   it, including the small `6942ea4` scope-evidence refresh that keeps the
   self-referential `git diff --name-only` block honest.
2. **A pure promotion should stay pure.** Slice 26 correctly folded in a hardening
   because the prior review found a real latent crash class; Slice 28 and Slice 32
   correctly did **not**, because their prior reviews found none. The spec
   explicitly justified zero Swift changes and the merged diff proves it. Resist
   bundling drive-by edits into a governance slice absent an evidence-backed
   reason.
3. **One-shot promotion is the right default across the entire headroom range.**
   The six promotions now span ~4.9× (Slice 26, hosted) to ~815× (this slice,
   hosted) tightest-scenario headroom, and one-shot blocking succeeded at both
   extremes with Decision 3's stop-and-retune as the standing net. Reserve
   observe-then-block only for a genuinely thin-margin gate, not as default
   ceremony.
4. **An earlier optimization arc keeps paying at promotion time.** The
   balanced-tree geometry gate promoted here is hosted-*faster* than the line-query
   gate was at its own promotion, despite doing more work — because Slices 29/30
   made balanced-tree `lineAt` a single native O(log N) descent underneath it. When
   a later slice composes over a path an earlier slice optimized, the earlier
   investment shows up as headroom in the later gate. Sequencing optimization
   before the composed-capability gate compounds.
5. **The functional → gate-promotion cadence has now completed six full cycles.**
   The CI/governance backlog opened by functional work is fully drained again. The
   engine is free to advance under complete regression protection — the next slice
   should be a genuine capability or infra choice, not more governance.

## Slice 33 Candidate Options

With Slice 32 the vertical-query surface is both **asymptotically optimal on the
balanced tree** (Slices 29/30) and **fully CI-protected** (Slices 28 + 32), and
there is **no governance debt** forcing the next slice. The project is back at the
capability-vs-infra crossroads the Slice 30 and Slice 31 reviews named, now with
the vertical geometry query hosted-blocking. The live options (carried from the
Slice 31 review, re-anchored to current state):

### Option B: Provider-native geometry-bearing descent (constant-factor win)

Add an optional `LineMetricsSource` hook returning `(index, top, bottom)` in one
tree walk, default-implemented as today's composed form, overridden by
`BalancedTreeLineMetrics` — the Slices 29/30 defaulted-hook + provider-override +
ordered-dispatch-test recipe applied to geometry. Folds the balanced tree's ~5
descents to ~2 (trims the constant, not the asymptotic class). **Now optimally
sequenced**: the gate that would measure the win (`--line-geometry-query --gate`
on `balanced_tree_*`) is, as of this slice, hosted-blocking, so the improvement is
directly and safely measurable. Small, low-risk, self-contained.

### Option C: Horizontal / point queries / wrap-aware visual rows

The larger product leap — `pointAt(x:y:)` (building directly on Slice 31's vertical
`LineGeometryLocation`), horizontal geometry, or wrapping/visual rows. Largest
design surface and the biggest step toward realistic editing of 100k+ line / >10 MB
documents; needs a fresh brainstorm + spec. The natural continuation of the
capability pivot now that the vertical geometry query is CI-protected.

### Option D: Verified closed-form uniform override (carried Slice 29/30/31 P3)

O(1) overrides for the uniform/prefix-sum providers' native index hooks,
boundary-safe against the equivalence oracles. Retires the last fallback-bound
common provider. Small, clean; lower product value.

### Option E: WASM blocking / Linux budget re-baseline (standing infra)

Promote WASM cross-target from observational to blocking (gated on stable SDK
provisioning), or re-derive Linux-native budgets from the now seven-gate-deep
accumulated x86_64 evidence and retire the macOS-calibration caveat. Standing
hygiene; independent of the capability arc.

## Recommended Slice 33 Selection

**This is a genuine product call for the user, not a forced move.** Unlike Slices
28 and 32 — each of which retired a specific CI-promotion debt and so had an
obvious next step — Slice 32 leaves **no debt outstanding**, so Slice 33 is a
direction choice among a small constant-factor deepening (B), the larger
capability leap (C), or standing infra (E).

My recommendation is to **surface the B-vs-C-vs-E product call to the user** and,
absent a stated preference, lean **Option C — horizontal / point / wrap-aware
capability**. The reasoning: the vertical axis is now complete on every dimension
the project has pursued — mapping (`lineAt`), geometry (`lineGeometryAt`), native
O(log N) descent, and blocking CI protection for both. The brief's headline goal is
realistic editing/scrolling of large documents, and the biggest unclaimed distance
to that goal is the horizontal/point/wrap axis, which `pointAt(x:y:)` would build
directly on this slice's `LineGeometryLocation`. Option C needs a fresh brainstorm
+ spec (largest design surface), which is the right way to open a new axis.

Option B is the lower-risk alternative and is *uniquely well-timed right now* — its
measuring gate went blocking in this very slice — so if the preference is a small,
fully-measurable increment before opening a new axis, B is the clean pick and
sequences naturally before C. Option E is the pick if the preference is to close
the last standing infra item (WASM-blocking / Linux budget re-baseline) while the
seven-gate hosted evidence is fresh. Whichever is chosen, keep functional/capability
work and CI/infra work in separate slices, per the project's standing convention.

## Slice 32 Review Conclusion

Slice 32 delivered the intended governance increment cleanly: the
`--line-geometry-query --gate` benchmark now runs as the **seventh** blocking
latency gate in the required host job, so runtime regressions in
`ViewportVirtualizer.lineGeometryAt` — the geometry-bearing vertical
position-query introduced in Slice 31 — block merge, sitting contiguously after the
line-query gate and before the memory-shape diagnostic. The macOS-calibrated
budgets held on hosted Linux x86_64 with the **most generous margin of the series**
(~815× under budget at the tightest hosted scenario, versus Slice 28's ~244×),
decisively validating the one-shot promotion and never approaching Decision 3's
escape hatch — helped by the Slices 29/30 native descent, which makes the composed
geometry query hosted-faster than line-query was at its own promotion. The change
is correctly scoped — **zero Swift changed** (no core, provider, benchmark, test,
or manifest surface; required contexts, docs-only behavior, and ruleset all
unchanged) — and verified at the step level on both the final PR-head run
(`28646126162`) and the post-merge push run (`28698965663`, merge commit
`86cd14a`), with all five checksums byte-identical across local, PR-head, and
merged-code runs.

The review found **no P0, P1, or P2 issues** against the merged result, and **no
evidence-accuracy defect**: Slice 32 again recorded the PR-head proof only in the
post-merge follow-up against the stable final head and never mis-classified the
source-bearing PR as docs-only. The one open P3 (spec/code primitive-naming drift)
is pre-existing hygiene this slice legitimately deferred. With all seven latency
gates now CI-protected and **no governance debt remaining**, Slice 32 cleanly
closes the vertical-query arc (mapping → geometry → native descent → full CI
protection) and hands off to a genuine product call — Option B (native geometry
descent, now gate-backed), Option C (the horizontal/point/wrap capability leap), or
Option E (WASM-blocking / Linux budget re-baseline) — for the user to direct.
