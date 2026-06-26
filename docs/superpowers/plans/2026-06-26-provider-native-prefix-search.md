# Provider-Native Prefix Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize `ViewportVirtualizer.lineAt(y:metrics:)` for `BalancedTreeLineMetrics` by routing in-range y-to-line lookup through a defaulted provider-native prefix-search hook while preserving the public query semantics.

**Architecture:** `LineMetricsSource` gains a defaulted lower-level `lineIndex(containingOffset:)` requirement. `ViewportVirtualizer.lineAt` keeps validation and clamp ownership, then calls that hook only after it has proven the documented in-range preconditions. `BalancedTreeLineMetrics` overrides the hook with one iterative descent over `subtreeHeightSum`/`subtreeCount`; non-native providers keep the shared binary-search fallback.

**Tech Stack:** Swift 6.0 package, `TextEngineCore`, `TextEngineReferenceProviders`, XCTest, `ViewportBenchmarks`, existing GitHub Swift CI gates.

---

## File Structure

- Modify: `Sources/TextEngineCore/LineMetricsSource.swift`
  - Add the defaulted `lineIndex(containingOffset:)` protocol requirement.
  - Add one internal binary-search helper shared by the default hook and `firstLineTopAtOrBelow`.
- Modify: `Sources/TextEngineCore/VariableViewportVirtualizer.swift`
  - Keep `compute` behavior unchanged.
  - Make `firstLineTopAtOrBelow` delegate to the shared fallback helper after its existing `target >= totalHeight` guard.
- Modify: `Sources/TextEngineCore/PositionQuery.swift`
  - Keep the Slice 27 validation/clamp ladder unchanged.
  - Replace the in-range `firstLineTopAtOrBelow` call with `metrics.lineIndex(containingOffset: y)`.
  - Refresh the doc comment so it no longer says every provider uses one generic binary search.
- Modify: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
  - Override `lineIndex(containingOffset:)`.
  - Add an internal `lineIndexAndVisitCount(containingOffset:)` helper for white-box tests via `@testable import`, not public API.
- Modify: `Tests/TextEngineCoreTests/LineAtQueryCountTests.swift`
  - Add core fallback and native-dispatch tests.
- Modify: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`
  - Add oracle tests for direct native search, public `lineAt`, post-mutation search, and logarithmic visit count.
- Modify: `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`
  - Refresh comments only. Do not change scenarios or budgets in this slice.
- Modify: `AGENTS.md`
  - Update the architecture paragraph to mention the provider-native hook plus fallback.
- Modify: `docs/superpowers/specs/2026-06-20-bulk-structural-edits-design.md`
  - Add the carried `join2`/`join3` naming cross-reference.
- Create: `docs/superpowers/verification/2026-06-26-provider-native-prefix-search.md`
  - Record local command output, line-query before/after checksum rows, cross-target evidence or precise local blocker, and hosted run IDs when available.

## Constraints

- Keep `Sources/TextEngineCore` Foundation-free.
- Do not add dependencies.
- Do not add a new public `LineQuery` shape or consumer-facing provider-specific query.
- Do not optimize `ViewportVirtualizer.compute` beyond sharing the fallback helper with its existing start-line search.
- Do not retune or tighten `--line-query --gate` budgets.
- Do not change `PrefixSumLineMetrics` or `UniformLineMetrics` behavior beyond inheriting the default hook.

---

### Task 0: Capture Pre-Change Line-Query Baseline

**Files:**
- Read: `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`
- Output only: `/tmp/slice29-line-query-before.txt`

- [ ] **Step 1: Run the existing line-query gate before code changes**

Run:

```bash
swift run -c release ViewportBenchmarks -- --line-query --gate | tee /tmp/slice29-line-query-before.txt
```

Expected: command exits `0`; every emitted `mode=line_query` row has `gate=pass`.
Keep the `checksum=` values for `balanced_tree_100k` and `balanced_tree_1m`; Task 6 records them beside the after-change rows.

- [ ] **Step 2: Do not commit baseline output**

Run:

```bash
git status --short
```

Expected: no tracked file changes from this task.

---

### Task 1: Add Failing Core Tests For Hook Fallback And Native Dispatch

**Files:**
- Modify: `Tests/TextEngineCoreTests/LineAtQueryCountTests.swift`

- [ ] **Step 1: Add a native-hook counter helper inside `LineAtQueryCountTests`**

Insert this code after `CountingLineMetrics`:

```swift
    private final class NativeSearchCounter {
        var offsetIndexes: [Int] = []
        var nativeOffsets: [Double] = []
    }

    private struct NativeSearchMetrics: LineMetricsSource {
        let offsets: [Double]
        let counter: NativeSearchCounter

        init(offsets: [Double], counter: NativeSearchCounter) {
            self.offsets = offsets
            self.counter = counter
        }

        var lineCount: Int { offsets.count - 1 }

        func offset(ofLine index: Int) -> Double {
            counter.offsetIndexes.append(index)
            return offsets[index]
        }

        func lineIndex(containingOffset y: Double) -> Int {
            counter.nativeOffsets.append(y)
            var result = 0
            for index in 0..<(offsets.count - 1) {
                if offsets[index] <= y {
                    result = index
                } else {
                    break
                }
            }
            return result
        }
    }
```

- [ ] **Step 2: Add a failing default fallback test**

Append this test to `LineAtQueryCountTests`:

```swift
    func testDefaultLineIndexRequirementUsesLogarithmicFallback() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)

        let index = metrics.lineIndex(containingOffset: Double(lineCount / 2) * 16.0 + 8.0)

        XCTAssertEqual(index, lineCount / 2)
        let expectedMax = ceilLog2(lineCount) + 1
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }
```

Before Task 2, this is the expected red state: compile failure because `CountingLineMetrics` has no `lineIndex(containingOffset:)` member yet.

- [ ] **Step 3: Add a failing native-dispatch test for `lineAt`**

Append this test to `LineAtQueryCountTests`:

```swift
    func testLineAtDispatchesToNativeHookAfterValidationProbes() {
        let counter = NativeSearchCounter()
        let metrics = NativeSearchMetrics(
            offsets: [0.0, 10.0, 30.0, 35.0, 80.0],
            counter: counter
        )

        let result = ViewportVirtualizer.lineAt(y: 31.0, metrics: metrics)

        XCTAssertEqual(result, .line(LineLocation(lineIndex: 2, clamp: .inRange)))
        XCTAssertEqual(counter.offsetIndexes, [0, 4])
        XCTAssertEqual(counter.nativeOffsets, [31.0])
    }
```

After Task 2, this proves `lineAt` reaches the protocol requirement only after `offset(0)` and `offset(lineCount)` validation probes. Before Task 2, it fails because the current `lineAt` runs the generic binary search and records extra `offset` probes instead of one native hook call.

- [ ] **Step 4: Run the focused red test**

Run:

```bash
swift test --filter LineAtQueryCountTests
```

Expected before Task 2: compile failure containing:

```text
value of type 'LineAtQueryCountTests.CountingLineMetrics' has no member 'lineIndex'
```

Do not commit this failing state.

---

### Task 2: Add The Defaulted Core Requirement And Wire `lineAt`

**Files:**
- Modify: `Sources/TextEngineCore/LineMetricsSource.swift`
- Modify: `Sources/TextEngineCore/VariableViewportVirtualizer.swift`
- Modify: `Sources/TextEngineCore/PositionQuery.swift`
- Test: `Tests/TextEngineCoreTests/LineAtQueryCountTests.swift`

- [ ] **Step 1: Add the protocol requirement, default implementation, and shared fallback helper**

In `Sources/TextEngineCore/LineMetricsSource.swift`, replace the protocol block with this version and add the extension/helper before `UniformLineMetrics`:

```swift
public protocol LineMetricsSource {
    var lineCount: Int { get }

    /// Cumulative top offset (y) of line `index`, in layout units.
    ///
    /// Domain: `0...lineCount`. `offset(ofLine: 0) == 0` and
    /// `offset(ofLine: lineCount)` is the total document height.
    ///
    /// Contract precondition: for every `i` in `0..<lineCount`, both
    /// `offset(ofLine: i)` and `offset(ofLine: i + 1)` are finite and
    /// `offset(ofLine: i) < offset(ofLine: i + 1)` (every line has finite
    /// positive height, and `offset(ofLine: lineCount)` is part of the monotone
    /// chain). The core never queries outside `0...lineCount`.
    ///
    /// Stability precondition: `lineCount` and `offset(ofLine:)` must be stable
    /// for one layout/query operation - a `compute`, a `lineAt`, and any
    /// `VariableLineGeometryCursor` traversal derived from a range it produced -
    /// so the range, the located line, and the geometry come from one consistent
    /// snapshot.
    func offset(ofLine index: Int) -> Double

    /// Returns the line whose half-open vertical span contains `y`.
    ///
    /// Preconditions: `lineCount > 0`, `offset(ofLine: 0) == 0`, and `y` is
    /// finite and in `[0, offset(ofLine: lineCount))` for the same stable metrics
    /// snapshot. This primitive does not validate or clamp; public query
    /// semantics stay centralized in `ViewportVirtualizer.lineAt(y:metrics:)`.
    func lineIndex(containingOffset y: Double) -> Int
}

extension LineMetricsSource {
    public func lineIndex(containingOffset y: Double) -> Int {
        binarySearchLineIndex(containingOffset: y, metrics: self, lineCount: lineCount)
    }
}

func binarySearchLineIndex<Metrics: LineMetricsSource>(
    containingOffset target: Double,
    metrics: Metrics,
    lineCount: Int
) -> Int {
    var low = 0
    var high = lineCount - 1
    var result = 0
    while low <= high {
        let mid = low + (high - low) / 2
        if metrics.offset(ofLine: mid) <= target {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    return result
}
```

- [ ] **Step 2: Keep `compute` on the shared fallback helper**

In `Sources/TextEngineCore/VariableViewportVirtualizer.swift`, replace only the body of `firstLineTopAtOrBelow` with:

```swift
    static func firstLineTopAtOrBelow<Metrics: LineMetricsSource>(
        _ target: Double,
        metrics: Metrics,
        lineCount: Int,
        totalHeight: Double
    ) -> Int {
        if target >= totalHeight {
            return lineCount
        }
        return binarySearchLineIndex(
            containingOffset: target,
            metrics: metrics,
            lineCount: lineCount
        )
    }
```

Do not change `firstLineTopAtOrAbove`; Slice 29 does not optimize visible-end search.

- [ ] **Step 3: Route the in-range `lineAt` branch through the hook**

In `Sources/TextEngineCore/PositionQuery.swift`, replace:

```swift
        let index = firstLineTopAtOrBelow(
            y,
            metrics: metrics,
            lineCount: lineCount,
            totalHeight: totalHeight
        )
```

with:

```swift
        let index = metrics.lineIndex(containingOffset: y)
```

Leave the validation and clamp order above this line unchanged.

- [ ] **Step 4: Run the focused core tests**

Run:

```bash
swift test --filter LineAtQueryCountTests
```

Expected: all `LineAtQueryCountTests` pass. In particular, `testLineAtDispatchesToNativeHookAfterValidationProbes` must observe exactly `counter.offsetIndexes == [0, 4]`.

- [ ] **Step 5: Run adjacent lineAt core tests**

Run:

```bash
swift test --filter LineAtTests
swift test --filter LineAtEquivalenceTests
swift test --filter LineMetricsSourceTests
```

Expected: all commands exit `0`; no expected result changes in existing tests.

- [ ] **Step 6: Commit the core hook work**

Run:

```bash
git add Sources/TextEngineCore/LineMetricsSource.swift Sources/TextEngineCore/VariableViewportVirtualizer.swift Sources/TextEngineCore/PositionQuery.swift Tests/TextEngineCoreTests/LineAtQueryCountTests.swift
git commit -m "feat: add provider-native line index hook"
```

Expected: commit succeeds with only the listed files staged.

---

### Task 3: Add Failing Balanced-Tree Oracle And Visit-Count Tests

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

- [ ] **Step 1: Add native search assertion helpers**

Insert these helpers after `assertMatchesOracle`:

```swift
    private func sampledSearchOffsets(_ oracle: PrefixSumLineMetrics) -> [Double] {
        if oracle.lineCount == 0 {
            return []
        }

        let rawIndexes = [
            0,
            1,
            2,
            oracle.lineCount / 2,
            oracle.lineCount - 2,
            oracle.lineCount - 1
        ]
        let indexes = Set(rawIndexes.filter { $0 >= 0 && $0 < oracle.lineCount }).sorted()
        var samples: [Double] = []
        for index in indexes {
            let top = oracle.offset(ofLine: index)
            let bottom = oracle.offset(ofLine: index + 1)
            samples.append(top)
            samples.append((top + bottom) / 2.0)
            let beforeBoundary = bottom.nextDown
            if beforeBoundary > top {
                samples.append(beforeBoundary)
            }
        }
        return samples
    }

    private func assertNativeSearchMatchesOracle(
        _ tree: BalancedTreeLineMetrics,
        _ array: [Double],
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let oracle = PrefixSumLineMetrics(heights: array)
        for y in sampledSearchOffsets(oracle) {
            XCTAssertEqual(
                tree.lineIndex(containingOffset: y),
                oracle.lineIndex(containingOffset: y),
                "lineIndex y=\(y) \(message())",
                file: file,
                line: line
            )
            XCTAssertEqual(
                tree.lineIndexAndVisitCount(containingOffset: y).lineIndex,
                oracle.lineIndex(containingOffset: y),
                "lineIndexAndVisitCount y=\(y) \(message())",
                file: file,
                line: line
            )
        }
    }
```

Before Task 4, this is the expected red state: compile failure because `BalancedTreeLineMetrics` has no `lineIndexAndVisitCount(containingOffset:)` helper.

- [ ] **Step 2: Add direct native-search boundary coverage**

Append this test before the first mutation test:

```swift
    func testNativeLineIndexMatchesPrefixSumOracleAtBoundaries() {
        let heights = sampleHeights(1_000)
        let tree = BalancedTreeLineMetrics(heights: heights)

        assertNativeSearchMatchesOracle(tree, heights, "initial build")
    }
```

- [ ] **Step 3: Add public `lineAt` oracle coverage for in-range and clamped y**

Append this test after `testNativeLineIndexMatchesPrefixSumOracleAtBoundaries`:

```swift
    func testLineAtWithBalancedTreeMatchesPrefixSumOracle() {
        let heights = sampleHeights(1_000)
        let tree = BalancedTreeLineMetrics(heights: heights)
        let oracle = PrefixSumLineMetrics(heights: heights)
        var samples = sampledSearchOffsets(oracle)
        samples.append(-1.0)
        samples.append(oracle.offset(ofLine: oracle.lineCount))
        samples.append(oracle.offset(ofLine: oracle.lineCount) + 100.0)

        for y in samples {
            XCTAssertEqual(
                ViewportVirtualizer.lineAt(y: y, metrics: tree),
                ViewportVirtualizer.lineAt(y: y, metrics: oracle),
                "lineAt y=\(y)"
            )
        }
    }
```

- [ ] **Step 4: Add post-mutation native-search coverage**

Append this test after `testLineAtWithBalancedTreeMatchesPrefixSumOracle`:

```swift
    func testNativeLineIndexMatchesOracleAfterSingleAndBulkMutations() {
        var array = sampleHeights(120)
        var tree = BalancedTreeLineMetrics(heights: array)

        tree.setHeight(ofLine: 0, to: 40.0)
        array[0] = 40.0
        assertNativeSearchMatchesOracle(tree, array, "after setHeight first")

        tree.setHeight(ofLine: array.count - 1, to: 12.0)
        array[array.count - 1] = 12.0
        assertNativeSearchMatchesOracle(tree, array, "after setHeight last")

        tree.insertLine(at: 10, height: 19.0)
        array.insert(19.0, at: 10)
        assertNativeSearchMatchesOracle(tree, array, "after insertLine")

        tree.removeLine(at: 3)
        array.remove(at: 3)
        assertNativeSearchMatchesOracle(tree, array, "after removeLine")

        let inserted = [17.0, 29.0, 31.0, 37.0]
        tree.insertLines(at: 20, heights: inserted)
        array.insert(contentsOf: inserted, at: 20)
        assertNativeSearchMatchesOracle(tree, array, "after insertLines")

        tree.removeLines(at: 5, count: 4)
        array.removeSubrange(5..<9)
        assertNativeSearchMatchesOracle(tree, array, "after removeLines")
    }
```

- [ ] **Step 5: Add logarithmic native-descent proof**

Append this test near the existing visit-count tests:

```swift
    func testNativeLineIndexVisitCountIsLogarithmic() {
        for n in [1_000, 100_000, 1_000_000] {
            let heights = sampleHeights(n)
            let tree = BalancedTreeLineMetrics(heights: heights)
            let oracle = PrefixSumLineMetrics(heights: heights)
            let samples = [
                0.0,
                oracle.offset(ofLine: n / 2),
                oracle.offset(ofLine: n).nextDown
            ]

            for y in samples {
                let measured = tree.lineIndexAndVisitCount(containingOffset: y)
                XCTAssertEqual(measured.lineIndex, oracle.lineIndex(containingOffset: y), "n=\(n) y=\(y)")
                XCTAssertLessThanOrEqual(measured.visits, 4 * (floorLog2(n) + 1), "n=\(n) y=\(y)")
                XCTAssertGreaterThan(measured.visits, 0, "n=\(n) y=\(y)")
            }
        }
    }
```

- [ ] **Step 6: Run the focused red test**

Run:

```bash
swift test --filter BalancedTreeLineMetricsTests/testNativeLineIndexMatchesPrefixSumOracleAtBoundaries
```

Expected before Task 4: compile failure containing:

```text
value of type 'BalancedTreeLineMetrics' has no member 'lineIndexAndVisitCount'
```

Do not commit this failing state.

---

### Task 4: Implement Balanced-Tree Native Prefix Search

**Files:**
- Modify: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- Test: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

- [ ] **Step 1: Add the public override and internal visit-count helper**

In `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`, insert this block after `offset(ofLine:)` and before `// MARK: - Height mutation`:

```swift
    public func lineIndex(containingOffset y: Double) -> Int {
        lineIndexAndVisitCount(containingOffset: y).lineIndex
    }

    internal func lineIndexAndVisitCount(containingOffset y: Double) -> (lineIndex: Int, visits: Int) {
        precondition(root != -1, "BalancedTreeLineMetrics.lineIndex requires a non-empty tree")

        var current = root
        var baseIndex = 0
        var remaining = y
        var visits = 0

        while current != -1 {
            visits += 1
            let node = nodes[current]
            let leftSum = nodeSum(node.left)
            if remaining < leftSum {
                current = node.left
                continue
            }

            remaining -= leftSum
            let leftCount = nodeCount(node.left)
            if remaining < node.height {
                return (baseIndex + leftCount, visits)
            }

            remaining -= node.height
            baseIndex += leftCount + 1
            current = node.right
        }

        preconditionFailure("BalancedTreeLineMetrics.lineIndex search exhausted")
    }
```

This must stay non-mutating and iterative. It may allocate no arrays and may not alter `lastMutationNodeVisits`.

- [ ] **Step 2: Run the focused reference-provider tests**

Run:

```bash
swift test --filter BalancedTreeLineMetricsTests/testNativeLineIndexMatchesPrefixSumOracleAtBoundaries
swift test --filter BalancedTreeLineMetricsTests/testLineAtWithBalancedTreeMatchesPrefixSumOracle
swift test --filter BalancedTreeLineMetricsTests/testNativeLineIndexMatchesOracleAfterSingleAndBulkMutations
swift test --filter BalancedTreeLineMetricsTests/testNativeLineIndexVisitCountIsLogarithmic
```

Expected: all commands exit `0`.

- [ ] **Step 3: Run the whole reference-provider test file**

Run:

```bash
swift test --filter BalancedTreeLineMetricsTests
```

Expected: all existing balanced-tree offset, mutation, re-layout, and new native-search tests pass.

- [ ] **Step 4: Run lineAt core tests again with the provider override present**

Run:

```bash
swift test --filter LineAtQueryCountTests
swift test --filter LineAtTests
swift test --filter LineAtEquivalenceTests
```

Expected: all commands exit `0`; uniform equivalence remains unchanged.

- [ ] **Step 5: Commit the balanced-tree override**

Run:

```bash
git add Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "feat: add balanced-tree native prefix search"
```

Expected: commit succeeds with only the listed files staged.

---

### Task 5: Update Durable Docs And Benchmark Comments

**Files:**
- Modify: `Sources/TextEngineCore/PositionQuery.swift`
- Modify: `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-06-20-bulk-structural-edits-design.md`

- [ ] **Step 1: Refresh the `PositionQuery.swift` complexity comment**

In `Sources/TextEngineCore/PositionQuery.swift`, replace the current comment paragraph:

```swift
    /// Stateless. O(log N) `offset(ofLine:)` queries (one binary search), O(1)
    /// core memory. A `y` outside `[0, totalHeight)` resolves to the nearest line
```

with:

```swift
    /// Stateless. The in-range branch calls
    /// `LineMetricsSource.lineIndex(containingOffset:)`: providers may override
    /// it with a native prefix search, while the default remains an O(log N)
    /// binary search over `offset(ofLine:)`. O(1) core memory. A `y` outside
    /// `[0, totalHeight)` resolves to the nearest line
```

- [ ] **Step 2: Refresh the line-query benchmark comment without retuning budgets**

In `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`, replace:

```swift
// Starter budgets (macOS-calibrated in Step 6). Uniform/PrefixSum offsets are
// O(1) -> O(log N) search; balanced-tree offsets are O(log N) -> O(log^2 N).
```

with:

```swift
// Budgets remain the hosted Slice 28 values. Uniform uses the default O(log N)
// fallback; balanced-tree scenarios exercise the native O(log N) provider
// descent through ViewportVirtualizer.lineAt(y:metrics:).
```

Do not change `p95BudgetNanoseconds`, `p99BudgetNanoseconds`, iterations, scenarios, or checksum logic.

- [ ] **Step 3: Update the `AGENTS.md` architecture paragraph**

In `AGENTS.md`, replace the two-line `lineAt` description that says:

```markdown
`ViewportVirtualizer.lineAt(y:metrics:)` is the inverse query - y -> line - over
the same `LineMetricsSource`, O(log N) queries / O(1) core memory, reusing the
same binary search; out-of-range `y` clamps with a `LineLocation.clamp` flag.
```

with:

```markdown
`ViewportVirtualizer.lineAt(y:metrics:)` is the inverse query - y -> line - over
the same `LineMetricsSource`, O(1) core memory, using a provider-native
prefix-search hook when available and the generic O(log N) binary-search
fallback otherwise; out-of-range `y` clamps with a `LineLocation.clamp` flag.
```

- [ ] **Step 4: Retire the carried `join2`/`join3` provider-doc P3**

In `docs/superpowers/specs/2026-06-20-bulk-structural-edits-design.md`, after the first paragraph that names `split(at:)`, `join(_:_:)`, and `detachMin(_:)`, insert:

```markdown
> Shipped naming note (Slice 29): the implementation names the weight-aware
> three-way join `join3` and the detach-min-derived two-way join `join2`; the
> earlier `join(_:_:)` wording refers to that shipped split.
```

Do not edit provider code in this docs task.

- [ ] **Step 5: Run docs/comment checks**

Run:

```bash
rg -n "Foundation" Sources/TextEngineCore
rg -n "Foundation" Sources/TextEngineReferenceProviders
swift test --filter LineAtQueryCountTests
swift test --filter BalancedTreeLineMetricsTests/testNativeLineIndexMatchesPrefixSumOracleAtBoundaries
```

Expected:

- Both `rg` commands produce no output and exit `1`.
- Both `swift test` commands exit `0`.

- [ ] **Step 6: Commit docs and comments**

Run:

```bash
git add Sources/TextEngineCore/PositionQuery.swift Sources/ViewportBenchmarks/LineQueryBenchmark.swift AGENTS.md docs/superpowers/specs/2026-06-20-bulk-structural-edits-design.md
git commit -m "docs: document provider-native line query path"
```

Expected: commit succeeds with only docs/comment files staged.

---

### Task 6: Run Full Verification And Record Evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-26-provider-native-prefix-search.md`

- [ ] **Step 1: Run the full local verification sweep**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --line-query --gate | tee /tmp/slice29-line-query-after.txt
swift run -c release ViewportBenchmarks -- --memory-shape
rg -n "Foundation" Sources/TextEngineCore
rg -n "Foundation" Sources/TextEngineReferenceProviders
./.github/scripts/cross-target-compile.sh --self-test
./.github/scripts/cross-target-compile.sh
```

Expected:

- `swift test` exits `0`.
- `swift build -c release` exits `0`.
- Synthetic `--gate` exits `0` and prints `gate=pass`.
- `--line-query --gate` exits `0`; every row prints `gate=pass`.
- `--memory-shape` prints `invariant=pass`.
- Both Foundation scans produce no output and exit `1`.
- `cross-target-compile.sh --self-test` exits `0`.
- Full cross-target compile exits `0`, or the verification record captures the exact local toolchain/SDK blocker and the command output.

- [ ] **Step 2: Compare line-query checksums before and after**

Run:

```bash
diff -u <(rg "balanced_tree_(100k|1m)" /tmp/slice29-line-query-before.txt) <(rg "balanced_tree_(100k|1m)" /tmp/slice29-line-query-after.txt)
```

Expected: `checksum=` values for `balanced_tree_100k` and `balanced_tree_1m` are unchanged. Timing fields may differ and should be recorded as observation only.

- [ ] **Step 3: Create the verification record**

Create `docs/superpowers/verification/2026-06-26-provider-native-prefix-search.md` after Step 1 and Step 2 have run. Use this exact section order:

```text
# Provider-Native Prefix Search Verification
Date: 2026-06-26
Branch: slice-29-provider-native-prefix-search
## Summary
## Local Commands
### swift test
### swift build -c release
### swift run -c release ViewportBenchmarks -- --gate
### swift run -c release ViewportBenchmarks -- --line-query --gate
### Line-query checksum comparison
### swift run -c release ViewportBenchmarks -- --memory-shape
### Foundation scans
### ./.github/scripts/cross-target-compile.sh --self-test
### ./.github/scripts/cross-target-compile.sh
## Hosted Evidence
```

Under `## Summary`, write these four bullets exactly if all Step 1/2 checks passed:

```markdown
- `ViewportVirtualizer.lineAt(y:metrics:)` keeps Slice 27 validation and clamp semantics.
- `LineMetricsSource.lineIndex(containingOffset:)` provides the default fallback hook.
- `BalancedTreeLineMetrics` overrides the hook with an iterative subtree-sum descent.
- `--line-query --gate` passes; balanced-tree checksums match the pre-change baseline.
```

Under each `###` local-command heading, paste a fenced terminal transcript that starts with the command line and continues with the real terminal output from this machine. The committed verification file must not contain ellipses or descriptive marker text. If the full cross-target compile cannot run locally, put the exact failing command, exit status, and blocker text under its heading.

Under `## Hosted Evidence`, write this exact text before a PR exists:

```markdown
- PR: not available until the slice branch is pushed.
- Host tests and benchmark gate: not available until the slice branch is pushed.
- iOS cross-target compile: not available until the slice branch is pushed.
- WASM cross-target observation: not available until the slice branch is pushed.
```

After a PR exists, replace those four lines with the PR number, head SHA, run IDs, job names, and conclusions.

- [ ] **Step 4: Run a markdown sanity check**

Run:

```bash
rg -n "T[B]D|T[O]DO|\\x3c[^\\x3e]+\\x3e|\\.\\.\\.|fill[ ]in[ ]details|implement[ ]later" docs/superpowers/verification/2026-06-26-provider-native-prefix-search.md
```

Expected before committing:

- No matches. If a PR already exists, also run `rg -n "not available until" docs/superpowers/verification/2026-06-26-provider-native-prefix-search.md`; expected no matches.

- [ ] **Step 5: Commit verification**

Run:

```bash
git add docs/superpowers/verification/2026-06-26-provider-native-prefix-search.md
git commit -m "docs: record provider-native prefix search verification"
```

Expected: commit succeeds with only the verification record staged.

---

## Final Pre-PR Check

- [ ] Run:

```bash
git status --short
git log --oneline --decorate -5
swift test
swift run -c release ViewportBenchmarks -- --line-query --gate
```

Expected:

- `git status --short` is clean.
- Recent commits follow the task sequence.
- Both commands exit `0`.
- The branch is ready to push as `slice-29-provider-native-prefix-search`.

## Self-Review

**Spec coverage:** Covered. Task 1 proves default hook and native dispatch from core. Task 2 adds the defaulted `LineMetricsSource` requirement, shares the fallback helper with `firstLineTopAtOrBelow`, and preserves `lineAt` validation/clamps. Task 3 adds structural oracle tests for `BalancedTreeLineMetrics`, including boundaries, clamped public `lineAt`, and post-mutation coverage. Task 4 implements the native subtree-sum descent. Task 5 updates durable docs and retires the carried `join2`/`join3` provider-doc P3. Task 6 runs and records the required verification sweep, including before/after line-query checksums.

**Marker scan:** Checked against the forbidden marker classes from the writing-plans skill. Task 6 requires real terminal transcripts before the verification artifact can be committed.

**Type consistency:** The hook name is consistently `lineIndex(containingOffset:)`. The balanced-tree test helper and implementation are consistently `lineIndexAndVisitCount(containingOffset:) -> (lineIndex: Int, visits: Int)`. The benchmark mode remains the existing `--line-query --gate`; no new mode or budget names are introduced.
