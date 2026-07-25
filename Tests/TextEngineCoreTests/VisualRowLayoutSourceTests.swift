import XCTest
@testable import TextEngineCore

final class VisualRowLayoutSourceTests: XCTestCase {
    // Lines pack to rowCounts [2, 1, 3] at this width -> firstVisualRow [0,2,3,6].
    // Line 0: 3 cells advance 10 each, break at {1,2}, width 20 -> rows [0,2),[2,3) = 2.
    // Line 1: 1 cell advance 5, no break, width 20 -> 1 row.
    // Line 2: 3 cells advance 30 each, break at {1,2}, width 20 (each cell overflows) -> 3 rows.
    private func layout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: [10, 10, 10], breaks: [1, 2]),
                (advances: [5], breaks: []),
                (advances: [30, 30, 30], breaks: [1, 2]),
            ],
            rowHeight: 4.0,
            wrapWidth: 20.0
        )
    }

    func testFirstVisualRowPrefixSum() {
        let l = layout()
        XCTAssertEqual(l.lineCount, 3)
        XCTAssertEqual(l.visualRowCount(inLine: 0), 2)
        XCTAssertEqual(l.visualRowCount(inLine: 1), 1)
        XCTAssertEqual(l.visualRowCount(inLine: 2), 3)
        XCTAssertEqual((0...3).map { l.firstVisualRow(ofLine: $0) }, [0, 2, 3, 6])
    }

    func testLogicalLineContainingVisualRowDefault() {
        let l = layout()
        // firstVisualRow = [0,2,3,6]; largest L with firstVisualRow(L) <= g.
        XCTAssertEqual((0..<6).map { l.logicalLine(containingVisualRow: $0) }, [0, 0, 1, 2, 2, 2])
    }
}
