import XCTest
@testable import TextEngineCore

final class PointGeometryAtQueryCountTests: XCTestCase {
    private final class Counter {
        var offsetCalls = 0
        var columnOffsetCalls = 0
    }

    private struct CountingLineMetrics: LineMetricsSource {
        let base: UniformLineMetrics
        let counter: Counter
        var lineCount: Int { base.lineCount }
        func offset(ofLine index: Int) -> Double {
            counter.offsetCalls += 1
            return base.offset(ofLine: index)
        }
    }

    private struct CountingColumnMetrics: LineHorizontalMetricsSource {
        let base: UniformColumnMetrics
        let counter: Counter
        func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.columnOffsetCalls += 1
            return base.columnOffset(inLine: line, column: column)
        }
    }

    // pointGeometryAt must cost exactly pointAt + 2 offset probes + 2 columnOffset
    // probes: the two boxes, and nothing else. A future refactor that re-runs a
    // search, or probes a neighbour it does not need, moves these numbers.
    func testAddsExactlyFourProbesOverPointAt() {
        let flat = Counter()
        let rich = Counter()
        let flatV = CountingLineMetrics(base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: flat)
        let flatH = CountingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 64, columnWidth: 8.0), counter: flat)
        let richV = CountingLineMetrics(base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: rich)
        let richH = CountingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 64, columnWidth: 8.0), counter: rich)

        // An in-range point, so both axes take their full search path.
        _ = ViewportVirtualizer.pointAt(x: 133.0, y: 4_002.0, lineMetrics: flatV, columnMetrics: flatH)
        _ = ViewportVirtualizer.pointGeometryAt(x: 133.0, y: 4_002.0, lineMetrics: richV, columnMetrics: richH)

        XCTAssertEqual(rich.offsetCalls, flat.offsetCalls + 2, "vertical box costs exactly two offset probes")
        XCTAssertEqual(rich.columnOffsetCalls, flat.columnOffsetCalls + 2, "cell box costs exactly two columnOffset probes")
    }

    // A clamped point must not cost more than an in-range one: the clamp fractions
    // are constants (0.0 / 1.0), not computed from extra probes.
    func testClampedPointCostsTheSameFourProbes() {
        let flat = Counter()
        let rich = Counter()
        let flatV = CountingLineMetrics(base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: flat)
        let flatH = CountingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 64, columnWidth: 8.0), counter: flat)
        let richV = CountingLineMetrics(base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: rich)
        let richH = CountingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 64, columnWidth: 8.0), counter: rich)

        _ = ViewportVirtualizer.pointAt(x: -5.0, y: 99_999.0, lineMetrics: flatV, columnMetrics: flatH)
        _ = ViewportVirtualizer.pointGeometryAt(x: -5.0, y: 99_999.0, lineMetrics: richV, columnMetrics: richH)

        XCTAssertEqual(rich.offsetCalls, flat.offsetCalls + 2)
        XCTAssertEqual(rich.columnOffsetCalls, flat.columnOffsetCalls + 2)
    }
}
