import XCTest
@testable import TextEngineCore

final class LineGeometryAtEquivalenceTests: XCTestCase {
    private func assertGeometry(
        _ metrics: UniformLineMetrics,
        y: Double,
        index: Int,
        fraction: Double,
        clamp: LineLocation.Clamp,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let h = metrics.lineHeight
        let expected = LineGeometryQuery.geometry(
            LineGeometryLocation(
                geometry: LineGeometry(lineIndex: index, y: Double(index) * h, height: h),
                fractionInLine: fraction,
                clamp: clamp
            )
        )
        XCTAssertEqual(
            ViewportVirtualizer.lineGeometryAt(y: y, metrics: metrics),
            expected,
            "lineCount=\(metrics.lineCount), lineHeight=\(h), y=\(y)",
            file: file, line: line
        )
    }

    func testStructuralEquivalenceOverRepresentableUniformMetrics() {
        // Exactly-representable heights; counts well under 2^53 so Double(i)*h is
        // exact and the fractions (0.0, 0.5, 1.0) are exact.
        let heights: [Double] = [1.0, 10.0, 16.0, 12.5, 256.0]
        let counts = [1, 2, 3, 100, 100_000]

        for height in heights {
            for count in counts {
                let metrics = UniformLineMetrics(lineCount: count, lineHeight: height)
                let total = Double(count) * height

                // Below the document -> clamp to top, fraction 0.0, line 0 box.
                assertGeometry(metrics, y: -height, index: 0, fraction: 0.0, clamp: .clampedToTop)

                let ks = Set([0, 1, count / 2, count - 1].filter { $0 >= 0 && $0 < count })
                for k in ks {
                    // Exact line top -> fraction 0.0, in range.
                    assertGeometry(metrics, y: Double(k) * height, index: k, fraction: 0.0, clamp: .inRange)
                    // Mid-line -> fraction 0.5, in range.
                    assertGeometry(metrics, y: Double(k) * height + height / 2.0,
                                   index: k, fraction: 0.5, clamp: .inRange)
                }

                // At and past the end -> clamp to bottom, fraction 1.0, last-line box.
                assertGeometry(metrics, y: total, index: count - 1, fraction: 1.0, clamp: .clampedToBottom)
                assertGeometry(metrics, y: total + height, index: count - 1, fraction: 1.0, clamp: .clampedToBottom)
            }
        }
    }

    func testIndexAndClampParityWithLineAt() {
        let metrics = UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0)
        let total = 1_000.0 * 16.0
        var ys: [Double] = [-10.0, 0.0, total, total + 25.0]
        for k in [0, 1, 500, 999] {
            ys.append(Double(k) * 16.0)
            ys.append(Double(k) * 16.0 + 7.0)
        }
        for y in ys {
            let geometryResult = ViewportVirtualizer.lineGeometryAt(y: y, metrics: metrics)
            let lineResult = ViewportVirtualizer.lineAt(y: y, metrics: metrics)
            guard case let .geometry(loc) = geometryResult, case let .line(line) = lineResult else {
                return XCTFail("expected .geometry and .line for y=\(y), got \(geometryResult) / \(lineResult)")
            }
            XCTAssertEqual(loc.geometry.lineIndex, line.lineIndex, "index parity y=\(y)")
            XCTAssertEqual(loc.clamp, line.clamp, "clamp parity y=\(y)")
        }
    }
}
