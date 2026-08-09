import XCTest
import TextEngineCore

/// Criterion 3's oracle on the y→row axis: at a wrap width no line can exceed, the wrap
/// path must be bit-identical to the no-wrap path. Scoped to the LOCATED branch
/// deliberately — the two queries return different types, and their failure/empty ladders
/// differ by design (`lineAt` answers an empty document without ever inspecting
/// `lineHeight`, `visualRowAt` follows `compute` and reports `.nonPositiveRowHeight`).
final class WrapRowQueryEquivalenceTests: XCTestCase {
    private static let rowHeight = 12.0

    /// Irregular advances and break sets, so a width-sensitive bug cannot hide behind a
    /// uniform fixture. A blank line is included: it packs to exactly one row.
    private static let lines: [(advances: [Double], breaks: Set<Int>)] = [
        (advances: [7.0, 3.0, 11.0], breaks: [1, 2]),
        (advances: [5.0], breaks: []),
        (advances: [2.0, 2.0, 2.0, 2.0], breaks: [1, 2, 3]),
        (advances: [], breaks: []),
        (advances: [9.0, 1.0], breaks: [1]),
    ]

    private func ySweep(totalHeight: Double) -> [Double] {
        var ys: [Double] = [-100.0, -0.001, 0.0]
        var row = 0
        while Double(row) * Self.rowHeight < totalHeight {
            let top = Double(row) * Self.rowHeight
            ys.append(top)                            // exact boundary
            ys.append(top + Self.rowHeight / 2)       // interior
            ys.append(top + Self.rowHeight - 0.001)   // just below the next boundary
            row += 1
        }
        ys.append(totalHeight - 0.001)
        ys.append(totalHeight)                        // clamped
        ys.append(totalHeight + 100.0)                // clamped
        return ys
    }

    func testWidthNoLineExceedsEqualsUniformLineAt() {
        let lineCount = Self.lines.count
        let totalHeight = Double(lineCount) * Self.rowHeight
        let uniform = UniformLineMetrics(lineCount: lineCount, lineHeight: Self.rowHeight)

        // ∞ and a large finite width: the oracle holds at any width >= every line's total
        // advance, not only at ∞.
        for width in [Double.infinity, 1_000.0] {
            let layout = TestVisualRowLayout(lines: Self.lines, rowHeight: Self.rowHeight, wrapWidth: width)

            // Precondition of the oracle: at this width every line is exactly one row.
            XCTAssertEqual(layout.firstVisualRow(ofLine: lineCount), lineCount, "width \(width)")

            for y in ySweep(totalHeight: totalHeight) {
                guard case .row(let located) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
                    XCTFail("expected .row at y=\(y), width \(width)"); continue
                }
                guard case .line(let reference) = ViewportVirtualizer.lineAt(y: y, metrics: uniform) else {
                    XCTFail("expected .line at y=\(y)"); continue
                }
                XCTAssertEqual(located.globalRow, reference.lineIndex, "y=\(y) width=\(width)")
                XCTAssertEqual(located.logicalLine, reference.lineIndex, "y=\(y) width=\(width)")
                XCTAssertEqual(located.rowInLine, 0, "y=\(y) width=\(width)")
                XCTAssertEqual(located.clamp, reference.clamp, "y=\(y) width=\(width)")
            }
        }
    }

    /// The oracle must be able to tell the two paths apart when they genuinely differ —
    /// otherwise "equal at ∞" is vacuous. At a narrow width the same document has more
    /// rows than lines, and the two answers must diverge.
    func testNarrowWidthIsNotEquivalent() {
        let layout = TestVisualRowLayout(lines: Self.lines, rowHeight: Self.rowHeight, wrapWidth: 5.0)
        XCTAssertGreaterThan(layout.firstVisualRow(ofLine: Self.lines.count), Self.lines.count)
    }
}
