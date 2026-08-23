# Slice 54 — post-slice review (calibration-chain hardening: D-23 + D-7)

- **Slice:** 54 — soft-wrap arc, **no map node** (de-risking work for criterion 4)
- **Spec:** [`2026-08-23-calibration-chain-hardening-design.md`](../specs/2026-08-23-calibration-chain-hardening-design.md)
- **Plan:** [`2026-08-23-calibration-chain-hardening.md`](../plans/2026-08-23-calibration-chain-hardening.md)
- **Verification:** [`2026-08-23-calibration-chain-hardening.md`](../verification/2026-08-23-calibration-chain-hardening.md)
- **PRs:** [#129](https://github.com/maldrakar/swift-text-engine/pull/129) (implementation, merge `e97791f`), [#130](https://github.com/maldrakar/swift-text-engine/pull/130) (post-merge hosted proof)
- **Hosted proof:** PR-head `32658632217`, **post-merge push `32660537137`** on `e97791f`
- **Ledger:** discharges D-23 (P2) and D-7 (P2); adds D-26 (accepted-risk) during the slice, plus D-27/D-28/D-29/D-30 from this review

## What shipped

Two unsound links in the calibration chain, repaired **before** node 6 consumes them —
which is the whole point, because `harvest → derive` never re-measures and never
re-authenticates, so neither defect is fixable after node 6's first harvest.

**D-23, the measurement.** Both wrap benchmark modes timed one operation per
`clock.measure` and printed host-tick multiples (≈41.7 ns granularity) where their gated
siblings amortise over 256 operations and measure 17-94 ns. They now run through a shared
`amortisedSamples` helper whose division is a separate pure function, `amortise`, so a
dropped division is a red test rather than a silent restoration of the defect. Every
measurement prints its own `*_operations_per_sample=` token. `--wrap-compute`'s `reindex_ns`
stays a single unamortised measurement **by decision**, printed as
`reindex_operations_per_sample=1` so the exemption reads as a choice; its layout is now
bound and reused, removing a second O(N) pass and making the timed work observably live.
Drain ranges moved outside the clock, so `drain_p95_ns` stops measuring compute+drain.

**D-7, the provenance.** The harvester now reads `.head_repository.full_name` per candidate
run and admits only this repository's runs, failing closed on an unreadable source, with no
opt-out and the same check on the `--runs` path. A second hole found while reading for it is
closed in the same slice: the corpus gained a sixth **verdict** column, and both consumers
reject `{budget_exceeded, budget_absolute_exceeded, operation_failures}` at read time,
pinned across languages by `testAdmissibleRowsMatchDeriveScript` — the third cross-language
pin, beside the two window pins.

**No budget moved.** All 46 committed budgets re-derive byte-identically over an untouched
corpus, before and after, and across the merge.

## Acceptance-criteria status

All 17 PASS. AC13 (byte-identity) and AC17 (hosted proof) were both re-verified after the
post-implementation changes described below, not carried forward from the first green run.

| AC | Note |
|---|---|
| 1-6 | The timing repair. AC5 is a **diff read by design** — see P3 #2 below, which disputes that it has to be |
| 7-12 | Provenance, the verdict column, and the reject set in both languages |
| 13 | 46 budgets byte-identical; corpus untouched; holds across the merge commit |
| 14 | Neither wrap mode is gateable or appears in `swift-ci.yml` |
| 15-16 | Docs; **eleven** drills recorded with observed red (the spec's seven, drill 8 from the whole-branch review, drills 9-11 from a post-implementation validation pass) |
| 17 | Step-level on both halves: 3 jobs, 46 `gate=pass` / 0 `gate=fail`, 408/0, `invariant=pass`, `blocking_failures=0`, zero failure tokens. The merged tree is verified to carry the slice's artifacts, and the three new tests appear **by name** in the push run's log |

## Strengths

**The reject set is classified by what happened to the measurement, not by whether the gate
passed** — and the hardest case is argued rather than assumed. `budget_stale` is *admitted*
on purpose: it means the sample was fast, and `AGENTS.md`'s prescribed response to it is
"re-derive from fresh hosted evidence", which requires harvesting exactly those rows. A
filter that dropped them would instruct the operator to re-derive and simultaneously refuse
to collect the evidence. That reasoning is in the code, in the ledger, and in a truth-table
test.

**Degeneracy is read from `failures=`, not from the verdict, and the argument is
structural.** `formatSummary` prints `failures=N` unconditionally, outside its `--gate`
branch, and `gateFailureReason` returns `.missingBudget` *before* it tests `failureCount`.
So a degenerate ungated line — exactly the shape node 6 bootstraps with, because a new
mode's budget does not exist yet — would be admitted as healthy if the verdict were the only
signal. Catching this required reading the printer's branch order, not the spec.

**`conclusion` was rejected as a filter axis with an audit, not an opinion.** A run-level
filter discards both directions of a red gate and would have dropped 92 sound rows over a
WASM SDK failure — 46 rows each from two runs, one of which is inside the active N=20
window. The row-level verdict axis keeps the forty-five sound siblings when one mode fails.

**The exemption is printed as a value.** `reindex_operations_per_sample=1` rather than an
absent token is a small thing that will matter to whoever reads this line at node 6: an
absence reads as an oversight, a `1` reads as a decision, and the comment forbids
"consolidating" it.

**Both `AGENTS.md` contradictions the repair created were found and fixed**, including the
`budget_stale` paragraph, whose old wording was — as the slice's own commit message says —
indistinguishable from an instruction to launder a regression into a looser budget.

## Issues

### P0 / P1

None. The shipped behaviour is correct; every finding below is about what is *guarded*, not
about what the code does.

### P2 #1 — ten of twelve blocking gate steps have unpinned shape; `|| true` disarms one in silence

`WorkflowShapeTests.pinnedGateSteps` pins exactly two gate steps
(`--point-geometry-query`, `--realistic-provider`): for each, that its `run:` payload
**equals** the expected command, that it is not `continue-on-error`, that it carries the
docs-only guard, and that it sits between its ordering anchors. The workflow contains
**twelve** `--gate` invocations. The other ten are pinned by nothing.

Drill H, run against `main` at `c3603c6`:

```
$ # append " || true" to the --line-query --gate step in swift-ci.yml
$ swift test
Executed 408 tests, with 0 failures
```

That gate is disarmed and the suite is green. `|| true` and `continue-on-error` are the
exact pair `AGENTS.md` names as the Slice 16 dead-step trap ("a `continue-on-error` step
cannot be a gate — it swallows every non-zero exit"), and the repo learned that lesson by
losing a step for several slices.

**Why this belongs to this review rather than to a general backlog:** slice 54 hit the
identical defect class **twice**, and neither instance generalized. The whole-branch review
found that deleting the derivation's production awk filter left every check green and fixed
*that one site* (drill 8). The post-implementation validation pass then found the same shape
in the harvester and fixed *those two sites* (drills 9-10). The class is now three-for-three
and this is its fourth, largest instance: a guard whose decision is correct and whose
**invocation** is unguarded. Ten blocking latency budgets are in that state.

`pinnedGateSteps`' own comment already scopes the fix and explains why it was not taken:
generalizing to every gated mode needs a `flagName` property on `BenchmarkMode`, a
named-and-justified exemption set (the `.pipeline` default has no flag at all), and a test
pinning the two together — "a design of its own". That is a correct read of the cost; the
new information is that the cost now buys ten gates, not a tidier test.

→ **new ledger item D-27 (P2)**. Not escalated this review (born here), but it should be
scheduled within two slices rather than aged.

### P3 #1 — `amortisedSamples` claims to be the gated modes' shape, and nothing pins that

The helper's comment reads "the measurement shape every gated mode uses
(`LineQueryBenchmark.swift:73-89`)". **The claim is true today** — verified line by line:
`LineQueryBenchmark.swift:71-89` is one clock read per iteration, `operationsPerSample`
operations inside it, and `samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))`
at line 89, which the `:89` truncation citation names exactly.

But the twelve gated modes deliberately keep their own hand-rolled loops (spec Non-Goal 1:
any change to them can shift their numbers and drag a budget re-derivation), so the helper
and the loops it claims to mirror are now two implementations of one shape with nothing
holding them together. The drift lands precisely at node 6, where wrap budgets are derived
on the unstated assumption that a wrap number and a `line_query` number mean the same thing.

Cheap fix: a test that drives the helper and one representative gated loop over the same
synthetic body and asserts equal sample cardinality and equal per-operation arithmetic —
or, more honestly, a comment that stops claiming equivalence and says "modelled on".

→ **new ledger item D-28 (P3)**.

### P3 #2 — AC5's "cannot get a test" is overstated; the drain-purity property is testable

The spec, the plan, and the verification record all state that Decision 4 (the drain body
performs no `compute`) is reviewable but not machine-checkable, because `amortisedSamples`'
structural test pins the body's call count and a body that computed a range inside itself
would satisfy it unchanged. That reasoning is correct **about `amortisedSamples`' test** and
does not generalize: the property is about `BenchmarkWrapLayout`, not about the helper.

A counting wrapper around the layout — the exact shape `D-24`'s proposed fix uses, and that
`WrapRowQueryCountTests` already uses for probe counts — would assert that
`compute(_:layout:)` is invoked zero times across the drain loop. Naming this as untestable
puts a standing property (a future edit could reintroduce a `compute` call inside the drain
body, and the recorded before/after numbers would not obviously move) into the one category
this repo does not re-examine.

This is the guarantee the falsifiability audit below flags as having no failure evidence, so
it carries a mandatory candidate option.

→ **new ledger item D-29 (P3)**.

### P3 #3 — `reindex_ns` is structurally unharvestable, and that constrains node 6 and criterion 1

`--wrap-compute` prints `reindex_ns=` with no `p95_ns`/`p99_ns` companions, and the harvester
requires those **exact** keys. The consequence is not a defect in this slice — the
unamortised exemption is a ratified decision and the right one — but it should be written
down where node 6 will read it: **the width-change cost cannot become a gate through the
`harvest → derive` recipe at all.** That quantity is what criterion 1 is about, and it is
the one number in this mode that a budget would be interesting for.

Whoever takes node 6 must either accept that `--wrap-compute` gates only `compute_`/`drain_`
(leaving the reindex observational forever), or design a second mechanism for one-shot setup
costs. Deciding that at node 6 under time pressure is worse than recording it now.

→ **new ledger item D-30 (P3)**.

### P3 #4 — the derivation's `dropped=` counts span every mode even when one is requested

`derive-gate-budgets.sh <corpus> line_query` applies the verdict filter before the mode
filter, so its stderr reports rows dropped for modes the operator did not ask about. Cosmetic
— the counts are diagnostics, not a parsed format, and the numbers are correct for what they
claim — but it makes a single-mode re-derivation look noisier than it is. Fold-in.

→ folded into **D-26** as a fourth residual rather than a new id.

### Process observations

**Falsifiability design had an axis it was not covering.** The spec designed seven drills;
all seven target a decision *function*. Nothing in the design or plan asked what happens when
the function survives and its call site does not — and on the harvester the answer was that
every automated check in the repository stayed green while a fork's rows entered the corpus
carrying twelve blocking budgets. Two review passes found three instances. The generalizable
lesson, worth carrying into future specs: **for every guard, ask separately whether the
decision can fail and whether its invocation can go missing.** They are different tests.

**D-17 re-observed live.** The `${PIPESTATUS[0]}` idiom expanded empty in this session's own
shell (`exit=` with no value), inverting an assertion into a pass exactly as the ledger says.
The item is not stale; it is two completed slices old and one away from escalation.

**The verification record hit a genuine sha regress**, and the fix is worth reusing: a
section recording its own hosted proof can never name the run of the commit that contains it.
Resolved by cutting the hosted-proof branch **after** the merge, so it names the merged
tree's push run from outside it — which is also why this repo's convention of a separate
post-merge docs PR exists. The record now says "the last tree carrying non-documentation
changes" rather than a sha that its own commit falsifies.

**Two green PR-head runs are both recorded**, not just the last one. Dropping the first would
have hidden that the branch changed after its first green run.

---

# Recommendation (skill Mode 2)

**Map pass.** Slice 54 consumed **no map node** — the fifth slice of that shape, after the
process slice 48, the debt slice 51, and the calibration slices 52 and 54's own predecessor.
Nothing it shipped touched wrap feasibility, so nodes 4-9 and fork V stand unrevised and
un-relearned. What it changed is the ground **node 6** stands on, for the third consecutive
time (slice 52: the recipe's evidence and the absolute ceiling; slice 53: recorded the timing
defect; slice 54: repaired the timing and authenticated the evidence). Node 6's two named
inputs are now sound. Next step is **topological**, not a fork; the first genuine fork remains
node 8 (host order) / fork V.

### Scoreboard delta

**No criterion status changed.** Slice 54 advanced no criterion by design — it is de-risking
work for criterion 4, which binds future wrap gates to the `harvest → derive` recipe and the
absolute 60 FPS ceiling *by reference*. A gate calibrated from clock overhead, or from rows a
fork could have written, is this arc's own "gate that cannot fail" failure mode with a
deadline, and the deadline is node 6's first harvest.

Still open or partial, unchanged:

| # | Criterion | Status |
|---|---|---|
| 1 | Width change does not recompute the document | partial — core half retired (Slice 50); `done` needs fork V (exact reindex is Ω(N)) |
| 2 | Core memory not linear with wrap on; `--memory-shape` extended | open — no evidence at all |
| 3 | Wrap-aware query analogs + ∞ equivalence | partial — per-line, whole-document and y→row shipped; **point→(row, cell) is the last one** |
| 4 | 100k+/10 MB wrap scroll holds budgets; wrap modes become blocking gates | open — but both of its mechanism's inputs are now repaired |
| 5 | Incremental edits under wrap within frame budgets | open |
| 6 | Thin iOS + browser verification hosts | open |

### Debt ledger delta

**Discharged** (links in the ledger):

- **D-23** (P2, born slice 53) — both wrap modes measure through `amortisedSamples`; repaired before node 6's first harvest, as the deadline required. [PR #129](https://github.com/maldrakar/swift-text-engine/pull/129), push run `32660537137`.
- **D-7** (P2, born slice 46, carried since slice 42) — run-source authentication, failing closed, both entry paths; plus the verdict column and the read-time reject set. Same PR and run. Its call sites are guarded too, which was not true when it was first written as discharged.

**Added during the slice:** D-26 (P3, accepted-risk) — the reject set's residuals. This
review folds P3 #4 into it as a fourth residual.

**New from this review:**

| id | sev | statement |
|---|---|---|
| D-27 | **P2** | Ten of twelve blocking gate steps have unpinned shape; appending `\|\| true` to one leaves `swift test` 408/0 (drill H). `pinnedGateSteps` covers two. Fix scoped in its own comment: `flagName` on `BenchmarkMode` + a named exemption set + a pin between them |
| D-28 | P3 | `amortisedSamples` claims to be the twelve gated modes' measurement shape; true today, pinned by nothing, and the drift would land at node 6 |
| D-29 | P3 | AC5's "cannot get a test" is overstated — a counting layout wrapper can assert the drain body invokes `compute` zero times |
| D-30 | P3 | `reindex_ns` carries no `p95_ns`/`p99_ns`, so the width-change cost is structurally unharvestable; node 6 must accept that or design a second mechanism |

**Open counts after this review:** P2 open = **3** (D-17, D-24, D-27); P2 deferred by user =
1 (D-9); P3 open = 14; accepted-risk = 3.

**Escalation rule.** No open P2 is forced this review: D-17 is two completed slices old
(born slice 52), D-24 is one (born slice 53), D-27 is born here. **D-17 escalates at the next
review** and was re-observed live this session, so it should not be allowed to age quietly.

**D-9 requires a statement here**, per the slice-53/54 note that its *second* consecutive
re-affirmation must be followed by scheduling or an argument. The argument: slice 52 converted
the open half from a stale named list into a re-derivable observable — `derive-gate-budgets.sh`
prints `gov_p95=median|max` per scenario — so the watch is answerable on demand at every
re-derivation. That is a genuine substitute for a *list*, but not for a *fix*: nothing fails
when a p95 budget becomes max-governed. Recommendation: fold a one-line assertion into the
next calibration-touching slice (fail `GateFloorTests` if the count of max-governed scenarios
exceeds a committed number), or record a third explicit user defer. It should not reach a
fourth silent re-affirmation.

### Falsifiability audit

Standing guarantees this slice added or changed, each with its evidence of failure:

| guarantee | evidence it can fail |
|---|---|
| `amortise` divides (D-23's repair) | Drill 1 — mutating the body to `return elapsedNanoseconds` reddens 4 assertions; re-run independently at review time |
| `admissible_source` truth table | Drill 2; and drill D2 at review time (gutting the unknown branch → `self_test=fail`) |
| Reject set, under-filtering | Drill 3 (`testAdmissibleRowsMatchDeriveScript` reddens) |
| Reject set, over-filtering | Drill 4 — pinned in **both** directions |
| Swift five-or-six-column reader | Drill 5 |
| Laundered regression, end to end | Drill 6 — `budget_p95` 200 → 3000000 when admitted |
| `failures=` outranks the verdict | Drill 7; re-run at review time (`self_test=fail`) |
| The **production** awk filter (not the seam) | Drill 8, added by the whole-branch review; re-run at review time |
| The harvester's `admissible_source` **call site** | **Drill 9** — before the repair, deleting it left 407/0 and all four self-tests green while a fork's rows entered the corpus; after, `self_test=fail` |
| The harvester's `extract_rows` **call site** | **Drill 10** — same case covers it |
| The two Swift readers agree | **Drill 11** — one reader stops reading the column → 3 red |
| **Decision 4: the drain body performs no `compute`** | **NONE.** Diff read plus recorded before/after numbers only |

Eleven of twelve guarantees have recorded reds; two of those drills were designed by the
spec's own author to be impossible and turned out not to be. The twelfth is the mandatory
option below.

### Candidate options

**Option A — node 4: point→(row, cell) wrap-aware composite. ← lean, and this review selects it.**

- **Criteria:** advances criterion 3 and closes its *last enumerated analog*; the criterion
  goes `partial → done` if the equivalence oracle lands with it.
- **Ledger:** natural home for **D-24** (P2, the row-axis dispatch pinned by nothing — drill C
  in the slice-53 review left 397/0 green while bypassing it), **D-25** (P3), plausibly
  **D-13** (P3).
- **Map:** node 4, the topological next step. Selected by the slice-53 review and deferred by
  user call at slice 54's selection, so it is one slice overdue.
- **Not mechanical:** `columnAt` requires `columnOffset(inLine:column:0) == 0` and clamps to
  the **logical line's** edges, while a visual row is a `[startColumn, endColumn)` span with
  its own left edge — so x rebasing, and whether a clamp lands on the row's edge or the
  line's, are real design questions for the brainstorm.
- **By symmetry it adds a third wrap benchmark mode**, which is now born on the repaired
  amortised shape rather than becoming a third copy of D-23 — the argument slice 54's
  selection made for going first.

**Option B — node 6: promote the wrap modes to blocking gates.**

- **Criteria:** advances criterion 4, the only criterion whose mechanism is now fully repaired.
- **Ledger:** forces D-20/D-21 (the non-gateable modes' `AbsoluteCeiling` class is pinned by
  nothing, and that inertness ends the moment a wrap mode becomes gateable) and would surface
  D-30 immediately.
- **Against:** node 4 adds a third wrap mode by symmetry, so promoting now means node 6 either
  splits or repeats. Sequencing says take node 4 first — the same argument the slice-53 review
  used to reject node 5.

**Option C — infrastructure: D-27 (gate-step shape) + D-29 (the drain-purity pin).**

- **Criteria:** advances none. Would be the **sixth** non-criterion slice of the arc.
- **Ledger:** discharges the new P2 and the falsifiability audit's mandatory option.
- **Against:** the arc cannot afford consecutive no-criterion slices — that is precisely how a
  brief criterion stays open for ten slices, and slice 54 was already one. D-27 is real but
  newborn and not escalated; the gates work today and the exposure is to a future edit.
- **But:** D-29 is a **mandatory** option under the skill's falsifiability rule, and it is
  small. Recommend folding **D-29 into Option A** — node 4 touches the wrap benchmark surface
  and will add a mode of its own, so the counting-wrapper pin belongs there, not in a slice of
  its own.

**Routing.** Node 4 is a topological step, not a fork, so this review **selects Option A**
rather than routing to the user — who can of course override. Recommended fold-ins: **D-24**
(P2, born on node 4's own axis), **D-29** (mandatory), and **D-25**; **D-13** if the
brainstorm finds it rides on merit rather than convenience. **D-27 should be scheduled in
slice 56** at the latest, and **D-17 escalates at the next review**.
