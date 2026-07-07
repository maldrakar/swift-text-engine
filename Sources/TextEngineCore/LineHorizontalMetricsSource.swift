public protocol LineHorizontalMetricsSource {
    /// Number of cells in `line`. A blank line has 0. (mirror of `lineCount`)
    func columnCount(inLine line: Int) -> Int

    /// Cumulative left offset (x) of cell `column` within `line`, in layout units.
    ///
    /// Domain: `0...columnCount(inLine: line)`.
    /// `columnOffset(inLine: l, column: 0) == 0`, and
    /// `columnOffset(inLine: l, column: columnCount(inLine: l))` is that line's
    /// total advance width.
    ///
    /// Contract precondition: for every `c` in `0..<columnCount(inLine: line)`,
    /// `columnOffset(_, column: c)` and `columnOffset(_, column: c + 1)` are finite
    /// and strictly increasing. Raw glyph advances can be zero (combining marks,
    /// ZWJ, ligature components), so the provider must fold zero-advance glyphs into
    /// their base cell to honour this; a *cell* is a positive-advance,
    /// caret-positionable unit in visual (left-to-right) order. The core never
    /// queries outside `0...columnCount(inLine: line)`.
    ///
    /// Stability precondition: `columnCount(inLine:)` and `columnOffset(inLine:column:)`
    /// for a given line must be stable for one `columnAt` / `columnGeometryAt` query.
    func columnOffset(inLine line: Int, column: Int) -> Double

    /// Provider-native inverse-search hook (mirror of `lineIndex(containingOffset:)`).
    /// Returns the cell whose half-open span
    /// `[columnOffset(_, c), columnOffset(_, c+1))` contains `x`.
    ///
    /// Preconditions: `columnCount(inLine: line) > 0`,
    /// `columnOffset(_, column: 0) == 0`, `x` finite in `[0, lineWidth)`, same stable
    /// snapshot. Does not validate or clamp; public query semantics stay centralized
    /// in `ViewportVirtualizer.columnAt(x:inLine:metrics:)`.
    func columnIndex(containingOffset x: Double, inLine line: Int) -> Int
}

extension LineHorizontalMetricsSource {
    public func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
        binarySearchColumnIndex(
            containingOffset: x, metrics: self,
            inLine: line, columnCount: columnCount(inLine: line)
        )
    }
}

// Largest c in [0, columnCount) with columnOffset(c) <= target (the cell whose
// half-open span contains target). Identical shape to binarySearchLineIndex, with
// the inLine/column addressing. Shared by the default columnIndex hook.
func binarySearchColumnIndex<Metrics: LineHorizontalMetricsSource>(
    containingOffset target: Double,
    metrics: Metrics,
    inLine line: Int,
    columnCount: Int
) -> Int {
    var low = 0
    var high = columnCount - 1
    var result = 0
    while low <= high {
        let mid = low + (high - low) / 2
        if metrics.columnOffset(inLine: line, column: mid) <= target {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    return result
}

/// Uniform-grid horizontal metrics — the faithful mirror of `UniformLineMetrics`,
/// placed in the core so the `ColumnAt*` equivalence oracle in `TextEngineCoreTests`
/// can drive it without a reference-provider dependency. O(1) metric, no per-line
/// storage. Uses the binary-search default for the inverse (no `columnIndex`
/// override).
public struct UniformColumnMetrics: LineHorizontalMetricsSource {
    public let columnsPerLine: Int
    public let columnWidth: Double

    public init(columnsPerLine: Int, columnWidth: Double) {
        self.columnsPerLine = columnsPerLine
        self.columnWidth = columnWidth
    }

    public func columnCount(inLine line: Int) -> Int { columnsPerLine }
    public func columnOffset(inLine line: Int, column: Int) -> Double {
        Double(column) * columnWidth
    }
}
