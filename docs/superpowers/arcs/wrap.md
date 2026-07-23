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
| 3 | Wrap-aware equivalents of existing queries (compute over visual rows, y→row, point→(row, cell)); no-wrap path preserved; wrap at infinite width equals no-wrap (equivalence oracle) | partial | Per-line equivalence oracle proven (wrap at ∞/≥total width = one whole-line row = no-wrap column model, over irregular advances+breaks) + no-wrap path untouched — [PR #114](https://github.com/maldrakar/swift-text-engine/pull/114) (`8e91f52`), post-merge run `29990966569`, `VisualRowEquivalenceTests`. Remaining: the query analogs (compute/y→row/point) and the whole-document equivalence half |
| 4 | 100k+ lines / >10 MB scroll with wrap on holds p95/p99 budgets and the absolute 60 FPS ceiling; new wrap modes become blocking CI gates via the existing harvest → derive recipe | open | — |
| 5 | Incremental edits with wrap on (in-line edit, structural insert/delete) stay within frame-hot-path budgets | open | — |
| 6 | Thin verification hosts: iOS feeding CoreText-measured advances, browser feeding canvas `measureText` over the WASM build; both observably smooth-scroll a large wrapped document | open | — |

## Slice map (working hypothesis — rewrite freely at every map pass)

1. `done` (Slice 49) — Visual-row model + row-packing math over a wrap-metrics
   provider contract (break opportunities + advances), with the
   infinite-width equivalence oracle from day one. Advanced criterion 3
   (per-line half). Per-line packing only; cross-line aggregation is node 2.
2. `pending` — **← next (lean).** Wrap-aware viewport compute over visual rows,
   plus the width-change cost demonstration (change the wrap width; the *core*
   per-frame compute stays viewport-bounded — O(log N), width-independent).
   Advances criteria 1 and 3. **Retires the top risk's core half.** Criterion 1
   reaches only `partial`: the *exact* width-change reindex is Ω(N) (see the
   risk-first note) and closing criterion 1 to `done` needs the veneer fork below,
   not this node.
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
V. `pending` — **fork (not yet a numbered node): the estimated/async width-change
   veneer** over the exact index space that closes criterion 1 from `partial` to
   `done`. Required because a *full* width change is Ω(N) (every multi-row line's
   count changes — no structure makes the *exact* reindex sublinear); a bounded
   rotation/resize frame therefore needs an estimated total extent and/or off-frame
   reindex layered on top of node 2's exact index — a deliberate re-entry into the
   A/B fork as a *layer*, not an "incremental exact reindex" (which is impossible).
   Criterion 6's smooth-scroll hosts may force this fork's timing.

Risk-first note: the highest feasibility uncertainty is criterion 1 —
who owns row data at a given wrap width and what recomputes when that width
changes. Node 2 answers the ownership half (the provider owns the visual-row
prefix sum) and proves the *core* per-frame compute is viewport-bounded and
width-independent. But the width-change *event* itself is irreducibly **Ω(N)**
for an exact total extent (every multi-row line changes) — so criterion 1 cannot
reach `done` by "incrementalizing" the reindex; no node can make Ω(N) sublinear.
`done` requires the estimated/async **veneer** (fork V above) over node 2's exact
index. Until then criterion 1 is `partial`, and that is honest, not a gap a later
node quietly closes. Nodes 1–2 front-load the ownership/core-cost half; geometry
conveniences (nodes 3–4) wait behind node 2; the veneer fork is sequenced by when
a host needs a bounded resize frame.

Map pass 2026-07-22 (Slice 48 review, first live Mode 2): Slice 48 was a
process slice and consumed no map node; nodes 1–9 stand unchanged and are
re-validated — nothing that shipped this slice touched wrap feasibility, so
the working hypothesis is unrevised. The next step is **topological**, not a
fork: node 1 (visual-row model) is the forced prerequisite for everything
downstream, and the first genuine fork is node 8 (host-platform order).
Node 1 is the lean.

Map pass 2026-07-23 (Slice 49 review): node 1 shipped as specified — the
per-line packing model, the streaming `VisualRowCursor`, and the per-line
infinite-width equivalence oracle. What it taught: the per-line packer is
purely local (advances + break opportunities + width), holds O(1) core
memory, and provably reduces to the no-wrap column model at width ≥ total —
so the row-partition *math* is settled and is NOT where criterion-1 risk
lives. The open question the arc rests on is untouched: **who owns row data
at a given wrap width, and what recomputes when that width changes** — that
is node 2, and it is exactly the top risk. Nodes 2–9 stand unrevised; the
next step is still **topological** (node 2 is the forced prerequisite for the
query analogs and front-loads criterion 1). Node 2 is the lean. First genuine
fork remains node 8.

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
- 2026-07-22 — **User chose Option A: Slice 49 = node 1** (visual-row model +
  row-packing math over a wrap-metrics provider contract, with the
  infinite-width equivalence oracle from day one). Advances criterion 3,
  front-loads the criterion-1 top risk via nodes 1–2. The three escalated
  P2s D-7/D-8/D-9 are `deferred(user, 2026-07-22)` in the ledger (rationale:
  D-7 latent under the current trusted-CI model with no fork-PR exploit path;
  D-8 cannot be scheduled without a product-target decision; D-9 is a
  self-healing watch-item as pre-slice-45 rows age out of the N=20 window).
- 2026-07-23 — **Slice 49 merged** (PR #114, merge `8e91f52`; post-merge push
  run `29990966569` green at step level). Node 1 done; criterion 3 → partial
  (per-line equivalence half proven). Its post-slice review recommends
  **Slice 50 = node 2** (wrap-aware compute + width-change cost demo) as the
  topological, top-risk-retiring lean. New debt: D-12 (P3, interior
  exact-equal width-boundary test gap — fold-in for node 2, which touches the
  cursor). D-1/D-2 (open P2s, slice 47) are at 2 completed slices and hit the
  ≥3 escalation threshold at the Slice 50 review.
- 2026-07-23 — **User chose Option A: Slice 50 = node 2** (wrap-aware viewport
  compute over visual rows + the width-change cost demonstration). The
  topological forced next step; retires the arc's top feasibility risk
  (criterion 1 — who owns row data at a given wrap width, what recomputes when
  the width changes) and advances criterion 3 (whole-document equivalence
  half). Folds in D-12 + the mandatory equivalence-oracle falsifiability
  follow-up. D-1/D-2 ride to the Slice 50 review's escalation moment (not
  pulled forward). Next inner-loop step: brainstorm node 2.
