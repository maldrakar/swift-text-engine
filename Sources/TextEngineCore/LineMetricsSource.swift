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

    /// Returns the smallest line index `i` in `lowerBound...lineCount` with
    /// `offset(ofLine: i) >= y` - the first line whose top is at or above `y`
    /// (end-exclusive). The inverse-direction companion to
    /// `lineIndex(containingOffset:)`, used by `compute` for the visible-end edge.
    ///
    /// `lowerBound` is a correctness-preserving optimization hint: the true
    /// answer is provably `>= lowerBound`, so an override may ignore it and still
    /// return the same index. Fallback providers use it to narrow the search.
    ///
    /// Preconditions: `lineCount > 0`; `offset(ofLine: 0) == 0`; `y` is finite and
    /// in `[0, offset(ofLine: lineCount))`; `0 <= lowerBound <= lineCount` with
    /// `offset(ofLine: lowerBound) <= y`, for the same stable metrics snapshot.
    /// This primitive does not validate or clamp; public query semantics stay
    /// centralized in `ViewportVirtualizer.compute`.
    func firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int
}

extension LineMetricsSource {
    public func lineIndex(containingOffset y: Double) -> Int {
        binarySearchLineIndex(containingOffset: y, metrics: self, lineCount: lineCount)
    }

    public func firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int {
        firstLineIndexAtOrAbove(offset: y, metrics: self, lowerBound: lowerBound, lineCount: lineCount)
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

// Smallest i in lowerBound...lineCount with offset(ofLine: i) >= target (the
// first line whose top is at or above target, end-exclusive). Narrowed by
// lowerBound; the answer is provably >= lowerBound. Shared by the default
// firstLineIndex hook so the fallback path has a single >= boundary convention.
func firstLineIndexAtOrAbove<Metrics: LineMetricsSource>(
    offset target: Double,
    metrics: Metrics,
    lowerBound: Int,
    lineCount: Int
) -> Int {
    var low = lowerBound
    var high = lineCount - 1
    var result = lineCount
    while low <= high {
        let mid = low + (high - low) / 2
        if metrics.offset(ofLine: mid) >= target {
            result = mid
            high = mid - 1
        } else {
            low = mid + 1
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
