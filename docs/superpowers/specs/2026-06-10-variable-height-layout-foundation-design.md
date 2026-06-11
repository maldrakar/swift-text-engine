# Variable-Height Layout Foundation Design

Date: 2026-06-10

## Status

Approved design. Revised 2026-06-11 after spec review: the variable-height gate
enforces locally but lands observation-only in CI, with CI-failing promotion
deferred to a follow-up slice (Decision 6); the `LineMetricsSource` monotonicity
contract wording is tightened and the query domain bounded (Decision 5); the
strict-virtualization/metadata-probe distinction is made explicit (Decision 2);
the memory-shape invariant is scoped to contract-honoring conformers; and a
deterministic query-count complexity test is required (Testing Strategy),
including the empty-cursor query-count edge case. The benchmark wording is also
tightened: the wall-clock gate is representative end-to-end coverage, while the
query-count test is the deterministic proof of asymptotic complexity.

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

**Strict virtualization is preserved.** The brief's strict-virtualization
criterion ("compute only the visible viewport + buffer/overscan") constrains
*materialization*: only visible+buffer lines have their geometry or content
produced. The O(log N) `offset(ofLine:)` lookups the binary search performs are
**bounded scalar metadata probes** (a single cumulative-offset read at each search
midpoint), not line-content or layout materialization — they touch O(log N)
indices' metadata, allocate nothing, and materialize no line. They are therefore
consistent with strict virtualization, not an exception to it.

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
returned by the fixed path). **Migration note:** adding an enum case is a source
break for any consumer doing an exhaustive `switch` over `ViewportValidationError`
without a `default`. This package contains no such switch (errors are only
compared by value), so the addition is safe here; the break is called out only for
a future or external exhaustive switch. A `UniformLineMetrics` conformance lets
the new general API be driven with a constant height; it is both a convenience
and the equivalence oracle (see Testing).

### Decision 5: Validation is contractual and local, not global

The core cannot scan all offsets without breaking O(viewport)/O(log N). The
protocol therefore states a precondition the core trusts: the domain is
`0...lineCount`; `offset(ofLine: 0) == 0`; and for every `i` in `0..<lineCount`
both `offset(ofLine: i)` and `offset(ofLine: i + 1)` are finite and
`offset(ofLine: i) < offset(ofLine: i + 1)` (every line has finite positive
height, so the endpoint `offset(ofLine: lineCount)` is included in the monotone
chain). The core never queries outside `0...lineCount`. The contract also requires
**stability**:
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

### Decision 6: The variable-height gate is local-enforcing, CI-observational

The new variable-height benchmark is a deterministic local p95/p99 measurement,
the same kind as the existing synthetic gate. `--variable-height --gate`
**enforces budgets locally** (it fails the developer's run on regression) so the
budget travels with the code. In CI it lands as an **observation-only** step this
slice (prints p95/p99, non-blocking); it does **not** fail Swift CI yet.

Two prior lessons drive this split. Slice 12's post-slice review #5 says
explicitly: "do not mix variable-height layout with benchmark enforcement … in one
slice; each needs its own design and review." And both existing gates were shipped
that way — the synthetic gate's measurement, its local gate, and its CI-enforcement
wiring landed across *separate* slices, and the realistic-provider gate stayed
CI-deferred until hosted samples justified enforcement (Slice 10/11). A brand-new
CI-failing gate introduced in the same slice as the public-API change it guards
would repeat exactly the mix those reviews warn against, and would enforce a budget
whose hosted behavior has not been observed even once.

Promotion of the CI step from observation-only to CI-failing is a small follow-up
slice (see Future Slices): collect a handful of hosted p95/p99 samples, set the
budget from `max(local, hosted) · safety_factor` with generous headroom, and — per
the Slice 10 fallback — do not wire CI enforcement if the hosted margin is thin.
Local budgets this slice are set with generous headroom (the Slice 11 lesson; see
Budget derivation) and are tunable later. Independent of either gate, a
deterministic call-counting unit test pins the O(log N) / O(buffer) query
complexity (see Testing Strategy), so the *algorithmic* guarantee is enforced in CI
even while the wall-clock gate is observation-only.

(The brief asks for regression benchmarks that block merge; *actual* merge-block
also remains repository-policy-blocked regardless — branch protection / required
status checks are unavailable on the private repo, the Slice 6 blocker, out of
scope here.)

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

**Portability (Embedded).** `LineMetricsSource` is consumed only through generic
specialization — `compute<Metrics: LineMetricsSource>`, `geometry<Metrics>`,
`VariableLineGeometryCursor<Metrics>` — never as an existential
(`any LineMetricsSource`), deliberately mirroring `DocumentLineSource`, which is
already proven to compile on every cross-target (iOS, WASM, embedded WASM). For
Swift Embedded this is a *compilation requirement*, not a stylistic choice:
existentials are unsupported there, so the new protocol inherits the proven
portability shape by construction rather than relying solely on re-running
cross-target CI. The protocol and its conformances stay Foundation-free for the
same reason.

## Public API Surface

Names are proposed and may be adjusted during implementation review.

### The metrics protocol

```swift
public protocol LineMetricsSource {
    var lineCount: Int { get }

    /// Cumulative top offset (y) of line `index`, in layout units.
    /// Domain: 0...lineCount.  offset(ofLine: 0) == 0.
    /// offset(ofLine: lineCount) == total document height.
    /// Contract precondition: for every i in 0..<lineCount both offset(ofLine: i)
    /// and offset(ofLine: i + 1) are finite and offset(ofLine: i) <
    /// offset(ofLine: i + 1) (every line has finite positive height; the endpoint
    /// offset(ofLine: lineCount) is part of the monotone chain). The core never
    /// queries outside 0...lineCount. See Decision 5.
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
3. `lineCount == 0` -> `emptyRange()` (identical to the fixed path). The
   `offset(ofLine: 0) == 0` check in step 2 runs *before* this short-circuit, so an
   empty document still makes exactly that one query and a broken provider yields
   `invalidLineMetrics` rather than `emptyRange`. This is deliberate parity with
   the fixed path, which validates `nonPositiveLineHeight` before its
   `lineCount == 0` short-circuit; implementations must not reorder the empty
   return ahead of the contract check.
4. `totalHeight = offset(ofLine: lineCount)`;
   `maxOffsetY = max(0, totalHeight - viewportHeight)`; clamp `scrollOffsetY`
   into `[0, maxOffsetY]`. Identical clamping policy to the fixed path.
5. `visibleStart`: if `effOffsetY >= totalHeight` (reachable only when
   `viewportHeight == 0` at the document end, where no line contains the top),
   `visibleStart = lineCount`; otherwise a binary search for the line `i` such
   that `offset(i) <= effOffsetY < offset(i + 1)` (the line containing the
   viewport top), by direct offset comparison (see Precision And Equivalence).
6. `visibleEndExclusive` = binary search for the smallest `i` such that
   `offset(i) >= effOffsetY + viewportHeight` (the first line fully below the
   viewport bottom), clamped to `lineCount`. The search seeds its lower bound at
   `visibleStart` rather than 0: since
   `offset(visibleStart) <= effOffsetY <= effOffsetY + viewportHeight`, the answer
   is provably `>= visibleStart`. This is exact and removes a constant factor of
   `offset(ofLine:)` queries for providers whose query is itself O(log N)
   (Decision 2). (When this search runs, `effOffsetY < totalHeight`, so
   `visibleStart <= lineCount - 1` and the seed is in range.)
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
dust from its own division does not move a line in or out of the range. The
variable path has no division; it compares `scrollOffsetY` against `offset(i)`
directly, so it needs no snapping of its own.

**Resolved plan-time finding.** The variable search uses a plain direct offset
comparison — no fuzzy tolerance. For **exactly-representable** line heights
(`16.0`, `10.0`, `1.0`, `12.5`, …) this reproduces the fixed path **exactly**:
`offset(i) = Double(i) · lineHeight` is exact, every boundary position is
unambiguous, and direct comparison lands on the same line the fixed path's
divide-snap-floor/ceil does (verified against every existing fixed-path test
scenario). For **non-power-of-two** heights such as `0.1`, the two paths can
differ by at most one line at sub-ulp boundaries: the fixed path divides once and
snaps the quotient, while the variable path multiplies `Double(i) · lineHeight`
and compares, and with *varying* heights there is no single `h` to divide by, so
the variable path cannot reproduce the division-snap. This 1-ulp
divide-vs-multiply gap is fundamental to the architecture, not a tunable defect,
and is meaningless at the ~1e-16 scale; the variable result is the more-direct,
correct computation for the given offsets.

**Equivalence oracle.** The `UniformLineMetrics` oracle proves **exact**
`variable == fixed` using exactly-representable line heights, covering at minimum:

- `scrollOffsetY` exactly on a line top (`offset(i)`), including the first and
  last lines;
- `scrollOffsetY` clamped to `maxOffsetY`, and the `effOffsetY == totalHeight`
  edge (where `visibleStart` takes the fixed path's high-end clamp to
  `lineCount`);
- `viewportHeight == 0` at three positions, matching the fixed path: an **exact
  line top** → empty range `[i, i)`; a **mid-line** offset → the single crossed
  line `[i, i + 1)`; the **document end** → `visibleStart == lineCount`;
- a range of non-boundary (mid-line) offsets;
- a moderately large `lineCount` (for example 100k) where adjacent
  `Double(i) · lineHeight` offsets stay distinct, so the strictly-increasing
  contract holds.

The `Int.max` clamp-at-end case is tested **separately**, not through the general
oracle: at `Int.max`, `UniformLineMetrics`' `Double(i) · lineHeight` offsets are
no longer strictly increasing (consecutive integers above `2^53` collapse to the
same `Double`), so it must not be used to exercise the offset→line search. The
clamp special case (`effOffsetY >= totalHeight → visibleStart == lineCount`) never
inspects mid-document offsets, so it is valid regardless and only proves
clamp/overflow-safety.

The oracle deliberately uses exactly-representable heights; equivalence at sub-ulp
boundaries of non-representable heights is explicitly **not** claimed, per the
finding above.

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
1k / 100k / 1M lines and shows the representative compute + geometry workload
stays within budget. The wall-clock benchmark may vary viewport height and
overscan across those scenario sizes to mirror the existing benchmark shape, so
it is **not** the sole proof that the algorithm scales logarithmically in
`lineCount`; it is an end-to-end performance gate and scale smoke test. The
deterministic O(log N) search + O(buffer) geometry guarantee is pinned by the
query-count unit test in Testing Strategy, while this gate catches constant-factor
regressions and provider/core interaction costs on the reference prefix-sum
provider. Per Decision 6 the gate **enforces locally** (`--variable-height --gate`
fails the developer's run) and lands **observation-only in CI** this slice
(non-blocking); CI enforcement is a follow-up after hosted calibration. Budgets
are local-deterministic with **generous** headroom (the Slice 11 lesson: a thin
margin — a hosted sample once hit 98.7% of its budget — is CI-fragile; the
synthetic gate is robust precisely because its margins are wide).

**Budget derivation.** To make "generous headroom" a rule rather than a matter of
taste, each budget is set as `budget = ceil(observed_pXX × safety_factor)` with
`safety_factor >= 4`, measured on the first local release run and rounded up to a
clean number. Four is a floor, not a target — it keeps the variable-height gate in
the same ballpark as the existing synthetic gate (whose 1M scenario runs at
roughly 6× headroom). The plan ships concrete starter budgets; the first local run
confirms each observed value sits at or below `budget / 4`, otherwise the budget is
raised (never the gate loosened on a real regression).

**Content-axis scope.** The brief's success criterion is "100k+ lines / >10 MB".
This gate scales the *line-count* axis (1k / 100k / 1M) at variable heights; it has
no byte/content dimension by design, because line heights are orthogonal to line
content. The *content* axis (>10 MB) is already covered by the realistic-provider
gate, which this slice does not touch, so the slice neither extends nor regresses
that axis.

**CLI and CI wiring.** The benchmark CLI separates a *mode* flag from the
orthogonal `--gate` enforcement switch, so the gate is invoked through a new
gateable mode, `--variable-height`, combined with `--gate`
(`ViewportBenchmarks --variable-height --gate`), mirroring
`--realistic-provider --gate`. In `.github/workflows/swift-ci.yml` the
variable-height benchmark runs as a new step in the host job immediately after the
existing synthetic-gate step, but **without `--gate`** (observation-only,
non-blocking) this slice — it prints p95/p99 for hosted-sample collection and does
not fail CI. The workflow step must set `continue-on-error: true`; that is the
mechanism that makes this hosted timing observation non-blocking while still
surfacing infrastructure or benchmark-output problems in the step logs. Promoting
that step to `--variable-height --gate` (CI-failing) is the follow-up slice. This
still follows the Slice 5 / Slice 7 convention of naming the exact invocation and
CI placement.

## Memory-Shape Demonstration

The brief's headline memory criterion (core-owned memory does not grow with
document size) is argued by construction in Decision 1, but this project's
practice (Slice 7) is to turn that claim into a deterministic diagnostic. The
`--memory-shape` diagnostic gains a variable-height scenario that runs the same
viewport/overscan against 100k and 1M lines through `compute` and
`VariableLineGeometryCursor`, using the **allocation-free** `UniformLineMetrics`,
and asserts identical `core_owned_bytes` across the two line counts (O(1) core
memory) and `geometry_lines == buffered_lines` (O(buffer) traversal). A dedicated
`variableCoreOwnedBytesEstimate` sums the `MemoryLayout` sizes of `VirtualRange`
and `VariableLineGeometryCursor<UniformLineMetrics>`. This is a structural
invariant, not a memory hard budget (which stays out of scope). `UniformLineMetrics`
is chosen over the indexed `PrefixSumLineMetrics` precisely because it allocates
nothing, so the diagnostic proves the core's O(1) memory without itself allocating
an O(N) prefix array (and therefore reports no `provider_owned_bytes`).

The invariant holds for any metrics that **honor the provider storage contract** —
index/prefix storage kept out of line (provider-owned) rather than inlined into the
value, so the value is a lightweight, copy-safe **handle**.
`VariableLineGeometryCursor<Metrics>` holds the `Metrics` by value to query offsets
per line, exactly as `DocumentLineCursor<Source>` holds its `Source`; holding by
value preserves the O(1) static size *only* under that contract — the protocol
cannot by itself forbid a heavy inlined value, so this is a documented requirement
on conformers, not a guarantee the type system provides. For an indexed provider
such as `PrefixSumLineMetrics`, the `[Double]` prefix array is a copy-on-write
reference, so only a pointer lives in the cursor's static size and the array stays
provider-owned.

## Testing Strategy

- offset→line correctness across boundaries, mid-line positions, clamps, the
  empty document, a single line, `viewportHeight == 0`, and huge/negative
  `scrollOffsetY`.
- geometry-cursor `y`/`height` derivation on hand-built non-uniform metrics
  (for example heights `[10, 30, 5, 100]`) with known expected output.
- `UniformLineMetrics` equivalence oracle: the variable path with uniform metrics
  must equal the fixed path **exactly** (using exactly-representable line heights)
  across the boundary positions enumerated in Precision And Equivalence and a
  non-boundary input matrix. This is the keystone test proving the variable path
  subsumes the fixed path.
- validation-error parity with the fixed path for each applicable error case,
  plus the O(1) `invalidLineMetrics` checks (`offset(ofLine: 0) != 0`, and for
  `lineCount > 0` a non-finite or non-positive total height) and a valid
  strictly-increasing non-uniform case. Global monotonicity violations are out of
  reach for the core and are not tested as core rejections.
- a deterministic **query-count** test: a `CountingLineMetrics` wrapper around the
  closed-form `UniformLineMetrics` (each query stays O(1) and offsets strictly
  increasing) counts `offset(ofLine:)` calls and asserts the algorithmic contract
  at 1M lines — `compute` issues O(log N) queries (a bound proportional to
  `log2(lineCount)`, comfortably under a small constant × `log2 N`, versus the ~N a
  stray linear scan would make). For geometry, a non-empty cursor issues exactly
  `bufferSize + 1` queries (one seed plus one bottom offset per emitted line), and
  an empty cursor issues **zero** queries because it must not seed an offset it
  will never emit. This catches an accidental O(N) scan deterministically, in the
  unit suite, independent of wall-clock/CI variance — complementing the perf gate,
  which then only has to cover constant factors. Edge inputs (empty, single line,
  the `effOffsetY >= totalHeight` clamp short-circuit) are included so no path
  scans. The implementation plan for this slice must include a concrete task/file
  for this test; it is not optional documentation.
- scale correctness and the locally-enforcing performance gate via
  `PrefixSumLineMetrics` at 1M lines.

## Verification

This slice changes the public core API, so the full verification set runs:

- `swift test` (host XCTest suite, including the new variable-height tests);
- `swift build -c release`;
- `rg -n "Foundation" Sources/TextEngineCore` (must return no matches — the
  brief's no-Foundation-in-core constraint, re-checked because this slice changes
  the public surface);
- `swift run -c release ViewportBenchmarks -- --gate` (synthetic gate, unchanged);
- `swift run -c release ViewportBenchmarks -- --variable-height --gate` (the new
  variable-height gate — enforces budgets locally; in CI the benchmark runs without
  `--gate` as an observation-only step this slice);
- workflow scan for the hosted observation step: `Run variable-height benchmark
  observation`, `continue-on-error: true`, and
  `swift run -c release ViewportBenchmarks -- --variable-height` with no
  `--variable-height --gate` in `.github/workflows/swift-ci.yml`;
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
- [ ] The fixed-height entry points keep their signatures and runtime behavior
  unchanged. The shared `ViewportValidationError` gains the additive
  `invalidLineMetrics` case — a source break only for an exhaustive `switch`
  without a `default` (none exists in this package; see the Decision 4 migration
  note). The existing tests, synthetic gate, memory-shape, and memory-observation
  pass without retuning.
- [ ] `ViewportValidationError` gains only the additive `invalidLineMetrics`
  case; existing cases are unchanged.
- [ ] `TextEngineCore` stays Foundation-free: `rg -n "Foundation"
  Sources/TextEngineCore` returns no matches.
- [ ] offset→line and line→offset are correct across the boundary, mid-line,
  clamp, empty, single-line, `viewportHeight == 0`, and huge/negative-offset
  cases.
- [ ] The `UniformLineMetrics` equivalence oracle passes **exactly** (with
  exactly-representable line heights) for the enumerated boundary positions and a
  non-boundary matrix.
- [ ] The shared overscan→buffer→flags helper is used by both `compute` paths
  with no behavior change to the fixed path.
- [ ] `--variable-height --gate` enforces budgets locally and passes at
  1k / 100k / 1M lines with generous headroom; the CI step runs the benchmark
  observation-only (without `--gate`, with `continue-on-error: true`) after the
  synthetic-gate step.
- [ ] A `CountingLineMetrics` query-count test asserts `compute` issues O(log N)
  `offset(ofLine:)` queries, a non-empty geometry cursor issues exactly
  `bufferSize + 1`, and an empty geometry cursor issues zero queries, at 1M lines
  and on the empty / single-line / clamp edge inputs. This acceptance criterion is
  backed by a dedicated implementation-plan task/test file, not only by prose.
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
- promoting the variable-height CI step from observation-only to CI-failing
  enforcement (its own follow-up slice; see Future Slices and Decision 6);
- repository branch protection / required status checks (Slice 6 external
  blocker, unchanged);
- storage adapters / additional providers;
- memory hard budgets (RSS, heap, malloc, allocation-count);
- shaping, rasterization, or any real (content-derived or asynchronous)
  measurement source;
- UI-framework integration.

## Future Slices

- **Variable-height gate CI promotion**: collect a handful of hosted p95/p99
  samples for the variable-height benchmark, set the budget from
  `max(local, hosted) · safety_factor` with generous headroom, and promote the CI
  step from observation-only to `--variable-height --gate` (CI-failing) — unless
  the hosted margin is thin, in which case keep it observational (the Slice 10
  fallback). This is the deliberately-separated benchmark-enforcement slice
  (Slice 12 review #5).
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
- **Anchored / galloping search** (deliberately NOT now): the stateless O(log N)
  binary search recomputes from scratch every frame. If a future gate shows that
  search cost dominates on incremental scroll, the core could accept a caller-supplied
  hint (the previous frame's top line) and gallop from it in O(log Δ), keeping the
  `offset(ofLine:)` contract but returning per-frame state. This is consciously
  deferred to preserve the pure-transform, stateless design (Decision 1/2);
  statelessness here is a chosen trade-off, not an oversight.
