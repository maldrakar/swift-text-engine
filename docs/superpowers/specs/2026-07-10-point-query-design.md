# 2D Point-Query (`pointAt(x:y:)`) Design

Slice 37 — the first two-axis primitive, composing the completed vertical and
horizontal position queries into a single `(x, y)` → `(line, cell)` hit-test.

## Status

Proposed. Brainstormed 2026-07-10; recommended by the Slice 36 post-slice review
(Option B — the `pointAt(x:y:)` 2D composite, "the product leap, now fully
unblocked") and scoped by the user, in sequence, to: Option B → *position-only
`pointAt` first* (geometry-bearing companion deferred to a later slice) → *nested
result shape* (`PointLocation` carrying a `LineLocation` plus a `ColumnResolution`
enum with an explicit `.blankLine` case).

## Source Context

The brief (`docs/initial-project-brief.md`) wants a headless
layout/virtualization core that supports realistic editing/scrolling of 100k+
line / >10 MB documents, stays Foundation-free and Embedded-compatible, keeps
core-owned memory sub-linear in document size, and keeps the document behind a
provider/source abstraction.

Both engine axes are now complete **and** CI-protected, each with a position
query, a geometry-bearing companion, and blocking hosted regression gates:

- **Vertical**: `lineAt(y:metrics:)` (Slice 27) → `lineGeometryAt(y:metrics:)`
  (Slice 31), gated by `--line-query` (Slice 28) and `--line-geometry-query`
  (Slice 32), with provider-native O(log N) descent (Slices 29/30).
- **Horizontal**: `columnAt(x:inLine:metrics:)` (Slice 33) →
  `columnGeometryAt(x:inLine:metrics:)` (Slice 35), gated by `--column-query`
  (Slice 34) and `--column-geometry-query` (Slice 36).

The Slice 36 review handed off with **no CI/governance debt** — all nine latency
gates run blocking in hosted CI — and named the 2D `pointAt(x:y:)` hit-test
(Option B) as the highest-value next increment, "now fully unblocked" because
both axes are geometry-bearing *and* their latency contracts are hosted-blocking.
This slice ships that composite's foundational, position-only form: the direct 2D
analog of how `lineGeometryAt` composed over `lineAt` on one axis.

## Problem

Every real consumer of a layout engine ultimately hit-tests a **point**, not an
axis: a pointer lands at `(x, y)` and the engine must answer *which line, and
which cell within it*. The two halves already exist —

- `lineAt(y:metrics:)` resolves the line over a `LineMetricsSource`;
- `columnAt(x:inLine:metrics:)` resolves the cell within a given line over a
  `LineHorizontalMetricsSource` —

but nothing composes them. A click-to-caret / selection / hit-test consumer today
must wire the two together itself, and in doing so must re-derive three subtle
composition rules that belong in the core, once:

1. **Ordering / dependency**: `columnAt` needs a valid `inLine`, which only exists
   *after* `lineAt` has resolved the line — so the vertical query must run first
   and feed the horizontal one.
2. **Failure precedence**: if the vertical metrics are invalid there is no line to
   query columns in, so a vertical failure must short-circuit before the
   horizontal query is even attempted.
3. **The blank-line seam**: a located line may have *no cells*
   (`columnAt` → `.empty`), which is neither an empty document nor a normal cell
   hit and needs its own representation — distinct from a caller accidentally
   collapsing it into "no result".

Left to each caller, these diverge (wrong failure precedence, mishandled blank
lines, inconsistent clamp reporting) exactly as an ad-hoc horizontal binary search
would have diverged from `lineAt` before Slice 33. The core already owns both 1D
queries and their conventions; it should own the one correct composition.

## Scope

Add a single public, stateless query to `TextEngineCore`:

> Given a target `(x, y)`, a `LineMetricsSource`, and a
> `LineHorizontalMetricsSource`, return the located line and the located cell
> within that line — each with its own clamp flag — resolving the empty-document,
> blank-line, and either-axis-failure cases explicitly.

Plus the result types (`PointQuery`, `PointLocation`, `ColumnResolution`), the
unit + composition-parity oracle tests, a `--point-query` benchmark mode with a
**local** `--gate`, and the slice paper trail. **No** new metrics protocol, **no**
new provider, **no** new search code, **no** geometry-bearing 2D result, **no** CI
promotion — this slice is pure composition over two already-shipped, already-gated
primitives.

## Goals

- Public
  `ViewportVirtualizer.pointAt(x:y:lineMetrics:columnMetrics:) -> PointQuery`,
  generic over both a `LineMetricsSource` (vertical) and a
  `LineHorizontalMetricsSource` (horizontal), composing `lineAt` ∘ `columnAt`.
- **Nested result shape**: `.point(PointLocation)` where `PointLocation` carries
  the always-present located `line: LineLocation` and a `column: ColumnResolution`
  that is either `.cell(ColumnLocation)` or `.blankLine`; top-level `.empty`
  reserved strictly for an empty document; `.failure(ViewportValidationError)` for
  either axis's validation failure.
- **Parity by construction**: the line half always equals `lineAt(y:lineMetrics:)`
  and the cell half always equals
  `columnAt(x:inLine: locatedLine, metrics: columnMetrics)`, proven by a
  composition oracle over an `(x, y)` grid.
- **Failure precedence**: the vertical query runs first; its failure
  short-circuits (the horizontal query is never attempted, and cannot be, without
  a valid `inLine`); only a vertical success proceeds to the horizontal query,
  whose failure is then surfaced.
- **Both-axes-clamped needs no special case**: the vertical `line.clamp`
  (top/bottom) and the horizontal cell `clamp` (left/right) are independent flags,
  each preserved verbatim from its 1D query.
- **Cost**: O(log N) + O(log M) queries (or better where a provider overrides its
  native inverse hook), **O(1)** core memory, zero allocation beyond the small
  returned value structs — the sum of the two 1D envelopes, adding no search of
  its own.
- Reuse the shared `ViewportValidationError` unchanged (no new cases — both 1D
  queries already surface every failure this composite can encounter).
- A `--point-query` benchmark mode + **local** `--gate` with macOS-calibrated
  budgets, following the established functional-slice rhythm.
- Foundation-free, Embedded-compatible, zero-dependency; iOS/WASM cross-target
  compile unchanged.

## Non-Goals

- **No geometry-bearing 2D result.** The result is `(LineLocation,
  ColumnResolution)` — line index + vertical clamp, cell index + horizontal clamp
  — with **no** boxes and **no** `fractionInLine` / `fractionInColumn`. A
  geometry-bearing `pointGeometryAt(x:y:)` companion (composing `lineGeometryAt` ∘
  `columnGeometryAt`, or equivalently composing over `pointAt` plus O(1) box
  probes) is the recommended next slice (Future Slices), exactly as
  `lineGeometryAt` followed `lineAt` and `columnGeometryAt` followed `columnAt`.
- **No new metrics protocol and no new provider.** `pointAt` consumes the existing
  `LineMetricsSource` and `LineHorizontalMetricsSource` and their existing
  providers unchanged. It adds no `UniformPointMetrics`, no combined source.
- **No new search code.** All inverse search stays in the two 1D queries;
  `pointAt` only orders and combines their results.
- **No error-vocabulary change.** `ViewportValidationError` is reused **unchanged**
  — every failure `pointAt` can surface (`negativeLineCount`, `nonFiniteValue`,
  `invalidLineMetrics` from the vertical query; `negativeColumnCount`,
  `nonFiniteValue`, `invalidColumnMetrics` from the horizontal query) already
  exists. No case is added or removed (contrast Slice 33, which extended the enum).
- **No `pointAt` overload taking a single fused source.** Two independent sources
  are passed explicitly; fusing them is a provider/caller concern, not the core's.
- **No wrap / visual rows, no bidi reordering, no shaping/rasterization.** Inherited
  verbatim from the two 1D queries' non-goals; `pointAt` adds no new modelling.
- **No CI promotion.** `--point-query --gate` runs locally only this slice;
  promoting it to a blocking hosted gate is a separate follow-up slice, exactly as
  every prior functional → promotion pair (line-query → 28, line-geometry-query →
  32, column-query → 34, column-geometry-query → 36).
- **No change to the 1D queries or providers.** `lineAt`, `lineGeometryAt`,
  `columnAt`, `columnGeometryAt`, `compute`, `LineMetricsSource`,
  `LineHorizontalMetricsSource`, and every provider are untouched. Strictly
  additive.

## Decisions

### Decision 1 — Two independent sources, passed explicitly; vertical runs first

`pointAt` takes **both** a `LineMetricsSource` (vertical) and a
`LineHorizontalMetricsSource` (horizontal) as separate generic parameters, labelled
`lineMetrics:` and `columnMetrics:` to name each axis by what it provides and to
disambiguate the two `metrics:`-labelled 1D queries it composes:

```swift
public static func pointAt<VMetrics: LineMetricsSource, HMetrics: LineHorizontalMetricsSource>(
    x: Double, y: Double,
    lineMetrics: VMetrics,
    columnMetrics: HMetrics
) -> PointQuery
```

The two sources are **independent by design** (Slice 33 Decision 1 kept the
horizontal metric a separate concern with no `lineCount`), so the composite cannot
fuse them; it consumes both. The **vertical query runs first** because the
horizontal query is parameterized by a line index (`inLine`) that only the vertical
query can produce — the same "document → line, line → cell" dependency the
horizontal axis was designed around. `x` precedes `y` in the label list by
coordinate convention `(x, y)`, though the vertical axis is evaluated first
internally.

### Decision 2 — Result shape: `PointQuery` / `PointLocation` / `ColumnResolution`

```swift
public enum PointQuery: Equatable {
    case point(PointLocation)             // a line was located (cell may be blank)
    case empty                            // empty document: lineCount == 0
    case failure(ViewportValidationError) // vertical or horizontal validation failure
}

public struct PointLocation: Equatable {
    /// The located line (index + vertical clamp). Always a real line.
    public let line: LineLocation
    /// The located cell within that line, or `.blankLine` if the line has no cells.
    public let column: ColumnResolution

    public init(line: LineLocation, column: ColumnResolution) {
        self.line = line
        self.column = column
    }
}

public enum ColumnResolution: Equatable {
    case cell(ColumnLocation)             // a real cell was located (index + horizontal clamp)
    case blankLine                        // located line has no cells (columnCount(inLine:) == 0)
}
```

Rationale:

- **`.point` always carries a line.** Once the vertical query succeeds there *is* a
  line, regardless of whether that line has cells; keeping `line` unconditional
  means a caller that only wants the line (line highlighting, gutter) reads
  `p.line` uniformly without branching on blank-ness. This is why the line lives in
  a `PointLocation` struct rather than being flattened into multiple top-level
  cases.
- **Top-level `.empty` means empty *document* only.** It is the direct 2D analog of
  `lineAt`'s `.empty` (`lineCount == 0`) — a structurally valid document with no
  line to locate. A blank *line* is a different thing and must not collapse into
  it.
- **`.blankLine` is an explicit named case, not `nil`.** A located line with zero
  cells is common (empty lines are everywhere) and structurally valid, so it gets a
  first-class named case inside `ColumnResolution` — matching the codebase's
  explicit-enum convention (`ColumnQuery` itself names this state `.empty` rather
  than using `ColumnLocation?`). An optional `ColumnLocation?` was rejected for
  overloading `nil` and departing from that convention.
- **`.cell` / `.blankLine` rename the 1D states deliberately.** `ColumnResolution`
  uses `.cell` / `.blankLine` where the 1D `ColumnQuery` uses `.column` / `.empty`.
  The divergence is intentional point-level disambiguation, not an oversight:
  `.blankLine` reads unambiguously against the *top-level* `PointQuery.empty`
  (empty document), which a nested `.empty` would clash with, and `.cell` names the
  hit result by what it is at the point level. `ColumnResolution` is a distinct
  point-composition type, so it is free to pick the clearer point-level vocabulary
  rather than mirror `ColumnQuery`'s case names.
- **`ColumnResolution` never carries `.failure`.** A horizontal failure is surfaced
  at the top level as `PointQuery.failure`, never nested — so `ColumnResolution`
  has exactly the two states reachable *after* a horizontal success-or-empty, and a
  caller pattern-matching it need not consider an impossible failure case (contrast
  nesting the whole `ColumnQuery`, which would leak an unreachable `.failure`).
- **Both clamps preserved independently.** `line.clamp` is `LineLocation.Clamp`
  (`.inRange` / `.clampedToTop` / `.clampedToBottom`); the cell clamp is
  `ColumnLocation.Clamp` (`.inRange` / `.clampedToLeft` / `.clampedToRight`). They
  are separate fields on separate structs, so a both-axes-clamped point (e.g. above
  the document *and* left of the line) records both without any combined-clamp type.

### Decision 3 — Composition algorithm & failure precedence

`pointAt` is a pure two-step composition with vertical short-circuit:

```swift
extension ViewportVirtualizer {
    public static func pointAt<VMetrics: LineMetricsSource, HMetrics: LineHorizontalMetricsSource>(
        x: Double, y: Double,
        lineMetrics: VMetrics,
        columnMetrics: HMetrics
    ) -> PointQuery {
        switch lineAt(y: y, metrics: lineMetrics) {
        case let .failure(error):
            return .failure(error)                       // vertical short-circuits
        case .empty:
            return .empty                                // empty document
        case let .line(lineLocation):
            switch columnAt(x: x, inLine: lineLocation.lineIndex, metrics: columnMetrics) {
            case let .failure(error):
                return .failure(error)                   // horizontal failure
            case .empty:
                return .point(PointLocation(line: lineLocation, column: .blankLine))
            case let .column(columnLocation):
                return .point(PointLocation(line: lineLocation, column: .cell(columnLocation)))
            }
        }
    }
}
```

Precedence and semantics, all forced by the composition and by construction:

- **Vertical wins ties.** If the vertical metrics are invalid *and* the horizontal
  would also be invalid, the vertical failure is returned — `columnAt` is never
  called, so its would-be error never materializes. This is not a preference; it is
  the only defined behavior, because the horizontal query needs a valid `inLine`
  that a failed vertical query cannot supply.
- **Shared error type composes cleanly.** Both 1D queries return
  `ViewportValidationError`, so `case let .failure(error): return .failure(error)`
  passes either axis's error through unchanged; no mapping, no new case.
- **`x` finiteness is checked by `columnAt`, `y` by `lineAt`** — each in its own 1D
  ladder, in the same order those queries already define. A non-finite `x` with a
  valid `y` therefore surfaces as `columnAt`'s `.nonFiniteValue` *after* the
  vertical query succeeds; a non-finite `y` surfaces as `lineAt`'s
  `.nonFiniteValue` first and short-circuits (the horizontal query never sees `x`).
- **A horizontal failure discards the located line.** On the `.line(L)` path a
  horizontal `.failure` (e.g. non-finite `x` over an otherwise valid line) returns
  top-level `.failure`, so `L` is *not* surfaced — `pointAt` reports "this point did
  not resolve", not "the line resolved but the cell did not". A caller that needs the
  line even under a garbage `x` should call `lineAt` directly; folding a valid line
  into a `.failure` result would require a fourth, half-resolved shape this slice
  deliberately does not add. This mirrors the 1D contract (a non-finite coordinate is
  a validation failure, not a clamp).
- **No independent validation in `pointAt`.** The composite adds no checks of its
  own; every validation is delegated to the two 1D queries, so their contracts
  remain single-sourced and cannot drift.

### Decision 4 — Full input → result table

Let `V = lineAt(y: y, metrics: lineMetrics)` and, when `V == .line(L)`,
`H = columnAt(x: x, inLine: L.lineIndex, metrics: columnMetrics)`.

| `V` (vertical) | `H` (horizontal) | `pointAt` result |
| --- | --- | --- |
| `.failure(e)` | *(not evaluated)* | `.failure(e)` |
| `.empty` | *(not evaluated)* | `.empty` |
| `.line(L)` | `.failure(e)` | `.failure(e)` |
| `.line(L)` | `.empty` | `.point(PointLocation(line: L, column: .blankLine))` |
| `.line(L)` | `.column(C)` | `.point(PointLocation(line: L, column: .cell(C)))` |

Every row is exercised by the unit tests (Testing Strategy). The clamp flags inside
`L` and `C` carry through verbatim, so e.g. `V = .line(L, .clampedToTop)` with
`H = .column(C, .clampedToLeft)` yields
`.point(PointLocation(line: L(.clampedToTop), column: .cell(C(.clampedToLeft))))`.

**Validation precedes the zero-count short-circuit (both axes).** The rows above
read `.empty` / `.blankLine` as if reachable for any coordinate, but in each 1D
query the `!isFinite` check and the O(1) contract probe run *before* the
`count == 0` branch (`PositionQuery.swift:19-32`, `HorizontalPositionQuery.swift:18-33`).
So `.empty` (empty document) is reachable only with a **finite `y` and valid vertical
metrics**, and `.blankLine` (located blank line) only with a **finite `x` and valid
horizontal metrics**. Concretely: `(lineCount == 0, y = NaN)` → `V = .failure(.nonFiniteValue)`
→ `pointAt == .failure`, *not* `.empty`; and `(columnCount == 0, x = NaN)` →
`H = .failure(.nonFiniteValue)` → `pointAt == .failure`, *not* `.blankLine`. Same for
a broken contract probe (`.invalidLineMetrics` / `.invalidColumnMetrics`). `pointAt`
adds nothing here — this is the two 1D ladders composing verbatim — but the contract
is pinned so no later test wrongly asserts blank-ness (or empty-ness) wins over a
non-finite coordinate.

### Decision 5 — File placement mirrors the 1D queries

The public method lives in a new file
`Sources/TextEngineCore/PointQuery.swift`, an `extension ViewportVirtualizer`,
mirroring `PositionQuery.swift` (`lineAt` / `lineGeometryAt`) and
`HorizontalPositionQuery.swift` (`columnAt` / `columnGeometryAt`). The three result
types go in `Sources/TextEngineCore/ViewportTypes.swift`, beside the existing
`LineQuery` / `ColumnQuery` / `LineGeometryQuery` / `ColumnGeometryQuery`, so the
public query vocabulary stays in one file. No existing file's logic changes.

### Decision 6 — Local gate now, CI promotion deferred (established rhythm)

This functional slice ships the `--point-query` benchmark mode **and** local
`--gate` enforcement with macOS-calibrated budgets, but does **not** wire the gate
into `.github/workflows/swift-ci.yml`. Promotion to a blocking hosted gate is a
separate follow-up slice, identical to the project's eight prior functional →
promotion pairs.

`--gate` becomes valid with `--point-query` automatically: the parser's rejection
is a **denylist** (`--gate` rejected only with `.rangeOnly` / `.memoryShape` /
`.memoryObservation` — `BenchmarkOptions.swift:155`), so a new gateable
`.pointQuery` mode needs no edit there. `AGENTS.md` gains the new local command, the
`--point-query` flag, **and a sentence in the "Architecture in one paragraph"
section** introducing `pointAt` as the first two-axis composite (`(x, y)` →
`(line, cell)`, composing `lineAt ∘ columnAt`, O(log N) + O(log M) queries / O(1)
core memory) — mirroring how every 1D query (`lineAt`, `lineGeometryAt`, `columnAt`,
`columnGeometryAt`) is described there. Its CI section is unchanged because the
workflow is unchanged.

## Component Design

### New file: `Sources/TextEngineCore/PointQuery.swift`

The `extension ViewportVirtualizer` holding `pointAt(x:y:lineMetrics:columnMetrics:)`
exactly as in Decision 3. No local helpers; it is a two-level `switch` over the two
1D query results.

- **O(log N) + O(log M) queries** (each delegated to a 1D query that may dispatch to
  a provider-native override), **O(1) core memory**, zero allocation beyond the
  returned value structs; Foundation-free; Embedded-safe (only `Int` / `Double` /
  generics over two protocols — the union of `lineAt`'s and `columnAt`'s footprint).

### Types added to `Sources/TextEngineCore/ViewportTypes.swift`

`PointQuery`, `PointLocation`, and `ColumnResolution` (Decision 2), beside the
existing query/location types. **No** change to `ViewportValidationError`
(Decision, Non-Goals).

### No change to the 1D axes

`PositionQuery.swift`, `HorizontalPositionQuery.swift`, `LineMetricsSource.swift`,
`LineHorizontalMetricsSource.swift`, `compute`, the cursors, and every provider are
untouched. Like `lineGeometryAt`-over-`lineAt`, this slice composes existing
gate-covered paths without refactoring any of them — a strictly additive slice.

## Testing Strategy

XCTest only, TDD failing-first. All `PointAt*` tests live in
`Tests/TextEngineCoreTests` and use only core types (`UniformLineMetrics`,
`UniformColumnMetrics`, and small hand-built sources), so the core test target keeps
its `TextEngineCore`-only dependency. `PrefixSumColumnMetrics` /
`PrefixSumLineMetrics` are reference-provider types; a composition test driving the
reference providers through `pointAt` lives in
`Tests/TextEngineReferenceProvidersTests` (which imports both products), never in
the core test target.

### Composition-parity oracle (load-bearing)

The oracle asserts that `pointAt` **is** the composition of the two 1D queries, over
a grid of `(x, y)` values chosen to hit every branch:

For each `(x, y)` in the grid, with `V = lineAt(y:lineMetrics)`:

- If `V == .failure(e)` → `pointAt == .failure(e)` **and** `columnAt` was not the
  source of the error (verified structurally: the error equals the vertical one).
- If `V == .empty` → `pointAt == .empty`.
- If `V == .line(L)` → let `H = columnAt(x:inLine: L.lineIndex, columnMetrics)`;
  then `pointAt == .point(PointLocation(line: L, column: resolution(H)))` where
  `resolution(.column(C)) == .cell(C)`, `resolution(.empty) == .blankLine`, and
  `H == .failure(e) → pointAt == .failure(e)`.

The grid spans: `y` below 0, at 0, mid-document, at exact line boundaries, at/above
total height, **plus non-finite (`NaN`, `±inf`)**; crossed with `x` below 0, at 0,
mid-cell, at exact cell boundaries, at/above line width, **plus non-finite** — over
both uniform sources and hand-built non-uniform sources, including a document
containing at least one blank line **and an empty-document source**. Non-finite
coordinates crossed with the empty-document and blank-line sources are what lock in
the "validation precedes the zero-count short-circuit" ordering (Decision 4): the
expected value is *defined* as the 1D composition, so the oracle derives
`.failure(.nonFiniteValue)` for those cells automatically rather than `.empty` /
`.blankLine`. Because the expected value is defined as the 1D composition, this
oracle proves parity directly and will catch any divergence in ordering, clamp
propagation, or blank-line handling.

### Unit tests (`PointAtTests`)

One test per Decision 4 row plus the clamp/precedence cases:

- **Empty document** (`lineCount == 0`) → `.empty`, for any **finite** `(x, y)`
  (including out-of-range extremes on both axes). A non-finite `y` short-circuits to
  `.failure(.nonFiniteValue)` even on an empty document (validation precedes the
  empty short-circuit) — covered by a dedicated case.
- **In-range cell hit** → `.point(line: L(.inRange), column: .cell(C(.inRange)))`
  with the correct `lineIndex` and `columnIndex`.
- **Blank located line** (in-range `y` selecting a line whose `columnCount == 0`) →
  `.point(line: L, column: .blankLine)`, for any **finite** `x` (negative, zero,
  positive). A non-finite `x` on that same blank line short-circuits to
  `.failure(.nonFiniteValue)` (validation precedes the blank-line short-circuit) —
  covered by a dedicated case.
- **Vertical clamp only**: `y < 0` / `y >= totalHeight` over a non-blank line →
  `line.clamp` is `.clampedToTop` / `.clampedToBottom`, cell still resolved
  `.inRange` (or clamped per `x`).
- **Horizontal clamp only**: `x < 0` / `x >= lineWidth` on an in-range line →
  cell `clamp` `.clampedToLeft` / `.clampedToRight`, `line.clamp` `.inRange`.
- **Both-axes-clamped**: `y < 0` and `x < 0` → `line.clamp == .clampedToTop` **and**
  cell `clamp == .clampedToLeft`, both preserved.
- **Vertical failure short-circuits**: a vertical source with `lineCount < 0`
  (`.negativeLineCount`), non-finite `y` (`.nonFiniteValue`), or
  `offset(ofLine: 0) != 0` (`.invalidLineMetrics`) → `.failure(...)`, and the
  horizontal source is **not consulted** (proven with a counting/trap horizontal
  source whose methods must not be called; see below).
- **Horizontal failure surfaces**: a valid vertical source but a horizontal source
  that is `.negativeColumnCount`, non-finite `x` (`.nonFiniteValue`), or
  `.invalidColumnMetrics` for the located line → `.failure(...)`.
- **Failure precedence**: a source pair where *both* axes would fail (e.g.
  `lineCount < 0` **and** `columnCount < 0`) → the **vertical** error is surfaced,
  and the horizontal source is not consulted.

### Dispatch / non-consultation test (`PointAtDispatchTests`)

A `TrapColumnMetrics` whose `columnCount` / `columnOffset` / `columnIndex` record
into an ordered event log (or fail the test if called) proves that on the vertical
`.failure` and `.empty` paths the horizontal source is **never** touched, and that
on the `.line` path the horizontal source is consulted **exactly once** with the
`inLine` equal to the vertically-located `lineIndex`. This mirrors the ordered
event-log discipline in `ColumnAtQueryCountTests` / `LineAtQueryCountTests`,
asserting order and `inLine` threading, not merely a boolean "was it called".

### No behavior-preservation burden

This slice adds only new files/types; it changes no existing algorithm and adds no
enum case. The existing full suite (vertical + horizontal oracles, query-count,
`compute`, cursors, all providers) must pass **unchanged in count and result** — its
only expected delta is the new `PointAt*` tests. No existing gate checksum changes.

## Benchmark Mode (`ViewportBenchmarks`)

New file `Sources/ViewportBenchmarks/PointQueryBenchmark.swift`, modeled on
`ColumnQueryBenchmark.swift`:

- **Mode**: add `.pointQuery` to `BenchmarkMode` (`outputName = "point_query"`),
  `--point-query` to `BenchmarkOptions.parse` / usage, a `.pointQuery` arm in
  `BenchmarkProgram.runBenchmarks`, and a `.pointQuery` arm wherever the synthetic
  switch matches the other query modes (`SyntheticBenchmarks.swift`).
- **Scenarios**: pair a `LineMetricsSource` with a `LineHorizontalMetricsSource` at
  increasing sizes — proposed `uniform_100k` (`UniformLineMetrics` ×
  `UniformColumnMetrics`), `uniform_1m`, and a variable pairing
  `prefixsum_100k` / `prefixsum_1m` (`PrefixSumLineMetrics` ×
  `PrefixSumColumnMetrics`, deterministic varied heights/advances) — each with
  `p95`/`p99` budgets. Large line/cell counts exist only to exercise combined
  search depth. These pairings cover the O(1) native-arithmetic vertical path
  (`UniformLineMetrics`) and the generic O(log N) binary-search fallback
  (`PrefixSumLineMetrics`); the balanced-tree native-descent path
  (`BalancedTreeLineMetrics`) is **deliberately not** re-measured here because the
  point gate's unique job is composition overhead, and that path is already guarded
  by `--line-query`. Because the composite's cost is the *sum* of the two 1D queries, the
  budgets are set with headroom over the observed combined latency (roughly the sum
  of the corresponding `--line-query` and `--column-query` scenarios), following the
  project's customary margin.
- **Workload**: per operation, derive a deterministic `(x, y)` spanning in-range and
  out-of-range values on both axes (reusing `deterministicScrollOffset` and a
  deterministic fraction of the line width, with a slice of samples pushed
  below `0` and at/above the edges to exercise both clamp branches and at least one
  blank line), call `pointAt(x:y:lineMetrics:columnMetrics:)`, and fold the returned
  `line.lineIndex`, an integer encoding of the two clamp cases, and the column
  resolution (`cell` index or a `blankLine` sentinel) into a running **checksum**
  (determinism guard, matching every other benchmark).
- **Gate**: `--point-query --gate` enforces `p95`/`p99` budgets and exits non-zero
  on regression; without `--gate` it asserts `failureCount == 0`. Budgets are
  macOS-calibrated; the plan records the observed numbers and sets budgets with the
  project's customary headroom.

`--gate` validity extends to `.pointQuery` automatically (Decision 6 — the parser
denylist needs no change).

## CI

**No `.github/workflows/swift-ci.yml` change.** The `--point-query --gate` is a
local gate this slice (Decision 6). The required job contexts, docs-only path,
iOS/WASM jobs, and the `Main` ruleset are all unchanged. CI promotion is the
recommended follow-up slice (Future Slices).

## Verification

Recorded in `docs/superpowers/verification/2026-07-10-point-query.md`:

- `swift test` — host unit tests (new `PointAt*` oracle + unit + dispatch tests
  green; existing suite unchanged count + 0 failures).
- `swift build -c release`.
- `swift run -c release ViewportBenchmarks -- --point-query --gate` → every scenario
  `gate=pass`; record p95/p99 and checksums.
- Existing gates still green and **checksum-identical** (this slice touches no
  existing algorithm, so all must be byte-identical): `--gate`,
  `--variable-height --gate`, `--variable-height-mutation --gate`,
  `--structural-mutation --gate`, `--bulk-structural-mutation --gate`,
  `--line-query --gate`, `--line-geometry-query --gate`, `--column-query --gate`,
  `--column-geometry-query --gate`.
- `--memory-shape` invariant `pass` (the query is O(1) memory).
- Foundation-free scans: `rg -n "Foundation" Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders` → empty (exit 1).
- `./.github/scripts/cross-target-compile.sh --self-test`, then the iOS (blocking)
  and WASM (observational) cross-target paths for both `TextEngineCore` and
  `TextEngineReferenceProviders`.
- Hosted PR run + post-merge push run IDs, verified at **step level**, recorded in
  the post-merge follow-up (per the standing stale-on-write lesson: record the
  PR-head proof against the stable final head in the post-merge doc, never against a
  pre-final commit).

## Acceptance Criteria

1. `ViewportVirtualizer.pointAt(x:y:lineMetrics:columnMetrics:) -> PointQuery` is
   public, stateless, and behaves exactly per the Decision 4 table.
2. The composition-parity oracle passes: for every `(x, y)` in the grid, `pointAt`
   equals `(lineAt(y), columnAt(x, locatedLine))` composed per Decision 4 — over
   uniform and non-uniform sources, including a document with a blank line.
3. All listed unit tests pass: every Decision 4 row, vertical-clamp-only,
   horizontal-clamp-only, both-axes-clamped, vertical-failure-short-circuit,
   horizontal-failure, and failure-precedence.
4. The dispatch test proves the horizontal source is **not consulted** on the
   vertical `.failure` / `.empty` paths and is consulted **exactly once** with
   `inLine == locatedLineIndex` on the `.line` path, via an ordered event log.
5. The slice is strictly additive: the entire existing suite passes unchanged in
   count and result, all nine existing gates pass with identical checksums, and
   `ViewportValidationError` is unchanged (no case added).
6. `--point-query` benchmark runs (uniform **and** prefix-sum pairings);
   `--point-query --gate` enforces budgets and joins the gateable set (never
   rejected), while `--gate` stays rejected with
   `--range-only`/`--memory-shape`/`--memory-observation`.
7. Foundation-free scans empty; `--memory-shape` invariant `pass`; iOS (blocking)
   and WASM (observational) cross-target compile unchanged.
8. Full paper trail (spec, plan, verification, post-slice review) on a
   `slice-37-point-query` branch; one PR; conventional commits.

## Risks And Gaps

### Result carries no geometry (deferred richness)

A caller doing tap-to-caret wants each axis's box (`y`/height, `x`/width) and the
fractional offsets, to place and snap the caret. This slice returns only indices +
clamps; such a caller makes extra `offset(ofLine:)` / `columnOffset(inLine:column:)`
queries, or waits for the geometry-bearing `pointGeometryAt` companion (Future
Slices). Chosen now for minimal surface and to mirror the position-first-then-geometry
cadence both axes already followed.

### `inLine` correctness rests on `lineAt`, not re-validated

`pointAt` feeds `columnAt` the `lineIndex` from `lineAt`, which is always in
`0..<lineCount` on the `.line` path — so the `inLine` precondition holds by
construction *for the vertical source's line domain*. The horizontal source is
trusted to define cells for that line index (Slice 33 Decision 5: `inLine` is a
documented precondition, and the horizontal source carries no `lineCount`). A caller
pairing a vertical source of `N` lines with a horizontal source that only defines
cells for fewer lines is a contract violation the core cannot detect — the same
contract-trusting posture both 1D queries already take.

### Benchmark budgets are macOS-calibrated and local-only

Like every gate before CI promotion, the `--point-query` budgets are macOS-derived
and unenforced in hosted CI until a promotion slice. A regression in `pointAt` (or,
transitively, in either 1D query as seen through the composite) would be caught
locally but not block merge until promotion. This matches the established rhythm and
is an accepted, time-boxed gap.

### The composite re-measures paths the 1D gates already cover

`--point-query` exercises `lineAt` and `columnAt` again, so a regression in either
1D primitive could surface here as well as in its own gate. This is redundancy, not
a gap — the composite gate's *unique* job is guarding the composition overhead (the
ordering, the result assembly, the blank-line branch), which no 1D gate covers. The
redundancy is cheap and consistent with how `lineGeometryAt` / `columnGeometryAt`
gates also re-measure their base query.

## Future Slices

- **Geometry-bearing `pointGeometryAt(x:y:)` (recommended next)**: compose
  `lineGeometryAt` ∘ `columnGeometryAt` (or `pointAt` plus O(1) box probes) into a
  2D result carrying each axis's box + fraction + clamp — the primitive a
  click-to-caret / caret-snapping consumer ultimately wants. New method/result type,
  never by appending a case to `PointQuery`.
- **Promote `--point-query --gate` to a blocking hosted CI gate**, completing the
  functional → promotion pair (the tenth blocking latency gate), exactly as
  Slices 28 / 32 / 34 / 36 did for the prior query modes. May be folded with, or
  sequenced after, the `pointGeometryAt` slice.
- **Provider-native horizontal descent + mutable horizontal provider** (Slice 36
  review Option D): O(1) monospace and balanced-tree `columnIndex` overrides, plus a
  matching benchmark scenario to catch the O(log²M) path — independent of the point
  arc.
- **Linux-native budget re-baseline** (Slice 36 review Option E): retire the
  macOS-calibration caveat using the now ten-gate-deep hosted x86_64 evidence.
- **Wrap-aware visual rows** remain the larger future capability; needs its own
  brainstorm, and interacts with both axes and the 2D composite.
```