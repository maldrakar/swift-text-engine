# Slice 56 — post-slice review (artifact-shape enforcement)

- **Date:** 2026-09-04
- **Spec:** [`2026-09-04-artifact-shape-enforcement-design.md`](../specs/2026-09-04-artifact-shape-enforcement-design.md)
- **Plan:** [`2026-09-04-artifact-shape-enforcement.md`](../plans/2026-09-04-artifact-shape-enforcement.md)
- **Verification:** [`2026-09-04-artifact-shape-enforcement.md`](../verification/2026-09-04-artifact-shape-enforcement.md)
- **Merged:** [PR #138](https://github.com/maldrakar/swift-text-engine/pull/138), merge commit `7d75eb7`
- **Hosted proof:** [PR #139](https://github.com/maldrakar/swift-text-engine/pull/139) (`slice-56-hosted-proof`), merged `4cd8b42` — AC17
- **Arc:** soft-wrap — an **infrastructure** slice; consumed no map node, advanced no criterion

## What shipped

Six repository artifacts whose shape nothing verified became verifiable.

1. **The twelve blocking gate steps** (`WorkflowShapeTests`). `pinnedGateSteps` went from two
   hand-written rows to one row per **gateable** mode, pinned to `BenchmarkMode.isGateable`
   as a bijection in both directions. Identification changed from flag-token containment to
   **exact payload equality** — forced, because the default mode's flag *is* `--gate`, and
   strictly stronger, because a token probe cannot see a second invocation or a trailing
   `|| true` inside one block scalar. Twelve before/after anchor pairs collapsed into one
   declared total order plus two boundary anchors, and a whole-file `--gate` census closes
   the one-level-up hole: a thirteenth gate step, in any job, cannot ship unpinned.
2. **`BenchmarkMode.flagName`** (exhaustive switch, `.pipeline` → `nil`), round-trip pinned
   against `BenchmarkOptions.parse` — which is what turns that `nil` from a comment into a
   verified claim.
3. **`lint-plan-assertions.sh`** — R1 (`PIPESTATUS` in a shell fence), R2 (`echo "…=$?"`
   after a status-insensitive predecessor), R3 (a `SCREAMING_SNAKE` variable used in a fence
   and assigned nowhere in it), R4 (a task with no guarantee inventory, or a listed guarantee
   with no drill step), with `--self-test`, `--list-exempt`, a 56-plan grandfather ratchet,
   and an unguarded CI step.
4. **`PlanLintTests`** — the ratchet pinned by four properties rather than by copying 56
   filenames into Swift.
5. **`DebtLedgerShapeTests`** — unescaped-pipe parity, table extent, id uniqueness and
   contiguity, status vocabulary.
6. **`AGENTS.md`** — D-2 rule 1 rewritten to drop the `${PIPESTATUS[0]}` recommendation that
   inverts a failed check into a pass under zsh; a fifth convention (the per-task guarantee
   inventory is the authority, a spec's drill list a lower bound); three lines on writing a
   record that cannot carry facts about its own branch.

Nothing measured moved: 46 gated checksums byte-identical, no budget literal, no corpus row,
no gated-mode set change, no core or provider source touched.

## Acceptance-criteria status

All 17 discharged. AC1–AC16 landed with the implementation; **AC17 needed two hosted
attempts** and is recorded in [PR #139](https://github.com/maldrakar/swift-text-engine/pull/139).

| Run | Head | Reading |
|---|---|---|
| 33882695798 | `7aa2879` | host **fail** — 497/3, all `ScriptSelfTestTests`; `lint=pass files=1 violations=0` (vacuous for R4) |
| 33893974939 | `369d2cf` | all three green — 497/0; 46 `gate=pass` / 0 `gate=fail`; 5 `invariant=pass` |
| 33894750111 | `7d75eb7` (merge) | same readings on merged code |

## Strengths

**The exact-payload predicate is a real strengthening, not a refactor.** Slice 54's Drill H
showed `|| true` on the `--line-query` step leaving `swift test` green at 408/0. Re-run
against the shipped tree, the same edit now produces **8 failures across 7 test methods**,
and the workflow restores byte-identical afterwards. Ten blocking budgets went from
unpinned to pinned by one table.

**The bijection and the census are different holes, and the record says so.** Payload
equality catches an edited or disarmed *existing* step; the whole-file `--gate` census
catches a *wholly unpinned* thirteenth step, which no per-step pin can see. An earlier
draft of D-27's discharge conflated the two; a review round separated them. That kind of
correction is the difference between a discharge and a claim.

**The linter's findings are trustworthy, which is the only property that matters for an
authoring tool.** Round 2's quote-stripping fix moved R2's violation count over the 57-plan
corpus from 12 → 8; all four dropped hits were confirmed quoted-alternation false positives
and all eight survivors confirmed genuine. Measured, not asserted.

**The spec refused to over-claim, in writing.** §2.1 states that **none** of D-34's four
measured defects is shape-detectable, so the linter answers D-17 and D-2 rule 4 and *not*
D-34; §8 states that R4 buys a prompt, not a proof. The ledger then matches: D-34 and D-35
stay `open` with only their shape/structural halves discharged. A slice whose thesis is
"unfalsifiable claims about enforcement are the defect" did not make one about itself.

**The `--self-test`-from-`swift test` redundancy paid for itself inside its own slice.**
D56-6 argued a bash script *and* a Swift test because "authoring discipline that only runs
when someone remembers it is the mechanism D-34 already measured as failing". On the first
hosted run the linter's own CI step printed `lint=pass files=1 violations=0` while R4
checked nothing; `ScriptSelfTestTests` is what went red. The argument was validated by
event, not by reasoning.

## Issues

### P0 / P1

None. All three required contexts are green on the merge commit at step level.

### P2 #1 — a docs-only PR runs the linter but never checks that the linter's rules are alive

D56-9 put the lint step **outside** the docs-only guard for a good reason: a plan is
`docs/**`, so a plan-carrying PR is detected as docs-only and skips `swift test`; without
the exemption the linter would be absent in CI for exactly the PRs that carry plans.

But the guarantee that the linter's rules still *work* — `--self-test`, which drives every
rule against a known-bad fixture and requires a red — lives in `ScriptSelfTestTests`, i.e.
**inside `swift test`**, which is guarded (`swift-ci.yml`, `Run host tests`:
`if: steps.change-scope.outputs.docs_only_pr != 'true'`). So on a plan-carrying docs-only
PR the only thing that runs is a linter that can print `lint=pass files=1 violations=0`
with one or more of its four rules checking nothing.

This is not hypothetical. Run `33882695798` is the recorded instance of that exact output
with R4 inert; it was caught only because that PR was *not* docs-only and `swift test` ran.
The same defect on a docs-only PR would have merged silently.

**Remedy, cheap:** make the unguarded step run both, in order — `--self-test` first, then
the lint — so the rule-liveness proof travels with the step that exists for those PRs.
Roughly one second, no Swift build, no new artifact. `WorkflowShapeTests`'
`testPlanLintStepIsBlockingAndUnguarded` pins that step by exact payload, so the change is
one line of YAML and one expected-payload literal.

Ledger: **D-43**.

### P3 #1 — D-42 (g) understates the guard that actually fired

D-42 (g), written in the same fix wave that discovered the awk defect, says nothing
mechanically prevents the next non-portable construct. Read literally that is true, but it
omits what the incident demonstrated: **every rule has at least one `bad-*` fixture whose
self-test asserts exit 1 and the exact rule name**, so a rule that goes inert on any
platform reddens `swift test` on that platform. That is a working detection guarantee, and
it is the one that fired.

What is genuinely missing is *prevention*, not detection: nothing stops a non-portable
construct from being written, so the failure surfaces one hosted run later than it could
(and, per P2 #1, not at all on a docs-only PR). The row is amended in place rather than
re-scoped — the D-15/D-9 precedent — because a residual that overstates a gap is the same
class of unfalsifiable claim as one that understates it.

### P3 #2 — the whole-file `--gate` census counts comments

`testEveryGateInvocationInTheWorkflowIsPinned` tokenizes the entire workflow file, so a
`--gate` token inside a YAML comment reddens it. It fails **closed**, which is the right
direction, and the alternative (scoping to `run:` payloads) reopens the hole the census
exists to close. Recorded rather than fixed. Ledger: **D-44**.

### Process observations

**A fix wave that lands after the verification record is written gets weaker verification
than the tasks did.** Every one of the seven tasks was driven red-first, drilled, and its
transcript recorded. The final fix wave (`7aa2879`) was reviewed, drilled and recorded to
the same standard — *on macOS*. It shipped the one defect that reddened CI, and its own
summary ("swift test: 497/0 … the four original rule drills were re-run against the final
tree and still redden") reads as completion evidence for a tree no hosted run had yet seen.
The tasks were protected by the plan's structure; the fix wave was protected only by the
implementer's judgement, and the difference showed. Worth carrying into the next slice's
plan as an explicit step rather than a lesson.

**A measured value in a comment rots faster than the branch it is written on.**
`PlanLintTests`' header quoted a 35/21 dirty/clean split of the exempt set and named a
specific plan as an example of a clean one. Two commits later — same branch, same slice —
R4's heading widening moved every exempt plan into the dirty set, and the named example
became false. Repaired by replacing the number with the command that re-derives it. This is
the third instance of the class in this repository (after D-9's named max-governed scenario
and D-42 (a) itself), and the remedy has been the same all three times.

**The slice's own plan was the linter's only subject, and that is fine.** All 56
pre-existing plans are grandfathered, so `lint=pass files=1 violations=0` covers exactly one
file. Non-vacuity was checked directly rather than assumed: deleting one assignment from a
copy of the plan produces `violation=R3` at that line, and renaming its `**Guarantees
added:**` block produces `violation=R4`.

---

# Recommendation (skill Mode 2)

**Map pass.** Slice 56 was the **infrastructure route** and consumed **no map node** — the
sixth slice of that shape, after the process slice 48, the debt slice 51 and the calibration
slices 52/54, and the second in a row that is not a criterion node (55b closed criterion 3;
56 closed no criterion). Nothing it shipped touches wrap feasibility, so nodes 5–9, fork R
and fork V stand unrevised and un-relearned.

What it changed for **node 6**, for the fifth time in six slices, is one row *leaving* the
reading list rather than joining it: **D-9 is now `scheduled(node-6)`** by explicit user
call, so node 6's precondition set is D-20/D-21, D-28, D-30, D-31 **plus D-9** — six rows,
and the newest of them is the p95 recipe itself, which must be right *before* that node's
first harvest because `harvest → derive` never re-measures.

Next step is **topological**, not a fork: node 5 (`--memory-shape` over the wrap path,
criterion 2). The arc file already recorded at 55b's pass that it "should not wait past
slice 57", and this is slice 57. First genuine fork remains node 8 (host order) / fork V,
now joined by fork R.

### Scoreboard delta

**No criterion status changed.** Slice 56 was infrastructure; it advanced no brief
criterion, which was known and accepted at selection.

Still open or partial:

| # | Criterion | Status |
|---|---|---|
| 1 | Width change does not recompute the document | **partial** — core half retired (Slice 50); `done` needs the estimated/async veneer (fork V), since the exact reindex is Ω(N) |
| 2 | Core memory not linear with wrap on; `--memory-shape` extended to the wrap path | **open** — no evidence at all; the only wrap criterion in that state |
| 4 | 100k+/10 MB scroll with wrap on holds budgets and the absolute ceiling; wrap modes become blocking gates | **open** |
| 5 | Incremental edits under wrap inside frame-hot-path budgets | **open** |
| 6 | Thin iOS/browser verification hosts | **open** |

Criterion 3 remains `done` (closed by slice 55b); nothing in slice 56 touched it, and the 46
byte-identical gated checksums on the post-merge run
([33894750111](https://github.com/maldrakar/swift-text-engine/actions/runs/33894750111)) are
the evidence.

### Debt ledger delta

**Discharged this slice** — all four with links in the ledger:

- **D-27** (P2) — ten of twelve gate steps unpinned → one row per gateable mode, bijection to
  `isGateable`, exact payload equality, whole-file census.
- **D-17** (P2) — `AGENTS.md` rule 1 recommended an idiom that inverts to a pass under zsh →
  rule rewritten with three shell-agnostic idioms, and mechanized as R1.
- **D-37** (P3) — "a record cannot carry facts about its own branch" was unwritten → three
  lines in `AGENTS.md`, exercised twice in this very slice (§0's open-ended commit table,
  §8 on a separate branch).
- **D-39** (P3) — the ledger's own table shape unenforced → `DebtLedgerShapeTests`.

**Re-scoped, not discharged:** **D-34** and **D-35** stay `open` with their shape/structural
halves discharged and their semantic halves named. That is the honest disposition and the
spec argued for it in advance.

**Rehomed by user call:** **D-9** → `scheduled(node-6)` (2026-09-04).

**Added by the slice:** **D-40** (three unmechanized assertion classes), **D-41**
(`flagName` is a pinned third copy, not a deleted one), **D-42** (ten implementation
residuals).

**Added by this review:**

- **D-43** (P2) — a docs-only PR runs the linter but skips `swift test`, so nothing checks
  that the linter's rules are alive on exactly the PRs the unguarded step exists for
  (P2 #1 above).
- **D-44** (P3) — the whole-file `--gate` census counts tokens in comments (P3 #2 above).

**Amended in place:** **D-42 (g)**, per P3 #1.

**Open counts after this review:** **3 open P2** (D-34, D-35, D-43) and **19 open P3**.

**Escalation rule:** none forced. D-34 and D-35 were born at the slice-55a and slice-55b
reviews and are one completed slice old; D-43 is new; D-9, the row that had been surfacing
for nine slices, is now `scheduled(node-6)` rather than open. This is the first review in
six with no P2 at the escalation threshold.

### Falsifiability audit

Twenty-one standing guarantees added, each with a **recorded red** — drills (a)–(w), 23 of
them, transcribed verbatim in the verification record's §2 and §3. Spot-checks re-run
independently against the merged tree rather than read from the record:

| Guarantee | Evidence it can fail |
|---|---|
| G3 — the twelve gate steps' payload equality | `\|\| true` appended to the `--line-query` step → **8 failures across 7 methods**; workflow restored byte-identical. The same edit left `swift test` green before this slice |
| G1/G2 — table ↔ `isGateable` bijection | deleting `.columnQuery`'s row and adding a non-gateable `.wrapRowQuery` row each redden, in different tests |
| G8–G11 — R1–R4 | each rule's `bad-*` fixture asserts exit 1 **and** the exact rule name; re-run against the final tree |
| G12/G20 — the grandfather ratchet | a same-day plan added to the list, an entry naming an absent file, and a deleted entry each redden a different check |
| G13/G21 — ledger shape | a raw `\|` in a code span, a deleted middle row, and a mangled id cell each redden |
| G16/G17 — `flagName` ↔ `parse` | a wrong flag spelling reddens 2 tests; giving `.pipeline` a flag reddens all 4 |

**The strongest evidence in the slice was not a drill.** Run `33882695798` is a *natural*
red for a guarantee nobody drilled deliberately: "R4's task-heading rule matches the
headings plans actually use, on the platform that enforces it". It failed, named its
fixture, and named the platform. No mutation test would have produced it, because the
mutation was accidental and the platform difference was invisible locally.

**One guarantee added after the record was written** — the `###?` heading pattern — carries
that hosted red as its evidence, which is stronger than a drill would have been.

**No guarantee in this slice lacks a red.** The mandatory "prove X can fail" candidate
option is therefore **not** spawned.

### Candidate options

**Option A — node 5: `--memory-shape` over the wrap path (lean, selected).**
Advances **criterion 2**, the only wrap criterion with no evidence at all, and the one the
brief's hard constraint 5 makes non-negotiable. Sits at the map's next topological slot; the
55b pass already said it should not wait past slice 57, and this is slice 57. The wrap query
surface is now complete (node 4 done), which was the stated reason for not extending
`--memory-shape` twice. Folds in **D-43** (one YAML line plus one pinned payload literal —
it belongs with the first slice that touches CI, and this is it). Cost: a new diagnostic
path over the wrap providers, no new gate.

**Option B — node 6: promote the wrap benchmark modes to blocking gates.**
Advances **criterion 4** and discharges the largest cluster of ledger rows in one slice
(D-9, D-20/D-21, D-28, D-30, D-31). Rejected as *next*: its reading list is a precondition
set, not a backlog, and one of the six — D-9's p95 recipe — was rehomed here only yesterday
and edits the budget arithmetic for all 46 committed budgets. Running that before criterion 2
has any evidence also leaves the arc with two criteria at `open` and no memory-shape
measurement, which is precisely the "criterion stays open for ten slices" failure this skill
exists to prevent.

**Option C — a second infrastructure slice for D-43 + D-40's unmechanized classes.**
Rejected: D-43 is one YAML line and folds into Option A at no cost, and slice 56 is already
the second consecutive slice that advanced no criterion. A third would be the shape the
arc file has flagged twice.

**Routing.** This is a **topological** step, not a fork, so this review **selects Option A**
(slice 57 = node 5, folding in D-43) rather than routing it to the user. The user can
override; the genuine forks still ahead are node 8 (host order), fork V (the width-change
veneer) and fork R (within-line random access), none of which blocks this selection.
