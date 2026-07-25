# Wrap-Aware Viewport Compute Over Visual Rows (`compute(_:layout:)`) Design

- **Slice:** 50 — soft-wrap arc, **node 2**
- **Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md)
- **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)

## Status

Proposed. Brainstormed 2026-07-24; this document is the ratified design. Two
load-bearing forks were decided with the user during brainstorming (recorded in
Decisions 1 and the honesty boundary of Decision 4). The next step after user
sign-off is the TDD implementation plan (`writing-plans`).

**Amended 2026-07-24 during slice-50 implementation (post whole-branch review):**
Decision 7 (and the Testing Strategy Falsifiability bullet and AC6) previously
claimed the `∞` oracle's row-streaming half is reddened by the D-12 `<`-vs-`<=`
mutation. That is false — at `∞` the fit test compares a finite advance against
`+∞`, so both `<` and `<=` accept and the packing is unchanged. Corrected to credit
the dedicated **finite-width** `testInteriorExactEqualWidthBoundary` fixture as the
real boundary discriminator (coverage was always genuine; only the prose over-claimed).

## Source Context

Node 1 (Slice 49) shipped **layer (i)**: per-logical-line greedy row-packing —
one logical line + a wrap width → its `VisualRow`s, each a half-open cell span
`[startColumn, endColumn)` with an advance-sum width, streamed by an O(1)-state
`VisualRowCursor<Metrics: WrapMetricsSource>`. It is pure, stateless, and owns no
Unicode/shaping/font knowledge; at `wrapWidth ≥ line total` (`∞` included) a line
packs to exactly one whole-line row equal to the no-wrap column model (the
per-line equivalence oracle). `VisualRow` is deliberately **horizontal only** —
no `y`/`height` — because vertical stacking is this node.

This slice is **layer (ii)**: cross-line aggregation — total visual-row count,
global-visual-row-index ↔ (logical line, row-in-line), cumulative `y` per visual
row — plus the wrap-aware `compute` those enable, plus the **width-change cost
demonstration**. This is where criterion 1's width-change question lives, and it
is the arc's highest feasibility risk (the arc map has front-loaded it since arc
start).

The provider contract mirrors the two existing metrics sources: `LineMetricsSource`
(vertical, cumulative `y` per logical line) and `LineHorizontalMetricsSource`
(horizontal, cumulative `x` per cell) — each is `count` + cumulative `offset` + a
provider-native inverse hook with a binary-search default. Node 2 adds a **third**
such source over the **visual-row** axis.

## The two forks decided during brainstorming

The whole node turns on one theoretical fact, so it is stated up front:

> **Exact total document height under wrap costs O(N) on a width change.** A width
> change alters *every* logical line's visual-row count at once, so recounting all
> N lines is Ω(N) — no data structure (balanced tree included: all leaves change)
> makes it sublinear.

**Fork A/B — architecture family (decided: A).** Family A = an **exact**
provider-owned visual-row index space; the core computes exactly in
O(log N) + O(buffer) with the width baked into the provider; a width change is a
provider swap whose O(N) reindex is a **setup cost** (the same category as the
O(N) initial document load the engine already accepts — only *scroll* is
O(log N)), and the core never walks the document. Family B (anchor + estimated
extent, viewport-bounded-on-width-change today, approximate scrollbar) was
**rejected**: it forgoes exactness and a bit-identical equivalence oracle, and
diverges from the engine's exact-O(log N)/provider-owned-prefix-search DNA. Under
A, criterion 1 moves `open → partial` this slice (the per-frame scroll cost is
proven viewport-bounded — no document re-walk on a width change, only a mild
O(log totalRows) term; see Decision 5).

**What `partial → done` actually requires (and what it does *not*).** The
Ω(N)-width-change fact above is a theorem: a *full* width change reindexes every
multi-row line, so the exact reindex **cannot** be made sublinear — no later node
"incrementalizes" it. Sublinearity is available only for **incremental edits**
(one edit → O(log N) in a balanced tree), which is a *different* operation, not a
width change. Closing criterion 1 to `done` (a bounded frame on rotation/resize)
therefore requires an **estimated/async veneer over the exact index space A** —
i.e. a deliberate re-entry into the A/B fork as a *layer* (exact index underneath;
an estimated total extent and/or off-frame reindex on top), **not** an
"incremental exact reindex," which is impossible. This slice's `partial` is honest
and final for A's core half; the veneer is the open work, and it is a fork
decision, not a mechanical optimization.

**Fork — within-line random access (decided: accept the O(rowInLine) walk).**
Greedy packing is inherently sequential, so reaching the k-th visual row of one
logical line costs O(k). Node 2 virtualizes **across** logical lines (the main
risk) and documents the **within-line** cost as O(rowInLine of the first buffered
row + buffer); random access inside a single line (a provider-owned break-point
cache) is a separate, isolated later node. The only case this bounds loosely is a
single pathological logical line of millions of rows with the viewport deep inside
it — real documents have many short-to-medium lines.

## Problem

With soft-wrap on, the vertical axis is measured in **visual rows**, not logical
lines: one logical line occupies one or more rows. A wrap-aware `compute` must map
a scroll offset + viewport height to the visible **visual-row** range and stream
each row's placement (`VisualRow` span + `y` + height), staying viewport-bounded
(O(log N) queries + O(buffer) + O(1) core memory), preserving the no-wrap path
exactly, and reducing to the existing logical-line `compute` at infinite width
(the whole-document equivalence oracle). The core must own only the aggregation
**math**; the wrap-width-dependent row counts live behind the provider.

## Scope

**In:**
- the `VisualRowLayoutSource` provider contract (the visual-row axis: `lineCount`,
  `rowHeight`, `wrapWidth`, `visualRowCount(inLine:)`, `firstVisualRow(ofLine:)`,
  and the `logicalLine(containingVisualRow:)` inverse hook with a binary-search
  default);
- `ViewportVirtualizer.compute(_:layout:)` — the third `compute` overload,
  returning a `VirtualRange` of **visual-row indices**;
- the `VisualRowGeometry` value type (a `VisualRow` + `y` + `height`);
- `DocumentVisualRowCursor<Layout>` — the O(1)-state cursor streaming
  `VisualRowGeometry` over a buffer visual-row range, reusing node 1's per-line
  `VisualRowCursor`, handed back by `visualRowGeometry(for:layout:)`;
- the **whole-document** equivalence oracle (wrap at `∞` = the logical-line
  `compute`, over irregular inputs) with a recorded red;
- the D-12 interior exact-equal wrap-width boundary test (folded in — node 2
  re-drives node 1's cursor);
- an **observational** `--wrap-compute` benchmark that demonstrates the
  width-change cost (compute stays viewport-bounded — it grows only as
  O(log totalRows), a couple of binary-search steps, not linearly with width;
  provider reindex cost measured), recorded in the verification doc.

**Out (later nodes, restated as non-goals below):** the estimated/async
width-change veneer that would close criterion 1 to `done` (a later **fork**, not
an "incremental exact reindex" — Ω(N) forbids that; see the fork section) /
within-line random access (later provider node); variable
visual-row height (later); `--memory-shape` extension to the wrap path (node 5);
wrap benchmark modes promoted to **blocking gates** (node 6); y→row and
point→(row, cell) wrap queries (nodes 3–4); incremental edits under wrap
(node 7); verification hosts (nodes 8–9).

## Goals

1. A visual-row axis contract that mirrors the two existing metrics sources —
   `count` + cumulative `offset` + inverse hook — introducing the document-level
   `lineCount` the horizontal source lacked, and no more than that.
2. A wrap-aware `compute` that **reuses** the proven vertical compute's
   range/clamp/`isAtTop`/`isAtBottom`/buffer math rather than re-deriving it (its
   own front ladder owns the layout-specific validation and the documented order).
3. An O(1)-core-memory `DocumentVisualRowCursor` that composes node 1's per-line
   packer across the viewport buffer with no array materialized.
4. A **strong** whole-document equivalence oracle: at `∞` width, over irregular
   advances + irregular breaks + variable per-line column counts, wrap `compute`
   equals the logical-line `compute` bit-for-bit and the streamed rows are
   one-per-line.
5. The width baked entirely into the provider, so the core takes no `wrapWidth` and
   never re-walks the document on a width change (only a mild O(log totalRows)
   term) — the demonstration that retires the top risk's core half.
6. Zero change to the no-wrap path; all existing tests still green.

## Non-Goals

- **No incremental *exact* width-change reindex — Ω(N) forbids it.** A width
  change constructs a new provider; its O(N) reindex is a measured setup cost, and
  because every multi-row line changes, the *exact* reindex **cannot** be made
  sublinear by any later node. Closing criterion 1 to `done` needs an
  estimated/async veneer over the exact index (a later **fork**), not an
  "incremental exact reindex" (see the fork section).
- **No within-line random access.** The O(rowInLine) walk to the first buffered
  row is accepted and documented (see the fork above).
- **No variable visual-row height.** `rowHeight` is a uniform scalar this slice
  (YAGNI; uniform is the real case). Adding variable heights is **not additive** —
  it is a re-architecture of the vertical axis (Risks): the *protocol* survives,
  but Decision 2's `y = globalRow * rowHeight` reuse does not; the migration path
  is recorded so a later reader does not mistake it for a small refinement.
- **No `--memory-shape` extension, no blocking gate, no host.** Node 5 / node 6 /
  nodes 8–9. The `--wrap-compute` mode is **observational only** and is **not**
  `isGateable` this slice.
- **No new shipped public provider.** As in node 1, correctness/oracle tests run
  against a **test-only** conformer; the demonstration runs against a
  **benchmark-local** aggregation provider. A shipped wrap layout provider waits
  until a host needs one (nodes 8–9).

## Decisions

### Decision 1 — `VisualRowLayoutSource` refines `WrapMetricsSource` (Family A)

```swift
public protocol VisualRowLayoutSource: WrapMetricsSource {
    /// Number of logical lines in the document. The horizontal source
    /// (`LineHorizontalMetricsSource`) carried no line count; the visual-row axis
    /// needs it to size the document, so it enters here.
    var lineCount: Int { get }

    /// Uniform height of one visual row, in layout units. Precondition: finite,
    /// `> 0`. Node 2 assumes uniform; variable row height is not an additive method
    /// on this protocol but a re-architecture of the vertical axis (see Risks) —
    /// `rowHeight` would retire in favour of a cumulative-y-per-row source.
    var rowHeight: Double { get }

    /// The layout width these row counts are computed at. `> 0`, `+∞` allowed (the
    /// equivalence case). Baked into the provider — a width change is a *new*
    /// provider. Exposed so the core cursor packs each line at the same width
    /// (Decision 4) and so validation can reject a non-positive width.
    var wrapWidth: Double { get }

    /// Visual rows logical line `line` packs into at `wrapWidth`. Precondition:
    /// `>= 1` for every line (a blank line is one row) and equal to the number of
    /// rows node 1's packer yields for `line` at `wrapWidth` — the provider owns
    /// this aggregate; the core owns the packing math that defines it. Domain
    /// `0..<lineCount`.
    func visualRowCount(inLine line: Int) -> Int

    /// Cumulative visual rows before logical line `line` — the prefix sum of
    /// `visualRowCount` over `0..<line`. Domain `0...lineCount`;
    /// `firstVisualRow(ofLine: 0) == 0`; `firstVisualRow(ofLine: lineCount)` is the
    /// document's total visual-row count. Strictly increasing (every line `>= 1`
    /// row). This is the `offset(ofLine:)` analog — O(1), provider-owned. A width
    /// change reindexes exactly this prefix sum.
    func firstVisualRow(ofLine line: Int) -> Int

    /// Inverse of the prefix sum: the logical line whose visual-row span contains
    /// global visual row `g` — the largest `L` with `firstVisualRow(ofLine: L) <=
    /// g`. The `lineIndex(containingOffset:)` analog. Precondition: `lineCount > 0`,
    /// `0 <= g < firstVisualRow(ofLine: lineCount)`, same stable snapshot. Does not
    /// validate or clamp.
    func logicalLine(containingVisualRow g: Int) -> Int
}

extension VisualRowLayoutSource {
    // Binary-search default over `firstVisualRow` — O(log N). A balanced-tree
    // provider may override it to answer in one descent, exactly as
    // `lineIndex(containingOffset:)` was made native in Slice 29. That native hook
    // is a LATER node; node 2 ships the default only.
    public func logicalLine(containingVisualRow g: Int) -> Int { /* binary search */ }
}
```

Rationale: (1) mirrors `LineMetricsSource` limb-for-limb (`offset(ofLine:)` →
`firstVisualRow(ofLine:)`, `lineIndex(containingOffset:)` →
`logicalLine(containingVisualRow:)` with a binary-search default), so the axis is
familiar and the O(log N) provider-native optimization has an obvious later home.
(2) Refining `WrapMetricsSource` (not just `LineMetricsSource`) is required: the
cursor reconstructs each row's **span** by re-running node 1's packer, which needs
the inherited `columnOffset`/`columnCount`/`canBreak` — so one object carries both
the aggregate counts and the per-cell advances, and they cannot drift. (3) The
width is a provider property, not a `compute` argument (Decision 5).

Only `firstLineIndex(withOffsetAtOrAbove:)` has **no** analog here: node 2's
vertical compute reuses the *uniform* vertical math (Decision 2), whose boundaries
are arithmetic, so the sole inverse hook the visual-row axis needs is the
containing-index one used by the cursor.

### Decision 2 — `compute(_:layout:)` reuses the uniform vertical compute

Because `rowHeight` is uniform, the visual-row axis's y is pure arithmetic:
`y(globalRow) = globalRow * rowHeight`, and the document's total height is
`totalRows * rowHeight` where `totalRows = layout.firstVisualRow(ofLine:
layout.lineCount)`. So the visible **visual-row** range is exactly what the
existing exact vertical `compute` returns for a uniform axis of `totalRows` rows
of height `rowHeight`:

```swift
extension ViewportVirtualizer {
    public static func compute<Layout: VisualRowLayoutSource>(
        _ input: VariableViewportInput, layout: Layout
    ) -> ViewportComputation
}
```

It runs a front validation ladder (Decision 6), computes `totalRows` with **one**
prefix query (`firstVisualRow(ofLine: lineCount)`), then obtains the visible range
by **reusing the proven variable compute over a uniform axis** —
`UniformLineMetrics(lineCount: totalRows, lineHeight: rowHeight)` — so the range,
clamp, `isAtTop`/`isAtBottom`, and buffer/overscan math is the existing, tested
code, not re-derived (Goal 2). The returned `VirtualRange`'s indices are
**visual-row indices**. Complexity: **O(log N) queries** at worst (the reused
compute binary-searches the uniform axis, since `UniformLineMetrics` keeps the
default inverse hook) and **O(1) memory** — well inside the viewport-bounded target
and strictly cheaper than the cursor's unavoidable O(log N). (An arithmetic uniform
implementation would be O(1) queries; that micro-optimization is not worth forgoing
the reuse, and the cursor is O(log N) regardless.)

**Return type is the reused `ViewportComputation`/`VirtualRange`** (indices
reinterpreted as visual rows), not a wrap-specific twin. `VirtualRange` is
axis-agnostic (an index range + edge flags); a parallel type would duplicate it.
The reinterpretation is documented on the overload. (Alternative — a distinct
`VisualRowRange` — was rejected as surface duplication.)

### Decision 3 — `VisualRowGeometry` adds the vertical placement

```swift
public struct VisualRowGeometry: Equatable {
    public let row: VisualRow   // node 1's horizontal span (logicalLine, rowInLine, start/endColumn, width)
    public let y: Double        // top of this visual row = globalVisualRow * rowHeight
    public let height: Double   // rowHeight (uniform this slice)
    public init(row: VisualRow, y: Double, height: Double)
}
```

Mirrors `LineGeometry`/`ColumnGeometry` (a positioned box) but composes node 1's
`VisualRow` rather than re-declaring its fields — so `VisualRow` stays the single
horizontal-span type and gains no `y`/`height` (which would be meaningless for
node 1's per-line packer). The global visual-row index is derivable
(`firstVisualRow(ofLine: row.logicalLine) + row.rowInLine`, or `y / rowHeight`) and
is **not** stored — kept lean; add it only if a later node needs it self-described.
Placed in `ViewportTypes.swift` beside `VisualRow`.

### Decision 4 — `DocumentVisualRowCursor<Layout>`, O(1) core memory

The document cursor streams `VisualRowGeometry` over a buffer visual-row range,
holding the provider so it lazily reads metrics as it advances — generic, like
node 1's `VisualRowCursor` and `VariableLineGeometryCursor`:

```swift
public struct DocumentVisualRowCursor<Layout: VisualRowLayoutSource> { // forward, mutable, non-Equatable
    private let layout: Layout
    public mutating func next() -> VisualRowGeometry?
}

extension ViewportVirtualizer {
    public static func visualRowGeometry<Layout: VisualRowLayoutSource>(
        for range: VirtualRange, layout: Layout
    ) -> DocumentVisualRowCursor<Layout>
}
```

Construction (from `range.bufferStart`):
1. `startLine = layout.logicalLine(containingVisualRow: range.bufferStart)` —
   O(log N) (or O(1) native later).
2. `rowInStartLine = range.bufferStart - layout.firstVisualRow(ofLine: startLine)`.
3. Open node 1's `VisualRowCursor` for `startLine` at `layout.wrapWidth` and drain
   `rowInStartLine` rows (**the accepted O(rowInLine) walk**), so the first
   `next()` yields the buffer's first row.

`next()` (bounded by `remaining = bufferEndExclusive - bufferStart`):
- `remaining == 0` → `nil`.
- Pull the next `VisualRow` from the inner per-line cursor; if it is exhausted,
  advance to the next logical line and open a fresh inner cursor at row 0.
- Emit `VisualRowGeometry(row:, y: globalRow * rowHeight, height: rowHeight)`;
  bump `globalRow`, decrement `remaining`.

State is O(1): `layout`, current logical line, the inner `VisualRowCursor`, the
running `globalRow`, `remaining`, `rowHeight`. Total work O(rowInStartLine +
buffer). Reusing node 1's `VisualRowCursor` for the packing keeps the core the
single packing authority and means the D-12 interior-boundary edge is exercised
here too. Embedded-safe: it composes the same generic-cursor shape that already
compiles for iOS + WASM + embedded WASM.

### Decision 5 — Width lives in the provider; `compute`/cursor take no `wrapWidth`

Neither `compute(_:layout:)` nor `visualRowGeometry(for:layout:)` takes a wrap
width — it is `layout.wrapWidth`. A width change is modelled as constructing a new
`VisualRowLayoutSource` at the new width (its O(N) reindex is the provider's setup
cost) and calling `compute` again. This is the exact analog of `LineMetricsSource`
baking in line heights. The core's per-call work — `compute` O(log N), cursor
O(log N) + O(buffer) — takes **no `wrapWidth` parameter** and **never re-walks the
document** on a width change; its only width-sensitivity is the mild O(log totalRows)
term (a couple of binary-search steps, not a linear re-layout). That is the crux of
retiring criterion 1's core half: the O(N) lives in the provider's reindex (a setup
cost), never in a core per-frame call.

### Decision 6 — Validation ladder for `compute(_:layout:)`

Front-loaded O(1) probes, reusing shared `ViewportValidationError` cases and adding
the two the visual-row axis needs, in a fixed documented order (parity with the
existing `compute` overloads, which validate before their empty short-circuit):

1. `layout.lineCount < 0` → `.failure(.negativeLineCount)`.
2. `!scrollOffsetY.isFinite || !viewportHeight.isFinite` → `.failure(.nonFiniteValue)`.
3. `viewportHeight < 0` → `.failure(.negativeViewportHeight)`.
4. `overscanLinesBefore < 0 || overscanLinesAfter < 0` → `.failure(.negativeOverscan)`.
5. `!rowHeight.isFinite || rowHeight <= 0` → **new** `.failure(.nonPositiveRowHeight)`.
6. `!(wrapWidth > 0)` → reuse `.failure(.nonPositiveWrapWidth)` (accepts `+∞`,
   rejects `NaN`/`−∞`/`≤ 0` — the same predicate and F1 trap note as node 1).
7. `layout.firstVisualRow(ofLine: 0) != 0` → **new** `.failure(.invalidVisualRowLayout)`
   (the prefix-sum contract probe, before the empty short-circuit — parity with
   the `offset(ofLine: 0) != 0` probe in the `LineMetricsSource` overload).
8. `lineCount == 0` → `.success(emptyRange())`.
9. `totalRows = layout.firstVisualRow(ofLine: lineCount)`; `totalRows <= 0` →
   `.failure(.invalidVisualRowLayout)` (a non-empty document has `≥ lineCount ≥ 1`
   rows; `≤ 0` is a malformed prefix sum).
10. `totalHeight = Double(totalRows) * rowHeight`; `!totalHeight.isFinite` →
    `.failure(.invalidVisualRowLayout)`. A pathologically large `totalRows ×
    rowHeight` product overflows to `+∞`; catching it here keeps the error surface
    wrap-coherent — otherwise the reused `LineMetricsSource` overload would surface
    its own `.invalidLineMetrics` **through** the wrap overload (an abstraction
    leak). Marginal in practice, closed for coherence.
11. Otherwise delegate the range math (Decision 2) and return `.success`.

Interior `visualRowCount`/`firstVisualRow`/`columnOffset` values stay
trusted-monotone (the same trust the existing binary searches place in interior
`offset(ofLine:)`), re-read by the cursor without re-validation. Two new error
cases: `.nonPositiveRowHeight`, `.invalidVisualRowLayout` (added to
`ViewportValidationError`).

### Decision 7 — Whole-document equivalence oracle (criterion 3, second half)

For a layout at `wrapWidth = ∞` (and, as a second point, any width `≥` every
line's total advance), over **irregular** advances, an **irregular** break set, and
**variable** per-line column counts:

- `visualRowCount(inLine: L) == 1` for every `L`, so `firstVisualRow(ofLine: L) ==
  L` and `totalRows == lineCount`; therefore
  `compute(input, layout∞) == compute(input, UniformLineMetrics(lineCount: layout.lineCount, lineHeight: layout.rowHeight))`
  — **bit-identical** `VirtualRange` (visible, buffer, and both edge flags).
- The rows drained from `visualRowGeometry(for:layout∞)` are **one per logical
  line**: `row == [0, columnCount(inLine: L))`, `y == L * rowHeight`,
  `height == rowHeight`.

Stating it over irregular, variable-width inputs (not a uniform grid) is what makes
it a guarantee rather than a tautology. The reference for the vertical axis is the
**uniform** vertical model (justified: uniform `rowHeight` ⇒ at `∞` the stacking is
exactly `UniformLineMetrics(lineCount, rowHeight)`), the whole-document mirror of
node 1's per-line oracle (which compared wrap-at-∞ to the no-wrap **column** model).

**Falsifiability (discharges the mandatory candidate from the Slice 49 review).**
The `∞` oracle's **range** comparison is, by itself, tautology-prone in exactly
node 1's way: at `∞`, `totalRows == lineCount`, so a `compute(_:layout:)` stub that
ignored the wrap inflation would still *pass* the range equality (both sides
coincide). So the oracle is **not** made falsifiable by its `∞` range half. Its
discriminating red comes from two places the plan records:

1. **The finite-width aggregation red (the genuine recorded red).** The
   `WrapComputeTests` row-range correctness cases run at a **finite** width where
   lines actually wrap (`totalRows > lineCount`) against known-expected ranges;
   the natural TDD stub (a `compute(_:layout:)` that returns the un-inflated
   logical-line range) is **red** there before the real aggregation lands. This is
   the aggregation's honest recorded red — at the width where the coincidence
   breaks.
2. **The dedicated finite-width D-12 boundary fixture + the mutation.** A break
   whose `columnOffset(c) − startOffset == wrapWidth` exactly must land inclusively
   on the row; a `<`-vs-`<=` mutation in node 1's `greedyEnd` (the **D-12** interior
   exact-equal wrap-width edge, folded in here since node 2 re-drives that cursor)
   produces a wrong span and **reddens that finite-width fixture**
   (`testInteriorExactEqualWidthBoundary`, width 20). Note the mutation does **not**
   redden the `∞` oracle's row-streaming half: at `∞` the fit test compares a finite
   advance against `+∞`, so both `<` and `<=` accept and the one-per-line packing is
   unchanged (`testInfiniteWidthStreamsOneRowPerLine` stays green under the flip).
   The discriminating boundary red is the finite-width fixture, not the `∞` streaming
   half.

So the mandatory candidate is discharged honestly — not by pretending the `∞` range
equality can fail, but by carrying the discriminating red at a **finite** width: the
aggregation red (`totalRows > lineCount`) and the recorded D-12 boundary mutation,
both where wrapping actually happens.

### Decision 8 — Test-only conformer + benchmark-local provider; no shipped provider

Consistent with node 1's Decision 7 (YAGNI on public providers):

- **`TestVisualRowLayout`** in `Tests/TextEngineCoreTests` — wraps a
  `TestWrapMetrics` (node 1's helper: advances + break set), a `rowHeight`, a
  `wrapWidth`; precomputes each line's `visualRowCount` by running node 1's packer
  and the `firstVisualRow` prefix array at construction (O(N)); `logicalLine`
  uses the binary-search default. Reachable from `TextEngineCoreTests` (which sees
  `TextEngineCore` alone), so the equivalence oracle — comparing two **core** APIs
  (`compute(_:layout:)` vs `compute(_:metrics:)`) — lives there.
- A **benchmark-local** aggregation provider in `Sources/ViewportBenchmarks` for
  the `--wrap-compute` demonstration at scale (100k lines) — it need not ship.
- **No new public/shipped `VisualRowLayoutSource`.** A shipped provider (and its
  balanced-tree O(log N) native `logicalLine` hook) waits until a host needs one
  (nodes 8–9), mirroring how reference providers followed the core in the first
  arc.

### Decision 9 — File placement mirrors the existing sources/queries

- `Sources/TextEngineCore/VisualRowLayoutSource.swift` — the protocol + the
  binary-search default for `logicalLine(containingVisualRow:)` + the shared
  binary-search helper (beside `LineMetricsSource.swift`).
- `Sources/TextEngineCore/WrapViewportVirtualizer.swift` — the
  `compute(_:layout:)` overload + the `visualRowGeometry(for:layout:)` factory as
  `ViewportVirtualizer` extensions (mirroring `VariableViewportVirtualizer.swift`).
- `Sources/TextEngineCore/DocumentVisualRowCursor.swift` — the cursor (beside
  `VisualRowCursor.swift`).
- `Sources/TextEngineCore/ViewportTypes.swift` — add `VisualRowGeometry` and the
  `.nonPositiveRowHeight` / `.invalidVisualRowLayout` error cases.

## Component Design

### `compute(_ input: VariableViewportInput, layout:)` (new overload)

Run the Decision 6 ladder; on no breach, read `totalRows` (one prefix query) and
reuse the variable compute over `UniformLineMetrics(totalRows, rowHeight)`,
returning `.success(VirtualRange)` with visual-row indices. O(log N) queries, O(1)
memory. No packing here.

### `visualRowGeometry(for range: VirtualRange, layout:)` (new factory)

Construct and return a `DocumentVisualRowCursor` positioned at `range.bufferStart`
(Decision 4). Precondition-based (the `range` came from a compatible
`compute(_:layout:)` over the same stable layout snapshot); no re-validation, like
`geometry(for:metrics:)`.

### `DocumentVisualRowCursor<Layout>` (new)

Holds `layout`, the current logical line, an inner node-1 `VisualRowCursor` at the
current position, `globalRow`, `remaining`, `rowHeight`. `next()` per Decision 4:
pull from the inner cursor, roll to the next line when it exhausts, emit
`VisualRowGeometry`, stop when `remaining` hits 0. O(rowInStartLine + buffer) total,
O(1) state.

### Types (new)

`VisualRowGeometry` (value type, `Equatable`), `DocumentVisualRowCursor<Layout>`
(generic, non-`Equatable`), `VisualRowLayoutSource` (protocol), the two
`ViewportValidationError` cases.

### Untouched

`LineMetricsSource`, `LineHorizontalMetricsSource`, `WrapMetricsSource`, node 1's
`VisualRow`/`VisualRowCursor`/`visualRows`, the existing `compute`/`lineAt`/
`columnAt`/`pointAt`/geometry overloads, all reference providers. The no-wrap path
is unchanged; existing tests are untouched and must stay green.

## Testing Strategy

### `TestVisualRowLayout` (test helper)

`Tests/TextEngineCoreTests/TestVisualRowLayout.swift` (Decision 8): builds over a
`TestWrapMetrics` + `rowHeight` + `wrapWidth`, precomputing per-line
`visualRowCount` (via node 1's packer) and the `firstVisualRow` prefix array.

### Whole-document equivalence oracle (load-bearing) — `WrapComputeEquivalenceTests`

- At `wrapWidth ∈ { .infinity, ≥ max line total }`, over irregular advances +
  irregular breaks + variable column counts: `compute(input, layout)` **equals**
  `compute(input, UniformLineMetrics(lineCount, rowHeight))` for a spread of scroll
  offsets (top, middle, past-bottom clamp) and overscans — bit-identical
  `VirtualRange`.
- The streamed `VisualRowGeometry`s at `∞` are one-per-line with the expected
  span/`y`/height.
- **Falsifiability** (Decision 7): the `∞` *range* equality is tautology-prone
  (`totalRows == lineCount` there), and — since at `∞` both `<` and `<=` accept a
  finite advance against `+∞` — the `∞` **row-streaming** half is **not** reddened by
  the `greedyEnd` `<`-vs-`<=` mutation either. This suite's discriminating red
  therefore lives at **finite** width: the aggregation red in `WrapComputeTests`
  below (`totalRows > lineCount`) and the dedicated D-12 interior exact-equal
  boundary fixture, which the mutation does redden.

### Wrap compute + cursor invariants — `WrapComputeTests`

- **Row-range correctness (carries the aggregation's recorded red):** for a
  document whose lines wrap into known row counts (`totalRows > lineCount`),
  `compute` returns the visual-row range covering the viewport; a scroll offset
  landing inside a multi-row line resolves to the right global row; `isAtTop`/
  `isAtBottom` at the extremes. The TDD stub — a `compute(_:layout:)` returning the
  un-inflated logical-line range — is **red** here; this is the recorded red that
  discharges the Slice-49 mandatory falsifiability candidate (at a finite width the
  `∞` coincidence breaks).
- **Cursor tiling:** the drained `VisualRowGeometry`s over the buffer range are
  contiguous in `globalRow`, `y` strictly increases by `rowHeight`, each `row`
  matches node 1's packing of its logical line, and consecutive rows reconstruct
  each logical line.
- **Mid-line start:** a buffer starting at `rowInLine > 0` of a multi-row line
  yields that row first (exercises the O(rowInLine) init walk).
- **Blank lines:** a blank logical line contributes exactly one `[0,0)` row of
  height `rowHeight`.
- **Empty document** (`lineCount == 0`) → `emptyRange()`; cursor yields nothing.
- **D-12 interior boundary:** a break at exactly `wrapWidth` lands inclusively on
  the row; the `<`-vs-`<=` mutation reddens it.

### Validation — `WrapComputeValidationTests`

Each Decision 6 breach returns its case: `negativeLineCount`, `nonFiniteValue`,
`negativeViewportHeight`, `negativeOverscan`, `nonPositiveRowHeight` (`0`, `−1`,
`−∞`, `NaN` heights), `nonPositiveWrapWidth` (`0`, `−1`, `−∞`, `NaN`; `.infinity`
does **not** fail), `invalidVisualRowLayout` (`firstVisualRow(0) != 0`;
non-positive `totalRows`; **non-finite `totalRows × rowHeight`** — the overflow
guard of ladder step 10, e.g. a huge `totalRows` with a huge finite `rowHeight`).
Plus an **ordering** test pinning the ladder (a layout tripping two probes returns
the earlier one).

### Not tested here

Incremental width-change reindex, within-line random access, variable row height,
memory-shape assertion, blocking-gate budgets, y→row, point→(row,cell) — all later
nodes.

## Benchmark Mode / CI

**Observational only.** A new `BenchmarkMode.wrapCompute` (`--wrap-compute`) that:

- builds a benchmark-local aggregation provider over ~100k lines at several wrap
  widths and prints `compute(_:layout:)` + buffer-drain latency per width,
  demonstrating the core cost stays **viewport-bounded** — it grows only as
  O(log totalRows) (a narrower width has more rows, so a couple more binary-search
  steps: ~17 vs ~20 iterations at 100k lines — flat within noise, **not** literally
  width-independent; the verification doc must phrase it this way so a slightly
  slower narrow measurement is not misread as a width-dependent regression); and
- prints the provider's **reindex** cost (rebuild at a new width) separately, so
  the O(N) setup cost is a measured number, not a hand-wave — the honest
  width-change demonstration.

The O(log totalRows) term is inherent to reusing the binary-search compute over a
uniform proxy; its clean elimination is **not** wrap's job — arithmetic native
overrides of `lineIndex(containingOffset:)` / `firstLineIndex(withOffsetAtOrAbove:)`
on `UniformLineMetrics` itself would make every uniform consumer O(1). That is a
separate slice (it speeds up already-gated modes like `--line-query`, forcing a
budget re-derivation), flagged as a candidate here, not done in Slice 50.

`--wrap-compute` is **not** `isGateable` this slice and **`--wrap-compute --gate`
is rejected** (like `--range-only`/`--memory-observation`). No new blocking gate,
no budget, no corpus rows — promotion to a blocking gate is node 6, by the existing
harvest → derive recipe. `GateFloorTests`'s gateable-⇔-has-scenarios pin is
unaffected (a non-gateable mode registers no scenarios). Stated explicitly so a
reviewer confirms the omission is intentional, not a missing gate.

The width-change numbers are recorded in the verification doc as the risk-retiring
evidence for criterion 1's core half.

## Documentation Updates

- `AGENTS.md` — extend the architecture paragraph with node 2: the
  `VisualRowLayoutSource` contract (the visual-row axis; `firstVisualRow` prefix
  sum + `logicalLine(containingVisualRow:)` inverse), `compute(_:layout:)` as the
  third `compute` overload returning a visual-row `VirtualRange`,
  `visualRowGeometry(for:layout:)` streaming `VisualRowGeometry` in O(buffer),
  width-baked-in-the-provider, the whole-document equivalence oracle, and the
  documented O(rowInLine) within-line boundary. Note the `--wrap-compute`
  observational mode is not gateable (gate is node 6).
- `docs/superpowers/arcs/wrap.md` — mark node 2 progress at the post-slice review
  (map pass), not in this spec.

## Verification

Per AGENTS.md "When you change the core":

- `swift test` (new tests green; existing suite unchanged).
- `swift build -c release`.
- `swift run -c release ViewportBenchmarks -- --gate` → `gate=pass` (unchanged; no
  new *gated* mode).
- `swift run -c release ViewportBenchmarks -- --wrap-compute` → prints the
  width-sweep + reindex numbers (recorded).
- Foundation-free scan: `rg -n "Foundation" Sources/TextEngineCore` → empty.
- Cross-target compile (portability-sensitive: new public API): iOS + WASM via
  `./.github/scripts/cross-target-compile.sh` (or the hosted CI jobs).

Record actual commands, outputs, hosted run IDs, and the `--wrap-compute` numbers
in `docs/superpowers/verification/2026-07-24-wrap-viewport-compute.md`, anchoring
merged proof in the post-merge run.

## Acceptance Criteria

1. `VisualRowLayoutSource` exists, refines `WrapMetricsSource`, and declares
   `lineCount`, `rowHeight`, `wrapWidth`, `visualRowCount(inLine:)`,
   `firstVisualRow(ofLine:)`, and `logicalLine(containingVisualRow:)` with a
   binary-search default (the ratified shapes of Decision 1).
2. `VisualRowGeometry` (value type, `Equatable`, composing `VisualRow` + `y` +
   `height`), `DocumentVisualRowCursor<Layout>` (streaming, generic,
   non-`Equatable`), and the `ViewportValidationError.nonPositiveRowHeight` /
   `.invalidVisualRowLayout` cases exist with the ratified shapes.
3. `ViewportVirtualizer.compute(_:layout:)` runs the Decision 6 ladder (in the
   fixed order) and, on success, returns a `VirtualRange` of visual-row indices
   equal to the reused variable compute over `UniformLineMetrics(totalRows,
   rowHeight)`; O(log N) queries, O(1) memory.
4. `visualRowGeometry(for:layout:)` returns a `DocumentVisualRowCursor` that
   streams the buffer range's `VisualRowGeometry`s in visual order — contiguous
   `globalRow`, `y` increasing by `rowHeight`, each `row` equal to node 1's packing
   — in O(rowInStartLine + buffer), O(1) state, honouring the mid-line start and
   blank-line cases.
5. Whole-document equivalence oracle (Decision 7) passes: at `∞`/`≥ max total`
   width over irregular, variable inputs, `compute(_:layout:)` is bit-identical to
   the logical-line `compute` and the streamed rows are one-per-line. Falsifiability
   is carried per Decision 7 — the **finite-width** `WrapComputeTests` row-range
   correctness case holds the aggregation's **recorded red** (a stub returning the
   un-inflated range is red where `totalRows > lineCount`), not the `∞` range half.
6. The D-12 interior exact-equal wrap-width boundary test exists and its
   `<`-vs-`<=` mutation reddens **that finite-width fixture** (the `∞` oracle's
   row-streaming half is *not* reddened by the mutation — at `∞` both comparisons
   accept a finite advance against `+∞`); all validation, invariant, and existing
   tests pass; the full suite stays green.
7. Foundation-free scan empty; release build + `--gate` pass; `--wrap-compute`
   prints the width-sweep + reindex numbers; iOS + WASM cross-compile pass.
8. Hosted CI green at **step** level (read step logs, not the job conclusion),
   recorded with run IDs; merged proof anchored in the post-merge run.

## Risks And Gaps

- **Within-line O(rowInLine) walk (accepted, documented).** Reaching the first
  buffered row costs O(rowInLine) because greedy packing is sequential; the loose
  case is a single logical line of millions of rows with the viewport deep inside
  it. Cross-line virtualization (the main risk) is bounded; within-line random
  access is a later provider node. Recorded so node 3+/hosts don't assume O(1)
  within-line seeking.
- **O(N) width-change reindex (measured; the exact reindex is irreducibly Ω(N)).**
  The provider rebuilds its prefix sum on a width change; node 2 measures it and
  treats it as a setup cost. The *exact* reindex **cannot** be made sublinear (every
  multi-row line changes — Ω(N)); the only way to a bounded rotation/resize frame is
  an **estimated/async veneer over the exact index** — a deliberate re-entry into
  the A/B fork as a layer, decided later. Until that veneer exists, criterion 1 is
  `partial`, not `done`. (Sublinearity exists only for *incremental edits* — a
  different operation, node 7 — never for a full width change.)
- **Provider trust (interior).** As with every existing source, interior
  `firstVisualRow`/`visualRowCount`/`columnOffset` values are trusted monotone; the
  `visualRowCount == packed row count at wrapWidth` invariant is cross-checked by a
  test on `TestVisualRowLayout` but not re-validated per query in the core.
- **Uniform row height is a scalar, and variable height is a re-architecture (not
  additive).** `rowHeight` is a first-class scalar this slice and `compute(_:layout:)`
  synthesizes `UniformLineMetrics(totalRows, rowHeight)` internally — a mild
  departure from the engine's "uniform = variable at uniform metrics" DNA, where
  `uniform` is never a scalar special-case. It is a legitimate YAGNI (uniform is the
  real case), but the consequence must be recorded: at variable row height Decision
  2's `y = globalRow * rowHeight` arithmetic collapses. **Migration path:** promote
  the vertical axis to a full cumulative-y-per-visual-row source (a
  `LineMetricsSource` *over rows*); `firstVisualRow` stays the count prefix (still
  needed to map global row → logical line), a **second** prefix sum carries the
  cumulative y, `rowHeight` **retires**, and `compute` reuses the existing
  *variable* path directly with no uniform proxy. This is a vertical-axis
  re-architecture, not a new method — recorded so a later reader does not scope it as
  a small refinement. (The more ambitious "expose the y-axis as a `LineMetricsSource`
  sub-axis now" was considered and rejected for this slice: it inflates the provider
  surface with a second O(N) prefix sum for no present benefit; the scalar is the
  right minimum today.)
- **`VirtualRange` reused across axes (P3, later).** The same type now carries
  logical-line indices (the `metrics:` overload) and visual-row indices (the
  `layout:` overload). Mitigated by documenting the interpretation on each overload;
  a caller mixing a range from one overload with the other's cursor is a
  precondition violation. If this ever bites, a phantom-typed `VirtualRange<Axis>`
  gives compile-time separation — but that is a broad refactor of every existing
  overload, so P3/later, not a Slice-50 change.

## Future Slices (arc map, for reference)

Node 3 — y→row (wrap-aware `lineAt` analog). Node 4 — point→(row, cell). Node 5 —
`--memory-shape` extension to the wrap path. Node 6 — wrap benchmark modes promoted
to blocking gates. Node 7 — incremental edits under wrap (a *different* operation
from a width change: one edit → O(log N), genuinely sublinear) plus the within-line
random-access provider work this node deferred. **A distinct later fork** (not a
numbered node yet) — the estimated/async width-change veneer over the exact index
that closes criterion 1 to `done`; it is a fork decision, since Ω(N) forbids an
exact sublinear reindex. Nodes 8–9 — iOS and browser/WASM verification hosts.

Candidate (surfaced in this slice's review, not scheduled): arithmetic native
`lineIndex(containingOffset:)` / `firstLineIndex(withOffsetAtOrAbove:)` overrides on
`UniformLineMetrics` (O(1) for all uniform consumers) — its own slice, since it
touches already-gated modes and forces a budget re-derivation.
