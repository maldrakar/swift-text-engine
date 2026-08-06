# Arc: soft-wrap ([brief](../../wrap-project-brief.md))

Status: active. Started 2026-07-21 (Slice 48 codified this process and
created this file). Slice 48 merged 2026-07-22 (PR #112, merge `a183205`);
its post-slice review is the first live Mode 2 run and selects Slice 1 below
as the lean. Constraints are enforced per-slice, not tracked here — see the
brief's «Ограничения» and the initial brief it inherits by reference.

## Scoreboard

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Layout-width change (device rotation, browser resize) does not recompute the document: frame cost stays viewport-bounded, in the spirit of the existing O(log N) + O(buffer) | partial | Core half retired (Slice 50): per-frame `compute(_:layout:)` is O(log totalRows) and never re-walks the document on a width change — width baked into the provider; only its O(N) reindex (a setup cost) is linear. [PR #117](https://github.com/maldrakar/swift-text-engine/pull/117) (`fdc66d2`), post-merge run `30169643578`, `--wrap-compute` numbers. `done` needs the estimated/async veneer (fork V) — the *exact* reindex is Ω(N) |
| 2 | Core memory not linear in document size with wrap on; wrap data lives behind the provider abstraction; `--memory-shape` extended to the wrap path | open | — |
| 3 | Wrap-aware equivalents of existing queries (compute over visual rows, y→row, point→(row, cell)); no-wrap path preserved; wrap at infinite width equals no-wrap (equivalence oracle) | partial | Per-line (Slice 49, [PR #114](https://github.com/maldrakar/swift-text-engine/pull/114) `8e91f52`, `VisualRowEquivalenceTests`) **and whole-document** (Slice 50, [PR #117](https://github.com/maldrakar/swift-text-engine/pull/117) `fdc66d2`, `WrapComputeEquivalenceTests`) equivalence proven (wrap at ∞ = no-wrap, bit-identical over irregular inputs); the **compute** query analog shipped; no-wrap path untouched. Remaining: the **y→row** (node 3) and **point→(row,cell)** (node 4) analogs |
| 4 | 100k+ lines / >10 MB scroll with wrap on holds p95/p99 budgets and the absolute 60 FPS ceiling; new wrap modes become blocking CI gates via the existing harvest → derive recipe | open | — |
| 5 | Incremental edits with wrap on (in-line edit, structural insert/delete) stay within frame-hot-path budgets | open | — |
| 6 | Thin verification hosts: iOS feeding CoreText-measured advances, browser feeding canvas `measureText` over the WASM build; both observably smooth-scroll a large wrapped document | open | — |

## Slice map (working hypothesis — rewrite freely at every map pass)

1. `done` (Slice 49) — Visual-row model + row-packing math over a wrap-metrics
   provider contract (break opportunities + advances), with the
   infinite-width equivalence oracle from day one. Advanced criterion 3
   (per-line half). Per-line packing only; cross-line aggregation is node 2.
2. `done` (Slice 50) — Wrap-aware viewport compute over visual rows +
   `DocumentVisualRowCursor` + the width-change cost demonstration. Advanced
   criteria 1 (→ partial) and 3 (whole-document equivalence half). **Retired the
   top risk's core half.** Correction the slice taught: the core per-frame compute
   is **O(log totalRows), viewport-bounded — NOT literally width-independent** (a
   narrower width has more rows → a couple more binary-search steps; flat within
   noise, not constant). Criterion 1 is `partial`, not `done`: the *exact*
   width-change reindex is Ω(N), so `done` needs the veneer fork V, not this node.
3. `pending` — **← next (lean, topological).** y→row inverse query (wrap-aware
   `lineAt` analog over the visual-row axis). Criterion 3 (next query analog behind
   node 2).
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

Map pass 2026-07-25 (Slice 50 review): node 2 shipped as specified — the
visual-row axis (`VisualRowLayoutSource`), the reused-uniform `compute(_:layout:)`,
the streaming `DocumentVisualRowCursor`, and the whole-document equivalence oracle.
What it taught, and what the map now absorbs: (a) the core per-frame compute is
**O(log totalRows), viewport-bounded — not literally width-independent** (the node-2
map wording above is corrected accordingly); (b) reuse-over-a-uniform-row-axis makes
the ∞ oracle bit-identical *by construction*; (c) criterion 1's *core* half is
retired and `done` is gated on the Ω(N) veneer fork V, exactly as front-loaded.
Nodes 3–9 + fork V stand unrevised. Next step is **topological** (node 3 = y→row,
the next criterion-3 analog behind node 2); first genuine fork remains node 8 (host
order) / fork V. Lean is node 3 — **but** the D-1/D-2 escalation (open P2s now ≥ 3
completed slices old) forces a user schedule-or-defer product call this review, so
the review routes the A/B/C choice to the user rather than auto-selecting node 3.

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
- 2026-07-25 — **Slice 50 merged** (PR #117, merge `fdc66d2`; post-merge push
  run `30169643578` green at step level; post-merge proof PR #118). Node 2 done;
  criterion 1 → partial (core half retired), criterion 3 whole-document
  equivalence half proven; D-12 discharged. In-slice falsifiability fix: the
  whole-branch review caught the ∞-oracle streaming-half over-claim (spec
  Decision 7 / Testing Strategy / AC6 + verification doc) and it was corrected
  (`ce25d29` / `e1d8df9`). New debt: D-13 (P3, per-axis binary-search triplication).
- 2026-07-25 — Slice 50 post-slice review recommends **Slice 51 = node 3 (y→row
  wrap analog)** as the topological lean, and — per the escalation rule —
  **surfaces the escalated P2s D-1/D-2** (born slice 47, now ≥ 3 completed slices)
  for a user **schedule-or-defer** product call (feature route A/C vs infra route
  B). See the [review](../reviews/2026-07-25-slice-50-post-slice-review.md)
  Candidate options. Awaiting the user's call.
- 2026-08-06 — **User chose Option B: Slice 51 = the debt route** (cross-target
  script hardening), not the node-3 lean. Scope: **D-1** (P2 — record a third
  precheck state on successful shared install), **D-3** (P3 — per-attempt retry
  logfiles), **D-6** (P3 — pin the shell-purity exemption set, mirroring
  `WorkflowShapeTests`'s `flagName` named-and-justified pattern), plus **D-2**
  (P2) folded in as the plan-assertion-executability conventions in `AGENTS.md`,
  applied to this slice's own plan. This **discharges both escalated P2s**
  (D-1, D-2, born slice 47) rather than deferring them a fourth slice, so the
  escalation is cleared by scheduling, not by silence. D-1 was **re-verified live
  on the tree at selection time**: slice 47 closed only the sibling half
  (`sdk_unresolved_after_install` is now recorded, `cross-target-compile.sh:569`),
  while `WASM_BUNDLE_FAILED_REASON` still stores failures only — so the
  asymmetric-drift path still burns a second bounded-retry ladder against an
  already-installed bundle and reports `sdk_install_failed`. **D-7** stays
  deferred (re-affirmed): `harvest-gate-corpus.sh` + corpus policy is a different
  surface deserving its own spec. Out of scope by the concern-separation rule:
  **D-13** (core) and **D-10/D-11** (repo-policy pins). Slice 51 advances **no
  wrap criterion** and consumes **no map node** (like the process slice 48);
  **node 3 (y→row) remains the lean** for the next feature slice. Next
  inner-loop step: brainstorm slice 51.
