/// Streams the visual rows of one logical line at a wrap width, in visual order.
/// Holds the provider so `next()` reads `columnOffset`/`canBreak` lazily — hence
/// generic, exactly like `VariableLineGeometryCursor<Metrics>`. O(1) state.
/// Construct via `ViewportVirtualizer.visualRows` (internal init); the width and
/// metrics are already validated there.
public struct VisualRowCursor<Metrics: WrapMetricsSource> {
    private let metrics: Metrics
    private let line: Int
    private let columnCount: Int
    private let wrapWidth: Double
    private var nextStartColumn: Int
    private var nextRowInLine: Int
    private var finished: Bool

    init(line: Int, columnCount: Int, wrapWidth: Double, metrics: Metrics) {
        self.metrics = metrics
        self.line = line
        self.columnCount = columnCount
        self.wrapWidth = wrapWidth
        self.nextStartColumn = 0
        self.nextRowInLine = 0
        self.finished = false
    }

    public mutating func next() -> VisualRow? {
        if finished { return nil }

        // Blank line: exactly one empty row.
        if columnCount == 0 {
            finished = true
            return VisualRow(logicalLine: line, rowInLine: 0, startColumn: 0, endColumn: 0, width: 0.0)
        }

        let start = nextStartColumn
        let startOffset = metrics.columnOffset(inLine: line, column: start)
        let end = columnCount   // Task 3 replaces with: greedyEnd(from: start, startOffset: startOffset)

        let row = VisualRow(
            logicalLine: line,
            rowInLine: nextRowInLine,
            startColumn: start,
            endColumn: end,
            width: metrics.columnOffset(inLine: line, column: end) - startOffset
        )
        nextStartColumn = end
        nextRowInLine += 1
        if end == columnCount { finished = true }
        return row
    }
}

extension ViewportVirtualizer {
    /// Streams the visual rows of logical line `inLine` packed to `wrapWidth`, in
    /// visual order. Stateless; the cursor is lazy (no packing happens here).
    /// `inLine` is a precondition (the source carries no `lineCount`), exactly like
    /// `columnAt`. Task 4 adds the width + metrics validation ladder.
    public static func visualRows<Metrics: WrapMetricsSource>(
        inLine line: Int,
        wrapWidth: Double,
        metrics: Metrics
    ) -> VisualRowQuery<Metrics> {
        let count = metrics.columnCount(inLine: line)
        return .rows(VisualRowCursor(line: line, columnCount: count, wrapWidth: wrapWidth, metrics: metrics))
    }
}
