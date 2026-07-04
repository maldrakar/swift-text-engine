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
