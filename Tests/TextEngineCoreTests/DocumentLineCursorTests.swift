import XCTest
@testable import TextEngineCore

private struct ArrayBackedLineSource: DocumentLineSource {
    let lines: [String]

    var lineCount: Int {
        lines.count
    }

    func line(at index: Int) -> DocumentLineFetch<String> {
        if index < 0 || index >= lines.count {
            return .missing
        }

        return .found(lines[index])
    }
}

private final class CountingLineSource: DocumentLineSource {
    typealias Line = String

    private let lines: [String]
    private(set) var requestedIndexes: [Int] = []

    init(lines: [String]) {
        self.lines = lines
    }

    var lineCount: Int {
        lines.count
    }

    func line(at index: Int) -> DocumentLineFetch<String> {
        requestedIndexes.append(index)

        if index < 0 || index >= lines.count {
            return .missing
        }

        return .found(lines[index])
    }
}

final class DocumentLineCursorTests: XCTestCase {
    func testCursorYieldsBufferedRangeLinesInOrder() {
        let source = ArrayBackedLineSource(
            lines: ["zero", "one", "two", "three", "four", "five"]
        )
        let range = VirtualRange(
            visibleStart: 2,
            visibleEndExclusive: 4,
            bufferStart: 1,
            bufferEndExclusive: 5,
            isAtTop: false,
            isAtBottom: false
        )

        var cursor = ViewportVirtualizer.lines(for: range, in: source)
        var output: [DocumentLineCursorElement<String>] = []
        while let element = cursor.next() {
            output.append(element)
        }

        XCTAssertEqual(
            output,
            [
                .line(DocumentLine(index: 1, content: "one")),
                .line(DocumentLine(index: 2, content: "two")),
                .line(DocumentLine(index: 3, content: "three")),
                .line(DocumentLine(index: 4, content: "four"))
            ]
        )
    }

    func testCursorYieldsNothingForEmptyRangeAndDoesNotFetch() {
        let source = CountingLineSource(lines: ["zero", "one", "two"])
        let range = VirtualRange(
            visibleStart: 0,
            visibleEndExclusive: 0,
            bufferStart: 0,
            bufferEndExclusive: 0,
            isAtTop: true,
            isAtBottom: true
        )

        var cursor = ViewportVirtualizer.lines(for: range, in: source)

        XCTAssertNil(cursor.next())
        XCTAssertEqual(source.requestedIndexes, [])
    }

    func testCursorReportsMissingIndexesWithoutClampingRange() {
        let source = ArrayBackedLineSource(lines: ["zero", "one", "two"])
        let range = VirtualRange(
            visibleStart: 1,
            visibleEndExclusive: 3,
            bufferStart: 1,
            bufferEndExclusive: 5,
            isAtTop: false,
            isAtBottom: true
        )

        var cursor = ViewportVirtualizer.lines(for: range, in: source)
        var output: [DocumentLineCursorElement<String>] = []
        while let element = cursor.next() {
            output.append(element)
        }

        XCTAssertEqual(
            output,
            [
                .line(DocumentLine(index: 1, content: "one")),
                .line(DocumentLine(index: 2, content: "two")),
                .missing(index: 3),
                .missing(index: 4)
            ]
        )
    }

    func testCursorFetchesOneLinePerBufferedIndex() {
        let source = CountingLineSource(
            lines: ["zero", "one", "two", "three", "four", "five", "six"]
        )
        let range = VirtualRange(
            visibleStart: 3,
            visibleEndExclusive: 5,
            bufferStart: 2,
            bufferEndExclusive: 6,
            isAtTop: false,
            isAtBottom: false
        )

        var cursor = ViewportVirtualizer.lines(for: range, in: source)
        while cursor.next() != nil {}

        XCTAssertEqual(source.requestedIndexes, [2, 3, 4, 5])
    }

    func testViewportComputationDoesNotFetchProviderLines() {
        let source = CountingLineSource(
            lines: ["zero", "one", "two", "three", "four", "five"]
        )
        let input = ViewportInput(
            lineCount: source.lineCount,
            lineHeight: 10.0,
            scrollOffsetY: 10.0,
            viewportHeight: 20.0,
            overscanLinesBefore: 1,
            overscanLinesAfter: 1
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 1,
                    visibleEndExclusive: 3,
                    bufferStart: 0,
                    bufferEndExclusive: 4,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
        XCTAssertEqual(source.requestedIndexes, [])
    }

    func testGeneratedRangesFetchOnlyBufferedIndexes() {
        let source = CountingLineSource(
            lines: (0..<1_000).map { "line-\($0)" }
        )

        for start in stride(from: 0, through: 900, by: 100) {
            let range = VirtualRange(
                visibleStart: start + 10,
                visibleEndExclusive: start + 20,
                bufferStart: start,
                bufferEndExclusive: start + 30,
                isAtTop: start == 0,
                isAtBottom: false
            )
            var cursor = ViewportVirtualizer.lines(for: range, in: source)
            while cursor.next() != nil {}
        }

        let expected = Array(stride(from: 0, through: 900, by: 100)).flatMap { start in
            Array(start..<(start + 30))
        }
        XCTAssertEqual(source.requestedIndexes, expected)
    }
}
