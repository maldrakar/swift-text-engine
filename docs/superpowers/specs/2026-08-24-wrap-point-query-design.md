# Wrap-Aware Point Query (`visualPointAt(x:y:layout:)`) Design

- **Slice:** 55 — soft-wrap arc, **node 4**
- **Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md)
- **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)

## Status

Proposed. Selection affirmed by the user 2026-08-23 (arc decision log); brainstormed
2026-08-24; this document is the ratified design. Four decisions were taken with the
user during brainstorming — the `x` coordinate frame and clamp target (Decision 1),
the result shape (Decision 3), the slice's scope (Decision 9), and the internal
composition approach (Decision 4). The next step after user sign-off is the TDD
implementation plan (`writing-plans`).

## Source Context

Node 1 (Slice 49) shipped per-logical-line greedy row packing: one logical line + a
wrap width → its `VisualRow`s, each a half-open cell span `[startColumn, endColumn)`
with an advance-sum width, streamed by an O(1)-state `VisualRowCursor<Metrics:
WrapMetricsSource>` (`ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:)`).

Node 2 (Slice 50) shipped cross-line aggregation: `VisualRowLayoutSource` (the
visual-row axis), the third `compute(_:layout:)` overload over a uniform row axis, and
`DocumentVisualRowCursor`, whose init pays the **accepted within-line walk** — locate
the start line, then drive the per-line packer forward `rowInStartLine` times, because
greedy packing is sequential.

Node 3 (Slice 53) shipped `visualRowAt(y:layout:)`: the wrap-aware `lineAt` analog. It
returns a `VisualRowLocation` naming the row in **both** coordinate systems —
`globalRow` (what `compute(_:layout:)` ranges over) plus `logicalLine`/`rowInLine`
(what `VisualRow` speaks) — with the reused `LineLocation.Clamp`. Its own spec named
that dual naming as what would make node 4 "a composition rather than a
re-derivation", and this design is the discharge of that claim.

The no-wrap precedent is `pointAt(x:y:lineMetrics:columnMetrics:)` (Slice 37): a pure
composition of `lineAt` over the vertical source and `columnAt` over a separate
horizontal source, adding no search of its own, with both clamp flags carried through
verbatim.

## Problem

Criterion 3 of the wrap brief enumerates three wrap-aware query analogs: compute over
visual rows (node 2), y→row (node 3), and **point→(row, cell)**. The third is the last
one open, and it cannot be had by pointing `pointAt` at a wrap provider: `columnAt`'s
`x` is measured from the **logical line's** left edge and its clamps land on the
line's edges, while under wrap the thing on screen at a given `y` is a **visual row** —
a `[startColumn, endColumn)` slice of that line with its own left edge. A hit test in a
wrapped viewport has the row's left edge as its origin and knows nothing about the
line's.

## Scope

One new public query on `ViewportVirtualizer`, two new public types, the criterion-3
equivalence oracle for this analog, one new observational benchmark mode, and three
ledger fold-ins (D-24, D-29, D-25). No provider contract changes: every capability the
query needs already exists on `VisualRowLayoutSource` and its refinements.

## Goals

1. **`visualPointAt(x:y:layout:)`** maps a point to `(visual row, cell)` over a single
   `VisualRowLayoutSource`, with `x` measured from the located row's left edge.
2. **No new search.** Every search the query performs is one an existing entry point
   already performs, dispatched through the same provider-overridable hooks.
3. **The infinite-width equivalence oracle** holds on the located branch: at
   `wrapWidth = ∞` (or any width no line exceeds) the result is bit-identical to
   `pointAt` over a uniform line axis and the same horizontal metrics.
4. **Honest cost.** The within-line walk inherited from node 2 is stated, tested, and
   measured — not hidden behind the logarithmic terms.
5. **Three ledger items discharged** (D-24, D-29, D-25), one of them the falsifiability
   audit's mandatory option.

## Non-Goals

1. **A geometry-bearing companion** (the wrap analog of `pointGeometryAt`). Criterion 3
   does not enumerate it, `visualRowAt` has no companion either, and the 37→39
   precedent gives geometry its own slice. Decision 9.
2. **Caret snapping and affinity.** At a soft break the position "after the row's last
   cell" and "before the next row's first cell" are the same document position; which
   one a caret shows is a caller concern, exactly as `columnGeometryAt` already states.
   The result carries what the caller needs to decide (the row span and the clamp
   flag); it does not decide.
3. **The inverse** `(row, cell) → (x, y)`.
4. **`--memory-shape` extension** to the wrap path (node 5) and **gate promotion** of
   any wrap mode (node 6).
5. **A shipped wrap reference provider.** Wrap conformers stay test-local and
   benchmark-local, as in nodes 1–3.
6. **D-13** (per-axis binary-search triplication). Decision 11.

## Decisions

### Decision 1 — `x` is measured from the located row; clamps land on the row's edges

**User call.** `x = 0` is the left edge of the row located by `y`. An `x` below the
row's left edge clamps to the row's first cell (`.clampedToLeft`); an `x` at or beyond
the row's right edge clamps to the row's last cell (`.clampedToRight`).

Rejected alternatives, with reasons kept:

- **Line-relative `x`** (the mechanical reuse of `columnAt`): the caller would have to
  add `columnOffset(inLine:column: startColumn)` itself — the row's left offset is
  precisely what it does not know, and getting it costs the within-line walk this query
  exists to perform. Unusable for hit testing.
- **Row-relative `x` with clamps only at the line's edges** ("continuous line"): an `x`
  past a middle row's right edge would return a cell belonging to a *later* row with
  `.inRange`, so the returned row and the returned cell would contradict each other
  while `y` picked the row. The result would not be a point in the document's visual
  layout.

At a width no line exceeds, every line packs to one row starting at column 0, whose
offset is 0 by contract — so row-relative and line-relative coincide and Goal 3's
oracle is unaffected by this decision.

### Decision 2 — The returned column index is line-absolute

`ColumnLocation.columnIndex` is an index into the **logical line**, not into the row.
`x` is row-relative and the index is line-absolute, and that asymmetry is deliberate:
the index is a document coordinate (the same quantity `columnAt` returns, the one that
addresses text), while `x` is a screen quantity. `rowSpan.startColumn` is the bridge in
both directions.

The asymmetry is recorded as its own decision rather than a doc-comment aside because
it is the kind of thing a later veneer silently gets wrong; the swept property test in
Testing Strategy pins `columnIndex ∈ [startColumn, endColumn)` so a row-relative
regression cannot pass.

### Decision 3 — Result shape: `VisualRowLocation` + `VisualRow` + `ColumnResolution`

**User call.**

```swift
public enum VisualPointQuery: Equatable {
    case point(VisualPointLocation)
    case empty                            // empty document (lineCount == 0)
    case failure(ViewportValidationError)
}

public struct VisualPointLocation: Equatable {
    public let row: VisualRowLocation     // verbatim from visualRowAt
    public let rowSpan: VisualRow         // the located row's [startColumn, endColumn) + width
    public let column: ColumnResolution   // .cell(ColumnLocation) | .blankLine
}
```

`row` is carried **verbatim** from `visualRowAt`, mirroring how `PointLocation` carries
`LineLocation` verbatim from `lineAt`. `rowSpan` is returned because the core computes
it anyway (Decision 4 needs it to rebase `x`) and re-deriving it costs the caller a
second within-line walk; without it, `.clampedToRight` cannot be told from a soft break
at the row's end, which is exactly what a caret needs to know.

The cost is that `logicalLine` and `rowInLine` appear in both fields. They agree by
construction; a test pins the agreement rather than leaving it to prose. Both rejected
shapes (a flattened struct with no duplication, and the minimal `PointLocation` mirror
that discards the span) are recorded in the brainstorm; the flattened one loses the
"verbatim from `visualRowAt`" property, the minimal one moves an unavoidable cost onto
every caller.

`ColumnResolution` is **reused**, not re-declared: `.blankLine` means the located line
has no cells, exactly as in `PointLocation`.

### Decision 4 — Composition over three existing entry points; no new search

**User call.** The implementation is:

1. `visualRowAt(y:layout:)` — the whole vertical ladder, the row-axis search, the
   `logicalLine(containingVisualRow:)` search, one `firstVisualRow` probe. `.failure`
   and `.empty` propagate unchanged.
2. `visualRows(inLine: row.logicalLine, wrapWidth: layout.wrapWidth, metrics: layout)`,
   then `next()` exactly `rowInLine + 1` times → the located `VisualRow`. This is node
   2's accepted within-line walk, not a new cost.
3. `rowLeft = layout.columnOffset(inLine: row.logicalLine, column: rowSpan.startColumn)`,
   then the clamp/delegate ladder of Decision 5.

Rejected alternatives, with reasons kept:

- **Reuse `DocumentVisualRowCursor` over a synthetic one-row range.** Less new code and
  y/height would come free, but its init re-runs `logicalLine(containingVisualRow:)` —
  the search `visualRowAt` just performed — so the query would perform two where the
  family's rule is "no new search", and it would violate the cursor's documented
  precondition that the range came from `compute(_:layout:)`.
- **A row-scoped binary search** over `[startColumn, endColumn)`. O(log cells-in-row)
  instead of O(log cells-in-line) — the same class, a constant apart — bought with a
  **fourth** copy of the binary-search body (feeding D-13) and, decisively, with
  bypassing `columnIndex(containingOffset:inLine:)`, so a provider with a native
  inverse would lose it on this path only.

### Decision 5 — The clamp/delegate ladder, and why `x`'s finiteness is checked explicitly

After the vertical ladder succeeds and before any horizontal work:

1. `if !x.isFinite → .failure(.nonFiniteValue)`.
2. `visualRows(...)` ladder + walk (Decision 4 step 2). Its `.failure` propagates.
3. `rowSpan.startColumn == rowSpan.endColumn` → `.point(... column: .blankLine)`.
4. `x < 0` → `.cell(ColumnLocation(columnIndex: rowSpan.startColumn, clamp: .clampedToLeft))`.
5. `x >= rowSpan.width` → `.cell(ColumnLocation(columnIndex: rowSpan.endColumn - 1, clamp: .clampedToRight))`.
6. otherwise `columnAt(x: rowLeft + x, inLine: row.logicalLine, metrics: layout)` →
   its index with `clamp: .inRange` (Decision 6 covers the rebasing edge).

The rule in one sentence: **vertical failures beat a non-finite `x`; a non-finite `x`
beats every horizontal failure and every clamp.**

**Why step 1 exists rather than delegating.** `NaN` would reach `columnAt` on its own
(both comparisons against `NaN` are false, so it falls through to step 6) and return
`.nonFiniteValue`. But `+∞ >= rowSpan.width` is **true**, so an infinite `x` would
silently clamp to the row's last cell instead of failing — breaking the family rule
"a non-finite coordinate is a failure, not a clamp" that `pointAt`'s doc comment
states. The explicit check exists for `+∞`, not for `NaN`, and a named test says so.

**Rejected alternative:** mirroring `columnAt`'s precedence exactly (probe
`columnCount` first so `.negativeColumnCount` beats a non-finite `x`). It costs an
extra O(1) probe to reproduce an ordering no oracle checks — node 3's oracle is
already scoped to the located branch precisely because the wrap and no-wrap ladders
differ by design — and that no consumer can act on, since both outcomes are failures.

**Clamped queries take a special case here, and that is a divergence from node 3**
(whose Decision 7 records that clamped `y` needs none). It costs no validation
coverage: steps 4–5 skip `columnAt`'s ladder, but `visualRows`' ladder in step 2 has
already checked the same three things on the same line — `columnCount < 0`,
`columnOffset(_, 0) == 0`, and a finite positive total advance. The two ladders
overlap by construction; the overlap is accepted rather than deduplicated, because
deduplicating it means not calling `columnAt`, i.e. re-implementing its semantics.

`visualRows`' own `.nonPositiveWrapWidth` branch is **unreachable** from here: the
vertical ladder validated `wrapWidth` before this point. It is mapped through rather
than force-unwrapped, following `visualRowAt`'s treatment of its unreachable branches.

### Decision 6 — The rebased `x` is clamped into the row's span

Step 6 adds `rowLeft` to a row-relative `x`. Under the `columnOffset` contract
(finite, **strictly** increasing within a line) the located index lies inside
`[startColumn, endColumn)` for every `x ∈ [0, rowSpan.width)` — in exact arithmetic.
In `Double` arithmetic it need not: `rowSpan.width` is itself the rounded difference
`columnOffset(endColumn) − rowLeft`, so at magnitudes near 2^53 an `x` strictly below
that difference can rebase to a value that rounds to `columnOffset(endColumn)` or
above, and `columnAt` would then answer with a cell belonging to the **next** row.

The located index is therefore clamped into `[startColumn, endColumn − 1]` before the
result is built. One comparison pair, and it makes Decision 2's swept property
structural rather than contract-dependent.

**The plan must demonstrate the branch fires.** A defensive branch nothing can reach
is the un-failable-guard defect this repo keeps finding, so the plan carries a step
that constructs a strictly-increasing finite offset vector at large magnitude (the
brainstorm's sketch: offsets on the order of `[0, 1, 1e16, 1e16 + 4]` with the row
ending at the `1e16` boundary) and asserts the unclamped composition would leave the
span while the shipped query does not. **If no such fixture can be built**, the clamp
is removed and the property is documented as resting on the contract instead — the
decision is not kept with an unreachable branch and an untestable claim.

### Decision 7 — The blank row is detected from the span

`rowSpan.startColumn == rowSpan.endColumn` ⟺ the line is blank: node 1's `greedyEnd`
returns an end strictly greater than the start for every non-blank line, and a blank
line packs to exactly one `[0, 0)` row. Using the span costs no probe; a second
`columnCount(inLine:)` call would.

### Decision 8 — Naming: `visualPointAt`, not an overload of `pointAt`

The visual-row family already names itself `Visual*` (`VisualRow`, `VisualRowQuery`,
`VisualRowLocation`, `VisualRowCursor`, `VisualRowGeometry`, `VisualRowLayoutSource`),
and node 3 chose a distinct name (`visualRowAt`) over overloading `lineAt` for the same
reason: the answer is in a different index space. Here there is a second, sharper
reason — `x` means something different (measured from the row, not the line), so an
overload sharing the name `pointAt` would put two different coordinate conventions
behind one identifier. `compute(_:layout:)`'s precedent (an overload) does not apply:
its argument means exactly what the other overloads' arguments mean.

### Decision 9 — Index-only; the geometry companion is a later node

**User call.** Criterion 3 enumerates `point→(row, cell)`, not its geometry-bearing
companion; `visualRowAt` shipped without one; and slices 37→39 set the precedent that
the composite and its geometry companion are separate slices. Note that this query
already returns part of what a companion would add — the row's cell span — because
Decision 4 computes it; what a companion would add on top is the row's `y`/`height`,
the cell's box, and the two within-box fractions.

### Decision 10 — File placement mirrors the existing sources

`Sources/TextEngineCore/WrapPointQuery.swift` for the query (beside
`WrapPositionQuery.swift`), the two new types appended to `ViewportTypes.swift` beside
`PointQuery`/`PointLocation`, tests in `Tests/TextEngineCoreTests/WrapPointQuery*.swift`,
the benchmark in `Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift`.

### Decision 11 — D-13 is not folded in

D-13 (three copies of the per-axis binary-search body) rides on merit, not proximity.
This slice **adds no fourth copy** — Decision 4 rejected the row-scoped search partly
for that reason — so it produces no new evidence for or against consolidation and no
natural home. It stays open, routed to whichever slice adds a fourth axis or a
provider-native hook that makes the shared shape load-bearing.

## Component Design

```swift
extension ViewportVirtualizer {
    public static func visualPointAt<Layout: VisualRowLayoutSource>(
        x: Double, y: Double, layout: Layout
    ) -> VisualPointQuery
}
```

One source for both axes: `VisualRowLayoutSource` refines `WrapMetricsSource`, which
refines `LineHorizontalMetricsSource`, so the layout supplies the row axis, the break
opportunities, and the cell advances. This is a genuine simplification over `pointAt`'s
two-source signature, and it removes `pointAt`'s standing precondition that the two
sources describe the same document.

**Cost.** `O(log totalRows)` (row-axis search) + `O(log lineCount)`
(`logicalLine(containingVisualRow:)`, provider-overridable) + **`O(cells up to the end
of the located row within its line)`** (the packer walk) + `O(log cells-in-line)`
(`columnIndex(containingOffset:inLine:)`, provider-overridable, and only on the
non-clamped path) + a constant number of O(1) probes. Core memory O(1); the per-line
cursor is O(1) state held on the stack; no allocation beyond the returned value types.

The third term is the only non-logarithmic one. It is inherited unchanged from node 2's
`DocumentVisualRowCursor` init — greedy packing is sequential, so reaching row *k* of a
line means packing rows 0…*k*. Random access inside a logical line remains a separate,
later provider node; this slice neither adds nor removes that cost.

## Testing Strategy

**`WrapPointQueryEquivalenceTests` — criterion 3's oracle.** At `wrapWidth = ∞`, and at
a finite width no line exceeds, `visualPointAt(x:y:layout:)` is bit-identical on the
located branch to `pointAt(x:y:lineMetrics: UniformLineMetrics(lineCount:
layout.lineCount, lineHeight: layout.rowHeight), columnMetrics: layout)`: same clamps,
same cell, with `globalRow == logicalLine == the located line`, `rowInLine == 0`, and
`rowSpan == [0, columnCount)`. Scoped to the located branch deliberately, following
node 3's oracle — the two ladders differ by design. Fixture: irregular advances and
break sets plus a blank line, swept across `x` and `y` at exact boundaries, interiors,
and both clamps. A narrow-width control asserts the equivalence **fails** there, so the
oracle is not vacuously true.

**`WrapPointQueryTests` — behavior.** A cell in the interior of a middle row; an exact
cell boundary resolving to the later cell (half-open spans); `x == rowSpan.width` →
`.clampedToRight`; `x < 0` → `.clampedToLeft` on `startColumn`; a blank line →
`.blankLine`; a **row that overflows** `wrapWidth` (an unbreakable run) where an `x`
between `wrapWidth` and `rowSpan.width` must stay `.inRange`, because the pre-clamp
compares against the **row's** width and not the wrap width; the duplicated-field
agreement (`rowSpan.logicalLine == row.logicalLine`, `rowSpan.rowInLine ==
row.rowInLine`); a clamped `y` combined with each `x` branch, so both clamp flags are
observed together; and the swept property from Decision 2 — the returned index is
always inside `[startColumn, endColumn)`.

**`WrapPointQueryValidationTests` — the ladder.** Each rung and each precedence pair:
`lineCount < 0`; non-finite `y` beating `.empty`; the empty document; each layout
failure; non-finite `x` — with `+∞` named separately, asserting `.nonFiniteValue` and
**not** a clamp, since that case is the only reason Decision 5 step 1 exists; a
horizontal metrics failure surfacing at the top level; and a provider whose
`firstVisualRow`/`visualRowCount` disagrees with the packer yielding
`.failure(.invalidVisualRowLayout)` (Decision 5's divergence from
`DocumentVisualRowCursor`'s GIGO — a query has a failure channel, a stream does not).

**`WrapPointQueryCountTests` — cost.** Exactly one `logicalLine(containingVisualRow:)`
call; at most one `columnIndex(containingOffset:inLine:)` call, and zero on a clamped
`x`; probe count independent of `lineCount` with the located row held fixed; and probe
count that **does** grow with `rowInLine`, asserted as such rather than bounded by a
number that hides it. Per D-25's lesson, no second weaker bound is written beside a
strong one.

**Fold-ins.**

- **D-24 (P2).** `VisualRowDispatchTests`, on the model of the existing
  `PointAtDispatchTests`: a test-only conformer that **overrides**
  `logicalLine(containingVisualRow:)` and asserts the override was called — covering
  both `visualRowAt` and `visualPointAt`. Today the documented "provider-overridable,
  binary-search default" contract is pinned by nothing: the slice-53 review's drill C
  bypassed the dispatch entirely and the suite stayed green.
- **D-29 (mandatory, falsifiability audit).** The `--wrap-compute` drain body is
  extracted into a function the test target can call, and a counting layout wrapper
  asserts it probes `firstVisualRow(ofLine: lineCount)` **zero** times. That probe is
  the witness: `compute(_:layout:)` makes it on every call and the drain path never
  can, because `logicalLine`'s binary search only probes `0..<lineCount`.
- **D-25 (P3).** `WrapRowQueryCountTests.testProbeCountDoesNotGrowLinearlyWithTheDocument`
  is tightened to claim something its sibling does not, or removed as redundant.

## Benchmark Mode / CI

`--wrap-point-query`: observational, **not** gateable, **not** wired into CI — the
third wrap mode, on the same amortised shape as every gated mode (`amortisedSamples`,
`operationsPerSample = 256` under one clock read, divided), so its numbers resolve the
operation rather than the host clock tick (D-23's repair, which this mode is born on
rather than re-violating).

Latency tokens stay **prefixed** (`query_p95_ns=` / `query_p99_ns=`), so the harvester —
which requires the exact keys `p95_ns`/`p99_ns` — emits no corpus row for this line.
Node 6 flips that in the same slice that adds the gate step.

Scenarios mirror `wrap_row_query` (`uniform_1k` and `uniform_100k` at `∞`,
`narrow_100k`, `clamped_100k`) plus one this query needs and node 3's did not:
**`long_line_deep_row`** — a document whose lines are long enough to pack into many
rows, queried into the last row of a line, so the within-line walk is visible instead
of being averaged away by short lines. Hiding the only non-logarithmic term from the
one mode that measures this query would leave node 6 deriving a budget for a cost
class it never saw.

Checksum: `wrapPointQueryChecksum` folds **every** returned field under distinct
multipliers — `globalRow`, `logicalLine`, `rowInLine`, `startColumn`, `endColumn`, the
cell index, and both clamp flags — pinned by `WrapPointQueryChecksumTests`. Folding one
index would let a release build delete the rest and still print a plausible number;
`PointGeometryChecksumTests` exists because exactly that reversion once passed
silently. A blank-line result folds a distinct sentinel, so `.blankLine` and cell 0
cannot collide.

`BenchmarkMode.isGateable` returns `false` for the new mode (the exhaustive switch, not
a deny-list), `--gate` is rejected with it, and `absoluteCeiling` classifies it
`.scrollFrame` like every other position query — inert today because the mode is not
gateable, which is exactly the D-20/D-21 residual node 6 must read.

Option parsing gets the standard coverage: mode selection, rejection when combined with
another mode flag, and rejection of `--gate`.

## Documentation Updates

- `AGENTS.md`: the architecture paragraph gains `visualPointAt` beside `visualRowAt`
  (node 4); the commands block gains the `--wrap-point-query` line; the benchmark-flag
  list and the `--gate`-rejection list both gain the flag; the "both wrap modes"
  wording for the amortised shape becomes three.
- `docs/superpowers/arcs/wrap.md`: node 4 marked `done` and the map pass written at the
  post-slice review, not here.
- `docs/superpowers/debt-ledger.md`: D-24, D-29, D-25 flipped to `discharged(...)` with
  links; any new debt appended by the review.

## Verification

Recorded in `docs/superpowers/verification/2026-08-24-wrap-point-query.md` with actual
commands and outputs:

```bash
swift test
swift build -c release
rg -n "Foundation" Sources/TextEngineCore          # must be empty
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --wrap-point-query
swift run -c release ViewportBenchmarks -- --wrap-row-query
swift run -c release ViewportBenchmarks -- --wrap-compute
./.github/scripts/cross-target-compile.sh --self-test
```

Plus the checksum baseline diff — every gated mode's benchmark checksum must be
byte-identical against the pre-branch baseline, since this slice touches no gated path
(the count is read from the baseline run, not quoted here: a number transcribed into a
spec is falsified by the next slice that adds a scenario) — and hosted step-level evidence on
both halves — the PR-head run and the post-merge push run — read at **step** level, not
job conclusion.

## Acceptance Criteria

1. `visualPointAt(x:y:layout:)` exists with the Decision 3 result shape and compiles
   against a single `VisualRowLayoutSource`.
2. `x` is row-relative and clamps land on the row's edges: tests cover `x < 0`,
   `x == rowSpan.width`, and an overflow row where `wrapWidth < x < rowSpan.width`
   stays `.inRange`.
3. The returned index is line-absolute and always inside `[startColumn, endColumn)`,
   asserted as a swept property.
4. The infinite-width oracle holds on the located branch, with a narrow-width control
   proving it is not vacuous.
5. The validation ladder matches Decision 5, including a named test that `x = +∞`
   fails rather than clamps, and one that a packer/provider disagreement yields
   `.failure(.invalidVisualRowLayout)`.
6. Decision 6 is discharged one way or the other **in writing**: either a fixture
   demonstrates the rebasing clamp firing, or the clamp is removed and the property is
   documented as contract-dependent.
7. Query-count tests pin one `logicalLine` call, at most one `columnIndex` call (zero
   when clamped), independence from `lineCount`, and the honest `rowInLine` growth.
8. **D-24 discharged**: an overriding conformer proves the row-axis hook is dispatched,
   for both `visualRowAt` and `visualPointAt`, and the test reddens when the dispatch
   is bypassed (recorded drill).
9. **D-29 discharged**: the counting-wrapper test asserts zero
   `firstVisualRow(ofLine: lineCount)` probes in the drain body, and reddens when a
   `compute` call is placed inside it (recorded drill).
10. **D-25 discharged**: the redundant assertion is tightened or removed, with the
    reasoning recorded.
11. `--wrap-point-query` runs, prints the five scenarios on the amortised shape with
    prefixed latency tokens and an all-fields checksum; `--gate` with it is rejected;
    combining it with another mode flag is rejected.
12. The Foundation-free scan is empty, `swift test` is green, the release build is
    clean, and every gated mode's benchmark checksum is byte-identical to the
    pre-branch baseline.
13. Hosted evidence at **step** level for both the PR-head run and the post-merge push
    run, recorded with run ids in the verification document.

## Risks And Gaps

- **The within-line walk is now on a hot interactive path.** A hit test is a
  per-interaction operation, not a per-frame one, so a long line's walk is acceptable
  today; but node 6 will measure it and criterion 4's absolute ceiling will judge it.
  `long_line_deep_row` exists so that judgement arrives with evidence rather than as a
  surprise. If it proves too slow, the answer is the random-access provider node, not a
  looser ceiling.
- **Decision 6 may not be demonstrable.** The fallback is written into the decision and
  AC6; the risk is that it costs plan time to find out.
- **D-29 requires touching `WrapComputeBenchmark`.** Extracting the drain body changes
  code that produces observational numbers. The mode is not gated and no budget rests
  on it, so the blast radius is a before/after comparison in the verification record —
  but it is a real edit to a measured path and the plan must record the numbers on both
  sides.
- **The duplicated fields in `VisualPointLocation`** are a public API commitment. A test
  pins their agreement; nothing prevents a future field from drifting the same way.
