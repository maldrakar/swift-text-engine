# Document Source Provider Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a generic document/source provider contract and buffered-range line cursor to `TextEngineCore`, with host, iOS, WASM, and embedded WASM library compile verification.

**Architecture:** `ViewportVirtualizer.compute(_:)` remains a pure range calculator. Provider integration is a separate cursor built from an already-computed `VirtualRange`, and it fetches only `bufferStart..<bufferEndExclusive` from a caller-owned source. The public API uses Swift standard-library protocols, structs, enums, generics, and conditional `Equatable` conformances without Foundation.

**Tech Stack:** Swift Package Manager, Swift 6.2.1, XCTest, `xcrun swiftc` for iOS module compile checks, Swift SDKs `swift-6.2.1-RELEASE_wasm` and `swift-6.2.1-RELEASE_wasm-embedded`.

---

## Scope Check

This plan implements the approved Slice 2 spec:

- `docs/superpowers/specs/2026-05-31-document-source-provider-contract-design.md`

It does not add file storage, rope storage, async loading, prefetch, caching, variable-height layout, UI adapters, or provider benchmarks.

## File Structure

- Create `Sources/TextEngineCore/DocumentLineTypes.swift`: public provider protocol and provider result/value enums and structs.
- Create `Sources/TextEngineCore/DocumentLineCursor.swift`: cursor that walks a `VirtualRange` buffered range and fetches from a `DocumentLineSource`.
- Create `Tests/TextEngineCoreTests/DocumentLineValueTests.swift`: value and conditional equality tests for the new public types.
- Create `Tests/TextEngineCoreTests/DocumentLineCursorTests.swift`: integration tests with test-only array and counting sources.
- Create `docs/superpowers/verification/2026-05-31-document-source-provider-contract.md`: verification record with exact commands and target results.
- Existing files in `Sources/TextEngineCore` remain unchanged unless a compile issue requires a minimal compatibility adjustment.

## Task 1: Provider Contract Value Types

**Files:**
- Create: `Tests/TextEngineCoreTests/DocumentLineValueTests.swift`
- Create: `Sources/TextEngineCore/DocumentLineTypes.swift`

- [ ] **Step 1: Write failing value and protocol tests**

Create `Tests/TextEngineCoreTests/DocumentLineValueTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the new tests to verify the types are missing**

Run:

```bash
swift test --filter DocumentLineValueTests
```

Expected: FAIL with compiler errors for missing `DocumentLine`, `DocumentLineFetch`, and `DocumentLineCursorElement`.

- [ ] **Step 3: Add the provider contract value types**

Create `Sources/TextEngineCore/DocumentLineTypes.swift`:

```swift
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
```

- [ ] **Step 4: Run the value tests to verify they pass**

Run:

```bash
swift test --filter DocumentLineValueTests
```

Expected: PASS.

- [ ] **Step 5: Run the existing Slice 1 tests**

Run:

```bash
swift test --filter Viewport
swift test --filter LineGeometryCursorTests
```

Expected: both commands PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/TextEngineCore/DocumentLineTypes.swift Tests/TextEngineCoreTests/DocumentLineValueTests.swift
git commit -m "feat: add document line source types"
```

Expected: commit succeeds.

## Task 2: Buffered Document Line Cursor

**Files:**
- Create: `Tests/TextEngineCoreTests/DocumentLineCursorTests.swift`
- Create: `Sources/TextEngineCore/DocumentLineCursor.swift`

- [ ] **Step 1: Write failing cursor and integration tests**

Create `Tests/TextEngineCoreTests/DocumentLineCursorTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the cursor tests to verify the cursor API is missing**

Run:

```bash
swift test --filter DocumentLineCursorTests
```

Expected: FAIL with compiler errors for missing `ViewportVirtualizer.lines(for:in:)`.

- [ ] **Step 3: Add the buffered line cursor**

Create `Sources/TextEngineCore/DocumentLineCursor.swift`:

```swift
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
```

- [ ] **Step 4: Run the cursor tests to verify they pass**

Run:

```bash
swift test --filter DocumentLineCursorTests
```

Expected: PASS.

- [ ] **Step 5: Run all tests**

Run:

```bash
swift test
```

Expected: PASS. The total test count should increase from Slice 1's 29 XCTest tests by the new value and cursor tests.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/TextEngineCore/DocumentLineCursor.swift Tests/TextEngineCoreTests/DocumentLineCursorTests.swift
git commit -m "feat: add buffered document line cursor"
```

Expected: commit succeeds.

## Task 3: Compile Verification Record

**Files:**
- Create: `docs/superpowers/verification/2026-05-31-document-source-provider-contract.md`

- [ ] **Step 1: Run host verification**

Run:

```bash
swift test
swift build -c release
```

Expected:

- `swift test`: PASS.
- `swift build -c release`: PASS.

- [ ] **Step 2: Run WASM library target verification**

Run:

```bash
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
```

Expected:

- Both commands PASS.
- Do not use `--product TextEngineCore`; `TextEngineCore` is an automatic library product and SwiftPM may build unrelated executable products for product builds.

- [ ] **Step 3: Run iOS library module verification**

Run:

```bash
xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
```

Expected:

- Both commands PASS.
- If sandboxing blocks compiler cache writes, rerun the same commands with approved escalated execution.

- [ ] **Step 4: Create the verification record**

Create `docs/superpowers/verification/2026-05-31-document-source-provider-contract.md`:

```markdown
# Document Source Provider Contract Verification

Date: 2026-05-31

## Commands

- `swift test`: pass
- `swift build -c release`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`: pass
- `xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule`: pass
- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule`: pass

## Swift Embedded-Sensitive Choices

- `DocumentLineSource` uses an associated type and a non-throwing method.
- `DocumentLineFetch`, `DocumentLine`, and `DocumentLineCursorElement` are generic public types.
- `DocumentLineCursor` is generic over `DocumentLineSource` and uses a mutating `next()` method rather than `Sequence` conformance.
- Conditional `Equatable` conformances are used only when the generic line payload is `Equatable`.
- The public API does not import Foundation.

## Target Verification

- Host SwiftPM build and tests: verified.
- iOS device source compatibility: verified by direct `xcrun swiftc` module compile.
- iOS simulator source compatibility: verified by direct `xcrun swiftc` module compile.
- WASM source compatibility: verified for the `TextEngineCore` target.
- Embedded WASM source compatibility: verified for the `TextEngineCore` target.

## Benchmark Scope

No provider benchmark was required for Slice 2.

`ViewportBenchmarks` remains outside embedded WASM verification because it uses `ContinuousClock`. The Slice 2 compile gate targets only the `TextEngineCore` library target.
```

- [ ] **Step 5: Commit the verification record**

Run:

```bash
git add docs/superpowers/verification/2026-05-31-document-source-provider-contract.md
git commit -m "docs: record document source provider verification"
```

Expected: commit succeeds.

## Final Check

- [ ] **Step 1: Run complete verification**

Run:

```bash
swift test
swift build -c release
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
git status --short
```

Expected:

- All Swift and `xcrun swiftc` commands PASS.
- `git status --short` prints no tracked-file changes.

- [ ] **Step 2: Inspect public API for Foundation leaks**

Run:

```bash
rg -n "import Foundation|URL|Data|NSError|NS" Sources/TextEngineCore
```

Expected: no output.

- [ ] **Step 3: Inspect provider integration for viewport hot-path coupling**

Run:

```bash
rg -n "DocumentLineSource|DocumentLineCursor|line\\(at:" Sources/TextEngineCore/ViewportVirtualizer.swift
```

Expected: no output. Provider access must stay outside `ViewportVirtualizer.compute(_:)`.
