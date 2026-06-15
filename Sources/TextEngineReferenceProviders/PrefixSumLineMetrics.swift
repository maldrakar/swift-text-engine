import TextEngineCore

/// Reference static provider: cumulative offsets precomputed as a prefix-sum
/// array. `offset(ofLine:)` is O(1), but any height change requires an O(N)
/// rebuild. Used as the correctness oracle for `FenwickLineMetrics` and by the
/// variable-height benchmark.
public struct PrefixSumLineMetrics: LineMetricsSource {
    public let prefix: [Double]

    public init(heights: [Double]) {
        var sums: [Double] = [0.0]
        sums.reserveCapacity(heights.count + 1)
        var running = 0.0
        for height in heights {
            running += height
            sums.append(running)
        }
        self.prefix = sums
    }

    public var lineCount: Int { prefix.count - 1 }

    public func offset(ofLine index: Int) -> Double { prefix[index] }
}
