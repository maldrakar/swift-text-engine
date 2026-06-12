import TextEngineCore

/// Test metrics built from explicit per-line heights; `offset(ofLine:)` returns
/// the cumulative top (prefix sum). Domain `0...lineCount`.
struct ListLineMetrics: LineMetricsSource {
    let prefix: [Double]

    init(heights: [Double]) {
        var sums: [Double] = [0.0]
        sums.reserveCapacity(heights.count + 1)
        var running = 0.0
        for height in heights {
            running += height
            sums.append(running)
        }
        self.prefix = sums
    }

    var lineCount: Int { prefix.count - 1 }

    func offset(ofLine index: Int) -> Double { prefix[index] }
}

/// Test metrics with an explicit `lineCount` and a custom offset function, used
/// to drive the contract/validation edge cases.
struct ClosureLineMetrics: LineMetricsSource {
    let lineCount: Int
    let offsetForLine: @Sendable (Int) -> Double

    func offset(ofLine index: Int) -> Double { offsetForLine(index) }
}
