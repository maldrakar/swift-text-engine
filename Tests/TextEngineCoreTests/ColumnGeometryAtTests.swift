import XCTest
@testable import TextEngineCore

final class ColumnGeometryAtTests: XCTestCase {
    private func box(_ index: Int, _ x: Double, _ width: Double) -> ColumnGeometry {
        ColumnGeometry(columnIndex: index, x: x, width: width)
    }

    // A line-addressable hand-built source (mirror of ColumnAtTests.ArrayColumnMetrics).
    // offsetsPerLine[line][0] must be 0 for a valid line; an empty inner array yields
    // columnCount == -1 (drives .negativeColumnCount).
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let offsetsPerLine: [[Double]]
        func columnCount(inLine line: Int) -> Int { offsetsPerLine[line].count - 1 }
        func columnOffset(inLine line: Int, column: Int) -> Double { offsetsPerLine[line][column] }
    }

    // MARK: failure + empty outcomes (inherited from columnAt)

    func testNegativeColumnCountFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[]]) // columnCount -1
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 3.0, inLine: 0, metrics: metrics),
                       .failure(.negativeColumnCount))
    }

    func testNonFiniteXFails() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        for x in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: x, inLine: 0, metrics: metrics),
                           .failure(.nonFiniteValue))
        }
    }

    func testInvalidFirstOffsetFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[5.0, 15.0]]) // columnOffset(_,0) == 5
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 3.0, inLine: 0, metrics: metrics),
                       .failure(.invalidColumnMetrics))
    }

    // Pins the "probe before empty short-circuit" ladder: a blank line whose
    // columnOffset(_,0) != 0 must fail, not short-circuit to .empty.
    func testInvalidFirstOffsetOnBlankLineFailsBeforeEmpty() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[5.0]]) // columnCount 0, offset(_,0) == 5
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 0.0, inLine: 0, metrics: metrics),
                       .failure(.invalidColumnMetrics))
    }

    func testZeroWidthFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, 0.0]]) // width 0
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 0.0, inLine: 0, metrics: metrics),
                       .failure(.invalidColumnMetrics))
    }

    func testNonFiniteWidthFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, .infinity]])
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 1.0, inLine: 0, metrics: metrics),
                       .failure(.invalidColumnMetrics))
    }

    func testBlankLineIsEmptyForAnyX() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0]]) // columnCount 0
        for x in [-5.0, 0.0, 12.0] {
            XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: x, inLine: 0, metrics: metrics), .empty)
        }
    }

    // MARK: in-range geometry + fraction

    func testExactCellLeftEdgeHasZeroFraction() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 16.0 * 5.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(5, 80.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .inRange)))
    }

    func testMidCellHasHalfFraction() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 16.0 * 3.0 + 8.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(3, 48.0, 16.0),
                                                        fractionInColumn: 0.5, clamp: .inRange)))
    }

    func testXZeroIsInRangeAtCellZero() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 0.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .inRange)))
    }

    // MARK: clamp fractions

    func testClampToLeftHasZeroFractionOnCellZero() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: -0.001, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .clampedToLeft)))
    }

    func testClampToRightHasUnitFractionOnLastCell() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        let width = 10.0 * 16.0
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: width, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(9, 144.0, 16.0),
                                                        fractionInColumn: 1.0, clamp: .clampedToRight)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: width + 100.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(9, 144.0, 16.0),
                                                        fractionInColumn: 1.0, clamp: .clampedToRight)))
    }

    // MARK: non-uniform metrics (guards against a uniform-only shortcut)

    func testNonUniformGeometryAndFraction() {
        // advances [10,30,5,50] -> offsets [0,10,40,45,95], width 95, columnCount 4
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, 10.0, 40.0, 45.0, 95.0]])
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 10.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(1, 10.0, 30.0),
                                                        fractionInColumn: 0.0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 25.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(1, 10.0, 30.0),
                                                        fractionInColumn: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 42.5, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(2, 40.0, 5.0),
                                                        fractionInColumn: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: -1.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 10.0),
                                                        fractionInColumn: 0.0, clamp: .clampedToLeft)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 95.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(3, 45.0, 50.0),
                                                        fractionInColumn: 1.0, clamp: .clampedToRight)))
    }

    func testSingleCellLine() {
        let metrics = UniformColumnMetrics(columnsPerLine: 1, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: -1.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .clampedToLeft)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 0.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 8.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 16.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 1.0, clamp: .clampedToRight)))
    }

    // MARK: reconstruction invariant (opposite direction from the equivalence oracle)

    func testReconstructionInvariant() {
        // offsets [0,10,40,45,95]; assert box.x + frac*box.width round-trips to x
        // for interior, non-half in-range points.
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, 10.0, 40.0, 45.0, 95.0]])
        for x in [3.0, 7.5, 22.0, 41.3, 60.0, 94.9] {
            guard case let .geometry(loc) = ViewportVirtualizer.columnGeometryAt(x: x, inLine: 0, metrics: metrics) else {
                return XCTFail("expected .geometry for x=\(x)")
            }
            XCTAssertEqual(loc.clamp, .inRange, "x=\(x)")
            XCTAssertLessThanOrEqual(abs(loc.geometry.x + loc.fractionInColumn * loc.geometry.width - x), 1e-9, "x=\(x)")
        }
    }

    // MARK: per-line addressing

    func testPerLineAddressing() {
        // line 0 offsets [0,10,40,45,95]; line 1 offsets [0,8,16]
        let metrics = ArrayColumnMetrics(offsetsPerLine: [
            [0.0, 10.0, 40.0, 45.0, 95.0],
            [0.0, 8.0, 16.0],
        ])
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 9.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 10.0),
                                                        fractionInColumn: 0.9, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 9.0, inLine: 1, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(1, 8.0, 8.0),
                                                        fractionInColumn: (9.0 - 8.0) / 8.0, clamp: .inRange)))
    }
}
