# Slice 57 — Wrap Memory Shape Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give brief criterion 2 its first evidence — a wrap half of `--memory-shape` that asserts core-owned work stays bounded by the viewport at 100k and 1M lines — and repair the two measurements in the mode's existing half that cannot fail.

**Architecture:** The observable is **provider probes, not bytes** (spec Decision 1): every wrap entry point returns fixed-size values, so growth would show as calls into the layout source. A `CountingWrapLayout` in `Sources/ViewportBenchmarks` wraps any `VisualRowLayoutSource` and counts all six hooks; six scenarios (`{100k, 1M} x {inf, 40, 10}`) run `compute(_:layout:)`, `DocumentVisualRowCursor`, `visualRowAt` and `visualPointAt` through it and emit one line each. The mode's cross-scenario comparison becomes a **pure function over a declared expectation**, unit-testable the way `GateLogicTests` unit-tests the gate verdict. Nine ledger fold-ins land after the spine.

**Tech Stack:** Swift 6.0 (`swift-tools-version`), XCTest, bash (`#!/usr/bin/env bash`), awk, GitHub Actions.

**Spec:** [`docs/superpowers/specs/2026-09-04-wrap-memory-shape-design.md`](../specs/2026-09-04-wrap-memory-shape-design.md)

## Global Constraints

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty. This slice touches **no core source at all** — every new file lands in `Sources/ViewportBenchmarks` or a test target — but the scan is part of every verification.
- **Zero third-party dependencies.** XCTest only; every reader is hand-rolled.
- **Nothing measured moves.** The 46 gated scenario checksums must be byte-identical to `main`; no `p95BudgetNanoseconds` / `p99BudgetNanoseconds` literal changes; the corpus TSV is untouched; `--wrap-compute` / `--wrap-row-query` / `--wrap-point-query` checksums are byte-identical. `--memory-shape`'s five existing lines stay byte-identical **in full**, `touched_lines` included (spec §7).
- **Scratch directory.** Every command block that needs scratch space assigns `SCRATCH` **in that same block**. Each Bash invocation is a fresh shell.
- **This plan's own assertions obey `AGENTS.md`'s D-2 conventions.** No `${PIPESTATUS...}` array in any command block — agent shells here are zsh, where it expands empty and inverts a failed check into a pass. Assert with `if ! cmd > /dev/null 2>&1; then ... else ... fi`, with `[ -z "$(...)" ]`, or by redirecting to a file and reading `$?` on the next line. Never `echo "...=$?"` after `git diff --name-only`, `git status`, `gh`, `jq`, `sed -i`, or a pipeline. This plan is **non-exempt**: `swift test` lints it via `PlanLintTests`, so every task must carry a `**Guarantees added:**` block naming a drill for each guarantee it lists.
- **Every test fixture is unit-scale.** `swift test` must not build a 1M-line provider. The 100k/1M scenarios exist only inside `--memory-shape`; every test in this plan constructs its own small scenario (1 000-10 000 lines), which is why the runner takes a scenario value rather than reading a fixed list.

## File Structure

**Created:**

- `Sources/ViewportBenchmarks/CountingWrapLayout.swift` — `WrapProbeCounter` (reference box), `CountingWrapLayout` (six hooks + the by-argument `firstVisualRowAtLineCount`), `DefaultLogicalLineProbe` (how the wrapper counts the default `logicalLine` search's probes without copying the search), `LineProbeCounter` and `CountingLineMetrics` (the variable half's `touched_lines` repair).
- `Sources/ViewportBenchmarks/WrapMemoryShapeDiagnostics.swift` — `WrapMemoryShapeScenario`, `wrapMemoryShapeScenarios()`, `WrapMemoryShapeSummary`, `runWrapMemoryShapeScenario(_:)`, `formatWrapMemoryShapeSummary(_:invariantPasses:)`, `wrapMemoryShapeCrossScenarioFailures(_:)`, `wrapCoreOwnedBytesEstimate()`.
- `Tests/ViewportBenchmarksTests/CountingWrapLayoutTests.swift` — the counter's own guarantees.
- `Tests/ViewportBenchmarksTests/WrapMemoryShapeTests.swift` — per-scenario invariants at unit scale.
- `Tests/ViewportBenchmarksTests/MemoryShapeComparisonTests.swift` — the pure comparison functions over synthetic summaries.
- `Tests/ViewportBenchmarksTests/WrapComputeProbeCountTests.swift` — spec §4D, first pin.
- `Tests/ViewportBenchmarksTests/DocumentVisualRowCursorProbeCountTests.swift` — spec §4D, second pin.
- `docs/superpowers/verification/2026-09-04-wrap-memory-shape.md` — the record.

**Modified:**

- `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift` — the shared viewport constants, `MemoryShapeWindowContribution`, `memoryShapeComparisonFailures(_:)`, the `touched_lines` count on the variable path, and the driver calling both halves.
- `Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift` — rewritten onto `CountingWrapLayout`; its private copy deleted.
- `Tests/ViewportBenchmarksTests/GateLogicTests.swift` — D-19 vocabulary; D-20/D-21 class pins.
- `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` — D-43 payload; D-11 job-set pin.
- `Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift` — D-38 derived constant.
- `.github/workflows/swift-ci.yml` — D-43's one-line payload change.
- `.github/scripts/derive-gate-budgets.sh`, `harvest-gate-corpus.sh`, `detect-docs-only-pr.sh` — D-14 classification, D-15 dispatcher shape.
- `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md` — D-10 superseded banner.
- `AGENTS.md`, `docs/superpowers/debt-ledger.md`, `docs/superpowers/arcs/wrap.md` — documentation and ledger.

**Guarantee map (the plan is the authority; the spec's §6 is a lower bound):**

| Task | Guarantees |
|---|---|
| 1 | G8, G19, G22 |
| 2 | G1, G5, G13, G14, G15, G16 |
| 3 | G2, G3, G4, G6, G7, G17, G18 |
| 4 | G20, G21 |
| 5 | G9 |
| 6 | G12, G23 |
| 7 | G10 |
| 8 | G11, G24 |
| 9 | none |

G22, G23 and G24 are additions to the spec's list, found while planning: the probe **attribution** property of `CountingWrapLayout` (G22), the derived-constant property of D-38's fixture (G23), and D-15's dispatcher shape (G24).

---

### Task 1: the counting layouts, and the measurement the contract table needs

**Files:**
- Create: `Sources/ViewportBenchmarks/CountingWrapLayout.swift`
- Create: `Tests/ViewportBenchmarksTests/CountingWrapLayoutTests.swift`
- Modify: `Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift` (delete the private `ProbeCounter`/`CountingLayout` at lines 13-32, rewrite onto the shared type)

**Interfaces:**
- Consumes: `VisualRowLayoutSource` (six requirements: `lineCount`, `rowHeight`, `wrapWidth`, `visualRowCount(inLine:)`, `firstVisualRow(ofLine:)`, `logicalLine(containingVisualRow:)` — the last has a binary-search default in the core), `LineMetricsSource` (`lineCount`, `offset(ofLine:)`, plus two defaulted inverse hooks), `BenchmarkWrapLayout(lineCount:cells:advance:rowHeight:wrapWidth:)`, `drainVisualRows(_:layout:)`.
- Produces: `final class WrapProbeCounter` with `columnCount`, `columnOffset`, `canBreak`, `visualRowCount`, `firstVisualRow`, `logicalLine`, `firstVisualRowAtLineCount` (all `Int`, all `var`) and a computed `total: Int` summing the six hook counters (**not** the by-argument one, which is a subset of `firstVisualRow`); `struct CountingWrapLayout<Base: VisualRowLayoutSource>: VisualRowLayoutSource` with `init(base:counter:)`; `final class LineProbeCounter` with `offset: Int` and `distinctLines: Set<Int>`; `struct CountingLineMetrics<Base: LineMetricsSource>: LineMetricsSource`. Tasks 2, 3 and 4 all consume these.

**Guarantees added:** G8, G19, G22

- [ ] **Step 1: Write the failing test**

Create `Tests/ViewportBenchmarksTests/CountingWrapLayoutTests.swift`:

```swift
import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class CountingWrapLayoutTests: XCTestCase {
    // 64 lines x 8 cells at width 4 -> 2 rows per line, 128 rows. Small enough for
    // `swift test`, wide enough that every hook is reachable.
    private func base() -> BenchmarkWrapLayout {
        BenchmarkWrapLayout(lineCount: 64, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
    }

    private func input() -> VariableViewportInput {
        VariableViewportInput(
            scrollOffsetY: 40.0, viewportHeight: 100.0,
            overscanLinesBefore: 4, overscanLinesAfter: 4)
    }

    // G8. Every hook increments its own counter. A hook whose increment is missing reads
    // as "the core never called it", which is exactly the reading a memory-shape
    // assertion would take at face value. Each assertion names the entry point that
    // WITNESSES the hook (Decision 7), so a zero here is a measurement, not an absence of
    // instrumentation.
    func testEveryHookIsCounted() {
        let counter = WrapProbeCounter()
        let layout = CountingWrapLayout(base: base(), counter: counter)

        // Witness for firstVisualRow + the by-argument counter: compute's ladder.
        guard case let .success(range) = ViewportVirtualizer.compute(input(), layout: layout) else {
            return XCTFail("expected success")
        }
        XCTAssertGreaterThan(counter.firstVisualRow, 0, "compute probes firstVisualRow")

        // Witness for visualRowCount + logicalLine: the drain locates its start line and
        // walks lines.
        let drainCounter = WrapProbeCounter()
        let drainLayout = CountingWrapLayout(base: base(), counter: drainCounter)
        XCTAssertGreaterThan(drainVisualRows(range, layout: drainLayout), 0, "the drain streamed rows")
        XCTAssertGreaterThan(drainCounter.logicalLine, 0, "the drain dispatches logicalLine")
        XCTAssertGreaterThan(drainCounter.visualRowCount, 0, "the packer reads visualRowCount")

        // Witness for columnCount, columnOffset and canBreak: the packer measures cells.
        XCTAssertGreaterThan(drainCounter.columnCount, 0, "the packer reads columnCount")
        XCTAssertGreaterThan(drainCounter.columnOffset, 0, "the packer reads columnOffset")
        XCTAssertGreaterThan(drainCounter.canBreak, 0, "the packer reads canBreak")

        // `total` is the sum of the six hooks and MUST NOT double-count the by-argument
        // counter, which is a subset of firstVisualRow.
        XCTAssertEqual(
            drainCounter.total,
            drainCounter.columnCount + drainCounter.columnOffset + drainCounter.canBreak
                + drainCounter.visualRowCount + drainCounter.firstVisualRow + drainCounter.logicalLine)
    }

    // G19. The by-argument counter, which D-29's discharge rests on: "the drain performs
    // no compute" is "no probe with the argument lineCount happened", and six per-hook
    // totals cannot express it. Both halves asserted here so the property is pinned in
    // the shared type rather than only in its one consumer.
    func testFirstVisualRowAtLineCountIsCountedSeparately() {
        let computeCounter = WrapProbeCounter()
        _ = ViewportVirtualizer.compute(input(), layout: CountingWrapLayout(base: base(), counter: computeCounter))
        XCTAssertGreaterThan(
            computeCounter.firstVisualRowAtLineCount, 0,
            "compute reads totalRows via firstVisualRow(ofLine: lineCount)")
        XCTAssertLessThan(
            computeCounter.firstVisualRowAtLineCount, computeCounter.firstVisualRow,
            "the by-argument counter is a strict subset: the ladder also probes line 0")

        guard case let .success(range) = ViewportVirtualizer.compute(input(), layout: base()) else {
            return XCTFail("expected success")
        }
        let drainCounter = WrapProbeCounter()
        _ = drainVisualRows(range, layout: CountingWrapLayout(base: base(), counter: drainCounter))
        XCTAssertEqual(
            drainCounter.firstVisualRowAtLineCount, 0,
            "the drain never reads totalRows")
        XCTAssertGreaterThan(drainCounter.firstVisualRow, 0, "...but it does probe firstVisualRow")
    }

    // G22. ATTRIBUTION. The wrapper must not forward `logicalLine` to `base`: the core's
    // default implementation of that requirement runs a binary search that probes
    // `firstVisualRow` on WHATEVER layout it is given, so forwarding would run the search
    // against the unwrapped base and every probe it makes would go uncounted. The drain
    // over a 64-line document must therefore see MORE firstVisualRow probes than the one
    // its start-line lookup needs -- roughly log2(64) of them from the search alone.
    func testTheDefaultLogicalLineSearchIsAttributedToTheCounter() {
        guard case let .success(range) = ViewportVirtualizer.compute(input(), layout: base()) else {
            return XCTFail("expected success")
        }
        let counter = WrapProbeCounter()
        _ = drainVisualRows(range, layout: CountingWrapLayout(base: base(), counter: counter))
        XCTAssertEqual(counter.logicalLine, 1, "the drain dispatches logicalLine exactly once")
        // A forwarding wrapper would report ~1-2 here (the cursor's own probes only).
        XCTAssertGreaterThanOrEqual(
            counter.firstVisualRow, 6,
            "the default logicalLine search over 64 lines costs ~log2(64) firstVisualRow "
                + "probes and they must land in this counter, not in the unwrapped base")
    }

    // G8, metrics half. The variable path's repair needs the same instrument on the
    // vertical axis, with the same attribution property: UniformLineMetrics overrides
    // neither inverse hook, so their default searches probe offset(ofLine:) and those
    // probes must be counted here too.
    //
    // The +1 is named rather than absorbed. `VariableLineGeometryCursor` reads
    // `offset(ofLine: bufferStart)` in its init and `offset(ofLine: i + 1)` per row, so a
    // 90-line buffer resolves 91 distinct indices -- the extra one is the END BOUNDARY,
    // not a buffered line. `touched_lines` counts the buffered ones, so the runner
    // intersects with the range and the counter stays dumb. Asserting both halves here is
    // what stops the interpretation from being invented at the call site later.
    func testCountingLineMetricsCountsOffsetsAndDistinctLines() {
        let counter = LineProbeCounter()
        let metrics = CountingLineMetrics(
            base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: counter)
        let range = VirtualRange(
            visibleStart: 15, visibleEndExclusive: 95,
            bufferStart: 10, bufferEndExclusive: 100,
            isAtTop: false, isAtBottom: false)
        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        var streamed = 0
        while cursor.next() != nil { streamed += 1 }
        XCTAssertEqual(streamed, 90)
        XCTAssertGreaterThan(counter.offset, 0, "the cursor reads offsets")
        XCTAssertEqual(
            counter.distinctLines.count, 91,
            "90 buffered lines plus the end-boundary offset the last row's height needs")
        let buffered = counter.distinctLines.filter {
            $0 >= range.bufferStart && $0 < range.bufferEndExclusive
        }
        XCTAssertEqual(
            buffered.count, 90,
            "the cursor resolves exactly the buffered lines -- this is the count that "
                + "replaces `providerLines: bufferedLines`")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
swift test --filter CountingWrapLayoutTests > /tmp/slice57-t1-red.txt 2>&1
tail -20 /tmp/slice57-t1-red.txt
```

Expected: compile failure — `cannot find 'WrapProbeCounter' in scope`, `cannot find 'CountingWrapLayout' in scope`, `cannot find 'LineProbeCounter' in scope`, `cannot find 'CountingLineMetrics' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/ViewportBenchmarks/CountingWrapLayout.swift`:

```swift
import TextEngineCore

/// Probe counters for one measured operation. A CLASS so a non-mutating protocol witness
/// can record: `VisualRowLayoutSource`'s requirements are all non-mutating, and the
/// wrapper is a struct held by value inside the core's generic machinery, so a value-type
/// counter would record into copies nobody reads. This is the shape
/// `WrapComputeDrainTests` already used (slice 55a); it is generalized here rather than
/// copied (spec Decision 6).
final class WrapProbeCounter {
    var columnCount = 0
    var columnOffset = 0
    var canBreak = 0
    var visualRowCount = 0
    var firstVisualRow = 0
    var logicalLine = 0

    /// The BY-ARGUMENT counter. `firstVisualRow(ofLine: lineCount)` is the total-rows
    /// probe every `compute(_:layout:)` makes and the drain path structurally never does,
    /// so "the drain performs no compute" (D-29) is a statement about THIS number, not
    /// about `firstVisualRow`. Six per-hook totals cannot express it, which is why the
    /// generalization keeps it (spec Decision 6).
    var firstVisualRowAtLineCount = 0

    /// The six hooks. Deliberately excludes `firstVisualRowAtLineCount`, which is a
    /// subset of `firstVisualRow` and would double-count.
    var total: Int {
        columnCount + columnOffset + canBreak + visualRowCount + firstVisualRow + logicalLine
    }
}

/// Counts every call the core makes into a `VisualRowLayoutSource`.
///
/// The observable of `--memory-shape`'s wrap half (spec Decision 1): every wrap entry
/// point returns fixed-size values, so a core that started walking the document would
/// show up here and nowhere else.
struct CountingWrapLayout<Base: VisualRowLayoutSource>: VisualRowLayoutSource {
    let base: Base
    let counter: WrapProbeCounter

    var lineCount: Int { base.lineCount }
    var rowHeight: Double { base.rowHeight }
    var wrapWidth: Double { base.wrapWidth }

    func columnCount(inLine line: Int) -> Int {
        counter.columnCount += 1
        return base.columnCount(inLine: line)
    }

    func columnOffset(inLine line: Int, column: Int) -> Double {
        counter.columnOffset += 1
        return base.columnOffset(inLine: line, column: column)
    }

    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
        counter.canBreak += 1
        return base.canBreak(beforeColumn: column, inLine: line)
    }

    func visualRowCount(inLine line: Int) -> Int {
        counter.visualRowCount += 1
        return base.visualRowCount(inLine: line)
    }

    func firstVisualRow(ofLine line: Int) -> Int {
        counter.firstVisualRow += 1
        if line == base.lineCount { counter.firstVisualRowAtLineCount += 1 }
        return base.firstVisualRow(ofLine: line)
    }

    /// ATTRIBUTION, and the one place a forwarding wrapper would silently lie.
    ///
    /// `base.logicalLine(containingVisualRow:)` would run the core's default binary
    /// search against the UNWRAPPED base, so every `firstVisualRow` probe that search
    /// makes -- O(log lineCount) of them, the dominant term this mode measures -- would
    /// go uncounted, and every probe count in `--memory-shape` would understate by
    /// exactly the quantity the mode exists to watch.
    ///
    /// Swift gives a type no way to call the protocol-extension default it shadows, and
    /// `binarySearchLogicalLine` is internal to `TextEngineCore`, so the search cannot be
    /// invoked directly and must not be copied (that would be D-13's fourth copy, in the
    /// benchmark target). `DefaultLogicalLineProbe` closes it: it does not declare the
    /// requirement, so the core's default applies to IT, and its `firstVisualRow`
    /// forwards here, where the probes are counted.
    func logicalLine(containingVisualRow g: Int) -> Int {
        counter.logicalLine += 1
        return DefaultLogicalLineProbe(inner: self).logicalLine(containingVisualRow: g)
    }
}

/// A layout that deliberately does NOT declare `logicalLine(containingVisualRow:)`, so
/// the core's binary-search default is its witness. Exists only for the attribution
/// argument on `CountingWrapLayout.logicalLine`; it terminates because the default calls
/// `firstVisualRow`, never `logicalLine`.
private struct DefaultLogicalLineProbe<Inner: VisualRowLayoutSource>: VisualRowLayoutSource {
    let inner: Inner

    var lineCount: Int { inner.lineCount }
    var rowHeight: Double { inner.rowHeight }
    var wrapWidth: Double { inner.wrapWidth }
    func columnCount(inLine line: Int) -> Int { inner.columnCount(inLine: line) }
    func columnOffset(inLine line: Int, column: Int) -> Double {
        inner.columnOffset(inLine: line, column: column)
    }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
        inner.canBreak(beforeColumn: column, inLine: line)
    }
    func visualRowCount(inLine line: Int) -> Int { inner.visualRowCount(inLine: line) }
    func firstVisualRow(ofLine line: Int) -> Int { inner.firstVisualRow(ofLine: line) }
}

/// The vertical-axis counterpart, for the variable half's `touched_lines` repair
/// (spec §4B). `distinctLines` is what replaces `providerLines: bufferedLines`: the set
/// of lines the core actually resolved. It records EVERY index, boundary probes included;
/// the caller intersects with the buffer range, because the cursor legitimately reads one
/// offset past the buffer to size the last row. Bounded by the buffer (91 entries), and
/// benchmark-owned, not core-owned.
final class LineProbeCounter {
    var offset = 0
    var distinctLines: Set<Int> = []
}

struct CountingLineMetrics<Base: LineMetricsSource>: LineMetricsSource {
    let base: Base
    let counter: LineProbeCounter

    var lineCount: Int { base.lineCount }

    func offset(ofLine index: Int) -> Double {
        counter.offset += 1
        counter.distinctLines.insert(index)
        return base.offset(ofLine: index)
    }

    // The two inverse hooks are deliberately NOT declared: `UniformLineMetrics` overrides
    // neither, so the core's binary-search defaults apply here and their probes land in
    // `offset` above. Forwarding them would lose the same attribution
    // `CountingWrapLayout.logicalLine` protects.
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
swift test --filter CountingWrapLayoutTests > /tmp/slice57-t1-green.txt 2>&1
tail -5 /tmp/slice57-t1-green.txt
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Rewrite `WrapComputeDrainTests` onto the shared type**

Delete lines 13-32 of `Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift` (the private `ProbeCounter` class and `CountingLayout` struct) and replace every use. The assertions do not change — only the type they read:

```swift
    func testDrainBodyPerformsNoCompute() {
        // 64 lines x 8 cells at width 4 -> 2 rows per line, 128 rows.
        let base = BenchmarkWrapLayout(lineCount: 64, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        let input = VariableViewportInput(scrollOffsetY: 40.0, viewportHeight: 100.0, overscanLinesBefore: 4, overscanLinesAfter: 4)

        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: base) else {
            return XCTFail("expected success")
        }

        // Witness: compute(_:layout:) DOES make the probe this test counts, so a zero
        // below is a measurement and not an absence of instrumentation.
        let witness = WrapProbeCounter()
        _ = ViewportVirtualizer.compute(input, layout: CountingWrapLayout(base: base, counter: witness))
        XCTAssertGreaterThan(witness.firstVisualRowAtLineCount, 0, "compute must probe firstVisualRow(ofLine: lineCount), or the zero below is vacuous")

        let counter = WrapProbeCounter()
        let sink = drainVisualRows(range, layout: CountingWrapLayout(base: base, counter: counter))
        XCTAssertGreaterThan(sink, 0, "the drain must have streamed rows")
        XCTAssertGreaterThan(counter.firstVisualRow, 0, "the drain locates its start line through the layout")
        XCTAssertEqual(counter.firstVisualRowAtLineCount, 0, "the drain body must not compute a range")
    }
```

- [ ] **Step 6: Run the drain tests and the whole suite**

```bash
swift test --filter WrapComputeDrainTests > /tmp/slice57-t1-drain.txt 2>&1
tail -5 /tmp/slice57-t1-drain.txt
swift test > /tmp/slice57-t1-suite.txt 2>&1
tail -3 /tmp/slice57-t1-suite.txt
```

Expected: `WrapComputeDrainTests` 1 test 0 failures; full suite 0 failures with the count up by 4.

- [ ] **Step 7: Drill G8, G19 and G22 — three recorded reds**

Run each drill, capture the failure text into the record, then restore the file byte-identically (`git diff --quiet` must succeed afterwards).

Drill (a) for **G8**: delete `counter.canBreak += 1` from `canBreak(beforeColumn:inLine:)`. Expected red: `testEveryHookIsCounted` fails on "the packer reads canBreak" and the `total` identity still holds (so the missing increment reads as a hook the core never called — the exact misreading the guarantee prevents).

Drill (b) for **G19**: change `if line == base.lineCount` to `if false`. Expected red: `testFirstVisualRowAtLineCountIsCountedSeparately` fails on "compute reads totalRows via firstVisualRow(ofLine: lineCount)" and `WrapComputeDrainTests.testDrainBodyPerformsNoCompute` fails on its witness assertion — D-29's discharge going dark, which is what this drill exists to show.

Drill (c) for **G22**: replace the body of `logicalLine(containingVisualRow:)` with `counter.logicalLine += 1; return base.logicalLine(containingVisualRow: g)` — the forwarding version a reasonable implementer would write. Expected red: `testTheDefaultLogicalLineSearchIsAttributedToTheCounter` fails on the `>= 6` assertion, reporting roughly 1-2 probes. **This is the drill that matters most in the task**: without it the whole mode understates by its dominant term and every assertion still passes.

```bash
git diff --quiet -- Sources/ViewportBenchmarks/CountingWrapLayout.swift
if [ $? -eq 0 ]; then echo "restored=clean"; else echo "restored=DIRTY"; fi
```

- [ ] **Step 8: Measure the contract table (spec Decision 8)**

The six scenarios' probe counts and the provider build wall time are **measured here** and written into Task 2's constant and into the record. Create a temporary measurement test — it is deleted at the end of this step, and its output is the evidence:

```swift
// TEMPORARY (Task 1 Step 8). Deleted in this same step; its numbers go into the record
// and into `wrapMemoryShapeComputeProbes`.
import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class WrapMemoryShapeMeasurementScratch: XCTestCase {
    func testMeasure() {
        for lineCount in [100_000, 1_000_000] {
            for (label, width) in [("inf", Double.infinity), ("40", 40.0), ("10", 10.0)] {
                let start = ContinuousClock().now
                let base = BenchmarkWrapLayout(
                    lineCount: lineCount, cells: 80, advance: 1.0, rowHeight: 16.0, wrapWidth: width)
                let buildNanos = ContinuousClock().now - start
                let offsetRow = base.firstVisualRow(ofLine: lineCount / 2) + 3
                let y = 16.0 * Double(offsetRow)
                let input = VariableViewportInput(
                    scrollOffsetY: y, viewportHeight: 80.0 * 16.0,
                    overscanLinesBefore: 5, overscanLinesAfter: 5)

                let c1 = WrapProbeCounter()
                guard case let .success(range) = ViewportVirtualizer.compute(
                    input, layout: CountingWrapLayout(base: base, counter: c1)) else {
                    return XCTFail("compute failed at \(lineCount)/\(label)")
                }
                let c2 = WrapProbeCounter()
                _ = drainVisualRows(range, layout: CountingWrapLayout(base: base, counter: c2))
                let c3 = WrapProbeCounter()
                _ = ViewportVirtualizer.visualRowAt(y: y, layout: CountingWrapLayout(base: base, counter: c3))
                let c4 = WrapProbeCounter()
                _ = ViewportVirtualizer.visualPointAt(
                    x: 5.0, y: y, layout: CountingWrapLayout(base: base, counter: c4))

                print("measure lines=\(lineCount) width=\(label) build=\(buildNanos) "
                    + "compute=\(c1.total) drain=\(c2.total) row=\(c3.total) point=\(c4.total)")
            }
        }
    }
}
```

```bash
swift test --filter WrapMemoryShapeMeasurementScratch > /tmp/slice57-measure.txt 2>&1
grep '^measure ' /tmp/slice57-measure.txt
rm Tests/ViewportBenchmarksTests/WrapMemoryShapeMeasurementScratch.swift
```

Record every line. Three readings decide Task 2 and Task 3:

1. **`compute=` must be the same number in all six rows.** The code reading says **2** (`validateVisualRowLayout` probes `firstVisualRow(ofLine: 0)` and `firstVisualRow(ofLine: lineCount)`; `rowHeight` and `wrapWidth` are properties). If the measurement says otherwise, the measurement wins and Task 2's constant is whatever it says — but if the six rows disagree with EACH OTHER, stop: that falsifies spec Decision 2, not a constant, and the spec needs amending before Task 2.
2. **`drain=`, `row=` and `point=` deltas between 1M and 100k at the same width** must be small (a handful of levels). If any exceeds 32, do not raise the bound — read the code, per spec §8.
3. **`build=`** retires or confirms the §8 construction-cost risk. The expectation from `--wrap-compute`'s shipped `reindex_ns` is ~0.55 s for `1M/width 10` and ~1 s for all six.

- [ ] **Step 9: Commit**

```bash
git add Sources/ViewportBenchmarks/CountingWrapLayout.swift Tests/ViewportBenchmarksTests/CountingWrapLayoutTests.swift Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift
git commit -m "feat: CountingWrapLayout and CountingLineMetrics, with probe attribution"
```

---

### Task 2: the six wrap scenarios and their per-scenario invariants

**Files:**
- Create: `Sources/ViewportBenchmarks/WrapMemoryShapeDiagnostics.swift`
- Create: `Tests/ViewportBenchmarksTests/WrapMemoryShapeTests.swift`
- Modify: `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift` (the shared viewport constants near line 110; `runMemoryShapeDiagnostics()` at line 417 calls the new half)

**Interfaces:**
- Consumes: `CountingWrapLayout`, `WrapProbeCounter` (Task 1); `BenchmarkWrapLayout`; `ViewportVirtualizer.compute(_:layout:)`, `.visualRowGeometry(for:layout:)`, `.visualRowAt(y:layout:)`, `.visualPointAt(x:y:layout:)`; `memoryShapeRangeIsOrderedAndBounded(_:lineCount:)`.
- Produces: `memoryShapeViewportRows` (`Int`, 80), `memoryShapeOverscanBefore`/`memoryShapeOverscanAfter` (`Int`, 5), `expectedMemoryShapeWindow` (`Int`, derived = 90); `struct WrapMemoryShapeScenario` (`name`, `lineCount`, `wrapWidth`, `widthLabel`); `wrapMemoryShapeScenarios() -> [WrapMemoryShapeScenario]`; `struct WrapMemoryShapeSummary`; `runWrapMemoryShapeScenario(_:) -> WrapMemoryShapeSummary`; `formatWrapMemoryShapeSummary(_:invariantPasses:) -> String`. Task 3 consumes the summary type; Task 4 consumes nothing from here.

**Guarantees added:** G1, G5, G13, G14, G15, G16

- [ ] **Step 1: Write the failing test**

Create `Tests/ViewportBenchmarksTests/WrapMemoryShapeTests.swift`. Every fixture is 1 000 lines — the three widths give 1/2/8 rows per line there exactly as they do at 100k, and Decision 9's phase argument is size-independent by construction, so the unit fixture reproduces the real scenarios' `rowInLine` values (0/1/3):

```swift
import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class WrapMemoryShapeTests: XCTestCase {
    private func scenario(_ label: String, _ width: Double) -> WrapMemoryShapeScenario {
        WrapMemoryShapeScenario(
            name: "1k_lines_width_\(label)", lineCount: 1_000, wrapWidth: width, widthLabel: label)
    }

    private var allWidths: [(String, Double)] { [("inf", .infinity), ("40", 40.0), ("10", 10.0)] }

    // G13 + G14 + G1. The three per-scenario structural invariants, asserted together
    // because they describe one range: it is ordered and inside the row axis, the window
    // is 80/90 at every width (Decision 3), and the cursor streams the buffer exactly.
    func testEveryWidthReportsTheSameWindowAndStreamsIt() {
        for (label, width) in allWidths {
            let summary = runWrapMemoryShapeScenario(scenario(label, width))
            XCTAssertEqual(summary.visibleRows, 80, "\(label): visible window")
            XCTAssertEqual(summary.bufferedRows, 90, "\(label): buffered window")
            XCTAssertEqual(summary.streamedRows, summary.bufferedRows, "\(label): streamed == buffered")
            XCTAssertTrue(summary.rangeIsOrderedAndBounded, "\(label): range ordered and bounded")
            XCTAssertTrue(summary.baseInvariantPasses, "\(label): per-scenario invariants")
        }
    }

    // G5. The within-line walk is EXERCISED, not assumed. The `+ 3` offset puts the query
    // three rows past the middle line's first row, so rowInLine is 0/1/3 at inf/40/10
    // (Decision 9). Asserting the exact triple, not just `> 0` at width 10, is what makes
    // the fixture's own arithmetic falsifiable.
    func testTheQueryLandsOffARowStartAtEveryWrappedWidth() {
        XCTAssertEqual(runWrapMemoryShapeScenario(scenario("inf", .infinity)).pointRowInLine, 0)
        XCTAssertEqual(runWrapMemoryShapeScenario(scenario("40", 40.0)).pointRowInLine, 1)
        XCTAssertEqual(runWrapMemoryShapeScenario(scenario("10", 10.0)).pointRowInLine, 3)
    }

    // G15. x = 5.0 must land INSIDE the located row at every width, or point_query_probes
    // measures the clamp path at one width and the delegating path at another: a clamped
    // x costs 3 + 2 column probes and never reaches columnIndex(containingOffset:inLine:).
    // The narrowest row spans 10 layout units, so 5.0 is the fixture's whole margin.
    func testThePointQueryNeverClamps() {
        for (label, width) in allWidths {
            XCTAssertEqual(
                runWrapMemoryShapeScenario(scenario(label, width)).pointClamp, "none",
                "\(label): x must be in range, or the probe counts compare two branches")
        }
    }

    // G16. Criterion 2's second clause: the linear data is PROVIDER-owned. The measured
    // value is the prefix array's own footprint; the expectation is derived from the line
    // count, independently of the array. Identical across widths at a fixed size, because
    // the prefix has one entry per logical line whatever the width does to the row count.
    func testProviderOwnedBytesIsTheDerivedPrefixSize() {
        let expected = (1_000 + 1) * MemoryLayout<Int>.size
        for (label, width) in allWidths {
            XCTAssertEqual(
                runWrapMemoryShapeScenario(scenario(label, width)).providerOwnedBytes, expected,
                "\(label): provider-owned bytes")
        }
    }

    // The emitted line carries every token §4A names, in order. A token silently dropped
    // from the formatter is a column the hosted record cannot show and a future harvest
    // cannot read.
    func testTheEmittedLineCarriesEveryToken() {
        let line = formatWrapMemoryShapeSummary(
            runWrapMemoryShapeScenario(scenario("10", 10.0)), invariantPasses: true)
        for token in [
            "mode=memory_shape", "provider=wrap", "scenario=1k_lines_width_10", "line_count=1000",
            "wrap_width=10", "total_rows=8000", "visible_rows=80", "buffered_rows=90",
            "streamed_rows=90", "point_row_in_line=3", "point_clamp=none", "compute_probes=",
            "drain_probes=", "row_query_probes=", "point_query_probes=", "core_owned_bytes=",
            "provider_owned_bytes=", "invariant=pass", "checksum="
        ] {
            XCTAssertTrue(line.contains(token), "missing \(token) in: \(line)")
        }
    }

    // The infinite width must print `inf`, the spelling --wrap-compute already uses. Two
    // modes labelling the same width two ways is a reading hazard in the record and a
    // grouping hazard for node 6.
    func testInfiniteWidthPrintsInf() {
        let line = formatWrapMemoryShapeSummary(
            runWrapMemoryShapeScenario(scenario("inf", .infinity)), invariantPasses: true)
        XCTAssertTrue(line.contains("wrap_width=inf"), line)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
swift test --filter WrapMemoryShapeTests > /tmp/slice57-t2-red.txt 2>&1
tail -20 /tmp/slice57-t2-red.txt
```

Expected: compile failure — `cannot find 'WrapMemoryShapeScenario' in scope`, `cannot find 'runWrapMemoryShapeScenario' in scope`, `cannot find 'formatWrapMemoryShapeSummary' in scope`.

- [ ] **Step 3: Add the shared viewport constants**

In `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`, immediately after `let variableUniformMemoryShapeProviderName` (line 110), add:

```swift
// The viewport every scenario in this mode shares, and the window it implies. Written as
// a derivation rather than as the literal 90, because the mode-wide equality (spec
// Decision 4) is exactly the claim that all eleven scenarios share this configuration --
// and a comparison against a typed-in 90 would agree with a scenario list that no longer
// does.
let memoryShapeViewportRows = 80
let memoryShapeOverscanBefore = 5
let memoryShapeOverscanAfter = 5
let expectedMemoryShapeWindow =
    memoryShapeViewportRows + memoryShapeOverscanBefore + memoryShapeOverscanAfter
```

- [ ] **Step 4: Write the wrap half**

Create `Sources/ViewportBenchmarks/WrapMemoryShapeDiagnostics.swift`:

```swift
import TextEngineCore

// The wrap half of --memory-shape (spec §4A). Its own file and its own scenario list:
// MemoryObservationDiagnostics.swift:151 calls memoryShapeScenarios(), so appending wrap
// scenarios there would silently extend --memory-observation too (spec Decision 5).

let wrapMemoryShapeCells = 80
let wrapMemoryShapeAdvance = 1.0
let wrapMemoryShapeRowHeight = 16.0

/// `x` for the point query, measured from the located ROW's left edge. In range at all
/// three widths: the narrowest row spans 10 layout units (spec Decision 9).
let wrapMemoryShapePointX = 5.0

/// The layout-probe count `compute(_:layout:)` makes, MEASURED in Task 1 Step 8, not
/// predicted. `validateVisualRowLayout` probes `firstVisualRow(ofLine: 0)` and
/// `firstVisualRow(ofLine: lineCount)`; the boundary searches that follow run over
/// `UniformLineMetrics` and touch the layout not at all.
let wrapMemoryShapeComputeProbes = 2

/// The `<= 32` shape bound of spec Decision 2. A SHAPE bound, not a budget: not
/// corpus-derived, not recalibrated, and if it fires the answer is to read the code.
let wrapMemoryShapeProbeShapeBound = 32

struct WrapMemoryShapeScenario {
    let name: String
    let lineCount: Int
    let wrapWidth: Double
    let widthLabel: String
}

func wrapMemoryShapeScenarios() -> [WrapMemoryShapeScenario] {
    var scenarios: [WrapMemoryShapeScenario] = []
    for (sizeLabel, lineCount) in [("100k", 100_000), ("1m", 1_000_000)] {
        for (widthLabel, width) in [("inf", Double.infinity), ("40", 40.0), ("10", 10.0)] {
            scenarios.append(WrapMemoryShapeScenario(
                name: "\(sizeLabel)_lines_width_\(widthLabel)",
                lineCount: lineCount,
                wrapWidth: width,
                widthLabel: widthLabel))
        }
    }
    return scenarios
}

struct WrapMemoryShapeSummary {
    let scenarioName: String
    let lineCount: Int
    let widthLabel: String
    let totalRows: Int
    let visibleRows: Int
    let bufferedRows: Int
    let streamedRows: Int
    let pointRowInLine: Int
    let pointClamp: String
    let computeProbes: Int
    let drainProbes: Int
    let rowQueryProbes: Int
    let pointQueryProbes: Int
    let coreOwnedBytes: Int
    let providerOwnedBytes: Int
    let rangeIsOrderedAndBounded: Bool
    let baseInvariantPasses: Bool
    let checksum: Int
}

/// Continuity with the mode's two existing byte estimators, and evidence of nothing:
/// `MemoryLayout<T>.size` reports the INLINE footprint, so a cursor that captured an
/// array would report a pointer. The wrap half's evidence is the probe counts beside it
/// (spec Decision 1); this token exists so the wrap lines carry the same columns as their
/// siblings.
func wrapCoreOwnedBytesEstimate() -> Int {
    MemoryLayout<VirtualRange>.size
        + MemoryLayout<DocumentVisualRowCursor<BenchmarkWrapLayout>>.size
        + MemoryLayout<Int>.size * 2
}

private func wrapMemoryShapeFailureSummary(
    _ scenario: WrapMemoryShapeScenario, totalRows: Int
) -> WrapMemoryShapeSummary {
    WrapMemoryShapeSummary(
        scenarioName: scenario.name, lineCount: scenario.lineCount,
        widthLabel: scenario.widthLabel, totalRows: totalRows,
        visibleRows: 0, bufferedRows: 0, streamedRows: 0,
        pointRowInLine: -1, pointClamp: "unknown",
        computeProbes: 0, drainProbes: 0, rowQueryProbes: 0, pointQueryProbes: 0,
        coreOwnedBytes: wrapCoreOwnedBytesEstimate(), providerOwnedBytes: 0,
        rangeIsOrderedAndBounded: false, baseInvariantPasses: false, checksum: -1)
}

func runWrapMemoryShapeScenario(_ scenario: WrapMemoryShapeScenario) -> WrapMemoryShapeSummary {
    // Built here and released when this function returns: the prefix array is 8 MB at 1M
    // lines, and the six scenarios must not be resident at once (spec §4A).
    let base = BenchmarkWrapLayout(
        lineCount: scenario.lineCount, cells: wrapMemoryShapeCells,
        advance: wrapMemoryShapeAdvance, rowHeight: wrapMemoryShapeRowHeight,
        wrapWidth: scenario.wrapWidth)
    let totalRows = base.firstVisualRow(ofLine: base.lineCount)

    // Decision 9: the middle line's first row, plus three. Rows-per-line is uniform, so
    // the within-line phase is identical at every document size, and the `+ 3` puts the
    // query off a row-start so the within-line walk is exercised.
    let offsetRow = base.firstVisualRow(ofLine: scenario.lineCount / 2) + 3
    let scrollOffsetY = wrapMemoryShapeRowHeight * Double(offsetRow)
    let input = VariableViewportInput(
        scrollOffsetY: scrollOffsetY,
        viewportHeight: Double(memoryShapeViewportRows) * wrapMemoryShapeRowHeight,
        overscanLinesBefore: memoryShapeOverscanBefore,
        overscanLinesAfter: memoryShapeOverscanAfter)

    // One counter per entry point: the four numbers are separate observables, and summing
    // them would hide which one grew.
    let computeCounter = WrapProbeCounter()
    guard case let .success(range) = ViewportVirtualizer.compute(
        input, layout: CountingWrapLayout(base: base, counter: computeCounter)) else {
        return wrapMemoryShapeFailureSummary(scenario, totalRows: totalRows)
    }

    let drainCounter = WrapProbeCounter()
    var cursor = ViewportVirtualizer.visualRowGeometry(
        for: range, layout: CountingWrapLayout(base: base, counter: drainCounter))
    var streamedRows = 0
    var checksum = 0
    while let geometry = cursor.next() {
        streamedRows += 1
        checksum &+= geometry.row.endColumn &* 3
    }

    let rowCounter = WrapProbeCounter()
    let rowQuery = ViewportVirtualizer.visualRowAt(
        y: scrollOffsetY, layout: CountingWrapLayout(base: base, counter: rowCounter))
    if case let .row(located) = rowQuery {
        checksum &+= located.globalRow &* 5
        checksum &+= located.logicalLine &* 7
        checksum &+= located.rowInLine &* 13
    }

    let pointCounter = WrapProbeCounter()
    let pointQuery = ViewportVirtualizer.visualPointAt(
        x: wrapMemoryShapePointX, y: scrollOffsetY,
        layout: CountingWrapLayout(base: base, counter: pointCounter))
    var pointRowInLine = -1
    var pointClamp = "unknown"
    if case let .point(location) = pointQuery {
        pointRowInLine = location.row.rowInLine
        switch location.column {
        case let .cell(cell):
            switch cell.clamp {
            case .inRange: pointClamp = "none"
            case .clampedToLeft: pointClamp = "left"
            case .clampedToRight: pointClamp = "right"
            }
            checksum &+= cell.columnIndex &* 11
        case .blankLine:
            pointClamp = "blank_line"
        }
    }

    let visibleRows = range.visibleEndExclusive - range.visibleStart
    let bufferedRows = range.bufferEndExclusive - range.bufferStart
    // Measured against an independently derived expectation, the way providerBytesPasses
    // already works on the fixed half -- not `lineCount * size`, which the array's own
    // +1 entry would falsify (spec §4A invariant 7).
    let providerOwnedBytes = base.firstRow.count * MemoryLayout<Int>.size
    let expectedProviderBytes = (scenario.lineCount + 1) * MemoryLayout<Int>.size
    let rangePasses = memoryShapeRangeIsOrderedAndBounded(range, lineCount: totalRows)

    let baseInvariantPasses = rangePasses
        && visibleRows == memoryShapeViewportRows
        && bufferedRows == expectedMemoryShapeWindow
        && streamedRows == bufferedRows
        && computeCounter.total == wrapMemoryShapeComputeProbes
        && (scenario.wrapWidth > 10.0 || pointRowInLine > 0)
        && pointClamp == "none"
        && providerOwnedBytes == expectedProviderBytes

    return WrapMemoryShapeSummary(
        scenarioName: scenario.name, lineCount: scenario.lineCount,
        widthLabel: scenario.widthLabel, totalRows: totalRows,
        visibleRows: visibleRows, bufferedRows: bufferedRows, streamedRows: streamedRows,
        pointRowInLine: pointRowInLine, pointClamp: pointClamp,
        computeProbes: computeCounter.total, drainProbes: drainCounter.total,
        rowQueryProbes: rowCounter.total, pointQueryProbes: pointCounter.total,
        coreOwnedBytes: wrapCoreOwnedBytesEstimate(), providerOwnedBytes: providerOwnedBytes,
        rangeIsOrderedAndBounded: rangePasses, baseInvariantPasses: baseInvariantPasses,
        checksum: checksum)
}

func formatWrapMemoryShapeSummary(
    _ summary: WrapMemoryShapeSummary, invariantPasses: Bool
) -> String {
    var output = "mode=\(BenchmarkMode.memoryShape.outputName)"
    output += " provider=wrap"
    output += " scenario=\(summary.scenarioName)"
    output += " line_count=\(summary.lineCount)"
    output += " wrap_width=\(summary.widthLabel)"
    output += " total_rows=\(summary.totalRows)"
    output += " visible_rows=\(summary.visibleRows)"
    output += " buffered_rows=\(summary.bufferedRows)"
    output += " streamed_rows=\(summary.streamedRows)"
    output += " point_row_in_line=\(summary.pointRowInLine)"
    output += " point_clamp=\(summary.pointClamp)"
    output += " compute_probes=\(summary.computeProbes)"
    output += " drain_probes=\(summary.drainProbes)"
    output += " row_query_probes=\(summary.rowQueryProbes)"
    output += " point_query_probes=\(summary.pointQueryProbes)"
    output += " core_owned_bytes=\(summary.coreOwnedBytes)"
    output += " provider_owned_bytes=\(summary.providerOwnedBytes)"
    output += " invariant=\(invariantPasses ? "pass" : "fail")"
    output += " checksum=\(summary.checksum)"
    return output
}
```

Note on `wrap_width=`: the label is carried on the scenario rather than formatted from the `Double`, so the infinite case prints `inf` (the `--wrap-compute` spelling) instead of Swift's default rendering.

- [ ] **Step 5: Run it and watch it pass**

```bash
swift test --filter WrapMemoryShapeTests > /tmp/slice57-t2-green.txt 2>&1
tail -5 /tmp/slice57-t2-green.txt
```

Expected: 6 tests, 0 failures.

- [ ] **Step 6: Wire the wrap half into the driver and run the mode**

In `runMemoryShapeDiagnostics()`, after `let variableSummaries = ...`, add the wrap half and print its lines after the existing five. Task 3 replaces the comparison logic wholesale, so this step wires printing only:

```swift
    let wrapSummaries = wrapMemoryShapeScenarios().map(runWrapMemoryShapeScenario)
```

and, after the existing `for summary in summaries` loop:

```swift
    for summary in wrapSummaries {
        print(formatWrapMemoryShapeSummary(summary, invariantPasses: summary.baseInvariantPasses))
        if !summary.baseInvariantPasses { passed = false }
    }
```

```bash
swift build -c release > /tmp/slice57-t2-build.txt 2>&1
swift run -c release ViewportBenchmarks -- --memory-shape > /tmp/slice57-t2-mode.txt 2>&1
echo "mode_exit=$?"
cat /tmp/slice57-t2-mode.txt
```

Expected: eleven lines, all `invariant=pass`, `mode_exit=0`; six of them `provider=wrap` with `compute_probes` equal in all six and `point_row_in_line` 0/1/3 at inf/40/10 for both sizes. Record the whole block — this is AC1's evidence.

- [ ] **Step 7: Drill the six guarantees — six recorded reds**

Each drill runs, its failure text goes into the record, and the file is restored (`git diff --quiet` afterwards).

Drill (d) for **G1**: in the drain loop, `while let geometry = cursor.next(), streamedRows < 89`. Expected red: `testEveryWidthReportsTheSameWindowAndStreamsIt` fails on "streamed == buffered", 89 vs 90.

Drill (e) for **G13**: pass `lineCount: totalRows - 1` to `memoryShapeRangeIsOrderedAndBounded`. Expected red: the same test fails on "range ordered and bounded" — the range's `bufferEndExclusive` now exceeds the axis it is checked against.

Drill (f) for **G14**: change `scrollOffsetY` to `wrapMemoryShapeRowHeight * Double(offsetRow) + 8.0` (half a row). Expected red: "visible window" fails, 81 vs 80 — the alignment half of the invariant, which no other assertion covers.

Drill (g) for **G5**: drop the `+ 3` from `offsetRow`. Expected red: `testTheQueryLandsOffARowStartAtEveryWrappedWidth` fails at widths 40 and 10 (0 vs 1, 0 vs 3) — the within-line walk silently unexercised, which is the failure mode Decision 9 exists to prevent.

Drill (h) for **G15**: set `wrapMemoryShapePointX = 12.0`. Expected red: `testThePointQueryNeverClamps` fails at width 10 with `right` — and note in the record that the other two widths stay `none`, which is exactly why a single-width fixture could not catch it.

Drill (i) for **G16**: assert against `scenario.lineCount * MemoryLayout<Int>.size` (drop the `+ 1`). Expected red: `testProviderOwnedBytesIsTheDerivedPrefixSize` fails, 8008 vs 8000.

```bash
git diff --quiet -- Sources/ViewportBenchmarks/WrapMemoryShapeDiagnostics.swift
if [ $? -eq 0 ]; then echo "restored=clean"; else echo "restored=DIRTY"; fi
```

- [ ] **Step 8: Commit**

```bash
git add Sources/ViewportBenchmarks/WrapMemoryShapeDiagnostics.swift Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift Tests/ViewportBenchmarksTests/WrapMemoryShapeTests.swift
git commit -m "feat: the wrap half of --memory-shape, six scenarios over four entry points"
```

---

### Task 3: D-45 — the comparison that can fail, and the count that is a count

**Files:**
- Modify: `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift` (`runVariableMemoryShapeScenario` at line 342; `runMemoryShapeDiagnostics()` at line 417)
- Modify: `Sources/ViewportBenchmarks/WrapMemoryShapeDiagnostics.swift` (add the cross-scenario function)
- Create: `Tests/ViewportBenchmarksTests/MemoryShapeComparisonTests.swift`
- Modify: `docs/superpowers/specs/2026-09-04-wrap-memory-shape-design.md` (§4B, one sentence — see Step 1)

**Interfaces:**
- Consumes: `CountingLineMetrics`, `LineProbeCounter` (Task 1); `WrapMemoryShapeSummary`, `wrapMemoryShapeComputeProbes`, `wrapMemoryShapeProbeShapeBound`, `expectedMemoryShapeWindow` (Task 2); `MemoryShapeSummary` (existing, fields `scenarioName`, `bufferedLines`, `geometryLines`, `providerLines`).
- Produces: `struct MemoryShapeWindowContribution` (`scenarioName: String`, `bufferedWindow: Int`, `streamedElements: Int`, `touchedElements: Int?`); `memoryShapeComparisonFailures(_: [MemoryShapeWindowContribution]) -> [String]`; `wrapMemoryShapeCrossScenarioFailures(_: [WrapMemoryShapeSummary]) -> [String]`. Nothing later consumes these; the driver is their only production caller.

**Guarantees added:** G2, G3, G4, G6, G7, G17, G18

- [ ] **Step 1: Amend the spec's §4B sentence before writing code against it**

The spec says every summary contributes `(scenarioName, bufferedWindow, streamedElements, touchedElements)` and that "every one of the eleven must equal ... on all three counts". A wrap scenario has no third, independent traversal: it streams rows, and a "touched" count beside `streamed_rows` would be the same walk reported twice — the vacuity this repair exists to remove. Replace that sentence with:

> every summary — fixed, variable and wrap — contributes `(scenarioName, bufferedWindow, streamedElements, touchedElements)`, and every one of the eleven must equal the driver's declared `expectedMemoryShapeWindow` (90) on the first two. `touchedElements` is `Int?`: the five non-wrap scenarios have a third, independent traversal (a document-source walk, or the metrics the geometry cursor resolves) and must equal 90 on it too; a wrap scenario has none, and reporting its streamed rows a second time under another name would be exactly the vacuity this repair removes.

Commit this amendment on its own so the reasoning is reviewable apart from the code:

```bash
git add docs/superpowers/specs/2026-09-04-wrap-memory-shape-design.md
git commit -m "docs: amend spec 4B - a wrap scenario has no third traversal"
```

- [ ] **Step 2: Write the failing test**

Create `Tests/ViewportBenchmarksTests/MemoryShapeComparisonTests.swift`. Both comparisons are pure functions over summaries, so they are driven with synthetic values and a red arrives in seconds — the `GateLogicTests` seam, applied to this mode (spec Decision 4):

```swift
import XCTest
@testable import ViewportBenchmarks

final class MemoryShapeComparisonTests: XCTestCase {
    private func contribution(
        _ name: String, buffered: Int = 90, streamed: Int = 90, touched: Int? = 90
    ) -> MemoryShapeWindowContribution {
        MemoryShapeWindowContribution(
            scenarioName: name, bufferedWindow: buffered,
            streamedElements: streamed, touchedElements: touched)
    }

    private func wrapSummary(
        _ name: String, lineCount: Int, widthLabel: String,
        compute: Int = 2, drain: Int = 100, row: Int = 20, point: Int = 40,
        buffered: Int = 90, streamed: Int = 90, providerBytes: Int? = nil
    ) -> WrapMemoryShapeSummary {
        WrapMemoryShapeSummary(
            scenarioName: name, lineCount: lineCount, widthLabel: widthLabel,
            totalRows: lineCount, visibleRows: 80, bufferedRows: buffered,
            streamedRows: streamed, pointRowInLine: 3, pointClamp: "none",
            computeProbes: compute, drainProbes: drain, rowQueryProbes: row,
            pointQueryProbes: point, coreOwnedBytes: 64,
            providerOwnedBytes: providerBytes ?? ((lineCount + 1) * 8),
            rangeIsOrderedAndBounded: true, baseInvariantPasses: true, checksum: 1)
    }

    /// The six real scenarios' shape, all healthy: 10x the lines, a handful more probes.
    private func healthyWrapSet() -> [WrapMemoryShapeSummary] {
        [
            wrapSummary("100k_lines_width_inf", lineCount: 100_000, widthLabel: "inf", drain: 271, row: 20, point: 31),
            wrapSummary("100k_lines_width_40", lineCount: 100_000, widthLabel: "40", drain: 190, row: 20, point: 60),
            wrapSummary("100k_lines_width_10", lineCount: 100_000, widthLabel: "10", drain: 150, row: 20, point: 95),
            wrapSummary("1m_lines_width_inf", lineCount: 1_000_000, widthLabel: "inf", drain: 274, row: 23, point: 34),
            wrapSummary("1m_lines_width_40", lineCount: 1_000_000, widthLabel: "40", drain: 193, row: 23, point: 63),
            wrapSummary("1m_lines_width_10", lineCount: 1_000_000, widthLabel: "10", drain: 153, row: 23, point: 98),
        ]
    }

    func testAHealthySetHasNoFailures() {
        XCTAssertEqual(memoryShapeComparisonFailures((1...11).map { contribution("s\($0)") }), [])
        XCTAssertEqual(wrapMemoryShapeCrossScenarioFailures(healthyWrapSet()), [])
    }

    // G7. The mode-wide window equality, and specifically on `large_text` -- the one
    // scenario the old per-group byte comparison matched NEITHER branch of, so it fell to
    // `else { comparisonPasses = true }` and was not compared at all.
    func testAWrongWindowFailsOnAnyScenarioIncludingLargeText() {
        var contributions = (1...10).map { contribution("s\($0)") }
        contributions.insert(contribution("100k_lines_10mb_text", buffered: 89), at: 2)
        XCTAssertEqual(memoryShapeComparisonFailures(contributions), ["100k_lines_10mb_text"])
    }

    // G17. The baseline is DECLARED, not first-of-group. Corrupting the first element must
    // name the first element -- under a first-of-group comparison it would instead redden
    // the other ten and leave the guilty one green, which is the second defect of the
    // idiom that produced `x == x`.
    func testCorruptingTheFirstContributionNamesTheFirstContribution() {
        var contributions = (1...11).map { contribution("s\($0)") }
        contributions[0] = contribution("s1", streamed: 91)
        XCTAssertEqual(memoryShapeComparisonFailures(contributions), ["s1"])
    }

    // G18, comparison half. A wrap scenario reports no `touchedElements`; the five
    // non-wrap ones must, and a nil there must not be silently treated as a pass for a
    // scenario that HAS the traversal.
    func testTouchedElementsIsCheckedWhereItExists() {
        XCTAssertEqual(memoryShapeComparisonFailures([contribution("variable_1m", touched: 89)]), ["variable_1m"])
        XCTAssertEqual(memoryShapeComparisonFailures([contribution("wrap", touched: nil)]), [])
    }

    // G2. Flatness, against the declared constant. `compute(_:layout:)` probes the layout
    // twice whatever the document size or wrap width does, because its boundary searches
    // run over UniformLineMetrics and touch the layout not at all.
    func testANonFlatComputeProbeCountFailsTheOffendingScenario() {
        var set = healthyWrapSet()
        set[4] = wrapSummary("1m_lines_width_40", lineCount: 1_000_000, widthLabel: "40", compute: 3)
        XCTAssertEqual(wrapMemoryShapeCrossScenarioFailures(set), ["1m_lines_width_40"])
    }

    // G3. The shape bound. A linear term would show as roughly 10x -- hundreds of
    // thousands of probes -- so a delta of 33 is already far outside the handful of
    // binary-search levels the 10x jump really costs, and both scenarios of the pair are
    // named because the invariant is relational.
    func testAProbeDeltaAboveTheBoundFailsBothScenariosOfThePair() {
        var set = healthyWrapSet()
        set[3] = wrapSummary("1m_lines_width_inf", lineCount: 1_000_000, widthLabel: "inf", drain: 271 + 33)
        XCTAssertEqual(
            wrapMemoryShapeCrossScenarioFailures(set),
            ["100k_lines_width_inf", "1m_lines_width_inf"])
    }

    // G4. The buffered window is width-independent: rowHeight and viewportHeight are the
    // same in every scenario, so the visible window is 80 rows and the buffer 90 whatever
    // the wrap width does to the row count.
    func testAWidthDependentBufferFails() {
        var set = healthyWrapSet()
        set[2] = wrapSummary("100k_lines_width_10", lineCount: 100_000, widthLabel: "10", buffered: 100, streamed: 100)
        XCTAssertTrue(wrapMemoryShapeCrossScenarioFailures(set).contains("100k_lines_width_10"))
    }

    // G6. The walk is a WIDTH term and the counter tracks it: at a fixed size the narrow
    // width must cost more point-query probes than the infinite one. If it does not, the
    // within-line walk is not being counted, and every "the walk is bounded" reading in
    // the record rests on a number that never moves.
    func testTheWalkMustCostSomething() {
        var set = healthyWrapSet()
        set[2] = wrapSummary("100k_lines_width_10", lineCount: 100_000, widthLabel: "10", point: 31)
        XCTAssertEqual(
            wrapMemoryShapeCrossScenarioFailures(set),
            ["100k_lines_width_10", "100k_lines_width_inf"])
    }

    // G16, cross half. The prefix sum has one entry per LOGICAL line, so at a fixed size
    // the provider's footprint does not move with the width -- and across the 10x size
    // jump it does.
    func testProviderBytesAreASizeTermAndNotAWidthTerm() {
        var set = healthyWrapSet()
        set[1] = wrapSummary(
            "100k_lines_width_40", lineCount: 100_000, widthLabel: "40", providerBytes: 1_600_016)
        let failures = wrapMemoryShapeCrossScenarioFailures(set)
        XCTAssertTrue(failures.contains("100k_lines_width_40"))
        XCTAssertTrue(failures.contains("100k_lines_width_inf"))
    }

    // G18, measurement half. `touched_lines` on the variable path used to be
    // `providerLines: bufferedLines` -- the buffered window written twice. This drives the
    // real scenario at unit scale and asserts the counted value.
    func testTheVariablePathCountsTheLinesItTouches() {
        let summary = runVariableMemoryShapeScenario(lineCount: 1_000)
        XCTAssertEqual(summary.bufferedLines, 90)
        XCTAssertEqual(summary.geometryLines, 90)
        XCTAssertEqual(summary.providerLines, 90, "counted, not assigned")
    }
}
```

- [ ] **Step 3: Run it and watch it fail**

```bash
swift test --filter MemoryShapeComparisonTests > /tmp/slice57-t3-red.txt 2>&1
tail -20 /tmp/slice57-t3-red.txt
```

Expected: compile failure — `cannot find 'MemoryShapeWindowContribution' in scope`, `cannot find 'memoryShapeComparisonFailures' in scope`, `cannot find 'wrapMemoryShapeCrossScenarioFailures' in scope`.

- [ ] **Step 4: Write the comparison functions**

In `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`, beside the viewport constants Task 2 added:

```swift
/// One scenario's contribution to the mode-wide structural equality (D-45).
struct MemoryShapeWindowContribution {
    let scenarioName: String
    let bufferedWindow: Int
    let streamedElements: Int
    /// `nil` where the scenario has no third, INDEPENDENT traversal. A wrap scenario
    /// streams rows and has nothing beside them to count, so reporting the same walk
    /// twice under another name would be the vacuity this repair removes (spec §4B).
    let touchedElements: Int?
}

/// The mode-wide structural comparison, as a PURE function so `swift test` can drive it
/// against synthetic summaries -- the `GateLogicTests` seam, which is what this mode was
/// missing when its only cross-scenario comparison turned out to be `x == x`.
///
/// Compares against the DECLARED expectation, never against `summaries.first`. The
/// first-of-group idiom is what produced the vacuity, and it has a second defect: the
/// first element is never itself checked, so corrupting IT reddens everything else and
/// leaves the guilty line green.
func memoryShapeComparisonFailures(
    _ contributions: [MemoryShapeWindowContribution]
) -> [String] {
    var failed: [String] = []
    for contribution in contributions {
        var passes = contribution.bufferedWindow == expectedMemoryShapeWindow
            && contribution.streamedElements == expectedMemoryShapeWindow
        if let touched = contribution.touchedElements {
            passes = passes && touched == expectedMemoryShapeWindow
        }
        if !passes { failed.append(contribution.scenarioName) }
    }
    return failed
}
```

In `Sources/ViewportBenchmarks/WrapMemoryShapeDiagnostics.swift`:

```swift
/// The wrap half's cross-scenario invariants (spec §4A, 8-12). Pure, for the same reason
/// `memoryShapeComparisonFailures` is. Every comparison is either against a DECLARED
/// constant or between a named PAIR -- never against `summaries.first`.
func wrapMemoryShapeCrossScenarioFailures(
    _ summaries: [WrapMemoryShapeSummary]
) -> [String] {
    var failed: Set<String> = []

    // (8) flatness, and (10) the width-independent window: both against constants.
    for summary in summaries {
        if summary.computeProbes != wrapMemoryShapeComputeProbes {
            failed.insert(summary.scenarioName)
        }
        if summary.bufferedRows != expectedMemoryShapeWindow
            || summary.streamedRows != expectedMemoryShapeWindow {
            failed.insert(summary.scenarioName)
        }
    }

    // (9) the shape bound and (12) the size half of provider bytes: pair the two sizes at
    // each width. A relational invariant fails BOTH scenarios of its pair -- neither is
    // the baseline for the other.
    for widthLabel in Set(summaries.map(\.widthLabel)).sorted() {
        let atWidth = summaries.filter { $0.widthLabel == widthLabel }
        guard let small = atWidth.min(by: { $0.lineCount < $1.lineCount }),
              let large = atWidth.max(by: { $0.lineCount < $1.lineCount }),
              small.lineCount != large.lineCount else { continue }
        let deltas = [
            large.drainProbes - small.drainProbes,
            large.rowQueryProbes - small.rowQueryProbes,
            large.pointQueryProbes - small.pointQueryProbes,
        ]
        if deltas.contains(where: { $0 > wrapMemoryShapeProbeShapeBound })
            || large.providerOwnedBytes < small.providerOwnedBytes * 9 {
            failed.insert(small.scenarioName)
            failed.insert(large.scenarioName)
        }
    }

    for lineCount in Set(summaries.map(\.lineCount)).sorted() {
        let atSize = summaries.filter { $0.lineCount == lineCount }

        // (11) the walk is a width term: the narrow width costs more point probes than
        // the infinite one, or the counter is not tracking the walk at all.
        if let narrow = atSize.first(where: { $0.widthLabel == "10" }),
           let wide = atSize.first(where: { $0.widthLabel == "inf" }),
           narrow.pointQueryProbes <= wide.pointQueryProbes {
            failed.insert(narrow.scenarioName)
            failed.insert(wide.scenarioName)
        }

        // (12) the width half: one prefix entry per LOGICAL line, so the provider's
        // footprint does not move with the width.
        if Set(atSize.map(\.providerOwnedBytes)).count > 1 {
            for summary in atSize { failed.insert(summary.scenarioName) }
        }
    }

    return failed.sorted()
}
```

- [ ] **Step 5: Make the variable half's `touched_lines` a count**

In `runVariableMemoryShapeScenario`, replace the geometry traversal (lines 368-376) and the `providerLines: bufferedLines` field (line 386):

```swift
        // D-45's second half. `providerLines: bufferedLines` was the buffered window
        // written twice, so the mode-wide equality would have been satisfied here BY
        // CONSTRUCTION. The cursor legitimately reads one offset past the buffer to size
        // the last row, so the count is intersected with the range: `touched_lines` means
        // buffered lines resolved, not offsets probed.
        let probeCounter = LineProbeCounter()
        var cursor = ViewportVirtualizer.geometry(
            for: range, metrics: CountingLineMetrics(base: metrics, counter: probeCounter))
        var geometryLines = 0
        var checksum = 0
        while let geometry = cursor.next() {
            geometryLines += 1
            checksum &+= geometry.lineIndex
            checksum &+= Int(geometry.y)
            checksum &+= Int(geometry.height)
        }
        let touchedLines = probeCounter.distinctLines.filter {
            $0 >= range.bufferStart && $0 < range.bufferEndExclusive
        }.count
```

and `providerLines: touchedLines`. The printed value does not move — it *is* 90 — so the two `variable_uniform` lines stay byte-identical; only the number's provenance changes. `checksum` is unaffected: the counting wrapper returns `base`'s offsets unchanged.

- [ ] **Step 6: Rewrite the driver**

Replace `runMemoryShapeDiagnostics()`'s body so both comparisons feed every line:

```swift
func runMemoryShapeDiagnostics() -> Bool {
    let fixedSummaries = memoryShapeScenarios().map(runMemoryShapeScenario)
    let variableSummaries = [100_000, 1_000_000].map(runVariableMemoryShapeScenario)
    let summaries = fixedSummaries + variableSummaries
    let wrapSummaries = wrapMemoryShapeScenarios().map(runWrapMemoryShapeScenario)

    let contributions = summaries.map {
        MemoryShapeWindowContribution(
            scenarioName: $0.scenarioName, bufferedWindow: $0.bufferedLines,
            streamedElements: $0.geometryLines, touchedElements: $0.providerLines)
    } + wrapSummaries.map {
        MemoryShapeWindowContribution(
            scenarioName: $0.scenarioName, bufferedWindow: $0.bufferedRows,
            streamedElements: $0.streamedRows, touchedElements: nil)
    }
    let windowFailures = Set(memoryShapeComparisonFailures(contributions))
    let wrapCrossFailures = Set(wrapMemoryShapeCrossScenarioFailures(wrapSummaries))

    // The per-group byte comparison stays, SUBORDINATE now: it compares a constant with
    // itself, and deleting it would move nothing except the reasons a green line is
    // green. It keeps its first-of-group shape deliberately -- changing it would alter
    // no verdict and is not this slice's subject.
    let syntheticCoreOwnedBytes = summaries
        .filter { $0.providerName == MemoryShapeProviderKind.synthetic.outputName }
        .map(\.coreOwnedBytes)
    let variableCoreOwnedBytes = summaries
        .filter { $0.providerName == variableUniformMemoryShapeProviderName }
        .map(\.coreOwnedBytes)
    let comparisonCoreOwnedBytes = syntheticCoreOwnedBytes.first
    let comparisonVariableCoreOwnedBytes = variableCoreOwnedBytes.first
    var passed = true

    for summary in summaries {
        let comparisonPasses: Bool
        if summary.providerName == MemoryShapeProviderKind.synthetic.outputName,
           let comparisonCoreOwnedBytes {
            comparisonPasses = summary.coreOwnedBytes == comparisonCoreOwnedBytes
        } else if summary.providerName == variableUniformMemoryShapeProviderName,
                  let comparisonVariableCoreOwnedBytes {
            comparisonPasses = summary.coreOwnedBytes == comparisonVariableCoreOwnedBytes
        } else {
            comparisonPasses = true
        }

        let invariantPasses = summary.baseInvariantPasses
            && comparisonPasses
            && !windowFailures.contains(summary.scenarioName)
        print(formatMemoryShapeSummary(summary, invariantPasses: invariantPasses))
        if !invariantPasses { passed = false }
    }

    for summary in wrapSummaries {
        let invariantPasses = summary.baseInvariantPasses
            && !windowFailures.contains(summary.scenarioName)
            && !wrapCrossFailures.contains(summary.scenarioName)
        print(formatWrapMemoryShapeSummary(summary, invariantPasses: invariantPasses))
        if !invariantPasses { passed = false }
    }

    return passed
}
```

- [ ] **Step 7: Run the tests and the mode**

```bash
swift test --filter MemoryShapeComparisonTests > /tmp/slice57-t3-green.txt 2>&1
tail -5 /tmp/slice57-t3-green.txt
swift test > /tmp/slice57-t3-suite.txt 2>&1
tail -3 /tmp/slice57-t3-suite.txt
swift build -c release > /tmp/slice57-t3-build.txt 2>&1
swift run -c release ViewportBenchmarks -- --memory-shape > /tmp/slice57-t3-mode.txt 2>&1
echo "mode_exit=$?"
```

Expected: 10 tests in the new file, 0 failures; full suite 0 failures; `mode_exit=0`; eleven `invariant=pass` lines.

- [ ] **Step 8: Assert the five existing lines are byte-identical to `main`**

This is the fingerprint AC7 and spec §7 rest on, and it is the check that proves the `touched_lines` repair changed provenance and not value:

```bash
SCRATCH=/tmp/slice57-fingerprint
mkdir -p "$SCRATCH"
git stash push --keep-index --include-untracked -m slice57-fp > "$SCRATCH/stash.txt" 2>&1
git checkout main -- . > "$SCRATCH/checkout.txt" 2>&1
swift run -c release ViewportBenchmarks -- --memory-shape > "$SCRATCH/main-lines.txt" 2>&1
git checkout HEAD -- . > "$SCRATCH/restore.txt" 2>&1
git stash pop > "$SCRATCH/pop.txt" 2>&1
swift run -c release ViewportBenchmarks -- --memory-shape > "$SCRATCH/head-lines.txt" 2>&1
grep -v 'provider=wrap' "$SCRATCH/head-lines.txt" > "$SCRATCH/head-existing.txt"
if diff -u "$SCRATCH/main-lines.txt" "$SCRATCH/head-existing.txt" > "$SCRATCH/diff.txt" 2>&1; then
  echo "existing_lines=byte_identical"
else
  echo "existing_lines=CHANGED"
  cat "$SCRATCH/diff.txt"
fi
```

Expected: `existing_lines=byte_identical`. If it says `CHANGED`, read the diff before touching anything: a moved `touched_lines` means the counted value is not 90, which is the repair reporting a real defect (spec §7), not a fingerprint miss.

- [ ] **Step 9: Drill the seven guarantees**

G2, G3, G4, G6, G7, G17 are drilled by **inverting each test's expectation** — each already constructs the broken input, so the drill is to break the *function* instead and confirm the test names it:

Drill (j) for **G7**: make `memoryShapeComparisonFailures` return `[]` unconditionally. Expected red: four tests fail, `testAWrongWindowFailsOnAnyScenarioIncludingLargeText` among them.

Drill (k) for **G17**: replace the declared expectation with `contributions.first?.bufferedWindow ?? 0` — the first-of-group idiom, restored. Expected red: `testCorruptingTheFirstContributionNamesTheFirstContribution` fails with `[]` against `["s1"]`, and `testAHealthySetHasNoFailures` still passes. Record both halves: the second is what makes the first meaningful.

Drill (l) for **G2**: compare `computeProbes` against `summaries.first?.computeProbes` instead of the constant. Expected red: `testANonFlatComputeProbeCountFailsTheOffendingScenario` reports the other five scenarios instead of the offending one.

Drill (m) for **G3**: raise `wrapMemoryShapeProbeShapeBound` to 1_000. Expected red: `testAProbeDeltaAboveTheBoundFailsBothScenariosOfThePair` fails with `[]`.

Drill (n) for **G4**: drop the `bufferedRows`/`streamedRows` clause. Expected red: `testAWidthDependentBufferFails`.

Drill (o) for **G6**: delete the `narrow.pointQueryProbes <= wide.pointQueryProbes` block. Expected red: `testTheWalkMustCostSomething` fails with `[]`. **Note in the record why the spec's original drill for this guarantee was replaced:** "stop counting `columnOffset`" does not reliably redden, because `canBreak` is counted on the same walk and the inequality can survive it.

Drill (p) for **G18**: in `CountingLineMetrics.offset`, drop the `counter.distinctLines.insert(index)`. Expected red: `testTheVariablePathCountsTheLinesItTouches` fails with 0 vs 90 **while `bufferedLines` and `geometryLines` stay 90** — which is the whole point: the count is now independent of the window it is compared against.

```bash
git diff --quiet -- Sources/ViewportBenchmarks
if [ $? -eq 0 ]; then echo "restored=clean"; else echo "restored=DIRTY"; fi
```

- [ ] **Step 10: Commit**

```bash
git add Sources/ViewportBenchmarks Tests/ViewportBenchmarksTests/MemoryShapeComparisonTests.swift
git commit -m "fix: D-45 - a declared expectation, and a touched_lines that is counted"
```

---

### Task 4: the two unit-level pins the mode alone would not carry

**Files:**
- Create: `Tests/ViewportBenchmarksTests/WrapComputeProbeCountTests.swift`
- Create: `Tests/ViewportBenchmarksTests/DocumentVisualRowCursorProbeCountTests.swift`

**Interfaces:**
- Consumes: `CountingWrapLayout`, `WrapProbeCounter`, `wrapMemoryShapeComputeProbes` (Tasks 1-2); `BenchmarkWrapLayout`; `drainVisualRows(_:layout:)`.
- Produces: nothing consumed later.

**Guarantees added:** G20, G21

Spec §4D. `visualRowAt` and `visualPointAt` already have tighter, faster pins in `swift test` (`WrapRowQueryCountTests`, `WrapPointQueryCountTests`, bounds of `<= 14` and `3 + 2 + 1`), which is why this task adds none for them. The two properties with no unit-level pin today are exactly the two this slice invents.

- [ ] **Step 1: Write both failing tests**

Create `Tests/ViewportBenchmarksTests/WrapComputeProbeCountTests.swift`:

```swift
import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class WrapComputeProbeCountTests: XCTestCase {
    private func probes(lineCount: Int, wrapWidth: Double) -> WrapProbeCounter {
        let base = BenchmarkWrapLayout(
            lineCount: lineCount, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: wrapWidth)
        let counter = WrapProbeCounter()
        let input = VariableViewportInput(
            scrollOffsetY: 16.0 * Double(base.firstVisualRow(ofLine: lineCount / 2)),
            viewportHeight: 160.0, overscanLinesBefore: 5, overscanLinesAfter: 5)
        guard case .success = ViewportVirtualizer.compute(
            input, layout: CountingWrapLayout(base: base, counter: counter)) else {
            XCTFail("compute failed at \(lineCount)/\(wrapWidth)")
            return counter
        }
        return counter
    }

    // G20. compute(_:layout:)'s LAYOUT-probe count is a constant: the ladder probes
    // firstVisualRow(ofLine: 0) and firstVisualRow(ofLine: lineCount), and the two
    // boundary searches that follow run over UniformLineMetrics, which touches the layout
    // not at all. Nothing pinned this before: WrapComputeDrainTests counts the DRAIN, and
    // the ladder is otherwise covered only by its error cases.
    //
    // Scope, stated because the number invites the wrong reading: this is flat on the
    // LAYOUT axis. compute's own cost is O(log totalRows) -- UniformLineMetrics overrides
    // neither native inverse hook (D-22), so those boundary searches are binary searches
    // over offset(ofLine:) that this counter cannot see and does not claim to.
    func testComputeProbesTheLayoutAConstantNumberOfTimes() {
        for lineCount in [1_000, 10_000, 100_000] {
            for width in [Double.infinity, 40.0, 10.0, 4.0] {
                XCTAssertEqual(
                    probes(lineCount: lineCount, wrapWidth: width).total,
                    wrapMemoryShapeComputeProbes,
                    "lines=\(lineCount) width=\(width)")
            }
        }
    }

    // The constant is not an opaque 2: one of the two probes is the total-rows probe, and
    // saying so is what lets a reader check the number against the ladder rather than
    // against this test.
    func testOneOfTheTwoProbesIsTheTotalRowsProbe() {
        let counter = probes(lineCount: 10_000, wrapWidth: 10.0)
        XCTAssertEqual(counter.firstVisualRow, 2)
        XCTAssertEqual(counter.firstVisualRowAtLineCount, 1)
        XCTAssertEqual(counter.logicalLine, 0, "compute never dispatches the row inverse")
        XCTAssertEqual(counter.visualRowCount, 0, "compute reads the prefix, never a per-line count")
    }
}
```

Create `Tests/ViewportBenchmarksTests/DocumentVisualRowCursorProbeCountTests.swift`:

```swift
import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class DocumentVisualRowCursorProbeCountTests: XCTestCase {
    private func drainProbes(lineCount: Int, wrapWidth: Double) -> Int {
        let base = BenchmarkWrapLayout(
            lineCount: lineCount, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: wrapWidth)
        // The buffer starts at the middle line's first row, so the within-line phase is
        // the same at every document size (spec Decision 9) and what is left varying is
        // the logarithmic search.
        let input = VariableViewportInput(
            scrollOffsetY: 16.0 * Double(base.firstVisualRow(ofLine: lineCount / 2)),
            viewportHeight: 160.0, overscanLinesBefore: 5, overscanLinesAfter: 5)
        guard case let .success(range) = ViewportVirtualizer.compute(input, layout: base) else {
            XCTFail("compute failed at \(lineCount)/\(wrapWidth)")
            return -1
        }
        let counter = WrapProbeCounter()
        _ = drainVisualRows(range, layout: CountingWrapLayout(base: base, counter: counter))
        return counter.total
    }

    // G21. The drain's probe count does not grow with the DOCUMENT. It grows with the
    // width (fewer logical lines per buffered row), which is a different axis and the
    // subject of the mode's invariant 11. WrapComputeDrainTests pins that the drain
    // performs no compute; nothing pinned that it does not walk the document.
    //
    // A 100x jump in lineCount buys at most the extra levels of one binary search --
    // log2(100) is under 7, and the bound is deliberately loose against that.
    func testDrainProbesDoNotGrowWithTheDocument() {
        for width in [Double.infinity, 10.0] {
            let small = drainProbes(lineCount: 1_000, wrapWidth: width)
            let large = drainProbes(lineCount: 100_000, wrapWidth: width)
            XCTAssertGreaterThan(small, 0, "width=\(width): the drain must probe something")
            XCTAssertLessThanOrEqual(
                large - small, 32,
                "width=\(width): probes went \(small) -> \(large) across a 100x document")
        }
    }

    // ...and it DOES move with the width, so the bound above is not passing because the
    // counter is inert.
    func testDrainProbesMoveWithTheWidth() {
        XCTAssertNotEqual(
            drainProbes(lineCount: 10_000, wrapWidth: .infinity),
            drainProbes(lineCount: 10_000, wrapWidth: 4.0))
    }
}
```

- [ ] **Step 2: Run both and watch them pass**

These two are written GREEN from birth — they measure an implementation rather than specify new behaviour, which is exactly the class D-35 says must be drilled instead of red-first:

```bash
swift test --filter WrapComputeProbeCountTests > /tmp/slice57-t4a.txt 2>&1
tail -5 /tmp/slice57-t4a.txt
swift test --filter DocumentVisualRowCursorProbeCountTests > /tmp/slice57-t4b.txt 2>&1
tail -5 /tmp/slice57-t4b.txt
```

Expected: 2 tests each, 0 failures. If `testComputeProbesTheLayoutAConstantNumberOfTimes` fails, Task 1 Step 8's measured constant and this pin disagree — fix the constant, not the test.

- [ ] **Step 3: Drill G20 and G21**

Drill (q) for **G20**: in `validateVisualRowLayout` (`Sources/TextEngineCore/WrapViewportVirtualizer.swift`), add `_ = layout.visualRowCount(inLine: 0)` before the `return .rows(totalRows)`. Expected red: both tests in the file fail, 3 vs 2. Restore the core file byte-identically — this is the only drill in the slice that touches `Sources/TextEngineCore`, and leaving it behind would break the "this slice touches no core source" constraint.

Drill (r) for **G21**: in `DocumentVisualRowCursor.init`, add `for i in 0..<layout.lineCount { _ = layout.firstVisualRow(ofLine: i) }`. Expected red: `testDrainProbesDoNotGrowWithTheDocument` fails at both widths with a delta near 99 000 — a linear term, three orders of magnitude outside the bound, which is the separation spec Decision 2 claims.

```bash
git diff --quiet -- Sources/TextEngineCore
if [ $? -eq 0 ]; then echo "core_restored=clean"; else echo "core_restored=DIRTY"; fi
```

- [ ] **Step 4: Commit**

```bash
git add Tests/ViewportBenchmarksTests/WrapComputeProbeCountTests.swift Tests/ViewportBenchmarksTests/DocumentVisualRowCursorProbeCountTests.swift
git commit -m "test: pin compute's constant layout probes and the drain's independence from lineCount"
```

---

### Task 5: D-43 — the plan linter's rules must be alive on the PRs it guards

**Files:**
- Modify: `.github/workflows/swift-ci.yml` (the `Lint plan assertions` step)
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` (`testPlanLintStepIsBlockingAndUnguarded`, line 577)

**Interfaces:**
- Consumes: `hostJobSteps()`, `stepNamed(_:in:)` (existing helpers in `WorkflowShapeTests`).
- Produces: nothing consumed later.

**Guarantees added:** G9

D-43: the `Lint plan assertions` step is deliberately outside the docs-only guard, because a plan is `docs/**` and a plan-carrying PR would otherwise skip the linter entirely. But `--self-test` — the thing that proves the rules still *work* — runs only from `swift test`, which a docs-only PR skips. So on exactly the PRs the unguarded step exists for, nothing checks that the rules are alive.

- [ ] **Step 1: Change the pin first, and watch it fail**

In `WorkflowShapeTests.testPlanLintStepIsBlockingAndUnguarded`, change the expected payload:

```swift
        let expected = "./.github/scripts/lint-plan-assertions.sh --self-test "
            + "&& ./.github/scripts/lint-plan-assertions.sh"
```

```bash
swift test --filter testPlanLintStepIsBlockingAndUnguarded > /tmp/slice57-t5-red.txt 2>&1
tail -10 /tmp/slice57-t5-red.txt
```

Expected: FAIL — "want exactly one step whose run payload is `... --self-test && ...`, found 0". The pin is payload **equality**, so it fails before the workflow changes: that ordering is the point.

- [ ] **Step 2: Change the workflow step**

In `.github/workflows/swift-ci.yml`, the `Lint plan assertions` step's `run:` becomes:

```yaml
        run: ./.github/scripts/lint-plan-assertions.sh --self-test && ./.github/scripts/lint-plan-assertions.sh
```

Nothing else about the step changes: no `if:` guard (its absence is deliberate and separately asserted), no `continue-on-error`, same name, same position before `swift test`.

- [ ] **Step 3: Run the pin and the script**

```bash
swift test --filter WorkflowShapeTests > /tmp/slice57-t5-green.txt 2>&1
tail -5 /tmp/slice57-t5-green.txt
./.github/scripts/lint-plan-assertions.sh --self-test > /tmp/slice57-t5-selftest.txt 2>&1
echo "selftest_exit=$?"
./.github/scripts/lint-plan-assertions.sh > /tmp/slice57-t5-lint.txt 2>&1
echo "lint_exit=$?"
tail -3 /tmp/slice57-t5-lint.txt
```

Expected: `WorkflowShapeTests` green; `selftest_exit=0`; `lint_exit=0` with `lint=pass files=2 violations=0` — two files now, because **this plan is the second non-exempt one**.

- [ ] **Step 4: Drill G9**

Drill (s): append ` || true` to the step's payload. Expected red: `testPlanLintStepIsBlockingAndUnguarded` fails on payload equality (`found 0`). Record it, and note that the same edit was green before slice 56 promoted the pin to equality — a `|| true` is precisely what a token probe reads as present and correct.

```bash
git diff --quiet -- .github/workflows/swift-ci.yml
if [ $? -eq 0 ]; then echo "workflow_restored=clean"; else echo "workflow_restored=DIRTY"; fi
```

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/swift-ci.yml Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
git commit -m "ci: D-43 - the plan linter runs its own self-test on every PR"
```

---

### Task 6: D-19, D-20, D-21, D-38 — vocabulary, the unpinned class arm, and one transcribed constant

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/GateLogicTests.swift` (lines 232, 235, 245, 298; add two tests after `testDiscreteActionClassIsExactlyDocumented` at line 213)
- Modify: `Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift` (line 271)

**Interfaces:**
- Consumes: `BenchmarkMode.allCases`, `BenchmarkMode.isGateable`, `BenchmarkMode.absoluteCeiling`, `AbsoluteCeiling` (`.scrollFrame` / `.discreteAction`), `TestVisualRowLayout` (the existing test fixture type).
- Produces: nothing consumed later.

**Guarantees added:** G12, G23

- [ ] **Step 1: D-19 — retire the vocabulary that outlived the concept**

`isFrameHotPath` was removed in slice 52 (`b79ead6`); the prose it named survives at four sites in `GateLogicTests.swift` — three comments (232, 245, 298) and the test *name* `testAbsoluteCeilingFiresForFrameHotPathMode` (235), whose sibling already reads `...ForBulkModeAtItsOwnCeiling`. The ledger row says "five"; the contract is an **empty scan**, not a count, because the row's number is stale for exactly the reason D-20's is:

```bash
rg -i -n 'frame.hot.path' Tests/ Sources/ > /tmp/slice57-t6-before.txt 2>&1
cat /tmp/slice57-t6-before.txt
```

Rename the test to `testAbsoluteCeilingFiresForScrollFrameMode` and rewrite the three comments in the `.scrollFrame` vocabulary. Nothing else changes: the concept maps 1:1, so no assertion moves.

```bash
if [ -z "$(rg -i -n 'frame.hot.path' Tests/ Sources/)" ]; then
  echo "vocabulary_scan=empty"
else
  echo "vocabulary_scan=NON_EMPTY"
  rg -i -n 'frame.hot.path' Tests/ Sources/
fi
```

Expected: `vocabulary_scan=empty`.

- [ ] **Step 2: D-20 + D-21 — write both failing tests**

Add to `GateLogicTests.swift`, after `testDiscreteActionClassIsExactlyDocumented`:

```swift
    // D-20. The NON-GATEABLE modes' AbsoluteCeiling class is pinned by nothing:
    // testDiscreteActionClassIsExactlyDocumented filters on isGateable, so these six
    // classify under a total function that no test covers. The ledger row says "five" --
    // it was written before wrapPointQuery existed. The count is therefore DERIVED from
    // allCases here rather than transcribed, so the row's stale number cannot become a
    // stale pin: adding a seventh non-gateable mode fails this test until its class is a
    // decision somebody made.
    func testNonGateableModesClassifyAsScrollFrame() {
        let nonGateable = BenchmarkMode.allCases.filter { !$0.isGateable }
        XCTAssertEqual(
            Set(nonGateable.map(\.outputName)),
            ["range_only", "memory_shape", "memory_observation",
             "wrap_compute", "wrap_row_query", "wrap_point_query"],
            "the non-gateable set changed; classify the new mode, do not widen the pin")
        for mode in nonGateable {
            XCTAssertEqual(
                mode.absoluteCeiling, .scrollFrame,
                "\(mode.outputName): inert today, but it stops being inert the moment a "
                    + "wrap mode becomes gateable at node 6")
        }
    }

    // D-21. The .scrollFrame arm was unpinned in the gateable direction: moving a gated
    // mode INTO .discreteAction reddens testDiscreteActionClassIsExactlyDocumented, but a
    // new gateable mode landing in .scrollFrame tripped nothing. Safe by default --
    // .scrollFrame is the tighter ceiling -- but the safety was an accident. Both arms are
    // now checked, and the two tests together partition the gateable set.
    func testGateableScrollFrameClassIsExactlyDocumented() {
        let scrollFrame = Set(
            BenchmarkMode.allCases
                .filter { $0.isGateable && $0.absoluteCeiling == .scrollFrame }
                .map(\.outputName))
        XCTAssertEqual(
            scrollFrame,
            ["pipeline", "realistic_provider", "variable_height", "variable_height_mutation",
             "structural_mutation", "line_query", "line_geometry_query", "column_query",
             "column_geometry_query", "point_query", "point_geometry_query"])
        let gateable = Set(BenchmarkMode.allCases.filter(\.isGateable).map(\.outputName))
        XCTAssertEqual(
            scrollFrame.union(["bulk_structural_mutation"]), gateable,
            "the two class pins must partition the gateable set, or a mode can sit in "
                + "neither and be checked by neither")
    }
```

```bash
swift test --filter GateLogicTests > /tmp/slice57-t6-red.txt 2>&1
tail -10 /tmp/slice57-t6-red.txt
```

Expected: PASS. Both are written green from birth — they measure an existing classification rather than specify a new one, so their falsifiability comes from Step 4's drills, not from a red-first cycle (D-35).

- [ ] **Step 3: D-38 — derive the transcribed constant**

In `Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift`, replace `let mustScan = 55 - 15` with a derivation from the fixture's own numbers. The fixture is 100 cells of advance 10 at width 50, so rows hold five cells each; the transcription is correct today and wrong the moment anyone reshapes it — the same defect the sibling assertion two lines above already had, and which this file already fixed once:

```swift
        // Derived, never transcribed (D-38). Rows are uniform here, so cells-per-row is
        // the fixture's own quotient; the guard makes the uniformity a checked premise
        // rather than an assumption inherited from the comment above.
        let rowCount = base.visualRowCount(inLine: 0)
        let cellCount = base.columnCount(inLine: 0)
        XCTAssertEqual(cellCount % rowCount, 0, "fixture: rows must hold equal cell counts")
        let cellsPerRow = cellCount / rowCount
        let mustScan = (far - near) * cellsPerRow
```

```bash
swift test --filter WrapPointQueryCountTests > /tmp/slice57-t6-d38.txt 2>&1
tail -5 /tmp/slice57-t6-d38.txt
```

Expected: PASS, and `mustScan` still 40 — `(10 - 2) * (100 / 20)`.

- [ ] **Step 4: Drill G12 and G23**

Drill (t) for **G12**, both halves: (i) change `.wrapPointQuery`'s arm in `absoluteCeiling` to `.discreteAction`. Expected red: `testNonGateableModesClassifyAsScrollFrame` fails naming `wrap_point_query`; `testDiscreteActionClassIsExactlyDocumented` stays **green** (it filters on `isGateable`), which is the gap D-20 records. (ii) Move `.columnQuery` into `.discreteAction`. Expected red: `testGateableScrollFrameClassIsExactlyDocumented` fails on both the set and the partition assertion — the D-21 half, which tripped nothing before.

Drill (u) for **G23**: reshape the fixture to `Array(repeating: 10.0, count: 50)` (50 cells, 10 rows). Expected: the derived `mustScan` follows to `(10 - 2) * 5`… and the test's own `far < rowCount - 1` guard fires first, naming the real problem. Record both: with the transcribed `55 - 15` the derivation would have silently kept asserting 40 against a fixture that no longer produces it.

```bash
git diff --quiet -- Sources Tests
if [ $? -eq 0 ]; then echo "restored=clean"; else echo "restored=DIRTY"; fi
```

- [ ] **Step 5: Commit**

```bash
git add Tests/ViewportBenchmarksTests/GateLogicTests.swift Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift
git commit -m "test: D-19/D-20/D-21/D-38 - scrollFrame vocabulary, both class arms, one derived constant"
```

---

### Task 7: D-10, D-11 — a pointer that leads to a retired name, and an unpinned job set

**Files:**
- Modify: `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md` (banner at the top)
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` (a new test beside `testJobNamesMatchRequiredCheckContexts`, line 549)

**Interfaces:**
- Consumes: `workflowPath`, `jobLevelValue(of:jobKey:)`, `requiredCheckContexts`, and the file reader those helpers use.
- Produces: `allJobKeys() throws -> [String]` — the workflow's job keys in file order.

**Guarantees added:** G10

- [ ] **Step 1: D-10 — the superseded banner**

`AGENTS.md` cites `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md` as a live "see" reference, and that record carries the retired context name `WASM cross-target observation` at 8+ sites — including inside ruleset JSON, where it reads as current policy. The record is evidence and must not be rewritten (rewriting a record to satisfy a later fact falsifies it), so it gets a banner instead. Insert immediately after the title:

```markdown
> **Superseded in part (slice 47, 2026-07-20).** The WASM job's required-check context
> was renamed from `WASM cross-target observation` to **`WASM cross-target compile`**
> when the job stopped being observational and started blocking. Every occurrence of the
> old name below — ruleset JSON included — is preserved as the record of what was true on
> 2026-06-16 and is **not** current policy. For the rename and the drop-rename-readd
> sequence it required, see
> [`2026-07-20-wasm-required-check-rename.md`](2026-07-20-wasm-required-check-rename.md).
```

- [ ] **Step 2: D-11 — write the failing test**

The required-check pin models each job's `name:` but not the **job set**: a fourth job is invisible to it, so a new required context could appear with nothing in the repository modelling it. Add to `WorkflowShapeTests`:

```swift
    // D-11. The job SET, not just each job's name. testJobNamesMatchRequiredCheckContexts
    // iterates requiredCheckContexts, so it can only check jobs that table already names:
    // a fourth job -- required or not -- is invisible to it. This is the repository's own
    // "pins must model what runtime reads" lesson, recurring on the container rather than
    // on the contents.
    func testWorkflowJobSetIsExactlyTheThreePinnedJobs() throws {
        let keys = try allJobKeys()
        XCTAssertEqual(
            keys, requiredCheckContexts.map(\.jobKey),
            "\(workflowPath): the job set changed. Every job here reports a status-check "
                + "context to GitHub, and ruleset Main (id 17656807) requires three of "
                + "them by exact name. A new job needs a row in requiredCheckContexts "
                + "AND a decision about whether the ruleset requires it.")
        var names: [String] = []
        for key in keys {
            guard let name = try jobLevelValue(of: "name", jobKey: key) else {
                XCTFail("\(workflowPath): no name: key in job \(key)")
                continue
            }
            names.append(name)
        }
        XCTAssertEqual(names, requiredCheckContexts.map(\.context))
    }
```

and the reader it needs, beside `jobLevelValue`:

```swift
/// The workflow's job keys, in file order. A job key is a 2-space-indented `key:` line
/// inside the top-level `jobs:` block; steps and job-level keys are indented deeper, so
/// the depth alone separates them. Narrow on purpose -- the package is zero-dependency
/// and there is no YAML parser in reach (the file's standing constraint).
private func allJobKeys() throws -> [String] {
    let lines = try workflowLines()
    var keys: [String] = []
    var inJobs = false
    for line in lines {
        if isBlank(line) || isComment(line) { continue }
        if line == "jobs:" { inJobs = true; continue }
        if inJobs && !line.hasPrefix(" ") { break }
        guard inJobs, line.hasPrefix("  "), !line.hasPrefix("   ") else { continue }
        let trimmed = line.dropFirst(2)
        guard trimmed.hasSuffix(":") else { continue }
        keys.append(String(trimmed.dropLast()))
    }
    return keys
}
```

If the file's existing reader spells its whole-file accessor differently from `workflowLines()`, use that spelling — this test adds no reader of its own beyond the job-key walk.

```bash
swift test --filter WorkflowShapeTests > /tmp/slice57-t7.txt 2>&1
tail -5 /tmp/slice57-t7.txt
```

Expected: PASS, three keys in order.

- [ ] **Step 3: Drill G10**

Drill (v): append a fourth job to `swift-ci.yml`:

```yaml
  scratch-job:
    name: Scratch job
    runs-on: ubuntu-latest
    steps:
      - run: echo hello
```

Expected red: `testWorkflowJobSetIsExactlyTheThreePinnedJobs` fails on both assertions, naming `scratch-job`; every other test in the file stays green, which is the gap D-11 records. Restore the workflow byte-identically.

```bash
git diff --quiet -- .github/workflows/swift-ci.yml
if [ $? -eq 0 ]; then echo "workflow_restored=clean"; else echo "workflow_restored=DIRTY"; fi
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
git commit -m "docs: D-10 superseded banner; test: D-11 pins the workflow job set"
```

---

### Task 8: D-14, D-15 — the coverage partition in three more scripts, and one dispatcher shape

**Files:**
- Modify: `.github/scripts/derive-gate-budgets.sh` (dispatcher at line 198; classification inside `run_self_test`)
- Modify: `.github/scripts/harvest-gate-corpus.sh` (dispatcher at line 417; same)
- Modify: `.github/scripts/detect-docs-only-pr.sh` (dispatcher at line 257; same)

**Interfaces:**
- Consumes: each script's existing `assert_equal` and `run_self_test`.
- Produces: in each script, `SELF_TEST_COVERED` / `SELF_TEST_EXEMPT` arrays plus `defined_functions`, `is_harness_function`, `self_test_body`, `body_references_function`, `assert_function_defined` — the same five helpers `cross-target-compile.sh` already carries, copied verbatim so the three scripts and the fourth enforce one rule.

**Guarantees added:** G11, G24

**Escape hatch (spec Decision 10 and §8).** D-14 is the heaviest fold-in in the slice. If this task runs past its budget, drop the *remaining* scripts to a named residual in the ledger — "D-14 partially discharged: `<script>` classified, `<script>` not" — and keep going. A fold-in must not delay node 5. D-15 is three lines and never drops.

- [ ] **Step 1: D-15 — converge the dispatchers**

`cross-target-compile.sh` reads `run_self_test || exit 1` then `exit 0`; the other three read `run_self_test` then `exit 0`. Today the difference is latent, because every `assert_*` helper calls `exit 1` directly — so a failure never reaches the dispatcher. It stops being latent the moment an assertion helper `return`s instead, and then the bare call falls through to `exit 0` and a red self-test reports success. Change all three to:

```bash
if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test || exit 1
  exit 0
fi
```

In `detect-docs-only-pr.sh` the same two lines go inside its `case` arm:

```bash
    --self-test)
      run_self_test || exit 1
      exit 0
      ;;
```

- [ ] **Step 2: Drill G24 — prove the shape matters before trusting it**

The drill needs a *returning* assertion, because the current ones exit. On a scratch copy only:

```bash
SCRATCH=/tmp/slice57-d15
mkdir -p "$SCRATCH"
cp .github/scripts/derive-gate-budgets.sh "$SCRATCH/before.sh"
cp .github/scripts/derive-gate-budgets.sh "$SCRATCH/after.sh"
python3 - "$SCRATCH/before.sh" "$SCRATCH/after.sh" <<'PY'
import sys
before, after = sys.argv[1], sys.argv[2]
for path, dispatch in ((before, "  run_self_test\n  exit 0\n"), (after, "  run_self_test || exit 1\n  exit 0\n")):
    src = open(path).read()
    # the returning assertion the drill is about
    src = src.replace('    echo "  actual:   [$actual]"\n    exit 1\n', '    echo "  actual:   [$actual]"\n    return 1\n')
    # a deliberately failing assertion, injected at the top of run_self_test
    src = src.replace('run_self_test() {\n', 'run_self_test() {\n  assert_equal "1" "2" "injected_failure"\n', 1)
    src = src.replace('if [[ "${1:-}" == "--self-test" ]]; then\n  run_self_test || exit 1\n  exit 0\nfi', 'if [[ "${1:-}" == "--self-test" ]]; then\n' + dispatch + 'fi')
    src = src.replace('if [[ "${1:-}" == "--self-test" ]]; then\n  run_self_test\n  exit 0\nfi', 'if [[ "${1:-}" == "--self-test" ]]; then\n' + dispatch + 'fi')
    open(path, "w").write(src)
PY
bash "$SCRATCH/before.sh" --self-test > "$SCRATCH/before.txt" 2>&1
echo "before_exit=$?"
bash "$SCRATCH/after.sh" --self-test > "$SCRATCH/after.txt" 2>&1
echo "after_exit=$?"
head -2 "$SCRATCH/before.txt"
```

Expected: `before_exit=0` **with `self_test=fail label=injected_failure` on stdout** — a red self-test reporting success, which is the whole of D-15 — and `after_exit=1`. Record both. The repository copy is never edited by this drill; only `$SCRATCH`.

- [ ] **Step 3: D-14 — copy the five helpers into each script**

Copy `defined_functions`, `is_harness_function`, `self_test_body`, `body_references_function` and `assert_function_defined` from `cross-target-compile.sh` (lines 311-352) into each of the three scripts, unchanged. `self_test_body`'s awk already matches `run_self_test` plus `scenario_*`, which is the shape all four use.

Then enumerate each script's functions to fill the two arrays. The list is produced by the helper itself, not by reading the file by eye:

```bash
for script in derive-gate-budgets harvest-gate-corpus detect-docs-only-pr; do
  echo "--- $script"
  grep -oE '^(function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*([[:space:]]*\(\))?|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\))[[:space:]]*\{' ".github/scripts/$script.sh" \
    | sed -E -e 's/^function[[:space:]]+//' -e 's/[[:space:]]*(\(\))?[[:space:]]*\{$//'
done
```

For each name: `SELF_TEST_COVERED` if the self-test drives it, otherwise a `SELF_TEST_EXEMPT` entry with a **tab-separated justification** (the array's format; an entry without one fails the check). `assert_*` and `run_self_test` are harness and are skipped by `is_harness_function` — derived, never listed.

- [ ] **Step 4: Add the partition check to each `run_self_test`**

The block is `cross-target-compile.sh` lines 727-760 — both directions plus the reference check, verbatim. It is written to a scratch file and spliced into all three scripts from there, so the three copies are identical by construction rather than by three careful pastes. (It also keeps the plan linter's R3 off script *source*: this is a function body destined for a script that assigns these arrays at top level, not a command block whose own shell must define them.)

```bash
SCRATCH=/tmp/slice57-d14
mkdir -p "$SCRATCH"
cat > "$SCRATCH/partition-check.txt" <<'PARTITION'
  local script_path defined body fn entry name classified
  script_path="${BASH_SOURCE[0]}"
  defined="$(defined_functions "$script_path")"
  body="$(self_test_body "$script_path")"

  # Direction 1: every defined function is classified.
  for fn in $defined; do
    if is_harness_function "$fn"; then continue; fi
    classified=0
    for name in "${SELF_TEST_COVERED[@]}"; do
      [[ "$name" == "$fn" ]] && classified=1
    done
    for entry in "${SELF_TEST_EXEMPT[@]}"; do
      [[ "${entry%%$'\t'*}" == "$fn" ]] && classified=1
    done
    assert_equal "1" "$classified" "classified_${fn}"
  done

  # Direction 2: no phantom names, and every exempt entry carries a justification.
  for name in "${SELF_TEST_COVERED[@]}"; do
    assert_function_defined "$name" "$defined" "covered_defined_${name}"
  done
  for entry in "${SELF_TEST_EXEMPT[@]}"; do
    assert_function_defined "${entry%%$'\t'*}" "$defined" "exempt_defined_${entry%%$'\t'*}"
    if [[ "$entry" != *$'\t'* || -z "${entry#*$'\t'}" ]]; then
      echo "self_test=fail label=exempt_justified_${entry} expected=justification actual=none"
      exit 1
    fi
  done

  # Coverage: every covered function is really referenced by the self-test's source.
  for name in "${SELF_TEST_COVERED[@]}"; do
    if ! body_references_function "$name" "$body"; then
      echo "self_test=fail label=covered_but_unreferenced fn=$name"
      exit 1
    fi
  done
PARTITION
if [ -s "$SCRATCH/partition-check.txt" ]; then
  echo "partition_block=written lines=$(wc -l < "$SCRATCH/partition-check.txt")"
else
  echo "partition_block=EMPTY"
fi
```

Splice `$SCRATCH/partition-check.txt` into each of the three scripts, immediately before that script's `echo "self_test=pass"` line. Verify each landed inside `run_self_test` and not after it:

```bash
for script in derive-gate-budgets harvest-gate-corpus detect-docs-only-pr; do
  if grep -q 'label=covered_but_unreferenced' ".github/scripts/$script.sh"; then
    echo "spliced_${script}=yes"
  else
    echo "spliced_${script}=NO"
  fi
done
```

Expected: three `=yes` lines.

- [ ] **Step 5: Run all four self-tests, and the Swift test that drives them**

```bash
for script in derive-gate-budgets harvest-gate-corpus detect-docs-only-pr cross-target-compile; do
  if ./.github/scripts/$script.sh --self-test > /tmp/slice57-t8-$script.txt 2>&1; then
    echo "selftest_${script}=pass"
  else
    echo "selftest_${script}=FAIL"
    tail -5 /tmp/slice57-t8-$script.txt
  fi
done
swift test --filter ScriptSelfTestTests > /tmp/slice57-t8-swift.txt 2>&1
tail -5 /tmp/slice57-t8-swift.txt
```

Expected: four `=pass` lines and `ScriptSelfTestTests` green — the enrollment that makes an assertion in any of them able to fail the build.

- [ ] **Step 6: Drill G11, once per script**

Drill (w), three instances: add `scratch_unclassified_fn() { :; }` to each script. Expected red, per script: `self_test=fail label=classified_scratch_unclassified_fn expected=1 actual=0`, exit 1. Then the phantom direction, once: add a name to `SELF_TEST_COVERED` that no function defines. Expected red: `label=covered_defined_<name> expected=defined actual=missing`.

```bash
git diff --quiet -- .github/scripts
if [ $? -eq 0 ]; then echo "scripts_restored=clean"; else echo "scripts_restored=DIRTY"; fi
```

- [ ] **Step 7: Commit**

```bash
git add .github/scripts
git commit -m "ci: D-14 coverage partition in three scripts; D-15 one dispatcher shape"
```

---

### Task 9: documentation, the ledger, the map pass, and the record

**Files:**
- Modify: `AGENTS.md` (the `--memory-shape` line in `## Commands`; a paragraph in the architecture section)
- Modify: `docs/superpowers/debt-ledger.md`
- Modify: `docs/superpowers/arcs/wrap.md` (scoreboard row 2; slice map node 5; a map-pass entry)
- Create: `docs/superpowers/verification/2026-09-04-wrap-memory-shape.md`
- Later, on a separate `slice-57-hosted-proof` branch: the post-merge evidence section

**Interfaces:**
- Consumes: every drill output recorded in Tasks 1-8.
- Produces: the evidence the post-slice review reads.

**Guarantees added:** none — this task writes prose, ledger rows and evidence; every guard it describes shipped in Tasks 1-8, each with its own drill.

- [ ] **Step 1: `AGENTS.md` (AC14)**

Two edits. In `## Commands`, the `--memory-shape` line gains its second half:

```
swift run -c release ViewportBenchmarks -- --memory-shape    # memory-shape invariant (fixed/variable + wrap); expect invariant=pass
```

And, after the wrap-layer paragraphs, a new one — what the wrap half asserts, what its observable is, and what it cannot see:

> `--memory-shape` has a **wrap half** (slice 57): six scenarios, `{100k, 1M} x {inf, 40, 10}`, each running `compute(_:layout:)`, `DocumentVisualRowCursor`, `visualRowAt` and `visualPointAt` against a `CountingWrapLayout`. The observable is **provider probes, not bytes** — every wrap entry point returns fixed-size values, so `MemoryLayout` sums cannot see growth (a struct holding an array reports a pointer). `compute`'s layout-probe count is a **constant** across all six; the other three are held to a bounded delta across the 10x size jump; the buffered window is 90 at every width; and `provider_owned_bytes` is asserted against the prefix sum's derived size, which is criterion 2's "wrap data lives behind the provider abstraction" made observable. The whole mode now shares one declared expectation rather than comparing a scenario against its neighbour. **What the probe count cannot see** is an allocation that does not traverse (D-46): no available instrument closes that, and the criterion's evidence is scoped to what was measured.

- [ ] **Step 2: The ledger**

- **D-45** — append the row (born: this slice's spec), status `discharged(...)` in the same edit, with what it covered: the vacuous `x == x` comparison, the `providerLines: bufferedLines` assignment, and the first-of-group idiom.
- **D-46** — append as `accepted-risk`: a probe count sees traversal, not allocation; `MemoryLayout` reports a pointer for the case that matters; RSS is `--memory-observation`'s non-blocking instrument and a blocking assertion on it would fail on the runner. Name the follow-up (one wrap scenario per size in `--memory-observation`) so the row is a decision, not a shrug.
- **D-43, D-19, D-20, D-21, D-10, D-11, D-14, D-15, D-38** — flip to `discharged(...)` with links. D-14 flips only if Step 3 of Task 8 covered all three scripts; otherwise it stays `open` with the amended statement the escape hatch prescribes.

```bash
swift test --filter DebtLedgerShapeTests > /tmp/slice57-t9-ledger.txt 2>&1
tail -5 /tmp/slice57-t9-ledger.txt
```

Expected: green — the shape guard slice 56 added catches a raw `|` inside a code span in a table cell, which is exactly the character a `gov_p95=median|max` style row invites.

- [ ] **Step 3: The arc map pass**

In `docs/superpowers/arcs/wrap.md`: criterion 2 moves `open` -> **`done`**, with the evidence link (PR + post-merge run + the six wrap lines) and the D-46 scope note written into the Evidence cell — the criterion is closed on a probe-count observable, and the row must say so. Node 5 moves `pending` -> `done` with what the slice taught. Add a map-pass entry dated 2026-09-04 recording that nodes 6-9, fork R and fork V stand unrevised, and that node 6's precondition set is unchanged except that **D-20/D-21 leave it** (discharged here).

- [ ] **Step 4: Record the invariant fingerprint**

```bash
SCRATCH=/tmp/slice57-final
mkdir -p "$SCRATCH"
swift build -c release > "$SCRATCH/build.txt" 2>&1
echo "build_exit=$?"
if [ -z "$(rg -n "Foundation" Sources/TextEngineCore)" ]; then
  echo "foundation_scan=empty"
else
  echo "foundation_scan=NON_EMPTY"
fi
if git diff --quiet main -- Sources/TextEngineCore; then
  echo "core_untouched=true"
else
  echo "core_untouched=FALSE"
  git diff --stat main -- Sources/TextEngineCore
fi
for mode in --gate --variable-height --variable-height-mutation --structural-mutation --bulk-structural-mutation --line-query --line-geometry-query --column-query --column-geometry-query --point-query --point-geometry-query --realistic-provider; do
  swift run -c release ViewportBenchmarks -- "$mode" --gate >> "$SCRATCH/gates.txt" 2>&1 || true
done
grep -c 'gate=pass' "$SCRATCH/gates.txt"
swift run -c release ViewportBenchmarks -- --wrap-compute > "$SCRATCH/wrap.txt" 2>&1
swift run -c release ViewportBenchmarks -- --wrap-row-query >> "$SCRATCH/wrap.txt" 2>&1
swift run -c release ViewportBenchmarks -- --wrap-point-query >> "$SCRATCH/wrap.txt" 2>&1
grep -o 'checksum=[0-9-]*' "$SCRATCH/wrap.txt" > "$SCRATCH/wrap-checksums.txt"
cat "$SCRATCH/wrap-checksums.txt"
swift run -c release ViewportBenchmarks -- --memory-observation > "$SCRATCH/observation.txt" 2>&1
grep -c 'provider=wrap' "$SCRATCH/observation.txt"
```

Expected: `build_exit=0`; `foundation_scan=empty`; `core_untouched=true` (Task 4's drill (q) is the only edit that ever touched the core, and it was restored); 46 `gate=pass`; the three wrap checksums byte-identical to slice 55b's record; and **0** `provider=wrap` lines in `--memory-observation` — AC6, the proof Decision 5's separate scenario list held.

Extract the 46 gated checksums with D-18's filter — `grep -v -e 'mode=memory_shape' -e 'mode=memory_observation'` — and diff them against slice 56's. The raw count including the diagnostic modes is now **60**, not 54, because the mode's line count went 5 -> 11.

- [ ] **Step 5: Record the test-count delta**

```bash
swift test > /tmp/slice57-final-suite.txt 2>&1
tail -3 /tmp/slice57-final-suite.txt
```

The fingerprint is a **pair with a delta**, not "grows only by the new tests": record slice 56's count, this slice's, the delta, and the enumeration — 4 (Task 1) + 6 (Task 2) + 10 (Task 3) + 4 (Task 4) + 2 (Task 6) + 1 (Task 7) = 27, with Task 5 adding none (it changes an existing pin's literal). If the delta and the enumeration disagree, find out which is wrong before writing the record.

- [ ] **Step 6: Run the plan linter on this plan**

```bash
./.github/scripts/lint-plan-assertions.sh docs/superpowers/plans/2026-09-04-wrap-memory-shape.md > /tmp/slice57-lint.txt 2>&1
echo "lint_exit=$?"
cat /tmp/slice57-lint.txt
```

Expected: `lint_exit=0`, `lint=pass files=1 violations=0`. This plan is non-exempt, so a violation here fails CI on the very step Task 5 strengthened.

- [ ] **Step 7: Write the record**

Create `docs/superpowers/verification/2026-09-04-wrap-memory-shape.md` with: the spec and plan links; per-task command transcripts; **every drill (a)-(w) with its recorded red text**; the Task 1 Step 8 measurement table (the six scenarios' probe counts and build times) and the constant it produced; the eleven `--memory-shape` lines in full; the byte-identity diff of the five existing lines; the 46-checksum diff; the three wrap checksums; the test-count pair and delta; and a section reserved for the hosted runs. Facts about this branch are phrased **re-checkably** — a per-head "commit -> run id" table, never "the current HEAD".

- [ ] **Step 8: Open the PR and read both hosted runs at STEP level**

A green job can hide a dead step. Read the step logs, not the job conclusion: the twelve gates print `gate=pass`; `Lint plan assertions` prints `lint=pass` **and** its self-test's line; `--memory-shape` prints eleven lines all `invariant=pass`; the host job's `swift test` reports 0 failures.

```bash
gh pr create --fill --base main
gh run list --limit 5
```

- [ ] **Step 9: Record the post-merge proof on a separate branch**

After merge, on `slice-57-hosted-proof`: the post-merge `push` run id, its step-level readings, and the per-head table. A separate branch because a record cannot carry facts about its own branch (`AGENTS.md`, `Conventions that matter`).

---

## Plan self-review

**1. Spec coverage.** AC1 -> Task 2 Step 6 and Task 3 Step 7. AC2 -> Tasks 2 and 3 (every §4A invariant is implemented in one of them, and drills (d)-(i) and (j)-(p) cover them). AC3 -> Task 1 Step 8 measures the constant, Task 2 asserts it, Task 4 pins it in `swift test`. AC4 -> Task 2's `testTheQueryLandsOffARowStartAtEveryWrappedWidth` and `testThePointQueryNeverClamps`, plus invariant 11 in Task 3. AC5 -> Task 3 (drills (j), (k), (p)). AC6 -> Task 9 Step 4's `provider=wrap` count in `--memory-observation`. AC7 -> Task 9 Step 4. AC8 -> Task 9 Steps 4-5. AC9 -> Tasks 5-8. AC10 -> Task 9 Steps 8-9. AC11 -> Task 9 Steps 2-3. AC12 -> Task 2 (`testProviderOwnedBytesIsTheDerivedPrefixSize`) and Task 3 (`testProviderBytesAreASizeTermAndNotAWidthTerm`). AC13 -> Task 4. AC14 -> Task 9 Step 1.

**2. Placeholder scan.** No "TBD", no "TODO", no "similar to Task N". Every code step carries its code. Two steps derive content by running a command rather than listing it — Task 8 Step 3's function enumeration and Task 9's ledger rows — and in both cases the command and the format are given in full; that is derivation, not a placeholder.

**3. Assertion audit (D-2).** No `PIPESTATUS` in any command block. `SCRATCH` is assigned in every block that uses it (Task 3 Step 8, Task 8 Step 2, Task 9 Step 4); loop variables are lowercase and bound by their own `for`. Every check is an `if`/`else` printing both branches, a `[ -z "$(...)" ]`, a `git diff --quiet` followed by `[ $? -eq 0 ]`, or an `echo "..._exit=$?"` after a command whose status **is** sensitive (`swift run`, `swift build`, a script invocation) — never after `git diff --name-only`, `git status`, `gh`, `jq`, `sed -i`, or a pipeline.

**4. Type consistency.** `WrapProbeCounter.total` is the six-hook sum everywhere it is read (Tasks 1, 2, 4); `firstVisualRowAtLineCount` is never folded into it. `MemoryShapeWindowContribution.touchedElements` is `Int?` at its definition (Task 3 Step 4), at every construction site (Task 3 Step 6) and in every test (Task 3 Step 2). `WrapMemoryShapeSummary`'s field list in Task 2 matches the synthetic constructor in Task 3's tests field for field. `wrapMemoryShapeComputeProbes` is defined in Task 2 and consumed by Tasks 3 and 4.

**5. Ordering.** Task 2 needs Task 1's counter. Task 3 needs Task 2's summary type and constants. Task 4 needs both. Tasks 5-8 are independent of the spine and of each other, and are sequenced after it so a fold-in cannot delay the criterion (spec Decision 10). Task 9 is last by construction, and its Step 6 lints this file — which only passes once every task above carries its `**Guarantees added:**` block.

**6. One deviation from the spec, amended rather than absorbed.** Task 3 Step 1 amends §4B: a wrap scenario contributes two counts, not three, because it has no third independent traversal and reporting its streamed rows twice would restate the vacuity D-45 removes. The amendment is committed on its own so the reasoning is reviewable apart from the code.

**7. Two guarantees the spec's §6 does not list, and one drill it lists wrongly.** G22 (probe attribution: a `logicalLine` forwarded to `base` sends the default search's probes into the unwrapped provider and every count in the mode understates by its dominant term), G23 (D-38's derived constant) and G24 (D-15's dispatcher shape) are additions the per-task inventory carries, per D-35. And §6's drill for **G6** — "stop counting `columnOffset`, and watch the inequality fail" — is replaced in Task 3 by a positive control, because `canBreak` is counted on the same walk and the inequality can survive that mutation: a drill that may report green is worse than no drill, since it certifies the guarantee.
