# Compute-Native Prefix Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ViewportVirtualizer.compute` over a balanced-tree provider fully O(log N) per call by routing its visible-start search through the Slice 29 `lineIndex(containingOffset:)` hook and adding a second native end-exclusive primitive `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`.

**Architecture:** A second defaulted `LineMetricsSource` requirement (declared in the protocol body for witness-table dispatch) backed by a shared binary-search helper, overridden by a `BalancedTreeLineMetrics` subtree-sum descent. `compute`'s two private edge-guard wrappers delegate to the dispatched hooks; the visible-end wrapper forwards the existing `lowerBound` (= visible start) narrowing as a correctness-preserving hint so fallback O(log N) providers keep their probe count.

**Tech Stack:** Swift 6.0, SwiftPM, XCTest. Foundation-free core. Reference providers in `TextEngineReferenceProviders`.

**Spec:** `docs/superpowers/specs/2026-06-27-compute-native-prefix-search-design.md`

## Global Constraints

Copied from the spec; every task implicitly includes these:

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty. Same for `Sources/TextEngineReferenceProviders`.
- **Swift Embedded compatible / zero-dependency / compiles for iOS and WASM with no source changes.** No runtime casts, no allocation in the native search.
- **O(1) core memory.** The native descent is iterative (no recursion stack) and allocates nothing; it does not touch `lastMutationNodeVisits`.
- **No new or changed public query API**, `ViewportComputation`/`VirtualRange`/`ViewportError` shape. The only public-API change is the second defaulted `LineMetricsSource` requirement.
- **Preserve the `lowerBound` narrowing** as a hint on the new primitive (do not drop it): fallback providers (`Uniform`/`PrefixSum`/`Fenwick`) must keep their exact current probe count.
- **No new benchmark mode and no new blocking gate.** No budget retuning.
- **TDD, one logical step per commit**, conventional-commit prefixes (`test:`, `feat:`, `docs:`).

## File Structure

- Modify: `Sources/TextEngineCore/LineMetricsSource.swift` — add the protocol requirement, its default, and the shared `firstLineIndexAtOrAbove` helper (Task 1).
- Modify: `Sources/TextEngineCore/VariableViewportVirtualizer.swift` — route the two `compute` edge-guard wrappers through the dispatched hooks (Task 2).
- Modify: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift` — native end-exclusive descent override (Task 3).
- Create: `Tests/TextEngineCoreTests/ComputeNativePrefixSearchTests.swift` — default-fallback, hint-narrowing, and compute-dispatch tests (Tasks 1, 2).
- Modify: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift` — native oracle, after-mutations, visit-count, and compute scroll-sweep equivalence (Tasks 3, 4).
- Modify: `AGENTS.md` — architecture paragraph (Task 5).
- Create: `docs/superpowers/verification/2026-06-27-compute-native-prefix-search.md` — verification record (Task 6).

---

### Task 1: End-exclusive primitive + default fallback (core)

**Files:**
- Modify: `Sources/TextEngineCore/LineMetricsSource.swift`
- Test: `Tests/TextEngineCoreTests/ComputeNativePrefixSearchTests.swift` (create)

**Interfaces:**
- Produces: `LineMetricsSource.firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int` (protocol requirement, defaulted). Default returns the smallest `i` in `lowerBound...lineCount` with `offset(ofLine: i) >= y`.
- Produces: `func firstLineIndexAtOrAbove<Metrics: LineMetricsSource>(offset target: Double, metrics: Metrics, lowerBound: Int, lineCount: Int) -> Int` (internal free helper).

- [ ] **Step 1: Write the failing tests**

Create `Tests/TextEngineCoreTests/ComputeNativePrefixSearchTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ComputeNativePrefixSearchTests: XCTestCase {
    private final class QueryCounter {
        var count = 0
    }

    private struct CountingLineMetrics: LineMetricsSource {
        let base: UniformLineMetrics
        let counter: QueryCounter

        init(lineCount: Int, lineHeight: Double, counter: QueryCounter) {
            self.base = UniformLineMetrics(lineCount: lineCount, lineHeight: lineHeight)
            self.counter = counter
        }

        var lineCount: Int { base.lineCount }

        func offset(ofLine index: Int) -> Double {
            counter.count += 1
            return base.offset(ofLine: index)
        }
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

    func testDefaultFirstLineIndexAtOrAboveReturnsSmallestIndexAtOrAbove() {
        let metrics = CountingLineMetrics(lineCount: 5, lineHeight: 10.0, counter: QueryCounter())
        // offsets: 0,10,20,30,40,50
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 20.0, startingAtLine: 0), 2) // exact top -> that line
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 21.0, startingAtLine: 0), 3) // interior -> next line
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 0.0, startingAtLine: 0), 0)
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 45.0, startingAtLine: 0), 5) // last interior -> lineCount
    }

    func testDefaultFirstLineIndexAtOrAboveUsesLogarithmicFallback() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)

        let index = metrics.firstLineIndex(
            withOffsetAtOrAbove: Double(lineCount / 2) * 16.0 + 8.0,
            startingAtLine: 0
        )

        XCTAssertEqual(index, lineCount / 2 + 1)
        XCTAssertLessThanOrEqual(counter.count, ceilLog2(lineCount) + 1)
        XCTAssertLessThan(counter.count, 100)
    }

    func testFirstLineIndexAtOrAboveHintNarrowsSearch() {
        let lineCount = 1_000_000
        let target = Double(lineCount - 2) * 16.0 // deep scroll: answer near the end

        let wide = QueryCounter()
        let wideMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: wide)
        let wideIndex = wideMetrics.firstLineIndex(withOffsetAtOrAbove: target, startingAtLine: 0)

        let narrow = QueryCounter()
        let narrowMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: narrow)
        let narrowIndex = narrowMetrics.firstLineIndex(withOffsetAtOrAbove: target, startingAtLine: lineCount - 4)

        XCTAssertEqual(wideIndex, lineCount - 2)
        XCTAssertEqual(narrowIndex, lineCount - 2)
        // Same answer, but the hint must strictly reduce the probe count at deep scroll.
        XCTAssertLessThan(narrow.count, wide.count)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ComputeNativePrefixSearchTests`
Expected: FAIL — compile error, `value of type '...' has no member 'firstLineIndex'`.

- [ ] **Step 3: Add the requirement, default, and helper**

In `Sources/TextEngineCore/LineMetricsSource.swift`, add the requirement to the protocol body immediately after the `lineIndex(containingOffset:)` requirement (before the closing `}` of the protocol):

```swift
    /// Returns the smallest line index `i` in `lowerBound...lineCount` with
    /// `offset(ofLine: i) >= y` - the first line whose top is at or above `y`
    /// (end-exclusive). The inverse-direction companion to
    /// `lineIndex(containingOffset:)`, used by `compute` for the visible-end edge.
    ///
    /// `lowerBound` is a correctness-preserving optimization hint: the true
    /// answer is provably `>= lowerBound`, so an override may ignore it and still
    /// return the same index. Fallback providers use it to narrow the search.
    ///
    /// Preconditions: `lineCount > 0`; `offset(ofLine: 0) == 0`; `y` is finite and
    /// in `[0, offset(ofLine: lineCount))`; `0 <= lowerBound <= lineCount` with
    /// `offset(ofLine: lowerBound) <= y`, for the same stable metrics snapshot.
    /// This primitive does not validate or clamp; public query semantics stay
    /// centralized in `ViewportVirtualizer.compute`.
    func firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int
```

Add the default to the existing `extension LineMetricsSource { ... }` (next to the `lineIndex` default):

```swift
    public func firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int {
        firstLineIndexAtOrAbove(offset: y, metrics: self, lowerBound: lowerBound, lineCount: lineCount)
    }
```

Add the shared free helper immediately after `binarySearchLineIndex`:

```swift
// Smallest i in lowerBound...lineCount with offset(ofLine: i) >= target (the
// first line whose top is at or above target, end-exclusive). Narrowed by
// lowerBound; the answer is provably >= lowerBound. Shared by the default
// firstLineIndex hook so the fallback path has a single >= boundary convention.
func firstLineIndexAtOrAbove<Metrics: LineMetricsSource>(
    offset target: Double,
    metrics: Metrics,
    lowerBound: Int,
    lineCount: Int
) -> Int {
    var low = lowerBound
    var high = lineCount - 1
    var result = lineCount
    while low <= high {
        let mid = low + (high - low) / 2
        if metrics.offset(ofLine: mid) >= target {
            result = mid
            high = mid - 1
        } else {
            low = mid + 1
        }
    }
    return result
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ComputeNativePrefixSearchTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify the full suite still builds and passes**

Run: `swift test`
Expected: PASS, 130 + 3 = 133 tests, 0 failures (plus the empty Swift Testing line).

- [ ] **Step 6: Commit**

```bash
git add Sources/TextEngineCore/LineMetricsSource.swift Tests/TextEngineCoreTests/ComputeNativePrefixSearchTests.swift
git commit -m "feat: add end-exclusive line-index prefix-search hook"
```

---

### Task 2: Route `compute` through the dispatched hooks (core)

**Files:**
- Modify: `Sources/TextEngineCore/VariableViewportVirtualizer.swift`
- Test: `Tests/TextEngineCoreTests/ComputeNativePrefixSearchTests.swift`

**Interfaces:**
- Consumes: `LineMetricsSource.lineIndex(containingOffset:)` (Slice 29) and `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` (Task 1).
- Produces: `compute`'s visible-start dispatches through `lineIndex(containingOffset:)`; visible-end dispatches through `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`, forwarding `lowerBound = visibleStart`. No signature change to `compute`.

- [ ] **Step 1: Write the failing dispatch test**

Append to `Tests/TextEngineCoreTests/ComputeNativePrefixSearchTests.swift` (inside the class):

```swift
    private enum ComputeSearchEvent: Equatable {
        case offset(Int)
        case lineIndex(Double)
        case firstAtOrAbove(Double, Int)
    }

    private final class ComputeSearchRecorder {
        var events: [ComputeSearchEvent] = []
    }

    // Spy that overrides BOTH native hooks so a dispatched compute never falls
    // back to offset-based binary search. offset() is therefore called only for
    // the two O(1) contract probes.
    private struct SpyMetrics: LineMetricsSource {
        let offsets: [Double] // length lineCount + 1
        let recorder: ComputeSearchRecorder

        var lineCount: Int { offsets.count - 1 }

        func offset(ofLine index: Int) -> Double {
            recorder.events.append(.offset(index))
            return offsets[index]
        }

        func lineIndex(containingOffset y: Double) -> Int {
            recorder.events.append(.lineIndex(y))
            var result = 0
            for i in 0..<(offsets.count - 1) {
                if offsets[i] <= y { result = i } else { break }
            }
            return result
        }

        func firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int {
            recorder.events.append(.firstAtOrAbove(y, lowerBound))
            var result = offsets.count - 1
            for i in lowerBound..<offsets.count {
                if offsets[i] >= y { result = i; break }
            }
            return result
        }
    }

    func testComputeDispatchesBothBoundarySearchesToNativeHooks() {
        let recorder = ComputeSearchRecorder()
        // 4 lines, tops at 0,10,30,35, total height 80.
        let metrics = SpyMetrics(offsets: [0.0, 10.0, 30.0, 35.0, 80.0], recorder: recorder)
        let input = VariableViewportInput(
            scrollOffsetY: 12.0,
            viewportHeight: 20.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        guard case .success = ViewportVirtualizer.compute(input, metrics: metrics) else {
            return XCTFail("expected success")
        }

        // effectiveOffsetY = 12 (< maxOffset 60). visible-start = lineIndex(12) = 1,
        // so visible-end = firstAtOrAbove(32, lowerBound: 1). offset() only for the
        // two contract probes (0 and lineCount=4).
        XCTAssertEqual(recorder.events, [
            .offset(0),
            .offset(4),
            .lineIndex(12.0),
            .firstAtOrAbove(32.0, 1)
        ])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ComputeNativePrefixSearchTests/testComputeDispatchesBothBoundarySearchesToNativeHooks`
Expected: FAIL — current `compute` uses `binarySearchLineIndex` (visible-start) and an inline offset loop (visible-end), so `recorder.events` contains extra `.offset(...)` probes and no `.lineIndex`/`.firstAtOrAbove` events.

- [ ] **Step 3: Route both wrappers through the hooks**

In `Sources/TextEngineCore/VariableViewportVirtualizer.swift`, change `firstLineTopAtOrBelow`'s in-range branch from the direct helper call to the dispatched hook:

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
        return metrics.lineIndex(containingOffset: target)
    }
```

Replace `firstLineTopAtOrAbove`'s inline binary search with a dispatch to the new hook, keeping the `lowerBound` parameter and the edge guard:

```swift
    private static func firstLineTopAtOrAbove<Metrics: LineMetricsSource>(
        _ target: Double,
        metrics: Metrics,
        lineCount: Int,
        totalHeight: Double,
        lowerBound: Int
    ) -> Int {
        if target >= totalHeight {
            return lineCount
        }
        return metrics.firstLineIndex(withOffsetAtOrAbove: target, startingAtLine: lowerBound)
    }
```

(The `compute` body itself is unchanged: it still calls `firstLineTopAtOrBelow(effectiveOffsetY, ...)` and `firstLineTopAtOrAbove(effectiveOffsetY + viewportHeight, ..., lowerBound: visibleStart)`.)

- [ ] **Step 4: Run the dispatch test and the existing compute query-count tests**

Run: `swift test --filter ComputeNativePrefixSearchTests`
Expected: PASS.

Run: `swift test --filter VariableHeightQueryCountTests`
Expected: PASS — fallback providers still do `2 + (ceilLog2(n) + 1) * 2` offset probes at most (visible-end is now narrowed, so the count is `<=` the old bound, which the existing `XCTAssertLessThanOrEqual` accepts).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextEngineCore/VariableViewportVirtualizer.swift Tests/TextEngineCoreTests/ComputeNativePrefixSearchTests.swift
git commit -m "feat: route compute searches through provider hooks"
```

---

### Task 3: Balanced-tree native end-exclusive descent (provider)

**Files:**
- Modify: `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- Test: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Produces: `BalancedTreeLineMetrics.firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` (public override, ignores the hint).
- Produces: `BalancedTreeLineMetrics.firstLineIndexAndVisitCount(withOffsetAtOrAbove y: Double) -> (lineIndex: Int, visits: Int)` (internal, test-only).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift` (inside the class; the helpers `sampleHeights`, `sampledSearchOffsets`, `floorLog2` already exist):

```swift
    // Independent oracle for "first line top at or above y": a linear scan over
    // the prefix-sum offsets, NOT the production binary search.
    private func bruteFirstAtOrAbove(_ oracle: PrefixSumLineMetrics, _ y: Double) -> Int {
        for i in 0...oracle.lineCount where oracle.offset(ofLine: i) >= y {
            return i
        }
        return oracle.lineCount
    }

    private func assertNativeAtOrAboveMatchesOracle(
        _ tree: BalancedTreeLineMetrics,
        _ array: [Double],
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let oracle = PrefixSumLineMetrics(heights: array)
        for y in sampledSearchOffsets(oracle) {
            let expected = bruteFirstAtOrAbove(oracle, y)
            XCTAssertEqual(
                tree.firstLineIndex(withOffsetAtOrAbove: y, startingAtLine: 0),
                expected,
                "firstLineIndex y=\(y) \(message())",
                file: file, line: line
            )
            XCTAssertEqual(
                tree.firstLineIndexAndVisitCount(withOffsetAtOrAbove: y).lineIndex,
                expected,
                "firstLineIndexAndVisitCount y=\(y) \(message())",
                file: file, line: line
            )
        }
    }

    func testNativeFirstLineIndexAtOrAboveMatchesOracleAtBoundaries() {
        let heights = sampleHeights(1_000)
        let tree = BalancedTreeLineMetrics(heights: heights)
        assertNativeAtOrAboveMatchesOracle(tree, heights, "initial build")
    }

    func testNativeFirstLineIndexAtOrAboveIgnoresHintButHonorsIt() {
        let heights = sampleHeights(500)
        let tree = BalancedTreeLineMetrics(heights: heights)
        let oracle = PrefixSumLineMetrics(heights: heights)
        // For a y whose answer is index a, any lowerBound <= a returns the same a.
        let y = oracle.offset(ofLine: 300) + 1.0 // interior of line 300 -> answer 301
        XCTAssertEqual(tree.firstLineIndex(withOffsetAtOrAbove: y, startingAtLine: 0), 301)
        XCTAssertEqual(tree.firstLineIndex(withOffsetAtOrAbove: y, startingAtLine: 301), 301)
        XCTAssertEqual(tree.firstLineIndex(withOffsetAtOrAbove: y, startingAtLine: 200), 301)
    }

    func testNativeFirstLineIndexAtOrAboveMatchesOracleAfterMutations() {
        var array = sampleHeights(120)
        var tree = BalancedTreeLineMetrics(heights: array)

        tree.setHeight(ofLine: 0, to: 40.0); array[0] = 40.0
        assertNativeAtOrAboveMatchesOracle(tree, array, "after setHeight first")

        tree.insertLine(at: 10, height: 19.0); array.insert(19.0, at: 10)
        assertNativeAtOrAboveMatchesOracle(tree, array, "after insertLine")

        tree.removeLine(at: 3); array.remove(at: 3)
        assertNativeAtOrAboveMatchesOracle(tree, array, "after removeLine")

        let inserted = [17.0, 29.0, 31.0, 37.0]
        tree.insertLines(at: 20, heights: inserted); array.insert(contentsOf: inserted, at: 20)
        assertNativeAtOrAboveMatchesOracle(tree, array, "after insertLines")

        tree.removeLines(at: 5, count: 4); array.removeSubrange(5..<9)
        assertNativeAtOrAboveMatchesOracle(tree, array, "after removeLines")
    }

    func testNativeFirstLineIndexAtOrAboveVisitCountIsLogarithmic() {
        for n in [1_000, 100_000, 1_000_000] {
            let heights = sampleHeights(n)
            let tree = BalancedTreeLineMetrics(heights: heights)
            let oracle = PrefixSumLineMetrics(heights: heights)
            let samples = [
                0.0,
                oracle.offset(ofLine: n / 2) + 1.0,
                oracle.offset(ofLine: n).nextDown
            ]
            for y in samples {
                let measured = tree.firstLineIndexAndVisitCount(withOffsetAtOrAbove: y)
                XCTAssertEqual(measured.lineIndex, bruteFirstAtOrAbove(oracle, y), "n=\(n) y=\(y)")
                XCTAssertLessThanOrEqual(measured.visits, 4 * (floorLog2(n) + 1), "n=\(n) y=\(y)")
                XCTAssertGreaterThan(measured.visits, 0, "n=\(n) y=\(y)")
            }
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BalancedTreeLineMetricsTests/testNativeFirstLineIndexAtOrAboveVisitCountIsLogarithmic`
Expected: FAIL — compile error, `BalancedTreeLineMetrics` has no member `firstLineIndexAndVisitCount`. (The public-method tests would otherwise pass on the inherited default; the internal-method reference forces RED and the visit-count proves the native descent is wired.)

- [ ] **Step 3: Implement the native override**

In `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`, add immediately after `lineIndexAndVisitCount(containingOffset:)` (around line 102):

```swift
    public func firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int {
        // The hint is ignored: this descent already returns the global smallest
        // index with offset >= y, which is provably >= lowerBound.
        firstLineIndexAndVisitCount(withOffsetAtOrAbove: y).lineIndex
    }

    internal func firstLineIndexAndVisitCount(withOffsetAtOrAbove y: Double) -> (lineIndex: Int, visits: Int) {
        precondition(root != -1, "BalancedTreeLineMetrics.firstLineIndex requires a non-empty tree")

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
                if remaining == 0 {
                    return (baseIndex + leftCount, visits)       // y exactly on this line's top
                }
                return (baseIndex + leftCount + 1, visits)       // y strictly inside -> next line's top
            }

            remaining -= node.height
            baseIndex += leftCount + 1
            current = node.right
        }

        preconditionFailure("BalancedTreeLineMetrics.firstLineIndex search exhausted")
    }
```

- [ ] **Step 4: Run the new tests**

Run: `swift test --filter BalancedTreeLineMetricsTests`
Expected: PASS (all existing + 4 new).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "feat: add balanced-tree end-exclusive native descent"
```

---

### Task 4: Compute scroll-sweep equivalence oracle (provider)

**Files:**
- Test: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.compute`, `BalancedTreeLineMetrics`, `PrefixSumLineMetrics`.

This task adds the end-to-end proof that native `compute` (balanced tree, both searches native) equals fallback `compute` (prefix-sum oracle, both searches binary search) across a scroll sweep. Production code is complete after Task 3, so this test is expected to pass when written — it is the cross-provider equivalence guard for the slice.

- [ ] **Step 1: Write the equivalence sweep test**

Append to `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift` (inside the class):

```swift
    func testComputeOverBalancedTreeMatchesPrefixSumOracleAcrossScrollSweep() {
        let heights = sampleHeights(5_000)
        let tree = BalancedTreeLineMetrics(heights: heights)
        let oracle = PrefixSumLineMetrics(heights: heights)
        let total = oracle.offset(ofLine: oracle.lineCount)

        // Scroll offsets: negative, exact line tops, interiors, fractional,
        // top, near-bottom, exactly bottom, and past bottom.
        var scrollOffsets: [Double] = [-50.0, 0.0, 1.5, total, total + 100.0]
        for line in [1, 2, 499, 2_500, 4_998, 4_999] {
            let top = oracle.offset(ofLine: line)
            scrollOffsets.append(top)
            scrollOffsets.append(top + 0.5)
            scrollOffsets.append(top.nextDown)
        }

        let viewportHeights: [Double] = [0.0, 16.0, 80.0 * 16.0, total + 10.0]
        let overscans: [(Int, Int)] = [(0, 0), (5, 5), (3, 9)]

        for scroll in scrollOffsets {
            for viewportHeight in viewportHeights {
                for (before, after) in overscans {
                    let input = VariableViewportInput(
                        scrollOffsetY: scroll,
                        viewportHeight: viewportHeight,
                        overscanLinesBefore: before,
                        overscanLinesAfter: after
                    )
                    let treeRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: tree))
                    let oracleRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: oracle))
                    XCTAssertEqual(
                        treeRange, oracleRange,
                        "scroll=\(scroll) vh=\(viewportHeight) overscan=(\(before),\(after))"
                    )
                }
            }
        }
    }
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter BalancedTreeLineMetricsTests/testComputeOverBalancedTreeMatchesPrefixSumOracleAcrossScrollSweep`
Expected: PASS — `VirtualRange` (including `isAtTop`/`isAtBottom`) is byte-equal between the native and fallback compute paths across the sweep.

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: PASS, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "test: prove balanced-tree compute equals prefix-sum oracle"
```

---

### Task 5: Update durable docs

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Update the architecture paragraph**

In `AGENTS.md`, the architecture paragraph currently describes variable `compute` as "O(log N) queries / O(1) core memory (binary search over offsets)". Update it so `compute`'s visible-start and visible-end searches are described as using the provider-native prefix-search hooks when available (balanced-tree O(log N) per call) and the generic binary-search fallback otherwise. Concretely, change the sentence:

> Variable compute is **O(log N)** queries / **O(1)** core memory (binary search over offsets); the geometry cursors stream per-line `LineGeometry` over the buffer range in O(buffer).

to:

> Variable compute is **O(log N)** queries / **O(1)** core memory: its visible-start and visible-end searches dispatch to the same provider-native prefix-search hooks `lineAt` uses (`lineIndex(containingOffset:)` and `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`), so a balanced-tree provider answers each in one O(log N) descent and other providers use the generic binary-search fallback over offsets; the geometry cursors stream per-line `LineGeometry` over the buffer range in O(buffer).

(Also extend the existing `lineAt` sentence's "provider-native prefix-search hook" wording if it reads as `lineAt`-only, so it's clear both vertical queries share the hooks. Keep edits to the architecture paragraph; do not restate code.)

- [ ] **Step 2: Verify no Foundation crept in and docs render**

Run: `rg -n "Foundation" Sources/TextEngineCore Sources/TextEngineReferenceProviders`
Expected: no matches (exit 1).

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document compute provider-native prefix search"
```

---

### Task 6: Full verification sweep and record

**Files:**
- Create: `docs/superpowers/verification/2026-06-27-compute-native-prefix-search.md`

- [ ] **Step 1: Run the full local verification sweep**

Run each and capture output verbatim:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift run -c release ViewportBenchmarks -- --line-query --gate
swift run -c release ViewportBenchmarks -- --memory-shape
rg -n "Foundation" Sources/TextEngineCore
rg -n "Foundation" Sources/TextEngineReferenceProviders
./.github/scripts/cross-target-compile.sh --self-test
./.github/scripts/cross-target-compile.sh
```

Expected: `swift test` 0 failures; every `--gate` prints `gate=pass`; structural / bulk-structural / line-query checksums byte-identical to the pre-change baseline (the native search returns the same indices); both Foundation scans empty (exit 1); cross-target self-test passes; cross-target compile passes for iOS (blocking) and records WASM (observational, or a precise local blocker if no matching SDK).

- [ ] **Step 2: Capture the one-off compute timing observation**

The `--structural-mutation --gate` / `--bulk-structural-mutation --gate` runs drive `compute` over a balanced tree. Record their p95/p99 before (pre-Task-2 `main`, i.e. `git stash`-free baseline from the merge-base) vs after, as an observation of the compute speedup. If a cleaner isolated number is wanted, note it as a manual one-off; do NOT add a benchmark mode.

- [ ] **Step 3: Write the verification record**

Create `docs/superpowers/verification/2026-06-27-compute-native-prefix-search.md` with the recorded commands, outputs, checksums, the before/after timing observation, and (after PR/merge) hosted run IDs at step-log level. Follow the format of `docs/superpowers/verification/2026-06-26-provider-native-prefix-search.md`.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/verification/2026-06-27-compute-native-prefix-search.md
git commit -m "docs: record compute-native prefix search verification"
```

---

## Self-Review

**Spec coverage:**
- Decision 1 (route visible-start through `lineIndex`) → Task 2.
- Decision 2 (defaulted end-exclusive requirement, protocol body, `lowerBound` hint) → Task 1.
- Decision 3 (shared `firstLineIndexAtOrAbove` helper; `lowerBound` preserved) → Task 1.
- Decision 4 (balanced-tree native descent, ignores hint, `remaining == 0` boundary, internal visit-count variant) → Task 3.
- Decision 5 (reuse gates; compute-equivalence oracle; one-off timing; fallback gates green) → Tasks 4, 6.
- Decision 6 (keep edge-guard wrappers; visible-end forwards `lowerBound`) → Task 2.
- Testing Strategy (default fallback, dispatch, equivalence oracle, native boundary/mutation/visit-count) → Tasks 1, 2, 3, 4.
- Docs (`AGENTS.md`) → Task 5. Verification sweep incl. `--variable-height-mutation --gate` → Task 6.

Note: the spec lists the compute-equivalence oracle under "Core Tests", but `TextEngineCoreTests` cannot import the reference providers; it is placed in `TextEngineReferenceProvidersTests` (Task 4). Core gets the default-fallback and dispatch tests (Tasks 1, 2).

**Placeholder scan:** none — every code/test step has complete code and exact commands.

**Type consistency:** `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` (public, both default and override), `firstLineIndexAtOrAbove(offset:metrics:lowerBound:lineCount:)` (free helper), `firstLineIndexAndVisitCount(withOffsetAtOrAbove:)` (internal, returns `(lineIndex:visits:)`) are used consistently across Tasks 1, 2, 3, 4.
