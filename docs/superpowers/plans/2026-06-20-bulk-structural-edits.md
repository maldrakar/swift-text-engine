# Bulk/Range Structural Edits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add atomic, O(k + log N) bulk `insertLines(at:heights:)` / `removeLines(at:count:)` to `BalancedTreeLineMetrics`, plus a local `--bulk-structural-mutation` benchmark gate.

**Architecture:** Implement `split` / `join` / `detachMin` primitives over the existing size-balanced order-statistics tree (the join-based "Just Join" framework) plus an allocation-aware `buildBalancedRun`. `insertLines` = build the run balanced (O(k), reusing `freeList`) + `split` + two `join`s; `removeLines` = two `split`s + recycle the middle subtree's slots + `join`. The stateless `TextEngineCore` is untouched.

**Tech Stack:** Swift 6.0 (SwiftPM), XCTest, `swift-tools-version: 6.0`. Pure value types over a flat `[Node]` arena — no Foundation, no classes/ARC.

## Global Constraints

- **No Foundation in `Sources/TextEngineCore`** — not touched this slice; the scan `rg -n "Foundation" Sources/TextEngineCore` must stay empty. Also keep `Sources/TextEngineReferenceProviders` Foundation-free (`rg -n "Foundation" Sources/TextEngineReferenceProviders` empty).
- **Swift Embedded compatible** — arrays + `Int`/`Double` only; no classes, ARC, or doubtful APIs in the provider.
- **Zero-dependency** — no third-party packages.
- **Compiles for iOS and WASM with no source changes** — the provider already rides `cross-target-compile.sh`; do not add platform conditionals.
- **Core-owned memory must not grow linearly with document size** — the core is unchanged; provider-owned O(N) memory is allowed, but arena slots MUST be recycled (no unbounded `nodes` growth under edit churn).
- **No `.github/workflows/swift-ci.yml` change** — the new benchmark is local-gate only this slice; CI promotion is a later slice.
- **No change to `TextEngineCore`, `Tests/TextEngineCoreTests`, `Package.swift`, `FenwickLineMetrics`, `PrefixSumLineMetrics`, or the existing single-line tree ops.**
- **Preconditions** use `precondition(_:)` with **static** string messages (fire in release; Embedded-safe). No throwing / `Result`.
- **TDD**: failing test first, minimal implementation, one logical step per commit. Conventional-commit prefixes (`feat:`, `test:`, `ci:`, `docs:`).
- Equivalence tests use the integer height set `{14,16,20,32}` so partial sums are bit-exact regardless of summation order.

**Reference (read before starting):**
- Spec: `docs/superpowers/specs/2026-06-20-bulk-structural-edits-design.md`
- Provider: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift` (existing `Node`, `allocateNode`, `pull`, `maintain`, `nodeCount`, `nodeSum`, `leftChild`, `rightChild`, `buildBalanced`, `removeMin`, `treeHeight`).
- Tests: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift` (existing helpers reused by new tests in the **same class**: `sampleHeights`, `assertMatchesOracle`, `floorLog2`, `ceilLog2`, `expectSuccess`, `QueryCounter`, `CountingMetrics`).
- Benchmark pattern: `Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift`.

---

### Task 1: `insertLines(at:heights:)` + split/join primitives + slot diagnostics

**Files:**
- Modify: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- Test: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes (existing, in `BalancedTreeLineMetrics`): `private mutating func allocateNode(height:) -> Int`, `private mutating func pull(_:)`, `private mutating func maintain(_ t: Int, leftGrew: Bool) -> Int`, `private func nodeCount(_:) -> Int`, `private func leftChild(_:) -> Int`, `private func rightChild(_:) -> Int`, `var lineCount: Int`, `func offset(ofLine:) -> Double`, `public private(set) var lastMutationNodeVisits: Int`, `var root: Int`, `var nodes: [Node]`, `var freeList: [Int]`.
- Produces (used by Task 2 and Task 3):
  - `@discardableResult public mutating func insertLines(at index: Int, heights: [Double]) -> Int`
  - `private mutating func split(_ t: Int, at index: Int) -> (left: Int, right: Int)`
  - `private mutating func join2(_ left: Int, _ right: Int) -> Int`
  - `internal var arenaNodeCount: Int` / `internal var freeSlotCount: Int`

- [ ] **Step 1: Write the failing tests for `insertLines`**

Add these methods to `final class BalancedTreeLineMetricsTests` in `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`:

```swift
    // MARK: - Bulk insert (Slice 25)

    func testInsertLinesMatchesArrayOracleAtHeadTailInterior() {
        let positions = [0, 500, 1_000] // head, interior, tail (== count)
        for index in positions {
            for k in [1, 8, 5_000] {
                var tree = BalancedTreeLineMetrics(heights: sampleHeights(1_000))
                var array = sampleHeights(1_000)
                let inserted = (0..<k).map { Double(10 + ($0 % 5) * 6) } // 10,16,22,28,34,...
                tree.insertLines(at: index, heights: inserted)
                array.insert(contentsOf: inserted, at: index)
                assertMatchesOracle(tree, array, "insert k=\(k) at \(index)")
            }
        }
    }

    func testInsertLinesEqualsLoopOfSingleInserts() {
        var bulk = BalancedTreeLineMetrics(heights: sampleHeights(300))
        var loop = BalancedTreeLineMetrics(heights: sampleHeights(300))
        let inserted = (0..<64).map { Double(12 + ($0 % 4) * 5) }
        let index = 137
        bulk.insertLines(at: index, heights: inserted)
        for (offset, height) in inserted.enumerated() {
            loop.insertLine(at: index + offset, height: height)
        }
        XCTAssertEqual(bulk.lineCount, loop.lineCount)
        for i in 0...bulk.lineCount {
            XCTAssertEqual(bulk.offset(ofLine: i), loop.offset(ofLine: i), "offset[\(i)]")
        }
    }

    func testInsertLinesEmptyIsNoOpAndInsertIntoEmptyDocument() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(50))
        let before = (0...tree.lineCount).map { tree.offset(ofLine: $0) }
        let visits = tree.insertLines(at: 25, heights: [])
        XCTAssertEqual(visits, 0)
        XCTAssertEqual(tree.lineCount, 50)
        XCTAssertEqual((0...tree.lineCount).map { tree.offset(ofLine: $0) }, before)

        var empty = BalancedTreeLineMetrics(heights: [])
        empty.insertLines(at: 0, heights: [21.0, 13.0, 17.0])
        assertMatchesOracle(empty, [21.0, 13.0, 17.0])
    }

    func testInsertLinesKeepsOffsetsStrictlyIncreasing() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(400))
        tree.insertLines(at: 0, heights: [40.0, 12.0])
        tree.insertLines(at: tree.lineCount, heights: [5.0, 64.0, 9.0])
        tree.insertLines(at: 200, heights: (0..<100).map { Double(8 + $0 % 7) })
        for i in 0..<tree.lineCount {
            XCTAssertLessThan(tree.offset(ofLine: i), tree.offset(ofLine: i + 1), "at \(i)")
        }
    }

    func testInsertLinesKeepsTreeBalanced() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(40))
        for k in 0..<200 {
            let count = tree.lineCount
            let index: Int
            switch k % 4 {
            case 0: index = 0
            case 1: index = count
            case 2: index = count / 2
            default: index = count / 3
            }
            let batch = (0..<(1 + k % 32)).map { Double(10 + ($0 % 5) * 6) }
            tree.insertLines(at: index, heights: batch)
        }
        XCTAssertLessThanOrEqual(
            tree.treeHeight(),
            3 * (floorLog2(tree.lineCount) + 1),
            "tree height not logarithmic: \(tree.treeHeight()) for \(tree.lineCount)"
        )
    }

    func testInsertLinesVisitCountIsKPlusLogarithmic() {
        let k = 64
        for n in [1_000, 100_000, 1_000_000] {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
            let batch = (0..<k).map { Double(10 + ($0 % 5) * 6) }
            let visits = tree.insertLines(at: n / 2, heights: batch)
            // O(k + log N): k build allocations plus a small constant times log N.
            XCTAssertLessThanOrEqual(visits, k + 12 * (floorLog2(n) + 1), "n=\(n)")
            // Strictly below an O(k log N) compose loop's cost.
            XCTAssertLessThan(visits, k * (floorLog2(n) + 1), "n=\(n) not below compose cost")
        }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter BalancedTreeLineMetricsTests/testInsertLines`
Expected: FAIL — compile error `value of type 'BalancedTreeLineMetrics' has no member 'insertLines'`.

- [ ] **Step 3: Add the diagnostics and private primitives**

In `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`, add the two diagnostics right after the `lastMutationNodeVisits` declaration:

```swift
    // Test-only white-box diagnostics (reached via @testable import; NOT public
    // API). Expose only arena slot bookkeeping, never the tree shape.
    internal var arenaNodeCount: Int { nodes.count }
    internal var freeSlotCount: Int { freeList.count }
```

Then add a new `// MARK: - Bulk structural mutation` section (place it after the single-line `removeLine` section, before `// MARK: - SBT balance`):

```swift
    // MARK: - Bulk structural mutation

    // Builds a perfectly balanced subtree from `heights` via allocateNode, so it
    // consumes recycled freeList slots before appending. O(k). Each allocation is
    // one node visit.
    private mutating func buildBalancedRun(_ heights: [Double]) -> Int {
        buildBalancedRun(heights, 0, heights.count)
    }

    private mutating func buildBalancedRun(_ heights: [Double], _ start: Int, _ end: Int) -> Int {
        if start >= end {
            return -1
        }
        let middle = start + (end - start) / 2
        lastMutationNodeVisits += 1
        let index = allocateNode(height: heights[middle])
        let left = buildBalancedRun(heights, start, middle)
        let right = buildBalancedRun(heights, middle + 1, end)
        nodes[index].left = left
        nodes[index].right = right
        pull(index)
        return index
    }

    // True iff a single node may root children L and R without violating the
    // size-balanced invariant (each child's count >= the opposite subtree's
    // nephews).
    private func canRoot(_ L: Int, _ R: Int) -> Bool {
        let cL = nodeCount(L)
        let cR = nodeCount(R)
        return cL >= nodeCount(leftChild(R)) && cL >= nodeCount(rightChild(R))
            && cR >= nodeCount(leftChild(L)) && cR >= nodeCount(rightChild(L))
    }

    // Joins L, single node m, and R with all keys(L) < m < all keys(R). m's
    // children are (re)assigned. Restores balance via the existing maintain.
    // O(|height(L) - height(R)|).
    private mutating func join3(_ L: Int, _ m: Int, _ R: Int) -> Int {
        lastMutationNodeVisits += 1
        if canRoot(L, R) {
            nodes[m].left = L
            nodes[m].right = R
            pull(m)
            return m
        }
        if nodeCount(L) > nodeCount(R) {
            nodes[L].right = join3(nodes[L].right, m, R)
            pull(L)
            return maintain(L, leftGrew: false) // right subtree grew
        } else {
            nodes[R].left = join3(L, m, nodes[R].left)
            pull(R)
            return maintain(R, leftGrew: true) // left subtree grew
        }
    }

    // Concatenates L and R (all keys(L) < all keys(R)), restoring balance, using
    // R's in-order-first node as the junction. O(log N). Does not allocate/free.
    private mutating func join2(_ L: Int, _ R: Int) -> Int {
        if L == -1 { return R }
        if R == -1 { return L }
        let detached = detachMin(R)
        return join3(L, detached.node, detached.root)
    }

    // Removes and returns the leftmost node index of subtree `t` (rebalancing t),
    // WITHOUT recycling the slot — distinct from removeMin, which frees the slot
    // and returns only the height. The returned node's children are cleared so the
    // caller can reuse it as a join junction.
    private mutating func detachMin(_ t: Int) -> (root: Int, node: Int) {
        lastMutationNodeVisits += 1
        if nodes[t].left == -1 {
            let detached = t
            let newRoot = nodes[t].right
            nodes[detached].left = -1
            nodes[detached].right = -1
            return (newRoot, detached)
        }
        let result = detachMin(nodes[t].left)
        nodes[t].left = result.root
        pull(t)
        let rebalanced = maintain(t, leftGrew: false) // left shrank -> right may be too big
        return (rebalanced, result.node)
    }

    // Splits subtree `t` at in-order position `index` into (left, right): left
    // holds the first `index` lines, right holds the rest. O(log N) total — the
    // per-unwind join3 costs telescope along one root-to-leaf path.
    private mutating func split(_ t: Int, at index: Int) -> (left: Int, right: Int) {
        lastMutationNodeVisits += 1
        if t == -1 {
            return (-1, -1)
        }
        let leftCount = nodeCount(nodes[t].left)
        if index <= leftCount {
            let (LL, LR) = split(nodes[t].left, at: index)
            let right = join3(LR, t, nodes[t].right) // t + its right subtree join the right portion
            return (LL, right)
        } else {
            let (RL, RR) = split(nodes[t].right, at: index - leftCount - 1)
            let left = join3(nodes[t].left, t, RL) // t.left + t join the left portion
            return (left, RR)
        }
    }
```

- [ ] **Step 4: Add the public `insertLines` method**

Add to the `// MARK: - Bulk structural mutation` section:

```swift
    // Inserts `heights.count` new lines so the first lands at in-order position
    // `index`. Validates all inputs before mutating (atomic). O(k + log N): build
    // the run balanced, split at index, join [left | run | right]. Returns node
    // visits.
    @discardableResult
    public mutating func insertLines(at index: Int, heights: [Double]) -> Int {
        precondition(
            index >= 0 && index <= lineCount,
            "BalancedTreeLineMetrics.insertLines index out of range"
        )
        for height in heights {
            precondition(
                height.isFinite && height > 0.0,
                "BalancedTreeLineMetrics.insertLines requires finite, positive heights"
            )
        }
        lastMutationNodeVisits = 0
        if heights.isEmpty {
            return 0
        }
        let middle = buildBalancedRun(heights)
        let (left, right) = split(root, at: index)
        root = join2(join2(left, middle), right)
        return lastMutationNodeVisits
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter BalancedTreeLineMetricsTests/testInsertLines`
Expected: PASS (all six `testInsertLines*` tests).

If `testInsertLinesKeepsTreeBalanced` or `testInsertLinesVisitCountIsKPlusLogarithmic` fails, the join is not restoring balance / not telescoping. See the spec's Decision 2 risk hedge (rebuild the affected spine subtree balanced) before changing the visit bound — the bound is the contract, not the variable to loosen. Surface this at the review checkpoint.

- [ ] **Step 6: Run the full provider test suite to confirm no regression**

Run: `swift test --filter BalancedTreeLineMetricsTests`
Expected: PASS — all existing single-line tests plus the new insert tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "feat: add O(k + log N) bulk insertLines to BalancedTreeLineMetrics"
```

---

### Task 2: `removeLines(at:count:)` + slot recycling

**Files:**
- Modify: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- Test: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes (from Task 1): `split`, `join2`, `buildBalancedRun`, `arenaNodeCount`, `freeSlotCount`, `insertLines`.
- Produces (used by Task 3): `@discardableResult public mutating func removeLines(at index: Int, count: Int) -> Int`.

- [ ] **Step 1: Write the failing tests for `removeLines`**

Add to `final class BalancedTreeLineMetricsTests`:

```swift
    // MARK: - Bulk remove (Slice 25)

    func testRemoveLinesMatchesArrayOracleAtHeadTailInterior() {
        // (index, count) spans: head, interior, tail.
        let spans = [(0, 1), (0, 250), (375, 250), (900, 100), (500, 1)]
        for (index, count) in spans {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(1_000))
            var array = sampleHeights(1_000)
            tree.removeLines(at: index, count: count)
            array.removeSubrange(index..<(index + count))
            assertMatchesOracle(tree, array, "remove \(count) at \(index)")
        }
    }

    func testRemoveLinesEntireDocumentLeavesEmpty() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(640))
        tree.removeLines(at: 0, count: 640)
        XCTAssertEqual(tree.lineCount, 0)
        XCTAssertEqual(tree.offset(ofLine: 0), 0.0)
        XCTAssertEqual(tree.treeHeight(), 0)
    }

    func testRemoveLinesEqualsLoopOfSingleRemoves() {
        var bulk = BalancedTreeLineMetrics(heights: sampleHeights(500))
        var loop = BalancedTreeLineMetrics(heights: sampleHeights(500))
        let index = 113
        let count = 80
        bulk.removeLines(at: index, count: count)
        for _ in 0..<count { loop.removeLine(at: index) }
        XCTAssertEqual(bulk.lineCount, loop.lineCount)
        for i in 0...bulk.lineCount {
            XCTAssertEqual(bulk.offset(ofLine: i), loop.offset(ofLine: i), "offset[\(i)]")
        }
    }

    func testRemoveLinesZeroCountIsNoOp() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(50))
        let before = (0...tree.lineCount).map { tree.offset(ofLine: $0) }
        let visits = tree.removeLines(at: 25, count: 0)
        XCTAssertEqual(visits, 0)
        XCTAssertEqual(tree.lineCount, 50)
        XCTAssertEqual((0...tree.lineCount).map { tree.offset(ofLine: $0) }, before)
    }

    func testRemoveLinesKeepsOffsetsStrictlyIncreasing() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(400))
        tree.removeLines(at: 0, count: 30)
        tree.removeLines(at: tree.lineCount - 20, count: 20)
        tree.removeLines(at: 100, count: 50)
        for i in 0..<tree.lineCount {
            XCTAssertLessThan(tree.offset(ofLine: i), tree.offset(ofLine: i + 1), "at \(i)")
        }
    }

    func testRemoveLinesVisitCountIsCountPlusLogarithmic() {
        let count = 64
        for n in [1_000, 100_000, 1_000_000] {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
            let visits = tree.removeLines(at: n / 2, count: count)
            XCTAssertLessThanOrEqual(visits, count + 12 * (floorLog2(n) + 1), "n=\(n)")
            XCTAssertLessThan(visits, count * (floorLog2(n) + 1), "n=\(n) not below compose cost")
        }
    }

    func testBulkChurnKeepsTreeBalanced() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(2_000))
        for k in 0..<300 {
            let count = tree.lineCount
            if k % 2 == 0 {
                let batch = (0..<(1 + k % 50)).map { Double(10 + ($0 % 5) * 6) }
                tree.insertLines(at: (k * 7) % (count + 1), heights: batch)
            } else {
                let span = min(1 + k % 50, tree.lineCount)
                let index = tree.lineCount == 0 ? 0 : (k * 13) % (tree.lineCount - span + 1)
                tree.removeLines(at: index, count: span)
            }
        }
        XCTAssertGreaterThan(tree.lineCount, 0)
        XCTAssertLessThanOrEqual(
            tree.treeHeight(),
            3 * (floorLog2(tree.lineCount) + 1),
            "tree height not logarithmic: \(tree.treeHeight()) for \(tree.lineCount)"
        )
    }

    func testBulkChurnReusesArenaSlots() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(1_000))
        let batch = (0..<128).map { Double(10 + ($0 % 5) * 6) }
        // First cycle establishes the high-water mark; later cycles must not grow.
        tree.removeLines(at: 400, count: 128)
        tree.insertLines(at: 400, heights: batch)
        let arenaAfterFirstCycle = tree.arenaNodeCount
        let freeAfterFirstCycle = tree.freeSlotCount
        for c in 0..<10 {
            tree.removeLines(at: 200 + c, count: 128)
            tree.insertLines(at: 200 + c, heights: batch)
            XCTAssertEqual(tree.arenaNodeCount, arenaAfterFirstCycle, "arena grew on cycle \(c)")
            XCTAssertEqual(tree.freeSlotCount, freeAfterFirstCycle, "free slots drifted on cycle \(c)")
        }
        XCTAssertEqual(tree.lineCount, 1_000)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter BalancedTreeLineMetricsTests/testRemoveLines`
Expected: FAIL — compile error `value of type 'BalancedTreeLineMetrics' has no member 'removeLines'`.

- [ ] **Step 3: Add `recycleSubtree` and `removeLines`**

In the `// MARK: - Bulk structural mutation` section of `BalancedTreeLineMetrics.swift`, add:

```swift
    // Pushes every node slot in subtree `t` onto freeList so a later insert reuses
    // them. Iterative (explicit stack) to avoid recursion depth on large ranges.
    // O(size of t).
    private mutating func recycleSubtree(_ t: Int) {
        if t == -1 {
            return
        }
        var stack = [t]
        while let node = stack.popLast() {
            lastMutationNodeVisits += 1
            let left = nodes[node].left
            let right = nodes[node].right
            freeList.append(node)
            if left != -1 { stack.append(left) }
            if right != -1 { stack.append(right) }
        }
    }

    // Removes the `count` lines starting at in-order position `index`. Validates
    // before mutating (atomic). O(count + log N): split out the range, recycle its
    // slots, join the remainder. Returns node visits. The bound is written as
    // `count <= lineCount - index` (not `index + count <= lineCount`) so an
    // adversarial near-Int.max input cannot trap on overflow before the
    // precondition message fires.
    @discardableResult
    public mutating func removeLines(at index: Int, count: Int) -> Int {
        precondition(
            index >= 0 && index <= lineCount && count >= 0 && count <= lineCount - index,
            "BalancedTreeLineMetrics.removeLines range out of bounds"
        )
        lastMutationNodeVisits = 0
        if count == 0 {
            return 0
        }
        let (left, rest) = split(root, at: index)
        let (middle, right) = split(rest, at: count)
        recycleSubtree(middle)
        root = join2(left, right)
        return lastMutationNodeVisits
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter BalancedTreeLineMetricsTests/testRemoveLines`
Expected: PASS (all `testRemoveLines*` tests).

Then the churn/arena tests:

Run: `swift test --filter BalancedTreeLineMetricsTests/testBulk`
Expected: PASS (`testBulkChurnKeepsTreeBalanced`, `testBulkChurnReusesArenaSlots`).

If `testBulkChurnReusesArenaSlots` fails because the arena grows, confirm `buildBalancedRun` allocates via `allocateNode` (not `nodes.append`) and that `recycleSubtree` runs before the `join2`. If `testBulkChurnKeepsTreeBalanced` fails, this is the join-balance risk — surface at the review checkpoint per the spec's Decision 2.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "feat: add O(k + log N) bulk removeLines with slot recycling"
```

---

### Task 3: Mixed-sequence and through-the-virtualizer integration tests

**Files:**
- Test: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes: `insertLines`, `removeLines`, `insertLine`, `removeLine`, `setHeight`, `ViewportVirtualizer.compute`, `ViewportVirtualizer.geometry`, `VariableViewportInput`, `PrefixSumLineMetrics`, `CountingMetrics`, `QueryCounter`, `expectSuccess`, `ceilLog2`.
- Produces: none (test-only).

- [ ] **Step 1: Write the failing integration tests**

Add to `final class BalancedTreeLineMetricsTests`:

```swift
    // MARK: - Bulk integration (Slice 25)

    func testMixedBulkAndSingleMutationEquivalenceOracle() {
        var rngState: UInt64 = 0x9E3779B97F4A7C15
        func nextRandom(_ bound: Int) -> Int {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            return Int((rngState >> 33) % UInt64(bound))
        }

        var tree = BalancedTreeLineMetrics(heights: sampleHeights(60))
        var array = sampleHeights(60)
        let heightChoices = [10.0, 16.0, 22.0, 28.0, 34.0]

        for step in 0..<1_500 {
            let count = array.count
            let op = count == 0 ? 0 : nextRandom(5)
            switch op {
            case 0: // bulk insert
                let index = nextRandom(count + 1)
                let k = 1 + nextRandom(40)
                let batch = (0..<k).map { heightChoices[nextRandom(heightChoices.count)] }
                tree.insertLines(at: index, heights: batch)
                array.insert(contentsOf: batch, at: index)
            case 1: // bulk remove
                let span = 1 + nextRandom(min(40, count))
                let index = nextRandom(count - span + 1)
                tree.removeLines(at: index, count: span)
                array.removeSubrange(index..<(index + span))
            case 2: // single insert
                let index = nextRandom(count + 1)
                let height = heightChoices[nextRandom(heightChoices.count)]
                tree.insertLine(at: index, height: height)
                array.insert(height, at: index)
            case 3: // single remove
                let index = nextRandom(count)
                tree.removeLine(at: index)
                array.remove(at: index)
            default: // setHeight
                let index = nextRandom(count)
                let height = heightChoices[nextRandom(heightChoices.count)]
                tree.setHeight(ofLine: index, to: height)
                array[index] = height
            }
            assertMatchesOracle(tree, array, "after step \(step) op \(op)")
        }
    }

    func testReLayoutAfterBulkEditMatchesFreshOracle() {
        var array = sampleHeights(10_000)
        var tree = BalancedTreeLineMetrics(heights: array)
        tree.removeLines(at: 4_000, count: 500)
        array.removeSubrange(4_000..<4_500)
        let inserted = (0..<500).map { Double(12 + ($0 % 5) * 6) }
        tree.insertLines(at: 2_000, heights: inserted)
        array.insert(contentsOf: inserted, at: 2_000)
        let oracle = PrefixSumLineMetrics(heights: array)

        let input = VariableViewportInput(
            scrollOffsetY: oracle.offset(ofLine: 5_000) - 100.0,
            viewportHeight: 80.0 * 16.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )
        let treeRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: tree))
        let oracleRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: oracle))
        XCTAssertEqual(treeRange, oracleRange)

        var treeCursor = ViewportVirtualizer.geometry(for: treeRange, metrics: tree)
        var oracleCursor = ViewportVirtualizer.geometry(for: oracleRange, metrics: oracle)
        var emitted = 0
        while true {
            let a = treeCursor.next()
            let b = oracleCursor.next()
            XCTAssertEqual(a, b, "geometry mismatch at \(emitted)")
            if a == nil && b == nil { break }
            emitted += 1
            if emitted >= 1_000 { XCTFail("cursor did not terminate"); return }
        }
        XCTAssertGreaterThan(emitted, 0)
    }

    func testReLayoutAfterBulkEditUsesLogarithmicCoreQueries() {
        let n = 1_000_000
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
        tree.removeLines(at: n / 3, count: 1_000)
        tree.insertLines(at: n / 4, heights: (0..<1_000).map { Double(20 + $0 % 9) })

        let counter = QueryCounter()
        let counting = CountingMetrics(base: tree, counter: counter)
        let input = VariableViewportInput(
            scrollOffsetY: tree.offset(ofLine: n / 2),
            viewportHeight: 80.0 * 16.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )
        _ = expectSuccess(ViewportVirtualizer.compute(input, metrics: counting))
        let expectedMax = 2 + (ceilLog2(n) + 1) * 2
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter BalancedTreeLineMetricsTests/testMixed`
Run: `swift test --filter BalancedTreeLineMetricsTests/testReLayoutAfterBulk`
Expected: PASS. (These exercise existing code from Tasks 1–2; they lock in bulk↔single interaction and core composition. If `testMixedBulkAndSingleMutationEquivalenceOracle` fails, the first failing step pinpoints the offending op.)

- [ ] **Step 3: Run the whole provider suite**

Run: `swift test --filter BalancedTreeLineMetricsTests`
Expected: PASS — every existing and new test.

- [ ] **Step 4: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "test: cover mixed bulk/single edits and bulk re-layout composition"
```

---

### Task 4: `--bulk-structural-mutation` benchmark mode with local gate

**Files:**
- Create: `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`

**Interfaces:**
- Consumes: `BalancedTreeLineMetrics.insertLines` / `.removeLines` / `.lastMutationNodeVisits`, `variableHeights(lineCount:)`, `deterministicScrollOffset(sample:maxOffset:)`, `percentile`, `nanoseconds`, `formatSummary`, `BenchmarkSummary`, `BenchmarkOperationResult`, `ViewportVirtualizer.compute` / `.geometry`, `VariableViewportInput`.
- Produces: `BenchmarkMode.bulkStructuralMutation`, `func runBulkStructuralMutationBenchmarks(enforceGate: Bool) -> Bool`.

- [ ] **Step 1: Add the mode to `BenchmarkMode` (compile-driven failing state)**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, add `case bulkStructuralMutation` after `case structuralMutation` in the `enum BenchmarkMode`, and add its `outputName`:

```swift
        case .bulkStructuralMutation:
            return "bulk_structural_mutation"
```

- [ ] **Step 2: Add parsing, usage, and gate-validity**

In `BenchmarkOptions.swift`, add to `usage` (in the `Usage:` line and the options list):

```
      --bulk-structural-mutation  Run bulk insert/delete-range+recompute benchmark (balanced-tree provider). Combine with --gate to enforce budgets.
```

Add the parse case after the `--structural-mutation` case:

```swift
            case "--bulk-structural-mutation":
                if mode != .pipeline {
                    return .failure("--bulk-structural-mutation cannot be combined with another mode")
                }
                mode = .bulkStructuralMutation
```

(`--gate` is already permitted for any mode except `rangeOnly` / `memoryShape` / `memoryObservation`, so `bulkStructuralMutation` is gate-valid with no change to the trailing guard.)

- [ ] **Step 3: Write the benchmark file**

Create `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift`:

```swift
import TextEngineCore
import TextEngineReferenceProviders

// Reuses variableHeights(lineCount:) and deterministicScrollOffset from
// VariableHeightBenchmark.swift / BenchmarkSupport.swift.
struct BulkStructuralMutationScenario {
    let name: String
    let lineCount: Int
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
    let batchSize: Int
    let operationsPerSample: Int
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

func bulkStructuralMutationScenarios() -> [BulkStructuralMutationScenario] {
    [
        // Small batch (K=64): typical paste/selection.
        BulkStructuralMutationScenario(
            name: "1k_lines_batch_64",
            lineCount: 1_000, viewportHeight: 20.0 * 16.0,
            overscanBefore: 0, overscanAfter: 0, batchSize: 64,
            operationsPerSample: 256, p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000
        ),
        BulkStructuralMutationScenario(
            name: "100k_lines_batch_64",
            lineCount: 100_000, viewportHeight: 80.0 * 16.0,
            overscanBefore: 5, overscanAfter: 5, batchSize: 64,
            operationsPerSample: 256, p95BudgetNanoseconds: 150_000, p99BudgetNanoseconds: 250_000
        ),
        BulkStructuralMutationScenario(
            name: "1m_lines_batch_64",
            lineCount: 1_000_000, viewportHeight: 200.0 * 16.0,
            overscanBefore: 50, overscanAfter: 50, batchSize: 64,
            operationsPerSample: 256, p95BudgetNanoseconds: 400_000, p99BudgetNanoseconds: 600_000
        ),
        // Large batch (K=4096): large paste / range delete — the case O(k + log N)
        // protects. Fewer ops per sample because each op is far heavier.
        BulkStructuralMutationScenario(
            name: "100k_lines_batch_4096",
            lineCount: 100_000, viewportHeight: 80.0 * 16.0,
            overscanBefore: 5, overscanAfter: 5, batchSize: 4_096,
            operationsPerSample: 16, p95BudgetNanoseconds: 1_500_000, p99BudgetNanoseconds: 2_500_000
        ),
        BulkStructuralMutationScenario(
            name: "1m_lines_batch_4096",
            lineCount: 1_000_000, viewportHeight: 200.0 * 16.0,
            overscanBefore: 50, overscanAfter: 50, batchSize: 4_096,
            operationsPerSample: 16, p95BudgetNanoseconds: 2_500_000, p99BudgetNanoseconds: 4_000_000
        )
    ]
}

@inline(never)
func runBulkStructuralMutationOperation(
    input: VariableViewportInput,
    metrics: BalancedTreeLineMetrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.compute(input, metrics: metrics) {
    case let .success(range):
        var checksum = 0
        checksum &+= range.visibleStart
        checksum &+= range.visibleEndExclusive
        checksum &+= range.bufferStart
        checksum &+= range.bufferEndExclusive
        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        while let geometry = cursor.next() {
            checksum &+= geometry.lineIndex
            checksum &+= Int(geometry.y)
            checksum &+= Int(geometry.height)
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runBulkStructuralMutationScenario(
    _ scenario: BulkStructuralMutationScenario,
    iterations: Int
) -> BenchmarkSummary {
    var metrics = BalancedTreeLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
    let initialTotal = metrics.offset(ofLine: metrics.lineCount)
    let maxOffset = initialTotal > scenario.viewportHeight ? initialTotal - scenario.viewportHeight : 0.0
    let lineCount = scenario.lineCount
    let batch = scenario.batchSize
    // A fixed batch of heights, rebuilt per op only as a value array (cheap); the
    // measured cost is the tree work, not array construction.
    let insertedHeights = (0..<batch).map { Double(14 + ($0 % 4) * 6) } // 14,20,26,32
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<scenario.operationsPerSample {
            let sample = iteration * scenario.operationsPerSample + operation
            // Pin lineCount: remove a batch then insert a batch, both within range.
            let removeIndex = (sample &* 2_654_435_761) % (lineCount - batch + 1)
            metrics.removeLines(at: removeIndex, count: batch)
            checksum &+= metrics.lastMutationNodeVisits
            let insertIndex = (sample &* 40_503) % (lineCount - batch + 1)
            metrics.insertLines(at: insertIndex, heights: insertedHeights)
            checksum &+= metrics.lastMutationNodeVisits

            let offset = deterministicScrollOffset(sample: sample, maxOffset: maxOffset)
            let input = VariableViewportInput(
                scrollOffsetY: offset,
                viewportHeight: scenario.viewportHeight,
                overscanLinesBefore: scenario.overscanBefore,
                overscanLinesAfter: scenario.overscanAfter
            )
            let result = runBulkStructuralMutationOperation(input: input, metrics: metrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(scenario.operationsPerSample))
    }

    samples.sort()
    return BenchmarkSummary(
        mode: .bulkStructuralMutation,
        providerName: "balanced_tree",
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: scenario.operationsPerSample,
        lineCount: scenario.lineCount,
        documentBytes: nil,
        lineBytes: nil,
        p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
        p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
        checksum: checksum,
        failureCount: failureCount,
        p95BudgetNanoseconds: scenario.p95BudgetNanoseconds,
        p99BudgetNanoseconds: scenario.p99BudgetNanoseconds
    )
}

@available(macOS 13.0, *)
func runBulkStructuralMutationBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 2_000
    var passed = true
    for scenario in bulkStructuralMutationScenarios() {
        let summary = runBulkStructuralMutationScenario(scenario, iterations: iterations)
        print(formatSummary(summary, includeGate: enforceGate))
        if enforceGate && !summary.passesGate {
            passed = false
        } else if !enforceGate && summary.failureCount != 0 {
            passed = false
        }
    }
    return passed
}
```

- [ ] **Step 4: Dispatch the mode**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, add to the `switch options.mode` in `runBenchmarks`, after the `.structuralMutation` case:

```swift
    case .bulkStructuralMutation:
        return runBulkStructuralMutationBenchmarks(enforceGate: options.enforceGate)
```

- [ ] **Step 5: Build and run the new gate**

Run: `swift build -c release`
Expected: `Build complete!`

Run: `swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate`
Expected: one summary line per scenario, each ending `gate=pass`, process exits 0.

If a scenario prints `gate=fail`, first confirm the measured p95/p99 vs the budget. **Calibrate budgets to observed-local + headroom** (macOS, like the other gates): raise an over-tight budget to ~1.5–2× the observed p95/p99 so it is stable but still tight enough that a regression to compose-level cost (≈ batchSize × the single-op `--structural-mutation` p95) would fail. Record the observed numbers for the verification doc.

- [ ] **Step 6: Confirm mutual exclusivity and gate-validity**

Run: `swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --structural-mutation`
Expected: `error=--structural-mutation cannot be combined with another mode` (exit 1).

Run: `swift run -c release ViewportBenchmarks -- --help`
Expected: usage text includes the `--bulk-structural-mutation` line.

- [ ] **Step 7: Commit**

```bash
git add Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift
git commit -m "feat: add --bulk-structural-mutation benchmark with local gate"
```

---

### Task 5: Document the new commands in `AGENTS.md`

**Files:**
- Modify: `AGENTS.md`

**Interfaces:** none.

- [ ] **Step 1: Add the local-gate command to the Commands block**

In `AGENTS.md`, in the ```bash Commands fenced block, add after the `--structural-mutation --gate` line:

```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate   # bulk insert/delete-range local gate
```

- [ ] **Step 2: Add the flag to the benchmark-flags note**

In `AGENTS.md`, in the "Benchmark flags:" paragraph, add `--bulk-structural-mutation` to the list of mode flags, and add it to the set for which `--gate` is **valid** (alongside `--structural-mutation`). Leave the `--gate`-rejected set (`--range-only`, `--memory-shape`, `--memory-observation`) unchanged.

- [ ] **Step 3: Verify the docs-only nature of this change**

Run: `git diff --name-only`
Expected: only `AGENTS.md`.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document --bulk-structural-mutation gate command"
```

---

## Verification (full sweep — run after Task 5, record outputs in the verification doc)

Run each and capture output for `docs/superpowers/verification/2026-06-20-bulk-structural-edits.md`:

```bash
swift test                                                                  # all pass; total > 90 baseline
swift build -c release                                                      # Build complete!
swift build -c release --target TextEngineReferenceProviders               # Build complete!
swift run -c release ViewportBenchmarks -- --gate                          # gate=pass
swift run -c release ViewportBenchmarks -- --variable-height --gate        # gate=pass
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate  # gate=pass
swift run -c release ViewportBenchmarks -- --structural-mutation --gate    # gate=pass (unchanged)
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate  # gate=pass (new)
swift run -c release ViewportBenchmarks -- --memory-shape                  # invariant=pass
rg -n "Foundation" Sources/TextEngineCore                                  # empty (exit 1)
rg -n "Foundation" Sources/TextEngineReferenceProviders                    # empty (exit 1)
./.github/scripts/cross-target-compile.sh --self-test                      # self_test=pass
git diff --check cb12fd9..HEAD                                             # empty
git diff --name-only cb12fd9..HEAD                                         # only Sources/TextEngineReferenceProviders, Sources/ViewportBenchmarks, Tests/TextEngineReferenceProvidersTests, AGENTS.md, docs/**
```

Then open a PR (branch `slice-25-bulk-structural-edits`), confirm the three required jobs (`Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`) are `success`, and anchor the proof on the post-merge push run.

## Self-Review Notes

- **Spec coverage:** Decision 1/2 (split/join/detachMin/buildBalancedRun, O(k+logN)) → Task 1+2; Decision 3 (atomic validation, empty no-op, overflow-safe precondition) → Task 1 (insert) + Task 2 (remove); Decision 4 (visit accounting + strict bound) → Task 1 test 6 + Task 2 visit test; Decision 5 (provider scope, value semantics) → no PrefixSum/Fenwick change; tests 1–10 → Tasks 1–3; benchmark (small+large K, local gate) → Task 4; AGENTS.md → Task 5; verification → final sweep. No gaps.
- **Type consistency:** `insertLines(at:heights:)`, `removeLines(at:count:)`, `split(_:at:)`, `join2`, `join3`, `detachMin`, `buildBalancedRun`, `recycleSubtree`, `canRoot`, `arenaNodeCount`, `freeSlotCount`, `BenchmarkMode.bulkStructuralMutation`, `runBulkStructuralMutationBenchmarks` used consistently across tasks.
- **Risk:** join-induced balance is the one open risk (Task 1 Step 5 / Task 2 Step 4 callouts); fallback is the spec's Decision 2 spine rebuild, chosen only if `testInsertLinesKeepsTreeBalanced` / `testBulkChurnKeepsTreeBalanced` force it.
