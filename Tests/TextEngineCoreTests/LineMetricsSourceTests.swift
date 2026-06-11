import XCTest
@testable import TextEngineCore

final class LineMetricsSourceTests: XCTestCase {
    func testUniformLineMetricsOffsetIsLinear() {
        let metrics = UniformLineMetrics(lineCount: 5, lineHeight: 16.0)

        XCTAssertEqual(metrics.lineCount, 5)
        XCTAssertEqual(metrics.offset(ofLine: 0), 0.0)
        XCTAssertEqual(metrics.offset(ofLine: 3), 48.0)
        XCTAssertEqual(metrics.offset(ofLine: 5), 80.0)
    }
}
