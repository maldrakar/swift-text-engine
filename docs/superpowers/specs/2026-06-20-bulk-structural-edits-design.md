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
- Implement them via internal `split(at:)`, `join(_:_:)`, and `detachMin(_:)`
  primitives plus an allocation-aware `buildBalancedRun` (built on `allocateNode`,
  not `init`'s `freeList`-bypassing `buildBalanced`), achieving **O(k + log N)**
  while preserving the size-balance invariant (logarithmic height) for subsequent
  operations.
- Keep arena growth bounded under churn: `removeLines` recycles the `count` removed
  slots onto `freeList`, and `insertLines` allocates its `k` nodes through
  `allocateNode` (consuming `freeList` before appending), so a remove-K-then-insert-K
  cycle reuses slots instead of growing the arena. Prove this with `@testable`
  diagnostics (`arenaNodeCount` / `freeSlotCount`) and a test asserting the arena
  does not grow across repeated equal-size remove/insert churn.
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

- `buildBalancedRun(heights)` — a perfectly balanced subtree from `k` heights in
  **O(k)**, no rotations. **It allocates every node through `allocateNode`** so it
  **consumes recycled `freeList` slots first** and only appends when the free list
  is empty. (The existing `buildBalanced` used by `init` does a direct
  `nodes.append` and bypasses `freeList`; reusing it for bulk insert would leak the
  slots `removeLines` recycled and let the arena grow unbounded under
  remove-then-insert churn. The bulk path therefore uses this allocation-aware
  builder, not `init`'s `buildBalanced`.) Its `k` allocations are counted in
  `lastMutationNodeVisits`.
- `split(_ root, at index) -> (left, right)` — partition the tree at in-order
  position `index` so `left` holds lines `[0, index)` and `right` holds
  `[index, lineCount)`. **O(log N)** (see Decision 2).
- `join(_ left, _ right) -> root` — concatenate two trees where every key in
  `left` precedes every key in `right`, restoring balance. **O(|h(left) −
  h(right)|) = O(log N)** (see Decision 2).

Then:

- `insertLines(at: index, heights:)` =
  `mid = buildBalancedRun(heights); (l, r) = split(root, at: index);
  root = join(join(l, mid), r)` → **O(k + log N)**.
- `removeLines(at: index, count:)` =
  `(l, rest) = split(root, at: index); (mid, r) = split(rest, at: count);
  recycleSubtree(mid); root = join(l, r)` → **O(count + log N)** (the O(count)
  term is the mandatory slot recycling, which pushes every removed node back onto
  `freeList` so the next `insertLines` reuses those slots).

### Decision 2 — `split`/`join` shape, strict O(log N), and balance preservation

This is the load-bearing decision and follows the join-based ("Just Join")
balanced-tree framework, where `join` is the one balancing primitive and `split`
is derived from it.

**`join(L, R)`** (all `L` keys < all `R` keys) is **size-aware**: it descends the
spine of the **larger** tree only until the two sides are size-comparable, grafts
there, fixes aggregates with `pull`, and restores local balance with the existing
`maintain` primitive on the way back up. Its cost is proportional to the height
difference, **O(|h(L) − h(R)|)**, not O(log N) per call. Concretely: if `L` is much
larger, recurse `L.right = join(L.right, R)` then `pull` + `maintain` (right grew);
symmetric when `R` dominates; when the two sides are size-comparable, use
`detachMin` (below) to pull `R`'s in-order-first node out as the junction root with
`left = L` and `right = R-without-min`, then `pull` + `maintain`.

**`detachMin(_ t) -> (root, node)`** is a **non-recycling** primitive that removes
and returns the leftmost node *index* of `t` (rebalancing `t`), distinct from the
deletion-path `removeMin`, which recycles the slot to `freeList` and returns only
the height. `join` reuses the detached node as the junction, so no node is freed or
allocated during a join.

**`split(_ t, at index) -> (left, right)`** is the recursive dual: descend by
position with a single pass, and recombine the off-path subtrees using `join` as
the recursion unwinds. Because each `join` on the unwind costs only
O(|height difference|) and those differences **telescope** along one root-to-leaf
path, the whole split is **O(log N)** total — *not* O(log² N). This telescoping is
the explicit guarantee the framework provides and is the answer to the "join per
unwind level might be O(log² N)" concern: it would be, with a per-level O(log N)
join, but a height-difference-proportional join sums to O(log N) over the path.

**Resulting bulk cost and its enforcement.** `insertLines`/`removeLines` are
therefore `O(k) build/recycle + O(log N) split + O(log N) joins = O(k + log N)`.
This is not left as prose: the visit-characteristic test (Component Design test 7)
asserts a **strict bound `lastMutationNodeVisits ≤ k + C·(⌊log₂N⌋ + 1)`** for a
small constant `C` calibrated during TDD, which **fails** if the implementation
regresses to O(k·log N) (a naive compose) or O(k + log² N) (a non-telescoping
split). The bound — not the prose — is the contract.

**Balance** after split/join is **proven, not assumed**: the tree-height test
(test 6) fails if `maintain` does not restore O(log N) height after bulk churn.

**Risk hedge.** SBT's amortized analysis is tuned for single-element steps, so
`maintain` after a join (which grafts a whole subtree) is the primary correctness
risk. If TDD shows `maintain` is insufficient to keep height logarithmic, the
documented fallback — chosen only if test 6 forces it — is to rebuild the affected
spine subtree balanced at the graft point, still O(k + log N) amortized and with no
public-API change. The choice is driven by the test, not guessed up front.

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
  lineCount` and every height finite & positive; `removeLines` requires
  `index ≥ 0 && index ≤ lineCount && count ≥ 0 && count ≤ lineCount − index`
  (written as `count ≤ lineCount − index`, **not** `index + count ≤ lineCount`, so
  an adversarial near-`Int.max` input cannot trap on integer-overflow before the
  intended precondition message fires). Enforced with
  `precondition(_:)` and **static** string messages (fire in release, Embedded-safe;
  consistent with the existing provider style). No throwing / `Result` API.
- **Empty batch is a no-op:** `heights == []` or `count == 0` mutates nothing,
  leaves `lineCount` and all offsets unchanged, sets `lastMutationNodeVisits = 0`,
  and returns 0.

### Decision 4 — Visit accounting includes the O(k) build, gated by a strict bound

`lastMutationNodeVisits` for a bulk op counts **every** node touched across
`buildBalancedRun` (its `k` allocations) + `split` + `join` + `detachMin` +
recycle, landing at `k + O(log N)`. Counting the build allocations keeps the metric
faithful to actual node activity. The win is enforced, not merely described:
Component Design test 7 asserts the **strict bound
`lastMutationNodeVisits ≤ k + C·(⌊log₂N⌋ + 1)`** (small constant `C` calibrated in
TDD) on `N = 1k / 100k / 1M`. That bound fails for an O(k·log N) compose or an
O(k + log² N) non-telescoping split, so it is the contract that the Decision 2
complexity is actually achieved — not just a "sublinear" smell test.

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
private mutating func buildBalancedRun(_ heights: [Double]) -> Int  // O(k), via allocateNode (freeList-first)
private mutating func split(_ t: Int, at index: Int) -> (left: Int, right: Int)
private mutating func join(_ left: Int, _ right: Int) -> Int
private mutating func detachMin(_ t: Int) -> (root: Int, node: Int)  // non-recycling; junction node for join
private mutating func recycleSubtree(_ t: Int)   // push every node slot onto freeList

// test-only white-box diagnostics, reached via @testable import (NOT public API):
internal var arenaNodeCount: Int { nodes.count }   // total arena slots ever materialized
internal var freeSlotCount: Int { freeList.count }  // recycled slots available for reuse
```

`buildBalancedRun` / `split` / `join` / `detachMin` / `recycleSubtree` are
`private`; the public surface gains only the two batch methods.
`lastMutationNodeVisits` is the existing `public private(set) var`. The two
`internal` diagnostics expose only slot bookkeeping (never the tree shape) and are
used solely by the arena-growth test.

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
7. **Visit characteristic (strict bound)** — for a fixed batch `k`,
   `lastMutationNodeVisits ≤ k + C·(⌊log₂N⌋ + 1)` on `N = 1k / 100k / 1M` for a
   small constant `C`; and the count stays **strictly below** the
   `k·(⌊log₂N⌋ + 1)` a compose loop would cost (asserting the O(k + log N) win,
   and catching an accidental O(k·log N) or O(k + log² N) regression).
8. **Arena-growth bound** — over repeated equal-size `removeLines(K)` /
   `insertLines(K)` churn, `arenaNodeCount` does not grow (slots are recycled and
   reused); `freeSlotCount` returns to its prior level after each remove/insert
   pair. Confirms the allocation-aware builder consumes `freeList` and the recycle
   path repopulates it.
9. **Mixed sequence** — extend the existing mixed-mutation equivalence oracle to
   interleave bulk `insertLines` / `removeLines` with single-line ops, comparing
   to the array after each step.
10. **Re-layout composition** — after a bulk edit, `ViewportVirtualizer.compute` +
    `geometry(...)` against the tree yield a range and `LineGeometry` stream
    identical to a fresh `PrefixSumLineMetrics` over the updated heights, and a
    counting wrapper confirms the core still issues O(log N) offset queries.

### Benchmark mode (`ViewportBenchmarks`)

- New `--bulk-structural-mutation` mode (output name `bulk_structural_mutation`),
  modeled on `StructuralMutationBenchmark`, over the existing 1k / 100k / 1M
  document sizes. Each size runs **two batch profiles**, because a single small `K`
  would not exercise the large-paste case the Problem motivates:
  - **Small batch** `K = 64` (typical paste/selection): the common interactive case.
  - **Large batch** `K ≈ 4,096` (or `lineCount` when smaller — e.g. the 1k doc):
    the large-paste / range-delete case where O(k + log N) diverges sharply from a
    compose loop's O(k·log N). Because each op is far heavier, this profile uses a
    **smaller `operationsPerSample`** so wall-clock per sample stays comparable.
    Its budget must be tight enough that a regression to compose-level cost
    (≈ `K`× the single-op gate) fails the gate — this is what gives the large-paste
    claim teeth.
  Fully deterministic:
  - One `BalancedTreeLineMetrics` is built once per (size, profile) from the
    deterministic `{14,16,20,32}` heights and **mutated in place**; the PrefixSum
    oracle never appears in the hot path.
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
  invariant (test 6) after bulk churn and the equivalence oracle (tests 1–3, 9)
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
