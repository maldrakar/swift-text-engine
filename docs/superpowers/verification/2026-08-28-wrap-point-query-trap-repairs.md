# Slice 55a — wrap trap repairs (node 4, piece 1) — verification record

The first of node 4's two pieces shipped **eight** commits on `slice-55a-wrap-trap-repairs`,
in this order: `a8c957a` *feat: the wrap_compute line prints its checksum* (commit 0, the
Decision 13 witness), `7512e0d` *refactor: extract the within-line walk; the document cursor
guards its start* (commit 1), `ebd5659` *feat: visualRowAt rejects a malformed logicalLine
override instead of trapping* (commit 2), `0235e73` *refactor: extract the per-line wrap
ladder; the cursor stores total* (commit 3), `a2007cc` *feat: the packer short-circuits when
the remaining suffix fits* (commit 4), `f143e96` *docs: the last-row O(1) claim is qualified
by overflow*, `c384f7b` *refactor: extract the `--wrap-compute` drain body so its purity is
testable (D-29)* (commit 5), and `58b78f4` *test: pin that the row-axis hook is dispatched
(D-24)* (commit 6). The extra, review-driven `docs:` commit `f143e96` — sixth in the order
above, and the one commit beyond the seven the plan contracted — exists because the Task 5
review produced a **counter-example** to the "the last row of every line packs in O(1)"
claim: on a line whose tail is an unbreakable run wider than `wrapWidth`, `greedyEnd`'s
suffix test `total - startOffset <= wrapWidth` does not fire on the last row either, the scan
runs and falls to the `firstLegal` forced-overflow fallback, and that last row costs
O(cells). No code line changed — the claim was narrowed with "unless it overflows" at four
in-repo sites (`AGENTS.md`'s node 1 and node 2 paragraphs, `DocumentVisualRowCursor.swift`'s
type doc comment, `VisualRowCursor.swift`'s `greedyEnd` comment) and four spec lines (305,
770, 1008–1009 and 1408; the latter two in this slice's final-review follow-up). The piece
adds **no new public API**: it adds five producer guards so a malformed
`logicalLine(containingVisualRow:)` override never traps (two in `visualRowAt`, two in
`DocumentVisualRowCursor.init`, one in the new shared walk helper), two behaviour-preserving
extractions shared with node 4's query (`advanceVisualRows(_:by:)` and `validateWrapLine`),
and the `greedyEnd` suffix short-circuit; it discharges **D-24** and **D-29**; and it records
**nine** drill reds. After these eight come the docs commits: this record with the ledger
edits, then the hosted-proof commit (`624b4d8`) and the final-review docs follow-up.

## 1. Acceptance criteria owned by this piece

| AC | Disposition | Evidence |
|---|---|---|
| 5 (the two `visualRowAt` cases, pinned directly) | **Met** — both cases are named tests in `WrapRowQueryValidationTests` on a plain array-backed conformer with the hook overridden, each yielding `.failure(.invalidVisualRowLayout)` rather than a trap; four reds observed before the guards existed | §3 |
| 8 (the shared walk, five guards, five reds) | **Met** — `advanceVisualRows(_:by:)` is one internal `inout` helper called by both `DocumentVisualRowCursor.init` and (in 55b) the query; five guards, five recorded reds ((d1), (f1)–(f4)) | §3, §5 |
| 9 (D-24) | **Discharged** — `VisualRowDispatchTests`, three tests, both dispatch sites drilled and both reddened | §5 |
| 10 (D-29) | **Discharged** — `WrapComputeDrainTests` asserts zero `firstVisualRow(ofLine: lineCount)` probes across the drain body with a non-vacuous witness call; a `compute` placed inside the body reddens it | §5 |
| 13 (Foundation scan, suite, release build, gated checksums) | **Met** — Foundation scan empty, `Executed 425 tests, with 0 failures`, release build green, 46 gated checksums byte-identical to the pre-branch baseline | §6 |
| 14 (recorded reds: nine in 55a) | **Met** — (d1), (f1), (f2), (f3), (f4), (l), (m), D-24 (two sites), D-29, each with its observed line | §5 |
| 16 (hosted evidence, both runs) | **PR-head half met** at step level with the run id; the post-merge push half is filled after the user merges | §7 |
| 17 (Decision 12, taken) | **Taken** — the short-circuit is `if total - startOffset <= wrapWidth { return columnCount }` in `greedyEnd`, reading `total` from stored state; both O(1) cases pinned red-first by `WrapPackingCountTests`; drill (l)'s inversion reddens `WrapPackingTests`; drill (m)'s narrowing reddens only the last-row pin; `--wrap-compute` recorded on all three widths and all three token families with every deviation recorded as a FINDING | §4, §5 |
| 18 (Decision 13, taken) | **Taken** — `validateWrapLine` is one internal function, `visualRows` a wrapper with unchanged signature/return type/probe order/failures, `VisualRowCursor` stores `total` through its `internal` init, no public type gains a field; the named suites pass **unedited**; the `wrap_compute` line prints `checksum=`, pinned in `WrapBenchmarkLineShapeTests`; both wrap modes' checksums are byte-identical across the extraction commit and across the Decision 12 commit | §2, §4 |

## 2. The five suites, unedited across commits 3 and 4

Commit 3 (`0235e73`, Task 4 Step 3) — `git diff --quiet HEAD -- Tests/…` over the named
suites, then the suites run:

```
PASS: no test file edited
green: WrapPackingTests
green: WrapValidationTests
green: WrapComputeTests
green: VisualRowEquivalenceTests
green: WrapComputeEquivalenceTests
green: VisualRowWalkHelperTests
suite green
Executed 419 tests, with 0 failures (0 unexpected)
```

Commit 4 (`a2007cc`, Task 5 Step 4) — the same check over `WrapPackingTests`,
`WrapValidationTests`, `WrapComputeTests`, `VisualRowEquivalenceTests`,
`WrapComputeEquivalenceTests`:

```
PASS: the five suites are unedited
green: WrapPackingCountTests
green: WrapPackingTests
green: WrapValidationTests
green: WrapComputeTests
green: VisualRowEquivalenceTests
green: WrapComputeEquivalenceTests
green: WrapRowQueryRoundTripTests
suite green
Executed 421 tests, with 0 failures (0 unexpected) in 6.466 (6.491) seconds
```

Suite counts across the branch: 408 (pre-branch baseline) → 408 (commit 0, one assertion
added to an existing test) → 415 (commit 1, +2 cursor guards +5 helper cases) → 419
(commit 2, +4 `visualRowAt` cases) → 419 (commit 3, extraction, no test added) → 421
(commit 4, +2 packing-count pins) → 422 (commit 5, +1 drain purity pin) → 425 (commit 6,
+3 dispatch pins).

## 3. The guards — red before, green after

Five guards, five reds, each observed **before** the guard existed. Four are traps (the test
process exits on signal 5, so each trap-shaped case was run alone under `--filter`; a
combined run would stop at the first trap and the second red would never be observed); two
are `.row(…)` mismatches where the malformed answer was returned rather than rejected.

**Guard 3** — `DocumentVisualRowCursor.init`, `startLine` outside `0..<lineCount`
(`testCursorStreamsNothingWhenTheHookAnswersOutOfRange`, Task 2 Step 3):

```
error: Exited with unexpected signal code 5
Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range
```

**Guard 4** — `DocumentVisualRowCursor.init`, negative `rowInStartLine`
(`testCursorStreamsNothingWhenTheHookMakesRowInLineNegative`, Task 2 Step 3):

```
error: Exited with unexpected signal code 5
Swift/arm64e-apple-macos.swiftinterface:19659: Fatal error: Range requires lowerBound <= upperBound
```

**Guard 5** — the helper's `k <= 0` rule, observed as a compile red before
`advanceVisualRows` existed (`VisualRowWalkHelperTests`, Task 2):

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/VisualRowWalkHelperTests.swift:21:22: error: cannot find 'advanceVisualRows' in scope
```

**Guard 1** — `visualRowAt`, `logicalLine` outside `0..<lineCount` (Task 3 Step 2), two
cases:

```
testHookAnsweringAboveLineCountIsRejectedNotTrapped
Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range

testHookAnsweringNegativeIsRejectedNotTrapped
Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range

/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift:149: error: -[TextEngineCoreTests.WrapRowQueryValidationTests testHookAnsweringExactlyLineCountIsRejected] : XCTAssertEqual failed: ("row(TextEngineCore.VisualRowLocation(globalRow: 1, logicalLine: 3, rowInLine: -2, clamp: TextEngineCore.LineLocation.Clamp.inRange))") is not equal to ("failure(TextEngineCore.ViewportValidationError.invalidVisualRowLayout)")
```

**Guard 2** — `visualRowAt`, negative `rowInLine` (Task 3 Step 2):

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift:162: error: -[TextEngineCoreTests.WrapRowQueryValidationTests testHookMakingRowInLineNegativeIsRejected] : XCTAssertEqual failed: ("row(TextEngineCore.VisualRowLocation(globalRow: 1, logicalLine: 2, rowInLine: -1, clamp: TextEngineCore.LineLocation.Clamp.inRange))") is not equal to ("failure(TextEngineCore.ViewportValidationError.invalidVisualRowLayout)")
```

Green after, per commit: commit 1 → `green: VisualRowWalkHelperTests`,
`green: WrapComputeTests`, `green: WrapComputeEquivalenceTests`,
`green: WrapRowQueryRoundTripTests`, `Executed 415 tests, with 0 failures (0 unexpected) in
6.838 (6.866) seconds`. Commit 2 → `green: WrapRowQueryValidationTests`,
`green: WrapRowQueryCountTests`, `green: WrapRowQueryTests`,
`green: WrapRowQueryEquivalenceTests`, `Executed 419 tests, with 0 failures (0 unexpected)
in 6.963 (6.988) seconds`. Commit 2's guards added **no** provider probe:
`WrapRowQueryCountTests`'s `<= ceilLog2(lineCount) + 4` bound stayed green, and the guards
read only values already computed in that frame plus the `lineCount` property.

### Plan-assertion defect #1 (D-2 class) — Task 3 Step 6's `HITS` regex could not pass

Step 6's `HITS` assertion carried the alternative `accept/reject sets are\s*$`, which matches
`Sources/TextEngineCore/WrapViewportVirtualizer.swift:2` — a line that is **identical** in the
plan's own "Replace" and "With" blocks (the narrowing begins on line 3), so `rg`'s
end-of-line `$` cannot discriminate narrowed from unnarrowed text there. The check printed:

```
FAIL:
Sources/TextEngineCore/WrapViewportVirtualizer.swift:2:/// `compute(_:layout:)` and `visualRowAt(y:layout:)` so their accept/reject sets are
```

The edits were applied byte-for-byte as specified and the narrowing was verified instead with
discriminating patterns: the old wording (`exactly the same layouts by construction`,
`equal by construction rather than by inspection (spec Decision 5)`) has **zero** hits, `AT
THE LADDER` appears at both core sites, and `**at the ladder**` appears in `AGENTS.md`. The
doc comment was not rewrapped to dodge the match.

## 4. `--wrap-compute`, one column per commit

Seven columns. B1 and B2 are two independent runs at commit 0 (the noise floor); C1, C3, C4,
C5 are commits 1, 3, 4, 5. **C3b exists** because C3 came out uniformly 1.029–1.692× slower
than C1 on **every** token, including the `compute_*` path that no commit in this slice
touches — a host-state event, not a code effect. Since the plan's `predict.py` divides C4 by
C3, a supplementary column **C3b** was taken at the same HEAD (`0235e73`) before any Task 5
edit. C3 is **not** replaced; both are carried and both are used below. C3b's own `width_inf`
column is itself the anomalously **fast** one: `compute_p95_ns` 68 against 115 (C1) and 132
(C3); `reindex_ns` 17 200 166 against 35 786 292 (C1) and 48 920 334 (C3).

| scenario | token | B1 | B2 | C1 | C3 | C3b | C4 | C5 |
|---|---|---|---|---|---|---|---|---|
| `width_inf` | `compute_p95_ns` | 95 | 81 | 115 | 132 | 68 | 140 | 117 |
| `width_inf` | `compute_p99_ns` | 183 | 126 | 193 | 212 | 81 | 187 | 135 |
| `width_inf` | `drain_p95_ns` | 15950 | 15250 | 15083 | 18166 | 15411 | 8773 | 8763 |
| `width_inf` | `drain_p99_ns` | 16773 | 16197 | 16104 | 22177 | 16309 | 9828 | 9312 |
| `width_inf` | `reindex_ns` | 27266042 | 16896666 | 35786292 | 48920334 | 17200166 | 14552458 | 11923958 |
| `width_inf` | `checksum` | 181094400 | 181094400 | 181094400 | 181094400 | 181094400 | 181094400 | 181094400 |
| `width_40` | `compute_p95_ns` | 83 | 81 | 85 | 106 | 71 | 78 | 80 |
| `width_40` | `compute_p99_ns` | 143 | 118 | 125 | 180 | 85 | 101 | 92 |
| `width_40` | `drain_p95_ns` | 9791 | 9507 | 9440 | 11578 | 9783 | 7947 | 8054 |
| `width_40` | `drain_p99_ns` | 10549 | 10072 | 10130 | 16018 | 10692 | 8338 | 8546 |
| `width_40` | `reindex_ns` | 18130500 | 17441833 | 16891417 | 19012875 | 17935750 | 11652542 | 11069708 |
| `width_40` | `checksum` | 143365120 | 143365120 | 143365120 | 143365120 | 143365120 | 143365120 | 143365120 |
| `width_10` | `compute_p95_ns` | 87 | 87 | 86 | 105 | 71 | 74 | 87 |
| `width_10` | `compute_p99_ns` | 153 | 156 | 150 | 180 | 90 | 100 | 140 |
| `width_10` | `drain_p95_ns` | 5065 | 4984 | 5151 | 6075 | 4955 | 4838 | 4924 |
| `width_10` | `drain_p99_ns` | 5492 | 5575 | 5682 | 9614 | 5367 | 5286 | 5463 |
| `width_10` | `reindex_ns` | 25305209 | 23866083 | 23862000 | 24562791 | 22645958 | 22189458 | 21575084 |
| `width_10` | `checksum` | 115068800 | 115068800 | 115068800 | 115068800 | 115068800 | 115068800 | 115068800 |

The `checksum=` token is **byte-identical in all seven columns** at all three widths
(181094400 / 143365120 / 115068800) — the Decision 13 witness held across both extractions
and the Decision 12 branch, and no wrap-compute packing result changed anywhere.

### The noise floor and the "flat" rule

The plan's rule for flatness is the **B1/B2 spread**, which on this host is **0.620–1.020**
(minimum `width_inf reindex_ns` = 0.620, maximum `width_10 compute_p99_ns` = 1.020). Any
ratio outside it is a FINDING recorded with its number.

### `--wrap-compute` per-commit findings against that rule

**C1 vs B2** (commit 1). `drain_p95_ns`/`drain_p99_ns` — the path this commit touches — stay
at 0.989 / 0.994 (`width_inf`), 0.993 / 1.006 (`width_40`), 1.034 / 1.019 (`width_10`).
FINDING: five ratios outside the spread, all on paths this commit does not touch —
`width_inf compute_p95_ns` = 1.420, `width_inf compute_p99_ns` = 1.532,
`width_inf reindex_ns` = 2.118, `width_40 compute_p95_ns` = 1.049,
`width_40 compute_p99_ns` = 1.059. `width_10 drain_p95_ns` = 1.034 is also marginally
outside. All three checksums IDENTICAL.

**C3 vs C1** (commit 3). FINDING: **all fifteen** timing ratios are above 1.0, spanning
1.029–1.692, and all but `width_10 reindex_ns` (1.029) sit outside the spread — including
the untouched `compute_*` path (1.098, 1.148, 1.200, 1.221, 1.247, 1.440). The touched path
reads `drain_p95_ns` 1.204 / 1.226 / 1.179 and `drain_p99_ns` 1.377 / 1.581 / 1.692 (widest
of the column). All three checksums IDENTICAL. This uniform elevation of both touched and
untouched tokens is what C3b was taken to characterise.

**C3b vs C3** (same HEAD `0235e73`, zero code change between them). Every one of the fifteen
ratios is below 1.0 (0.352–0.943), i.e. C3b is faster on every token: `width_inf
compute_p95_ns` 0.515, `compute_p99_ns` 0.382, `reindex_ns` 0.352; `width_40` 0.670 / 0.472 /
0.943; `width_10` 0.676 / 0.500 / 0.922; `drain_*` 0.848 / 0.735, 0.845 / 0.667, 0.816 /
0.558. All three checksums IDENTICAL. Two measurements of the same commit differing by up to
2.84× is the size of this host's state effect.

**C5 vs C4** (commit 5). FINDING: five ratios outside the spread —
`width_40 compute_p95_ns` = 1.026, `width_40 drain_p99_ns` = 1.025,
`width_10 compute_p95_ns` = 1.176, `width_10 compute_p99_ns` = 1.400,
`width_10 drain_p99_ns` = 1.033. The touched path (`drain_*`, which runs the extracted
`drainVisualRows` body) reads 0.999 / 0.947 (`width_inf`), 1.013 / 1.025 (`width_40`),
1.018 / 1.033 (`width_10`) — two of its six ratios (both `drain_p99_ns`) are outside. All
three checksums IDENTICAL.

### `predict.py` — RUN 1 (`B1 B2 C3 C4`, the plan's literal invocation)

```
width_inf  reindex_ns    ratio=0.297  predicted [0.00, 0.75]  PASS
width_inf  drain_p95_ns  ratio=0.483  predicted [0.00, 0.75]  PASS
width_inf  drain_p99_ns  ratio=0.443  predicted [0.00, 0.75]  PASS
width_40   reindex_ns    ratio=0.613  predicted [0.45, 0.95]  PASS
width_40   drain_p95_ns  ratio=0.686  predicted [0.45, 0.95]  PASS
width_40   drain_p99_ns  ratio=0.521  predicted [0.45, 0.95]  PASS
width_10   reindex_ns    ratio=0.903  predicted [0.70, 1.02]  PASS
width_10   drain_p95_ns  ratio=0.796  predicted [0.70, 1.02]  PASS
width_10   drain_p99_ns  ratio=0.550  predicted [0.70, 1.02]  FINDING
reindex_ns               order inf<40<10<1: 0.297 < 0.613 < 0.903  PASS
width_10   compute_p95_ns ratio=0.705  noise floor x1.15  FINDING
width_10   compute_p99_ns ratio=0.556  noise floor x1.15  FINDING
width_10   checksum IDENTICAL
drain_p95_ns             order inf<40<10<1: 0.483 < 0.686 < 0.796  PASS
width_10   compute_p95_ns ratio=0.705  noise floor x1.15  FINDING
width_10   compute_p99_ns ratio=0.556  noise floor x1.15  FINDING
width_10   checksum IDENTICAL
drain_p99_ns             order inf<40<10<1: 0.443 < 0.521 < 0.550  PASS
width_10   compute_p95_ns ratio=0.705  noise floor x1.15  FINDING
width_10   compute_p99_ns ratio=0.556  noise floor x1.15  FINDING
width_10   checksum IDENTICAL
```

### `predict.py` — RUN 2 (`B1 B2 C3b C4`, C3b as "before")

```
width_inf  reindex_ns    ratio=0.846  predicted [0.00, 0.75]  FINDING
width_inf  drain_p95_ns  ratio=0.569  predicted [0.00, 0.75]  PASS
width_inf  drain_p99_ns  ratio=0.603  predicted [0.00, 0.75]  PASS
width_40   reindex_ns    ratio=0.650  predicted [0.45, 0.95]  PASS
width_40   drain_p95_ns  ratio=0.812  predicted [0.45, 0.95]  PASS
width_40   drain_p99_ns  ratio=0.780  predicted [0.45, 0.95]  PASS
width_10   reindex_ns    ratio=0.980  predicted [0.70, 1.02]  PASS
width_10   drain_p95_ns  ratio=0.976  predicted [0.70, 1.02]  PASS
width_10   drain_p99_ns  ratio=0.985  predicted [0.70, 1.02]  PASS
reindex_ns               order inf<40<10<1: 0.846 < 0.650 < 0.980  FINDING
width_10   compute_p95_ns ratio=1.042  noise floor x1.15  PASS (flat)
width_10   compute_p99_ns ratio=1.111  noise floor x1.15  PASS (flat)
width_10   checksum IDENTICAL
drain_p95_ns             order inf<40<10<1: 0.569 < 0.812 < 0.976  PASS
width_10   compute_p95_ns ratio=1.042  noise floor x1.15  PASS (flat)
width_10   compute_p99_ns ratio=1.111  noise floor x1.15  PASS (flat)
width_10   checksum IDENTICAL
drain_p99_ns             order inf<40<10<1: 0.603 < 0.780 < 0.985  PASS
width_10   compute_p95_ns ratio=1.042  noise floor x1.15  PASS (flat)
width_10   compute_p99_ns ratio=1.111  noise floor x1.15  PASS (flat)
width_10   checksum IDENTICAL
```

### The `predict.py` script bug (the plan's script, not the implementer's)

`/tmp/slice55a-predict.py`'s `compute_*` and `checksum` checks are indented **inside** the
band loop's trailing `for k in (…)` passes while the scenario variable `sc` is never rebound
there, so `sc` stays at whatever the bands loop last assigned — `width_10`, the last key. The
nine `compute_*`/`checksum` lines in each run are therefore `width_10` evaluated **three
times**, never `width_inf` or `width_40`. Because of that, the `compute_*` ratios for all
three widths and the checksums for all three widths are given below straight from
`compare.py`.

### `compute_*` at all three widths, from `compare.py` (Decision 12's flatness claim)

Tolerance per token/width is the plan's `tol = max(B1/B2 spread on that token, 1.15)`, where
`spread = max(B1, B2) / min(B1, B2)`:

| width | token | B1 | B2 | spread | tol |
|---|---|---|---|---|---|
| inf | `compute_p95_ns` | 95 | 81 | 1.173 | 1.173 |
| inf | `compute_p99_ns` | 183 | 126 | 1.452 | 1.452 |
| 40 | `compute_p95_ns` | 83 | 81 | 1.025 | 1.150 |
| 40 | `compute_p99_ns` | 143 | 118 | 1.212 | 1.212 |
| 10 | `compute_p95_ns` | 87 | 87 | 1.000 | 1.150 |
| 10 | `compute_p99_ns` | 153 | 156 | 1.020 | 1.150 |

**C4 vs C3b**:

| width | token | C3b | C4 | ratio | tol | verdict |
|---|---|---|---|---|---|---|
| inf | `compute_p95_ns` | 68 | 140 | 2.059 | 1.173 | **FINDING** |
| inf | `compute_p99_ns` | 81 | 187 | 2.309 | 1.452 | **FINDING** |
| 40 | `compute_p95_ns` | 71 | 78 | 1.099 | 1.150 | PASS (flat) |
| 40 | `compute_p99_ns` | 85 | 101 | 1.188 | 1.212 | PASS (flat) |
| 10 | `compute_p95_ns` | 71 | 74 | 1.042 | 1.150 | PASS (flat) |
| 10 | `compute_p99_ns` | 90 | 100 | 1.111 | 1.150 | PASS (flat) |

**C4 vs C3**:

| width | token | C3 | C4 | ratio | tol | verdict |
|---|---|---|---|---|---|---|
| inf | `compute_p95_ns` | 132 | 140 | 1.061 | 1.173 | PASS (flat) |
| inf | `compute_p99_ns` | 212 | 187 | 0.882 | 1.452 | PASS (flat) |
| 40 | `compute_p95_ns` | 106 | 78 | 0.736 | 1.150 | **FINDING** |
| 40 | `compute_p99_ns` | 180 | 101 | 0.561 | 1.212 | **FINDING** |
| 10 | `compute_p95_ns` | 105 | 74 | 0.705 | 1.150 | **FINDING** |
| 10 | `compute_p99_ns` | 180 | 100 | 0.556 | 1.150 | **FINDING** |

Checksums from both `compare.py` runs: `width_inf`, `width_40`, `width_10` all IDENTICAL
against **both** C3 and C3b.

### Every FINDING line, reproduced with what was found

1. `width_10 drain_p99_ns ratio=0.550 predicted [0.70, 1.02] FINDING` (RUN 1) — drain p99 at
   width 10 fell further below the predicted floor than the band allowed, against the C3
   baseline.
2. `width_10 compute_p95_ns ratio=0.705 noise floor x1.15 FINDING` (RUN 1, printed 3×) —
   compute p95 at width 10 moved outside the flatness tolerance against C3.
3. `width_10 compute_p99_ns ratio=0.556 noise floor x1.15 FINDING` (RUN 1, printed 3×) — the
   same for compute p99 at width 10.
4. `width_inf reindex_ns ratio=0.846 predicted [0.00, 0.75] FINDING` (RUN 2) — against the
   cleaner C3b baseline, reindex at width ∞ fell by only ~15%, less than the predicted
   quarter-or-more drop.
5. `reindex_ns order inf<40<10<1: 0.846 < 0.650 < 0.980 FINDING` (RUN 2) — the predicted
   cross-width ordering is **broken**: width ∞ (0.846) is not the smallest; width 40 (0.650)
   fell further than width ∞ did.
6. `C4 vs C3b: width_inf compute_p95_ns 2.059` and `compute_p99_ns 2.309`, both above their
   tolerances (1.173, 1.452) — compute at width ∞ moved, against a path this slice does not
   touch.
7. `C4 vs C3: width_40 compute_p95_ns 0.736`, `compute_p99_ns 0.561`, `width_10
   compute_p95_ns 0.705`, `compute_p99_ns 0.556`, all below their tolerances — the same
   untouched path moving in the opposite direction against the other baseline.
8. The C1, C3 and C5 per-column findings listed above (five ratios outside the spread in C1,
   fourteen of fifteen in C3, five in C5).

**How this reads against AC17.** `drain_*` is the token family the short-circuit is supposed
to move, and against the supplementary C3b column it falls at **every** width in the
predicted order — 0.569/0.603 (∞) < 0.812/0.780 (40) < 0.976/0.985 (10) — every band PASS.
`reindex_ns` also falls at every width against C3b (0.846, 0.650, 0.980) but its ∞/40 order
is **inverted**, and C3b's `width_inf` column is itself the anomalously fast measurement (its
`reindex_ns` is 17.2 M against 35.8 M in C1 and 48.9 M in C3, with no code change between
C3 and C3b). `compute_*` is untouched by every commit in this slice and its ratios carry the
recorded findings above in both directions depending on which baseline is used as the
denominator. The `checksum=` token is byte-identical in all seven columns. Every measurement
here is a single run on a shared host; no band was widened, no run was repeated to obtain a
better number, and no FINDING is recorded as noise without its ratio beside it.

## 5. Drills — nine observed reds

Each drill deletes or perverts exactly one shipped line, observes the red, and reverts with
`git checkout --`. **In Tasks 2, 3 and 5 the drills ran after that task's commit** (the
plan's own `git checkout --` inside each drill would otherwise have reverted the still
uncommitted implementation); the reds are unaffected, and each task re-confirmed green with
a clean tree afterwards.

**(d1)** — `visualRowAt` guard 1 deleted, `testHookAnsweringAboveLineCountIsRejectedNotTrapped`
run alone:

```
EXPECTED RED (d1, trap)
Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range
```

**(f1)** — `DocumentVisualRowCursor.init` guard 4 (`rowInStartLine < 0`) deleted:

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapComputeTests.swift:132: error: -[TextEngineCoreTests.WrapComputeTests testCursorStreamsNothingWhenTheHookMakesRowInLineNegative] : XCTAssertNil failed: "VisualRowGeometry(row: TextEngineCore.VisualRow(logicalLine: 2, rowInLine: 0, startColumn: 0, endColumn: 2, width: 20.0), y: 5.0, height: 5.0)" - a negative rowInStartLine must stream nothing, not trap or restart the line
```

(The predicted shape: without the guard the cursor streams line 2 from row 0 rather than
trapping.)

**(f2)** — `DocumentVisualRowCursor.init` guard 3 (`startLine` range) deleted:

```
Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range
```

**(f3)** — `if k <= 0 { return nil }` removed from `advanceVisualRows`; two observations:

```
direct helper test:
Swift/arm64e-apple-macos.swiftinterface:19659: Fatal error: Range requires lowerBound <= upperBound

cursor test:
EXPECTED GREEN (f3): the producer guard catches it first
```

**(f4)** — `visualRowAt` guard 2 (`rowInLine < 0`) deleted:

```
EXPECTED RED (f4)
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift:162: error: -[TextEngineCoreTests.WrapRowQueryValidationTests testHookMakingRowInLineNegativeIsRejected] : XCTAssertEqual failed: ("row(TextEngineCore.VisualRowLocation(globalRow: 1, logicalLine: 2, rowInLine: -1, clamp: TextEngineCore.LineLocation.Clamp.inRange))") is not equal to ("failure(TextEngineCore.ViewportValidationError.invalidVisualRowLayout)")

EXPECTED GREEN (f4): the boundary is guard 1's
```

**(l)** — the short-circuit predicate inverted (`>=` for `<=`). `WrapPackingTests` reddens on
three cases (lines that should wrap collapse to one row, because the inverted predicate fires
on the **first** row instead of the last), and both `∞` oracles stay green — they hold only
fitting lines, on which the two predicates agree:

```
EXPECTED RED (l): WrapPackingTests
WrapPackingTests.swift:10: testGreedyBreaksAtLastFittingOpportunity : XCTAssertEqual failed: ("[…endColumn: 4, width: 40.0)]") is not equal to ("[…endColumn: 2, width: 20.0), …(rowInLine: 1, startColumn: 2, endColumn: 4, width: 20.0)]")
WrapPackingTests.swift:21: testBreakOnlyAtDeclaredOpportunities : XCTAssertEqual failed: ("[…endColumn: 4, width: 40.0)]") is not equal to ("[…endColumn: 2, width: 20.0), …(rowInLine: 1, startColumn: 2, endColumn: 4, width: 20.0)]")
WrapPackingTests.swift:38: testCharWrapOneCellPerRow : XCTAssertEqual failed: ("[…endColumn: 3, width: 30.0)]") is not equal to ("[…endColumn: 1, …), …(rowInLine: 1, …), …(rowInLine: 2, …)]")
EXPECTED GREEN (l): VisualRowEquivalenceTests -- an ∞ oracle cannot see the predicate's shape
EXPECTED GREEN (l): WrapComputeEquivalenceTests -- an ∞ oracle cannot see the predicate's shape
```

**(m)** — the predicate narrowed to the first row only (`start == 0`). Every result-bearing
suite is blind to the narrowing; **only** the last-row probe-count pin catches it:

```
EXPECTED GREEN (m): WrapPackingTests -- results unchanged
EXPECTED GREEN (m): VisualRowEquivalenceTests -- results unchanged
EXPECTED GREEN (m): WrapComputeEquivalenceTests -- results unchanged
EXPECTED GREEN (m): the fitting-line case cannot see a start == 0 narrowing
EXPECTED RED (m): the last-row pin is the only test that reads this
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPackingCountTests.swift:75: error: -[TextEngineCoreTests.WrapPackingCountTests testLastRowOfAWrappedLineAddsNoScan] : XCTAssertEqual failed: ("3") is not equal to ("0") - the last row of a wrapped line must not scan -- its suffix fits
reverted
```

**D-24, site 1** — `visualRowAt`'s `layout.logicalLine(containingVisualRow: globalRow)`
replaced with a direct `binarySearchLogicalLine(...)` call. All three dispatch tests failed;
the two lines below are from `/tmp/slice55a-drill-d24-query.txt`:

```
VisualRowDispatchTests.swift:31: testVisualRowAtDispatchesThroughTheHookExactlyOnce : XCTAssertEqual failed: ("[]") is not equal to ("[5]") - one dispatch, with the located global row
VisualRowDispatchTests.swift:44: testClampedVisualRowAtStillDispatchesThroughTheHook : XCTAssertEqual failed: ("[]") is not equal to ("[0]") - y=-1.0: the clamped edge dispatches once
VisualRowDispatchTests.swift:44: testClampedVisualRowAtStillDispatchesThroughTheHook : XCTAssertEqual failed: ("[]") is not equal to ("[7]") - y=1000.0: the clamped edge dispatches once
```

**D-24, site 2** — `DocumentVisualRowCursor`'s
`layout.logicalLine(containingVisualRow: range.bufferStart)` replaced the same way:

```
EXPECTED RED (D-24, cursor)
VisualRowDispatchTests.swift:58: testDocumentCursorDispatchesThroughTheHookOnceForTheBufferStart : XCTAssertEqual failed: ("[]") is not equal to ("[5]") - one dispatch for the buffer start; the stream itself never searches
reverted
```

**D-29** — a `ViewportVirtualizer.compute(...)` call inserted as the first statement of
`drainVisualRows`:

```
EXPECTED RED (D-29)
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift:56: error: -[ViewportBenchmarksTests.WrapComputeDrainTests testDrainBodyPerformsNoCompute] : XCTAssertEqual failed: ("1") is not equal to ("0") - the drain body must not compute a range
```

### Red-first evidence for commit 4 — `WrapPackingCountTests` on the shipped packer

Before the `greedyEnd` short-circuit existed, the two new probe-count pins failed with the
three predicted numbers (7 vs 0, 12 vs 4, 3 vs 0):

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPackingCountTests.swift:46: error: -[TextEngineCoreTests.WrapPackingCountTests testFittingLinePacksWithoutScanning] : XCTAssertEqual failed: ("7") is not equal to ("0") - a line that fits must not scan its break opportunities
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPackingCountTests.swift:49: error: -[TextEngineCoreTests.WrapPackingCountTests testFittingLinePacksWithoutScanning] : XCTAssertEqual failed: ("12") is not equal to ("4") - next() on a fitting line reads start and end, and nothing else
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapPackingCountTests.swift:75: error: -[TextEngineCoreTests.WrapPackingCountTests testLastRowOfAWrappedLineAddsNoScan] : XCTAssertEqual failed: ("3") is not equal to ("0") - the last row of a wrapped line must not scan -- its suffix fits
```

### Plan-assertion defect #2 (D-2 class) — Task 6's `REVERTED TOO FAR` check is inverted

Task 6 Step 3's post-drill check
(`git diff --quiet … && echo "REVERTED TOO FAR — Step 2's extraction is gone"`) assumes the
pre-commit ordering, where the index still holds the un-extracted content. Under the brief's
own commit-first alternative the checkout resyncs the working tree to the index, so the diff
is **always** quiet and the message always fires — a false alarm. It printed
`REVERTED TOO FAR — Step 2's extraction is gone; redo Step 2`, and the true state was
verified directly instead: `rg -n "func drainVisualRows"
Sources/ViewportBenchmarks/WrapComputeBenchmark.swift` hit at line 107, the drill line was
absent, `git status --short` was empty, and the file diffed clean against `c384f7b`.

## 6. Gates, checksums, memory shape, Foundation, `--wrap-row-query`

Final full check at HEAD `58b78f4` — the last commit on this branch that carries shipped
Swift; every later commit is documentation (the one exception is a comment-only line in
`WrapPackingCountTests.swift`, `d977248`, which changes no behaviour). Re-run at `d977248`
during the pre-merge validation pass, the same numbers held: `Executed 425 tests, with 0
failures`, release build green, Foundation scan empty, 46 `gate=pass` / 0 `gate=fail`, the
46-tuple checksum diff against the hosted baseline of §7 **empty**, `--wrap-compute`
`181094400 / 143365120 / 115068800` and all four `--wrap-row-query` checksums unchanged,
`--memory-shape` five times `invariant=pass`, and drill (m) reproduced with exactly one red
(`testLastRowOfAWrappedLineAddsNoScan`, `3 != 0`) out of 425.

```
suite green
	 Executed 425 tests, with 0 failures (0 unexpected) in 8.292 (8.319) seconds
release build green
PASS: Foundation-free
gate=pass lines: 46 (expect 46)
gate=fail lines: 0 (expect 0)
PASS: 46 gated checksums byte-identical to the pre-branch baseline (AC13)
memory-shape: invariant=pass
PASS: wrap_row_query checksums byte-identical
cross-target self-test pass
```

425 = the pre-branch baseline 408 + 17 (2 + 5 + 4 + 2 + 1 + 3). The twelve gated modes
(default pipeline plus `--variable-height`, `--variable-height-mutation`,
`--structural-mutation`, `--bulk-structural-mutation`, `--line-query`,
`--line-geometry-query`, `--column-query`, `--column-geometry-query`, `--point-query`,
`--point-geometry-query`, `--realistic-provider`) were each run once with `--gate`,
appending to one file; no mode was skipped and none was run twice into it. The 46-tuple
`diff` against `/tmp/slice55a-checksums-baseline.tsv` (taken at the branch point, before
commit 0) is **empty**.

`--wrap-row-query`, final run, all four checksums equal to the pre-branch baseline:

```
mode=wrap_row_query scenario=uniform_1k total_rows=1000 query_operations_per_sample=256 query_p95_ns=64 query_p99_ns=79 checksum=20459520000
mode=wrap_row_query scenario=uniform_100k total_rows=100000 query_operations_per_sample=256 query_p95_ns=228 query_p99_ns=256 checksum=2047976320000
mode=wrap_row_query scenario=narrow_100k total_rows=400000 query_operations_per_sample=256 query_p95_ns=239 query_p99_ns=270 checksum=2240234540000
mode=wrap_row_query scenario=clamped_100k total_rows=400000 query_operations_per_sample=256 query_p95_ns=31 query_p99_ns=37 checksum=2240231040000
```

`--memory-shape`, all five scenarios `invariant=pass` with `core_owned_bytes` 74/74/74/90/90
at line counts 100 000 / 1 000 000 / 100 000 / 100 000 / 1 000 000 — flat in the document
size, as the invariant requires.

The `cross-target-compile.sh --self-test` pass is shell-logic evidence only: it compiles
nothing. The portability evidence is the two hosted jobs in §7.

## 7. Hosted proof (step level)

### PR-head run

PR **#132** (`slice-55a-wrap-trap-repairs` -> `main`), workflow run
**33192269902**, read at **step** level — a green job can hide a dead step.

**Which run covers what.** The branch produced more than one PR-head run, because
documentation commits landed after the code did, and a record naming only the first would
send a reader to a run that is no longer the head. The full inventory, every one `success`
at job level:

| run | head | what it adds |
|---|---|---|
| `33192269902` | `be0752d` | **the run read at step level below** — `be0752d` is the last commit carrying shipped Swift, so this run covers 100 % of the slice's code |
| `33192988425` | `624b4d8` | docs only (this record's hosted-proof section) |
| `33195156738` | `d977248` | docs, plus one comment-only line in `WrapPackingCountTests.swift` |
| — | the pre-merge fix commit | its run id and the post-merge `push` run are recorded together in **Post-merge push run** below; a record cannot name the run of the commit that contains it |

The step-level read is done on `33192269902` and not repeated for the docs runs: they
compile and test the same Swift, and the checksum tuples at the end of this section were
re-derived locally at `d977248` with an empty diff (§6), which is the property the step
read exists to establish.

Three jobs, all `success`:

```
WASM cross-target compile: success
Host tests and benchmark gate: success
iOS cross-target compile: success
```

Counts over the run log:

```
run=33192269902
gate=pass lines: 46 (expect 46)
gate=fail lines: 0 (expect 0)
Host tests and benchmark gate	Run host tests	2026-08-28T16:56:43.2477044Z 	 Executed 425 tests, with 0 failures (0 unexpected) in 9.833 (9.833) seconds
hosted checksum tuples: 46 (expect 46)
```

The hosted `Executed 425 tests, with 0 failures` matches the local count exactly. All 46
`gate=pass` lines come from the **Host tests and benchmark gate** job, distributed across
the twelve gate steps — and no mode's summary is printed by more than one step, so the
"exactly one CI step may print a given mode's summary lines" rule holds and a future
harvest of this run cannot double-weight any scenario:

```
   3 Run synthetic benchmark gate
   3 Run variable-height benchmark gate
   3 Run variable-height mutation benchmark gate
   3 Run structural mutation benchmark gate
   5 Run bulk structural mutation benchmark gate
   5 Run line query benchmark gate
   5 Run line geometry query benchmark gate
   5 Run column query benchmark gate
   5 Run column geometry query benchmark gate
   4 Run point query benchmark gate
   4 Run point geometry query benchmark gate
   1 Run realistic provider benchmark gate
```

Every step of every job concluded `success` (the docs-only detector correctly declined this
PR: `Complete docs-only PR: skipped` in all three jobs, so all three ran the heavy path):

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
iOS cross-target compile | 3 Detect PR change scope: success
iOS cross-target compile | 4 Complete docs-only PR: skipped
iOS cross-target compile | 5 Show toolchain: success
iOS cross-target compile | 6 Compile cross-target packages for iOS: success
WASM cross-target compile | 4 Detect PR change scope: success
WASM cross-target compile | 5 Complete docs-only PR: skipped
WASM cross-target compile | 6 Show toolchain: success
WASM cross-target compile | 7 Compile cross-target packages for WASM: success
```

**The WASM job's four `result=pass … blocking=true` lines** (two kinds x two packages), and
the iOS job's own four (two targets x two packages) — the portability evidence the
`--self-test` in §6 cannot give:

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

### Plan-assertion defect #3 (D-2 class) — the "WASM blocking lines" count is not job-scoped

The plan's check
`echo "WASM blocking lines: $(grep -c 'result=pass.*blocking=true' <run.log>) (expect 4)"`
greps the **whole run** log, which carries the iOS job's four blocking lines as well as the
WASM job's four, so it printed `8` where the plan expected `4`. This is a mislabelled
counter, not a failure: scoped to the WASM job the count is exactly the four
`wasm`/`wasm_embedded` x `core`/`providers` lines AGENTS.md specifies, and the four extra
lines are the iOS job's own blocking compiles, which are equally required. Both sets are
reproduced verbatim above so the number is read rather than inferred. The scoped commands
are:

```bash
awk -F'\t' '$1=="WASM cross-target compile" && /result=pass.*blocking=true/' <run.log> | wc -l   # 4
awk -F'\t' '$1=="iOS cross-target compile"  && /result=pass.*blocking=true/' <run.log> | wc -l   # 4
```

### The 46 hosted checksum tuples — 55b's hosted baseline

No recent verification record holds the hosted 46 tuples, so per the plan's fallback they
are recorded here in full for 55b to diff against. Extracted with the D-18 `grep -v` filter
(`mode=memory_shape`, `mode=memory_observation` removed — a hosted log carries five and
three of those respectively, and it is that filter that makes the count 46 and the diff
meaningful):

```
bulk_structural_mutation|100k_lines_batch_4096	2285022074625
bulk_structural_mutation|100k_lines_batch_64	36564666309410
bulk_structural_mutation|1k_lines_batch_64	82740062444
bulk_structural_mutation|1m_lines_batch_4096	82203678997143
bulk_structural_mutation|1m_lines_batch_64	1317343499882000
column_geometry_query|prefixsum_100k	223985600000
column_geometry_query|prefixsum_1m	839521520640
column_geometry_query|uniform_100k	267505512960
column_geometry_query|uniform_1k	160641440000
column_geometry_query|uniform_1m	799841600000
column_query|prefixsum_100k	63985600000
column_query|prefixsum_1m	639841560320
column_query|uniform_100k	63985556480
column_query|uniform_1k	641440000
column_query|uniform_1m	639841600000
line_geometry_query|balanced_tree_100k	223985600000
line_geometry_query|balanced_tree_1m	852321495040
line_geometry_query|uniform_100k	267505512960
line_geometry_query|uniform_1k	160641440000
line_geometry_query|uniform_1m	799841600000
line_query|balanced_tree_100k	63985600000
line_query|balanced_tree_1m	639841547520
line_query|uniform_100k	63985556480
line_query|uniform_1k	641440000
line_query|uniform_1m	639841600000
pipeline|100k_lines_80_visible_overscan_5	570448232307200
pipeline|1k_lines_20_visible_overscan_0	1319670707200
pipeline|1m_lines_200_visible_overscan_50	18852477646272000
point_geometry_query|prefixsum_100k	1712152282485110528
point_geometry_query|prefixsum_1m	5915921755926273280
point_geometry_query|uniform_100k	4687694617200924928
point_geometry_query|uniform_1m	6036755761047907072
point_query|prefixsum_100k	64166280960
point_query|prefixsum_1m	640022228480
point_query|uniform_100k	64166237440
point_query|uniform_1m	640022280960
realistic_provider|100k_lines_10mb_text	756321289736960
structural_mutation|100k_lines_80_visible_overscan_5	89494497658324
structural_mutation|1k_lines_20_visible_overscan_0	200106952336
structural_mutation|1m_lines_200_visible_overscan_50	3379593298396981
variable_height_mutation|100k_lines_80_visible_overscan_5	88324286099072
variable_height_mutation|1k_lines_20_visible_overscan_0	196866548667
variable_height_mutation|1m_lines_200_visible_overscan_50	3571078666132451
variable_height|100k_lines_80_visible_overscan_5	101209179008000
variable_height|1k_lines_20_visible_overscan_0	231017730560
variable_height|1m_lines_200_visible_overscan_50	3536425156727040
```

They are **byte-identical to the 46 local tuples** of §6 (`diff` empty), which is the
stronger form of the expected result: different hardware changes timings, not checksums.

### Post-merge push run

**Filled after merge** — the user merges the PR; the post-merge `push` run on `main` is then
read at step level, its counts appended here, and its 46 checksum tuples diffed against the
PR-head tuples recorded above.


## 8. Pre-merge validation pass (2026-09-02)

The branch was re-validated against this record before merge — every claim above re-run
rather than re-read (§6 carries the numbers). Five documentation defects were found and
repaired in the commit that carries this section; none touched shipped behaviour, and the
46 gated checksums, both wrap modes' checksums and the suite count are unchanged by them:

1. **§7 named one PR-head run while the branch had three.** Repaired by the inventory table
   in §7 — the step-level read stays on `33192269902` (the run covering every Swift commit)
   and the two later docs runs are named with what each adds.
2. **§6 read as though `58b78f4` were the head.** Repaired: it now says which commits come
   after it and why they change nothing, and carries the `d977248` re-run.
3. **`AGENTS.md`'s `visualRowAt` paragraph over-read its own guards.** It said the query
   answers `.failure(.invalidVisualRowLayout)` "instead of trapping or naming a row that
   does not exist"; the parenthetical scoped that to the two *guarded* answers, but a
   reader takes the sentence whole — and the **third** malformed answer (a line whose
   `firstVisualRow` sits *below* the row's own line) still returns a `.row` naming a row
   that does not exist in that line. Spec Goal 6 states the exemption; `AGENTS.md` now does
   too. The code comment at `WrapPositionQuery.swift:53-55` already did.
4. **`AGENTS.md` still claimed `Tests/ViewportBenchmarksTests` holds "five files".** It
   holds thirteen, and this slice added the thirteenth. The spec assigns this repair to
   55b's Documentation Updates as pre-existing drift; it is taken **here** instead, because
   55a is the slice that made the number wronger and 55a's own Documentation Updates
   preamble is the rule being broken ("a shipped claim that is wrong in the tree between
   two merges is the drift this document exists to prevent"). Repaired as 55b's bullet
   prescribes — the head-count is dropped, not corrected, since every slice that adds a
   test file falsifies it. **55b's Documentation Updates bullet for this item is therefore
   already discharged**; 55b's record should say so rather than re-doing it.
5. **The plan's drill arithmetic said "nine of nineteen".** Eighteen lettered drills plus
   D-24's and D-29's is twenty; 55a's nine and 55b's twelve sum to twenty-one because both
   run `(d1)`. Corrected in the plan.

Two ledger rows were opened by the same pass, both P3, neither a defect in the shipped
code: **D-31** — `--wrap-compute`'s local columns cannot resolve an effect below this
host's own state variance (two measurements of `0235e73` differ by up to 2.84x; a third at
`d977248` reads `width_inf reindex_ns` 5 927 042 against C5's 11 923 958), which is what
made §4's `reindex_ns` ordering and `compute_*` flatness read as findings, and which node 6
must confront before promoting a wrap mode through `harvest -> derive`. **D-32** —
`advanceVisualRows`' *rule* is pinned but its *call site* is not: reverting
`DocumentVisualRowCursor.init` to the inline `for _ in 0..<rowInStartLine` loop leaves all
425 tests green, because with guard 4 live the two forms are behaviourally identical.
Scheduled to 55b, where a second caller makes the property observable.

## 9. Standing notes for 55b and the review

- 55b compares its `--wrap-compute` run against column **C5**.
- D-17 escalates at this piece's review; D-27 goes into its Candidate options (spec, Scope).
- The overriding conformer (`OverridingLogicalLineLayout`) is 55b's second count fixture.
- **D-32 is scheduled to 55b** and it is not new apparatus: the round-trip test AC8 already
  requires discharges it, *provided* both sides are driven through `advanceVisualRows`.
  Say so in 55b's record rather than leaving it implicit (§8).
- **55b's `AGENTS.md` "five files" bullet is already done** — taken in 55a's pre-merge pass
  (§8), by dropping the head-count as that bullet prescribes. 55b re-states it as discharged;
  it does not re-do it.
- **D-31 is node 6's problem, not 55b's**, but 55b runs `--wrap-compute` once against C5 and
  calls a movement a finding — read that comparison against D-31's measured 2.84x host
  spread before filing anything as a regression.
- The spec's narrative lines 778, 810, 872, 1602 and 1810 still say "last row … O(1)"
  **without** the overflow qualifier. `f143e96` added it at six normative sites (four
  in-repo sites plus spec lines 305 and 1408); this slice's final-review follow-up added it
  at the two remaining prescriptive spec sites, 770 (Decision 12's cost table) and 1008–1009
  (55b's Component Design cost model), for eight normative sites qualified in total. Four of
  the five narrative lines sit in the decision log and one in AC17's drill-(m) description;
  all five are historical prose rather than live claims, and remain deliberately untouched.
