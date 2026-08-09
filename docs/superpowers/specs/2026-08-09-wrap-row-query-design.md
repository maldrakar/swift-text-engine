# Wrap-Aware Vertical Position Query (`visualRowAt(y:layout:)`) Design

- **Slice:** 53 — soft-wrap arc, **node 3**
- **Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md)
- **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)

## Status

Proposed. Brainstormed 2026-08-09; this document is the ratified design. Five
decisions were taken with the user during brainstorming (result shape, the
`UniformLineMetrics` O(1) hook's placement, the `VisualRowQuery` name collision,
the benchmark mode, and how the validation ladder is shared). The next step after
user sign-off is the TDD implementation plan (`writing-plans`).

## Source Context

Node 1 (Slice 49) shipped per-logical-line greedy row-packing: one logical line +
a wrap width → its `VisualRow`s, each a half-open cell span `[startColumn,
endColumn)` with an advance-sum width, streamed by an O(1)-state
`VisualRowCursor<Metrics: WrapMetricsSource>`.

Node 2 (Slice 50) shipped cross-line aggregation: `VisualRowLayoutSource` (the
visual-row axis — `lineCount` + uniform `rowHeight` + baked-in `wrapWidth` +
`visualRowCount(inLine:)` + the provider-owned prefix sum `firstVisualRow(ofLine:)`
+ a `logicalLine(containingVisualRow:)` inverse with a binary-search default),
the third `compute` overload `compute(_:layout:)`, the streaming
`DocumentVisualRowCursor`, and the whole-document infinite-width equivalence
oracle.

Criterion 3 of the brief names three wrap-aware query analogs:
«compute по визуальным рядам, y→ряд, точка→(ряд, ячейка)». Node 2 shipped the
first. **This slice ships the second: `y → row`.** The third (point→(row, cell))
is node 4.

The no-wrap axis is the template. `ViewportVirtualizer.lineAt(y:metrics:)`
(`Sources/TextEngineCore/PositionQuery.swift:13`) answers `y` with a
`LineLocation` — an index plus a clamp flag — and owns the validation ladder,
the empty-document short-circuit, and the clamp semantics. Geometry arrived
later as a separate companion (`lineGeometryAt`, Slice 31). This slice mirrors
that split: **indices now, geometry later.**

## Problem

`compute(_:layout:)` returns a `VirtualRange` over **visual-row indices**, and
`DocumentVisualRowCursor` streams the rows in that range. But nothing maps a
document `y` back to a row. Every caller that resolves a pointer event, a caret
position, or a scroll anchor under wrap needs that inverse, and today has to
reimplement it: divide by `rowHeight`, handle the two edges, then call
`logicalLine(containingVisualRow:)` and subtract the prefix sum. That is core
math living in callers — precisely what the engine exists to own, and precisely
the shape `lineAt` retired on the no-wrap axis.

## Scope

One public static query, its result types, an internal refactor that lets it
share `compute(_:layout:)`'s validation ladder, one public-type rename, and a
local-only observational benchmark mode.

## Goals

1. `ViewportVirtualizer.visualRowAt(y:layout:)` maps a document `y` to a visual
   row over any `VisualRowLayoutSource`, naming the row in **both** coordinate
   systems the engine speaks.
2. O(1) core memory. No packing, no within-line walk, no new search machinery —
   it composes searches that already exist.
3. Validation, clamp semantics, and the empty-document case are **identical to
   `compute(_:layout:)` and `lineAt` by construction**, not by inspection.
4. The infinite-width equivalence oracle holds: at `wrapWidth = ∞`,
   `visualRowAt` is bit-identical to `lineAt` over a uniform line axis
   (criterion 3's oracle requirement, on the vertical axis, for this query).

## Non-Goals

Each has a home; none is a gap this slice quietly leaves.

| Not this slice | Where it goes |
|---|---|
| Row **geometry** — cell span, `y`/`height`, within-row fraction | the geometry companion slice, on the `lineAt`→`lineGeometryAt` (27→31) pattern |
| `UniformLineMetrics` native O(1) hook + the budget re-derivation it forces | its own slice — see Decision 2 |
| CI wiring, a gate, a budget, corpus rows | map node 6 |
| point→(row, cell) | map node 4 |
| A balanced-tree native `logicalLine(containingVisualRow:)` descent | a later provider node, mirroring Slices 29/30 on the logical-line axis |
| A shipped reference provider | node 2's Decision 8 precedent: test-only conformer + benchmark-local provider |
| D-13 (per-axis binary-search consolidation) | the O(1)-hook slice — see Decision 6 |

## Decisions

### Decision 1 — The result names the row in both coordinate systems

`visualRowAt` returns a `VisualRowLocation` carrying `globalRow`, `logicalLine`,
`rowInLine`, and the clamp flag.

```swift
public struct VisualRowLocation: Equatable {
    public let globalRow: Int    // index into compute(_:layout:)'s VirtualRange
    public let logicalLine: Int
    public let rowInLine: Int
    public let clamp: LineLocation.Clamp   // reused, not re-declared
}

public enum VisualRowQuery: Equatable {
    case row(VisualRowLocation)
    case empty                             // lineCount == 0
    case failure(ViewportValidationError)
}
```

Rationale: the wrap axis has two useful coordinates for the same row.
`globalRow` is what `compute(_:layout:)` ranges over; `(logicalLine, rowInLine)`
is what `VisualRow` and `DocumentVisualRowCursor` speak. A bare `globalRow`
cannot be turned into text without the second pair, so every caller would
immediately call `logicalLine(containingVisualRow:)` and subtract the prefix sum
themselves — core arithmetic duplicated at every call site.

Cost of including it: one call to `logicalLine(containingVisualRow:)` (already a
protocol hook with a binary-search default that a provider may override with a
native descent) plus one O(1) `firstVisualRow(ofLine:)` probe. No new search
machinery.

`LineLocation.Clamp` is **reused rather than re-declared**: the vertical clamp
question is identical on both axes, and a parallel enum would invite the two to
drift.

### Decision 2 — The `UniformLineMetrics` O(1) hook is a separate slice

`visualRowAt` delegates its row-axis search to `lineAt` over
`UniformLineMetrics(lineCount: totalRows, lineHeight: layout.rowHeight)`, exactly
as `compute(_:layout:)` delegates its range math (node 2, Decision 2). The
search inside is therefore whatever `UniformLineMetrics` provides.

Today it provides the generic binary search: `UniformLineMetrics`
(`Sources/TextEngineCore/LineMetricsSource.swift:103`) implements only
`offset(ofLine:)` and overrides **neither** `lineIndex(containingOffset:)` nor
`firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`. A uniform axis could
answer both by division in O(1), with a bounded ±1 correction to stay exactly
consistent with `offset(ofLine:)` under floating-point rounding.

That optimization is **deliberately not in this slice.** Live check at selection
time: `UniformLineMetrics` is on the hot path of four *gated* modes —
`line_query`, `line_geometry_query`, `point_query`, `point_geometry_query` all
construct it for their `uniform_*` scenarios (`LineQueryBenchmark.swift:123`,
`LineGeometryQueryBenchmark.swift:132`, `PointQueryBenchmark.swift:163`,
`PointGeometryQueryBenchmark.swift:195`). Removing ~17 probes at 100k lines is a
genuine speed-up, and `AGENTS.md` is explicit about what that costs: a speed-up
that trips `headroom_p95 <= 50x` must be answered by re-deriving budgets from
fresh hosted evidence **in the same PR** (the Slices 29/30 precedent).

So the hook is its own slice — *uniform-axis native hook + budget
re-derivation* — which owns both halves coherently and keeps this slice about
wrap. Consequence accepted here: wrap compute and `visualRowAt` keep their
O(log totalRows) row-axis term, which is the arc's already-recorded position
(the map's "O(log totalRows), viewport-bounded — not literally
width-independent" correction).

### Decision 3 — `VisualRowQuery` is renamed onto the axis-query family

Node 1's `VisualRowQuery<Metrics>` (`ViewportTypes.swift:246`) becomes
`VisualRowPackingQuery<Metrics>`, freeing `VisualRowQuery` for this slice's
result.

Rationale: every other member of the family is named for what it answers —
`LineQuery` (y→line), `ColumnQuery` (x→cell), `PointQuery` ((x,y)→both). Node 1's
enum is not a position query at all; it wraps a streaming packer, and it is the
only generic, non-`Equatable` member of the family. Naming it for what it is
(`…PackingQuery`) restores the pattern rather than permanently exempting one
member from it.

Cost: a public-type rename. The blast radius is this repository — a headless
pre-1.0 core with no external consumers — and the change is mechanical. The
spec+plan ceremony that `AGENTS.md` requires for public-API changes is the
process this document is part of.

### Decision 4 — `visualRowAt` re-validates the layout; it does not just delegate

`visualRowAt` cannot hand its `layout` straight to `lineAt`. `lineAt` validates
the metrics object it receives — the *uniform row axis* — not the layout
provider behind it. Two concrete failures if it delegated blind:

- `rowHeight <= 0` would surface as `.invalidLineMetrics` (via a non-positive
  `totalHeight`) instead of `.nonPositiveRowHeight`.
- `wrapWidth <= 0` or `NaN` would not be caught **at all**, so a layout that
  `compute(_:layout:)` rejects would be silently accepted here, and the two
  entry points would disagree about whether the same provider is usable.

`wrapWidth` is therefore validated even though this query never packs. It reads
as a useless check; it is the check that keeps the two entry points'
accept/reject sets equal.

### Decision 5 — The shared ladder is extracted, not duplicated

`compute(_:layout:)`'s six layout checks move into one internal helper that both
entry points call:

```swift
enum VisualRowLayoutValidation {
    case failure(ViewportValidationError)
    case empty
    case rows(Int)          // totalRows > 0, totalHeight finite
}

// 1. rowHeight finite && > 0        -> .nonPositiveRowHeight
// 2. wrapWidth > 0                  -> .nonPositiveWrapWidth   (+∞ passes)
// 3. firstVisualRow(ofLine: 0) != 0 -> .invalidVisualRowLayout
// 4. lineCount == 0                 -> .empty
// 5. totalRows <= 0                 -> .invalidVisualRowLayout
// 6. totalHeight non-finite         -> .invalidVisualRowLayout
```

Check 2 keeps node 1's F1 trap comment: `wrapWidth > 0` accepts `+∞` (the
equivalence case) and rejects `NaN`/`−∞`/`≤ 0`. It must **not** be written as
`isFinite && > 0` — `+∞` is not finite.

`lineCount < 0` stays as the first line in **each** caller rather than moving
into the helper. The reason is precedence: `compute`'s next checks are
input-specific (`scrollOffsetY`/`viewportHeight` finiteness, negative viewport
height, negative overscan) while `visualRowAt`'s next check is `y` finiteness.
Hoisting the whole layout ladder above those would change `compute`'s shipped
error precedence, which node 2's Decision 6 and
`WrapComputeValidationTests.testLadderOrderLineCountBeforeRowHeight` pin.

The extraction is behaviour-identical by construction, and **its proof is that
node 2's existing `WrapComputeValidationTests` pass untouched**. If extraction
perturbs precedence, those tests redden. That is the check — not inspection.

Each caller maps the helper's neutral result to its own type: `compute` maps
`.empty` to `.success(emptyRange())`, `visualRowAt` maps it to `.empty`.

### Decision 6 — D-13 is routed to the O(1)-hook slice, not folded in here

The Slice 52 review folded D-13 (per-axis binary-search triplication) into node 3
on the argument that node 3 would otherwise add a **fourth** copy of the same
body. Re-verified at selection time, that argument does not hold: node 3 follows
node 2's reuse pattern and adds no copy — it reuses `binarySearchLineIndex` (via
`UniformLineMetrics`) and the existing `binarySearchLogicalLine`, and never
touches either body.

D-13 stays open on merit. Its natural home is the Decision 2 slice, which edits
`LineMetricsSource.swift` directly — where two of the three copies live. Folding
it here would be unrelated churn in a slice whose diff should stay readable.
Recorded in the arc decision log (2026-08-09) and confirmed with the user.

### Decision 7 — Clamped queries need no special case

`lineAt` owns the clamp decision and resolves an out-of-range `y` to `globalRow
0` (`.clampedToTop`) or `totalRows − 1` (`.clampedToBottom`). Both then flow
through the *same* two provider calls as an in-range hit, so `logicalLine` and
`rowInLine` are correct at the edges by construction: a clamped-to-bottom query
names the last row of the last logical line without a branch.

This layer never re-derives the clamp. Consequence to hold onto in review: any
future change to clamp semantics belongs in `lineAt`, and this query inherits it.

### Decision 8 — Test-only conformer and benchmark-local provider; no shipped provider

Node 2's Decision 8, unchanged. `VisualRowLayoutSource` conformers for this slice
live in the test target (`VisualRowLayoutTestSupport.swift` already carries the
node-2 conformer) and in the benchmark target. Nothing is added to
`TextEngineReferenceProviders`. A shipped wrap provider is a later decision with
its own portability surface.

### Decision 9 — File placement mirrors the existing sources

| File | Role |
|---|---|
| `Sources/TextEngineCore/WrapPositionQuery.swift` | **new** — `visualRowAt`, mirroring `PositionQuery.swift` |
| `Sources/TextEngineCore/ViewportTypes.swift` | `VisualRowLocation`, `VisualRowQuery`; node 1's enum renamed |
| `Sources/TextEngineCore/WrapViewportVirtualizer.swift` | the extracted `VisualRowLayoutValidation` helper; `compute(_:layout:)` calls it |
| `Sources/TextEngineCore/VisualRowCursor.swift`, `DocumentVisualRowCursor.swift` | rename follow-through only |
| `Sources/ViewportBenchmarks/WrapRowQueryBenchmark.swift` | **new** — the observational mode |

## Component Design

```
visualRowAt(y:layout:)
  │
  ├─ layout.lineCount < 0            -> .failure(.negativeLineCount)
  ├─ !y.isFinite                     -> .failure(.nonFiniteValue)
  ├─ validate(layout)                -> .failure(e) | .empty | .rows(totalRows)
  │                                        │           └──────> .empty
  │                                        └──────────────────> .failure(e)
  └─ lineAt(y:, metrics: UniformLineMetrics(totalRows, layout.rowHeight))
        └─ .line(loc)
             ├─ globalRow   = loc.lineIndex
             ├─ logicalLine = layout.logicalLine(containingVisualRow: globalRow)
             ├─ rowInLine   = globalRow − layout.firstVisualRow(ofLine: logicalLine)
             └─ .row(VisualRowLocation(…, clamp: loc.clamp))
```

**Cost.** O(1) core memory. One row-axis search (O(log totalRows) today — see
Decision 2), one `logicalLine` search (O(log lineCount) by default,
provider-overridable), one O(1) `firstVisualRow` probe. The query never re-drives
node 1's packer, which is exactly why it is index-only: reconstructing a row's
cell span costs the documented O(rowInLine) within-line walk and belongs to the
geometry companion.

**Unreachable branches are mapped through, not force-unwrapped.** Given the
ladder passed (`totalRows > 0`, `y` finite, `UniformLineMetrics.offset(ofLine: 0)`
exactly `0`), the delegated `lineAt` can only return `.line`. The switch still
maps `.empty`/`.failure` straight through rather than force-unwrapping: no
fabricated row, no crash — the GIGO precedent `DocumentVisualRowCursor` set
(`DocumentVisualRowCursor.swift:38`).

## Testing Strategy

TDD, XCTest, in `Tests/TextEngineCoreTests`.

| Suite | What it pins |
|---|---|
| `WrapRowQueryValidationTests` | one test per error case; `.nonFiniteValue` precedes `.nonPositiveRowHeight`; `+∞` `wrapWidth` does not fail |
| **Ladder parity** (same file) | the same rigged layouts driven through `compute(_:layout:)` **and** `visualRowAt`, asserting identical verdict and identical error case — pins the `lineCount` head each caller still owns |
| `WrapRowQueryTests` | irregular row counts (e.g. `[1,3,2]`, `totalRows == 6`): `globalRow 3` → line 1, `rowInLine 2`; half-open boundary (`y == k·rowHeight` → row `k`, not `k−1`); both clamps; `y == totalHeight − ε`; empty document → `.empty` |
| `WrapRowQueryEquivalenceTests` | **criterion 3's oracle** — at `wrapWidth = ∞`, and at any finite width ≥ every line's total advance, bit-identical to `lineAt` over `UniformLineMetrics(lineCount, rowHeight)`: `globalRow == lineIndex`, `logicalLine == lineIndex`, `rowInLine == 0`, clamp equal; swept over negative, exact-boundary, interior, and past-the-end `y` |
| `WrapRowQueryRoundTripTests` | for a `compute(_:layout:)` range, every row `DocumentVisualRowCursor` streams satisfies `visualRowAt(y: geom.y) == that row`'s `globalRow`/`logicalLine`/`rowInLine` |
| Query-count (same file) | a counting layout wrapper: probe count bounded and independent of document size — no linear walk |
| `Tests/ViewportBenchmarksTests/WrapRowQueryOptionsTests.swift` | mode selection, `--gate` rejection, mode-conflict rejection |

**The round-trip test is the load-bearing one.** Every other suite compares the
query against arithmetic restated in the test file, so a coherent-but-wrong row
model could satisfy all of them. The round-trip compares it against node 1's
independently-written greedy packer driven through node 2's cursor.

**Falsifiability, planned up front.** Each new guarantee ships with recorded
evidence it can fail — the post-slice review's audit requires it, and a guarantee
drilled after the fact is weaker evidence than one drilled during. The plan
carries deliberate mutations, with the observed red recorded in the verification
document, for at least:

1. the half-open boundary (`<=` → `<` on the row-containment comparison),
2. the `rowInLine` subtraction (off-by-one),
3. the ∞ equivalence oracle,
4. the ladder-parity test (perturb one caller's ladder),
5. the query-count bound.

## Benchmark Mode / CI

`--wrap-row-query`: **observational, local-only, not gateable.**

Wiring is dictated by existing exhaustive switches in
`Sources/ViewportBenchmarks/BenchmarkOptions.swift`: a `BenchmarkMode` case,
`isGateable → false`, `absoluteCeiling → .scrollFrame`, help/usage text, a parse
case with combination rejection, and dispatch in `BenchmarkProgram.swift`.

It is **not** added to `.github/workflows/swift-ci.yml`. Two reasons, both
structural: gate promotion for wrap modes is map node 6, and an un-gated mode
printing summary lines in CI would put rows into every future harvest of that
run — the "exactly one CI step may print a given mode's summary lines" rule.
`--wrap-compute` set this precedent.

Known and accepted: this makes a **fifth** non-gateable mode whose
`AbsoluteCeiling` class is pinned by nothing (D-20). The class-membership pin
filters on `isGateable`, so `.scrollFrame` here is a compile-time obligation, not
a pinned one. Inert until a wrap mode becomes gateable — which is node 6, where
D-20 is the row to read. D-20's statement is updated from four modes to five.

## Documentation Updates

- `AGENTS.md` — the wrap section gains node 3's paragraph (the query, its two
  coordinate systems, its cost class, and the ∞ oracle); the flag list and the
  commands block gain `--wrap-row-query`, marked non-gateable alongside
  `--wrap-compute`.
- `docs/superpowers/debt-ledger.md` — new row for the `UniformLineMetrics` O(1)
  hook (candidate slice, born this spec); D-20's statement updated four → five.
- `docs/superpowers/arcs/wrap.md` — the map pass belongs to the post-slice
  review, not this spec; the 2026-08-09 selection entry is already recorded.

## Verification

Recorded as commands + outputs in
`docs/superpowers/verification/2026-08-09-wrap-row-query.md`:

- `swift test` — full suite green, with the count.
- `swift build -c release`.
- `rg -n "Foundation" Sources/TextEngineCore` — **empty** (the hard constraint).
- All **twelve** blocking gates (`--gate` on the default pipeline plus the eleven
  other gated modes) — `gate=pass`, unchanged. This slice touches no gated code
  path, so any movement is a finding, not noise.
- `swift run -c release ViewportBenchmarks -- --wrap-row-query` — the new
  observational output.
- `swift run -c release ViewportBenchmarks -- --memory-shape` — `invariant=pass`.
- `./.github/scripts/cross-target-compile.sh --self-test`.
- The five falsifiability drills, each with its observed red.
- Hosted proof at **step level** on both the PR-head run and the post-merge push
  run — not job conclusion (the Slice 16 dead-step lesson).

## Acceptance Criteria

1. `ViewportVirtualizer.visualRowAt(y:layout:)` exists over any
   `VisualRowLayoutSource` and returns `VisualRowQuery`.
2. `VisualRowLocation` carries `globalRow`, `logicalLine`, `rowInLine`, and a
   reused `LineLocation.Clamp`.
3. Node 1's enum is renamed `VisualRowPackingQuery<Metrics>`; no other public
   behaviour changes with it.
4. `compute(_:layout:)` and `visualRowAt` share one extracted layout ladder, and
   node 2's `WrapComputeValidationTests` pass **untouched**.
5. The accept/reject sets of the two entry points are equal, pinned by the
   ladder-parity test.
6. The ∞ equivalence oracle passes: `visualRowAt` is bit-identical to `lineAt`
   over a uniform axis at infinite (and sufficiently large finite) width.
7. The round-trip test passes against `DocumentVisualRowCursor` over a
   `compute(_:layout:)` range.
8. Core memory is O(1) and probe count is bounded, pinned by the query-count
   test.
9. `--wrap-row-query` runs, is rejected with `--gate`, is rejected with another
   mode flag, and is absent from `swift-ci.yml`.
10. The Foundation-free scan is empty and the release build succeeds.
11. All five falsifiability drills are recorded with their observed red.
12. Hosted proof at step level on both the PR-head and post-merge runs.

## Risks And Gaps

| Risk | Mitigation |
|---|---|
| The rename touches public API | Mechanical; no external consumers; compiler finds every site |
| The ladder extraction touches shipped node-2 code | Behaviour-identical by construction; proof is node 2's validation tests passing untouched |
| Floating-point: `y` near an exact row boundary | The half-open boundary test; the row-axis comparison is `lineAt`'s, unchanged and already covered on the no-wrap axis |
| A gated benchmark drifts | This slice touches no gated code path; the twelve gates run in verification precisely so drift is visible |
| `${PIPESTATUS[0]}` in the plan's own assertions | **D-17**: the idiom `AGENTS.md` rule 1 recommends expands empty under zsh and inverts the assertion into a pass. The plan must use `if ! cmd; then … fi` instead. Carried as an explicit plan instruction |

**Gap left open deliberately:** the O(1) uniform-axis hook (Decision 2). It is
recorded as a ledger row and a candidate slice, not silently dropped — it would
make wrap compute *literally* width-independent on the row axis, which is a
strengthening of criterion 1's wording, but it drags a gate re-derivation that
does not belong in a wrap-query slice.

## Future Slices (arc map, for reference)

- **node 4** — point→(row, cell): the 2D wrap composite, composing this query
  with the horizontal axis. Criterion 3's third analog.
- **geometry companion** — row span + `y`/`height` + within-row fraction, on the
  27→31 pattern.
- **uniform-axis O(1) hook + budget re-derivation** — Decision 2; folds in D-13.
- **node 5** — `--memory-shape` extended to the wrap path. Criterion 2.
- **node 6** — wrap modes promoted to blocking gates. Criterion 4; the slice
  where D-20 stops being inert.
