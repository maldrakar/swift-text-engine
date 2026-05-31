# Headless Fixed-Height Viewport Virtualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Swift headless core that computes visible and buffered viewport ranges for fixed-height logical lines.

**Architecture:** The core is a SwiftPM library target with value-type inputs and outputs, no Foundation dependency in public API, and a stateless `ViewportVirtualizer`. Tests drive range calculation, validation, overscan behavior, and geometry cursor behavior. A separate executable target reports p95 and p99 headless recompute latency.

**Tech Stack:** Swift Package Manager, Swift standard library, XCTest for tests, a Swift executable benchmark target using standard library timing.

---

## Scope Check

This plan implements the approved first slice from `docs/superpowers/specs/2026-05-30-headless-fixed-height-viewport-virtualization-design.md`.

It does not implement glyph shaping, rasterization, bidi, rich text, variable-height line layout, provider storage, async prefetch, or UI adapters.

## File Structure

- Create `Package.swift`: SwiftPM manifest with `TextEngineCore` and `TextEngineCoreTests`; add `ViewportBenchmarks` in Task 6.
- Create `Sources/TextEngineCore/ViewportTypes.swift`: public value types and validation result enums.
- Create `Sources/TextEngineCore/ViewportVirtualizer.swift`: stateless validation and range calculation.
- Create `Sources/TextEngineCore/LineGeometryCursor.swift`: allocation-free cursor for buffered line geometry.
- Create `Tests/TextEngineCoreTests/ViewportInputValueTests.swift`: value type tests.
- Create `Tests/TextEngineCoreTests/ViewportValidationTests.swift`: invalid input and empty document tests.
- Create `Tests/TextEngineCoreTests/ViewportRangeTests.swift`: fixed-height visible range tests.
- Create `Tests/TextEngineCoreTests/ViewportOverscanInvariantTests.swift`: overscan, clamping, and deterministic invariant tests.
- Create `Tests/TextEngineCoreTests/LineGeometryCursorTests.swift`: geometry cursor tests.
- Create `Sources/ViewportBenchmarks/main.swift`: benchmark executable that prints p95 and p99 latency.
- Create `docs/superpowers/verification/2026-05-31-headless-fixed-height-viewport-virtualization.md`: compile and benchmark verification record.

## Task 1: Package Skeleton And Public Value Types

**Files:**
- Create: `Package.swift`
- Create: `Tests/TextEngineCoreTests/ViewportInputValueTests.swift`
- Create: `Sources/TextEngineCore/ViewportTypes.swift`

- [ ] **Step 1: Create the package manifest and failing value-type tests**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTextEngine",
    products: [
        .library(name: "TextEngineCore", targets: ["TextEngineCore"])
    ],
    targets: [
        .target(name: "TextEngineCore"),
        .testTarget(
            name: "TextEngineCoreTests",
            dependencies: ["TextEngineCore"]
        )
    ]
)
```

Create `Tests/TextEngineCoreTests/ViewportInputValueTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ViewportInputValueTests: XCTestCase {
    func testViewportInputStoresAllFields() {
        let input = ViewportInput(
            lineCount: 100,
            lineHeight: 12.5,
            scrollOffsetY: 25.0,
            viewportHeight: 80.0,
            overscanLinesBefore: 2,
            overscanLinesAfter: 3
        )

        XCTAssertEqual(input.lineCount, 100)
        XCTAssertEqual(input.lineHeight, 12.5)
        XCTAssertEqual(input.scrollOffsetY, 25.0)
        XCTAssertEqual(input.viewportHeight, 80.0)
        XCTAssertEqual(input.overscanLinesBefore, 2)
        XCTAssertEqual(input.overscanLinesAfter, 3)
    }

    func testVirtualRangeReportsEmpty() {
        let range = VirtualRange(
            visibleStart: 0,
            visibleEndExclusive: 0,
            bufferStart: 0,
            bufferEndExclusive: 0,
            isAtTop: true,
            isAtBottom: true
        )

        XCTAssertTrue(range.isEmpty)
        XCTAssertTrue(range.isAtTop)
        XCTAssertTrue(range.isAtBottom)
    }

    func testLineGeometryStoresIndexAndDimensions() {
        let geometry = LineGeometry(lineIndex: 7, y: 84.0, height: 12.0)

        XCTAssertEqual(geometry.lineIndex, 7)
        XCTAssertEqual(geometry.y, 84.0)
        XCTAssertEqual(geometry.height, 12.0)
    }
}
```

- [ ] **Step 2: Run tests to verify the missing core types fail**

Run:

```bash
swift test --filter ViewportInputValueTests
```

Expected: FAIL because `ViewportInput`, `VirtualRange`, and `LineGeometry` do not exist.

- [ ] **Step 3: Create the minimal public value types**

Create `Sources/TextEngineCore/ViewportTypes.swift`:

```swift
public struct ViewportInput: Equatable {
    public let lineCount: Int
    public let lineHeight: Double
    public let scrollOffsetY: Double
    public let viewportHeight: Double
    public let overscanLinesBefore: Int
    public let overscanLinesAfter: Int

    public init(
        lineCount: Int,
        lineHeight: Double,
        scrollOffsetY: Double,
        viewportHeight: Double,
        overscanLinesBefore: Int,
        overscanLinesAfter: Int
    ) {
        self.lineCount = lineCount
        self.lineHeight = lineHeight
        self.scrollOffsetY = scrollOffsetY
        self.viewportHeight = viewportHeight
        self.overscanLinesBefore = overscanLinesBefore
        self.overscanLinesAfter = overscanLinesAfter
    }
}

public struct VirtualRange: Equatable {
    public let visibleStart: Int
    public let visibleEndExclusive: Int
    public let bufferStart: Int
    public let bufferEndExclusive: Int
    public let isAtTop: Bool
    public let isAtBottom: Bool

    public var isEmpty: Bool {
        visibleStart == visibleEndExclusive && bufferStart == bufferEndExclusive
    }

    public init(
        visibleStart: Int,
        visibleEndExclusive: Int,
        bufferStart: Int,
        bufferEndExclusive: Int,
        isAtTop: Bool,
        isAtBottom: Bool
    ) {
        self.visibleStart = visibleStart
        self.visibleEndExclusive = visibleEndExclusive
        self.bufferStart = bufferStart
        self.bufferEndExclusive = bufferEndExclusive
        self.isAtTop = isAtTop
        self.isAtBottom = isAtBottom
    }
}

public struct LineGeometry: Equatable {
    public let lineIndex: Int
    public let y: Double
    public let height: Double

    public init(lineIndex: Int, y: Double, height: Double) {
        self.lineIndex = lineIndex
        self.y = y
        self.height = height
    }
}

public enum ViewportValidationError: Equatable {
    case negativeLineCount
    case nonPositiveLineHeight
    case negativeViewportHeight
    case negativeOverscan
}

public enum ViewportComputation: Equatable {
    case success(VirtualRange)
    case failure(ViewportValidationError)
}
```

- [ ] **Step 4: Run tests to verify value types pass**

Run:

```bash
swift test --filter ViewportInputValueTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/TextEngineCore/ViewportTypes.swift Tests/TextEngineCoreTests/ViewportInputValueTests.swift
git commit -m "feat: add viewport value types"
```

## Task 2: Validation And Empty Document Behavior

**Files:**
- Create: `Tests/TextEngineCoreTests/ViewportValidationTests.swift`
- Create: `Sources/TextEngineCore/ViewportVirtualizer.swift`

- [ ] **Step 1: Write failing validation tests**

Create `Tests/TextEngineCoreTests/ViewportValidationTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ViewportValidationTests: XCTestCase {
    func testNegativeLineCountFails() {
        let input = ViewportInput(
            lineCount: -1,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: 50.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(ViewportVirtualizer.compute(input), .failure(.negativeLineCount))
    }

    func testNonPositiveLineHeightFails() {
        let input = ViewportInput(
            lineCount: 10,
            lineHeight: 0.0,
            scrollOffsetY: 0.0,
            viewportHeight: 50.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(ViewportVirtualizer.compute(input), .failure(.nonPositiveLineHeight))
    }

    func testNegativeViewportHeightFails() {
        let input = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: -1.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(ViewportVirtualizer.compute(input), .failure(.negativeViewportHeight))
    }

    func testNegativeOverscanFails() {
        let beforeInput = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: 50.0,
            overscanLinesBefore: -1,
            overscanLinesAfter: 0
        )
        let afterInput = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: 50.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: -1
        )

        XCTAssertEqual(ViewportVirtualizer.compute(beforeInput), .failure(.negativeOverscan))
        XCTAssertEqual(ViewportVirtualizer.compute(afterInput), .failure(.negativeOverscan))
    }

    func testEmptyDocumentReturnsEmptyRange() {
        let input = ViewportInput(
            lineCount: 0,
            lineHeight: 10.0,
            scrollOffsetY: 100.0,
            viewportHeight: 50.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
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
}
```

- [ ] **Step 2: Run validation tests to verify the virtualizer is missing**

Run:

```bash
swift test --filter ViewportValidationTests
```

Expected: FAIL because `ViewportVirtualizer` does not exist.

- [ ] **Step 3: Implement validation and empty document behavior**

Create `Sources/TextEngineCore/ViewportVirtualizer.swift`:

```swift
public enum ViewportVirtualizer {
    public static func compute(_ input: ViewportInput) -> ViewportComputation {
        if input.lineCount < 0 {
            return .failure(.negativeLineCount)
        }
        if input.lineHeight <= 0.0 {
            return .failure(.nonPositiveLineHeight)
        }
        if input.viewportHeight < 0.0 {
            return .failure(.negativeViewportHeight)
        }
        if input.overscanLinesBefore < 0 || input.overscanLinesAfter < 0 {
            return .failure(.negativeOverscan)
        }
        if input.lineCount == 0 {
            return .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 0,
                    bufferStart: 0,
                    bufferEndExclusive: 0,
                    isAtTop: true,
                    isAtBottom: true
                )
            )
        }

        return .success(
            VirtualRange(
                visibleStart: 0,
                visibleEndExclusive: 0,
                bufferStart: 0,
                bufferEndExclusive: 0,
                isAtTop: true,
                isAtBottom: false
            )
        )
    }
}
```

- [ ] **Step 4: Run validation tests to verify they pass**

Run:

```bash
swift test --filter ViewportValidationTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/ViewportVirtualizer.swift Tests/TextEngineCoreTests/ViewportValidationTests.swift
git commit -m "feat: validate viewport input"
```

## Task 3: Fixed-Height Visible Range Calculation

**Files:**
- Create: `Tests/TextEngineCoreTests/ViewportRangeTests.swift`
- Modify: `Sources/TextEngineCore/ViewportVirtualizer.swift`

- [ ] **Step 1: Write failing visible range tests**

Create `Tests/TextEngineCoreTests/ViewportRangeTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ViewportRangeTests: XCTestCase {
    func testSublineOffsetUsesFloorForStartAndCeilForEnd() {
        let input = ViewportInput(
            lineCount: 100,
            lineHeight: 10.0,
            scrollOffsetY: 25.0,
            viewportHeight: 35.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 2,
                    visibleEndExclusive: 6,
                    bufferStart: 2,
                    bufferEndExclusive: 6,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testNegativeScrollOffsetClampsToTop() {
        let input = ViewportInput(
            lineCount: 100,
            lineHeight: 10.0,
            scrollOffsetY: -12.0,
            viewportHeight: 20.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 2,
                    bufferStart: 0,
                    bufferEndExclusive: 2,
                    isAtTop: true,
                    isAtBottom: false
                )
            )
        )
    }

    func testViewportLargerThanDocumentReturnsWholeDocument() {
        let input = ViewportInput(
            lineCount: 3,
            lineHeight: 10.0,
            scrollOffsetY: 40.0,
            viewportHeight: 100.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 3,
                    bufferStart: 0,
                    bufferEndExclusive: 3,
                    isAtTop: true,
                    isAtBottom: true
                )
            )
        )
    }

    func testZeroHeightViewportProducesEmptyRangeAtOffset() {
        let input = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 20.0,
            viewportHeight: 0.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
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
}
```

- [ ] **Step 2: Run visible range tests to verify the stub fails**

Run:

```bash
swift test --filter ViewportRangeTests
```

Expected: FAIL because non-empty documents currently return an empty range at the top.

- [ ] **Step 3: Implement fixed-height range calculation without overscan expansion**

Replace `Sources/TextEngineCore/ViewportVirtualizer.swift` with:

```swift
public enum ViewportVirtualizer {
    public static func compute(_ input: ViewportInput) -> ViewportComputation {
        if input.lineCount < 0 {
            return .failure(.negativeLineCount)
        }
        if input.lineHeight <= 0.0 {
            return .failure(.nonPositiveLineHeight)
        }
        if input.viewportHeight < 0.0 {
            return .failure(.negativeViewportHeight)
        }
        if input.overscanLinesBefore < 0 || input.overscanLinesAfter < 0 {
            return .failure(.negativeOverscan)
        }
        if input.lineCount == 0 {
            return .success(emptyRange())
        }

        let effectiveOffsetY = clampedScrollOffsetY(
            scrollOffsetY: input.scrollOffsetY,
            lineCount: input.lineCount,
            lineHeight: input.lineHeight,
            viewportHeight: input.viewportHeight
        )
        let visibleStart = clampedIndex(
            Int((effectiveOffsetY / input.lineHeight).rounded(.down)),
            lineCount: input.lineCount
        )
        let visibleEndExclusive = clampedIndex(
            Int(((effectiveOffsetY + input.viewportHeight) / input.lineHeight).rounded(.up)),
            lineCount: input.lineCount
        )
        let maxOffsetY = maximumScrollOffsetY(
            lineCount: input.lineCount,
            lineHeight: input.lineHeight,
            viewportHeight: input.viewportHeight
        )

        return .success(
            VirtualRange(
                visibleStart: visibleStart,
                visibleEndExclusive: visibleEndExclusive,
                bufferStart: visibleStart,
                bufferEndExclusive: visibleEndExclusive,
                isAtTop: effectiveOffsetY == 0.0,
                isAtBottom: effectiveOffsetY == maxOffsetY
            )
        )
    }

    private static func emptyRange() -> VirtualRange {
        VirtualRange(
            visibleStart: 0,
            visibleEndExclusive: 0,
            bufferStart: 0,
            bufferEndExclusive: 0,
            isAtTop: true,
            isAtBottom: true
        )
    }

    private static func clampedScrollOffsetY(
        scrollOffsetY: Double,
        lineCount: Int,
        lineHeight: Double,
        viewportHeight: Double
    ) -> Double {
        let maxOffsetY = maximumScrollOffsetY(
            lineCount: lineCount,
            lineHeight: lineHeight,
            viewportHeight: viewportHeight
        )
        if scrollOffsetY < 0.0 {
            return 0.0
        }
        if scrollOffsetY > maxOffsetY {
            return maxOffsetY
        }
        return scrollOffsetY
    }

    private static func maximumScrollOffsetY(
        lineCount: Int,
        lineHeight: Double,
        viewportHeight: Double
    ) -> Double {
        let documentHeight = Double(lineCount) * lineHeight
        let maxOffsetY = documentHeight - viewportHeight
        if maxOffsetY < 0.0 {
            return 0.0
        }
        return maxOffsetY
    }

    private static func clampedIndex(_ index: Int, lineCount: Int) -> Int {
        if index < 0 {
            return 0
        }
        if index > lineCount {
            return lineCount
        }
        return index
    }
}
```

- [ ] **Step 4: Run validation and range tests**

Run:

```bash
swift test --filter ViewportValidationTests
swift test --filter ViewportRangeTests
```

Expected: PASS for both commands.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/ViewportVirtualizer.swift Tests/TextEngineCoreTests/ViewportRangeTests.swift
git commit -m "feat: compute fixed height visible range"
```

## Task 4: Overscan, Clamping, And Large-Document Invariants

**Files:**
- Create: `Tests/TextEngineCoreTests/ViewportOverscanInvariantTests.swift`
- Modify: `Sources/TextEngineCore/ViewportVirtualizer.swift`

- [ ] **Step 1: Write failing overscan and invariant tests**

Create `Tests/TextEngineCoreTests/ViewportOverscanInvariantTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ViewportOverscanInvariantTests: XCTestCase {
    func testOverscanExpandsBufferedRange() {
        let input = ViewportInput(
            lineCount: 100,
            lineHeight: 10.0,
            scrollOffsetY: 50.0,
            viewportHeight: 20.0,
            overscanLinesBefore: 2,
            overscanLinesAfter: 3
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 5,
                    visibleEndExclusive: 7,
                    bufferStart: 3,
                    bufferEndExclusive: 10,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testOverscanClampsAtTopAndBottom() {
        let topInput = ViewportInput(
            lineCount: 4,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: 10.0,
            overscanLinesBefore: 50,
            overscanLinesAfter: 1
        )
        let bottomInput = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 999.0,
            viewportHeight: 30.0,
            overscanLinesBefore: 1,
            overscanLinesAfter: 50
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(topInput),
            .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 1,
                    bufferStart: 0,
                    bufferEndExclusive: 2,
                    isAtTop: true,
                    isAtBottom: false
                )
            )
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(bottomInput),
            .success(
                VirtualRange(
                    visibleStart: 7,
                    visibleEndExclusive: 10,
                    bufferStart: 6,
                    bufferEndExclusive: 10,
                    isAtTop: false,
                    isAtBottom: true
                )
            )
        )
    }

    func testGeneratedInputsStayInBounds() {
        let lineCounts = [0, 1, 2, 10, 100_000, 1_000_000]
        let lineHeights = [1.0, 10.0, 17.5]
        let viewportHeights = [0.0, 1.0, 25.0, 1_000.0]
        let offsets = [-100.0, 0.0, 0.5, 10.0, 999_999.0]
        let overscans = [(0, 0), (1, 2), (50, 50)]

        for lineCount in lineCounts {
            for lineHeight in lineHeights {
                for viewportHeight in viewportHeights {
                    for offset in offsets {
                        for overscan in overscans {
                            let input = ViewportInput(
                                lineCount: lineCount,
                                lineHeight: lineHeight,
                                scrollOffsetY: offset,
                                viewportHeight: viewportHeight,
                                overscanLinesBefore: overscan.0,
                                overscanLinesAfter: overscan.1
                            )

                            guard case let .success(range) = ViewportVirtualizer.compute(input) else {
                                XCTFail("Valid generated input failed: \(input)")
                                return
                            }

                            XCTAssertGreaterThanOrEqual(range.visibleStart, 0)
                            XCTAssertLessThanOrEqual(range.visibleStart, range.visibleEndExclusive)
                            XCTAssertLessThanOrEqual(range.visibleEndExclusive, lineCount)
                            XCTAssertGreaterThanOrEqual(range.bufferStart, 0)
                            XCTAssertLessThanOrEqual(range.bufferStart, range.bufferEndExclusive)
                            XCTAssertLessThanOrEqual(range.bufferEndExclusive, lineCount)
                            XCTAssertLessThanOrEqual(range.bufferStart, range.visibleStart)
                            XCTAssertLessThanOrEqual(range.visibleEndExclusive, range.bufferEndExclusive)
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run overscan tests to verify buffer expansion fails**

Run:

```bash
swift test --filter ViewportOverscanInvariantTests
```

Expected: FAIL because `bufferStart` and `bufferEndExclusive` currently equal the visible range.

- [ ] **Step 3: Implement overscan expansion**

Replace the return block in `Sources/TextEngineCore/ViewportVirtualizer.swift` with:

```swift
        let bufferStart = clampedIndex(
            visibleStart - input.overscanLinesBefore,
            lineCount: input.lineCount
        )
        let bufferEndExclusive = clampedIndex(
            visibleEndExclusive + input.overscanLinesAfter,
            lineCount: input.lineCount
        )

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

The full non-empty path in `compute(_:)` should now calculate `bufferStart` and `bufferEndExclusive` after `maxOffsetY`.

- [ ] **Step 4: Run the full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/ViewportVirtualizer.swift Tests/TextEngineCoreTests/ViewportOverscanInvariantTests.swift
git commit -m "feat: apply viewport overscan"
```

## Task 5: Buffered Line Geometry Cursor

**Files:**
- Create: `Tests/TextEngineCoreTests/LineGeometryCursorTests.swift`
- Create: `Sources/TextEngineCore/LineGeometryCursor.swift`

- [ ] **Step 1: Write failing geometry cursor tests**

Create `Tests/TextEngineCoreTests/LineGeometryCursorTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class LineGeometryCursorTests: XCTestCase {
    func testCursorYieldsOnlyBufferedLines() {
        let range = VirtualRange(
            visibleStart: 5,
            visibleEndExclusive: 7,
            bufferStart: 3,
            bufferEndExclusive: 6,
            isAtTop: false,
            isAtBottom: false
        )

        var cursor = ViewportVirtualizer.geometry(for: range, lineHeight: 10.0)
        var output: [LineGeometry] = []
        while let geometry = cursor.next() {
            output.append(geometry)
        }

        XCTAssertEqual(
            output,
            [
                LineGeometry(lineIndex: 3, y: 30.0, height: 10.0),
                LineGeometry(lineIndex: 4, y: 40.0, height: 10.0),
                LineGeometry(lineIndex: 5, y: 50.0, height: 10.0)
            ]
        )
    }

    func testCursorForEmptyRangeYieldsNoGeometry() {
        let range = VirtualRange(
            visibleStart: 0,
            visibleEndExclusive: 0,
            bufferStart: 0,
            bufferEndExclusive: 0,
            isAtTop: true,
            isAtBottom: true
        )

        var cursor = ViewportVirtualizer.geometry(for: range, lineHeight: 10.0)

        XCTAssertNil(cursor.next())
    }
}
```

- [ ] **Step 2: Run geometry tests to verify cursor API is missing**

Run:

```bash
swift test --filter LineGeometryCursorTests
```

Expected: FAIL because `ViewportVirtualizer.geometry(for:lineHeight:)` does not exist.

- [ ] **Step 3: Implement the allocation-free cursor**

Create `Sources/TextEngineCore/LineGeometryCursor.swift`:

```swift
public struct LineGeometryCursor {
    private var nextLineIndex: Int
    private let endExclusive: Int
    private let lineHeight: Double

    public init(bufferStart: Int, bufferEndExclusive: Int, lineHeight: Double) {
        self.nextLineIndex = bufferStart
        self.endExclusive = bufferEndExclusive
        self.lineHeight = lineHeight
    }

    public mutating func next() -> LineGeometry? {
        if nextLineIndex >= endExclusive {
            return nil
        }

        let lineIndex = nextLineIndex
        nextLineIndex += 1

        return LineGeometry(
            lineIndex: lineIndex,
            y: Double(lineIndex) * lineHeight,
            height: lineHeight
        )
    }
}

extension ViewportVirtualizer {
    public static func geometry(for range: VirtualRange, lineHeight: Double) -> LineGeometryCursor {
        LineGeometryCursor(
            bufferStart: range.bufferStart,
            bufferEndExclusive: range.bufferEndExclusive,
            lineHeight: lineHeight
        )
    }
}
```

- [ ] **Step 4: Run the full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/LineGeometryCursor.swift Tests/TextEngineCoreTests/LineGeometryCursorTests.swift
git commit -m "feat: add buffered geometry cursor"
```

## Task 6: Headless Benchmark Executable

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Add the benchmark executable target**

Replace `Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTextEngine",
    products: [
        .library(name: "TextEngineCore", targets: ["TextEngineCore"]),
        .executable(name: "ViewportBenchmarks", targets: ["ViewportBenchmarks"])
    ],
    targets: [
        .target(name: "TextEngineCore"),
        .executableTarget(
            name: "ViewportBenchmarks",
            dependencies: ["TextEngineCore"]
        ),
        .testTarget(
            name: "TextEngineCoreTests",
            dependencies: ["TextEngineCore"]
        )
    ]
)
```

- [ ] **Step 2: Create benchmark executable**

Create `Sources/ViewportBenchmarks/main.swift`:

```swift
import TextEngineCore

struct BenchmarkScenario {
    let name: String
    let lineCount: Int
    let lineHeight: Double
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
}

struct BenchmarkSummary {
    let scenarioName: String
    let p95Nanoseconds: Int64
    let p99Nanoseconds: Int64
    let checksum: Int
}

func nanoseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    return components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
}

func percentile(_ sortedSamples: [Int64], numerator: Int, denominator: Int) -> Int64 {
    if sortedSamples.isEmpty {
        return 0
    }
    let index = (sortedSamples.count - 1) * numerator / denominator
    return sortedSamples[index]
}

@inline(never)
func runScenario(_ scenario: BenchmarkScenario, iterations: Int) -> BenchmarkSummary {
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    let documentHeight = Double(scenario.lineCount) * scenario.lineHeight
    let maxOffset = documentHeight > scenario.viewportHeight
        ? documentHeight - scenario.viewportHeight
        : 0.0

    for iteration in 0..<iterations {
        let fraction = Double((iteration * 37) % 1_000) / 1_000.0
        let offset = maxOffset * fraction
        let input = ViewportInput(
            lineCount: scenario.lineCount,
            lineHeight: scenario.lineHeight,
            scrollOffsetY: offset,
            viewportHeight: scenario.viewportHeight,
            overscanLinesBefore: scenario.overscanBefore,
            overscanLinesAfter: scenario.overscanAfter
        )

        let start = clock.now
        let result = ViewportVirtualizer.compute(input)
        let elapsed = start.duration(to: clock.now)

        switch result {
        case let .success(range):
            checksum &+= range.visibleStart
            checksum &+= range.visibleEndExclusive
            checksum &+= range.bufferStart
            checksum &+= range.bufferEndExclusive
        case .failure:
            checksum &-= 1
        }

        samples.append(nanoseconds(elapsed))
    }

    samples.sort()

    return BenchmarkSummary(
        scenarioName: scenario.name,
        p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
        p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
        checksum: checksum
    )
}

let scenarios = [
    BenchmarkScenario(
        name: "1k_lines_20_visible_overscan_0",
        lineCount: 1_000,
        lineHeight: 16.0,
        viewportHeight: 20.0 * 16.0,
        overscanBefore: 0,
        overscanAfter: 0
    ),
    BenchmarkScenario(
        name: "100k_lines_80_visible_overscan_5",
        lineCount: 100_000,
        lineHeight: 16.0,
        viewportHeight: 80.0 * 16.0,
        overscanBefore: 5,
        overscanAfter: 5
    ),
    BenchmarkScenario(
        name: "1m_lines_200_visible_overscan_50",
        lineCount: 1_000_000,
        lineHeight: 16.0,
        viewportHeight: 200.0 * 16.0,
        overscanBefore: 50,
        overscanAfter: 50
    )
]

let iterations = 10_000

for scenario in scenarios {
    let summary = runScenario(scenario, iterations: iterations)
    print(
        "scenario=\(summary.scenarioName) iterations=\(iterations) p95_ns=\(summary.p95Nanoseconds) p99_ns=\(summary.p99Nanoseconds) checksum=\(summary.checksum)"
    )
}
```

- [ ] **Step 3: Run benchmark executable in release mode**

Run:

```bash
swift run -c release ViewportBenchmarks
```

Expected: PASS and print one line per scenario containing `p95_ns=` and `p99_ns=`.

- [ ] **Step 4: Run tests after adding benchmark target**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ViewportBenchmarks/main.swift
git commit -m "perf: add viewport benchmark executable"
```

## Task 7: Verification Record

**Files:**
- Create: `docs/superpowers/verification/2026-05-31-headless-fixed-height-viewport-virtualization.md`

- [ ] **Step 1: Run verification commands**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks
```

Expected:

- `swift test`: PASS.
- `swift build -c release`: PASS.
- `swift run -c release ViewportBenchmarks`: PASS and prints p95/p99 latency lines.

- [ ] **Step 2: Create compile and benchmark verification record**

Create `docs/superpowers/verification/2026-05-31-headless-fixed-height-viewport-virtualization.md`:

```markdown
# Headless Fixed-Height Viewport Virtualization Verification

Date: 2026-05-31

## Commands

- `swift test`: pass
- `swift build -c release`: pass
- `swift run -c release ViewportBenchmarks`: pass

## Swift Embedded-Sensitive Choices

- `TextEngineCore` public API uses `Int`, `Double`, public structs, and enums.
- `TextEngineCore` does not import Foundation.
- Geometry generation uses `LineGeometryCursor` instead of `Sequence` conformance.
- `ContinuousClock` is used only in the benchmark executable target.

## Target Verification

- Host SwiftPM build: verified by `swift test` and `swift build -c release`.
- iOS source compatibility: blocked until an iOS SDK build command is configured for this repository.
- WASM source compatibility: blocked until a Swift WASM SDK or `wasm32-unknown-wasi` toolchain is configured for this repository.
```

- [ ] **Step 3: Add actual benchmark output to the verification record**

After `swift run -c release ViewportBenchmarks` completes, add a `## Benchmark Output` section between `## Commands` and `## Swift Embedded-Sensitive Choices` in `docs/superpowers/verification/2026-05-31-headless-fixed-height-viewport-virtualization.md`. The section must contain one fenced text block with the three `scenario=` stdout lines from the current benchmark run.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/verification/2026-05-31-headless-fixed-height-viewport-virtualization.md
git commit -m "docs: record viewport verification"
```

## Final Check

- [ ] **Step 1: Run complete verification**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks
git status --short
```

Expected:

- all Swift commands pass
- benchmark output includes p95 and p99 for 1k, 100k, and 1M line scenarios
- `git status --short` prints no tracked-file changes
