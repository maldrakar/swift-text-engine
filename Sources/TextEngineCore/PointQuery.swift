extension ViewportVirtualizer {
    /// Maps a single point `(x, y)` to the line whose vertical span contains `y`
    /// and the cell within that line whose horizontal span contains `x` — the 2D
    /// composite of `lineAt(y:metrics:)` and `columnAt(x:inLine:metrics:)`.
    ///
    /// Stateless, pure composition — it adds no search of its own. The vertical
    /// query runs first over `lineMetrics`; its failure short-circuits (the
    /// horizontal query needs a valid `inLine`, which only a vertical success can
    /// supply) and an empty document returns `.empty`. On a located line the line
    /// index feeds `columnAt` over `columnMetrics`: a horizontal failure surfaces at
    /// the top level (discarding the located line), a blank line becomes
    /// `.blankLine`, and a real cell becomes `.cell`. Both clamp flags carry through
    /// verbatim from their 1D queries, so a both-axes-clamped point records both.
    /// Cost is the sum of the two 1D envelopes: O(log N) + O(log M) queries (or
    /// better where a provider overrides its native inverse hook), O(1) core memory,
    /// zero allocation beyond the returned value structs. Validation is delegated
    /// entirely to the two 1D queries — a non-finite coordinate is a failure, not a
    /// clamp, and it is checked before either axis's zero-count short-circuit.
    public static func pointAt<VMetrics: LineMetricsSource, HMetrics: LineHorizontalMetricsSource>(
        x: Double,
        y: Double,
        lineMetrics: VMetrics,
        columnMetrics: HMetrics
    ) -> PointQuery {
        switch lineAt(y: y, metrics: lineMetrics) {
        case let .failure(error):
            return .failure(error)
        case .empty:
            return .empty
        case let .line(lineLocation):
            switch columnAt(x: x, inLine: lineLocation.lineIndex, metrics: columnMetrics) {
            case let .failure(error):
                return .failure(error)
            case .empty:
                return .point(PointLocation(line: lineLocation, column: .blankLine))
            case let .column(columnLocation):
                return .point(PointLocation(line: lineLocation, column: .cell(columnLocation)))
            }
        }
    }
}
