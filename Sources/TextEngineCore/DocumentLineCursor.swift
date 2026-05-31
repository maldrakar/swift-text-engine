public struct DocumentLineCursor<Source: DocumentLineSource> {
    private let source: Source
    private var nextLineIndex: Int
    private let endExclusive: Int

    public init(range: VirtualRange, source: Source) {
        self.source = source
        self.nextLineIndex = range.bufferStart
        self.endExclusive = range.bufferEndExclusive
    }

    public mutating func next() -> DocumentLineCursorElement<Source.Line>? {
        if nextLineIndex >= endExclusive {
            return nil
        }

        let index = nextLineIndex
        nextLineIndex += 1

        switch source.line(at: index) {
        case let .found(content):
            return .line(DocumentLine(index: index, content: content))
        case .missing:
            return .missing(index: index)
        }
    }
}

extension ViewportVirtualizer {
    public static func lines<Source: DocumentLineSource>(
        for range: VirtualRange,
        in source: Source
    ) -> DocumentLineCursor<Source> {
        DocumentLineCursor(range: range, source: source)
    }
}
