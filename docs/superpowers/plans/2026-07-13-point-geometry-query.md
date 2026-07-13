# Point-Geometry Query (`pointGeometryAt`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ViewportVirtualizer.pointGeometryAt(x:y:lineMetrics:columnMetrics:)` — the geometry-bearing 2D hit-test — and ship it with a latency budget *derived* from hosted evidence gathered inside this same PR.

**Architecture:** Pure composition of the two existing 1D geometry queries: `lineGeometryAt(y:)` runs first, its located line index feeds `columnGeometryAt(x:inLine:)`. The core gains **no new search and no new arithmetic** — every box, fraction, and clamp flag comes from the single existing implementation on that axis. Cost equals `pointAt`'s plus exactly four constant probes.

**Tech Stack:** Swift 6.0 (`swift-tools-version: 6.0`), XCTest, SwiftPM. No dependencies. Bash + `gh` for the CI-log harvest.

**Spec:** `docs/superpowers/specs/2026-07-13-point-geometry-query-design.md` — read it before Task 1. Decision numbers referenced below are its Decisions.

## Global Constraints

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty. (Test targets may import it; `Tests/ViewportBenchmarksTests/GateFloorTests.swift` already does.)
- **Swift Embedded compatible; compiles for iOS and WASM with no source changes.** Stdlib only in the core.
- **Zero-dependency.** No third-party packages.
- **Core-owned memory must not grow with document size.** This query is O(1) core memory.
- **Never hand-type a budget.** Budgets come only from `.github/scripts/derive-gate-budgets.sh` run against the committed corpus. Before derivation the scenario table holds `nil`, never a placeholder number.
- **One logical step per commit**, conventional prefixes: `feat:`, `test:`, `refactor:`, `docs:`, `ci:`.
- **Branch:** `slice-39-point-geometry-query` (already created; the design doc is committed on it).
- **Strictly additive:** `pointAt`, `lineAt`, `lineGeometryAt`, `columnAt`, `columnGeometryAt`, `compute`, both metrics protocols, `ViewportValidationError`, and every provider are **untouched**. If the diff modifies any of them, the slice has drifted.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Sources/TextEngineCore/ViewportTypes.swift` | Modify (append after the `ColumnResolution` block, currently ending ~line 226) | The three new public result types |
| `Sources/TextEngineCore/PointGeometryQuery.swift` | Create | The `pointGeometryAt` extension — nothing else |
| `Tests/TextEngineCoreTests/PointGeometryAtTests.swift` | Create | Hardcoded expectations: every row of Decision 7, clamps, blank line, reconstruction |
| `Tests/TextEngineCoreTests/PointGeometryAtEquivalenceTests.swift` | Create | The three parity oracles (vs `pointAt`, vs `lineGeometryAt`, vs `columnGeometryAt`) |
| `Tests/TextEngineCoreTests/PointGeometryAtQueryCountTests.swift` | Create | Pins Decision 3: exactly **+2** `offset` and **+2** `columnOffset` probes over `pointAt` |
| `Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift` | Create | The `--point-geometry-query` mode: scenarios (nil budgets first), geometry-folding checksum |
| `Sources/ViewportBenchmarks/BenchmarkOptions.swift` | Modify | `BenchmarkMode.pointGeometryQuery`, flag, help text, temporary `--gate` rejection |
| `Sources/ViewportBenchmarks/BenchmarkProgram.swift` | Modify | Dispatch to the new runner |
| `Tests/ViewportBenchmarksTests/PointGeometryQueryOptionsTests.swift` | Create | Flag parses; `--gate` rejected before budgets exist, accepted after |
| `Tests/ViewportBenchmarksTests/GateFloorTests.swift` | Modify (`everyGatedBudget()`, after the `pointQueryScenarios()` loop) | The **twelfth** loop — without it the mode is gated but invisible to the floor test |
| `.github/workflows/swift-ci.yml` | Modify (host job, after the `--point-query --gate` step, before `--memory-shape`) | One observational step → later `--gate` + `continue-on-error` |
| `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` | Modify (append) | Hosted rows. **This existing dated file** — `GateFloorTests` hardcodes its path |
| `AGENTS.md` | Modify | Architecture paragraph, Commands, flag list, CI step list |
| `docs/superpowers/verification/2026-07-13-point-geometry-query.md` | Create | Verification record: commands, real output, run IDs, spread, prediction outcome |

---

### Task 1: Core — the three types and `pointGeometryAt`

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (append after the `ColumnResolution` enum)
- Create: `Sources/TextEngineCore/PointGeometryQuery.swift`
- Test: `Tests/TextEngineCoreTests/PointGeometryAtTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.lineGeometryAt(y:metrics:) -> LineGeometryQuery` and `ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:) -> ColumnGeometryQuery` (both exist); `LineGeometryLocation(geometry:fractionInLine:clamp:)`, `LineGeometry(lineIndex:y:height:)`, `ColumnGeometryLocation(geometry:fractionInColumn:clamp:)`, `ColumnGeometry(columnIndex:x:width:)` (all have public inits).
- Produces: `PointGeometryQuery` (`.geometry` / `.empty` / `.failure`), `PointGeometryLocation(line:column:)`, `ColumnGeometryResolution` (`.cell` / `.blankLine`), and `ViewportVirtualizer.pointGeometryAt(x:y:lineMetrics:columnMetrics:) -> PointGeometryQuery`. Tasks 2, 3 depend on these exact names.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TextEngineCoreTests/PointGeometryAtTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class PointGeometryAtTests: XCTestCase {
    // Hand-built horizontal source: advancesPerLine[line] = per-cell widths.
    // A blank line is an empty advance vector. Same shape as PointAtTests', plus an
    // `originShift` so the contract-violating case (columnOffset(_, 0) != 0) is
    // reachable without a second helper type.
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let advancesPerLine: [[Double]]
        var originShift: Double = 0.0
        func columnCount(inLine line: Int) -> Int { advancesPerLine[line].count }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            var sum = originShift
            for i in 0..<column { sum += advancesPerLine[line][i] }
            return sum
        }
    }

    // A horizontal source that reports a negative cell count, to reach
    // .negativeColumnCount on a successfully located line.
    private struct NegativeCountColumnMetrics: LineHorizontalMetricsSource {
        func columnCount(inLine line: Int) -> Int { -1 }
        func columnOffset(inLine line: Int, column: Int) -> Double { 0.0 }
    }

    // MARK: In-range hit — both boxes and both fractions

    func testInRangeHitCarriesBothBoxesAndFractions() {
        let v = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)       // totalHeight 160
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)  // lineWidth 40
        // y = 40 -> line 2, box [32, 48), fraction (40-32)/16 = 0.5
        // x = 20 -> cell 2, box [16, 24), fraction (20-16)/8  = 0.5
        let result = ViewportVirtualizer.pointGeometryAt(x: 20.0, y: 40.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 2, y: 32.0, height: 16.0),
                fractionInLine: 0.5,
                clamp: .inRange),
            column: .cell(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: 2, x: 16.0, width: 8.0),
                fractionInColumn: 0.5,
                clamp: .inRange))
        )))
    }

    // MARK: Decision 7 rows

    func testEmptyDocumentIsEmptyForFiniteCoordinates() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        for (x, y) in [(0.0, 0.0), (-5.0, -5.0), (999.0, 999.0)] {
            XCTAssertEqual(
                ViewportVirtualizer.pointGeometryAt(x: x, y: y, lineMetrics: v, columnMetrics: h), .empty)
        }
    }

    func testNegativeLineCountIsFailure() {
        // ClosureLineMetrics lives in Tests/TextEngineCoreTests/TestLineMetrics.swift and
        // is the established way to build an invalid vertical source. Do not add a helper.
        let v = ClosureLineMetrics(lineCount: -1, offsetForLine: { Double($0) * 16.0 })
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 0.0, y: 0.0, lineMetrics: v, columnMetrics: h),
            .failure(.negativeLineCount))
    }

    // offset(ofLine: 0) != 0 breaks the vertical metrics contract. The probe runs
    // BEFORE the empty short-circuit, so it fires even on a zero-line document.
    func testInvalidLineMetricsIsFailure() {
        let v = ClosureLineMetrics(lineCount: 4, offsetForLine: { 5.0 + Double($0) * 16.0 })
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 0.0, y: 0.0, lineMetrics: v, columnMetrics: h),
            .failure(.invalidLineMetrics))
    }

    // A non-positive total height is the other vertical-metrics failure.
    func testNonPositiveTotalHeightIsFailure() {
        let v = ClosureLineMetrics(lineCount: 4, offsetForLine: { _ in 0.0 })
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 0.0, y: 0.0, lineMetrics: v, columnMetrics: h),
            .failure(.invalidLineMetrics))
    }

    func testNegativeColumnCountOnLocatedLineIsFailureAndDiscardsTheLine() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(
                x: 5.0, y: 20.0, lineMetrics: v, columnMetrics: NegativeCountColumnMetrics()),
            .failure(.negativeColumnCount))
    }

    // columnOffset(inLine:column: 0) != 0 breaks the horizontal contract. The located
    // line is discarded: a failure on either axis means the query answered nothing.
    func testInvalidColumnMetricsOnLocatedLineIsFailure() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        // Every cell offset is shifted by 5, so columnOffset(_, 0) == 5 != 0.
        let h = ArrayColumnMetrics(advancesPerLine: Array(repeating: [8.0, 8.0], count: 4),
                                   originShift: 5.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 5.0, y: 20.0, lineMetrics: v, columnMetrics: h),
            .failure(.invalidColumnMetrics))
    }

    // MARK: Precedence — the four rules a refactor could silently reorder

    func testNonFiniteYBeatsEmptyDocument() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        for y in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(
                ViewportVirtualizer.pointGeometryAt(x: 0.0, y: y, lineMetrics: v, columnMetrics: h),
                .failure(.nonFiniteValue), "y=\(y)")
        }
    }

    func testEmptyDocumentBeatsNonFiniteX() {
        let v = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 4, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: .nan, y: 0.0, lineMetrics: v, columnMetrics: h),
            .empty)
    }

    func testNonFiniteXBeatsBlankLine() {
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 8.0], [], [8.0]])
        // y = 15 -> blank line 1; a non-finite x must still be a failure.
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: .nan, y: 15.0, lineMetrics: v, columnMetrics: h),
            .failure(.nonFiniteValue))
    }

    // MARK: Blank lines keep their line geometry

    func testBlankLocatedLineKeepsItsBox() {
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 8.0], [], [8.0]])
        // y = 15 -> line 1, box [10, 20), fraction 0.5; line 1 is blank.
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 5.0, y: 15.0, lineMetrics: v, columnMetrics: h),
            .geometry(PointGeometryLocation(
                line: LineGeometryLocation(
                    geometry: LineGeometry(lineIndex: 1, y: 10.0, height: 10.0),
                    fractionInLine: 0.5,
                    clamp: .inRange),
                column: .blankLine)))
    }

    // The most common real hit-test, and the exact gap the Slice 37 review left
    // open (its P3 #1): the document's last line is blank and the user clicks in
    // the empty area below it. It is the INTERSECTION of the vertical clamp and
    // the blank line, which every other test covers only separately.
    func testClickBelowADocumentWhoseLastLineIsBlank() {
        let v = UniformLineMetrics(lineCount: 3, lineHeight: 10.0)        // totalHeight 30
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 8.0], [8.0], []])  // last line blank
        let result = ViewportVirtualizer.pointGeometryAt(x: 4.0, y: 100.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(result, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 2, y: 20.0, height: 10.0),
                fractionInLine: 1.0,
                clamp: .clampedToBottom),
            column: .blankLine)))
    }

    // MARK: Clamped corners — all four, fractions pinned exactly

    func testBothAxesClampedTopLeft() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: -7.0, y: -3.0, lineMetrics: v, columnMetrics: h),
            .geometry(PointGeometryLocation(
                line: LineGeometryLocation(
                    geometry: LineGeometry(lineIndex: 0, y: 0.0, height: 16.0),
                    fractionInLine: 0.0,
                    clamp: .clampedToTop),
                column: .cell(ColumnGeometryLocation(
                    geometry: ColumnGeometry(columnIndex: 0, x: 0.0, width: 8.0),
                    fractionInColumn: 0.0,
                    clamp: .clampedToLeft)))))
    }

    func testBothAxesClampedBottomRight() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)        // totalHeight 64
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)  // lineWidth 40
        XCTAssertEqual(
            ViewportVirtualizer.pointGeometryAt(x: 999.0, y: 999.0, lineMetrics: v, columnMetrics: h),
            .geometry(PointGeometryLocation(
                line: LineGeometryLocation(
                    geometry: LineGeometry(lineIndex: 3, y: 48.0, height: 16.0),
                    fractionInLine: 1.0,
                    clamp: .clampedToBottom),
                column: .cell(ColumnGeometryLocation(
                    geometry: ColumnGeometry(columnIndex: 4, x: 32.0, width: 8.0),
                    fractionInColumn: 1.0,
                    clamp: .clampedToRight)))))
    }

    func testMixedClampsCompose() {
        let v = UniformLineMetrics(lineCount: 4, lineHeight: 16.0)
        let h = UniformColumnMetrics(columnsPerLine: 5, columnWidth: 8.0)
        // y clamped to top, x clamped to right.
        let topRight = ViewportVirtualizer.pointGeometryAt(x: 999.0, y: -1.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(topRight, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 0, y: 0.0, height: 16.0),
                fractionInLine: 0.0, clamp: .clampedToTop),
            column: .cell(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: 4, x: 32.0, width: 8.0),
                fractionInColumn: 1.0, clamp: .clampedToRight)))))
        // y clamped to bottom, x clamped to left.
        let bottomLeft = ViewportVirtualizer.pointGeometryAt(x: -1.0, y: 999.0, lineMetrics: v, columnMetrics: h)
        XCTAssertEqual(bottomLeft, .geometry(PointGeometryLocation(
            line: LineGeometryLocation(
                geometry: LineGeometry(lineIndex: 3, y: 48.0, height: 16.0),
                fractionInLine: 1.0, clamp: .clampedToBottom),
            column: .cell(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: 0, x: 0.0, width: 8.0),
                fractionInColumn: 0.0, clamp: .clampedToLeft)))))
    }

    // MARK: Reconstruction property — the fraction must reproduce the input

    func testInRangeGeometryReconstructsTheInputPoint() {
        let v = UniformLineMetrics(lineCount: 50, lineHeight: 13.0)        // totalHeight 650
        let h = UniformColumnMetrics(columnsPerLine: 7, columnWidth: 11.0)  // lineWidth 77
        for step in 0..<40 {
            let y = Double(step) * 16.1 + 0.3   // stays inside [0, 650)
            let x = Double(step % 7) * 11.0 + 3.7  // stays inside [0, 77)
            guard case let .geometry(p) = ViewportVirtualizer.pointGeometryAt(
                x: x, y: y, lineMetrics: v, columnMetrics: h),
                  case let .cell(cell) = p.column else {
                return XCTFail("expected a located cell at x=\(x) y=\(y)")
            }
            XCTAssertEqual(p.line.geometry.y + p.line.fractionInLine * p.line.geometry.height,
                           y, accuracy: 1e-9, "y reconstruction at step \(step)")
            XCTAssertEqual(cell.geometry.x + cell.fractionInColumn * cell.geometry.width,
                           x, accuracy: 1e-9, "x reconstruction at step \(step)")
        }
    }
}
```

> `ClosureLineMetrics(lineCount:offsetForLine:)` and `ListLineMetrics(heights:)` already exist in `Tests/TextEngineCoreTests/TestLineMetrics.swift` — they are the established helpers for invalid and variable-height vertical sources. Use them; do **not** add new ones.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter PointGeometryAtTests
```

Expected: FAIL — compile error, `cannot find 'PointGeometryLocation' in scope` / `type 'ViewportVirtualizer' has no member 'pointGeometryAt'`. A compile failure *is* the failing-test state here; do not proceed until you have seen it.

- [ ] **Step 3: Add the three types**

Append to `Sources/TextEngineCore/ViewportTypes.swift`, directly after the `ColumnResolution` enum that closes the `PointQuery` block:

```swift
/// The geometry-bearing 2D result: `pointGeometryAt`'s answer.
///
/// `PointQuery`'s shape with each component swapped for its geometry-bearing
/// counterpart — `LineLocation` -> `LineGeometryLocation`, `ColumnLocation` ->
/// `ColumnGeometryLocation`.
public enum PointGeometryQuery: Equatable {
    case geometry(PointGeometryLocation)  // a line was located (its cell may be blank)
    case empty                            // empty document: lineCount == 0
    case failure(ViewportValidationError) // vertical or horizontal validation failure
}

public struct PointGeometryLocation: Equatable {
    /// The located line's box + within-line fraction + vertical clamp, verbatim
    /// from `lineGeometryAt`. Always a real line — carried even when the cell is
    /// `.blankLine`, because the caret box of an empty line is exactly what a
    /// consumer needs there.
    public let line: LineGeometryLocation
    /// The located cell's box + within-cell fraction + horizontal clamp, or
    /// `.blankLine` if the located line has no cells.
    public let column: ColumnGeometryResolution

    public init(line: LineGeometryLocation, column: ColumnGeometryResolution) {
        self.line = line
        self.column = column
    }
}

public enum ColumnGeometryResolution: Equatable {
    case cell(ColumnGeometryLocation)     // a real cell was located, with its box
    case blankLine                        // located line has no cells (columnCount(inLine:) == 0)
}
```

- [ ] **Step 4: Add `pointGeometryAt`**

Create `Sources/TextEngineCore/PointGeometryQuery.swift`:

```swift
extension ViewportVirtualizer {
    /// The geometry-bearing companion to `pointAt(x:y:lineMetrics:columnMetrics:)`:
    /// maps a single point to the located line's box and the located cell's box,
    /// each with its within-box fraction and its clamp flag.
    ///
    /// Pure composition of `lineGeometryAt(y:metrics:)` and
    /// `columnGeometryAt(x:inLine:metrics:)`. It performs **no search of its own**
    /// (both inverse searches stay inside the 1D queries, which dispatch to the
    /// provider-native hooks) and **no arithmetic of its own** — every box and
    /// fraction is produced by the single existing implementation on that axis, so
    /// each component is equal, by construction, to what the corresponding 1D query
    /// would have returned. Over `pointAt` it adds exactly four constant probes (two
    /// `offset(ofLine:)`, two `columnOffset(inLine:column:)`), so it never adds a log
    /// factor and its per-provider cost class equals `pointAt`'s: O(log N) + O(log M)
    /// queries, O(1) core memory, zero allocation beyond the returned value structs.
    ///
    /// The vertical query runs first: its failure short-circuits (the horizontal
    /// query needs a valid `inLine`, which only a vertical success can supply) and an
    /// empty document returns `.empty`. On a located line, a horizontal failure
    /// surfaces at the top level and **discards** the located line — a `.failure`
    /// means the query answered nothing, on either axis — a blank line becomes
    /// `.blankLine` (still carrying the line's box), and a real cell becomes `.cell`.
    /// Both clamp flags carry through verbatim, so a point clamped on both axes
    /// records both, with each fraction pinned to exactly `0.0` or `1.0` rather than
    /// computed from a coordinate that lies outside the box.
    ///
    /// Validation is delegated entirely to the two 1D queries, so their precedence is
    /// inherited: each checks its own coordinate's finiteness before its own
    /// zero-count short-circuit. A non-finite `y` therefore beats `.empty`, and a
    /// non-finite `x` beats `.blankLine`. `x` is only ever examined by the horizontal
    /// query, so an empty document returns `.empty` even for a non-finite `x`.
    ///
    /// Caret snapping is a caller concern: this reports where the point fell (the
    /// cell, its box, and the fraction within it), not which caret index to round to.
    ///
    /// - Precondition: `lineMetrics` and `columnMetrics` must describe the same
    ///   document. The line index located by the vertical query is threaded into
    ///   `columnGeometryAt(inLine:)` over the horizontal source, whose `inLine` is an
    ///   unvalidated precondition (`LineHorizontalMetricsSource` carries no line
    ///   count, by design — a line-agnostic provider holds O(1) memory for a document
    ///   of any size), so the two sources must agree on the line count.
    public static func pointGeometryAt<VMetrics: LineMetricsSource, HMetrics: LineHorizontalMetricsSource>(
        x: Double,
        y: Double,
        lineMetrics: VMetrics,
        columnMetrics: HMetrics
    ) -> PointGeometryQuery {
        switch lineGeometryAt(y: y, metrics: lineMetrics) {
        case let .failure(error):
            return .failure(error)
        case .empty:
            return .empty
        case let .geometry(line):
            switch columnGeometryAt(x: x, inLine: line.geometry.lineIndex, metrics: columnMetrics) {
            case let .failure(error):
                return .failure(error)
            case .empty:
                return .geometry(PointGeometryLocation(line: line, column: .blankLine))
            case let .geometry(column):
                return .geometry(PointGeometryLocation(line: line, column: .cell(column)))
            }
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
swift test --filter PointGeometryAtTests
```

Expected: PASS, all tests green.

- [ ] **Step 6: Run the full suite and the Foundation scan**

```bash
swift test
rg -n "Foundation" Sources/TextEngineCore
```

Expected: the whole suite green (plus the harmless "0 tests in 0 suites" Swift Testing line), and the `rg` output **empty**.

- [ ] **Step 7: Commit**

```bash
git add Sources/TextEngineCore/ViewportTypes.swift \
        Sources/TextEngineCore/PointGeometryQuery.swift \
        Tests/TextEngineCoreTests/PointGeometryAtTests.swift
git commit -m "feat: add pointGeometryAt, the geometry-bearing 2D point query"
```

---

### Task 2: The parity oracles and the probe-count pin

These are what the chosen composition *pays for*: composing the two 1D geometry queries makes each axis's box/fraction correct by construction, and moves the 2D ordering rules — which this file re-states — onto tests.

**Files:**
- Create: `Tests/TextEngineCoreTests/PointGeometryAtEquivalenceTests.swift`
- Create: `Tests/TextEngineCoreTests/PointGeometryAtQueryCountTests.swift`

**Interfaces:**
- Consumes: `pointGeometryAt` and the three types from Task 1; the existing `pointAt`, `lineGeometryAt`, `columnGeometryAt`; the existing providers `UniformLineMetrics`, `UniformColumnMetrics`, and `PrefixSumLineMetrics` / `PrefixSumColumnMetrics` from `TextEngineReferenceProviders`.
- Produces: nothing consumed by later tasks.

> **Note on the reference providers:** `Tests/TextEngineCoreTests` does *not* import `TextEngineReferenceProviders` (the core's tests stay core-only; that is why `UniformColumnMetrics` lives in the core at all). Use the in-file `ArrayColumnMetrics` and a hand-built variable-height vertical source, exactly as `PointAtEquivalenceTests.swift` does. Read that file first and mirror its helpers rather than inventing new ones.

- [ ] **Step 1: Write the parity oracle**

Create `Tests/TextEngineCoreTests/PointGeometryAtEquivalenceTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class PointGeometryAtEquivalenceTests: XCTestCase {
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let advancesPerLine: [[Double]]
        func columnCount(inLine line: Int) -> Int { advancesPerLine[line].count }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            var sum = 0.0
            for i in 0..<column { sum += advancesPerLine[line][i] }
            return sum
        }
    }

    // Variable-height vertical source built from an explicit height vector.
    private struct ArrayLineMetrics: LineMetricsSource {
        let heights: [Double]
        var lineCount: Int { heights.count }
        func offset(ofLine index: Int) -> Double {
            var sum = 0.0
            for i in 0..<index { sum += heights[i] }
            return sum
        }
    }

    // Oracle 1 — vs pointAt. This is NOT a copy of the implementation: it compares
    // against an independently existing function, so a wrong 2D ordering in
    // pointGeometryAt cannot agree with it by accident.
    private func assertIndexAndClampParityWithPointAt<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics v: V, columnMetrics h: H, xs: [Double], ys: [Double],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for y in ys {
            for x in xs {
                let flat = ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: v, columnMetrics: h)
                let rich = ViewportVirtualizer.pointGeometryAt(x: x, y: y, lineMetrics: v, columnMetrics: h)
                switch (flat, rich) {
                case let (.failure(a), .failure(b)):
                    XCTAssertEqual(a, b, "x=\(x) y=\(y)", file: file, line: line)
                case (.empty, .empty):
                    break
                case let (.point(p), .geometry(g)):
                    XCTAssertEqual(p.line.lineIndex, g.line.geometry.lineIndex, "x=\(x) y=\(y)", file: file, line: line)
                    XCTAssertEqual(p.line.clamp, g.line.clamp, "x=\(x) y=\(y)", file: file, line: line)
                    switch (p.column, g.column) {
                    case let (.cell(c), .cell(gc)):
                        XCTAssertEqual(c.columnIndex, gc.geometry.columnIndex, "x=\(x) y=\(y)", file: file, line: line)
                        XCTAssertEqual(c.clamp, gc.clamp, "x=\(x) y=\(y)", file: file, line: line)
                    case (.blankLine, .blankLine):
                        break
                    default:
                        XCTFail("column resolution diverged at x=\(x) y=\(y)", file: file, line: line)
                    }
                default:
                    XCTFail("outcome diverged at x=\(x) y=\(y): \(flat) vs \(rich)", file: file, line: line)
                }
            }
        }
    }

    // Oracles 2 and 3 — each component must EQUAL the 1D geometry query's result.
    private func assertComponentParityWith1D<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
        lineMetrics v: V, columnMetrics h: H, xs: [Double], ys: [Double],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for y in ys {
            for x in xs {
                guard case let .geometry(g) = ViewportVirtualizer.pointGeometryAt(
                    x: x, y: y, lineMetrics: v, columnMetrics: h) else { continue }

                // Oracle 2: the line component is exactly lineGeometryAt(y:).
                XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: y, metrics: v),
                               .geometry(g.line), "x=\(x) y=\(y)", file: file, line: line)

                // Oracle 3: the column component is exactly columnGeometryAt(x:inLine:).
                let located = g.line.geometry.lineIndex
                let want = ViewportVirtualizer.columnGeometryAt(x: x, inLine: located, metrics: h)
                switch g.column {
                case let .cell(cell):
                    XCTAssertEqual(want, .geometry(cell), "x=\(x) y=\(y)", file: file, line: line)
                case .blankLine:
                    XCTAssertEqual(want, .empty, "x=\(x) y=\(y)", file: file, line: line)
                }
            }
        }
    }

    func testParityUniformSources() {
        let v = UniformLineMetrics(lineCount: 20, lineHeight: 16.0)        // totalHeight 320
        let h = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)  // lineWidth 80
        let ys: [Double] = [-1.0, 0.0, 106.7, 160.0, 320.0, 325.0, .nan, .infinity, -.infinity]
        let xs: [Double] = [-1.0, 0.0, 26.7, 40.0, 80.0, 85.0, .nan, .infinity, -.infinity]
        assertIndexAndClampParityWithPointAt(lineMetrics: v, columnMetrics: h, xs: xs, ys: ys)
        assertComponentParityWith1D(lineMetrics: v, columnMetrics: h, xs: xs, ys: ys)
    }

    func testParityVariableSourcesWithBlankLine() {
        // Heights 10/20/5/30 (totalHeight 65); line 2 is blank; advances vary per line.
        let v = ArrayLineMetrics(heights: [10.0, 20.0, 5.0, 30.0])
        let h = ArrayColumnMetrics(advancesPerLine: [[8.0, 4.0, 12.0], [6.0, 6.0], [], [20.0, 3.0]])
        let ys: [Double] = [-1.0, 0.0, 5.0, 15.0, 32.0, 40.0, 65.0, 70.0, .nan, .infinity]
        let xs: [Double] = [-1.0, 0.0, 3.0, 9.0, 20.0, 24.0, 30.0, .nan, .infinity]
        assertIndexAndClampParityWithPointAt(lineMetrics: v, columnMetrics: h, xs: xs, ys: ys)
        assertComponentParityWith1D(lineMetrics: v, columnMetrics: h, xs: xs, ys: ys)
    }
}
```

- [ ] **Step 2: Write the probe-count test**

This is the executable form of Decision 3 — "exactly four probes more than `pointAt`". Create `Tests/TextEngineCoreTests/PointGeometryAtQueryCountTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class PointGeometryAtQueryCountTests: XCTestCase {
    private final class Counter {
        var offsetCalls = 0
        var columnOffsetCalls = 0
    }

    private struct CountingLineMetrics: LineMetricsSource {
        let base: UniformLineMetrics
        let counter: Counter
        var lineCount: Int { base.lineCount }
        func offset(ofLine index: Int) -> Double {
            counter.offsetCalls += 1
            return base.offset(ofLine: index)
        }
    }

    private struct CountingColumnMetrics: LineHorizontalMetricsSource {
        let base: UniformColumnMetrics
        let counter: Counter
        func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.columnOffsetCalls += 1
            return base.columnOffset(inLine: line, column: column)
        }
    }

    // pointGeometryAt must cost exactly pointAt + 2 offset probes + 2 columnOffset
    // probes: the two boxes, and nothing else. A future refactor that re-runs a
    // search, or probes a neighbour it does not need, moves these numbers.
    func testAddsExactlyFourProbesOverPointAt() {
        let flat = Counter()
        let rich = Counter()
        let flatV = CountingLineMetrics(base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: flat)
        let flatH = CountingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 64, columnWidth: 8.0), counter: flat)
        let richV = CountingLineMetrics(base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: rich)
        let richH = CountingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 64, columnWidth: 8.0), counter: rich)

        // An in-range point, so both axes take their full search path.
        _ = ViewportVirtualizer.pointAt(x: 133.0, y: 4_002.0, lineMetrics: flatV, columnMetrics: flatH)
        _ = ViewportVirtualizer.pointGeometryAt(x: 133.0, y: 4_002.0, lineMetrics: richV, columnMetrics: richH)

        XCTAssertEqual(rich.offsetCalls, flat.offsetCalls + 2, "vertical box costs exactly two offset probes")
        XCTAssertEqual(rich.columnOffsetCalls, flat.columnOffsetCalls + 2, "cell box costs exactly two columnOffset probes")
    }

    // A clamped point must not cost more than an in-range one: the clamp fractions
    // are constants (0.0 / 1.0), not computed from extra probes.
    func testClampedPointCostsTheSameFourProbes() {
        let flat = Counter()
        let rich = Counter()
        let flatV = CountingLineMetrics(base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: flat)
        let flatH = CountingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 64, columnWidth: 8.0), counter: flat)
        let richV = CountingLineMetrics(base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: rich)
        let richH = CountingColumnMetrics(base: UniformColumnMetrics(columnsPerLine: 64, columnWidth: 8.0), counter: rich)

        _ = ViewportVirtualizer.pointAt(x: -5.0, y: 99_999.0, lineMetrics: flatV, columnMetrics: flatH)
        _ = ViewportVirtualizer.pointGeometryAt(x: -5.0, y: 99_999.0, lineMetrics: richV, columnMetrics: richH)

        XCTAssertEqual(rich.offsetCalls, flat.offsetCalls + 2)
        XCTAssertEqual(rich.columnOffsetCalls, flat.columnOffsetCalls + 2)
    }
}
```

- [ ] **Step 3: Run both new test classes**

```bash
swift test --filter PointGeometryAt
```

Expected: PASS. If the probe-count test fails, do **not** adjust the expected numbers — that failure means the implementation is probing more than the design allows; fix the implementation.

- [ ] **Step 4: Run the full suite**

```bash
swift test
```

Expected: green.

- [ ] **Step 5: Commit**

```bash
git add Tests/TextEngineCoreTests/PointGeometryAtEquivalenceTests.swift \
        Tests/TextEngineCoreTests/PointGeometryAtQueryCountTests.swift
git commit -m "test: pin pointGeometryAt to its 1D oracles and its four-probe budget"
```

---

### Task 3: Benchmark mode `--point-geometry-query` (nil budgets, `--gate` rejected)

The mode ships **without budgets**. `p95BudgetNanoseconds` is `Int64?` and holds `nil`, so there is nowhere to hand-type a placeholder — the defect Slice 38 exists to repair. `--gate` is rejected at the CLI for the same reason. Both are lifted in Task 6, once hosted evidence exists.

**Files:**
- Create: `Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift:24-25` area (the mode `switch`)
- Test: `Tests/ViewportBenchmarksTests/PointGeometryQueryOptionsTests.swift`

**Interfaces:**
- Consumes: `pointGeometryAt` (Task 1); the existing benchmark helpers `deterministicScrollOffset(sample:maxOffset:)`, `variableHeights(lineCount:)`, `percentile(_:numerator:denominator:)`, `nanoseconds(_:)`, `formatSummary(_:includeGate:)`, `BenchmarkOperationResult(checksum:failureCount:)`, `BenchmarkSummary.init(...)` (its `p95BudgetNanoseconds` / `p99BudgetNanoseconds` parameters are already `Int64?`).
- Produces: `BenchmarkMode.pointGeometryQuery` (`outputName == "point_geometry_query"`), `PointGeometryQueryScenario` (with `name`, `providerName`, `lineCount`, `useVariableHeights`, `p95BudgetNanoseconds: Int64?`, `p99BudgetNanoseconds: Int64?`), `pointGeometryQueryScenarios()`, `runPointGeometryQueryBenchmarks(enforceGate:)`. Tasks 4, 5, and 6 depend on these names.

- [ ] **Step 1: Write the failing options test**

Create `Tests/ViewportBenchmarksTests/PointGeometryQueryOptionsTests.swift`:

```swift
import XCTest
@testable import ViewportBenchmarks

final class PointGeometryQueryOptionsTests: XCTestCase {
    // BenchmarkOptions.parse takes an UNLABELLED [String] and returns
    // BenchmarkOptionParse (.run / .help / .failure) — see BenchmarkOptions.swift:82.
    func testFlagSelectsTheMode() {
        guard case let .run(options) = BenchmarkOptions.parse(["--point-geometry-query"]) else {
            return XCTFail("--point-geometry-query must select a runnable mode")
        }
        XCTAssertEqual(options.mode.outputName, "point_geometry_query")
        XCTAssertFalse(options.enforceGate)
    }

    // Until this mode's budgets are DERIVED from hosted evidence, --gate must be
    // refused: a gate with no budget is either a crash or an invitation to type a
    // placeholder, and the placeholder is the bug Slice 38 spent a whole slice
    // removing. Task 6 of the plan flips this expectation once the corpus carries
    // the mode's rows.
    func testGateIsRejectedUntilBudgetsAreDerived() {
        guard case let .failure(message) = BenchmarkOptions.parse(
            ["--point-geometry-query", "--gate"]) else {
            return XCTFail("--gate must be rejected while the scenarios carry nil budgets")
        }
        XCTAssertTrue(message.contains("point_geometry_query"), "message should name the mode: \(message)")
    }

    func testEveryScenarioStartsWithoutABudget() {
        for scenario in pointGeometryQueryScenarios() {
            XCTAssertNil(scenario.p95BudgetNanoseconds, "\(scenario.name) must not carry a hand-typed budget")
            XCTAssertNil(scenario.p99BudgetNanoseconds, "\(scenario.name) must not carry a hand-typed budget")
        }
    }
}
```

> The tests assert on `mode.outputName` rather than on `BenchmarkMode` itself, because the enum does not conform to `Equatable` — and it should not be made to, just for a test. `outputName` is the right anchor anyway: it is the string the benchmark prints and the corpus keys on.

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --filter PointGeometryQueryOptionsTests
```

Expected: FAIL — compile error, `type 'BenchmarkMode' has no member 'pointGeometryQuery'`.

- [ ] **Step 3: Add the benchmark mode**

Create `Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift`:

```swift
import TextEngineCore
import TextEngineReferenceProviders

struct PointGeometryQueryScenario {
    let name: String
    let providerName: String
    let lineCount: Int
    let useVariableHeights: Bool     // true -> PrefixSumLineMetrics, false -> UniformLineMetrics
    // Optional BY DESIGN. A nil budget means "no hosted evidence yet", and the gate
    // reports `missing_budget` rather than passing. Fill these ONLY from
    // .github/scripts/derive-gate-budgets.sh; never by hand.
    let p95BudgetNanoseconds: Int64?
    let p99BudgetNanoseconds: Int64?
}

private let pointGeometryColumnsPerLine = 256
private let pointGeometryColumnWidth = 8.0
private let pointGeometryLineHeight = 16.0

// Scenarios mirror --point-query one for one, deliberately: the two modes then differ
// only by the four box probes, so their hosted rows are comparable line by line and
// the composite's own overhead is what the difference measures.
//
// Budgets are nil until they are derived from hosted Linux x86_64 samples of this
// PR's own CI runs by .github/scripts/derive-gate-budgets.sh against
// docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv. Hosted is the
// calibration authority; it runs 2-3x slower than local macOS, so it binds.
//
// This mode's corpus base is thin (six runs, matching --point-query, the previous
// thinnest). The 3x-over-worst-sample floor does NOT make a thin base safe: over an
// append-only corpus it freezes a noisy sample in. Re-derive as evidence accumulates —
// do not hand-edit.
func pointGeometryQueryScenarios() -> [PointGeometryQueryScenario] {
    [
        PointGeometryQueryScenario(name: "uniform_100k", providerName: "uniform",
                                   lineCount: 100_000, useVariableHeights: false,
                                   p95BudgetNanoseconds: nil, p99BudgetNanoseconds: nil),
        PointGeometryQueryScenario(name: "uniform_1m", providerName: "uniform",
                                   lineCount: 1_000_000, useVariableHeights: false,
                                   p95BudgetNanoseconds: nil, p99BudgetNanoseconds: nil),
        PointGeometryQueryScenario(name: "prefixsum_100k", providerName: "prefixsum",
                                   lineCount: 100_000, useVariableHeights: true,
                                   p95BudgetNanoseconds: nil, p99BudgetNanoseconds: nil),
        PointGeometryQueryScenario(name: "prefixsum_1m", providerName: "prefixsum",
                                   lineCount: 1_000_000, useVariableHeights: true,
                                   p95BudgetNanoseconds: nil, p99BudgetNanoseconds: nil),
    ]
}

// The checksum must fold the GEOMETRY, not just the indices. --point-query folds
// `lineIndex + clamp + columnIndex + clamp`, which is right for a query that returns
// only indices — but here the entire payload this mode exists to measure (two boxes,
// two fractions) would be absent from the "workload unchanged" anchor the promotion
// slice leans on, and a drifted fraction would leave it byte-identical.
//
// Distinct odd multipliers per field also fix the weakness the Slice 37 review
// recorded (its P3 #5): a purely additive fold makes an axis SWAP invisible.
//
// Reproducible across runs and platforms: Swift does not enable fast-math, and
// + - * / are exactly-rounded under IEEE-754, so the bit patterns are stable.
@inline(__always)
private func fold(_ value: Double, _ multiplier: Int) -> Int {
    Int(truncatingIfNeeded: Int64(bitPattern: value.bitPattern)) &* multiplier
}

@inline(never)
func runPointGeometryQueryOperation<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
    x: Double, y: Double, lineMetrics: V, columnMetrics: H
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.pointGeometryAt(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics) {
    case let .geometry(location):
        var checksum = location.line.geometry.lineIndex &* 19
        switch location.line.clamp {
        case .inRange: checksum &+= 1
        case .clampedToTop: checksum &+= 2
        case .clampedToBottom: checksum &+= 3
        }
        checksum &+= fold(location.line.geometry.y, 3)
        checksum &+= fold(location.line.geometry.height, 5)
        checksum &+= fold(location.line.fractionInLine, 7)

        switch location.column {
        case let .cell(cell):
            checksum &+= cell.geometry.columnIndex &* 23
            switch cell.clamp {
            case .inRange: checksum &+= 10
            case .clampedToLeft: checksum &+= 20
            case .clampedToRight: checksum &+= 30
            }
            checksum &+= fold(cell.geometry.x, 11)
            checksum &+= fold(cell.geometry.width, 13)
            checksum &+= fold(cell.fractionInColumn, 17)
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
func runPointGeometryQueryScenarioCore<V: LineMetricsSource>(
    _ scenario: PointGeometryQueryScenario,
    lineMetrics: V,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let columnMetrics = UniformColumnMetrics(columnsPerLine: pointGeometryColumnsPerLine,
                                             columnWidth: pointGeometryColumnWidth)
    let totalHeight = lineMetrics.offset(ofLine: lineMetrics.lineCount)
    let width = Double(pointGeometryColumnsPerLine) * pointGeometryColumnWidth
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    // The sampler is IDENTICAL to --point-query's, deliberately, including its known
    // correlation (Slice 37 review, P3 #2: five of every eight operations draw x and y
    // from the same deterministicScrollOffset fraction, so the workload walks a 1-D
    // diagonal). The design predicts this mode's latency against --point-query's row by
    // row, and that comparison is only valid if the workload is identical. Decorrelating
    // the axes changes BOTH modes and belongs to a slice that re-derives both budgets.
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
            let result = runPointGeometryQueryOperation(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .pointGeometryQuery,
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
func runPointGeometryQueryScenario(
    _ scenario: PointGeometryQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useVariableHeights {
        let lineMetrics = PrefixSumLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
        return runPointGeometryQueryScenarioCore(scenario, lineMetrics: lineMetrics,
                                                 iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let lineMetrics = UniformLineMetrics(lineCount: scenario.lineCount, lineHeight: pointGeometryLineHeight)
        return runPointGeometryQueryScenarioCore(scenario, lineMetrics: lineMetrics,
                                                 iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runPointGeometryQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in pointGeometryQueryScenarios() {
        let summary = runPointGeometryQueryScenario(
            scenario,
            iterations: iterations,
            operationsPerSample: operationsPerSample
        )
        print(formatSummary(summary, includeGate: enforceGate))

        // Budget-blind is not failure-blind: without --gate this still reddens on a
        // scenario that starts returning .empty/.failure.
        if enforceGate && !summary.passesGate {
            passed = false
        } else if !enforceGate && summary.failureCount != 0 {
            passed = false
        }
    }

    return passed
}
```

- [ ] **Step 4: Wire the flag**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`:

1. Add the case to `BenchmarkMode` after `case pointQuery`:

```swift
    case pointGeometryQuery
```

2. Add its `outputName`, after the `.pointQuery` case:

```swift
        case .pointGeometryQuery:
            return "point_geometry_query"
```

3. Add the flag to the argument `switch`, after the `--point-query` case:

```swift
            case "--point-geometry-query":
                if mode != .pipeline {
                    return .failure("--point-geometry-query cannot be combined with another mode")
                }
                mode = .pointGeometryQuery
```

4. Extend the `--gate` rejection (this is the temporary half — Task 6 removes `.pointGeometryQuery` from it):

```swift
        // .pointGeometryQuery is rejected here ONLY until its budgets are derived from
        // hosted evidence (Slice 39, plan Task 6). Its scenarios carry nil budgets, so
        // a gate could not enforce anything — and a placeholder is exactly the bug
        // Slice 38 removed. Remove it from this list in the same commit that fills the
        // derived budgets in.
        if enforceGate && (mode == .rangeOnly || mode == .memoryShape || mode == .memoryObservation
                            || mode == .pointGeometryQuery) {
            return .failure("--gate cannot be combined with \(mode.outputName) mode")
        }
```

5. Add the usage/help lines: append `[--point-geometry-query]` to the `Usage:` line, and after the `--point-query` help line:

```
      --point-geometry-query  Run (x,y)->(line+box+fraction, cell+box+fraction) 2D geometry query benchmark. Not yet gateable: budgets pending hosted derivation.
```

- [ ] **Step 5: Wire the dispatch**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, in the mode `switch`, after the `.pointQuery` case:

```swift
    case .pointGeometryQuery:
        return runPointGeometryQueryBenchmarks(enforceGate: options.enforceGate)
```

- [ ] **Step 6: Run the tests**

```bash
swift test --filter PointGeometryQueryOptionsTests
swift test
```

Expected: PASS, and the full suite green (`GateFloorTests` still passes — the mode is not yet registered there, and it must not be until it has corpus rows).

- [ ] **Step 7: Run the benchmark locally and eyeball the output**

```bash
swift build -c release
swift run -c release ViewportBenchmarks -- --point-geometry-query
swift run -c release ViewportBenchmarks -- --point-geometry-query --gate ; echo "exit=$?"
```

Expected: four lines of the form `mode=point_geometry_query provider=… scenario=… … p95_ns=… p99_ns=… failures=0 checksum=…` (this is exactly the shape the harvester matches), exit 0; and the `--gate` invocation **rejected** with `--gate cannot be combined with point_geometry_query mode`, exit non-zero.

- [ ] **Step 8: Commit**

```bash
git add Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift \
        Sources/ViewportBenchmarks/BenchmarkOptions.swift \
        Sources/ViewportBenchmarks/BenchmarkProgram.swift \
        Tests/ViewportBenchmarksTests/PointGeometryQueryOptionsTests.swift
git commit -m "feat: add the --point-geometry-query benchmark mode with no budgets yet"
```

---

### Task 4: The observational CI step, the docs, and the PR

Land the CI step **early**: every later commit of this slice then produces a hosted run for free, and six distinct runs is what Task 5 needs.

**Files:**
- Modify: `.github/workflows/swift-ci.yml` (host job, between the `--point-query --gate` step and the `--memory-shape` step)
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: `--point-geometry-query` (Task 3).
- Produces: hosted CI runs whose logs carry `mode=point_geometry_query …` lines — the input to Task 5.

- [ ] **Step 1: Add the CI step**

In `.github/workflows/swift-ci.yml`, in the **Host tests and benchmark gate** job, immediately after the `--point-query --gate` step and before the `--memory-shape` step:

```yaml
      - name: Observe point-geometry query benchmark latency
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query
```

Both the `if:` guard and the `--scratch-path` are mandatory and match every other step in that job: without the guard the step runs on docs-only PRs; without the scratch path it rebuilds from scratch.

This step is **budget-blind, not failure-blind** — a bare run still exits non-zero if any scenario returns `.empty`/`.failure` — so it blocks on correctness while carrying no latency gate. It is not a required-check change and adds no job.

- [ ] **Step 2: Update `AGENTS.md`**

Four edits, none of which restates a measured number (per the standing rule — point at the corpus and the script instead):

1. **Architecture paragraph** — after the `pointAt` sentences, add: `ViewportVirtualizer.pointGeometryAt(x:y:lineMetrics:columnMetrics:)` is its geometry-bearing companion: it composes `lineGeometryAt` with `columnGeometryAt`, returning both axes' boxes, within-box fractions, and clamp flags in a nested `PointGeometryQuery` (`.geometry(PointGeometryLocation)` carrying a `LineGeometryLocation` plus a `ColumnGeometryResolution` — `.cell`/`.blankLine`), adding no search and no arithmetic, only four constant probes, so its cost class equals `pointAt`'s. Caret snapping stays a caller concern. Its `--point-geometry-query` mode is **observational in CI, not yet a gate** (promotion is Slice 40).
2. **`## Commands`** — add, after the `--point-query --gate` line:
   ```bash
   swift run -c release ViewportBenchmarks -- --point-geometry-query   # (x,y)->(line+box+fraction, cell+box+fraction); observational, not yet a gate
   ```
3. **Flag list** — add `--point-geometry-query` to the list of benchmark flags, and add it to the list of modes with which `--gate` is **rejected** (Task 6 moves it to the "valid with" list).
4. **CI section** — the host job gains one observational `--point-geometry-query` step after the point-query gate. The blocking-gate count stays at **ten** in this slice.

- [ ] **Step 3: Verify the workflow parses and the docs are consistent**

```bash
swift test && swift build -c release
rg -n "point-geometry-query" .github/workflows/swift-ci.yml AGENTS.md
```

Expected: tests/build green; `rg` shows the new CI step and the four `AGENTS.md` mentions.

- [ ] **Step 4: Commit and open the PR**

```bash
git add .github/workflows/swift-ci.yml AGENTS.md
git commit -m "ci: observe point-geometry query latency on hosted Linux before gating it"
git push -u origin slice-39-point-geometry-query
gh pr create --title "Slice 39: pointGeometryAt — the geometry-bearing 2D point query" --body "$(cat <<'EOF'
## Summary
- Adds `ViewportVirtualizer.pointGeometryAt(x:y:lineMetrics:columnMetrics:)`: composes `lineGeometryAt` with `columnGeometryAt`, returning both axes' boxes, fractions, and clamp flags. No new search, no new arithmetic; cost = `pointAt` + four constant probes.
- Adds the `--point-geometry-query` benchmark mode. Its scenarios ship with **nil budgets** and `--gate` is refused: budgets are derived from this PR's own hosted runs, never hand-typed (Slice 38's rule).
- Adds one observational CI step so that evidence can exist at all. Promotion to a blocking gate is Slice 40.

## Verification
See `docs/superpowers/verification/2026-07-13-point-geometry-query.md` (filled once the hosted evidence lands).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Confirm the hosted run emitted harvestable lines**

Wait for the host job, then read the **step log**, not the job conclusion:

```bash
gh run list --workflow swift-ci.yml --limit 3
gh run view <run-id> --log | rg "mode=point_geometry_query" | head -5
```

Expected: four `mode=point_geometry_query … p95_ns=… p99_ns=…` lines. If they are absent, the harvest in Task 5 has nothing to find — stop and fix before continuing.

---

### Task 5: Harvest ≥6 distinct hosted runs and derive the budgets

**Files:**
- Modify: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` (append — this **existing** dated file; `GateFloorTests` hardcodes its path, so a new dated corpus would orphan the floor test)

**Interfaces:**
- Consumes: the hosted runs produced by Task 4.
- Produces: corpus rows for `point_geometry_query|{uniform_100k,uniform_1m,prefixsum_100k,prefixsum_1m}`, and the four derived budget pairs that Task 6 pastes in.

- [ ] **Step 1: Confirm six *distinct* runs exist**

The harvest dedup key is the **run id**, so a workflow *re-run* contributes nothing — six runs means six pushes. This slice's own commits supply them; if you are short, push the verification-record skeleton or a doc commit rather than re-running a workflow.

```bash
gh run list --workflow swift-ci.yml --branch slice-39-point-geometry-query --limit 20
```

Expected: at least six completed runs whose host job succeeded.

- [ ] **Step 2: Preview the harvest**

```bash
./.github/scripts/harvest-gate-corpus.sh --limit 40 \
  --corpus docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv --dry-run
```

Expected: the new run ids listed as *harvest*, previously-harvested ones as *skip*. `--corpus` is what makes the append idempotent (PR #83); without it, already-harvested runs are re-added and double-weight themselves in `median()`.

- [ ] **Step 3: Append**

```bash
./.github/scripts/harvest-gate-corpus.sh --limit 40 \
  --corpus docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
  >> docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv

grep -c "point_geometry_query" docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
cut -f1 docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | grep -v run_id | sort -u | wc -l
```

Expected: **≥24** `point_geometry_query` rows (6 runs × 4 scenarios).

- [ ] **Step 4: Derive**

```bash
./.github/scripts/derive-gate-budgets.sh \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv point-geometry-query
```

Expected: one line per scenario, of the shape

```
point_geometry_query|uniform_100k   n=6  p95[med=…  max=… ] p99[med=…  max=… ] budget_p95=…  budget_p99=…  margin_p95=…x margin_p99=…x
```

Record all four lines verbatim — they go into the verification document and their `budget_*` values are the **only** legal source for Task 6's numbers.

- [ ] **Step 5: Read the spread before you trust the budgets**

For each scenario compute `max / median` on both statistics from the line above. The recipe is `budget_p95 = round_up_2sf(max(8 × median, 3 × max))`, so the median term governs only while `max ≤ 2.67 × median`.

- If a scenario shows `max > 2.67 × median`, its budget is **set by one sample**, and the append-only corpus plus `GateFloorTests` will then *enforce* that outlier permanently (Slice 38 review, P2 #2 — still open). Say so explicitly in the verification record, and consider pushing another commit or two for more runs rather than freezing the outlier in silently.
- Also check the Decision 6 prediction now: each scenario's median p95 should sit **above** its `--point-query` counterpart and within roughly 30 % of it. Today's `point_query` medians are in the corpus — read them with:

```bash
./.github/scripts/derive-gate-budgets.sh \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv point-query
```

If a scenario lands far outside that band (say 2×), **stop and investigate the code** — that is a finding (a lost specialization, a re-probe, an allocation), not a budget to widen around.

- [ ] **Step 6: Commit the corpus**

```bash
git add docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
git commit -m "chore: harvest hosted point-geometry-query samples into the gate corpus"
```

---

### Task 6: Wire the derived budgets, the floor test, and the gated CI step

**Files:**
- Modify: `Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift` (the four scenarios)
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (drop the temporary `--gate` rejection; update the help line)
- Modify: `Tests/ViewportBenchmarksTests/PointGeometryQueryOptionsTests.swift` (flip the two expectations)
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (`everyGatedBudget()`)
- Modify: `.github/workflows/swift-ci.yml`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: the four `budget_p95` / `budget_p99` pairs printed by Task 5, Step 4.
- Produces: a gateable `--point-geometry-query --gate` whose budgets are derived, and a `GateFloorTests` that can see it.

- [ ] **Step 1: Paste the derived budgets in**

In `pointGeometryQueryScenarios()`, replace each `nil` with the corresponding `budget_p95` / `budget_p99` from Task 5's derive output. Nothing else. Do not round, adjust, or "sanity-check" the numbers — the script already rounded them.

```swift
        PointGeometryQueryScenario(name: "uniform_100k", providerName: "uniform",
                                   lineCount: 100_000, useVariableHeights: false,
                                   p95BudgetNanoseconds: <budget_p95 from derive>,
                                   p99BudgetNanoseconds: <budget_p99 from derive>),
```

…and likewise for `uniform_1m`, `prefixsum_100k`, `prefixsum_1m`.

- [ ] **Step 2: Let the mode be gated**

In `BenchmarkOptions.swift`, restore the rejection list to its original three modes (delete the `|| mode == .pointGeometryQuery` clause **and** the comment that explained it), and change the help line to the standard wording:

```
      --point-geometry-query  Run (x,y)->(line+box+fraction, cell+box+fraction) 2D geometry query benchmark. Combine with --gate to enforce budgets.
```

- [ ] **Step 3: Add the twelfth loop to `GateFloorTests`**

`everyGatedBudget()` is **eleven hand-written loops** with no exhaustiveness check over `BenchmarkMode` — a gated mode that is not listed there is simply invisible to the floor test. Add, after the `pointQueryScenarios()` loop:

```swift
    for s in pointGeometryQueryScenarios() {
        guard let p95 = s.p95BudgetNanoseconds, let p99 = s.p99BudgetNanoseconds else {
            XCTFail("point_geometry_query|\(s.name) is gated but carries no budget — "
                    + "derive it with .github/scripts/derive-gate-budgets.sh")
            continue
        }
        add(.pointGeometryQuery, s.name, p95, p99)
    }
```

The `guard`/`XCTFail` is not ceremony: it is what keeps a future `nil` from silently escaping the floor test the way a placeholder once escaped every gate.

- [ ] **Step 4: Flip the options test**

In `PointGeometryQueryOptionsTests.swift`, replace `testGateIsRejectedUntilBudgetsAreDerived` and `testEveryScenarioStartsWithoutABudget` with:

```swift
    func testGateIsAcceptedNowThatBudgetsAreDerived() {
        guard case let .run(options) = BenchmarkOptions.parse(
            ["--point-geometry-query", "--gate"]) else {
            return XCTFail("--gate must be accepted once the scenarios carry derived budgets")
        }
        XCTAssertEqual(options.mode.outputName, "point_geometry_query")
        XCTAssertTrue(options.enforceGate)
    }

    // Every budget in this mode comes from .github/scripts/derive-gate-budgets.sh run
    // against the committed corpus. A nil here would mean a gate that cannot fail;
    // a hand-typed number would mean a gate that never could.
    func testEveryScenarioCarriesADerivedBudget() {
        for scenario in pointGeometryQueryScenarios() {
            XCTAssertNotNil(scenario.p95BudgetNanoseconds, "\(scenario.name) has no p95 budget")
            XCTAssertNotNil(scenario.p99BudgetNanoseconds, "\(scenario.name) has no p99 budget")
        }
    }
```

- [ ] **Step 5: Run everything**

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --point-geometry-query --gate ; echo "exit=$?"
```

Expected: full suite green (including `GateFloorTests` with the twelfth loop, which now needs the corpus rows from Task 5); the gate prints `gate=pass` for all four scenarios with `exit=0`, and every scenario's headroom sits inside the band (floor 3x, `headroom_p95 <= 50x`, `headroom_p99 <= 100x`). A `gate=fail reason=budget_stale` here means the budget is too loose for local hardware — **re-derive, do not edit the ceiling**.

Also run the whole existing gate suite once, to prove nothing else moved:

```bash
for m in --gate "--variable-height --gate" "--variable-height-mutation --gate" \
         "--structural-mutation --gate" "--bulk-structural-mutation --gate" \
         "--line-query --gate" "--line-geometry-query --gate" "--column-query --gate" \
         "--column-geometry-query --gate" "--point-query --gate"; do
  echo "== $m"; swift run -c release ViewportBenchmarks -- $m | tail -2
done
```

Expected: `gate=pass` throughout.

- [ ] **Step 6: Make hosted Linux exercise the derived budget**

In `.github/workflows/swift-ci.yml`, replace the observational step from Task 4 with:

```yaml
      - name: Point-geometry query benchmark gate (observational until Slice 40)
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        continue-on-error: true
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate
```

`continue-on-error` keeps it out of the blocking set — Slice 40 promotes it by deleting that one line — while still exercising the budget on the calibration authority *inside this slice*, instead of for the first time when it becomes required.

- [ ] **Step 7: Update `AGENTS.md`**

Move `--point-geometry-query` from the "`--gate` is **rejected** with" list to the "`--gate` is valid with" list, and update the CI section: the host job's point-geometry step now runs `--gate` under `continue-on-error` (still **ten** blocking gates; the eleventh arrives in Slice 40).

- [ ] **Step 8: Commit and push**

```bash
git add Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift \
        Sources/ViewportBenchmarks/BenchmarkOptions.swift \
        Tests/ViewportBenchmarksTests/PointGeometryQueryOptionsTests.swift \
        Tests/ViewportBenchmarksTests/GateFloorTests.swift \
        .github/workflows/swift-ci.yml AGENTS.md
git commit -m "feat: gate --point-geometry-query on budgets derived from hosted evidence"
git push
```

- [ ] **Step 9: Read the hosted step log**

```bash
gh run list --workflow swift-ci.yml --branch slice-39-point-geometry-query --limit 1
gh run view <run-id> --log | rg "mode=point_geometry_query|gate=" | head -10
```

Expected: `gate=pass` on all four scenarios on hosted Linux. Read the **step log**, not the job conclusion — a `continue-on-error` step that died leaves the job green (the Slice 16 lesson).

---

### Task 7: Verification record, cross-target proof, and the post-merge anchor

**Files:**
- Create: `docs/superpowers/verification/2026-07-13-point-geometry-query.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the slice's evidence trail; the post-slice review reads it.

- [ ] **Step 1: Run the cross-target compile**

```bash
./.github/scripts/cross-target-compile.sh
```

Expected: iOS device + simulator green for both `TextEngineCore` and `TextEngineReferenceProviders`; WASM green **or** a recorded non-blocking skip if no matching Swift SDK is installed.

- [ ] **Step 2: Write the verification record**

Create `docs/superpowers/verification/2026-07-13-point-geometry-query.md` with the **actual commands and their real output** — evidence, not assertions. It must contain:

1. `swift test` (full suite, with the new oracles, the probe-count pin, and `GateFloorTests` carrying the twelfth loop).
2. `swift build -c release`.
3. `rg -n "Foundation" Sources/TextEngineCore` → empty.
4. All eleven benchmark modes' gate output, including `--point-geometry-query --gate` with each scenario's headroom.
5. `./.github/scripts/cross-target-compile.sh` output.
6. The harvested hosted run IDs (**≥6 distinct**), the corpus diff summary, and the verbatim `derive-gate-budgets.sh` invocation and output.
7. **The spread table**: `max/median` of p95 and p99 per scenario, and for each, whether its budget came from the median term (`8 × median`) or the `3 × max` floor. Name every floor-governed budget explicitly — it is a budget set by one sample, and this record is the only place that fact is visible before the append-only corpus freezes it.
8. **The absolute check**: each scenario's observed hosted p99 against a fixed **1 µs** product line — the brief's "turn 60 FPS into a measurable headless budget", which the project records nowhere else. Record it as an *observation*, not a gate, and note that the derived **regression** budgets already exceed 1 µs on p99 for `point_query`, so the two thresholds are different objects that a future absolute-budget slice must reconcile rather than assume agree.
9. **The Decision 6 prediction versus the measurement** — the arithmetic, and whether it held. Record it either way; a prediction that only gets reported when it succeeds is not a prediction.
10. The hosted PR-head run ID, and (after merge) the post-merge `push` run ID — anchor proof of merged code in the push run, not only the PR run.

- [ ] **Step 3: Commit and push**

```bash
git add docs/superpowers/verification/2026-07-13-point-geometry-query.md
git commit -m "docs: record slice 39 verification evidence"
git push
```

- [ ] **Step 4: Confirm the PR is green, then hand off**

```bash
gh pr checks
```

Expected: the three required contexts (`Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`) green.

Do **not** self-merge without the user's sign-off. After merge, fill the post-merge `push` run ID into the verification record (a small docs-only follow-up PR is the established pattern), then write the post-slice review at `docs/superpowers/reviews/2026-07-13-slice-39-post-slice-review.md`, ending with a recommendation for Slice 40 — which, per the design, is the zero-Swift promotion of this gate to blocking, and the natural home for Slice 38's still-open P2 #2 (the `3 × max` ratchet).

---

## Task Dependency Order

1 → 2 → 3 → 4 → **(wait for ≥6 hosted runs)** → 5 → 6 → 7.

Tasks 1–3 are pure local work and can be reviewed as they land. Task 4 must land early precisely so that Tasks 5–7's commits *are* the six runs. Task 5 cannot start until six distinct runs exist; Task 6 cannot start until Task 5 prints the budgets.
