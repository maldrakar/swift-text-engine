import XCTest
@testable import TextEngineCore

final class PointAtTests: XCTestCase {
    // A hand-built horizontal source whose per-line cell counts / advances are
    // fixed by an array of advance-vectors. Blank lines are an empty advance
    // vector. Line-agnostic providers (UniformColumnMetrics) are used where the
    // located line index does not matter.
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let advancesPerLine: [[Double]]   // advancesPerLine[line] = per-cell widths
        func columnCount(inLine line: Int) -> Int { advancesPerLine[line].count }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            var sum = 0.0
            for i in 0..<column { sum += advancesPerLine[line][i] }
            return sum
        }
    }

    // MARK: Decision 4 rows

    func testEmptyDocumentIsEmptyForFiniteCoordinates() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        // Finite in-range and out-of-range extremes all short-circuit to .empty.
        for (x, y) in [(0.0, 0.0), (-5.0, -5.0), (999.0, 999.0)] {
            XCTAssertEqual(ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: v, columnMetrics: h), .empty)
        }
    }

    func testInRangeCellHit() {
        let v = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)      // totalHeight 160
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0) // width 40
        // y = 40 -> line 2 (inRange); x = 20 -> cell 2 (inRange, since 16 <= 20 < 24)
        let result = ViewportVirtualizer.pointAt(x: 20.0, y: 40.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .point(PointLocation(
            line: LineLocation(lineIndex: 2, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 2, clamp: .inRange))
        )))
    }

    func testBlankLocatedLineIsBlankLineForFiniteX() {
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)       // totalHeight 30
        // line 1 is blank (empty advance vector); lines 0 and 2 have cells.
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 8.0], [], [8.0]])
        // y = 15 -> line 1 (10 <= 15 < 20); any finite x -> .blankLine
        for x in [-3.0, 0.0, 5.0, 100.0] {
            let result = ViewportVirtualizer.pointAt(x: x, y: 15.0, lineMetrics: v, columnMetrics: h)
            XCTAssertEqual(result, .point(PointLocation(
                line: LineLocation(lineIndex: 1, clamp: .inRange),
                column: .blankLine
            )))
        }
    }

    // MARK: Clamp propagation

    func testVerticalClampOnlyKeepsCellResolved() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)       // totalHeight 64
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0) // width 40
        // y below the document -> clampedToTop at line 0; x = 12 -> cell 1 inRange
        let top = ViewportVirtualizer.pointAt(x: 12.0, y: -5.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(top, .point(PointLocation(
            line: LineLocation(lineIndex: 0, clamp: .clampedToTop),
            column: .cell(ColumnLocation(columnIndex: 1, clamp: .inRange))
        )))
        // y past the end -> clampedToBottom at last line; x = 12 -> cell 1 inRange
        let bottom = ViewportVirtualizer.pointAt(x: 12.0, y: 999.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(bottom, .point(PointLocation(
            line: LineLocation(lineIndex: 3, clamp: .clampedToBottom),
            column: .cell(ColumnLocation(columnIndex: 1, clamp: .inRange))
        )))
    }

    func testHorizontalClampOnlyKeepsLineResolved() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0) // width 40
        // y = 20 -> line 1 inRange; x < 0 -> clampedToLeft at cell 0
        let left = ViewportVirtualizer.pointAt(x: -1.0, y: 20.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(left, .point(PointLocation(
            line: LineLocation(lineIndex: 1, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft))
        )))
        // x >= width -> clampedToRight at last cell
        let right = ViewportVirtualizer.pointAt(x: 40.0, y: 20.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(right, .point(PointLocation(
            line: LineLocation(lineIndex: 1, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 4, clamp: .clampedToRight))
        )))
    }

    func testBothAxesClampedRecordsBothFlags() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)
        // y < 0 and x < 0 -> clampedToTop + clampedToLeft, both preserved
        let result = ViewportVirtualizer.pointAt(x: -1.0, y: -1.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .point(PointLocation(
            line: LineLocation(lineIndex: 0, clamp: .clampedToTop),
            column: .cell(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft))
        )))
    }

    // MARK: Failure precedence & validation-before-short-circuit

    func testVerticalFailureShortCircuits() {
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        // negative lineCount -> .negativeLineCount, horizontal never consulted
        let neg = UniformLineMetrics(lineCount: -1, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 5.0, lineMetrics: neg, columnMetrics: h),
                       .failure(.negativeLineCount))
        // non-finite y -> .nonFiniteValue (short-circuits before x is ever looked at)
        let ok = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: .nan, lineMetrics: ok, columnMetrics: h),
                       .failure(.nonFiniteValue))
        // offset(ofLine: 0) != 0 breaks the O(1) contract probe -> .invalidLineMetrics
        struct BrokenLineMetrics: LineMetricsSource {
            var lineCount: Int { 4 }
            func offset(ofLine index: Int) -> Double { Double(index) * 16.0 + 1.0 }
        }
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 5.0, lineMetrics: BrokenLineMetrics(), columnMetrics: h),
                       .failure(.invalidLineMetrics))
    }

    func testHorizontalFailureSurfaces() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        // valid line located, but non-finite x -> columnAt .nonFiniteValue surfaces
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: .infinity, y: 20.0, lineMetrics: v, columnMetrics: h),
                       .failure(.nonFiniteValue))
        // valid line, but negative columnCount -> .negativeColumnCount surfaces
        struct NegativeColumnMetrics: LineHorizontalMetricsSource {
            func columnCount(inLine line: Int) -> Int { -1 }
            func columnOffset(inLine line: Int, column: Int) -> Double { 0.0 }
        }
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 20.0, lineMetrics: v, columnMetrics: NegativeColumnMetrics()),
                       .failure(.negativeColumnCount))
        // columnOffset(inLine:column: 0) != 0 breaks the probe -> .invalidColumnMetrics
        struct BrokenColumnMetrics: LineHorizontalMetricsSource {
            func columnCount(inLine line: Int) -> Int { 4 }
            func columnOffset(inLine line: Int, column: Int) -> Double { Double(column) * 8.0 + 1.0 }
        }
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 20.0, lineMetrics: v, columnMetrics: BrokenColumnMetrics()),
                       .failure(.invalidColumnMetrics))
    }

    func testFailurePrecedenceVerticalWins() {
        // Both axes would fail: lineCount < 0 AND columnCount < 0 -> vertical error.
        struct NegativeColumnMetrics: LineHorizontalMetricsSource {
            func columnCount(inLine line: Int) -> Int { -1 }
            func columnOffset(inLine line: Int, column: Int) -> Double { 0.0 }
        }
        let v = UniformLineMetrics(lineCount: -1, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 5.0, lineMetrics: v, columnMetrics: NegativeColumnMetrics()),
                       .failure(.negativeLineCount))
    }

    func testNonFiniteYBeatsEmptyDocument() {
        // Validation precedes the zero-count short-circuit: NaN y on an empty doc
        // is .failure(.nonFiniteValue), NOT .empty.
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: .nan, lineMetrics: v, columnMetrics: h),
                       .failure(.nonFiniteValue))
    }

    func testNonFiniteXBeatsBlankLine() {
        // Validation precedes the blank-line short-circuit: NaN x on a located
        // blank line is .failure(.nonFiniteValue), NOT .blankLine.
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)      // y=15 -> line 1
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0], [], [8.0]]) // line 1 blank
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: .nan, y: 15.0, lineMetrics: v, columnMetrics: h),
                       .failure(.nonFiniteValue))
    }
}
