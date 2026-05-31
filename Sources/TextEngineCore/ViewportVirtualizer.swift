public enum ViewportVirtualizer {
    public static func compute(_ input: ViewportInput) -> ViewportComputation {
        if input.lineCount < 0 {
            return .failure(.negativeLineCount)
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
            return .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 0,
                    bufferStart: 0,
                    bufferEndExclusive: 0,
                    isAtTop: true,
                    isAtBottom: true
                )
            )
        }

        return .success(
            VirtualRange(
                visibleStart: 0,
                visibleEndExclusive: 0,
                bufferStart: 0,
                bufferEndExclusive: 0,
                isAtTop: true,
                isAtBottom: false
            )
        )
    }
}
