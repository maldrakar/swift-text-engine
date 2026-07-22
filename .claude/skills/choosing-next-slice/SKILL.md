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
