extension ViewportVirtualizer {
    /// Maps a document `y` offset to the line whose half-open vertical span
    /// `[offset(i), offset(i+1))` contains it - the inverse of
    /// `LineMetricsSource.offset(ofLine:)`.
    ///
    /// Stateless. The in-range branch calls
    /// `LineMetricsSource.lineIndex(containingOffset:)`: providers may override
    /// it with a native prefix search, while the default remains an O(log N)
    /// binary search over `offset(ofLine:)`. O(1) core memory. A `y` outside
    /// `[0, totalHeight)` resolves to the nearest line
    /// with `LineLocation.clamp` recording the edge. Validation mirrors
    /// `compute`'s order; an empty document is `.empty`, not a failure.
    public static func lineAt<Metrics: LineMetricsSource>(
        y: Double,
        metrics: Metrics
    ) -> LineQuery {
        let lineCount = metrics.lineCount

        if lineCount < 0 {
            return .failure(.negativeLineCount)
        }
        if !y.isFinite {
            return .failure(.nonFiniteValue)
        }
        // O(1) contract probe, checked before the empty short-circuit for parity
        // with `compute`. Do not reorder.
        if metrics.offset(ofLine: 0) != 0.0 {
            return .failure(.invalidLineMetrics)
        }
        if lineCount == 0 {
            return .empty
        }
        let totalHeight = metrics.offset(ofLine: lineCount)
        if !totalHeight.isFinite || totalHeight <= 0.0 {
            return .failure(.invalidLineMetrics)
        }

        if y < 0.0 {
            return .line(LineLocation(lineIndex: 0, clamp: .clampedToTop))
        }
        if y >= totalHeight {
            return .line(LineLocation(lineIndex: lineCount - 1, clamp: .clampedToBottom))
        }

        let index = metrics.lineIndex(containingOffset: y)
        return .line(LineLocation(lineIndex: index, clamp: .inRange))
    }

    /// The geometry-bearing companion to `lineAt(y:metrics:)`: returns the located
    /// line's box (`LineGeometry`) plus the within-line `fractionInLine` and the
    /// same clamp flag.
    ///
    /// Composes over `lineAt` — index, clamp, and the validation ladder come
    /// straight from it (parity by construction) — then reads `offset(ofLine: i)`
    /// and `offset(ofLine: i + 1)` to build the box. Adds only a constant number of
    /// `offset(ofLine:)` probes over `lineAt`, so it never adds a log factor and its
    /// per-provider cost class equals `lineAt`'s. O(1) core memory. `.empty` /
    /// `.failure` pass straight through from `lineAt`.
    public static func lineGeometryAt<Metrics: LineMetricsSource>(
        y: Double,
        metrics: Metrics
    ) -> LineGeometryQuery {
        switch lineAt(y: y, metrics: metrics) {
        case let .failure(error):
            return .failure(error)
        case .empty:
            return .empty
        case let .line(location):
            let top = metrics.offset(ofLine: location.lineIndex)
            let bottom = metrics.offset(ofLine: location.lineIndex + 1)
            let box = LineGeometry(lineIndex: location.lineIndex, y: top, height: bottom - top)
            let fraction: Double
            switch location.clamp {
            case .clampedToTop:
                fraction = 0.0
            case .clampedToBottom:
                fraction = 1.0
            case .inRange:
                fraction = (y - top) / box.height
            }
            return .geometry(LineGeometryLocation(geometry: box, fractionInLine: fraction, clamp: location.clamp))
        }
    }
}
