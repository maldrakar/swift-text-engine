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

**Revised 2026-08-09** after a design review run against the tree. The review
re-verified every code reference and the three load-bearing arguments (Decision 2's
gated-mode hot path, Decision 5's precedence constraint, Decision 6's
no-fourth-copy correction) and all three hold. What it changed, folded in below:
the query-count guarantee was logarithmic and only half-observable, not "bounded
and independent of document size" (Decision 7, Testing Strategy, AC8); the
ladder-parity test proves consistency but not *presence* (Decision 5, drill 6);
the rename's one non-compiler-checked site was unlisted (Decision 9,
Documentation Updates, AC3); the benchmark mode had neither an anti-dead-code
guard nor an output-shape decision (Benchmark Mode / CI, AC10); Goal 3 claimed
parity with two ladders that cannot both hold (Goal 3, Decision 4); and Decision 2
was missing the one option that gets its optimization without a budget
re-derivation.

**Second pass, same day.** A review of the revision itself found two defects it
had introduced, both of the class the revision existed to catch, and both are
fixed above rather than footnoted. (1) The added AC — a before/after comparison of
`--wrap-compute` output, advertised as "the non-vacuous evidence" for the
Decision 5 extraction — **could not fail**: `total_rows` is read off the provider,
the drained rows are never printed, and a `.failure` return is silent. It is
withdrawn; the extraction's evidence is AC4, now widened from one node-2 suite to
all three, and Verification records why the benchmark cannot help. (2) The rename's
blast radius was miscounted: `WrapTestSupport.swift:4` is a `///` comment, so there
are **two** prose sites the compiler cannot see, not one. Both counts are now
derived from `rg` output in Decision 9 rather than asserted.

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
3. The validation ladder is **identical to `compute(_:layout:)` by construction**
   — one shared helper, not inspection. From `lineAt` this query inherits
   something different: the **clamp semantics and the located index**, not the
   ladder. The two guarantees are deliberately distinct and cannot both be
   "identical" — `lineAt` has no notion of `rowHeight` or `wrapWidth` to validate,
   and answers an empty document without ever looking at either (Decision 4).
   Only the first is a parity claim, and only the first is pinned as one (AC5).
4. The infinite-width equivalence oracle holds: at `wrapWidth = ∞`,
   `visualRowAt` is bit-identical to `lineAt` over a uniform line axis
   (criterion 3's oracle requirement, on the vertical axis, for this query).

## Non-Goals

Each has a home; none is a gap this slice quietly leaves.

| Not this slice | Where it goes |
|---|---|
| Row **geometry** — cell span, `y`/`height`, within-row fraction | the geometry companion slice, on the `lineAt`→`lineGeometryAt` (27→31) pattern |
| Uniform-axis native O(1) hook — public `UniformLineMetrics` (forces a budget re-derivation) or the internal wrap-only axis (does not) | its own slice — see Decision 2, which records both paths |
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

**Why the fields are flat and not a nested `LineLocation`.** `PointLocation`
(`ViewportTypes.swift:257`) composes `LineLocation` rather than flattening it, so
the composition precedent is one slice old and a reviewer will ask. It does not
transfer: composing here would put a field named `lineIndex` — holding a
*visual-row* index — inside a struct that separately carries a real
`logicalLine`, which is exactly the confusion this result type exists to remove.
The clamp is the one part that genuinely asks the same question on both axes, and
that is the part that is reused.

### Decision 2 — The uniform-axis O(1) hook is a separate slice

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

**A third path exists, and is recorded so the future slice is not forced into a
false binary.** The re-derivation cost above is a property of the *public*
`UniformLineMetrics`, not of the optimization itself. An **internal** row axis —

```swift
struct UniformRowAxis: LineMetricsSource {   // internal, not public
    let lineCount: Int
    let lineHeight: Double
    func offset(ofLine i: Int) -> Double { Double(i) * lineHeight }
    func lineIndex(containingOffset y: Double) -> Int { /* division + bounded ±1 correction */ }
}
```

— constructed only by `compute(_:layout:)` and `visualRowAt`, moves no gated
mode's hot path. Verified at review time: every `UniformLineMetrics(` construction
site in `Sources/ViewportBenchmarks` is one of the four gated query modes cited
above plus the non-gated `MemoryShapeDiagnostics.swift:347`, and none of them would
see this type. So no headroom shifts, no budget is re-derived, and the map's "not
literally width-independent" correction retires on the row axis. Its cost is a
second uniform type — `internal`, and absorbed by the eventual public hook.

**Deferring is still the call**, on both paths: the ±1 floating-point correction
is a design question of its own, and this slice's diff should stay about wrap. So
the hook is its own slice — *public hook + budget re-derivation*, or the internal
variant that needs neither — which owns whichever halves it picks coherently. The
deferral is now recorded with **both** shapes, so that slice chooses rather than
inheriting "modify `UniformLineMetrics` and re-derive four gated modes" as though
it were the only option. Consequence accepted here: wrap compute and `visualRowAt`
keep their O(log totalRows) row-axis term, which is the arc's already-recorded
position (the map's "O(log totalRows), viewport-bounded — not literally
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
- On an **empty** document the two ladders answer different questions, and must.
  `lineAt` over `UniformLineMetrics(lineCount: 0, …)` returns `.empty` without
  ever inspecting `lineHeight` (`PositionQuery.swift:30` short-circuits before
  the total-height check), so a layout with `lineCount == 0` **and**
  `rowHeight <= 0` would read as `.empty` where `compute(_:layout:)` reports
  `.nonPositiveRowHeight`. This query follows `compute`. That divergence is why
  Goal 3 claims ladder parity with one entry point, not both.

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
node 2's existing wrap-compute suites pass untouched** — all three of them, not
just the validation one: `WrapComputeValidationTests` (every error case plus the
precedence pin), `WrapComputeTests` (success-path ranges — visible range,
scroll-to-bottom, cursor tiling, blank line, the interior exact-equal width
boundary), and `WrapComputeEquivalenceTests` (the ∞ oracle and the empty
document). Naming all three is load-bearing: a helper that returns a wrong
`totalRows` perturbs the *success* path while every error case still resolves
correctly, and the validation suite alone would not see it. If extraction moves
anything, those suites redden. That is the check — not inspection, and not the
benchmark (see Verification).

**What ladder parity does and does not prove.** The parity test compares the two
callers against *each other*, so it catches **divergence**: a check that moved,
that fires in a different order, or that exists on one side only. It cannot catch
**absence** — deleting a check from the shared helper changes both callers
identically and leaves parity green. Presence is carried by the per-error-case
tests on each side. `wrapWidth` needs them most: Decision 4 concedes it "reads as
a useless check", which makes it the first thing a later reader deletes as dead
weight. Drill 6 in the falsifiability list exists for exactly this asymmetry, and
records reds from both sides rather than from the parity test.

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

**The property that does *not* carry over — pinned, not assumed.** On the no-wrap
axis a clamped query costs two probes and performs no search;
`LineAtQueryCountTests.testClampBranchesDoNotSearch` (`:103`) pins exactly that
constant. Here it is false. `lineAt`'s clamp branch does skip the *row-axis*
search, but the `logicalLine` search on the *layout* axis still runs, because this
decision routes both edges through the same two provider calls as an in-range hit.
An O(1) special case is four lines — `.clampedToTop` → `(0, 0)`, `.clampedToBottom`
→ `(lineCount − 1, totalRows − 1 − firstVisualRow(ofLine: lineCount − 1))` — and it
is **deliberately not taken**: the uniform path has fewer branches and therefore
fewer places for an edge-case bug to hide, and the clamp path is not per-frame hot.
What the slice owes instead is a test that *states* the difference, so a reader who
knows the no-wrap axis does not copy that constant across. The query-count suite
carries it.

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
| `Tests/TextEngineCoreTests/WrapValidationTests.swift` (`:5`), `WrapTestSupport.swift` (`:7`) | rename follow-through only — compiler-checked uses |
| `Tests/TextEngineCoreTests/WrapTestSupport.swift` (`:4`) | rename follow-through — a `///` **doc comment**, so the compiler will not flag it. One of the two prose sites, not one of the four code sites |
| `AGENTS.md` (`:111`) | rename follow-through — the other prose site: the live architecture paragraph names `VisualRowQuery<Metrics>`, and after this slice that sentence describes a different type. See Documentation Updates and AC3 |

**The full blast radius, counted rather than asserted** (`rg -n "VisualRowQuery"`
over `Sources/`, `Tests/` and `AGENTS.md`; `docs/superpowers/**` is historical
record and is deliberately not rewritten):

- **Four compiler-checked code sites** — the declaration itself
  (`ViewportTypes.swift:246`, its own row above) plus three uses
  (`VisualRowCursor.swift:88`, `WrapValidationTests.swift:5`,
  `WrapTestSupport.swift:7`).
- **Two prose sites nothing checks** — `WrapTestSupport.swift:4` (a `///` comment
  on `collectRows`) and `AGENTS.md:111`. These are the ones a green build hides,
  and they are why AC3 enumerates them by path.
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

Counted on the layout axis, that is `firstVisualRow(ofLine: 0)` +
`firstVisualRow(ofLine: lineCount)` from the ladder, `<= ceilLog2(lineCount) + 1`
probes inside the default `logicalLine` search, and one final probe for the
subtraction: **`<= ceilLog2(lineCount) + 4`**. That is the number the query-count
suite pins, and it is logarithmic — not constant — in document size.

**One probe is knowingly paid twice.** The default `binarySearchLogicalLine`'s
last accepted probe *is* `firstVisualRow(ofLine: result)`, which the `rowInLine`
subtraction then re-reads. An internal `(line, firstRow)`-returning variant would
save it. Rejected: `logicalLine(containingVisualRow:)` is a protocol hook a
provider may override with a native descent that returns an index alone, so the
saving exists only on the fallback path and would buy it with an asymmetry between
the two paths. Recorded because it is what the `+ 4` above is hiding.

**The prefix-sum contract is trusted, not validated** — node 2's stance,
unchanged. Neither `compute(_:layout:)` nor this query checks that
`firstVisualRow` is strictly increasing. Under the *default* `logicalLine` hook
`rowInLine >= 0` holds regardless (the ladder already proved
`firstVisualRow(ofLine: 0) == 0`, and the search only ever accepts probes
`<= globalRow`), but a provider that **overrides** the hook and returns a line
whose `firstVisualRow` exceeds `globalRow` yields a negative `rowInLine`. That is
undefined-behavior input, not a handled case — the same GIGO precedent as
`DocumentVisualRowCursor.swift:38`, stated here so the absence of a check is a
decision on the record rather than an oversight.

**Unreachable branches are mapped through, not force-unwrapped.** Given the
ladder passed (`totalRows > 0`, `y` finite, `UniformLineMetrics.offset(ofLine: 0)`
exactly `0`), the delegated `lineAt` can only return `.line`. The switch still
maps `.empty`/`.failure` straight through rather than force-unwrapping: no
fabricated row, no crash — the GIGO precedent `DocumentVisualRowCursor` set
(`DocumentVisualRowCursor.swift:38`).

## Testing Strategy

TDD, XCTest. Core suites in `Tests/TextEngineCoreTests`; the benchmark-target
suites in `Tests/ViewportBenchmarksTests`, which is where option parsing and
checksum shape are already pinned for the other query modes.

| Suite | What it pins |
|---|---|
| `WrapRowQueryValidationTests` | one test per error case; `.nonFiniteValue` precedes `.nonPositiveRowHeight`; `+∞` `wrapWidth` does not fail |
| **Ladder parity** (same file) | the same rigged layouts driven through `compute(_:layout:)` **and** `visualRowAt`, asserting identical verdict and identical error case — pins the `lineCount` head each caller still owns |
| `WrapRowQueryTests` | irregular row counts (e.g. `[1,3,2]`, `totalRows == 6`): `globalRow 3` → line 1, `rowInLine 2`; half-open boundary (`y == k·rowHeight` → row `k`, not `k−1`); both clamps; `y == totalHeight − ε`; empty document → `.empty` |
| `WrapRowQueryEquivalenceTests` | **criterion 3's oracle** — at `wrapWidth = ∞`, and at any finite width ≥ every line's total advance, bit-identical to `lineAt` over `UniformLineMetrics(lineCount, rowHeight)`: `globalRow == lineIndex`, `logicalLine == lineIndex`, `rowInLine == 0`, clamp equal; swept over negative, exact-boundary, interior, and past-the-end `y` |
| `WrapRowQueryRoundTripTests` | for a `compute(_:layout:)` range, every row `DocumentVisualRowCursor` streams satisfies `visualRowAt(y:) ==` that row's `globalRow`/`logicalLine`/`rowInLine`, probed at **both** `geom.y` (the exact row boundary) and `geom.y + rowHeight / 2` (the interior). The boundary probe is what a `<`/`<=` mutation moves; the interior probe closes the class of compensating errors where a shifted boundary and a shifted index cancel on boundary samples alone |
| Query-count (same file) | a counting layout wrapper pinning the **logarithmic** layout-axis bound: `firstVisualRow` probes `<= ceilLog2(lineCount) + 4` (Component Design). Plus the clamp asymmetry from Decision 7 — clamped queries **do** search here, so the no-wrap axis's two-probe constant is asserted *not* to hold |
| `Tests/ViewportBenchmarksTests/WrapRowQueryOptionsTests.swift` | mode selection, `--gate` rejection, mode-conflict rejection |
| `Tests/ViewportBenchmarksTests/WrapRowQueryChecksumTests.swift` | the checksum folds **all three** returned fields under distinct multipliers — `PointGeometryChecksumTests` applied up front, so a zeroed multiplier or a drift back to an index-only fold cannot pass silently (AC10) |

**The query-count test pins one of the two axes, and says so rather than implying
otherwise.** `visualRowAt` constructs its `UniformLineMetrics` *inside* the core,
so a counting wrapper around `layout` cannot observe the row-axis search at all —
it sees `firstVisualRow` and `logicalLine`, nothing else. That is not a coverage
gap being papered over: `UniformLineMetrics.offset` is pure arithmetic touching no
provider, and the row-axis search is already pinned by `LineAtQueryCountTests`
(`testInRangeUsesLogarithmicQueriesAtOneMillionLines`, whose
`expectedMax = 2 + (ceilLog2(lineCount) + 1)` is the shape the bound above copies).
Naming the split is what keeps AC8 from claiming coverage the harness structurally
cannot give. And on neither axis is the count constant in document size —
"bounded" here means **logarithmic**, in the vocabulary the no-wrap suite already
uses.

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
4. the ladder-parity test — perturb **one** caller's ladder, proving the parity
   test sees divergence,
5. the query-count bound,
6. **presence, which parity structurally cannot see** — delete the `wrapWidth`
   check from the *shared* helper. This changes both callers identically, so
   drill 4's parity test stays **green**; the red must come from the
   per-error-case suites on both sides (`WrapRowQueryValidationTests` and node 2's
   `WrapComputeValidationTests.testNonPositiveWrapWidth`, `:31`). Recording both
   reds is what makes Decision 5's divergence-vs-absence distinction evidence
   rather than an assertion.

## Benchmark Mode / CI

`--wrap-row-query`: **observational, local-only, not gateable.**

Wiring is dictated by existing exhaustive switches in
`Sources/ViewportBenchmarks/BenchmarkOptions.swift`: a `BenchmarkMode` case,
`isGateable → false`, `absoluteCeiling → .scrollFrame`, help/usage text, a parse
case with combination rejection, and dispatch in `BenchmarkProgram.swift`.

**What it measures.** A benchmark-local `VisualRowLayoutSource` — the
`BenchmarkWrapLayout` shape node 2 already carries (`WrapComputeBenchmark.swift:7`:
char-wrap, uniform advances, prefix sum built by actually packing every line, so
the index is honest rather than faked) — swept over:

| Scenario | Shape | Why it is here |
|---|---|---|
| `uniform_1k` | 1 000 lines, one row each | the low-N reference point |
| `uniform_100k` | 100 000 lines, one row each | criterion 4's document size; the ∞-equivalent geometry |
| `narrow_100k` | 100 000 lines, several rows each | `totalRows >> lineCount`, so the two searches differ in depth — the only scenario where that separation is visible |
| `clamped_100k` | as above, queried past both edges | the branch Decision 7 routes through the layout search rather than short-circuiting |

`y` values come from the shared `deterministicIndex(sample:multiplier:modulus:)`
(`BenchmarkSupport.swift:27`), never from a clock, so the sweep is reproducible.

**Anti-dead-code guard.** A release build may delete a query whose result is
never read, and a mode that measures nothing still "runs" — AC9 alone would not
notice. The timed loop therefore folds every returned field into a printed
checksum: `globalRow`, `logicalLine` **and** `rowInLine`, each under a distinct
multiplier, in the `&*`/`&+` style the other query benchmarks use. Folding the
whole payload rather than one index is not belt-and-braces here:
`PointGeometryChecksumTests` exists precisely because a checksum once folded the
indices only, and a reversion to that shape passed silently.

**Output line shape.** The latency tokens are **prefixed** —
`mode=wrap_row_query scenario=<s> query_p95_ns=… query_p99_ns=…` — following
`--wrap-compute` (`WrapComputeBenchmark.swift:101` prints `compute_p95_ns=` /
`drain_p95_ns=`), not the bare `p95_ns=` / `p99_ns=` of a gated mode. This is
load-bearing, not cosmetic: the harvester matches `/p95_ns=[0-9]+/` as a
**substring** and only afterwards requires the exact keys
(`harvest-gate-corpus.sh:209–219`), so a prefixed line is inert by shape even if it
ever reaches a hosted log. Node 6 flips this to the bare shape in the same slice
that adds the gate step and the corpus rows — not before.

It is **not** added to `.github/workflows/swift-ci.yml`. Three reasons, in
increasing order of loudness:

1. Gate promotion for wrap modes is map node 6.
2. An un-gated mode printing summary lines in CI would put rows into every future
   harvest of that run — the "exactly one CI step may print a given mode's summary
   lines" rule. `--wrap-compute` set this precedent.
3. **It would fail the build, not merely skew a median.**
   `GateFloorTests.testEveryCommittedBudgetReproducesFromCorpus`
   (`GateFloorTests.swift:376`) asserts `derived.count == everyGatedBudget().count`
   — a *bijection* between corpus scenarios and registered gated budgets, chosen as
   equality rather than `>=` specifically to catch the reverse drift. One harvested
   `wrap_row_query` row reddens `swift test`, and the test's own comment names the
   escape hatch ("relax to `>=` only if a non-gated row is ever CONSCIOUSLY
   added"). This is the barrier worth knowing about, because it is the one that
   fires locally and immediately rather than silently biasing a future
   re-derivation.

Known and accepted: this makes a **fifth** non-gateable mode whose
`AbsoluteCeiling` class is pinned by nothing (D-20). The class-membership pin
filters on `isGateable`, so `.scrollFrame` here is a compile-time obligation, not
a pinned one. Inert until a wrap mode becomes gateable — which is node 6, where
D-20 is the row to read. D-20's statement is updated from four modes to five.

## Documentation Updates

- `AGENTS.md` — three edits, not one:
  1. the wrap section gains node 3's paragraph (the query, its two coordinate
     systems, its cost class, and the ∞ oracle);
  2. the flag list and the commands block gain `--wrap-row-query`, marked
     non-gateable alongside `--wrap-compute` — including the "`--gate` is
     **rejected** with …" enumeration;
  3. **`AGENTS.md:111` is corrected for the rename.** It currently reads
     "wrapped in `VisualRowQuery<Metrics>` — the first generic query enum", which
     after this slice describes a different type. Nothing in the build catches
     this: `WorkflowShapeTests` reads the workflow, not the architecture prose.
     It is one of the two prose sites AC3 names by path — the other is the `///`
     comment at `WrapTestSupport.swift:4`, which the compiler is equally blind to.
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift` — the two comments on the
  switches this slice edits, updated together with the switches themselves:
  `absoluteCeiling`'s "The four non-gateable modes …" (`:94`) becomes five, and
  `isGateable`'s "The three false cases have no budgets by nature …" (`:65–67`)
  becomes five as well. The latter is **already stale on `main`** — slice 50 added
  `wrapCompute` as a fourth `false` case and left the comment saying three. Folded
  in rather than left for a drive-by: this slice is editing that exact switch, so
  correcting it here is the line being touched, not unrelated churn.
- `docs/superpowers/debt-ledger.md` — new row for the uniform-axis O(1) hook
  (candidate slice, born this spec — recorded with **both** paths from Decision 2,
  since only one of them drags a budget re-derivation); D-20's statement updated
  four → five.
- `docs/superpowers/arcs/wrap.md` — the map pass belongs to the post-slice
  review, not this spec; the 2026-08-09 selection entry is already recorded.
- **Expected scoreboard delta**, stated here so this spec's non-goals are
  checkable even though writing the delta is the review's job: criterion 3 stays
  `partial` — the y→row analog lands, point→(row, cell) (node 4) remains open. No
  other criterion moves. Criterion 1's row-axis "not literally width-independent"
  correction stands unless Decision 2's internal-axis option is taken, which this
  slice declines.

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
  observational output, including the checksum line per scenario.
- `swift run -c release ViewportBenchmarks -- --wrap-compute` — recorded as a
  **smoke run only** (the binary runs, the mode completes), explicitly **not** as
  evidence about the Decision 5 extraction. An earlier draft of this spec claimed a
  before/after comparison of its output would prove the extraction behaviour-neutral.
  That check cannot fail, and the reasons are worth writing down so the next slice
  does not re-invent it:
  - `total_rows` is read straight off the provider
    (`WrapComputeBenchmark.swift:73` calls `layout.firstVisualRow(ofLine:)`
    directly), so it is byte-identical even if `compute(_:layout:)` is completely
    broken.
  - The drained rows are never printed: the loop folds `endColumn` into a `sink`
    that is discarded, and `:92`'s `print("")` fires only on `sink == Int.min` — a
    dead-code guard, not a value.
  - A `.failure` return is silent. `:85` is `if case .success(let r) = … { range = r }`
    with no `else`, so `range` keeps the zero-initialized `VirtualRange` from `:83`,
    the cursor yields nothing, and the only trace is a faster `drain_p95_ns` — the
    one field a latency-excluding comparison would ignore.

  The evidence about the extraction is AC4, and only AC4. The gated modes'
  checksums say nothing here either — wrap is not on their code path, so they are
  unchanged trivially.
- `swift run -c release ViewportBenchmarks -- --memory-shape` — `invariant=pass`.
- `./.github/scripts/cross-target-compile.sh --self-test` — **shell logic only.
  It compiles nothing** (it needs no toolchain, by design) and is therefore not
  portability evidence. This slice adds public core API, so the portability
  evidence is the two hosted jobs below.
- The **six** falsifiability drills, each with its observed red.
- Hosted proof at **step level** on both the PR-head run and the post-merge push
  run — not job conclusion (the Slice 16 dead-step lesson). Named explicitly, so
  "green" is not the claim: the host job's twelve `gate=pass` mode lines and the
  `swift test` count; the **iOS** job's two target compiles (`TextEngineCore` and
  `TextEngineReferenceProviders`); the **WASM** job's four
  `result=pass … blocking=true` lines (two kinds × two packages).
- **If the plan writes an AC-style checksum-extraction step**, it must carry
  D-18's fix: the literal `extract_checksums` recipe over a hosted log also matches
  the non-gate `memory_shape` (5) and `memory_observation` (3) diagnostic lines, so
  the count is 54 where a reader expects 46. D-18 names "whichever slice next
  writes an AC9 step" as its fold-in home — if this slice writes one, it is that
  slice.

## Acceptance Criteria

1. `ViewportVirtualizer.visualRowAt(y:layout:)` exists over any
   `VisualRowLayoutSource` and returns `VisualRowQuery`.
2. `VisualRowLocation` carries `globalRow`, `logicalLine`, `rowInLine`, and a
   reused `LineLocation.Clamp`.
3. Node 1's enum is renamed `VisualRowPackingQuery<Metrics>`; no other public
   behaviour changes with it. Both of the rename's **non-compiler-checked** sites
   are corrected in the same slice: `WrapTestSupport.swift:4` (a `///` doc comment)
   and `AGENTS.md:111`. A green build is not evidence for either, so they are
   enumerated by path rather than left to the compiler.
4. `compute(_:layout:)` and `visualRowAt` share one extracted layout ladder, and
   **all three** of node 2's wrap-compute suites pass **untouched**:
   `WrapComputeValidationTests` (error cases + precedence), `WrapComputeTests`
   (success-path ranges), `WrapComputeEquivalenceTests` (∞ oracle + empty
   document). This is the **only** evidence about the extraction — the
   `--wrap-compute` benchmark output cannot supply any, and Verification records
   why.
5. The accept/reject sets of the two entry points are equal, pinned by the
   ladder-parity test — and each side's per-error-case suite pins **presence**,
   which parity structurally cannot (Decision 5, drill 6).
6. The ∞ equivalence oracle passes **on the located branch**: at infinite (and at
   any finite width `>=` every line's total advance), `visualRowAt`'s `globalRow`,
   `logicalLine` (`== globalRow`), `rowInLine` (`== 0`) and clamp equal `lineAt`'s
   `lineIndex` and clamp over `UniformLineMetrics(lineCount, rowHeight)`. Scoped to
   the located branch deliberately: the two return different types and their
   failure/empty ladders differ by design (Decision 4).
7. The round-trip test passes against `DocumentVisualRowCursor` over a
   `compute(_:layout:)` range, probed at both the row boundary and the row
   interior.
8. Core memory is O(1); the layout-axis probe count is **logarithmic**, pinned at
   `<= ceilLog2(lineCount) + 4` by the query-count test, with clamped queries
   asserted **to** search (the no-wrap axis's two-probe constant does not carry
   over). The row-axis half is outside that harness by construction and is pinned
   by `LineAtQueryCountTests`; this criterion claims only what is pinned.
9. `--wrap-row-query` runs, is rejected with `--gate`, is rejected with another
   mode flag, and is absent from `swift-ci.yml`.
10. The benchmark cannot silently measure eliminated code: it prints a checksum
    folding `globalRow`, `logicalLine` **and** `rowInLine` under distinct
    multipliers, and its latency tokens are prefixed (`query_p95_ns=`), so the mode
    is inert to the harvester by shape as well as by absence from CI.
11. The Foundation-free scan is empty and the release build succeeds.
12. All **six** falsifiability drills are recorded with their observed red.
13. Hosted proof at step level on both the PR-head and post-merge runs, including
    the iOS job's two target compiles and the WASM job's four
    `result=pass … blocking=true` lines.

## Risks And Gaps

| Risk | Mitigation |
|---|---|
| The rename touches public API | Mechanical; no external consumers; the compiler finds all four code sites. It finds **neither** prose site — `WrapTestSupport.swift:4` (a `///` comment) nor `AGENTS.md:111` — so both are enumerated by path in Decision 9 and AC3. A green build is not evidence for a rename's prose |
| A check deleted from the shared ladder leaves parity green | Parity sees divergence, not absence. Presence is pinned by each side's per-error-case suite, and drill 6 records the red from both (Decision 5) |
| The observational benchmark measures code the optimizer removed | A printed checksum folding all three returned fields under distinct multipliers (AC10) — the `PointGeometryChecksumTests` lesson applied up front rather than after |
| A future harvest ingests `wrap_row_query` rows | Three independent barriers: absent from CI; latency tokens prefixed, so the harvester's line regex still matches but its exact-key extraction (`kv[1] == "p95_ns"`) yields nothing and no row is emitted; and `GateFloorTests.testEveryCommittedBudgetReproducesFromCorpus` fails the build on a bijectivity break |
| The query-count test is read as covering both searches | It cannot — the row axis runs over a core-constructed `UniformLineMetrics`. Stated in the Testing Strategy and scoped in AC8, with the row-axis half pinned by `LineAtQueryCountTests` |
| The ladder extraction touches shipped node-2 code | Behaviour-identical by construction; proof is all **three** node-2 wrap-compute suites passing untouched (AC4) — validation alone would miss a helper that returns a wrong `totalRows` while every error case still resolves. The `--wrap-compute` benchmark contributes nothing here and Verification says why |
| Floating-point: `y` near an exact row boundary | The half-open boundary test; the row-axis comparison is `lineAt`'s, unchanged and already covered on the no-wrap axis |
| A gated benchmark drifts | This slice touches no gated code path; the twelve gates run in verification precisely so drift is visible |
| `${PIPESTATUS[0]}` in the plan's own assertions | **D-17**: the idiom `AGENTS.md` rule 1 recommends expands empty under zsh and inverts the assertion into a pass. The plan must use `if ! cmd; then … fi` instead. Carried as an explicit plan instruction |

**Gap left open deliberately:** the O(1) uniform-axis hook (Decision 2). It is
recorded as a ledger row and a candidate slice, not silently dropped — it would
make wrap compute *literally* width-independent on the row axis, a strengthening
of criterion 1's wording. The public-`UniformLineMetrics` path drags a gate
re-derivation that does not belong in a wrap-query slice; the **internal**-axis
path does not, and is recorded beside it so the future slice chooses rather than
inherits. What this slice declines is the floating-point ±1 correction *design* —
not one particular implementation of it, and not the goal.

## Future Slices (arc map, for reference)

- **node 4** — point→(row, cell): the 2D wrap composite, composing this query
  with the horizontal axis. Criterion 3's third analog.
- **geometry companion** — row span + `y`/`height` + within-row fraction, on the
  27→31 pattern.
- **uniform-axis O(1) hook** — Decision 2, on either of its two recorded paths
  (public + budget re-derivation, or internal wrap-only + none); folds in D-13.
- **node 5** — `--memory-shape` extended to the wrap path. Criterion 2.
- **node 6** — wrap modes promoted to blocking gates. Criterion 4; the slice
  where D-20 stops being inert.
