extension ViewportVirtualizer {
    /// Maps a document `y` offset to the line whose half-open vertical span
    /// `[offset(i), offset(i+1))` contains it - the inverse of
    /// `LineMetricsSource.offset(ofLine:)`.
    ///
    /// Stateless. O(log N) `offset(ofLine:)` queries (one binary search), O(1)
    /// core memory. A `y` outside `[0, totalHeight)` resolves to the nearest line
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
}
