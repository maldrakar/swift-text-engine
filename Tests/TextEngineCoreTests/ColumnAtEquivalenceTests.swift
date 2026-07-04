import XCTest
@testable import TextEngineCore

final class ColumnAtEquivalenceTests: XCTestCase {
    // Exactly-representable widths (no rounding at product boundaries), well under 2^53.
    private let widths: [Double] = [1.0, 8.0, 16.0, 12.5, 256.0]
    private let counts: [Int] = [1, 2, 7, 1000]
    private let lines: [Int] = [0, 3, 9]

    private func expected(x: Double, count: Int, width: Double) -> ColumnQuery {
        // Structural expectation. x is always a product k*width (+width/2), so no
        // division is needed to name the cell.
        if x < 0.0 { return .column(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft)) }
        let totalWidth = Double(count) * width
        if x >= totalWidth { return .column(ColumnLocation(columnIndex: count - 1, clamp: .clampedToRight)) }
        // in-range: derive k by counting products, not dividing.
        var k = 0
        while Double(k + 1) * width <= x { k += 1 }
        return .column(ColumnLocation(columnIndex: k, clamp: .inRange))
    }

    func testUniformColumnAtMatchesStructuralOracle() {
        for width in widths {
            for count in counts {
                let metrics = UniformColumnMetrics(columnsPerLine: count, columnWidth: width)
                for line in lines {
                    var xs: [Double] = [-width, 0.0]
                    for k in Set([0, 1, count / 2, count - 1]) where k >= 0 && k < count {
                        xs.append(Double(k) * width)                    // exact boundary
                        xs.append(Double(k) * width + width / 2)        // mid-span
                    }
                    xs.append(Double(count) * width)                    // exact total width
                    xs.append(Double(count) * width + width)            // past the end
                    for x in xs {
                        XCTAssertEqual(
                            ViewportVirtualizer.columnAt(x: x, inLine: line, metrics: metrics),
                            expected(x: x, count: count, width: width),
                            "width=\(width) count=\(count) line=\(line) x=\(x)"
                        )
                    }
                }
            }
        }
    }
}
