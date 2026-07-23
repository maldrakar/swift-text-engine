import XCTest
import TextEngineCore

/// Faithful multi-line `VisualRowLayoutSource`. Row counts are precomputed at
/// construction by running node 1's packer per line, so `visualRowCount` agrees with
/// the packer by construction (the reference the cursor must match).
struct TestVisualRowLayout: VisualRowLayoutSource {
    let lineOffsets: [[Double]]   // per line: cumulative offsets [0, a0, a0+a1, ...]
    let lineBreaks: [Set<Int>]
    let rowHeight: Double
    let wrapWidth: Double
    let rowCounts: [Int]
    let firstRow: [Int]           // prefix sum, size lineCount + 1

    init(lines: [(advances: [Double], breaks: Set<Int>)], rowHeight: Double, wrapWidth: Double) {
        var offs: [[Double]] = []
        var brks: [Set<Int>] = []
        var counts: [Int] = []
        for (advances, breaks) in lines {
            let single = TestWrapMetrics(advances: advances, breakColumns: breaks)
            offs.append(single.offsets)
            brks.append(breaks)
            var n = 0
            if case .rows(var c) = ViewportVirtualizer.visualRows(
                inLine: 0, wrapWidth: wrapWidth, metrics: single
            ) {
                while c.next() != nil { n += 1 }
            }
            counts.append(n)
        }
        var pref: [Int] = [0]
        for n in counts { pref.append(pref.last! + n) }
        self.lineOffsets = offs
        self.lineBreaks = brks
        self.rowHeight = rowHeight
        self.wrapWidth = wrapWidth
        self.rowCounts = counts
        self.firstRow = pref
    }

    var lineCount: Int { lineOffsets.count }
    func columnCount(inLine line: Int) -> Int { lineOffsets[line].count - 1 }
    func columnOffset(inLine line: Int, column: Int) -> Double { lineOffsets[line][column] }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { lineBreaks[line].contains(column) }
    func visualRowCount(inLine line: Int) -> Int { rowCounts[line] }
    func firstVisualRow(ofLine line: Int) -> Int { firstRow[line] }
}

/// Hand-riggable `VisualRowLayoutSource` for validation-ladder tests: aggregates are set
/// directly (so `firstVisualRow(0)`, `totalRows`, `rowHeight`, `wrapWidth`, `lineCount`
/// can be made malformed). Column metrics are stubbed — `compute(_:layout:)` never reads
/// them (only the cursor does, and validation tests build no cursor).
struct RiggedVisualRowLayout: VisualRowLayoutSource {
    let lineCount: Int
    let rowHeight: Double
    let wrapWidth: Double
    let firstRow: [Int]   // size max(lineCount + 1, 1)

    func columnCount(inLine line: Int) -> Int { 0 }
    func columnOffset(inLine line: Int, column: Int) -> Double { 0.0 }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { false }
    func visualRowCount(inLine line: Int) -> Int { firstRow[line + 1] - firstRow[line] }
    func firstVisualRow(ofLine line: Int) -> Int { firstRow[line] }
}
