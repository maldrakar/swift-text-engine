public protocol DocumentLineSource {
    associatedtype Line

    var lineCount: Int { get }

    func line(at index: Int) -> DocumentLineFetch<Line>
}

public enum DocumentLineFetch<Line> {
    case found(Line)
    case missing
}

extension DocumentLineFetch: Equatable where Line: Equatable {}

public struct DocumentLine<Line> {
    public let index: Int
    public let content: Line

    public init(index: Int, content: Line) {
        self.index = index
        self.content = content
    }
}

extension DocumentLine: Equatable where Line: Equatable {}

public enum DocumentLineCursorElement<Line> {
    case line(DocumentLine<Line>)
    case missing(index: Int)
}

extension DocumentLineCursorElement: Equatable where Line: Equatable {}
