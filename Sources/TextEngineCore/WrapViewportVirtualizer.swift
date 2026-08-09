/// The layout half of the visual-row validation ladder, shared verbatim by
/// `compute(_:layout:)` and `visualRowAt(y:layout:)` so their accept/reject sets are
/// equal by construction rather than by inspection (spec Decision 5).
///
/// `lineCount < 0` deliberately does NOT live here: it is the first check in BOTH
/// callers, and each caller's *next* check differs (`compute` validates its input,
/// `visualRowAt` validates `y`). Hoisting it would change `compute`'s shipped error
/// precedence against its input-value checks (`nonFiniteValue`,
/// `negativeViewportHeight`, `negativeOverscan`) — a pairing no test currently
/// covers, so this placement is an architectural decision, not a test-enforced one.
/// (`testLadderOrderLineCountBeforeRowHeight` pins only lineCount-before-rowHeight,
/// which survives the hoist.)
enum VisualRowLayoutValidation {
    case failure(ViewportValidationError)
    case empty                            // lineCount == 0
    case rows(Int)                        // totalRows > 0, totalHeight finite
}

func validateVisualRowLayout<Layout: VisualRowLayoutSource>(
    _ layout: Layout
) -> VisualRowLayoutValidation {
    if !layout.rowHeight.isFinite || layout.rowHeight <= 0.0 { return .failure(.nonPositiveRowHeight) }
    // wrapWidth > 0 accepts +∞ (the equivalence case) and rejects NaN/−∞/≤0. Do NOT
    // write `isFinite && > 0`: +∞ is not finite (the node-1 F1 trap).
    if !(layout.wrapWidth > 0) { return .failure(.nonPositiveWrapWidth) }
    if layout.firstVisualRow(ofLine: 0) != 0 { return .failure(.invalidVisualRowLayout) }
    if layout.lineCount == 0 { return .empty }
    let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
    if totalRows <= 0 { return .failure(.invalidVisualRowLayout) }
    let totalHeight = Double(totalRows) * layout.rowHeight
    if !totalHeight.isFinite { return .failure(.invalidVisualRowLayout) }
    return .rows(totalRows)
}

extension ViewportVirtualizer {
    /// Wrap-aware viewport compute over the visual-row axis. Returns a `VirtualRange`
    /// whose indices are **visual-row indices** (not logical lines). Reuses the proven
    /// variable compute over a uniform row axis. See the spec, Decision 2.
    public static func compute<Layout: VisualRowLayoutSource>(
        _ input: VariableViewportInput, layout: Layout
    ) -> ViewportComputation {
        if layout.lineCount < 0 { return .failure(.negativeLineCount) }
        if !input.scrollOffsetY.isFinite || !input.viewportHeight.isFinite { return .failure(.nonFiniteValue) }
        if input.viewportHeight < 0.0 { return .failure(.negativeViewportHeight) }
        if input.overscanLinesBefore < 0 || input.overscanLinesAfter < 0 { return .failure(.negativeOverscan) }
        switch validateVisualRowLayout(layout) {
        case .failure(let error):
            return .failure(error)
        case .empty:
            return .success(emptyRange())
        case .rows(let totalRows):
            return compute(input, metrics: UniformLineMetrics(lineCount: totalRows, lineHeight: layout.rowHeight))
        }
    }
}
