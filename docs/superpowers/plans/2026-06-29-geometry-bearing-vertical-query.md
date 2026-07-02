# Geometry-Bearing Vertical Query (`lineGeometryAt`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ViewportVirtualizer.lineGeometryAt(y:metrics:)`, a stateless query that returns the located line's box (`LineGeometry`) plus the within-line `fractionInLine` and a clamp flag, composed over the existing `lineAt`.

**Architecture:** A new public method in `PositionQuery.swift` delegates to `lineAt` for validation/index/clamp, then reads `offset(ofLine: i)` / `offset(ofLine: i+1)` to build the box and computes the fraction. Two new public types (`LineGeometryQuery`, `LineGeometryLocation`) reuse the existing `LineGeometry` and `LineLocation.Clamp`. No provider, `lineAt`, `compute`, or `LineQuery` change. A new `--line-geometry-query` benchmark mode + local gate mirrors `--line-query`.

**Tech Stack:** Swift 6.0, SwiftPM, XCTest, headless `TextEngineCore` + `TextEngineReferenceProviders` + `ViewportBenchmarks`.

## Global Constraints

- **No Foundation in `Sources/TextEngineCore`** — `rg -n "Foundation" Sources/TextEngineCore` must be empty (also empty for `Sources/TextEngineReferenceProviders`).
- **Swift Embedded compatible / zero-dependency / compiles for iOS + WASM with no source changes.**
- **Core-owned memory must not grow with document size** — the new query is O(1) core memory.
- **Additive, non-breaking public API** — new method + new types only; do **not** add a case to `LineQuery`, and do **not** change `lineAt`, `compute`, the `LineMetricsSource` protocol surface, or any provider's behavior.
- **Per-provider cost equals `lineAt`'s** — the two added `offset` probes are a constant factor (O(log N) for O(1)-offset providers and the balanced tree; O(log²N) inherited for Fenwick). Never a new log factor.
- **No `.github/workflows/swift-ci.yml` change** — `--line-geometry-query --gate` is a **local** gate this slice; CI promotion is the follow-up Slice 32.
- **One PR on branch `slice-31-geometry-bearing-vertical-query`; conventional commits** (`feat:`, `test:`, `docs:`), one logical step per commit.
- **Reference:** spec `docs/superpowers/specs/2026-06-29-geometry-bearing-vertical-query-design.md`.

---

## File Structure

- `Sources/TextEngineCore/ViewportTypes.swift` (modify) — add `LineGeometryQuery`, `LineGeometryLocation`.
- `Sources/TextEngineCore/PositionQuery.swift` (modify) — add `lineGeometryAt(y:metrics:)`.
- `Sources/TextEngineCore/LineMetricsSource.swift` (modify) — stability-precondition doc-comment names `lineGeometryAt`.
- `Tests/TextEngineCoreTests/LineGeometryAtTests.swift` (create) — unit/edge/clamp-fraction tests.
- `Tests/TextEngineCoreTests/LineGeometryAtEquivalenceTests.swift` (create) — structural uniform oracle + parity with `lineAt`.
- `Tests/TextEngineCoreTests/LineGeometryAtQueryCountTests.swift` (create) — query-count + native-hook dispatch/order tests.
- `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift` (modify) — balanced-tree-vs-prefix-sum geometry equivalence oracle (incl. post-mutation).
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (modify) — `.lineGeometryQuery` mode, `outputName`, `--line-geometry-query` parse + usage.
- `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift` (modify) — exhaustive-switch `.lineGeometryQuery` case.
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift` (modify) — dispatch arm.
- `Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift` (create) — the benchmark + scenarios + local gate.
- `AGENTS.md` (modify) — architecture paragraph + Commands + benchmark flags.
- `docs/superpowers/verification/2026-06-29-geometry-bearing-vertical-query.md` (create) — verification record.

---

## Task 1: Core query — types, method, unit tests, doc-comment

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (after `LineLocation`, ~line 120)
- Modify: `Sources/TextEngineCore/PositionQuery.swift` (extend the existing `extension ViewportVirtualizer`)
- Modify: `Sources/TextEngineCore/LineMetricsSource.swift:16` (doc-comment only)
- Test: `Tests/TextEngineCoreTests/LineGeometryAtTests.swift` (create)

**Interfaces:**
- Consumes: `ViewportVirtualizer.lineAt(y:metrics:) -> LineQuery`; `LineQuery` (`.line(LineLocation)` / `.empty` / `.failure`); `LineLocation` (`lineIndex`, `clamp: Clamp`); `LineLocation.Clamp` (`.inRange` / `.clampedToTop` / `.clampedToBottom`); `LineGeometry(lineIndex:y:height:)`; `LineMetricsSource.offset(ofLine:)`; test helpers `UniformLineMetrics`, `ListLineMetrics`, `ClosureLineMetrics` (the last two in `Tests/TextEngineCoreTests/TestLineMetrics.swift`).
- Produces: `LineGeometryQuery` (`.geometry(LineGeometryLocation)` / `.empty` / `.failure(ViewportValidationError)`); `LineGeometryLocation(geometry: LineGeometry, fractionInLine: Double, clamp: LineLocation.Clamp)`; `static func lineGeometryAt<Metrics: LineMetricsSource>(y: Double, metrics: Metrics) -> LineGeometryQuery`.

- [ ] **Step 1: Write the failing unit tests**

Create `Tests/TextEngineCoreTests/LineGeometryAtTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class LineGeometryAtTests: XCTestCase {
    private func geom(_ index: Int, _ y: Double, _ height: Double) -> LineGeometry {
        LineGeometry(lineIndex: index, y: y, height: height)
    }

    // MARK: failure + empty outcomes (inherited from lineAt)

    func testNegativeLineCountFails() {
        let metrics = ClosureLineMetrics(lineCount: -1, offsetForLine: { _ in 0.0 })
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics),
                       .failure(.negativeLineCount))
    }

    func testNonFiniteYFails() {
        let metrics = UniformLineMetrics(lineCount: 5, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: .nan, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: .infinity, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -.infinity, metrics: metrics), .failure(.nonFiniteValue))
    }

    func testInvalidFirstOffsetFails() {
        let metrics = ClosureLineMetrics(lineCount: 3, offsetForLine: { Double($0) + 1.0 })
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 1.0, metrics: metrics),
                       .failure(.invalidLineMetrics))
    }

    func testNonPositiveTotalHeightFails() {
        let metrics = ClosureLineMetrics(lineCount: 2, offsetForLine: { _ in 0.0 })
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 1.0, metrics: metrics),
                       .failure(.invalidLineMetrics))
    }

    func testEmptyDocumentIsEmptyForAnyY() {
        let metrics = UniformLineMetrics(lineCount: 0, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -5.0, metrics: metrics), .empty)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics), .empty)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 100.0, metrics: metrics), .empty)
    }

    // MARK: in-range geometry + fraction

    func testExactLineTopHasZeroFraction() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 16.0 * 5.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(5, 80.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .inRange)))
    }

    func testMidLineHasHalfFraction() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 16.0 * 3.0 + 8.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(3, 48.0, 16.0),
                                                      fractionInLine: 0.5, clamp: .inRange)))
    }

    func testZeroIsInRangeAtLineZero() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .inRange)))
    }

    // MARK: clamp fractions

    func testClampToTopHasZeroFractionOnFirstLine() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -0.001, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .clampedToTop)))
    }

    func testClampToBottomHasUnitFractionOnLastLine() {
        let metrics = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
        let total = 10.0 * 16.0
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: total, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(9, 144.0, 16.0),
                                                      fractionInLine: 1.0, clamp: .clampedToBottom)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: total + 100.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(9, 144.0, 16.0),
                                                      fractionInLine: 1.0, clamp: .clampedToBottom)))
    }

    // MARK: non-uniform metrics

    func testNonUniformGeometryAndFraction() {
        // heights [10,30,5,50] -> offsets [0,10,40,45,95], total 95, lineCount 4
        let metrics = ListLineMetrics(heights: [10.0, 30.0, 5.0, 50.0])
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 10.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(1, 10.0, 30.0),
                                                      fractionInLine: 0.0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 25.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(1, 10.0, 30.0),
                                                      fractionInLine: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 42.5, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(2, 40.0, 5.0),
                                                      fractionInLine: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -1.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 10.0),
                                                      fractionInLine: 0.0, clamp: .clampedToTop)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 95.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(3, 45.0, 50.0),
                                                      fractionInLine: 1.0, clamp: .clampedToBottom)))
    }

    func testSingleLineDocument() {
        let metrics = UniformLineMetrics(lineCount: 1, lineHeight: 16.0)
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: -1.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .clampedToTop)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.0, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 8.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 0.5, clamp: .inRange)))
        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 16.0, metrics: metrics),
                       .geometry(LineGeometryLocation(geometry: geom(0, 0.0, 16.0),
                                                      fractionInLine: 1.0, clamp: .clampedToBottom)))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail (do not compile)**

Run: `swift test --filter LineGeometryAtTests`
Expected: FAIL — compile error, `cannot find 'LineGeometryQuery'`/`lineGeometryAt` in scope.

- [ ] **Step 3: Add the result types**

In `Sources/TextEngineCore/ViewportTypes.swift`, immediately after the `LineLocation` struct (after its closing `}` near line 120), add:

```swift
public enum LineGeometryQuery: Equatable {
    case geometry(LineGeometryLocation)
    case empty
    case failure(ViewportValidationError)
}

public struct LineGeometryLocation: Equatable {
    /// The located line's box: lineIndex, top y, height.
    public let geometry: LineGeometry
    /// Where `y` falls within the line: `0.0` at the line top and when clamped to
    /// top; `(y - geometry.y) / geometry.height` in `[0, 1)` for an in-range
    /// query; `1.0` when clamped to bottom.
    public let fractionInLine: Double
    /// Whether the query landed inside the document or past an edge (from `lineAt`).
    public let clamp: LineLocation.Clamp

    public init(geometry: LineGeometry, fractionInLine: Double, clamp: LineLocation.Clamp) {
        self.geometry = geometry
        self.fractionInLine = fractionInLine
        self.clamp = clamp
    }
}
```

- [ ] **Step 4: Add the `lineGeometryAt` method**

In `Sources/TextEngineCore/PositionQuery.swift`, inside the existing `extension ViewportVirtualizer { ... }` (after `lineAt`), add:

```swift
    /// The geometry-bearing companion to `lineAt(y:metrics:)`: returns the located
    /// line's box (`LineGeometry`) plus the within-line `fractionInLine` and the
    /// same clamp flag.
    ///
    /// Composes over `lineAt` — index, clamp, and the validation ladder come
    /// straight from it (parity by construction) — then reads `offset(ofLine: i)`
    /// and `offset(ofLine: i + 1)` to build the box. Adds only a constant number of
    /// `offset(ofLine:)` probes over `lineAt`, so it never adds a log factor and its
    /// per-provider cost class equals `lineAt`'s. O(1) core memory. `.empty` /
    /// `.failure` pass straight through from `lineAt`.
    public static func lineGeometryAt<Metrics: LineMetricsSource>(
        y: Double,
        metrics: Metrics
    ) -> LineGeometryQuery {
        switch lineAt(y: y, metrics: metrics) {
        case let .failure(error):
            return .failure(error)
        case .empty:
            return .empty
        case let .line(location):
            let top = metrics.offset(ofLine: location.lineIndex)
            let bottom = metrics.offset(ofLine: location.lineIndex + 1)
            let box = LineGeometry(lineIndex: location.lineIndex, y: top, height: bottom - top)
            let fraction: Double
            switch location.clamp {
            case .clampedToTop:
                fraction = 0.0
            case .clampedToBottom:
                fraction = 1.0
            case .inRange:
                fraction = (y - top) / box.height
            }
            return .geometry(LineGeometryLocation(geometry: box, fractionInLine: fraction, clamp: location.clamp))
        }
    }
```

Note: `lineAt(...)` is unqualified here because it is a `static` method on the same `ViewportVirtualizer` type as `lineGeometryAt`; if the compiler reports it as unresolved, qualify as `Self.lineAt(y: y, metrics: metrics)`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter LineGeometryAtTests`
Expected: PASS (all `LineGeometryAtTests` green).

- [ ] **Step 6: Update the `LineMetricsSource` stability precondition doc-comment**

In `Sources/TextEngineCore/LineMetricsSource.swift`, change the stability-precondition comment (currently lines 15-16):

```swift
    /// Stability precondition: `lineCount` and `offset(ofLine:)` must be stable
    /// for one layout/query operation - a `compute`, a `lineAt`, and any
```

to:

```swift
    /// Stability precondition: `lineCount` and `offset(ofLine:)` must be stable
    /// for one layout/query operation - a `compute`, a `lineAt`, a `lineGeometryAt`,
    /// and any
```

(Comment only; no behavior change.)

- [ ] **Step 7: Run the full core suite to confirm nothing regressed**

Run: `swift test --filter TextEngineCoreTests`
Expected: PASS, 0 failures (existing suite + the new `LineGeometryAtTests`).

- [ ] **Step 8: Commit**

```bash
git add Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/PositionQuery.swift Sources/TextEngineCore/LineMetricsSource.swift Tests/TextEngineCoreTests/LineGeometryAtTests.swift
git commit -m "feat: add geometry-bearing lineGeometryAt query"
```

---

## Task 2: Structural uniform oracle + parity with `lineAt`

**Files:**
- Test: `Tests/TextEngineCoreTests/LineGeometryAtEquivalenceTests.swift` (create)

**Interfaces:**
- Consumes: `ViewportVirtualizer.lineGeometryAt`, `ViewportVirtualizer.lineAt`, `UniformLineMetrics`, `LineGeometry`, `LineGeometryLocation`, `LineGeometryQuery`, `LineQuery`.

This oracle derives the expected box/fraction **independently** from products over exactly-representable heights (not from the production method), and pins that `lineGeometryAt`'s index+clamp equal `lineAt`'s. It should pass against Task 1; if it fails, Task 1 has a bug.

- [ ] **Step 1: Write the oracle test**

Create `Tests/TextEngineCoreTests/LineGeometryAtEquivalenceTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class LineGeometryAtEquivalenceTests: XCTestCase {
    private func assertGeometry(
        _ metrics: UniformLineMetrics,
        y: Double,
        index: Int,
        fraction: Double,
        clamp: LineLocation.Clamp,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let h = metrics.lineHeight
        let expected = LineGeometryQuery.geometry(
            LineGeometryLocation(
                geometry: LineGeometry(lineIndex: index, y: Double(index) * h, height: h),
                fractionInLine: fraction,
                clamp: clamp
            )
        )
        XCTAssertEqual(
            ViewportVirtualizer.lineGeometryAt(y: y, metrics: metrics),
            expected,
            "lineCount=\(metrics.lineCount), lineHeight=\(h), y=\(y)",
            file: file, line: line
        )
    }

    func testStructuralEquivalenceOverRepresentableUniformMetrics() {
        // Exactly-representable heights; counts well under 2^53 so Double(i)*h is
        // exact and the fractions (0.0, 0.5, 1.0) are exact.
        let heights: [Double] = [1.0, 10.0, 16.0, 12.5, 256.0]
        let counts = [1, 2, 3, 100, 100_000]

        for height in heights {
            for count in counts {
                let metrics = UniformLineMetrics(lineCount: count, lineHeight: height)
                let total = Double(count) * height

                // Below the document -> clamp to top, fraction 0.0, line 0 box.
                assertGeometry(metrics, y: -height, index: 0, fraction: 0.0, clamp: .clampedToTop)

                let ks = Set([0, 1, count / 2, count - 1].filter { $0 >= 0 && $0 < count })
                for k in ks {
                    // Exact line top -> fraction 0.0, in range.
                    assertGeometry(metrics, y: Double(k) * height, index: k, fraction: 0.0, clamp: .inRange)
                    // Mid-line -> fraction 0.5, in range.
                    assertGeometry(metrics, y: Double(k) * height + height / 2.0,
                                   index: k, fraction: 0.5, clamp: .inRange)
                }

                // At and past the end -> clamp to bottom, fraction 1.0, last-line box.
                assertGeometry(metrics, y: total, index: count - 1, fraction: 1.0, clamp: .clampedToBottom)
                assertGeometry(metrics, y: total + height, index: count - 1, fraction: 1.0, clamp: .clampedToBottom)
            }
        }
    }

    func testIndexAndClampParityWithLineAt() {
        let metrics = UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0)
        let total = 1_000.0 * 16.0
        var ys: [Double] = [-10.0, 0.0, total, total + 25.0]
        for k in [0, 1, 500, 999] {
            ys.append(Double(k) * 16.0)
            ys.append(Double(k) * 16.0 + 7.0)
        }
        for y in ys {
            let geometryResult = ViewportVirtualizer.lineGeometryAt(y: y, metrics: metrics)
            let lineResult = ViewportVirtualizer.lineAt(y: y, metrics: metrics)
            guard case let .geometry(loc) = geometryResult, case let .line(line) = lineResult else {
                return XCTFail("expected .geometry and .line for y=\(y), got \(geometryResult) / \(lineResult)")
            }
            XCTAssertEqual(loc.geometry.lineIndex, line.lineIndex, "index parity y=\(y)")
            XCTAssertEqual(loc.clamp, line.clamp, "clamp parity y=\(y)")
        }
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter LineGeometryAtEquivalenceTests`
Expected: PASS (pins Task 1's geometry/fraction against an independent oracle and `lineAt` parity).

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/LineGeometryAtEquivalenceTests.swift
git commit -m "test: pin lineGeometryAt geometry against uniform oracle and lineAt parity"
```

---

## Task 3: Query-count + native-hook dispatch/order tests

**Files:**
- Test: `Tests/TextEngineCoreTests/LineGeometryAtQueryCountTests.swift` (create)

**Interfaces:**
- Consumes: `ViewportVirtualizer.lineGeometryAt`, `LineMetricsSource`, `UniformLineMetrics`, `LineGeometry`, `LineGeometryLocation`.
- The private harnesses (`QueryCounter`, `CountingLineMetrics`, `NativeSearchEvent`, `NativeSearchCounter`, `NativeSearchMetrics`, `ceilLog2`) mirror those in `LineAtQueryCountTests.swift`; they are redeclared private here so the existing file is untouched.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TextEngineCoreTests/LineGeometryAtQueryCountTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

final class LineGeometryAtQueryCountTests: XCTestCase {
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

    private enum NativeSearchEvent: Equatable {
        case offset(Int)
        case native(Double)
    }

    private final class NativeSearchCounter {
        var events: [NativeSearchEvent] = []
    }

    private struct NativeSearchMetrics: LineMetricsSource {
        let offsets: [Double]
        let counter: NativeSearchCounter

        var lineCount: Int { offsets.count - 1 }

        func offset(ofLine index: Int) -> Double {
            counter.events.append(.offset(index))
            return offsets[index]
        }

        func lineIndex(containingOffset y: Double) -> Int {
            counter.events.append(.native(y))
            var result = 0
            for index in 0..<(offsets.count - 1) {
                if offsets[index] <= y { result = index } else { break }
            }
            return result
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

    func testInRangeUsesLogarithmicQueriesPlusTwoGeometryProbes() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)

        let result = ViewportVirtualizer.lineGeometryAt(y: Double(lineCount / 2) * 16.0 + 8.0, metrics: metrics)

        guard case .geometry = result else { return XCTFail("expected .geometry, got \(result)") }
        // lineAt's 2 contract probes + binary search (<= ceilLog2(n)+1) + 2 geometry probes.
        let expectedMax = 2 + (ceilLog2(lineCount) + 1) + 2
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }

    func testEmptyDocumentQueriesOnlyFirstOffset() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 0, lineHeight: 16.0, counter: counter)

        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics), .empty)
        XCTAssertEqual(counter.count, 1)
    }

    func testClampBranchesUseFourProbes() {
        let lineCount = 1_000_000

        let topCounter = QueryCounter()
        let topMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: topCounter)
        _ = ViewportVirtualizer.lineGeometryAt(y: -1.0, metrics: topMetrics)
        XCTAssertEqual(topCounter.count, 4) // lineAt offset(0)+total, then box offset(0)+offset(1)

        let bottomCounter = QueryCounter()
        let bottomMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: bottomCounter)
        _ = ViewportVirtualizer.lineGeometryAt(y: Double(lineCount) * 16.0 + 1.0, metrics: bottomMetrics)
        XCTAssertEqual(bottomCounter.count, 4)
    }

    func testNonFiniteYDoesNotQueryOffsets() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 1_000, lineHeight: 16.0, counter: counter)

        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: .nan, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(counter.count, 0)
    }

    func testDispatchesToNativeHookThenTakesTwoGeometryProbesInOrder() {
        let counter = NativeSearchCounter()
        let metrics = NativeSearchMetrics(offsets: [0.0, 10.0, 30.0, 35.0, 80.0], counter: counter)

        let result = ViewportVirtualizer.lineGeometryAt(y: 31.0, metrics: metrics)

        XCTAssertEqual(result, .geometry(LineGeometryLocation(
            geometry: LineGeometry(lineIndex: 2, y: 30.0, height: 5.0),
            fractionInLine: (31.0 - 30.0) / 5.0,
            clamp: .inRange
        )))
        // lineAt: offset(0), offset(lineCount=4), native(31); then box: offset(2), offset(3).
        XCTAssertEqual(counter.events, [.offset(0), .offset(4), .native(31.0), .offset(2), .offset(3)])
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter LineGeometryAtQueryCountTests`
Expected: PASS — confirms the O(log N) query / O(1) memory envelope, the per-path probe counts, and that the composed query reuses `lineAt`'s native index dispatch then takes exactly two ordered geometry probes.

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineCoreTests/LineGeometryAtQueryCountTests.swift
git commit -m "test: prove lineGeometryAt query-count envelope and native dispatch order"
```

---

## Task 4: Balanced-tree-vs-prefix-sum geometry equivalence oracle

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift` (add a helper + a test in the existing `BalancedTreeLineMetricsTests` class; reuse its `sampleHeights`, `sampledSearchOffsets`)

**Interfaces:**
- Consumes: `ViewportVirtualizer.lineGeometryAt`, `BalancedTreeLineMetrics(heights:)` (+ `setHeight(ofLine:to:)`, `insertLines(at:heights:)`, `removeLines(at:count:)`), `PrefixSumLineMetrics(heights:)`, existing private helpers `sampleHeights(_:)`, `sampledSearchOffsets(_:)`.

This proves the composed geometry is byte-identical over the tree and the prefix-sum oracle, statically and after mutations — the provider-equivalence half of the two-oracle design.

- [ ] **Step 1: Add the helper and test**

In `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`, inside the `BalancedTreeLineMetricsTests` class (e.g. just after `testLineAtWithBalancedTreeMatchesPrefixSumOracle`), add:

```swift
    private func assertLineGeometryAtMatchesOracle(
        _ tree: BalancedTreeLineMetrics,
        _ array: [Double],
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let oracle = PrefixSumLineMetrics(heights: array)
        var samples = sampledSearchOffsets(oracle)
        let total = oracle.offset(ofLine: oracle.lineCount)
        samples.append(-1.0)
        samples.append(total)
        samples.append(total + 100.0)
        for y in samples {
            XCTAssertEqual(
                ViewportVirtualizer.lineGeometryAt(y: y, metrics: tree),
                ViewportVirtualizer.lineGeometryAt(y: y, metrics: oracle),
                "lineGeometryAt y=\(y) \(message())",
                file: file, line: line
            )
        }
    }

    func testLineGeometryAtWithBalancedTreeMatchesPrefixSumOracle() {
        var array = sampleHeights(1_000)
        var tree = BalancedTreeLineMetrics(heights: array)
        assertLineGeometryAtMatchesOracle(tree, array, "initial")

        tree.setHeight(ofLine: 0, to: 40.0); array[0] = 40.0
        assertLineGeometryAtMatchesOracle(tree, array, "after setHeight")

        let inserted = [17.0, 29.0, 31.0]
        tree.insertLines(at: 20, heights: inserted); array.insert(contentsOf: inserted, at: 20)
        assertLineGeometryAtMatchesOracle(tree, array, "after insertLines")

        tree.removeLines(at: 5, count: 4); array.removeSubrange(5..<9)
        assertLineGeometryAtMatchesOracle(tree, array, "after removeLines")
    }
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter BalancedTreeLineMetricsTests`
Expected: PASS — `lineGeometryAt` over the balanced tree equals `lineGeometryAt` over the prefix-sum oracle across the scroll sweep, initially and after each mutation.

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
git commit -m "test: prove balanced-tree lineGeometryAt equals prefix-sum oracle"
```

---

## Task 5: `--line-geometry-query` benchmark mode + local gate

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (mode enum, `outputName`, `parse`, `usage`)
- Modify: `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift` (exhaustive switch, ~line 126)
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift` (dispatch, ~line 16)
- Create: `Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.lineGeometryAt`, `LineMetricsSource`, `UniformLineMetrics`, `BalancedTreeLineMetrics`, and the benchmark helpers `BenchmarkOperationResult`, `BenchmarkSummary`, `formatSummary`, `percentile`, `nanoseconds`, `deterministicScrollOffset`, `variableHeights`.
- Produces: `BenchmarkMode.lineGeometryQuery` (`outputName == "line_geometry_query"`); `runLineGeometryQueryBenchmarks(enforceGate:) -> Bool`.

- [ ] **Step 1: Add the mode case + `outputName`**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, add `case lineGeometryQuery` to the `BenchmarkMode` enum (after `case lineQuery`):

```swift
    case lineQuery
    case lineGeometryQuery
    case memoryShape
```

and add to the `outputName` switch (after the `.lineQuery` arm):

```swift
        case .lineQuery:
            return "line_query"
        case .lineGeometryQuery:
            return "line_geometry_query"
        case .memoryShape:
            return "memory_shape"
```

- [ ] **Step 2: Add the `--line-geometry-query` parse arm + usage**

In the same file, in `parse`, after the `--line-query` case:

```swift
            case "--line-geometry-query":
                if mode != .pipeline {
                    return .failure("--line-geometry-query cannot be combined with another mode")
                }
                mode = .lineGeometryQuery
```

In the `usage` string, extend the `Usage:` line to include `[--line-geometry-query]` after `[--line-query]`, and add an option line after the `--line-query` description:

```
      --line-geometry-query Run y->line+box+fraction geometry query benchmark. Combine with --gate to enforce budgets.
```

(No change to the gate-rejection check: `--gate` stays valid with `.lineGeometryQuery` because the rejection set is only `.rangeOnly` / `.memoryShape` / `.memoryObservation`.)

- [ ] **Step 3: Add the exhaustive-switch case in `SyntheticBenchmarks.swift`**

In `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`, in the `switch mode` near line 126, after the `.lineQuery` arm:

```swift
            case .lineQuery:
                preconditionFailure("line query mode uses runLineQueryScenario")
            case .lineGeometryQuery:
                preconditionFailure("line geometry query mode uses runLineGeometryQueryScenario")
            case .memoryShape:
```

- [ ] **Step 4: Add the dispatch arm in `BenchmarkProgram.swift`**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, in `runBenchmarks`, after the `.lineQuery` arm:

```swift
    case .lineQuery:
        return runLineQueryBenchmarks(enforceGate: options.enforceGate)
    case .lineGeometryQuery:
        return runLineGeometryQueryBenchmarks(enforceGate: options.enforceGate)
    case .memoryShape:
```

- [ ] **Step 5: Create the benchmark file**

Create `Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift`:

```swift
import TextEngineCore
import TextEngineReferenceProviders

struct LineGeometryQueryScenario {
    let name: String
    let providerName: String
    let lineCount: Int
    let useBalancedTree: Bool
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// Budgets mirror the --line-query local gate: lineGeometryAt is lineAt plus a
// constant two offset(ofLine:) probes, so it stays well within the same headroom.
// Uniform uses the O(log N) fallback; balanced-tree scenarios exercise the native
// O(log N) index descent plus the two generic O(log N) geometry probes.
func lineGeometryQueryScenarios() -> [LineGeometryQueryScenario] {
    [
        LineGeometryQueryScenario(name: "uniform_1k", providerName: "uniform",
                                  lineCount: 1_000, useBalancedTree: false,
                                  p95BudgetNanoseconds: 30_000, p99BudgetNanoseconds: 60_000),
        LineGeometryQueryScenario(name: "uniform_100k", providerName: "uniform",
                                  lineCount: 100_000, useBalancedTree: false,
                                  p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000),
        LineGeometryQueryScenario(name: "uniform_1m", providerName: "uniform",
                                  lineCount: 1_000_000, useBalancedTree: false,
                                  p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        LineGeometryQueryScenario(name: "balanced_tree_100k", providerName: "balanced_tree",
                                  lineCount: 100_000, useBalancedTree: true,
                                  p95BudgetNanoseconds: 300_000, p99BudgetNanoseconds: 600_000),
        LineGeometryQueryScenario(name: "balanced_tree_1m", providerName: "balanced_tree",
                                  lineCount: 1_000_000, useBalancedTree: true,
                                  p95BudgetNanoseconds: 600_000, p99BudgetNanoseconds: 1_200_000),
    ]
}

@inline(never)
func runLineGeometryQueryOperation<Metrics: LineMetricsSource>(
    y: Double,
    metrics: Metrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.lineGeometryAt(y: y, metrics: metrics) {
    case let .geometry(location):
        var checksum = location.geometry.lineIndex
        switch location.clamp {
        case .inRange: checksum &+= 1
        case .clampedToTop: checksum &+= 2
        case .clampedToBottom: checksum &+= 3
        }
        checksum &+= Int(location.fractionInLine * 1_000_000.0)
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runLineGeometryQueryScenarioCore<Metrics: LineMetricsSource>(
    _ scenario: LineGeometryQueryScenario,
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
            let result = runLineGeometryQueryOperation(y: y, metrics: metrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .lineGeometryQuery,
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
func runLineGeometryQueryScenario(
    _ scenario: LineGeometryQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useBalancedTree {
        let metrics = BalancedTreeLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
        return runLineGeometryQueryScenarioCore(scenario, metrics: metrics,
                                                iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let metrics = UniformLineMetrics(lineCount: scenario.lineCount, lineHeight: 16.0)
        return runLineGeometryQueryScenarioCore(scenario, metrics: metrics,
                                                iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runLineGeometryQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in lineGeometryQueryScenarios() {
        let summary = runLineGeometryQueryScenario(
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

- [ ] **Step 6: Build the benchmarks target**

Run: `swift build -c release`
Expected: builds cleanly (all four exhaustive `BenchmarkMode` switches now cover `.lineGeometryQuery`).

- [ ] **Step 7: Run the new gate and confirm pass**

Run: `swift run -c release ViewportBenchmarks -- --line-geometry-query --gate`
Expected: five scenarios printed, each `gate=pass`, exit 0. Note the printed p95/p99 per scenario for the verification record. If any scenario reports `gate=fail`, raise only that scenario's `p95BudgetNanoseconds`/`p99BudgetNanoseconds` to ~3× the observed value (matching the headroom the other local gates use), rebuild, and re-run until all pass.

- [ ] **Step 8: Confirm the mode-exclusivity and gate-validity rules**

Run: `swift run -c release ViewportBenchmarks -- --line-geometry-query --line-query`
Expected: `error=--line-query cannot be combined with another mode` (or the symmetric message), exit 1.

Run: `swift run -c release ViewportBenchmarks -- --memory-shape --gate`
Expected: `error=--gate cannot be combined with memory_shape mode`, exit 1 (unchanged behavior — sanity that the rejection set is intact).

- [ ] **Step 9: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/SyntheticBenchmarks.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift
git commit -m "feat: add --line-geometry-query benchmark mode and local gate"
```

---

## Task 6: Documentation — `AGENTS.md`

**Files:**
- Modify: `AGENTS.md` (architecture paragraph, Commands block, Benchmark flags paragraph)

- [ ] **Step 1: Extend the architecture paragraph**

In `AGENTS.md`, find the sentence ending the architecture paragraph:

```
`ViewportVirtualizer.lineAt(y:metrics:)` is the inverse query - y -> line - over
the same `LineMetricsSource`, O(1) core memory, using the shared
`lineIndex(containingOffset:)` provider-native hook when available and the
generic O(log N) binary-search fallback otherwise; out-of-range `y` clamps with
a `LineLocation.clamp` flag.
```

Append immediately after it:

```
`ViewportVirtualizer.lineGeometryAt(y:metrics:)` is the geometry-bearing companion:
it composes over `lineAt`, returning the located line's `LineGeometry` box (top y +
height) plus the within-line `fractionInLine` and the same clamp flag, adding only a
constant number of `offset(ofLine:)` probes (O(1) core memory), so its per-provider
cost class equals `lineAt`'s.
```

- [ ] **Step 2: Add the Commands line**

In the `## Commands` code block, after:

```bash
swift run -c release ViewportBenchmarks -- --line-query --gate   # y->line position-query local gate
```

add:

```bash
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate   # y->line+box+fraction local gate
```

- [ ] **Step 3: Update the benchmark-flags paragraph**

In the `Benchmark flags:` paragraph, add `--line-geometry-query` to the flag list (after `--line-query`,) and to the `--gate` is **valid with** list (after `--line-query`). The result reads:

```
Benchmark flags: `--range-only`, `--realistic-provider`, `--variable-height`,
`--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--memory-shape`, `--memory-observation`, `--gate`. Only one mode flag at a time.
`--gate` is valid with the default pipeline, `--realistic-provider`,
`--variable-height`, `--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, and `--line-geometry-query` modes; it
is **rejected** with `--range-only`, `--memory-shape`, `--memory-observation`.
```

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document lineGeometryAt and --line-geometry-query gate"
```

---

## Task 7: Verification record

**Files:**
- Create: `docs/superpowers/verification/2026-06-29-geometry-bearing-vertical-query.md`

Run each command, capture the real output, and record it (commands + outputs) in the verification doc. Do not assert results you did not run.

- [ ] **Step 1: Host tests + build**

Run: `swift test`
Expected: all tests pass, 0 failures; the test count is higher than the Slice 30 baseline of 140 by the number of new tests added across Tasks 1-4 (plus the expected empty Swift Testing harness line `0 tests in 0 suites`). Record the exact total.

Run: `swift build -c release`
Expected: clean build.

- [ ] **Step 2: New gate + all existing gates (must stay green and checksum-stable)**

Run and record p95/p99 + checksums for each:

```bash
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift run -c release ViewportBenchmarks -- --line-query --gate
swift run -c release ViewportBenchmarks -- --memory-shape
```
Expected: every `--gate` run reports all scenarios `gate=pass`; `--memory-shape` reports `invariant=pass`. The existing gates' checksums must be **byte-identical** to the Slice 30 record (this slice touches no shared search or provider path) — record them and confirm no movement.

- [ ] **Step 3: Foundation-free scans**

```bash
rg -n "Foundation" Sources/TextEngineCore
rg -n "Foundation" Sources/TextEngineReferenceProviders
```
Expected: no matches (exit 1) for both.

- [ ] **Step 4: Cross-target self-test + compile (public-API change)**

```bash
./.github/scripts/cross-target-compile.sh --self-test
./.github/scripts/cross-target-compile.sh
```
Expected: `self_test=pass`; iOS device + simulator compile blocking-green for `TextEngineCore` and `TextEngineReferenceProviders` (`blocking_failures=0 exit=0`); WASM/embedded-WASM observational (skip recorded if no matching SDK).

- [ ] **Step 5: Write and commit the verification record**

Create `docs/superpowers/verification/2026-06-29-geometry-bearing-vertical-query.md` with the recorded commands and outputs (local section now; leave a `Pending` anchor for the hosted PR + post-merge push runs, to be filled by the post-merge follow-up per the project's verification convention).

```bash
git add docs/superpowers/verification/2026-06-29-geometry-bearing-vertical-query.md
git commit -m "docs: record geometry-bearing vertical query verification"
```

- [ ] **Step 6: Open the slice PR**

Push `slice-31-geometry-bearing-vertical-query` and open one PR titled "Slice 31: geometry-bearing vertical query". After the hosted run is green at step level, record the PR-head + post-merge push run IDs in the verification doc (post-merge follow-up), per AGENTS.md.

---

## Self-Review

**Spec coverage:**
- New public method + `LineGeometryQuery`/`LineGeometryLocation` reusing `LineGeometry` + `LineLocation.Clamp` (spec Decision 1) → Task 1.
- Composed over `lineAt`, parity by construction (Decision 2) → Task 1 (method) + Task 2 (parity test).
- Clamp/fraction contract `0.0`/`(y-top)/height`/`1.0` (Decision 3) → Task 1 tests + Task 2 oracle.
- O(log N)/O(1) cost; constant two extra probes; per-path counts (Decision 4) → Task 3.
- Native-hook dispatch + order (P3) → Task 3.
- Structural uniform oracle (Testing Strategy) → Task 2.
- Reference-provider balanced-tree equivalence + post-mutation (Testing Strategy) → Task 4.
- `--line-geometry-query` mode + local gate, gate-valid set, mode exclusivity (Decision 5 / Benchmark) → Task 5.
- Documentation Updates: `LineMetricsSource` precondition (Task 1 step 6) + `AGENTS.md` (Task 6).
- No CI workflow change (Decision 5) → no workflow task; Verification confirms existing gates green/stable (Task 7).
- Verification record (Verification) → Task 7.

**Placeholder scan:** No TBD/TODO; every code step shows full code; budgets are concrete with a documented adjust-on-fail rule (Task 5 step 7).

**Type consistency:** `lineGeometryAt`, `LineGeometryQuery.geometry/.empty/.failure`, `LineGeometryLocation(geometry:fractionInLine:clamp:)`, `LineGeometry(lineIndex:y:height:)`, `LineLocation.Clamp`, and `BenchmarkMode.lineGeometryQuery`/`outputName "line_geometry_query"`/`runLineGeometryQueryBenchmarks` are used identically across all tasks.
