# Slice 48 — post-slice review (outer-loop codification)

- **Slice:** 48 — outer-loop codification
- **Merged:** 2026-07-22, PR #112, merge commit `a183205`
- **This review:** first live run of the `choosing-next-slice` skill's **Mode 2**
  (AC7). The recommendation section below is the skill's output contract — the
  four `###` headers, map pass first — not free prose.
- **Reviewed range:** `main` before #112 → `a183205` (all-Markdown slice: the
  `choosing-next-slice` skill, `arcs/wrap.md`, `debt-ledger.md`, the AGENTS.md
  outer-loop invariant, spec/plan/verification).

## What shipped

Slice 48 codified the **outer loop** — how the *next* slice is chosen — after the
retro that closed the initial brief. It was deliberately all-Markdown (zero
Swift/CI/script change) and was built and RED→GREEN-tested via
subagent-driven-development. Deliverables:

- `.claude/skills/choosing-next-slice/SKILL.md` — Mode 1 (arc start) + Mode 2
  (recommend next), output contract = four fixed headers.
- `docs/superpowers/arcs/wrap.md` — soft-wrap scoreboard (6 criteria), 9-node
  slice map, decision log.
- `docs/superpowers/debt-ledger.md` — cross-arc P2/P3 ledger seeded from
  reviews 44–47 (11 rows).
- `AGENTS.md` — outer-loop invariant (pointer style; the checklist lives only
  in the skill).

## Acceptance-criteria status

| AC | Statement | Status | Evidence |
|---|---|---|---|
| AC1 | skill file + can't-fail checks | ✅ | `leak_exit=1`, four `###` headers present; the skill even surfaced in its own implementing session's skill listing |
| AC2 | `arcs/wrap.md` present + shaped | ✅ | 6 criteria / 9 map nodes / risk-first note / decision log; byte-identical to plan block |
| AC3 | `debt-ledger.md` present + shaped | ✅ | 11 rows, escalation rule stated, all grep shape-checks clean |
| AC4 | AGENTS.md outer-loop invariant (no checklist dup) | ✅ | 2 skill mentions, pointer style, dup-check exit=1 |
| AC5 | control vs treatment RED→GREEN | ✅ | 4 control runs missed traps (a)+(c); treatment caught them first run — verification doc control/treatment transcripts |
| AC6 | Mode 1 executability | ✅ | 6-of-6 criteria mapped, risk = criterion 1 (matched), fork markers present |
| **AC7** | **first live Mode 2 run** | ✅ | **this review** |
| AC8 | hosted docs-only fast path | ✅ | PR run `29929826808` (3× `mode=docs_only_pr … result=success`) + map-first amendment run `29946076997` (green) |
| **AC9** | **post-merge tree check + push-run note** | ✅ | all four artifacts present at `a183205`; **no post-merge push run** (docs-only `paths-ignore` skip — `gh run list --commit a183205` empty); the two PR runs above are the hosted evidence |

All nine ACs discharged.

## Strengths

- **The test was a real RED→GREEN, not a self-congratulating GREEN.** AC5 stood
  up four control runs (no skill) that genuinely failed the ritual before the
  treatment passed — the falsifiability discipline the skill itself now
  mandates, applied to the skill's own introduction.
- **Living inputs are files, not memory.** The arc scoreboard and the ledger
  are on disk and were read fresh for this recommendation; the map-first
  ordering means the map is re-validated before any option cites "where on the
  map."
- **Honest paper trail.** The verification doc records the (c)-trap flip as
  control *variance* rather than a fixture property, discloses the one
  transport-escape restoration in a "verbatim" transcript, and the spec↔skill
  map-pass divergence was surfaced and resolved (map-first, commit `72998d2`)
  rather than papered over.

## Issues

**Critical:** none. **Important:** none. (The SDD whole-branch review returned
READY with zero Critical/Important; 10 carried Minors were triaged CARRY —
doc-polish only, below ledger threshold.)

**Minor (carried, not blocking):**

- The four-header contract has **no mechanical enforcement** — a future review
  could silently drop a header or emit `##`. This is a *known, user-accepted*
  gap, already tracked as **D-5** `deferred(user, 2026-07-21)`: watch the ritual
  run manually for at least one arc before adding a grep test. This review is
  arc-run #1 of that watch.

---

# Recommendation (skill Mode 2 — first live run)

*Map pass ran first; its output is the updated `arcs/wrap.md` (Slice 48 marked
as a process slice consuming no node; nodes 1–9 re-validated unchanged; next
step is **topological** → node 1; first fork is node 8).*

### Scoreboard delta

**None — Slice 48 moved no wrap-brief criterion.** It was a process slice; it
advances the *selection machinery*, not the soft-wrap engine. All six criteria
remain **open** (see `arcs/wrap.md` scoreboard). This is the expected shape: the
first live Mode 2 run had to recommend from the arc **map**, not from a criterion
this slice advanced — and it does (node 1 below).

### Debt ledger delta

**New this review:** none. Slice 48 was clean (zero Critical/Important); the one
standing process-enforcement gap is already **D-5** (deferred by user). No P2/P3
born, none discharged.

**Open counts:** 5 open P2 (D-1, D-2, D-7, D-8, D-9) · 4 open P3 (D-3, D-6,
D-10, D-11) · 1 deferred P3 (D-5) · 1 accepted-risk (D-4).

**Escalation rule fires — three P2s, by construction of the seed.** An open P2
whose origin is ≥ 3 completed slices ago MUST appear under Candidate options,
scheduled or explicitly user-deferred; silence is not a legal state. At this
first Mode 2 run three qualify (age measured from each row's "carried since"
origin, not its slice-46/47 born-cell):

| id | statement (short) | carried since | completed-slices-ago |
|---|---|---|---|
| D-7 | harvester provenance gap (no conclusion/event/fork check) | slice 42 | 6 |
| D-8 | bulk-edit absolute-ceiling backstop (needs a product target) | slice 43 | 5 |
| D-9 | p95 thin axis when the windowed 3×-max floor relaxes | slice 41 | 7 |

All three are surfaced under Candidate options below. D-1/D-2 (born slice 47,
1 slice ago) do **not** yet escalate; P3s never force.

### Falsifiability audit

Slice 48 added a **process** guarantee — the outer-loop ritual (the four-header
recommendation contract, driven by the skill) — **not** a runtime gate, oracle,
or pin. Its can-fail evidence:

- **Recorded red:** AC5's four control runs (skill absent) *failed* the ritual —
  they generated greedy diff-neighbor option lists and missed the seeded traps
  (a) a new gate with no can-fail evidence and (c) an aged P2 needing
  schedule-or-defer. The treatment (skill present) caught them. That is the
  ritual demonstrably failing without the skill. Honest caveat, per the
  verification doc: the trap-(c) flip was partly control *variance*, not a hard
  fixture property; trap (a) was robustly missed across all four runs.
- **Live exercise:** this Mode 2 run is the first application of the guarantee
  to a *real* review rather than a synthetic fixture — and it did fire the
  escalation rule against the real ledger (three P2s above), which is the
  behavior the control runs lacked.

No guarantee here is un-falsifiable, so **no mandatory "prove X can fail"
option** is spawned. The gap that remains is *mechanical enforcement* of the
contract (a guarantee can-fail ≠ a guarantee auto-checked) — already tracked as
**D-5**, `deferred(user, 2026-07-21)`, not re-opened here.

### Candidate options

This is a genuine **fork**: the escalation forces a user decision on three
carried P2s, and "open the wrap arc now" vs "pay down infra debt first" is a
product direction. Each option cites the criteria it advances, the ledger items
it touches, and its map position.

- **Option A (lean) — Open the wrap arc at node 1 + explicitly defer
  D-7/D-8/D-9.** Ship the visual-row model + row-packing math over a
  wrap-metrics provider contract, with the **infinite-width equivalence oracle**
  (wrap at ∞ width ≡ no-wrap) from day one.
  - *Advances:* criterion **3** (wrap-aware queries / equivalence oracle).
  - *Map:* node **1** — the forced topological root; risk-first front-loads
    criterion 1 via nodes 1–2, and node 1 is node 2's prerequisite.
  - *Ledger:* discharges none; **explicitly defers D-7/D-8/D-9** with recorded
    rationale (D-7 latent — no fork-PR exploit path under the current trusted-CI
    model; D-8 *cannot* be scheduled without a product-target decision the user
    must supply; D-9 is a watch-item that self-heals as pre-slice-45 rows age
    out of the N=20 window). Recording `deferred(user, 2026-07-22)` on the three
    satisfies the escalation rule via explicit user defer.
  - *Why lean:* the user already chose the wrap arc as the brief-level goal
    (decision log 2026-07-20); node 1 opens it at its root, and its equivalence
    oracle is the day-one falsifiable guarantee the whole arc rests on. Pattern
    proven ~12× in this codebase (provider contract + equivalence oracle).

- **Option B — Interleave one infra-debt slice first: discharge D-7 (harvester
  provenance).** Add a conclusion/event/fork guard to `harvest-gate-corpus.sh`
  plus a selection-logic self-test.
  - *Advances:* no wrap criterion. *Ledger:* **discharges D-7** (the only
    escalated P2 that needs no product decision). *Map:* off the wrap map
    (cross-arc infra).
  - *Why consider:* D-7 is the single unverified link in the twelve-gate
    calibration chain; if we schedule rather than defer one escalated P2, this
    is the one that is fully actionable today.

- **Option C — Take on D-8 (bulk-edit absolute backstop).** Surfaced only
  because the escalation names it; **not** drop-in. It needs a product-target
  decision first (what latency budget a bulk paste / range-delete may spend, and
  whether it is even a frame-hot-path op), so it would open with its own
  brainstorm + spec, not a plan. Lowest priority of the three unless the user
  wants to settle that target now.

**Routing — fork → user product call.** Lean is **A** (open wrap at node 1; user
explicitly defers D-7/D-8/D-9 with the rationale above). If you would rather pay
down one escalated P2 before touching wrap, that is **B** (D-7, no product input
needed). **C** only if you want to decide the bulk-edit target now. On your call
I will (i) draft the node-1 slice via `brainstorming` → spec → plan, and
(ii) stamp the ledger — `deferred(user, 2026-07-22)` on the deferred rows, or
`scheduled(slice-49)` on whichever P2 you elect to pay down.
