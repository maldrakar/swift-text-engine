# Dynamic Line Insert/Delete Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `BalancedTreeLineMetrics`, a mutable reference `LineMetricsSource` whose mid-document `insertLine` / `removeLine` / `setHeight` and `offset(ofLine:)` are each O(log N), proving cheap incremental re-layout under structural editing while `TextEngineCore` stays completely unchanged.

**Architecture:** A size-balanced order-statistics binary search tree stored in a flat `[Node]` arena (integer child indices, `-1` sentinel, no classes/pointers/ARC). Each node carries `subtreeCount` and `subtreeHeightSum` aggregates so an order-statistics descent answers `offset(ofLine:)` in O(log N); a Size-Balanced-Tree (SBT) `maintain` keeps height O(log N) after each structural edit. The provider is a `struct` with copy-on-write value semantics, lives only in `Sources/TextEngineReferenceProviders`, and is exercised by XCTest against the `PrefixSumLineMetrics` oracle plus a new `--structural-mutation` benchmark with a local gate.

**Tech Stack:** Swift 6 (`swift-tools-version: 6.0`), SwiftPM, XCTest, `TextEngineCore` (`ViewportVirtualizer.compute(_:metrics:)` / `geometry(for:metrics:)`), the `ViewportBenchmarks` executable.

## Global Constraints

Every task's requirements implicitly include these. Copied from the spec and `AGENTS.md`:

- **No `TextEngineCore` source or public-API change.** The core stays stateless and generic over `LineMetricsSource`.
- **No `Package.swift` change.** The `TextEngineReferenceProviders` library and `TextEngineReferenceProvidersTests` target already exist (Slice 17); this slice only *adds* files.
- **No `.github/workflows/swift-ci.yml` change.** The new benchmark is gated **locally only** this slice.
- **Foundation-free.** `rg -n "Foundation" Sources/TextEngineCore` and `rg -n "Foundation" Sources/TextEngineReferenceProviders` must both stay empty. Do not `import Foundation` in the new provider or benchmark files. (XCTest files may use what XCTest brings in; the new tests need no `Foundation` import.)
- **Embedded-Swift compatible style.** Arrays + `Int`/`Double` only, no classes/ARC in the provider. Preconditions use `precondition(_:)` with **static** string messages (fire in release too). No throwing / `Result` mutation API.
- **Zero-dependency.** No third-party packages.
- **Integer-valued heights in tests** (e.g. `{14,16,20,32}`), totals `< 2^53`, so tree partial sums are bit-exactly equal to the left-to-right prefix-sum oracle regardless of summation order. No fractional-height equivalence.
- **Strictly-increasing offsets contract.** Every line height is finite and `> 0`; no zero-height / collapsed lines. `offset(ofLine:)` honors the `LineMetricsSource` contract (domain `0...lineCount`, `offset(0) == 0`) and does **not** re-validate the core's preconditions.
- **Conventional commits**, one logical step per commit (`feat:`, `test:`, `refactor:`, `docs:`). End commit messages with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.
- Work happens on branch `slice-23-dynamic-line-insert-delete` (already checked out). Diff must touch only `Sources/TextEngineReferenceProviders/**`, `Sources/ViewportBenchmarks/**`, `Tests/TextEngineReferenceProvidersTests/**`, `AGENTS.md`, and `docs/**`.

---

## File Structure

- `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift` **(NEW)** — the provider: `Node` arena, `init(heights:)`, `offset`, `setHeight`, `insertLine`, `removeLine`, SBT internals, and the test-only `treeHeight()`. One file, one responsibility (the data structure).
- `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift` **(NEW)** — all six spec tests + shared helpers. Uses `@testable import TextEngineReferenceProviders` to reach `treeHeight()`.
- `Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift` **(NEW)** — the `--structural-mutation` benchmark, modeled on `VariableHeightMutationBenchmark.swift`.
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift` **(EDIT)** — add `.structuralMutation` mode, parsing, `outputName`, usage.
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift` **(EDIT)** — dispatch the new mode.
- `AGENTS.md` **(EDIT)** — command list + benchmark-flags note (the only doc edit outside `docs/superpowers/`).
- `docs/superpowers/verification/2026-06-20-dynamic-line-insert-delete.md` **(NEW)** — recorded verification evidence (Task 9).

The provider stays a single focused file. The benchmark mode is split out into its own file matching the existing one-benchmark-per-file convention in `Sources/ViewportBenchmarks`.

---

## Task 1: `BalancedTreeLineMetrics` — balanced build, `offset`, `lineCount`, `treeHeight`

A read-only, perfectly-balanced order-statistics tree that matches the prefix-sum oracle. No mutation yet.

**Files:**
- Create: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- Test: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes: `TextEngineCore.LineMetricsSource`, `PrefixSumLineMetrics(heights:)` (oracle).
- Produces (later tasks rely on these exact names/types):
  - `public struct BalancedTreeLineMetrics: LineMetricsSource`
  - `public init(heights: [Double])`
  - `public var lineCount: Int { get }`
  - `public func offset(ofLine index: Int) -> Double`
  - `public private(set) var lastMutationNodeVisits: Int` (declared now; written by Tasks 2–4)
  - `internal func treeHeight() -> Int`
  - private helpers `nodeCount(_:)`, `nodeSum(_:)`, `pull(_:)`, `buildBalanced(_:_:_:)`, and the nested `Node` type used by all later tasks.

- [ ] **Step 1: Write the failing test file**

Create `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`:

```swift
import XCTest
@testable import TextEngineReferenceProviders
import TextEngineCore

private final class QueryCounter {
    var count = 0
}

private struct CountingMetrics<Base: LineMetricsSource>: LineMetricsSource {
    let base: Base
    let counter: QueryCounter

    var lineCount: Int { base.lineCount }

    func offset(ofLine index: Int) -> Double {
        counter.count += 1
        return base.offset(ofLine: index)
    }
}

final class BalancedTreeLineMetricsTests: XCTestCase {
    // Deterministic, integer-valued, strictly-positive non-uniform heights in
    // {14,16,20,32}. Integer values with totals < 2^53 make tree partial sums
    // bit-exactly equal to the left-to-right prefix-sum oracle.
    private func sampleHeights(_ lineCount: Int) -> [Double] {
        var heights: [Double] = []
        heights.reserveCapacity(lineCount)
        for index in 0..<lineCount {
            let bucket = ((index &* 31) &+ 7) % 4
            switch bucket {
            case 0: heights.append(14.0)
            case 1: heights.append(16.0)
            case 2: heights.append(20.0)
            default: heights.append(32.0)
            }
        }
        return heights
    }

    private func floorLog2(_ value: Int) -> Int {
        precondition(value >= 1)
        return Int.bitWidth - 1 - value.leadingZeroBitCount
    }

    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value {
            capacity <<= 1
            power += 1
        }
        return power
    }

    private func expectSuccess(
        _ computation: ViewportComputation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> VirtualRange {
        switch computation {
        case let .success(range):
            return range
        case let .failure(error):
            XCTFail("expected success, got \(error)", file: file, line: line)
            return VirtualRange(
                visibleStart: 0, visibleEndExclusive: 0,
                bufferStart: 0, bufferEndExclusive: 0,
                isAtTop: true, isAtBottom: true
            )
        }
    }

    // Compares lineCount and every offset(0...count) against a freshly-built
    // prefix-sum oracle over `array`. The array is the easy oracle.
    private func assertMatchesOracle(
        _ tree: BalancedTreeLineMetrics,
        _ array: [Double],
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let oracle = PrefixSumLineMetrics(heights: array)
        XCTAssertEqual(tree.lineCount, oracle.lineCount, "lineCount \(message())", file: file, line: line)
        for i in 0...array.count {
            XCTAssertEqual(
                tree.offset(ofLine: i),
                oracle.offset(ofLine: i),
                "offset[\(i)] \(message())",
                file: file,
                line: line
            )
        }
    }

    func testOffsetMatchesPrefixSumOracleOnBuild() {
        let heights = sampleHeights(1_000)
        let tree = BalancedTreeLineMetrics(heights: heights)
        assertMatchesOracle(tree, heights)
    }

    func testBalancedBuildHeightIsLogarithmic() {
        let n = 100_000
        let tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
        // Perfectly-balanced midpoint build: height == floor(log2 n) + 1.
        XCTAssertLessThanOrEqual(tree.treeHeight(), ceilLog2(n + 1))
        XCTAssertGreaterThan(tree.treeHeight(), 0)
    }

    func testEmptyDocument() {
        let tree = BalancedTreeLineMetrics(heights: [])
        XCTAssertEqual(tree.lineCount, 0)
        XCTAssertEqual(tree.offset(ofLine: 0), 0.0)
        XCTAssertEqual(tree.treeHeight(), 0)
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: compile failure — `cannot find 'BalancedTreeLineMetrics' in scope`.

- [ ] **Step 3: Create the provider with build + read paths**

Create `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`:

```swift
import TextEngineCore

/// Mutable, indexed metrics provider backed by a size-balanced order-statistics
/// binary search tree held in a flat `[Node]` arena (integer child indices, no
/// pointers/classes/ARC). `offset(ofLine:)` is O(log N); `insertLine`,
/// `removeLine`, and `setHeight` are each a localized O(log N) update — unlike a
/// Fenwick tree or prefix-sum array, a mid-document insert/delete does NOT cost
/// O(N). Provider-owned memory is O(N): the line metrics are the document,
/// living outside the stateless core.
public struct BalancedTreeLineMetrics: LineMetricsSource {
    private struct Node {
        var height: Double           // this line's height (finite, > 0)
        var left: Int                // arena index of left child, -1 == none
        var right: Int               // arena index of right child, -1 == none
        var subtreeCount: Int        // number of lines in this subtree (incl. self)
        var subtreeHeightSum: Double // sum of heights in this subtree (incl. self)
    }

    private var nodes: [Node]   // the arena
    private var root: Int       // -1 when empty
    private var freeList: [Int] // recycled slots from removeLine

    /// Number of nodes visited by the most recent structural/height mutation
    /// (descent steps + rebalance touches). A logarithmic upper bound proportional
    /// to log N, not Fenwick's exact closed form — a balanced tree's count depends
    /// on shape and rotations. Deterministic evidence for the O(log N) update claim.
    public private(set) var lastMutationNodeVisits: Int

    public init(heights: [Double]) {
        for height in heights {
            precondition(
                height.isFinite && height > 0.0,
                "BalancedTreeLineMetrics requires finite, positive heights"
            )
        }
        var arena: [Node] = []
        arena.reserveCapacity(heights.count)
        self.nodes = arena
        self.root = -1
        self.freeList = []
        self.lastMutationNodeVisits = 0
        if !heights.isEmpty {
            self.root = buildBalanced(heights, 0, heights.count - 1)
        }
    }

    public var lineCount: Int {
        root == -1 ? 0 : nodes[root].subtreeCount
    }

    // offset(ofLine: index) = sum of heights of lines [0, index), via an
    // order-statistics descent. At a node whose left subtree holds `leftCount`
    // lines, the node sits at position `leftCount`. O(tree height) = O(log N).
    public func offset(ofLine index: Int) -> Double {
        var accum = 0.0
        var i = index
        var t = root
        while t != -1 {
            let leftCount = nodeCount(nodes[t].left)
            if i <= leftCount {
                t = nodes[t].left
            } else {
                accum += nodeSum(nodes[t].left) + nodes[t].height
                i -= leftCount + 1
                t = nodes[t].right
            }
        }
        return accum
    }

    // MARK: - Aggregates

    private func nodeCount(_ i: Int) -> Int {
        i == -1 ? 0 : nodes[i].subtreeCount
    }

    private func nodeSum(_ i: Int) -> Double {
        i == -1 ? 0.0 : nodes[i].subtreeHeightSum
    }

    // Recompute node `i`'s aggregates from its children. Child indices and height
    // are read into locals before the writes so the array accesses don't overlap.
    private mutating func pull(_ i: Int) {
        let l = nodes[i].left
        let r = nodes[i].right
        let h = nodes[i].height
        let newCount = 1 + nodeCount(l) + nodeCount(r)
        let newSum = h + nodeSum(l) + nodeSum(r)
        nodes[i].subtreeCount = newCount
        nodes[i].subtreeHeightSum = newSum
    }

    // O(N) perfectly-balanced build by recursive midpoint; aggregates filled
    // bottom-up, no rotations. In-order traversal yields heights in array order,
    // so offset(i) == sum(heights[0..<i]).
    private mutating func buildBalanced(_ heights: [Double], _ lo: Int, _ hi: Int) -> Int {
        let mid = lo + (hi - lo) / 2
        let nodeIndex = nodes.count
        nodes.append(
            Node(
                height: heights[mid], left: -1, right: -1,
                subtreeCount: 1, subtreeHeightSum: heights[mid]
            )
        )
        var left = -1
        var right = -1
        if lo <= mid - 1 {
            left = buildBalanced(heights, lo, mid - 1)
        }
        if mid + 1 <= hi {
            right = buildBalanced(heights, mid + 1, hi)
        }
        nodes[nodeIndex].left = left
        nodes[nodeIndex].right = right
        nodes[nodeIndex].subtreeCount = 1 + nodeCount(left) + nodeCount(right)
        nodes[nodeIndex].subtreeHeightSum = heights[mid] + nodeSum(left) + nodeSum(right)
        return nodeIndex
    }

    // Test-only white-box access (NOT public API), reached via `@testable import`.
    // Iterative DFS over the arena; O(N). Height = number of nodes on the longest
    // root-to-leaf path (a single node has height 1, empty tree 0).
    internal func treeHeight() -> Int {
        if root == -1 { return 0 }
        var maxDepth = 0
        var stack: [(node: Int, depth: Int)] = [(root, 1)]
        while let top = stack.popLast() {
            if top.depth > maxDepth { maxDepth = top.depth }
            let l = nodes[top.node].left
            let r = nodes[top.node].right
            if l != -1 { stack.append((l, top.depth + 1)) }
            if r != -1 { stack.append((r, top.depth + 1)) }
        }
        return maxDepth
    }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "feat: add BalancedTreeLineMetrics balanced build and offset query

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `setHeight` — O(log N) height mutation (no structural change)

**Files:**
- Modify: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- Modify: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes: `nodeCount(_:)`, `lastMutationNodeVisits` (Task 1).
- Produces: `@discardableResult public mutating func setHeight(ofLine index: Int, to newHeight: Double) -> Int`; private `updateHeight(_:_:_:) -> Double`.

- [ ] **Step 1: Write the failing tests**

Add these methods inside `BalancedTreeLineMetricsTests`:

```swift
    func testSetHeightMatchesFreshOracle() {
        let heights = sampleHeights(500)
        var tree = BalancedTreeLineMetrics(heights: heights)
        var mutated = heights
        // First line, last line, an interior line, then the same interior line
        // again (repeated edit).
        let edits: [(index: Int, height: Double)] = [
            (0, 40.0), (heights.count - 1, 12.0), (250, 28.0), (250, 50.0)
        ]
        for edit in edits {
            let returned = tree.setHeight(ofLine: edit.index, to: edit.height)
            XCTAssertEqual(returned, tree.lastMutationNodeVisits)
            mutated[edit.index] = edit.height
            assertMatchesOracle(tree, mutated, "after editing line \(edit.index)")
        }
    }

    func testSetHeightKeepsOffsetsStrictlyIncreasing() {
        let heights = sampleHeights(300)
        var tree = BalancedTreeLineMetrics(heights: heights)
        tree.setHeight(ofLine: 0, to: 64.0)
        tree.setHeight(ofLine: 299, to: 2.0)
        tree.setHeight(ofLine: 150, to: 5.0)
        for i in 0..<tree.lineCount {
            XCTAssertLessThan(
                tree.offset(ofLine: i),
                tree.offset(ofLine: i + 1),
                "offsets not strictly increasing at line \(i)"
            )
        }
    }

    func testSetHeightVisitCountIsLogarithmic() {
        for n in [1_000, 100_000, 1_000_000] {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
            let visits = tree.setHeight(ofLine: n / 2, to: 24.0)
            // Descent depth only (no rebalance): bounded by the tree height.
            XCTAssertLessThanOrEqual(visits, 4 * (floorLog2(n) + 1), "n=\(n)")
            XCTAssertGreaterThan(visits, 0)
        }
    }
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: compile failure — `value of type 'BalancedTreeLineMetrics' has no member 'setHeight'`.

- [ ] **Step 3: Implement `setHeight`**

Add inside `BalancedTreeLineMetrics`, after `offset(ofLine:)` (before the `// MARK: - Aggregates` section):

```swift
    // MARK: - Height mutation

    // Sets the line at `index` to `newHeight` and adds the height delta to
    // subtreeHeightSum along the ancestor path on the way back up. No structural
    // change, no rebalance. Returns the node-visit count. O(log N).
    @discardableResult
    public mutating func setHeight(ofLine index: Int, to newHeight: Double) -> Int {
        precondition(
            index >= 0 && index < lineCount,
            "BalancedTreeLineMetrics.setHeight index out of range"
        )
        precondition(
            newHeight.isFinite && newHeight > 0.0,
            "BalancedTreeLineMetrics.setHeight requires a finite, positive height"
        )
        lastMutationNodeVisits = 0
        _ = updateHeight(root, index, newHeight)
        return lastMutationNodeVisits
    }

    private mutating func updateHeight(_ t: Int, _ index: Int, _ newHeight: Double) -> Double {
        lastMutationNodeVisits += 1
        let leftCount = nodeCount(nodes[t].left)
        let delta: Double
        if index < leftCount {
            delta = updateHeight(nodes[t].left, index, newHeight)
        } else if index > leftCount {
            delta = updateHeight(nodes[t].right, index - leftCount - 1, newHeight)
        } else {
            delta = newHeight - nodes[t].height
            nodes[t].height = newHeight
        }
        nodes[t].subtreeHeightSum += delta
        return delta
    }
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "feat: add O(log N) setHeight to BalancedTreeLineMetrics

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `insertLine` — O(log N) structural insert with SBT rebalancing

The first structural edit. Brings in node allocation, rotations, and the Size-Balanced-Tree `maintain`. Correctness under heavy insertion (including repeated head inserts that force rotations) is proven against the oracle, and balance is proven by `treeHeight()`.

**Files:**
- Modify: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- Modify: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes: `pull(_:)`, `nodeCount(_:)`, `treeHeight()` (Tasks 1).
- Produces: `@discardableResult public mutating func insertLine(at index: Int, height: Double) -> Int`; private `allocateNode(height:) -> Int`, `insert(_:_:_:) -> Int`, `rotateLeft(_:) -> Int`, `rotateRight(_:) -> Int`, `maintain(_:leftGrew:) -> Int`, `leftChild(_:) -> Int`, `rightChild(_:) -> Int`. (Tasks 4 reuses `maintain`, `pull`, `leftChild`, `rightChild`.)

- [ ] **Step 1: Write the failing tests**

Add inside `BalancedTreeLineMetricsTests`:

```swift
    func testInsertSequenceMatchesOracleAndStaysBalanced() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(40))
        var mutated = sampleHeights(40)
        // 500 deterministic inserts at head, tail, and interior positions, heights
        // from a fixed integer set. Head inserts (index 0) force left-heavy
        // rebalancing; tail inserts force right-heavy.
        let positionsCycle = 5
        for k in 0..<500 {
            let count = mutated.count
            let index: Int
            switch k % positionsCycle {
            case 0: index = 0
            case 1: index = count            // tail (insert at end)
            case 2: index = count / 2
            case 3: index = count / 3
            default: index = (count * 2) / 3
            }
            let height = Double(10 + (k % 5) * 6) // 10,16,22,28,34
            let visits = tree.insertLine(at: index, height: height)
            XCTAssertGreaterThan(visits, 0)
            mutated.insert(height, at: index)
            assertMatchesOracle(tree, mutated, "after insert #\(k) at \(index)")
        }
        // Balanced after 500 inserts: height stays logarithmic, not linear.
        XCTAssertLessThanOrEqual(
            tree.treeHeight(),
            3 * (floorLog2(tree.lineCount) + 1),
            "tree height not logarithmic: \(tree.treeHeight()) for lineCount \(tree.lineCount)"
        )
    }

    func testInsertIntoEmptyDocument() {
        var tree = BalancedTreeLineMetrics(heights: [])
        XCTAssertEqual(tree.lineCount, 0)
        tree.insertLine(at: 0, height: 21.0)
        assertMatchesOracle(tree, [21.0])
        tree.insertLine(at: 1, height: 13.0)
        assertMatchesOracle(tree, [21.0, 13.0])
        tree.insertLine(at: 0, height: 17.0)
        assertMatchesOracle(tree, [17.0, 21.0, 13.0])
    }
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: compile failure — `no member 'insertLine'`.

- [ ] **Step 3: Implement insert, rotations, and SBT `maintain`**

Add inside `BalancedTreeLineMetrics`, after the height-mutation section:

```swift
    // MARK: - Structural mutation: insert

    // Inserts a new line of `height` so it lands at in-order position `index`.
    // O(log N): descend to the leaf insertion point, splice in a node (reusing a
    // freed slot when available), fix aggregates, rebalance. Returns node visits.
    @discardableResult
    public mutating func insertLine(at index: Int, height: Double) -> Int {
        precondition(
            index >= 0 && index <= lineCount,
            "BalancedTreeLineMetrics.insertLine index out of range"
        )
        precondition(
            height.isFinite && height > 0.0,
            "BalancedTreeLineMetrics.insertLine requires a finite, positive height"
        )
        lastMutationNodeVisits = 0
        let newNode = allocateNode(height: height)
        root = insert(root, index, newNode)
        return lastMutationNodeVisits
    }

    // Reuses a freed slot when available, else appends. New node is a leaf.
    private mutating func allocateNode(height: Double) -> Int {
        let node = Node(
            height: height, left: -1, right: -1,
            subtreeCount: 1, subtreeHeightSum: height
        )
        if let slot = freeList.popLast() {
            nodes[slot] = node
            return slot
        }
        nodes.append(node)
        return nodes.count - 1
    }

    private mutating func insert(_ t: Int, _ index: Int, _ newNode: Int) -> Int {
        lastMutationNodeVisits += 1
        if t == -1 { return newNode }
        let leftCount = nodeCount(nodes[t].left)
        let goLeft = index <= leftCount
        if goLeft {
            let updated = insert(nodes[t].left, index, newNode)
            nodes[t].left = updated
        } else {
            let updated = insert(nodes[t].right, index - leftCount - 1, newNode)
            nodes[t].right = updated
        }
        pull(t)
        return maintain(t, leftGrew: goLeft)
    }

    // MARK: - SBT balance

    private func leftChild(_ i: Int) -> Int { i == -1 ? -1 : nodes[i].left }
    private func rightChild(_ i: Int) -> Int { i == -1 ? -1 : nodes[i].right }

    // Right-rotate around x; left child y becomes the new subtree root. Each
    // rotation recomputes the two affected nodes' aggregates (child first, then
    // new parent), keeping order-statistics correct through rebalancing.
    private mutating func rotateRight(_ x: Int) -> Int {
        let y = nodes[x].left
        let yRight = nodes[y].right
        nodes[x].left = yRight
        nodes[y].right = x
        pull(x)
        pull(y)
        return y
    }

    // Left-rotate around x; right child y becomes the new subtree root.
    private mutating func rotateLeft(_ x: Int) -> Int {
        let y = nodes[x].right
        let yLeft = nodes[y].left
        nodes[x].right = yLeft
        nodes[y].left = x
        pull(x)
        pull(y)
        return y
    }

    // Size-Balanced-Tree maintain. `leftGrew == true` means the left side may now
    // be too large (after a left insert, or a right-side delete that relatively
    // grew the left); false means the right side. Restores "no subtree smaller
    // than a nephew" and recurses only where a rotation happened. Amortized O(1).
    private mutating func maintain(_ t: Int, leftGrew: Bool) -> Int {
        if t == -1 { return -1 }
        lastMutationNodeVisits += 1
        var t = t
        if leftGrew {
            let l = nodes[t].left
            if nodeCount(leftChild(l)) > nodeCount(nodes[t].right) {
                t = rotateRight(t)
            } else if nodeCount(rightChild(l)) > nodeCount(nodes[t].right) {
                let rotated = rotateLeft(l)
                nodes[t].left = rotated
                t = rotateRight(t)
            } else {
                return t
            }
        } else {
            let r = nodes[t].right
            if nodeCount(rightChild(r)) > nodeCount(nodes[t].left) {
                t = rotateLeft(t)
            } else if nodeCount(leftChild(r)) > nodeCount(nodes[t].left) {
                let rotated = rotateRight(r)
                nodes[t].right = rotated
                t = rotateLeft(t)
            } else {
                return t
            }
        }
        let newLeft = maintain(nodes[t].left, leftGrew: true)
        nodes[t].left = newLeft
        let newRight = maintain(nodes[t].right, leftGrew: false)
        nodes[t].right = newRight
        t = maintain(t, leftGrew: true)
        t = maintain(t, leftGrew: false)
        return t
    }
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "feat: add O(log N) insertLine with SBT rebalancing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `removeLine` — O(log N) structural delete

Standard BST delete by position with in-order successor swap for two-children nodes, slot recycling, and the same `maintain`.

**Files:**
- Modify: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- Modify: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes: `pull(_:)`, `nodeCount(_:)`, `maintain(_:leftGrew:)`, `freeList` (Tasks 1, 3).
- Produces: `@discardableResult public mutating func removeLine(at index: Int) -> Int`; private `remove(_:_:) -> Int`, `minNode(_:) -> Int`, `removeMin(_:) -> Int`.

- [ ] **Step 1: Write the failing test**

Add inside `BalancedTreeLineMetricsTests`:

```swift
    func testRemoveSequenceMatchesOracleDownToEmpty() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(600))
        var mutated = sampleHeights(600)
        var k = 0
        while !mutated.isEmpty {
            let count = mutated.count
            // Cycle head / tail / interior removals (interior exercises the
            // two-children successor-swap delete path).
            let raw: Int
            switch k % 3 {
            case 0: raw = 0
            case 1: raw = count - 1
            default: raw = count / 2
            }
            let index = raw % count
            let visits = tree.removeLine(at: index)
            XCTAssertGreaterThan(visits, 0)
            mutated.remove(at: index)
            assertMatchesOracle(tree, mutated, "after removing index \(index) (k=\(k))")
            k += 1
        }
        XCTAssertEqual(tree.lineCount, 0)
        XCTAssertEqual(tree.offset(ofLine: 0), 0.0)
        XCTAssertEqual(tree.treeHeight(), 0)
    }
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: compile failure — `no member 'removeLine'`.

- [ ] **Step 3: Implement `removeLine`**

Add inside `BalancedTreeLineMetrics`, after the insert section (before `// MARK: - SBT balance` is fine, or after it — order is cosmetic):

```swift
    // MARK: - Structural mutation: remove

    // Removes the line at `index`. O(log N): descend to the target, remove it
    // (in-order successor swap when it has two children), recycle its slot, fix
    // aggregates, rebalance. Returns node visits.
    @discardableResult
    public mutating func removeLine(at index: Int) -> Int {
        precondition(
            index >= 0 && index < lineCount,
            "BalancedTreeLineMetrics.removeLine index out of range"
        )
        lastMutationNodeVisits = 0
        root = remove(root, index)
        return lastMutationNodeVisits
    }

    private mutating func remove(_ t: Int, _ index: Int) -> Int {
        lastMutationNodeVisits += 1
        let leftCount = nodeCount(nodes[t].left)
        if index < leftCount {
            let updated = remove(nodes[t].left, index)
            nodes[t].left = updated
            pull(t)
            return maintain(t, leftGrew: false) // left shrank -> right may be too big
        } else if index > leftCount {
            let updated = remove(nodes[t].right, index - leftCount - 1)
            nodes[t].right = updated
            pull(t)
            return maintain(t, leftGrew: true)  // right shrank -> left may be too big
        } else {
            let l = nodes[t].left
            let r = nodes[t].right
            if l == -1 {
                freeList.append(t)
                return r
            } else if r == -1 {
                freeList.append(t)
                return l
            } else {
                // Two children: copy the in-order successor's height into this
                // node, then delete the successor (the min of the right subtree).
                let succ = minNode(r)
                nodes[t].height = nodes[succ].height
                let updated = removeMin(r)
                nodes[t].right = updated
                pull(t)
                return maintain(t, leftGrew: true) // right shrank -> left may be too big
            }
        }
    }

    // Leftmost node of subtree `t` (non-mutating; the descent walks the left spine).
    private func minNode(_ t: Int) -> Int {
        var i = t
        while nodes[i].left != -1 { i = nodes[i].left }
        return i
    }

    // Removes the leftmost node of subtree `t`, recycles its slot, returns the new
    // subtree root.
    private mutating func removeMin(_ t: Int) -> Int {
        lastMutationNodeVisits += 1
        if nodes[t].left == -1 {
            let r = nodes[t].right
            freeList.append(t)
            return r
        }
        let updated = removeMin(nodes[t].left)
        nodes[t].left = updated
        pull(t)
        return maintain(t, leftGrew: false) // left shrank -> right may be too big
    }
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "feat: add O(log N) removeLine to BalancedTreeLineMetrics

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Mixed-mutation equivalence oracle, node-visit bound, and tree-height invariant

The decisive correctness and complexity proofs (spec tests 2, 3, 4, 5). The provider is now complete; these tests stress all three mutations interleaved and assert the logarithmic guarantees.

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes: full `BalancedTreeLineMetrics` API + `treeHeight()` + `assertMatchesOracle`, `floorLog2` (Tasks 1–4). No new production code.

- [ ] **Step 1: Write the failing tests**

Add inside `BalancedTreeLineMetricsTests`:

```swift
    func testMixedMutationEquivalenceOracle() {
        // Deterministic LCG (no Foundation): seeded, reproducible op sequence.
        var rngState: UInt64 = 0x2545F4914F6CDD1D
        func nextRandom(_ bound: Int) -> Int {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            return Int((rngState >> 33) % UInt64(bound))
        }

        var tree = BalancedTreeLineMetrics(heights: sampleHeights(40))
        var array = sampleHeights(40)
        let heightChoices = [10.0, 16.0, 22.0, 28.0, 34.0]

        for step in 0..<2_000 {
            let count = array.count
            let op = count == 0 ? 0 : nextRandom(3) // force insert when empty
            switch op {
            case 0: // insert (head / tail / interior all reachable)
                let index = nextRandom(count + 1)
                let height = heightChoices[nextRandom(heightChoices.count)]
                tree.insertLine(at: index, height: height)
                array.insert(height, at: index)
            case 1: // remove
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
            // Strictly-increasing invariant (spec test 3) after each op.
            for i in 0..<tree.lineCount {
                XCTAssertLessThan(
                    tree.offset(ofLine: i),
                    tree.offset(ofLine: i + 1),
                    "not strictly increasing at \(i) after step \(step)"
                )
            }
        }

        // Remove-to-empty edge, then refill from empty.
        while array.count > 0 {
            tree.removeLine(at: 0)
            array.remove(at: 0)
            assertMatchesOracle(tree, array, "draining to empty")
        }
        XCTAssertEqual(tree.lineCount, 0)
        tree.insertLine(at: 0, height: 21.0)
        array.insert(21.0, at: 0)
        assertMatchesOracle(tree, array, "refill from empty")
    }

    func testStructuralMutationVisitCountIsLogarithmic() {
        var visitsBySize: [Int: Int] = [:]
        for n in [1_000, 100_000, 1_000_000] {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
            let visits = tree.insertLine(at: n / 2, height: 24.0)
            XCTAssertGreaterThan(visits, 0)
            // Descent + rebalance touches stay within a small constant times log N.
            XCTAssertLessThanOrEqual(visits, 10 * (floorLog2(n) + 1), "n=\(n)")
            visitsBySize[n] = visits
        }
        // A 1000x size jump must NOT scale visits ~1000x; a balanced tree's
        // descent grows only logarithmically (~2x over this range).
        XCTAssertLessThan(
            visitsBySize[1_000_000]!,
            visitsBySize[1_000]! * 8,
            "node visits grew faster than logarithmic across a 1000x size jump"
        )
    }

    func testTreeHeightStaysLogarithmicAfterEditSequence() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(10_000))
        // Deterministic interleaved inserts and deletes that churn the structure.
        for k in 0..<10_000 {
            let count = tree.lineCount
            if k % 2 == 0 {
                let index = (k &* 7) % (count + 1)
                tree.insertLine(at: index, height: Double(12 + (k % 4) * 5))
            } else {
                let index = (k &* 13) % count
                tree.removeLine(at: index)
            }
        }
        XCTAssertGreaterThan(tree.lineCount, 0)
        XCTAssertLessThanOrEqual(
            tree.treeHeight(),
            3 * (floorLog2(tree.lineCount) + 1),
            "tree height not logarithmic: height=\(tree.treeHeight()) lineCount=\(tree.lineCount)"
        )
    }
```

- [ ] **Step 2: Run the tests to confirm they fail, then pass**

These exercise only existing API, so they should **pass immediately** — that is acceptable here because the implementation already exists (Tasks 1–4); their role is to prove the aggregate/balance invariants hold across mixed editing. Run:

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: PASS (12 tests). If `testMixedMutationEquivalenceOracle` fails, an aggregate is mis-maintained in a rotation or the successor-swap delete (Tasks 3/4) — fix there, not here.

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "test: prove mixed-mutation equivalence, log node visits, log tree height

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Re-layout composition with the stateless core

Proves the core composes correctly with the mutated provider with **no core change** (spec test 6): identical range + geometry stream vs a fresh oracle after a structural edit, and O(log N) core offset queries.

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.compute(_:metrics:)`, `ViewportVirtualizer.geometry(for:metrics:)`, `VariableViewportInput`, `VirtualRange`, `LineGeometry` (`TextEngineCore`); `QueryCounter`/`CountingMetrics`/`expectSuccess`/`ceilLog2` (file helpers, Task 1).

- [ ] **Step 1: Write the failing tests**

Add inside `BalancedTreeLineMetricsTests`:

```swift
    func testReLayoutAfterStructuralEditMatchesFreshOracle() {
        var array = sampleHeights(10_000)
        var tree = BalancedTreeLineMetrics(heights: array)
        // Structural edit: delete one line, insert a different one elsewhere.
        tree.removeLine(at: 4_321)
        array.remove(at: 4_321)
        tree.insertLine(at: 2_000, height: 48.0)
        array.insert(48.0, at: 2_000)
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
            XCTAssertEqual(a, b, "geometry mismatch at emitted index \(emitted)")
            if a == nil && b == nil { break }
            emitted += 1
            if emitted >= 1_000 {
                XCTFail("geometry cursor did not terminate")
                return
            }
        }
        XCTAssertGreaterThan(emitted, 0)
    }

    func testReLayoutAfterStructuralEditUsesLogarithmicCoreQueries() {
        let n = 1_000_000
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
        tree.removeLine(at: n / 3)
        tree.insertLine(at: n / 4, height: 50.0) // lineCount back to n

        let counter = QueryCounter()
        let counting = CountingMetrics(base: tree, counter: counter)
        let input = VariableViewportInput(
            scrollOffsetY: tree.offset(ofLine: n / 2),
            viewportHeight: 80.0 * 16.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )
        _ = expectSuccess(ViewportVirtualizer.compute(input, metrics: counting))

        // Two O(1) contract queries (offset 0 and total) plus two binary searches.
        // A linear scan would be hundreds of thousands of queries.
        let expectedMax = 2 + (ceilLog2(n) + 1) * 2
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter BalancedTreeLineMetricsTests 2>&1 | tail -20`
Expected: PASS (14 tests). (Existing API only — these prove composition; they should pass once Tasks 1–4 are correct.)

- [ ] **Step 3: Run the full suite + Foundation scan to confirm nothing regressed**

Run: `swift test 2>&1 | tail -15`
Expected: all tests pass; total grows by 14 over the Task-0 baseline. (`swift test` also prints a "0 tests in 0 suites" line for the empty Swift Testing harness — not a failure.)

Run: `rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "exit=$?"`
Expected: no matches (`rg` prints nothing, `exit=1`).

- [ ] **Step 4: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "test: prove core re-layout composition after structural edit

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: `--structural-mutation` benchmark mode with local gate

Adds the benchmark mode (output name `structural_mutation`) over the 1k / 100k / 1M scenarios, modeled on `VariableHeightMutationBenchmark`, with a local `--gate`. Budgets are calibrated from observed local numbers + headroom (macOS-calibrated, like the other gates).

**Files:**
- Create: `Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`

**Interfaces:**
- Consumes: `VariableHeightScenario`, `variableHeights(lineCount:)`, `deterministicScrollOffset(sample:maxOffset:)`, `nanoseconds(_:)`, `percentile(_:numerator:denominator:)`, `formatSummary(_:includeGate:)`, `BenchmarkSummary`, `BenchmarkOperationResult` (existing in `Sources/ViewportBenchmarks`); `BalancedTreeLineMetrics`, `ViewportVirtualizer.compute(_:metrics:)`, `geometry(for:metrics:)`.
- Produces: `BenchmarkMode.structuralMutation` (outputName `"structural_mutation"`); `func runStructuralMutationBenchmarks(enforceGate: Bool) -> Bool`.

- [ ] **Step 1: Add the `.structuralMutation` mode to `BenchmarkOptions`**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, add the case to the `BenchmarkMode` enum (after `.variableHeightMutation`):

```swift
    case variableHeightMutation
    case structuralMutation
    case memoryShape
```

Add its `outputName` (in the `outputName` switch, after the `variableHeightMutation` case):

```swift
        case .variableHeightMutation:
            return "variable_height_mutation"
        case .structuralMutation:
            return "structural_mutation"
        case .memoryShape:
            return "memory_shape"
```

Add parsing (in `parse`, after the `--variable-height-mutation` case):

```swift
            case "--structural-mutation":
                if mode != .pipeline {
                    return .failure("--structural-mutation cannot be combined with another mode")
                }
                mode = .structuralMutation
```

Update the usage string to include the new flag. Replace the `Usage:` line and add an `Options:` entry:

```swift
    static let usage = """
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--variable-height] [--variable-height-mutation] [--structural-mutation] [--memory-shape] [--memory-observation] [--help]

    Options:
      --range-only          Run only viewport range recompute benchmark.
      --gate                Enforce p95/p99 budgets for gateable benchmark modes and exit non-zero on failure.
      --realistic-provider  Run large-text provider benchmark. Combine with --gate to enforce calibrated budgets.
      --variable-height     Run variable-height compute+geometry benchmark. Combine with --gate to enforce budgets.
      --variable-height-mutation  Run mutate+recompute benchmark (Fenwick provider). Combine with --gate to enforce budgets.
      --structural-mutation  Run insert/delete+recompute benchmark (balanced-tree provider). Combine with --gate to enforce budgets.
      --memory-shape        Run deterministic core-owned memory-shape diagnostics.
      --memory-observation  Run host RSS observation diagnostics.
      --help                Print this help.
    """
```

No change to the gate-rejection line: `--gate` stays **valid** with `.structuralMutation` because the rejection guard only lists `.rangeOnly`, `.memoryShape`, `.memoryObservation`.

- [ ] **Step 2: Build to confirm the dispatch is now non-exhaustive (failing build)**

Run: `swift build 2>&1 | tail -15`
Expected: FAIL — `runBenchmarks(options:)` in `BenchmarkProgram.swift` has a non-exhaustive switch (`must be exhaustive`, missing `.structuralMutation`). This is the "red" state driving Step 3.

- [ ] **Step 3: Dispatch the new mode in `BenchmarkProgram`**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, add to the `runBenchmarks` switch (after the `variableHeightMutation` case):

```swift
    case .variableHeightMutation:
        return runVariableHeightMutationBenchmarks(enforceGate: options.enforceGate)
    case .structuralMutation:
        return runStructuralMutationBenchmarks(enforceGate: options.enforceGate)
    case .memoryShape:
        return runMemoryShapeDiagnostics()
```

- [ ] **Step 4: Create the benchmark file (with provisional generous budgets)**

Create `Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift`. The budgets below are **provisional generous floors**; Step 6 calibrates them from observed local p95/p99 + headroom.

```swift
import TextEngineCore
import TextEngineReferenceProviders

// Reuses VariableHeightScenario, variableHeights(lineCount:), and
// deterministicScrollOffset from VariableHeightBenchmark.swift / BenchmarkSupport.swift.
func structuralMutationScenarios() -> [VariableHeightScenario] {
    [
        VariableHeightScenario(
            name: "1k_lines_20_visible_overscan_0",
            lineCount: 1_000,
            viewportHeight: 20.0 * 16.0,
            overscanBefore: 0,
            overscanAfter: 0,
            p95BudgetNanoseconds: 20_000,
            p99BudgetNanoseconds: 40_000
        ),
        VariableHeightScenario(
            name: "100k_lines_80_visible_overscan_5",
            lineCount: 100_000,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5,
            p95BudgetNanoseconds: 80_000,
            p99BudgetNanoseconds: 120_000
        ),
        VariableHeightScenario(
            name: "1m_lines_200_visible_overscan_50",
            lineCount: 1_000_000,
            viewportHeight: 200.0 * 16.0,
            overscanBefore: 50,
            overscanAfter: 50,
            p95BudgetNanoseconds: 250_000,
            p99BudgetNanoseconds: 400_000
        )
    ]
}

@inline(never)
func runStructuralMutationOperation(
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
func runStructuralMutationScenario(
    _ scenario: VariableHeightScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    // One provider, mutated in place across all operations (no per-op rebuild of
    // any structure; the PrefixSum oracle never appears in the hot path).
    var metrics = BalancedTreeLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
    let initialTotal = metrics.offset(ofLine: metrics.lineCount)
    let maxOffset = initialTotal > scenario.viewportHeight ? initialTotal - scenario.viewportHeight : 0.0
    let lineCount = scenario.lineCount
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            // Pin lineCount constant: remove one line, insert one elsewhere, both
            // at deterministic positions spread across the document. After the
            // remove the count is lineCount-1, so insert index domain is
            // 0...(lineCount-1); `% lineCount` stays within it.
            let removeIndex = (sample &* 2_654_435_761) % lineCount
            metrics.removeLine(at: removeIndex)
            checksum &+= metrics.lastMutationNodeVisits

            let insertIndex = (sample &* 40_503) % lineCount
            let newHeight = ((sample & 1) == 0) ? 18.0 : 30.0
            metrics.insertLine(at: insertIndex, height: newHeight)
            checksum &+= metrics.lastMutationNodeVisits

            let offset = deterministicScrollOffset(sample: sample, maxOffset: maxOffset)
            let input = VariableViewportInput(
                scrollOffsetY: offset,
                viewportHeight: scenario.viewportHeight,
                overscanLinesBefore: scenario.overscanBefore,
                overscanLinesAfter: scenario.overscanAfter
            )
            let operationResult = runStructuralMutationOperation(input: input, metrics: metrics)
            checksum &+= operationResult.checksum
            failureCount &+= operationResult.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .structuralMutation,
        providerName: "balanced_tree",
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
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
func runStructuralMutationBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in structuralMutationScenarios() {
        let summary = runStructuralMutationScenario(
            scenario,
            iterations: iterations,
            operationsPerSample: operationsPerSample
        )
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

- [ ] **Step 5: Build and run the benchmark without the gate**

Run: `swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

Run: `swift run -c release ViewportBenchmarks -- --structural-mutation 2>&1 | tail -5`
Expected: three lines `mode=structural_mutation provider=balanced_tree scenario=... p95_ns=<X> p99_ns=<Y> failures=0 checksum=<...>`, all `failures=0`. **Record the observed `p95_ns` / `p99_ns` per scenario.**

- [ ] **Step 6: Calibrate budgets from observed numbers + headroom**

For each scenario set `p95BudgetNanoseconds = ceil(observed_p95 * 1.8)` and `p99BudgetNanoseconds = ceil(observed_p99 * 1.8)`, but never below the provisional floor already in the file (keep whichever is larger). Round up to a clean number. Edit the three scenarios in `structuralMutationScenarios()` accordingly. (If the observed numbers comfortably fit under the provisional floors, leave the floors — they are already generous.)

- [ ] **Step 7: Run with the gate**

Run: `swift run -c release ViewportBenchmarks -- --structural-mutation --gate 2>&1 | tail -5`
Expected: three lines each ending `gate=pass`; process exits 0.

Also confirm mode-combination + help still parse:

Run: `swift run -c release ViewportBenchmarks -- --structural-mutation --variable-height 2>&1 | tail -3`
Expected: `error=--variable-height cannot be combined with another mode` (or the symmetric message) and a non-zero exit.

Run: `swift run -c release ViewportBenchmarks -- --help 2>&1 | grep structural`
Expected: the `--structural-mutation` usage line.

- [ ] **Step 8: Commit**

```bash
git add Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift
git commit -m "feat: add --structural-mutation benchmark mode with local gate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Update `AGENTS.md` command list and benchmark-flags note

The only doc edit outside `docs/superpowers/`.

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Add the command-list line**

In the `## Commands` fenced block, add a line immediately after the `--variable-height-mutation` line. Replace:

```
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate   # mutate+recompute local gate
swift run -c release ViewportBenchmarks -- --memory-shape    # memory-shape invariant; expect invariant=pass
```

with:

```
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate   # mutate+recompute local gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate   # structural insert/delete local gate
swift run -c release ViewportBenchmarks -- --memory-shape    # memory-shape invariant; expect invariant=pass
```

- [ ] **Step 2: Update the benchmark-flags note**

Replace:

```
Benchmark flags: `--range-only`, `--realistic-provider`, `--variable-height`,
`--variable-height-mutation`, `--memory-shape`, `--memory-observation`, `--gate`.
Only one mode flag at a time. `--gate` is valid with the default pipeline,
`--realistic-provider`, `--variable-height`, and `--variable-height-mutation`
modes; it is **rejected** with `--range-only`, `--memory-shape`,
`--memory-observation`.
```

with:

```
Benchmark flags: `--range-only`, `--realistic-provider`, `--variable-height`,
`--variable-height-mutation`, `--structural-mutation`, `--memory-shape`,
`--memory-observation`, `--gate`. Only one mode flag at a time. `--gate` is
valid with the default pipeline, `--realistic-provider`, `--variable-height`,
`--variable-height-mutation`, and `--structural-mutation` modes; it is
**rejected** with `--range-only`, `--memory-shape`, `--memory-observation`.
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document --structural-mutation benchmark flag

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Verification record

Run the full spec verification command set, capture real output, and record it. This is evidence, not assertion.

**Files:**
- Create: `docs/superpowers/verification/2026-06-20-dynamic-line-insert-delete.md`

- [ ] **Step 1: Run every verification command and capture output**

```bash
swift test 2>&1 | tail -15
swift build -c release 2>&1 | tail -3
swift build -c release --target TextEngineReferenceProviders 2>&1 | tail -3
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tail -6
swift run -c release ViewportBenchmarks -- --variable-height --gate 2>&1 | tail -4
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate 2>&1 | tail -4
swift run -c release ViewportBenchmarks -- --structural-mutation --gate 2>&1 | tail -4
swift run -c release ViewportBenchmarks -- --memory-shape 2>&1 | tail -4
rg -n "Foundation" Sources/TextEngineCore; echo "core_scan_exit=$?"
rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "providers_scan_exit=$?"
./.github/scripts/cross-target-compile.sh --self-test 2>&1 | tail -3
git diff --check
git diff --name-only main...HEAD
```

Expected, in order: all host tests pass; `Build complete!` (×2 for the two builds); `gate=pass` for the four gated runs; `invariant=pass` for memory-shape; both Foundation scans empty (`*_scan_exit=1`); `self_test=pass`; `git diff --check` empty; `git diff --name-only` lists only `Sources/TextEngineReferenceProviders/**`, `Sources/ViewportBenchmarks/**`, `Tests/TextEngineReferenceProvidersTests/**`, `AGENTS.md`, and `docs/**`.

- [ ] **Step 2: Write the verification record**

Create `docs/superpowers/verification/2026-06-20-dynamic-line-insert-delete.md` with: the exact commands above, their captured outputs, the calibrated benchmark budgets and observed p95/p99, the new host-test total vs the prior baseline, and (filled in after the PR opens) the hosted PR run + post-merge push run IDs for the three required jobs (`Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`), anchored on the post-merge push run.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/verification/2026-06-20-dynamic-line-insert-delete.md
git commit -m "docs: record slice 23 verification evidence

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 4: Cross-target compile (portability-sensitive change)**

Because a new file lands in the cross-compiled `TextEngineReferenceProviders` product:

Run: `./.github/scripts/cross-target-compile.sh --targets ios 2>&1 | tail -10`
Expected: iOS device + simulator compile both `TextEngineCore` and `TextEngineReferenceProviders` (blocking) succeed. (WASM is observational and may record a non-blocking skip if no matching Swift SDK is installed; run `--targets wasm` if an SDK is provisioned.)

---

## Spec Coverage Map

| Spec item | Task |
| --- | --- |
| `BalancedTreeLineMetrics` flat-arena BST, `init(heights:)` O(N), `offset` O(log N), `lineCount` O(1) | 1 |
| `setHeight(ofLine:to:)` O(log N) | 2 |
| `insertLine(at:height:)` O(log N) + SBT `maintain`/rotations + freeList | 3 |
| `removeLine(at:)` O(log N) + successor swap + slot recycle | 4 |
| `lastMutationNodeVisits` instrumentation (Decision 4) | 1 (declared), 2–4 (written) |
| Static-message `precondition` handling (Decision 5) | 2, 3, 4 |
| Value semantics, struct + `[Node]` arena (Decision 6) | 1 |
| Test 1 build correctness | 1 |
| Test 2 structural-mutation equivalence oracle (mixed, after every op, edges) | 5 |
| Test 3 strictly-increasing invariant | 2 (setHeight), 5 (mixed) |
| Test 4 logarithmic node-visit bound across sizes | 5 |
| Test 5 tree-height invariant via `internal treeHeight()` (`@testable`) | 1 (impl), 3 & 5 (asserts) |
| Test 6 re-layout composition + counting wrapper | 6 |
| `--structural-mutation` benchmark mode + local gate (Component Design) | 7 |
| `BenchmarkMode`/parse/dispatch/usage edits, gate valid | 7 |
| AGENTS.md command + flags note | 8 |
| No `TextEngineCore` / `Package.swift` / CI change | All (constraint) |
| Verification record anchored on post-merge push | 9 |

---

**Plan complete and saved to `docs/superpowers/plans/2026-06-20-dynamic-line-insert-delete.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
