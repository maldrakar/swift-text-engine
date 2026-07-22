# Slice 48 — Outer-Loop Codification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codify the slice-selection process as the `choosing-next-slice` project skill plus living artifacts (wrap arc file, cross-arc debt ledger, AGENTS.md invariant), tested RED → GREEN with control-vs-treatment subagent runs.

**Architecture:** All deliverables are Markdown; there is no Swift, CI, or script change. The "tests" are subagent dispatches: a control run (no skill) must fail to do the ritual BEFORE `SKILL.md` exists, a treatment run (with skill) must catch all three seeded traps, and a Mode 1 run must prove the skill is executable by a non-author. Task order is load-bearing: control before the skill exists, AC6 before `arcs/wrap.md` exists, `AGENTS.md` last — each ordering prevents a contamination path.

**Tech Stack:** Markdown, git, `gh` CLI, harness Agent tool (`subagent_type: general-purpose`).

**Spec:** `docs/superpowers/specs/2026-07-21-outer-loop-codification-design.md` (source of truth; AC numbers below refer to it).

## Global Constraints

- Branch: `slice-48-outer-loop-codification` (exists; spec committed as `84516a5`, amended `89f16ea`).
- Every changed path must be Markdown outside `.github/workflows/**` and `.github/scripts/**` (AC8 docs-only requirement). Creating any non-`.md` file is a plan violation.
- Commit prefix `docs:`, one logical step per commit, trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Artifact language: English (brief criteria may be quoted in Russian).
- Subagent dispatches use the exact prompts given in the task. Never paraphrase them, never add hints about traps. Every prompt ends by requiring a self-declared "Files read:" list — the harness does not expose subagent tool logs, so the declaration is the recordable evidence (note this limitation verbatim in the verification doc).
- The four contract headers are exactly: `### Scoreboard delta`, `### Debt ledger delta`, `### Falsifiability audit`, `### Candidate options`.
- Do NOT edit `AGENTS.md` before Task 6, and do NOT create `docs/superpowers/arcs/wrap.md` before Task 4 — ordering is part of test validity.
- AC7 (live Mode 2 run) and AC9 (post-merge checks) are NOT in this plan: AC7 belongs to the slice 48 post-slice-review phase, AC9 to after the user merges. The verification doc lists them as pending with owners.

---

### Task 1: AC5 fixture + control run (RED)

**Files:**
- Create: `docs/superpowers/verification/2026-07-21-outer-loop-codification.md`

**Interfaces:**
- Produces: the verification doc with the frozen AC5 fixture text and the recorded control transcript. Task 2 reuses the SAME fixture verbatim for the treatment run; Tasks 2–7 append to this doc and must not rewrite the control section.

- [ ] **Step 1: Create the verification doc with the fixture**

Write `docs/superpowers/verification/2026-07-21-outer-loop-codification.md` with exactly:

````markdown
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
> with p95/p99 budgets committed in Budgets.swift. Both hosted runs (PR-head
> and post-merge) printed `mode=cell_query gate=pass` on the first try. The
> PR discussion notes the natural next step: a batch variant `cellsAt(_:)`
> that resolves many points in one call, which several call sites would
> simplify around."
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
> The project's debt ledger:
>
> | id | born | severity | statement | status |
> |---|---|---|---|---|
> | D-3 | slice 3 review | P2 | ci.yml step ordering is load-bearing but untested — a reorder silently disarms the docs-only guard | open |
> | D-6 | slice 6 review | P3 | benchmark summary line format duplicated in two files | open |
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

### Control run (RED)

<transcript and verdict recorded by Task 1>

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
````

- [ ] **Step 2: Dispatch the control subagent**

Dispatch via the Agent tool, `subagent_type: general-purpose`, with the prompt being EXACTLY the quoted prompt body from Step 1 (strip the leading `> ` markers; include nothing else — no mention of skills, checklists, traps, or this plan).

- [ ] **Step 3: Evaluate the control against the trap rubric**

Apply the rubric (a)/(b)/(c) to the control's output. Record in the `### Control run (RED)` section: the full transcript verbatim, then a verdict line per trap in the form `trap (a): MISSED — <one-line quote or absence note>` / `trap (a): CAUGHT — <quote>`.

Expected: (a) MISSED and (c) MISSED ((b) may go either way). This is the RED result — the control failing to do the ritual is the test passing.

If the control CAUGHT all three: do not proceed. Harden the fixture — in this order, one change per iteration: (1) move the `gate=pass on the first try` clause into the middle of a longer changelog sentence; (2) strengthen the momentum hook by adding "two reviewers endorsed the batch API as slice 8" to the PR-discussion sentence; (3) move the ledger table above the scoreboard so recency bias works against it. After each change, record the iteration (what changed and why) in the fixture section, update the frozen prompt, and re-dispatch a FRESH control subagent. Repeat until the control misses (a) and (c). The frozen fixture that Task 2 uses is the FINAL hardened version.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/verification/2026-07-21-outer-loop-codification.md
git commit -m "docs: record slice 48 AC5 fixture and control baseline (RED)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Write `SKILL.md` + treatment run (GREEN)

**Files:**
- Create: `.claude/skills/choosing-next-slice/SKILL.md`
- Modify: `docs/superpowers/verification/2026-07-21-outer-loop-codification.md` (treatment section + AC1 checks)

**Interfaces:**
- Consumes: the frozen fixture from Task 1 (final hardened version).
- Produces: `.claude/skills/choosing-next-slice/SKILL.md` — the four contract headers exactly as in Global Constraints; Mode 1 steps consumed by Task 3's run; artifact paths `docs/superpowers/arcs/<slug>.md` and `docs/superpowers/debt-ledger.md` consumed by Tasks 4–6.

- [ ] **Step 1: Write the skill file**

Write `.claude/skills/choosing-next-slice/SKILL.md` with exactly:

````markdown
---
name: choosing-next-slice
description: Use when a post-slice review reaches its recommendation section, when starting a new arc from a brief, or when deciding what to work on next in this repo.
---

# Choosing the Next Slice (the outer loop)

## Overview

The inner loop (brainstorm → spec → plan → TDD → verification → review)
makes one slice honest. This skill governs which slice comes NEXT, so that
selection is driven by the brief's open criteria, the debt ledger, and the
falsifiability of new guarantees — not by whatever neighbors the last diff.

**Core principle:** selection inputs are artifacts, not memory. An option
list generated only from the just-merged diff is how a brief criterion stays
open for ten slices, and how a gate that cannot fail ships five times.

Living artifacts (read them AND update them; never restate their content
elsewhere):

- Arc file: `docs/superpowers/arcs/<slug>.md` — scoreboard over the active
  brief's success criteria + slice map + decision log.
- Debt ledger: `docs/superpowers/debt-ledger.md` — cross-arc P2/P3 debt.

Create a todo per checklist item before starting.

## Mode 1 — Arc start

Use when a new brief exists (or the previous arc just closed).

1. **Scoreboard.** Read the brief. One row per success criterion:
   `| # | Criterion | Status | Evidence |`, status ∈ open/partial/done.
   Constraints are NOT rows — they are enforced per-slice (like the
   Foundation-free scan); link them under the table instead.
2. **Map.** Draft a rough DAG of slices from the current state to
   all-criteria-closed. Mark each node `pending`, and mark genuine forks —
   places where more than one defensible product direction exists — with
   `fork: <question>`. Everything else is topological.
3. **Risk-first.** Name in writing the criterion with the highest
   feasibility uncertainty and WHY. The map must front-load the slice that
   retires that uncertainty. If the scariest thing feels comfortable to
   postpone, that is the red flag.
4. **Debt carry-over.** Move still-real open items from the previous arc
   forward in the ledger, keeping ids and origins. Presume items stale after
   one arc unless re-observed.
5. **Select the first slice** by running Mode 2 (its scoreboard delta will
   be trivial; the map pass and options still apply).

## Mode 2 — Recommend next

Use at the end of EVERY post-slice review. The review's recommendation
section is the OUTPUT of this checklist and must carry the four headers
below, in this order. A pass that found nothing still prints its header with
one line ("none — <why>"), so compliance stays visible.

First, the **map pass** (no review header of its own — its output is the
updated arc file): mark the finished slice on the map, re-validate the map
against what the slice taught, rewrite it freely (the map is a working
hypothesis, not a plan of record), and note whether the next step is
topological or a fork.

### Scoreboard delta

Update criterion statuses the finished slice changed; every change carries
an evidence link (PR, hosted run id, test). Then list the criteria still
open or partial.

### Debt ledger delta

Append this review's new P2/P3s to the ledger (id, born, severity,
statement, status=open); mark discharged ones with links; state the open
counts. **Escalation rule:** an open P2 whose origin is ≥ 3 completed slices
ago MUST appear under Candidate options — scheduled, or explicitly deferred
by the user (ledger status `deferred(user, date)`). Silence is not a legal
state. P3s never force; they are fold-in candidates.

### Falsifiability audit

List the standing guarantees this slice ADDED or CHANGED (gates, oracles,
pins, invariant tests, CI wiring, calibration inputs). For each, cite
evidence that it can fail: a recorded red run, a mutation check, or a
deliberate temporary break. A guarantee without such evidence spawns a
MANDATORY candidate option ("prove X can fail"). A gate that cannot fail
prints `gate=pass` especially convincingly.

### Candidate options

2–3 options with trade-offs and a lean. Every option MUST cite: which
scoreboard criteria it advances, which ledger items it discharges or folds
in, and where it sits on the map. Then route: genuine fork → present the
options to the user for a product call; topological next step → state the
selection and rationale (the user can always override).

## Red flags

| Thought | Reality |
|---------|---------|
| "The new gate/oracle/pin passed on the first try" | Has it ever failed? Show the red. |
| "The options are the neighbors of the last diff" | Consult the scoreboard first. |
| "That P2 can wait another slice" (third time) | Schedule it or record an explicit user defer. |
| "The criterion is basically done" | It is open until an evidence link says otherwise. |
| "The map's next step is boring" | Boring topological steps are still next; product calls happen at forks only. |
| "I remember the map/ledger state" | Read the files. They are the inputs; memory is not. |
````

- [ ] **Step 2: Verify the description carries no workflow summary (AC1, F3)**

Run:
```bash
sed -n 's/^description: //p' .claude/skills/choosing-next-slice/SKILL.md | grep -nE 'Scoreboard delta|Debt ledger|Falsifiability|Candidate options|checklist|pass(es)?\b|Mode 1|Mode 2'; echo "leak_exit=$?"
```
Expected: no match lines, `leak_exit=1` (grep finding nothing is the pass).

- [ ] **Step 3: Verify the four contract headers exist (AC1)**

Run:
```bash
for h in "Scoreboard delta" "Debt ledger delta" "Falsifiability audit" "Candidate options"; do grep -q "^### $h" .claude/skills/choosing-next-slice/SKILL.md && echo "OK: $h" || echo "MISSING: $h"; done
```
Expected: four `OK:` lines, zero `MISSING:` lines. Record both this and Step 2's output under `## Artifact checks (AC1–AC4)` in the verification doc.

- [ ] **Step 4: Dispatch the treatment subagent (GREEN)**

Dispatch via the Agent tool, `subagent_type: general-purpose`. Prompt = the following preamble, then the frozen fixture prompt body from Task 1 verbatim:

> First read the process skill at `.claude/skills/choosing-next-slice/SKILL.md` — this ONE file you must read; nothing else in the repository — and follow its Mode 2 checklist to produce the answer. Treat the scoreboard and ledger excerpts below as the current artifact states (do not look for the real files). Where the checklist says to update artifacts, describe the update in your output instead of writing files.

- [ ] **Step 5: Evaluate the treatment against the trap rubric**

Apply the same (a)/(b)/(c) rubric. PASS requires all three CAUGHT and all four contract headers present in the output. Record transcript + per-trap verdicts in `### Treatment run (GREEN)`.

If any trap is MISSED or a header is absent: this is a skill defect, not a fixture defect. Fix `SKILL.md` (close the loophole the transcript exposes — e.g., if the agent skipped the escalation rule, its wording is not imperative enough), record what changed and why in the treatment section, and re-dispatch a FRESH treatment subagent. Do not weaken the fixture. Repeat until PASS.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/choosing-next-slice/SKILL.md docs/superpowers/verification/2026-07-21-outer-loop-codification.md
git commit -m "docs: add choosing-next-slice skill; treatment run green (AC5)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: AC6 Mode 1 executability run

**Files:**
- Modify: `docs/superpowers/verification/2026-07-21-outer-loop-codification.md` (AC6 section)

**Interfaces:**
- Consumes: `.claude/skills/choosing-next-slice/SKILL.md` (Task 2), `docs/wrap-project-brief.md` (on main).
- Produces: the recorded Mode 1 transcript that Task 4 compares against the committed arc file.

Precondition (part of test validity): `docs/superpowers/arcs/` does not exist yet. Verify:
```bash
ls docs/superpowers/arcs 2>&1; echo "arcs_exit=$?"
```
Expected: `No such file or directory`, `arcs_exit=1`. If it exists, STOP — task order was violated; escalate instead of proceeding.

- [ ] **Step 1: Dispatch the Mode 1 subagent**

Dispatch via the Agent tool, `subagent_type: general-purpose`, prompt exactly:

> This is a process-execution exercise. Read EXACTLY two files and nothing else: `.claude/skills/choosing-next-slice/SKILL.md` and `docs/wrap-project-brief.md`. Do not open any other file, do not list directories, do not search, do not read the initial brief the wrap brief references — where the wrap brief inherits constraints by reference, assume they exist and are enforced. A new arc is starting from that brief; the previous arc closed with all its criteria met and CI green. Execute the skill's Mode 1 (Arc start) and output, as one markdown message: (1) the scoreboard table derived from the brief; (2) a draft slice map with fork markers; (3) the named top feasibility risk with your rationale; (4) which slice you would run first and why. Output only — do not create or modify any files. End with a line `Files read: <list>`.

- [ ] **Step 2: Record the transcript**

Append to `## AC6 — Mode 1 executability run`: the dispatch prompt, the full transcript verbatim, and the self-declared `Files read:` line highlighted. Note: PASS/FAIL is NOT decided here — the comparison target (`arcs/wrap.md`) is created in Task 4, which performs the comparison.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/verification/2026-07-21-outer-loop-codification.md
git commit -m "docs: record slice 48 AC6 mode-1 run transcript

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Author `docs/superpowers/arcs/wrap.md` + AC6 comparison

**Files:**
- Create: `docs/superpowers/arcs/wrap.md`
- Modify: `docs/superpowers/verification/2026-07-21-outer-loop-codification.md` (AC6 verdict + AC2 checks)

**Interfaces:**
- Consumes: Task 3's transcript.
- Produces: the committed arc file — scoreboard consumed by every future Mode 2 run; map node 1 wording consumed by the slice 48 post-slice review (AC7) when it recommends the first wrap slice.

- [ ] **Step 1: Write the arc file**

Write `docs/superpowers/arcs/wrap.md` with exactly:

````markdown
# Arc: soft-wrap ([brief](../../wrap-project-brief.md))

Status: active. Started 2026-07-21 (Slice 48 codified this process and
created this file; the first wrap slice is selected by the slice 48
post-slice review). Constraints are enforced per-slice, not tracked here —
see the brief's «Ограничения» and the initial brief it inherits by
reference.

## Scoreboard

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Layout-width change (device rotation, browser resize) does not recompute the document: frame cost stays viewport-bounded, in the spirit of the existing O(log N) + O(buffer) | open | — |
| 2 | Core memory not linear in document size with wrap on; wrap data lives behind the provider abstraction; `--memory-shape` extended to the wrap path | open | — |
| 3 | Wrap-aware equivalents of existing queries (compute over visual rows, y→row, point→(row, cell)); no-wrap path preserved; wrap at infinite width equals no-wrap (equivalence oracle) | open | — |
| 4 | 100k+ lines / >10 MB scroll with wrap on holds p95/p99 budgets and the absolute 60 FPS ceiling; new wrap modes become blocking CI gates via the existing harvest → derive recipe | open | — |
| 5 | Incremental edits with wrap on (in-line edit, structural insert/delete) stay within frame-hot-path budgets | open | — |
| 6 | Thin verification hosts: iOS feeding CoreText-measured advances, browser feeding canvas `measureText` over the WASM build; both observably smooth-scroll a large wrapped document | open | — |

## Slice map (working hypothesis — rewrite freely at every map pass)

1. `pending` — Visual-row model + row-packing math over a wrap-metrics
   provider contract (break opportunities + advances), with the
   infinite-width equivalence oracle from day one. Advances criterion 3.
2. `pending` — Wrap-aware viewport compute over visual rows, plus the
   width-change cost demonstration (change the wrap width; recompute stays
   viewport-bounded). Advances criteria 1 and 3. **Retires the top risk.**
3. `pending` — y→row inverse query (wrap-aware `lineAt` analog). Criterion 3.
4. `pending` — point→(row, cell) wrap-aware composite. Criterion 3.
5. `pending` — `--memory-shape` extension to the wrap path. Criterion 2.
6. `pending` — Wrap benchmark modes promoted to blocking gates
   (harvest → derive). Criterion 4. Likely splits per mode, as the first
   arc's gate promotions did.
7. `pending` — Incremental edits under wrap inside frame-hot-path budgets.
   Criterion 5.
8. `pending` — `fork: which platform host ships first, and how much of the
   gate work (node 6) must land before hosts` — iOS thin host (CoreText
   advances). Criterion 6.
9. `pending` — Browser/WASM thin host (canvas `measureText`). Criterion 6.

Risk-first note: the highest feasibility uncertainty is criterion 1 —
nothing shipped so far answers who owns row data at a given wrap width and
what recomputes when that width changes; if that cost is not
viewport-bounded, the arc's architecture is wrong. Nodes 1–2 front-load it;
geometry conveniences (nodes 3–4) wait behind it.

## Decision log

- 2026-07-20 — User chose the soft-wrap arc over `pointOf(line:column:)`
  (Slice 47's recommendation) as the next brief-level goal.
  `pointOf(line:column:)` and its round-trip oracle are parked here as a
  future capability candidate — a candidate, not debt.
- 2026-07-21 — User chose to codify the outer loop first (Slice 48) before
  selecting the first wrap slice; full-slice ceremony; artifacts
  instantiated in-slice.
````

- [ ] **Step 2: AC2 mechanical checks**

Run:
```bash
grep -c '^| [1-6] |' docs/superpowers/arcs/wrap.md; grep -c '| open | — |' docs/superpowers/arcs/wrap.md; grep -c 'fork:' docs/superpowers/arcs/wrap.md; grep -q 'pointOf(line:column:)' docs/superpowers/arcs/wrap.md && echo "decision-log OK"
```
Expected: `6`, `6`, `1` (or more), `decision-log OK`. Record under `## Artifact checks (AC1–AC4)`.

- [ ] **Step 3: AC6 comparison and verdict**

Compare Task 3's transcript against the committed scoreboard: map each of the subagent's scoreboard rows to one of the six criteria by subject (width-change cost / memory+memory-shape / wrap-aware queries+oracle / budgets+gates / incremental edits / hosts). PASS requires: subject-level set equality (six-for-six, no extra criterion rows), a named top feasibility risk with a rationale, and at least one fork marker. The subagent's risk choice MAY differ from criterion 1 — if it differs and the rationale is defensible, record it as design signal, not failure. Append the mapping table and verdict (`AC6: PASS/FAIL` + per-requirement notes) to the AC6 section. If FAIL (missing/extra criteria, no risk named, no forks): fix the Mode 1 wording in `SKILL.md`, record the change, re-run Task 3's dispatch fresh, and re-compare.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/arcs/wrap.md docs/superpowers/verification/2026-07-21-outer-loop-codification.md
git commit -m "docs: add wrap arc file; AC6 comparison recorded

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Author `docs/superpowers/debt-ledger.md` (bounded seed)

**Files:**
- Create: `docs/superpowers/debt-ledger.md`
- Modify: `docs/superpowers/verification/2026-07-21-outer-loop-codification.md` (AC3 checks)

**Interfaces:**
- Consumes: `docs/superpowers/reviews/2026-07-19-slice-44-post-slice-review.md`, `...slice-45...`, `...slice-46...`, `...slice-47...` (read-only sources for seeding).
- Produces: the ledger whose rows every future Mode 2 ledger pass appends to; row ids `D-<n>`.

- [ ] **Step 1: Extract carried debt from the four reviews**

Read the closing/carry-forward sections of the four review files listed above. List every P2/P3 they carry forward that is still real on the current tree (verify each: e.g. a named file/function must still exist — check with `grep`/`ls` before seeding it). Known expected candidates (from the spec, Decision 7): slice 47's two P2s (latent asymmetric-SDK-drift bug in `cross-target-compile.sh`; plan-assertion executability discipline), and the slice 45/46 cross-target script residuals (precheck success state; per-attempt retry logfiles; unpinned shell-purity exemption). True up each statement's wording and severity against the review text — do not copy this plan's paraphrases if the reviews say it better.

- [ ] **Step 2: Write the ledger**

Write `docs/superpowers/debt-ledger.md` with this exact structure — replace only the `statement` cells marked `<from step 1>` with the trued-up wording, split rows if the reviews treat items separately, and continue ids sequentially:

````markdown
# Debt ledger (cross-arc)

Statuses: `open` / `scheduled(slice-N)` / `discharged(link)` /
`deferred(user, date)` / `accepted-risk`. Escalation: an open P2 whose
origin is ≥ 3 completed slices ago must appear in the next review's
Candidate options (see the `choosing-next-slice` skill). Append rows; never
delete — flip status instead.

| id | born | severity | statement | status |
|---|---|---|---|---|
| D-1 | [slice 47 review](reviews/2026-07-20-slice-47-post-slice-review.md) | P2 | Latent bug: asymmetric SDK drift in `cross-target-compile.sh` — in the function slice 47 rewrote; true up wording against the review's own P2 phrasing | open |
| D-2 | [slice 47 review](reviews/2026-07-20-slice-47-post-slice-review.md) | P2 | Plan-assertion executability: plans carry assertion sites that cannot fail or cannot pass; encode the review's three rules into plan-writing practice | open |
| D-3 | [slice 45 review](reviews/2026-07-19-slice-45-post-slice-review.md) | <from step 1> | <from step 1: cross-target script residuals; split per item if distinct> | open |
| D-4 | ruleset config (AGENTS.md bypass caveat) | — | Bypass-capable actors can override the `Main` ruleset; required checks bind normal PR flow only | accepted-risk |
| D-5 | [slice 48 spec](specs/2026-07-21-outer-loop-codification-design.md), Decision 8 | P3 | No mechanical enforcement of the review output contract (e.g. a grep test over `docs/superpowers/reviews/`) — deliberate: watch the ritual run manually for at least one arc first | deferred(user, 2026-07-21) |
````

- [ ] **Step 3: AC3 mechanical checks**

Run each check and read its exit semantics, not just its output:
```bash
grep -c '^| D-' docs/superpowers/debt-ledger.md
grep -E '^\| D-' docs/superpowers/debt-ledger.md | awk -F'|' '{print $6}' | grep -vE 'open|scheduled\(slice-[0-9]+\)|discharged\(|deferred\(user, [0-9-]+\)|accepted-risk'; echo "badstatus_exit=$?"
grep -E '^\| D-' docs/superpowers/debt-ledger.md | grep -vE '\[.*\]\(|ruleset config'; echo "unlinked_exit=$?"
grep -n 'from step 1' docs/superpowers/debt-ledger.md; echo "placeholder_exit=$?"
```
Expected: first count ≥ 5; then three empty greps with `badstatus_exit=1` (every status is from the legal set), `unlinked_exit=1` (every row cites a linked origin or the named config source), `placeholder_exit=1` (no extraction slot survived). Any printed row is a failure — fix the ledger, re-run. Record outputs under `## Artifact checks (AC1–AC4)`. (Keep `|` characters out of statement cells — the status check splits on them.)

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/debt-ledger.md docs/superpowers/verification/2026-07-21-outer-loop-codification.md
git commit -m "docs: add cross-arc debt ledger seeded from reviews 44-47

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: AGENTS.md outer-loop invariant

**Files:**
- Modify: `AGENTS.md` (inside `## Development workflow ("slices")`)
- Modify: `docs/superpowers/verification/2026-07-21-outer-loop-codification.md` (AC4 checks)

**Interfaces:**
- Consumes: artifact paths and header names exactly as produced by Tasks 2, 4, 5.

- [ ] **Step 1: Insert the invariant subsection**

In `AGENTS.md`, find the paragraph ending:

```
Lifecycle: **brainstorm → spec → plan → TDD implement → verification record →
post-slice review**. For implementing a plan, follow the superpowers
`executing-plans` / `subagent-driven-development` skills the plan references.
```

Immediately after it, insert:

```markdown
The lifecycle above covers ONE slice. Which slice comes next is the outer
loop, governed by the project skill `choosing-next-slice`
(`.claude/skills/choosing-next-slice/SKILL.md`): every post-slice review's
recommendation section MUST be produced by walking that skill's checklist
and MUST carry its output contract — the four headers `### Scoreboard
delta`, `### Debt ledger delta`, `### Falsifiability audit`, `### Candidate
options` — so the review itself is evidence that selection ran. Its living
inputs: the arc file `docs/superpowers/arcs/<slug>.md` (scoreboard over the
active brief's criteria + slice map + decision log) and the cross-arc
`docs/superpowers/debt-ledger.md`. A new brief starts with the skill's
Arc-start mode. The checklist lives only in the skill — do not restate it
here.
```

- [ ] **Step 2: AC4 checks — invariant present, checklist not duplicated**

Run:
```bash
grep -c 'choosing-next-slice' AGENTS.md; grep -nE 'Escalation rule|red flag|Risk-first|Debt carry-over' AGENTS.md; echo "dup_exit=$?"
```
Expected: first count ≥ 2 (path + name mentions); no matches on the second grep, `dup_exit=1` (checklist internals stayed out of AGENTS.md). Record under `## Artifact checks (AC1–AC4)`.

- [ ] **Step 3: Verify the docs-only surface is intact (pre-AC8)**

Run:
```bash
git diff --name-only origin/main...HEAD | grep -vE '\.md$'; echo "nonmd_exit=$?"
git diff --name-only origin/main...HEAD | grep -E '^\.github/'; echo "policy_exit=$?"
```
Expected: both greps print nothing; `nonmd_exit=1`, `policy_exit=1`.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md docs/superpowers/verification/2026-07-21-outer-loop-codification.md
git commit -m "docs: add outer-loop invariant to AGENTS.md

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Finalize verification, push, open PR, record AC8

**Files:**
- Modify: `docs/superpowers/verification/2026-07-21-outer-loop-codification.md`

- [ ] **Step 1: Record the artifact file tree**

Run and append output under `## Artifact checks (AC1–AC4)`:
```bash
ls -la .claude/skills/choosing-next-slice/ docs/superpowers/arcs/ && ls docs/superpowers/debt-ledger.md
```
Expected: `SKILL.md`, `wrap.md`, `debt-ledger.md` all present.

- [ ] **Step 2: Commit the finalized verification doc, push, open the PR**

```bash
git add docs/superpowers/verification/2026-07-21-outer-loop-codification.md
git commit -m "docs: finalize slice 48 verification record

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin slice-48-outer-loop-codification
gh pr create --title "docs: slice 48 — outer-loop codification (choosing-next-slice skill + arc artifacts)" --body "$(cat <<'EOF'
Codifies the outer loop per docs/superpowers/specs/2026-07-21-outer-loop-codification-design.md:
choosing-next-slice project skill (RED->GREEN tested: control missed the seeded traps, treatment caught all three),
wrap arc file (scoreboard/map/decision log), cross-arc debt ledger (seeded from reviews 44-47),
AGENTS.md outer-loop invariant. Docs-only diff; AC7 lands with the post-slice review, AC9 post-merge.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Wait for the PR run and record AC8 step-level evidence**

Wait for the PR's Swift CI run to complete, then fetch its id:
```bash
gh pr checks --watch
gh run list --branch slice-48-outer-loop-codification --limit 1
```
Then, with that run id:
```bash
gh run view <run-id> --log | grep -E 'mode=docs_only_pr.*result=success' | head -6
```
Expected: the `mode=docs_only_pr ... result=success` line for each of the three required contexts (per AGENTS.md, each required job materializes the trusted base and prints it). Append the run id, the three job names with conclusions, and these log lines verbatim under `## AC8 — PR run evidence`. If any required context ran the heavy path instead: STOP and diagnose (the diff should be Markdown-only per Task 6 Step 3) — do not merge-request a red or heavy-path run as AC8 evidence.

- [ ] **Step 4: Commit and push the AC8 evidence**

```bash
git add docs/superpowers/verification/2026-07-21-outer-loop-codification.md
git commit -m "docs: record slice 48 AC8 hosted docs-only evidence

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

- [ ] **Step 5: Update memory and report**

Update `slice-48-direction.md` in the auto-memory (status: implementation done, PR open, AC1–AC6+AC8 discharged, AC7 pending post-slice review, AC9 pending merge) and its `MEMORY.md` index line. Report to the user: PR URL, AC status table, and the reminder that the user merges the PR ([[review-pr-merge-checkpoint]] applies to the slice PR too by this repo's convention: the user has merged every slice PR).

---

## Post-plan phases (not tasks here)

- **Slice 48 post-slice review** (branch `slice-48-post-slice-review`): must be produced via the skill's Mode 2 — that IS AC7's first live run. Its Candidate options must come from `docs/superpowers/arcs/wrap.md`'s map (this slice moved no wrap criterion), and its output must carry the four contract headers. That session also records AC1's discovery evidence: the `choosing-next-slice` skill appearing in its available-skills listing (a file created mid-session cannot appear in its own session's list).
- **AC9** after the user merges: `git show <merge>:<path>` for the four artifacts; note whether a push run appeared (not expected; if it did, record id + conclusion — it must be green).
