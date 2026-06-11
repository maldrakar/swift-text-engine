import XCTest
@testable import TextEngineCore

final class VariableUniformEquivalenceTests: XCTestCase {
    private func assertEquivalent(
        lineCount: Int,
        lineHeight: Double,
        scrollOffsetY: Double,
        viewportHeight: Double,
        overscanBefore: Int,
        overscanAfter: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fixed = ViewportVirtualizer.compute(
            ViewportInput(
                lineCount: lineCount,
                lineHeight: lineHeight,
                scrollOffsetY: scrollOffsetY,
                viewportHeight: viewportHeight,
                overscanLinesBefore: overscanBefore,
                overscanLinesAfter: overscanAfter
            )
        )
        let variable = ViewportVirtualizer.compute(
            VariableViewportInput(
                scrollOffsetY: scrollOffsetY,
                viewportHeight: viewportHeight,
                overscanLinesBefore: overscanBefore,
                overscanLinesAfter: overscanAfter
            ),
            metrics: UniformLineMetrics(lineCount: lineCount, lineHeight: lineHeight)
        )
        XCTAssertEqual(
            variable,
            fixed,
            "lineCount=\(lineCount), lineHeight=\(lineHeight), scrollOffsetY=\(scrollOffsetY), viewportHeight=\(viewportHeight), overscan=(\(overscanBefore), \(overscanAfter))",
            file: file,
            line: line
        )
    }

    func testMatchesFixedAcrossRepresentableHeights() {
        let heights: [Double] = [1.0, 10.0, 16.0, 12.5, 256.0]
        // Counts stay well under 2^53, so Double(i) * lineHeight is strictly
        // increasing and the metrics honor their own contract.
        let counts = [1, 2, 3, 100, 100_000]

        for height in heights {
            for count in counts {
                let total = Double(count) * height
                let positions: [Double] = [
                    -height,                          // negative -> clamp to top
                    0.0,                              // first line top
                    height,                           // second line top
                    Double(count / 2) * height,       // a mid-document line top
                    Double(count / 2) * height + height / 2, // mid-line
                    total,                            // at the document end
                    total + height                    // past the document end
                ]
                let viewports: [Double] = [0.0, height, height * 3 + height / 2, total + height]

                for position in positions {
                    for viewport in viewports {
                        assertEquivalent(
                            lineCount: count, lineHeight: height,
                            scrollOffsetY: position, viewportHeight: viewport,
                            overscanBefore: 0, overscanAfter: 0
                        )
                        assertEquivalent(
                            lineCount: count, lineHeight: height,
                            scrollOffsetY: position, viewportHeight: viewport,
                            overscanBefore: 5, overscanAfter: 7
                        )
                    }
                }
            }
        }
    }

    // Clamp-at-end special case ONLY. UniformLineMetrics at Int.max is NOT
    // strictly increasing (consecutive Ints above 2^53 collapse to the same
    // Double), so this must not exercise the offset->line search — and it does
    // not: scrollOffsetY clamps to totalHeight, so both paths take the
    // `target >= totalHeight -> visibleStart == lineCount` early-out. This only
    // proves clamp/overflow-safety, not strict-increasing equivalence.
    func testMatchesFixedForIntMaxClamp() {
        assertEquivalent(
            lineCount: Int.max, lineHeight: 1.0,
            scrollOffsetY: Double(Int.max), viewportHeight: 0.0,
            overscanBefore: 0, overscanAfter: 0
        )
    }
}
