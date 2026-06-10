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
(the search that virtualizes). The provider supplies a monotonic (strictly
increasing; see Decision 5) cumulative-offset query, `offset(ofLine:)`. The core
owns the O(log N) binary search that turns a `scrollOffsetY` into a line index.

This keeps the brief's division of labor intact ("the core virtualizes the
visible area"; the document lives outside the core): the provider owns the data,
the core owns the algorithm. Core memory stays O(1). A virtualize costs O(log N)
`offset(ofLine:)` *queries* (the binary search), and the geometry pass costs
O(buffer) queries; the per-query cost is provider-defined (see below). It is
exact and fast for *any* scroll pattern — incremental scrolling and a scrollbar
drag to an arbitrary offset are both O(log N) queries.

The contract mandates a *query*, not a data structure, exactly as
`DocumentLineSource.line(at:)` does not dictate storage. A toy provider may sum
heights on the fly (correct, slow); a production provider uses a prefix array,
Fenwick tree, or B-tree. The core is exact either way, and any O(N) prefix
structure lives in the provider — never the core.

**Performance expectation.** Because the per-virtualize cost is O(log N) *queries*
times the provider's per-query cost, a gated or production provider must answer
`offset(ofLine:)` in O(1) or O(log N) (the reference `PrefixSumLineMetrics` is
O(1)). The sum-on-the-fly toy provider is correctness-only: it makes each query
O(N) and a virtualize O(N log N), which is acceptable for tests but not for the
gate or production.

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

The existing fixed-height entry points (`ViewportInput`,
`compute(_: ViewportInput)`, `LineGeometryCursor`, `geometry(for:lineHeight:)`)
keep their signatures and behavior unchanged, so the synthetic gate, the
realistic-provider observation, and the memory diagnostics keep passing without
retuning. The variable-height path is otherwise purely additive. The one
public-surface change touching a shared type is the additive
`ViewportValidationError.invalidLineMetrics` case (existing cases unchanged, never
returned by the fixed path); note that adding an enum case is source-breaking for
any consumer doing an exhaustive `switch` without a `default`. A `UniformLineMetrics` conformance lets
the new general API be driven with a constant height; it is both a convenience
and the equivalence oracle (see Testing).

### Decision 5: Validation is contractual and local, not global

The core cannot scan all offsets without breaking O(viewport)/O(log N). The
protocol therefore states a precondition the core trusts: offsets are finite,
**strictly increasing** on `0..<lineCount` (every line has finite positive
height), and `offset(ofLine: 0) == 0`. The contract also requires **stability**:
`lineCount` and `offset(ofLine:)` must not change during a single layout
operation — one `compute` together with any `VariableLineGeometryCursor`
traversal derived from the range it produced — so the range and the geometry are
computed from one consistent snapshot of prefix sums. (This is the static query
half; mutation between frames is a later slice.)

**Recorded product decision:** this slice requires strictly increasing offsets
and so forbids zero-height (collapsed/hidden) lines. The reason is the contract,
not precision: "non-decreasing" would let a provider return equal adjacent
offsets, for which the containing-interval search
(`offset(i) <= y < offset(i + 1)`) has no defined answer and the tie-break across
an equal-offset run is ambiguous. (Precision collapse of adjacent positive-height
sums is not a real driver: with a 53-bit significand, adjacent prefix sums round
equal only when total height approaches `height · 2^52` — for 16 px lines that is
about 4.5×10^15 lines, which is unreachable.) If collapsed lines become a
near-term requirement, a later slice can relax to non-decreasing and define the
run tie-break precisely (for example `visibleStart` = first line of the run,
`visibleEndExclusive` = past the last) with tests.

The core enforces only the O(1) checks it can afford: `offset(ofLine: 0) == 0`,
and for `lineCount > 0` the queried total height `offset(ofLine: lineCount)`
finite and **strictly positive** (a non-positive total contradicts the
strict-positive-height contract). Global strict monotonicity is **not** verified —
that needs an O(N) scan, which violates the budget — so a mid-document contract
violation is undefined behavior, like any precondition.
Contract violations the core does detect cheaply surface as a dedicated
`invalidLineMetrics` error rather than overloading `nonFiniteValue`.

### Decision 6: The variable-height benchmark is a blocking gate

The new variable-height benchmark is a deterministic local p95/p99 measurement,
the same kind as the existing synthetic gate, and the brief requires regression
benchmarks to block merge on degradation. It is introduced as a blocking gate
(not observation-first) with budgets set with generous headroom and tunable
later.

## Architecture Overview

The variable-height path reuses the existing pure-transform architecture
wholesale. No new state is introduced anywhere in the core. The data flow mirrors
the fixed-height pipeline exactly, with a metrics source replacing the constant
`lineHeight`, and geometry and content traversed over the same `VirtualRange`:

```text
host/provider computes per-line heights (out of scope how)
  -> exposes cumulative offsets via LineMetricsSource.offset(ofLine:)
  -> ViewportVirtualizer.compute(VariableViewportInput, metrics) -> VirtualRange
       |
       +-> ViewportVirtualizer.geometry(for: range, metrics:)        -> LineGeometry stream
       +-> ViewportVirtualizer.lines(for: range, in: contentSource)  -> content stream
  -> host renders
```

Cost profile: O(1) core memory; per virtualize O(log N) `offset(ofLine:)` queries
(binary search) plus O(buffer) queries for geometry; per-query cost is
provider-defined (Decision 2). No per-line core state at any point.

**Two `lineCount` sources.** Both `LineMetricsSource` and the existing
`DocumentLineSource` expose `lineCount`. The host is responsible for keeping them
consistent, as it already is for a single source today; if they disagree the
result is undefined. Composition is otherwise unchanged from the fixed path: the
same `VirtualRange` produced by the variable `compute` feeds both the
metrics-driven geometry cursor and the existing `ViewportVirtualizer.lines(for:in:)`
content cursor, so geometry and content are traversed over identical indices.

## Public API Surface

Names are proposed and may be adjusted during implementation review.

### The metrics protocol

```swift
public protocol LineMetricsSource {
    var lineCount: Int { get }

    /// Cumulative top offset (y) of line `index`, in layout units.
    /// Domain: 0...lineCount.  offset(ofLine: 0) == 0.
    /// offset(ofLine: lineCount) == total document height.
    /// Contract precondition: finite and strictly increasing on 0..<lineCount
    /// (every line has finite positive height). See Decision 5.
    /// Stability precondition: `lineCount` and `offset(ofLine:)` must be stable
    /// for one layout operation — a `compute` and any `VariableLineGeometryCursor`
    /// traversal derived from the range it produced — so the range and the
    /// geometry come from one snapshot (the static query half; mutation is a
    /// later slice).
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

### Reused, with one additive error case

`VirtualRange`, `LineGeometry`, and `ViewportComputation` carry no height
assumptions and are reused unchanged. `ViewportValidationError` gains one
additive case, `invalidLineMetrics`, for the O(1) contract checks in Decision 5;
its existing cases are unchanged. The variable path otherwise produces the same
output and error types as the fixed path.

## Algorithms

### `compute(_ input: VariableViewportInput, metrics:)`

Mirrors the fixed-height `compute` step-for-step, swapping the O(1) offset↔line
arithmetic for searches over `offset(ofLine:)`:

1. **Validate scalars** (reusing `ViewportValidationError`): `lineCount >= 0`
   (`negativeLineCount`); `scrollOffsetY` and `viewportHeight` finite
   (`nonFiniteValue`); `viewportHeight >= 0` (`negativeViewportHeight`); overscan
   values `>= 0` (`negativeOverscan`). `nonPositiveLineHeight` no longer applies
   (there is no `lineHeight`).
2. **O(1) metrics contract checks** (Decision 5): `offset(ofLine: 0) == 0`; and
   for `lineCount > 0`, the queried total height `offset(ofLine: lineCount)` is
   finite and strictly positive (`> 0`). Otherwise fail with `invalidLineMetrics`.
   (For `lineCount == 0`, `offset(ofLine: 0) == 0` is also the total height and the
   result is `emptyRange` — step 3.) Global strict monotonicity is not scanned
   (that would be O(N)).
3. `lineCount == 0` -> `emptyRange()` (identical to the fixed path).
4. `totalHeight = offset(ofLine: lineCount)`;
   `maxOffsetY = max(0, totalHeight - viewportHeight)`; clamp `scrollOffsetY`
   into `[0, maxOffsetY]`. Identical clamping policy to the fixed path.
5. `visibleStart`: if `effOffsetY >= totalHeight` (reachable only when
   `viewportHeight == 0` at the document end, where no line contains the top),
   `visibleStart = lineCount`; otherwise a binary search for the line `i` such
   that `offset(i) <= effOffsetY < offset(i + 1)` (the line containing the
   viewport top), with the boundary comparison defined per Precision And
   Equivalence.
6. `visibleEndExclusive` = binary search for the smallest `i` such that
   `offset(i) >= effOffsetY + viewportHeight` (the first line fully below the
   viewport bottom), clamped to `lineCount`.
7. **overscan -> buffer -> `isAtTop`/`isAtBottom`**: identical to the fixed path
   (index arithmetic on `visibleStart`/`visibleEndExclusive` with the overscan
   counts and clamps; `isAtTop = effOffsetY == 0`,
   `isAtBottom = effOffsetY == maxOffsetY`).

### `VariableLineGeometryCursor`

Parallels `LineGeometryCursor`: walks `[bufferStart, bufferEndExclusive)`,
emitting `LineGeometry(lineIndex, y, height)` where `y = offset(ofLine: i)` and
`height = offset(ofLine: i + 1) - offset(ofLine: i)`. It caches the rolling
offset so it makes one `offset` call per line (plus one to seed the first), and
stays O(bufferSize). It holds the `Metrics` value as a copy-safe handle (see
Memory-Shape Demonstration).

## Internal Refactor

Step 7 of `compute` (overscan -> buffer -> top/bottom flags) is identical between
the fixed and variable paths. To prevent the two paths from drifting, that logic
is extracted into one private helper that both call. This is a targeted internal
change: no public API change and no behavior change to the fixed path (guarded by
the unchanged fixed-height tests and the unchanged synthetic gate).

## Precision And Equivalence

The fixed path snaps near-integer *quotients* (`scrollOffsetY / lineHeight`) to
integers using an ulp tolerance (`snappedIntegerQuotient`), so floating-point
dust at exact line boundaries does not move a line in or out of the range. The
variable path has no division; it compares `scrollOffsetY` against `offset(i)`
directly.

This slice commits to **exact** `UniformLineMetrics` equivalence: the variable
path driven by `UniformLineMetrics(lineCount, lineHeight)` must produce a
`VirtualRange` byte-identical to the fixed path's for the same inputs. There is no
"±1 line" fallback. To achieve it, the binary search's boundary comparison is
defined to reproduce the fixed path's snapping in offset space — a comparison
tolerance keyed to the offset magnitude at the candidate line, chosen so that for
`offset(i) = i · lineHeight` the search lands on the same line the quotient
snapping would. The implementation plan must define the exact comparison
predicate (the snapping helper, written with the fixed path's
`snappedIntegerQuotient` in hand) before coding the search: this spec fixes the
requirement (exact equivalence), the plan fixes the formula.

The equivalence oracle must cover, at minimum, these boundary positions:

- `scrollOffsetY` exactly on a line top (`offset(i)`), including the first and
  last lines;
- `scrollOffsetY` clamped to `maxOffsetY`, and the `effOffsetY == totalHeight`
  edge (where `visibleStart` takes the fixed path's high-end clamp,
  `clampedIndex(…, lineCount)`);
- `viewportHeight == 0`;
- a range of non-boundary offsets.

If implementation surfaces a specific boundary where exact equivalence is
genuinely unachievable, that is a plan-time finding to resolve explicitly — not a
pre-authorized soft fallback.

## Reference Provider And Performance Gate

A reference indexed provider, `PrefixSumLineMetrics`, lives in the
benchmark/test target — **outside** the core. It is backed by a `[Double]` prefix
array of length `lineCount + 1`, so `offset(ofLine:)` is an O(1) array read. Its
O(N) memory is legitimate: it represents the document store living outside the
core, exactly like the existing synthetic and realistic providers in
`ViewportBenchmarks`. It drives both scale-correctness tests and the performance
proof.

**What the gate measures.** The existing synthetic gate measures a full traversal
(compute plus a per-line provider walk), not compute alone. The variable-height
gate matches that philosophy by measuring **compute plus the variable geometry
traversal** (`VariableLineGeometryCursor` over the buffer range) — the geometry
walk is the variable-height-specific per-line work, since each emitted line costs
an `offset(ofLine:)` query. Content traversal is unchanged by line height and is
already covered by the existing pipeline gate, so it is not duplicated here.

**Access pattern.** The benchmark reuses the existing `deterministicScrollOffset`
generator, which already spreads offsets across `[0, maxOffset]` rather than
scrolling sequentially. Varied offsets are kept for benchmark realism — they
exercise varied prefix-array cache behavior and avoid optimizer/branch-prediction
artifacts from a fixed offset — not because the search would otherwise be
under-exercised: the search is **stateless** (Decision 2, not anchored walking),
so every virtualize is O(log N) queries regardless of locality.

**Scenarios and budgets.** A new variable-height scenario (non-uniform heights
drawn from a fixed distribution) measures compute + geometry p95/p99 at
1k / 100k / 1M lines and shows the cost stays within budget and scales
logarithmically, not linearly, in N (the O(log N) search + O(buffer) geometry
claim; the buffer is fixed by the viewport/overscan and so is constant across the
scale points, leaving only the log-N search term to vary). Per Decision 6 it is a blocking gate; budgets are
local-deterministic with **generous** headroom (the Slice 11 lesson: a thin
margin — a hosted sample once hit 98.7% of its budget — is CI-fragile; the
synthetic gate is robust precisely because its margins are wide).

**CLI and CI wiring.** The benchmark CLI separates a *mode* flag from the
orthogonal `--gate` enforcement switch, so the gate is invoked through a new
gateable mode, `--variable-height`, combined with `--gate`
(`ViewportBenchmarks --variable-height --gate`), mirroring
`--realistic-provider --gate`. In `.github/workflows/swift-ci.yml` it runs as a
new step in the host job immediately after the existing synthetic-gate step,
consistent with the Slice 5 / Slice 7 convention of naming the exact invocation
and CI placement.

## Memory-Shape Demonstration

The brief's headline memory criterion (core-owned memory does not grow with
document size) is argued by construction in Decision 1, but this project's
practice (Slice 7) is to turn that claim into a deterministic diagnostic. The
`--memory-shape` diagnostic gains a variable-height scenario that runs the same
viewport/overscan against 100k and 1M lines through `compute` and
`VariableLineGeometryCursor`, and asserts identical `core_owned_bytes` across the
two line counts (O(1) core memory) and `geometry_lines == buffered_lines`
(O(buffer) traversal). `coreOwnedBytesEstimate` already sums `MemoryLayout` sizes,
so it extends to the variable cursor naturally. This is a structural invariant,
not a memory hard budget (which stays out of scope).

This depends on the metrics value stored in the cursor being a lightweight,
copy-safe **handle**: `VariableLineGeometryCursor<Metrics>` holds the `Metrics`
by value to query offsets per line, exactly as `DocumentLineCursor<Source>` holds
its `Source`. `PrefixSumLineMetrics`'s `[Double]` is a copy-on-write reference, so
only an 8-byte pointer lives in the cursor's static size; the prefix array stays
provider-owned and is counted as `provider_owned_bytes`. A conforming metrics
type must keep its index/prefix storage out of line (provider-owned), not inlined
into the value.

## Testing Strategy

- offset→line correctness across boundaries, mid-line positions, clamps, the
  empty document, a single line, `viewportHeight == 0`, and huge/negative
  `scrollOffsetY`.
- geometry-cursor `y`/`height` derivation on hand-built non-uniform metrics
  (for example heights `[10, 30, 5, 100]`) with known expected output.
- `UniformLineMetrics` equivalence oracle: the variable path with uniform metrics
  must equal the fixed path **exactly** across the boundary positions enumerated
  in Precision And Equivalence and a non-boundary input matrix. This is the
  keystone test proving the variable path subsumes the fixed path.
- validation-error parity with the fixed path for each applicable error case,
  plus the O(1) `invalidLineMetrics` checks (`offset(ofLine: 0) != 0`, and for
  `lineCount > 0` a non-finite or non-positive total height) and a valid
  strictly-increasing non-uniform case. Global monotonicity violations are out of
  reach for the core and are not tested as core rejections.
- scale correctness and the blocking performance gate via `PrefixSumLineMetrics`
  at 1M lines.

## Verification

This slice changes the public core API, so the full verification set runs:

- `swift test` (host XCTest suite, including the new variable-height tests);
- `swift build -c release`;
- `swift run -c release ViewportBenchmarks -- --gate` (synthetic gate, unchanged);
- `swift run -c release ViewportBenchmarks -- --variable-height --gate` (the new
  blocking variable-height gate);
- `swift run -c release ViewportBenchmarks -- --memory-shape` (including the new
  variable-height scenario);
- `swift run -c release ViewportBenchmarks -- --memory-observation` (host RSS,
  unchanged);
- iOS device + simulator cross-target compile via the Slice 13 `xcodebuild` CI
  job (continuous and blocking);
- local WASM and embedded-WASM package-graph builds of `TextEngineCore`;
- the Slice 13 cross-target helper self-test and the hosted-job evidence on the
  merge commit.

WASM-in-CI remains skipped on the hosted runner (default Swift 6.1.2 has no
matching public WASM SDK) — unchanged from Slice 13, not a regression.

## Acceptance Criteria

- [ ] `LineMetricsSource`, `UniformLineMetrics`, `VariableViewportInput`,
  `VariableLineGeometryCursor`, and the two `ViewportVirtualizer` entry points are
  public and compile in `TextEngineCore`.
- [ ] The fixed-height entry points keep their signatures and behavior unchanged
  (the only shared-surface change is the additive
  `ViewportValidationError.invalidLineMetrics` case); the existing tests, synthetic
  gate, memory-shape, and memory-observation pass without retuning.
- [ ] `ViewportValidationError` gains only the additive `invalidLineMetrics`
  case; existing cases are unchanged.
- [ ] offset→line and line→offset are correct across the boundary, mid-line,
  clamp, empty, single-line, `viewportHeight == 0`, and huge/negative-offset
  cases.
- [ ] The `UniformLineMetrics` equivalence oracle passes **exactly** for the
  enumerated boundary positions and a non-boundary matrix.
- [ ] The shared overscan→buffer→flags helper is used by both `compute` paths
  with no behavior change to the fixed path.
- [ ] `--variable-height --gate` passes at 1k / 100k / 1M lines with generous
  headroom and is wired into CI after the synthetic-gate step.
- [ ] `--memory-shape` shows identical `core_owned_bytes` for the variable-height
  scenario at 100k vs 1M lines, and `geometry_lines == buffered_lines`.
- [ ] Host tests, release build, iOS cross-target CI, and local WASM +
  embedded-WASM builds all pass.

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
- **Collapsed/hidden lines**: if zero-height lines become a requirement, relax the
  Decision 5 strictly-increasing precondition to non-decreasing and define the
  equal-offset-run tie-break precisely, with tests.
- **Measurement source**: once shaping/rasterization can produce real per-line
  heights, revisit whether an estimated-height-plus-measurement model (the
  Decision 1 rejected alternative) becomes worthwhile for asynchronous measuring.
