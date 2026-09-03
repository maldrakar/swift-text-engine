import XCTest
import TextEngineCore

/// Node 4's behaviour. The fixture carries all three row kinds the ladder distinguishes:
/// a wrapped line (three equal rows), a blank line (one `[0, 0)` row), and a line whose
/// first row OVERFLOWS the wrap width (an unbreakable run wider than the width — node 1
/// packs it rather than force-breaking, so an `x` between `wrapWidth` and `rowSpan.width`
/// is a real point inside a real row).
final class WrapPointQueryTests: XCTestCase {
    static let rowHeight = 10.0
    static let wrapWidth = 20.0

    /// line 0: 6 cells x 10, breakable everywhere -> rows [0,2) [2,4) [4,6), each 20 wide
    /// line 1: blank                              -> one [0,0) row
    /// line 2: 5 cells x 10, break before 4 ONLY  -> rows [0,4) width 40 (OVERFLOW), [4,5) width 10
    /// firstVisualRow = [0, 3, 4, 6]; totalRows 6; total height 60.
    ///
    /// The overflow run is FOUR cells wide, not one, and that is the fixture's whole point:
    /// with a one-cell row `startColumn`, `endColumn - 1` and the hook's own answer are the
    /// SAME index, so no assertion in the index can tell the branches apart — the defect
    /// this suite already found once, on Decision 14's `>= total` fixture. At four cells the
    /// overflow band `(wrapWidth, rowSpan.width) = (20, 40)` still spans two whole cells, so
    /// an `x` inside it lands on a cell that is neither end of the span.
    static func layout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: Array(repeating: 10.0, count: 6), breaks: Set(1..<6)),
                (advances: [], breaks: []),
                (advances: Array(repeating: 10.0, count: 5), breaks: [4]),
            ],
            rowHeight: rowHeight,
            wrapWidth: wrapWidth)
    }

    private func located(
        x: Double, y: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) -> VisualPointLocation? {
        switch ViewportVirtualizer.visualPointAt(x: x, y: y, layout: Self.layout()) {
        case .point(let location):
            return location
        case .empty:
            XCTFail("expected .point, got .empty", file: file, line: line); return nil
        case .failure(let error):
            XCTFail("expected .point, got .failure(\(error))", file: file, line: line); return nil
        }
    }

    // Global row 1 = line 0, row 1: span [2, 4), rowLeft 20, width 20.
    func testInteriorOfAMiddleRowResolvesToItsCell() {
        guard let point = located(x: 5.0, y: 15.0) else { return }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 1, logicalLine: 0, rowInLine: 1, clamp: .inRange))
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 2, endColumn: 4, width: 20.0))
        // Line-ABSOLUTE (Decision 2): x = 5 is row-relative, cell 2 is the line's index.
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 2, clamp: .inRange)))
    }

    // Half-open spans: an x landing exactly on a cell boundary belongs to the LATER cell.
    func testExactCellBoundaryResolvesToTheLaterCell() {
        guard let point = located(x: 10.0, y: 15.0) else { return }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 3, clamp: .inRange)))
    }

    // Decision 1: the clamps land on the ROW's edges, not the line's.
    func testXAtTheRowWidthClampsToTheRowsLastCell() {
        guard let point = located(x: 20.0, y: 15.0) else { return }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 3, clamp: .clampedToRight)))
    }

    func testNegativeXClampsToTheRowsFirstCell() {
        guard let point = located(x: -1.0, y: 15.0) else { return }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 2, clamp: .clampedToLeft)))
    }

    // Decision 7: read from the span, not from a second columnCount probe.
    func testBlankLineResolvesToBlankLine() {
        guard let point = located(x: 5.0, y: 35.0) else { return }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 3, logicalLine: 1, rowInLine: 0, clamp: .inRange))
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 1, rowInLine: 0, startColumn: 0, endColumn: 0, width: 0.0))
        XCTAssertEqual(point.column, .blankLine)
    }

    // AC2: on an OVERFLOW row the clamp compares against the row's own advance sum, not
    // against wrapWidth -- so wrapWidth < x < rowSpan.width is .inRange, a real point.
    func testXBetweenWrapWidthAndRowWidthOnAnOverflowRowStaysInRange() {
        guard let point = located(x: 25.0, y: 45.0) else { return }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 4, logicalLine: 2, rowInLine: 0, clamp: .inRange))
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 2, rowInLine: 0, startColumn: 0, endColumn: 4, width: 40.0))
        XCTAssertGreaterThan(25.0, Self.wrapWidth, "the fixture must put x past the wrap width, or this covers nothing")
        // Fixture guard: the row must be wide enough that the RIGHT index is neither end of
        // the span, or this test pins the flag and nothing else. Cell 2 spans [20, 30).
        XCTAssertGreaterThanOrEqual(point.rowSpan.endColumn - point.rowSpan.startColumn, 3,
                                    "fixture: the overflow run must hold at least three cells")
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 2, clamp: .inRange)))
        XCTAssertNotEqual(2, point.rowSpan.startColumn, "fixture: the answer must differ from a clamp-to-left")
        XCTAssertNotEqual(2, point.rowSpan.endColumn - 1, "fixture: the answer must differ from a clamp-to-right")
    }

    // Both clamp flags observed together: the vertical one on `row`, the horizontal one
    // on the cell. A query that dropped either would still pass every test above.
    func testClampedYCrossedWithEachXBranch() {
        guard let topLeft = located(x: -1.0, y: -5.0) else { return }
        XCTAssertEqual(topLeft.row, VisualRowLocation(globalRow: 0, logicalLine: 0, rowInLine: 0, clamp: .clampedToTop))
        XCTAssertEqual(topLeft.column, .cell(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft)))

        guard let bottomRight = located(x: 100.0, y: 1_000.0) else { return }
        XCTAssertEqual(bottomRight.row, VisualRowLocation(globalRow: 5, logicalLine: 2, rowInLine: 1, clamp: .clampedToBottom))
        XCTAssertEqual(bottomRight.rowSpan, VisualRow(logicalLine: 2, rowInLine: 1, startColumn: 4, endColumn: 5, width: 10.0))
        XCTAssertEqual(bottomRight.column, .cell(ColumnLocation(columnIndex: 4, clamp: .clampedToRight)))

        guard let bottomInterior = located(x: 5.0, y: 1_000.0) else { return }
        XCTAssertEqual(bottomInterior.row.clamp, .clampedToBottom)
        // Line-absolute (Decision 2): the last row is [4, 5), so a row-relative x = 5 is the
        // LINE's cell 4 -- the bridge is rowSpan.startColumn.
        XCTAssertEqual(bottomInterior.column, .cell(ColumnLocation(columnIndex: 4, clamp: .inRange)))
    }

    /// Every row boundary, every row interior and BOTH clamp edges.
    private func ySweep() -> [Double] {
        var ys: [Double] = [-100.0, -0.001]
        for row in 0..<6 {
            let top = Double(row) * Self.rowHeight
            ys.append(top)                              // exact boundary
            ys.append(top + Self.rowHeight / 2.0)       // interior
            ys.append(top + Self.rowHeight - 0.001)     // just below the next boundary
        }
        ys.append(60.0)                                 // clamped to the bottom
        ys.append(1_000.0)
        return ys
    }

    /// Decision 3's central promise: `row` is `visualRowAt`'s answer, carried verbatim.
    ///
    /// Nothing else in this slice notices a re-derivation — the oracle compares against
    /// `pointAt`, the round-trip against the cursor, the count tests count probes; all
    /// three stay green if the vertical half is rebuilt inside the query. The CLAMP EDGES
    /// are what give this teeth: a fabricated location would most plausibly get the index
    /// right and the flag wrong.
    func testRowIsCarriedVerbatimFromVisualRowAt() {
        let layout = Self.layout()
        var sawTop = false
        var sawBottom = false
        for y in ySweep() {
            guard case .row(let expected) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
                XCTFail("fixture: visualRowAt must locate a row at y=\(y)"); continue
            }
            guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 5.0, y: y, layout: layout) else {
                XCTFail("expected .point at y=\(y)"); continue
            }
            XCTAssertEqual(point.row, expected, "y=\(y)")
            if expected.clamp == .clampedToTop { sawTop = true }
            if expected.clamp == .clampedToBottom { sawBottom = true }
        }
        XCTAssertTrue(sawTop && sawBottom, "the sweep must reach both clamp edges, or the pin has no teeth")
    }

    /// The duplicated fields agree. Named for what this actually catches: with the walk
    /// called at `k = rowInLine + 1`, the last row it consumes carries that `rowInLine` BY
    /// CONSTRUCTION, so the assertion can only fire on a wrong `k` — a plausible edit, and
    /// worth a test, but not evidence that two independently derived numbers agree.
    func testRowSpanAndRowAgreeOnTheirDuplicatedFields() {
        let layout = Self.layout()
        for y in ySweep() {
            guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 5.0, y: y, layout: layout) else {
                XCTFail("expected .point at y=\(y)"); continue
            }
            XCTAssertEqual(point.rowSpan.logicalLine, point.row.logicalLine, "y=\(y)")
            XCTAssertEqual(point.rowSpan.rowInLine, point.row.rowInLine, "y=\(y)")
        }
    }

    /// Decision 2's swept property, and the only test that reads Decision 6's clamp.
    /// Shared so Task 3 can drive it over the FP fixture where the clamp actually fires.
    func assertIndexInsideItsRowSpan<Layout: VisualRowLayoutSource>(
        layout: Layout, xs: [Double], ys: [Double],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for y in ys {
            for x in xs {
                guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: x, y: y, layout: layout) else {
                    XCTFail("expected .point at (x: \(x), y: \(y))", file: file, line: line); continue
                }
                guard case .cell(let cell) = point.column else { continue }  // blank rows have no cell
                XCTAssertGreaterThanOrEqual(cell.columnIndex, point.rowSpan.startColumn,
                                            "(x: \(x), y: \(y)) left the span", file: file, line: line)
                XCTAssertLessThan(cell.columnIndex, point.rowSpan.endColumn,
                                  "(x: \(x), y: \(y)) left the span", file: file, line: line)
            }
        }
    }

    func testTheIndexIsAlwaysInsideItsRowSpan() {
        assertIndexInsideItsRowSpan(
            layout: Self.layout(),
            xs: [-100.0, -0.001, 0.0, 0.001, 4.999, 5.0, 9.999, 10.0, 19.999, 20.0, 25.0, 30.0, 1_000.0],
            ys: ySweep())
    }

    // ---- Decision 6: Double arithmetic at magnitudes near 2^53 ----
    //
    // `rowSpan.width` is itself the rounded difference `columnOffset(end) - rowLeft`, so
    // an `x` STRICTLY below that difference can rebase to a value that rounds up to
    // `columnOffset(end)` or beyond. ulp is 2 at 1e16: every offset below is exactly
    // representable and strictly increasing, so these are legal inputs, and
    // `1e16 + 3.9` rounds to exactly `1e16 + 4`.

    /// Fixture 1 — the rounding lands INSIDE the line, so the hook answers with a cell
    /// belonging to the NEXT row and only the clamp confines it.
    ///
    ///   advances [1e16, 4, 4] -> offsets [0, 1e16, 1e16+4, 1e16+8], breaks before 1 and 2
    ///   wrapWidth 4:  row 0 = [0,1) (overflow), row 1 = [1,2) rowLeft 1e16 width 4,
    ///                 row 2 = [2,3)
    private static func fpClampLayout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [(advances: [1e16, 4.0, 4.0], breaks: [1, 2])],
            rowHeight: rowHeight, wrapWidth: 4.0)
    }

    /// Fixture 2 — split the tail into two cells and the rounding lands on the LINE's
    /// width, so Decision 14's `>= total` guard answers and the hook is never called
    /// (calling it would violate its `x < lineWidth` precondition).
    ///
    /// The located row must hold at least TWO cells. With a one-cell row the guard's
    /// answer (`endColumn - 1`) and a wrong one (`startColumn`) are the SAME index, so the
    /// fixture would pin only that the guard fires and not what it answers — a mutation to
    /// `raw = rowSpan.startColumn` survived the earlier single-cell fixture with the whole
    /// suite green. Column 2 is deliberately NOT a break opportunity, so the packer cannot
    /// split the tail back into two rows.
    ///
    ///   advances [1e16, 2, 2] -> offsets [0, 1e16, 1e16+2, 1e16+4], break before 1 only
    ///   wrapWidth 4:  row 0 = [0,1) (overflow), row 1 = [1,3) rowLeft 1e16 width 4
    private static func fpGuardLayout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [(advances: [1e16, 2.0, 2.0], breaks: [1])],
            rowHeight: rowHeight, wrapWidth: 4.0)
    }

    func testFixtureOneRoundsPastTheRowAndTheClampConfinesTheIndex() {
        let layout = Self.fpClampLayout()

        // The fixture must actually be the FP case, or this test proves nothing.
        XCTAssertEqual(layout.firstVisualRow(ofLine: 1), 3, "fixture: three rows")
        XCTAssertEqual(1e16 + 3.9, 1e16 + 4.0, "fixture: 3.9 must round up at this magnitude")
        XCTAssertEqual(layout.columnIndex(containingOffset: 1e16 + 3.9, inLine: 0), 2,
                       "the UNCLAMPED hook answers cell 2 -- outside row 1's [1, 2) span")

        // y = 15 -> global row 1 (rowHeight 10). x = 3.9 < rowSpan.width == 4.
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 3.9, y: 15.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 1, endColumn: 2, width: 4.0))
        // The clamp moves the INDEX and not the FLAG: x was inside [0, width), so a
        // right-edge report would be a different wrong answer.
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 1, clamp: .inRange)))
    }

    func testFixtureTwoAnswersFromTheTotalGuardWithoutCallingTheHook() {
        let log = ColumnHookLog()
        let layout = OverridingColumnIndexLayout(base: Self.fpGuardLayout(), log: log)

        XCTAssertEqual(layout.firstVisualRow(ofLine: 1), 2, "fixture: two rows")
        XCTAssertEqual(1e16 + 3.9, 1e16 + 4.0, "fixture: 3.9 must round up at this magnitude")

        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 3.9, y: 15.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 1, endColumn: 3, width: 4.0))
        // The fixture must SEPARATE the guard's answer from the plausible wrong one, or it
        // pins only that the guard fires. Two cells is the minimum that does.
        XCTAssertGreaterThanOrEqual(point.rowSpan.endColumn - point.rowSpan.startColumn, 2,
                                    "fixture: the guard's row must hold at least two cells")
        // x = 3.9 is inside the row's SECOND cell (row-relative [2, 4)): `endColumn - 1`
        // answers 2, and `raw = rowSpan.startColumn` would answer 1.
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 2, clamp: .inRange)))
        XCTAssertEqual(log.callCount, 0,
                       "rebased == total: the guard must answer, and the hook must not be called at x == lineWidth")
    }

    /// The swept property over the FP fixture — this is where drill (e) reddens it.
    func testTheIndexIsAlwaysInsideItsRowSpanOnTheFPFixture() {
        assertIndexInsideItsRowSpan(
            layout: Self.fpClampLayout(),
            xs: [-1.0, 0.0, 1e15, 3.9, 3.999, 4.0, 5.0],
            ys: [-1.0, 5.0, 15.0, 25.0, 100.0])
    }
}
