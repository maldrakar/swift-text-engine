public struct VariableLineGeometryCursor<Metrics: LineMetricsSource> {
    private let metrics: Metrics
    private var nextLineIndex: Int
    private let endExclusive: Int
    private var nextLineTop: Double

    public init(bufferStart: Int, bufferEndExclusive: Int, metrics: Metrics) {
        self.metrics = metrics
        self.nextLineIndex = bufferStart
        self.endExclusive = bufferEndExclusive
        self.nextLineTop = bufferStart < bufferEndExclusive ? metrics.offset(ofLine: bufferStart) : 0.0
    }

    public mutating func next() -> LineGeometry? {
        if nextLineIndex >= endExclusive {
            return nil
        }

        let lineIndex = nextLineIndex
        let y = nextLineTop
        let bottom = metrics.offset(ofLine: lineIndex + 1)
        nextLineIndex += 1
        nextLineTop = bottom

        return LineGeometry(lineIndex: lineIndex, y: y, height: bottom - y)
    }
}

extension ViewportVirtualizer {
    public static func geometry<Metrics: LineMetricsSource>(
        for range: VirtualRange,
        metrics: Metrics
    ) -> VariableLineGeometryCursor<Metrics> {
        VariableLineGeometryCursor(
            bufferStart: range.bufferStart,
            bufferEndExclusive: range.bufferEndExclusive,
            metrics: metrics
        )
    }
}
