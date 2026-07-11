# 2D Point-Query (`pointAt(x:y:)`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ViewportVirtualizer.pointAt(x:y:lineMetrics:columnMetrics:)`, the first two-axis position query, composing the existing `lineAt` and `columnAt` 1D queries into a single `(x, y)` → `(line, cell)` hit-test, plus a local `--point-query` benchmark gate.

**Architecture:** Pure composition. `pointAt` runs `lineAt(y:)` over a `LineMetricsSource` first; on success it feeds the located line index into `columnAt(x:inLine:)` over a `LineHorizontalMetricsSource`. It adds no new search code, no new metrics protocol, no new provider, and no new error case — every validation and search is delegated to the two 1D queries, so their contracts stay single-sourced. The result is a nested `PointQuery` enum whose `.point` case always carries the located line plus a `ColumnResolution` (`.cell` or `.blankLine`).

**Tech Stack:** Swift 6.0, SwiftPM, XCTest. `Sources/TextEngineCore` (Foundation-free library), `Sources/ViewportBenchmarks` (executable, gates), `Tests/TextEngineCoreTests` + `Tests/TextEngineReferenceProvidersTests` (XCTest).

## Global Constraints

Copied verbatim from the spec and `AGENTS.md`; every task's requirements implicitly include these:

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty (exit 1). The public API must not expose Foundation types.
- **Swift Embedded compatible.** Only `Int` / `Double` / generics over protocols / enums / structs. No APIs that don't survive Embedded Swift.
- **Zero-dependency.** No third-party packages.
- **Compiles for iOS and WASM with no source changes.** iOS blocking, WASM observational.
- **Core-owned memory must not grow linearly with document size.** `pointAt` is O(1) core memory, zero allocation beyond the returned value structs.
- **`ViewportValidationError` is reused UNCHANGED.** No enum case is added or removed in this slice (contrast Slice 33). Every failure `pointAt` surfaces already exists.
- **Strictly additive.** No existing algorithm changes; the entire existing suite must pass unchanged in count and result, and all nine existing gates must pass with byte-identical checksums.
- **TDD, one logical step per commit**, conventional-commit prefixes (`feat:`, `test:`, `docs:`, `ci:`). Branch: `slice-37-point-query` (already created).

## File Structure

- **Create** `Sources/TextEngineCore/PointQuery.swift` — the `extension ViewportVirtualizer` holding `pointAt`. Mirrors `PositionQuery.swift` / `HorizontalPositionQuery.swift`. One responsibility: the 2D composition.
- **Modify** `Sources/TextEngineCore/ViewportTypes.swift` — add `PointQuery`, `PointLocation`, `ColumnResolution` beside the existing query/location types. **No** change to `ViewportValidationError`.
- **Create** `Tests/TextEngineCoreTests/PointAtTests.swift` — behavior + clamp + failure-precedence unit tests.
- **Create** `Tests/TextEngineCoreTests/PointAtDispatchTests.swift` — ordered-event dispatch / non-consultation tests.
- **Create** `Tests/TextEngineCoreTests/PointAtEquivalenceTests.swift` — the composition-parity oracle over an `(x, y)` grid.
- **Create** `Tests/TextEngineReferenceProvidersTests/PointAtReferenceProviderTests.swift` — `pointAt` over the reference providers.
- **Create** `Sources/ViewportBenchmarks/PointQueryBenchmark.swift` — the `--point-query` benchmark mode. Modeled on `ColumnQueryBenchmark.swift` + `LineQueryBenchmark.swift`.
- **Modify** `Sources/ViewportBenchmarks/BenchmarkOptions.swift` — add `.pointQuery` mode, `outputName`, `--point-query` parse arm, usage lines.
- **Modify** `Sources/ViewportBenchmarks/BenchmarkProgram.swift` — add `.pointQuery` arm.
- **Modify** `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift` — add `.pointQuery` `preconditionFailure` arm to the exhaustive `switch`.
- **Modify** `AGENTS.md` — architecture-paragraph `pointAt` sentence, `--point-query` in the Commands list + flags list.
- **Create** `docs/superpowers/verification/2026-07-10-point-query.md` — recorded commands + outputs + hosted run IDs.

---

### Task 1: `PointQuery` result types + `pointAt` composition + core behavior

**Files:**
- Create: `Sources/TextEngineCore/PointQuery.swift`
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (append after `ColumnGeometryLocation`, ~line 203)
- Test: `Tests/TextEngineCoreTests/PointAtTests.swift`

**Interfaces:**
- Consumes (already exist): `ViewportVirtualizer.lineAt(y:metrics:) -> LineQuery`, `ViewportVirtualizer.columnAt(x:inLine:metrics:) -> ColumnQuery`, `LineLocation`, `ColumnLocation`, `LineMetricsSource`, `LineHorizontalMetricsSource`, `UniformLineMetrics`, `UniformColumnMetrics`, `ViewportValidationError`.
- Produces (later tasks rely on these exact names/types):
  - `enum PointQuery: Equatable { case point(PointLocation); case empty; case failure(ViewportValidationError) }`
  - `struct PointLocation: Equatable { let line: LineLocation; let column: ColumnResolution; init(line:column:) }`
  - `enum ColumnResolution: Equatable { case cell(ColumnLocation); case blankLine }`
  - `static func ViewportVirtualizer.pointAt<VMetrics: LineMetricsSource, HMetrics: LineHorizontalMetricsSource>(x: Double, y: Double, lineMetrics: VMetrics, columnMetrics: HMetrics) -> PointQuery`

- [ ] **Step 1: Write the failing test file**

Create `Tests/TextEngineCoreTests/PointAtTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class PointAtTests: XCTestCase {
    // A hand-built horizontal source whose per-line cell counts / advances are
    // fixed by an array of advance-vectors. Blank lines are an empty advance
    // vector. Line-agnostic providers (UniformColumnMetrics) are used where the
    // located line index does not matter.
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let advancesPerLine: [[Double]]   // advancesPerLine[line] = per-cell widths
        func columnCount(inLine line: Int) -> Int { advancesPerLine[line].count }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            var sum = 0.0
            for i in 0..<column { sum += advancesPerLine[line][i] }
            return sum
        }
    }

    // MARK: Decision 4 rows

    func testEmptyDocumentIsEmptyForFiniteCoordinates() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        // Finite in-range and out-of-range extremes all short-circuit to .empty.
        for (x, y) in [(0.0, 0.0), (-5.0, -5.0), (999.0, 999.0)] {
            XCTAssertEqual(ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: v, columnMetrics: h), .empty)
        }
    }

    func testInRangeCellHit() {
        let v = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)      // totalHeight 160
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0) // width 40
        // y = 40 -> line 2 (inRange); x = 20 -> cell 2 (inRange, since 16 <= 20 < 24)
        let result = ViewportVirtualizer.pointAt(x: 20.0, y: 40.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .point(PointLocation(
            line: LineLocation(lineIndex: 2, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 2, clamp: .inRange))
        )))
    }

    func testBlankLocatedLineIsBlankLineForFiniteX() {
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)       // totalHeight 30
        // line 1 is blank (empty advance vector); lines 0 and 2 have cells.
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 8.0], [], [8.0]])
        // y = 15 -> line 1 (10 <= 15 < 20); any finite x -> .blankLine
        for x in [-3.0, 0.0, 5.0, 100.0] {
            let result = ViewportVirtualizer.pointAt(x: x, y: 15.0, lineMetrics: v, columnMetrics: h)
            XCTAssertEqual(result, .point(PointLocation(
                line: LineLocation(lineIndex: 1, clamp: .inRange),
                column: .blankLine
            )))
        }
    }

    // MARK: Clamp propagation

    func testVerticalClampOnlyKeepsCellResolved() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)       // totalHeight 64
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0) // width 40
        // y below the document -> clampedToTop at line 0; x = 12 -> cell 1 inRange
        let top = ViewportVirtualizer.pointAt(x: 12.0, y: -5.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(top, .point(PointLocation(
            line: LineLocation(lineIndex: 0, clamp: .clampedToTop),
            column: .cell(ColumnLocation(columnIndex: 1, clamp: .inRange))
        )))
        // y past the end -> clampedToBottom at last line; x = 12 -> cell 1 inRange
        let bottom = ViewportVirtualizer.pointAt(x: 12.0, y: 999.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(bottom, .point(PointLocation(
            line: LineLocation(lineIndex: 3, clamp: .clampedToBottom),
            column: .cell(ColumnLocation(columnIndex: 1, clamp: .inRange))
        )))
    }

    func testHorizontalClampOnlyKeepsLineResolved() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0) // width 40
        // y = 20 -> line 1 inRange; x < 0 -> clampedToLeft at cell 0
        let left = ViewportVirtualizer.pointAt(x: -1.0, y: 20.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(left, .point(PointLocation(
            line: LineLocation(lineIndex: 1, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft))
        )))
        // x >= width -> clampedToRight at last cell
        let right = ViewportVirtualizer.pointAt(x: 40.0, y: 20.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(right, .point(PointLocation(
            line: LineLocation(lineIndex: 1, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 4, clamp: .clampedToRight))
        )))
    }

    func testBothAxesClampedRecordsBothFlags() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)
        // y < 0 and x < 0 -> clampedToTop + clampedToLeft, both preserved
        let result = ViewportVirtualizer.pointAt(x: -1.0, y: -1.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .point(PointLocation(
            line: LineLocation(lineIndex: 0, clamp: .clampedToTop),
            column: .cell(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft))
        )))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter PointAtTests 2>&1 | tail -20`
Expected: FAIL — compile error, `cannot find 'PointLocation' in scope` / `type 'ViewportVirtualizer' has no member 'pointAt'`.

- [ ] **Step 3: Add the result types**

Append to `Sources/TextEngineCore/ViewportTypes.swift` (after the closing brace of `ColumnGeometryLocation`, at end of file):

```swift

public enum PointQuery: Equatable {
    case point(PointLocation)             // a line was located (cell may be blank)
    case empty                            // empty document: lineCount == 0
    case failure(ViewportValidationError) // vertical or horizontal validation failure
}

public struct PointLocation: Equatable {
    /// The located line (index + vertical clamp). Always a real line.
    public let line: LineLocation
    /// The located cell within that line, or `.blankLine` if the line has no cells.
    public let column: ColumnResolution

    public init(line: LineLocation, column: ColumnResolution) {
        self.line = line
        self.column = column
    }
}

public enum ColumnResolution: Equatable {
    case cell(ColumnLocation)             // a real cell was located (index + horizontal clamp)
    case blankLine                        // located line has no cells (columnCount(inLine:) == 0)
}
```

- [ ] **Step 4: Add the `pointAt` composition**

Create `Sources/TextEngineCore/PointQuery.swift`:

```swift
extension ViewportVirtualizer {
    /// Maps a single point `(x, y)` to the line whose vertical span contains `y`
    /// and the cell within that line whose horizontal span contains `x` — the 2D
    /// composite of `lineAt(y:metrics:)` and `columnAt(x:inLine:metrics:)`.
    ///
    /// Stateless, pure composition — it adds no search of its own. The vertical
    /// query runs first over `lineMetrics`; its failure short-circuits (the
    /// horizontal query needs a valid `inLine`, which only a vertical success can
    /// supply) and an empty document returns `.empty`. On a located line the line
    /// index feeds `columnAt` over `columnMetrics`: a horizontal failure surfaces at
    /// the top level (discarding the located line), a blank line becomes
    /// `.blankLine`, and a real cell becomes `.cell`. Both clamp flags carry through
    /// verbatim from their 1D queries, so a both-axes-clamped point records both.
    /// Cost is the sum of the two 1D envelopes: O(log N) + O(log M) queries (or
    /// better where a provider overrides its native inverse hook), O(1) core memory,
    /// zero allocation beyond the returned value structs. Validation is delegated
    /// entirely to the two 1D queries — a non-finite coordinate is a failure, not a
    /// clamp, and it is checked before either axis's zero-count short-circuit.
    public static func pointAt<VMetrics: LineMetricsSource, HMetrics: LineHorizontalMetricsSource>(
        x: Double,
        y: Double,
        lineMetrics: VMetrics,
        columnMetrics: HMetrics
    ) -> PointQuery {
        switch lineAt(y: y, metrics: lineMetrics) {
        case let .failure(error):
            return .failure(error)
        case .empty:
            return .empty
        case let .line(lineLocation):
            switch columnAt(x: x, inLine: lineLocation.lineIndex, metrics: columnMetrics) {
            case let .failure(error):
                return .failure(error)
            case .empty:
                return .point(PointLocation(line: lineLocation, column: .blankLine))
            case let .column(columnLocation):
                return .point(PointLocation(line: lineLocation, column: .cell(columnLocation)))
            }
        }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter PointAtTests 2>&1 | tail -20`
Expected: PASS — all six tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/PointQuery.swift Tests/TextEngineCoreTests/PointAtTests.swift
git commit -m "feat: add pointAt 2D composite position query"
```

---

### Task 2: Failure precedence + validation-before-short-circuit + dispatch/non-consultation

**Files:**
- Modify: `Tests/TextEngineCoreTests/PointAtTests.swift` (add failure/precedence cases)
- Test: `Tests/TextEngineCoreTests/PointAtDispatchTests.swift` (new)

**Interfaces:**
- Consumes: `ViewportVirtualizer.pointAt(...)`, `PointQuery`, `PointLocation`, `ColumnResolution`, `ViewportValidationError` (Task 1).
- Produces: no new public API — proves the failure-precedence and dispatch contract.

- [ ] **Step 1: Add failure + validation-ordering tests to `PointAtTests.swift`**

Append these methods inside `final class PointAtTests` (before its closing brace):

```swift
    // MARK: Failure precedence & validation-before-short-circuit

    func testVerticalFailureShortCircuits() {
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        // negative lineCount -> .negativeLineCount, horizontal never consulted
        let neg = UniformLineMetrics(lineCount: -1, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 5.0, lineMetrics: neg, columnMetrics: h),
                       .failure(.negativeLineCount))
        // non-finite y -> .nonFiniteValue (short-circuits before x is ever looked at)
        let ok = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: .nan, lineMetrics: ok, columnMetrics: h),
                       .failure(.nonFiniteValue))
    }

    func testHorizontalFailureSurfaces() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        // valid line located, but non-finite x -> columnAt .nonFiniteValue surfaces
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: .infinity, y: 20.0, lineMetrics: v, columnMetrics: h),
                       .failure(.nonFiniteValue))
        // valid line, but negative columnCount -> .negativeColumnCount surfaces
        struct NegativeColumnMetrics: LineHorizontalMetricsSource {
            func columnCount(inLine line: Int) -> Int { -1 }
            func columnOffset(inLine line: Int, column: Int) -> Double { 0.0 }
        }
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 20.0, lineMetrics: v, columnMetrics: NegativeColumnMetrics()),
                       .failure(.negativeColumnCount))
    }

    func testFailurePrecedenceVerticalWins() {
        // Both axes would fail: lineCount < 0 AND columnCount < 0 -> vertical error.
        struct NegativeColumnMetrics: LineHorizontalMetricsSource {
            func columnCount(inLine line: Int) -> Int { -1 }
            func columnOffset(inLine line: Int, column: Int) -> Double { 0.0 }
        }
        let v = UniformLineMetrics(lineCount: -1, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 5.0, lineMetrics: v, columnMetrics: NegativeColumnMetrics()),
                       .failure(.negativeLineCount))
    }

    func testNonFiniteYBeatsEmptyDocument() {
        // Validation precedes the zero-count short-circuit: NaN y on an empty doc
        // is .failure(.nonFiniteValue), NOT .empty.
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: .nan, lineMetrics: v, columnMetrics: h),
                       .failure(.nonFiniteValue))
    }

    func testNonFiniteXBeatsBlankLine() {
        // Validation precedes the blank-line short-circuit: NaN x on a located
        // blank line is .failure(.nonFiniteValue), NOT .blankLine.
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)      // y=15 -> line 1
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0], [], [8.0]]) // line 1 blank
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: .nan, y: 15.0, lineMetrics: v, columnMetrics: h),
                       .failure(.nonFiniteValue))
    }
```

- [ ] **Step 2: Write the dispatch/non-consultation test file**

Create `Tests/TextEngineCoreTests/PointAtDispatchTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class PointAtDispatchTests: XCTestCase {
    private enum Event: Equatable {
        case columnCount(Int)               // (line)
        case columnOffset(Int, Int)         // (line, column)
        case columnIndex(Int, Double)       // (line, x)
    }

    private final class EventLog {
        var events: [Event] = []
    }

    // Records every horizontal call. Wraps a UniformColumnMetrics for real answers,
    // so a .line path produces a genuine cell while logging the inLine threading.
    private struct RecordingColumnMetrics: LineHorizontalMetricsSource {
        let base: UniformColumnMetrics
        let log: EventLog
        func columnCount(inLine line: Int) -> Int {
            log.events.append(.columnCount(line)); return base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            log.events.append(.columnOffset(line, column)); return base.columnOffset(inLine: line, column: column)
        }
        func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
            log.events.append(.columnIndex(line, x)); return base.columnIndex(containingOffset: x, inLine: line)
        }
    }

    func testHorizontalNotConsultedOnEmptyDocument() {
        let log = EventLog()
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = RecordingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0), log: log)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 5.0, lineMetrics: v, columnMetrics: h), .empty)
        XCTAssertEqual(log.events, [], "horizontal source must not be touched on the empty-document path")
    }

    func testHorizontalNotConsultedOnVerticalFailure() {
        let log = EventLog()
        let v = UniformLineMetrics(lineCount: -1, lineHeight: 16.0)   // .negativeLineCount
        let h = RecordingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0), log: log)
        XCTAssertEqual(ViewportVirtualizer.pointAt(x: 5.0, y: 5.0, lineMetrics: v, columnMetrics: h),
                       .failure(.negativeLineCount))
        XCTAssertEqual(log.events, [], "horizontal source must not be touched on the vertical-failure path")
    }

    func testHorizontalConsultedOnceWithLocatedLineIndex() {
        let log = EventLog()
        // 10 lines x 16 -> totalHeight 160; y = 88 -> line 5 (80 <= 88 < 96).
        let v = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        let h = RecordingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0), log: log)
        let result = ViewportVirtualizer.pointAt(x: 12.0, y: 88.0, lineMetrics: v, columnMetrics: h)
        guard case let .point(location) = result else { return XCTFail("expected .point, got \(result)") }
        XCTAssertEqual(location.line.lineIndex, 5)
        // Every horizontal event carries inLine == 5 (the vertically-located line).
        for event in log.events {
            switch event {
            case let .columnCount(line): XCTAssertEqual(line, 5)
            case let .columnOffset(line, _): XCTAssertEqual(line, 5)
            case let .columnIndex(line, _): XCTAssertEqual(line, 5)
            }
        }
        // The in-range path dispatches through columnIndex exactly once.
        let nativeCalls = log.events.filter { if case .columnIndex = $0 { return true } else { return false } }
        XCTAssertEqual(nativeCalls.count, 1)
    }
}
```

- [ ] **Step 3: Run to verify it fails first (dispatch file references may pass, precedence tests are the gate)**

Run: `swift test --filter PointAtDispatchTests 2>&1 | tail -20` and `swift test --filter PointAtTests 2>&1 | tail -20`
Expected: Both files **compile and pass** — the `pointAt` from Task 1 already satisfies these contracts by construction (the tests pin the contract; they should be green immediately on the Task 1 implementation). If any fail, the Task 1 implementation diverges from the spec and must be fixed, not the test.

Note: these tests assert behavior Task 1's code already produces (short-circuit ordering, inLine threading). They are added as a separate task because they guard a distinct contract a reviewer gates independently; they are not expected to require new production code.

- [ ] **Step 4: Confirm green**

Run: `swift test --filter PointAt 2>&1 | tail -20`
Expected: PASS — `PointAtTests` (11 tests) + `PointAtDispatchTests` (3 tests) all green.

- [ ] **Step 5: Commit**

```bash
git add Tests/TextEngineCoreTests/PointAtTests.swift Tests/TextEngineCoreTests/PointAtDispatchTests.swift
git commit -m "test: pin pointAt failure precedence and horizontal-dispatch contract"
```

---

### Task 3: Composition-parity oracle

**Files:**
- Test: `Tests/TextEngineCoreTests/PointAtEquivalenceTests.swift` (new)

**Interfaces:**
- Consumes: `ViewportVirtualizer.pointAt(...)`, `ViewportVirtualizer.lineAt(...)`, `ViewportVirtualizer.columnAt(...)`, all result types (Task 1).
- Produces: the load-bearing oracle proving `pointAt` **is** the 1D composition over an `(x, y)` grid including non-finite coordinates, empty-document, and blank-line sources.

- [ ] **Step 1: Write the oracle test file**

Create `Tests/TextEngineCoreTests/PointAtEquivalenceTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class PointAtEquivalenceTests: XCTestCase {
    // Hand-built non-uniform horizontal source; blank line = empty advance vector.
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let advancesPerLine: [[Double]]
        func columnCount(inLine line: Int) -> Int { advancesPerLine[line].count }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            var sum = 0.0
            for i in 0..<column { sum += advancesPerLine[line][i] }
            return sum
        }
    }

    // The oracle: derive the expected PointQuery from the two 1D queries, then
    // assert pointAt equals it. Because the expected value is *defined* as the 1D
    // composition, this proves parity directly and derives the non-finite ->
    // .failure ordering automatically (validation precedes the zero-count branch).
    private func expected<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        x: Double, y: Double, lineMetrics: V, columnMetrics: H
    ) -> PointQuery {
        switch ViewportVirtualizer.lineAt(y: y, metrics: lineMetrics) {
        case let .failure(e): return .failure(e)
        case .empty: return .empty
        case let .line(l):
            switch ViewportVirtualizer.columnAt(x: x, inLine: l.lineIndex, metrics: columnMetrics) {
            case let .failure(e): return .failure(e)
            case .empty: return .point(PointLocation(line: l, column: .blankLine))
            case let .column(c): return .point(PointLocation(line: l, column: .cell(c)))
            }
        }
    }

    private func assertParity<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics: V, columnMetrics: H, totalHeight: Double, lineWidth: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let ys: [Double] = [-1.0, 0.0, totalHeight / 3.0, totalHeight / 2.0,
                            totalHeight, totalHeight + 5.0, .nan, .infinity, -.infinity]
        let xs: [Double] = [-1.0, 0.0, lineWidth / 3.0, lineWidth / 2.0,
                            lineWidth, lineWidth + 5.0, .nan, .infinity, -.infinity]
        for y in ys {
            for x in xs {
                let got = ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics)
                let want = expected(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics)
                XCTAssertEqual(got, want, "x=\(x) y=\(y)", file: file, line: line)
            }
        }
    }

    func testParityUniformSources() {
        let v = UniformLineMetrics(lineCount: 20, lineHeight: 16.0)         // totalHeight 320
        let h = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)   // width 80
        assertParity(lineMetrics: v, columnMetrics: h, totalHeight: 320.0, lineWidth: 80.0)
    }

    func testParityNonUniformSourcesWithBlankLine() {
        // 4 lines of varied heights; line 2 is blank (empty advance vector).
        let v = ArrayColumnMetricsBackedLineMetrics(heights: [10.0, 20.0, 5.0, 30.0]) // totalHeight 65
        let h = ArrayColumnMetrics(advancesPerLine: [[10.0, 30.0, 5.0], [8.0, 8.0], [], [50.0]])
        // lineWidth here is line 0's width (30 + ... ) = 45; the sweep hits every line
        // via the y grid, so per-line widths are all exercised.
        assertParity(lineMetrics: v, columnMetrics: h, totalHeight: 65.0, lineWidth: 45.0)
    }

    func testParityEmptyDocument() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)
        // totalHeight 0; the grid still crosses non-finite y, deriving .failure vs .empty.
        assertParity(lineMetrics: v, columnMetrics: h, totalHeight: 0.0, lineWidth: 40.0)
    }

    // A simple variable-height vertical source for the non-uniform parity case,
    // using cumulative prefix sums over a heights array (no reference-provider dep).
    private struct ArrayColumnMetricsBackedLineMetrics: LineMetricsSource {
        let cumulative: [Double]
        init(heights: [Double]) {
            var sums: [Double] = [0.0]
            var running = 0.0
            for hgt in heights { running += hgt; sums.append(running) }
            cumulative = sums
        }
        var lineCount: Int { cumulative.count - 1 }
        func offset(ofLine index: Int) -> Double { cumulative[index] }
    }
}
```

- [ ] **Step 2: Run to verify it passes**

Run: `swift test --filter PointAtEquivalenceTests 2>&1 | tail -20`
Expected: PASS — all three parity tests green (the oracle is satisfied by Task 1's composition). If it fails, the divergence is a real `pointAt` bug (ordering, clamp propagation, or blank-line handling) — fix the implementation, not the oracle.

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/PointAtEquivalenceTests.swift
git commit -m "test: add pointAt composition-parity oracle"
```

---

### Task 4: Reference-provider composition test

**Files:**
- Test: `Tests/TextEngineReferenceProvidersTests/PointAtReferenceProviderTests.swift` (new)

**Interfaces:**
- Consumes: `ViewportVirtualizer.pointAt(...)` (imported from `TextEngineCore`), `PrefixSumLineMetrics(heights:)` and `PrefixSumColumnMetrics(advancesPerLine:)` (from `TextEngineReferenceProviders`).
- Produces: proof that `pointAt` composes over the shipped reference providers, exercised in the target that imports both products (never in the core test target).

- [ ] **Step 1: Write the reference-provider test file**

Create `Tests/TextEngineReferenceProvidersTests/PointAtReferenceProviderTests.swift`:

```swift
import XCTest
import TextEngineCore
import TextEngineReferenceProviders

final class PointAtReferenceProviderTests: XCTestCase {
    func testPointAtOverPrefixSumProviders() {
        // 3 lines of heights [10, 20, 30] -> tops [0, 10, 30], totalHeight 60.
        let v = PrefixSumLineMetrics(heights: [10.0, 20.0, 30.0])
        // Per-line advances: line0 [8,8,8], line1 [10,10], line2 [5,5,5,5].
        let h = PrefixSumColumnMetrics(advancesPerLine: [[8.0, 8.0, 8.0], [10.0, 10.0], [5.0, 5.0, 5.0, 5.0]])

        // y = 15 -> line 1 (10 <= 15 < 30); x = 12 -> cell 1 (10 <= 12 < 20).
        let hit = ViewportVirtualizer.pointAt(x: 12.0, y: 15.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(hit, .point(PointLocation(
            line: LineLocation(lineIndex: 1, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 1, clamp: .inRange))
        )))

        // y = 45 -> line 2 (30 <= 45 < 60); x >= width(20) -> clampedToRight at cell 3.
        let clampRight = ViewportVirtualizer.pointAt(x: 100.0, y: 45.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(clampRight, .point(PointLocation(
            line: LineLocation(lineIndex: 2, clamp: .inRange),
            column: .cell(ColumnLocation(columnIndex: 3, clamp: .clampedToRight))
        )))

        // y below the document -> clampedToTop line 0; x = 4 -> cell 0 inRange.
        let clampTop = ViewportVirtualizer.pointAt(x: 4.0, y: -5.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(clampTop, .point(PointLocation(
            line: LineLocation(lineIndex: 0, clamp: .clampedToTop),
            column: .cell(ColumnLocation(columnIndex: 0, clamp: .inRange))
        )))
    }

    func testPointAtBlankLineOverPrefixSumProviders() {
        let v = PrefixSumLineMetrics(heights: [10.0, 10.0, 10.0])       // totalHeight 30
        // line 1 is blank (empty advance vector).
        let h = PrefixSumColumnMetrics(advancesPerLine: [[8.0], [], [8.0]])
        // y = 15 -> line 1 (blank); any finite x -> .blankLine.
        let result = ViewportVirtualizer.pointAt(x: 5.0, y: 15.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .point(PointLocation(
            line: LineLocation(lineIndex: 1, clamp: .inRange),
            column: .blankLine
        )))
    }
}
```

- [ ] **Step 2: Run to verify it passes**

Run: `swift test --filter PointAtReferenceProviderTests 2>&1 | tail -20`
Expected: PASS — both tests green.

Note: confirm `PrefixSumColumnMetrics(advancesPerLine:)` accepts an empty `[]` advance vector for a blank line (it builds `prefix = [0.0]`, so `columnCount == 0`). If the initializer rejects empty vectors, use a different blank-line construction that yields `columnCount(inLine:) == 0`.

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/PointAtReferenceProviderTests.swift
git commit -m "test: exercise pointAt over prefix-sum reference providers"
```

---

### Task 5: `--point-query` benchmark mode + local gate

**Files:**
- Create: `Sources/ViewportBenchmarks/PointQueryBenchmark.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (mode enum ~line 11, outputName ~line 39, parse arm ~line 139, usage ~line 59 + ~line 72)
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift` (~line 23)
- Modify: `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift` (~line 133)

**Interfaces:**
- Consumes: `ViewportVirtualizer.pointAt(...)`, `UniformLineMetrics`, `UniformColumnMetrics`, `PrefixSumLineMetrics`, `variableHeights(lineCount:)`, `deterministicScrollOffset(sample:maxOffset:)`, `BenchmarkSummary`, `BenchmarkOperationResult`, `formatSummary`, `percentile`, `nanoseconds`.
- Produces: `runPointQueryBenchmarks(enforceGate:) -> Bool`, `BenchmarkMode.pointQuery` (`outputName == "point_query"`), `--point-query` flag (gateable via the existing denylist — no denylist edit needed).

- [ ] **Step 1: Add the `.pointQuery` mode + outputName (compile-first, wiring incomplete → build fails)**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, add `case pointQuery` to the `BenchmarkMode` enum after `case columnGeometryQuery` (line 12):

```swift
    case columnGeometryQuery
    case pointQuery
    case memoryShape
```

Add its `outputName` arm after the `.columnGeometryQuery` arm (line 39):

```swift
        case .columnGeometryQuery:
            return "column_geometry_query"
        case .pointQuery:
            return "point_query"
        case .memoryShape:
```

- [ ] **Step 2: Add the `--point-query` parse arm + usage strings**

In the same file, add a parse arm after the `--column-geometry-query` arm (after line 139):

```swift
            case "--point-query":
                if mode != .pipeline {
                    return .failure("--point-query cannot be combined with another mode")
                }
                mode = .pointQuery
```

Update the `usage` string's first line (line 59) to include `[--point-query]` after `[--column-geometry-query]`:

```
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--variable-height] [--variable-height-mutation] [--structural-mutation] [--bulk-structural-mutation] [--line-query] [--line-geometry-query] [--column-query] [--column-geometry-query] [--point-query] [--memory-shape] [--memory-observation] [--help]
```

Add a flag description line after the `--column-geometry-query` line (line 72):

```
      --point-query         Run (x,y)->(line,cell) 2D composite position-query benchmark. Combine with --gate to enforce budgets.
```

- [ ] **Step 3: Add the `.pointQuery` arm to `SyntheticBenchmarks.swift`**

In the exhaustive `switch mode` (after the `.columnGeometryQuery` arm at line 133), add:

```swift
            case .columnGeometryQuery:
                preconditionFailure("column geometry query mode uses runColumnGeometryQueryScenario")
            case .pointQuery:
                preconditionFailure("point query mode uses runPointQueryScenario")
            case .memoryShape:
```

- [ ] **Step 4: Add the `.pointQuery` arm to `BenchmarkProgram.swift`**

After the `.columnGeometryQuery` arm (line 23):

```swift
        case .columnGeometryQuery:
            return runColumnGeometryQueryBenchmarks(enforceGate: options.enforceGate)
        case .pointQuery:
            return runPointQueryBenchmarks(enforceGate: options.enforceGate)
        case .memoryShape:
```

- [ ] **Step 5: Write the benchmark file**

Create `Sources/ViewportBenchmarks/PointQueryBenchmark.swift`. Budgets are placeholders sized ≈ (`--line-query` + `--column-query`) for the matching provider, to be tightened to observed values in Step 7. The horizontal provider is `UniformColumnMetrics` in every scenario (line-agnostic, valid for every located line); only the vertical provider varies.

```swift
import TextEngineCore
import TextEngineReferenceProviders

struct PointQueryScenario {
    let name: String
    let providerName: String
    let lineCount: Int
    let useVariableHeights: Bool     // true -> PrefixSumLineMetrics, false -> UniformLineMetrics
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// Horizontal provider is UniformColumnMetrics in every scenario: line-agnostic,
// O(1) memory, valid for every located line, still O(log M) search per line.
// Only the VERTICAL provider varies (uniform native arithmetic vs prefix-sum
// O(log N) fallback). Balanced-tree vertical descent stays gated by --line-query
// and variable horizontal advances by --column-query; the point gate's unique job
// is composition overhead (sum of the two 1D queries).
private let pointColumnsPerLine = 256
private let pointColumnWidth = 8.0
private let pointLineHeight = 16.0

func pointQueryScenarios() -> [PointQueryScenario] {
    [
        PointQueryScenario(name: "uniform_100k", providerName: "uniform",
                           lineCount: 100_000, useVariableHeights: false,
                           p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        PointQueryScenario(name: "uniform_1m", providerName: "uniform",
                           lineCount: 1_000_000, useVariableHeights: false,
                           p95BudgetNanoseconds: 240_000, p99BudgetNanoseconds: 480_000),
        PointQueryScenario(name: "prefixsum_100k", providerName: "prefixsum",
                           lineCount: 100_000, useVariableHeights: true,
                           p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        PointQueryScenario(name: "prefixsum_1m", providerName: "prefixsum",
                           lineCount: 1_000_000, useVariableHeights: true,
                           p95BudgetNanoseconds: 240_000, p99BudgetNanoseconds: 480_000),
    ]
}

@inline(never)
func runPointQueryOperation<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
    x: Double, y: Double, lineMetrics: V, columnMetrics: H
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics) {
    case let .point(location):
        var checksum = location.line.lineIndex
        switch location.line.clamp {
        case .inRange: checksum &+= 1
        case .clampedToTop: checksum &+= 2
        case .clampedToBottom: checksum &+= 3
        }
        switch location.column {
        case let .cell(cell):
            checksum &+= cell.columnIndex
            switch cell.clamp {
            case .inRange: checksum &+= 10
            case .clampedToLeft: checksum &+= 20
            case .clampedToRight: checksum &+= 30
            }
        case .blankLine:
            checksum &+= 7
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runPointQueryScenarioCore<V: LineMetricsSource>(
    _ scenario: PointQueryScenario,
    lineMetrics: V,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let columnMetrics = UniformColumnMetrics(columnsPerLine: pointColumnsPerLine, columnWidth: pointColumnWidth)
    let totalHeight = lineMetrics.offset(ofLine: lineMetrics.lineCount)
    let width = Double(pointColumnsPerLine) * pointColumnWidth
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let y: Double
            let x: Double
            switch sample % 8 {
            case 0:
                y = -1.0 - Double(sample % 1_000)            // above the document
                x = deterministicScrollOffset(sample: sample, maxOffset: width)
            case 1:
                y = totalHeight + Double(sample % 1_000)     // past the document end
                x = width + Double(sample % 1_000)           // right of the line end
            case 2:
                y = deterministicScrollOffset(sample: sample, maxOffset: totalHeight)
                x = -1.0 - Double(sample % 1_000)            // left of the line
            default:
                y = deterministicScrollOffset(sample: sample, maxOffset: totalHeight)
                x = deterministicScrollOffset(sample: sample, maxOffset: width)
            }
            let result = runPointQueryOperation(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .pointQuery,
        providerName: scenario.providerName,
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: lineMetrics.lineCount,
        documentBytes: nil,
        lineBytes: nil,
        p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
        p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
        checksum: checksum,
        failureCount: failureCount,
        p95BudgetNanoseconds: scenario.p95BudgetNanoseconds,
        p99BudgetNanoseconds: scenario.p99BudgetNanoseconds
    )
}

@available(macOS 13.0, *)
func runPointQueryScenario(
    _ scenario: PointQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useVariableHeights {
        let lineMetrics = PrefixSumLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
        return runPointQueryScenarioCore(scenario, lineMetrics: lineMetrics,
                                         iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let lineMetrics = UniformLineMetrics(lineCount: scenario.lineCount, lineHeight: pointLineHeight)
        return runPointQueryScenarioCore(scenario, lineMetrics: lineMetrics,
                                         iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runPointQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in pointQueryScenarios() {
        let summary = runPointQueryScenario(
            scenario,
            iterations: iterations,
            operationsPerSample: operationsPerSample
        )
        print(formatSummary(summary, includeGate: enforceGate))

        if enforceGate && !summary.passesGate {
            passed = false
        } else if !enforceGate && summary.failureCount != 0 {
            passed = false
        }
    }

    return passed
}
```

- [ ] **Step 6: Build and run without the gate (correctness + observe latencies)**

Run: `swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

Run: `swift run -c release ViewportBenchmarks -- --point-query 2>&1 | tail -8`
Expected: four `mode=point_query` lines, `failures=0` on each; note the reported `p95=`/`p99=` values per scenario.

- [ ] **Step 7: Tighten budgets to observed values with headroom, then verify the gate passes**

Set each scenario's `p95BudgetNanoseconds` / `p99BudgetNanoseconds` in `pointQueryScenarios()` to roughly `2×`–`4×` the observed p95/p99 from Step 6 (the project's customary headroom; keep round numbers consistent with the sibling gates' 30k–480k range). Do **not** loosen below the observed value.

Run: `swift run -c release ViewportBenchmarks -- --point-query --gate 2>&1 | tail -8`
Expected: every scenario prints `gate=pass`, and the process exits `0`.

Run: `swift run -c release ViewportBenchmarks -- --range-only --point-query 2>&1 | tail -3` (sanity: two mode flags rejected)
Expected: `error=--point-query cannot be combined with another mode` (or the symmetric `--range-only` message), exit `1`.

Run: `swift run -c release ViewportBenchmarks -- --memory-shape --gate 2>&1 | tail -3` (sanity: `--gate` still rejected with a non-gateable mode — proves the denylist is intact and `--point-query` did not alter it)
Expected: `error=--gate cannot be combined with memory_shape mode`, exit `1`.

- [ ] **Step 8: Commit**

```bash
git add Sources/ViewportBenchmarks/PointQueryBenchmark.swift Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
git commit -m "feat: add --point-query benchmark mode with local gate"
```

---

### Task 6: `AGENTS.md` documentation

**Files:**
- Modify: `AGENTS.md` (architecture paragraph; Commands list; benchmark flags list)

**Interfaces:**
- Consumes: nothing (docs only).
- Produces: the durable description of `pointAt` and its local (not-yet-CI) gate.

- [ ] **Step 1: Add the `pointAt` architecture sentence**

In `AGENTS.md`, in the "Architecture in one paragraph" section, immediately after the `columnGeometryAt` sentence (the one ending "`--column-geometry-query` is its blocking host-job CI gate."), add:

```
`ViewportVirtualizer.pointAt(x:y:lineMetrics:columnMetrics:)` is the first two-axis
composite: it maps a single point to `(line, cell)` by composing `lineAt` over a
`LineMetricsSource` with `columnAt` over a `LineHorizontalMetricsSource` (vertical
runs first and feeds the located line index to the horizontal query), returning a
nested `PointQuery` — `.point(PointLocation)` carrying the located `line` plus a
`ColumnResolution` (`.cell`/`.blankLine`), `.empty` for an empty document, or
`.failure`. It adds no new search: O(log N) + O(log M) queries / O(1) core memory,
both clamp flags preserved. Its `--point-query --gate` is **local (not-yet-CI)**.
```

- [ ] **Step 2: Add the `--point-query` local command to the Commands list**

In the ```bash Commands block, after the `--column-geometry-query --gate` line, add:

```bash
swift run -c release ViewportBenchmarks -- --point-query --gate   # (x,y)->(line,cell) 2D composite local gate
```

- [ ] **Step 3: Add `--point-query` to the benchmark-flags prose list**

In the "Benchmark flags:" paragraph, add `--point-query` to the enumerated list (after `--column-geometry-query`), and add it to the sentence listing which modes `--gate` is valid with (after `--column-geometry-query`). Leave the `--gate`-rejected list (`--range-only`, `--memory-shape`, `--memory-observation`) unchanged.

- [ ] **Step 4: Verify the Foundation scan and commit**

Run: `rg -n "Foundation" Sources/TextEngineCore; echo "exit=$?"`
Expected: no matches, `exit=1`.

```bash
git add AGENTS.md
git commit -m "docs: describe pointAt 2D composite and its local point-query gate"
```

---

### Task 7: Full-suite verification + verification record

**Files:**
- Create: `docs/superpowers/verification/2026-07-10-point-query.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the recorded evidence for the slice paper trail (local proof; hosted run IDs filled in the post-merge follow-up per the standing stale-on-write lesson).

- [ ] **Step 1: Run the full local verification suite and capture outputs**

Run each and capture the output:

```bash
swift test 2>&1 | tail -5
swift build -c release 2>&1 | tail -2
swift run -c release ViewportBenchmarks -- --point-query --gate 2>&1 | tail -6
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tail -4
swift run -c release ViewportBenchmarks -- --variable-height --gate 2>&1 | tail -4
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate 2>&1 | tail -4
swift run -c release ViewportBenchmarks -- --structural-mutation --gate 2>&1 | tail -4
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate 2>&1 | tail -4
swift run -c release ViewportBenchmarks -- --line-query --gate 2>&1 | tail -6
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate 2>&1 | tail -6
swift run -c release ViewportBenchmarks -- --column-query --gate 2>&1 | tail -6
swift run -c release ViewportBenchmarks -- --column-geometry-query --gate 2>&1 | tail -6
swift run -c release ViewportBenchmarks -- --memory-shape 2>&1 | tail -4
rg -n "Foundation" Sources/TextEngineCore; echo "core exit=$?"
rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "refprov exit=$?"
./.github/scripts/cross-target-compile.sh --self-test 2>&1 | tail -5
```

Expected: `swift test` reports the prior total **+19** new tests — 17 in the core target (`PointAtTests` 11 + `PointAtDispatchTests` 3 + `PointAtEquivalenceTests` 3) and 2 in the reference-providers target (`PointAtReferenceProviderTests` 2); confirm the exact delta — 0 failures. Every existing gate `gate=pass` with **checksums identical** to their pre-slice values (record them). `--memory-shape` `invariant=pass`. Both Foundation scans `exit=1`. Cross-target self-test passes.

- [ ] **Step 2: Confirm existing-gate checksums are byte-identical**

Compare each existing gate's per-scenario `checksum=` values against the Slice 36 verification record (`docs/superpowers/verification/2026-07-10-column-geometry-query-ci-gate-promotion.md`). Any difference means this slice accidentally touched a shared path — investigate before proceeding. Expected: all identical (this slice is strictly additive).

- [ ] **Step 3: Write the verification record**

Create `docs/superpowers/verification/2026-07-10-point-query.md` capturing: the exact commands above with their real outputs; the new test count delta; the `--point-query` per-scenario p95/p99 + checksums; confirmation that all nine existing gates are checksum-identical; the Foundation scans; the cross-target self-test result; and a `## Hosted Proof — Pending` placeholder section (the real PR-head + post-merge push run IDs are filled in the post-merge follow-up against the stable final head, never against a pre-final commit).

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/verification/2026-07-10-point-query.md
git commit -m "docs: record 2D point-query local verification"
```

---

## Self-Review

**1. Spec coverage:**
- Public `pointAt(x:y:lineMetrics:columnMetrics:)` over both sources → Task 1. ✓
- Nested `PointQuery` / `PointLocation` / `ColumnResolution` with `.cell`/`.blankLine` → Task 1 (types) + Task 4 edit note (point-level rename honored). ✓
- Parity by construction (oracle) → Task 3. ✓
- Failure precedence, vertical short-circuit, horizontal-failure-discards-line → Task 2. ✓
- Validation precedes zero-count short-circuit (non-finite beats `.empty`/`.blankLine`) → Task 2 (`testNonFiniteYBeatsEmptyDocument`, `testNonFiniteXBeatsBlankLine`) + Task 3 (grid includes non-finite). ✓
- Both-axes-clamped, no special case → Task 1 (`testBothAxesClampedRecordsBothFlags`). ✓
- `ViewportValidationError` unchanged → Global Constraints + no task edits it. ✓
- Dispatch / non-consultation with ordered events + inLine threading → Task 2 (`PointAtDispatchTests`). ✓
- Reference-provider composition test in the right target → Task 4. ✓
- `--point-query` mode + local gate, gateable via denylist (no denylist edit) → Task 5 (incl. `--gate`-still-rejected sanity check). ✓
- Horizontal provider is line-agnostic `UniformColumnMetrics` in all point scenarios; vary only vertical → Task 5. ✓
- AGENTS.md architecture sentence + flags + command → Task 6. ✓
- Strictly additive; existing gates checksum-identical → Task 7 (Step 2). ✓
- Foundation-free, memory-shape, cross-target → Task 7 (Step 1). ✓
- Verification record with Pending hosted proof → Task 7. ✓
- No CI workflow change (deferred) → not a task; Global Constraints + spec Non-Goal. ✓

**2. Placeholder scan:** No "TBD/TODO/handle edge cases" — every step shows complete code or an exact command. Budgets in Task 5 are explicit numbers tightened against observed values in Step 7 (not a placeholder — a calibrated procedure, matching how every prior functional gate set budgets).

**3. Type consistency:** `pointAt(x:y:lineMetrics:columnMetrics:)`, `PointQuery.point/empty/failure`, `PointLocation(line:column:)`, `ColumnResolution.cell/.blankLine`, `BenchmarkMode.pointQuery`, `runPointQueryBenchmarks(enforceGate:)`, `runPointQueryScenario`, `PointQueryScenario` — used identically across Tasks 1–7. `LineLocation(lineIndex:clamp:)` / `ColumnLocation(columnIndex:clamp:)` match the existing types read from `ViewportTypes.swift`. ✓
