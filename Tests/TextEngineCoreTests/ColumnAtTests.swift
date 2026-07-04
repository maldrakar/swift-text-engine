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

    // A blank line (columnCount == 0) whose columnOffset(_, column: 0) != 0 must
    // fail with .invalidColumnMetrics, NOT short-circuit to .empty — this pins the
    // "probe before empty short-circuit" ladder order (the "Do not reorder"
    // invariant in HorizontalPositionQuery.swift).
    func testInvalidFirstOffsetOnBlankLineFailsBeforeEmpty() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[5.0]]) // columnCount 0, columnOffset(_,0) == 5
        XCTAssertEqual(
            ViewportVirtualizer.columnAt(x: 0.0, inLine: 0, metrics: metrics),
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
