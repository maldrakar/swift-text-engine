/// Streams the visual rows of one logical line at a wrap width, in visual order.
/// Holds the provider so `next()` reads `columnOffset`/`canBreak` lazily — hence
/// generic, exactly like `VariableLineGeometryCursor<Metrics>`. O(1) state.
/// Construct via `ViewportVirtualizer.visualRows` (internal init); the width and
/// metrics are already validated there.
public struct VisualRowCursor<Metrics: WrapMetricsSource> {
    private let metrics: Metrics
    private let line: Int
    private let columnCount: Int
    /// The line's total advance, `columnOffset(inLine:column: columnCount)` as the
    /// ladder validated it (`0` on a blank line). Stored so `greedyEnd` can decide
    /// "does the remaining suffix fit" from a value in hand rather than a probe
    /// (slice 55 spec, Decisions 12 and 13). Never re-read from the provider.
    private let total: Double
    private let wrapWidth: Double
    private var nextStartColumn: Int
    private var nextRowInLine: Int
    private var finished: Bool

    init(line: Int, columnCount: Int, total: Double, wrapWidth: Double, metrics: Metrics) {
        self.metrics = metrics
        self.line = line
        self.columnCount = columnCount
        self.total = total
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
        let end = greedyEnd(from: start, startOffset: startOffset)

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

    // The largest legal end `e > start` with `columnOffset(e) - startOffset <=
    // wrapWidth`; if none fits, the smallest legal end `e > start` (forced overflow
    // — a row wider than wrapWidth). `columnCount` is always a legal end; interior
    // legal ends are columns `c` with `canBreak(beforeColumn: c)`. Relies on the
    // monotone `columnOffset` precondition: once a legal end overflows, every later
    // one does too, so the walk stops there. O(cells in the row).
    private func greedyEnd(from start: Int, startOffset: Double) -> Int {
        var lastFitting = -1   // largest legal end seen that fits
        var firstLegal = -1    // smallest legal end > start (overflow fallback)
        var c = start + 1
        while c <= columnCount {
            let isLegal = (c == columnCount) || metrics.canBreak(beforeColumn: c, inLine: line)
            if isLegal {
                if firstLegal == -1 { firstLegal = c }
                if metrics.columnOffset(inLine: line, column: c) - startOffset <= wrapWidth {
                    lastFitting = c
                } else {
                    break
                }
            }
            c += 1
        }
        return lastFitting != -1 ? lastFitting : firstLegal
    }
}

/// What the per-line wrap ladder hands back: the values its three probes read, so a
/// caller can build a `VisualRowCursor` without probing them again.
enum WrapLineMetrics {
    case valid(count: Int, total: Double)   // total == 0 on a blank line
    case failure(ViewportValidationError)
}

/// The per-line wrap ladder, shared by `visualRows(inLine:wrapWidth:metrics:)` and node
/// 4's `visualPointAt` (slice 55 spec, Decision 13): the same three probes in the same
/// order with the same failures as the ladder `visualRows` carried inline --
/// `columnCount(inLine:)`, then `wrapWidth`, then `columnOffset(inLine:column: 0)`, then
/// (non-blank lines only) `columnOffset(inLine:column: count)`. Behaviour-preserving by
/// construction; `WrapValidationTests` pins each rung and its order.
func validateWrapLine<Metrics: WrapMetricsSource>(
    inLine line: Int,
    wrapWidth: Double,
    metrics: Metrics
) -> WrapLineMetrics {
    let count = metrics.columnCount(inLine: line)
    if count < 0 {
        return .failure(.negativeColumnCount)
    }
    // `wrapWidth > 0` accepts +∞ (the equivalence case) and rejects NaN, −∞, ≤ 0.
    // Do NOT write `wrapWidth.isFinite && wrapWidth > 0`: +∞ is not finite.
    if !(wrapWidth > 0) {
        return .failure(.nonPositiveWrapWidth)
    }
    // O(1) contract probe, before the blank short-circuit, for parity with columnAt.
    if metrics.columnOffset(inLine: line, column: 0) != 0.0 {
        return .failure(.invalidColumnMetrics)
    }
    if count == 0 {
        // The probe above validated columnOffset(0) == 0, which IS the blank line's
        // total: no fourth probe.
        return .valid(count: 0, total: 0.0)
    }
    let total = metrics.columnOffset(inLine: line, column: count)
    if !total.isFinite || total <= 0.0 {
        return .failure(.invalidColumnMetrics)
    }
    return .valid(count: count, total: total)
}

extension ViewportVirtualizer {
    /// Streams the visual rows of logical line `inLine` packed to `wrapWidth`, in
    /// visual order. Stateless; the cursor is lazy (no packing happens here).
    /// `inLine` is a precondition (the source carries no `lineCount`), exactly like
    /// `columnAt`. Validates `wrapWidth` (`> 0`, so `+∞` is allowed — the
    /// equivalence case) and runs the same O(1) metrics ladder as `columnAt`
    /// (`validateWrapLine`) before handing back the lazy cursor.
    public static func visualRows<Metrics: WrapMetricsSource>(
        inLine line: Int,
        wrapWidth: Double,
        metrics: Metrics
    ) -> VisualRowPackingQuery<Metrics> {
        switch validateWrapLine(inLine: line, wrapWidth: wrapWidth, metrics: metrics) {
        case .failure(let error):
            return .failure(error)
        case .valid(let count, let total):
            return .rows(VisualRowCursor(line: line, columnCount: count, total: total, wrapWidth: wrapWidth, metrics: metrics))
        }
    }
}
