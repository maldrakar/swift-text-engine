extension ViewportVirtualizer {
    public static func compute<Metrics: LineMetricsSource>(
        _ input: VariableViewportInput,
        metrics: Metrics
    ) -> ViewportComputation {
        let lineCount = metrics.lineCount

        if lineCount < 0 {
            return .failure(.negativeLineCount)
        }
        if !input.scrollOffsetY.isFinite || !input.viewportHeight.isFinite {
            return .failure(.nonFiniteValue)
        }
        if input.viewportHeight < 0.0 {
            return .failure(.negativeViewportHeight)
        }
        if input.overscanLinesBefore < 0 || input.overscanLinesAfter < 0 {
            return .failure(.negativeOverscan)
        }

        // O(1) metrics contract checks (Decision 5). offset(ofLine: 0) is checked
        // BEFORE the empty short-circuit below — deliberate parity with the fixed
        // path (which validates before its lineCount == 0 return). Do not reorder.
        if metrics.offset(ofLine: 0) != 0.0 {
            return .failure(.invalidLineMetrics)
        }
        if lineCount == 0 {
            return .success(emptyRange())
        }
        let totalHeight = metrics.offset(ofLine: lineCount)
        if !totalHeight.isFinite || totalHeight <= 0.0 {
            return .failure(.invalidLineMetrics)
        }

        let maxOffsetY = nonNegative(totalHeight - input.viewportHeight)
        let effectiveOffsetY = clamp(input.scrollOffsetY, to: maxOffsetY)

        let visibleStart = firstLineTopAtOrBelow(
            effectiveOffsetY,
            metrics: metrics,
            lineCount: lineCount,
            totalHeight: totalHeight
        )
        let visibleEndExclusive = firstLineTopAtOrAbove(
            effectiveOffsetY + input.viewportHeight,
            metrics: metrics,
            lineCount: lineCount,
            totalHeight: totalHeight,
            lowerBound: visibleStart
        )

        return .success(
            bufferedRange(
                visibleStart: visibleStart,
                visibleEndExclusive: visibleEndExclusive,
                lineCount: lineCount,
                overscanLinesBefore: input.overscanLinesBefore,
                overscanLinesAfter: input.overscanLinesAfter,
                isAtTop: effectiveOffsetY == 0.0,
                isAtBottom: effectiveOffsetY == maxOffsetY
            )
        )
    }

    // Largest i in [0, lineCount) with offset(i) <= target (the line containing
    // `target`). For `target` at or past the document end, returns lineCount.
    private static func firstLineTopAtOrBelow<Metrics: LineMetricsSource>(
        _ target: Double,
        metrics: Metrics,
        lineCount: Int,
        totalHeight: Double
    ) -> Int {
        if target >= totalHeight {
            return lineCount
        }
        var low = 0
        var high = lineCount - 1
        var result = 0
        while low <= high {
            let mid = low + (high - low) / 2
            if metrics.offset(ofLine: mid) <= target {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    // Smallest i in [lowerBound, lineCount] with offset(i) >= target (the first
    // line whose top is at or below the viewport bottom, exclusive). The caller
    // passes lowerBound = visibleStart, since the answer is provably >= it
    // (offset(visibleStart) <= effOffsetY <= target). For `target` at or past the
    // document end, returns lineCount.
    private static func firstLineTopAtOrAbove<Metrics: LineMetricsSource>(
        _ target: Double,
        metrics: Metrics,
        lineCount: Int,
        totalHeight: Double,
        lowerBound: Int
    ) -> Int {
        if target >= totalHeight {
            return lineCount
        }
        var low = lowerBound
        var high = lineCount - 1
        var result = lineCount
        while low <= high {
            let mid = low + (high - low) / 2
            if metrics.offset(ofLine: mid) >= target {
                result = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return result
    }
}
