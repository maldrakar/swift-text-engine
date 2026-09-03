import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

/// Byte-identity guard for the observational mode's checksum. A benchmark whose result is
/// never read can be deleted by a release build and still "run"; a checksum that folds one
/// of eight fields has the same hole for the other seven. Applied up front because
/// `PointGeometryChecksumTests` exists precisely because a reversion to an index-only fold
/// once passed silently — and `AGENTS.md` records that lesson by name.
final class WrapPointQueryChecksumTests: XCTestCase {
    private func location(
        globalRow: Int = 5, logicalLine: Int = 3, rowInLine: Int = 2,
        rowClamp: LineLocation.Clamp = .inRange,
        startColumn: Int = 4, endColumn: Int = 9, width: Double = 40.0,
        column: ColumnResolution = .cell(ColumnLocation(columnIndex: 6, clamp: .inRange))
    ) -> VisualPointLocation {
        VisualPointLocation(
            row: VisualRowLocation(globalRow: globalRow, logicalLine: logicalLine,
                                   rowInLine: rowInLine, clamp: rowClamp),
            rowSpan: VisualRow(logicalLine: logicalLine, rowInLine: rowInLine,
                               startColumn: startColumn, endColumn: endColumn, width: width),
            column: column)
    }

    func testEveryFieldAffectsTheChecksum() {
        let base = wrapPointQueryChecksum(location())
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(globalRow: 6)), "globalRow")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(logicalLine: 4)), "logicalLine")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(rowInLine: 3)), "rowInLine")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(rowClamp: .clampedToTop)), "the vertical clamp flag")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(rowClamp: .clampedToBottom)), "the vertical clamp flag")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(startColumn: 5)), "startColumn")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(endColumn: 10)), "endColumn")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(width: 41.0)), "rowSpan.width")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(
            location(column: .cell(ColumnLocation(columnIndex: 7, clamp: .inRange)))), "the cell index")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(
            location(column: .cell(ColumnLocation(columnIndex: 6, clamp: .clampedToLeft)))), "the horizontal clamp flag")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(
            location(column: .cell(ColumnLocation(columnIndex: 6, clamp: .clampedToRight)))), "the horizontal clamp flag")
    }

    /// Distinct multipliers: under an additive fold a +1 on one field and a −1 on another
    /// cancel, which is how an index-only regression hides.
    func testFieldsAreNotInterchangeable() {
        XCTAssertNotEqual(wrapPointQueryChecksum(location(globalRow: 6)),
                          wrapPointQueryChecksum(location(logicalLine: 4)))
        XCTAssertNotEqual(wrapPointQueryChecksum(location(startColumn: 5)),
                          wrapPointQueryChecksum(location(endColumn: 10)))
    }

    /// A blank row carries no cell, so its contribution must be a distinct sentinel rather
    /// than the absence of one — otherwise `.blankLine` collides with cell 0 `.inRange`.
    func testBlankLineCannotCollideWithACell() {
        let blank = wrapPointQueryChecksum(
            location(startColumn: 0, endColumn: 0, width: 0.0, column: .blankLine))
        let cellZero = wrapPointQueryChecksum(
            location(startColumn: 0, endColumn: 0, width: 0.0,
                     column: .cell(ColumnLocation(columnIndex: 0, clamp: .inRange))))
        XCTAssertNotEqual(blank, cellZero)
    }
}
