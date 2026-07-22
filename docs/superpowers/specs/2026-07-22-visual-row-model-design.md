# Visual-Row Model + Row-Packing (`visualRows(inLine:wrapWidth:)`) Design

- **Slice:** 49 — soft-wrap arc, **node 1**
- **Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md)
- **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)

## Status

Proposed. Brainstormed 2026-07-22; this document is the ratified design. The
next step after user sign-off is the TDD implementation plan
(`writing-plans`).

## Source Context

The soft-wrap arc adds a layer that maps **logical lines** to **visual rows**
at a given wrap width, while the engine stays headless and Foundation-free.
The full feature has two layers:

- **(i) Per-logical-line packing** — one logical line + a wrap width → its
  visual rows, each a half-open cell span with a width. A *pure, stateless*
  function of (advances, break opportunities, width). No document-global state.
- **(ii) Cross-line aggregation** — total visual-row count, global
  visual-row-index ↔ (logical line, row-in-line), cumulative y per visual row;
  the structure wrap-aware `compute` needs, and where criterion 1's
  width-change-cost question lives.

This slice is **layer (i) only** (arc map node 1). Layer (ii) is node 2.

The provider contract mirrors the two existing metrics sources:
`LineMetricsSource` (vertical, cumulative y) and `LineHorizontalMetricsSource`
(horizontal, cumulative x per cell). Both are `count` + cumulative `offset` +
a provider-native inverse hook (binary-search default) + a `Uniform*` core
reference. The row packer reuses the horizontal source's advances verbatim.

## Problem

An editor with soft-wrap on displays each logical line as one or more visual
rows sized to a layout width. The core must compute that row partition from
provider-supplied metrics **without** owning Unicode tables, shaping, or font
knowledge — «только математику упаковки advance'ов в ряды» (only the math of
packing advances into rows). Rows are described in **visual order**; bidi and
shaping are out of scope. The no-wrap path must be preserved, and wrap at
infinite width must equal no-wrap (an equivalence oracle, by the model of
"variable == fixed at uniform metrics").

## Scope

**In:** the `WrapMetricsSource` provider contract; greedy per-line row-packing
math; the `VisualRow` value type; a streaming `VisualRowCursor`; the stateless
`ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:)` entry point with
width validation; the per-line equivalence oracle and packing-invariant tests.

**Out (later nodes, stated as non-goals below):** cross-line aggregation /
global row indexing (node 2); vertical stacking — row y/height (node 2);
wrap-aware `compute` and the width-change cost demonstration (node 2);
y→row and point→(row, cell) queries (nodes 3–4); geometry-bearing row boxes;
`--memory-shape` extension (node 5); benchmark modes / CI gates (node 6);
incremental edits under wrap (node 7); verification hosts (nodes 8–9).

## Goals

1. A wrap-metrics contract that adds **only** break opportunities on top of the
   existing horizontal advances — nothing re-declared.
2. Greedy first-fit packing that breaks **only** at provider-declared
   opportunities and never invents grapheme boundaries.
3. A `VisualRow` model + O(1)-memory streaming cursor that composes into
   node 2's buffer streaming.
4. A **strong** per-line equivalence oracle (irregular advances + irregular
   breaks; at width ≥ line total, exactly one row = the no-wrap column model).
5. Zero change to the existing no-wrap path; all existing tests still green.

## Non-Goals

- No Knuth-Plass / optimal line breaking. Greedy first-fit only.
- No mid-segment (grapheme-level) breaking. The core has no Unicode tables; an
  unbreakable run wider than the width **overflows** its row.
- No trailing-whitespace collapse/hang. The core cannot identify whitespace
  without Unicode tables; row width is the raw advance sum. A provider controls
  hanging behaviour by *where* it places break opportunities.
- No vertical model, no cross-line indexing, no `compute`, no gate, no host —
  all later nodes.
- No new **public** reference provider. Node 1 is driven by a test-only
  conformer; a shipped `UniformWrapMetrics` / reference wrap provider is
  deferred to when a host needs one (nodes 8–9).

## Decisions

### Decision 1 — `WrapMetricsSource` refines `LineHorizontalMetricsSource`

```swift
public protocol WrapMetricsSource: LineHorizontalMetricsSource {
    /// Is a soft-break legal immediately before `column` (i.e. after cell
    /// column − 1)? Interior boundaries are `1..<columnCount(inLine:)`; the core
    /// additionally treats `columnCount(inLine:)` (the line end) as an implicit
    /// legal end and never queries `canBreak` at `0` or at `columnCount`.
    /// Word-wrap ⇒ true only after spaces; char-wrap ⇒ true at every boundary.
    /// The density of opportunities is entirely the provider's call — the core
    /// owns no Unicode tables, shaping, or font knowledge.
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool
}
```

Rationale: (1) **DRY** — advances come through the inherited `columnOffset`;
the wrap contract adds only break opportunities. (2) The equivalence oracle is
airtight — the "no-wrap reference" and the "wrap advances" are the **same
object**, so nothing independently constructed can drift. (3) A single
predicate spans word-wrap and char-wrap with zero core changes.

`canBreak` has **no default** — it is the one thing a wrap provider must supply
beyond the horizontal metrics. (The inherited `columnIndex` inverse hook keeps
its binary-search default.)

### Decision 2 — Greedy first-fit packing, break only at opportunities

For a row starting at column `s` in a line with `n = columnCount(inLine:)`
cells, the **legal ends** are `{ c ∈ 1...n : c == n or canBreak(beforeColumn:
c) }`. The packer:

1. Picks the **largest** legal end `e > s` with
   `columnOffset(e) − columnOffset(s) ≤ wrapWidth` (first-fit greedy). Emits
   row `[s, e)`; continues from `e`.
2. **Overflow rule:** if *no* legal end fits (the nearest legal end already
   exceeds `wrapWidth`), emits the **smallest** legal end `e > s` as a row
   **wider than `wrapWidth`**, and continues from `e`. The core never breaks a
   segment the provider did not declare breakable.

Invariants this guarantees:

- Rows **tile** `[0, n)` — contiguous, no gaps, no overlaps; their
  concatenation reconstructs the line.
- **Every logical line → ≥ 1 visual row.**
- **Blank line** (`n == 0`) → exactly **one** visual row, span `[0, 0)`,
  width 0.
- **Row width = advance sum** `columnOffset(e) − columnOffset(s)`; no
  whitespace special-casing.

### Decision 3 — `VisualRow` value type (horizontal only)

```swift
public struct VisualRow: Equatable {
    public let logicalLine: Int    // which logical line this row belongs to
    public let rowInLine: Int      // 0-based index of this row within logicalLine
    public let startColumn: Int    // inclusive
    public let endColumn: Int      // exclusive — half-open [startColumn, endColumn)
    public let width: Double       // columnOffset(endColumn) − columnOffset(startColumn)
    public init(logicalLine: Int, rowInLine: Int, startColumn: Int, endColumn: Int, width: Double)
}
```

No `y`/`height` and no x-origin: node 1 is pure horizontal packing; vertical
stacking and geometry-bearing boxes are later nodes. `rowInLine` is derivable
but kept as a self-describing addressing field (node 4 will want it), mirroring
how `LineGeometry` carries its own `lineIndex`. Placed in `ViewportTypes.swift`
beside `LineGeometry`/`ColumnGeometry`.

### Decision 4 — Streaming `VisualRowCursor`, O(1) core memory

```swift
public struct VisualRowCursor { /* forward, non-Equatable, mutable state */
    public mutating func next() -> VisualRow?
}
```

State is O(1): line index, `columnCount`, `wrapWidth`, and the current start
column; each `next()` runs one greedy walk. This matches `LineGeometryCursor`
(standalone struct + `mutating func next() -> T?`, handed back by a
`ViewportVirtualizer` factory) and keeps core memory constant per the hard
constraint. It **composes into node 2** — node 2 chains per-line cursors across
the viewport buffer with no array materialized. The cursor holds the metrics
value; tests collect it into `[VisualRow]` in two lines.

For a valid line the cursor yields **≥ 1** row (a blank line yields exactly the
`[0, 0)` row, then `nil`).

### Decision 5 — `visualRows` entry point validates width; `inLine` is a precondition

```swift
public enum VisualRowQuery {   // NOT Equatable: carries a mutable, non-Equatable cursor
    case rows(VisualRowCursor)               // one or more rows (blank line ⇒ one)
    case failure(ViewportValidationError)    // invalid wrapWidth
}

extension ViewportVirtualizer {
    public static func visualRows<Metrics: WrapMetricsSource>(
        inLine line: Int, wrapWidth: Double, metrics: Metrics) -> VisualRowQuery
}
```

`VisualRowQuery` is **not** `Equatable` (unlike `ColumnQuery`/`LineQuery`,
whose payloads are all value types) — its `.rows` payload is the mutable
`VisualRowCursor`, for which structural equality is meaningless. Tests
pattern-match the case and compare the extracted `[VisualRow]` (which *is*
`Equatable`) for `.rows`, and the extracted `ViewportValidationError` for
`.failure`. This matches the bare-cursor factory `geometry(for:lineHeight:)`,
which also returns a non-`Equatable` cursor.

- Validates `wrapWidth` **finite and `> 0`** → new
  `ViewportValidationError.nonPositiveWrapWidth`. `wrapWidth == .infinity` is
  **not** an error — it is the equivalence case (one row). Non-finite (`NaN`,
  `−∞`) and `≤ 0` fail.
- `inLine` is a **precondition**, not validated — `WrapMetricsSource` (via
  `LineHorizontalMetricsSource`) carries no `lineCount`, exactly as `columnAt`
  treats its `inLine`. The caller passes a valid line index.
- **No `.empty` case:** a blank line is still one real row, delivered through
  the cursor, so there is no empty-result branch (contrast `ColumnQuery.empty`,
  which means "blank line, no cell"). The only non-row outcome is invalid width.

Validation lives in this method (public semantics centralized here); the cursor
is the raw, precondition-based streaming primitive — the codebase's split
between validating query methods and unvalidated cursors.

### Decision 6 — Equivalence oracle stated strongly

For **irregular** advances and an **irregular** break set, and for any
`wrapWidth ≥ columnOffset(inLine: L, column: columnCount(inLine: L))` (the
line's total advance — `.infinity` included), packing line `L` yields
**exactly one** `VisualRow` with `startColumn == 0`,
`endColumn == columnCount(inLine: L)`, and
`width == columnOffset(inLine: L, column: columnCount(inLine: L))` — the
no-wrap column model read off the **same** source. This is the per-line half of
criterion 3's "wrap at infinite width equals no-wrap"; the whole-document half
is node 2. Stating it over irregular inputs (not a uniform grid) is what makes
it a real guarantee rather than a tautology.

### Decision 7 — Test-only `TestWrapMetrics`, no new public provider

All packing/oracle tests are driven by a **test-only** `TestWrapMetrics` in
`Tests/TextEngineCoreTests` (arbitrary advances array → cumulative
`columnOffset`; a `Set<Int>` of break columns → `canBreak`), mirroring the
existing `TestLineMetrics.swift`. This supplies the *irregular* inputs the
oracle needs and keeps the node-1 **core surface minimal** — no public
reference provider ships until a host needs one (deferred, YAGNI).

`TextEngineCoreTests` depends on `TextEngineCore` alone, so this conformer is
reachable there and needs no reference-provider dependency — the same reason
`UniformColumnMetrics`/`TestLineMetrics` sit where they do.

### Decision 8 — File placement mirrors the existing sources/queries

- `Sources/TextEngineCore/WrapMetricsSource.swift` — the protocol (beside
  `LineHorizontalMetricsSource.swift`).
- `Sources/TextEngineCore/VisualRowCursor.swift` — the cursor + the
  `ViewportVirtualizer.visualRows` factory (beside `LineGeometryCursor.swift`).
- `Sources/TextEngineCore/ViewportTypes.swift` — add `VisualRow`,
  `VisualRowQuery`, and the `nonPositiveWrapWidth` error case.

## Component Design

### `visualRows(inLine:wrapWidth:metrics:)` (new)

Validate `wrapWidth` (finite & `> 0`); on failure return
`.failure(.nonPositiveWrapWidth)`. Otherwise construct and return
`.rows(VisualRowCursor(line:wrapWidth:metrics:))`. No packing work happens
here — the cursor is lazy.

### `VisualRowCursor` (new)

Holds `line`, `columnCount` (read once at init for a stable snapshot),
`wrapWidth`, `metrics`, `nextStartColumn` (init 0), `nextRowInLine` (init 0),
and a `finished` flag. `next()`:

- If `finished`, return `nil`.
- If `columnCount == 0`: emit the single blank row `[0, 0)` width 0, set
  `finished`, return it.
- Else compute the greedy end `e` from `nextStartColumn` (Decision 2), emit
  `[nextStartColumn, e)`, advance `nextStartColumn = e` and `rowInLine`, set
  `finished` when `e == columnCount`, return the row.

The greedy end search walks legal ends forward from `nextStartColumn`; because
`columnOffset` is monotone, it stops at the first end that would overflow and
returns the previous fitting end (or the first legal end on overflow). O(cells
in the row) per `next()`, O(1) state.

### Types (new)

`VisualRow`, `VisualRowQuery` (Decisions 3, 5), `WrapMetricsSource`
(Decision 1), `ViewportValidationError.nonPositiveWrapWidth`.

### Untouched

`LineMetricsSource`, `LineHorizontalMetricsSource`, `ViewportVirtualizer`
compute/`lineAt`/`columnAt`/`pointAt`, all cursors, all reference providers.
The no-wrap path is unchanged; existing tests are untouched and must stay green.

## Testing Strategy

### `TestWrapMetrics` (test helper)

`Tests/TextEngineCoreTests/TestWrapMetrics.swift`: advances `[Double]`
(strictly increasing partial sums built from positive per-cell advances) +
`Set<Int>` break columns → `columnCount`, `columnOffset`, `canBreak`.

### Equivalence oracle (load-bearing) — `VisualRowEquivalenceTests`

Irregular advances + irregular break sets; for `wrapWidth ∈ { total, total +
ε, .infinity }` assert exactly one row `[0, n)` width `total`. Include a blank
line (one `[0,0)` row) and a single-cell line.

### Packing invariants — `WrapPackingTests`

- **Partition:** rows tile `[0, n)`, contiguous, reconstruct the line;
  `rowInLine` is 0-based and monotone; `logicalLine` is constant.
- **Breaks only at opportunities:** every interior break column is in the break
  set, *except* a forced-overflow row whose start was already unbreakable.
- **Greedy maximality:** each non-final, non-overflow row cannot legally extend
  — the next legal end would overflow.
- **Overflow:** a single unbreakable run wider than `wrapWidth` → one row wider
  than `wrapWidth`; char-wrap (break everywhere) with a too-small width → one
  cell per row.
- **Blank line** → one `[0,0)` row, width 0, then `nil`.
- **Width validation:** `wrapWidth ∈ { 0, −1, −∞, NaN }` →
  `.failure(.nonPositiveWrapWidth)`; `.infinity` and tiny positive widths do
  **not** fail.

### Not tested here

Cross-line aggregation, vertical geometry, `compute`, y→row, point→(row,cell),
performance/gates — all later nodes.

## Benchmark Mode / CI

**None this slice.** No new `BenchmarkMode`, no `--gate`, no CI wiring — node 1
is pure model + math. Performance calibration and blocking gates for wrap are
node 6, by the existing harvest → derive recipe. (Stated explicitly so a
reviewer confirms the omission is intentional, not a missing gate.)

## Documentation Updates

- `AGENTS.md` — extend the architecture paragraph with the wrap layer: the
  `WrapMetricsSource` contract (refines `LineHorizontalMetricsSource` + one
  `canBreak` predicate), `visualRows(inLine:wrapWidth:)` returning a streaming
  `VisualRowCursor`, greedy-first-fit / overflow-overflows semantics, and the
  per-line equivalence oracle. Note node 1 is per-line only; cross-line
  aggregation is node 2.
- `docs/superpowers/arcs/wrap.md` — mark node 1 progress at the post-slice
  review (map pass), not in this spec.

## Verification

Per AGENTS.md "When you change the core":

- `swift test` (new tests green; existing suite unchanged).
- `swift build -c release`.
- `swift run -c release ViewportBenchmarks -- --gate` → `gate=pass` (unchanged;
  no new mode).
- Foundation-free scan: `rg -n "Foundation" Sources/TextEngineCore` → empty.
- Cross-target compile (portability-sensitive: new public API): iOS + WASM via
  `./.github/scripts/cross-target-compile.sh` (or the hosted CI jobs).

Record actual commands, outputs, and hosted run IDs in
`docs/superpowers/verification/2026-07-22-visual-row-model.md`, anchoring merged
proof in the post-merge run.

## Acceptance Criteria

1. `WrapMetricsSource` exists, refines `LineHorizontalMetricsSource`, adds
   `canBreak(beforeColumn:inLine:)` with no default.
2. `VisualRow` (`Equatable`), `VisualRowQuery` (**not** `Equatable`),
   `VisualRowCursor` (streaming, non-`Equatable`), and
   `ViewportValidationError.nonPositiveWrapWidth` exist with the ratified
   shapes.
3. `ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:)` validates width
   (finite & `> 0`; `.infinity` allowed) and returns a lazy cursor.
4. Greedy packing honours Decision 2 (largest-fit, overflow-at-smallest-end,
   break-only-at-opportunities, tile-the-line, blank→one row).
5. Equivalence oracle (Decision 6) passes over irregular inputs at
   `wrapWidth ≥ total`.
6. All packing-invariant tests pass; the full existing suite stays green.
7. Foundation-free scan empty; release build + `--gate` pass; iOS + WASM
   cross-compile pass.
8. Hosted CI green at **step** level (read step logs, not the job conclusion),
   recorded with run IDs; merged proof anchored in the post-merge run.

## Risks And Gaps

- **Provider monotonicity trust.** The packer assumes `columnOffset` is finite
  and strictly increasing (the existing `LineHorizontalMetricsSource`
  precondition). It does not re-validate per cell — same trust model as
  `columnAt`. A malformed provider is a precondition violation, not a handled
  case.
- **Overflow visibility.** A row wider than `wrapWidth` is a legitimate result,
  not an error and not flagged. Callers that need to detect overflow compare
  `width` to the wrap width themselves. Recorded so node 2/hosts don't expect a
  flag.
- **Cursor is not `Equatable`.** By design (mutable state); the `VisualRow`
  values it yields are the `Equatable` test surface. Tests collect before
  comparing.
- **`.infinity` arithmetic.** `columnOffset(e) − columnOffset(s) ≤ .infinity`
  is trivially true, so `wrapWidth == .infinity` always fits the whole line in
  one row — the equivalence case — with no special-case branch. A finite
  `total` reaches the same one-row result, so the branch stays uniform.

## Future Slices (arc map, for reference)

Node 2 — wrap-aware `compute` over visual rows + width-change cost demo
(retires the top risk). Nodes 3–4 — y→row and point→(row,cell). Node 5 —
`--memory-shape`. Node 6 — wrap gates. Node 7 — incremental edits under wrap.
Nodes 8–9 — iOS and browser/WASM verification hosts.
