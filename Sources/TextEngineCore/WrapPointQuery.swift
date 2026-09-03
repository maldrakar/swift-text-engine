extension ViewportVirtualizer {
    /// Maps a point `(x, y)` to the visual row whose vertical span contains `y` and the
    /// cell within that row whose horizontal span contains `x` — the wrap-aware analog of
    /// `pointAt(x:y:lineMetrics:columnMetrics:)`, over a SINGLE `VisualRowLayoutSource`.
    ///
    /// One source for both axes (the layout refines `WrapMetricsSource`, which refines
    /// `LineHorizontalMetricsSource`), so unlike `pointAt` there is no precondition that
    /// two sources describe the same document.
    ///
    /// `x` is measured from the located ROW's left edge, and the clamps land on the row's
    /// edges: `x < 0` resolves to the row's first cell (`.clampedToLeft`), `x >=
    /// rowSpan.width` to its last (`.clampedToRight`). On an OVERFLOW row (an unbreakable
    /// run wider than `wrapWidth`) the comparison is against the row's own advance sum, so
    /// an `x` between `wrapWidth` and `rowSpan.width` is `.inRange`. The returned
    /// `columnIndex` is an index into the LOGICAL LINE; `rowSpan.startColumn` bridges the
    /// two frames.
    ///
    /// Adds no search of its own. The vertical half is `visualRowAt` verbatim (its
    /// `.failure`/`.empty` propagate, and its two guards on a malformed
    /// `logicalLine(containingVisualRow:)` override are inherited — this query re-checks
    /// neither); the horizontal half is one `columnIndex(containingOffset:inLine:)`
    /// dispatch on the delegating path only. Cost: O(log totalRows) + O(log lineCount) +
    /// the within-line walk to the located row (zero extra columns scanned on a line that
    /// fits `wrapWidth`, and on any line's last row unless it overflows) + O(log
    /// cells-in-line), with three column-axis probes in the shared per-line ladder, two
    /// per row the walk yields, and one more for the row's left offset when it delegates.
    /// O(1) core memory.
    ///
    /// A non-finite `x` is a failure, not a clamp — `+∞ >= rowSpan.width` and `-∞ < 0`
    /// would both silently clamp — and it is checked before any horizontal work, so a
    /// non-finite `x` costs zero column-metric probes. An empty document is `.empty` even
    /// for a non-finite `x` (the vertical half runs first); a non-finite `x` beats
    /// `.blankLine` (the check runs before the span is read).
    ///
    /// The one failure this query adds of its own: a layout whose
    /// `firstVisualRow`/`visualRowCount` disagrees with node 1's packer, so the walk runs
    /// out before the row it was asked for — `.failure(.invalidVisualRowLayout)` rather
    /// than a fabricated row.
    public static func visualPointAt<Layout: VisualRowLayoutSource>(
        x: Double,
        y: Double,
        layout: Layout
    ) -> VisualPointQuery {
        // Step 1 — the whole vertical ladder, verbatim.
        let row: VisualRowLocation
        switch visualRowAt(y: y, layout: layout) {
        case .failure(let error): return .failure(error)
        case .empty: return .empty
        case .row(let located): row = located
        }

        // Step 2 — before any horizontal work (see the doc comment: this placement is
        // what `WrapPointQueryCountTests`' zero-probe assertion observes).
        if !x.isFinite { return .failure(.nonFiniteValue) }

        // Step 3 — the shared per-line ladder, then the shared within-line walk.
        let line = row.logicalLine
        let count: Int
        let total: Double
        switch validateWrapLine(inLine: line, wrapWidth: layout.wrapWidth, metrics: layout) {
        // .nonPositiveWrapWidth is unreachable here (step 1 validated wrapWidth); mapped
        // through rather than force-unwrapped, as visualRowAt treats its own.
        case .failure(let error): return .failure(error)
        case .valid(let validCount, let validTotal): count = validCount; total = validTotal
        }
        var cursor = VisualRowCursor(
            line: line, columnCount: count, total: total,
            wrapWidth: layout.wrapWidth, metrics: layout)
        // `nil` means exactly one thing here: the walk ran out before row `rowInLine`.
        // Decision 12's short-circuit cannot bypass the detection -- it decides where ONE
        // row ends, so a fitting line asked for row 2 still consumes its single row and
        // fails here.
        guard let rowSpan = advanceVisualRows(&cursor, by: row.rowInLine + 1) else {
            return .failure(.invalidVisualRowLayout)
        }

        // Step 4 — the blank row, read from the span: a second columnCount probe would buy
        // nothing (node 1 returns an end strictly greater than the start for every
        // non-blank line, and a blank line packs to exactly one [0, 0) row).
        if rowSpan.startColumn == rowSpan.endColumn {
            return .point(VisualPointLocation(row: row, rowSpan: rowSpan, column: .blankLine))
        }

        // Steps 5-6 — both clamps, no probe. rowLeft is deliberately NOT read yet.
        if x < 0.0 {
            return .point(VisualPointLocation(
                row: row, rowSpan: rowSpan,
                column: .cell(ColumnLocation(columnIndex: rowSpan.startColumn, clamp: .clampedToLeft))))
        }
        if x >= rowSpan.width {
            return .point(VisualPointLocation(
                row: row, rowSpan: rowSpan,
                column: .cell(ColumnLocation(columnIndex: rowSpan.endColumn - 1, clamp: .clampedToRight))))
        }

        // Step 7 — rebase into the line's frame and dispatch to the provider's hook.
        let rowLeft = layout.columnOffset(inLine: line, column: rowSpan.startColumn)
        let rebased = rowLeft + x
        // Reproduces the answer columnAt's own `x` rung gave for a non-finite interior
        // offset: the ladder validates columnOffset at 0 and count only, so an interior
        // offset is trusted, unvalidated input (the cursor documents the same).
        if !rebased.isFinite { return .failure(.nonFiniteValue) }
        let raw: Int
        if rebased >= total {
            // The hook's precondition is `x < lineWidth` and it does not clamp. On a
            // line's last row, `rowLeft + x` can round up onto `total` even for an x
            // strictly below the row's width (Decision 6, fixture 2). `total` is the
            // ladder's own value -- this guard costs no probe.
            raw = rowSpan.endColumn - 1
        } else {
            raw = layout.columnIndex(containingOffset: rebased, inLine: line)
        }
        // Decision 6: in Double arithmetic the rounding above can also land INSIDE the
        // line but past the row, and the hook then answers with a cell belonging to the
        // NEXT row. Clamp the index into the row's span -- and only the index: `x` was
        // inside [0, rowSpan.width), so the flag stays .inRange. Flipping it would report
        // a right-edge hit for a point in the row's interior.
        //
        // Only the UPPER half fires under a conforming provider, and that asymmetry is
        // deliberate: `x >= 0` here, so `rebased >= rowLeft == columnOffset(startColumn)`
        // and a monotone `columnIndex` hook cannot answer below `startColumn`. The `max`
        // is defensive symmetry against a provider that violates that contract; it is
        // kept, and has no recorded red, because no conforming fixture can reach it.
        let index = min(max(raw, rowSpan.startColumn), rowSpan.endColumn - 1)
        return .point(VisualPointLocation(
            row: row, rowSpan: rowSpan,
            column: .cell(ColumnLocation(columnIndex: index, clamp: .inRange))))
    }
}
