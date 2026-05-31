public struct LineGeometryCursor {
    private var nextLineIndex: Int
    private let endExclusive: Int
    private let lineHeight: Double

    public init(bufferStart: Int, bufferEndExclusive: Int, lineHeight: Double) {
        self.nextLineIndex = bufferStart
        self.endExclusive = bufferEndExclusive
        self.lineHeight = lineHeight
    }

    public mutating func next() -> LineGeometry? {
        if nextLineIndex >= endExclusive {
            return nil
        }

        let lineIndex = nextLineIndex
        nextLineIndex += 1

        return LineGeometry(
            lineIndex: lineIndex,
            y: Double(lineIndex) * lineHeight,
            height: lineHeight
        )
    }
}

extension ViewportVirtualizer {
    public static func geometry(for range: VirtualRange, lineHeight: Double) -> LineGeometryCursor {
        LineGeometryCursor(
            bufferStart: range.bufferStart,
            bufferEndExclusive: range.bufferEndExclusive,
            lineHeight: lineHeight
        )
    }
}
