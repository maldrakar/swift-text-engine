import XCTest
import TextEngineCore
import TextEngineReferenceProviders

// pointGeometryAt over the SHIPPED providers. TextEngineCoreTests cannot reach them
// (it depends on TextEngineCore alone), so its oracles run on hand-built doubles and
// the reference providers would otherwise meet this query for the first time in a
// consumer's app. This is the sibling of PointAtReferenceProviderTests, which covers
// the same ground for pointAt.
final class PointGeometryAtReferenceProviderTests: XCTestCase {

    // 3 lines of heights [10, 20, 30] -> tops [0, 10, 30], totalHeight 60.
    private let heights = [10.0, 20.0, 30.0]
    // line0 [8,8,8] -> offsets 0,8,16,24 (width 24)
    // line1 [10,10] -> offsets 0,10,20   (width 20)
    // line2 [5,5,5,5] -> offsets 0,5,10,15,20 (width 20)
    private let advances = [[8.0, 8.0, 8.0], [10.0, 10.0], [5.0, 5.0, 5.0, 5.0]]

    func testInRangeHitCarriesBothBoxesOverPrefixSumProviders() {
        let v = PrefixSumLineMetrics(heights: heights)
        let h = PrefixSumColumnMetrics(advancesPerLine: advances)

        // y = 15 -> line 1, box [10, 30), fraction (15-10)/20 = 0.25
        // x = 12 -> cell 1, box [10, 20), fraction (12-10)/10 = 0.2
        let result = ViewportVirtualizer.pointGeometryAt(x: 12.0, y: 15.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 1, y: 10.0, height: 20.0),
                fractionInLine: 0.25,
                clamp: .inRange),
            column: .cell(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: 1, x: 10.0, width: 10.0),
                fractionInColumn: 0.2,
                clamp: .inRange))
        )))
    }

    // Right of the line end: the cell clamps to the last one and the fraction pins to
    // exactly 1.0 rather than being computed from an x that lies outside the box.
    func testClampedRightKeepsTheLastCellBoxAndPinsTheFraction() {
        let v = PrefixSumLineMetrics(heights: heights)
        let h = PrefixSumColumnMetrics(advancesPerLine: advances)

        // y = 45 -> line 2, box [30, 60), fraction (45-30)/30 = 0.5
        // x = 100 -> past the line width (20) -> cell 3, box [15, 20), fraction 1.0
        let result = ViewportVirtualizer.pointGeometryAt(x: 100.0, y: 45.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 2, y: 30.0, height: 30.0),
                fractionInLine: 0.5,
                clamp: .inRange),
            column: .cell(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: 3, x: 15.0, width: 5.0),
                fractionInColumn: 1.0,
                clamp: .clampedToRight))
        )))
    }

    // Above the document: the line clamps to 0 with fractionInLine pinned to 0.0, while
    // the horizontal axis stays in range. Each axis clamps independently.
    func testClampedTopAboveTheDocument() {
        let v = PrefixSumLineMetrics(heights: heights)
        let h = PrefixSumColumnMetrics(advancesPerLine: advances)

        // y = -5 -> line 0, box [0, 10), fraction 0.0, clampedToTop
        // x = 4  -> cell 0, box [0, 8), fraction 0.5, inRange
        let result = ViewportVirtualizer.pointGeometryAt(x: 4.0, y: -5.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 0, y: 0.0, height: 10.0),
                fractionInLine: 0.0,
                clamp: .clampedToTop),
            column: .cell(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: 0, x: 0.0, width: 8.0),
                fractionInColumn: 0.5,
                clamp: .inRange))
        )))
    }

    // A blank line still carries its full line box — the caret box of an empty line is
    // exactly what a consumer needs there.
    func testBlankLineKeepsItsLineBoxOverPrefixSumProviders() {
        let v = PrefixSumLineMetrics(heights: [10.0, 10.0, 10.0])          // totalHeight 30
        let h = PrefixSumColumnMetrics(advancesPerLine: [[8.0], [], [8.0]])  // line 1 is blank

        let result = ViewportVirtualizer.pointGeometryAt(x: 5.0, y: 15.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 1, y: 10.0, height: 10.0),
                fractionInLine: 0.5,
                clamp: .inRange),
            column: .blankLine
        )))
    }

    // BalancedTreeLineMetrics is the one provider that OVERRIDES the vertical search hook
    // (lineIndex(containingOffset:)) with a native O(log N) descent instead of the core's
    // generic binary search. Its answers must be identical to the provider that uses the
    // fallback — geometry, fractions and clamps included, not just the line index.
    func testBalancedTreeNativeDescentEqualsThePrefixSumFallback() {
        let heights = (0..<64).map { 8.0 + Double($0 % 5) * 3.0 }
        let tree = BalancedTreeLineMetrics(heights: heights)
        let prefix = PrefixSumLineMetrics(heights: heights)
        // Variable advances; every 7th line is blank.
        let advances: [[Double]] = (0..<64).map { line in
            line % 7 == 0 ? [] : (0..<(3 + line % 4)).map { 4.0 + Double($0) }
        }
        let h = PrefixSumColumnMetrics(advancesPerLine: advances)

        let totalHeight = prefix.offset(ofLine: prefix.lineCount)
        XCTAssertEqual(tree.offset(ofLine: tree.lineCount), totalHeight)

        var checked = 0
        for yStep in -2...130 {
            let y = Double(yStep) * 5.0
            for xStep in -1...12 {
                let x = Double(xStep) * 3.0
                XCTAssertEqual(
                    ViewportVirtualizer.pointGeometryAt(x: x, y: y, lineMetrics: tree, columnMetrics: h),
                    ViewportVirtualizer.pointGeometryAt(x: x, y: y, lineMetrics: prefix, columnMetrics: h),
                    "native descent diverged from the fallback at (x: \(x), y: \(y))")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 1_000)
    }
}
