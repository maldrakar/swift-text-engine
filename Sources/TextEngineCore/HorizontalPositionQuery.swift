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

    /// The geometry-bearing companion to `columnAt(x:inLine:metrics:)`: returns the
    /// located cell's box (`ColumnGeometry`) plus the within-cell `fractionInColumn`
    /// and the same clamp flag.
    ///
    /// Composes over `columnAt` — index, clamp, and the validation ladder come
    /// straight from it (parity by construction) — then reads
    /// `columnOffset(inLine:column: i)` and `columnOffset(inLine:column: i + 1)` to
    /// build the box. Adds only a constant number of `columnOffset(inLine:column:)`
    /// probes over `columnAt`, so it never adds a log factor and its per-provider cost
    /// class equals `columnAt`'s. O(1) core memory. `.empty` / `.failure` pass straight
    /// through from `columnAt`. `inLine` is a documented precondition, not validated.
    public static func columnGeometryAt<Metrics: LineHorizontalMetricsSource>(
        x: Double,
        inLine line: Int,
        metrics: Metrics
    ) -> ColumnGeometryQuery {
        switch columnAt(x: x, inLine: line, metrics: metrics) {
        case let .failure(error):
            return .failure(error)
        case .empty:
            return .empty
        case let .column(location):
            let left = metrics.columnOffset(inLine: line, column: location.columnIndex)
            let right = metrics.columnOffset(inLine: line, column: location.columnIndex + 1)
            let box = ColumnGeometry(columnIndex: location.columnIndex, x: left, width: right - left)
            let fraction: Double
            switch location.clamp {
            case .clampedToLeft:
                fraction = 0.0
            case .clampedToRight:
                fraction = 1.0
            case .inRange:
                fraction = (x - left) / box.width
            }
            return .geometry(ColumnGeometryLocation(geometry: box, fractionInColumn: fraction, clamp: location.clamp))
        }
    }
}
