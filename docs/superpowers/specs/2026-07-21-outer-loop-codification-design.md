# Slice 48 — Codify the outer loop: `choosing-next-slice` skill + living arc artifacts

## Summary

Codify the slice-selection process (the "outer loop") that until now lived in
per-review narrative and session memory. Four deliverables, all Markdown:

1. A project skill, `.claude/skills/choosing-next-slice/SKILL.md`, with two
   modes: **Arc start** (brief → scoreboard, map, risk-first ordering) and
   **Recommend next** (the checklist every post-slice review's recommendation
   section must be produced by).
2. A living arc file, `docs/superpowers/arcs/wrap.md`: scoreboard over the wrap
   brief's success criteria + slice map + decision log.
3. A living cross-arc debt ledger, `docs/superpowers/debt-ledger.md`, seeded
   bounded (reviews 44–47 + known standing residuals).
4. An `AGENTS.md` invariant making the skill's output contract mandatory for
   every post-slice review's recommendation section.

The wrap-arc artifacts are instantiated in this same slice: that instantiation
**is** the skill's first Mode 1 execution and its live test. Zero Swift, zero
CI/workflow change, docs-only PR.

## Motivation — brief alignment

The initial brief closed at Slice 47 (validated 2026-07-20: every success
criterion carries fresh evidence). The wrap brief (`docs/wrap-project-brief.md`,
merged as PR #111) opens a new arc. Before starting it, fix the selection
process itself. Three defects were observed across the first arc, each with
receipts:

1. **Greedy option lists.** Candidate options were generated from the
   just-merged slice's vantage — promote the gate just built, add the symmetric
   query. The chain was coherent, but nothing forced reconciliation against the
   brief: the criterion "regression benchmarks block merge" became *fully* true
   only at Slices 45 (realistic mode first ran under `--gate`), 46 (WASM went
   blocking), and 47 (ruleset caught up). Nobody decided to defer those; "which
   brief criteria are still open" was simply never a mandatory input.
2. **Invisible debt classes cannot appear in an option list.** Hand-typed
   starter budgets ran 815×–3,000× loose across Slices 27–37 — five slices in
   which no gate could fail, while every one of those slices passed its inner
   loop honestly (`gate=pass` from a gate that cannot fail prints especially
   convincingly). Per-slice review sees the delta; this rot lived in the
   *standing* system. The repo's standing-test response (GateFloorTests,
   reproduce-from-corpus, window pins, WorkflowShapeTests) was correct but
   reactive. "Plan assertions must be able to fail" (Slice 47's process lesson)
   is the same disease at the plan layer — this is a systemic class.
3. **Debt lived in narrative.** P2/P3s were carried in review prose and session
   memory ("do it in Slice 40" — actually done in 41). It worked, at the cost of
   archaeology.

The outer loop already exists (post-slice review recommends options A/B/C with
a lean; the user makes product calls at forks; memory carries direction). Its
skeleton is sound. This slice codifies its **inputs** so they cannot be skipped
by forgetting.

## Background — current state

- **Recommendation format today**: the Slice 47 review ends with "Slice 48
  Candidate Options" (A/B/C, trade-offs, recommendation) and carries two P2s
  forward in prose. Good bones; implicit inputs.
- **No project skills exist**: `.claude/` holds only `settings.local.json`.
- **Pointer-style precedent**: `AGENTS.md` already defers process authority to
  superpowers skills ("follow the superpowers `executing-plans` /
  `subagent-driven-development` skills the plan references").
- **The enforcement property**: a project skill appears in every session's
  available-skills list with a trigger description, and the `using-superpowers`
  meta-rule compels invocation when a skill applies — the same mechanism that
  makes brainstorming/TDD non-optional. A process doc under `docs/` has no such
  property; it works only if the review author remembers to open it, which is
  exactly the failure mode being eliminated.
- **Live example of local-vantage selection**: Slice 47's recommendation
  (`pointOf(line:column:)`) was superseded by the arc boundary. It must be
  parked visibly (arc decision log), not lost.
- The 580 µs comment residual tracked since Slice 44 was de-rotted by Slice 47
  (verified: no occurrence in `BenchmarkModels.swift` / `AGENTS.md`) — it does
  **not** seed the ledger.

## Design decisions

### Decision 1 — A skill, not an AGENTS.md section or a process doc

Chosen for the enforcement property above. `AGENTS.md` gets a short invariant +
paths, never a second copy of the checklist: the skill is the single authority,
so the two cannot drift.

### Decision 2 — One skill, two modes

Arc start happens once per brief; recommend-next happens every slice. Same
discipline, shared artifacts — splitting them into two skills would double the
frontmatter surface for no isolation gain.

### Decision 3 — The review's recommendation section IS the skill's output contract

Fixed, grep-able headers, in this order:

```
### Scoreboard delta
### Debt ledger delta
### Falsifiability audit
### Candidate options
```

followed by the recommendation/routing as today. A review missing a header is
visibly non-compliant on sight. This is "verification is evidence, not
assertion" applied to the process itself: the review becomes evidence that
selection ran, not an assertion that it did. Passes that found nothing print
one line ("Scoreboard delta: none — no wrap criterion moved"), so the ritual
stays cheap on quiet slices.

### Decision 4 — P2 escalation is a rule, not a vibe

An open ledger P2 whose origin slice is ≥ 3 completed slices ago MUST appear in
the candidate options: either scheduled (as its own option or an explicit
fold-in) or explicitly deferred by the user (recorded in the ledger as
`deferred(user, date)`). Silence is not a legal state. P3s never force; they are
fold-in candidates only. (Calibration: the ratchet P2 born in Slice 38 waited
three slices; the rule makes that the ceiling, not the norm.)

### Decision 5 — Falsifiability audit is bounded to this slice's delta

The audit enumerates standing guarantees **added or changed by the just-finished
slice** (gates, oracles, pins, invariant tests, CI wiring, calibration inputs).
For each, it cites evidence that the guarantee *can fail*: a recorded red run, a
mutation check, or a deliberate temporary break. A guarantee without such
evidence spawns a mandatory candidate option ("prove X can fail"). Bounding the
audit to the delta keeps it O(slice), not O(repo); the loose-budget incident is
exactly what an unbounded version would have needed five slices earlier, and the
bounded version catches it at birth — the budgets were *added* by the slices
that shipped them.

### Decision 6 — The arc map is a working hypothesis, not a plan of record

The map is re-validated by every Map pass and rewritten freely as knowledge
lands. Fork markers separate genuine product calls (user decides) from
topological steps (agent selects, user can override). The arc file is living and
therefore undated — dated files in `docs/superpowers/` are immutable records.

### Decision 7 — Ledger seeding is bounded

Seed from the Slice 44–47 post-slice reviews plus known standing residuals
(bypass-capable ruleset actors → `accepted-risk`). Known candidates going in:
Slice 47's two carried P2s (latent asymmetric-SDK-drift bug in
`cross-target-compile.sh`; plan-assertion executability discipline) and the
Slice 45/46 cross-target script residuals its reviews name (precheck success
state, per-attempt retry logfiles, unpinned shell-purity exemption). The
implementation step re-reads those four reviews and takes what is still real;
older P3s are presumed stale and re-enter only by being re-observed.

### Decision 8 — No mechanical enforcement of review shape (deliberate)

No grep-test over `docs/superpowers/reviews/` yet: watch the ritual run manually
for at least one arc first. The possibility is recorded in the ledger as a
deliberate deferral, so it ages visibly instead of being forgotten.

## Skill content (normative)

Frontmatter: `name: choosing-next-slice`; description triggers on (a) a
post-slice review reaching its recommendation section, (b) starting a new
arc/brief, (c) any "what should we work on next" decision — and contains ONLY
those triggers: never the pass list, never the four contract headers.
writing-skills' rule "Description = When to Use, NOT What the Skill Does"
documents the trap: a description that summarizes workflow becomes a shortcut
the agent follows instead of reading the body — for this skill that would be
an agent printing four empty contract headers while skipping the passes, the
precise defect the skill exists to treat. Body instructs
creating a todo per checklist item (superpowers convention). Language: English,
like every process doc in this repo; brief criteria may be quoted in Russian.

**Mode 1 — Arc start** (a new brief exists / the previous arc closed):

1. Read the brief. Decompose its success criteria into the scoreboard: one row
   per criterion, columns status (`open`/`partial`/`done`) + evidence link.
   Constraints are not rows — they are enforced per-slice (like the
   Foundation-free scan); the arc file links them.
2. Draft the slice map: a rough DAG from current state to all-criteria-closed,
   marking genuine forks vs topological steps.
3. Risk-first ordering: name in writing the criterion with the highest
   feasibility uncertainty; the map must front-load the slice that retires it.
4. Carry surviving debt from the previous arc into the ledger, each with origin.
5. Select the first slice by running Mode 2.

**Mode 2 — Recommend next** (every post-slice review's recommendation section):

1. **Scoreboard pass** — update statuses changed by this slice, with evidence
   links; list criteria still open.
2. **Ledger pass** — append this review's new P2/P3s; mark discharged ones;
   state open counts; apply the Decision 4 escalation rule.
3. **Falsifiability audit** — per Decision 5.
4. **Map pass** — mark the finished slice; re-validate the map against new
   knowledge; update it; state whether the next step is topological or a fork.
5. **Candidate options** — 2–3 options with trade-offs and a lean, as today;
   each option must cite which scoreboard criteria it advances, which ledger
   items it discharges or folds in, and where it sits on the map. An option
   list whose every entry is a neighbor of the last diff and none references an
   open criterion is a red flag (greedy selection).
6. **Routing** — fork → present options for a user product call (as today);
   topological → state the selection and rationale; the user can always
   override.

**Red flags table** (house style), at minimum:

| Thought | Reality |
|---|---|
| "The new gate/oracle/pin passed first try" | Has it ever failed? Show the red. |
| "Options are the neighbors of the last diff" | Consult the scoreboard first. |
| "That P2 can wait another slice" (3rd time) | Schedule it or get an explicit defer. |
| "The criterion is basically done" | It is `open` until an evidence link says otherwise. |
| "The map's next step is boring" | Boring topological steps are still next; product calls happen at forks only. |

## Artifact formats (normative)

**`docs/superpowers/arcs/wrap.md`** — header (brief link, arc status, started
date), then:

1. *Scoreboard*: `| # | Criterion | Status | Evidence |` — six rows from the
   wrap brief: (1) layout-width change costs stay viewport-bounded (no
   full-document recompute); (2) core memory not linear with wrap on;
   `--memory-shape` extended to the wrap path; (3) wrap-aware equivalents of
   existing queries (compute over visual rows, y→row, point→(row, cell)),
   no-wrap path preserved, infinite-width equivalence oracle; (4) 100k+/10MB
   wrapped scroll holds p95/p99 budgets + the absolute 60 FPS ceiling; new wrap
   modes become blocking gates via the existing harvest → derive recipe;
   (5) incremental edits with wrap on stay within frame-hot-path budgets;
   (6) thin verification hosts: iOS feeding CoreText-measured advances, browser
   feeding canvas `measureText` over the WASM build, both observably smooth.
   All start `open` with empty evidence cells.
2. *Slice map*: ordered list/DAG; each entry `status`
   (`pending`/`in-progress`/`done`/`dropped`) + fork marker where a product
   call is expected. Content is drafted during implementation by executing
   Mode 1 (this spec fixes the format, not the map).
3. *Decision log*: dated one-liners. Seeded with: 2026-07-20 — user chose the
   wrap arc over `pointOf(line:column:)` as the next brief-level goal; `pointOf`
   + round-trip oracle parked here as a future capability candidate (it is not
   debt).

**`docs/superpowers/debt-ledger.md`** — cross-arc, one table:
`| id | born | severity | statement | status |` where `born` links the origin
review and `status` ∈ `open` / `scheduled(slice-N)` / `discharged(link)` /
`deferred(user, date)` / `accepted-risk`. Seeded per Decision 7, plus the
Decision 8 deferral.

**`AGENTS.md`** — in `## Development workflow ("slices")`, a short subsection
stating: the lifecycle has an outer loop; every post-slice review's
recommendation section MUST be produced by walking the `choosing-next-slice`
skill and MUST carry its output contract (the four headers of Decision 3);
living artifacts live at `docs/superpowers/arcs/<slug>.md` and
`docs/superpowers/debt-ledger.md`. Pointer style — no checklist duplication.

## Change set

1. `.claude/skills/choosing-next-slice/SKILL.md` — new.
2. `docs/superpowers/arcs/wrap.md` — new; Mode 1 executed for real.
3. `docs/superpowers/debt-ledger.md` — new; seeded per Decision 7.
4. `AGENTS.md` — outer-loop invariant subsection.
5. `docs/superpowers/verification/2026-07-21-outer-loop-codification.md` — new.
6. Memory — Slice 48 direction note + index line.

## Acceptance criteria

1. **AC1** — `.claude/skills/choosing-next-slice/SKILL.md` exists with valid
   frontmatter (name + a description carrying the three triggers and nothing
   else — no workflow summary, per the normative description constraint), both
   modes, the red-flags table, and the output contract. (Fresh-session
   discovery evidence lands in the Slice 48 post-slice-review session — a new
   session by convention — and is recorded there; a file created mid-session
   cannot appear in its own session's skill list.)
2. **AC2** — `docs/superpowers/arcs/wrap.md` exists; scoreboard has exactly the
   six brief criteria, all `open`; the map front-loads the width-change/resize
   feasibility risk and marks at least one genuine fork; the decision log
   contains the wrap-over-`pointOf` entry.
3. **AC3** — `docs/superpowers/debt-ledger.md` exists; every seeded row cites
   an origin review; every status is from the legal set; the Decision 8
   deferral is present.
4. **AC4** — `AGENTS.md` carries the invariant, pointer-style: it names the
   skill and the four contract headers but does not duplicate checklist steps.
5. **AC5** — Mode 2 control-vs-treatment test. One synthetic scenario whose
   traps are seeded in the stub *data*, not the task framing — the task given
   to both subagents is only "produce the recommendation section". Stub
   artifacts (scoreboard and ledger states) are inlined in the prompt so the
   test exercises the checklist rather than tripping on missing files. Three
   traps: (a) the slice added gate Y, which passed on its first run, no red
   run recorded; (b) the stub scoreboard carries an open criterion the slice
   did not touch, while the slice summary offers a tempting diff-neighbor
   continuation; (c) the stub ledger carries a P2 born four slices ago, still
   open.
   *Control (RED)*: a fresh subagent gets scenario + stubs, **no skill**.
   Expected: it misses at least (a) and (c). If the control surfaces all
   three traps, the scenario is too easy and MUST be hardened until the
   control fails — a test the control passes discriminates nothing.
   *Treatment (GREEN)*: a fresh subagent gets the same inputs plus the skill.
   PASS requires all three: the falsifiability audit flags gate Y and the
   options include proving it can fail; the options cite the open criterion
   rather than only diff neighbors; the escalation rule surfaces the aged P2
   as schedule-or-defer. Both transcripts land verbatim in the verification
   doc; a treatment run missing any trap is a FAIL and blocks the slice.
6. **AC6** — Mode 1 executability test (skill given, deliberately no
   control): a fresh subagent, given the skill and
   `docs/wrap-project-brief.md`, executes Arc start. PASS: its scoreboard
   extracts the same six criteria as AC2's (set equality — mechanical), it
   names a top feasibility risk with a rationale, and it marks at least one
   fork. Its risk choice may differ from the committed one: a defensible
   divergence is recorded in the verification doc as design signal, not
   failure. Why no control: an agent without the skill cannot spontaneously
   produce this ritual, so a Mode 1 control could not pass — and a test that
   cannot pass proves nothing (the plan-assertion lesson, mirrored). Mode 1's
   discriminating question is executability by a non-author; that is what
   this AC tests.
7. **AC7** — The Slice 48 post-slice review's recommendation section is
   produced by Mode 2 (first live run): all four contract headers present, and
   — since this slice moves no wrap criterion — the recommended next slice
   comes from the arc map, not from this slice's diff.
8. **AC8** — The PR diff touches only Markdown outside policy-sensitive
   directories; all three required contexts print
   `mode=docs_only_pr ... result=success` at step level on the PR run.
9. **AC9** — After the user merges, the main tree contains all four artifacts
   (`git show` on the merge commit), and the memory index carries a Slice 48
   direction note. The PR run is the hosted evidence for this slice. A
   post-merge push run is *not expected* — `push.paths-ignore` (`docs/**`,
   `**/*.md`) covers every changed path, and the three most recent docs-only
   merges (257fc6f, 34c7fb1, e6cfa54) produced no push run (verified
   2026-07-22 via `gh run list`) — but the skip is not a success condition
   and a run's appearance is not a failure: if one does appear, it must be
   green, and it is recorded. Those three precedents were all skipped by
   `docs/**` alone; this merge is the first push whose skip relies on
   `**/*.md` for non-docs paths (`AGENTS.md`, `.claude/**`) — exactly why
   this AC must not hinge on the skip happening.

## Non-goals / out of scope

- No Swift, no CI/workflow/script changes, no budget or corpus changes.
- No mechanical enforcement of review shape (Decision 8 — deferred visibly).
- No full-history debt archaeology (Decision 7 — bounded to reviews 44–47).
- No backfilled arc file for the closed initial arc.
- The arc map is not a commitment; slices beyond the first are hypotheses.

## Verification plan

Recorded in `docs/superpowers/verification/2026-07-21-outer-loop-codification.md`:

- File tree of the four artifacts (`ls` output).
- `grep` of the AGENTS.md invariant and of the four contract headers in the
  skill.
- AC5 control and treatment transcripts (verbatim) with PASS/FAIL verdicts,
  plus any scenario-hardening iterations the calibration clause forced.
- AC6 Mode 1 transcript with the criteria-set comparison and the risk-choice
  divergence note, if any.
- PR run: three required contexts' step-level `mode=docs_only_pr` lines
  (`gh run view --log` excerpts), per AC8.
- Post-merge: `git show <merge>:<path>` for the four artifacts, per AC9; if a
  push run appeared, its id and conclusion.

## Risks & trade-offs

- **Ritual overhead on quiet slices** → contract passes collapse to one line
  each when nothing changed; the expensive passes only spend effort when their
  input changed.
- **Skill/AGENTS.md drift** → single-authority split (Decision 1): the
  checklist lives in exactly one place.
- **Map ossification** → Decision 6 makes re-validation a mandatory pass, and
  the map's non-commitment status is stated in the file itself.
- **Ledger becomes a graveyard** → Decision 4 escalation forces
  schedule-or-defer; `deferred` requires a user + date, so even deferrals age
  visibly.
- **Self-referential first test** (the slice validating its own process) →
  AC5's control-vs-treatment test injects trap scenarios the checklist must
  catch independently of this slice's happy path, with a no-skill baseline
  proving the skill — not agent common sense — causes the catch; AC7's live
  run has a non-self-serving success condition (the recommendation must come
  from the map, because the diff offers no wrap-criterion neighbor).

## Next step

`superpowers:writing-plans` → task-by-task implementation plan
(`docs/superpowers/plans/2026-07-21-outer-loop-codification.md`). The plan
MUST structure the skill work RED → GREEN → REFACTOR per writing-skills' Iron
Law ("NO SKILL WITHOUT A FAILING TEST FIRST", explicitly covering new skills):
author the AC5 scenario + stubs and record the failing control runs **before**
`SKILL.md` exists; write the skill; record the passing treatment and AC6 runs;
then close whatever loopholes the transcripts expose. The normative sections
above are design input to the GREEN step, not a license to write the artifact
first.
