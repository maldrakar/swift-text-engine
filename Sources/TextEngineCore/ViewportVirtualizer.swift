public enum ViewportVirtualizer {
    public static func compute(_ input: ViewportInput) -> ViewportComputation {
        if input.lineCount < 0 {
            return .failure(.negativeLineCount)
        }
        if !input.lineHeight.isFinite || !input.scrollOffsetY.isFinite || !input.viewportHeight.isFinite {
            return .failure(.nonFiniteValue)
        }
        if input.lineHeight <= 0.0 {
            return .failure(.nonPositiveLineHeight)
        }
        if input.viewportHeight < 0.0 {
            return .failure(.negativeViewportHeight)
        }
        if input.overscanLinesBefore < 0 || input.overscanLinesAfter < 0 {
            return .failure(.negativeOverscan)
        }
        if input.lineCount == 0 {
            return .success(emptyRange())
        }

        let effectiveOffsetY = clampedScrollOffsetY(
            scrollOffsetY: input.scrollOffsetY,
            lineCount: input.lineCount,
            lineHeight: input.lineHeight,
            viewportHeight: input.viewportHeight
        )
        let visibleStartQuotient = snappedIntegerQuotient(effectiveOffsetY / input.lineHeight)
        let visibleEndExclusiveQuotient = snappedIntegerQuotient(
            (effectiveOffsetY + input.viewportHeight) / input.lineHeight
        )
        let visibleStart = clampedIndex(
            visibleStartQuotient.rounded(.down),
            lineCount: input.lineCount
        )
        let visibleEndExclusive = clampedIndex(
            visibleEndExclusiveQuotient.rounded(.up),
            lineCount: input.lineCount
        )
        let maxOffsetY = maximumScrollOffsetY(
            lineCount: input.lineCount,
            lineHeight: input.lineHeight,
            viewportHeight: input.viewportHeight
        )
        return .success(
            bufferedRange(
                visibleStart: visibleStart,
                visibleEndExclusive: visibleEndExclusive,
                lineCount: input.lineCount,
                overscanLinesBefore: input.overscanLinesBefore,
                overscanLinesAfter: input.overscanLinesAfter,
                isAtTop: effectiveOffsetY == 0.0,
                isAtBottom: effectiveOffsetY == maxOffsetY
            )
        )
    }

    static func emptyRange() -> VirtualRange {
        VirtualRange(
            visibleStart: 0,
            visibleEndExclusive: 0,
            bufferStart: 0,
            bufferEndExclusive: 0,
            isAtTop: true,
            isAtBottom: true
        )
    }

    static func bufferedRange(
        visibleStart: Int,
        visibleEndExclusive: Int,
        lineCount: Int,
        overscanLinesBefore: Int,
        overscanLinesAfter: Int,
        isAtTop: Bool,
        isAtBottom: Bool
    ) -> VirtualRange {
        let bufferStart = if overscanLinesBefore >= visibleStart {
            0
        } else {
            visibleStart - overscanLinesBefore
        }
        let remainingAfterVisible = lineCount - visibleEndExclusive
        let bufferEndExclusive = if overscanLinesAfter >= remainingAfterVisible {
            lineCount
        } else {
            visibleEndExclusive + overscanLinesAfter
        }

        return VirtualRange(
            visibleStart: visibleStart,
            visibleEndExclusive: visibleEndExclusive,
            bufferStart: bufferStart,
            bufferEndExclusive: bufferEndExclusive,
            isAtTop: isAtTop,
            isAtBottom: isAtBottom
        )
    }

    private static func clampedScrollOffsetY(
        scrollOffsetY: Double,
        lineCount: Int,
        lineHeight: Double,
        viewportHeight: Double
    ) -> Double {
        let maxOffsetY = maximumScrollOffsetY(
            lineCount: lineCount,
            lineHeight: lineHeight,
            viewportHeight: viewportHeight
        )
        return clamp(scrollOffsetY, to: maxOffsetY)
    }

    static func nonNegative(_ value: Double) -> Double {
        value < 0.0 ? 0.0 : value
    }

    static func clamp(_ value: Double, to maxValue: Double) -> Double {
        if value < 0.0 {
            return 0.0
        }
        if value > maxValue {
            return maxValue
        }
        return value
    }

    private static func maximumScrollOffsetY(
        lineCount: Int,
        lineHeight: Double,
        viewportHeight: Double
    ) -> Double {
        let documentHeight = Double(lineCount) * lineHeight
        return nonNegative(documentHeight - viewportHeight)
    }

    private static func clampedIndex(_ candidate: Double, lineCount: Int) -> Int {
        if candidate <= 0.0 {
            return 0
        }
        if candidate >= Double(lineCount) {
            return lineCount
        }
        return Int(candidate)
    }

    private static func snappedIntegerQuotient(_ quotient: Double) -> Double {
        let nearest = quotient.rounded()
        let tolerance = nearest.ulp
        if abs(quotient - nearest) <= tolerance {
            return nearest
        }
        return quotient
    }
}
