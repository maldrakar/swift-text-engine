import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

// The --point-geometry-query checksum folds the GEOMETRY (both boxes, both fractions),
// not just the indices, and it is the "workload unchanged" anchor the gate-promotion
// slice leans on. Until these tests existed that property was asserted only by a source
// comment: a zeroed multiplier, a dropped field, or a reversion to --point-query's
// additive index-only fold would have left every test green.
//
// Both tests are built so that an index-only fold CANNOT pass them: each pair of points
// is chosen to be indistinguishable to --point-query's `lineIndex + clamp + columnIndex
// + clamp` accumulator.
final class PointGeometryChecksumTests: XCTestCase {

    // A drifted fraction must move the checksum. Both points land on the same line and
    // the same cell with the same clamps -- so the located INDICES are byte-identical,
    // as pointAt itself confirms below -- and differ only in where inside the two boxes
    // they fell. An index-only fold returns the same number for both.
    func testADriftedFractionChangesTheChecksum() {
        let v = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)        // line 2 = [32, 48)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)  // cell 2 = [16, 24)

        // (20, 40) -> line 2 fraction 0.50, cell 2 fraction 0.500
        // (21, 41) -> line 2 fraction 0.5625, cell 2 fraction 0.625
        let a = runPointGeometryQueryOperation(x: 20.0, y: 40.0, lineMetrics: v, columnMetrics: h)
        let b = runPointGeometryQueryOperation(x: 21.0, y: 41.0, lineMetrics: v, columnMetrics: h)

        XCTAssertEqual(a.failureCount, 0)
        XCTAssertEqual(b.failureCount, 0)

        // The premise: to an index-and-clamp fold these two points are the same point.
        XCTAssertEqual(
            ViewportVirtualizer.pointAt(x: 20.0, y: 40.0, lineMetrics: v, columnMetrics: h),
            ViewportVirtualizer.pointAt(x: 21.0, y: 41.0, lineMetrics: v, columnMetrics: h),
            "the two points must share indices and clamps, or this test proves nothing")

        XCTAssertNotEqual(
            a.checksum, b.checksum,
            "the checksum does not cover the fractions — a drifted fraction would leave it "
                + "byte-identical, and the promotion slice's 'workload unchanged' anchor with it")
    }

    // Swapping the two axes must move the checksum. On a square document (line height ==
    // column width) the swapped point yields the SAME SET of geometry values, merely
    // assigned to the other axis's fields -- so a fold that adds every field with one
    // shared multiplier cancels the swap exactly. This is the weakness the Slice 37 review
    // recorded (its P3 #5); distinct odd multipliers per field are what close it.
    func testAnAxisSwapChangesTheChecksum() {
        let v = UniformLineMetrics(lineCount: 8, lineHeight: 8.0)
        let h = UniformColumnMetrics(columnsPerLine: 8, columnWidth: 8.0)

        // (20, 36) -> line 4 box [32, 40) fraction 0.5, cell 2 box [16, 24) fraction 0.5
        // (36, 20) -> line 2 box [16, 24) fraction 0.5, cell 4 box [32, 40) fraction 0.5
        let point = runPointGeometryQueryOperation(x: 20.0, y: 36.0, lineMetrics: v, columnMetrics: h)
        let swapped = runPointGeometryQueryOperation(x: 36.0, y: 20.0, lineMetrics: v, columnMetrics: h)

        XCTAssertEqual(point.failureCount, 0)
        XCTAssertEqual(swapped.failureCount, 0)

        XCTAssertNotEqual(
            point.checksum, swapped.checksum,
            "the fold is blind to an axis swap — the two axes' fields must carry distinct "
                + "multipliers, or transposing x and y cancels out")
    }

    // The checksum is a determinism anchor across runs and platforms, so the same input
    // must fold to the same number twice. (Cheap, and it would catch a fold that picked up
    // uninitialised or run-dependent state.)
    func testTheChecksumIsReproducibleForTheSameInput() {
        let v = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)

        let first = runPointGeometryQueryOperation(x: 20.0, y: 40.0, lineMetrics: v, columnMetrics: h)
        let second = runPointGeometryQueryOperation(x: 20.0, y: 40.0, lineMetrics: v, columnMetrics: h)

        XCTAssertEqual(first.checksum, second.checksum)
    }
}
