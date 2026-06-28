import XCTest
@testable import TextEngineCore

final class ComputeNativePrefixSearchTests: XCTestCase {
    private final class QueryCounter {
        var count = 0
    }

    private struct CountingLineMetrics: LineMetricsSource {
        let base: UniformLineMetrics
        let counter: QueryCounter

        init(lineCount: Int, lineHeight: Double, counter: QueryCounter) {
            self.base = UniformLineMetrics(lineCount: lineCount, lineHeight: lineHeight)
            self.counter = counter
        }

        var lineCount: Int { base.lineCount }

        func offset(ofLine index: Int) -> Double {
            counter.count += 1
            return base.offset(ofLine: index)
        }
    }

    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value {
            capacity <<= 1
            power += 1
        }
        return power
    }

    func testDefaultFirstLineIndexAtOrAboveReturnsSmallestIndexAtOrAbove() {
        let metrics = CountingLineMetrics(lineCount: 5, lineHeight: 10.0, counter: QueryCounter())
        // offsets: 0,10,20,30,40,50
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 20.0, startingAtLine: 0), 2) // exact top -> that line
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 21.0, startingAtLine: 0), 3) // interior -> next line
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 0.0, startingAtLine: 0), 0)
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 45.0, startingAtLine: 0), 5) // last interior -> lineCount
    }

    func testDefaultFirstLineIndexAtOrAboveUsesLogarithmicFallback() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)

        let index = metrics.firstLineIndex(
            withOffsetAtOrAbove: Double(lineCount / 2) * 16.0 + 8.0,
            startingAtLine: 0
        )

        XCTAssertEqual(index, lineCount / 2 + 1)
        XCTAssertLessThanOrEqual(counter.count, ceilLog2(lineCount) + 1)
        XCTAssertLessThan(counter.count, 100)
    }

    func testFirstLineIndexAtOrAboveHintNarrowsSearch() {
        let lineCount = 1_000_000
        let target = Double(lineCount - 2) * 16.0 // deep scroll: answer near the end

        let wide = QueryCounter()
        let wideMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: wide)
        let wideIndex = wideMetrics.firstLineIndex(withOffsetAtOrAbove: target, startingAtLine: 0)

        let narrow = QueryCounter()
        let narrowMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: narrow)
        let narrowIndex = narrowMetrics.firstLineIndex(withOffsetAtOrAbove: target, startingAtLine: lineCount - 4)

        XCTAssertEqual(wideIndex, lineCount - 2)
        XCTAssertEqual(narrowIndex, lineCount - 2)
        // Same answer, but the hint must strictly reduce the probe count at deep scroll.
        XCTAssertLessThan(narrow.count, wide.count)
    }

    private enum ComputeSearchEvent: Equatable {
        case offset(Int)
        case lineIndex(Double)
        case firstAtOrAbove(Double, Int)
    }

    private final class ComputeSearchRecorder {
        var events: [ComputeSearchEvent] = []
    }

    // Spy that overrides BOTH native hooks so a dispatched compute never falls
    // back to offset-based binary search. offset() is therefore called only for
    // the two O(1) contract probes.
    private struct SpyMetrics: LineMetricsSource {
        let offsets: [Double] // length lineCount + 1
        let recorder: ComputeSearchRecorder

        var lineCount: Int { offsets.count - 1 }

        func offset(ofLine index: Int) -> Double {
            recorder.events.append(.offset(index))
            return offsets[index]
        }

        func lineIndex(containingOffset y: Double) -> Int {
            recorder.events.append(.lineIndex(y))
            var result = 0
            for i in 0..<(offsets.count - 1) {
                if offsets[i] <= y { result = i } else { break }
            }
            return result
        }

        func firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int {
            recorder.events.append(.firstAtOrAbove(y, lowerBound))
            var result = offsets.count - 1
            for i in lowerBound..<offsets.count {
                if offsets[i] >= y { result = i; break }
            }
            return result
        }
    }

    func testComputeDispatchesBothBoundarySearchesToNativeHooks() {
        let recorder = ComputeSearchRecorder()
        // 4 lines, tops at 0,10,30,35, total height 80.
        let metrics = SpyMetrics(offsets: [0.0, 10.0, 30.0, 35.0, 80.0], recorder: recorder)
        let input = VariableViewportInput(
            scrollOffsetY: 12.0,
            viewportHeight: 20.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        guard case .success = ViewportVirtualizer.compute(input, metrics: metrics) else {
            return XCTFail("expected success")
        }

        // effectiveOffsetY = 12 (< maxOffset 60). visible-start = lineIndex(12) = 1,
        // so visible-end = firstAtOrAbove(32, lowerBound: 1). offset() only for the
        // two contract probes (0 and lineCount=4).
        XCTAssertEqual(recorder.events, [
            .offset(0),
            .offset(4),
            .lineIndex(12.0),
            .firstAtOrAbove(32.0, 1)
        ])
    }
}
