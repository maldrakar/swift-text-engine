import XCTest
import TextEngineCore

/// Every row the document cursor streams is found by its own `y`, with an identical span.
/// Both sides run node 1's packer through the shared `advanceVisualRows`, so this pins
/// AGREEMENT — it is not independent evidence that the packing is right (that is the
/// packer's own suites). What it catches is an edit that unshares the walk.
final class WrapPointQueryRoundTripTests: XCTestCase {
    private static let rowHeight = 10.0
    private static let wrapWidth = 20.0

    /// Both kinds of line, because `greedyEnd` has two branches after Decision 12 and a
    /// fixture of one kind exercises one of them:
    ///   * lines 0 and 2 FIT the width (one row, packed in O(1) with no scan)
    ///   * lines 1 and 4 EXCEED it (interior rows scan)
    ///   * line 3 is blank
    private static func layout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: [10.0, 10.0], breaks: [1]),                             // fits: 1 row
                (advances: Array(repeating: 10.0, count: 6), breaks: Set(1..<6)),   // 3 rows
                (advances: [15.0], breaks: []),                                     // fits: 1 row
                (advances: [], breaks: []),                                         // blank: 1 row
                (advances: Array(repeating: 5.0, count: 12), breaks: Set(1..<12)),  // 3 rows
            ],
            rowHeight: rowHeight, wrapWidth: wrapWidth)
    }

    func testEveryStreamedRowIsFoundByItsOwnPoint() {
        let layout = Self.layout()

        // Fixture guard: both branches must be present, or this test covers one of them
        // while claiming both.
        var fitting = 0
        var wrapped = 0
        for line in 0..<layout.lineCount {
            let count = layout.columnCount(inLine: line)
            if layout.columnOffset(inLine: line, column: count) <= Self.wrapWidth { fitting += 1 } else { wrapped += 1 }
        }
        XCTAssertGreaterThan(fitting, 0, "fixture must carry a line that FITS the wrap width")
        XCTAssertGreaterThan(wrapped, 0, "fixture must carry a line that EXCEEDS it")

        let input = VariableViewportInput(
            scrollOffsetY: 15.0, viewportHeight: 60.0,
            overscanLinesBefore: 1, overscanLinesAfter: 1)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else {
            return XCTFail("compute must succeed on a well-formed layout")
        }
        let streamed = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertFalse(streamed.isEmpty, "the fixture must produce a non-empty buffer range")
        XCTAssertEqual(streamed.count, range.bufferEndExclusive - range.bufferStart)

        for (offset, geometry) in streamed.enumerated() {
            let expectedGlobalRow = range.bufferStart + offset
            // Both the exact row boundary (what a `<`/`<=` mutation moves) and the row
            // interior (which closes the compensating-error class).
            for probe in [geometry.y, geometry.y + Self.rowHeight / 2.0] {
                guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 0.0, y: probe, layout: layout) else {
                    XCTFail("expected .point at y=\(probe)"); continue
                }
                XCTAssertEqual(point.row.globalRow, expectedGlobalRow, "probe \(probe)")
                XCTAssertEqual(point.rowSpan, geometry.row, "probe \(probe)")
            }
        }
    }
}
