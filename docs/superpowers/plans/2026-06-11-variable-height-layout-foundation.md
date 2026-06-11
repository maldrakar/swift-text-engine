# Variable-Height Layout Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the static (query) half of variable-height layout — a stateless core that virtualizes and lays out documents whose lines have different heights, driven by a provider-supplied cumulative-offset query.

**Architecture:** A new `LineMetricsSource` protocol supplies `offset(ofLine:)` (cumulative top y). The core keeps zero per-line state: a new `ViewportVirtualizer.compute(_:metrics:)` overload binary-searches `offset(ofLine:)` to virtualize (O(log N), O(1) memory), and a `VariableLineGeometryCursor` emits per-line geometry over the buffer range. The fixed-height path is preserved unchanged; the two `compute` paths share an extracted `bufferedRange` helper. A reference `PrefixSumLineMetrics` plus a CI-failing benchmark gate (fails Swift CI on regression; actual merge-blocking stays repository-policy-blocked) live in the benchmark target.

**Tech Stack:** Swift 6.0 package (`swift-tools-version: 6.0`), XCTest (`@testable import TextEngineCore`), `ViewportBenchmarks` executable, GitHub Actions (`.github/workflows/swift-ci.yml`). Spec: `docs/superpowers/specs/2026-06-10-variable-height-layout-foundation-design.md`.

---

### Task 1: `LineMetricsSource` protocol and `UniformLineMetrics`

**Files:**
- Create: `Sources/TextEngineCore/LineMetricsSource.swift`
- Test: `Tests/TextEngineCoreTests/LineMetricsSourceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/TextEngineCoreTests/LineMetricsSourceTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class LineMetricsSourceTests: XCTestCase {
    func testUniformLineMetricsOffsetIsLinear() {
        let metrics = UniformLineMetrics(lineCount: 5, lineHeight: 16.0)

        XCTAssertEqual(metrics.lineCount, 5)
        XCTAssertEqual(metrics.offset(ofLine: 0), 0.0)
        XCTAssertEqual(metrics.offset(ofLine: 3), 48.0)
        XCTAssertEqual(metrics.offset(ofLine: 5), 80.0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LineMetricsSourceTests`
Expected: FAIL — `cannot find 'UniformLineMetrics' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/TextEngineCore/LineMetricsSource.swift`:

```swift
public protocol LineMetricsSource {
    var lineCount: Int { get }

    /// Cumulative top offset (y) of line `index`, in layout units.
    ///
    /// Domain: `0...lineCount`. `offset(ofLine: 0) == 0` and
    /// `offset(ofLine: lineCount)` is the total document height.
    ///
    /// Contract precondition: finite and strictly increasing on `0..<lineCount`
    /// (every line has finite positive height).
    ///
    /// Stability precondition: `lineCount` and `offset(ofLine:)` must be stable
    /// for one layout operation — a `compute` and any `VariableLineGeometryCursor`
    /// traversal derived from the range it produced — so the range and the
    /// geometry come from one consistent snapshot.
    func offset(ofLine index: Int) -> Double
}

public struct UniformLineMetrics: LineMetricsSource {
    public let lineCount: Int
    public let lineHeight: Double

    public init(lineCount: Int, lineHeight: Double) {
        self.lineCount = lineCount
        self.lineHeight = lineHeight
    }

    public func offset(ofLine index: Int) -> Double {
        Double(index) * lineHeight
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LineMetricsSourceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/LineMetricsSource.swift Tests/TextEngineCoreTests/LineMetricsSourceTests.swift
git commit -m "feat: add LineMetricsSource protocol and UniformLineMetrics"
```

---

### Task 2: `VariableViewportInput` and `invalidLineMetrics` error case

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift`
- Test: `Tests/TextEngineCoreTests/VariableViewportInputValueTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/TextEngineCoreTests/VariableViewportInputValueTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class VariableViewportInputValueTests: XCTestCase {
    func testVariableViewportInputStoresFields() {
        let input = VariableViewportInput(
            scrollOffsetY: 12.0,
            viewportHeight: 100.0,
            overscanLinesBefore: 2,
            overscanLinesAfter: 3
        )

        XCTAssertEqual(input.scrollOffsetY, 12.0)
        XCTAssertEqual(input.viewportHeight, 100.0)
        XCTAssertEqual(input.overscanLinesBefore, 2)
        XCTAssertEqual(input.overscanLinesAfter, 3)
        XCTAssertEqual(input, input)
    }

    func testInvalidLineMetricsErrorIsDistinct() {
        XCTAssertNotEqual(ViewportValidationError.invalidLineMetrics, .nonFiniteValue)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VariableViewportInputValueTests`
Expected: FAIL — `cannot find 'VariableViewportInput' in scope` and `type 'ViewportValidationError' has no member 'invalidLineMetrics'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/TextEngineCore/ViewportTypes.swift`, add the `invalidLineMetrics` case to the existing enum. Change:

```swift
public enum ViewportValidationError: Equatable {
    case negativeLineCount
    case nonFiniteValue
    case nonPositiveLineHeight
    case negativeViewportHeight
    case negativeOverscan
}
```

to:

```swift
public enum ViewportValidationError: Equatable {
    case negativeLineCount
    case nonFiniteValue
    case nonPositiveLineHeight
    case negativeViewportHeight
    case negativeOverscan
    case invalidLineMetrics
}
```

Then add this struct at the end of `Sources/TextEngineCore/ViewportTypes.swift`:

```swift
public struct VariableViewportInput: Equatable {
    public let scrollOffsetY: Double
    public let viewportHeight: Double
    public let overscanLinesBefore: Int
    public let overscanLinesAfter: Int

    public init(
        scrollOffsetY: Double,
        viewportHeight: Double,
        overscanLinesBefore: Int,
        overscanLinesAfter: Int
    ) {
        self.scrollOffsetY = scrollOffsetY
        self.viewportHeight = viewportHeight
        self.overscanLinesBefore = overscanLinesBefore
        self.overscanLinesAfter = overscanLinesAfter
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VariableViewportInputValueTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/ViewportTypes.swift Tests/TextEngineCoreTests/VariableViewportInputValueTests.swift
git commit -m "feat: add VariableViewportInput and invalidLineMetrics error case"
```

---

### Task 3: Extract shared `bufferedRange` helper (refactor, no behavior change)

**Files:**
- Modify: `Sources/TextEngineCore/ViewportVirtualizer.swift`

This is a pure refactor guarded by the existing `ViewportRangeTests` and the synthetic gate. No new test; the safety net is the unchanged suite staying green.

- [ ] **Step 1: Confirm the suite is green before the refactor**

Run: `swift test`
Expected: PASS, 0 failures.

- [ ] **Step 2: Make `emptyRange()` internal and add the `bufferedRange` helper**

In `Sources/TextEngineCore/ViewportVirtualizer.swift`, change the `emptyRange` declaration from:

```swift
    private static func emptyRange() -> VirtualRange {
```

to (drop `private` so the variable path can reuse it):

```swift
    static func emptyRange() -> VirtualRange {
```

Then add this new helper inside the `enum ViewportVirtualizer { ... }` body (place it directly after the `emptyRange()` function):

```swift
    static func bufferedRange(
        visibleStart: Int,
        visibleEndExclusive: Int,
        lineCount: Int,
        overscanLinesBefore: Int,
        overscanLinesAfter: Int,
        isAtTop: Bool,
        isAtBottom: Bool
    ) -> VirtualRange {
        let bufferStart = if overscanLinesBefore >= visibleStart {
            0
        } else {
            visibleStart - overscanLinesBefore
        }
        let remainingAfterVisible = lineCount - visibleEndExclusive
        let bufferEndExclusive = if overscanLinesAfter >= remainingAfterVisible {
            lineCount
        } else {
            visibleEndExclusive + overscanLinesAfter
        }

        return VirtualRange(
            visibleStart: visibleStart,
            visibleEndExclusive: visibleEndExclusive,
            bufferStart: bufferStart,
            bufferEndExclusive: bufferEndExclusive,
            isAtTop: isAtTop,
            isAtBottom: isAtBottom
        )
    }
```

- [ ] **Step 3: Route the fixed `compute` through the helper**

In the same file, replace this block in `compute(_:)`:

```swift
        let bufferStart = if input.overscanLinesBefore >= visibleStart {
            0
        } else {
            visibleStart - input.overscanLinesBefore
        }
        let remainingAfterVisible = input.lineCount - visibleEndExclusive
        let bufferEndExclusive = if input.overscanLinesAfter >= remainingAfterVisible {
            input.lineCount
        } else {
            visibleEndExclusive + input.overscanLinesAfter
        }

        return .success(
            VirtualRange(
                visibleStart: visibleStart,
                visibleEndExclusive: visibleEndExclusive,
                bufferStart: bufferStart,
                bufferEndExclusive: bufferEndExclusive,
                isAtTop: effectiveOffsetY == 0.0,
                isAtBottom: effectiveOffsetY == maxOffsetY
            )
        )
```

with:

```swift
        return .success(
            bufferedRange(
                visibleStart: visibleStart,
                visibleEndExclusive: visibleEndExclusive,
                lineCount: input.lineCount,
                overscanLinesBefore: input.overscanLinesBefore,
                overscanLinesAfter: input.overscanLinesAfter,
                isAtTop: effectiveOffsetY == 0.0,
                isAtBottom: effectiveOffsetY == maxOffsetY
            )
        )
```

- [ ] **Step 4: Verify no behavior change**

Run: `swift test`
Expected: PASS, 0 failures (same as Step 1).

Run: `swift run -c release ViewportBenchmarks -- --gate`
Expected: three `gate=pass` lines.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/ViewportVirtualizer.swift
git commit -m "refactor: extract shared bufferedRange helper in ViewportVirtualizer"
```

---

### Task 4: Variable-height `compute` (validation, contract checks, offset→line search)

**Files:**
- Create: `Sources/TextEngineCore/VariableViewportVirtualizer.swift`
- Create: `Tests/TextEngineCoreTests/TestLineMetrics.swift` (test-only metrics helpers)
- Test: `Tests/TextEngineCoreTests/VariableViewportComputeTests.swift`

- [ ] **Step 1: Add test-only metrics helpers**

Create `Tests/TextEngineCoreTests/TestLineMetrics.swift`:

```swift
import TextEngineCore

/// Test metrics built from explicit per-line heights; `offset(ofLine:)` returns
/// the cumulative top (prefix sum). Domain `0...lineCount`.
struct ListLineMetrics: LineMetricsSource {
    let prefix: [Double]

    init(heights: [Double]) {
        var sums: [Double] = [0.0]
        sums.reserveCapacity(heights.count + 1)
        var running = 0.0
        for height in heights {
            running += height
            sums.append(running)
        }
        self.prefix = sums
    }

    var lineCount: Int { prefix.count - 1 }

    func offset(ofLine index: Int) -> Double { prefix[index] }
}

/// Test metrics with an explicit `lineCount` and a custom offset function, used
/// to drive the contract/validation edge cases.
struct ClosureLineMetrics: LineMetricsSource {
    let lineCount: Int
    let offsetForLine: @Sendable (Int) -> Double

    func offset(ofLine index: Int) -> Double { offsetForLine(index) }
}
```

- [ ] **Step 2: Write the failing test**

Create `Tests/TextEngineCoreTests/VariableViewportComputeTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class VariableViewportComputeTests: XCTestCase {
    private func input(
        scrollOffsetY: Double,
        viewportHeight: Double,
        overscanLinesBefore: Int = 0,
        overscanLinesAfter: Int = 0
    ) -> VariableViewportInput {
        VariableViewportInput(
            scrollOffsetY: scrollOffsetY,
            viewportHeight: viewportHeight,
            overscanLinesBefore: overscanLinesBefore,
            overscanLinesAfter: overscanLinesAfter
        )
    }

    func testNonUniformVisibleRange() {
        // offsets: [0, 10, 40, 45, 145], totalHeight 145.
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: 20.0, viewportHeight: 30.0),
            metrics: metrics
        )

        XCTAssertEqual(
            result,
            .success(
                VirtualRange(
                    visibleStart: 1,
                    visibleEndExclusive: 4,
                    bufferStart: 1,
                    bufferEndExclusive: 4,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testNonUniformWithOverscan() {
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: 40.0, viewportHeight: 5.0, overscanLinesBefore: 1, overscanLinesAfter: 1),
            metrics: metrics
        )

        XCTAssertEqual(
            result,
            .success(
                VirtualRange(
                    visibleStart: 2,
                    visibleEndExclusive: 3,
                    bufferStart: 1,
                    bufferEndExclusive: 4,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testEmptyDocumentReturnsEmptyRange() {
        let metrics = ListLineMetrics(heights: [])
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: 0.0, viewportHeight: 100.0),
            metrics: metrics
        )

        XCTAssertEqual(
            result,
            .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 0,
                    bufferStart: 0,
                    bufferEndExclusive: 0,
                    isAtTop: true,
                    isAtBottom: true
                )
            )
        )
    }

    func testZeroHeightViewportExactLineTopIsEmpty() {
        // offsets: [0, 10, 40, 45, 145]. scrollOffset 40 == line 2 top -> empty [2, 2).
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 40.0, viewportHeight: 0.0), metrics: metrics),
            .success(
                VirtualRange(
                    visibleStart: 2,
                    visibleEndExclusive: 2,
                    bufferStart: 2,
                    bufferEndExclusive: 2,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testZeroHeightViewportMidLineKeepsCrossedLine() {
        // scrollOffset 20 is inside line 1 ([10, 40)) -> single crossed line [1, 2).
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 20.0, viewportHeight: 0.0), metrics: metrics),
            .success(
                VirtualRange(
                    visibleStart: 1,
                    visibleEndExclusive: 2,
                    bufferStart: 1,
                    bufferEndExclusive: 2,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testZeroHeightViewportAtDocumentEndClampsToLineCount() {
        // scrollOffset 145 == totalHeight (document end) -> visibleStart == lineCount.
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 145.0, viewportHeight: 0.0), metrics: metrics),
            .success(
                VirtualRange(
                    visibleStart: 4,
                    visibleEndExclusive: 4,
                    bufferStart: 4,
                    bufferEndExclusive: 4,
                    isAtTop: false,
                    isAtBottom: true
                )
            )
        )
    }

    func testNegativeLineCountFails() {
        let metrics = ClosureLineMetrics(lineCount: -1) { Double($0) }
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: 10.0), metrics: metrics),
            .failure(.negativeLineCount)
        )
    }

    func testNonFiniteScrollOffsetFails() {
        let metrics = ListLineMetrics(heights: [10, 10])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: .infinity, viewportHeight: 10.0), metrics: metrics),
            .failure(.nonFiniteValue)
        )
    }

    func testNegativeViewportHeightFails() {
        let metrics = ListLineMetrics(heights: [10, 10])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: -1.0), metrics: metrics),
            .failure(.negativeViewportHeight)
        )
    }

    func testNegativeOverscanFails() {
        let metrics = ListLineMetrics(heights: [10, 10])
        XCTAssertEqual(
            ViewportVirtualizer.compute(
                input(scrollOffsetY: 0.0, viewportHeight: 10.0, overscanLinesBefore: -1),
                metrics: metrics
            ),
            .failure(.negativeOverscan)
        )
    }

    func testNonZeroFirstOffsetFails() {
        let metrics = ClosureLineMetrics(lineCount: 3) { _ in 5.0 }
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: 10.0), metrics: metrics),
            .failure(.invalidLineMetrics)
        )
    }

    func testNonPositiveTotalHeightFails() {
        let metrics = ClosureLineMetrics(lineCount: 3) { _ in 0.0 }
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: 10.0), metrics: metrics),
            .failure(.invalidLineMetrics)
        )
    }

    func testNonFiniteTotalHeightFails() {
        let metrics = ClosureLineMetrics(lineCount: 3) { $0 == 3 ? .infinity : Double($0) }
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: 10.0), metrics: metrics),
            .failure(.invalidLineMetrics)
        )
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter VariableViewportComputeTests`
Expected: FAIL — no `compute(_:metrics:)` overload exists.

- [ ] **Step 4: Implement the variable `compute`**

Create `Sources/TextEngineCore/VariableViewportVirtualizer.swift`:

```swift
extension ViewportVirtualizer {
    public static func compute<Metrics: LineMetricsSource>(
        _ input: VariableViewportInput,
        metrics: Metrics
    ) -> ViewportComputation {
        let lineCount = metrics.lineCount

        if lineCount < 0 {
            return .failure(.negativeLineCount)
        }
        if !input.scrollOffsetY.isFinite || !input.viewportHeight.isFinite {
            return .failure(.nonFiniteValue)
        }
        if input.viewportHeight < 0.0 {
            return .failure(.negativeViewportHeight)
        }
        if input.overscanLinesBefore < 0 || input.overscanLinesAfter < 0 {
            return .failure(.negativeOverscan)
        }

        // O(1) metrics contract checks (Decision 5).
        if metrics.offset(ofLine: 0) != 0.0 {
            return .failure(.invalidLineMetrics)
        }
        if lineCount == 0 {
            return .success(emptyRange())
        }
        let totalHeight = metrics.offset(ofLine: lineCount)
        if !totalHeight.isFinite || totalHeight <= 0.0 {
            return .failure(.invalidLineMetrics)
        }

        let maxOffsetY = variableMaximumOffsetY(totalHeight: totalHeight, viewportHeight: input.viewportHeight)
        let effectiveOffsetY = variableClampedOffsetY(scrollOffsetY: input.scrollOffsetY, maxOffsetY: maxOffsetY)

        let visibleStart = firstLineTopAtOrBelow(
            effectiveOffsetY,
            metrics: metrics,
            lineCount: lineCount,
            totalHeight: totalHeight
        )
        let visibleEndExclusive = firstLineTopAtOrAbove(
            effectiveOffsetY + input.viewportHeight,
            metrics: metrics,
            lineCount: lineCount,
            totalHeight: totalHeight
        )

        return .success(
            bufferedRange(
                visibleStart: visibleStart,
                visibleEndExclusive: visibleEndExclusive,
                lineCount: lineCount,
                overscanLinesBefore: input.overscanLinesBefore,
                overscanLinesAfter: input.overscanLinesAfter,
                isAtTop: effectiveOffsetY == 0.0,
                isAtBottom: effectiveOffsetY == maxOffsetY
            )
        )
    }

    private static func variableMaximumOffsetY(totalHeight: Double, viewportHeight: Double) -> Double {
        let maxOffsetY = totalHeight - viewportHeight
        return maxOffsetY < 0.0 ? 0.0 : maxOffsetY
    }

    private static func variableClampedOffsetY(scrollOffsetY: Double, maxOffsetY: Double) -> Double {
        if scrollOffsetY < 0.0 {
            return 0.0
        }
        if scrollOffsetY > maxOffsetY {
            return maxOffsetY
        }
        return scrollOffsetY
    }

    // Largest i in [0, lineCount) with offset(i) <= target (the line containing
    // `target`). For `target` at or past the document end, returns lineCount.
    private static func firstLineTopAtOrBelow<Metrics: LineMetricsSource>(
        _ target: Double,
        metrics: Metrics,
        lineCount: Int,
        totalHeight: Double
    ) -> Int {
        if target >= totalHeight {
            return lineCount
        }
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

    // Smallest i in [0, lineCount] with offset(i) >= target (the first line whose
    // top is at or below the viewport bottom, exclusive). For `target` at or past
    // the document end, returns lineCount.
    private static func firstLineTopAtOrAbove<Metrics: LineMetricsSource>(
        _ target: Double,
        metrics: Metrics,
        lineCount: Int,
        totalHeight: Double
    ) -> Int {
        if target >= totalHeight {
            return lineCount
        }
        var low = 0
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
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter VariableViewportComputeTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextEngineCore/VariableViewportVirtualizer.swift Tests/TextEngineCoreTests/TestLineMetrics.swift Tests/TextEngineCoreTests/VariableViewportComputeTests.swift
git commit -m "feat: add variable-height ViewportVirtualizer.compute"
```

---

### Task 5: Equivalence oracle — variable(uniform) == fixed (keystone test)

**Files:**
- Test: `Tests/TextEngineCoreTests/VariableUniformEquivalenceTests.swift`

This proves the variable path subsumes the fixed path, using exactly-representable line heights (per the spec's resolved Precision finding). No production code changes — if it passes, the variable `compute` is correct against the fixed ground truth.

- [ ] **Step 1: Write the test**

Create `Tests/TextEngineCoreTests/VariableUniformEquivalenceTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class VariableUniformEquivalenceTests: XCTestCase {
    private func assertEquivalent(
        lineCount: Int,
        lineHeight: Double,
        scrollOffsetY: Double,
        viewportHeight: Double,
        overscanBefore: Int,
        overscanAfter: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fixed = ViewportVirtualizer.compute(
            ViewportInput(
                lineCount: lineCount,
                lineHeight: lineHeight,
                scrollOffsetY: scrollOffsetY,
                viewportHeight: viewportHeight,
                overscanLinesBefore: overscanBefore,
                overscanLinesAfter: overscanAfter
            )
        )
        let variable = ViewportVirtualizer.compute(
            VariableViewportInput(
                scrollOffsetY: scrollOffsetY,
                viewportHeight: viewportHeight,
                overscanLinesBefore: overscanBefore,
                overscanLinesAfter: overscanAfter
            ),
            metrics: UniformLineMetrics(lineCount: lineCount, lineHeight: lineHeight)
        )
        XCTAssertEqual(variable, fixed, file: file, line: line)
    }

    func testMatchesFixedAcrossRepresentableHeights() {
        let heights: [Double] = [1.0, 10.0, 16.0, 12.5, 256.0]
        // Counts stay well under 2^53, so Double(i) * lineHeight is strictly
        // increasing and the metrics honor their own contract.
        let counts = [1, 2, 3, 100, 100_000]

        for height in heights {
            for count in counts {
                let total = Double(count) * height
                let positions: [Double] = [
                    -height,                          // negative -> clamp to top
                    0.0,                              // first line top
                    height,                           // second line top
                    Double(count / 2) * height,       // a mid-document line top
                    Double(count / 2) * height + height / 2, // mid-line
                    total,                            // at the document end
                    total + height                    // past the document end
                ]
                let viewports: [Double] = [0.0, height, height * 3 + height / 2, total + height]

                for position in positions {
                    for viewport in viewports {
                        assertEquivalent(
                            lineCount: count, lineHeight: height,
                            scrollOffsetY: position, viewportHeight: viewport,
                            overscanBefore: 0, overscanAfter: 0
                        )
                        assertEquivalent(
                            lineCount: count, lineHeight: height,
                            scrollOffsetY: position, viewportHeight: viewport,
                            overscanBefore: 5, overscanAfter: 7
                        )
                    }
                }
            }
        }
    }

    // Clamp-at-end special case ONLY. UniformLineMetrics at Int.max is NOT
    // strictly increasing (consecutive Ints above 2^53 collapse to the same
    // Double), so this must not exercise the offset->line search — and it does
    // not: scrollOffsetY clamps to totalHeight, so both paths take the
    // `target >= totalHeight -> visibleStart == lineCount` early-out. This only
    // proves clamp/overflow-safety, not strict-increasing equivalence.
    func testMatchesFixedForIntMaxClamp() {
        assertEquivalent(
            lineCount: Int.max, lineHeight: 1.0,
            scrollOffsetY: Double(Int.max), viewportHeight: 0.0,
            overscanBefore: 0, overscanAfter: 0
        )
    }
}
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter VariableUniformEquivalenceTests`
Expected: PASS.

If any assertion fails, the failure message prints the exact `(lineCount, lineHeight, scrollOffsetY, viewportHeight, overscan)`. This is the spec's anticipated plan-time checkpoint: STOP and report the failing case rather than weakening the test. Do not add a fuzzy tolerance — the resolved decision is direct comparison on representable heights.

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/VariableUniformEquivalenceTests.swift
git commit -m "test: prove variable compute matches fixed path for uniform metrics"
```

---

### Task 6: `VariableLineGeometryCursor` and the `geometry(for:metrics:)` factory

**Files:**
- Create: `Sources/TextEngineCore/VariableLineGeometryCursor.swift`
- Test: `Tests/TextEngineCoreTests/VariableLineGeometryCursorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/TextEngineCoreTests/VariableLineGeometryCursorTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class VariableLineGeometryCursorTests: XCTestCase {
    func testCursorYieldsBufferedLineGeometry() {
        // offsets: [0, 10, 40, 45, 145].
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        let range = VirtualRange(
            visibleStart: 2,
            visibleEndExclusive: 3,
            bufferStart: 1,
            bufferEndExclusive: 4,
            isAtTop: false,
            isAtBottom: false
        )

        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        var output: [LineGeometry] = []
        while let geometry = cursor.next() {
            output.append(geometry)
        }

        XCTAssertEqual(
            output,
            [
                LineGeometry(lineIndex: 1, y: 10.0, height: 30.0),
                LineGeometry(lineIndex: 2, y: 40.0, height: 5.0),
                LineGeometry(lineIndex: 3, y: 45.0, height: 100.0)
            ]
        )
    }

    func testCursorForEmptyRangeYieldsNoGeometry() {
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        let range = VirtualRange(
            visibleStart: 0,
            visibleEndExclusive: 0,
            bufferStart: 0,
            bufferEndExclusive: 0,
            isAtTop: true,
            isAtBottom: true
        )

        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        XCTAssertNil(cursor.next())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VariableLineGeometryCursorTests`
Expected: FAIL — no `geometry(for:metrics:)` / `VariableLineGeometryCursor`.

- [ ] **Step 3: Implement the cursor and factory**

Create `Sources/TextEngineCore/VariableLineGeometryCursor.swift`:

```swift
public struct VariableLineGeometryCursor<Metrics: LineMetricsSource> {
    private let metrics: Metrics
    private var nextLineIndex: Int
    private let endExclusive: Int
    private var nextLineTop: Double

    public init(bufferStart: Int, bufferEndExclusive: Int, metrics: Metrics) {
        self.metrics = metrics
        self.nextLineIndex = bufferStart
        self.endExclusive = bufferEndExclusive
        self.nextLineTop = bufferStart < bufferEndExclusive ? metrics.offset(ofLine: bufferStart) : 0.0
    }

    public mutating func next() -> LineGeometry? {
        if nextLineIndex >= endExclusive {
            return nil
        }

        let lineIndex = nextLineIndex
        let y = nextLineTop
        let bottom = metrics.offset(ofLine: lineIndex + 1)
        nextLineIndex += 1
        nextLineTop = bottom

        return LineGeometry(lineIndex: lineIndex, y: y, height: bottom - y)
    }
}

extension ViewportVirtualizer {
    public static func geometry<Metrics: LineMetricsSource>(
        for range: VirtualRange,
        metrics: Metrics
    ) -> VariableLineGeometryCursor<Metrics> {
        VariableLineGeometryCursor(
            bufferStart: range.bufferStart,
            bufferEndExclusive: range.bufferEndExclusive,
            metrics: metrics
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VariableLineGeometryCursorTests`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextEngineCore/VariableLineGeometryCursor.swift Tests/TextEngineCoreTests/VariableLineGeometryCursorTests.swift
git commit -m "feat: add VariableLineGeometryCursor"
```

---

### Task 7: Add the `--variable-height` benchmark mode, runner, and CI-failing gate

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- Create: `Sources/ViewportBenchmarks/VariableHeightBenchmark.swift`

The benchmark target has no XCTest coverage (it is an executable), so this task is verified by building and running the executable. All three files land in **one commit**: `BenchmarkMode.variableHeight`, the `BenchmarkProgram` switch arm, and `runVariableHeightBenchmarks` are mutually dependent (a partial commit would not compile — non-exhaustive switch and/or undefined symbol), so the build step runs only after all three files exist.

- [ ] **Step 1: Replace `BenchmarkOptions.swift` with the version that knows `--variable-height`**

Overwrite `Sources/ViewportBenchmarks/BenchmarkOptions.swift` with:

```swift
enum BenchmarkMode {
    case pipeline
    case rangeOnly
    case realisticProvider
    case variableHeight
    case memoryShape
    case memoryObservation

    var outputName: String {
        switch self {
        case .pipeline:
            return "pipeline"
        case .rangeOnly:
            return "range_only"
        case .realisticProvider:
            return "realistic_provider"
        case .variableHeight:
            return "variable_height"
        case .memoryShape:
            return "memory_shape"
        case .memoryObservation:
            return "memory_observation"
        }
    }
}

enum BenchmarkOptionParse {
    case run(BenchmarkOptions)
    case help
    case failure(String)
}

struct BenchmarkOptions {
    let mode: BenchmarkMode
    let enforceGate: Bool

    static let usage = """
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--variable-height] [--memory-shape] [--memory-observation] [--help]

    Options:
      --range-only          Run only viewport range recompute benchmark.
      --gate                Enforce p95/p99 budgets for gateable benchmark modes and exit non-zero on failure.
      --realistic-provider  Run large-text provider benchmark. Combine with --gate to enforce calibrated budgets.
      --variable-height     Run variable-height compute+geometry benchmark. Combine with --gate to enforce budgets.
      --memory-shape        Run deterministic core-owned memory-shape diagnostics.
      --memory-observation  Run host RSS observation diagnostics.
      --help                Print this help.
    """

    static func parse(_ arguments: [String]) -> BenchmarkOptionParse {
        var mode = BenchmarkMode.pipeline
        var enforceGate = false

        for argument in arguments {
            switch argument {
            case "--":
                continue
            case "--help":
                return .help
            case "--range-only":
                if mode != .pipeline {
                    return .failure("--range-only cannot be combined with another mode")
                }
                mode = .rangeOnly
            case "--gate":
                enforceGate = true
            case "--realistic-provider":
                if mode != .pipeline {
                    return .failure("--realistic-provider cannot be combined with another mode")
                }
                mode = .realisticProvider
            case "--variable-height":
                if mode != .pipeline {
                    return .failure("--variable-height cannot be combined with another mode")
                }
                mode = .variableHeight
            case "--memory-shape":
                if mode != .pipeline {
                    return .failure("--memory-shape cannot be combined with another mode")
                }
                mode = .memoryShape
            case "--memory-observation":
                if mode != .pipeline {
                    return .failure("--memory-observation cannot be combined with another mode")
                }
                mode = .memoryObservation
            default:
                return .failure("unknown argument \(argument)")
            }
        }

        if enforceGate && (mode == .rangeOnly || mode == .memoryShape || mode == .memoryObservation) {
            return .failure("--gate cannot be combined with \(mode.outputName) mode")
        }

        return .run(BenchmarkOptions(mode: mode, enforceGate: enforceGate))
    }
}
```

(The mutual-exclusion checks are simplified to "only one non-pipeline mode flag" — behavior-equivalent to the old pairwise checks, and it now covers `--variable-height` too.)

- [ ] **Step 2: Route the new mode in the program**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, change:

```swift
    switch options.mode {
    case .pipeline, .rangeOnly:
        return runSyntheticBenchmarks(options: options)
    case .realisticProvider:
        return runRealisticProviderBenchmarks(enforceGate: options.enforceGate)
    case .memoryShape:
        return runMemoryShapeDiagnostics()
    case .memoryObservation:
        return runMemoryObservationDiagnostics()
    }
```

to:

```swift
    switch options.mode {
    case .pipeline, .rangeOnly:
        return runSyntheticBenchmarks(options: options)
    case .realisticProvider:
        return runRealisticProviderBenchmarks(enforceGate: options.enforceGate)
    case .variableHeight:
        return runVariableHeightBenchmarks(enforceGate: options.enforceGate)
    case .memoryShape:
        return runMemoryShapeDiagnostics()
    case .memoryObservation:
        return runMemoryObservationDiagnostics()
    }
```

This references `runVariableHeightBenchmarks`, created in Step 3 below. Do not build yet — the build step (Step 4) runs after all three files exist.

- [ ] **Step 3: Create the benchmark runner and `PrefixSumLineMetrics`**

Create `Sources/ViewportBenchmarks/VariableHeightBenchmark.swift`:

```swift
import TextEngineCore

struct PrefixSumLineMetrics: LineMetricsSource {
    let prefix: [Double]

    init(heights: [Double]) {
        var sums: [Double] = [0.0]
        sums.reserveCapacity(heights.count + 1)
        var running = 0.0
        for height in heights {
            running += height
            sums.append(running)
        }
        self.prefix = sums
    }

    var lineCount: Int { prefix.count - 1 }

    func offset(ofLine index: Int) -> Double { prefix[index] }
}

struct VariableHeightScenario {
    let name: String
    let lineCount: Int
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

func variableHeightScenarios() -> [VariableHeightScenario] {
    [
        VariableHeightScenario(
            name: "1k_lines_20_visible_overscan_0",
            lineCount: 1_000,
            viewportHeight: 20.0 * 16.0,
            overscanBefore: 0,
            overscanAfter: 0,
            p95BudgetNanoseconds: 50_000,
            p99BudgetNanoseconds: 100_000
        ),
        VariableHeightScenario(
            name: "100k_lines_80_visible_overscan_5",
            lineCount: 100_000,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5,
            p95BudgetNanoseconds: 100_000,
            p99BudgetNanoseconds: 200_000
        ),
        VariableHeightScenario(
            name: "1m_lines_200_visible_overscan_50",
            lineCount: 1_000_000,
            viewportHeight: 200.0 * 16.0,
            overscanBefore: 50,
            overscanAfter: 50,
            p95BudgetNanoseconds: 250_000,
            p99BudgetNanoseconds: 500_000
        )
    ]
}

// Deterministic, strictly-positive, non-uniform heights in {14, 16, 20, 32}.
func variableHeights(lineCount: Int) -> [Double] {
    var heights: [Double] = []
    heights.reserveCapacity(lineCount)
    for index in 0..<lineCount {
        let bucket = ((index &* 31) &+ 7) % 4
        switch bucket {
        case 0:
            heights.append(14.0)
        case 1:
            heights.append(16.0)
        case 2:
            heights.append(20.0)
        default:
            heights.append(32.0)
        }
    }
    return heights
}

@inline(never)
func runVariableHeightOperation(
    input: VariableViewportInput,
    metrics: PrefixSumLineMetrics
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
func runVariableHeightScenario(
    _ scenario: VariableHeightScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let metrics = PrefixSumLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
    let totalHeight = metrics.offset(ofLine: metrics.lineCount)
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0
    let maxOffset = totalHeight > scenario.viewportHeight ? totalHeight - scenario.viewportHeight : 0.0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let offset = deterministicScrollOffset(sample: sample, maxOffset: maxOffset)
            let input = VariableViewportInput(
                scrollOffsetY: offset,
                viewportHeight: scenario.viewportHeight,
                overscanLinesBefore: scenario.overscanBefore,
                overscanLinesAfter: scenario.overscanAfter
            )

            let operationResult = runVariableHeightOperation(input: input, metrics: metrics)
            checksum &+= operationResult.checksum
            failureCount &+= operationResult.failureCount
        }
        let elapsed = start.duration(to: clock.now)

        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .variableHeight,
        providerName: "prefix_sum",
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
func runVariableHeightBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in variableHeightScenarios() {
        let summary = runVariableHeightScenario(
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

- [ ] **Step 4: Build (now that all three files exist)**

Run: `swift build -c release`
Expected: build succeeds.

- [ ] **Step 5: Run the benchmark (observation, no gate)**

Run: `swift run -c release ViewportBenchmarks -- --variable-height`
Expected: three `mode=variable_height provider=prefix_sum scenario=… p95_ns=… p99_ns=… failures=0 checksum=…` lines, no `gate=` field.

- [ ] **Step 6: Run the gate and confirm generous headroom**

Run: `swift run -c release ViewportBenchmarks -- --variable-height --gate`
Expected: three `gate=pass` lines, exit code 0.

Inspect the printed `p95_ns`/`p99_ns` against `budget_p95_ns`/`budget_p99_ns`. Each observed value should be comfortably under budget (target ≥ 2× headroom). If any observed value is within 2× of its budget, raise the corresponding budget so the CI-failing gate stays robust (Slice 11 lesson: thin CI margins are fragile) and re-run. If a `gate=fail` appears, STOP and report the observed numbers rather than loosening blindly.

- [ ] **Step 7: Confirm `--help` lists the new flag**

Run: `swift run ViewportBenchmarks -- --help`
Expected: usage text includes the `--variable-height` line.

- [ ] **Step 8: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/VariableHeightBenchmark.swift
git commit -m "feat: add --variable-height benchmark mode and CI-failing gate"
```

---

### Task 8: Wire the variable-height gate into CI

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Add the gate step after the synthetic gate**

In `.github/workflows/swift-ci.yml`, in the `host-tests-and-benchmark-gate` job, insert a new step immediately after the existing `Run synthetic benchmark gate` step and before `Run memory shape diagnostic`. Change:

```yaml
      - name: Run synthetic benchmark gate
        run: swift run -c release ViewportBenchmarks -- --gate

      - name: Run memory shape diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-shape
```

to:

```yaml
      - name: Run synthetic benchmark gate
        run: swift run -c release ViewportBenchmarks -- --gate

      - name: Run variable-height benchmark gate
        run: swift run -c release ViewportBenchmarks -- --variable-height --gate

      - name: Run memory shape diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-shape
```

- [ ] **Step 2: Validate the workflow YAML locally**

Run: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"`
Expected: `yaml_ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: run variable-height benchmark gate after synthetic gate"
```

---

### Task 9: Variable-height memory-shape scenario

**Files:**
- Modify: `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`

Demonstrates O(1) core memory (identical `core_owned_bytes` at 100k vs 1M) and O(buffer) traversal (`geometry_lines == buffered_lines`) on the variable path, using allocation-free `UniformLineMetrics`.

- [ ] **Step 1: Add the variable-height memory-shape functions**

Append to `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`:

```swift
func variableCoreOwnedBytesEstimate() -> Int {
    MemoryLayout<VirtualRange>.size
        + MemoryLayout<VariableLineGeometryCursor<UniformLineMetrics>>.size
        + MemoryLayout<Int>.size * 2
}

struct VariableMemoryShapeSummary {
    let scenarioName: String
    let lineCount: Int
    let bufferedLines: Int
    let geometryLines: Int
    let coreOwnedBytes: Int
    let traversalPasses: Bool
    let checksum: Int
}

func runVariableMemoryShapeScenario(lineCount: Int) -> VariableMemoryShapeSummary {
    let lineHeight = 16.0
    let viewportHeight = 80.0 * lineHeight
    let overscanBefore = 5
    let overscanAfter = 5
    let metrics = UniformLineMetrics(lineCount: lineCount, lineHeight: lineHeight)
    let totalHeight = metrics.offset(ofLine: lineCount)
    let maxOffset = totalHeight > viewportHeight ? totalHeight - viewportHeight : 0.0
    let middleOffset = Double(lineCount / 2) * lineHeight
    let scrollOffsetY = middleOffset > maxOffset ? maxOffset : middleOffset
    let input = VariableViewportInput(
        scrollOffsetY: scrollOffsetY,
        viewportHeight: viewportHeight,
        overscanLinesBefore: overscanBefore,
        overscanLinesAfter: overscanAfter
    )
    let coreOwnedBytes = variableCoreOwnedBytesEstimate()
    let scenarioName = "\(lineCount)_lines_80_visible_overscan_5"

    switch ViewportVirtualizer.compute(input, metrics: metrics) {
    case let .success(range):
        let bufferedLines = range.bufferEndExclusive - range.bufferStart
        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        var geometryLines = 0
        var checksum = 0
        while let geometry = cursor.next() {
            geometryLines += 1
            checksum &+= geometry.lineIndex
            checksum &+= Int(geometry.y)
            checksum &+= Int(geometry.height)
        }

        return VariableMemoryShapeSummary(
            scenarioName: scenarioName,
            lineCount: lineCount,
            bufferedLines: bufferedLines,
            geometryLines: geometryLines,
            coreOwnedBytes: coreOwnedBytes,
            traversalPasses: geometryLines == bufferedLines,
            checksum: checksum
        )
    case .failure:
        return VariableMemoryShapeSummary(
            scenarioName: scenarioName,
            lineCount: lineCount,
            bufferedLines: 0,
            geometryLines: 0,
            coreOwnedBytes: coreOwnedBytes,
            traversalPasses: false,
            checksum: -1
        )
    }
}

func formatVariableMemoryShapeSummary(_ summary: VariableMemoryShapeSummary, invariantPasses: Bool) -> String {
    var output = "mode=\(BenchmarkMode.memoryShape.outputName)"
    output += " provider=variable_uniform"
    output += " scenario=\(summary.scenarioName)"
    output += " line_count=\(summary.lineCount)"
    output += " buffered_lines=\(summary.bufferedLines)"
    output += " geometry_lines=\(summary.geometryLines)"
    output += " core_owned_bytes=\(summary.coreOwnedBytes)"
    output += " invariant=\(invariantPasses ? "pass" : "fail")"
    output += " checksum=\(summary.checksum)"
    return output
}
```

- [ ] **Step 2: Run the variable scenarios inside `runMemoryShapeDiagnostics`**

In the same file, in `runMemoryShapeDiagnostics()`, insert the following immediately before the closing `return passed`:

```swift
    let variableSummaries = [100_000, 1_000_000].map(runVariableMemoryShapeScenario)
    let referenceVariableCoreOwnedBytes = variableSummaries.first?.coreOwnedBytes
    for summary in variableSummaries {
        let coreBytesMatches = summary.coreOwnedBytes == referenceVariableCoreOwnedBytes
        let invariantPasses = summary.traversalPasses && coreBytesMatches
        print(formatVariableMemoryShapeSummary(summary, invariantPasses: invariantPasses))

        if !invariantPasses {
            passed = false
        }
    }
```

- [ ] **Step 3: Run the memory-shape diagnostic**

Run: `swift run -c release ViewportBenchmarks -- --memory-shape`
Expected: the three existing `invariant=pass` lines, plus two new
`mode=memory_shape provider=variable_uniform scenario=…_lines_80_visible_overscan_5 … invariant=pass` lines (one for 100k, one for 1M) with identical `core_owned_bytes` and `geometry_lines == buffered_lines`. Exit code 0.

- [ ] **Step 4: Commit**

```bash
git add Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
git commit -m "feat: add variable-height memory-shape scenario"
```

---

### Task 10: Full verification (host, gates, diagnostics, portability)

**Files:** none (verification only).

Run the full `Verification` set from the spec. Record any failure and stop.

- [ ] **Step 1: Host tests**

Run: `swift test`
Expected: PASS, 0 failures.

- [ ] **Step 2: Release build**

Run: `swift build -c release`
Expected: build succeeds.

- [ ] **Step 3: Synthetic gate (unchanged)**

Run: `swift run -c release ViewportBenchmarks -- --gate`
Expected: three `gate=pass` lines.

- [ ] **Step 4: Variable-height gate (new)**

Run: `swift run -c release ViewportBenchmarks -- --variable-height --gate`
Expected: three `gate=pass` lines.

- [ ] **Step 5: Memory-shape diagnostic (with new variable scenario)**

Run: `swift run -c release ViewportBenchmarks -- --memory-shape`
Expected: all `invariant=pass`, including the two `provider=variable_uniform` lines.

- [ ] **Step 6: RSS memory observation (unchanged)**

Run: `swift run -c release ViewportBenchmarks -- --memory-observation`
Expected: three `observation=pass` lines.

- [ ] **Step 7: Local WASM and embedded-WASM core builds**

Run:
```bash
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
```
Expected: both succeed. (If the installed Swift SDK identifiers differ on the maintainer's machine, use `swift sdk list` to find the matching `wasm` / `wasm-embedded` SDK ids and substitute them.)

- [ ] **Step 8: iOS cross-target compile (the Slice 13 helper)**

Run: `./.github/scripts/cross-target-compile.sh`
Expected: `target=ios_device result=pass` and `target=ios_simulator result=pass`; WASM lines may be `skipped` depending on the local toolchain; summary `blocking_failures=0 exit=0`.

- [ ] **Step 9: Confirm core is Foundation-free**

Run: `rg -n "Foundation" Sources/TextEngineCore`
Expected: no matches (exit code 1) — the brief's no-Foundation-in-core constraint, re-checked because this slice changes the public surface.

- [ ] **Step 10: Push the branch and confirm CI is green**

Push `slice-14-variable-height-layout-foundation` and confirm the `Host tests and benchmark gate` job (now including the variable-height gate step) and the `Cross-target compile` job both conclude `success`. iOS targets pass and block; WASM stays skipped on the hosted runner (Swift 6.1.2), unchanged from Slice 13.

---

## Self-Review

**Spec coverage:**
- Stateless core + `LineMetricsSource` (Decision 1–3): Tasks 1, 4. ✓
- Provider `offset(ofLine:)` + core binary search (Decision 2): Task 4. ✓
- Separate metrics protocol (Decision 3): Task 1. ✓
- Fixed path preserved + `UniformLineMetrics` oracle (Decision 4): Tasks 3, 5. ✓
- Contractual O(1) validation + `invalidLineMetrics` (Decision 5): Tasks 2, 4. ✓
- CI-failing variable-height gate (Decision 6): Tasks 7, 8. ✓
- `VariableViewportInput`, reused output types: Task 2. ✓
- `compute` algorithm incl. `effOffsetY >= totalHeight → lineCount` special case: Task 4 (`firstLineTopAtOrBelow`/`firstLineTopAtOrAbove` early-out). ✓
- `VariableLineGeometryCursor` (rolling offset, copy-safe handle): Task 6. ✓
- Internal shared `bufferedRange` refactor: Task 3. ✓
- Precision: direct comparison + representable-height oracle (resolved finding): Task 5. ✓
- Reference `PrefixSumLineMetrics` + perf gate (compute + geometry, varied offsets): Task 7. ✓
- Memory-shape demonstration (100k vs 1M, identical core bytes; handle): Task 9. ✓
- Verification + Acceptance Criteria: Task 10. ✓
- Out of scope (mutation, WASM-CI promotion, branch protection, storage adapters, memory budgets, measurement source): untouched. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every run step shows the command and expected output.

**Type consistency:** `LineMetricsSource.offset(ofLine:)`, `UniformLineMetrics`, `VariableViewportInput`, `ViewportValidationError.invalidLineMetrics`, `bufferedRange(...)`, `ViewportVirtualizer.compute(_:metrics:)`, `VariableLineGeometryCursor`, `ViewportVirtualizer.geometry(for:metrics:)`, `PrefixSumLineMetrics`, `BenchmarkMode.variableHeight` / `outputName "variable_height"`, `runVariableHeightBenchmarks(enforceGate:)` are used consistently across tasks. The benchmark `BenchmarkSummary` fields match the existing model. `ListLineMetrics`/`ClosureLineMetrics` are test-only (test target); `PrefixSumLineMetrics` is benchmark-only (executable target) — the two targets cannot share, so the small duplication is intentional.
