extension ViewportVirtualizer {
    /// Maps a target `x` within line `inLine` to the cell whose half-open span
    /// `[columnOffset(c), columnOffset(c+1))` contains it — the horizontal mirror
    /// of `lineAt(y:metrics:)`.
    ///
    /// Stateless. The in-range branch dispatches to
    /// `LineHorizontalMetricsSource.columnIndex(containingOffset:inLine:)`; the
    /// default is an O(log M) binary search over `columnOffset`, and a provider may
    /// override it. O(1) core memory. An `x` outside `[0, lineWidth)` resolves to
    /// the nearest cell with `ColumnLocation.clamp` recording the edge. A blank
    /// line (`columnCount == 0`) is `.empty`, not a failure. `inLine` is a
    /// documented precondition (a valid line for the source), not validated.
    public static func columnAt<Metrics: LineHorizontalMetricsSource>(
        x: Double,
        inLine line: Int,
        metrics: Metrics
    ) -> ColumnQuery {
        let count = metrics.columnCount(inLine: line)

        if count < 0 {
            return .failure(.negativeColumnCount)
        }
        if !x.isFinite {
            return .failure(.nonFiniteValue)
        }
        // O(1) contract probe, checked before the empty short-circuit for parity
        // with `lineAt`. Do not reorder.
        if metrics.columnOffset(inLine: line, column: 0) != 0.0 {
            return .failure(.invalidColumnMetrics)
        }
        if count == 0 {
            return .empty
        }
        let width = metrics.columnOffset(inLine: line, column: count)
        if !width.isFinite || width <= 0.0 {
            return .failure(.invalidColumnMetrics)
        }

        if x < 0.0 {
            return .column(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft))
        }
        if x >= width {
            return .column(ColumnLocation(columnIndex: count - 1, clamp: .clampedToRight))
        }

        let index = metrics.columnIndex(containingOffset: x, inLine: line)
        return .column(ColumnLocation(columnIndex: index, clamp: .inRange))
    }
}
