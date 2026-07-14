extension ViewportVirtualizer {
    /// The geometry-bearing companion to `pointAt(x:y:lineMetrics:columnMetrics:)`:
    /// maps a single point to the located line's box and the located cell's box,
    /// each with its within-box fraction and its clamp flag.
    ///
    /// Pure composition of `lineGeometryAt(y:metrics:)` and
    /// `columnGeometryAt(x:inLine:metrics:)`. It performs **no search of its own**
    /// (both inverse searches stay inside the 1D queries, which dispatch to the
    /// provider-native hooks) and **no arithmetic of its own** — every box and
    /// fraction is produced by the single existing implementation on that axis, so
    /// each component is equal, by construction, to what the corresponding 1D query
    /// would have returned. Over `pointAt` it adds only a constant number of probes —
    /// up to four (two `offset(ofLine:)`, two `columnOffset(inLine:column:)`) on a
    /// located cell, fewer on a blank line or a failure path, where the horizontal
    /// probes are never taken — so it never adds a log factor and its per-provider
    /// cost class equals `pointAt`'s: O(log N) + O(log M) queries, O(1) core memory,
    /// zero allocation beyond the returned value structs.
    ///
    /// The vertical query runs first: its failure short-circuits (the horizontal
    /// query needs a valid `inLine`, which only a vertical success can supply) and an
    /// empty document returns `.empty`. On a located line, a horizontal failure
    /// surfaces at the top level and **discards** the located line — a `.failure`
    /// means the query answered nothing, on either axis — a blank line becomes
    /// `.blankLine` (still carrying the line's box), and a real cell becomes `.cell`.
    /// Both clamp flags carry through verbatim, so a point clamped on both axes
    /// records both, with each fraction pinned to exactly `0.0` or `1.0` rather than
    /// computed from a coordinate that lies outside the box.
    ///
    /// Validation is delegated entirely to the two 1D queries, so their precedence is
    /// inherited: each checks its own coordinate's finiteness before its own
    /// zero-count short-circuit. A non-finite `y` therefore beats `.empty`, and a
    /// non-finite `x` beats `.blankLine`. `x` is only ever examined by the horizontal
    /// query, so an empty document returns `.empty` even for a non-finite `x`.
    ///
    /// Caret snapping is a caller concern: this reports where the point fell (the
    /// cell, its box, and the fraction within it), not which caret index to round to.
    ///
    /// - Precondition: `lineMetrics` and `columnMetrics` must describe the same
    ///   document. The line index located by the vertical query is threaded into
    ///   `columnGeometryAt(inLine:)` over the horizontal source, whose `inLine` is an
    ///   unvalidated precondition (`LineHorizontalMetricsSource` carries no line
    ///   count, by design — a line-agnostic provider holds O(1) memory for a document
    ///   of any size), so the two sources must agree on the line count.
    public static func pointGeometryAt<VMetrics: LineMetricsSource, HMetrics: LineHorizontalMetricsSource>(
        x: Double,
        y: Double,
        lineMetrics: VMetrics,
        columnMetrics: HMetrics
    ) -> PointGeometryQuery {
        switch lineGeometryAt(y: y, metrics: lineMetrics) {
        case let .failure(error):
            return .failure(error)
        case .empty:
            return .empty
        case let .geometry(line):
            switch columnGeometryAt(x: x, inLine: line.geometry.lineIndex, metrics: columnMetrics) {
            case let .failure(error):
                return .failure(error)
            case .empty:
                return .geometry(PointGeometryLocation(line: line, column: .blankLine))
            case let .geometry(column):
                return .geometry(PointGeometryLocation(line: line, column: .cell(column)))
            }
        }
    }
}
