import XCTest
@testable import TextEngineCore

final class LineAtTests: XCTestCase {
    // Contract-violating providers for the defensive validation checks.
    private struct NegativeCountMetrics: LineMetricsSource {
        var lineCount: Int { -1 }
        func offset(ofLine index: Int) -> Double { 0.0 }
    }
    private struct BadFirstOffsetMetrics: LineMetricsSource {
        var lineCount: Int { 3 }
        func offset(ofLine index: Int) -> Double { Double(index) + 1.0 } // offset(0) == 1
    }
    private struct ZeroTotalMetrics: LineMetricsSource {
        var lineCount: Int { 2 }
        func offset(ofLine index: Int) -> Double { 0.0 } // offset(0) == 0, total == 0
    }

    // MARK: failure + empty outcomes

    func testNegativeLineCountFails() {
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: NegativeCountMetrics()),
                       .failure(.negativeLineCount))
    }

    func testNonFiniteYFails() {
        let metrics = UniformLineMetrics(lineCount: 5, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: .nan, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: .infinity, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: -.infinity, metrics: metrics), .failure(.nonFiniteValue))
    }

    func testInvalidFirstOffsetFails() {
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 1.0, metrics: BadFirstOffsetMetrics()),
                       .failure(.invalidLineMetrics))
    }

    func testNonPositiveTotalHeightFails() {
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 1.0, metrics: ZeroTotalMetrics()),
                       .failure(.invalidLineMetrics))
    }

    func testEmptyDocumentIsEmptyForAnyY() {
        let metrics = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: -5.0, metrics: metrics), .empty)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics), .empty)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 100.0, metrics: metrics), .empty)
    }

    // MARK: clamp flags

    func testClampToTopForNegativeY() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: -0.001, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .clampedToTop)))
    }

    func testZeroIsInRangeAtLineZero() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
    }

    func testClampToBottomAtAndPastTotalHeight() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        let total = 10.0 * 16.0
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: total, metrics: metrics),
                       .line(LineLocation(lineIndex: 9, clamp: .clampedToBottom)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: total + 100.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 9, clamp: .clampedToBottom)))
    }

    // MARK: in-range resolution

    func testExactBoundaryResolvesToStartingLine() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 16.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 1, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 16.0 * 5.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 5, clamp: .inRange)))
    }

    func testMidLineResolvesToContainingLine() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 16.0 * 3.0 + 8.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 3, clamp: .inRange)))
    }

    func testNonUniformMetricsResolveCorrectly() {
        // offsets: [0, 10, 40, 45, 95]; lineCount = 4
        let metrics = ListLineMetrics(heights: [10.0, 30.0, 5.0, 50.0])
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 9.999, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 10.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 1, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 44.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 2, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 45.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 3, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 94.999, metrics: metrics),
                       .line(LineLocation(lineIndex: 3, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 95.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 3, clamp: .clampedToBottom)))
    }

    func testSingleLineDocument() {
        let metrics = UniformLineMetrics(lineCount: 1, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: -1.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .clampedToTop)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 8.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 16.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .clampedToBottom)))
    }
}
