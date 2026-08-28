/// Streams the placed visual rows of a document over a buffer visual-row range, in
/// visual order. Reuses node 1's per-line `VisualRowCursor` for packing; holds the
/// provider, so it is generic and O(1) state. Construct via
/// `ViewportVirtualizer.visualRowGeometry(for:layout:)`. Cost: O(rowInStartLine +
/// buffer) — the O(rowInStartLine) is the accepted within-line walk (node 2's spec
/// fork): rows 0…rowInStartLine−1 of the start line are packed, each interior row
/// scanning its cells, while a line's last row is O(1) (node 1's suffix short-circuit).
public struct DocumentVisualRowCursor<Layout: VisualRowLayoutSource> {
    private let layout: Layout
    private let rowHeight: Double
    private let wrapWidth: Double
    private var currentLine: Int
    private var inner: VisualRowCursor<Layout>?
    private var globalRow: Int
    private var remaining: Int

    init(range: VirtualRange, layout: Layout) {
        self.layout = layout
        self.rowHeight = layout.rowHeight
        self.wrapWidth = layout.wrapWidth
        self.globalRow = range.bufferStart
        self.remaining = range.bufferEndExclusive - range.bufferStart
        if remaining <= 0 || layout.lineCount == 0 {
            self.currentLine = layout.lineCount
            self.inner = nil
            self.remaining = 0
            return
        }
        let startLine = layout.logicalLine(containingVisualRow: range.bufferStart)
        // Guard 3 (slice 55 spec, Decision 4). The default hook cannot answer outside
        // 0..<lineCount; an override can, and `firstVisualRow(ofLine:)` below would trap
        // on it. Streaming has no failure channel, so the cursor takes the terminal state
        // it already has and streams nothing -- not the line from row 0, not the next
        // line; both are plausible-looking wrong answers.
        if startLine < 0 || startLine >= layout.lineCount {
            self.currentLine = layout.lineCount
            self.inner = nil
            self.remaining = 0
            return
        }
        let rowInStartLine = range.bufferStart - layout.firstVisualRow(ofLine: startLine)
        // Guard 4: an in-range line whose firstVisualRow exceeds bufferStart -- the other
        // way an override can lie -- makes this negative, and the walk would trap on its
        // range. Same terminal state.
        if rowInStartLine < 0 {
            self.currentLine = layout.lineCount
            self.inner = nil
            self.remaining = 0
            return
        }
        self.currentLine = startLine
        self.inner = Self.makeInner(line: startLine, layout: layout, wrapWidth: wrapWidth)
        // The accepted O(rowInLine) walk, through the helper node 4's query shares. A nil
        // `inner` (a malformed line, GIGO -- see makeInner) keeps its shipped meaning:
        // there is nothing to walk.
        if var cursor = inner {
            _ = advanceVisualRows(&cursor, by: rowInStartLine)
            inner = cursor
        }
    }

    private static func makeInner(line: Int, layout: Layout, wrapWidth: Double) -> VisualRowCursor<Layout>? {
        if case .rows(let cursor) = ViewportVirtualizer.visualRows(inLine: line, wrapWidth: wrapWidth, metrics: layout) {
            return cursor
        }
        // A `.failure` here means the provider violated the trusted per-line metrics
        // precondition: Decision 6 re-reads interior columnOffset/canBreak without
        // re-validating them, so a malformed line is undefined-behavior input, not a
        // handled case. Streaming has no failure channel — stop this line (GIGO) rather
        // than fabricate a row.
        return nil
    }

    public mutating func next() -> VisualRowGeometry? {
        if remaining <= 0 { return nil }
        while true {
            if let row = inner?.next() {
                let geom = VisualRowGeometry(row: row, y: Double(globalRow) * rowHeight, height: rowHeight)
                globalRow += 1
                remaining -= 1
                return geom
            }
            currentLine += 1
            if currentLine >= layout.lineCount {
                remaining = 0
                return nil
            }
            inner = Self.makeInner(line: currentLine, layout: layout, wrapWidth: wrapWidth)
        }
    }
}

/// Advances `cursor` by `k` rows and returns the result of the k-th `next()` call: `nil`
/// if `k <= 0` (a negative `k` never forms a range) or if any of the `k` calls returned
/// `nil` -- it stops at that call rather than spinning the rest -- and row `k - 1`
/// otherwise. NOT the last non-nil row seen along the way: node 4's `visualPointAt`
/// relies on `nil` meaning "the walk ran out before the row it asked for" (spec
/// Decision 4).
///
/// `inout` on purpose. `VisualRowCursor` is a struct; a by-value helper would advance a
/// copy and leave the caller's cursor where it was -- a mutation that compiles and passes
/// a one-row test. Shared by `DocumentVisualRowCursor.init` (k = rowInStartLine, return
/// discarded) and `visualPointAt` (k = rowInLine + 1, return kept), so the two agree on
/// "row k of line L" by construction rather than by two tests agreeing.
func advanceVisualRows<M: WrapMetricsSource>(_ cursor: inout VisualRowCursor<M>, by k: Int) -> VisualRow? {
    if k <= 0 { return nil }
    var last: VisualRow? = nil
    for _ in 0..<k {
        guard let row = cursor.next() else { return nil }
        last = row
    }
    return last
}

extension ViewportVirtualizer {
    /// Streams the placed `VisualRowGeometry` of the buffer visual-row range, in visual
    /// order. Precondition: `range` came from `compute(_:layout:)` over the same stable
    /// `layout`. Stateless; the cursor is lazy.
    public static func visualRowGeometry<Layout: VisualRowLayoutSource>(
        for range: VirtualRange, layout: Layout
    ) -> DocumentVisualRowCursor<Layout> {
        DocumentVisualRowCursor(range: range, layout: layout)
    }
}
