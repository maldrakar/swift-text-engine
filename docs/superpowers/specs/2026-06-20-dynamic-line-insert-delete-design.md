# Dynamic Line Insert/Delete Provider Design

Date: 2026-06-20

## Status

Approved direction, written for user review.

## Source Context

This is Slice 23 of SwiftTextEngine, the **first functional-core slice since
Slice 17**. Slice 17 delivered `FenwickLineMetrics`: a mutable, indexed
`LineMetricsSource` whose single-line **height** change is a localized O(log N)
update (vs the O(N) rebuild a prefix-sum array needs), proving cheap incremental
re-layout while `TextEngineCore` stays unchanged. Slices 18–22 were all
CI / portability / governance hardening (trusted docs-only gate, required-check
ruleset, policy-sensitive path hardening, variable-height-mutation CI gate
promotion, cross-target provider coverage). The Slice 22 post-slice review
recommends returning to functional core work and names line insert/delete its
Option B; the user selected it for Slice 23.

Current reference providers, all in the Foundation-free
`TextEngineReferenceProviders` library (created in Slice 17):

- `PrefixSumLineMetrics` — O(1) `offset(ofLine:)`, O(N) rebuild on any change;
  the correctness oracle.
- `FenwickLineMetrics` — O(log N) `offset` and O(log N) `setHeight` (Binary
  Indexed Tree), with deterministic `lastUpdateWriteCount` evidence. Supports
  **height** mutation at a fixed `lineCount` only.
- `UniformLineMetrics` — in the core, the uniform-equivalence reference.

The `TextEngineReferenceProvidersTests` XCTest target already exists (Slice 17)
and depends on both `TextEngineReferenceProviders` and `TextEngineCore`. `main`
is clean; the core is Foundation-free, zero-dependency, and Embedded /
cross-target compatible.

## Problem

A Fenwick tree (and a prefix-sum array) is keyed by a **fixed** line index: it
supports changing a line's height cheaply, but **inserting or deleting a line in
the middle of the document — which changes `lineCount` and shifts every
subsequent line's index — costs O(N)** (an array shift plus aggregate rebuild).
Real editing is dominated by exactly these structural edits (typing a newline,
deleting a line, pasting a block). The brief requires stable performance on
100k+ line / >10 MB documents with the document living outside the core behind a
provider abstraction. What is missing is a reference provider that turns a
mid-document line **insert or delete** into a **localized O(log N) update**,
proving cheap incremental re-layout under structural editing while
`TextEngineCore` stays completely unchanged.

## Scope

Add a mutable, indexed reference `LineMetricsSource` implementation
(`BalancedTreeLineMetrics`) backed by a **size-balanced order-statistics binary
search tree**, whose line `insertLine`, `removeLine`, and `setHeight` operations
are each O(log N) and whose `offset(ofLine:)` query is O(log N). Prove — by unit
tests, a deterministic operation-count, a tree-height invariant, and a local
benchmark — that re-layout after a structural edit is cheap and that the
stateless core composes correctly with the mutated provider **without any core
change**.

This slice is a functional-core slice confined to
`Sources/TextEngineReferenceProviders`, `Tests/TextEngineReferenceProvidersTests`,
and `Sources/ViewportBenchmarks`. It does **not** change `TextEngineCore` source
or public API, and it does **not** touch `.github/workflows/swift-ci.yml`.

## Goals

- Add `BalancedTreeLineMetrics`: a size-balanced order-statistics BST in a flat
  `[Node]` arena (integer child indices, no pointers/classes/ARC), with O(log N)
  `offset(ofLine:)`, `insertLine(at:height:)`, `removeLine(at:)`, and
  `setHeight(ofLine:to:)`, and O(N) `init(heights:)` build.
- Expose deterministic O(log N) evidence via `lastMutationNodeVisits` (number of
  nodes visited by the last mutation), mirroring `FenwickLineMetrics`'s
  `lastUpdateWriteCount`.
- Prove, by XCTest: build correctness against the prefix-sum oracle; structural
  mutation correctness against a freshly-rebuilt oracle (insert / delete /
  setHeight in lockstep with an array); the strictly-increasing invariant; a
  logarithmic node-visit bound that grows sub-linearly with size; a tree-height
  invariant `height ≤ C·log₂N` after a deterministic edit sequence; and correct,
  cheap re-layout composition with the stateless core after a structural edit.
- Add a `--structural-mutation` benchmark mode with a **local** `--gate`.
- Keep `TextEngineCore`, `Tests/TextEngineCoreTests`, `FenwickLineMetrics`,
  `PrefixSumLineMetrics`, and `Package.swift` unchanged.

## Non-Goals

- No change to `TextEngineCore` source or public API; the core stays stateless
  and generic over `LineMetricsSource`.
- No replacement or removal of `FenwickLineMetrics`. The new tree functionally
  supersedes it (it does everything Fenwick does plus structural edits), but
  Fenwick stays as the lighter-constant height-only provider and keeps the
  proven `--variable-height-mutation` gate unchanged. Both coexist — a menu of
  reference providers.
- No fractional-height exact equivalence (would need a tolerance); equivalence
  tests use integer-valued heights so partial sums are bit-exact regardless of
  summation order.
- No zero-height / collapsed-line support (contract still requires strictly
  increasing offsets).
- **No CI workflow change.** The new benchmark is locally gated only this slice.
  Promotion to a blocking (or observation-only) CI gate is a deliberate
  follow-on slice, mirroring the established gate-promotion pattern (the
  functional slice adds a local gate; a later slice promotes it in CI), used for
  both the variable-height and variable-height-mutation benchmarks. This slice's
  diff is intentionally confined to `Sources/**`, `Tests/**`, and docs.
- No range/bulk insert/delete API; single-line `insertLine` / `removeLine` only.
  Bulk edits compose from single-line ops this slice.
- No `--memory-shape` scenario for the new provider — the core path is
  unchanged, so core-owned memory shape is already proven; provider-owned memory
  is O(N) (the document) and allowed by the brief.

## Decisions

### Decision 1 — Data structure: size-balanced order-statistics BST in a flat arena

`BalancedTreeLineMetrics` stores the document lines as in-order nodes of a binary
search tree whose key is the **implicit line index** (in-order position), held in
a flat arena:

```
struct Node {
    var height: Double          // this line's height (finite, > 0)
    var left: Int               // arena index of left child, -1 == none
    var right: Int              // arena index of right child, -1 == none
    var subtreeCount: Int       // number of lines in this subtree (incl. self)
    var subtreeHeightSum: Double// sum of heights in this subtree (incl. self)
}
```

State: `nodes: [Node]` (the arena), `root: Int` (-1 when empty), and
`freeList: [Int]` of recycled slots from `removeLine`. `lineCount` is the root's
`subtreeCount` (0 when `root == -1`), O(1).

- `offset(ofLine: index)` = sum of heights of lines `[0, index)`, computed by an
  order-statistics descent: at a node whose left subtree holds `cL` lines with
  height-sum `sL`, the node sits at position `cL`. If `index <= cL`, recurse left
  with the same `index`. Otherwise add `sL` (all of the left subtree) plus the
  node's own `height` (position `cL < index`), then recurse right with
  `index - cL - 1`. O(tree height) = O(log N).
- `insertLine(at: index, height:)` descends by position to the leaf insertion
  point, splices in a fresh node (reusing a `freeList` slot when available),
  fixes aggregates up the path, and rebalances. O(log N).
- `removeLine(at: index)` descends to the target, removes it (standard BST delete:
  in-order successor swap when two children), returns its slot to `freeList`,
  fixes aggregates, and rebalances. O(log N).
- `setHeight(ofLine: index, to:)` descends to the target node, updates its
  `height`, and adds the delta to `subtreeHeightSum` along the ancestor path.
  O(log N). (No structural change, no rebalance.)
- `init(heights:)` builds a **perfectly balanced** BST directly from the array by
  recursive midpoint, filling the arena and computing aggregates bottom-up, in
  O(N) (no rotations).

A segment tree (range-query power we do not need, ~2N nodes) and
sqrt-decomposition (O(√N), contradicting the localized-O(log N) goal) are
rejected. A Fenwick tree is rejected for this slice because it cannot do
mid-document insert/delete cheaply — that is the whole problem.

### Decision 2 — Balance: size-balanced (deterministic), no PRNG

Balance is maintained by subtree **size** — the `subtreeCount` aggregate that
order-statistics already requires — using a Size-Balanced-Tree (SBT) style
`maintain` after each structural edit (rotations restoring "no subtree is smaller
than a nephew"). This guarantees `height = O(log N)` and amortized O(log N) per
operation with a **deterministic shape** derived solely from the operation
sequence. It needs **no random priorities**, avoiding the "PRNG under Embedded
Swift" question a treap would raise, and reuses the size aggregate we maintain
anyway. (A weight-balanced BB[α] tree is an equivalent deterministic alternative;
SBT is chosen for its compact four-case `maintain`.) Each rotation recomputes the
two affected nodes' aggregates from their children
(`subtreeCount = 1 + count(left) + count(right)`,
`subtreeHeightSum = height + sum(left) + sum(right)`), keeping order-statistics
correct through rebalancing.

### Decision 3 — Operation API and absolute heights

The mutation surface is `insertLine(at:height:)`, `removeLine(at:)`, and
`setHeight(ofLine:to:)`. `setHeight` takes the absolute new height (matching the
real "this line re-measured to height X" event, consistent with
`FenwickLineMetrics`). Insertion takes the new line's absolute height. No
relative-adjust or bulk variants this slice.

### Decision 4 — `lastMutationNodeVisits` instrumentation

`BalancedTreeLineMetrics` exposes `public private(set) var lastMutationNodeVisits:
Int`, set by every structural/height mutation to the number of nodes visited
(descent + rebalance touches), and each mutation returns it (`@discardableResult
-> Int`), mirroring `FenwickLineMetrics.lastUpdateWriteCount`. **Unlike Fenwick's
exact closed form** (`⌊log₂N⌋+1`), a balanced tree's visit count depends on shape
and rotations, so this is a logarithmic **upper bound** ∝ log N, not an exact
formula. It is honest work, not test scaffolding, and is the deterministic
evidence for the O(log N) update claim. The actual tree height — the direct
balance guarantee that this bound depends on — is asserted separately by the
tree-height invariant test (Component Design test 5), which reads it via an
`internal func treeHeight() -> Int` exposed only through `@testable import`, so
the tree shape stays out of the public API while remaining test-verifiable.

### Decision 5 — Provider precondition handling

Matching `FenwickLineMetrics`: `offset(ofLine:)` honors the `LineMetricsSource`
contract (domain `0...lineCount`, `offset(0) == 0`, strictly increasing for
positive heights) and does **not** re-validate the core's preconditions. To keep
offsets strictly increasing, `init(heights:)`, `insertLine`, and `setHeight`
require finite, positive heights; index ranges are `0...lineCount` for
`insertLine` and `0..<lineCount` for `removeLine` / `setHeight`. These are
enforced with `precondition(_:)` and **static** string messages (fire in release
as well as debug, Embedded-safe). No throwing / `Result` API — kept Embedded-clean
and consistent with the provider style.

### Decision 6 — Value semantics and no target restructure

`BalancedTreeLineMetrics` is a `struct` whose arena is a Swift `[Node]` array, so
it has the same copy-on-write value semantics as the other providers — a snapshot
copied before mutation stays stable for one layout operation (the
`LineMetricsSource` stability precondition). The `TextEngineReferenceProviders`
library and the `TextEngineReferenceProvidersTests` target already exist (Slice
17), so this slice only **adds files** — `BalancedTreeLineMetrics.swift` and
`BalancedTreeLineMetricsTests.swift` — and a benchmark file. `Package.swift` is
unchanged.

## Component Design

### Target layout (only additions)

```
Sources/
  TextEngineReferenceProviders/
      BalancedTreeLineMetrics.swift          (NEW)
  ViewportBenchmarks/
      StructuralMutationBenchmark.swift      (NEW)
      BenchmarkOptions.swift                 (edit: add mode + parse + usage)
      BenchmarkProgram.swift                 (edit: dispatch new mode)
Tests/
  TextEngineReferenceProvidersTests/
      BalancedTreeLineMetricsTests.swift     (NEW)
```

### `BalancedTreeLineMetrics` API

```swift
public struct BalancedTreeLineMetrics: LineMetricsSource {
    public private(set) var lastMutationNodeVisits: Int

    public init(heights: [Double])                       // O(N) balanced build

    public var lineCount: Int { ... }                    // O(1): root subtreeCount
    public func offset(ofLine index: Int) -> Double       // O(log N) order-statistics descent

    @discardableResult
    public mutating func insertLine(at index: Int, height: Double) -> Int   // O(log N)
    @discardableResult
    public mutating func removeLine(at index: Int) -> Int                   // O(log N)
    @discardableResult
    public mutating func setHeight(ofLine index: Int, to newHeight: Double) -> Int  // O(log N)

    // Test-only white-box access, reached via `@testable import` (NOT public API):
    internal func treeHeight() -> Int   // iterative DFS over the arena; O(N)
}
```

(`removeLine` returns the node-visit count for instrumentation symmetry, not the
removed height — no consumer needs the removed height this slice. `treeHeight()`
is `internal`, used only by the tree-height invariant test; the public surface
never exposes the tree shape.)

### Tests (`TextEngineReferenceProvidersTests`, TDD failing-first)

Integer-valued non-uniform heights (e.g. `{14,16,20,32}`), totals < 2⁵³, so tree
height sums are bit-exactly equal to the prefix-sum oracle regardless of
summation association. The **array is the easy oracle**: apply the same
`insert` / `remove` / `setHeight` to a `[Double]`, rebuild
`PrefixSumLineMetrics(updated)`, and compare.

1. **Build correctness** — `offset(ofLine: i)` equals the `PrefixSumLineMetrics`
   oracle for all `i in 0...lineCount`, and `lineCount` matches.
2. **Structural mutation correctness (equivalence oracle)** — a deterministic
   (seeded) sequence of mixed `insertLine` / `removeLine` / `setHeight` applied
   in lockstep to the tree and to an array; after **each** operation, `lineCount`
   and every `offset(ofLine: i)` bit-exactly equal a freshly-built
   `PrefixSumLineMetrics` over the updated array. Covers head / tail / interior
   positions, insert-into-empty and remove-to-empty edges, and repeated edits.
3. **Strictly-increasing invariant** — after mutations, `offset(i) < offset(i+1)`
   for all `i`.
4. **Logarithmic node-visit bound** — `lastMutationNodeVisits` after a structural
   edit on `N = 1k / 100k / 1M` stays ≤ `C·(⌊log₂N⌋+1)` for a small constant `C`,
   and grows by a small additive amount across a 1000× size jump (not linearly).
5. **Tree-height invariant** — after a deterministic insert/delete sequence, the
   actual tree height is ≤ `C·log₂(lineCount)`, proving the balance guarantee
   directly (the primary worst-case-shape defense, complementing test 4). The
   height is read via an `internal func treeHeight() -> Int` (an iterative DFS
   over the arena from `root`, O(N)), reached by the test through
   `@testable import TextEngineReferenceProviders`. It is **test-only white-box
   instrumentation and stays out of the public provider API** — the public
   surface never exposes the tree shape.
6. **Re-layout composition** — after a structural edit, re-running
   `ViewportVirtualizer.compute(input, metrics: tree)` + `geometry(...)` yields a
   range and `LineGeometry` stream identical to running the same against a fresh
   `PrefixSumLineMetrics` over the updated heights. A counting wrapper confirms
   core `compute` still issues O(log N) offset queries after a structural edit.

### Benchmark mode (`ViewportBenchmarks`)

- New `--structural-mutation` mode (output name `structural_mutation`) over the
  existing 1k / 100k / 1M scenarios, modeled on `VariableHeightMutationBenchmark`.
  Fully deterministic so the executor measures exactly the intended path:
  - One `BalancedTreeLineMetrics` is built once per scenario from the
    deterministic `{14,16,20,32}` heights and **mutated in place**; no per-op
    rebuild of any structure, and the `PrefixSumLineMetrics` oracle never appears
    in the hot path.
  - Each measured operation pins `lineCount` constant by pairing a
    `removeLine(at: idx)` with an `insertLine(at: idx2, height:)` at deterministic
    positions spread across the document, then runs `compute` and a full geometry
    traversal. A running checksum consumes `lastMutationNodeVisits`, the range,
    and the geometry to prevent dead-code elimination.
  - Reports p95/p99 with a **local** `--gate`; budgets set from observed local
    numbers plus headroom (macOS-calibrated, like the other gates).
- `BenchmarkOptions`: add `.structuralMutation` to `BenchmarkMode`; `--gate` is
  **valid** with it; one mode flag at a time; rejected in combination with
  another mode. Update `--help`/usage. `BenchmarkProgram` dispatches the mode.
- Update the AGENTS.md command list and benchmark-flags note (the only doc edit;
  the spec/plan/verification/review live under `docs/superpowers/`).

### CI

**No `.github/workflows/swift-ci.yml` change this slice** (see Non-Goals). The
gate is exercised locally via `swift run -c release ViewportBenchmarks --
--structural-mutation --gate`. A follow-on gate-promotion slice will add the
hosted observation step and then the blocking gate with Linux-calibrated budgets.

## Verification

Recorded with actual commands and outputs, anchored on the post-merge push run:

- `swift test` — new tests pass; total grows from the current baseline.
- `swift build -c release` — `Build complete!`.
- `swift build -c release --target TextEngineReferenceProviders` — `Build
  complete!` (the provider library builds in isolation).
- `swift run -c release ViewportBenchmarks -- --gate` — `gate=pass`.
- `swift run -c release ViewportBenchmarks -- --variable-height --gate` —
  `gate=pass`.
- `swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate`
  — `gate=pass` (unchanged Fenwick gate still green).
- `swift run -c release ViewportBenchmarks -- --structural-mutation --gate` —
  `gate=pass` (the new local gate).
- `swift run -c release ViewportBenchmarks -- --memory-shape` —
  `invariant=pass`.
- `rg -n "Foundation" Sources/TextEngineCore` — empty.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` — empty.
- `./.github/scripts/cross-target-compile.sh --self-test` — `self_test=pass`.
- `git diff --check` — empty; `git diff --name-only` touches only
  `Sources/TextEngineReferenceProviders`, `Sources/ViewportBenchmarks`,
  `Tests/TextEngineReferenceProvidersTests`, `AGENTS.md`, and `docs/**`.
- Hosted PR run + post-merge push run IDs, both `success` (the existing three
  required jobs; no new job).

## Risks And Gaps

- **Rebalance correctness with aggregates.** The main implementation risk is
  carrying `subtreeCount` / `subtreeHeightSum` correctly through every rotation
  and the delete successor-swap. Mitigated by the equivalence oracle (test 2,
  after every op) and the tree-height invariant (test 5); a single mis-maintained
  aggregate fails the oracle immediately.
- **Provider is host-compiled, not Embedded-proven this slice.** Like
  `FenwickLineMetrics`, it is Foundation-free and written Embedded-style (arrays
  + `Int`/`Double`, no classes/ARC), proven to compile on the host. The
  cross-target helper already compiles `TextEngineReferenceProviders` for iOS
  (blocking) and WASM (observational) as of Slice 22, so the new file rides that
  coverage once merged — but this slice does not add a dedicated Embedded compile
  step for it.
- **`lastMutationNodeVisits` is observable API.** `private(set)` and an honest
  count; it widens the reference provider's surface for instrumentation only and
  does not touch the core or the brief's public-API constraints.
- **Local gate only.** Budgets are macOS-calibrated and exercised locally;
  hosted observation and blocking promotion are a deferred follow-on slice. No
  regression protection in CI for structural mutation until that slice lands.
- **Node-visit count is a bound, not Fenwick's exact formula.** Acceptable: the
  tree-height invariant test provides the direct balance guarantee that the
  bound depends on.
