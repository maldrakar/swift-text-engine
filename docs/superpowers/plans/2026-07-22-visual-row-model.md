# Visual-Row Model + Row-Packing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the soft-wrap arc's node 1 — a `WrapMetricsSource` provider contract and greedy per-logical-line row-packing that streams `VisualRow`s from `ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:)`, with a per-line infinite-width equivalence oracle.

**Architecture:** `WrapMetricsSource` refines `LineHorizontalMetricsSource` with one `canBreak(beforeColumn:inLine:)` predicate. A generic streaming `VisualRowCursor<Metrics>` greedily packs one logical line into visual rows in visual order (largest legal break-end that fits the width; unbreakable runs overflow). The stateless `visualRows` factory validates the width and the same O(1) metrics ladder as `columnAt`, then hands back the cursor wrapped in a generic `VisualRowQuery<Metrics>`. This is per-line packing only; cross-line aggregation is a later node.

**Tech Stack:** Swift 6.0 tools / 6.2.1 toolchain, XCTest, no third-party dependencies, no Foundation in the core.

**Spec:** `docs/superpowers/specs/2026-07-22-visual-row-model-design.md` — read it before starting. Decisions 1–8 and the acceptance criteria are the source of truth.

## Global Constraints

Every task's requirements implicitly include these (copied from the spec / `AGENTS.md`):

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty. New public API must not expose Foundation types.
- **Swift Embedded compatible.** Only APIs that survive Embedded Swift. The generic-cursor-holding-metrics shape is proven safe by `VariableLineGeometryCursor<Metrics>` (already compiles iOS + WASM + embedded WASM).
- **Zero-dependency.** No third-party packages.
- **Compiles for iOS and WASM with no source changes.** Both are blocking in CI.
- **Core-owned memory must not grow linearly with document size.** The cursor is O(1) state; per-line packing allocates nothing document-sized.
- **XCTest only** in `Tests/TextEngineCoreTests`. `swift test` also prints "0 tests in 0 suites" for the empty Swift Testing harness — not a failure.
- **TDD, one logical step per commit**, conventional-commit prefixes (`feat:`, `test:`, `docs:`).

## File Structure

- **Create** `Sources/TextEngineCore/WrapMetricsSource.swift` — the `WrapMetricsSource` protocol (Task 1).
- **Modify** `Sources/TextEngineCore/ViewportTypes.swift` — add `VisualRow`, `VisualRowQuery<Metrics>`, and `ViewportValidationError.nonPositiveWrapWidth` (Task 2).
- **Create** `Sources/TextEngineCore/VisualRowCursor.swift` — `VisualRowCursor<Metrics>` + the `ViewportVirtualizer.visualRows` factory (Tasks 2–4).
- **Create** `Tests/TextEngineCoreTests/TestWrapMetrics.swift` — test-only conformer (Task 1).
- **Create** `Tests/TextEngineCoreTests/WrapMetricsSourceTests.swift` — driver/contract sanity (Task 1).
- **Create** `Tests/TextEngineCoreTests/WrapTestSupport.swift` — `collectRows` cursor-draining helper (Task 2, once `VisualRowQuery` exists).
- **Create** `Tests/TextEngineCoreTests/VisualRowEquivalenceTests.swift` — blank, single-cell, ∞-equivalence oracle (Task 2).
- **Create** `Tests/TextEngineCoreTests/WrapPackingTests.swift` — greedy multi-row, break-at-opportunities, overflow, char-wrap, partition (Task 3).
- **Create** `Tests/TextEngineCoreTests/WrapValidationTests.swift` — the validation ladder (Task 4). *(The spec groups validation under `WrapPackingTests`; a separate file keeps each task's deliverable a self-contained new file for subagent review — a trivial, XCTest-agnostic refinement.)*
- **Modify** `AGENTS.md` — architecture-paragraph wrap-layer addition (Task 5).
- **Create** `docs/superpowers/verification/2026-07-22-visual-row-model.md` — verification record (Task 5).

---

### Task 1: `WrapMetricsSource` contract + test driver

**Files:**
- Create: `Sources/TextEngineCore/WrapMetricsSource.swift`
- Create: `Tests/TextEngineCoreTests/TestWrapMetrics.swift`
- Test: `Tests/TextEngineCoreTests/WrapMetricsSourceTests.swift`

**Interfaces:**
- Consumes: `LineHorizontalMetricsSource` (existing — `columnCount(inLine:)`, `columnOffset(inLine:column:)`).
- Produces:
  - `protocol WrapMetricsSource: LineHorizontalMetricsSource { func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool }`
  - `struct TestWrapMetrics: WrapMetricsSource` with `init(offsets: [Double], breakColumns: Set<Int> = [])` and `init(advances: [Double], breakColumns: Set<Int> = [])`. Struct only — no `VisualRow*` references, so Task 1 compiles and passes standalone. The `collectRows` cursor helper lands in Task 2, when `VisualRowQuery` exists.

- [ ] **Step 1: Write the protocol**

Create `Sources/TextEngineCore/WrapMetricsSource.swift`:

```swift
/// Provider contract for soft-wrap: the horizontal cell advances (inherited from
/// `LineHorizontalMetricsSource`) plus the line's break opportunities. The core
/// packs advances into visual rows; it owns no Unicode tables, shaping, or font
/// knowledge — the density of break opportunities is entirely the provider's call
/// (word-wrap ⇒ breaks only after spaces; char-wrap ⇒ breaks at every boundary).
public protocol WrapMetricsSource: LineHorizontalMetricsSource {
    /// Is a soft-break legal immediately before `column` (i.e. after cell
    /// `column - 1`)? Interior boundaries are `1..<columnCount(inLine:)`. The core
    /// additionally treats `columnCount(inLine:)` (the line end) as an implicit
    /// legal end and never queries `canBreak` at `0` or at `columnCount`.
    ///
    /// No default: this is the one thing a wrap provider must supply beyond the
    /// inherited horizontal metrics.
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool
}
```

- [ ] **Step 2: Write the test driver**

Create `Tests/TextEngineCoreTests/TestWrapMetrics.swift`:

```swift
import TextEngineCore

/// Test-only `WrapMetricsSource` for a single line. `offsets` is that line's
/// cumulative column offsets (`offsets[0]` should be 0 for a valid line);
/// `columnCount == offsets.count - 1`, so `[]` yields -1 (drives
/// `.negativeColumnCount`) and `[0.0]` a blank line. `breakColumns` are the
/// interior columns (`1..<count`) where a break is legal. The `line` argument is
/// ignored — node-1 packing tests exercise one line at a time.
struct TestWrapMetrics: WrapMetricsSource {
    let offsets: [Double]
    let breakColumns: Set<Int>

    /// Build directly from cumulative offsets — use for validation edge cases:
    /// `[]` → count -1, `[0.0]` → blank, `[5.0]` → blank with bad offset0,
    /// `[0.0, 0.0]` → zero total, `[0.0, .infinity]` → non-finite total.
    init(offsets: [Double], breakColumns: Set<Int> = []) {
        self.offsets = offsets
        self.breakColumns = breakColumns
    }

    /// Convenience: build from per-cell advances (all positive). `offsets` become
    /// the prefix sums `[0, a0, a0+a1, …]`.
    init(advances: [Double], breakColumns: Set<Int> = []) {
        var sums: [Double] = [0.0]
        sums.reserveCapacity(advances.count + 1)
        var running = 0.0
        for a in advances {
            running += a
            sums.append(running)
        }
        self.init(offsets: sums, breakColumns: breakColumns)
    }

    func columnCount(inLine line: Int) -> Int { offsets.count - 1 }
    func columnOffset(inLine line: Int, column: Int) -> Double { offsets[column] }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
        breakColumns.contains(column)
    }
}
```

- [ ] **Step 3: Write the failing contract test**

Create `Tests/TextEngineCoreTests/WrapMetricsSourceTests.swift`:

```swift
import XCTest
import TextEngineCore

final class WrapMetricsSourceTests: XCTestCase {
    func testDriverCumulativeOffsetsAndBreaks() {
        let metrics = TestWrapMetrics(advances: [10.0, 30.0, 5.0], breakColumns: [1])
        XCTAssertEqual(metrics.columnCount(inLine: 0), 3)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 0), 0.0)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 1), 10.0)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 3), 45.0)
        XCTAssertTrue(metrics.canBreak(beforeColumn: 1, inLine: 0))
        XCTAssertFalse(metrics.canBreak(beforeColumn: 2, inLine: 0))
    }

    func testOffsetsInitExpressesMalformedCounts() {
        XCTAssertEqual(TestWrapMetrics(offsets: []).columnCount(inLine: 0), -1)
        XCTAssertEqual(TestWrapMetrics(offsets: [0.0]).columnCount(inLine: 0), 0)
    }

    // A WrapMetricsSource IS a LineHorizontalMetricsSource — usable wherever the
    // inherited contract is expected (pins the refinement).
    func testRefinesLineHorizontalMetricsSource() {
        let metrics: LineHorizontalMetricsSource = TestWrapMetrics(advances: [8.0, 8.0])
        XCTAssertEqual(metrics.columnCount(inLine: 0), 2)
        XCTAssertEqual(metrics.columnOffset(inLine: 0, column: 2), 16.0)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter WrapMetricsSourceTests`
Expected: **PASS** (3 tests). Task 1 is self-contained — the protocol + driver compile and the driver behaves. (A true red-first cycle isn't meaningful for a pure protocol + test-double contract; the sanity tests still fail before `WrapMetricsSource.swift` exists — run them once with the source deleted if you want to see the compile red.)

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/WrapMetricsSource.swift \
        Tests/TextEngineCoreTests/TestWrapMetrics.swift \
        Tests/TextEngineCoreTests/WrapMetricsSourceTests.swift
git commit -m "feat: add WrapMetricsSource contract + test driver (wrap node 1)"
```

---

### Task 2: `VisualRow` model, streaming cursor, and the `visualRows` entry (blank + ∞-equivalence)

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (add `VisualRow`, `VisualRowQuery`, error case)
- Create: `Sources/TextEngineCore/VisualRowCursor.swift`
- Test: `Tests/TextEngineCoreTests/WrapTestSupport.swift` (`collectRows` helper — shared with Task 3)
- Test: `Tests/TextEngineCoreTests/VisualRowEquivalenceTests.swift`

**Interfaces:**
- Consumes: `WrapMetricsSource`, `TestWrapMetrics` (Task 1); `ViewportVirtualizer` enum, `ViewportValidationError` (existing).
- Produces:
  - `func collectRows<M: WrapMetricsSource>(_ query: VisualRowQuery<M>, file:line:) -> [VisualRow]` — drains a query's cursor; used by Tasks 2–3.
  - `struct VisualRow: Equatable` with `init(logicalLine:rowInLine:startColumn:endColumn:width:)`.
  - `enum VisualRowQuery<Metrics: WrapMetricsSource> { case rows(VisualRowCursor<Metrics>); case failure(ViewportValidationError) }`.
  - `struct VisualRowCursor<Metrics: WrapMetricsSource> { public mutating func next() -> VisualRow? }` (internal init).
  - `ViewportVirtualizer.visualRows<Metrics: WrapMetricsSource>(inLine:wrapWidth:metrics:) -> VisualRowQuery<Metrics>`.
  - `ViewportValidationError.nonPositiveWrapWidth`.
  - **Task-2 behaviour:** blank line → one `[0,0)` row; any `count > 0` → one whole-line row `[0, count)` (a deliberate stub Task 3 replaces with greedy breaking); **no** validation yet (Task 4 adds it).

- [ ] **Step 1: Add the value type and error case**

In `Sources/TextEngineCore/ViewportTypes.swift`, add `nonPositiveWrapWidth` to `ViewportValidationError` (it is an `enum` around line 67):

```swift
public enum ViewportValidationError: Equatable {
    case negativeLineCount
    case nonFiniteValue
    case nonPositiveLineHeight
    case negativeViewportHeight
    case negativeOverscan
    case invalidLineMetrics
    case negativeColumnCount
    case invalidColumnMetrics
    case nonPositiveWrapWidth
}
```

Then add `VisualRow` and `VisualRowQuery` beside the other geometry/query types (e.g. after `ColumnGeometryLocation`):

```swift
/// One visual row of a soft-wrapped logical line: a half-open cell span
/// `[startColumn, endColumn)` with its advance-sum width, in visual order.
/// Horizontal only — vertical stacking (y/height) is a later node.
public struct VisualRow: Equatable {
    public let logicalLine: Int   // the logical line this row belongs to
    public let rowInLine: Int     // 0-based index of this row within logicalLine
    public let startColumn: Int   // inclusive
    public let endColumn: Int     // exclusive — half-open [startColumn, endColumn)
    public let width: Double      // columnOffset(endColumn) − columnOffset(startColumn)

    public init(logicalLine: Int, rowInLine: Int, startColumn: Int, endColumn: Int, width: Double) {
        self.logicalLine = logicalLine
        self.rowInLine = rowInLine
        self.startColumn = startColumn
        self.endColumn = endColumn
        self.width = width
    }
}

/// Result of `ViewportVirtualizer.visualRows`. Generic — its `.rows` payload is the
/// provider-holding `VisualRowCursor<Metrics>`, so this is the project's first
/// generic query enum. NOT `Equatable` (the cursor is mutable, non-`Equatable`);
/// tests pattern-match and compare the drained `[VisualRow]`.
public enum VisualRowQuery<Metrics: WrapMetricsSource> {
    case rows(VisualRowCursor<Metrics>)      // one or more rows (a blank line ⇒ one)
    case failure(ViewportValidationError)    // invalid wrapWidth or malformed metrics
}
```

- [ ] **Step 2: Write the `collectRows` helper, then the failing tests**

Create `Tests/TextEngineCoreTests/WrapTestSupport.swift`:

```swift
import XCTest
import TextEngineCore

/// Drain a `VisualRowQuery`'s cursor into an array, failing the test if it is
/// `.failure`. Shared by every packing/equivalence test.
func collectRows<M: WrapMetricsSource>(
    _ query: VisualRowQuery<M>,
    file: StaticString = #filePath,
    line: UInt = #line
) -> [VisualRow] {
    guard case .rows(var cursor) = query else {
        XCTFail("expected .rows, got .failure", file: file, line: line)
        return []
    }
    var rows: [VisualRow] = []
    while let row = cursor.next() {
        rows.append(row)
    }
    return rows
}
```

Then create `Tests/TextEngineCoreTests/VisualRowEquivalenceTests.swift`:

```swift
import XCTest
import TextEngineCore

final class VisualRowEquivalenceTests: XCTestCase {
    // A blank logical line is exactly one empty visual row, then nil.
    func testBlankLineIsOneEmptyRow() {
        let metrics = TestWrapMetrics(offsets: [0.0]) // columnCount 0
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics))
        XCTAssertEqual(rows, [VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 0, width: 0.0)])
    }

    func testSingleCellLineIsOneRow() {
        let metrics = TestWrapMetrics(advances: [8.0])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics))
        XCTAssertEqual(rows, [VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 1, width: 8.0)])
    }

    // The marquee guarantee: irregular advances + irregular breaks; at any width
    // ≥ the line's total advance (+∞ included), packing yields exactly one row
    // [0, count) whose width is the total — the no-wrap column model read off the
    // same source. The `.infinity` case is also the F1 regression test (a
    // `wrapWidth.isFinite` guard would wrongly reject it).
    func testWidthAtOrAboveTotalYieldsOneRowEqualToNoWrap() {
        let advances = [12.0, 3.0, 40.0, 7.0, 25.0]      // total 87
        let metrics = TestWrapMetrics(advances: advances, breakColumns: [1, 3])
        let total = metrics.columnOffset(inLine: 0, column: advances.count)
        for width in [total, total + 0.5, Double.infinity] {
            let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: width, metrics: metrics))
            XCTAssertEqual(
                rows,
                [VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 5, width: 87.0)],
                "width=\(width)"
            )
        }
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter VisualRowEquivalenceTests`
Expected: **FAIL** to compile — `VisualRowCursor` and `ViewportVirtualizer.visualRows` do not exist yet.

- [ ] **Step 4: Write the cursor + factory (blank + whole-line stub)**

Create `Sources/TextEngineCore/VisualRowCursor.swift`:

```swift
/// Streams the visual rows of one logical line at a wrap width, in visual order.
/// Holds the provider so `next()` reads `columnOffset`/`canBreak` lazily — hence
/// generic, exactly like `VariableLineGeometryCursor<Metrics>`. O(1) state.
/// Construct via `ViewportVirtualizer.visualRows` (internal init); the width and
/// metrics are already validated there.
public struct VisualRowCursor<Metrics: WrapMetricsSource> {
    private let metrics: Metrics
    private let line: Int
    private let columnCount: Int
    private let wrapWidth: Double
    private var nextStartColumn: Int
    private var nextRowInLine: Int
    private var finished: Bool

    init(line: Int, columnCount: Int, wrapWidth: Double, metrics: Metrics) {
        self.metrics = metrics
        self.line = line
        self.columnCount = columnCount
        self.wrapWidth = wrapWidth
        self.nextStartColumn = 0
        self.nextRowInLine = 0
        self.finished = false
    }

    public mutating func next() -> VisualRow? {
        if finished { return nil }

        // Blank line: exactly one empty row.
        if columnCount == 0 {
            finished = true
            return VisualRow(logicalLine: line, rowInLine: 0, startColumn: 0, endColumn: 0, width: 0.0)
        }

        let start = nextStartColumn
        let startOffset = metrics.columnOffset(inLine: line, column: start)
        let end = columnCount   // Task 3 replaces with: greedyEnd(from: start, startOffset: startOffset)

        let row = VisualRow(
            logicalLine: line,
            rowInLine: nextRowInLine,
            startColumn: start,
            endColumn: end,
            width: metrics.columnOffset(inLine: line, column: end) - startOffset
        )
        nextStartColumn = end
        nextRowInLine += 1
        if end == columnCount { finished = true }
        return row
    }
}

extension ViewportVirtualizer {
    /// Streams the visual rows of logical line `inLine` packed to `wrapWidth`, in
    /// visual order. Stateless; the cursor is lazy (no packing happens here).
    /// `inLine` is a precondition (the source carries no `lineCount`), exactly like
    /// `columnAt`. Task 4 adds the width + metrics validation ladder.
    public static func visualRows<Metrics: WrapMetricsSource>(
        inLine line: Int,
        wrapWidth: Double,
        metrics: Metrics
    ) -> VisualRowQuery<Metrics> {
        let count = metrics.columnCount(inLine: line)
        return .rows(VisualRowCursor(line: line, columnCount: count, wrapWidth: wrapWidth, metrics: metrics))
    }
}
```

- [ ] **Step 5: Run to verify the tests pass (and the whole suite compiles)**

Run: `swift test --filter VisualRowEquivalenceTests`
Expected: **PASS** (3 tests).
Then run the full suite to confirm Task 1's `WrapMetricsSourceTests` and everything else now compile and pass:
Run: `swift test`
Expected: **PASS** — all existing tests + the new ones; "0 tests in 0 suites" line for the Swift Testing harness is normal.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextEngineCore/ViewportTypes.swift \
        Sources/TextEngineCore/VisualRowCursor.swift \
        Tests/TextEngineCoreTests/WrapTestSupport.swift \
        Tests/TextEngineCoreTests/VisualRowEquivalenceTests.swift
git commit -m "feat: add VisualRow model + streaming cursor + visualRows (blank/equivalence)"
```

---

### Task 3: Greedy multi-row packing + overflow

**Files:**
- Modify: `Sources/TextEngineCore/VisualRowCursor.swift` (replace the whole-line stub with the greedy walk)
- Test: `Tests/TextEngineCoreTests/WrapPackingTests.swift`

**Interfaces:**
- Consumes: everything from Task 2.
- Produces: real greedy packing — a row from `start` ends at the largest legal end that fits `wrapWidth`, or (if none fits) the smallest legal end (forced overflow, row wider than `wrapWidth`). Legal interior ends are columns `c` with `canBreak(beforeColumn: c)`; `columnCount` is always legal. Rows tile `[0, count)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TextEngineCoreTests/WrapPackingTests.swift`:

```swift
import XCTest
import TextEngineCore

final class WrapPackingTests: XCTestCase {
    // advances [10,10,10,10] (total 40), break before every column, width 25.
    // Row0 [0,2) (offset 20 ≤ 25; 30 > 25); Row1 [2,4) (20 ≤ 25).
    func testGreedyBreaksAtLastFittingOpportunity() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0, 10.0], breakColumns: [1, 2, 3])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 25.0, metrics: metrics))
        XCTAssertEqual(rows, [
            VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 2, width: 20.0),
            VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 2, endColumn: 4, width: 20.0),
        ])
    }

    // Only column 2 is breakable. width 25. The core may end a row only at 2 or 4,
    // never at 1 or 3, even though cells would otherwise fit.
    func testBreakOnlyAtDeclaredOpportunities() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0, 10.0], breakColumns: [2])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 25.0, metrics: metrics))
        XCTAssertEqual(rows, [
            VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 2, width: 20.0),
            VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 2, endColumn: 4, width: 20.0),
        ])
    }

    // No interior breaks; width 5 < total 40. One overflowing row wider than width.
    func testUnbreakableRunOverflowsOneRow() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0, 10.0], breakColumns: [])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 5.0, metrics: metrics))
        XCTAssertEqual(rows, [VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 4, width: 40.0)])
    }

    // Break before every column; width 5 < each advance 10 ⇒ one cell per row.
    func testCharWrapOneCellPerRow() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0], breakColumns: [1, 2])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 5.0, metrics: metrics))
        XCTAssertEqual(rows, [
            VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 1, width: 10.0),
            VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 1, endColumn: 2, width: 10.0),
            VisualRow(logicalLine: 0, rowInLine: 2, startColumn: 2, endColumn: 3, width: 10.0),
        ])
    }

    // Property: rows are contiguous, cover [0, count), non-empty, rowInLine 0-based
    // monotone, logicalLine constant — for an irregular line.
    func testPartitionTilesTheLine() {
        let advances = [7.0, 13.0, 5.0, 21.0, 9.0, 4.0] // offsets [0,7,20,25,46,55,59]
        let metrics = TestWrapMetrics(advances: advances, breakColumns: [1, 2, 3, 4, 5])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 20.0, metrics: metrics))
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(rows.first?.startColumn, 0)
        XCTAssertEqual(rows.last?.endColumn, advances.count)
        for (i, row) in rows.enumerated() {
            XCTAssertEqual(row.rowInLine, i, "rowInLine at \(i)")
            XCTAssertEqual(row.logicalLine, 0)
            XCTAssertLessThan(row.startColumn, row.endColumn, "non-empty row \(i)")
            if i > 0 { XCTAssertEqual(row.startColumn, rows[i - 1].endColumn, "contiguous at \(i)") }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter WrapPackingTests`
Expected: **FAIL** — the Task-2 stub returns one whole-line row regardless of width, so every multi-row / overflow / char-wrap assertion mismatches (e.g. `testGreedyBreaksAtLastFittingOpportunity` gets one `[0,4)` row).

- [ ] **Step 3: Replace the stub with the greedy walk**

In `Sources/TextEngineCore/VisualRowCursor.swift`, change the one stub line in `next()`:

```swift
        let end = greedyEnd(from: start, startOffset: startOffset)
```

and add this private method to `VisualRowCursor` (e.g. after `next()`):

```swift
    // The largest legal end `e > start` with `columnOffset(e) - startOffset <=
    // wrapWidth`; if none fits, the smallest legal end `e > start` (forced overflow
    // — a row wider than wrapWidth). `columnCount` is always a legal end; interior
    // legal ends are columns `c` with `canBreak(beforeColumn: c)`. Relies on the
    // monotone `columnOffset` precondition: once a legal end overflows, every later
    // one does too, so the walk stops there. O(cells in the row).
    private func greedyEnd(from start: Int, startOffset: Double) -> Int {
        var lastFitting = -1   // largest legal end seen that fits
        var firstLegal = -1    // smallest legal end > start (overflow fallback)
        var c = start + 1
        while c <= columnCount {
            let isLegal = (c == columnCount) || metrics.canBreak(beforeColumn: c, inLine: line)
            if isLegal {
                if firstLegal == -1 { firstLegal = c }
                if metrics.columnOffset(inLine: line, column: c) - startOffset <= wrapWidth {
                    lastFitting = c
                } else {
                    break
                }
            }
            c += 1
        }
        return lastFitting != -1 ? lastFitting : firstLegal
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter WrapPackingTests`
Expected: **PASS** (5 tests).
Run: `swift test --filter VisualRowEquivalenceTests`
Expected: **PASS** — the equivalence oracle still holds under real greedy (at width ≥ total, `greedyEnd` returns `columnCount`).

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/VisualRowCursor.swift \
        Tests/TextEngineCoreTests/WrapPackingTests.swift
git commit -m "feat: greedy multi-row row-packing + overflow (wrap node 1)"
```

---

### Task 4: Validation ladder on `visualRows` (parity with `columnAt`)

**Files:**
- Modify: `Sources/TextEngineCore/VisualRowCursor.swift` (add the ladder to `visualRows`)
- Test: `Tests/TextEngineCoreTests/WrapValidationTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–3.
- Produces: `visualRows` runs `columnAt`'s O(1) ladder in its fixed order — `count < 0 → .negativeColumnCount`; `!(wrapWidth > 0) → .nonPositiveWrapWidth`; `columnOffset(0) != 0 → .invalidColumnMetrics` (before the blank short-circuit); for `count > 0`, non-finite/`≤ 0` line total `→ .invalidColumnMetrics` — then `.rows`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TextEngineCoreTests/WrapValidationTests.swift`:

```swift
import XCTest
import TextEngineCore

final class WrapValidationTests: XCTestCase {
    private func failure<M: WrapMetricsSource>(_ query: VisualRowQuery<M>) -> ViewportValidationError? {
        if case .failure(let error) = query { return error }
        return nil
    }

    func testNegativeColumnCountFails() {
        let metrics = TestWrapMetrics(offsets: []) // columnCount -1
        XCTAssertEqual(
            failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 10.0, metrics: metrics)),
            .negativeColumnCount
        )
    }

    func testNonPositiveOrNonFiniteWidthFails() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0])
        for width in [0.0, -1.0, -Double.infinity, Double.nan] {
            XCTAssertEqual(
                failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: width, metrics: metrics)),
                .nonPositiveWrapWidth,
                "width=\(width)"
            )
        }
    }

    func testInfiniteWidthDoesNotFail() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0])
        guard case .rows = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: .infinity, metrics: metrics) else {
            return XCTFail("expected .rows for +infinity")
        }
    }

    func testFirstOffsetNonZeroFails() {
        let metrics = TestWrapMetrics(offsets: [5.0, 15.0]) // columnOffset(0) == 5
        XCTAssertEqual(
            failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics)),
            .invalidColumnMetrics
        )
    }

    func testZeroOrNonFiniteLineTotalFails() {
        for offsets in [[0.0, 0.0], [0.0, Double.infinity]] {
            let metrics = TestWrapMetrics(offsets: offsets)
            XCTAssertEqual(
                failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics)),
                .invalidColumnMetrics,
                "offsets=\(offsets)"
            )
        }
    }

    // Ordering: both count<0 AND width≤0 ⇒ count is checked first.
    func testLadderChecksCountBeforeWidth() {
        let metrics = TestWrapMetrics(offsets: []) // columnCount -1
        XCTAssertEqual(
            failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 0.0, metrics: metrics)),
            .negativeColumnCount
        )
    }

    // A blank line whose columnOffset(0) != 0 must fail with .invalidColumnMetrics,
    // NOT short-circuit to a blank row — pins "probe before blank short-circuit".
    func testBlankLineWithBadFirstOffsetFailsBeforeShortCircuit() {
        let metrics = TestWrapMetrics(offsets: [5.0]) // columnCount 0, columnOffset(0) == 5
        XCTAssertEqual(
            failure(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics)),
            .invalidColumnMetrics
        )
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter WrapValidationTests`
Expected: **FAIL** — `visualRows` currently does no validation, so it returns `.rows` (not `.failure`) for the malformed inputs, and `testNegativeColumnCountFails` even traps in the cursor's greedy walk over a `-1` count. Assertions fail / the run aborts on the trap.

- [ ] **Step 3: Add the validation ladder**

In `Sources/TextEngineCore/VisualRowCursor.swift`, replace the body of `visualRows` with the full ladder (Decision 5 order — mirrors `HorizontalPositionQuery.swift`'s "Do not reorder"):

```swift
    public static func visualRows<Metrics: WrapMetricsSource>(
        inLine line: Int,
        wrapWidth: Double,
        metrics: Metrics
    ) -> VisualRowQuery<Metrics> {
        let count = metrics.columnCount(inLine: line)
        if count < 0 {
            return .failure(.negativeColumnCount)
        }
        // `wrapWidth > 0` accepts +∞ (the equivalence case) and rejects NaN, −∞, ≤ 0.
        // Do NOT write `wrapWidth.isFinite && wrapWidth > 0`: +∞ is not finite.
        if !(wrapWidth > 0) {
            return .failure(.nonPositiveWrapWidth)
        }
        // O(1) contract probe, before the blank short-circuit, for parity with columnAt.
        if metrics.columnOffset(inLine: line, column: 0) != 0.0 {
            return .failure(.invalidColumnMetrics)
        }
        if count > 0 {
            let total = metrics.columnOffset(inLine: line, column: count)
            if !total.isFinite || total <= 0.0 {
                return .failure(.invalidColumnMetrics)
            }
        }
        return .rows(VisualRowCursor(line: line, columnCount: count, wrapWidth: wrapWidth, metrics: metrics))
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter WrapValidationTests`
Expected: **PASS** (7 tests).
Run: `swift test`
Expected: **PASS** — full suite green (packing + equivalence + validation + all existing tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/VisualRowCursor.swift \
        Tests/TextEngineCoreTests/WrapValidationTests.swift
git commit -m "feat: visualRows width + metrics validation ladder (columnAt parity)"
```

---

### Task 5: Docs + full verification

**Files:**
- Modify: `AGENTS.md` (architecture paragraph — wrap layer)
- Create: `docs/superpowers/verification/2026-07-22-visual-row-model.md`

**Interfaces:** none (documentation + verification only).

- [ ] **Step 1: Extend the `AGENTS.md` architecture description**

In `AGENTS.md`, immediately after the `pointGeometryAt(...)` paragraph (the one ending with the `--point-geometry-query --gate` sentence, just before `## Package layout`), add:

```markdown
The **soft-wrap layer** (node 1) adds `WrapMetricsSource` (refines
`LineHorizontalMetricsSource` with one `canBreak(beforeColumn:inLine:)`
predicate — the provider owns break opportunities; the core owns no Unicode
tables) and `ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:)`, which
validates `wrapWidth` (`> 0`, `+∞` allowed — the equivalence case) and runs the
same O(1) metrics ladder as `columnAt`, then hands back a generic streaming
`VisualRowCursor<Metrics>` (wrapped in `VisualRowQuery<Metrics>` — the first
generic query enum). The cursor greedily packs one logical line into `VisualRow`s
in **visual order**: each row ends at the largest legal break-opportunity that
fits `wrapWidth`, and an unbreakable run wider than `wrapWidth` **overflows**
(a row wider than the width) rather than force-breaking. Every logical line yields
≥ 1 row (a blank line one `[0,0)` row); rows tile the line; row width is the
advance sum. At `wrapWidth ≥ the line's total advance` (∞ included) a line packs
to exactly one row equal to the no-wrap column model (per-line equivalence
oracle). This is per-logical-line packing only — cross-line aggregation, vertical
stacking, and wrap-aware `compute` are later nodes. O(1) core memory,
O(cells-in-row) per `next()`.
```

- [ ] **Step 2: Run the full core-change verification suite**

Run each and capture the output for the verification record:

```bash
swift test                                                   # expect: all pass (+ "0 tests in 0 suites")
swift build -c release                                       # expect: Compiling / Build complete
swift run -c release ViewportBenchmarks -- --gate            # expect: gate=pass (unchanged; no new mode)
rg -n "Foundation" Sources/TextEngineCore                    # expect: no output (empty)
./.github/scripts/cross-target-compile.sh --self-test        # expect: shell self-test passes (no toolchain)
```

Expected: `swift test` green; release build succeeds; `gate=pass`; the Foundation scan prints nothing; the cross-target self-test passes. (The real iOS + WASM cross-compiles run in hosted CI on the PR — record those run IDs in Step 3 once the PR is open.)

- [ ] **Step 3: Write the verification record**

Create `docs/superpowers/verification/2026-07-22-visual-row-model.md` with: the exact commands from Step 2 and their captured outputs; the new test counts (WrapMetricsSourceTests, VisualRowEquivalenceTests, WrapPackingTests, WrapValidationTests); a placeholder section "Hosted CI" to be filled with the PR-run and post-merge-push run IDs (read at **step** level, not job conclusion — a green job can hide a dead step) once CI runs. Anchor merged proof in the post-merge push run per the repo convention.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md docs/superpowers/verification/2026-07-22-visual-row-model.md
git commit -m "docs: AGENTS.md wrap layer + slice 49 verification record"
```

---

## Self-Review

**1. Spec coverage** (each spec section → task):
- Decision 1 (`WrapMetricsSource` refines + `canBreak`, no default) → Task 1.
- Decision 2 (greedy, overflow, tile, blank→one row, width=advance-sum) → Tasks 2 (blank) + 3 (greedy/overflow).
- Decision 3 (`VisualRow` fields) → Task 2.
- Decision 4 (generic `VisualRowCursor<Metrics>`, O(1) state, `next()`) → Tasks 2 + 3.
- Decision 5 (generic `VisualRowQuery<Metrics>`, `visualRows`, `wrapWidth > 0`, metrics ladder + order, no `.empty`, `inLine` precondition) → Tasks 2 (types + entry) + 4 (ladder).
- Decision 6 (∞-equivalence over irregular inputs) → Task 2 `testWidthAtOrAboveTotalYieldsOneRowEqualToNoWrap`.
- Decision 7 (test-only `TestWrapMetrics`, no public provider) → Task 1; `collectRows` helper → Task 2 (needs `VisualRowQuery`).
- Decision 8 (file placement) → File Structure + per-task Files blocks.
- Testing Strategy (all named tests) → Tasks 1–4. Benchmark/CI = none → no task (spec §Benchmark Mode/CI). Documentation Updates → Task 5. Verification + ACs → Task 5.
- ACs 1–8 all mapped (AC7 gate/Foundation/cross-compile, AC8 hosted step-level = Task 5 Steps 2–3).

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". Every code step shows complete code; the one deliberate stub (Task 2 `let end = columnCount`) is labelled and Task 3 gives its exact replacement. Each task compiles and passes standalone (Task 1 is struct + protocol only; `collectRows` lands in Task 2 with the types it needs); the Task-2 stub red that Task 3 turns green is stated explicitly.

**3. Type consistency:** `VisualRow` init label order `(logicalLine:rowInLine:startColumn:endColumn:width:)` identical across Tasks 2/3/4 tests and the type def. `VisualRowCursor(line:columnCount:wrapWidth:metrics:)` init identical in Task 2 and Task 4's `visualRows`. `visualRows(inLine:wrapWidth:metrics:)` label set identical everywhere. `VisualRowQuery<Metrics>` / `VisualRowCursor<Metrics>` generic form consistent. `collectRows` signature defined in Task 1 matches all call sites. Error cases (`.negativeColumnCount`, `.nonPositiveWrapWidth`, `.invalidColumnMetrics`) match the enum in Task 2 Step 1.
