# Calibration-Chain Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the two unsound links in the calibration chain before map node 6 harvests through them — the wrap benchmarks must measure the operation rather than the host clock tick (D-23), and the harvester must admit only rows whose run is this repository's and whose own line does not say the measurement was slow or degenerate (D-7).

**Architecture:** Three independent surfaces, no engine change. (1) A shared `amortisedSamples` helper in `BenchmarkSupport.swift` — beside `nanoseconds`/`percentile`, **not** through `formatSummary`, which twelve blocking gates depend on — with its division extracted into a pure `amortise` so losing it is catchable; both wrap modes move onto it. (2) The corpus grows a sixth **verdict** column that the harvester writes and both consumers filter on at **read** time, with the reject set pinned across languages by a third seam test. (3) The harvester gains a per-run `.head_repository.full_name` check that fails closed, and its awk parser moves into a `extract_rows()` function so `--self-test` can drive it.

**Tech Stack:** Swift 6.0 tools version, XCTest, SwiftPM, bash + awk, `gh` CLI. No dependencies.

**Spec:** [`docs/superpowers/specs/2026-08-23-calibration-chain-hardening-design.md`](../specs/2026-08-23-calibration-chain-hardening-design.md)

## Global Constraints

Every task's requirements implicitly include these.

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty. This slice adds no core code, but the scan is still run.
- **`Sources/ViewportBenchmarks` stays Foundation-free too.** Convention-only (the committed scan covers the core alone), but this slice adds code there, so the one-line check is part of verification. The new helper must not become the first exception.
- **Zero third-party dependencies**; **Swift Embedded compatible**; compiles for iOS and WASM with no source changes.
- **The twelve gated modes' measurement loops are UNTOUCHED.** Any change to them shifts their numbers and drags a budget re-derivation under the headroom-ceiling rule. Spec Non-Goal 1. Verified by diff in Task 8.
- **No budget moves, and the committed corpus file is not edited.** `derive-gate-budgets.sh <corpus>` stdout must be **byte-identical** before and after the whole slice (AC13).
- **Neither wrap mode becomes gateable or enters `swift-ci.yml`** (AC14). Both keep their **prefixed** latency tokens (`query_p95_ns=`, `compute_p95_ns=`, …) so they emit no corpus row.
- **TDD.** Failing test first, minimal implementation, green, commit. One logical step per commit.
- **Conventional commits**: `feat:`, `test:`, `refactor:`, `docs:`, `ci:`.
- **Branch**: `slice-54-calibration-chain-hardening` (already created; the spec and the selection records are already committed on it).
- **D-17 — do NOT use `${PIPESTATUS[0]}` in any command block.** Agent shells here are **zsh**, where it expands empty and `[ "" -eq 0 ]` evaluates **true**, inverting a failed assertion into a pass. Use `if ! cmd; then …; fi`, or do not pipe.
- **D-2 assertion conventions**: never put a check on the left of a pipe whose right side is `tail`/`tee`/`jq`/`wc`/`rg`; never `echo "…=$?"` after a status-insensitive command (`git diff --name-only`, `git status`, `gh pr list`, `jq`, `sed -i`, and every pipeline exit 0; `rg`/`grep` exit **1** on no match, so the desired outcome reads as a failure). Assert with `[ -z "$(…)" ]`, `git diff --quiet`, or an explicit `if`/`else` printing both branches.
- **Every command block assigns the variables it uses.** Each Bash invocation is a fresh shell; nothing carries across steps.
- Run everything from the repo root: `/Users/aabanschikov/swift-text-engine`.
- **Scratch files** go under `/tmp/slice54-*`. Never inside the repository.

---

## File Structure

**Benchmarks (`Sources/ViewportBenchmarks`)**

| File | Responsibility |
|---|---|
| `BenchmarkSupport.swift` | +`amortise(elapsedNanoseconds:operationsPerSample:)` (pure, pinned by exact equality) and +`amortisedSamples(iterations:operationsPerSample:body:)` (one clock read per iteration). The measurement shape's single home. Nothing existing in this file changes. |
| `WrapRowQueryBenchmark.swift` | Moves onto the helper (5 000 × 256); +`formatWrapRowQueryLine(...)` extracted so the line shape is unit-testable; +`query_operations_per_sample=` token. |
| `WrapComputeBenchmark.swift` | `compute` (256) and `drain` (16) onto the helper; drain ranges pre-built outside the clock; reindex construction bound and reused (one O(N) pass, observably live); +`formatWrapComputeLine(...)`; +`scenario=`, +`drain_p99_ns=`, +three `*_operations_per_sample=` tokens. |

**Scripts (`.github/scripts`)**

| File | Responsibility |
|---|---|
| `harvest-gate-corpus.sh` | +`extract_rows()` (the awk parser, now a stdin function emitting **six** columns with a verdict); +`admissible_source()` (pure run-source decision); one `gh api` per candidate between dedup and log fetch, on both entry paths; two new `--self-test` truth tables; usage-header schema gains the sixth column. |
| `derive-gate-budgets.sh` | +`REJECTED_VERDICTS` constant; main awk drops rejected rows and reports per-reason counts on **stderr**; +`--admissible-rows` seam mirroring `--window-run-ids`. |

**Tests (`Tests/ViewportBenchmarksTests`)**

| File | Responsibility |
|---|---|
| `AmortisedSamplesTests.swift` | **new** — `amortise` exact-equality pin (Decision 2, drill 1) + `amortisedSamples` structural pins (call count, sample count, index sequence). |
| `WrapBenchmarkLineShapeTests.swift` | **new** — both wrap line formatters: required tokens present, `*_operations_per_sample` values, and **no bare `p95_ns`/`p99_ns` key** (the harvester-inertness claim, machine-checked instead of eyeballed). |
| `GateFloorTests.swift` | Reader accepts five **or** six columns; +`rejectedVerdicts`/`isAdmissibleVerdict`/`admissibleCorpusRows`; +`testSixColumnRowsAreReadAndFilteredByVerdict`; +`testAdmissibleRowsMatchDeriveScript` (third cross-language pin). |

**Docs**: `AGENTS.md` (three `## Gate budgets` edits + one `## Commands` note), `docs/superpowers/debt-ledger.md` (D-23, D-7 → discharged), `docs/superpowers/verification/2026-08-23-calibration-chain-hardening.md` (new).

**Untouched on purpose**: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`, `.github/workflows/swift-ci.yml`, every gated benchmark file, `formatSummary`, `BenchmarkModels.swift`.

---

## Task 1: The amortised measurement helper

Spec Decisions 1 and 2. AC1 (helper exists), AC2 (`amortise` separate and pinned), drill 1.

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkSupport.swift` (append after `deterministicIndex`, before `runProviderOperation`)
- Create: `Tests/ViewportBenchmarksTests/AmortisedSamplesTests.swift`

**Interfaces:**
- Consumes: `nanoseconds(_ duration: Duration) -> Int64` (already in `BenchmarkSupport.swift`).
- Produces:
  - `func amortise(elapsedNanoseconds: Int64, operationsPerSample: Int) -> Int64` — truncating integer division.
  - `@available(macOS 13.0, *) func amortisedSamples(iterations: Int, operationsPerSample: Int, body: (Int) -> Int) -> (samples: [Int64], checksum: Int)` — `body` receives the **global operation index** (`iteration * operationsPerSample + operation`) and returns an Int folded into `checksum` with `&+=`. `samples` comes back **unsorted**, one per iteration; callers sort before calling `percentile`.

- [ ] **Step 1: Record the green baseline**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test > /tmp/slice54-baseline.txt 2>&1; then
  echo "BASELINE RED — stop and investigate before changing anything"
else
  echo "baseline green"
fi
rg -n "Executed [0-9]+ tests" /tmp/slice54-baseline.txt | tail -2
```

Expected: `baseline green`, and a test count to carry into the verification record.

- [ ] **Step 2: Record the BEFORE-side wrap output (D-23 evidence, needed before any code moves)**

This is evidence for AC4 and for the Problem section's structural before-claim. It must be captured **before** Task 2 and Task 3 change either mode.

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice54-before-build.txt 2>&1; then
  echo "RELEASE BUILD RED"; tail -20 /tmp/slice54-before-build.txt
else
  echo "release build green"
fi
swift run -c release ViewportBenchmarks -- --wrap-row-query > /tmp/slice54-before-wrap-row-query.txt 2>&1
swift run -c release ViewportBenchmarks -- --wrap-compute   > /tmp/slice54-before-wrap-compute.txt 2>&1
cat /tmp/slice54-before-wrap-row-query.txt /tmp/slice54-before-wrap-compute.txt
```

Then count how many of the printed latency values are integer multiples of the host clock tick. The denominator is derived from the **output shape**, not from the sweep: `--wrap-row-query` prints 2 values per scenario over 4 scenarios, `--wrap-compute` prints 4 per width (`compute_p95`, `compute_p99`, `drain_p95`, `reindex`) over 3 widths — **8 + 12 = 20**.

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY'
import re
vals = []
for path, keys in (
    ("/tmp/slice54-before-wrap-row-query.txt", ("query_p95_ns", "query_p99_ns")),
    ("/tmp/slice54-before-wrap-compute.txt",
     ("compute_p95_ns", "compute_p99_ns", "drain_p95_ns", "reindex_ns")),
):
    for line in open(path):
        for k in keys:
            m = re.search(r"\b%s=(\d+)" % k, line)
            if m:
                vals.append((k, int(m.group(1))))
TICK = 1e9 / 24_000_000  # Apple silicon mach timebase: 24 MHz -> 41.666... ns
hits = [v for _, v in vals if abs(v - round(v / TICK) * TICK) <= 1.0]
print("printed values:", len(vals), "(expected 20)")
print("within 1 ns of an integer tick multiple:", len(hits), "of", len(vals))
for k, v in vals:
    print("   %-16s %8d  ticks=%.3f" % (k, v, v / TICK))
PY
```

Expected: `printed values: 20`, and **20 of 20** within 1 ns of an integer tick multiple. Save the full stdout of this block into `/tmp/slice54-before-ticks.txt` for the verification record (re-run with `> /tmp/slice54-before-ticks.txt` after reading it).

> If the host is not Apple silicon at 24 MHz, the tick constant is wrong and the ratio will not reproduce. In that case record the observed granularity instead (the smallest non-zero difference between distinct printed values) and say so in the verification record — the claim is "quantised to the host tick", not "quantised to 41.667 ns".

- [ ] **Step 3: Write the failing tests**

Create `Tests/ViewportBenchmarksTests/AmortisedSamplesTests.swift`:

```swift
import XCTest
@testable import ViewportBenchmarks

// The shared measurement shape both wrap modes run on (spec Decisions 1 and 2).
//
// ContinuousClock cannot be substituted, so these tests pin what is pinnable: the
// loop's STRUCTURE (how many times the body runs, how many samples come back, which
// indices the body sees) and the ARITHMETIC, separately. The split is the point --
// a dropped division leaves every structural assertion true, which is why `amortise`
// is a free function pinned by exact equality rather than an inline `/`.
@available(macOS 13.0, *)
final class AmortisedSamplesTests: XCTestCase {

    // Drill 1's target. Mutating this function's body to `return elapsedNanoseconds`
    // reddens exactly here.
    func testAmortiseDividesByOperationsPerSample() {
        XCTAssertEqual(amortise(elapsedNanoseconds: 2_560, operationsPerSample: 256), 10)
        XCTAssertEqual(amortise(elapsedNanoseconds: 41, operationsPerSample: 1), 41)
        XCTAssertEqual(amortise(elapsedNanoseconds: 0, operationsPerSample: 256), 0)
    }

    // Truncation is not incidental: it is the same flooring every gated mode does
    // (LineQueryBenchmark.swift:89), and it is what lets a sub-tick operation report 0
    // rather than 1. Pinned so a "helpful" rounding change is a red test, not a drift.
    func testAmortiseTruncatesRatherThanRounds() {
        XCTAssertEqual(amortise(elapsedNanoseconds: 255, operationsPerSample: 256), 0)
        XCTAssertEqual(amortise(elapsedNanoseconds: 511, operationsPerSample: 256), 1)
        XCTAssertEqual(amortise(elapsedNanoseconds: 767, operationsPerSample: 256), 2)
    }

    func testBodyRunsIterationsTimesOperationsPerSample() {
        var calls = 0
        let measured = amortisedSamples(iterations: 7, operationsPerSample: 5) { _ in
            calls += 1
            return 1
        }
        XCTAssertEqual(calls, 35)
        XCTAssertEqual(measured.samples.count, 7)
        XCTAssertEqual(measured.checksum, 35)
    }

    // The body must see the GLOBAL operation index, contiguously from 0: the wrap modes'
    // deterministic input generators (deterministicScrollOffset, deterministicIndex) are
    // functions of it, so a per-iteration reset would silently shrink the input space to
    // `operationsPerSample` distinct inputs.
    func testBodyReceivesEveryGlobalOperationIndexOnceInOrder() {
        var seen: [Int] = []
        _ = amortisedSamples(iterations: 3, operationsPerSample: 4) { index in
            seen.append(index)
            return 0
        }
        XCTAssertEqual(seen, Array(0..<12))
    }

    // Samples come back UNSORTED and one-per-iteration: percentile() requires a sorted
    // array, and the caller is the one that sorts. Pinned so the helper never starts
    // sorting on its own and leaves callers double-sorting a copy.
    func testSamplesAreOnePerIterationAndNotSortedByTheHelper() {
        let measured = amortisedSamples(iterations: 4, operationsPerSample: 1) { _ in 0 }
        XCTAssertEqual(measured.samples.count, 4)
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter AmortisedSamplesTests > /tmp/slice54-t1-red.txt 2>&1; then
  echo "RED as expected"
else
  echo "UNEXPECTEDLY GREEN — the helper must not exist yet"
fi
rg -n "cannot find 'amortise'|cannot find 'amortisedSamples'|error:" /tmp/slice54-t1-red.txt | head -5
```

Expected: `RED as expected`, with `cannot find 'amortise' in scope` / `cannot find 'amortisedSamples' in scope` compile errors.

- [ ] **Step 5: Implement the helper**

In `Sources/ViewportBenchmarks/BenchmarkSupport.swift`, insert after `deterministicIndex(sample:multiplier:modulus:)` and before `runProviderOperation`:

```swift
// The division that turns one batched clock read into a per-operation cost.
//
// A FREE FUNCTION rather than an inline `/` on purpose (spec Decision 2). ContinuousClock
// cannot be substituted in a unit test, so a test can pin `amortisedSamples`' structure --
// the body runs `iterations * operationsPerSample` times, exactly `iterations` samples come
// back -- but not its arithmetic: a dropped division leaves both of those true and silently
// restores the defect this slice repairs. Pinned by exact equality in AmortisedSamplesTests.
//
// Truncating, matching every gated mode (LineQueryBenchmark.swift:89): an operation cheaper
// than one clock tick reports 0, not 1.
func amortise(elapsedNanoseconds: Int64, operationsPerSample: Int) -> Int64 {
    precondition(operationsPerSample > 0, "operationsPerSample must be > 0")
    return elapsedNanoseconds / Int64(operationsPerSample)
}

// One clock read per iteration, `operationsPerSample` operations inside it, divided by
// `amortise` -- the measurement shape every gated mode uses (LineQueryBenchmark.swift:73-89),
// extracted so it lives in exactly one place and can be tested there.
//
// It serves the WRAP modes only. The twelve gated modes deliberately keep their own loops:
// any change to them can shift their numbers, and a shift drags a budget re-derivation under
// the headroom-ceiling rule (spec Non-Goal 1). Routing this through BenchmarkSummary /
// formatSummary was rejected for the same reason -- that printer is pinned by
// WorkflowShapeTests and the checksum tests, and it would put harvestability one wrong
// default away.
//
// `body` receives the GLOBAL operation index, so deterministicScrollOffset /
// deterministicIndex carry over unchanged, and returns an Int folded into `checksum` --
// which the caller must consume, or a release build is free to delete the measured work.
// Samples come back unsorted; the caller sorts before `percentile`.
@available(macOS 13.0, *)
func amortisedSamples(
    iterations: Int,
    operationsPerSample: Int,
    body: (Int) -> Int
) -> (samples: [Int64], checksum: Int) {
    precondition(iterations > 0, "iterations must be > 0")
    precondition(operationsPerSample > 0, "operationsPerSample must be > 0")

    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            checksum &+= body(iteration * operationsPerSample + operation)
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(
            amortise(elapsedNanoseconds: nanoseconds(elapsed),
                     operationsPerSample: operationsPerSample))
    }

    return (samples, checksum)
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter AmortisedSamplesTests > /tmp/slice54-t1-green.txt 2>&1; then
  echo "STILL RED"; rg -n "error:|XCTAssert" /tmp/slice54-t1-green.txt | head -20
else
  echo "green"
fi
rg -n "Executed [0-9]+ tests" /tmp/slice54-t1-green.txt | tail -2
```

Expected: `green`, 5 tests executed with 0 failures.

- [ ] **Step 7: Drill 1 — remove the division and record the red**

```bash
cd /Users/aabanschikov/swift-text-engine
cp Sources/ViewportBenchmarks/BenchmarkSupport.swift /tmp/slice54-drill1-backup.swift
sed -i '' 's|    return elapsedNanoseconds / Int64(operationsPerSample)|    return elapsedNanoseconds|' \
  Sources/ViewportBenchmarks/BenchmarkSupport.swift
if ! swift test --filter AmortisedSamplesTests > /tmp/slice54-drill1-red.txt 2>&1; then
  echo "DRILL 1 RED as required"
else
  echo "DRILL 1 DID NOT FAIL — the amortise pin cannot fail; stop and fix it"
fi
rg -n "XCTAssertEqual failed" /tmp/slice54-drill1-red.txt | head -5
cp /tmp/slice54-drill1-backup.swift Sources/ViewportBenchmarks/BenchmarkSupport.swift
if ! swift test --filter AmortisedSamplesTests > /tmp/slice54-drill1-restored.txt 2>&1; then
  echo "RESTORE FAILED"
else
  echo "restored green"
fi
```

Expected: `DRILL 1 RED as required`, at least three `XCTAssertEqual failed` lines from the two `amortise` tests, then `restored green`. Keep `/tmp/slice54-drill1-red.txt` for the verification record.

> **On drill 1's exact target.** The spec words it as "remove the division from `amortisedSamples`". Deleting the *call site* (appending `nanoseconds(elapsed)` directly) would **not** redden the `amortise` equality test — that test calls `amortise` directly. The mutation performed here is the one the pin actually catches: the division inside `amortise` itself. The call-site residual is covered by evidence rather than by a unit test — dropping the call would multiply every printed wrap value by `operationsPerSample` and restore the tick-multiple signature that AC4's recorded before/after comparison reads. Record this distinction in the verification record; do not claim a pin the suite does not have.

- [ ] **Step 8: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/ViewportBenchmarks/BenchmarkSupport.swift \
        Tests/ViewportBenchmarksTests/AmortisedSamplesTests.swift
git commit -m "feat: shared amortised measurement helper for the wrap benchmarks

amortisedSamples takes one clock read per iteration over operationsPerSample
operations and divides -- the shape every gated mode already uses -- so the wrap
modes stop timing a single operation and reporting raw clock ticks (D-23).

The division is a separate pure function, amortise, because ContinuousClock
cannot be substituted: a structural test pins the loop (call count, sample
count, index sequence) and would stay green if the division vanished. Exact
equality pins the arithmetic instead.

The helper serves the wrap modes only. The twelve gated modes keep their own
loops: changing them shifts their numbers and drags a budget re-derivation."
```

---

## Task 2: `--wrap-row-query` onto the helper

Spec Component Design (`WrapRowQueryBenchmark.swift`). AC1 (both wrap modes use the helper), AC4 (`query_operations_per_sample=`).

**Files:**
- Modify: `Sources/ViewportBenchmarks/WrapRowQueryBenchmark.swift:27-80`
- Create: `Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift`

**Interfaces:**
- Consumes: `amortisedSamples(iterations:operationsPerSample:body:)` and `amortise(...)` from Task 1; `wrapRowQueryChecksum(_ location: VisualRowLocation) -> Int` (already in this file, pinned by `WrapRowQueryChecksumTests`).
- Produces: `func formatWrapRowQueryLine(scenarioName: String, totalRows: Int, operationsPerSample: Int, p95Nanoseconds: Int64, p99Nanoseconds: Int64, checksum: Int) -> String` — the whole printed line, pure, so its token shape is unit-testable.

- [ ] **Step 1: Write the failing test**

Create `Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift`:

```swift
import XCTest
@testable import ViewportBenchmarks

// Both wrap modes' printed lines, pinned through their pure formatters.
//
// Two claims live here that were previously eyeballed:
//
//  1. Every measurement names its own operation count (`*_operations_per_sample=`), and
//     reindex's is the VALUE 1 rather than an absent token -- spec Decision 3: a missing
//     token reads as an oversight, a token reading 1 reads as a decision.
//  2. Neither line carries a BARE `p95_ns` / `p99_ns` key. That is the whole reason these
//     modes are inert to the harvester: harvest-gate-corpus.sh matches `p95_ns=` as a
//     substring but then requires the EXACT key, so `query_p95_ns=` yields no row. Node 6
//     flips this deliberately; until then, un-prefixing one by accident must be a red test,
//     not a surprise corpus row.
final class WrapBenchmarkLineShapeTests: XCTestCase {

    // The harvester's exact-key rule, mirrored: split on spaces, take the text before the
    // first `=`. `query_p95_ns` and `p95_ns` are different keys; substring matching is not.
    private func tokenKeys(_ line: String) -> [String] {
        line.split(separator: " ").map { String($0.split(separator: "=")[0]) }
    }

    private func value(_ key: String, in line: String) -> String? {
        for token in line.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == Substring(key) { return String(parts[1]) }
        }
        return nil
    }

    func testWrapRowQueryLineCarriesItsOperationCountAndNoBareLatencyKeys() {
        let line = formatWrapRowQueryLine(
            scenarioName: "uniform_1k", totalRows: 1_000, operationsPerSample: 256,
            p95Nanoseconds: 37, p99Nanoseconds: 41, checksum: 12_345)

        XCTAssertEqual(value("mode", in: line), "wrap_row_query")
        XCTAssertEqual(value("scenario", in: line), "uniform_1k")
        XCTAssertEqual(value("query_operations_per_sample", in: line), "256")
        XCTAssertEqual(value("query_p95_ns", in: line), "37")
        XCTAssertEqual(value("query_p99_ns", in: line), "41")
        XCTAssertEqual(value("checksum", in: line), "12345")

        let keys = tokenKeys(line)
        XCTAssertFalse(keys.contains("p95_ns"), "bare p95_ns would make this line harvestable")
        XCTAssertFalse(keys.contains("p99_ns"), "bare p99_ns would make this line harvestable")
    }

    func testWrapComputeLineCarriesThreeOperationCountsAndNoBareLatencyKeys() {
        let line = formatWrapComputeLine(
            widthLabel: "40", totalRows: 200_000,
            computeOperationsPerSample: 256, computeP95Nanoseconds: 210, computeP99Nanoseconds: 260,
            drainOperationsPerSample: 16, drainP95Nanoseconds: 4_100, drainP99Nanoseconds: 5_200,
            reindexNanoseconds: 61_000_000)

        XCTAssertEqual(value("mode", in: line), "wrap_compute")
        // scenario= is what both consumers group on (`mode|scenario`); the line carried only
        // width= before this slice, so node 6 would have had no grouping key.
        XCTAssertEqual(value("scenario", in: line), "width_40")
        XCTAssertEqual(value("width", in: line), "40")
        XCTAssertEqual(value("compute_operations_per_sample", in: line), "256")
        XCTAssertEqual(value("drain_operations_per_sample", in: line), "16")
        // Spec Decision 3: reindex is a one-shot O(N) setup, exempt from amortisation, and
        // the exemption is stated as a VALUE.
        XCTAssertEqual(value("reindex_operations_per_sample", in: line), "1")
        XCTAssertEqual(value("compute_p95_ns", in: line), "210")
        XCTAssertEqual(value("compute_p99_ns", in: line), "260")
        XCTAssertEqual(value("drain_p95_ns", in: line), "4100")
        // No gate can be derived from p95 alone: node 6 needs both statistics.
        XCTAssertEqual(value("drain_p99_ns", in: line), "5200")
        XCTAssertEqual(value("reindex_ns", in: line), "61000000")

        let keys = tokenKeys(line)
        XCTAssertFalse(keys.contains("p95_ns"), "bare p95_ns would make this line harvestable")
        XCTAssertFalse(keys.contains("p99_ns"), "bare p99_ns would make this line harvestable")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter WrapBenchmarkLineShapeTests > /tmp/slice54-t2-red.txt 2>&1; then
  echo "RED as expected"
else
  echo "UNEXPECTEDLY GREEN"
fi
rg -n "cannot find 'formatWrap" /tmp/slice54-t2-red.txt | head -4
```

Expected: `RED as expected`, with `cannot find 'formatWrapRowQueryLine' in scope` and `cannot find 'formatWrapComputeLine' in scope`. Both formatters are referenced now; `formatWrapComputeLine` lands in Task 3, so this file stays red until then — that is the intended sequencing, and Task 2's own step 4 filters to the row-query test.

- [ ] **Step 3: Rewrite the benchmark onto the helper**

In `Sources/ViewportBenchmarks/WrapRowQueryBenchmark.swift`, replace the whole `runWrapRowQueryBenchmarks()` function (currently lines 27-80) with:

```swift
// Pure so WrapBenchmarkLineShapeTests can pin the token shape without running the
// benchmark. The latency tokens stay PREFIXED (`query_p95_ns=`): the harvester requires
// the exact key `p95_ns`, so this line emits no corpus row. Node 6 flips that in the same
// slice that adds the gate step.
func formatWrapRowQueryLine(
    scenarioName: String,
    totalRows: Int,
    operationsPerSample: Int,
    p95Nanoseconds: Int64,
    p99Nanoseconds: Int64,
    checksum: Int
) -> String {
    "mode=wrap_row_query scenario=\(scenarioName) total_rows=\(totalRows)"
        + " query_operations_per_sample=\(operationsPerSample)"
        + " query_p95_ns=\(p95Nanoseconds)"
        + " query_p99_ns=\(p99Nanoseconds)"
        + " checksum=\(checksum)"
}

/// Observational only: NOT gateable, NOT wired into CI. Measured on the same amortised
/// shape as every gated mode (`amortisedSamples`): one clock read per iteration over 256
/// queries, divided. Timing a single query instead reported the host clock tick, not the
/// operation (D-23) -- the query costs a fraction of a tick, as its gated siblings' 17-94 ns
/// show.
@available(macOS 13.0, *)
func runWrapRowQueryBenchmarks() -> Bool {
    let rowHeight = 16.0
    let cells = 20
    let advance = 8.0
    let iterations = 5_000
    let operationsPerSample = 256

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

        // `sample` is the GLOBAL operation index, so the input sequence is exactly what the
        // single-operation loop produced -- only the clock reads changed.
        let measured = amortisedSamples(
            iterations: iterations, operationsPerSample: operationsPerSample
        ) { sample in
            let y: Double
            if scenario.clamped {
                let offset = Double(deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: 10_000))
                y = sample % 2 == 0 ? -(offset + 1.0) : totalHeight + offset
            } else {
                let row = deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: totalRows)
                y = Double(row) * rowHeight + rowHeight / 2.0
            }
            if case .row(let location) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) {
                return wrapRowQueryChecksum(location)
            }
            return 0
        }

        var querySamples = measured.samples
        querySamples.sort()
        print(formatWrapRowQueryLine(
            scenarioName: scenario.name,
            totalRows: totalRows,
            operationsPerSample: operationsPerSample,
            p95Nanoseconds: percentile(querySamples, numerator: 95, denominator: 100),
            p99Nanoseconds: percentile(querySamples, numerator: 99, denominator: 100),
            checksum: measured.checksum))
    }
    return true
}
```

Leave `WrapRowQueryScenario` (lines 3-8) and `wrapRowQueryChecksum` (lines 10-20) exactly as they are. Delete the old doc comment block at lines 22-26 — its content is folded into the new one above `runWrapRowQueryBenchmarks`.

- [ ] **Step 4: Run the row-query half of the test to verify it passes**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter WrapBenchmarkLineShapeTests/testWrapRowQueryLineCarriesItsOperationCountAndNoBareLatencyKeys \
     > /tmp/slice54-t2-green.txt 2>&1; then
  echo "STILL RED"; rg -n "error:|XCTAssert" /tmp/slice54-t2-green.txt | head -20
else
  echo "green"
fi
```

Expected: `green`.

- [ ] **Step 5: Run the mode and record the after-side output**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice54-t2-build.txt 2>&1; then
  echo "RELEASE BUILD RED"; tail -20 /tmp/slice54-t2-build.txt
else
  echo "release build green"
fi
swift run -c release ViewportBenchmarks -- --wrap-row-query > /tmp/slice54-after-wrap-row-query.txt 2>&1
cat /tmp/slice54-after-wrap-row-query.txt
echo "--- before ---"
cat /tmp/slice54-before-wrap-row-query.txt
```

Expected: four `mode=wrap_row_query` lines, each carrying `query_operations_per_sample=256`, and latency values that are **not** integer tick multiples (the whole point). Keep both files for the verification record. Do not predict a threshold here — the recorded pair is the evidence.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/ViewportBenchmarks/WrapRowQueryBenchmark.swift \
        Tests/ViewportBenchmarksTests/WrapBenchmarkLineShapeTests.swift
git commit -m "feat: --wrap-row-query measures on the amortised shape

5000 iterations x 256 queries under one clock read, divided -- the shape every
gated mode uses. Timing one query per clock.measure reported the host tick
(D-23); the query costs a fraction of one.

The printed line is extracted into formatWrapRowQueryLine so its token shape is
unit-testable: query_operations_per_sample= is now stated, and the test pins
that no BARE p95_ns/p99_ns key appears -- the exact-key rule that keeps this
mode inert to the harvester until node 6 flips it deliberately.

formatWrapComputeLine is referenced by the new test file and lands next."
```

---

## Task 3: `--wrap-compute` — amortise, de-contaminate, and repair the reindex site

Spec Decisions 3 and 4, and Component Design. AC3 (single live reindex construction), AC4 (three operation-count tokens), AC5 (drain ranges pre-built), AC6 (`scenario=`, `drain_p99_ns=`, tokens stay prefixed).

**Files:**
- Modify: `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift:54-108`

**Interfaces:**
- Consumes: `amortisedSamples(...)` (Task 1); `BenchmarkWrapLayout(lineCount:cells:advance:rowHeight:wrapWidth:)` and `deterministicScrollOffset(sample:maxOffset:)` (unchanged); `formatWrapComputeLine` is asserted by Task 2's test file.
- Produces: `func formatWrapComputeLine(widthLabel: String, totalRows: Int, computeOperationsPerSample: Int, computeP95Nanoseconds: Int64, computeP99Nanoseconds: Int64, drainOperationsPerSample: Int, drainP95Nanoseconds: Int64, drainP99Nanoseconds: Int64, reindexNanoseconds: Int64) -> String`.

- [ ] **Step 1: Run the failing test (it is already written, from Task 2)**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter WrapBenchmarkLineShapeTests/testWrapComputeLineCarriesThreeOperationCountsAndNoBareLatencyKeys \
     > /tmp/slice54-t3-red.txt 2>&1; then
  echo "RED as expected"
else
  echo "UNEXPECTEDLY GREEN"
fi
rg -n "cannot find 'formatWrapComputeLine'" /tmp/slice54-t3-red.txt | head -2
```

Expected: `RED as expected`, `cannot find 'formatWrapComputeLine' in scope`.

- [ ] **Step 2: Rewrite `runWrapComputeBenchmarks` and add the formatter**

In `Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`, replace the whole `runWrapComputeBenchmarks()` function (currently lines 54-108) with:

```swift
// Pure so WrapBenchmarkLineShapeTests can pin the token shape without running the
// benchmark. Latency tokens stay PREFIXED, so this line emits no corpus row.
//
// `scenario=` is new and inert today: both derive-gate-budgets.sh and GateFloorTests
// group on `mode|scenario`, and this line carried only `width=`, so node 6 would have had
// nothing to group on. `drain_p99_ns=` is new for the same reason -- no gate can be derived
// from p95 alone. Adding both here rather than at node 6 lets this slice's extract_rows()
// truth table cover the wrap_compute line shape end to end, and reduces node 6's flip to
// un-prefixing.
func formatWrapComputeLine(
    widthLabel: String,
    totalRows: Int,
    computeOperationsPerSample: Int,
    computeP95Nanoseconds: Int64,
    computeP99Nanoseconds: Int64,
    drainOperationsPerSample: Int,
    drainP95Nanoseconds: Int64,
    drainP99Nanoseconds: Int64,
    reindexNanoseconds: Int64
) -> String {
    "mode=wrap_compute scenario=width_\(widthLabel) width=\(widthLabel) total_rows=\(totalRows)"
        + " compute_operations_per_sample=\(computeOperationsPerSample)"
        + " compute_p95_ns=\(computeP95Nanoseconds)"
        + " compute_p99_ns=\(computeP99Nanoseconds)"
        + " drain_operations_per_sample=\(drainOperationsPerSample)"
        + " drain_p95_ns=\(drainP95Nanoseconds)"
        + " drain_p99_ns=\(drainP99Nanoseconds)"
        // reindex is a ONE-SHOT O(N) setup over 100 000 lines -- the width-change cost this
        // mode exists to demonstrate -- not a repeatable operation, so averaging it over
        // repetitions would destroy its meaning (spec Decision 3). The discriminator is
        // setup-vs-operation, NOT magnitude: `drain` measures in microseconds, as far above
        // tick granularity as reindex is, and is amortised anyway so node 6 promotes one
        // shape rather than two. The token is the VALUE 1 rather than absent, so the
        // exemption reads as a decision and not an oversight. Do not "consolidate" it.
        + " reindex_operations_per_sample=1"
        + " reindex_ns=\(reindexNanoseconds)"
}

@available(macOS 13.0, *)
func runWrapComputeBenchmarks() -> Bool {
    let lineCount = 100_000
    let cells = 80
    let advance = 1.0
    let rowHeight = 16.0
    let viewportHeight = 800.0
    let iterations = 2_000
    let computeOperationsPerSample = 256
    // drain walks the whole buffer per operation, so it takes the smaller count -- the
    // precedent BulkStructuralMutationBenchmark.swift:66-77 already sets for heavy scenarios.
    let drainOperationsPerSample = 16
    // deterministicScrollOffset is periodic with period 1 000 (BenchmarkSupport.swift), so
    // 1 000 pre-built ranges cover its entire image exactly. Sized independently of
    // drainOperationsPerSample -- and 1 000 is not a multiple of 16 -- so no drain sample
    // ever replays one range sixteen times.
    let drainRangeCount = 1_000
    let clock = ContinuousClock()

    // Wide (∞ -> 1 row/line) to narrow (more rows/line). Compute cost grows only as
    // O(log totalRows) across these -- viewport-bounded, NOT literally width-independent.
    let widths: [Double] = [.infinity, 40.0, 10.0]

    for width in widths {
        // The timed construction is BOUND and REUSED. It used to be discarded
        // (`_ = BenchmarkWrapLayout(...)`) with a second identical layout built for use:
        // two O(N) passes per width, and the mode's headline measurement was the one
        // carrying no dead-code guard while the far cheaper drain below did. Binding it
        // removes the second pass and makes the measured work observably live -- `layout`
        // is read on the very next line (spec Decision 3).
        let reindexStart = clock.now
        let layout = BenchmarkWrapLayout(
            lineCount: lineCount, cells: cells, advance: advance,
            rowHeight: rowHeight, wrapWidth: width)
        let reindexElapsed = reindexStart.duration(to: clock.now)

        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        let maxOffset = Double(totalRows) * rowHeight - viewportHeight

        func input(forOperation operation: Int) -> VariableViewportInput {
            VariableViewportInput(
                scrollOffsetY: deterministicScrollOffset(sample: operation, maxOffset: max(0, maxOffset)),
                viewportHeight: viewportHeight,
                overscanLinesBefore: 4,
                overscanLinesAfter: 4)
        }

        let computeMeasured = amortisedSamples(
            iterations: iterations, operationsPerSample: computeOperationsPerSample
        ) { operation in
            if case .success(let range) = ViewportVirtualizer.compute(input(forOperation: operation), layout: layout) {
                return range.bufferEndExclusive &- range.bufferStart
            }
            return 0
        }

        // Spec Decision 4: the ranges the drain body walks are built HERE, outside the clock.
        // Computing one inside the drain body would make drain_p95_ns measure compute+drain,
        // contradicting the two independent tokens this line prints and gating node 6 on the
        // wrong quantity. It is also a repair: the old shape ran compute and drain in the same
        // iteration, so every drain sample was contaminated by what the compute call before it
        // left in cache and branch predictors, while the two tokens claimed independence.
        var drainRanges: [VirtualRange] = []
        drainRanges.reserveCapacity(drainRangeCount)
        for index in 0..<drainRangeCount {
            switch ViewportVirtualizer.compute(input(forOperation: index), layout: layout) {
            case .success(let range):
                drainRanges.append(range)
            case .failure:
                preconditionFailure("wrap compute failed while pre-building the drain ranges")
            }
        }

        let drainMeasured = amortisedSamples(
            iterations: iterations, operationsPerSample: drainOperationsPerSample
        ) { operation in
            var cursor = ViewportVirtualizer.visualRowGeometry(
                for: drainRanges[operation % drainRangeCount], layout: layout)
            var sink = 0
            while let geometry = cursor.next() { sink &+= geometry.row.endColumn }
            return sink
        }

        var computeSamples = computeMeasured.samples
        var drainSamples = drainMeasured.samples
        computeSamples.sort()
        drainSamples.sort()

        // Keeps both measured bodies observably live without adding a token to a line the
        // harvester must keep ignoring -- the same guard the drain body carried before, now
        // covering compute as well.
        if computeMeasured.checksum &+ drainMeasured.checksum == Int.min { print("") }

        // No Foundation in this target: `String(format:)` is unavailable, so format the
        // (always-integral) finite widths via `Int(_:)` rather than importing Foundation.
        let widthLabel = width.isFinite ? String(Int(width)) : "inf"
        print(formatWrapComputeLine(
            widthLabel: widthLabel,
            totalRows: totalRows,
            computeOperationsPerSample: computeOperationsPerSample,
            computeP95Nanoseconds: percentile(computeSamples, numerator: 95, denominator: 100),
            computeP99Nanoseconds: percentile(computeSamples, numerator: 99, denominator: 100),
            drainOperationsPerSample: drainOperationsPerSample,
            drainP95Nanoseconds: percentile(drainSamples, numerator: 95, denominator: 100),
            drainP99Nanoseconds: percentile(drainSamples, numerator: 99, denominator: 100),
            reindexNanoseconds: nanoseconds(reindexElapsed)))
    }
    return true
}
```

Leave `BenchmarkWrapLayout` (lines 3-43) and `SingleLineWrap` (lines 45-52) untouched.

- [ ] **Step 3: Run the tests to verify they pass**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter WrapBenchmarkLineShapeTests > /tmp/slice54-t3-green.txt 2>&1; then
  echo "STILL RED"; rg -n "error:|XCTAssert" /tmp/slice54-t3-green.txt | head -20
else
  echo "green"
fi
rg -n "Executed [0-9]+ tests" /tmp/slice54-t3-green.txt | tail -2
```

Expected: `green`, 2 tests, 0 failures.

- [ ] **Step 4: Verify AC3 and AC5 by reading the diff (these two are deliberately not machine-checked)**

```bash
cd /Users/aabanschikov/swift-text-engine
git diff -- Sources/ViewportBenchmarks/WrapComputeBenchmark.swift > /tmp/slice54-wrapcompute.diff
DISCARDED="$(rg -n '_ = BenchmarkWrapLayout' Sources/ViewportBenchmarks/WrapComputeBenchmark.swift || true)"
if [ -z "$DISCARDED" ]; then
  echo "AC3 PASS: no discarded BenchmarkWrapLayout construction remains"
else
  echo "AC3 FAIL:"; echo "$DISCARDED"
fi
CONSTRUCTIONS="$(rg -c 'BenchmarkWrapLayout\(' Sources/ViewportBenchmarks/WrapComputeBenchmark.swift || true)"
echo "BenchmarkWrapLayout( occurrences in WrapComputeBenchmark.swift: $CONSTRUCTIONS (expect 1)"
COMPUTE_IN_DRAIN="$(rg -n 'visualRowGeometry' -A 4 Sources/ViewportBenchmarks/WrapComputeBenchmark.swift | rg 'ViewportVirtualizer.compute' || true)"
if [ -z "$COMPUTE_IN_DRAIN" ]; then
  echo "AC5 PASS: the drain body performs no compute"
else
  echo "AC5 FAIL:"; echo "$COMPUTE_IN_DRAIN"
fi
```

Expected: `AC3 PASS`, `occurrences … 1`, `AC5 PASS`. Then **read `/tmp/slice54-wrapcompute.diff` yourself** — spec Risks names this as the one guard that is a diff read rather than a test, and the greps above are an aid, not a substitute.

- [ ] **Step 5: Run the mode and record the after-side output, including the drain de-contamination**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice54-t3-build.txt 2>&1; then
  echo "RELEASE BUILD RED"; tail -20 /tmp/slice54-t3-build.txt
else
  echo "release build green"
fi
swift run -c release ViewportBenchmarks -- --wrap-compute > /tmp/slice54-after-wrap-compute.txt 2>&1
echo "--- after ---";  cat /tmp/slice54-after-wrap-compute.txt
echo "--- before ---"; cat /tmp/slice54-before-wrap-compute.txt
```

Expected: three `mode=wrap_compute` lines carrying `scenario=width_inf|width_40|width_10`, all three `*_operations_per_sample=` tokens, and `drain_p99_ns=`. Record the `drain_p95_ns` values on both sides — that pair is AC5's evidence (spec Testing Strategy, "Before/after evidence for Decision 4").

- [ ] **Step 6: Re-run the tick-multiple check on the repaired shape**

The after-side denominator comes from the **repaired** output shape, not from the before-side: `--wrap-compute` now prints **5** values per width, so the total is `8 + 3 × 5 = 23`.

```bash
cd /Users/aabanschikov/swift-text-engine
python3 - <<'PY' > /tmp/slice54-after-ticks.txt
import re
vals = []
for path, keys in (
    ("/tmp/slice54-after-wrap-row-query.txt", ("query_p95_ns", "query_p99_ns")),
    ("/tmp/slice54-after-wrap-compute.txt",
     ("compute_p95_ns", "compute_p99_ns", "drain_p95_ns", "drain_p99_ns", "reindex_ns")),
):
    for line in open(path):
        for k in keys:
            m = re.search(r"\b%s=(\d+)" % k, line)
            if m:
                vals.append((k, int(m.group(1))))
TICK = 1e9 / 24_000_000
hits = [v for _, v in vals if abs(v - round(v / TICK) * TICK) <= 1.0]
print("printed values:", len(vals), "(expected 23)")
print("within 1 ns of an integer tick multiple:", len(hits), "of", len(vals))
for k, v in vals:
    print("   %-16s %10d  ticks=%.3f" % (k, v, v / TICK))
PY
cat /tmp/slice54-after-ticks.txt
```

Expected: `printed values: 23`. The tick-multiple count should collapse — `reindex_ns` legitimately stays a tick multiple (a one-shot setup is quantised like anything else, which is expected and is **not** evidence of the defect). Record the ratio, not a predicted threshold.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Sources/ViewportBenchmarks/WrapComputeBenchmark.swift
git commit -m "feat: --wrap-compute amortises compute and drain, and repairs the reindex site

compute (256/sample) and drain (16/sample -- it walks the whole buffer) now run
through amortisedSamples. reindex_ns stays a SINGLE unamortised measurement: it
is a one-shot O(N) setup, not a repeatable operation, and averaging it would
destroy the width-change cost this mode exists to show. The exemption is stated
as a value, reindex_operations_per_sample=1, so it reads as a decision.

Two defects at the reindex site are repaired while it is open: the timed
construction was DISCARDED and an identical layout built again for use (two O(N)
passes per width), and the discarded one carried no dead-code guard while the
far cheaper drain below it did. It is now bound and reused -- one pass,
observably live.

Decision 4: the drain body's ranges are pre-built outside the clock and indexed
by global operation index. Computing one inside would make drain_p95_ns measure
compute+drain; it also removes the cache/branch-predictor contamination the old
compute-then-drain interleave left in every drain sample.

scenario= and drain_p99_ns= are added ahead of node 6 (both consumers group on
mode|scenario; no gate derives from p95 alone). Both are inert while the latency
tokens stay prefixed."
```

---

## Task 4: The Swift corpus reader learns the verdict column

Spec Decisions 6 and 7. AC9 (readers accept legacy five-column rows), AC12 (five-or-six columns, drill 5). **Must land before Task 6** — spec Decision 6 forces this order: the moment a six-column row reaches the corpus, a reader requiring exactly five goes red.

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift:52-81` (the reader) and append two tests

**Interfaces:**
- Consumes: `mostRecentRunIDs(_:limit:)`, `corpusExtremes(from:windowSize:)` (both already in this file).
- Produces:
  - `let rejectedVerdicts: Set<String>` = `["budget_exceeded", "budget_absolute_exceeded", "operation_failures"]`
  - `func isAdmissibleVerdict(_ verdict: String) -> Bool`
  - `func admissibleCorpusRows(from text: String) -> [String]` — header excluded, verdict filter only (no windowing), raw lines in input order. Task 5's cross-language pin consumes it.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ViewportBenchmarksTests/GateFloorTests.swift`, inside `final class GateFloorTests`, after `testWindowedExtremesDropAnAgedOutFreak()`:

```swift
    // The corpus schema's sixth column, and the back-compatibility claim, in one fixture.
    //
    // Five-column rows are LEGACY: the committed corpus consists entirely of them, and no
    // harvest produces them any more. An absent verdict means "unknown", which is admitted --
    // rejecting them would discard the whole corpus. Drill 5 mutates the reader to require
    // exactly six columns; the legacy row here is what reddens.
    //
    // The rejected rows still contribute their run ids to the WINDOW (spec Decision 8): the
    // verdict filter applies to row admission, after windowing, so neither window pin is
    // touched. Run 500 below is rejected on both its rows yet still occupies a window slot.
    func testSixColumnRowsAreReadAndFilteredByVerdict() {
        let corpus = """
        run_id\tmode\tscenario\tp95_ns\tp99_ns\tverdict
        500\tline_query\tuniform_1k\t900\t900\tbudget_exceeded
        500\tline_query\tuniform_1k\t901\t901\toperation_failures
        400\tline_query\tuniform_1k\t32\t64\tpass
        300\tline_query\tuniform_1k\t31\t62\tbudget_stale
        200\tline_query\tuniform_1k\t30\t60\tmissing_budget
        100\tline_query\tuniform_1k\t29\t58\tnone
        50\tline_query\tuniform_1k\t28\t56
        """

        // Window of 10 covers every run: what is dropped is dropped by VERDICT, not by age.
        let all = corpusExtremes(from: corpus, windowSize: 10)["line_query|uniform_1k"]
        XCTAssertEqual(all?.maxP95, 32, "a budget_exceeded row must not set the observed max")
        XCTAssertEqual(all?.maxP99, 64)
        XCTAssertEqual(all?.sampleCount, 5, "pass, budget_stale, missing_budget, none, legacy")

        // Window of 2 keeps runs {500, 400}. Run 500's rows are both rejected, so it
        // consumes a slot and contributes nothing -- the accepted cost in Decision 8.
        let windowed = corpusExtremes(from: corpus, windowSize: 2)["line_query|uniform_1k"]
        XCTAssertEqual(windowed?.maxP95, 32)
        XCTAssertEqual(windowed?.sampleCount, 1)
    }

    // The reject set itself, stated as a truth table so that adding or removing a case is a
    // deliberate edit against a list, not a silent set-literal change. Classified by what
    // happened to the MEASUREMENT, not by whether the gate passed.
    func testRejectSetIsExactlyThreeReasons() {
        XCTAssertEqual(rejectedVerdicts.count, 3)
        XCTAssertFalse(isAdmissibleVerdict("budget_exceeded"))         // slow
        XCTAssertFalse(isAdmissibleVerdict("budget_absolute_exceeded")) // slow, above the 60 FPS ceiling
        XCTAssertFalse(isAdmissibleVerdict("operation_failures"))       // degenerate timed path
        XCTAssertTrue(isAdmissibleVerdict("budget_stale"))              // FAST -- its fix NEEDS this data
        XCTAssertTrue(isAdmissibleVerdict("missing_budget"))            // valid, merely unjudgeable
        XCTAssertTrue(isAdmissibleVerdict("none"))                      // printed without --gate
        XCTAssertTrue(isAdmissibleVerdict(""))                          // legacy five-column row
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter "GateFloorTests/testSixColumnRowsAreReadAndFilteredByVerdict" \
     > /tmp/slice54-t4-red.txt 2>&1; then
  echo "RED as expected"
else
  echo "UNEXPECTEDLY GREEN"
fi
rg -n "cannot find 'rejectedVerdicts'|cannot find 'isAdmissibleVerdict'|malformed corpus row" /tmp/slice54-t4-red.txt | head -5
```

Expected: `RED as expected` — compile errors for the two new symbols (and, once they exist, `malformed corpus row` from the still-`== 5` reader).

- [ ] **Step 3: Add the reject set and teach the reader six columns**

In `Tests/ViewportBenchmarksTests/GateFloorTests.swift`, insert after the `mostRecentRunIDs` function (currently ending at line 30):

```swift
// The verdict values the derivation REFUSES. Classified by what happened to the
// MEASUREMENT, not by whether the gate passed: `budget_exceeded` and
// `budget_absolute_exceeded` mean the sample was SLOW -- the regression-laundering case,
// where one bad row sets a looser budget through the 3x-max term and
// testEveryCommittedBudgetReproducesFromCorpus then REQUIRES that looser budget to be
// committed. `operation_failures` means the timed path was degenerate, so the number
// measures nothing.
//
// `budget_stale` is admitted ON PURPOSE. It means the measurement was FAST enough that
// headroom breached its ceiling, and AGENTS.md's prescribed response is "re-derive from
// fresh hosted evidence" -- which requires harvesting exactly these rows. A filter that
// dropped them would instruct the operator to re-derive and simultaneously refuse to
// collect the evidence.
//
// Pinned byte-for-byte against REJECTED_VERDICTS in .github/scripts/derive-gate-budgets.sh
// by testAdmissibleRowsMatchDeriveScript -- the third cross-language pin, beside the two
// window pins. That pin covers AGREEMENT, not correctness: if both sides gain the same
// wrong entry, nothing notices.
let rejectedVerdicts: Set<String> = [
    "budget_exceeded",
    "budget_absolute_exceeded",
    "operation_failures",
]

// An EMPTY verdict is a legacy five-column row, admitted as "unknown": the committed corpus
// consists entirely of those, and the corpus is append-only, so they are never rewritten.
func isAdmissibleVerdict(_ verdict: String) -> Bool { !rejectedVerdicts.contains(verdict) }

// Corpus text -> the raw rows the derivation admits, header excluded, in input order.
// VERDICT FILTER ONLY -- windowing is a separate axis, pinned by the two window pins, and
// the shell seam this is compared against (`--admissible-rows`) does not window either.
// Returns the lines verbatim so the cross-language comparison is over bytes, not over a
// re-parse that could paper over a field-splitting disagreement.
func admissibleCorpusRows(from text: String) -> [String] {
    var admitted: [String] = []
    for (index, line) in text.split(separator: "\n").enumerated() {
        if index == 0 { continue }  // header
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        let verdict = columns.count >= 6 ? String(columns[5]) : ""
        if isAdmissibleVerdict(verdict) { admitted.append(String(line)) }
    }
    return admitted
}
```

Then, in `corpusExtremes(from:windowSize:)`, replace the parsing block (currently lines 59-68):

```swift
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        // Five OR six: five is a legacy row (the committed corpus is entirely legacy), six
        // carries the verdict every harvest now writes. Requiring exactly six would redden
        // on the committed corpus itself; requiring exactly five would redden the moment a
        // harvested row lands -- which is what forced this reader to learn the column
        // BEFORE the harvester started writing it (spec Decision 6).
        guard columns.count == 5 || columns.count == 6,
              let runID = Int64(columns[0]),
              let p95 = Int64(columns[3]),
              let p99 = Int64(columns[4]) else {
            XCTFail("malformed corpus row \(index + 1): \(line)")
            continue
        }
        // The run id is recorded BEFORE the verdict filter: the window is verdict-blind
        // (spec Decision 8), exactly as the shell's `cut -f1 | sort -rnu | head` is, so a
        // run whose every row is rejected still consumes a window slot.
        runIDs.append(runID)
        let verdict = columns.count == 6 ? String(columns[5]) : ""
        guard isAdmissibleVerdict(verdict) else { continue }
        rows.append(Row(runID: runID, key: "\(columns[1])|\(columns[2])", p95: p95, p99: p99))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter GateFloorTests > /tmp/slice54-t4-green.txt 2>&1; then
  echo "STILL RED"; rg -n "error:|XCTAssert|failed" /tmp/slice54-t4-green.txt | head -20
else
  echo "green"
fi
rg -n "Executed [0-9]+ tests" /tmp/slice54-t4-green.txt | tail -2
```

Expected: `green`. The whole `GateFloorTests` class runs, including `testEveryCommittedBudgetReproducesFromCorpus` over the untouched committed corpus — no budget may move.

- [ ] **Step 5: Drill 5 — require exactly six columns and record the red**

```bash
cd /Users/aabanschikov/swift-text-engine
cp Tests/ViewportBenchmarksTests/GateFloorTests.swift /tmp/slice54-drill5-backup.swift
sed -i '' 's|        guard columns.count == 5 || columns.count == 6,|        guard columns.count == 6,|' \
  Tests/ViewportBenchmarksTests/GateFloorTests.swift
if ! swift test --filter "GateFloorTests/testSixColumnRowsAreReadAndFilteredByVerdict" \
     > /tmp/slice54-drill5-red.txt 2>&1; then
  echo "DRILL 5 RED as required"
else
  echo "DRILL 5 DID NOT FAIL — the back-compatibility claim is untested; stop and fix it"
fi
rg -n "malformed corpus row" /tmp/slice54-drill5-red.txt | head -3
cp /tmp/slice54-drill5-backup.swift Tests/ViewportBenchmarksTests/GateFloorTests.swift
if ! swift test --filter GateFloorTests > /tmp/slice54-drill5-restored.txt 2>&1; then
  echo "RESTORE FAILED"
else
  echo "restored green"
fi
```

Expected: `DRILL 5 RED as required`, a `malformed corpus row` failure naming the legacy five-column fixture row, then `restored green`.

> If the `sed` leaves the file unchanged (the `||` needs no escaping in a `sed` s-command, but the shell does not expand it inside single quotes — verify), edit the line by hand instead and re-run. Assert the mutation landed before trusting the red: `rg -n 'columns.count == 6,' Tests/ViewportBenchmarksTests/GateFloorTests.swift`.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/ViewportBenchmarksTests/GateFloorTests.swift
git commit -m "test: the corpus reader learns the verdict column, five-or-six

The Swift half of the schema change lands FIRST, and the ordering is forced:
GateFloorTests read each row with columns.count == 5, so the moment the
harvester writes a six-column row, swift test goes red. The schema therefore
cannot reach one consumer without the other.

rejectedVerdicts is the reject set -- budget_exceeded and
budget_absolute_exceeded (slow), operation_failures (degenerate). budget_stale
is ADMITTED: it means the measurement was fast, and its prescribed response is
to re-derive from exactly these samples.

The window stays verdict-blind (Decision 8): a run id is recorded before the
filter, so a run whose every row is rejected still consumes a window slot and
neither window pin is touched."
```

---

## Task 5: The derivation applies the reject set, and the third cross-language pin

Spec Decisions 8, 11 (read side) and 12. AC11 (identical reject set in both consumers, pinned), drills 3 and 4.

**Files:**
- Modify: `.github/scripts/derive-gate-budgets.sh` (new constant + `admissible_rows()` + seam dispatch + main awk filter and stderr report + two self-test assertions)
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (append `testAdmissibleRowsMatchDeriveScript`)

**Interfaces:**
- Consumes: `admissibleCorpusRows(from:)` and `rejectedVerdicts` (Task 4); `runProcess(_:_:stdin:)` and `repositoryRoot()` (`ProcessSupport.swift`).
- Produces: `derive-gate-budgets.sh --admissible-rows` — reads a corpus **with header** on stdin, prints admitted rows **verbatim**, in input order, exit 0. Mirrors the existing `--window-run-ids` seam.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ViewportBenchmarksTests/GateFloorTests.swift`, inside `final class GateFloorTests`, after `testWindowSelectionMatchesDeriveScript()`:

```swift
    // The THIRD cross-language pin, beside testWindowConstantMatchesDeriveScript (the
    // window's N) and testWindowSelectionMatchesDeriveScript (the window's selection).
    // Those two cross-check WHICH ROWS are in scope; this one cross-checks WHICH ROWS ARE
    // ADMITTED. The reject set now lives in awk and in Swift, and nothing but this forces
    // them equal -- a divergence would mean the budget swift test re-derives is not the
    // budget the operator re-derives from the same corpus.
    //
    // Compared as raw LINES, not as re-parsed values: a field-splitting disagreement between
    // awk's -F'\t' and Swift's split(separator: "\t") would survive a value comparison.
    func testAdmissibleRowsMatchDeriveScript() throws {
        let scriptURL = repositoryRoot()
            .appendingPathComponent(".github/scripts/derive-gate-budgets.sh")

        // One row per verdict value the corpus can carry, plus a legacy five-column row.
        // Distinct run ids so nothing here depends on the window (this seam does not window).
        let corpus = """
        run_id\tmode\tscenario\tp95_ns\tp99_ns\tverdict
        901\tline_query\tuniform_1k\t10\t20\tpass
        902\tline_query\tuniform_1k\t11\t21\tbudget_exceeded
        903\tline_query\tuniform_1k\t12\t22\tbudget_absolute_exceeded
        904\tline_query\tuniform_1k\t13\t23\toperation_failures
        905\tline_query\tuniform_1k\t14\t24\tbudget_stale
        906\tline_query\tuniform_1k\t15\t25\tmissing_budget
        907\tline_query\tuniform_1k\t16\t26\tnone
        908\tline_query\tuniform_1k\t17\t27
        """

        let env = URL(fileURLWithPath: "/usr/bin/env")
        let result = try runProcess(
            env, ["bash", scriptURL.path, "--admissible-rows"], stdin: corpus + "\n")

        XCTAssertEqual(
            result.exitCode, 0,
            "derive-gate-budgets.sh --admissible-rows exited \(result.exitCode); "
                + "stderr: \(result.stderr)")

        let shellRows = result.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(
            shellRows, admissibleCorpusRows(from: corpus),
            "shell REJECTED_VERDICTS and Swift rejectedVerdicts disagree — the two corpus "
                + "consumers would derive different budgets from the same corpus; re-run "
                + "`.github/scripts/derive-gate-budgets.sh --self-test`")

        // Non-vacuity in BOTH directions. Without these, a seam that admitted everything
        // (or nothing) would pass as long as Swift did the same thing.
        XCTAssertEqual(shellRows.count, 5, "pass, budget_stale, missing_budget, none, legacy")
        XCTAssertTrue(
            shellRows.contains { $0.hasSuffix("\tbudget_stale") },
            "budget_stale must be ADMITTED: its prescribed fix is to re-derive from it")
        XCTAssertFalse(
            shellRows.contains { $0.hasSuffix("\tbudget_exceeded") },
            "budget_exceeded must be REJECTED: it is the regression-laundering row")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test --filter "GateFloorTests/testAdmissibleRowsMatchDeriveScript" \
     > /tmp/slice54-t5-red.txt 2>&1; then
  echo "RED as expected"
else
  echo "UNEXPECTEDLY GREEN"
fi
rg -n "exited [0-9]+|usage:" /tmp/slice54-t5-red.txt | head -5
```

Expected: `RED as expected` — the script treats `--admissible-rows` as a corpus path and exits non-zero.

- [ ] **Step 3: Add the reject set, the seam, and the filter to `derive-gate-budgets.sh`**

**3a.** After the `WINDOW=20` block (currently ending line 26), insert:

```bash
# The verdict values this derivation REFUSES, as the corpus's sixth column records them.
# Classified by what happened to the MEASUREMENT: budget_exceeded and
# budget_absolute_exceeded mean the sample was SLOW (the regression-laundering case -- one
# such row can set a budget by itself through the 3*max term); operation_failures means the
# timed path was degenerate. budget_stale is ADMITTED on purpose: it means the sample was
# FAST, and the prescribed response to it is to re-derive from exactly these rows.
# A legacy five-column row has no verdict and is admitted as "unknown".
#
# Pinned byte-for-byte against `rejectedVerdicts` in GateFloorTests.swift by
# testAdmissibleRowsMatchDeriveScript, over the --admissible-rows seam below. Keep this a
# bare top-of-file space-separated assignment.
REJECTED_VERDICTS="budget_exceeded budget_absolute_exceeded operation_failures"

# Corpus on stdin (WITH header) -> the rows this derivation admits, verbatim, in order.
# VERDICT FILTER ONLY: windowing is a separate axis (Decision 8 -- the verdict filter runs
# AFTER windowing, so neither window pin is touched, and a run whose rows are all rejected
# still consumes a window slot). $6 is empty for a five-column legacy row, which is why the
# empty case is tested explicitly rather than left to the substring search.
admissible_rows() {
  awk -F'\t' -v rejected=" $REJECTED_VERDICTS " '
    NR == 1 { next }
    $6 == "" { print; next }
    index(rejected, " " $6 " ") == 0 { print }
  '
}
```

**3b.** After the `--window-run-ids` dispatch block (currently ending line 115), insert:

```bash
# Test seam mirroring --window-run-ids: exposes the exact verdict filter the derivation
# applies at read time, so GateFloorTests.testAdmissibleRowsMatchDeriveScript can pin it to
# the Swift reader. Reads the corpus (WITH header) on stdin. Delegates -- it duplicates none
# of the rule.
if [[ "${1:-}" == "--admissible-rows" ]]; then
  admissible_rows
  exit 0
fi
```

**3c.** In the main `awk` invocation, add the reject set as a variable. Change the opening line from

```bash
awk -F'\t' -v modes="$modes" '
```

to

```bash
awk -F'\t' -v modes="$modes" -v rejected=" $REJECTED_VERDICTS " '
```

**3d.** In the same awk program, replace the row-accumulation block (currently lines 139-147) with:

```awk
{
  # Read-time verdict filter (spec Decision 6): the corpus is append-only full history, and
  # what is COUNTED is decided here, exactly as the N=20 window already is. A rejected row is
  # a sample whose own hosted line said the measurement was slow or degenerate; admitting it
  # would let one bad run set a looser budget through the 3*max term, and
  # testEveryCommittedBudgetReproducesFromCorpus would then REQUIRE that loosened budget to
  # be committed for swift test to go green.
  if ($6 != "" && index(rejected, " " $6 " ") > 0) { dropped[$6]++; next }

  seen[$2] = 1
  if (modes != "" && index(" " modes " ", " " $2 " ") == 0) next
  matched[$2] = 1
  k = $2 "|" $3
  n[k]++
  p95[k, n[k]] = $4
  p99[k, n[k]] = $5
}
```

**3e.** In the `END` block, immediately before `for (k in n) {`, insert:

```awk
  # Rejections are LOUD (spec Decision 12): silent filtering produces a corpus that looks
  # complete and is not. stderr, so stdout stays byte-identical for a corpus with nothing to
  # drop -- which is every corpus until the first post-slice-54 harvest lands. Emission order
  # is awk hash order; these are diagnostics, not a parsed format.
  #
  # NOTE: no apostrophes anywhere inside this awk program -- it is single-quoted in the
  # shell, so one would terminate the quote and break the script.
  for (r in dropped)
    printf "dropped=%s rows=%d\n", r, dropped[r] > "/dev/stderr"
```

**3f.** In `run_self_test()`, before `echo "self_test=pass"`, insert:

```bash
  # The reject set, at the seam the Swift pin drives. Kept here as well so a shell-only
  # change (someone editing REJECTED_VERDICTS without running swift test) still fails.
  local verdict_fixture
  verdict_fixture="$(mktemp)"
  {
    printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\tverdict\n'
    printf '901\tline_query\tuniform_1k\t10\t20\tpass\n'
    printf '902\tline_query\tuniform_1k\t11\t21\tbudget_exceeded\n'
    printf '903\tline_query\tuniform_1k\t12\t22\tbudget_stale\n'
    printf '904\tline_query\tuniform_1k\t13\t23\n'
  } > "$verdict_fixture"

  local expected_admitted
  expected_admitted="$(
    printf '901\tline_query\tuniform_1k\t10\t20\tpass\n'
    printf '903\tline_query\tuniform_1k\t12\t22\tbudget_stale\n'
    printf '904\tline_query\tuniform_1k\t13\t23\n'
  )"
  assert_equal "$expected_admitted" "$(admissible_rows < "$verdict_fixture")" \
    "admissible_rows drops budget_exceeded, keeps budget_stale and legacy rows"
  rm -f "$verdict_fixture"
```

- [ ] **Step 4: Run the shell self-test and the Swift pin**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! ./.github/scripts/derive-gate-budgets.sh --self-test > /tmp/slice54-t5-selftest.txt 2>&1; then
  echo "SELF-TEST RED"; cat /tmp/slice54-t5-selftest.txt
else
  echo "self-test green"; cat /tmp/slice54-t5-selftest.txt
fi
if ! swift test --filter GateFloorTests > /tmp/slice54-t5-green.txt 2>&1; then
  echo "STILL RED"; rg -n "error:|XCTAssert|failed" /tmp/slice54-t5-green.txt | head -20
else
  echo "green"
fi
```

Expected: `self_test=pass`, then `green`.

- [ ] **Step 5: Prove no budget moved (AC13, the byte-identity check)**

```bash
cd /Users/aabanschikov/swift-text-engine
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
git stash list > /dev/null
git show HEAD~1:.github/scripts/derive-gate-budgets.sh > /tmp/slice54-derive-before.sh
bash /tmp/slice54-derive-before.sh "$CORPUS" > /tmp/slice54-derive-before.txt 2>/tmp/slice54-derive-before.err
bash ./.github/scripts/derive-gate-budgets.sh "$CORPUS" > /tmp/slice54-derive-after.txt 2>/tmp/slice54-derive-after.err
if diff -u /tmp/slice54-derive-before.txt /tmp/slice54-derive-after.txt > /tmp/slice54-derive.diff 2>&1; then
  echo "AC13 PASS: derivation stdout is byte-identical"
else
  echo "AC13 FAIL:"; cat /tmp/slice54-derive.diff
fi
echo "dropped rows reported: $(cat /tmp/slice54-derive-after.err)"
if [ -z "$(cat /tmp/slice54-derive-after.err)" ]; then
  echo "no rows dropped (expected: the committed corpus is entirely legacy five-column)"
else
  echo "UNEXPECTED DROPS — investigate"
fi
if git diff --quiet -- "$CORPUS"; then echo "corpus untouched"; else echo "CORPUS MODIFIED — revert"; fi
```

Expected: `AC13 PASS`, no dropped rows, `corpus untouched`.

> `HEAD~1` here is Task 4's commit, whose `derive-gate-budgets.sh` is the pre-slice one (Tasks 1-4 do not touch it). If the task order was changed, use `git show <ref-before-this-task>:...` instead — the point is a before/after over this task's script change.

- [ ] **Step 6: Drills 3 and 4 — both directions of the pin**

```bash
cd /Users/aabanschikov/swift-text-engine
cp .github/scripts/derive-gate-budgets.sh /tmp/slice54-drill34-backup.sh

# Drill 3: UNDER-filtering. Remove budget_exceeded from the shell's reject set.
sed -i '' 's|^REJECTED_VERDICTS="budget_exceeded budget_absolute_exceeded operation_failures"|REJECTED_VERDICTS="budget_absolute_exceeded operation_failures"|' \
  .github/scripts/derive-gate-budgets.sh
if ! rg -q '^REJECTED_VERDICTS="budget_absolute_exceeded operation_failures"' .github/scripts/derive-gate-budgets.sh; then
  echo "MUTATION DID NOT LAND — edit by hand and re-run"
fi
if ! swift test --filter "GateFloorTests/testAdmissibleRowsMatchDeriveScript" > /tmp/slice54-drill3-red.txt 2>&1; then
  echo "DRILL 3 RED as required"
else
  echo "DRILL 3 DID NOT FAIL — the pin is blind to under-filtering; stop and fix it"
fi
cp /tmp/slice54-drill34-backup.sh .github/scripts/derive-gate-budgets.sh

# Drill 4: OVER-filtering. Add budget_stale to the shell's reject set.
sed -i '' 's|^REJECTED_VERDICTS="budget_exceeded budget_absolute_exceeded operation_failures"|REJECTED_VERDICTS="budget_exceeded budget_absolute_exceeded operation_failures budget_stale"|' \
  .github/scripts/derive-gate-budgets.sh
if ! rg -q 'operation_failures budget_stale"' .github/scripts/derive-gate-budgets.sh; then
  echo "MUTATION DID NOT LAND — edit by hand and re-run"
fi
if ! swift test --filter "GateFloorTests/testAdmissibleRowsMatchDeriveScript" > /tmp/slice54-drill4-red.txt 2>&1; then
  echo "DRILL 4 RED as required"
else
  echo "DRILL 4 DID NOT FAIL — the pin is blind to over-filtering; stop and fix it"
fi
cp /tmp/slice54-drill34-backup.sh .github/scripts/derive-gate-budgets.sh

if ! swift test --filter GateFloorTests > /tmp/slice54-drill34-restored.txt 2>&1; then
  echo "RESTORE FAILED"
else
  echo "restored green"
fi
```

Expected: `DRILL 3 RED as required`, `DRILL 4 RED as required`, `restored green`. Drill 4 is the one that matters most conceptually — it proves the rule is pinned against **over**-filtering too, so nobody can quietly "harden" the set by dropping `budget_stale`, the row whose own fix requires it.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add .github/scripts/derive-gate-budgets.sh Tests/ViewportBenchmarksTests/GateFloorTests.swift
git commit -m "feat: the derivation rejects slow and degenerate rows at read time

The reject set is {budget_exceeded, budget_absolute_exceeded,
operation_failures} -- what happened to the MEASUREMENT, not whether the gate
passed. budget_stale is admitted: it means the sample was fast, and the
prescribed response to it is to re-derive from exactly these rows.

Applied at READ time on the sixth column, not at harvest, following this
repository's own pattern: the corpus is append-only full history and the N=20
window is already a read-time concept. The filter runs AFTER windowing, so
neither window pin is touched.

--admissible-rows is the seam, mirroring --window-run-ids, and
testAdmissibleRowsMatchDeriveScript is the third cross-language pin. Rejections
are loud: per-reason dropped-row counts go to stderr, so stdout stays
byte-identical -- verified against the committed corpus, which is entirely
legacy five-column and drops nothing."
```

---

## Task 6: `extract_rows()` — the parser becomes testable and writes the verdict

Spec Decisions 7 and 9. AC8 (parser extracted, truth table under `--self-test`), AC9 (sixth column on every emitted row), AC10 (`failures=` outranks the verdict), drill 7.

**Files:**
- Modify: `.github/scripts/harvest-gate-corpus.sh` (usage header, new `extract_rows()`, call site, self-test)

**Interfaces:**
- Consumes: nothing new.
- Produces: `extract_rows <run_id>` — reads a hosted CI log on **stdin**, writes six-column TSV rows on stdout: `run_id \t mode \t scenario \t p95_ns \t p99_ns \t verdict`.

- [ ] **Step 1: Write the failing self-test**

In `.github/scripts/harvest-gate-corpus.sh`, inside `run_self_test()`, before `rm -f "$fixture" "$empty"`, insert:

```bash
  # ------------------------------------------------------------------
  # extract_rows: the parser, previously unreachable from --self-test because it
  # lived inside the network branch. Putting the new verdict rule there as-is would
  # have produced a guard with no way to fail -- the defect class this slice exists
  # to prevent. Extracting it also brings the EXISTING five-column parser under test
  # for the first time, including the prefixed-token protection both wrap modes rely on.
  # ------------------------------------------------------------------
  local logfixture
  logfixture="$(mktemp)"
  {
    # 1. A gated pass line.
    printf 'mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=24 p99_ns=54 failures=0 budget_p95_ns=190 budget_p99_ns=440 headroom_p95=7.9x headroom_p99=8.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=30864.1x gate=pass checksum=1\n'
    # 2. The regression-laundering row: slow, and must never enter the corpus as evidence
    #    of normal cost. The summary line is printed BEFORE the verdict is checked, so it
    #    genuinely reaches a hosted log.
    printf 'mode=line_query provider=uniform scenario=uniform_100k p95_ns=30 p99_ns=60 failures=0 budget_p95_ns=280 budget_p99_ns=560 gate=fail reason=budget_exceeded checksum=2\n'
    # 3. budget_stale: the sample was FAST. Admitted -- its prescribed fix needs it.
    printf 'mode=line_query provider=uniform scenario=uniform_1m p95_ns=31 p99_ns=61 failures=0 budget_p95_ns=320 budget_p99_ns=640 gate=fail reason=budget_stale checksum=3\n'
    # 4. A step run WITHOUT --gate: no gate= token at all. Admitted as `none` -- a new
    #    mode's first hosted evidence necessarily looks like this, because its budget does
    #    not exist yet, and rejecting it would make a gate unbootstrappable.
    printf 'mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=40 p99_ns=70 failures=0 checksum=4\n'
    # 5. THE NODE-6 BOOTSTRAP HOLE: no gate= token AND failures=3. Degeneracy must be read
    #    from failures=, which formatSummary prints unconditionally, or this line -- the
    #    exact shape node 6's first harvest produces -- is admitted as healthy.
    printf 'mode=column_query provider=uniform scenario=uniform_100k p95_ns=41 p99_ns=71 failures=3 checksum=5\n'
    # 6. failures= OUTRANKS the verdict: gate=pass cannot launder a degenerate timing.
    printf 'mode=point_query provider=uniform scenario=uniform_1k p95_ns=42 p99_ns=72 failures=2 budget_p95_ns=900 budget_p99_ns=1800 gate=pass checksum=6\n'
    # 7. A wrap_row_query line: PREFIXED latency tokens -> NO ROW. Nothing on the shell side
    #    pinned this before.
    printf 'mode=wrap_row_query scenario=uniform_1k total_rows=1000 query_operations_per_sample=256 query_p95_ns=37 query_p99_ns=41 checksum=7\n'
    # 8. A wrap_compute line, full node-6-ready shape (scenario=, drain_p99_ns=) with the
    #    latency tokens still prefixed -> NO ROW.
    printf 'mode=wrap_compute scenario=width_40 width=40 total_rows=200000 compute_operations_per_sample=256 compute_p95_ns=210 compute_p99_ns=260 drain_operations_per_sample=16 drain_p95_ns=4100 drain_p99_ns=5200 reindex_operations_per_sample=1 reindex_ns=61000000\n'
    # 9. Shape 2, the pre-slice-45 realistic relative observation: 2 base + 2 head -> 4 rows.
    printf 'mode=realistic_relative_observation base_p95_ns_values=11,12 base_p99_ns_values=21,22 head_p95_ns_values=13,14 head_p99_ns_values=23,24\n'
    # 10. A real `gh run view --log` line carries a job/step/timestamp prefix. awk scans all
    #     fields, so the prefix is inert -- pinned rather than assumed.
    printf 'Host tests and benchmark gate\tSynthetic gate\t2026-08-23T10:00:00Z mode=pipeline provider=uniform scenario=uniform_1k p95_ns=50 p99_ns=80 failures=0 budget_p95_ns=500 budget_p99_ns=1000 gate=pass checksum=10\n'
    # 11. Beyond the spec truth table, fail-closed: gate=fail with no reason= cannot be
    #     produced by formatSummary, so if one ever appears something is wrong. Treat it as
    #     the rejecting verdict rather than admitting it.
    printf 'mode=pipeline provider=uniform scenario=uniform_100k p95_ns=51 p99_ns=81 failures=0 budget_p95_ns=500 budget_p99_ns=1000 gate=fail checksum=11\n'
  } > "$logfixture"

  local expected_rows
  expected_rows="$(
    printf '999\tline_query\tuniform_1k\t24\t54\tpass\n'
    printf '999\tline_query\tuniform_100k\t30\t60\tbudget_exceeded\n'
    printf '999\tline_query\tuniform_1m\t31\t61\tbudget_stale\n'
    printf '999\tcolumn_query\tuniform_1k\t40\t70\tnone\n'
    printf '999\tcolumn_query\tuniform_100k\t41\t71\toperation_failures\n'
    printf '999\tpoint_query\tuniform_1k\t42\t72\toperation_failures\n'
    printf '999\trealistic_provider\t100k_lines_10mb_text\t11\t21\tnone\n'
    printf '999\trealistic_provider\t100k_lines_10mb_text\t12\t22\tnone\n'
    printf '999\trealistic_provider\t100k_lines_10mb_text\t13\t23\tnone\n'
    printf '999\trealistic_provider\t100k_lines_10mb_text\t14\t24\tnone\n'
    printf '999\tpipeline\tuniform_1k\t50\t80\tpass\n'
    printf '999\tpipeline\tuniform_100k\t51\t81\tbudget_exceeded\n'
  )"

  assert_equal "$expected_rows" "$(extract_rows 999 < "$logfixture")" \
    "extract_rows: six columns, failures= outranks the verdict, prefixed wrap lines emit nothing"

  rm -f "$logfixture"
```

Also extend the final cleanup line from `rm -f "$fixture" "$empty"` to keep working (it already does — `$logfixture` is removed above).

- [ ] **Step 2: Run the self-test to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! ./.github/scripts/harvest-gate-corpus.sh --self-test > /tmp/slice54-t6-red.txt 2>&1; then
  echo "RED as expected"
else
  echo "UNEXPECTEDLY GREEN"
fi
cat /tmp/slice54-t6-red.txt
```

Expected: `RED as expected`, with `extract_rows: command not found` (the function does not exist yet).

- [ ] **Step 3: Extract the parser and add the verdict**

**3a.** Replace the usage-header schema block (currently lines 14-15) with:

```bash
# Emits corpus rows on stdout (no header), ready to append:
#   run_id <TAB> mode <TAB> scenario <TAB> p95_ns <TAB> p99_ns <TAB> verdict
#
# The sixth column is the ROW'S OWN gate verdict: `pass`, a GateFailureReason raw value, or
# `none` for a summary line printed without --gate. It is the only place the corpus schema
# is written down. Readers accept legacy FIVE-column rows -- the committed corpus consists
# entirely of them -- and treat a missing verdict as admissible.
#
# derive-gate-budgets.sh and GateFloorTests then REFUSE, at read time, rows whose verdict is
# budget_exceeded, budget_absolute_exceeded or operation_failures: a summary line is printed
# BEFORE the gate verdict is checked, so a slow sample genuinely reaches a hosted log, and
# the 3*max term lets one such row set a budget by itself.
```

**3b.** After `plan_runs()` (currently ending line 57), insert **one** new function — the verdict rule lives inside its awk program, nowhere else:

```bash
# The corpus-row parser: a hosted CI log on stdin, six-column TSV rows on stdout.
# $1 = run id.
#
# Extracted from the network branch (spec Decision 9) so --self-test can drive it over a
# fixture. Leaving it inline would have made the verdict rule a guard with no way to fail --
# the exact defect class this slice exists to prevent -- and it retroactively brings the
# existing five-column parser under test for the first time, including the exact-key rule
# that keeps the prefixed wrap lines from emitting rows.
extract_rows() {
  awk -v run="$1" '
    # Row-level verdict for one summary line.
    #
    # `failures=` OUTRANKS the gate verdict, and that is not belt-and-braces. formatSummary
    # prints failures=N UNCONDITIONALLY, outside the --gate branch
    # (BenchmarkSupport.swift:103), whereas gate=/reason= appear only on gated steps -- and
    # the FIRST hosted evidence for a new mode necessarily comes from an ungated step,
    # because its budget does not exist yet. Reading degeneracy from the verdict alone would
    # therefore miss it on exactly the line shape node 6 bootstraps with.
    #
    # gate=fail with no reason= cannot be produced by formatSummary; if one ever appears,
    # something is wrong, so it takes the REJECTING verdict rather than the admitting one.
    function verdict(g, r, f) {
      if (f != "" && f + 0 != 0) return "operation_failures"
      if (g == "pass") return "pass"
      if (g == "fail") return (r != "" ? r : "budget_exceeded")
      return "none"
    }

    function emit_pairs(a, b,   x, y, n, m, i) {
      if (a == "" || b == "") return
      n = split(a, x, ",")
      m = split(b, y, ",")
      if (n != m) return
      for (i = 1; i <= n; i++)
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", run, "realistic_provider", "100k_lines_10mb_text", x[i], y[i], "none"
    }

    # Shape 2 must be tested first: it carries mode= and *_p95_ns_values= but no
    # bare p95_ns=, so shape 1 would not match it anyway -- the order is for the
    # reader, not the parser. It comes from a step run WITHOUT --gate, so `none`.
    /mode=realistic_relative_observation/ {
      bp95 = ""; bp99 = ""; hp95 = ""; hp99 = ""
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "base_p95_ns_values") bp95 = kv[2]
        else if (kv[1] == "base_p99_ns_values") bp99 = kv[2]
        else if (kv[1] == "head_p95_ns_values") hp95 = kv[2]
        else if (kv[1] == "head_p99_ns_values") hp99 = kv[2]
      }
      emit_pairs(bp95, bp99)
      emit_pairs(hp95, hp99)
      next
    }

    # The regex is a cheap line filter; the EXACT key is what decides. That distinction is
    # what makes the wrap modes inert: `query_p95_ns=37` matches the regex and then fails
    # kv[1] == "p95_ns", so the line yields no row until node 6 un-prefixes it deliberately.
    /p95_ns=[0-9]+/ && /p99_ns=[0-9]+/ {
      mode = ""; scenario = ""; p95 = ""; p99 = ""; gate = ""; reason = ""; failures = ""
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "mode") mode = kv[2]
        else if (kv[1] == "scenario") scenario = kv[2]
        else if (kv[1] == "p95_ns") p95 = kv[2]
        else if (kv[1] == "p99_ns") p99 = kv[2]
        else if (kv[1] == "gate") gate = kv[2]
        else if (kv[1] == "reason") reason = kv[2]
        else if (kv[1] == "failures") failures = kv[2]
      }
      if (mode != "" && scenario != "" && p95 != "" && p99 != "")
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", run, mode, scenario, p95, p99, verdict(gate, reason, failures)
    }
  '
}
```

Delete the now-unused `verdict_of` helper if it was added — it is **not** needed; the awk-internal `verdict()` function is the single implementation. (Written out above only to show the rule in isolation; do **not** add both. Add the `extract_rows` function only.)

**3c.** Replace the call site (currently lines 182-221, the whole `printf '%s\n' "$log" | awk -v run="$id" '...'` block) with:

```bash
  printf '%s\n' "$log" | extract_rows "$id"
```

**3d.** Update the comment at line ~175 (inside the log-fetch block) from

```
  # partial corpus is exactly the failure mode the slice-38 record warns about
  # ("harvest EVERY available hosted run, not a convenient subset").
```

to

```
  # partial corpus is exactly the failure mode the slice-38 record warns about
  # ("harvest EVERY available hosted run, not a convenient subset"). Since slice 54
  # "available" means "available AND admissible": a run whose source repository is not
  # this one, and a row whose own line reports a slow or degenerate measurement, are
  # excluded on purpose and said out loud on stderr. That is a policy, not a convenience.
```

- [ ] **Step 4: Run the self-test to verify it passes**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! ./.github/scripts/harvest-gate-corpus.sh --self-test > /tmp/slice54-t6-green.txt 2>&1; then
  echo "STILL RED"; cat /tmp/slice54-t6-green.txt
else
  echo "self-test green"; cat /tmp/slice54-t6-green.txt
fi
if ! swift test --filter ScriptSelfTestTests > /tmp/slice54-t6-swift.txt 2>&1; then
  echo "SWIFT DRIVER RED"; rg -n "XCTAssert|self_test=fail" /tmp/slice54-t6-swift.txt | head -10
else
  echo "swift driver green"
fi
```

Expected: `self_test=pass` and `swift driver green` — `ScriptSelfTestTests` drives every script's `--self-test` under `swift test`, so this truth table is build-failing with no new infrastructure.

- [ ] **Step 5: Drill 7 — remove the `failures=` clause and record the red**

This is the drill that matters most: it is the only guard whose gap sits on node 6's own bootstrap path, where no verdict token exists to catch it.

```bash
cd /Users/aabanschikov/swift-text-engine
cp .github/scripts/harvest-gate-corpus.sh /tmp/slice54-drill7-backup.sh
sed -i '' 's|      if (f != "" \&\& f + 0 != 0) return "operation_failures"|      if (0) return "operation_failures"|' \
  .github/scripts/harvest-gate-corpus.sh
if ! rg -q 'if \(0\) return "operation_failures"' .github/scripts/harvest-gate-corpus.sh; then
  echo "MUTATION DID NOT LAND — edit the verdict() function by hand and re-run"
fi
if ! ./.github/scripts/harvest-gate-corpus.sh --self-test > /tmp/slice54-drill7-red.txt 2>&1; then
  echo "DRILL 7 RED as required"
else
  echo "DRILL 7 DID NOT FAIL — the bootstrap hole is unguarded; stop and fix it"
fi
cat /tmp/slice54-drill7-red.txt
cp /tmp/slice54-drill7-backup.sh .github/scripts/harvest-gate-corpus.sh
if ! ./.github/scripts/harvest-gate-corpus.sh --self-test > /tmp/slice54-drill7-restored.txt 2>&1; then
  echo "RESTORE FAILED"
else
  echo "restored green"
fi
```

Expected: `DRILL 7 RED as required`, with a `self_test=fail` diff showing the ungated `failures=3` line recorded as `none` instead of `operation_failures` (and the `gate=pass failures=2` line as `pass`), then `restored green`.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add .github/scripts/harvest-gate-corpus.sh
git commit -m "feat: extract_rows writes the verdict column and is finally testable

The awk parser moves out of the network branch into a function over stdin, so
--self-test can drive it over a fixture -- and putting the new rule where it
was would have produced a guard with no way to fail. It retroactively brings the
EXISTING five-column parser under test for the first time, including the
exact-key rule that keeps both prefixed wrap modes from emitting corpus rows.

Every emitted row now carries a sixth column: the row's own gate verdict, or
`none` for a line printed without --gate. Verdict-less lines are admitted on
purpose: a new mode's first hosted evidence necessarily comes from an ungated
step, because its budget does not exist yet.

Degeneracy is read from failures=, NOT from the verdict, and that closes the
hole the `none` exemption would otherwise open exactly where node 6 lands:
failures= is printed unconditionally, so an ungated degenerate line -- node 6's
own bootstrap shape -- is caught. It is strictly stronger on gated lines too,
since gateFailureReason returns .missingBudget before it tests failureCount."
```

---

## Task 7: Run-source provenance, failing closed

Spec Decisions 10, 11 and 12. AC7 (foreign runs rejected, unknown source fails closed, `--runs` obeys the same policy), drill 2.

**Files:**
- Modify: `.github/scripts/harvest-gate-corpus.sh` (new `admissible_source()`, self-test truth table, network wiring, usage text)

**Interfaces:**
- Consumes: `plan_runs` decisions (unchanged).
- Produces: `admissible_source <run_id> <observed_repo> <expected_repo>` → exactly one line: `plan=harvest run=<id>` / `skip=foreign_repo run=<id> source=<observed>` / `skip=provenance_unknown run=<id>`.

- [ ] **Step 1: Write the failing self-test**

In `run_self_test()`, after the `extract_rows` assertion added in Task 6, insert:

```bash
  # ------------------------------------------------------------------
  # admissible_source: the run-level axis. A fork executes its own code and can print
  # gate=pass beside any number it likes, so no per-row check helps here -- and the
  # --runs id,id entry path bypassed even the workflow filter, so this was the one
  # unauthenticated link in a chain carrying twelve blocking budgets.
  # ------------------------------------------------------------------
  assert_equal "plan=harvest run=555" \
    "$(admissible_source 555 'maldrakar/swift-text-engine' 'maldrakar/swift-text-engine')" \
    "admissible_source admits a run whose head repository is the harvested one"

  assert_equal "skip=foreign_repo run=555 source=attacker/swift-text-engine" \
    "$(admissible_source 555 'attacker/swift-text-engine' 'maldrakar/swift-text-engine')" \
    "admissible_source rejects a fork's run and names the source it saw"

  # Fails CLOSED. An unreadable provenance (deleted branch, 404, expired token, rate
  # limit) is the one state a fork can manufacture, so unknown must mean rejected --
  # there is deliberately no --allow-failed escape hatch: an optional policy is not one.
  assert_equal "skip=provenance_unknown run=555" \
    "$(admissible_source 555 '' 'maldrakar/swift-text-engine')" \
    "admissible_source fails closed when the source cannot be read"

  # `gh api --jq` prints the four characters `null` for a null field, which is not a
  # repository name and must not be compared as one.
  assert_equal "skip=provenance_unknown run=555" \
    "$(admissible_source 555 'null' 'maldrakar/swift-text-engine')" \
    "admissible_source treats a null head repository as unknown, not as a foreign name"
```

- [ ] **Step 2: Run the self-test to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! ./.github/scripts/harvest-gate-corpus.sh --self-test > /tmp/slice54-t7-red.txt 2>&1; then
  echo "RED as expected"
else
  echo "UNEXPECTEDLY GREEN"
fi
cat /tmp/slice54-t7-red.txt
```

Expected: `RED as expected`, `admissible_source: command not found`.

- [ ] **Step 3: Implement `admissible_source` and wire it into the network half**

**3a.** After `plan_runs()` and before `extract_rows()`, insert:

```bash
# Pure decision over (run id, observed head repository, expected repository).
#
# Neither `gh run list --json` nor `gh run view --json` exposes the source repository --
# both field lists were checked and it is absent. The datum lives at
# `gh api repos/{owner}/{repo}/actions/runs/{id}` as `.head_repository.full_name`.
#
# Rejected alternative: switching candidate selection to the workflow-runs API, which
# returns ids and sources together in one call. It rewrites the selection path wholesale
# and the --runs entry path would still need per-run lookups, so the policy would have two
# implementations. One call per candidate at N <= 40 is not worth a second code path.
# Likewise rejected: skipping the probe for `event != pull_request` runs, which cannot have
# a foreign head repository. It buys nothing the --corpus dedup does not already buy, and
# costs the same second code path.
admissible_source() {
  local id="$1" observed="$2" expected="$3"
  # Fail CLOSED on an unreadable source: that is the one state a fork can manufacture.
  # `null` is what `gh api --jq` prints for a null field -- it is not a repository name.
  if [[ -z "$observed" || "$observed" == "null" ]]; then
    printf 'skip=provenance_unknown run=%s\n' "$id"
  elif [[ "$observed" != "$expected" ]]; then
    printf 'skip=foreign_repo run=%s source=%s\n' "$id" "$observed"
  else
    printf 'plan=harvest run=%s\n' "$id"
  fi
}
```

**3b.** In the main loop, insert the network probe **after** the `--dry-run` block and **before** the `gh run view … --log` fetch:

```bash
  # Provenance, per run. Placed after the dedup skip and before the log fetch, so a run
  # already in the corpus still costs ZERO API calls -- the existing property this must not
  # break. Applied to BOTH entry paths, --runs included: that path bypassed even the
  # workflow filter, so a caller passing an inadmissible id now gets a loud skip= and no
  # row (a deliberate behaviour change to a documented flag).
  #
  # `< /dev/null` so gh cannot swallow the while-loop's stdin, exactly as the log fetch
  # below does. `|| true` turns any gh failure into an empty source, which admissible_source
  # rejects -- fail-closed by construction rather than by a second branch.
  source_repo="$(gh api "repos/$repo/actions/runs/$id" \
    --jq '.head_repository.full_name' < /dev/null 2>/dev/null || true)"
  source_decision="$(admissible_source "$id" "$source_repo" "$repo")"
  if [[ "$source_decision" == skip=* ]]; then
    echo "$source_decision" >&2
    continue
  fi
```

**3c.** Extend the `--dry-run` block's comment (currently the bare `if [[ "$dry_run" == 1 ]]` branch) so the omission is deliberate rather than discovered:

```bash
  # --dry-run stays NETWORK-FREE: it previews the dedup decision only. The provenance
  # decision below costs one API call per candidate, which is the thing a dry run exists to
  # avoid. A dry run therefore over-reports what a real harvest would take.
  if [[ "$dry_run" == 1 ]]; then
    echo "$decision" >&2
    continue
  fi
```

**3d.** Add a line to the usage header, after the existing `Usage:` block:

```bash
# Every candidate's SOURCE repository is checked before its log is fetched: a run whose
# .head_repository.full_name is not --repo is skipped (skip=foreign_repo), and a run whose
# source cannot be read is skipped too (skip=provenance_unknown). There is no opt-out --
# an optional policy is not a policy. The --runs id,id path obeys the same check.
```

- [ ] **Step 4: Run the self-test to verify it passes**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! ./.github/scripts/harvest-gate-corpus.sh --self-test > /tmp/slice54-t7-green.txt 2>&1; then
  echo "STILL RED"; cat /tmp/slice54-t7-green.txt
else
  echo "self-test green"; cat /tmp/slice54-t7-green.txt
fi
if ! bash -n .github/scripts/harvest-gate-corpus.sh; then
  echo "SYNTAX ERROR in the network half (which --self-test never executes)"
else
  echo "syntax OK"
fi
if ! swift test --filter ScriptSelfTestTests > /tmp/slice54-t7-swift.txt 2>&1; then
  echo "SWIFT DRIVER RED"
else
  echo "swift driver green"
fi
```

Expected: `self_test=pass`, `syntax OK`, `swift driver green`. The `bash -n` check matters: `--self-test` exits before the network half, so nothing else parses those lines.

- [ ] **Step 5: Exercise the network half against a real run (one live call, no corpus write)**

```bash
cd /Users/aabanschikov/swift-text-engine
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
RECENT="$(gh run list -R maldrakar/swift-text-engine --workflow swift-ci.yml --limit 1 --json databaseId --jq '.[].databaseId')"
echo "probing run $RECENT"
gh api "repos/maldrakar/swift-text-engine/actions/runs/$RECENT" --jq '.head_repository.full_name'
./.github/scripts/harvest-gate-corpus.sh --runs "$RECENT" --corpus "$CORPUS" > /tmp/slice54-live-rows.txt 2>/tmp/slice54-live-stderr.txt
echo "--- stderr ---"; cat /tmp/slice54-live-stderr.txt
echo "--- rows (first 5) ---"; head -5 /tmp/slice54-live-rows.txt
COLS="$(head -1 /tmp/slice54-live-rows.txt | awk -F'\t' '{print NF}')"
echo "columns in the first emitted row: $COLS (expect 6, or no rows if the run was already harvested)"
if git diff --quiet -- "$CORPUS"; then echo "corpus untouched"; else echo "CORPUS MODIFIED — revert"; fi
```

Expected: the source prints `maldrakar/swift-text-engine`; either six-column rows on stdout, or `skip=already_harvested` on stderr if that run is already in the corpus (in which case re-run against a run id that is not, or accept the dedup path as the evidence). **The corpus must stay untouched** — this slice appends nothing.

- [ ] **Step 6: Drill 2 — remove the source clause and record the red**

```bash
cd /Users/aabanschikov/swift-text-engine
cp .github/scripts/harvest-gate-corpus.sh /tmp/slice54-drill2-backup.sh
sed -i '' 's|  elif \[\[ "$observed" != "$expected" \]\]; then|  elif false; then|' \
  .github/scripts/harvest-gate-corpus.sh
if ! rg -q 'elif false; then' .github/scripts/harvest-gate-corpus.sh; then
  echo "MUTATION DID NOT LAND — edit admissible_source by hand and re-run"
fi
if ! ./.github/scripts/harvest-gate-corpus.sh --self-test > /tmp/slice54-drill2-red.txt 2>&1; then
  echo "DRILL 2 RED as required"
else
  echo "DRILL 2 DID NOT FAIL — the provenance rule is unguarded; stop and fix it"
fi
cat /tmp/slice54-drill2-red.txt
cp /tmp/slice54-drill2-backup.sh .github/scripts/harvest-gate-corpus.sh
if ! ./.github/scripts/harvest-gate-corpus.sh --self-test > /tmp/slice54-drill2-restored.txt 2>&1; then
  echo "RESTORE FAILED"
else
  echo "restored green"
fi
```

Expected: `DRILL 2 RED as required`, with the `admissible_source rejects a fork's run` assertion showing `plan=harvest run=555` where `skip=foreign_repo …` was expected, then `restored green`.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add .github/scripts/harvest-gate-corpus.sh
git commit -m "feat: the harvester authenticates a run's source, failing closed

Run selection was `gh run list --json databaseId` -- the run id and nothing
else -- with no check that the code came from this repository rather than a
fork, and the --runs id,id path bypassed even the workflow filter. A fork
executes its own code and can print gate=pass beside any number it likes, so
this axis cannot be checked per row; it is checked per run.

admissible_source is pure and self-tested: same repo -> harvest, different repo
-> skip=foreign_repo, empty or `null` -> skip=provenance_unknown. Unknown means
REJECTED. There is no --allow-failed escape hatch: an optional policy is not a
policy.

One gh api call per candidate, placed after the dedup skip and before the log
fetch, so a run already in the corpus still costs zero API calls. Both entry
paths obey it, --runs included -- a deliberate behaviour change to a documented
flag. --dry-run stays network-free and says so.

`conclusion` is deliberately NOT a criterion: audited against this repository's
own history, it would have discarded 92 sound rows over a WASM SDK failure, one
of them inside the active N=20 window."
```

---

## Task 8: End-to-end drill, documentation, ledger, and the verification record

AC13 (no budget moves), AC15 (docs), AC16 (all seven drills recorded), plus drill 6 and the AC1 diff proof.

**Files:**
- Modify: `AGENTS.md` (three `## Gate budgets` edits, one `## Commands` note)
- Modify: `docs/superpowers/debt-ledger.md` (D-23, D-7)
- Create: `docs/superpowers/verification/2026-08-23-calibration-chain-hardening.md`

**Interfaces:**
- Consumes: everything from Tasks 1-7 and every `/tmp/slice54-*` artefact recorded along the way.
- Produces: no code.

- [ ] **Step 1: Drill 6 — prove a laundered regression cannot set a budget**

The control and the treatment differ **only** in the verdict, so the window shift the new run id causes is identical on both sides and cannot be mistaken for the effect.

```bash
cd /Users/aabanschikov/swift-text-engine
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
cp "$CORPUS" /tmp/slice54-drill6-control.tsv
cp "$CORPUS" /tmp/slice54-drill6-treatment.tsv
# Same synthetic run id, same absurd latency, same scenario. Only the verdict differs.
printf '99999999999\tline_query\tuniform_1k\t999999\t999999\tpass\n'            >> /tmp/slice54-drill6-control.tsv
printf '99999999999\tline_query\tuniform_1k\t999999\t999999\tbudget_exceeded\n' >> /tmp/slice54-drill6-treatment.tsv

./.github/scripts/derive-gate-budgets.sh /tmp/slice54-drill6-control.tsv line-query \
  > /tmp/slice54-drill6-control.txt 2>/tmp/slice54-drill6-control.err
./.github/scripts/derive-gate-budgets.sh /tmp/slice54-drill6-treatment.tsv line-query \
  > /tmp/slice54-drill6-treatment.txt 2>/tmp/slice54-drill6-treatment.err
./.github/scripts/derive-gate-budgets.sh "$CORPUS" line-query \
  > /tmp/slice54-drill6-clean.txt 2>/dev/null

echo "--- control (verdict=pass: the laundered row IS counted) ---"
cat /tmp/slice54-drill6-control.txt
echo "--- treatment (verdict=budget_exceeded: rejected) ---"
cat /tmp/slice54-drill6-treatment.txt
echo "--- treatment stderr ---"
cat /tmp/slice54-drill6-treatment.err

if diff -q /tmp/slice54-drill6-control.txt /tmp/slice54-drill6-treatment.txt > /dev/null 2>&1; then
  echo "DRILL 6 FAILED: the verdict changed nothing — the filter is inert"
else
  echo "DRILL 6: control and treatment differ, as required"
fi
if diff -q /tmp/slice54-drill6-treatment.txt /tmp/slice54-drill6-clean.txt > /dev/null 2>&1; then
  echo "DRILL 6 PASS: rejecting the row reproduces the clean-corpus budget exactly"
else
  echo "DRILL 6 PARTIAL — treatment differs from clean; read the diff (the new run id also"
  echo "shifts the N=20 window, which is expected and is NOT the laundering effect):"
  diff -u /tmp/slice54-drill6-clean.txt /tmp/slice54-drill6-treatment.txt
fi
if git diff --quiet -- "$CORPUS"; then echo "committed corpus untouched"; else echo "CORPUS MODIFIED — revert"; fi
rm -f /tmp/slice54-drill6-control.tsv /tmp/slice54-drill6-treatment.tsv
```

Expected: the control shows a hugely inflated `budget_p95`/`budget_p99` for `line_query|uniform_1k`; the treatment does not, and reports `dropped=budget_exceeded rows=1` on stderr; the committed corpus is untouched. A `DRILL 6 PARTIAL` result is acceptable **only** if the diff is explained entirely by the window shift (the oldest run aging out), which affects both sides equally — record the diff either way.

- [ ] **Step 2: Prove the twelve gated modes' measurement loops are unchanged (AC1)**

```bash
cd /Users/aabanschikov/swift-text-engine
BASE="$(git merge-base HEAD main)"
CHANGED="$(git diff --name-only "$BASE"...HEAD -- Sources/ViewportBenchmarks)"
echo "benchmark files changed on this branch:"; echo "$CHANGED"
GATED="$(git diff --name-only "$BASE"...HEAD -- \
  Sources/ViewportBenchmarks/LineQueryBenchmark.swift \
  Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift \
  Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift \
  Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift \
  Sources/ViewportBenchmarks/PointQueryBenchmark.swift \
  Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift \
  Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift \
  Sources/ViewportBenchmarks/SyntheticBenchmarks.swift \
  Sources/ViewportBenchmarks/VariableHeightBenchmark.swift \
  Sources/ViewportBenchmarks/VariableHeightMutationBenchmark.swift \
  Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift \
  Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift \
  Sources/ViewportBenchmarks/BenchmarkModels.swift)"
if [ -z "$GATED" ]; then
  echo "AC1 PASS: no gated benchmark file and no BenchmarkModels.swift touched"
else
  echo "AC1 FAIL — these must not change:"; echo "$GATED"
fi
FORMAT="$(git diff "$BASE"...HEAD -- Sources/ViewportBenchmarks/BenchmarkSupport.swift | rg '^-' | rg -v '^---' || true)"
if [ -z "$FORMAT" ]; then
  echo "AC1 PASS: BenchmarkSupport.swift is purely additive (no deleted lines)"
else
  echo "AC1 FAIL — BenchmarkSupport.swift lost lines:"; echo "$FORMAT"
fi
```

Expected: both `AC1 PASS` lines, and `changed` listing only `BenchmarkSupport.swift`, `WrapRowQueryBenchmark.swift`, `WrapComputeBenchmark.swift`.

- [ ] **Step 3: Edit `AGENTS.md` — the harvest-admissibility rule**

In `## Gate budgets`, change the sentence at line 560 from

```
harvester reads every `p95_ns=` line in a run's log, so a second printing step
```

to

```
harvester reads every **admissible** `p95_ns=` line in a run's log (see **What the
harvester admits** below), so a second printing step
```

Then, immediately after that paragraph (before the "The one time to harvest **without** `--corpus`" paragraph), insert:

```markdown
**What the harvester admits.** Two orthogonal axes, checked at two different levels.
`conclusion` is deliberately **not** one of them.

- **Source, per run.** `harvest-gate-corpus.sh` reads `.head_repository.full_name`
  from `gh api repos/{owner}/{repo}/actions/runs/{id}` and admits a run only if it
  equals the harvested repository. A run whose source cannot be read is **rejected**
  (`skip=provenance_unknown`), not admitted: a fork executes its own code and can
  print `gate=pass` beside any number it likes, so this axis fails closed. There is
  no opt-out, and the `--runs id,id` path obeys the same check. The probe sits
  between the dedup skip and the log fetch, so a run already in the corpus still
  costs zero API calls.
- **Verdict, per row.** Every summary line carries its own `gate=`/`reason=`, and
  the harvester records it as the corpus's **sixth column**. Both consumers reject a
  row at read time when that column is one of
  `{budget_exceeded, budget_absolute_exceeded, operation_failures}` — the
  measurement was slow or degenerate — and admit everything else. Row-level, not
  run-level: one failing mode drops its own scenario and keeps its forty-five
  siblings.
- **`budget_stale` is admitted.** It means the measurement was *fast* enough that
  headroom breached its ceiling, and the prescribed response is to re-derive from
  fresh evidence — which requires harvesting exactly those samples. A filter that
  dropped them would instruct the operator to re-derive and simultaneously refuse to
  collect the evidence.
- **Degeneracy is read from `failures=`, not from the verdict.** `formatSummary`
  prints `failures=N` unconditionally, **outside** the `--gate` branch, so a row
  whose `failures=` is non-zero is recorded as `operation_failures` whatever the
  verdict says — including on a line with no `gate=` at all. That is strictly
  stronger than reading the verdict: `gateFailureReason` returns `missing_budget`
  **before** it tests `failureCount`, and `missing_budget` is admitted.
- **A verdict-less line is admitted** (`none`), and so is a legacy five-column row.
  A new mode's **first** hosted evidence necessarily comes from a step without
  `--gate`, because its budget does not exist yet; rejecting those would make a new
  gate unbootstrappable. The committed corpus is entirely five-column and is never
  rewritten — the corpus is append-only.
- **Why not `conclusion`.** A run-level filter discards both directions of a red
  gate, and one failing mode out of twelve would discard the other forty-five
  scenarios' sound rows. Audited against this repository's own history: it would
  have dropped 92 sound rows over a WASM SDK failure, one of them inside the active
  N=20 window.

The reject set lives in two languages — `.github/scripts/derive-gate-budgets.sh`
(`REJECTED_VERDICTS`) and `GateFloorTests.swift` (`rejectedVerdicts`) — pinned
against each other by `testAdmissibleRowsMatchDeriveScript` over the
`--admissible-rows` seam. That is the **third** cross-language pin, beside the two
window pins, and like them it covers agreement, not correctness. The verdict filter
applies **after** windowing, so neither window pin is touched; a run whose rows are
all rejected still consumes a window slot. Rejections are loud: skipped runs print
`skip=` and dropped rows print `dropped=<reason> rows=N`, both on stderr.
```

- [ ] **Step 4: Edit `AGENTS.md` — the `budget_stale` instruction**

Replace the second bullet of the "A harvest re-derives every mode" list (lines 547-551) with:

```markdown
- A post-harvest **`GateFloorTests` failure is `budget_stale`, not an engine
  regression**: the new samples raised a floor under an unchanged budget. Re-derive
  that scenario; do not go hunting for a slowdown in the core. (Budgets sitting
  within a few percent of their floor are normal — whenever the `3 x max` term
  governs, `round_up_2sf` lands just above it *by construction*.) **This holds
  because a slow sample can no longer enter the corpus**: a row whose own hosted line
  reported `budget_exceeded`, `budget_absolute_exceeded` or `operation_failures` is
  rejected at read time (see **What the harvester admits**). Before Slice 54 nothing
  downstream read the verdict, and this instruction was indistinguishable from one to
  launder a regression into a looser budget — the summary line is printed *before* the
  gate verdict is checked, so a slow sample genuinely reaches the log, and the
  `3 x max` term lets a single row set a budget by itself.
```

- [ ] **Step 5: Edit `AGENTS.md` — the `## Commands` wrap entries**

Replace lines 263-264:

```
swift run -c release ViewportBenchmarks -- --wrap-compute   # observational wrap compute width-change demo (amortised; not gateable)
swift run -c release ViewportBenchmarks -- --wrap-row-query   # observational wrap y->row query benchmark (amortised; not gateable)
```

And after the `--gate` rejection enumeration (the paragraph ending `--wrap-compute`, `--wrap-row-query`. at line ~292), insert:

```markdown
Both wrap modes measure on the same **amortised** shape as the gated modes —
`operationsPerSample` operations under one clock read, divided by `amortise`
(`BenchmarkSupport.swift`) — so their numbers resolve the operation rather than the
host clock tick. Every measurement prints its own `*_operations_per_sample=` token.
The one exemption is `--wrap-compute`'s `reindex_ns`, a one-shot O(N) setup whose
meaning averaging would destroy; it prints `reindex_operations_per_sample=1` so the
exemption reads as a decision rather than an oversight.
```

- [ ] **Step 6: Verify the AGENTS.md edits landed and contradict nothing**

```bash
cd /Users/aabanschikov/swift-text-engine
for token in "What the harvester admits" "admissible\` \`p95_ns=" "REJECTED_VERDICTS" "reindex_operations_per_sample=1"; do
  if rg -q -- "$token" AGENTS.md; then echo "present: $token"; else echo "MISSING: $token"; fi
done
STALE="$(rg -n 'harvester reads every `p95_ns=` line' AGENTS.md || true)"
if [ -z "$STALE" ]; then
  echo "PASS: the un-qualified sentence is gone"
else
  echo "FAIL — still present:"; echo "$STALE"
fi
```

Expected: four `present:` lines (adjust the second token if the exact wording differs — the check is that the qualifier landed) and `PASS`.

- [ ] **Step 7: Update the debt ledger**

In `docs/superpowers/debt-ledger.md`, flip the status cell of **D-23** from `scheduled(slice-54) — …` to:

```
discharged([slice 54](verification/2026-08-23-calibration-chain-hardening.md)) — both wrap modes now measure through `amortisedSamples` (one clock read per `operationsPerSample` operations, divided by the separately-pinned `amortise`), so their numbers resolve the operation rather than the host tick. `--wrap-compute`'s `reindex_ns` stays a single unamortised measurement by decision, printed as `reindex_operations_per_sample=1`; its construction is now bound and reused, removing a second O(N) pass and making the timed work observably live. Repaired **before** node 6's first harvest, as the deadline required
```

And **D-7** from `scheduled(slice-54) — …` to:

```
discharged([slice 54](verification/2026-08-23-calibration-chain-hardening.md)) — `harvest-gate-corpus.sh` now checks each candidate run's `.head_repository.full_name` and fails closed when it cannot be read, on both entry paths (`--runs` included), with no opt-out. A second hole found while reading for it is closed in the same slice: the corpus gained a sixth **verdict** column, and both consumers reject `{budget_exceeded, budget_absolute_exceeded, operation_failures}` at read time, pinned across languages by `testAdmissibleRowsMatchDeriveScript`. Both guards are preventive and their only evidence is the recorded drills — no fork has ever run CI, and no contaminated row exists
```

Then append a new row for the residual the spec names in Risks (the ledger is append-only; new debt gets a new id — use the next unused one, which as of this slice is **D-26**; confirm with `rg -n '^\| D-' docs/superpowers/debt-ledger.md | tail -3`):

```
| D-26 | [slice 54](verification/2026-08-23-calibration-chain-hardening.md) | P3 | The reject set now lives in two languages, and `testAdmissibleRowsMatchDeriveScript` covers **agreement, not correctness**: if both sides gain the same wrong entry, nothing notices. Same residual the two window pins carry, accepted on the same terms. Related: `operation_failures` is rejected on reasoning rather than measurement — no such row exists to inspect — and a scenario whose every windowed row was rejected would fail `GateFloorTests` with "no hosted evidence", a message pointing at the corpus rather than at the rejections that emptied it (the derivation's per-reason `dropped=` counts are what would explain it) | accepted-risk |
```

- [ ] **Step 8: Full verification sweep**

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test > /tmp/slice54-final-test.txt 2>&1; then echo "SUITE RED"; else echo "suite green"; fi
rg -n "Executed [0-9]+ tests" /tmp/slice54-final-test.txt | tail -2
if ! swift build -c release > /tmp/slice54-final-build.txt 2>&1; then echo "RELEASE BUILD RED"; else echo "release build green"; fi
FOUNDATION_CORE="$(rg -n 'Foundation' Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION_CORE" ]; then echo "PASS: TextEngineCore Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION_CORE"; fi
# Convention-only, but this slice adds code there, so the new helper must not become the
# first exception (spec Verification).
FOUNDATION_BENCH="$(rg -n 'Foundation' Sources/ViewportBenchmarks || true)"
if [ -z "$FOUNDATION_BENCH" ]; then echo "PASS: ViewportBenchmarks Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION_BENCH"; fi
for s in cross-target-compile.sh derive-gate-budgets.sh harvest-gate-corpus.sh detect-docs-only-pr.sh; do
  if ! "./.github/scripts/$s" --self-test > "/tmp/slice54-selftest-$s.txt" 2>&1; then
    echo "SELF-TEST RED: $s"; cat "/tmp/slice54-selftest-$s.txt"
  else
    echo "self_test=pass: $s"
  fi
done
```

Expected: `suite green`, `release build green`, both Foundation scans `PASS`, four `self_test=pass` lines.

- [ ] **Step 9: The twelve gates and the memory-shape invariant**

```bash
cd /Users/aabanschikov/swift-text-engine
for flag in "" "--realistic-provider" "--variable-height" "--variable-height-mutation" \
            "--structural-mutation" "--bulk-structural-mutation" "--line-query" \
            "--line-geometry-query" "--column-query" "--column-geometry-query" \
            "--point-query" "--point-geometry-query"; do
  out="/tmp/slice54-gate$(echo "$flag" | tr -d ' -').txt"
  if ! swift run -c release ViewportBenchmarks -- $flag --gate > "$out" 2>&1; then
    echo "GATE RED: ${flag:-default}"; tail -5 "$out"
  else
    echo "gate=pass: ${flag:-default}"
  fi
done
PASSES="$(cat /tmp/slice54-gate*.txt | rg -c 'gate=pass' || true)"
echo "total gate=pass lines across the twelve modes: $PASSES (expect 46)"
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected: twelve `gate=pass:` lines, **46** `gate=pass` scenario lines in total, and `invariant=pass`.

- [ ] **Step 10: Final AC13 re-check against the committed corpus**

```bash
cd /Users/aabanschikov/swift-text-engine
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
BASE="$(git merge-base HEAD main)"
git show "$BASE:.github/scripts/derive-gate-budgets.sh" > /tmp/slice54-derive-base.sh
bash /tmp/slice54-derive-base.sh "$CORPUS" > /tmp/slice54-final-derive-base.txt 2>/dev/null
bash ./.github/scripts/derive-gate-budgets.sh "$CORPUS" > /tmp/slice54-final-derive-head.txt 2>/tmp/slice54-final-derive-head.err
if diff -u /tmp/slice54-final-derive-base.txt /tmp/slice54-final-derive-head.txt > /tmp/slice54-final-derive.diff 2>&1; then
  echo "AC13 PASS: derivation output byte-identical to the branch point"
else
  echo "AC13 FAIL:"; cat /tmp/slice54-final-derive.diff
fi
echo "stderr from the head derivation (expect empty): [$(cat /tmp/slice54-final-derive-head.err)]"
if git diff --quiet "$BASE"...HEAD -- "$CORPUS"; then echo "AC13 PASS: corpus file untouched"; else echo "AC13 FAIL: corpus modified"; fi
if git diff --quiet "$BASE"...HEAD -- .github/workflows/swift-ci.yml; then echo "AC14 PASS: swift-ci.yml untouched"; else echo "AC14 FAIL"; fi
GATEABLE="$(rg -n 'wrapCompute|wrapRowQuery' Sources/ViewportBenchmarks/BenchmarkOptions.swift | rg 'isGateable|true' || true)"
echo "wrap modes in isGateable context (read this by eye, expect the false arm): $GATEABLE"
```

Expected: both `AC13 PASS` lines, empty stderr, `AC14 PASS`.

- [ ] **Step 11: Write the verification record**

Create `docs/superpowers/verification/2026-08-23-calibration-chain-hardening.md` with these sections, each carrying **actual pasted output**, not a summary:

1. **Scope and acceptance criteria** — the seventeen ACs from the spec, each with a one-line disposition and a pointer to the section below that proves it.
2. **Baseline** — `swift test` count before the slice.
3. **D-23 before/after** — the full `--wrap-row-query` and `--wrap-compute` output on both sides, plus both tick-multiple checks (`/tmp/slice54-before-ticks.txt`, `/tmp/slice54-after-ticks.txt`) with their **derived denominators** (20 before, 23 after) and the ratio on each side. State explicitly that `reindex_ns` remaining a tick multiple is expected, not residual defect. If the host is not 24 MHz, record the observed granularity instead and say so.
4. **Decision 4 evidence** — the `drain_p95_ns` values before and after, and the diff read confirming the drain body performs no `compute` (AC5 is a diff read, not a test — say so).
5. **AC1 diff proof** — the Step 2 output showing no gated benchmark file changed.
6. **The seven drills**, each with the mutation applied, the observed red (pasted), and the restored green. Drill 1 must carry the note that its mutation targets `amortise`'s body, and that the call-site residual is covered by the recorded before/after evidence rather than by a unit test.
7. **Drill 6 end-to-end** — control vs. treatment vs. clean, and the `dropped=budget_exceeded rows=1` stderr line.
8. **Live network exercise** — the `gh api` source lookup and the six-column rows (or the dedup skip), with the corpus confirmed untouched.
9. **Full sweep** — `swift test`, release build, both Foundation scans, four `--self-test` runs, twelve gates with the 46-count, `--memory-shape`.
10. **AC13** — the byte-identical derivation diff (empty) and the untouched corpus.
11. **Hosted proof** — left open, discharged in Step 13.

- [ ] **Step 12: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add AGENTS.md docs/superpowers/debt-ledger.md \
        docs/superpowers/verification/2026-08-23-calibration-chain-hardening.md
git commit -m "docs: AGENTS.md harvest admissibility, ledger D-23/D-7, slice 54 verification

AGENTS.md gains 'What the harvester admits' -- the two orthogonal axes (source
per run, verdict per row), the reject set, the failures= rule, why a
verdict-less line is admitted, and why conclusion is NOT a criterion, with the
audited cost of the rejected alternative (92 sound rows over a WASM SDK
failure).

The budget_stale instruction gains the qualification this slice earns: 'do not
go hunting for a slowdown in the core' holds BECAUSE a slow sample can no longer
enter the corpus. Until now it was indistinguishable from an instruction to
launder a regression.

Ledger: D-23 and D-7 discharged; D-26 records the accepted residual -- the
cross-language pin covers agreement, not correctness.

Verification records both before/after wrap sweeps with denominators derived
from the output shape on each side, all seven drills with their observed reds,
the end-to-end laundering drill, the twelve gates at 46 gate=pass, and the
byte-identical derivation."
```

- [ ] **Step 13: Open the PR and discharge the hosted proof (AC17)**

```bash
cd /Users/aabanschikov/swift-text-engine
git push -u origin slice-54-calibration-chain-hardening
gh pr create --title "Slice 54: calibration-chain hardening (D-23 + D-7)" --body "$(cat <<'EOF'
Repairs the two unsound links in the calibration chain before map node 6 harvests through them.

**D-23 — the wrap benchmarks measured the clock, not the operation.** Both wrap modes now run on a shared `amortisedSamples` helper (one clock read per `operationsPerSample` operations, divided by a separately-pinned `amortise`), the shape every gated mode already uses. `--wrap-compute`'s `reindex_ns` stays a single unamortised measurement by decision — a one-shot O(N) setup, printed as `reindex_operations_per_sample=1` so the exemption reads as a decision — and its construction is now bound and reused, removing a second O(N) pass and making the timed work observably live. Drain ranges are pre-built outside the clock, so `drain_p95_ns` measures drain and not compute+drain.

**D-7 — the harvester authenticated nothing.** Every candidate run's `.head_repository.full_name` is now checked, failing closed when it cannot be read, on both entry paths with no opt-out. A second hole found while reading for it is closed in the same slice: the corpus gained a sixth **verdict** column, and both consumers reject `{budget_exceeded, budget_absolute_exceeded, operation_failures}` at read time — degeneracy read from `failures=`, which is printed even on ungated lines, because node 6's own bootstrap harvest is exactly that shape.

No budget moves; the committed corpus is untouched; the twelve gated modes' measurement loops are unchanged; neither wrap mode becomes gateable. Both guards are preventive — no fork has ever run CI and no contaminated row exists — so the seven falsifiability drills, each with its observed red, are the whole proof. See `docs/superpowers/verification/2026-08-23-calibration-chain-hardening.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Then wait for the PR-head run, read it at **step level** (a green job can hide a dead `continue-on-error` step), record the run id and the three job conclusions plus the twelve gate steps and their 46 `gate=pass`, and after merge do the same for the post-merge push run. Append both to the verification record's **Hosted proof** section and commit that as a docs-only follow-up PR.

```bash
cd /Users/aabanschikov/swift-text-engine
RUN="$(gh run list -R maldrakar/swift-text-engine --workflow swift-ci.yml --limit 1 --json databaseId --jq '.[].databaseId')"
gh run view "$RUN" -R maldrakar/swift-text-engine --json jobs \
  --jq '.jobs[] | "\(.name): \(.conclusion)"'
gh run view "$RUN" -R maldrakar/swift-text-engine --log > /tmp/slice54-hosted.log 2>&1
echo "gate=pass lines in the hosted log: $(rg -c 'gate=pass' /tmp/slice54-hosted.log || echo 0) (expect 46)"
echo "gate=fail lines: $(rg -c 'gate=fail' /tmp/slice54-hosted.log || echo 0) (expect 0)"
```

---

## Plan Self-Review

**1. Spec coverage.** Every spec section maps to a task:

| Spec | Task |
|---|---|
| Decision 1 (shared helper, not `formatSummary`) | 1 |
| Decision 2 (division extracted, pinned by equality) | 1 (+ drill 1) |
| Decision 3 (`reindex_ns` exempt; bind-and-reuse repair) | 3 |
| Decision 4 (drain ranges built outside the clock) | 3 (+ AC5 diff read) |
| Decision 5 (two axes; `conclusion` rejected) | 7 (source axis), 5+6 (verdict axis), 8 (documented) |
| Decision 6 (record at harvest, filter at derivation; Swift reader first) | 4 → 5 → 6, in that order |
| Decision 7 (reject set of three; `failures=` rule) | 4 (Swift), 5 (shell), 6 (harvest side) |
| Decision 8 (window stays verdict-blind) | 4 (run id recorded before the filter), 5 (filter after `KEEP`) |
| Decision 9 (`extract_rows()` extracted so the rule can fail) | 6 |
| Decision 10 (one `gh api` per candidate) | 7 |
| Decision 11 (`--runs` obeys the policy) | 7 (the check is inside the shared loop) |
| Decision 12 (rejections are loud) | 5 (`dropped=`), 7 (`skip=`) |
| Component Design — `BenchmarkSupport.swift` | 1 |
| Component Design — `WrapRowQueryBenchmark.swift` | 2 |
| Component Design — `WrapComputeBenchmark.swift` | 3 |
| Component Design — `harvest-gate-corpus.sh` | 6, 7 |
| Component Design — `derive-gate-budgets.sh` | 5 |
| Component Design — `GateFloorTests.swift` | 4, 5 |
| Testing Strategy — timing helper | 1 |
| Testing Strategy — harvester self-test truth tables | 6, 7 |
| Testing Strategy — cross-language pin | 5 |
| Testing Strategy — drills 1-7 | 1 (d1), 7 (d2), 5 (d3, d4), 4 (d5), 8 (d6), 6 (d7) |
| Testing Strategy — before/after evidence | 1 step 2 (before), 2 step 5 + 3 steps 5-6 (after) |
| Benchmark Mode / CI (nothing added) | 8 step 10 |
| Documentation Updates | 8 steps 3-6 |
| Verification | 8 steps 8-11 |
| AC1-AC17 | 1-8; see the drill map above |

**2. Placeholder scan.** No "TBD"/"TODO"/"similar to Task N". Every code step carries complete code; every assertion carries its expected output and an explicit `if`/`else` that prints both branches. No `${PIPESTATUS[0]}` anywhere. Every command block assigns the variables it uses (`CORPUS`, `BASE`, `RUN`, `RECENT` are all assigned in the block that reads them). The plan asserts no HEAD commit of its own.

**3. Type consistency.** `amortise(elapsedNanoseconds:operationsPerSample:)` and `amortisedSamples(iterations:operationsPerSample:body:) -> (samples: [Int64], checksum: Int)` are declared in Task 1 and used with those exact labels in Tasks 2 and 3. `formatWrapRowQueryLine(scenarioName:totalRows:operationsPerSample:p95Nanoseconds:p99Nanoseconds:checksum:)` is asserted in Task 2's test and defined in Task 2's source with the same labels; `formatWrapComputeLine(widthLabel:totalRows:computeOperationsPerSample:computeP95Nanoseconds:computeP99Nanoseconds:drainOperationsPerSample:drainP95Nanoseconds:drainP99Nanoseconds:reindexNanoseconds:)` likewise across Tasks 2 (test) and 3 (source). `rejectedVerdicts` / `isAdmissibleVerdict(_:)` / `admissibleCorpusRows(from:)` are defined in Task 4 and consumed in Task 5. `REJECTED_VERDICTS` / `admissible_rows` / `--admissible-rows` are one triple in Task 5. `extract_rows <id>` (Task 6) and `admissible_source <id> <observed> <expected>` (Task 7) are called with those arities in their own self-tests and at the network call site. `BenchmarkWrapLayout(lineCount:cells:advance:rowHeight:wrapWidth:)` matches the existing declaration.

**Four risks flagged for the implementer:**

1. **Drill 1's target is `amortise`'s body, not its call site.** The spec words it as "remove the division from `amortisedSamples`"; deleting the *call* would not redden the equality test, because that test calls `amortise` directly. Task 1 Step 7 performs the mutation the pin actually catches and records the residual honestly. Do not claim a pin the suite does not have.
2. **AC5 has no test and cannot get one.** `amortisedSamples`' structural test pins the body's call count, and a body that computed a range inside itself would satisfy it. The guards are the diff read in Task 3 Step 4 and the recorded before/after `drain_p95_ns`. The spec names this in Risks; the verification record must repeat it rather than implying a green test covers it.
3. **The task order 4 → 5 → 6 is load-bearing.** The Swift reader must accept six columns before the harvester writes them (spec Decision 6), and the cross-language pin in Task 5 consumes `admissibleCorpusRows` from Task 4. Reordering produces a red `swift test` for the wrong reason and a pin that cannot compile.
4. **Task 6's fixture line 11 (`gate=fail` with no `reason=`) is beyond the spec's truth table.** It pins the fail-closed fallback for a shape `formatSummary` cannot currently produce. Keep it — but if a reviewer objects that it invents vocabulary, the answer is that it invents none: it maps to `budget_exceeded`, an existing reject-set member, and rejects rather than admits.
