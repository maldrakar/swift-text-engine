public protocol LineMetricsSource {
    var lineCount: Int { get }

    /// Cumulative top offset (y) of line `index`, in layout units.
    ///
    /// Domain: `0...lineCount`. `offset(ofLine: 0) == 0` and
    /// `offset(ofLine: lineCount)` is the total document height.
    ///
    /// Contract precondition: for every `i` in `0..<lineCount`, both
    /// `offset(ofLine: i)` and `offset(ofLine: i + 1)` are finite and
    /// `offset(ofLine: i) < offset(ofLine: i + 1)` (every line has finite
    /// positive height, and `offset(ofLine: lineCount)` is part of the monotone
    /// chain). The core never queries outside `0...lineCount`.
    ///
    /// Stability precondition: `lineCount` and `offset(ofLine:)` must be stable
    /// for one layout/query operation - a `compute`, a `lineAt`, and any
    /// `VariableLineGeometryCursor` traversal derived from a range it produced -
    /// so the range, the located line, and the geometry come from one consistent
    /// snapshot.
    func offset(ofLine index: Int) -> Double

    /// Returns the line whose half-open vertical span contains `y`.
    ///
    /// Preconditions: `lineCount > 0`, `offset(ofLine: 0) == 0`, and `y` is
    /// finite and in `[0, offset(ofLine: lineCount))` for the same stable metrics
    /// snapshot. This primitive does not validate or clamp; public query
    /// semantics stay centralized in `ViewportVirtualizer.lineAt(y:metrics:)`.
    func lineIndex(containingOffset y: Double) -> Int
}

extension LineMetricsSource {
    public func lineIndex(containingOffset y: Double) -> Int {
        binarySearchLineIndex(containingOffset: y, metrics: self, lineCount: lineCount)
    }
}

func binarySearchLineIndex<Metrics: LineMetricsSource>(
    containingOffset target: Double,
    metrics: Metrics,
    lineCount: Int
) -> Int {
    var low = 0
    var high = lineCount - 1
    var result = 0
    while low <= high {
        let mid = low + (high - low) / 2
        if metrics.offset(ofLine: mid) <= target {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    return result
}

public struct UniformLineMetrics: LineMetricsSource {
    public let lineCount: Int
    public let lineHeight: Double

    public init(lineCount: Int, lineHeight: Double) {
        self.lineCount = lineCount
        self.lineHeight = lineHeight
    }

    public func offset(ofLine index: Int) -> Double {
        Double(index) * lineHeight
    }
}
