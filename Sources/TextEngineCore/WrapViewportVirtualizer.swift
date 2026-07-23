extension ViewportVirtualizer {
    /// Wrap-aware viewport compute over the visual-row axis. Returns a `VirtualRange`
    /// whose indices are **visual-row indices** (not logical lines). Reuses the proven
    /// variable compute over a uniform row axis. See the spec, Decision 2.
    public static func compute<Layout: VisualRowLayoutSource>(
        _ input: VariableViewportInput, layout: Layout
    ) -> ViewportComputation {
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        return compute(input, metrics: UniformLineMetrics(lineCount: totalRows, lineHeight: layout.rowHeight))
    }
}
