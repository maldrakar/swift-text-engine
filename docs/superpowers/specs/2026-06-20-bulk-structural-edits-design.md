# Bulk/Range Structural Edits Design

Date: 2026-06-20

## Status

Approved direction, written for user review.

## Source Context

This is Slice 25 of SwiftTextEngine, a **functional-core slice building directly
on Slice 23's `BalancedTreeLineMetrics`** (Slice 24, between them, was the CI gate
promotion for that provider). Slice 23 added a mutable, indexed
`LineMetricsSource` backed by a **size-balanced order-statistics BST** in a flat
arena, with single-line `insertLine(at:height:)`,
`removeLine(at:)`, and `setHeight(ofLine:to:)` — each O(log N) — plus
`offset(ofLine:)` O(log N) and an O(N) balanced `init(heights:)`. Slice 24 then
promoted that provider's `--structural-mutation` benchmark to a **blocking**
hosted CI gate, so all four latency paths (synthetic, static variable-height,
variable-height mutation, structural mutation) now block merge on regression. The
Slice 24 post-slice review found no open CI/governance gap and recommends
returning to functional-core work; the user selected **Option A — bulk/range
structural edits** for Slice 25, and chose the **true-bulk O(k + log N)** algorithm
over a compose-only O(k·log N) wrapper.

Current reference providers, all in the Foundation-free
`TextEngineReferenceProviders` library:

- `PrefixSumLineMetrics` — O(1) `offset(ofLine:)`, O(N) rebuild on any change; the
  correctness oracle. Its bulk equivalents in tests are `Array`'s own
  `insert(contentsOf:at:)` / `removeSubrange`.
- `FenwickLineMetrics` — O(log N) `offset` and `setHeight`; height mutation at a
  fixed `lineCount` only (no structural insert/delete).
- `BalancedTreeLineMetrics` — the Slice 23 size-balanced order-statistics BST;
  the only provider with structural insert/delete. The target of this slice.
- `UniformLineMetrics` — in the core, the uniform-equivalence reference.

`main` is clean; the core is Foundation-free, zero-dependency, and Embedded /
cross-target compatible. The `TextEngineReferenceProvidersTests` XCTest target
already exists and depends on both `TextEngineReferenceProviders` and
`TextEngineCore`.

## Problem

`BalancedTreeLineMetrics` exposes only **single-line** structural edits. Real
editing produces **contiguous multi-line** structural changes: pasting a block,
deleting a multi-line selection, replacing a region. Today a caller must loop the
single-line ops, which is **O(k·log N)** for a `k`-line batch — for a large paste
(e.g. 10k lines into a 1M-line document) that is ~200k node touches versus the
~10k a true bulk operation needs. The brief requires stable performance on 100k+
line / >10 MB documents, and a benchmark-gated engine should not let a pathological
large paste or range delete cause a frame hitch. What is missing is an **atomic,
batched insert/delete-range API** whose cost is **O(k + log N)** — building the
inserted run as a balanced subtree in O(k) and splicing it with O(log N) tree
restructuring — proving cheap bulk re-layout while `TextEngineCore` stays
completely unchanged.

## Scope

Add two batched methods to `BalancedTreeLineMetrics`:

- `insertLines(at index: Int, heights: [Double]) -> Int`
- `removeLines(at index: Int, count: Int) -> Int`

implemented with **split** and **join** primitives over the existing size-balanced
tree so each is **O(k + log N)** (where `k` is the batch size), not O(k·log N).
Prove — by an equivalence oracle, a bulk-equals-compose oracle, a tree-height
invariant, and a deterministic visit-count characteristic — that bulk edits are
correct and cheap and that the stateless core composes correctly with the mutated
provider **without any core change**. Add a `--bulk-structural-mutation` benchmark
mode with a **local** `--gate`.

This slice is a functional-core slice confined to
`Sources/TextEngineReferenceProviders`, `Tests/TextEngineReferenceProvidersTests`,
and `Sources/ViewportBenchmarks` (plus `AGENTS.md` and `docs/**`). It does **not**
change `TextEngineCore` source or public API, and it does **not** touch
`.github/workflows/swift-ci.yml`.

## Goals

- Add `insertLines(at:heights:)` and `removeLines(at:count:)` to
  `BalancedTreeLineMetrics`, each `@discardableResult -> Int` returning the
  node-visit count and recorded in `lastMutationNodeVisits`, mirroring the
  single-line ops.
- Implement them via internal `split(at:)` and `join(_:_:)` primitives plus the
  existing `buildBalanced`, achieving **O(k + log N)** while preserving the
  size-balance invariant (logarithmic height) for subsequent operations.
- Recycle the `count` removed slots onto `freeList`, preserving the bounded
  slot-reuse the single-line `removeLine` already relies on (no unbounded arena
  growth across bulk edit churn).
- Prove, by XCTest: bulk insert/remove correctness against the array oracle;
  bulk-equals-compose equivalence; the strictly-increasing invariant; a tree-height
  invariant after bulk churn; an O(k + log N) visit characteristic; and correct,
  cheap re-layout composition with the stateless core after a bulk edit.
- Add a `--bulk-structural-mutation` benchmark mode with a **local** `--gate`.
- Keep `TextEngineCore`, `Tests/TextEngineCoreTests`, `FenwickLineMetrics`,
  `PrefixSumLineMetrics`, the single-line tree ops, and `Package.swift` unchanged.

## Non-Goals

- No change to `TextEngineCore` source or public API; the core stays stateless and
  generic over `LineMetricsSource`. Mutations are provider methods, not part of the
  `LineMetricsSource` protocol.
- No bulk ops on `FenwickLineMetrics` (fixed-size, no structural) or
  `PrefixSumLineMetrics` (the naive array oracle; its bulk behavior is `Array`'s
  own range methods in tests).
- No change to the existing single-line `insertLine` / `removeLine` / `setHeight`
  behavior or signatures. (`split`/`join` are added; the single-line paths may
  optionally be re-expressed over them only if it does not regress the
  `--structural-mutation` gate — default is to leave them untouched.)
- No relative-height or content payload; `insertLines` takes absolute heights, same
  as `insertLine`.
- No fractional-height exact equivalence; equivalence tests use integer-valued
  heights so partial sums are bit-exact regardless of summation order.
- No zero-height / collapsed-line support (contract still requires strictly
  increasing offsets).
- **No CI workflow change.** The new benchmark is locally gated only this slice.
  Promotion to a blocking hosted gate is a deliberate follow-on slice (Slice 26),
  mirroring the established cadence used for the variable-height,
  variable-height-mutation, and structural-mutation gates (functional slice adds a
  local gate; a later slice promotes it in CI with Linux-fit budgets). This slice's
  diff is intentionally confined to `Sources/**`, `Tests/**`, `AGENTS.md`, and docs.
- No `--memory-shape` scenario for the new path — the core is unchanged, so
  core-owned memory shape is already proven; provider-owned memory is O(N) (the
  document) and allowed by the brief.

## Decisions

### Decision 1 — True bulk via split/join, target O(k + log N)

The user selected the true-bulk algorithm over a compose-only O(k·log N) wrapper.
Both batch ops are built from three primitives:

- `buildBalanced(heights)` (already present) — a perfectly balanced subtree from
  `k` heights in **O(k)**, no rotations.
- `split(_ root, at index) -> (left, right)` — partition the tree at in-order
  position `index` so `left` holds lines `[0, index)` and `right` holds
  `[index, lineCount)`. **O(log N)**.
- `join(_ left, _ right) -> root` — concatenate two trees where every key in
  `left` precedes every key in `right`, restoring balance. **O(log N)**.

Then:

- `insertLines(at: index, heights:)` =
  `mid = buildBalanced(heights); (l, r) = split(root, at: index);
  root = join(join(l, mid), r)` → **O(k + log N)**.
- `removeLines(at: index, count:)` =
  `(l, rest) = split(root, at: index); (mid, r) = split(rest, at: count);
  recycle every node of mid onto freeList; root = join(l, r)` →
  **O(count + log N)** (the O(count) term is the mandatory slot recycling).

### Decision 2 — `join` shape and balance preservation

`join(L, R)` (all `L` keys < all `R` keys) is size-aware: it descends the spine of
the **larger** tree until the two sides are size-comparable, grafts there, fixes
aggregates with `pull`, and restores local balance with the **existing `maintain`
primitive** on the way back up — the standard balanced-tree join shape, giving
O(|height(L) − height(R)|) = O(log N). Concretely: if `L` is much larger than `R`,
recurse `L.right = join(L.right, R)` and `maintain` (right grew); symmetric when
`R` dominates; when comparable, detach one tree's boundary node (e.g. the min of
`R`) as the junction root and attach both sides. `split` is its recursive dual:
descend by position, and recombine the off-path subtrees with `join` as the
recursion unwinds.

Balance after split/join is **proven, not assumed**: the tree-height-logarithmic
test (Component Design test 6) fails immediately if `maintain` does not restore an
O(log N) height after bulk churn.

**Risk hedge.** SBT's amortized analysis is tuned for single-element steps, so
`maintain` after a join (which grafts a whole subtree) is the primary correctness
risk. If TDD shows `maintain` is insufficient to keep the height logarithmic, the
documented fallback — chosen only if a test forces it — is to rebuild the affected
spine subtree balanced at the graft point, still O(k + log N) amortized and with no
public-API change. The decision between these is driven by test 6, not guessed up
front.

### Decision 3 — API, atomicity, and empty-batch semantics

```swift
@discardableResult
public mutating func insertLines(at index: Int, heights: [Double]) -> Int
@discardableResult
public mutating func removeLines(at index: Int, count: Int) -> Int
```

- Return value = node-visit count, recorded in `lastMutationNodeVisits`, mirroring
  the single-line ops and feeding the visit-characteristic test and the benchmark
  checksum.
- **Atomic validation:** all preconditions are checked **before** any mutation, so
  a bad batch leaves the tree unchanged. `insertLines` requires `0 ≤ index ≤
  lineCount` and every height finite & positive; `removeLines` requires `count ≥
  0`, `index ≥ 0`, and `index + count ≤ lineCount`. Enforced with
  `precondition(_:)` and **static** string messages (fire in release, Embedded-safe;
  consistent with the existing provider style). No throwing / `Result` API.
- **Empty batch is a no-op:** `heights == []` or `count == 0` mutates nothing,
  leaves `lineCount` and all offsets unchanged, sets `lastMutationNodeVisits = 0`,
  and returns 0.

### Decision 4 — Visit accounting includes the O(k) build

`lastMutationNodeVisits` for a bulk op counts **every** node touched across
`split` + `buildBalanced` + `join` + recycle, landing at ~`k + log N`. This makes
the win directly assertable (Component Design test 7): for fixed `k`, doubling `N`
adds only ~`log N` visits (sublinear in N); for fixed `N`, visits grow ~linearly in
`k` (not `k·log N`). The `buildBalanced` touches are honest work, not scaffolding —
counting them keeps the metric faithful to actual node activity.

### Decision 5 — Provider scope and value semantics unchanged

Only `BalancedTreeLineMetrics` gains bulk ops; it is the sole structural-mutation
provider. It remains a `struct` over a `[Node]` arena with copy-on-write value
semantics, so a snapshot copied before mutation stays stable for one layout
operation (the `LineMetricsSource` stability precondition). The PrefixSum oracle's
"bulk" behavior in tests is `Array.insert(contentsOf:at:)` / `removeSubrange` —
no new oracle code. This slice **adds** methods and tests to existing files and
**adds** one benchmark file; `Package.swift` is unchanged.

## Component Design

### Target layout

```
Sources/
  TextEngineReferenceProviders/
      BalancedTreeLineMetrics.swift          (edit: add split, join,
                                              insertLines, removeLines)
  ViewportBenchmarks/
      BulkStructuralMutationBenchmark.swift   (NEW)
      BenchmarkOptions.swift                  (edit: add mode + parse + usage)
      BenchmarkProgram.swift                  (edit: dispatch new mode)
Tests/
  TextEngineReferenceProvidersTests/
      BalancedTreeLineMetricsTests.swift      (edit: add bulk tests)
```

### `BalancedTreeLineMetrics` additions

```swift
@discardableResult
public mutating func insertLines(at index: Int, heights: [Double]) -> Int  // O(k + log N)
@discardableResult
public mutating func removeLines(at index: Int, count: Int) -> Int         // O(count + log N)

// internal primitives (not public API):
private mutating func split(_ t: Int, at index: Int) -> (left: Int, right: Int)
private mutating func join(_ left: Int, _ right: Int) -> Int
private mutating func recycleSubtree(_ t: Int)   // push every node slot onto freeList
```

`split` / `join` / `recycleSubtree` are `private`; the public surface gains only
the two batch methods. `lastMutationNodeVisits` is the existing
`public private(set) var`.

### Tests (`TextEngineReferenceProvidersTests`, TDD failing-first)

Reuse the existing `assertMatchesOracle` harness (compare against a freshly built
`PrefixSumLineMetrics`) and the integer height set `{14,16,20,32}` so partial sums
are bit-exact.

1. **Bulk insert correctness** — `insertLines(at:heights:)` matches
   `array.insert(contentsOf:at:)` for head / tail / interior positions and
   `k = 1`, small (e.g. 8), and large (e.g. 5,000) batches.
2. **Bulk remove correctness** — `removeLines(at:count:)` matches
   `array.removeSubrange(index..<index+count)` for head / tail / interior spans,
   including `count == lineCount` (remove all → empty).
3. **Bulk equals compose** — `insertLines` / `removeLines` produce the same
   `lineCount` and every `offset(ofLine:)` as looping the single-line ops on an
   independent tree (proves the optimized path equals the proven naive path).
4. **Empty-batch no-op** — `insertLines(at:heights: [])` and
   `removeLines(at:count: 0)` leave `lineCount`, all offsets, and tree shape
   unchanged and return 0 visits; plus insert-into-empty and remove-to-empty edges.
5. **Strictly-increasing invariant** — `offset(i) < offset(i+1)` for all `i` after
   bulk ops.
6. **Tree-height invariant (the key balance gate)** — after a deterministic churn
   of bulk inserts and removes, `treeHeight() ≤ C·log₂(lineCount)`, proving
   split/join preserve balance. Read via the existing `internal func treeHeight()`
   through `@testable import`.
7. **Visit characteristic** — `lastMutationNodeVisits` for a fixed-`k` bulk op on
   `N = 1k / 100k / 1M` grows only ~additively with `log N` (sublinear in N), and
   for fixed `N` grows ~linearly with `k` and stays well under the `k·(⌊log₂N⌋+1)`
   a compose loop would cost.
8. **Mixed sequence** — extend the existing mixed-mutation equivalence oracle to
   interleave bulk `insertLines` / `removeLines` with single-line ops, comparing
   to the array after each step.
9. **Re-layout composition** — after a bulk edit, `ViewportVirtualizer.compute` +
   `geometry(...)` against the tree yield a range and `LineGeometry` stream
   identical to a fresh `PrefixSumLineMetrics` over the updated heights, and a
   counting wrapper confirms the core still issues O(log N) offset queries.

### Benchmark mode (`ViewportBenchmarks`)

- New `--bulk-structural-mutation` mode (output name `bulk_structural_mutation`),
  modeled on `StructuralMutationBenchmark`, over the existing 1k / 100k / 1M
  scenarios with a fixed representative batch size `K` (e.g. 64 lines,
  paste/selection-sized). Fully deterministic:
  - One `BalancedTreeLineMetrics` is built once per scenario from the deterministic
    `{14,16,20,32}` heights and **mutated in place**; the PrefixSum oracle never
    appears in the hot path.
  - Each measured operation pins `lineCount` constant by pairing a
    `removeLines(at: idx, count: K)` with an `insertLines(at: idx2, heights:)` of
    `K` heights at deterministic positions, then runs `compute` and a full geometry
    traversal. A running checksum consumes `lastMutationNodeVisits`, the range, and
    the geometry to defeat dead-code elimination.
  - Reports p95/p99 with a **local** `--gate`; budgets set from observed local
    numbers plus headroom (macOS-calibrated, like the other gates).
- `BenchmarkOptions`: add `.bulkStructuralMutation` to `BenchmarkMode`; `--gate` is
  **valid** with it; one mode flag at a time; rejected in combination with another
  mode. Update `--help`/usage. `BenchmarkProgram` dispatches the mode.
- Update the AGENTS.md command list and benchmark-flags note (the only durable-doc
  edit; spec/plan/verification/review live under `docs/superpowers/`).

### CI

**No `.github/workflows/swift-ci.yml` change this slice** (see Non-Goals). The gate
is exercised locally via `swift run -c release ViewportBenchmarks --
--bulk-structural-mutation --gate`. A follow-on Slice 26 will add the hosted
observation/blocking gate with Linux-fit budgets, completing the established
functional → promotion cadence a fourth time.

## Verification

Recorded with actual commands and outputs, anchored on the post-merge push run:

- `swift test` — new bulk tests pass; total grows from the current 90-test
  baseline.
- `swift build -c release` — `Build complete!`.
- `swift build -c release --target TextEngineReferenceProviders` — `Build
  complete!` (the provider library builds in isolation).
- `swift run -c release ViewportBenchmarks -- --gate` — `gate=pass`.
- `swift run -c release ViewportBenchmarks -- --variable-height --gate` —
  `gate=pass`.
- `swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate` —
  `gate=pass`.
- `swift run -c release ViewportBenchmarks -- --structural-mutation --gate` —
  `gate=pass` (existing single-line gate unchanged).
- `swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate` —
  `gate=pass` (the new local gate).
- `swift run -c release ViewportBenchmarks -- --memory-shape` — `invariant=pass`.
- `rg -n "Foundation" Sources/TextEngineCore` — empty.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` — empty.
- `./.github/scripts/cross-target-compile.sh --self-test` — `self_test=pass`.
- `git diff --check` — empty; `git diff --name-only` touches only
  `Sources/TextEngineReferenceProviders`, `Sources/ViewportBenchmarks`,
  `Tests/TextEngineReferenceProvidersTests`, `AGENTS.md`, and `docs/**`.
- Hosted PR run + post-merge push run IDs, both `success` (the existing three
  required jobs; no new job).

## Risks And Gaps

- **Join-induced balance (primary risk).** Grafting a whole subtree during `join`
  is outside SBT's single-step amortized model. Mitigated by the tree-height
  invariant (test 6) after bulk churn and the equivalence oracle (tests 1–3, 8)
  after every op; the Decision 2 spine-rebuild fallback is the documented escape
  hatch if a test forces it.
- **Aggregate maintenance through split/join.** Every `split`/`join`/rotation must
  carry `subtreeCount` / `subtreeHeightSum` correctly; a single mis-maintained
  aggregate fails the oracle immediately.
- **Provider is host-compiled, not Embedded-proven this slice.** Like the rest of
  `BalancedTreeLineMetrics`, the new code is Foundation-free and Embedded-style
  (arrays + `Int`/`Double`, no classes/ARC). The cross-target helper already
  compiles `TextEngineReferenceProviders` for iOS (blocking) and WASM
  (observational), so the additions ride that coverage once merged; this slice adds
  no dedicated Embedded step.
- **Local gate only.** Budgets are macOS-calibrated and exercised locally; hosted
  observation and blocking promotion are deferred to Slice 26. No CI regression
  protection for bulk mutation until that slice lands.
- **Visit count is a bound, not an exact formula.** Acceptable: the tree-height
  invariant test provides the direct balance guarantee the bound depends on.
