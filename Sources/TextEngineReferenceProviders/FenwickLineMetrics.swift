import TextEngineCore

/// Mutable, indexed metrics provider backed by a Binary Indexed Tree (Fenwick
/// tree) over per-line heights. `offset(ofLine:)` is O(log N); a single-line
/// height change (`setHeight`) is a localized O(log N) update, versus the O(N)
/// rebuild a prefix-sum array needs. Provider-owned memory is O(N) - the line
/// metrics are the document, living outside the stateless core.
public struct FenwickLineMetrics: LineMetricsSource {
    private var heights: [Double]   // per-line heights; count == lineCount
    private var tree: [Double]      // 1-based BIT; count == lineCount + 1

    /// Number of BIT cells written by the most recent `setHeight` (the set-bit
    /// step count of the update walk, <= floor(log2 N) + 1). Deterministic
    /// evidence for the O(log N) update claim.
    public private(set) var lastUpdateWriteCount: Int

    public init(heights: [Double]) {
        for height in heights {
            precondition(
                height.isFinite && height > 0.0,
                "FenwickLineMetrics requires finite, positive heights"
            )
        }
        let n = heights.count
        var tree = [Double](repeating: 0.0, count: n + 1)
        // O(N) Fenwick construction: seed each cell, then push it into its parent.
        var i = 1
        while i <= n {
            tree[i] += heights[i - 1]
            let parent = i + (i & (-i))
            if parent <= n {
                tree[parent] += tree[i]
            }
            i += 1
        }
        self.heights = heights
        self.tree = tree
        self.lastUpdateWriteCount = 0
    }

    public var lineCount: Int { heights.count }

    // offset(ofLine: index) = sum(heights[0..<index]); reads one cell per set bit
    // of `index`, i.e. popcount(index) <= floor(log2 N) + 1 cells.
    public func offset(ofLine index: Int) -> Double {
        var sum = 0.0
        var i = index
        while i > 0 {
            sum += tree[i]
            i -= i & (-i)
        }
        return sum
    }

    // Sets line `index` to `newHeight`. delta = newHeight - heights[index] is
    // computed in O(1) from the heights array; one BIT point-update walks
    // `i += i & (-i)` in O(log N). Returns the number of cells written.
    @discardableResult
    public mutating func setHeight(ofLine index: Int, to newHeight: Double) -> Int {
        precondition(
            index >= 0 && index < heights.count,
            "FenwickLineMetrics.setHeight index out of range"
        )
        precondition(
            newHeight.isFinite && newHeight > 0.0,
            "FenwickLineMetrics.setHeight requires a finite, positive height"
        )
        let delta = newHeight - heights[index]
        heights[index] = newHeight

        var writes = 0
        var i = index + 1
        let n = heights.count
        while i <= n {
            tree[i] += delta
            writes += 1
            i += i & (-i)
        }
        lastUpdateWriteCount = writes
        return writes
    }
}
