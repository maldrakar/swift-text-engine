# Horizontal Geometry Query (`columnGeometryAt(x:inLine:)`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a public, stateless `ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:)` that returns the located cell's box (`columnIndex`, left `x`, advance `width`) plus the within-cell `fractionInColumn` and the same clamp flag as `columnAt` — the horizontal mirror of `lineGeometryAt`.

**Architecture:** `columnGeometryAt` composes over the existing `columnAt` (index + clamp + validation come from it, parity by construction), then reads two `columnOffset(inLine:column:)` probes to build the cell box and computes the fraction with a `switch` on the clamp — exactly as `lineGeometryAt` composes over `lineAt`. No new search, no provider-protocol member, no change to `columnAt`. Ships a `--column-geometry-query` benchmark with a **local** `--gate` (CI promotion is a later slice).

**Tech Stack:** Swift 6.0 (`swift-tools-version: 6.0`), XCTest, SwiftPM. Three products: `TextEngineCore` (pure/headless/Foundation-free), `TextEngineReferenceProviders` (Foundation-free providers), `ViewportBenchmarks` (executable).

## Global Constraints

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must be empty (exit 1). Same for `Sources/TextEngineReferenceProviders`.
- **Swift Embedded compatible / zero-dependency.** Only `Int`/`Double`/generics-over-protocol; no third-party packages.
- **Compiles for iOS and WASM with no source changes.** Public-API change ⇒ cross-target compile is part of verification.
- **Core-owned memory must not grow linearly with document size.** `columnGeometryAt` is O(1) core memory; `--memory-shape` must stay `invariant=pass`.
- **Additive, non-breaking public surface.** New method + new types only. Do **not** add a case to `ColumnQuery` and do **not** change `columnAt`, `LineHorizontalMetricsSource`, or any existing type.
- **TDD, one logical step per commit, conventional-commit prefixes** (`feat:`, `test:`, `docs:`). Branch: `slice-35-horizontal-geometry-query` (already checked out).
- **Existing suite + all 8 gates must stay green with no checksum movement** (nothing shared is touched). Host test count grows from **189**.
- Build/test commands use the repo defaults; the hosted CI build dir is `/tmp/text-engine-host-build`, but locally plain `swift test` / `swift build` are fine.

---

## File Structure

New files:
- `Tests/TextEngineCoreTests/ColumnGeometryAtTests.swift` — unit/edge/failure/clamp/fraction/non-uniform/single-cell/reconstruction tests (core types only).
- `Tests/TextEngineCoreTests/ColumnGeometryAtQueryCountTests.swift` — exact `columnOffset` probe counts + ordered native-dispatch event log.
- `Tests/TextEngineCoreTests/ColumnGeometryAtEquivalenceTests.swift` — structural uniform oracle (products) + index/clamp parity with `columnAt`.
- `Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift` — `--column-geometry-query` mode + scenarios + local gate.

Modified files:
- `Sources/TextEngineCore/ViewportTypes.swift` — add `ColumnGeometry`, `ColumnGeometryQuery`, `ColumnGeometryLocation` (append after `ColumnLocation`). No change to existing types.
- `Sources/TextEngineCore/HorizontalPositionQuery.swift` — add `columnGeometryAt` to the existing `extension ViewportVirtualizer`.
- `Sources/TextEngineCore/LineHorizontalMetricsSource.swift` — one-line doc-comment broadening of the `columnOffset` stability precondition.
- `Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift` — add the PrefixSum `columnGeometryAt` equivalence test (established home for PrefixSum coverage; see Task 4 note).
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift` — new `BenchmarkMode` case + `outputName` + usage + parse arm.
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift` — new `runBenchmarks` arm.
- `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift` — new exhaustive-switch `preconditionFailure` case.
- `AGENTS.md` — architecture sentence + command + flags list + gate-valid sentence.

Docs (Task 7):
- `docs/superpowers/verification/2026-07-07-horizontal-geometry-query.md` — recorded verification.

---

## Task 1: `columnGeometryAt` + result types (core capability)

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (append after line 167, end of `ColumnLocation`)
- Modify: `Sources/TextEngineCore/HorizontalPositionQuery.swift` (add method inside the existing `extension ViewportVirtualizer`, after `columnAt`, before the closing `}` on line 49)
- Modify: `Sources/TextEngineCore/LineHorizontalMetricsSource.swift:20-21` (doc-comment)
- Test: `Tests/TextEngineCoreTests/ColumnGeometryAtTests.swift` (create)

**Interfaces:**
- Consumes: `ViewportVirtualizer.columnAt(x:inLine:metrics:) -> ColumnQuery` (existing), `LineHorizontalMetricsSource.columnOffset(inLine:column:)` (existing), `ColumnLocation.Clamp` (existing).
- Produces (later tasks rely on these exact names/types):
  - `struct ColumnGeometry: Equatable { let columnIndex: Int; let x: Double; let width: Double; init(columnIndex:x:width:) }`
  - `enum ColumnGeometryQuery: Equatable { case geometry(ColumnGeometryLocation); case empty; case failure(ViewportValidationError) }`
  - `struct ColumnGeometryLocation: Equatable { let geometry: ColumnGeometry; let fractionInColumn: Double; let clamp: ColumnLocation.Clamp; init(geometry:fractionInColumn:clamp:) }`
  - `static func columnGeometryAt<Metrics: LineHorizontalMetricsSource>(x: Double, inLine line: Int, metrics: Metrics) -> ColumnGeometryQuery`

- [ ] **Step 1: Write the failing unit test file**

Create `Tests/TextEngineCoreTests/ColumnGeometryAtTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ColumnGeometryAtTests: XCTestCase {
    private func box(_ index: Int, _ x: Double, _ width: Double) -> ColumnGeometry {
        ColumnGeometry(columnIndex: index, x: x, width: width)
    }

    // A line-addressable hand-built source (mirror of ColumnAtTests.ArrayColumnMetrics).
    // offsetsPerLine[line][0] must be 0 for a valid line; an empty inner array yields
    // columnCount == -1 (drives .negativeColumnCount).
    private struct ArrayColumnMetrics: LineHorizontalMetricsSource {
        let offsetsPerLine: [[Double]]
        func columnCount(inLine line: Int) -> Int { offsetsPerLine[line].count - 1 }
        func columnOffset(inLine line: Int, column: Int) -> Double { offsetsPerLine[line][column] }
    }

    // MARK: failure + empty outcomes (inherited from columnAt)

    func testNegativeColumnCountFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[]]) // columnCount -1
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 3.0, inLine: 0, metrics: metrics),
                       .failure(.negativeColumnCount))
    }

    func testNonFiniteXFails() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 8.0)
        for x in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: x, inLine: 0, metrics: metrics),
                           .failure(.nonFiniteValue))
        }
    }

    func testInvalidFirstOffsetFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[5.0, 15.0]]) // columnOffset(_,0) == 5
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 3.0, inLine: 0, metrics: metrics),
                       .failure(.invalidColumnMetrics))
    }

    // Pins the "probe before empty short-circuit" ladder: a blank line whose
    // columnOffset(_,0) != 0 must fail, not short-circuit to .empty.
    func testInvalidFirstOffsetOnBlankLineFailsBeforeEmpty() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[5.0]]) // columnCount 0, offset(_,0) == 5
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 0.0, inLine: 0, metrics: metrics),
                       .failure(.invalidColumnMetrics))
    }

    func testZeroWidthFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, 0.0]]) // width 0
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 0.0, inLine: 0, metrics: metrics),
                       .failure(.invalidColumnMetrics))
    }

    func testNonFiniteWidthFails() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, .infinity]])
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 1.0, inLine: 0, metrics: metrics),
                       .failure(.invalidColumnMetrics))
    }

    func testBlankLineIsEmptyForAnyX() {
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0]]) // columnCount 0
        for x in [-5.0, 0.0, 12.0] {
            XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: x, inLine: 0, metrics: metrics), .empty)
        }
    }

    // MARK: in-range geometry + fraction

    func testExactCellLeftEdgeHasZeroFraction() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 16.0 * 5.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(5, 80.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .inRange)))
    }

    func testMidCellHasHalfFraction() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 16.0 * 3.0 + 8.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(3, 48.0, 16.0),
                                                        fractionInColumn: 0.5, clamp: .inRange)))
    }

    func testXZeroIsInRangeAtCellZero() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 0.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .inRange)))
    }

    // MARK: clamp fractions

    func testClampToLeftHasZeroFractionOnCellZero() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: -0.001, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .clampedToLeft)))
    }

    func testClampToRightHasUnitFractionOnLastCell() {
        let metrics = UniformColumnMetrics(columnsPerLine: 10, columnWidth: 16.0)
        let width = 10.0 * 16.0
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: width, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(9, 144.0, 16.0),
                                                        fractionInColumn: 1.0, clamp: .clampedToRight)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: width + 100.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(9, 144.0, 16.0),
                                                        fractionInColumn: 1.0, clamp: .clampedToRight)))
    }

    // MARK: non-uniform metrics (guards against a uniform-only shortcut)

    func testNonUniformGeometryAndFraction() {
        // advances [10,30,5,50] -> offsets [0,10,40,45,95], width 95, columnCount 4
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, 10.0, 40.0, 45.0, 95.0]])
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 10.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(1, 10.0, 30.0),
                                                        fractionInColumn: 0.0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 25.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(1, 10.0, 30.0),
                                                        fractionInColumn: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 42.5, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(2, 40.0, 5.0),
                                                        fractionInColumn: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: -1.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 10.0),
                                                        fractionInColumn: 0.0, clamp: .clampedToLeft)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 95.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(3, 45.0, 50.0),
                                                        fractionInColumn: 1.0, clamp: .clampedToRight)))
    }

    func testSingleCellLine() {
        let metrics = UniformColumnMetrics(columnsPerLine: 1, columnWidth: 16.0)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: -1.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .clampedToLeft)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 0.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 8.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 16.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 16.0),
                                                        fractionInColumn: 1.0, clamp: .clampedToRight)))
    }

    // MARK: reconstruction invariant (opposite direction from the equivalence oracle)

    func testReconstructionInvariant() {
        // offsets [0,10,40,45,95]; assert box.x + frac*box.width round-trips to x
        // for interior, non-half in-range points.
        let metrics = ArrayColumnMetrics(offsetsPerLine: [[0.0, 10.0, 40.0, 45.0, 95.0]])
        for x in [3.0, 7.5, 22.0, 41.3, 60.0, 94.9] {
            guard case let .geometry(loc) = ViewportVirtualizer.columnGeometryAt(x: x, inLine: 0, metrics: metrics) else {
                return XCTFail("expected .geometry for x=\(x)")
            }
            XCTAssertEqual(loc.clamp, .inRange, "x=\(x)")
            XCTAssertLessThanOrEqual(abs(loc.geometry.x + loc.fractionInColumn * loc.geometry.width - x), 1e-9, "x=\(x)")
        }
    }

    // MARK: per-line addressing

    func testPerLineAddressing() {
        // line 0 offsets [0,10,40,45,95]; line 1 offsets [0,8,16]
        let metrics = ArrayColumnMetrics(offsetsPerLine: [
            [0.0, 10.0, 40.0, 45.0, 95.0],
            [0.0, 8.0, 16.0],
        ])
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 9.0, inLine: 0, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(0, 0.0, 10.0),
                                                        fractionInColumn: 0.9, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 9.0, inLine: 1, metrics: metrics),
                       .geometry(ColumnGeometryLocation(geometry: box(1, 8.0, 8.0),
                                                        fractionInColumn: (9.0 - 8.0) / 8.0, clamp: .inRange)))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ColumnGeometryAtTests`
Expected: FAIL — compile error, `cannot find 'columnGeometryAt' in scope` / `cannot find type 'ColumnGeometry' in scope`.

- [ ] **Step 3: Add the result types**

In `Sources/TextEngineCore/ViewportTypes.swift`, append after the closing `}` of `ColumnLocation` (currently the last line, 167):

```swift

public struct ColumnGeometry: Equatable {
    public let columnIndex: Int
    public let x: Double        // cell left edge (columnOffset of columnIndex)
    public let width: Double    // advance width (columnOffset(i+1) - columnOffset(i))

    public init(columnIndex: Int, x: Double, width: Double) {
        self.columnIndex = columnIndex
        self.x = x
        self.width = width
    }
}

public enum ColumnGeometryQuery: Equatable {
    case geometry(ColumnGeometryLocation) // a real cell was located, with its box
    case empty                            // blank line: columnCount(inLine:) == 0
    case failure(ViewportValidationError) // invalid input / metrics
}

public struct ColumnGeometryLocation: Equatable {
    /// The located cell's box: columnIndex, left x, advance width.
    public let geometry: ColumnGeometry
    /// Where `x` falls within the cell: `0.0` at the cell left edge and when clamped
    /// to left; `(x - geometry.x) / geometry.width` in `[0, 1)` for an in-range
    /// query; `1.0` when clamped to right.
    public let fractionInColumn: Double
    /// Whether the query landed inside the line or past an edge (from `columnAt`).
    public let clamp: ColumnLocation.Clamp

    public init(geometry: ColumnGeometry, fractionInColumn: Double, clamp: ColumnLocation.Clamp) {
        self.geometry = geometry
        self.fractionInColumn = fractionInColumn
        self.clamp = clamp
    }
}
```

- [ ] **Step 4: Add the `columnGeometryAt` method**

In `Sources/TextEngineCore/HorizontalPositionQuery.swift`, insert the following inside the `extension ViewportVirtualizer` block, immediately after `columnAt`'s closing `}` (currently line 48) and before the extension's closing `}` (line 49):

```swift

    /// The geometry-bearing companion to `columnAt(x:inLine:metrics:)`: returns the
    /// located cell's box (`ColumnGeometry`) plus the within-cell `fractionInColumn`
    /// and the same clamp flag.
    ///
    /// Composes over `columnAt` — index, clamp, and the validation ladder come
    /// straight from it (parity by construction) — then reads
    /// `columnOffset(inLine:column: i)` and `columnOffset(inLine:column: i + 1)` to
    /// build the box. Adds only a constant number of `columnOffset(inLine:column:)`
    /// probes over `columnAt`, so it never adds a log factor and its per-provider cost
    /// class equals `columnAt`'s. O(1) core memory. `.empty` / `.failure` pass straight
    /// through from `columnAt`. `inLine` is a documented precondition, not validated.
    public static func columnGeometryAt<Metrics: LineHorizontalMetricsSource>(
        x: Double,
        inLine line: Int,
        metrics: Metrics
    ) -> ColumnGeometryQuery {
        switch columnAt(x: x, inLine: line, metrics: metrics) {
        case let .failure(error):
            return .failure(error)
        case .empty:
            return .empty
        case let .column(location):
            let left = metrics.columnOffset(inLine: line, column: location.columnIndex)
            let right = metrics.columnOffset(inLine: line, column: location.columnIndex + 1)
            let box = ColumnGeometry(columnIndex: location.columnIndex, x: left, width: right - left)
            let fraction: Double
            switch location.clamp {
            case .clampedToLeft:
                fraction = 0.0
            case .clampedToRight:
                fraction = 1.0
            case .inRange:
                fraction = (x - left) / box.width
            }
            return .geometry(ColumnGeometryLocation(geometry: box, fractionInColumn: fraction, clamp: location.clamp))
        }
    }
```

- [ ] **Step 5: Broaden the `columnOffset` stability precondition doc-comment**

In `Sources/TextEngineCore/LineHorizontalMetricsSource.swift`, edit the stability precondition (lines 20-21).

Old:
```swift
    /// Stability precondition: `columnCount(inLine:)` and `columnOffset(inLine:column:)`
    /// for a given line must be stable for one `columnAt` query.
```
New:
```swift
    /// Stability precondition: `columnCount(inLine:)` and `columnOffset(inLine:column:)`
    /// for a given line must be stable for one `columnAt` / `columnGeometryAt` query.
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `swift test --filter ColumnGeometryAtTests`
Expected: PASS (all `ColumnGeometryAtTests` green).

- [ ] **Step 7: Commit**

```bash
git add Sources/TextEngineCore/ViewportTypes.swift \
        Sources/TextEngineCore/HorizontalPositionQuery.swift \
        Sources/TextEngineCore/LineHorizontalMetricsSource.swift \
        Tests/TextEngineCoreTests/ColumnGeometryAtTests.swift
git commit -m "feat: add columnGeometryAt geometry-bearing horizontal query

Composes over columnAt (parity by construction) + two columnOffset probes
for the cell box; fractionInColumn with clamp-edge sentinels 0.0/1.0. New
additive types ColumnGeometry / ColumnGeometryQuery / ColumnGeometryLocation.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Query-count + native-dispatch order tests

Regression pins for the O(log M) query / O(1) memory envelope and the exact composed dispatch order. These pass against Task 1's implementation (no new production code) — they lock the probe contract so an accidental re-search or linear scan later fails.

**Files:**
- Test: `Tests/TextEngineCoreTests/ColumnGeometryAtQueryCountTests.swift` (create)

**Interfaces:**
- Consumes: `ViewportVirtualizer.columnGeometryAt(...)`, `UniformColumnMetrics`, `ColumnGeometry`, `ColumnGeometryLocation`, `ColumnLocation.Clamp` (all from Task 1 / existing core).

- [ ] **Step 1: Write the test file**

Create `Tests/TextEngineCoreTests/ColumnGeometryAtQueryCountTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ColumnGeometryAtQueryCountTests: XCTestCase {
    private final class QueryCounter {
        var count = 0
    }

    // Counts every columnOffset probe (columnCount is free), mirror of the
    // ColumnAtQueryCountTests harness.
    private struct CountingColumnMetrics: LineHorizontalMetricsSource {
        let base: UniformColumnMetrics
        let counter: QueryCounter

        init(columnsPerLine: Int, columnWidth: Double, counter: QueryCounter) {
            self.base = UniformColumnMetrics(columnsPerLine: columnsPerLine, columnWidth: columnWidth)
            self.counter = counter
        }

        func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.count += 1
            return base.columnOffset(inLine: line, column: column)
        }
    }

    private enum NativeSearchEvent: Equatable {
        case offset(Int, Int)    // (line, column)
        case native(Int, Double) // (line, x)
    }

    private final class NativeSearchCounter {
        var events: [NativeSearchEvent] = []
    }

    // Overrides columnIndex so the in-range path shows a .native event; the override
    // reads `offsets` directly (does NOT call columnOffset), so the event log is clean.
    private struct NativeSearchColumnMetrics: LineHorizontalMetricsSource {
        let offsets: [Double]
        let counter: NativeSearchCounter

        func columnCount(inLine line: Int) -> Int { offsets.count - 1 }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.events.append(.offset(line, column))
            return offsets[column]
        }
        func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
            counter.events.append(.native(line, x))
            var result = 0
            for index in 0..<(offsets.count - 1) {
                if offsets[index] <= x { result = index } else { break }
            }
            return result
        }
    }

    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value { capacity <<= 1; power += 1 }
        return power
    }

    func testInRangeUsesLogarithmicQueriesPlusTwoGeometryProbes() {
        let count = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingColumnMetrics(columnsPerLine: count, columnWidth: 8.0, counter: counter)

        let result = ViewportVirtualizer.columnGeometryAt(x: Double(count / 2) * 8.0 + 4.0, inLine: 0, metrics: metrics)

        guard case .geometry = result else { return XCTFail("expected .geometry, got \(result)") }
        // columnAt's 2 contract probes + binary search (<= ceilLog2(count)+1) + 2 geometry probes.
        let expectedMax = 2 + (ceilLog2(count) + 1) + 2
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }

    func testBlankLineQueriesOnlyFirstOffset() {
        struct BlankColumnMetrics: LineHorizontalMetricsSource {
            let counter: QueryCounter
            func columnCount(inLine line: Int) -> Int { 0 }
            func columnOffset(inLine line: Int, column: Int) -> Double { counter.count += 1; return 0.0 }
        }
        let counter = QueryCounter()
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: 3.0, inLine: 0, metrics: BlankColumnMetrics(counter: counter)), .empty)
        XCTAssertEqual(counter.count, 1)
    }

    func testClampBranchesUseFourProbes() {
        let count = 1_000_000

        let leftCounter = QueryCounter()
        let leftMetrics = CountingColumnMetrics(columnsPerLine: count, columnWidth: 8.0, counter: leftCounter)
        _ = ViewportVirtualizer.columnGeometryAt(x: -1.0, inLine: 0, metrics: leftMetrics)
        XCTAssertEqual(leftCounter.count, 4) // columnAt offset(0)+width, then box offset(0)+offset(1)

        let rightCounter = QueryCounter()
        let rightMetrics = CountingColumnMetrics(columnsPerLine: count, columnWidth: 8.0, counter: rightCounter)
        _ = ViewportVirtualizer.columnGeometryAt(x: Double(count) * 8.0 + 1.0, inLine: 0, metrics: rightMetrics)
        XCTAssertEqual(rightCounter.count, 4) // columnAt offset(0)+width, then box offset(count-1)+offset(count)
    }

    func testNonFiniteXDoesNotQueryOffsets() {
        let counter = QueryCounter()
        let metrics = CountingColumnMetrics(columnsPerLine: 1_000, columnWidth: 8.0, counter: counter)
        XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: .nan, inLine: 0, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(counter.count, 0)
    }

    func testDispatchesToNativeHookThenTakesTwoGeometryProbesInOrder() {
        let counter = NativeSearchCounter()
        // offsets [0,10,30,35,80] on line 0; count == 4, width == 80; x = 31 -> cell 2.
        let metrics = NativeSearchColumnMetrics(offsets: [0.0, 10.0, 30.0, 35.0, 80.0], counter: counter)

        let result = ViewportVirtualizer.columnGeometryAt(x: 31.0, inLine: 0, metrics: metrics)

        XCTAssertEqual(result, .geometry(ColumnGeometryLocation(
            geometry: ColumnGeometry(columnIndex: 2, x: 30.0, width: 5.0),
            fractionInColumn: (31.0 - 30.0) / 5.0,
            clamp: .inRange
        )))
        // columnAt: offset(0,0), offset(0,4), native(0,31); then box: offset(0,2), offset(0,3).
        XCTAssertEqual(counter.events, [.offset(0, 0), .offset(0, 4), .native(0, 31.0), .offset(0, 2), .offset(0, 3)])
    }
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `swift test --filter ColumnGeometryAtQueryCountTests`
Expected: PASS (all green — Task 1's composition already produces exactly these probe counts and this event order).

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/ColumnGeometryAtQueryCountTests.swift
git commit -m "test: pin columnGeometryAt query-count + native dispatch order

O(log M) query / O(1) memory envelope: non-finite 0, blank 1, clamp 4,
in-range <= 2+(ceilLog2(M)+1)+2; ordered event log proves it reuses
columnAt's index dispatch then takes exactly two geometry probes.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Structural uniform oracle + `columnAt` parity (core)

Mirror of `LineGeometryAtEquivalenceTests.swift`: product-built `x` over exactly-representable widths so box/fraction are known by construction (dodges `floor(x/width)` boundary fragility), plus index/clamp parity with `columnAt`.

**Files:**
- Test: `Tests/TextEngineCoreTests/ColumnGeometryAtEquivalenceTests.swift` (create)

**Interfaces:**
- Consumes: `ViewportVirtualizer.columnGeometryAt(...)`, `ViewportVirtualizer.columnAt(...)`, `UniformColumnMetrics`, `ColumnGeometry`, `ColumnGeometryLocation`, `ColumnGeometryQuery`, `ColumnLocation.Clamp`.

- [ ] **Step 1: Write the test file**

Create `Tests/TextEngineCoreTests/ColumnGeometryAtEquivalenceTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class ColumnGeometryAtEquivalenceTests: XCTestCase {
    private func assertGeometry(
        _ metrics: UniformColumnMetrics,
        inLine line: Int,
        x: Double,
        index: Int,
        fraction: Double,
        clamp: ColumnLocation.Clamp,
        file: StaticString = #filePath,
        line testLine: UInt = #line
    ) {
        let w = metrics.columnWidth
        let expected = ColumnGeometryQuery.geometry(
            ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: index, x: Double(index) * w, width: w),
                fractionInColumn: fraction,
                clamp: clamp
            )
        )
        XCTAssertEqual(
            ViewportVirtualizer.columnGeometryAt(x: x, inLine: line, metrics: metrics),
            expected,
            "columnsPerLine=\(metrics.columnsPerLine), columnWidth=\(w), line=\(line), x=\(x)",
            file: file, line: testLine
        )
    }

    func testStructuralEquivalenceOverRepresentableUniformMetrics() {
        // Exactly-representable widths; counts well under 2^53 so Double(k)*w is exact
        // and the fractions (0.0, 0.5, 1.0) are exact.
        let widths: [Double] = [1.0, 10.0, 16.0, 12.5, 256.0]
        let counts = [1, 2, 3, 100, 100_000]
        let lines = [0, 3, 9]

        for width in widths {
            for count in counts {
                let metrics = UniformColumnMetrics(columnsPerLine: count, columnWidth: width)
                let totalWidth = Double(count) * width
                for line in lines {
                    // Left of the line -> clamp left, fraction 0.0, cell 0 box.
                    assertGeometry(metrics, inLine: line, x: -width, index: 0, fraction: 0.0, clamp: .clampedToLeft)

                    let ks = Set([0, 1, count / 2, count - 1].filter { $0 >= 0 && $0 < count })
                    for k in ks {
                        // Exact cell left edge -> fraction 0.0, in range.
                        assertGeometry(metrics, inLine: line, x: Double(k) * width, index: k, fraction: 0.0, clamp: .inRange)
                        // Mid-cell -> fraction 0.5, in range.
                        assertGeometry(metrics, inLine: line, x: Double(k) * width + width / 2.0,
                                       index: k, fraction: 0.5, clamp: .inRange)
                    }

                    // At and past the line width -> clamp right, fraction 1.0, last-cell box.
                    assertGeometry(metrics, inLine: line, x: totalWidth, index: count - 1, fraction: 1.0, clamp: .clampedToRight)
                    assertGeometry(metrics, inLine: line, x: totalWidth + width, index: count - 1, fraction: 1.0, clamp: .clampedToRight)
                }
            }
        }
    }

    func testIndexAndClampParityWithColumnAt() {
        let metrics = UniformColumnMetrics(columnsPerLine: 1_000, columnWidth: 16.0)
        let width = 1_000.0 * 16.0
        var xs: [Double] = [-10.0, 0.0, width, width + 25.0]
        for k in [0, 1, 500, 999] {
            xs.append(Double(k) * 16.0)
            xs.append(Double(k) * 16.0 + 7.0)
        }
        for x in xs {
            let geometryResult = ViewportVirtualizer.columnGeometryAt(x: x, inLine: 0, metrics: metrics)
            let columnResult = ViewportVirtualizer.columnAt(x: x, inLine: 0, metrics: metrics)
            guard case let .geometry(loc) = geometryResult, case let .column(col) = columnResult else {
                return XCTFail("expected .geometry and .column for x=\(x), got \(geometryResult) / \(columnResult)")
            }
            XCTAssertEqual(loc.geometry.columnIndex, col.columnIndex, "index parity x=\(x)")
            XCTAssertEqual(loc.clamp, col.clamp, "clamp parity x=\(x)")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `swift test --filter ColumnGeometryAtEquivalenceTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/ColumnGeometryAtEquivalenceTests.swift
git commit -m "test: add columnGeometryAt structural uniform oracle + columnAt parity

Product-built x over exactly-representable widths (box/fraction known by
construction) plus index/clamp parity with columnAt across an x sweep.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: PrefixSum reference equivalence

The provider-level proof that the composed geometry is byte-consistent with the shipped `PrefixSumColumnMetrics.columnOffset`. **Placement note:** the spec suggested a new file `Tests/TextEngineReferenceProvidersTests/ColumnGeometryAtEquivalenceTests.swift`, but the established repo pattern puts PrefixSum coverage in `PrefixSumColumnMetricsTests.swift` (which already holds `testColumnAtOverPrefixSumMatchesHandBuiltOffsets`). We extend that file to stay DRY and consistent — same target, same provider, one home for PrefixSum coverage.

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift` (add one test method)

**Interfaces:**
- Consumes: `PrefixSumColumnMetrics` (ref provider), `ViewportVirtualizer.columnGeometryAt(...)`, `ViewportVirtualizer.columnAt(...)`, `ColumnGeometry`, `ColumnGeometryLocation`, `ColumnLocation.Clamp` (core).

- [ ] **Step 1: Add the equivalence test method**

In `Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift`, add this method inside the `PrefixSumColumnMetricsTests` class (e.g. after `testColumnAtOverPrefixSumMatchesHandBuiltOffsets`):

```swift
    func testColumnGeometryAtOverPrefixSumMatchesProviderOffsets() {
        // advances [10,30,5,50] -> offsets [0,10,40,45,95], width 95.
        let metrics = PrefixSumColumnMetrics(advancesPerLine: [[10.0, 30.0, 5.0, 50.0]])

        // Self-consistency: geometry read back from the provider's own columnOffset,
        // and fraction recomputed under the Decision 3 contract, must equal the result.
        let xs: [Double] = [-2.0, 0.0, 5.0, 10.0, 22.0, 40.0, 44.0, 45.0, 94.0, 95.0, 200.0]
        for x in xs {
            guard case let .column(col) = ViewportVirtualizer.columnAt(x: x, inLine: 0, metrics: metrics) else {
                return XCTFail("expected .column for x=\(x)")
            }
            let left = metrics.columnOffset(inLine: 0, column: col.columnIndex)
            let right = metrics.columnOffset(inLine: 0, column: col.columnIndex + 1)
            let expectedFraction: Double
            switch col.clamp {
            case .clampedToLeft: expectedFraction = 0.0
            case .clampedToRight: expectedFraction = 1.0
            case .inRange: expectedFraction = (x - left) / (right - left)
            }
            let expected = ColumnGeometryQuery.geometry(ColumnGeometryLocation(
                geometry: ColumnGeometry(columnIndex: col.columnIndex, x: left, width: right - left),
                fractionInColumn: expectedFraction,
                clamp: col.clamp
            ))
            XCTAssertEqual(ViewportVirtualizer.columnGeometryAt(x: x, inLine: 0, metrics: metrics), expected, "x=\(x)")
        }
    }
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `swift test --filter PrefixSumColumnMetricsTests`
Expected: PASS (existing methods + the new one).

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift
git commit -m "test: add columnGeometryAt PrefixSum reference equivalence

Composed geometry/fraction read back byte-consistent with the shipped
PrefixSumColumnMetrics columnOffset across an x sweep.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `--column-geometry-query` benchmark mode + local gate

Adds the benchmark file and wires the new mode through the four plumbing sites. The `--gate` denylist (`BenchmarkOptions.swift:146` — rejected only for `.rangeOnly`/`.memoryShape`/`.memoryObservation`) needs **no** change, so `--column-geometry-query --gate` is gateable automatically.

**Files:**
- Create: `Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (enum case, `outputName`, usage string, usage flag line, parse arm)
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift` (`runBenchmarks` arm)
- Modify: `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift` (exhaustive-switch case)

**Interfaces:**
- Consumes: `ViewportVirtualizer.columnGeometryAt(...)`, `UniformColumnMetrics`, `PrefixSumColumnMetrics`, `BenchmarkSummary`, `BenchmarkOperationResult`, `deterministicScrollOffset`, `variableAdvances`, `percentile`, `nanoseconds`, `formatSummary` (existing benchmark support).
- Produces: `func runColumnGeometryQueryBenchmarks(enforceGate: Bool) -> Bool`; `BenchmarkMode.columnGeometryQuery` (`outputName == "column_geometry_query"`).

- [ ] **Step 1: Create the benchmark file**

Create `Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift`:

```swift
import TextEngineCore
import TextEngineReferenceProviders

struct ColumnGeometryQueryScenario {
    let name: String
    let providerName: String
    let columnCount: Int
    let useVariableAdvance: Bool
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// columnGeometryAt is columnAt plus a constant two O(1) columnOffset probes, so it
// stays within the --column-query headroom. Both provider families answer
// columnOffset in O(1); there is no balanced-tree/Fenwick horizontal analog. Budgets
// start from the --column-query numbers; the verification step confirms gate=pass and
// bumps with the project's customary headroom if the constant probes need it.
func columnGeometryQueryScenarios() -> [ColumnGeometryQueryScenario] {
    [
        ColumnGeometryQueryScenario(name: "uniform_1k", providerName: "uniform",
                                    columnCount: 1_000, useVariableAdvance: false,
                                    p95BudgetNanoseconds: 30_000, p99BudgetNanoseconds: 60_000),
        ColumnGeometryQueryScenario(name: "uniform_100k", providerName: "uniform",
                                    columnCount: 100_000, useVariableAdvance: false,
                                    p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000),
        ColumnGeometryQueryScenario(name: "uniform_1m", providerName: "uniform",
                                    columnCount: 1_000_000, useVariableAdvance: false,
                                    p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        ColumnGeometryQueryScenario(name: "prefixsum_100k", providerName: "prefixsum",
                                    columnCount: 100_000, useVariableAdvance: true,
                                    p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000),
        ColumnGeometryQueryScenario(name: "prefixsum_1m", providerName: "prefixsum",
                                    columnCount: 1_000_000, useVariableAdvance: true,
                                    p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
    ]
}

@inline(never)
func runColumnGeometryQueryOperation<Metrics: LineHorizontalMetricsSource>(
    x: Double,
    inLine line: Int,
    metrics: Metrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.columnGeometryAt(x: x, inLine: line, metrics: metrics) {
    case let .geometry(location):
        var checksum = location.geometry.columnIndex
        switch location.clamp {
        case .inRange: checksum &+= 1
        case .clampedToLeft: checksum &+= 2
        case .clampedToRight: checksum &+= 3
        }
        checksum &+= Int(location.fractionInColumn * 1_000_000.0)
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runColumnGeometryQueryScenarioCore<Metrics: LineHorizontalMetricsSource>(
    _ scenario: ColumnGeometryQueryScenario,
    metrics: Metrics,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let width = metrics.columnOffset(inLine: 0, column: scenario.columnCount)
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let x: Double
            switch sample % 8 {
            case 0:
                x = -1.0 - Double(sample % 1_000)      // left of the line
            case 1:
                x = width + Double(sample % 1_000)     // right of the line end
            default:
                x = deterministicScrollOffset(sample: sample, maxOffset: width)
            }
            let result = runColumnGeometryQueryOperation(x: x, inLine: 0, metrics: metrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .columnGeometryQuery,
        providerName: scenario.providerName,
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: nil,
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
func runColumnGeometryQueryScenario(
    _ scenario: ColumnGeometryQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useVariableAdvance {
        let metrics = PrefixSumColumnMetrics(advancesPerLine: [variableAdvances(cellCount: scenario.columnCount)])
        return runColumnGeometryQueryScenarioCore(scenario, metrics: metrics,
                                                  iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let metrics = UniformColumnMetrics(columnsPerLine: scenario.columnCount, columnWidth: 8.0)
        return runColumnGeometryQueryScenarioCore(scenario, metrics: metrics,
                                                  iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runColumnGeometryQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in columnGeometryQueryScenarios() {
        let summary = runColumnGeometryQueryScenario(
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

- [ ] **Step 2: Add the `BenchmarkMode` case + `outputName`**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, add the enum case after `case columnQuery` (line 11):
```swift
    case columnQuery
    case columnGeometryQuery
```
And add the `outputName` case after the `.columnQuery` arm (line 35-36):
```swift
        case .columnQuery:
            return "column_query"
        case .columnGeometryQuery:
            return "column_geometry_query"
```

- [ ] **Step 3: Add the usage entries + parse arm**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`:

Add `[--column-geometry-query]` to the `Usage:` line (line 56), immediately after `[--column-query]`:
```
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--variable-height] [--variable-height-mutation] [--structural-mutation] [--bulk-structural-mutation] [--line-query] [--line-geometry-query] [--column-query] [--column-geometry-query] [--memory-shape] [--memory-observation] [--help]
```

Add the flag description after the `--column-query` line (line 68):
```
      --column-query        Run x->cell within-line position-query benchmark. Combine with --gate to enforce budgets.
      --column-geometry-query  Run x->cell+box+fraction within-line geometry query benchmark. Combine with --gate to enforce budgets.
```

Add the parse arm after the `--column-query` case (lines 126-130):
```swift
            case "--column-query":
                if mode != .pipeline {
                    return .failure("--column-query cannot be combined with another mode")
                }
                mode = .columnQuery
            case "--column-geometry-query":
                if mode != .pipeline {
                    return .failure("--column-geometry-query cannot be combined with another mode")
                }
                mode = .columnGeometryQuery
```

(No change to the `--gate` denylist on line 146 — `.columnGeometryQuery` is gateable by default.)

- [ ] **Step 4: Add the `runBenchmarks` dispatch arm**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, add after the `.columnQuery` arm (lines 20-21):
```swift
    case .columnQuery:
        return runColumnQueryBenchmarks(enforceGate: options.enforceGate)
    case .columnGeometryQuery:
        return runColumnGeometryQueryBenchmarks(enforceGate: options.enforceGate)
```

- [ ] **Step 5: Add the `SyntheticBenchmarks` exhaustive-switch case**

In `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`, add after the `.columnQuery` case (lines 130-131):
```swift
            case .columnQuery:
                preconditionFailure("column query mode uses runColumnQueryScenario")
            case .columnGeometryQuery:
                preconditionFailure("column geometry query mode uses runColumnGeometryQueryScenario")
```

- [ ] **Step 6: Build to verify all exhaustive switches are satisfied**

Run: `swift build`
Expected: build succeeds. If the compiler reports a non-exhaustive `switch` over `BenchmarkMode` anywhere else, add the mirrored `.columnGeometryQuery` case there (the three switches above are the known set: `outputName`, `runBenchmarks`, `SyntheticBenchmarks`).

- [ ] **Step 7: Run the benchmark gate**

Run: `swift run -c release ViewportBenchmarks -- --column-geometry-query --gate`
Expected: five scenario lines, each ending `gate=pass`, process exits 0. Record the printed p95/p99 per scenario for Task 7. If any scenario prints `gate=fail`, raise that scenario's `p95`/`p99` budget in `columnGeometryQueryScenarios()` to the observed value plus the project's customary headroom (compare the neighbouring `--column-query` budget), then re-run until all pass.

- [ ] **Step 8: Verify mode-combination guards**

Run: `swift run -c release ViewportBenchmarks -- --column-geometry-query --column-query`
Expected: `error=--column-query cannot be combined with another mode` (exit 1).

Run: `swift run -c release ViewportBenchmarks -- --range-only --gate`
Expected: `error=--gate cannot be combined with range_only mode` (exit 1) — confirms the denylist is unchanged.

- [ ] **Step 9: Commit**

```bash
git add Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift \
        Sources/ViewportBenchmarks/BenchmarkOptions.swift \
        Sources/ViewportBenchmarks/BenchmarkProgram.swift \
        Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
git commit -m "feat: add --column-geometry-query benchmark mode with local gate

x->cell+box+fraction latency over uniform_* and prefixsum_* scenarios;
gateable by default (denylist unchanged). Local gate only; CI promotion
is a follow-up slice.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: AGENTS.md documentation

Add the capability to the architecture paragraph, the local command, the flags list, and the gate-valid sentence. The CI section is unchanged (local gate this slice).

**Files:**
- Modify: `AGENTS.md` (architecture paragraph ~line 77; Commands ~line 105; flags list ~line 118; gate-valid sentence ~line 122)

- [ ] **Step 1: Add the architecture sentence**

In `AGENTS.md`, after the `columnAt` sentence that ends `...` `--column-query` `is its blocking\nhost-job CI gate.` (line 76-77), append:

Old:
```
`PrefixSumColumnMetrics` (reference providers); `--column-query` is its blocking
host-job CI gate.
```
New:
```
`PrefixSumColumnMetrics` (reference providers); `--column-query` is its blocking
host-job CI gate.
`ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:)` is the geometry-bearing
companion to `columnAt`: it composes over `columnAt`, returning the located cell's
`ColumnGeometry` box (left `x` + advance `width`) plus the within-cell
`fractionInColumn` and the same clamp flag, adding only a constant number of
`columnOffset(inLine:column:)` probes (O(1) core memory), so its per-provider cost
class equals `columnAt`'s; caret snapping stays a caller concern. Its
`--column-geometry-query --gate` is **local (not-yet-CI)**.
```

- [ ] **Step 2: Add the Commands line**

In `AGENTS.md`, after the `--column-query --gate` command (line 105), add:

Old:
```
swift run -c release ViewportBenchmarks -- --column-query --gate   # x->cell within-line position-query local gate
swift run -c release ViewportBenchmarks -- --memory-shape    # memory-shape invariant; expect invariant=pass
```
New:
```
swift run -c release ViewportBenchmarks -- --column-query --gate   # x->cell within-line position-query local gate
swift run -c release ViewportBenchmarks -- --column-geometry-query --gate   # x->cell+box+fraction within-line local gate
swift run -c release ViewportBenchmarks -- --memory-shape    # memory-shape invariant; expect invariant=pass
```

- [ ] **Step 3: Add to the flags list**

In `AGENTS.md`, update the "Benchmark flags:" enumeration (lines 115-118) to include `--column-geometry-query` after `--column-query`:

Old:
```
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, `--memory-shape`, `--memory-observation`, `--gate`. Only one mode
```
New:
```
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, `--column-geometry-query`, `--memory-shape`,
`--memory-observation`, `--gate`. Only one mode
```

- [ ] **Step 4: Add to the gate-valid sentence**

In `AGENTS.md`, update the gate-valid list (lines 121-122) to add `--column-geometry-query`:

Old:
```
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`, and
`--column-query` modes; it is **rejected** with `--range-only`, `--memory-shape`,
```
New:
```
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, and `--column-geometry-query` modes; it is **rejected** with
`--range-only`, `--memory-shape`,
```

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document columnGeometryAt + --column-geometry-query local gate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Full verification sweep + verification record

Run the complete verification suite and record the evidence. Public-API change ⇒ cross-target compile is required.

**Files:**
- Create: `docs/superpowers/verification/2026-07-07-horizontal-geometry-query.md`

- [ ] **Step 1: Host tests**

Run: `swift test`
Expected: 0 failures; test count grown from 189 by the new tests (ColumnGeometryAt* core suites + the added PrefixSum method). Record the new total. (`swift test` also prints a "0 tests in 0 suites" line for the empty Swift Testing harness — not a failure.)

- [ ] **Step 2: Release build**

Run: `swift build -c release`
Expected: builds clean.

- [ ] **Step 3: New local gate**

Run: `swift run -c release ViewportBenchmarks -- --column-geometry-query --gate`
Expected: every scenario `gate=pass`. Record per-scenario p95/p99, headroom vs budget, and the checksum.

- [ ] **Step 4: All existing gates — no checksum movement**

Run each and confirm `gate=pass` (nothing shared was touched, so checksums must match the pre-slice values):
```bash
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift run -c release ViewportBenchmarks -- --line-query --gate
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
swift run -c release ViewportBenchmarks -- --column-query --gate
```
Expected: all `gate=pass`, checksums unchanged from the previous slice.

- [ ] **Step 5: Memory-shape invariant**

Run: `swift run -c release ViewportBenchmarks -- --memory-shape`
Expected: `invariant=pass` (the new query is O(1) core memory).

- [ ] **Step 6: Foundation-free scans**

Run:
```bash
rg -n "Foundation" Sources/TextEngineCore
rg -n "Foundation" Sources/TextEngineReferenceProviders
```
Expected: both empty (exit 1).

- [ ] **Step 7: Cross-target compile (public-API change)**

Run:
```bash
./.github/scripts/cross-target-compile.sh --self-test
./.github/scripts/cross-target-compile.sh --targets ios
./.github/scripts/cross-target-compile.sh --targets wasm
```
Expected: self-test passes; iOS compiles for both `TextEngineCore` and `TextEngineReferenceProviders` (blocking); WASM compiles if a matching Swift SDK is provisioned, else records a non-blocking skip (observational).

- [ ] **Step 8: Write the verification record**

Create `docs/superpowers/verification/2026-07-07-horizontal-geometry-query.md` recording, for each step above: the exact command, the key output lines (test count, per-scenario p95/p99 + checksums for the new gate, `gate=pass` for existing gates with unchanged checksums, `invariant=pass`, empty Foundation scans, cross-target results), and a `Pending` placeholder for the hosted PR-head run ID + post-merge push run ID (to be filled by the post-merge follow-up, per the standing stale-on-write lesson: anchor the PR-head proof against the stable final head in the post-merge doc).

- [ ] **Step 9: Commit**

```bash
git add docs/superpowers/verification/2026-07-07-horizontal-geometry-query.md
git commit -m "docs: record slice 35 horizontal geometry query verification

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage** (checked against `docs/superpowers/specs/2026-07-07-horizontal-geometry-query-design.md`):

- Goal — public `columnGeometryAt` over `LineHorizontalMetricsSource` → Task 1. ✓
- Decision 1 — three new types `ColumnGeometry`/`ColumnGeometryQuery`/`ColumnGeometryLocation` → Task 1 Step 3. ✓
- Decision 2 — single entry point, composed over `columnAt`, `.failure`/`.empty` pass-through → Task 1 Step 4. ✓
- Decision 3 — half-open fraction contract, clamp sentinels 0.0/1.0 → Task 1 Step 4 + Tasks 1/3 tests. ✓
- Decision 4 — O(log M)/O(1), per-path probe counts (0/1/4/`2+(ceilLog2 M+1)+2`) → Task 2. ✓
- Decision 5 — local gate, no CI change → Task 5 + Task 6 (local wording) + Task 7 (no workflow edit). ✓
- Acceptance criteria 1-6a — Tasks 1-4 (behavior, parity, structural oracle, reference equivalence, unit/failure/clamp/reconstruction, query-count, native dispatch order). ✓
- Acceptance 7 — benchmark + gateable set + denylist unchanged + single mode flag → Task 5 Steps 7-8. ✓
- Acceptance 8 — existing gates + suites unchanged, memory-shape pass → Task 7 Steps 4-5. ✓
- Acceptance 9 — Foundation scans empty; iOS blocking, WASM observational → Task 7 Steps 6-7. ✓
- Acceptance 10 — full paper trail (spec ✓ already committed; plan = this doc; verification = Task 7; post-slice review = separate follow-up) on `slice-35-horizontal-geometry-query`, one PR, conventional commits. ✓
- Documentation Updates — `columnOffset` stability precondition broadened (Task 1 Step 5), AGENTS.md (Task 6). ✓
- Deviation noted: reference equivalence goes in `PrefixSumColumnMetricsTests.swift` (established repo home) rather than a new `ColumnGeometryAtEquivalenceTests.swift` in the ref-provider target — Task 4 note.

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N"/"write tests for the above" — every code step carries complete code; every command carries expected output. The only intentional `Pending` is the hosted-run-ID placeholder in the verification record (Task 7 Step 8), which is filled by the post-merge follow-up per the project's stale-on-write lesson, not a plan gap.

**3. Type consistency:** `columnGeometryAt` signature, `ColumnGeometry(columnIndex:x:width:)`, `ColumnGeometryLocation(geometry:fractionInColumn:clamp:)`, `ColumnGeometryQuery.geometry/.empty/.failure`, `ColumnLocation.Clamp` (`.inRange`/`.clampedToLeft`/`.clampedToRight`), and `BenchmarkMode.columnGeometryQuery` (`outputName == "column_geometry_query"`) are used identically across Tasks 1-7. Field access in the benchmark (`location.geometry.columnIndex`, `location.fractionInColumn`, `location.clamp`) matches the Task 1 type definitions.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-07-horizontal-geometry-query.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
