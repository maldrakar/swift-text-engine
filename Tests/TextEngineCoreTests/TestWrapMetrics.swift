import TextEngineCore

/// Test-only `WrapMetricsSource` for a single line. `offsets` is that line's
/// cumulative column offsets (`offsets[0]` should be 0 for a valid line);
/// `columnCount == offsets.count - 1`, so `[]` yields -1 (drives
/// `.negativeColumnCount`) and `[0.0]` a blank line. `breakColumns` are the
/// interior columns (`1..<count`) where a break is legal. The `line` argument is
/// ignored — node-1 packing tests exercise one line at a time.
struct TestWrapMetrics: WrapMetricsSource {
    let offsets: [Double]
    let breakColumns: Set<Int>

    /// Build directly from cumulative offsets — use for validation edge cases:
    /// `[]` → count -1, `[0.0]` → blank, `[5.0]` → blank with bad offset0,
    /// `[0.0, 0.0]` → zero total, `[0.0, .infinity]` → non-finite total.
    init(offsets: [Double], breakColumns: Set<Int> = []) {
        self.offsets = offsets
        self.breakColumns = breakColumns
    }

    /// Convenience: build from per-cell advances (all positive). `offsets` become
    /// the prefix sums `[0, a0, a0+a1, …]`.
    init(advances: [Double], breakColumns: Set<Int> = []) {
        var sums: [Double] = [0.0]
        sums.reserveCapacity(advances.count + 1)
        var running = 0.0
        for a in advances {
            running += a
            sums.append(running)
        }
        self.init(offsets: sums, breakColumns: breakColumns)
    }

    func columnCount(inLine line: Int) -> Int { offsets.count - 1 }
    func columnOffset(inLine line: Int, column: Int) -> Double { offsets[column] }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
        breakColumns.contains(column)
    }
}
