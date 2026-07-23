import XCTest
import TextEngineCore

final class WrapValidationTests: XCTestCase {
    private func failure<M: WrapMetricsSource>(_ query: VisualRowQuery<M>) -> ViewportValidationError? {
        if case .failure(let error) = query { return error }
        return nil
    }

    func testNegativeColumnCountFails() {
        let metrics = TestWrapMetrics(offsets: []) // columnCount -1
        XCTAssertEqual(
            failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 10.0, metrics: metrics)),
            .negativeColumnCount
        )
    }

    func testNonPositiveOrNonFiniteWidthFails() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0])
        for width in [0.0, -1.0, -Double.infinity, Double.nan] {
            XCTAssertEqual(
                failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: width, metrics: metrics)),
                .nonPositiveWrapWidth,
                "width=\(width)"
            )
        }
    }

    func testInfiniteWidthDoesNotFail() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0])
        guard case .rows = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: .infinity, metrics: metrics) else {
            return XCTFail("expected .rows for +infinity")
        }
    }

    func testFirstOffsetNonZeroFails() {
        let metrics = TestWrapMetrics(offsets: [5.0, 15.0]) // columnOffset(0) == 5
        XCTAssertEqual(
            failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics)),
            .invalidColumnMetrics
        )
    }

    func testZeroOrNonFiniteLineTotalFails() {
        for offsets in [[0.0, 0.0], [0.0, Double.infinity]] {
            let metrics = TestWrapMetrics(offsets: offsets)
            XCTAssertEqual(
                failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics)),
                .invalidColumnMetrics,
                "offsets=\(offsets)"
            )
        }
    }

    // Ordering: both count<0 AND width≤0 ⇒ count is checked first.
    func testLadderChecksCountBeforeWidth() {
        let metrics = TestWrapMetrics(offsets: []) // columnCount -1
        XCTAssertEqual(
            failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 0.0, metrics: metrics)),
            .negativeColumnCount
        )
    }

    // A blank line whose columnOffset(0) != 0 must fail with .invalidColumnMetrics,
    // NOT short-circuit to a blank row — pins "probe before blank short-circuit".
    func testBlankLineWithBadFirstOffsetFailsBeforeShortCircuit() {
        let metrics = TestWrapMetrics(offsets: [5.0]) // columnCount 0, columnOffset(0) == 5
        XCTAssertEqual(
            failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics)),
            .invalidColumnMetrics
        )
    }
}
