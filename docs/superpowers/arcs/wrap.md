# Arc: soft-wrap ([brief](../../wrap-project-brief.md))

Status: active. Started 2026-07-21 (Slice 48 codified this process and
created this file). Slice 48 merged 2026-07-22 (PR #112, merge `a183205`);
its post-slice review is the first live Mode 2 run and selects Slice 1 below
as the lean. Constraints are enforced per-slice, not tracked here — see the
brief's «Ограничения» and the initial brief it inherits by reference.

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

Map pass 2026-07-22 (Slice 48 review, first live Mode 2): Slice 48 was a
process slice and consumed no map node; nodes 1–9 stand unchanged and are
re-validated — nothing that shipped this slice touched wrap feasibility, so
the working hypothesis is unrevised. The next step is **topological**, not a
fork: node 1 (visual-row model) is the forced prerequisite for everything
downstream, and the first genuine fork is node 8 (host-platform order).
Node 1 is the lean.

## Decision log

- 2026-07-20 — User chose the soft-wrap arc over `pointOf(line:column:)`
  (Slice 47's recommendation) as the next brief-level goal.
  `pointOf(line:column:)` and its round-trip oracle are parked here as a
  future capability candidate — a candidate, not debt.
- 2026-07-21 — User chose to codify the outer loop first (Slice 48) before
  selecting the first wrap slice; full-slice ceremony; artifacts
  instantiated in-slice.
- 2026-07-22 — Slice 48 merged (PR #112, `a183205`); its post-slice review
  ran the first live Mode 2. Lean for the next slice: node 1 (visual-row
  model + row-packing + infinite-width equivalence oracle). The three infra
  P2s D-7/D-8/D-9 escalated (origins ≥ 3 slices old) and are surfaced for a
  user schedule-or-defer product call — see that review's Candidate options.
