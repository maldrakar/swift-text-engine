import XCTest
@testable import TextEngineCore

final class LineAtEquivalenceTests: XCTestCase {
    private func assertLineAt(
        _ metrics: UniformLineMetrics,
        y: Double,
        _ expected: LineQuery,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            ViewportVirtualizer.lineAt(y: y, metrics: metrics),
            expected,
            "lineCount=\(metrics.lineCount), lineHeight=\(metrics.lineHeight), y=\(y)",
            file: file,
            line: line
        )
    }

    func testStructuralEquivalenceOverRepresentableUniformMetrics() {
        // Exactly-representable heights; counts well under 2^53 so Double(i)*h is
        // exact and strictly increasing (matches VariableUniformEquivalenceTests).
        let heights: [Double] = [1.0, 10.0, 16.0, 12.5, 256.0]
        let counts = [1, 2, 3, 100, 100_000]

        for height in heights {
            for count in counts {
                let metrics = UniformLineMetrics(lineCount: count, lineHeight: height)
                let total = Double(count) * height

                // Below the document.
                assertLineAt(metrics, y: -height,
                             .line(LineLocation(lineIndex: 0, clamp: .clampedToTop)))
                // First line top is in range.
                assertLineAt(metrics, y: 0.0,
                             .line(LineLocation(lineIndex: 0, clamp: .inRange)))

                // Product-built boundaries and mid-line points for a few k < count.
                let ks = Set([0, 1, count / 2, count - 1].filter { $0 >= 0 && $0 < count })
                for k in ks {
                    // Exact boundary offset(k) -> line k (half-open span).
                    assertLineAt(metrics, y: Double(k) * height,
                                 .line(LineLocation(lineIndex: k, clamp: .inRange)))
                    // Mid-line stays on line k.
                    assertLineAt(metrics, y: Double(k) * height + height / 2.0,
                                 .line(LineLocation(lineIndex: k, clamp: .inRange)))
                }

                // At and past the document end clamp to the last line.
                assertLineAt(metrics, y: total,
                             .line(LineLocation(lineIndex: count - 1, clamp: .clampedToBottom)))
                assertLineAt(metrics, y: total + height,
                             .line(LineLocation(lineIndex: count - 1, clamp: .clampedToBottom)))
            }
        }
    }
}
