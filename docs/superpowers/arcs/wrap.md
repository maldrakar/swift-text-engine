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
| 3 | Wrap-aware equivalents of existing queries (compute over visual rows, y→row, point→(row, cell)); no-wrap path preserved; wrap at infinite width equals no-wrap (equivalence oracle) | partial | Per-line (Slice 49, [PR #114](https://github.com/maldrakar/swift-text-engine/pull/114) `8e91f52`, `VisualRowEquivalenceTests`) **and whole-document** (Slice 50, [PR #117](https://github.com/maldrakar/swift-text-engine/pull/117) `fdc66d2`, `WrapComputeEquivalenceTests`) equivalence proven (wrap at ∞ = no-wrap, bit-identical over irregular inputs); the **compute** query analog shipped; no-wrap path untouched. The **y→row** analog shipped (Slice 53, [PR #126](https://github.com/maldrakar/swift-text-engine/pull/126) `c2e6b37`, `WrapRowQueryEquivalenceTests` — `visualRowAt` at ∞, and at any width no line exceeds, is bit-identical to `lineAt` over a uniform axis; post-merge run `32595528239`). Remaining: the **point→(row, cell)** analog (node 4), the last item on this criterion's own list |
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
3. `done` (Slice 53) — y→row inverse query (`visualRowAt`), the wrap-aware `lineAt`
   analog over the visual-row axis. Advanced criterion 3. Shipped as specified: the shared
   layout ladder makes `compute(_:layout:)` and `visualRowAt` accept and reject identical
   layouts by construction; the row is named in both coordinate systems (`globalRow` plus
   `logicalLine`/`rowInLine`), which is what makes node 4 a composition rather than a
   re-derivation; clamped queries take **no** special case (unlike the no-wrap axis's
   two-probe constant) and a test says so. D-13 was **not** folded in — see the correction
   below, which the selection had already made. **Fold-in rationale corrected at selection
   time (kept for the record):**
   node 3 does **not** add a fourth copy of the per-axis binary-search body — following
   node 2's own reuse pattern it reuses `binarySearchLineIndex` (via
   `UniformLineMetrics`) plus the existing `binarySearchLogicalLine`. D-13 therefore
   rides on merit, not on "cheapest here". The fold-in that *is* on this node's own
   axis: `UniformLineMetrics` (`LineMetricsSource.swift:103`) overrides **neither**
   native hook, so the reused compute pays O(log totalRows) where a uniform axis answers
   by division — the exact term behind this map's "not literally width-independent"
   correction. Floating-point edges make it a design question for the brainstorm, not a
   drive-by.
4. `pending` — **← SELECTED by the slice-54 review (topological)**; deferred once already
   (slice 54 took the calibration-chain route by user call, 2026-08-23), so this node is one
   slice overdue. point→(row, cell) wrap-aware composite.
   Criterion 3, and its last enumerated analog. Composes node 3's `visualRowAt` with the
   existing within-line column query the way `pointAt` composes `lineAt` with `columnAt` —
   no new search. Fold-in home for **D-24** (the row-axis dispatch is pinned by nothing —
   drill C leaves 397/0 green while bypassing it), **D-29** (MANDATORY under the skill's
   falsifiability rule — the only slice-54 guarantee with no recorded red; a counting
   layout wrapper asserts the `--wrap-compute` drain body invokes `compute` zero times)
   and **D-25**; plausibly **D-13**.
5. `pending` — `--memory-shape` extension to the wrap path. Criterion 2.
6. `pending` — Wrap benchmark modes promoted to blocking gates
   (harvest → derive). Criterion 4. Likely splits per mode, as the first
   arc's gate promotions did. **Both of its inputs were repaired ahead of it in
   slice 54 (`done`)** (D-23: the wrap modes measure one operation per `clock.measure` and print
   tick-quantised numbers; D-7: the harvester selects rows by run id with no
   conclusion/event/fork check) — because `harvest → derive` never re-measures and never
   re-authenticates, so neither defect is repairable *after* this node's first harvest.
   Still to read when it arrives: D-20/D-21 (the non-gateable modes' `AbsoluteCeiling`
   class is pinned by nothing, and that inertness ends the moment a wrap mode becomes
   gateable).
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

Map pass 2026-08-08 (Slice 51 review): Slice 51 was the **debt route** and
consumed **no map node** — the same shape as the process slice 48. Nothing it
shipped touched wrap feasibility, so nodes 3–9 and fork V stand unrevised and
un-relearned; there is no correction to absorb this pass. It did discharge both
escalated P2s (D-1, D-2) plus D-3/D-6, so the escalation that routed the Slice 50
review's recommendation to the user is now cleared by *scheduling*, not by a
fourth defer. Next step is **topological** (node 3 = y→row, the next criterion-3
analog behind node 2); first genuine fork remains node 8 (host order) / fork V.
Lean is node 3, and this review **selects** it rather than routing — the aging
defers D-8/D-9 are surfaced for a re-affirmation, but neither is a fork blocking
the selection.

Map pass 2026-08-09 (Slice 52 review): Slice 52 was the **calibration route** and
consumed **no map node** — the third slice of that shape, after the process slice 48
and the debt slice 51. Nothing it shipped touched wrap feasibility, so nodes 3–9 and
fork V stand unrevised and un-relearned; there is no correction to absorb this pass.
What it did change is the ground **node 6** stands on: criterion 4 binds future wrap
gates to the harvest → derive recipe and to the absolute 60 FPS ceiling by reference,
and slice 52 repaired both inputs — the calibration evidence now includes the last ten
slices, and a future wrap mode classifies itself into an `AbsoluteCeiling` class
instead of inheriting a boolean designed before wrap existed. One row to read when
node 6 arrives: the class-membership pin filters on `isGateable`, so the four
non-gateable modes (including `wrapCompute`) are classified but **pinned by nothing**
(review P3 #4) — that inertness ends the moment a wrap mode becomes gateable. Next
step is **topological** (node 3 = y→row); first genuine fork remains node 8 (host
order) / fork V. Lean is node 3, and this review **selects** it — the arc cannot
afford a fourth consecutive no-criterion slice, which is precisely how a brief
criterion stays open for ten slices.

Map pass 2026-08-22 (Slice 53 review): node 3 shipped as specified — `visualRowAt`
adds no new search, reuses the extracted layout ladder, and returns both coordinate
systems. Nodes 4-9 and fork V stand unrevised; nothing this slice taught invalidates
them. What it *did* change is the ground **node 6** stands on, in a second way beyond
slice 52's: D-23 records that both wrap benchmark modes time a single operation per
`clock.measure` and print tick-quantised numbers (≈41.7 ns granularity, `p95 == p99` on
the small scenario) where their gated siblings amortise over 256 operations and measure
17-94 ns. `harvest -> derive` never re-measures, so node 6 must fix the timing shape
before its first harvest or it will derive a budget from clock overhead. Next step is
**topological** (node 4 = point→(row, cell), the last analog on criterion 3's list);
first genuine fork remains node 8 (host order) / fork V. Lean is node 4, and this review
**selects** it — the competing option was node 5 (criterion 2, the only wrap criterion
with no evidence at all), rejected on sequencing: `--memory-shape` should be extended
once, over a complete wrap query surface, not twice.

Map pass 2026-08-23 (Slice 54 review): Slice 54 took the **calibration route** and consumed
**no map node** — the fifth slice of that shape, after the process slice 48, the debt slice 51
and the calibration slice 52. Nothing it shipped touched wrap feasibility, so nodes 4-9 and
fork V stand unrevised and un-relearned; there is no correction to absorb this pass. What it
changed is the ground **node 6** stands on, for the third consecutive time (52: the recipe's
evidence and the absolute ceiling; 53: recorded the timing defect as D-23; 54: repaired the
timing and authenticated the evidence). Node 6's two named inputs are now sound: the wrap
modes measure the operation rather than the host tick, and the harvester admits only this
repository's runs and refuses rows whose own line reports a slow or degenerate measurement.
Two rows node 6 gains from this slice: **D-30** (`reindex_ns` carries no `p95_ns`/`p99_ns`,
so the width-change cost — criterion 1's own quantity — is structurally unharvestable through
`harvest -> derive`) and **D-28** (`amortisedSamples` claims to be the gated modes' shape and
nothing pins it, which is exactly the assumption node 6's derived budgets rest on); they join
D-20/D-21 on that node's reading list. Next step is **topological** (node 4 = point→(row,
cell), the last analog on criterion 3's list); first genuine fork remains node 8 (host order)
/ fork V. Lean is node 4, and this review **selects** it — it was already selected by the
slice-53 review and deferred by user call at slice 54's selection, so it is one slice overdue,
and the arc cannot afford consecutive no-criterion slices.

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
  while the WASM bundle-state global still stored failures only — so the
  asymmetric-drift path still burned a second bounded-retry ladder against an
  already-installed bundle and reported `sdk_install_failed`. Slice 51
  discharged this remaining half: the global is renamed `WASM_BUNDLE_STATE` and
  gains a `bundle_installed_ok` state recorded on successful shared install.
  **D-7** stays
  deferred (re-affirmed): `harvest-gate-corpus.sh` + corpus policy is a different
  surface deserving its own spec. Out of scope by the concern-separation rule:
  **D-13** (core) and **D-10/D-11** (repo-policy pins). Slice 51 advances **no
  wrap criterion** and consumes **no map node** (like the process slice 48);
  **node 3 (y→row) remains the lean** for the next feature slice. Next
  inner-loop step: brainstorm slice 51.
- 2026-08-08 — **Slice 51 merged** (PR #120, merge `bd5e042`; post-merge push run
  `31214035498` green at step level; post-merge proof PR #121). Debt route
  complete: **D-1, D-2, D-3, D-6 all discharged** — both slice-47 escalated P2s
  closed by scheduling. Scoreboard unchanged **by design** (no criterion
  advanced, no map node consumed). Enforcement multiplier worth recording: all
  four `.github/scripts` self-tests now run under `swift test`, so
  `detect-docs-only-pr.sh` — the trusted gate deciding whether heavy CI runs —
  has build-failing assertions for the first time. Two in-slice falsifiability
  corrections: the whole-branch review caught a fail-open `mktemp -d` that would
  have written to `/` in the root-run CI container while reporting
  `self_test=pass`; and the post-merge conformance pass found the D-6 pin's own
  detector (`defined_functions`) blind to five of six declaration forms, fixed
  test-first in `2c71676`. New/changed debt: **D-16** (P3, accepted-risk —
  string-literal residual in the coverage check), **D-15** statement corrected
  (its recorded trigger cannot fire under the sibling scripts' `set -e`).
  Slice 51's review **selects Slice 52 = node 3 (y→row wrap analog)** as the
  topological next step, with D-13 as a fold-in candidate; **D-8** is surfaced
  for a user re-affirm-or-schedule (it needs a product target before it can ever
  be scheduled), and D-9's self-healing prediction is now testable and unchecked.
- 2026-08-08 — **Slice 52 selected and shipped: the calibration route.** The slice-51
  review's lean was Option A (map node 3, y→row); the **user chose Option C** after
  live evidence at selection time showed the calibration base was ten slices stale —
  the corpus unappended since 2026-07-18, zero post-slice-45 runs in the N=20 window.
  The same call gave **D-8** the product target it had waited on since slice 43 (one
  whole 60 FPS frame for a discrete action), converting it from "cannot be scheduled"
  into ordinary work. Slice 52 advances **no wrap criterion** and consumes **no map
  node**, like slices 48 and 51 — but it is not housekeeping: the wrap brief's fourth
  criterion binds future wrap gates to *this* recipe («по существующему рецепту
  калибровки (harvest → derive)») and to the absolute 60 FPS ceiling, so a stale
  evidence base and a pre-wrap boolean were both de-risking work for a named criterion.
  After it, a future `wrap_compute` gate calibrates against evidence including the last
  ten slices, and a future wrap mode classifies itself into a ceiling class rather than
  inheriting a flag designed before wrap existed. **Node 3 (y→row) remains the lean**
  for the next feature slice.
- 2026-08-09 — **Slice 52 merged** ([PR #123](https://github.com/maldrakar/swift-text-engine/pull/123),
  merge `955dec8`; post-merge push run `31307764210` green at step level — 46
  `gate=pass`, 362/0, 41 lines at `1666666` + 5 at `16666666`, zero `=exempt`; hosted
  proof PR [#124](https://github.com/maldrakar/swift-text-engine/pull/124)). Calibration
  route complete: **D-8 discharged** (the item that could not be scheduled without a
  product target since slice 43), **D-9 amended in place** — shape-transition half
  discharged by fact, thin-axis half still open but now carrying the rule and the ratio
  rather than a list, because the single max-governed scenario *moved* in one harvest.
  27 of 46 budgets moved, 6 tightened; the tightening risk — the one direction no
  re-derivation can catch — was closed empirically on three hosted samples. Scoreboard
  unchanged **by design**. New debt: **D-17** (P2 — `${PIPESTATUS[0]}` is un-failable
  under zsh, invalidating the compliance evidence slice 51's review recorded for D-2)
  plus four P3s (D-18…D-21). In-slice falsifiability catch: the plan's Task 5 TDD red
  was *unreachable as written*, and the mutation substituted for it proved strictly
  more than the planned red would have. This review's audit found one guarantee
  un-drilled (the `gov_p95` self-test's max branch, invisible behind a fail-fast
  harness) and drilled it — it bites. Slice 52's review **selects Slice 53 = node 3
  (y→row wrap analog)**, folding in D-13.
- 2026-08-09 — **User chose Option A: Slice 53 = node 3** (y→row wrap analog), the
  topological next step and the first slice to advance a wrap criterion since slice 50.
  Two corrections came out of the live re-verification this selection ran against the
  tree, and both are recorded rather than absorbed silently:
  (a) the slice-52 review's D-13 fold-in argument — "node 3 would otherwise add a
  **fourth** copy of the per-axis binary-search body" — **does not hold**. Node 3
  following node 2's reuse pattern (`compute(_:layout:)` reuses
  `UniformLineMetrics(lineCount: totalRows, lineHeight: rowHeight)`,
  `WrapViewportVirtualizer.swift:22`) adds no copy: it reuses `binarySearchLineIndex`
  and the existing `binarySearchLogicalLine`. D-13 stays open on merit; it is a fold-in
  candidate for this slice, not a forced one.
  (b) A fold-in candidate on node 3's **own** axis surfaced in its place:
  `UniformLineMetrics` (`LineMetricsSource.swift:103`) overrides neither
  `lineIndex(containingOffset:)` nor `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`,
  so wrap compute pays O(log totalRows) on both boundary searches where a uniform axis
  answers by division — the term behind this map's own "not literally width-independent"
  correction. Deferred to the node-3 brainstorm as a design question (floating-point
  edges), not pre-decided here.
  **D-9** (open P2, born slice 46, ≥ 3 completed slices old and passed over by the
  slice-52 review's escalation check) was surfaced at selection time and is
  `deferred(user, 2026-08-09)`: slice 52 converted it from a stale named list into a
  re-derivable observable (`gov_p95=median|max` per scenario), so the watch is on demand
  rather than transcribed. **D-17** (P2, one slice old, does not escalate) rides —
  mitigated by a one-line "do not use `${PIPESTATUS[0]}`" instruction in slice 53's plan;
  it was re-verified live at selection time and still inverts a failure into a pass under
  zsh, with `AGENTS.md:642` still recommending it by name. Next inner-loop step:
  brainstorm node 3.
- 2026-08-22 — Slice 53 (node 3, `visualRowAt`) merged ([PR #126](https://github.com/maldrakar/swift-text-engine/pull/126)
  `c2e6b37`; hosted proof [PR #127](https://github.com/maldrakar/swift-text-engine/pull/127) `53dcbfc`).
  Suite 396 → 397, twelve gates unchanged, no budget or corpus touched. Its review is
  **READY, no P0/P1**, and records two new P2s — **D-23** (both wrap benchmark modes time
  one operation per `clock.measure`; output quantised to the host clock tick, so node 6
  cannot derive a budget from this shape) and **D-24** (the row axis's documented
  "provider-overridable" hook is pinned by nothing: bypassing the dispatch leaves 397/0
  green) — plus **D-25** (P3, the second probe-count bound is decorative). D-21 gained
  live evidence rather than a new row.
  Two things this slice is worth remembering for: (a) the **user** found the coverage gap
  six drills, an SDD fix wave and a whole-branch review all missed — every probe-count
  fixture wrapped at ∞, so `totalRows == lineCount` and a per-row cost term was invisible
  *by construction*; the fold-in closes it at the unchanged bound (13/13/14 against 14),
  and drill 7 shows the gap instead of asserting it. Same lesson as the fix wave's own
  catch, twice in one slice, on one file: *a probe-count harness must be built on a
  fixture where the axes it separates actually differ.* (b) The review's falsifiability
  audit found **two** shipped guarantees un-drilled (the anti-dead-code checksum, and
  non-gateability) and drilled both — they bite — and found a third that was not a
  guarantee at all (D-24).
  Slice 53's review **selects Slice 54 = node 4 (point→(row, cell))**, folding in D-24.
  Open for the user rather than decided here: re-affirm or schedule **D-7** and **D-9**
  (both `deferred(user, …)` P2s, origins ≥ 3 completed slices back), and whether **D-23**
  folds into slice 54 or waits for node 6's first task.

- 2026-08-23 — **User chose Option C: Slice 54 = the calibration-chain route**, not the
  node-4 lean, and in the same call **scheduled D-7** (which had been `deferred(user, …)`
  since 2026-07-22 and re-affirmed once) rather than deferring it a third time. Scope:
  **D-23** (P2 — put both wrap benchmark modes on the amortised `operationsPerSample`
  timing shape the twelve gated modes use) plus **D-7** (P2 — provenance checks in
  `harvest-gate-corpus.sh`, so a run's `p95_ns=` lines are selected on conclusion/event/fork
  and not on run id alone). One theme, not two errands: **D-23 makes the measurement real,
  D-7 makes the harvested evidence authentic**, and both are inputs to node 6 that
  `harvest → derive` can never repair after the fact — it neither re-measures nor
  re-authenticates. Pairing them also answers the slice-53 review's own objection to Option C
  standing alone ("it is a fold-in, not a slice").
  Argument added at selection time, beyond what the review recorded: node 4 will by symmetry
  add its own wrap benchmark mode (node 3 added `--wrap-row-query`), so repairing the timing
  shape **first** means that third mode is born correct instead of becoming a third copy of
  the defect.
  Slice 54 advances **no wrap criterion** and consumes **no map node** — the fourth slice of
  that shape, after the process slice 48, the debt slice 51 and the calibration slice 52 — but
  like slice 52 it is de-risking work for a *named* criterion: criterion 4 binds future wrap
  gates to this recipe by reference, and a gate calibrated from clock overhead or from
  unauthenticated rows is the arc's own "gate that cannot fail" failure mode with a deadline.
  **Node 4 (point→(row, cell)) remains the lean** for the next feature slice, carrying D-24
  (and D-25, plausibly D-13) as fold-ins. **D-9** is `deferred(user, 2026-08-23)` — re-affirmed,
  and now on its second consecutive re-affirmation; the next review should schedule it or state
  why the `gov_p95` observable is a permanent substitute for a fix.
  Live re-verification run at selection time (three claims, all held): D-24 is still real
  (`grep "func logicalLine(containingVisualRow"` → exactly the requirement and the default, no
  conformer overrides); `pointAt` does compose `lineAt` → `columnAt` feeding the located line
  index forward (`PointQuery.swift:34-40`), so node 4's composition shape is confirmed; and
  `visualRowAt` does return both coordinate systems (`WrapPositionQuery.swift:39-45`).
  One design question surfaced for node 4's brainstorm rather than pre-decided here: `columnAt`
  requires `columnOffset(inLine:column:0) == 0` (`HorizontalPositionQuery.swift:28`) and clamps
  to the **logical line's** edges (`columnIndex: 0` / `count - 1`, lines 40/43), while a visual
  row is a `[startColumn, endColumn)` span with its own left edge — so node 4 must settle x
  rebasing and whether a clamp lands on the row's edge or the line's. That is what makes node 4
  more than a mechanical composition.
- 2026-08-23 — Slice 54 merged ([PR #129](https://github.com/maldrakar/swift-text-engine/pull/129),
  `e97791f`; post-merge hosted proof [PR #130](https://github.com/maldrakar/swift-text-engine/pull/130),
  push run `32660537137`). Its post-slice review **selects node 4** (point→(row, cell)) — a
  topological step, not a fork, so the review selects rather than routing; the user can override.
  Node 4 was already selected by the slice-53 review and deferred once by user call, so it is one
  slice overdue. Recommended fold-ins: **D-24** (P2, born on node 4's own axis), **D-29**
  (MANDATORY — the only slice-54 guarantee with no recorded red) and **D-25**; **D-13** only if
  the brainstorm finds it rides on merit.
  Rejected alternatives, with reasons kept: **node 6** (gate promotion) — its mechanism is finally
  sound, but node 4 adds a third wrap benchmark mode by symmetry, so promoting first means node 6
  splits or repeats; **an infrastructure slice** for D-27 — real but newborn and not escalated, and
  it would be the arc's sixth no-criterion slice after slice 54 was already one.
  Two items the next reviews must not let age: **D-27** (P2, born this review — ten of twelve
  blocking gate steps have unpinned shape; `|| true` on one leaves `swift test` 408/0) should be
  scheduled by slice 56; **D-17** (P2, born slice 52, re-observed live at this review) **escalates
  at the next review**. **D-9** is on its second consecutive re-affirmation and the review states
  the argument rather than re-deferring silently: the `gov_p95=median|max` observable substitutes
  for a stale *list*, not for a *fix*, and a one-line assertion should fold into the next
  calibration-touching slice or be deferred a third time explicitly.
