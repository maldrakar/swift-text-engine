# Slice 50 verification — wrap-aware viewport compute over visual rows (wrap node 2)

Branch `slice-50-wrap-viewport-compute`, on top of `main`. Commits on this
branch before this task (Tasks 1-5, already landed):

- `2875979` — docs: record Slice 50 selection (wrap node 2) in arc decision log
- `1a1db88` — docs: slice 50 wrap-viewport-compute design (node 2)
- `f7bcd25` — docs: revise slice 50 design per spec review (round 1)
- `5aa70fa` — docs: slice 50 wrap-viewport-compute TDD implementation plan (node 2)
- `aebb49c` — feat: VisualRowLayoutSource contract + binary-search inverse + test conformers (Task 1)
- `6a2b93c` — feat: compute(_:layout:) wrap-aware viewport compute over visual rows (Task 2)
- `654bf27` — feat: DocumentVisualRowCursor streams placed visual rows over the buffer range (Task 3)
- `a61b958` — docs: correct makeInner precondition comment (trusted interior metrics, not compute-validated)
- `bbcb648` — feat: Decision-6 validation ladder on compute(_:layout:) (wrap-coherent errors) (Task 4)
- `e58c987` — feat: --wrap-compute observational width-change demonstration (not gateable) (Task 5)

This task (Task 6) is documentation + the full verification record — no
source changes.

This slice (node 2 of the wrap arc) adds cross-line aggregation on top of
node 1's (Slice 49) per-logical-line row packing: `VisualRowLayoutSource` (the
visual-row axis: `lineCount` + `rowHeight` + `wrapWidth` +
`visualRowCount`/`firstVisualRow` prefix sum + `logicalLine(containingVisualRow:)`
inverse), `ViewportVirtualizer.compute(_:layout:)` (the third `compute`
overload, returning a `VirtualRange` of **visual-row** indices by reusing the
proven variable compute over a synthesized uniform row axis),
`DocumentVisualRowCursor`/`visualRowGeometry(for:layout:)` (streaming
`VisualRowGeometry` — `VisualRow` + `y` + `height` — over the buffer range,
O(1) core memory), and the observational `--wrap-compute` benchmark
demonstrating the width-change cost. The wrap width is baked into the
provider; the core never re-walks the document on a width change. No engine
behavior outside the new wrap-compute surface changed — the no-wrap
`compute`/query methods, all providers, and all gate budgets are untouched.

---

## 1. AGENTS.md updates (Step 1)

Three edits, all additive:

1. A new paragraph inserted immediately after the node-1 soft-wrap paragraph
   (the one ending "...O(1) core memory, O(cells-in-row) per `next()`.") and
   before `## Package layout`, describing node 2's `VisualRowLayoutSource`
   contract, `compute(_:layout:)` as the third `compute` overload, the
   `visualRowGeometry` streaming cursor, width-baked-into-the-provider, the
   whole-document infinite-width equivalence oracle, and the documented
   O(rowInLine) within-line boundary.
2. `## Commands` gained:
   ```
   swift run -c release ViewportBenchmarks -- --wrap-compute   # observational wrap compute width-change demo (not gateable)
   ```
3. The "Benchmark flags" list gained `--wrap-compute` in the flag enumeration,
   and the **rejected**-with-`--gate` list now reads
   `--range-only`, `--memory-shape`, `--memory-observation`, `--wrap-compute`
   (was missing `--wrap-compute` before this task).

No other AGENTS.md content was touched.

## 2. Full core-change verification suite (Step 2)

### 2a. `swift test` — full suite, 359 tests, 0 failures

```
$ swift test 2>&1 | tail -5
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-07-24 11:37:25.831.
	 Executed 359 tests, with 0 failures (0 unexpected) in 4.290 (4.310) seconds
Test Suite 'All tests' passed at 2026-07-24 11:37:25.831.
	 Executed 359 tests, with 0 failures (0 unexpected) in 4.290 (4.311) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

The trailing "0 tests in 0 suites" line is the empty Swift Testing harness,
not a failure, per AGENTS.md's package-layout note.

**New test counts by file this slice** (Tasks 1-4's TDD steps):

| Test file | Tests |
|---|---|
| `VisualRowLayoutSourceTests` | 2 |
| `WrapComputeEquivalenceTests` | 3 |
| `WrapComputeOptionsTests` | 4 |
| `WrapComputeTests` | 6 |
| `WrapComputeValidationTests` | 11 |
| **New total** | **26** |

**359 = Slice 49's baseline (333) + 26 new node-2 tests.**

### 2b. `swift build -c release` — succeeds

```
$ swift build -c release 2>&1 | tail -2
[0/1] Planning build
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build complete! (0.10s)
```

### 2c. `swift run -c release ViewportBenchmarks -- --gate` — `gate=pass` (unchanged; no new gated mode)

```
$ swift run -c release ViewportBenchmarks -- --gate 2>&1 | tail -3
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1229 p99_ns=1322 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=17.1x headroom_p99=31.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1260.7x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5015 p99_ns=5220 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=16.7x headroom_p99=32.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=319.3x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16553 p99_ns=16935 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=16.9x headroom_p99=33.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=98.4x gate=pass checksum=18852477646272000
```

All three synthetic scenarios `gate=pass`; checksums are byte-identical to
prior slices' (`1319670707200` / `570448232307200` / `18852477646272000`) —
this slice added no new gated benchmark mode, and the no-wrap synthetic
pipeline is untouched.

### 2d. `swift run -c release ViewportBenchmarks -- --wrap-compute` — three `mode=wrap_compute` lines

Fresh run captured for this task (macOS, local):

```
$ swift run -c release ViewportBenchmarks -- --wrap-compute
mode=wrap_compute width=inf total_rows=100000 compute_p95_ns=208 compute_p99_ns=209 drain_p95_ns=14875 reindex_ns=16284708
mode=wrap_compute width=40 total_rows=200000 compute_p95_ns=208 compute_p99_ns=209 drain_p95_ns=8959 reindex_ns=18139167
mode=wrap_compute width=10 total_rows=800000 compute_p95_ns=209 compute_p99_ns=250 drain_p95_ns=5125 reindex_ns=25945417
```

Task 5's originally recorded set (kept here as the reference story; the two
sets differ only by ordinary run-to-run noise, not by any code change between
them — no source files changed on this branch since `e58c987`):

```
mode=wrap_compute width=inf total_rows=100000 compute_p95_ns=209 compute_p99_ns=209 drain_p95_ns=17875 reindex_ns=34822916
mode=wrap_compute width=40 total_rows=200000 compute_p95_ns=167 compute_p99_ns=208 drain_p95_ns=9375 reindex_ns=18815667
mode=wrap_compute width=10 total_rows=800000 compute_p95_ns=208 compute_p99_ns=209 drain_p95_ns=4875 reindex_ns=24746750
```

**Reading these numbers (spec Point 4 — do NOT call `compute` "flat /
width-independent"):** `total_rows` grows 100k -> 200k -> 800k as the width
narrows (∞ -> 40 -> 10), because a narrower width means more visual rows per
logical line at the same 100k-line/80-cell fixture. `compute_p95_ns` is
**viewport-bounded** and grows only as **O(log totalRows)** across that
range — a couple of extra binary-search steps over the reused uniform axis
(~17 vs ~20 iterations at the two ends) — so it stays flat within noise
(167-209 ns across both runs above), **not** literally width-independent; a
slightly slower narrow-width sample (e.g. the fresh run's 208-209 ns vs Task
5's 167-208 ns at width=40) is exactly that noise, not a regression. The
`reindex_ns` column (16.3-34.8 ms across both runs) is the provider's O(N)
prefix-sum rebuild — the **measured setup cost** of a width change — and it
is what the O(N) work is; a width change never re-walks the document inside a
per-frame `compute`/cursor call. `drain_p95_ns` (the buffer-range cursor
drain) also stays in the single-digit-microsecond range across widths,
consistent with its O(buffer) cost class being independent of `total_rows`.

### 2e. Foundation-free scan — empty

```
$ rg -n "Foundation" Sources/TextEngineCore ; echo "rg exit: $?"
rg exit: 1
```

`rg` exit code 1 = no matches (ripgrep convention); no output printed.
`Sources/TextEngineCore` — including the new `VisualRowLayoutSource.swift`,
`WrapViewportVirtualizer.swift`, and `DocumentVisualRowCursor.swift` — remains
Foundation-free.

## 3. Cross-target compile (Step 3 — portability-sensitive: new public API)

### 3a. iOS — device + simulator, both packages, `result=pass`

```
$ ./.github/scripts/cross-target-compile.sh --targets ios 2>&1 | tail -20
cross_target_swift_version=6.2.4
cross_target_developer_dir=unset
cross_target_xcode_select_path=/Applications/Xcode_26_3.app/Contents/Developer
cross_target_xcodebuild_version=Xcode 26.3;Build version 17C529
cross_target_iphoneos_sdk_version=26.2
cross_target_iphonesimulator_sdk_version=26.2
mode=cross_target_compile target=ios_device package=core result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator package=core result=pass reason=none blocking=true
mode=cross_target_compile_summary package=core ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile target=ios_device package=providers result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator package=providers result=pass reason=none blocking=true
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

Both `TextEngineCore` and `TextEngineReferenceProviders` compile clean for
iOS device + simulator, exercising the new `VisualRowLayoutSource` protocol,
`compute(_:layout:)`, `VisualRowGeometry`, and `DocumentVisualRowCursor<Layout>`
public surface under the real iOS SDK.

### 3b. WASM — attempted locally, deferred to hosted CI (honest, not faked)

The local toolchain is `swift-driver version: 1.127.15 Apple Swift version
6.2.4`, not the `6.2.1` the pinned SDK resolves against (per AGENTS.md's
"Local WASM build" note: "the resolver matches an installed SDK id against
the local toolchain version... only resolves on a 6.2.1 toolchain"). `swift
sdk list` does show `swift-6.2.1-RELEASE_wasm` / `swift-6.2.1-RELEASE_wasm-embedded`
installed locally, but on this 6.2.4 toolchain they do not resolve — attempting
the compile fails closed exactly as documented, not silently:

```
$ ./.github/scripts/cross-target-compile.sh --targets wasm 2>&1 | tail -12
cross_target_swift_version=6.2.4
mode=cross_target_compile target=wasm package=core result=fail reason=sdk_unavailable blocking=true
mode=cross_target_compile target=wasm_embedded package=core result=fail reason=sdk_unavailable blocking=true
mode=cross_target_compile_summary package=core ios_device=skipped ios_simulator=skipped wasm=fail wasm_embedded=fail
mode=cross_target_compile target=wasm package=providers result=fail reason=sdk_unavailable blocking=true
mode=cross_target_compile target=wasm_embedded package=providers result=fail reason=sdk_unavailable blocking=true
mode=cross_target_compile_summary package=providers ios_device=skipped ios_simulator=skipped wasm=fail wasm_embedded=fail
mode=cross_target_compile_overall blocking_failures=4 exit=1
```

This is the documented toolchain-version mismatch behavior, not a broken
checkout or an engine regression — it is not forced past. **WASM + embedded
WASM compile verification for this slice's new public API is deferred to the
hosted `swift:6.2.1-bookworm` CI job**, which resolves the pinned SDK
correctly (see the Hosted CI section below for run IDs once available).

## 4. Recorded reds (falsifiability evidence carried from Tasks 2-3)

### 4a. The Task 2 aggregation red — `compute(_:layout:)` stub using `lineCount`, not `totalRows`

Per the spec's Decision 7 falsifiability discussion, the whole-document `∞`
range equivalence is tautology-prone by itself: at `∞` width,
`totalRows == lineCount`, so a stub `compute(_:layout:)` that ignored the wrap
inflation would still pass the `∞` range comparison. The genuine discriminating
red therefore has to come from a **finite** width, where wrapping actually
inflates `totalRows` above `lineCount`.

Task 2's TDD step implemented exactly that stub first:

```swift
public static func compute<Layout: VisualRowLayoutSource>(
    _ input: VariableViewportInput, layout: Layout
) -> ViewportComputation {
    // STUB (recorded red): uses lineCount, NOT totalRows.
    return compute(input, metrics: UniformLineMetrics(lineCount: layout.lineCount, lineHeight: layout.rowHeight))
}
```

against a 4-logical-line fixture (each line 4 cells, breaking every cell,
`wrapWidth: 20.0` -> 2 rows/line, so `totalRows = 8`, not `lineCount = 4`).
`WrapComputeEquivalenceTests` (the `∞`-width oracle) and
`testFiniteWidthVisibleRangeIsInVisualRows` (top-of-document, where the stub
and the real code coincide) **passed** against the stub — confirming the `∞`
coincidence does not discriminate. `WrapComputeTests.testScrollToBottomIsInVisualRows`
**FAILED**: the stub computed over 4 pseudo-lines of total height 20 (so
`visibleEndExclusive` came out wrong against the height-40/8-row document the
test expects), while the assertion expected the real 8-row range
(`XCTAssertEqual(range.visibleEndExclusive, 8)`), reporting `"4" is not equal
to "8"`. This is the aggregation's honest recorded red (spec Decision 7).
Replacing the stub body with
`let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)` (commit
`6a2b93c`) turned the full `WrapCompute*` suite green.

### 4b. The Task 3 D-12 mutation — node 1's `greedyEnd` inclusive boundary

`WrapComputeTests.testInteriorExactEqualWidthBoundary` fixes a break landing
**exactly** at `wrapWidth` (`columnOffset(2) - startOffset == 20 == wrapWidth`,
3 cells of advance 10, breaks at columns 1 and 2) and asserts the row keeps
both cells: `rows[0].endColumn == 2`, `rows.count == 2`.

Per the plan's Task 3 Step 6, node 1's `greedyEnd` fit comparison in
`Sources/TextEngineCore/VisualRowCursor.swift` (the `<=` at line 65,
`metrics.columnOffset(inLine: line, column: c) - startOffset <= wrapWidth`)
was temporarily flipped to `<`, and
`swift test --filter testInteriorExactEqualWidthBoundary` was re-run:

- **With the mutation (`<`):** FAILED — `row[0].endColumn` came out `1`
  (not `2`) and `rows.count` came out `3` (not `2`): the exact-fit break was
  excluded from the row instead of kept on it.
- **After reverting to `<=`:** PASSED — back to `row[0].endColumn == 2`,
  `rows.count == 2`.

The mutation was never committed: `git diff 5aa70fa e58c987 --
Sources/TextEngineCore/VisualRowCursor.swift` (spanning every commit on this
branch) is empty, and `git log --oneline -- Sources/TextEngineCore/VisualRowCursor.swift`
shows the file's last change predates this slice (commit `0d2f258`, Slice
49) — confirmed for this task via:

```
$ grep -n "<=" Sources/TextEngineCore/VisualRowCursor.swift
51:    // The largest legal end `e > start` with `columnOffset(e) - startOffset <=
61:        while c <= columnCount {
65:                if metrics.columnOffset(inLine: line, column: c) - startOffset <= wrapWidth {
104:            if !total.isFinite || total <= 0.0 {
```

`VisualRowCursor.swift` is byte-identical to base in this branch's committed
history; the D-12 mutation was a throwaway local edit, reverted before
committing Task 3. This is the oracle/boundary falsifiability evidence for AC6: the dedicated
finite-width fixture `testInteriorExactEqualWidthBoundary` (a break landing
exactly at `wrapWidth`) reddens under the mutation, as recorded above. Note
that the `∞`/large-width equivalence oracle's row-streaming half does **not**
catch this mutation: at `wrapWidth = ∞` the fit test compares a finite advance
against `+∞`, so both `<` and `<=` accept and the one-row-per-line packing is
unchanged — `testInfiniteWidthStreamsOneRowPerLine` stays green under the flip.
The finite-width D-12 fixture is the real discriminator. (The spec's Decision 7
point 2 makes the same over-claim about the `∞` streaming half; that ratified
design doc is left as-is here, flagged for a separate correction.)

## 5. Diff scope vs `main`

```
$ git log --oneline main..HEAD
e58c987 feat: --wrap-compute observational width-change demonstration (not gateable)
bbcb648 feat: Decision-6 validation ladder on compute(_:layout:) (wrap-coherent errors)
a61b958 docs: correct makeInner precondition comment (trusted interior metrics, not compute-validated)
654bf27 feat: DocumentVisualRowCursor streams placed visual rows over the buffer range
6a2b93c feat: compute(_:layout:) wrap-aware viewport compute over visual rows
aebb49c feat: VisualRowLayoutSource contract + binary-search inverse + test conformers
5aa70fa docs: slice 50 wrap-viewport-compute TDD implementation plan (node 2)
f7bcd25 docs: revise slice 50 design per spec review (round 1)
1a1db88 docs: slice 50 wrap-viewport-compute design (node 2)
2875979 docs: record Slice 50 selection (wrap node 2) in arc decision log

$ git diff --stat main HEAD
 .../TextEngineCore/DocumentVisualRowCursor.swift   |   74 ++
 Sources/TextEngineCore/ViewportTypes.swift         |   18 +
 Sources/TextEngineCore/VisualRowLayoutSource.swift |   59 ++
 .../TextEngineCore/WrapViewportVirtualizer.swift   |   24 +
 Sources/ViewportBenchmarks/BenchmarkOptions.swift  |   17 +-
 Sources/ViewportBenchmarks/BenchmarkProgram.swift  |    2 +
 .../ViewportBenchmarks/SyntheticBenchmarks.swift   |    2 +
 .../ViewportBenchmarks/WrapComputeBenchmark.swift  |  108 ++
 .../VisualRowLayoutSourceTests.swift               |   35 +
 .../VisualRowLayoutTestSupport.swift               |   72 ++
 .../WrapComputeEquivalenceTests.swift              |   66 ++
 Tests/TextEngineCoreTests/WrapComputeTests.swift   |  102 ++
 .../WrapComputeValidationTests.swift               |   53 +
 .../WrapComputeOptionsTests.swift                  |   20 +
 docs/superpowers/arcs/wrap.md                      |   39 +-
 .../plans/2026-07-24-wrap-viewport-compute.md      | 1118 ++++
 .../2026-07-24-wrap-viewport-compute-design.md     |  710 +++
 17 files changed, 2510 insertions(+), 9 deletions(-)
```

(This verification doc and the AGENTS.md edit are added by this task's own
commit, immediately after this listing was captured.)

No existing gate script, corpus, or budget-literal path is touched — the new
surface (`VisualRowLayoutSource`, `VisualRowGeometry`, `compute(_:layout:)`,
`DocumentVisualRowCursor`, `visualRowGeometry`, `--wrap-compute`) is purely
additive to `Sources/TextEngineCore` and `Sources/ViewportBenchmarks`,
alongside its tests and this slice's docs.

## 6. Final clean-tree confirmation

```
$ git status --short
```

Clean immediately before this verification doc + `AGENTS.md` were staged for
this task's commit.

---

## Hosted CI

**PR: [#117](https://github.com/maldrakar/swift-text-engine/pull/117)** (base
`main`, head `slice-50-wrap-viewport-compute`). Per repo convention, hosted
proof is read at **step** level, not job conclusion (a green job can hide a
dead `continue-on-error` step — the Slice 16 dead-step trap), and merged proof
must be anchored in the **post-merge push run**, not just the PR-head run.

**PR-head run is DISCHARGED at step level. Post-merge push run is pending the
merge** (to be filled from the post-merge `push`-to-`main` run, following the
pattern of every prior slice's verification record).

The PR-head evidence below was read from `gh run view 30084403436 --json jobs`:
the query `.jobs[].steps[] | select(.conclusion != "success" and .conclusion
!= "skipped")` returned **empty** — every step in all three required jobs is
`success` or `skipped`, so no step was swallowed by `continue-on-error`.

| | PR-head run | Post-merge push run |
|---|---|---|
| Run ID / commit | **`30084403436`** @ `e1d8df9` | **TBD** (after merge) |
| Trigger | `pull_request` | `push` to `main` |
| Three required jobs (step level) | **PASS** — Host tests and benchmark gate, iOS cross-target compile, WASM cross-target compile all `success` at step level (no non-success/non-skipped step in any job) | **TBD** — same three jobs |
| `Complete docs-only PR` step | **`[skipped]`** in all three jobs (correct — this PR touches `Sources/`, so the heavy path ran) | **TBD** |
| Twelve blocking gate steps | **all `success` (`gate=pass`)** — synthetic, variable-height, variable-height-mutation, structural-mutation, bulk-structural-mutation, line-query, line-geometry-query, column-query, column-geometry-query, point-query, point-geometry-query, realistic-provider (unchanged budgets — this slice adds no new gated mode) | **TBD** |
| Host tests (`Run host tests` step) | **`success`** (the 359/0 suite) | **TBD** |
| iOS cross-target compile step | **`success`** (blocking; both packages, device+simulator) | **TBD** |
| WASM cross-target compile step | **`success`** (blocking; hosted pinned-6.2.1 SDK — local attempt deferred per Section 3b) | **TBD** |

Note: committing this evidence to the PR branch retriggers a second PR-head
run on the docs commit (expected — strict required-status-checks bind the merge
to the latest commit); that run is the one the merge gates on and is expected
green for the same reasons. The **post-merge push run** column is filled after
the user merges, anchoring the merged proof (its creation can lag ~13 min after
the merge — do not mistake the lag for a skip).
