import XCTest
import TextEngineCore

/// The load-bearing correctness test. Every other suite compares `visualRowAt` against
/// arithmetic restated in the test file, so a coherent-but-wrong row model could satisfy
/// all of them. This one compares it against node 1's independently-written greedy packer,
/// driven across lines by node 2's cursor over a real `compute` range.
final class WrapRowQueryRoundTripTests: XCTestCase {
    private static let rowHeight = 10.0

    private func layout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: [10.0], breaks: []),                          // 1 row
                (advances: [10.0, 10.0, 10.0], breaks: [1, 2]),          // 3 rows
                (advances: [], breaks: []),                              // blank -> 1 row
                (advances: [10.0, 10.0], breaks: [1]),                   // 2 rows
                (advances: [10.0, 10.0, 10.0, 10.0], breaks: [1, 2, 3]), // 4 rows
            ],
            rowHeight: Self.rowHeight,
            wrapWidth: 10.0
        )
    }

    func testEveryStreamedRowIsFoundByItsOwnY() {
        let layout = layout()
        let input = VariableViewportInput(
            scrollOffsetY: 15.0, viewportHeight: 40.0,
            overscanLinesBefore: 1, overscanLinesAfter: 1)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else {
            return XCTFail("compute must succeed on a well-formed layout")
        }
        let streamed = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertFalse(streamed.isEmpty, "the fixture must produce a non-empty buffer range")
        XCTAssertEqual(streamed.count, range.bufferEndExclusive - range.bufferStart)

        for (offset, geometry) in streamed.enumerated() {
            let expectedGlobalRow = range.bufferStart + offset
            // Probe BOTH the exact row boundary (what a `<`/`<=` mutation moves) and the
            // row interior (which closes the class of compensating errors where a shifted
            // boundary and a shifted index cancel on boundary samples alone).
            for probe in [geometry.y, geometry.y + Self.rowHeight / 2] {
                guard case .row(let located) = ViewportVirtualizer.visualRowAt(y: probe, layout: layout) else {
                    XCTFail("expected .row at y=\(probe)"); continue
                }
                XCTAssertEqual(located.globalRow, expectedGlobalRow, "probe \(probe)")
                XCTAssertEqual(located.logicalLine, geometry.row.logicalLine, "probe \(probe)")
                XCTAssertEqual(located.rowInLine, geometry.row.rowInLine, "probe \(probe)")
            }
        }
    }
}
