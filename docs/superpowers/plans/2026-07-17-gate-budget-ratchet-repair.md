# Gate Budget Ratchet Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `3× max` gate-budget floor two-way by deriving `median`/`max` over a trailing window of the most-recent N=20 distinct hosted runs instead of all corpus history, applied identically in both consumers and pinned by a cross-language test.

**Architecture:** Two consumers read the append-only corpus TSV: `derive-gate-budgets.sh` (awk) and `GateFloorTests.swift`. Both gain the *same* window — the N most-recent distinct run ids, keyed on the integer run id (`sort -rnu | head -N` in shell, `Set(ids).sorted(by:>).prefix(N)` in Swift). The corpus file stays full-history append-only; the window is applied only at read time, so N is a re-tunable knob with no data loss. No engine or provider code changes; only calibration machinery and its evidence move.

**Tech Stack:** Bash + awk (derive script), Swift 6.0 / XCTest (`ViewportBenchmarks` test target), the committed corpus TSV, `gh` CLI (harvest only).

## Global Constraints

_Every task's requirements implicitly include this section. Values copied verbatim from the spec (`docs/superpowers/specs/2026-07-17-gate-budget-ratchet-repair-design.md`)._

- **Zero engine/provider diff.** `git diff --name-only` must show **no path under `Sources/TextEngineCore` or `Sources/TextEngineReferenceProviders`** (AC2). Expected diff there: zero lines.
- **Foundation stays test-target-only.** `rg -n "Foundation" Sources/TextEngineCore` → empty. `GateFloorTests.swift` may import Foundation (it already does, to read files); `Sources/ViewportBenchmarks` stays Foundation-free.
- **Zero-dependency.** No YAML/TSV parser added. Hand-rolled narrow readers only, as `WorkflowShapeTests` and the current `GateFloorTests` already do.
- **Byte-identical checksums.** Every gated mode's query/mutation checksum must be **byte-identical** to the Slice 40 baseline (AC4) — the proof the calibration change moved no measured path.
- **One documented N.** `WINDOW=20` (shell) and `windowSize = 20` (Swift) must agree, stated once in `AGENTS.md` and pinned by a standing test. The run-id key is pure integer arithmetic — no timestamps, no Foundation, no Embedded strain.
- **Derived, never hand-typed.** Every committed budget literal must reproduce byte-for-byte from `derive-gate-budgets.sh <corpus>` (windowed) after the harvest. Sweep **all** modes, commit whatever `derive` prints.
- **Corpus is append-only.** The run id is its dedup key; rows are never removed or reordered. The window is a read-time filter, not a pruning of the file.
- **TDD, one logical step per commit**, conventional-commit prefixes (`feat:`/`test:`/`refactor:`/`docs:`/`ci:`). Branch: `slice-41-gate-budget-ratchet-repair` (already checked out).

---

## File Structure

| Path | Responsibility | Change |
| --- | --- | --- |
| `.github/scripts/derive-gate-budgets.sh` | Corpus → windowed budgets; owns `WINDOW=20`, the `window_run_ids()` selector, and a `--self-test` | Modify |
| `Tests/ViewportBenchmarksTests/GateFloorTests.swift` | Holds budgets to `3× windowed max`; owns `windowSize = 20`, `mostRecentRunIDs`, the testable `corpusExtremes(from:windowSize:)`, and the `WINDOW`/`windowSize` pin test | Modify |
| `Sources/ViewportBenchmarks/*Benchmark.swift`, `SyntheticBenchmarks.swift` | Budget literals (data only) | Modify (re-derived values) |
| `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` | Hosted evidence, append-only | Append one run |
| `AGENTS.md` | `## Gate budgets` window doc + `GateFloorTests` description + `Tests/ViewportBenchmarksTests` file list (P3 #1) | Modify |
| `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` | Comment fix only (P3 #2) | Modify (comment) |
| `docs/superpowers/verification/2026-07-17-gate-budget-ratchet-repair.md` | Verification record | Create |

**Ordering rationale (why tasks are sequenced this way):** the window machinery (Tasks 1–2) must exist before the corpus can be re-derived under it (Task 4). Windowing the floor test *before* re-deriving is safe: the windowed max is `≤` the all-history max, and the committed budgets were derived to clear `3×` the all-history max, so they still clear `3×` the windowed max — no red between Task 2 and Task 4. The pin test (Task 3) needs both constants present. Harvest + re-derive land together (Task 4) so no intermediate `budget_stale` state exists.

---

### Task 1: Trailing window in `derive-gate-budgets.sh` + `--self-test`

**Files:**
- Modify: `.github/scripts/derive-gate-budgets.sh`

**Interfaces:**
- Produces: `WINDOW=20` (a top-of-file shell assignment the pin test in Task 3 reads by `hasPrefix("WINDOW=")`); `window_run_ids [N]` (corpus on stdin → top-N distinct run ids, one per line, `sort -rnu` order); `--self-test` (pure, no network).
- Consumes: the corpus TSV `run_id<TAB>mode<TAB>scenario<TAB>p95_ns<TAB>p99_ns`.

**Semantics of the window:** `window_run_ids` = `tail -n +2 | cut -f1 | sort -rnu | head -n N`. `sort -rnu` = reverse-numeric-unique → distinct run ids, largest (newest, since GitHub `databaseId` is monotonic) first. This must be **byte-identical in meaning** to Task 2's Swift `mostRecentRunIDs`.

- [ ] **Step 1: Add `WINDOW=20`, the `window_run_ids` selector, and a `--self-test` that asserts the selection**

Insert immediately after `set -euo pipefail` (line 17), *before* the `corpus=` line. This block defines the constant, the pure selector, and the self-test, then dispatches `--self-test` early (mirroring `harvest-gate-corpus.sh`):

```bash
# Trailing window: derive median/max over the most-recent N distinct runs only,
# not all corpus history, so an aged-out freak sample can release the budget it
# inflated. N is the single documented value in AGENTS.md "## Gate budgets" and is
# pinned to GateFloorTests.swift's `windowSize` by a test. Keep this a bare
# top-of-file `WINDOW=<int>` assignment: that test reads it by line prefix.
WINDOW=20

# Corpus on stdin (WITH header) -> its N most-recent distinct run ids, newest first.
# `sort -rnu` = reverse numeric unique: GitHub databaseId is monotonic with run
# creation, so numeric-descending IS recency-descending. This is the exact window
# GateFloorTests.mostRecentRunIDs computes in Swift; the two must not drift.
window_run_ids() {
  local n="${1:-$WINDOW}"
  tail -n +2 | cut -f1 | sort -rnu | head -n "$n"
}

assert_equal() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "self_test=fail label=$label"
    echo "  expected: [$expected]"
    echo "  actual:   [$actual]"
    exit 1
  fi
}

run_self_test() {
  local fixture
  fixture="$(mktemp)"
  # Run ids out of chronological order on purpose: physical row order must not
  # matter, only the numeric ranking. Run 305 has two rows (a realistic_provider
  # run genuinely does) -- the run id, not the row, is the unit of recency.
  printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n' > "$fixture"
  printf '100\tline_query\tuniform_1k\t24\t54\n'   >> "$fixture"
  printf '305\tline_query\tuniform_1k\t30\t60\n'   >> "$fixture"
  printf '305\tline_query\tuniform_1m\t31\t61\n'   >> "$fixture"
  printf '210\tline_query\tuniform_1k\t28\t58\n'   >> "$fixture"
  printf '99\tline_query\tuniform_1k\t22\t52\n'    >> "$fixture"

  assert_equal "305
210" "$(window_run_ids 2 < "$fixture")" "keeps the 2 most-recent distinct run ids"

  # N >= distinct-run-count is a no-op: keep them all, still newest-first.
  assert_equal "305
210
100
99" "$(window_run_ids 10 < "$fixture")" "keeps all runs when N exceeds the run count"

  rm -f "$fixture"
  echo "self_test=pass"
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi
```

- [ ] **Step 2: Run the self-test to verify it passes**

Run: `./.github/scripts/derive-gate-budgets.sh --self-test`
Expected: `self_test=pass`

(To confirm the guard is live — the "red" for a shell selector — temporarily change `head -n "$n"` to `head -n 1`, re-run, observe `self_test=fail label=keeps the 2 most-recent...`, then revert.)

- [ ] **Step 3: Wire the window into the derivation via a process-substitution first file**

Change the single awk invocation at the bottom of the script. The current call is:

```bash
awk -F'\t' -v modes="$modes" '
  ...program...
' "$corpus" | sort
```

Replace the invocation line **and** add a `FNR==NR` first-file block plus a KEEP guard to the program. The kept run ids arrive as awk's *first* file via `<(window_run_ids < "$corpus")` — this sidesteps the `awk -v` newline-mangling that a newline-separated `-v` value triggers. Concretely:

1. Add these two lines to the program, immediately after the `med(...)` function definition and **before** `NR == 1 { next }`:

```awk
  FNR == NR { KEEP[$1] = 1; next }   # first file: the windowed run ids
  !($1 in KEEP) { next }             # skip the corpus header (id "run_id" is not in KEEP) and out-of-window rows
```

2. Delete the now-redundant `NR == 1 { next }` header line — the `!($1 in KEEP)` guard already drops the header, because `"run_id"` is never a kept numeric id.

3. Change the invocation's final line from `' "$corpus" | sort` to:

```bash
' <(window_run_ids < "$corpus") "$corpus" | sort
```

- [ ] **Step 4: Verify the windowed derivation still emits every gated scenario**

Run: `./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | wc -l`
Expected: `46` (no gated scenario is dropped — min windowed coverage is 11 runs, so every scenario still has rows).

Run: `./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | grep -E "line_geometry_query.uniform_1k|line_query.uniform_100k"`
Expected (sanity, pre-harvest windowed): `line_geometry_query|uniform_1k` shows `budget_p99=500` (was 990 all-history) and `line_query|uniform_100k` p95 margin lifted off 3.0× — the old freaks aged out. Exact numbers are re-derived in Task 4; this only confirms the window is engaged.

- [ ] **Step 5: Verify the mode-not-found error path still works**

Run: `./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv not_a_mode; echo "exit=$?"`
Expected: `error=no_corpus_rows mode=not_a_mode known=...` on stderr, `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add .github/scripts/derive-gate-budgets.sh
git commit -m "feat: window derive-gate-budgets over the most-recent N=20 runs

Add WINDOW=20, a pure window_run_ids() selector (sort -rnu | head -N), and
a --self-test. Feed the kept run ids into awk as a process-substitution
first file so the derivation ranges over the trailing window, not all
corpus history. No budget literal changes yet -- this only teaches the
script to window; re-derivation lands in a later commit."
```

---

### Task 2: Window `GateFloorTests` — `mostRecentRunIDs` helper + testable `corpusExtremes` + fixture unit tests

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift`

**Interfaces:**
- Produces: `windowSize: Int = 20` (file-scope `private let`, read by the Task 3 pin test); `mostRecentRunIDs(_ ids: [Int64], limit: Int) -> Set<Int64>`; `corpusExtremes(from text: String, windowSize: Int) -> [String: CorpusExtremes]` (pure, testable).
- Consumes: nothing new.

- [ ] **Step 1: Write the failing unit test for `mostRecentRunIDs`**

Add this test method to `final class GateFloorTests` (after the existing tests). It references `mostRecentRunIDs`, which does not exist yet:

```swift
    func testMostRecentRunIDsKeepsTopNByValue() {
        let ids: [Int64] = [100, 305, 210, 99, 305]   // 305 duplicated: distinct-by-value
        XCTAssertEqual(mostRecentRunIDs(ids, limit: 2), Set<Int64>([305, 210]))
        // limit >= distinct count is a no-op (keep all distinct ids)
        XCTAssertEqual(mostRecentRunIDs(ids, limit: 10), Set<Int64>([100, 305, 210, 99]))
        XCTAssertEqual(mostRecentRunIDs(ids, limit: 4), Set<Int64>([100, 305, 210, 99]))
        XCTAssertTrue(mostRecentRunIDs([], limit: 5).isEmpty)
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter GateFloorTests/testMostRecentRunIDsKeepsTopNByValue`
Expected: FAIL — compile error, `cannot find 'mostRecentRunIDs' in scope`.

- [ ] **Step 3: Implement `windowSize` and `mostRecentRunIDs`**

Add near the top of `GateFloorTests.swift`, right after the `floorFactor` / `corpusPath` constants:

```swift
// Trailing window: hold budgets to 3x the max over only the most-recent N distinct
// runs, not all corpus history, so an aged-out freak releases the budget it inflated.
// This N is the same value as WINDOW= in .github/scripts/derive-gate-budgets.sh and is
// pinned to it by testWindowConstantMatchesDeriveScript(); AGENTS.md documents the one N.
private let windowSize = 20

// The N most-recent run ids by value. GitHub databaseId is monotonic with run creation,
// so "largest N ids" is "most-recent N runs" -- the exact set `sort -rnu | head -N`
// produces in the derive script. Dedups first (a run contributes many rows).
func mostRecentRunIDs(_ ids: [Int64], limit: Int) -> Set<Int64> {
    Set(Set(ids).sorted(by: >).prefix(limit))
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter GateFloorTests/testMostRecentRunIDsKeepsTopNByValue`
Expected: PASS.

- [ ] **Step 5: Write the failing two-way-floor test (AC6) against a testable `corpusExtremes`**

Add this test. It references `corpusExtremes(from:windowSize:)`, which does not exist yet. It demonstrates the floor is **two-way**: with the freak in an out-of-window (old) run the windowed max drops back; with the freak recent it is retained.

```swift
    func testWindowedExtremesDropAnAgedOutFreak() {
        // Header + rows: run 500 (newest) is clean; run 100 (oldest) carries a freak.
        let corpus = """
        run_id\tmode\tscenario\tp95_ns\tp99_ns
        500\tline_query\tuniform_1k\t30\t60
        400\tline_query\tuniform_1k\t32\t64
        300\tline_query\tuniform_1k\t31\t62
        100\tline_query\tuniform_1k\t999\t999
        """
        // Window of 3 keeps {500,400,300}: the 999 freak in run 100 is aged out.
        let windowed = corpusExtremes(from: corpus, windowSize: 3)["line_query|uniform_1k"]
        XCTAssertEqual(windowed?.maxP95, 32)
        XCTAssertEqual(windowed?.maxP99, 64)
        // Window wide enough to still include run 100: the freak is (correctly) retained.
        let all = corpusExtremes(from: corpus, windowSize: 10)["line_query|uniform_1k"]
        XCTAssertEqual(all?.maxP95, 999)
        XCTAssertEqual(all?.maxP99, 999)
    }
```

- [ ] **Step 6: Run it to verify it fails**

Run: `swift test --filter GateFloorTests/testWindowedExtremesDropAnAgedOutFreak`
Expected: FAIL — compile error, `cannot find 'corpusExtremes' in scope`.

- [ ] **Step 7: Refactor `loadCorpus` into a pure `corpusExtremes(from:windowSize:)` that windows**

Replace the entire body of `loadCorpus()` (lines 34–57) with a thin file reader delegating to a pure, windowed function:

```swift
// key -> "<mode>|<scenario>", matching the derivation script's grouping exactly.
private func loadCorpus() throws -> [String: CorpusExtremes] {
    let url = repositoryRoot().appendingPathComponent(corpusPath)
    let text = try String(contentsOf: url, encoding: .utf8)
    return corpusExtremes(from: text, windowSize: windowSize)
}

// Pure so a fixture can exercise it. Two passes: collect distinct run ids, keep the
// most-recent `windowSize`, then fold only rows in that window into the extremes --
// the identical rule .github/scripts/derive-gate-budgets.sh applies in awk.
func corpusExtremes(from text: String, windowSize: Int) -> [String: CorpusExtremes] {
    struct Row { let runID: Int64; let key: String; let p95: Int64; let p99: Int64 }

    var rows: [Row] = []
    var runIDs: [Int64] = []
    for (index, line) in text.split(separator: "\n").enumerated() {
        if index == 0 { continue }  // header
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count == 5,
              let runID = Int64(columns[0]),
              let p95 = Int64(columns[3]),
              let p99 = Int64(columns[4]) else {
            XCTFail("malformed corpus row \(index + 1): \(line)")
            continue
        }
        runIDs.append(runID)
        rows.append(Row(runID: runID, key: "\(columns[1])|\(columns[2])", p95: p95, p99: p99))
    }

    let window = mostRecentRunIDs(runIDs, limit: windowSize)
    var extremes: [String: CorpusExtremes] = [:]
    for row in rows where window.contains(row.runID) {
        var entry = extremes[row.key] ?? CorpusExtremes()
        entry.maxP95 = max(entry.maxP95, row.p95)
        entry.maxP99 = max(entry.maxP99, row.p99)
        entry.sampleCount += 1
        extremes[row.key] = entry
    }
    return extremes
}
```

- [ ] **Step 8: Run the new tests and the full floor suite**

Run: `swift test --filter GateFloorTests`
Expected: PASS — all methods, including the two new ones. The existing `testEveryGatedBudgetClearsTheFloorOnBothStatistics` and `testEveryGatedScenarioHasCorpusEvidence` stay green: the windowed max is `≤` the all-history max (so the committed budgets still clear `3×` it), and every gated scenario keeps `≥ 11` windowed runs.

- [ ] **Step 9: Run the whole test target to confirm nothing else regressed**

Run: `swift test`
Expected: all tests pass (count = current 296 + 2 new = 298), 0 failures.

- [ ] **Step 10: Commit**

```bash
git add Tests/ViewportBenchmarksTests/GateFloorTests.swift
git commit -m "test: window GateFloorTests over the most-recent N=20 runs

Add windowSize=20 and mostRecentRunIDs (the Swift twin of the derive
script's sort -rnu | head -N). Refactor loadCorpus into a pure
corpusExtremes(from:windowSize:) that folds only in-window rows, and add
a fixture test showing the floor is two-way: an aged-out freak drops out
of the windowed max, a recent one is retained (AC6). Committed budgets
still clear the floor because windowed max <= all-history max."
```

---

### Task 3: The `WINDOW`/`windowSize` cross-language pin test

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift`

**Interfaces:**
- Consumes: `windowSize` (Task 2) and the top-of-file `WINDOW=` assignment (Task 1). Reuses `repositoryRoot()` already in the file.
- Produces: `testWindowConstantMatchesDeriveScript()` — the standing guard that the two Ns cannot silently diverge (Decision 3, closes the silent-pass direction the asymmetric self-guard cannot).

- [ ] **Step 1: Write the pin test**

Add to `final class GateFloorTests`. It hand-parses the shell script's `WINDOW=` line — no shell executed, no parser added, mirroring `WorkflowShapeTests`'s narrow reader:

```swift
    // Pins the ONE documented N across languages. derive-gate-budgets.sh computes the
    // window in awk, GateFloorTests in Swift; nothing else forces them equal. The
    // asymmetric self-guard (Decision 3) catches only test-N > derive-N; this catches
    // the silent-pass direction too. Reads the bare `WINDOW=<int>` assignment by prefix.
    func testWindowConstantMatchesDeriveScript() throws {
        let scriptURL = repositoryRoot()
            .appendingPathComponent(".github/scripts/derive-gate-budgets.sh")
        let text = try String(contentsOf: scriptURL, encoding: .utf8)

        let assignment = text.split(separator: "\n").first { $0.hasPrefix("WINDOW=") }
        guard let assignment else {
            XCTFail("derive-gate-budgets.sh has no top-level `WINDOW=` assignment for the "
                + "pin test to read")
            return
        }
        let digits = assignment.dropFirst("WINDOW=".count).prefix { $0.isNumber }
        guard let scriptWindow = Int(digits) else {
            XCTFail("could not parse an integer from `\(assignment)`")
            return
        }

        XCTAssertEqual(
            scriptWindow, windowSize,
            "WINDOW=\(scriptWindow) in derive-gate-budgets.sh disagrees with windowSize="
                + "\(windowSize) in GateFloorTests.swift — the two consumers would window "
                + "the corpus differently. Update AGENTS.md's one documented N and both sites.")
    }
```

- [ ] **Step 2: Run it to verify it passes on the agreeing constants**

Run: `swift test --filter GateFloorTests/testWindowConstantMatchesDeriveScript`
Expected: PASS (both are 20).

- [ ] **Step 3: Demonstrate the guard is live (red on mismatch, then revert)**

Temporarily edit `.github/scripts/derive-gate-budgets.sh`: change `WINDOW=20` to `WINDOW=21`.
Run: `swift test --filter GateFloorTests/testWindowConstantMatchesDeriveScript`
Expected: FAIL — `WINDOW=21 ... disagrees with windowSize=20`.
Revert: change `WINDOW=21` back to `WINDOW=20`. Re-run: PASS.

- [ ] **Step 4: Commit**

```bash
git add Tests/ViewportBenchmarksTests/GateFloorTests.swift
git commit -m "test: pin derive-gate-budgets WINDOW to GateFloorTests windowSize

Standing guard that the one documented N cannot silently diverge between
the awk consumer and the Swift consumer. Reads the bare WINDOW= line from
the shell script with a narrow reader (no shell run, no parser added) and
asserts it equals windowSize. Closes the silent-pass direction the
asymmetric self-guard (Decision 3) cannot see."
```

---

### Task 4: Harvest Slice 40's post-merge run, re-derive every budget under the window, commit the literals

**Files:**
- Modify: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` (append one run)
- Modify: budget literals under `Sources/ViewportBenchmarks/` (whatever `derive` prints)

**Interfaces:**
- Consumes: the windowed `derive-gate-budgets.sh` (Task 1). Requires `gh` auth and that run `29606487287` is still within log retention.
- Produces: a corpus carrying run `29606487287`; committed budget literals that reproduce byte-for-byte from the windowed corpus.

> **Why every mode, not just the cluster:** a harvest raises `max(hosted)` and can move the median for scenarios this slice never reasoned about, and the window shift moves them again. Deriving only the five at-floor scenarios would leave the rest silently *not reproducing* from the committed corpus — the Slice 39 partial-sweep breakage. Sweep all modes; commit whatever `derive` prints.

- [ ] **Step 1: Record the pre-harvest corpus shape (for the append-only proof)**

Run: `wc -l docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
Note the line count; run `29606487287` must be absent:
Run: `grep -c 29606487287 docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
Expected: `0`.

- [ ] **Step 2: Harvest run `29606487287` idempotently and append**

```bash
./.github/scripts/harvest-gate-corpus.sh --runs 29606487287 \
  --corpus docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
  >> docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
```

Then confirm it appended (and only appended):
Run: `git diff --numstat docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
Expected: `<N> 0 docs/.../2026-07-12-gate-budget-corpus.tsv` — additions only, **zero deletions** (append-only).
Run: `grep -c 29606487287 docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
Expected: non-zero.

> If `gh` reports the log has aged out (`warn=log_unavailable`), stop and consult the user — the authoritative merged-code run is required by AC5 and Decision 5. Do not substitute a different run.

- [ ] **Step 3: Re-derive every mode under the window**

Run: `./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
This prints one line per gated scenario with `budget_p95=` and `budget_p99=`. Capture the full output — these are the literals to commit.

- [ ] **Step 4: Update every budget literal to match the derived output**

For each printed `<mode>|<scenario> ... budget_p95=P budget_p99=Q`, set that scenario's `p95BudgetNanoseconds: P, p99BudgetNanoseconds: Q` in its `Sources/ViewportBenchmarks/*Benchmark.swift` definition (e.g. `line_geometry_query|uniform_1k` → `LineGeometryQueryBenchmark.swift`). The scenario files: `SyntheticBenchmarks.swift` (pipeline), `RealisticProviderBenchmark.swift`, `VariableHeightBenchmark.swift`, `VariableHeightMutationBenchmark.swift`, `StructuralMutationBenchmark.swift`, `BulkStructuralMutationBenchmark.swift`, `LineQueryBenchmark.swift`, `LineGeometryQueryBenchmark.swift`, `ColumnQueryBenchmark.swift`, `ColumnGeometryQueryBenchmark.swift`, `PointQueryBenchmark.swift`, `PointGeometryQueryBenchmark.swift`. Change **only** the numeric literals — no code, no scenario names, no ordering.

> Sanity anchor (pre-harvest windowed, will shift slightly after the harvest): `line_geometry_query|uniform_1k` p99 ≈ 500 (was 990), `line_geometry_query|uniform_1m` p99 ≈ 760 (was 800), `line_query|uniform_100k` p95 lifts off 3.0×. `line_query|uniform_1k` p95 and `column_query|uniform_100k` p99 legitimately stay at/near 3.0× (recent freaks). Commit `derive`'s actual post-harvest numbers, not these.

- [ ] **Step 5: Prove every committed literal reproduces from the corpus**

Run: `./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
Cross-check each `budget_p95`/`budget_p99` against the edited source. Zero mismatches (record the check; not an automated assertion). `GateFloorTests` is the automated backstop in the next step.

- [ ] **Step 6: Run the floor test and the full suite**

Run: `swift test`
Expected: all pass. `GateFloorTests` is green **by construction** — the budgets were just derived to clear `3×` the windowed max on both statistics.

- [ ] **Step 7: Run all eleven blocking gates locally + verify checksum byte-identity (AC4)**

Run each and confirm `gate=pass` and `failures=0`:

```bash
for m in "" "--variable-height" "--variable-height-mutation" "--structural-mutation" \
         "--bulk-structural-mutation" "--line-query" "--line-geometry-query" \
         "--column-query" "--column-geometry-query" "--point-query" "--point-geometry-query"; do
  echo "== gate $m =="
  swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- $m --gate \
    | grep -E "gate=|checksum" 
done
```

Expected: every mode `gate=pass`; every printed `checksum=` **byte-identical** to the Slice 40 baseline (recorded in the Slice 40 verification record / post-merge run `29606487287`). A moved checksum means the workload changed — stop, that violates AC4.

- [ ] **Step 8: Foundation-free scan (invariant)**

Run: `rg -n "Foundation" Sources/TextEngineCore`
Expected: empty.
Run: `git diff --name-only | grep -E "Sources/(TextEngineCore|TextEngineReferenceProviders)/" || echo "clean"`
Expected: `clean` (AC2 — zero engine/provider diff).

- [ ] **Step 9: Commit corpus + budgets together**

```bash
git add docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv Sources/ViewportBenchmarks/
git commit -m "feat: harvest slice 40 post-merge run and re-derive budgets under the window

Append run 29606487287 (Slice 40's post-merge push proof) append-only,
then re-derive EVERY gated budget over the N=20 window and commit the
literals verbatim. Old freaks age out; several budgets tighten
(line_geometry uniform_1k p99 990 -> ~500). No workload changed --
all eleven gate checksums stay byte-identical to the Slice 40 baseline."
```

---

### Task 5: `AGENTS.md` window docs + P3 folds

**Files:**
- Modify: `AGENTS.md`
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` (comment only, P3 #2)

**Interfaces:** none (documentation).

- [ ] **Step 1: Document the window in `AGENTS.md` `## Gate budgets`**

In the recipe subsection, add the window definition and rationale. After the `budget_p95 = ...` / `budget_p99 = ...` recipe block, insert a paragraph stating:

- `hosted` in the recipe = **the most-recent N=20 distinct runs, keyed on the integer run id**, not all corpus history. The corpus stays append-only/full-history; the window is applied only at read time.
- **Both** consumers (`derive-gate-budgets.sh` and `GateFloorTests`) apply the identical window, pinned to one documented N by `testWindowConstantMatchesDeriveScript`.
- Rationale: the `3× max` floor over an append-only corpus was a one-way ratchet (`max` can only rise → budgets could only loosen). The window makes it two-way: an old freak ages out and the budget can tighten again. What covers an aged-out freak's recurrence is the median-anchored floors (and on p99 the `2×budget_p95` floor), not the `3×`-max term; p95 is the thin axis to watch.

- [ ] **Step 2: Update the `GateFloorTests` description in the package-layout section**

Change the `GateFloorTests.swift` sentence to say it holds every gated scenario to **`3× the windowed (most-recent N=20) max`** on both statistics, and note it now also carries `testWindowConstantMatchesDeriveScript` pinning `windowSize` to the derive script's `WINDOW=`.

- [ ] **Step 3: P3 #1 — complete the `Tests/ViewportBenchmarksTests` file list**

In the package-layout `Tests/ViewportBenchmarksTests` bullet, add the two omitted files: `PointGeometryChecksumTests.swift` (byte-identity checksum guard for point-geometry) and `PointGeometryQueryOptionsTests.swift` (option-parsing coverage). The directory holds five test files; list all five.

- [ ] **Step 4: P3 #2 — fix the stale `WorkflowShapeTests` comment**

In `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`, the comment at lines 94–97 justifies excluding comment lines by pointing at a rationale block "this slice deletes" that "says the words 'continue-on-error' twice." That specific block is gone (Slice 40). Rewrite the comment to point at the **still-present** justification: a `continue-on-error` comment still lives in the host job on the PR-only realistic-provider observation step, so a reader that scanned raw text could still miscount a blocking step as observational — which is why comment lines stay excluded. Do not change any code, only the comment prose.

- [ ] **Step 5: Verify tests and Foundation scan**

Run: `swift test`
Expected: all pass (WorkflowShapeTests green — comment-only change; count unchanged from Task 4).
Run: `rg -n "Foundation" Sources/TextEngineCore`
Expected: empty.

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
git commit -m "docs: document the N=20 gate-budget window and fold slice 40 P3s

Describe the trailing window (most-recent N=20 distinct runs, run-id key,
applied identically in both consumers and pinned by a test) and its
two-way-floor rationale in AGENTS.md. Update the GateFloorTests
description to 3x the windowed max. Fold P3 #1 (list the two omitted
ViewportBenchmarksTests files) and P3 #2 (repoint the WorkflowShapeTests
comment at the still-present continue-on-error comment)."
```

---

### Task 6: Verification record

**Files:**
- Create: `docs/superpowers/verification/2026-07-17-gate-budget-ratchet-repair.md`

**Interfaces:** none.

- [ ] **Step 1: Write the local-evidence sections**

Record, with actual pasted command output:
1. Corpus append: `git --numstat` showing `<N> 0` (append-only) and the harvested run id `29606487287`.
2. `derive-gate-budgets.sh --self-test` → `self_test=pass`.
3. The window unit tests red→green (`testMostRecentRunIDsKeepsTopNByValue`, `testWindowedExtremesDropAnAgedOutFreak`) and the pin test's temporary-mismatch red→green.
4. Full before/after budget table under the window (all changed scenarios, both statistics), and the `derive` reproduces-every-literal check (0 mismatches).
5. `swift test` full output (298 tests, 0 failures).
6. All eleven `--gate` modes `gate=pass` locally, with the checksum byte-identity note vs the Slice 40 baseline.
7. `rg -n Foundation Sources/TextEngineCore` empty; `git diff --name-only` shows no `Sources/TextEngineCore`/`TextEngineReferenceProviders` path (AC2).
8. Cross-target compile: state it was **not** run and why (no `TextEngineCore`/`TextEngineReferenceProviders` file changed — the iOS/WASM surface is untouched), per the Slice 40 P3 #5 lesson.

- [ ] **Step 2: Commit the local record**

```bash
git add docs/superpowers/verification/2026-07-17-gate-budget-ratchet-repair.md
git commit -m "docs: record slice 41 local verification evidence"
```

- [ ] **Step 3: Open the PR, then fill the hosted-proof section (read at STEP level)**

After pushing and opening the PR, read the hosted runs **at step level** (a `continue-on-error` step can conclude a job green while its own step failed — the standing rule). Record:
- PR-head run id: three required jobs `success`; all eleven blocking gates ran and reported `gate=pass`.
- Post-merge `push` run id: same, on the merge commit; the tally of `gate=pass` across all eleven gates, and checksum byte-identity to the PR-head and local runs.

Append these to the verification record and commit (`docs: record slice 41 hosted proof`) — anchoring the proof in the post-merge push run, per the AGENTS.md discipline. This closes AC1 and AC8.

---

## Self-Review

**1. Spec coverage** — every spec item maps to a task:
- Window in `derive-gate-budgets.sh` + `--self-test` → **Task 1**.
- Identical window in `GateFloorTests` + window-selection helper + fixture unit test → **Task 2**.
- Mandatory `WINDOW`/`windowSize` pin test (Scope, Testing §5, AC3, Decision 3) → **Task 3**.
- Harvest run `29606487287` + re-derive every budget under the window (Decision 5, AC5) → **Task 4**.
- `AGENTS.md` window doc + `GateFloorTests` description + P3 #1 + P3 #2 → **Task 5**.
- Verification record with local + hosted step-level proof (AC1, AC8) → **Task 6**.
- AC2 (zero engine/provider diff) → checked in Task 4 Step 8 and Task 5 Step 5.
- AC4 (byte-identical checksums) → Task 4 Step 7.
- AC6 (two-way floor demonstrated) → Task 2 Step 5 (`testWindowedExtremesDropAnAgedOutFreak`), and re-stated in the record (Task 6).
- AC7 (AGENTS.md states N=20, run-id key, both consumers, rationale, P3s) → Task 5.

**2. Placeholder scan** — the only non-hard-coded values are Task 4's re-derived budget literals, which are *derived from a live harvest* (the spec forbids hard-coding them: "the shipped literals are whatever `derive` prints"). Exact commands and the update procedure are given, with a computed sanity anchor. Not a placeholder — a derivation step.

**3. Type/name consistency** — `windowSize` (Swift `Int`), `WINDOW` (shell), `mostRecentRunIDs(_:limit:) -> Set<Int64>`, `corpusExtremes(from:windowSize:) -> [String: CorpusExtremes]`, `window_run_ids [N]` are used identically wherever referenced across Tasks 1–3. `CorpusExtremes` (existing struct) is reused unchanged. The pin test reads `WINDOW=` by the exact prefix Task 1 writes.

---

## Notes carried from the spec review (do not re-litigate)

- The recurrence-safety of an aged-out freak rests on the **median-anchored floors** (and, on p99, `budget_p99 ≥ 2×budget_p95`), **not** the `3×`-max term. The worst freak (`line_geometry|uniform_1k` p99 = 330) is 4.12× its windowed max and is covered only by the `2×p95` floor. **p95 is the thin axis** — monitor there. This is why Task 4 must not hand-adjust any budget: the derivation already encodes this.
- `realistic_provider` keeps only 17 windowed runs at N=20 (PR-only), not 20 — still far from the 11-run starvation floor, but it is the mode whose windowed count tracks differently from the raw run count.
