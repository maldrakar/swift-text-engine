import XCTest
import TextEngineCore
import TextEngineReferenceProviders

final class PointAtReferenceProviderTests: XCTestCase {
    func testPointAtOverPrefixSumProviders() {
        // 3 lines of heights [10, 20, 30] -> tops [0, 10, 30], totalHeight 60.
        let v = PrefixSumLineMetrics(heights: [10.0, 20.0, 30.0])
        // Per-line advances: line0 [8,8,8], line1 [10,10], line2 [5,5,5,5].
        let h = PrefixSumColumnMetrics(advancesPerLine: [[8.0, 8.0, 8.0], [10.0, 10.0], [5.0, 5.0, 5.0, 5.0]])

        // y = 15 -> line 1 (10 <= 15 < 30); x = 12 -> cell 1 (10 <= 12 < 20).
        let hit = ViewportVirtualizer.pointAt(x: 12.0, y: 15.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(hit, .point(PointLocation(
            line: LineLocation(lineIndex: 1, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 1, clamp: .inRange))
        )))

        // y = 45 -> line 2 (30 <= 45 < 60); x >= width(20) -> clampedToRight at cell 3.
        let clampRight = ViewportVirtualizer.pointAt(x: 100.0, y: 45.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(clampRight, .point(PointLocation(
            line: LineLocation(lineIndex: 2, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 3, clamp: .clampedToRight))
        )))

        // y below the document -> clampedToTop line 0; x = 4 -> cell 0 inRange.
        let clampTop = ViewportVirtualizer.pointAt(x: 4.0, y: -5.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(clampTop, .point(PointLocation(
            line: LineLocation(lineIndex: 0, clamp: .clampedToTop),
            column: .cell(ColumnLocation(columnIndex: 0, clamp: .inRange))
        )))
    }

    func testPointAtBlankLineOverPrefixSumProviders() {
        let v = PrefixSumLineMetrics(heights: [10.0, 10.0, 10.0])       // totalHeight 30
        // line 1 is blank (empty advance vector).
        let h = PrefixSumColumnMetrics(advancesPerLine: [[8.0], [], [8.0]])
        // y = 15 -> line 1 (blank); any finite x -> .blankLine.
        let result = ViewportVirtualizer.pointAt(x: 5.0, y: 15.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .point(PointLocation(
            line: LineLocation(lineIndex: 1, clamp: .inRange),
            column: .blankLine
        )))
    }
}
