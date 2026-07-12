# Gate Budget Recalibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ten latency gates able to fail — recalibrate 27 inflated scenarios against hosted-Linux evidence, teach the gate to reject its own stale budgets, and promote `--point-query` to the tenth blocking gate with an honest budget.

**Architecture:** Budgets are re-derived from a committed corpus of real hosted-CI samples by a committed script, so the derivation is reproducible rather than transcribed. `BenchmarkSummary` gains a `headroomP95` and a typed gate-failure reason; `--gate` fails when headroom exceeds 50×, which makes an inflated budget a build error instead of a silent no-op. `--point-query` first *observes* on hosted CI (non-gate step, cannot fail), and only once it has real hosted samples does it become a blocking gate.

**Tech Stack:** Swift 6 (swift-tools 6.0), SwiftPM, XCTest, GitHub Actions, `gh` CLI, awk.

## Global Constraints

Copied verbatim from `AGENTS.md` and the spec. Every task's requirements implicitly include this section.

- **Zero changes to `Sources/TextEngineCore`.** `git diff --name-only main` must show no path under it, in every commit. This slice changes no engine behavior.
- **No Foundation in `Sources/TextEngineCore`** (`rg -n "Foundation" Sources/TextEngineCore` → empty, exit 1).
- **`Sources/ViewportBenchmarks` today imports no Foundation, and must not start.** Verified: `rg -l "import Foundation" Sources/ViewportBenchmarks` → no matches. This rules out `String(format:)` for the new `headroom_p95` field; format it with integer arithmetic (Task 3).
- **Zero third-party dependencies.**
- **Every gate checksum must stay byte-identical** to the Slice 37 baseline. Recalibration changes budgets, never measured paths — byte-identity is the proof.
- **Existing test count is 232.** It must not drop. New tests only add.
- **One logical step per commit**, conventional-commit prefixes (`feat:`, `test:`, `refactor:`, `docs:`, `ci:`).
- Benchmarks/gates live in `Sources/ViewportBenchmarks`, never in the core.
- The gate output contract is **key=value, space-separated**. `.github/scripts/realistic-relative-observation.sh` parses it by key (`tr ' ' '\n' | awk -F=`), so adding fields is safe; reordering or renaming existing keys is not.

## Baseline (measured 2026-07-12, macOS arm64, before any change)

Record these; several steps compare against them.

| Gate | Local p95 range | Current budget headroom (hosted) |
| --- | --- | --- |
| 5 query gates (20 scenarios) | 12 – 184 ns | **815× – 3,000×** |
| `--variable-height` (3) | 204 – 2,019 ns | **45× – 98×** |
| Other 5 gates (15) | — | 3× – 10× (correct, untouched) |

`swift test` → 232 tests, 0 failures. All ten gates → `gate=pass`.

---

## Task 1: Commit the hosted corpus and the derivation script

The budgets must be *derived*, not typed in. This task builds the evidence and the tool; Task 2 applies the result. This is the task that makes the fix auditable — and re-runnable by the next gate author, which is the whole anti-rot point.

**Files:**
- Create: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
- Create: `.github/scripts/derive-gate-budgets.sh`

**Interfaces:**
- Produces: `derive-gate-budgets.sh <corpus.tsv>` prints one line per scenario:
  `mode scenario n p95_med p95_max p99_med p99_max budget_p95 budget_p99 margin_p95 margin_p99`.
  Task 2 and Task 5 consume this output.

- [ ] **Step 1: Harvest every hosted run that carries gate lines**

The corpus must come from **every** available run, not a convenient subset — the spec's Risks section records that the extra runs carried the worst tails (`line_query|uniform_1m` worst p95: 61 → 109 ns), and the worst tail is exactly what the 3× floor rests on.

Run:

```bash
{
  printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n'
  gh run list -R maldrakar/swift-text-engine --workflow swift-ci.yml --limit 40 \
    --json databaseId --jq '.[].databaseId' \
  | while read -r id; do
      gh run view "$id" -R maldrakar/swift-text-engine --log < /dev/null 2>/dev/null \
      | grep -oE 'mode=[a-z_]+ .*p95_ns=[0-9]+ p99_ns=[0-9]+.*' \
      | awk -v id="$id" '{
          delete v
          for (i = 1; i <= NF; i++) { split($i, p, "="); v[p[1]] = p[2] }
          if (v["scenario"] != "" && v["p95_ns"] != "")
            printf "%s\t%s\t%s\t%s\t%s\n", id, v["mode"], v["scenario"], v["p95_ns"], v["p99_ns"]
        }'
    done
} > docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv

wc -l < docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
cut -f1 docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | tail -n +2 | sort -u | wc -l
```

Expected: ~540–580 sample rows, ~19–20 distinct runs. The exact count depends on how many runs are still within GitHub's log-retention window — record whatever you actually get, and record it per scenario (the `n` column of Step 3). Do **not** proceed if a scenario has fewer than 5 runs, except `point_query`, which has zero by construction and is handled in Task 5.

- [ ] **Step 2: Write the derivation script**

Create `.github/scripts/derive-gate-budgets.sh`:

```bash
#!/usr/bin/env bash
# Derive gate budgets from a corpus of observed hosted-CI samples.
#
# Recipe (Slice 38 design, Decision 2) — the 3x floor is inside the formula, not
# a check applied afterwards, and it covers BOTH statistics because the gate can
# fail on either:
#
#   budget_p95 = round_up_2sf(max(8 * median(p95), 3 * max(p95)))
#   budget_p99 = round_up_2sf(max(2 * budget_p95, 8 * median(p99), 3 * max(p99)))
#
# Usage: ./.github/scripts/derive-gate-budgets.sh <corpus.tsv> [mode ...]
set -euo pipefail

corpus="${1:?usage: derive-gate-budgets.sh <corpus.tsv> [mode ...]}"
shift || true

awk -F'\t' -v modes="$*" '
function ru2(x,   e, n) {          # round up to 2 significant figures
  if (x <= 0) return 0
  e = 1
  while (x / e >= 100) e *= 10
  n = x / e
  if (n == int(n)) return int(n) * e
  return (int(n) + 1) * e
}
function med(arr, n,   i, j, t) {  # lower median of a 1..n array, sorts in place
  for (i = 1; i < n; i++)
    for (j = i + 1; j <= n; j++)
      if (arr[i] + 0 > arr[j] + 0) { t = arr[i]; arr[i] = arr[j]; arr[j] = t }
  return arr[int((n + 1) / 2)] + 0
}
NR == 1 { next }                   # header
{
  if (modes != "" && index(" " modes " ", " " $2 " ") == 0) next
  k = $2 "|" $3
  n[k]++
  p95[k, n[k]] = $4
  p99[k, n[k]] = $5
}
END {
  for (k in n) {
    cnt = n[k]
    for (i = 1; i <= cnt; i++) { a[i] = p95[k, i]; b[i] = p99[k, i] }
    m95 = med(a, cnt); x95 = a[cnt] + 0     # med() leaves the array sorted
    m99 = med(b, cnt); x99 = b[cnt] + 0

    b95 = ru2(8 * m95 > 3 * x95 ? 8 * m95 : 3 * x95)
    lo99 = 2 * b95
    if (8 * m99 > lo99) lo99 = 8 * m99
    if (3 * x99 > lo99) lo99 = 3 * x99
    b99 = ru2(lo99)

    printf "%-46s n=%-3d p95[med=%-6d max=%-6d] p99[med=%-6d max=%-6d] budget_p95=%-7d budget_p99=%-7d margin_p95=%.1fx margin_p99=%.1fx\n", \
           k, cnt, m95, x95, m99, x99, b95, b99, b95 / x95, b99 / x99
  }
}
' "$corpus" | sort
```

Make it executable: `chmod +x .github/scripts/derive-gate-budgets.sh`

- [ ] **Step 3: Run the derivation and check the floors**

Run:

```bash
./.github/scripts/derive-gate-budgets.sh \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
  line_query line_geometry_query column_query column_geometry_query variable_height
```

Expected: 23 lines. **Every `margin_p95` ≥ 3.0× and every `margin_p99` ≥ 3.0×** — that is the floor, and it is guaranteed by the formula, so a value below 3.0 means the script is wrong, not the data.

Expected budgets (from the spec's corpus; yours may differ by one rounding step if the retention window shifted — **the script's output wins, not this table**):

| mode \| scenario | budget_p95 | budget_p99 |
| --- | --- | --- |
| `line_query\|uniform_1k` | 200 | 440 |
| `line_query\|uniform_100k` | 280 | 560 |
| `line_query\|uniform_1m` | 330 | 660 |
| `line_query\|balanced_tree_100k` | 1700 | 3400 |
| `line_query\|balanced_tree_1m` | 2100 | 4200 |
| `line_geometry_query\|uniform_1k` | 270 | 540 |
| `line_geometry_query\|uniform_100k` | 360 | 720 |
| `line_geometry_query\|uniform_1m` | 380 | 760 |
| `line_geometry_query\|balanced_tree_100k` | 3000 | 6000 |
| `line_geometry_query\|balanced_tree_1m` | 3400 | 6800 |
| `column_query\|uniform_1k` | 200 | 400 |
| `column_query\|uniform_100k` | 300 | 600 |
| `column_query\|uniform_1m` | 320 | 640 |
| `column_query\|prefixsum_100k` | 460 | 920 |
| `column_query\|prefixsum_1m` | 570 | 1200 |
| `column_geometry_query\|uniform_1k` | 260 | 520 |
| `column_geometry_query\|uniform_100k` | 350 | 700 |
| `column_geometry_query\|uniform_1m` | 390 | 780 |
| `column_geometry_query\|prefixsum_100k` | 840 | 1700 |
| `column_geometry_query\|prefixsum_1m` | 720 | 1500 |
| `variable_height\|1k_lines_20_visible_overscan_0` | 4100 | 8200 |
| `variable_height\|100k_lines_80_visible_overscan_5` | 14000 | 28000 |
| `variable_height\|1m_lines_200_visible_overscan_50` | 45000 | 90000 |

Save the script's actual output — Task 7 records it verbatim.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
        .github/scripts/derive-gate-budgets.sh
git commit -m "docs: commit the hosted gate-budget corpus and its derivation script

The budgets the next task applies are derived from this corpus by this
script, so the numbers can be re-derived rather than trusted. Slice 27's
budgets were typed in and never checked; that is the failure this slice
exists to repair, and it should not be repeated by transcribing a table."
```

---

## Task 2: Apply the recalibrated budgets

Budgets only. **No logic changes** in this task — that is what makes the byte-identical checksums a real proof.

Order matters: budgets are tightened *before* the ceiling exists (Task 3). Doing it the other way round would make every query gate fail the moment the ceiling landed, and the tree must stay green at every commit.

**Files:**
- Modify: `Sources/ViewportBenchmarks/LineQueryBenchmark.swift:20-32` (5 scenarios)
- Modify: `Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift:21-33` (5)
- Modify: `Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift:21-33` (5)
- Modify: `Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift:22-34` (5)
- Modify: `Sources/ViewportBenchmarks/VariableHeightBenchmark.swift:14-45` (3)

**Interfaces:**
- Consumes: the budget table printed by Task 1 Step 3.
- Produces: scenario tables whose `p95BudgetNanoseconds` / `p99BudgetNanoseconds` are the derived values. `PointQueryBenchmark.swift` is **deliberately untouched** — it has no hosted evidence yet (Task 5).

- [ ] **Step 1: Record the pre-change checksums**

Run:

```bash
swift build -c release
for m in --gate --variable-height --variable-height-mutation --structural-mutation \
         --bulk-structural-mutation --line-query --line-geometry-query \
         --column-query --column-geometry-query --point-query; do
  swift run -c release ViewportBenchmarks -- "$m" --gate
done | grep -oE 'mode=[a-z_]+ .*scenario=[a-z0-9_]+.*checksum=[0-9-]+' \
     | sed -E 's/.*mode=([a-z_]+).*scenario=([a-z0-9_]+).*checksum=([0-9-]+)/\1|\2 \3/' \
     | sort > /tmp/checksums-before.txt
wc -l < /tmp/checksums-before.txt
```

Expected: 42 lines (42 gated scenarios). Keep this file — Step 4 diffs against it.

- [ ] **Step 2: Replace the budget constants**

In each file, replace only the two budget arguments per scenario. Example — `LineQueryBenchmark.swift`, whose scenario list becomes:

```swift
func lineQueryScenarios() -> [LineQueryScenario] {
    [
        LineQueryScenario(name: "uniform_1k", providerName: "uniform",
                          lineCount: 1_000, useBalancedTree: false,
                          p95BudgetNanoseconds: 200, p99BudgetNanoseconds: 440),
        LineQueryScenario(name: "uniform_100k", providerName: "uniform",
                          lineCount: 100_000, useBalancedTree: false,
                          p95BudgetNanoseconds: 280, p99BudgetNanoseconds: 560),
        LineQueryScenario(name: "uniform_1m", providerName: "uniform",
                          lineCount: 1_000_000, useBalancedTree: false,
                          p95BudgetNanoseconds: 330, p99BudgetNanoseconds: 660),
        LineQueryScenario(name: "balanced_tree_100k", providerName: "balanced_tree",
                          lineCount: 100_000, useBalancedTree: true,
                          p95BudgetNanoseconds: 1_700, p99BudgetNanoseconds: 3_400),
        LineQueryScenario(name: "balanced_tree_1m", providerName: "balanced_tree",
                          lineCount: 1_000_000, useBalancedTree: true,
                          p95BudgetNanoseconds: 2_100, p99BudgetNanoseconds: 4_200),
    ]
}
```

Apply the same substitution to the other four files, matching scenario name to the Task 1 table. Also delete the now-false comment in `LineQueryBenchmark.swift` that calls these "Starter budgets (macOS-calibrated in Step 6)" — that comment is the origin of this entire slice. Replace it with:

```swift
// Budgets derived from hosted Linux x86_64 by .github/scripts/derive-gate-budgets.sh
// against docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv.
// Hosted is the calibration authority: it runs 2-3x slower than local macOS, so it
// binds. Do not hand-edit — re-derive.
```

- [ ] **Step 3: Build and run every gate**

Run:

```bash
swift build -c release
for m in --line-query --line-geometry-query --column-query --column-geometry-query --variable-height; do
  swift run -c release ViewportBenchmarks -- "$m" --gate
done
```

Expected: every line `gate=pass`, `failures=0`. Local p95 sits far under the new budgets (local runs 2–3× faster than the hosted machine these budgets were cut for), so a failure here means a budget was mistyped — compare against the Task 1 table.

- [ ] **Step 4: Prove no measured path moved**

Run:

```bash
for m in --gate --variable-height --variable-height-mutation --structural-mutation \
         --bulk-structural-mutation --line-query --line-geometry-query \
         --column-query --column-geometry-query --point-query; do
  swift run -c release ViewportBenchmarks -- "$m" --gate
done | grep -oE 'mode=[a-z_]+ .*scenario=[a-z0-9_]+.*checksum=[0-9-]+' \
     | sed -E 's/.*mode=([a-z_]+).*scenario=([a-z0-9_]+).*checksum=([0-9-]+)/\1|\2 \3/' \
     | sort > /tmp/checksums-after.txt
diff /tmp/checksums-before.txt /tmp/checksums-after.txt && echo "CHECKSUMS IDENTICAL"
```

Expected: `CHECKSUMS IDENTICAL`, exit 0. Any diff means a scenario's *workload* changed, which this task must not do — revert and find the edit that did it.

- [ ] **Step 5: Full test suite and the Foundation scan**

Run:

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests"
rg -n "Foundation" Sources/TextEngineCore; echo "core scan exit: $?"
git diff --name-only main -- Sources/TextEngineCore | wc -l
```

Expected: `Executed 232 tests, with 0 failures`; the scan prints nothing and reports `core scan exit: 1`; the core diff is `0` lines.

- [ ] **Step 6: Commit**

```bash
git add Sources/ViewportBenchmarks/
git commit -m "feat: recalibrate the query and variable-height gate budgets

The five query gates ran 815x-3000x looser than observed hosted latency and
--variable-height 45x-98x, so none of them could catch the constant-factor
regressions a latency gate exists to catch: --column-query passed even if the
O(log M) search were replaced by a linear scan over all 256 cells.

Budgets are now derived from 19-20 hosted runs by derive-gate-budgets.sh.
Every gate checksum is byte-identical, so no measured path moved."
```

---

## Task 3: Teach the gate to reject its own stale budgets

TDD, and the first tests the gate logic has ever had — `passesGate` and `formatSummary` are today reachable from no test target at all, which is precisely how an uncalibrated placeholder propagated through five slices without anything objecting.

**Files:**
- Modify: `Package.swift` (add one test target)
- Create: `Tests/ViewportBenchmarksTests/GateLogicTests.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkModels.swift:40-48`
- Modify: `Sources/ViewportBenchmarks/BenchmarkSupport.swift:93-102`

**Interfaces:**
- Produces, consumed by Task 5 and Task 7:
  - `enum GateFailureReason: String { case operationFailures = "operation_failures", budgetExceeded = "budget_exceeded", budgetStale = "budget_stale", missingBudget = "missing_budget" }`
  - `BenchmarkSummary.headroomP95: Double?` — `budget_p95 ÷ p95`, `.infinity` when `p95 <= 0`, `nil` when there is no budget.
  - `BenchmarkSummary.gateFailureReason: GateFailureReason?` — `nil` iff the gate passes.
  - `BenchmarkSummary.passesGate: Bool` — now `gateFailureReason == nil`.
  - `enum GateLimits { static let maxHeadroomP95: Double = 50.0 }`
  - Gate output gains ` headroom_p95=N.Nx`, and on failure ` reason=<raw value>`.

- [ ] **Step 1: Add the test target**

In `Package.swift`, insert between the two existing test targets:

```swift
        .testTarget(
            name: "ViewportBenchmarksTests",
            dependencies: ["ViewportBenchmarks"]
        ),
```

A test target may depend on an executable target under swift-tools 6.0. This was verified end-to-end on macOS arm64 while validating the spec: `@testable import ViewportBenchmarks` builds **and executes**, so the executable's `main.swift` does not collide with the test bundle's entry point. If hosted Linux disagrees (it is proven by the PR's own `swift test` step), the fallback is to extract the gate types into a small `BenchmarkKit` library target that both the executable and the tests depend on.

- [ ] **Step 2: Write the failing tests**

Create `Tests/ViewportBenchmarksTests/GateLogicTests.swift`:

```swift
import XCTest
@testable import ViewportBenchmarks

private func summary(
    p95: Int64,
    p99: Int64,
    budgetP95: Int64?,
    budgetP99: Int64?,
    failures: Int = 0
) -> BenchmarkSummary {
    BenchmarkSummary(
        mode: .lineQuery,
        providerName: "uniform",
        scenarioName: "test",
        iterations: 1,
        operationsPerSample: 1,
        lineCount: 1_000,
        documentBytes: nil,
        lineBytes: nil,
        p95Nanoseconds: p95,
        p99Nanoseconds: p99,
        checksum: 0,
        failureCount: failures,
        p95BudgetNanoseconds: budgetP95,
        p99BudgetNanoseconds: budgetP99
    )
}

final class GateLogicTests: XCTestCase {

    // The bug this slice exists to repair: a budget so far above reality that no
    // regression can trip it. Latency is inside budget and nothing failed, yet the
    // gate must reject it -- the budget, not the code, is broken.
    func testInflatedBudgetFailsTheGate() {
        let s = summary(p95: 20, p99: 40, budgetP95: 60_000, budgetP99: 120_000)
        XCTAssertFalse(s.passesGate)
        XCTAssertEqual(s.gateFailureReason, .budgetStale)
    }

    func testBudgetInsideTheBandPassesTheGate() {
        let s = summary(p95: 40, p99: 70, budgetP95: 330, budgetP99: 660)
        XCTAssertTrue(s.passesGate)
        XCTAssertNil(s.gateFailureReason)
    }

    // Exactly at the ceiling is still in band; a hair past it is not.
    func testCeilingBoundaryIsInclusive() {
        let atCeiling = summary(p95: 10, p99: 20, budgetP95: 500, budgetP99: 1_000)
        XCTAssertEqual(atCeiling.headroomP95, 50.0)
        XCTAssertTrue(atCeiling.passesGate)

        let pastCeiling = summary(p95: 10, p99: 20, budgetP95: 501, budgetP99: 1_000)
        XCTAssertFalse(pastCeiling.passesGate)
        XCTAssertEqual(pastCeiling.gateFailureReason, .budgetStale)
    }

    // The two failures demand opposite responses, so the gate must say which it is.
    func testSlowCodeAndStaleBudgetAreDistinguished() {
        let slow = summary(p95: 400, p99: 700, budgetP95: 330, budgetP99: 660)
        XCTAssertEqual(slow.gateFailureReason, .budgetExceeded)

        let slowOnP99Only = summary(p95: 100, p99: 700, budgetP95: 330, budgetP99: 660)
        XCTAssertEqual(slowOnP99Only.gateFailureReason, .budgetExceeded)
    }

    func testOperationFailuresOutrankBudgetChecks() {
        let s = summary(p95: 40, p99: 70, budgetP95: 330, budgetP99: 660, failures: 1)
        XCTAssertEqual(s.gateFailureReason, .operationFailures)
    }

    func testMissingBudgetFailsTheGate() {
        let s = summary(p95: 40, p99: 70, budgetP95: nil, budgetP99: nil)
        XCTAssertFalse(s.passesGate)
        XCTAssertEqual(s.gateFailureReason, .missingBudget)
        XCTAssertNil(s.headroomP95)
    }

    // A workload too cheap for the clock guards nothing. Must not divide by zero.
    func testZeroLatencyIsUnboundedHeadroomAndFails() {
        let s = summary(p95: 0, p99: 0, budgetP95: 330, budgetP99: 660)
        XCTAssertEqual(s.headroomP95, .infinity)
        XCTAssertEqual(s.gateFailureReason, .budgetStale)
    }

    func testHeadroomIsBudgetOverP95() {
        XCTAssertEqual(summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 640).headroomP95, 8.0)
    }

    func testGateOutputCarriesHeadroomAndReason() {
        let passing = formatSummary(
            summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 640), includeGate: true)
        XCTAssertTrue(passing.contains(" headroom_p95=8.0x"), passing)
        XCTAssertTrue(passing.contains(" gate=pass"), passing)
        XCTAssertFalse(passing.contains(" reason="), passing)

        let stale = formatSummary(
            summary(p95: 20, p99: 40, budgetP95: 60_000, budgetP99: 120_000), includeGate: true)
        XCTAssertTrue(stale.contains(" gate=fail"), stale)
        XCTAssertTrue(stale.contains(" reason=budget_stale"), stale)
    }

    // Non-gate output is a separate contract and must not change.
    func testNonGateOutputIsUnchanged() {
        let line = formatSummary(
            summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 640), includeGate: false)
        XCTAssertFalse(line.contains("headroom_p95"), line)
        XCTAssertFalse(line.contains("budget_p95_ns"), line)
        XCTAssertFalse(line.contains("gate="), line)
    }

    // The p95-only ceiling cannot see an inflated p99 budget, so pin it statically
    // over the real scenario tables.
    func testEveryScenarioTableKeepsP99AtLeastTwiceP95() {
        var budgets: [(String, Int64, Int64)] = []
        for s in lineQueryScenarios() {
            budgets.append(("line_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in lineGeometryQueryScenarios() {
            budgets.append(("line_geometry_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in columnQueryScenarios() {
            budgets.append(("column_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in columnGeometryQueryScenarios() {
            budgets.append(("column_geometry_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in pointQueryScenarios() {
            budgets.append(("point_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in variableHeightScenarios() {
            budgets.append(("variable_height|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }

        XCTAssertFalse(budgets.isEmpty)
        for (name, p95, p99) in budgets {
            XCTAssertGreaterThanOrEqual(
                p99, 2 * p95,
                "\(name): p99 budget \(p99) is below 2x the p95 budget \(p95)")
        }
    }
}
```

Note: the scenario-table test deliberately includes `pointQueryScenarios()`, whose budgets are still the inflated 120k/240k at this point. It passes — `240_000 >= 2 * 120_000` — because it checks the *ratio*, not the magnitude. The magnitude is Task 5's job, and it is the ceiling, not this test, that will condemn it.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter GateLogicTests`
Expected: compile error — `value of type 'BenchmarkSummary' has no member 'gateFailureReason'` (and `headroomP95`). A compile failure *is* the red state here: the type does not exist yet.

- [ ] **Step 4: Implement the gate logic**

Replace `BenchmarkSummary.passesGate` in `Sources/ViewportBenchmarks/BenchmarkModels.swift` (currently lines 40-48) with:

```swift
    var headroomP95: Double? {
        guard let p95BudgetNanoseconds else {
            return nil
        }
        if p95Nanoseconds <= 0 {
            return .infinity
        }
        return Double(p95BudgetNanoseconds) / Double(p95Nanoseconds)
    }

    // A gate that cannot fail is not a gate. `budgetStale` is what makes an
    // inflated budget a build error rather than a silent no-op: the two causes
    // demand opposite responses (fix the code vs. re-derive the budget), so the
    // gate reports which one it is.
    var gateFailureReason: GateFailureReason? {
        guard let p95BudgetNanoseconds, let p99BudgetNanoseconds else {
            return .missingBudget
        }
        if failureCount != 0 {
            return .operationFailures
        }
        if p95Nanoseconds > p95BudgetNanoseconds || p99Nanoseconds > p99BudgetNanoseconds {
            return .budgetExceeded
        }
        if let headroomP95, headroomP95 > GateLimits.maxHeadroomP95 {
            return .budgetStale
        }
        return nil
    }

    var passesGate: Bool {
        gateFailureReason == nil
    }
```

Add above `struct BenchmarkSummary` in the same file:

```swift
enum GateLimits {
    // The budget must stay within this multiple of observed latency, or it is
    // guarding nothing. Calibrated against the fastest machine in play (local
    // macOS arm64, which runs 2-3x faster than hosted CI and so shows the highest
    // headroom): no scenario exceeds 23x there, leaving >= 2.2x of margin.
    static let maxHeadroomP95: Double = 50.0
}

enum GateFailureReason: String {
    case operationFailures = "operation_failures"
    case budgetExceeded = "budget_exceeded"
    case budgetStale = "budget_stale"
    case missingBudget = "missing_budget"
}
```

- [ ] **Step 5: Emit the new fields**

In `Sources/ViewportBenchmarks/BenchmarkSupport.swift`, add above `formatSummary`:

```swift
// One decimal place, without Foundation: `String(format:)` would drag Foundation
// into a target that has none, and the benchmark target must stay free of it.
// Returns the complete field value, `x` suffix included, so the unbounded case
// reads `inf` rather than `infx`.
func formatHeadroom(_ headroom: Double) -> String {
    if !headroom.isFinite {
        return "inf"
    }
    let tenths = Int64((headroom * 10.0).rounded())
    return "\(tenths / 10).\(tenths % 10)x"
}
```

Then replace the `if includeGate { ... }` block (currently lines 93-102) with:

```swift
    if includeGate {
        guard let p95BudgetNanoseconds = summary.p95BudgetNanoseconds,
              let p99BudgetNanoseconds = summary.p99BudgetNanoseconds,
              let headroomP95 = summary.headroomP95 else {
            preconditionFailure("gate output requires budget values")
        }

        output += " budget_p95_ns=\(p95BudgetNanoseconds)"
        output += " budget_p99_ns=\(p99BudgetNanoseconds)"
        output += " headroom_p95=\(formatHeadroom(headroomP95))"
        output += " gate=\(summary.passesGate ? "pass" : "fail")"
        if let reason = summary.gateFailureReason {
            output += " reason=\(reason.rawValue)"
        }
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter GateLogicTests`
Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 7: Run every gate and confirm the ceiling holds**

Run:

```bash
swift build -c release
for m in --gate --variable-height --variable-height-mutation --structural-mutation \
         --bulk-structural-mutation --line-query --line-geometry-query \
         --column-query --column-geometry-query; do
  swift run -c release ViewportBenchmarks -- "$m" --gate
done | grep -oE 'scenario=[a-z0-9_]+ .*headroom_p95=[0-9.]+x gate=[a-z]+' | sort
```

Expected: every line `gate=pass`, and every `headroom_p95` ≤ 50.0x (observed locally: 3.2x – 23.0x). Note `--point-query` is **excluded** — see the next step.

- [ ] **Step 8: Confirm the ceiling condemns the un-recalibrated point gate**

Run: `swift run -c release ViewportBenchmarks -- --point-query --gate; echo "exit=$?"`
Expected: `gate=fail reason=budget_stale` on all four scenarios, `exit=1`.

**This is correct, not a bug.** `--point-query` still carries its inflated 120k/240k budgets because it has no hosted evidence yet (Task 5 obtains it). The ceiling is telling the truth: that budget is stale. This is also exactly why `--point-query --gate` is not in CI yet — and it is a live demonstration that the new machinery works.

- [ ] **Step 9: Full suite and constraints**

Run:

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests"
rg -n "import Foundation" Sources/ViewportBenchmarks; echo "benchmark Foundation scan exit: $?"
git diff --name-only main -- Sources/TextEngineCore | wc -l
```

Expected: `Executed 243 tests, with 0 failures` (232 + 11); the Foundation scan prints nothing and exits 1; the core diff is `0`.

- [ ] **Step 10: Commit**

```bash
git add Package.swift Tests/ViewportBenchmarksTests/ Sources/ViewportBenchmarks/
git commit -m "feat: fail the gate when its own budget goes stale

A passing gate is not a guarding gate. The gate now reports headroom_p95 and
rejects any budget more than 50x above observed latency, so the defect this
slice repairs -- a budget so loose no regression can trip it -- becomes a build
error instead of a silent pass.

gate=fail now carries reason=: budget_exceeded (the code got slower, fix the
code) vs budget_stale (the budget no longer reflects reality, re-derive it).

Adds the benchmark target's first test target: passesGate and formatSummary
were reachable from no test at all, which is how the placeholder survived five
slices."
```

---

## Task 4: Observe `--point-query` on hosted CI

`--point-query` has zero hosted samples, and scaling local numbers by an assumed hosted/local ratio would be an inference, not evidence. So it observes before it gates — a **non-gate** step, which prints latency and cannot fail on it, so no inert gate and no ceiling exemption ever enters CI.

**Files:**
- Modify: `.github/workflows/swift-ci.yml:124` (insert a step after the column-geometry-query gate)

- [ ] **Step 1: Add the observation step**

In `.github/workflows/swift-ci.yml`, insert after the `Run column geometry query benchmark gate` step (which ends at line 124) and before `Run memory shape diagnostic`:

```yaml
      - name: Observe point query benchmark latency
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-query
```

Note the absence of `--gate`. `formatSummary(includeGate: false)` prints `p95_ns` / `p99_ns` and omits `budget_*`, `headroom_p95`, and `gate=` entirely, so this step reports hosted latency while asserting nothing about it. It still fails on `failures != 0`, which is the correctness check we do want.

- [ ] **Step 2: Push and open the PR**

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: observe point-query latency on hosted Linux before gating it

--point-query has no hosted history, so its budget cannot be derived. This
non-gate step harvests it. It is replaced by the blocking gate in this same PR,
once three hosted samples exist."
git push -u origin slice-38-gate-budget-recalibration
gh pr create --title "Slice 38: recalibrate the gate budgets and promote --point-query" \
             --body "See docs/superpowers/specs/2026-07-12-gate-budget-recalibration-design.md"
```

- [ ] **Step 3: Confirm the recalibrated budgets survive hosted Linux**

This is the moment of truth for Task 2 — the budgets were cut for this machine, and until now they have only ever run on a machine 2–3× faster.

```bash
gh run list --branch slice-38-gate-budget-recalibration --limit 1 --json databaseId --jq '.[0].databaseId'
gh run view <run-id> --log | grep -oE 'mode=[a-z_]+ .*headroom_p95=[0-9.]+x gate=[a-z]+.*'
```

Expected: all nine blocking gates `gate=pass`, every `headroom_p95` between 3.0x and 50.0x.

If a gate reports `gate=fail reason=budget_exceeded`, the floor was too thin for that scenario: raise **that** budget using the new observation (re-run `derive-gate-budgets.sh` with the sample appended to the corpus), record the new sample in the corpus file, and never widen it back toward inertness. Do not touch the ceiling.

- [ ] **Step 4: Harvest three hosted point-query samples**

Each push to the branch yields one run. Tasks 5–7 each push at least once; if you reach Task 5 with fewer than three, push a no-op docs commit to generate more. Collect them:

```bash
gh run list --branch slice-38-gate-budget-recalibration --limit 10 --json databaseId --jq '.[].databaseId' \
| while read -r id; do
    gh run view "$id" --log < /dev/null 2>/dev/null \
    | grep -oE 'mode=point_query .*p95_ns=[0-9]+ p99_ns=[0-9]+.*' \
    | awk -v id="$id" '{
        delete v
        for (i = 1; i <= NF; i++) { split($i, p, "="); v[p[1]] = p[2] }
        printf "%s\t%s\t%s\t%s\t%s\n", id, v["mode"], v["scenario"], v["p95_ns"], v["p99_ns"]
      }'
  done | sort -u
```

Expected: 4 scenarios × ≥3 runs = ≥12 rows. Append them to `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`.

---

## Task 5: Derive the point budgets and promote the gate

**Files:**
- Modify: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` (append the point samples)
- Modify: `Sources/ViewportBenchmarks/PointQueryBenchmark.swift:26-41`
- Modify: `.github/workflows/swift-ci.yml` (replace the observation step with the gate)

**Interfaces:**
- Consumes: `derive-gate-budgets.sh` (Task 1), the `budgetStale` ceiling (Task 3), the hosted samples (Task 4).

- [ ] **Step 1: Derive the budgets**

Run:

```bash
./.github/scripts/derive-gate-budgets.sh \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv point_query
```

Expected: 4 lines, `margin_p95` and `margin_p99` both ≥ 3.0×. On a 3-sample base the **floor** terms (`3 × max`) bind, not the median terms — that is by design, and it is why the point budget is the one most likely of the 27 to need a later upward revision.

- [ ] **Step 2: Cross-check against additivity**

`pointAt` is proven pure composition — `lineAt ∘ columnAt`, no search of its own (Slice 37). Its hosted median must therefore land near the **sum** of the two 1D medians, both known from the corpus:

```bash
./.github/scripts/derive-gate-budgets.sh \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
  line_query column_query point_query | grep -E 'uniform_1m|uniform_100k'
```

Expected: `point_query|uniform_1m` median ≈ `line_query|uniform_1m` median + `column_query|uniform_1m` median (≈ 41 + 40 = **~81 ns**), within the noise of a 3-sample base.

If the point median comes in **materially above** that sum, stop. The thin sample base is not the explanation — the composite is doing work it should not be, and that is a finding to investigate, not a budget to widen around.

- [ ] **Step 3: Apply the budgets**

In `Sources/ViewportBenchmarks/PointQueryBenchmark.swift`, replace the four budget pairs in `pointQueryScenarios()` with the derived values, and replace the comment block above it with the same "derived, do not hand-edit" note used in Task 2.

- [ ] **Step 4: Verify the ceiling now accepts the point gate**

Run: `swift run -c release ViewportBenchmarks -- --point-query --gate; echo "exit=$?"`
Expected: all four scenarios `gate=pass`, `headroom_p95` ≤ 50.0x, `exit=0`.

This is the inverse of Task 3 Step 8, where the same command failed with `reason=budget_stale`. The gate is now honest.

- [ ] **Step 5: Promote the workflow step**

In `.github/workflows/swift-ci.yml`, **replace** the `Observe point query benchmark latency` step added in Task 4 with:

```yaml
      - name: Run point query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-query --gate
```

The observation step must **not** survive to `main` — an acceptance criterion. Confirm: `grep -c 'point-query$' .github/workflows/swift-ci.yml` → `0`, and `grep -c 'point-query --gate' .github/workflows/swift-ci.yml` → `1`.

Required-context names are unchanged (this is a step inside the existing `Host tests and benchmark gate` job), so the `Main` ruleset needs no edit.

- [ ] **Step 6: Full local verification**

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests"
for m in --gate --variable-height --variable-height-mutation --structural-mutation \
         --bulk-structural-mutation --line-query --line-geometry-query \
         --column-query --column-geometry-query --point-query; do
  swift run -c release ViewportBenchmarks -- "$m" --gate || echo "GATE FAILED: $m"
done | grep -c 'gate=pass'
```

Expected: `Executed 243 tests, with 0 failures`; `42` (all ten gates, all 42 scenarios pass).

- [ ] **Step 7: Commit and push**

```bash
git add Sources/ViewportBenchmarks/PointQueryBenchmark.swift \
        .github/workflows/swift-ci.yml \
        docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
git commit -m "ci: promote --point-query to the tenth blocking gate

Budgets derived from the hosted samples the observation step harvested, so the
gate lands calibrated rather than inert. The observation step is removed in the
same commit that replaces it -- it existed only to produce the evidence."
git push
```

---

## Task 6: Document the rule

The recipe is the durable, non-obvious fact this repo currently lacks. Slice 27's budgets were wrong because nothing wrote down how to set one.

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Add the calibration rule**

Add a `## Gate budgets` section to `AGENTS.md`, after the CI section:

```markdown
## Gate budgets

A gate that cannot fail is not a gate. Every gated scenario's hosted headroom
must stay inside **[3×, 50×]** of observed latency, and `--gate` enforces the
upper bound itself: `gate=fail reason=budget_stale`.

**Hosted Linux x86_64 is the calibration authority**, not local macOS. Hosted runs
2–3× slower, so it binds; a budget that holds there holds locally with room to
spare, and the reverse is false.

To set or re-derive a budget:

    ./.github/scripts/derive-gate-budgets.sh \
      docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv <mode>

    budget_p95 = round_up_2sf(max(8 × median(hosted p95), 3 × max(hosted p95)))
    budget_p99 = round_up_2sf(max(2 × budget_p95, 8 × median(p99), 3 × max(p99)))

The 3× floor covers **both** statistics because the gate fails on either. Never
hand-type a budget: Slices 27/31/33/35/37 shipped copy-pasted "starter budgets"
that ran 815×–3,000× loose, and no gate could fail for five slices.

**When an optimization trips the ceiling, raise the budget — never the ceiling.**
A genuine speed-up (Slices 29/30 cut `lineAt` from O(log²N) to O(log N)) or faster
hardware will push headroom past 50× and turn a gate red on a clean tree. That is
the ceiling working. Re-derive that budget from fresh hosted evidence in the same
PR that caused the shift.

Budgets for the ten gated modes are hosted-Linux-derived. The five compute/mutation
gates' budgets predate this rule and remain macOS-era, but sit inside the band.
```

- [ ] **Step 2: Update the CI and commands sections**

In `AGENTS.md`:
- The CI section's gate chain gains `→ --point-query --gate (blocking)` and the count becomes **ten** blocking gates.
- The `--point-query` command entry loses its "local (not-yet-CI)" label; the architecture paragraph's sentence "Its `--point-query --gate` is **local (not-yet-CI)**" becomes "`--point-query --gate` is its blocking host-job CI gate."
- The Package layout section gains `Tests/ViewportBenchmarksTests` — the gate-logic tests.

- [ ] **Step 3: Verify no stale claims remain**

Run: `rg -n "not-yet-CI|nine blocking|macOS-calibrated" AGENTS.md`
Expected: no match for `not-yet-CI` or `nine blocking`; `macOS-calibrated` appears only in the scoped sentence about the five untouched compute gates.

- [ ] **Step 4: Commit and push**

```bash
git add AGENTS.md
git commit -m "docs: state the gate-budget rule and the tenth blocking gate"
git push
```

---

## Task 7: Verification record

**Files:**
- Create: `docs/superpowers/verification/2026-07-12-gate-budget-recalibration.md`

- [ ] **Step 1: Demonstrate that the ceiling catches the original bug**

Evidence, not assertion. Temporarily revert one budget and show the gate rejects it:

```bash
sed -i.bak 's/p95BudgetNanoseconds: 330, p99BudgetNanoseconds: 660/p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000/' \
  Sources/ViewportBenchmarks/LineQueryBenchmark.swift
swift run -c release ViewportBenchmarks -- --line-query --gate; echo "exit=$?"
mv Sources/ViewportBenchmarks/LineQueryBenchmark.swift.bak Sources/ViewportBenchmarks/LineQueryBenchmark.swift
git diff --exit-code Sources/ViewportBenchmarks/LineQueryBenchmark.swift && echo "RESTORED CLEAN"
```

Expected: the `uniform_1m` line reports `gate=fail reason=budget_stale` with `headroom_p95` around 2900x, `exit=1`; then `RESTORED CLEAN`. Capture the failing line verbatim — it is the proof that the Slice 27 defect is now a build error.

- [ ] **Step 2: Write the record**

Create `docs/superpowers/verification/2026-07-12-gate-budget-recalibration.md` containing, as raw command output rather than prose:

- The corpus provenance: run count, sample count, and **per-scenario `n`** (the spec's Risks section requires this — a thin base hides tails).
- `derive-gate-budgets.sh` output for all 27 recalibrated scenarios, with both margins.
- Before/after headroom for all 42 gated scenarios.
- `swift test` → 243 tests, 0 failures.
- All ten gates locally: `gate=pass`, every `headroom_p95` in band.
- The checksum diff from Task 2 Step 4: **identical**.
- The Step 1 demonstration above: the reverted budget fails with `reason=budget_stale`.
- The core diff: `git diff --name-only main -- Sources/TextEngineCore` → empty.
- Foundation scans: core and benchmark target both clean.
- `./.github/scripts/cross-target-compile.sh --self-test` → `self_test=pass`.
- **Hosted proof**, at *step* level, not job conclusion — a green job can hide a dead `continue-on-error` step (the standing lesson from Slice 16):
  - PR-head run ID, all three required jobs, and the ten gate steps each `success`.
  - `grep -c "mode=point_query"` over the hosted log → **non-zero** (the inverse of the Slice 37 check, which required 0).
  - Every hosted `headroom_p95` recorded, to prove the band holds on the machine the budgets were cut for.
- A `## Hosted Proof — Pending` placeholder for the post-merge push run, filled by a **genuinely docs-only** follow-up PR against the stable merge commit. This is the project's clean-evidence convention (Slices 31/33/35/37) — do not fabricate the run ID in advance.

- [ ] **Step 3: Commit and push**

```bash
git add docs/superpowers/verification/2026-07-12-gate-budget-recalibration.md
git commit -m "docs: record gate-budget recalibration verification"
git push
```

- [ ] **Step 4: Confirm the final PR run is green**

```bash
gh pr checks
gh run view <latest-run-id> --log | grep -oE 'mode=[a-z_]+ .*headroom_p95=[0-9.]+x gate=[a-z]+.*' | sort
```

Expected: all three required checks pass; all ten gates `gate=pass`; every hosted `headroom_p95` inside [3.0x, 50.0x].

---

## Acceptance Criteria (from the spec — verify all before requesting review)

1. `swift test` → 232 existing + 11 new = **243 tests, 0 failures**, green on hosted Linux, not only locally.
2. `git diff --name-only main -- Sources/TextEngineCore` → **empty**. The only `Package.swift` change is the added test target.
3. All ten gates `gate=pass` locally; all 42 checksums **byte-identical** to the Slice 37 baseline.
4. Every gated scenario prints `headroom_p95` ≤ 50× locally.
5. Every recalibrated budget clears **both** floors — `budget_p95 ≥ 3 × max(hosted p95)` **and** `budget_p99 ≥ 3 × max(hosted p99)` — shown per scenario in the verification record.
6. Reverting any recalibrated budget makes `--gate` fail with `reason=budget_stale` — demonstrated (Task 7 Step 1), not asserted.
7. Hosted: all ten gates green on the PR head and the post-merge push run; `mode=point_query` **present** in the hosted log; **no non-gate point-query observation step** left in the workflow on `main`.
8. `AGENTS.md` states the calibration rule (both statistics), the band, the stale-budget policy, and the tenth blocking gate.
