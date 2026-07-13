import XCTest
@testable import TextEngineCore

final class PointGeometryAtEquivalenceTests: XCTestCase {
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let advancesPerLine: [[Double]]
        func columnCount(inLine line: Int) -> Int { advancesPerLine[line].count }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            var sum = 0.0
            for i in 0..<column { sum += advancesPerLine[line][i] }
            return sum
        }
    }

    // Variable-height vertical source built from an explicit height vector.
    private struct ArrayLineMetrics: LineMetricsSource {
        let heights: [Double]
        var lineCount: Int { heights.count }
        func offset(ofLine index: Int) -> Double {
            var sum = 0.0
            for i in 0..<index { sum += heights[i] }
            return sum
        }
    }

    // Oracle 1 — vs pointAt. This is NOT a copy of the implementation: it compares
    // against an independently existing function, so a wrong 2D ordering in
    // pointGeometryAt cannot agree with it by accident.
    private func assertIndexAndClampParityWithPointAt<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics v: V, columnMetrics h: H, xs: [Double], ys: [Double],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for y in ys {
            for x in xs {
                let flat = ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: v, columnMetrics: h)
                let rich = ViewportVirtualizer.pointGeometryAt(x: x, y: y, lineMetrics: v, columnMetrics: h)
                switch (flat, rich) {
                case let (.failure(a), .failure(b)):
                    XCTAssertEqual(a, b, "x=\(x) y=\(y)", file: file, line: line)
                case (.empty, .empty):
                    break
                case let (.point(p), .geometry(g)):
                    XCTAssertEqual(p.line.lineIndex, g.line.geometry.lineIndex, "x=\(x) y=\(y)", file: file, line: line)
                    XCTAssertEqual(p.line.clamp, g.line.clamp, "x=\(x) y=\(y)", file: file, line: line)
                    switch (p.column, g.column) {
                    case let (.cell(c), .cell(gc)):
                        XCTAssertEqual(c.columnIndex, gc.geometry.columnIndex, "x=\(x) y=\(y)", file: file, line: line)
                        XCTAssertEqual(c.clamp, gc.clamp, "x=\(x) y=\(y)", file: file, line: line)
                    case (.blankLine, .blankLine):
                        break
                    default:
                        XCTFail("column resolution diverged at x=\(x) y=\(y)", file: file, line: line)
                    }
                default:
                    XCTFail("outcome diverged at x=\(x) y=\(y): \(flat) vs \(rich)", file: file, line: line)
                }
            }
        }
    }

    // Oracles 2 and 3 — each component must EQUAL the 1D geometry query's result.
    private func assertComponentParityWith1D<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics v: V, columnMetrics h: H, xs: [Double], ys: [Double],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for y in ys {
            for x in xs {
                guard case let .geometry(g) = ViewportVirtualizer.pointGeometryAt(
                    x: x, y: y, lineMetrics: v, columnMetrics: h) else { continue }

                // Oracle 2: the line component is exactly lineGeometryAt(y:).
                XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: y, metrics: v),
                               .geometry(g.line), "x=\(x) y=\(y)", file: file, line: line)

                // Oracle 3: the column component is exactly columnGeometryAt(x:inLine:).
                let located = g.line.geometry.lineIndex
                let want = ViewportVirtualizer.columnGeometryAt(x: x, inLine: located, metrics: h)
                switch g.column {
                case let .cell(cell):
                    XCTAssertEqual(want, .geometry(cell), "x=\(x) y=\(y)", file: file, line: line)
                case .blankLine:
                    XCTAssertEqual(want, .empty, "x=\(x) y=\(y)", file: file, line: line)
                }
            }
        }
    }

    func testParityUniformSources() {
        let v = UniformLineMetrics(lineCount: 20, lineHeight: 16.0)        // totalHeight 320
        let h = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)  // lineWidth 80
        let ys: [Double] = [-1.0, 0.0, 106.7, 160.0, 320.0, 325.0, .nan, .infinity, -.infinity]
        let xs: [Double] = [-1.0, 0.0, 26.7, 40.0, 80.0, 85.0, .nan, .infinity, -.infinity]
        assertIndexAndClampParityWithPointAt(lineMetrics: v, columnMetrics: h, xs: xs, ys: ys)
        assertComponentParityWith1D(lineMetrics: v, columnMetrics: h, xs: xs, ys: ys)
    }

    func testParityVariableSourcesWithBlankLine() {
        // Heights 10/20/5/30 (totalHeight 65); line 2 is blank; advances vary per line.
        let v = ArrayLineMetrics(heights: [10.0, 20.0, 5.0, 30.0])
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 4.0, 12.0], [6.0, 6.0], [], [20.0, 3.0]])
        let ys: [Double] = [-1.0, 0.0, 5.0, 15.0, 32.0, 40.0, 65.0, 70.0, .nan, .infinity]
        let xs: [Double] = [-1.0, 0.0, 3.0, 9.0, 20.0, 24.0, 30.0, .nan, .infinity]
        assertIndexAndClampParityWithPointAt(lineMetrics: v, columnMetrics: h, xs: xs, ys: ys)
        assertComponentParityWith1D(lineMetrics: v, columnMetrics: h, xs: xs, ys: ys)
    }
}
