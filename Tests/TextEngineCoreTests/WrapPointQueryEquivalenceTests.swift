import XCTest
import TextEngineCore

/// Criterion 3's oracle on the point axis: at a wrap width no line can exceed, the wrap
/// path must be bit-identical to the no-wrap path. The comparison is against `pointAt`
/// over a UNIFORM vertical axis and the very same layout as the horizontal source —
/// `VisualRowLayoutSource` refines `LineHorizontalMetricsSource`, so one object serves
/// both queries and the oracle compares two ladders over identical metrics.
///
/// Located branch only, and that scoping is the honest statement of what is proven: the
/// two failure orderings diverge by design.
final class WrapPointQueryEquivalenceTests: XCTestCase {
    private static let rowHeight = 12.0

    /// Irregular advances and break sets, so a width-sensitive bug cannot hide behind a
    /// uniform fixture. A blank line is included: it packs to exactly one `[0, 0)` row and
    /// both queries must answer `.blankLine`.
    private static let lines: [(advances: [Double], breaks: Set<Int>)] = [
        (advances: [7.0, 3.0, 11.0], breaks: [1, 2]),
        (advances: [5.0], breaks: []),
        (advances: [2.0, 2.0, 2.0, 2.0], breaks: [1, 2, 3]),
        (advances: [], breaks: []),
        (advances: [9.0, 1.0], breaks: [1]),
    ]

    private static func layout(wrapWidth: Double) -> TestVisualRowLayout {
        TestVisualRowLayout(lines: lines, rowHeight: rowHeight, wrapWidth: wrapWidth)
    }

    private func ySweep(lineCount: Int) -> [Double] {
        var ys: [Double] = [-100.0, -0.001]
        for row in 0..<lineCount {
            let top = Double(row) * Self.rowHeight
            ys.append(top)
            ys.append(top + Self.rowHeight / 2.0)
            ys.append(top + Self.rowHeight - 0.001)
        }
        ys.append(Double(lineCount) * Self.rowHeight)
        ys.append(Double(lineCount) * Self.rowHeight + 100.0)
        return ys
    }

    /// Interiors and both clamps for every line in the fixture, and exact cell boundaries
    /// for lines 0 and 1 (offsets `[0, 7, 10, 21]` and `[0, 5]`, all present below). Lines
    /// 2 and 4 are covered at their interiors and at some of their boundaries only —
    /// `6.0` (line 2) and `9.0` (line 4) are not in the sweep. Line 3 is blank and has no
    /// cell boundary to hit.
    private static let xs: [Double] = [-100.0, -0.001, 0.0, 0.001, 1.0, 2.0, 4.0, 5.0,
                                       6.999, 7.0, 8.0, 10.0, 20.0, 21.0, 1_000.0]

    /// Returns the first (x, y) at which the two queries disagree, or nil if none does.
    private func firstDisagreement(wrapWidth: Double) -> String? {
        let layout = Self.layout(wrapWidth: wrapWidth)
        let uniform = UniformLineMetrics(lineCount: layout.lineCount, lineHeight: Self.rowHeight)
        for y in ySweep(lineCount: layout.lineCount) {
            for x in Self.xs {
                let wrap = ViewportVirtualizer.visualPointAt(x: x, y: y, layout: layout)
                let flat = ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: uniform, columnMetrics: layout)
                guard case .point(let wrapPoint) = wrap, case .point(let flatPoint) = flat else {
                    return "non-located branch at (x: \(x), y: \(y)): \(wrap) vs \(flat)"
                }
                let line = flatPoint.line.lineIndex
                let count = layout.columnCount(inLine: line)
                let total = layout.columnOffset(inLine: line, column: count)
                let expectedSpan = VisualRow(logicalLine: line, rowInLine: 0,
                                             startColumn: 0, endColumn: count, width: total)
                if wrapPoint.row.globalRow != line
                    || wrapPoint.row.logicalLine != line
                    || wrapPoint.row.rowInLine != 0
                    || wrapPoint.row.clamp != flatPoint.line.clamp
                    || wrapPoint.rowSpan != expectedSpan
                    || wrapPoint.column != flatPoint.column {
                    return "(x: \(x), y: \(y)): \(wrapPoint) vs \(flatPoint)"
                }
            }
        }
        return nil
    }

    /// ∞ AND a large finite width: the oracle holds at any width >= every line's total
    /// advance, not only at ∞. `rowSpan.width` is asserted alongside the span because it
    /// is what steps 5-6 compare against.
    func testWidthNoLineExceedsEqualsUniformPointAt() {
        for width in [Double.infinity, 1_000.0] {
            XCTAssertNil(firstDisagreement(wrapWidth: width), "width=\(width)")
        }
    }

    /// The control. Without it the oracle could be vacuously true — two queries that both
    /// ignored the width would pass it.
    func testANarrowWidthBreaksTheEquivalence() {
        XCTAssertNotNil(firstDisagreement(wrapWidth: 4.0),
                        "at a width the fixture's lines exceed, the wrap answer MUST differ")
    }
}
