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

<transcript and verdict recorded by Task 2>

## AC6 — Mode 1 executability run

<prompt, transcript, and comparison recorded by Tasks 3–4>

## Artifact checks (AC1–AC4)

<commands and outputs recorded by Tasks 2, 4, 5, 6>

## AC8 — PR run evidence

<recorded by Task 7>

## Pending after this plan

- AC7 — first live Mode 2 run: produced by the slice 48 post-slice review
  (its own phase, on branch `slice-48-post-slice-review`).
- AC9 — post-merge tree check + push-run note: after the user merges the PR.
