import XCTest
import TextEngineCore

/// Located-branch mapping for `visualRowAt`. Fixture: row counts [1, 3, 2] over three
/// logical lines at rowHeight 10 -> totalRows 6, firstVisualRow prefix [0, 1, 4, 6],
/// totalHeight 60.
final class WrapRowQueryTests: XCTestCase {
    private static let rowHeight = 10.0
    private static let totalRows = 6
    private static let totalHeight = 60.0

    /// Lines pack to 1, 3 and 2 rows at wrapWidth 10 (char-wrap on 10-wide cells).
    private func layout123() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: [10.0], breaks: []),                    // 1 row
                (advances: [10.0, 10.0, 10.0], breaks: [1, 2]),    // 3 rows
                (advances: [10.0, 10.0], breaks: [1]),             // 2 rows
            ],
            rowHeight: Self.rowHeight,
            wrapWidth: 10.0
        )
    }

    private func located(_ y: Double, _ layout: TestVisualRowLayout,
                         _ file: StaticString = #filePath, _ line: UInt = #line) -> VisualRowLocation? {
        guard case .row(let location) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
            XCTFail("expected .row at y=\(y)", file: file, line: line)
            return nil
        }
        return location
    }

    // The fixture must actually have the shape the rest of the file assumes.
    func testFixtureShape() {
        let layout = layout123()
        XCTAssertEqual(layout.lineCount, 3)
        XCTAssertEqual([0, 1, 2].map { layout.visualRowCount(inLine: $0) }, [1, 3, 2])
        XCTAssertEqual(layout.firstVisualRow(ofLine: 3), Self.totalRows)
    }

    func testInteriorOfAMultiRowLine() {
        // globalRow 3 sits in line 1 (rows 1..<4), as its second-from-last row.
        guard let location = located(35.0, layout123()) else { return }
        XCTAssertEqual(location.globalRow, 3)
        XCTAssertEqual(location.logicalLine, 1)
        XCTAssertEqual(location.rowInLine, 2)
        XCTAssertEqual(location.clamp, .inRange)
    }

    func testEverySingleRowRoundTripsItsOwnIndices() {
        let layout = layout123()
        let expected: [(line: Int, rowInLine: Int)] = [
            (0, 0), (1, 0), (1, 1), (1, 2), (2, 0), (2, 1),
        ]
        for globalRow in 0..<Self.totalRows {
            guard let location = located(Double(globalRow) * Self.rowHeight + 5.0, layout) else { return }
            XCTAssertEqual(location.globalRow, globalRow)
            XCTAssertEqual(location.logicalLine, expected[globalRow].line, "globalRow \(globalRow)")
            XCTAssertEqual(location.rowInLine, expected[globalRow].rowInLine, "globalRow \(globalRow)")
        }
    }

    // Half-open [top, bottom): a y exactly on a row top belongs to THAT row, not the
    // one above. This is the assertion a `<=` -> `<` mutation in the row-axis search
    // moves (falsifiability drill 1).
    func testExactRowTopBelongsToThatRow() {
        let layout = layout123()
        for globalRow in 0..<Self.totalRows {
            guard let location = located(Double(globalRow) * Self.rowHeight, layout) else { return }
            XCTAssertEqual(location.globalRow, globalRow, "y == \(globalRow) * rowHeight")
        }
    }

    func testLastInteriorYIsStillInRange() {
        guard let location = located(Self.totalHeight - 0.001, layout123()) else { return }
        XCTAssertEqual(location.globalRow, Self.totalRows - 1)
        XCTAssertEqual(location.logicalLine, 2)
        XCTAssertEqual(location.rowInLine, 1)
        XCTAssertEqual(location.clamp, .inRange)
    }

    // Clamped queries take no special case: both edges flow through the same two
    // provider calls as an in-range hit, so line/rowInLine are right by construction
    // (spec Decision 7).
    func testClampedToTop() {
        guard let location = located(-1.0, layout123()) else { return }
        XCTAssertEqual(location.globalRow, 0)
        XCTAssertEqual(location.logicalLine, 0)
        XCTAssertEqual(location.rowInLine, 0)
        XCTAssertEqual(location.clamp, .clampedToTop)
    }

    func testClampedToBottomNamesTheLastRowOfTheLastLine() {
        guard let location = located(Self.totalHeight, layout123()) else { return }
        XCTAssertEqual(location.globalRow, Self.totalRows - 1)
        XCTAssertEqual(location.logicalLine, 2)
        XCTAssertEqual(location.rowInLine, 1)
        XCTAssertEqual(location.clamp, .clampedToBottom)
    }

    func testEmptyDocumentIsEmptyNotFailure() {
        let layout = TestVisualRowLayout(lines: [], rowHeight: Self.rowHeight, wrapWidth: 10.0)
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 0, layout: layout), .empty)
    }

    // A blank logical line still occupies exactly one visual row (node 1's contract),
    // so it is addressable by y like any other.
    func testBlankLineIsAddressable() {
        let layout = TestVisualRowLayout(
            lines: [(advances: [10.0], breaks: []), (advances: [], breaks: [])],
            rowHeight: Self.rowHeight, wrapWidth: 10.0
        )
        XCTAssertEqual(layout.firstVisualRow(ofLine: 2), 2)
        guard let location = located(15.0, layout) else { return }
        XCTAssertEqual(location.globalRow, 1)
        XCTAssertEqual(location.logicalLine, 1)
        XCTAssertEqual(location.rowInLine, 0)
    }
}
