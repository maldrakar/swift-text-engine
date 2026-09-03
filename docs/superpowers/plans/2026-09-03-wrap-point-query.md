# Wrap Point Query (Slice 55b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship node 4 proper — `ViewportVirtualizer.visualPointAt(x:y:layout:)`, the wrap-aware `(x, y) → (visual row, cell)` composite over a single `VisualRowLayoutSource` — with the infinite-width oracle, the probe-count table, the three malformed-provider cases, an observational `--wrap-point-query` benchmark mode, and the D-33 fold-in the slice-55a review made mandatory. Criterion 3 goes `partial → done`.

**Architecture:** Composition, not a new search. Step 1 delegates the whole vertical half to `visualRowAt` (55a's guards ride along, so no guard lives in this query); step 2 rejects a non-finite `x` before any horizontal work; step 3 runs 55a's shared `validateWrapLine` ladder and walks 55a's shared `advanceVisualRows` to the located row; steps 4–6 answer blank rows and both clamps from the span alone; step 7 rebases `x` by the row's left offset and calls the provider's `columnIndex` hook directly, guarded by `rebased >= total` and clamped into the row's span. Cost: one row-axis search + one `logicalLine` search + the inherited within-line walk + one optional `columnIndex` search, O(1) core memory.

**Tech Stack:** Swift 6.0 tools version, XCTest, SwiftPM. No dependencies. Local toolchain is Swift 6.2.4 (hosted CI is 6.2.1).

**Spec:** [`docs/superpowers/specs/2026-08-24-wrap-point-query-design.md`](../specs/2026-08-24-wrap-point-query-design.md) — read **Contract — 55b** first; it is this plan's source, and every task below names the Decision it implements. 55a is merged (`ccbd13e`); its helpers (`validateWrapLine`, `advanceVisualRows`, the five guards, the `greedyEnd` short-circuit) are in the tree and this plan **consumes** them.

## Global Constraints

Every task's requirements implicitly include these.

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty; run it at every commit that touches the core.
- **Zero third-party dependencies**; **Swift Embedded compatible** (value types, no existentials, no Foundation); compiles for iOS and WASM with no source changes — this slice adds public core API, so the hosted iOS and WASM jobs are its portability evidence (Task 11).
- **No guard for the row-axis hook's answer lives in `visualPointAt`.** Guards 1 and 2 are `visualRowAt`'s (55a); guards 3 and 4 are `DocumentVisualRowCursor.init`'s; guard 5 is `advanceVisualRows`' `k <= 0` rule. This query adds exactly one new failure of its own: the walk exhausting early (spec Decision 5, step 3). If a step here finds itself re-checking `logicalLine` or `rowInLine`, the guard has been placed in the wrong file.
- **`x` is row-relative; the returned column index is line-absolute** (Decisions 1 and 2). Both are in visual order.
- **Every gated mode's benchmark checksum is byte-identical to the pre-branch baseline** (AC13). This slice touches no gated path; a movement in any of the twelve gates is a **finding**, not noise.
- **The `--wrap-compute` `checksum=` VALUE must not change.** Task 9 extracts the fold into a pure function so a test can drive it (D-33) — extraction only, weights unchanged (`compute &+ drain`), so 55b's `--wrap-compute` column stays byte-comparable against 55a's final column, which the spec's Verification section requires. A weighted fold would buy swap-detection and cost that comparison; the trade-off is recorded in the test file and in the ledger discharge.
- **`--wrap-point-query` is observational**: `isGateable == false`, `--gate` rejected, latency tokens stay prefixed (`query_p95_ns=`), not wired into `.github/workflows/swift-ci.yml`, no budget, no corpus row. `absoluteCeiling` is `.scrollFrame` (spec Benchmark Mode / CI — a decision, not a default).
- **`BenchmarkWrapLayout` is not touched.** Its `init` *is* `--wrap-compute`'s measured reindex. The new mode gets its own `WrapPointQueryLayout` with an O(`lineCount` + `cells`) construction.
- **TDD.** Failing test first, minimal implementation, green, commit. Where a pin's red requires breaking shipped code, that is a **drill**: apply the edit, observe the red, record the exact failure line, revert with `git checkout --`, re-run green. A drill is never committed.
- **Fourteen recorded reds** (spec drills (a), (b), (c), (d1), (d2), (d3), (e), (g), (h), (i), (j), (k) — twelve — plus (n) and (o) for D-33). A guarantee whose drill is missing is an unfinished acceptance criterion (AC14).
- **Conventional commits**: `feat:`, `test:`, `refactor:`, `docs:`. One logical step per commit. Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
  ```
- **Branch**: `slice-55b-wrap-point-query` (already created from `main` at `6ff3852`; its first commit `38028db` records the selection and the three routed P2 calls).
- **D-17 — do NOT use `${PIPESTATUS[0]}` in any command block.** Agent shells here are **zsh**, where it expands empty and `[ "" -eq 0 ]` evaluates **true**, inverting a failed assertion into a pass. Use `if ! cmd; then …; fi`, a plain `$?` on an unpiped command, or `[ -z "$(…)" ]`.
- **D-2 assertion conventions**: never put a check on the left of a pipe whose right side is `tail`/`tee`/`jq`/`wc`/`rg`; never `echo "…=$?"` after a status-insensitive command (`git diff --name-only`, `git status`, `jq`, `sed -i`, every pipeline); `rg`/`grep` exit 1 on **no** match, so assert with `[ -z "$(…)" ]`, `git diff --quiet`, or an `if`/`else` that prints both branches.
- **Every command block assigns the variables it uses.** Each Bash invocation is a fresh shell.
- Run everything from the repo root: `/Users/aabanschikov/swift-text-engine`.
- **Scratch files** go under `/tmp/slice55b-*` (flat files, Tasks 8-9) or the directory `/tmp/slice55b/`
  (Task 11 creates it with `mkdir -p` before its first write). Never inside the repository.
- **Line numbers in this plan are anchors, not instructions.** Edits are given as *Replace / With* text; match on the text.

---

## File Structure

**Core (`Sources/TextEngineCore`)**

| File | Responsibility after this slice |
|---|---|
| `ViewportTypes.swift` | +`VisualPointQuery` (`.point` / `.empty` / `.failure`) and +`VisualPointLocation` (`row: VisualRowLocation`, `rowSpan: VisualRow`, `column: ColumnResolution`), placed beside `PointQuery`/`PointLocation` where every `Visual*` type already lives. `ColumnResolution` is **reused**, not re-declared. |
| `WrapPointQuery.swift` | **new** — `visualPointAt(x:y:layout:)`, the seven-step ladder. The only file with new behaviour. |

**Benchmarks (`Sources/ViewportBenchmarks`)**

| File | Responsibility |
|---|---|
| `WrapPointQueryBenchmark.swift` | **new** — `WrapPointQueryScenario`, the top-level `wrapPointQueryScenarios` table, `WrapPointQueryLayout` (O(`lineCount` + `cells`) construction), `wrapPointQueryChecksum`, `formatWrapPointQueryLine`, `runWrapPointQueryBenchmarks()`. |
| `BenchmarkOptions.swift` | +`case wrapPointQuery` with its `outputName`, its `isGateable == false` arm, its `absoluteCeiling == .scrollFrame` arm, the `--wrap-point-query` parse case, and the usage/`--help` lines. |
| `BenchmarkProgram.swift` | +the dispatch arm. |
| `WrapComputeBenchmark.swift` | +`wrapComputeChecksum(compute:drain:)`, a pure extraction of the existing `computeMeasured.checksum &+ drainMeasured.checksum` (D-33). Value unchanged. `BenchmarkWrapLayout` untouched. |

**Tests (`Tests/TextEngineCoreTests`)**

| File | Responsibility |
|---|---|
| `WrapPointQueryTests.swift` | **new** — behaviour: interior cell, exact cell boundary, both `x` clamps, blank line, an overflow row, a clamped `y` crossed with each `x` branch, Decision 6's two fixtures, the swept span property (Decision 2), the verbatim-`row` sweep and the duplicated-field agreement (Decision 3). |
| `WrapPointQueryValidationTests.swift` | **new** — the ladder rung by rung, both structural precedence pairs, `x = ±∞` named separately, and all three malformed-provider cases. |
| `WrapPointQueryCountTests.swift` | **new** — two counters, two fixtures: the layout-axis bound `<= ceilLog2(lineCount) + 4`; zero column-metric calls on every non-located path; exactly `3 + 2` clamped and `3 + 2 + 1` delegating on a fitting line; the `rowInLine` growth lower bound; exactly one `logicalLine` and at most one `columnIndex` call on overriding conformers. |
| `WrapPointQueryEquivalenceTests.swift` | **new** — criterion 3's oracle: at `∞` and at a finite width no line exceeds, bit-identical to `pointAt` over a uniform vertical axis on the located branch, with a narrow-width control. |
| `WrapPointQueryRoundTripTests.swift` | **new** — every row streamed by `visualRowGeometry` is found by its own `y`, with an equal `rowSpan`; fixture carries a fitting line **and** a wrapped one, with a guard. |
| `WrapRowQueryCountTests.swift` | D-25: the redundant `< lineCount / 10` bound is tightened to the sibling's tight bound at a **second search target**. |
| `VisualRowLayoutTestSupport.swift` | The `RiggedVisualRowLayout` comment is corrected — `visualPointAt` is the first *query* that reaches its stubbed column metrics through the cursor. |

**Tests (`Tests/ViewportBenchmarksTests`)**

| File | Responsibility |
|---|---|
| `WrapPointQueryChecksumTests.swift` | **new** — every folded field moves the value, fields are not interchangeable, `.blankLine` cannot collide with cell 0. |
| `WrapPointQueryOptionsTests.swift` | **new** — mode selection, `--gate` rejected, a second mode flag rejected, `isGateable == false`. |
| `WrapBenchmarkLineShapeTests.swift` | +3 cases: no bare `p95_ns=`/`p99_ns=` key and the `fast_path=` value the parameters imply; the scenario table's floors; `WrapPointQueryLayout` and `BenchmarkWrapLayout` agree element for element on `firstVisualRow`. |
| `WrapComputeChecksumTests.swift` | **new** (D-33) — both halves of the `wrap_compute` fold move the value, and `drainVisualRows` folds **every** row's `endColumn`, not the first. |

**Docs**: `AGENTS.md` (node 4 paragraph, commands, both flag lists, "both wrap modes" → three, the `Tests/ViewportBenchmarksTests` inventory head-count), `docs/superpowers/debt-ledger.md` (D-18, D-25, D-33 → `discharged`), the spec's Revision History + Decision 15 + AC19 (the D-33 fold-in), `docs/superpowers/verification/2026-09-03-wrap-point-query.md` (new).

**Untouched on purpose**: `BenchmarkWrapLayout`, every gated benchmark file, `BenchmarkModels.swift`, `.github/workflows/swift-ci.yml`, the corpus, every budget, `docs/superpowers/arcs/wrap.md`'s map (node 4 is marked `done` at the post-slice review, not here — spec Documentation Updates).

---

## Task 1: The result types and the seven-step ladder

Spec Contract 55b (the ladder), Decisions 1, 2, 3, 5, 7, 8, 10, 14. This task delivers the whole query and its behavioural cases; every later core task adds a pin over code that already exists here.

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (append after `ColumnGeometryResolution`, the last type in the file)
- Create: `Sources/TextEngineCore/WrapPointQuery.swift`
- Create: `Tests/TextEngineCoreTests/WrapPointQueryTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.visualRowAt(y:layout:) -> VisualRowQuery` (`WrapPositionQuery.swift`); `validateWrapLine(inLine:wrapWidth:metrics:) -> WrapLineMetrics` and `VisualRowCursor.init(line:columnCount:total:wrapWidth:metrics:)` (`VisualRowCursor.swift`, both `internal`); `advanceVisualRows(_:by:) -> VisualRow?` (`DocumentVisualRowCursor.swift`, `internal`); `VisualRowLayoutSource.columnIndex(containingOffset:inLine:)` (inherited from `LineHorizontalMetricsSource`).
- Produces: `public enum VisualPointQuery { case point(VisualPointLocation); case empty; case failure(ViewportValidationError) }`; `public struct VisualPointLocation { public let row: VisualRowLocation; public let rowSpan: VisualRow; public let column: ColumnResolution }` with a public memberwise `init(row:rowSpan:column:)`; `public static func visualPointAt<Layout: VisualRowLayoutSource>(x: Double, y: Double, layout: Layout) -> VisualPointQuery`.

- [ ] **Step 1: Write the failing behaviour test**

Create `Tests/TextEngineCoreTests/WrapPointQueryTests.swift`:

```swift
import XCTest
import TextEngineCore

/// Node 4's behaviour. The fixture carries all three row kinds the ladder distinguishes:
/// a wrapped line (three equal rows), a blank line (one `[0, 0)` row), and a line whose
/// first row OVERFLOWS the wrap width (an unbreakable run wider than the width — node 1
/// packs it rather than force-breaking, so an `x` between `wrapWidth` and `rowSpan.width`
/// is a real point inside a real row).
final class WrapPointQueryTests: XCTestCase {
    static let rowHeight = 10.0
    static let wrapWidth = 20.0

    /// line 0: 6 cells x 10, breakable everywhere -> rows [0,2) [2,4) [4,6), each 20 wide
    /// line 1: blank                              -> one [0,0) row
    /// line 2: advances [30, 10], break before 1  -> rows [0,1) width 30 (OVERFLOW), [1,2) width 10
    /// firstVisualRow = [0, 3, 4, 6]; totalRows 6; total height 60.
    static func layout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: Array(repeating: 10.0, count: 6), breaks: Set(1..<6)),
                (advances: [], breaks: []),
                (advances: [30.0, 10.0], breaks: [1]),
            ],
            rowHeight: rowHeight,
            wrapWidth: wrapWidth)
    }

    private func located(
        x: Double, y: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) -> VisualPointLocation? {
        switch ViewportVirtualizer.visualPointAt(x: x, y: y, layout: Self.layout()) {
        case .point(let location):
            return location
        case .empty:
            XCTFail("expected .point, got .empty", file: file, line: line); return nil
        case .failure(let error):
            XCTFail("expected .point, got .failure(\(error))", file: file, line: line); return nil
        }
    }

    // Global row 1 = line 0, row 1: span [2, 4), rowLeft 20, width 20.
    func testInteriorOfAMiddleRowResolvesToItsCell() {
        guard let point = located(x: 5.0, y: 15.0) else { return }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 1, logicalLine: 0, rowInLine: 1, clamp: .inRange))
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 2, endColumn: 4, width: 20.0))
        // Line-ABSOLUTE (Decision 2): x = 5 is row-relative, cell 2 is the line's index.
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 2, clamp: .inRange)))
    }

    // Half-open spans: an x landing exactly on a cell boundary belongs to the LATER cell.
    func testExactCellBoundaryResolvesToTheLaterCell() {
        guard let point = located(x: 10.0, y: 15.0) else { return }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 3, clamp: .inRange)))
    }

    // Decision 1: the clamps land on the ROW's edges, not the line's.
    func testXAtTheRowWidthClampsToTheRowsLastCell() {
        guard let point = located(x: 20.0, y: 15.0) else { return }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 3, clamp: .clampedToRight)))
    }

    func testNegativeXClampsToTheRowsFirstCell() {
        guard let point = located(x: -1.0, y: 15.0) else { return }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 2, clamp: .clampedToLeft)))
    }

    // Decision 7: read from the span, not from a second columnCount probe.
    func testBlankLineResolvesToBlankLine() {
        guard let point = located(x: 5.0, y: 35.0) else { return }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 3, logicalLine: 1, rowInLine: 0, clamp: .inRange))
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 1, rowInLine: 0, startColumn: 0, endColumn: 0, width: 0.0))
        XCTAssertEqual(point.column, .blankLine)
    }

    // AC2: on an OVERFLOW row the clamp compares against the row's own advance sum, not
    // against wrapWidth -- so wrapWidth < x < rowSpan.width is .inRange, a real point.
    func testXBetweenWrapWidthAndRowWidthOnAnOverflowRowStaysInRange() {
        guard let point = located(x: 25.0, y: 45.0) else { return }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 4, logicalLine: 2, rowInLine: 0, clamp: .inRange))
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 2, rowInLine: 0, startColumn: 0, endColumn: 1, width: 30.0))
        XCTAssertGreaterThan(25.0, Self.wrapWidth, "the fixture must put x past the wrap width, or this covers nothing")
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 0, clamp: .inRange)))
    }

    // Both clamp flags observed together: the vertical one on `row`, the horizontal one
    // on the cell. A query that dropped either would still pass every test above.
    func testClampedYCrossedWithEachXBranch() {
        guard let topLeft = located(x: -1.0, y: -5.0) else { return }
        XCTAssertEqual(topLeft.row, VisualRowLocation(globalRow: 0, logicalLine: 0, rowInLine: 0, clamp: .clampedToTop))
        XCTAssertEqual(topLeft.column, .cell(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft)))

        guard let bottomRight = located(x: 100.0, y: 1_000.0) else { return }
        XCTAssertEqual(bottomRight.row, VisualRowLocation(globalRow: 5, logicalLine: 2, rowInLine: 1, clamp: .clampedToBottom))
        XCTAssertEqual(bottomRight.rowSpan, VisualRow(logicalLine: 2, rowInLine: 1, startColumn: 1, endColumn: 2, width: 10.0))
        XCTAssertEqual(bottomRight.column, .cell(ColumnLocation(columnIndex: 1, clamp: .clampedToRight)))

        guard let bottomInterior = located(x: 5.0, y: 1_000.0) else { return }
        XCTAssertEqual(bottomInterior.row.clamp, .clampedToBottom)
        XCTAssertEqual(bottomInterior.column, .cell(ColumnLocation(columnIndex: 1, clamp: .inRange)))
    }
}
```

- [ ] **Step 2: Run it and confirm it fails to compile**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryTests 2>&1 | tail -20
```

Expected: a compile error naming `visualPointAt` / `VisualPointLocation` as unresolved (`cannot find 'ViewportVirtualizer.visualPointAt'`, `cannot find type 'VisualPointLocation' in scope`). Record the exact first error line — it is this task's red.

- [ ] **Step 3: Add the two public types**

Append to `Sources/TextEngineCore/ViewportTypes.swift` (after `ColumnGeometryResolution`, at the end of the file):

```swift
/// The wrap-aware 2D result: `visualPointAt`'s answer — a located visual row plus the
/// cell within it. The visual-row mirror of `PointQuery`.
public enum VisualPointQuery: Equatable {
    case point(VisualPointLocation)       // a visual row was located (its cell may be blank)
    case empty                            // empty document: lineCount == 0
    case failure(ViewportValidationError) // vertical, horizontal or layout validation failure
}

/// Where a point `(x, y)` lands in a soft-wrapped document.
///
/// `x` is measured from the located ROW's left edge (spec Decision 1) while
/// `column.cell.columnIndex` is an index into the LOGICAL LINE (Decision 2);
/// `rowSpan.startColumn` is the bridge in both directions. Both quantities are in visual
/// order, which is what the brief promises — bidi is out of scope today, so visual and
/// logical order coincide, and the day they stop coinciding a caller needs to know this
/// index was never the logical one.
public struct VisualPointLocation: Equatable {
    /// The located row, carried VERBATIM from `visualRowAt(y:layout:)`.
    ///
    /// Type note: this is a `VisualRowLocation` (globalRow + logicalLine + rowInLine +
    /// vertical clamp), NOT a `VisualRow` — unlike `VisualRowGeometry.row`, which is a
    /// `VisualRow`. The two families deliberately spell `.row` differently: this one
    /// mirrors `PointLocation.line: LineLocation`, that one composes node 1's span type.
    /// The span lives under `rowSpan` here.
    public let row: VisualRowLocation
    /// The located row's half-open cell span and advance-sum width.
    ///
    /// Type note: this IS node 1's `VisualRow`. Returned because the core derives it
    /// anyway to rebase `x`, and re-deriving it would cost the caller a second within-line
    /// walk; without it, `.clampedToRight` cannot be told from a soft break at the row's
    /// end. `logicalLine` and `rowInLine` appear here and on `row`; they agree by
    /// construction (one walk, `advanceVisualRows(by: rowInLine + 1)`).
    public let rowSpan: VisualRow
    /// The located cell within the row (index + horizontal clamp), or `.blankLine` when
    /// the located line has no cells. Reused from `PointLocation` — the question is
    /// identical.
    public let column: ColumnResolution

    public init(row: VisualRowLocation, rowSpan: VisualRow, column: ColumnResolution) {
        self.row = row
        self.rowSpan = rowSpan
        self.column = column
    }
}
```

- [ ] **Step 4: Write the query**

Create `Sources/TextEngineCore/WrapPointQuery.swift`:

```swift
extension ViewportVirtualizer {
    /// Maps a point `(x, y)` to the visual row whose vertical span contains `y` and the
    /// cell within that row whose horizontal span contains `x` — the wrap-aware analog of
    /// `pointAt(x:y:lineMetrics:columnMetrics:)`, over a SINGLE `VisualRowLayoutSource`.
    ///
    /// One source for both axes (the layout refines `WrapMetricsSource`, which refines
    /// `LineHorizontalMetricsSource`), so unlike `pointAt` there is no precondition that
    /// two sources describe the same document.
    ///
    /// `x` is measured from the located ROW's left edge, and the clamps land on the row's
    /// edges: `x < 0` resolves to the row's first cell (`.clampedToLeft`), `x >=
    /// rowSpan.width` to its last (`.clampedToRight`). On an OVERFLOW row (an unbreakable
    /// run wider than `wrapWidth`) the comparison is against the row's own advance sum, so
    /// an `x` between `wrapWidth` and `rowSpan.width` is `.inRange`. The returned
    /// `columnIndex` is an index into the LOGICAL LINE; `rowSpan.startColumn` bridges the
    /// two frames.
    ///
    /// Adds no search of its own. The vertical half is `visualRowAt` verbatim (its
    /// `.failure`/`.empty` propagate, and its two guards on a malformed
    /// `logicalLine(containingVisualRow:)` override are inherited — this query re-checks
    /// neither); the horizontal half is one `columnIndex(containingOffset:inLine:)`
    /// dispatch on the delegating path only. Cost: O(log totalRows) + O(log lineCount) +
    /// the within-line walk to the located row (zero extra columns scanned on a line that
    /// fits `wrapWidth`, and on any line's last row unless it overflows) + O(log
    /// cells-in-line), with three column-axis probes in the shared per-line ladder, two
    /// per row the walk yields, and one more for the row's left offset when it delegates.
    /// O(1) core memory.
    ///
    /// A non-finite `x` is a failure, not a clamp — `+∞ >= rowSpan.width` and `-∞ < 0`
    /// would both silently clamp — and it is checked before any horizontal work, so a
    /// non-finite `x` costs zero column-metric probes. An empty document is `.empty` even
    /// for a non-finite `x` (the vertical half runs first); a non-finite `x` beats
    /// `.blankLine` (the check runs before the span is read).
    ///
    /// The one failure this query adds of its own: a layout whose
    /// `firstVisualRow`/`visualRowCount` disagrees with node 1's packer, so the walk runs
    /// out before the row it was asked for — `.failure(.invalidVisualRowLayout)` rather
    /// than a fabricated row.
    public static func visualPointAt<Layout: VisualRowLayoutSource>(
        x: Double,
        y: Double,
        layout: Layout
    ) -> VisualPointQuery {
        // Step 1 — the whole vertical ladder, verbatim.
        let row: VisualRowLocation
        switch visualRowAt(y: y, layout: layout) {
        case .failure(let error): return .failure(error)
        case .empty: return .empty
        case .row(let located): row = located
        }

        // Step 2 — before any horizontal work (see the doc comment: this placement is
        // what `WrapPointQueryCountTests`' zero-probe assertion observes).
        if !x.isFinite { return .failure(.nonFiniteValue) }

        // Step 3 — the shared per-line ladder, then the shared within-line walk.
        let line = row.logicalLine
        let count: Int
        let total: Double
        switch validateWrapLine(inLine: line, wrapWidth: layout.wrapWidth, metrics: layout) {
        // .nonPositiveWrapWidth is unreachable here (step 1 validated wrapWidth); mapped
        // through rather than force-unwrapped, as visualRowAt treats its own.
        case .failure(let error): return .failure(error)
        case .valid(let validCount, let validTotal): count = validCount; total = validTotal
        }
        var cursor = VisualRowCursor(
            line: line, columnCount: count, total: total,
            wrapWidth: layout.wrapWidth, metrics: layout)
        // `nil` means exactly one thing here: the walk ran out before row `rowInLine`.
        // Decision 12's short-circuit cannot bypass the detection -- it decides where ONE
        // row ends, so a fitting line asked for row 2 still consumes its single row and
        // fails here.
        guard let rowSpan = advanceVisualRows(&cursor, by: row.rowInLine + 1) else {
            return .failure(.invalidVisualRowLayout)
        }

        // Step 4 — the blank row, read from the span: a second columnCount probe would buy
        // nothing (node 1 returns an end strictly greater than the start for every
        // non-blank line, and a blank line packs to exactly one [0, 0) row).
        if rowSpan.startColumn == rowSpan.endColumn {
            return .point(VisualPointLocation(row: row, rowSpan: rowSpan, column: .blankLine))
        }

        // Steps 5-6 — both clamps, no probe. rowLeft is deliberately NOT read yet.
        if x < 0.0 {
            return .point(VisualPointLocation(
                row: row, rowSpan: rowSpan,
                column: .cell(ColumnLocation(columnIndex: rowSpan.startColumn, clamp: .clampedToLeft))))
        }
        if x >= rowSpan.width {
            return .point(VisualPointLocation(
                row: row, rowSpan: rowSpan,
                column: .cell(ColumnLocation(columnIndex: rowSpan.endColumn - 1, clamp: .clampedToRight))))
        }

        // Step 7 — rebase into the line's frame and dispatch to the provider's hook.
        let rowLeft = layout.columnOffset(inLine: line, column: rowSpan.startColumn)
        let rebased = rowLeft + x
        // Reproduces the answer columnAt's own `x` rung gave for a non-finite interior
        // offset: the ladder validates columnOffset at 0 and count only, so an interior
        // offset is trusted, unvalidated input (the cursor documents the same).
        if !rebased.isFinite { return .failure(.nonFiniteValue) }
        let raw: Int
        if rebased >= total {
            // The hook's precondition is `x < lineWidth` and it does not clamp. On a
            // line's last row, `rowLeft + x` can round up onto `total` even for an x
            // strictly below the row's width (Decision 6, fixture 2). `total` is the
            // ladder's own value -- this guard costs no probe.
            raw = rowSpan.endColumn - 1
        } else {
            raw = layout.columnIndex(containingOffset: rebased, inLine: line)
        }
        // Decision 6: in Double arithmetic the rounding above can also land INSIDE the
        // line but past the row, and the hook then answers with a cell belonging to the
        // NEXT row. Clamp the index into the row's span -- and only the index: `x` was
        // inside [0, rowSpan.width), so the flag stays .inRange. Flipping it would report
        // a right-edge hit for a point in the row's interior.
        let index = min(max(raw, rowSpan.startColumn), rowSpan.endColumn - 1)
        return .point(VisualPointLocation(
            row: row, rowSpan: rowSpan,
            column: .cell(ColumnLocation(columnIndex: index, clamp: .inRange))))
    }
}
```

- [ ] **Step 5: Run the test and the Foundation scan**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryTests 2>&1 | tail -12
FOUNDATION="$(rg -n "Foundation" Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "foundation_scan=empty"; else echo "foundation_scan=DIRTY"; echo "$FOUNDATION"; fi
```

Expected: all seven cases pass; `foundation_scan=empty`.

- [ ] **Step 6: Run the whole suite**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test 2>&1 | tail -5
```

Expected: green, count = 425 (55a's total) + 7.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/WrapPointQuery.swift Tests/TextEngineCoreTests/WrapPointQueryTests.swift
git commit -m "$(cat <<'MSG'
feat: add visualPointAt, the wrap-aware (x,y) -> (row, cell) query

Node 4 proper. Composes visualRowAt over the vertical axis with a rebased
columnIndex dispatch over the horizontal one, through 55a's shared per-line
ladder and within-line walk, so it adds no search of its own.

x is row-relative and both clamps land on the row's edges; the returned index
is line-absolute, with rowSpan.startColumn as the bridge. An overflow row
compares against its own advance sum, so wrapWidth < x < rowSpan.width is a
real in-range point. A non-finite x fails before any horizontal work.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 2: The three pins nothing else in the suite would catch

Spec Testing Strategy (`WrapPointQueryTests`, the two named pins), Decisions 2 and 3. Each is a standing guarantee whose *invocation* is otherwise unguarded — the defect class this repository has now found five times (D-24, D-27, D-29 and slice 54's two drills).

**Files:**
- Modify: `Tests/TextEngineCoreTests/WrapPointQueryTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.visualPointAt(x:y:layout:)` and `ViewportVirtualizer.visualRowAt(y:layout:)` (Task 1).
- Produces: `WrapPointQueryTests.assertIndexInsideItsRowSpan(layout:xs:ys:file:line:)` — Task 3 calls it over Decision 6's fixture 1.

- [ ] **Step 1: Write the three failing pins**

Append inside `final class WrapPointQueryTests` in `Tests/TextEngineCoreTests/WrapPointQueryTests.swift`:

```swift
    /// Every row boundary, every row interior and BOTH clamp edges.
    private func ySweep() -> [Double] {
        var ys: [Double] = [-100.0, -0.001]
        for row in 0..<6 {
            let top = Double(row) * Self.rowHeight
            ys.append(top)                              // exact boundary
            ys.append(top + Self.rowHeight / 2.0)       // interior
            ys.append(top + Self.rowHeight - 0.001)     // just below the next boundary
        }
        ys.append(60.0)                                 // clamped to the bottom
        ys.append(1_000.0)
        return ys
    }

    /// Decision 3's central promise: `row` is `visualRowAt`'s answer, carried verbatim.
    ///
    /// Nothing else in this slice notices a re-derivation — the oracle compares against
    /// `pointAt`, the round-trip against the cursor, the count tests count probes; all
    /// three stay green if the vertical half is rebuilt inside the query. The CLAMP EDGES
    /// are what give this teeth: a fabricated location would most plausibly get the index
    /// right and the flag wrong.
    func testRowIsCarriedVerbatimFromVisualRowAt() {
        let layout = Self.layout()
        var sawTop = false
        var sawBottom = false
        for y in ySweep() {
            guard case .row(let expected) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
                XCTFail("fixture: visualRowAt must locate a row at y=\(y)"); continue
            }
            guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 5.0, y: y, layout: layout) else {
                XCTFail("expected .point at y=\(y)"); continue
            }
            XCTAssertEqual(point.row, expected, "y=\(y)")
            if expected.clamp == .clampedToTop { sawTop = true }
            if expected.clamp == .clampedToBottom { sawBottom = true }
        }
        XCTAssertTrue(sawTop && sawBottom, "the sweep must reach both clamp edges, or the pin has no teeth")
    }

    /// The duplicated fields agree. Named for what this actually catches: with the walk
    /// called at `k = rowInLine + 1`, the last row it consumes carries that `rowInLine` BY
    /// CONSTRUCTION, so the assertion can only fire on a wrong `k` — a plausible edit, and
    /// worth a test, but not evidence that two independently derived numbers agree.
    func testRowSpanAndRowAgreeOnTheirDuplicatedFields() {
        let layout = Self.layout()
        for y in ySweep() {
            guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 5.0, y: y, layout: layout) else {
                XCTFail("expected .point at y=\(y)"); continue
            }
            XCTAssertEqual(point.rowSpan.logicalLine, point.row.logicalLine, "y=\(y)")
            XCTAssertEqual(point.rowSpan.rowInLine, point.row.rowInLine, "y=\(y)")
        }
    }

    /// Decision 2's swept property, and the only test that reads Decision 6's clamp.
    /// Shared so Task 3 can drive it over the FP fixture where the clamp actually fires.
    func assertIndexInsideItsRowSpan<Layout: VisualRowLayoutSource>(
        layout: Layout, xs: [Double], ys: [Double],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for y in ys {
            for x in xs {
                guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: x, y: y, layout: layout) else {
                    XCTFail("expected .point at (x: \(x), y: \(y))", file: file, line: line); continue
                }
                guard case .cell(let cell) = point.column else { continue }  // blank rows have no cell
                XCTAssertGreaterThanOrEqual(cell.columnIndex, point.rowSpan.startColumn,
                                            "(x: \(x), y: \(y)) left the span", file: file, line: line)
                XCTAssertLessThan(cell.columnIndex, point.rowSpan.endColumn,
                                  "(x: \(x), y: \(y)) left the span", file: file, line: line)
            }
        }
    }

    func testTheIndexIsAlwaysInsideItsRowSpan() {
        assertIndexInsideItsRowSpan(
            layout: Self.layout(),
            xs: [-100.0, -0.001, 0.0, 0.001, 4.999, 5.0, 9.999, 10.0, 19.999, 20.0, 25.0, 30.0, 1_000.0],
            ys: ySweep())
    }
```

- [ ] **Step 2: Run them**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryTests 2>&1 | tail -8
```

Expected: green. These three pass on arrival by construction — the query already carries `row` verbatim and already clamps. Their falsifiability evidence is drill (g) below and drill (e) in Task 3, not a red at authoring time.

- [ ] **Step 3: Drill (g) — the verbatim-`row` pin can fail**

Break the query so it rebuilds the location instead of carrying it:

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/TextEngineCore/WrapPointQuery.swift'
s = open(p).read()
old = "        case .row(let located): row = located"
new = ("        case .row(let located): row = VisualRowLocation(\n"
       "            globalRow: located.globalRow, logicalLine: located.logicalLine,\n"
       "            rowInLine: located.rowInLine, clamp: .inRange)   // DRILL (g)")
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapPointQueryTests 2>&1 | tail -12
```

Expected: **RED** — `testRowIsCarriedVerbatimFromVisualRowAt` fails at the clamp edges with a `VisualRowLocation` mismatch on `clamp` (`.inRange` vs `.clampedToTop`), while every non-clamped `y` in the same sweep passes. Record the exact failure line. Note which other tests stay green: `testClampedYCrossedWithEachXBranch` also reddens (it asserts the flag directly) — record both, they are one guard with two readers.

```bash
cd /Users/aabanschikov/swift-text-engine
git checkout -- Sources/TextEngineCore/WrapPointQuery.swift
swift test --filter WrapPointQueryTests 2>&1 | tail -5
```

Expected: green again.

- [ ] **Step 4: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/TextEngineCoreTests/WrapPointQueryTests.swift
git commit -m "$(cat <<'MSG'
test: pin visualPointAt's verbatim row, span property and field agreement

Three pins whose invocation nothing else would catch. The verbatim-row sweep
reaches both clamp edges, where a fabricated location would most plausibly get
the index right and the flag wrong (drill (g): rebuild the location with a
hard-coded .inRange and the sweep reddens at the edges only).

The duplicated-field assertion is named for what it catches -- a wrong k in
advanceVisualRows -- and not counted as evidence that two derivations agree.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 3: Decision 6 — the FP clamp and the `>= total` guard, on two fixtures

Spec Decision 6 (both fixtures, checked by hand there and observed here), Decision 14 (the guard), AC6. Neither fixture subsumes the other: the three-advance one puts the rounding strictly INSIDE the line so the clamp is what saves the answer; the two-advance one puts it at the line's END so the guard is.

**Files:**
- Modify: `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift` (+`ColumnHookLog`, +`OverridingColumnIndexLayout`)
- Modify: `Tests/TextEngineCoreTests/WrapPointQueryTests.swift`

**Interfaces:**
- Produces: `ColumnHookLog` (records every `columnIndex(containingOffset:inLine:)` dispatch) and `OverridingColumnIndexLayout` (a `TestVisualRowLayout` whose column-inverse hook is overridden with the CORRECT answer and every call logged) — Task 5's count fixture 2 uses both.

- [ ] **Step 1: Add the overriding-column-hook conformer**

Append to `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift`:

```swift
/// Records every `columnIndex(containingOffset:inLine:)` dispatch made through an
/// `OverridingColumnIndexLayout`.
final class ColumnHookLog {
    var offsets: [Double] = []
    var lines: [Int] = []
    var callCount: Int { offsets.count }
}

/// A `TestVisualRowLayout` whose COLUMN-inverse hook is overridden with the correct
/// answer, every call logged. The mirror of `OverridingLogicalLineLayout` on the other
/// axis, and needed for the same two reasons (slice 55 spec, Testing Strategy): only an
/// overriding conformer can count "exactly one `columnIndex` call", and only an
/// overriding conformer can show ZERO calls on a path that must not dispatch — the
/// default hook's probes are indistinguishable from the ladder's own.
struct OverridingColumnIndexLayout: VisualRowLayoutSource {
    let base: TestVisualRowLayout
    let log: ColumnHookLog

    var lineCount: Int { base.lineCount }
    var rowHeight: Double { base.rowHeight }
    var wrapWidth: Double { base.wrapWidth }
    func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
    func columnOffset(inLine line: Int, column: Int) -> Double { base.columnOffset(inLine: line, column: column) }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { base.canBreak(beforeColumn: column, inLine: line) }
    func visualRowCount(inLine line: Int) -> Int { base.visualRowCount(inLine: line) }
    func firstVisualRow(ofLine line: Int) -> Int { base.firstVisualRow(ofLine: line) }
    func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
        log.offsets.append(x)
        log.lines.append(line)
        return base.columnIndex(containingOffset: x, inLine: line)
    }
}
```

- [ ] **Step 2: Write the two fixture tests**

Append inside `final class WrapPointQueryTests`:

```swift
    // ---- Decision 6: Double arithmetic at magnitudes near 2^53 ----
    //
    // `rowSpan.width` is itself the rounded difference `columnOffset(end) - rowLeft`, so
    // an `x` STRICTLY below that difference can rebase to a value that rounds up to
    // `columnOffset(end)` or beyond. ulp is 2 at 1e16: every offset below is exactly
    // representable and strictly increasing, so these are legal inputs, and
    // `1e16 + 3.9` rounds to exactly `1e16 + 4`.

    /// Fixture 1 — the rounding lands INSIDE the line, so the hook answers with a cell
    /// belonging to the NEXT row and only the clamp confines it.
    ///
    ///   advances [1e16, 4, 4] -> offsets [0, 1e16, 1e16+4, 1e16+8], breaks before 1 and 2
    ///   wrapWidth 4:  row 0 = [0,1) (overflow), row 1 = [1,2) rowLeft 1e16 width 4,
    ///                 row 2 = [2,3)
    private static func fpClampLayout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [(advances: [1e16, 4.0, 4.0], breaks: [1, 2])],
            rowHeight: rowHeight, wrapWidth: 4.0)
    }

    /// Fixture 2 — drop the third advance and the rounding lands on the LINE's width, so
    /// Decision 14's `>= total` guard answers and the hook is never called (calling it
    /// would violate its `x < lineWidth` precondition).
    ///
    ///   advances [1e16, 4] -> offsets [0, 1e16, 1e16+4], break before 1
    ///   wrapWidth 4:  row 0 = [0,1) (overflow), row 1 = [1,2) rowLeft 1e16 width 4
    private static func fpGuardLayout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [(advances: [1e16, 4.0], breaks: [1])],
            rowHeight: rowHeight, wrapWidth: 4.0)
    }

    func testFixtureOneRoundsPastTheRowAndTheClampConfinesTheIndex() {
        let layout = Self.fpClampLayout()

        // The fixture must actually be the FP case, or this test proves nothing.
        XCTAssertEqual(layout.firstVisualRow(ofLine: 1), 3, "fixture: three rows")
        XCTAssertEqual(1e16 + 3.9, 1e16 + 4.0, "fixture: 3.9 must round up at this magnitude")
        XCTAssertEqual(layout.columnIndex(containingOffset: 1e16 + 3.9, inLine: 0), 2,
                       "the UNCLAMPED hook answers cell 2 -- outside row 1's [1, 2) span")

        // y = 15 -> global row 1 (rowHeight 10). x = 3.9 < rowSpan.width == 4.
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 3.9, y: 15.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 1, endColumn: 2, width: 4.0))
        // The clamp moves the INDEX and not the FLAG: x was inside [0, width), so a
        // right-edge report would be a different wrong answer.
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 1, clamp: .inRange)))
    }

    func testFixtureTwoAnswersFromTheTotalGuardWithoutCallingTheHook() {
        let log = ColumnHookLog()
        let layout = OverridingColumnIndexLayout(base: Self.fpGuardLayout(), log: log)

        XCTAssertEqual(layout.firstVisualRow(ofLine: 1), 2, "fixture: two rows")

        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 3.9, y: 15.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 1, endColumn: 2, width: 4.0))
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 1, clamp: .inRange)))
        XCTAssertEqual(log.callCount, 0,
                       "rebased == total: the guard must answer, and the hook must not be called at x == lineWidth")
    }

    /// The swept property over the FP fixture — this is where drill (e) reddens it.
    func testTheIndexIsAlwaysInsideItsRowSpanOnTheFPFixture() {
        assertIndexInsideItsRowSpan(
            layout: Self.fpClampLayout(),
            xs: [-1.0, 0.0, 1e15, 3.9, 3.999, 4.0, 5.0],
            ys: [-1.0, 5.0, 15.0, 25.0, 100.0])
    }
```

- [ ] **Step 3: Run them**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryTests 2>&1 | tail -8
```

Expected: green. **If `testFixtureOneRoundsPastTheRowAndTheClampConfinesTheIndex` shows the unclamped hook answering `1` rather than `2`, the fixture does not fire** — spec Decision 6 says what to do then: remove the clamp from `WrapPointQuery.swift`, document the property as resting on the `columnOffset` contract instead, and record the decision. Do not keep an unreachable branch with an untestable claim.

- [ ] **Step 4: Drill (e) — the clamp can fail**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/TextEngineCore/WrapPointQuery.swift'
s = open(p).read()
old = "        let index = min(max(raw, rowSpan.startColumn), rowSpan.endColumn - 1)"
new = "        let index = raw   // DRILL (e)"
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapPointQueryTests 2>&1 | tail -14
git checkout -- Sources/TextEngineCore/WrapPointQuery.swift
```

Expected: **RED** in `testTheIndexIsAlwaysInsideItsRowSpanOnTheFPFixture` (`2 is not less than 2` — the index left the span at `x = 3.9`) and in `testFixtureOneRoundsPastTheRowAndTheClampConfinesTheIndex`, while the ordinary-fixture sweep stays green. Record both failure lines and the fact that the non-FP sweep does not move — that asymmetry is the reason the FP fixture exists.

- [ ] **Step 5: Drill (k) — the `>= total` guard can fail**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/TextEngineCore/WrapPointQuery.swift'
s = open(p).read()
old = """        let raw: Int
        if rebased >= total {"""
new = """        let raw: Int
        if false {   // DRILL (k)"""
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapPointQueryTests 2>&1 | tail -12
git checkout -- Sources/TextEngineCore/WrapPointQuery.swift
swift test --filter WrapPointQueryTests 2>&1 | tail -5
```

Expected: **RED** in `testFixtureTwoAnswersFromTheTotalGuardWithoutCallingTheHook` (`XCTAssertEqual failed: ("1") is not equal to ("0")` — the hook was called at `x == lineWidth`, violating its precondition), while fixture 1 stays **green** (its rounding lands inside the line, so the guard was never the thing answering there). Record both halves. Then green again after the revert.

Note: a Swift compiler warning on `if false` is expected and harmless; the drill is reverted, never committed.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift Tests/TextEngineCoreTests/WrapPointQueryTests.swift
git commit -m "$(cat <<'MSG'
test: pin Decision 6's FP clamp and Decision 14's >= total guard

Two fixtures at 1e16, where ulp is 2 and an x strictly below the row's width
rebases onto the next cell's offset. Fixture 1 puts that rounding inside the
line, so the hook answers a cell outside the row and only the clamp confines
it (drill (e)); fixture 2 puts it on the line's width, so the guard answers
and the hook is never called at x == lineWidth (drill (k)). Neither subsumes
the other, and each drill leaves the other fixture green.

Adds OverridingColumnIndexLayout, the column-axis mirror of
OverridingLogicalLineLayout, which Task 5's dispatch counts also need.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 4: The validation ladder and the three malformed-provider cases

Spec Decision 5 (rung by rung and both structural precedence pairs), Decision 4 (the guards live at the producers), AC5. **No guard is added to `WrapPointQuery.swift` in this task** — if a case here needs one, it has been placed in the wrong file.

**Files:**
- Create: `Tests/TextEngineCoreTests/WrapPointQueryValidationTests.swift`

**Interfaces:**
- Consumes: `RiggedVisualRowLayout`, `TestVisualRowLayout`, `OverridingLogicalLineLayout`, `HookLog` (`VisualRowLayoutTestSupport.swift`).

- [ ] **Step 1: Write the suite**

Create `Tests/TextEngineCoreTests/WrapPointQueryValidationTests.swift`:

```swift
import XCTest
import TextEngineCore

/// `visualPointAt`'s ladder, rung by rung (slice 55 spec, Decision 5), plus the three
/// ways a provider can be malformed. Every one of these outcomes is produced by code that
/// lives OUTSIDE this query: the vertical rungs and the two hook guards are
/// `visualRowAt`'s, the column rungs are `validateWrapLine`'s, and the helper's `k <= 0`
/// rule is `advanceVisualRows`'. This suite pins that they surface here unchanged.
final class WrapPointQueryValidationTests: XCTestCase {
    private static let rowHeight = 10.0
    private static let wrapWidth = 20.0

    /// Two lines x 2 rows at width 20 (4 cells of 10, breakable everywhere):
    /// firstVisualRow [0, 2, 4], total height 40.
    private static func good() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: Array(repeating: (advances: Array(repeating: 10.0, count: 4), breaks: Set([1, 2, 3])), count: 2),
            rowHeight: rowHeight, wrapWidth: wrapWidth)
    }

    private static func blankLineLayout() -> TestVisualRowLayout {
        TestVisualRowLayout(lines: [(advances: [], breaks: [])], rowHeight: rowHeight, wrapWidth: wrapWidth)
    }

    private static func rigged(lineCount: Int, rowHeight: Double, wrapWidth: Double, firstRow: [Int]) -> RiggedVisualRowLayout {
        RiggedVisualRowLayout(lineCount: lineCount, rowHeight: rowHeight, wrapWidth: wrapWidth, firstRow: firstRow)
    }

    /// A layout whose ROW axis is sound and whose COLUMN metrics are not — the class the
    /// per-line ladder rejects. Only the queried accessor lies; `TestVisualRowLayout`
    /// packed its prefix sum from the honest metrics.
    private struct BrokenColumnLayout: VisualRowLayoutSource {
        let base: TestVisualRowLayout
        let negativeCount: Bool
        let offsetBias: Double

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int { negativeCount ? -1 : base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double { base.columnOffset(inLine: line, column: column) + offsetBias }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { base.canBreak(beforeColumn: column, inLine: line) }
        func visualRowCount(inLine line: Int) -> Int { base.visualRowCount(inLine: line) }
        func firstVisualRow(ofLine line: Int) -> Int { base.firstVisualRow(ofLine: line) }
    }

    // ---- The vertical rungs, propagated verbatim from visualRowAt ----

    func testNegativeLineCountFails() {
        let layout = Self.rigged(lineCount: -1, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .failure(.negativeLineCount))
    }

    func testNonFiniteYBeatsTheEmptyDocument() {
        let layout = Self.rigged(lineCount: 0, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: .nan, layout: layout), .failure(.nonFiniteValue))
    }

    func testEmptyDocumentIsEmpty() {
        let layout = Self.rigged(lineCount: 0, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .empty)
    }

    /// Precedence pair 1 (Decision 5). `x` is examined only after the vertical half, so an
    /// empty document answers `.empty` even for a non-finite `x` — matching `pointAt`,
    /// whose doc comment states the same outcome for the same reason.
    func testEmptyDocumentBeatsANonFiniteX() {
        let layout = Self.rigged(lineCount: 0, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: .infinity, y: 1.0, layout: layout), .empty)
    }

    func testNonPositiveRowHeightFails() {
        let layout = Self.rigged(lineCount: 1, rowHeight: 0.0, wrapWidth: Self.wrapWidth, firstRow: [0, 1])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .failure(.nonPositiveRowHeight))
    }

    func testNonPositiveWrapWidthFails() {
        let layout = Self.rigged(lineCount: 1, rowHeight: Self.rowHeight, wrapWidth: 0.0, firstRow: [0, 1])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .failure(.nonPositiveWrapWidth))
    }

    func testMalformedPrefixSumFails() {
        let layout = Self.rigged(lineCount: 2, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [1, 2, 3])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .failure(.invalidVisualRowLayout))
    }

    // ---- The x rung: a non-finite coordinate is a failure, not a clamp ----

    /// Both signs, named separately: WITHOUT this rung each reaches a DIFFERENT clamp
    /// branch (`+∞ >= rowSpan.width` and `-∞ < 0` are both true), so one test cannot stand
    /// for the other.
    func testPositiveInfinityXFailsRatherThanClampingRight() {
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: .infinity, y: 5.0, layout: Self.good()),
                       .failure(.nonFiniteValue))
    }

    func testNegativeInfinityXFailsRatherThanClampingLeft() {
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: -.infinity, y: 5.0, layout: Self.good()),
                       .failure(.nonFiniteValue))
    }

    func testNaNXFails() {
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: .nan, y: 5.0, layout: Self.good()),
                       .failure(.nonFiniteValue))
    }

    /// Precedence pair 2 (Decision 5): the `x` rung runs before the span is read, exactly
    /// as `columnAt` checks `x` before its `count == 0` short-circuit.
    func testNonFiniteXBeatsTheBlankLine() {
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: .infinity, y: 5.0, layout: Self.blankLineLayout()),
                       .failure(.nonFiniteValue))
        // Control: with a finite x the same layout answers .blankLine.
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: Self.blankLineLayout()) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.column, .blankLine)
    }

    // ---- The column rungs, surfacing at the top level ----

    func testNegativeColumnCountSurfaces() {
        let layout = BrokenColumnLayout(base: Self.good(), negativeCount: true, offsetBias: 0.0)
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: layout),
                       .failure(.negativeColumnCount))
    }

    func testNonZeroFirstColumnOffsetSurfaces() {
        let layout = BrokenColumnLayout(base: Self.good(), negativeCount: false, offsetBias: 5.0)
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: layout),
                       .failure(.invalidColumnMetrics))
    }

    // ---- The three malformed-provider cases (Decision 4) ----

    /// Case 1, at THREE values. The boundary (`== lineCount`) does not trap at the named
    /// site, so a test carrying only the upper value leaves it unpinned; a negative value
    /// is what an edit to `logicalLine < lineCount` alone lets through.
    func testAnOutOfRangeLogicalLineOverrideFails() {
        for answer in [3, 2, -1] {           // lineCount == 2: above, at the boundary, below
            let base = Self.good()
            let log = HookLog()
            let layout = OverridingLogicalLineLayout(base: base, log: log, answer: { _ in answer })
            XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: layout),
                           .failure(.invalidVisualRowLayout), "answer=\(answer)")
            XCTAssertEqual(log.logicalLineCalls.count, 1, "answer=\(answer): the hook is consulted once")
        }
    }

    /// Case 2: an IN-RANGE line whose `firstVisualRow` exceeds the located row, so
    /// `rowInLine` goes negative. Global row 0 answered as line 1 (firstVisualRow 2)
    /// gives rowInLine -2.
    func testAnInRangeOverrideThatMakesRowInLineNegativeFails() {
        let base = Self.good()
        let layout = OverridingLogicalLineLayout(base: base, log: HookLog(), answer: { _ in 1 })
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout),
                       .failure(.invalidVisualRowLayout))
    }

    /// Case 3 — the ONLY failure this query adds of its own: a layout whose row counts
    /// disagree with node 1's packer, so the walk runs out before the row it was asked
    /// for. `RiggedVisualRowLayout`'s stubbed column metrics describe a blank line (one
    /// packed row) while its prefix sum claims three.
    func testAWalkThatExhaustsEarlyFails() {
        let layout = Self.rigged(lineCount: 1, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0, 3])

        // Control: row 0 exists in the packer's world and answers normally, so the failure
        // below is the WALK and not the fixture.
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: layout) else {
            return XCTFail("expected .point at the line's only packed row")
        }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 0, logicalLine: 0, rowInLine: 0, clamp: .inRange))
        XCTAssertEqual(point.column, .blankLine)

        // Row 2 is claimed by the prefix sum and never produced by the packer.
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 25.0, layout: layout),
                       .failure(.invalidVisualRowLayout))
    }
}
```

- [ ] **Step 2: Run the suite**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryValidationTests 2>&1 | tail -8
```

Expected: green — every outcome is produced by code 55a already shipped. The reds are the three drills below.

- [ ] **Step 3: Drill (d1) — remove `visualRowAt`'s range check (guard 1)**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/TextEngineCore/WrapPositionQuery.swift'
s = open(p).read()
old = """            if logicalLine < 0 || logicalLine >= layout.lineCount {
                return .failure(.invalidVisualRowLayout)
            }"""
new = "            // DRILL (d1): guard 1 removed"
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapPointQueryValidationTests 2>&1 | tail -12
git checkout -- Sources/TextEngineCore/WrapPositionQuery.swift
```

Expected: **a trap, not an assertion failure** — the test process aborts with `Fatal error: Index out of range` inside `TestVisualRowLayout.firstVisualRow(ofLine:)`, reached from `WrapPositionQuery.swift`, on `answer = 3`. Record the abort line and the non-zero exit. This is the red that shows the query's trap-freedom is **inherited**, not re-derived: no code in `WrapPointQuery.swift` changed.

Note: run it against `answer = 3` (the value above `lineCount`), not the boundary — the boundary's unguarded outcome is a trap elsewhere or a fabricated row, which is a different observation.

- [ ] **Step 4: Drill (d2) — remove the producer's `rowInLine < 0` check AND the helper's `k <= 0` rule**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
q = 'Sources/TextEngineCore/WrapPositionQuery.swift'
s = open(q).read()
old = """            if rowInLine < 0 {
                return .failure(.invalidVisualRowLayout)
            }"""
assert old in s
open(q, 'w').write(s.replace(old, "            // DRILL (d2): guard 2 removed"))

h = 'Sources/TextEngineCore/DocumentVisualRowCursor.swift'
t = open(h).read()
old2 = "    if k <= 0 { return nil }"
assert old2 in t
open(h, 'w').write(t.replace(old2, "    // DRILL (d2): the k <= 0 rule removed"))
PY
swift test --filter WrapPointQueryValidationTests 2>&1 | tail -12
git checkout -- Sources/TextEngineCore/WrapPositionQuery.swift Sources/TextEngineCore/DocumentVisualRowCursor.swift
```

Expected: **a trap** — `Fatal error: Range requires lowerBound <= upperBound` inside `advanceVisualRows`, from `testAnInRangeOverrideThatMakesRowInLineNegativeFails` (`rowInLine == -2`, so `k == -1`). Record it. **Both** edits are required: with the helper's rule intact the query returns `.failure` and stays green, which is the layering Decision 4 claims — the producer guard is the repair, the helper's rule the backstop.

- [ ] **Step 5: Drill (d3) — remove the walk's exhaustion check**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/TextEngineCore/WrapPointQuery.swift'
s = open(p).read()
old = """        guard let rowSpan = advanceVisualRows(&cursor, by: row.rowInLine + 1) else {
            return .failure(.invalidVisualRowLayout)
        }"""
new = "        let rowSpan = advanceVisualRows(&cursor, by: row.rowInLine + 1)!   // DRILL (d3)"
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapPointQueryValidationTests 2>&1 | tail -12
git checkout -- Sources/TextEngineCore/WrapPointQuery.swift
swift test --filter WrapPointQueryValidationTests 2>&1 | tail -5
```

Expected: **a trap** — `Fatal error: Unexpectedly found nil while unwrapping an Optional value` from `testAWalkThatExhaustsEarlyFails`. Record it, then confirm green after the revert.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/TextEngineCoreTests/WrapPointQueryValidationTests.swift
git commit -m "$(cat <<'MSG'
test: pin visualPointAt's ladder and the three malformed-provider cases

Every rung, both structural precedence pairs (.empty beats a non-finite x; a
non-finite x beats .blankLine), +inf and -inf named separately because without
the rung each reaches a different clamp branch, and the three ways a provider
can be malformed -- the out-of-range hook answer at three values, the in-range
answer that makes rowInLine negative, and the row counts that disagree with the
packer so the walk exhausts.

No guard is added to the query: drills (d1) and (d2) remove the producers'
guards and this suite TRAPS, which is what shows the trap-freedom is inherited.
(d3) removes the one failure the query does add and it traps too.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 5: The probe-count table, on two counters and two fixtures — and D-25

Spec Contract 55b (the probe table), Component Design, Testing Strategy (`WrapPointQueryCountTests`), AC7 and AC11. The four quantities **cannot share one harness**: the row-axis search is structurally invisible to a counting layout wrapper (`visualRowAt` builds its `UniformLineMetrics` inside the core), and "exactly one hook call" can only be counted by a conformer that OVERRIDES the hook — which the probe-bound fixture must not, or the default search's probes stop reaching the counter.

**Files:**
- Create: `Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift`
- Modify: `Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift` (D-25)

- [ ] **Step 1: Write the count suite**

Create `Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift`:

```swift
import XCTest
import TextEngineCore

/// The probe table of the slice-55 spec's Contract 55b. Two counters and two fixtures,
/// because the four quantities cannot share one harness (Testing Strategy):
///
///  * Counter 1, the LAYOUT axis (`firstVisualRow` + `visualRowCount`): node 3's constant
///    `<= ceilLog2(lineCount) + 4`, unchanged and still tight, because node 4 adds NO
///    layout-axis probe. Never `ceilLog2(totalRows)` — the row-axis search touches no
///    provider (`UniformLineMetrics.offset` is arithmetic), so such a term would count
///    nothing and hand slack to a regression. It is pinned where it IS observable, by
///    `LineAtQueryCountTests`.
///  * Counter 2, the COLUMN axis (`columnCount` + `columnOffset` + `canBreak`).
///  * Fixture 1 does NOT override either inverse hook, so the default searches run
///    against the wrapper and their probes are counted.
///  * Fixture 2 OVERRIDES both, which is the only way to count "exactly one dispatch" —
///    and the reason it cannot double as fixture 1.
final class WrapPointQueryCountTests: XCTestCase {
    private final class ProbeCounter {
        var firstVisualRowCalls = 0
        var visualRowCountCalls = 0
        var columnCountCalls = 0
        var columnOffsetCalls = 0
        var canBreakCalls = 0
        var logicalLineDispatches = 0
        var columnIndexDispatches = 0

        /// Summed, exactly as node 3 sums its two fields: a bound pinned to one accessor
        /// goes blind to a scan that walks the document through the other.
        var layoutCalls: Int { firstVisualRowCalls + visualRowCountCalls }
        var columnCalls: Int { columnCountCalls + columnOffsetCalls + canBreakCalls }
    }

    /// Fixture 1 — counts both axes, overrides neither hook.
    private struct CountingLayout: VisualRowLayoutSource {
        let base: TestVisualRowLayout
        let counter: ProbeCounter

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int {
            counter.columnCountCalls += 1; return base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.columnOffsetCalls += 1; return base.columnOffset(inLine: line, column: column)
        }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
            counter.canBreakCalls += 1; return base.canBreak(beforeColumn: column, inLine: line)
        }
        func visualRowCount(inLine line: Int) -> Int {
            counter.visualRowCountCalls += 1; return base.visualRowCount(inLine: line)
        }
        func firstVisualRow(ofLine line: Int) -> Int {
            counter.firstVisualRowCalls += 1; return base.firstVisualRow(ofLine: line)
        }
    }

    /// Fixture 2 — counts both axes AND overrides both inverse hooks with the correct
    /// answers, forwarding to `base` so the hooks' own probes are not counted.
    private struct CountingOverridingLayout: VisualRowLayoutSource {
        let base: TestVisualRowLayout
        let counter: ProbeCounter

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int {
            counter.columnCountCalls += 1; return base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.columnOffsetCalls += 1; return base.columnOffset(inLine: line, column: column)
        }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
            counter.canBreakCalls += 1; return base.canBreak(beforeColumn: column, inLine: line)
        }
        func visualRowCount(inLine line: Int) -> Int {
            counter.visualRowCountCalls += 1; return base.visualRowCount(inLine: line)
        }
        func firstVisualRow(ofLine line: Int) -> Int {
            counter.firstVisualRowCalls += 1; return base.firstVisualRow(ofLine: line)
        }
        func logicalLine(containingVisualRow g: Int) -> Int {
            counter.logicalLineDispatches += 1; return base.logicalLine(containingVisualRow: g)
        }
        func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
            counter.columnIndexDispatches += 1; return base.columnIndex(containingOffset: x, inLine: line)
        }
    }

    // Identical to the seven existing *QueryCountTests — same helper, same shape.
    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value { capacity <<= 1; power += 1 }
        return power
    }

    private static let lineCount = 1_024
    private static let rowHeight = 16.0
    private var expectedMax: Int { ceilLog2(Self.lineCount) + 4 }

    /// 1024 lines, one 8-wide cell each, at ∞ — one row per line, and the line FITS, so
    /// the packer short-circuits and the exact column counts below are the `3 + 2` of the
    /// spec's table.
    private static func fittingLines() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: Array(repeating: (advances: [8.0], breaks: Set<Int>()), count: lineCount),
            rowHeight: rowHeight, wrapWidth: .infinity)
    }

    /// One line of 4 cells x 10 at ∞ — the fitting-line fixture for the exact counts,
    /// small enough that the numbers are read rather than bounded.
    private static func oneFittingLine() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [(advances: Array(repeating: 10.0, count: 4), breaks: Set([1, 2, 3]))],
            rowHeight: rowHeight, wrapWidth: .infinity)
    }

    /// One line of 100 cells x 10 at width 50 — 5 cells per row, 20 rows. Char-wrap, so
    /// every interior column is a break opportunity and an interior row genuinely scans.
    private static func wrappedLine() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [(advances: Array(repeating: 10.0, count: 100), breaks: Set(1..<100))],
            rowHeight: rowHeight, wrapWidth: 50.0)
    }

    // ---- Counter 1: the layout axis ----

    func testLayoutAxisStaysLogarithmicInLineCount() {
        let counter = ProbeCounter()
        let layout = CountingLayout(base: Self.fittingLines(), counter: counter)
        guard case .point = ViewportVirtualizer.visualPointAt(
            x: 4.0, y: 700.0 * Self.rowHeight + 3.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        // node 3's constant, copied and NOT widened: 2 ladder probes + <= ceilLog2 + 1
        // inside the default logicalLine search + 1 for the rowInLine subtraction.
        XCTAssertLessThanOrEqual(counter.layoutCalls, expectedMax)
    }

    func testClampedQueriesDoNotWidenTheLayoutBound() {
        for y in [-1.0, Double(Self.lineCount) * Self.rowHeight + 1.0] {
            let counter = ProbeCounter()
            let layout = CountingLayout(base: Self.fittingLines(), counter: counter)
            guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 4.0, y: y, layout: layout) else {
                return XCTFail("expected .point at y=\(y)")
            }
            XCTAssertNotEqual(point.row.clamp, .inRange, "y=\(y) must clamp")
            XCTAssertLessThanOrEqual(counter.layoutCalls, expectedMax, "y=\(y)")
        }
    }

    // ---- Counter 2: zero column-metric calls on every non-located path ----
    //
    // This is the ONLY observation of the `x` rung's PLACEMENT rather than its result: an
    // implementation that checked `x` after the walk would pass the ±∞ result tests
    // unchanged, and the walk is the expensive half.

    func testEmptyDocumentTouchesNoColumnMetrics() {
        let counter = ProbeCounter()
        let layout = CountingLayout(
            base: TestVisualRowLayout(lines: [], rowHeight: Self.rowHeight, wrapWidth: .infinity),
            counter: counter)
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .empty)
        XCTAssertEqual(counter.columnCalls, 0)
    }

    func testVerticalFailureTouchesNoColumnMetrics() {
        let counter = ProbeCounter()
        let layout = CountingLayout(base: Self.oneFittingLine(), counter: counter)
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: .nan, layout: layout),
                       .failure(.nonFiniteValue))
        XCTAssertEqual(counter.columnCalls, 0)
    }

    func testNonFiniteXTouchesNoColumnMetrics() {
        for x in [Double.infinity, -.infinity, .nan] {
            let counter = ProbeCounter()
            let layout = CountingLayout(base: Self.oneFittingLine(), counter: counter)
            XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: x, y: 5.0, layout: layout),
                           .failure(.nonFiniteValue), "x=\(x)")
            XCTAssertEqual(counter.columnCalls, 0,
                           "x=\(x): the x rung must run BEFORE any horizontal work")
        }
    }

    // ---- Counter 2: the exact counts on a fitting line ----

    func testFittingLineClampedCostsThreePlusTwo() {
        let counter = ProbeCounter()
        let layout = CountingOverridingLayout(base: Self.oneFittingLine(), counter: counter)
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: -1.0, y: 5.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft)))
        // 3 in the shared ladder (columnCount, columnOffset(0), columnOffset(count))
        // + 2 in the one row the cursor yields (its start and end offsets).
        // Nothing for Decision 12's predicate or Decision 14's guard: both read stored
        // values. Nothing for rowLeft: a clamped x never reads it.
        XCTAssertEqual(counter.columnCalls, 5)
        XCTAssertEqual(counter.columnIndexDispatches, 0, "a clamped x must not dispatch")
        XCTAssertEqual(counter.logicalLineDispatches, 1)
    }

    func testFittingLineDelegatingCostsThreePlusTwoPlusOneAndOneDispatch() {
        let counter = ProbeCounter()
        let layout = CountingOverridingLayout(base: Self.oneFittingLine(), counter: counter)
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 15.0, y: 5.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 1, clamp: .inRange)))
        XCTAssertEqual(counter.columnCalls, 6, "3 ladder + 2 row + 1 rowLeft")
        XCTAssertEqual(counter.columnIndexDispatches, 1, "exactly one dispatch through the provider hook")
        XCTAssertEqual(counter.logicalLineDispatches, 1)
    }

    // ---- Counter 2: growth with rowInLine, as a LOWER bound ----

    /// "Strictly more" is not enough: it passes on a growth of one probe, and that is
    /// D-25's shape. The bound is the cells the scan MUST pay for the rows between the two
    /// samples — `endColumn(k + m) − endColumn(k)`. On a uniform fixture that equals the
    /// start-column distance, which is why the phrasing matters: the quantity is the END
    /// columns.
    func testColumnCostGrowsWithTheRowInLine() {
        let base = Self.wrappedLine()
        // Fixture guards. The line must EXCEED the width (a fitting line has one row and
        // no growth), and neither sampled row may be its last (a last row packs in O(1),
        // so the test would measure one row less than its name says).
        XCTAssertEqual(base.visualRowCount(inLine: 0), 20, "fixture: the line must wrap into 20 rows")

        func columnCalls(atRow rowInLine: Int) -> Int {
            let counter = ProbeCounter()
            let layout = CountingLayout(base: base, counter: counter)
            let y = Double(rowInLine) * Self.rowHeight + Self.rowHeight / 2.0
            guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 5.0, y: y, layout: layout) else {
                XCTFail("expected .point at rowInLine=\(rowInLine)"); return 0
            }
            XCTAssertEqual(point.row.rowInLine, rowInLine)
            return counter.columnCalls
        }

        let near = 2
        let far = 10
        XCTAssertLessThan(far, 19, "neither sample may be the line's last row")
        // Rows are [5j, 5j+5): endColumn(10) − endColumn(2) = 55 − 15 = 40 cells the walk
        // must scan between the two samples.
        let mustScan = 55 - 15
        XCTAssertGreaterThanOrEqual(columnCalls(atRow: far) - columnCalls(atRow: near), mustScan)
    }
}
```

- [ ] **Step 2: Run it**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryCountTests 2>&1 | tail -10
```

Expected: green. If either exact count is off by a probe, **do not widen the assertion** — read the ladder and find the extra probe; the exact numbers are what pin Decision 13 as bought and Decisions 12 and 14 as free.

- [ ] **Step 3: Drill (h) — the `x` rung's PLACEMENT can fail**

Move step 2 after the walk:

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/TextEngineCore/WrapPointQuery.swift'
s = open(p).read()
rung = "        if !x.isFinite { return .failure(.nonFiniteValue) }\n"
assert s.count(rung) == 1
s = s.replace(rung, "", 1)
anchor = """        if rowSpan.startColumn == rowSpan.endColumn {"""
assert anchor in s
s = s.replace(anchor, "        if !x.isFinite { return .failure(.nonFiniteValue) }   // DRILL (h)\n\n" + anchor, 1)
open(p, 'w').write(s)
PY
swift test --filter WrapPointQueryCountTests 2>&1 | tail -10
swift test --filter WrapPointQueryValidationTests 2>&1 | tail -5
git checkout -- Sources/TextEngineCore/WrapPointQuery.swift
```

Expected: `testNonFiniteXTouchesNoColumnMetrics` is **RED** (`("5") is not equal to ("0")` — the ladder and the row were paid for before `x` was looked at), while `WrapPointQueryValidationTests` stays **entirely green**, including both `±∞` cases. Record both halves: that asymmetry is the whole reason the placement pin exists beside the result tests.

- [ ] **Step 4: Drill (i) — the growth bound can fail where "strictly more" would pass**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/TextEngineCore/VisualRowCursor.swift'
s = open(p).read()
old = """        if total - startOffset <= wrapWidth { return columnCount }
        var lastFitting = -1   // largest legal end seen that fits"""
new = """        if total - startOffset <= wrapWidth { return columnCount }
        // DRILL (i): one probe per ROW instead of one per cell (throwaway; correct only
        // on a uniform char-wrap fixture, which is why this drill is run --filter-scoped).
        let advance = metrics.columnOffset(inLine: line, column: start + 1) - startOffset
        let fits = Int(wrapWidth / advance)
        return min(columnCount, start + max(1, fits))
        var lastFitting = -1   // largest legal end seen that fits"""
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapPointQueryCountTests 2>&1 | tail -12
git checkout -- Sources/TextEngineCore/VisualRowCursor.swift
swift test --filter WrapPointQueryCountTests 2>&1 | tail -5
```

Expected: `testColumnCostGrowsWithTheRowInLine` is **RED** — the observed difference is around 24, which is greater than zero (so a bare "strictly more" assertion would have **passed**) and below the 40-cell lower bound. **Record both numbers**, the observed difference and the bound: that gap is what the drill demonstrates. Compiler warnings about unreachable code after the early `return` are expected; the drill is never committed. Then green after the revert.

- [ ] **Step 5: D-25 — tighten the redundant bound**

`WrapRowQueryCountTests.testProbeCountDoesNotGrowLinearlyWithTheDocument` asserts `totalCalls < lineCount / 10` (102) while its sibling asserts `<= ceilLog2(lineCount) + 4` (14) on the same fixture and the same located branch. The two probe different `y`, so they are not formally nested, but no independent failure mode is on record. Keep the second target — search depth genuinely varies by target, and the sibling's own comment records 13 at one target and 14 at another — and hold it to the **tight** bound.

Replace, in `Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift`:

```swift
    func testProbeCountDoesNotGrowLinearlyWithTheDocument() {
        let (layout, counter) = counting()
        guard case .row = ViewportVirtualizer.visualRowAt(y: 1_000.0 * Self.rowHeight + 3.0, layout: layout) else {
            return XCTFail("expected .row")
        }
        // A linear walk over 1024 lines would blow this by two orders of magnitude.
        XCTAssertLessThan(counter.totalCalls, Self.lineCount / 10)
    }
```

With:

```swift
    /// A SECOND search target, held to the same TIGHT bound (D-25, discharged in slice
    /// 55b). It used to assert `< lineCount / 10` — 102 against a sibling's 14 on the same
    /// fixture and the same located branch — so no implementation could fail it without
    /// the sibling failing first; the review recorded it as redundant rather than
    /// un-failable. What it can now claim that its sibling cannot: binary-search depth
    /// varies by target (the sibling measures 13 at row 700, this one row 1000), so a
    /// regression that only lengthens the search for adversarial targets is visible here.
    func testASecondSearchTargetHoldsTheSameTightBound() {
        let (layout, counter) = counting()
        guard case .row = ViewportVirtualizer.visualRowAt(y: 1_000.0 * Self.rowHeight + 3.0, layout: layout) else {
            return XCTFail("expected .row")
        }
        XCTAssertLessThanOrEqual(counter.totalCalls, expectedMax)
    }
```

- [ ] **Step 6: Run the two count suites and the whole test target**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapRowQueryCountTests 2>&1 | tail -6
swift test 2>&1 | tail -5
```

Expected: both green. If the tightened D-25 assertion fails, record the observed count — a target needing more than `ceilLog2(lineCount) + 4` probes is a finding about the search, not a reason to restore the loose bound.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift
git commit -m "$(cat <<'MSG'
test: pin visualPointAt's probe table; tighten D-25's redundant bound

Two counters and two fixtures. The layout axis keeps node 3's ceilLog2(lineCount)
+ 4 with no totalRows term; the column axis is zero on every non-located path
(drill (h): move the x rung after the walk and only this assertion reddens),
exactly 3+2 clamped and 3+2+1 plus one dispatch delegating, and grows with
rowInLine by at least endColumn(k+m) - endColumn(k) (drill (i): probe once per
row and the difference falls to ~24 against a 40-cell bound -- a "strictly more"
assertion would have passed).

D-25: the < lineCount/10 bound, redundant against a sibling's <= 14 on the same
fixture, becomes the tight bound at a second search target.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 6: The infinite-width oracle — criterion 3's evidence

Spec Testing Strategy (`WrapPointQueryEquivalenceTests`), AC4. Scoped to the **located branch** deliberately, following node 3's oracle: the two ladders' failure orderings differ by design (Decision 5), and the review carries that scoping into criterion 3's evidence cell.

**Files:**
- Create: `Tests/TextEngineCoreTests/WrapPointQueryEquivalenceTests.swift`

- [ ] **Step 1: Write the oracle**

Create `Tests/TextEngineCoreTests/WrapPointQueryEquivalenceTests.swift`:

```swift
import XCTest
import TextEngineCore

/// Criterion 3's oracle on the point axis: at a wrap width no line can exceed, the wrap
/// path must be bit-identical to the no-wrap path. The comparison is against `pointAt`
/// over a UNIFORM vertical axis and the very same layout as the horizontal source —
/// `VisualRowLayoutSource` refines `LineHorizontalMetricsSource`, so one object serves
/// both queries and the oracle compares two ladders over identical metrics.
///
/// Located branch only, and that scoping is the honest statement of what is proven: the
/// two failure orderings diverge by design.
final class WrapPointQueryEquivalenceTests: XCTestCase {
    private static let rowHeight = 12.0

    /// Irregular advances and break sets, so a width-sensitive bug cannot hide behind a
    /// uniform fixture. A blank line is included: it packs to exactly one `[0, 0)` row and
    /// both queries must answer `.blankLine`.
    private static let lines: [(advances: [Double], breaks: Set<Int>)] = [
        (advances: [7.0, 3.0, 11.0], breaks: [1, 2]),
        (advances: [5.0], breaks: []),
        (advances: [2.0, 2.0, 2.0, 2.0], breaks: [1, 2, 3]),
        (advances: [], breaks: []),
        (advances: [9.0, 1.0], breaks: [1]),
    ]

    private static func layout(wrapWidth: Double) -> TestVisualRowLayout {
        TestVisualRowLayout(lines: lines, rowHeight: rowHeight, wrapWidth: wrapWidth)
    }

    private func ySweep(lineCount: Int) -> [Double] {
        var ys: [Double] = [-100.0, -0.001]
        for row in 0..<lineCount {
            let top = Double(row) * Self.rowHeight
            ys.append(top)
            ys.append(top + Self.rowHeight / 2.0)
            ys.append(top + Self.rowHeight - 0.001)
        }
        ys.append(Double(lineCount) * Self.rowHeight)
        ys.append(Double(lineCount) * Self.rowHeight + 100.0)
        return ys
    }

    /// Exact cell boundaries, interiors, and both clamps for every line in the fixture.
    private static let xs: [Double] = [-100.0, -0.001, 0.0, 0.001, 1.0, 2.0, 4.0, 5.0,
                                       6.999, 7.0, 8.0, 10.0, 20.0, 21.0, 1_000.0]

    /// Returns the first (x, y) at which the two queries disagree, or nil if none does.
    private func firstDisagreement(wrapWidth: Double) -> String? {
        let layout = Self.layout(wrapWidth: wrapWidth)
        let uniform = UniformLineMetrics(lineCount: layout.lineCount, lineHeight: Self.rowHeight)
        for y in ySweep(lineCount: layout.lineCount) {
            for x in Self.xs {
                let wrap = ViewportVirtualizer.visualPointAt(x: x, y: y, layout: layout)
                let flat = ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: uniform, columnMetrics: layout)
                guard case .point(let wrapPoint) = wrap, case .point(let flatPoint) = flat else {
                    return "non-located branch at (x: \(x), y: \(y)): \(wrap) vs \(flat)"
                }
                let line = flatPoint.line.lineIndex
                let count = layout.columnCount(inLine: line)
                let total = layout.columnOffset(inLine: line, column: count)
                let expectedSpan = VisualRow(logicalLine: line, rowInLine: 0,
                                             startColumn: 0, endColumn: count, width: total)
                if wrapPoint.row.globalRow != line
                    || wrapPoint.row.logicalLine != line
                    || wrapPoint.row.rowInLine != 0
                    || wrapPoint.row.clamp != flatPoint.line.clamp
                    || wrapPoint.rowSpan != expectedSpan
                    || wrapPoint.column != flatPoint.column {
                    return "(x: \(x), y: \(y)): \(wrapPoint) vs \(flatPoint)"
                }
            }
        }
        return nil
    }

    /// ∞ AND a large finite width: the oracle holds at any width >= every line's total
    /// advance, not only at ∞. `rowSpan.width` is asserted alongside the span because it
    /// is what steps 5-6 compare against.
    func testWidthNoLineExceedsEqualsUniformPointAt() {
        for width in [Double.infinity, 1_000.0] {
            XCTAssertNil(firstDisagreement(wrapWidth: width), "width=\(width)")
        }
    }

    /// The control. Without it the oracle could be vacuously true — two queries that both
    /// ignored the width would pass it.
    func testANarrowWidthBreaksTheEquivalence() {
        XCTAssertNotNil(firstDisagreement(wrapWidth: 4.0),
                        "at a width the fixture's lines exceed, the wrap answer MUST differ")
    }
}
```

- [ ] **Step 2: Run it**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryEquivalenceTests 2>&1 | tail -8
```

Expected: both green.

- [ ] **Step 3: Drill (a) — the oracle can fail**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/TextEngineCore/WrapPointQuery.swift'
s = open(p).read()
old = "        let rebased = rowLeft + x"
new = "        let rebased = rowLeft + x * 2.0   // DRILL (a)"
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapPointQueryEquivalenceTests 2>&1 | tail -10
git checkout -- Sources/TextEngineCore/WrapPointQuery.swift
swift test --filter WrapPointQueryEquivalenceTests 2>&1 | tail -5
```

Expected: **RED** in `testWidthNoLineExceedsEqualsUniformPointAt`, with the failure message naming the first disagreeing `(x, y)`. Record it.

**Record this too, because it bounds what the oracle proves:** deleting the rebasing outright (`let rebased = x`) leaves this oracle **green** by construction — at a width no line exceeds every line packs to one row starting at column 0, so `rowLeft` is always 0 and row-relative equals line-relative (spec Decision 1 says so in as many words). The rebasing is pinned by the multi-row fixtures in `WrapPointQueryTests` and `WrapPointQueryRoundTripTests`, not here. Optionally run the deletion to observe it; if you do, confirm `WrapPointQueryTests` reddens and this suite does not.

- [ ] **Step 4: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/TextEngineCoreTests/WrapPointQueryEquivalenceTests.swift
git commit -m "$(cat <<'MSG'
test: infinite-width oracle for visualPointAt (criterion 3)

At infinity and at any finite width no line exceeds, visualPointAt is
bit-identical to pointAt over a uniform vertical axis and the same layout as
the horizontal source: same clamps, same cell, globalRow == logicalLine ==
the located line, rowInLine 0, and the span equal to [0, columnCount) with its
advance-sum width. A narrow-width control proves it is not vacuous.

Located branch only -- the two failure orderings diverge by design (Decision 5),
and that scoping is what the review carries into criterion 3's evidence cell.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 7: Round-trip agreement with the streaming path

Spec Testing Strategy (`WrapPointQueryRoundTripTests`), AC8's second half. The query and `DocumentVisualRowCursor` now answer the *same* question through the *same* helper; this is what notices if a later edit unshares them.

**Files:**
- Create: `Tests/TextEngineCoreTests/WrapPointQueryRoundTripTests.swift`

- [ ] **Step 1: Write the round trip**

Create `Tests/TextEngineCoreTests/WrapPointQueryRoundTripTests.swift`:

```swift
import XCTest
import TextEngineCore

/// Every row the document cursor streams is found by its own `y`, with an identical span.
/// Both sides run node 1's packer through the shared `advanceVisualRows`, so this pins
/// AGREEMENT — it is not independent evidence that the packing is right (that is the
/// packer's own suites). What it catches is an edit that unshares the walk.
final class WrapPointQueryRoundTripTests: XCTestCase {
    private static let rowHeight = 10.0
    private static let wrapWidth = 20.0

    /// Both kinds of line, because `greedyEnd` has two branches after Decision 12 and a
    /// fixture of one kind exercises one of them:
    ///   * lines 0 and 2 FIT the width (one row, packed in O(1) with no scan)
    ///   * lines 1 and 4 EXCEED it (interior rows scan)
    ///   * line 3 is blank
    private static func layout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: [10.0, 10.0], breaks: [1]),                             // fits: 1 row
                (advances: Array(repeating: 10.0, count: 6), breaks: Set(1..<6)),   // 3 rows
                (advances: [15.0], breaks: []),                                     // fits: 1 row
                (advances: [], breaks: []),                                         // blank: 1 row
                (advances: Array(repeating: 5.0, count: 12), breaks: Set(1..<12)),  // 3 rows
            ],
            rowHeight: rowHeight, wrapWidth: wrapWidth)
    }

    func testEveryStreamedRowIsFoundByItsOwnPoint() {
        let layout = Self.layout()

        // Fixture guard: both branches must be present, or this test covers one of them
        // while claiming both.
        var fitting = 0
        var wrapped = 0
        for line in 0..<layout.lineCount {
            let count = layout.columnCount(inLine: line)
            if layout.columnOffset(inLine: line, column: count) <= Self.wrapWidth { fitting += 1 } else { wrapped += 1 }
        }
        XCTAssertGreaterThan(fitting, 0, "fixture must carry a line that FITS the wrap width")
        XCTAssertGreaterThan(wrapped, 0, "fixture must carry a line that EXCEEDS it")

        let input = VariableViewportInput(
            scrollOffsetY: 15.0, viewportHeight: 60.0,
            overscanLinesBefore: 1, overscanLinesAfter: 1)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else {
            return XCTFail("compute must succeed on a well-formed layout")
        }
        let streamed = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertFalse(streamed.isEmpty, "the fixture must produce a non-empty buffer range")
        XCTAssertEqual(streamed.count, range.bufferEndExclusive - range.bufferStart)

        for (offset, geometry) in streamed.enumerated() {
            let expectedGlobalRow = range.bufferStart + offset
            // Both the exact row boundary (what a `<`/`<=` mutation moves) and the row
            // interior (which closes the compensating-error class).
            for probe in [geometry.y, geometry.y + Self.rowHeight / 2.0] {
                guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 0.0, y: probe, layout: layout) else {
                    XCTFail("expected .point at y=\(probe)"); continue
                }
                XCTAssertEqual(point.row.globalRow, expectedGlobalRow, "probe \(probe)")
                XCTAssertEqual(point.rowSpan, geometry.row, "probe \(probe)")
            }
        }
    }
}
```

- [ ] **Step 2: Run it, then the whole suite**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryRoundTripTests 2>&1 | tail -6
swift test 2>&1 | tail -5
```

Expected: both green. The round trip has no drill of its own — Decision 4's shared helper makes the two sides agree structurally, and the helper's own rule is pinned by `VisualRowWalkHelperTests` (55a) with drill (f3) on record.

- [ ] **Step 3: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/TextEngineCoreTests/WrapPointQueryRoundTripTests.swift
git commit -m "$(cat <<'MSG'
test: round-trip visualPointAt against the streamed visual rows

Every row DocumentVisualRowCursor streams is found by its own y with an equal
rowSpan, on a fixture carrying both of greedyEnd's branches -- lines that fit
the width and lines that exceed it -- with a guard asserting both are present.

Pins agreement between the query and the cursor, which share advanceVisualRows;
it is what notices an edit that unshares them.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 8: The observational `--wrap-point-query` benchmark mode

Spec Benchmark Mode / CI, Contract 55b (the scenario table and the line tokens), Decision 10 (file placement), AC12. Observational: `isGateable == false`, `--gate` rejected, latency tokens prefixed, **not** wired into CI, no budget, no corpus row.

**Files:**
- Create: `Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (the enum case, `outputName`, `isGateable`, `absoluteCeiling`, the parse case, both usage lines)
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift` (the dispatch arm)
- Create: `Tests/ViewportBenchmarksTests/WrapPointQueryOptionsTests.swift`
- Create: `Tests/ViewportBenchmarksTests/WrapPointQueryChecksumTests.swift`
- Modify: `Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift` (+3 cases)

**Interfaces:**
- Consumes: `amortisedSamples(iterations:operationsPerSample:body:) -> (samples: [Int64], checksum: Int)`, `deterministicIndex(sample:multiplier:modulus:)`, `percentile(_:numerator:denominator:)` (`BenchmarkSupport.swift`); `BenchmarkWrapLayout` (read-only, for the agreement test).
- Produces: `WrapPointQueryScenario`, `wrapPointQueryScenarios`, `WrapPointQueryLayout`, `wrapPointQueryChecksum(_:)`, `formatWrapPointQueryLine(...)`, `runWrapPointQueryBenchmarks()`, `BenchmarkMode.wrapPointQuery`.

**One deliberate deviation from the spec, with its reason:** the spec's floors are `cells_per_line >= 1_000` and `rows_per_line >= 100`, and it says "the plan may raise them, never lower them". At those values drill (j) — halving `long_line_deep_row`'s 2 000 cells — leaves 1 000 cells and 200 rows, both still **above** the floor, so the pin would not redden and would be exactly the unfalsifiable shape D-25 describes. The floors are therefore raised to the scenario's own values (`2_000` and `400`), which is the form that makes any shortening red. Record this in the verification record.

- [ ] **Step 1: Write the failing option tests**

Create `Tests/ViewportBenchmarksTests/WrapPointQueryOptionsTests.swift`:

```swift
import XCTest
@testable import ViewportBenchmarks

final class WrapPointQueryOptionsTests: XCTestCase {
    func testFlagSelectsTheMode() {
        guard case let .run(options) = BenchmarkOptions.parse(["--wrap-point-query"]) else {
            return XCTFail("--wrap-point-query must select a runnable mode")
        }
        XCTAssertEqual(options.mode.outputName, "wrap_point_query")
        XCTAssertFalse(options.enforceGate)
    }

    // Gate promotion for wrap modes is map node 6, and it is not one step: un-prefix the
    // latency keys, run a hosted step WITHOUT --gate so a verdict-less line bootstraps the
    // corpus, harvest, derive, and only then add the gate step. Until a hosted budget
    // exists, --gate must be REJECTED rather than accepted against a hand-typed number.
    func testGateIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(["--wrap-point-query", "--gate"]) else {
            return XCTFail("--gate must be rejected for a non-gateable mode")
        }
        XCTAssertTrue(message.contains("wrap_point_query"), "message should name the mode: \(message)")
    }

    func testCombiningWithAnEarlierModeFlagIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(["--wrap-row-query", "--wrap-point-query"]) else {
            return XCTFail("two mode flags must be rejected")
        }
        XCTAssertTrue(message.contains("--wrap-point-query"), "message should name the flag: \(message)")
    }

    func testIsNotGateable() {
        XCTAssertFalse(BenchmarkMode.wrapPointQuery.isGateable)
    }

    /// Spec Benchmark Mode / CI: `.scrollFrame` is a DECISION here, not a default
    /// inherited by proximity — a hit test is on the frame path because a drag-select
    /// performs one per frame, and the demanding caller sets the class. The value is inert
    /// until node 6 makes the mode gateable (D-20), which is exactly why it is written
    /// down where a reader can find it.
    func testAbsoluteCeilingIsTheScrollFrameClass() {
        XCTAssertEqual(BenchmarkMode.wrapPointQuery.absoluteCeiling, .scrollFrame)
    }
}
```

- [ ] **Step 2: Run and confirm the compile failure**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryOptionsTests 2>&1 | tail -10
```

Expected: a compile error — `type 'BenchmarkMode' has no member 'wrapPointQuery'`. That is this task's red.

- [ ] **Step 3: Wire the mode into `BenchmarkOptions.swift`**

Four exhaustive switches and two usage strings. Apply each edit by matching text:

1. In `enum BenchmarkMode`, after `case wrapRowQuery`, add:
```swift
    case wrapPointQuery
```
2. In `outputName`, after the `.wrapRowQuery` arm, add:
```swift
        case .wrapPointQuery:
            return "wrap_point_query"
```
3. In `isGateable`, extend the `false` arm — replace `             .wrapRowQuery:\n            return false` with:
```swift
             .wrapRowQuery,
             .wrapPointQuery:
            return false
```
   and update that arm's comment: "the two wrap modes are observational until map node 6 promotes them" becomes "the **three** wrap modes are observational until map node 6 promotes them".
4. In `absoluteCeiling`, extend the `.scrollFrame` arm the same way (`.wrapRowQuery,` → `.wrapRowQuery,\n             .wrapPointQuery,`) and update its comment's "five non-gateable modes" to "six".
5. In `usage`, add `[--wrap-point-query]` to the `Usage:` line after `[--wrap-row-query]`, and add the option line after the `--wrap-row-query` one:
```
      --wrap-point-query    Run the observational wrap-aware (x,y)->(row,cell) point query benchmark (not gateable).
```
6. In `parse`, after the `--wrap-row-query` case:
```swift
            case "--wrap-point-query":
                if mode != .pipeline {
                    return .failure("--wrap-point-query cannot be combined with another mode")
                }
                mode = .wrapPointQuery
```

Then in `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, after the `.wrapRowQuery` arm:

```swift
    case .wrapPointQuery:
        return runWrapPointQueryBenchmarks()
```

- [ ] **Step 4: Write the benchmark**

Create `Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift`:

```swift
import TextEngineCore

struct WrapPointQueryScenario {
    let name: String
    let lineCount: Int
    let wrapWidth: Double
    let cells: Int
    let advance: Double
    /// Per-scenario, NOT one constant for the mode: 256 is right for the five logarithmic
    /// scenarios and wrong for `long_line_deep_row`, whose per-operation cost is linear in
    /// the line's cells. At 256 x thousands of cells that scenario either runs for minutes
    /// or gets its line quietly shortened until the term it exists to expose is invisible
    /// -- and the shortening is the failure mode, because it looks like a passing
    /// benchmark. Precedent: WrapComputeBenchmark's drain (16), itself after
    /// BulkStructuralMutationBenchmark.
    let operationsPerSample: Int
    /// The located line FITS the wrap width, so the query scans no columns at all.
    ///
    /// PRINTED rather than inferred, because `rows_per_line == 1` does NOT imply it: a
    /// line with no break opportunities and `total > wrapWidth` packs to exactly one
    /// OVERFLOW row and still takes the walk. It also deliberately does not track
    /// Decision 12's other O(1) case -- `long_line_deep_row` is `false` even though its
    /// own final `greedyEnd` returns immediately -- because the token names the cost class
    /// of the WHOLE operation, which is what a budget is derived from.
    let fastPath: Bool
    /// Non-nil only where the sampling rule FIXES the walk depth, so the printed number
    /// means one thing. The other scenarios sample the row axis uniformly and their depth
    /// genuinely varies, so the token is omitted there rather than filled with an average.
    let rowInLine: Int?
    let clampY: Bool
    let clampX: Bool
}

/// A top-level value so `WrapBenchmarkLineShapeTests` can pin the parameters under
/// `@testable import` without running the benchmark. The pin asserts PARAMETERS, never
/// timings.
let wrapPointQueryScenarios: [WrapPointQueryScenario] = [
    // ∞ width -> one row per line, the packer short-circuits, the query is genuinely
    // logarithmic.
    WrapPointQueryScenario(name: "uniform_1k", lineCount: 1_000, wrapWidth: .infinity,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: true, rowInLine: nil, clampY: false, clampX: false),
    WrapPointQueryScenario(name: "uniform_100k", lineCount: 100_000, wrapWidth: .infinity,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: true, rowInLine: nil, clampY: false, clampX: false),
    // Narrow -> 4 rows per line; every located row but the last pays the walk.
    WrapPointQueryScenario(name: "narrow_100k", lineCount: 100_000, wrapWidth: 40.0,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: false, rowInLine: nil, clampY: false, clampX: false),
    // node 3's single clamped_100k SPLITS IN TWO here: the two axes clamp through
    // different branches, and averaging them would hand node 6 a budget for an operation
    // that does not exist. A clamped y still runs both provider searches on the layout
    // axis; a clamped x skips the column hook entirely.
    WrapPointQueryScenario(name: "clamped_y_100k", lineCount: 100_000, wrapWidth: 40.0,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: false, rowInLine: nil, clampY: true, clampX: false),
    WrapPointQueryScenario(name: "clamped_x_100k", lineCount: 100_000, wrapWidth: 40.0,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: false, rowInLine: nil, clampY: false, clampX: true),
    // The only non-logarithmic term this query has, measured instead of averaged away:
    // 400 rows per line, queried at the LAST row, so the within-line walk is visible.
    // Hiding it from the one mode that measures this query would leave node 6 deriving a
    // budget for a cost class it never saw.
    WrapPointQueryScenario(name: "long_line_deep_row", lineCount: 1_000, wrapWidth: 40.0,
                           cells: 2_000, advance: 8.0, operationsPerSample: 16,
                           fastPath: false, rowInLine: 399, clampY: false, clampX: false),
]

/// Single-line char-wrap metrics for packing the one representative line.
private struct SingleLinePointWrap: WrapMetricsSource {
    let cells: Int
    let advance: Double
    func columnCount(inLine line: Int) -> Int { cells }
    func columnOffset(inLine line: Int, column: Int) -> Double { Double(column) * advance }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { column > 0 && column < cells }
}

/// This mode's own layout, so the long line is not fighting an O(N x cells) setup.
///
/// `BenchmarkWrapLayout.init` deliberately re-packs EVERY line -- its init IS
/// `--wrap-compute`'s measured reindex -- and at `long_line_deep_row`'s 1 000 x 2 000
/// cells a layout built that way would spend ~10^9 packing steps before the first
/// measurement, appear to hang, and the nearest remedy to hand is a shorter line, which
/// silently deletes the term the scenario exists to expose. A QUERY mode measures no
/// reindex and has no use for that property, and every line in these fixtures is
/// identical by construction, so this packs ONE line and fills the prefix sum by
/// multiplication: O(lineCount + cells). `BenchmarkWrapLayout` is NOT touched, and the
/// two constructions' agreement is asserted on a small shape in
/// `WrapBenchmarkLineShapeTests` -- the shortcut is valid because of the FIXTURE, not the
/// type.
struct WrapPointQueryLayout: VisualRowLayoutSource {
    let lineCount: Int
    let rowHeight: Double
    let wrapWidth: Double
    let cells: Int
    let advance: Double
    let rowsPerLine: Int

    init(lineCount: Int, cells: Int, advance: Double, rowHeight: Double, wrapWidth: Double) {
        self.lineCount = lineCount
        self.rowHeight = rowHeight
        self.wrapWidth = wrapWidth
        self.cells = cells
        self.advance = advance
        var packed = 0
        if case .rows(var cursor) = ViewportVirtualizer.visualRows(
            inLine: 0, wrapWidth: wrapWidth, metrics: SingleLinePointWrap(cells: cells, advance: advance)
        ) {
            while cursor.next() != nil { packed += 1 }
        }
        self.rowsPerLine = packed
    }

    func columnCount(inLine line: Int) -> Int { cells }
    func columnOffset(inLine line: Int, column: Int) -> Double { Double(column) * advance }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { column > 0 && column < cells }
    func visualRowCount(inLine line: Int) -> Int { rowsPerLine }
    func firstVisualRow(ofLine line: Int) -> Int { line * rowsPerLine }
    // logicalLine(containingVisualRow:) is deliberately NOT overridden: the default
    // binary search is what BenchmarkWrapLayout uses, and this mode must measure the same
    // dispatch.
}

private func wrapPointVerticalClampCode(_ clamp: LineLocation.Clamp) -> Int {
    switch clamp {
    case .inRange: return 1
    case .clampedToTop: return 2
    case .clampedToBottom: return 3
    }
}

private func wrapPointHorizontalClampCode(_ clamp: ColumnLocation.Clamp) -> Int {
    switch clamp {
    case .inRange: return 1
    case .clampedToLeft: return 2
    case .clampedToRight: return 3
    }
}

/// Folds EVERY returned field under distinct multipliers -- both indices of the row, both
/// ends of the span, the span's width, the cell, and BOTH clamp flags. Folding one index
/// would let a release build delete the rest and still print a plausible number;
/// `PointGeometryChecksumTests` exists because exactly that reversion once passed
/// silently. `width` is a Double, folded through its bit pattern with
/// `Int(truncatingIfNeeded:)` -- `Int(bitPattern: UInt(...))` traps where Int is 32-bit,
/// and although this target is not cross-compiled today the idiom costs nothing. A blank
/// line folds a distinct sentinel, so `.blankLine` and cell 0 cannot collide. Clamp codes
/// start at 1, so `.inRange` still contributes. Pinned by `WrapPointQueryChecksumTests`.
func wrapPointQueryChecksum(_ location: VisualPointLocation) -> Int {
    var value = 0
    value = value &+ location.row.globalRow &* 1
    value = value &+ location.row.logicalLine &* 31
    value = value &+ location.row.rowInLine &* 131
    value = value &+ wrapPointVerticalClampCode(location.row.clamp) &* 1_009
    value = value &+ location.rowSpan.startColumn &* 3_571
    value = value &+ location.rowSpan.endColumn &* 7_919
    value = value &+ Int(truncatingIfNeeded: location.rowSpan.width.bitPattern) &* 17
    switch location.column {
    case .blankLine:
        value = value &+ 104_729
    case .cell(let cell):
        value = value &+ cell.columnIndex &* 15_485_863
        value = value &+ wrapPointHorizontalClampCode(cell.clamp) &* 32_452_843
    }
    return value
}

// Pure so WrapBenchmarkLineShapeTests can pin the token shape without running the
// benchmark. The latency tokens stay PREFIXED (`query_p95_ns=`): the harvester matches
// `p95_ns=` as a substring but then requires the EXACT key, so this line emits no corpus
// row. Node 6 un-prefixes them in the same sequence that adds the gate step.
func formatWrapPointQueryLine(
    scenarioName: String,
    totalRows: Int,
    cellsPerLine: Int,
    rowsPerLine: Int,
    fastPath: Bool,
    rowInLine: Int?,
    operationsPerSample: Int,
    p95Nanoseconds: Int64,
    p99Nanoseconds: Int64,
    checksum: Int
) -> String {
    var line = "mode=wrap_point_query scenario=\(scenarioName) total_rows=\(totalRows)"
        + " cells_per_line=\(cellsPerLine)"
        + " rows_per_line=\(rowsPerLine)"
        + " fast_path=\(fastPath)"
    if let rowInLine {
        line += " row_in_line=\(rowInLine)"
    }
    line += " query_operations_per_sample=\(operationsPerSample)"
        + " query_p95_ns=\(p95Nanoseconds)"
        + " query_p99_ns=\(p99Nanoseconds)"
        + " checksum=\(checksum)"
    return line
}

/// Observational only: NOT gateable, NOT wired into CI. Measured on the same amortised
/// shape as every gated mode (`amortisedSamples`), so the numbers resolve the operation
/// rather than the host clock tick (D-23's repair, which this mode is born on). That
/// "same shape as the gated modes" is inherited, not proven here -- D-28 records that
/// `amortisedSamples` and the twelve gated modes' hand-rolled loops are two
/// implementations of one shape with nothing pinning them together, and node 6 must not
/// read the claim as established when it derives budgets that rest on it.
@available(macOS 13.0, *)
func runWrapPointQueryBenchmarks() -> Bool {
    let rowHeight = 16.0
    let iterations = 5_000

    for scenario in wrapPointQueryScenarios {
        let layout = WrapPointQueryLayout(
            lineCount: scenario.lineCount, cells: scenario.cells, advance: scenario.advance,
            rowHeight: rowHeight, wrapWidth: scenario.wrapWidth)
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        let totalHeight = Double(totalRows) * rowHeight
        // Every row of these char-wrap fixtures is this wide: the scenarios are sized so
        // the line's advance divides by the width exactly, and at ∞ the row IS the line.
        let rowWidth = min(scenario.wrapWidth, Double(scenario.cells) * scenario.advance)

        // `operation` is the GLOBAL operation index, so the input sequence is exactly what
        // a single-operation loop would produce -- only the clock reads are batched.
        let measured = amortisedSamples(
            iterations: iterations, operationsPerSample: scenario.operationsPerSample
        ) { operation in
            let y: Double
            if scenario.clampY {
                let offset = Double(deterministicIndex(sample: operation, multiplier: 2_654_435_761, modulus: 10_000))
                y = operation % 2 == 0 ? -(offset + 1.0) : totalHeight + offset
            } else if let fixedRow = scenario.rowInLine {
                // The sampling rule that makes `row_in_line=` meaningful: the LINE varies,
                // the depth within it does not, so the walk depth is the constant
                // `rows_per_line - 1` on every operation.
                let line = deterministicIndex(sample: operation, multiplier: 2_654_435_761, modulus: layout.lineCount)
                y = Double(line * layout.rowsPerLine + fixedRow) * rowHeight + rowHeight / 2.0
            } else {
                let row = deterministicIndex(sample: operation, multiplier: 2_654_435_761, modulus: totalRows)
                y = Double(row) * rowHeight + rowHeight / 2.0
            }

            let x: Double
            if scenario.clampX {
                x = rowWidth + Double(deterministicIndex(sample: operation, multiplier: 40_503, modulus: 1_000))
            } else {
                x = Double(deterministicIndex(sample: operation, multiplier: 40_503, modulus: Int(rowWidth))) + 0.25
            }

            if case .point(let location) = ViewportVirtualizer.visualPointAt(x: x, y: y, layout: layout) {
                return wrapPointQueryChecksum(location)
            }
            return 0
        }

        var samples = measured.samples
        samples.sort()
        print(formatWrapPointQueryLine(
            scenarioName: scenario.name,
            totalRows: totalRows,
            cellsPerLine: scenario.cells,
            rowsPerLine: layout.rowsPerLine,
            fastPath: scenario.fastPath,
            rowInLine: scenario.rowInLine,
            operationsPerSample: scenario.operationsPerSample,
            p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
            p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
            checksum: measured.checksum))
    }
    return true
}
```

- [ ] **Step 5: Run the option tests and the mode itself**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryOptionsTests 2>&1 | tail -6
swift build -c release 2>&1 | tail -3
swift run -c release ViewportBenchmarks -- --wrap-point-query 2>&1 | tee /tmp/slice55b-wrap-point-query-local.txt
```

Expected: five option tests green; six `mode=wrap_point_query` lines, one per scenario, each with `checksum=` and a non-zero `query_p95_ns=`. Sanity-read the parameters before moving on: `uniform_1k` `total_rows=1000 rows_per_line=1 fast_path=true`, `narrow_100k` `total_rows=400000 rows_per_line=4 fast_path=false`, `long_line_deep_row` `total_rows=400000 cells_per_line=2000 rows_per_line=400 fast_path=false row_in_line=399`. A `checksum=0` on any scenario means every query fell to `.failure`/`.empty` — stop and read the layout.

- [ ] **Step 6: Write the checksum pin**

Create `Tests/ViewportBenchmarksTests/WrapPointQueryChecksumTests.swift`:

```swift
import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

/// Byte-identity guard for the observational mode's checksum. A benchmark whose result is
/// never read can be deleted by a release build and still "run"; a checksum that folds one
/// of eight fields has the same hole for the other seven. Applied up front because
/// `PointGeometryChecksumTests` exists precisely because a reversion to an index-only fold
/// once passed silently — and `AGENTS.md` records that lesson by name.
final class WrapPointQueryChecksumTests: XCTestCase {
    private func location(
        globalRow: Int = 5, logicalLine: Int = 3, rowInLine: Int = 2,
        rowClamp: LineLocation.Clamp = .inRange,
        startColumn: Int = 4, endColumn: Int = 9, width: Double = 40.0,
        column: ColumnResolution = .cell(ColumnLocation(columnIndex: 6, clamp: .inRange))
    ) -> VisualPointLocation {
        VisualPointLocation(
            row: VisualRowLocation(globalRow: globalRow, logicalLine: logicalLine,
                                   rowInLine: rowInLine, clamp: rowClamp),
            rowSpan: VisualRow(logicalLine: logicalLine, rowInLine: rowInLine,
                               startColumn: startColumn, endColumn: endColumn, width: width),
            column: column)
    }

    func testEveryFieldAffectsTheChecksum() {
        let base = wrapPointQueryChecksum(location())
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(globalRow: 6)), "globalRow")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(logicalLine: 4)), "logicalLine")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(rowInLine: 3)), "rowInLine")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(rowClamp: .clampedToTop)), "the vertical clamp flag")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(rowClamp: .clampedToBottom)), "the vertical clamp flag")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(startColumn: 5)), "startColumn")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(endColumn: 10)), "endColumn")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(location(width: 41.0)), "rowSpan.width")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(
            location(column: .cell(ColumnLocation(columnIndex: 7, clamp: .inRange)))), "the cell index")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(
            location(column: .cell(ColumnLocation(columnIndex: 6, clamp: .clampedToLeft)))), "the horizontal clamp flag")
        XCTAssertNotEqual(base, wrapPointQueryChecksum(
            location(column: .cell(ColumnLocation(columnIndex: 6, clamp: .clampedToRight)))), "the horizontal clamp flag")
    }

    /// Distinct multipliers: under an additive fold a +1 on one field and a −1 on another
    /// cancel, which is how an index-only regression hides.
    func testFieldsAreNotInterchangeable() {
        XCTAssertNotEqual(wrapPointQueryChecksum(location(globalRow: 6)),
                          wrapPointQueryChecksum(location(logicalLine: 4)))
        XCTAssertNotEqual(wrapPointQueryChecksum(location(startColumn: 5)),
                          wrapPointQueryChecksum(location(endColumn: 10)))
    }

    /// A blank row carries no cell, so its contribution must be a distinct sentinel rather
    /// than the absence of one — otherwise `.blankLine` collides with cell 0 `.inRange`.
    func testBlankLineCannotCollideWithACell() {
        let blank = wrapPointQueryChecksum(
            location(startColumn: 0, endColumn: 0, width: 0.0, column: .blankLine))
        let cellZero = wrapPointQueryChecksum(
            location(startColumn: 0, endColumn: 0, width: 0.0,
                     column: .cell(ColumnLocation(columnIndex: 0, clamp: .inRange))))
        XCTAssertNotEqual(blank, cellZero)
    }
}
```

- [ ] **Step 7: Add the three line-shape cases**

Append inside `final class WrapBenchmarkLineShapeTests` in `Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift`:

```swift
    func testWrapPointQueryLineCarriesItsTokensAndNoBareLatencyKeys() {
        let line = formatWrapPointQueryLine(
            scenarioName: "long_line_deep_row", totalRows: 400_000,
            cellsPerLine: 2_000, rowsPerLine: 400, fastPath: false, rowInLine: 399,
            operationsPerSample: 16, p95Nanoseconds: 1_234, p99Nanoseconds: 2_345,
            checksum: 987_654)

        XCTAssertEqual(value("mode", in: line), "wrap_point_query")
        XCTAssertEqual(value("scenario", in: line), "long_line_deep_row")
        XCTAssertEqual(value("total_rows", in: line), "400000")
        XCTAssertEqual(value("cells_per_line", in: line), "2000")
        XCTAssertEqual(value("rows_per_line", in: line), "400")
        XCTAssertEqual(value("fast_path", in: line), "false")
        XCTAssertEqual(value("row_in_line", in: line), "399")
        XCTAssertEqual(value("query_operations_per_sample", in: line), "16")
        XCTAssertEqual(value("query_p95_ns", in: line), "1234")
        XCTAssertEqual(value("query_p99_ns", in: line), "2345")
        XCTAssertEqual(value("checksum", in: line), "987654")

        let keys = tokenKeys(line)
        XCTAssertFalse(keys.contains("p95_ns"), "bare p95_ns would make this line harvestable")
        XCTAssertFalse(keys.contains("p99_ns"), "bare p99_ns would make this line harvestable")

        // row_in_line is printed only where the sampling rule fixes the depth; elsewhere
        // it is OMITTED rather than filled with an average.
        let uniform = formatWrapPointQueryLine(
            scenarioName: "uniform_1k", totalRows: 1_000,
            cellsPerLine: 20, rowsPerLine: 1, fastPath: true, rowInLine: nil,
            operationsPerSample: 256, p95Nanoseconds: 37, p99Nanoseconds: 41, checksum: 12_345)
        XCTAssertNil(value("row_in_line", in: uniform))
        XCTAssertEqual(value("fast_path", in: uniform), "true")
    }

    /// The scenario table's parameters, pinned so a later shortening is a RED TEST rather
    /// than a quieter benchmark printing a smaller, plausible number.
    ///
    /// The floors are the scenarios' own values, not the spec's `>= 1_000` / `>= 100`:
    /// at those, HALVING `long_line_deep_row`'s cells leaves 1 000 cells and 200 rows,
    /// both still above the floor, so the pin could not fail — the exact shape D-25
    /// describes. The spec permits raising floors, never lowering them.
    func testWrapPointQueryScenarioParametersAreAtTheirFloors() {
        guard let deep = wrapPointQueryScenarios.first(where: { $0.name == "long_line_deep_row" }) else {
            return XCTFail("the long_line_deep_row scenario must exist: it is the only one that measures the walk")
        }
        XCTAssertGreaterThanOrEqual(deep.cells, 2_000, "shortening the line deletes the term this scenario exposes")
        let rowsPerLine = Int((Double(deep.cells) * deep.advance / deep.wrapWidth).rounded(.down))
        XCTAssertGreaterThanOrEqual(rowsPerLine, 400, "the walk must be hundreds of rows deep")
        XCTAssertEqual(deep.rowInLine, rowsPerLine - 1, "the scenario must query the LAST row of its line")
        XCTAssertEqual(deep.operationsPerSample, 16, "a linear-cost scenario takes the smaller operation count")

        // fast_path is a per-scenario constant decidable from the parameters, and every
        // scenario's stored value must equal what its parameters imply.
        for scenario in wrapPointQueryScenarios {
            let implied = Double(scenario.cells) * scenario.advance <= scenario.wrapWidth
            XCTAssertEqual(scenario.fastPath, implied, "\(scenario.name): fast_path must match its parameters")
        }
        XCTAssertEqual(wrapPointQueryScenarios.count, 6)
    }

    /// The multiplication shortcut in `WrapPointQueryLayout` is valid only because every
    /// line in these fixtures is identical — a property of the FIXTURE, not of the type.
    /// So the two constructions are compared element for element on a small shape.
    func testTheTwoWrapLayoutsAgreeOnTheirPrefixSums() {
        let shortcut = WrapPointQueryLayout(lineCount: 8, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        let repacked = BenchmarkWrapLayout(lineCount: 8, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        XCTAssertGreaterThan(repacked.visualRowCount(inLine: 0), 1, "the shape must WRAP, or this compares 1 == 1")
        for line in 0...8 {
            XCTAssertEqual(shortcut.firstVisualRow(ofLine: line), repacked.firstVisualRow(ofLine: line), "line \(line)")
        }
        for line in 0..<8 {
            XCTAssertEqual(shortcut.visualRowCount(inLine: line), repacked.visualRowCount(inLine: line), "line \(line)")
        }
    }
```

- [ ] **Step 8: Run the benchmark-target suite**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapPointQueryChecksumTests 2>&1 | tail -6
swift test --filter WrapBenchmarkLineShapeTests 2>&1 | tail -6
```

Expected: green.

- [ ] **Step 9: Drill (b) — the checksum's completeness**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift'
s = open(p).read()
old = "    value = value &+ Int(truncatingIfNeeded: location.rowSpan.width.bitPattern) &* 17"
new = "    value = value &+ Int(truncatingIfNeeded: location.rowSpan.width.bitPattern) &* 0   // DRILL (b)"
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapPointQueryChecksumTests 2>&1 | tail -8
git checkout -- Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift
```

Expected: **RED** — `testEveryFieldAffectsTheChecksum` fails on "rowSpan.width". Record the line. This is the zeroed-multiplier reversion `AGENTS.md` names.

- [ ] **Step 10: Drill (c) — the prefixed latency keys**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift'
s = open(p).read()
old = """    line += " query_operations_per_sample=\\(operationsPerSample)"
        + " query_p95_ns=\\(p95Nanoseconds)"
        + " query_p99_ns=\\(p99Nanoseconds)\""""
new = """    line += " query_operations_per_sample=\\(operationsPerSample)"
        + " p95_ns=\\(p95Nanoseconds)"
        + " p99_ns=\\(p99Nanoseconds)\"   // DRILL (c)"""
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapBenchmarkLineShapeTests 2>&1 | tail -10
git checkout -- Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift
```

Expected: **RED** — `testWrapPointQueryLineCarriesItsTokensAndNoBareLatencyKeys` fails on `bare p95_ns would make this line harvestable` (and on the `query_p95_ns` value lookup). Record both assertions. Un-prefixing by accident must be a red test, not a surprise corpus row.

- [ ] **Step 11: Drill (j) — the scenario-parameter pin**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift'
s = open(p).read()
old = "                           cells: 2_000, advance: 8.0, operationsPerSample: 16,"
new = "                           cells: 1_000, advance: 8.0, operationsPerSample: 16,   // DRILL (j)"
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapBenchmarkLineShapeTests 2>&1 | tail -10
git checkout -- Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift
swift test 2>&1 | tail -5
```

Expected: **RED** — `testWrapPointQueryScenarioParametersAreAtTheirFloors` fails on both the cells floor and `rowInLine == rowsPerLine - 1` (the halved line packs 200 rows, so `399` no longer names its last row). Record both. Then the whole suite green after the revert.

- [ ] **Step 12: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Tests/ViewportBenchmarksTests/WrapPointQueryOptionsTests.swift Tests/ViewportBenchmarksTests/WrapPointQueryChecksumTests.swift Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift
git commit -m "$(cat <<'MSG'
feat: add the observational --wrap-point-query benchmark mode

Six scenarios on the amortised shape, with per-scenario operationsPerSample.
node 3's single clamped_100k splits in two, because the two axes clamp through
different branches and averaging them would describe an operation that does not
exist; long_line_deep_row is new -- 400 rows per line queried at the last row,
so the within-line walk is measured instead of averaged away.

Its own O(lineCount + cells) layout type: BenchmarkWrapLayout re-packs every
line on purpose (its init IS --wrap-compute's measured reindex) and would spend
~10^9 packing steps on this fixture, whose nearest remedy is a shorter line --
the failure mode that looks like a passing benchmark. The two constructions'
prefix sums are compared element for element.

Not gateable, --gate rejected, latency keys prefixed so no corpus row is
emitted, not wired into CI. absoluteCeiling is .scrollFrame by decision.

Drills: (b) a zeroed width multiplier reddens the checksum pin, (c) un-prefixing
the latency keys reddens the line-shape pin, (j) halving the deep line's cells
reddens the parameter pin.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 9: D-33 — the `wrap_compute` checksum's completeness

The slice-55a review's falsifiability audit found one guarantee out of nine with **no recorded red**, and it is the one two ratified decisions lean on: `--wrap-compute`'s `checksum=` is the result-preservation witness for Decisions 12 and 13, and `WrapBenchmarkLineShapeTests` pins only that the token is *printed* with the value it was handed. Zeroing the drain half — the half that witnesses **packing** — still prints a stable number, byte-identical across every column of the record, and every claim built on that byte-identity silently becomes vacuous. Both sibling checksums in the same target already close this hole. Scheduled into 55b by user call (2026-09-03).

**Files:**
- Modify: `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift` (extract the fold; the VALUE does not change)
- Create: `Tests/ViewportBenchmarksTests/WrapComputeChecksumTests.swift`

**The weights are 1 and 1, deliberately.** A weighted fold (`compute &+ drain &* 131`) would additionally catch a swap of the two halves — but it would change the printed value, and the spec's Verification section requires 55b's `--wrap-compute` run to be compared against **55a's final column** (`width_inf` 181094400, `width_40` 143365120, `width_10` 115068800). Byte-comparability with the record the two decisions rest on is worth more than swap-detection between two operands that are read from distinct measurements three lines apart. Record the trade-off in the ledger discharge.

- [ ] **Step 1: Write the failing pin**

Create `Tests/ViewportBenchmarksTests/WrapComputeChecksumTests.swift`:

```swift
import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

/// D-33. `--wrap-compute`'s `checksum=` is the witness Decisions 12 and 13 rest their
/// result-preservation argument on: both are result-preserving BY CONSTRUCTION, so neither
/// adds a result assertion, and what covers them is a fold over 100 000 lines at three
/// widths that stays byte-identical across every edit. Until this file, nothing pinned that
/// the fold can MOVE — a zeroed drain half would print an equally stable number and every
/// byte-identity claim built on it would be vacuous.
///
/// Two halves, two pins: the combination must read both operands, and the drain fold must
/// read every row rather than the first.
final class WrapComputeChecksumTests: XCTestCase {

    /// A layout identical to `base` except that ONE line is a cell shorter, which moves
    /// exactly one row's `endColumn` and nothing else: at 8 cells and width 4 the line
    /// packs [0,4) [4,8), and at 7 cells it packs [0,4) [4,7) — still two rows, so the
    /// prefix sum and row counts stay honest and only the fold can notice.
    private struct ShortenedLineLayout: VisualRowLayoutSource {
        let base: BenchmarkWrapLayout
        let shortLine: Int

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int {
            line == shortLine ? base.columnCount(inLine: line) - 1 : base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double { base.columnOffset(inLine: line, column: column) }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { base.canBreak(beforeColumn: column, inLine: line) }
        func visualRowCount(inLine line: Int) -> Int { base.visualRowCount(inLine: line) }
        func firstVisualRow(ofLine line: Int) -> Int { base.firstVisualRow(ofLine: line) }
    }

    /// Half 1: the printed value reads BOTH measurements. A reversion to
    /// `computeMeasured.checksum` alone is the exact defect D-33 names.
    func testBothHalvesAffectTheChecksum() {
        let base = wrapComputeChecksum(compute: 5, drain: 7)
        XCTAssertNotEqual(base, wrapComputeChecksum(compute: 6, drain: 7), "the compute half must be folded")
        XCTAssertNotEqual(base, wrapComputeChecksum(compute: 5, drain: 8), "the drain half must be folded")
        XCTAssertNotEqual(base, wrapComputeChecksum(compute: 5, drain: 0),
                          "zeroing the drain half must move the value -- it is the half that witnesses packing")
    }

    /// Half 2: the drain fold reads EVERY row's `endColumn`, not the first. `drainVisualRows`
    /// is what the checksum's drain half is made of, and a fold that stopped after one row
    /// would leave `WrapComputeDrainTests` (D-29) entirely green.
    func testDrainFoldsEveryRowsEndColumnNotTheFirst() {
        // 64 lines x 8 cells at width 4 -> 2 rows per line, 128 rows.
        let base = BenchmarkWrapLayout(lineCount: 64, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        let input = VariableViewportInput(scrollOffsetY: 40.0, viewportHeight: 100.0,
                                          overscanLinesBefore: 4, overscanLinesAfter: 4)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: base) else {
            return XCTFail("expected success")
        }

        // Find a row that is NOT the range's first and is its line's SECOND row -- the row
        // whose endColumn the perturbation moves. A first-row-only fold cannot see it.
        var streamed: [VisualRowGeometry] = []
        var cursor = ViewportVirtualizer.visualRowGeometry(for: range, layout: base)
        while let geometry = cursor.next() { streamed.append(geometry) }
        XCTAssertGreaterThan(streamed.count, 2, "the fixture must stream several rows")
        guard let target = streamed.dropFirst().first(where: { $0.row.rowInLine == 1 }) else {
            return XCTFail("the range must contain a non-first row that is its line's second row")
        }

        let perturbed = ShortenedLineLayout(base: base, shortLine: target.row.logicalLine)
        XCTAssertEqual(perturbed.visualRowCount(inLine: target.row.logicalLine), 2,
                       "the perturbation must move an endColumn, not a row count")

        let honest = drainVisualRows(range, layout: base)
        let moved = drainVisualRows(range, layout: perturbed)
        XCTAssertGreaterThan(honest, 0, "the drain must have streamed rows")
        XCTAssertEqual(honest - moved, 1,
                       "exactly one row's endColumn moved by one, and the fold must carry it")
    }
}
```

- [ ] **Step 2: Run it and confirm the compile failure**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapComputeChecksumTests 2>&1 | tail -10
```

Expected: a compile error — `cannot find 'wrapComputeChecksum' in scope`. That is the red for half 1. Half 2 (`testDrainFoldsEveryRowsEndColumnNotTheFirst`) compiles against the shipped `drainVisualRows` and its red is drill (o) below.

- [ ] **Step 3: Extract the fold — value unchanged**

In `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`, add above `runWrapComputeBenchmarks`:

```swift
/// The `wrap_compute` line's result-preservation witness, as a pure function so a test can
/// drive it (D-33). The compute half folds every computed range's length, the drain half
/// every drained row's `endColumn` — the half that witnesses PACKING, and the half whose
/// silent removal would leave a stable, plausible, meaningless number.
///
/// Both weights are 1, and that is a trade, not an oversight: a weighted fold would also
/// catch a swap of the two halves, but it would change the printed VALUE and break
/// byte-comparability with the slice-55a record that Decisions 12 and 13 rest on
/// (`width_inf` 181094400, `width_40` 143365120, `width_10` 115068800). The siblings'
/// distinct-multiplier rule exists to stop an INDEX fold from colliding; here the two
/// operands come from distinct measurements three lines apart.
func wrapComputeChecksum(compute: Int, drain: Int) -> Int {
    compute &+ drain
}
```

Then replace the call site:

```swift
        let checksum = computeMeasured.checksum &+ drainMeasured.checksum
```

with:

```swift
        let checksum = wrapComputeChecksum(compute: computeMeasured.checksum, drain: drainMeasured.checksum)
```

- [ ] **Step 4: Run the pin, then prove the VALUE did not move**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WrapComputeChecksumTests 2>&1 | tail -6
swift build -c release 2>&1 | tail -3
swift run -c release ViewportBenchmarks -- --wrap-compute 2>&1 | tee /tmp/slice55b-wrap-compute.txt
CHECKSUMS="$(sed -nE 's/.*width=([^ ]+).*checksum=([0-9-]+).*/\1 \2/p' /tmp/slice55b-wrap-compute.txt | sort)"
echo "$CHECKSUMS"
EXPECTED="$(printf '10 115068800\n40 143365120\ninf 181094400\n')"
if [ "$CHECKSUMS" = "$EXPECTED" ]; then echo "checksums=unchanged_from_55a"; else echo "checksums=MOVED -- this is a finding, stop"; fi
```

Expected: both tests green; `checksums=unchanged_from_55a`. A moved checksum here means the extraction was not value-preserving — stop and read it; it is a finding, not a number to update.

Record the whole `--wrap-compute` output in the verification record: the spec requires one 55b run against 55a's final column, and this slice touches no shipped path, so a movement in the timings is also a finding (subject to D-31: this host's own state variance reaches 2.84x, so read the timings as a record, not as a check).

- [ ] **Step 5: Drill (n) — the combination can fail**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/ViewportBenchmarks/WrapComputeBenchmark.swift'
s = open(p).read()
old = """func wrapComputeChecksum(compute: Int, drain: Int) -> Int {
    compute &+ drain
}"""
new = """func wrapComputeChecksum(compute: Int, drain: Int) -> Int {
    compute   // DRILL (n)
}"""
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapComputeChecksumTests 2>&1 | tail -8
swift test --filter WrapBenchmarkLineShapeTests 2>&1 | tail -4
git checkout -- Sources/ViewportBenchmarks/WrapComputeBenchmark.swift
```

Expected: **RED** — `testBothHalvesAffectTheChecksum` fails on "the drain half must be folded", while `WrapBenchmarkLineShapeTests` stays **green** (it passes a literal to the formatter and never reaches the fold). Record both halves: that asymmetry is precisely D-33's statement.

- [ ] **Step 6: Drill (o) — the drain fold's completeness**

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
p = 'Sources/ViewportBenchmarks/WrapComputeBenchmark.swift'
s = open(p).read()
old = "    while let geometry = cursor.next() { sink &+= geometry.row.endColumn }"
new = "    while let geometry = cursor.next() { sink &+= geometry.row.endColumn; break }   // DRILL (o)"
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
swift test --filter WrapComputeChecksumTests 2>&1 | tail -8
swift test --filter WrapComputeDrainTests 2>&1 | tail -4
git checkout -- Sources/ViewportBenchmarks/WrapComputeBenchmark.swift
swift test 2>&1 | tail -5
```

Expected: **RED** — `testDrainFoldsEveryRowsEndColumnNotTheFirst` fails on the `honest - moved == 1` assertion, while `WrapComputeDrainTests` (D-29) stays **entirely green**: its assertions are `sink > 0`, `firstVisualRowCalls > 0` and `firstVisualRowAtLineCount == 0`, all still true when the fold reads one row. Record that — it is the concrete demonstration that D-29's pin could not have covered D-33. Then the whole suite green after the revert.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/ViewportBenchmarks/WrapComputeBenchmark.swift Tests/ViewportBenchmarksTests/WrapComputeChecksumTests.swift
git commit -m "$(cat <<'MSG'
test: pin the wrap-compute checksum's completeness (D-33)

The witness Decisions 12 and 13 rest on had no recorded red: zeroing the drain
half -- the half that witnesses packing -- printed an equally stable number and
every byte-identity claim built on it went vacuous.

Two pins. The fold is extracted into a pure wrapComputeChecksum(compute:drain:)
so a test can assert both operands are read (drill (n): return the compute half
alone and it reddens, while the line-shape pin stays green). And drainVisualRows
is driven over two layouts differing in exactly one row's endColumn (drill (o):
fold only the first row and it reddens, while D-29's own test stays green --
which is why D-29 could not have covered this).

Both weights stay 1: a weighted fold would catch a swap but change the printed
value and break byte-comparability with the 55a record.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 10: Documentation, the ledger, and the spec amendment

Spec Documentation Updates (the 55b list), AC11, AC15. `docs/superpowers/arcs/wrap.md` is **not** touched here — node 4 is marked `done` and the map pass is written at the post-slice review, not in the slice (spec Documentation Updates says so explicitly).

**Files:**
- Modify: `AGENTS.md`
- Modify: `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift` (the `RiggedVisualRowLayout` comment)
- Modify: `docs/superpowers/debt-ledger.md` (D-18, D-25, D-33 → `discharged`)
- Modify: `docs/superpowers/specs/2026-08-24-wrap-point-query-design.md` (Decision 15, AC19, Revision History)

- [ ] **Step 1: `AGENTS.md` — the node 4 paragraph**

After the `visualRowAt` paragraph (the one ending "`--wrap-row-query` is its observational, **non-gateable** benchmark mode."), insert:

```markdown
`ViewportVirtualizer.visualPointAt(x:y:layout:)` is **node 4**: the wrap-aware `pointAt`
analog, mapping a point to `(visual row, cell)` over a **single**
`VisualRowLayoutSource` — the layout refines `WrapMetricsSource`, which refines
`LineHorizontalMetricsSource`, so one object serves both axes and `pointAt`'s standing
"the two sources must describe the same document" precondition disappears. It composes
`visualRowAt` (the whole vertical half, carried **verbatim** into
`VisualPointLocation.row`, guards included) with one
`columnIndex(containingOffset:inLine:)` dispatch, and adds **no search**: the shared
per-line ladder (`validateWrapLine`) and the shared within-line walk
(`advanceVisualRows`) are the same code `visualRows` and `DocumentVisualRowCursor` run.
`x` is measured from the located **row**'s left edge and both clamps land on the row's
edges, while the returned `columnIndex` is an index into the **logical line**, with
`rowSpan.startColumn` as the bridge; on an **overflow** row an `x` between `wrapWidth`
and `rowSpan.width` is `.inRange`, because the comparison is against the row's own
advance sum. A non-finite `x` is a failure, not a clamp, and is checked before any
horizontal work, so it costs zero column-metric probes; `.empty` still beats it, and it
beats `.blankLine`. Cost: O(log totalRows) + O(log lineCount) + the inherited
within-line walk + O(log cells-in-line), with `3 + 2` column-axis probes on a fitting
line when it clamps and `3 + 2 + 1` plus one hook call when it delegates; O(1) core
memory. Step 7 rebases `x` by the row's left offset, answers from the ladder's stored
`total` when the rebased value rounds onto the line's width (the hook's precondition is
`x < lineWidth` and it does not clamp), and otherwise clamps the hook's answer into the
row's span — the index only, never the flag. The one failure it adds of its own is a
layout whose row counts disagree with the packer, so the walk runs out before the row it
was asked for: `.failure(.invalidVisualRowLayout)`, not a fabricated row. At `wrapWidth =
∞` (or any width no line exceeds) it is bit-identical to `pointAt` over a uniform
vertical axis **on the located branch** — the failure orderings diverge by design
(equivalence oracle). Geometry is a later companion, smaller than the family's precedent
suggests: its vertical half is arithmetic, so it adds one axis's box and fractions.
`--wrap-point-query` is its observational, **non-gateable** benchmark mode.
```

- [ ] **Step 2: `AGENTS.md` — commands and the two flag lists**

Three edits, each by matching text:

1. In the commands block, after the `--wrap-row-query` line:
```
swift run -c release ViewportBenchmarks -- --wrap-point-query   # observational wrap (x,y)->(row,cell) query benchmark (amortised; not gateable)
```
2. In the benchmark-flag list, `` `--memory-observation`, `--wrap-compute`, `--wrap-row-query`, `--gate`. Only one mode `` becomes `` `--memory-observation`, `--wrap-compute`, `--wrap-row-query`, `--wrap-point-query`, `--gate`. Only one mode ``.
3. In the `--gate`-rejection sentence, `` `--memory-observation`, `--wrap-compute`, `--wrap-row-query`. `` becomes `` `--memory-observation`, `--wrap-compute`, `--wrap-row-query`, `--wrap-point-query`. ``.
4. `Both wrap modes measure on the same **amortised** shape` becomes `All three wrap modes measure on the same **amortised** shape`.

- [ ] **Step 3: `AGENTS.md` — verify the inventory needs nothing**

The spec's Documentation Updates lists a `Tests/ViewportBenchmarksTests` head-count repair ("it says the target holds five files and names five"). Check whether 55a already did it:

```bash
cd /Users/aabanschikov/swift-text-engine
HEADCOUNT="$(grep -n 'five files\|holds five\|five test files' AGENTS.md || true)"
if [ -z "$HEADCOUNT" ]; then echo "headcount=already_repaired"; else echo "headcount=STILL_PRESENT"; echo "$HEADCOUNT"; fi
```

Expected: `headcount=already_repaired` (55a's documentation pass replaced the count with "the head-count is deliberately not stated"). If it is still present, replace the count with that wording as the spec directs.

- [ ] **Step 4: Correct the `RiggedVisualRowLayout` comment**

In `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift`, replace:

```swift
/// Hand-riggable `VisualRowLayoutSource` for validation-ladder tests: aggregates are set
/// directly (so `firstVisualRow(0)`, `totalRows`, `rowHeight`, `wrapWidth`, `lineCount`
/// can be made malformed). Column metrics are stubbed — `compute(_:layout:)` never reads
/// them (only the cursor does, and validation tests build no cursor).
```

with:

```swift
/// Hand-riggable `VisualRowLayoutSource` for validation-ladder tests: aggregates are set
/// directly (so `firstVisualRow(0)`, `totalRows`, `rowHeight`, `wrapWidth`, `lineCount`
/// can be made malformed). Column metrics are stubbed as a BLANK LINE (`columnCount == 0`,
/// `columnOffset == 0`): `compute(_:layout:)` never reads them at all, and `visualRowAt`
/// does not either. `visualPointAt` is the first query that does — it builds the per-line
/// cursor — so on a rigged layout it sees one packed `[0, 0)` row per line. That is not a
/// limitation but the fixture for `WrapPointQueryValidationTests`' walk-exhaustion case: a
/// prefix sum claiming more rows than the packer produces.
```

- [ ] **Step 5: Amend the spec with the D-33 fold-in**

The spec was ratified before the slice-55a review opened D-33 and before the user scheduled it into 55b, so the fold-in is added as an amendment rather than smuggled in as a plan step with no design of record.

1. After Decision 14, add:

```markdown
### Decision 15 — D-33's completeness pin rides in 55b, with the fold's weights unchanged

**User call** (2026-09-03, at the slice-55b selection). The slice-55a review's
falsifiability audit found `--wrap-compute`'s `checksum=` to be the only guarantee in that
piece with no recorded red — and it is the witness Decisions 12 and 13 rest their
result-preservation argument on. The pin lands here, in the slice that already adds two
benchmark-target test files.

Two halves, because the hole has two shapes: the printed value must read **both**
measurements (the fold is extracted into a pure `wrapComputeChecksum(compute:drain:)` so a
test can drive it), and the drain half must fold **every** row's `endColumn` rather than
the first (`drainVisualRows` driven over two layouts differing in exactly one row's
`endColumn`, as the ledger row prescribes).

**The weights stay 1 and 1.** A weighted fold would additionally catch a swap of the two
halves, at the cost of changing the printed value — and the Verification section requires
55b's `--wrap-compute` run to be byte-comparable against **55a's final column**, which is
the evidence the two decisions rest on. The siblings' distinct-multiplier rule exists to
stop an *index* fold from colliding; here the two operands come from distinct measurements
three lines apart, and the swap is not a live defect. Recorded so a later reader does not
"repair" the weights and silently break the comparison.
```

2. After acceptance criterion 18, add:

```markdown
19. **D-33 discharged** (Decision 15): `wrapComputeChecksum(compute:drain:)` is a pure
    function pinned to read both operands, `drainVisualRows` is pinned to fold every row's
    `endColumn` over two layouts differing in exactly one of them, both with recorded reds
    ((n) and (o)) — and each red leaves the sibling guard green (the line-shape pin for
    (n), D-29's own test for (o)), which is what shows neither existing pin covered it. The
    printed `checksum=` value is byte-identical to 55a's final column.
```

3. Append to Revision History:

```markdown
11. **2026-09-03, eleventh pass** (amendment, not a review pass). **Decision 15** and
    **AC19** add the D-33 fold-in the slice-55a review made mandatory and the user
    scheduled into 55b; the 55b plan is written against this amendment. Nothing else in the
    body changed.
```

- [ ] **Step 6: Discharge the three ledger rows**

In `docs/superpowers/debt-ledger.md`, replace the status cell (the last column) of each row:

- **D-18** — `open` becomes:
  `discharged([slice 55b](plans/2026-09-03-wrap-point-query.md)): the AC13 checksum-extraction step is written with the `grep -v -e 'mode=memory_shape' -e 'mode=memory_observation'` filter, so the hosted count reads 46 and not 54, and the plan contains no `${PIPESTATUS[0]}` (D-17)`
- **D-25** — `open` becomes:
  `discharged([slice 55b](plans/2026-09-03-wrap-point-query.md)): TIGHTENED, not removed. `testProbeCountDoesNotGrowLinearlyWithTheDocument` becomes `testASecondSearchTargetHoldsTheSameTightBound` — the same second target, now held to `<= ceilLog2(lineCount) + 4` instead of `< lineCount / 10`. Reasoning recorded in the test: binary-search depth varies by target (13 probes at row 700, up to 14 at row 1000), so a regression that lengthens the search only for adversarial targets is visible there and nowhere else, which is a claim its sibling does not make`
- **D-33** — the `scheduled(slice-55b)` text becomes:
  `discharged([slice 55b](plans/2026-09-03-wrap-point-query.md), spec Decision 15): `WrapComputeChecksumTests` pins both halves — the fold reads both operands (drill (n): returning the compute half alone reddens it while the line-shape pin stays green) and `drainVisualRows` folds every row's `endColumn` (drill (o): folding only the first row reddens it while D-29's own test stays green). The fold's weights stay 1 and 1 on purpose, so the printed value remains byte-comparable with 55a's final column; a weighted fold would buy swap-detection and cost that comparison`

- [ ] **Step 7: Verify the ledger's own conventions still hold**

```bash
cd /Users/aabanschikov/swift-text-engine
BADSTATUS="$(grep -E '^\| D-' docs/superpowers/debt-ledger.md | awk -F'|' '{print $NF}' | grep -vE 'open|scheduled\(slice-[0-9]+[ab]?\)|discharged\(|deferred\(user, [0-9-]+\)|accepted-risk' || true)"
if [ -z "$BADSTATUS" ]; then echo "ledger_status=ok"; else echo "ledger_status=BAD"; echo "$BADSTATUS"; fi
ROWS="$(grep -cE '^\| D-' docs/superpowers/debt-ledger.md)"
echo "ledger_rows=$ROWS (expect 34)"
```

Expected: `ledger_status=ok`, `ledger_rows=34` (this slice opens no new row; if the implementation turns one up, add it and say so here).

- [ ] **Step 8: Run everything and commit**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test 2>&1 | tail -5
FOUNDATION="$(rg -n "Foundation" Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "foundation_scan=empty"; else echo "foundation_scan=DIRTY"; echo "$FOUNDATION"; fi
git add AGENTS.md Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift docs/superpowers/debt-ledger.md docs/superpowers/specs/2026-08-24-wrap-point-query-design.md
git commit -m "$(cat <<'MSG'
docs: node 4 in AGENTS.md; discharge D-18, D-25 and D-33; amend the spec

AGENTS.md gains the visualPointAt paragraph beside visualRowAt, the
--wrap-point-query command, both flag lists, and "all three wrap modes" for the
amortised shape. The RiggedVisualRowLayout comment is corrected: visualPointAt
is the first query that reaches its stubbed column metrics, which is what makes
the walk-exhaustion fixture work.

Spec Decision 15 and AC19 record the D-33 fold-in as a design amendment rather
than a plan step with no design of record, including why the fold's weights
stay 1 and 1.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
```

---

## Task 11: Verification evidence, the record, the PR, and hosted proof

Spec Verification and AC13/AC15/AC16. Evidence is **commands and their actual output**, pasted — not prose written about them.

**Files:**
- Create: `docs/superpowers/verification/2026-09-03-wrap-point-query.md`

- [ ] **Step 1: The suite, the release build, and the Foundation scan**

```bash
cd /Users/aabanschikov/swift-text-engine
mkdir -p /tmp/slice55b
swift test 2>&1 | tee /tmp/slice55b/suite.txt | tail -5
swift build -c release 2>&1 | tee /tmp/slice55b/release-build.txt | tail -3
FOUNDATION="$(rg -n "Foundation" Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "foundation_scan=empty"; else echo "foundation_scan=DIRTY"; echo "$FOUNDATION"; fi
BENCH_FOUNDATION="$(rg -n "^import Foundation" Sources/ViewportBenchmarks || true)"
if [ -z "$BENCH_FOUNDATION" ]; then echo "benchmarks_import_foundation=none"; else echo "benchmarks_import_foundation=PRESENT"; echo "$BENCH_FOUNDATION"; fi
```

Expected: `Executed <N> tests, with 0 failures` with `N` = 425 (55a's total) + this slice's additions; a clean release build; `foundation_scan=empty`. The benchmark target has never imported Foundation (`String(format:)` is unavailable there — `WrapComputeBenchmark` says so) and this slice must not be the first.

- [ ] **Step 2: All twelve blocking gates, and the checksum baseline diff**

Not `--gate` alone: this slice touches no gated code path, so **any** movement in **any** of the twelve is a finding, and eleven would go unread if only the synthetic pipeline were recorded. Written out one line per mode — do **not** loop over a variable holding the flags: agent shells here are zsh, which does not word-split an unquoted parameter, so the loop would silently run the default pipeline twelve times.

```bash
cd /Users/aabanschikov/swift-text-engine
: > /tmp/slice55b/gates.txt
swift run -c release ViewportBenchmarks -- --gate                          >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --variable-height --gate        >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --structural-mutation --gate    >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --line-query --gate             >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate    >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --column-query --gate           >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --column-geometry-query --gate  >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --point-query --gate            >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --point-geometry-query --gate   >> /tmp/slice55b/gates.txt 2>&1
swift run -c release ViewportBenchmarks -- --realistic-provider --gate     >> /tmp/slice55b/gates.txt 2>&1
PASS="$(grep -c 'gate=pass' /tmp/slice55b/gates.txt)"
FAIL="$(grep -c 'gate=fail' /tmp/slice55b/gates.txt)"
echo "gate_pass=$PASS gate_fail=$FAIL (expect 46 and 0)"
```

Then the checksum baseline diff. **D-18**: the `grep -v` filter is what makes the count 46 rather than 54 — a hosted log also carries five `mode=memory_shape` and three `mode=memory_observation` lines with `mode=`/`scenario=`/`checksum=` fields, and the literal `extract_checksums` recipe matches them. The filter is applied here too, so the local and hosted extractions are the same recipe.

```bash
cd /Users/aabanschikov/swift-text-engine
grep -v -e 'mode=memory_shape' -e 'mode=memory_observation' /tmp/slice55b/gates.txt \
  | sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9-]+).*/\1|\2\t\3/p' \
  | sort -u > /tmp/slice55b/checksums-local.tsv
awk '/^### The 46 hosted checksum tuples/,0' docs/superpowers/verification/2026-08-28-wrap-point-query-trap-repairs.md \
  | awk '/^```/{n++; next} n==1' | sort -u > /tmp/slice55b/checksums-baseline.tsv
echo "local=$(wc -l < /tmp/slice55b/checksums-local.tsv | tr -d ' ') baseline=$(wc -l < /tmp/slice55b/checksums-baseline.tsv | tr -d ' ') (expect 46 and 46)"
DIFF="$(diff /tmp/slice55b/checksums-baseline.tsv /tmp/slice55b/checksums-local.tsv || true)"
if [ -z "$DIFF" ]; then echo "checksum_diff=empty"; else echo "checksum_diff=NON_EMPTY -- a finding, not noise"; echo "$DIFF"; fi
```

Expected: `gate_pass=46 gate_fail=0`, both counts 46, `checksum_diff=empty`. The baseline is 55a's recorded **hosted** tuples; checksums are deterministic, so hardware changes timings and never these values.

- [ ] **Step 3: The three wrap modes and the memory invariant**

```bash
cd /Users/aabanschikov/swift-text-engine
swift run -c release ViewportBenchmarks -- --wrap-row-query    2>&1 | tee /tmp/slice55b/wrap-row-query.txt
swift run -c release ViewportBenchmarks -- --wrap-point-query  2>&1 | tee /tmp/slice55b/wrap-point-query.txt
swift run -c release ViewportBenchmarks -- --memory-shape      2>&1 | tee /tmp/slice55b/memory-shape.txt | tail -3
./.github/scripts/cross-target-compile.sh --self-test 2>&1 | tail -3
```

Expected: `--wrap-row-query`'s four `checksum=` tokens **byte-identical** to 55a's record (`uniform_1k` 20459520000, `uniform_100k` 2047976320000, `narrow_100k` 2240234540000, `clamped_100k` 2240231040000) — D-25 touched its tests, not its code, so a movement is a finding; six `wrap_point_query` lines; `invariant=pass`; the self-test green. `--wrap-compute` was already run and checked in Task 9 Step 4 — carry that output into the record rather than re-running it (its host-to-host spread is 2.84x, D-31, so a second run's timings would invite a comparison the host cannot support).

The `cross-target-compile.sh --self-test` is **shell logic only** — it compiles nothing and is not portability evidence. This slice adds public core API, so its portability evidence is the two hosted jobs in Step 6.

- [ ] **Step 4: Write the verification record**

Create `docs/superpowers/verification/2026-09-03-wrap-point-query.md` with these sections, each filled from the scratch file named beside it — evidence pasted, not summarized:

1. **Header** — branch, PR, spec, plan, commits in order with their one-line subjects.
2. **Acceptance-criteria table** — one row per AC this piece owns (1, 2, 3, 4, 5's 55b half, 6, 7, 8's round-trip half, 11, 12, 13, 14, 15, 16, 19), each with its disposition and the section that proves it.
3. **The fourteen drills** — one row each: (a), (b), (c), (d1), (d2), (d3), (e), (g), (h), (i), (j), (k), (n), (o) — with the exact observed failure line, and for the four that are asymmetric ((d1)/(d2) trapping without a query edit, (e)/(k) leaving each other's fixture green, (h) leaving the ±∞ result tests green, (i)'s observed difference against its bound, (n)/(o) leaving their sibling guards green) **both** halves recorded. A drill without its observed red is an unfinished acceptance criterion, not a review finding.
4. **Suite, release build, Foundation scan** — `/tmp/slice55b/suite.txt`, `/tmp/slice55b/release-build.txt`, the scan's `foundation_scan=empty`.
5. **The twelve gates** — `/tmp/slice55b/gates.txt` (the 46 summary lines), the `gate_pass`/`gate_fail` counts, and the checksum diff with its `checksum_diff=empty`.
6. **The three wrap modes and `--memory-shape`** — `/tmp/slice55b/wrap-row-query.txt` with the four-checksum comparison against 55a, `/tmp/slice55b/wrap-point-query.txt` in full (six scenarios), Task 9's `--wrap-compute` output with its three-checksum comparison, `/tmp/slice55b/memory-shape.txt`.
7. **Hosted proof** — Step 6 below, both runs, at step level.
8. **Deviations from the spec, with reasons** — the raised scenario floors (Task 8), Decision 15 and AC19 (the D-33 amendment, Task 10), and anything the implementation turned up. A deviation recorded here is a decision; one that is not is drift.

- [ ] **Step 5: Commit the record and open the PR**

```bash
cd /Users/aabanschikov/swift-text-engine
git add docs/superpowers/plans/2026-09-03-wrap-point-query.md docs/superpowers/verification/2026-09-03-wrap-point-query.md
git commit -m "$(cat <<'MSG'
docs: slice 55b plan and verification record

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
MSG
)"
git push -u origin slice-55b-wrap-point-query
gh pr create --repo maldrakar/swift-text-engine --base main --head slice-55b-wrap-point-query \
  --title "Slice 55b: wrap-aware point query (visualPointAt) — node 4" \
  --body "$(cat <<'PRBODY'
Node 4 proper, the second of the slice-55 split: `ViewportVirtualizer.visualPointAt(x:y:layout:)`, the wrap-aware `(x, y) → (visual row, cell)` composite over a **single** `VisualRowLayoutSource`. Criterion 3 (`wrap-aware query analogs + ∞ oracle`) closes its last enumerated analog.

**No new search.** The vertical half is `visualRowAt` carried verbatim (its guards included, and a pin at both clamp edges says so); the horizontal half is one `columnIndex` dispatch on the delegating path. The shared per-line ladder and the shared within-line walk are 55a's, so the query and `DocumentVisualRowCursor` agree on "row *k* of line *L*" by construction — pinned by a round trip over a fixture carrying both of `greedyEnd`'s branches.

**`x` is row-relative, the index is line-absolute**, with `rowSpan.startColumn` as the bridge; on an overflow row an `x` between `wrapWidth` and `rowSpan.width` stays `.inRange`. Decision 6's two `1e16` fixtures pin the FP clamp and the `>= total` guard, and each drill leaves the other fixture green. A non-finite `x` fails before any horizontal work — the only observation of that placement is the zero-column-probe assertion, and drill (h) reddens it while the ±∞ result tests stay green.

**Probe table pinned** on two counters and two fixtures: `<= ceilLog2(lineCount) + 4` on the layout axis with no `totalRows` term, zero column-metric calls on every non-located path, exactly `3 + 2` clamped and `3 + 2 + 1` plus one dispatch delegating, and growth with `rowInLine` bounded below by `endColumn(k+m) − endColumn(k)` (drill (i) shows a bare "strictly more" would have passed).

**`--wrap-point-query`** is a new observational mode — six scenarios, `long_line_deep_row` measuring the within-line walk at 400 rows per line, with its own O(`lineCount` + `cells`) layout so the fixture is not fighting an O(N × cells) setup. Not gateable, `--gate` rejected, latency keys prefixed, not wired into CI.

**Fold-ins: D-25, D-18 and D-33 discharged.** D-33 is the slice-55a review's mandatory falsifiability option — `--wrap-compute`'s `checksum=` now has a completeness pin on both halves, with the fold's weights deliberately unchanged so the printed value stays byte-comparable with 55a's record.

Fourteen recorded reds. 46 gated checksums byte-identical to the pre-branch baseline; twelve gates `gate=pass`; Foundation scan empty. See `docs/superpowers/verification/2026-09-03-wrap-point-query.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_017mqDLc9fAUHbw7Bkw6uv2f
PRBODY
)"
```

- [ ] **Step 6: Read the PR-head run at step level**

A green job can hide a dead `continue-on-error` step, so read steps, not conclusions.

```bash
cd /Users/aabanschikov/swift-text-engine
RUN="$(gh run list -R maldrakar/swift-text-engine --workflow swift-ci.yml --branch slice-55b-wrap-point-query --limit 1 --json databaseId --jq '.[].databaseId')"
echo "run=$RUN"
gh run view "$RUN" -R maldrakar/swift-text-engine --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'
gh run view "$RUN" -R maldrakar/swift-text-engine --log > /tmp/slice55b/hosted-prhead.log 2>&1
echo "gate=pass lines: $(grep -c 'gate=pass' /tmp/slice55b/hosted-prhead.log) (expect 46)"
echo "gate=fail lines: $(grep -c 'gate=fail' /tmp/slice55b/hosted-prhead.log) (expect 0)"
rg -n "Executed [0-9]+ tests" /tmp/slice55b/hosted-prhead.log | tail -1
echo "blocking compile lines: $(grep -c 'result=pass.*blocking=true' /tmp/slice55b/hosted-prhead.log) (expect 8: 4 WASM + 4 iOS)"
grep -v -e 'mode=memory_shape' -e 'mode=memory_observation' /tmp/slice55b/hosted-prhead.log \
  | sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9-]+).*/\1|\2\t\3/p' | sort -u > /tmp/slice55b/checksums-hosted.tsv
echo "hosted checksum tuples: $(wc -l < /tmp/slice55b/checksums-hosted.tsv | tr -d ' ') (expect 46)"
HOSTED_DIFF="$(diff /tmp/slice55b/checksums-baseline.tsv /tmp/slice55b/checksums-hosted.tsv || true)"
if [ -z "$HOSTED_DIFF" ]; then echo "hosted_checksum_diff=empty"; else echo "hosted_checksum_diff=NON_EMPTY"; echo "$HOSTED_DIFF"; fi
```

Expected: three jobs `success`; 46 / 0 / the suite count / 8 / 46 / `hosted_checksum_diff=empty`. Note that `--wrap-point-query` does **not** run in CI (it is not wired in), so no `wrap_point_query` line appears in the hosted log — that absence is correct, not a missing step.

Paste all of it into §7 of the record and commit as `docs: slice 55b hosted proof (PR-head run <id>)`.

- [ ] **Step 7: After merge, the post-merge push run**

Repeat Step 6 with `--branch main`, append to §7, and open the docs-only follow-up PR as every slice does. Then the post-slice review, which is a live `choosing-next-slice` Mode-2 run: it marks node 4 `done` on the map, writes the map pass (including the three things the spec's Documentation Updates says that pass must carry — the two-slice consumption, the within-line random-access node restored to node 7 with a **numeric** trigger, and criterion 3's evidence cell stating the oracle's located-branch scoping), and selects slice 56, which the user has already confirmed as the infrastructure slice: **D-27 + D-34 + D-17 + D-9**, all four `scheduled(slice-56)` in the ledger.

---

## Plan Self-Review

**1. Spec coverage (Contract 55b + Decision 15).**

| Contract 55b item | Task |
|---|---|
| Public API — `VisualPointQuery`, `VisualPointLocation`, `visualPointAt` | 1 |
| The ladder, steps 1–7 | 1 |
| Decision 1 (row-relative `x`, clamps on the row's edges) | 1 |
| Decision 2 (line-absolute index) + its swept property | 1, 2 |
| Decision 3 (result shape, the verbatim `row`, the duplicated fields, the naming collision in the doc comments) | 1, 2 |
| Decision 4 (composition; the shared walk; guards at the producers) | 1, 4 |
| Decision 5 (the ladder's precedence; both structural pairs) | 4 |
| Decision 6 (the FP clamp, two fixtures) | 3 |
| Decision 7 (blank row read from the span) | 1, 4 |
| Decision 8 (naming), Decision 10 (file placement) | 1, 8 |
| Decision 9 (index-only; the companion's two notes) | recorded for the review's map pass — 11 Step 7 |
| Decision 11 (D-13 not folded in) | no task, by design |
| Decision 14 (step 7 calls the hook directly; the `>= total` guard) | 1, 3 |
| Decision 15 + AC19 (the D-33 fold-in) | 9, 10 |
| Probe-count table (four rows) | 5 |
| `WrapPointQueryEquivalenceTests` | 6 |
| `WrapPointQueryTests` | 1, 2, 3 |
| `WrapPointQueryValidationTests` | 4 |
| `WrapPointQueryCountTests` | 5 |
| `WrapPointQueryRoundTripTests` | 7 |
| `WrapPointQueryChecksumTests`, `WrapPointQueryOptionsTests`, three `WrapBenchmarkLineShapeTests` cases | 8 |
| `--wrap-point-query`: mode, `isGateable`, `absoluteCeiling`, parsing, `--help`, the layout, the scenario table, the checksum, the tokens | 8 |
| D-25 | 5 |
| D-18 | 11 Step 2 (the `grep -v` filter), 10 (the ledger) |
| D-33 | 9, 10 |
| Documentation — `AGENTS.md`, the `RiggedVisualRowLayout` comment, the ledger, the arc (review, not here) | 10, 11 |
| Verification record + hosted proof, both runs | 11 |
| Twelve drills (a)–(k) + (n), (o) | 6 (a), 8 (b, c, j), 4 (d1, d2, d3), 3 (e, k), 2 (g), 5 (h, i), 9 (n, o) |

**Deliberately not in this plan** (55a's, already merged): the five guards, `advanceVisualRows`, `validateWrapLine`, the `greedyEnd` short-circuit, `WrapPackingCountTests`, `VisualRowDispatchTests`, `WrapComputeDrainTests`, drills (d1)'s producer half, (f1)–(f4), (l), (m). This plan **consumes** them and re-observes (d1) through the composite. **Deliberately deferred**: the geometry companion (Decision 9), D-13 (Decision 11), node 6's gate promotion, and the map pass itself.

**2. Placeholder scan.** No "TBD"/"TODO"/"similar to Task N". Every code step carries its code; every assertion carries its expected output and, where the command's exit status is insensitive to the invariant, an `if`/`else` printing both branches. No `${PIPESTATUS[0]}` (D-17). No step asserts this plan's own HEAD commit. Every command block assigns the variables it reads (`FOUNDATION`, `BENCH_FOUNDATION`, `HEADCOUNT`, `BADSTATUS`, `ROWS`, `PASS`, `FAIL`, `DIFF`, `HOSTED_DIFF`, `CHECKSUMS`, `EXPECTED`, `RUN`), and no block reads a variable another block set. The twelve gate invocations are written out rather than looped over a flags variable, because zsh does not word-split an unquoted parameter and the loop would run the default pipeline twelve times while printing `gate=pass` convincingly.

**3. Type consistency.** `VisualPointLocation(row:rowSpan:column:)` is used with that argument order and those labels in Tasks 1, 2, 3, 4, 6, 7 and 8. `VisualRowLocation(globalRow:logicalLine:rowInLine:clamp:)`, `VisualRow(logicalLine:rowInLine:startColumn:endColumn:width:)`, `ColumnLocation(columnIndex:clamp:)` and `ColumnResolution.cell`/`.blankLine` match the shipped declarations in `ViewportTypes.swift`. `validateWrapLine` returns `WrapLineMetrics.valid(count:total:)`; `VisualRowCursor.init(line:columnCount:total:wrapWidth:metrics:)` and `advanceVisualRows(_:by:)` match `VisualRowCursor.swift` and `DocumentVisualRowCursor.swift`. `formatWrapPointQueryLine` is called with the same eleven labels in Task 8's benchmark and in its line-shape test. `wrapComputeChecksum(compute:drain:)` is used with those labels in Task 9's benchmark and test.

**4. One residual, stated rather than hidden.** Task 3's fixtures rest on `1e16 + 3.9 == 1e16 + 4.0` in IEEE double, checked by hand in the spec and asserted in the test itself. If the assertion fails on the executing host, spec Decision 6 says what to do: remove the clamp and document the property as contract-dependent — not keep an unreachable branch and an untestable claim.
