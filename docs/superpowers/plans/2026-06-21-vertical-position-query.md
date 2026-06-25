# Vertical Position-Query (`lineAt(y:)`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a public, stateless `ViewportVirtualizer.lineAt(y:metrics:)` that maps a document `y` offset to the line whose vertical span contains it — the inverse of `LineMetricsSource.offset(ofLine:)` — with clamp semantics, an equivalence oracle, a query-count proof, and a local benchmark gate.

**Architecture:** A new `extension ViewportVirtualizer` (`PositionQuery.swift`) runs `compute`'s validation ladder, handles the two clamp branches, and for in-range `y` reuses the existing `firstLineTopAtOrBelow` binary search (relaxed from `private` to internal — no logic change). New public result types `LineQuery` / `LineLocation` / `LineLocation.Clamp` live beside the existing vocabulary in `ViewportTypes.swift`. A `--line-query` benchmark mode (uniform + balanced-tree scenarios) enforces p95/p99 budgets locally; CI promotion is a separate future slice.

**Tech Stack:** Swift 6.0 (`swift-tools-version: 6.0`), SwiftPM, XCTest. `TextEngineCore` (Foundation-free), `TextEngineReferenceProviders`, `ViewportBenchmarks` executable.

## Global Constraints

Every task implicitly inherits these (copied from the spec / AGENTS.md):

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty (exit 1). Public API exposes no Foundation types.
- **Swift Embedded compatible.** Pure arithmetic + the existing binary search only; no doubtful APIs in the core.
- **Zero-dependency.** No third-party packages.
- **Compiles for iOS and WASM with no source changes.** iOS blocking, WASM observational, via `./.github/scripts/cross-target-compile.sh`.
- **Core-owned memory must not grow linearly with document size.** `lineAt` is O(1) core memory; `--memory-shape` must still `pass`.
- **XCTest only** in `Tests/TextEngineCoreTests` (the empty Swift Testing harness prints a `0 tests in 0 suites` line — not a failure).
- **One logical step per commit**, conventional-commit prefixes (`refactor:`, `feat:`, `test:`, `ci:`, `docs:`).
- **No CI workflow change this slice** — the `--line-query --gate` is local only.

---

### Task 1: Relax the shared binary search to internal (behavior-preserving refactor)

`lineAt`'s in-range path must reuse `firstLineTopAtOrBelow` rather than copy it (spec Decision 3). It is currently `private static` in `VariableViewportVirtualizer.swift`; relax to internal `static` so `PositionQuery.swift` (a separate file, same module) can call it. This is an access-level change only — no logic, so `compute`'s behavior and every gate checksum are unchanged by construction.

**Files:**
- Modify: `Sources/TextEngineCore/VariableViewportVirtualizer.swift:67`

**Interfaces:**
- Produces: `static func firstLineTopAtOrBelow<Metrics: LineMetricsSource>(_ target: Double, metrics: Metrics, lineCount: Int, totalHeight: Double) -> Int` — now callable from other files in `TextEngineCore`. Returns the largest `i` in `[0, lineCount)` with `offset(i) <= target`; returns `lineCount` for `target >= totalHeight`.

- [ ] **Step 1: Relax the access modifier**

In `Sources/TextEngineCore/VariableViewportVirtualizer.swift`, change the declaration:

```swift
    // Largest i in [0, lineCount) with offset(i) <= target (the line containing
    // `target`). For `target` at or past the document end, returns lineCount.
    static func firstLineTopAtOrBelow<Metrics: LineMetricsSource>(
        _ target: Double,
        metrics: Metrics,
        lineCount: Int,
        totalHeight: Double
    ) -> Int {
```

(Only the line `private static func firstLineTopAtOrBelow<Metrics: LineMetricsSource>(` loses its `private`; the body is untouched. Leave `firstLineTopAtOrAbove` private — `lineAt` does not use it.)

- [ ] **Step 2: Build and run the full existing suite (no regression)**

Run: `swift build && swift test`
Expected: build succeeds; **107 tests, 0 failures** (plus the `0 tests in 0 suites` Swift Testing line). An access-only change cannot alter behavior.

- [ ] **Step 3: Confirm the variable-height gate is unchanged**

Run: `swift run -c release ViewportBenchmarks -- --variable-height --gate`
Expected: all three scenarios `gate=pass`; checksums identical to before (the change is access-only).

- [ ] **Step 4: Commit**

```bash
git add Sources/TextEngineCore/VariableViewportVirtualizer.swift
git commit -m "refactor: share firstLineTopAtOrBelow across the core for position-query reuse"
```

---

### Task 2: Public result types + `lineAt` implementation + unit tests

Add `LineQuery` / `LineLocation` / `LineLocation.Clamp`, implement `lineAt`, and prove the full Decision 4 behavior table. TDD: the unit test file references the new symbols first (won't compile → failing state), then the types + implementation make it pass.

**Files:**
- Create: `Sources/TextEngineCore/PositionQuery.swift`
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (append the result types)
- Modify: `Sources/TextEngineCore/LineMetricsSource.swift:14-18` (stability doc-comment)
- Test: `Tests/TextEngineCoreTests/LineAtTests.swift`

**Interfaces:**
- Consumes: `firstLineTopAtOrBelow(_:metrics:lineCount:totalHeight:)` (Task 1); `ViewportValidationError`, `LineMetricsSource`, `UniformLineMetrics` (existing).
- Produces:
  - `public enum LineQuery: Equatable { case line(LineLocation); case empty; case failure(ViewportValidationError) }`
  - `public struct LineLocation: Equatable { public let lineIndex: Int; public let clamp: Clamp; public init(lineIndex: Int, clamp: Clamp); public enum Clamp: Equatable { case inRange; case clampedToTop; case clampedToBottom } }`
  - `public static func lineAt<Metrics: LineMetricsSource>(y: Double, metrics: Metrics) -> LineQuery`

- [ ] **Step 1: Write the failing unit tests**

Create `Tests/TextEngineCoreTests/LineAtTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class LineAtTests: XCTestCase {
    // A non-uniform provider built from a heights array (cumulative offsets).
    private struct ListLineMetrics: LineMetricsSource {
        let offsets: [Double]
        init(heights: [Double]) {
            var acc: [Double] = [0.0]
            var running = 0.0
            for height in heights {
                running += height
                acc.append(running)
            }
            self.offsets = acc
        }
        var lineCount: Int { offsets.count - 1 }
        func offset(ofLine index: Int) -> Double { offsets[index] }
    }

    // Contract-violating providers for the defensive validation checks.
    private struct NegativeCountMetrics: LineMetricsSource {
        var lineCount: Int { -1 }
        func offset(ofLine index: Int) -> Double { 0.0 }
    }
    private struct BadFirstOffsetMetrics: LineMetricsSource {
        var lineCount: Int { 3 }
        func offset(ofLine index: Int) -> Double { Double(index) + 1.0 } // offset(0) == 1
    }
    private struct ZeroTotalMetrics: LineMetricsSource {
        var lineCount: Int { 2 }
        func offset(ofLine index: Int) -> Double { 0.0 } // offset(0) == 0, total == 0
    }

    // MARK: failure + empty outcomes

    func testNegativeLineCountFails() {
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: NegativeCountMetrics()),
                       .failure(.negativeLineCount))
    }

    func testNonFiniteYFails() {
        let metrics = UniformLineMetrics(lineCount: 5, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: .nan, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: .infinity, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: -.infinity, metrics: metrics), .failure(.nonFiniteValue))
    }

    func testInvalidFirstOffsetFails() {
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 1.0, metrics: BadFirstOffsetMetrics()),
                       .failure(.invalidLineMetrics))
    }

    func testNonPositiveTotalHeightFails() {
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 1.0, metrics: ZeroTotalMetrics()),
                       .failure(.invalidLineMetrics))
    }

    func testEmptyDocumentIsEmptyForAnyY() {
        let metrics = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: -5.0, metrics: metrics), .empty)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics), .empty)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 100.0, metrics: metrics), .empty)
    }

    // MARK: clamp flags

    func testClampToTopForNegativeY() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: -0.001, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .clampedToTop)))
    }

    func testZeroIsInRangeAtLineZero() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
    }

    func testClampToBottomAtAndPastTotalHeight() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        let total = 10.0 * 16.0
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: total, metrics: metrics),
                       .line(LineLocation(lineIndex: 9, clamp: .clampedToBottom)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: total + 100.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 9, clamp: .clampedToBottom)))
    }

    // MARK: in-range resolution

    func testExactBoundaryResolvesToStartingLine() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 16.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 1, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 16.0 * 5.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 5, clamp: .inRange)))
    }

    func testMidLineResolvesToContainingLine() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 16.0 * 3.0 + 8.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 3, clamp: .inRange)))
    }

    func testNonUniformMetricsResolveCorrectly() {
        // offsets: [0, 10, 40, 45, 95]; lineCount = 4
        let metrics = ListLineMetrics(heights: [10.0, 30.0, 5.0, 50.0])
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 9.999, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 10.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 1, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 44.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 2, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 45.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 3, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 94.999, metrics: metrics),
                       .line(LineLocation(lineIndex: 3, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 95.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 3, clamp: .clampedToBottom)))
    }

    func testSingleLineDocument() {
        let metrics = UniformLineMetrics(lineCount: 1, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: -1.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .clampedToTop)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 8.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 16.0, metrics: metrics),
                       .line(LineLocation(lineIndex: 0, clamp: .clampedToBottom)))
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `swift test --filter LineAtTests`
Expected: **compile failure** — `LineQuery`, `LineLocation`, and `ViewportVirtualizer.lineAt` are undefined. This is the failing state.

- [ ] **Step 3: Add the result types**

Append to `Sources/TextEngineCore/ViewportTypes.swift`:

```swift
public enum LineQuery: Equatable {
    case line(LineLocation)
    case empty
    case failure(ViewportValidationError)
}

public struct LineLocation: Equatable {
    public let lineIndex: Int
    public let clamp: Clamp

    public init(lineIndex: Int, clamp: Clamp) {
        self.lineIndex = lineIndex
        self.clamp = clamp
    }

    public enum Clamp: Equatable {
        case inRange
        case clampedToTop
        case clampedToBottom
    }
}
```

- [ ] **Step 4: Implement `lineAt`**

Create `Sources/TextEngineCore/PositionQuery.swift`:

```swift
extension ViewportVirtualizer {
    /// Maps a document `y` offset to the line whose half-open vertical span
    /// `[offset(i), offset(i+1))` contains it — the inverse of
    /// `LineMetricsSource.offset(ofLine:)`.
    ///
    /// Stateless. O(log N) `offset(ofLine:)` queries (one binary search), O(1)
    /// core memory. A `y` outside `[0, totalHeight)` resolves to the nearest line
    /// with `LineLocation.clamp` recording the edge. Validation mirrors
    /// `compute`'s order; an empty document is `.empty`, not a failure.
    public static func lineAt<Metrics: LineMetricsSource>(
        y: Double,
        metrics: Metrics
    ) -> LineQuery {
        let lineCount = metrics.lineCount

        if lineCount < 0 {
            return .failure(.negativeLineCount)
        }
        if !y.isFinite {
            return .failure(.nonFiniteValue)
        }
        // O(1) contract probe, checked before the empty short-circuit for parity
        // with `compute`. Do not reorder.
        if metrics.offset(ofLine: 0) != 0.0 {
            return .failure(.invalidLineMetrics)
        }
        if lineCount == 0 {
            return .empty
        }
        let totalHeight = metrics.offset(ofLine: lineCount)
        if !totalHeight.isFinite || totalHeight <= 0.0 {
            return .failure(.invalidLineMetrics)
        }

        if y < 0.0 {
            return .line(LineLocation(lineIndex: 0, clamp: .clampedToTop))
        }
        if y >= totalHeight {
            return .line(LineLocation(lineIndex: lineCount - 1, clamp: .clampedToBottom))
        }

        let index = firstLineTopAtOrBelow(
            y,
            metrics: metrics,
            lineCount: lineCount,
            totalHeight: totalHeight
        )
        return .line(LineLocation(lineIndex: index, clamp: .inRange))
    }
}
```

- [ ] **Step 5: Update the `LineMetricsSource` stability doc-comment**

In `Sources/TextEngineCore/LineMetricsSource.swift`, change the stability paragraph:

```swift
    /// Stability precondition: `lineCount` and `offset(ofLine:)` must be stable
    /// for one layout/query operation — a `compute`, a `lineAt`, and any
    /// `VariableLineGeometryCursor` traversal derived from a range it produced —
    /// so the range, the located line, and the geometry come from one consistent
    /// snapshot.
```

- [ ] **Step 6: Run the tests to confirm they pass**

Run: `swift test --filter LineAtTests`
Expected: all `LineAtTests` PASS.

- [ ] **Step 7: Run the full suite + Foundation scan**

Run: `swift test && rg -n "Foundation" Sources/TextEngineCore; echo "scan exit: $?"`
Expected: full suite green (now 107 + new `LineAtTests`); `rg` prints nothing and reports `scan exit: 1`.

- [ ] **Step 8: Commit**

```bash
git add Sources/TextEngineCore/PositionQuery.swift Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/LineMetricsSource.swift Tests/TextEngineCoreTests/LineAtTests.swift
git commit -m "feat: add ViewportVirtualizer.lineAt vertical position-query"
```

---

### Task 3: Equivalence oracle (structural, product-built sweep)

Prove `lineAt` equals the structurally-derived expected line over a product-built `y` sweep on exactly-representable uniform metrics — **not** a fragile `floor(y / lineHeight)` (spec Testing Strategy / Decision 2). Every `y` is built from a product so the expected index is known by construction.

**Files:**
- Test: `Tests/TextEngineCoreTests/LineAtEquivalenceTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.lineAt(y:metrics:)`, `LineQuery`, `LineLocation`, `UniformLineMetrics` (Task 2).

- [ ] **Step 1: Write the oracle test**

Create `Tests/TextEngineCoreTests/LineAtEquivalenceTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class LineAtEquivalenceTests: XCTestCase {
    private func assertLineAt(
        _ metrics: UniformLineMetrics,
        y: Double,
        _ expected: LineQuery,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            ViewportVirtualizer.lineAt(y: y, metrics: metrics),
            expected,
            "lineCount=\(metrics.lineCount), lineHeight=\(metrics.lineHeight), y=\(y)",
            file: file,
            line: line
        )
    }

    func testStructuralEquivalenceOverRepresentableUniformMetrics() {
        // Exactly-representable heights; counts well under 2^53 so Double(i)*h is
        // exact and strictly increasing (matches VariableUniformEquivalenceTests).
        let heights: [Double] = [1.0, 10.0, 16.0, 12.5, 256.0]
        let counts = [1, 2, 3, 100, 100_000]

        for height in heights {
            for count in counts {
                let metrics = UniformLineMetrics(lineCount: count, lineHeight: height)
                let total = Double(count) * height

                // Below the document.
                assertLineAt(metrics, y: -height,
                             .line(LineLocation(lineIndex: 0, clamp: .clampedToTop)))
                // First line top is in range.
                assertLineAt(metrics, y: 0.0,
                             .line(LineLocation(lineIndex: 0, clamp: .inRange)))

                // Product-built boundaries and mid-line points for a few k < count.
                let ks = Set([0, 1, count / 2, count - 1].filter { $0 >= 0 && $0 < count })
                for k in ks {
                    // Exact boundary offset(k) -> line k (half-open span).
                    assertLineAt(metrics, y: Double(k) * height,
                                 .line(LineLocation(lineIndex: k, clamp: .inRange)))
                    // Mid-line stays on line k.
                    assertLineAt(metrics, y: Double(k) * height + height / 2.0,
                                 .line(LineLocation(lineIndex: k, clamp: .inRange)))
                }

                // At and past the document end clamp to the last line.
                assertLineAt(metrics, y: total,
                             .line(LineLocation(lineIndex: count - 1, clamp: .clampedToBottom)))
                assertLineAt(metrics, y: total + height,
                             .line(LineLocation(lineIndex: count - 1, clamp: .clampedToBottom)))
            }
        }
    }
}
```

- [ ] **Step 2: Run the oracle test**

Run: `swift test --filter LineAtEquivalenceTests`
Expected: PASS. (If any boundary case fails, the implementation diverges from the half-open convention — do not "fix" by switching the oracle to `floor`.)

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/LineAtEquivalenceTests.swift
git commit -m "test: add structural equivalence oracle for lineAt"
```

---

### Task 4: Query-count tests (deterministic O(log N) proof)

Assert the exact `offset(ofLine:)` query counts per path, mirroring `VariableHeightQueryCountTests`. This proves the cost envelope (logarithmic queries, no linear scan) deterministically, independent of the benchmark.

**Files:**
- Test: `Tests/TextEngineCoreTests/LineAtQueryCountTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.lineAt(y:metrics:)`, `LineMetricsSource` (Task 2).

- [ ] **Step 1: Write the query-count tests**

Create `Tests/TextEngineCoreTests/LineAtQueryCountTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class LineAtQueryCountTests: XCTestCase {
    private final class QueryCounter {
        var count = 0
    }

    private struct CountingLineMetrics: LineMetricsSource {
        let base: UniformLineMetrics
        let counter: QueryCounter

        init(lineCount: Int, lineHeight: Double, counter: QueryCounter) {
            self.base = UniformLineMetrics(lineCount: lineCount, lineHeight: lineHeight)
            self.counter = counter
        }

        var lineCount: Int { base.lineCount }

        func offset(ofLine index: Int) -> Double {
            counter.count += 1
            return base.offset(ofLine: index)
        }
    }

    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value {
            capacity <<= 1
            power += 1
        }
        return power
    }

    func testInRangeUsesLogarithmicQueriesAtOneMillionLines() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)

        let result = ViewportVirtualizer.lineAt(y: Double(lineCount / 2) * 16.0 + 8.0, metrics: metrics)

        guard case .line = result else { return XCTFail("expected .line, got \(result)") }
        // Two O(1) contract queries (offset 0 and total height) plus one binary
        // search of at most ceilLog2(n)+1 probes.
        let expectedMax = 2 + (ceilLog2(lineCount) + 1)
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }

    func testEmptyDocumentQueriesOnlyFirstOffset() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 0, lineHeight: 16.0, counter: counter)

        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics), .empty)
        XCTAssertEqual(counter.count, 1)
    }

    func testClampBranchesDoNotSearch() {
        let lineCount = 1_000_000

        let topCounter = QueryCounter()
        let topMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: topCounter)
        _ = ViewportVirtualizer.lineAt(y: -1.0, metrics: topMetrics)
        XCTAssertEqual(topCounter.count, 2) // offset(0) + total, no search

        let bottomCounter = QueryCounter()
        let bottomMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: bottomCounter)
        _ = ViewportVirtualizer.lineAt(y: Double(lineCount) * 16.0 + 1.0, metrics: bottomMetrics)
        XCTAssertEqual(bottomCounter.count, 2)
    }

    func testNonFiniteYDoesNotQueryOffsets() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 1_000, lineHeight: 16.0, counter: counter)

        XCTAssertEqual(ViewportVirtualizer.lineAt(y: .nan, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(counter.count, 0)
    }
}
```

- [ ] **Step 2: Run the query-count tests**

Run: `swift test --filter LineAtQueryCountTests`
Expected: PASS (in-range `count <= 23` and `< 100`; empty `== 1`; clamp `== 2`; non-finite `== 0`).

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/LineAtQueryCountTests.swift
git commit -m "test: assert lineAt query-count envelope (O(log N), O(1) memory)"
```

---

### Task 5: `--line-query` benchmark mode + local gate

Add the benchmark mode with uniform **and** balanced-tree scenarios (the balanced-tree scenario is the real O(log² N) hot path — spec Decision/benchmark section), wire it into the option parser and program, then calibrate macOS budgets so the gate passes with comfortable headroom.

**Files:**
- Create: `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (mode enum, `outputName`, parse case, usage)
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift` (dispatch arm)

**Interfaces:**
- Consumes: `ViewportVirtualizer.lineAt(y:metrics:)`, `LineQuery`, `LineLocation` (Task 2); `UniformLineMetrics`; `BalancedTreeLineMetrics(heights:)`; existing `variableHeights(lineCount:)`, `deterministicScrollOffset(sample:maxOffset:)`, `nanoseconds(_:)`, `percentile(_:numerator:denominator:)`, `formatSummary(_:includeGate:)`, `BenchmarkSummary`, `BenchmarkOperationResult`.
- Produces: `func runLineQueryBenchmarks(enforceGate: Bool) -> Bool` (`@available(macOS 13.0, *)`); `BenchmarkMode.lineQuery`.

- [ ] **Step 1: Add the `.lineQuery` mode**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, add the case to `BenchmarkMode` (after `bulkStructuralMutation`):

```swift
    case bulkStructuralMutation
    case lineQuery
    case memoryShape
```

and to `outputName`:

```swift
        case .lineQuery:
            return "line_query"
```

- [ ] **Step 2: Add the parse case + usage**

In `BenchmarkOptions.parse`, add after the `--bulk-structural-mutation` case:

```swift
            case "--line-query":
                if mode != .pipeline {
                    return .failure("--line-query cannot be combined with another mode")
                }
                mode = .lineQuery
```

Add `--line-query` to the `usage` string's flag list and an option line:

```swift
      --line-query          Run y->line position-query benchmark. Combine with --gate to enforce budgets.
```

(No change to the `--gate` reject check: `.lineQuery` is not in `{rangeOnly, memoryShape, memoryObservation}`, so `--gate` is accepted automatically.)

- [ ] **Step 3: Add the dispatch arm**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, add to the `switch options.mode`:

```swift
    case .lineQuery:
        return runLineQueryBenchmarks(enforceGate: options.enforceGate)
```

- [ ] **Step 4: Create the benchmark with starter budgets**

Create `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`:

```swift
import TextEngineCore
import TextEngineReferenceProviders

struct LineQueryScenario {
    let name: String
    let providerName: String
    let lineCount: Int
    let useBalancedTree: Bool
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// Starter budgets (macOS-calibrated in Step 6). Uniform/PrefixSum offsets are
// O(1) -> O(log N) search; balanced-tree offsets are O(log N) -> O(log^2 N).
func lineQueryScenarios() -> [LineQueryScenario] {
    [
        LineQueryScenario(name: "uniform_1k", providerName: "uniform",
                          lineCount: 1_000, useBalancedTree: false,
                          p95BudgetNanoseconds: 30_000, p99BudgetNanoseconds: 60_000),
        LineQueryScenario(name: "uniform_100k", providerName: "uniform",
                          lineCount: 100_000, useBalancedTree: false,
                          p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000),
        LineQueryScenario(name: "uniform_1m", providerName: "uniform",
                          lineCount: 1_000_000, useBalancedTree: false,
                          p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        LineQueryScenario(name: "balanced_tree_100k", providerName: "balanced_tree",
                          lineCount: 100_000, useBalancedTree: true,
                          p95BudgetNanoseconds: 300_000, p99BudgetNanoseconds: 600_000),
        LineQueryScenario(name: "balanced_tree_1m", providerName: "balanced_tree",
                          lineCount: 1_000_000, useBalancedTree: true,
                          p95BudgetNanoseconds: 600_000, p99BudgetNanoseconds: 1_200_000),
    ]
}

@inline(never)
func runLineQueryOperation<Metrics: LineMetricsSource>(
    y: Double,
    metrics: Metrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.lineAt(y: y, metrics: metrics) {
    case let .line(location):
        var checksum = location.lineIndex
        switch location.clamp {
        case .inRange: checksum &+= 1
        case .clampedToTop: checksum &+= 2
        case .clampedToBottom: checksum &+= 3
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runLineQueryScenarioCore<Metrics: LineMetricsSource>(
    _ scenario: LineQueryScenario,
    metrics: Metrics,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let totalHeight = metrics.offset(ofLine: metrics.lineCount)
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
            switch sample % 8 {
            case 0:
                y = -1.0 - Double(sample % 1_000)         // below the document
            case 1:
                y = totalHeight + Double(sample % 1_000)  // past the document end
            default:
                y = deterministicScrollOffset(sample: sample, maxOffset: totalHeight)
            }
            let result = runLineQueryOperation(y: y, metrics: metrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .lineQuery,
        providerName: scenario.providerName,
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: metrics.lineCount,
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
func runLineQueryScenario(
    _ scenario: LineQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useBalancedTree {
        let metrics = BalancedTreeLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
        return runLineQueryScenarioCore(scenario, metrics: metrics,
                                        iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let metrics = UniformLineMetrics(lineCount: scenario.lineCount, lineHeight: 16.0)
        return runLineQueryScenarioCore(scenario, metrics: metrics,
                                        iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runLineQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in lineQueryScenarios() {
        let summary = runLineQueryScenario(
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

- [ ] **Step 5: Build and run without the gate (measure)**

Run: `swift build -c release && swift run -c release ViewportBenchmarks -- --line-query`
Expected: five `mode=line_query` lines (three `provider=uniform`, two `provider=balanced_tree`), each with `failures=0` and a `checksum=`. Record each scenario's `p95_ns` / `p99_ns`.

- [ ] **Step 6: Calibrate the budgets**

For each scenario, compare the observed `p95_ns` to the starter budget. Each budget must sit comfortably above the observed value (target ≈ 5–10× headroom, the project's customary posture). If any observed `p95_ns` is within ~5× of its budget, or exceeds it, raise that scenario's `p95BudgetNanoseconds` to roughly `observed_p95 × 10` and `p99BudgetNanoseconds` to roughly `observed_p99 × 10`, rounded to a clean number, in `lineQueryScenarios()`. If observed values are far under the starters, leave the starters (generous local budgets are expected). Record the final budgets and observed numbers for the verification doc.

- [ ] **Step 7: Run with the gate**

Run: `swift run -c release ViewportBenchmarks -- --line-query --gate`
Expected: all five scenarios print `gate=pass` and the process exits `0`.

- [ ] **Step 8: Confirm `--gate` validity rules are intact**

Run: `swift run -c release ViewportBenchmarks -- --range-only --gate; echo "exit: $?"`
Expected: `error=--gate cannot be combined with range_only mode` and `exit: 1` (the existing rejection still holds; `--line-query` did not loosen it).

- [ ] **Step 9: Commit**

```bash
git add Sources/ViewportBenchmarks/LineQueryBenchmark.swift Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift
git commit -m "feat: add --line-query benchmark mode with local gate"
```

---

### Task 6: Update AGENTS.md (local command + flags)

Document the new local gate and flag in the durable guide. **No CI workflow change** — the gate is local this slice; the CI section stays as is.

**Files:**
- Modify: `AGENTS.md` (Commands block, Benchmark flags paragraph, architecture paragraph)

- [ ] **Step 1: Add the local command**

In the `## Commands` fenced block, add after the `--bulk-structural-mutation --gate` line:

```bash
swift run -c release ViewportBenchmarks -- --line-query --gate   # y→line position-query local gate
```

- [ ] **Step 2: Update the benchmark-flags paragraph**

Add `--line-query` to the flag list and to the `--gate`-valid list:

- In the list of flags, insert `` `--line-query`, `` before `` `--memory-shape` ``.
- In "`--gate` is valid with …", add `` `--line-query`, `` to the accepted modes (e.g. after `--bulk-structural-mutation`).

- [ ] **Step 3: Add a one-line architecture note**

In the "Architecture in one paragraph" section, append a sentence noting the reverse mapping:

```
`ViewportVirtualizer.lineAt(y:metrics:)` is the inverse query — y → line — over
the same `LineMetricsSource`, O(log N) queries / O(1) core memory, reusing the
same binary search; out-of-range `y` clamps with a `LineLocation.clamp` flag.
```

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document lineAt and the --line-query local gate in AGENTS.md"
```

---

### Task 7: Full verification sweep + record

Run every required check and write the verification record. Anchor merged-code proof in the post-merge run per the Slice 26 stale-on-write lesson (the PR-head proof goes in the post-merge follow-up against the stable final head, never a pre-final commit).

**Files:**
- Create: `docs/superpowers/verification/2026-06-21-vertical-position-query.md`

- [ ] **Step 1: Host tests + build**

Run: `swift test && swift build -c release`
Expected: full suite green (existing 107 + `LineAtTests` + `LineAtEquivalenceTests` + `LineAtQueryCountTests`); release build succeeds. Record the test count.

- [ ] **Step 2: New gate**

Run: `swift run -c release ViewportBenchmarks -- --line-query --gate`
Expected: five `gate=pass`. Record p95/p99/budgets/checksums.

- [ ] **Step 3: Existing gates unchanged (behavior-preservation)**

Run each and confirm `gate=pass` with checksums identical to the recorded baselines:
```
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
```
Expected: all pass; checksums match (the Task 1 refactor is access-only).

- [ ] **Step 4: Memory-shape invariant**

Run: `swift run -c release ViewportBenchmarks -- --memory-shape`
Expected: `invariant=pass` (lineAt adds no core-owned memory growth).

- [ ] **Step 5: Foundation-free scans**

Run: `rg -n "Foundation" Sources/TextEngineCore; echo "core exit: $?"; rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "providers exit: $?"`
Expected: no output; both `exit: 1`.

- [ ] **Step 6: Cross-target self-test + compile**

Run: `./.github/scripts/cross-target-compile.sh --self-test`
Expected: `self_test=pass`. Then run the iOS path (blocking) and the WASM path (observational) as available locally:
```
./.github/scripts/cross-target-compile.sh --targets ios
./.github/scripts/cross-target-compile.sh --targets wasm
```
Record results (WASM may record a non-blocking skip if no matching SDK).

- [ ] **Step 7: Write the verification record**

Create `docs/superpowers/verification/2026-06-21-vertical-position-query.md` capturing the actual commands and outputs from Steps 1–6 (test count, gate p95/p99/budgets/checksums for `--line-query`, identical checksums for the five existing gates, memory-shape `pass`, empty Foundation scans, cross-target results). Leave the hosted PR-head + post-merge run IDs as `Pending` to be filled by the post-merge follow-up (per the stale-on-write convention).

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/verification/2026-06-21-vertical-position-query.md
git commit -m "docs: record local verification sweep for vertical position-query"
```

---

## Notes for execution

- After Task 7, open one PR for the `slice-27-vertical-position-query` branch. The post-merge follow-up PR fills the hosted run IDs in the verification record (do not record PR-head proof against a pre-final commit).
- The post-slice review (recommending Slice 28 = promote `--line-query --gate` to a blocking hosted CI gate) is written after merge on a `slice-27-post-slice-review` branch and is **not** auto-merged — the user reviews it first.
- If any existing-gate checksum changes in Task 7 Step 3, stop: the Task 1 refactor was supposed to be access-only. Investigate before proceeding (systematic-debugging).
