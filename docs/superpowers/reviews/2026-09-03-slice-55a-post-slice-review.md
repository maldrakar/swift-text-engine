# Slice 55a — post-slice review (wrap trap repairs; node 4, piece 1)

- **Branch / PRs:** `slice-55a-wrap-trap-repairs` → [#132](https://github.com/maldrakar/swift-text-engine/pull/132) (merge `ccbd13e`); post-merge hosted proof [#133](https://github.com/maldrakar/swift-text-engine/pull/133) (merge `6bf875a`)
- **Spec:** [`2026-08-24-wrap-point-query-design.md`](../specs/2026-08-24-wrap-point-query-design.md), Contract 55a
- **Plan:** [`2026-08-28-wrap-point-query-trap-repairs.md`](../plans/2026-08-28-wrap-point-query-trap-repairs.md)
- **Record:** [`2026-08-28-wrap-point-query-trap-repairs.md`](../verification/2026-08-28-wrap-point-query-trap-repairs.md)
- **Hosted:** PR-head `33682449259` (`21e4d5a`), post-merge push `33683089074` (`ccbd13e`), both read at step level
- **Reviewer note:** every numeric claim below was **re-run**, not re-read — suite, release build, Foundation scan, twelve gates, both wrap modes, `--memory-shape`, and drill (m) reproduced independently at `d977248`.

## What shipped

The first of node 4's two pieces: the shipped wrap layer repaired and made cheaper, with
**no new public API**. Seven contracted commits in the mandated order, plus one in-slice
`docs:` correction and the two documentation commits:

1. `a8c957a` — the `wrap_compute` line prints `checksum=`, the printer only, **before** any
   measured-path edit. Ordering is the whole point: a token added later would be
   byte-identical only across the columns that have it.
2. `7512e0d` — the within-line walk extracted to `advanceVisualRows(_:by:)` (`inout`, k-th
   `next()` result, `k <= 0 → nil`), and `DocumentVisualRowCursor.init` gains its two guards.
3. `ebd5659` — `visualRowAt` rejects an out-of-range `logicalLine` and a negative `rowInLine`
   with `.failure(.invalidVisualRowLayout)` instead of trapping.
4. `0235e73` — the per-line ladder extracted to `validateWrapLine`; the cursor stores `total`.
5. `a2007cc` — `greedyEnd`'s suffix-fits short-circuit, red-first.
6. `f143e96` — the review-driven narrowing: the last row is O(1) **unless it overflows**.
7. `c384f7b` — the `--wrap-compute` drain body becomes `drainVisualRows` (D-29).
8. `58b78f4` — `VisualRowDispatchTests`, D-24's dispatch pin, **after** the guards.
9. `21e4d5a` — the pre-merge validation pass (five documentation defects, D-31, D-32).

Five producer guards, two behaviour-preserving extractions shared with 55b, one packer
short-circuit, nine recorded drill reds. **D-24 and D-29 discharged.**

## Acceptance-criteria status

55a owns nine of node 4's eighteen criteria; all nine close.

| AC | Disposition |
|---|---|
| 5 (55a half) | Met — four cases in `WrapRowQueryValidationTests`, four reds before the guards |
| 8 | Met — one shared `inout` helper, five guards, five reds ((d1), (f1)–(f4)) |
| 9 (D-24) | Discharged — both dispatch sites drilled, `[] != [5]` |
| 10 (D-29) | Discharged — zero `firstVisualRow(ofLine: lineCount)` probes with a non-vacuous witness; a `compute` in the body gives `1 != 0` |
| 13 | Met — Foundation scan empty, 425/0, release build green, 46 gated checksums byte-identical. **Re-verified this review**: the 46-tuple diff is empty against the local run, the PR-head run and the push run |
| 14 | Met — nine reds, each with its observed line |
| 16 | **Closed, both halves** — `33682449259` and `33683089074`, step level, 46 `gate=pass` / 0 `gate=fail`, 425/0, 4 + 4 blocking compile lines, one step per mode |
| 17 (Decision 12) | Taken — see P3 #3 on how its benchmark half should be read |
| 18 (Decision 13) | Taken — the five named suites pass unedited; both wrap modes' checksums byte-identical across both extractions |

## Strengths

**The commit order was load-bearing and it held.** D-24's overriding conformer is what makes
the malformed-override category *live*; landing it before the guards would have put a test
driving a lie against an unguarded consumer into the tree. The spec named this and the
execution respected it — commit 6, after commits 1–2, with the conformer used against only
the consumer each commit guards.

**The cost claim got a positive pin, not a comment.** The plausible regression here —
narrowing the short-circuit to `start == 0` — preserves every row, every checksum and every
result test while making the `AGENTS.md` sentence false. `WrapPackingCountTests` reads it
through a counting `WrapMetricsSource` and is the only thing that can. I re-ran drill (m)
independently at `d977248`: exactly **one** red out of 425, and it is that pin. That is the
shape a cost claim should ship in.

**The slice corrected its own spec mid-flight, at the boundary that mattered.** Task 5's
review produced a counter-example to "the last row of every line packs in O(1)": on a line
whose tail is an unbreakable run wider than the width, the suffix test does not fire on the
last row either, and the scan falls to the forced-overflow fallback. The narrowing is not
hedging — it is exactly right, and provably so: if a row's suffix does not fit, the scan
cannot return `columnCount` via `lastFitting`, so a last row that does not short-circuit
**is** an overflow row. Eight normative sites now carry the qualifier.

**The guards land at the producers, and the three channels answer differently on purpose.**
`visualRowAt` has a failure channel and uses it; the cursor has none and takes the terminal
state it already holds; `compute` never consults the hook and accepts the layout. Three
answers, each correct for what that entry point can observe — and the design says so rather
than papering the divergence over.

**The record reports what it measured, including the parts that contradicted the
prediction.** `reindex_ns`'s predicted cross-width ordering came out broken and `compute_*`
moved in both directions depending on the baseline; every one is written down with its ratio,
no band was widened, and no run was repeated to obtain a better number. That is the reason
D-31 could be written at all.

## Issues

### P0 / P1

None. The engine behaviour is correct, the guards are reachable only through overrides the
default hook cannot produce, and no shipped result changed anywhere — 46 gated checksums,
three `--wrap-compute` checksums and four `--wrap-row-query` checksums are byte-identical
across the whole branch and across three machines.

### P2 #1 — the one witness Decisions 12 and 13 rest on has no completeness pin and no red

Both decisions are result-preserving by construction, so neither adds a result assertion. What
covers them is (a) that a wrong version reddens the existing suite, and (b) the `checksum=`
token folded over 100 000 lines at three widths — the spec's own words, "a result-preservation
check on a fixture no unit test reaches".

`WrapBenchmarkLineShapeTests` pins that the token is **printed** with the value
`formatWrapComputeLine` was handed (`987654`). Nothing pins the fold. The value is
`computeMeasured.checksum &+ drainMeasured.checksum`; zero the drain half — the half that folds
every drained row's `endColumn`, i.e. the half that witnesses **packing** — and the token still
prints a stable number, byte-identical across every column of the record, while every claim
built on that byte-identity becomes vacuous.

Both sibling checksums in the same test target already close this hole.
`WrapRowQueryChecksumTests` asserts each folded index affects the value;
`PointGeometryChecksumTests` exists, per `AGENTS.md`, precisely so "a zeroed multiplier or a
reversion to an additive index-only fold cannot pass silently". The wrap-compute token is the
odd one out and it is the one carrying the most weight.

Ledger **D-33**. **MANDATORY candidate option** under the falsifiability rule. Fix is one
sibling file, no shipped-code change.

### P2 #2 — D-2's conventions are documentation, not enforcement, and this slice measured it

D-2 was discharged in slice 51 by writing four plan-assertion rules into `AGENTS.md`. Slice
55a's plan was written after that discharge, was smoke-tested, and carried an explicit
assertion audit in its own preamble. It still shipped **four** defective checks, all found at
execution time and all recorded in the verification record: the `HITS` regex that could not
pass; the `REVERTED TOO FAR` check that is inverted under the commit-first ordering the plan
itself permits; the WASM `blocking=true` count that is not job-scoped and reads the iOS job's
lines too; and `predict.py`'s scenario variable, never rebound inside the loop its checks are
indented into, so nine reported lines are `width_10` evaluated three times and the `width_inf`
and `width_40` verdicts the record needed were never computed by it.

Three are the class D-2 names. The fourth extends it from shell to plan-supplied analysis
code, which D-2's rules do not mention. Two honest readings — four per plan is the irreducible
rate for hand-written checks, or the conventions need a mechanical pass that *executes* each
assertion against a known-bad tree and requires a red — and the ledger takes the second.
Related and unresolved: **D-17**, the `${PIPESTATUS[0]}` idiom rule 1 still recommends by name,
which inverts to a pass under this repo's zsh.

Ledger **D-34**.

### P3 #1 — `--wrap-compute`'s local columns cannot resolve the effect they were used to check

Two measurements of the *same* commit (`0235e73`, columns C3 and C3b) moved on all fifteen
tokens, up to **2.84x**. A third measurement at `d977248` during this review read `width_inf
reindex_ns` 5 927 042 against column C5's 11 923 958 — another 2x on an unchanged tree. Node 6
promotes wrap modes through `harvest -> derive`, which never re-measures. Ledger **D-31**
(opened in-slice).

### P3 #2 — the shared walk is pinned by its rule, not by its call site

Reverting `DocumentVisualRowCursor.init` to the inline `for _ in 0..<rowInStartLine` loop
leaves all 425 tests green: with guard 4 live the two forms are behaviourally identical, and
the "by construction" property the extraction exists for is silently gone. Fifth instance of
the class the ledger carries in D-24, D-27 and D-26(b). No cheap repair exists at the 55a
boundary — the property is unobservable until a second caller exists. Ledger **D-32**,
scheduled to 55b.

### P3 #3 — AC17 makes a prediction and does not say what a falsified prediction costs

"…`reindex_ns` and `drain_*` moving as predicted … with any other outcome a finding" reads two
ways: a deviation must be *recorded* (the slice's reading, and the one the record executed
faithfully), or a deviation means the criterion is **not met**. Under the first reading an
acceptance criterion can be discharged while the prediction it names is falsified, which is
what happened: the `reindex_ns` ordering broke and `compute_*` was not flat. Decision 12
survives on `WrapPackingCountTests` — the stronger evidence — so nothing is wrong with the
slice; what is wrong is that the criterion cannot distinguish "confirmed" from "recorded as
contradicted". Any future AC that names a predicted direction should say which one it is.

### P3 #4 — a verification record cannot name its own hosted run, and the repo has no convention for it

Slice 55a hit this twice. §7 named one PR-head run and the branch went on to have four; the
final PR-head run could only be recorded by the *next* commit, in the post-merge proof. Both
were repaired here (an inventory table plus a row filled after merge), but the shape is
generic: every hosted-proof section in this repo has it, and the failure mode is a reader
sent to a run that is not the head. The convention that works is the one this slice ended up
inventing — name the run that covers the last code-bearing commit, list the rest, and let the
post-merge proof close the table.

### Process observations

- **The record was written and checked by the same pass.** Five documentation defects survived
  the plan's own audit, the record's authoring and a recorded hosted proof, and were found
  only when a separate pass re-ran every claim. Cheap and worth institutionalising: the
  re-run cost about twenty minutes of machine time and found a stale run id, a stale HEAD, two
  false `AGENTS.md` claims and an arithmetic error.
- **Nine drill reds, all with their observed output.** Four are traps, so each was run alone
  under `--filter`; the record says so, which is what makes the count readable.
- **The split behaved as designed.** 55a is a repair slice that consumes no map node — planned,
  not discovered. The cost the spec predicted (a second full merge cycle for the heavier half)
  is exactly what was paid.

# Recommendation (skill Mode 2)

Map pass written to [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md) (2026-09-03): node 4
stays `pending` — 55a consumed no node **by design**; nodes 5–9 and fork V unrevised; next
step **topological**, not a fork.

### Scoreboard delta

No criterion status changed, and that was the plan of record rather than drift: the slice-55
design splits node 4 so that **55b** marks it `done`. Half a split is the one outcome the
design rejects.

| # | Criterion | Status | Change |
|---|---|---|---|
| 1 | Width change does not recompute the document | partial | unchanged — `done` needs fork V (Ω(N) veneer) |
| 2 | Core memory not linear with wrap on; `--memory-shape` extended | open | unchanged — node 5 |
| 3 | Wrap-aware query analogs + ∞ oracle | **partial** | unchanged; 55a repaired the analogs already shipped and made node 1's packer cheaper, but shipped no new analog. **55b closes it** |
| 4 | Wrap modes as blocking gates under the ceiling | open | unchanged — but node 6's reading list grew to five rows (D-20/D-21, D-28, D-30, and now D-31, D-33) |
| 5 | Incremental edits under wrap | open | unchanged |
| 6 | Thin iOS / browser verification hosts | open | unchanged |

Still open or partial: **all six**. Criterion 3 is one slice from `done`.

### Debt ledger delta

**Discharged (2):** D-24 — `VisualRowDispatchTests` pins one dispatch per `visualRowAt` (in
range and at both clamp edges) and one per `DocumentVisualRowCursor`, both sites drilled.
D-29 — `WrapComputeDrainTests` asserts zero `firstVisualRow(ofLine: lineCount)` probes across
`drainVisualRows` with a witness call proving the probe exists to be counted.

**New (4):** D-31 (P3, host variance on `--wrap-compute`) and D-32 (P3, unpinned walk call
site, `scheduled(slice-55b)`) were opened in-slice by the pre-merge validation pass; **D-33**
(P2, the wrap-compute checksum has no completeness pin — MANDATORY) and **D-34** (P2, D-2's
conventions are unenforced) are opened by this review.

**Counts (re-derived from the file, not remembered):** 34 rows — **10** discharged, 3
accepted-risk, 1 `deferred(user)`, 1 `scheduled`, **19** open. P2s needing a decision:
**D-17, D-27, D-33, D-34** open, plus **D-9**, whose formal status is `deferred(user,
2026-08-23)` while its own statement says the thin-axis half "stays **open**" — the
discrepancy is why it keeps surfacing and why it needs closing one way or the other.

**Escalation (rule: an open P2 whose origin is ≥ 3 completed slices ago MUST appear under
Candidate options):**

- **D-9** — born slice 46, **nine** completed slices ago, `deferred(user, 2026-08-23)` and
  already re-affirmed twice. Its own row says the next review must "schedule it or state why
  the observable is a permanent substitute for a fix". **Third consecutive surfacing; it needs
  a decision, not a fourth deferral.**
- **D-17** — born slice 52, three completed slices ago; the slice-55 design mandates its
  escalation **at this review** by name. It is the rule `AGENTS.md` itself still recommends
  and which inverts to a pass under this repo's shell, and P2 #2 shows the surrounding
  convention is unenforced too.
- **D-27** — born slice 54, one completed slice ago, so the age rule does not force it; the
  spec instructs this review to carry it and the row's own text says "schedule by slice 56
  rather than aging it". Ten of twelve blocking gate steps still have unpinned shape.

### Falsifiability audit

Standing guarantees this slice added or changed, and the evidence each can fail:

| Guarantee | Evidence it can fail |
|---|---|
| `WrapPackingCountTests` — the two O(1) packing cases | Red-first on the shipped packer (`7 != 0`, `12 != 4`, `3 != 0`); drill (m) reddens **only** this pin. **Independently reproduced this review**: one red out of 425 |
| `WrapRowQueryValidationTests` +4 — `visualRowAt` guards 1–2 | Four reds: two traps (`Index out of range`), two `.row(…)` mismatches; drills (d1), (f4) |
| `WrapComputeTests` +2 — cursor guards 3–4 | Two trap reds (`Index out of range`, `Range requires lowerBound <= upperBound`); drills (f1), (f2). (f1) also pins the *plausible wrong answer* — streaming line 2 from row 0 |
| `VisualRowWalkHelperTests` — the helper's `k <= 0` rule | Compile red before the helper existed; drill (f3) restores the raw loop and traps |
| `VisualRowDispatchTests` — D-24 | Both dispatch sites drilled: `[] != [5]`, and `[] != [0]` / `[] != [7]` at the clamp edges |
| `WrapComputeDrainTests` — D-29 | A `compute` inserted in the body gives `1 != 0`, with a witness call proving the probe is counted |
| `WrapBenchmarkLineShapeTests` — the `checksum=` token case | Red-first at commit 0 (the token did not exist) |
| **`--wrap-compute`'s `checksum=` as a result-preservation witness** | **NONE.** No red, no completeness pin. Drill (l) reddens unit tests, not this token; the value stayed byte-identical in all seven columns and in this review's own run, which is exactly what a zeroed half would also produce → **MANDATORY option (D-33)** |
| The `AGENTS.md` cost sentence (node 1 and node 2 paragraphs) | Read by `WrapPackingCountTests` — the only prose claim in this slice with a test behind it |

One guarantee out of nine has no recorded red, and it is the one two ratified decisions lean on.

### Candidate options

**Option A — 55b: node 4 proper (`visualPointAt(x:y:layout:)`).**
*Criteria:* closes criterion 3 (`partial → done`) — its last enumerated analog.
*Ledger:* discharges D-25 and D-18; discharges D-32 (scheduled there); natural home for
**D-33**, which is one test file beside the two the spec already has 55b adding (Decision 10).
*Map:* node 4, marked `done` by this piece.
*Trade-off:* it is the heavier half — new public API, twelve drill reds, a new benchmark mode,
its own portability evidence — and it leaves five open P2s untouched, two of them newly
opened by this review.

**Option B — the infrastructure slice: D-27 + D-34 + D-17 (+ D-33).**
*Criteria:* advances none directly; repairs node 6's preconditions and the plan machinery every
future slice runs on.
*Ledger:* discharges the three escalated P2s and folds in D-33.
*Map:* consumes no node — the shape of slices 48, 51, 52 and 54.
*Trade-off:* it would be the **sixth** slice of that shape and would leave the ratified 55a/55b
split half-finished across two more merge cycles, with 55a's two single-caller helpers
(`validateWrapLine`, `advanceVisualRows`) sitting in the tree with one production caller each.
That is the configuration the design warns against.

**Option C — 55b with D-33 folded in, and the infrastructure slice scheduled as 56.**
*Criteria:* criterion 3 → `done`.
*Ledger:* A's discharges plus D-33; D-27, D-34 and D-17 scheduled rather than aged, which is
what D-27's own row asks for by name.
*Map:* node 4 `done`; slice 56 consumes no node.
*Trade-off:* D-9 still needs a call this review either way — it cannot ride on a schedule.

**Lean and selection: Option C.** The next step is topological, the split is ratified, and
finishing it is worth more than any of the three escalated P2s individually — none of which is
blocking anything today (D-27 and D-34 are latent, D-17 has no affected committed script).
Folding D-33 into 55b costs one test file and closes the audit's only gap in the slice that
already touches that surface.

**Routed to the user — three calls this review cannot make:**

1. **D-9** — schedule it, or record that `gov_p95=median|max` is a **permanent** substitute
   for a fix and close the row. Third surfacing; silence is not a legal state.
2. **D-27 + D-34 + D-17 as slice 56** — confirm, or override the lean and take Option B now.
3. Whether **D-33** rides in 55b (the lean) or waits for 56.
