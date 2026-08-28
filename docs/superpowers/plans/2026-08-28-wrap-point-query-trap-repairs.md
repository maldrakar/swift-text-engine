# Wrap Trap Repairs (Slice 55a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the first of node 4's two pieces — the shipped wrap layer repaired and made cheaper, with **no new public API**: five guards so a malformed `logicalLine(containingVisualRow:)` override never traps, the within-line walk and the per-line wrap ladder extracted into shared internal helpers, the packer's suffix-fits short-circuit, and the D-24 / D-29 fold-ins — every guard with a recorded red, every measured-path edit its own commit and its own `--wrap-compute` column.

**Architecture:** Seven commits in a load-bearing order (spec Contract 55a). Commit 0 adds the `checksum=` witness to the `wrap_compute` line before anything on its path moves. Commit 1 extracts `advanceVisualRows` and guards `DocumentVisualRowCursor.init`; commit 2 guards `visualRowAt`; commit 3 extracts `validateWrapLine` and stores `total` on the cursor; commit 4 adds the `greedyEnd` short-circuit, red-first against a probe-count pin; commit 5 extracts the `--wrap-compute` drain body (D-29); commit 6 lands the D-24 dispatch pin — after the guards, never before. Every guard sits at the **producer** of the value it checks; the stream stops (it has no failure channel), the query fails.

**Tech Stack:** Swift 6.0 tools version, XCTest, SwiftPM. No dependencies. Local toolchain is Swift 6.2.4 (hosted CI is 6.2.1).

**Spec:** [`docs/superpowers/specs/2026-08-24-wrap-point-query-design.md`](../specs/2026-08-24-wrap-point-query-design.md) — read **Contract — 55a** first; it is this plan's source, and every task below names the Decision it implements.

## Global Constraints

Every task's requirements implicitly include these.

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty; it is run at every commit that touches the core.
- **Zero third-party dependencies**; **Swift Embedded compatible** (no new Foundation, no existentials, value types only — the same shapes the file already uses); compiles for iOS and WASM with no source changes (hosted proof, Task 8).
- **No new public API, no public type gains a field.** `advanceVisualRows`, `WrapLineMetrics`, `validateWrapLine`, `drainVisualRows` are `internal`. `VisualRowCursor.init` stays `internal`. `visualRows(inLine:wrapWidth:metrics:)` keeps its signature, return type, probe order and failures.
- **Five suites pass UNEDITED across commits 3 and 4** (spec Decision 13, AC18): `WrapPackingTests`, `WrapValidationTests`, `WrapComputeTests` (its shipped cases), `VisualRowEquivalenceTests`, `WrapComputeEquivalenceTests`. If one has to be edited to go green, **stop** — the extraction was not neutral. Tasks 4 and 5 assert this with `git diff --quiet` on the files.
- **Every gated mode's benchmark checksum is byte-identical to the pre-branch baseline** (AC13). Nothing here touches a gated path; a movement is a finding, not noise.
- **Neither wrap mode becomes gateable or enters `swift-ci.yml`.** Both keep prefixed latency tokens (`compute_p95_ns=`, `query_p95_ns=`); the new `checksum=` token on the `wrap_compute` line is not a latency key and creates no corpus row.
- **`--wrap-compute` is recorded one column per commit on its path** — two baselines after commit 0, then after commits 1, 3, 4, 5 — never one before/after spanning two edits. Commits 1, 3 and 5 are predicted **flat**; commit 4 lowers `reindex_ns` and `drain_*` at every width in the order Decision 12 predicts (`inf` < `40` < `10` < 1 — time falls less than scan iterations; Task 5 Step 8) and leaves `compute_*` flat. Any other outcome is a **finding** to record, not to explain away.
- **TDD.** Failing test first, minimal implementation, green, commit. A guard's red is a **trap** on the shipped code (the test process aborts with `Fatal error: Index out of range`, exit code non-zero) — record it as such; it is the red.
- **Conventional commits**: `feat:`, `test:`, `refactor:`, `docs:`. One logical step per commit. Every commit ends with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **Branch**: `slice-55a-wrap-trap-repairs`, created from `slice-55-wrap-point-query` so the spec and this plan travel with it (Task 1).
- **D-17 — do NOT use `${PIPESTATUS[0]}` in any command block.** Agent shells here are **zsh**, where it expands empty and `[ "" -eq 0 ]` evaluates **true**, inverting a failed assertion into a pass. Use `if ! cmd; then …; fi`, a plain `$?` on an unpiped command, or `[ -z "$(…)" ]`.
- **D-2 assertion conventions**: never put a check on the left of a pipe whose right side is `tail`/`tee`/`jq`/`wc`/`rg`; never `echo "…=$?"` after a status-insensitive command; assert with `[ -z "$(…)" ]`, `git diff --quiet`, or an `if`/`else` that prints both branches.
- **Every command block assigns the variables it uses.** Each Bash invocation is a fresh shell.
- Run everything from the repo root: `/Users/aabanschikov/swift-text-engine`.
- **Scratch files** go under `/tmp/slice55a-*`. Never inside the repository.
- **Line numbers in this plan are anchors, not instructions.** Edits are given as *Replace / With* text; match on the text.

---

## File Structure

**Core (`Sources/TextEngineCore`)**

| File | Responsibility after this slice |
|---|---|
| `DocumentVisualRowCursor.swift` | The document cursor, now with guards 3 and 4 in `init` (out-of-range `startLine`, negative `rowInStartLine` → terminal state, streams nothing), and the new internal `advanceVisualRows(_:by:)` — the one within-line walk, shared with node 4's query. |
| `WrapPositionQuery.swift` | `visualRowAt` gains guards 1 and 2 (`logicalLine ∉ 0..<lineCount`, `rowInLine < 0` → `.failure(.invalidVisualRowLayout)`); its doc comment narrows the "same accept/reject set" claim to the ladder. |
| `WrapViewportVirtualizer.swift` | Doc comment only: the same narrowing. |
| `VisualRowCursor.swift` | `VisualRowCursor` stores `total`; `greedyEnd` gains the suffix-fits short-circuit; the per-line ladder moves into the internal `validateWrapLine(inLine:wrapWidth:metrics:) -> WrapLineMetrics`, and `visualRows` becomes a thin wrapper over it. |

**Benchmarks (`Sources/ViewportBenchmarks`)**

| File | Responsibility |
|---|---|
| `WrapComputeBenchmark.swift` | `formatWrapComputeLine` gains a trailing `checksum=` (commit 0); the drain body becomes the internal `drainVisualRows(_:layout:)` (commit 5). `BenchmarkWrapLayout` is **untouched** — its init is the measured reindex. |

**Tests**

| File | Responsibility |
|---|---|
| `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift` | +`HookLog`, +`OverridingLogicalLineLayout` — a `TestVisualRowLayout` whose row-axis hook is overridden with a caller-supplied answer and every call logged. Commits 1–2 hand it a **wrong** answer (the guard tests); commit 6 the **right** one (the dispatch pin). |
| `Tests/TextEngineCoreTests/WrapComputeTests.swift` | +2 cases: the cursor's two guards, each asserting `next() == nil` on the first call. |
| `Tests/TextEngineCoreTests/VisualRowWalkHelperTests.swift` | **new**, `@testable` — the helper's own rule (`k <= 0`, the k-th result, `nil` past the end, stops at the first `nil`). |
| `Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift` | +4 cases: guard 1 at three values, guard 2. |
| `Tests/TextEngineCoreTests/WrapPackingCountTests.swift` | **new** — Decision 12's two O(1) cases (zero `canBreak` on a fitting line; zero `canBreak` added by a wrapped line's last row). Red on the shipped packer. |
| `Tests/TextEngineCoreTests/VisualRowDispatchTests.swift` | **new** — D-24: `visualRowAt` (in range, both clamps) and the document cursor each dispatch through the hook exactly once. |
| `Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift` | The `wrap_compute` shape case gains the `checksum=` token. |
| `Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift` | **new** — D-29: the drain body makes zero `firstVisualRow(ofLine: lineCount)` probes, with a witness that `compute(_:layout:)` makes one. |

**Docs**: `AGENTS.md` (node 1 and node 2 cost wording; the `visualRowAt` paragraph; the "same accept/reject set" sentence), `docs/superpowers/debt-ledger.md` (D-24, D-29 → `discharged`), `docs/superpowers/verification/2026-08-28-wrap-point-query-trap-repairs.md` (new).

**Untouched on purpose**: `BenchmarkWrapLayout`, every gated benchmark file, `BenchmarkModels.swift`, `BenchmarkOptions.swift`, `.github/workflows/swift-ci.yml`, the corpus, every budget. `VisualRowLayoutTestSupport.swift:49-53`'s comment on `RiggedVisualRowLayout` is 55b's.

---

## Task 1: Branch, baselines, and commit 0 — the `checksum=` witness

Spec Contract 55a commit 0; Decision 13 ("a witness absent from the first column is a witness for nothing"). Also the pre-branch baselines every later task compares against.

**Files:**
- Modify: `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift` (`formatWrapComputeLine` and its call site)
- Modify: `Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift` (`testWrapComputeLineCarriesThreeOperationCountsAndNoBareLatencyKeys`)

**Interfaces:**
- Consumes: `amortisedSamples(...) -> (samples: [Int64], checksum: Int)` (`BenchmarkSupport.swift`).
- Produces: `formatWrapComputeLine(widthLabel:totalRows:computeOperationsPerSample:computeP95Nanoseconds:computeP99Nanoseconds:drainOperationsPerSample:drainP95Nanoseconds:drainP99Nanoseconds:reindexNanoseconds:checksum:) -> String` — one new trailing parameter, one new trailing token ` checksum=<Int>`.

- [ ] **Step 1: Create the branch from the spec branch**

```bash
cd /Users/aabanschikov/swift-text-engine
git switch slice-55-wrap-point-query
if [ -z "$(git status --porcelain)" ]; then echo "clean"; else echo "DIRTY — commit the spec/plan first"; git status --short; fi
git switch -c slice-55a-wrap-trap-repairs
echo "branch=$(git branch --show-current)"
```

Expected: `clean`, then `branch=slice-55a-wrap-trap-repairs`.

- [ ] **Step 2: Record the green suite baseline**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test > /tmp/slice55a-baseline-suite.txt 2>&1; then
  echo "BASELINE RED — stop and investigate before changing anything"
else
  echo "baseline green"
fi
rg -n "Executed [0-9]+ tests" /tmp/slice55a-baseline-suite.txt | tail -2
```

Expected: `baseline green`, and the test count (the verification record carries it; the slice-54 merge left it at 408).

- [ ] **Step 3: Release build, the twelve gates, and the pre-branch checksum baseline (AC13)**

This runs before any code moves. Every gated mode prints `mode=… scenario=… checksum=…`; the extraction is the recipe from the slice-52 record, and because only the twelve gated modes are run here the count is 46 with no filter.

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice55a-baseline-build.txt 2>&1; then
  echo "RELEASE BUILD RED"; tail -20 /tmp/slice55a-baseline-build.txt
else
  echo "release build green"
fi
: > /tmp/slice55a-gates-baseline.txt
if ! swift run -c release ViewportBenchmarks -- --gate >> /tmp/slice55a-gates-baseline.txt 2>&1; then echo "GATE RED: default pipeline"; fi
for flag in --variable-height --variable-height-mutation --structural-mutation --bulk-structural-mutation --line-query --line-geometry-query --column-query --column-geometry-query --point-query --point-geometry-query --realistic-provider; do
  if ! swift run -c release ViewportBenchmarks -- "$flag" --gate >> /tmp/slice55a-gates-baseline.txt 2>&1; then echo "GATE RED: $flag"; fi
done
echo "gate=pass lines: $(grep -c 'gate=pass' /tmp/slice55a-gates-baseline.txt) (expect 46)"
echo "gate=fail lines: $(grep -c 'gate=fail' /tmp/slice55a-gates-baseline.txt) (expect 0)"
sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9]+).*/\1|\2\t\3/p' /tmp/slice55a-gates-baseline.txt | sort -u > /tmp/slice55a-checksums-baseline.tsv
echo "checksum tuples: $(wc -l < /tmp/slice55a-checksums-baseline.tsv | tr -d ' ') (expect 46)"
```

Expected: no `GATE RED` line, `46` / `0` / `46`. (`grep -c` prints `0` on no match; it is inside `$(…)`, so its exit status is not being read.)

- [ ] **Step 4: The two observational baselines and `--memory-shape`**

```bash
cd /Users/aabanschikov/swift-text-engine
swift run -c release ViewportBenchmarks -- --wrap-row-query > /tmp/slice55a-wrq-baseline.txt 2>&1
grep '^mode=wrap_row_query' /tmp/slice55a-wrq-baseline.txt
if swift run -c release ViewportBenchmarks -- --memory-shape > /tmp/slice55a-memshape-baseline.txt 2>&1 && grep -q 'invariant=pass' /tmp/slice55a-memshape-baseline.txt && ! grep -q 'invariant=fail' /tmp/slice55a-memshape-baseline.txt; then
  echo "memory-shape: invariant=pass"
else
  echo "MEMORY-SHAPE RED"; grep 'invariant=' /tmp/slice55a-memshape-baseline.txt
fi
```

Expected: four `mode=wrap_row_query` lines, each with a `checksum=`; `memory-shape: invariant=pass`. Keep `/tmp/slice55a-wrq-baseline.txt` — Task 3 compares against it.

- [ ] **Step 5: Write the failing shape test (the token)**

In `Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift`, inside `testWrapComputeLineCarriesThreeOperationCountsAndNoBareLatencyKeys`:

Replace:
```swift
            drainOperationsPerSample: 16, drainP95Nanoseconds: 4_100, drainP99Nanoseconds: 5_200,
            reindexNanoseconds: 61_000_000)
```
With:
```swift
            drainOperationsPerSample: 16, drainP95Nanoseconds: 4_100, drainP99Nanoseconds: 5_200,
            reindexNanoseconds: 61_000_000, checksum: 987_654)
```

And replace:
```swift
        XCTAssertEqual(value("reindex_ns", in: line), "61000000")
```
With:
```swift
        XCTAssertEqual(value("reindex_ns", in: line), "61000000")
        // Slice 55a commit 0: the result-preservation witness for every edit on this
        // mode's path (spec Decision 13). Folds the compute and drain checksums the
        // anti-dead-code guard used to hold; must be byte-identical across every column
        // of the --wrap-compute record.
        XCTAssertEqual(value("checksum", in: line), "987654")
```

- [ ] **Step 6: Run it to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapBenchmarkLineShapeTests > /tmp/slice55a-t1-red.txt 2>&1; then
  echo "UNEXPECTED PASS"
else
  echo "EXPECTED RED"; rg -n "error:" /tmp/slice55a-t1-red.txt | head -3
fi
```

Expected: `EXPECTED RED` with `extra argument 'checksum' in call` (a compile error is the red here).

- [ ] **Step 7: Add the parameter and the token; print it at the call site**

In `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`:

Replace:
```swift
    drainP99Nanoseconds: Int64,
    reindexNanoseconds: Int64
) -> String {
```
With:
```swift
    drainP99Nanoseconds: Int64,
    reindexNanoseconds: Int64,
    checksum: Int
) -> String {
```

Replace:
```swift
        + " reindex_operations_per_sample=1"
        + " reindex_ns=\(reindexNanoseconds)"
}
```
With:
```swift
        + " reindex_operations_per_sample=1"
        + " reindex_ns=\(reindexNanoseconds)"
        // The result-preservation witness (slice 55 spec, Decision 13): every drained
        // row's endColumn and every computed range's length, folded, over 100 000 lines
        // at this width. Deterministic under deterministicScrollOffset, so it must be
        // byte-identical across every edit on this mode's path while the timings move.
        // Not a latency key: the harvester still sees no bare p95_ns/p99_ns here.
        + " checksum=\(checksum)"
}
```

Replace:
```swift
        // Keeps both measured bodies observably live without adding a token to a line the
        // harvester must keep ignoring -- the same guard the drain body carried before, now
        // covering compute as well.
        if computeMeasured.checksum &+ drainMeasured.checksum == Int.min { print("") }

```
With:
```swift
        // Both measured bodies stay observably live by being PRINTED (the checksum= token
        // below), which replaced the former `== Int.min` guard in slice 55a.
        let checksum = computeMeasured.checksum &+ drainMeasured.checksum

```

Replace:
```swift
            reindexNanoseconds: nanoseconds(reindexElapsed)))
```
With:
```swift
            reindexNanoseconds: nanoseconds(reindexElapsed),
            checksum: checksum))
```

- [ ] **Step 8: Run the shape tests and the full suite**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapBenchmarkLineShapeTests > /tmp/slice55a-t1-green.txt 2>&1; then echo "shape tests green"; else echo "SHAPE TESTS RED"; rg -n "error:|failed" /tmp/slice55a-t1-green.txt | head -5; fi
if swift test > /tmp/slice55a-t1-full.txt 2>&1; then echo "suite green"; else echo "SUITE RED"; rg -n "error:|failed" /tmp/slice55a-t1-full.txt | head -5; fi
rg -n "Executed [0-9]+ tests" /tmp/slice55a-t1-full.txt | tail -1
```

Expected: both green; the count unchanged from Step 2 (no new test, one assertion added).

- [ ] **Step 9: Commit 0**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/ViewportBenchmarks/WrapComputeBenchmark.swift Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift
git commit -m "feat: the wrap_compute line prints its checksum

The result-preservation witness for slice 55a (spec Decision 13): the
compute and drain checksums the anti-dead-code guard used to hold, folded
and printed as a trailing checksum= token. Lands BEFORE any edit on this
mode's measured path, so every --wrap-compute column in the record carries
it and 'byte-identical across all columns' can fail. Not a latency key --
the line still prints no bare p95_ns/p99_ns and creates no corpus row.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 10: The two `--wrap-compute` baseline columns (B1, B2)**

Two separate runs, so the host's run-to-run spread sits in the record and "flat" can be read against it.

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice55a-b-build.txt 2>&1; then echo "RELEASE BUILD RED"; fi
swift run -c release ViewportBenchmarks -- --wrap-compute > /tmp/slice55a-wc-B1.txt 2>&1
swift run -c release ViewportBenchmarks -- --wrap-compute > /tmp/slice55a-wc-B2.txt 2>&1
grep '^mode=wrap_compute' /tmp/slice55a-wc-B1.txt
grep '^mode=wrap_compute' /tmp/slice55a-wc-B2.txt
```

Then the comparison script every later column reuses. Save it once:

```bash
cat > /tmp/slice55a-compare.py <<'PY'
import sys
def parse(path):
    out = {}
    for line in open(path):
        if not line.startswith("mode=wrap_compute"): continue
        toks = dict(t.split("=", 1) for t in line.split() if "=" in t)
        out[toks["scenario"]] = toks
    return out
a, b = parse(sys.argv[1]), parse(sys.argv[2])
keys = ["compute_p95_ns", "compute_p99_ns", "drain_p95_ns", "drain_p99_ns", "reindex_ns"]
for sc in ["width_inf", "width_40", "width_10"]:
    for k in keys:
        x, y = int(a[sc][k]), int(b[sc][k])
        print("%-10s %-15s %12d -> %12d  ratio=%.3f" % (sc, k, x, y, (y / x) if x else float("nan")))
    same = a[sc]["checksum"] == b[sc]["checksum"]
    print("%-10s checksum        %s -> %s  %s" % (sc, a[sc]["checksum"], b[sc]["checksum"], "IDENTICAL" if same else "DIFFERENT -- FINDING"))
PY
python3 /tmp/slice55a-compare.py /tmp/slice55a-wc-B1.txt /tmp/slice55a-wc-B2.txt
```

Expected: three `IDENTICAL` lines (the checksum is deterministic — a `DIFFERENT` here means the token is not a witness, stop); the timing ratios are the **noise floor** — note the widest one, it is what "flat" is read against for commits 1, 3 and 5.

---

## Task 2: Commit 1 — `advanceVisualRows` and the cursor's two guards

Spec Decision 4 (guards 3, 4, 5), Contract 55a commit 1; drills (f1), (f2), (f3).

**Files:**
- Modify: `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift` (append `HookLog`, `OverridingLogicalLineLayout`)
- Modify: `Tests/TextEngineCoreTests/WrapComputeTests.swift` (+2 cases)
- Create: `Tests/TextEngineCoreTests/VisualRowWalkHelperTests.swift`
- Modify: `Sources/TextEngineCore/DocumentVisualRowCursor.swift`

**Interfaces:**
- Consumes: `VisualRowCursor<Metrics>.next() -> VisualRow?`; `ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:) -> VisualRowPackingQuery<Metrics>` (`.rows(cursor)` / `.failure`).
- Produces: `func advanceVisualRows<M: WrapMetricsSource>(_ cursor: inout VisualRowCursor<M>, by k: Int) -> VisualRow?` — **the result of the k-th `next()` call**: `nil` if `k <= 0` or if any of the `k` calls returned `nil` (it stops at that call); otherwise row `k − 1`. Node 4's query calls it with `k = rowInLine + 1` and keeps the result; the cursor calls it with `k = rowInStartLine` and discards it.
- Produces (tests): `final class HookLog { var logicalLineCalls: [Int] }`; `struct OverridingLogicalLineLayout: VisualRowLayoutSource` with `init(base: TestVisualRowLayout, log: HookLog, answer: @escaping (Int) -> Int)` — memberwise, in that order.

- [ ] **Step 1: The overriding conformer (test support)**

Append to `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift`:

```swift

/// Records every `logicalLine(containingVisualRow:)` call made through an
/// `OverridingLogicalLineLayout`.
final class HookLog {
    var logicalLineCalls: [Int] = []
}

/// A `TestVisualRowLayout` whose row-axis hook is OVERRIDDEN with a caller-supplied
/// answer, every call logged. Two uses (slice 55 spec, Decision 4 and D-24): hand a
/// malformed answer to each consumer of the hook -- the default cannot misbehave, an
/// override can, so the producer guards are only reachable this way -- and, with the
/// correct answer, pin that the consumers dispatch through the hook at all. The
/// prefix sum, row counts and column metrics are `base`'s, untouched: only the hook lies.
struct OverridingLogicalLineLayout: VisualRowLayoutSource {
    let base: TestVisualRowLayout
    let log: HookLog
    let answer: (Int) -> Int

    var lineCount: Int { base.lineCount }
    var rowHeight: Double { base.rowHeight }
    var wrapWidth: Double { base.wrapWidth }
    func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
    func columnOffset(inLine line: Int, column: Int) -> Double { base.columnOffset(inLine: line, column: column) }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { base.canBreak(beforeColumn: column, inLine: line) }
    func visualRowCount(inLine line: Int) -> Int { base.visualRowCount(inLine: line) }
    func firstVisualRow(ofLine line: Int) -> Int { base.firstVisualRow(ofLine: line) }
    func logicalLine(containingVisualRow g: Int) -> Int {
        log.logicalLineCalls.append(g)
        return answer(g)
    }
}
```

- [ ] **Step 2: The two failing cursor-guard tests**

Append inside `final class WrapComputeTests` in `Tests/TextEngineCoreTests/WrapComputeTests.swift` (before the closing `}`):

```swift

    // --- slice 55a, guards 3 and 4 (spec Decision 4): a malformed logicalLine override ---
    // Both cases must STREAM NOTHING -- next() is nil on the first call -- rather than
    // trap, stream the start line from row 0, or skip to the next line. The range comes
    // from compute over the plain layout (compute never consults the hook); only the
    // cursor sees the override.

    // The override answers a line outside 0..<lineCount; on the shipped code
    // `firstVisualRow(ofLine:)` traps on it. Drill (f2) removes the guard.
    func testCursorStreamsNothingWhenTheHookAnswersOutOfRange() {
        let base = layout()
        let rigged = OverridingLogicalLineLayout(base: base, log: HookLog(), answer: { _ in base.lineCount + 1 })
        let input = VariableViewportInput(scrollOffsetY: 5, viewportHeight: 5, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: base) else { return XCTFail("expected success") }
        var cursor = ViewportVirtualizer.visualRowGeometry(for: range, layout: rigged)
        XCTAssertNil(cursor.next(), "an out-of-range startLine must stream nothing, not trap")
    }

    // The override answers an in-range line whose firstVisualRow exceeds bufferStart, so
    // rowInStartLine is negative; on the shipped code the walk's `0..<k` range traps
    // (SIGTRAP). Drill (f1) removes the guard: with the helper total, the case then
    // streams line 2 FROM ROW 0 -- the plausible wrong answer this assertion catches.
    func testCursorStreamsNothingWhenTheHookMakesRowInLineNegative() {
        let base = layout()
        // bufferStart = 1 (row 1 of line 0); answering 2 gives firstVisualRow(2) = 4 > 1.
        let rigged = OverridingLogicalLineLayout(base: base, log: HookLog(), answer: { _ in 2 })
        let input = VariableViewportInput(scrollOffsetY: 5, viewportHeight: 5, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: base) else { return XCTFail("expected success") }
        XCTAssertEqual(range.bufferStart, 1, "fixture: the buffer must start inside a line")
        var cursor = ViewportVirtualizer.visualRowGeometry(for: range, layout: rigged)
        XCTAssertNil(cursor.next(), "a negative rowInStartLine must stream nothing, not trap or restart the line")
    }
```

- [ ] **Step 3: Run each new case alone and record the trap**

Run them one at a time — a trap aborts the whole test process, so a combined run would hide the second.

```bash
cd /Users/aabanschikov/swift-text-engine
for t in testCursorStreamsNothingWhenTheHookAnswersOutOfRange testCursorStreamsNothingWhenTheHookMakesRowInLineNegative; do
  if swift test --filter "WrapComputeTests.$t" > "/tmp/slice55a-t2-red-$t.txt" 2>&1; then
    echo "UNEXPECTED PASS: $t"
  else
    echo "EXPECTED RED (trap): $t"; rg -n "Fatal error|Index out of range|Range requires|Crash|error:" "/tmp/slice55a-t2-red-$t.txt" | head -2
  fi
done
```

Expected: both `EXPECTED RED (trap)` — the first with `Fatal error: Index out of range` (at `firstVisualRow`, `DocumentVisualRowCursor.swift:28`), the second with `Fatal error: Range requires lowerBound <= upperBound` (the `0..<k` at `:31`). Record both lines; they are the reds for guards 3 and 4.

- [ ] **Step 4: The failing helper suite**

Create `Tests/TextEngineCoreTests/VisualRowWalkHelperTests.swift`:

```swift
import XCTest
@testable import TextEngineCore

/// The shared within-line walk, pinned directly. Once both producers guard their own
/// input (slice 55 spec, Decision 4), no public entry point reaches the helper with
/// k < 0, so its own rule is observable only here. Three guards for one input, each with
/// its own drill -- do not read one of these reds as evidence for another.
final class VisualRowWalkHelperTests: XCTestCase {
    // Three rows [0,1) [1,2) [2,3): three cells of 10, breakable everywhere, width 5.
    private func cursor() -> VisualRowCursor<TestWrapMetrics> {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0], breakColumns: [1, 2])
        guard case .rows(let c) = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 5.0, metrics: metrics) else {
            fatalError("fixture must pack")
        }
        return c
    }

    // Drill (f3): restore the raw `for _ in 0..<k` and this traps.
    func testNegativeCountReturnsNilWithoutTrapping() {
        var c = cursor()
        XCTAssertNil(advanceVisualRows(&c, by: -1))
        XCTAssertEqual(c.next()?.rowInLine, 0, "nothing may be consumed")
    }

    func testZeroCountReturnsNilAndConsumesNothing() {
        var c = cursor()
        XCTAssertNil(advanceVisualRows(&c, by: 0))
        XCTAssertEqual(c.next()?.rowInLine, 0)
    }

    // The k-th next() result, and the cursor is left AT row k. The second assertion is
    // the inout pin: a by-value helper would advance a copy and leave this cursor at row 0.
    func testReturnsTheKthRowAndLeavesTheCursorAfterIt() {
        var c = cursor()
        XCTAssertEqual(advanceVisualRows(&c, by: 2)?.rowInLine, 1)
        XCTAssertEqual(c.next()?.rowInLine, 2)
    }

    // Past the end the answer is nil -- NOT the last row that was seen. Node 4's
    // exhaustion guard rests on exactly this (spec Decision 4).
    func testPastTheEndReturnsNilNotTheLastRowSeen() {
        var c = cursor()
        XCTAssertNil(advanceVisualRows(&c, by: 4))
        XCTAssertNil(c.next())
    }

    // Stops at the first nil rather than spinning: a helper that looped k times over an
    // exhausted cursor would not return from Int.max.
    func testStopsAtTheFirstNilRatherThanSpinning() {
        var c = cursor()
        XCTAssertNil(advanceVisualRows(&c, by: Int.max))
    }
}
```

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter VisualRowWalkHelperTests > /tmp/slice55a-t2-helper-red.txt 2>&1; then
  echo "UNEXPECTED PASS"
else
  echo "EXPECTED RED"; rg -n "error:" /tmp/slice55a-t2-helper-red.txt | head -2
fi
```

Expected: `EXPECTED RED` with `cannot find 'advanceVisualRows' in scope`.

- [ ] **Step 5: Implement the helper and the two guards**

Replace the whole of `Sources/TextEngineCore/DocumentVisualRowCursor.swift` with:

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
        // Guard 3 (slice 55 spec, Decision 4). The default hook cannot answer outside
        // 0..<lineCount; an override can, and `firstVisualRow(ofLine:)` below would trap
        // on it. Streaming has no failure channel, so the cursor takes the terminal state
        // it already has and streams nothing -- not the line from row 0, not the next
        // line; both are plausible-looking wrong answers.
        if startLine < 0 || startLine >= layout.lineCount {
            self.currentLine = layout.lineCount
            self.inner = nil
            self.remaining = 0
            return
        }
        let rowInStartLine = range.bufferStart - layout.firstVisualRow(ofLine: startLine)
        // Guard 4: an in-range line whose firstVisualRow exceeds bufferStart -- the other
        // way an override can lie -- makes this negative, and the walk would trap on its
        // range. Same terminal state.
        if rowInStartLine < 0 {
            self.currentLine = layout.lineCount
            self.inner = nil
            self.remaining = 0
            return
        }
        self.currentLine = startLine
        self.inner = Self.makeInner(line: startLine, layout: layout, wrapWidth: wrapWidth)
        // The accepted O(rowInLine) walk, through the helper node 4's query shares. A nil
        // `inner` (a malformed line, GIGO -- see makeInner) keeps its shipped meaning:
        // there is nothing to walk.
        if var cursor = inner {
            _ = advanceVisualRows(&cursor, by: rowInStartLine)
            inner = cursor
        }
    }

    private static func makeInner(line: Int, layout: Layout, wrapWidth: Double) -> VisualRowCursor<Layout>? {
        if case .rows(let cursor) = ViewportVirtualizer.visualRows(inLine: line, wrapWidth: wrapWidth, metrics: layout) {
            return cursor
        }
        // A `.failure` here means the provider violated the trusted per-line metrics
        // precondition: Decision 6 re-reads interior columnOffset/canBreak without
        // re-validating them, so a malformed line is undefined-behavior input, not a
        // handled case. Streaming has no failure channel — stop this line (GIGO) rather
        // than fabricate a row.
        return nil
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

/// Advances `cursor` by `k` rows and returns the result of the k-th `next()` call: `nil`
/// if `k <= 0` (a negative `k` never forms a range) or if any of the `k` calls returned
/// `nil` -- it stops at that call rather than spinning the rest -- and row `k - 1`
/// otherwise. NOT the last non-nil row seen along the way: node 4's `visualPointAt`
/// relies on `nil` meaning "the walk ran out before the row it asked for" (spec
/// Decision 4).
///
/// `inout` on purpose. `VisualRowCursor` is a struct; a by-value helper would advance a
/// copy and leave the caller's cursor where it was -- a mutation that compiles and passes
/// a one-row test. Shared by `DocumentVisualRowCursor.init` (k = rowInStartLine, return
/// discarded) and `visualPointAt` (k = rowInLine + 1, return kept), so the two agree on
/// "row k of line L" by construction rather than by two tests agreeing.
func advanceVisualRows<M: WrapMetricsSource>(_ cursor: inout VisualRowCursor<M>, by k: Int) -> VisualRow? {
    if k <= 0 { return nil }
    var last: VisualRow? = nil
    for _ in 0..<k {
        guard let row = cursor.next() else { return nil }
        last = row
    }
    return last
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

- [ ] **Step 6: Green — the four suites, then the whole thing**

```bash
cd /Users/aabanschikov/swift-text-engine
for s in VisualRowWalkHelperTests WrapComputeTests WrapComputeEquivalenceTests WrapRowQueryRoundTripTests; do
  if swift test --filter "$s" > "/tmp/slice55a-t2-green-$s.txt" 2>&1; then echo "green: $s"; else echo "RED: $s"; rg -n "error:|failed" "/tmp/slice55a-t2-green-$s.txt" | head -3; fi
done
if swift test > /tmp/slice55a-t2-full.txt 2>&1; then echo "suite green"; else echo "SUITE RED"; rg -n "error:|failed" /tmp/slice55a-t2-full.txt | head -5; fi
rg -n "Executed [0-9]+ tests" /tmp/slice55a-t2-full.txt | tail -1
```

Expected: four `green:` lines, `suite green`, count = baseline + 7.

- [ ] **Step 7: Drills (f1), (f2), (f3) — one red each, then revert**

**(f1)** — in `DocumentVisualRowCursor.swift`, delete the whole `if rowInStartLine < 0 { … return }` block (guard 4). With the helper still total, the negative case does not trap: `advanceVisualRows(&cursor, by: -3)` returns `nil`, the cursor is untouched, and `next()` streams line 2 from row 0.

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapComputeTests.testCursorStreamsNothingWhenTheHookMakesRowInLineNegative > /tmp/slice55a-drill-f1.txt 2>&1; then
  echo "UNEXPECTED PASS — guard 4 is not pinned"
else
  echo "EXPECTED RED (f1)"; rg -n "XCTAssertNil failed" /tmp/slice55a-drill-f1.txt | head -2
fi
git checkout -- Sources/TextEngineCore/DocumentVisualRowCursor.swift
```

Expected: `EXPECTED RED (f1)` with `XCTAssertNil failed: "VisualRowGeometry(row: … logicalLine: 2, rowInLine: 0 …"` — the "streams the start line from row 0" shape, and **not** a trap.

**(f2)** — delete the guard-3 block (`if startLine < 0 || startLine >= layout.lineCount { … }`):

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapComputeTests.testCursorStreamsNothingWhenTheHookAnswersOutOfRange > /tmp/slice55a-drill-f2.txt 2>&1; then
  echo "UNEXPECTED PASS — guard 3 is not pinned"
else
  echo "EXPECTED RED (f2, trap)"; rg -n "Fatal error|Index out of range" /tmp/slice55a-drill-f2.txt | head -2
fi
git checkout -- Sources/TextEngineCore/DocumentVisualRowCursor.swift
```

Expected: `EXPECTED RED (f2, trap)` at `firstVisualRow(ofLine:)`.

**(f3)** — in `advanceVisualRows`, delete `if k <= 0 { return nil }`. The direct test traps; the cursor's negative case stays **green**, because guard 4 rejects that input first (a red there would mean the producer guard is missing).

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter VisualRowWalkHelperTests.testNegativeCountReturnsNilWithoutTrapping > /tmp/slice55a-drill-f3-helper.txt 2>&1; then
  echo "UNEXPECTED PASS — the helper's rule is not pinned"
else
  echo "EXPECTED RED (f3, trap)"; rg -n "Fatal error|Range requires" /tmp/slice55a-drill-f3-helper.txt | head -2
fi
if swift test --filter WrapComputeTests.testCursorStreamsNothingWhenTheHookMakesRowInLineNegative > /tmp/slice55a-drill-f3-cursor.txt 2>&1; then
  echo "EXPECTED GREEN (f3): the producer guard catches it first"
else
  echo "UNEXPECTED RED — guard 4 is missing or misplaced"
fi
git checkout -- Sources/TextEngineCore/DocumentVisualRowCursor.swift
git diff --quiet -- Sources/TextEngineCore/DocumentVisualRowCursor.swift && echo "reverted"
```

Expected: `EXPECTED RED (f3, trap)`, `EXPECTED GREEN (f3)`, `reverted`. Record all three drills' observed lines.

- [ ] **Step 8: Foundation scan and commit 1**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter "VisualRowWalkHelperTests|WrapComputeTests" > /tmp/slice55a-t2-recheck.txt 2>&1; then echo "green after revert"; else echo "RED AFTER REVERT"; fi
FOUNDATION="$(rg -n 'Foundation' Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "PASS: Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION"; fi
git add Sources/TextEngineCore/DocumentVisualRowCursor.swift \
        Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift \
        Tests/TextEngineCoreTests/WrapComputeTests.swift \
        Tests/TextEngineCoreTests/VisualRowWalkHelperTests.swift
git commit -m "refactor: extract the within-line walk; the document cursor guards its start

advanceVisualRows(_:by:) is the one within-line walk (slice 55 spec, Decision 4):
it returns the result of the k-th next() call -- nil if k <= 0 or if any earlier
call was nil, stopping there -- and node 4's query will share it, so the cursor
and the query agree on 'row k of line L' by construction.

DocumentVisualRowCursor.init now guards the two ways a malformed
logicalLine(containingVisualRow:) override can lie: a startLine outside
0..<lineCount (trapped at firstVisualRow) and an in-range line whose
firstVisualRow exceeds the buffer start (trapped at the walk's 0..<k range,
SIGTRAP). Both stream nothing -- streaming has no failure channel. The
default hook cannot reach either branch; no existing test moves.

Drills recorded: (f1) remove the negative check -> the case streams the start
line from row 0 and the nil assertion reddens; (f2) remove the range check ->
the case traps at firstVisualRow; (f3) restore the raw 0..<k in the helper ->
the direct test traps while the cursor case stays green through guard 4.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 9: `--wrap-compute` column C1 (predicted flat)**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice55a-c1-build.txt 2>&1; then echo "RELEASE BUILD RED"; fi
swift run -c release ViewportBenchmarks -- --wrap-compute > /tmp/slice55a-wc-C1.txt 2>&1
grep '^mode=wrap_compute' /tmp/slice55a-wc-C1.txt
echo "--- C1 vs B2 ---"; python3 /tmp/slice55a-compare.py /tmp/slice55a-wc-B2.txt /tmp/slice55a-wc-C1.txt
```

Expected: three `IDENTICAL`; every ratio inside the B1/B2 spread from Task 1 Step 10. A ratio outside it is a **finding** for the record (not a reason to re-run until it looks flat).

---

## Task 3: Commit 2 — `visualRowAt` guards and the narrowed claim

Spec Decision 4 (guards 1, 2), Contract 55a commit 2; drills (d1), (f4); Documentation Updates (the three "same accept/reject set" sites and the `visualRowAt` paragraph).

**Files:**
- Modify: `Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift` (+4 cases)
- Modify: `Sources/TextEngineCore/WrapPositionQuery.swift`
- Modify: `Sources/TextEngineCore/WrapViewportVirtualizer.swift` (doc comment)
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: `OverridingLogicalLineLayout` (Task 2).
- Produces: `visualRowAt` returns `.failure(.invalidVisualRowLayout)` for `logicalLine ∉ 0..<lineCount` and for `rowInLine < 0`. Node 4's query inherits both by `.failure` propagation and must **not** re-check either.

- [ ] **Step 1: The four failing cases**

Append inside `final class WrapRowQueryValidationTests` (before the closing `}`):

```swift

    // --- slice 55a, guards 1 and 2 (spec Decision 4): a malformed logicalLine override ---
    // RiggedVisualRowLayout cannot carry these: they need real column metrics behind an
    // overridden hook, so they run on TestVisualRowLayout wrapped by
    // OverridingLogicalLineLayout. If a case here seems to need a conformer whose
    // firstVisualRow is total just to survive, the guard has been placed in the wrong
    // function (it belongs here, at the producer, not in node 4's query).

    // 3 lines x 1 row at width 20; firstRow [0,1,2,3]. y = 7 -> global row 1.
    private func plainLayout() -> TestVisualRowLayout {
        TestVisualRowLayout(lines: Array(repeating: (advances: [5.0], breaks: Set<Int>()), count: 3),
                            rowHeight: 5.0, wrapWidth: 20.0)
    }

    private func overriding(_ answer: Int) -> OverridingLogicalLineLayout {
        OverridingLogicalLineLayout(base: plainLayout(), log: HookLog(), answer: { _ in answer })
    }

    // Traps at firstVisualRow (WrapPositionQuery.swift:41) on the shipped code. Drill (d1).
    func testHookAnsweringAboveLineCountIsRejectedNotTrapped() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 7.0, layout: overriding(4)), .failure(.invalidVisualRowLayout))
    }

    // The boundary does NOT trap at the named site (conformer arrays are lineCount + 1
    // long): the unguarded query reads totalRows, yields a negative rowInLine, and returns
    // a location naming no row. Carried as its own value so the pin does not rest on a trap.
    func testHookAnsweringExactlyLineCountIsRejected() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 7.0, layout: overriding(3)), .failure(.invalidVisualRowLayout))
    }

    // The natural wrong edit is `logicalLine < lineCount` alone; the two values above
    // cannot see it. Traps on the shipped code.
    func testHookAnsweringNegativeIsRejectedNotTrapped() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 7.0, layout: overriding(-1)), .failure(.invalidVisualRowLayout))
    }

    // Guard 2: an in-range line whose firstVisualRow exceeds the row -- line 2 for global
    // row 1 (firstVisualRow(2) = 2 > 1). The shipped code returns
    // .row(globalRow: 1, logicalLine: 2, rowInLine: -1, .inRange): a location naming no row.
    func testHookMakingRowInLineNegativeIsRejected() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 7.0, layout: overriding(2)), .failure(.invalidVisualRowLayout))
    }
```

- [ ] **Step 2: Run each alone; two trap, two fail**

```bash
cd /Users/aabanschikov/swift-text-engine
for t in testHookAnsweringAboveLineCountIsRejectedNotTrapped testHookAnsweringExactlyLineCountIsRejected testHookAnsweringNegativeIsRejectedNotTrapped testHookMakingRowInLineNegativeIsRejected; do
  if swift test --filter "WrapRowQueryValidationTests.$t" > "/tmp/slice55a-t3-red-$t.txt" 2>&1; then
    echo "UNEXPECTED PASS: $t"
  else
    echo "EXPECTED RED: $t"; rg -n "Fatal error|Index out of range|XCTAssertEqual failed" "/tmp/slice55a-t3-red-$t.txt" | head -1
  fi
done
```

Expected: `AboveLineCount` and `Negative` → `Fatal error: Index out of range`; `ExactlyLineCount` → `XCTAssertEqual failed: ("row(… logicalLine: 3, rowInLine: -2 …)") is not equal to ("failure(…invalidVisualRowLayout)")`; `RowInLineNegative` → the same shape with `logicalLine: 2, rowInLine: -1`. Record the four lines.

- [ ] **Step 3: The two guards**

In `Sources/TextEngineCore/WrapPositionQuery.swift`:

Replace:
```swift
        case .line(let location):
            let globalRow = location.lineIndex
            let logicalLine = layout.logicalLine(containingVisualRow: globalRow)
            let rowInLine = globalRow - layout.firstVisualRow(ofLine: logicalLine)
            return .row(VisualRowLocation(
```
With:
```swift
        case .line(let location):
            let globalRow = location.lineIndex
            let logicalLine = layout.logicalLine(containingVisualRow: globalRow)
            // Guards 1 and 2 (slice 55 spec, Decision 4). The default hook cannot
            // misbehave (binarySearchLogicalLine returns a line in 0..<lineCount whose
            // firstVisualRow is <= globalRow); an override can, and this is the only
            // frame that can catch it -- one frame later the array below has been read.
            // A line outside the range would trap on the provider's array; an in-range
            // line whose firstVisualRow exceeds the row names no row at all. Both are
            // .invalidVisualRowLayout, not a trap and not a fabricated location; node
            // 4's query inherits this by .failure propagation and re-checks neither.
            // The upper bound (rowInLine < visualRowCount) is deliberately NOT checked
            // here: it costs a layout-axis probe, and the within-line walk catches it at
            // the point of use.
            if logicalLine < 0 || logicalLine >= layout.lineCount {
                return .failure(.invalidVisualRowLayout)
            }
            let rowInLine = globalRow - layout.firstVisualRow(ofLine: logicalLine)
            if rowInLine < 0 {
                return .failure(.invalidVisualRowLayout)
            }
            return .row(VisualRowLocation(
```

- [ ] **Step 4: Green, and the count bound is untouched**

The guards read `lineCount` and a value in hand: counter 1's bound (`WrapRowQueryCountTests`, `<= ceilLog2(lineCount) + 4`) must not move.

```bash
cd /Users/aabanschikov/swift-text-engine
for s in WrapRowQueryValidationTests WrapRowQueryCountTests WrapRowQueryTests WrapRowQueryEquivalenceTests; do
  if swift test --filter "$s" > "/tmp/slice55a-t3-green-$s.txt" 2>&1; then echo "green: $s"; else echo "RED: $s"; rg -n "error:|failed" "/tmp/slice55a-t3-green-$s.txt" | head -3; fi
done
if swift test > /tmp/slice55a-t3-full.txt 2>&1; then echo "suite green"; else echo "SUITE RED"; rg -n "error:|failed" /tmp/slice55a-t3-full.txt | head -5; fi
rg -n "Executed [0-9]+ tests" /tmp/slice55a-t3-full.txt | tail -1
```

Expected: four `green:`, `suite green`, count = Task 2's + 4.

- [ ] **Step 5: Drills (d1) and (f4)**

**(d1)** — delete the guard-1 block (`if logicalLine < 0 || logicalLine >= layout.lineCount { … }`). Run on the value that traps at the named site (`> lineCount`), not the boundary:

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryValidationTests.testHookAnsweringAboveLineCountIsRejectedNotTrapped > /tmp/slice55a-drill-d1.txt 2>&1; then
  echo "UNEXPECTED PASS — guard 1 is not pinned"
else
  echo "EXPECTED RED (d1, trap)"; rg -n "Fatal error|Index out of range" /tmp/slice55a-drill-d1.txt | head -1
fi
git checkout -- Sources/TextEngineCore/WrapPositionQuery.swift
```

**(f4)** — delete the guard-2 block (`if rowInLine < 0 { … }`) only. The direct pin reddens with a `.row` carrying a negative `rowInLine`; the `== lineCount` case stays green because guard 1 still catches it.

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapRowQueryValidationTests.testHookMakingRowInLineNegativeIsRejected > /tmp/slice55a-drill-f4.txt 2>&1; then
  echo "UNEXPECTED PASS — guard 2 is not pinned"
else
  echo "EXPECTED RED (f4)"; rg -n "XCTAssertEqual failed" /tmp/slice55a-drill-f4.txt | head -1
fi
if swift test --filter WrapRowQueryValidationTests.testHookAnsweringExactlyLineCountIsRejected > /tmp/slice55a-drill-f4-boundary.txt 2>&1; then
  echo "EXPECTED GREEN (f4): the boundary is guard 1's"
else
  echo "UNEXPECTED RED — guard 1 no longer covers == lineCount"
fi
git checkout -- Sources/TextEngineCore/WrapPositionQuery.swift
git diff --quiet -- Sources/TextEngineCore/WrapPositionQuery.swift && echo "reverted"
```

Expected: `EXPECTED RED (d1, trap)`; `EXPECTED RED (f4)` with `rowInLine: -1`; `EXPECTED GREEN (f4)`; `reverted`.

- [ ] **Step 6: Narrow the "same accept/reject set" claim in its three places, and state the new behaviour**

**(a)** `Sources/TextEngineCore/WrapPositionQuery.swift`, the doc comment. Replace:
```swift
    /// Stateless, O(1) core memory. Runs `compute(_:layout:)`'s layout ladder (the same
    /// shared helper, so the two entry points accept and reject exactly the same
    /// layouts), then delegates the row-axis search to `lineAt` over a uniform row axis
```
With:
```swift
    /// Stateless, O(1) core memory. Runs `compute(_:layout:)`'s layout ladder (the same
    /// shared helper, so the two entry points accept and reject exactly the same
    /// layouts AT THE LADDER; after it they diverge on one class -- a
    /// `logicalLine(containingVisualRow:)` override answering outside `0..<lineCount`,
    /// or an in-range line whose `firstVisualRow` exceeds the row -- which `compute`
    /// never consults and this query rejects with `.invalidVisualRowLayout` rather than
    /// trapping or naming a row that does not exist; the default hook cannot produce
    /// either), then delegates the row-axis search to `lineAt` over a uniform row axis
```

**(b)** `Sources/TextEngineCore/WrapViewportVirtualizer.swift`. Replace:
```swift
/// The layout half of the visual-row validation ladder, shared verbatim by
/// `compute(_:layout:)` and `visualRowAt(y:layout:)` so their accept/reject sets are
/// equal by construction rather than by inspection (spec Decision 5).
```
With:
```swift
/// The layout half of the visual-row validation ladder, shared verbatim by
/// `compute(_:layout:)` and `visualRowAt(y:layout:)` so their accept/reject sets are
/// equal AT THE LADDER by construction rather than by inspection (slice 53 spec,
/// Decision 5). After the ladder the two diverge on exactly one class -- a malformed
/// `logicalLine(containingVisualRow:)` override -- which `compute` never consults and
/// `visualRowAt` rejects (slice 55 spec, Decision 4).
```

**(c)** `AGENTS.md`, the `visualRowAt` paragraph. Replace:
```
layout ladder — the *same* extracted helper, so the two entry points accept and
reject exactly the same layouts by construction — then delegates the row-axis search
```
With:
```
layout ladder — the *same* extracted helper, so the two entry points accept and
reject exactly the same layouts **at the ladder** by construction; after it they
diverge on one class, a malformed `logicalLine(containingVisualRow:)` override (a line
outside `0..<lineCount`, or an in-range line whose `firstVisualRow` exceeds the row),
which `compute` never consults and `visualRowAt` rejects with
`.failure(.invalidVisualRowLayout)` instead of trapping or naming a row that does not
exist (slice 55a; the default hook cannot produce either) — then delegates the row-axis search
```

```bash
cd /Users/aabanschikov/swift-text-engine
HITS="$(rg -n 'exactly the same layouts by construction|accept/reject sets are\s*$|equal by construction rather than by inspection \(spec Decision 5\)' AGENTS.md Sources/TextEngineCore || true)"
if [ -z "$HITS" ]; then echo "PASS: no unnarrowed claim remains"; else echo "FAIL:"; echo "$HITS"; fi
if swift build > /tmp/slice55a-t3-docbuild.txt 2>&1; then echo "build green"; else echo "BUILD RED"; fi
```

Expected: `PASS`, `build green`.

- [ ] **Step 7: `--wrap-row-query` checksum byte-identical to the baseline**

The guards are unreachable for the benchmark's conformer; the numbers may move within noise, the checksums may not.

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice55a-t3-relbuild.txt 2>&1; then echo "RELEASE BUILD RED"; fi
swift run -c release ViewportBenchmarks -- --wrap-row-query > /tmp/slice55a-wrq-after-c2.txt 2>&1
grep '^mode=wrap_row_query' /tmp/slice55a-wrq-after-c2.txt
BEFORE="$(sed -nE 's/.*scenario=([^ ]+).*checksum=([0-9]+).*/\1 \2/p' /tmp/slice55a-wrq-baseline.txt)"
AFTER="$(sed -nE 's/.*scenario=([^ ]+).*checksum=([0-9]+).*/\1 \2/p' /tmp/slice55a-wrq-after-c2.txt)"
if [ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ]; then echo "PASS: wrap_row_query checksums byte-identical (4 scenarios)"; else echo "FAIL: checksums moved"; echo "$BEFORE"; echo "---"; echo "$AFTER"; fi
```

Expected: `PASS`.

- [ ] **Step 8: Commit 2**

```bash
cd /Users/aabanschikov/swift-text-engine
FOUNDATION="$(rg -n 'Foundation' Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "PASS: Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION"; fi
git add Sources/TextEngineCore/WrapPositionQuery.swift Sources/TextEngineCore/WrapViewportVirtualizer.swift AGENTS.md \
        Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift
git commit -m "feat: visualRowAt rejects a malformed logicalLine override instead of trapping

Two producer guards (slice 55 spec, Decision 4): a logicalLine outside
0..<lineCount -- which trapped on the provider's array one frame later, or
at the boundary read totalRows and returned a location with a negative
rowInLine -- and an in-range line whose firstVisualRow exceeds the located
row. Both are now .failure(.invalidVisualRowLayout). The default hook cannot
reach either branch; no existing test moves, and the layout-axis probe bound
is untouched (both checks read lineCount and a value in hand).

The 'compute and visualRowAt accept and reject exactly the same layouts'
claim is narrowed to the shared ladder in its three places: after it the two
diverge on this one class, which compute never consults.

Drills recorded: (d1) remove the range check -> the > lineCount case traps
at firstVisualRow; (f4) remove the negative-rowInLine check -> the direct pin
reddens with rowInLine -1 while the boundary case stays green through the
range check. --wrap-row-query checksums byte-identical to the baseline.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 4: Commit 3 — `validateWrapLine` and the stored `total`

Spec Decision 13, Contract 55a commit 3. Behaviour-preserving: same three probes, same order, same failures, same rows. **No new test, no drill** (a refactor with no new standing guarantee has nothing to break); the evidence is negative — the five named suites pass **unedited**, and the `wrap_compute` checksum holds.

**Files:**
- Modify: `Sources/TextEngineCore/VisualRowCursor.swift`

**Interfaces:**
- Produces: `enum WrapLineMetrics { case valid(count: Int, total: Double); case failure(ViewportValidationError) }`; `func validateWrapLine<M: WrapMetricsSource>(inLine line: Int, wrapWidth: Double, metrics: M) -> WrapLineMetrics`; `VisualRowCursor.init(line:columnCount:total:wrapWidth:metrics:)` (internal). `total` is the line's total advance as the ladder validated it — `0` on a blank line. Node 4's step 3 calls `validateWrapLine` and builds the cursor from `(count, total)`, probing neither again.

- [ ] **Step 1: Confirm nothing else constructs the cursor**

```bash
cd /Users/aabanschikov/swift-text-engine
rg -n "VisualRowCursor\(" Sources Tests
```

Expected: exactly one construction site, in `visualRows` (`Sources/TextEngineCore/VisualRowCursor.swift`). Any other hit must be updated in Step 2.

- [ ] **Step 2: The extraction**

Replace the whole of `Sources/TextEngineCore/VisualRowCursor.swift` with:

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
    /// The line's total advance, `columnOffset(inLine:column: columnCount)` as the
    /// ladder validated it (`0` on a blank line). Stored so `greedyEnd` can decide
    /// "does the remaining suffix fit" from a value in hand rather than a probe
    /// (slice 55 spec, Decisions 12 and 13). Never re-read from the provider.
    private let total: Double
    private let wrapWidth: Double
    private var nextStartColumn: Int
    private var nextRowInLine: Int
    private var finished: Bool

    init(line: Int, columnCount: Int, total: Double, wrapWidth: Double, metrics: Metrics) {
        self.metrics = metrics
        self.line = line
        self.columnCount = columnCount
        self.total = total
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
        let end = greedyEnd(from: start, startOffset: startOffset)

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
}

/// What the per-line wrap ladder hands back: the values its three probes read, so a
/// caller can build a `VisualRowCursor` without probing them again.
enum WrapLineMetrics {
    case valid(count: Int, total: Double)   // total == 0 on a blank line
    case failure(ViewportValidationError)
}

/// The per-line wrap ladder, shared by `visualRows(inLine:wrapWidth:metrics:)` and node
/// 4's `visualPointAt` (slice 55 spec, Decision 13): the same three probes in the same
/// order with the same failures as the ladder `visualRows` carried inline --
/// `columnCount(inLine:)`, then `wrapWidth`, then `columnOffset(inLine:column: 0)`, then
/// (non-blank lines only) `columnOffset(inLine:column: count)`. Behaviour-preserving by
/// construction; `WrapValidationTests` pins each rung and its order.
func validateWrapLine<Metrics: WrapMetricsSource>(
    inLine line: Int,
    wrapWidth: Double,
    metrics: Metrics
) -> WrapLineMetrics {
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
    if count == 0 {
        // The probe above validated columnOffset(0) == 0, which IS the blank line's
        // total: no fourth probe.
        return .valid(count: 0, total: 0.0)
    }
    let total = metrics.columnOffset(inLine: line, column: count)
    if !total.isFinite || total <= 0.0 {
        return .failure(.invalidColumnMetrics)
    }
    return .valid(count: count, total: total)
}

extension ViewportVirtualizer {
    /// Streams the visual rows of logical line `inLine` packed to `wrapWidth`, in
    /// visual order. Stateless; the cursor is lazy (no packing happens here).
    /// `inLine` is a precondition (the source carries no `lineCount`), exactly like
    /// `columnAt`. Validates `wrapWidth` (`> 0`, so `+∞` is allowed — the
    /// equivalence case) and runs the same O(1) metrics ladder as `columnAt`
    /// (`validateWrapLine`) before handing back the lazy cursor.
    public static func visualRows<Metrics: WrapMetricsSource>(
        inLine line: Int,
        wrapWidth: Double,
        metrics: Metrics
    ) -> VisualRowPackingQuery<Metrics> {
        switch validateWrapLine(inLine: line, wrapWidth: wrapWidth, metrics: metrics) {
        case .failure(let error):
            return .failure(error)
        case .valid(let count, let total):
            return .rows(VisualRowCursor(line: line, columnCount: count, total: total, wrapWidth: wrapWidth, metrics: metrics))
        }
    }
}
```

- [ ] **Step 3: The five suites, unedited, plus everything else**

```bash
cd /Users/aabanschikov/swift-text-engine
if git diff --quiet HEAD -- Tests/; then echo "PASS: no test file edited"; else echo "STOP: a test was edited during a neutral extraction"; git diff --stat HEAD -- Tests/; fi
for s in WrapPackingTests WrapValidationTests WrapComputeTests VisualRowEquivalenceTests WrapComputeEquivalenceTests VisualRowWalkHelperTests; do
  if swift test --filter "$s" > "/tmp/slice55a-t4-$s.txt" 2>&1; then echo "green: $s"; else echo "RED: $s"; rg -n "error:|failed" "/tmp/slice55a-t4-$s.txt" | head -3; fi
done
if swift test > /tmp/slice55a-t4-full.txt 2>&1; then echo "suite green"; else echo "SUITE RED"; rg -n "error:|failed" /tmp/slice55a-t4-full.txt | head -5; fi
rg -n "Executed [0-9]+ tests" /tmp/slice55a-t4-full.txt | tail -1
```

Expected: `PASS: no test file edited`, six `green:`, `suite green`, count unchanged from Task 3.

- [ ] **Step 4: Foundation scan and commit 3**

```bash
cd /Users/aabanschikov/swift-text-engine
FOUNDATION="$(rg -n 'Foundation' Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "PASS: Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION"; fi
git add Sources/TextEngineCore/VisualRowCursor.swift
git commit -m "refactor: extract the per-line wrap ladder; the cursor stores total

validateWrapLine(inLine:wrapWidth:metrics:) is the ladder visualRows carried
inline -- the same three probes, order and failures -- now handing back the
(count, total) it read so a caller can build the cursor without probing
again (slice 55 spec, Decision 13). visualRows is a thin wrapper with its
signature, return type, probe order and failures unchanged. VisualRowCursor
stores total beside columnCount through its internal init; no public type
gains a field. The blank line needs no fourth probe: columnOffset(0) == 0 is
validated and IS its total.

Behaviour-preserving, evidence negative: WrapPackingTests,
WrapValidationTests, WrapComputeTests, VisualRowEquivalenceTests and
WrapComputeEquivalenceTests pass unedited; the wrap_compute checksum is
byte-identical (recorded as column C3).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: `--wrap-compute` column C3 (predicted flat)**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice55a-c3-build.txt 2>&1; then echo "RELEASE BUILD RED"; fi
swift run -c release ViewportBenchmarks -- --wrap-compute > /tmp/slice55a-wc-C3.txt 2>&1
grep '^mode=wrap_compute' /tmp/slice55a-wc-C3.txt
echo "--- C3 vs C1 ---"; python3 /tmp/slice55a-compare.py /tmp/slice55a-wc-C1.txt /tmp/slice55a-wc-C3.txt
```

Expected: three `IDENTICAL`; ratios within the noise floor.

---

## Task 5: Commit 4 — the suffix-fits short-circuit, red-first

Spec Decision 12, Contract 55a commit 4; drills (l), (m); the node 1 / node 2 cost wording and the two doc comments (Documentation Updates).

**Files:**
- Create: `Tests/TextEngineCoreTests/WrapPackingCountTests.swift`
- Modify: `Sources/TextEngineCore/VisualRowCursor.swift` (`greedyEnd`)
- Modify: `Sources/TextEngineCore/DocumentVisualRowCursor.swift` (doc comment lines 4-5)
- Modify: `AGENTS.md` (node 1 and node 2 paragraphs)

**Interfaces:**
- Consumes: `VisualRowCursor.total` (Task 4).
- Produces: `greedyEnd` returns `columnCount` without a probe whenever `total − startOffset <= wrapWidth`. Cost claims node 4's spec and `AGENTS.md` rely on: a fitting line packs in O(1); the last row of any line packs in O(1); on a fitting line one `next()` costs exactly 2 `columnOffset` probes and 0 `canBreak`.

- [ ] **Step 1: The failing probe-count suite**

Create `Tests/TextEngineCoreTests/WrapPackingCountTests.swift`:

```swift
import XCTest
import TextEngineCore

/// Decision 12's two O(1) cases (slice 55 spec), pinned at node 1's own entry point.
///
/// Result-bearing suites cannot see this: the short-circuit changes no row, so a
/// version that fires on too few rows -- say only when `start == 0` -- leaves every
/// packing result, every checksum and every result test green while the cost claim in
/// AGENTS.md ("the last row of any line packs in O(1)") is false. Only a probe count
/// can read it. Both cases are RED on the packer as shipped before slice 55a.
final class WrapPackingCountTests: XCTestCase {
    private final class ProbeCounter {
        var columnCountCalls = 0
        var columnOffsetCalls = 0
        var canBreakCalls = 0
    }

    private struct CountingWrapMetrics: WrapMetricsSource {
        let base: TestWrapMetrics
        let counter: ProbeCounter
        func columnCount(inLine line: Int) -> Int {
            counter.columnCountCalls += 1; return base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.columnOffsetCalls += 1; return base.columnOffset(inLine: line, column: column)
        }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
            counter.canBreakCalls += 1; return base.canBreak(beforeColumn: column, inLine: line)
        }
    }

    // A line that fits: 8 cells of 10 (total 80) at width 100, breakable at every interior
    // column -- so a scan would have seven opportunities to read.
    func testFittingLinePacksWithoutScanning() {
        let counter = ProbeCounter()
        let metrics = CountingWrapMetrics(
            base: TestWrapMetrics(advances: Array(repeating: 10.0, count: 8), breakColumns: Set(1..<8)),
            counter: counter)
        guard case .rows(var cursor) = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics) else {
            return XCTFail("expected .rows")
        }
        XCTAssertEqual(counter.columnCountCalls, 1, "the ladder reads columnCount once")
        XCTAssertEqual(counter.columnOffsetCalls, 2, "the ladder reads columnOffset(0) and columnOffset(count)")

        XCTAssertEqual(cursor.next(), VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 8, width: 80.0))
        XCTAssertEqual(counter.canBreakCalls, 0, "a line that fits must not scan its break opportunities")
        // Exactly two more: the row's start and end offsets, nothing per cell. This is the
        // `+ 2` in node 4's `3 + 2` column-axis count.
        XCTAssertEqual(counter.columnOffsetCalls, 4, "next() on a fitting line reads start and end, and nothing else")
        XCTAssertNil(cursor.next())
    }

    // A wrapped line: 12 cells of 10 at width 40 -> rows [0,4) [4,8) [8,12). The last
    // row's remaining suffix fits by definition, so it must add no scan; the row before
    // it must, or "adds zero" would be vacuous.
    func testLastRowOfAWrappedLineAddsNoScan() {
        let counter = ProbeCounter()
        let metrics = CountingWrapMetrics(
            base: TestWrapMetrics(advances: Array(repeating: 10.0, count: 12), breakColumns: Set(1..<12)),
            counter: counter)
        guard case .rows(var cursor) = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 40.0, metrics: metrics) else {
            return XCTFail("expected .rows")
        }
        var rows: [VisualRow] = []
        var canBreakAfterRow: [Int] = []
        while let row = cursor.next() {
            rows.append(row)
            canBreakAfterRow.append(counter.canBreakCalls)
        }
        XCTAssertEqual(rows.map { $0.endColumn }, [4, 8, 12], "fixture must pack to exactly three rows")

        let penultimateAdded = canBreakAfterRow[1] - canBreakAfterRow[0]
        let lastAdded = canBreakAfterRow[2] - canBreakAfterRow[1]
        XCTAssertGreaterThan(penultimateAdded, 0, "fixture guard: an interior row must scan, or the assertion below covers nothing")
        XCTAssertEqual(lastAdded, 0, "the last row of a wrapped line must not scan -- its suffix fits")
    }
}
```

- [ ] **Step 2: Run it to verify both cases fail on the shipped packer**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapPackingCountTests > /tmp/slice55a-t5-red.txt 2>&1; then
  echo "UNEXPECTED PASS — the packer already short-circuits?"
else
  echo "EXPECTED RED"; rg -n "XCTAssertEqual failed" /tmp/slice55a-t5-red.txt | head -4
fi
```

Expected: `EXPECTED RED` — `canBreakCalls` `("7") is not equal to ("0")` and `columnOffsetCalls` `("12") is not equal to ("4")` in the first case; `lastAdded` `("3") is not equal to ("0")` in the second. Record these; they are the red-first evidence for commit 4.

- [ ] **Step 3: The short-circuit**

In `Sources/TextEngineCore/VisualRowCursor.swift`, replace:
```swift
    // The largest legal end `e > start` with `columnOffset(e) - startOffset <=
    // wrapWidth`; if none fits, the smallest legal end `e > start` (forced overflow
    // — a row wider than wrapWidth). `columnCount` is always a legal end; interior
    // legal ends are columns `c` with `canBreak(beforeColumn: c)`. Relies on the
    // monotone `columnOffset` precondition: once a legal end overflows, every later
    // one does too, so the walk stops there. O(cells in the row).
    private func greedyEnd(from start: Int, startOffset: Double) -> Int {
        var lastFitting = -1   // largest legal end seen that fits
```
With:
```swift
    // The largest legal end `e > start` with `columnOffset(e) - startOffset <=
    // wrapWidth`; if none fits, the smallest legal end `e > start` (forced overflow
    // — a row wider than wrapWidth). `columnCount` is always a legal end; interior
    // legal ends are columns `c` with `canBreak(beforeColumn: c)`. Relies on the
    // monotone `columnOffset` precondition: once a legal end overflows, every later
    // one does too, so the walk stops there.
    //
    // Cost: O(1) when the remaining suffix fits -- `columnCount` is a legal end and,
    // under the strictly-increasing contract, every legal end before it fits too, so
    // the scan would finish at `columnCount` anyway; the short-circuit returns it with
    // no probe (slice 55 spec, Decision 12). That is every row of a line that fits the
    // width (∞ included) and the LAST row of every line; only the interior rows of a
    // wrapped line scan, O(cells in the row). Bit-identical to the scan: both compare
    // in the same `offset − startOffset <= wrapWidth` form and IEEE subtraction of a
    // common operand is monotone; on an interior-GIGO NaN startOffset both fall to
    // `firstLegal`. Pinned by WrapPackingCountTests; the predicate must NOT be narrowed
    // to `start == 0` -- that keeps every row identical and loses the last-row case.
    private func greedyEnd(from start: Int, startOffset: Double) -> Int {
        if total - startOffset <= wrapWidth { return columnCount }
        var lastFitting = -1   // largest legal end seen that fits
```

- [ ] **Step 4: Green — the pin, the five unedited suites, the whole suite**

```bash
cd /Users/aabanschikov/swift-text-engine
if git diff --quiet HEAD -- Tests/TextEngineCoreTests/WrapPackingTests.swift Tests/TextEngineCoreTests/WrapValidationTests.swift Tests/TextEngineCoreTests/WrapComputeTests.swift Tests/TextEngineCoreTests/VisualRowEquivalenceTests.swift Tests/TextEngineCoreTests/WrapComputeEquivalenceTests.swift; then echo "PASS: the five suites are unedited"; else echo "STOP: a neutral-suite file was edited"; fi
for s in WrapPackingCountTests WrapPackingTests WrapValidationTests WrapComputeTests VisualRowEquivalenceTests WrapComputeEquivalenceTests WrapRowQueryRoundTripTests; do
  if swift test --filter "$s" > "/tmp/slice55a-t5-$s.txt" 2>&1; then echo "green: $s"; else echo "RED: $s"; rg -n "error:|failed" "/tmp/slice55a-t5-$s.txt" | head -3; fi
done
if swift test > /tmp/slice55a-t5-full.txt 2>&1; then echo "suite green"; else echo "SUITE RED"; rg -n "error:|failed" /tmp/slice55a-t5-full.txt | head -5; fi
rg -n "Executed [0-9]+ tests" /tmp/slice55a-t5-full.txt | tail -1
```

Expected: `PASS`, seven `green:`, `suite green`, count = Task 3's + 2.

- [ ] **Step 5: Drills (l) and (m)**

**(l) — invert the predicate.** Change `if total - startOffset <= wrapWidth { return columnCount }` to `if total - startOffset >= wrapWidth { return columnCount }`. Inversion, not deletion: deleting a result-preserving branch reddens nothing.

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapPackingTests > /tmp/slice55a-drill-l-packing.txt 2>&1; then
  echo "UNEXPECTED PASS (l): WrapPackingTests"
else
  echo "EXPECTED RED (l): WrapPackingTests"; rg -n "XCTAssertEqual failed" /tmp/slice55a-drill-l-packing.txt | head -2
fi
for s in VisualRowEquivalenceTests WrapComputeEquivalenceTests; do
  if swift test --filter "$s" > "/tmp/slice55a-drill-l-$s.txt" 2>&1; then echo "EXPECTED GREEN (l): $s -- an ∞ oracle cannot see the predicate's shape"; else echo "UNEXPECTED RED (l): $s"; fi
done
git checkout -- Sources/TextEngineCore/VisualRowCursor.swift
```

Expected: `EXPECTED RED (l): WrapPackingTests` (`testCharWrapOneCellPerRow` / `testUnbreakableRunOverflowsOneRow` / `testPartitionTilesTheLine` collapse lines to one row) and **two `EXPECTED GREEN (l)`**: at `∞` the inverted predicate `total − startOffset >= ∞` is false and the scan runs, at `width == total` both predicates are true, and an equivalence fixture holds only fitting lines, on which the two agree. Observed in this plan's smoke test. That blindness is why the packer's cost claims cannot be pinned by the oracles and need `WrapPackingCountTests` — record the greens beside the red.

**(m) — narrow the predicate to the first row.** Change the branch to `if start == 0 && total - startOffset <= wrapWidth { return columnCount }` (the rejected query-side shape). Every result-bearing suite stays green; only the last-row pin reddens.

```bash
cd /Users/aabanschikov/swift-text-engine
for s in WrapPackingTests VisualRowEquivalenceTests WrapComputeEquivalenceTests; do
  if swift test --filter "$s" > "/tmp/slice55a-drill-m-$s.txt" 2>&1; then echo "EXPECTED GREEN (m): $s -- results unchanged"; else echo "UNEXPECTED RED (m): $s"; fi
done
if swift test --filter WrapPackingCountTests.testFittingLinePacksWithoutScanning > /tmp/slice55a-drill-m-fit.txt 2>&1; then echo "EXPECTED GREEN (m): the fitting-line case cannot see a start == 0 narrowing"; else echo "UNEXPECTED RED (m): fitting case"; fi
if swift test --filter WrapPackingCountTests.testLastRowOfAWrappedLineAddsNoScan > /tmp/slice55a-drill-m-last.txt 2>&1; then
  echo "UNEXPECTED PASS (m) — the last-row case is not pinned"
else
  echo "EXPECTED RED (m): the last-row pin is the only test that reads this"; rg -n "XCTAssertEqual failed" /tmp/slice55a-drill-m-last.txt | head -1
fi
git checkout -- Sources/TextEngineCore/VisualRowCursor.swift
git diff --quiet -- Sources/TextEngineCore/VisualRowCursor.swift && echo "reverted"
```

Expected: four `EXPECTED GREEN (m)`, one `EXPECTED RED (m)` with `("3") is not equal to ("0")`, `reverted`. That asymmetry is the point of the drill: record it.

- [ ] **Step 6: The cost wording — `AGENTS.md` and the two doc comments**

**(a)** `AGENTS.md`, node 1 paragraph. Replace:
```
oracle). This is per-logical-line packing only — cross-line aggregation, vertical
stacking, and wrap-aware `compute` are later nodes. O(1) core memory,
O(cells-in-row) per `next()`.
```
With:
```
oracle). This is per-logical-line packing only — cross-line aggregation, vertical
stacking, and wrap-aware `compute` are later nodes. O(1) core memory,
O(cells-in-row) per `next()` — except that a row whose remaining suffix fits `wrapWidth`
is answered in O(1) with no scan (the packer checks `total − startOffset <= wrapWidth`
before scanning, from the `total` the per-line ladder validated), so a line that fits
packs in O(1), `∞` included, and so does the **last** row of every line; only the
interior rows of a wrapped line scan their cells. Pinned by `WrapPackingCountTests`
(slice 55a).
```

**(b)** `AGENTS.md`, node 2 paragraph. Replace:
```
node 1's per-line oracle. Reaching the first buffered row of a multi-row line
costs the documented O(rowInLine) within-line walk (greedy packing is
sequential); random access inside one line is a later, separate provider node.
```
With:
```
node 1's per-line oracle. Reaching the first buffered row of a multi-row line
costs the documented O(rowInLine) within-line walk (greedy packing is
sequential: rows `0…rowInLine−1` are packed, each interior row scanning its cells,
while a line's last row is O(1) by node 1's suffix short-circuit); random access
inside one line is a later, separate provider node. The walk is one shared internal
helper, `advanceVisualRows(_:by:)`, written so node 4's query reuses it rather than
copying it. A malformed `logicalLine(containingVisualRow:)` override — a start line
outside `0..<lineCount`, or an in-range line whose `firstVisualRow` exceeds the buffer
start — makes the cursor **stream nothing** rather than trap (streaming has no failure
channel; slice 55a).
```

**(c)** `Sources/TextEngineCore/DocumentVisualRowCursor.swift`, the type's doc comment. Replace:
```swift
/// `ViewportVirtualizer.visualRowGeometry(for:layout:)`. Cost: O(rowInStartLine +
/// buffer) — the O(rowInStartLine) is the accepted within-line walk (spec fork).
```
With:
```swift
/// `ViewportVirtualizer.visualRowGeometry(for:layout:)`. Cost: O(rowInStartLine +
/// buffer) — the O(rowInStartLine) is the accepted within-line walk (node 2's spec
/// fork): rows 0…rowInStartLine−1 of the start line are packed, each interior row
/// scanning its cells, while a line's last row is O(1) (node 1's suffix short-circuit).
```

**(d)** `Sources/TextEngineCore/VisualRowCursor.swift` — the `greedyEnd` comment was rewritten in Step 3; nothing further.

```bash
cd /Users/aabanschikov/swift-text-engine
if rg -q 'O\(cells-in-row\) per `next\(\)`\.$' AGENTS.md; then echo "FAIL: node 1 wording not updated"; else echo "PASS: node 1 wording updated"; fi
if rg -q 'suffix short-circuit' AGENTS.md Sources/TextEngineCore/DocumentVisualRowCursor.swift; then echo "PASS: cost wording present"; else echo "FAIL: cost wording missing"; fi
if swift build > /tmp/slice55a-t5-docbuild.txt 2>&1; then echo "build green"; else echo "BUILD RED"; fi
```

Expected: two `PASS`, `build green`.

- [ ] **Step 7: Foundation scan and commit 4**

```bash
cd /Users/aabanschikov/swift-text-engine
FOUNDATION="$(rg -n 'Foundation' Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "PASS: Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION"; fi
git add Sources/TextEngineCore/VisualRowCursor.swift Sources/TextEngineCore/DocumentVisualRowCursor.swift AGENTS.md \
        Tests/TextEngineCoreTests/WrapPackingCountTests.swift
git commit -m "feat: the packer short-circuits when the remaining suffix fits

greedyEnd returns columnCount without a probe whenever
total − startOffset <= wrapWidth (slice 55 spec, Decision 12): columnCount
is always a legal end, and under the strictly-increasing columnOffset
contract every legal end before it fits too, so the scan would finish there
anyway. Bit-identical to the scan (same comparison form; IEEE subtraction of
a common operand is monotone; NaN falls to firstLegal on both). Every line
that fits the width -- ∞ included -- and the LAST row of every line now pack
in O(1); only the interior rows of a wrapped line scan.

Red-first: WrapPackingCountTests pins both O(1) cases (zero canBreak on a
fitting line, exactly two columnOffset reads in next(); zero canBreak added
by a wrapped line's last row) and failed on the shipped packer (7/12/3).
The five neutral suites pass unedited.

Drills recorded: (l) invert the predicate -> WrapPackingTests reddens while
the ∞ oracles stay green (at ∞ the inverted predicate is false, at width ==
total both are true; an oracle fixture holds only fitting lines); (m) narrow
it to start == 0 -> every result-bearing suite stays green and only the
last-row pin reddens, which is why that pin exists.

AGENTS.md's node 1 and node 2 cost wording and the two doc comments state
the new cost.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 8: `--wrap-compute` column C4 — the one predicted move, checked per width and per token**

Decision 12's table on this mode's fixture (80 cells, advance 1): `greedyEnd` scan iterations per line go `80 → 0` at `inf`, `81 → 41` at `40`, `87 → 77` at `10`, and both the reindex (`BenchmarkWrapLayout.init`) and the drain stream through the same `greedyEnd`. **Time falls less than iterations**: the scan costs ~1.5 ns per cell, and a per-row fixed cost — cursor construction in `makeInner`, protocol-witness dispatch on the layout, the layout value's retain/release per line — stays. Measured in this plan's smoke test (Apple silicon, one run each side, 2026-08-28): `drain_p95` 0.55 / 0.80 / 0.92 and `reindex_ns` 0.45 / 0.68 / 0.93 at `inf` / `40` / `10`, `compute_*` within noise, checksums identical. So the structural predictions are: the ratios are **ordered** `inf` < `40` < `10` < 1 on both token families, `inf` falls by at least a quarter, and `compute_*` never touches the packer and must not move. `reindex_ns` at `inf` is additionally the first width the mode runs (cold caches, page faults on the fresh 100 000-entry array) — a pre-existing property of the mode; record it, do not reorder the loop.

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice55a-c4-build.txt 2>&1; then echo "RELEASE BUILD RED"; fi
swift run -c release ViewportBenchmarks -- --wrap-compute > /tmp/slice55a-wc-C4.txt 2>&1
grep '^mode=wrap_compute' /tmp/slice55a-wc-C4.txt
echo "--- C4 vs C3 ---"; python3 /tmp/slice55a-compare.py /tmp/slice55a-wc-C3.txt /tmp/slice55a-wc-C4.txt
cat > /tmp/slice55a-predict.py <<'PY'
import sys
def parse(path):
    out = {}
    for line in open(path):
        if not line.startswith("mode=wrap_compute"): continue
        toks = dict(t.split("=", 1) for t in line.split() if "=" in t)
        out[toks["scenario"]] = toks
    return out
b1, b2, before, after = (parse(p) for p in sys.argv[1:5])
def ratio(sc, k): return int(after[sc][k]) / int(before[sc][k])
def spread(sc, k):
    x, y = int(b1[sc][k]), int(b2[sc][k]); return max(x, y) / min(x, y) if min(x, y) else float("inf")
# Predicted bands (spec Decision 12, corrected by the plan's smoke test: 0.45-0.55 / 0.68-0.80 / ~0.93).
bands = {"width_inf": (0.0, 0.75), "width_40": (0.45, 0.95), "width_10": (0.70, 1.02)}
for sc, (lo, hi) in bands.items():
    for k in ("reindex_ns", "drain_p95_ns", "drain_p99_ns"):
        r = ratio(sc, k)
        print("%-10s %-13s ratio=%.3f  predicted [%.2f, %.2f]  %s" % (sc, k, r, lo, hi, "PASS" if lo <= r <= hi else "FINDING"))
# The ordering is the structural half of the prediction: inf falls most, 10 least, all below 1.
for k in ("reindex_ns", "drain_p95_ns", "drain_p99_ns"):
    ri, r40, r10 = ratio("width_inf", k), ratio("width_40", k), ratio("width_10", k)
    print("%-24s order inf<40<10<1: %.3f < %.3f < %.3f  %s" % (k, ri, r40, r10, "PASS" if ri < r40 < r10 < 1.0 else "FINDING"))
    for k in ("compute_p95_ns", "compute_p99_ns"):
        r = ratio(sc, k); s = spread(sc, k); tol = max(s, 1.15)
        print("%-10s %-13s ratio=%.3f  noise floor x%.2f  %s" % (sc, k, r, tol, "PASS (flat)" if 1 / tol <= r <= tol else "FINDING"))
    print("%-10s checksum %s" % (sc, "IDENTICAL" if before[sc]["checksum"] == after[sc]["checksum"] else "DIFFERENT -- FINDING"))
PY
python3 /tmp/slice55a-predict.py /tmp/slice55a-wc-B1.txt /tmp/slice55a-wc-B2.txt /tmp/slice55a-wc-C3.txt /tmp/slice55a-wc-C4.txt
```

Expected: every `reindex_ns`/`drain_*` line `PASS` in its band, three `order … PASS`, every `compute_*` line `PASS (flat)`, three `IDENTICAL`. **A `FINDING` is recorded as such in the verification record with the number** — a flat `width_inf`, a `width_40` that falls less than `width_10`, or a moving `compute_*` is a finding about the edit, not about the harness. Do not widen the bands to make it pass; if a band is wrong, say why with the numbers. (`reindex_ns` at `inf` may sit near the top of its band for the cold-start reason above; that is expected and is recorded, not explained away.)

---

## Task 6: Commit 5 — the drain body is a function, and D-29's pin

Spec Testing Strategy (fold-ins, D-29), Contract 55a commit 5. The drain body is extracted so a counting layout can assert it never calls `compute(_:layout:)` — witnessed by zero `firstVisualRow(ofLine: lineCount)` probes, which every `compute(_:layout:)` makes (the layout ladder reads `totalRows`) and the drain path structurally never does (`binarySearchLogicalLine` probes `0..<lineCount`; the cursor probes `firstVisualRow(ofLine: startLine)` with `startLine < lineCount`).

**Files:**
- Create: `Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift`
- Modify: `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`

**Interfaces:**
- Consumes: `BenchmarkWrapLayout(lineCount:cells:advance:rowHeight:wrapWidth:)` (internal, reachable via `@testable import ViewportBenchmarks`).
- Produces: `func drainVisualRows<Layout: VisualRowLayoutSource>(_ range: VirtualRange, layout: Layout) -> Int` — streams `visualRowGeometry(for: range, layout: layout)` and returns the `&+` fold of every row's `endColumn`.

- [ ] **Step 1: The failing test**

Create `Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift`:

```swift
import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

// D-29: `--wrap-compute`'s drain body performs no `compute(_:layout:)`. Slice 54 recorded
// this as reviewable-but-not-machine-checkable; it is checkable, because the property is
// about the LAYOUT, not the timing helper. Every compute(_:layout:) call probes
// `firstVisualRow(ofLine: lineCount)` (the layout ladder reads totalRows), and the drain
// path never can: the logicalLine search probes 0..<lineCount and the cursor probes the
// start line only. So a counting layout that sees zero such probes across the body has
// seen no compute -- and a witness call proves the probe exists to be counted.
final class WrapComputeDrainTests: XCTestCase {
    private final class ProbeCounter {
        var firstVisualRowCalls = 0
        var firstVisualRowAtLineCount = 0
    }

    private struct CountingLayout: VisualRowLayoutSource {
        let base: BenchmarkWrapLayout
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
            if line == base.lineCount { counter.firstVisualRowAtLineCount += 1 }
            return base.firstVisualRow(ofLine: line)
        }
    }

    func testDrainBodyPerformsNoCompute() {
        // 64 lines x 8 cells at width 4 -> 2 rows per line, 128 rows.
        let base = BenchmarkWrapLayout(lineCount: 64, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        let input = VariableViewportInput(scrollOffsetY: 40.0, viewportHeight: 100.0, overscanLinesBefore: 4, overscanLinesAfter: 4)

        // The range is built OUTSIDE the counted region, exactly as the benchmark builds
        // its drain ranges outside the clock (slice 54 spec, Decision 4).
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: base) else {
            return XCTFail("expected success")
        }

        // Witness: compute(_:layout:) DOES make the probe this test counts, so a zero
        // below is a measurement and not an absence of instrumentation.
        let witness = ProbeCounter()
        _ = ViewportVirtualizer.compute(input, layout: CountingLayout(base: base, counter: witness))
        XCTAssertGreaterThan(witness.firstVisualRowAtLineCount, 0, "compute must probe firstVisualRow(ofLine: lineCount), or the zero below is vacuous")

        let counter = ProbeCounter()
        let sink = drainVisualRows(range, layout: CountingLayout(base: base, counter: counter))
        XCTAssertGreaterThan(sink, 0, "the drain must have streamed rows")
        XCTAssertGreaterThan(counter.firstVisualRowCalls, 0, "the drain locates its start line through the layout")
        XCTAssertEqual(counter.firstVisualRowAtLineCount, 0, "the drain body must not compute a range")
    }
}
```

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapComputeDrainTests > /tmp/slice55a-t6-red.txt 2>&1; then
  echo "UNEXPECTED PASS"
else
  echo "EXPECTED RED"; rg -n "error:" /tmp/slice55a-t6-red.txt | head -2
fi
```

Expected: `EXPECTED RED` with `cannot find 'drainVisualRows' in scope`.

- [ ] **Step 2: Extract the drain body**

In `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`:

Insert before `@available(macOS 13.0, *)\nfunc runWrapComputeBenchmarks() -> Bool {`:
```swift
/// The `--wrap-compute` drain body, one operation: stream the buffer range through
/// `visualRowGeometry` and fold every row's `endColumn`. A function rather than a
/// closure so `WrapComputeDrainTests` can drive it through a counting layout and assert
/// it performs no `compute(_:layout:)` (D-29) -- witnessed by zero
/// `firstVisualRow(ofLine: lineCount)` probes, which every compute makes and the drain
/// path structurally never does. The drain ranges are built outside the clock by the
/// caller (slice 54 spec, Decision 4); computing one in here would make drain_p95_ns
/// measure compute+drain and gate node 6 on the wrong quantity.
func drainVisualRows<Layout: VisualRowLayoutSource>(_ range: VirtualRange, layout: Layout) -> Int {
    var cursor = ViewportVirtualizer.visualRowGeometry(for: range, layout: layout)
    var sink = 0
    while let geometry = cursor.next() { sink &+= geometry.row.endColumn }
    return sink
}

```

Replace:
```swift
        let drainMeasured = amortisedSamples(
            iterations: iterations, operationsPerSample: drainOperationsPerSample
        ) { operation in
            var cursor = ViewportVirtualizer.visualRowGeometry(
                for: drainRanges[operation % drainRangeCount], layout: layout)
            var sink = 0
            while let geometry = cursor.next() { sink &+= geometry.row.endColumn }
            return sink
        }
```
With:
```swift
        let drainMeasured = amortisedSamples(
            iterations: iterations, operationsPerSample: drainOperationsPerSample
        ) { operation in
            drainVisualRows(drainRanges[operation % drainRangeCount], layout: layout)
        }
```

- [ ] **Step 3: Green, then D-29's drill**

```bash
cd /Users/aabanschikov/swift-text-engine
for s in WrapComputeDrainTests WrapBenchmarkLineShapeTests AmortisedSamplesTests; do
  if swift test --filter "$s" > "/tmp/slice55a-t6-$s.txt" 2>&1; then echo "green: $s"; else echo "RED: $s"; rg -n "error:|failed" "/tmp/slice55a-t6-$s.txt" | head -3; fi
done
```

Expected: three `green:`.

**D-29 drill** — inside `drainVisualRows`, insert as the first line of the body:
```swift
    _ = ViewportVirtualizer.compute(VariableViewportInput(scrollOffsetY: 0, viewportHeight: 1, overscanLinesBefore: 0, overscanLinesAfter: 0), layout: layout)
```

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter WrapComputeDrainTests > /tmp/slice55a-drill-d29.txt 2>&1; then
  echo "UNEXPECTED PASS — the drain-purity pin does not bite"
else
  echo "EXPECTED RED (D-29)"; rg -n "XCTAssertEqual failed" /tmp/slice55a-drill-d29.txt | head -1
fi
git checkout -- Sources/ViewportBenchmarks/WrapComputeBenchmark.swift
git diff --quiet -- Sources/ViewportBenchmarks/WrapComputeBenchmark.swift && echo "REVERTED TOO FAR — Step 2's extraction is gone; redo Step 2" || echo "extraction still present"
```

Expected: `EXPECTED RED (D-29)` with `("1") is not equal to ("0")`, then `extraction still present`. (The `git checkout` reverts the **uncommitted** file entirely — Step 2's extraction is uncommitted at this point, so it is lost with the drill. Re-apply Step 2 after the drill; the `git diff --quiet` line tells you which state you are in.)

> Simpler alternative to avoid the redo: commit Step 2 first (Step 4 below), then run the drill, then `git checkout -- Sources/ViewportBenchmarks/WrapComputeBenchmark.swift` reverts only the drill. Either order is fine; the record needs the observed red and a final green.

- [ ] **Step 4: Full suite and commit 5**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test > /tmp/slice55a-t6-full.txt 2>&1; then echo "suite green"; else echo "SUITE RED"; rg -n "error:|failed" /tmp/slice55a-t6-full.txt | head -5; fi
rg -n "Executed [0-9]+ tests" /tmp/slice55a-t6-full.txt | tail -1
BENCH_FOUNDATION="$(rg -n 'import Foundation' Sources/ViewportBenchmarks || true)"
if [ -z "$BENCH_FOUNDATION" ]; then echo "PASS: benchmark target still Foundation-free"; else echo "NOTE:"; echo "$BENCH_FOUNDATION"; fi
git add Sources/ViewportBenchmarks/WrapComputeBenchmark.swift Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift
git commit -m "refactor: extract the --wrap-compute drain body so its purity is testable (D-29)

drainVisualRows(_:layout:) is the drain body slice 54 wrote inline. Slice 54
recorded 'the drain performs no compute' as reviewable but not
machine-checkable; it is: the property is about the layout, not the timing
helper. WrapComputeDrainTests drives the body through a counting layout and
asserts zero firstVisualRow(ofLine: lineCount) probes -- the probe every
compute(_:layout:) makes and the drain path never can -- with a witness
compute proving the probe exists to be counted. Drill recorded: a compute
call placed inside the body reddens it (1 != 0).

Timing shape unchanged: the closure now calls the function it used to
inline. Recorded as column C5, predicted flat, wrap_compute checksum
byte-identical.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Expected: `suite green`, count = Task 5's + 1.

- [ ] **Step 5: `--wrap-compute` column C5 (predicted flat)**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice55a-c5-build.txt 2>&1; then echo "RELEASE BUILD RED"; fi
swift run -c release ViewportBenchmarks -- --wrap-compute > /tmp/slice55a-wc-C5.txt 2>&1
grep '^mode=wrap_compute' /tmp/slice55a-wc-C5.txt
echo "--- C5 vs C4 ---"; python3 /tmp/slice55a-compare.py /tmp/slice55a-wc-C4.txt /tmp/slice55a-wc-C5.txt
```

Expected: three `IDENTICAL`; ratios within the noise floor. This is the column 55b compares against.

---

## Task 7: Commit 6 — D-24's dispatch pin

Spec Testing Strategy (fold-ins, D-24), Contract 55a commit 6 — **after** the guards, never before. The conformer from Task 2 with the **correct** answer; the only thing the tests can see is dispatch.

**Files:**
- Create: `Tests/TextEngineCoreTests/VisualRowDispatchTests.swift`

**Interfaces:**
- Consumes: `OverridingLogicalLineLayout`, `HookLog` (Task 2); `collectGeometry(_:)` (`VisualRowLayoutTestSupport.swift`).

- [ ] **Step 1: The tests**

Create `Tests/TextEngineCoreTests/VisualRowDispatchTests.swift`:

```swift
import XCTest
import TextEngineCore

/// D-24. `logicalLine(containingVisualRow:)` is documented as provider-overridable with a
/// binary-search default -- in the protocol, in AGENTS.md, in visualRowAt's doc comment --
/// and until this file nothing pinned that a consumer dispatches through it: the slice-53
/// review's drill C replaced the dispatch in visualRowAt with a direct
/// binarySearchLogicalLine call and 397 tests stayed green. The conformer here overrides
/// the hook with the CORRECT answer and logs the call, so a test can only see dispatch.
/// Model: PointAtDispatchTests on the column axis.
final class VisualRowDispatchTests: XCTestCase {
    // 4 lines x 2 rows at width 20 (4 cells of 10, breakable everywhere): firstRow
    // [0,2,4,6,8], rowHeight 5, total height 40.
    private func base() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: Array(repeating: (advances: [10.0, 10.0, 10.0, 10.0], breaks: Set([1, 2, 3])), count: 4),
            rowHeight: 5.0, wrapWidth: 20.0)
    }

    private func recording() -> (OverridingLogicalLineLayout, HookLog) {
        let b = base()
        let log = HookLog()
        return (OverridingLogicalLineLayout(base: b, log: log, answer: { b.logicalLine(containingVisualRow: $0) }), log)
    }

    func testVisualRowAtDispatchesThroughTheHookExactlyOnce() {
        let (layout, log) = recording()
        // y = 27 -> global row 5 = line 2, row 1.
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 27.0, layout: layout),
                       .row(VisualRowLocation(globalRow: 5, logicalLine: 2, rowInLine: 1, clamp: .inRange)))
        XCTAssertEqual(log.logicalLineCalls, [5], "one dispatch, with the located global row")
    }

    // Node 3's Decision 7: clamped queries take no special case -- both edges go through
    // the same provider search as an in-range hit, so the dispatch must show there too.
    func testClampedVisualRowAtStillDispatchesThroughTheHook() {
        for (y, expectedRow) in [(-1.0, 0), (1_000.0, 7)] {
            let (layout, log) = recording()
            guard case .row(let located) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
                return XCTFail("expected .row at y=\(y)")
            }
            XCTAssertEqual(located.globalRow, expectedRow, "y=\(y)")
            XCTAssertNotEqual(located.clamp, .inRange, "y=\(y) must clamp")
            XCTAssertEqual(log.logicalLineCalls, [expectedRow], "y=\(y): the clamped edge dispatches once")
        }
    }

    func testDocumentCursorDispatchesThroughTheHookOnceForTheBufferStart() {
        let (layout, log) = recording()
        let input = VariableViewportInput(scrollOffsetY: 25, viewportHeight: 10, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else { return XCTFail("expected success") }
        XCTAssertEqual(log.logicalLineCalls, [], "compute never consults the hook")
        XCTAssertEqual(range.bufferStart, 5, "fixture: buffer starts at row 1 of line 2")

        let rows = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertEqual(rows.first?.row.logicalLine, 2)
        XCTAssertEqual(rows.first?.row.rowInLine, 1)
        XCTAssertEqual(log.logicalLineCalls, [range.bufferStart], "one dispatch for the buffer start; the stream itself never searches")
    }
}
```

- [ ] **Step 2: Green**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter VisualRowDispatchTests > /tmp/slice55a-t7-green.txt 2>&1; then echo "green"; else echo "RED"; rg -n "error:|failed" /tmp/slice55a-t7-green.txt | head -3; fi
```

Expected: `green` (a correct override is dispatched today; the pin's value is the drill).

- [ ] **Step 3: D-24's drill, at both sites**

**Site 1** — `Sources/TextEngineCore/WrapPositionQuery.swift`: replace `layout.logicalLine(containingVisualRow: globalRow)` with `binarySearchLogicalLine(containingVisualRow: globalRow, layout: layout, lineCount: layout.lineCount)`.

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter VisualRowDispatchTests > /tmp/slice55a-drill-d24-query.txt 2>&1; then
  echo "UNEXPECTED PASS — visualRowAt's dispatch is not pinned"
else
  echo "EXPECTED RED (D-24, visualRowAt)"; rg -n "XCTAssertEqual failed" /tmp/slice55a-drill-d24-query.txt | head -1
fi
git checkout -- Sources/TextEngineCore/WrapPositionQuery.swift
```

**Site 2** — `Sources/TextEngineCore/DocumentVisualRowCursor.swift`: replace `layout.logicalLine(containingVisualRow: range.bufferStart)` with `binarySearchLogicalLine(containingVisualRow: range.bufferStart, layout: layout, lineCount: layout.lineCount)`.

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test --filter VisualRowDispatchTests.testDocumentCursorDispatchesThroughTheHookOnceForTheBufferStart > /tmp/slice55a-drill-d24-cursor.txt 2>&1; then
  echo "UNEXPECTED PASS — the cursor's dispatch is not pinned"
else
  echo "EXPECTED RED (D-24, cursor)"; rg -n "XCTAssertEqual failed" /tmp/slice55a-drill-d24-cursor.txt | head -1
fi
git checkout -- Sources/TextEngineCore/DocumentVisualRowCursor.swift
git diff --quiet -- Sources/TextEngineCore && echo "reverted"
```

Expected: two `EXPECTED RED (D-24, …)` — `("[]") is not equal to ("[5]")` — then `reverted`.

- [ ] **Step 4: Full suite and commit 6**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test > /tmp/slice55a-t7-full.txt 2>&1; then echo "suite green"; else echo "SUITE RED"; rg -n "error:|failed" /tmp/slice55a-t7-full.txt | head -5; fi
rg -n "Executed [0-9]+ tests" /tmp/slice55a-t7-full.txt | tail -1
git add Tests/TextEngineCoreTests/VisualRowDispatchTests.swift
git commit -m "test: pin that the row-axis hook is dispatched (D-24)

logicalLine(containingVisualRow:) is documented as provider-overridable with
a binary-search default, and nothing pinned the dispatch: the slice-53
review's drill C bypassed it and 397 tests stayed green. A conformer that
overrides the hook with the correct answer and logs the call now pins one
dispatch per query in visualRowAt (in range and at both clamp edges -- node
3's Decision 7 says clamped queries still search) and one per cursor for the
buffer start. Drill recorded at both sites: bypassing the dispatch reddens
([] != [5]).

Lands after the producer guards, never before: an overriding conformer is
what makes the malformed-override category live, and it must not meet an
unguarded consumer.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Expected: `suite green`, count = Task 6's + 3.

---

## Task 8: Ledger, final checks, the verification record, the PR

Spec Documentation Updates (55a), Verification, AC13/AC16.

**Files:**
- Modify: `docs/superpowers/debt-ledger.md` (D-24, D-29)
- Create: `docs/superpowers/verification/2026-08-28-wrap-point-query-trap-repairs.md`

- [ ] **Step 1: Ledger — D-24 and D-29 discharged**

In `docs/superpowers/debt-ledger.md`, the D-24 row ends with:
```
Fix is one test-only conformer that overrides the hook and asserts it was called — a fold-in, natural home node 4 | open |
```
Replace that tail with:
```
Fix is one test-only conformer that overrides the hook and asserts it was called — a fold-in, natural home node 4 | discharged([slice 55a](verification/2026-08-28-wrap-point-query-trap-repairs.md)): `VisualRowDispatchTests` on `OverridingLogicalLineLayout` (hook overridden with the correct answer, calls logged) pins one dispatch per `visualRowAt` (in range and at both clamp edges) and one per `DocumentVisualRowCursor` for the buffer start; bypassing either site reddens (`[] != [5]`). Landed **after** the five producer guards of the same slice, because the conformer is what makes the malformed-override category live |
```

The D-29 row ends with:
```
the review recommends folding it into node 4, which touches the same benchmark surface | open |
```
Replace that tail with:
```
the review recommends folding it into node 4, which touches the same benchmark surface | discharged([slice 55a](verification/2026-08-28-wrap-point-query-trap-repairs.md)): the drain body is `drainVisualRows(_:layout:)`, and `WrapComputeDrainTests` drives it through a counting `BenchmarkWrapLayout` asserting zero `firstVisualRow(ofLine: lineCount)` probes — the probe every `compute(_:layout:)` makes (a witness call proves it) and the drain path never can; a `compute` placed inside the body reddens it (`1 != 0`) |
```

```bash
cd /Users/aabanschikov/swift-text-engine
N="$(rg -c 'discharged\(\[slice 55a\]' docs/superpowers/debt-ledger.md || echo 0)"
if [ "$N" = "2" ]; then echo "PASS: two rows discharged"; else echo "FAIL: found $N"; fi
```

Expected: `PASS`.

- [ ] **Step 2: Final full checks — suite, build, twelve gates, checksums, memory-shape, Foundation, self-test**

```bash
cd /Users/aabanschikov/swift-text-engine
if swift test > /tmp/slice55a-final-suite.txt 2>&1; then echo "suite green"; else echo "SUITE RED"; fi
rg -n "Executed [0-9]+ tests" /tmp/slice55a-final-suite.txt | tail -1
if swift build -c release > /tmp/slice55a-final-build.txt 2>&1; then echo "release build green"; else echo "RELEASE BUILD RED"; fi
FOUNDATION="$(rg -n 'Foundation' Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "PASS: Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION"; fi
: > /tmp/slice55a-gates-final.txt
if ! swift run -c release ViewportBenchmarks -- --gate >> /tmp/slice55a-gates-final.txt 2>&1; then echo "GATE RED: default pipeline"; fi
for flag in --variable-height --variable-height-mutation --structural-mutation --bulk-structural-mutation --line-query --line-geometry-query --column-query --column-geometry-query --point-query --point-geometry-query --realistic-provider; do
  if ! swift run -c release ViewportBenchmarks -- "$flag" --gate >> /tmp/slice55a-gates-final.txt 2>&1; then echo "GATE RED: $flag"; fi
done
echo "gate=pass lines: $(grep -c 'gate=pass' /tmp/slice55a-gates-final.txt) (expect 46)"
sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9]+).*/\1|\2\t\3/p' /tmp/slice55a-gates-final.txt | sort -u > /tmp/slice55a-checksums-final.tsv
if diff -q /tmp/slice55a-checksums-baseline.tsv /tmp/slice55a-checksums-final.tsv > /dev/null; then
  echo "PASS: 46 gated checksums byte-identical to the pre-branch baseline (AC13)"
else
  echo "FAIL: gated checksums moved"; diff /tmp/slice55a-checksums-baseline.tsv /tmp/slice55a-checksums-final.tsv
fi
if swift run -c release ViewportBenchmarks -- --memory-shape > /tmp/slice55a-memshape-final.txt 2>&1 && grep -q 'invariant=pass' /tmp/slice55a-memshape-final.txt && ! grep -q 'invariant=fail' /tmp/slice55a-memshape-final.txt; then echo "memory-shape: invariant=pass"; else echo "MEMORY-SHAPE RED"; fi
swift run -c release ViewportBenchmarks -- --wrap-row-query > /tmp/slice55a-wrq-final.txt 2>&1
BEFORE="$(sed -nE 's/.*scenario=([^ ]+).*checksum=([0-9]+).*/\1 \2/p' /tmp/slice55a-wrq-baseline.txt)"
AFTER="$(sed -nE 's/.*scenario=([^ ]+).*checksum=([0-9]+).*/\1 \2/p' /tmp/slice55a-wrq-final.txt)"
if [ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ]; then echo "PASS: wrap_row_query checksums byte-identical"; else echo "FAIL: wrap_row_query checksums moved"; fi
if ./.github/scripts/cross-target-compile.sh --self-test > /tmp/slice55a-xt-selftest.txt 2>&1; then echo "cross-target self-test pass"; else echo "CROSS-TARGET SELF-TEST RED"; tail -5 /tmp/slice55a-xt-selftest.txt; fi
```

Expected: `suite green` (count = baseline + 17: 2 + 5 + 4 + 2 + 1 + 3), `release build green`, `PASS: Foundation-free`, `46`, `PASS … (AC13)`, `invariant=pass`, `PASS: wrap_row_query …`, `cross-target self-test pass`. The self-test compiles nothing and is not portability evidence — the two hosted jobs are (Step 5).

- [ ] **Step 3: The verification record**

Create `docs/superpowers/verification/2026-08-28-wrap-point-query-trap-repairs.md` with these sections, each filled from the named scratch files (paste the actual lines; do not summarise a number the file contains):

```markdown
# Slice 55a — wrap trap repairs (node 4, piece 1) — verification record

<one paragraph: what shipped — the seven commits by sha and subject, in order; no new
public API; five guards; two extractions; the short-circuit; D-24 and D-29 discharged;
nine drill reds.>

## 1. Acceptance criteria owned by this piece

| AC | Disposition | Evidence |
|---|---|---|
| 5 (the two `visualRowAt` cases, pinned directly) | | §3 |
| 8 (the shared walk, five guards, five reds) | | §3, §5 |
| 9 (D-24) | | §5 |
| 10 (D-29) | | §5 |
| 13 (Foundation scan, suite, release build, gated checksums) | | §6 |
| 14 (recorded reds: nine in 55a) | | §5 |
| 16 (hosted evidence, both runs) | | §7 |
| 17 (Decision 12, taken) | | §4, §5 |
| 18 (Decision 13, taken) | | §2, §4 |

## 2. The five suites, unedited across commits 3 and 4
<the `git diff --quiet HEAD -- Tests/…` outputs from Task 4 Step 3 and Task 5 Step 4>

## 3. The guards — red before, green after
<Task 2 Step 3 and Task 3 Step 2 outputs: the four trap lines and the two `.row(…)` lines>

## 4. `--wrap-compute`, one column per commit
| token | B1 | B2 | C1 (commit 1) | C3 (commit 3) | C4 (commit 4) | C5 (commit 5) |
<one row per (scenario, token) for compute_p95/p99, drain_p95/p99, reindex_ns, checksum —
from /tmp/slice55a-wc-*.txt; then the /tmp/slice55a-predict.py output verbatim and the
noise floor from B1/B2. Every FINDING line, if any, reproduced with a sentence saying what
was found, not why it is fine.>

## 5. Drills — nine observed reds
<(d1), (f1), (f2), (f3), (f4), (l), (m), D-24 (two sites), D-29: the observed line each>
<plus the red-first evidence for commit 4: WrapPackingCountTests 7/12/3 on the shipped packer>

## 6. Gates, checksums, memory shape, Foundation, `--wrap-row-query`
<Task 8 Step 2 output; the 46-line checksum baseline diff is empty>

## 7. Hosted proof (step level)
<filled after Step 5: PR-head run id, three job conclusions, twelve gate steps with their
46 gate=pass, the swift test count, the iOS job's two compiles, the WASM job's four
result=pass … blocking=true lines; then the same for the post-merge push run>

## 8. Standing notes for 55b and the review
- 55b compares its `--wrap-compute` run against column **C5**.
- D-17 escalates at this piece's review; D-27 goes into its Candidate options (spec, Scope).
- The overriding conformer (`OverridingLogicalLineLayout`) is 55b's second count fixture.
```

- [ ] **Step 4: Commit the docs**

```bash
cd /Users/aabanschikov/swift-text-engine
git add docs/superpowers/debt-ledger.md docs/superpowers/verification/2026-08-28-wrap-point-query-trap-repairs.md
git commit -m "docs: slice 55a verification record; D-24 and D-29 discharged

Records the seven commits in order, the five guards' reds (four traps, two
fabricated locations), the nine drills, the per-commit --wrap-compute
columns against Decision 12's per-width prediction, the 46 gated checksums
byte-identical to the pre-branch baseline, and the unedited five suites
across the two extractions. Hosted proof to follow at step level.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Open the PR and discharge the hosted proof (AC16)**

```bash
cd /Users/aabanschikov/swift-text-engine
git push -u origin slice-55a-wrap-trap-repairs
gh pr create --title "Slice 55a: wrap trap repairs (node 4, piece 1)" --body "$(cat <<'PRBODY'
The first of node 4's two pieces: the shipped wrap layer repaired and made cheaper, with **no new public API**.

**Five guards** so a malformed `logicalLine(containingVisualRow:)` override never traps — two in `visualRowAt` (`.failure(.invalidVisualRowLayout)`), two in `DocumentVisualRowCursor.init` (streams nothing; streaming has no failure channel), one in the new shared walk helper. The default hook cannot reach any of them; every one has a recorded red (four traps, two fabricated locations).

**Two extractions**, shared with node 4's query: `advanceVisualRows(_:by:)` (the within-line walk, defined as the k-th `next()` result) and `validateWrapLine` (the per-line ladder, handing back `(count, total)`). Behaviour-preserving; the five neutral suites pass unedited.

**The packer short-circuits when the remaining suffix fits** — every line that fits the width and the last row of every line now pack in O(1). Red-first against `WrapPackingCountTests`; drill (l) inverts the predicate and `WrapPackingTests` reddens (the ∞ oracles stay green — they hold only fitting lines, on which both predicates agree), drill (m) narrows it to the first row and only the last-row pin reddens. `--wrap-compute` recorded one column per commit; `reindex_ns` and `drain_*` fall at every width in the predicted order (most at ∞ — time falls less than scan iterations, a per-row fixed cost remains), `compute_*` flat, checksum byte-identical across all columns.

**D-24** (the row-axis dispatch is now pinned; bypassing either site reddens) and **D-29** (the drain body performs no compute, machine-checked) discharged. 46 gated checksums byte-identical to the pre-branch baseline. See `docs/superpowers/verification/2026-08-28-wrap-point-query-trap-repairs.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
PRBODY
)"
```

Then read the PR-head run at **step level** (a green job can hide a dead step):

```bash
cd /Users/aabanschikov/swift-text-engine
RUN="$(gh run list -R maldrakar/swift-text-engine --workflow swift-ci.yml --branch slice-55a-wrap-trap-repairs --limit 1 --json databaseId --jq '.[].databaseId')"
echo "run=$RUN"
gh run view "$RUN" -R maldrakar/swift-text-engine --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'
gh run view "$RUN" -R maldrakar/swift-text-engine --log > /tmp/slice55a-hosted-prhead.log 2>&1
echo "gate=pass lines: $(grep -c 'gate=pass' /tmp/slice55a-hosted-prhead.log) (expect 46)"
echo "gate=fail lines: $(grep -c 'gate=fail' /tmp/slice55a-hosted-prhead.log) (expect 0)"
rg -n "Executed [0-9]+ tests" /tmp/slice55a-hosted-prhead.log | tail -1
echo "WASM blocking lines: $(grep -c 'result=pass.*blocking=true' /tmp/slice55a-hosted-prhead.log) (expect 4)"
# D-18: a hosted log also carries memory_shape (5) and memory_observation (3) checksum
# lines, so the filter is what makes the count 46 and the diff meaningful.
grep -v -e 'mode=memory_shape' -e 'mode=memory_observation' /tmp/slice55a-hosted-prhead.log \
  | sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9]+).*/\1|\2\t\3/p' | sort -u > /tmp/slice55a-checksums-hosted.tsv
echo "hosted checksum tuples: $(wc -l < /tmp/slice55a-checksums-hosted.tsv | tr -d ' ') (expect 46)"
```

Expected: three jobs `success`; 46 / 0 / the suite count / 4 / 46. Hosted checksums are compared against the **hosted** baseline of the previous merged run (they differ from local by design — different hardware only changes timings, not checksums, so the tuples should match the last main run's; if no hosted baseline is at hand, record the 46 tuples for 55b to diff against). Paste all of it into §7 of the record and commit as `docs: slice 55a hosted proof (PR-head run <id>)`.

After merge, repeat for the post-merge **push** run on `main` (`--branch main`), append to §7, and open the docs-only follow-up PR as every slice does. The post-slice review that follows is a live `choosing-next-slice` Mode-2 run: it selects 55b, **escalates D-17** and puts **D-27** in its Candidate options (spec, Scope).

---

## Plan Self-Review

**1. Spec coverage (Contract 55a).**

| Contract 55a item | Task |
|---|---|
| Commit 0 — `checksum=` witness (Decision 13) | 1 |
| Commit 1 — `advanceVisualRows`, guards 3–4–5 (Decision 4) | 2 |
| Commit 2 — `visualRowAt` guards 1–2, the three narrowed sites (Decision 4, Documentation Updates) | 3 |
| Commit 3 — `validateWrapLine`, stored `total` (Decision 13) | 4 |
| Commit 4 — `greedyEnd` short-circuit, `WrapPackingCountTests`, cost wording + two doc comments (Decision 12) | 5 |
| Commit 5 — drain extraction (D-29) | 6 |
| Commit 6 — `VisualRowDispatchTests` after the guards (D-24) | 7 |
| Internal signatures block | 2 (`advanceVisualRows`), 4 (`WrapLineMetrics`, `validateWrapLine`, the init), 5 (the branch), 1 (`formatWrapComputeLine`) |
| The five guards table | 2 (3, 4, 5), 3 (1, 2) |
| Tests that pass unedited across commits 3 and 4 | 4 Step 3, 5 Step 4 (`git diff --quiet`) |
| Drills — nine reds: (d1), (f1)–(f4), (l), (m), D-24, D-29 | 3 (d1, f4), 2 (f1, f2, f3), 5 (l, m), 7 (D-24), 6 (D-29) |
| Expected numbers — `--wrap-compute` two baselines + four columns; `--wrap-row-query` checksum; twelve gates; suite; Foundation; memory-shape | 1 (B1, B2, baselines), 2 (C1), 4 (C3), 5 (C4 + prediction), 6 (C5), 3 + 8 (`--wrap-row-query`), 8 (gates, AC13, memory-shape) |
| Documentation — node 1, node 2, `visualRowAt` paragraphs; three narrowed sites; two doc comments; D-24, D-29 → discharged | 3 (narrowing + `visualRowAt` behaviour), 5 (cost wording, doc comments), 8 (ledger) |
| Record + hosted proof, D-17 escalation and D-27 candidate at the review | 8 |
| AC5 (55a half), AC8, AC9, AC10, AC13, AC14 (nine of nineteen), AC16, AC17, AC18 | see the record's AC table (Task 8 Step 3) |

Deliberately **not** in this plan (55b's): the `RiggedVisualRowLayout` comment at `VisualRowLayoutTestSupport.swift:49-53`, the `AGENTS.md` node 4 paragraph and flag lists, D-25, D-18's ledger flip (the `grep -v` filter is already used in Task 8 Step 5 so the hosted count reads 46).

**2. Placeholder scan.** No "TBD"/"TODO"/"similar to Task N". Every code step carries the code; every assertion carries its expected output and an `if`/`else` printing both branches; no `${PIPESTATUS[0]}`; every command block assigns the variables it reads (`FOUNDATION`, `HITS`, `BEFORE`, `AFTER`, `N`, `RUN`, `BENCH_FOUNDATION`). The plan asserts no HEAD commit of its own. The verification record's skeleton (Task 8 Step 3) names, for each section, the scratch file whose content fills it — the record is evidence pasted, not prose written.

**3. Type consistency.** `advanceVisualRows(_:by:) -> VisualRow?` is defined in Task 2 and called with `&cursor` / `&c` in Tasks 2 and 3 (the cursor) and by name in the helper suite. `OverridingLogicalLineLayout(base:log:answer:)` is declared in Task 2 with that memberwise order and constructed the same way in Tasks 2, 3 and 7. `VisualRowCursor.init(line:columnCount:total:wrapWidth:metrics:)` is declared in Task 4 and used only by `visualRows` in the same file; `total` is read by `greedyEnd` in Task 5. `WrapLineMetrics.valid(count:total:)` labels match between the enum and the `switch` in `visualRows`. `formatWrapComputeLine(... reindexNanoseconds:checksum:)` is asserted in Task 1's test and defined in Task 1's source with that trailing label. `drainVisualRows(_:layout:) -> Int` is defined and called with those labels in Task 6. `HookLog.logicalLineCalls: [Int]` is asserted as `[5]`, `[expectedRow]`, `[range.bufferStart]`, `[]` in Task 7.

**Four risks flagged for the implementer:**

1. **Trap reds abort the test process.** Tasks 2 and 3 run each trap-shaped case alone with `--filter`; a combined run stops at the first trap and the second case's red is never observed. The observed line is the red — record it as `Fatal error: …`, not as an XCTest failure.
2. **Task 6's drill and `git checkout` interact.** The drain extraction is uncommitted while the D-29 drill runs; `git checkout -- <file>` reverts both. The step says so and offers the commit-first order; whichever is taken, the record needs the observed red *and* a final green with the extraction present (`rg -n "func drainVisualRows" Sources/ViewportBenchmarks/WrapComputeBenchmark.swift` must hit).
3. **Task 5 Step 8's prediction bands are evidence-based, from one smoke-test run per side** (`[0, 0.75]`, `[0.45, 0.95]`, `[0.70, 1.02]`, the `inf < 40 < 10 < 1` ordering, `compute_*` within `max(B1/B2 spread, 1.15)`). The smoke test measured drain p95 0.55 / 0.80 / 0.92 and reindex 0.45 / 0.68 / 0.93, so a healthy tree sits mid-band. A `FINDING` is recorded with its number; it is not a reason to loosen the band. The spec's original wording ("by the cells-per-line factor") was the *iteration* count, not time, and was corrected from this measurement — do not reintroduce it.
4. **Commit 6 must stay after commits 1–2.** The order is the task order, but a subagent that "batches test files" could move `VisualRowDispatchTests` earlier. The rule is stated in Global Constraints and in the commit message; an executor that finds itself writing the dispatch pin before Task 3's guards are green has left the plan.
