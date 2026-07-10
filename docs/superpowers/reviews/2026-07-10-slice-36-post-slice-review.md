# Slice 36 Post-Slice Review

Date: 2026-07-10

## Scope Reviewed

This review covers Slice 36: **column-geometry-query CI gate promotion**. It wires
the local-only `--column-geometry-query --gate` benchmark (shipped in Slice 35)
into the hosted `Host tests and benchmark gate` job as the **ninth blocking
latency gate**, so a `columnGeometryAt` runtime regression now fails the required
host job on hosted Linux x86_64 — not just locally. This retires the
**CI-promotion debt** Slice 35 re-opened, exactly as the Slice 35 review's
recommended **Option A** and the user-selected direction.

Slice 36 is the **eighth gate-promotion slice** in the established cadence
(Slices 15, 21, 24, 26, 28, 32, 34, then 36) and the **exact horizontal twin of
Slice 32** (which promoted the vertical `line-geometry-query` gate). It is the
"promote a benchmark that has never run in hosted CI" shape — like Slices 24, 26,
28, 32, 34 — so there was no observation step to flip and no prior hosted Linux
evidence; the one-shot PR-head run produced the Linux budget-fit evidence.

This is a **pure CI + docs slice — zero Swift-source change of any kind**. It adds
one blocking `run:` step to `.github/workflows/swift-ci.yml`, updates `AGENTS.md`
to reflect the promotion, and records local + hosted proof. It touches **no**
`TextEngineCore`, `TextEngineReferenceProviders`, benchmark Swift source
(scenario / budget / helper), or `Package.swift`. The `columnGeometryAt`
capability, its benchmark mode, and its budgets all already existed from Slice 35
and are promoted **unchanged** — the five per-scenario checksums are byte-identical
to the Slice 35 values, which is the free "benchmark workload unchanged" integrity
check that this slice's central Non-Goal (no benchmark source edit) demands.

The slice was delivered through **two** PRs, both now merged:

- **PR #74** (`slice-36-column-geometry-query-ci-gate-promotion`), title *"Slice 36:
  promote column-geometry-query to a blocking CI gate"*, verified head
  `bb24c95f86a9d0ce415f83f6bd1172c7a808595a` (`bb24c95`), merged to `main` as
  `52a2eafe092fefa2dcbf27b74fdaa454276729af` (`52a2eaf`) by `maldrakar` at
  2026-07-10T17:22:02Z — the workflow gate step, the `AGENTS.md` update, the
  design + plan + verification docs, with the verification record's `Hosted Proof`
  section left as an explicit `## Hosted Proof — Pending` placeholder.
- **PR #75** (`slice-36-post-merge-hosted-proof`), title *"Slice 36 follow-up:
  record column-geometry-query gate hosted proof"*, verified head
  `d8595f90eb7859cca6b1d00077962438c5871a02` (`d8595f9`), merged as
  `3fc045ac3a1aea596536d2236b4231b2fd8d00a2` (`3fc045a`, current `main` HEAD) by
  `maldrakar` at 2026-07-10T18:38:28Z — a **genuinely docs-only** follow-up that
  touches only the verification Markdown (`git diff --name-only 52a2eaf..3fc045a`
  → the single verification file) and fills the `Hosted Proof` section with the
  real PR-head + post-merge push run IDs and the hosted per-scenario headroom
  table.

**Both PRs are merged at review time**, so `main`'s verification record carries
real hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-07-10-column-geometry-query-ci-gate-promotion-design.md`
- `docs/superpowers/plans/2026-07-10-column-geometry-query-ci-gate-promotion.md`
- `docs/superpowers/verification/2026-07-10-column-geometry-query-ci-gate-promotion.md`
- `docs/superpowers/reviews/2026-07-10-slice-35-post-slice-review.md`,
  `docs/superpowers/reviews/2026-07-04-slice-32-post-slice-review.md` (the vertical
  twin), `docs/superpowers/reviews/2026-07-07-slice-34-post-slice-review.md` (the
  prior horizontal-gate promotion)
- `.github/workflows/swift-ci.yml`, `AGENTS.md`
- PR #74 / #75 metadata, hosted run evidence (step-level conclusions and gate
  output), merge parentage, and the merged Slice 36 diff

The reviewed Slice 36 range (PR #73 review merge → current `main` HEAD), excluding
this review document itself, is:

```text
95b735e..3fc045a
```

`git merge-base --is-ancestor 95b735e 3fc045a` confirms the Slice 35 review merge
(PR #73, `95b735e`) is a clean ancestor, so the range captures exactly the Slice 36
work. Merge parentage confirmed via `git rev-list --parents`: `52a2eaf` (PR #74)'s
parents are the base `95b735e` and the verified PR head `bb24c95`
(`52a2eaf^2 == bb24c95`); `3fc045a` (PR #75) merges the post-merge-proof commit
`d8595f9` onto `52a2eaf` (`3fc045a^2 == d8595f9`). A fresh name-only diff confirms
the range touches only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and
`docs/**` — it does **not** touch `Sources/**`, `Tests/**`, or `Package.swift`
(`git diff --name-only 95b735e..3fc045a -- Sources Tests Package.swift` is empty).

## Product Brief Alignment

The brief (`docs/initial-project-brief.md`) requires that regression benchmarks
block merge on performance degradation
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
Before this slice, that principle held for **eight** blocking hosted latency gates
(synthetic, static variable-height, variable-height-mutation, structural-mutation,
bulk-structural-mutation, line-query, line-geometry-query, column-query) but **not**
for the horizontal within-line **geometry** query path introduced in Slice 35 —
its gate was local-only.

Slice 36 closes that single gap. It makes the brief's "benchmark gates block merge"
principle true for `columnGeometryAt`: a constant-factor slowdown, an added
allocation, or a cache-unfriendly change that preserves query count and correctness
(so it slips past `swift test`) but degrades wall-clock p95/p99 now fails the
required host job. The hosted job already ran `swift test`, so `columnGeometryAt`'s
**correctness** (half-open boundary, clamp, `.empty`, the structural uniform oracle,
the `columnAt`-parity test, the reconstruction round-trip, the `PrefixSumColumnMetrics`
equivalence oracle, and the ordered event-log dispatch test) was already enforced
hosted; this slice adds the **latency** guard that unit tests structurally cannot
provide. Every hard constraint is untouched by construction — no Swift changed, so
Foundation-free / zero-dependency / Embedded-compatible / O(1)-core-memory /
iOS+WASM-portable all hold trivially, and the review re-confirmed the two
Foundation scans empty anyway.

Because the promoted benchmark reuses the `--column-query` / `--line-geometry-query`
budget shape verbatim and `columnGeometryAt` composes over the already-hosted-gated
`columnAt` plus two O(1) `columnOffset` probes, the promotion carries generous
headroom and does not lean on a thin margin (below).

## Delivered Design

Merged Slice 36 diff (`95b735e..3fc045a`), non-docs surface only:

```text
 .github/workflows/swift-ci.yml |  4 ++++
 AGENTS.md                      | 10 ++++++----
 2 files changed, 10 insertions(+), 4 deletions(-)
```

(Plus the design, plan, and verification docs under `docs/superpowers/**`.)

### The workflow gate step (Decisions 1, 2, 4, 7)

`.github/workflows/swift-ci.yml` gains exactly one step in the
`host-tests-and-benchmark-gate` job, inserted between the column-query gate and
the memory-shape diagnostic:

```yaml
      - name: Run column geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-geometry-query --gate
```

This is exactly right and matches its siblings byte-for-byte in shape:

- **Blocking.** No `continue-on-error: true`, so a budget breach fails the job.
- **Same docs-only guard** as every adjacent gate
  (`if: steps.change-scope.outputs.docs_only_pr != 'true'`), so docs-only PRs still
  skip it via the trusted lightweight path (Decision 6).
- **Same scratch-path** (`/tmp/text-engine-host-build`) and the same
  `swift run -c release … ViewportBenchmarks -- …` invocation as its siblings, so
  budgets stay single-sourced in `Sources/ViewportBenchmarks` and are **not**
  duplicated in YAML (Decision 2).
- **Ordered** column-query → column-geometry-query → memory-shape, keeping all
  nine blocking latency gates contiguous and failing before lower-priority
  diagnostics. Placing it directly after `--column-query` also buys differential
  diagnosis (Decision 4): because `columnGeometryAt` composes over `columnAt`, a
  column-query **pass** with a column-geometry-query **fail** localizes the
  regression to `columnGeometryAt`'s own delta (its two geometry probes + the
  fraction arithmetic), while a both-fail points at the shared `columnAt` /
  provider path.

The step is a one-line Swift command with no pipes or shell-specific behavior, so
it correctly needs no `shell: bash` override (Decision 7). No other workflow step
moved or changed.

### AGENTS.md (Decision — documentation)

`AGENTS.md` is updated in two places, and the diff is minimal and accurate:

- The architecture paragraph's `columnGeometryAt` sentence drops the trailing
  "Its `--column-geometry-query --gate` is **local (not-yet-CI)**." and now reads
  "`--column-geometry-query` is its blocking host-job CI gate." — matching how the
  adjacent `columnAt` sentence already reads for `--column-query`.
- The CI section's `Host tests and benchmark gate` bullet adds
  `→ --column-geometry-query --gate (blocking)` to the step sequence after
  `--column-query --gate (blocking)` and before `--memory-shape`, and extends the
  "fail the job on perf regression" sentence to name the column-geometry-query
  gate. All other CI wording (memory diagnostics, RSS observation, realistic
  observation, iOS, WASM, docs-only shortcut, ruleset, bypass caveat) is unchanged.

The local `--column-geometry-query --gate` command entry already present in the
Commands list stays consistent with its siblings (Slice 35 added it).

This is a textbook governance slice: the smallest possible change that makes an
existing, proven benchmark path merge-blocking, with the doc kept in lockstep.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `3fc045a`)

- `git diff --name-only 95b735e..3fc045a -- Sources Tests Package.swift` → **empty**
  (no Swift, provider, benchmark, or manifest surface touched); the whole range is
  `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**` only.
- `git diff --check 95b735e..3fc045a` → no output, exit `0` (no whitespace errors).
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `swift build -c release` → `Build complete!` (exit 0).
- `swift test` → **213 tests, 0 failures**, plus the expected empty Swift Testing
  harness line (`0 tests in 0 suites`). Unchanged from the Slice 35 baseline, as
  expected — this slice adds no tests and changes no Swift.
- Workflow-invariant assertion (Ruby YAML load of `swift-ci.yml`) →
  `workflow_assertions_ok`: the new step exists in the
  `host-tests-and-benchmark-gate` job, invokes `--column-geometry-query --gate`, is
  not `continue-on-error`, shares its sibling's `if:` docs-only guard, is ordered
  column-query → column-geometry-query → memory-shape, and the three required job
  context names (`Host tests and benchmark gate`, `iOS cross-target compile`,
  `WASM cross-target observation`) are unchanged.
- `swift run -c release ViewportBenchmarks -- --column-geometry-query --gate` → all
  five scenarios `gate=pass`, `failures=0`; the five checksums are byte-identical to
  the Slice 35 / verification-record values (`160641440000`, `267505512960`,
  `799841600000`, `223985600000`, `839521520640`), confirming the promoted benchmark
  workload is unchanged. Local p95 landed 15–44 ns against 30k–120k ns budgets
  (~1,400×–5,700× headroom).
- `swift run -c release ViewportBenchmarks -- --column-query --gate` → all five
  scenarios `gate=pass`, checksums unmoved (`641440000`, `63985556480`,
  `639841600000`, `63985600000`, `639841560320`) — confirming this slice touched no
  shared search/provider path and the sibling gate is unaffected.

### Hosted runs (verified live via `gh`, at step-log level not just job conclusion)

Both runs re-verified via `gh` during this review — and, per the project's "a green
job can hide a dead `continue-on-error` step" lesson, checked at the **step** level:

- **PR #74 final-head run `29108998305`** (head `bb24c95`, event `pull_request`):
  conclusion `success`; all three required jobs `success`. In the host job the new
  step **#16 `Run column geometry query benchmark gate` = `success`** (not skipped,
  not `continue-on-error`), sitting between #15 `Run column query benchmark gate` and
  #17 `Run memory shape diagnostic`; step #19 `Observe realistic provider relative
  performance` = `success` (it runs on PR events).
- **Post-merge push run `29110714042`** on merge commit `52a2eaf` (event `push`,
  branch `main`): conclusion `success`; all three required jobs `success`. In the host
  job, step **#16 `Run column geometry query benchmark gate` = `success`**; step #5
  `Complete docs-only PR` = `skipped` (correctly **not** docs-only — the merge touches
  `.github/workflows/**`, which the detector rejects before the Markdown allow rule);
  the eight pre-existing gates #8–#15 all `success`; and step #19 `Observe realistic
  provider relative performance` correctly `skipped` on the `push` event. **This is the
  merged-code evidence anchor for Slice 36.** Merge parentage confirms `52a2eaf`'s
  second parent is `bb24c95`, so the proof anchors the actually-merged head.

I independently extracted the hosted `column_geometry_query` rows from the push run's
gate-step log: all five scenarios `gate=pass`, `failures=0`, with the five checksums
**byte-identical** to the local + Slice 35 values, and the hosted p95/p99 rows
(`34/63`, `46/75`, `52/84`, `67/105`, `74/109`) matching the verification record's
push table exactly — so the record's hosted headroom table is grounded in the real
logs, not asserted. The two watch scenarios behaved as the spec predicted:
`prefixsum_100k` held the least multiplicative headroom (~895× post-merge) and
`prefixsum_1m` the largest absolute latency (74 ns p95 post-merge), both comfortably
inside budget. Decision 3's stop-and-retune path was therefore **not** triggered — no
`continue-on-error`, no silent budget widening.

PR #75 was a genuinely docs-only follow-up (only the verification Markdown), so it
legitimately took the trusted docs-only path; the workflow YAML has not changed since
`52a2eaf`, so run `29110714042` still represents current `main`'s workflow behavior.

## Git History

Reviewed Slice 36 commits (PR #74 → #75):

```text
a6c3dd5 docs: add column-geometry-query CI gate promotion design
372ef69 docs: add slice 36 column-geometry-query CI gate promotion plan
82e0372 ci: add blocking column-geometry-query benchmark gate
422b7ff docs: list column-geometry-query as the 9th blocking CI gate
bb24c95 docs: record column-geometry-query CI gate local verification
52a2eaf Merge pull request #74 …
d8595f9 docs: fill column-geometry-query gate hosted proof
3fc045a Merge pull request #75 …
```

Clean, one-logical-step-per-commit with correct conventional-commit prefixes:
design → plan precede the single substantive `ci:` change (`82e0372`, the four-line
workflow step); the `AGENTS.md` update (`422b7ff`) and the local verification record
(`bb24c95`) land as isolated `docs:` commits; the post-merge hosted proof lands as its
own `docs:` follow-up (`d8595f9`). The PR head is `bb24c95`, exactly the head the
PR-head run `29108998305` tested — no post-head drift. The two-PR split
(implementation + local/PR-head proof, then docs-only post-merge proof) is the
standard pattern for a workflow-touching slice. One benign nuance: the plan's Task 4
committed the plan doc at push time, but in the actual history the plan (`372ef69`)
was committed right after the design and before the implementation commits — which is
if anything more faithful to the project's "spec → plan precede code" convention. Not
a defect.

## Code Review Findings

Reviewed across workflow correctness, scope discipline, evidence integrity, and the
hard constraints.

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, the gate step is blocking, correctly guarded, correctly
ordered, and single-sources its budgets through the executable; the promoted
benchmark workload is provably unchanged (five checksums byte-identical locally **and**
in the hosted push-run log); the scope is airtight (no Swift/provider/benchmark/manifest
touched); and the hard constraints hold by construction (no Swift changed) and were
re-confirmed anyway.

### P2 / Production Readiness

None. The merged result is proven green on merged code at step level (`29110714042`),
and the verification record carries **no evidence-accuracy defect**: at PR #74's head
(`bb24c95`), the `Hosted Proof` section was an explicit `## Hosted Proof — Pending`
placeholder (no stale-on-write run IDs against a still-moving head), and the real
hosted run IDs plus per-scenario headroom table were added only in the docs-only
post-merge follow-up (PR #75, `d8595f9`) once the final head was stable. The
source-bearing PR #74 was never described as taking the docs-only shortcut (the record
documents that the merge is workflow-bearing and the docs-only step is skipped hosted).
Decision 3's requested per-scenario hosted headroom table is present for all five
scenarios, and I verified its numbers against the live logs.

### P3 / Minor But Valid

**1. Budgets remain macOS-calibrated after this slice (standing, accepted).** The
promotion confirms the macOS budgets *fit* hosted Linux (with ~880×–2,300× hosted
headroom) but does not re-derive Linux-native budgets. This matches the standing
project posture for every gate before it and is the deferred Option E (Linux budget
re-baseline). Now that nine gate promotions' worth of hosted x86_64 evidence has
accumulated, a dedicated re-baseline is increasingly well-supported — but it is
correctly out of scope here.

**2. The horizontal axis stays fallback-bound; no 2D composite (carried, out of
scope).** This slice protects the current column-geometry-query path against
regression; it does not improve its asymptotics. Both shipped horizontal providers
(`UniformColumnMetrics`, `PrefixSumColumnMetrics`) still answer the located-cell
search via the generic `binarySearchColumnIndex` default (Slice 35 review Option D),
and there is still no `pointAt(x:y:)` 2D composite (Option B). Both are documented
Non-Goals / Future Slices, not gaps in this slice — and, notably, this slice's gate
makes the horizontal geometry latency contract hosted-blocking *before* either
follow-on builds against it.

**3. `join(_:_:)` spec/code naming drift, still open (carried from Slice 25 P3 #3 /
Slices 26/28/32/34/35 P3).** The bulk-edits spec names the join primitive `join(_:_:)`
while the implementation ships `join3`/`join2`. Provider-doc hygiene unrelated to this
slice; Slice 36 touches no provider source or the bulk-edits spec, so it is correctly
**not** a Slice 36 defect — but it remains an open item with no home slice yet. A
one-line cross-reference in the bulk-edits spec would retire it whenever a
provider-touching slice next opens.

No P3 changes whether the merged result is correct.

## Risks And Gaps

### The CI-promotion debt is now closed — a debt-free handoff

This was the one governance follow-up Slice 35 handed forward, and Slice 36 retires it:
`--column-geometry-query --gate` is now a blocking hosted gate, so both engine axes are
CI-protected and geometry-bearing. Slice 36 itself introduces **no new measurable path**
(it promotes an existing one), so — like the debt-free Slice 34 handoff and unlike a
capability slice — it hands the next slice off **debt-free**. There is no functional →
promotion pair left dangling.

### Budgets remain macOS-derived (standing)

As above: promotion confirms fit, not a Linux re-baseline. Accepted, time-boxed against
Option E.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative observation
remains PR-only `continue-on-error`; the `Main` ruleset keeps its documented
bypass-actor shape (the admin user can still bypass required checks). None were in scope
for Slice 36, and none were altered by it (the workflow-invariant assertion confirms the
three required contexts are unchanged and no new required context was added).

## Lessons For The Next Slice

1. **A one-shot promotion of a high-headroom benchmark is the right default — again.**
   For the eighth time in the cadence, adding the gate directly as blocking (rather than
   an observe-then-flip two-step) was pure win: the single PR-head run both enforced the
   gate and produced the hosted Linux budget-fit evidence, and with ~880×–2,300× hosted
   headroom Decision 3's stop-and-retune net never had to fire. Reserve observe-then-flip
   for a genuinely thin-margin promotion; this was not one.
2. **The clean-evidence convention held for the tenth source/workflow-touching slice.**
   The recurring stale-on-write defect (recording PR-head proof against a still-moving
   head, or mis-classifying a workflow-bearing PR as docs-only) stayed absent: Slice 36
   left an explicit `## Hosted Proof — Pending` placeholder in PR #74, filled the real run
   IDs only in the docs-only post-merge follow-up (PR #75) against the stable head, and
   documented PR #74 as workflow-bearing. This is the proven default; keep it.
3. **Verify hosted evidence at the step level, and cross-check the recorded numbers
   against the live log.** Confirming step #16 `= success` (not a green job hiding a dead
   `continue-on-error` step) and then extracting the actual hosted checksums + p95/p99
   rows from the gate-step log turned the verification record's hosted headroom table from
   an assertion into a re-verified fact. Cheap, and it is what makes "proven green on
   merged code" load-bearing.
4. **Track which kind of slice you are shipping.** Slice 35 added a measurable path and so
   owed a promotion; Slice 36 *is* that promotion and reuses no new path, so it hands off
   debt-free. Naming this explicitly keeps the functional → promotion rhythm honest and
   tells the next slice it starts from a clean governance slate.

## Slice 37 Candidate Options

With Slice 36 closing the pair, **both** engine axes are now CI-protected **and**
geometry-bearing (`lineAt` + `lineGeometryAt` + gates on the vertical axis; `columnAt` +
`columnGeometryAt` + gates on the horizontal). Slice 36 hands off **debt-free**, so unlike
the forced-move promotion this slice was, Slice 37 is a genuine product crossroads — the one
the Slice 35 review and Slice 36 spec both surfaced. The live options:

### Option B: `pointAt(x:y:)` 2D composite (the product leap, now fully unblocked)

Compose the horizontal `ColumnGeometryLocation` with the vertical `LineGeometryLocation`
into a single point → (line, cell) hit-test over both metrics sources — the primitive a
realistic click-to-caret / selection / hit-test consumer wants on large documents. It was
waiting on horizontal geometry (Slice 35) **and** on that geometry's latency being
hosted-blocking (this slice) before anything optimized or built against it — both now
delivered, so B is fully unblocked. Largest design surface: it needs a fresh brainstorm +
spec for how two **independent** metrics sources compose (the combined result/clamp shape,
the empty-line and both-axes-clamped cases, whether it is one query or a documented
composition of the two existing ones). Highest product value; the natural lean given the
user's sustained steer toward editing affordances (Slice 32 review → `columnAt`, Slice 33
review → column-query gate, Slice 34 review → `columnGeometryAt`, Slice 35 review → this
gate).

### Option D: horizontal native / closed-form `columnIndex` overrides (fallback-bound cleanup)

O(1) / native-prefix-search overrides of `columnIndex` for `UniformColumnMetrics` and
`PrefixSumColumnMetrics`, boundary-safe against the equivalence oracle — the horizontal
mirror of the vertical Slices 29/30 native-descent work. Retires the horizontal
fallback-bound-provider item and is now directly measurable against **both** horizontal
hosted gates (`--column-query` from Slice 34 and `--column-geometry-query` from this slice).
Small and clean; lower product value than B. A provider-native one-walk `(index, left,
right)` geometry hook (the constant-factor probe trim) is the adjacent optimization.

### Option E: standing infra (WASM blocking / Linux budget re-baseline)

Promote WASM cross-target from observational to blocking (gated on stable SDK provisioning),
or re-derive Linux-native budgets from the now nine-gate-deep accumulated hosted x86_64
evidence and retire the macOS-calibration caveat. Standing hygiene; independent of the
capability arc, and the Linux re-baseline is better-supported now than at any prior point.

## Recommended Slice 37 Selection

Recommended Slice 37 is a **product call to surface to the user**, leaning **Option B —
`pointAt(x:y:)` 2D composite**.

The reasoning: Slice 36 was the last forced move — it closed the only outstanding governance
debt, and with both axes now CI-protected and geometry-bearing the project has reached exactly
the crossroads the Slice 35 review predicted. B is the highest-value increment and is now
**fully** unblocked (both axes geometry-bearing *and* their latency contracts hosted-blocking),
and it is the consistent trajectory of the user's editing-affordance steer across the last four
slices. Its cost is that it is a real design step — two independent metrics sources composing —
so it wants its **own brainstorm + spec** rather than a drive-by, which is why this should be
put to the user as a direction choice (B vs the smaller Option D provider cleanup vs the
Option E infra hygiene) before a spec is written. Whichever is chosen, keep functional/capability
work and CI/infra work in separate slices, per the project's standing convention.

## Slice 36 Review Conclusion

Slice 36 delivered its governance increment cleanly: it promoted the local-only
`--column-geometry-query --gate` to the **ninth blocking hosted latency gate** with a single
four-line workflow step and a minimal two-place `AGENTS.md` update, and **no Swift-source change
of any kind**. The promoted benchmark is provably unchanged — the five per-scenario checksums are
byte-identical to the Slice 35 values both locally and in the hosted push-run log — so the gate
protects the exact `columnGeometryAt` path Slice 35 shipped, now against runtime regression on
hosted Linux x86_64 rather than only locally. The step is blocking, correctly docs-only-guarded,
and correctly ordered (column-query → column-geometry-query → memory-shape), keeping all nine
blocking latency gates contiguous.

The review found **no P0, P1, or P2 issues** and **no evidence-accuracy defect**: PR #74's
final-head run `29108998305` and the merged-code push run `29110714042` (merge commit `52a2eaf`,
second parent the tested head `bb24c95`) are both green at step level, with the new gate step
`= success`, all eight pre-existing gates run, the docs-only step correctly `skipped` on the
workflow-bearing merge, and the realistic-observation step correctly `skipped` on push. The
clean-evidence convention held for the tenth source/workflow-touching slice — an explicit
`Pending` placeholder in PR #74, filled only in the genuinely docs-only post-merge follow-up
(PR #75) against the stable head. The three P3s are standing/carried (macOS-calibrated budgets;
fallback-bound horizontal providers + no 2D composite; the pre-existing `join` spec/code naming
drift this slice legitimately did not touch). Every hard constraint holds by construction and was
re-confirmed: Foundation-free (both scans empty), zero-dependency, O(1) core memory,
cross-target-portable, 213 tests / 0 failures.

Slice 36 retires the CI-promotion debt Slice 35 re-opened and hands off **debt-free**: both engine
axes are now CI-protected and geometry-bearing, no functional → promotion pair is left dangling, and
the project reaches the genuine product crossroads — the newly-and-fully-unblocked 2D `pointAt(x:y:)`
hit-test (Option B, the lean), the horizontal native-descent cleanup (Option D), or standing infra
(Option E) — to be put to the user as the Slice 37 direction call, kept in its own slice per the
project's functional-vs-CI separation convention.
