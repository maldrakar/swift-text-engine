import XCTest
import TextEngineCore

final class WrapMetricsSourceTests: XCTestCase {
    func testDriverCumulativeOffsetsAndBreaks() {
        let metrics = TestWrapMetrics(advances: [10.0, 30.0, 5.0], breakColumns: [1])
        XCTAssertEqual(metrics.columnCount(inLine: 0), 3)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 0), 0.0)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 1), 10.0)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 3), 45.0)
        XCTAssertTrue(metrics.canBreak(beforeColumn: 1, inLine: 0))
        XCTAssertFalse(metrics.canBreak(beforeColumn: 2, inLine: 0))
    }

    func testOffsetsInitExpressesMalformedCounts() {
        XCTAssertEqual(TestWrapMetrics(offsets: []).columnCount(inLine: 0), -1)
        XCTAssertEqual(TestWrapMetrics(offsets: [0.0]).columnCount(inLine: 0), 0)
    }

    // A WrapMetricsSource IS a LineHorizontalMetricsSource — usable wherever the
    // inherited contract is expected (pins the refinement).
    func testRefinesLineHorizontalMetricsSource() {
        let metrics: LineHorizontalMetricsSource = TestWrapMetrics(advances: [8.0, 8.0])
        XCTAssertEqual(metrics.columnCount(inLine: 0), 2)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 2), 16.0)
    }
}
