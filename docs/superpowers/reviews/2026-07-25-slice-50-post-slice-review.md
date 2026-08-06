# Slice 50 — post-slice review (wrap-aware viewport compute over visual rows, wrap node 2)

**Slice:** 50 — soft-wrap arc, **node 2**
**Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md) · **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)
**Spec:** [`specs/2026-07-24-wrap-viewport-compute-design.md`](../specs/2026-07-24-wrap-viewport-compute-design.md) · **Plan:** [`plans/2026-07-24-wrap-viewport-compute.md`](../plans/2026-07-24-wrap-viewport-compute.md)
**Merged:** [PR #117](https://github.com/maldrakar/swift-text-engine/pull/117), merge commit `fdc66d2` (merge commit — child SHAs preserved, no rebase-rewrite).
**Merged proof:** post-merge `push`-to-`main` run `30169643578` @ `fdc66d2` — green at **step** level (all 3 required jobs, empty non-success/non-skipped set, heavy path ran: twelve gates `gate=pass`, host tests 359/0, iOS+WASM blocking compiles pass). Recorded via docs PR [#118](https://github.com/maldrakar/swift-text-engine/pull/118).

## What shipped

The cross-line aggregation layer of soft-wrap: the visual-row axis, the third
`compute` overload over it, and the document-level streaming cursor — delivered
via subagent-driven-development (6 tasks, each per-task reviewed clean; final
whole-branch review on opus = ready-to-merge, 0 P0/P1).

- **`VisualRowLayoutSource`** (`Sources/TextEngineCore/VisualRowLayoutSource.swift`)
  — refines `WrapMetricsSource` with `lineCount`, `rowHeight`, `wrapWidth`,
  `visualRowCount(inLine:)`, the `firstVisualRow(ofLine:)` prefix sum, and the
  `logicalLine(containingVisualRow:)` inverse with a binary-search default. The
  third metrics source, mirroring `LineMetricsSource`/`LineHorizontalMetricsSource`
  limb-for-limb. Width is baked into the provider — a width change is a *new*
  provider.
- **`ViewportVirtualizer.compute(_:layout:)`** — the **third** `compute` overload,
  returning a `VirtualRange` of **visual-row indices**, computed by reusing the
  proven variable compute over `UniformLineMetrics(totalRows, rowHeight)`
  (`totalRows = firstVisualRow(ofLine: lineCount)`); O(log N) queries, O(1) memory.
  Fronted by the Decision-6 validation ladder (new `.nonPositiveRowHeight` /
  `.invalidVisualRowLayout` cases; wrap-coherent — never leaks the reused overload's
  `.invalidLineMetrics`).
- **`VisualRowGeometry`** (Equatable; `VisualRow` + `y` + `height`) and
  **`DocumentVisualRowCursor<Layout>`** — O(1)-state cursor streaming placed
  `VisualRowGeometry` over the buffer range via `visualRowGeometry(for:layout:)`,
  reusing node 1's per-line `VisualRowCursor` (O(rowInStartLine + buffer)).
- **Whole-document ∞-width equivalence oracle** + a **finite-width recorded red**
  (a stub using `lineCount`=4 instead of `totalRows`=8 failed
  `testScrollToBottomIsInVisualRows` `"4"≠"8"`) + the **D-12** interior exact-equal
  wrap-width boundary fixture (its `<=`→`<` mutation reddens it).
- **Observational `--wrap-compute` benchmark** (`Sources/ViewportBenchmarks`, **not
  gateable**, `--gate` rejected) demonstrating the width-change cost: core compute
  stays viewport-bounded; the provider's O(N) reindex is the measured setup cost.

26 new tests (VisualRowLayoutSourceTests 2 / WrapComputeEquivalenceTests 3 /
WrapComputeTests 6 / WrapComputeValidationTests 11 / WrapComputeOptionsTests 4);
full suite **359/0**. No new blocking gate (`--wrap-compute` is observational; the
gate promotion is node 6).

## Acceptance-criteria status

All eight ACs discharged (spec §Acceptance Criteria):

| AC | Status | Evidence |
|---|---|---|
| 1 `VisualRowLayoutSource` shape + binary-search default | ✅ | Task 1 review; hand-traced prefix `[0,2,3,6]` + inverse `[0,0,1,2,2,2]`; refines `WrapMetricsSource` without redeclaring inherited members |
| 2 `VisualRowGeometry` + `DocumentVisualRowCursor` + two error cases, ratified shapes | ✅ | Tasks 2/3 reviews; `VisualRowGeometry` first exercised by Task 3's cursor tests |
| 3 `compute(_:layout:)` ladder + reused-uniform range, O(log N)/O(1) | ✅ | Tasks 2/4 reviews + final review: reuse of `compute(_:metrics:)` over `UniformLineMetrics(totalRows, rowHeight)`; wrap-coherent ladder pins the overflow seam (`testTotalHeightOverflowIsWrapCoherent`) |
| 4 `visualRowGeometry` streaming, mid-line + blank, O(rowInStartLine+buffer) | ✅ | Task 3 review + final review hand-trace of `testCursorMidLineStart` (scroll 5 → row 1, discard 1, first row `rowInLine=1`, `y=5`) |
| 5 Whole-document equivalence oracle + finite-width recorded red | ✅ | `WrapComputeEquivalenceTests` (∞ = logical-line compute, bit-identical, over irregular inputs); the discriminating red is the finite-width `testScrollToBottomIsInVisualRows` `"4"≠"8"` |
| 6 D-12 interior boundary + mutation reddens; suite green | ✅ | `testInteriorExactEqualWidthBoundary` + Task-3 recorded mutation (`endColumn` 2→1); 359/0. **Correction landed in-slice:** the ∞ oracle's streaming half does *not* catch the mutation (at ∞ both `<` and `<=` accept finite-vs-`+∞`) — the finite-width fixture is the real discriminator (spec + verification doc fixed, `ce25d29`/`e1d8df9`) |
| 7 Foundation-free + release + gate + `--wrap-compute` + iOS/WASM | ✅ | Verification record; Foundation scan empty; `--gate` gate=pass (unchanged); iOS compile pass; WASM on the hosted pinned-6.2.1 job |
| 8 Hosted CI green at step level, run IDs, merged proof in post-merge run | ✅ | Three PR-head runs (`30084403436`/`30084964150`/`30119186946`) + post-merge `30169643578`, all step-level green |

## Strengths

- **The final whole-branch review (opus) proved the composition, not just read
  it:** it verified correct tiling (no gap/overlap/off-by-one, `y = globalRow ·
  rowHeight` consistent between the compute range and the cursor), the ladder is
  wrap-coherent (every delegated-overload failure path pre-empted → no
  `.invalidLineMetrics` leak), O(1) core memory holds, and — crucially — it
  **caught a false falsifiability claim**: the doc/spec asserted the ∞ oracle's
  row-streaming half catches the D-12 mutation, which it provably does not. The
  spec (Decision 7, Testing Strategy, AC6) and the verification doc were corrected
  in-slice (`ce25d29`, `e1d8df9`). Coverage was always genuine; only the prose
  over-claimed. This is the falsifiability discipline working on itself.
- **Reuse over re-derivation (Decision 2 held in practice):** the visual-row axis
  at ∞ *is* `UniformLineMetrics(lineCount, rowHeight)`, so the ∞ oracle is
  bit-identical **by construction**, and the range/clamp/edge-flag math is the
  existing tested code — not re-implemented.
- **The type hierarchy prevents the worse half of the cross-axis risk:**
  `VisualRowLayoutSource` refines `WrapMetricsSource`, not `LineMetricsSource`, so a
  layout source cannot be handed to `compute(_:metrics:)` at all; the residual
  misuse (a visual-row `VirtualRange` into a logical-line cursor) degrades to empty
  output, never a crash (spec Risk P3, confirmed by the reviewer).
- **The width-change story is measured, not asserted:** `--wrap-compute` shows
  `total_rows` growing 100k→200k→800k as width narrows while `compute_p95_ns` stays
  flat (~167–209 ns — O(log totalRows), a couple of binary-search steps, **not**
  literally width-independent), and the O(N) reindex (tens of ms) is a separate,
  labelled setup cost.
- **In-slice comment-truth fix (twice):** the Task-3 `makeInner` comment that
  overclaimed compute's validation was corrected (`a61b958`), and the ∞-oracle
  over-claim above.

## Issues

No P0/P1. Carried Minors (all non-blocking, from the per-task and final reviews):

- **P3 (→ ledger D-13):** `binarySearchLogicalLine` is the **third** per-axis copy
  of the same binary-search body (line / column / visual-row axes), differing only
  in the accessor and `Int`/`Double` target. Plan-governed (spec Decision 1 ratifies
  a per-axis default); each copy is correct; consolidation into a shared generic
  helper is a later cross-axis slice. Logged as a fold-in/consolidation candidate.
- **P3 (test-gap, not ledgered — marginal, correct by inspection):** no single
  fixture combines `lineCount==0` *and* `firstVisualRow(0)!=0` (the step-7-before-8
  ladder order is inspection-verified only), and `testInfiniteWrapWidthDoesNotFail`
  asserts *not-`.failure`* rather than an exact `.success(range)`. The ladder is
  otherwise pinned by the specific-error validation tests.
- **P3 (style, not ledgered):** the char-wrap `canBreak` predicate is duplicated
  between the two benchmark-local providers (`BenchmarkWrapLayout` / `SingleLineWrap`
  in `WrapComputeBenchmark.swift`); harmless, one file, benchmark-only.

---

# Recommendation (skill Mode 2)

Map pass output is the updated [arc file](../arcs/wrap.md): node 2 marked `done`;
the map's "width-independent" wording **corrected** to "O(log totalRows),
viewport-bounded" (what the slice actually proved); nodes 3–9 + fork V
re-validated (they stand — node 2 retired the criterion-1 *core* half and did not
touch the downstream shape). Next step is **topological**, not a fork — but the
**D-1/D-2 escalation** (below) forces a schedule-or-defer product call this review.

### Scoreboard delta

- **Criterion 1** (width change doesn't recompute the document; frame cost stays
  viewport-bounded): `open` → **`partial`**. Node 2 retired the **core half**: the
  per-frame `compute` is O(log totalRows) and never re-walks the document on a
  width change — the width is baked into the provider, and only its O(N) reindex (a
  setup cost, the same category as the initial document load) is linear. Evidence:
  [PR #117](https://github.com/maldrakar/swift-text-engine/pull/117) (`fdc66d2`),
  post-merge run `30169643578`, the `--wrap-compute` numbers (compute flat ~167–209
  ns across widths inf/40/10 while `total_rows` grows 100k→800k; reindex tens of
  ms). `partial`, not `done`: the *exact* width-change reindex is irreducibly Ω(N)
  (every multi-row line changes), so `done` needs the estimated/async **veneer**
  (fork V), not this node.
- **Criterion 3** (wrap-aware query equivalents; wrap at ∞ = no-wrap): **`partial`**
  (advanced, not closed). The **whole-document** equivalence half is now proven
  (`compute(_:layout:)` at ∞ = the logical-line `compute`, bit-identical, over
  irregular advances+breaks+variable column counts) and the **compute** query
  analog shipped. Evidence: [PR #117](https://github.com/maldrakar/swift-text-engine/pull/117),
  `WrapComputeEquivalenceTests`. Remaining: the **y→row** (node 3) and
  **point→(row,cell)** (node 4) analogs.

Still open/partial: criterion 1 (**partial** — core half done; veneer for `done`),
criterion 2 (open), criterion 3 (**partial** — compute+equivalence done; y→row +
point remain), criteria 4/5/6 (open).

### Debt ledger delta

- **Discharged D-12** (interior exact-equal wrap-width boundary): node 2 added
  `testInteriorExactEqualWidthBoundary` with a recorded `<=`→`<` mutation (`endColumn`
  2→1). Status → `discharged` ([PR #117](https://github.com/maldrakar/swift-text-engine/pull/117)).
- **Appended D-13** (P3, born this review): per-axis binary-search default
  triplication (line/column/visual-row) — consolidation candidate; see Issues.
- **Escalation (MANDATORY this review):** **D-1** and **D-2** (both P2, born
  [slice 47 review](2026-07-20-slice-47-post-slice-review.md)) are now **≥ 3
  completed slices old** (48, 49, 50) and MUST appear under Candidate options,
  scheduled or explicitly user-deferred — see Option B. Silence is not a legal
  state.
- **Open counts:** P2 = **2 open** (D-1, D-2 — now escalated) + 3
  `deferred(user, 2026-07-22)` (D-7, D-8, D-9); P3 = **6 open** (D-3, D-6, D-10,
  D-11, D-13) + 1 `deferred(user, 2026-07-21)` (D-5); 1 `discharged` (D-12); 1
  `accepted-risk` (D-4).

### Falsifiability audit

Standing guarantees this slice added, each with can-it-fail evidence:

- **`compute(_:layout:)` aggregation** — **recorded red**: the `lineCount`-vs-`totalRows`
  stub failed `testScrollToBottomIsInVisualRows` `"4"≠"8"` at finite width before the
  real aggregation landed. Falsifiable. ✅
- **The Decision-6 validation ladder** (`WrapComputeValidationTests`) — **recorded
  red**: before the ladder, malformed inputs crashed (array bounds in `firstVisualRow`)
  or leaked the reused overload's error cases. Falsifiable. ✅
- **The D-12 interior boundary** (`testInteriorExactEqualWidthBoundary`) — **recorded
  mutation**: `greedyEnd` `<=`→`<` reddens it (`endColumn` 2→1). Falsifiable. ✅
  (Discharges ledger D-12.)
- **The whole-document ∞ equivalence oracle** (`WrapComputeEquivalenceTests`,
  `testInfiniteWidthStreamsOneRowPerLine`) — **tautology-prone by itself** and now
  *documented as such*: at ∞, `totalRows == lineCount` (range half coincides) and the
  fit test compares finite-vs-`+∞` so both `<`/`<=` accept (streaming half unchanged by
  the D-12 mutation). Its discriminating reds live at **finite** width — the
  aggregation red and the D-12 fixture above, both recorded. This **discharges the
  Slice-49 mandatory candidate** ("prove the equivalence oracle can fail") honestly,
  at finite width — and the whole-branch review's catch-and-fix of the earlier
  over-claim is itself recorded evidence the audit bites. **No new mandatory
  candidate:** every behaviour the oracle nominally guards carries a finite-width
  recorded red or mutation.
- **`--wrap-compute`** is **observational, not a gate** (not `isGateable`; `--gate`
  rejected) — a demonstration that prints numbers, not a budget that can fail, so no
  falsifiability obligation attaches until node 6 promotes wrap modes to blocking
  gates via the harvest→derive recipe. The `isGateable`/`isFrameHotPath` registry pins
  stay green (wrapCompute non-gateable, registers no scenarios; frame-hot-path
  excluded set unchanged at `{bulkStructuralMutation}`).

### Candidate options

- **Option A — Slice 51 = node 3: y→row wrap-aware inverse query (`lineAt` analog
  over the visual-row axis). (LEAN.)** Advances **criterion 3** (the next query
  analog; completes more of the in-flight criterion before opening new ones). Map
  node 3 — the topological next step behind node 2. Discharges no ledger item;
  folds in nothing mandatory (D-13 is a cross-axis consolidation, not a node-3
  concern). The natural continuation of the query-analog line the arc has been
  walking.
- **Option B — Slice 51 = infra/debt: discharge the escalated P2s D-1 and/or D-2**
  (+ optionally fold the cross-target-compile.sh P3s D-3/D-6/D-10/D-11 and the new
  D-13). **Mandatory to surface** (D-1/D-2 are ≥ 3 slices old). Advances **no wrap
  criterion**, but clears the process/CI-hygiene debt before it ages further. D-1 is
  a real (if latent-under-the-6.2.1-pin) `cross-target-compile.sh` misdiagnosis; D-2
  is a plan-writing convention better encoded as practice than shipped as a big
  slice. Reasonable if the user wants the slice-47 P2s cleared now rather than
  carrying them further.
- **Option C — Slice 51 = node 5: `--memory-shape` extension to the wrap path.**
  Opens **criterion 2** (currently untouched — memory not linear with wrap on;
  `--memory-shape` asserts the invariant on the wrap path). Also topological, but
  leaves criterion 3's analogs (nodes 3/4) in-flight; the map orders node 5 after
  3/4. Pick this only to prioritise the memory-shape invariant over finishing the
  query analogs.

**Routing:** the topological lean is **Option A (node 3)** — it continues the
in-flight criterion-3 analog line and is the map's next step. **But the D-1/D-2
escalation forces an explicit product call**: per the escalation rule I cannot
silently carry them a fourth slice. So this routes to the **user** —
**schedule D-1/D-2 (Option B) now, or record an explicit defer** (`deferred(user,
2026-07-25)` with rationale, e.g. "D-1 latent under the 6.2.1 pin which provides
both SDK ids; D-2 folded into plan-writing practice rather than a standalone
slice") and take **Option A** as the lean. Options A and C are the wrap-feature
routes; B is the debt route. The user decides whether Slice 51 is a feature slice
(A/C) or the infra paydown (B).
