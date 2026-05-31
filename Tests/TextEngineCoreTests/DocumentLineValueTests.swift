import XCTest
@testable import TextEngineCore

final class DocumentLineValueTests: XCTestCase {
    func testDocumentLineStoresIndexAndContent() {
        let line = DocumentLine(index: 7, content: "seven")

        XCTAssertEqual(line.index, 7)
        XCTAssertEqual(line.content, "seven")
    }

    func testDocumentLineFetchEquatableWhenPayloadIsEquatable() {
        XCTAssertEqual(
            DocumentLineFetch<String>.found("line"),
            DocumentLineFetch<String>.found("line")
        )
        XCTAssertNotEqual(
            DocumentLineFetch<String>.found("line"),
            DocumentLineFetch<String>.found("other")
        )
        XCTAssertEqual(
            DocumentLineFetch<String>.missing,
            DocumentLineFetch<String>.missing
        )
        XCTAssertNotEqual(
            DocumentLineFetch<String>.found("line"),
            DocumentLineFetch<String>.missing
        )
    }

    func testDocumentLineEquatableWhenPayloadIsEquatable() {
        XCTAssertEqual(
            DocumentLine(index: 1, content: "one"),
            DocumentLine(index: 1, content: "one")
        )
        XCTAssertNotEqual(
            DocumentLine(index: 1, content: "one"),
            DocumentLine(index: 2, content: "one")
        )
        XCTAssertNotEqual(
            DocumentLine(index: 1, content: "one"),
            DocumentLine(index: 1, content: "two")
        )
    }

    func testDocumentLineCursorElementEquatableWhenPayloadIsEquatable() {
        XCTAssertEqual(
            DocumentLineCursorElement.line(DocumentLine(index: 2, content: "two")),
            DocumentLineCursorElement.line(DocumentLine(index: 2, content: "two"))
        )
        XCTAssertNotEqual(
            DocumentLineCursorElement.line(DocumentLine(index: 2, content: "two")),
            DocumentLineCursorElement.line(DocumentLine(index: 2, content: "other"))
        )
        XCTAssertEqual(
            DocumentLineCursorElement<String>.missing(index: 4),
            DocumentLineCursorElement<String>.missing(index: 4)
        )
        XCTAssertNotEqual(
            DocumentLineCursorElement<String>.missing(index: 4),
            DocumentLineCursorElement<String>.missing(index: 5)
        )
        XCTAssertNotEqual(
            DocumentLineCursorElement.line(DocumentLine(index: 4, content: "four")),
            DocumentLineCursorElement<String>.missing(index: 4)
        )
    }
}
