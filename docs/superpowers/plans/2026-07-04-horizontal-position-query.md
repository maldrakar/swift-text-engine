# Horizontal Position-Query (`columnAt`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ViewportVirtualizer.columnAt(x:inLine:metrics:)` — the horizontal within-line inverse query (x → cell) over a new `LineHorizontalMetricsSource`, the faithful structural mirror of the vertical `lineAt`.

**Architecture:** A new standalone core protocol supplies each line's cell count and cumulative x-offsets; a stateless public query runs the same validation ladder and half-open/clamp semantics as `lineAt`, dispatching the in-range search through a provider-overridable `columnIndex` hook (binary-search default). A core `UniformColumnMetrics` provider drives the equivalence oracle; a `PrefixSumColumnMetrics` reference provider covers the realistic non-uniform case; a `--column-query` local benchmark gate follows the established rhythm.

**Tech Stack:** Swift 6.0 (`swift-tools-version: 6.0`), XCTest, SwiftPM. `TextEngineCore` (library), `TextEngineReferenceProviders` (library), `ViewportBenchmarks` (executable).

## Global Constraints

Copied verbatim from the spec and `AGENTS.md`; every task's requirements implicitly include these:

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` and `Sources/TextEngineReferenceProviders` must both be empty (exit 1).
- **Swift Embedded compatible.** Only `Int` / `Double` / generics-over-a-protocol — identical footprint to `lineAt`. No Foundation types in any public API.
- **Zero-dependency.** No third-party packages.
- **Compiles for iOS and WASM with no source changes.** Both new providers must cross-compile.
- **Core-owned memory must not grow linearly with document size.** `UniformColumnMetrics` stores no per-line data; `PrefixSumColumnMetrics` per-line storage lives in `TextEngineReferenceProviders` (provider-side, outside the core-memory invariant).
- **`columnAt` is stateless, return-based (no `throws`), O(log M) queries / O(1) core memory**, reusing the shared `ViewportValidationError`.
- **`inLine` is a documented precondition, not validated.** The source carries no `lineCount`.
- **Cell model, visual (left-to-right) order.** A cell is a positive-advance, caret-positionable unit; `columnIndex` is a *visual* index.
- **TDD failing-first; one logical step per commit; conventional-commit prefixes** (`feat:`, `test:`, `docs:`).
- **XCTest only.** `swift test` also prints a "0 tests in 0 suites" line for the empty Swift Testing harness — not a failure.
- **Branch:** all work on `slice-33-horizontal-position-query` (already created; spec already committed as `49853db`).

Spec: `docs/superpowers/specs/2026-07-04-horizontal-position-query-design.md`.

---

### Task 1: `LineHorizontalMetricsSource` protocol + `UniformColumnMetrics` + binary search

**Files:**
- Create: `Sources/TextEngineCore/LineHorizontalMetricsSource.swift`
- Test: `Tests/TextEngineCoreTests/LineHorizontalMetricsSourceTests.swift`

**Interfaces:**
- Consumes: nothing (new leaf).
- Produces:
  - `protocol LineHorizontalMetricsSource { func columnCount(inLine: Int) -> Int; func columnOffset(inLine: Int, column: Int) -> Double; func columnIndex(containingOffset: Double, inLine: Int) -> Int }` with a default `columnIndex` extension.
  - `func binarySearchColumnIndex<Metrics: LineHorizontalMetricsSource>(containingOffset: Double, metrics: Metrics, inLine: Int, columnCount: Int) -> Int` (internal).
  - `struct UniformColumnMetrics: LineHorizontalMetricsSource { init(columnsPerLine: Int, columnWidth: Double) }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TextEngineCoreTests/LineHorizontalMetricsSourceTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class LineHorizontalMetricsSourceTests: XCTestCase {
    func testUniformColumnCountIsConstantPerLine() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        XCTAssertEqual(metrics.columnCount(inLine: 0), 10)
        XCTAssertEqual(metrics.columnCount(inLine: 5), 10)
    }

    func testUniformColumnOffsetIsProductOfWidth() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 0), 0.0)
        XCTAssertEqual(metrics.columnOffset(inLine: 3, column: 4), 32.0)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 10), 80.0) // total width
    }

    func testDefaultColumnIndexReturnsContainingCell() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        // half-open: [16, 24) is cell 2
        XCTAssertEqual(metrics.columnIndex(containingOffset: 20.0, inLine: 0), 2)
        XCTAssertEqual(metrics.columnIndex(containingOffset: 16.0, inLine: 0), 2) // exact boundary -> right cell
        XCTAssertEqual(metrics.columnIndex(containingOffset: 0.0, inLine: 0), 0)
        XCTAssertEqual(metrics.columnIndex(containingOffset: 79.9, inLine: 0), 9) // last cell
    }

    private struct ManualColumnMetrics: LineHorizontalMetricsSource {
        let offsets: [Double] // one line's cumulative offsets, offsets[0] == 0
        func columnCount(inLine line: Int) -> Int { offsets.count - 1 }
        func columnOffset(inLine line: Int, column: Int) -> Double { offsets[column] }
    }

    func testBinarySearchColumnIndexOverNonUniformOffsets() {
        // advances [10,30,5,50] -> offsets [0,10,40,45,95]
        let metrics = ManualColumnMetrics(offsets: [0.0, 10.0, 40.0, 45.0, 95.0])
        XCTAssertEqual(binarySearchColumnIndex(containingOffset: 5.0, metrics: metrics, inLine: 0, columnCount: 4), 0)
        XCTAssertEqual(binarySearchColumnIndex(containingOffset: 40.0, metrics: metrics, inLine: 0, columnCount: 4), 2)
        XCTAssertEqual(binarySearchColumnIndex(containingOffset: 44.0, metrics: metrics, inLine: 0, columnCount: 4), 2)
        XCTAssertEqual(binarySearchColumnIndex(containingOffset: 94.0, metrics: metrics, inLine: 0, columnCount: 4), 3)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LineHorizontalMetricsSourceTests`
Expected: FAIL — compile error, `cannot find 'UniformColumnMetrics'` / `cannot find 'LineHorizontalMetricsSource'` / `cannot find 'binarySearchColumnIndex'`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/TextEngineCore/LineHorizontalMetricsSource.swift`:

```swift
public protocol LineHorizontalMetricsSource {
    /// Number of cells in `line`. A blank line has 0. (mirror of `lineCount`)
    func columnCount(inLine line: Int) -> Int

    /// Cumulative left offset (x) of cell `column` within `line`, in layout units.
    ///
    /// Domain: `0...columnCount(inLine: line)`.
    /// `columnOffset(inLine: l, column: 0) == 0`, and
    /// `columnOffset(inLine: l, column: columnCount(inLine: l))` is that line's
    /// total advance width.
    ///
    /// Contract precondition: for every `c` in `0..<columnCount(inLine: line)`,
    /// `columnOffset(_, column: c)` and `columnOffset(_, column: c + 1)` are finite
    /// and strictly increasing. Raw glyph advances can be zero (combining marks,
    /// ZWJ, ligature components), so the provider must fold zero-advance glyphs into
    /// their base cell to honour this; a *cell* is a positive-advance,
    /// caret-positionable unit in visual (left-to-right) order. The core never
    /// queries outside `0...columnCount(inLine: line)`.
    ///
    /// Stability precondition: `columnCount(inLine:)` and `columnOffset(inLine:column:)`
    /// for a given line must be stable for one `columnAt` query.
    func columnOffset(inLine line: Int, column: Int) -> Double

    /// Provider-native inverse-search hook (mirror of `lineIndex(containingOffset:)`).
    /// Returns the cell whose half-open span
    /// `[columnOffset(_, c), columnOffset(_, c+1))` contains `x`.
    ///
    /// Preconditions: `columnCount(inLine: line) > 0`,
    /// `columnOffset(_, column: 0) == 0`, `x` finite in `[0, lineWidth)`, same stable
    /// snapshot. Does not validate or clamp; public query semantics stay centralized
    /// in `ViewportVirtualizer.columnAt(x:inLine:metrics:)`.
    func columnIndex(containingOffset x: Double, inLine line: Int) -> Int
}

extension LineHorizontalMetricsSource {
    public func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
        binarySearchColumnIndex(
            containingOffset: x, metrics: self,
            inLine: line, columnCount: columnCount(inLine: line)
        )
    }
}

// Largest c in [0, columnCount) with columnOffset(c) <= target (the cell whose
// half-open span contains target). Identical shape to binarySearchLineIndex, with
// the inLine/column addressing. Shared by the default columnIndex hook.
func binarySearchColumnIndex<Metrics: LineHorizontalMetricsSource>(
    containingOffset target: Double,
    metrics: Metrics,
    inLine line: Int,
    columnCount: Int
) -> Int {
    var low = 0
    var high = columnCount - 1
    var result = 0
    while low <= high {
        let mid = low + (high - low) / 2
        if metrics.columnOffset(inLine: line, column: mid) <= target {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    return result
}

/// Uniform-grid horizontal metrics — the faithful mirror of `UniformLineMetrics`,
/// placed in the core so the `ColumnAt*` equivalence oracle in `TextEngineCoreTests`
/// can drive it without a reference-provider dependency. O(1) metric, no per-line
/// storage. Uses the binary-search default for the inverse (no `columnIndex`
/// override).
public struct UniformColumnMetrics: LineHorizontalMetricsSource {
    public let columnsPerLine: Int
    public let columnWidth: Double

    public init(columnsPerLine: Int, columnWidth: Double) {
        self.columnsPerLine = columnsPerLine
        self.columnWidth = columnWidth
    }

    public func columnCount(inLine line: Int) -> Int { columnsPerLine }
    public func columnOffset(inLine line: Int, column: Int) -> Double {
        Double(column) * columnWidth
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LineHorizontalMetricsSourceTests`
Expected: PASS — the 4 tests succeed (plus the "0 tests in 0 suites" Swift Testing line).

- [ ] **Step 5: Verify Foundation-free**

Run: `rg -n "Foundation" Sources/TextEngineCore`
Expected: no matches, exit 1.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextEngineCore/LineHorizontalMetricsSource.swift Tests/TextEngineCoreTests/LineHorizontalMetricsSourceTests.swift
git commit -m "feat: add LineHorizontalMetricsSource protocol and UniformColumnMetrics

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `columnAt` query + result types + core behavior tests

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (add result types + two error cases)
- Create: `Sources/TextEngineCore/HorizontalPositionQuery.swift`
- Test: `Tests/TextEngineCoreTests/ColumnAtTests.swift`

**Interfaces:**
- Consumes: `LineHorizontalMetricsSource`, `UniformColumnMetrics` (Task 1); existing `ViewportVirtualizer`, `ViewportValidationError`.
- Produces:
  - `enum ColumnQuery: Equatable { case column(ColumnLocation); case empty; case failure(ViewportValidationError) }`.
  - `struct ColumnLocation: Equatable { let columnIndex: Int; let clamp: Clamp; init(columnIndex: Int, clamp: Clamp); enum Clamp: Equatable { case inRange, clampedToLeft, clampedToRight } }`.
  - `ViewportValidationError` gains `case negativeColumnCount`, `case invalidColumnMetrics`.
  - `static func ViewportVirtualizer.columnAt<Metrics: LineHorizontalMetricsSource>(x: Double, inLine: Int, metrics: Metrics) -> ColumnQuery`.

- [ ] **Step 1: Add the result types and error cases (so the test can compile)**

In `Sources/TextEngineCore/ViewportTypes.swift`, add the two new cases to `ViewportValidationError`. Change:

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

to:

```swift
public enum ViewportValidationError: Equatable {
    case negativeLineCount
    case nonFiniteValue
    case nonPositiveLineHeight
    case negativeViewportHeight
    case negativeOverscan
    case invalidLineMetrics
    case negativeColumnCount
    case invalidColumnMetrics
}
```

Then, at the end of `Sources/TextEngineCore/ViewportTypes.swift`, append the query result vocabulary beside the existing `LineQuery` / `LineGeometryQuery`:

```swift
public enum ColumnQuery: Equatable {
    case column(ColumnLocation)           // a real cell was located
    case empty                            // blank line: columnCount(inLine:) == 0
    case failure(ViewportValidationError) // invalid input / metrics
}

public struct ColumnLocation: Equatable {
    public let columnIndex: Int
    public let clamp: Clamp

    public init(columnIndex: Int, clamp: Clamp) {
        self.columnIndex = columnIndex
        self.clamp = clamp
    }

    public enum Clamp: Equatable {
        case inRange          // x was inside [0, lineWidth)
        case clampedToLeft    // x < 0;          resolved to cell 0
        case clampedToRight   // x >= lineWidth;  resolved to last cell
    }
}
```

- [ ] **Step 2: Write the failing test**

Create `Tests/TextEngineCoreTests/ColumnAtTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ColumnAtTests: XCTestCase {
    // A line-addressable hand-built source. offsetsPerLine[line] is that line's
    // cumulative offsets; offsetsPerLine[line][0] must be 0 for a valid line.
    // An empty inner array yields columnCount == -1 (drives .negativeColumnCount).
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let offsetsPerLine: [[Double]]
        func columnCount(inLine line: Int) -> Int { offsetsPerLine[line].count - 1 }
        func columnOffset(inLine line: Int, column: Int) -> Double { offsetsPerLine[line][column] }
    }

    func testInRangeMidSpan() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 20.0, inLine: 0, metrics: metrics),
            .column(ColumnLocation(columnIndex: 2, clamp: .inRange))
        )
    }

    func testXZeroIsInRangeCellZero() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 0.0, inLine: 0, metrics: metrics),
            .column(ColumnLocation(columnIndex: 0, clamp: .inRange))
        )
    }

    func testExactBoundaryResolvesToRightCell() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 16.0, inLine: 0, metrics: metrics),
            .column(ColumnLocation(columnIndex: 2, clamp: .inRange))
        )
    }

    func testXBelowZeroClampsLeft() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: -1.0, inLine: 0, metrics: metrics),
            .column(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft))
        )
    }

    func testXAtWidthClampsRight() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        // width == 80
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 80.0, inLine: 0, metrics: metrics),
            .column(ColumnLocation(columnIndex: 9, clamp: .clampedToRight))
        )
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 999.0, inLine: 0, metrics: metrics),
            .column(ColumnLocation(columnIndex: 9, clamp: .clampedToRight))
        )
    }

    func testBlankLineIsEmpty() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0]]) // columnCount 0
        for x in [-5.0, 0.0, 12.0] {
            XCTAssertEqual(ViewportVirtualizer.columnAt(x: x, inLine: 0, metrics: metrics), .empty)
        }
    }

    func testNegativeColumnCountFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[]]) // columnCount -1
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 3.0, inLine: 0, metrics: metrics),
            .failure(.negativeColumnCount)
        )
    }

    func testNonFiniteXFails() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        for x in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(
                ViewportVirtualizer.columnAt(x: x, inLine: 0, metrics: metrics),
                .failure(.nonFiniteValue)
            )
        }
    }

    func testFirstOffsetNonZeroFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[5.0, 15.0]]) // columnOffset(_,0) == 5
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 3.0, inLine: 0, metrics: metrics),
            .failure(.invalidColumnMetrics)
        )
    }

    func testZeroWidthFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, 0.0]]) // width 0
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 0.0, inLine: 0, metrics: metrics),
            .failure(.invalidColumnMetrics)
        )
    }

    func testNonFiniteWidthFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, .infinity]])
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 1.0, inLine: 0, metrics: metrics),
            .failure(.invalidColumnMetrics)
        )
    }

    func testNonUniformResolution() {
        // advances [10,30,5,50] -> offsets [0,10,40,45,95], width 95
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, 10.0, 40.0, 45.0, 95.0]])
        let cases: [(Double, Int, ColumnLocation.Clamp)] = [
            (0.0, 0, .inRange), (5.0, 0, .inRange),
            (10.0, 1, .inRange), (39.0, 1, .inRange),
            (40.0, 2, .inRange), (44.0, 2, .inRange),
            (45.0, 3, .inRange), (94.0, 3, .inRange),
            (95.0, 3, .clampedToRight), (-2.0, 0, .clampedToLeft),
        ]
        for (x, cell, clamp) in cases {
            XCTAssertEqual(
                ViewportVirtualizer.columnAt(x: x, inLine: 0, metrics: metrics),
                .column(ColumnLocation(columnIndex: cell, clamp: clamp)),
                "x=\(x)"
            )
        }
    }

    func testSingleCellLine() {
        let metrics = UniformColumnMetrics(columnsPerLine: 1, columnWidth: 8.0)
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: 0.0, inLine: 0, metrics: metrics),
                       .column(ColumnLocation(columnIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: 7.9, inLine: 0, metrics: metrics),
                       .column(ColumnLocation(columnIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: 8.0, inLine: 0, metrics: metrics),
                       .column(ColumnLocation(columnIndex: 0, clamp: .clampedToRight)))
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: -1.0, inLine: 0, metrics: metrics),
                       .column(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft)))
    }

    func testPerLineAddressing() {
        // line 0 offsets [0,10,40,45,95]; line 1 offsets [0,8,16]
        let metrics = ArrayColumnMetrics(offsetsPerLine: [
            [0.0, 10.0, 40.0, 45.0, 95.0],
            [0.0, 8.0, 16.0],
        ])
        // x = 9: line 0 -> cell 0 (0<=9<10); line 1 -> cell 1 (8<=9<16)
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: 9.0, inLine: 0, metrics: metrics),
                       .column(ColumnLocation(columnIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: 9.0, inLine: 1, metrics: metrics),
                       .column(ColumnLocation(columnIndex: 1, clamp: .inRange)))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ColumnAtTests`
Expected: FAIL — compile error, `type 'ViewportVirtualizer' has no member 'columnAt'`.

- [ ] **Step 4: Write minimal implementation**

Create `Sources/TextEngineCore/HorizontalPositionQuery.swift`:

```swift
extension ViewportVirtualizer {
    /// Maps a target `x` within line `inLine` to the cell whose half-open span
    /// `[columnOffset(c), columnOffset(c+1))` contains it — the horizontal mirror
    /// of `lineAt(y:metrics:)`.
    ///
    /// Stateless. The in-range branch dispatches to
    /// `LineHorizontalMetricsSource.columnIndex(containingOffset:inLine:)`; the
    /// default is an O(log M) binary search over `columnOffset`, and a provider may
    /// override it. O(1) core memory. An `x` outside `[0, lineWidth)` resolves to
    /// the nearest cell with `ColumnLocation.clamp` recording the edge. A blank
    /// line (`columnCount == 0`) is `.empty`, not a failure. `inLine` is a
    /// documented precondition (a valid line for the source), not validated.
    public static func columnAt<Metrics: LineHorizontalMetricsSource>(
        x: Double,
        inLine line: Int,
        metrics: Metrics
    ) -> ColumnQuery {
        let count = metrics.columnCount(inLine: line)

        if count < 0 {
            return .failure(.negativeColumnCount)
        }
        if !x.isFinite {
            return .failure(.nonFiniteValue)
        }
        // O(1) contract probe, checked before the empty short-circuit for parity
        // with `lineAt`. Do not reorder.
        if metrics.columnOffset(inLine: line, column: 0) != 0.0 {
            return .failure(.invalidColumnMetrics)
        }
        if count == 0 {
            return .empty
        }
        let width = metrics.columnOffset(inLine: line, column: count)
        if !width.isFinite || width <= 0.0 {
            return .failure(.invalidColumnMetrics)
        }

        if x < 0.0 {
            return .column(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft))
        }
        if x >= width {
            return .column(ColumnLocation(columnIndex: count - 1, clamp: .clampedToRight))
        }

        let index = metrics.columnIndex(containingOffset: x, inLine: line)
        return .column(ColumnLocation(columnIndex: index, clamp: .inRange))
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ColumnAtTests`
Expected: PASS — all `ColumnAtTests` succeed.

- [ ] **Step 6: Run the full suite to confirm the enum-case addition broke nothing**

Run: `swift test`
Expected: PASS — every existing test still green, 0 failures (the only new tests are `LineHorizontalMetricsSourceTests` + `ColumnAtTests`).

- [ ] **Step 7: Commit**

```bash
git add Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/HorizontalPositionQuery.swift Tests/TextEngineCoreTests/ColumnAtTests.swift
git commit -m "feat: add ViewportVirtualizer.columnAt horizontal position query

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Closed-form equivalence oracle

**Files:**
- Test: `Tests/TextEngineCoreTests/ColumnAtEquivalenceTests.swift`

**Interfaces:**
- Consumes: `UniformColumnMetrics`, `ViewportVirtualizer.columnAt`, `ColumnQuery`, `ColumnLocation` (Tasks 1–2).
- Produces: nothing (test-only).

- [ ] **Step 1: Write the failing test**

Create `Tests/TextEngineCoreTests/ColumnAtEquivalenceTests.swift`. The oracle builds every `x` from a **product** over an exactly-representable width, so the expected cell is known by construction (never divided out):

```swift
import XCTest
@testable import TextEngineCore

final class ColumnAtEquivalenceTests: XCTestCase {
    // Exactly-representable widths (no rounding at product boundaries), well under 2^53.
    private let widths: [Double] = [1.0, 8.0, 16.0, 12.5, 256.0]
    private let counts: [Int] = [1, 2, 7, 1000]
    private let lines: [Int] = [0, 3, 9]

    private func expected(x: Double, count: Int, width: Double) -> ColumnQuery {
        // Structural expectation. x is always a product k*width (+width/2), so no
        // division is needed to name the cell.
        if x < 0.0 { return .column(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft)) }
        let totalWidth = Double(count) * width
        if x >= totalWidth { return .column(ColumnLocation(columnIndex: count - 1, clamp: .clampedToRight)) }
        // in-range: derive k by counting products, not dividing.
        var k = 0
        while Double(k + 1) * width <= x { k += 1 }
        return .column(ColumnLocation(columnIndex: k, clamp: .inRange))
    }

    func testUniformColumnAtMatchesStructuralOracle() {
        for width in widths {
            for count in counts {
                let metrics = UniformColumnMetrics(columnsPerLine: count, columnWidth: width)
                for line in lines {
                    var xs: [Double] = [-width, 0.0]
                    for k in Set([0, 1, count / 2, count - 1]) where k >= 0 && k < count {
                        xs.append(Double(k) * width)                    // exact boundary
                        xs.append(Double(k) * width + width / 2)        // mid-span
                    }
                    xs.append(Double(count) * width)                    // exact total width
                    xs.append(Double(count) * width + width)            // past the end
                    for x in xs {
                        XCTAssertEqual(
                            ViewportVirtualizer.columnAt(x: x, inLine: line, metrics: metrics),
                            expected(x: x, count: count, width: width),
                            "width=\(width) count=\(count) line=\(line) x=\(x)"
                        )
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails, then passes**

Run: `swift test --filter ColumnAtEquivalenceTests`
Expected: PASS immediately (the implementation from Task 2 already satisfies the oracle). If any assertion fails, the boundary/clamp logic in `columnAt` diverges from the spec table — fix `columnAt`, not the oracle.

(Note: this task's test exercises only already-shipped behavior, so it is green on first run — a regression guard, not a red-green cycle. That is intentional: the oracle is the load-bearing correctness proof.)

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/ColumnAtEquivalenceTests.swift
git commit -m "test: add columnAt closed-form equivalence oracle

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Query-count / dispatch event-log tests

**Files:**
- Test: `Tests/TextEngineCoreTests/ColumnAtQueryCountTests.swift`

**Interfaces:**
- Consumes: `LineHorizontalMetricsSource`, `UniformColumnMetrics`, `ViewportVirtualizer.columnAt`, `ColumnLocation` (Tasks 1–2).
- Produces: nothing (test-only). Mirrors `LineAtQueryCountTests`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TextEngineCoreTests/ColumnAtQueryCountTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ColumnAtQueryCountTests: XCTestCase {
    private final class QueryCounter {
        var count = 0
    }

    // Counts every columnOffset probe. columnCount is NOT counted (mirrors the
    // vertical CountingLineMetrics, where lineCount is free).
    private struct CountingColumnMetrics: LineHorizontalMetricsSource {
        let base: UniformColumnMetrics
        let counter: QueryCounter

        init(columnsPerLine: Int, columnWidth: Double, counter: QueryCounter) {
            self.base = UniformColumnMetrics(columnsPerLine: columnsPerLine, columnWidth: columnWidth)
            self.counter = counter
        }

        func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.count += 1
            return base.columnOffset(inLine: line, column: column)
        }
    }

    private enum NativeSearchEvent: Equatable {
        case offset(Int, Int)   // (line, column)
        case native(Int, Double) // (line, x)
    }

    private final class NativeSearchCounter {
        var events: [NativeSearchEvent] = []
    }

    // Overrides columnIndex so the in-range path shows a .native event, recording
    // the exact dispatch order (mirror of the vertical NativeSearchMetrics).
    private struct NativeSearchColumnMetrics: LineHorizontalMetricsSource {
        let offsets: [Double] // one line's cumulative offsets
        let counter: NativeSearchCounter

        func columnCount(inLine line: Int) -> Int { offsets.count - 1 }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.events.append(.offset(line, column))
            return offsets[column]
        }
        func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
            counter.events.append(.native(line, x))
            var result = 0
            for index in 0..<(offsets.count - 1) {
                if offsets[index] <= x { result = index } else { break }
            }
            return result
        }
    }

    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value { capacity <<= 1; power += 1 }
        return power
    }

    func testInRangeUsesLogarithmicQueriesAtOneMillionCells() {
        let count = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingColumnMetrics(columnsPerLine: count, columnWidth: 8.0, counter: counter)

        let result = ViewportVirtualizer.columnAt(x: Double(count / 2) * 8.0 + 4.0, inLine: 0, metrics: metrics)

        guard case .column = result else { return XCTFail("expected .column, got \(result)") }
        let expectedMax = 2 + (ceilLog2(count) + 1)
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }

    func testBlankLineQueriesOnlyFirstOffset() {
        // A source whose line has 0 cells: columnCount 0, columnOffset(_,0)==0.
        struct BlankColumnMetrics: LineHorizontalMetricsSource {
            let counter: QueryCounter
            func columnCount(inLine line: Int) -> Int { 0 }
            func columnOffset(inLine line: Int, column: Int) -> Double { counter.count += 1; return 0.0 }
        }
        let counter = QueryCounter()
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: 3.0, inLine: 0, metrics: BlankColumnMetrics(counter: counter)), .empty)
        XCTAssertEqual(counter.count, 1)
    }

    func testClampBranchesDoNotSearch() {
        let count = 1_000_000

        let leftCounter = QueryCounter()
        let leftMetrics = CountingColumnMetrics(columnsPerLine: count, columnWidth: 8.0, counter: leftCounter)
        _ = ViewportVirtualizer.columnAt(x: -1.0, inLine: 0, metrics: leftMetrics)
        XCTAssertEqual(leftCounter.count, 2) // columnOffset(0) + width, no search

        let rightCounter = QueryCounter()
        let rightMetrics = CountingColumnMetrics(columnsPerLine: count, columnWidth: 8.0, counter: rightCounter)
        _ = ViewportVirtualizer.columnAt(x: Double(count) * 8.0 + 1.0, inLine: 0, metrics: rightMetrics)
        XCTAssertEqual(rightCounter.count, 2)
    }

    func testNonFiniteXDoesNotQueryOffsets() {
        let counter = QueryCounter()
        let metrics = CountingColumnMetrics(columnsPerLine: 1_000, columnWidth: 8.0, counter: counter)
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: .nan, inLine: 0, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(counter.count, 0)
    }

    func testInRangeDispatchesToNativeHookAfterValidationProbes() {
        let counter = NativeSearchCounter()
        // offsets [0,10,30,35,80] on line 0; count == 4, width == 80.
        let metrics = NativeSearchColumnMetrics(offsets: [0.0, 10.0, 30.0, 35.0, 80.0], counter: counter)

        let result = ViewportVirtualizer.columnAt(x: 31.0, inLine: 0, metrics: metrics)

        XCTAssertEqual(result, .column(ColumnLocation(columnIndex: 2, clamp: .inRange)))
        XCTAssertEqual(counter.events, [.offset(0, 0), .offset(0, 4), .native(0, 31.0)])
    }

    func testNonInRangePathsNeverDispatchNative() {
        // blank -> [.offset(0,0)] ; clamp -> [.offset(0,0), .offset(0,count)] ; non-finite -> []
        let blankCounter = NativeSearchCounter()
        _ = ViewportVirtualizer.columnAt(x: 5.0, inLine: 0, metrics: NativeSearchColumnMetrics(offsets: [0.0], counter: blankCounter))
        XCTAssertEqual(blankCounter.events, [.offset(0, 0)])

        let clampCounter = NativeSearchCounter()
        _ = ViewportVirtualizer.columnAt(x: -1.0, inLine: 0, metrics: NativeSearchColumnMetrics(offsets: [0.0, 10.0, 30.0, 35.0, 80.0], counter: clampCounter))
        XCTAssertEqual(clampCounter.events, [.offset(0, 0), .offset(0, 4)])

        let nanCounter = NativeSearchCounter()
        _ = ViewportVirtualizer.columnAt(x: .nan, inLine: 0, metrics: NativeSearchColumnMetrics(offsets: [0.0, 10.0], counter: nanCounter))
        XCTAssertEqual(nanCounter.events, [])
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter ColumnAtQueryCountTests`
Expected: PASS — all six tests succeed (the behavior already exists; these prove the cost envelope and dispatch order).

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/ColumnAtQueryCountTests.swift
git commit -m "test: add columnAt query-count and native-dispatch event-log tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `PrefixSumColumnMetrics` reference provider + test

**Files:**
- Create: `Sources/TextEngineReferenceProviders/PrefixSumColumnMetrics.swift`
- Test: `Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift`

**Interfaces:**
- Consumes: `LineHorizontalMetricsSource`, `ViewportVirtualizer.columnAt`, `ColumnLocation` (from `TextEngineCore`).
- Produces: `struct PrefixSumColumnMetrics: LineHorizontalMetricsSource { init(advancesPerLine: [[Double]]) }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift`:

```swift
import XCTest
import TextEngineCore
@testable import TextEngineReferenceProviders

final class PrefixSumColumnMetricsTests: XCTestCase {
    func testBuildsCumulativeOffsets() {
        let metrics = PrefixSumColumnMetrics(advancesPerLine: [[10.0, 30.0, 5.0, 50.0]])
        XCTAssertEqual(metrics.columnCount(inLine: 0), 4)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 0), 0.0)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 2), 40.0)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 4), 95.0) // total width
    }

    func testColumnAtOverPrefixSumMatchesHandBuiltOffsets() {
        // advances [10,30,5,50] -> offsets [0,10,40,45,95]; same vectors as the
        // core ColumnAtTests.testNonUniformResolution, driven through the shipped
        // reference provider.
        let metrics = PrefixSumColumnMetrics(advancesPerLine: [[10.0, 30.0, 5.0, 50.0]])
        let cases: [(Double, Int, ColumnLocation.Clamp)] = [
            (0.0, 0, .inRange), (5.0, 0, .inRange),
            (10.0, 1, .inRange), (40.0, 2, .inRange),
            (44.0, 2, .inRange), (45.0, 3, .inRange),
            (94.0, 3, .inRange), (95.0, 3, .clampedToRight),
            (-2.0, 0, .clampedToLeft),
        ]
        for (x, cell, clamp) in cases {
            XCTAssertEqual(
                ViewportVirtualizer.columnAt(x: x, inLine: 0, metrics: metrics),
                .column(ColumnLocation(columnIndex: cell, clamp: clamp)),
                "x=\(x)"
            )
        }
    }

    func testPerLineAddressing() {
        let metrics = PrefixSumColumnMetrics(advancesPerLine: [[10.0, 30.0], [8.0, 8.0]])
        // line 0 offsets [0,10,40]; line 1 offsets [0,8,16]. x = 9:
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: 9.0, inLine: 0, metrics: metrics),
                       .column(ColumnLocation(columnIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: 9.0, inLine: 1, metrics: metrics),
                       .column(ColumnLocation(columnIndex: 1, clamp: .inRange)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PrefixSumColumnMetricsTests`
Expected: FAIL — compile error, `cannot find 'PrefixSumColumnMetrics'`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/TextEngineReferenceProviders/PrefixSumColumnMetrics.swift`:

```swift
import TextEngineCore

/// Reference variable/proportional horizontal provider — the faithful mirror of
/// `PrefixSumLineMetrics`. Per-line cumulative offsets precomputed as prefix-sum
/// arrays; `columnOffset` is O(1). Provider-side per-line storage lives here,
/// outside the core-memory invariant. Uses the binary-search default for the
/// inverse (no `columnIndex` override — a native descent is a future slice). The
/// realistic non-uniform-advance case for the containing-cell search.
public struct PrefixSumColumnMetrics: LineHorizontalMetricsSource {
    /// One prefix-sum array per line: `prefix[line][c]` is the left offset of cell
    /// `c`, with `prefix[line][0] == 0` and `prefix[line].count == cells + 1`.
    public let prefix: [[Double]]

    /// `advancesPerLine[line]` is that line's per-cell advances (widths).
    public init(advancesPerLine: [[Double]]) {
        prefix = advancesPerLine.map { advances in
            var sums: [Double] = [0.0]
            sums.reserveCapacity(advances.count + 1)
            var running = 0.0
            for advance in advances {
                running += advance
                sums.append(running)
            }
            return sums
        }
    }

    public func columnCount(inLine line: Int) -> Int { prefix[line].count - 1 }
    public func columnOffset(inLine line: Int, column: Int) -> Double {
        prefix[line][column]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PrefixSumColumnMetricsTests`
Expected: PASS — all three tests succeed.

- [ ] **Step 5: Verify Foundation-free**

Run: `rg -n "Foundation" Sources/TextEngineReferenceProviders`
Expected: no matches, exit 1.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextEngineReferenceProviders/PrefixSumColumnMetrics.swift Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift
git commit -m "feat: add PrefixSumColumnMetrics reference provider

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: `--column-query` benchmark mode + local gate

**Files:**
- Create: `Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (enum case, `outputName`, `usage`, `parse`)
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift` (`runBenchmarks` dispatch)
- Modify: `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift` (exhaustive-switch arm)

**Interfaces:**
- Consumes: `UniformColumnMetrics` (core), `PrefixSumColumnMetrics` (reference providers), `ViewportVirtualizer.columnAt`, `ColumnQuery`; existing `BenchmarkSummary`, `BenchmarkOperationResult`, `deterministicScrollOffset`, `percentile`, `nanoseconds`, `formatSummary`.
- Produces: `BenchmarkMode.columnQuery`; `func runColumnQueryBenchmarks(enforceGate: Bool) -> Bool`.

- [ ] **Step 1: Add `.columnQuery` to the mode enum and its `outputName`**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, add the case to `enum BenchmarkMode` after `case lineGeometryQuery`:

```swift
    case lineGeometryQuery
    case columnQuery
    case memoryShape
```

and add its `outputName` arm after the `.lineGeometryQuery` arm:

```swift
        case .lineGeometryQuery:
            return "line_geometry_query"
        case .columnQuery:
            return "column_query"
        case .memoryShape:
            return "memory_shape"
```

- [ ] **Step 2: Add the parse case and usage line**

In the same file, add a parse case after the `--line-geometry-query` block (which ends `mode = .lineGeometryQuery`):

```swift
            case "--column-query":
                if mode != .pipeline {
                    return .failure("--column-query cannot be combined with another mode")
                }
                mode = .columnQuery
```

Add to `usage`, in the `Usage:` line after `[--line-geometry-query]`, insert `[--column-query]`, and add a description line after the `--line-geometry-query` one:

```swift
      --column-query        Run x->cell within-line position-query benchmark. Combine with --gate to enforce budgets.
```

(No change to the `--gate` denylist at `BenchmarkOptions.swift:137` — `.columnQuery` joins the gateable set automatically.)

- [ ] **Step 3: Add the dispatch arm and the exhaustive-switch arm**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, in `runBenchmarks`, add after the `.lineGeometryQuery` arm:

```swift
    case .lineGeometryQuery:
        return runLineGeometryQueryBenchmarks(enforceGate: options.enforceGate)
    case .columnQuery:
        return runColumnQueryBenchmarks(enforceGate: options.enforceGate)
    case .memoryShape:
        return runMemoryShapeDiagnostics()
```

In `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`, in the `switch mode` inside `runScenario`, add after the `.lineGeometryQuery` arm:

```swift
            case .lineGeometryQuery:
                preconditionFailure("line geometry query mode uses runLineGeometryQueryScenario")
            case .columnQuery:
                preconditionFailure("column query mode uses runColumnQueryScenario")
            case .memoryShape:
```

- [ ] **Step 4: Create the benchmark file**

Create `Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift`. Budgets start from the line-query uniform shape (structurally identical work); Step 6 calibrates them:

```swift
import TextEngineCore
import TextEngineReferenceProviders

struct ColumnQueryScenario {
    let name: String
    let providerName: String
    let columnCount: Int
    let useVariableAdvance: Bool
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// Large cell counts exist only to exercise binary-search depth (real lines are
// short). uniform_* use UniformColumnMetrics (core); prefixsum_* use
// PrefixSumColumnMetrics (reference providers) — the realistic proportional case.
// Both answer columnOffset in O(1), so the generic search is O(log M) wall-clock.
func columnQueryScenarios() -> [ColumnQueryScenario] {
    [
        ColumnQueryScenario(name: "uniform_1k", providerName: "uniform",
                            columnCount: 1_000, useVariableAdvance: false,
                            p95BudgetNanoseconds: 30_000, p99BudgetNanoseconds: 60_000),
        ColumnQueryScenario(name: "uniform_100k", providerName: "uniform",
                            columnCount: 100_000, useVariableAdvance: false,
                            p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000),
        ColumnQueryScenario(name: "uniform_1m", providerName: "uniform",
                            columnCount: 1_000_000, useVariableAdvance: false,
                            p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        ColumnQueryScenario(name: "prefixsum_100k", providerName: "prefixsum",
                            columnCount: 100_000, useVariableAdvance: true,
                            p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000),
        ColumnQueryScenario(name: "prefixsum_1m", providerName: "prefixsum",
                            columnCount: 1_000_000, useVariableAdvance: true,
                            p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
    ]
}

// Deterministic positive per-cell advances (mirror of variableHeights).
func variableAdvances(cellCount: Int) -> [Double] {
    var advances: [Double] = []
    advances.reserveCapacity(cellCount)
    for index in 0..<cellCount {
        let bucket = ((index &* 31) &+ 7) % 4
        switch bucket {
        case 0: advances.append(6.0)
        case 1: advances.append(8.0)
        case 2: advances.append(10.0)
        default: advances.append(14.0)
        }
    }
    return advances
}

@inline(never)
func runColumnQueryOperation<Metrics: LineHorizontalMetricsSource>(
    x: Double,
    inLine line: Int,
    metrics: Metrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.columnAt(x: x, inLine: line, metrics: metrics) {
    case let .column(location):
        var checksum = location.columnIndex
        switch location.clamp {
        case .inRange: checksum &+= 1
        case .clampedToLeft: checksum &+= 2
        case .clampedToRight: checksum &+= 3
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runColumnQueryScenarioCore<Metrics: LineHorizontalMetricsSource>(
    _ scenario: ColumnQueryScenario,
    metrics: Metrics,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let width = metrics.columnOffset(inLine: 0, column: scenario.columnCount)
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let x: Double
            switch sample % 8 {
            case 0:
                x = -1.0 - Double(sample % 1_000)      // left of the line
            case 1:
                x = width + Double(sample % 1_000)     // right of the line end
            default:
                x = deterministicScrollOffset(sample: sample, maxOffset: width)
            }
            let result = runColumnQueryOperation(x: x, inLine: 0, metrics: metrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .columnQuery,
        providerName: scenario.providerName,
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: nil,
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
func runColumnQueryScenario(
    _ scenario: ColumnQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useVariableAdvance {
        let metrics = PrefixSumColumnMetrics(advancesPerLine: [variableAdvances(cellCount: scenario.columnCount)])
        return runColumnQueryScenarioCore(scenario, metrics: metrics,
                                          iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let metrics = UniformColumnMetrics(columnsPerLine: scenario.columnCount, columnWidth: 8.0)
        return runColumnQueryScenarioCore(scenario, metrics: metrics,
                                          iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runColumnQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in columnQueryScenarios() {
        let summary = runColumnQueryScenario(
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

- [ ] **Step 5: Build to verify all exhaustive switches compile**

Run: `swift build`
Expected: `Build complete!` — no "switch must be exhaustive" errors (the three switches — `outputName`, `runBenchmarks`, `runScenario` — all have a `.columnQuery` arm).

- [ ] **Step 6: Run the gate and calibrate budgets**

Run: `swift run -c release ViewportBenchmarks -- --column-query --gate`
Expected: five lines `mode=column_query provider=... scenario=... ... gate=pass`, process exit 0.

Read each scenario's `p95_ns` / `p99_ns`. If any scenario reports `gate=fail`, or if the observed p95 sits under ~1/50 of its budget with a much larger provider spread (i.e. the starting budgets are wildly loose or tight versus the macOS reality), adjust that scenario's `p95BudgetNanoseconds` / `p99BudgetNanoseconds` in `columnQueryScenarios()` to the project's customary headroom (roughly the same multiple over observed p95/p99 that `lineQueryScenarios()` uses — order ~1000× on uniform), then re-run until every scenario is `gate=pass` with comfortable headroom. Record the observed numbers for the verification doc (Task 8).

- [ ] **Step 7: Run without `--gate` to confirm the determinism/failure path**

Run: `swift run -c release ViewportBenchmarks -- --column-query`
Expected: five lines with `failures=0` and a stable `checksum=` per scenario, exit 0. Re-run once; the checksums must be identical between runs (determinism guard).

- [ ] **Step 8: Commit**

```bash
git add Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
git commit -m "feat: add --column-query benchmark mode with local gate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: `AGENTS.md` documentation

**Files:**
- Modify: `AGENTS.md` (architecture paragraph, Commands block, Benchmark-flags paragraph)

**Interfaces:**
- Consumes: nothing (docs).
- Produces: nothing (docs).

- [ ] **Step 1: Add the architecture sentence**

In `AGENTS.md`, immediately after the `lineGeometryAt` sentence (the paragraph ending "...its per-provider cost class equals `lineAt`'s.", around line 65), append:

```markdown
`ViewportVirtualizer.columnAt(x:inLine:metrics:)` opens the horizontal axis: the
within-line inverse query — x -> cell — over a **separate**
`LineHorizontalMetricsSource` (provider supplies `columnCount(inLine:)` and the
cumulative `columnOffset(inLine:column:)`), O(log M) queries / O(1) core memory via
the shared `columnIndex(containingOffset:inLine:)` hook (binary-search default,
provider-overridable), cell model with half-open spans in **visual order**;
out-of-range `x` clamps with a `ColumnLocation.clamp`
(`.clampedToLeft`/`.clampedToRight`) flag and a blank line is `.empty`. `inLine` is a
precondition (the source carries no `lineCount`). Its two providers are
`UniformColumnMetrics` (in the core, beside `UniformLineMetrics`) and
`PrefixSumColumnMetrics` (reference providers); `--column-query` is its **local**
(not-yet-CI) gate.
```

- [ ] **Step 2: Add the Commands line**

In the ` ```bash ` Commands block, after the `--line-geometry-query --gate` line (around line 92), insert:

```bash
swift run -c release ViewportBenchmarks -- --column-query --gate   # x->cell within-line position-query local gate
```

- [ ] **Step 3: Update the Benchmark-flags paragraph**

In the "Benchmark flags:" paragraph, add `--column-query` to the flag list (after `--line-geometry-query`), and add it to the `--gate` is valid with... list (after `--line-query`, and `--line-geometry-query`). The resulting sentences read:

```markdown
Benchmark flags: `--range-only`, `--realistic-provider`, `--variable-height`,
`--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, `--memory-shape`, `--memory-observation`, `--gate`. Only one mode
flag at a time. `--gate` is valid with the default pipeline, `--realistic-provider`,
`--variable-height`, `--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`, and
`--column-query` modes; it is **rejected** with `--range-only`, `--memory-shape`,
`--memory-observation`.
```

- [ ] **Step 4: Verify the CI section is unchanged**

Confirm no edit was made to the "## CI" section or the workflow (this is a local gate; CI promotion is a future slice). Run: `git diff AGENTS.md` and confirm only the architecture sentence, the Commands line, and the Benchmark-flags paragraph changed.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document columnAt and --column-query in AGENTS.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Full verification, cross-target, and paper trail

**Files:**
- Create: `docs/superpowers/verification/2026-07-04-horizontal-position-query.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the verification record (evidence, not assertion).

- [ ] **Step 1: Run the full host test suite**

Run: `swift test`
Expected: PASS, 0 failures. Note the total test count (it should be the prior baseline + the new `LineHorizontalMetricsSourceTests`, `ColumnAtTests`, `ColumnAtEquivalenceTests`, `ColumnAtQueryCountTests`, `PrefixSumColumnMetricsTests`). Record the count.

- [ ] **Step 2: Release build**

Run: `swift build -c release`
Expected: `Build complete!`

- [ ] **Step 3: New gate green**

Run: `swift run -c release ViewportBenchmarks -- --column-query --gate`
Expected: all five scenarios `gate=pass`, exit 0. Record p95/p99 and the five checksums.

- [ ] **Step 4: Existing gates checksum-identical (strictly-additive proof)**

Run each and confirm `gate=pass` with checksums identical to their recorded baselines (this slice changed no existing algorithm):

```bash
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift run -c release ViewportBenchmarks -- --line-query --gate
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
```

Expected: every scenario `gate=pass`; every checksum byte-identical to the value in the most recent verification record. Record.

- [ ] **Step 5: Memory-shape invariant**

Run: `swift run -c release ViewportBenchmarks -- --memory-shape`
Expected: `invariant=pass` (columnAt is O(1) memory; `UniformColumnMetrics` adds no per-line storage).

- [ ] **Step 6: Foundation-free scans**

```bash
rg -n "Foundation" Sources/TextEngineCore
rg -n "Foundation" Sources/TextEngineReferenceProviders
```

Expected: no matches, exit 1 for both.

- [ ] **Step 7: Cross-target compile (iOS blocking, WASM observational)**

```bash
./.github/scripts/cross-target-compile.sh --self-test
./.github/scripts/cross-target-compile.sh --targets ios
./.github/scripts/cross-target-compile.sh --targets wasm
```

Expected: self-test passes; iOS compiles both `TextEngineCore` (now including `UniformColumnMetrics`) and `TextEngineReferenceProviders` (now including `PrefixSumColumnMetrics`); WASM either compiles (if an SDK is provisioned) or records a non-blocking skip. Record outputs/run status.

- [ ] **Step 8: Write the verification record**

Create `docs/superpowers/verification/2026-07-04-horizontal-position-query.md` capturing the actual commands and outputs from Steps 1–7 (test count, new-gate p95/p99 + checksums, existing-gate checksum-identity, memory-shape result, Foundation scans, cross-target results). Leave a `Hosted Proof` section with `Pending` placeholders for the PR-head and post-merge push run IDs, to be filled by the post-merge follow-up PR (per the standing stale-on-write lesson: record hosted proof against the stable final head in the post-merge doc, not a pre-final commit).

- [ ] **Step 9: Commit**

```bash
git add docs/superpowers/verification/2026-07-04-horizontal-position-query.md
git commit -m "docs: record local verification for horizontal position query

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**

| Spec element | Task |
| --- | --- |
| `LineHorizontalMetricsSource` protocol + default `columnIndex` hook + `binarySearchColumnIndex` (Decision 1, Component Design) | Task 1 |
| `UniformColumnMetrics` in the core (Decision 8) | Task 1 |
| `ColumnQuery` / `ColumnLocation` / `Clamp` (Decision 2) | Task 2 |
| `ViewportValidationError` +2 cases (Decision 3) | Task 2 |
| `columnAt` validation ladder + half-open/clamp table (Decisions 4, 5) | Task 2 |
| Cell model / visual order (Decision 6) — encoded in provider contract + tests | Tasks 1, 2, 5 |
| Closed-form equivalence oracle | Task 3 |
| Query-count + ordered-event-log dispatch tests | Task 4 |
| `PrefixSumColumnMetrics` reference provider + its test (Decision 8) | Task 5 |
| `--column-query` benchmark + local gate (Decision 7) | Task 6 |
| `AGENTS.md` architecture + commands + flags | Task 7 |
| Verification: swift test, gate, existing-gate checksum identity, memory-shape, Foundation scans, cross-target | Task 8 |
| Strictly additive (no vertical-axis change) | enforced by Task 2 Step 6 + Task 8 Step 4 |

No spec requirement is without a task. **No CI workflow change** (Decision 7) is honored — no task touches `.github/workflows/`.

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". The one deferred value — benchmark budgets — has an explicit calibration procedure (Task 6 Step 6) with a concrete starting point and adjustment rule, not a placeholder. The verification doc's `Hosted Proof` "Pending" is the project's standard post-merge pattern, not a plan gap.

**3. Type consistency:** `columnCount(inLine:)`, `columnOffset(inLine:column:)`, `columnIndex(containingOffset:inLine:)`, `binarySearchColumnIndex(containingOffset:metrics:inLine:columnCount:)`, `UniformColumnMetrics(columnsPerLine:columnWidth:)`, `PrefixSumColumnMetrics(advancesPerLine:)`, `ColumnQuery.column(ColumnLocation)` / `.empty` / `.failure`, `ColumnLocation(columnIndex:clamp:)`, `Clamp.inRange`/`.clampedToLeft`/`.clampedToRight`, `ViewportVirtualizer.columnAt(x:inLine:metrics:)`, `BenchmarkMode.columnQuery` (`outputName == "column_query"`), `runColumnQueryBenchmarks(enforceGate:)` — used identically across Tasks 1–8.
