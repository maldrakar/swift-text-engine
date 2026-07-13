import XCTest
@testable import TextEngineCore

final class PointGeometryAtTests: XCTestCase {
    // Hand-built horizontal source: advancesPerLine[line] = per-cell widths.
    // A blank line is an empty advance vector. Same shape as PointAtTests', plus an
    // `originShift` so the contract-violating case (columnOffset(_, 0) != 0) is
    // reachable without a second helper type.
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let advancesPerLine: [[Double]]
        var originShift: Double = 0.0
        func columnCount(inLine line: Int) -> Int { advancesPerLine[line].count }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            var sum = originShift
            for i in 0..<column { sum += advancesPerLine[line][i] }
            return sum
        }
    }

    // A horizontal source that reports a negative cell count, to reach
    // .negativeColumnCount on a successfully located line.
    private struct NegativeCountColumnMetrics: LineHorizontalMetricsSource {
        func columnCount(inLine line: Int) -> Int { -1 }
        func columnOffset(inLine line: Int, column: Int) -> Double { 0.0 }
    }

    // MARK: In-range hit — both boxes and both fractions

    func testInRangeHitCarriesBothBoxesAndFractions() {
        let v = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)       // totalHeight 160
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)  // lineWidth 40
        // y = 40 -> line 2, box [32, 48), fraction (40-32)/16 = 0.5
        // x = 20 -> cell 2, box [16, 24), fraction (20-16)/8  = 0.5
        let result = ViewportVirtualizer.pointGeometryAt(x: 20.0, y: 40.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 2, y: 32.0, height: 16.0),
                fractionInLine: 0.5,
                clamp: .inRange),
            column: .cell(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: 2, x: 16.0, width: 8.0),
                fractionInColumn: 0.5,
                clamp: .inRange))
        )))
    }

    // MARK: Decision 7 rows

    func testEmptyDocumentIsEmptyForFiniteCoordinates() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        for (x, y) in [(0.0, 0.0), (-5.0, -5.0), (999.0, 999.0)] {
            XCTAssertEqual(
                ViewportVirtualizer.pointGeometryAt(x: x, y: y, lineMetrics: v, columnMetrics: h), .empty)
        }
    }

    func testNegativeLineCountIsFailure() {
        // ClosureLineMetrics lives in Tests/TextEngineCoreTests/TestLineMetrics.swift and
        // is the established way to build an invalid vertical source. Do not add a helper.
        let v = ClosureLineMetrics(lineCount: -1, offsetForLine: { Double($0) * 16.0 })
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 0.0, y: 0.0, lineMetrics: v, columnMetrics: h),
            .failure(.negativeLineCount))
    }

    // offset(ofLine: 0) != 0 breaks the vertical metrics contract. The probe runs
    // BEFORE the empty short-circuit, so it fires even on a zero-line document.
    func testInvalidLineMetricsIsFailure() {
        let v = ClosureLineMetrics(lineCount: 4, offsetForLine: { 5.0 + Double($0) * 16.0 })
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 0.0, y: 0.0, lineMetrics: v, columnMetrics: h),
            .failure(.invalidLineMetrics))
    }

    // A non-positive total height is the other vertical-metrics failure.
    func testNonPositiveTotalHeightIsFailure() {
        let v = ClosureLineMetrics(lineCount: 4, offsetForLine: { _ in 0.0 })
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 0.0, y: 0.0, lineMetrics: v, columnMetrics: h),
            .failure(.invalidLineMetrics))
    }

    func testNegativeColumnCountOnLocatedLineIsFailureAndDiscardsTheLine() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(
                x: 5.0, y: 20.0, lineMetrics: v, columnMetrics: NegativeCountColumnMetrics()),
            .failure(.negativeColumnCount))
    }

    // columnOffset(inLine:column: 0) != 0 breaks the horizontal contract. The located
    // line is discarded: a failure on either axis means the query answered nothing.
    func testInvalidColumnMetricsOnLocatedLineIsFailure() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        // Every cell offset is shifted by 5, so columnOffset(_, 0) == 5 != 0.
        let h = ArrayColumnMetrics(advancesPerLine: Array(repeating: [8.0, 8.0], count: 4),
                                   originShift: 5.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 5.0, y: 20.0, lineMetrics: v, columnMetrics: h),
            .failure(.invalidColumnMetrics))
    }

    // MARK: Precedence — the four rules a refactor could silently reorder

    func testNonFiniteYBeatsEmptyDocument() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        for y in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(
                ViewportVirtualizer.pointGeometryAt(x: 0.0, y: y, lineMetrics: v, columnMetrics: h),
                .failure(.nonFiniteValue), "y=\(y)")
        }
    }

    func testEmptyDocumentBeatsNonFiniteX() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: .nan, y: 0.0, lineMetrics: v, columnMetrics: h),
            .empty)
    }

    func testNonFiniteXBeatsBlankLine() {
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 8.0], [], [8.0]])
        // y = 15 -> blank line 1; a non-finite x must still be a failure.
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: .nan, y: 15.0, lineMetrics: v, columnMetrics: h),
            .failure(.nonFiniteValue))
    }

    // MARK: Blank lines keep their line geometry

    func testBlankLocatedLineKeepsItsBox() {
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 8.0], [], [8.0]])
        // y = 15 -> line 1, box [10, 20), fraction 0.5; line 1 is blank.
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 5.0, y: 15.0, lineMetrics: v, columnMetrics: h),
            .geometry(PointGeometryLocation(
                line: LineGeometryLocation(
                    geometry: LineGeometry(lineIndex: 1, y: 10.0, height: 10.0),
                    fractionInLine: 0.5,
                    clamp: .inRange),
                column: .blankLine)))
    }

    // The most common real hit-test, and the exact gap the Slice 37 review left
    // open (its P3 #1): the document's last line is blank and the user clicks in
    // the empty area below it. It is the INTERSECTION of the vertical clamp and
    // the blank line, which every other test covers only separately.
    func testClickBelowADocumentWhoseLastLineIsBlank() {
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)        // totalHeight 30
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 8.0], [8.0], []])  // last line blank
        let result = ViewportVirtualizer.pointGeometryAt(x: 4.0, y: 100.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 2, y: 20.0, height: 10.0),
                fractionInLine: 1.0,
                clamp: .clampedToBottom),
            column: .blankLine)))
    }

    // MARK: Clamped corners — all four, fractions pinned exactly

    func testBothAxesClampedTopLeft() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: -7.0, y: -3.0, lineMetrics: v, columnMetrics: h),
            .geometry(PointGeometryLocation(
                line: LineGeometryLocation(
                    geometry: LineGeometry(lineIndex: 0, y: 0.0, height: 16.0),
                    fractionInLine: 0.0,
                    clamp: .clampedToTop),
                column: .cell(ColumnGeometryLocation(
                    geometry: ColumnGeometry(columnIndex: 0, x: 0.0, width: 8.0),
                    fractionInColumn: 0.0,
                    clamp: .clampedToLeft)))))
    }

    func testBothAxesClampedBottomRight() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)        // totalHeight 64
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)  // lineWidth 40
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 999.0, y: 999.0, lineMetrics: v, columnMetrics: h),
            .geometry(PointGeometryLocation(
                line: LineGeometryLocation(
                    geometry: LineGeometry(lineIndex: 3, y: 48.0, height: 16.0),
                    fractionInLine: 1.0,
                    clamp: .clampedToBottom),
                column: .cell(ColumnGeometryLocation(
                    geometry: ColumnGeometry(columnIndex: 4, x: 32.0, width: 8.0),
                    fractionInColumn: 1.0,
                    clamp: .clampedToRight)))))
    }

    func testMixedClampsCompose() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)
        // y clamped to top, x clamped to right.
        let topRight = ViewportVirtualizer.pointGeometryAt(x: 999.0, y: -1.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(topRight, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 0, y: 0.0, height: 16.0),
                fractionInLine: 0.0, clamp: .clampedToTop),
            column: .cell(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: 4, x: 32.0, width: 8.0),
                fractionInColumn: 1.0, clamp: .clampedToRight)))))
        // y clamped to bottom, x clamped to left.
        let bottomLeft = ViewportVirtualizer.pointGeometryAt(x: -1.0, y: 999.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(bottomLeft, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 3, y: 48.0, height: 16.0),
                fractionInLine: 1.0, clamp: .clampedToBottom),
            column: .cell(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: 0, x: 0.0, width: 8.0),
                fractionInColumn: 0.0, clamp: .clampedToLeft)))))
    }

    // MARK: Reconstruction property — the fraction must reproduce the input

    func testInRangeGeometryReconstructsTheInputPoint() {
        let v = UniformLineMetrics(lineCount: 50, lineHeight: 13.0)        // totalHeight 650
        let h = UniformColumnMetrics(columnsPerLine: 7, columnWidth: 11.0)  // lineWidth 77
        for step in 0..<40 {
            let y = Double(step) * 16.1 + 0.3   // stays inside [0, 650)
            let x = Double(step % 7) * 11.0 + 3.7  // stays inside [0, 77)
            guard case let .geometry(p) = ViewportVirtualizer.pointGeometryAt(
                x: x, y: y, lineMetrics: v, columnMetrics: h),
                  case let .cell(cell) = p.column else {
                return XCTFail("expected a located cell at x=\(x) y=\(y)")
            }
            XCTAssertEqual(p.line.geometry.y + p.line.fractionInLine * p.line.geometry.height,
                           y, accuracy: 1e-9, "y reconstruction at step \(step)")
            XCTAssertEqual(cell.geometry.x + cell.fractionInColumn * cell.geometry.width,
                           x, accuracy: 1e-9, "x reconstruction at step \(step)")
        }
    }
}
