/// Streams the placed visual rows of a document over a buffer visual-row range, in
/// visual order. Reuses node 1's per-line `VisualRowCursor` for packing; holds the
/// provider, so it is generic and O(1) state. Construct via
/// `ViewportVirtualizer.visualRowGeometry(for:layout:)`. Cost: O(rowInStartLine +
/// buffer) — the O(rowInStartLine) is the accepted within-line walk (spec fork).
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
        let rowInStartLine = range.bufferStart - layout.firstVisualRow(ofLine: startLine)
        self.currentLine = startLine
        self.inner = Self.makeInner(line: startLine, layout: layout, wrapWidth: wrapWidth)
        for _ in 0..<rowInStartLine { _ = inner?.next() }   // accepted O(rowInLine) walk
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
