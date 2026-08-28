extension ViewportVirtualizer {
    /// Maps a document `y` to the visual row whose half-open vertical span contains it —
    /// the wrap-aware analog of `lineAt(y:metrics:)`, over the visual-row axis.
    ///
    /// Stateless, O(1) core memory. Runs `compute(_:layout:)`'s layout ladder (the same
    /// shared helper, so the two entry points accept and reject exactly the same
    /// layouts AT THE LADDER; after it they diverge on one class -- a
    /// `logicalLine(containingVisualRow:)` override answering outside `0..<lineCount`,
    /// or an in-range line whose `firstVisualRow` exceeds the row -- which `compute`
    /// never consults and this query rejects with `.invalidVisualRowLayout` rather than
    /// trapping or naming a row that does not exist; the default hook cannot produce
    /// either), then delegates the row-axis search to `lineAt` over a uniform row axis
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
            // Guards 1 and 2 (slice 55 spec, Decision 4). The default hook cannot
            // misbehave (binarySearchLogicalLine returns a line in 0..<lineCount whose
            // firstVisualRow is <= globalRow); an override can, and this is the only
            // frame that can catch it -- one frame later the array below has been read.
            // A line outside the range would trap on the provider's array; an in-range
            // line whose firstVisualRow exceeds the row names no row at all. Both are
            // .invalidVisualRowLayout, not a trap and not a fabricated location; node
            // 4's query inherits this by .failure propagation and re-checks neither.
            // The upper bound (rowInLine < visualRowCount) is deliberately NOT checked
            // here: it costs a layout-axis probe, and the within-line walk catches it at
            // the point of use.
            if logicalLine < 0 || logicalLine >= layout.lineCount {
                return .failure(.invalidVisualRowLayout)
            }
            let rowInLine = globalRow - layout.firstVisualRow(ofLine: logicalLine)
            if rowInLine < 0 {
                return .failure(.invalidVisualRowLayout)
            }
            return .row(VisualRowLocation(
                globalRow: globalRow,
                logicalLine: logicalLine,
                rowInLine: rowInLine,
                clamp: location.clamp
            ))
        }
    }
}
