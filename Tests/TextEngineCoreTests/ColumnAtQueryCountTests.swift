import XCTest
@testable import TextEngineCore

final class ColumnAtQueryCountTests: XCTestCase {
    private final class QueryCounter {
        var count = 0
    }

    // Counts every columnOffset probe. columnCount is NOT counted (mirrors the
    // vertical CountingLineMetrics, where lineCount is free).
    private struct CountingColumnMetrics: LineHorizontalMetricsSource {
        let base: UniformColumnMetrics
        let counter: QueryCounter

        init(columnsPerLine: Int, columnWidth: Double, counter: QueryCounter) {
            self.base = UniformColumnMetrics(columnsPerLine: columnsPerLine, columnWidth: columnWidth)
            self.counter = counter
        }

        func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.count += 1
            return base.columnOffset(inLine: line, column: column)
        }
    }

    private enum NativeSearchEvent: Equatable {
        case offset(Int, Int)   // (line, column)
        case native(Int, Double) // (line, x)
    }

    private final class NativeSearchCounter {
        var events: [NativeSearchEvent] = []
    }

    // Overrides columnIndex so the in-range path shows a .native event, recording
    // the exact dispatch order (mirror of the vertical NativeSearchMetrics).
    private struct NativeSearchColumnMetrics: LineHorizontalMetricsSource {
        let offsets: [Double] // one line's cumulative offsets
        let counter: NativeSearchCounter

        func columnCount(inLine line: Int) -> Int { offsets.count - 1 }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.events.append(.offset(line, column))
            return offsets[column]
        }
        func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
            counter.events.append(.native(line, x))
            var result = 0
            for index in 0..<(offsets.count - 1) {
                if offsets[index] <= x { result = index } else { break }
            }
            return result
        }
    }

    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value { capacity <<= 1; power += 1 }
        return power
    }

    func testInRangeUsesLogarithmicQueriesAtOneMillionCells() {
        let count = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingColumnMetrics(columnsPerLine: count, columnWidth: 8.0, counter: counter)

        let result = ViewportVirtualizer.columnAt(x: Double(count / 2) * 8.0 + 4.0, inLine: 0, metrics: metrics)

        guard case .column = result else { return XCTFail("expected .column, got \(result)") }
        let expectedMax = 2 + (ceilLog2(count) + 1)
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }

    func testBlankLineQueriesOnlyFirstOffset() {
        // A source whose line has 0 cells: columnCount 0, columnOffset(_,0)==0.
        struct BlankColumnMetrics: LineHorizontalMetricsSource {
            let counter: QueryCounter
            func columnCount(inLine line: Int) -> Int { 0 }
            func columnOffset(inLine line: Int, column: Int) -> Double { counter.count += 1; return 0.0 }
        }
        let counter = QueryCounter()
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: 3.0, inLine: 0, metrics: BlankColumnMetrics(counter: counter)), .empty)
        XCTAssertEqual(counter.count, 1)
    }

    func testClampBranchesDoNotSearch() {
        let count = 1_000_000

        let leftCounter = QueryCounter()
        let leftMetrics = CountingColumnMetrics(columnsPerLine: count, columnWidth: 8.0, counter: leftCounter)
        _ = ViewportVirtualizer.columnAt(x: -1.0, inLine: 0, metrics: leftMetrics)
        XCTAssertEqual(leftCounter.count, 2) // columnOffset(0) + width, no search

        let rightCounter = QueryCounter()
        let rightMetrics = CountingColumnMetrics(columnsPerLine: count, columnWidth: 8.0, counter: rightCounter)
        _ = ViewportVirtualizer.columnAt(x: Double(count) * 8.0 + 1.0, inLine: 0, metrics: rightMetrics)
        XCTAssertEqual(rightCounter.count, 2)
    }

    func testNonFiniteXDoesNotQueryOffsets() {
        let counter = QueryCounter()
        let metrics = CountingColumnMetrics(columnsPerLine: 1_000, columnWidth: 8.0, counter: counter)
        XCTAssertEqual(ViewportVirtualizer.columnAt(x: .nan, inLine: 0, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(counter.count, 0)
    }

    func testInRangeDispatchesToNativeHookAfterValidationProbes() {
        let counter = NativeSearchCounter()
        // offsets [0,10,30,35,80] on line 0; count == 4, width == 80.
        let metrics = NativeSearchColumnMetrics(offsets: [0.0, 10.0, 30.0, 35.0, 80.0], counter: counter)

        let result = ViewportVirtualizer.columnAt(x: 31.0, inLine: 0, metrics: metrics)

        XCTAssertEqual(result, .column(ColumnLocation(columnIndex: 2, clamp: .inRange)))
        XCTAssertEqual(counter.events, [.offset(0, 0), .offset(0, 4), .native(0, 31.0)])
    }

    func testNonInRangePathsNeverDispatchNative() {
        // blank -> [.offset(0,0)] ; clamp -> [.offset(0,0), .offset(0,count)] ; non-finite -> []
        let blankCounter = NativeSearchCounter()
        _ = ViewportVirtualizer.columnAt(x: 5.0, inLine: 0, metrics: NativeSearchColumnMetrics(offsets: [0.0], counter: blankCounter))
        XCTAssertEqual(blankCounter.events, [.offset(0, 0)])

        let clampCounter = NativeSearchCounter()
        _ = ViewportVirtualizer.columnAt(x: -1.0, inLine: 0, metrics: NativeSearchColumnMetrics(offsets: [0.0, 10.0, 30.0, 35.0, 80.0], counter: clampCounter))
        XCTAssertEqual(clampCounter.events, [.offset(0, 0), .offset(0, 4)])

        let nanCounter = NativeSearchCounter()
        _ = ViewportVirtualizer.columnAt(x: .nan, inLine: 0, metrics: NativeSearchColumnMetrics(offsets: [0.0, 10.0], counter: nanCounter))
        XCTAssertEqual(nanCounter.events, [])
    }
}
