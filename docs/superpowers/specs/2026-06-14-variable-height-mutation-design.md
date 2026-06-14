# Variable-Height Mutation / Indexed Provider Design

Date: 2026-06-14

## Status

Approved direction, written for user review.

## Source Context

This is Slice 17 of SwiftTextEngine, the first functional slice since Slice 14.
Slice 14 delivered the *static* variable-height query foundation: the
`LineMetricsSource` protocol (`lineCount` + `offset(ofLine:)`), an O(log N)
binary-search `ViewportVirtualizer.compute(_:metrics:)`, and the streaming
`VariableLineGeometryCursor`. The core stayed stateless and O(1)-core-memory.
Slices 15 and 16 were CI/infrastructure work (variable-height gate promotion;
CI resource optimization). Both the Slice 14 and Slice 16 post-slice reviews
recommend variable-height mutation as the next functional slice; the Slice 16
review names it Option A and the user selected it for Slice 17.

The only reference provider that exists today is `PrefixSumLineMetrics`, defined
locally inside `Sources/ViewportBenchmarks/VariableHeightBenchmark.swift`. It
answers `offset(ofLine:)` in O(1) from a precomputed prefix-sum array, but **any
single-line height change forces an O(N) rebuild of the whole array**. There is
a second near-identical copy of the same prefix-sum logic, `ListLineMetrics`, in
`Tests/TextEngineCoreTests/TestLineMetrics.swift`.

`main` is clean. A fresh local `swift test` baseline passes with 67 XCTest tests
and 0 failures (plus the expected empty Swift Testing harness line). The core is
Foundation-free, zero-dependency, and Embedded/cross-target compatible.

## Problem

A real document is edited and re-measured: a single line's height changes (font
load, reflow, re-shape). With the static prefix-sum provider, reflecting that one
change costs O(N) to rebuild cumulative offsets, which does not scale to the
brief's 100k+ line / >10 MB documents. The brief requires the document to live
outside the core behind a provider abstraction, with strict virtualization and
core-owned memory that does not grow with document size. Nothing in the brief
forbids the *provider* from holding O(N) document metrics — that O(N) data **is**
the document. What is missing is a reference provider that turns a single-line
height change into a **localized O(log N) update** instead of an O(N) rebuild,
proving that cheap incremental re-layout is achievable while `TextEngineCore`
stays completely unchanged.

## Scope

Add a mutable, indexed reference `LineMetricsSource` implementation
(`FenwickLineMetrics`) whose single-line height change is an O(log N) update and
whose `offset(ofLine:)` query is O(log N), and prove — by unit tests, a
deterministic operation-count, and a benchmark — that re-layout after a mutation
is cheap while the stateless core composes correctly with the mutated provider
**without any core change**.

This slice is a functional-core slice that also introduces a small target
restructure to make reference providers unit-testable. It does **not** change
`TextEngineCore` source or public API.

### Height mutation only

Slice 17 covers **height mutation at a fixed `lineCount`**. Line insertion and
deletion (which change `lineCount`) are a separate, larger story — a Fenwick tree
does not support cheap mid-array insert/delete — and are explicitly deferred.

## Goals

- Introduce a Foundation-free `TextEngineReferenceProviders` library target that
  is the shared home for reference `LineMetricsSource` implementations, usable by
  both `ViewportBenchmarks` and a new XCTest target.
- Move `PrefixSumLineMetrics` out of the benchmark executable into that library,
  removing the benchmark-local copy.
- Add `FenwickLineMetrics`: O(log N) `offset(ofLine:)` and O(log N)
  `setHeight(ofLine:to:)` single-line update, backed by a Binary Indexed Tree.
- Prove, by XCTest: build correctness against the prefix-sum oracle; mutation
  correctness against a freshly-rebuilt oracle; the strictly-increasing
  invariant; a deterministic O(log N) update operation-count; O(log N) query
  cost; and correct, cheap re-layout composition with the stateless core.
- Add a `--variable-height-mutation` benchmark mode with a local `--gate` and an
  observation-only CI step.
- Keep `TextEngineCore` and `Tests/TextEngineCoreTests` unchanged.

## Non-Goals

- No change to `TextEngineCore` source or public API; no provider-specialized
  search added to the core (it stays stateless and generic over
  `LineMetricsSource`).
- No line insert/delete / `lineCount` mutation.
- No fractional-height exact equivalence (would require a tolerance); equivalence
  tests use integer-valued heights.
- No zero-height / collapsed-line support (contract still requires strictly
  increasing offsets).
- No promotion of the new benchmark to a blocking CI gate (deliberate future
  slice, mirroring the Slice 14 → Slice 15 variable-height gate split).
- No `--memory-shape` scenario for the mutation provider — the core path is
  unchanged, so core-owned memory shape is already proven by the existing
  `variable_uniform` scenario.
- No migration of `ListLineMetrics` (the third near-copy) — left in the core test
  target to avoid churn; consolidation is noted as future cleanup.

## Decisions

### Decision 1 — Data structure: Fenwick / Binary Indexed Tree

`FenwickLineMetrics` stores a parallel `heights: [Double]` array (per-line
heights) and a 1-based BIT `tree: [Double]` of size `lineCount + 1`.

- `offset(ofLine: i)` = prefix sum `heights[0..<i]` via a BIT query that walks
  `index -= index & (-index)`, in O(log N).
- `setHeight(ofLine: i, to: newHeight)` computes `delta = newHeight -
  heights[i]` in O(1) (from the heights array), updates `heights[i]`, then does
  one BIT point-update walking `index += index & (-index)`, in O(log N).
- Build from `heights` in O(N).

A segment/sum tree (O(log N) but ~2N nodes and range-query power we do not need)
and sqrt-decomposition (O(√N), which contradicts the localized-O(log N) goal) are
rejected.

### Decision 2 — The indexed provider trades O(1) query for O(log N) query

The prefix-sum provider answers `offset` in O(1) but rebuilds in O(N). The
Fenwick provider answers `offset` in O(log N) and updates in O(log N). Therefore,
with the Fenwick provider, the unchanged generic core `compute` performs
O(log²N) work (its O(log N) binary search × O(log N) per offset query) and
geometry streams in O(buffer · log N). This is still trivially within budget
(log²(1M) ≈ 400) and is the explicit reason both providers coexist: prefix-sum
for static documents, Fenwick for mutated documents. The core is **not**
specialized for the BIT; it stays stateless and generic.

### Decision 3 — Absolute `setHeight`, not relative adjust

The mutation API is `setHeight(ofLine: index, to: newHeight)`, taking the
absolute new height. This matches the real event ("this line re-measured to
height X"); the parallel `heights` array makes the `delta` computation O(1). No
relative `adjustBy:` variant in this slice.

### Decision 4 — `lastUpdateWriteCount` instrumentation

`FenwickLineMetrics` exposes `public private(set) var lastUpdateWriteCount: Int`,
set by `setHeight` to the exact number of BIT cells written (the set-bit step
count of the update walk, ≤ ⌊log₂N⌋+1). `setHeight` also returns this count
(`@discardableResult`). This is an honest count of real work, not test-only
scaffolding, and it is the deterministic evidence for the O(log N) update claim —
mirroring how the repo already pins core query counts in
`VariableHeightQueryCountTests`.

### Decision 5 — Provider precondition handling

`offset(ofLine:)` honors the `LineMetricsSource` contract (domain `0...lineCount`,
`offset(0) == 0`, strictly increasing for positive heights) and does **not**
re-validate the core's preconditions — the same division of responsibility as
`PrefixSumLineMetrics`. `setHeight` requires a finite, positive `newHeight` so
offsets stay strictly increasing; a non-positive / non-finite height is a
documented provider precondition violation (debug `assert`, no silent BIT
corruption). No throwing/`Result` API — kept Embedded-clean and consistent with
the provider style.

### Decision 6 — Target restructure for testability

Reference providers must stay out of the Foundation-free core (per AGENTS.md) yet
be unit-testable. `Tests/TextEngineCoreTests` depends only on `TextEngineCore`,
and `ViewportBenchmarks` is an executable that uses top-level `main.swift` (so it
cannot be cleanly `@testable import`ed). The resolution is a new Foundation-free
`TextEngineReferenceProviders` library target depending on `TextEngineCore`,
consumed by both `ViewportBenchmarks` and a new `TextEngineReferenceProvidersTests`
target. `Tests/TextEngineCoreTests` is left unchanged (Core-only); `ListLineMetrics`
stays.

## Component Design

### Target layout

```
Sources/
  TextEngineCore/                    (lib, Foundation-free)   — UNCHANGED
  TextEngineReferenceProviders/      (lib, Foundation-free)   — NEW
      PrefixSumLineMetrics.swift     (moved from benchmarks)
      FenwickLineMetrics.swift       (new)
  ViewportBenchmarks/                (exe)  deps: TextEngineCore + TextEngineReferenceProviders
Tests/
  TextEngineCoreTests/               (test) -> TextEngineCore             — UNCHANGED
  TextEngineReferenceProvidersTests/ (test) -> TextEngineReferenceProviders — NEW
```

`Package.swift` gains: the `TextEngineReferenceProviders` target, a matching
`.library` product, the new test target, and the dependency edge from
`ViewportBenchmarks`. `VariableHeightBenchmark.swift` drops its local
`PrefixSumLineMetrics` definition and imports it from the library.

### `FenwickLineMetrics` API

```swift
public struct FenwickLineMetrics: LineMetricsSource {
    private var heights: [Double]      // count == lineCount
    private var tree: [Double]         // 1-based BIT; count == lineCount + 1

    public private(set) var lastUpdateWriteCount: Int

    public init(heights: [Double])     // O(N) build

    public var lineCount: Int { heights.count }

    public func offset(ofLine index: Int) -> Double   // O(log N) BIT prefix sum

    @discardableResult
    public mutating func setHeight(ofLine index: Int, to newHeight: Double) -> Int
}
```

### Tests (`TextEngineReferenceProvidersTests`, TDD failing-first)

Integer-valued non-uniform heights (e.g. `{14,16,20,32}`), totals < 2⁵³, so BIT
sums are bit-exactly equal to the prefix-sum oracle.

1. **Build correctness** — `offset(ofLine: i)` equals the `PrefixSumLineMetrics`
   oracle for all `i in 0...lineCount`.
2. **Mutation correctness (equivalence oracle)** — after a sequence of
   `setHeight` calls, every `offset(ofLine: i)` exactly equals a freshly-built
   `PrefixSumLineMetrics` over the updated heights. Covers first / last /
   interior lines and repeated edits to one line.
3. **Strictly-increasing invariant** — after mutations, `offset(i) < offset(i+1)`
   for all `i`.
4. **Localized O(log N) update (deterministic)** — `setHeight` returns the exact
   BIT write count for known `(N, index)` pairs, and for `N = 1k / 100k / 1M` the
   count stays ≤ ⌊log₂N⌋+1 (grows by ~10 across a 1000× size jump, not linearly).
5. **O(log N) query cost** — a single `offset(ofLine:)` walks exactly
   `popcount(index)` BIT cells, which is ≤ ⌊log₂N⌋+1; asserted by the
   deterministic set-bit-count formula (no separate read counter needed).
6. **Re-layout composition** — after a `setHeight`, re-running
   `ViewportVirtualizer.compute(input, metrics: fenwick)` + `geometry(...)`
   yields a range and `LineGeometry` stream identical to running the same against
   a fresh `PrefixSumLineMetrics` with the updated heights. A counting wrapper
   confirms core `compute` still issues O(log N) offset queries after mutation.

### Benchmark mode (`ViewportBenchmarks`)

- New `--variable-height-mutation` mode. Each operation = `setHeight` on one line
  **then** `compute` + geometry traversal, over the deterministic
  `{14,16,20,32}` heights, for the existing 1k / 100k / 1M scenarios. Reports
  p95/p99 with a local `--gate`; budgets set from observed local numbers plus
  headroom.
- `BenchmarkOptions`: add the mode; `--gate` is **valid** with it; it is
  **rejected** with `--range-only` / `--memory-shape` / `--memory-observation`;
  one mode flag at a time. Update `--help` and the AGENTS.md command list.

### CI

Add an observation-only step (`continue-on-error: true`, no `--gate`) after the
variable-height gate, exactly how the variable-height benchmark entered in Slice
14 before its Slice 15 promotion. Use `shell: bash` if the step needs
`pipefail` (heeding the Slice 16 P2 finding). Promotion to a blocking gate is a
future slice.

## Verification

Recorded with actual commands and outputs, anchored on the post-merge push run:

- `swift test` — new tests pass; total grows from 67.
- `swift build -c release` — `Build complete!`.
- `swift run -c release ViewportBenchmarks -- --gate` — `gate=pass`.
- `swift run -c release ViewportBenchmarks -- --variable-height --gate` —
  `gate=pass`.
- `swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate`
  — `gate=pass`.
- `swift run -c release ViewportBenchmarks -- --memory-shape` —
  `invariant=pass`.
- `swift run -c release ViewportBenchmarks -- --memory-observation` —
  `observation=pass`.
- `rg -n "Foundation" Sources/TextEngineCore` — empty.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` — empty.
- `./.github/scripts/cross-target-compile.sh --self-test` — `self_test=pass`.
- `git diff --check` — empty.
- Hosted PR run + post-merge push run IDs, both `success`.

## Risks And Gaps

- **New library not in the blocking cross-compile.** `cross-target-compile.sh`
  and the Foundation-free scan target `TextEngineCore` specifically. The new
  library is Foundation-free and Embedded-friendly by construction, but this
  slice does not add it to the blocking iOS/WASM cross-compile. Acceptable: it is
  a host-side reference provider, not core. Adding it to cross-target coverage is
  optional follow-up.
- **`lastUpdateWriteCount` is observable API.** It is `private(set)` and an honest
  count, but it widens the provider's public surface for instrumentation. Scoped
  to the reference provider (not the core), so it does not affect the brief's
  public-API constraints.
- **Benchmark stays observation-only in CI.** Like Slice 14's variable-height
  benchmark, the new mode is locally gated but only observed in CI this slice;
  promotion is deferred.
- **`ListLineMetrics` duplication remains.** Three near-copies of prefix-sum
  logic existed; this slice consolidates the benchmark copy into the library but
  leaves the core-test copy in place to avoid churn.
