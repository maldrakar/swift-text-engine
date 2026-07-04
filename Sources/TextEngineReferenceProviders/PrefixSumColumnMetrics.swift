import TextEngineCore

/// Reference variable/proportional horizontal provider — the faithful mirror of
/// `PrefixSumLineMetrics`. Per-line cumulative offsets precomputed as prefix-sum
/// arrays; `columnOffset` is O(1). Provider-side per-line storage lives here,
/// outside the core-memory invariant. Uses the binary-search default for the
/// inverse (no `columnIndex` override — a native descent is a future slice). The
/// realistic non-uniform-advance case for the containing-cell search.
public struct PrefixSumColumnMetrics: LineHorizontalMetricsSource {
    /// One prefix-sum array per line: `prefix[line][c]` is the left offset of cell
    /// `c`, with `prefix[line][0] == 0` and `prefix[line].count == cells + 1`.
    public let prefix: [[Double]]

    /// `advancesPerLine[line]` is that line's per-cell advances (widths).
    public init(advancesPerLine: [[Double]]) {
        prefix = advancesPerLine.map { advances in
            var sums: [Double] = [0.0]
            sums.reserveCapacity(advances.count + 1)
            var running = 0.0
            for advance in advances {
                running += advance
                sums.append(running)
            }
            return sums
        }
    }

    public func columnCount(inLine line: Int) -> Int { prefix[line].count - 1 }
    public func columnOffset(inLine line: Int, column: Int) -> Double {
        prefix[line][column]
    }
}
