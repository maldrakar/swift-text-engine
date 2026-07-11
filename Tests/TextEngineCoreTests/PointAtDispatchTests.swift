import XCTest
@testable import TextEngineCore

final class PointAtDispatchTests: XCTestCase {
    private enum Event: Equatable {
        case columnCount(Int)               // (line)
        case columnOffset(Int, Int)         // (line, column)
        case columnIndex(Int, Double)       // (line, x)
    }

    private final class EventLog {
        var events: [Event] = []
    }

    // Records every horizontal call. Wraps a UniformColumnMetrics for real answers,
    // so a .line path produces a genuine cell while logging the inLine threading.
    private struct RecordingColumnMetrics: LineHorizontalMetricsSource {
        let base: UniformColumnMetrics
        let log: EventLog
        func columnCount(inLine line: Int) -> Int {
            log.events.append(.columnCount(line)); return base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            log.events.append(.columnOffset(line, column)); return base.columnOffset(inLine: line, column: column)
        }
        func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
            log.events.append(.columnIndex(line, x)); return base.columnIndex(containingOffset: x, inLine: line)
        }
    }

    func testHorizontalNotConsultedOnEmptyDocument() {
        let log = EventLog()
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = RecordingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0), log: log)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 5.0, lineMetrics: v, columnMetrics: h), .empty)
        XCTAssertEqual(log.events, [], "horizontal source must not be touched on the empty-document path")
    }

    func testHorizontalNotConsultedOnVerticalFailure() {
        let log = EventLog()
        let v = UniformLineMetrics(lineCount: -1, lineHeight: 16.0)   // .negativeLineCount
        let h = RecordingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0), log: log)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 5.0, lineMetrics: v, columnMetrics: h),
                       .failure(.negativeLineCount))
        XCTAssertEqual(log.events, [], "horizontal source must not be touched on the vertical-failure path")
    }

    func testHorizontalConsultedOnceWithLocatedLineIndex() {
        let log = EventLog()
        // 10 lines x 16 -> totalHeight 160; y = 88 -> line 5 (80 <= 88 < 96).
        let v = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        let h = RecordingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0), log: log)
        let result = ViewportVirtualizer.pointAt(x: 12.0, y: 88.0, lineMetrics: v, columnMetrics: h)
        guard case let .point(location) = result else { return XCTFail("expected .point, got \(result)") }
        XCTAssertEqual(location.line.lineIndex, 5)
        // Every horizontal event carries inLine == 5 (the vertically-located line).
        for event in log.events {
            switch event {
            case let .columnCount(line): XCTAssertEqual(line, 5)
            case let .columnOffset(line, _): XCTAssertEqual(line, 5)
            case let .columnIndex(line, _): XCTAssertEqual(line, 5)
            }
        }
        // The in-range path dispatches through columnIndex exactly once.
        let nativeCalls = log.events.filter { if case .columnIndex = $0 { return true } else { return false } }
        XCTAssertEqual(nativeCalls.count, 1)
    }
}
