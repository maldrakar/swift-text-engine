/// The visual-row axis for soft-wrap (Family A): the document's logical-line count,
/// a uniform visual-row height, the wrap width these counts are computed at, and the
/// provider-owned prefix sum of per-line visual-row counts. Mirrors `LineMetricsSource`
/// (count + cumulative `firstVisualRow` + a `logicalLine` inverse hook with a
/// binary-search default). Refines `WrapMetricsSource` so the cursor can reconstruct
/// each row's span from the same object (advances + break opportunities). The width is
/// baked in — a width change is a *new* provider.
public protocol VisualRowLayoutSource: WrapMetricsSource {
    /// Number of logical lines in the document.
    var lineCount: Int { get }

    /// Uniform height of one visual row, in layout units. Precondition: finite, `> 0`.
    var rowHeight: Double { get }

    /// The layout width these row counts are computed at. `> 0`, `+∞` allowed.
    var wrapWidth: Double { get }

    /// Visual rows logical line `line` packs into at `wrapWidth`. Precondition `>= 1`,
    /// and equal to node 1's packed row count for `line` at `wrapWidth`.
    func visualRowCount(inLine line: Int) -> Int

    /// Cumulative visual rows before logical line `line` (prefix sum of `visualRowCount`
    /// over `0..<line`). Domain `0...lineCount`; `firstVisualRow(ofLine: 0) == 0`;
    /// `firstVisualRow(ofLine: lineCount)` is the total visual-row count; strictly
    /// increasing. O(1), provider-owned. A width change reindexes exactly this.
    func firstVisualRow(ofLine line: Int) -> Int

    /// Largest `L` with `firstVisualRow(ofLine: L) <= g` — the logical line whose
    /// visual-row span contains global visual row `g`. Precondition `lineCount > 0`,
    /// `0 <= g < firstVisualRow(ofLine: lineCount)`. Does not validate or clamp.
    func logicalLine(containingVisualRow g: Int) -> Int
}

extension VisualRowLayoutSource {
    public func logicalLine(containingVisualRow g: Int) -> Int {
        binarySearchLogicalLine(containingVisualRow: g, layout: self, lineCount: lineCount)
    }
}

// Largest L in [0, lineCount) with firstVisualRow(ofLine: L) <= target. Identical shape
// to binarySearchLineIndex. Shared by the default logicalLine hook; a balanced-tree
// provider may override the hook for a single O(log N) descent (a later node).
func binarySearchLogicalLine<L: VisualRowLayoutSource>(
    containingVisualRow target: Int, layout: L, lineCount: Int
) -> Int {
    var low = 0
    var high = lineCount - 1
    var result = 0
    while low <= high {
        let mid = low + (high - low) / 2
        if layout.firstVisualRow(ofLine: mid) <= target {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    return result
}
