# Horizontal Geometry Query (`columnGeometryAt(x:inLine:)`) Design

Slice 35 — return to functional core after the Slice 33→34 horizontal-axis pair
(`columnAt` capability → CI gate). The tight horizontal mirror of Slice 31's
`lineGeometryAt`.

## Status

Proposed. Brainstormed 2026-07-07; recommended by the Slice 34 post-slice review
(Option C — `columnGeometryAt` / caret-x) and selected by the user over the
C-vs-B-vs-D-vs-E product call (deepen the horizontal axis toward caret geometry
rather than take the larger 2D `pointAt` leap, the horizontal native-descent
cleanup, or standing infra). The user further chose the **pure geometry mirror**
shape (box + fraction, caret snapping left to the caller) over baking a caret
snap policy into the core.

## Source Context

The brief (`docs/initial-project-brief.md`) wants a headless
layout/virtualization core that supports realistic editing/scrolling of 100k+
line / >10 MB documents, stays Foundation-free and Embedded-compatible, and keeps
core-owned memory sub-linear in document size.

Slice 33 added the public **x → cell** within-line mapping
`ViewportVirtualizer.columnAt(x:inLine:metrics:) -> ColumnQuery`, returning
`columnIndex` + a `clamp` flag and nothing more. Its own design (Decision 6)
explicitly deferred geometry:

> **Sub-cell position deferred.** The result is `columnIndex` + `clamp` only — no
> cell `x`/width, no `fractionInColumn`, no caret left/right snapping. A caller
> wanting sub-cell position gets it from a future geometry-bearing companion
> (`columnGeometryAt`, the `lineGeometryAt` analog) — added as a **new method /
> result type**.

Slice 34 then completed the horizontal-axis **regression-protection** step:
`--column-query` became the eighth blocking hosted gate — the first for the
horizontal axis. The Slice 34 review found the horizontal axis at the exact point
the vertical axis occupied after Slice 28 (mapping query + gate, no geometry, not
yet asymptotically optimal), and handed off to a genuine product call. This slice
is the rhythm-consistent next capability: surface the geometry that `columnAt`
already locates, exactly as Slice 31 (`lineGeometryAt`) did for `lineAt` after the
Slice 27→28 vertical mapping+gate pair.

This is the tight **27→31 mirror applied to the horizontal axis**: Slice 33
(`columnAt`, mirror of Slice 27 `lineAt`) → Slice 34 (`--column-query` gate,
mirror of Slice 28) → **Slice 35 (`columnGeometryAt`, mirror of Slice 31
`lineGeometryAt`)**.

## Problem

`columnAt` answers *"which cell?"*. The next thing every tap-to-caret / selection
/ hit-test consumer needs is *"which cell, and where within it?"* — the located
cell's horizontal box (left `x`, advance width) and how far the query point falls
into that box (so it can snap the caret to the cell's leading or trailing edge).
Today a caller must:

1. call `columnAt(x:inLine:)` for the index + clamp, then
2. issue its own `columnOffset(inLine:column: i)` / `columnOffset(_, column: i+1)`
   queries to rebuild the cell box, then
3. re-derive the within-cell fraction, re-implementing the clamp/boundary
   conventions the core already owns.

That re-implementation is exactly the duplication Slice 33 set out to remove for
the index. The core should own the geometry-bearing form too, as the authoritative
companion to `columnAt`, with the same validation discipline, the same boundary
and clamp conventions, and the same O(log M) / O(1)-core-memory envelope. This is
also precisely the duplication Slice 31 removed on the vertical axis — this slice
applies the identical treatment horizontally.

## Scope

Add a single public, stateless query to `TextEngineCore`:

> Given a target `x`, a line index `inLine`, and a `LineHorizontalMetricsSource`,
> return the located cell's **box** (index, left `x`, advance width) **plus** the
> within-cell fraction of `x`, with the same clamp flag `columnAt` returns.

Plus its equivalence-oracle and unit tests, a `--column-geometry-query` benchmark
mode with a **local** `--gate`, and the slice paper trail. No rendering, no
vertical composition (`pointAt`), no caret-snap policy, no wrap, no provider change,
no change to `columnAt`.

## Goals

- Public `ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:) -> ColumnGeometryQuery`
  over the general `LineHorizontalMetricsSource` path, the geometry-bearing
  companion to `columnAt(x:inLine:metrics:)`.
- **Index + clamp parity with `columnAt` by construction** — `columnGeometryAt`
  delegates to `columnAt` for the located cell and clamp, so the two can never
  drift on boundary/clamp conventions.
- **O(log M) provider calls, O(1) core memory.** `columnGeometryAt` adds only a
  *constant* number of `columnOffset(inLine:column:)` probes (the box left/right)
  on top of `columnAt`'s index search — no new search, no provider protocol change
  — so it never adds a log factor and its per-provider wall-clock **equals
  `columnAt`'s**. See Decision 4 for the full per-provider breakdown.
- Validation parity with `columnAt`: up-front, return-based (no `throws`),
  Foundation-free, reusing the existing `ViewportValidationError`.
- An **equivalence oracle**: over `PrefixSumColumnMetrics`, `columnGeometryAt`'s
  index/clamp equal `columnAt`'s and its `geometry`/`fractionInColumn` equal the
  values rebuilt from the provider's own `columnOffset(inLine:column:)` across an
  `x` sweep — the same "provably matches the offset-derived expectation" discipline
  the project uses for `compute`, `lineAt`, `lineGeometryAt`, and `columnAt`. Plus a
  **structural uniform oracle** (products, not quotients) over `UniformColumnMetrics`
  for boundary-exact `x`.
- A `--column-geometry-query` benchmark mode + local `--gate` with macOS-calibrated
  budgets, following the established functional-slice rhythm.
- Foundation-free, Embedded-compatible, zero-dependency; iOS/WASM cross-target
  compile unchanged.

## Non-Goals

- **No 2D composition / point query.** No `pointAt(x:y:)` combining the vertical
  (`lineGeometryAt`) and horizontal (`columnGeometryAt`) mapping primitives. That is
  the larger Option B leap and needs its own brainstorm (how two independent metrics
  sources compose). This slice is strictly the horizontal geometry.
- **No caret-snap policy in the core.** The result stops at the cell box +
  within-cell fraction. Mapping the fraction to a snapped caret column/`x` (a
  `< 0.5` threshold, RTL/affinity handling) is the caller's job — exactly as the
  vertical `lineGeometryAt` leaves it. This was the user's explicit choice over an
  in-core snapped caret field.
- **No wrap / visual rows.** The unit stays the cell (caret-stop granularity) in
  visual left-to-right order, as Slice 33 defined it.
- **No provider-native richer descent.** `columnGeometryAt` composes over the
  existing `columnAt` + `columnOffset(inLine:column:)` primitives; it adds **no**
  new `LineHorizontalMetricsSource` requirement. A native one-walk
  `(index, left, right)` descent, and closed-form/native `columnIndex` overrides for
  the shipped providers (the horizontal Option D), are deferred optimizations
  (Future Slices), mirroring the Slice 31 (capability) → later-native split for
  `lineGeometryAt`.
- **No change to `columnAt`, the provider protocol, or `ColumnQuery`.** The
  geometry-bearing form is **additive** — a new method and new result types. It is
  **not** a new case on the existing `ColumnQuery` enum (source-breaking for client
  `switch`es; the same non-breaking-extension rule Slice 27/31/33 set).
- **No `lineCount` / multi-line entry point.** `inLine` stays a documented
  precondition (the source carries no `lineCount`), exactly as `columnAt`.
- **No CI promotion.** The `--column-geometry-query --gate` runs locally only this
  slice; promoting it to a blocking hosted gate is a separate follow-up slice
  (the ninth blocking gate), exactly as `--line-geometry-query` → Slice 32 and
  `--column-query` → Slice 34.

## Decisions

### Decision 1 — Result shape: `ColumnGeometry` / `ColumnGeometryQuery` / `ColumnGeometryLocation`

Three new public types, the exact horizontal mirror of the `LineGeometry*` trio.
Unlike the vertical case — which *reused* the pre-existing `LineGeometry` (already
streamed by the geometry cursor) — there is **no** existing horizontal cell-box
type, so this slice introduces `ColumnGeometry`. It carries the `ColumnLocation.Clamp`
flag by reuse (no new clamp enum).

```swift
public struct ColumnGeometry: Equatable {
    public let columnIndex: Int
    public let x: Double        // cell left edge (columnOffset of columnIndex)
    public let width: Double    // advance width (columnOffset(i+1) - columnOffset(i))

    public init(columnIndex: Int, x: Double, width: Double) { ... }
}

public enum ColumnGeometryQuery: Equatable {
    case geometry(ColumnGeometryLocation) // a real cell was located, with its box
    case empty                            // blank line: columnCount(inLine:) == 0
    case failure(ViewportValidationError) // invalid input / metrics
}

public struct ColumnGeometryLocation: Equatable {
    /// The located cell's box: columnIndex, left x, advance width.
    public let geometry: ColumnGeometry
    /// Where `x` falls within the cell's horizontal span. `0.0` at the cell left
    /// edge; `(x - geometry.x) / geometry.width` in `[0, 1)` for an in-range query;
    /// `0.0` when clamped to left; `1.0` when clamped to right. See Decision 3.
    public let fractionInColumn: Double
    /// Whether the query landed inside the line or past an edge — the same flag
    /// `columnAt` returns (reused, not duplicated).
    public let clamp: ColumnLocation.Clamp

    public init(geometry: ColumnGeometry, fractionInColumn: Double, clamp: ColumnLocation.Clamp) { ... }
}
```

Rationale:

- The new surface is **three new public types** (`ColumnGeometry`,
  `ColumnGeometryQuery`, `ColumnGeometryLocation`). `ColumnGeometry` mirrors
  `LineGeometry{lineIndex, y, height}` field-for-field (`x`↔`y`, `width`↔`height`),
  and the clamp flag reuses `ColumnLocation.Clamp` — so the geometry-bearing query
  and `columnAt` speak one vocabulary for "a cell's box" and "edge clamp state".
- The **`.empty` / `.failure` cases parallel `ColumnQuery`** exactly, so the two
  query results are switched the same way and validation outcomes map 1:1.
- `fractionInColumn` is a **convenience the core defines centrally** rather than
  leaving every caller to recompute `(x - left) / width` and re-decide what it means
  at the clamped edges. Centralizing it is the point: the clamp-edge fraction
  contract (Decision 3) lives in one place — from which a caller derives the snapped
  caret (`caretColumn = fraction < 0.5 ? columnIndex : columnIndex + 1`,
  `caretX = fraction < 0.5 ? geometry.x : geometry.x + geometry.width`) under its own
  affinity policy.

### Decision 2 — One metrics-based entry point, composed over `columnAt`

`columnGeometryAt` is a single generic over `LineHorizontalMetricsSource`,
alongside `columnAt`:

```swift
extension ViewportVirtualizer {
    public static func columnGeometryAt<Metrics: LineHorizontalMetricsSource>(
        x: Double, inLine line: Int, metrics: Metrics
    ) -> ColumnGeometryQuery
}
```

`inLine` stays a documented precondition (parity with `columnAt`; the source has no
`lineCount`).

The implementation **delegates to `columnAt(x:inLine:metrics:)`** for validation,
the located index, and the clamp flag, then attaches geometry only on the `.column`
branch:

```
columnGeometryAt(x, line, metrics):
    switch columnAt(x, line, metrics):
        case .failure(e): return .failure(e)         // validation single-sourced
        case .empty:      return .empty               // blank line, no geometry
        case .column(loc):
            left  = metrics.columnOffset(inLine: line, column: loc.columnIndex)
            right = metrics.columnOffset(inLine: line, column: loc.columnIndex + 1)
            box   = ColumnGeometry(columnIndex: loc.columnIndex, x: left, width: right - left)
            frac  = fraction(x, box, loc.clamp)       // Decision 3
            return .geometry(ColumnGeometryLocation(geometry: box,
                                                    fractionInColumn: frac,
                                                    clamp: loc.clamp))
```

Rationale — composing over `columnAt` rather than re-deriving:

- **Parity by construction.** Index, clamp, and the entire validation ladder
  (`negativeColumnCount`, `nonFiniteValue`, the `columnOffset(_, 0) != 0` and
  width-`<= 0`/non-finite `invalidColumnMetrics` probes) come straight from
  `columnAt`; `columnGeometryAt` cannot disagree with `columnAt` on which cell /
  which clamp. The equivalence oracle then only has to pin the *geometry*.
- **No new search, no provider change.** The located index already came from the
  (default binary-search, provider-overridable) `columnIndex(containingOffset:inLine:)`
  inside `columnAt`. The two extra `columnOffset` probes for `left`/`right` reuse the
  existing offset contract.
- The two extra `columnOffset` probes are accepted (Decision 4) rather than threaded
  out of the search: a native one-walk `(index, left, right)` descent is a deferred
  optimization, not this slice.

### Decision 3 — Within-cell fraction + clamp contract

Cells occupy half-open horizontal spans `[columnOffset(i), columnOffset(i+1))` (the
convention `columnAt` already uses). `columnGeometryAt` reports, for the located
cell's box `(left, width)`:

| `x` | `clamp` (from `columnAt`) | `geometry` | `fractionInColumn` |
| --- | --- | --- | --- |
| `x < 0` | `clampedToLeft` | cell 0's box | `0.0` |
| `0 <= x < lineWidth` | `inRange` | located cell's box | `(x - left) / width`, in `[0, 1)` |
| `x >= lineWidth` | `clampedToRight` | last cell's box | `1.0` |
| `columnCount == 0` | — | — | (result is `.empty`) |

Notes:

- The **in-range fraction is the exact arithmetic ratio** `(x - left) / width`, not
  artificially clamped, so `x == left + fractionInColumn * width` holds for in-range
  queries (modulo floating-point). It is in `[0, 1)` by the half-open contract
  (`left <= x < right`); at an exact cell left edge `x == left` it is `0.0`. (At `x`
  extremely close to `right`, floating-point may round the ratio up toward `1.0`; the
  core does not special-case this, consistent with how the rest of the engine trusts
  the `columnOffset` contract.)
- The **clamp edges report sentinel fractions** `0.0` (left) and `1.0` (right) rather
  than an out-of-box ratio: a tap left of the line caret-positions at the very left of
  cell 0, a tap past the line's right edge at the very right of the last cell. `1.0` is
  the only way `fractionInColumn` reaches `1.0` — it never does for `inRange`.
- `geometry.width = right - left` is finite and strictly positive by the
  `LineHorizontalMetricsSource` contract (`columnOffset` is a strictly increasing
  chain over the `0..<columnCount` cells). No zero-width special case is needed for a
  valid provider.

This is the exact mirror of the vertical Decision 3 (`lineGeometryAt`), with
`x`/`left`/`width`/`lineWidth`/left-right substituted for `y`/`top`/`height`/
`totalHeight`/top-bottom.

### Decision 4 — Cost: O(log M) queries, O(1) core memory; two extra columnOffset probes accepted

`columnGeometryAt` issues `columnAt`'s `columnOffset(inLine:column:)` queries plus
**two** more (`columnOffset(_, i)`, `columnOffset(_, i+1)`) on the located branch.
Per path (over `M = columnCount(inLine: line)`):

| `columnGeometryAt` path | `columnOffset` count |
| --- | --- |
| **non-finite `x`** | `0` — `columnAt` fails before any offset probe; no geometry |
| **empty** (`columnCount == 0`) | `1` — `columnAt`'s `columnOffset(_, 0)` contract probe, then `.empty`; no geometry |
| **clamp** (`x < 0` or `x >= lineWidth`) | `4` — `columnAt`'s `columnOffset(_, 0)` + width `= 2`, plus the two geometry probes |
| **in-range**, 1M cells | `columnAt`'s `2 + (ceilLog2(M) + 1)` + `2` geometry probes; and `< 100` |

So the query count stays **`O(log M)`** (a constant number of `columnOffset` probes
plus `columnAt`'s single index search) and core memory stays **`O(1)`**. Wall-clock
is `O(log M x offsetCost)`. `columnGeometryAt`'s two extra probes are a **constant
factor**, so its per-provider asymptotic class is exactly `columnAt`'s — the geometry
probes never introduce a log factor.

Per shipped provider — and here the horizontal story is **simpler than the vertical
one**: unlike the vertical axis (`BalancedTreeLineMetrics` with a Slice 29 native
O(log N) descent, plus `FenwickLineMetrics` at O(log²N)), **both** shipped horizontal
providers answer `columnOffset` in **O(1)** and use the **generic** O(log M)
`columnIndex` binary search — so there is no native-descent case and no O(log²)
case to enumerate:

- `UniformColumnMetrics` (core) answers `columnOffset` in O(1) and runs `columnAt`'s
  index search as an O(log M) binary search over O(1) probes → **O(log M)**.
- `PrefixSumColumnMetrics` (reference) answers `columnOffset` in O(1) (array read)
  and likewise uses the generic O(log M) `columnIndex` → **O(log M)**.

A native/closed-form `columnIndex` override (the horizontal Option D, Future Slices)
would take the uniform case to O(1) and a native prefix-search to a single descent;
a native one-walk `(index, left, right)` geometry hook would cut the constant probe
count. Neither is this slice.

### Decision 5 — Local gate now, CI promotion deferred (established rhythm)

This functional slice ships the `--column-geometry-query` benchmark mode **and**
local `--gate` enforcement with macOS-calibrated budgets, but does **not** wire the
gate into `.github/workflows/swift-ci.yml`. Promotion to a blocking hosted gate (the
ninth) is a separate follow-up slice, identical to the project's seven prior
functional → promotion pairs (variable-height → 15, variable-height-mutation → 21,
structural-mutation → 24, bulk-structural-mutation → 26, line-query → 28,
line-geometry-query → 32, column-query → 34).

`--gate` becomes valid with `--column-geometry-query` (added to the gateable set
alongside the pipeline, realistic-provider, variable-height,
variable-height-mutation, structural-mutation, bulk-structural-mutation, line-query,
line-geometry-query, and column-query modes); it remains rejected with
`--range-only`, `--memory-shape`, and `--memory-observation`. Only one mode flag at a
time.

`AGENTS.md` gains the new local command and the `--column-geometry-query` flag; its
CI section is unchanged because the workflow is unchanged. Following the Slice 33
precedent for `columnAt`/`--column-query`, the architecture paragraph describes the
`--column-geometry-query` gate as **local (not-yet-CI)**.

## Component Design

### Extend `Sources/TextEngineCore/HorizontalPositionQuery.swift`

Add `columnGeometryAt(x:inLine:metrics:)` to the existing `extension
ViewportVirtualizer` that already holds `columnAt`, plus a tiny private fraction
helper. It:

1. Calls `columnAt(x:inLine:metrics:)` and switches on the result.
2. Maps `.failure(e)` and `.empty` straight through (validation never duplicated).
3. On `.column(loc)`, reads `left`/`right` via `columnOffset(inLine:column:)`, builds
   the `ColumnGeometry` box, computes `fractionInColumn` per the Decision 3 clamp
   branch, and returns `.geometry(...)`.

Keeping it in `HorizontalPositionQuery.swift` next to `columnAt` keeps the two
x→cell queries co-located (mirror of the vertical pair co-located in
`PositionQuery.swift`).

### Types added to `Sources/TextEngineCore/ViewportTypes.swift`

`ColumnGeometry`, `ColumnGeometryQuery`, and `ColumnGeometryLocation` (Decision 1),
alongside the existing `ColumnQuery` / `ColumnLocation` and the `LineGeometry*`
definitions, so the public vocabulary stays in one file. No change to existing types.

### No search change; provider code untouched (one doc-comment update)

The `TextEngineReferenceProviders` providers (`PrefixSumColumnMetrics`) and the core
`UniformColumnMetrics` are untouched — no signature or behavior change.
`columnGeometryAt` only consumes the existing `columnAt` + `columnOffset(inLine:column:)`
surface and adds **no** `LineHorizontalMetricsSource` requirement. The single
provider-protocol touch is a **doc-comment** update to the `columnOffset` stability
precondition — see Documentation Updates.

## Documentation Updates

- **`Sources/TextEngineCore/LineHorizontalMetricsSource.swift` stability
  precondition.** The `columnOffset(inLine:column:)` stability precondition currently
  scopes its "stable for one `columnAt` query" guarantee to `columnAt`.
  `columnGeometryAt` issues several `columnOffset` queries (via `columnAt` plus the two
  geometry probes) that must observe one consistent snapshot. Broaden the wording to
  "stable for one `columnAt` / `columnGeometryAt` query". Comment only; no signature or
  behavior change. (Slice 31 made the identical `offset(ofLine:)` update when it added
  `lineGeometryAt`.)
- **`AGENTS.md`.** Add `columnGeometryAt` to the architecture paragraph as the
  geometry-bearing companion to `columnAt` — the x→(cell index + box + within-cell
  fraction) query, the horizontal `lineGeometryAt` mirror, composed over `columnAt`
  plus two `columnOffset` probes, O(1) core memory — and add the
  `--column-geometry-query` / `--column-geometry-query --gate` commands and flag to the
  Commands and benchmark-flags lists, described as the **local (not-yet-CI)** gate. The
  CI section is unchanged (no workflow change, Decision 5).

## Testing Strategy

XCTest only, TDD failing-first. Split by the providers each test needs (the Slice 30
placement lesson: a test that needs reference providers lives in the
reference-provider test target). Mirror the `LineGeometryAt*` test files.

### Core tests (`Tests/TextEngineCoreTests/ColumnGeometryAtTests.swift`, `ColumnGeometryAtQueryCountTests.swift`)

**Structural uniform oracle (load-bearing, products not quotients).** Mirrors the
`ColumnAtEquivalenceTests` uniform oracle to dodge `floor(x/columnWidth)` boundary
fragility: pick `columnWidth` from the exactly-representable set
(e.g. `[1.0, 10.0, 16.0, 12.5, 256.0]`), `columnCount` well under `2^53`, **build
each `x` from a product**, and assert the full `ColumnGeometryQuery` over
`UniformColumnMetrics`:

| Constructed `x` | Expected result |
| --- | --- |
| `-columnWidth` | `.geometry(box=(0, 0, w), frac=0.0, clampedToLeft)` |
| `Double(k) * w` for `k in {0, 1, count/2, count-1}` | `.geometry(box=(k, k*w, w), frac=0.0, inRange)` |
| `Double(k) * w + w/2` for `k < count` | `.geometry(box=(k, k*w, w), frac=0.5, inRange)` |
| `Double(count) * w` (lineWidth) | `.geometry(box=(count-1, (count-1)*w, w), frac=1.0, clampedToRight)` |
| `Double(count) * w + w` | `.geometry(box=(count-1, (count-1)*w, w), frac=1.0, clampedToRight)` |

Run for several `(columnCount, columnWidth)` including `columnCount == 1`. Because
every `x` is a product over a representable width, box `x`/`width` and the fraction
are known by construction.

**Parity with `columnAt`.** For a swept set of `x`, assert
`columnGeometryAt(...).columnIndex == columnAt(...).columnIndex` and the clamp flags
match — the construction guarantee, pinned as a regression test.

**Unit / edge tests:**

- **Blank line** (`columnCount == 0`) → `.empty` for any `x`.
- **Failure ladder** (reached via `columnAt`): `negativeColumnCount`; non-finite `x`
  (`.nan`, `+/-inf`) → `nonFiniteValue`; a provider with `columnOffset(_, 0) != 0` →
  `invalidColumnMetrics`; a provider with lineWidth `0`/non-finite →
  `invalidColumnMetrics`. (The line/viewport-specific `ViewportValidationError` cases
  remain unreachable, as for `columnAt`.)
- **Fraction at exact cell left edge** `x == columnOffset(i)` → `frac == 0.0`,
  `inRange`, box left `== columnOffset(i)`.
- **Fraction mid-cell** → `frac == 0.5` for an `x` at the span midpoint.
- **Clamp fractions**: `x < 0` → `0.0` + cell 0 box; `x >= lineWidth` → `1.0` + last
  cell box; `x == 0` → `inRange`, `frac 0.0`; `x == lineWidth` → `clampedToRight`,
  `frac 1.0`.
- **Single-cell line**: in-range `x` → cell 0 box, fraction in `[0,1)`; clamps as
  above.
- **Variable-advance cells** (a small explicit `PrefixSumColumnMetrics` or an inline
  test provider with unequal advances): a mid-cell `x` yields the right non-uniform
  box and fraction (guards against a uniform-only implementation shortcut).

**Query-count tests** (`CountingColumnMetrics`, the existing harness in
`ColumnAtQueryCountTests`): assert the exact `columnOffset` counts per path from the
Decision 4 table — non-finite `0`, blank `1`, clamp `4`,
in-range `<= 2 + (ceilLog2(M)+1) + 2` and `< 100`. Proves the O(log M) query / O(1)
memory envelope and that no accidental linear scan crept in. (Over
`CountingColumnMetrics`, whose `columnIndex` falls back to the binary search, the
in-range count includes the `ceilLog2(M)+1` fallback probes.)

**Native-hook dispatch + order test** (`NativeSearchColumnMetrics`, the existing
ordered event-log harness behind
`testInRangeDispatchesToNativeHookAfterValidationProbes`,
`ColumnAtQueryCountTests.swift:111`). Proves `columnGeometryAt` reuses `columnAt`'s
index dispatch and then takes exactly the two geometry probes, in order. Reuse that
test's exact `NativeSearchColumnMetrics` fixture, whose in-range `columnAt` records
`[.offset(0,0), .offset(0,4), .native(0,31.0)]` (`x = 31` → cell 2), and assert the
`columnGeometryAt` event log extends it to `[.offset(0,0), .offset(0,4),
.native(0,31.0), .offset(0,2), .offset(0,3)]` — i.e. `columnAt`'s `columnOffset(_,0)`
+ width probes, its index
search dispatch, then `columnOffset(_,i)` / `columnOffset(_,i+1)` for the box. This is
the load-bearing proof (the Slice 29 lesson) that the composed query does **not**
silently fall back to a redundant re-search — and it directly exhibits the Decision 4
constant-descent-count shape.

### Reference-provider equivalence oracle (`Tests/TextEngineReferenceProvidersTests/ColumnGeometryAtEquivalenceTests.swift`)

Mirrors the `columnAt` reference equivalence and the vertical
`LineGeometryAtEquivalenceTests`. Build the same advances into a
`PrefixSumColumnMetrics`; across an `x` sweep (left, right, interior, exact cell
edges, fractional offsets, out-of-range left/right) assert:

- `columnGeometryAt(...).clamp == columnAt(...).clamp` and the indices match;
- `geometry == ColumnGeometry(i, provider.columnOffset(_, i), provider.columnOffset(_, i+1) - provider.columnOffset(_, i))`;
- `fractionInColumn` equals the value recomputed from the provider's offsets under the
  Decision 3 contract (exact `0.0`/`1.0` at the clamp edges).

This is the provider-level proof that the composed geometry is byte-consistent with
`columnOffset`.

### No behavior change to existing code

`columnGeometryAt` adds code; it changes none. The existing `columnAt`, `lineAt`,
`lineGeometryAt`, `compute`, and all mutation/query suites and gates must pass
**unchanged** (no checksum movement) — this slice touches no shared search or
provider path, so that is expected, not a refactor-preservation obligation.

## Benchmark Mode (`ViewportBenchmarks`)

New file `Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift`, modeled on
`ColumnQueryBenchmark.swift` (itself the `LineGeometryQueryBenchmark.swift` sibling):

- **Mode**: add `.columnGeometryQuery` to `BenchmarkMode`
  (`outputName = "column_geometry_query"`), `--column-geometry-query` to
  `BenchmarkOptions.parse`/usage, a `runColumnGeometryQueryBenchmarks` arm in the
  program, and `.columnGeometryQuery` to the `--gate`-valid set.
- **Scenarios**: reuse the `--column-query` scenario shape exactly — `uniform_1k`,
  `uniform_100k`, `uniform_1m` over `UniformColumnMetrics`, and `prefixsum_100k`,
  `prefixsum_1m` over `PrefixSumColumnMetrics` (the realistic proportional-advance
  path, and the **watch scenario** at the largest cell count). Both provider families
  answer `columnOffset` in O(1), so the whole query is the O(log M) generic search
  plus the two constant geometry probes; there is no balanced-tree/Fenwick analog to
  add. Each scenario carries `p95`/`p99` budgets, expected to sit slightly above the
  `--column-query` numbers by the constant cost of two extra O(1) `columnOffset`
  probes.
- **Workload**: per operation derive a deterministic `x` spanning in-range and both
  out-of-range clamp branches (reuse the `--column-query` derivation:
  `deterministicScrollOffset` / a deterministic fraction of `lineWidth`, with a slice
  pushed below `0` and at/above `lineWidth`), call `columnGeometryAt(x:inLine:metrics:)`,
  and fold `geometry.columnIndex`, an integer encoding of the `clamp` case, and a
  quantized `fractionInColumn` (e.g. `Int(fractionInColumn * 1_000_000)`) into a
  running **checksum** (determinism guard, matching every other benchmark).
- **Gate**: `--column-geometry-query --gate` enforces `p95`/`p99` and exits non-zero
  on regression; without `--gate` it asserts `failureCount == 0`. Budgets are
  macOS-calibrated; the plan/verification record observed numbers per scenario (p95,
  p99, headroom) and set budgets with the project's customary headroom, so any future
  Linux re-baseline starts from a recorded per-scenario baseline (Slice 34 lesson 4).

## CI

**No `.github/workflows/swift-ci.yml` change.** The `--column-geometry-query --gate`
is a local gate this slice (Decision 5). Required job contexts, docs-only path,
iOS/WASM jobs, and the `Main` ruleset are unchanged. CI promotion is a recommended
follow-up slice (the ninth blocking gate).

## Verification

Recorded in
`docs/superpowers/verification/2026-07-07-horizontal-geometry-query.md`:

- `swift test` — host unit tests (new oracles + unit + query-count + dispatch tests
  green; existing suite count grows from 189, 0 failures).
- `swift build -c release`.
- `swift run -c release ViewportBenchmarks -- --column-geometry-query --gate` → every
  scenario `gate=pass`; record per-scenario p95/p99, headroom, and checksums.
- Existing gates still green with **no checksum movement** (nothing shared touched):
  `--gate`, `--variable-height --gate`, `--variable-height-mutation --gate`,
  `--structural-mutation --gate`, `--bulk-structural-mutation --gate`,
  `--line-query --gate`, `--line-geometry-query --gate`, `--column-query --gate`.
- `--memory-shape` invariant `pass` (the new query is O(1) memory).
- Foundation-free scans: `rg -n "Foundation" Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders` → empty (exit 1).
- `./.github/scripts/cross-target-compile.sh --self-test`, then iOS (blocking) and
  WASM (observational) cross-target paths for both `TextEngineCore` and
  `TextEngineReferenceProviders` (public-API change → cross-target verify).
- Hosted PR run + post-merge push run IDs, verified at **step level**, recorded in a
  post-merge follow-up (the Slice 26 stale-on-write lesson: anchor the PR-head proof
  against the stable final head in the post-merge doc, leave an explicit `Pending`
  placeholder in the source-bearing PR).

## Acceptance Criteria

1. `ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:) -> ColumnGeometryQuery`
   is public, stateless, and behaves exactly per the Decision 3 table.
2. Index + clamp parity with `columnAt` holds across the swept `x` set (by
   construction, pinned by test).
3. The structural uniform oracle passes: box `x`/`width` and `fractionInColumn` equal
   the product-built expectation across the full `x` sweep over exactly-representable
   widths, for multiple `(columnCount, columnWidth)` including `columnCount == 1`.
4. The reference-provider equivalence oracle passes: over `PrefixSumColumnMetrics`,
   geometry and fraction equal the provider-`columnOffset`-derived values across the
   `x` sweep.
5. All unit / failure / clamp-fraction / variable-advance tests pass; `.empty` and all
   `columnAt`-reachable validation outcomes are covered.
6. The query-count tests pass with the exact per-path `columnOffset` counts in the
   Decision 4 table (non-finite `0`, blank `1`, clamp `4`,
   in-range `<= 2 + (ceilLog2(M)+1) + 2` and `< 100`).
6a. The native-hook dispatch + order test passes: in-range `columnGeometryAt` over
   `NativeSearchColumnMetrics` produces the event log
   `[.offset(0,0), .offset(0,count), .native(0,x), .offset(0,i), .offset(0,i+1)]`,
   proving index dispatch + exactly two ordered geometry probes.
7. `--column-geometry-query` benchmark runs; `--column-geometry-query --gate` enforces
   budgets and is accepted only where the other gateable modes are; `--gate` stays
   rejected with `--range-only`/`--memory-shape`/`--memory-observation`; only one mode
   flag at a time.
8. Existing gates and suites pass unchanged (no checksum movement); `--memory-shape`
   invariant `pass`.
9. Foundation-free scans empty; iOS cross-target compile green (blocking); WASM
   observational.
10. Full paper trail (spec, plan, verification, post-slice review) on a
    `slice-35-horizontal-geometry-query` branch; one PR; conventional commits.

## Risks And Gaps

### Two extra `columnOffset` probes on the located path (constant factor, deferred native hook)

`columnGeometryAt` issues two more `columnOffset` probes than `columnAt`. For both
shipped providers `columnOffset` is O(1), so this is a fixed, tiny constant — the
geometry path stays **O(log M)** wall-clock (it does **not** become O(log²M): the
probes are a fixed count, not a binary search whose every step pays a `columnOffset`).
A future slice can still add a provider-native one-walk `(index, left, right)` hook
(default = the composed form), and the horizontal Option D closed-form/native
`columnIndex` overrides would take the uniform case's *search* to O(1) — both
constant/asymptotic wins made measurable by the `uniform_*` / `prefixsum_*` benchmark
scenarios. Out of scope here (Non-Goals).

### Budgets are macOS-calibrated and local-only

Like every gate before CI promotion, the `--column-geometry-query` budgets are
macOS-derived and unenforced in hosted CI until a promotion slice. A regression would
be caught locally but not block merge until promotion. Established rhythm; accepted,
time-boxed gap.

### Floating-point at the in-range upper edge

The in-range `fractionInColumn = (x - left) / width` is the exact ratio and is in
`[0, 1)` mathematically, but for `x` extremely close to `right` floating-point may
round it toward `1.0`. The core does not special-case this (consistent with how the
engine trusts the `columnOffset` contract elsewhere); `1.0` as a *clamp* sentinel and
a `1.0` produced by extreme-edge rounding are not distinguished. Documented, accepted
(the exact vertical `lineGeometryAt` posture).

### Additive public surface

Three new public types (`ColumnGeometry`, `ColumnGeometryQuery`,
`ColumnGeometryLocation`) plus one method widen the API. This is the intended
capability growth and is non-breaking (new method + new types, not a new `ColumnQuery`
case), per the Slice 27/31/33 extension rule. One more new type than the vertical
`lineGeometryAt` (which reused the pre-existing `LineGeometry`), because no horizontal
cell-box type existed.

### Caret snapping stays a caller concern

Per the user's chosen shape, the core returns box + fraction and does **not** snap the
caret to a leading/trailing edge. A consumer wanting a single caret column/`x` applies
its own threshold/affinity/RTL rule (`fraction < 0.5 ? leading : trailing`). This
keeps editor-specific policy out of the headless core, matching `lineGeometryAt`.
Documented as intentional, not a gap.

## Future Slices

- **Promote `--column-geometry-query --gate` to a blocking hosted CI gate** (the
  ninth), completing the functional → promotion pair, exactly as Slices 15 / 21 / 24 /
  26 / 28 / 32 / 34 did for the prior seven modes.
- **`pointAt(x:y:)` 2D hit-test (Option B)**: compose this slice's horizontal
  `ColumnGeometryLocation` with the vertical `LineGeometryLocation` into a single
  point → (line, cell) query over both metrics sources — the biggest product leap
  toward click-to-caret / selection. Needs its own brainstorm (how the two independent
  sources compose, the combined result/clamp shape). Reads cleanly now that both axes
  are geometry-bearing.
- **Horizontal native / closed-form `columnIndex` overrides (Option D)**: O(1) uniform
  and native prefix-search overrides for `UniformColumnMetrics` /
  `PrefixSumColumnMetrics`, boundary-safe against the equivalence oracle — the
  horizontal mirror of vertical Slices 29/30, now measurable against this slice's (and
  Slice 34's) gates.
- **Provider-native geometry-bearing descent**: an optional
  `LineHorizontalMetricsSource` hook returning `(index, left, right)` in one walk,
  default-implemented as today's composed form — the constant-factor trim, the Slice
  31→native pattern applied horizontally.
