# Variable-Height Layout Foundation Design

Date: 2026-06-10

## Status

Approved design.

## Source Context

This design is Slice 14 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slices 1 through 13 built and de-risked the fixed-height proof envelope:

- fixed-height viewport virtualization (`ViewportVirtualizer.compute`);
- an external document/source provider contract (`DocumentLineSource`) and
  range traversal (`DocumentLineCursor`);
- fixed-height per-line geometry (`LineGeometryCursor`, emitting `LineGeometry`);
- a synthetic p95/p99 benchmark gate that blocks on regression;
- a realistic 100,000-line, 11.2 MB provider benchmark;
- a core-owned memory-shape invariant and an RSS memory observation;
- GitHub Actions host tests plus, from Slice 13, continuous and blocking iOS
  cross-target compile CI (with a best-effort, currently-skipped WASM probe).

Every layout computation in the core today is derived from a single constant
`lineHeight`. `ViewportVirtualizer.compute` finds the visible range with O(1)
arithmetic (`floor(scrollOffsetY / lineHeight)`, etc.), and `LineGeometryCursor`
emits each line's geometry as `y = lineIndex * lineHeight`, `height = lineHeight`.
The constant-height assumption is therefore baked into the whole layout surface.

Slice 14 is the deliberate pivot from proof closure to functional expansion
recommended by the Slice 11, 12, and 13 reviews: it introduces variable-height
line layout. This is the largest deferred functional capability and the clearest
remaining product value. It is also the first slice to change the public core API
since the cross-target CI work, which is why Slice 13 landed continuous iOS
portability proof first.

## Goal

Let the core virtualize and lay out a document whose lines have different
heights, without breaking any of the brief's success criteria — in particular,
without the core owning memory that grows linearly with the document size, and
without regressing stable scroll performance on 100k+ line documents.

The slice delivers the *static* (query) half of variable-height layout: given a
source of per-line vertical metrics, compute the visible/buffer range
(offset→line) and per-line geometry (line→offset) exactly and cheaply. Mutation
of line heights and the localized-update story it implies are deliberately
deferred to a follow-up slice (see Out Of Scope).

## Key Decisions

These were settled during brainstorming and are recorded here so the rationale
travels with the design.

### Decision 1: Stateless core, height data lives in a provider

The brief requires that memory owned by the layout/virtualization core must not
grow linearly with document size. Exact variable-height offset↔line mapping
fundamentally needs cumulative height data somewhere, and an exact per-line
prefix sum over N lines is inherently O(N).

The core therefore owns **zero** per-line state. Per-line vertical metrics are
supplied by a provider, mirroring how `DocumentLineSource` already supplies line
*content* from outside the core. This satisfies the no-linear-core-memory
criterion by construction (there is nothing in the core to grow), and it is the
faithful extension of the existing architecture, in which every core type is a
pure transform with no per-document state.

Rejected alternatives:

- A core-owned estimated height plus a bounded measured-height cache. Bounded
  memory, but it makes offset↔line *approximate* and forces a convergence and
  eviction contract to be designed now. That approximation only earns its keep
  once measurement is expensive and asynchronous (real shaping/rasterization),
  which is a later slice. Today heights are simply whatever the provider knows,
  so approximation buys nothing and costs contract surface.
- A core-owned chunked cumulative index (O(N/K) memory). Exact and simple, but it
  still grows with N and therefore bends the no-linear-growth criterion rather
  than satisfying it.

### Decision 2: Provider supplies cumulative offsets; core owns the search

The problem splits cleanly into **data** (cumulative offsets) and **algorithm**
(the search that virtualizes). The provider supplies a monotonic cumulative-offset
query, `offset(ofLine:)`. The core owns the O(log N) binary search that turns a
`scrollOffsetY` into a line index.

This keeps the brief's division of labor intact ("the core virtualizes the
visible area"; the document lives outside the core): the provider owns the data,
the core owns the algorithm. Core memory stays O(1); a virtualize is O(log N) in
the document size plus O(viewport) for geometry. It is exact and fast for *any*
scroll pattern — incremental scrolling and a scrollbar drag to an arbitrary
offset are both O(log N).

The contract mandates a *query*, not a data structure, exactly as
`DocumentLineSource.line(at:)` does not dictate storage. A toy provider may sum
heights on the fly (correct, slow); a production provider uses a prefix array,
Fenwick tree, or B-tree. The core is exact either way, and any O(N) prefix
structure lives in the provider — never the core.

Rejected alternatives:

- Provider supplies only per-line `height(at:)`, core walks anchored from the
  previous frame. Thinnest provider contract, but scrollbar jumps to an arbitrary
  offset and computing total document height both become O(N), which directly
  risks the brief's stable-scroll-on-100k+/1M criterion.
- Provider answers both `offset(ofLine:)` and the inverse `line(atOffsetY:)`.
  Thinnest core, but the virtualization search moves out of the core (tension
  with "the core virtualizes") and demands the most from every provider.

### Decision 3: A separate metrics protocol, not an extension of `DocumentLineSource`

Line *content* ("what is on line i") and line *metrics* ("where does line i sit")
are orthogonal concerns. They get separate protocols so each unit has one clear
purpose, and so a host can supply heights independently of content.

### Decision 4: The fixed-height path is preserved unchanged

The existing fixed-height public API and behavior (`ViewportInput`,
`compute(_: ViewportInput)`, `LineGeometryCursor`, `geometry(for:lineHeight:)`)
stay byte-for-byte unchanged, so the synthetic gate, the realistic-provider
observation, and the memory diagnostics keep passing without retuning. The
variable-height path is purely additive. A `UniformLineMetrics` conformance lets
the new general API be driven with a constant height; it is both a convenience
and the equivalence oracle (see Testing).

### Decision 5: Validation is contractual and local, not global

The core cannot scan all offsets for monotonicity or finiteness without breaking
O(viewport)/O(log N). The protocol therefore *requires* the provider to return
finite, monotonic-non-decreasing offsets with `offset(ofLine: 0) == 0`. The core
validates only the scalar inputs it is handed, plus one O(1) defensive check on
the total height it queries.

### Decision 6: The variable-height benchmark is a blocking gate

The new variable-height `compute` benchmark is a deterministic local p95/p99
measurement, the same kind as the existing synthetic gate, and the brief requires
regression benchmarks to block merge on degradation. It is introduced as a
blocking gate (not observation-first) with budgets set with generous headroom and
tunable later.

## Architecture Overview

The variable-height path reuses the existing pure-transform architecture
wholesale. No new state is introduced anywhere in the core. The data flow mirrors
the fixed-height pipeline exactly, with a metrics source replacing the constant
`lineHeight`:

```text
host/provider computes per-line heights (out of scope how)
  -> exposes cumulative offsets via LineMetricsSource.offset(ofLine:)
  -> ViewportVirtualizer.compute(VariableViewportInput, metrics) -> VirtualRange
  -> ViewportVirtualizer.geometry(for: range, metrics:) -> LineGeometry stream
  -> host renders
```

Cost profile: O(1) core memory; O(log N) per virtualize (binary search over
`offset(ofLine:)`); O(viewport) for geometry. No per-line core state at any
point.

## Public API Surface

Names are proposed and may be adjusted during implementation review.

### The metrics protocol

```swift
public protocol LineMetricsSource {
    var lineCount: Int { get }

    /// Cumulative top offset (y) of line `index`, in layout units.
    /// Domain: 0...lineCount.  offset(ofLine: 0) == 0.
    /// offset(ofLine: lineCount) == total document height.
    /// Contract precondition: finite and monotonic non-decreasing.
    func offset(ofLine index: Int) -> Double
}
```

Everything derives from this single query:

- height of line `i` = `offset(ofLine: i + 1) - offset(ofLine: i)`
- total document height = `offset(ofLine: lineCount)`
- offset→line = the core's binary search over `offset(ofLine:)`

### Constant-height conformance and oracle

```swift
public struct UniformLineMetrics: LineMetricsSource {
    public let lineCount: Int
    public let lineHeight: Double
    public init(lineCount: Int, lineHeight: Double)
    public func offset(ofLine index: Int) -> Double // Double(index) * lineHeight
}
```

### Scalar input

```swift
public struct VariableViewportInput: Equatable {
    public let scrollOffsetY: Double
    public let viewportHeight: Double
    public let overscanLinesBefore: Int
    public let overscanLinesAfter: Int
    public init(...)
}
```

`lineCount` is intentionally absent — it comes from the metrics source. There is
no `lineHeight`.

### Entry points

```swift
extension ViewportVirtualizer {
    public static func compute<Metrics: LineMetricsSource>(
        _ input: VariableViewportInput,
        metrics: Metrics
    ) -> ViewportComputation

    public static func geometry<Metrics: LineMetricsSource>(
        for range: VirtualRange,
        metrics: Metrics
    ) -> VariableLineGeometryCursor<Metrics>
}
```

### Reused unchanged

`VirtualRange`, `LineGeometry`, `ViewportComputation`, and
`ViewportValidationError` carry no height assumptions, so the variable path
produces the same output and error types as the fixed path.

## Algorithms

### `compute(_ input: VariableViewportInput, metrics:)`

Mirrors the fixed-height `compute` step-for-step, swapping the O(1) offset↔line
arithmetic for searches over `offset(ofLine:)`:

1. **Validate scalars** (reusing `ViewportValidationError`): `lineCount >= 0`
   (`negativeLineCount`); `scrollOffsetY` and `viewportHeight` finite
   (`nonFiniteValue`); `viewportHeight >= 0` (`negativeViewportHeight`); overscan
   values `>= 0` (`negativeOverscan`). `nonPositiveLineHeight` no longer applies
   (there is no `lineHeight`). As a cheap O(1) defensive check, if
   `offset(ofLine: lineCount)` (total height) is non-finite, fail with
   `nonFiniteValue`. This catches a broken provider without an O(N) scan.
2. `lineCount == 0` -> `emptyRange()` (identical to the fixed path).
3. `totalHeight = offset(ofLine: lineCount)`;
   `maxOffsetY = max(0, totalHeight - viewportHeight)`; clamp `scrollOffsetY`
   into `[0, maxOffsetY]`. Identical clamping policy to the fixed path.
4. `visibleStart` = binary search for the line `i` such that
   `offset(i) <= effOffsetY < offset(i + 1)` (the line containing the viewport
   top).
5. `visibleEndExclusive` = binary search for the smallest `i` such that
   `offset(i) >= effOffsetY + viewportHeight` (the first line fully below the
   viewport bottom), clamped to `lineCount`.
6. **overscan -> buffer -> `isAtTop`/`isAtBottom`**: identical to the fixed path
   (index arithmetic on `visibleStart`/`visibleEndExclusive` with the overscan
   counts and clamps; `isAtTop = effOffsetY == 0`,
   `isAtBottom = effOffsetY == maxOffsetY`).

### `VariableLineGeometryCursor`

Parallels `LineGeometryCursor`: walks `[bufferStart, bufferEndExclusive)`,
emitting `LineGeometry(lineIndex, y, height)` where `y = offset(ofLine: i)` and
`height = offset(ofLine: i + 1) - offset(ofLine: i)`. It caches the rolling
offset so it makes one `offset` call per line (plus one to seed the first), and
stays O(bufferSize).

## Internal Refactor

Step 6 of `compute` (overscan -> buffer -> top/bottom flags) is identical between
the fixed and variable paths. To prevent the two paths from drifting, that logic
is extracted into one private helper that both call. This is a targeted internal
change: no public API change and no behavior change to the fixed path (guarded by
the unchanged fixed-height tests and the unchanged synthetic gate).

## Precision And Equivalence

The fixed path snaps near-integer quotients to integers using an ulp tolerance
(`snappedIntegerQuotient`), so floating-point dust at exact line boundaries does
not push a line in or out of the range. The variable path compares offsets
directly.

For the `UniformLineMetrics` equivalence oracle to hold exactly (variable path
with uniform metrics == fixed path), the binary-search boundary comparisons must
reproduce the fixed path's boundary semantics. The plan is to define the search's
boundary handling to match that snapping intent, with the equivalence test as the
guard. If exact equivalence proves impractical at some pathological float
boundary, the documented fallback is equivalence "up to one line at exact
floating-point boundaries"; the intent is exact equivalence.

## Reference Provider And Performance Gate

A reference indexed provider, `PrefixSumLineMetrics`, lives in the
benchmark/test target — **outside** the core. It is backed by a `[Double]` prefix
array of length `lineCount + 1`, so `offset(ofLine:)` is an O(1) array read. Its
O(N) memory is legitimate: it represents the document store living outside the
core, exactly like the existing synthetic and realistic providers in
`ViewportBenchmarks`. It drives both scale correctness tests and the performance
proof.

A new variable-height benchmark scenario (non-uniform heights drawn from a fixed
distribution) measures `compute` p95/p99 at 1k / 100k / 1M lines and proves
offset→line stays flat (O(log N)) at 1M lines. Per Decision 6 it is a blocking
gate that mirrors the existing synthetic gate, with budgets set with generous
headroom and tunable later. This extends the brief's "stable scroll on 100k+
lines" criterion to the variable-height path.

## Testing Strategy

- offset→line correctness across boundaries, mid-line positions, clamps, the
  empty document, a single line, `viewportHeight == 0`, and huge/negative
  `scrollOffsetY`.
- geometry-cursor `y`/`height` derivation on hand-built non-uniform metrics
  (for example heights `[10, 30, 5, 100]`) with known expected output.
- `UniformLineMetrics` equivalence oracle: the variable path with uniform metrics
  must equal the fixed path across an input matrix. This is the keystone test
  proving the variable path subsumes the fixed path.
- validation-error parity with the fixed path for each applicable error case.
- scale correctness and the blocking performance gate via `PrefixSumLineMetrics`
  at 1M lines.

## Portability Verification

This slice changes the public core API, so the standard portability checks run:

- host `swift test`;
- iOS cross-target CI (continuous and blocking since Slice 13);
- local WASM and embedded-WASM package-graph builds of `TextEngineCore`.

WASM-in-CI remains skipped on the hosted runner (default Swift 6.1.2 has no
matching public WASM SDK) — unchanged from Slice 13, not a regression.

## Out Of Scope

Restating the locked boundary for this slice:

- single-line-height mutation and the localized provider-update story it implies
  (the next slice; because the core is stateless, this is entirely a provider
  concern);
- WASM CI promotion from skipped to compiled/blocking;
- repository branch protection / required status checks (Slice 6 external
  blocker, unchanged);
- storage adapters / additional providers;
- memory hard budgets (RSS, heap, malloc, allocation-count);
- shaping, rasterization, or any real (content-derived or asynchronous)
  measurement source;
- UI-framework integration.

## Future Slices

- **Variable-height mutation**: a reference indexed provider whose single-line
  height change is a localized update (for example an O(log N) Fenwick update
  rather than an O(N) rebuild), with end-to-end tests that a height change yields
  a correct, cheap re-layout. The stateless core needs no change for this; it is
  provider-side work plus tests.
- **Measurement source**: once shaping/rasterization can produce real per-line
  heights, revisit whether an estimated-height-plus-measurement model (the
  Decision 1 rejected alternative) becomes worthwhile for asynchronous measuring.
