# Slice 57 — wrap memory shape — verification record

- **Spec:** [`docs/superpowers/specs/2026-09-04-wrap-memory-shape-design.md`](../specs/2026-09-04-wrap-memory-shape-design.md)
- **Plan:** [`docs/superpowers/plans/2026-09-04-wrap-memory-shape.md`](../plans/2026-09-04-wrap-memory-shape.md)
- **Branch:** `slice-57-wrap-memory-shape`, forked from `2e798a3` (merge of PR #140,
  slice 56's post-slice review).
- **Map node:** wrap arc node 5. **Criterion:** 2.

## 0. Commits, by SHA — not "the current HEAD"

Per `AGENTS.md`'s "A record cannot carry facts about its own branch" (D-37): the commits
below are named **by full SHA**, oldest first, and the list is **open at the end**. A row
named by SHA cannot be falsified by a later commit; a *total* can, so no bare commit count
is asserted anywhere in this document and no commit is called "the current HEAD". Re-derive
the list with:

```bash
git log --format='%H %s' --reverse 2e798a3..HEAD
```

| # | SHA (full) | Subject | Task |
|---|---|---|---|
| 1 | `6ebe61a50d898f57ac6d80d027dea60238589fed` | docs: slice 57 design — wrap memory shape, D-45, and nine fold-ins | — |
| 2 | `0b43c7a8c6b38e4008c861f94e60f4af34d498e1` | docs: slice 57 spec — review fixes, D-46, and two more vacuous measurements | — |
| 3 | `659bf2e22d17ac191fd20653332cb12e87e9d584` | docs: slice 57 plan — nine tasks, twenty-four guarantees, twenty-three drills | — |
| 4 | `b1a4ff9175efe9b6042d24cd8354d4ab23978f4f` | feat: CountingWrapLayout and CountingLineMetrics, with probe attribution | 1 |
| 5 | `f1bc828796da6da51df6a73175bd7c4595f0e958` | feat: the wrap half of --memory-shape, six scenarios over four entry points | 2 |
| 6 | `077b0e77a3eab2cc22d7962794ea9dbe273a90fc` | docs: amend spec 4B - a wrap scenario has no third traversal | 3 |
| 7 | `3856003275f934ac88183f8860f6a3af66076cbc` | fix: D-45 - a declared expectation, and a touched_lines that is counted | 3 |
| 8 | `68e9358071fc6bf9ef5d5ac903e1beb48379f0a9` | test: fix round 1 drills (l) and (n) - fixture isolation for the pair check | 3 |
| 9 | `bf75379df7d9b1613d932d2eadeeb2b67cbbe011` | test: pin compute's constant layout probes and the drain's independence from lineCount | 4 |
| 10 | `8d848fb06878ac876143003ff4602f0d77118a8f` | test: fix round 1 for task 4 - separate the wrapped/unwrapped regimes in the drain probe-count pin | 4 |
| 11 | `f9d19325f9513e00adc289be6eabf4318d6113c5` | ci: D-43 - the plan linter runs its own self-test on every PR | 5 |
| 12 | `3bd409f2f7551a5d29c5ba1510965332b64987c2` | test: D-19/D-20/D-21/D-38 - scrollFrame vocabulary, both class arms, one derived constant | 6 |
| 13 | `ce4bd55b6c4b1ae2faa89de4f2402eb44d3f48dc` | docs: fix D-19 rot in the absoluteCeiling comment (fix round 3) | 6 |
| 14 | `48bde6c4b6d1c150a0fb46ba89b748fb164588d0` | docs: D-10 superseded banner; test: D-11 pins the workflow job set | 7 |
| 15 | `a8947ad827193a27da0b5322519e75c78b793402` | docs: move jobLines comment back down, fix stale one-place clause | 7 |
| 16 | `404feb86c1ca2cb3c4ef965385834b4ec4936b0f` | ci: D-14 coverage partition in three scripts; D-15 falsified (reverted) | 8 |

Rows 1–3 are the paper trail written before implementation; rows 4–16 are the
implementation, and every measurement in this document was taken on the tree at row 16 or
later. The commit carrying **this record** is not named here, for exactly the reason the
section exists — it cannot name itself, and the next commit would falsify a total. §9 is
reserved for the hosted runs, which likewise cannot be named by the commit that creates
their section.

Two commits in the table are amendments in place rather than additions (recorded because
the SHAs in the implementers' own reports differ from the ones above): row 4 amends
`8f082d2` (Task 1's fix round closed a hole in the same step's test file before anything
depended on the SHA), and row 16 amends `81c9724` (Task 8's fix round reverted the D-15
edits inside the same task).

## 1. Scope recap

Three things, in the order the spec makes load-bearing:

1. **The spine.** `--memory-shape` — already a **blocking** step in the host CI job — gained
   a **wrap half**: six scenarios, `{100k, 1M} x {inf, 40, 10}`, each running
   `compute(_:layout:)`, the `DocumentVisualRowCursor` drain, `visualRowAt` and
   `visualPointAt` through a `CountingWrapLayout` that counts all six
   `VisualRowLayoutSource` hooks. The observable is **provider probes, not bytes**: every
   wrap entry point returns fixed-size values, so a `MemoryLayout` sum reports a pointer for
   exactly the case that matters (spec §2, Decision 1). Node 1's per-line `visualRows` is
   covered transitively through the drain, not by a scenario of its own.
2. **The repair (D-45).** Two vacuous measurements in the mode's existing fixed/variable
   half: a cross-scenario comparison that compared a constant with itself (and skipped
   `large_text` entirely), and a `touched_lines` column that was an *assignment* of
   `buffered_lines` rather than a count.
3. **The fold-ins.** Of the nine rows the spec listed, **eight are discharged** — D-43 (P2)
   and D-10, D-11, D-14, D-19, D-20, D-21, D-38 (P3) — and the ninth, **D-15, is falsified
   rather than discharged** (§7.1): its prescribed remedy was implemented, measured to
   produce the exact failure the row exists to prevent, and reverted. Two rows are born here:
   **D-45** (opened and discharged in the same slice) and **D-46** (`accepted-risk`), plus
   **D-47** carrying D-15's falsification evidence.

Nothing measured moves: no core source, no budget literal, no corpus row, no gated
checksum, no wrap-mode checksum (§5).

## 2. Per-task record

Each task's transcript is drawn from the implementer's own report
(`.superpowers/sdd/2026-09-04-wrap-memory-shape/task-N-report.md` — gitignored, so
transcribed here rather than linked). Every drill's **recorded red is quoted verbatim**.

### Task 1 — `CountingWrapLayout`, `CountingLineMetrics`, and the measurement (commit `b1a4ff9`)

Adds `Sources/ViewportBenchmarks/CountingWrapLayout.swift`: `WrapProbeCounter`,
`CountingWrapLayout<Base>`, a private `DefaultLogicalLineProbe<Inner>`, `LineProbeCounter`,
`CountingLineMetrics<Base>`. `WrapComputeDrainTests`'s private `ProbeCounter`/`CountingLayout`
were deleted and that test rewritten onto the shared types.

Red first, as specified — `swift test --filter CountingWrapLayoutTests` failed to compile
with exactly the four predicted errors:

```
error: cannot find 'WrapProbeCounter' in scope
error: cannot find 'CountingWrapLayout' in scope
error: cannot find 'LineProbeCounter' in scope
error: cannot find 'CountingLineMetrics' in scope
```

Green after implementation: `CountingWrapLayoutTests` 4/0, `WrapComputeDrainTests` 1/0,
whole suite **501/0** (497 baseline + 4).

#### Drill (a) — G8 — delete `counter.canBreak += 1`

```
CountingWrapLayoutTests.swift:56: error: -[...testEveryHookIsCounted] :
XCTAssertGreaterThan failed: ("0") is not greater than ("0") - the packer reads canBreak
```

Only that assertion failed; the `total` identity further down the same test was reached and
passed — the missing increment reads as "the core never called it", which is precisely the
failure mode G8 exists to name.

#### Drill (a2) — G8 — delete `counter.visualRowCount += 1` (added in fix round 1)

```
CountingWrapLayoutTests.swift:62: error: -[ViewportBenchmarksTests.CountingWrapLayoutTests testEveryHookIsCounted] :
XCTAssertEqual failed: ("0") is not equal to ("1") - the hook increments its own counter
```

The same deletion was confirmed **green** before the witness was added (`swift test --filter
CountingWrapLayoutTests` → 4 tests, 0 failures), so the drill records both polarities. See
§7.2 for why this drill exists at all.

#### Drill (b) — G19 — `if line == base.lineCount` → `if false`

```
CountingWrapLayoutTests.swift:73: error: -[...testFirstVisualRowAtLineCountIsCountedSeparately] :
XCTAssertGreaterThan failed: ("0") is not greater than ("0") - compute reads totalRows via firstVisualRow(ofLine: lineCount)

WrapComputeDrainTests.swift:26: error: -[...testDrainBodyPerformsNoCompute] :
XCTAssertGreaterThan failed: ("0") is not greater than ("0") - compute must probe firstVisualRow(ofLine: lineCount), or the zero below is vacuous
```

#### Drill (c) — G22 — forward `logicalLine` to `base` instead of routing it through `DefaultLogicalLineProbe`

```
CountingWrapLayoutTests.swift:105: error: -[...testTheDefaultLogicalLineSearchIsAttributedToTheCounter] :
XCTAssertGreaterThanOrEqual failed: ("1") is less than ("6") - the default logicalLine search
over 64 lines costs ~log2(64) firstVisualRow probes and they must land in this counter, not
in the unwrapped base
```

Measured **1** where ~6 are spent. This is the load-bearing drill of the task: without the
routing, every count in the mode would silently understate its dominant O(log N) term while
every other assertion stayed green. The task reviewer reproduced it independently and
confirmed that the forwarding version leaves **both** other tests green — so the attribution
argument holds as written, and nothing else in the suite covers it.

All three source drills restored byte-identically (`git diff --quiet --
Sources/ViewportBenchmarks/CountingWrapLayout.swift` → `restored=clean` after each).

### Task 2 — the six wrap scenarios and their per-scenario invariants (commit `f1bc828`)

Adds `Sources/ViewportBenchmarks/WrapMemoryShapeDiagnostics.swift` (scenarios,
`WrapMemoryShapeSummary`, `wrapCoreOwnedBytesEstimate()`, `runWrapMemoryShapeScenario`,
`formatWrapMemoryShapeSummary`) and `Tests/ViewportBenchmarksTests/WrapMemoryShapeTests.swift`
(six tests), plus the four shared viewport constants in `MemoryShapeDiagnostics.swift` and
the wrap print loop in `runMemoryShapeDiagnostics()`. Red first: `cannot find
'WrapMemoryShapeScenario' in scope` and its three siblings. Whole suite after: **507/0**.

The unit fixture is 1 000 lines throughout — `swift test` builds no 100k- or 1M-line
provider.

#### Drill (d) — G1 — cap the drain at 89 rows

```
WrapMemoryShapeTests.swift:21: ... XCTAssertEqual failed: ("89") is not equal to ("90") - inf: streamed == buffered
WrapMemoryShapeTests.swift:23: ... XCTAssertTrue failed - inf: per-scenario invariants
WrapMemoryShapeTests.swift:21: ... XCTAssertEqual failed: ("89") is not equal to ("90") - 40: streamed == buffered
WrapMemoryShapeTests.swift:23: ... XCTAssertTrue failed - 40: per-scenario invariants
WrapMemoryShapeTests.swift:21: ... XCTAssertEqual failed: ("89") is not equal to ("90") - 10: streamed == buffered
WrapMemoryShapeTests.swift:23: ... XCTAssertTrue failed - 10: per-scenario invariants
```

#### Drill (e) — G13 — the range is ordered and bounded

The plan's perturbation (`lineCount: totalRows - 1`) **did not redden**, and that is a
defect in the drill, not in the code — see §7.3. The superseding perturbation, taken from
the spec's own stronger drill text ("hand the checker a range with `bufferEndExclusive >
totalRows`"), is `memoryShapeRangeIsOrderedAndBounded(range, lineCount: range.bufferEndExclusive - 1)`:

```
WrapMemoryShapeTests.swift:22: error: ... XCTAssertTrue failed - inf: range ordered and bounded
WrapMemoryShapeTests.swift:23: error: ... XCTAssertTrue failed - inf: per-scenario invariants
WrapMemoryShapeTests.swift:22: error: ... XCTAssertTrue failed - 40: range ordered and bounded
WrapMemoryShapeTests.swift:23: error: ... XCTAssertTrue failed - 40: per-scenario invariants
WrapMemoryShapeTests.swift:22: error: ... XCTAssertTrue failed - 10: range ordered and bounded
WrapMemoryShapeTests.swift:23: error: ... XCTAssertTrue failed - 10: per-scenario invariants
```

**Scope note, earned by the finding and recorded rather than glossed:** this drill certifies
that the checker's verdict is genuinely **wired into** `summary.rangeIsOrderedAndBounded`
*and* into `baseInvariantPasses` (hence into the mode's own `invariant=` column) — neither
path is dead and neither swallows a `false`. It does **not** show the upper-bound clause
firing on a real range: it forges the checker's *axis*, not the range. With Decision 9's
mid-document anchor, no perturbation of the fixture's scroll position can manufacture a real
`bufferEndExclusive > totalRows`, because the 90-row window never approaches the document's
edge at any of the six sizes/widths.

#### Drill (f) — G14 — shift the scroll offset by half a row

```
WrapMemoryShapeTests.swift:19: ... XCTAssertEqual failed: ("81") is not equal to ("80") - inf: visible window
WrapMemoryShapeTests.swift:20: ... XCTAssertEqual failed: ("91") is not equal to ("90") - inf: buffered window
WrapMemoryShapeTests.swift:23: ... XCTAssertTrue failed - inf: per-scenario invariants
```

(and the same triple at widths 40 and 10; the buffered-window line is a direct consequence
of `visibleRows` growing by one, not a separate finding).

#### Drill (g) — G5 — drop the `+ 3` from `offsetRow`

```
WrapMemoryShapeTests.swift:33: ... XCTAssertEqual failed: ("0") is not equal to ("1")
WrapMemoryShapeTests.swift:34: ... XCTAssertEqual failed: ("0") is not equal to ("3")
```

Width `inf` stays green, correctly: `pointRowInLine` is 0 there with or without the offset.

#### Drill (h) — G15 — `wrapMemoryShapePointX = 12.0`

```
WrapMemoryShapeTests.swift:43: ... XCTAssertEqual failed: ("right") is not equal to ("none") - 10: x must be in range, or the probe counts compare two branches
```

**One failure line only, and it is at width 10** — which is the argument for a three-width
fixture made concrete: at widths `inf` and 40 the row is wide enough that `x = 12.0` is
still in range, so a single-width fixture would have missed the regression entirely.

#### Drill (i) — G16 — assert `lineCount` instead of `lineCount + 1` prefix entries

```
WrapMemoryShapeTests.swift:56: ... XCTAssertEqual failed: ("8008") is not equal to ("8000") - inf: provider-owned bytes
WrapMemoryShapeTests.swift:56: ... XCTAssertEqual failed: ("8008") is not equal to ("8000") - 40: provider-owned bytes
WrapMemoryShapeTests.swift:56: ... XCTAssertEqual failed: ("8008") is not equal to ("8000") - 10: provider-owned bytes
```

The edit lands in the **test**, not the source: editing the source's `expectedProviderBytes`
would flip `baseInvariantPasses` for all six scenarios and redden a *different* test than
the one the plan names.

### Task 3 — D-45's repair (commits `077b0e7`, `3856003`, `68e9358`)

`077b0e7` amends the spec's §4B on its own, before any code: a wrap scenario contributes
**two** window counts, not three, because it has no third independent traversal and
reporting its streamed rows twice would restate the exact vacuity D-45 removes.

`3856003` ships: `MemoryShapeWindowContribution` and the pure
`memoryShapeComparisonFailures(_:) -> [String]` comparing every contribution's
`bufferedWindow`/`streamedElements` (and `touchedElements` where non-nil) against the
**declared** `expectedMemoryShapeWindow`, never against `contributions.first`;
`wrapMemoryShapeCrossScenarioFailures(_:)` implementing spec invariants 8–12; the
`touched_lines` repair (the variable path's geometry cursor now runs over
`CountingLineMetrics`, and `providerLines` is `probeCounter.distinctLines` intersected with
the buffer range); and `runMemoryShapeDiagnostics()` rewritten to fold both comparison
functions into every line's `invariant=`. Ten new tests
(`MemoryShapeComparisonTests`); whole suite **517/0**.

Three of this task's seven drills did not redden as planned. All three were traced to the
same root cause — the field or index a drill substituted was not the one its paired test
corrupts — and repaired (§7.4). The reds below are the post-repair ones.

#### Drill (j) — G7 — `memoryShapeComparisonFailures` returns `[]` unconditionally

**Three** tests fail, not the four the plan predicted:
`testAWrongWindowFailsOnAnyScenarioIncludingLargeText`,
`testCorruptingTheFirstContributionNamesTheFirstContribution`, and
`testTouchedElementsIsCheckedWhereItExists`, each `[] != [expected]`.
`testAHealthySetHasNoFailures` correctly survives, because its own expectation *is* `[]` and
a function that always returns `[]` satisfies it by construction. The prediction overcounted
by one; the code is right.

#### Drill (k) — G17 — restore the first-of-group idiom (the real one, all three fields)

```
MemoryShapeComparisonTests.swift:61: error: -[...testCorruptingTheFirstContributionNamesTheFirstContribution] :
XCTAssertEqual failed: ("["s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11"]") is not equal to ("["s1"]")
MemoryShapeComparisonTests.swift:68: error: -[...testTouchedElementsIsCheckedWhereItExists] :
XCTAssertEqual failed: ("[]") is not equal to ("["variable_1m"]")
```

The corrupted first element matches *itself* and passes, while the ten healthy scenarios are
reported instead — the exact inversion a first-of-group baseline produces.
`testAHealthySetHasNoFailures` stays green, as predicted: on a healthy set the idiom is
vacuous but harmless, which is precisely why it survived unnoticed until this slice.

#### Drill (l) — G2 — flatness against `summaries.first?.computeProbes`

```
MemoryShapeComparisonTests.swift:87: error: -[...testANonFlatComputeProbeCountFailsTheOffendingScenario] :
XCTAssertEqual failed: ("["100k_lines_width_10", "100k_lines_width_40", "1m_lines_width_10", "1m_lines_width_40", "1m_lines_width_inf"]") is not equal to ("["100k_lines_width_inf"]") - the FIRST scenario must be able to fail; under a first-of-group baseline it is the one element that never is
```

Reaching this red required **adding a first-element case to the shipped test** (`68e9358`):
with only the plan's index-4 corruption, `summaries.first` still holds the healthy value and
the substitution is invisible. The strengthening is what makes the plan's own predicted red
reachable.

#### Drill (m) — G3 — raise `wrapMemoryShapeProbeShapeBound` to 1 000

Reddened exactly as predicted: the drain-delta-33 pair drops below the raised bound and the
actual failure list is `[]` against `["100k_lines_width_inf", "1m_lines_width_inf"]`.

#### Drill (n) — G4 — delete the `bufferedRows`/`streamedRows` clause

```
MemoryShapeComparisonTests.swift:118: error: -[...testAWidthDependentBufferFails] : XCTAssertTrue failed
```

Also required a fixture repair first (`68e9358`): as planned, the mutation left
`drain`/`point` at their constructor defaults, which independently breached the `<= 32` pair
bound, so the scenario was named by invariant 9 whether or not invariant 10 existed.

#### Drill (o) — G6 — delete the `narrow.pointQueryProbes <= wide.pointQueryProbes` block

Reddened exactly as predicted: `[]` against
`["100k_lines_width_10", "100k_lines_width_inf"]`. This drill is the spec's own G6 drill
*replaced* by a positive control, because the spec's proposed mutation (stop counting
`columnOffset`) can be survived — `canBreak` is counted on the same walk — and a drill that
may report green certifies nothing.

#### Drill (p) — G18 — drop `counter.distinctLines.insert(index)`

Reddened exactly as predicted: `providerLines` reports `"0" is not equal to "90" - counted,
not assigned`, while the two preceding assertions in the same method (`bufferedLines == 90`,
`geometryLines == 90`) report no failure at all. That asymmetry *is* the guarantee: the
column is a count now, and it moves independently of the window it used to be assigned from.

#### The byte-identity fingerprint of the five pre-existing lines

Run with a throwaway `git worktree` at `main` (the plan's `git checkout main -- .` version
cannot work here — §7.5), built and run in isolation. The raw script verdict was
`existing_lines=CHANGED`; the diff was read before anything was concluded from it, and the
**entire** difference is SwiftPM's own build-progress preamble (`Building for production…`,
`[0/6] Write sources`, `Compiling …`, `Build … complete! (N.NNs)`) — a from-scratch build in
the `main` worktree against an incremental one at HEAD. Isolating the `^mode=memory_shape`
lines from both captures (5 lines each) and diffing those directly: **byte-identical, 0
differences**, `checksum=` included. `touched_lines` and `provider_lines` print `90` on both
sides, which is the repair behaving exactly as spec §7 requires — the provenance changes
from an assignment to a measurement, the number does not.

This is the claim AC7 and spec §7 rest on, so it was **verified twice independently**: by
Task 3's implementer, and again by that task's reviewer with a fresh `main` worktree, both
runs and a diff of the non-wrap lines showing 0 differences.

### Task 4 — the two unit-level probe-count pins (commits `bf75379`, `8d848fb`)

`WrapComputeProbeCountTests` (G20) and `DocumentVisualRowCursorProbeCountTests` (G21). Both
green from birth by design — they **measure** an implementation rather than specify new
behaviour, which is the D-35 class that gets a drill instead of a red-first. Whole suite
**521/0**.

`testComputeProbesTheLayoutAConstantNumberOfTimes` passed at
`wrapMemoryShapeComputeProbes = 2` without adjustment, so Task 1's measured constant and
this pin agree — the consistency check the task exists to make.

#### Drill (q) — G20 — add `_ = layout.visualRowCount(inLine: 0)` to `validateVisualRowLayout`

```
WrapComputeProbeCountTests.swift:34: error: ... XCTAssertEqual failed:
("3") is not equal to ("2") - lines=1000 width=inf
... (11 more, one per lineCount x width combination)

WrapComputeProbeCountTests.swift:50: error: ... XCTAssertEqual failed:
("1") is not equal to ("0") - compute reads the prefix, never a per-line count
```

Both tests redden, but **not for the same reason**, which corrects the plan's "both tests
fail, 3 vs 2": the second test asserts no total at all and fails on the `visualRowCount == 0`
assertion. This is the slice's **only** edit to `Sources/TextEngineCore`; it was restored
and `git diff main -- Sources/TextEngineCore` was empty before and after (and again in §5).

#### Drill (r) — G21 — give `DocumentVisualRowCursor.init` a linear `firstVisualRow` loop

```
DocumentVisualRowCursorProbeCountTests.swift:55: error: ...
XCTAssertLessThanOrEqual failed: ("99007") is greater than ("32")
- width=inf: probes went 1112 -> 100119 across a 100x document

DocumentVisualRowCursorProbeCountTests.swift:55: error: ...
XCTAssertLessThanOrEqual failed: ("99007") is greater than ("32")
- width=4.0: probes went 1197 -> 100204 across a 100x document
```

The **base counts** in that output are the point, and they are the second polarity of a
fixture repair (§7.6): before the fix the same drill printed `1112 -> 100119` at *both*
widths, digit for digit, because the fixture is an 8-cell line at advance 1.0 and any
`wrapWidth >= 8.0` — including the `10.0` the pin used — is the infinite case under another
name. The pin measured the unwrapped regime twice. It now sweeps `.infinity` and `4.0`, and
carries a **fixture guard** asserting the two widths really are two regimes
(`visualRowCount(inLine: 0) > 1` at 4.0, `== 1` at `.infinity`), so the coincidence cannot
recur silently.

### Task 5 — D-43: the plan linter runs its own self-test on every PR (commit `f9d1932`)

The unguarded `Lint plan assertions` step's payload becomes
`./.github/scripts/lint-plan-assertions.sh --self-test && ./.github/scripts/lint-plan-assertions.sh`,
and `WorkflowShapeTests.testPlanLintStepIsBlockingAndUnguarded`'s expected literal moves with
it. The pin was changed **first**, and reddened before the workflow was touched — which is
the ordering evidence that it is a real payload-equality pin and not a token probe:

```
error: -[ViewportBenchmarksTests.WorkflowShapeTests testPlanLintStepIsBlockingAndUnguarded] :
XCTAssertEqual failed: ("0") is not equal to ("1") - .github/workflows/swift-ci.yml: want exactly
one step whose run payload is `./.github/scripts/lint-plan-assertions.sh --self-test &&
./.github/scripts/lint-plan-assertions.sh`, found 0
```

`WorkflowShapeTests` 14/0 after; `lint-plan-assertions.sh --self-test` → `self_test=pass`
(exit 0); `lint-plan-assertions.sh` → `lint=pass files=2 violations=0` (exit 0); whole suite
**521/0**.

#### Drill (s) — G9 — append ` || true` to the step's payload

```
Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:582:
error: -[ViewportBenchmarksTests.WorkflowShapeTests testPlanLintStepIsBlockingAndUnguarded] :
XCTAssertEqual failed: ("0") is not equal to ("1") - .github/workflows/swift-ci.yml: want exactly
one step whose run payload is `./.github/scripts/lint-plan-assertions.sh --self-test &&
./.github/scripts/lint-plan-assertions.sh`, found 0
```

A trailing ` || true` makes the whole step exit 0 forever, and a token probe reports it as
green because every expected token is present and in order. Payload equality is what catches
it.

The plan's own restoration check (`git diff --quiet -- .github/workflows/swift-ci.yml`)
printed `DIRTY` here, correctly and uninterestingly: at that point in the ordering the task's
own intended payload change was still uncommitted, so the working tree necessarily differs
from `HEAD` whether or not the drill artifact was removed. Restoration was verified by
content instead — one changed line, byte-identical to the intended payload, no ` || true`
residue.

### Task 6 — D-19, D-20, D-21, D-38 (commits `3bd409f`, `ce4bd55`)

- **D-19.** `testAbsoluteCeilingFiresForFrameHotPathMode` → `testAbsoluteCeilingFiresForScrollFrameMode`,
  three comments rewritten into `.scrollFrame` vocabulary; `rg -i 'frame.hot.path' Tests/
  Sources/` → **empty** (`vocabulary_scan=empty`). `docs/` deliberately untouched: five
  historical hits there are evidence records, not sites to fix.
- **D-20/D-21.** `testNonGateableModesClassifyAsScrollFrame` and
  `testGateableScrollFrameClassIsExactlyDocumented`, both deriving their sets from
  `BenchmarkMode.allCases`. `GateLogicTests` 27 → 29 tests.
- **D-38.** `let mustScan = 55 - 15` replaced by a derivation from the fixture's own
  variables, with a divisibility guard:

```swift
let rowCount = base.visualRowCount(inLine: 0)
let cellCount = base.columnCount(inLine: 0)
XCTAssertEqual(cellCount % rowCount, 0, "fixture: rows must hold equal cell counts")
let cellsPerRow = cellCount / rowCount
let mustScan = (far - near) * cellsPerRow
```

Whole suite **523/0**.

#### Drill (t)(i) — G12 — move `.wrapPointQuery` into the `.discreteAction` arm

```
GateLogicTests.swift:236: error: -[...testNonGateableModesClassifyAsScrollFrame] :
XCTAssertEqual failed: ("discreteAction") is not equal to ("scrollFrame") - wrap_point_query:
inert today, but it stops being inert the moment a wrap mode becomes gateable at node 6
```

`testDiscreteActionClassIsExactlyDocumented` and
`testGateableScrollFrameClassIsExactlyDocumented` both **passed**, and all 14
`GateFloorTests` stayed green — which is exactly the gap D-20 records, demonstrated rather
than asserted: both siblings filter on `isGateable`, and `wrapPointQuery` is not gateable.

#### Drill (t)(ii) — G12 — move `.columnQuery` into the `.discreteAction` arm

```
GateLogicTests.swift:218: error: -[...testDiscreteActionClassIsExactlyDocumented] :
XCTAssertEqual failed: ("["bulk_structural_mutation", "column_query"]") is not equal to ("["bulk_structural_mutation"]")
GateLogicTests.swift:253: error: -[...testGateableScrollFrameClassIsExactlyDocumented] :
XCTAssertEqual failed: (…"column_geometry_query", "point_query", …) is not equal to (…"column_query", …)
GateLogicTests.swift:259: error: -[...testGateableScrollFrameClassIsExactlyDocumented] :
XCTAssertEqual failed: (…) - the two class pins must partition the gateable set, or a mode can sit in neither and be checked by neither
```

`GateFloorTests` stayed green here too, and that is informative rather than incidental:
moving a mode into `.discreteAction` only **loosens** its ceiling, so a budget already under
the tighter one stays under the looser one. No budget-under-ceiling check can see this
mutation; only a class pin can. A full `swift test` confirmed exactly these 2 tests / 3
assertions reddened project-wide.

#### Drill (u) — G23 — D-38's derived constant vs the transcribed one

Three attempts were needed; the first two could not separate the derived implementation from
the transcribed one it replaced, which is a defect in the drill (§7.7). The separating run:

```
Test Case '-[TextEngineCoreTests.WrapPointQueryCountTests testColumnCostGrowsWithTheRowInLine]' started.
WrapPointQueryCountTests.swift:279: error: ... XCTAssertGreaterThanOrEqual failed: ("25") is less than ("40")
Test Case '...testColumnCostGrowsWithTheRowInLine' failed (0.036 seconds).
FIXROUND2-GROWTH-PROBE growth=25 mustScan=40
```

| Attempt | Fixture | `far`/`near` | Derived `mustScan` | Transcribed `mustScan` | Observed growth | Separates? |
|---|---|---|---|---|---|---|
| Original (planned) | 50 cells / width 50 (10 rows) | 10 / 2 | 40 | 40 | not reached (earlier fixture guards fired) | no — the two values coincide |
| Fix round 1 | 100 cells / width 10 (100 rows) | 10 / 2 | 8 | 40 | 49 | no — growth clears both |
| Fix round 2 | 100 cells / width 10 (100 rows) | 6 / 2 | 4 | 40 | 25 | **yes** — 4 ≤ 25 < 40 |

The derived version tracks the reshaped fixture and stays green; the transcribed constant
overshoots a fixture it no longer describes and reddens. Recorded with all three growth
measurements so a reader can see the assertion's slack rather than take it on faith: the
test is a `XCTAssertGreaterThanOrEqual` lower bound, and at a wide sample gap the real cost
(~6 probes per row, not one per cell) clears both bounds.

#### Fix round 3 — a stale comment shipping beside its own discharge

`Sources/ViewportBenchmarks/BenchmarkOptions.swift`'s comment above `absoluteCeiling` still
said the class-membership pin "does NOT cover" the non-gateable modes and "do not expect a
test to catch a wrong choice here" — which `testNonGateableModesClassifyAsScrollFrame`, added
two steps earlier in the *same* task, had just made false. It is also the exact sentence
D-20's ledger row cites as where the gap is documented, so shipping D-20's discharge beside
it would be the documentation rot D-19 exists to remove, inside the task that removes it.
Comment-only edit (`ce4bd55`); every switch arm byte-identical.

### Task 7 — D-10, D-11 (commits `48bde6c`, `a8947ad`)

- **D-10.** A superseded banner inserted immediately after the title of
  `verification/2026-06-16-swift-ci-required-checks.md`, naming the current context
  (`WASM cross-target compile`), the slice that renamed it, and the fact that every
  old-name occurrence below — ruleset JSON included — is the record of what was true on
  2026-06-16 and is not current policy. Pure insertion; the body is byte-unchanged, because
  a record is evidence and rewriting it to match a later fact falsifies it.
- **D-11.** `allJobKeys()` (walks the top-level `jobs:` block) plus
  `testWorkflowJobSetIsExactlyTheThreePinnedJobs`, pinning both the job keys and the job
  names against `requiredCheckContexts`. `workflowLines()` was extracted so the file read
  lives in one place (§7.8).

Whole suite **524/0**.

#### Drill (v) — G10 — append a fourth job to the workflow

```
WorkflowShapeTests.swift:607: error: -[...testWorkflowJobSetIsExactlyTheThreePinnedJobs] :
XCTAssertEqual failed: ("["host-tests-and-benchmark-gate", "ios-cross-target-compile", "wasm-cross-target-compile", "scratch-job"]") is not equal to ("["host-tests-and-benchmark-gate", "ios-cross-target-compile", "wasm-cross-target-compile"]") - .github/workflows/swift-ci.yml: the job set changed. Every job here reports a status-check context to GitHub, and ruleset Main (id 17656807) requires three of them by exact name. A new job needs a row in requiredCheckContexts AND a decision about whether the ruleset requires it.
WorkflowShapeTests.swift:621: error: -[...testWorkflowJobSetIsExactlyTheThreePinnedJobs] :
XCTAssertEqual failed: ("["Host tests and benchmark gate", "iOS cross-target compile", "WASM cross-target compile", "Scratch job"]") is not equal to ("["Host tests and benchmark gate", "iOS cross-target compile", "WASM cross-target compile"]")
```

**All fourteen other tests in the file stayed green** — enumerated by name in the
implementer's report and confirmed from the per-test log rather than assumed, including the
whole-file `--gate` census (the scratch job's `echo hello` adds no `--gate` token). That is
the gap D-11 records, demonstrated: before this test, a fourth job was invisible to every pin
in the file.

Workflow restored byte-identically (`git diff --quiet -- .github/workflows/swift-ci.yml` →
clean).

### Task 8 — D-14 discharged, D-15 falsified (commit `404feb8`)

**D-14.** `derive-gate-budgets.sh`, `harvest-gate-corpus.sh` and `detect-docs-only-pr.sh` each
gain the five classification helpers (copied verbatim from `cross-target-compile.sh:302-352`,
diffed byte-for-byte against the source range before insertion), a
`SELF_TEST_COVERED`/`SELF_TEST_EXEMPT` partition, and the two-direction partition check. The
check block was written **once** to a file and spliced into each script with `awk`, so the
three copies are identical by construction rather than by three hand-pastes. `SELF_TEST_EXEMPT`
is empty in the first two scripts (every non-harness function is genuinely referenced by
`run_self_test`) and carries three tab-separated justifications in `detect-docs-only-pr.sh`
(`usage`, `fail`, `write_github_output`).

`lint-plan-assertions.sh` — a **fifth** script the plan's D-15 scope did not name — was
checked and deliberately left alone: its `--self-test` case arm is a bare `run_self_test`
with **no** trailing `exit 0`, so its status propagates through `main "$@"`. Recorded so the
record shows the fifth script was considered, not missed.

Two real defects, both caught by *running* the self-tests rather than inspecting them:

1. **bash 3.2 + `set -u` + a declared-but-empty array is `unbound variable`, not zero
   iterations.** `derive-gate-budgets.sh: line 269: SELF_TEST_EXEMPT[@]: unbound variable` on
   the first full run. The three copies therefore use `"${ARR[@]+"${ARR[@]}"}"` where the
   reference script uses the bare form its own never-empty arrays make safe. Five expansion
   sites per script; a `grep` confirmed none left unguarded.
2. **The four non-`assert_*` helpers must classify themselves.** `is_harness_function` only
   exempts `assert_*`, so `defined_functions`, `is_harness_function`, `self_test_body` and
   `body_references_function` need their own `SELF_TEST_COVERED` entries — first run produced
   `self_test=fail label=classified_defined_functions expected=1 actual=0`.

#### Drill (w), G11 — an unexercised function per script, plus the phantom direction

```
derive-gate-budgets:    exit=1  self_test=fail label=classified_scratch_unclassified_fn
                        (next two lines: "  expected: [1]" / "  actual:   [0]")
harvest-gate-corpus:    exit=1  self_test=fail label=classified_scratch_unclassified_fn
                        (next two lines: "  expected: [1]" / "  actual:   [0]")
detect-docs-only-pr:    exit=1  self_test=fail label=classified_scratch_unclassified_fn expected=1 actual=0
```

Phantom direction (a covered-but-undefined name), on `derive-gate-budgets.sh`:

```
exit=1
self_test=fail label=covered_defined_phantom_function_does_not_exist expected=defined actual=missing fn=phantom_function_does_not_exist
```

#### Drill (w), G24 — D-15's dispatcher shape, at the opposite polarity to the prediction

```
before_exit=1
after_exit=0
```

`before` (bare `run_self_test`) printed `self_test=fail label=injected_failure` / `expected:
[1]` / `actual: [2]` and **stopped there**, process exit 1. `after` (the prescribed
`run_self_test || exit 1`) printed the same three lines **plus** `self_test=pass`, process
exit 0. Re-run twice from a clean scratch directory; both runs agree. This is what falsified
D-15 — see §7.1.

Final state of the task: four `selftest=pass`, `swift test --filter ScriptSelfTestTests` 2/0,
whole suite **524/0**, and `git diff a8947ad --stat -- .github/scripts` showing **336
insertions, 0 deletions** — purely additive, which is itself the proof that the three
dispatcher lines were restored to their pre-task bytes rather than merely re-edited.

## 3. The mode's eleven lines, and the five that must not move

`swift run -c release ViewportBenchmarks -- --memory-shape`, exit 0, **eleven lines, every
one `invariant=pass`** (five pre-existing + six wrap):

```
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=765061875
mode=memory_shape provider=wrap scenario=100k_lines_width_inf line_count=100000 wrap_width=inf total_rows=100000 visible_rows=80 buffered_rows=90 streamed_rows=90 point_row_in_line=0 point_clamp=none compute_probes=2 drain_probes=469 row_query_probes=21 point_query_probes=34 core_owned_bytes=242 provider_owned_bytes=800008 invariant=pass checksum=621691
mode=memory_shape provider=wrap scenario=100k_lines_width_40 line_count=100000 wrap_width=40 total_rows=200000 visible_rows=80 buffered_rows=90 streamed_rows=90 point_row_in_line=1 point_clamp=none compute_probes=2 drain_probes=4023 row_query_probes=21 point_query_probes=118 core_owned_bytes=242 provider_owned_bytes=800008 invariant=pass checksum=866730
mode=memory_shape provider=wrap scenario=100k_lines_width_10 line_count=100000 wrap_width=10 total_rows=800000 visible_rows=80 buffered_rows=90 streamed_rows=90 point_row_in_line=3 point_clamp=none compute_probes=2 drain_probes=2094 row_query_probes=21 point_query_probes=128 core_owned_bytes=242 provider_owned_bytes=800008 invariant=pass checksum=2362769
mode=memory_shape provider=wrap scenario=1m_lines_width_inf line_count=1000000 wrap_width=inf total_rows=1000000 visible_rows=80 buffered_rows=90 streamed_rows=90 point_row_in_line=0 point_clamp=none compute_probes=2 drain_probes=472 row_query_probes=24 point_query_probes=37 core_owned_bytes=242 provider_owned_bytes=8000008 invariant=pass checksum=6021691
mode=memory_shape provider=wrap scenario=1m_lines_width_40 line_count=1000000 wrap_width=40 total_rows=2000000 visible_rows=80 buffered_rows=90 streamed_rows=90 point_row_in_line=1 point_clamp=none compute_probes=2 drain_probes=4026 row_query_probes=24 point_query_probes=121 core_owned_bytes=242 provider_owned_bytes=8000008 invariant=pass checksum=8516730
mode=memory_shape provider=wrap scenario=1m_lines_width_10 line_count=1000000 wrap_width=10 total_rows=8000000 visible_rows=80 buffered_rows=90 streamed_rows=90 point_row_in_line=3 point_clamp=none compute_probes=2 drain_probes=2097 row_query_probes=24 point_query_probes=131 core_owned_bytes=242 provider_owned_bytes=8000008 invariant=pass checksum=23512769
```

What the six wrap lines say, read across rather than down:

- **`compute_probes=2` in all six.** Flat across a 10x size jump *and* three widths. This is
  AC3, and it is a **measurement** (Task 1 Step 8), not a number the design predicted — the
  spec's §8 named it as a risk to the number, never to the shape.
- **`buffered_rows == streamed_rows == 90` in all six**, at every width. The visible window
  is 80 rows and the buffer 90 whatever the wrap width does to the row count, so the drain
  streams exactly the buffered window and nothing more.
- **`drain_probes`, `row_query_probes`, `point_query_probes` move by exactly 3** from 100k to
  1M at fixed width (469→472, 4023→4026, 2094→2097; 21→24 thrice; 34→37, 118→121, 128→131) —
  against a `<= 32` shape bound. `log2(10) ≈ 3.32`, and a linear term would show as ~10x,
  three orders of magnitude away.
- **`point_row_in_line` is 0 / 1 / 3 at inf / 40 / 10** and `point_clamp=none` everywhere:
  the query lands off a row start at both wrapped widths (AC4), so the within-line walk is
  actually exercised, and `point_query_probes` at width 10 (128, 131) exceeds the
  infinite-width value (34, 37) — the walk is counted, not inferred.
- **`provider_owned_bytes` is 800 008 at 100k and 8 000 008 at 1M**, identical across widths
  at a fixed size: exactly `(line_count + 1) * MemoryLayout<Int>.size`. That is criterion 2's
  second clause — the linear data is **provider**-owned — made observable (AC12).
- **`core_owned_bytes=242`** is printed for continuity with the two sibling groups and is
  **not evidence**; the source says so in a comment. See D-46.

The **five pre-existing lines are byte-identical to `main`**, `checksum=` included, verified
twice independently against a fresh `main` worktree (Task 3 above). `touched_lines` prints
`90` on both sides: the repair changed the number's provenance from an assignment to a
measurement without changing the number, which is what spec §7 requires and what would have
been a *finding* had it come out otherwise.

## 4. Task 1 Step 8 — the measurement the contract table was filled from

Six scenarios, run once each under `swift test` (a scratch test, deleted immediately after):

```
measure lines=100000 width=inf build=0.021630834 seconds compute=2 drain=469  row=21 point=34
measure lines=100000 width=40  build=0.082841792 seconds compute=2 drain=4023 row=21 point=118
measure lines=100000 width=10  build=0.175671333 seconds compute=2 drain=2094 row=21 point=128
measure lines=1000000 width=inf build=0.215517875 seconds compute=2 drain=472  row=24 point=37
measure lines=1000000 width=40  build=0.820341 seconds compute=2 drain=4026 row=24 point=121
measure lines=1000000 width=10  build=1.752271042 seconds compute=2 drain=2097 row=24 point=131
```

**Reading 1 — the constant is 2.** Identical in all six rows, matching the code reading
exactly (`validateVisualRowLayout` probes `firstVisualRow(ofLine: 0)` and
`firstVisualRow(ofLine: lineCount)`; `rowHeight` and `wrapWidth` are properties, not counted
hooks). No disagreement across rows, so spec Decision 2 was not falsified and
`wrapMemoryShapeComputeProbes = 2` is a measured constant, not a predicted one.

**Reading 2 — every 1M-vs-100k delta at fixed width is exactly 3:**

| width | drain Δ | row Δ | point Δ |
|-------|--------:|------:|--------:|
| inf | 3 | 3 | 3 |
| 40 | 3 | 3 | 3 |
| 10 | 3 | 3 | 3 |

Well inside the `<= 32` bound, and consistent with `log2(1 000 000 / 100 000) ≈ 3.32`. The
spec's "if a delta exceeds 32, read the code" branch was not taken.

**Reading 3 — construction cost, and a labelling correction the record must carry.** The six
`build=` figures sum to 3.068 s, matching XCTest's reported 3.070 s for the single test, so
the provider-construction risk in spec §8 is retired: the O(N) reindex is bounded and finite
at 1M x width 10. **But these six figures are DEBUG configuration** — `swift test` builds and
runs unoptimized — and are roughly **3x** the release `reindex_ns` figures the spec's §8
quotes from `--wrap-compute` (which are taken under `swift run -c release`). The *shape*
matches the release intuition (width 10 ≫ width inf; 1M ≫ 100k); only the absolute wall time
differs, and by a debug/release factor rather than anything structural. They must not be
quoted against release numbers.

## 5. Invariant fingerprint (spec §7, AC6/AC7/AC8)

All commands run on the tree at row 16 of §0 plus this record's own uncommitted docs edits
(which touch no Swift source, no script and no workflow).

```
$ swift build -c release
build_exit=0

$ if [ -z "$(rg -n "Foundation" Sources/TextEngineCore)" ]; then echo "foundation_scan=empty"; else echo "foundation_scan=NON_EMPTY"; fi
foundation_scan=empty

$ if git diff --quiet main -- Sources/TextEngineCore; then echo "core_untouched=true"; else echo "core_untouched=FALSE"; fi
core_untouched=true
```

`core_untouched=true` is the one that had to be earned: Task 4's drill (q) and drill (r) are
the slice's **only** edits to `Sources/TextEngineCore`, both temporary, both restored, and
the emptiness was confirmed by the implementer before and after each drill and again here.

**Twelve gated modes**, each run as `swift run -c release ViewportBenchmarks -- <flag> --gate`
into one log — the default pipeline mode taking a bare `--gate` (passing `--gate --gate`
would be a repeated mode flag):

```
--gate  --variable-height  --variable-height-mutation  --structural-mutation
--bulk-structural-mutation  --line-query  --line-geometry-query  --column-query
--column-geometry-query  --point-query  --point-geometry-query  --realistic-provider
```

```
$ grep -c 'gate=pass' gates.txt
46
$ grep -c 'gate=fail' gates.txt
0
```

**Checksum diff, 46 gated tuples.** Baseline re-derived from the repository alone, out of
slice 55b's record (the last record carrying the raw 46 lines; slice 56 proved its own set
byte-identical to it, so it is equally slice 56's baseline):

```
$ awk '/^## 5\. The twelve gates and the checksum baseline diff$/{p=1} p{print} p && /^## 6\./{exit}' \
    docs/superpowers/verification/2026-09-03-wrap-point-query.md \
    | awk '/^```$/{n++; next} n==3' > baseline-gates-raw.txt
$ sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9-]+).*/\1|\2\t\3/p' baseline-gates-raw.txt \
    | sort -u > checksums-baseline.tsv
$ wc -l < checksums-baseline.tsv
      46
$ grep -v -e 'mode=memory_shape' -e 'mode=memory_observation' gates.txt \
    | sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9-]+).*/\1|\2\t\3/p' \
    | sort -u > checksums-local.tsv
$ wc -l < checksums-local.tsv
      46
$ DIFF="$(diff checksums-baseline.tsv checksums-local.tsv || true)"
$ if [ -z "$DIFF" ]; then echo "checksum_diff=empty"; else echo "checksum_diff=NON_EMPTY"; fi
checksum_diff=empty
```

**46/46 byte-identical.** The D-18 filter is what makes that count 46: without it the same
extraction over this slice's gate log plus the two diagnostic modes yields **60**, not the
54 it yielded before — because `--memory-shape`'s line count went **5 → 11**. Re-measured
here rather than asserted:

```
$ sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9-]+).*/\1|\2\t\3/p' \
    gates.txt memshape.txt observation.txt | sort -u | wc -l
      60
```

**The three wrap modes' checksums**, thirteen tuples across `--wrap-compute` (3),
`--wrap-row-query` (4) and `--wrap-point-query` (6), diffed against slice 55b's record:

```
wrap_compute|width_10            115068800
wrap_compute|width_40            143365120
wrap_compute|width_inf           181094400
wrap_point_query|clamped_x_100k  2306197982545833952
wrap_point_query|clamped_y_100k  2306075261392253952
wrap_point_query|long_line_deep_row  2452436673478389824
wrap_point_query|narrow_100k     2306075259458473952
wrap_point_query|uniform_100k    2306075108941053952
wrap_point_query|uniform_1k      2306073081424253952
wrap_row_query|clamped_100k      2240231040000
wrap_row_query|narrow_100k       2240234540000
wrap_row_query|uniform_100k      2047976320000
wrap_row_query|uniform_1k        20459520000
```

```
wrap_checksum_diff=empty
```

**AC6 — the wrap scenarios did not leak into `--memory-observation`** (spec Decision 5 keeps
the two scenario lists separate):

```
$ swift run -c release ViewportBenchmarks -- --memory-observation > observation.txt 2>&1
observation_exit=0
$ grep -c 'provider=wrap' observation.txt
0
```

Three `mode=memory_observation` lines, unchanged in shape, all `observation=pass`.

**Budgets and corpus, untouched:**

```
$ git diff --quiet main -- docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
corpus_unchanged=true
$ git diff --quiet main -- Sources/ViewportBenchmarks/BenchmarkModels.swift
budgets_file_unchanged=true
```

## 6. Test-count pair, delta, and enumeration (AC8)

- **Slice 56's count (baseline):** 497 tests, 0 failures.
- **This slice's count:** **524 tests, 0 failures.**

```
$ swift test
	 Executed 524 tests, with 0 failures (0 unexpected) in 7.364 (7.395) seconds
```

- **Delta: 524 − 497 = 27.**

**Re-checkable from git alone**, with no historical session run required — a static count of
`func test` declarations at `main` and at the last implementation commit (`404feb8`, row 16
of §0, named rather than "HEAD"):

```
$ git grep -o "func test" main -- Tests | wc -l
     497
$ git grep -o "func test" 404feb8 -- Tests | wc -l
     524
```

**Enumeration:**

| Task | New test functions | Running total |
|---|---|---|
| 1 | 4 (`CountingWrapLayoutTests`) | 501 |
| 2 | 6 (`WrapMemoryShapeTests`) | 507 |
| 3 | 10 (`MemoryShapeComparisonTests`) | 517 |
| 4 | 4 (`WrapComputeProbeCountTests` 2 + `DocumentVisualRowCursorProbeCountTests` 2) | 521 |
| 5 | 0 (an existing pin's expected literal changed) | 521 |
| 6 | 2 (`GateLogicTests`: D-20 and D-21's class pins) | 523 |
| 7 | 1 (`WorkflowShapeTests.testWorkflowJobSetIsExactlyTheThreePinnedJobs`) | 524 |
| 8 | 0 (shell scripts and their self-tests) | 524 |

`4 + 6 + 10 + 4 + 0 + 2 + 1 + 0 = 27`. **Enumeration and measured delta agree exactly.**
Every intermediate running total above (501, 507, 517, 521, 521, 523, 524, 524) matches the
whole-suite count recorded at the end of that task's own section in §2 — including the two
fix rounds that added *assertions* inside existing tests rather than new test functions
(Task 1's `visualRowCount` witness, Task 3's first-element case), which is why those rounds
moved no count.

## 7. Plan and spec defects found during execution

The plan document is deliberately **not** retro-edited. A plan is an argument and a piece of
evidence about what was believed at planning time; correcting it in place would destroy that.
The one exception is the spec's §4B, which states a *contract* later code is written against,
and which was amended on its own commit (`077b0e7`) before that code existed. Everything else
is corrected here.

### 7.1 D-15 is FALSIFIED, not discharged

The row prescribed converging all four `.github/scripts` self-test dispatchers on
`run_self_test || exit 1` followed by an explicit `exit 0`, "so a self-test's failure cannot
be swallowed by a dispatcher that merely falls through". **The prescribed shape produces
exactly the swallow it was written to prevent.**

Bash's `-e` exemption for a command on the left of `||` applies to the callee's **entire
body**, not to the call statement. So under `set -e`, `run_self_test || exit 1` disables `-e`
inside `run_self_test`: a returning assertion no longer aborts the shell, execution continues
to the closing `echo "self_test=pass"`, that success becomes the function's own status, and
the `|| exit 1` branch never fires. The **bare** call is the safe shape there, because `-e`
stays live and aborts at the `return 1`. Measured (drill (w), G24, on
`derive-gate-budgets.sh`): bare → exit **1**, printing only the fail line; guarded → exit
**0**, printing the fail line **and** a false `self_test=pass`.

The five scripts split **two** ways on `set`:

| Script | `set` flags | Has `-e`? |
|---|---|---|
| `derive-gate-budgets.sh` | `set -euo pipefail` | yes |
| `harvest-gate-corpus.sh` | `set -euo pipefail` | yes |
| `lint-plan-assertions.sh` | `set -euo pipefail` | yes (out of D-15's scope — bare call, no trailing `exit 0`) |
| `detect-docs-only-pr.sh` | `set -uo pipefail` | no |
| `cross-target-compile.sh` | `set -uo pipefail` | no |

The *consequence* of converging has three buckets, which is a different partition from the
`set` split: on the two `-e` scripts D-15 touches, the guard is a **regression**; on the one
non-`-e` script it touches, it is **inert** (without `-e` a returning assertion is ignored by
`run_self_test`'s own body either way, so the dispatcher was never the thing standing between
a returning assertion and a false pass); and `cross-target-compile.sh` — the reference the
row points at as the safe spelling — is itself a non-`-e` script, so its guard is equally
inert and reads as safe only because nothing in it has ever needed the guard to fire.

There is no script in the set where the prescribed convergence closes the hole.
**Purpose over letter:** the three dispatcher edits were reverted to their `a8947ad` bytes
(confirmed by `git diff a8947ad --stat -- .github/scripts` = 336 insertions, **0 deletions**,
so the dispatcher lines were never altered in the shipped diff), D-14 shipped whole, D-15
stays **open** with an amended statement and its remedy withdrawn, and the evidence plus the
shape a real fix would take are recorded as the new row **D-47**.

The real defect lives *inside* `run_self_test`, not at the dispatcher: a `return`-based
assertion's failure is lost the moment execution continues past it to a later command that
succeeds — here, always the closing `echo`. Fixing it needs a run-level failure counter that
every assertion increments and that `run_self_test` checks before that `echo`, which is a
change to the assertion/harness contract, not a three-line dispatcher edit. It is latent
today because every `assert_*` helper in all five scripts calls `exit 1`, which kills the
process regardless of `-e` state or `||` context.

### 7.2 `visualRowCount(inLine:)` has no consuming call site in the core — the plan says it does

`docs/superpowers/plans/2026-09-04-wrap-memory-shape.md:121` asserts
`XCTAssertGreaterThan(drainCounter.visualRowCount, 0, "the packer reads visualRowCount")`.
**That is false against the shipped core**, and it is the correction a reader of the plan
alone would otherwise miss. `grep -rn "\.visualRowCount(" Sources/TextEngineCore/` returns
**zero** hits: not in `validateVisualRowLayout` (which reads `firstVisualRow(ofLine: 0)` and
`firstVisualRow(ofLine: lineCount)` and nothing else — the same two probes §4's constant
counts), not in `DocumentVisualRowCursor`, not in `visualRowAt` (whose own comment says the
upper bound `rowInLine < visualRowCount(inLine:)` is *deliberately* not checked because it
would cost a probe), not in `visualPointAt`. Through all four entry points the counting
instrument wraps, the hook is structurally unreachable; the count is 0 on every run,
deterministically. The plan is internally aware of half of this (its line 1439 asserts
`counter.visualRowCount == 0` for `compute` specifically) but not that the **drain** path
never calls it either.

The test now asserts `== 0` with the grep evidence in a comment. That alone would have left
the hook's own increment witnessed by nothing — deleting `counter.visualRowCount += 1` was
**measured green** before the repair — which is the exact G8 failure mode and a violation of
spec Decision 7 ("every counter carries a witness"). So the test additionally calls the hook
directly on the counting wrapper and asserts the counter moved; drill (a2) above is that
witness's recorded red.

### 7.3 Drill (e) could not redden with a mid-document anchor

The plan's `lineCount: totalRows - 1` cannot trip
`memoryShapeRangeIsOrderedAndBounded`'s upper-bound clause, because Decision 9 anchors every
query at the document's midpoint: on the 1 000-line fixture at width 40, `bufferEndExclusive`
is ~1 088 against `totalRows - 1 = 1 999`. The spec's own drill text asks for something
stronger and reachable — "hand the checker a range with `bufferEndExclusive > totalRows`" —
which `lineCount: range.bufferEndExclusive - 1` satisfies by construction. Superseding red
and scope note in §2, Task 2.

### 7.4 Three drills whose substitution missed the field their test corrupts

Drills (k), (l) and (n) all produced **zero** red as written, and all three for the same
reason: the drill's chosen reference field or index did not line up with the field or index
its paired test's fixture actually corrupts.

- **(k)** substituted only `bufferedWindow` from `.first`, while the test corrupts that same
  element's `streamedElements` — so the substituted baseline read the *uncorrupted* field and
  the verdict did not move. The honest first-of-group idiom substitutes all three fields.
- **(l)** substituted `summaries.first?.computeProbes` while the test corrupts index 4, so
  `first` still held the healthy `2`. The property only becomes visible when the corrupted
  element **is** the first — hence the added first-element case in the shipped test.
- **(n)** mutated an element using the constructor's default `drain`, which trips the `<= 32`
  pair bound as well, so the scenario was named by invariant 9 whether or not the clause
  under test existed. The fixture now carries width-10's own healthy `drain`/`row`/`point`
  alongside the field under test.

Two of the three repairs are changes to *shipped tests*, committed (`68e9358`); (k) was
drill-only. Uncertified guarantees are what D-35 exists to stop, which is why these went into
a fix round rather than being parked as findings.

### 7.5 Task 3 Step 8's fingerprint script could not have compiled

The plan's fingerprint script uses `git checkout main -- .` to obtain `main`'s
`--memory-shape` output. That only rewrites paths that exist in `main`; the four files Tasks
1–2 add exist in HEAD and not in `main` (confirmed with `git diff --name-only --diff-filter=A
main HEAD`), so they would survive the checkout and be compiled against `main`'s
`MemoryShapeDiagnostics.swift`, which lacks the symbols they reference. Replaced with a
throwaway `git worktree` at `main`, built and run in isolation, then removed — same
comparison, no stashing of live work, and it actually compiles.

### 7.6 A probe-count pin whose two widths were one regime

`testDrainProbesDoNotGrowWithTheDocument` swept `[Double.infinity, 10.0]` over a fixture of 8
cells at advance 1.0 — a line 8.0 wide — so **any** width `>= 8.0` is the infinite case under
another name. The pin measured the unwrapped regime twice while reading as two regimes, and
G21 was uncertified in exactly the regime the wrap arc is about. Drill (r)'s own output
proved it before the finding was named: `1112 -> 100119` at *both* widths, digit for digit.
Fixed by sweeping `4.0` instead of `10.0` and adding a fixture guard that asserts the two
widths are two regimes. This is the repository's own recorded lesson (*fixtures must separate
the axes*) recurring inside the slice whose subject is falsifiability.

A sibling, left as a documented minor: `WrapComputeProbeCountTests` sweeps
`[inf, 40, 10, 4]` over the same 8-cell fixture, so three of its four widths are the
unwrapped regime — undocumented and unguarded there. It is presentational for G20 (the ladder
has no branch on width), so the sweep reads richer than it is without weakening what is
pinned.

### 7.7 Drill (u) could not separate the two implementations, twice

The planned reshape (100 cells/width 50 → 50 cells/width 50) leaves cells-per-row at 5, so
the derived `mustScan` computes to 40 — exactly what the transcribed `55 - 15` yields. The
drill could not distinguish the implementations even if it reached the assertion, so G23 (a
guarantee the plan **added** beyond the spec) was uncertified. The first replacement (width
50 → 10, one cell per row) also failed to separate them, for a reason worth recording: the
within-line walk costs ~6 probes per **row**, not one per cell, so at a gap of 8 rows the
observed growth (49) cleared both the derived bound (8) and the transcribed one (40). What
separates them is shrinking the *sample gap* rather than the cells per row: at `far = 6`,
growth is 25, which the derived bound of 4 passes and the transcribed 40 fails. Table in §2,
Task 6.

A secondary finding on the same drill, independent of the separation question: the plan
predicted that the test's derived `far < rowCount - 1` guard (line 267) fires first on a
reshape. It does not — a *pre-existing*, separately hardcoded
`XCTAssertEqual(base.visualRowCount(inLine: 0), 20, …)` at line 248 is the first assertion in
the body and the first failure reported. Both guards do fire; the plan named the wrong one.

### 7.8 Two smaller corrections

- **`workflowLines()` did not exist.** Task 7's brief refers to a whole-file accessor in
  `WorkflowShapeTests.swift`; the file read was inline inside `jobLines(_:)` and again inside
  the `--gate` census. A small private `workflowLines()` was added and `jobLines` now calls
  it; the census's read was left alone, because it splits on whitespace *and* newlines to
  build a flat token stream and shares no purpose with the line-oriented reader. A review
  round then moved `jobLines`'s job-scoping comment back down off the new function and
  corrected its now-false "in exactly one place" clause.
- **Drill (q)'s predicted red was imprecise.** "Both tests fail, 3 vs 2" is true of the first
  test only; the second fails on `visualRowCount == 0` becoming 1. Both halves redden, for
  different reasons.

### 7.9 The tally, so a reader comparing the plan's drill list to this record does not conclude drills were skipped

**Eight of the plan's drills were defective as written** — (e), (j), (k), (l), (n), (q), (u),
(w) — and every one was repaired or replaced in-flight rather than skipped or tuned to a
green: (e) and (u) by a new perturbation, (k) by drilling the real idiom, (l) and (n) by
isolating the shipped test's fixture, (j) and (q) by correcting the *prediction* (how many
tests, which assertion) while the drill itself was sound, and (w) by following the evidence
to a falsified ledger row. A ninth finding of a different class — (r)'s fixture, where two
widths were one regime — is §7.6. What all of them have in common is the mechanism D-35
names: a drill's prediction about *which* mutation reddens is itself unverified until it is
run, and a drill that cannot fail certifies nothing while looking exactly like one that can.

### 7.10 Residuals for the debt ledger — carry, don't fix

The whole-branch review triaged five residuals as carry-not-fix: real, but each either
undrillable without a new seam, narrow in exposure, or latent rather than introduced by this
slice. Recorded here, one paragraph each, so the post-slice review can lift them into
`docs/superpowers/debt-ledger.md` as rows without re-deriving them from the transcripts. This
section is *not* itself a ledger edit — the post-slice review owns that delta.

**M-2 — `touched_lines`'s repair has no test that can fail for the reason D-45 shipped it.**
`testTheVariablePathCountsTheLinesItTouches` passes identically if `providerLines:
touchedLines` (the repair) is reverted to `providerLines: bufferedLines` (the pre-D-45
assignment): the counter and its test survive, unused, because *touched* and *buffered*
coincide in every reachable configuration of `runVariableMemoryShapeScenario(lineCount:)`,
which takes no range argument and always drains exactly the buffered window. Structurally
undrillable without a new seam (a range parameter, or a scenario whose touched set is a
strict subset of its buffered one) — Drill (p) covered the counter's own wiring at ship time
(§2, Task 3), but nothing standing distinguishes "counts touched lines" from "counts buffered
lines" for this column. Trigger to revisit: whichever slice next gives this scenario runner a
range argument, or otherwise makes touched and buffered diverge.

**M-5 — `testTheEmittedLineCarriesEveryToken` checks substrings, not tokens.** It asserts
`line.contains(token)` for each of `--memory-shape`'s wrap-half fields, so `"visible_rows=80"`
would equally satisfy a search for `"visible_rows=801"` (or any string containing it) — the
exact substring-vs-token hazard `AGENTS.md` writes down for `WorkflowShapeTests`'s own
`--gate` census (`--variable-height` is a prefix of `--variable-height-mutation`). Exposure is
narrow here: this test's own sibling tests in the same file (`testEveryWidthReportsTheSameWindowAndStreamsIt`,
`testTheQueryLandsOffARowStartAtEveryWrappedWidth`, etc.) separately pin the exact values, so a
wrong number would be caught elsewhere even though this test would not catch it. But the
project's own rule says tokens, not substrings, and this test does not follow it. Fix: split on
whitespace and assert exact-token membership, the way the workflow census does.

**M-6 — `cross-target-compile.sh` still carries unguarded array expansions under `set -u`.**
Five bare `"${SELF_TEST_COVERED[@]}"` / `"${SELF_TEST_EXEMPT[@]}"` expansions remain in
`cross-target-compile.sh`, where the three scripts this slice's Task 8 touched
(`derive-gate-budgets.sh`, `harvest-gate-corpus.sh`, `detect-docs-only-pr.sh`) now use the
bash-3.2-safe `${ARR[@]+"${ARR[@]}"}` form (found and fixed as one of Task 8's two real
defects — see §2, Task 8, and the ledger's D-14 discharge). `cross-target-compile.sh` runs
`set -uo pipefail`, so the same "declared-but-empty array expansion is `unbound variable`
under bash 3.2" trap applies to it too; it is latent only because its own
`SELF_TEST_COVERED`/`SELF_TEST_EXEMPT` arrays happen to be non-empty today. Not introduced by
this slice — this slice made the *other* three scripts safer and left the original (the
script D-14's copies were taken from) as the least-safe of the four. Trigger to revisit: the
first time either of `cross-target-compile.sh`'s two arrays is emptied, or the next slice that
touches that script's self-test harness.

**M-7 — `lint-plan-assertions.sh` is now the one self-tested script with no coverage
partition, and D-14's discharge note justifies the exclusion on the wrong row's axis.**
Task 8 checked `lint-plan-assertions.sh` (a fifth script, outside D-14's stated three-script
scope) and correctly left it alone for D-15's purposes — its dispatcher is a bare
`run_self_test` call with no trailing `exit 0`, so it is not vulnerable to D-15's defect (§2,
Task 8). But that finding is about the *dispatcher*, which is D-15's axis, not D-14's: D-14 is
about the `SELF_TEST_COVERED`/`SELF_TEST_EXEMPT` classification partition, and on that axis
`lint-plan-assertions.sh`'s four helper functions (`cleanup`, `write_awk_program`, `lint_file`,
`run_lint`) remain unclassified — the literal discharge is correct (D-14's row names exactly
three scripts, and all three now carry the partition), but the residual is real: a fifth
script's self-test coverage is unverified by the mechanism the other four now have, and
nothing documents that as a deliberate scope boundary rather than an oversight. Trigger to
revisit: extending D-14's classification helpers to a fifth script, or writing down explicitly
why `lint-plan-assertions.sh` is out of scope for the *classification* partition and not only
for the dispatcher-shape question D-15 asks.

**M-8 — `WrapComputeProbeCountTests`'s four-width sweep is mostly one regime, undocumented
where a reader meets it.** `testComputeProbesTheLayoutAConstantNumberOfTimes` sweeps
`[Double.infinity, 40.0, 10.0, 4.0]` over an 8-cell/advance-1.0 fixture (a line 8.0 wide), so
any width `>= 8.0` — three of the four swept values — is the unwrapped regime under another
name; only `4.0` genuinely wraps. Harmless for what this particular pin measures (the layout
probe count is flat regardless of width — see the test's own scope note), but it reads as a
four-regime sweep and is really two, which is exactly the coincidence its sibling
`DocumentVisualRowCursorProbeCountTests.testDrainProbesDoNotGrowWithTheDocument` hit for real
(G21, §7.6) and now guards against with an explicit fixture assertion. Recorded in this
record's §7.6 already, but not in the test file itself, where a reader will actually meet it —
a one-line comment noting the coincidence has now been added directly to
`WrapComputeProbeCountTests.swift`. Trigger to revisit: adding a fixture guard here too, or
reshaping the fixture so the four widths are genuinely four regimes.

## 8. Controller rulings made during execution

Eleven rulings, listed here in the order they were made; the full text of each is in the SDD
ledger (`.superpowers/sdd/2026-09-04-wrap-memory-shape/progress.md`, gitignored). Several
correct the plan or the spec, which is why they belong in the record and not only in the
session.

**Count reconciliation, since a mechanical check of this section reads a different number.**
`grep -c "Ruling:" .superpowers/sdd/2026-09-04-wrap-memory-shape/progress.md` returns **nine**,
not eleven — and the gap is not a miscount, it is two different things being counted. This
list is a **selective account of the load-bearing decisions**, not a literal rendering of that
grep. Of the eleven items: eight are among the nine ledger lines tagged exactly `Task N:
Ruling:` (the string the grep matches); items 1 and 2 are two decisions made *before* any task
was dispatched, logged in the ledger as `Ruling 1 —` and `Ruling 2 —` — no colon after
`Ruling`, so the grep does not see them; item 6 is a third pre-dispatch decision, logged as
`Task 3: Ruling (pre-dispatch):`, which the same grep misses for the same reason (the colon
sits after `(pre-dispatch)`, not after `Ruling`). That accounts for all eleven (8 + 2 + 1). The
ninth `Ruling:`-tagged ledger line — Task 9's endorsement that the implementer's own catch of
D-38 should be discharged — is deliberately not one of the eleven: it added no correction of
its own to the plan or the spec, and is folded into §2's Task 9 account instead.

1. **Pre-flight, Task 3.** `testTheWalkMustCostSomething`'s fixture as planned mutates an
   element whose constructor defaults *also* breach the `<= 32` shape bound, so the function
   returns three names against the test's two-name expectation — the test would fail on a
   healthy implementation. Mutate `set[0]` (100k / width ∞) to `point: 95` instead, which
   violates invariant 11 and nothing else, leaving the plan's expected array exactly as
   written. It is also the more faithful model of the failure it stands for: an uncounted
   walk makes every width report the same cost.
2. **Pre-flight, Task 7.** No `workflowLines()` accessor exists; add one beside `jobLines`
   rather than inlining a second read (§7.8).
3. **Task 1.** The plan's `visualRowCount > 0` assertion is false against the shipped core;
   keep the corrected `== 0` measurement **and** add a direct witness, so the hook stays
   falsifiable without claiming the core calls it (§7.2).
4. **Task 1.** Leave the plan document's false line uncorrected; the correction lives in the
   test comment and in this record. A plan is evidence about what was believed at planning
   time; a spec amendment (Task 3 Step 1) is a different case, because it changes a contract
   later code is written against.
5. **Task 2.** Drill (e) is defective as planned; re-run it with
   `lineCount: range.bufferEndExclusive - 1` and record the honest scope note the finding
   earns (§7.3).
6. **Pre-flight, Task 3.** The plan's Step 8 fingerprint script is broken and would not
   compile; replace `git checkout main -- .` with a throwaway worktree (§7.5).
7. **Task 3.** Drills (k), (l), (n) are fixture mismatches, not defects in the repair; fix
   (k) by drilling the real idiom, (l) by adding a first-element case to the shipped test,
   (n) by isolating the fixture (§7.4).
8. **Task 4.** `testDrainProbesDoNotGrowWithTheDocument`'s two widths are the same regime;
   switch to 4.0 and add a fixture guard (§7.6).
9. **Task 6.** Drill (u) cannot separate the derived constant from the transcribed one;
   replace it, and when the replacement also fails to separate them, shrink the sample gap
   rather than the cells per row (§7.7).
10. **Task 6.** Fix the stale `absoluteCeiling` comment here rather than deferring it: it is
    the exact sentence D-20's ledger row cites, and this slice flips D-20 to discharged.
11. **Task 8.** D-15's contract is falsified; revert the three dispatcher edits, keep D-14
    whole, and record the falsification as a new ledger row (§7.1).

Two further rulings were made pre-flight and produced no correction to the plan (Ruling 3's
double-printed `touched_lines`/`provider_lines` token, and Ruling 4's constraint that
`variableCoreOwnedBytesEstimate()` must not be re-typed by the counting wrapper, both in the
SDD ledger); they are named here only so the count in this section is not read as the whole
list of decisions taken.

## 9. Plan linter, and the ledger's own shape

```
$ ./.github/scripts/lint-plan-assertions.sh
lint_exit=0
lint=pass files=2 violations=0

$ ./.github/scripts/lint-plan-assertions.sh --self-test
selftest_exit=0
self_test=pass
```

Two files: slice 56's plan and this slice's, both non-exempt. This slice's plan therefore
passes the very step Task 5 strengthened — and the self-test line above is the half that step
did not previously run on a docs-only PR, which is D-43's whole content.

```
$ swift test --filter DebtLedgerShapeTests
	 Executed 5 tests, with 0 failures (0 unexpected)
```

Run after the ledger edits of this slice, which add three rows (D-45, D-46, D-47) and edit
nine existing rows — verified against `git diff 404feb8..ea1a5dd -- docs/superpowers/debt-ledger.md`:
eight flip `open` -> `discharged` (D-10, D-11, D-14, D-19, D-20, D-21, D-38, D-43) and one,
D-15, is amended in place with its status left `open`. The shape guard catches a raw `|`
inside a code span in a table cell — the character a row quoting `run_self_test || exit 1`
invites, and D-47 quotes it twice.

## 10. Hosted evidence — RESERVED, NOT YET DISCHARGED

**This section is deliberately empty.** AC10 requires step-level readings from **both**
halves — the PR-head run and the post-merge `push` run — and neither exists at the time this
record is written. A green job conclusion is not evidence
(`verify-ci-step-logs-not-job-conclusion`): the readings to take are the twelve gates'
`gate=pass` lines, `Lint plan assertions` printing **both** `self_test=pass` and
`lint=pass files=2 violations=0`, `--memory-shape` printing **eleven** lines all
`invariant=pass`, and the host job's `swift test` reporting 0 failures.

When those runs exist, they are recorded as a per-head **commit → run id** table rather than
as a bare run id, because a bare run id is a fact about "the current HEAD" and the next commit
falsifies it:

| Head commit (SHA) | Event | Run id | Step-level readings |
|---|---|---|---|
| *(pending)* | `pull_request` | *(pending)* | *(pending)* |
| *(pending)* | `push` to `main` | *(pending)* | *(pending)* |

Per `AGENTS.md`'s "A record cannot carry facts about its own branch", the post-merge half is
written on a separate `slice-57-hosted-proof` branch, as slices 54, 55a, 55b and 56 did.
