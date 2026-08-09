# Wrap-Aware Vertical Position Query (`visualRowAt`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `ViewportVirtualizer.visualRowAt(y:layout:)` — the wrap-aware `lineAt` analog over the visual-row axis — advancing brief criterion 3's second query analog.

**Architecture:** The query composes existing machinery and adds no new search. It runs `compute(_:layout:)`'s layout ladder (extracted into one shared helper so parity is by construction), delegates the row-axis search to `lineAt` over `UniformLineMetrics(totalRows, rowHeight)`, then names the located row in both coordinate systems via `logicalLine(containingVisualRow:)` and one `firstVisualRow` probe. Node 1's `VisualRowQuery<Metrics>` is renamed `VisualRowPackingQuery<Metrics>` to free the family-consistent name.

**Tech Stack:** Swift 6.0 tools version, XCTest, SwiftPM. No dependencies. `Sources/TextEngineCore` must stay Foundation-free.

**Spec:** [`docs/superpowers/specs/2026-08-09-wrap-row-query-design.md`](../specs/2026-08-09-wrap-row-query-design.md)

## Global Constraints

Every task's requirements implicitly include these.

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty.
- **Swift Embedded compatible**; **zero third-party dependencies**; compiles for iOS and WASM with no source changes.
- **Core-owned memory must not grow with document size.** This query is O(1) core memory: no arrays, no buffers, no caching.
- **TDD.** Failing test first, minimal implementation, green, commit. One logical step per commit.
- **Conventional commits**: `feat:`, `test:`, `refactor:`, `docs:`, `ci:`.
- **Branch**: `slice-53-wrap-row-query` (already created; the spec and the selection records are already committed on it).
- **D-17 — do NOT use `${PIPESTATUS[0]}` in any command block.** Agent shells here are **zsh**, which does not populate `PIPESTATUS`; the expansion is empty and `[ "" -eq 0 ]` evaluates **true**, inverting a failed assertion into a pass. Use `if ! cmd; then …; fi`, or do not pipe. Every assertion in this plan follows that form.
- **D-2 assertion conventions**: never put a check on the left of a pipe; never `echo "…=$?"` after a status-insensitive command; assert with `[ -z "$(…)" ]` or an explicit `if`/`else` printing both branches.
- Run `swift test` from the repo root: `/Users/aabanschikov/swift-text-engine`.

---

## File Structure

**Core (`Sources/TextEngineCore`)**

| File | Responsibility |
|---|---|
| `WrapPositionQuery.swift` | **new** — `visualRowAt(y:layout:)`. Mirrors `PositionQuery.swift`'s role on the no-wrap axis: one public static query, no types of its own. |
| `ViewportTypes.swift` | +`VisualRowLocation`, +`VisualRowQuery`; node 1's enum renamed to `VisualRowPackingQuery`. All public value types live here already. |
| `WrapViewportVirtualizer.swift` | +`VisualRowLayoutValidation` and `validateVisualRowLayout(_:)`; `compute(_:layout:)` refactored to call it. The layout ladder's single home. |
| `VisualRowCursor.swift` | rename follow-through (return type at `:88`). |

**Tests (`Tests/TextEngineCoreTests`)**

| File | Responsibility |
|---|---|
| `WrapRowQueryTests.swift` | **new** — located-branch mapping: indices, boundary, clamps, empty document. |
| `WrapRowQueryValidationTests.swift` | **new** — one test per error case, precedence, and the ladder-parity matrix against `compute`. |
| `WrapRowQueryEquivalenceTests.swift` | **new** — the ∞ / large-finite-width oracle against `lineAt`. |
| `WrapRowQueryRoundTripTests.swift` | **new** — against `DocumentVisualRowCursor` over a `compute` range. |
| `WrapRowQueryCountTests.swift` | **new** — layout-axis probe bound + the Decision 7 clamp asymmetry. |
| `WrapTestSupport.swift`, `WrapValidationTests.swift` | rename follow-through only. |

> **Deviation from the spec, deliberate:** the spec's Testing Strategy puts the query-count tests in the round-trip file ("Query-count (same file)"). This plan gives them their own `WrapRowQueryCountTests.swift`, following the repo's six existing `*QueryCountTests.swift` files (`LineAtQueryCountTests`, `ColumnAtQueryCountTests`, `LineGeometryAtQueryCountTests`, `ColumnGeometryAtQueryCountTests`, `PointGeometryAtQueryCountTests`, `VariableHeightQueryCountTests`). Same coverage, conventional placement.

**Benchmarks (`Sources/ViewportBenchmarks`)**

| File | Responsibility |
|---|---|
| `WrapRowQueryBenchmark.swift` | **new** — `runWrapRowQueryBenchmarks() -> Bool`, four scenarios, checksum-guarded. |
| `BenchmarkOptions.swift` | +`case wrapRowQuery` in `BenchmarkMode`, `outputName`, `isGateable` (false), `absoluteCeiling` (`.scrollFrame`), usage text, parse case; two stale comments corrected. |
| `BenchmarkProgram.swift` | dispatch case. |
| `SyntheticBenchmarks.swift` | `preconditionFailure` case (the exhaustive switch at `:151`). |

**Tests (`Tests/ViewportBenchmarksTests`)**

| File | Responsibility |
|---|---|
| `WrapRowQueryOptionsTests.swift` | **new** — mode selection, `--gate` rejection, mode-conflict rejection. |
| `WrapRowQueryChecksumTests.swift` | **new** — the checksum folds all three fields under distinct multipliers. |

**Docs**: `AGENTS.md` (3 edits), `docs/superpowers/debt-ledger.md` (2 edits), `docs/superpowers/verification/2026-08-09-wrap-row-query.md` (new).

---

## Task 1: Rename `VisualRowQuery` → `VisualRowPackingQuery`

Frees the family-consistent name for Task 3. Spec Decision 3. Six sites: four compiler-checked, two prose.

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift:242-249`
- Modify: `Sources/TextEngineCore/VisualRowCursor.swift:88`
- Modify: `Tests/TextEngineCoreTests/WrapValidationTests.swift:5`
- Modify: `Tests/TextEngineCoreTests/WrapTestSupport.swift:4,:7`
- Modify: `AGENTS.md:111`

**Interfaces:**
- Consumes: nothing.
- Produces: `VisualRowPackingQuery<Metrics: WrapMetricsSource>` with cases `.rows(VisualRowCursor<Metrics>)` and `.failure(ViewportValidationError)`; `ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:) -> VisualRowPackingQuery<Metrics>`. Frees the identifier `VisualRowQuery` for Task 3.

- [ ] **Step 1: Record the green baseline**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test > /tmp/slice53-baseline.txt 2>&1; then
  echo "BASELINE RED — stop and investigate before renaming"
else
  echo "baseline green"
fi
rg -n "Executed [0-9]+ tests" /tmp/slice53-baseline.txt | tail -2
```

Expected: `baseline green`, and a test count to carry into the verification record.

- [ ] **Step 2: Rename the declaration and update its doc comment**

In `Sources/TextEngineCore/ViewportTypes.swift`, replace the existing declaration block (currently lines 242-249):

```swift
/// Result of `ViewportVirtualizer.visualRows` — how ONE logical line packs into
/// visual rows. Named for what it answers, which keeps the axis-query family
/// consistent (`LineQuery` y→line, `ColumnQuery` x→cell, `PointQuery` (x,y)→both,
/// `VisualRowQuery` y→row): this is a packing result, not a position query.
/// Generic — its `.rows` payload is the provider-holding `VisualRowCursor<Metrics>`,
/// so this is the project's first generic query enum. NOT `Equatable` (the cursor is
/// mutable, non-`Equatable`); tests pattern-match and compare the drained `[VisualRow]`.
public enum VisualRowPackingQuery<Metrics: WrapMetricsSource> {
    case rows(VisualRowCursor<Metrics>)      // one or more rows (a blank line ⇒ one)
    case failure(ViewportValidationError)    // invalid wrapWidth or malformed metrics
}
```

- [ ] **Step 3: Update the three remaining code sites**

`Sources/TextEngineCore/VisualRowCursor.swift:88` — the return type:

```swift
    ) -> VisualRowPackingQuery<Metrics> {
```

`Tests/TextEngineCoreTests/WrapValidationTests.swift:5`:

```swift
    private func failure<M: WrapMetricsSource>(_ query: VisualRowPackingQuery<M>) -> ViewportValidationError? {
```

`Tests/TextEngineCoreTests/WrapTestSupport.swift:4` and `:7` — the doc comment **and** the parameter type (the comment is a `///`, so the compiler will not flag it):

```swift
/// Drain a `VisualRowPackingQuery`'s cursor into an array, failing the test if it is
/// `.failure`. Shared by every packing/equivalence test.
func collectRows<M: WrapMetricsSource>(
    _ query: VisualRowPackingQuery<M>,
```

- [ ] **Step 4: Update `AGENTS.md:111`**

Replace `wrapped in \`VisualRowQuery<Metrics>\`` with `wrapped in \`VisualRowPackingQuery<Metrics>\`` in the soft-wrap layer paragraph. Nothing in the build reads this file — this step is the only thing standing between the rename and stale live architecture prose.

- [ ] **Step 5: Build, test, and assert zero residual references**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build 2>&1 | tail -5; then echo "BUILD FAILED"; fi
if ! swift test > /tmp/slice53-task1.txt 2>&1; then
  echo "TESTS RED"; rg -n "error:|failed" /tmp/slice53-task1.txt | head -20
else
  echo "tests green"
fi
```

Then the residual check. `VisualRowQuery` must have **zero** occurrences in code and live docs at this point — the new type does not exist until Task 3, and `VisualRowQuery` is not a substring of `VisualRowPackingQuery`:

```bash
cd /Users/aabanschikov/swift-text-engine
RESIDUAL="$(rg -n 'VisualRowQuery' Sources/ Tests/ AGENTS.md || true)"
if [ -z "$RESIDUAL" ]; then
  echo "PASS: no residual VisualRowQuery references"
else
  echo "FAIL: residual references remain:"; echo "$RESIDUAL"
fi
```

Expected: `tests green` (same count as the baseline) and `PASS: no residual VisualRowQuery references`.

> Historical `docs/superpowers/specs|plans|reviews|verification` files legitimately keep the old name — they record what shipped at the time and are **not** in the scan. Only `AGENTS.md` is live prose.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/VisualRowCursor.swift \
        Tests/TextEngineCoreTests/WrapValidationTests.swift Tests/TextEngineCoreTests/WrapTestSupport.swift \
        AGENTS.md
git commit -m "refactor: rename VisualRowQuery to VisualRowPackingQuery

Node 1's enum wraps a streaming packer, not a position query, and it is the
only generic non-Equatable member of the query family. Naming it for what it
answers frees VisualRowQuery for the y->row result and keeps the family
consistent with LineQuery / ColumnQuery / PointQuery.

Six sites: four compiler-checked (declaration, VisualRowCursor:88,
WrapValidationTests:5, WrapTestSupport:7) and two prose the compiler cannot
see (WrapTestSupport:4 doc comment, AGENTS.md:111 architecture paragraph)."
```

---

## Task 2: Extract the shared layout ladder

Spec Decision 5. Behaviour-identical refactor; its proof is that all three node-2 wrap-compute suites pass **untouched** (AC4).

**Files:**
- Modify: `Sources/TextEngineCore/WrapViewportVirtualizer.swift` (whole file)

**Interfaces:**
- Consumes: `VisualRowLayoutSource`, `UniformLineMetrics`, `ViewportVirtualizer.emptyRange()` (internal, `ViewportVirtualizer.swift:58`).
- Produces: `enum VisualRowLayoutValidation { case failure(ViewportValidationError); case empty; case rows(Int) }` and `func validateVisualRowLayout<Layout: VisualRowLayoutSource>(_ layout: Layout) -> VisualRowLayoutValidation` — both **internal** (same module), consumed by Task 3.

- [ ] **Step 1: Confirm the three node-2 suites are green before touching anything**

```bash
cd /Users/aabanschikov/swift-text-engine
for suite in WrapComputeTests WrapComputeValidationTests WrapComputeEquivalenceTests; do
  if ! swift test --filter "$suite" > "/tmp/slice53-pre-$suite.txt" 2>&1; then
    echo "PRE-CHECK RED: $suite"
  else
    echo "PRE-CHECK green: $suite"
  fi
done
```

Expected: three `PRE-CHECK green` lines. These three suites are the entire evidence base for this task — the benchmark cannot help (spec Verification explains why).

- [ ] **Step 2: Rewrite `WrapViewportVirtualizer.swift`**

Replace the whole file with:

```swift
/// The layout half of the visual-row validation ladder, shared verbatim by
/// `compute(_:layout:)` and `visualRowAt(y:layout:)` so their accept/reject sets are
/// equal by construction rather than by inspection (spec Decision 5).
///
/// `lineCount < 0` deliberately does NOT live here: it is the first check in BOTH
/// callers, and each caller's *next* check differs (`compute` validates its input,
/// `visualRowAt` validates `y`). Hoisting it would change `compute`'s shipped error
/// precedence, which `WrapComputeValidationTests.testLadderOrderLineCountBeforeRowHeight`
/// pins.
enum VisualRowLayoutValidation {
    case failure(ViewportValidationError)
    case empty                            // lineCount == 0
    case rows(Int)                        // totalRows > 0, totalHeight finite
}

func validateVisualRowLayout<Layout: VisualRowLayoutSource>(
    _ layout: Layout
) -> VisualRowLayoutValidation {
    if !layout.rowHeight.isFinite || layout.rowHeight <= 0.0 { return .failure(.nonPositiveRowHeight) }
    // wrapWidth > 0 accepts +∞ (the equivalence case) and rejects NaN/−∞/≤0. Do NOT
    // write `isFinite && > 0`: +∞ is not finite (the node-1 F1 trap).
    if !(layout.wrapWidth > 0) { return .failure(.nonPositiveWrapWidth) }
    if layout.firstVisualRow(ofLine: 0) != 0 { return .failure(.invalidVisualRowLayout) }
    if layout.lineCount == 0 { return .empty }
    let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
    if totalRows <= 0 { return .failure(.invalidVisualRowLayout) }
    let totalHeight = Double(totalRows) * layout.rowHeight
    if !totalHeight.isFinite { return .failure(.invalidVisualRowLayout) }
    return .rows(totalRows)
}

extension ViewportVirtualizer {
    /// Wrap-aware viewport compute over the visual-row axis. Returns a `VirtualRange`
    /// whose indices are **visual-row indices** (not logical lines). Reuses the proven
    /// variable compute over a uniform row axis. See the spec, Decision 2.
    public static func compute<Layout: VisualRowLayoutSource>(
        _ input: VariableViewportInput, layout: Layout
    ) -> ViewportComputation {
        if layout.lineCount < 0 { return .failure(.negativeLineCount) }
        if !input.scrollOffsetY.isFinite || !input.viewportHeight.isFinite { return .failure(.nonFiniteValue) }
        if input.viewportHeight < 0.0 { return .failure(.negativeViewportHeight) }
        if input.overscanLinesBefore < 0 || input.overscanLinesAfter < 0 { return .failure(.negativeOverscan) }
        switch validateVisualRowLayout(layout) {
        case .failure(let error):
            return .failure(error)
        case .empty:
            return .success(emptyRange())
        case .rows(let totalRows):
            return compute(input, metrics: UniformLineMetrics(lineCount: totalRows, lineHeight: layout.rowHeight))
        }
    }
}
```

- [ ] **Step 3: Verify the three suites still pass, untouched**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! git diff --quiet -- Tests/TextEngineCoreTests/WrapComputeTests.swift \
                          Tests/TextEngineCoreTests/WrapComputeValidationTests.swift \
                          Tests/TextEngineCoreTests/WrapComputeEquivalenceTests.swift; then
  echo "FAIL: a node-2 suite was modified — AC4 requires them UNTOUCHED"
else
  echo "PASS: node-2 suites untouched"
fi
if ! swift test --filter WrapCompute > /tmp/slice53-task2.txt 2>&1; then
  echo "FAIL: wrap-compute suites red"; rg -n "error:|XCTAssert|failed" /tmp/slice53-task2.txt | head -20
else
  echo "PASS: all three wrap-compute suites green"
fi
```

Expected: `PASS: node-2 suites untouched` and `PASS: all three wrap-compute suites green`.

- [ ] **Step 4: Refactor-safety check — prove those suites would catch a broken helper**

Not one of the six numbered falsifiability drills; it exists to make AC4's *widening* (from one node-2 suite to three) evidence rather than reasoning. The spec's stated failure mode is a helper returning a wrong `totalRows`, which perturbs the success path while every error case still resolves.

Temporarily change the final line of `validateVisualRowLayout` to `return .rows(totalRows + 1)`, then:

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapComputeValidationTests > /tmp/slice53-drill0-val.txt 2>&1; then
  echo "EXPECTED: validation suite still GREEN (error cases all resolve)"
else
  echo "UNEXPECTED: validation suite red"
fi
if swift test --filter WrapComputeTests > /tmp/slice53-drill0-succ.txt 2>&1; then
  echo "UNEXPECTED PASS: success-path suite did not catch a wrong totalRows"
else
  echo "EXPECTED RED: success-path suite caught it"
  rg -n "XCTAssertEqual failed|error:" /tmp/slice53-drill0-succ.txt | head -5
fi
```

Expected: validation **green**, success-path **red**. Record both lines — this is what justifies naming three suites in AC4 instead of one. Then revert the mutation and re-run `swift test --filter WrapCompute` to confirm green again.

- [ ] **Step 5: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/TextEngineCore/WrapViewportVirtualizer.swift
git commit -m "refactor: extract the shared visual-row layout ladder

compute(_:layout:)'s six layout checks move into validateVisualRowLayout, in
their existing order, so visualRowAt can share them and the two entry points'
accept/reject sets are equal by construction. lineCount < 0 stays in each
caller: their next checks differ, and hoisting it would change compute's
shipped error precedence.

Behaviour-identical. Proof is all three node-2 wrap-compute suites passing
untouched; a recorded mutation (.rows(totalRows + 1)) reddens the success-path
suite while the validation suite stays green, which is why AC4 names three."
```

---

## Task 3: `VisualRowLocation`, `VisualRowQuery`, and `visualRowAt`

The core deliverable. Test-first on the located branch (mapping); the validation ladder is pinned in Task 4. Spec Decisions 1, 4, 7 and Component Design.

**Files:**
- Modify: `Sources/TextEngineCore/ViewportTypes.swift` (append after `ColumnGeometryLocation`, before `VisualRow`)
- Create: `Sources/TextEngineCore/WrapPositionQuery.swift`
- Create: `Tests/TextEngineCoreTests/WrapRowQueryTests.swift`

**Interfaces:**
- Consumes: `validateVisualRowLayout(_:)` and `VisualRowLayoutValidation` (Task 2); `ViewportVirtualizer.lineAt(y:metrics:) -> LineQuery`; `LineLocation.Clamp`; `UniformLineMetrics(lineCount:lineHeight:)`; `VisualRowLayoutSource.logicalLine(containingVisualRow:)` and `.firstVisualRow(ofLine:)`.
- Produces:
  - `public struct VisualRowLocation: Equatable` with `init(globalRow: Int, logicalLine: Int, rowInLine: Int, clamp: LineLocation.Clamp)` and those four `let` properties.
  - `public enum VisualRowQuery: Equatable { case row(VisualRowLocation); case empty; case failure(ViewportValidationError) }`.
  - `public static func visualRowAt<Layout: VisualRowLayoutSource>(y: Double, layout: Layout) -> VisualRowQuery`.
  - Test helper `layout123()` in `WrapRowQueryTests.swift` — Tasks 5 and 6 define their own fixtures rather than importing this one.

- [ ] **Step 1: Write the failing mapping tests**

Create `Tests/TextEngineCoreTests/WrapRowQueryTests.swift`:

```swift
import XCTest
import TextEngineCore

/// Located-branch mapping for `visualRowAt`. Fixture: row counts [1, 3, 2] over three
/// logical lines at rowHeight 10 -> totalRows 6, firstVisualRow prefix [0, 1, 4, 6],
/// totalHeight 60.
final class WrapRowQueryTests: XCTestCase {
    private static let rowHeight = 10.0
    private static let totalRows = 6
    private static let totalHeight = 60.0

    /// Lines pack to 1, 3 and 2 rows at wrapWidth 10 (char-wrap on 10-wide cells).
    private func layout123() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: [10.0], breaks: []),                    // 1 row
                (advances: [10.0, 10.0, 10.0], breaks: [1, 2]),    // 3 rows
                (advances: [10.0, 10.0], breaks: [1]),             // 2 rows
            ],
            rowHeight: Self.rowHeight,
            wrapWidth: 10.0
        )
    }

    private func located(_ y: Double, _ layout: TestVisualRowLayout,
                         _ file: StaticString = #filePath, _ line: UInt = #line) -> VisualRowLocation? {
        guard case .row(let location) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
            XCTFail("expected .row at y=\(y)", file: file, line: line)
            return nil
        }
        return location
    }

    // The fixture must actually have the shape the rest of the file assumes.
    func testFixtureShape() {
        let layout = layout123()
        XCTAssertEqual(layout.lineCount, 3)
        XCTAssertEqual([0, 1, 2].map { layout.visualRowCount(inLine: $0) }, [1, 3, 2])
        XCTAssertEqual(layout.firstVisualRow(ofLine: 3), Self.totalRows)
    }

    func testInteriorOfAMultiRowLine() {
        // globalRow 3 sits in line 1 (rows 1..<4), as its second-from-last row.
        guard let location = located(35.0, layout123()) else { return }
        XCTAssertEqual(location.globalRow, 3)
        XCTAssertEqual(location.logicalLine, 1)
        XCTAssertEqual(location.rowInLine, 2)
        XCTAssertEqual(location.clamp, .inRange)
    }

    func testEverySingleRowRoundTripsItsOwnIndices() {
        let layout = layout123()
        let expected: [(line: Int, rowInLine: Int)] = [
            (0, 0), (1, 0), (1, 1), (1, 2), (2, 0), (2, 1),
        ]
        for globalRow in 0..<Self.totalRows {
            guard let location = located(Double(globalRow) * Self.rowHeight + 5.0, layout) else { return }
            XCTAssertEqual(location.globalRow, globalRow)
            XCTAssertEqual(location.logicalLine, expected[globalRow].line, "globalRow \(globalRow)")
            XCTAssertEqual(location.rowInLine, expected[globalRow].rowInLine, "globalRow \(globalRow)")
        }
    }

    // Half-open [top, bottom): a y exactly on a row top belongs to THAT row, not the
    // one above. This is the assertion a `<=` -> `<` mutation in the row-axis search
    // moves (falsifiability drill 1).
    func testExactRowTopBelongsToThatRow() {
        let layout = layout123()
        for globalRow in 0..<Self.totalRows {
            guard let location = located(Double(globalRow) * Self.rowHeight, layout) else { return }
            XCTAssertEqual(location.globalRow, globalRow, "y == \(globalRow) * rowHeight")
        }
    }

    func testLastInteriorYIsStillInRange() {
        guard let location = located(Self.totalHeight - 0.001, layout123()) else { return }
        XCTAssertEqual(location.globalRow, Self.totalRows - 1)
        XCTAssertEqual(location.logicalLine, 2)
        XCTAssertEqual(location.rowInLine, 1)
        XCTAssertEqual(location.clamp, .inRange)
    }

    // Clamped queries take no special case: both edges flow through the same two
    // provider calls as an in-range hit, so line/rowInLine are right by construction
    // (spec Decision 7).
    func testClampedToTop() {
        guard let location = located(-1.0, layout123()) else { return }
        XCTAssertEqual(location.globalRow, 0)
        XCTAssertEqual(location.logicalLine, 0)
        XCTAssertEqual(location.rowInLine, 0)
        XCTAssertEqual(location.clamp, .clampedToTop)
    }

    func testClampedToBottomNamesTheLastRowOfTheLastLine() {
        guard let location = located(Self.totalHeight, layout123()) else { return }
        XCTAssertEqual(location.globalRow, Self.totalRows - 1)
        XCTAssertEqual(location.logicalLine, 2)
        XCTAssertEqual(location.rowInLine, 1)
        XCTAssertEqual(location.clamp, .clampedToBottom)
    }

    func testEmptyDocumentIsEmptyNotFailure() {
        let layout = TestVisualRowLayout(lines: [], rowHeight: Self.rowHeight, wrapWidth: 10.0)
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 0, layout: layout), .empty)
    }

    // A blank logical line still occupies exactly one visual row (node 1's contract),
    // so it is addressable by y like any other.
    func testBlankLineIsAddressable() {
        let layout = TestVisualRowLayout(
            lines: [(advances: [10.0], breaks: []), (advances: [], breaks: [])],
            rowHeight: Self.rowHeight, wrapWidth: 10.0
        )
        XCTAssertEqual(layout.firstVisualRow(ofLine: 2), 2)
        guard let location = located(15.0, layout) else { return }
        XCTAssertEqual(location.globalRow, 1)
        XCTAssertEqual(location.logicalLine, 1)
        XCTAssertEqual(location.rowInLine, 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryTests > /tmp/slice53-task3-red.txt 2>&1; then
  echo "UNEXPECTED PASS — the types cannot exist yet"
else
  echo "EXPECTED RED"; rg -n "cannot find|error:" /tmp/slice53-task3-red.txt | head -5
fi
```

Expected: `EXPECTED RED` with `cannot find 'VisualRowQuery' in scope` / `value of type 'ViewportVirtualizer' has no member 'visualRowAt'`.

- [ ] **Step 3: Add the result types**

In `Sources/TextEngineCore/ViewportTypes.swift`, insert after `ColumnGeometryLocation` and before the `VisualRow` declaration:

```swift
/// Where a document `y` lands on the visual-row axis. Names the row in BOTH coordinate
/// systems the engine speaks: `globalRow` indexes `compute(_:layout:)`'s `VirtualRange`,
/// while `(logicalLine, rowInLine)` is what `VisualRow` and `DocumentVisualRowCursor`
/// speak. `Clamp` is reused from `LineLocation` rather than re-declared — the vertical
/// clamp question is identical on both axes, and a parallel enum would invite drift.
public struct VisualRowLocation: Equatable {
    /// Global visual-row index — the same index space as `compute(_:layout:)`'s range.
    public let globalRow: Int
    /// The logical line this row belongs to.
    public let logicalLine: Int
    /// 0-based index of this row within `logicalLine`.
    public let rowInLine: Int
    /// Whether the query landed inside the document or past an edge.
    public let clamp: LineLocation.Clamp

    public init(globalRow: Int, logicalLine: Int, rowInLine: Int, clamp: LineLocation.Clamp) {
        self.globalRow = globalRow
        self.logicalLine = logicalLine
        self.rowInLine = rowInLine
        self.clamp = clamp
    }
}

public enum VisualRowQuery: Equatable {
    case row(VisualRowLocation)           // a real visual row was located
    case empty                            // empty document: lineCount == 0
    case failure(ViewportValidationError) // invalid input / malformed layout
}
```

- [ ] **Step 4: Implement `visualRowAt`**

Create `Sources/TextEngineCore/WrapPositionQuery.swift`:

```swift
extension ViewportVirtualizer {
    /// Maps a document `y` to the visual row whose half-open vertical span contains it —
    /// the wrap-aware analog of `lineAt(y:metrics:)`, over the visual-row axis.
    ///
    /// Stateless, O(1) core memory. Runs `compute(_:layout:)`'s layout ladder (the same
    /// shared helper, so the two entry points accept and reject exactly the same
    /// layouts), then delegates the row-axis search to `lineAt` over a uniform row axis
    /// and names the located row in both coordinate systems. Adds no new search: one
    /// row-axis search, one `logicalLine(containingVisualRow:)` search
    /// (provider-overridable, binary-search default), one O(1) `firstVisualRow` probe.
    ///
    /// A `y` outside `[0, totalRows * rowHeight)` clamps to the nearest row with
    /// `LineLocation.Clamp` recording the edge; both edges flow through the same two
    /// provider calls as an in-range hit, so no special case is needed. An empty
    /// document is `.empty`, not a failure.
    public static func visualRowAt<Layout: VisualRowLayoutSource>(
        y: Double,
        layout: Layout
    ) -> VisualRowQuery {
        if layout.lineCount < 0 { return .failure(.negativeLineCount) }
        if !y.isFinite { return .failure(.nonFiniteValue) }

        let totalRows: Int
        switch validateVisualRowLayout(layout) {
        case .failure(let error): return .failure(error)
        case .empty: return .empty
        case .rows(let rows): totalRows = rows
        }

        let rowAxis = UniformLineMetrics(lineCount: totalRows, lineHeight: layout.rowHeight)
        switch lineAt(y: y, metrics: rowAxis) {
        // Neither branch is reachable: the ladder proved totalRows > 0 and y finite, and
        // UniformLineMetrics.offset(ofLine: 0) is exactly 0. Mapped through rather than
        // force-unwrapped — no fabricated row, no crash (the DocumentVisualRowCursor
        // GIGO precedent).
        case .failure(let error): return .failure(error)
        case .empty: return .empty
        case .line(let location):
            let globalRow = location.lineIndex
            let logicalLine = layout.logicalLine(containingVisualRow: globalRow)
            let rowInLine = globalRow - layout.firstVisualRow(ofLine: logicalLine)
            return .row(VisualRowLocation(
                globalRow: globalRow,
                logicalLine: logicalLine,
                rowInLine: rowInLine,
                clamp: location.clamp
            ))
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter WrapRowQueryTests > /tmp/slice53-task3-green.txt 2>&1; then
  echo "RED"; rg -n "XCTAssert|error:" /tmp/slice53-task3-green.txt | head -20
else
  echo "PASS"
fi
```

Expected: `PASS`.

- [ ] **Step 6: Falsifiability drill 1 — the half-open boundary**

Mutate the row-containment comparison in `Sources/TextEngineCore/LineMetricsSource.swift`'s `binarySearchLineIndex`, changing `metrics.offset(ofLine: mid) <= target` to `< target`:

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryTests.testExactRowTopBelongsToThatRow > /tmp/slice53-drill1.txt 2>&1; then
  echo "UNEXPECTED PASS — the boundary is not pinned"
else
  echo "EXPECTED RED"; rg -n "XCTAssertEqual failed" /tmp/slice53-drill1.txt | head -3
fi
```

Expected: `EXPECTED RED` — `("2") is not equal to ("3")`-shaped, at `y == 3 * rowHeight`. **Collateral is expected and correct**: this comparison is shared, so no-wrap boundary tests redden too. Record the wrap-side red. Revert the mutation.

- [ ] **Step 7: Falsifiability drill 2 — the `rowInLine` subtraction**

In `WrapPositionQuery.swift`, change `let rowInLine = globalRow - layout.firstVisualRow(ofLine: logicalLine)` to `... + 1`:

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryTests > /tmp/slice53-drill2.txt 2>&1; then
  echo "UNEXPECTED PASS — rowInLine is not pinned"
else
  echo "EXPECTED RED"; rg -n "XCTAssertEqual failed" /tmp/slice53-drill2.txt | head -3
fi
```

Expected: `EXPECTED RED` in `testInteriorOfAMultiRowLine` / `testEverySingleRowRoundTripsItsOwnIndices`. Revert and re-run to confirm green.

- [ ] **Step 8: Full suite, Foundation scan, commit**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test > /tmp/slice53-task3-full.txt 2>&1; then echo "SUITE RED"; else echo "suite green"; fi
FOUNDATION="$(rg -n 'Foundation' Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "PASS: Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION"; fi
git add Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/WrapPositionQuery.swift \
        Tests/TextEngineCoreTests/WrapRowQueryTests.swift
git commit -m "feat: visualRowAt maps y to a visual row on the wrap axis

The wrap-aware lineAt analog (map node 3, brief criterion 3). Returns a
VisualRowLocation naming the row in both coordinate systems - globalRow for
compute's VirtualRange, (logicalLine, rowInLine) for VisualRow and the document
cursor - plus a reused LineLocation.Clamp.

Composes rather than searches: the shared layout ladder, then lineAt over a
uniform row axis, then one logicalLine search and one firstVisualRow probe.
O(1) core memory. Clamped queries need no special case; both edges flow through
the same two provider calls as an in-range hit.

Drills recorded: <= -> < on the row-containment comparison reddens the exact-top
test; +1 on the rowInLine subtraction reddens the mapping tests."
```

---

## Task 4: Validation ladder tests and the parity matrix

Pins the ladder Task 3 wired in, and the divergence-vs-absence distinction. Spec Decisions 4 and 5; AC5; drills 4 and 6.

**Files:**
- Create: `Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.visualRowAt(y:layout:)` (Task 3); `RiggedVisualRowLayout(lineCount:rowHeight:wrapWidth:firstRow:)` and `TestVisualRowLayout` from `VisualRowLayoutTestSupport.swift`.
- Produces: nothing consumed downstream.

- [ ] **Step 1: Write the failing validation and parity tests**

Create `Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift`:

```swift
import XCTest
import TextEngineCore

/// `visualRowAt`'s ladder, and its parity with `compute(_:layout:)`.
///
/// The two entry points share one layout helper, so parity catches DIVERGENCE — a check
/// that moved, fires in a different order, or exists on one side only. It cannot catch
/// ABSENCE: deleting a check from the shared helper changes both callers identically and
/// leaves parity green. That is what the per-error-case tests below are for, and
/// `wrapWidth` needs them most — it is the check this query never uses and a later reader
/// would delete as dead weight.
final class WrapRowQueryValidationTests: XCTestCase {
    private func rigged(lineCount: Int = 2, rowHeight: Double = 5.0, wrapWidth: Double = 20.0,
                        firstRow: [Int] = [0, 1, 2]) -> RiggedVisualRowLayout {
        RiggedVisualRowLayout(lineCount: lineCount, rowHeight: rowHeight, wrapWidth: wrapWidth, firstRow: firstRow)
    }

    private func expectFailure(_ y: Double, _ layout: RiggedVisualRowLayout, _ expected: ViewportValidationError,
                               _ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: y, layout: layout), .failure(expected),
                       file: file, line: line)
    }

    // --- presence: one test per error case -------------------------------------

    func testNegativeLineCount() { expectFailure(0, rigged(lineCount: -1, firstRow: [0]), .negativeLineCount) }

    func testNonFiniteY() {
        for y in [Double.nan, .infinity, -.infinity] {
            expectFailure(y, rigged(), .nonFiniteValue)
        }
    }

    func testNonPositiveRowHeight() {
        for h in [0.0, -1.0, -Double.infinity, Double.nan] {
            expectFailure(0, rigged(rowHeight: h), .nonPositiveRowHeight)
        }
    }

    // The check this query never uses. Deleting it would let visualRowAt accept a layout
    // compute rejects — see the class comment and drill 6.
    func testNonPositiveWrapWidth() {
        for w in [0.0, -1.0, -Double.infinity, Double.nan] {
            expectFailure(0, rigged(wrapWidth: w), .nonPositiveWrapWidth)
        }
    }

    func testInfiniteWrapWidthDoesNotFail() {
        let layout = TestVisualRowLayout(lines: [(advances: [5.0], breaks: [])], rowHeight: 5.0, wrapWidth: .infinity)
        if case .failure = ViewportVirtualizer.visualRowAt(y: 0, layout: layout) { XCTFail("∞ width must not fail") }
    }

    func testFirstVisualRowZeroNotZero() { expectFailure(0, rigged(firstRow: [5, 6, 7]), .invalidVisualRowLayout) }

    func testNonPositiveTotalRows() { expectFailure(0, rigged(lineCount: 1, firstRow: [0, 0]), .invalidVisualRowLayout) }

    func testTotalHeightOverflowIsWrapCoherent() {
        let huge = 1 << 40
        expectFailure(0, rigged(lineCount: 1, rowHeight: .greatestFiniteMagnitude, firstRow: [0, huge]),
                      .invalidVisualRowLayout)
    }

    func testEmptyDocumentIsEmptyNotFailure() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 0, layout: rigged(lineCount: 0, firstRow: [0])), .empty)
    }

    // --- precedence -------------------------------------------------------------

    func testLadderOrderLineCountBeforeY() {
        expectFailure(.nan, rigged(lineCount: -1, firstRow: [0]), .negativeLineCount)
    }

    func testLadderOrderYBeforeRowHeight() {
        // y finiteness is this query's value check and sits above the layout half, exactly
        // as compute's input checks do.
        expectFailure(.nan, rigged(rowHeight: -1), .nonFiniteValue)
    }

    // --- parity with compute ----------------------------------------------------

    private func riggedMatrix() -> [(name: String, layout: RiggedVisualRowLayout)] {
        [
            ("valid", rigged()),
            ("negativeLineCount", rigged(lineCount: -1, firstRow: [0])),
            ("emptyDocument", rigged(lineCount: 0, firstRow: [0])),
            ("zeroRowHeight", rigged(rowHeight: 0)),
            ("nanRowHeight", rigged(rowHeight: .nan)),
            ("zeroWrapWidth", rigged(wrapWidth: 0)),
            ("nanWrapWidth", rigged(wrapWidth: .nan)),
            ("infiniteWrapWidth", rigged(wrapWidth: .infinity)),
            ("firstRowNotZero", rigged(firstRow: [5, 6, 7])),
            ("zeroTotalRows", rigged(lineCount: 1, firstRow: [0, 0])),
            ("totalHeightOverflow", rigged(lineCount: 1, rowHeight: .greatestFiniteMagnitude, firstRow: [0, 1 << 40])),
        ]
    }

    private func computeError(_ layout: RiggedVisualRowLayout, badValue: Bool) -> ViewportValidationError? {
        let input = VariableViewportInput(
            scrollOffsetY: badValue ? .nan : 0, viewportHeight: 30,
            overscanLinesBefore: 0, overscanLinesAfter: 0)
        if case .failure(let error) = ViewportVirtualizer.compute(input, layout: layout) { return error }
        return nil
    }

    private func rowError(_ layout: RiggedVisualRowLayout, badValue: Bool) -> ViewportValidationError? {
        if case .failure(let error) = ViewportVirtualizer.visualRowAt(y: badValue ? .nan : 0, layout: layout) {
            return error
        }
        return nil
    }

    func testLadderParityWithCompute() {
        for (name, layout) in riggedMatrix() {
            for badValue in [false, true] {
                XCTAssertEqual(
                    computeError(layout, badValue: badValue),
                    rowError(layout, badValue: badValue),
                    "\(name) (badValue: \(badValue)): compute and visualRowAt disagree")
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify green**

The implementation already exists (Task 3), so these tests pin it rather than drive it. They must pass on the first run — a red here means Task 3's ladder is wrong, not that this task is incomplete.

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter WrapRowQueryValidationTests > /tmp/slice53-task4.txt 2>&1; then
  echo "RED — Task 3's ladder is wrong"; rg -n "XCTAssert" /tmp/slice53-task4.txt | head -10
else
  echo "PASS"
fi
```

Expected: `PASS`.

- [ ] **Step 3: Falsifiability drill 4 — parity sees divergence**

Swap the first two checks in `visualRowAt` so `!y.isFinite` is tested **before** `layout.lineCount < 0`:

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryValidationTests.testLadderParityWithCompute > /tmp/slice53-drill4.txt 2>&1; then
  echo "UNEXPECTED PASS — parity does not see head-order divergence"
else
  echo "EXPECTED RED"; rg -n "disagree" /tmp/slice53-drill4.txt | head -3
fi
```

Expected: `EXPECTED RED` on the `negativeLineCount (badValue: true)` cell — `compute` still answers `.negativeLineCount` while `visualRowAt` now answers `.nonFiniteValue`. Revert.

- [ ] **Step 4: Falsifiability drill 6 — parity is blind to absence**

Delete the `wrapWidth` check from the **shared** helper in `WrapViewportVirtualizer.swift`. This changes both callers identically, so the parity test must stay **green** while both per-error-case suites redden. Three commands, three separate expectations:

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryValidationTests.testLadderParityWithCompute > /tmp/slice53-drill6-parity.txt 2>&1; then
  echo "EXPECTED GREEN: parity is blind to absence (this is the point)"
else
  echo "UNEXPECTED RED: parity should not see a symmetric deletion"
fi
if swift test --filter WrapRowQueryValidationTests.testNonPositiveWrapWidth > /tmp/slice53-drill6-row.txt 2>&1; then
  echo "UNEXPECTED PASS: visualRowAt side did not catch the deletion"
else
  echo "EXPECTED RED: visualRowAt side caught it"
fi
if swift test --filter WrapComputeValidationTests.testNonPositiveWrapWidth > /tmp/slice53-drill6-compute.txt 2>&1; then
  echo "UNEXPECTED PASS: compute side did not catch the deletion"
else
  echo "EXPECTED RED: compute side caught it"
fi
```

Expected, in order: `EXPECTED GREEN`, `EXPECTED RED: visualRowAt side caught it`, `EXPECTED RED: compute side caught it`. **All three lines go in the verification record** — together they are what makes Decision 5's divergence-vs-absence claim evidence rather than an assertion. Revert and re-run to confirm green.

- [ ] **Step 5: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift
git commit -m "test: pin visualRowAt's ladder and its parity with compute

One test per error case plus two precedence pins, and a parity matrix driving
eleven rigged layouts x good/bad value through both entry points.

Parity catches divergence, not absence: drill 4 (swap visualRowAt's head order)
reddens it, while drill 6 (delete the wrapWidth check from the SHARED helper)
leaves it green and reddens the per-error-case test on each side instead. Both
recorded."
```

---

## Task 5: The infinite-width equivalence oracle

Brief criterion 3's oracle requirement for this query. Spec Decision 4 scoping and AC6; drill 3.

**Files:**
- Create: `Tests/TextEngineCoreTests/WrapRowQueryEquivalenceTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.visualRowAt(y:layout:)`, `ViewportVirtualizer.lineAt(y:metrics:)`, `TestVisualRowLayout`, `UniformLineMetrics`.
- Produces: nothing consumed downstream.

- [ ] **Step 1: Write the oracle**

Create `Tests/TextEngineCoreTests/WrapRowQueryEquivalenceTests.swift`:

```swift
import XCTest
import TextEngineCore

/// Criterion 3's oracle on the y→row axis: at a wrap width no line can exceed, the wrap
/// path must be bit-identical to the no-wrap path. Scoped to the LOCATED branch
/// deliberately — the two queries return different types, and their failure/empty ladders
/// differ by design (`lineAt` answers an empty document without ever inspecting
/// `lineHeight`, `visualRowAt` follows `compute` and reports `.nonPositiveRowHeight`).
final class WrapRowQueryEquivalenceTests: XCTestCase {
    private static let rowHeight = 12.0

    /// Irregular advances and break sets, so a width-sensitive bug cannot hide behind a
    /// uniform fixture. A blank line is included: it packs to exactly one row.
    private static let lines: [(advances: [Double], breaks: Set<Int>)] = [
        (advances: [7.0, 3.0, 11.0], breaks: [1, 2]),
        (advances: [5.0], breaks: []),
        (advances: [2.0, 2.0, 2.0, 2.0], breaks: [1, 2, 3]),
        (advances: [], breaks: []),
        (advances: [9.0, 1.0], breaks: [1]),
    ]

    private func ySweep(totalHeight: Double) -> [Double] {
        var ys: [Double] = [-100.0, -0.001, 0.0]
        var row = 0
        while Double(row) * Self.rowHeight < totalHeight {
            let top = Double(row) * Self.rowHeight
            ys.append(top)                            // exact boundary
            ys.append(top + Self.rowHeight / 2)       // interior
            ys.append(top + Self.rowHeight - 0.001)   // just below the next boundary
            row += 1
        }
        ys.append(totalHeight - 0.001)
        ys.append(totalHeight)                        // clamped
        ys.append(totalHeight + 100.0)                // clamped
        return ys
    }

    func testWidthNoLineExceedsEqualsUniformLineAt() {
        let lineCount = Self.lines.count
        let totalHeight = Double(lineCount) * Self.rowHeight
        let uniform = UniformLineMetrics(lineCount: lineCount, lineHeight: Self.rowHeight)

        // ∞ and a large finite width: the oracle holds at any width >= every line's total
        // advance, not only at ∞.
        for width in [Double.infinity, 1_000.0] {
            let layout = TestVisualRowLayout(lines: Self.lines, rowHeight: Self.rowHeight, wrapWidth: width)

            // Precondition of the oracle: at this width every line is exactly one row.
            XCTAssertEqual(layout.firstVisualRow(ofLine: lineCount), lineCount, "width \(width)")

            for y in ySweep(totalHeight: totalHeight) {
                guard case .row(let located) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
                    XCTFail("expected .row at y=\(y), width \(width)"); continue
                }
                guard case .line(let reference) = ViewportVirtualizer.lineAt(y: y, metrics: uniform) else {
                    XCTFail("expected .line at y=\(y)"); continue
                }
                XCTAssertEqual(located.globalRow, reference.lineIndex, "y=\(y) width=\(width)")
                XCTAssertEqual(located.logicalLine, reference.lineIndex, "y=\(y) width=\(width)")
                XCTAssertEqual(located.rowInLine, 0, "y=\(y) width=\(width)")
                XCTAssertEqual(located.clamp, reference.clamp, "y=\(y) width=\(width)")
            }
        }
    }

    /// The oracle must be able to tell the two paths apart when they genuinely differ —
    /// otherwise "equal at ∞" is vacuous. At a narrow width the same document has more
    /// rows than lines, and the two answers must diverge.
    func testNarrowWidthIsNotEquivalent() {
        let layout = TestVisualRowLayout(lines: Self.lines, rowHeight: Self.rowHeight, wrapWidth: 5.0)
        XCTAssertGreaterThan(layout.firstVisualRow(ofLine: Self.lines.count), Self.lines.count)
    }
}
```

- [ ] **Step 2: Run — it must pass on the first run**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter WrapRowQueryEquivalenceTests > /tmp/slice53-task5.txt 2>&1; then
  echo "RED"; rg -n "XCTAssert" /tmp/slice53-task5.txt | head -10
else
  echo "PASS"
fi
```

Expected: `PASS`. An oracle pins a property that must already hold; a red here means Task 3 is wrong.

- [ ] **Step 3: Falsifiability drill 3 — the oracle can fail**

In `WrapPositionQuery.swift`, replace `clamp: location.clamp` with `clamp: .inRange`:

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryEquivalenceTests > /tmp/slice53-drill3.txt 2>&1; then
  echo "UNEXPECTED PASS — the oracle does not compare clamp"
else
  echo "EXPECTED RED"; rg -n "XCTAssertEqual failed" /tmp/slice53-drill3.txt | head -3
fi
```

Expected: `EXPECTED RED` on the clamped samples (`y = -100`, `y = totalHeight`). Collateral in `WrapRowQueryTests`'s clamp tests is expected — record the equivalence-suite red specifically. Revert and re-run.

- [ ] **Step 4: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/TextEngineCoreTests/WrapRowQueryEquivalenceTests.swift
git commit -m "test: infinite-width equivalence oracle for visualRowAt

At any width no line exceeds (∞ included), visualRowAt is bit-identical to
lineAt over a uniform axis: globalRow == lineIndex, logicalLine == lineIndex,
rowInLine == 0, clamp equal - swept over negative, exact-boundary, interior and
past-the-end y across five irregular lines including a blank one.

Scoped to the located branch: the two ladders differ by design on the empty
document. A companion test pins that the two paths DO diverge at a narrow
width, so 'equal at infinity' is not vacuous. Drill: clamp -> .inRange reddens
the clamped samples."
```

---

## Task 6: Round-trip against the cursor, and the probe-count bound

The load-bearing correctness test (spec: every other suite compares against arithmetic restated in the test file) plus the cost-class pin. AC7, AC8; drill 5.

**Files:**
- Create: `Tests/TextEngineCoreTests/WrapRowQueryRoundTripTests.swift`
- Create: `Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift`

**Interfaces:**
- Consumes: `ViewportVirtualizer.compute(_:layout:)`, `ViewportVirtualizer.visualRowGeometry(for:layout:)`, `collectGeometry` (`VisualRowLayoutTestSupport.swift:67`), `TestVisualRowLayout`, `VisualRowGeometry`.
- Produces: nothing consumed downstream.

- [ ] **Step 1: Write the round-trip test**

Create `Tests/TextEngineCoreTests/WrapRowQueryRoundTripTests.swift`:

```swift
import XCTest
import TextEngineCore

/// The load-bearing correctness test. Every other suite compares `visualRowAt` against
/// arithmetic restated in the test file, so a coherent-but-wrong row model could satisfy
/// all of them. This one compares it against node 1's independently-written greedy packer,
/// driven across lines by node 2's cursor over a real `compute` range.
final class WrapRowQueryRoundTripTests: XCTestCase {
    private static let rowHeight = 10.0

    private func layout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: [10.0], breaks: []),                          // 1 row
                (advances: [10.0, 10.0, 10.0], breaks: [1, 2]),          // 3 rows
                (advances: [], breaks: []),                              // blank -> 1 row
                (advances: [10.0, 10.0], breaks: [1]),                   // 2 rows
                (advances: [10.0, 10.0, 10.0, 10.0], breaks: [1, 2, 3]), // 4 rows
            ],
            rowHeight: Self.rowHeight,
            wrapWidth: 10.0
        )
    }

    func testEveryStreamedRowIsFoundByItsOwnY() {
        let layout = layout()
        let input = VariableViewportInput(
            scrollOffsetY: 15.0, viewportHeight: 40.0,
            overscanLinesBefore: 1, overscanLinesAfter: 1)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else {
            return XCTFail("compute must succeed on a well-formed layout")
        }
        let streamed = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertFalse(streamed.isEmpty, "the fixture must produce a non-empty buffer range")
        XCTAssertEqual(streamed.count, range.bufferEndExclusive - range.bufferStart)

        for (offset, geometry) in streamed.enumerated() {
            let expectedGlobalRow = range.bufferStart + offset
            // Probe BOTH the exact row boundary (what a `<`/`<=` mutation moves) and the
            // row interior (which closes the class of compensating errors where a shifted
            // boundary and a shifted index cancel on boundary samples alone).
            for probe in [geometry.y, geometry.y + Self.rowHeight / 2] {
                guard case .row(let located) = ViewportVirtualizer.visualRowAt(y: probe, layout: layout) else {
                    XCTFail("expected .row at y=\(probe)"); continue
                }
                XCTAssertEqual(located.globalRow, expectedGlobalRow, "probe \(probe)")
                XCTAssertEqual(located.logicalLine, geometry.row.logicalLine, "probe \(probe)")
                XCTAssertEqual(located.rowInLine, geometry.row.rowInLine, "probe \(probe)")
            }
        }
    }
}
```

- [ ] **Step 2: Write the probe-count test**

Create `Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift`:

```swift
import XCTest
import TextEngineCore

/// The LAYOUT-axis probe bound. This harness sees one of the two searches by
/// construction: `visualRowAt` builds its `UniformLineMetrics` INSIDE the core, so a
/// counting wrapper around `layout` cannot observe the row-axis search at all. That is
/// not a gap being papered over — `UniformLineMetrics.offset` is pure arithmetic touching
/// no provider, and the row-axis search is pinned by `LineAtQueryCountTests`
/// (`testInRangeUsesLogarithmicQueriesAtOneMillionLines`, whose
/// `expectedMax = 2 + (ceilLog2(lineCount) + 1)` is the shape the bound below copies).
///
/// On neither axis is the count constant in document size: "bounded" here means
/// LOGARITHMIC, in the vocabulary the no-wrap suite already uses.
final class WrapRowQueryCountTests: XCTestCase {
    private final class ProbeCounter {
        var firstVisualRowCalls = 0
    }

    private struct CountingVisualRowLayout: VisualRowLayoutSource {
        let base: TestVisualRowLayout
        let counter: ProbeCounter

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double { base.columnOffset(inLine: line, column: column) }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { base.canBreak(beforeColumn: column, inLine: line) }
        func visualRowCount(inLine line: Int) -> Int { base.visualRowCount(inLine: line) }

        func firstVisualRow(ofLine line: Int) -> Int {
            counter.firstVisualRowCalls += 1
            return base.firstVisualRow(ofLine: line)
        }
        // logicalLine(containingVisualRow:) is deliberately NOT overridden: the default
        // binary search runs against this wrapper, so its probes are counted.
    }

    // Identical to the six existing *QueryCountTests — same helper, same shape.
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

    private static let lineCount = 1_024
    private static let rowHeight = 16.0

    private func counting() -> (CountingVisualRowLayout, ProbeCounter) {
        let base = TestVisualRowLayout(
            lines: Array(repeating: (advances: [8.0], breaks: Set<Int>()), count: Self.lineCount),
            rowHeight: Self.rowHeight,
            wrapWidth: .infinity)
        let counter = ProbeCounter()
        return (CountingVisualRowLayout(base: base, counter: counter), counter)
    }

    // 2 ladder probes (firstVisualRow(0), firstVisualRow(lineCount))
    // + <= ceilLog2(lineCount) + 1 inside the default logicalLine search
    // + 1 final probe for the rowInLine subtraction.
    //
    // The bound is EXACTLY tight at 1024 lines: the search's worst case is 11 probes,
    // + 2 + 1 = 14 = ceilLog2(1024) + 4. There is no slack, which is deliberate — slack
    // is what lets a regression hide. If a future change makes this red by one, check
    // whether a probe was genuinely added before widening the bound.
    private var expectedMax: Int { ceilLog2(Self.lineCount) + 4 }

    func testInRangeQueryIsLogarithmicOnTheLayoutAxis() {
        let (layout, counter) = counting()
        guard case .row = ViewportVirtualizer.visualRowAt(y: 700.0 * Self.rowHeight + 3.0, layout: layout) else {
            return XCTFail("expected .row")
        }
        XCTAssertLessThanOrEqual(counter.firstVisualRowCalls, expectedMax)
    }

    func testProbeCountDoesNotGrowLinearlyWithTheDocument() {
        let (layout, counter) = counting()
        guard case .row = ViewportVirtualizer.visualRowAt(y: 1_000.0 * Self.rowHeight + 3.0, layout: layout) else {
            return XCTFail("expected .row")
        }
        // A linear walk over 1024 lines would blow this by two orders of magnitude.
        XCTAssertLessThan(counter.firstVisualRowCalls, Self.lineCount / 10)
    }

    /// `LineAtQueryCountTests.testClampBranchesDoNotSearch` pins a two-probe CONSTANT for
    /// clamped queries on the no-wrap axis. That does NOT carry over here, and this test
    /// states the difference so a reader who knows the no-wrap axis does not copy the
    /// constant across: `lineAt` does skip the row-axis search when clamping, but the
    /// `logicalLine` search on the layout axis still runs, because Decision 7 routes both
    /// edges through the same two provider calls as an in-range hit.
    func testClampedQueriesStillSearchTheLayoutAxis() {
        for y in [-1.0, Double(Self.lineCount) * Self.rowHeight + 1.0] {
            let (layout, counter) = counting()
            guard case .row(let located) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
                return XCTFail("expected .row at y=\(y)")
            }
            XCTAssertNotEqual(located.clamp, .inRange, "y=\(y) must clamp")
            XCTAssertGreaterThan(counter.firstVisualRowCalls, 2,
                                 "the no-wrap axis's two-probe clamp constant must NOT hold here")
            XCTAssertLessThanOrEqual(counter.firstVisualRowCalls, expectedMax, "y=\(y)")
        }
    }
}
```

- [ ] **Step 3: Run both suites**

```bash
cd /Users/aabanschikov/swift-text-engine
for suite in WrapRowQueryRoundTripTests WrapRowQueryCountTests; do
  if ! swift test --filter "$suite" > "/tmp/slice53-task6-$suite.txt" 2>&1; then
    echo "RED: $suite"; rg -n "XCTAssert" "/tmp/slice53-task6-$suite.txt" | head -10
  else
    echo "PASS: $suite"
  fi
done
```

Expected: two `PASS` lines.

- [ ] **Step 4: Falsifiability drill 5 — the probe bound can fail**

In `WrapPositionQuery.swift`, replace the `logicalLine` call with a linear scan:

```swift
            var logicalLine = 0
            while logicalLine + 1 < layout.lineCount && layout.firstVisualRow(ofLine: logicalLine + 1) <= globalRow {
                logicalLine += 1
            }
```

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryCountTests > /tmp/slice53-drill5.txt 2>&1; then
  echo "UNEXPECTED PASS — the probe bound is not pinned"
else
  echo "EXPECTED RED"; rg -n "is not less than|is not less than or equal" /tmp/slice53-drill5.txt | head -3
fi
```

Expected: `EXPECTED RED` — the linear scan produces ~700-1000 probes against a bound of 14. Note the round-trip and mapping suites stay **green** under this mutation: a linear scan is *correct*, only slow, which is exactly why the cost class needs its own pin. Revert and re-run.

- [ ] **Step 5: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/TextEngineCoreTests/WrapRowQueryRoundTripTests.swift \
        Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift
git commit -m "test: round-trip visualRowAt against the document cursor, pin its cost class

The round-trip drives compute -> DocumentVisualRowCursor over an irregular
five-line fixture and asserts every streamed row is found by its own y, probed
at both the exact boundary and the row interior - the one test that compares
the query against node 1's independently-written packer rather than against
arithmetic restated in the test file.

The count suite pins the LAYOUT-axis bound at ceilLog2(lineCount) + 4 and says
what it cannot see: the row-axis search runs over a core-constructed
UniformLineMetrics and is pinned by LineAtQueryCountTests instead. It also
pins the Decision 7 asymmetry - clamped queries DO search here, unlike the
no-wrap axis's two-probe constant.

Drill: a linear scan for logicalLine reddens the bound while every correctness
suite stays green."
```

---

## Task 7: The `--wrap-row-query` benchmark mode

Observational, local-only, not gateable. Spec Benchmark Mode / CI; AC9, AC10.

**Files:**
- Create: `Sources/ViewportBenchmarks/WrapRowQueryBenchmark.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- Modify: `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- Create: `Tests/ViewportBenchmarksTests/WrapRowQueryOptionsTests.swift`
- Create: `Tests/ViewportBenchmarksTests/WrapRowQueryChecksumTests.swift`

**Interfaces:**
- Consumes: `BenchmarkWrapLayout(lineCount:cells:advance:rowHeight:wrapWidth:)` (`WrapComputeBenchmark.swift:7`), `percentile(_:numerator:denominator:)`, `nanoseconds(_:)`, `deterministicIndex(sample:multiplier:modulus:)` (`BenchmarkSupport.swift:27`), `ViewportVirtualizer.visualRowAt`.
- Produces: `func runWrapRowQueryBenchmarks() -> Bool`; `BenchmarkMode.wrapRowQuery` with `outputName == "wrap_row_query"`; `func wrapRowQueryChecksum(_ location: VisualRowLocation) -> Int` (used by the checksum test).

- [ ] **Step 1: Write the failing options tests**

Create `Tests/ViewportBenchmarksTests/WrapRowQueryOptionsTests.swift`:

```swift
import XCTest
@testable import ViewportBenchmarks

final class WrapRowQueryOptionsTests: XCTestCase {
    func testFlagSelectsTheMode() {
        guard case let .run(options) = BenchmarkOptions.parse(["--wrap-row-query"]) else {
            return XCTFail("--wrap-row-query must select a runnable mode")
        }
        XCTAssertEqual(options.mode.outputName, "wrap_row_query")
        XCTAssertFalse(options.enforceGate)
    }

    // Gate promotion for wrap modes is map node 6. Until a hosted budget exists, --gate
    // must be REJECTED rather than silently accepted against a hand-typed number - the
    // failure mode AGENTS.md records in bold for slices 27/31/33/35/37.
    func testGateIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(["--wrap-row-query", "--gate"]) else {
            return XCTFail("--gate must be rejected for a non-gateable mode")
        }
        XCTAssertTrue(message.contains("wrap_row_query"), "message should name the mode: \(message)")
    }

    func testCombiningWithAnEarlierModeFlagIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(
            ["--wrap-compute", "--wrap-row-query"]) else {
            return XCTFail("two mode flags must be rejected")
        }
        XCTAssertTrue(message.contains("--wrap-row-query"), "message should name the flag: \(message)")
    }

    func testIsNotGateable() {
        XCTAssertFalse(BenchmarkMode.wrapRowQuery.isGateable)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryOptionsTests > /tmp/slice53-task7-red.txt 2>&1; then
  echo "UNEXPECTED PASS"
else
  echo "EXPECTED RED"; rg -n "cannot find|has no member|error:" /tmp/slice53-task7-red.txt | head -5
fi
```

Expected: `EXPECTED RED` — `type 'BenchmarkMode' has no member 'wrapRowQuery'`.

- [ ] **Step 3: Wire the mode into `BenchmarkOptions.swift`**

Five edits in this file:

1. Add `case wrapRowQuery` to the `BenchmarkMode` enum, after `case wrapCompute`.
2. Add to `outputName`:

```swift
        case .wrapRowQuery:
            return "wrap_row_query"
```

3. Add `.wrapRowQuery` to the `false` arm of `isGateable`, and **correct the stale comment above it** — it says "The three false cases" while there are already four on `main` (slice 50 added `wrapCompute` and left the count):

```swift
    // The five false cases have no budgets by nature: --range-only is a component
    // timing, the two memory modes assert an invariant / observe RSS rather than
    // measure latency, and the two wrap modes are observational until map node 6
    // promotes them.
```

4. Add `.wrapRowQuery` to the `.scrollFrame` arm of `absoluteCeiling`, and update its comment from four non-gateable modes to five:

```swift
    // The five non-gateable modes (rangeOnly, memoryShape, memoryObservation,
    // wrapCompute, wrapRowQuery) must classify under a total function but never reach the
    // gate, so their value is inert. Worth knowing: the class-membership pin filters on
    // isGateable and therefore does NOT cover them. Their class is a compile-time
    // obligation, not a pinned one -- do not expect a test to catch a wrong choice here.
```

5. Add the usage line and the parse case:

```swift
      --wrap-row-query      Run the observational wrap-aware y->row position query benchmark (not gateable).
```

```swift
            case "--wrap-row-query":
                if mode != .pipeline {
                    return .failure("--wrap-row-query cannot be combined with another mode")
                }
                mode = .wrapRowQuery
```

Also add `[--wrap-row-query]` to the `Usage:` line.

- [ ] **Step 4: Add the two exhaustive-switch cases**

`Sources/ViewportBenchmarks/BenchmarkProgram.swift`, in `runBenchmarks(options:)`:

```swift
    case .wrapRowQuery:
        return runWrapRowQueryBenchmarks()
```

`Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`, in the exhaustive switch at `:151`:

```swift
            case .wrapRowQuery:
                preconditionFailure("wrap row query mode uses runWrapRowQueryBenchmarks")
```

- [ ] **Step 5: Write the benchmark**

Create `Sources/ViewportBenchmarks/WrapRowQueryBenchmark.swift`:

```swift
import TextEngineCore

struct WrapRowQueryScenario {
    let name: String
    let lineCount: Int
    let wrapWidth: Double
    let clamped: Bool
}

/// Folds ALL THREE returned fields under distinct multipliers. Folding one index would
/// let a release build delete the other two and still print a plausible number --
/// `PointGeometryChecksumTests` exists because exactly that reversion once passed
/// silently. Pinned by `WrapRowQueryChecksumTests`.
func wrapRowQueryChecksum(_ location: VisualRowLocation) -> Int {
    var value = 0
    value &+= location.globalRow &* 1
    value &+= location.logicalLine &* 31
    value &+= location.rowInLine &* 131
    return value
}

/// Observational only: NOT gateable, NOT wired into CI. The latency tokens are
/// deliberately PREFIXED (`query_p95_ns=`), following `--wrap-compute`: the harvester
/// matches `p95_ns=` as a substring but then requires the exact key, so a prefixed line
/// emits no corpus row even if it ever reached a hosted log. Map node 6 flips this to the
/// bare shape in the same slice that adds the gate step and the corpus rows.
@available(macOS 13.0, *)
func runWrapRowQueryBenchmarks() -> Bool {
    let rowHeight = 16.0
    let cells = 20
    let advance = 8.0
    let samples = 2_000
    let clock = ContinuousClock()

    let scenarios: [WrapRowQueryScenario] = [
        // ∞ width -> one row per line: the no-wrap-equivalent geometry.
        WrapRowQueryScenario(name: "uniform_1k", lineCount: 1_000, wrapWidth: .infinity, clamped: false),
        WrapRowQueryScenario(name: "uniform_100k", lineCount: 100_000, wrapWidth: .infinity, clamped: false),
        // Narrow -> totalRows >> lineCount, so the two searches differ in depth.
        WrapRowQueryScenario(name: "narrow_100k", lineCount: 100_000, wrapWidth: 40.0, clamped: false),
        // The branch Decision 7 routes through the layout search rather than short-circuiting.
        WrapRowQueryScenario(name: "clamped_100k", lineCount: 100_000, wrapWidth: 40.0, clamped: true),
    ]

    for scenario in scenarios {
        let layout = BenchmarkWrapLayout(
            lineCount: scenario.lineCount, cells: cells, advance: advance,
            rowHeight: rowHeight, wrapWidth: scenario.wrapWidth)
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        let totalHeight = Double(totalRows) * rowHeight

        var querySamples: [Int64] = []
        querySamples.reserveCapacity(samples)
        var checksum = 0

        for sample in 0..<samples {
            let y: Double
            if scenario.clamped {
                let offset = Double(deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: 10_000))
                y = sample % 2 == 0 ? -(offset + 1.0) : totalHeight + offset
            } else {
                let row = deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: totalRows)
                y = Double(row) * rowHeight + rowHeight / 2.0
            }
            let elapsed = clock.measure {
                if case .row(let location) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) {
                    checksum &+= wrapRowQueryChecksum(location)
                }
            }
            querySamples.append(nanoseconds(elapsed))
        }

        querySamples.sort()
        print("mode=wrap_row_query scenario=\(scenario.name) total_rows=\(totalRows)"
            + " query_p95_ns=\(percentile(querySamples, numerator: 95, denominator: 100))"
            + " query_p99_ns=\(percentile(querySamples, numerator: 99, denominator: 100))"
            + " checksum=\(checksum)")
    }
    return true
}
```

- [ ] **Step 6: Write the checksum test**

Create `Tests/ViewportBenchmarksTests/WrapRowQueryChecksumTests.swift`:

```swift
import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

/// Byte-identity guard for the observational mode's anti-dead-code checksum. A benchmark
/// whose result is never read can be deleted by a release build and still "run"; a
/// checksum that folds only one index has the same hole for the other two. Applied up
/// front here because `PointGeometryChecksumTests` exists precisely because a reversion to
/// an index-only fold once passed silently.
final class WrapRowQueryChecksumTests: XCTestCase {
    private func location(globalRow: Int, logicalLine: Int, rowInLine: Int) -> VisualRowLocation {
        VisualRowLocation(globalRow: globalRow, logicalLine: logicalLine, rowInLine: rowInLine, clamp: .inRange)
    }

    func testFoldsAllThreeFields() {
        let base = location(globalRow: 5, logicalLine: 3, rowInLine: 2)
        XCTAssertNotEqual(wrapRowQueryChecksum(base),
                          wrapRowQueryChecksum(location(globalRow: 6, logicalLine: 3, rowInLine: 2)),
                          "globalRow must affect the checksum")
        XCTAssertNotEqual(wrapRowQueryChecksum(base),
                          wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 4, rowInLine: 2)),
                          "logicalLine must affect the checksum")
        XCTAssertNotEqual(wrapRowQueryChecksum(base),
                          wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 3, rowInLine: 3)),
                          "rowInLine must affect the checksum")
    }

    // Distinct multipliers: an additive fold would make (6,3,2) and (5,4,2) collide, which
    // is how an index-only regression hides.
    func testFieldsAreNotInterchangeable() {
        XCTAssertNotEqual(wrapRowQueryChecksum(location(globalRow: 6, logicalLine: 3, rowInLine: 2)),
                          wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 4, rowInLine: 2)))
        XCTAssertNotEqual(wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 4, rowInLine: 2)),
                          wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 3, rowInLine: 3)))
    }

    func testKnownValue() {
        // 5*1 + 3*31 + 2*131 = 5 + 93 + 262 = 360
        XCTAssertEqual(wrapRowQueryChecksum(location(globalRow: 5, logicalLine: 3, rowInLine: 2)), 360)
    }
}
```

- [ ] **Step 7: Run everything and the mode itself**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test > /tmp/slice53-task7-full.txt 2>&1; then
  echo "SUITE RED"; rg -n "error:|XCTAssert" /tmp/slice53-task7-full.txt | head -20
else
  echo "suite green"
fi
if ! swift build -c release 2>&1 | tail -3; then echo "RELEASE BUILD FAILED"; fi
swift run -c release ViewportBenchmarks -- --wrap-row-query
```

Expected: four `mode=wrap_row_query scenario=… total_rows=… query_p95_ns=… query_p99_ns=… checksum=…` lines, all four checksums non-zero.

Then assert the mode is absent from CI and inert to the harvester:

```bash
cd /Users/aabanschikov/swift-text-engine
CI_HIT="$(rg -n 'wrap-row-query|wrap_row_query' .github/workflows/swift-ci.yml || true)"
if [ -z "$CI_HIT" ]; then
  echo "PASS: absent from swift-ci.yml"
else
  echo "FAIL: mode reached CI:"; echo "$CI_HIT"
fi
BARE="$(swift run -c release ViewportBenchmarks -- --wrap-row-query | rg -o '(^| )p95_ns=[0-9]+' || true)"
if [ -z "$BARE" ]; then
  echo "PASS: no bare p95_ns= token — harvester emits no row"
else
  echo "FAIL: bare latency token present:"; echo "$BARE"
fi
```

Expected: both `PASS` lines. The second is the shape check that makes barrier 2 real rather than assumed.

- [ ] **Step 8: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/ViewportBenchmarks/WrapRowQueryBenchmark.swift \
        Sources/ViewportBenchmarks/BenchmarkOptions.swift \
        Sources/ViewportBenchmarks/BenchmarkProgram.swift \
        Sources/ViewportBenchmarks/SyntheticBenchmarks.swift \
        Tests/ViewportBenchmarksTests/WrapRowQueryOptionsTests.swift \
        Tests/ViewportBenchmarksTests/WrapRowQueryChecksumTests.swift
git commit -m "feat: --wrap-row-query observational benchmark mode

Four scenarios over the benchmark-local wrap layout: uniform 1k/100k (one row
per line), narrow 100k (totalRows >> lineCount, so the two searches differ in
depth) and clamped 100k (the edge branch that still searches the layout axis).

Not gateable and not wired into CI - gate promotion is map node 6. Latency
tokens are prefixed (query_p95_ns=), so the harvester's exact-key extraction
emits no corpus row even if the line ever reached a hosted log; a test asserts
no bare p95_ns= token is printed.

The checksum folds all three returned fields under distinct multipliers, pinned
by WrapRowQueryChecksumTests - the PointGeometryChecksumTests lesson applied up
front rather than after a silent reversion.

Also corrects two stale comments on the switches this touches: isGateable said
'three false cases' since slice 50 added a fourth, and absoluteCeiling's
non-gateable count goes four -> five."
```

---

## Task 8: Documentation, ledger, and the verification record

Spec Documentation Updates and Verification; AC3, AC11, AC12, AC13.

**Files:**
- Modify: `AGENTS.md` (architecture paragraph, flag list, commands block, `--gate` rejection list)
- Modify: `docs/superpowers/debt-ledger.md` (new O(1)-hook row; D-20 four → five)
- Create: `docs/superpowers/verification/2026-08-09-wrap-row-query.md`

**Interfaces:**
- Consumes: the recorded outputs from Tasks 1-7.
- Produces: the evidence base the post-slice review reads.

- [ ] **Step 1: Add node 3 to `AGENTS.md`'s architecture section**

After the visual-row layer (node 2) paragraph, add:

```markdown
`ViewportVirtualizer.visualRowAt(y:layout:)` is the **y→row layer** (node 3): the
wrap-aware `lineAt` analog over the visual-row axis. It runs `compute(_:layout:)`'s
layout ladder — the *same* extracted helper, so the two entry points accept and
reject exactly the same layouts by construction — then delegates the row-axis search
to `lineAt` over `UniformLineMetrics(totalRows, rowHeight)` and names the located row
in **both** coordinate systems: `globalRow` (the index space `compute(_:layout:)`
ranges over) plus `logicalLine`/`rowInLine` (what `VisualRow` and
`DocumentVisualRowCursor` speak), with the reused `LineLocation.Clamp`. It adds no
new search: one row-axis search, one `logicalLine(containingVisualRow:)` search
(provider-overridable, binary-search default), one O(1) `firstVisualRow` probe —
`<= ceilLog2(lineCount) + 4` probes on the layout axis, O(1) core memory. Clamped
queries take **no special case**: both edges flow through the same two provider calls
as an in-range hit, so unlike the no-wrap axis a clamped query *does* search. At
`wrapWidth = ∞` (or any width no line exceeds) it is bit-identical to `lineAt` over a
uniform axis (equivalence oracle). Geometry — the row's cell span, `y`/`height`, and
within-row fraction — is a later companion, on the `lineAt`→`lineGeometryAt` pattern.
`--wrap-row-query` is its observational, **non-gateable** benchmark mode.
```

- [ ] **Step 2: Add the flag to `AGENTS.md`'s commands and flag lists**

In the commands block, after the `--wrap-compute` line:

```bash
swift run -c release ViewportBenchmarks -- --wrap-row-query   # observational wrap y->row query benchmark (not gateable)
```

In the "Benchmark flags:" paragraph add `--wrap-row-query` to the list, and add it to the `--gate` **rejected** enumeration alongside `--range-only`, `--memory-shape`, `--memory-observation`, `--wrap-compute`.

- [ ] **Step 3: Update the debt ledger**

Append a new row (id `D-22`) for the deferred optimization, recording **both** paths so the future slice chooses rather than inherits:

```markdown
| D-22 | [slice 53 spec](specs/2026-08-09-wrap-row-query-design.md), Decision 2 | P3 | Uniform-axis inverse hooks are unimplemented: `UniformLineMetrics` (`LineMetricsSource.swift:103`) overrides neither `lineIndex(containingOffset:)` nor `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`, so every consumer pays an O(log N) binary search where a uniform axis answers by division with a bounded ±1 correction. Two paths, and they differ in cost: making the **public** type native moves four gated modes' hot path (`line_query`, `line_geometry_query`, `point_query`, `point_geometry_query` all construct it for their `uniform_*` scenarios) and therefore drags a budget re-derivation in the same PR per the headroom-ceiling rule; an **internal** `UniformRowAxis` constructed only by `compute(_:layout:)` and `visualRowAt` moves no gated mode and needs none. Would retire the wrap arc's "O(log totalRows), not literally width-independent" correction on the row axis. Natural home for **D-13** (it edits `LineMetricsSource.swift`, where two of the three binary-search copies live). Watch-item for whichever path is taken: node 2's ∞ oracle compares `compute(_:layout:)` against `UniformLineMetrics`, so a division-based wrap axis would make that oracle compare two different search implementations — stronger when they agree, and the first place a ±1 rounding disagreement surfaces | open |
```

Then update **D-20**'s statement: `rangeOnly`, `memoryShape`, `memoryObservation`, and `wrapCompute` become five modes with the addition of `wrapRowQuery`, and note that slice 53 added the fifth.

- [ ] **Step 4: Write the verification record**

Create `docs/superpowers/verification/2026-08-09-wrap-row-query.md` with the actual commands and their actual output. Required sections:

1. `swift test` — full suite, with the count, and the baseline count from Task 1 Step 1 for comparison.
2. `swift build -c release`.
3. `rg -n "Foundation" Sources/TextEngineCore` — empty.
4. All **twelve** blocking gates, each `gate=pass`. This slice touches no gated code path, so any movement is a finding.
5. `--wrap-row-query` output, all four scenarios including checksums.
6. `--wrap-compute` — **smoke run only**, explicitly not evidence about the Decision 5 extraction. Copy the spec's three reasons (`total_rows` read off the provider at `WrapComputeBenchmark.swift:73`; drained rows never printed, `:92` fires only on `Int.min`; `.failure` silent because `:85` has no `else`).
7. `--memory-shape` — `invariant=pass`.
8. `./.github/scripts/cross-target-compile.sh --self-test` — noting it compiles nothing and is **not** portability evidence.
9. **The six falsifiability drills**, each with its observed red, plus Task 2 Step 4's refactor-safety check (recorded separately — it is not one of the six).
10. Hosted proof at **step level** on both the PR-head run and the post-merge push run: the host job's twelve `gate=pass` lines and `swift test` count; the iOS job's two target compiles; the WASM job's four `result=pass … blocking=true` lines.

Sections 1-9 are fillable now; section 10 is filled after the PR runs.

- [ ] **Step 5: Full verification sweep**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test > /tmp/slice53-final-test.txt 2>&1; then echo "SUITE RED"; else echo "suite green"; fi
rg -n "Executed [0-9]+ tests" /tmp/slice53-final-test.txt | tail -2
if ! swift build -c release > /tmp/slice53-final-build.txt 2>&1; then echo "RELEASE BUILD RED"; else echo "release build green"; fi
FOUNDATION="$(rg -n 'Foundation' Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "PASS: Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION"; fi
```

Then the twelve gates, each checked on its own exit status:

```bash
cd /Users/aabanschikov/swift-text-engine
for flag in "" "--realistic-provider" "--variable-height" "--variable-height-mutation" \
            "--structural-mutation" "--bulk-structural-mutation" "--line-query" \
            "--line-geometry-query" "--column-query" "--column-geometry-query" \
            "--point-query" "--point-geometry-query"; do
  if ! swift run -c release ViewportBenchmarks -- $flag --gate > "/tmp/slice53-gate$(echo "$flag" | tr -d ' -').txt" 2>&1; then
    echo "GATE RED: ${flag:-default}"
  else
    echo "gate=pass: ${flag:-default}"
  fi
done
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected: twelve `gate=pass:` lines and `invariant=pass`.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add AGENTS.md docs/superpowers/debt-ledger.md docs/superpowers/verification/2026-08-09-wrap-row-query.md
git commit -m "docs: AGENTS.md node 3, ledger D-22, and the slice 53 verification record

AGENTS.md gains the y->row layer paragraph (both coordinate systems, the shared
ladder, the probe bound, the clamp asymmetry, the infinity oracle) and
--wrap-row-query in the commands block, the flag list, and the --gate rejection
enumeration.

Ledger: D-22 records the deferred uniform-axis O(1) hook with BOTH paths - the
public one drags a budget re-derivation across four gated modes, the internal
one does not - plus the oracle watch-item and D-13's routing. D-20's
non-gateable count goes four -> five.

Verification records the twelve gates, the Foundation scan, the six drills with
their observed reds, and why --wrap-compute is a smoke run rather than evidence
about the ladder extraction."
```

---

## Plan Self-Review

**1. Spec coverage.** Every spec section maps to a task:

| Spec | Task |
|---|---|
| Decision 1 (result shape) | 3 |
| Decision 2 (O(1) hook deferred) | 8 (ledger D-22) |
| Decision 3 (rename) | 1 |
| Decision 4 (re-validates layout) | 3 (implementation), 4 (tests) |
| Decision 5 (shared ladder) | 2 (extraction), 4 (parity + drill 6) |
| Decision 6 (D-13 routed away) | 8 (ledger D-22 names it) |
| Decision 7 (clamp, no special case) | 3 (tests), 6 (clamp asymmetry pin) |
| Decision 8 (no shipped provider) | 3-7 — all conformers are test- or benchmark-local |
| Decision 9 (file placement) | File Structure + Tasks 1, 3, 7 |
| Component Design (probe bound, GIGO, trusted prefix sum) | 3 (implementation + comments), 6 (bound) |
| Testing Strategy (7 suites) | 3, 4, 5, 6, 7 |
| Benchmark Mode / CI (3 barriers) | 7 (absent from CI + prefixed shape asserted; the `GateFloorTests` bijection barrier needs no new work) |
| Documentation Updates | 8 |
| Verification | 8 |
| AC1-AC13 | 1-8; AC12's six drills sit in Tasks 3 (1, 2), 4 (4, 6), 5 (3), 6 (5) |

**2. Placeholder scan.** No "TBD"/"TODO"/"similar to Task N". Every code step carries complete code; every assertion carries its expected output.

**3. Type consistency.** `VisualRowLocation(globalRow:logicalLine:rowInLine:clamp:)` is declared in Task 3 and used with that exact label order in Tasks 5, 6, 7. `VisualRowQuery` cases `.row`/`.empty`/`.failure` are matched identically throughout. `validateVisualRowLayout(_:)` is defined in Task 2 and called in Task 3 with the same unlabelled signature. `wrapRowQueryChecksum(_:)` is defined in Task 7's benchmark and consumed by Task 7's test. `BenchmarkWrapLayout(lineCount:cells:advance:rowHeight:wrapWidth:)` matches `WrapComputeBenchmark.swift:70`. `TestVisualRowLayout(lines:rowHeight:wrapWidth:)` and `RiggedVisualRowLayout(lineCount:rowHeight:wrapWidth:firstRow:)` match `VisualRowLayoutTestSupport.swift`.

**Two risks flagged for the implementer:**

1. Task 7's `testGateIsRejected` asserts the failure message contains `wrap_row_query`. The existing rejection is built from `mode.outputName` ("`--gate` cannot be combined with \(mode.outputName) mode"), so this holds — but if that message is ever reworded, fix the assertion rather than weakening it.
2. Task 6's probe bound has **zero slack** (14 allowed, 14 worst-case). That is intentional, and it means an implementation that adds even one probe — for instance the `(line, firstRow)`-returning variant the spec's Component Design considers and rejects — will redden it. That red would be correct: the spec commits to paying one probe twice, and changing that is a spec change, not a test change.
