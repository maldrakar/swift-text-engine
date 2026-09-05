# Slice 57 — post-slice review (wrap memory shape)

- **Date:** 2026-09-05
- **Spec:** [`2026-09-04-wrap-memory-shape-design.md`](../specs/2026-09-04-wrap-memory-shape-design.md)
- **Plan:** [`2026-09-04-wrap-memory-shape.md`](../plans/2026-09-04-wrap-memory-shape.md)
- **Verification:** [`2026-09-04-wrap-memory-shape.md`](../verification/2026-09-04-wrap-memory-shape.md)
- **Merged:** [PR #141](https://github.com/maldrakar/swift-text-engine/pull/141), merge commit `6490a87`
- **Hosted proof:** [PR #142](https://github.com/maldrakar/swift-text-engine/pull/142) (`slice-57-hosted-proof`), merged `a8f2017` — AC10
- **Arc:** soft-wrap — map **node 5**, closing **criterion 2**

**Independence disclosure, stated first because it bounds everything below.** The
validation pass recorded as record §2a — and the five repairs in commit `747682f` — were
produced by the same session that writes this review. This review is therefore
*independent of the implementation* (a separate session shipped rows 4–17) but **not**
independent of the validation pass. Findings P2 #1, P3 #1 and P3 #2 are new here; the
strengths attributed to §2a are self-attributed and should be read with that discount.

## What shipped

**The spine.** `--memory-shape` — already a **blocking** CI step — gained a wrap half: six
scenarios, `{100k, 1M} × {inf, 40, 10}`, each driving all four wrap entry points a viewport
reaches (`compute(_:layout:)`, the `DocumentVisualRowCursor` drain, `visualRowAt`,
`visualPointAt`) through a `CountingWrapLayout` that counts all six `VisualRowLayoutSource`
hooks. Node 1's per-line `visualRows` is covered transitively through the drain.

The observable is **provider probes, not bytes** (Decision 1), because every wrap entry
point returns fixed-size values and a `MemoryLayout` sum reports a *pointer* for exactly
the case it would need to catch. That choice is what makes the mode able to say anything at
all about criterion 2 — and its residual is named rather than implied (**D-46**).

**The repair (D-45), which had to land first.** The mode's only cross-scenario comparison
compared each summary's `coreOwnedBytes` against the first of its provider group — `x == x`
for the synthetic group, and `large_text` matched neither branch and was not compared at
all. `touched_lines` on the variable path was `providerLines: bufferedLines`, the buffered
window written twice. Both replaced by a mode-wide equality against a **declared**
expectation, extracted as pure functions that `swift test` drives over synthetic summaries.

**The fold-ins.** Eight of nine discharged (D-10, D-11, D-14, D-19, D-20, D-21, D-38,
D-43). The ninth, **D-15, was falsified** — see Strengths.

**The validation pass** (record §2a) added the slice's only positive control and closed four
of the five residuals §7.10 had triaged as carry-not-fix.

Nothing measured moved: 46 gated checksums byte-identical, no budget literal, no corpus row,
no gated-mode set change, `git diff main -- Sources/TextEngineCore` empty.

## Acceptance-criteria status

All 14 discharged. AC1–AC9 and AC11–AC14 landed with the implementation; **AC10** is in
[PR #142](https://github.com/maldrakar/swift-text-engine/pull/142).

| Run | Head | Event | Reading |
|---|---|---|---|
| 33952531288 | `bbd9608` | PR | green, but superseded — pre-validation-pass tree |
| 33957419266 | `34c6d9b` | PR | auto-cancelled by `ea57cc9` |
| **33957528537** | `ea57cc9` | PR | 3 jobs; 46 `gate=pass`/0 fail; 11 `invariant=pass`; 525/0; lint step prints both `self_test=pass` and `lint=pass` |
| **33957849785** | `6490a87` (merge) | push | identical readings on the merged tree |

**AC9 is the one to read carefully.** It says "every fold-in row in §4E is implemented", and
D-15 is not — it was implemented, measured to produce the exact failure the row exists to
prevent, and reverted. The literal AC is unmet and the outcome is better than compliance;
the spec's §4E row is now struck through and points at D-47.

## Strengths

**1. D-15's falsification is the best thing in the slice.** The row prescribed converging
four self-test dispatchers on `run_self_test || exit 1`. Under `set -e`, `||` lifts `-e`
from the callee's **entire body**, so a returning assertion no longer aborts, execution
reaches `echo "self_test=pass"`, and that success becomes the function's status. Measured
both ways on a real script; the edits were reverted and the row's remedy withdrawn. A slice
that discharges eight of nine fold-ins and *refuses* the ninth on evidence is the behaviour
the ledger exists to produce.

**2. The mode repaired its own instrument before extending it.** Closing criterion 2 on a
comparison that cannot fail is a shape this repository has shipped five times
(`AGENTS.md`, "Never hand-type a budget"). D-45 was found by *reading the mode before
extending it* — not by a test, not by CI — and the spec made the repair a precondition of
the spine rather than a follow-up. That ordering is why criterion 2's evidence cell can be
read literally.

**3. The declared-expectation idiom, and its second defect named.** The repair does not
inherit `summaries.first`, and the spec says why in two clauses: a neighbour comparison is
how `x == x` happened, **and** the first element is never itself checked, so corrupting *it*
reddens the other ten and leaves the guilty line green.
`testCorruptingTheFirstContributionNamesTheFirstContribution` is the pin for the second
clause, which is the one nobody would have thought to write.

**4. `CountingWrapLayout.logicalLine` does not forward.** The core's default binary search
probes `firstVisualRow` on whatever layout it is handed, so a forwarding wrapper would send
the dominant O(log N) term into the *unwrapped* base and every probe count in the mode would
understate — silently, with all other assertions green. `DefaultLogicalLineProbe` closes it
without copying `binarySearchLogicalLine` (which would have been D-13's fourth copy).
`testTheDefaultLogicalLineSearchIsAttributedToTheCounter` pins it.

**5. The fixture separates its axes, deliberately and in writing.** 1 / 2 / 8 rows per line,
none equal to the buffered window (90), the visible window (80), or each other; the `+ 3`
offset puts the query off a row-start so `rowInLine` reads 0 / 1 / 3 rather than 0
everywhere; `x = 5.0` is in range at all three widths so `point_query_probes` measures the
delegating branch rather than the clamp path at one width and the delegating path at
another. Both are printed (`point_row_in_line=`, `point_clamp=`) so a reader checks rather
than assumes. This is the repo's own recorded lesson applied *before* it bit.

**6. The record is unusually honest about its own defects.** §7 documents eight of the
plan's twenty-three drills as defective **as written** and every one repaired in-flight
rather than tuned to a green; §7.6 documents a probe-count pin whose two widths were one
regime; §7.9 tallies it so a reader comparing the plan to the record does not conclude
drills were skipped.

**7. Architecture-independence, which came out stronger than AC7 asked for.** All eleven
`--memory-shape` lines from the hosted Linux x86_64 runner are byte-identical — `checksum=`
included — to the baseline taken locally on macOS arm64. A probe count *should* be
architecture-independent; a timing never would be. That is a property of the observable
Decision 1 chose, and it is worth naming because it is what makes this mode cheap to trust.

## Issues

### P0 / P1

None. The mode is correct, blocking, hosted-green on both halves, and every invariant in
§4A is implemented.

### P2 #1 — the slice's twenty-three drills contained no positive control, and that is why a blind spot survived to the merge queue

**The mechanism.** Every drill in the plan perturbs a **check** or an **expectation**:
truncate the drain by one row, add a gratuitous probe, change an overscan, corrupt a
summary, drop a hook's increment, append `|| true`. None of them injects the **real failure
mode** — a core that walks the document — into the measured path and asks whether the mode
notices.

**The measurement.** The `--memory-shape` variable half could not report an over-walk at
all: `touched_lines` is `distinctLines` intersected with the buffer range, so it is bounded
above by construction and a core walking the whole document still prints `touched_lines=90`.
The raw distinct count — the only quantity that would move — was collected into
`LineProbeCounter` and thrown away. That blindness survived: a spec-level audit that was
*specifically looking for vacuous measurements in this mode* and found two (D-45), the
plan's twenty-three drills, a whole-branch review, a fix wave, and a hosted green. It was
found the first time somebody injected the failure (record §2a, drill (y)), where the
new invariant reddens **while `touched_lines` sits unmoved at 90**.

**Why this is not D-35.** D-35 says a spec's drill *list* is a lower bound and the per-task
inventory is the authority — a **completeness** rule, and slice 57 obeyed it (twenty-four
guarantees inventoried, twenty-three drills). This is about the drill **kind**: a complete
list of check-mutations still cannot discover that the check is aimed slightly to one side
of the thing it is for. The two compose; neither implies the other.

**Proposed rule, small enough to fold in:** a slice whose subject is an invariant must carry
at least one drill that injects the invariant's *own* failure mode into the measured path,
distinct from any mutation of the checks. In slice 57 that drill costs eight lines and one
release rebuild, and it is the single most convincing artifact the slice produced — all six
wrap lines red, `exit=1`, `drain_probes` at 100469 / 1000472 against a `<= 32` bound.

Ledger row **D-49** (P2).

### P3 #1 — `allJobKeys` misses a job key that carries an inline comment

`WorkflowShapeTests.allJobKeys()` accepts a line only if, after the two-space indent, it
`hasSuffix(":")`. `isComment` filters *whole-line* comments, so a fourth job written as

```yaml
  temporary-job:  # remove after the migration
```

is silently skipped, and `testWorkflowJobSetIsExactlyTheThreePinnedJobs` — the pin D-11
added precisely so "a fourth job cannot appear unmodelled" — passes. The pin fails **open**
on that shape, which is the wrong direction for a census.

Narrow in exposure (no job key in this workflow carries an inline comment, and the repo's
YAML style does not), and the fix is one line: strip a trailing ` #…` before the suffix
test. Recorded rather than fixed, because a review does not edit code here. This is the
repository's own recurring lesson — *pins must model what runtime reads* — landing on the
container one slice after D-44 landed it on the contents.

Ledger row **D-50** (P3).

### P3 #2 — `CountingWrapLayout`'s precondition is documentation, not a check, and it is cheaply checkable

The wrapper deliberately answers `logicalLine(containingVisualRow:)` from the core's default
instead of forwarding (Strength 4 — correct, and the whole mode's attribution depends on
it). The consequence is a precondition: **a base that overrides that hook natively must not
be wrapped**, or the mode measures a different algorithm and may return a different index.
The validation pass wrote that precondition into the doc comment; nothing enforces it.

`BenchmarkWrapLayout` declares no override, so this is latent today. It stops being latent
at exactly the node most likely to arrive next: a balanced-tree wrap provider — the wrap
analog of `BalancedTreeLineMetrics`, which is precisely the shape that *would* override the
hook — is the natural provider for node 6's gate scenarios.

This is the same class as **D-34** ("conventions are documentation, not enforcement"), and
unlike most instances of it, this one has a cheap mechanical answer: cross-check the
wrapper's answer against `base.logicalLine(containingVisualRow:)` and trap on disagreement.
That converts a prose precondition into a failing test the first time it is violated.

Ledger row **D-51** (P3).

### P3 #3 — declined a row: cross-scenario invariant 12's size clause is one-sided

`wrapMemoryShapeCrossScenarioFailures` fails a width pair when
`large.providerOwnedBytes < small.providerOwnedBytes * 9`, so a footprint growing 100× at 10×
the lines passes. **No ledger row**, deliberately: per-scenario invariant 7 already pins
`provider_owned_bytes == (line_count + 1) * MemoryLayout<Int>.size` **exactly**, on every
line, so invariant 12's size clause is a cross-check of an already-exact assertion and its
looseness cannot admit anything invariant 7 rejects. Recorded here so the next reader does
not re-derive it as a finding.

### Process observations

**1. Nine of the ten rows in scope had nothing to do with the node.** The user raised the
fold-in depth from one row to nine, and Decision 10 sequenced them *after* the spine
precisely so a fold-in could not delay the criterion. It worked — but the heaviest fold-in
(D-14, three scripts) is also where the falsified row (D-15) lived, and the pass that closed
M-7 later found the same partition missing from a **fifth** script that was outside D-14's
stated scope. Deep fold-in slices buy debt reduction at the cost of a wider surface for
exactly this kind of near-miss.

**2. The record's §6 went stale twice, in the section immediately after the one written to
prevent it.** §0 forbids bare totals and names commits by SHA; §6 then asserted a test count
that the very next commit falsified, and again after the one after that. It is now a
per-SHA table. Worth noting because the failure was not ignorance of the rule — the rule was
written *in the same document*, six sections earlier.

**3. The slice's own drills produced more findings than its tests did.** Eight defective
drills, one fixture coincidence, one false plan claim about the shipped core
(`visualRowCount(inLine:)` has no consuming call site anywhere in `Sources/TextEngineCore`).
None of these was found by running the suite; all were found by trying to make it fail.

---

# Recommendation (skill Mode 2)

**Map pass.** Node 5 is **`done`** and with it **criterion 2** — the wrap criterion that had
no evidence at all. The map pass was written during the slice (arc file, "Map pass
2026-09-05") and this review re-validates it, with two corrections:

1. **Node 6's precondition set was listed wrong.** The slice's pass wrote it as "D-28, D-30,
   D-31, **D-33** plus D-9". D-33 was discharged in slice 55b. The set is **D-28, D-30, D-31
   plus D-9** — four rows, of which D-9 (`scheduled(node-6)`) is the only P2 and the only one
   that edits arithmetic behind all 46 committed budgets.
2. **Node 5's entry gains the validation pass** as its fourth lesson (already applied), and
   with it the generalizable one: an invariant slice needs a positive control, not only
   check-mutations (P2 #1 / D-49).

Nodes 6–9, fork R and fork V stand unrevised — nothing this slice shipped touches gate
promotion, incremental edits under wrap, the hosts, within-line random access, or the
width-change veneer.

**Where the next step sits.** For the first time in several slices the map's next step is a
**choice between two topological successors**, not a single one: node 6 (gate promotion,
criterion 4) is listed first and node 7 (incremental edits under wrap, criterion 5) has no
precondition set at all. The arc file already flagged this. It is routed to the user below.

### Scoreboard delta

**Criterion 2: `open` → `done`.** Evidence:
[PR #141](https://github.com/maldrakar/swift-text-engine/pull/141) (merge `6490a87`),
hosted proof [PR #142](https://github.com/maldrakar/swift-text-engine/pull/142) (merge
`a8f2017`), post-merge run
[33957849785](https://github.com/maldrakar/swift-text-engine/actions/runs/33957849785) —
eleven `--memory-shape` lines all `invariant=pass`, six of them `provider=wrap`,
`compute_probes=2` in all six, size deltas of exactly 3 on every other entry point,
`provider_owned_bytes` 800008 → 8000008.

**Scope of that `done`, carried into the cell:** the observable is provider probes, so it
sees a core that *traverses* and is blind to one that *allocates* without traversing
(**D-46**, `accepted-risk`). No instrument available here closes that.

Still open or partial:

| # | Criterion | Status |
|---|---|---|
| 1 | Width change does not recompute the document | **partial** — core half retired (Slice 50); `done` needs the estimated/async veneer (fork V), since the exact reindex is Ω(N) |
| 4 | 100k+/10 MB scroll with wrap on holds budgets and the absolute ceiling; wrap modes become blocking gates | **open** |
| 5 | Incremental edits under wrap inside frame-hot-path budgets | **open** |
| 6 | Thin iOS/browser verification hosts | **open** |

Criteria 2 and 3 are `done`. **Three of six criteria are now closed or half-closed, and the
three that remain are the three that need hosted measurement or a platform host** — the arc
has finished the part that is pure core work.

### Debt ledger delta

**Discharged by the slice** — nine rows, each with a link in the ledger:

- **D-45** (P2) — the two vacuous measurements, opened and discharged in the same slice.
  *Scope added by the validation pass:* clause (a) outright; clause (b) in **provenance**,
  not in falsifiability (see D-48).
- **D-43** (P2) — the plan linter now runs its own self-test on every PR, unguarded.
- **D-10, D-11, D-14, D-19, D-20, D-21, D-38** (P3) — the superseded banner, the job-set
  pin, the coverage partition in three scripts, the `frame-hot-path` vocabulary, both
  `AbsoluteCeiling` class arms, and one transcribed constant.

**Falsified, not discharged:** **D-15** stays `open` with its remedy **withdrawn** — the
prescribed shape is the unsafe one under `set -e`. Do not fold it in as written.

**Opened by the slice:** **D-46** (P3, `accepted-risk` — a probe count sees traversal, not
allocation), **D-47** (P3 — D-15's falsification evidence and the shape a real fix would
take), **D-48** (P3 — D-45's `touched_lines` clause is discharged in provenance but not in
falsifiability).

**Opened by this review:**

- **D-49** (P2) — the drill vocabulary has no positive-control category (P2 #1).
- **D-50** (P3) — `allJobKeys` misses a job key with an inline comment (P3 #1).
- **D-51** (P3) — `CountingWrapLayout`'s precondition is prose, not a check (P3 #2).

**Open counts after this review:** **3 open P2** (D-34, D-35, D-49) and **15 open P3**.
D-9 remains `scheduled(node-6)`; D-4, D-16, D-26, D-46 are `accepted-risk`; D-5 is
`deferred(user, 2026-07-21)`.

**Escalation rule — one row is forced.** **D-34** (P2, born at the slice-55a review) is now
three completed slices old (55b, 56, 57) and therefore MUST appear under Candidate options:
it does, inside **Option C**, and if Option C is not selected the user should record an
explicit `deferred(user, <date>)` rather than let it surface a fourth time. D-35 is two
slices old and not yet forced; D-49 is new.

### Falsifiability audit

Twenty-four standing guarantees added or changed, and **every one carries a recorded red.**
Drills (a)–(w) are transcribed verbatim in the record's §2; the validation pass adds (x),
(y) and three more. Independently re-run against the merged tree rather than read from the
record:

| Guarantee | Evidence it can fail |
|---|---|
| **The mode catches a document walk** (the criterion itself) | inject `for i in 0..<lineCount { _ = drainLayout.firstVisualRow(ofLine: i) }` → all six wrap lines `invariant=fail`, `exit=1`, `drain_probes` 469 → 100469 and 472 → 1000472 |
| The variable half's raw offset count | expectation `+1` → `+2` reddens both lines; injecting a real walk reddens them **while `touched_lines` stays 90** (drills (x), (y)) |
| `compute_probes` flat / the `<= 32` shape bound / the window / the walk-is-a-width-term | `MemoryShapeComparisonTests`, ten unit tests over synthetic summaries, each mutation naming the intended scenario(s) |
| D-45's mode-wide equality | corrupting `large_text` (formerly exempt) and corrupting the **first** contribution each name their own line |
| `CountingWrapLayout` counts every hook / keeps the by-argument counter | dropping an increment, and folding `firstVisualRowAtLineCount` into `total`, each redden — the latter only on the *compute* counter, which is why the fix wave added that assertion |
| The wrap line's token shape | `visible_rows=80` → `801` reddens (the old substring form passed); a `surprise_column=` reddens the count pin; renaming `row_query_probes=` to a duplicate `drain_probes=` reddens the **per-key uniqueness** clause in isolation, count pin green |
| The scenario list | relabelling width `"10"` → `"8"` reddens the list pin and *nothing else* — the mode keeps printing `invariant=pass`, which is the hole it was added for |
| `lint-plan-assertions.sh`'s partition (new) | four drills: unclassified function, phantom COVERED name, exempt entry with no justification, covered-but-unreferenced — each with its own label |
| D-43's payload pin / D-11's job set / D-14 ×3 / D-20 / D-21 / D-38 | drills (s), (v), (w), (t)(i), (t)(ii), and §7.7's twice-corrected (u) |
| M-8's fixture guard (new) | restoring two of the old widths fires it |

**No mandatory "prove X can fail" option is spawned.** One honest exception, recorded rather
than glossed: **M-6** (the `${ARR[@]+…}` guards in `cross-target-compile.sh`) is a latent-bug
fix, not a standing guarantee — it adds no test, and the condition that would exercise it
(an emptied classification array) does not exist today. It is listed here so the audit's
"every one" claim is not quietly doing work it should not.

**The audit's own lesson, and the reason for D-49:** this table was *also* complete before
the validation pass, minus its first two rows. Completeness of check-mutations is not
coverage of the invariant.

### Candidate options

**Option A — node 6: promote the wrap benchmark modes to blocking gates.**
Advances **criterion 4** and discharges the arc's largest remaining cluster: **D-9** (its
`scheduled(node-6)` home), **D-28**, **D-30**, **D-31**. Sits at the map's next topological
slot and is listed first there. Both of its calibration inputs were repaired ahead of it in
slice 54, because `harvest → derive` never re-measures and never re-authenticates — so those
defects are unrepairable *after* this node's first harvest, which is the argument for not
letting it drift. **Cost and risk:** D-9 edits the p95 arithmetic behind all 46 committed
budgets and must land before the first harvest, not inside the same PR as a gate-shape diff;
D-31 says `--wrap-compute`'s local columns cannot resolve an effect smaller than host state
variance, so the calibration must be hosted from the start. Likely splits per mode, as the
first arc's gate promotions did. **Also relevant:** node 6's scenarios are where a
balanced-tree wrap provider would first appear, which is exactly what makes **D-51** stop
being latent — so P3 #2 folds in here at near-zero cost.

**Option B — node 7: incremental edits under wrap.**
Advances **criterion 5**, and is the only remaining node with **no precondition set at all**
— nothing in the ledger blocks it. It is also the last purely-core capability in the arc:
after it, everything left is gates (4), hosts (6) and the width-change veneer (fork V).
**Against it as next:** criterion 5's own wording is "stay within frame-hot-path budgets",
and there is no wrap budget until node 6 exists, so shipping node 7 first means shipping a
capability whose acceptance criterion cannot be evaluated. That is a real ordering argument,
not a preference — it is why the map lists 6 before 7.

**Option C — an infrastructure slice: D-34 + D-40 + D-49, the "documentation is not
enforcement" cluster.**
Advances **no criterion**, and discharges the escalated **D-34** together with **D-40** (the
three assertion classes the linter cannot mechanize) and this review's **D-49** (the
positive-control rule), plus P3 fold-ins **D-50**, **D-51**, **D-41**, **D-42**, **D-44**.
The case for it: D-34 is at the escalation threshold, D-49 is a P2 born from a blind spot
that reached the merge queue, and the three of them are one coherent subject — the gap
between a convention being written down and a convention being enforced. **Against it:**
this would be the *third* infrastructure slice in five (52/54 calibration, 56 artifact
shape), and the arc file has flagged that shape twice. Criterion 4 has been `open` since the
arc started.

**Routing — this goes to the user.** The map's next step is a choice between two defensible
directions (node 6 vs node 7) with a third, non-criterion option carrying an escalated P2, so
this review does **not** self-select.

**The lean is Option A**, for one reason that outranks the others: node 6's inputs are the
only ones in the arc that are *unrepairable after the fact*. Every other row on the ledger can
be fixed in the slice after the one that needs it; a budget derived from a contaminated or
mis-quantised corpus cannot be, because `harvest → derive` never re-measures. Option C's
**D-34 should then be explicitly deferred** (`deferred(user, 2026-09-05)`) rather than
surfacing a fourth time, and **D-51** rides along with Option A on merit, not on convenience.

If the user prefers Option B, the honest consequence to accept in writing is that
criterion 5's acceptance evidence waits for node 6 anyway.
