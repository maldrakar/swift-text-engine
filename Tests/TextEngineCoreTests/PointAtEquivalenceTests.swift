import XCTest
@testable import TextEngineCore

final class PointAtEquivalenceTests: XCTestCase {
    // Hand-built non-uniform horizontal source; blank line = empty advance vector.
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let advancesPerLine: [[Double]]
        func columnCount(inLine line: Int) -> Int { advancesPerLine[line].count }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            var sum = 0.0
            for i in 0..<column { sum += advancesPerLine[line][i] }
            return sum
        }
    }

    // The oracle: derive the expected PointQuery from the two 1D queries, then
    // assert pointAt equals it. Because the expected value is *defined* as the 1D
    // composition, this proves parity directly and derives the non-finite ->
    // .failure ordering automatically (validation precedes the zero-count branch).
    private func expected<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        x: Double, y: Double, lineMetrics: V, columnMetrics: H
    ) -> PointQuery {
        switch ViewportVirtualizer.lineAt(y: y, metrics: lineMetrics) {
        case let .failure(e): return .failure(e)
        case .empty: return .empty
        case let .line(l):
            switch ViewportVirtualizer.columnAt(x: x, inLine: l.lineIndex, metrics: columnMetrics) {
            case let .failure(e): return .failure(e)
            case .empty: return .point(PointLocation(line: l, column: .blankLine))
            case let .column(c): return .point(PointLocation(line: l, column: .cell(c)))
            }
        }
    }

    private func assertParity<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics: V, columnMetrics: H, totalHeight: Double, lineWidth: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let ys: [Double] = [-1.0, 0.0, totalHeight / 3.0, totalHeight / 2.0,
                            totalHeight, totalHeight + 5.0, .nan, .infinity, -.infinity]
        let xs: [Double] = [-1.0, 0.0, lineWidth / 3.0, lineWidth / 2.0,
                            lineWidth, lineWidth + 5.0, .nan, .infinity, -.infinity]
        for y in ys {
            for x in xs {
                let got = ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics)
                let want = expected(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics)
                XCTAssertEqual(got, want, "x=\(x) y=\(y)", file: file, line: line)
            }
        }
    }

    func testParityUniformSources() {
        let v = UniformLineMetrics(lineCount: 20, lineHeight: 16.0)         // totalHeight 320
        let h = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)   // width 80
        assertParity(lineMetrics: v, columnMetrics: h, totalHeight: 320.0, lineWidth: 80.0)
    }

    func testParityNonUniformSourcesWithBlankLine() {
        // 4 lines of varied heights; line 2 is blank (empty advance vector).
        let v = ArrayColumnMetricsBackedLineMetrics(heights: [10.0, 20.0, 5.0, 30.0]) // totalHeight 65
        let h = ArrayColumnMetrics(advancesPerLine: [[10.0, 30.0, 5.0], [8.0, 8.0], [], [50.0]])
        // lineWidth here is line 0's width (30 + ... ) = 45; the sweep hits every line
        // via the y grid, so per-line widths are all exercised.
        assertParity(lineMetrics: v, columnMetrics: h, totalHeight: 65.0, lineWidth: 45.0)
    }

    func testParityEmptyDocument() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)
        // totalHeight 0; the grid still crosses non-finite y, deriving .failure vs .empty.
        assertParity(lineMetrics: v, columnMetrics: h, totalHeight: 0.0, lineWidth: 40.0)
    }

    // A simple variable-height vertical source for the non-uniform parity case,
    // using cumulative prefix sums over a heights array (no reference-provider dep).
    private struct ArrayColumnMetricsBackedLineMetrics: LineMetricsSource {
        let cumulative: [Double]
        init(heights: [Double]) {
            var sums: [Double] = [0.0]
            var running = 0.0
            for hgt in heights { running += hgt; sums.append(running) }
            cumulative = sums
        }
        var lineCount: Int { cumulative.count - 1 }
        func offset(ofLine index: Int) -> Double { cumulative[index] }
    }
}
