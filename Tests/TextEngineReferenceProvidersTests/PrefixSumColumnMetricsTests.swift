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
