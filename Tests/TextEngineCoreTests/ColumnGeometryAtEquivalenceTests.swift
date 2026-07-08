import XCTest
@testable import TextEngineCore

final class ColumnGeometryAtEquivalenceTests: XCTestCase {
    private func assertGeometry(
        _ metrics: UniformColumnMetrics,
        inLine line: Int,
        x: Double,
        index: Int,
        fraction: Double,
        clamp: ColumnLocation.Clamp,
        file: StaticString = #filePath,
        line testLine: UInt = #line
    ) {
        let w = metrics.columnWidth
        let expected = ColumnGeometryQuery.geometry(
            ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: index, x: Double(index) * w, width: w),
                fractionInColumn: fraction,
                clamp: clamp
            )
        )
        XCTAssertEqual(
            ViewportVirtualizer.columnGeometryAt(x: x, inLine: line, metrics: metrics),
            expected,
            "columnsPerLine=\(metrics.columnsPerLine), columnWidth=\(w), line=\(line), x=\(x)",
            file: file, line: testLine
        )
    }

    func testStructuralEquivalenceOverRepresentableUniformMetrics() {
        // Exactly-representable widths; counts well under 2^53 so Double(k)*w is exact
        // and the fractions (0.0, 0.5, 1.0) are exact.
        let widths: [Double] = [1.0, 10.0, 16.0, 12.5, 256.0]
        let counts = [1, 2, 3, 100, 100_000]
        let lines = [0, 3, 9]

        for width in widths {
            for count in counts {
                let metrics = UniformColumnMetrics(columnsPerLine: count, columnWidth: width)
                let totalWidth = Double(count) * width
                for line in lines {
                    // Left of the line -> clamp left, fraction 0.0, cell 0 box.
                    assertGeometry(metrics, inLine: line, x: -width, index: 0, fraction: 0.0, clamp: .clampedToLeft)

                    let ks = Set([0, 1, count / 2, count - 1].filter { $0 >= 0 && $0 < count })
                    for k in ks {
                        // Exact cell left edge -> fraction 0.0, in range.
                        assertGeometry(metrics, inLine: line, x: Double(k) * width, index: k, fraction: 0.0, clamp: .inRange)
                        // Mid-cell -> fraction 0.5, in range.
                        assertGeometry(metrics, inLine: line, x: Double(k) * width + width / 2.0,
                                       index: k, fraction: 0.5, clamp: .inRange)
                    }

                    // At and past the line width -> clamp right, fraction 1.0, last-cell box.
                    assertGeometry(metrics, inLine: line, x: totalWidth, index: count - 1, fraction: 1.0, clamp: .clampedToRight)
                    assertGeometry(metrics, inLine: line, x: totalWidth + width, index: count - 1, fraction: 1.0, clamp: .clampedToRight)
                }
            }
        }
    }

    func testIndexAndClampParityWithColumnAt() {
        let metrics = UniformColumnMetrics(columnsPerLine: 1_000, columnWidth: 16.0)
        let width = 1_000.0 * 16.0
        var xs: [Double] = [-10.0, 0.0, width, width + 25.0]
        for k in [0, 1, 500, 999] {
            xs.append(Double(k) * 16.0)
            xs.append(Double(k) * 16.0 + 7.0)
        }
        for x in xs {
            let geometryResult = ViewportVirtualizer.columnGeometryAt(x: x, inLine: 0, metrics: metrics)
            let columnResult = ViewportVirtualizer.columnAt(x: x, inLine: 0, metrics: metrics)
            guard case let .geometry(loc) = geometryResult, case let .column(col) = columnResult else {
                return XCTFail("expected .geometry and .column for x=\(x), got \(geometryResult) / \(columnResult)")
            }
            XCTAssertEqual(loc.geometry.columnIndex, col.columnIndex, "index parity x=\(x)")
            XCTAssertEqual(loc.clamp, col.clamp, "clamp parity x=\(x)")
        }
    }
}
