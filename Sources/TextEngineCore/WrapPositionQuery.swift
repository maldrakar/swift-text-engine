extension ViewportVirtualizer {
    /// Maps a document `y` to the visual row whose half-open vertical span contains it —
    /// the wrap-aware analog of `lineAt(y:metrics:)`, over the visual-row axis.
    ///
    /// Stateless, O(1) core memory. Runs `compute(_:layout:)`'s layout ladder (the same
    /// shared helper, so the two entry points accept and reject exactly the same
    /// layouts), then delegates the row-axis search to `lineAt` over a uniform row axis
    /// and names the located row in both coordinate systems. Adds no new search: one
    /// row-axis search, one `logicalLine(containingVisualRow:)` search
    /// (provider-overridable, binary-search default), one O(1) `firstVisualRow` probe.
    ///
    /// A `y` outside `[0, totalRows * rowHeight)` clamps to the nearest row with
    /// `LineLocation.Clamp` recording the edge; both edges flow through the same two
    /// provider calls as an in-range hit, so no special case is needed. An empty
    /// document is `.empty`, not a failure.
    public static func visualRowAt<Layout: VisualRowLayoutSource>(
        y: Double,
        layout: Layout
    ) -> VisualRowQuery {
        if layout.lineCount < 0 { return .failure(.negativeLineCount) }
        if !y.isFinite { return .failure(.nonFiniteValue) }

        let totalRows: Int
        switch validateVisualRowLayout(layout) {
        case .failure(let error): return .failure(error)
        case .empty: return .empty
        case .rows(let rows): totalRows = rows
        }

        let rowAxis = UniformLineMetrics(lineCount: totalRows, lineHeight: layout.rowHeight)
        switch lineAt(y: y, metrics: rowAxis) {
        // Neither branch is reachable: the ladder proved totalRows > 0 and y finite, and
        // UniformLineMetrics.offset(ofLine: 0) is exactly 0. Mapped through rather than
        // force-unwrapped — no fabricated row, no crash (the DocumentVisualRowCursor
        // GIGO precedent).
        case .failure(let error): return .failure(error)
        case .empty: return .empty
        case .line(let location):
            let globalRow = location.lineIndex
            let logicalLine = layout.logicalLine(containingVisualRow: globalRow)
            let rowInLine = globalRow - layout.firstVisualRow(ofLine: logicalLine)
            return .row(VisualRowLocation(
                globalRow: globalRow,
                logicalLine: logicalLine,
                rowInLine: rowInLine,
                clamp: location.clamp
            ))
        }
    }
}
