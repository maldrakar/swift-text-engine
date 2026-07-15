import XCTest
import TextEngineCore
import TextEngineReferenceProviders

// The parity oracles and the reconstruction property for pointGeometryAt, run over the
// FOUR provider pairings acceptance criterion 1 names:
//
//     {UniformLineMetrics, PrefixSumLineMetrics} x {UniformColumnMetrics, PrefixSumColumnMetrics}
//
// They live here, and not in TextEngineCoreTests beside the other *EquivalenceTests,
// because that target depends on TextEngineCore alone: PrefixSumLineMetrics and
// PrefixSumColumnMetrics are physically unreachable from it (Package.swift), so its
// oracles could only ever run on hand-built doubles -- two pairings, neither of them a
// shipped provider. This target has both dependencies. The doubles they used added no
// dispatch the grid below lacks: like them, both PrefixSum providers take the core's
// generic binary-search fallback, and the fixtures keep what the doubles were there for
// (variable heights on the vertical axis, a blank line on the horizontal one).
//
// BalancedTreeLineMetrics -- the one provider that overrides the vertical search hook --
// is covered against the fallback in PointGeometryAtReferenceProviderTests.
final class PointGeometryAtOracleTests: XCTestCase {

    // 20 lines either way, so any vertical source pairs with any horizontal one
    // (columnAt takes `inLine` as a precondition; the horizontal source carries no
    // lineCount of its own).
    private static let lineCount = 20

    // Variable heights: 8, 11, 14, 17, 20, 8, ... -> totalHeight 300.
    private static let heights = (0..<lineCount).map { 8.0 + Double($0 % 5) * 3.0 }

    // Variable advances, every 7th line blank -- the case a uniform source cannot express.
    private static let advances: [[Double]] = (0..<lineCount).map { line in
        line % 7 == 0 ? [] : (0..<(2 + line % 4)).map { 4.0 + Double($0) * 2.0 }
    }

    // Sample points span both axes' clamp regions and the non-finite inputs.
    private static let ys: [Double] = [-8.0, -0.5, 0.0, 7.9, 13.0, 44.4, 100.0, 187.5,
                                       299.9, 300.0, 320.0, 640.0, .nan, .infinity, -.infinity]
    private static let xs: [Double] = [-9.0, -0.5, 0.0, 3.7, 8.0, 13.3, 22.0, 41.5,
                                       79.9, 80.0, 96.0, .nan, .infinity, -.infinity]

    // MARK: Oracle 1 -- indices and clamps must equal the query pointGeometryAt extends

    // Not a copy of the implementation: pointAt is an independently existing function, so
    // a swapped axis or a dropped clamp in pointGeometryAt cannot agree with it by accident.
    private func assertIndexAndClampParityWithPointAt<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics v: V, columnMetrics h: H, pairing: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for y in Self.ys {
            for x in Self.xs {
                let flat = ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: v, columnMetrics: h)
                let rich = ViewportVirtualizer.pointGeometryAt(x: x, y: y, lineMetrics: v, columnMetrics: h)
                let at = "\(pairing) x=\(x) y=\(y)"

                switch (flat, rich) {
                case let (.failure(a), .failure(b)):
                    XCTAssertEqual(a, b, at, file: file, line: line)
                case (.empty, .empty):
                    break
                case let (.point(p), .geometry(g)):
                    XCTAssertEqual(p.line.lineIndex, g.line.geometry.lineIndex, at, file: file, line: line)
                    XCTAssertEqual(p.line.clamp, g.line.clamp, at, file: file, line: line)
                    switch (p.column, g.column) {
                    case let (.cell(c), .cell(gc)):
                        XCTAssertEqual(c.columnIndex, gc.geometry.columnIndex, at, file: file, line: line)
                        XCTAssertEqual(c.clamp, gc.clamp, at, file: file, line: line)
                    case (.blankLine, .blankLine):
                        break
                    default:
                        XCTFail("column resolution diverged at \(at)", file: file, line: line)
                    }
                default:
                    XCTFail("outcome diverged at \(at): \(flat) vs \(rich)", file: file, line: line)
                }
            }
        }
    }

    // MARK: Oracles 2 and 3 -- each axis must EQUAL the 1D geometry query it composes

    private func assertComponentParityWith1D<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics v: V, columnMetrics h: H, pairing: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for y in Self.ys {
            for x in Self.xs {
                guard case let .geometry(g) = ViewportVirtualizer.pointGeometryAt(
                    x: x, y: y, lineMetrics: v, columnMetrics: h) else { continue }
                let at = "\(pairing) x=\(x) y=\(y)"

                // Oracle 2: the line component is exactly lineGeometryAt(y:).
                XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: y, metrics: v),
                               .geometry(g.line), at, file: file, line: line)

                // Oracle 3: the column component is exactly columnGeometryAt(x:inLine:),
                // asked on the line the vertical axis located.
                let located = g.line.geometry.lineIndex
                let want = ViewportVirtualizer.columnGeometryAt(x: x, inLine: located, metrics: h)
                switch g.column {
                case let .cell(cell):
                    XCTAssertEqual(want, .geometry(cell), at, file: file, line: line)
                case .blankLine:
                    XCTAssertEqual(want, .empty, at, file: file, line: line)
                }
            }
        }
    }

    // MARK: Reconstruction -- the fractions must reproduce the input point

    // Only for a point that landed inside a real cell: on a clamped axis the fraction is
    // pinned to 0.0/1.0 on purpose, so it cannot (and must not) reproduce an input that
    // lies outside the box. The hit counter keeps that skip from making this vacuous.
    private func assertReconstruction<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics v: V, columnMetrics h: H, pairing: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var reconstructed = 0
        for y in Self.ys {
            for x in Self.xs {
                guard case let .geometry(g) = ViewportVirtualizer.pointGeometryAt(
                          x: x, y: y, lineMetrics: v, columnMetrics: h),
                      case let .cell(cell) = g.column,
                      g.line.clamp == .inRange, cell.clamp == .inRange else { continue }
                let at = "\(pairing) x=\(x) y=\(y)"

                XCTAssertEqual(g.line.geometry.y + g.line.fractionInLine * g.line.geometry.height,
                               y, accuracy: 1e-9, "y reconstruction at \(at)", file: file, line: line)
                XCTAssertEqual(cell.geometry.x + cell.fractionInColumn * cell.geometry.width,
                               x, accuracy: 1e-9, "x reconstruction at \(at)", file: file, line: line)
                reconstructed += 1
            }
        }
        XCTAssertGreaterThan(reconstructed, 8,
                             "\(pairing): too few in-range hits to call this a test",
                             file: file, line: line)
    }

    private func assertAllOracles<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics v: V, columnMetrics h: H, pairing: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertIndexAndClampParityWithPointAt(lineMetrics: v, columnMetrics: h, pairing: pairing,
                                             file: file, line: line)
        assertComponentParityWith1D(lineMetrics: v, columnMetrics: h, pairing: pairing,
                                    file: file, line: line)
        assertReconstruction(lineMetrics: v, columnMetrics: h, pairing: pairing,
                             file: file, line: line)
    }

    // MARK: The 2x2 grid

    private var uniformLines: UniformLineMetrics {
        UniformLineMetrics(lineCount: Self.lineCount, lineHeight: 16.0)   // totalHeight 320
    }
    private var prefixSumLines: PrefixSumLineMetrics {
        PrefixSumLineMetrics(heights: Self.heights)                       // totalHeight 300
    }
    private var uniformColumns: UniformColumnMetrics {
        UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)        // lineWidth 80
    }
    private var prefixSumColumns: PrefixSumColumnMetrics {
        PrefixSumColumnMetrics(advancesPerLine: Self.advances)
    }

    func testOraclesUniformLinesUniformColumns() {
        assertAllOracles(lineMetrics: uniformLines, columnMetrics: uniformColumns,
                         pairing: "uniform x uniform")
    }

    func testOraclesUniformLinesPrefixSumColumns() {
        assertAllOracles(lineMetrics: uniformLines, columnMetrics: prefixSumColumns,
                         pairing: "uniform x prefixsum")
    }

    func testOraclesPrefixSumLinesUniformColumns() {
        assertAllOracles(lineMetrics: prefixSumLines, columnMetrics: uniformColumns,
                         pairing: "prefixsum x uniform")
    }

    func testOraclesPrefixSumLinesPrefixSumColumns() {
        assertAllOracles(lineMetrics: prefixSumLines, columnMetrics: prefixSumColumns,
                         pairing: "prefixsum x prefixsum")
    }
}
