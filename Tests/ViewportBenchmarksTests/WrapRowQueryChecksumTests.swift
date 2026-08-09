import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

/// Byte-identity guard for the observational mode's anti-dead-code checksum. A benchmark
/// whose result is never read can be deleted by a release build and still "run"; a
/// checksum that folds only one index has the same hole for the other two. Applied up
/// front here because `PointGeometryChecksumTests` exists precisely because a reversion to
/// an index-only fold once passed silently.
final class WrapRowQueryChecksumTests: XCTestCase {
    private func location(globalRow: Int, logicalLine: Int, rowInLine: Int) -> VisualRowLocation {
        VisualRowLocation(globalRow: globalRow, logicalLine: logicalLine, rowInLine: rowInLine, clamp: .inRange)
    }

    func testFoldsAllThreeFields() {
        let base = location(globalRow: 5, logicalLine: 3, rowInLine: 2)
        XCTAssertNotEqual(wrapRowQueryChecksum(base),
                          wrapRowQueryChecksum(location(globalRow: 6, logicalLine: 3, rowInLine: 2)),
                          "globalRow must affect the checksum")
        XCTAssertNotEqual(wrapRowQueryChecksum(base),
                          wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 4, rowInLine: 2)),
                          "logicalLine must affect the checksum")
        XCTAssertNotEqual(wrapRowQueryChecksum(base),
                          wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 3, rowInLine: 3)),
                          "rowInLine must affect the checksum")
    }

    // Distinct multipliers: an additive fold would make (6,3,2) and (5,4,2) collide, which
    // is how an index-only regression hides.
    func testFieldsAreNotInterchangeable() {
        XCTAssertNotEqual(wrapRowQueryChecksum(location(globalRow: 6, logicalLine: 3, rowInLine: 2)),
                          wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 4, rowInLine: 2)))
        XCTAssertNotEqual(wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 4, rowInLine: 2)),
                          wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 3, rowInLine: 3)))
    }

    func testKnownValue() {
        // 5*1 + 3*31 + 2*131 = 5 + 93 + 262 = 360
        XCTAssertEqual(wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 3, rowInLine: 2)), 360)
    }
}
