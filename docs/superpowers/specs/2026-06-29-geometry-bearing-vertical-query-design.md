# Geometry-Bearing Vertical Query (`lineGeometryAt(y:)`) Design

Slice 31 — return to functional core after the Slice 27→30 vertical-axis arc
(`lineAt` capability → CI gate → `lineAt` native → `compute` native).

## Status

Proposed. Brainstormed 2026-06-29; recommended by the Slice 30 post-slice review
(Option A — geometry-bearing vertical query) and selected by the user over the
A-vs-C product call (deepen the vertical axis toward editing affordances rather
than open the horizontal/wrap axis).

## Source Context

The brief (`docs/initial-project-brief.md`) wants a headless
layout/virtualization core that supports realistic editing/scrolling of 100k+
line / >10 MB documents, stays Foundation-free and Embedded-compatible, and keeps
core-owned memory sub-linear in document size.

Slice 27 added the public **y → line** mapping
`ViewportVirtualizer.lineAt(y:metrics:) -> LineQuery`, returning `lineIndex` +
a `clamp` flag and nothing more. Its own design explicitly deferred geometry:

> **No within-line fractional offset / geometry in the result.** The result is
> `lineIndex` + clamp status; a caller wanting the line's span derives it from the
> existing `offset(ofLine:)`. (Considered and deferred — see Risks And Gaps.)

and named the follow-up precisely (Slice 27 "Future Slices"):

> **Geometry-bearing / point queries**: a richer result with the located line's
> span ... added as a new method/result type, not a new `LineQuery` case.

Slices 28→30 then completed the vertical-axis **performance** arc: `--line-query`
became a blocking hosted gate (28), and both `lineAt` (29) and `compute` (30)
became single O(log N) subtree-sum descents over `BalancedTreeLineMetrics`. The
Slice 30 review found the vertical-query *optimization* thread complete and handed
off to a pivot from optimization to capability. This slice is the first step of
that pivot: surface the geometry that `lineAt` already locates.

## Problem

`lineAt` answers *"which line?"*. The next thing every tap-to-caret / selection /
hit-test consumer needs is *"which line, and where within it?"* — the located
line's vertical box (top `y`, height) and how far the query point falls into that
box. Today a caller must:

1. call `lineAt(y:)` for the index + clamp, then
2. issue its own `offset(ofLine: i)` / `offset(ofLine: i+1)` queries to rebuild the
   box, then
3. re-derive the within-line fraction, re-implementing the clamp/boundary
   conventions the core already owns.

That re-implementation is exactly the duplication Slice 27 set out to remove for
the index. The core should own the geometry-bearing form too, as the authoritative
companion to `lineAt`, with the same validation discipline, the same boundary and
clamp conventions, and the same O(log N) / O(1)-core-memory envelope.

## Scope

Add a single public, stateless query to `TextEngineCore`:

> Given a document `y` offset and a `LineMetricsSource`, return the located line's
> **box** (index, top `y`, height) **plus** the within-line fraction of `y`, with
> the same clamp flag `lineAt` returns.

Plus its equivalence-oracle and unit tests, a `--line-geometry-query` benchmark
mode with a **local** `--gate`, and the slice paper trail. No rendering, no
horizontal axis, no wrap, no provider change, no change to `lineAt` / `compute`.

## Goals

- Public `ViewportVirtualizer.lineGeometryAt(y:metrics:) -> LineGeometryQuery` over
  the general `LineMetricsSource` path, the geometry-bearing companion to
  `lineAt(y:metrics:)`.
- **Index + clamp parity with `lineAt` by construction** — `lineGeometryAt`
  delegates to `lineAt` for the located line and clamp, so the two can never drift
  on boundary/clamp conventions.
- **O(log N) provider calls, O(1) core memory.** `lineGeometryAt` adds only a
  *constant* number of `offset(ofLine:)` probes (the box top/bottom) on top of
  `lineAt`'s index search — no new search, no provider protocol change — so it never
  adds a log factor and its per-provider wall-clock **equals `lineAt`'s**: O(log N)
  for O(1)-offset providers and for the balanced tree (Slice 29 native index
  descent), but O(log^2 N) for `FenwickLineMetrics` (O(log N) `offset` + generic
  fallback index search, inherited from `lineAt`). See Decision 4 for the full
  per-provider breakdown.
- Validation parity with `lineAt`/`compute`: up-front, return-based (no `throws`),
  Foundation-free, reusing the existing `ViewportValidationError`.
- An **equivalence oracle**: over `BalancedTreeLineMetrics`, `lineGeometryAt`'s
  index/clamp equal `lineAt`'s and its `geometry`/`fractionInLine` equal the values
  rebuilt from a `PrefixSumLineMetrics` oracle's `offset(ofLine:)` across a scroll
  sweep — the same "provably matches the offset-derived expectation" discipline the
  project uses for `compute` and `lineAt`. Plus a **structural uniform oracle**
  (products, not quotients) for boundary-exact `y`.
- A `--line-geometry-query` benchmark mode + local `--gate` with macOS-calibrated
  budgets, following the established functional-slice rhythm.
- Foundation-free, Embedded-compatible, zero-dependency; iOS/WASM cross-target
  compile unchanged.

## Non-Goals

- **No horizontal axis** (no `x`, width, or `pointAt(x:y:)`). This slice is
  strictly the vertical geometry. Horizontal/point queries remain a future slice.
- **No wrap / visual rows.** The unit stays the logical line.
- **No glyph/caret/column mapping.** The result stops at the line box + within-line
  fraction; mapping the fraction to a caret/row/glyph is downstream of this slice.
- **No provider-native richer descent.** `lineGeometryAt` composes over the
  existing `lineAt` + `offset(ofLine:)` primitives; it adds **no** new
  `LineMetricsSource` requirement. A native one-walk `(index, top, bottom)` descent
  is a deferred optimization (Future Slices), mirroring the Slice 27 (capability) →
  Slice 29 (native) split for `lineAt`.
- **No change to `lineAt`, `compute`, the provider protocol, or `LineQuery`.** The
  geometry-bearing form is **additive** — a new method and new result type. It is
  **not** a new case on the existing `LineQuery` enum (source-breaking for client
  `switch`es; the same non-breaking-extension rule Slice 27 set).
- **No fixed-height overload.** One metrics-based entry point only, matching
  `lineAt`.
- **No CI promotion.** The `--line-geometry-query --gate` runs locally only this
  slice; promoting it to a blocking hosted gate is a separate follow-up slice
  (the recommended Slice 32), exactly as `--line-query` → Slice 28.

## Decisions

### Decision 1 — Result shape: `LineGeometryQuery` / `LineGeometryLocation`

The query returns a three-case result enum mirroring `LineQuery`'s
located/empty/failure discipline, carrying a new location struct that **reuses**
the existing `LineGeometry` and `LineLocation.Clamp` types:

```swift
public enum LineGeometryQuery: Equatable {
    case geometry(LineGeometryLocation)   // a real line was located, with its box
    case empty                            // document has zero lines (not an error)
    case failure(ViewportValidationError) // invalid input / metrics
}

public struct LineGeometryLocation: Equatable {
    /// The located line's box: lineIndex, top y, height. (Existing core type,
    /// also produced by the geometry cursor.)
    public let geometry: LineGeometry
    /// Where `y` falls within the line's vertical span. `0.0` at the line top;
    /// `(y - geometry.y) / geometry.height` in `[0, 1)` for an in-range query;
    /// `0.0` when clamped to top; `1.0` when clamped to bottom. See Decision 3.
    public let fractionInLine: Double
    /// Whether the query landed inside the document or past an edge — the same
    /// flag `lineAt` returns (reused, not duplicated).
    public let clamp: LineLocation.Clamp

    public init(geometry: LineGeometry, fractionInLine: Double, clamp: LineLocation.Clamp) {
        self.geometry = geometry
        self.fractionInLine = fractionInLine
        self.clamp = clamp
    }
}
```

Rationale:

- The new surface is intentionally **two new public types only** (`LineGeometryQuery`,
  `LineGeometryLocation`). The line box reuses `LineGeometry` (already public,
  already what `VariableLineGeometryCursor` streams), and the clamp flag reuses
  `LineLocation.Clamp` — so the geometry-bearing query, `lineAt`, and the geometry
  cursor all speak one vocabulary for "a line's box" and "edge clamp state".
- The **`.empty` / `.failure` cases parallel `LineQuery`** exactly, so the two query
  results are switched the same way and validation outcomes map 1:1.
- `fractionInLine` is a **convenience the core defines centrally** rather than
  leaving every caller to recompute `(y - top) / height` and re-decide what it
  means at the clamped edges. Centralizing it is the point: the clamp-edge fraction
  contract (Decision 3) lives in one place.

### Decision 2 — One metrics-based entry point, composed over `lineAt`

`lineGeometryAt` is a single generic over `LineMetricsSource`, alongside `lineAt`:

```swift
extension ViewportVirtualizer {
    public static func lineGeometryAt<Metrics: LineMetricsSource>(
        y: Double, metrics: Metrics
    ) -> LineGeometryQuery
}
```

There is **no** fixed-height overload (parity with `lineAt`, Decision 2 there).

The implementation **delegates to `lineAt(y:metrics:)`** for validation, the
located index, and the clamp flag, then attaches geometry only on the `.line`
branch:

```
lineGeometryAt(y, metrics):
    switch lineAt(y, metrics):
        case .failure(e): return .failure(e)        // validation single-sourced
        case .empty:      return .empty              // no line, no geometry
        case .line(loc):
            top    = metrics.offset(ofLine: loc.lineIndex)
            bottom = metrics.offset(ofLine: loc.lineIndex + 1)
            box    = LineGeometry(lineIndex: loc.lineIndex, y: top, height: bottom - top)
            frac   = fraction(y, box, loc.clamp)     // Decision 3
            return .geometry(LineGeometryLocation(geometry: box,
                                                  fractionInLine: frac,
                                                  clamp: loc.clamp))
```

Rationale — composing over `lineAt` rather than re-deriving:

- **Parity by construction.** Index, clamp, and the entire validation ladder come
  straight from `lineAt`; `lineGeometryAt` cannot disagree with `lineAt` on which
  line / which clamp. The equivalence oracle then only has to pin the *geometry*.
- **No new search, no provider change.** The located index already came from the
  (possibly provider-native) `lineIndex(containingOffset:)` inside `lineAt`. The two
  extra `offset(ofLine:)` probes for `top`/`bottom` reuse the existing offset
  contract.
- The two extra `offset` probes are accepted (Decision 4) rather than threaded out
  of the search: a native one-walk `(index, top, bottom)` descent is a deferred
  optimization, not this slice.

### Decision 3 — Within-line fraction + clamp contract

Lines occupy half-open vertical spans `[offset(i), offset(i+1))` (the convention
`lineAt`/`compute` already use). `lineGeometryAt` reports, for the located line's
box `(top, height)`:

| `y` | `clamp` (from `lineAt`) | `geometry` | `fractionInLine` |
| --- | --- | --- | --- |
| `y < 0` | `clampedToTop` | line 0's box | `0.0` |
| `0 <= y < totalHeight` | `inRange` | located line's box | `(y - top) / height`, in `[0, 1)` |
| `y >= totalHeight` | `clampedToBottom` | last line's box | `1.0` |
| `lineCount == 0` | — | — | (result is `.empty`) |

Notes:

- The **in-range fraction is the exact arithmetic ratio** `(y - top) / height`, not
  artificially clamped, so the relation `y == top + fractionInLine * height` holds
  for in-range queries (modulo floating-point). It is in `[0, 1)` by the half-open
  contract (`top <= y < bottom`); at an exact line top `y == top` it is `0.0`. (At
  `y` extremely close to `bottom`, floating-point may round the ratio up toward
  `1.0`; the core does not special-case this, consistent with how the rest of the
  engine trusts the `offset` contract.)
- The **clamp edges report sentinel fractions** `0.0` (top) and `1.0` (bottom)
  rather than an out-of-box ratio: a tap above the document caret-positions at the
  very top of line 0, a tap below it at the very bottom of the last line. `1.0` is
  the only way `fractionInLine` reaches `1.0` — it never does for `inRange`.
- `geometry.height = bottom - top` is finite and strictly positive by the
  `LineMetricsSource` contract (`offset` is a strictly increasing chain). No
  zero-height special case is needed for a valid provider.

### Decision 4 — Cost: O(log N) queries, O(1) core memory; two extra offset probes accepted

`lineGeometryAt` issues `lineAt`'s `offset(ofLine:)` queries plus **two** more
(`offset(ofLine: i)`, `offset(ofLine: i+1)`) on the located branch. Per path:

| `lineGeometryAt` path | `offset(ofLine:)` count |
| --- | --- |
| **non-finite `y`** | `0` — `lineAt` fails before any probe; no geometry |
| **empty** (`lineCount == 0`) | `1` — `lineAt`'s `offset(0)` probe, then `.empty`; no geometry |
| **clamp** (`y < 0` or `y >= total`) | `4` — `lineAt`'s `offset(0)` + total `= 2`, plus the two geometry probes |
| **in-range**, 1M lines | `lineAt`'s `2 + (ceilLog2(n) + 1)` + `2` geometry probes; and `< 100` |

So the query count stays **`O(log N)`** (a constant number of `offset(ofLine:)`
probes plus `lineAt`'s single index search) and core memory stays **`O(1)`**.
Wall-clock is `O(log N x offsetCost)`. Crucially, `lineGeometryAt`'s two extra
probes are a **constant factor**, so its per-provider asymptotic class is exactly
`lineAt`'s — the geometry probes never introduce a log factor:

- `UniformLineMetrics` / `PrefixSumLineMetrics` answer `offset` in O(1) and run
  `lineAt`'s index search as an O(log N) binary search over O(1) probes →
  **O(log N)**.
- `BalancedTreeLineMetrics` answers `offset` in O(log N) (one tree descent,
  `BalancedTreeLineMetrics.swift:47`) but answers `lineAt`'s index search with its
  Slice 29 **native** O(log N) descent, so the whole query is a *constant* number of
  O(log N) descents (~ `offset(0)`, total, native index, `offset(i)`,
  `offset(i+1)`) → **O(log N)**. (Unlike Slice 27's pre-native `lineAt`, there is no
  O(log^2 N) path for the balanced tree.)
- `FenwickLineMetrics` answers `offset` in O(log N)
  (`FenwickLineMetrics.swift:45`) and does **not** override
  `lineIndex(containingOffset:)`, so `lineAt`'s index search is the generic binary
  search (`LineMetricsSource.swift:47`) paying an O(log N) `offset` per probe →
  **O(log^2 N)**. This is inherited from `lineAt`/`compute`'s existing Fenwick cost;
  the two added geometry probes contribute only O(log N) more (a constant factor),
  not the log factor.

A native one-walk `(index, top, bottom)` descent (Future Slices) would cut the
balanced tree's constant (~5 descents → ~2); a Fenwick native index override is the
separate, already-known route that would take *its* path to O(log N).

### Decision 5 — Local gate now, CI promotion deferred (established rhythm)

This functional slice ships the `--line-geometry-query` benchmark mode **and**
local `--gate` enforcement with macOS-calibrated budgets, but does **not** wire the
gate into `.github/workflows/swift-ci.yml`. Promotion to a blocking hosted gate is
the recommended follow-up Slice 32, identical to the project's five prior
functional → promotion pairs (variable-height → 15, variable-height-mutation → 21,
structural-mutation → 24, bulk-structural-mutation → 26, line-query → 28).

`--gate` becomes valid with `--line-geometry-query` (added to the gateable set
alongside the pipeline, realistic-provider, variable-height,
variable-height-mutation, structural-mutation, bulk-structural-mutation, and
line-query modes); it remains rejected with `--range-only`, `--memory-shape`, and
`--memory-observation`. Only one mode flag at a time.

`AGENTS.md` gains the new local command and the `--line-geometry-query` flag; its
CI section is unchanged because the workflow is unchanged.

## Component Design

### Extend `Sources/TextEngineCore/PositionQuery.swift`

Add `lineGeometryAt(y:metrics:)` to the existing `extension ViewportVirtualizer`
that already holds `lineAt`, plus a tiny private fraction helper. It:

1. Calls `lineAt(y:metrics:)` and switches on the result.
2. Maps `.failure(e)` and `.empty` straight through (validation never duplicated).
3. On `.line(loc)`, reads `top`/`bottom` via `offset(ofLine:)`, builds the
   `LineGeometry` box, computes `fractionInLine` per the Decision 3 clamp branch,
   and returns `.geometry(...)`.

Keeping it in `PositionQuery.swift` next to `lineAt` keeps the two y→line queries
co-located.

### Types added to `Sources/TextEngineCore/ViewportTypes.swift`

`LineGeometryQuery` and `LineGeometryLocation` (Decision 1), alongside the existing
`LineQuery` / `LineLocation` / `LineGeometry` definitions, so the public vocabulary
stays in one file. No change to existing types.

### No search change; provider code untouched (one doc-comment update)

`VariableViewportVirtualizer` and the `TextEngineReferenceProviders` providers are
untouched — no signature or behavior change. `lineGeometryAt` only consumes the
existing `lineAt` + `offset(ofLine:)` surface and adds **no** `LineMetricsSource`
requirement. The single provider-protocol touch is a **doc-comment** update to the
`offset(ofLine:)` stability precondition — see Documentation Updates.

## Documentation Updates

- **`Sources/TextEngineCore/LineMetricsSource.swift` stability precondition.** The
  `offset(ofLine:)` stability precondition currently scopes its
  "stable for one layout/query operation" guarantee to "a `compute`, a `lineAt`, and
  any `VariableLineGeometryCursor` traversal derived from a range it produced".
  `lineGeometryAt` issues several `offset(ofLine:)` queries (via `lineAt` plus the
  two geometry probes) that must observe one consistent snapshot. Add
  `lineGeometryAt` to the enumeration: "... a `compute`, a `lineAt`, a
  `lineGeometryAt`, and any `VariableLineGeometryCursor` traversal ...". Comment
  only; no signature or behavior change. (Slice 27 made the identical update when it
  added `lineAt`.)
- **`AGENTS.md`.** Add `lineGeometryAt` to the architecture paragraph as the
  geometry-bearing companion to `lineAt` — the y→(line index + box + within-line
  fraction) query — and add the `--line-geometry-query` /
  `--line-geometry-query --gate` commands and flag to the Commands and
  benchmark-flags lists. The CI section is unchanged (no workflow change,
  Decision 5).

## Testing Strategy

XCTest only, TDD failing-first. Split by the providers each test needs (the
Slice 30 placement lesson: a test that needs reference providers lives in the
reference-provider test target).

### Core tests (`Tests/TextEngineCoreTests`)

**Structural uniform oracle (load-bearing, products not quotients).** Mirrors the
Slice 27 `lineAt` oracle to dodge the `floor(y/lineHeight)` boundary fragility:
pick `lineHeight` from the exactly-representable set
(`[1.0, 10.0, 16.0, 12.5, 256.0]`), `lineCount` well under `2^53`, **build each `y`
from a product**, and assert the full `LineGeometryQuery`:

| Constructed `y` | Expected result |
| --- | --- |
| `-lineHeight` | `.geometry(box=(0, 0, h), frac=0.0, clampedToTop)` |
| `Double(k) * h` for `k in {0, 1, lineCount/2, lineCount-1}` | `.geometry(box=(k, k*h, h), frac=0.0, inRange)` |
| `Double(k) * h + h/2` for `k < lineCount` | `.geometry(box=(k, k*h, h), frac=0.5, inRange)` |
| `Double(lineCount) * h` (total) | `.geometry(box=(lineCount-1, (lineCount-1)*h, h), frac=1.0, clampedToBottom)` |
| `Double(lineCount) * h + h` | `.geometry(box=(lineCount-1, (lineCount-1)*h, h), frac=1.0, clampedToBottom)` |

Run for several `(lineCount, lineHeight)` including `lineCount == 1`. Because every
`y` is a product over a representable height, box `y`/`height` and the fraction are
known by construction.

**Parity with `lineAt`.** For a swept set of `y`, assert
`lineGeometryAt(y).…lineIndex == lineAt(y).…lineIndex` and the clamp flags match —
the construction guarantee, pinned as a regression test.

**Unit / edge tests:**

- **Empty document** (`lineCount == 0`) → `.empty` for any `y`.
- **Failure ladder** (reached via `lineAt`): `negativeLineCount`; non-finite `y`
  (`.nan`, `+/-inf`); a provider with `offset(ofLine: 0) != 0` →
  `.invalidLineMetrics`; a provider with total height `0`/non-finite →
  `.invalidLineMetrics`. (The three fixed-/viewport-specific
  `ViewportValidationError` cases remain unreachable, as for `lineAt`.)
- **Fraction at exact line top** `y == offset(i)` → `frac == 0.0`, `inRange`,
  box top `== offset(i)`.
- **Fraction mid-line** → `frac == 0.5` for a `y` at the span midpoint.
- **Clamp fractions**: `y < 0` → `0.0` + line 0 box; `y >= total` → `1.0` + last
  line box; `y == 0` → `inRange`, `frac 0.0`; `y == total` → `clampedToBottom`,
  `frac 1.0`.
- **Single-line document**: in-range `y` → line 0 box, fraction in `[0,1)`; clamps
  as above.

**Query-count tests** (`CountingLineMetrics`, the existing harness): assert the
exact `offset(ofLine:)` counts per path from the Decision 4 table — non-finite `0`,
empty `1`, clamp `4`, in-range `<= 2 + (ceilLog2(n)+1) + 2` and `< 100`. Proves the
O(log N) query / O(1) memory envelope and that no accidental linear scan crept in.
(Over `CountingLineMetrics`, whose `lineIndex` falls back to the binary search, the
in-range count includes the `ceilLog2(n)+1` fallback probes.)

**Native-hook dispatch + order test** (`NativeSearchMetrics`, the existing ordered
event-log harness behind `testLineAtDispatchesToNativeHookAfterValidationProbes`,
`LineAtQueryCountTests.swift:138`). Proves `lineGeometryAt` reuses `lineAt`'s
**native** index dispatch and then takes exactly the two geometry probes, in order.
For an in-range `y` over a small `NativeSearchMetrics`
(offsets `[0, 10, 30, 35, 80]`, `y = 31` → line 2), assert the event log is
`[.offset(0), .offset(4), .native(31.0), .offset(2), .offset(3)]` — i.e. `lineAt`'s
`offset(0)` + total-height probes, its native index search, then `offset(i)` /
`offset(i+1)` for the box. This is the load-bearing proof (the Slice 29 lesson) that
the composed query does **not** silently fall back to a generic search or re-search
redundantly — and it directly exhibits the Decision 4 constant-descent-count
(hence O(log N), not O(log^2 N)) shape over a native provider.

### Reference-provider equivalence oracle (`Tests/TextEngineReferenceProvidersTests`)

Mirrors the Slice 30 compute-equivalence oracle. Build the same heights into a
`BalancedTreeLineMetrics` and a `PrefixSumLineMetrics` oracle; across a scroll
sweep (top, bottom, interior, exact line-tops, fractional offsets, out-of-range
above/below) assert:

- `lineGeometryAt(balanced).clamp == lineAt(oracle).clamp` and the indices match;
- `geometry == LineGeometry(i, oracle.offset(i), oracle.offset(i+1) - oracle.offset(i))`;
- `fractionInLine` equals the value recomputed from the oracle's offsets under the
  Decision 3 contract (exact `0.0`/`1.0` at the clamp edges).

Optionally re-assert after a few `setHeight`/`insertLine`/`removeLine` mutations so
the geometry tracks the mutated tree (reuses existing mutation helpers). This is
the provider-level proof that the composed geometry is byte-consistent with
`offset(ofLine:)`.

### No behavior change to existing code

`lineGeometryAt` adds code; it changes none. The existing `lineAt`, `compute`,
variable-height, structural, bulk, and line-query suites and gates must pass
**unchanged** (no checksum movement) — this slice touches no shared search or
provider path, so that is expected, not a refactor-preservation obligation.

## Benchmark Mode (`ViewportBenchmarks`)

New file `Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift`, modeled on
`LineQueryBenchmark.swift`:

- **Mode**: add `.lineGeometryQuery` to `BenchmarkMode`
  (`outputName = "line_geometry_query"`), `--line-geometry-query` to
  `BenchmarkOptions.parse`/usage, a `runLineGeometryQueryBenchmarks` arm in the
  program, and `.lineGeometryQuery` to the `--gate`-valid set.
- **Scenarios**: large synthetic docs (`1k`, `100k`, `1m`), each with `p95`/`p99`
  budgets, reusing the `--line-query` scenario shape. **Must include at least one
  `provider=balanced_tree` scenario** (the realistic O(log N)-`offset` path: still
  O(log N) overall, but with a higher per-query constant than the O(1)-offset
  providers because each descent — including the two added geometry probes — pays a
  tree walk; a uniform-only suite would under-measure that constant and the future
  native-hook win), plus a uniform / O(1) baseline. Optionally add a
  `provider=fenwick` scenario to also exercise the **O(log^2 N)** generic-fallback
  path (Fenwick's `offset` is O(log N) and it has no native index override) — this
  is `lineAt`/`compute`'s existing Fenwick cost, inherited and not new to this slice,
  so it is recommended-not-required, mirroring `--line-query` (which likewise
  benchmarks uniform + balanced_tree only).
- **Workload**: per operation derive a deterministic `y` spanning in-range and
  both out-of-range clamp branches (reuse `deterministicScrollOffset` / a
  deterministic fraction of `totalHeight`, with a slice pushed below 0 and above
  `totalHeight`), call `lineGeometryAt(y:metrics:)`, and fold `geometry.lineIndex`,
  an integer encoding of the `clamp` case, and a quantized `fractionInLine` (e.g.
  `Int(fractionInLine * 1_000_000)`) into a running **checksum** (determinism
  guard, matching every other benchmark).
- **Gate**: `--line-geometry-query --gate` enforces `p95`/`p99` and exits non-zero
  on regression; without `--gate` it asserts `failureCount == 0`. Budgets are
  macOS-calibrated; the plan records observed numbers and sets budgets with the
  project's customary headroom.

## CI

**No `.github/workflows/swift-ci.yml` change.** The `--line-geometry-query --gate`
is a local gate this slice (Decision 5). Required job contexts, docs-only path,
iOS/WASM jobs, and the `Main` ruleset are unchanged. CI promotion is the
recommended Slice 32.

## Verification

Recorded in
`docs/superpowers/verification/2026-06-29-geometry-bearing-vertical-query.md`:

- `swift test` — host unit tests (new oracles + unit + query-count tests green;
  existing suite count grows, 0 failures).
- `swift build -c release`.
- `swift run -c release ViewportBenchmarks -- --line-geometry-query --gate` → every
  scenario `gate=pass`; record p95/p99 and checksums.
- Existing gates still green: `--gate`, `--variable-height --gate`,
  `--variable-height-mutation --gate`, `--structural-mutation --gate`,
  `--bulk-structural-mutation --gate`, `--line-query --gate` (no checksum movement
  expected — nothing shared was touched).
- `--memory-shape` invariant `pass` (the new query is O(1) memory).
- Foundation-free scans: `rg -n "Foundation" Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders` → empty (exit 1).
- `./.github/scripts/cross-target-compile.sh --self-test`, then iOS (blocking) and
  WASM (observational) cross-target paths for both `TextEngineCore` and
  `TextEngineReferenceProviders` (public-API change → cross-target verify).
- Hosted PR run + post-merge push run IDs, verified at **step level**, recorded in
  the post-merge follow-up (the Slice 26 stale-on-write lesson: anchor the
  PR-head proof against the stable final head in the post-merge doc).

## Acceptance Criteria

1. `ViewportVirtualizer.lineGeometryAt(y:metrics:) -> LineGeometryQuery` is public,
   stateless, and behaves exactly per the Decision 3 table.
2. Index + clamp parity with `lineAt` holds across the swept `y` set (by
   construction, pinned by test).
3. The structural uniform oracle passes: box `y`/`height` and `fractionInLine`
   equal the product-built expectation across the full `y` sweep over
   exactly-representable heights, for multiple `(lineCount, lineHeight)` including
   `lineCount == 1`.
4. The reference-provider equivalence oracle passes: over `BalancedTreeLineMetrics`,
   geometry and fraction equal the `PrefixSumLineMetrics`-oracle-derived values
   across the scroll sweep (and after the mutation re-assert, if included).
5. All unit / failure / clamp-fraction tests pass; `.empty` and all
   `lineAt`-reachable validation outcomes are covered.
6. The query-count tests pass with the exact per-path `offset(ofLine:)` counts in
   the Decision 4 table (non-finite `0`, empty `1`, clamp `4`,
   in-range `<= 2 + (ceilLog2(n)+1) + 2` and `< 100`).
6a. The native-hook dispatch + order test passes: in-range `lineGeometryAt` over
   `NativeSearchMetrics` produces the event log
   `[.offset(0), .offset(lineCount), .native(y), .offset(i), .offset(i+1)]`,
   proving native index dispatch + exactly two ordered geometry probes.
7. `--line-geometry-query` benchmark runs; `--line-geometry-query --gate` enforces
   budgets and is rejected only where the other gateable modes are accepted;
   `--gate` stays rejected with `--range-only`/`--memory-shape`/`--memory-observation`;
   only one mode flag at a time.
8. Existing gates and suites pass unchanged (no checksum movement);
   `--memory-shape` invariant `pass`.
9. Foundation-free scans empty; iOS cross-target compile green (blocking); WASM
   observational.
10. Full paper trail (spec, plan, verification, post-slice review) on a
    `slice-31-geometry-bearing-vertical-query` branch; one PR; conventional commits.

## Risks And Gaps

### Two extra `offset` probes on the located path (constant factor, deferred native hook)

`lineGeometryAt` issues two more `offset(ofLine:)` probes than `lineAt`. For O(1)-
offset providers this is free; for `BalancedTreeLineMetrics` it is two extra
O(log N) tree descents — a **constant factor** on top of `lineAt`'s descents, so the
geometry path stays **O(log N)** wall-clock (it does **not** become O(log^2 N): the
probes are a fixed count, not a binary search whose every step pays an `offset`).
For `FenwickLineMetrics` the path *is* O(log^2 N), but that is `lineAt`'s inherited
generic-fallback cost (Decision 4), not something these two probes introduce.
A future slice can still add a provider-native one-walk `(index, top, bottom)` hook
(default = the composed form) overridden on the balanced tree, folding the ~5
descents into ~2 — a constant-factor win, the Slice 27 → Slice 29 pattern applied to
geometry, made measurable by the balanced-tree benchmark scenario. Out of scope here
(Non-Goals).

### Budgets are macOS-calibrated and local-only

Like every gate before CI promotion, the `--line-geometry-query` budgets are
macOS-derived and unenforced in hosted CI until Slice 32. A regression would be
caught locally but not block merge until promotion. Established rhythm; accepted,
time-boxed gap.

### Floating-point at the in-range upper edge

The in-range `fractionInLine = (y - top) / height` is the exact ratio and is in
`[0, 1)` mathematically, but for `y` extremely close to `bottom` floating-point may
round it toward `1.0`. The core does not special-case this (consistent with how the
engine trusts the `offset` contract elsewhere); `1.0` as a *clamp* sentinel and a
`1.0` produced by extreme-edge rounding are not distinguished. Documented, accepted.

### Additive public surface

Two new public types (`LineGeometryQuery`, `LineGeometryLocation`) plus one method
widen the API. This is the intended capability growth and is non-breaking (new
method + new types, not a new `LineQuery` case), per the Slice 27 extension rule.

## Future Slices

- **Slice 32 (recommended next): promote `--line-geometry-query --gate` to a
  blocking hosted CI gate**, completing the functional → promotion pair, exactly as
  Slices 15 / 21 / 24 / 26 / 28 did for the prior five modes.
- **Provider-native geometry-bearing descent (constant-factor: ~5 descents → ~2)**:
  an optional `LineMetricsSource` hook returning `(index, top, bottom)` in one tree
  walk, default-implemented as today's composed form, overridden by
  `BalancedTreeLineMetrics` — the Slice 29/30 defaulted-hook + provider-override +
  dispatch-test recipe applied to geometry. This trims the constant, **not** the
  asymptotic class (the composed path is already O(log N)).
- **Verified closed-form uniform override** (carried Slice 29/30 P3): O(1) overrides
  for the uniform/prefix-sum providers' native hooks, boundary-safe against the
  equivalence oracles.
- **Horizontal axis / point queries / wrap-aware visual rows**: the larger product
  leaps (Option C), each needing its own brainstorm. `pointAt(x:y:)` would build on
  this slice's vertical `LineGeometryLocation`.
