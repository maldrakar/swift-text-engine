# Gate Recalibration + Bulk Absolute Ceiling (D-9 / D-8) Design

- **Slice:** 52 — calibration route (no wrap-arc criterion, no map node)
- **Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md) (selection recorded
  in its decision log, 2026-08-08)
- **Ledger:** [`docs/superpowers/debt-ledger.md`](../debt-ledger.md) — D-8 moves
  `deferred(user, 2026-07-22)` → `scheduled(slice-52)`; D-9 is re-observed and
  its statement amended

## Status

Proposed. Brainstormed 2026-08-08; this document is the ratified design.

Four questions were decided with the user during selection and brainstorming and
are recorded as Decisions below: the slice boundary (recalibration **and** D-8,
not one or the other), the harvest breadth (everything newer than the corpus
max), the product target for D-8 (one whole 60 FPS frame), and the ceiling model
(a total two-class classification rather than a second boolean or an optional).

**Revised 2026-08-08 after the user's spec review**, which found one P1, five
P2s, and six P3s. Every one was verified against the tree and every one held.
The three that changed load-bearing parts of the design:

1. **AC9 was unmeetable.** It compared this slice's checksums against
   `2026-08-07-cross-target-script-hardening.md`, which carries **3**
   `checksum=` lines (all `mode=pipeline`), not 46. The fix was a **three-way
   local ↔ PR-head ↔ push tuple diff** internal to this slice — the slice-44 §5
   pattern — plus a cross-slice anchor. This round sized that anchor at three
   values; the third round found the sizing wrong and widened it to 46 (below).
2. **AC2 checked a proxy rather than the invariant.** A run-id threshold assumes
   run ids order workflow *versions*, which they do not: a branch cut before
   slice 45 merged could produce a higher run id carrying the old shape. The
   invariant itself is one `awk` line — no run in the window contributes more
   than one `realistic_provider` row — and it is discriminating today: **16 of
   the 20** window runs contribute 8 rows each. It is now the primary check and
   the run-id threshold is corroboration.
3. **The window check violated the plan-assertion conventions this repository
   just wrote down.** `stale="$(derive … | awk …)"` takes the pipeline's status
   from `awk`, so a failing `derive-gate-budgets.sh` yields an empty `stale` and
   the assertion passes. Rule 1, in the document that claims every command below
   it is status-sensitive.

The remaining items are folded in as the AGENTS.md touch points in Documentation
Updates (four paragraphs, none of which AC5's scan could see), Decision 10's two
diagnosed branches, the tightening-direction risk, Decision 8's correction (the
old test's *body* changes, not just its comment), drill 4's `--filter` and its
expected collateral red, and the non-gateable modes' classification.

A second review round proposed making Goal 3 mechanical rather than one-off, and
it is adopted as **Decision 13** (`gov_p95` in the derive output) with Decision 12
amended to name the exception. Its compatibility claims were verified against the
tree; one estimate was optimistic in a way that matters and is recorded there —
the script's `--self-test` covers `window_run_ids` and *nothing else*, so the
budget arithmetic has no standing check today and this token's drill is the first.

**A third review round validated the revision and found three more**, all in the
verification block rather than in the design, and all verified against the tree:

1. **AC9 was still unmeetable, for a new reason.** The extraction
   `grep -o 'scenario=[^ ]* .*checksum=[0-9]*'` is greedy: `.*` swallows
   `p95_ns`, `p99_ns`, and every `headroom_*` field, all of which *must* differ
   between local and hosted (hosted runs 2-3x slower — that is the calibration
   authority rule). The three-way diff could never come out empty. Worse, the
   tuple was `(scenario, checksum)`, and scenario names are shared by up to
   **six** modes each — `uniform_1m`, `uniform_100k`,
   `1k_lines_20_visible_overscan_0`, `100k_lines_80_visible_overscan_5`,
   `1m_lines_200_visible_overscan_50`. The key is `(mode, scenario)`.
2. **The 46-value cross-slice anchor exists after all, and the second draft
   weakened AC9 to three values on a false premise.** The premise conflated a
   *table* with a *document*: slice 43's Section 8 table holds 45 rows, but the
   document as a whole carries **46 distinct `(mode|scenario, checksum)` tuples**
   across all twelve gated modes, `realistic_provider` included. This is the same
   fact as the correction the second draft made to the first review — that
   `realistic_provider` did print `checksum=` before slice 45,
   `756321289736960` — followed one step further. Slice 51's three `pipeline`
   values appear in that document unchanged, so the set is still current.
3. **The window-file redirect reintroduced the hole it was written to close.**
   Moving `derive … --window-run-ids` out of a pipe and into a file fixed the
   pipeline-status problem and left the redirect's own status unchecked, under a
   block that declares no `set -e`. A failing derive leaves an empty
   `window.txt`, and then **both** AC2 checks pass vacuously. Fixing the shape of
   a check is not the same as making it status-sensitive.

The remaining third-round items are folded in below: `--dry-run` writes its
decisions to **stderr** (a naive `> file` capture records nothing), the
`AGENTS.md` paragraph runs to `:431` rather than `:427`, Decision 13's self-test
needs a re-invocation form this script has never used, and the measured
distribution of the thin axis (**45 of 46**) now appears in Decision 11,
Decision 13, and AC3 instead of being discovered during execution.

**A fourth review round re-verified every measurable claim in this document
against the tree and found no factual error** — the corpus counts, the 45-of-46
thin-axis distribution and its lone exception, the 46-tuple anchor, the bulk
margins, and every file:line reference including the third round's `:431`
correction all hold. It raised two P2s and five P3s, all about what the document
*says* rather than what it measures, and all are folded in:

1. **Decision 9 contradicted itself, and the contradiction had a code
   consequence.** It claimed Decision 7's pin makes the runtime absolute check
   unable to fire *and* that the check "fires once the regression budget has
   climbed past 16.67 ms" — but the pin is exactly what forbids that budget from
   being committed. The branch is unreachable by construction, not merely
   "today", which is the same no-inhabitants defect Decision 4 rejects an
   optional ceiling for. Decision 9 is rewritten around the true enforcement
   point (the static pin), and the consequence the earlier drafts missed is now
   in Component Design: that test's **failure message** currently offers two
   remediations this slice invalidates.
2. **`gov_p95` was observable but not watched, and its real value was
   mis-stated.** A token nobody diffs decays exactly like the hand-transcription
   Decision 13 rejects. More usefully, a `max → median` flip is the *signature*
   of the budget-tightening risk this document already names as having no
   pre-hosted control — a connection no draft drew. Decision 13, the risk entry,
   and the verification block now carry it, with a zero-code directional diff as
   the control.

The five P3s are folded in as: Decision 6's product rationale restated so it
survives its own 10%/90% premise, the anchor's 54-raw-lines → 46-tuples
collapse explained where it is asserted, two count assertions closing AC5's
unchecked half, a comment on the deliberately unquoted `$mode`, and the
brief-alignment argument added to Source Context and the arc entry.

The next step after sign-off is the TDD implementation plan (`writing-plans`),
written under the four plan-assertion conventions `AGENTS.md` gained in slice 51.

## Source Context

Slice 51 closed the debt route and its post-slice review ran the outer-loop
checklist. That review's lean was Option A (wrap map node 3, y→row); the user
chose **Option C** instead — the calibration route — after live evidence gathered
at selection time showed the calibration base was ten slices stale. The same call
gave D-8 the product target it had been waiting on since slice 43, which is what
converts it from "cannot be scheduled" into ordinary work.

**This is a debt route that de-risks a named brief criterion**, and the
distinction is worth stating rather than leaving the slice to read as
housekeeping. The wrap brief's fourth success criterion commits future wrap work
to this exact machinery — «новые wrap-режимы становятся блокирующими CI-гейтами
**по существующему рецепту калибровки (harvest → derive)**», holding «p95/p99-бюджеты
и абсолютный потолок 60 FPS». Both halves of that sentence are what this slice
repairs: the recipe's evidence base currently contains no post-slice-45 run, and
the absolute ceiling is a boolean designed before wrap existed. After this slice a
future `wrap_compute` gate calibrates against evidence that includes the last ten
slices, and a future wrap mode **classifies itself** into a ceiling class rather
than inheriting one. The scoreboard still moves by zero — this slice advances no
criterion and consumes no map node, like slices 48 and 51 — but the reason to run
it now is not only that D-8 and D-9 are old.

Seven facts measured while exploring, all load-bearing:

- **The corpus has not been appended since 2026-07-18** (commit `9ce6975`,
  "harvest slice 40 post-merge run and re-derive budgets under the window"). It
  carries 48 distinct run ids; its maximum is `29606487287`.
- **The N=20 window therefore contains zero post-slice-45 runs.** Slice 45's own
  runs are `29692848870` (PR head) and `29694705807` (post-merge push), both
  above the corpus maximum. Every one of the twelve blocking budgets rests on
  pre-slice-45 evidence.
- **Nothing is red.** `derive-gate-budgets.sh` over the committed corpus
  reproduces all **46** gated scenarios byte-identically, so
  `testEveryCommittedBudgetReproducesFromCorpus` passes. This is staleness, not
  breakage — the distinction matters, because it means the slice is refreshing
  evidence, not repairing a failure.
- **62 hosted runs are newer than the corpus maximum** (2026-07-17 … 2026-08-08),
  all inside log retention. Roughly half are docs-only PRs, which skip the heavy
  path and print no `p95_ns=` lines at all — the corpus self-filters them, since
  a run with no sample lines contributes no rows.
- **Two of the 62 carry a run-level `failure`** (`29701333581`, `29701547123`,
  both from slice 46's WASM promotion). Both were checked job-by-job: `Host tests
  and benchmark gate` is **`success`** in each; only `WASM cross-target
  observation` failed. Their samples are legitimate measurements taken on a
  hosted runner with every gate passing.
- **The binding bulk scenario has structural margin.** From the committed corpus:

  ```
  bulk_structural_mutation|1m_lines_batch_4096  n=20
    p95[med=362205 max=514326]  p99[med=399530 max=550764]
    budget_p95=2900000  budget_p99=5800000
  ```

  `budget_p99` is governed by the `2 × budget_p95` term, and `budget_p95` by the
  `8 × median(p95)` term — so `budget_p99 = 16 × median(p95)`. Against a
  16_666_666 ns ceiling that leaves 2.87× on the budget and ~30× on the observed
  p99 maximum: the ceiling is breached only if that scenario's median p95 nearly
  triples.

- **The thin axis is not a short list — it is nearly everything.** Measured over
  the committed corpus, **45 of the 46** p95 budgets are already governed by the
  `8 × median` term. The sole exception is `line_query|uniform_1k`
  (`8 × med = 192` against `3 × max = 219`). The rule behind the count is
  arithmetic and does not rot: a budget is median-governed exactly when
  `max / med <= 2.67`, and hosted runner noise essentially never produces a
  worst-to-median ratio that large. So the `3 × max` term is close to vestigial
  on p95, and D-9's surviving half describes the normal state of the recipe
  rather than an occasional condition. This is why Decision 13's token is worth
  having and why Decision 11 records a **rule and a ratio**, not a list.

`everyGatedBudget()` reads the scenario functions directly rather than holding a
second copy of the numbers, so the budgets have exactly one home
(`Sources/ViewportBenchmarks/*Benchmark.swift`) and cannot drift between the
runtime gate and the floor test.

## Problem

Two recorded gaps, one in the calibration data and one in the gate policy.

**D-9 — the calibration base is stale, and its self-healing prediction was never
tested.** The ledger records D-9 as "the p95 thin axis … the realistic
shape-transition half self-heals as pre-slice-45 rows age out of the N=20
window". That prediction cannot have begun: no harvest has run since slice 45
changed the `realistic_provider` line shape, so the window is *entirely*
pre-transition. Concretely, `realistic_provider|100k_lines_10mb_text` shows
`n=128` — 8 shape-2 rows per run across 16 runs — where a post-slice-45 run
contributes exactly one row. The budget under it is derived from a statistic the
mode no longer prints.

The second half of D-9 is structural rather than temporal: when the windowed
`3 × max` term relaxes, a p95 budget rests on the `8 × median` backup term alone.
That half is a watch-item, not a defect, and it has never been observed by name —
nobody has written down *which* scenarios are currently on it.

**D-8 — `bulk_structural_mutation` has no product ceiling.** Slice 43 introduced
the absolute 60 FPS ceiling for frame-hot-path modes and deliberately exempted
bulk edits: a multi-line paste or range delete is a discrete user action that may
legitimately span more than one frame, and no product target existed for it. The
exemption was honest but it left the mode gated on its regression budget alone —
and a regression budget is anchored to a moving median, so it cannot see slow
drift that successive legitimate re-derivations ratify. The ledger has carried
this as an open P2 since slice 43, deferred three times for want of a target.

## Scope

In scope, in this order:

1. **Phase 0 (tooling).** Add the `gov_p95` token to `derive-gate-budgets.sh` and
   its two self-test assertions (Decision 13). It goes first so the Phase 1 sweep
   already carries the token and no second sweep is needed to produce the
   evidence AC3 asks for.
2. **Phase 1 (data).** Capture the pre-harvest budget baseline; harvest every
   hosted run newer than the corpus maximum into the corpus; sweep-re-derive
   **all** modes; update every budget literal the recipe now produces differently;
   record which p95 budgets are median-governed and which budgets moved in which
   direction. The baseline comes first because it is unrecoverable afterwards.
3. **Phase 2 (policy).** Replace the exemption with a total two-class absolute
   ceiling; give `bulk_structural_mutation` a ceiling of one whole 60 FPS frame;
   generalize the four pins that depend on the old boolean.
4. **Paper trail.** Spec, plan, verification record, arc decision-log entry,
   ledger status changes.

Out of scope — see Non-Goals.

## Goals

1. Every gated budget is derived from hosted evidence that includes the last ten
   slices, and reproduces from the committed corpus.
2. The N=20 window contains no pre-slice-45 run, so D-9's shape-transition half is
   closed by fact rather than by prediction.
3. The p95 thin axis becomes **mechanically observable**: `derive-gate-budgets.sh`
   prints `gov_p95=median|max` beside every budget, so which scenarios rest on the
   median term alone is answered by the tool at every future re-derivation, not
   transcribed by hand once. This slice's verification record quotes that output.
4. Every gated mode carries an absolute product ceiling; none is exempt.
5. `bulk_structural_mutation`'s ceiling is one 60 FPS frame, fixed and derived
   from the frame constant, never corpus-derived.
6. Every one of the 46 committed budgets sits under the ceiling of its own class,
   enforced by a test. That test is the product target's enforcement point — its
   red is the ceiling firing — and it is also why the runtime absolute check cannot
   redden a clean tree (Decision 9).

## Non-Goals

- **D-7 (harvester provenance).** Re-affirmed `deferred` at the slice-51
  selection. This slice checks its two `failure` runs by hand and records the
  check; it does not add a conclusion filter. A filter that is not pinned is
  worse than none, and pinning it is D-7's own spec.
- **Retiring the harvester's shape-2 branch.** Explicitly rejected when the slice
  boundary was chosen. After this slice the window no longer uses that branch, so
  it becomes a retirement candidate — that becomes a ledger row at the post-slice
  review, not work here.
- **D-14 / D-15** (script classification and dispatcher shape) and **D-13** (core
  binary-search triplication) — different concerns, different slices.
- **Any change to `.github/workflows/swift-ci.yml`.** Bulk already runs as a
  blocking `--gate` step; this slice adds no CI step and does not touch
  `WorkflowShapeTests`.
- **Any change to engine or provider source.** The benchmark checksums must come
  out byte-identical; that is an acceptance criterion, not a hope.
- **Any change to the three gate failure reasons.** `budget_absolute_exceeded`
  already exists and already carries the right instruction; bulk simply starts
  being able to report it.

## Decisions

### Decision 1 — Three phases: tooling, then data, then policy

Phase 1 (harvest + re-derive) lands before Phase 2 (the ceiling). The reason is
mechanical rather than stylistic: Phase 2 adds a test asserting that every gated
budget sits under its class ceiling. Written against stale budgets, that pin
would have to be repaired inside the same slice the moment the fresh numbers
land. Written against fresh budgets, it is correct on arrival.

Phase 0 (the `gov_p95` token) precedes both for a weaker but real reason: the
sweep is the evidence AC3 records, and a sweep run before the token exists would
have to be run again afterwards. Nothing depends on it beyond that.

### Decision 2 — Harvest everything newer than the corpus maximum, including the two `failure` runs

`--limit 100 --corpus <corpus>`: the corpus dedup skips already-harvested ids
before fetching their logs, so a generous limit costs only the listing call. This
takes all 62 candidates, of which ~30 carry samples — comfortably more than the
20 the window needs, so the pre-slice-45 tail is guaranteed to be flushed. The
narrower `--limit 40` default was rejected: it yields roughly 20 sample-carrying
runs, exactly on the boundary, and a docs-only count slightly higher than
estimated would leave the tail in place and silently fail Goal 2.

The two run-level failures are included. What makes a run dangerous to harvest is
not a red conclusion but a **host job that failed on its budget**: those samples
are the slow ones, and ingesting them raises `max()` and loosens the very budget
they violated. Neither of these two is that case — both host jobs are `success`
and only the WASM job failed. The check is per-run and recorded in the
verification document; systematizing it is D-7.

### Decision 3 — Harvest and re-derivation are ONE commit

`testEveryCommittedBudgetReproducesFromCorpus` compares every committed budget
literal against a re-derivation from the committed corpus. Appending corpus rows
in one commit and updating the literals in the next leaves an intermediate tree
where that test is red. "One logical step per commit" therefore resolves here to
**one** commit containing the new corpus rows and every budget literal the recipe
now produces differently. Phase 2 splits into ordinary TDD steps.

### Decision 4 — A total two-class classification replaces the boolean

```swift
enum AbsoluteCeiling {
    case scrollFrame      // GateLimits.frameNanoseconds / 10 = 1_666_666
    case discreteAction   // GateLimits.frameNanoseconds      = 16_666_666

    var p99Nanoseconds: Int64 { ... }
}

extension BenchmarkMode {
    var absoluteCeiling: AbsoluteCeiling { /* exhaustive switch */ }
}
```

`isFrameHotPath: Bool` is removed, and with it the concept of exemption. Two
alternatives were considered and rejected:

- **A second boolean** (`isDiscreteAction` beside `isFrameHotPath`) is the
  smallest diff, but it requires the two flags to stay mutually exclusive and
  jointly total with nothing enforcing either property — the repository's own
  "pins must model what runtime reads" lesson, and it leaves the `exempt` output
  branch reachable in principle and dead in fact.
- **An optional ceiling** (`Int64?`, `nil` = exempt) keeps exemption available at
  the cost of a branch with no inhabitants — a code path that cannot fire, which
  this repository treats the same way it treats a gate that cannot fail.

The total function keeps the property that made the original design safe: an
exhaustive switch forces a newly added mode to classify itself.

### Decision 5 — Class belongs to the mode, nanoseconds belong to the limits

`BenchmarkMode.absoluteCeiling` answers *which class*; `AbsoluteCeiling.p99Nanoseconds`
answers *how many nanoseconds*, and both values are computed from
`GateLimits.frameNanoseconds`. `GateLimits.absoluteP99Nanoseconds` is **removed**
rather than kept as a synonym for `.scrollFrame.p99Nanoseconds`: with two ceilings
in play, a bare "the absolute ceiling" is no longer a well-formed reference, and
every call site should have to name the class it means.

### Decision 6 — The bulk ceiling is one whole 60 FPS frame, and it is FIXED

`AbsoluteCeiling.discreteAction.p99Nanoseconds == GateLimits.frameNanoseconds ==
16_666_666`.

**The product statement, phrased so it survives the premise it inherits.** The
scroll-frame ceiling is 10% of a frame because the other 90% belongs to shaping,
rasterization, and UI outside the headless core. An earlier draft extended that
sentence by saying the core's share of a bulk edit "is allowed to be a whole
frame's worth rather than a tenth" — which does not survive its own premise: a
4096-line paste unquestionably triggers shaping and rasterization too, so a
ceiling that hands the core 100% of a frame leaves 0% for the very layers whose
existence justified the 10%. The number is right; that derivation of it is not.

What actually distinguishes the two classes is **whether the frame may be
dropped**. A scroll frame must not drop, so every participant is rationed and the
core's ration is a tenth. A discrete action is one the user has already accepted a
perceptible pause for, so it *may* cost a dropped frame — and the core's budget
for the action it triggered is one frame's worth of work. The 10%/90% split keeps
meaning what it meant, and 16_666_666 follows from "one dropped frame" rather than
from "the core may consume a whole frame".

The derivation is frame-based on purpose. Two alternatives were put to the user
with their arithmetic: 10 ms (10% of the 100 ms "feels instantaneous" threshold,
1.72× over the binding budget) and 100 ms (10% of the 1 s "flow of thought"
class, 17× over it — comfortable, and too weak to ever fire). The user chose the
frame derivation.

Like the scroll-frame ceiling, it is **never recalibrated and never
corpus-derived**. On breach the response is to fix the code or the architecture.
A ceiling that scales with batch size was rejected outright: it would be a second
calibration surface and would undo the one property that makes an absolute
ceiling worth having.

### Decision 7 — The floor pin loses its filter

`GateFloorTests.testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling` currently
reads `everyGatedBudget().filter { $0.mode.isFrameHotPath }` — bulk is simply not
checked. With every mode classified, the filter disappears and each budget is
compared against the ceiling of its own class. This is strictly stronger: the
number of budgets under the pin rises from 41 to all 46.

That test is what guarantees the runtime absolute gate cannot redden a clean
tree, and the guarantee now extends to bulk.

### Decision 8 — The existing bulk test keeps its assertion and changes its meaning

`testAbsoluteCeilingDoesNotFireForBulkMode` feeds a bulk summary with
`p99 = 1_666_667` and asserts `gateFailureReason == nil`. Under the new model that
assertion still holds — 1.67 ms is far below bulk's own 16.67 ms ceiling — but it
now proves something different: not "bulk has no ceiling" but "bulk is not held to
the *scroll-frame* ceiling".

What survives is the **assertion**, not the text around it. Its body reads
`GateLimits.absoluteP99Nanoseconds + 1`, and Decision 5 deletes that symbol.
Five test bodies in `GateLogicTests` reference it — lines 227, 228, 235, 246,
257 — plus two in `GateFloorTests` (416, 418) and a comment in
`BenchmarkOptions` (91). Each becomes `AbsoluteCeiling.scrollFrame.p99Nanoseconds`
or the class it actually means. The plan must budget for touching bodies, not
comments.

Its new companion is where D-8 actually lands: the same shape at
`p99 = 16_666_667` with a passing regression budget must report
`.budgetAbsoluteExceeded`.

The pair does more than state the change; it **brackets the ceiling from both
sides**, and neither test alone would. The old one fails if bulk's ceiling drops
to 1_666_667 or below — the "bulk got dragged back onto the scroll-frame ceiling"
mutation. The new one fails if the ceiling rises above 16_666_667 or disappears
altogether. Together they confine the value to `(1_666_667, 16_666_666]`, and the
frame-math pin nails it to the exact number inside that interval.

This bracketing is why the drill table below does not contain the obvious-looking
mutation "classify bulk as `.scrollFrame`, expect the new test to redden". It
would not redden: at `p99 = 16_666_667` a 1.67 ms ceiling is breached just as a
16.67 ms one is, and the reported reason is `.budgetAbsoluteExceeded` either way.
Each of the two mutations reddens exactly one of the two tests.

### Decision 9 — The product ceiling is enforced statically; the runtime reason is defense-in-depth

Earlier drafts of this decision said two incompatible things: that Decision 7's
pin makes the runtime absolute check unable to fire, *and* that the check "exists
for the future — it fires once slow drift has pushed the regression budget past
16.67 ms". The pin is precisely what forbids that budget from ever being
committed, so the second sentence describes a state the first sentence makes
unreachable. The resolution is not to weaken either claim but to name the
enforcement point correctly, and doing so makes the guarantee **stronger** than
the version it replaces.

**The unreachability is structural, not temporal:**

```
pin (Decision 7):      ∀ gated budget:  budget_p99 < ceiling(its class)
observed p99 > ceiling  ⟹  observed p99 > budget_p99
                        ⟹  budgetExceeded, which is evaluated FIRST
⟹ the budgetAbsoluteExceeded branch has no reachable inhabitant
```

This holds for `.scrollFrame` exactly as it does for `.discreteAction`; it is not
a property of bulk's current 2.87× margin, and no re-derivation can create the
gap, because the re-derivation that would is the one `swift test` rejects.

**So the product gate is the static test, and its red IS the ceiling firing.**
When slow drift — ratified by a series of individually legitimate re-derivations,
which is exactly what a median-anchored regression budget cannot see — finally
produces a re-derived budget at or above the class ceiling,
`testEveryGatedBudgetIsUnderItsClassCeiling` fails at `swift test`, before the
gate steps in the same host job ever run. That is the moment the product target
is enforced, and the message that test prints is therefore the message that has
to carry the doctrine (Component Design spells out what it must say, because the
current text offers two remediations this slice invalidates).

The runtime half still earns its place, but for two jobs neither of which is
"catch the drift":

- **Defense-in-depth.** The `budget_absolute_exceeded` branch is what still fails
  the build if the pin is deleted, weakened, or bypassed by editing budget
  literals without running the suite. Unreachable *given* the pin is not the same
  as redundant: it is the second of two independent checks on one invariant, and
  they fail under disjoint conditions.
- **Publication** — which belongs to the classification and the output layer, not
  to the reason. `BenchmarkSupport` reads `mode.absoluteCeiling.p99Nanoseconds` to
  put `budget_absolute_p99_ns` and `headroom_absolute_p99` on every gated line, so
  each hosted run records the product number and its live margin whether or not
  anything fires. Slice 43 built that; this slice makes it total, so the number
  appears on all 46 lines rather than 41 — and bulk's margin becomes visible for
  the first time instead of reading `exempt`.

Consequence for the falsifiability audit, stated so the post-slice review does not
have to re-derive it: the drills for both halves are synthetic — a unit test over a
constructed `BenchmarkSummary` for the runtime branch (Testing Strategy rows 1–2),
and a raised budget literal for the static pin (row 4). A guarantee whose red can
only be produced synthetically is still falsifiable; one whose red cannot be
produced at all is not, and row 4's red is the one that would fire in earnest.

Its position in `gateFailureReason` — after `budgetExceeded`, before
`budgetStale` — does not move. Under the pin the ordering is unobservable at
runtime, but it is the ordering that makes the branch *correct* if the pin is ever
gone, and inverting it would let a blown frame be reported as a stale budget.

### Decision 10 — If the re-derived bulk budget reaches the ceiling, diagnose first, then stop

If Phase 1 produces `bulk_structural_mutation|1m_lines_batch_4096` with
`budget_p99 >= 16_666_666`, the slice **halts and returns to the user** — but not
before naming *which of two causes* produced it, because they have opposite
correct answers and the diagnosis is one line of the derive output away.

The sweep prints `p95[med=… max=…] p99[med=… max=…]` beside every budget, so the
governing term is readable directly:

- **Cause (a) — genuine drift.** The **median** has moved, so the
  `8 × median` (and hence the `2 × budget_p95`) term governs. The engine really is
  slower; the doctrine applies verbatim — fix the code or the architecture, never
  the ceiling. That is a different slice with a different spec.
- **Cause (b) — one anomalous hosted sample.** The median sits where it always
  did and the `3 × max` term governs alone. Then the ceiling is being breached by
  a runner stall, not by the engine, and "fix the code" would be treating a
  measurement artifact. This is the case the windowing doctrine already has an
  answer for — the freak ages out of the N=20 window — but it cannot be shipped
  red in the meantime, so it is a user decision, not an author decision.

Decision 10 does not pre-authorize a response to (b); it requires that the halt
arrive with the diagnosis attached. Measured likelihood of either is low — the
governing term today is `16 × median(p95)` and the median would have to nearly
triple — but a response decided under pressure is exactly what naming both
branches in advance prevents.

### Decision 11 — D-9 is amended, not closed

D-9 has two halves and they end this slice in different states. The
shape-transition half is **discharged by fact**: after the harvest the window
holds no pre-slice-45 run, which is checkable and checked. The p95 thin-axis half
is structural — it is a property of the recipe, not a defect that can be fixed —
so it stays open, with its statement amended to record the re-observation.

**The amendment records a rule and a ratio, not a list of scenarios.** A named
list is the wrong durable form here: it runs to 45 of 46 entries (Source Context)
and the next harvest can move any of them, so a ledger row holding it is stale on
arrival — this repository's own lesson that a document restating a measured value
is falsified by the next re-derivation. What does not rot is the arithmetic: a
p95 budget rests on the median term exactly when `max / med <= 2.67`, and today
that is 45 of 46 with `line_query|uniform_1k` the only exception. The ledger
carries the rule and the ratio; the scenario-by-scenario snapshot lives in this
slice's verification record, and after Decision 13 it is re-derivable on demand
rather than transcribed.

This follows the D-15 precedent from slice 51: a ledger row whose statement is
corrected by evidence is amended in place, never silently re-scoped.

### Decision 12 — Nothing else moves, with one named exception

No engine source, no provider source, no workflow file, and **no script except
the one reporting token in Decision 13**. That exception is stated here rather
than left to be discovered in the diff: a decision quietly contradicted by a later
one is worse than either choice on its own. Everything else holds — AC9's
three-way checksum diff must come out empty and the three `pipeline` values must
match slice 51's; if either fails, something moved that this design did not
authorize.

### Decision 13 — `gov_p95` makes the thin-axis observation mechanical

`derive-gate-budgets.sh`'s per-scenario line gains one token,
`gov_p95=median|max`, naming which term produced `budget_p95`. Goal 3 then stops
being a one-off transcription and becomes a property of every future
re-derivation — the same move slice 44 made when it turned "derived, never
hand-typed" from a per-slice discipline into a standing test.

**Why it is worth breaking Decision 12 for.** D-9's surviving half is "when the
windowed `3 × max` term relaxes, a p95 budget rests on the `8 × median` backup
term alone — the thin axis to watch at every re-derivation." Watching it by hand
is precisely the kind of instruction that decays into silence; `gov_p95=median`
*is* the watch, printed beside the budget it describes.

**Scope, deliberately narrow:**

- **`gov_p95` only, no `gov_p99`.** p99 is not thin: it carries the
  `2 × budget_p95` floor as a structural backup, so a median-governed p99 is not
  the same warning. One qualification, because an earlier draft over-stated this
  as "a token nobody watches": Decision 10's halt **does** require reading the p99
  governing term, since bulk's `budget_p99` is governed by `2 × budget_p95` today
  and cause (a) vs cause (b) turns on which term moved. That read stays manual,
  off the `p99[med=… max=…]` columns the sweep already prints. The narrow scope is
  a judgement that one halt-time manual read is cheaper than a second column on
  every line of every sweep — not a claim that the p99 term is never wanted.
- **The tie rule is `median` when `8 × med >= 3 × max`.** The token answers "is
  this budget resting on the median term alone?", and on a tie it is.
- **The comparison operator differs from the one beside it, on purpose.** The
  value at `:143` is chosen with `8 * m95 > 3 * x95`, where a tie is harmless
  because both terms yield the same number. For the token a tie is meaningful, so
  it reads `>=`. That asymmetry is commented in the script, or the next reader
  harmonizes the operators and silently changes the rule.

**Expect a near-constant token, and say so before anyone reads it.** On today's
corpus `gov_p95=median` on **45 of 46** lines, with `line_query|uniform_1k` the
lone `max` (Source Context). A reader meeting a column that is one value 98% of
the time will suspect a broken field, so the expectation is stated here and
quoted in the verification record. Its value is in the **flip**, not the
distribution — and the two directions do not mean the same thing:

- **`median → max`** — a freak sample has taken over that scenario's floor, so
  `3 × max` now governs and the budget **loosened**. Noisier evidence, but the
  loose direction is the one the runtime gate already catches loudly, as
  `budget_stale`.
- **`max → median`** — the freak aged out of the N=20 window, `3 × max` released,
  and the budget dropped back to `8 × median`. **This is the signature of the one
  risk this design says nothing else catches before CI.** Risks And Gaps records
  that a *tightened* budget is the direction that reddens a clean tree, that every
  Phase 1 check is arithmetic and runs no benchmark, and that the only control is
  AC9's hosted PR-head run. A `max → median` flip is that mechanism, named, in the
  sweep output, before the hosted run.

The alternative — printing the `max / med` ratio — was rejected as a second number
to calibrate by eye when the question the thin axis asks is binary.

**A printed token is not yet a watch, and this design does not pretend otherwise.**
The argument against hand-transcription ("precisely the kind of instruction that
decays into silence") applies one level up to hand-*diffing*: the previous sweep
lives in a previous slice's verification record, and comparing them requires
someone to remember, across documents, at the next harvest. So the token is paired
with a control that runs at the moment it matters:

- **Required, zero code:** the verification block emits a **directional budget
  diff** — every scenario whose re-derived budget differs from the committed one,
  with the direction — and the *tightened* set is recorded as the explicit
  watch-list for AC9's PR-head run. This is what turns the risk entry's "the only
  control is a hosted run" into "a hosted run, with a list of what to look at".
- **Optional, stronger, deliberately not taken here:** pin the max-governed set
  the way this repository pins every other set (`testFrameHotPathExclusionsAreExactlyDocumented`,
  `pinnedGateSteps`, `SELF_TEST_COVERED`/`SELF_TEST_EXEMPT`).
  `GateFloorTests` already shells out to `derive-gate-budgets.sh` and parses its
  output in `derivedBudgets(fromScriptOutput:)`, so extending that parse to
  `gov_p95` and asserting the set equals a committed literal (today
  `["line_query|uniform_1k"]`) is ~20 lines and no new machinery. It is left out
  of this slice because the set changes at every harvest that flips a scenario,
  which is a standing cost this slice has no evidence to size yet; the first
  post-52 harvest is exactly the evidence. It becomes a ledger row at the
  post-slice review, alongside the harvester's shape-2 retirement candidate.

**Compatibility, verified rather than assumed.** `GateFloorTests`'
`derivedBudgets(fromScriptOutput:)` splits each line on whitespace and scans for
the `budget_p95=` / `budget_p99=` prefixes; its own comment records that a
*missing* token becomes a loud missing-key failure. An *additional* token passes
through untouched, and `testEveryCommittedBudgetReproducesFromCorpus` compares
parsed budgets rather than raw lines.

**The surface it lands on is emptier than it looks.** `run_self_test` in that
script contains exactly two assertions, both on `window_run_ids` fixtures — the
budget arithmetic has **no** self-test coverage at all today. So this token's
drill is also the first standing check on that arithmetic. The cost stays small
because the fixture machinery already exists: `run_self_test` writes a corpus TSV
to a `mktemp` file under a cleanup trap, and the addition is a second scenario
whose rows carry an outlier (so `3 × max` beats `8 × median`) plus two
assertions, one per branch. Since slice 51 put all four script self-tests under
`swift test`, the guarantee is build-failing from its first day at no extra
wiring cost.

**But it needs a form this script has never used.** Both existing assertions call
a *function* (`window_run_ids`); the derivation lives in the `awk` program
**below** the `--self-test` dispatch and is not reachable that way. Asserting on
derived output therefore means re-invoking the script itself,
`"$0" "$fixture"` — and under this script's `set -euo pipefail` a non-zero child
aborts the shell before `assert_equal` can print its label, turning a real
failure into a bare exit. The capture must be written so the status is caught
rather than fatal:

```bash
out="$("$0" "$fixture")" || { echo "self_test=fail label=gov_p95_derivation_exited $?"; exit 1; }
```

This is a new pattern for the file and it sits next to D-15's dispatcher-shape
nit, so the plan states it rather than leaving it to be improvised at the
keyboard.

**Interaction with D-14, recorded rather than hidden.** This adds arithmetic to a
script whose coverage/exemption classification is *not* pinned — D-14 exactly.
This slice exercises what it adds, so nothing is silent today, but the next
addition to that script still would be. That is an argument for D-14, and it
should be visible when D-14 is next weighed rather than rediscovered then.

## Component Design

**`Sources/ViewportBenchmarks/BenchmarkModels.swift`**

- `GateLimits.frameNanoseconds` unchanged.
- `GateLimits.absoluteP99Nanoseconds` removed (Decision 5).
- New `enum AbsoluteCeiling` with `scrollFrame` / `discreteAction` and a
  `p99Nanoseconds` computed from `frameNanoseconds`.
- `BenchmarkSummary.headroomAbsoluteP99` reads `mode.absoluteCeiling.p99Nanoseconds`
  instead of the single constant. The zero-observed `.infinity` guard is untouched.
- The gate check becomes `if p99Nanoseconds > mode.absoluteCeiling.p99Nanoseconds`.
  Its position in `gateFailureReason` — after `budgetExceeded`, before
  `budgetStale` — does not move; Decision 9 explains why that ordering still holds.
- **Two** comment blocks are rewritten, not one. The block above `GateLimits`
  carries the exemption language; the block *inside* `gateFailureReason` (the
  paragraph opening "The absolute PRODUCT ceiling, checked for frame-hot-path
  modes only") states the ordering argument in terms of a single "1.67ms
  ceiling" and of bulk being exempt. Both are false under the new model, and the
  second is the one that explains why the check sits between `budgetExceeded` and
  `budgetStale` — it must now make Decision 9's argument for both classes.
  Decision 9's argument changed in the fourth review round, so this comment does
  too: it explains that under the floor pin this branch is **unreachable by
  construction** (any p99 above the ceiling is also above the budget, and
  `budgetExceeded` is checked first), that it is therefore defense-in-depth plus
  the publisher of the two output tokens, and that the enforcement point for the
  product target is `testEveryGatedBudgetIsUnderItsClassCeiling`. A comment
  claiming this branch is what catches slow drift would send the next reader
  looking for a hosted red that cannot occur.

**`Sources/ViewportBenchmarks/BenchmarkOptions.swift`**

- `isFrameHotPath: Bool` → `absoluteCeiling: AbsoluteCeiling`, same exhaustive
  switch shape, `bulkStructuralMutation` alone returning `.discreteAction`.
- The four **non-gateable** modes (`rangeOnly`, `memoryShape`, `memoryObservation`,
  `wrapCompute`) sit in the `return true` arm today and must classify under a total
  function. They take `.scrollFrame` and never reach the gate, so the value is
  inert. It is worth stating because the membership pin filters on `isGateable`
  and therefore does **not** cover them: their class is a compile-time obligation,
  not a pinned one, and the plan should not expect a test to catch a wrong choice
  there.
- The comment at `:91` naming `GateLimits.absoluteP99Nanoseconds` goes with the
  symbol.

**`Sources/ViewportBenchmarks/BenchmarkSupport.swift`**

- The `if summary.mode.isFrameHotPath { … } else { … "exempt" }` branch collapses:
  every gated summary prints `budget_absolute_p99_ns=<n>` and
  `headroom_absolute_p99=<h>`. The `exempt` marker is deleted.

**`Sources/ViewportBenchmarks/*Benchmark.swift`**

- Budget literals updated wherever the sweep re-derivation differs. No structural
  change; scenario names, counts, and workloads are untouched.

**`Tests/ViewportBenchmarksTests/GateLogicTests.swift`**

- Exclusion pin → class-membership pin: the set of gateable modes classified
  `.discreteAction` equals `["bulk_structural_mutation"]`.
- Frame-math pin extended: `.scrollFrame == frameNanoseconds / 10` and
  `.discreteAction == frameNanoseconds`, plus both literals.
- `testAbsoluteCeilingDoesNotFireForBulkMode` re-commented (Decision 8).
- New `testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling`.
- `testGateOutputMarksBulkExempt` inverts on **both** of its assertions and is
  renamed: the line must now carry `budget_absolute_p99_ns=16666666`, and the
  `XCTAssertFalse(line.contains("headroom_absolute_p99"))` becomes an
  `XCTAssertTrue` with the computed headroom, since a classified mode emits both
  tokens.
- `testGateOutputCarriesAbsoluteCeilingForFrameHotPath` keeps its assertions —
  `1666666` and `8.3x` stay correct for a `.scrollFrame` mode — but its name
  refers to a classification that no longer exists and is renamed with it.
- `testNonGateOutputHasNoAbsoluteToken` is unaffected: non-gate output is a
  separate contract and still carries neither token.

References here are by test name on purpose. The first draft mixed a `func` line
with an assertion line, which reads as one convention and is two.

**`Tests/ViewportBenchmarksTests/GateFloorTests.swift`**

- `testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling` →
  `testEveryGatedBudgetIsUnderItsClassCeiling`, filter removed, message naming the
  class it compared against.
- **Its failure message is rewritten, not just re-labelled — this is the load-bearing
  half.** Decision 9 establishes that this test's red *is* the product ceiling firing,
  so the text it prints is the only place the doctrine reaches the person who broke it.
  The current message offers three remediations and **two of them stop existing in this
  slice**:

  > "Reclassify the mode as not frame-hot-path, raise the ceiling fraction (a
  > conscious product decision), or accept the op is too slow for a frame."

  `not frame-hot-path` is a state Decision 4 deletes along with the boolean, and
  `raise the ceiling fraction` is exactly what `AGENTS.md` forbids — "on breach the
  response is to **fix the code/architecture — never loosen the ceiling**". The new
  message must carry that instruction, name the class it compared against and that
  class's ceiling, and leave exactly one legitimate alternative: reclassifying the
  mode into the other ceiling class, which is a product decision with its own
  argument, not a knob. A rename that keeps this body would ship a test whose red
  tells the reader to do the one thing the doctrine prohibits.
- The comment block above it also states the filter and the exemption ("Bulk is
  filtered out here exactly as `isFrameHotPath` filters it at runtime, so the two
  agree"). It must instead state Decision 9's relationship: the runtime check and
  this pin do not merely "agree" — this pin is what makes the runtime branch
  unreachable, which is why the pin, not the branch, is the enforcement point.

**`.github/scripts/derive-gate-budgets.sh`** (Decision 13, the one script change)

- One `gov95 = (8 * m95 >= 3 * x95) ? "median" : "max"` assignment beside the
  `b95` computation, and one `gov_p95=%s` field in the `printf` format.
- `run_self_test` gains a second fixture scenario carrying an outlier — so
  `3 × max` beats `8 × median` there — and two assertions, one per branch. It
  reaches the derivation by re-invoking `"$0" "$fixture"`, captured in the
  status-catching form Decision 13 spells out: under `set -euo pipefail` a bare
  `$(…)` would abort the shell before the assertion could name what failed.
- Nothing else in the script moves: no change to the recipe, the window, the
  `--window-run-ids` seam, or the existing fixtures.

**`docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`**

- Appended only. Existing rows are never edited, reordered, or de-duplicated.

## Testing Strategy

Seven drills, one per guarantee this slice adds or changes. Each is executed, its
red output recorded verbatim in the verification document, and then reverted.

| Guarantee | Mutation | Test that must redden |
|---|---|---|
| Bulk has an absolute ceiling at all — D-8's substance | Skip the absolute check for `.discreteAction` (or give it an unbounded value) | **New** paired test: expected `.budgetAbsoluteExceeded`, actual `nil` |
| The bulk ceiling is one frame, not a tenth of one | Classify `.bulkStructuralMutation` as `.scrollFrame` | **Old** re-commented test: expected `nil`, actual `.budgetAbsoluteExceeded` |
| Class membership is pinned | Classify a second mode as `.discreteAction` | Membership pin fails, naming the extra mode |
| Every budget is under its class ceiling | Raise `1m_lines_batch_4096`'s p99 budget above `16_666_666` | `testEveryGatedBudgetIsUnderItsClassCeiling`, recorded under `--filter`; `testEveryCommittedBudgetReproducesFromCorpus` reddens too and is recorded as expected collateral |
| Ceiling values are pinned to the frame math | Replace a derived value with a differing bare literal | Frame-math pin |
| `exempt` is gone from the output | Restore the `else` branch in `BenchmarkSupport` | Output-line test |
| `gov_p95` names the right term | Flip the token's `>=` to `<` | `derive-gate-budgets.sh --self-test` reports `self_test=fail` on the median-governed fixture, and `ScriptSelfTestTests` carries it into a red `swift test` |

Rows 1 and 2 are the bracket from Decision 8, and they are deliberately *not*
interchangeable: each mutation reddens exactly one of the two tests, and the
mutation that looks like it should redden the new test (reclassifying bulk
downward) reddens the old one instead. A drill recorded against the wrong test
would look like evidence and be none.

Row 4 is the one drill with **collateral**: raising a committed budget literal
also stops it reproducing from the corpus, so
`testEveryCommittedBudgetReproducesFromCorpus` goes red alongside the target. The
target's red is recorded under `--filter` so the evidence names one test, and the
collateral red is recorded as such — an unexplained second failure in a drill log
is indistinguishable from a drill that hit the wrong thing.

Phase 1 needs no new test: `testEveryCommittedBudgetReproducesFromCorpus` is a
standing guarantee whose red was drilled in slice 44, and it is the arbiter of
whether the re-derivation was transcribed correctly. Re-drilling it is not
required by the falsifiability rule, which asks for evidence per **added or
changed** guarantee.

TDD order inside Phase 2: the paired bulk test is written first and must fail with
the old model before the classification lands.

## Documentation Updates

**`AGENTS.md` carries the old model in four places, not one.** The first draft
named only the third of them, and AC5's source scan cannot see any of them:

- **`:413`** — names the removed symbol: "`GateLimits.absoluteP99Nanoseconds =
  1_000_000_000 / 60 / 10`". Becomes the two-class derivation.
- **`:417`** — "checked against **p99 only** (a passing p99 implies a passing p95
  under a uniform ceiling)". The parenthetical is true *within* one mode and false
  across modes once two ceilings exist; tightened to say so.
- **`:420-431`** — the "applies to **frame-hot-path** modes only … is **exempt** …
  prints `budget_absolute_p99_ns=exempt`" paragraph, including the
  `BenchmarkMode.isFrameHotPath` reference and the `GateFloorTests` sentence that
  describes the now-removed filter. The paragraph runs to `:431` ("So the runtime
  absolute gate can never redden a clean tree."), not to `:427` as an earlier
  draft had it — the four lines that draft cut off are exactly the sentence about
  the filter, which is the part the new model changes most.

  Its closing sentence needs more than generalizing. "So the runtime absolute gate
  can never redden a clean tree" is true but reads as a reassurance about a gate
  that otherwise works; Decision 9 establishes that it is the *whole* story — the
  runtime branch is unreachable while the pin holds. The rewritten paragraph must
  therefore say which check enforces the product target (`GateFloorTests`, at
  `swift test` time), and what the runtime reason is for (defense-in-depth if the
  pin goes, plus publishing the ceiling and headroom on every gate line). A reader
  who takes the current sentence at face value will go looking for a hosted
  `budget_absolute_exceeded` that cannot occur.
- **`:548`** — the three-failure-reasons paragraph: "`budget_absolute_exceeded`
  means a frame-hot-path op blew the fixed 60 FPS ceiling". Generalized to both
  classes. The three reasons themselves do not change.

The rewrite must describe the **current** state without naming the removed
identifiers, since AC5 scans `AGENTS.md` for them. Describing the history belongs
in this spec and in the verification record, both of which live under `docs/` and
are outside the scan.

- **`AGENTS.md`, `## Gate budgets`** also documents the `gov_p95` token where it
  already explains that p95 "carries only the median term as backup, so it is the
  thin axis to watch": the sentence now says what to read rather than only what to
  watch for, and records the rule behind it — median-governed exactly when
  `max / med <= 2.67`, which is why nearly every budget is. Stating the rule
  rather than the current count keeps the paragraph true across re-derivations.
  It also records what the two flip directions mean (Decision 13), since
  `max → median` is the tightening signature and that is the token's real use.
- **`AGENTS.md`, `## Gate budgets`** gains one sentence on the **pre-harvest budget
  baseline**: a re-derivation is compared against the budgets it replaces, and the
  tightened set is the watch-list for the hosted run. Today the harvest recipe
  documents how to produce new budgets and says nothing about comparing them with
  the old ones, which is why the tightening direction has been uncontrolled since
  slice 41 introduced the window that causes it.
- **Arc decision log** (`docs/superpowers/arcs/wrap.md`): the 2026-08-08 user call
  — Option C over the node-3 lean, plus the D-8 target — with the map pass noting
  that slice 52 consumes no node, like slices 48 and 51. It also records *why now*
  beyond debt age: the wrap brief's fourth criterion binds future wrap gates to
  this recipe and to the absolute ceiling, so a ten-slice-stale calibration base
  and a pre-wrap boolean are both de-risking work for a named criterion, even
  though the scoreboard moves by zero (Source Context).
- **Debt ledger:** D-8 → `scheduled(slice-52)` then `discharged(...)`; D-9
  statement amended per Decision 11.

## Verification

Written under the plan-assertion conventions in `AGENTS.md`: every command below
either fails non-zero on its own fault, or is followed by an explicit test whose
exit status is sensitive to the invariant.

```bash
# `set -e` is NOT enough on its own here and `set -e` alone is not what this block
# wants: it would abort before the `echo` that says which invariant broke. So:
# -u and pipefail globally, and an explicit `|| exit 1` on every bare command whose
# only failure signal is its exit status. Rule: a command with no `||` and no
# following test is a bug in this block, not a command that cannot fail.
set -uo pipefail

CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
WORK="$(mktemp -d)"
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo 'temp root unavailable'; exit 1; }

# Provenance, by hand, because D-7 is deferred. A run is admissible when its HOST
# job passed: a host job that failed ON ITS BUDGET carries exactly the slow samples
# that would loosen the budget they broke. A red WASM job says nothing about them.
for run in 29701333581 29701547123; do
  host="$(gh run view "$run" --json jobs \
          --jq '.jobs[] | select(.name == "Host tests and benchmark gate") | .conclusion')"
  [ "$host" = "success" ] || { echo "run $run host job = ${host:-missing}"; exit 1; }
done

# Harvest plan first. The decisions go to STDERR (`echo "$decision" >&2` in the
# script), so `> file` alone would record an empty file and look like a clean plan.
# No pipe: rule 1's strongest form is not to pipe at all, which also keeps the
# block free of ${PIPESTATUS} and portable to whatever shell runs it.
./.github/scripts/harvest-gate-corpus.sh --limit 100 --corpus "$CORPUS" --dry-run \
  > "$WORK/harvest-plan.txt" 2>&1 \
  || { echo 'harvest --dry-run failed'; cat "$WORK/harvest-plan.txt"; exit 1; }

# PRE-harvest baseline for the directional diff below. It must be taken HERE: after
# the append the old budgets are unrecoverable from the corpus, and the comparison
# would be against themselves. `key p95 p99` per line, sorted, ready for `join`.
budget_columns() {
  awk '{ p95 = ""; p99 = ""
         for (i = 1; i <= NF; i++) {
           if ($i ~ /^budget_p95=/) { split($i, a, "="); p95 = a[2] }
           if ($i ~ /^budget_p99=/) { split($i, a, "="); p99 = a[2] } }
         if (p95 != "" && p99 != "") print $1, p95, p99 }' "$1" | sort
}
./.github/scripts/derive-gate-budgets.sh "$CORPUS" > "$WORK/sweep-old.txt" \
  || { echo 'pre-harvest sweep failed'; exit 1; }
budget_columns "$WORK/sweep-old.txt" > "$WORK/old-budgets.txt"
old_n="$(wc -l < "$WORK/old-budgets.txt")"
[ "$old_n" -eq 46 ] || { echo "pre-harvest baseline holds $old_n budgets, want 46"; exit 1; }

# Append. The redirect is the point, so the script's own exit status is the check --
# but a status nobody tests is not a check: a mid-sweep abort would leave partial
# rows appended and the block would carry on to derive budgets from them.
./.github/scripts/harvest-gate-corpus.sh --limit 100 --corpus "$CORPUS" >> "$CORPUS" \
  || { echo 'harvest failed; corpus may hold a partial append -- inspect before committing'; exit 1; }

# Window run ids to a FILE first. Reading them through a pipe into awk would put
# the check on the left of the pipe: a failing derive would still yield an empty
# result and the assertion would pass (AGENTS.md plan-assertion rule 1).
#
# The redirect needs BOTH guards below. Moving the command out of a pipe fixed the
# pipeline-status half and left the redirect's own status untested -- and an empty
# window.txt makes the two AC2 checks below pass vacuously, which is the same
# cannot-fail shape wearing different clothes. The line count is the stronger of
# the two: it fails on a truncated file, which a zero exit status does not see.
./.github/scripts/derive-gate-budgets.sh --window-run-ids 20 < "$CORPUS" > "$WORK/window.txt" \
  || { echo 'derive --window-run-ids failed'; exit 1; }
ids="$(wc -l < "$WORK/window.txt")"
[ "$ids" -eq 20 ] || { echo "window holds $ids run ids, want 20"; exit 1; }

# PRIMARY -- the invariant itself: no run in the window may contribute more than one
# realistic_provider row, because a post-slice-45 run prints exactly one summary line
# for it. Discriminating today: 16 of the 20 window runs contribute 8 rows each.
offenders="$(awk -F'\t' 'NR==FNR {win[$1]; next}
                         $2 == "realistic_provider" && ($1 in win) {n[$1]++}
                         END {for (r in n) if (n[r] > 1) print r, n[r]}' \
             "$WORK/window.txt" "$CORPUS")"
[ -z "$offenders" ] || { printf 'shape-2 rows still in window:\n%s\n' "$offenders"; exit 1; }

# CORROBORATION -- a proxy, kept as a second signal only. 29692848870 is slice 45's
# PR-head run, the first whose workflow prints the shape-1 summary (a pull_request
# run executes the merge ref). Run ids order runs, NOT workflow versions, so this
# cannot stand alone: a branch cut before the merge could carry the old shape.
old="$(awk '$1 < 29692848870' "$WORK/window.txt")"
[ -z "$old" ] || { printf 'window carries pre-slice-45 runs:\n%s\n' "$old"; exit 1; }

# Sweep every mode; a mode with no corpus rows is an error, not an empty success.
# To a file, again without a pipe: this output is AC3's evidence (the gov_p95
# column) and AC4's, and it is recorded verbatim in the verification document.
./.github/scripts/derive-gate-budgets.sh "$CORPUS" > "$WORK/sweep.txt" \
  || { echo 'sweep failed'; exit 1; }

# AC3, read off the sweep rather than recomputed. Expect ~45 of 46 on `median`
# (Decision 13). `grep` exits 1 on NO match, so the desired outcome would read as a
# failure -- rule 2. Hence: assert the count, and mark the may-be-empty grep `|| true`.
med="$(grep -c 'gov_p95=median' "$WORK/sweep.txt")"
[ "$med" -ge 1 ] || { echo 'no gov_p95=median lines -- token missing from the sweep?'; exit 1; }
echo "median-governed: $med of 46"
grep 'gov_p95=max' "$WORK/sweep.txt" || true   # an empty max set is a legitimate outcome

# DIRECTIONAL DIFF (Decision 13) -- the control for the TIGHTENING risk.
#
# Every other Phase 1 check is arithmetic and none of them runs the benchmark, so
# without this the first sign of a budget that landed too close to observed latency
# is a red hosted run with no prior. A `max -> median` flip in the token above is the
# mechanism; this is the same fact read off the numbers, per scenario.
#
# NOT an assertion. A tightening is legitimate -- it is exactly what slice 41's window
# was built to allow -- so failing here would redden the block for correct behaviour.
# This is EVIDENCE: the tightened set is the watch-list for AC9's PR-head run and is
# recorded in the verification document.
budget_columns "$WORK/sweep.txt" > "$WORK/new-budgets.txt"
new_n="$(wc -l < "$WORK/new-budgets.txt")"
[ "$new_n" -eq 46 ] || { echo "post-harvest sweep holds $new_n budgets, want 46"; exit 1; }

# `join` drops keys present in only one side, which would silently hide a scenario
# that appeared or vanished. Both sides are pinned at 46 above and this slice changes
# no scenario (Non-Goals), so assert the join is total rather than trusting it.
join "$WORK/old-budgets.txt" "$WORK/new-budgets.txt" > "$WORK/budget-diff.txt"
joined_n="$(wc -l < "$WORK/budget-diff.txt")"
[ "$joined_n" -eq 46 ] || { echo "join matched $joined_n of 46 keys -- scenario set moved"; exit 1; }

# To files, then count them -- the same shape as every other check here, and for the
# same reason: `awk … | wc -l` would report 0 if awk failed, and "0 tightened" is the
# outcome a reader most wants to see. Evidence that reads as good news when its own
# producer broke is the rule-2 trap wearing an evidence label.
awk '$2 != $4 || $3 != $5 {
       dir = ($2 > $4 || $3 > $5) ? "TIGHTENED" : "loosened"
       printf "%-10s %-46s p95 %s->%s  p99 %s->%s\n", dir, $1, $2, $4, $3, $5 }' \
    "$WORK/budget-diff.txt" > "$WORK/moved.txt" || { echo 'movement scan failed'; exit 1; }
awk '$2 > $4 || $3 > $5 { print $1 }' "$WORK/budget-diff.txt" > "$WORK/tightened.txt" \
  || { echo 'tightening scan failed'; exit 1; }
echo "--- budget movement (old -> new): $(wc -l < "$WORK/moved.txt") of 46 moved, \
$(wc -l < "$WORK/tightened.txt") tightened ---"
cat "$WORK/moved.txt"

# The arbiter of Phase 1: budgets must reproduce from the committed corpus.
swift test --filter GateFloorTests || exit 1

# Full suite and release build.
swift test || exit 1
swift build -c release || exit 1

# Every gated mode locally, captured to a file rather than piped: `… | tee` would
# put the loop on the left of a pipe and its exit inside a subshell -- rule 1 again.
for mode in "" --realistic-provider --variable-height --variable-height-mutation \
            --structural-mutation --bulk-structural-mutation --line-query \
            --line-geometry-query --column-query --column-geometry-query \
            --point-query --point-geometry-query; do
  # Without the explicit exit the loop swallows a failing gate and the whole
  # block becomes a check that cannot fail (rule 2).
  #
  # $mode is UNQUOTED on purpose and must stay that way: the first element is the
  # empty string (the default pipeline mode takes no flag), and `"$mode"` would pass
  # a literal empty argument instead of passing none. Under `set -u` the variable is
  # always assigned, so the usual unquoted-expansion hazard does not apply here --
  # every element is a single fixed token with no whitespace or globs. Commented for
  # the same reason Decision 13 comments its `>=`: the next reader's instinct is to
  # "fix" the quoting, and the fix is a silent behaviour change.
  swift run -c release ViewportBenchmarks -- $mode --gate >> "$WORK/local-gate.txt" || exit 1
done

# AC5's second half, which had no mechanical check until the fourth review round: every
# gated summary must print a NUMERIC ceiling and a headroom beside it. The scans in AC5
# prove the old tokens are gone; these prove the new ones are present on all 46 lines.
# Counts, not bare greps -- `grep` exits 1 on no match, so the failing case would read
# as the desired one (rule 2).
n="$(grep -c 'budget_absolute_p99_ns=[0-9]' "$WORK/local-gate.txt")"
[ "$n" -eq 46 ] || { echo "numeric budget_absolute_p99_ns on $n lines, want 46"; exit 1; }
n="$(grep -c 'headroom_absolute_p99=' "$WORK/local-gate.txt")"
[ "$n" -eq 46 ] || { echo "headroom_absolute_p99 on $n lines, want 46"; exit 1; }

# The local half of AC9's three-way comparison. Assert the COUNT before comparing:
# an empty checksum set would diff clean against anything.
n="$(grep -c 'checksum=' "$WORK/local-gate.txt")"
[ "$n" -eq 46 ] || { echo "expected 46 checksum lines, got $n"; exit 1; }

# Extract (mode|scenario, checksum) and NOTHING else. Two traps, both of which an
# earlier draft fell into:
#   * a greedy `.*checksum=` between two anchors drags p95_ns/p99_ns/headroom_* along,
#     and those MUST differ local vs hosted (hosted runs 2-3x slower -- that is the
#     calibration-authority rule). A tuple carrying them can never diff empty.
#   * scenario alone is not a key: `uniform_1m`, `uniform_100k`,
#     `1k_lines_20_visible_overscan_0`, `100k_lines_80_visible_overscan_5` and
#     `1m_lines_200_visible_overscan_50` each appear in SIX modes.
extract_checksums() {
  sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9]+).*/\1|\2\t\3/p' "$1" | sort -u
}

extract_checksums "$WORK/local-gate.txt" > "$WORK/local.txt"
keys="$(cut -f1 "$WORK/local.txt" | sort -u | wc -l)"
[ "$keys" -eq 46 ] || { echo "expected 46 distinct mode|scenario keys, got $keys"; exit 1; }

# The 46-value CROSS-SLICE anchor. Slice 43's verification document carries all 46
# tuples across all twelve gated modes (realistic_provider included) -- its Section 8
# *table* holds 45, the document does not. Extracted with the same function, so a
# difference is a real difference and not a parsing artefact.
#
# Why 46 and not the document's raw line count: it holds 54 `checksum=` lines, and
# `sort -u` inside extract_checksums collapses them to 46 because every repetition
# AGREES. That collapse is not a weakening -- it is what makes the count assertion
# meaningful. A document that recorded two DIFFERENT checksums for one (mode,scenario)
# -- which any drill log legitimately would, since a drill records mutated output
# verbatim -- would yield 47+ tuples and fail the line below. So the count is asserted
# BEFORE the diff, and it is what qualifies a document to serve as an anchor at all.
# Anyone reusing this pattern against a different verification record must re-check it
# there rather than assume; this slice's own record will carry seven drill reds.
extract_checksums docs/superpowers/verification/2026-07-18-absolute-product-budget.md \
  > "$WORK/anchor.txt"
[ "$(wc -l < "$WORK/anchor.txt")" -eq 46 ] || { echo 'anchor is not 46 tuples'; exit 1; }
diff "$WORK/anchor.txt" "$WORK/local.txt" \
  || { echo 'checksums drifted since slice 43 -- a workload moved'; exit 1; }

# The core is untouched: the Foundation-free scan must find nothing.
[ -z "$(rg -n 'Foundation' Sources/TextEngineCore)" ] || { echo 'Foundation leaked'; exit 1; }
```

Hosted evidence is read at **step level**, not job conclusion: a green job can
hide a dead step. Both the PR-head run and the post-merge push run are recorded,
each showing all twelve blocking gate steps green — **46** scenario lines
reporting `gate=pass`, one per gated scenario — with the five bulk lines now
carrying `budget_absolute_p99_ns=16666666` where they previously read `exempt`.

**The checksum comparison has two independent halves, and they prove different
things.** The same `extract_checksums` function is run over the local sweep, the
PR-head log, and the post-merge log, giving 46 `(mode|scenario, checksum)` tuples
each; the three sets must diff empty pairwise, and all three are recorded in this
slice's verification document. That is the **internal** half, and on its own it
proves only that three environments agree with each other — three identically
wrong sets would pass it.

The **cross-slice** half is what proves the workload did not drift, and it is a
full 46-value anchor rather than a token sample:
[`2026-07-18-absolute-product-budget.md`](../verification/2026-07-18-absolute-product-budget.md)
carries all 46 tuples across all twelve gated modes, `realistic_provider`
included. An earlier draft weakened this to slice 51's three `pipeline` values on
the belief that no committed document held the full set; that belief confused
slice 43's **Section 8 table** (45 rows, `realistic_provider` written up
separately) with the **document** (46 tuples). Slice 51's three values are present
in that document unchanged, which is the evidence the anchor is still current, and
they remain quoted as a spot check across 51 → 52.

Extracting the anchor with the same function as the fresh sets is deliberate: a
tuple parsed two ways can differ for reasons that have nothing to do with the
engine. This is the pattern slice 44's verification document used in its
Section 5, with the anchor widened from a table lookup to a mechanical read.

## Acceptance Criteria

1. **AC1 — Idempotent, provenance-checked append.** The corpus is appended via
   `--corpus`; the `--dry-run` decision plan is recorded (captured from **stderr**,
   where the script writes it — a stdout capture records an empty plan and reads
   as a clean one); no pre-existing row is
   edited, reordered, or removed (`git diff` over the corpus shows additions
   only). **And** the two run-level failures (`29701333581`, `29701547123`) are
   shown to have a `success` **host** job, with the `gh` output recorded. That
   hand check is the only provenance control in the chain while D-7 stays
   deferred, so it belongs in an acceptance criterion rather than in prose.
2. **AC2 — Window flushed, checked directly.** No run in the N=20 window
   contributes more than one `realistic_provider` row. This is the invariant
   itself, and it is discriminating today: 16 of the 20 window runs contribute 8
   rows each. Corroborated — not replaced — by two weaker signals: no window run
   id below `29692848870`, and `realistic_provider`'s `n=` falling from 128 toward
   ~20. The run-id threshold is a proxy because run ids order *runs*, not
   *workflow versions*.

   This check has its falsifiability evidence **already, from before the work**:
   run against the committed corpus it reports 16 offenders (`29280327104 8`,
   `29205750443 8`, `29206089605 8`, `29195160122 8`, … ). It is red today and the
   slice's job is to make it green — the one guarantee here whose red needs no
   mutation drill, because the pre-work state is the red.
3. **AC3 — Thin axis observed mechanically.** `derive-gate-budgets.sh` emits
   `gov_p95=median|max` on every scenario line, its tie rule (`median` at
   `8 × med == 3 × max`) is asserted by the script's own `--self-test`, and that
   self-test fails `swift test` when broken. The verification record quotes the
   swept output with the counts on both sides of the token.

   What goes into the **ledger** is the rule and the ratio — a p95 budget is
   median-governed exactly when `max / med <= 2.67`, and after the harvest it is
   *n* of 46 — not the enumeration, which runs to nearly every scenario and rots
   at the next re-derivation (Decision 11). The pre-harvest measurement is 45 of
   46, so a post-harvest result anywhere near that is the expected outcome and not
   a finding; a sharp move in either direction is.
4. **AC4 — Budgets reproduce, and their movement is recorded with its direction.**
   All 46 gated scenarios reproduce from the appended corpus; `swift test` green.

   **And** the verification record carries the directional budget diff against the
   **pre-harvest** baseline — every scenario whose budget moved, labelled tightened
   or loosened, with the tightened set called out as the watch-list for AC9's
   PR-head run. The baseline must be captured before the append (afterwards the old
   budgets are unrecoverable from the corpus). This is evidence, never an
   assertion: a tightening is legitimate behaviour, and the criterion is that the
   diff was taken and recorded, not that it came out empty. It is the only
   pre-hosted control on the tightening risk.
5. **AC5 — Total classification.** Two precise scans over
   `Sources Tests AGENTS.md` find nothing:
   `rg -n 'isFrameHotPath|absoluteP99Nanoseconds'` and
   `rg -n 'budget_absolute_p99_ns=exempt'`. (`.github/**` was checked and carries
   neither identifier nor the token, so the three-path scope is complete.)

   Every gated summary prints a numeric `budget_absolute_p99_ns` alongside a
   `headroom_absolute_p99` — asserted, not asserted-by-eye: two count checks over
   the 46 local gate lines, since the scans above can only prove the *old* tokens
   are gone and nothing else proved the new ones arrived.

   Two scoping decisions, both load-bearing:

   - **`AGENTS.md` is in scope.** It carries the removed symbol and the exemption
     model in four paragraphs, and a scan limited to `Sources Tests` — the first
     draft's — could not see any of them.
   - **`docs/superpowers/**` is out of scope.** Verification records are
     append-only history and must keep the `exempt` lines they recorded when they
     were true; this spec and the review both discuss the removed identifiers by
     name. Scanning them would make the criterion unmeetable, and would collide
     with the plan-assertion rule against mandating a string and asserting zero
     occurrences of it.

   The scans match identifiers and the emitted **token**, never the English word
   "exempt", which legitimately survives in `GateLogicTests`'s registry-invariant
   comment and `WorkflowShapeTests`'s exemption-set comment. A bare `rg exempt`
   would match both — the repository's own token-not-substring lesson, applied to
   its own acceptance criteria.
6. **AC6 — Bulk ceiling pinned.** `.discreteAction` equals `frameNanoseconds`
   (16_666_666) and the set of gateable modes in that class is exactly
   `{bulk_structural_mutation}`, both asserted.
7. **AC7 — Full-coverage floor pin, carrying the doctrine.**
   `testEveryGatedBudgetIsUnderItsClassCeiling` iterates all 46 budgets with no
   filter, and each is under its class ceiling.

   **And** its failure message is rewritten, not merely re-labelled. Decision 9
   makes this test the enforcement point for the product target, so its text is
   where the doctrine reaches whoever tripped it. The message must name the class
   and its ceiling and instruct **fix the code/architecture — never loosen the
   ceiling**. Neither remediation the current message offers may survive:
   "reclassify the mode as not frame-hot-path" names a state Decision 4 deletes,
   and "raise the ceiling fraction" is the one response `AGENTS.md` forbids. A pass
   here with the old body would ship a product gate whose red advises the
   prohibited fix.
8. **AC8 — Seven recorded reds.** Each drill in Testing Strategy is executed and
   its failure output recorded verbatim, then reverted. The eighth guarantee —
   AC2's window check — needs no drill: its red is the pre-work state, recorded
   before the harvest rather than manufactured after it.
9. **AC9 — Hosted proof, step level, self-contained checksums.** PR-head run and
   post-merge push run both green at step level: twelve blocking gate steps, 46
   scenario lines reporting `gate=pass`, `swift test` green, and the five bulk
   gate lines showing `budget_absolute_p99_ns=16666666`.

   The checksum criterion has two halves, both required:

   - **Internal** — a three-way tuple diff. The 46 `(mode|scenario, checksum)`
     tuples from the local sweep, the PR-head log, and the post-merge log diff
     empty pairwise, all three sets recorded here. The key is `(mode, scenario)`,
     never scenario alone: five scenario names are shared by six modes each. The
     tuple carries the checksum and nothing else — no `p95_ns`, no `headroom_*`,
     which differ between local and hosted by construction.
   - **Cross-slice** — a 46-value anchor. Every tuple must equal the one extracted
     by the same function from
     [`2026-07-18-absolute-product-budget.md`](../verification/2026-07-18-absolute-product-budget.md),
     which carries all 46 across all twelve gated modes. Slice 51's three
     `pipeline` values are quoted alongside as a spot check.

   The internal diff proves three environments agree; only the anchor proves the
   workload did not drift. An earlier draft cut the anchor to three values on the
   false premise that 46 exist in no committed document — a *table* holds 45, the
   document holds 46.
10. **AC10 — Paper trail.** Spec, plan, verification record, arc decision-log
    entry, and ledger status changes (D-8 discharged, D-9 amended) all committed.

## Risks And Gaps

- **The re-derived bulk budget could reach the ceiling.** Handled by Decision 10:
  halt and return to the user. Measured likelihood is low — the governing term is
  `16 × median(p95)` and the median would have to nearly triple.
- **The window might still hold a pre-slice-45 tail** if docs-only runs are more
  numerous than estimated. Detected immediately by AC2's check and by
  `realistic_provider`'s `n=` falling from 128 to roughly 20; the response is a
  wider `--limit` and a re-run, not a weakened criterion.
- **A large budget diff is expected, not a smell.** A harvest re-derives every
  mode, so scenarios this slice never targeted will move. The opposite outcome — no
  budget changes at all — is also legitimate (`round_up_2sf` hysteresis) and is
  recorded as a finding rather than treated as an empty slice.
- **The dangerous direction is a budget that TIGHTENS.** A loosened budget is
  harmless: the runtime gate compares against this run's latency, so a budget with
  too much headroom fails loudly as `budget_stale`. A *tightened* budget is the one
  that reddens a clean tree — the window is doing exactly what slice 41 built it to
  do, an old freak sample ages out, and the re-derived budget lands closer to the
  observed latency than the code can reliably clear on a noisy runner. Every Phase 1
  check is arithmetic (does the literal reproduce from the corpus?) and none of them
  runs the benchmark, so **no Phase 1 check can fail on this**.

  The fourth review round added the one control that is available before CI, and it
  costs no code: the verification block takes a **pre-harvest budget baseline** and
  prints the directional diff, so the tightened set is known by name at the moment
  the literals are updated. `gov_p95` is the same fact in the sweep — a
  `max → median` flip *is* a tightening, mechanically (the `3 × max` term released
  and the budget fell back to `8 × median`). Neither is an assertion: tightening is
  legitimate behaviour, not a defect.

  What they change is that AC9's hosted PR-head run — still the only *empirical*
  control — now runs against a watch-list rather than blind. A green PR-head run
  stays load-bearing rather than a formality, and a `budget_exceeded` there after a
  clean local run is this risk materializing, not an engine regression; the diff
  says in advance which scenarios could produce it.
- **`realistic_provider`'s statistical base changes in kind.** Its window goes from
  128 shape-2 rows to roughly 20 shape-1 rows. Its budget will move for that reason
  alone, and that movement says nothing about the engine.
- **The harvester's provenance gap (D-7) is untouched.** This slice's two `failure`
  runs are cleared by a hand check recorded in the verification document. That check
  is evidence, not a control: the next harvest will not repeat it automatically.
- **The runtime absolute check cannot fire at all while the floor pin holds**
  (Decision 9) — structurally, not just on today's tree. Its falsifiability rests on
  synthetic unit tests, and the product target is really enforced by
  `testEveryGatedBudgetIsUnderItsClassCeiling` at `swift test` time. Stated here so
  the post-slice review's falsifiability audit does not have to rediscover it, and so
  nobody later "fixes" the unreachable branch by removing the pin that guarantees it.
