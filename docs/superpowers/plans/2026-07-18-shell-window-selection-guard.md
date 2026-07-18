# Shell Window-Selection Standing Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin the shell window-selection logic (`window_run_ids` in `derive-gate-budgets.sh`) to the Swift selector (`mostRecentRunIDs` in `GateFloorTests`) with a standing test, closing the one half of Slice 41's "both consumers agree" invariant that only a manual `--self-test` guards.

**Architecture:** Add a thin `--window-run-ids [N]` subcommand to `derive-gate-budgets.sh` that delegates to the existing `window_run_ids` function (the exact selector the derivation uses via `<(window_run_ids < "$corpus")`), exposing it for isolated invocation. Then a new XCTest, `testWindowSelectionMatchesDeriveScript`, launches that subcommand over a fixture corpus via `Foundation.Process` and asserts its chosen run-id **set** equals `mostRecentRunIDs(sameIDs, limit: N)`. This is the cross-language analog of the existing constant-pin test, now for the selection logic. No engine, provider, workload, budget, or corpus byte changes.

**Tech Stack:** Bash (`derive-gate-budgets.sh`), Swift 6.0 / XCTest (`ViewportBenchmarksTests`), `Foundation.Process`/`Pipe` (test target only — already imports Foundation to read the corpus).

## Global Constraints

Copied verbatim from the spec and AGENTS.md hard constraints. Every task's requirements implicitly include this section.

- **Zero change to `Sources/TextEngineCore` or `Sources/TextEngineReferenceProviders`.** `git diff --name-only main` must show no path under either. Expected engine/provider diff: **zero lines**.
- **Zero change to any budget literal, the corpus, or any benchmark workload.** No harvest, no re-derivation. All eleven `--gate` checksums stay **byte-identical** to the Slice 41 baseline.
- **No Foundation in `Sources/TextEngineCore`** — `rg -n "Foundation" Sources/TextEngineCore` stays empty. The subprocess helper and its `Process` use live in `Tests/ViewportBenchmarksTests`, which already imports Foundation; nothing crosses into the core.
- **One logical step per commit**, conventional-commit prefixes (`feat:`, `fix:`, `test:`, `docs:`).
- Branch: `slice-42-shell-window-selection-guard` (already created; spec already committed there).

---

### Task 1: Shell `--window-run-ids` seam + P3 #1 trap fold

**Files:**
- Modify: `.github/scripts/derive-gate-budgets.sh` (add subcommand after the `--self-test` guard block at lines 71–74; add trap in `run_self_test` after line 47; remove the now-redundant explicit `rm` at line 67)

**Interfaces:**
- Produces: a `--window-run-ids [N]` subcommand — reads a corpus (WITH header) on stdin, prints the windowed run ids (newest-first, one per line) by delegating to `window_run_ids`. N defaults to `$WINDOW` when omitted. Consumed by Task 2's Swift test.

- [ ] **Step 1: Fold P3 #1 — trap-clean the self-test fixture on the red path**

In `run_self_test()`, add a `trap` immediately after `fixture="$(mktemp)"` (currently line 47). Use **double quotes** so `$fixture` is expanded *now* (while the `local` is in scope) and baked into the trap string as a literal path — the single-quote form the Slice 41 review sketched defers expansion to `exit` time, when the `local fixture` is out of scope and would expand to empty (`rm -f ""`).

Change:

```sh
run_self_test() {
  local fixture
  fixture="$(mktemp)"
```

to:

```sh
run_self_test() {
  local fixture
  fixture="$(mktemp)"
  # P3 #1: clean up on the red path too. assert_equal exits 1 before any trailing
  # rm, so without this a failing self-test orphans the fixture. Double-quoted so
  # $fixture is baked in now (the local is out of scope by the time EXIT fires).
  trap "rm -f '$fixture'" EXIT
```

Then remove the now-redundant explicit cleanup near the end of `run_self_test` (currently line 67) — the trap subsumes it on both paths:

```sh
  rm -f "$fixture"
  echo "self_test=pass"
```

becomes:

```sh
  echo "self_test=pass"
```

- [ ] **Step 2: Verify the self-test still passes**

Run: `bash .github/scripts/derive-gate-budgets.sh --self-test`
Expected: `self_test=pass`

- [ ] **Step 3: Commit the trap fold**

```bash
git add .github/scripts/derive-gate-budgets.sh
git commit -m "fix: trap-clean derive-gate-budgets self-test fixture on red path

Slice 41 review P3 #1: assert_equal exits 1 before the trailing rm, so a
failing --self-test orphaned its mktemp fixture. trap with the path baked in
(double-quoted, since the local fixture is out of scope by EXIT time) cleans
both paths; the explicit success-path rm is now redundant and removed."
```

- [ ] **Step 4: Add the `--window-run-ids` subcommand**

Insert a new guard block between the `--self-test` block (ends at line 74, `fi`) and the `corpus=...` line (line 76). Current text:

```sh
if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

corpus="${1:?usage: derive-gate-budgets.sh <corpus.tsv> [mode ...]}"
```

becomes:

```sh
if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

# Test seam: expose the exact window_run_ids selection the derivation uses via
# <(window_run_ids < "$corpus"), so GateFloorTests.testWindowSelectionMatchesDeriveScript
# can pin it to Swift's mostRecentRunIDs. Reads the corpus (WITH header) on stdin;
# N defaults to WINDOW. Delegates -- it duplicates none of the selection logic.
if [[ "${1:-}" == "--window-run-ids" ]]; then
  window_run_ids "${2:-$WINDOW}"
  exit 0
fi

corpus="${1:?usage: derive-gate-budgets.sh <corpus.tsv> [mode ...]}"
```

- [ ] **Step 5: Verify the subcommand selects correctly by hand**

Run (7 rows, 5 distinct ids `{100,305,210,99,42}`, run 305 and 210 each contributing two rows, physically out of order):

```bash
printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n100\tm\ts\t1\t2\n305\tm\ts\t1\t2\n305\tm\ts2\t1\t2\n210\tm\ts\t1\t2\n99\tm\ts\t1\t2\n210\tm\ts2\t1\t2\n42\tm\ts\t1\t2\n' \
  | bash .github/scripts/derive-gate-budgets.sh --window-run-ids 2
```

Expected (newest-first, deduped):

```
305
210
```

Also verify the no-op regime keeps all distinct ids newest-first:

```bash
printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n100\tm\ts\t1\t2\n305\tm\ts\t1\t2\n305\tm\ts2\t1\t2\n210\tm\ts\t1\t2\n99\tm\ts\t1\t2\n210\tm\ts2\t1\t2\n42\tm\ts\t1\t2\n' \
  | bash .github/scripts/derive-gate-budgets.sh --window-run-ids 10
```

Expected:

```
305
210
100
99
42
```

- [ ] **Step 6: Verify the self-test still passes (subcommand did not disturb it)**

Run: `bash .github/scripts/derive-gate-budgets.sh --self-test`
Expected: `self_test=pass`

- [ ] **Step 7: Commit the subcommand**

```bash
git add .github/scripts/derive-gate-budgets.sh
git commit -m "feat: add --window-run-ids seam to derive-gate-budgets

Exposes the existing window_run_ids selection for isolated invocation (reads a
corpus on stdin, prints the windowed run ids; N defaults to WINDOW). It
delegates to the one function the derivation already uses, duplicating no
selection logic, so a Swift test can pin it to mostRecentRunIDs."
```

---

### Task 2: Swift cross-language selection pin

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (add a private `runProcess` helper near `repositoryRoot()` at line 38; add `testWindowSelectionMatchesDeriveScript` inside `final class GateFloorTests`, beside `testWindowConstantMatchesDeriveScript` at the end of the class)

**Interfaces:**
- Consumes: the `--window-run-ids [N]` subcommand from Task 1; the existing `repositoryRoot()` and `mostRecentRunIDs(_:limit:)` free functions in this file.
- Produces: `testWindowSelectionMatchesDeriveScript` — the standing guard; no downstream consumer.

- [ ] **Step 1: Write the failing test (and its subprocess helper)**

Add the helper as a private free function next to `repositoryRoot()` (after line 44, the close of `repositoryRoot()`):

```swift
// The test target's first subprocess launch. Safe here: ViewportBenchmarksTests runs
// only on the host (Linux CI + local macOS), never on iOS/WASM, which merely compile
// TextEngineCore/ReferenceProviders. Foundation.Process is already available (this file
// imports Foundation to read the corpus); nothing here reaches the Foundation-free core.
// Feeds `stdin` to the process, reads stdout to EOF, then reaps. Output here is a handful
// of run ids, so read-then-wait cannot deadlock on a full pipe buffer.
private func runProcess(_ executableURL: URL, _ arguments: [String], stdin: String) throws
    -> (stdout: String, stderr: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    try stdinPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
    try stdinPipe.fileHandleForWriting.close()

    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return (String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self),
            process.terminationStatus)
}
```

Add the test at the end of `final class GateFloorTests`, after `testWindowConstantMatchesDeriveScript` (before the class's closing brace at line 280):

```swift
    // The selection-logic analog of testWindowConstantMatchesDeriveScript: that test pins
    // the window's N CONSTANT across languages; this pins the window's SELECTION LOGIC.
    // It runs the script's real window_run_ids (via the --window-run-ids seam) over a
    // fixture and asserts its chosen run-id SET equals mostRecentRunIDs -- the function the
    // floor test derives its extremes through. Set, not ordered list: the awk KEEP filter
    // and the Swift window.contains fold both use membership, so emission order never
    // reaches the derivation (the shell --self-test covers newest-first ordering separately).
    // Closes the shell half of the "both consumers agree" invariant that the constant pin,
    // GateFloorTests, and the runtime --gate all leave open (Slice 41 review P2 #1).
    func testWindowSelectionMatchesDeriveScript() throws {
        let scriptURL = repositoryRoot()
            .appendingPathComponent(".github/scripts/derive-gate-budgets.sh")

        // Discriminating fixture: 305 and 210 each contribute two rows (a run contributes
        // many rows -> must dedup); rows are physically out of chronological order (ranking
        // is by run-id value, not row position). Distinct ids: {100, 305, 210, 99, 42}.
        // window_run_ids reads only column 1; the other columns are inert here.
        let fixtureIDs: [Int64] = [100, 305, 305, 210, 99, 210, 42]
        var corpus = "run_id\tmode\tscenario\tp95_ns\tp99_ns\n"
        for id in fixtureIDs {
            corpus += "\(id)\tm\ts\t1\t2\n"
        }

        let env = URL(fileURLWithPath: "/usr/bin/env")

        // Both regimes: N < distinct count (2, 3 drop runs) and N >= distinct count (10, no-op).
        for limit in [2, 3, 10] {
            let result = try runProcess(
                env, ["bash", scriptURL.path, "--window-run-ids", "\(limit)"], stdin: corpus)

            XCTAssertEqual(
                result.exitCode, 0,
                "derive-gate-budgets.sh --window-run-ids \(limit) exited \(result.exitCode); "
                    + "stderr: \(result.stderr)")

            let shellSet = Set(result.stdout.split(separator: "\n").compactMap { Int64($0) })
            XCTAssertEqual(
                shellSet, mostRecentRunIDs(fixtureIDs, limit: limit),
                "shell window_run_ids and Swift mostRecentRunIDs disagree at N=\(limit) — the "
                    + "two corpus consumers would window differently; re-run "
                    + "`.github/scripts/derive-gate-budgets.sh --self-test`")
        }
    }
```

- [ ] **Step 2: Run the test to verify it passes green**

The seam from Task 1 already exists, so this guard test is green immediately (the two selectors agree). That is expected for a guard test; Step 3 proves it can fail.

Run: `swift test --filter GateFloorTests/testWindowSelectionMatchesDeriveScript`
Expected: PASS (`Executed 1 test, with 0 failures`).

- [ ] **Step 3: Prove the guard is live (break → red → revert → green)**

Temporarily weaken the shell selector to make it diverge from Swift. In `.github/scripts/derive-gate-budgets.sh`, change `window_run_ids` line 32 from:

```sh
  tail -n +2 | cut -f1 | sort -rnu | head -n "$n"
```

to (drop the `-u`, so duplicate run ids stop collapsing):

```sh
  tail -n +2 | cut -f1 | sort -rn | head -n "$n"
```

Run: `swift test --filter GateFloorTests/testWindowSelectionMatchesDeriveScript`
Expected: **FAIL** — at N=2 the shell now yields `{305}` (rows `305,305`) while `mostRecentRunIDs` yields `{305, 210}`. Capture the failure output for the verification record.

Then revert the change (restore `sort -rnu`):

```bash
git checkout .github/scripts/derive-gate-budgets.sh
```

Run again: `swift test --filter GateFloorTests/testWindowSelectionMatchesDeriveScript`
Expected: PASS.

- [ ] **Step 4: Run the full floor suite to confirm nothing else moved**

Run: `swift test --filter GateFloorTests`
Expected: PASS (all existing floor tests + the new one).

- [ ] **Step 5: Commit**

```bash
git add Tests/ViewportBenchmarksTests/GateFloorTests.swift
git commit -m "test: pin shell window-selection to Swift mostRecentRunIDs

testWindowSelectionMatchesDeriveScript runs derive-gate-budgets.sh's real
window_run_ids (via the --window-run-ids seam) over a fixture and asserts its
chosen run-id set equals mostRecentRunIDs. The selection-logic analog of the
existing constant pin: closes the shell half of the 'both consumers agree'
invariant (Slice 41 review P2 #1). Compared as sets -- the derivation uses
membership, not order. Guard-is-live demonstrated (drop -u -> red)."
```

---

### Task 3: Document the seam and the selection pin in AGENTS.md

**Files:**
- Modify: `AGENTS.md` (Commands block line 178; `GateFloorTests.swift` description lines 128–130; `## Gate budgets` window paragraph lines 331–334)

**Interfaces:**
- Consumes: nothing. Documentation only.

- [ ] **Step 1: Add the `--window-run-ids` line to the Commands block**

Change (line 178):

```
./.github/scripts/derive-gate-budgets.sh <corpus.tsv> <mode> # corpus -> budgets (re-derive half)
```

to:

```
./.github/scripts/derive-gate-budgets.sh <corpus.tsv> <mode> # corpus -> budgets (re-derive half)
./.github/scripts/derive-gate-budgets.sh --window-run-ids <n> < <corpus.tsv> # windowed run ids (Swift-pin test seam)
```

- [ ] **Step 2: Extend the `GateFloorTests.swift` description**

Change (lines 128–130):

```
  reverse. It also carries `testWindowConstantMatchesDeriveScript`, pinning its
  `windowSize` constant to `derive-gate-budgets.sh`'s `WINDOW=` so the two windows
  cannot drift apart.
```

to:

```
  reverse. It also carries `testWindowConstantMatchesDeriveScript`, pinning its
  `windowSize` constant to `derive-gate-budgets.sh`'s `WINDOW=` so the two windows
  cannot drift apart, and `testWindowSelectionMatchesDeriveScript`, pinning the
  shell `window_run_ids` *selection logic* to Swift's `mostRecentRunIDs` by driving
  the script's `--window-run-ids` seam over a fixture and comparing the chosen
  run-id set — so not just the N constant but the selection itself cannot silently
  diverge.
```

- [ ] **Step 3: Extend the `## Gate budgets` window paragraph**

Change (lines 331–334):

```
consumers apply the identical window: `derive-gate-budgets.sh` and
`GateFloorTests` each hold `N=20`, pinned to one documented value by
`testWindowConstantMatchesDeriveScript` so they cannot silently drift apart.
```

to:

```
consumers apply the identical window: `derive-gate-budgets.sh` and
`GateFloorTests` each hold `N=20`, pinned to one documented value by
`testWindowConstantMatchesDeriveScript` so they cannot silently drift apart. The
*selection logic* behind that constant is separately pinned by
`testWindowSelectionMatchesDeriveScript`, which drives the script's
`--window-run-ids` seam over a fixture and asserts its chosen run-id set equals
`mostRecentRunIDs` — closing the shell half of the invariant the constant pin
leaves open.
```

- [ ] **Step 4: Verify the doc references are accurate**

Run: `rg -n "testWindowSelectionMatchesDeriveScript|--window-run-ids" AGENTS.md`
Expected: the three new references (Commands line, GateFloorTests description, Gate budgets paragraph) plus none stale.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs: record the --window-run-ids seam and selection pin in AGENTS.md"
```

---

### Task 4: Local verification record

**Files:**
- Create: `docs/superpowers/verification/2026-07-18-shell-window-selection-guard.md`

**Interfaces:**
- Consumes: nothing. Records the evidence for AC1–AC7 (AC8, hosted, is recorded after CI runs, per the finishing workflow).

- [ ] **Step 1: Run the full local verification sweep and capture outputs**

Run each and keep the output for the record:

```bash
# Full test suite (includes the new pin test)
swift test 2>&1 | tail -5

# Shell self-test still green (with the trap fold)
bash .github/scripts/derive-gate-budgets.sh --self-test

# The seam, by hand (expect 305 then 210)
printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n100\tm\ts\t1\t2\n305\tm\ts\t1\t2\n305\tm\ts2\t1\t2\n210\tm\ts\t1\t2\n99\tm\ts\t1\t2\n210\tm\ts2\t1\t2\n42\tm\ts\t1\t2\n' \
  | bash .github/scripts/derive-gate-budgets.sh --window-run-ids 2

# Foundation-free core scan (must be empty)
rg -n "Foundation" Sources/TextEngineCore || echo "EMPTY (pass)"

# Zero engine/provider diff for the whole branch
git diff --name-only main -- Sources/TextEngineCore Sources/TextEngineReferenceProviders || true
echo "^ must be empty"

# All eleven blocking gates locally (each must print gate=pass)
for m in "" "--variable-height" "--variable-height-mutation" "--structural-mutation" \
         "--bulk-structural-mutation" "--line-query" "--line-geometry-query" \
         "--column-query" "--column-geometry-query" "--point-query" "--point-geometry-query"; do
  echo "== gate $m =="
  swift run -c release ViewportBenchmarks -- $m --gate 2>&1 | rg "gate=|checksum" || true
done
```

- [ ] **Step 2: Write the verification record**

Create `docs/superpowers/verification/2026-07-18-shell-window-selection-guard.md` capturing, with the actual command outputs from Step 1:
- `swift test` total pass count (all prior tests + `testWindowSelectionMatchesDeriveScript`).
- The **guard-is-live** evidence from Task 2 Step 3: the red output with `sort -rn` (the N=2 `{305}` vs `{305,210}` mismatch), and the green after revert.
- `derive-gate-budgets.sh --self-test` → `self_test=pass`.
- The by-hand `--window-run-ids 2` output (`305`/`210`).
- `rg Foundation Sources/TextEngineCore` empty; `git diff --name-only main` shows zero `Sources/TextEngineCore`/`TextEngineReferenceProviders` paths.
- All eleven gates `gate=pass` locally, with the query/mutation checksums recorded and noted **byte-identical to the Slice 41 baseline** (`docs/superpowers/verification/2026-07-17-gate-budget-ratchet-repair.md`) — the proof no measured path moved.
- A "hosted proof pending" placeholder for the PR-head and post-merge `push` run IDs, to be filled in at step level (a `continue-on-error` step can conclude a job green while its own step failed) once CI runs — per the Slices 24–41 anchor-proof-in-the-push-run pattern.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/verification/2026-07-18-shell-window-selection-guard.md
git commit -m "docs: record slice 42 local verification"
```

---

## Self-Review

**1. Spec coverage:**

- Spec "In scope" → `--window-run-ids` subcommand: Task 1. → `testWindowSelectionMatchesDeriveScript`: Task 2. → P3 #1 trap fold: Task 1 Step 1. → AGENTS.md note + subcommand record: Task 3. ✓
- Spec AC1 (subcommand delegates, N defaults to WINDOW): Task 1 Steps 4–5. ✓
- Spec AC2 (set-equality over discriminating fixture, guard demonstrably live): Task 2 Steps 1, 3. ✓
- Spec AC3 (`swift test` passes in full, green on hosted Linux): Task 2 Step 4 + Task 4 Step 1 (local); hosted in the finishing workflow. ✓
- Spec AC4 (zero engine/provider/budget/corpus diff): Global Constraints + Task 4 Step 1. ✓
- Spec AC5 (eleven gates `gate=pass`, checksums byte-identical): Task 4 Steps 1–2. ✓
- Spec AC6 (self-test passes, fixture cleaned on red path): Task 1 Steps 1–2. ✓
- Spec AC7 (AGENTS.md records pin + seam): Task 3. ✓
- Spec AC8 (hosted, step level): Task 4 Step 2 placeholder + the finishing workflow. ✓
- Spec Testing Strategy (TDD guard-is-live): Task 2 Step 3. ✓

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N"/"write tests for the above". Every code step shows the actual code; every run step shows the exact command and expected output. The only intentional forward-reference is AC8's hosted run IDs, which cannot exist until CI runs — recorded as an explicit placeholder in Task 4 Step 2, per house convention. ✓

**3. Type consistency:** `window_run_ids` / `--window-run-ids` / `$WINDOW` spelled identically across Tasks 1–3. `mostRecentRunIDs(_:limit:)`, `repositoryRoot()`, `runProcess(_:_:stdin:)` return type `(stdout:stderr:exitCode:)`, and `fixtureIDs: [Int64]` are consistent between the helper and the test in Task 2. `testWindowSelectionMatchesDeriveScript` named identically in Tasks 2, 3, 4. ✓
