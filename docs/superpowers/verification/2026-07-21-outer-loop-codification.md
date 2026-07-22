# Slice 48 verification — outer-loop codification

Spec: `../specs/2026-07-21-outer-loop-codification-design.md`
Branch: `slice-48-outer-loop-codification`

Subagent-run caveat (applies to every transcript below): the harness does not
expose a subagent's tool log, so "which files it read" is evidenced by the
prompt-mandated self-declaration at the end of each transcript, not by an
independent trace.

## AC5 — Mode 2 control vs treatment

### Fixture (frozen; both runs use it verbatim)

The fictional project is GridPager. Traps seeded in the data, per spec AC5:
(a) a new gate with no can-fail evidence, (b) an open criterion plus a
tempting diff-neighbor hook, (c) an open P2 aged 4 slices (D-3, born slice 3,
current slice 7).

Prompt body (the control run uses it as-is; the treatment run prepends the
skill instruction given in the treatment section):

> You are helping with a fictional Swift project called GridPager. This is a
> self-contained exercise: answer ONLY from the materials in this prompt. Do
> not browse, read, or search the repository you are running in; do not open
> any files; do not use any tools. Produce your answer as a single markdown
> message, and end it with a line `Files read: <list, or "none">`.
>
> Context — slice 7 has just merged. Its summary:
>
> "Slice 7 added the point→cell query `cellAt(x:y:)` to QueryEngine, and
> promoted `--cell-query --gate` to a blocking CI gate (step 9 of ci.yml),
> with p95/p99 budgets committed in Budgets.swift, both hosted runs (PR-head
> and post-merge) printing `mode=cell_query gate=pass` on the first try,
> docs and helper-script updates landing alongside, and the benchmark
> harness's flag listing regenerated. The
> PR discussion notes the natural next step: a batch variant `cellsAt(_:)`
> that resolves many points in one call, which several call sites would
> simplify around; two reviewers endorsed the batch API as slice 8."
>
> The project's debt ledger:
>
> | id | born | severity | statement | status |
> |---|---|---|---|---|
> | D-3 | slice 3 review | P2 | ci.yml step ordering is load-bearing but untested — a reorder silently disarms the docs-only guard | open |
> | D-6 | slice 6 review | P3 | benchmark summary line format duplicated in two files | open |
>
> The project's arc scoreboard:
>
> | # | Criterion | Status | Evidence |
> |---|---|---|---|
> | 1 | point→cell query with O(log N) bound | done | slice 7 PR |
> | 2 | row→range query | done | slice 5 PR |
> | 3 | scroll compute holds the 60 FPS budget on the 100k corpus | done | slice 6 gate |
> | 4 | engine memory stays O(viewport) regardless of document size | open | — |
> | 5 | every shipped query holds budgets on the 100k corpus | partial | cell-query gated (slice 7); row-range query still ungated |
>
> Task: produce the recommendation section of the slice 7 post-slice review —
> 2–3 candidate options for slice 8 with trade-offs, and your recommendation.

Trap rubric (evaluated for both runs):
- (a) flags that the `--cell-query` gate has never failed / has no red-run
  evidence, and includes an option (or option component) to prove it can fail;
- (b) options cite open criterion 4 and/or the ungated row-range half of
  criterion 5 — not only the batch-API diff neighbor;
- (c) D-3 (P2, age 4 slices) is surfaced as schedule-or-defer.

Control expectation (RED): misses at least (a) and (c). Calibration clause:
if the control surfaces all three traps, the scenario is too easy and must be
hardened until the control fails; each hardening iteration is recorded below.

Hardening iterations (the prompt body above is always the CURRENT — final —
version; iterations edited it in place):

- Iteration 1 (after control run #1, recorded below, caught trap (c)):
  applied hardening (2) — appended "two reviewers endorsed the batch API as
  slice 8" to the PR-discussion sentence, so the diff-neighbor momentum hook
  competes harder for the 2–3 option slots and carries social proof.
  Hardening (1) (bury the `gate=pass` clause in a longer changelog sentence)
  was deliberately skipped: it targets trap (a), which run #1 already
  MISSED — applying it would harden the shared fixture against the treatment
  run for zero calibration gain (the calibration goal is only to flip (c) to
  MISSED). The plan's hardening order is preserved among the hardenings
  actually applied: (2) now, (3) next if (c) survives.

- Iteration 2 (after control run #2, recorded below, caught trap (c) again —
  this time as an "opportunistic fold-in" of D-3 into slice 8's gate
  wiring): applied hardening (3) — moved the debt-ledger block above the
  scoreboard block, so recency bias works against D-3: the material closest
  to the task line is now the scoreboard, and the momentum-hooked slice
  summary sits first. No wording changed; pure reordering.

- Iteration 3 (after control run #3, recorded below, caught trap (c) a third
  time — "explicitly re-scoping D-3 as the very next slice"): applied the
  remaining plan hardening (1) — folded the standalone "Both hosted runs …
  gate=pass on the first try." sentence into the middle of a longer
  changelog sentence (added trailing changelog noise: docs/helper-script
  updates, regenerated flag listing). Mechanically this targets trap (a),
  which every run has already missed; it is applied to exhaust the plan's
  enumerated hardening list before concluding anything about (c), at ~zero
  cost to the treatment side (the skill's falsifiability audit keys off the
  gate promotion itself, not off the buried first-try-pass hint).

### Control run (RED)

All control runs dispatched via the harness Agent tool, `subagent_type:
general-purpose`, model `sonnet` — the same model as the treatment run, so
the comparison isolates the skill's effect, not model strength. Prompt = the
fixture prompt body current at dispatch time, verbatim, nothing else.

#### Run #1 — fixture v1 (pre-hardening) — NOT RED: trap (c) caught

Transcript (verbatim):

````markdown
## Slice 7 Post-Slice Review — Recommendation

### Candidate options for Slice 8

**Option A — Promote the row→range query to a blocking CI gate**
Give the slice-5 `row→range` query the same treatment slice 7 just gave `cellAt(x:y:)`: a `--row-range-query` benchmark mode, hosted-corpus budget derivation, and a new blocking step in ci.yml. This closes the specific gap arc criterion 5 already names.

- Pros: mechanically a repeat of the playbook slice 7 just executed, so risk and scope are well understood; zero engine/query-surface change; takes criterion 5 from "partial" to "done" outright; stops the "ungated query" gap from growing before more query surface is added on top of it.
- Cons: ships no new capability — pure CI/perf-governance work; row-range's cost profile may differ enough from cell-query's that budget derivation isn't a pure copy-paste (some fresh harvesting effort likely).

**Option B — Batch point→cell query `cellsAt(_:)`**
Build the batch variant the slice 7 PR discussion flagged as the natural next step, to simplify the call sites that currently loop over `cellAt`.

- Pros: directly requested by reviewers while context is fresh; concrete ergonomic win at real call sites; opens the door to internal optimizations (e.g., one shared traversal/sort across a batch instead of N independent O(log N) descents).
- Cons: adds new public API with no gate plan yet — landing it without a budget would leave criterion 5 *worse* in relative terms (1 of 3 shipped queries ungated instead of 1 of 2); to land it *with* a gate in the same slice roughly doubles scope (new query + benchmark + budget derivation + gate), which cuts against this project's pattern of keeping functional-core slices and gate-promotion slices separate; batch semantics (per-point error handling, ordering guarantees) need real design, not just a signature.

**Option C — Pay down D-3 (pin ci.yml step ordering)**
Add a standing test asserting the docs-only guard step structurally precedes the steps it's meant to gate, closing the P2 debt item open since slice 3.

- Pros: removes a known silent-failure mode (a step reorder could disarm the docs-only guard with no red build to notice it); it's the higher-severity of the two open debt items; small and self-contained.
- Cons: doesn't move the arc scoreboard at all; has sat open for four slices without an incident, so it's a latent risk rather than an active one; needs a short design pass to decide what "load-bearing order" should actually assert (structural pin vs. descriptive comment).

### Recommendation

**Option A.** It closes an explicitly tracked, partially-complete arc criterion at close to marginal cost, since slice 7 already proved out the exact mechanism (benchmark mode → hosted budgets → blocking gate step) on a sibling query. Doing this before Option B also matters directly: shipping `cellsAt(_:)` next would add a third query to the "still needs a budget" pile rather than shrinking the pile that already exists, and criterion 5's own wording ("row-range query still ungated") reads as the pre-flagged next gap to close rather than a footnote. Option C's debt is real and worth scheduling, but D-3 is P2 and has caused no incident in four slices, so it can follow without urgency cost.

Suggested sequencing beyond slice 8: slice 9 = Option B, scoped from the start to include its own gate promotion so `cellsAt(_:)` never becomes a second standing entry in the ungated-query gap; slice 10 = Option C, unless a ci.yml incident makes D-3 urgent enough to pull forward.

*Noted but deliberately excluded from the option set*: arc criterion 4 (engine memory O(viewport)) is the largest open item on the scoreboard, but it's foundational and currently undesigned — it warrants its own brainstorm/spec pass before it's plannable as a single slice, rather than being force-fit as a slice 8 candidate.

Files read: none
````

Verdicts (run #1):

- trap (a): MISSED — no sentence anywhere questions whether the just-promoted
  `--cell-query` gate can fail; the summary's "gate=pass on the first try"
  goes unexamined, and no option carries a red-run/mutation-proof component.
- trap (b): CAUGHT — "takes criterion 5 from 'partial' to 'done' outright"
  (Option A targets the ungated row-range half), and criterion 4 is weighed
  explicitly ("the largest open item on the scoreboard").
- trap (c): CAUGHT — "slice 10 = Option C, unless a ci.yml incident makes
  D-3 urgent enough to pull forward" (D-3 surfaced as an option with an
  explicit schedule; its 4-slice age is even noted).

Disposition: the RED expectation ("misses at least (a) and (c)") is NOT met —
(c) was caught, so a treatment catch of (c) would discriminate nothing.
Calibration clause fired → hardening iteration 1 (see the fixture section),
fresh control re-dispatched.

#### Run #2 — fixture v2 (hardening iteration 1) — NOT RED: trap (c) caught

Transcript (verbatim):

````markdown
## Slice 7 Post-Slice Review — Recommendation

### Candidate options for Slice 8

**Option A — Promote the row→range query to a blocking gate**
Row→range query has shipped since slice 5 but still carries no committed budget or `--gate` coverage — the scoreboard has flagged it as the sole reason criterion 5 ("every shipped query holds budgets on the 100k corpus") is "partial" rather than "done," and it's now been sitting ungated for two slices. This reuses the exact playbook slice 7 just proved out (add/confirm budgets, wire `--gate`, land a blocking CI step), touching no public API.
- *Pros*: smallest, best-understood scope; zero new API surface; closes a scoreboard gap that's been open the longest; low execution risk.
- *Cons*: no reviewer momentum behind it specifically; reads as "more CI/gate work" right after slice 7 did the same shape of thing.

**Option B — Batch point→cell query `cellsAt(_:)`**
The PR-endorsed next step: two reviewers want a batch variant of `cellAt(x:y:)`, with concrete call sites already identified that would simplify around it.
- *Pros*: reviewer-endorsed with real (not speculative) call-site motivation; keeps momentum from slice 7.
- *Cons*: it's a new public API needing its own design pass (batch error/partial-failure semantics aren't scoped by anything given here); shipped without a gate in the same slice it *widens* criterion 5's partial state rather than closing it; shipped together with a gate (as slice 7 did) repeats bundling capability-work and gate-work into one slice.

**Option C — Engine memory O(viewport) invariant (arc criterion 4)**
The only scoreboard row that's fully "open," not merely "partial." Nothing in the record indicates a memory-shape benchmark or verification harness exists yet, unlike the latency gates.
- *Pros*: closes the last untouched criterion; foundational, and the cost of retrofitting it only grows as more query surface (`cellAt`, a future `cellsAt`, row→range) ships without it being verified.
- *Cons*: highest effort — likely needs new benchmark infrastructure before there's even something to gate; not a clean "small vertical slice"; nothing in the current materials signals urgency beyond its open status.

### Recommendation

**Slice 8 = Option A** — gate the row→range query.

It's the lowest-risk, best-scoped option, it directly converts arc criterion 5 from "partial" to "done" (row→range is the only remaining ungated shipped query once cell-query is counted), and it reuses a gate-promotion playbook the project just executed successfully in slice 7. The batch API has real reviewer backing, but shipping it now either leaves it ungated (making criterion 5 worse, not better) or bundles capability + gate into one slice again — better to let it land as **Slice 9**, once every currently-shipped query sits on a uniform gated baseline, so `cellsAt(_:)` arrives into a clean state instead of adding to the same backlog it would otherwise create.

Option C is legitimate and shouldn't be indefinitely deferred — it's the only fully-open scoreboard row — but it looks like it needs its own design/spec slice (new benchmark harness, not a drop-in gate against existing infra) rather than being the next natural step. Worth naming explicitly as a near-term target so it doesn't keep losing out to lower-effort, query-shaped options; if it's passed over again next review, that's worth calling out directly.

**Opportunistic fold-in**: since Slice 8 touches `ci.yml` gate wiring regardless of choice, it's a cheap moment to also land a small pinning test for **D-3** (P2 — untested step ordering that could silently disarm the docs-only guard) alongside the new row-range gate step, rather than spending a standalone slice on it later. **D-6** (P3, duplicated benchmark summary format) isn't touched by this work and shouldn't be forced in — leave it open.

Files read: none
````

Verdicts (run #2):

- trap (a): MISSED — the gate's can-fail evidence is again never questioned;
  no red-run/mutation-proof component in any option.
- trap (b): CAUGHT — Option A targets the ungated row-range half of
  criterion 5; Option C is criterion 4 itself.
- trap (c): CAUGHT — "it's a cheap moment to also land a small pinning test
  for **D-3** ... alongside the new row-range gate step" (an explicit
  schedule of D-3 into slice 8, despite the strengthened batch momentum).

Disposition: still NOT RED — (c) survived hardening (2). → hardening
iteration 2 (see the fixture section), fresh control re-dispatched.

#### Run #3 — fixture v3 (hardening iteration 2) — NOT RED: trap (c) caught

Transcript (verbatim):

````markdown
# Slice 7 Post-Slice Review — Recommendation for Slice 8

## Candidate options

### Option A — Batch point→cell query: `cellsAt(_:)`
Add a batch-resolving variant of `cellAt(x:y:)` that takes many points and resolves them in one call.

- **For:** Directly requested in the slice 7 PR discussion, with two reviewers endorsing it; call-site simplification is concrete and immediate, not speculative; builds on `cellAt` while the query and its budget model are still fresh in context.
- **Against:** Doesn't close anything on the arc scoreboard or debt ledger — criteria 4 and 5 stay exactly where they are. Worse, it *grows* the gap in criterion 5: a third shipped query (`cellAt`, row→range, now `cellsAt`) with only one gated today makes "every shipped query holds budgets" harder to reach, not easier. Its own performance envelope (O(k log N) for k points? better via batching?) is undefined and would need its own budget derivation before it could ever be gated.

### Option B — Promote row→range query to a blocking gate
Close out arc criterion 5 by giving the row→range query (shipped slice 5) the same treatment `cellAt` just received in slice 7: corpus-derived p95/p99 budgets in Budgets.swift, wired as a blocking ci.yml step.

- **For:** The smallest, best-understood option on the table — slice 7 just proved this exact playbook (budget derivation → Budgets.swift entry → blocking step) end to end on hosted CI, twice. It fully flips criterion 5 from "partial" to "done" in one slice, since row→range is the only remaining ungated query on the board. Low implementation risk, high confidence of a clean ship.
- **Against:** No reviewer asked for it. And it lands directly on the surface D-3 flags as dangerous: adding a new blocking step means inserting into ci.yml's step ordering, which is exactly the "load-bearing but untested" ordering D-3 warns can silently disarm the docs-only guard. Shipping this with no ordering check is building directly on the crack D-3 already identified.

### Option C — Verify arc criterion 4: engine memory stays O(viewport)
Add a memory-shape diagnostic that exercises the engine across a range of document sizes and asserts engine-owned memory stays flat/bounded by viewport rather than document size.

- **For:** The only arc criterion with *zero* evidence — not partial, fully open. It's also the most foundational: if bounded memory regardless of document size is core to GridPager's value proposition, every slice shipped since has been adding surface (including the reviewer-endorsed batch API under discussion) on top of an unverified architectural claim. Cheaper to catch a violation now, with two queries, than later with more.
- **Against:** Least well-scoped of the three — no existing playbook to reuse the way B reuses slice 7's, so sizing and design work is needed before this is even TDD-able. Real risk of ballooning into a multi-slice arc rather than landing as one clean slice.

## Recommendation

**Option B.** It's the only option that fully closes an open scoreboard item this slice, at the lowest risk, reusing a pattern already proven hosted-green twice in slice 7. It doesn't foreclose the others: Option C should follow soon — ideally slice 9 — precisely because it's the last fully-open criterion and the cost of leaving it unverified only grows as more queries ship; Option A becomes a cleaner pickup once it lands on a fully-gated query set instead of adding a third ungated surface onto a still-partial one.

One caveat: shipping B means inserting a new step into ci.yml's ordering, which lands squarely on the risk D-3 already flagged. Pair B with either (a) a minimal check that the docs-only guard still fires correctly after the new step is inserted, or (b) explicitly re-scoping D-3 as the very next slice if that's out of scope for B itself. A second untested reorder stacked on the first is how D-3 stops being a P2 on a ledger and starts being an incident.

Files read: none
````

Verdicts (run #3):

- trap (a): MISSED — "proved this exact playbook … hosted-green twice" is
  even cited as a *positive*; the gate's can-fail evidence is never
  questioned, no red-run/mutation-proof component anywhere.
- trap (b): CAUGHT — Option B targets the ungated row-range half of
  criterion 5; Option C is criterion 4 itself.
- trap (c): CAUGHT — "explicitly re-scoping D-3 as the very next slice if
  that's out of scope for B itself" (an explicit schedule-or-defer of D-3;
  moving the ledger above the scoreboard made it *more* woven-in, not less).

Disposition: still NOT RED — (c) survived hardening (3). One enumerated
hardening remains, (1); it targets (a) but is applied to exhaust the plan's
list → hardening iteration 3 (see the fixture section), fresh control
re-dispatched.

#### Run #4 — fixture v4 (hardening iteration 3) — RED: traps (a) and (c) both missed

Transcript (verbatim):

````markdown
# Slice 7 Post-Slice Review — Recommendation

## Candidate options for Slice 8

### Option A — Batch point→cell query: `cellsAt(_:)`
Ship the batch variant of `cellAt(x:y:)` flagged in the slice 7 PR discussion, resolving many points in one call.

**For:**
- Two reviewers explicitly endorsed it, with identified call sites that would simplify around it — not speculative demand.
- Direct, low-ambiguity extension of slice 7 while the `cellAt` internals are still fresh in context.

**Against:**
- Grows the set of shipped queries while scoreboard item 5 ("every shipped query holds budgets on the 100k corpus") is still only *partial* — the row→range query (slice 5) remains ungated. A second ungated query compounds that gap instead of closing it.
- If implemented as a thin loop over `cellAt`, the real work is a new benchmark mode + gate + budgets for a query that doesn't exist yet — structurally the same lift as Option B, just for new surface area rather than existing debt.
- Doesn't move arc item 4, the only scoreboard row with zero progress.

### Option B — Promote row→range query to a blocking CI gate
Give the slice-5 row→range query the same treatment `cellAt` just received: committed p95/p99 budgets, a `--gate`-blocking CI step, docs/helper-script updates.

**For:**
- Fully closes arc item 5 (partial → done): every shipped query would then hold budgets on the 100k corpus.
- Slice 7 just validated this exact playbook end-to-end — both hosted runs printed `gate=pass` on the first try, zero engine changes required. Execution risk is close to zero.
- Shrinks open scoreboard surface rather than adding to it; the gap has already lagged two slices (born slice 5, still open at slice 7).

**Against:**
- Not the direction reviewers asked for in the slice 7 PR; batch-query momentum may cool if deferred a slice.
- No new capability — back-to-back "gate promotion" slices with slice 7.
- Leaves D-3, D-6, and arc item 4 untouched.

### Option C — Engine memory invariant: O(viewport) regardless of document size
Begin work on arc item 4, the only scoreboard row still fully open with no prior slice against it.

**For:**
- Nothing has touched it yet; every slice that skips it leaves it open longer, and it's a structural invariant — cheaper to establish before more query surface (cellsAt and beyond) gets built on assumptions it might violate.

**Against:**
- Materials at hand contain no design/benchmark shape for this yet — likely needs its own brainstorm/spec pass before it's plannable as a TDD slice, unlike A/B which are both directly executable now.
- Orthogonal to the concrete momentum and reviewer feedback currently on the table.
- Bigger, less-scoped slice to schedule immediately after a clean, fast slice 7.

## Recommendation

**Option B** — promote the row→range query to a blocking `--gate`, closing scoreboard item 5 completely — ahead of the batch `cellsAt(_:)` API.

Rationale: slice 7 already proved this exact playbook works (budgets committed, both hosted runs `gate=pass` on the first try), so scope and risk are both well understood and small. Taking Option A next instead would grow shipped-but-ungated query surface at the exact moment the scoreboard flags that as the open gap — the wrong direction. Closing it first means the batch query lands into a state where every existing query is gated, and its own eventual gate work has one less "how do we gate this" question to invent from scratch.

The reviewer-endorsed `cellsAt(_:)` isn't rejected, only resequenced: recommend it as **slice 9**, immediately after. PR momentum should easily carry across one slice.

Option C is worth surfacing to the user now as the next arc gap after A/B, but isn't concrete enough to commit as slice 8 — suggest a brainstorm/spec pass on it in parallel, targeting slice 9 or 10.

Debt note: D-3 (P2, untested CI step-ordering) deserves a follow-up slice given it concerns *silent* CI failure, but slice 7 didn't touch `ci.yml` ordering, so it doesn't block or get displaced by this recommendation. D-6 (P3) stays low-priority housekeeping.

Files read: none
````

Verdicts (run #4):

- trap (a): MISSED — "both hosted runs printed `gate=pass` on the first
  try" is twice cited as evidence of *low execution risk*; the gate's
  can-fail evidence is never questioned, and no option carries a
  red-run/mutation-proof component.
- trap (b): CAUGHT — Option B targets the ungated row-range half of
  criterion 5; Option C is criterion 4 itself (allowed: the expectation
  says "(b) may go either way").
- trap (c): MISSED — D-3 appears only in a trailing "Debt note": "deserves
  a follow-up slice … doesn't block or get displaced by this
  recommendation". That is an acknowledgment, not a schedule-or-defer:
  D-3 is not among the candidate options, gets no slot (contrast run #1's
  "slice 10 = Option C", run #2's fold-into-slice-8, run #3's "the very
  next slice"), carries no explicit defer decision, and its 4-slice age is
  never noted. A review ending this way leaves the P2 drifting — exactly
  the pathology the skill's escalation rule exists to stop, and the bar
  the treatment run must clear.

Disposition: **RED achieved on fixture v4** — the control misses (a) and
(c); (b) caught is explicitly allowed. Fixture v4 (the prompt body in the
fixture section above) is the FINAL frozen fixture; the treatment run uses
it verbatim. Scoring note: runs #1–#3 were scored CAUGHT on (c) for
actionable dispositions (a named slot, a fold-in to slice 8, "the very next
slice"); run #4's non-committal mention fails that same bar. The verbatim
transcripts above let this scoring be re-checked.

Honesty note on causality (added at task review's suggestion): the two
(c)-targeting hardenings, (2) and (3), did NOT flip (c) — runs #2 and #3
still caught it — and run #4 differs from run #3 only by hardening (1),
which targets (a). The (c) miss in run #4 is therefore best read as
run-to-run control variance scored against a consistent bar: a single
demonstrated control failure on (c), not a property fixture v4 reliably
induces. AC5's discrimination on (c) accordingly rests on the treatment
catching it decisively via the skill's escalation rule, not on the control
being structurally unable to catch it.

### Treatment run (GREEN)

Dispatched via the harness Agent tool, `subagent_type: general-purpose`,
model `sonnet` — the same model as every control run. Prompt = the plan's
treatment preamble (read exactly ONE file, the skill; follow its Mode 2
checklist; treat the excerpts below as the current artifact states; describe
artifact updates instead of writing files), then the frozen fixture v4
prompt body verbatim.

Transcript (verbatim):

````markdown
# Slice 7 Post-Slice Review — Recommendation Section

Produced per `.claude/skills/choosing-next-slice/SKILL.md`, Mode 2 ("Recommend next" — used at the end of every post-slice review).

## Map pass (arc file update — not one of the four required headers)

Per Mode 2, this runs first; its output is the updated arc file, described here rather than written.

- **Mark slice 7 finished on the map.** The node delivered `cellAt(x:y:)` (criterion 1) *and* its gate promotion (feeding criterion 5) in a single slice — feature and gate landed together rather than split across two slices.
- **Re-validate against what the slice taught.** Slice 7 proves a repeatable recipe: ship a query, then gate it, in one pass. That recipe has an obvious next application — row→range query (criterion 2, shipped slice 5) still has no gate. Add/confirm that node as the map's direct successor to slice 7.
- **Criterion 4** (engine memory O(viewport)) still has no node on the map — no design work, no evidence, nothing. It remains the arc's least-started criterion and biggest blind spot. It isn't actionable as a single slice yet (no groundwork to build on), so it is not promoted to a slice-8 candidate below, but it's flagged here as a likely future **fork** (multiple defensible memory-bounding strategies could exist) — worth a design spike before it becomes a slice, not a drive-by pick.
- **Next-step classification: topological.** Slice 8 doesn't require a product-direction choice among competing architectures — see Candidate options below.

## Scoreboard delta

Changes attributable to slice 7:

| # | Criterion | Before → After | Evidence |
|---|---|---|---|
| 1 | point→cell query with O(log N) bound | open → **done** | slice 7 PR (`cellAt(x:y:)` + hosted `gate=pass`) |
| 5 | every shipped query holds budgets on the 100k corpus | open → **partial** | slice 7 PR (`--cell-query --gate`, ci.yml step 9, both hosted runs green) |

Unchanged: #2 (done, slice 5), #3 (done, slice 6 gate).

**Still open or partial:**
- **#4 open** — engine memory O(viewport) regardless of document size. No evidence at all.
- **#5 partial** — cell-query is gated; row→range query (done since slice 5) is still ungated.

## Debt ledger delta

No existing item discharged this slice. One new item, generated by the falsifiability audit below:

| id | born | severity | statement | status |
|---|---|---|---|---|
| D-3 | slice 3 review | P2 | ci.yml step ordering is load-bearing but untested — a reorder silently disarms the docs-only guard | open — **escalates this review** |
| D-6 | slice 6 review | P3 | benchmark summary line format duplicated in two files | open |
| D-7 | slice 7 review | P2 | `--cell-query --gate` (ci.yml step 9) has never been observed to fail — both hosted runs (PR-head, post-merge) printed `gate=pass` on the first try; no red run, mutation check, or deliberate break on record | open |

Open counts: **2 P2 (D-3, D-7), 1 P3 (D-6), 3 total.**

**Escalation check:** D-3's origin is slice 3 review; slices 4, 5, 6, and 7 have completed since (≥3 by any reasonable boundary count). Per the checklist's escalation rule it **MUST appear under Candidate options this review** — it carries no `deferred(user, date)` status, so silence is not a legal state here. It appears below as Option B, scheduled into slice 8 rather than carried a fifth time.

## Falsifiability audit

Standing guarantees this slice **added**:
1. `--cell-query --gate` — new blocking CI gate, ci.yml step 9.
2. Committed p95/p99 budgets for `cell_query` in `Budgets.swift` — new calibration input backing that gate.

Evidence either can fail: **none.** Both hosted runs (PR-head and post-merge) printed `mode=cell_query gate=pass` on the first try. No recorded red run, no mutation check, no deliberate temporary break. This is the top-listed red flag in the skill ("the new gate/oracle/pin passed on the first try" → "has it ever failed? Show the red"), and it is currently unaddressed.

→ **Mandatory candidate option:** prove `--cell-query --gate` can fail (logged above as D-7, presented below as Option A).

## Candidate options

**Option A — Prove `--cell-query --gate` can fail.** *(mandatory: falsifiability audit)*
Temporarily regress `cellAt` (or force an impossible budget), confirm the run flips to `gate=fail`, capture that as the recorded red, then revert; add a standing mutation/unit check on the gate's pass/fail logic so the evidence doesn't rot.
- *Advances:* no criterion directly — it's the evidence backing criterion 1 ("done") and criterion 5 ("partial"), not a new criterion.
- *Ledger:* discharges D-7.
- *Map:* sits immediately after slice 7, before any further gate reuses the same unproven mechanism.
- *Trade-off:* small and fast; skip it and every future `gate=pass` on this mechanism — including a future row-range gate — inherits the same unverified trust.

**Option B — Discharge D-3: pin ci.yml step ordering.** *(mandatory: escalation rule, ≥3 slices stale)*
Add a workflow-shape test (or equivalent pin) asserting the docs-only guard's required step order, so a future reorder can't silently disarm it.
- *Advances:* no criterion directly, but protects the enforcement integrity criterion 5 depends on (a query only "holds budgets" if the gate enforcing that can't be silently bypassed).
- *Ledger:* discharges D-3.
- *Map:* cross-cutting CI-hygiene node, independent of which query ships next.
- *Trade-off:* doesn't move the scoreboard, but it's the oldest open ledger item, and the checklist forbids letting it roll again without an explicit schedule or user defer.

**Option C — Promote row→range query to a blocking gate.**
Repeat slice 7's recipe for the query shipped in slice 5: add `--row-range-query --gate`, derive and commit p95/p99 budgets, wire it into ci.yml, get both hosted runs green.
- *Advances:* criterion 5, **partial → done** (both shipped queries would then be gated).
- *Ledger:* discharges none directly; possible incidental fold-in of D-6 if the new gate's summary-line output touches the duplicated formatting code (worth checking during implementation, not guaranteed).
- *Map:* topological, low-risk, directly mirrors the just-proven slice 7 pattern.
- *Trade-off:* real, visible scoreboard progress — but it stacks a second instance of the same gate machinery before Options A/B confirm that machinery is trustworthy and that CI can't silently reorder around it.

**Considered and set aside — batch `cellsAt(_:)`.** PR-endorsed by two reviewers and the most obvious continuation of the just-merged diff. But it advances none of the five scoreboard criteria (a convenience/perf variant of an already-"done" query, not a new criterion) and discharges no ledger item — it is close to the textbook case of the skill's own warning: *"the options are the neighbors of the last diff → consult the scoreboard first."* Worth revisiting once it can be justified against the scoreboard; not picked for slice 8 on the evidence given.

### Recommendation

Routing: **not a fork** — A, B, and C don't compete for one architectural slot; nothing here is a genuine product-direction disagreement, so this is a topological call stated directly (the user can still override), not a referral for a product decision.

**Lean: slice 8 = Option A + Option B together; slice 9 = Option C.**

A and B are both small, both are mandatory outputs of this exact review (one from the falsifiability audit, one from the debt-escalation rule), and both are CI-gate-integrity concerns rather than product surface — bundling them is cheap and coherent. Doing them first means slice 9's row-range gate (Option C) lands on infrastructure already shown to catch a regression, ordered by a pinned CI, instead of stacking a second unverified gate on top of the first. This also satisfies the escalation rule's "scheduled" requirement for D-3 outright, rather than listing it again and letting it roll to a fifth review.

Files read: /Users/aabanschikov/swift-text-engine/.claude/skills/choosing-next-slice/SKILL.md
````

Verdicts (treatment):

- trap (a): CAUGHT — the falsifiability audit lists both added guarantees
  (the gate and its committed budgets), states "Evidence either can fail:
  **none**", and spawns the mandatory option: "Option A — Prove
  `--cell-query --gate` can fail" with a captured-red + standing
  mutation-check plan, logging it as new ledger row D-7. Notably this was
  caught despite hardening (1) having buried the first-try-pass tell — the
  audit keyed off the gate promotion itself, exactly as the iteration-3 log
  predicted.
- trap (b): CAUGHT — the option set is scoreboard-driven: Option C is the
  ungated row-range half of criterion 5 ("partial → done"); criterion 4 is
  examined in the map pass and deliberately routed to a design spike rather
  than ignored; the batch API is explicitly set aside citing the skill's
  own red flag ("the options are the neighbors of the last diff → consult
  the scoreboard first").
- trap (c): CAUGHT — the escalation rule is applied by name with the age
  computed ("origin is slice 3 review; slices 4, 5, 6, and 7 have completed
  since") and D-3 becomes Option B, scheduled into slice 8 "rather than
  carried a fifth time".

Contract headers: all four present with exact names, in contract order
(Scoreboard delta → Debt ledger delta → Falsifiability audit → Candidate
options), preceded by a map pass that correctly carries no contract header
of its own. Recorded variance: the subagent emitted them at `##` heading
level rather than the contract's `###` — the treatment PASS bar is
presence-in-output; the level was the subagent's own document-structure
choice (its top-level sections are all `##`).

Files read (self-declared): only
`.claude/skills/choosing-next-slice/SKILL.md` — exactly the one file the
preamble permits.

Verdict: **GREEN — PASS on the first treatment run.** All three traps
caught and all four contract headers present, against the same fixture v4
the final control failed. The differential is stark: four control runs
produced zero falsifiability questions and zero contract structure; the
treatment produced the full ritual (map pass, both deltas with open counts,
a mandatory prove-it-can-fail option, rule-cited escalation of the aged
P2).

## AC6 — Mode 1 executability run

Precondition verified immediately before dispatch (part of test validity —
the committed arc file must not exist yet, so the run cannot crib from it):

```
$ ls docs/superpowers/arcs 2>&1; echo "arcs_exit=$?"
ls: docs/superpowers/arcs: No such file or directory
arcs_exit=1
```

Dispatched via the harness Agent tool, `subagent_type: general-purpose`,
model `sonnet`. Dispatch prompt, verbatim:

> This is a process-execution exercise. Read EXACTLY two files and nothing
> else: `.claude/skills/choosing-next-slice/SKILL.md` and
> `docs/wrap-project-brief.md`. Do not open any other file, do not list
> directories, do not search, do not read the initial brief the wrap brief
> references — where the wrap brief inherits constraints by reference,
> assume they exist and are enforced. A new arc is starting from that
> brief; the previous arc closed with all its criteria met and CI green.
> Execute the skill's Mode 1 (Arc start) and output, as one markdown
> message: (1) the scoreboard table derived from the brief; (2) a draft
> slice map with fork markers; (3) the named top feasibility risk with your
> rationale; (4) which slice you would run first and why. Output only — do
> not create or modify any files. End with a line `Files read: <list>`.

Transcript (verbatim; one restoration applied: the harness notification
layer XML-escapes `>` in agent output, and those transport escapes were
restored to the `>` characters the agent wrote — e.g. ">10MB" and the
map's ASCII "->" arrows. No other characters altered):

````markdown
# Wrap Arc — Mode 1 (Arc Start) Execution

## 1. Scoreboard

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Wrap-width change (rotation/resize) doesn't require recomputing the whole document — frame cost stays viewport-bounded, in the spirit of the existing O(log N) + O(buffer) | open | — |
| 2 | Core memory doesn't grow linearly with document size when wrap is enabled — wrap data lives behind the provider abstraction like other metrics; `--memory-shape` extends to the wrap path | open | — |
| 3 | Existing queries gain wrap-aware equivalents — compute over visual rows, y→row, point→(row, cell); no-wrap path is preserved; wrap path at infinite wrap width must equal it (equivalence oracle, mirroring "variable == fixed at uniform metrics") | open | — |
| 4 | Scrolling 100k+ lines / >10MB with wrap enabled holds p95/p99 budgets and the absolute 60 FPS ceiling; new wrap modes become blocking CI gates via the existing harvest → derive recipe | open | — |
| 5 | Incremental edits with wrap enabled (in-line edit, structural insert/delete) stay within the frame-hot-path budget | open | — |
| 6 | iOS verification host feeds the core CoreText-measured advances; browser verification host feeds canvas `measureText`-measured advances over the WASM build; both observably scroll a wrapped document smoothly | open | — |

**Constraints** (enforced per-slice, not scored as rows):
- All constraints of the [initial brief](../initial-project-brief.md) — Foundation-free core, Swift Embedded compatibility, zero-dependency, iOS+WASM compile with no source changes, strict viewport-bounded core memory — carry forward in full to the wrap layer.
- Break opportunities and advance metrics are provider-supplied; the core contains no Unicode tables, shaping, or font knowledge — only the math of packing advances into rows.
- Bidi and shaping are out of scope; rows are described in visual order.
- No rendering in the core. Verification hosts are separate non-core targets with no reusable-component commitment — "a scrolling rectangle with text."

All six criteria are open — this is an arc start, nothing wrap-related has shipped yet.

## 2. Draft slice map

```
W1 [pending] Wrap provider abstraction + single-line row-packing math
   (no deps — entry point; front-loads the top risk, see §3)
   |
   v
W2 [pending] Cross-document wrap compute (visual-row viewport range)
   (fallback/generic indexing first; equivalence oracle v1 @ infinite width)
   |
   v
W3 [pending] y->row query + geometry companion (wrap-aware lineAt/lineGeometryAt)
   |
   v
FORK A: sequencing call, all three still ship —
        (a) harden to resize-safe O(log N) wrap indexing now [lean — retires
            the named top risk for real, see §3/§4],
        (b) extend breadth to point->(row,cell) first, or
        (c) promote --memory-shape + a first wrap CI gate on what exists first?
   |
   +-- W4a [pending] Resize-safe O(log N) wrap indexing
   +-- W4b [pending] point->(row,cell) 2D composite for wrap
   +-- W4c [pending] --memory-shape wrap extension + first wrap gate promotion
   |
   v
W5 [pending] Incremental edits under wrap (in-line + structural insert/delete)
   (topological dep on W4a — needs an incrementally-updatable wrap index)
   |
   v
W6 [pending] Remaining blocking CI-gate promotions for wrap benchmark modes
   |
   v
W8 [pending] Arc-closing hardening (remaining oracle/gate gaps, scoreboard all-done)
   ^
   |
FORK B (parallel branch — only needs W2/W3, does not wait on W4-W6):
        iOS CoreText host first, vs. browser/WASM canvas-measureText host
        first, vs. both together in one slice? [no lean — symmetric platforms,
        pure scheduling call]
   |
   +-- W7a [pending] iOS verification host (CoreText advances, smooth-scroll demo)
   +-- W7b [pending] Browser/WASM verification host (canvas measureText, smooth-scroll demo)
```

(Labels are placeholders for map slugs, not committed slice numbers — the first would likely land after the in-flight Slice 48 outer-loop-codification work, but that's scheduling, not this map's concern.)

## 3. Top feasibility risk

**Criterion 1 — wrap-width change must not require a full-document recompute, with frame cost bounded by the viewport.**

Every other criterion is a mechanical extension of a pattern already proven up to twelve times in this codebase: add a wrap-aware overload of an existing query, wire an equivalence oracle against the no-wrap path, promote a new benchmark mode to a blocking gate via harvest→derive, extend `--memory-shape`. Slices 27 through 40 are a long, repeated demonstration that this shape of work lands cleanly.

Criterion 1 is structurally different. Everything the engine currently indexes cumulatively (line offsets, column offsets) is a **static** per-document-state quantity that only changes on an explicit structural mutation the engine already knows how to update incrementally (Fenwick/balanced-tree providers). Wrap width is not document state — it's a **runtime parameter**, and the row count a single logical line produces is a function of that parameter. That makes the cumulative visual-row offset of every line downstream of line 0 a width-dependent prefix sum. A resize invalidates that entire prefix sum at once, yet criterion 1 demands the next frame's cost stay viewport-bounded, and criterion 2 simultaneously forbids caching per-width layouts in core memory (that would grow with document size). Naive eager recomputation violates criterion 1; naive full memoization violates criterion 2. Nothing in the current architecture's prefix-search hooks (`lineIndex(containingOffset:)`, `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`) has ever had to answer a query whose underlying cumulative structure itself changes on every call with a new parameter — this needs either a genuinely new provider-hook shape or a lazy/incremental re-flow structure that has no precedent in this codebase yet.

This is exactly the kind of thing the skill's red flag warns about ("If the scariest thing feels comfortable to postpone, that is the red flag") — it would be easy to instead start with the breadth work (point→(row,cell), more query surface) since that's comfortable, proven territory, and defer the resize question until "later." The map above resists that by putting the packing-math foundation (W1) and cross-document compute (W2) first, and by making "harden to resize-safe indexing" the leaned option at Fork A rather than letting breadth-first or gate-first quietly become the path of least resistance.

## 4. First slice to run

**W1 — wrap provider abstraction + single-line row-packing math.**

It's the only node in the map with no dependencies, so it's the only legal entry point regardless of risk. It's also where the risk named in §3 first becomes tractable: before any cross-document indexing question can be answered, the core needs a settled shape for what a visual row *is* (its provider-supplied inputs — break opportunities, advances — and the packing algorithm that turns one line's advances into an ordered sequence of rows in visual order). Getting that single-line contract right first is what makes it possible to reason about the resize/prefix-sum problem in W2/Fork A concretely instead of abstractly. Starting anywhere else (e.g., jumping to compute or to a platform host) would mean building on a data model that hasn't been proven out yet.

---

**Process note:** Mode 1 step 4 (debt carry-over from `docs/superpowers/debt-ledger.md`) and a full Mode 2 pass for step 5 (scoreboard delta / debt-ledger delta / falsifiability audit for slice selection) were not performed — both require reading files outside the two this exercise permitted. The "first slice" answer above is the direct selection the map and risk analysis support, not the output of a complete Mode 2 checklist.

Files read: .claude/skills/choosing-next-slice/SKILL.md, docs/wrap-project-brief.md
````

Self-declared **`Files read:`** line: exactly the two permitted files —
`.claude/skills/choosing-next-slice/SKILL.md` and
`docs/wrap-project-brief.md` (see the subagent-run caveat at the top of
this doc: this declaration is the recordable evidence).

PASS/FAIL is NOT decided here: the comparison target
(`docs/superpowers/arcs/wrap.md`) is created by Task 4, which performs the
subject-level mapping and records the verdict below.

### AC6 comparison and verdict (Task 4)

Subject-level mapping of the subagent's scoreboard rows onto the committed
`docs/superpowers/arcs/wrap.md` scoreboard:

| Subagent row (abridged subject) | Subject class | Committed criterion |
|---|---|---|
| 1 — wrap-width change (rotation/resize) doesn't recompute the document; frame cost viewport-bounded | width-change cost | 1 |
| 2 — core memory not linear with wrap on; provider abstraction; `--memory-shape` extends | memory + memory-shape | 2 |
| 3 — wrap-aware equivalents (visual-row compute, y→row, point→(row, cell)); no-wrap preserved; infinite-width equivalence oracle | wrap-aware queries + oracle | 3 |
| 4 — 100k+/>10MB scroll holds p95/p99 + absolute 60 FPS; wrap modes become blocking gates via harvest → derive | budgets + gates | 4 |
| 5 — incremental edits under wrap stay in frame-hot-path budget | incremental edits | 5 |
| 6 — iOS CoreText host + browser canvas `measureText` host, both smooth-scroll | hosts | 6 |

Set equality: six-for-six, and no extra criterion rows — the subagent's
"Constraints" block is correctly rendered as non-scored bullets under the
table (the skill's "Constraints are NOT rows" instruction, followed by a
non-author).

Named top feasibility risk: criterion 1, with a structural rationale (wrap
width is a runtime parameter, so cumulative visual-row offsets become a
width-dependent prefix sum; eager recomputation violates criterion 1 while
full per-width memoization violates criterion 2 — no existing prefix-search
hook has faced this). This is the SAME choice as the committed arc file's
risk-first note, so there is no divergence to record as design signal —
the two rationales agree on the mechanism (who owns row data at a width /
what recomputes on change).

Fork markers: two — "FORK A" (sequencing after the y→row node: resize-safe
indexing vs breadth vs gate-first) and "FORK B" (which platform host ships
first). Requirement is "at least one": met. Design signal worth keeping:
FORK B coincides in subject with the committed map's node-8 fork; FORK A is
sequencing signal the committed map absorbs by its linear node ordering
(nodes 2 → 5) — noted for the first live map pass, no action now.

**AC6: PASS** — subject-level set equality (6/6, no extras), a named top
feasibility risk with a defensible rationale, and two fork markers.

## Artifact checks (AC1–AC4)

### AC1 — skill file checks (Task 2)

```
$ sed -n 's/^description: //p' .claude/skills/choosing-next-slice/SKILL.md | grep -nE 'Scoreboard delta|Debt ledger|Falsifiability|Candidate options|checklist|pass(es)?\b|Mode 1|Mode 2'; echo "leak_exit=$?"
leak_exit=1

$ for h in "Scoreboard delta" "Debt ledger delta" "Falsifiability audit" "Candidate options"; do grep -q "^### $h" .claude/skills/choosing-next-slice/SKILL.md && echo "OK: $h" || echo "MISSING: $h"; done
OK: Scoreboard delta
OK: Debt ledger delta
OK: Falsifiability audit
OK: Candidate options
```

No workflow summary leaks into the frontmatter description (the grep found
nothing; `leak_exit=1` is the pass), and all four contract headers are
present as `###` headings.

Bonus discovery evidence (beyond what the plan expected): the
`choosing-next-slice` skill appeared in THIS session's available-skills
listing shortly after the file was created — the plan assumed a file
created mid-session cannot appear in its own session's list and deferred
discovery evidence to the post-slice-review session (which still records
its own, per AC1).

### AC2 — arc file checks (Task 4)

```
$ grep -c '^| [1-6] |' docs/superpowers/arcs/wrap.md
6
$ grep -c '| open | — |' docs/superpowers/arcs/wrap.md
6
$ grep -c 'fork:' docs/superpowers/arcs/wrap.md
1
$ grep -q 'pointOf(line:column:)' docs/superpowers/arcs/wrap.md && echo "decision-log OK"
decision-log OK
```

Six scoreboard rows, all six open with no evidence yet, one `fork:` marker
(node 8), and the decision log carries the wrap-over-`pointOf` entry.

### AC3 — debt ledger checks (Task 5)

```
$ grep -c '^| D-' docs/superpowers/debt-ledger.md
11
$ grep -E '^\| D-' docs/superpowers/debt-ledger.md | awk -F'|' '{print $6}' | grep -vE 'open|scheduled\(slice-[0-9]+\)|discharged\(|deferred\(user, [0-9-]+\)|accepted-risk'; echo "badstatus_exit=$?"
badstatus_exit=1
$ grep -E '^\| D-' docs/superpowers/debt-ledger.md | grep -vE '\[.*\]\(|ruleset config'; echo "unlinked_exit=$?"
unlinked_exit=1
$ grep -n 'from step 1' docs/superpowers/debt-ledger.md; echo "placeholder_exit=$?"
placeholder_exit=1
```

Eleven rows (the plan's template floor is five): every status is from the
legal set, every row cites a linked origin review (or the sanctioned
"ruleset config" source for D-4), and no extraction placeholder survived.

Seeding decisions, recorded for the record (all statements trued against
the review texts, each named file/function re-verified on the current
tree by `grep`/`ls` before seeding):

- The spec's "precheck success state" residual is D-1's fix description,
  not a separate row — slice 47's P2 #1 *is* the precheck-success-state
  item (its Fix line proposes the third state).
- The "cross-target script residuals" slot split into D-3 (retry logfile
  overwrite, slice 47 P3 #6) and D-6 (unpinned shell-purity exemption,
  slice 47 risks table), ids continued sequentially per the plan. Born
  links corrected to the reviews that actually name them: the plan
  template attributed the residuals to the slice 45 review, but the slice
  45 review (realistic-provider gate promotion) contains no cross-target
  script findings — the naming rows are slice 47's (debt stemming from the
  slice 45/46 script work, as D-3's statement records).
- D-7/D-8/D-9 (harvester provenance, bulk-edit absolute backstop, p95 thin
  axis) are the three cross-review P2s carried by the slice 44/45/46
  reviews and dropped silently by slice 47's. Decision 7's operative
  sentence ("re-reads those four reviews and takes what is still real")
  plus its P3-only staleness presumption ("older P3s are presumed stale")
  put them in; after this slice the ledger — not the review chain — is the
  carry mechanism, so leaving still-real P2s out of the seed would orphan
  them. All three verified still real (harvester has no
  conclusion/event/fork check; `BenchmarkMode.isFrameHotPath` still
  excludes `bulk_structural_mutation`; the p95 floor's median-only backup
  term is structural). Note: their origins are ≥ 3 completed slices old,
  so the escalation rule fires for all three at the first live Mode 2 run
  (AC7) — by design, giving the user one consolidated schedule-or-defer
  moment.
- D-10/D-11 are slice 47's own still-real P3s (stale AGENTS.md "see"
  pointer; pin models `name:` only) — from the newest in-bound review, so
  the staleness presumption does not apply.
- Pruned as stale or discharged (spot-verified): slice 46's P3 #3/#4
  (closed by slice 47 Tasks 5–6), the frozen-580 sites (closed by slice 47
  Task 7), and the recurring plan-checkbox / parser-unit-test /
  "contributes 8" P3 tails (not re-observed by the slice 47 review —
  presumed stale per Decision 7; they re-enter only by being
  re-observed).
- NOT pruned — corrected at task review's finding (this bullet originally
  mislisted it as closed): slice 46's P3 #2, the success→drift
  double-install. Slice 47 closed only the failure→failure sibling path;
  its review re-observed the drift path and escalated it to P2 #1, which
  this ledger seeds open as D-1.

### AC4 — AGENTS.md invariant checks (Task 6)

```
$ grep -c 'choosing-next-slice' AGENTS.md
2
$ grep -nE 'Escalation rule|red flag|Risk-first|Debt carry-over' AGENTS.md; echo "dup_exit=$?"
dup_exit=1
```

The invariant names the skill and its path (two mentions); the second grep
finding nothing (`dup_exit=1`) confirms the checklist's internals stayed
out of `AGENTS.md` — pointer-style only, per AC4.

Docs-only surface pre-check (pre-AC8), run after the AGENTS.md edit:

```
$ git diff --name-only origin/main...HEAD | grep -vE '\.md$'; echo "nonmd_exit=$?"
nonmd_exit=1
$ git diff --name-only origin/main...HEAD | grep -E '^\.github/'; echo "policy_exit=$?"
policy_exit=1
```

Every changed path is Markdown and none is under `.github/` — the diff
qualifies for the docs-only fast path on all three required CI contexts.

### Artifact file tree (Task 7)

```
$ ls -la .claude/skills/choosing-next-slice/ docs/superpowers/arcs/ && ls docs/superpowers/debt-ledger.md
.claude/skills/choosing-next-slice/:
total 16
drwxr-xr-x@ 3 aabanschikov  staff    96 Jul 22 16:25 .
drwxr-xr-x@ 3 aabanschikov  staff    96 Jul 22 16:25 ..
-rw-r--r--@ 1 aabanschikov  staff  5026 Jul 22 16:25 SKILL.md

docs/superpowers/arcs/:
total 8
drwxr-xr-x@ 3 aabanschikov  staff    96 Jul 22 16:58 .
drwxr-xr-x@ 8 aabanschikov  staff   256 Jul 22 17:07 ..
-rw-r--r--@ 1 aabanschikov  staff  3570 Jul 22 16:58 wrap.md
docs/superpowers/debt-ledger.md
```

`SKILL.md`, `wrap.md`, and `debt-ledger.md` all present at their contract
paths. A final whole-branch review (most capable model) ran before this
push and returned READY: zero Critical/Important findings; its three
cosmetic notes and the per-task Minor triage live in the session's progress
ledger and the post-slice review picks them up.

## AC8 — PR run evidence

PR: https://github.com/maldrakar/swift-text-engine/pull/112 (PR head
`7f30dfc`). Swift CI run `29929826808` (event `pull_request`), overall
conclusion success in 53s; all three required contexts green:

```
Host tests and benchmark gate | success
iOS cross-target compile | success
WASM cross-target compile | success
```

Step-level docs-only evidence — the executed output line of each required
job's "Complete docs-only PR" step (`gh run view 29929826808 --log`,
filtered to the executed-output lines; the log also carries each step's
`##[group]` header and ANSI command echo, which are Actions echoing the
inline script source, not executed output — the lines below are the
executed ones, timestamp-prefixed):

```
Host tests and benchmark gate	Complete docs-only PR	2026-07-22T14:42:24.8692760Z mode=docs_only_pr job=host-tests-and-benchmark-gate result=success
iOS cross-target compile	Complete docs-only PR	2026-07-22T14:41:59.2939230Z mode=docs_only_pr job=ios-cross-target-compile result=success
WASM cross-target compile	Complete docs-only PR	2026-07-22T14:42:40.1349701Z mode=docs_only_pr job=wasm-cross-target-compile result=success
```

All three required contexts took the docs-only fast path (7s/34s/49s job
durations) — no heavy Swift/test/compile work ran, exactly as the
Markdown-only diff qualifies for.

## Pending after this plan

- AC7 — first live Mode 2 run: produced by the slice 48 post-slice review
  (its own phase, on branch `slice-48-post-slice-review`).
- AC9 — post-merge tree check + push-run note: after the user merges the PR.

## Amendment 2026-07-22 — spec↔skill map-pass ordering resolved

On reviewing the shipped artifacts the user flagged a prose-level discrepancy:
the spec's Mode 2 step list (`## Skill content (normative)`) numbered the **map
pass** as step 4 (after the falsifiability audit), while the shipped
`.claude/skills/choosing-next-slice/SKILL.md` — and both test runs, the AC5
treatment and the AC6 Mode 1 exercise — run the map pass **first**, before the
`### Scoreboard delta` header. The four contract headers of Decision 3
(Scoreboard delta / Debt ledger delta / Falsifiability audit / Candidate
options) appear in identical order under both, so AC7 is satisfied either way:
this was a divergence of the two prose step-lists, not a contract violation.

Resolved by the user in favor of **map-first**, on the rationale that the map is
re-validated against what the slice taught *before* Candidate options reference
where a step sits on it — the options then cite a reconciled map, not a stale
one. The spec's Mode 2 list was amended to lead with the map pass (now step 1),
matching the committed `SKILL.md`; the four contract headers keep their fixed
Decision-3 order as steps 2–5, and Routing stays step 6. No skill, arc, ledger,
or test change — the committed reality already was map-first; only the spec's
prose is brought into line.
