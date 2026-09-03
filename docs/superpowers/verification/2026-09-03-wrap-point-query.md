# Slice 55b — wrap-aware point query (node 4, piece 2) — verification record

Branch `slice-55b-wrap-point-query` → `main`. Spec:
[`docs/superpowers/specs/2026-08-24-wrap-point-query-design.md`](../specs/2026-08-24-wrap-point-query-design.md)
(Contract 55b). Plan:
[`docs/superpowers/plans/2026-09-03-wrap-point-query.md`](../plans/2026-09-03-wrap-point-query.md).
PR: opened by this record's own commit (Task 11 Step 5) — see the post-merge follow-up
appended to §7 once the number and hosted proof are known; Step 6/7 (both hosted proofs)
are explicitly out of this task's scope and land as separate commits.

Seventeen commits (`main..HEAD`) once this record's own fix-wave commit lands. Sixteen are
listed below by SHA; the seventeenth **is** the fix-wave commit carrying this sentence, so it
cannot name its own hash — committing it would change it. The count was re-checked after that
commit landed (`git log main..HEAD --oneline | wc -l` → 17).

1. `38028db` docs: record the slice-55b selection and the three routed P2 calls
2. `7852e92` docs: slice 55b implementation plan (node 4, visualPointAt)
3. `c857992` docs: fold the plan-validation findings into the slice 55b plan
4. `31b31a9` feat: add visualPointAt, the wrap-aware (x,y) -> (row, cell) query
5. `143b572` test: pin visualPointAt's verbatim row, span property and field agreement
6. `ce162b8` test: pin Decision 6's FP clamp and Decision 14's >= total guard
7. `d1d6656` test: pin visualPointAt's ladder and the three malformed-provider cases
8. `0d178fb` test: pin visualPointAt's probe table; tighten D-25's redundant bound
9. `6bc3b4d` test: infinite-width oracle for visualPointAt (criterion 3)
10. `99984f5` test: round-trip visualPointAt against the streamed visual rows
11. `8ad909f` feat: add the observational --wrap-point-query benchmark mode
12. `de10e37` fix: correct the layout justification and pin the blank-line sentinel
13. `eb04ba4` test: pin the wrap-compute checksum's completeness (D-33)
14. `aa10b76` docs: node 4 in AGENTS.md; discharge D-18, D-25 and D-33; amend the spec
15. `e563794` docs: retract the spec's ~10^9/appear-to-hang claim (fix round 1)
16. `6913fe7` docs: slice 55b plan and verification record
17. *(this commit)* the post-review fix wave — six findings, two new recorded reds (§9 item 7)

## 1. Acceptance criteria owned by this piece

| AC | Disposition | Evidence |
|---|---|---|
| 1 (`visualPointAt` exists, `row` pinned verbatim to `visualRowAt`) | **Met** — `Sources/TextEngineCore/WrapPointQuery.swift`; `testRowIsCarriedVerbatimFromVisualRowAt` sweeps `y` across both clamp edges; drill (g) reddens it | §2, §3 |
| 2 (`x` row-relative, clamps land on the row's edges, overflow-row mid-range stays `.inRange`) | **Met** — steps 5–6 of the ladder; `testXBetweenWrapWidthAndRowWidthOnAnOverflowRowStaysInRange` (Task 1) | §2 |
| 3 (index line-absolute, always inside `[startColumn, endColumn)`, swept property) | **Met** — `testTheIndexIsAlwaysInsideItsRowSpan` / `...OnTheFPFixture`; drills (e) and (k) each reddens the fixture they gate | §2, §3 |
| 4 (infinite-width oracle on the located branch, narrow-width control non-vacuous) | **Met** — `WrapPointQueryEquivalenceTests`; the narrow-width control was independently confirmed non-vacuous (Task 6, a genuine `rowSpan` shape mismatch); drill (a) reddens the oracle | §2, §3 |
| 5, 55b half (validation ladder rung for rung, `±∞` named separately, both precedence pairs, three malformed-provider cases) | **Met** — `WrapPointQueryValidationTests`, 16 cases; drills (d1)/(d2)/(d3) each trap when their guard is removed | §2, §3 |
| 6 (Decision 6 discharged on both fixtures) | **Met** — fixture 1 (the FP clamp, `.inRange` intact) and fixture 2 (the `>= total` guard, zero hook calls) both in `WrapPointQueryTests`; drills (e)/(k) are the asymmetric pair | §2, §3 |
| 7 (probe-count table) | **Met** — `WrapPointQueryCountTests`, 8 cases: `<= ceilLog2(lineCount) + 4` with no `totalRows` term, zero column-metric calls off the located path, exact `3 + 2` / `3 + 2 + 1` counts, the `rowInLine` growth lower bound; drills (h)/(i) reddens the placement and the bound respectively | §2, §3 |
| 8, round-trip half (streamed row equals queried row on both line kinds) | **Met** — `WrapPointQueryRoundTripTests.testEveryStreamedRowIsFoundByItsOwnPoint`, fixture guard corrected to `fitting = 3, wrapped = 2` (§8) | §2, §8 |
| 9, 55b half (D-24: dispatch proven for `visualPointAt`, with a recorded red) | **Deviation — discharged by assertion, not by drill.** `WrapPointQueryCountTests`' fixture 2 asserts `logicalLineDispatches == 1` on both the clamped and the delegating path, but Contract 55b's drill list carries no dispatch-bypass drill and D-24's ledger row is already `discharged(slice 55a)` on 55a's own red. See §9 | §9 |
| 11 (D-25 discharged) | **Met** — retargeted (not merely tightened) to row 1 022, `testTheInRangeWorstCaseTargetHasNoSlackAgainstTheBound`, `totalCalls` read back as 14 with zero slack. See §9 for why a tightened-in-place bound would not have discharged it | §2, §9 |
| 12 (`--wrap-point-query`: six scenarios, tokens, checksum, floors, `--gate`/second-flag rejected, two test files) | **Met, with a recorded floor deviation** — six scenario lines, `fast_path=` printed, `row_in_line=` only on `long_line_deep_row`, prefixed `query_p95_ns=`/`query_p99_ns=`, checksum folding every non-duplicated field; `WrapPointQueryOptionsTests` + `WrapPointQueryChecksumTests` + 3 `WrapBenchmarkLineShapeTests` cases; drills (b)/(c)/(j). Floors raised to `cells >= 2_000` / `rowsPerLine >= 400` (§9) | §6, §9 |
| 13 (Foundation scan empty, suite green, release build clean, gated checksums byte-identical) | **Met** — `foundation_scan=empty`; `Executed 479 tests, with 0 failures` at Task 11 and `Executed 480 tests, with 0 failures` after the fix wave; `Build complete!`, 46/46 checksum tuples, `checksum_diff=empty` (the wave changes no gated output — its only `Sources/` edit is a doc comment) | §4, §5 |
| 14 (every standing guarantee carries a recorded red) | **NOT met as shipped at Task 11; met after the post-review fix wave.** Fourteen drills plus the bonus fifteenth were recorded — but the final whole-branch review found **two shipped guards that survived deletion with the whole suite green**: Decision 14's `>= total` *answer* (the fixture's located row held one cell, where the right answer and a plausible wrong one are the same index) and step 7's `!rebased.isFinite` guard (no test at all). Both now carry a recorded red — drills **(p)** and **(q)**. One guarantee remains **deliberately** without one: Decision 6's lower clamp half, unreachable by any conforming provider (§9 item 7). This row is not rewritten into having always been met | §3, §9 |
| 15 (D-18 discharged unconditionally) | **Met** — the checksum-extraction step (§5) uses the `grep -v -e 'mode=memory_shape' -e 'mode=memory_observation'` filter; no `${PIPESTATUS[0]}` anywhere in this record's commands | §5 |
| 16 (hosted evidence, both runs, step level) | **Pending — out of this task's scope.** Step 6 (PR-head) and Step 7 (post-merge) are performed by the controller after this record's commit and PR are created; §7 is a placeholder | §7 |
| 19 (D-33 discharged, Decision 15) | **Met** — `wrapComputeChecksum(compute:drain:)` extracted as a pure function pinned to read both operands (drill (n)); `drainVisualRows` pinned to fold every row's `endColumn` (drill (o)); printed `checksum=` byte-identical to 55a's final column on all three widths | §6, §8 |

## 2. Test files added this piece

- `Tests/TextEngineCoreTests/WrapPointQueryTests.swift` — the seven-step ladder, the verbatim-row pin, the swept span property, Decision 6's two fixtures (Tasks 1–3).
- `Tests/TextEngineCoreTests/WrapPointQueryValidationTests.swift` — the full validation ladder, 16 cases (Task 4).
- `Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift` — the probe-count table, 8 cases (Task 5).
- `Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift` — modified: D-25's retarget (Task 5).
- `Tests/TextEngineCoreTests/WrapPointQueryEquivalenceTests.swift` — the infinite-width oracle (Task 6).
- `Tests/TextEngineCoreTests/WrapPointQueryRoundTripTests.swift` — the streamed-row round trip (Task 7).
- `Tests/TextEngineCoreTests/VisualRowLayoutTestSupport.swift` — modified: `ColumnHookLog`/`OverridingColumnIndexLayout`, corrected `RiggedVisualRowLayout` comment (Tasks 3, 10).
- `Tests/ViewportBenchmarksTests/WrapPointQueryOptionsTests.swift` — option parsing, 5 cases (Task 8).
- `Tests/ViewportBenchmarksTests/WrapPointQueryChecksumTests.swift` — checksum completeness, 3 cases + the golden-value bonus pin (Task 8 + fix round).
- `Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift` — modified: three new cases for `wrap_point_query`'s line shape (Task 8).
- `Tests/ViewportBenchmarksTests/WrapComputeChecksumTests.swift` — D-33's completeness pin, 2 cases (Task 9).

Source files added/modified: `Sources/TextEngineCore/ViewportTypes.swift` (`VisualPointQuery`,
`VisualPointLocation`), `Sources/TextEngineCore/WrapPointQuery.swift` (new),
`Sources/ViewportBenchmarks/BenchmarkOptions.swift`, `Sources/ViewportBenchmarks/BenchmarkProgram.swift`,
`Sources/ViewportBenchmarks/SyntheticBenchmarks.swift` (the fifth exhaustive switch — §9),
`Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift` (new),
`Sources/ViewportBenchmarks/WrapComputeBenchmark.swift` (`wrapComputeChecksum` extraction).

## 3. The fourteen drills, plus one bonus and two fix-wave additions

Every named guarantee's recorded red, with the exact observed failure line(s) and, for the
asymmetric ones, both halves.

**(a) — infinite-width oracle, `Sources/TextEngineCore/WrapPointQuery.swift`
`let rebased = rowLeft + x` → `rowLeft + x * 2.0`.**

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryEquivalenceTests.swift:81: error: -[TextEngineCoreTests.WrapPointQueryEquivalenceTests testWidthNoLineExceedsEqualsUniformPointAt] : XCTAssertNil failed: "(x: 4.0, y: -100.0): VisualPointLocation(row: ..., rowSpan: TextEngineCore.VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 3, width: 21.0), column: ...cell(...columnIndex: 1...)) vs PointLocation(..., column: ...cell(...columnIndex: 0...))" - width=inf
```
`testANarrowWidthBreaksTheEquivalence` (the control) stayed green. `Executed 2 tests, with 2 failures`.

**(b) — checksum completeness, `Sources/ViewportBenchmarks/WrapPointQueryBenchmark.swift`
`... location.rowSpan.width.bitPattern) &* 17` → `&* 0`.**

```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapPointQueryChecksumTests.swift:34: error: -[ViewportBenchmarksTests.WrapPointQueryChecksumTests testEveryFieldAffectsTheChecksum] : XCTAssertNotEqual failed: ("125454945") is equal to ("125454945") - rowSpan.width
```
`Executed 3 tests, with 1 failure`.

**(c) — prefixed latency keys, `formatWrapPointQueryLine`'s `query_p95_ns=`/`query_p99_ns=` →
bare `p95_ns=`/`p99_ns=`.**

```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift:98: error: -[ViewportBenchmarksTests.WrapBenchmarkLineShapeTests testWrapPointQueryLineCarriesItsTokensAndNoBareLatencyKeys] : XCTAssertEqual failed: ("nil") is not equal to ("Optional("1234")")
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift:99: error: ... XCTAssertEqual failed: ("nil") is not equal to ("Optional("2345")")
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift:103: error: ... XCTAssertFalse failed - bare p95_ns would make this line harvestable
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift:104: error: ... XCTAssertFalse failed - bare p99_ns would make this line harvestable
```
`Executed 5 tests, with 4 failures`. **Asymmetry**: the two sibling wrap-mode line pins
(`wrap_row_query`, `wrap_compute`) stayed green — each pin sees only its own formatter.

**(d1) — `visualRowAt`'s guard 1 (the `logicalLine` range check) removed.**

```
Test Case '-[TextEngineCoreTests.WrapPointQueryValidationTests testAnOutOfRangeLogicalLineOverrideFails]' started.
Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range
```
Trap (exit code 1, signal 5), not an assertion failure — the guard removal is inherited
purely through `visualRowAt`, with no query-side edit at all. This is the deliberately
asymmetric case: **no `WrapPointQuery.swift` edit produced this red; removing `visualRowAt`'s
own guard is what did.**

**(d2) — both the producer's `rowInLine < 0` check and the helper's `k <= 0` rule removed
(both required).**

```
Test Case '-[TextEngineCoreTests.WrapPointQueryValidationTests testAnInRangeOverrideThatMakesRowInLineNegativeFails]' started.
Swift/arm64e-apple-macos.swiftinterface:19659: Fatal error: Range requires lowerBound <= upperBound
```
**Both halves recorded**: with only the producer guard removed (helper's `k <= 0` rule
intact), the suite stayed **green** (`Executed 16 tests, with 0 failures`) — the helper
backstops it. With both guards removed, the trap above reproduces. Only the fully-removed
pair traps.

**(d3) — the walk's exhaustion check
(`guard let rowSpan = advanceVisualRows(...) else { .failure(...) }`) force-unwrapped instead.**

```
Test Case '-[TextEngineCoreTests.WrapPointQueryValidationTests testAWalkThatExhaustsEarlyFails]' started.
TextEngineCore/WrapPointQuery.swift:73: Fatal error: Unexpectedly found nil while unwrapping an Optional value
```
Trap. This is the one failure `visualPointAt` adds of its own.

**(e) — Decision 6 fixture 1, the clamp
(`min(max(raw, rowSpan.startColumn), rowSpan.endColumn - 1)`) replaced with `raw` unclamped.**

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryTests.swift:232: error: -[TextEngineCoreTests.WrapPointQueryTests testFixtureOneRoundsPastTheRowAndTheClampConfinesTheIndex] : XCTAssertEqual failed: ("cell(TextEngineCore.ColumnLocation(columnIndex: 2, clamp: TextEngineCore.ColumnLocation.Clamp.inRange))") is not equal to ("cell(TextEngineCore.ColumnLocation(columnIndex: 1, clamp: TextEngineCore.ColumnLocation.Clamp.inRange))")
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryTests.swift:252: error: -[TextEngineCoreTests.WrapPointQueryTests testTheIndexIsAlwaysInsideItsRowSpanOnTheFPFixture] : XCTAssertLessThan failed: ("2") is not less than ("2") - (x: 3.9, y: 15.0) left the span
```
3 of 13 failures. **Asymmetry**: `testFixtureTwoAnswersFromTheTotalGuardWithoutCallingTheHook`
(fixture 2) and the ordinary non-FP sweep both stayed **green** — the clamp never fires on
those magnitudes.

**(g) — the verbatim-row pin, `case .row(let located): row = located` reconstructed with
`clamp: .inRange` hard-coded instead of copied.**

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryTests.swift:90: error: -[TextEngineCoreTests.WrapPointQueryTests testClampedYCrossedWithEachXBranch] : XCTAssertEqual failed: ("VisualRowLocation(globalRow: 0, logicalLine: 0, rowInLine: 0, clamp: TextEngineCore.LineLocation.Clamp.inRange)") is not equal to ("VisualRowLocation(globalRow: 0, logicalLine: 0, rowInLine: 0, clamp: TextEngineCore.LineLocation.Clamp.clampedToTop)")
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryTests.swift:135: error: -[TextEngineCoreTests.WrapPointQueryTests testRowIsCarriedVerbatimFromVisualRowAt] : XCTAssertEqual failed: (".inRange") is not equal to (".clampedToTop") - y=-100.0
```
7 of 10 failures, only at the swept sweep's clamp edges; the other 8 non-clamp tests stayed
green.

**(h) — the `x`-finiteness check's PLACEMENT: moved from before the per-line ladder to just
before the blank-line check (result unaffected, cost changed).**

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift:184: error: -[TextEngineCoreTests.WrapPointQueryCountTests testNonFiniteXTouchesNoColumnMetrics] : XCTAssertEqual failed: ("5") is not equal to ("0") - x=inf: the x rung must run BEFORE any horizontal work
```
3 of 8 failures. **Asymmetry**: `swift test --filter WrapPointQueryValidationTests` stayed
**entirely green** (`Executed 16 tests, with 0 failures`) — both `±∞` result tests pass
unchanged because the *result* is unaffected by placement, only the cost is.

**(i) — the growth bound vs. "strictly more": a throwaway one-probe-per-row `greedyEnd`
shortcut inserted (correct only on a uniform fixture).**

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift:255: error: -[TextEngineCoreTests.WrapPointQueryCountTests testColumnCostGrowsWithTheRowInLine] : XCTAssertGreaterThanOrEqual failed: ("24") is less than ("40")
```
1 of 8 failures. **Both numbers recorded**: observed difference under the drill = 24; the
bound = 40 (`endColumn(10) − endColumn(2) = 55 − 15`); 24 > 0 means a bare
`XCTAssertGreaterThan(diff, 0)` would have **passed** under this drill — only the 40-cell
lower bound catches it.

**(j) — the scenario-parameter pin: `long_line_deep_row`'s `cells: 2_000` → `cells: 1_000`.**

```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift:127: error: -[ViewportBenchmarksTests.WrapBenchmarkLineShapeTests testWrapPointQueryScenarioParametersAreAtTheirFloors] : XCTAssertGreaterThanOrEqual failed: ("1000") is less than ("2000") - shortening the line deletes the term this scenario exposes
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift:129: error: ... XCTAssertGreaterThanOrEqual failed: ("200") is less than ("400") - the walk must be hundreds of rows deep
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift:130: error: ... XCTAssertEqual failed: ("Optional(399)") is not equal to ("Optional(199)") - the scenario must query the LAST row of its line
```
3 of 5 failures — exactly the three predicted (cells floor, derived-rows floor, `rowInLine`).

**(k) — Decision 14's `>= total` guard, `if rebased >= total` replaced with `if false`.**

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryTests.swift:246: error: -[TextEngineCoreTests.WrapPointQueryTests testFixtureTwoAnswersFromTheTotalGuardWithoutCallingTheHook] : XCTAssertEqual failed: ("1") is not equal to ("0") - rebased == total: the guard must answer, and the hook must not be called at x == lineWidth
```
1 of 13 failures. **Asymmetry**: fixture 1's clamp tests (drill (e)'s pair) both stayed
**green** — fixture 1's rounding never lands on `total`, so removing this guard doesn't
touch that path.

**(n) — `wrapComputeChecksum(compute:drain:)`'s `compute &+ drain` reduced to `compute` alone.**

```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapComputeChecksumTests.swift:41: error: -[ViewportBenchmarksTests.WrapComputeChecksumTests testBothHalvesAffectTheChecksum] : XCTAssertNotEqual failed: ("5") is equal to ("5") - the drain half must be folded
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapComputeChecksumTests.swift:42: error: ... XCTAssertNotEqual failed: ("5") is equal to ("5") - zeroing the drain half must move the value -- it is the half that witnesses packing
```
2 of 2 failures in `WrapComputeChecksumTests`. **Asymmetry**: `WrapBenchmarkLineShapeTests`
stayed entirely **green** (`Executed 5 tests, with 0 failures`) — it only pins the printed
string with a literal `checksum:` value and never calls `wrapComputeChecksum`.

**(o) — `drainVisualRows`'s fold truncated to the first streamed row only.**

```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapComputeChecksumTests.swift:75: error: -[ViewportBenchmarksTests.WrapComputeChecksumTests testDrainFoldsEveryRowsEndColumnNotTheFirst] : XCTAssertEqual failed: ("0") is not equal to ("1") - exactly one row's endColumn moved by one, and the fold must carry it
```
1 of 2 failures. **Asymmetry**: `WrapComputeDrainTests` (D-29's own pin) stayed entirely
**green** — it asserts `sink > 0` and call-count/probe properties, never the fold's *value*,
so it cannot see this defect.

**Bonus, a fifteenth red — not a renumbering.** Task 8's fix round drilled the newly added
blank-line golden pin, `testBlankLineGoldenValuePinsTheSentinel` (`value = value &+ 104_729`
replaced with `break`):

```
Test Case '-[...WrapPointQueryChecksumTests testBlankLineCannotCollideWithACell]' passed (0.000 seconds)
/Users/.../WrapPointQueryChecksumTests.swift:73: error: -[ViewportBenchmarksTests.WrapPointQueryChecksumTests testBlankLineGoldenValuePinsTheSentinel] : XCTAssertEqual failed: ("1369") is not equal to ("106098")
```
The **old** inequality test (`testBlankLineCannotCollideWithACell`) stayed green under this
drill while the **new** golden pin failed — demonstrating the old test alone could not have
caught a defect the golden pin now can. This is an extra beyond the fourteen enumerated
drills, added because Task 8's fix round found the golden pin itself needed proving it could
fail; the fourteen are not renumbered.

**Two fix-wave additions, (p) and (q) — also not a renumbering.** The final whole-branch
review found two shipped guards with no recorded red (§9 item 7). Both are drilled below.
The fourteen enumerated drills and the bonus fifteenth above are untouched; these are
*additions*, and the letters continue past (o) rather than filling the (l)/(m) gap.

**Revert discipline, stated because it is the defect a drill exists to catch.** Both drills
mutate `Sources/TextEngineCore/WrapPointQuery.swift` while the working tree carried
*uncommitted* fixes to three test files and the plan. `git checkout --` was therefore
deliberately **not** used. The file was copied to a scratch path before the first mutation
and restored from that copy after each one; every restore was verified byte-identical by
`diff -q` **and** by md5 (`f8371ad972755d0758b3406ade2f057a` before and after both drills),
and the restored guard line was re-grepped, before the suite was re-run green.

**(p) — fix-wave addition. Decision 14's `>= total` ANSWER,
`Sources/TextEngineCore/WrapPointQuery.swift` `raw = rowSpan.endColumn - 1` →
`raw = rowSpan.startColumn`.**

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryTests.swift:259: error: -[TextEngineCoreTests.WrapPointQueryTests testFixtureTwoAnswersFromTheTotalGuardWithoutCallingTheHook] : XCTAssertEqual failed: ("cell(TextEngineCore.ColumnLocation(columnIndex: 1, clamp: TextEngineCore.ColumnLocation.Clamp.inRange))") is not equal to ("cell(TextEngineCore.ColumnLocation(columnIndex: 2, clamp: TextEngineCore.ColumnLocation.Clamp.inRange))")
```
`Executed 480 tests, with 1 failure (0 unexpected)`. **The same mutation left the whole suite
GREEN under the fixture as shipped at Task 11.** That fixture's advances were `[1e16, 4.0]`,
so its located row was `[1, 2)` — ONE cell, where `rowSpan.endColumn - 1` and
`rowSpan.startColumn` denote the *same* index. The fixture therefore pinned only that the
guard *fires*, never what it *answers*. The fix widens it to `[1e16, 2.0, 2.0]` with a break
before column 1 only (column 2 is deliberately not a break opportunity, so the packer cannot
split the tail back into two rows), making the located row `[1, 3)` and the expected answer
`columnIndex: 2` where `startColumn` would answer 1. The widened test now asserts its own
two-cell minimum, so the gap cannot silently reopen. Reverted; re-run
`Executed 480 tests, with 0 failures (0 unexpected)`.

**(q) — fix-wave addition. Step 7's non-finite rebase guard,
`if !rebased.isFinite { return .failure(.nonFiniteValue) }`, deleted.**

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPointQueryValidationTests.swift:89: error: -[TextEngineCoreTests.WrapPointQueryValidationTests testANonFiniteInteriorColumnOffsetFails] : XCTAssertEqual failed: ("point(TextEngineCore.VisualPointLocation(row: TextEngineCore.VisualRowLocation(globalRow: 1, logicalLine: 0, rowInLine: 1, clamp: TextEngineCore.LineLocation.Clamp.inRange), rowSpan: TextEngineCore.VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 1, endColumn: 2, width: inf), column: TextEngineCore.ColumnResolution.cell(TextEngineCore.ColumnLocation(columnIndex: 1, clamp: TextEngineCore.ColumnLocation.Clamp.inRange))))") is not equal to ("failure(TextEngineCore.ViewportValidationError.nonFiniteValue)")
```
`Executed 480 tests, with 1 failure (0 unexpected)`. **Before the fix wave this guard had no
test at all** — deleting it was entirely silent. The failure text states the defect exactly:
without the guard the query fabricates `.cell(columnIndex: 1, .inRange)` for a coordinate that
has no cell, where Decision 5 promises `.failure(.nonFiniteValue)`. The new conformer
`PoisonedInteriorOffsetLayout` reaches step 7 by poisoning an **interior** `columnOffset` with
`-∞` — the per-line ladder validates `columnOffset(0) == 0` and `columnOffset(count)` only and
trusts everything between, so an interior offset is the only route to the guard. The sign is
forced, not chosen: at `+∞` the located row's width is `columnOffset(end) - rowLeft = -∞`, so
step 6's `x >= rowSpan.width` clamps right *before* step 7 and the guard is bypassed. The test
asserts its own reachability (three packed rows, row 1 starting at the poisoned column, width
`+∞`) and carries a finite-row control. Reverted; re-run
`Executed 480 tests, with 0 failures (0 unexpected)`.

## 4. Suite, release build, Foundation scan

```
$ swift test 2>&1 | tail -5
	 Executed 479 tests, with 0 failures (0 unexpected) in 6.785 (6.815) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

```
$ swift build -c release 2>&1 | tail -3
[1/3] Write swift-version-58A378E29CF047B.txt
[3/4] Compiling ViewportBenchmarks BenchmarkModels.swift
Build complete! (2.11s)
```

```
$ FOUNDATION="$(rg -n "Foundation" Sources/TextEngineCore || true)"
$ if [ -z "$FOUNDATION" ]; then echo "foundation_scan=empty"; else echo "foundation_scan=DIRTY"; fi
foundation_scan=empty
$ BENCH_FOUNDATION="$(rg -n "^import Foundation" Sources/ViewportBenchmarks || true)"
$ if [ -z "$BENCH_FOUNDATION" ]; then echo "benchmarks_import_foundation=none"; else echo "benchmarks_import_foundation=PRESENT"; fi
benchmarks_import_foundation=none
```

**Observed count is 479, not 425 (55a's baseline).** 425 (55a) + 7 (Task 1) + 3 (Task 2) +
3 (Task 3) + 16 (Task 4) + 8 (Task 5, net; one `WrapRowQueryCountTests` case replaced not
added) + 2 (Task 6) + 1 (Task 7) + 11 (Task 8) + 1 (Task 8 fix round, the golden pin) + 2
(Task 9) + 0 (Task 10, docs-only) = 479. Matches the per-task reports' running counts
exactly.

**After the post-review fix wave the count is 480.** The wave adds exactly one test —
`WrapPointQueryValidationTests.testANonFiniteInteriorColumnOffsetFails` (Finding 2, drill
(q)). Finding 1 *widened an existing fixture* rather than adding a case, so it moves no
count. 479 + 1 = 480. Observed on the reverted tree at the end of the wave:

```
$ swift test 2>&1 | grep -E "(error:|Executed 480 tests)" | tail -5
	 Executed 480 tests, with 0 failures (0 unexpected) in 5.962 (5.990) seconds
	 Executed 480 tests, with 0 failures (0 unexpected) in 5.962 (5.991) seconds
```

(`grep` is on the right of the pipe here only to *display* the result; the pass/fail claim
rests on the `0 failures` count in the line itself, not on the pipeline's exit status, which
is `grep`'s and would be 0 either way. `${PIPESTATUS[0]}` is deliberately not used anywhere
in this record — see AC15.)

## 5. The twelve gates and the checksum baseline diff

Twelve modes, each run as its own literal invocation (never looped over a flags variable),
appended to one log:

```
$ swift run -c release ViewportBenchmarks -- --gate                          >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --variable-height --gate        >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate    >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --line-query --gate             >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --line-geometry-query --gate    >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --column-query --gate           >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --column-geometry-query --gate  >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --point-query --gate            >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --point-geometry-query --gate   >> gates.txt 2>&1
$ swift run -c release ViewportBenchmarks -- --realistic-provider --gate     >> gates.txt 2>&1
```

The 46 summary lines (build noise elided; every line below is `gate=pass`):

```
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1459 p99_ns=1546 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=14.4x headroom_p99=27.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1078.1x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=6246 p99_ns=6541 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=13.4x headroom_p99=26.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=254.8x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=19347 p99_ns=21186 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=14.5x headroom_p99=26.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=78.7x gate=pass checksum=18852477646272000
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=229 p99_ns=243 failures=0 budget_p95_ns=4100 budget_p99_ns=8200 headroom_p95=17.9x headroom_p99=33.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=6858.7x gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=758 p99_ns=840 failures=0 budget_p95_ns=14000 budget_p99_ns=28000 headroom_p95=18.5x headroom_p99=33.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1984.1x gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2504 p99_ns=2639 failures=0 budget_p95_ns=46000 budget_p99_ns=92000 headroom_p95=18.4x headroom_p99=34.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=631.6x gate=pass checksum=3536425156727040
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=462 p99_ns=502 failures=0 budget_p95_ns=6600 budget_p99_ns=14000 headroom_p95=14.3x headroom_p99=27.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=3320.1x gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1803 p99_ns=1975 failures=0 budget_p95_ns=24000 budget_p99_ns=48000 headroom_p95=13.3x headroom_p99=24.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=843.9x gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5864 p99_ns=6123 failures=0 budget_p95_ns=82000 budget_p99_ns=170000 headroom_p95=14.0x headroom_p99=27.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=272.2x gate=pass checksum=3571078666132451
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1172 p99_ns=1290 failures=0 budget_p95_ns=16000 budget_p99_ns=32000 headroom_p95=13.7x headroom_p99=24.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1292.0x gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=7213 p99_ns=8050 failures=0 budget_p95_ns=71000 budget_p99_ns=150000 headroom_p95=9.8x headroom_p99=18.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=207.0x gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=35445 p99_ns=38957 failures=0 budget_p95_ns=290000 budget_p99_ns=580000 headroom_p95=8.2x headroom_p99=14.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=42.8x gate=pass checksum=3379593298396981
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3305 p99_ns=4210 failures=0 budget_p95_ns=51000 budget_p99_ns=110000 headroom_p95=15.4x headroom_p99=26.1x budget_absolute_p99_ns=16666666 headroom_absolute_p99=3958.8x gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=12211 p99_ns=15174 failures=0 budget_p95_ns=130000 budget_p99_ns=260000 headroom_p95=10.6x headroom_p99=17.1x budget_absolute_p99_ns=16666666 headroom_absolute_p99=1098.4x gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=53616 p99_ns=57272 failures=0 budget_p95_ns=450000 budget_p99_ns=900000 headroom_p95=8.4x headroom_p99=15.7x budget_absolute_p99_ns=16666666 headroom_absolute_p99=291.0x gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=83179 p99_ns=120140 failures=0 budget_p95_ns=1400000 budget_p99_ns=2800000 headroom_p95=16.8x headroom_p99=23.3x budget_absolute_p99_ns=16666666 headroom_absolute_p99=138.7x gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=193932 p99_ns=296906 failures=0 budget_p95_ns=3000000 budget_p99_ns=6000000 headroom_p95=15.5x headroom_p99=20.2x budget_absolute_p99_ns=16666666 headroom_absolute_p99=56.1x gate=pass checksum=82203678997143
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=14 p99_ns=17 failures=0 budget_p95_ns=190 budget_p99_ns=440 headroom_p95=13.6x headroom_p99=25.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=98039.2x gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=19 p99_ns=38 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=14.7x headroom_p99=14.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=43859.6x gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=23 p99_ns=53 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=13.9x headroom_p99=12.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=31446.5x gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=93 p99_ns=101 failures=0 budget_p95_ns=1700 budget_p99_ns=3400 headroom_p95=18.3x headroom_p99=33.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=16501.6x gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=142 p99_ns=320 failures=0 budget_p95_ns=2100 budget_p99_ns=4200 headroom_p95=14.8x headroom_p99=13.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=5208.3x gate=pass checksum=639841547520
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=25 p99_ns=49 failures=0 budget_p95_ns=250 budget_p99_ns=500 headroom_p95=10.0x headroom_p99=10.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=34013.6x gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=25 p99_ns=66 failures=0 budget_p95_ns=340 budget_p99_ns=680 headroom_p95=13.6x headroom_p99=10.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=25252.5x gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=30 p99_ns=68 failures=0 budget_p95_ns=380 budget_p99_ns=760 headroom_p95=12.7x headroom_p99=11.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=24509.8x gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=238 p99_ns=437 failures=0 budget_p95_ns=3000 budget_p99_ns=6000 headroom_p95=12.6x headroom_p99=13.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=3813.9x gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=278 p99_ns=585 failures=0 budget_p95_ns=3400 budget_p99_ns=6800 headroom_p95=12.2x headroom_p99=11.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=2849.0x gate=pass checksum=852321495040
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=13 p99_ns=15 failures=0 budget_p95_ns=200 budget_p99_ns=440 headroom_p95=15.4x headroom_p99=29.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=111111.1x gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=20 p99_ns=51 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=14.0x headroom_p99=11.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=32679.7x gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=22 p99_ns=27 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=14.5x headroom_p99=23.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=61728.4x gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=37 p99_ns=43 failures=0 budget_p95_ns=500 budget_p99_ns=1000 headroom_p95=13.5x headroom_p99=23.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=38759.7x gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=50 p99_ns=68 failures=0 budget_p95_ns=600 budget_p99_ns=1200 headroom_p95=12.0x headroom_p99=17.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=24509.8x gate=pass checksum=639841560320
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=24 p99_ns=53 failures=0 budget_p95_ns=260 budget_p99_ns=520 headroom_p95=10.8x headroom_p99=9.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=31446.5x gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=26 p99_ns=73 failures=0 budget_p95_ns=350 budget_p99_ns=700 headroom_p95=13.5x headroom_p99=9.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=22831.0x gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=28 p99_ns=57 failures=0 budget_p95_ns=390 budget_p99_ns=780 headroom_p95=13.9x headroom_p99=13.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=29239.8x gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=52 p99_ns=84 failures=0 budget_p95_ns=820 budget_p99_ns=1700 headroom_p95=15.8x headroom_p99=20.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=19841.3x gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=56 p99_ns=90 failures=0 budget_p95_ns=690 budget_p99_ns=1400 headroom_p95=12.3x headroom_p99=15.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=18518.5x gate=pass checksum=839521520640
mode=point_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=33 p99_ns=72 failures=0 budget_p95_ns=760 budget_p99_ns=1600 headroom_p95=23.0x headroom_p99=22.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=23148.1x gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=41 p99_ns=103 failures=0 budget_p95_ns=680 budget_p99_ns=1400 headroom_p95=16.6x headroom_p99=13.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=16181.2x gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=66 p99_ns=132 failures=0 budget_p95_ns=920 budget_p99_ns=1900 headroom_p95=13.9x headroom_p99=14.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=12626.3x gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=71 p99_ns=129 failures=0 budget_p95_ns=1100 budget_p99_ns=2200 headroom_p95=15.5x headroom_p99=17.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=12919.9x gate=pass checksum=640022228480
mode=point_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=69 p99_ns=119 failures=0 budget_p95_ns=980 budget_p99_ns=2000 headroom_p95=14.2x headroom_p99=16.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=14005.6x gate=pass checksum=4687694617200924928
mode=point_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=58 p99_ns=95 failures=0 budget_p95_ns=990 budget_p99_ns=2000 headroom_p95=17.1x headroom_p99=21.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=17543.9x gate=pass checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=76 p99_ns=126 failures=0 budget_p95_ns=1200 budget_p99_ns=2400 headroom_p95=15.8x headroom_p99=19.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=13227.5x gate=pass checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=85 p99_ns=156 failures=0 budget_p95_ns=1300 budget_p99_ns=2600 headroom_p95=15.3x headroom_p99=16.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=10683.8x gate=pass checksum=5915921755926273280
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=6004 p99_ns=6658 failures=0 budget_p95_ns=98000 budget_p99_ns=200000 headroom_p95=16.3x headroom_p99=30.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=250.3x gate=pass checksum=756321289736960
```

```
$ PASS="$(grep -c 'gate=pass' gates.txt)"
$ FAIL="$(grep -c 'gate=fail' gates.txt)"
$ echo "gate_pass=$PASS gate_fail=$FAIL (expect 46 and 0)"
gate_pass=46 gate_fail=0 (expect 46 and 0)
```

Checksum baseline diff, using the D-18 `grep -v` filter (D-18 discharge, AC15):

```
$ grep -v -e 'mode=memory_shape' -e 'mode=memory_observation' gates.txt \
    | sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9-]+).*/\1|\2\t\3/p' \
    | sort -u > checksums-local.tsv
$ awk '/^### The 46 hosted checksum tuples/,0' docs/superpowers/verification/2026-08-28-wrap-point-query-trap-repairs.md \
    | awk '/^```/{n++; next} n==1' | sort -u > checksums-baseline.tsv
$ echo "local=$(wc -l < checksums-local.tsv | tr -d ' ') baseline=$(wc -l < checksums-baseline.tsv | tr -d ' ') (expect 46 and 46)"
local=46 baseline=46 (expect 46 and 46)
$ DIFF="$(diff checksums-baseline.tsv checksums-local.tsv || true)"
$ if [ -z "$DIFF" ]; then echo "checksum_diff=empty"; else echo "checksum_diff=NON_EMPTY -- a finding, not noise"; fi
checksum_diff=empty
```

**No movement in any of the twelve gates, and no movement in any of the 46 checksum
tuples.** This slice touches no gated code path (per AGENTS.md, any movement here would be
a finding); none was observed.

## 6. The three wrap modes and `--memory-shape`

**`--wrap-row-query`** — four checksums, compared against 55a's recorded values:

```
mode=wrap_row_query scenario=uniform_1k total_rows=1000 query_operations_per_sample=256 query_p95_ns=67 query_p99_ns=112 checksum=20459520000
mode=wrap_row_query scenario=uniform_100k total_rows=100000 query_operations_per_sample=256 query_p95_ns=235 query_p99_ns=268 checksum=2047976320000
mode=wrap_row_query scenario=narrow_100k total_rows=400000 query_operations_per_sample=256 query_p95_ns=246 query_p99_ns=282 checksum=2240234540000
mode=wrap_row_query scenario=clamped_100k total_rows=400000 query_operations_per_sample=256 query_p95_ns=29 query_p99_ns=35 checksum=2240231040000
```

| scenario | 55a recorded checksum | this run | match |
|---|---|---|---|
| `uniform_1k` | 20459520000 | 20459520000 | byte-identical |
| `uniform_100k` | 2047976320000 | 2047976320000 | byte-identical |
| `narrow_100k` | 2240234540000 | 2240234540000 | byte-identical |
| `clamped_100k` | 2240231040000 | 2240231040000 | byte-identical |

All four byte-identical — no movement, despite D-25 touching this mode's *tests* (D-25's
retarget lives in `WrapRowQueryCountTests`, a different file from the benchmark's own
checksum path).

**`--wrap-point-query`** — six scenarios, full output:

```
mode=wrap_point_query scenario=uniform_1k total_rows=1000 cells_per_line=20 rows_per_line=1 fast_path=true query_operations_per_sample=256 query_p95_ns=216 query_p99_ns=272 checksum=2306073081424253952
mode=wrap_point_query scenario=uniform_100k total_rows=100000 cells_per_line=20 rows_per_line=1 fast_path=true query_operations_per_sample=256 query_p95_ns=305 query_p99_ns=360 checksum=2306075108941053952
mode=wrap_point_query scenario=narrow_100k total_rows=400000 cells_per_line=20 rows_per_line=4 fast_path=false query_operations_per_sample=256 query_p95_ns=360 query_p99_ns=415 checksum=2306075259458473952
mode=wrap_point_query scenario=clamped_y_100k total_rows=400000 cells_per_line=20 rows_per_line=4 fast_path=false query_operations_per_sample=256 query_p95_ns=164 query_p99_ns=341 checksum=2306075261392253952
mode=wrap_point_query scenario=clamped_x_100k total_rows=400000 cells_per_line=20 rows_per_line=4 fast_path=false query_operations_per_sample=256 query_p95_ns=326 query_p99_ns=352 checksum=2306197982545833952
mode=wrap_point_query scenario=long_line_deep_row total_rows=400000 cells_per_line=2000 rows_per_line=400 fast_path=false row_in_line=399 query_operations_per_sample=16 query_p95_ns=8755 query_p99_ns=10877 checksum=2452436673478389824
```

All six checksums byte-identical to the values recorded in Task 8's report and the Task 8
fix round's re-run (the fold logic was untouched by the fix round — comments and one added
test only). `uniform_1k`/`uniform_100k` are `fast_path=true` (line fits, one row);
`narrow_100k`/`clamped_y_100k`/`clamped_x_100k` are `fast_path=false, rows_per_line=4`;
`long_line_deep_row` is the only scenario carrying `row_in_line=` (399, the last row of a
400-row line) and costs roughly 20-30x its logarithmic siblings — the within-line walk
becoming visible, which is the scenario's purpose.

**`--wrap-compute`** — not re-run this task (per the brief: "was already run and checked in
Task 9 Step 4 — carry that output into the record rather than re-running it," host-to-host
spread is 2.84x per D-31). Task 9's post-extraction ("after") run, the current committed
state:

```
mode=wrap_compute scenario=width_inf width=inf total_rows=100000 compute_operations_per_sample=256 compute_p95_ns=66 compute_p99_ns=131 drain_operations_per_sample=16 drain_p95_ns=8828 drain_p99_ns=76716 reindex_operations_per_sample=1 reindex_ns=20945000 checksum=181094400
mode=wrap_compute scenario=width_40 width=40 total_rows=200000 compute_operations_per_sample=256 compute_p95_ns=70 compute_p99_ns=95 drain_operations_per_sample=16 drain_p95_ns=8354 drain_p99_ns=9179 reindex_operations_per_sample=1 reindex_ns=13327375 checksum=143365120
mode=wrap_compute scenario=width_10 width=10 total_rows=800000 compute_operations_per_sample=256 compute_p95_ns=129 compute_p99_ns=240 drain_operations_per_sample=16 drain_p95_ns=5270 drain_p99_ns=116645 reindex_operations_per_sample=1 reindex_ns=54559667 checksum=115068800
```

| width | checksum | 55a recorded | match |
|---|---|---|---|
| inf | 181094400 | 181094400 | byte-identical |
| 40 | 143365120 | 143365120 | byte-identical |
| 10 | 115068800 | 115068800 | byte-identical |

Timings moved noticeably between Task 9's before/after runs (host variance, D-31); the
checksum — the value that must not move — did not.

**`--memory-shape`**:

```
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=765061875
```

All five `invariant=pass`.

**`cross-target-compile.sh --self-test`** (shell logic only — not portability evidence; this
slice's portability evidence is the two hosted jobs in §7):

```
$ ./.github/scripts/cross-target-compile.sh --self-test 2>&1 | tail -3
warn=sdk_install_attempt_failed attempt=1/3
warn=sdk_install_attempt_failed attempt=2/3
self_test=pass
```

## 7. Hosted proof

### PR-head run (Task 11 Step 6)

PR **#135** (`slice-55b-wrap-point-query` -> `main`), workflow run **33772207907**, head
**`334a94f`** — the current HEAD, i.e. the **post-fix-wave** head, not the earlier one. Read
at **step** level, not job conclusion: this repo's standing lesson is that a green job can
hide a dead `continue-on-error` step (Slice 16).

**Which run covers what.** An earlier run, **33758940527**, was green on the pre-fix-wave
head `6913fe7`; it is superseded by this run, which covers the fix wave (`334a94f`, six
findings, two new recorded reds per §9 item 7) as well as everything the earlier run covered.

Three jobs, all `success`:

```
$ gh run view 33772207907 -R maldrakar/swift-text-engine --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'
WASM cross-target compile: success
Host tests and benchmark gate: success
iOS cross-target compile: success
```

Every step of every job concluded `success` (the docs-only detector correctly declined this
PR — `result=not_docs_only docs_only_pr=false file_count=24 non_doc_count=18` in all three
jobs — so all three ran the heavy path, not the docs-only skip):

```
Host tests and benchmark gate | 4 Detect PR change scope: success
Host tests and benchmark gate | 5 Complete docs-only PR: skipped
Host tests and benchmark gate | 6 Show toolchain: success
Host tests and benchmark gate | 7 Run host tests: success
Host tests and benchmark gate | 8 Run synthetic benchmark gate: success
Host tests and benchmark gate | 9 Run variable-height benchmark gate: success
Host tests and benchmark gate | 10 Run variable-height mutation benchmark gate: success
Host tests and benchmark gate | 11 Run structural mutation benchmark gate: success
Host tests and benchmark gate | 12 Run bulk structural mutation benchmark gate: success
Host tests and benchmark gate | 13 Run line query benchmark gate: success
Host tests and benchmark gate | 14 Run line geometry query benchmark gate: success
Host tests and benchmark gate | 15 Run column query benchmark gate: success
Host tests and benchmark gate | 16 Run column geometry query benchmark gate: success
Host tests and benchmark gate | 17 Run point query benchmark gate: success
Host tests and benchmark gate | 18 Run point geometry query benchmark gate: success
Host tests and benchmark gate | 19 Run realistic provider benchmark gate: success
Host tests and benchmark gate | 20 Run memory shape diagnostic: success
Host tests and benchmark gate | 21 Run RSS memory observation diagnostic: success
iOS cross-target compile | 4 Complete docs-only PR: skipped
iOS cross-target compile | 6 Compile cross-target packages for iOS: success
WASM cross-target compile | 4 Complete docs-only PR: skipped
WASM cross-target compile | 7 Compile cross-target packages for WASM: success
```

Counts over the run log (fetched fresh; both fetches were byte-identical to the
pre-downloaded copy, 452453 bytes):

```
$ RUN=33772207907
$ gh run view "$RUN" -R maldrakar/swift-text-engine --log > hosted-prhead.log 2>&1
$ L=hosted-prhead.log
$ echo "gate=pass lines: $(grep -c 'gate=pass' "$L") (expect 46)"
gate=pass lines: 46 (expect 46)
$ echo "gate=fail lines: $(grep -c 'gate=fail' "$L") (expect 0)"
gate=fail lines: 0 (expect 0)
$ grep -oE 'Executed [0-9]+ tests, with [0-9]+ failures' "$L" | tail -1
Executed 480 tests, with 0 failures
```

46 `gate=pass` / 0 `gate=fail`, and **480 tests, 0 failures** on hosted Linux x86_64 — the
same 480 the local suite reports in §4.

**The WASM job's four `result=pass … blocking=true` lines** (two kinds x two packages), and
the iOS job's own four (two targets x two packages), counted **job-scoped** — an unscoped
whole-log grep prints 8 and reads as a mislabelled "WASM" counter (the plan-assertion defect
recorded in the 55a trap-repairs record):

```
$ echo "WASM blocking: $(awk -F'\t' '$1=="WASM cross-target compile" && /result=pass.*blocking=true/' "$L" | wc -l | tr -d ' ') (expect 4)"
WASM blocking: 4 (expect 4)
$ echo "iOS blocking:  $(awk -F'\t' '$1=="iOS cross-target compile" && /result=pass.*blocking=true/' "$L" | wc -l | tr -d ' ') (expect 4)"
iOS blocking:  4 (expect 4)
```

```
WASM cross-target compile | mode=cross_target_compile target=wasm          package=core      result=pass reason=none blocking=true
WASM cross-target compile | mode=cross_target_compile target=wasm_embedded package=core      result=pass reason=none blocking=true
WASM cross-target compile | mode=cross_target_compile target=wasm          package=providers result=pass reason=none blocking=true
WASM cross-target compile | mode=cross_target_compile target=wasm_embedded package=providers result=pass reason=none blocking=true
iOS cross-target compile  | mode=cross_target_compile target=ios_device    package=core      result=pass reason=none blocking=true
iOS cross-target compile  | mode=cross_target_compile target=ios_simulator package=core      result=pass reason=none blocking=true
iOS cross-target compile  | mode=cross_target_compile target=ios_device    package=providers result=pass reason=none blocking=true
iOS cross-target compile  | mode=cross_target_compile target=ios_simulator package=providers result=pass reason=none blocking=true
```

**Zero `mode=wrap_point_query` lines, and that absence is correct** — not a missing step.
`--wrap-point-query` is deliberately observational (§6) and is not wired into
`.github/workflows/swift-ci.yml`, so no CI step ever invokes it:

```
$ echo "wrap_point_query lines in CI: $(grep -c 'mode=wrap_point_query' "$L") (expect 0 - not wired)"
wrap_point_query lines in CI: 0 (expect 0 - not wired)
```

**The 46 hosted checksum tuples diff empty against slice 55a's recorded hosted baseline**
(the `### The 46 hosted checksum tuples` table in
`docs/superpowers/verification/2026-08-28-wrap-point-query-trap-repairs.md`):

```
$ grep -v -e 'mode=memory_shape' -e 'mode=memory_observation' "$L" \
    | sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9-]+).*/\1|\2\t\3/p' | sort -u > checksums-hosted.tsv
$ awk '/^### The 46 hosted checksum tuples/,0' docs/superpowers/verification/2026-08-28-wrap-point-query-trap-repairs.md \
    | awk '/^```/{n++; next} n==1' | sort -u > checksums-baseline.tsv
$ echo "hosted=$(wc -l < checksums-hosted.tsv | tr -d ' ') baseline=$(wc -l < checksums-baseline.tsv | tr -d ' ')"
hosted=46 baseline=46
$ D="$(diff checksums-baseline.tsv checksums-hosted.tsv || true)"
$ if [ -z "$D" ]; then echo "hosted_checksum_diff=empty"; else echo "hosted_checksum_diff=NON_EMPTY"; fi
hosted_checksum_diff=empty
```

This slice touches no gated code path, so any movement here would have been a finding, not
noise — none was observed.

**One extra thing this run discharges.** The Task 8 review of the `1e16` floating-point
fixtures (`Tests/TextEngineCoreTests/WrapPointQueryTests.swift`, the two fixtures around
lines 200/219 and the IEEE rounding-property assertions
`XCTAssertEqual(1e16 + 3.9, 1e16 + 4.0, …)` at lines 228 and 247) left an open note that the
property `1e16 + 3.9 == 1e16 + 4.0` had only ever been exercised on local macOS arm64. This
run's hosted x86_64 job ran the full 480-test suite green, and that suite contains both
`1e16` fixtures, so the property is now confirmed on the CI architecture too — IEEE 754
double rounding at that magnitude behaves identically on both architectures, not just
locally.

### Post-merge push run (Task 11 Step 7)

**Pending — out of this task's scope.** The branch is not merged; Step 7 (the post-merge
push run, read at step level) is performed after the PR merges and lands as a separate
commit.

## 8. D-32, stated

The shared within-line-walk helper, `advanceVisualRows(_:by:)`, has exactly two call sites
(Task 7 Step 3):

```
$ grep -rn 'advanceVisualRows(&' Sources/TextEngineCore
Sources/TextEngineCore/WrapPointQuery.swift:73:        guard let rowSpan = advanceVisualRows(&cursor, by: row.rowInLine + 1) else {
Sources/TextEngineCore/DocumentVisualRowCursor.swift:58:            _ = advanceVisualRows(&cursor, by: rowInStartLine)
```

`WrapPointQueryRoundTripTests.testEveryStreamedRowIsFoundByItsOwnPoint` drives both call
sites over a fixture with `fitting = 3` fitting lines and `wrapped = 2` wrapped lines (this
corrects Task 7's own report, which stated `fitting = 2`; the blank line, total advance
`0.0`, also satisfies the `<=` guard and is a third fitting line — the fixture's assertions
only require `> 0` on each side, so both values are correctly reported as positive
regardless of the arithmetic error, but the true counts are 3 and 2, not 2 and 2).

The probe, run and reverted (Task 7 Step 3(ii)): `DocumentVisualRowCursor.init`'s call site
was replaced with the inline walk it used to be —
`for _ in 0..<rowInStartLine { _ = inner?.next() }` — and the suite was re-run.

```
$ swift test --filter WrapPointQueryRoundTripTests
Executed 1 test, with 0 failures (0 unexpected)
$ swift test
Executed 465 tests, with 0 failures (0 unexpected)
```

**Result: GREEN**, both the round-trip test alone and the whole suite. Reverted; `git diff
Sources/` was empty afterward.

**The sentence the discharge rests on, stated in full.** The shared-helper property — that
`DocumentVisualRowCursor.init` and `visualPointAt` agree on "row *k* of line *L*" because
both walk through the same `advanceVisualRows` helper — is **observable**: two call sites,
one helper, one round-trip test holding them equal on a fixture covering both of
`greedyEnd`'s branches. It is **not enforced** by any red: reverting one call site to an
inline walk is behaviourally indistinguishable from the shared call while producer guard 4
holds (`rowInStartLine < 0` cannot reach the loop either way), so no assertion anywhere —
not the round trip, not the 465-test suite at the time of the probe — reddens on that
reversion. Enforcement would require a call-site pin (a structural assertion that the source
text calls the shared helper), which is a different, un-taken decision.

## 9. Deviations from the spec, with reasons

1. **The `--wrap-point-query` scenario floors were raised above the spec's values.** The
   spec's Contract 55b names `cells >= 1_000` / `rowsPerLine >= 100` for
   `long_line_deep_row`; the shipped scenario uses `cells: 2_000` / the derived
   `rowsPerLine >= 400`. At the spec's values, drill (j) (§3) would not redden — Task 8
   found this while implementing the parameter-floor pin and raised the floors so the drill
   is genuinely falsifiable, recording the reason in both the source and the Task 8 report.

2. **Task 8 had to add an arm to a fifth exhaustive switch over `BenchmarkMode`.**
   `runSyntheticScenario` in `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift:120`
   switches over `mode` and `preconditionFailure`s for every non-`.pipeline`/`.rangeOnly`
   mode. The plan's file inventory named only four exhaustive switches (`outputName`,
   `isGateable`, `absoluteCeiling`, `parse`'s dispatch); this fifth one is not in that
   inventory, and without adding `case .wrapPointQuery: preconditionFailure(...)` the target
   does not compile. The compiler forced the answer — nothing was silently defaulted — but
   the inventory gap is worth carrying forward for the next mode-adding slice.

3. **A false claim was retracted, not repeated.** The plan and the spec (as it stood on
   `main` before this branch) both asserted that re-packing every line in
   `WrapPointQueryLayout` would cost "~10⁹ packing steps" and "appear to hang." **This is
   false by roughly three orders of magnitude.** `greedyEnd`
   (`Sources/TextEngineCore/VisualRowCursor.swift:76-93`) `break`s at the first legal end
   that overflows the width, so a row's scan is bounded by its own cells, the rows' scans
   partition the line, and packing one line is **O(cells)** — re-packing every line is
   **O(lineCount × cells)**, not the claimed step count. The source comment was corrected in
   commit `de10e37`; the spec was amended in commit `e563794` (Revision History entry 13,
   "twelfth pass," an amendment/retraction, not a new decision). **This false claim is not
   repeated anywhere else in this record or the PR body.** Note for the reader: commit
   `8ad909f`'s own commit-message body still carries the superseded sentence — that commit
   was not rewritten (per instruction not to rewrite history), and the correction lives in
   `de10e37` and the spec amendment instead.

4. **The D-25 retarget** (not merely a tightened bound). `WrapRowQueryCountTests`' original
   `testProbeCountDoesNotGrowLinearlyWithTheDocument` asserted `totalCalls < lineCount / 10`
   (= 102) at row 1000. Tightening that bound in place would not have discharged D-25: over
   1024 lines the default `logicalLine` search costs 10 probes at almost every target, so row
   700 (the sibling test's own target) and row 1000 (the old target) both measure the same
   13 total probes — the same fixture, same branch, same count, same bound the sibling
   already asserts. The test needed a **different target**, not a tighter number at the same
   one. Only rows 1022/1023 reach the search's actual 11-probe worst case on the in-range
   branch; the replacement test, `testTheInRangeWorstCaseTargetHasNoSlackAgainstTheBound`,
   targets row **1022**, where the observed count is exactly 14 (`expectedMax`), read back
   via a temporary literal-mismatch assertion, with zero slack.

5. **AC9's 55b half is discharged by assertion, not by drill.** AC9 reads: "an overriding
   conformer proves the row-axis hook is dispatched, for `visualRowAt` (55a) and
   `visualPointAt` (55b), **with a recorded red when the dispatch is bypassed**." This slice
   covers the dispatch itself — `WrapPointQueryCountTests`' fixture 2 asserts
   `logicalLineDispatches == 1` on both the clamped and the delegating path (also AC7's own
   requirement) — but records **no red** for a bypassed dispatch, because Contract 55b's
   drill list (the authoritative distribution across the plan's tasks) is the twelve named
   there and carries no dispatch-bypass drill, and D-24's ledger row is already
   `discharged(slice 55a)` on 55a's own red (`VisualRowDispatchTests`). AC9's 55b half is
   therefore discharged **by assertion, not by drill**. The alternative — a `visualPointAt`
   case added to `VisualRowDispatchTests` plus a fifteenth drill — was not taken because it
   would add a guarantee outside this slice's scoped contract; it is the cheap repair if a
   reviewer disagrees (one test, one drill).

6. **Two deferred minor findings, not fixed this slice.**
   - `Tests/ViewportBenchmarksTests/WrapComputeChecksumTests.swift`'s secondary assertion
     that `perturbed.visualRowCount(inLine:) == 2` is **tautological**: the test layout
     (`ShortenedLineLayout`) forwards `visualRowCount` unconditionally to its base and never
     consults the shortened line, so the assertion cannot fail regardless of what the
     shortening actually does. Fresh evidence for ledger row **D-34**, already
     `scheduled(slice-56)`.
   - `Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift`'s `let mustScan = 55 - 15` is
     hand-computed from the fixture's advances rather than algebraically derived from the
     test's own `near`/`far` variables — correct today, but a latent transcription risk if
     the fixture ever changes without the literal being re-derived by hand again.

7. **A post-review fix wave, landed after this record was first written.** The final
   whole-branch review returned six findings; all six are fixed on this branch before merge,
   in one commit (entry 17 of the commit list above). **`visualPointAt`'s behaviour is
   unchanged by the wave** — findings 1 and 2 were *test* gaps, not engine defects, and the
   only edit under `Sources/` is a doc comment (finding 3). That is why §5's 46 gated
   checksum tuples and the `checksum_diff=empty` result are untouched by it — **re-verified,
   not asserted**: the twelve gated invocations of §5 were re-run at the end of the wave, all
   twelve exited 0, all 46 summary lines read `gate=pass`, and the 46
   `(mode, provider, scenario, checksum)` tuples compare byte-identical to the block in §5.

   - **Finding 1 — a fixture that could not separate the right answer from a wrong one.**
     Decision 14's `>= total` branch answers `rowSpan.endColumn - 1`. Fixture 2's located row
     (advances `[1e16, 4.0]`, row `[1, 2)`) held exactly **one** cell, where that expression
     and `rowSpan.startColumn` denote the same index — so mutating the branch to the wrong
     one left the entire suite green. The fixture pinned that the guard *fires*, not what it
     *answers*. Widened to `[1e16, 2.0, 2.0]` (row `[1, 3)`, two cells, column 2 not a break
     opportunity) and drilled: **(p)**. Generalised lesson, already in the ledger's idiom: a
     pin is only as strong as the fixture's ability to *separate* the answers, and where two
     quantities coincide no assertion in them can tell the branches apart.
   - **Finding 2 — a shipped guard with no test.** Step 7's `!rebased.isFinite` check had no
     coverage at all; deleting it was silent. New conformer `PoisonedInteriorOffsetLayout`
     plus `testANonFiniteInteriorColumnOffsetFails`, drilled: **(q)**.
   - **Finding 3 — Decision 6's lower clamp half is deliberately left without a red.** The
     clamp is `min(max(raw, rowSpan.startColumn), rowSpan.endColumn - 1)`, and only the
     **upper** half can fire under a conforming provider: control reaches it only with
     `x >= 0`, so `rebased >= rowLeft == columnOffset(startColumn)`, and a monotone
     `columnIndex` hook cannot answer below `startColumn`. The `max` is defensive symmetry
     against a provider that violates that contract. **No conforming fixture can reach it**,
     so it carries no recorded red, and the asymmetry is now recorded in the source comment
     rather than papered over with a deliberately non-conforming fixture built only to make a
     drill redden — which would pin the mock, not the guarantee. This is the single standing
     exception to AC14 after the wave, and it is named as such in the §1 table.
   - **Findings 4 and 5 — documentation corrections.** The plan
     (`docs/superpowers/plans/2026-09-03-wrap-point-query.md`) restated the retracted
     "~10⁹ packing steps"/"appear to hang" claim (item 3 above) at **two** sites — the doc
     comment it prescribes, and the Task 8 commit-message body it prescribes. Both are
     rewritten to cost classes, each carrying a bracketed editorial retraction note so the
     change reads as a correction rather than as history quietly rewritten.
     `WrapPointQueryEquivalenceTests`' "exact cell boundaries for every line" comment was
     corrected in the same wave.
   - **Finding 6 — this record.** The commit count (was "Fifteen", the branch carried 16
     before the wave's own commit and 17 after), the test count (was 479, now 480), the two
     new recorded reds, the honest AC14 disposition, and this entry.

   **AC14 is not silently rewritten.** Its §1 row states what was true before the wave — two
   shipped guards survived deletion with the whole suite green, so the criterion was **not**
   met as shipped at Task 11 — and what is true after, with the one deliberate exception
   above. The governing rule this discharges: *a guarantee whose drill is missing is an
   unfinished acceptance criterion, not a review finding.*

Two decisions recorded elsewhere and cross-referenced here for completeness: **Decision 15
and AC19** (the D-33 fold-in, `wrapComputeChecksum`/`drainVisualRows` completeness pins,
Task 9) and **D-18's discharge** (the `grep -v` checksum-extraction filter, §5) — both are
listed in the AC table (§1) and are not repeated here since neither is a departure from what
the spec already specified for this slice.
