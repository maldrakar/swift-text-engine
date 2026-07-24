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
        if !layout.rowHeight.isFinite || layout.rowHeight <= 0.0 { return .failure(.nonPositiveRowHeight) }
        // wrapWidth > 0 accepts +∞ (the equivalence case) and rejects NaN/−∞/≤0. Do NOT
        // write `isFinite && > 0`: +∞ is not finite (the node-1 F1 trap).
        if !(layout.wrapWidth > 0) { return .failure(.nonPositiveWrapWidth) }
        if layout.firstVisualRow(ofLine: 0) != 0 { return .failure(.invalidVisualRowLayout) }
        if layout.lineCount == 0 { return .success(emptyRange()) }
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        if totalRows <= 0 { return .failure(.invalidVisualRowLayout) }
        let totalHeight = Double(totalRows) * layout.rowHeight
        if !totalHeight.isFinite { return .failure(.invalidVisualRowLayout) }
        return compute(input, metrics: UniformLineMetrics(lineCount: totalRows, lineHeight: layout.rowHeight))
    }
}
