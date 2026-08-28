# Wrap-Aware Point Query (`visualPointAt(x:y:layout:)`) Design

- **Slice:** 55 — soft-wrap arc, **node 4**, shipped as two pieces (55a, 55b)
- **Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md)
- **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)

## Status

Proposed. Selection affirmed by the user 2026-08-23 (arc decision log); brainstormed
2026-08-24; this document is the ratified design. **Six user calls** are recorded in it:
the `x` coordinate frame and clamp target (Decision 1), the result shape (Decision 3), the
index-only scope (Decision 9) and the composition approach (Decision 4) from the brainstorm;
the two-piece **55a/55b split** (Scope; 2026-08-27); and step 7 calling the provider's
`columnIndex(containingOffset:inLine:)` hook directly rather than composing `columnAt`
(Decision 14; 2026-08-28). The pieces ship on `slice-55a-wrap-trap-repairs` and
`slice-55b-wrap-point-query` — lettered, not renumbered, because they are two pieces of one
map node. The next step is the TDD implementation plan (`writing-plans`), **one plan per
piece, written from that piece's Contract section below**.

This document has been through ten review passes; each is one line in **Revision History**
at the end, which records what a pass changed and nothing more. Two rules govern the body:
it states what is ratified and keeps rejected alternatives on their merits, never narrating
which pass replaced what; and **every argument lives in exactly one section** — the one that
owns it — and is referenced from everywhere else by section name, so a fact cannot be
edited in one copy and left standing in another. The two Contract sections restate no
argument; they list what the executor must build, with pointers.

## Contract — 55a: `slice-55a-wrap-trap-repairs`

The shipped wrap layer, repaired and made cheaper: **no new public API**. Its acceptance
story is entirely *negative* — an unedited existing suite, byte-identical `checksum=` tokens
on both wrap modes, one predicted `--wrap-compute` speed-up, and recorded reds for every
guard it adds — so it is judged without reference to a query that does not exist yet.

**Commits, in this order, one per shipped-code edit** (the order is load-bearing — see
Scope for why commit 6 cannot precede commits 1–2):

| # | Commit | Decision | Files |
|---|---|---|---|
| 0 | `feat:` the `wrap_compute` line prints `checksum=` — the printer only, **before** any measured-path edit, so every column below carries the witness (a token added later would be byte-identical only across the columns that have it) | Decision 13 | `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift` (`formatWrapComputeLine` + its call site); `Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift` (shape case gains the token) |
| 1 | `refactor:` extract the within-line walk into `advanceVisualRows`; the cursor gains its `startLine` range check (after `DocumentVisualRowCursor.swift:27`) and its `rowInStartLine < 0` check — both → *streams nothing* | Decision 4 | `Sources/TextEngineCore/DocumentVisualRowCursor.swift`; `Tests/TextEngineCoreTests/WrapComputeTests.swift` (+2 cases); new `Tests/TextEngineCoreTests/VisualRowWalkHelperTests.swift` (`@testable`); `VisualRowLayoutTestSupport.swift` (+`OverridingLogicalLineLayout`: the hook overridden with a caller-supplied answer and a call log — the malformed-override conformer the guard tests need, reused by commit 6 with a correct answer) |
| 2 | `feat:` `visualRowAt` rejects an out-of-range `logicalLine` (between `WrapPositionQuery.swift:40` and `:41`) and a negative `rowInLine` (after `:41`) → `.failure(.invalidVisualRowLayout)`; the "same accept/reject set" wording narrowed in its three places | Decision 4 | `Sources/TextEngineCore/WrapPositionQuery.swift`; `Sources/TextEngineCore/WrapViewportVirtualizer.swift:1-3`; `AGENTS.md:155-156`; `Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift` (+4 cases) |
| 3 | `refactor:` extract the per-line wrap ladder into `validateWrapLine`; `VisualRowCursor` stores `total` | Decision 13 | `Sources/TextEngineCore/VisualRowCursor.swift` |
| 4 | `feat:` `greedyEnd` suffix-fits short-circuit, **red-first** against `WrapPackingCountTests` (the two O(1) rows of Decision 12's table); cost wording in `AGENTS.md` (node 1 and node 2 paragraphs) and the two doc comments | Decision 12 | new `Tests/TextEngineCoreTests/WrapPackingCountTests.swift`; `Sources/TextEngineCore/VisualRowCursor.swift:51-74`; `Sources/TextEngineCore/DocumentVisualRowCursor.swift:4-5`; `AGENTS.md` |
| 5 | `refactor:` extract the `--wrap-compute` drain body into a testable function (D-29) | Testing Strategy (fold-ins) | `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`; new `Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift` |
| 6 | `test:` D-24's dispatch pin, `VisualRowDispatchTests` — the overriding conformer of commit 1 with a **correct** answer, asserting the hook was called — **after** commits 1–2, never before: no test may drive an override against an unguarded consumer (commit 1's tests drive one only against the cursor it guards; commit 2's only against the `visualRowAt` it guards) | Testing Strategy (fold-ins) | new `Tests/TextEngineCoreTests/VisualRowDispatchTests.swift` |

**Internal signatures this piece introduces** (all `internal`; no public type gains a field):

```swift
// DocumentVisualRowCursor.swift — the shared walk (Decision 4)
func advanceVisualRows<M: WrapMetricsSource>(_ cursor: inout VisualRowCursor<M>, by k: Int) -> VisualRow?
//   Returns the result of the k-th `next()` call: nil if k <= 0 (k < 0 before any range is
//   formed) or if ANY of the k calls returned nil (it stops at that call); otherwise row k−1.
//   NOT "the last non-nil row seen" — under that reading step 3's exhaustion guard is dead code.

// VisualRowCursor.swift — the shared per-line ladder (Decision 13)
enum WrapLineMetrics { case valid(count: Int, total: Double); case failure(ViewportValidationError) }
func validateWrapLine<M: WrapMetricsSource>(inLine line: Int, wrapWidth: Double, metrics: M) -> WrapLineMetrics
//   visualRows(inLine:wrapWidth:metrics:) becomes a thin wrapper; signature, probe order, failures unchanged.
//   VisualRowCursor.init(line:columnCount:total:wrapWidth:metrics:) — `total` stored beside `columnCount`.

// VisualRowCursor.greedyEnd, before the scan (Decision 12)
if total - startOffset <= wrapWidth { return columnCount }

// WrapComputeBenchmark.swift — formatWrapComputeLine gains a trailing `checksum=` token (commit 0, Decision 13)
```

**The five guards** (canonical argument: Decision 4):

| # | Site | Malformed input | Today | After | Pinned by | Drill |
|---|---|---|---|---|---|---|
| 1 | `visualRowAt`, between `:40` and `:41` | `logicalLine ∉ 0..<lineCount` | traps at `:41` (`> lineCount`, `< 0`) or returns garbage (`== lineCount`) | `.failure(.invalidVisualRowLayout)` | `WrapRowQueryValidationTests`, three values (`> lineCount`, `== lineCount`, `< 0`) | (d1) |
| 2 | `visualRowAt`, after `:41` | in-range line whose `firstVisualRow` exceeds the row → `rowInLine < 0` | returns a location naming no row | `.failure(.invalidVisualRowLayout)` | `WrapRowQueryValidationTests` | (f4) |
| 3 | `DocumentVisualRowCursor.init`, after `:27` | `startLine ∉ 0..<lineCount` | traps at `:28` | streams nothing | `WrapComputeTests` | (f2) |
| 4 | `DocumentVisualRowCursor.init`, before the walk | `rowInStartLine < 0` | traps at `:31` (`0..<k`, SIGTRAP verified) | streams nothing | `WrapComputeTests` | (f1) |
| 5 | `advanceVisualRows` | `k < 0` | (new code) | `nil`, no range formed | `VisualRowWalkHelperTests` (direct, `@testable`) | (f3) |

**Tests that must pass unedited** across commits 3 and 4 (an edit is a stop, not an
adjustment — Decision 13): `WrapPackingTests`, `WrapValidationTests`, `WrapComputeTests`
(its shipped cases), `VisualRowEquivalenceTests`, `WrapComputeEquivalenceTests`.

**Drills, nine observed reds** (definitions: Testing Strategy): (d1) direct pin, (f1),
(f2), (f3), (f4), (l), (m), D-24's, D-29's.

**Expected numbers** (record shape: Verification):

- `--wrap-compute`, one column per commit on its path — two baselines after commit 0, then after commits
  1, 3, 4, 5. Commits 1, 3, 5: flat on every token within the baseline spread. Commit 4:
  `compute_*` flat; `reindex_ns` and `drain_*` fall at every width, ordered `inf` < `40` <
  `10` < 1 — time falls less than Decision 12's scan-iteration factors, because a per-row
  fixed cost remains once the scan is gone (the plan's smoke test measured drain p95 0.55 /
  0.80 / 0.92 and reindex 0.45 / 0.68 / 0.93); the record reads the direction and the order,
  not the iteration factor. The `checksum=` token is byte-identical across **all** columns.
- `--wrap-row-query`: `checksum=` byte-identical to the pre-branch run.
- All twelve blocking gates `gate=pass`; every gated checksum byte-identical to the
  pre-branch baseline; `swift test` green with its count; Foundation scan empty;
  `--memory-shape` `invariant=pass`.

**Documentation** (canonical list: Documentation Updates): `AGENTS.md` node 1, node 2 and
`visualRowAt` paragraphs; the three "same accept/reject set" sites; the two doc comments;
ledger D-24 and D-29 → `discharged`.

**Record**: `docs/superpowers/verification/<date>-wrap-point-query-trap-repairs.md`, hosted
proof at step level for the PR-head and post-merge runs. Its post-slice review is a live
Mode-2 run that selects 55b; **D-17 escalates at this review**, and **D-27 goes into its
Candidate options** (Documentation Updates).

## Contract — 55b: `slice-55b-wrap-point-query`

Node 4 proper: new code only, on top of merged 55a; it touches no shipped measured path,
so a movement in any existing benchmark is a finding.

**Public API** (Decisions 3, 8, 10):

```swift
// ViewportTypes.swift
public enum VisualPointQuery: Equatable {
    case point(VisualPointLocation)
    case empty                            // empty document (lineCount == 0)
    case failure(ViewportValidationError)
}
public struct VisualPointLocation: Equatable {
    public let row: VisualRowLocation     // verbatim from visualRowAt (NOT a VisualRow — see Decision 3)
    public let rowSpan: VisualRow         // the located row's [startColumn, endColumn) + width
    public let column: ColumnResolution   // .cell(ColumnLocation) | .blankLine
}
// WrapPointQuery.swift
extension ViewportVirtualizer {
    public static func visualPointAt<Layout: VisualRowLayoutSource>(x: Double, y: Double, layout: Layout) -> VisualPointQuery
}
```

**The ladder** (canonical argument: Decision 5; step 7: Decision 14; the clamp: Decision 6):

```
1. visualRowAt(y:layout:)            → .failure / .empty propagate; else `row` (verbatim)
2. !x.isFinite                       → .failure(.nonFiniteValue)          — before any horizontal work
3. validateWrapLine(inLine: row.logicalLine, wrapWidth: layout.wrapWidth, metrics: layout)
                                     → .failure propagates; else (count, total)
   var cursor = VisualRowCursor(line:count:total:wrapWidth:metrics:)
   guard let rowSpan = advanceVisualRows(&cursor, by: row.rowInLine + 1)
                                     else → .failure(.invalidVisualRowLayout)   — walk exhausted early
4. rowSpan.startColumn == rowSpan.endColumn → .point(row, rowSpan, .blankLine)
5. x < 0                             → .cell(startColumn, .clampedToLeft)
6. x >= rowSpan.width                → .cell(endColumn − 1, .clampedToRight)
7. rowLeft  = layout.columnOffset(inLine: line, column: rowSpan.startColumn)    — 1 probe
   rebased  = rowLeft + x;  !rebased.isFinite → .failure(.nonFiniteValue)
   raw      = rebased >= total ? rowSpan.endColumn − 1                            — `total` from step 3, no probe
                               : layout.columnIndex(containingOffset: rebased, inLine: line)
   index    = min(max(raw, rowSpan.startColumn), rowSpan.endColumn − 1)          — Decision 6
                                     → .cell(index, .inRange)                     — the flag is written
```

**Probe counts** (canonical argument: Component Design; pinned by `WrapPointQueryCountTests`):

| Path | Layout axis (`firstVisualRow` + `visualRowCount`) | Column axis (`columnCount` + `columnOffset` + `canBreak`) | `columnIndex` hook |
|---|---|---|---|
| `.empty`, any vertical failure, non-finite `x` | as `visualRowAt` | **0** | 0 |
| located, fitting line, clamped `x` | `<= ceilLog2(lineCount) + 4` | exactly `3 + 2` | 0 |
| located, fitting line, delegating `x` | same | exactly `3 + 2 + 1` (on an overriding-hook conformer) | exactly 1 |
| located, wrapped line, interior row *k* | same | grows with *k*: rows `k+1…k+m` add ≥ `endColumn(k+m) − endColumn(k)` | ≤ 1 |

**Tests** (canonical: Testing Strategy), all in `Tests/TextEngineCoreTests/`:
`WrapPointQueryEquivalenceTests` (the ∞ oracle), `WrapPointQueryTests` (behaviour, Decision
6's two fixtures, the verbatim-`row` sweep), `WrapPointQueryValidationTests` (the ladder and
the three malformed-provider cases), `WrapPointQueryCountTests` (two counters, two fixtures),
`WrapPointQueryRoundTripTests` (agreement with `visualRowGeometry`); D-25 tightened in
`WrapRowQueryCountTests`. In `Tests/ViewportBenchmarksTests/`: `WrapPointQueryChecksumTests`,
`WrapPointQueryOptionsTests`, three new cases in `WrapBenchmarkLineShapeTests`.

**Drills, twelve observed reds** (definitions: Testing Strategy): (a), (b), (c), (d1)
composite pin, (d2), (d3), (e), (g), (h), (i), (j), (k).

**Benchmark mode `--wrap-point-query`** (canonical: Benchmark Mode / CI): observational,
`isGateable == false`, `absoluteCeiling == .scrollFrame`, not wired into CI, own
`WrapPointQueryLayout` (O(`lineCount` + `cells`) construction), scenario table as a
top-level value:

| Scenario | `lineCount` | `wrapWidth` | `cells` × `advance` | `operationsPerSample` | `fast_path` | `row_in_line` |
|---|---|---|---|---|---|---|
| `uniform_1k` | 1 000 | `∞` | 20 × 8 | 256 | true | omitted |
| `uniform_100k` | 100 000 | `∞` | 20 × 8 | 256 | true | omitted |
| `narrow_100k` | 100 000 | 40 | 20 × 8 (4 rows/line) | 256 | false | omitted |
| `clamped_y_100k` (`y` out of range, `x` in row) | 100 000 | 40 | 20 × 8 | 256 | false | omitted |
| `clamped_x_100k` (`y` in range, `x` past the row) | 100 000 | 40 | 20 × 8 | 256 | false | omitted |
| `long_line_deep_row` (last row of its line) | 1 000 | 40 | 2 000 × 8 (400 rows/line) | 16 | false | `399` |

Floors pinned by `WrapBenchmarkLineShapeTests`: `cells_per_line >= 1_000`, `rows_per_line >=
100` on `long_line_deep_row`; the plan may raise them, never lower them. Line tokens:
`mode=wrap_point_query scenario= total_rows= cells_per_line= rows_per_line= fast_path=
[row_in_line=] query_operations_per_sample= query_p95_ns= query_p99_ns= checksum=`.

**Documentation and ledger** (canonical: Documentation Updates): `AGENTS.md` node 4
paragraph, commands, flag lists, "both wrap modes" → three, `Tests/ViewportBenchmarksTests`
inventory; `VisualRowLayoutTestSupport.swift:49-53` comment; D-25 and D-18 → `discharged`;
the three map-pass items for the review.

**Record**: `docs/superpowers/verification/<date>-wrap-point-query.md`; twelve gates,
gated checksums, `--wrap-row-query` and `--wrap-compute` re-run flat against 55a's final
column, hosted step-level proof. Expected scoreboard delta: criterion 3 **partial → done**
(Goals).

## Source Context

Node 1 (Slice 49) shipped per-logical-line greedy row packing: one logical line + a wrap
width → its `VisualRow`s, each a half-open cell span `[startColumn, endColumn)` with an
advance-sum width, streamed by an O(1)-state `VisualRowCursor<Metrics: WrapMetricsSource>`
(`ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:)`).

Node 2 (Slice 50) shipped cross-line aggregation: `VisualRowLayoutSource` (the visual-row
axis), the third `compute(_:layout:)` overload over a uniform row axis, and
`DocumentVisualRowCursor`, whose init pays the **accepted within-line walk** — locate the
start line, then drive the per-line packer forward `rowInStartLine` times, because greedy
packing is sequential.

Node 3 (Slice 53) shipped `visualRowAt(y:layout:)`: the wrap-aware `lineAt` analog. It
returns a `VisualRowLocation` naming the row in **both** coordinate systems — `globalRow`
(what `compute(_:layout:)` ranges over) plus `logicalLine`/`rowInLine` (what `VisualRow`
speaks) — with the reused `LineLocation.Clamp`. Its own spec named that dual naming as what
would make node 4 "a composition rather than a re-derivation"; this design discharges that
claim.

The no-wrap precedent is `pointAt(x:y:lineMetrics:columnMetrics:)` (Slice 37): a pure
composition of `lineAt` over the vertical source and `columnAt` over a separate horizontal
source, adding no search of its own, with both clamp flags carried through verbatim.

## Problem

Criterion 3 of the wrap brief enumerates three wrap-aware query analogs: compute over
visual rows (node 2), y→row (node 3), and **point→(row, cell)**. The third is the last one
open, and it cannot be had by pointing `pointAt` at a wrap provider: `columnAt`'s `x` is
measured from the **logical line's** left edge and its clamps land on the line's edges,
while under wrap the thing on screen at a given `y` is a **visual row** — a `[startColumn,
endColumn)` slice of that line with its own left edge. A hit test in a wrapped viewport has
the row's left edge as its origin and knows nothing about the line's.

## Scope

One new public query on `ViewportVirtualizer`, two new public types, two internal helpers
extracted from shipped code and shared with their origin — the within-line walk out of
`DocumentVisualRowCursor` (Decision 4) and the per-line wrap ladder out of `visualRows`
(Decision 13) — one O(1) short-circuit in node 1's packer (Decision 12), five guards across
the consumers of `logicalLine(containingVisualRow:)` and the shared walk helper (Decision
4), the criterion-3 equivalence oracle for this analog, one new observational benchmark
mode, and four ledger fold-ins (D-24, D-29, D-25, D-18). **No provider contract changes**:
every capability the query needs already exists on `VisualRowLayoutSource` and its
refinements; no public type gains a field; both extractions keep their public entry point's
signature and behaviour; the short-circuit changes no result, only how many columns are
scanned to produce one.

**Five edits land on shipped code that produces observational numbers.** Four sit on
`--wrap-compute`'s path — the walk in `DocumentVisualRowCursor.init`, the ladder in
`visualRows` (reached from `makeInner`), the short-circuit in `greedyEnd`, and the drain body
in `WrapComputeBenchmark` — and one on `--wrap-row-query`'s, the guards in `visualRowAt`.
None is on a gated path (AC13's checksum baseline establishes that). Every one gets its own
commit, so a movement in a number is attributable to one edit, not a pair; Decision 12 is
the one edit *predicted* to move numbers, and its table says where and by how much.

**The work ships as two sequenced pieces, and that is a user call.** The slice carries a
new public query, two behavioural repairs to shipped node-3 code, two extractions, a packer
change, four fold-ins, a benchmark mode with six scenarios and eighteen drill reds —
materially above this arc's median. The cut is drawn along **shipped code versus new
code**, not along "repairs versus the feature": 55a takes every shipped-code edit
(including the two behaviour-neutral refactors, Decisions 13 and D-29), so its acceptance
is wholly negative and 55b moves `--wrap-compute`'s numbers not at all — a checkable claim.
The rejected cut, "repairs first, then the feature with its refactors", would leave piece B
carrying a new feature *and* two refactors of measured code, and a movement in
`--wrap-compute` could not be attributed without reading three commits across two branches.

**The order inside 55a is forced.** D-24's fix is a test-only conformer that **overrides**
`logicalLine(containingVisualRow:)` — precisely what turns the malformed-override category
from hypothetical into live. Landing it while the traps are still in the tree is the
configuration this design exists to avoid, so it is commit 6, after the guards, and 55b
reuses that conformer as its count suite's second fixture.

**"Separable" means *earlier*, never *dropped*.** Deferring the repairs past D-24 is not a
smaller version of this slice, it is the rejected configuration. If 55b proves too heavy,
the only candidate to lift out is D-29 — a genuinely worse cut, because D-29 is the
falsifiability audit's **mandatory** option and the arc map assigned it to this node by
name; the `choosing-next-slice` rule makes such an item a mandatory *candidate option*, not
a mandatory fold-in, so the move would be legal, but it must be recorded as a call against
the mandatory option rather than made silently.

**The split moves two ledger deadlines by arithmetic, and that is a cost.** D-27's row says
"schedule by slice 56"; with 55b occupying that position, D-27 ages one cycle for no reason
connected to its merits — the mechanism the row was written to name. D-17's row says it
escalates at slice 55's review; with two reviews, that is **55a's**, the first. Neither call
is made here — selection belongs to the review and the user — but 55a's review must put
D-27 in its Candidate options and either schedule it or record a deliberate re-read of the
deadline as "the slice after 55b". Silence is the one outcome ruled out.

## Goals

1. **`visualPointAt(x:y:layout:)`** maps a point to `(visual row, cell)` over a single
   `VisualRowLayoutSource`, with `x` measured from the located row's left edge.
2. **No new search.** Every search the query performs is one an existing entry point already
   performs, dispatched through the same provider-overridable hooks.
3. **The infinite-width equivalence oracle** holds on the located branch: at `wrapWidth =
   ∞` (or any width no line exceeds) the result is bit-identical to `pointAt` over a uniform
   line axis and the same horizontal metrics.
4. **Honest cost.** The within-line walk inherited from node 2 is stated, tested and
   measured, not hidden behind the logarithmic terms; Decision 12 confines the column scan
   to rows whose remaining suffix does not fit, so a line that fits (`∞` included) and the
   last row of any line pack in O(1) unless it overflows, and at `∞` the query's cost
   class equals `pointAt`'s.
   Which scenarios pay the walk is printed, not inferred (Benchmark Mode / CI).
5. **Four ledger items discharged** — D-24, D-29 (the falsifiability audit's mandatory
   option), D-25 and D-18 — counted here because the review's ledger delta counts what the
   Goals claim.
6. **No malformed `logicalLine(containingVisualRow:)` override reaches a trap, at any site
   that consumes the hook's answer, and `visualRowAt` never returns a location naming no
   row.** The sites, the guards and why each guard sits where it does are Decision 4's; the
   substance of this goal is that the guard lands at each **producer** and the query
   inherits trap-freedom by `.failure` propagation. The goal is stated at the width it is
   kept: a provider whose `columnCount(inLine:)` disagrees with its own offset storage still
   traps inside the per-line ladder at `columnOffset(inLine:column: count)`, exactly as it
   does under `columnAt` — that class stays GIGO and is unchanged.

**Expected scoreboard outcome:** criterion 3 goes **partial → done**. It enumerates three
analogs and an equivalence oracle; nodes 2 and 3 shipped two, this slice ships the third
with its oracle, and the no-wrap path is untouched. The geometry companions it does *not*
enumerate are Non-Goal 1; if the review reads the criterion as covering them, the delta is
`partial`, and that reading is stated here so the review confirms or contradicts it
deliberately.

## Non-Goals

1. **A geometry-bearing companion** (the wrap analog of `pointGeometryAt`). Decision 9.
2. **Caret snapping and affinity.** At a soft break "after the row's last cell" and "before
   the next row's first cell" are the same document position; which one a caret shows is a
   caller concern, as `columnGeometryAt` already states. The result carries what the caller
   needs to decide — the row span and the clamp flag — and does not decide.
3. **The inverse** `(row, cell) → (x, y)`.
4. **Random access inside a logical line** — a provider-native seam answering "row *k* of
   line *L*" without packing rows 0…*k*. Deferring costs nothing in API terms: the seam
   would arrive as a protocol requirement **with a default implementation**,
   source-compatible for every conformer. The cost it would remove is measured by
   `long_line_deep_row` from this slice onward, and it is the standing answer if node 6's
   absolute ceiling is breached (Risks And Gaps). Decision 12 neither pre-empts nor shrinks
   it: the short-circuit decides "does the remaining suffix fit" in O(1) from a value the
   packer already holds; the seam decides "where does row *k* start", which no O(1)
   predicate can. After Decision 12 only the interior rows of genuinely wrapped lines can
   drive a ceiling breach, which sharpens the case for the seam. It is on no arc-map node
   and in no ledger row today; Documentation Updates makes putting it there part of this
   slice's map pass.
5. **`--memory-shape` extension** to the wrap path (node 5) and **gate promotion** of any
   wrap mode (node 6).
6. **A shipped wrap reference provider.** Wrap conformers stay test-local and
   benchmark-local, as in nodes 1–3.
7. **D-13** (per-axis binary-search triplication). Decision 11.

## Decisions

### Decision 1 — `x` is measured from the located row; clamps land on the row's edges

**User call.** `x = 0` is the left edge of the row located by `y`. An `x` below the row's
left edge clamps to the row's first cell (`.clampedToLeft`); an `x` at or beyond the row's
right edge clamps to the row's last cell (`.clampedToRight`). For a hit test this is the
viewport's own frame: every visual row is drawn from the left margin, so row-relative and
viewport-relative coincide.

Rejected alternatives, with reasons kept:

- **Line-relative `x`** (the mechanical reuse of `columnAt`): the caller would have to add
  `columnOffset(inLine:column: startColumn)` itself — the row's left offset is precisely
  what it does not know, and getting it costs the within-line walk this query exists to
  perform. Unusable for hit testing.
- **Row-relative `x` with clamps only at the line's edges** ("continuous line"): an `x`
  past a middle row's right edge would return a cell belonging to a *later* row with
  `.inRange`, so the returned row and cell would contradict each other while `y` picked the
  row. Not a point in the document's visual layout.

At a width no line exceeds, every line packs to one row starting at column 0, whose offset
is 0 by contract — row-relative and line-relative coincide, and Goal 3's oracle is
unaffected by this decision.

### Decision 2 — The returned column index is line-absolute

`ColumnLocation.columnIndex` is an index into the **logical line**, not into the row. `x`
is row-relative and the index is line-absolute, deliberately: the index is a document
coordinate (the same quantity `columnAt` returns, the one that addresses text), `x` is a
screen quantity, and `rowSpan.startColumn` is the bridge in both directions.

Both quantities are in **visual order** — the brief's «ряды описываются в визуальном
порядке», inherited unchanged from node 1's cell model. Bidi is out of the brief's scope,
so visual and logical order coincide today; the doc comment still says which one is
promised, because the day they stop coinciding is the day a caller needs to know this index
was never the logical one.

Recorded as its own decision because a later veneer silently gets it wrong; the swept
property in `WrapPointQueryTests` pins `columnIndex ∈ [startColumn, endColumn)` so a
row-relative regression cannot pass.

### Decision 3 — Result shape: `VisualRowLocation` + `VisualRow` + `ColumnResolution`

**User call.** The types are in Contract 55b. `row` is carried **verbatim** from
`visualRowAt`, mirroring how `PointLocation` carries `LineLocation` verbatim from `lineAt`.
`rowSpan` is returned because the core computes it anyway (Decision 4 needs it to rebase
`x`) and re-deriving it would cost the caller a second within-line walk; without it,
`.clampedToRight` cannot be told from a soft break at the row's end, which is exactly what
a caret needs to know. `ColumnResolution` is **reused**: `.blankLine` means the located
line has no cells, exactly as in `PointLocation`.

**A naming collision to state in the doc comments**: `VisualRowGeometry.row` is a
`VisualRow`, while `VisualPointLocation.row` is a `VisualRowLocation` and the `VisualRow`
sits under `rowSpan`. Each is locally right — `.row` mirrors `PointLocation.line:
LineLocation` here, and `VisualRowGeometry` composes node 1's type there — but across the
two wrap types the pair is a foot-gun, so both fields carry a doc comment naming their type.

The cost is that `logicalLine` and `rowInLine` appear in both fields. They agree by
construction, and a test pins the agreement (Testing Strategy says what that pin actually
catches). The rejected shapes — a flattened struct with no duplication, and the minimal
`PointLocation` mirror that discards the span — are in the brainstorm: the flattened one
loses "verbatim from `visualRowAt`", the minimal one moves an unavoidable cost onto every
caller.

`rowLeft` (the row's left offset in the line's coordinate space) is **not** returned,
although the core computes it too. Caller cost settles it: re-deriving `rowSpan` costs the
caller a second within-line walk, re-deriving `rowLeft` is one O(1)
`columnOffset(inLine:column:)` call on the provider it already holds.

### Decision 4 — Composition over three existing entry points; the walk is shared; guards live at the producers

**User call** (the composition; its step 7 was re-decided as Decision 14). The
implementation is the ladder in Contract 55b: `visualRowAt` for the whole vertical half;
`x`'s finiteness; the shared per-line wrap ladder (Decision 13) over `row.logicalLine`, a
`VisualRowCursor` over its `(count, total)`, walked to row `rowInLine` by the shared helper
— **one derivation of `rowSpan`, unconditionally**, since Decision 12's O(1) case lives
inside the packer; then the clamp/delegate steps of Decision 5, whose delegating branch
dispatches to the provider's `columnIndex(containingOffset:inLine:)` hook (Decision 14).
Every search is one an existing entry point already performs, through the same hooks.

**The walk is shared code, not a second copy.** Otherwise the "drive the per-line packer
forward *k* rows" loop would exist twice — `DocumentVisualRowCursor.init`
(`DocumentVisualRowCursor.swift:31`) and this query — the seed of another D-13-shaped row.
Both call `advanceVisualRows` (signature in Contract 55a): advance a `VisualRowCursor` by
*k* rows and return the last row consumed. **`k` is a count of `next()` calls, not a row
index**: the cursor passes `k = rowInStartLine` and discards the return (its next `next()`
then yields row `rowInStartLine`, exactly as today); the query passes `k = rowInLine + 1`
and keeps it. A wrong `k` is the plausible edit, and the duplicated-field assertion in
`WrapPointQueryTests` is what catches it. The cursor's and the query's idea of "row *k* of
line *L*" becomes identical **by construction** rather than by two tests agreeing.

**The signature is `inout`, and that is not incidental.** `VisualRowCursor` is a struct; a
helper taking it by value would advance a copy and leave both call sites unchanged — a
mutation that compiles, passes the round-trip test's first row, and diverges after it. On
the cursor's side the receiver is `inner`, an `Optional`, so the call is `&inner!` under the
cursor's own `nil` guard (a force-unwrapped `Optional` `var` is an addressable lvalue); if
that does not compile, the fallback is `if var c = inner { _ = advanceVisualRows(&c, by:
k); inner = c }`. Either form is acceptable; quietly reverting to a by-value helper is not.
The cursor's `inner` stays `Optional` (`makeInner` returns `nil` on a malformed line) and
the cursor guards before calling the helper, so the `nil`-inner path keeps its shipped GIGO
meaning.

**The helper's return is the *k*-th `next()` result, and it owns two degenerate bounds.**
The return is defined as the value of the *k*-th `next()` call — `nil` if any of the *k*
calls returned `nil`, row *k−1* otherwise — and **not** the last non-`nil` row seen along
the way: under that reading a cursor exhausted at row *j* < *k* would hand the query a real
row carrying the wrong `rowInLine`, and step 3's exhaustion guard (Decision 5) would be dead
code. The two bounds: `k < 0 → nil` *before* forming `0..<k`, and a stop at the first `nil`
the cursor yields rather than spinning the remaining iterations (a provider reporting far
more rows than the packer yields would otherwise burn `k` iterations on a cursor returning
`nil` since iteration three). The first is what makes the *helper* total for any future
call site; it is **not** what repairs either shipped caller, and the distinction is
load-bearing: `nil` is also what `by: 0` yields on the overwhelmingly common healthy input
(`bufferStart` on a line boundary), and a caller inspecting the return cannot tell `k < 0`
from `k == 0`. Both callers therefore guard their own input, below.

**The five guards, and why each sits where it does.** `logicalLine(containingVisualRow:)`
has exactly **two** places in the tree where its answer is consumed — `grep -rn "func
logicalLine(containingVisualRow"` finds only the requirement and the default, `grep -rn
"logicalLine(containingVisualRow:"` finds the two call sites (`WrapPositionQuery.swift:40`,
`DocumentVisualRowCursor.swift:27`) — and both feed it straight into an array-backed
accessor without a range check. The default hook cannot
misbehave (`binarySearchLogicalLine` structurally returns an index in `[0, lineCount)`
whose `firstVisualRow` is `<= g`), so every branch below is unreachable for every
non-overriding conformer and no existing test moves; an override can, and D-24 — landed in
55a — puts the first overriding conformer into the tree. The table is in Contract 55a;
what it does not say:

- **Guard 1 (`visualRowAt`, `logicalLine ∉ 0..<lineCount`)** is the guard that covers
  `visualPointAt`, and the only placement that can: the query does not call the hook, it
  consumes `visualRowAt`'s answer one frame after `visualRowAt` has already subscripted the
  array at `WrapPositionQuery.swift:41`. A check inside the query would be a guard that
  never runs. **The trap site is exact only above the boundary**: every conformer in the
  tree sizes its `firstVisualRow` array at `lineCount + 1` (`TestVisualRowLayout.firstRow`,
  `VisualRowLayoutTestSupport.swift:13`; `BenchmarkWrapLayout.firstRow`), because the layout
  ladder itself probes `firstVisualRow(ofLine: lineCount)` (`WrapViewportVirtualizer.swift:31`).
  A hook answering exactly `lineCount` does not trap at `:41` — it reads `totalRows`,
  yields a negative `rowInLine`, and traps later, elsewhere (in the query, at
  `columnCount(inLine: lineCount)`) or fabricates a row on a provider with total accessors.
  The `0..<lineCount` check covers all three ways the answer can leave the range (`>
  lineCount`, `== lineCount`, `< 0`); the **test** carries all three values — the negative
  one because the natural wrong edit is `logicalLine < lineCount` alone, which the two upper
  values cannot see — and drill (d1) runs on `> lineCount`, the value that traps at the
  named site.
- **Guard 2 (`visualRowAt`, `rowInLine < 0`)**: `:41` computes `globalRow −
  firstVisualRow(ofLine: logicalLine)`, and an in-range line whose `firstVisualRow` exceeds
  `globalRow` — the other way an override can lie — makes it negative. One comparison on a
  value in hand, no probe (counter 1's bound is untouched). Without it `visualRowAt` hands
  its callers a location naming no row; with it, the query's `k = rowInLine + 1` is `>= 1`
  by the producer's guarantee, and the helper's `nil` has exactly one meaning for the query
  ("exhausted early"). The upper bound `rowInLine < visualRowCount(inLine:)` is deliberately
  **not** checked: it costs a layout-axis probe, widens node 3's `+ 4` bound, and the
  walk's early exhaustion already catches it at the point of use.
- **Guards 3 and 4 (the cursor)** cannot live in the helper: the out-of-range `startLine`
  traps at `layout.firstVisualRow(ofLine: startLine)` (`:28`) and again in `makeInner`'s
  `columnCount(inLine:)` — *before* the walk the helper owns begins — and the negative
  `rowInStartLine` traps at `:31` (`0..<k`, SIGTRAP, exit 133, verified against the shipped
  code), which the helper's own `k < 0` rule would survive but could not *signal* (see
  above). **Both outcomes are `streams nothing`**: the cursor enters the terminal state it
  already has (`inner = nil`, `remaining = 0` — `DocumentVisualRowCursor.swift:21-26`),
  because streaming has no failure channel — the GIGO rule node 2 stated from the other
  side. Three neighbouring outcomes are ruled out by name because they are what an
  implementation drifts into: letting the helper return `nil` while the cursor ignores it
  streams the start line **from row 0** (a plausible-looking wrong answer); setting `inner =
  nil` without zeroing `remaining` **skips** the start line; and trapping is what the repair
  removes.
- **Guard 5 (the helper)** is unreachable from any public entry point once guards 2 and 4
  exist, so it is pinned by a direct `@testable` unit test (Testing Strategy).

The two consumers differ in what a *detected* degeneracy becomes — the query has a
failure channel and returns `.failure(.invalidVisualRowLayout)`, the stream has none and
stops — and that is the intended divergence. Neither traps.

**The cost, stated rather than absorbed.** `visualRowAt` is shipped node-3 code that node
3's spec did not scope for repair; the two guards are three comparisons on two
unreachable-by-default branches, but they convert a trap and a returned non-location into
returned failures — observable behaviour — and they narrow, without falsifying, node 3's
"`compute(_:layout:)` and `visualRowAt` accept and reject exactly the same layouts by
construction" claim. That claim is about the shared `validateVisualRowLayout` ladder and
survives; the two entry points now diverge *after* the ladder on one class of layout:
`compute` never consults the hook, so it accepts a layout whose override is malformed,
while `visualRowAt` rejects it and the cursor streams nothing — three channels, three
answers, each correct for what that entry point can observe. The wording is narrowed to the
ladder in its three places (Documentation Updates). The alternative — leaving the traps and
narrowing Goal 6 to providers whose `firstVisualRow` is total — was rejected: it would ship
D-24's overriding conformer into a tree with a known reachable trap on the path that
conformer exercises.

**`VisualRow` does not carry the row's start offset**, although node 1's packer computes
it (`startOffset`, `VisualRowCursor.swift:35`), so step 7 re-probes
`columnOffset(inLine:column: startColumn)`. Two ways to avoid that probe are rejected:
widening node 1's shipped public `VisualRow` (a public API change for one O(1) probe), and
returning it through the helper (new internal state on `VisualRowCursor`, a further edit to
shipped code, for one O(1) probe on the located path). The re-probe re-reads a value the
contract already requires to be stable; it costs a probe and buys nothing back.

Rejected alternatives for the composition itself:

- **Reuse `DocumentVisualRowCursor` over a synthetic one-row range.** Less new code and
  y/height would come free, but its init re-runs `logicalLine(containingVisualRow:)` — the
  search `visualRowAt` just performed — so the query would perform two where the family's
  rule is "no new search", and it would violate the cursor's documented precondition that
  the range came from `compute(_:layout:)`.
- **A row-scoped binary search** over `[startColumn, endColumn)`. O(log cells-in-row)
  instead of O(log cells-in-line) — the same class, a constant apart — bought with a
  **fourth** copy of the binary-search body (feeding D-13) and, decisively, with bypassing
  `columnIndex(containingOffset:inLine:)`, so a provider with a native inverse would lose it
  on this path only.
- **Composing `columnAt`** for step 7 — the brainstorm's original wording. Decision 14.

### Decision 5 — The ladder: precedence, and why `x`'s finiteness is checked explicitly

The steps are in Contract 55b. What each step means, in the order that matters:

- **Step 1** propagates `visualRowAt`'s whole vertical ladder verbatim (`lineCount < 0` →
  `y` finite → `validateVisualRowLayout` → `.empty`), including both of Decision 4's
  producer guards. An out-of-range `logicalLine` or a negative `rowInLine` therefore never
  reaches step 3, and no check for either lives in the query: putting one here would be dead
  code, and putting the *only* one here would be a guard that never runs.
- **Step 2** exists for `±∞`, not for `NaN`. `NaN` would fall through steps 5–6 (every
  comparison against `NaN` is false) and fail at step 7's `rebased.isFinite`; but `+∞ >=
  rowSpan.width` and `-∞ < 0` are both **true**, so an infinite `x` would silently clamp —
  `+∞` to the row's last cell, `-∞` to its first — breaking the family rule "a non-finite
  coordinate is a failure, not a clamp" that `pointAt`'s doc comment states. Two named tests
  say so, one per sign: each infinity reaches a different clamp branch, so one test cannot
  stand for the other. The rung sits **before any
  horizontal work**, and AC7's zero-column-metric pin is the only observation of that
  placement (Testing Strategy).
- **Step 3** runs the shared ladder (Decision 13) — the same three probes and the same
  `.failure`s as `visualRows`, which propagate — then the walk. Its `.nonPositiveWrapWidth`
  branch is unreachable here (step 1 validated `wrapWidth`) and is mapped through rather
  than force-unwrapped, following `visualRowAt`'s treatment of its own unreachable branches.
  The helper's `nil` means exactly one thing on this path: the walk ran out before row
  `rowInLine` — a provider whose `firstVisualRow`/`visualRowCount` disagrees with the packer.
  Decision 12 cannot bypass that detection: the short-circuit decides where *one* row ends,
  so a line that fits the width but is asked for row 2 still runs the walk, consumes its one
  row, and fails here.
- **Steps 4–6** need no probe: the blank row is read from the span (Decision 7), and the
  two clamps compare against the **row's** own advance-sum width — so on an overflow row (an
  unbreakable run wider than `wrapWidth`) an `x` between `wrapWidth` and `rowSpan.width` is
  `.inRange`. Clamped queries take a special case here, a divergence from node 3 (whose
  Decision 7 records that a clamped `y` needs none); it costs no validation coverage, since
  step 3's ladder is the query's only column-axis validation and it has already run.
- **Step 7** is Decision 14; its FP clamp is Decision 6. `rowLeft` is read there and
  nowhere earlier — steps 5–6 do not use it, and reading it up front would spend a probe on
  the clamped path AC7 pins at zero hook calls.

**The precedence rules, and the pairs worth naming.** Vertical failures beat a non-finite
`x`; a non-finite `x` beats every horizontal failure and every clamp. Two pairs are
structural rather than written, and each has a named test in `WrapPointQueryValidationTests`
because AC7's zero-probe pin covers their *cost* and says nothing about their *value*:
`.empty` beats a non-finite `x` (step 1 propagates before step 2 runs, so
`visualPointAt(x: .infinity, y: _, layout: emptyLayout)` is `.empty` — matching `pointAt`,
whose doc comment states the same outcome for the same reason), and a non-finite `x` beats
`.blankLine` (step 2 runs before step 4, as `columnAt` checks `x` before its `count == 0`
short-circuit, `HorizontalPositionQuery.swift:23-33`).

**Rejected alternative:** running the shared ladder before the `x` rung, so
`.negativeColumnCount` beats a non-finite `x` as it does in `columnAt`. Its price: the
shared ladder is **atomic** under Decision 13, so putting it first spends **three**
column-axis probes on a query already known to fail. Be precise about what that buys,
because the cheap misreading is "parity with `columnAt`": `columnAt` does **not** run its
whole ladder first — its `x` rung sits after the single `columnCount` probe and *before*
`columnOffset(inLine:column: 0)` (`HorizontalPositionQuery.swift:18-30`). Mirroring that
precedence exactly would cost one probe, not three, but would require splitting the shared
ladder so the `x` check could sit inside it, trading Decision 13's neutrality argument for
an ordering nothing observes. Either form breaks AC7's "zero column-metric calls on a
non-finite `x`" pin outright — the *only* observation distinguishing step 2's placement from
its result — for an ordering no oracle checks (node 3's oracle is scoped to the located
branch precisely because the wrap and no-wrap ladders differ by design) and no consumer can
act on, since both outcomes are failures.

**Step 7's GIGO cases, at their true width.** The shared ladder validates `columnOffset` at
columns `0` and `count` only; interior `columnOffset`/`canBreak` are re-read without
re-validation (`DocumentVisualRowCursor.swift:38-42` records this for the cursor). A
non-finite offset **at the row's `startColumn`** makes `rowLeft`, hence `rebased`,
non-finite → `.failure(.nonFiniteValue)` from step 7's own finiteness check — the same
answer `columnAt`'s rung would have given. A non-finite offset at the row's **`endColumn`**
leaves `rowLeft` finite and makes `rowSpan.width` `NaN`, so steps 5–6 are both false, step
7 runs the hook over garbage, and Decision 6's clamp confines the answer to `[startColumn,
endColumn − 1]`: a **cell**, not a failure. Both are the GIGO class node 1 already
documents and both propagate safely — no trap, no fabricated row outside the span. The
claim is "safe", not "always a failure".

### Decision 6 — The rebased `x` is clamped into the row's span; two fixtures

Step 7 adds `rowLeft` to a row-relative `x`. Under the `columnOffset` contract (finite,
**strictly** increasing within a line) the located index lies inside `[startColumn,
endColumn)` for every `x ∈ [0, rowSpan.width)` — in exact arithmetic. In `Double`
arithmetic it need not: `rowSpan.width` is itself the rounded difference
`columnOffset(endColumn) − rowLeft`, so at magnitudes near 2^53 an `x` strictly below that
difference can rebase to a value that rounds to `columnOffset(endColumn)` or above, and the
hook then answers with a cell belonging to the **next** row. The located index is therefore
clamped into `[startColumn, endColumn − 1]` before the result is built — one comparison
pair, and it makes Decision 2's swept property structural rather than contract-dependent.
**The clamp moves the index and not the flag**: `x` was inside `[0, rowSpan.width)`, so the
result stays `.inRange`; a clamp that flipped the flag would report a right-edge hit for a
point in the row's interior, a different wrong answer.

**Fixture 1 — the clamp fires.** The located row must sit **away from the line's end**,
otherwise the rounding lands on `total`, Decision 14's `>= total` guard answers
`endColumn − 1`, and the clamp has nothing to do. The working form, checked by hand (ulp is
2 at `1e16`; every offset is exactly representable and strictly increasing, so it is legal
input and `TestVisualRowLayout` takes it as-is):

```
advances  [1e16, 4, 4]        →  offsets [0, 1e16, 1e16 + 4, 1e16 + 8]
breaks    before columns 1, 2
wrapWidth 4
  row 0 = [0, 1)   (overflow: one cell wider than the width)
  row 1 = [1, 2)   rowLeft = 1e16,  width = (1e16 + 4) − 1e16 = 4   (exact)
  x = 3.9  <  width, yet 1e16 + 3.9 rounds to 1e16 + 4 == columnOffset(2) < total
  → the hook answers cell 2, outside row 1's span; the clamp answers 1, .inRange
```

The test asserts both halves — the unclamped index leaves the span, the shipped query does
not — and the flag beside the index. **If the fixture turns out not to fire**, the clamp is
removed and the property is documented as resting on the contract instead; the decision is
not kept with an unreachable branch and an untestable claim. (The fixture has been checked
by hand and does fire; the plan still observes it rather than inheriting the claim.)

**Fixture 2 — the `>= total` guard fires, and the hook is not called.** Drop the third
advance and the rounding lands on the **line's** width:

```
advances  [1e16, 4]          →  offsets [0, 1e16, 1e16 + 4]
breaks    before column 1
wrapWidth 4
  row 0 = [0, 1)   (overflow)
  row 1 = [1, 2)   rowLeft = 1e16,  width = 4   — and endColumn == columnCount
  x = 3.9  <  width, yet 1e16 + 3.9 rounds to 1e16 + 4 == total
  → rebased >= total: the guard answers endColumn − 1 = 1, .inRange, and the hook is NOT
    called — calling it would violate its precondition (`x < lineWidth`)
```

The test runs on a conformer that **overrides** `columnIndex(containingOffset:inLine:)` and
records every argument it receives, asserting zero calls on this input and `(1, .inRange)`
as the result. Both fixtures are needed and neither subsumes the other: the three-advance
one puts the rounding strictly inside the line so the clamp is what saves the answer, the
two-advance one puts it at the line's end so the guard is. Drills (e) and (k).

### Decision 7 — The blank row is detected from the span

`rowSpan.startColumn == rowSpan.endColumn` ⟺ the line is blank: node 1's `greedyEnd`
returns an end strictly greater than the start for every non-blank line, and a blank line
packs to exactly one `[0, 0)` row. Using the span costs no probe; a second
`columnCount(inLine:)` call would.

### Decision 8 — Naming: `visualPointAt`, not an overload of `pointAt`

The visual-row family already names itself `Visual*` (`VisualRow`, `VisualRowQuery`,
`VisualRowLocation`, `VisualRowCursor`, `VisualRowGeometry`, `VisualRowLayoutSource`), and
node 3 chose a distinct name (`visualRowAt`) over overloading `lineAt` for the same reason:
the answer is in a different index space. Here there is a sharper reason — `x` means
something different (measured from the row, not the line), so an overload sharing the name
`pointAt` would put two coordinate conventions behind one identifier.
`compute(_:layout:)`'s precedent (an overload) does not apply: its argument means exactly
what the other overloads' arguments mean.

### Decision 9 — Index-only; the geometry companion is a later node

**User call.** Criterion 3 enumerates `point→(row, cell)`, not its geometry-bearing
companion; `visualRowAt` shipped without one; and slices 37→39 set the precedent that the
composite and its companion are separate slices. This query already returns part of what a
companion would add — the row's cell span — because Decision 4 computes it.

Two things are recorded for the map pass so the later node inherits them instead of
re-deciding: the companion is **smaller than the precedent suggests** — its vertical half is
arithmetic (`y = globalRow * rowHeight`, `height = rowHeight`, both available to the caller
with no probe), so it adds the cell's box and the two within-box fractions, one axis; and
**its coordinate frame is settled by Decision 1** — `x` goes in row-relative, so the cell's
box must come back row-relative, bridged by `rowLeft`, which Decision 3 does not return and
the companion either re-probes (one O(1) call) or builds a row-relative box from.

### Decision 10 — File placement mirrors the existing sources

The file lists are in the two Contracts. The rule behind them: the query beside
`WrapPositionQuery.swift`; the new types in `ViewportTypes.swift` beside
`PointQuery`/`PointLocation`, where every `Visual*` type already lives; each extracted
helper beside the code it is extracted from; the benchmark with its **own** layout type
(Benchmark Mode / CI), not a change to `BenchmarkWrapLayout`; benchmark-target tests in
`Tests/ViewportBenchmarksTests/`, mirroring `WrapRowQueryChecksumTests.swift` /
`WrapRowQueryOptionsTests.swift`, with the line-shape cases added to the **existing**
`WrapBenchmarkLineShapeTests.swift`, not a new file.

### Decision 11 — D-13 is not folded in

D-13 (three copies of the per-axis binary-search body) rides on merit, not proximity. This
slice adds no fourth copy — Decision 4 rejected the row-scoped search partly for that reason
— so it produces no new evidence for or against consolidation and no natural home. It stays
open, routed to whichever slice adds a fourth axis or a provider-native hook that makes the
shared shape load-bearing.

### Decision 12 — The packer short-circuits when the remaining suffix fits

**Not a user call**; adopted during review. It lives in **node 1's packer**, not in the
query: `greedyEnd` (`VisualRowCursor.swift:57-74`) looks for the largest legal end that
fits, and `columnCount` is **always** a legal end, so whenever the remaining suffix fits the
width there is nothing to search for. The branch is in Contract 55a; `total` is the line's
total advance, stored on the cursor by Decision 13's ladder — a stored value, not a probe.

**Correct for every row, not only the first, and bit-identical to the scan.** The predicate
appeals neither to the provider's row counts nor to `start == 0`. Under the `columnOffset`
contract (finite, strictly increasing), `columnOffset(c) − startOffset <= total −
startOffset` for every `c <= columnCount`; IEEE subtraction of a common operand is
monotone, and the scan compares in exactly the same form (`columnOffset(c) − startOffset <=
wrapWidth`, `VisualRowCursor.swift:65`), so if the suffix fits then every legal end fits,
the scan's `break` is unreachable, and `lastFitting` finishes at `columnCount` — what the
short-circuit returns. On an interior-GIGO `NaN` `startOffset` both forms fall to
`firstLegal`. An optimization, not a behaviour change.

**What it changes, per row** (the cost table Component Design refers to):

| Located row | Columns scanned to pack it |
|---|---|
| The only row of a line that fits `wrapWidth` (every line at `∞`; unwrapped lines at any width) | **0** — `greedyEnd` returns `columnCount` on the suffix check |
| The **last** row of any line | **0** — same check; its remaining suffix fits by definition |
| An interior row *k* of a wrapped line | O(columns from the line's start to the end of row *k*) — the walk packs rows 0…*k* |

So a line that fits packs in O(1), the query's cost class at `∞` equals `pointAt`'s (where
without the branch even the *first* row costs O(cells in it), and at `∞` the first row is
the whole line — same answer as `pointAt`, different cost class, on exactly the oracle's
input), and `DocumentVisualRowCursor` inherits both wins because it calls the same
`greedyEnd`. What node 6 must still measure is the third row: `long_line_deep_row` targets
the last row of its line, whose own packing is now O(1), but reaching it still packs rows
0…*k−1*, so the walk term is undiminished and the scenario keeps measuring what it exists
to measure. The residue is real and unchanged: on a wrapped line, reaching interior row *k*
costs O(cells up to its end), and the random-access seam (Non-Goal 4) is the only thing
that would change it.

**What it does to `--wrap-compute`, predicted per width and per token.** The mode packs
every line twice: in `BenchmarkWrapLayout.init` (`WrapComputeBenchmark.swift:15-36`, the
`reindex_ns` token) and in the drain, which streams the buffer through the same `greedyEnd`
(`DocumentVisualRowCursor` → `makeInner` → `next()`, the `drain_*` tokens). `compute_*`
never touches the packer and must not move. On the mode's fixture (`cells = 80`, `advance =
1`, `WrapComputeBenchmark.swift:94-96`), `greedyEnd` scan iterations per line:

| Width | Rows/line | Before → after | `reindex_ns` and `drain_*` |
|---|---|---|---|
| `inf` | 1 | 80 → 0 (the only row is the last row) | fall the most — smoke test: reindex 0.45, drain p95 0.55 |
| `40` | 2 | 41 + 40 → 41 + 0, i.e. 81 → 41 | fall less — 0.68 / 0.80 |
| `10` | 8 | 7 × 11 + 10 → 7 × 11 + 0, i.e. 87 → 77 | fall least — 0.93 / 0.92 |

**Time falls less than iterations.** The scan costs about 1.5 ns per cell on this fixture,
and what remains per row does not shrink: `makeInner`'s cursor construction through
`visualRows`, protocol-witness dispatch on the layout, the layout value's retain/release
per line, the `VisualRowGeometry` itself. So the ratios are ordered `inf` < `40` < `10` < 1
but sit nowhere near the iteration factors — the numbers in the table are what the plan's
smoke test measured (Apple silicon, one run each side, 2026-08-28), with `compute_*` inside
the noise and all three checksums identical. `reindex_ns` at `inf` carries a second effect
the record must name: it is the first width the mode runs, so its one-shot construction
pays the cold caches and the fresh 100 000-entry array's page faults — a pre-existing
property of the mode, recorded rather than repaired here.

Every direction is a prediction the record confirms (Verification): a flat `width_inf`, a
`width_40` that falls less than `width_10`, or a `compute_*` that moves is a finding. "`width_inf`
falls and the rest holds still" is the wrong prediction — it forgets that the last row of a
wrapped line is the same O(1) case — and a record carrying it beside a `width_40` column
that fell by a fifth would force a reviewer to file the fall as an instrumentation bug. That is a
genuine speed-up of the measured operation, not a weakening of the measurement: at the
finite widths every line still wraps, the interior rows still scan, and the mode keeps
measuring the reindex it exists to measure.

**What it buys against the rejected query-side form** — `visualPointAt` itself synthesizing
the `VisualRow` `[0, columnCount)` whenever the line fits and skipping the packer: the last
row of any line (no query-side predicate can reach it); the cursor and `--wrap-compute`'s
drain (the query-side form gave them nothing); **one derivation of `rowSpan`** — a
query-side fast path synthesizes a row the packer would otherwise have produced, so the two
*can* disagree, and policing that divergence costs an agreement test, a two-kind fixture, a
fixture guard and a drill, an apparatus that exists only to contain a divergence the design
chose to create; and an **∞ oracle that still exercises the packer** — the query-side form
would have every line in the oracle's fixture bypass node 1's packing entirely, leaving the
oracle's horizontal half near-tautological.

**What it costs.** Two more O(1) probes on the fitting path than the query-side form — the
cursor's `next()` still reads `columnOffset` at the row's start and end
(`VisualRowCursor.swift:35`, `:43`) where a synthesized row read neither; the cost class is
unchanged. And an edit to node 1's shipped packer, the fifth on shipped code (Scope), with
the predicted `--wrap-compute` movement above.

**Rejected refinement:** eliding those two probes by reading `0` for `columnOffset(start)`
when `start == 0` and `total` for `columnOffset(end)` when `end == columnCount` — both
values the ladder validated. Correct, and it would make the fitting path cost zero extra
probes; not taken, because it puts two conditionals inside the packer's hottest routine
whose correctness depends on a validation performed in a *different* function — the kind of
cross-file coupling that survives the slice that understood it and breaks in the one that
does not.

**Rejected form:** a `visualRowCount(inLine:) == 1` predicate. It would trust a provider
number where this form trusts only the metrics the packer itself reads — a provider lying
about `visualRowCount` could make a whole line come back as one row, silently — and it would
land on the **layout** axis and widen AC7's `ceilLog2(lineCount) + 4` bound, which node 3
measures at 14 with no slack (`WrapRowQueryCountTests.swift:103-111`). The adopted form
reads a stored value and touches **neither** axis; if a plan step finds itself widening that
constant, the predicate has drifted.

**Verification: the existing suite plus a checksum over 100 000 lines for the *result*,
and a probe-count pin for the *cost*.** The result is preserved, so no new test asserts a
result; what covers it is that a *wrong* version reddens what is already there —
`WrapPackingTests` (`testCharWrapOneCellPerRow`, `testUnbreakableRunOverflowsOneRow`,
`testPartitionTilesTheLine`) exercises lines that must **not** collapse to a single row —
and **only** it does: `VisualRowEquivalenceTests` and `WrapComputeEquivalenceTests` are ∞
oracles whose every line fits, and on a fitting line the inverted predicate is false at `∞`
and true at `width == total`, exactly like the real one, so they stay green under (l)
(observed in the plan's smoke test). Drill (l) shows the packing suite bites,
and it **inverts** the predicate rather than deleting it: deleting a pure optimization
changes no result and would redden nothing, which is exactly the shape of a drill that
proves nothing. The second witness is the `checksum=` token 55a adds to the `wrap_compute`
line (Decision 13): it folds every drained row's `endColumn` over 100 000 lines at three
widths, so it must be byte-identical across this commit while the timing columns move — a
result-preservation check on a fixture no unit test reaches, and one drill (l)'s inversion
also reddens. This is weaker evidence than a new pin, the same weakness Decision 13 carries
for the same reason; what makes it acceptable is that the branch is three tokens over a
stored value, its correctness argument is a one-line consequence of the `columnOffset`
contract, and the existing suite contains lines that must not collapse, so a wrong version
cannot be quiet.

**The cost claim is a new standing guarantee, and it gets a positive, red-first pin.** The
moment Documentation Updates writes "a line that fits packs in O(1), and the last row of
any line does too" into `AGENTS.md`, that sentence is a claim some test must read — and no
result-bearing suite can: the plausible regression is restricting the predicate to `start
== 0 && total − startOffset <= wrapWidth` (the rejected query-side shape), which preserves
every row, every checksum and every count the 55b suite pins (its exact counts sit on
fitting lines, its growth bound on non-last rows by design), while making the last-row
sentence false. `WrapPackingCountTests` (Testing Strategy) counts `canBreak` through a
counting `WrapMetricsSource` and asserts zero on a fitting line and zero *added* by the last
row of a wrapped line — both red on the shipped packer, which is the red-first shape
`AGENTS.md`'s TDD norm asks of commit 4, and the second red again under drill (m). Without
it the only witness for the last-row case would be one `width_40` column in 55a's record.

**Reverting is cheap and local**: dropping the branch touches this decision, drill (l),
AC17, the cost wording in `AGENTS.md` and the two doc comments, `WrapPackingCountTests`,
and the `total` parameter Decision 13 hands the cursor. No type, no signature.

### Decision 13 — The per-line wrap ladder is extracted and shared; `total` is stored; the `wrap_compute` line prints its checksum

**Not a user call**; adopted during review, over an initial refusal answered below.

`visualRows` (`VisualRowCursor.swift:84-109`) runs a three-probe ladder —
`columnCount(inLine:)`, `columnOffset(inLine:column: 0)`, `columnOffset(inLine:column:
count)` — validates `wrapWidth`, and hands **neither value back**: `count` goes into the
cursor's private state (`:9`) and `total` is discarded (`:103`). Three consumers need them:
`VisualRowCursor` itself, for Decision 12's short-circuit (`total` becomes a stored property
beside `columnCount`, passed through the **`internal`** init — the only channel by which
`greedyEnd` can see it); `visualPointAt`, which needs `count` to construct that cursor and
would otherwise re-probe it one line after the ladder read it; and step 7's `>= total`
guard (Decision 14), which reads it for free. The ladder body moves into `validateWrapLine`
(Contract 55a); `visualRows` becomes a thin wrapper and keeps its signature, return type,
probe order and failures. **The blank line needs no fourth probe**: when `count == 0` the
ladder reads `columnOffset(inLine:column: 0)` and validates it is exactly `0`, which *is*
`total`; the cursor's blank-line branch (`:29-32`) returns `[0, 0)` before `greedyEnd`, so
the stored `total` is simply unread there.

**Why the obvious objection does not hold.** The extraction looks like the `startOffset`
alternatives Decision 4 rejects, and those grounds do not transfer: Decision 4 rejected
*widening a shipped public type* and *adding state to a shipped cursor* — real API and
invariant costs. This is a body move inside one file plus one stored `Double` on a struct
nobody outside the module can construct — no signature changes, no public type gains a
field, the extracted function is not public. Declining it would buy one fewer diff hunk and
cost a probe the caller already paid for — and, with Decision 12 in the packer, the only
route by which `total` reaches `greedyEnd`.

**It is behaviour-preserving, and the evidence is negative.** Same probes, same order,
same failure values, same rows. `WrapPackingTests`, `WrapValidationTests`,
`WrapComputeTests` and `VisualRowEquivalenceTests` must pass **unedited** — if a test has to
be edited to make the extraction pass, the extraction was not neutral: stop and find out
why, rather than adjusting the test — and both wrap modes' `checksum=` tokens must be
byte-identical across the extraction commit. That is weaker than every other guarantee in
this slice — there is no test that fails if the extraction is wrong in a way the existing
suite does not already cover — which is why AC18 makes "no test may be edited" part of the
criterion, and why Decision 13 adds no drill: a refactor with no new standing guarantee has
nothing to break. The residual is that a defect invisible to those suites today would be
invisible after the move too.

**The `wrap_compute` line gains a `checksum=` token, in 55a.** Today `formatWrapComputeLine`
(`WrapComputeBenchmark.swift:63-90`) prints none — the sum is only consumed by the
anti-dead-code guard at `:188` — so "byte-identical checksums on both wrap modes" would be,
for the very mode this piece edits most, a criterion that cannot fail: the D-25 shape. The
token is added in **commit 0**, before any measured-path edit — a witness absent from the
first column is a witness for nothing — in the printer only, with `WrapBenchmarkLineShapeTests`'
shape case updated in the same commit; it folds the two sums the guard already holds — every drained row's `endColumn` and every
computed range's length, both deterministic under `deterministicScrollOffset`. The harvester
keys on bare `p95_ns=`, which this line still does not print, so no corpus row appears;
`WrapBenchmarkLineShapeTests`'s shape case gains the token; D-18's `extract_checksums`
recipe is unaffected because no wrap mode runs in CI. With it in place the token is a
behavioural pin over 100 000 lines at three widths for **every** 55a edit on this path —
including Decision 12, whose result-preservation it checks on a fixture no unit test
reaches. `--wrap-compute`'s *timings* do move, through Decision 12 — a separate commit and a
separate column in the record.

**Its cost is one more edit to shipped code on `--wrap-compute`'s measured path** (via
`makeInner`), which is why Scope counts five and why it takes its own commit and column.

**Rejected alternative, kept as the fallback:** leave `visualRows` alone and let `greedyEnd`
probe `columnOffset(inLine:column: columnCount)` for itself — one probe **per row** instead
of one **per line**. On a fitting line one probe still replaces a whole column scan, so
Decision 12 survives; but every row of a *wrapped* line pays a probe it cannot use, the tax
landing exactly on the case the short-circuit cannot help. Dropping Decision 13 therefore
converts a free win into a trade rather than forcing Decision 12 out; AC18's "if dropped"
branch records which was chosen, and dropping Decision 13 while leaving Decision 12's
`total` unsourced is not admissible.

### Decision 14 — Step 7 calls the provider's `columnIndex` hook directly, not `columnAt`

**User call** (2026-08-28), re-deciding the last step of the brainstorm's Decision 4
wording ("`columnAt` on a rebased `x`"). Step 7 is in Contract 55b. It keeps every
property Decision 4 was chosen for — no new search, dispatch through the provider's
overridable `columnIndex(containingOffset:inLine:)` hook (so a provider with a native
inverse keeps it on this path), one derivation of `rowSpan` — and drops what composing
`columnAt` would have added.

**Why composition bought nothing here.** After steps 4–6, `columnAt`'s two clamp branches
are pre-empted and its `.empty` branch is unreachable (a non-empty span means `columnCount
> 0`); step 7 must *write* `.inRange` rather than carry `columnAt`'s flag, because on
Decision 6's second fixture `columnAt` answers `.clampedToRight` for a point strictly inside
the row; and its `.failure` branch is reachable only on interior GIGO. What remained of the
composition was one hook call — bought with `columnAt`'s own three-probe ladder
(`columnCount`, `columnOffset(_, 0)`, `columnOffset(_, count)`,
`HorizontalPositionQuery.swift:18-37`) re-run on a line step 3 had just validated, a
paragraph mapping branches that cannot fire, a second Decision 6 fixture whose only job was
to catch the carried flag, and a deferred ledger row proposing to extract `columnAt`'s tail
to get the three probes back. "Structural parity with the family" (`pointAt`,
`columnGeometryAt` and `pointGeometryAt` all compose their 1D query) was nominal: it held
for the in-range branch alone. Decision 13's own accounting — declining to save probes for a
file-local change is inconsistent with paying them elsewhere — points the same way, and
unlike extracting `columnAt`'s tail, this touches no gated path.

**What the direct call must do that `columnAt` did for free.** The hook's precondition is
`0 <= x < lineWidth` and it does not clamp. `rebased >= rowLeft >= 0` holds for every `x
>= 0` (IEEE addition is monotone and `columnOffset(0) == 0`), so the lower bound is
structural. The upper bound is **not**: on the last row of a line the rounding Decision 6
describes can land `rebased` exactly on `total` (fixture 2), where `columnAt`'s `x >= width`
branch used to answer `count − 1` silently. So step 7 carries an explicit `rebased >= total`
guard answering `rowSpan.endColumn − 1` — `total` is the value Decision 13's ladder already
returned, so the guard costs no probe — and the hook is called only with its precondition
established. The finiteness check on `rebased` reproduces the GIGO answer `columnAt`'s `x`
rung gave for a non-finite interior offset (Decision 5). Either branch of step 7 lands inside
the span: the guard by construction, the hook through Decision 6's clamp.

**What it changes elsewhere in this document.** The delegating probe count is `3 + 2 + 1`
plus exactly one hook call (Component Design); Decision 6's second fixture pins the `>=
total` guard instead of a carried flag, on an overriding-hook conformer that records its
calls; drill (k) targets that guard; no ledger row is appended for a `columnAt`-tail
extraction, because nothing here needs it.

## Component Design

The signature is in Contract 55b. One source for both axes: `VisualRowLayoutSource` refines
`WrapMetricsSource`, which refines `LineHorizontalMetricsSource`, so the layout supplies the
row axis, the break opportunities and the cell advances — a genuine simplification over
`pointAt`'s two-source signature, and it removes `pointAt`'s standing precondition that the
two sources describe the same document.

**Cost.** `O(log totalRows)` (row-axis search) + `O(log lineCount)`
(`logicalLine(containingVisualRow:)`, provider-overridable) + **`O(columns scanned up to the
end of the located row)`** — the packer walk, zero on a line that fits `wrapWidth` and on any
line's last row (Decision 12's table) — + `O(log cells-in-line)`
(`columnIndex(containingOffset:inLine:)`, provider-overridable, on the delegating path only)
+ a constant number of O(1) probes on the column axis: **three** in the shared ladder
(Decision 13), **two per row the cursor yields** (`columnOffset` at the row's start and end,
`VisualRowCursor.swift:35` and `:43`), and, on the delegating branch only, **one** for
`rowLeft`. The exact counts are the table in Contract 55b: a located query on a fitting line
costs `3 + 2` column probes when it clamps and `3 + 2 + 1` plus the hook when it delegates —
one hook call on a provider that overrides `columnIndex`, and under the default
`binarySearchColumnIndex` one `columnCount` probe plus O(log cells-in-line) `columnOffset`
reads. Nothing is probed for Decision 12's predicate or Decision 14's guard; both read
stored values. Core memory O(1); the per-line cursor is O(1) state on the stack; no
allocation beyond the returned value types.

The walk term is the only non-logarithmic one and is inherited unchanged from node 2's
`DocumentVisualRowCursor` init — greedy packing is sequential, so reaching interior row *k*
of a wrapped line means packing rows 0…*k*. Random access inside a logical line remains a
later provider node (Non-Goal 4); this slice neither adds nor removes that cost, and
Decision 12 says exactly which rows still pay it.

The first term is `O(log totalRows)` rather than O(1) because of **D-22**:
`UniformLineMetrics` overrides neither native inverse hook, so the reused row-axis search
binary-searches where a uniform axis could answer by division — the same term behind the
arc's "O(log totalRows), not literally width-independent" correction. This slice inherits
it and does not touch it; D-22 records the two ways out and their differing blast radius.

## Testing Strategy

**`WrapPointQueryEquivalenceTests` — criterion 3's oracle.** At `wrapWidth = ∞`, and at a
finite width no line exceeds, `visualPointAt(x:y:layout:)` is bit-identical on the located
branch to `pointAt(x:y:lineMetrics: UniformLineMetrics(lineCount: layout.lineCount,
lineHeight: layout.rowHeight), columnMetrics: layout)`: same clamps, same cell, with
`globalRow == logicalLine == the located line`, `rowInLine == 0`, `rowSpan == [0,
columnCount)`, and `rowSpan.width == columnOffset(inLine:column: columnCount)` — the width
is asserted too, because it is what steps 5–6 compare against. Scoped to the located branch
deliberately, following node 3's oracle: the two ladders' failure orderings differ by
design (Decision 5). Fixture: irregular advances and break sets plus a blank line, swept
across `x` and `y` at exact boundaries, interiors and both clamps; a narrow-width control
asserts the equivalence **fails** there, so the oracle is not vacuously true. Decision 12
leaves this oracle honest: the short-circuit lives inside `greedyEnd`, so the query still
obtains every `rowSpan` from node 1's packer and the oracle still compares the packer's own
output — the packer is simply fast on this fixture, and the round-trip fixture below covers
`greedyEnd`'s other branch.

**`WrapPointQueryTests` — behaviour.** A cell in the interior of a middle row; an exact cell
boundary resolving to the later cell (half-open spans); `x == rowSpan.width` →
`.clampedToRight`; `x < 0` → `.clampedToLeft` on `startColumn`; a blank line →
`.blankLine`; a **row that overflows** `wrapWidth` where an `x` between `wrapWidth` and
`rowSpan.width` stays `.inRange`; a clamped `y` combined with each `x` branch, so both clamp
flags are observed together; **Decision 6's two fixtures**; the swept property from
Decision 2 (the index is always inside `[startColumn, endColumn)`); and two pins that
nothing else in this suite would catch, each a standing guarantee whose *invocation* is
otherwise unguarded — the defect class this repository has found five times (D-24, D-27,
D-29, and the two drills of slice 54):

- **`row` is carried verbatim from `visualRowAt`.** Decision 3's central promise, delivered
  by step 1. Nothing else notices a re-derivation: the oracle compares against `pointAt`,
  the round-trip against the cursor, the count tests count probes — all three stay green if
  the vertical half is rebuilt inside the query. The pin is one sweep over `y` at row
  interiors, exact row boundaries and **both** clamp edges, at a fixed in-range `x`,
  asserting the query's `row` equals `visualRowAt`'s `VisualRowLocation` field for field.
  The clamp edges give it teeth: a fabricated location would most plausibly get the index
  right and the `clamp` flag wrong.
- **The duplicated-field agreement** (`rowSpan.logicalLine == row.logicalLine`,
  `rowSpan.rowInLine == row.rowInLine`), named for what it actually catches: with the
  helper called at `k = rowInLine + 1`, the last row it consumes carries that `rowInLine`
  by construction, so the assertion can only fire on a wrong `k`. Worth a test — a wrong
  `k` is the plausible edit — but it is a regression pin on one argument, not evidence that
  two independently derived numbers agree, and it is not counted twice.

**`WrapPointQueryValidationTests` — the ladder.** Each rung and each precedence pair:
`lineCount < 0`; non-finite `y` beating `.empty`; the empty document; `.empty` beating a
non-finite `x`; each layout failure; non-finite `x` — with `+∞` and `-∞` each named
separately, asserting `.nonFiniteValue` and **not** a clamp (without step 2 each would reach
a different clamp branch), and once on a **blank** line, where it beats `.blankLine` (the
two pairs Decision 5 names); a horizontal metrics failure surfacing at
the top level; and **all three** malformed-provider cases, each with its own conformer and
each asserting `.failure(.invalidVisualRowLayout)` rather than a trap: an overriding
`logicalLine(containingVisualRow:)` returning a line **outside** `0..<lineCount` — three
values, `> lineCount`, `== lineCount` and `< 0`: the boundary does not trap at the named
site (Decision 4), so a test carrying only the upper value leaves it unpinned, and a
negative value is what an edit to `logicalLine < lineCount` alone lets through; the same hook
returning an in-range line that makes `rowInLine` **negative**; and a
`firstVisualRow`/`visualRowCount` that disagrees with the packer so the walk **exhausts
early**. The first two are caught in `visualRowAt` and need nothing but
`TestVisualRowLayout` with the hook overridden — the ordinary shape; if a plan step finds
itself writing a conformer with a *total* `firstVisualRow` just to survive step 1, the guard
has been placed in the query by mistake.

**Producer-side pins, so the shipped entry points' own behaviour is not left to the
composite.** `WrapRowQueryValidationTests` (55a) pins both `visualRowAt` guards directly —
the out-of-range line at both values, the negative `rowInLine`. `WrapComputeTests` (55a)
pins the cursor's two guards where `visualRowGeometry(for:layout:)`'s coverage already
lives: the negative `rowInStartLine` and the out-of-range `startLine`, each asserting the
cursor **streams nothing** — `next()` returns `nil` on the first call — rather than
trapping, streaming the start line from row 0, or skipping to the next line. Two cases, not
one, because the two guards are reached by different inputs and removable independently.
`VisualRowWalkHelperTests` (55a, `@testable import TextEngineCore` — ten files in the target
already import it that way) pins the helper's own rule directly, because no public entry
point can reach it with `k < 0` once the producers guard: `by: -1` returns `nil` without
trapping, `by: 0` returns `nil` and consumes nothing, `by: k` past the end stops at the
first `nil`. The plan must not record any one of these reds as evidence for another; they
are three guards for one input, each with its own drill.

**`WrapPointQueryCountTests` — cost, on two counters and two fixtures.** The suite pins the
table in Contract 55b, and the four quantities cannot share one harness — getting that wrong
is how a count test measures nothing and stays green, the slice-53 lesson on this file
family.

- **Counter 1, the layout axis** (`firstVisualRow` + `visualRowCount`): `<= ceilLog2(lineCount)
  + 4`, node 3's constant, unchanged and still tight, because node 4 adds **no** layout-axis
  probe — the shared ladder, the walk, Decision 12's predicate, Decision 14's guard and step
  7 all touch column metrics only, and `visualRowAt`'s new checks read `lineCount` and a
  value in hand. `AGENTS.md:163` states this bound and `WrapRowQueryCountTests` measures 13
  and 14 against it; copy the constant, never widen it. **Do not write a
  `ceilLog2(totalRows)` term into it**: the row-axis search is structurally invisible to a
  counting layout wrapper — `visualRowAt` builds its `UniformLineMetrics` inside the core
  and `UniformLineMetrics.offset` touches no provider (`WrapRowQueryCountTests.swift:4-11`)
  — so the term counts nothing and on a 1024-line × 8-row fixture adds 13 probes of slack to
  a true bound of 14, the precise D-25 defect this slice discharges. The row-axis search is
  pinned where it *is* observable, by `LineAtQueryCountTests`.
- **Counter 2, the column axis** (`columnCount` + `columnOffset` + `canBreak`), three
  assertions. *Zero on every non-located path* — `.empty`, every vertical failure, and a
  non-finite `x` — on the model of `PointAtDispatchTests.testHorizontalNotConsultedOnEmptyDocument`
  / `...OnVerticalFailure`; this is the only observation of Decision 5 step 2's *placement*
  rather than its result, since an implementation that checked `x` only after the walk
  would pass the `+∞` result test unchanged, and the walk is the expensive half. *Exact on a
  fitting line*: `3 + 2` clamped, `3 + 2 + 1` delegating (the latter on fixture 2 below,
  whose overriding hook contributes one call and no `columnOffset` reads; under the default
  search the total would depend on the fixture's cell count) — the exact numbers, not upper
  bounds, are what pin Decision 13 as bought (the ladder runs once) and Decisions 12 and 14
  as free. *Growing with the row*: the same document queried into row *k* and row *k + m* of
  one wrapped line must cost more, asserted as a comparison with a **lower bound** — at
  least the cells in rows `k + 1 … k + m`, `endColumn(k + m) − endColumn(k)`, which the scan
  must pay (row *k* is scanned by both queries; on a uniform fixture this equals the
  start-column distance, which is why that phrasing would pass while being the wrong
  quantity). "Strictly more" is not enough: it passes on a growth of one probe and is D-25's
  shape. The line must **exceed** `wrapWidth` (a fitting line has one row and no growth) and
  neither sampled row may be the line's last (its own packing is O(1), so the test would
  measure one row less than its name says; the bound still holds, and a fixture guard is
  cheaper than rediscovering that). Counters 1 and 2 are fields of one `ProbeCounter` behind
  one wrapper, exactly as node 3 sums its two fields.
- **Fixture 2 — the dispatch counts need *overriding* conformers, and must not be the
  probe-bound fixture.** "Exactly one `logicalLine(containingVisualRow:)` call" can only be
  counted by a conformer that overrides the hook, but the probe wrapper deliberately does
  not (`WrapRowQueryCountTests.swift:48-49`) — the default binary search has to run against
  the wrapper for its probes to reach counter 1. So: a second fixture, **D-24's overriding
  conformer**, which 55a lands anyway; the same rule covers "exactly one `columnIndex`
  call, zero on a clamped `x`" with an overriding column-hook conformer. Both shapes already
  coexist in `ColumnAtQueryCountTests` (`CountingColumnMetrics` beside
  `NativeSearchCounter`).

**`WrapPointQueryRoundTripTests` — agreement with the streaming path.** Node 3 carried
`WrapRowQueryRoundTripTests` (`testEveryStreamedRowIsFoundByItsOwnY`); the analog matters
more here, because the query and `DocumentVisualRowCursor` now answer the *same* question.
For every row streamed by `visualRowGeometry(for:layout:)` over a range, a `visualPointAt`
at that row's own `y` returns the same `globalRow` and a `rowSpan` equal to the streamed
`VisualRow`. Decision 4's shared helper makes the two agree structurally; this test is what
notices if a later edit unshares them. Its fixture carries lines of **both** kinds — at
least one that fits `wrapWidth` and one that exceeds it — because `greedyEnd` has two
branches after Decision 12 and a fixture of only one kind exercises one of them; a fixture
guard asserts both are present, on the model of
`WrapRowQueryCountTests.testProbeCountIsIndependentOfRowsPerLine`'s own guard. Because both
sides run the same packer, this pins *agreement*; the short-circuit's correctness is drill
(l).

**`WrapBenchmarkLineShapeTests` — three new cases** (Benchmark Mode / CI): the emitted
`wrap_point_query` line carries no bare `p95_ns=`/`p99_ns=` key (split on spaces, compare
the text before the first `=`; `query_p95_ns` and `p95_ns` are different keys, and
substring matching is not the rule) and carries `fast_path=` with the value the scenario's
parameters imply; the scenario table's `cells_per_line`/`rows_per_line` are at or above
their floors; and `WrapPointQueryLayout` and `BenchmarkWrapLayout` built on a small shape
agree element for element on `firstVisualRow`. The first is the same defect class as D-24:
a decision whose *invocation* would otherwise be pinned by nothing.

**`WrapPackingCountTests` — Decision 12's two O(1) cases, at node 1's own entry point (55a).**
A counting `WrapMetricsSource` (`columnCountCalls`, `columnOffsetCalls`, `canBreakCalls`
behind a reference-type counter, the `ColumnAtQueryCountTests.CountingColumnMetrics` shape)
under `visualRows(inLine:wrapWidth:metrics:)`, two cases. *Fitting line* (total advance
`<= wrapWidth`, breakable at every interior column so a scan would have plenty to read):
one `next()` costs **zero** `canBreak` calls and exactly **four** `columnOffset` calls (two
in the ladder, two in `next()` at the row's start and end) — the exact numbers, because
they are also what 55b's `3 + 2` rests on. *Wrapped line* (exceeds the width, at least
three rows): drain it, sampling `canBreakCalls` after the penultimate row and after the
last; the last row adds **zero**, and a fixture guard asserts the penultimate row added
more than zero, so "adds zero" is not vacuous. Both cases are **red on the shipped
packer** — that is the red-first shape of Contract 55a's commit 4 — and the second is the
only test in either piece that reads the last-row half of Decision 12's table.

**Drills — eighteen reds, plus the two fold-ins' own.** The slice-53 review found two
discharged guarantees with no recorded red, and D-29 exists because of that gap, so the
drills are named here rather than left to the review. Each drill's piece is in the
Contracts; (d1) is observed in both.

- **(a)** the ∞ oracle — break the rebasing and it reddens.
- **(b)** the checksum's completeness — zero one folded field and
  `WrapPointQueryChecksumTests` reddens.
- **(c)** the line-shape pin — drop the `query_` prefix and it reddens.
- **(d)** the `.invalidVisualRowLayout` outcomes, once per malformed-provider case: **(d1)**
  remove `visualRowAt`'s range check → the direct pin traps at `WrapPositionQuery.swift:41`
  on `> lineCount` (run on that value, not the boundary, whose un-guarded outcome is a trap
  elsewhere or a fabricated row) and the composite pin traps too, which shows the query's
  trap-freedom is inherited, not re-derived; **(d2)** remove *both* the producer's
  `rowInLine < 0` check and the helper's `k < 0` rule → the composite negative-`rowInLine`
  case traps; **(d3)** remove the walk's exhaustion check → the early-exhaustion case
  fabricates a row or traps.
- **(e)** the row-span property — remove the Decision 6 clamp and the swept property
  reddens on fixture 1.
- **(f)** the four guards, one red each, because each sits in its own place and is removable
  alone: **(f1)** remove the cursor's `rowInStartLine < 0` check → with the helper still
  total the case does not trap, it streams the start line **from row 0**, so the AC8 case
  asserting `next() == nil` reddens; **(f2)** remove the cursor's `startLine` range check →
  the case **traps** at `firstVisualRow(ofLine:)`; **(f3)** restore the raw `for _ in 0..<k`
  range inside the helper → the direct `@testable` test traps on `by: -1`, while the query's
  negative-`rowInLine` case stays **green** because `visualRowAt` rejects that input first
  (a red there would mean the producer guard is missing); **(f4)** remove `visualRowAt`'s
  `rowInLine < 0` check → its direct pin reddens (a `.row` with a negative `rowInLine`
  instead of `.failure`) while the composite case stays green through the helper's `nil` —
  the layering that shows the producer guard is the repair and the helper's rule the
  backstop. (f1) and (f3) together show Decision 4's claim — the helper buys trap-freedom,
  the cursor's own check buys the repair — rather than one red standing for both.
- **(g)** the verbatim-`row` pin — have the query build its own `VisualRowLocation` with a
  hard-coded `.inRange` and the sweep reddens at the clamp edges.
- **(h)** the placement pin — move step 2's `!x.isFinite` check to after the step-3 walk;
  the zero-column-metric assertion reddens on the non-finite `x` case while the `+∞` result
  test stays green, which is the whole point of having both.
- **(i)** the counter-2 lower bound — memoise `canBreak`/`columnOffset` inside `greedyEnd`
  so the walk probes once per row instead of once per cell (a throwaway edit); the lower
  bound reddens where a bare "strictly more" would still pass.
- **(j)** the scenario-parameter pin — halve `long_line_deep_row`'s cells-per-line; the
  parameter pin reddens rather than the benchmark printing a smaller, plausible number.
- **(k)** the `>= total` guard — remove it; on Decision 6's fixture 2 the overriding hook
  records a call at `x == lineWidth` and the test reddens, while fixture 1 stays green.
- **(l)** the packer short-circuit — **invert** its predicate (`total − startOffset >=
  wrapWidth`); `WrapPackingTests` (the three named cases) reddens, while
  `VisualRowEquivalenceTests` and the ∞ oracles stay **green** — at `∞` the inverted
  predicate is false and the scan runs, at `width == total` both predicates are true, and an
  equivalence fixture holds only fitting lines, on which the two agree (observed in the
  plan's smoke test); the oracle is structurally blind to the predicate's shape, which is
  one more reason drill (m)'s cost pin cannot be replaced by it. Inversion and not
  deletion, on purpose: deleting a result-preserving
  optimization reddens nothing, so a deletion drill would prove only that the branch is
  optional — the D-25 shape in drill form. Decision 13 adds no drill (a refactor with no new
  standing guarantee has nothing to break); Decision 12 is not in that category, because it
  adds a *branch* rather than moving a body, and a wrong branch changes rows.
- **(m)** the last-row O(1) case — restrict the short-circuit's predicate to `start == 0 &&
  total − startOffset <= wrapWidth` (the rejected query-side shape); every result-bearing
  suite and the `wrap_compute` checksum stay **green**, and only `WrapPackingCountTests`'
  last-row case reddens. That asymmetry is the point: it shows the cost claim `AGENTS.md`
  makes for the last row is read by exactly one test, and that (l) alone would not have
  caught a regression which changes no row.

**Fold-ins.**

- **D-24 (P2).** `VisualRowDispatchTests`, on the model of `PointAtDispatchTests`: a
  test-only conformer that **overrides** `logicalLine(containingVisualRow:)` and asserts the
  override was called — covering `visualRowAt` in 55a and `visualPointAt` in 55b. Today the
  documented "provider-overridable, binary-search default" contract is pinned by nothing:
  the slice-53 review's drill C bypassed the dispatch entirely and the suite stayed green.
- **D-29 (mandatory, falsifiability audit).** The `--wrap-compute` drain body is extracted
  into a function the test target can call, and a counting layout wrapper asserts it probes
  `firstVisualRow(ofLine: lineCount)` **zero** times — the witness, since
  `compute(_:layout:)` makes that probe on every call and the drain path never can (the
  `logicalLine` binary search only probes `0..<lineCount`). Red when a `compute` call is
  placed inside the body.
- **D-25 (P3).** `WrapRowQueryCountTests.testProbeCountDoesNotGrowLinearlyWithTheDocument`
  is tightened to claim something its sibling does not, or removed as redundant, with the
  reasoning recorded.

## Benchmark Mode / CI

`--wrap-point-query`: observational, **not** gateable, **not** wired into CI — the third
wrap mode, on the same amortised shape as the gated modes (`amortisedSamples`: one clock
read per `operationsPerSample` operations, divided), so its numbers resolve the operation
rather than the host clock tick — D-23's repair, which this mode is born on. That "same
shape as the gated modes" is an assertion this slice inherits, not one it proves: **D-28**
(open) records that `amortisedSamples` and the twelve gated modes' hand-rolled loops are two
implementations of one shape with nothing pinning them together; node 6 must not read the
claim as established when it derives budgets that rest on it. The scenario table, tokens
and parameters are in Contract 55b; what follows is why they are what they are.

**`operationsPerSample` is a per-scenario field, not one constant for the mode.** 256 is
right for the five logarithmic scenarios and wrong for `long_line_deep_row`, whose whole
purpose is a per-operation cost linear in the line's cells; at 256 × thousands of cells
that scenario either runs for minutes or gets its line quietly shortened until the term it
exists to expose is invisible — and shortening it is the failure mode, because it looks
like a passing benchmark. The precedent is in the tree: `WrapComputeBenchmark` gives its
drain `drainOperationsPerSample = 16` for exactly this reason, itself following
`BulkStructuralMutationBenchmark`. The printed `query_operations_per_sample=` is what lets
node 6 read the divisor off the output.

**Scenarios.** They mirror `wrap_row_query` (`uniform_1k` and `uniform_100k` at `∞`,
`narrow_100k` at 40) — except that its single `clamped_100k` **splits in two**, because the
two axes clamp through different branches and averaging them would hand node 6 a budget for
an operation that does not exist: a clamped `y` still runs both provider searches on the
layout axis (node 3's Decision 7), a clamped `x` skips the hook entirely. On a twenty-cell
line the skipped search is a handful of probes against a packer walk that dominates the
operation, so the split is justified by **which branches are exercised and reported
separately**, not by a change of cost class. Plus one node 3 did not need:
`long_line_deep_row`, a document whose lines pack into hundreds of rows, queried at the
**last row** of its line, so the within-line walk is visible instead of averaged away —
hiding the only non-logarithmic term from the one mode that measures this query would
leave node 6 deriving a budget for a cost class it never saw. Decision 12 makes the split
between the families real rather than nominal: on the ∞ pair the packer short-circuits and
the query is genuinely logarithmic; `narrow_100k`, both `clamped_*_100k` (four rows per
line) and, at depth, `long_line_deep_row` pay the walk. A budget derived by averaging across
the two families would describe neither.

**The sampling rule for `long_line_deep_row`** — "queried at the last row" and "the depth
varies across the sample sequence" cannot both hold — is that the query targets the **last
row** of its line, at a `y` derived from `deterministicIndex` over the line index, so the
walk depth is the constant `rows_per_line − 1` on every operation. Fixing the depth is what
makes the scenario's number mean one thing; consequently the line prints `row_in_line=` for
this scenario as a constant. The other five sample the row axis uniformly, so their depth
genuinely varies and the token is **omitted** there rather than filled with an average;
node 6 loses nothing, because on the ∞ pair the depth is irrelevant and on the three
`wrapWidth: 40` scenarios the printed `rows_per_line` bounds it.

**`fast_path=` is printed, not inferred, because `rows_per_line == 1` does not imply it.**
Decision 12's predicate is `total − startOffset <= wrapWidth`; a line with **no break
opportunities** and `total > wrapWidth` packs to exactly one *overflow* row (`greedyEnd`
finds no fitting legal end and falls back to `firstLegal == columnCount`,
`VisualRowCursor.swift:73`), reports `rows_per_line == 1`, and still takes the walk. The
equivalence happens to hold for all six scenarios here (both benchmark layouts are
char-wrap, breakable at every interior column), but a reading rule true only for this
mode's own fixtures is the over-broad shape. So the token means *the located line fits the
wrap width, so the query scans no columns at all* — a per-scenario constant decidable from
the scenario's parameters (`cells_per_line * advance <= wrapWidth`) — and it deliberately
does **not** track Decision 12's other O(1) case: `long_line_deep_row` is `fast_path=false`
even though its own final `greedyEnd` returns immediately, because the token names the cost
class of the whole operation, which is what a budget is derived from. `cells_per_line=` and
`rows_per_line=` (`== total_rows / line_count`) are printed for the same reason: node 6
should not have to open this file to know what it measured.

**The mode gets its own layout type, so the long line is not fighting an O(N × cells)
setup.** `BenchmarkWrapLayout.init` deliberately re-packs *every* line to measure the real
O(N) reindex; `--wrap-row-query` reuses it, and at `100_000 × 20` the setup is invisible,
but a `long_line_deep_row` built that way would spend ~10⁹ packing steps before the first
measurement, appear to hang, and the nearest remedy to hand is a shorter line — which
silently deletes the term the scenario exists to expose. A *query* mode measures no reindex
and has no use for that property, and every line in these fixtures is identical by
construction, so `WrapPointQueryLayout` packs **one** line and fills the prefix sum by
multiplication — O(`lineCount` + `cells`) — with `firstVisualRow`, `visualRowCount` and the
column metrics otherwise identical. Two rules: `BenchmarkWrapLayout` is **not touched** (its
init *is* `--wrap-compute`'s measured reindex), and the equivalence of the two
constructions is **asserted** on a small shape in `WrapBenchmarkLineShapeTests`, because the
multiplication shortcut is valid only because the lines are identical — a property of the
fixture, not of the type. With the setup cost gone, the scenario's shape is chosen for what
it must expose; a case in the same file pins the table's parameters at or above their
floors, so a later shortening is a red test rather than a quieter benchmark. The scenario
table is therefore a **top-level value** readable under `@testable import`, and the pin
asserts parameters, never timings.

**Checksum.** `wrapPointQueryChecksum` folds **every** returned field under distinct
multipliers — `globalRow`, `logicalLine`, `rowInLine`, `startColumn`, `endColumn`,
`rowSpan.width`, the cell index, and both clamp flags — pinned by
`WrapPointQueryChecksumTests`. `width` is a `Double` and is folded through
`Double.bitPattern` as `Int(truncatingIfNeeded: width.bitPattern)` with the wrapping
operators the siblings use (`&+`, `&*`): `Int(bitPattern: UInt(...))` traps where `Int` is
32-bit, and although the benchmark target is not cross-compiled today the idiom costs
nothing. Folding one index would let a release build delete the rest and still print a
plausible number — `PointGeometryChecksumTests` exists because exactly that reversion once
passed silently. A blank-line result folds a distinct sentinel, so `.blankLine` and cell 0
cannot collide.

**Prefixed latency tokens, and what node 6's flip actually costs.** `query_p95_ns=` /
`query_p99_ns=` stay prefixed, so the harvester — which requires the exact keys
`p95_ns`/`p99_ns` — emits no corpus row. Node 6's flip is not one step: un-prefix the keys,
run the mode in a hosted step **without** `--gate` (a verdict-less line is admitted precisely
so a new mode can bootstrap — `AGENTS.md`, "What the harvester admits"), harvest, derive,
and only then add the gate step — at least two hosted runs per mode, and this slice makes it
three modes. None of that is this slice's work; it is written so node 6 is scoped for the
sequence.

**`BenchmarkMode`.** `isGateable` returns `false` for the new mode (the exhaustive switch,
not a deny-list) and `--gate` is rejected with it. **`absoluteCeiling` is `.scrollFrame`,
and that is a decision, not a default inherited by proximity.** The other reading — a hit
test is a per-interaction operation and `.discreteAction` is the class for work the user has
already accepted a pause for — is reconciled here rather than left for node 6, because D-20
records that a non-gateable mode's class is pinned by nothing and node 6 is where that
inertness ends. `.scrollFrame` wins on two grounds: every position and geometry query in the
tree classifies there, and a hit test is not off the frame path — a drag-select performs one
*per frame*, and the demanding caller sets the class. The consequence is the point: the
walk's linear term will be measured against the tighter ceiling, and if it breaches, the
answer is the random-access provider node (Non-Goal 4), never a reclassification and never
a looser ceiling. This is the D-20/D-21 residual node 6 must read.

Option parsing gets the standard coverage: mode selection, rejection when combined with
another mode flag, rejection of `--gate`; and `--help` gains the flag.

## Documentation Updates

**55a**, with the code, not deferred to 55b — a shipped claim that is wrong in the tree
between two merges is the drift this document exists to prevent:

- `AGENTS.md`, the **node 1 and node 2 paragraphs**: node 1's says packing is
  "O(cells-in-row) per `next()`" and node 2's says reaching the first buffered row costs
  "the documented O(rowInLine) within-line walk"; both must now say that a row whose
  remaining suffix fits the wrap width is answered in O(1) — so a line that fits packs in
  O(1) (`∞` included), and the last row of any line does too, unless it overflows
  (Decision 12).
- The two shipped doc comments stating the same cost: `DocumentVisualRowCursor.swift:4-5`
  ("Cost: O(rowInStartLine + buffer)") and `VisualRowCursor.swift:51-56` (`greedyEnd`'s
  "O(cells in the row)"), in the Decision 12 commit itself.
- The "**same accept/reject set**" claim in its three places — `AGENTS.md:155-156`,
  `WrapPositionQuery.swift:5-7`, `WrapViewportVirtualizer.swift:1-3` — narrowed to the
  shared ladder, with the post-ladder divergence stated in one clause (Decision 4).
- `AGENTS.md`, the `visualRowAt` paragraph, and `WrapPositionQuery.swift`'s doc comment: an
  overriding `logicalLine(containingVisualRow:)` returning a line outside `0..<lineCount`, or
  an in-range line whose `firstVisualRow` exceeds the row, is now
  `.failure(.invalidVisualRowLayout)` — shipped, publicly observable behaviour of a node-3
  entry point that this piece changes.
- `docs/superpowers/debt-ledger.md`: D-24 and D-29 → `discharged(...)` with links.

**55b:**

- `AGENTS.md`: the architecture paragraph gains `visualPointAt` beside `visualRowAt` (node
  4); the commands block gains the `--wrap-point-query` line; the benchmark-flag list and
  the `--gate`-rejection list both gain the flag; the "both wrap modes" wording for the
  amortised shape becomes three (`AGENTS.md:294`).
- `AGENTS.md`, the `Tests/ViewportBenchmarksTests` entry: it says the target holds **five
  files** and names five; it holds twelve today and this slice adds more. Pre-existing
  drift, repaired here by stopping the count — name what the inventory is *for* (the guards
  that live there) and drop the head-count, which every slice that adds a test file
  falsifies.
- `--help` output and `BenchmarkMode`: the flag, the `isGateable` arm (`false`), the
  `absoluteCeiling` arm (`.scrollFrame`).
- `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift:49-53`: the comment on
  `RiggedVisualRowLayout` says its column metrics are stubbed because "`compute(_:layout:)`
  never reads them (only the cursor does, and validation tests build no cursor)";
  `visualPointAt` is the first *query* that reaches column metrics through a rigged layout,
  so the comment is corrected.
- `docs/superpowers/debt-ledger.md`: D-25 and **D-18** → `discharged(...)`. D-18's discharge
  is **unconditional** — not "if the plan writes a checksum-extraction step": AC13 requires
  the checksum baseline diff over a hosted log, so the plan writes that step and carries the
  `grep -v` filter, and a criterion that could be satisfied by *not* writing it is the D-25
  shape.
- `docs/superpowers/arcs/wrap.md`: node 4 marked `done` and the map pass written at the
  post-slice review, not here. **Three** things that pass must carry: (1) the node was
  consumed by two slices, planned rather than discovered — 55a is a repair slice on shipped
  node-2/node-3 code that consumes no map node of its own (the shape of slices 48 and 51),
  55b marks node 4 `done`, and the 55a review is a Mode-2 run like any other that selects
  55b; (2) the **within-line random-access provider node** goes *back* on the map: node 2's
  spec assigned it to **node 7** (`2026-07-24-wrap-viewport-compute-design.md:715-719`,
  "…plus the within-line random-access provider work this node deferred") and the arc map's
  node 7 entry dropped that clause, so this is a restoration, not a new node — re-attach it
  to node 7, or split it out as a fork in the style of fork V (a provider capability, not a
  criterion node), and give it a **numeric trigger** (a stated fraction of `.scrollFrame` on
  `long_line_deep_row`'s p99) rather than only "if node 6's ceiling is breached", which
  fires after the gate is already red. This document leans on it as the only admissible
  answer to a ceiling breach, and today `grep -i "random access" docs/superpowers/` hits
  only node 2's spec in prose, so node 6 would otherwise inherit a remedy nobody scheduled
  (the D-27 failure shape, named before it happens); (3) **criterion 3's evidence cell states the oracle's scoping** — the
  brief's «wrap-путь при бесконечной ширине укладки обязан совпадать с ним» is unqualified,
  what this slice and node 3 prove is bit-identity **on the located branch** with the
  failure ordering deliberately divergent, and the cell currently reads "bit-identical" for
  node 3 with no such caveat. Flipping the criterion to `done` is right; the evidence must
  say what was proven, not more. Decision 9's two notes for the geometry companion belong on
  the same pass.

## Verification

Recorded as commands plus their actual output, **one record per piece** (paths in the
Contracts), since each is its own branch, PR and hosted proof. Items with no piece named are
repeated in **both**:

- `swift test` — full suite green, with the count. `swift build -c release`.
- `rg -n "Foundation" Sources/TextEngineCore` — **empty** (the hard constraint).
- **All twelve blocking gates** — `--gate` on the default pipeline plus the eleven other
  gated modes — each `gate=pass`, unchanged. Not `--gate` alone: this slice touches no gated
  code path, so any movement in any of the twelve is a finding, and eleven would go unread
  if only the synthetic pipeline were recorded. And the **checksum baseline diff**: every
  gated mode's checksum byte-identical to the pre-branch baseline; the count is read from
  the baseline run and deliberately not quoted here.
- `swift run -c release ViewportBenchmarks -- --wrap-row-query` — re-run in both pieces:
  in 55a because the guards add three comparisons to the code this mode measures (they
  should be invisible on a path already doing two provider searches, but "should be" is not
  a record, and its `checksum=` must be byte-identical since the branches are unreachable
  for every conformer the benchmark builds); in 55b because D-25 touches its tests.
- `swift run -c release ViewportBenchmarks -- --wrap-compute` — in 55a, **one column per
  commit that touches its path**, never one before/after spanning two edits, because a
  movement attributed to a pair is attributed to nothing: two **baseline** columns from two
  separate runs after commit 0 (so the host's run-to-run spread sits in the table and "flat" can be read
  against it — without it a `−4 %` column cannot be told from noise), then after commits 1,
  3, 4 and 5 of Contract 55a (the cursor's two guards ride in commit 1 — same repair, same
  init, columns that cannot differ). Commits 1, 3 and 5 are predicted flat on every token;
  commit 4 is predicted by Decision 12's table, per width and per token, and is the only
  place in this slice where an observational number is used as a check rather than a
  record. The timing columns are evidence about latency and shape, **not** about behavioural
  neutrality — node 3's spec established that this mode's latency output is insensitive to
  whether `compute` works at all; the behavioural evidence is the `checksum=` token 55a adds
  (Decision 13), byte-identical across every column, plus each edit's own pin (the cursor
  tests for the walk extraction, which is *not* neutral — it converts a trap into a stopped
  stream; the D-29 test for the drain body; the unedited suite for Decision 13). In 55b, one
  run against 55a's final column: it touches no shipped path, so a movement is a finding.
- `swift run -c release ViewportBenchmarks -- --wrap-point-query` (55b) — the new
  observational output, all six scenarios with the checksum per scenario.
- `swift run -c release ViewportBenchmarks -- --memory-shape` — `invariant=pass`.
- `./.github/scripts/cross-target-compile.sh --self-test` — shell logic only; it compiles
  nothing and is not portability evidence. 55b adds public core API, so its portability
  evidence is the two hosted jobs.
- The falsifiability drills, each with its observed red — nine in 55a, twelve in 55b
  (Contracts; definitions in Testing Strategy).
- Hosted proof at **step** level on both the PR-head run and the post-merge push run, not
  job conclusion (the Slice 16 dead-step lesson): the host job's twelve `gate=pass` lines
  and the `swift test` count; the iOS job's two target compiles; the WASM job's four
  `result=pass … blocking=true` lines.

**Two standing traps the plan must carry**, both recorded as debt rather than advice:
**D-18** — the literal `extract_checksums` recipe over a hosted log also matches the
non-gate `memory_shape` (5) and `memory_observation` (3) diagnostic lines, so the count is
**54** where a reader expects 46; the plan carries the `grep -v` filter and D-18 is
discharged with it. **D-17** — the plan must **not** use `${PIPESTATUS[0]}`, which
`AGENTS.md`'s own plan-assertion rule 1 recommends by name: agent command blocks run under
zsh, where it expands empty and `[ "" -eq 0 ]` evaluates **true**, inverting the assertion
into a pass. Use `${pipestatus[1]}`, a plain `$?` on an unpiped command, or `[ -z "$(…)" ]`.

## Acceptance Criteria

Criteria for node 4 as a whole; the Contracts say which piece owns which. Neither piece
merges with any criterion of its own left open — a split is two complete slices, not one
slice with its acceptance deferred.

1. `visualPointAt(x:y:layout:)` exists with the Decision 3 result shape against a single
   `VisualRowLayoutSource`, and its `row` field is pinned equal, field for field, to
   `visualRowAt(y:layout:)`'s `VisualRowLocation` across a sweep of `y` including both clamp
   edges (Testing Strategy, the verbatim-`row` pin).
2. `x` is row-relative and clamps land on the row's edges: `x < 0`, `x == rowSpan.width`,
   and an overflow row where `wrapWidth < x < rowSpan.width` stays `.inRange`.
3. The returned index is line-absolute and always inside `[startColumn, endColumn)`,
   asserted as a swept property.
4. The infinite-width oracle holds on the located branch — span **and** `rowSpan.width` —
   with a narrow-width control proving it is not vacuous; "located branch" is the scope the
   review carries into criterion 3's evidence cell. No fast-path/packer agreement test is
   written: there is one derivation of `rowSpan` and nothing to compare it against.
5. The validation ladder matches Decision 5 rung for rung, with named tests for `x = +∞`
   and `x = -∞` each failing rather than clamping, for both structural precedence pairs,
   and for all three
   malformed-provider cases — the first at three values — each yielding
   `.failure(.invalidVisualRowLayout)` rather than a trap; the two `visualRowAt` cases are
   pinned directly in `WrapRowQueryValidationTests` (55a) as well as through the composite
   (55b), on a plain array-backed conformer with the hook overridden.
6. Decision 6 is discharged in writing on both fixtures: fixture 1 demonstrates the clamp
   firing with `.inRange` intact, or the clamp is removed and the property documented as
   contract-dependent; fixture 2 demonstrates the `>= total` guard answering
   `(endColumn − 1, .inRange)` with zero hook calls, on an overriding-hook conformer.
7. `WrapPointQueryCountTests` pins the probe table in Contract 55b: the layout-axis bound
   `<= ceilLog2(lineCount) + 4` with no `ceilLog2(totalRows)` term and not widened for
   Decision 12; **zero** column-metric calls on every non-located path; exactly `3 + 2`
   (clamped) and `3 + 2 + 1` plus one hook call (delegating, on the overriding conformer) on
   a fitting line; the `rowInLine` growth as a lower bound of `endColumn(k + m) −
   endColumn(k)` on a wrapped line whose sampled rows are not its last; and exactly one
   `logicalLine` call plus at most one `columnIndex` call (zero when clamped) on overriding
   conformers.
8. The within-line walk is one shared internal helper, `inout` over the value-type cursor,
   total on both degenerate inputs, called by both `DocumentVisualRowCursor.init` and
   `visualPointAt`; the round-trip test holds the streamed row and the queried row equal on
   a fixture of both line kinds; the cursor's two guards are pinned in `WrapComputeTests`
   (streams nothing, on both inputs), the helper's rule in `VisualRowWalkHelperTests`, and
   `visualRowAt`'s two guards in `WrapRowQueryValidationTests` — five guards, five
   observed reds ((d1), (f1)–(f4)), and no guard for the hook's answer lives in
   `visualPointAt`.
9. **D-24 discharged**: an overriding conformer proves the row-axis hook is dispatched, for
   `visualRowAt` (55a) and `visualPointAt` (55b), with a recorded red when the dispatch is
   bypassed.
10. **D-29 discharged**: the counting-wrapper test asserts zero `firstVisualRow(ofLine:
    lineCount)` probes in the drain body and reddens when a `compute` call is placed inside
    it.
11. **D-25 discharged**: the redundant assertion is tightened or removed, with the reasoning
    recorded.
12. `--wrap-point-query` runs and prints the six scenarios of Contract 55b with the tokens
    listed there — `fast_path=` printed rather than inferred, `row_in_line=` only where the
    sampling rule fixes the depth, prefixed latency keys, a checksum folding every returned
    field including `rowSpan.width`; per-scenario `operationsPerSample`; its own
    O(`lineCount` + `cells`) layout type with `BenchmarkWrapLayout` unmodified; the three
    `WrapBenchmarkLineShapeTests` cases (no bare `p95_ns=`/`p99_ns=` key and the `fast_path`
    value, the parameter floors, the two layouts' prefix agreement); `--gate` and a second
    mode flag rejected; the two benchmark-target test files of Decision 10.
13. The Foundation-free scan is empty, `swift test` is green, the release build is clean,
    and every gated mode's benchmark checksum is byte-identical to the pre-branch baseline.
14. Every standing guarantee this slice adds carries a **recorded red**: the eighteen drill
    reds of Testing Strategy plus D-24's and D-29's, distributed as the Contracts say. A
    guarantee whose drill is missing is an unfinished acceptance criterion, not a review
    finding.
15. **D-18 discharged** unconditionally: the plan writes the checksum-extraction step AC13
    requires with the `grep -v` filter, and contains no `${PIPESTATUS[0]}` (D-17).
16. Hosted evidence at **step** level for both the PR-head run and the post-merge push run
    of each piece, recorded with run ids.
17. **Decision 12 is discharged one way or the other in writing.** If taken: the
    short-circuit lives in `greedyEnd`, fires exactly when `total − startOffset <=
    wrapWidth`, reads `total` from stored state so it probes neither axis, reddens the
    shipped packing suite under drill (l)'s **inversion**, has its two O(1) cases pinned by
    `WrapPackingCountTests` (zero `canBreak` on a fitting line; zero `canBreak` added by the
    last row of a wrapped line — red on the shipped packer, red again under drill (m)), and
    `--wrap-compute` is recorded
    before and after on all three widths and all three token families against Decision 12's
    table — `compute_*` flat, `reindex_ns` and `drain_*` moving as predicted, the
    `wrap_compute` `checksum=` byte-identical — with any other outcome a finding. If dropped:
    the branch, this criterion, drills (l) and (m), `WrapPackingCountTests`, the cost
    wording and the `total` parameter are reverted together and the reason recorded; not
    half-applied, not silently omitted.
18. **Decision 13 is discharged one way or the other in writing.** If taken:
    `validateWrapLine` is one internal function, `visualRows` a wrapper with unchanged
    signature, return type, probe order and failures; `VisualRowCursor` stores `total`
    through its `internal` init and no public type gains a field; `visualPointAt` builds its
    cursor from `(count, total)` and re-probes neither; the four named suites pass
    **unedited** (an edit is a stop, not an adjustment); the `wrap_compute` line prints its
    `checksum=` token, pinned in `WrapBenchmarkLineShapeTests`; both wrap modes' tokens are
    byte-identical across the extraction commit **and** across the Decision 12 commit. If
    dropped: the fallback of Decision 13 is applied (`greedyEnd` probes
    `columnOffset(inLine:column: columnCount)` itself, one probe per row), the fitting-line
    counts are restated at `3 + 3` clamped and `3 + 3 + 1` delegating, and the record says
    whether Decision 12 was kept on those terms; dropping Decision 13 while leaving Decision
    12's `total` unsourced is not admissible.

## Risks And Gaps

Residuals only; everything argued elsewhere is referenced, not restated.

- **The within-line walk is on a hot interactive path.** A hit test is per-interaction, but
  a drag-select performs one per frame, which is why the mode is `.scrollFrame` (Benchmark
  Mode / CI); node 6 will measure the walk and criterion 4's absolute ceiling will judge it.
  `long_line_deep_row` exists so that judgement arrives with evidence. If it breaches, the
  answer is the random-access provider node (Non-Goal 4) — usable only if it exists as a
  scheduled item, which is why Documentation Updates puts it on the map.
- **Decision 13's only evidence is negative, and so is Decision 12's result preservation**
  — an unedited suite, drill (l)'s inversion and a byte-identical checksum — because a
  result-preserving change has no new *result* guarantee to assert. A defect invisible to
  the existing suites today would be invisible after them too; the extraction and the
  branch cannot make coverage worse, but cannot prove it sufficient either. The checksum
  over 100 000 lines is what narrows that for Decision 12; its *cost* claim is the one
  positive pin (`WrapPackingCountTests`, drill (m)), and it reads only the two O(1) cases —
  the interior-row walk's cost is pinned by 55b's growth bound, not here.
- **The duplicated fields in `VisualPointLocation`** are a public API commitment whose
  agreement pin catches a wrong `k` and not a genuine divergence (Testing Strategy). Nothing
  prevents a future field from drifting the same way, and nothing would notice.
- **The guards buy trap-freedom, not correctness.** A hook that returns an in-range *wrong*
  line is undetectable at O(1): the walk succeeds, the span is real, and the answer is
  silently wrong. D-24's conformer is what makes such overrides a live category.
- **Splitting the slice buys legibility with a second full merge cycle**, and 55a is not
  the small half: it carries five shipped-code edits, all the `--wrap-compute` columns and
  eight reds. Each piece owes a PR, two hosted runs and a post-slice review that is a live
  `choosing-next-slice` run whose recommendation is near-certain but not automatic. If that
  overhead is judged to outweigh the legibility, the fallback is one branch with the commit
  order of Contract 55a preserved — what must **not** happen is D-24's conformer landing
  before the guards, in either arrangement. The split also ages D-27 and moves D-17's
  escalation to 55a's review (Scope); this document cannot make those calls, and if the
  review skips them the items age anyway.
- **The reader of `--wrap-compute`'s record must be told what moved and why.** Three of
  55a's four edits on that path are expected to be invisible and one is expected to move
  every width on two token families (Decision 12's table). A large drop with no attribution
  reads exactly like an instrumentation bug, and a reviewer's correct instinct is to
  distrust it; the per-commit columns, the two baselines and AC17's stated directions are
  what make the record confirm a prediction rather than discover a surprise.
- **D-29 requires touching `WrapComputeBenchmark`**, code that produces observational
  numbers. Not gated, no budget rests on it, so the blast radius is a column in the record —
  but it is a real edit to a measured path, and the `checksum=` token added in the same
  commit is what shows the drain still streams the same rows.

## Revision History

One line per pass. **Superseded statements are deliberately not restated here** — a
changelog that keeps describing a design the body has since replaced is what a plan
executor implements by mistake. Read the body for what is ratified; read this only for
provenance.

1. **2026-08-24 — ratified.** Brainstormed with the user; four decisions were taken as
   user calls (Decisions 1, 3, 9, 4).
2. **2026-08-26, first pass** (spec against the code). Established that
   `DocumentVisualRowCursor` **traps** rather than meeting a malformed provider with
   GIGO (SIGTRAP verified), so the shared walk helper owns the `k < 0` guard and the
   extraction is a repair; made the count-test bound explicit; made
   `operationsPerSample` per-scenario.
3. **2026-08-26, second pass** (spec against the working tree). Removed a
   `ceilLog2(totalRows)` term that a counting layout wrapper **cannot measure** (~13
   probes of pure slack — the D-25 defect this slice discharges); carried the range
   check across to the cursor; made `.scrollFrame` a stated decision.
4. **2026-08-26, third pass** (spec against code, brief, arc map and ledger). Found that
   the within-line random-access node this document leans on exists on no map node and in
   no ledger row, and made putting it there part of the map pass; added the pins for
   `row`-verbatim, step-2 placement, and counter-2's lower bound; narrowed Goal 6 and AC5
   to what they prove.
5. **2026-08-26, fourth pass.** Moved the `logicalLine` range check to the **producers**
   (`visualRowAt` and the cursor), where the trap actually fires; adopted **Decision 12**
   (the single-row fast path), priced in both directions for the first time.
6. **2026-08-27, fifth pass** (spec against code, brief, arc map and ledger). Adopted
   **Decision 13** (the shared wrap-line ladder, which makes Decision 12's predicate cost
   zero probes instead of two); made the two-piece split (55a/55b) the **plan of record**
   rather than a contingency, with D-24 moving to the repair piece; corrected the
   `rows_per_line == 1 ⇒ fast path` reading rule, which is false for an unbreakable line,
   and replaced it with a printed `fast_path=` token; gave the benchmark its own
   fast-constructing layout so the `long_line_deep_row` shape is not fighting an O(N×cells)
   setup; corrected Goal 5's ledger count (four, not three); narrowed three over-broad
   claims (step 7's GIGO case, the Decision 5 rejected alternative's price, and the
   `.empty`-versus-non-finite-`x` precedence, which was structural but unpinned); and
   moved the changelog here.
7. **2026-08-27, sixth pass** (spec against code, brief, arc map and ledger). One
   correction, one relocation, and three precision repairs.
   **Correction:** Decision 4 claimed "the helper owns the two degenerate bounds, so both
   call sites inherit them", and for the cursor that is false — the helper's `nil` is what
   `k == 0` returns on healthy input, so it cannot signal `k < 0` to a caller passing
   `k = rowInStartLine`. The cursor gains its own negative check (three guards, three
   drills), and the repair's outcome is stated once as `streams nothing` where Scope,
   Decision 5 and AC8 had said three different things.
   **Relocation:** **Decision 12 moved out of the query and into `greedyEnd`** as a
   suffix-fits short-circuit over a `total` Decision 13 now hands the cursor. Correct for
   every row rather than only row 0, it deletes the second derivation of `rowSpan` and the
   apparatus that policed it (the agreement test, the fixture guard, AC17's compensating
   pins), keeps the ∞ oracle exercising the packer, and extends the win to
   `DocumentVisualRowCursor`. It costs two O(1) probes on the fitting path, a fifth edit to
   shipped code, and a predicted drop in `--wrap-compute`'s `width_inf` reindex. Decision 13
   and D-29 moved to **55a** with it, so all five shipped-code edits sit in one piece.
   **Precision:** the first trap row does not fire at `logicalLine == lineCount` (conformer
   arrays are `lineCount + 1` long), so AC5 and drill (d) name their values; the Decision 5
   rejected alternative's "three probes" is priced against the atomic ladder, not against
   `columnAt`'s actual precedence, which costs one; and Decision 13's own accounting
   argument, applied to step 7's three redundant probes, produces a deferred **ledger row**
   with node 6 as its trigger rather than a sentence in this file. D-27's and D-17's
   deadlines are re-read against the split rather than allowed to lapse by arithmetic.
8. **2026-08-27, seventh pass** (spec against the code, brief, arc map and ledger; the
   split put to the user and affirmed). **Correction:** the column-axis probe accounting on
   the delegating branch — Component Design and AC7 said `3 + 2 + 1`, omitting `columnAt`'s
   own three-probe ladder (`HorizontalPositionQuery.swift:18-37`) that Decision 5 already
   priced, so the "exact count" test as written would fail on a correct implementation; AC7
   and Testing Strategy now state both branches' exact counts (`3 + 2` clamped,
   `3 + 2 + 1 + 3` delegating) and the overriding-`columnIndex` conformer the delegating
   count needs. **Recorded:** the 55a/55b split as the fifth user call, with its branches
   named. **Removed:** the pass-relative narration from the body (which pass adopted, moved
   or corrected what), keeping every rejected alternative on its merits — provenance lives
   here, and the body had been carrying a changelog against its own rule. **Precision:**
   the `row_in_line=` token's two statements reconciled (printed as a constant on
   `long_line_deep_row`, omitted elsewhere); node 6's bootstrap sequence spelled out behind
   "flips that" (un-prefix → hosted non-gate step → harvest → derive → gate, per mode); the
   non-finite-`x`-beats-`.blankLine` pairing named and given a test; the "2.7x" length
   figure replaced by a non-numeric one, since it was already stale. Verified at this pass
   and recorded for the plan: Decision 12's short-circuit is bit-identical to the scan
   because `greedyEnd` compares in the same `offset − startOffset <= wrapWidth` form and
   IEEE subtraction of a common operand is monotone; no existing test counts column-axis
   probes through the packer (`WrapRowQueryCountTests.ProbeCounter` holds only
   `firstVisualRow`/`visualRowCount`), so AC18's "unedited suite" holds; and both Decision
   6 fixtures reproduce by hand (`1e16 + 3.9` rounds to `1e16 + 4`, ulp 2).
9. **2026-08-28, eighth pass** (an external review folded in; **no new scope** — the split
   stands, and the review's own instruction that there be no further scope-bearing pass is
   adopted). **Correction:** the `--wrap-compute` prediction — "`width_inf` falls,
   `width_40`/`width_10` move little" — contradicted Decision 12's own table, since the
   **last** row of every line is O(1): on the mode's fixture (80 cells, advance 1) scan
   iterations per line go 80 → 0 at `inf`, 81 → 41 at `40`, 87 → 77 at `10`, and the drain
   streams through the same `greedyEnd`, so `reindex_ns` **and** `drain_*` move on every
   width while `compute_*` holds; Scope, AC17, Verification and Risks now carry the
   per-width, per-token prediction. **Correction:** "byte-identical checksums on both wrap
   modes" was unfalsifiable for `wrap_compute`, whose line prints no `checksum=`
   (`formatWrapComputeLine`, `WrapComputeBenchmark.swift:63-90`; the sum is only consumed by
   the `:188` guard) — 55a adds the token in the D-29 commit, and it becomes the
   result-preservation witness for Decision 12 on 100 000 lines. **Guard placement:**
   `visualRowAt` also rejects a negative `rowInLine` (one comparison on the value `:41`
   computes, no probe, bound unchanged), on Goal 6's producer principle; the helper's
   `k < 0` rule is then unreachable from any entry point and is pinned by a direct
   `@testable` test; drill (f) grows to four ((f3) re-targeted, (f4) added), seventeen reds.
   **Precision:** the two shipped doc comments stating the old packing cost
   (`DocumentVisualRowCursor.swift:4-5`, `VisualRowCursor.swift:51-56`) join Documentation
   Updates; counter 2's lower bound is stated on the cells the walk actually adds
   (`endColumn(k + m) − endColumn(k)`, rows `k + 1 … k + m`), not on start-column distance,
   which coincides only on uniform rows; the `--wrap-compute` record takes two baseline
   columns so "flat" is read against the host's noise floor. **Open for the user**
   (Status): calling `columnIndex(containingOffset:inLine:)` directly at step 7 instead of
   composing `columnAt` — it overrides the brainstorm's Decision 4 wording, so it is not
   adopted here. **Deferred, not declined:** the review's consolidation pass (one canonical
   place per argument, a one-page contract per piece for the plan executor) is the next
   pass's whole content, to run after the open question closes, because the contract's
   signatures and probe counts depend on it.
10. **2026-08-28, ninth pass** (the open question closed by the user; the consolidation
    pass). **Decision 14 adopted as the sixth user call**: step 7 calls
    `columnIndex(containingOffset:inLine:)` directly, behind an explicit `rebased >= total`
    guard and a `rebased.isFinite` check, instead of composing `columnAt` — the
    brainstorm's Decision 4 wording. It keeps hook dispatch, one derivation of `rowSpan`
    and "no new search"; it removes `columnAt`'s three redundant probes (the delegating
    count is `3 + 2 + 1` plus one hook call), the mapping of branches that cannot fire, and
    the deferred `columnAt`-tail ledger row; Decision 6's second fixture is re-purposed to
    pin the guard (zero hook calls at `x == lineWidth`) and drill (k) re-targeted to it.
    **Consolidation, no new scope**: every argument now lives in exactly one section — the
    guards in Decision 4, the ladder's precedence in Decision 5, the FP fixtures in
    Decision 6, the short-circuit with its per-row cost table and its `--wrap-compute`
    prediction in Decision 12, the ladder extraction and the `checksum=` token in Decision
    13, the direct call in Decision 14, scenarios/tokens/sampling in Benchmark Mode / CI,
    the suites and all seventeen drills in Testing Strategy — and every other section
    references by name; the Scope trap table, the Component Design cost table and the
    Scope prediction table each moved to their owning decision. Two one-page **Contract**
    sections (55a, 55b) were added at the top — commits in order, files, signatures, the
    five guards, the probe table, tests, drills per piece, expected numbers, scenario
    table, records — as the plan executor's entry point; the Acceptance Criteria and Risks
    were reduced to what they own. `long_line_deep_row`'s parameters are proposed in the
    Contract (1 000 lines × 2 000 cells at width 40, 400 rows per line, 16 operations per
    sample; floors 1 000 cells and 100 rows) — the plan may raise them, never lower. No
    ratified content was dropped; the document went from 2 360 lines to about 1 700, and
    the next pass, if any, is the plan.
11. **2026-08-28, tenth pass** (an external review of the pass-9 document against the
    code, brief, arc map and ledger; **no new scope**, no user call). **Correction:**
    `advanceVisualRows`' return was stated as "the last row consumed", a wording that admits
    a last-non-`nil` reading under which step 3's early-exhaustion guard is dead code and a
    malformed provider gets a `.point` with a foreign `rowSpan`; the Contract and Decision
    4 now define it as the *k*-th `next()` result (`nil` if any earlier call was `nil`).
    **Gap closed:** Decision 12's "the last row of any line packs in O(1)" was about to
    enter `AGENTS.md` with no test reading it — the 55b count suite pins fitting lines and
    non-last rows by design, drill (l) reddens results not cost, and the only witness was
    one `--wrap-compute` column; a `start == 0 && …` regression would have kept every suite
    green. `WrapPackingCountTests` (55a, commit 4, red-first on the shipped packer) pins
    both O(1) cases; drill (m) added; counts are nine reds in 55a, eighteen drills overall.
    **Precision:** step 2's rung is for `±∞` (`-∞ < 0` is true and would clamp left), with a
    named test per sign; guard 1's test carries a third, negative value, since `logicalLine
    < lineCount` alone is the natural wrong edit; "three places consume the hook" corrected
    to two, with the call sites named; the map-pass item for the random-access seam records
    that node 2's spec had placed it on node 7 and the arc map dropped it, and asks for a
    numeric trigger. Not adopted (a user/process call, left as is): plain `55`/`56`
    numbering instead of `55a`/`55b` — `AGENTS.md`'s `slice-N-<slug>` convention and the
    ledger's slice-counting escalation arithmetic both read numbers, and slices 48/51/52/54
    already set the precedent of a numbered slice consuming no map node; if the letters
    stay, the arc decision log should say how a lettered slice counts for escalation.
    **Found while writing the 55a plan:** the `checksum=` witness was scheduled in commit
    5, after four of the five columns it was to certify; it moves to **commit 0** (printer
    only), and the overriding-hook test conformer moves to commit 1 (the guard tests need
    it), with commit 6 reduced to the dispatch pin and the ordering rule restated as "no
    test drives an override against an unguarded consumer". **Smoke-tested from the
    plan** (a throwaway worktree, 2026-08-28): every predicted red reproduces on the
    shipped code (two trap shapes, two fabricated `.row`s, `WrapPackingCountTests` at
    7/12/3), the full suite is 425/0 after (408 + 17), the three `wrap_compute` checksums
    are identical across the short-circuit, and drills (m), D-24 (both sites) and D-29
    bite. Two corrections from it: drill (l) reddens `WrapPackingTests` only — the ∞
    oracles cannot see the predicate's shape — and the `--wrap-compute` *time* prediction
    was over-claimed: scan iterations fall by the table's factors, time by 0.45–0.55 at
    `inf`, 0.68–0.80 at `40`, about 0.93 at `10`, because a per-row fixed cost remains once
    the ~1.5 ns/cell scan is gone; Decision 12's table and Contract 55a now say so.
