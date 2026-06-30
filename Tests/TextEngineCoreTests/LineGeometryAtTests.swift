import XCTest
@testable import TextEngineCore

final class LineGeometryAtTests: XCTestCase {
    private func geom(_ index: Int, _ y: Double, _ height: Double) -> LineGeometry {
        LineGeometry(lineIndex: index, y: y, height: height)
    }

    // MARK: failure + empty outcomes (inherited from lineAt)

    func testNegativeLineCountFails() {
        let metrics = ClosureLineMetrics(lineCount: -1, offsetForLine: { _ in 0.0 })
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics),
                       .failure(.negativeLineCount))
    }

    func testNonFiniteYFails() {
        let metrics = UniformLineMetrics(lineCount: 5, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: .nan, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: .infinity, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -.infinity, metrics: metrics), .failure(.nonFiniteValue))
    }

    func testInvalidFirstOffsetFails() {
        let metrics = ClosureLineMetrics(lineCount: 3, offsetForLine: { Double($0) + 1.0 })
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 1.0, metrics: metrics),
                       .failure(.invalidLineMetrics))
    }

    func testNonPositiveTotalHeightFails() {
        let metrics = ClosureLineMetrics(lineCount: 2, offsetForLine: { _ in 0.0 })
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 1.0, metrics: metrics),
                       .failure(.invalidLineMetrics))
    }

    func testEmptyDocumentIsEmptyForAnyY() {
        let metrics = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -5.0, metrics: metrics), .empty)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics), .empty)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 100.0, metrics: metrics), .empty)
    }

    // MARK: in-range geometry + fraction

    func testExactLineTopHasZeroFraction() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 16.0 * 5.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(5, 80.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .inRange)))
    }

    func testMidLineHasHalfFraction() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 16.0 * 3.0 + 8.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(3, 48.0, 16.0),
                                                      fractionInLine: 0.5, clamp: .inRange)))
    }

    func testZeroIsInRangeAtLineZero() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .inRange)))
    }

    // MARK: clamp fractions

    func testClampToTopHasZeroFractionOnFirstLine() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -0.001, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .clampedToTop)))
    }

    func testClampToBottomHasUnitFractionOnLastLine() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        let total = 10.0 * 16.0
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: total, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(9, 144.0, 16.0),
                                                      fractionInLine: 1.0, clamp: .clampedToBottom)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: total + 100.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(9, 144.0, 16.0),
                                                      fractionInLine: 1.0, clamp: .clampedToBottom)))
    }

    // MARK: non-uniform metrics

    func testNonUniformGeometryAndFraction() {
        // heights [10,30,5,50] -> offsets [0,10,40,45,95], total 95, lineCount 4
        let metrics = ListLineMetrics(heights: [10.0, 30.0, 5.0, 50.0])
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 10.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(1, 10.0, 30.0),
                                                      fractionInLine: 0.0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 25.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(1, 10.0, 30.0),
                                                      fractionInLine: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 42.5, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(2, 40.0, 5.0),
                                                      fractionInLine: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -1.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 10.0),
                                                      fractionInLine: 0.0, clamp: .clampedToTop)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 95.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(3, 45.0, 50.0),
                                                      fractionInLine: 1.0, clamp: .clampedToBottom)))
    }

    func testSingleLineDocument() {
        let metrics = UniformLineMetrics(lineCount: 1, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -1.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .clampedToTop)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 8.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 16.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 1.0, clamp: .clampedToBottom)))
    }
}
