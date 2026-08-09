# Slice 52 — post-slice review (gate recalibration + bulk absolute ceiling: D-9 / D-8)

**Slice:** 52 — soft-wrap arc, **calibration route** (no map node, no brief criterion advanced)
**Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md) · **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)
**Spec:** [`specs/2026-08-08-gate-recalibration-and-bulk-ceiling-design.md`](../specs/2026-08-08-gate-recalibration-and-bulk-ceiling-design.md) · **Plan:** [`plans/2026-08-08-gate-recalibration-and-bulk-ceiling.md`](../plans/2026-08-08-gate-recalibration-and-bulk-ceiling.md)
**Merged:** [PR #123](https://github.com/maldrakar/swift-text-engine/pull/123), merge commit `955dec8` (merge commit — child SHAs preserved). 8 commits over `6533435..955dec8`.
**Merged proof:** post-merge `push`-to-`main` run `31307764210` @ `955dec8` — green at **step** level (3/3 jobs, 24/8/10 steps with **zero** non-success; the only skipped step per job is the dormant `Complete docs-only PR`; 362/0 tests; twelve blocking gate steps; 46 `gate=pass` / 0 `gate=fail`; 41 lines at `budget_absolute_p99_ns=1666666` + 5 at `=16666666` + **0** at `=exempt`; four WASM + four iOS `blocking=true` passes; zero `continue-on-error` in the run or the workflow). Recorded via docs PR [#124](https://github.com/maldrakar/swift-text-engine/pull/124), verification §12.

## What shipped

The slice the user chose over the topological node-3 lean, after live evidence at
selection time showed the calibration base was ten slices stale. Two things that look
unrelated and are not: the evidence under every gate budget, and the classification that
decides which absolute ceiling a mode answers to. Delivered via subagent-driven
development (8 tasks), every task clean on its **first** review — no fix loops.

- **Phase 0 — `gov_p95` names which term governs each p95 budget.**
  `derive-gate-budgets.sh` prints `gov_p95=median|max` between `budget_p99=` and
  `margin_p95=`. D-9's thin axis had been a watch-by-hand instruction since slice 41;
  it is now a property of every re-derivation. The tie rule reads `>=` where the `b95`
  line beside it reads `>` — deliberate and commented: on a tie the budget *is* resting
  on the median term, and harmonizing the operators would silently change the rule.
  The two new self-test assertions are the **first standing checks on the budget
  arithmetic at all** — both pre-existing assertions covered `window_run_ids` only.
- **Phase 1 — every budget re-derived against evidence including the last ten slices.**
  The corpus had not been appended since 2026-07-18. Harvested with `--limit 100
  --corpus` (idempotent); **33 of 70** planned runs carried samples, the rest docs-only.
  27 of 46 budgets moved, **6 tightened**. Corpus rows and budget literals landed in
  **one commit** by design: split, the intermediate tree fails
  `testEveryCommittedBudgetReproducesFromCorpus`.
- **Phase 2 — `isFrameHotPath: Bool` → a total `AbsoluteCeiling`.**
  `{ scrollFrame, discreteAction }`, chosen per mode by an exhaustive switch with no
  `default:` arm. `.scrollFrame` = `GateLimits.frameNanoseconds / 10`, `.discreteAction`
  = `GateLimits.frameNanoseconds` = 16_666_666 ns. **No mode is exempt.**
  `bulk_structural_mutation` prints a number where it printed `exempt`, and its live
  margin under the product ceiling is visible on every hosted run for the first time.
  `testEveryGatedBudgetIsUnderItsClassCeiling` lost its filter and rose from 41 budgets
  to all **46**.

Suite **362/0** (up from 361 — the one new paired bulk test). Zero
`Sources/TextEngineCore` / `Sources/TextEngineReferenceProviders` change; zero workflow
change; the 46 benchmark checksums are byte-identical to slice 43's anchor.

## Acceptance-criteria status

All ten ACs discharged (spec §Acceptance Criteria). Rows marked **re-verified** were
re-run in this review rather than read off the record.

| AC | Status | Evidence |
|---|---|---|
| 1 idempotent, provenance-checked append | ✅ | `--dry-run` plan (70 planned / 30 skipped) recorded from **stderr**; both run-level failures hand-checked to `host job = success`; append-only proven by the pre-existing 1994 lines being a **byte-identical prefix** of the new 3543 — **re-verified** |
| 2 window flushed, checked directly | ✅ | Pre-work red recorded *before* the harvest: 16 runs contributing 8 `realistic_provider` rows each → **0** after. Smallest window id `29701547123` > the `29692848870` boundary — **re-verified** |
| 3 thin axis observed mechanically | ✅ | `gov_p95` on all 46 lines; both tie branches asserted in `--self-test`; Drill 7 carries the shell red into a red `swift test` |
| 4 budgets reproduce + directional diff | ✅ | 49 literal values over 34 source lines; all 46 reproduce, enforced by `testEveryCommittedBudgetReproducesFromCorpus` — **re-verified** |
| 5 total classification | ✅ | Both identifier scans clean (`isFrameHotPath`, `absoluteP99Nanoseconds`, `budget_absolute_p99_ns=exempt` — none survive in `Sources`, `Tests`, `AGENTS.md`); 46 numeric ceilings + 46 headrooms on the hosted run |
| 6 bulk ceiling pinned | ✅ | `testDiscreteActionClassIsExactlyDocumented` + `testAbsoluteCeilingsArePinnedToTheFrameMath`; Drills 2, 3, 5 |
| 7 full-coverage floor pin + rewritten doctrine message | ✅ | Pin iterates all 46 unfiltered; neither forbidden remediation survives in the message; Drill 4 |
| 8 seven recorded drill reds | ✅ | §10, drills 1–7 verbatim, both expected-collateral reds labelled, `tree clean` after each — **three re-run from scratch in the task review, byte-identical** |
| 9 hosted proof, step level, checksums | ✅ | PR-head `31268616348` @ `45a1591` + post-merge `31307764210` @ `955dec8`; 46 tuples diff empty pairwise **and** against slice 43's 46-value anchor — **re-verified** |
| 10 paper trail | ✅ | Spec `82041ae`, plan `6533435`, verification + arc + ledger `b731eed`, hosted evidence PR #124 |

## Strengths

- **The two halves compose, and the margin is real.** Phase 2's pin asserts every one
  of Phase 1's 46 freshly-derived budgets sits under its class ceiling. Binding
  scenario per class: `structural_mutation|1m_lines_200_visible_overscan_50` at 2.87×
  under `.scrollFrame`, `bulk_structural_mutation|1m_lines_batch_4096` at 2.78× under
  `.discreteAction`. Against *observed* hosted p99 both sit ~36× under. Tripping the
  pin needs a genuine ~2.8× slowdown, which is exactly the intended trigger.
- **The one direction the arithmetic cannot catch was controlled empirically.** Six
  budgets **tightened** — an old freak sample aged out of the trailing N=20 window,
  which is precisely what slice 41 built the window to allow. Nothing in a
  re-derivation runs the benchmark, so a budget that has moved closer to observed
  latency than a noisy runner clears is invisible until a hosted run. The slice named
  the six as a watch-list *before* the run, then closed the loop: all six pass on
  **three** hosted samples, tightest `column_geometry_query|prefixsum_1m` at 5.1× p95.
  The risk did not materialize, and the record says so with numbers.
- **A composition hazard was found and cleared rather than assumed away.**
  `budget_absolute_p99_ns=` contains `p99_ns=` as a substring, and bulk now emits a
  *number* there where it emitted `exempt`. A loosely-matching harvester would ingest
  `16666666` as a latency into every future corpus append. It does not —
  `harvest-gate-corpus.sh` splits each field on `=` and compares `kv[1] == "p99_ns"`
  exactly — but the whole-branch review checked instead of reasoning from "probably
  fine".
- **The static enforcement point is named, and the doctrine lives where it fires.**
  Under the floor pin the runtime `budget_absolute_exceeded` branch has **no reachable
  inhabitant**: any p99 above a class ceiling is also above that mode's regression
  budget, and `budgetExceeded` is evaluated first. So the pin's red *is* the ceiling
  firing, at `swift test` time, before the gate steps in the same job run. Its failure
  message was rewritten rather than relabelled — the old text offered "reclassify as
  not frame-hot-path" (a state this slice deletes) and "raise the ceiling fraction"
  (the one response the doctrine forbids).
- **A finding that invalidates prior compliance evidence was reported, not buried.**
  D-17 (below) says the idiom `AGENTS.md`'s own D-2 rule recommends is un-failable in
  the shell agents actually run. The honest consequence — that slice 51's 13
  `${PIPESTATUS[0]}` sites, counted as *evidence of D-2 compliance*, do not hold — is
  written into the ledger row rather than softened.

## Issues

No P0/P1. Six P3s and one nit. Two are findings this review produced; the rest were
found during the slice and deferred here.

**P3 #1 — the `gov_p95` self-test's second assertion shipped without a recorded red
(found and drilled in this review; it bites).** The slice recorded seven drills for
seven guarantees, but the Phase 0 self-test carries **two** assertions and a self-test
exits at the first failure — so Drill 7's operator flip (`>=` → `<`) reddens the
median-branch assertion and returns before the max-branch one is ever evaluated. The
max branch therefore had no evidence it could fail. Drilled here with a mutation that
leaves the first assertion passing:

```
# gov95 = (8 * m95 >= 3 * x95) ? "median" : "max"   ->   gov95 = "median"
$ ./.github/scripts/derive-gate-budgets.sh --self-test
self_test=fail label=gov_p95=max when 3*max > 8*med
  expected: [max]
  actual:   [median]
exit=1
```

It bites. The generalizable lesson, and the reason this is worth a row: **in a
fail-fast harness, one mutation can only ever evidence one assertion.** A drill count
that matches the guarantee count is not the same as coverage when several assertions
sit behind a single early-exit gate. Same shape as slice 51's P3 #2, one level down.

**P3 #2 — the plan's own AC9 checksum assertion fails on a healthy run.** Task 8
Step 3 asserts `[ "$N" -eq 46 ]` over `extract_checksums` applied to a hosted run log.
The literal function yields **54**: the non-gate `memory_shape` (5) and
`memory_observation` (3) diagnostic steps also emit `mode=`/`scenario=`/`checksum=`
fields. §9's *local* extraction never saw it because the local capture loops only the
twelve gated modes. Recorded with the `grep -v` fix in verification §12.5, but the
plan **template** is unfixed and the next slice copying the recipe will rediscover it.
Fold-in candidate for whichever slice next writes an AC9 step.

**P3 #3 — `frame-hot-path` vocabulary outlives the concept in test prose.** Five sites
in `GateLogicTests.swift` (including a test *name*,
`testAbsoluteCeilingFiresForFrameHotPathMode`, whose sibling reads
`…ForBulkModeAtItsOwnCeiling`) still speak a classification the slice deletes. Nothing
is false — the concept maps 1:1 onto `.scrollFrame` — and the AC5 scans are
identifier-based so they cannot see prose. Renaming restores symmetry. Fold-in for the
next slice touching this file.

**P3 #4 — the non-gateable modes' ceiling class is pinned by nothing.**
`testDiscreteActionClassIsExactlyDocumented` filters on `isGateable`, so the four
non-gateable modes (`rangeOnly`, `memoryShape`, `memoryObservation`, `wrapCompute`)
classify under a total function but are covered by no test. This is **documented where
someone would look** — on the `absoluteCeiling` switch itself, in the words "do not
expect a test to catch a wrong choice here" — and the value is inert because the
absolute tokens are emitted only inside the `includeGate` branch. Recorded so the
inertness is a decision rather than an oversight, and so the day a wrap mode becomes
gateable, this is the row that says what to check. Directly relevant to map node 6.

**P3 #5 — a new gateable mode choosing `.scrollFrame` passes silently.** The
class-membership pin is bidirectional for `.discreteAction` (moving bulk out, or any
mode in, reddens it) but a new gateable mode landing in the `.scrollFrame` arm trips
nothing. That is the *tighter* ceiling and `GateFloorTests` still catches an
over-budget one, so the default is safe — but "safe by accident of which arm is
larger" is worth naming before wrap modes arrive.

**P3 #6 — `AGENTS.md` residuals the slice did not reach.** Two, both pre-existing and
both now more collidable because this slice tripled the absolute-ceiling passage:
D-10's stale "see" pointer (a verification doc carrying the retired
`WASM cross-target observation` context name with no superseded banner), and the
lingering fact that "ceiling" names two different objects ~140 lines apart. The second
was *partly* fixed in-slice (`:578` now says "the headroom ceiling"); the general
audit of the word was not done.

**Nit — the Phase 1 commit message describes a threshold the harvester does not
implement.** `24a1548` says "harvested every hosted run newer than run id
`29606487287`", but `harvest-gate-corpus.sh` dedups by **set membership**, not a max-id
cutoff, so run `29579314733` (older, never previously harvested, 53 rows) was correctly
included. Zero budget effect — it sits far below the window floor `29701547123`.
Plan-mandated wording; unfixable without rewriting history on a merged PR.

### Process observations

Worth recording because they are about the *method*, not the slice:

- **The plan's TDD step was unreachable in one task, and the substitution was
  stronger.** Task 5 Step 2 predicted a compile-error red; at that point in the
  sequence the old symbols still existed and the new pins referenced only
  already-landed ones, so the suite passed. The implementer discharged the obligation
  by mutation instead (flip bulk to `.scrollFrame`, observe both new pins redden,
  revert), and the reviewer reproduced it byte-for-byte and judged it *strictly
  stronger* than the red the plan asked for — a compile error only proves the **old**
  references break, whereas the mutation proved the un-filtered pin actually reaches
  the five newly-covered bulk budgets. The plan text was wrong; the process caught it.
- **A brief file was never generated for Task 8** (controller slip — it ran from
  inline instructions), and a *stale* `task-8-brief.md` from slice 39 sits at the
  deprecated flat `.superpowers/sdd/` path. The task reviewer noticed the absence,
  substituted the plan's Task 8 section, and verified every requirement independently.
  No damage, but the failure mode is real: a stale sibling artifact at a path an agent
  might resolve loosely.

---

# Recommendation (skill Mode 2)

Map pass first (its output is the updated arc file): Slice 52 was the **calibration
route** and consumed **no map node** — the third slice of that shape, after the process
slice 48 and the debt slice 51. Nothing it shipped touched wrap feasibility, so nodes
3–9 and fork V stand unrevised and un-relearned; there is no correction to absorb this
pass. What it *did* change is the ground node 6 stands on: the recipe that criterion 4
names by reference now rests on evidence including the last ten slices, and a future
wrap mode will classify itself into a ceiling class instead of inheriting a boolean
designed before wrap existed. The next step is **topological**, not a fork: node 3
(y→row) is the next criterion-3 analog behind node 2, and the first genuine fork
remains node 8 (host order) / fork V.

### Scoreboard delta

**None — by design**, and stated as such at selection time (arc decision log,
2026-08-08). Slice 52 advanced no brief criterion and moved no evidence link.

The honest nuance, which is not a status change: criterion 4 binds future wrap gates to
«по существующему рецепту калибровки (harvest → derive)» and to the absolute 60 FPS
ceiling. Slice 52 repaired both of those inputs. That is de-risking work *for* a named
criterion, not progress *on* it — criterion 4 stays `open` until a wrap mode is
actually gated.

Still open or partial:

| # | Criterion | Status |
|---|---|---|
| 1 | Width change does not recompute the document | partial — core half retired (Slice 50); `done` gated on fork V (the exact reindex is Ω(N)) |
| 2 | Core memory not linear with wrap on; `--memory-shape` extended | open |
| 3 | Wrap-aware query analogs + ∞ equivalence | partial — per-line + whole-document equivalence proven, `compute` analog shipped; **y→row** and **point→(row,cell)** remain |
| 4 | 100k+/10 MB wrapped scroll inside budgets + blocking wrap gates | open — both *inputs* refreshed by this slice; the criterion itself untouched |
| 5 | Incremental edits under wrap inside frame-hot-path budgets | open |
| 6 | Thin iOS + browser verification hosts | open |

### Debt ledger delta

**Discharged (1), amended (1), new (1).**

- **D-8** (P2, born slice 46, carried since slice 43) → `discharged`
  ([PR #123](https://github.com/maldrakar/swift-text-engine/pull/123)). The item that
  by its own statement "needs a product-target decision before any ceiling can be
  derived": the user supplied the target at selection time and it became ordinary
  work. No mode is exempt; the floor pin covers all 46.
- **D-9** (P2) → **statement amended in place, status stays `open`** (the D-15
  precedent — never silently re-scope). Its *shape-transition* half is discharged **by
  fact**: the window holds no pre-slice-45 run and no run contributing more than one
  `realistic_provider` row. Its *thin-axis* half stays open and now carries **the rule
  and the ratio, not a list** — median-governed exactly when `max / med <= 2.67`, true
  for 45 of 46 after this harvest — because the single max-governed scenario **moved**
  (`line_query|uniform_1k` → `column_query|prefixsum_100k`) in this one harvest, so any
  named list is stale on arrival.
- **D-17** (P2, new) → `open`. `${PIPESTATUS[0]}`, recommended **by name** in
  `AGENTS.md`'s D-2 conventions, expands to the empty string under zsh — and
  `[ "" -eq 0 ]` is *true* there, so the assertion **inverts into a pass**. No
  committed script is affected (all four are bash and none uses it); the blast radius
  is agent-run plan/verification blocks, **including the 13 sites slice 51's review
  counted as D-2 compliance evidence**. Remediation recorded, not applied — choosing
  the replacement idiom is its own decision.
- **New P3s from this review:** #1 (max-branch assertion, now drilled — record as
  closed-by-this-review evidence rather than open debt), #2 (plan AC9 checksum
  assertion), #3 (frame-hot-path vocabulary), #4 (non-gateable classes unpinned),
  #5 (new-gateable-mode silent `.scrollFrame`).

**Open counts after this review:** P2 — **3** (D-7 `deferred(user)`, D-9 thin-axis
half, D-17 new). P3 — 8 open (D-5 deferred, D-10, D-11, D-13, D-14, D-15, plus this
review's #2–#5 folded in), 2 accepted-risk (D-4, D-16).

**Escalation check.** D-7 (born slice 46, `deferred(user, 2026-07-22; re-affirmed
2026-08-06)`) is at ≥ 3 completed slices and is a legally deferred state, so it does
not force. **D-17 is new** and does not escalate yet — but it is the only open P2 whose
subject is the repo's own assertion practice, and it invalidates a prior slice's
compliance evidence, so it appears in the options below on merit rather than by rule.

### Falsifiability audit

Guarantees this slice **added or changed**, each with evidence it can fail:

| Guarantee | Evidence it can fail |
|---|---|
| `gov_p95` names the governing term (median branch) | Drill 7 — operator flip → `expected: [median] actual: [max]`, carried into a red `swift test` via `ScriptSelfTestTests` |
| `gov_p95` names the governing term (**max** branch) | **No in-slice red — drilled in this review** (P3 #1): forcing `gov95 = "median"` → `expected: [max] actual: [median]`, exit 1. It bites |
| Bulk has an absolute ceiling at all | Drill 1 — gate the check on `.scrollFrame` → `("nil") is not equal to ("Optional(…budgetAbsoluteExceeded)")` |
| Bulk's ceiling is a whole frame, not a tenth | Drill 2 — move bulk to the `.scrollFrame` arm → `XCTAssertNil failed`. **Not interchangeable with Drill 1**: at p99 = 16_666_667 both ceilings are breached and the reason is the same either way, so a drill recorded against the wrong test would look like evidence and be none |
| `.discreteAction` class membership is exactly `{bulk}` | Drill 3 — move `.structuralMutation` in → two-element set |
| Every gated budget is under its class ceiling (46, unfiltered) | Drill 4 — raise bulk p99 to 20_000_000 → `("20000000") is not less than ("16666666")` + labelled collateral red in `testEveryCommittedBudgetReproducesFromCorpus`. Independently re-run under mutation in the Task 5 review, which confirmed the un-filtered pin reaches the five newly-covered bulk budgets |
| Both ceilings are pinned to the frame math | Drill 5 — bare `1_666_667` → `("1666667") is not equal to ("1666666")` + labelled collateral. Note the two bracket tests still **pass** here (both use `scrollFrame.p99Nanoseconds + 1`, which moves with the mutation) — which is exactly why this drill needs its own target |
| Every gated line publishes a numeric ceiling | Drill 6 — restore the `exempt` branch → `XCTAssertTrue failed` on the missing `=16666666` |
| The 46 recalibrated budgets reproduce from the committed corpus | Drill 4's collateral red; the standing test is `testEveryCommittedBudgetReproducesFromCorpus` (slice 44) |

**Two guarantees this slice added carry no failure evidence, by construction, and both
are recorded above rather than left silent:** the exhaustiveness of the
`absoluteCeiling` switch is compiler-enforced (a new mode is a compile error until it
classifies itself — no test can redden for it), and the four non-gateable modes' class
is pinned by nothing (P3 #4). Neither spawns a mandatory option: the first is a
stronger guarantee than a test, and the second is inert until a non-gateable mode
becomes gateable — which is precisely map node 6, where P3 #4 is the row to read.

No other guarantee shipped un-drilled. The audit's one catch, P3 #1, is closed by the
drill recorded in it.

### Candidate options

**Option A — node 3: the y→row wrap analog (LEAN).**
*Advances:* criterion 3 (the next query analog behind node 2 — wrap-aware `lineAt` over
the visual-row axis). *Map:* node 3, the forced topological next step; nodes 4–9 sit
behind it. *Debt:* folds in **D-13** (P3 — the per-axis binary-search triplication;
node 3 would add a **fourth** copy of the same body unless consolidated, so this is the
slice where the fold-in is cheapest and most defensible) and is the natural home for
**P3 #3** (vocabulary) only if it touches `GateLogicTests`, which it likely does not.
*Trade-off:* leaves D-17 open another slice.

**Option B — the assertion-practice repair (D-17 + the plan-template defects).**
*Advances:* no criterion. *Map:* consumes no node — a fourth non-map slice.
*Debt:* discharges **D-17** (P2) and folds in **P3 #2** (the AC9 checksum assertion
that fails on a healthy run) and **D-14**/**D-15** (P3, script classification and
dispatcher shape). *Trade-off:* the honest case for doing it now is that D-17 makes a
documented convention actively harmful — an agent following rule 1 today writes an
assertion that reports success on failure — and every future plan inherits it. The
honest case against: it is the *fourth* consecutive slice that would advance no wrap
criterion (48 process, 51 debt, 52 calibration, this), and the arc has six criteria
open with only two partial. D-17 is one slice old and does not escalate.

**Option C — node 5: `--memory-shape` extended to the wrap path.**
*Advances:* criterion 2, which is fully `open` and untouched since the arc began.
*Map:* node 5, reachable now (it needs node 2's visual-row axis, which shipped).
*Debt:* none directly. *Trade-off:* it is out of topological order — nodes 3 and 4 are
the criterion-3 analogs and node 5 was mapped after them — but nothing forces that
order, and criterion 2 is the only wrap criterion with *no* evidence of any kind.
Worth naming because "no evidence at all" is a different risk from "partial".

**Lean: Option A (node 3).** It is the topological next step, it is the third
consecutive review to name it, and the arc cannot afford a fourth consecutive
no-criterion slice — 48, 51, and 52 were each individually well-justified, and that is
exactly how a brief criterion stays open for ten slices, which is the failure this
skill exists to prevent. D-17 is real and I would rather it did not wait, but it is one
slice old, it does not escalate, and its blast radius is plan-authoring practice that
the *next plan* can simply avoid by not using the idiom — which is a note in the plan,
not a slice. Fold **D-13** into node 3 (the fourth-copy argument makes it cheaper now
than later) and carry a one-line "do not use `${PIPESTATUS[0]}`" instruction in that
plan.

**Routing: topological next step, not a fork** — so this review **selects** Option A
rather than presenting a product call. The user can override, and the one input that
would justify overriding is a decision to treat D-17 as urgent enough to preempt the
map (Option B).
