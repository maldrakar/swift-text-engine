# Slice 55b — post-slice review (wrap-aware point query; node 4, piece 2)

- **Branch / PRs:** `slice-55b-wrap-point-query` → [#135](https://github.com/maldrakar/swift-text-engine/pull/135) (merge `7390107`); post-merge hosted proof [#136](https://github.com/maldrakar/swift-text-engine/pull/136) (merge `f9ffe58`)
- **Spec:** [`2026-08-24-wrap-point-query-design.md`](../specs/2026-08-24-wrap-point-query-design.md), Contract 55b
- **Plan:** [`2026-09-03-wrap-point-query.md`](../plans/2026-09-03-wrap-point-query.md)
- **Record:** [`2026-09-03-wrap-point-query.md`](../verification/2026-09-03-wrap-point-query.md)
- **Hosted:** PR-head `33790617260` (`04fb75d`), post-merge push `33791182282` (`7390107`), both read at step level; the branch's three earlier heads carry their own green runs (record §7's per-head table)
- **Reviewer note:** every numeric claim below was **re-run**, not re-read — suite (480/0), release build, Foundation scan, `--wrap-point-query` (six checksums byte-identical to the record), `--wrap-row-query` (four byte-identical to 55a), `--memory-shape` (5 × `invariant=pass`), and both hosted runs re-counted at step level with the 46-tuple checksum diff recomputed. Four *new* probes were run for this review and are cited where they matter: a layout-axis probe census, drills (r) and (s), and a round-trip mutation check.

## What shipped

Node 4 proper, on top of merged 55a: `ViewportVirtualizer.visualPointAt(x:y:layout:)`, the
wrap-aware `(x, y) → (visual row, cell)` composite over a **single** `VisualRowLayoutSource`,
plus `VisualPointQuery` / `VisualPointLocation`. Twenty commits, in three phases:

1. **Commits 4–13** — the query and its six test suites, then the observational
   `--wrap-point-query` mode and D-33's completeness pin. Fourteen drill reds.
2. **Commit 17 (`334a94f`)** — the whole-branch review's fix wave: six findings, two of them
   *shipped guards with no recorded red*, drilled as (p) and (q).
3. **Commits 19–20 (`20a8351`, `04fb75d`)** — a pre-merge validation pass against the spec,
   which found two more pins that could not fail on the defect they name; drilled as (r) and
   (s).

**Nineteen recorded reds** in total. **D-25, D-18, D-32 and D-33 discharged**; criterion 3's
last enumerated analog closes.

The engine half is small and, in the end, unamended: `visualPointAt`'s behaviour is unchanged
by phases 2 and 3 — the only `Sources/` edit after phase 1 is a doc comment. That is the
shape the split was drawn for (55a took every shipped-code edit), and it is why the 46 gated
checksums never moved across all twenty.

## Acceptance-criteria status

55b owns sixteen of node 4's nineteen criteria (ACs 10, 17 and 18 are 55a's). All sixteen
close; two carry a recorded deviation and one a deliberate exception.

| AC | Disposition |
|---|---|
| 1 (query exists; `row` verbatim) | Met — the verbatim-`row` sweep covers both clamp edges; drill (g) reddens it there |
| 2 (`x` row-relative, clamps on the row's edges, overflow mid-range `.inRange`) | Met — **strengthened in phase 3**: the overflow run went from one cell to four, so the returned index is pinned and not only the flag; drill (s) |
| 3 (index line-absolute, swept property) | Met — swept on both the ordinary and the FP fixture; drills (e), (k) |
| 4 (∞ oracle, located branch, non-vacuous control) | Met — drill (a); the narrow-width control fails on a genuine `rowSpan` mismatch, not on a non-located branch |
| 5 (55b half — ladder, `±∞` separately, both precedence pairs, three malformed-provider cases) | Met — 17 cases; drills (d1)–(d3), (h), (q) |
| 6 (Decision 6, both fixtures) | Met — both fire; each drill leaves the *other* fixture green, which is what shows neither subsumes the other |
| 7 (probe table) | Met — **strengthened in phase 3**: the in-range layout-axis pin moved to the zero-slack target; drills (i), (r) |
| 8 (round-trip half) | Met — and its falsifiability is established by this review's mutation check, not by an in-slice drill (audit below) |
| 9 (55b half, D-24) | **Deviation** — discharged by assertion, not by drill. I agree with the record's reasoning and go further: the drill is not merely out of scope, it is **unavailable**. `visualPointAt` never calls the row-axis hook; it inherits the dispatch through `visualRowAt`, whose single call site 55a already drilled. A "bypass" drill here would drill 55a's site again |
| 11 (D-25) | Discharged — retargeted, not merely tightened, with the reasoning that a tighter bound at the same target would not have discharged it |
| 12 (`--wrap-point-query`) | Met, with two recorded deviations: the scenario floors were raised so drill (j) can redden, and the checksum folds every *non-duplicated* field (P3 #1) |
| 13 (scan, suite, build, checksums) | Met — re-verified independently this review, locally and on both hosted runs |
| 14 (every standing guarantee carries a red) | Met **after** phases 2 and 3, with one deliberate exception (Decision 6's lower clamp half, unreachable by any conforming provider). The record marks it NOT met as shipped at Task 11 and **does not rewrite that row** — see Strengths |
| 15 (D-18) | Discharged — the `grep -v` filter is in the plan and the record; no `${PIPESTATUS[0]}` in either except as prose forbidding it (verified: 5 occurrences, all prohibitions) |
| 16 (hosted, both runs, step level) | Closed, both halves — 46 `gate=pass` / 0 `gate=fail`, 480/0, 4 + 4 blocking compile lines, no step concluding anything but success or skipped, checksum diff empty on both |
| 19 (D-33) | Discharged — both halves pinned, drills (n) and (o), each leaving the sibling guard green |

## Strengths

**The composition is a composition, and the pins say so.** The family rule "adds no search"
is easy to claim and hard to keep: it fails silently the moment someone re-derives the
vertical half inside the query. Three of this slice's pins exist specifically because
*nothing else would notice* — the verbatim-`row` sweep (the oracle compares against
`pointAt`, the round trip against the cursor, the counters count probes; all three stay green
under a re-derivation), the zero-column-probe assertion (the only observation of the `x`
rung's placement rather than its result), and the exact `3 + 2` / `3 + 2 + 1` counts, which
are what pin Decision 13 as *bought* and Decisions 12 and 14 as *free*. Each has a drill, and
drill (h) is the model: it reddens the placement pin while the `±∞` result tests stay green.

**Asymmetric drills are now the house style, and they earn it.** Six of the nineteen reds
are asymmetric — (f1)/(f3) and (f4) in 55a, (k) vs (e), (n)/(o), (p), (r), (s) — and in every
case the *green* half carries the information. Drill (s) is the clearest: the mutation
reddens the four-cell fixture and leaves the one-cell fixture green, which is not a
restatement of the fix but the proof that the old fixture was measuring nothing about the
index. A symmetric drill would have shown only that the mutation is detectable somewhere.

**The record does not launder its own history.** AC14's row says the criterion was **not met
as shipped at Task 11**, names the two guards that survived deletion, and adds "this row is
not rewritten into having always been met." §9 carries nine deviations, including one
(item 3) that retracts a false claim the *spec* made and that the plan repeated at two sites.
A record that reports its own misses in the tense they happened is worth more than a clean
one, and this repo's whole method depends on that being true.

**The benchmark mode measures the term it would be tempting to hide.** `long_line_deep_row`
exists to expose the within-line walk — the query's only non-logarithmic term — and it is
protected against the specific way such a scenario decays: the parameter floors are pinned
(drill (j) reddens on a halved line), `operationsPerSample` is per-scenario so the scenario
cannot be silently shortened to keep the runtime down, and `fast_path=` is *printed* rather
than inferred because `rows_per_line == 1` does not imply it. Locally it costs ~20-30× its
logarithmic siblings, which is the number node 6 needs to see before it derives a budget.

**One source for both axes retires a standing precondition.** Because
`VisualRowLayoutSource` refines `WrapMetricsSource` refines `LineHorizontalMetricsSource`,
`pointAt`'s "the two sources must describe the same document" precondition simply does not
exist for `visualPointAt`. That is a genuine simplification over the no-wrap sibling, not a
restatement of it.

## Issues

### P0 / P1

**None.** No correctness defect in `visualPointAt` was found by the whole-branch review, by
the pre-merge validation pass, or by this review's independent probes. The ladder implements
Contract 55b step for step, the guards are inherited rather than re-checked, and the failure
orderings match Decision 5 including both structural precedence pairs.

### P2 #1 — the drill list is a closed set in the Contract, and AC14 says "every standing guarantee"; when they disagree, the closed set wins

AC14 reads: *"Every standing guarantee this slice adds carries a **recorded red** … A
guarantee whose drill is missing is an unfinished acceptance criterion, not a review
finding."* Contract 55b, meanwhile, enumerates the drills as a list of twelve (plus AC19's
two). The two disagree the moment the slice adds a guarantee the Contract did not foresee —
and in this slice it happened **four times**:

- **(p)** Decision 14's `>= total` *answer* — the fixture could not separate the guard's
  answer from a plausible wrong one. Found by the whole-branch review.
- **(q)** step 7's `!rebased.isFinite` guard — no test at all. Found by the whole-branch
  review.
- **(r)** the layout-axis bound's *target* — 13 probes against a bound of 14. Found by the
  pre-merge validation pass.
- **(s)** the overflow fixture's inability to separate the index. Found by the same pass.

And once *actively*: the record's §9 item 5 discharges AC9's 55b half without a drill and
cites the closed list as the reason — "Contract 55b's drill list (the authoritative
distribution across the plan's tasks) is the twelve named there and carries no dispatch-bypass
drill." The closed list did not merely fail to require a drill; it was quoted as the authority
for not writing one. (In that particular case the outcome is right for an independent reason —
the drill is unavailable, see the AC table — but the *reasoning* is the defect.)

**Why this keeps happening, stated as a mechanism rather than a lapse.** TDD writes a test
red-first when the test *specifies* behaviour. A cost pin, a probe-count bound, a fixture that
must separate two indices — these **measure** the implementation rather than specify it, so
they are written against working code and are green from birth. Nothing in the workflow forces
the question *"can this pin fail?"* at the moment it is written; the question is asked later,
by a reviewer, and how thoroughly depends on who reads. Four escapes in one slice, caught by
two different late passes, is the measurement.

**Proposed fix** (a candidate option below, not a decision here): make the **guarantee
inventory** the authority and the Contract's drill list a *lower bound*. Concretely — at plan
time, each task enumerates the standing guarantees it adds, and every one gets a drill step in
the same task; the spec's list stays as the *cross-task* distribution it is good at, and stops
being read as exhaustive. The cost is a plan-authoring step; the alternative is a third
consecutive slice where the drills are completed by whoever reviews last.

Severity P2 rather than P3 because it is a governance defect with a measured recurrence,
because two of the four escapes were **shipped guards with no coverage at all**, and because
it is the same shape as D-34 (D-2's plan conventions are documentation, not enforcement) —
which is scheduled for slice 56 and is the natural place to answer both.

### P3 #1 — AC12's "every returned field" ships as "every non-duplicated field"

`wrapPointQueryChecksum` folds eight fields and deliberately omits `rowSpan.logicalLine` and
`rowSpan.rowInLine`, which duplicate `row.logicalLine` / `row.rowInLine`. The reasoning is
sound and pinned elsewhere (`testRowSpanAndRowAgreeOnTheirDuplicatedFields`), and the record
now carries it as §9 item 9 after this review raised it — but the criterion's literal wording
is narrowed and folding the two would move the printed checksum, which §6's byte-identity
comparison leans on. The right moment to fold them is when node 6 re-baselines this mode's
line anyway. Ledger **D-36**.

### P3 #2 — a verification record cannot carry facts about its own branch, and the convention that solves it is still oral

This slice's record stated a commit count (wrong twice: "fifteen", then "seventeen", against
an actual 20) and called a hosted run "the current HEAD" (false two commits later, because
§7's own fill-in moved the head). Both are now fixed — the record carries a **per-head table**
and the count is phrased as "nineteen by SHA plus this one" — and the post-merge proof landed
on a **separate branch** (`slice-55b-hosted-proof`), the same shape slices 54 and 55a used.

That is a working convention with three instances and **zero written statement**: 55a's review
raised the same thing as its P3 #4 ("a verification record cannot name its own hosted run, and
the repo has no convention for it") and it was never laddered into the ledger, so it recurred
one slice later. `AGENTS.md`'s workflow section says verification records anchor proof in the
post-merge run; it does not say the proof lands on its own branch, nor that self-referential
counts belong in a re-checkable form. Ledger **D-37**, with the cheap fix named: three lines
in `AGENTS.md`.

### P3 #3 — one derived quantity in the count suite is still hand-computed

`WrapPointQueryCountTests`' growth bound uses `let mustScan = 55 - 15`, transcribed from the
fixture's advances rather than derived from the test's own `near`/`far` variables. Correct
today; a latent transcription risk if the fixture changes. The record already lists it (§9
item 6) with no ledger row. Ledger **D-38**. Note that the *sibling* defect in the same file —
a fixture guard written as a comparison of two constants — was already caught and fixed during
Task 5, which is what makes this one worth carrying rather than dismissing.

### Process observations

- **The slice needed three correction waves after it was "done"**, and all three found the
  same class (P2 #1). The waves worked — nothing defective merged — but each was discovered by
  a *different* late reader, which is precisely the property a standing check exists to remove.
- **The 55a→55b split delivered what it promised.** 55b touches no shipped measured path, and
  that claim was checkable rather than assertable: `--wrap-compute` and `--wrap-row-query`
  checksums are byte-identical to 55a's, and the 46 gated tuples never moved across twenty
  commits and four hosted heads. A "repairs vs feature" cut would not have supported that.
- **Two ledger rows were structurally broken, and one of them was D-9.** Writing a script to
  re-derive this review's open counts (rather than reading them) surfaced it: GFM does **not**
  protect a pipe inside a code span in a table, so D-9's `gov_p95=median|max` and D-27's two
  `|| true` spans split those rows into 7 and 10 cells instead of 6. The consequence is not
  cosmetic — D-9's **status** column rendered as ``max` per scenario)…`` instead of
  `scheduled(slice-56)`, i.e. the exact column the escalation rule reads, wrong on the exact
  row that has been surfacing for nine slices. Both are repaired in this review's ledger
  commit, and **D-39** carries the missing guard (a one-line invariant: every `| D-` row has
  six unescaped pipes). The general lesson is the one this arc keeps relearning from the other
  side: *derive the number, do not read it* — the skill's own instruction to re-derive counts
  from the file is what found a defect that reading had passed over for nine slices.

# Recommendation (skill Mode 2)

Map pass first (its output is the updated arc file, and this pass owes three items the spec
names by hand): node 4 is marked **`done`** — consumed by two slices, *planned* rather than
discovered, so 55a's "no map node" is not the shape of slices 48/51/52/54. The **within-line
random-access provider seam** goes back on the map as **fork R** with a *numeric* trigger
(node 2's spec had assigned it to node 7 and the map entry dropped the clause). Criterion 3's
evidence cell states the oracle's **scoping** rather than an unqualified "bit-identical".
Nodes 5-9 and fork V stand unrevised — nothing 55b taught touches them. Next step is
**topological**, and the immediate slot is already spoken for by a user call (below).

### Scoreboard delta

**Criterion 3: `partial` → `done`.** Its own list enumerates three wrap-aware query analogs
plus the equivalence oracle; node 2 shipped compute-over-visual-rows, node 3 shipped y→row,
and this slice ships point→(row, cell) with its oracle. The no-wrap path is untouched (46
gated checksums byte-identical across the whole branch). Evidence:
[PR #135](https://github.com/maldrakar/swift-text-engine/pull/135) (`7390107`),
`WrapPointQueryEquivalenceTests`, post-merge run `33791182282`.

**The evidence cell states what was proven, not more.** The brief's «wrap-путь при
бесконечной ширине укладки обязан совпадать с ним» is unqualified; what nodes 3 and 4 prove is
bit-identity **on the located branch**, with the failure orderings deliberately divergent
(the wrap and no-wrap ladders validate different things in different orders). The cell now
says so for both analogs — flipping the criterion to `done` is right, and the caveat travels
with it rather than being discovered by whoever reads it next.

**Still open or partial:** criterion 1 (`partial` — core half retired, `done` gated on the
Ω(N) veneer, fork V), criterion 2 (`open`, no evidence at all), criterion 4 (`open`),
criterion 5 (`open`), criterion 6 (`open`).

### Debt ledger delta

**Discharged (4):** **D-25** (retargeted to the in-range worst case, row 1 022, where the
bound has zero slack — a tightened bound at the old target would not have discharged it),
**D-18** (the `grep -v` filter, written into the plan and used in both hosted checksum
extractions), **D-32** (the shared walk's second call site now exists, and the round trip
drives both — discharged as *observability*, explicitly not as enforcement, with the green
probe recorded), **D-33** (both halves of the `wrap_compute` checksum pinned, drills (n) and
(o)). All four discharge links now point at the **verification record** rather than the plan:
a plan is a promise, a record is evidence.

**New (5):** **D-35** (P2 — the Contract's drill list is a closed set while AC14 says "every
standing guarantee"; four escapes in one slice, one of them citing the list as authority),
**D-36** (P3 — the `wrap_point_query` checksum omits two duplicated fields; fold them when
node 6 re-baselines the line), **D-37** (P3 — the "record cannot carry facts about its own
branch" convention is unwritten; second instance, first was 55a's P3 #4 which was never
laddered), **D-38** (P3 — one hand-computed literal in the count suite), **D-39** (P3 — two ledger rows
broke the table's own structure, one of them in the status column of the most-escalated row;
repaired here, with no guard against recurrence).

**Counts (re-derived from the file with a parser that honours `\|`, not remembered):** 39
rows — **14** discharged, 3 accepted-risk, 1 `deferred(user)`, 4 `scheduled(slice-56)`, **17**
open (16 P3 + D-35). The four discharges above move rows from open to discharged, so the
discharged count rises 10 → 14 against 55a's; the open count falls 19 → 17 despite five new
rows.

**Escalation (rule: an open P2 whose origin is ≥ 3 completed slices ago MUST appear under
Candidate options):** **none forced, and that is a first for this arc.** All four P2s that
were aging — D-9 (born slice 46, nine slices), D-17 (slice 52), D-27 (slice 54), D-34 (slice
55a) — carry `scheduled(slice-56)` from the user's call of 2026-09-03, so silence is not their
state and the rule is satisfied by the schedule rather than by a fifth surfacing. The one new
P2, D-35, is one slice old and does not force; it appears below as a fold-in candidate on its
merits, which is where the skill wants a young P2.

### Falsifiability audit

Standing guarantees this slice **added or changed**, each with evidence it can fail:

| Guarantee | Evidence it can fail |
|---|---|
| `visualPointAt`'s ladder and its inherited guards | Reds (d1), (d2), (d3), (h), (q) — each removal traps or fabricates, and (d1)'s composite half shows the trap-freedom is *inherited*, not re-derived |
| The infinite-width oracle (criterion 3's evidence) | Red (a); plus a narrow-width control asserting the equivalence **fails** there, so the oracle is not vacuously true |
| The verbatim-`row` promise | Red (g), at the clamp edges — a fabricated location gets the index right and the flag wrong |
| Decision 6's clamp and Decision 14's `>= total` guard | Reds (e), (k), (p) — mutually asymmetric: each reddens one fixture and leaves the other green |
| The probe table (layout axis, column axis, growth) | Reds (i) and (r). (r) is new this review: one gratuitous layout-axis probe reddens the retargeted pin (2 failures) and does **not** redden the row-700 form (1 failure, and not that test) |
| The overflow row's index (AC2) | Red (s), new this review: dropping the hook dispatch reddens the four-cell fixture and leaves the shipped one-cell fixture green |
| `--wrap-point-query`'s line shape, floors and checksum | Reds (b), (c), (j) |
| D-33's two `wrap_compute` pins | Reds (n) and (o), each leaving the sibling guard green |
| **The round-trip agreement (AC8's half)** | **No in-slice drill** — the Contract's list carries none, and §8's recorded probe is the *green* one (an inline-walk revert leaves it green, which is D-32's honest residual, not a red). **Mutation check run for this review**: `advanceVisualRows(&cursor, by: row.rowInLine + 1)` → `+ 2` gives `Executed 1 test, with 18 failures`. The guarantee is falsifiable; what it does not do is enforce the shared-helper property, exactly as D-32 states |
| `isGateable == false`, `absoluteCeiling == .scrollFrame` | Pins on constants: they fail only if the constant changes. Inert until node 6 makes a wrap mode gateable — the D-20/D-21 class, already on node 6's reading list. No new option |

**Mandatory candidate options spawned: none.** Every guarantee above has a red or a mutation
check, and the single guarantee deliberately without one — Decision 6's lower `max` clamp — is
unreachable by any conforming provider, which the source comment and the record both state.
That is an argued exception, not a gap. But note *how* this audit came out clean: two of the
rows above were filled by drills written after the branch was declared done, and one by a
mutation run during this review. That is P2 #1's evidence, restated as a scoreboard.

### Candidate options

**Option A — Slice 56 = the infrastructure slice, as already called (the lean, and already the
user's selection).** D-27 (ten of twelve gate steps have unpinned shape) + D-34 (D-2's plan
conventions unenforced) + D-17 (`${PIPESTATUS[0]}` inverts under zsh) + D-9 (the p95 thin
axis). *Criteria:* none directly — but three of the four are preconditions for **node 6**
(criterion 4), whose reading list is already five rows long and which cannot be repaired after
its first harvest. *Ledger:* discharges four scheduled P2s; **folds in D-35** naturally, since
D-34 and D-35 are the same defect on two artifacts (plan conventions and drill lists are both
documentation that nothing enforces), plus **D-39** beside D-27 (both are "an artifact whose
shape nothing verifies", and D-39's guard is a one-liner) and **D-37** (three lines in
`AGENTS.md`) for free. *Map:* consumes no node.

**Option B — node 5, `--memory-shape` extended to the wrap path.** *Criteria:* criterion 2,
the only wrap criterion with **no evidence at all**, and one of the brief's five hard
constraints. *Ledger:* discharges nothing scheduled. *Map:* node 5, topological, and the
slice-53 review's sequencing argument now applies in its favour — `--memory-shape` should be
extended **once**, over a complete wrap query surface, and as of this slice that surface is
complete. *Against:* it would defer four scheduled P2s a sixth time, and D-27/D-34 are exactly
the kind of item that ages into never.

**Option C — node 6, wrap gate promotion.** *Criteria:* criterion 4. *Against:* premature.
Its precondition set is five ledger rows (D-20/D-21, D-28, D-30, D-31) plus the four scheduled
P2s, and `harvest → derive` never re-measures — the whole point of reading that set *before*
the first harvest. Option A is the slice that shortens this list.

**Route: topological, and the slot is already assigned.** This is **not** a fork — the arc's
genuine forks remain node 8 (host order) and fork V (the width-change veneer), and neither is
in reach. Slice 56 was selected by the user on 2026-09-03 at this slice's own selection, and
nothing 55b taught argues against it: the audit's clean result was bought by two late correction
waves, which is the argument *for* spending a slice on enforcement rather than against it.
**Lean and selection: Option A**, with D-35 and D-37 folded in on the reasoning above.
**Node 5 (criterion 2) is the next feature node**, and after two consecutive infrastructure
slices the arc should not take a third — the skill's own red flag about a criterion staying
open for ten slices applies to criterion 2, which has been `open` with zero evidence since the
arc began.
