import XCTest
@testable import TextEngineCore

final class VariableViewportInputValueTests: XCTestCase {
    func testVariableViewportInputStoresFields() {
        let input = VariableViewportInput(
            scrollOffsetY: 12.0,
            viewportHeight: 100.0,
            overscanLinesBefore: 2,
            overscanLinesAfter: 3
        )

        XCTAssertEqual(input.scrollOffsetY, 12.0)
        XCTAssertEqual(input.viewportHeight, 100.0)
        XCTAssertEqual(input.overscanLinesBefore, 2)
        XCTAssertEqual(input.overscanLinesAfter, 3)
        XCTAssertEqual(input, input)
    }

    func testInvalidLineMetricsErrorIsDistinct() {
        XCTAssertNotEqual(ViewportValidationError.invalidLineMetrics, .nonFiniteValue)
    }
}
