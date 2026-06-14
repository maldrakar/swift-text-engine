# Variable-Height Mutation / Indexed Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a mutable, indexed reference `LineMetricsSource` (`FenwickLineMetrics`) whose single-line height change is an O(log N) update, proving cheap re-layout while `TextEngineCore` stays stateless and unchanged.

**Architecture:** Extract reference providers into a new Foundation-free `TextEngineReferenceProviders` library so they are both unit-testable and reusable by benchmarks; add `FenwickLineMetrics` (Binary Indexed Tree) there; prove correctness, the O(log N) update, and correct re-layout composition with the unchanged generic core; add a `--variable-height-mutation` benchmark with a local gate and an observation-only CI step.

**Tech Stack:** Swift 6.0 (SwiftPM), XCTest, no Foundation in core/providers, Embedded-friendly (arrays + `Int`/`Double`).

**Spec:** `docs/superpowers/specs/2026-06-14-variable-height-mutation-design.md`

---

## File Structure

- `Package.swift` — add `TextEngineReferenceProviders` target + product, new test target, and the `ViewportBenchmarks` dependency edge.
- `Sources/TextEngineReferenceProviders/PrefixSumLineMetrics.swift` — moved from benchmarks, made `public`.
- `Sources/TextEngineReferenceProviders/FenwickLineMetrics.swift` — new BIT provider.
- `Sources/ViewportBenchmarks/VariableHeightBenchmark.swift` — drop local `PrefixSumLineMetrics`, import it from the library.
- `Sources/ViewportBenchmarks/VariableHeightMutationBenchmark.swift` — new benchmark mode.
- `Sources/ViewportBenchmarks/BenchmarkModels.swift` — add `.variableHeightMutation` mode.
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift` — parse `--variable-height-mutation`, usage text.
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift` — dispatch the new mode.
- `Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift` — all provider unit tests.
- `.github/workflows/swift-ci.yml` — observation-only CI step.
- `AGENTS.md` — command list / flag matrix update.
- `docs/superpowers/verification/2026-06-14-variable-height-mutation.md` — verification record.

---

## Task 1: Extract reference providers into a library target

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TextEngineReferenceProviders/PrefixSumLineMetrics.swift`
- Modify: `Sources/ViewportBenchmarks/VariableHeightBenchmark.swift:1-20`

- [ ] **Step 1: Add the library target and product to `Package.swift`**

Replace the entire file with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTextEngine",
    products: [
        .library(name: "TextEngineCore", targets: ["TextEngineCore"]),
        .library(name: "TextEngineReferenceProviders", targets: ["TextEngineReferenceProviders"]),
        .executable(name: "ViewportBenchmarks", targets: ["ViewportBenchmarks"])
    ],
    targets: [
        .target(name: "TextEngineCore"),
        .target(
            name: "TextEngineReferenceProviders",
            dependencies: ["TextEngineCore"]
        ),
        .executableTarget(
            name: "ViewportBenchmarks",
            dependencies: ["TextEngineCore", "TextEngineReferenceProviders"]
        ),
        .testTarget(
            name: "TextEngineCoreTests",
            dependencies: ["TextEngineCore"]
        )
    ]
)
```

- [ ] **Step 2: Create the moved `PrefixSumLineMetrics` (now public) in the library**

Create `Sources/TextEngineReferenceProviders/PrefixSumLineMetrics.swift`:

```swift
import TextEngineCore

/// Reference static provider: cumulative offsets precomputed as a prefix-sum
/// array. `offset(ofLine:)` is O(1), but any height change requires an O(N)
/// rebuild. Used as the correctness oracle for `FenwickLineMetrics` and by the
/// variable-height benchmark.
public struct PrefixSumLineMetrics: LineMetricsSource {
    public let prefix: [Double]

    public init(heights: [Double]) {
        var sums: [Double] = [0.0]
        sums.reserveCapacity(heights.count + 1)
        var running = 0.0
        for height in heights {
            running += height
            sums.append(running)
        }
        self.prefix = sums
    }

    public var lineCount: Int { prefix.count - 1 }

    public func offset(ofLine index: Int) -> Double { prefix[index] }
}
```

- [ ] **Step 3: Remove the local copy from the benchmark and import the library**

In `Sources/ViewportBenchmarks/VariableHeightBenchmark.swift`, delete the local
`PrefixSumLineMetrics` struct (current lines 3-20) and add the import. The top of
the file changes from:

```swift
import TextEngineCore

struct PrefixSumLineMetrics: LineMetricsSource {
    let prefix: [Double]

    init(heights: [Double]) {
        var sums: [Double] = [0.0]
        sums.reserveCapacity(heights.count + 1)
        var running = 0.0
        for height in heights {
            running += height
            sums.append(running)
        }
        self.prefix = sums
    }

    var lineCount: Int { prefix.count - 1 }

    func offset(ofLine index: Int) -> Double { prefix[index] }
}

struct VariableHeightScenario {
```

to:

```swift
import TextEngineCore
import TextEngineReferenceProviders

struct VariableHeightScenario {
```

- [ ] **Step 4: Verify build, existing tests, and the variable-height gate still pass**

Run: `swift build`
Expected: `Build complete!`

Run: `swift test`
Expected: `Executed 67 tests, with 0 failures` (plus the empty Swift Testing line).

Run: `swift run -c release ViewportBenchmarks -- --variable-height --gate`
Expected: three `mode=variable_height provider=prefix_sum ... gate=pass` rows.

- [ ] **Step 5: Confirm the library is Foundation-free**

Run: `rg -n "Foundation" Sources/TextEngineReferenceProviders`
Expected: no output (exit code 1).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/TextEngineReferenceProviders/PrefixSumLineMetrics.swift Sources/ViewportBenchmarks/VariableHeightBenchmark.swift
git commit -m "refactor: extract reference providers into a library target

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `FenwickLineMetrics` build + O(log N) query (TDD)

**Files:**
- Modify: `Package.swift`
- Create: `Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift`
- Create: `Sources/TextEngineReferenceProviders/FenwickLineMetrics.swift`

- [ ] **Step 1: Add the new test target to `Package.swift`**

Append a fourth entry to the `targets:` array (after the `TextEngineCoreTests`
target), so the array ends:

```swift
        .testTarget(
            name: "TextEngineCoreTests",
            dependencies: ["TextEngineCore"]
        ),
        .testTarget(
            name: "TextEngineReferenceProvidersTests",
            dependencies: ["TextEngineReferenceProviders", "TextEngineCore"]
        )
```

(The test target depends on **both** libraries: `TextEngineReferenceProviders`
for the providers under test, and `TextEngineCore` for the re-layout types used
in Task 7. SwiftPM requires a direct dependency to `import` a module.)

- [ ] **Step 2: Write the failing build-correctness test**

Create `Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift`:

```swift
import XCTest
import TextEngineReferenceProviders

final class FenwickLineMetricsTests: XCTestCase {
    // Deterministic, integer-valued, strictly-positive non-uniform heights in
    // {14,16,20,32}. Integer values with totals < 2^53 make Fenwick prefix sums
    // bit-exactly equal to the left-to-right prefix-sum oracle.
    private func sampleHeights(_ lineCount: Int) -> [Double] {
        var heights: [Double] = []
        heights.reserveCapacity(lineCount)
        for index in 0..<lineCount {
            let bucket = ((index &* 31) &+ 7) % 4
            switch bucket {
            case 0: heights.append(14.0)
            case 1: heights.append(16.0)
            case 2: heights.append(20.0)
            default: heights.append(32.0)
            }
        }
        return heights
    }

    func testOffsetMatchesPrefixSumOracleOnBuild() {
        let heights = sampleHeights(1_000)
        let fenwick = FenwickLineMetrics(heights: heights)
        let oracle = PrefixSumLineMetrics(heights: heights)

        XCTAssertEqual(fenwick.lineCount, oracle.lineCount)
        for i in 0...heights.count {
            XCTAssertEqual(
                fenwick.offset(ofLine: i),
                oracle.offset(ofLine: i),
                "offset mismatch at \(i)"
            )
        }
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter FenwickLineMetricsTests`
Expected: FAIL — compile error "cannot find 'FenwickLineMetrics' in scope".

- [ ] **Step 4: Implement `FenwickLineMetrics` build + query**

Create `Sources/TextEngineReferenceProviders/FenwickLineMetrics.swift`:

```swift
import TextEngineCore

/// Mutable, indexed metrics provider backed by a Binary Indexed Tree (Fenwick
/// tree) over per-line heights. `offset(ofLine:)` is O(log N); a single-line
/// height change (`setHeight`) is a localized O(log N) update, versus the O(N)
/// rebuild a prefix-sum array needs. Provider-owned memory is O(N) — the line
/// metrics are the document, living outside the stateless core.
public struct FenwickLineMetrics: LineMetricsSource {
    private var heights: [Double]   // per-line heights; count == lineCount
    private var tree: [Double]      // 1-based BIT; count == lineCount + 1

    /// Number of BIT cells written by the most recent `setHeight` (the set-bit
    /// step count of the update walk, <= floor(log2 N) + 1). Deterministic
    /// evidence for the O(log N) update claim.
    public private(set) var lastUpdateWriteCount: Int

    public init(heights: [Double]) {
        for height in heights {
            precondition(
                height.isFinite && height > 0.0,
                "FenwickLineMetrics requires finite, positive heights"
            )
        }
        let n = heights.count
        var tree = [Double](repeating: 0.0, count: n + 1)
        // O(N) Fenwick construction: seed each cell, then push it into its parent.
        var i = 1
        while i <= n {
            tree[i] += heights[i - 1]
            let parent = i + (i & (-i))
            if parent <= n {
                tree[parent] += tree[i]
            }
            i += 1
        }
        self.heights = heights
        self.tree = tree
        self.lastUpdateWriteCount = 0
    }

    public var lineCount: Int { heights.count }

    // offset(ofLine: index) = sum(heights[0..<index]); reads one cell per set bit
    // of `index`, i.e. popcount(index) <= floor(log2 N) + 1 cells.
    public func offset(ofLine index: Int) -> Double {
        var sum = 0.0
        var i = index
        while i > 0 {
            sum += tree[i]
            i -= i & (-i)
        }
        return sum
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter FenwickLineMetricsTests`
Expected: PASS — `Executed 1 test, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/TextEngineReferenceProviders/FenwickLineMetrics.swift Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift
git commit -m "feat: add FenwickLineMetrics build and O(log N) offset query

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `setHeight` O(log N) update + mutation correctness (TDD)

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift`
- Modify: `Sources/TextEngineReferenceProviders/FenwickLineMetrics.swift`

- [ ] **Step 1: Write the failing mutation-correctness test**

Add this method to `FenwickLineMetricsTests`:

```swift
    func testMutationKeepsOffsetsEqualToFreshOracle() {
        let heights = sampleHeights(500)
        var fenwick = FenwickLineMetrics(heights: heights)
        var mutated = heights

        // First line, last line, an interior line, then the same interior line
        // again (repeated edit). All values integer-valued and positive.
        let edits: [(index: Int, height: Double)] = [
            (0, 40.0), (heights.count - 1, 12.0), (250, 28.0), (250, 50.0)
        ]

        for edit in edits {
            fenwick.setHeight(ofLine: edit.index, to: edit.height)
            mutated[edit.index] = edit.height
            let oracle = PrefixSumLineMetrics(heights: mutated)
            for i in 0...heights.count {
                XCTAssertEqual(
                    fenwick.offset(ofLine: i),
                    oracle.offset(ofLine: i),
                    "mismatch at \(i) after editing line \(edit.index)"
                )
            }
        }
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FenwickLineMetricsTests/testMutationKeepsOffsetsEqualToFreshOracle`
Expected: FAIL — compile error "value of type 'FenwickLineMetrics' has no member 'setHeight'".

- [ ] **Step 3: Implement `setHeight`**

Add this method to `FenwickLineMetrics` (after `offset(ofLine:)`):

```swift
    // Sets line `index` to `newHeight`. delta = newHeight - heights[index] is
    // computed in O(1) from the heights array; one BIT point-update walks
    // `i += i & (-i)` in O(log N). Returns the number of cells written.
    @discardableResult
    public mutating func setHeight(ofLine index: Int, to newHeight: Double) -> Int {
        precondition(
            index >= 0 && index < heights.count,
            "FenwickLineMetrics.setHeight index out of range"
        )
        precondition(
            newHeight.isFinite && newHeight > 0.0,
            "FenwickLineMetrics.setHeight requires a finite, positive height"
        )
        let delta = newHeight - heights[index]
        heights[index] = newHeight

        var writes = 0
        var i = index + 1
        let n = heights.count
        while i <= n {
            tree[i] += delta
            writes += 1
            i += i & (-i)
        }
        lastUpdateWriteCount = writes
        return writes
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter FenwickLineMetricsTests/testMutationKeepsOffsetsEqualToFreshOracle`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextEngineReferenceProviders/FenwickLineMetrics.swift Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift
git commit -m "feat: add FenwickLineMetrics O(log N) setHeight update

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Strictly-increasing invariant after mutation (TDD guard)

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift`

- [ ] **Step 1: Write the invariant test**

Add this method to `FenwickLineMetricsTests`:

```swift
    func testOffsetsStrictlyIncreasingAfterMutation() {
        let heights = sampleHeights(300)
        var fenwick = FenwickLineMetrics(heights: heights)
        fenwick.setHeight(ofLine: 0, to: 64.0)
        fenwick.setHeight(ofLine: 299, to: 2.0)
        fenwick.setHeight(ofLine: 150, to: 5.0)

        for i in 0..<fenwick.lineCount {
            XCTAssertLessThan(
                fenwick.offset(ofLine: i),
                fenwick.offset(ofLine: i + 1),
                "offsets not strictly increasing at line \(i)"
            )
        }
    }
```

- [ ] **Step 2: Run the test (guard test — should pass with current implementation)**

Run: `swift test --filter FenwickLineMetricsTests/testOffsetsStrictlyIncreasingAfterMutation`
Expected: PASS. (This pins the contract; positive heights keep offsets strictly increasing through mutation.)

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift
git commit -m "test: pin strictly-increasing offsets through mutation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: O(log N) update operation-count (deterministic)

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift`

- [ ] **Step 1: Add a `floorLog2` helper and the operation-count tests**

Add the helper (inside the class, near `sampleHeights`):

```swift
    // floor(log2(value)) for value >= 1.
    private func floorLog2(_ value: Int) -> Int {
        precondition(value >= 1)
        return Int.bitWidth - 1 - value.leadingZeroBitCount
    }
```

Add the two tests:

```swift
    func testUpdateWriteCountIsLogarithmicAcrossSizes() {
        // Updating line 0 (BIT position 1) writes to positions 1,2,4,...,<=N,
        // i.e. exactly floor(log2 N) + 1 cells. A 1000x size jump adds ~10 writes,
        // not 1000x — the localized O(log N) update proof.
        let cases: [(n: Int, expected: Int)] = [
            (1_000, 10), (100_000, 17), (1_000_000, 20)
        ]
        for testCase in cases {
            var fenwick = FenwickLineMetrics(heights: sampleHeights(testCase.n))
            let writes = fenwick.setHeight(ofLine: 0, to: 17.0)
            XCTAssertEqual(writes, testCase.expected, "n=\(testCase.n)")
            XCTAssertEqual(writes, floorLog2(testCase.n) + 1, "n=\(testCase.n)")
            XCTAssertEqual(fenwick.lastUpdateWriteCount, testCase.expected, "n=\(testCase.n)")
        }
    }

    func testUpdateWriteCountExactForKnownSmallCases() {
        var fenwick = FenwickLineMetrics(heights: sampleHeights(8))
        // line 0 -> BIT position 1 -> writes 1,2,4,8
        XCTAssertEqual(fenwick.setHeight(ofLine: 0, to: 10.0), 4)
        // line 7 -> BIT position 8 -> writes 8 only
        XCTAssertEqual(fenwick.setHeight(ofLine: 7, to: 10.0), 1)
    }
```

- [ ] **Step 2: Run the tests to verify they pass**

Run: `swift test --filter FenwickLineMetricsTests/testUpdateWriteCountIsLogarithmicAcrossSizes`
Expected: PASS.

Run: `swift test --filter FenwickLineMetricsTests/testUpdateWriteCountExactForKnownSmallCases`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift
git commit -m "test: pin logarithmic FenwickLineMetrics update write counts

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: O(log N) prefix-query walk bound

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift`

- [ ] **Step 1: Write the query-bound test**

Add this method to `FenwickLineMetricsTests`:

```swift
    func testPrefixQueryWalkBoundIsLogarithmic() {
        // offset(ofLine: index) reads exactly popcount(index) BIT cells (one per
        // set bit; see FenwickLineMetrics.offset). Over the index domain
        // 0...lineCount that never exceeds floor(log2 N) + 1, including the
        // max-popcount (all-ones) index. We also confirm those long-walk indices
        // produce correct offsets.
        for n in [1_000, 100_000, 1_000_000] {
            let bound = floorLog2(n) + 1
            let heights = sampleHeights(n)
            let fenwick = FenwickLineMetrics(heights: heights)
            let oracle = PrefixSumLineMetrics(heights: heights)
            let allOnes = (1 << floorLog2(n)) - 1   // largest 2^k - 1 <= n

            for index in [0, 1, n / 2, n - 1, n, allOnes] {
                XCTAssertLessThanOrEqual(index.nonzeroBitCount, bound, "index=\(index) n=\(n)")
                XCTAssertEqual(
                    fenwick.offset(ofLine: index),
                    oracle.offset(ofLine: index),
                    "offset mismatch at long-walk index \(index) for n=\(n)"
                )
            }
        }
    }
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `swift test --filter FenwickLineMetricsTests/testPrefixQueryWalkBoundIsLogarithmic`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift
git commit -m "test: bound FenwickLineMetrics prefix-query walk to O(log N)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Re-layout composition with the stateless core (TDD)

**Files:**
- Modify: `Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift`

- [ ] **Step 1: Add the `TextEngineCore` import and counting wrapper**

At the top of the test file, add the core import below the existing imports:

```swift
import XCTest
import TextEngineReferenceProviders
import TextEngineCore
```

Add these helper types **above** `final class FenwickLineMetricsTests`:

```swift
private final class QueryCounter {
    var count = 0
}

private struct CountingMetrics<Base: LineMetricsSource>: LineMetricsSource {
    let base: Base
    let counter: QueryCounter

    var lineCount: Int { base.lineCount }

    func offset(ofLine index: Int) -> Double {
        counter.count += 1
        return base.offset(ofLine: index)
    }
}
```

- [ ] **Step 2: Write the re-layout composition tests**

Add a `ceilLog2` helper and the tests to `FenwickLineMetricsTests`:

```swift
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

    private func expectSuccess(
        _ computation: ViewportComputation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> VirtualRange {
        switch computation {
        case let .success(range):
            return range
        case let .failure(error):
            XCTFail("expected success, got \(error)", file: file, line: line)
            return VirtualRange(
                visibleStart: 0, visibleEndExclusive: 0,
                bufferStart: 0, bufferEndExclusive: 0,
                isAtTop: true, isAtBottom: true
            )
        }
    }

    func testReLayoutAfterMutationMatchesFreshOracle() {
        let heights = sampleHeights(10_000)
        var fenwick = FenwickLineMetrics(heights: heights)
        var mutated = heights
        let editIndex = 4_321
        let newHeight = 48.0
        fenwick.setHeight(ofLine: editIndex, to: newHeight)
        mutated[editIndex] = newHeight
        let oracle = PrefixSumLineMetrics(heights: mutated)

        let input = VariableViewportInput(
            scrollOffsetY: oracle.offset(ofLine: editIndex) - 100.0,
            viewportHeight: 80.0 * 16.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )

        let fenwickRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: fenwick))
        let oracleRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: oracle))
        XCTAssertEqual(fenwickRange, oracleRange)

        var fenwickCursor = ViewportVirtualizer.geometry(for: fenwickRange, metrics: fenwick)
        var oracleCursor = ViewportVirtualizer.geometry(for: oracleRange, metrics: oracle)
        var emitted = 0
        while true {
            let fenwickLine = fenwickCursor.next()
            let oracleLine = oracleCursor.next()
            XCTAssertEqual(fenwickLine, oracleLine, "geometry mismatch at emitted index \(emitted)")
            if fenwickLine == nil && oracleLine == nil { break }
            emitted += 1
            XCTAssertLessThan(emitted, 1_000, "geometry cursor did not terminate")
        }
        XCTAssertGreaterThan(emitted, 0)
    }

    func testReLayoutAfterMutationUsesLogarithmicCoreQueries() {
        let n = 1_000_000
        var fenwick = FenwickLineMetrics(heights: sampleHeights(n))
        fenwick.setHeight(ofLine: n / 3, to: 50.0)

        let counter = QueryCounter()
        let counting = CountingMetrics(base: fenwick, counter: counter)
        let input = VariableViewportInput(
            scrollOffsetY: fenwick.offset(ofLine: n / 2),
            viewportHeight: 80.0 * 16.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )

        _ = expectSuccess(ViewportVirtualizer.compute(input, metrics: counting))

        // Two O(1) contract queries (offset 0 and total height) plus two binary
        // searches over the line count. A linear scan would be hundreds of
        // thousands of queries.
        let expectedMax = 2 + (ceilLog2(n) + 1) * 2
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }
```

- [ ] **Step 3: Run the tests to verify they pass**

Run: `swift test --filter FenwickLineMetricsTests/testReLayoutAfterMutationMatchesFreshOracle`
Expected: PASS.

Run: `swift test --filter FenwickLineMetricsTests/testReLayoutAfterMutationUsesLogarithmicCoreQueries`
Expected: PASS.

- [ ] **Step 4: Run the whole provider suite and confirm the full test count grows**

Run: `swift test`
Expected: `Executed 75 tests, with 0 failures` (67 existing + 8 new), plus the
empty Swift Testing harness line. If the count differs, reconcile before
committing.

- [ ] **Step 5: Commit**

```bash
git add Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift
git commit -m "test: prove cheap correct re-layout after FenwickLineMetrics mutation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: `--variable-height-mutation` benchmark mode + local gate

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkModels.swift:1-25`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- Create: `Sources/ViewportBenchmarks/VariableHeightMutationBenchmark.swift`

- [ ] **Step 1: Add the `.variableHeightMutation` mode**

In `Sources/ViewportBenchmarks/BenchmarkModels.swift`, add the case and its
output name. The `BenchmarkMode` enum becomes:

```swift
enum BenchmarkMode {
    case pipeline
    case rangeOnly
    case realisticProvider
    case variableHeight
    case variableHeightMutation
    case memoryShape
    case memoryObservation

    var outputName: String {
        switch self {
        case .pipeline:
            return "pipeline"
        case .rangeOnly:
            return "range_only"
        case .realisticProvider:
            return "realistic_provider"
        case .variableHeight:
            return "variable_height"
        case .variableHeightMutation:
            return "variable_height_mutation"
        case .memoryShape:
            return "memory_shape"
        case .memoryObservation:
            return "memory_observation"
        }
    }
}
```

- [ ] **Step 2: Parse `--variable-height-mutation` and update usage**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, update the `usage` string
and add the parse case.

Change the usage `Usage:` line and add the option line so usage reads:

```swift
    static let usage = """
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--variable-height] [--variable-height-mutation] [--memory-shape] [--memory-observation] [--help]

    Options:
      --range-only          Run only viewport range recompute benchmark.
      --gate                Enforce p95/p99 budgets for gateable benchmark modes and exit non-zero on failure.
      --realistic-provider  Run large-text provider benchmark. Combine with --gate to enforce calibrated budgets.
      --variable-height     Run variable-height compute+geometry benchmark. Combine with --gate to enforce budgets.
      --variable-height-mutation  Run mutate+recompute benchmark (Fenwick provider). Combine with --gate to enforce budgets.
      --memory-shape        Run deterministic core-owned memory-shape diagnostics.
      --memory-observation  Run host RSS observation diagnostics.
      --help                Print this help.
    """
```

Add this case to the `for argument in arguments` switch, immediately after the
`--variable-height` case:

```swift
            case "--variable-height-mutation":
                if mode != .pipeline {
                    return .failure("--variable-height-mutation cannot be combined with another mode")
                }
                mode = .variableHeightMutation
```

(The existing gate-rejection check `enforceGate && (mode == .rangeOnly || mode ==
.memoryShape || mode == .memoryObservation)` already excludes
`.variableHeightMutation`, so `--gate` stays valid with it — no change needed
there.)

- [ ] **Step 3: Dispatch the new mode**

In `Sources/ViewportBenchmarks/BenchmarkProgram.swift`, add the case to
`runBenchmarks(options:)`:

```swift
    case .variableHeight:
        return runVariableHeightBenchmarks(enforceGate: options.enforceGate)
    case .variableHeightMutation:
        return runVariableHeightMutationBenchmarks(enforceGate: options.enforceGate)
    case .memoryShape:
        return runMemoryShapeDiagnostics()
```

- [ ] **Step 4: Implement the benchmark**

Create `Sources/ViewportBenchmarks/VariableHeightMutationBenchmark.swift`:

```swift
import TextEngineCore
import TextEngineReferenceProviders

// Reuses VariableHeightScenario, variableHeights(lineCount:), and
// deterministicScrollOffset from VariableHeightBenchmark.swift / BenchmarkSupport.swift.
func variableHeightMutationScenarios() -> [VariableHeightScenario] {
    [
        VariableHeightScenario(
            name: "1k_lines_20_visible_overscan_0",
            lineCount: 1_000,
            viewportHeight: 20.0 * 16.0,
            overscanBefore: 0,
            overscanAfter: 0,
            p95BudgetNanoseconds: 100_000,
            p99BudgetNanoseconds: 200_000
        ),
        VariableHeightScenario(
            name: "100k_lines_80_visible_overscan_5",
            lineCount: 100_000,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5,
            p95BudgetNanoseconds: 250_000,
            p99BudgetNanoseconds: 500_000
        ),
        VariableHeightScenario(
            name: "1m_lines_200_visible_overscan_50",
            lineCount: 1_000_000,
            viewportHeight: 200.0 * 16.0,
            overscanBefore: 50,
            overscanAfter: 50,
            p95BudgetNanoseconds: 500_000,
            p99BudgetNanoseconds: 1_000_000
        )
    ]
}

@inline(never)
func runVariableHeightMutationOperation(
    input: VariableViewportInput,
    metrics: FenwickLineMetrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.compute(input, metrics: metrics) {
    case let .success(range):
        var checksum = 0
        checksum &+= range.visibleStart
        checksum &+= range.visibleEndExclusive
        checksum &+= range.bufferStart
        checksum &+= range.bufferEndExclusive

        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        while let geometry = cursor.next() {
            checksum &+= geometry.lineIndex
            checksum &+= Int(geometry.y)
            checksum &+= Int(geometry.height)
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runVariableHeightMutationScenario(
    _ scenario: VariableHeightScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    // One provider, mutated in place across all operations (no per-op rebuild).
    var metrics = FenwickLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
    let initialTotal = metrics.offset(ofLine: metrics.lineCount)
    let maxOffset = initialTotal > scenario.viewportHeight ? initialTotal - scenario.viewportHeight : 0.0
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let lineIndex = sample % scenario.lineCount
            // Toggle by visit count so each visit to a line strictly changes its
            // height (no no-op updates): 18 and 30 are distinct and never appear
            // in the initial {14,16,20,32} set.
            let newHeight = ((sample / scenario.lineCount) & 1) == 0 ? 18.0 : 30.0
            metrics.setHeight(ofLine: lineIndex, to: newHeight)
            checksum &+= metrics.lastUpdateWriteCount

            let offset = deterministicScrollOffset(sample: sample, maxOffset: maxOffset)
            let input = VariableViewportInput(
                scrollOffsetY: offset,
                viewportHeight: scenario.viewportHeight,
                overscanLinesBefore: scenario.overscanBefore,
                overscanLinesAfter: scenario.overscanAfter
            )
            let operationResult = runVariableHeightMutationOperation(input: input, metrics: metrics)
            checksum &+= operationResult.checksum
            failureCount &+= operationResult.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .variableHeightMutation,
        providerName: "fenwick",
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: scenario.lineCount,
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
func runVariableHeightMutationBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in variableHeightMutationScenarios() {
        let summary = runVariableHeightMutationScenario(
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

- [ ] **Step 5: Build, then observe the benchmark without the gate to confirm budget headroom**

Run: `swift build -c release`
Expected: `Build complete!`

Run: `swift run -c release ViewportBenchmarks -- --variable-height-mutation`
Expected: three `mode=variable_height_mutation provider=fenwick ... failures=0`
rows. Read the `p95_ns` / `p99_ns` values: each must sit comfortably (target ≥3×
headroom) below the budgets in `variableHeightMutationScenarios()`
(1k 100000/200000, 100k 250000/500000, 1m 500000/1000000). If any value is within
3× of its budget on this machine, raise that scenario's budget so the gate has
clear headroom, and note the change in the verification record.

- [ ] **Step 6: Run the gate and confirm it passes**

Run: `swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate`
Expected: three `mode=variable_height_mutation provider=fenwick ... gate=pass` rows; process exits 0.

- [ ] **Step 7: Confirm the gate is rejected with non-gateable modes (unchanged behavior holds)**

Run: `swift run -c release ViewportBenchmarks -- --variable-height-mutation --memory-shape`
Expected: `error=--variable-height-mutation cannot be combined with another mode` (exit 1).

- [ ] **Step 8: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkModels.swift Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/VariableHeightMutationBenchmark.swift
git commit -m "feat: add --variable-height-mutation benchmark mode and local gate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: CI observation step + AGENTS.md update

**Files:**
- Modify: `.github/workflows/swift-ci.yml:49-51`
- Modify: `AGENTS.md`

- [ ] **Step 1: Add the observation-only CI step**

In `.github/workflows/swift-ci.yml`, insert a new step immediately after the
`Run variable-height benchmark gate` step (current lines 49-50) and before the
`Run memory shape diagnostic` step:

```yaml
      - name: Run variable-height benchmark gate
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height --gate

      - name: Observe variable-height mutation benchmark
        continue-on-error: true
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation

      - name: Run memory shape diagnostic
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

(This step is observation-only: no `--gate`, `continue-on-error: true`, mirroring
how the variable-height benchmark entered CI in Slice 14. It is a plain
single-line `run:` with no `set -o pipefail`, so it is sh-safe and needs no
`shell: bash`.)

- [ ] **Step 2: Validate the workflow YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/swift-ci.yml'))" && echo yaml_ok`
Expected: `yaml_ok`.

- [ ] **Step 3: Update the AGENTS.md command list and flag matrix**

In `AGENTS.md`, in the Commands section, add a line after the existing
`--variable-height --gate` example:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate   # mutate+recompute local gate
```

And update the "Benchmark flags" paragraph so the flag list and the gate-validity
sentence include the new mode. Change:

```
Benchmark flags: `--range-only`, `--realistic-provider`, `--variable-height`,
`--memory-shape`, `--memory-observation`, `--gate`. Only one mode flag at a time.
`--gate` is valid with the default pipeline, `--realistic-provider`, and
`--variable-height` modes; it is **rejected** with `--range-only`,
`--memory-shape`, `--memory-observation`.
```

to:

```
Benchmark flags: `--range-only`, `--realistic-provider`, `--variable-height`,
`--variable-height-mutation`, `--memory-shape`, `--memory-observation`, `--gate`.
Only one mode flag at a time. `--gate` is valid with the default pipeline,
`--realistic-provider`, `--variable-height`, and `--variable-height-mutation`
modes; it is **rejected** with `--range-only`, `--memory-shape`,
`--memory-observation`.
```

Also, in the CI section's host-job step list, add the mutation observation after
the variable-height gate, so the sequence reads
`... → `--variable-height --gate` (blocking) → `--variable-height-mutation`
(observational) → `--memory-shape` → ...`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/swift-ci.yml AGENTS.md
git commit -m "ci: observe variable-height mutation benchmark after variable-height gate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Full local verification + verification record

**Files:**
- Create: `docs/superpowers/verification/2026-06-14-variable-height-mutation.md`

- [ ] **Step 1: Run the full local verification suite, capturing output**

Run each and capture the actual output:

```bash
swift test
swift build -c release
swift build -c release --target TextEngineReferenceProviders
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
rg -n "Foundation" Sources/TextEngineCore
rg -n "Foundation" Sources/TextEngineReferenceProviders
./.github/scripts/cross-target-compile.sh --self-test
git diff --check
```

Expected: `swift test` reports `Executed 75 tests, with 0 failures`; all builds
`Build complete!`; all three gate modes `gate=pass`; `--memory-shape`
`invariant=pass`; `--memory-observation` `observation=pass`; both `rg` scans
empty (exit 1); `self_test=pass`; `git diff --check` empty.

- [ ] **Step 2: Write the verification record**

Create `docs/superpowers/verification/2026-06-14-variable-height-mutation.md`
with: the date, the exact commands above and their captured outputs (including
the observed mutation benchmark `p95_ns`/`p99_ns` and any budget adjustment from
Task 8 Step 5), the new test count, and a "Hosted Evidence" section to be filled
with the PR run ID and the post-merge push run ID once available (anchor proof on
the post-merge run, per AGENTS.md).

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/verification/2026-06-14-variable-height-mutation.md
git commit -m "docs: record variable-height mutation verification

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 4: Push the branch and open the PR**

```bash
git push -u origin slice-17-variable-height-mutation
gh pr create --title "Slice 17: variable-height mutation / indexed provider" --body "Implements the mutable Fenwick reference provider per docs/superpowers/specs/2026-06-14-variable-height-mutation-design.md. Core unchanged; new TextEngineReferenceProviders library; O(log N) setHeight proven; --variable-height-mutation benchmark observational in CI.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 5: After CI is green, record hosted run IDs**

Watch the PR run, then (after merge) the post-merge push run; append both run IDs
and their step outcomes to the verification record and commit that update. Do not
mark the slice complete until the post-merge push run on `main` is green (the
merged-code anchor).

---

## Notes for the executor

- **Do not modify `Sources/TextEngineCore` or `Tests/TextEngineCoreTests`.** This
  slice proves the *unchanged* core composes with a mutable provider. If you find
  yourself editing the core, stop — that is out of scope.
- **Integer-valued heights only** in equivalence tests (`{14,16,20,32}` and
  integer edits). Fractional heights would break bit-exact equivalence and are
  out of scope.
- **No-op updates are a benchmark error.** The toggle in Task 8 must always
  change the line's height; if you alter it, preserve that property.
- The post-slice review is a separate workflow step after merge, not part of this
  plan.
```
