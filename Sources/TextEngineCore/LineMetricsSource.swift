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
    /// for one layout operation — a `compute` and any `VariableLineGeometryCursor`
    /// traversal derived from the range it produced — so the range and the
    /// geometry come from one consistent snapshot.
    func offset(ofLine index: Int) -> Double
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
