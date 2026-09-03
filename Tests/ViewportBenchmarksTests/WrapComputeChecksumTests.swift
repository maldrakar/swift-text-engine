import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

/// D-33. `--wrap-compute`'s `checksum=` is the witness Decisions 12 and 13 rest their
/// result-preservation argument on: both are result-preserving BY CONSTRUCTION, so neither
/// adds a result assertion, and what covers them is a fold over 100 000 lines at three
/// widths that stays byte-identical across every edit. Until this file, nothing pinned that
/// the fold can MOVE — a zeroed drain half would print an equally stable number and every
/// byte-identity claim built on it would be vacuous.
///
/// Two halves, two pins: the combination must read both operands, and the drain fold must
/// read every row rather than the first.
final class WrapComputeChecksumTests: XCTestCase {

    /// A layout identical to `base` except that ONE line is a cell shorter, which moves
    /// exactly one row's `endColumn` and nothing else: at 8 cells and width 4 the line
    /// packs [0,4) [4,8), and at 7 cells it packs [0,4) [4,7) — still two rows, so the
    /// prefix sum and row counts stay honest and only the fold can notice.
    private struct ShortenedLineLayout: VisualRowLayoutSource {
        let base: BenchmarkWrapLayout
        let shortLine: Int

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int {
            line == shortLine ? base.columnCount(inLine: line) - 1 : base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double { base.columnOffset(inLine: line, column: column) }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { base.canBreak(beforeColumn: column, inLine: line) }
        func visualRowCount(inLine line: Int) -> Int { base.visualRowCount(inLine: line) }
        func firstVisualRow(ofLine line: Int) -> Int { base.firstVisualRow(ofLine: line) }
    }

    /// Half 1: the printed value reads BOTH measurements. A reversion to
    /// `computeMeasured.checksum` alone is the exact defect D-33 names.
    func testBothHalvesAffectTheChecksum() {
        let base = wrapComputeChecksum(compute: 5, drain: 7)
        XCTAssertNotEqual(base, wrapComputeChecksum(compute: 6, drain: 7), "the compute half must be folded")
        XCTAssertNotEqual(base, wrapComputeChecksum(compute: 5, drain: 8), "the drain half must be folded")
        XCTAssertNotEqual(base, wrapComputeChecksum(compute: 5, drain: 0),
                          "zeroing the drain half must move the value -- it is the half that witnesses packing")
    }

    /// Half 2: the drain fold reads EVERY row's `endColumn`, not the first. `drainVisualRows`
    /// is what the checksum's drain half is made of, and a fold that stopped after one row
    /// would leave `WrapComputeDrainTests` (D-29) entirely green.
    func testDrainFoldsEveryRowsEndColumnNotTheFirst() {
        // 64 lines x 8 cells at width 4 -> 2 rows per line, 128 rows.
        let base = BenchmarkWrapLayout(lineCount: 64, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        let input = VariableViewportInput(scrollOffsetY: 40.0, viewportHeight: 100.0,
                                          overscanLinesBefore: 4, overscanLinesAfter: 4)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: base) else {
            return XCTFail("expected success")
        }

        // Find a row that is NOT the range's first and is its line's SECOND row -- the row
        // whose endColumn the perturbation moves. A first-row-only fold cannot see it.
        var streamed: [VisualRowGeometry] = []
        var cursor = ViewportVirtualizer.visualRowGeometry(for: range, layout: base)
        while let geometry = cursor.next() { streamed.append(geometry) }
        XCTAssertGreaterThan(streamed.count, 2, "the fixture must stream several rows")
        guard let target = streamed.dropFirst().first(where: { $0.row.rowInLine == 1 }) else {
            return XCTFail("the range must contain a non-first row that is its line's second row")
        }

        let perturbed = ShortenedLineLayout(base: base, shortLine: target.row.logicalLine)
        XCTAssertEqual(perturbed.visualRowCount(inLine: target.row.logicalLine), 2,
                       "the perturbation must move an endColumn, not a row count")

        let honest = drainVisualRows(range, layout: base)
        let moved = drainVisualRows(range, layout: perturbed)
        XCTAssertGreaterThan(honest, 0, "the drain must have streamed rows")
        XCTAssertEqual(honest - moved, 1,
                       "exactly one row's endColumn moved by one, and the fold must carry it")
    }
}
