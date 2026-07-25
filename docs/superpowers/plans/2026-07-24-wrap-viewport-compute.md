# Wrap-Aware Viewport Compute Over Visual Rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add wrap-aware viewport compute over a visual-row axis: a `VisualRowLayoutSource` provider contract, a `compute(_:layout:)` overload returning a visual-row `VirtualRange`, a `DocumentVisualRowCursor` streaming placed `VisualRowGeometry`, the whole-document infinite-width equivalence oracle, and an observational `--wrap-compute` width-change demonstration.

**Architecture:** Family A (exact, provider-owned visual-row index space). The provider owns the per-line visual-row-count prefix sum (`firstVisualRow`); `compute(_:layout:)` reuses the proven variable compute over a uniform row axis (`UniformLineMetrics(totalRows, rowHeight)`); the cursor re-packs each logical line with node 1's `VisualRowCursor`. Width is baked into the provider, so the core takes no `wrapWidth` and never re-walks the document on a width change.

**Tech Stack:** Swift 6.0 (tools), XCTest, `swift-tools-version: 6.0`. Pure headless core.

**Spec:** `docs/superpowers/specs/2026-07-24-wrap-viewport-compute-design.md` — read Decisions 1–9 before starting.

## Global Constraints

Copied verbatim from the spec / AGENTS.md; every task's requirements implicitly include these:

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty. Do not `import Foundation` in any core file.
- **Swift Embedded compatible / zero-dependency / compiles for iOS + WASM unchanged.** No third-party imports; no APIs that break Embedded Swift. New generic cursors must compose the same shape that already compiles (`VariableLineGeometryCursor`, node 1's `VisualRowCursor`).
- **O(1) core memory.** No core structure grows with document size or row count. `compute(_:layout:)` and `DocumentVisualRowCursor` hold constant state; no materialized arrays.
- **One logical step per commit**, conventional-commit prefixes (`feat:`, `test:`, `docs:`).
- **TDD.** Failing test first, minimal implementation, green, commit.
- **Uniform row height this slice** (`rowHeight` scalar). Variable height is out of scope (a later re-architecture — spec Risks).
- **No new blocking gate, no shipped public provider.** `--wrap-compute` is observational and not `isGateable`. Providers used are test-only / benchmark-local.

## File Structure

**Core (`Sources/TextEngineCore/`):**
- Create `VisualRowLayoutSource.swift` — the protocol + the binary-search default for `logicalLine(containingVisualRow:)` + the shared search helper.
- Create `WrapViewportVirtualizer.swift` — the `compute(_:layout:)` overload (as a `ViewportVirtualizer` extension).
- Create `DocumentVisualRowCursor.swift` — the cursor + the `visualRowGeometry(for:layout:)` factory.
- Modify `ViewportTypes.swift` — add `VisualRowGeometry` and the `.nonPositiveRowHeight` / `.invalidVisualRowLayout` error cases.

**Core tests (`Tests/TextEngineCoreTests/`):**
- Create `VisualRowLayoutTestSupport.swift` — `TestVisualRowLayout` (faithful, from real lines), `RiggedVisualRowLayout` (hand-set aggregates for validation), and the `collectGeometry` drain helper.
- Create `VisualRowLayoutSourceTests.swift`, `WrapComputeTests.swift`, `WrapComputeEquivalenceTests.swift`, `WrapComputeValidationTests.swift`.

**Benchmarks (`Sources/ViewportBenchmarks/`):**
- Modify `BenchmarkOptions.swift` — add the `wrapCompute` case, `outputName`, `isGateable` (false), `isFrameHotPath` (true), the parse case, the usage string.
- Modify `BenchmarkProgram.swift` — dispatch `.wrapCompute`.
- Create `WrapComputeBenchmark.swift` — the observational benchmark + a benchmark-local `BenchmarkWrapLayout`.

**Benchmark tests (`Tests/ViewportBenchmarksTests/`):**
- Create `WrapComputeOptionsTests.swift` — option-parse coverage + `isGateable == false`.

**Docs:** Modify `AGENTS.md` (architecture paragraph, commands, benchmark-flags list).

`Package.swift` needs **no** change — SwiftPM auto-includes new files in existing target directories.

---

### Task 1: `VisualRowLayoutSource` contract + binary-search default + test conformers

**Files:**
- Create: `Sources/TextEngineCore/VisualRowLayoutSource.swift`
- Create: `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift`
- Test: `Tests/TextEngineCoreTests/VisualRowLayoutSourceTests.swift`

**Interfaces:**
- Consumes: `WrapMetricsSource`, `ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:) -> VisualRowQuery<M>` (node 1).
- Produces:
  - `protocol VisualRowLayoutSource: WrapMetricsSource { var lineCount: Int { get }; var rowHeight: Double { get }; var wrapWidth: Double { get }; func visualRowCount(inLine: Int) -> Int; func firstVisualRow(ofLine: Int) -> Int; func logicalLine(containingVisualRow: Int) -> Int }` with a binary-search default for `logicalLine`.
  - `struct TestVisualRowLayout: VisualRowLayoutSource` — `init(lines: [(advances: [Double], breaks: Set<Int>)], rowHeight: Double, wrapWidth: Double)`.
  - `struct RiggedVisualRowLayout: VisualRowLayoutSource` — `init(lineCount: Int, rowHeight: Double, wrapWidth: Double, firstRow: [Int])`.
  - `func collectGeometry<L: VisualRowLayoutSource>(_ cursor: DocumentVisualRowCursor<L>) -> [VisualRowGeometry]` (referenced from Task 3; declared here in the same support file — leave it out until Task 3 if it will not compile, see note).

- [ ] **Step 1: Write the failing test for the protocol default inverse**

Create `Tests/TextEngineCoreTests/VisualRowLayoutSourceTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class VisualRowLayoutSourceTests: XCTestCase {
    // Lines pack to rowCounts [2, 1, 3] at this width -> firstVisualRow [0,2,3,6].
    // Line 0: 3 cells advance 10 each, break at {1,2}, width 20 -> rows [0,2),[2,3) = 2.
    // Line 1: 1 cell advance 5, no break, width 20 -> 1 row.
    // Line 2: 3 cells advance 30 each, break at {1,2}, width 20 (each cell overflows) -> 3 rows.
    private func layout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: [10, 10, 10], breaks: [1, 2]),
                (advances: [5], breaks: []),
                (advances: [30, 30, 30], breaks: [1, 2]),
            ],
            rowHeight: 4.0,
            wrapWidth: 20.0
        )
    }

    func testFirstVisualRowPrefixSum() {
        let l = layout()
        XCTAssertEqual(l.lineCount, 3)
        XCTAssertEqual(l.visualRowCount(inLine: 0), 2)
        XCTAssertEqual(l.visualRowCount(inLine: 1), 1)
        XCTAssertEqual(l.visualRowCount(inLine: 2), 3)
        XCTAssertEqual((0...3).map { l.firstVisualRow(ofLine: $0) }, [0, 2, 3, 6])
    }

    func testLogicalLineContainingVisualRowDefault() {
        let l = layout()
        // firstVisualRow = [0,2,3,6]; largest L with firstVisualRow(L) <= g.
        XCTAssertEqual((0..<6).map { l.logicalLine(containingVisualRow: $0) }, [0, 0, 1, 2, 2, 2])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter VisualRowLayoutSourceTests`
Expected: FAIL to **compile** — `VisualRowLayoutSource` / `TestVisualRowLayout` undefined.

- [ ] **Step 3: Create the protocol + binary-search default**

Create `Sources/TextEngineCore/VisualRowLayoutSource.swift`:

```swift
/// The visual-row axis for soft-wrap (Family A): the document's logical-line count,
/// a uniform visual-row height, the wrap width these counts are computed at, and the
/// provider-owned prefix sum of per-line visual-row counts. Mirrors `LineMetricsSource`
/// (count + cumulative `firstVisualRow` + a `logicalLine` inverse hook with a
/// binary-search default). Refines `WrapMetricsSource` so the cursor can reconstruct
/// each row's span from the same object (advances + break opportunities). The width is
/// baked in — a width change is a *new* provider.
public protocol VisualRowLayoutSource: WrapMetricsSource {
    /// Number of logical lines in the document.
    var lineCount: Int { get }

    /// Uniform height of one visual row, in layout units. Precondition: finite, `> 0`.
    var rowHeight: Double { get }

    /// The layout width these row counts are computed at. `> 0`, `+∞` allowed.
    var wrapWidth: Double { get }

    /// Visual rows logical line `line` packs into at `wrapWidth`. Precondition `>= 1`,
    /// and equal to node 1's packed row count for `line` at `wrapWidth`.
    func visualRowCount(inLine line: Int) -> Int

    /// Cumulative visual rows before logical line `line` (prefix sum of `visualRowCount`
    /// over `0..<line`). Domain `0...lineCount`; `firstVisualRow(ofLine: 0) == 0`;
    /// `firstVisualRow(ofLine: lineCount)` is the total visual-row count; strictly
    /// increasing. O(1), provider-owned. A width change reindexes exactly this.
    func firstVisualRow(ofLine line: Int) -> Int

    /// Largest `L` with `firstVisualRow(ofLine: L) <= g` — the logical line whose
    /// visual-row span contains global visual row `g`. Precondition `lineCount > 0`,
    /// `0 <= g < firstVisualRow(ofLine: lineCount)`. Does not validate or clamp.
    func logicalLine(containingVisualRow g: Int) -> Int
}

extension VisualRowLayoutSource {
    public func logicalLine(containingVisualRow g: Int) -> Int {
        binarySearchLogicalLine(containingVisualRow: g, layout: self, lineCount: lineCount)
    }
}

// Largest L in [0, lineCount) with firstVisualRow(ofLine: L) <= target. Identical shape
// to binarySearchLineIndex. Shared by the default logicalLine hook; a balanced-tree
// provider may override the hook for a single O(log N) descent (a later node).
func binarySearchLogicalLine<L: VisualRowLayoutSource>(
    containingVisualRow target: Int, layout: L, lineCount: Int
) -> Int {
    var low = 0
    var high = lineCount - 1
    var result = 0
    while low <= high {
        let mid = low + (high - low) / 2
        if layout.firstVisualRow(ofLine: mid) <= target {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    return result
}
```

- [ ] **Step 4: Create the test conformers**

Create `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift`:

```swift
import XCTest
import TextEngineCore

/// Faithful multi-line `VisualRowLayoutSource`. Row counts are precomputed at
/// construction by running node 1's packer per line, so `visualRowCount` agrees with
/// the packer by construction (the reference the cursor must match).
struct TestVisualRowLayout: VisualRowLayoutSource {
    let lineOffsets: [[Double]]   // per line: cumulative offsets [0, a0, a0+a1, ...]
    let lineBreaks: [Set<Int>]
    let rowHeight: Double
    let wrapWidth: Double
    let rowCounts: [Int]
    let firstRow: [Int]           // prefix sum, size lineCount + 1

    init(lines: [(advances: [Double], breaks: Set<Int>)], rowHeight: Double, wrapWidth: Double) {
        var offs: [[Double]] = []
        var brks: [Set<Int>] = []
        var counts: [Int] = []
        for (advances, breaks) in lines {
            let single = TestWrapMetrics(advances: advances, breakColumns: breaks)
            offs.append(single.offsets)
            brks.append(breaks)
            var n = 0
            if case .rows(var c) = ViewportVirtualizer.visualRows(
                inLine: 0, wrapWidth: wrapWidth, metrics: single
            ) {
                while c.next() != nil { n += 1 }
            }
            counts.append(n)
        }
        var pref: [Int] = [0]
        for n in counts { pref.append(pref.last! + n) }
        self.lineOffsets = offs
        self.lineBreaks = brks
        self.rowHeight = rowHeight
        self.wrapWidth = wrapWidth
        self.rowCounts = counts
        self.firstRow = pref
    }

    var lineCount: Int { lineOffsets.count }
    func columnCount(inLine line: Int) -> Int { lineOffsets[line].count - 1 }
    func columnOffset(inLine line: Int, column: Int) -> Double { lineOffsets[line][column] }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { lineBreaks[line].contains(column) }
    func visualRowCount(inLine line: Int) -> Int { rowCounts[line] }
    func firstVisualRow(ofLine line: Int) -> Int { firstRow[line] }
}

/// Hand-riggable `VisualRowLayoutSource` for validation-ladder tests: aggregates are set
/// directly (so `firstVisualRow(0)`, `totalRows`, `rowHeight`, `wrapWidth`, `lineCount`
/// can be made malformed). Column metrics are stubbed — `compute(_:layout:)` never reads
/// them (only the cursor does, and validation tests build no cursor).
struct RiggedVisualRowLayout: VisualRowLayoutSource {
    let lineCount: Int
    let rowHeight: Double
    let wrapWidth: Double
    let firstRow: [Int]   // size max(lineCount + 1, 1)

    func columnCount(inLine line: Int) -> Int { 0 }
    func columnOffset(inLine line: Int, column: Int) -> Double { 0.0 }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { false }
    func visualRowCount(inLine line: Int) -> Int { firstRow[line + 1] - firstRow[line] }
    func firstVisualRow(ofLine line: Int) -> Int { firstRow[line] }
}
```

Note: `collectGeometry` is added in Task 3 (it references `DocumentVisualRowGeometry` types that do not exist yet). Do not add it here.

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter VisualRowLayoutSourceTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Confirm the no-wrap path is untouched and Foundation-free**

Run: `swift build && rg -n "Foundation" Sources/TextEngineCore`
Expected: build succeeds; `rg` prints nothing (exit 1).

- [ ] **Step 7: Commit**

```bash
git add Sources/TextEngineCore/VisualRowLayoutSource.swift Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift Tests/TextEngineCoreTests/VisualRowLayoutSourceTests.swift
git commit -m "feat: VisualRowLayoutSource contract + binary-search inverse + test conformers"
```

---

### Task 2: `VisualRowGeometry` + error cases + `compute(_:layout:)` (with the finite-width recorded red)

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (add `VisualRowGeometry`, two error cases)
- Create: `Sources/TextEngineCore/WrapViewportVirtualizer.swift`
- Test: `Tests/TextEngineCoreTests/WrapComputeEquivalenceTests.swift`, `Tests/TextEngineCoreTests/WrapComputeTests.swift`

**Interfaces:**
- Consumes: `VisualRowLayoutSource` (Task 1), `UniformLineMetrics`, `ViewportVirtualizer.compute(_:metrics:) -> ViewportComputation`, `VirtualRange`, `ViewportComputation`.
- Produces:
  - `struct VisualRowGeometry: Equatable { let row: VisualRow; let y: Double; let height: Double; init(row:y:height:) }`
  - `ViewportValidationError.nonPositiveRowHeight`, `.invalidVisualRowLayout`
  - `static func compute<Layout: VisualRowLayoutSource>(_ input: VariableViewportInput, layout: Layout) -> ViewportComputation`

- [ ] **Step 1: Add `VisualRowGeometry` and the two error cases**

In `Sources/TextEngineCore/ViewportTypes.swift`, add to the `ViewportValidationError` enum (beside `nonPositiveWrapWidth`):

```swift
    case nonPositiveRowHeight
    case invalidVisualRowLayout
```

And add, beside `VisualRow`:

```swift
/// One visual row of a soft-wrapped document, placed on the vertical axis: node 1's
/// horizontal `VisualRow` span plus its top `y` and `height`. Mirrors `LineGeometry`
/// but composes `VisualRow` rather than re-declaring its fields. `y == globalVisualRow *
/// rowHeight`; `height == rowHeight` (uniform this slice).
public struct VisualRowGeometry: Equatable {
    public let row: VisualRow
    public let y: Double
    public let height: Double

    public init(row: VisualRow, y: Double, height: Double) {
        self.row = row
        self.y = y
        self.height = height
    }
}
```

- [ ] **Step 2: Write the equivalence + empty tests (pass against any correct compute)**

Create `Tests/TextEngineCoreTests/WrapComputeEquivalenceTests.swift`:

```swift
import XCTest
import TextEngineCore

final class WrapComputeEquivalenceTests: XCTestCase {
    // Irregular advances + irregular breaks + VARIABLE per-line column counts.
    private func irregularLines() -> [(advances: [Double], breaks: Set<Int>)] {
        [
            (advances: [7, 3, 11, 5], breaks: [1, 2, 3]),
            (advances: [13], breaks: []),
            (advances: [2, 2, 2, 2, 2, 2], breaks: [2, 4]),
            (advances: [], breaks: []),          // blank line
            (advances: [9, 9], breaks: [1]),
        ]
    }

    private func inputs() -> [VariableViewportInput] {
        [
            VariableViewportInput(scrollOffsetY: 0, viewportHeight: 30, overscanLinesBefore: 0, overscanLinesAfter: 0),
            VariableViewportInput(scrollOffsetY: 12, viewportHeight: 20, overscanLinesBefore: 1, overscanLinesAfter: 2),
            VariableViewportInput(scrollOffsetY: 9_999, viewportHeight: 20, overscanLinesBefore: 0, overscanLinesAfter: 0),
        ]
    }

    // At infinite width every logical line is one visual row, so the visual-row axis is
    // exactly UniformLineMetrics(lineCount, rowHeight) and the ranges must be identical.
    func testInfiniteWidthComputeEqualsUniformLogicalCompute() {
        let rowHeight = 4.0
        for width in [Double.infinity, 1_000_000.0] {   // ∞ and >= every line total
            let layout = TestVisualRowLayout(lines: irregularLines(), rowHeight: rowHeight, wrapWidth: width)
            XCTAssertEqual(layout.firstVisualRow(ofLine: layout.lineCount), layout.lineCount,
                           "at width \(width) every line should be one row")
            let uniform = UniformLineMetrics(lineCount: layout.lineCount, lineHeight: rowHeight)
            for input in inputs() {
                XCTAssertEqual(
                    ViewportVirtualizer.compute(input, layout: layout),
                    ViewportVirtualizer.compute(input, metrics: uniform),
                    "width \(width), scroll \(input.scrollOffsetY)")
            }
        }
    }

    func testEmptyDocumentIsEmptyRange() {
        let layout = TestVisualRowLayout(lines: [], rowHeight: 4.0, wrapWidth: 20.0)
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 30, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(range.isEmpty)
    }
}
```

- [ ] **Step 3: Write the finite-width row-range test (this carries the recorded red)**

Create `Tests/TextEngineCoreTests/WrapComputeTests.swift`:

```swift
import XCTest
import TextEngineCore

final class WrapComputeTests: XCTestCase {
    // 4 lines, each 4 cells advance 10, break at every cell, width 20 -> 2 rows/line.
    // totalRows = 8 (NOT lineCount 4). rowHeight 5 -> total height 40.
    private func layout(width: Double = 20.0) -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: Array(repeating: (advances: [10.0, 10.0, 10.0, 10.0], breaks: Set([1, 2, 3])), count: 4),
            rowHeight: 5.0,
            wrapWidth: width
        )
    }

    // A viewport of height 15 from the top covers rows [0,3): 3 visual rows, not 3 lines.
    // A stub compute that used lineCount (4) instead of totalRows (8) would clamp/scale
    // wrong here -- this is the finite-width test that the recorded-red stub fails.
    func testFiniteWidthVisibleRangeIsInVisualRows() {
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 15, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout()) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(range.visibleStart, 0)
        XCTAssertEqual(range.visibleEndExclusive, 3)   // rows 0,1,2 (y in [0,15))
        XCTAssertTrue(range.isAtTop)
        XCTAssertFalse(range.isAtBottom)
    }

    // Scrolling to the very bottom: total height 40, viewport 15 -> maxOffset 25 ->
    // visibleStart at row 5 (y=25), through row 8. isAtBottom true.
    func testScrollToBottomIsInVisualRows() {
        let input = VariableViewportInput(scrollOffsetY: 9_999, viewportHeight: 15, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout()) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(range.visibleEndExclusive, 8)   // 8 total rows
        XCTAssertTrue(range.isAtBottom)
    }
}
```

- [ ] **Step 4: Implement the STUB compute (records the red)**

Create `Sources/TextEngineCore/WrapViewportVirtualizer.swift`:

```swift
extension ViewportVirtualizer {
    /// Wrap-aware viewport compute over the visual-row axis. Returns a `VirtualRange`
    /// whose indices are **visual-row indices** (not logical lines). Reuses the proven
    /// variable compute over a uniform row axis. See the spec, Decision 2.
    public static func compute<Layout: VisualRowLayoutSource>(
        _ input: VariableViewportInput, layout: Layout
    ) -> ViewportComputation {
        // STUB (recorded red): uses lineCount, NOT totalRows. Correct at infinite width
        // (totalRows == lineCount there), WRONG at any finite wrapping width.
        return compute(input, metrics: UniformLineMetrics(lineCount: layout.lineCount, lineHeight: layout.rowHeight))
    }
}
```

- [ ] **Step 5: Run the tests — the finite-width suite must FAIL, the equivalence + empty must PASS**

Run: `swift test --filter WrapCompute`
Expected: `WrapComputeEquivalenceTests` PASS (at ∞ the range coincides with `lineCount`). In `WrapComputeTests`, `testFiniteWidthVisibleRangeIsInVisualRows` (top of document) **passes** in both stub and real — the top rows coincide, so it is not discriminating. `testScrollToBottomIsInVisualRows` **FAILS**: the stub computes over 4 pseudo-lines (total height 20, `visibleEndExclusive=4`, and a smaller `maxOffset`), while the assertion expects the real 8 rows (`visibleEndExclusive=8`). **This is the aggregation's recorded red** (spec Decision 7) — record it.

- [ ] **Step 6: Fix compute to use `totalRows`**

Replace the stub body in `WrapViewportVirtualizer.swift`:

```swift
    public static func compute<Layout: VisualRowLayoutSource>(
        _ input: VariableViewportInput, layout: Layout
    ) -> ViewportComputation {
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        return compute(input, metrics: UniformLineMetrics(lineCount: totalRows, lineHeight: layout.rowHeight))
    }
```

- [ ] **Step 7: Run the tests to verify all pass**

Run: `swift test --filter WrapCompute`
Expected: PASS (all of `WrapComputeEquivalenceTests` + `WrapComputeTests`).

- [ ] **Step 8: Commit**

```bash
git add Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/WrapViewportVirtualizer.swift Tests/TextEngineCoreTests/WrapComputeEquivalenceTests.swift Tests/TextEngineCoreTests/WrapComputeTests.swift
git commit -m "feat: compute(_:layout:) wrap-aware viewport compute over visual rows"
```

---

### Task 3: `DocumentVisualRowCursor` + `visualRowGeometry(for:layout:)` (streaming, D-12 fold-in)

**Files:**
- Create: `Sources/TextEngineCore/DocumentVisualRowCursor.swift`
- Modify: `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift` (add `collectGeometry`)
- Test: `Tests/TextEngineCoreTests/WrapComputeTests.swift` (extend), `Tests/TextEngineCoreTests/WrapComputeEquivalenceTests.swift` (extend)

**Interfaces:**
- Consumes: `VisualRowLayoutSource`, `VisualRowGeometry`, `VirtualRange`, node 1's `VisualRowCursor<Layout>` via `ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:)`.
- Produces:
  - `struct DocumentVisualRowCursor<Layout: VisualRowLayoutSource> { public mutating func next() -> VisualRowGeometry? }`
  - `static func visualRowGeometry<Layout: VisualRowLayoutSource>(for range: VirtualRange, layout: Layout) -> DocumentVisualRowCursor<Layout>`
  - `func collectGeometry<L>(_ cursor: DocumentVisualRowCursor<L>) -> [VisualRowGeometry]` (test helper)

- [ ] **Step 1: Write the cursor tiling + mid-line + blank tests**

In `Tests/TextEngineCoreTests/WrapComputeTests.swift`, add:

```swift
    private func drain(_ layout: TestVisualRowLayout, _ input: VariableViewportInput) -> [VisualRowGeometry] {
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else {
            XCTFail("expected success"); return []
        }
        return collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
    }

    func testCursorTilesBufferRangeInVisualRows() {
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 15, overscanLinesBefore: 0, overscanLinesAfter: 1)
        let rows = drain(layout(), input)
        // buffer = visible [0,3) + 1 overscan after -> 4 rows (globalRow 0..4 exclusive).
        XCTAssertEqual(rows.count, 4)
        // globalRow contiguous, y increases by rowHeight (5).
        for (i, g) in rows.enumerated() {
            XCTAssertEqual(g.y, Double(i) * 5.0, accuracy: 0)
            XCTAssertEqual(g.height, 5.0)
        }
        // each row's span matches node 1's packing: line L = globalRow/2, rowInLine = globalRow%2.
        for (i, g) in rows.enumerated() {
            XCTAssertEqual(g.row.logicalLine, i / 2)
            XCTAssertEqual(g.row.rowInLine, i % 2)
        }
    }

    func testCursorMidLineStart() {
        // Scroll so the buffer starts at row 1 of line 0 (an odd global row) -> the
        // O(rowInLine) discard walk must land on rowInLine 1.
        let input = VariableViewportInput(scrollOffsetY: 5, viewportHeight: 5, overscanLinesBefore: 0, overscanLinesAfter: 0)
        let rows = drain(layout(), input)
        XCTAssertEqual(rows.first?.row.logicalLine, 0)
        XCTAssertEqual(rows.first?.row.rowInLine, 1)
        XCTAssertEqual(rows.first?.y, 5.0)
    }

    func testBlankLineIsOneRow() {
        let layout = TestVisualRowLayout(
            lines: [(advances: [10, 10], breaks: [1]), (advances: [], breaks: []), (advances: [10], breaks: [])],
            rowHeight: 5.0, wrapWidth: 20.0)
        // line0 -> 1 row (both cells fit in 20), line1 blank -> 1 row [0,0), line2 -> 1 row.
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 100, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else { return XCTFail() }
        let rows = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1].row.startColumn, 0)
        XCTAssertEqual(rows[1].row.endColumn, 0)   // blank -> [0,0)
        XCTAssertEqual(rows[1].row.logicalLine, 1)
    }

    // D-12 fold-in: a break lands EXACTLY on wrapWidth (columnOffset(2) - 0 == 20 == width).
    // The inclusive `<=` edge must keep it on the row; a `<`-vs-`<=` mutation in
    // greedyEnd would split it and this fixture reddens.
    func testInteriorExactEqualWidthBoundary() {
        let layout = TestVisualRowLayout(
            lines: [(advances: [10, 10, 10], breaks: [1, 2])], rowHeight: 5.0, wrapWidth: 20.0)
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 100, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else { return XCTFail() }
        let rows = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].row.startColumn, 0)
        XCTAssertEqual(rows[0].row.endColumn, 2)   // [0,2) width exactly 20 -- inclusive edge
        XCTAssertEqual(rows[1].row.startColumn, 2)
    }
```

Add the streamed-one-per-line assertion to `WrapComputeEquivalenceTests`:

```swift
    func testInfiniteWidthStreamsOneRowPerLine() {
        let rowHeight = 4.0
        let layout = TestVisualRowLayout(lines: irregularLines(), rowHeight: rowHeight, wrapWidth: .infinity)
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 10_000, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else { return XCTFail() }
        let rows = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertEqual(rows.count, layout.lineCount)
        for (L, g) in rows.enumerated() {
            XCTAssertEqual(g.row.logicalLine, L)
            XCTAssertEqual(g.row.rowInLine, 0)
            XCTAssertEqual(g.row.startColumn, 0)
            XCTAssertEqual(g.row.endColumn, layout.columnCount(inLine: L))
            XCTAssertEqual(g.y, Double(L) * rowHeight)
        }
    }
```

- [ ] **Step 2: Add the `collectGeometry` helper**

Append to `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift`:

```swift
/// Drain a `DocumentVisualRowCursor` into an array.
func collectGeometry<L: VisualRowLayoutSource>(_ cursor: DocumentVisualRowCursor<L>) -> [VisualRowGeometry] {
    var c = cursor
    var out: [VisualRowGeometry] = []
    while let g = c.next() { out.append(g) }
    return out
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter WrapCompute`
Expected: FAIL to compile — `DocumentVisualRowCursor` / `visualRowGeometry` undefined.

- [ ] **Step 4: Implement the cursor + factory**

Create `Sources/TextEngineCore/DocumentVisualRowCursor.swift`:

```swift
/// Streams the placed visual rows of a document over a buffer visual-row range, in
/// visual order. Reuses node 1's per-line `VisualRowCursor` for packing; holds the
/// provider, so it is generic and O(1) state. Construct via
/// `ViewportVirtualizer.visualRowGeometry(for:layout:)`. Cost: O(rowInStartLine +
/// buffer) — the O(rowInStartLine) is the accepted within-line walk (spec fork).
public struct DocumentVisualRowCursor<Layout: VisualRowLayoutSource> {
    private let layout: Layout
    private let rowHeight: Double
    private let wrapWidth: Double
    private var currentLine: Int
    private var inner: VisualRowCursor<Layout>?
    private var globalRow: Int
    private var remaining: Int

    init(range: VirtualRange, layout: Layout) {
        self.layout = layout
        self.rowHeight = layout.rowHeight
        self.wrapWidth = layout.wrapWidth
        self.globalRow = range.bufferStart
        self.remaining = range.bufferEndExclusive - range.bufferStart
        if remaining <= 0 || layout.lineCount == 0 {
            self.currentLine = layout.lineCount
            self.inner = nil
            self.remaining = 0
            return
        }
        let startLine = layout.logicalLine(containingVisualRow: range.bufferStart)
        let rowInStartLine = range.bufferStart - layout.firstVisualRow(ofLine: startLine)
        self.currentLine = startLine
        self.inner = Self.makeInner(line: startLine, layout: layout, wrapWidth: wrapWidth)
        for _ in 0..<rowInStartLine { _ = inner?.next() }   // accepted O(rowInLine) walk
    }

    private static func makeInner(line: Int, layout: Layout, wrapWidth: Double) -> VisualRowCursor<Layout>? {
        if case .rows(let cursor) = ViewportVirtualizer.visualRows(inLine: line, wrapWidth: wrapWidth, metrics: layout) {
            return cursor
        }
        return nil   // malformed line is a precondition violation (compute already validated)
    }

    public mutating func next() -> VisualRowGeometry? {
        if remaining <= 0 { return nil }
        while true {
            if let row = inner?.next() {
                let geom = VisualRowGeometry(row: row, y: Double(globalRow) * rowHeight, height: rowHeight)
                globalRow += 1
                remaining -= 1
                return geom
            }
            currentLine += 1
            if currentLine >= layout.lineCount {
                remaining = 0
                return nil
            }
            inner = Self.makeInner(line: currentLine, layout: layout, wrapWidth: wrapWidth)
        }
    }
}

extension ViewportVirtualizer {
    /// Streams the placed `VisualRowGeometry` of the buffer visual-row range, in visual
    /// order. Precondition: `range` came from `compute(_:layout:)` over the same stable
    /// `layout`. Stateless; the cursor is lazy.
    public static func visualRowGeometry<Layout: VisualRowLayoutSource>(
        for range: VirtualRange, layout: Layout
    ) -> DocumentVisualRowCursor<Layout> {
        DocumentVisualRowCursor(range: range, layout: layout)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter WrapCompute`
Expected: PASS (all `WrapComputeTests` + `WrapComputeEquivalenceTests`).

- [ ] **Step 6: Verify the D-12 mutation reddens (manual mutation check)**

Temporarily change node 1's `greedyEnd` in `Sources/TextEngineCore/VisualRowCursor.swift`: the `<=` on line ~65 to `<`. Run: `swift test --filter testInteriorExactEqualWidthBoundary`.
Expected: FAIL (row[0].endColumn becomes 1, not 2). **Revert the mutation** and re-run: PASS. Record this in the verification doc as the oracle/boundary falsifiability evidence.

- [ ] **Step 7: Commit**

```bash
git add Sources/TextEngineCore/DocumentVisualRowCursor.swift Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift Tests/TextEngineCoreTests/WrapComputeTests.swift Tests/TextEngineCoreTests/WrapComputeEquivalenceTests.swift
git commit -m "feat: DocumentVisualRowCursor streams placed visual rows over the buffer range"
```

---

### Task 4: Validation ladder on `compute(_:layout:)`

**Files:**
- Modify: `Sources/TextEngineCore/WrapViewportVirtualizer.swift`
- Test: `Tests/TextEngineCoreTests/WrapComputeValidationTests.swift`

**Interfaces:**
- Consumes: `RiggedVisualRowLayout`, `TestVisualRowLayout`, `ViewportValidationError`, `emptyRange()` (internal to the module).
- Produces: the hardened `compute(_:layout:)` with the Decision 6 ladder (no signature change).

- [ ] **Step 1: Write the validation tests**

Create `Tests/TextEngineCoreTests/WrapComputeValidationTests.swift`:

```swift
import XCTest
import TextEngineCore

final class WrapComputeValidationTests: XCTestCase {
    private func goodInput() -> VariableViewportInput {
        VariableViewportInput(scrollOffsetY: 0, viewportHeight: 30, overscanLinesBefore: 0, overscanLinesAfter: 0)
    }
    private func rigged(lineCount: Int = 2, rowHeight: Double = 5.0, wrapWidth: Double = 20.0, firstRow: [Int] = [0, 1, 2]) -> RiggedVisualRowLayout {
        RiggedVisualRowLayout(lineCount: lineCount, rowHeight: rowHeight, wrapWidth: wrapWidth, firstRow: firstRow)
    }
    private func expectFailure(_ input: VariableViewportInput, _ layout: RiggedVisualRowLayout, _ expected: ViewportValidationError,
                               _ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertEqual(ViewportVirtualizer.compute(input, layout: layout), .failure(expected), file: file, line: line)
    }

    func testNegativeLineCount() { expectFailure(goodInput(), rigged(lineCount: -1, firstRow: [0]), .negativeLineCount) }
    func testNonFiniteScroll() {
        expectFailure(VariableViewportInput(scrollOffsetY: .nan, viewportHeight: 30, overscanLinesBefore: 0, overscanLinesAfter: 0), rigged(), .nonFiniteValue)
    }
    func testNegativeViewportHeight() {
        expectFailure(VariableViewportInput(scrollOffsetY: 0, viewportHeight: -1, overscanLinesBefore: 0, overscanLinesAfter: 0), rigged(), .negativeViewportHeight)
    }
    func testNegativeOverscan() {
        expectFailure(VariableViewportInput(scrollOffsetY: 0, viewportHeight: 30, overscanLinesBefore: -1, overscanLinesAfter: 0), rigged(), .negativeOverscan)
    }
    func testNonPositiveRowHeight() {
        for h in [0.0, -1.0, -Double.infinity, Double.nan] {
            expectFailure(goodInput(), rigged(rowHeight: h), .nonPositiveRowHeight)
        }
    }
    func testNonPositiveWrapWidth() {
        for w in [0.0, -1.0, -Double.infinity, Double.nan] {
            expectFailure(goodInput(), rigged(wrapWidth: w), .nonPositiveWrapWidth)
        }
    }
    func testInfiniteWrapWidthDoesNotFail() {
        // .infinity is legal; a well-formed ∞-width layout succeeds.
        let layout = TestVisualRowLayout(lines: [(advances: [5], breaks: [])], rowHeight: 5.0, wrapWidth: .infinity)
        if case .failure = ViewportVirtualizer.compute(goodInput(), layout: layout) { XCTFail("∞ width must not fail") }
    }
    func testFirstVisualRowZeroNotZero() { expectFailure(goodInput(), rigged(firstRow: [5, 6, 7]), .invalidVisualRowLayout) }
    func testNonPositiveTotalRows() { expectFailure(goodInput(), rigged(lineCount: 1, firstRow: [0, 0]), .invalidVisualRowLayout) }
    func testTotalHeightOverflowIsWrapCoherent() {
        // huge totalRows * huge rowHeight overflows to +∞ -> the wrap-specific case,
        // NOT the reused overload's .invalidLineMetrics leaking through.
        let huge = 1 << 40
        expectFailure(goodInput(), rigged(lineCount: 1, rowHeight: .greatestFiniteMagnitude, firstRow: [0, huge]), .invalidVisualRowLayout)
    }
    func testLadderOrderLineCountBeforeRowHeight() {
        // Both lineCount<0 AND rowHeight<=0 -> the earlier probe (negativeLineCount) wins.
        expectFailure(goodInput(), rigged(lineCount: -1, rowHeight: -1, firstRow: [0]), .negativeLineCount)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WrapComputeValidationTests`
Expected: FAIL — the current compute has no ladder, so malformed inputs either crash (array bounds in `firstVisualRow`) or leak the reused overload's error cases (e.g. `.invalidLineMetrics` / `.negativeLineCount` from delegation) instead of the wrap-specific cases.

- [ ] **Step 3: Implement the full Decision 6 ladder**

Replace the `compute(_:layout:)` body in `Sources/TextEngineCore/WrapViewportVirtualizer.swift`:

```swift
    public static func compute<Layout: VisualRowLayoutSource>(
        _ input: VariableViewportInput, layout: Layout
    ) -> ViewportComputation {
        if layout.lineCount < 0 { return .failure(.negativeLineCount) }
        if !input.scrollOffsetY.isFinite || !input.viewportHeight.isFinite { return .failure(.nonFiniteValue) }
        if input.viewportHeight < 0.0 { return .failure(.negativeViewportHeight) }
        if input.overscanLinesBefore < 0 || input.overscanLinesAfter < 0 { return .failure(.negativeOverscan) }
        if !layout.rowHeight.isFinite || layout.rowHeight <= 0.0 { return .failure(.nonPositiveRowHeight) }
        // wrapWidth > 0 accepts +∞ (the equivalence case) and rejects NaN/−∞/≤0. Do NOT
        // write `isFinite && > 0`: +∞ is not finite (the node-1 F1 trap).
        if !(layout.wrapWidth > 0) { return .failure(.nonPositiveWrapWidth) }
        if layout.firstVisualRow(ofLine: 0) != 0 { return .failure(.invalidVisualRowLayout) }
        if layout.lineCount == 0 { return .success(emptyRange()) }
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        if totalRows <= 0 { return .failure(.invalidVisualRowLayout) }
        let totalHeight = Double(totalRows) * layout.rowHeight
        if !totalHeight.isFinite { return .failure(.invalidVisualRowLayout) }
        return compute(input, metrics: UniformLineMetrics(lineCount: totalRows, lineHeight: layout.rowHeight))
    }
```

- [ ] **Step 4: Run the validation tests + the whole wrap suite to verify all pass**

Run: `swift test --filter WrapCompute`
Expected: PASS (validation + equivalence + compute + cursor).

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineCore/WrapViewportVirtualizer.swift Tests/TextEngineCoreTests/WrapComputeValidationTests.swift
git commit -m "feat: Decision-6 validation ladder on compute(_:layout:) (wrap-coherent errors)"
```

---

### Task 5: `--wrap-compute` observational benchmark + benchmark-local provider

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (enum case, outputName, isGateable, isFrameHotPath, parse, usage)
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift` (dispatch)
- Create: `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`
- Test: `Tests/ViewportBenchmarksTests/WrapComputeOptionsTests.swift`

**Interfaces:**
- Consumes: `BenchmarkMode`, `BenchmarkOptions.parse`, `ContinuousClock`, `nanoseconds(_:)`, `percentile(_:numerator:denominator:)`, `ViewportVirtualizer.compute(_:layout:)`, `visualRowGeometry(for:layout:)`, `VisualRowLayoutSource`.
- Produces: `BenchmarkMode.wrapCompute`, `runWrapComputeBenchmarks() -> Bool`, a benchmark-local `BenchmarkWrapLayout`.

- [ ] **Step 1: Write the option-parse tests**

Create `Tests/ViewportBenchmarksTests/WrapComputeOptionsTests.swift`:

```swift
import XCTest
@testable import ViewportBenchmarks

final class WrapComputeOptionsTests: XCTestCase {
    func testWrapComputeSelectsMode() {
        guard case .run(let opts) = BenchmarkOptions.parse(["--wrap-compute"]) else { return XCTFail() }
        XCTAssertEqual(opts.mode, .wrapCompute)
        XCTAssertFalse(opts.enforceGate)
    }
    func testWrapComputeRejectsGate() {
        guard case .failure(let msg) = BenchmarkOptions.parse(["--wrap-compute", "--gate"]) else { return XCTFail() }
        XCTAssertTrue(msg.contains("wrap_compute"))
    }
    func testWrapComputeRejectsSecondMode() {
        guard case .failure = BenchmarkOptions.parse(["--wrap-compute", "--line-query"]) else { return XCTFail() }
    }
    func testWrapComputeIsNotGateable() {
        XCTAssertFalse(BenchmarkMode.wrapCompute.isGateable)
    }
}
```

Note: `BenchmarkMode` must be `Equatable` for `XCTAssertEqual` on `.wrapCompute`. It is a plain enum with no associated values, so it is `Equatable` automatically. If a compile error says otherwise, compare `opts.mode.outputName` to `"wrap_compute"` instead.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WrapComputeOptionsTests`
Expected: FAIL to compile — `BenchmarkMode.wrapCompute` undefined.

- [ ] **Step 3: Add the enum case + classifications + parse + usage**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`:

Add the case after `case memoryObservation`:
```swift
    case wrapCompute
```
Add to `outputName`'s switch:
```swift
        case .wrapCompute:
            return "wrap_compute"
```
Add to `isGateable`'s **false** group (observational, no budget):
```swift
        case .rangeOnly,
             .memoryShape,
             .memoryObservation,
             .wrapCompute:
            return false
```
Add to `isFrameHotPath`'s **true** group (keeps the excluded set exactly `{bulk_structural_mutation}`; the ceiling never applies since `--gate` is rejected, but the exhaustive switch must classify it):
```swift
        case .pipeline,
             .rangeOnly,
             .realisticProvider,
             .variableHeight,
             .variableHeightMutation,
             .structuralMutation,
             .lineQuery,
             .lineGeometryQuery,
             .columnQuery,
             .columnGeometryQuery,
             .pointQuery,
             .pointGeometryQuery,
             .memoryShape,
             .memoryObservation,
             .wrapCompute:
            return true
```
Add the parse case (after `--memory-observation`):
```swift
            case "--wrap-compute":
                if mode != .pipeline {
                    return .failure("--wrap-compute cannot be combined with another mode")
                }
                mode = .wrapCompute
```
Add to `usage` (the flags line and an option line):
```
      --wrap-compute        Run the observational wrap-aware compute width-change demonstration (not gateable).
```

- [ ] **Step 4: Create the benchmark + benchmark-local provider**

Create `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`:

```swift
import TextEngineCore

/// Benchmark-local aggregation provider (not shipped). Every logical line is the same
/// `cells` cells of `advance` width, breakable at every cell (char-wrap). The prefix sum
/// is built by packing EACH line via node 1 at construction — an honest O(N) reindex, so
/// the width-change cost is measured, not faked.
struct BenchmarkWrapLayout: VisualRowLayoutSource {
    let lineCount: Int
    let rowHeight: Double
    let wrapWidth: Double
    let cells: Int
    let advance: Double
    let firstRow: [Int]

    init(lineCount: Int, cells: Int, advance: Double, rowHeight: Double, wrapWidth: Double) {
        self.lineCount = lineCount
        self.rowHeight = rowHeight
        self.wrapWidth = wrapWidth
        self.cells = cells
        self.advance = advance
        // Build the prefix by packing every line (identical here, but packed each time to
        // measure the real O(N) reindex).
        var pref: [Int] = [0]
        pref.reserveCapacity(lineCount + 1)
        let single = SingleLineWrap(cells: cells, advance: advance)
        var running = 0
        for _ in 0..<lineCount {
            var n = 0
            if case .rows(var c) = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: wrapWidth, metrics: single) {
                while c.next() != nil { n += 1 }
            }
            running += n
            pref.append(running)
        }
        self.firstRow = pref
    }

    func columnCount(inLine line: Int) -> Int { cells }
    func columnOffset(inLine line: Int, column: Int) -> Double { Double(column) * advance }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { column > 0 && column < cells }
    func visualRowCount(inLine line: Int) -> Int { firstRow[line + 1] - firstRow[line] }
    func firstVisualRow(ofLine line: Int) -> Int { firstRow[line] }
}

/// Single-line char-wrap metrics for packing one representative line.
private struct SingleLineWrap: WrapMetricsSource {
    let cells: Int
    let advance: Double
    func columnCount(inLine line: Int) -> Int { cells }
    func columnOffset(inLine line: Int, column: Int) -> Double { Double(column) * advance }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { column > 0 && column < cells }
}

@available(macOS 13.0, *)
func runWrapComputeBenchmarks() -> Bool {
    let lineCount = 100_000
    let cells = 80
    let advance = 1.0
    let rowHeight = 16.0
    let viewportHeight = 800.0
    let samples = 2_000
    let clock = ContinuousClock()

    // Wide (∞ -> 1 row/line) to narrow (more rows/line). Compute cost grows only as
    // O(log totalRows) across these -- viewport-bounded, NOT literally width-independent.
    let widths: [Double] = [.infinity, 40.0, 10.0]

    for width in widths {
        let reindexElapsed = clock.measure {
            _ = BenchmarkWrapLayout(lineCount: lineCount, cells: cells, advance: advance, rowHeight: rowHeight, wrapWidth: width)
        }
        let layout = BenchmarkWrapLayout(lineCount: lineCount, cells: cells, advance: advance, rowHeight: rowHeight, wrapWidth: width)
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        let maxOffset = Double(totalRows) * rowHeight - viewportHeight

        var computeSamples: [Int64] = []
        var drainSamples: [Int64] = []
        computeSamples.reserveCapacity(samples)
        drainSamples.reserveCapacity(samples)
        for s in 0..<samples {
            let scroll = deterministicScrollOffset(sample: s, maxOffset: max(0, maxOffset))
            let input = VariableViewportInput(scrollOffsetY: scroll, viewportHeight: viewportHeight, overscanLinesBefore: 4, overscanLinesAfter: 4)
            var range = VirtualRange(visibleStart: 0, visibleEndExclusive: 0, bufferStart: 0, bufferEndExclusive: 0, isAtTop: true, isAtBottom: true)
            let computeElapsed = clock.measure {
                if case .success(let r) = ViewportVirtualizer.compute(input, layout: layout) { range = r }
            }
            computeSamples.append(nanoseconds(computeElapsed))
            let drainElapsed = clock.measure {
                var cursor = ViewportVirtualizer.visualRowGeometry(for: range, layout: layout)
                var sink = 0
                while let g = cursor.next() { sink &+= g.row.endColumn }
                if sink == Int.min { print("") }   // prevent dead-code elimination
            }
            drainSamples.append(nanoseconds(drainElapsed))
        }
        computeSamples.sort()
        drainSamples.sort()
        let widthLabel = width.isFinite ? String(format: "%.0f", width) : "inf"
        print("mode=wrap_compute width=\(widthLabel) total_rows=\(totalRows)"
            + " compute_p95_ns=\(percentile(computeSamples, numerator: 95, denominator: 100))"
            + " compute_p99_ns=\(percentile(computeSamples, numerator: 99, denominator: 100))"
            + " drain_p95_ns=\(percentile(drainSamples, numerator: 95, denominator: 100))"
            + " reindex_ns=\(nanoseconds(reindexElapsed))")
    }
    return true
}
```

Note: `deterministicScrollOffset` is an existing `BenchmarkSupport` helper. `VirtualRange`'s memberwise `init` is public (see `ViewportTypes.swift`).

- [ ] **Step 5: Dispatch the mode**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, add before the closing brace of the `switch`:
```swift
    case .wrapCompute:
        return runWrapComputeBenchmarks()
```

- [ ] **Step 6: Run the option tests + build the benchmark target**

Run: `swift test --filter WrapComputeOptionsTests && swift build`
Expected: option tests PASS; build succeeds.

- [ ] **Step 7: Run the observational benchmark and capture output**

Run: `swift run -c release ViewportBenchmarks -- --wrap-compute`
Expected: three `mode=wrap_compute ...` lines (widths inf, 40, 10) with `total_rows` increasing as width narrows and `compute_p95_ns` roughly flat (a couple of binary-search steps of growth). Save the output for the verification doc.

- [ ] **Step 8: Confirm the gate/exclusion pins still pass**

Run: `swift test --filter ViewportBenchmarksTests`
Expected: PASS — `testEveryGateableModeIsRegistered`, `testNoUngateableModeIsRegistered`, and `testFrameHotPathExclusionsAreExactlyDocumented` all green (wrapCompute is non-gateable and registers no scenarios).

- [ ] **Step 9: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/WrapComputeBenchmark.swift Tests/ViewportBenchmarksTests/WrapComputeOptionsTests.swift
git commit -m "feat: --wrap-compute observational width-change demonstration (not gateable)"
```

---

### Task 6: Docs (AGENTS.md) + full verification record

**Files:**
- Modify: `AGENTS.md`
- Create: `docs/superpowers/verification/2026-07-24-wrap-viewport-compute.md`

**Interfaces:** none (docs + verification).

- [ ] **Step 1: Update `AGENTS.md`**

In the architecture section (after the soft-wrap `visualRows` paragraph), add a paragraph describing node 2: the `VisualRowLayoutSource` contract (the visual-row axis; `lineCount` + `rowHeight` + `wrapWidth` + `visualRowCount`/`firstVisualRow` prefix sum + `logicalLine(containingVisualRow:)` inverse with a binary-search default), `compute(_:layout:)` as the **third** `compute` overload returning a visual-row `VirtualRange`, `visualRowGeometry(for:layout:)` streaming `VisualRowGeometry` in O(buffer), the width baked into the provider (the core takes no `wrapWidth` and never re-walks the document; only the provider's O(N) reindex on a width change — Ω(N), a setup cost), the whole-document infinite-width equivalence oracle, and the documented O(rowInLine) within-line boundary.

In `## Commands`, add:
```
swift run -c release ViewportBenchmarks -- --wrap-compute   # observational wrap compute width-change demo (not gateable)
```

In the "Benchmark flags" list, add `--wrap-compute` and note it is **rejected** with `--gate` (alongside `--range-only`, `--memory-shape`, `--memory-observation`).

- [ ] **Step 2: Run the full verification suite**

Run each and capture output:
```bash
swift test 2>&1 | tail -5
swift build -c release 2>&1 | tail -2
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tail -3
swift run -c release ViewportBenchmarks -- --wrap-compute
rg -n "Foundation" Sources/TextEngineCore ; echo "rg exit: $?"
```
Expected: full suite green (`Executed N tests ... 0 failures`); release build ok; `--gate` prints `gate=pass` (unchanged — no new gated mode); three `--wrap-compute` lines; `rg` prints nothing (exit 1).

- [ ] **Step 3: Cross-target compile (portability-sensitive — new public API)**

Run: `./.github/scripts/cross-target-compile.sh --targets ios` (and `--targets wasm` if a matching 6.2.1 SDK is installed locally; otherwise rely on the hosted CI jobs).
Expected: iOS device + simulator compile pass for `TextEngineCore` + `TextEngineReferenceProviders`; `result=pass` lines. Record the outcome (or note WASM is deferred to hosted CI).

- [ ] **Step 4: Write the verification record**

Create `docs/superpowers/verification/2026-07-24-wrap-viewport-compute.md` with: the exact commands + outputs from Steps 2–3; the `--wrap-compute` numbers phrased as "viewport-bounded; compute grows only as O(log totalRows) — a couple of binary-search steps between ∞ and the narrowest width; the O(N) reindex is the measured setup cost" (per spec Point 4); the D-12 mutation red/green from Task 3 Step 6; and the recorded red from Task 2 Step 5. Leave a placeholder section for hosted CI run IDs to be filled from the PR-head and post-merge runs.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs/superpowers/verification/2026-07-24-wrap-viewport-compute.md
git commit -m "docs: AGENTS.md wrap-compute (node 2) + verification record"
```

---

## Self-Review

**1. Spec coverage** (each AC → task):
- AC1 `VisualRowLayoutSource` shape + binary-search default → Task 1.
- AC2 `VisualRowGeometry` + `DocumentVisualRowCursor` + two error cases → Tasks 2, 3.
- AC3 `compute(_:layout:)` ladder + reused-uniform range, O(log N)/O(1) → Tasks 2, 4.
- AC4 `visualRowGeometry` streaming, mid-line + blank, O(rowInStartLine + buffer) → Task 3.
- AC5 whole-document equivalence oracle + finite-width recorded red → Tasks 2, 3.
- AC6 D-12 interior boundary + mutation reddens; full suite green → Task 3.
- AC7 Foundation-free + release + `--gate` + `--wrap-compute` + iOS/WASM → Task 6.
- AC8 hosted CI step-level green + run IDs → Task 6 (verification placeholder; filled at PR time).

**2. Placeholder scan:** no "TBD"/"add error handling"/"similar to Task N" — every code step carries complete code. The only cross-task reference (`collectGeometry`) is defined in Task 3 with a note in Task 1 explaining the deferral.

**3. Type consistency:** `VisualRowLayoutSource` members (`lineCount`, `rowHeight`, `wrapWidth`, `visualRowCount`, `firstVisualRow`, `logicalLine(containingVisualRow:)`) are identical across Tasks 1–5. `compute(_ input:layout:)` / `visualRowGeometry(for:layout:)` / `VisualRowGeometry(row:y:height:)` signatures match between producer and consumer tasks. `BenchmarkMode.wrapCompute` / `outputName == "wrap_compute"` consistent across Task 5 and its tests.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-24-wrap-viewport-compute.md`. Two execution options:

1. **Subagent-Driven (recommended)** — a fresh subagent per task, two-stage review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session with checkpoints.

Which approach?
