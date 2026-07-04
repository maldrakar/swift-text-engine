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
and unit tests, a `UniformColumnMetrics` reference provider, a `--column-query`
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
- A `UniformColumnMetrics` reference provider in `TextEngineReferenceProviders`
  (uniform in both dimensions; no per-line storage), mirroring `UniformLineMetrics`.
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
- **No wrap / visual rows.** The unit stays the logical line's cells.
- **No provider-native horizontal descent.** `UniformColumnMetrics` uses the
  binary-search default (like `UniformLineMetrics`); an O(1) monospace override
  and a variable/prefix-sum horizontal provider are deferred (the Slice 29 analog).
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
    /// `columnOffset(_, column: c + 1)` are finite and strictly increasing. The
    /// core never queries outside `0...columnCount(inLine: line)`.
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

`ViewportValidationError` is a non-frozen `Equatable` enum; appending cases is
source-compatible for the library's own exhaustive switches (all in-repo).
Extending the shared enum keeps the failure vocabulary single-sourced, matching how
the vertical position queries reuse it rather than minting a parallel error type.

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

### Decision 6 — Cell model, sub-cell position deferred (mirror of vertical Decision 7)

The result is `columnIndex` + `clamp` only — no cell `x`/width, no
`fractionInColumn`, no caret left/right snapping. A caller wanting sub-cell position
gets it from a future geometry-bearing companion (`columnGeometryAt`, the
`lineGeometryAt` analog) — added as a **new method / result type**, never by
appending a case to `ColumnQuery` (source-breaking for client switches over a
non-frozen enum). Keeping the primitive minimal avoids widening the public type and
an extra `columnOffset` query on the hot path for callers that only need the cell.

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

### New file: `Sources/TextEngineReferenceProviders/UniformColumnMetrics.swift`

The faithful mirror of `UniformLineMetrics` — a uniform grid, O(1) metric, **no
per-line storage** (so it cannot violate the core-memory invariant), relying on the
binary-search default for the inverse (no `columnIndex` override, exactly as
`UniformLineMetrics` provides no `lineIndex` override):

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

### No change to the vertical axis

`LineMetricsSource`, `PositionQuery.swift` (`lineAt`), `VariableLineGeometryCursor`,
`compute`, and all `LineMetricsSource` providers are untouched. Unlike Slice 27
(which relaxed `firstLineTopAtOrBelow`'s access to share a search), this slice adds
a **wholly new** search over a **new** protocol, so there is no behavior-preserving
refactor of an existing gate-covered path — a strictly additive slice.

## Testing Strategy

XCTest only, in `Tests/TextEngineCoreTests`, TDD failing-first.

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
- **Non-uniform metrics**: a hand-built source with varied advances (e.g.
  `[10, 30, 5, 50]` for a line) — verify each boundary and mid-span `x` maps to the
  correct cell, independent of the uniform oracle.
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
(a counting override that records it was called), so a future provider-native
override is guaranteed to be reachable.

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
  `uniform_1k`, `uniform_100k`, `uniform_1m` cells — each with `p95`/`p99` budgets,
  purely as a **binary-search-depth / log-scaling probe** (real lines are short;
  large cell counts exist only to exercise search depth). Because
  `UniformColumnMetrics.columnOffset` is O(1), the generic binary search over it is
  O(log M) wall-clock; there is **no** balanced-tree horizontal provider yet, so —
  unlike `--line-query`, which needed a `balanced_tree` scenario to catch the
  O(log²N) path — this suite is uniform-only by construction, and that limitation is
  recorded (Risks And Gaps).
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
  `TextEngineReferenceProviders` (the new `UniformColumnMetrics` must cross-compile).
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
   to dispatch through `columnIndex(containingOffset:inLine:)`.
5. The slice is strictly additive: the entire existing suite passes unchanged in
   count and result, and all seven existing gates pass with identical checksums.
6. `--column-query` benchmark runs; `--column-query --gate` enforces budgets and is
   rejected only where the other gateable modes are (never — it joins the gateable
   set); `--gate` stays rejected with
   `--range-only`/`--memory-shape`/`--memory-observation`.
7. `UniformColumnMetrics` conforms to `LineHorizontalMetricsSource`, stores no
   per-line data, and cross-compiles for iOS (blocking) and WASM (observational).
8. Foundation-free scans empty; `--memory-shape` invariant `pass`.
9. Full paper trail (spec, plan, verification, post-slice review) on a
   `slice-33-horizontal-position-query` branch; one PR; conventional commits.

## Risks And Gaps

### Result carries no geometry (deferred richness)

A caller doing tap-to-caret wants the cell's `x`/width and the fractional offset
within the cell (to snap the caret left or right). This slice returns only
`columnIndex` + `clamp`; such a caller makes one or two extra `columnOffset`
queries. A future geometry-bearing `columnGeometryAt` (the `lineGeometryAt` analog)
adds the richness **as a new method/result type**, never by appending a case to
`ColumnQuery` (source-breaking for client switches over a non-frozen enum). Chosen
now for minimal surface (Decision 6).

### Benchmark is uniform-only (no O(log²N) horizontal path exists yet)

`--line-query` needed a `balanced_tree` scenario because a mutable tree provider's
`offset(ofLine:)` is itself O(log N), making the generic search O(log²N). There is
**no** balanced-tree horizontal provider in this slice, so `--column-query` is
uniform-only and measures only the O(log M) baseline. When a
variable/tree-structured horizontal provider is added (Future Slices), the benchmark
must gain a matching scenario before it can claim to cover that provider's real hot
path — the same lesson the vertical benchmark encodes.

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
- **Provider-native horizontal descent + variable horizontal provider**: an O(1)
  monospace `columnIndex` override and a variable/prefix-sum horizontal provider
  (the Slice 29 analog for the horizontal axis), with a matching benchmark scenario.
- **Wrap-aware visual rows** remain the larger future capability flagged by the
  Slice 32 review; needs its own brainstorm, and interacts with both axes.
