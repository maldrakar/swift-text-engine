# Horizontal Position-Query (`columnAt(x:inLine:)`) Design

Slice 33 — opens the horizontal axis after the vertical arc completed and went
fully CI-protected in Slice 32.

## Status

Proposed. Brainstormed 2026-07-04; recommended by the Slice 32 post-slice review
(Option C — the horizontal/point/wrap capability leap) and scoped by the user, in
sequence, to: Option C → *horizontal within-line primitive only* → *new standalone
metrics protocol* → *cell model* → *full Slice-27 mirror* (core + reference
provider + local benchmark).

## Source Context

The brief (`docs/initial-project-brief.md`) wants a headless
layout/virtualization core that supports realistic editing/scrolling of 100k+
line / >10 MB documents, stays Foundation-free and Embedded-compatible, keeps
core-owned memory sub-linear in document size, and keeps the document behind a
provider/source abstraction.

The engine to date is **vertical-axis only**. The vertical arc is now complete on
every dimension the project pursued:

- **line → y** via `LineMetricsSource.offset(ofLine:)` (cumulative top offset);
- **y → line** via `ViewportVirtualizer.lineAt(y:metrics:)` (Slice 27, cell model,
  clamp flag), with provider-native O(log N) descent on the balanced tree
  (Slices 29/30);
- **y → line + box + fraction** via `lineGeometryAt(y:metrics:)` (Slice 31);
- both position queries under blocking hosted regression gates (`--line-query`
  Slice 28, `--line-geometry-query` Slice 32).

The Slice 32 review handed off with **no CI/governance debt remaining** — all
seven latency gates run blocking in hosted CI — and named the horizontal/point/wrap
axis (Option C) as the biggest unclaimed distance to the brief's headline goal.
This slice opens that axis with its foundational primitive, the direct structural
mirror of Slice 27's `lineAt`.

## Problem

Every real consumer of a layout engine needs the horizontal inverse of line
layout, exactly as it needs the vertical one:

- **Hit-testing / tap-to-position** — a pointer lands at `(x, y)`; the vertical
  half (`lineAt`) already resolves the line, but nothing resolves **which cell
  within that line** `x` falls on.
- **Caret/selection placement** — the horizontal half of locating a caret from a
  point.
- **Column math** — "which cell owns this x within this line".

The engine is headless: it does no shaping or rasterization, so per-cell advances
(glyph widths) are **not** the core's to compute — they come from outside, exactly
as line heights do. The core's job is the same inverse-search it already owns on
the vertical axis: given cumulative x-offsets for a line's cells and a target `x`,
return the containing cell, with the same validation discipline, the same
half-open boundary convention, the same clamp semantics, and the same
O(log M) / O(1)-memory envelope as `lineAt`. Today a consumer would have to
re-implement that binary search itself, risking divergent boundary/clamp
conventions from the vertical axis.

## Scope

Add a single public, stateless query to `TextEngineCore`:

> Given a target `x`, a line index `inLine`, and a `LineHorizontalMetricsSource`,
> return the cell whose horizontal span contains `x` within that line, clamped
> into the line with an explicit flag telling the caller whether the query landed
> inside the line or past an edge.

Plus a new standalone metrics protocol, the result types, its closed-form oracle
and unit tests, a `UniformColumnMetrics` provider **in the core** (the oracle
target, beside `UniformLineMetrics`) and a `PrefixSumColumnMetrics`
variable/proportional provider in `TextEngineReferenceProviders`, a `--column-query`
benchmark mode with a **local** `--gate`, and the slice paper trail. No rendering,
no shaping, no `pointAt(x:y:)` composite yet, no wrap, no geometry-bearing
horizontal result.

## Goals

- Public `ViewportVirtualizer.columnAt(x:inLine:metrics:) -> ColumnQuery` over a
  new `LineHorizontalMetricsSource`, structurally symmetric with `lineAt(y:metrics:)`.
- **Cell model**: return the containing cell in `0..<columnCount(inLine:)` (which
  cell is under `x`); a blank line (0 columns) → `.empty`. Faithful mirror of
  `lineAt`'s line-cell shape; sub-cell (caret left/right) position is deferred to a
  future geometry-bearing companion, exactly as `lineGeometryAt` followed `lineAt`.
- **O(log M)** queries (M = cells in the line), **O(1)** core memory, zero
  allocation — the horizontal analog of `lineAt`'s envelope, reusing a binary
  search over `columnOffset` behind a provider-overridable hook.
- Validation parity with `lineAt`: up-front, return-based (no `throws`),
  Foundation-free, reusing the shared `ViewportValidationError` (extended by two
  axis-specific cases).
- A **closed-form equivalence oracle**: for `UniformColumnMetrics`, in-range
  `columnAt(x)` equals the structurally-derived expected cell (index + clamp) over
  a product-built sweep of exactly-representable widths — the horizontal analog of
  the vertical uniform oracle, **not** a numerically-fragile raw
  `floor(x / columnWidth)`.
- A `UniformColumnMetrics` provider **in `TextEngineCore`** (uniform advances; no
  per-line storage), beside `UniformLineMetrics` in the core exactly as its vertical
  mirror sits there, so the core equivalence-oracle test can drive it without a
  reference-provider dependency (Decision 8).
- A `PrefixSumColumnMetrics` variable/proportional provider in
  `TextEngineReferenceProviders` (per-line prefix sums, provider-side storage),
  mirroring `PrefixSumLineMetrics` — the realistic non-uniform-advance case, giving
  the unit tests and the benchmark a real variable provider rather than only
  hand-built doubles.
- A `--column-query` benchmark mode + local `--gate` with macOS-calibrated budgets,
  following the established functional-slice rhythm.
- Foundation-free, Embedded-compatible, zero-dependency; iOS/WASM cross-target
  compile unchanged.

## Non-Goals

- **No `pointAt(x:y:)` composite.** This slice ships only the horizontal
  primitive; composing it with `lineAt` into a 2D hit-test is the recommended
  next slice (Future Slices).
- **No geometry-bearing horizontal result.** The result is `columnIndex` + clamp
  only — no cell `x`/width, no `fractionInColumn`. A geometry-bearing
  `columnGeometryAt` companion (the `lineGeometryAt` analog) is a future slice.
- **No shaping / rasterization / glyph metrics.** Per-cell advances are supplied
  by the provider, exactly as line heights are. The core does inverse search only.
- **No wrap / visual rows.** The unit stays the single (unwrapped) line's cells.
- **No logical↔visual reordering (bidi) and no glyph clustering.** Cells are the
  provider's already-resolved **visual-order** advance slots (see Decision 6);
  mapping a bidi run's logical characters to visual cells, and merging zero-advance
  glyphs (combining marks, ZWJ, ligature components) into their base cell, are the
  provider's job, not the core's. `columnIndex` is therefore a **visual** cell index.
- **No provider-native horizontal descent.** Both shipped providers
  (`UniformColumnMetrics`, `PrefixSumColumnMetrics`) use the generic binary-search
  default (like `Uniform`/`PrefixSum` `LineMetricsSource`); an O(1) monospace
  override and a balanced-tree / mutable horizontal provider with a native O(log M)
  descent are deferred (the Slice 29 analog).
- **No `inLine` validation.** `inLine` is a documented precondition (a valid line
  for the source), not validated — the same posture the vertical primitives take
  toward their query domain. See Decision 5.
- **No CI promotion.** The `--column-query --gate` runs locally only this slice;
  promoting it to a blocking hosted gate is a separate follow-up slice, exactly as
  every prior functional → promotion pair (line-query → Slice 28,
  line-geometry-query → Slice 32).
- **No change to the vertical axis.** `LineMetricsSource`, `lineAt`,
  `lineGeometryAt`, `compute`, and their providers are untouched.

## Decisions

### Decision 1 — New standalone protocol `LineHorizontalMetricsSource`

The horizontal metric is a **separate concern** from vertical layout, so it is a
new protocol, not an extension of `LineMetricsSource`. A caller needing only
vertical virtualization implements nothing new; the existing providers
(`Uniform`/`PrefixSum`/`Fenwick`/`BalancedTree` `LineMetricsSource`) do not grow
horizontal methods.

```swift
public protocol LineHorizontalMetricsSource {
    /// Number of cells in `line`. A blank line has 0. (mirror of `lineCount`)
    func columnCount(inLine line: Int) -> Int

    /// Cumulative left offset (x) of cell `column` within `line`, in layout units.
    ///
    /// Domain: `0...columnCount(inLine: line)`.
    /// `columnOffset(inLine: l, column: 0) == 0`, and
    /// `columnOffset(inLine: l, column: columnCount(inLine: l))` is that line's
    /// total advance width.
    ///
    /// Contract precondition (mirror of `offset(ofLine:)`): for every `c` in
    /// `0..<columnCount(inLine: line)`, `columnOffset(_, column: c)` and
    /// `columnOffset(_, column: c + 1)` are finite and strictly increasing. Unlike
    /// line heights (always positive), raw glyph advances can be **zero** (combining
    /// marks, ZWJ, ligature components), so "strictly increasing" is a real
    /// modelling constraint here, not a free one: a *cell* is a positive-advance,
    /// caret-positionable unit in **visual (left-to-right) order**, and the provider
    /// must fold zero-advance glyphs into their base cell to honour it. See
    /// Decision 6 for the cell definition. The core never queries outside
    /// `0...columnCount(inLine: line)`.
    ///
    /// Stability precondition: `columnCount(inLine:)` and `columnOffset(inLine:column:)`
    /// for a given line must be stable for one `columnAt` query, so the located
    /// cell comes from one consistent snapshot.
    func columnOffset(inLine line: Int, column: Int) -> Double

    /// Provider-native inverse-search hook (mirror of `lineIndex(containingOffset:)`).
    /// Returns the cell whose half-open span
    /// `[columnOffset(_, c), columnOffset(_, c+1))` contains `x`.
    ///
    /// Preconditions: `columnCount(inLine: line) > 0`,
    /// `columnOffset(_, column: 0) == 0`, `x` finite in `[0, lineWidth)`, same
    /// stable snapshot. Does not validate or clamp; public query semantics stay
    /// centralized in `ViewportVirtualizer.columnAt(x:inLine:metrics:)`.
    func columnIndex(containingOffset x: Double, inLine line: Int) -> Int
}

extension LineHorizontalMetricsSource {
    public func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
        binarySearchColumnIndex(
            containingOffset: x, metrics: self,
            inLine: line, columnCount: columnCount(inLine: line)
        )
    }
}
```

There is **no** `firstColumnIndex(withOffsetAtOrAbove:…)` mirror of
`LineMetricsSource.firstLineIndex(...)`. That vertical hook exists only for
`compute`'s visible-**end** viewport-range edge; `columnAt` is a point query, so it
needs only the containing-offset hook. Keeping the protocol to three members is the
minimal faithful mirror.

### Decision 2 — Result shape: `ColumnQuery` / `ColumnLocation` / `Clamp`

Mirrors `LineQuery` / `LineLocation` / `LineLocation.Clamp` case-for-case:

```swift
public enum ColumnQuery: Equatable {
    case column(ColumnLocation)           // a real cell was located
    case empty                            // blank line: columnCount(inLine:) == 0
    case failure(ViewportValidationError) // invalid input / metrics
}

public struct ColumnLocation: Equatable {
    public let columnIndex: Int
    public let clamp: Clamp

    public init(columnIndex: Int, clamp: Clamp) {
        self.columnIndex = columnIndex
        self.clamp = clamp
    }

    public enum Clamp: Equatable {
        case inRange          // x was inside [0, lineWidth)
        case clampedToLeft    // x < 0;         resolved to cell 0
        case clampedToRight   // x >= lineWidth; resolved to last cell
    }
}
```

Rationale (all inherited from the vertical Decision 1):

- A **distinct `.empty`** for a blank line: a 0-cell line is structurally valid,
  not a validation error, and has no cell to return. This is the exact horizontal
  analog of `lineAt`'s empty-document `.empty` — and, unlike the vertical axis
  where empty documents are rare, blank lines are common, so `.empty` is a
  first-class, frequently-taken path here.
- The **clamp flag** is what hit-testing wants: out-of-range `x` resolves to the
  nearest cell (tap never fails at a line edge), while the flag lets a caller
  distinguish an exact-edge hit from a clamp.
- `Clamp` is **nested** in `ColumnLocation` to namespace a generic name; use sites
  read `.inRange` / `.clampedToLeft` / `.clampedToRight` via inference.

### Decision 3 — Error vocabulary reuses (and minimally extends) `ViewportValidationError`

`columnAt` reuses the shared `ViewportValidationError` — as `lineAt`/`lineGeometryAt`
do — adding **two** axis-specific cases and reusing one axis-neutral case:

- add `case negativeColumnCount` (columnCount(inLine:) < 0),
- add `case invalidColumnMetrics` (columnOffset(_, 0) ≠ 0, or a non-finite / ≤ 0
  line width),
- reuse the existing `case nonFiniteValue` for a non-finite `x` (already
  axis-neutral; `lineAt` uses it for non-finite `y`).

**Migration note (parity with variable-height Decision 4).** Adding an enum case is
a source break for any consumer doing an exhaustive `switch` over
`ViewportValidationError` without a `default`. This package contains no such switch
(the in-repo switches are updated here, and errors are otherwise only compared by
value), so the addition is safe in-repo; the break is called out only for a future
or external defaultless exhaustive switch, which must add the new cases or a
`default`. Extending the shared enum — rather than minting a parallel error type —
is a deliberate choice to keep the failure vocabulary single-sourced, matching how
the vertical position queries reuse it.

### Decision 4 — Half-open boundary + clamp semantics (mirror of vertical Decision 4)

Cells occupy **half-open** horizontal spans `[columnOffset(c), columnOffset(c+1))`.
An `x` exactly on a boundary `columnOffset(c)` resolves to cell `c` (the cell
*starting* there) — the same convention `lineAt` uses vertically, introducing no
new rule. Full input → result table, evaluated in `lineAt`'s deliberate order
(Decision 5), with `count = metrics.columnCount(inLine: line)` and
`width = metrics.columnOffset(inLine: line, column: count)`:

| Input condition | Result |
| --- | --- |
| `count < 0` | `.failure(.negativeColumnCount)` |
| `x` not finite (`NaN`/`±inf`) | `.failure(.nonFiniteValue)` |
| `metrics.columnOffset(inLine: line, column: 0) != 0.0` | `.failure(.invalidColumnMetrics)` |
| `count == 0` | `.empty` |
| `width` non-finite or `<= 0` | `.failure(.invalidColumnMetrics)` |
| `x < 0` | `.column(ColumnLocation(0, .clampedToLeft))` |
| `x >= width` | `.column(ColumnLocation(count - 1, .clampedToRight))` |
| otherwise (`0 <= x < width`) | `.column(ColumnLocation(search(x), .inRange))` |

Notes:

- `x == 0` on a non-blank line is **`.inRange`** at cell 0 (`0` is inside
  `[0, width)`). Only strictly negative `x` is `clampedToLeft`.
- `x == width` is `clampedToRight` (the right edge is the exclusive end of the last
  cell's half-open span), resolving to `count - 1`.
- The explicit `width` non-finite / `<= 0` check is defensive parity with `lineAt`'s
  total-height check against a contract-violating provider.
- On a **blank line** (`count == 0`) the `columnOffset(_, column: 0)` probe still
  runs first and must return `0.0` per contract; only then does the `count == 0`
  branch short-circuit to `.empty`. A blank line whose column-0 offset is non-zero
  is `.invalidColumnMetrics`, not `.empty` — the probe precedes the empty
  short-circuit exactly as on the vertical axis.

### Decision 5 — `inLine` is a precondition, not validated; validation order is parity with `lineAt`

`columnAt` validates the **column-domain** contract for the selected line exactly
as `lineAt` validates the **line-domain** contract for the document: `count < 0` →
`x` finiteness → `columnOffset(_, 0) == 0` (checked **before** the `count == 0`
empty short-circuit) → empty short-circuit → line-width sanity.

`inLine` itself is **not** validated. Under the "document → line, line → cell"
mirror, `inLine` is the selector picking *which line* (sub-document) the inverse
search runs in; it has no vertical analog (there is one document, but many lines),
and its validity is a documented precondition — the same posture the vertical
primitives take toward their query domain (`offset(ofLine:)` is documented as never
queried outside `0...lineCount`, not defended at runtime). The standalone
`LineHorizontalMetricsSource` deliberately carries **no `lineCount`**, so it neither
can nor should re-authorize the line index; the eventual `pointAt(x:y:)` always
feeds `columnAt` a line already validated by `lineAt`.

### Decision 6 — Cell model: caret-stop unit in visual order; sub-cell position deferred (mirror of vertical Decision 7)

**What a cell is.** A *cell* is one positive-advance, caret-positionable unit —
grapheme-cluster / caret-stop granularity — occupying the half-open span
`[columnOffset(c), columnOffset(c+1))`, laid out in **visual (left-to-right)
order**. This definition is load-bearing for the whole primitive:

- It justifies the strictly-increasing `columnOffset` contract (Decision 1):
  positive advance *between caret stops* holds by construction, so the provider must
  fold zero-advance glyphs (combining marks, ZWJ, ligature components) into their
  base cell.
- Visual order is what makes the binary search valid: `columnOffset` is monotone in
  the cell index only if cells run left-to-right, so for a bidi run the provider
  supplies cells already in visual order and `columnIndex` is a **visual** index
  (logical↔visual mapping is out of core scope — see Non-Goals).

**Terminology.** "Column" and "cell" are used synonymously in this slice; the API
keeps the `column*` names to pair with the vertical `line*` axis, while "cell" is
the precise concept — a variable-advance visual slot, **not** necessarily a
monospace grid column. `columnCount` / `columnOffset` / `columnIndex` / `columnAt`
all mean cells in this sense.

**Sub-cell position deferred.** The result is `columnIndex` + `clamp` only — no cell
`x`/width, no `fractionInColumn`, no caret left/right snapping. A caller wanting
sub-cell position gets it from a future geometry-bearing companion
(`columnGeometryAt`, the `lineGeometryAt` analog) — added as a **new method / result
type**, never by appending a case to `ColumnQuery` (source-breaking for client
switches over a non-frozen enum). Keeping the primitive minimal avoids widening the
public type and an extra `columnOffset` query on the hot path for callers that only
need the cell.

### Decision 7 — Local gate now, CI promotion deferred (established rhythm)

This functional slice ships the `--column-query` benchmark mode **and** local
`--gate` enforcement with macOS-calibrated budgets, but does **not** wire the gate
into `.github/workflows/swift-ci.yml`. Promotion to a blocking hosted gate is a
separate follow-up slice, identical to the project's six prior functional →
promotion pairs (variable-height → 15, variable-height-mutation → 21,
structural-mutation → 24, bulk-structural-mutation → 26, line-query → 28,
line-geometry-query → 32).

`--gate` becomes valid with `--column-query` automatically: the parser's rejection
is a **denylist** (`--gate` rejected only with `.rangeOnly` / `.memoryShape` /
`.memoryObservation` — `BenchmarkOptions.swift:137`), so a new gateable
`.columnQuery` mode needs no edit there. `AGENTS.md` gains the new local command and
the `--column-query` flag; its CI section is unchanged because the workflow is
unchanged.

### Decision 8 — Provider placement: uniform in the core, variable in reference providers

`UniformColumnMetrics` lives in **`TextEngineCore`**, beside `UniformLineMetrics`
(`LineMetricsSource.swift`), **not** in `TextEngineReferenceProviders`. This is the
faithful mirror: `UniformLineMetrics` is itself a core type, placed there precisely
because it is the equivalence-oracle target and the core test target imports only
`TextEngineCore` — variable-height Decision 4 says as much ("both a convenience and
the equivalence oracle"). The `ColumnAt*` oracle lives in `TextEngineCoreTests`,
which depends only on `TextEngineCore` (`Package.swift`), so the oracle's uniform
provider must be a core type; otherwise the plan either fails to compile or silently
grows `TextEngineCoreTests`'s dependency on the reference-provider product. Keeping
it in the core avoids both.

`PrefixSumColumnMetrics` — the variable/proportional provider — lives in
`TextEngineReferenceProviders`, mirroring `PrefixSumLineMetrics`. Proportional
advance (not a monospace grid) is the *common* horizontal case, so a variable
reference provider is what makes the containing-cell search meaningful on unequal
spans and gives the benchmark a realistic scenario (Benchmark Mode). It stores
per-line prefix sums — provider-side storage outside the core, exactly like
`PrefixSumLineMetrics`, and therefore outside the core-memory invariant. Its
`columnAt` coverage lives in `TextEngineReferenceProvidersTests` (which imports both
products), never in the core test target (Testing Strategy).

## Component Design

### New file: `Sources/TextEngineCore/LineHorizontalMetricsSource.swift`

The `LineHorizontalMetricsSource` protocol (Decision 1), its default
`columnIndex(containingOffset:inLine:)` extension, and the shared
`binarySearchColumnIndex(...)` free function — the horizontal mirror of
`LineMetricsSource.swift`'s `binarySearchLineIndex`:

```swift
func binarySearchColumnIndex<Metrics: LineHorizontalMetricsSource>(
    containingOffset target: Double, metrics: Metrics,
    inLine line: Int, columnCount: Int
) -> Int {
    var low = 0
    var high = columnCount - 1
    var result = 0
    while low <= high {
        let mid = low + (high - low) / 2
        if metrics.columnOffset(inLine: line, column: mid) <= target {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    return result
}
```

("Largest `c` in `[0, columnCount)` with `columnOffset(c) <= x`" — identical shape
to `binarySearchLineIndex`, with the `inLine`/`column` addressing.)

### New file: `Sources/TextEngineCore/HorizontalPositionQuery.swift`

An `extension ViewportVirtualizer` holding the public
`columnAt(x:inLine:metrics:)`. It runs the Decision 4/5 validation ladder, computes
`width = metrics.columnOffset(inLine: line, column: count)` once, handles the two
clamp branches without touching the search, and for in-range `x` dispatches to
`metrics.columnIndex(containingOffset:inLine:)`, wrapping as
`.column(ColumnLocation(i, .inRange))`.

```swift
extension ViewportVirtualizer {
    public static func columnAt<Metrics: LineHorizontalMetricsSource>(
        x: Double, inLine line: Int, metrics: Metrics
    ) -> ColumnQuery {
        let count = metrics.columnCount(inLine: line)
        if count < 0 { return .failure(.negativeColumnCount) }
        if !x.isFinite { return .failure(.nonFiniteValue) }
        if metrics.columnOffset(inLine: line, column: 0) != 0.0 {
            return .failure(.invalidColumnMetrics)      // O(1) probe, before empty short-circuit
        }
        if count == 0 { return .empty }                 // blank line
        let width = metrics.columnOffset(inLine: line, column: count)
        if !width.isFinite || width <= 0.0 { return .failure(.invalidColumnMetrics) }
        if x < 0.0 { return .column(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft)) }
        if x >= width { return .column(ColumnLocation(columnIndex: count - 1, clamp: .clampedToRight)) }
        let index = metrics.columnIndex(containingOffset: x, inLine: line)
        return .column(ColumnLocation(columnIndex: index, clamp: .inRange))
    }
}
```

**O(log M) `columnOffset` queries** (one binary search) / **O(1) core memory**;
zero allocation; Foundation-free; Embedded-safe (only `Int`/`Double`/generic over a
protocol — identical footprint to `lineAt`).

### Types added to `Sources/TextEngineCore/ViewportTypes.swift`

`ColumnQuery`, `ColumnLocation`, and `ColumnLocation.Clamp` (Decision 2), beside the
existing `LineQuery` / `LineLocation`, so the public query vocabulary stays in one
file. Two cases (`negativeColumnCount`, `invalidColumnMetrics`) added to
`ViewportValidationError` (Decision 3).

### `Sources/TextEngineCore/LineHorizontalMetricsSource.swift` (with the protocol): `UniformColumnMetrics`

The faithful mirror of `UniformLineMetrics` — which likewise lives in the core,
inside `LineMetricsSource.swift`. A uniform grid, O(1) metric, **no per-line
storage** (so it cannot violate the core-memory invariant), relying on the
binary-search default for the inverse (no `columnIndex` override, exactly as
`UniformLineMetrics` provides no `lineIndex` override). Placed in the core so the
`ColumnAt*` equivalence oracle in `TextEngineCoreTests` can drive it without a
reference-provider dependency (Decision 8):

```swift
public struct UniformColumnMetrics: LineHorizontalMetricsSource {
    public let columnsPerLine: Int
    public let columnWidth: Double

    public init(columnsPerLine: Int, columnWidth: Double) {
        self.columnsPerLine = columnsPerLine
        self.columnWidth = columnWidth
    }

    public func columnCount(inLine line: Int) -> Int { columnsPerLine }
    public func columnOffset(inLine line: Int, column: Int) -> Double {
        Double(column) * columnWidth
    }
}
```

### New file: `Sources/TextEngineReferenceProviders/PrefixSumColumnMetrics.swift`

The variable/proportional provider, the faithful mirror of `PrefixSumLineMetrics`:
per-line cumulative offsets precomputed as prefix-sum arrays. `columnOffset` is
O(1); provider-side per-line storage sits outside the core-memory invariant
(Decision 8). It relies on the binary-search default for the inverse (no
`columnIndex` override — a native descent is a future slice). This is the realistic
non-uniform-advance case that exercises the containing-cell search on unequal spans:

```swift
public struct PrefixSumColumnMetrics: LineHorizontalMetricsSource {
    /// One prefix-sum array per line: `prefix[line][c]` is the left offset of cell
    /// `c`, with `prefix[line][0] == 0` and `prefix[line].count == cells + 1`.
    public let prefix: [[Double]]

    /// `advancesPerLine[line]` is that line's per-cell advances (widths).
    public init(advancesPerLine: [[Double]]) {
        prefix = advancesPerLine.map { advances in
            var sums: [Double] = [0.0]
            sums.reserveCapacity(advances.count + 1)
            var running = 0.0
            for advance in advances {
                running += advance
                sums.append(running)
            }
            return sums
        }
    }

    public func columnCount(inLine line: Int) -> Int { prefix[line].count - 1 }
    public func columnOffset(inLine line: Int, column: Int) -> Double {
        prefix[line][column]
    }
}
```

### No change to the vertical axis

`LineMetricsSource`, `PositionQuery.swift` (`lineAt`), `VariableLineGeometryCursor`,
`compute`, and all `LineMetricsSource` providers are untouched. Unlike Slice 27
(which relaxed `firstLineTopAtOrBelow`'s access to share a search), this slice adds
a **wholly new** search over a **new** protocol, so there is no behavior-preserving
refactor of an existing gate-covered path — a strictly additive slice.

## Testing Strategy

XCTest only, TDD failing-first. The core `ColumnAt*` tests (oracle, failures, clamp,
boundary, query-count) live in `Tests/TextEngineCoreTests` and use only core types
(`UniformColumnMetrics` + hand-built sources), so the core test target keeps its
`TextEngineCore`-only dependency (`Package.swift`, Decision 8). The one test that
drives the shipped `PrefixSumColumnMetrics` through `columnAt` lives in
`Tests/TextEngineReferenceProvidersTests` (which already imports both products),
exactly as the vertical reference providers are tested there — never by widening
`TextEngineCoreTests`'s dependencies.

### Closed-form equivalence oracle (load-bearing)

The oracle is **structural**, not a re-derivation by `floor(x / columnWidth)`. A
raw division-based floor is numerically fragile at exact boundaries: `columnAt`'s
in-range answer comes from the binary search comparing **products**
(`columnOffset(c) = Double(c) * columnWidth <= x`), while `floor(x / columnWidth)`
divides, and the two can disagree by one at an exact boundary `x = k * columnWidth`
— the same hazard the vertical uniform oracle guards by restricting to
exactly-representable heights.

So the oracle picks `columnWidth` from the exactly-representable set
(`[1.0, 8.0, 16.0, 12.5, 256.0]`) and `columnsPerLine` well under `2^53`, and
**builds each `x` from a product** so the expected cell is known by construction:

| Constructed `x` | Expected `ColumnQuery` |
| --- | --- |
| `-columnWidth` | `.column(0, .clampedToLeft)` |
| `0.0` | `.column(0, .inRange)` |
| `Double(k) * columnWidth` for `k ∈ {0, 1, count/2, count-1}` | `.column(k, .inRange)` |
| `Double(k) * columnWidth + columnWidth/2` for `k < count` | `.column(k, .inRange)` |
| `Double(count) * columnWidth` (line width) | `.column(count-1, .clampedToRight)` |
| `Double(count) * columnWidth + columnWidth` | `.column(count-1, .clampedToRight)` |

Run the sweep for several `(columnsPerLine, columnWidth)` pairs, including
`columnsPerLine == 1`, over a few distinct `inLine` values (to prove `inLine`
addressing is honoured). Because every `x` is a product over a representable width,
the search and the expected index agree exactly, and the boundary case
`x = k * columnWidth → cell k` is asserted directly.

### Unit tests (`ColumnAtTests`)

- **Blank line** (`columnCount == 0`) → `.empty`, for any `x` (negative, zero,
  positive), over multiple `inLine` values.
- **Failure cases**: `negativeColumnCount`; non-finite `x` (`.nan`, `.infinity`,
  `-.infinity`) → `.nonFiniteValue`; a hand-built source with
  `columnOffset(_, 0) != 0` → `.invalidColumnMetrics`; a source whose line width is
  `0` / non-finite → `.invalidColumnMetrics`.
- **Clamp flags**: `x < 0` → `clampedToLeft` at cell 0; `x >= width` →
  `clampedToRight` at last cell; `x == 0` → `inRange` at cell 0; `x == width` →
  `clampedToRight`.
- **Exact-boundary resolution**: `x == columnOffset(c)` → cell `c` (`inRange`).
- **Non-uniform metrics** (core, hand-built source): varied advances (e.g.
  `[10, 30, 5, 50]` for a line) — verify each boundary and mid-span `x` maps to the
  correct cell, independent of the uniform oracle. The shipped
  `PrefixSumColumnMetrics` is exercised by a companion test in
  `TextEngineReferenceProvidersTests` (same advance vectors), so the real variable
  provider is covered without pulling a reference-provider dependency into the core
  test target.
- **Single-cell line** (`columnCount == 1`): every in-range `x` → cell 0 `inRange`;
  `x < 0` / `x >= width` → the clamp flags.
- **Per-line addressing**: a hand-built source whose lines have *different* advance
  arrays — assert `columnAt(x, inLine: a)` and `columnAt(x, inLine: b)` resolve
  against the correct line's metrics.

### Query-count / dispatch tests (`ColumnAtQueryCountTests`)

Mirrors `LineGeometryAtQueryCountTests` with a `CountingColumnMetrics` wrapper that
increments a shared counter on every `columnOffset(inLine:column:)` and asserts
dispatch flows through the `columnIndex` hook. Asserts the exact `columnOffset`
count per path — not a wall-clock measurement:

| `columnAt` path | Expected `columnOffset` count |
| --- | --- |
| **in-range**, 1M cells | `<= 2 + (ceilLog2(count) + 1)` — two O(1) probes (`columnOffset(0)`, width) plus one binary search; and `< 100` (a linear scan would be hundreds of thousands) |
| **blank line** (`count == 0`) | exactly `1` — only the `columnOffset(0)` probe, then `.empty` |
| **clamp branch** (`x < 0` and `x >= width`, 1M cells) | exactly `2` — `columnOffset(0)` + width, no search probes |
| **non-finite `x`** | exactly `0` — returns before any `columnOffset` probe |

Also assert the in-range path routes through `columnIndex(containingOffset:inLine:)`
using an **ordered event log**, not a boolean "was it called" — matching the vertical
`LineAtQueryCountTests` (`Tests/TextEngineCoreTests/LineAtQueryCountTests.swift`,
which asserts `events == [.offset(0), .offset(4), .native(31.0)]`). A
`CountingColumnMetrics` records each probe as `.offset(line, column)` and each hook
call as `.native(line, x)`, and the tests assert:

- **in-range**: `events == [.offset(line, 0), .offset(line, count), .native(line, x)]`
  — the two validation probes in order, then exactly one native dispatch, with the
  correct `inLine` threaded through every event;
- **blank / clamp / non-finite**: **no** `.native(...)` event at all (blank ends at
  `[.offset(line, 0)]`; clamp at `[.offset(line, 0), .offset(line, count)]`;
  non-finite at `[]`).

This proves both the exact dispatch order and that a future provider-native override
is reachable only on the in-range path.

### No behavior-preservation burden

This slice adds only new files/types and two enum cases; it changes no existing
algorithm. The existing full suite (vertical oracle, query-count, `compute`,
cursors, all providers) must pass **unchanged in count and result** — its only
expected delta is the new `ColumnAt*` tests. No existing gate checksum changes.

## Benchmark Mode (`ViewportBenchmarks`)

New file `Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift`, modeled on
`LineQueryBenchmark.swift`:

- **Mode**: add `.columnQuery` to `BenchmarkMode` (`outputName = "column_query"`),
  `--column-query` to `BenchmarkOptions.parse`/usage, a `.columnQuery` arm in
  `BenchmarkProgram.runBenchmarks`, and (if the synthetic switch requires it) a
  `.columnQuery` arm wherever `.lineQuery` is matched
  (`SyntheticBenchmarks.swift:126`, `BenchmarkProgram.swift:16`).
- **Scenarios**: `UniformColumnMetrics` at increasing `columnsPerLine` — proposed
  `uniform_1k`, `uniform_100k`, `uniform_1m` cells — **plus** a
  `PrefixSumColumnMetrics` variable-advance scenario at matching sizes (proposed
  `prefixsum_100k`, `prefixsum_1m`, built from deterministic varied advances), each
  with `p95`/`p99` budgets. Large cell counts exist only to exercise search depth
  (real lines are short); the prefix-sum scenarios add the realistic proportional
  case so the gate covers non-uniform spans, not only the uniform grid. Both
  providers answer `columnOffset` in O(1), so the generic binary search over either
  is O(log M) wall-clock. There is still **no** balanced-tree / mutable horizontal
  provider whose own `columnOffset` is O(log M), so — unlike `--line-query`, which
  needed a `balanced_tree` scenario to catch the O(log²N) path — this suite does not
  yet exercise an O(log²M) provider; that remaining gap is recorded (Risks And Gaps).
- **Workload**: per operation, derive a deterministic `x` spanning in-range and
  out-of-range values (reusing `deterministicScrollOffset` / a deterministic
  fraction of the line width, with a slice of samples pushed below `0` and at/above
  `width` to exercise both clamp branches) at a deterministic `inLine`, call
  `columnAt(x:inLine:metrics:)`, and fold the returned `columnIndex` and an integer
  encoding of the `clamp` case into a running **checksum** (determinism guard,
  matching every other benchmark).
- **Gate**: `--column-query --gate` enforces `p95`/`p99` budgets and exits non-zero
  on regression; without `--gate` it asserts `failureCount == 0`. Budgets are
  macOS-calibrated; the plan records the observed numbers and sets budgets with the
  project's customary headroom.

`--gate` validity extends to `.columnQuery` automatically (Decision 7 — the parser
denylist needs no change).

## CI

**No `.github/workflows/swift-ci.yml` change.** The `--column-query --gate` is a
local gate this slice (Decision 7). The required job contexts, docs-only path,
iOS/WASM jobs, and the `Main` ruleset are all unchanged. CI promotion is the
recommended follow-up slice (Future Slices).

## Verification

Recorded in `docs/superpowers/verification/2026-07-04-horizontal-position-query.md`:

- `swift test` — host unit tests (new `ColumnAt*` oracle + unit + query-count tests
  green; existing suite unchanged count + 0 failures).
- `swift build -c release`.
- `swift run -c release ViewportBenchmarks -- --column-query --gate` → every
  scenario `gate=pass`; record p95/p99 and checksums.
- Existing gates still green and **checksum-identical** (this slice touches no
  existing algorithm, so all must be byte-identical): `--gate`,
  `--variable-height --gate`, `--variable-height-mutation --gate`,
  `--structural-mutation --gate`, `--bulk-structural-mutation --gate`,
  `--line-query --gate`, `--line-geometry-query --gate`.
- `--memory-shape` invariant `pass` (the query is O(1) memory).
- Foundation-free scans: `rg -n "Foundation" Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders` → empty (exit 1).
- `./.github/scripts/cross-target-compile.sh --self-test`, then the iOS (blocking)
  and WASM (observational) cross-target paths for both `TextEngineCore` and
  `TextEngineReferenceProviders` (the new `UniformColumnMetrics` in the core and
  `PrefixSumColumnMetrics` in the reference providers must both cross-compile).
- Hosted PR run + post-merge push run IDs, verified at **step level**, recorded in
  the post-merge follow-up (per the standing stale-on-write lesson: record the
  PR-head proof against the stable final head in the post-merge doc, never against a
  pre-final commit).

## Acceptance Criteria

1. `ViewportVirtualizer.columnAt(x:inLine:metrics:) -> ColumnQuery` is public,
   stateless, and behaves exactly per the Decision 4 table.
2. The closed-form equivalence oracle passes: in-range `columnAt` equals the
   structurally-derived expected cell (index + clamp) across the full product-built
   `x` sweep over exactly-representable widths, for multiple
   `(columnsPerLine, columnWidth)` including `columnsPerLine == 1` and multiple
   `inLine` values.
3. All listed unit and failure tests pass; `.empty` and all **`columnAt`-reachable**
   validation outcomes are covered — `.negativeColumnCount`, `.nonFiniteValue`, and
   both `.invalidColumnMetrics` triggers (invalid first offset, invalid line width).
4. The query-count tests pass with the exact per-path `columnOffset` counts in the
   Testing Strategy table (in-range `<= 2 + (ceilLog2(count) + 1)` and `< 100`;
   blank `= 1`; clamp `= 2`; non-finite `x` `= 0`), and the in-range path is proven
   to dispatch through `columnIndex(containingOffset:inLine:)` via an **ordered event
   log** (`[.offset(line, 0), .offset(line, count), .native(line, x)]`), with **no**
   `.native` event on the blank / clamp / non-finite paths.
5. The slice is strictly additive: the entire existing suite passes unchanged in
   count and result, and all seven existing gates pass with identical checksums.
6. `--column-query` benchmark runs (uniform **and** prefix-sum scenarios);
   `--column-query --gate` enforces budgets and joins the gateable set (never
   rejected), while `--gate` stays rejected with
   `--range-only`/`--memory-shape`/`--memory-observation`.
7. `UniformColumnMetrics` (in `TextEngineCore`, no per-line storage) and
   `PrefixSumColumnMetrics` (in `TextEngineReferenceProviders`, per-line prefix sums)
   both conform to `LineHorizontalMetricsSource` and cross-compile for iOS (blocking)
   and WASM (observational).
8. Foundation-free scans empty; `--memory-shape` invariant `pass`.
9. Full paper trail (spec, plan, verification, post-slice review) on a
   `slice-33-horizontal-position-query` branch; one PR; conventional commits.

## Risks And Gaps

### The strictly-increasing contract assumes provider-side cell resolution

Unlike line heights (always positive), raw glyph advances can be zero (combining
marks, ZWJ, ligature components) and, in a bidi run, logical order is not visual
order. The `columnOffset` contract (strictly increasing, visual order) therefore
pushes two real responsibilities onto the provider: fold zero-advance glyphs into
their base cell, and present cells in visual (left-to-right) order (Decision 6). A
provider that feeds raw per-glyph advances or logical-order cells violates the
contract, and the core cannot detect it (it never scans all offsets — Decision 5).
This is the horizontal analog of the vertical "contract-trusting" posture, but a
*stronger* ask than the vertical axis makes, so it is called out explicitly rather
than left implicit. `columnIndex` is a visual cell index; a consumer needing logical
character positions must apply the provider's own visual↔logical map.

### Result carries no geometry (deferred richness)

A caller doing tap-to-caret wants the cell's `x`/width and the fractional offset
within the cell (to snap the caret left or right). This slice returns only
`columnIndex` + `clamp`; such a caller makes one or two extra `columnOffset`
queries. A future geometry-bearing `columnGeometryAt` (the `lineGeometryAt` analog)
adds the richness **as a new method/result type**, never by appending a case to
`ColumnQuery` (source-breaking for client switches over a non-frozen enum). Chosen
now for minimal surface (Decision 6).

### Benchmark covers uniform + proportional, but no O(log²M) horizontal path exists yet

This slice ships both a uniform (`UniformColumnMetrics`) and a variable/proportional
(`PrefixSumColumnMetrics`) provider, and the benchmark exercises both — so it covers
the realistic non-uniform-advance case, not only a monospace grid. What it still
cannot cover is an O(log²M) path: `--line-query` needed a `balanced_tree` scenario
because a mutable tree provider's `offset(ofLine:)` is itself O(log N), making the
generic search O(log²N). Both horizontal providers here answer `columnOffset` in
O(1), so the suite measures only the O(log M) baseline. When a balanced-tree /
mutable horizontal provider is added (Future Slices), the benchmark must gain a
matching scenario before it can claim to cover that provider's real hot path — the
same lesson the vertical benchmark encodes.

### `inLine` is trusted, not validated

`columnAt` does not defend against an out-of-range `inLine`; it is a documented
precondition (Decision 5), consistent with the vertical primitives' contract
posture and with the standalone source carrying no `lineCount`. The eventual
`pointAt(x:y:)` always supplies a line validated by `lineAt`. A standalone caller
passing a bogus `inLine` is a contract violation, not a defended case.

### Budgets are macOS-calibrated and local-only

Like every gate before CI promotion, the `--column-query` budgets are macOS-derived
and unenforced in hosted CI until a promotion slice. A regression in `columnAt`
would be caught locally but not block merge until promotion. This matches the
established rhythm and is an accepted, time-boxed gap.

### Contract-trusting line-width check

For a non-blank line the `LineHorizontalMetricsSource` contract guarantees a finite,
strictly-positive width; the explicit non-finite / `<= 0` check is defensive parity
with `lineAt`, not a guarantee the core can fully enforce against a misbehaving
provider mid-line. Consistent with the existing vertical path's contract posture.

## Future Slices

- **`pointAt(x:y:)` composite (recommended next)**: compose `lineAt(y:)` ∘
  `columnAt(x:)` into a 2D hit-test returning `(line, column, clamp)` — trivial glue
  over the two primitives (the `lineGeometryAt`-over-`lineAt` pattern), delivering
  the first end-to-end 2D capability. Takes both a `LineMetricsSource` and a
  `LineHorizontalMetricsSource`.
- **Promote `--column-query --gate` to a blocking hosted CI gate**, completing the
  functional → promotion pair (the eighth blocking latency gate), exactly as
  Slices 15 / 21 / 24 / 26 / 28 / 32 did for the prior modes. May be folded with, or
  sequenced after, the `pointAt` slice.
- **Geometry-bearing `columnGeometryAt(x:inLine:)`**: the cell's box +
  `fractionInColumn` + clamp, the horizontal `lineGeometryAt` analog, enabling caret
  left/right snapping. New method/result type (see Risks).
- **Provider-native horizontal descent + mutable horizontal provider**: an O(1)
  monospace `columnIndex` override and a balanced-tree / mutable horizontal provider
  with a native O(log M) descent (the Slice 29 analog for the horizontal axis; the
  variable/prefix-sum provider itself ships in this slice), plus a matching
  balanced-tree benchmark scenario to catch the O(log²M) path.
- **Wrap-aware visual rows** remain the larger future capability flagged by the
  Slice 32 review; needs its own brainstorm, and interacts with both axes.
