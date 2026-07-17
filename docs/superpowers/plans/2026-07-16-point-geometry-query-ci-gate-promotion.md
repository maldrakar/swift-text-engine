# Point-Geometry-Query CI Gate Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote `--point-geometry-query` to the **eleventh** blocking hosted latency gate by collapsing its two CI steps (bare-correctness + `continue-on-error`-observational) into one blocking step, guarded by a committed workflow-shape regression test rather than a one-time hand check.

**Architecture:** A bare promotion — one concern, no bundled machinery change. Two durable, mode-independent rules are relocated into `AGENTS.md` *before* the text that is their only copy is deleted (spec Decision 2). The collapse is then driven test-first by a new `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`, which hand-rolls a narrow reader of `swift-ci.yml` (the package is zero-dependency and Foundation ships no YAML parser) and is red against today's two-step wiring. A fresh harvest re-derives **every** gated mode from the enlarged corpus. `TextEngineCore`, `TextEngineReferenceProviders`, and every benchmark **workload** are untouched; only budget *literals* move, and only where the re-derivation moves them.

**Tech Stack:** GitHub Actions workflow YAML; Swift 6 (swift-tools 6.0) + XCTest (`Tests/ViewportBenchmarksTests`, which already links Foundation); SwiftPM `ViewportBenchmarks` executable; `gh` CLI + bash/awk (`harvest-gate-corpus.sh`, `derive-gate-budgets.sh`); ripgrep for doc assertions.

## Global Constraints

Copied from `AGENTS.md` and the spec's Non-Goals / Acceptance Criteria. Every task's requirements implicitly include this section.

- **No `TextEngineCore` changes.** `git diff --name-only main -- Sources/TextEngineCore` must be empty in every commit.
- **No `TextEngineReferenceProviders` changes.** Same check for that directory.
- **No benchmark *workload* change.** No scenario added or removed; no viewport parameter, provider, `lineCount`, sampler, or checksum-fold edit. Only `p95BudgetNanoseconds` / `p99BudgetNanoseconds` literals may move, and only where `derive-gate-budgets.sh` moves them.
- **The four `point_geometry_query` checksums must stay byte-identical to Slice 39's.** Verified present at HEAD on 2026-07-17 (local macOS arm64):

  | scenario | checksum |
  | --- | --- |
  | `uniform_100k` | `4687694617200924928` |
  | `uniform_1m` | `6036755761047907072` |
  | `prefixsum_100k` | `1712152282485110528` |
  | `prefixsum_1m` | `5915921755926273280` |

  A drift means the workload changed — STOP.
- **No ratchet repair.** No trailing window, no outlier rejection, no floor-factor change, no recipe change of any kind. That is Slice 41.
- **The corpus is strictly append-only.** No row deletion, no reorder, no `sort -u`. Harvest only with `--corpus` (the idempotent dedup).
- **No harvester or derivation-script change.** `harvest-gate-corpus.sh` and `derive-gate-budgets.sh` are read-only this slice.
- **Never hand-type a budget.** If the recipe produces a value, commit that value — including a *looser* one. Hand-editing one back down is the prohibited practice.
- **No Foundation in `Sources/TextEngineCore`** (`rg -n "Foundation" Sources/TextEngineCore` → empty, exit 1). Same for `Sources/TextEngineReferenceProviders`.
- **`Sources/ViewportBenchmarks` imports no Foundation and must not start.** The new Foundation import lives in the *test* target only, exactly as `GateFloorTests.swift` already does.
- The new gate step must be **blocking**: no `continue-on-error: true`.
- The step sits **after** `Run point query benchmark gate` and **before** `Run memory shape diagnostic`, keeping all eleven blocking latency gates contiguous.
- The three required job context names are unchanged: `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`. No ruleset, docs-only-detector, or bypass-actor change.
- **One logical step per commit**, conventional-commit prefixes (`feat:`, `test:`, `refactor:`, `docs:`, `ci:`). The tree must be green at every commit — `swift test` is a blocking CI step, so a red-committed test would fail the required job.
- **Decision 5 (stop-and-re-derive):** if the hosted PR-head run fails on budget, re-derive from that fresh hosted evidence **in this same PR**. Do NOT restore `continue-on-error`, add a workflow-only threshold, or hand-widen a budget.

## Baseline (measured 2026-07-17 on this branch, macOS arm64, before any change)

Record these; several steps compare against them.

| Fact | Value | How it was measured |
| --- | --- | --- |
| `swift test` | **290 tests, 0 failures** | `swift test` |
| Gated scenarios | **46** (92 statistics) | `derive-gate-budgets.sh <corpus>` → 46 lines |
| Committed budgets reproducing from the corpus | **46 of 46**, byte-for-byte | Task 3 Step 1's diff, run at HEAD |
| Local gate sweep | **46 `gate=pass`, 0 `gate=fail`** | 12 gateable modes with `--gate` |
| Corpus | 1,691 data rows, **42** distinct runs | `wc -l`, `cut -f1 | sort -u | wc -l` |
| `point_geometry_query` corpus runs | **6** (all from the Slice 39 PR; run `29426572267` absent) | `grep -P '\tpoint_geometry_query\t'` |
| Steps carrying `--point-geometry-query` in `swift-ci.yml` | **2** (lines 144-154 bare, 156-159 gated `continue-on-error`) | `grep -c` |

`point_geometry_query`'s tightest hosted headroom today is **3.16× p95** (`prefixsum_100k`, 231 ns on run `29280327104` vs a 730 ns budget), and that budget sits **+5.34%** above its `3×max` floor (730 vs 693). It is **median-governed** (8 × 91 = 728 > 3 × 231 = 693). This slice does not widen that margin — see the spec's Risks section.

---

## Task 1: Relocate the two durable rules into `AGENTS.md` before their only copies are deleted

Spec Decision 2. Two permanent, **mode-independent** rules currently live *only* inside text that Tasks 2 and 4 delete. This task re-states them as general rules first, so the slice cannot lose them. It is purely **additive** — both old copies still stand, and nothing contradicts anything, so the tree stays green and the docs stay true.

Doing this after the deletion is not an option: the deletion is what makes them unrecoverable without archaeology.

**Files:**
- Modify: `AGENTS.md` (`## CI` section, after the three-job bullet list at ~line 225 and before `Required-check policy:` at ~line 227; `## Gate budgets` section, after the append-only/dedup-key paragraph at ~lines 329-333)
- Modify: (commit only) `docs/superpowers/plans/2026-07-16-point-geometry-query-ci-gate-promotion.md`

**Interfaces:**
- Produces: two mode-independent paragraphs in `AGENTS.md` that Task 2 (workflow-comment deletion) and Task 4 (CI-section rewrite) rely on as the surviving statement of both rules. Neither paragraph mentions point-geometry-query.

- [ ] **Step 1: Commit this plan**

```bash
cd /Users/aabanschikov/swift-text-engine
git add docs/superpowers/plans/2026-07-16-point-geometry-query-ci-gate-promotion.md
git commit -m "$(cat <<'EOF'
docs: add slice 40 point-geometry-query CI gate promotion plan

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 2: Assert the "before" state — neither rule exists as mode-independent prose**

Run:

```bash
cd /Users/aabanschikov/swift-text-engine
rg -c "Exactly one CI step may print" AGENTS.md; echo "rule1 exit=$?"
rg -c "A \`continue-on-error\` step cannot be a gate" AGENTS.md; echo "rule2 exit=$?"
```

Expected: both print nothing and report `exit=1` (ripgrep's no-match exit). This is the red state: both rules exist **only** inside `swift-ci.yml:130-143` and `AGENTS.md:102-106` / `AGENTS.md:203-213`, all of which this slice deletes.

- [ ] **Step 3: Add rule 2 (a `continue-on-error` step cannot be a gate) to `## CI`**

In `AGENTS.md`, insert a new paragraph immediately **after** the `- **WASM cross-target observation** …` bullet ends (the line `  installed/provisioned, otherwise records a non-blocking skip.`) and **before** the line `Required-check policy: the public repository …`. Insert, separated by blank lines:

```markdown
A `continue-on-error` step cannot be a gate. It swallows every non-zero exit —
budget misses, correctness failures, and crashes alike (the Slice 16 dead-step
trap). An observational benchmark step and a blocking correctness step must
therefore be separate steps until the budget itself goes blocking, at which
point one step is both.
```

This is deliberately stated for **any** gate, not for point-geometry-query: `AGENTS.md:105-106` and `AGENTS.md:207-209` are the repo's only two records of the Slice 16 lesson, and Tasks 2 and 4 delete both.

- [ ] **Step 4: Add rule 1 (exactly one printing step) to `## Gate budgets`**

In `AGENTS.md`, insert a new paragraph immediately **after** the append-only/dedup-key paragraph (the one ending `…it would collapse two genuine repetitions that happened to measure the same nanoseconds, and it reorders every row.`) and **before** the paragraph beginning `The one time to harvest **without** \`--corpus\`…`. Insert, separated by blank lines:

```markdown
**Exactly one CI step may print a given mode's benchmark summary lines.** The
harvester reads every `p95_ns=` line in a run's log, so a second printing step
puts two rows per scenario into every future harvest of that run and
double-weights it in `median()` — the term that governs most budgets. This is a
different rule from the idempotent `--corpus` dedup above (which is about
harvesting the *same run* twice): here one run genuinely carries two rows per
scenario, and no dedup key can tell them apart.
```

Note it is distinct from the idempotent-harvest rule and the append-only/dedup-key paragraph; both of those stay exactly as they are.

- [ ] **Step 5: Assert the "after" state**

Run:

```bash
cd /Users/aabanschikov/swift-text-engine
rg -n "Exactly one CI step may print" AGENTS.md
rg -n "A \`continue-on-error\` step cannot be a gate" AGENTS.md
# Neither relocated rule may be phrased in terms of point-geometry-query:
rg -n "point-geometry|point_geometry" AGENTS.md | rg -n "Exactly one CI step|cannot be a gate" && echo "MODE-COUPLED — FAIL" || echo "both rules are mode-independent OK"
# Both old copies are still standing — this task deletes nothing:
grep -c -- '--point-geometry-query' .github/workflows/swift-ci.yml
```

Expected: one match each for the two rules; `both rules are mode-independent OK`; `2` (the workflow is untouched).

- [ ] **Step 6: Confirm scope and commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git diff --name-only   # expect only AGENTS.md
swift test 2>&1 | grep -E "Executed [0-9]+ tests"   # expect 290 tests, 0 failures
git add AGENTS.md
git commit -m "$(cat <<'EOF'
docs: state the one-printing-step and continue-on-error-is-not-a-gate rules

Both are permanent, mode-independent rules that today live only inside text
Slice 40 deletes: the 14-line rationale comment in swift-ci.yml and the
two-step point-geometry-query description in AGENTS.md. Re-state them as
general rules first, so the collapse cannot take them with it.

Rule 1 (one printing step) belongs with the harvester's other rules under
## Gate budgets; rule 2 (the Slice 16 dead-step trap) belongs under ## CI,
detached from any one mode.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Pin the workflow shape with a test, then collapse the two steps into one

Spec Decisions 1 and 6. This is the slice's failing-first anchor and the only Swift it adds.

The test and the collapse land in **one commit**, matching the house TDD pattern (Slice 38 Task 3 committed `GateLogicTests.swift` together with the logic it drove). Committing the red test alone would leave `swift test` — a blocking CI step — failing at that commit.

Deleting only one half of the wiring is the trap the spec names: keeping the bare step alone would double-run the mode and double-weight it in every future harvest of that run; keeping `continue-on-error` alone would swallow correctness failures too. Both go in the same edit.

**Files:**
- Create: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`
- Modify: `.github/workflows/swift-ci.yml` (delete lines 130-159 — the 14-line rationale comment, the bare correctness step, and the `continue-on-error` gated step — and insert one blocking step in their place)

**Interfaces:**
- Consumes: the `--point-geometry-query --gate` executable path shipped by Slice 39 (`Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift`), promoted unchanged.
- Produces:
  - a workflow whose `host-tests-and-benchmark-gate` job contains exactly one step named `Run point geometry query benchmark gate`, blocking, ordered point-query → point-geometry-query → memory-shape. Tasks 4-6 and the verification record reference this exact step name.
  - `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` with six `XCTestCase` methods, one per Decision 6 invariant. Test count rises 290 → **296**.

- [ ] **Step 1: Write the failing test**

Create `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`:

```swift
// Foundation is imported HERE, in the test target, purely to read the workflow file off
// disk -- the same reason GateFloorTests.swift imports it. Sources/ViewportBenchmarks
// stays Foundation-free; a test-target import cannot change that, and the XCTest runtime
// already links Foundation anyway.
import Foundation
import XCTest

// The shape this pins is the one the Slice 16 dead-step trap destroyed once already: a
// `continue-on-error` step swallows EVERY non-zero exit, so a gated step under it is
// budget-blind AND failure-blind. Slice 39 worked around that with two steps -- a bare
// correctness run plus an observational gated run -- and Slice 40 collapsed them into one
// blocking step. Nothing else in the repo reads swift-ci.yml, so without this test the
// collapse is verified exactly once, by hand, into a verification record: the failure mode
// GateFloorTests.swift was created to end.
//
// Scoped to --point-geometry-query on purpose, and NOT to `BenchmarkMode.allCases where
// isGateable`. That quantifier is false today for 3 of the 12 gateable modes, so a test
// written against it would be red for reasons unrelated to this slice -- and `swift test`
// is a blocking CI step, so it would fail the required job:
//   * .pipeline has no flag at all; it is the default mode, run as a bare `--gate`.
//   * .realisticProvider is deliberately never run with `--gate` in CI (AGENTS.md,
//     "## Gate budgets"): its step is PR-only and continue-on-error.
//   * there is no BenchmarkMode -> flag mapping to match against; BenchmarkMode exposes
//     only snake_case `outputName`, while the flags live as hand-written `case` labels
//     inside BenchmarkOptions.parse.
// Generalizing to every CI-gated mode needs a `flagName` property, a named-and-justified
// exemption set, and a test pinning the two together -- a design of its own.

private let workflowPath = ".github/workflows/swift-ci.yml"
private let hostJobKey = "host-tests-and-benchmark-gate"
private let pointGeometryFlag = "--point-geometry-query"
private let pointGeometryStepName = "Run point geometry query benchmark gate"
private let pointQueryStepName = "Run point query benchmark gate"
private let memoryShapeStepName = "Run memory shape diagnostic"
private let docsOnlyGuard = "steps.change-scope.outputs.docs_only_pr != 'true'"

// Twin of `repositoryRoot()` in GateFloorTests.swift -- the same three-parent walk from
// #filePath. Duplicated rather than shared because both are file-scope `private` helpers
// in a target with no test-support file; if one moves, move the other.
private func repositoryRoot() -> URL {
    // .../Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift -> repo root
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private struct WorkflowStep {
    let name: String
    let index: Int          // position within the host job's step list
    let ifCondition: String?
    let continueOnError: String?
    let runTokens: [String]
}

private func indentation(of line: String) -> Int {
    line.prefix(while: { $0 == " " }).count
}

private func isBlank(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).isEmpty
}

private func isComment(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
}

// A step key at the fixed 8-space indent this file uses, e.g. `        if: ...`.
private func value(of key: String, in line: String) -> String? {
    let prefix = "        \(key):"
    guard line.hasPrefix(prefix) else { return nil }
    return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
}

// There is no YAML parser in reach -- the package is zero-dependency and Foundation ships
// none -- so this is a deliberately narrow reader of the one shape swift-ci.yml actually
// uses: 6-space `- name:` step headers, 8-space step keys, and a `run:` that is either
// inline or a `|` block scalar whose body is indented past the key.
//
// Comment lines are excluded everywhere. That is load-bearing, not tidiness: the rationale
// comment this slice deletes sits INSIDE the point-query gate's block (it precedes the next
// `- name:`) and says the words "continue-on-error" twice, so a reader that scanned raw
// text would call a blocking step observational.
private func parseStep(_ block: [String], index: Int) -> WorkflowStep {
    let header = "      - name:"
    let name = String(block[0].dropFirst(header.count)).trimmingCharacters(in: .whitespaces)

    var ifCondition: String?
    var continueOnError: String?
    var runTokens: [String] = []

    for (offset, line) in block.enumerated() {
        if isComment(line) { continue }
        if let condition = value(of: "if", in: line) { ifCondition = condition }
        if let flag = value(of: "continue-on-error", in: line) { continueOnError = flag }
        if let inlineRun = value(of: "run", in: line) {
            var payload = [inlineRun]
            var cursor = offset + 1
            while cursor < block.count {
                let next = block[cursor]
                cursor += 1
                if isBlank(next) { continue }
                if indentation(of: next) <= 8 { break }   // a sibling key ends the payload
                if isComment(next) { continue }
                payload.append(next)
            }
            // Whitespace-separated TOKENS, never substrings: `--variable-height` is a
            // prefix of `--variable-height-mutation`, and `contains(_: String)` on the
            // joined payload would conflate the two.
            runTokens = payload.joined(separator: " ")
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
        }
    }

    return WorkflowStep(name: name, index: index, ifCondition: ifCondition,
                        continueOnError: continueOnError, runTokens: runTokens)
}

// Scoped to the host job's own region -- from its 2-space key to the next one. All three
// jobs indent their steps identically, and four step names (`Check out repository`,
// `Detect PR change scope`, `Complete docs-only PR`, `Show toolchain`) repeat verbatim
// across them, so a whole-file split would make every name lookup ambiguous.
private func hostJobSteps() throws -> [WorkflowStep] {
    let url = repositoryRoot().appendingPathComponent(workflowPath)
    let text = try String(contentsOf: url, encoding: .utf8)
    let allLines = text.components(separatedBy: "\n")

    guard let jobStart = allLines.firstIndex(where: { $0.hasPrefix("  \(hostJobKey):") }) else {
        XCTFail("\(workflowPath): no job keyed \(hostJobKey)")
        return []
    }

    var jobEnd = allLines.count
    for index in (jobStart + 1)..<allLines.count {
        let line = allLines[index]
        if isBlank(line) || isComment(line) { continue }
        if indentation(of: line) <= 2 {
            jobEnd = index
            break
        }
    }

    let lines = Array(allLines[jobStart..<jobEnd])
    let starts = lines.indices.filter { lines[$0].hasPrefix("      - name:") }
    return starts.enumerated().map { order, start in
        let end = order + 1 < starts.count ? starts[order + 1] : lines.count
        return parseStep(Array(lines[start..<end]), index: order)
    }
}

private func stepNamed(_ name: String, in steps: [WorkflowStep]) -> WorkflowStep? {
    steps.first { $0.name == name }
}

final class WorkflowShapeTests: XCTestCase {

    // Every test resolves the point-geometry steps by FLAG, not by name, and asserts the
    // set is non-empty first. A test that quantified over an empty set would be vacuously
    // green the day someone deleted the gate outright.
    private func pointGeometrySteps() throws -> [WorkflowStep] {
        let matches = try hostJobSteps().filter { $0.runTokens.contains(pointGeometryFlag) }
        XCTAssertFalse(
            matches.isEmpty,
            "\(workflowPath): no step in \(hostJobKey) runs \(pointGeometryFlag) — the "
                + "eleventh blocking gate is gone")
        return matches
    }

    // Invariant 1. Two steps ran this mode while its budget was observational: a bare
    // correctness run and a continue-on-error gated run. One step cannot be both, so the
    // split was correct scaffolding -- and it had to end as one step, not one and a half.
    // A second printing step also puts two rows per scenario into every future harvest of
    // that run and double-weights it in median().
    func testExactlyOneStepRunsThePointGeometryQueryBenchmark() throws {
        let matches = try pointGeometrySteps()
        XCTAssertEqual(
            matches.count, 1,
            "\(workflowPath): \(matches.count) steps run \(pointGeometryFlag), want exactly "
                + "1 — \(matches.map(\.name))")
    }

    // Invariant 2. Without --gate the step prints latency and asserts nothing about it.
    func testThePointGeometryStepEnforcesItsBudget() throws {
        for step in try pointGeometrySteps() {
            XCTAssertTrue(
                step.runTokens.contains("--gate"),
                "\(step.name): runs \(pointGeometryFlag) without --gate — it observes "
                    + "latency instead of gating on it")
        }
    }

    // Invariant 3. THE one that matters: continue-on-error swallows every non-zero exit,
    // so a gated step under it can fail neither on budget nor on failureCount != 0.
    func testThePointGeometryStepIsNotContinueOnError() throws {
        for step in try pointGeometrySteps() {
            XCTAssertNil(
                step.continueOnError,
                "\(step.name): carries continue-on-error: \(step.continueOnError ?? "") — a "
                    + "continue-on-error step cannot be a gate; it swallows budget misses, "
                    + "correctness failures and crashes alike")
        }
    }

    // Invariant 4. The same docs-only guard every sibling gate carries, asserted as the
    // literal expression so no other step's shape can turn this test red or green.
    func testThePointGeometryStepCarriesTheDocsOnlyGuard() throws {
        for step in try pointGeometrySteps() {
            XCTAssertEqual(
                step.ifCondition, docsOnlyGuard,
                "\(step.name): does not carry the sibling docs-only guard")
        }
    }

    // Invariant 5. The name is the only place a reader learns whether the step is blocking,
    // so a stale "observational"/"until Slice 40" qualifier is a lie in the log of every run.
    func testThePointGeometryStepIsNamedForItsSiblings() throws {
        for step in try pointGeometrySteps() {
            XCTAssertEqual(
                step.name, pointGeometryStepName,
                "step running \(pointGeometryFlag) is named \"\(step.name)\", want "
                    + "\"\(pointGeometryStepName)\"")
        }
    }

    // Invariant 6. All eleven blocking latency gates stay contiguous, ahead of the
    // diagnostics.
    func testThePointGeometryStepSitsBetweenThePointQueryGateAndTheMemoryShapeDiagnostic() throws {
        let steps = try hostJobSteps()
        let matches = steps.filter { $0.runTokens.contains(pointGeometryFlag) }
        XCTAssertFalse(matches.isEmpty)

        guard let pointQuery = stepNamed(pointQueryStepName, in: steps),
              let memoryShape = stepNamed(memoryShapeStepName, in: steps) else {
            XCTFail("\(workflowPath): missing \"\(pointQueryStepName)\" or "
                + "\"\(memoryShapeStepName)\" — the ordering anchors are gone")
            return
        }

        for step in matches {
            XCTAssertLessThan(
                pointQuery.index, step.index,
                "\(step.name) must sit after \"\(pointQueryStepName)\"")
            XCTAssertLessThan(
                step.index, memoryShape.index,
                "\(step.name) must sit before \"\(memoryShapeStepName)\"")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails, and capture the red output**

Run:

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WorkflowShapeTests 2>&1 | tee /tmp/workflow-shape-red.txt | grep -E "error:|failed|Executed [0-9]+ tests"
```

Expected: **4 of the 6 tests fail** (verified against the real file on 2026-07-17):

| test | pre-collapse | why |
| --- | --- | --- |
| `testExactlyOneStepRunsThePointGeometryQueryBenchmark` | **FAIL** | `2 steps run --point-geometry-query, want exactly 1 — ["Run point geometry query benchmark (correctness; blocking)", "Point-geometry query benchmark gate (budget observational until Slice 40)"]` |
| `testThePointGeometryStepEnforcesItsBudget` | **FAIL** | the bare correctness step has no `--gate` |
| `testThePointGeometryStepIsNotContinueOnError` | **FAIL** | `carries continue-on-error: true` |
| `testThePointGeometryStepCarriesTheDocsOnlyGuard` | PASS | both steps already carry it |
| `testThePointGeometryStepIsNamedForItsSiblings` | **FAIL** | both names are the two-step-era names |
| `testThePointGeometryStepSitsBetweenThePointQueryGateAndTheMemoryShapeDiagnostic` | PASS | both already sit at indices 15/16, between 14 and 17 |

Keep `/tmp/workflow-shape-red.txt` — Task 5 records the red assertion messages verbatim (AC3 requires it).

If **all six** pass, the parser is not reading the file: check `repositoryRoot()` resolves and that `hostJobSteps()` returns 20 steps against the pre-collapse workflow.

- [ ] **Step 3: Collapse the two steps into one blocking step**

In `.github/workflows/swift-ci.yml`, **delete lines 130-159 in one edit** — the 14-line rationale comment (130-143), the bare correctness step (144-154), and the `continue-on-error` gated step (156-159) — and put one step in their place. The region between the point-query gate and the memory-shape diagnostic becomes exactly:

```yaml
      - name: Run point query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-query --gate

      - name: Run point geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate

      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

6-space step indent, 8-space keys, one blank line between steps — identical to the ten sibling gates. Do not move or alter any other step.

The comment must go **with** the steps it explains: it says the split lasts "until Slice 40, which deletes this step and the `continue-on-error` on that one together", which is false the moment the collapse lands. Its durable half is already relocated (Task 1).

The single step is blocking on **both** halves at once: `--gate` makes `failureCount != 0` a `gateFailureReason.operationFailures`, so correctness still reddens the job — the property the bare step existed to preserve.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter WorkflowShapeTests 2>&1 | grep -E "failed|Executed [0-9]+ tests"
```

Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Assert the workflow text invariants directly (AC1, AC2)**

```bash
cd /Users/aabanschikov/swift-text-engine
grep -c -- '--point-geometry-query' .github/workflows/swift-ci.yml          # expect 1
grep -c -- '--point-geometry-query --gate' .github/workflows/swift-ci.yml   # expect 1
grep -c '^        continue-on-error:' .github/workflows/swift-ci.yml        # expect 1
rg -n "observational|Slice 40|correctness" .github/workflows/swift-ci.yml || echo "no stale two-step text OK"
```

Expected: `1`, `1`, `1`, and `no stale two-step text OK`.

Notes on the third check: it is anchored to the 8-space step **key**, not to the bare string. Unanchored, `grep -c 'continue-on-error'` returns `5` before the collapse and `2` after — the extra hits are prose inside comments (the rationale block, and the realistic-provider step's own `shell: bash` comment, which survives). The one surviving key is the realistic-provider observation step at ~line 144. Verified pre-collapse: `^        continue-on-error:` matches lines 158 and 171, and all `observational|Slice 40|correctness` matches lie inside the deleted 130-159 region.

- [ ] **Step 6: Full suite, workload identity, and scope**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test 2>&1 | grep -E "Executed [0-9]+ tests"
swift build -c release
swift run -c release ViewportBenchmarks -- --point-geometry-query --gate; echo "exit=$?"
rg -n "Foundation" Sources/TextEngineCore; echo "core scan exit: $?"
rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "provider scan exit: $?"
rg -n "import Foundation" Sources/ViewportBenchmarks; echo "benchmark scan exit: $?"
git diff --name-only   # expect only .github/workflows/swift-ci.yml + the new test file
```

Expected: `Executed 296 tests, with 0 failures` (290 + 6); four `gate=pass` with `failures=0` and `exit=0`; the four checksums byte-identical to the Global Constraints table; all three Foundation scans print nothing and report `exit: 1`.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add .github/workflows/swift-ci.yml Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
git commit -m "$(cat <<'EOF'
ci: promote --point-geometry-query to the eleventh blocking gate

Collapse the two point-geometry-query steps into one. The bare correctness run
and the continue-on-error gated run were scaffolding Slice 39 built precisely
so this slice could delete both halves at once: keeping the bare step alone
would double-run the mode and double-weight it in every future harvest of that
run; keeping continue-on-error alone would swallow correctness failures too.

--gate blocks on both halves at once -- failureCount != 0 is
reason=operation_failures -- so correctness stays blocking.

WorkflowShapeTests reads swift-ci.yml and pins the six invariants: exactly one
step carries the flag, it passes --gate, it is not continue-on-error, it carries
the docs-only guard, it is named for its siblings, and it sits between the
point-query gate and the memory-shape diagnostic. Nothing else in the repo reads
that file; verifying this shape once by hand is the failure mode GateFloorTests
was created to end.

Benchmark source and budgets unchanged; the four Slice 39 checksums are
byte-identical.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Harvest fresh hosted evidence and re-derive every gated mode

Spec Decision 3. A harvest re-derives **every** mode, not the one you came for: each hosted run measures all the gated modes, so appending it moves `max(hosted)` — and can move the median — for scenarios this slice never touched.

The append and the re-derivation are **one commit**. `GateFloorTests` reads the *committed* corpus on every `swift test`, and six budgets repo-wide sit within ~5% of their `3×max` floor (worst: `line_geometry_query|uniform_1k` p99 at **0.0%**). A commit that appends rows without re-deriving would leave `swift test` — a blocking CI step — red. Slice 39 landed them together for the same reason (`a23e559`).

**Requires network and `gh` auth.**

**Files:**
- Modify: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` (append-only)
- Modify: whichever budget tables under `Sources/ViewportBenchmarks` the re-derivation moves — possibly none. Candidates, one `…Scenarios()` table each: `SyntheticBenchmarks.swift`, `RealisticProviderBenchmark.swift`, `VariableHeightBenchmark.swift`, `VariableHeightMutationBenchmark.swift`, `StructuralMutationBenchmark.swift`, `BulkStructuralMutationBenchmark.swift`, `LineQueryBenchmark.swift`, `LineGeometryQueryBenchmark.swift`, `ColumnQueryBenchmark.swift`, `ColumnGeometryQueryBenchmark.swift`, `PointQueryBenchmark.swift`, `PointGeometryQueryBenchmark.swift`

**Interfaces:**
- Consumes: `.github/scripts/harvest-gate-corpus.sh` and `.github/scripts/derive-gate-budgets.sh`, both unchanged.
- Produces: a corpus whose appended rows include run `29426572267`, and 46 committed budgets that reproduce byte-for-byte from `derive-gate-budgets.sh <corpus>`. Task 5 records the sweep.

- [ ] **Step 1: Snapshot the pre-harvest derivation, and prove all 46 reproduce at HEAD**

The committed budgets are the baseline the post-harvest sweep is diffed against, so establish first that they *are* the recipe's output today. This exact pipeline was run at HEAD on 2026-07-17 and printed `ALL 46 BUDGETS REPRODUCE`.

```bash
cd /Users/aabanschikov/swift-text-engine
C=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv

# The committed budgets, read out of the benchmark itself rather than parsed out of
# Swift: --gate prints budget_p95_ns/budget_p99_ns per scenario in the same key=value
# shape for all twelve tables. --realistic-provider is included because it is a GATED
# mode (46th budget) even though CI never runs it with --gate.
swift build -c release
for m in --gate --realistic-provider --variable-height --variable-height-mutation \
         --structural-mutation --bulk-structural-mutation --line-query --line-geometry-query \
         --column-query --column-geometry-query --point-query --point-geometry-query; do
  swift run -c release ViewportBenchmarks -- "$m" --gate
done > /tmp/gate-sweep-before.txt

awk '{ delete v; for (i=1;i<=NF;i++) { n=split($i,p,"="); if (n==2) v[p[1]]=p[2] }
       if (v["budget_p95_ns"] != "") printf "%s|%s %s %s\n", v["mode"], v["scenario"], v["budget_p95_ns"], v["budget_p99_ns"] }' \
  /tmp/gate-sweep-before.txt | sort > /tmp/committed-budgets.txt

./.github/scripts/derive-gate-budgets.sh "$C" > /tmp/derive-before.txt
awk '{ b95=""; b99=""; for (i=1;i<=NF;i++) { split($i,p,"="); if (p[1]=="budget_p95") b95=p[2]; if (p[1]=="budget_p99") b99=p[2] }
       printf "%s %s %s\n", $1, b95, b99 }' /tmp/derive-before.txt | sort > /tmp/derived-before.txt

wc -l < /tmp/committed-budgets.txt   # expect 46
wc -l < /tmp/derived-before.txt      # expect 46
diff /tmp/committed-budgets.txt /tmp/derived-before.txt && echo "ALL 46 BUDGETS REPRODUCE"
grep -c 'gate=pass' /tmp/gate-sweep-before.txt   # expect 46
```

Expected: `46`, `46`, `ALL 46 BUDGETS REPRODUCE`, `46`. A diff here means the tree drifted from the corpus **before** this slice touched anything — stop and report it; it is not something to re-derive around silently.

- [ ] **Step 2: Preview the harvest, and confirm it reaches run `29426572267`**

AC5 requires the appended rows to include run `29426572267` — the Slice 39 post-merge push run, and this mode's only sample that is not from the Slice 39 PR head. `--limit 40` returns the 40 most recent `swift-ci.yml` runs, and the corpus already carries 42 distinct runs, so the window is **not guaranteed** to reach back that far. Check before appending:

```bash
cd /Users/aabanschikov/swift-text-engine
C=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
grep -c '^29426572267' "$C"   # expect 0 — not yet harvested

./.github/scripts/harvest-gate-corpus.sh --limit 40 --corpus "$C" --dry-run 2>&1 >/dev/null \
  | tee /tmp/harvest-plan.txt | grep -E '^plan=harvest'
grep -c '^plan=harvest' /tmp/harvest-plan.txt
grep -c 'plan=harvest run=29426572267' /tmp/harvest-plan.txt
```

Expected: `0` for the first check, at least one `plan=harvest` line, and **`1`** for `plan=harvest run=29426572267`.

`--dry-run` writes its decisions to **stderr** (so they can never land in the corpus), hence the `2>&1 >/dev/null` redirect order.

If `plan=harvest run=29426572267` is **absent**, the run has fallen outside the window. Widen it and re-preview — `./.github/scripts/harvest-gate-corpus.sh --limit 80 --corpus "$C" --dry-run` — and use the same `--limit` in Step 3. Do **not** fall back to `--runs 29426572267` alone: that would harvest one run and silently skip every other unharvested one, which is the "convenient subset" the Slice 38 record warns against.

- [ ] **Step 3: Append the harvest**

Use the same `--limit` that Step 2's preview validated:

```bash
cd /Users/aabanschikov/swift-text-engine
C=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
cp "$C" /tmp/corpus-before.tsv

./.github/scripts/harvest-gate-corpus.sh --limit 40 --corpus "$C" >> "$C"

# Append-only proof: the old file must be a byte-exact PREFIX of the new one.
head -n "$(wc -l < /tmp/corpus-before.tsv)" "$C" | diff - /tmp/corpus-before.tsv \
  && echo "APPEND-ONLY: no row deleted, none reordered"
echo "rows: $(($(wc -l < /tmp/corpus-before.tsv) - 1)) -> $(($(wc -l < "$C") - 1))"
echo "runs: $(tail -n +2 /tmp/corpus-before.tsv | cut -f1 | sort -u | wc -l) -> $(tail -n +2 "$C" | cut -f1 | sort -u | wc -l)"
grep -c '^29426572267' "$C"
tail -n +2 "$C" | grep -P '\tpoint_geometry_query\t' | cut -f1 | sort -u | wc -l
```

Expected: `APPEND-ONLY: no row deleted, none reordered`; the row and run counts rise from 1,691 / 42; a non-zero count for run `29426572267`; and a `point_geometry_query` run count above 6 — record it, AC5 and the spec's Risks section key on it.

`--corpus` makes this idempotent: runs already in the corpus are skipped **before** their logs are fetched. Never run the harvest without it, and never `sort -u` the corpus — one run legitimately contributes many rows (a `realistic_provider` run contributes 8), and two of them can be byte-identical.

- [ ] **Step 4: Re-derive every mode and list exactly what moved**

No mode argument → all modes.

```bash
cd /Users/aabanschikov/swift-text-engine
C=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
./.github/scripts/derive-gate-budgets.sh "$C" > /tmp/derive-after.txt
wc -l < /tmp/derive-after.txt   # expect 46

awk '{ b95=""; b99=""; for (i=1;i<=NF;i++) { split($i,p,"="); if (p[1]=="budget_p95") b95=p[2]; if (p[1]=="budget_p99") b99=p[2] }
       printf "%s %s %s\n", $1, b95, b99 }' /tmp/derive-after.txt | sort > /tmp/derived-after.txt

echo "=== budgets the harvest moved (committed -> derived) ==="
diff /tmp/committed-budgets.txt /tmp/derived-after.txt || true
```

Expected: 46 lines; the `diff` lists every scenario whose budget the recipe now produces differently. **That list is the edit** — no more, no less. An empty diff is a legitimate outcome (harvest changed no budget): skip Step 5 and say so in Step 7's commit message and in the verification record.

**A re-derived budget may move in either direction.** The `8×median` term governs most budgets, and a harvest can lower a median, so a *looser* re-derived budget is a correct result to commit. Hand-editing one back down is the hand-typed-budget prohibition.

- [ ] **Step 5: Apply exactly the moved budgets**

For each key in Step 4's diff, edit only the two budget literals of that scenario in its table. Nothing else in these files may change — not a scenario name, provider, `lineCount`, sampler, viewport parameter, or comment describing the workload.

Key → file → scenario table:

| corpus mode | file | table function |
| --- | --- | --- |
| `pipeline` | `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift` | `benchmarkScenarios()` |
| `realistic_provider` | `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift` | `realisticProviderScenarios()` |
| `variable_height` | `Sources/ViewportBenchmarks/VariableHeightBenchmark.swift` | `variableHeightScenarios()` |
| `variable_height_mutation` | `Sources/ViewportBenchmarks/VariableHeightMutationBenchmark.swift` | `variableHeightMutationScenarios()` |
| `structural_mutation` | `Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift` | `structuralMutationScenarios()` |
| `bulk_structural_mutation` | `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift` | `bulkStructuralMutationScenarios()` |
| `line_query` | `Sources/ViewportBenchmarks/LineQueryBenchmark.swift` | `lineQueryScenarios()` |
| `line_geometry_query` | `Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift` | `lineGeometryQueryScenarios()` |
| `column_query` | `Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift` | `columnQueryScenarios()` |
| `column_geometry_query` | `Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift` | `columnGeometryQueryScenarios()` |
| `point_query` | `Sources/ViewportBenchmarks/PointQueryBenchmark.swift` | `pointQueryScenarios()` |
| `point_geometry_query` | `Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift` | `pointGeometryQueryScenarios()` |

The literals use Swift digit separators (`1_400_000`); match the file's existing style. Example — if the diff moved `point_geometry_query|prefixsum_100k` from `730 1500` to `770 1600`, the only edit in `PointGeometryQueryBenchmark.swift` is:

```swift
        PointGeometryQueryScenario(name: "prefixsum_100k", providerName: "prefixsum",
                                   lineCount: 100_000, useVariableHeights: true,
                                   p95BudgetNanoseconds: 770, p99BudgetNanoseconds: 1_600),
```

Do **not** update the "derived from … re-derive" comment blocks above the tables to quote new numbers: a comment that restates a measured value is falsified by the next re-derivation. They already point at the script and the corpus, which is the durable form.

- [ ] **Step 6: Prove all 46 reproduce, no workload moved, and the floor holds**

```bash
cd /Users/aabanschikov/swift-text-engine
C=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
swift build -c release
for m in --gate --realistic-provider --variable-height --variable-height-mutation \
         --structural-mutation --bulk-structural-mutation --line-query --line-geometry-query \
         --column-query --column-geometry-query --point-query --point-geometry-query; do
  swift run -c release ViewportBenchmarks -- "$m" --gate
done > /tmp/gate-sweep-after.txt

# 1. Every committed budget is the recipe's output (AC6).
awk '{ delete v; for (i=1;i<=NF;i++) { n=split($i,p,"="); if (n==2) v[p[1]]=p[2] }
       if (v["budget_p95_ns"] != "") printf "%s|%s %s %s\n", v["mode"], v["scenario"], v["budget_p95_ns"], v["budget_p99_ns"] }' \
  /tmp/gate-sweep-after.txt | sort > /tmp/committed-budgets-after.txt
diff /tmp/committed-budgets-after.txt /tmp/derived-after.txt && echo "ALL 46 BUDGETS REPRODUCE"

# 2. No measured path moved: checksums byte-identical across the whole sweep (AC8).
for f in before after; do
  grep -oE 'mode=[a-z_]+ .*scenario=[a-z0-9_]+.*checksum=[0-9-]+' "/tmp/gate-sweep-$f.txt" \
  | sed -E 's/.*mode=([a-z_]+).*scenario=([a-z0-9_]+).*checksum=([0-9-]+)/\1|\2 \3/' \
  | sort > "/tmp/checksums-$f.txt"
done
diff /tmp/checksums-before.txt /tmp/checksums-after.txt && echo "CHECKSUMS IDENTICAL"

# 3. Every gate still passes locally, and the floor test re-reads the new corpus.
grep -c 'gate=pass' /tmp/gate-sweep-after.txt   # expect 46
grep -c 'gate=fail' /tmp/gate-sweep-after.txt   # expect 0
swift test 2>&1 | grep -E "Executed [0-9]+ tests"

# 4. The core and providers did not move.
git diff --name-only main -- Sources/TextEngineCore Sources/TextEngineReferenceProviders | wc -l
```

Expected: `ALL 46 BUDGETS REPRODUCE`; `CHECKSUMS IDENTICAL`; `46` / `0`; `Executed 296 tests, with 0 failures`; `0`.

If `GateFloorTests` fails here, it is **`budget_stale`, not an engine regression**: the new samples raised a floor under a budget Step 5 did not move. Re-run Step 4's diff and apply what it says — do not go hunting for a slowdown in the core, and do not touch `floorFactor`.

If a checksum moved, a benchmark **workload** changed — revert and find the edit that did it.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv Sources/ViewportBenchmarks/
git commit -m "$(cat <<'EOF'
feat: harvest fresh hosted samples and re-derive every budget they move

A harvest re-derives every mode, not the one the slice came for: each hosted run
measures all the gated modes, so appending one moves max(hosted) -- and can move
the median -- for scenarios this slice never touched. Deriving only
point_geometry_query would leave the others silently not reproducing from the
committed corpus.

The append and the re-derivation are one commit on purpose: GateFloorTests reads
the COMMITTED corpus, and six budgets sit within ~5% of their 3x floor, so an
append-only commit would redden a blocking CI step.

The corpus gains run 29426572267 -- the Slice 39 post-merge push run, and
point_geometry_query's first sample that is not from the Slice 39 PR head.

All 46 budgets reproduce byte-for-byte from derive-gate-budgets.sh; every gate
checksum is byte-identical, so no measured path moved.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Graduate `AGENTS.md` to eleven blocking gates

Spec §Documentation. This deletes the two-step description and the Slice-16-trap sentences whose durable halves Task 1 already relocated.

**Files:**
- Modify: `AGENTS.md` — architecture paragraph (~lines 102-106), CI section (~lines 196-215), Commands (~line 153), Package layout (~lines 119-130)

**Interfaces:**
- Consumes: the collapsed workflow (Task 2) and the new test file name `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` (Task 2).
- Produces: `AGENTS.md` describing `--point-geometry-query` as the eleventh blocking host-job gate, with no surviving two-step / not-yet-blocking claim.

- [ ] **Step 1: Assert the "before" state**

```bash
cd /Users/aabanschikov/swift-text-engine
rg -n "gateable, not yet blocking|two steps|observational on latency|Slice 40 promotes|Ten blocking gates" AGENTS.md
```

Expected: **5 matches** — lines ~102, ~104, ~153, ~203, ~212. These are the claims this task falsifies.

- [ ] **Step 2: Rewrite the architecture paragraph**

In `AGENTS.md`, the `pointGeometryAt` paragraph currently ends with these five lines (~102-106):

```text
`--point-geometry-query` is derived-budget gateable, and CI runs it as **two steps**:
a bare run that is **blocking on correctness**, then a `--gate` run under
`continue-on-error` that is **observational on latency, not yet a blocking gate**
(promotion is Slice 40, which deletes both halves at once). One step cannot be both:
`continue-on-error` swallows every non-zero exit, budget and correctness alike.
```

Replace all five with one line, mirroring how the adjacent `columnGeometryAt` and `pointAt` sentences read:

```text
`--point-geometry-query --gate` is its blocking host-job CI gate (the eleventh).
```

- [ ] **Step 3: Rewrite the CI section's gate chain and count**

In the `- **Host tests and benchmark gate**` bullet, the wiring and the trailing rationale currently read (~196-214):

```text
  → `--column-geometry-query --gate` (blocking) → `--point-query --gate`
  (blocking) → `--point-geometry-query` bare (blocking on **correctness**) →
  `--point-geometry-query --gate` (`continue-on-error`, observational on
  latency) →
  `--memory-shape`
  → `--memory-observation` → realistic relative
  observation (PR-only,
  `continue-on-error`). Ten blocking gates: synthetic, static variable-height,
  mutation variable-height, structural-mutation, bulk-structural-mutation,
  line-query, line-geometry-query, column-query, column-geometry-query, and
  point-query — all **fail the job on perf regression**. Point-geometry-query is
  split in two on purpose: `continue-on-error` swallows *every* non-zero exit, so
  a lone gated step under it would also swallow `failureCount != 0` and crashes —
  the Slice 16 dead-step trap. The bare step keeps correctness blocking and its
  summary lines **out of the log** (the harvester reads every `p95_ns=` line in a
  run, so a second printing step would double-weight that run in `median()`).
  Slice 40 promotes the mode by deleting the bare step and the
  `continue-on-error` together.
  Budget calibration is not restated here — see `## Gate budgets` below. SwiftPM
```

Replace that region with:

```text
  → `--column-geometry-query --gate` (blocking) → `--point-query --gate`
  (blocking) → `--point-geometry-query --gate` (blocking) →
  `--memory-shape`
  → `--memory-observation` → realistic relative
  observation (PR-only,
  `continue-on-error`). Eleven blocking gates: synthetic, static variable-height,
  mutation variable-height, structural-mutation, bulk-structural-mutation,
  line-query, line-geometry-query, column-query, column-geometry-query,
  point-query, and point-geometry-query — all **fail the job on perf
  regression**.
  Budget calibration is not restated here — see `## Gate budgets` below. SwiftPM
```

The two lessons that block goes to die with it are already re-stated, mode-independently, by Task 1: the Slice 16 dead-step trap in `## CI` and the one-printing-step rule in `## Gate budgets`. Do not re-attach either to point-geometry-query here.

- [ ] **Step 4: Update the Commands block**

Replace line ~153:

```text
swift run -c release ViewportBenchmarks -- --point-geometry-query --gate   # (x,y)->(line+box+fraction, cell+box+fraction); gateable, not yet blocking in CI
```

with:

```text
swift run -c release ViewportBenchmarks -- --point-geometry-query --gate   # (x,y)->(line+box+fraction, cell+box+fraction) 2D geometry blocking CI gate
```

- [ ] **Step 5: Add `WorkflowShapeTests.swift` to the Package layout description**

In the `- \`Tests/ViewportBenchmarksTests\`` bullet, after the sentence ending `…a gateable mode with no scenarios registered fails, and so does the reverse.`, append:

```text
  `WorkflowShapeTests.swift` is the third guard: it reads
  `.github/workflows/swift-ci.yml` and pins the point-geometry-query gate step's
  shape — exactly one step carries the flag, it passes `--gate`, it is not
  `continue-on-error`, it carries the docs-only guard, it is named
  `Run point geometry query benchmark gate`, and it sits between the point-query
  gate and the memory-shape diagnostic. There is no YAML parser in reach (the
  package is zero-dependency and Foundation ships none), so it hand-rolls a
  narrow reader and compares whitespace-separated **tokens**, never substrings —
  `--variable-height` is a prefix of `--variable-height-mutation`.
```

- [ ] **Step 6: Assert the "after" state (AC9)**

```bash
cd /Users/aabanschikov/swift-text-engine
rg -n "gateable, not yet blocking|two steps|observational on latency|Slice 40 promotes|Ten blocking gates" AGENTS.md \
  && echo "STALE CLAIM SURVIVES — FAIL" || echo "no stale two-step/not-yet-blocking claim OK"
rg -n "Eleven blocking gates" AGENTS.md
rg -n "point-geometry-query --gate\` is its blocking host-job CI gate" AGENTS.md
rg -n "point-query, and point-geometry-query" AGENTS.md
rg -n "WorkflowShapeTests.swift" AGENTS.md
# The Task 1 relocations must still be standing:
rg -c "Exactly one CI step may print" AGENTS.md
rg -c "A \`continue-on-error\` step cannot be a gate" AGENTS.md
```

Expected: `no stale two-step/not-yet-blocking claim OK`; one match for each of the next four; `1` and `1` for the two relocated rules.

- [ ] **Step 7: Confirm scope and commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git diff --name-only   # expect only AGENTS.md
swift test 2>&1 | grep -E "Executed [0-9]+ tests"   # expect 296 tests, 0 failures
git add AGENTS.md
git commit -m "$(cat <<'EOF'
docs: describe point-geometry-query as the eleventh blocking CI gate

Drop the two-step / not-yet-blocking wiring from the architecture paragraph and
the CI section, take the blocking-gate count from ten to eleven, drop the
"gateable, not yet blocking in CI" qualifier from the Commands block, and add
WorkflowShapeTests.swift as the third guard in the ViewportBenchmarksTests
description.

The two durable lessons the deleted text carried -- one printing step per mode,
and a continue-on-error step cannot be a gate -- were re-stated
mode-independently before this deletion, not with it.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Verification record (hosted proof left Pending)

**Files:**
- Create: `docs/superpowers/verification/2026-07-16-point-geometry-query-ci-gate-promotion.md`

**Interfaces:**
- Consumes: `/tmp/workflow-shape-red.txt` (Task 2 Step 2), `/tmp/derive-before.txt` and `/tmp/derive-after.txt` (Task 3), `/tmp/gate-sweep-after.txt`, `/tmp/checksums-{before,after}.txt`.
- Produces: a verification record with local evidence and an explicit `## Hosted Proof — Pending` placeholder that Task 6 fills post-merge.

- [ ] **Step 1: Re-run the full local evidence suite and capture it**

```bash
cd /Users/aabanschikov/swift-text-engine
C=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
swift test 2>&1 | tail -6
swift build -c release
for m in --gate --realistic-provider --variable-height --variable-height-mutation \
         --structural-mutation --bulk-structural-mutation --line-query --line-geometry-query \
         --column-query --column-geometry-query --point-query --point-geometry-query; do
  swift run -c release ViewportBenchmarks -- "$m" --gate
done
swift run -c release ViewportBenchmarks -- --memory-shape
rg -n "Foundation" Sources/TextEngineCore ; echo "core scan exit=$?"
rg -n "Foundation" Sources/TextEngineReferenceProviders ; echo "provider scan exit=$?"
./.github/scripts/cross-target-compile.sh --self-test
./.github/scripts/harvest-gate-corpus.sh --self-test
./.github/scripts/derive-gate-budgets.sh "$C" | tail -20
git diff --check
git diff --name-only main
```

Expected: `Executed 296 tests, with 0 failures` (plus the empty Swift Testing harness line, which is not a failure); 46 `gate=pass`, `failures=0`; `invariant=pass`; both Foundation scans silent with `exit=1`; `self_test=pass` from both scripts; `git diff --check` clean; and `git diff --name-only main` listing **only** `.github/workflows/swift-ci.yml`, `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`, the corpus TSV, whichever `Sources/ViewportBenchmarks/*.swift` budget tables moved, `AGENTS.md`, and `docs/**` (AC8).

- [ ] **Step 2: Write the record**

Create `docs/superpowers/verification/2026-07-16-point-geometry-query-ci-gate-promotion.md` containing, as raw command output rather than prose:

1. **The workflow-shape test's red-before state** — `/tmp/workflow-shape-red.txt` verbatim: the four failing tests and their assertion messages, above all `2 steps run --point-geometry-query, want exactly 1` and `carries continue-on-error: true`. AC3 requires this; it is what proves the test is a genuine anchor rather than a tautology written after the fact. State explicitly that `testThePointGeometryStepCarriesTheDocsOnlyGuard` and the ordering test passed in both states, and why (both pre-collapse steps already carried the guard and already sat between the anchors).
2. **The green-after state** — `Executed 6 tests, with 0 failures`, and the six invariants named.
3. **Workflow text proof** — `grep -c -- '--point-geometry-query'` → 1; `'--point-geometry-query --gate'` → 1; `continue-on-error` → 1 (realistic-provider only); `rg "observational|Slice 40|correctness" .github/workflows/swift-ci.yml` → no match (AC1, AC2).
4. **Corpus provenance (AC5)** — rows and distinct runs before → after; the append-only prefix diff; `grep -c '^29426572267'` non-zero; and **`point_geometry_query`'s post-harvest run count**, which Decision 5 and the Risks section key on.
5. **The derivation sweep (AC6)** — `derive-gate-budgets.sh <corpus>` output for all **46** scenarios verbatim, the committed→derived diff (empty: `ALL 46 BUDGETS REPRODUCE`), and a table of every budget the harvest moved with its **direction**, stating that none was hand-edited. If nothing moved, say so explicitly — that is a result, not an omission.
6. **`point_geometry_query`'s post-harvest evidence base** — per scenario: run count, budget, `3×max` floor margin, and tightest hosted headroom. Compare against the pre-harvest figures (tightest 3.16× p95 on `prefixsum_100k`; +5.34% over its floor). Carry the residual risk knowingly if the mode is still under ~10 runs.
7. **Local gates (AC10)** — all eleven CI gates `gate=pass` (46 of 46 gated scenarios including `realistic_provider`, which CI never runs with `--gate`), `--point-geometry-query --gate` `gate=pass` ×4 with per-scenario headroom, and the four checksums byte-identical to Slice 39's: `4687694617200924928`, `6036755761047907072`, `1712152282485110528`, `5915921755926273280`.
8. **Checksum identity across the whole sweep** — `CHECKSUMS IDENTICAL` (no measured path moved).
9. **`swift test`** — 290 → **296**, 0 failures.
10. **Foundation scans** — empty for both `Sources/TextEngineCore` and `Sources/TextEngineReferenceProviders`; `Sources/ViewportBenchmarks` still imports none.
11. **Scope proof (AC7, AC8)** — `git diff --name-only main`; the three required job context names unchanged; no core/provider/workload change.
12. **The Decision 2 relocation proof (AC4)** — both rules present in `AGENTS.md` as mode-independent prose, quoted, with the grep showing neither is phrased in terms of point-geometry-query and neither depends on the deleted text.
13. A final section literally titled `## Hosted Proof — Pending`, stating that the PR-head and post-merge push run IDs are recorded in the post-merge follow-up once the head SHA is stable (the project's clean-evidence convention — never record a run ID against a still-moving head). Name the watch scenario: `point_geometry_query|prefixsum_100k`, the tightest of this mode's four.

- [ ] **Step 3: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add docs/superpowers/verification/2026-07-16-point-geometry-query-ci-gate-promotion.md
git commit -m "$(cat <<'EOF'
docs: record slice 40 local verification

The eleventh blocking gate: WorkflowShapeTests red-before (4 of 6 failing, with
the assertion messages) and green-after, the collapsed workflow proved by grep,
the corpus append proved a byte-exact prefix, all 46 budgets reproducing from
derive-gate-budgets.sh, every gate checksum byte-identical, and both relocated
rules standing. Hosted proof left as an explicit Pending placeholder.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Open the PR, confirm hosted green at step level, record the post-merge proof

The hosted-evidence half. Follow the project's `superpowers:finishing-a-development-branch` flow.

- [ ] **Step 1: Push the branch**

```bash
cd /Users/aabanschikov/swift-text-engine
git push -u origin slice-40-point-geometry-query-ci-gate-promotion
```

- [ ] **Step 2: Open the PR**

Open a PR against `main` titled *"Slice 40: promote --point-geometry-query to the eleventh blocking CI gate"*. Body: eleventh blocking latency gate; bare promotion (no ratchet repair — that is Slice 41); two CI steps collapsed into one; `WorkflowShapeTests` guards the shape; fresh harvest re-derived all 46 budgets; benchmark workload unchanged (Slice 39 checksums byte-identical). Reference `docs/superpowers/specs/2026-07-16-point-geometry-query-ci-gate-promotion-design.md`.

This PR changes workflow YAML, so it is never docs-only and runs the full heavy path in all three required jobs.

- [ ] **Step 3: Confirm the hosted PR-head run at STEP level**

A green job can hide a dead `continue-on-error` step — read step conclusions and logs, not the job conclusion.

```bash
cd /Users/aabanschikov/swift-text-engine
gh pr checks
gh run list --branch slice-40-point-geometry-query-ci-gate-promotion --limit 1 --json databaseId --jq '.[0].databaseId'
gh run view <run-id> --log | grep -oE 'mode=[a-z_]+ .*headroom_p95=[0-9.]+x .*gate=[a-z]+.*' | sort
gh run view <run-id> --log | grep -c 'mode=point_geometry_query'
```

Verify:

- all three required jobs `success` (`Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`);
- the step `Run point geometry query benchmark gate` = `success`, with four hosted `gate=pass` rows; record per-scenario hosted p95/p99 and headroom, especially `prefixsum_100k`;
- `grep -c 'mode=point_geometry_query'` returns **4**, not 8 — one printing step, so the next harvest of this run cannot double-weight it;
- the step is **not** `continue-on-error` (the workflow carries exactly one, on the realistic-provider observation);
- `Run host tests` = `success` with `Executed 296 tests, with 0 failures` — the workflow-shape test runs on hosted Linux too.

**If the gate step fails on budget:** apply Decision 5 — re-derive from that fresh hosted evidence in this same PR (append the run to the corpus with `harvest-gate-corpus.sh --runs <run-id> --corpus <corpus>`, re-run the Task 3 Step 4 sweep, apply what it says). Do **not** restore `continue-on-error`, add a workflow-only threshold, or hand-widen a budget.

- [ ] **Step 4: Merge, then record the hosted proof in a post-merge follow-up**

After merge, capture the **post-merge push run** on the merge commit (event `push`, branch `main`) at step level: all three required jobs `success`; `Run point geometry query benchmark gate` = `success` with four `gate=pass`; the realistic-observation step correctly `skipped` on a push event. This PR changes YAML, so the merge is **not** docs-only and runs the full heavy path — that run is the merged-code anchor.

Then open a small follow-up PR that fills the verification doc's `## Hosted Proof — Pending` section with the real PR-head run ID and the post-merge push run ID. That follow-up touches only verification Markdown, so it legitimately takes the trusted docs-only path.

---

## Self-Review

**1. Spec coverage.** Every spec section maps to a task:

| Spec | Task |
| --- | --- |
| Decision 1 (collapse both halves together; step name; position) | Task 2 Steps 3, 5 |
| Decision 2 (relocate both durable rules first) | Task 1 (rules added) + Tasks 2/4 (copies deleted after) |
| Decision 3 (re-derive every mode; no exempt set; either direction) | Task 3 Steps 4-5 |
| Decision 4 (job order; required contexts unchanged) | Task 2 Step 3 + Global Constraints + Task 6 Step 3 |
| Decision 5 (first-run miss → re-derive in-PR) | Global Constraints + Task 6 Step 3 |
| Decision 6 (workflow-shape guard, all six invariants, parsing contract, one mode only) | Task 2 Step 1 |
| §Implementation Architecture → Harvest + re-derive | Task 3 |
| §Implementation Architecture → Documentation (`AGENTS.md`, 5 sites) | Task 1 (2 additions) + Task 4 (4 sites) |
| §Implementation Architecture → Verification record | Task 5 |
| AC1, AC2 | Task 2 Steps 3, 5 |
| AC3 | Task 2 Steps 1, 2, 4 + Task 5 Step 2 item 1 |
| AC4 | Task 1 + Task 4 Step 6 + Task 5 Step 2 item 12 |
| AC5 | Task 3 Steps 2, 3 |
| AC6 | Task 3 Steps 1, 4, 6 |
| AC7 | Global Constraints + Task 6 Step 3 |
| AC8 | Global Constraints + Task 3 Step 6 + Task 5 Step 1 |
| AC9 | Task 4 Steps 1, 6 |
| AC10 | Task 3 Step 6 + Task 5 Step 1 |
| AC11 | Task 6 Steps 3, 4 |
| Non-Goals (no core/provider/workload/ratchet/corpus-rewrite/harvester change) | Global Constraints + the `git diff --name-only` and checksum checks in Tasks 2, 3, 5 |

**2. Placeholder scan.** No "TBD" / "handle edge cases" / "similar to Task N". The one literal placeholder is the verification doc's `## Hosted Proof — Pending`, which is the project's required clean-evidence convention (Slices 31/33/35/37), filled by Task 6 Step 4. `<run-id>` in Task 6 is substituted from the `gh run list` command immediately above it. Task 3 Step 5 shows the edit shape with a worked example rather than a fixed budget table, because the budgets that move are not knowable until the harvest runs — the diff in Step 4 *is* the list, and hand-copying a table is the practice the recipe exists to end.

**3. Type/name consistency.** The step name `Run point geometry query benchmark gate` is identical in the YAML (Task 2 Step 3), the test constant `pointGeometryStepName` (Task 2 Step 1), the greps (Task 2 Step 5), `AGENTS.md` (Task 4 Step 5), and Task 6's step-level checks. The flag `--point-geometry-query --gate` is identical everywhere. The four checksums are identical in the Global Constraints, Task 2 Step 6, and Task 5 Step 2 item 7. Test counts chain: 290 (baseline) → 296 (Task 2 Step 6, Task 4 Step 7, Task 5, Task 6 Step 3). The parser helpers (`indentation(of:)`, `isBlank(_:)`, `isComment(_:)`, `value(of:in:)`, `parseStep(_:index:)`, `hostJobSteps()`, `stepNamed(_:in:)`) are each defined once and used consistently; `repositoryRoot()` is `private` at file scope, so it does not collide with its twin in `GateFloorTests.swift`.

**4. Executed, not assumed.** Before this plan was written, against this branch at HEAD on 2026-07-17: the parser above was run as a standalone Swift script against the real `swift-ci.yml` (20 host-job steps; **2** carry the flag; `continue-on-error` correctly read as `nil` for the point-query gate despite the rationale comment inside its block naming `continue-on-error` twice; `--variable-height` correctly matched only the variable-height gate) and against a scratchpad copy with the collapse applied (**1** step, named, `continue-on-error` nil, `--gate` present, index 15 between 14 and 16). The Task 3 Step 1 pipeline was run and printed `46`, `46`, `ALL 46 BUDGETS REPRODUCE`, `46 gate=pass / 0 gate=fail`. `swift test` printed `Executed 290 tests, with 0 failures`. The four checksums were read off a live gate run. Every `AGENTS.md` and `swift-ci.yml` line reference in the spec was checked and holds.

---

## Spec gaps found while planning

> **Status: all six confirmed and folded into the spec** (design commit following
> this plan). Each "Resolution taken (confirm or correct)" below is now the spec's
> own text, so the plan and the design agree; the section stays as the record of
> why. Independently re-verified before folding: `swift-ci.yml` defines 3 jobs (20
> host-job steps vs 30 file-wide) and all four shared step names occur exactly 3×;
> `Tests/ViewportBenchmarksTests/` holds 4 files, so the new test is the 5th but the
> 3rd *described* guard; and run `29426572267` **is** inside the `--limit 40` window
> as of 2026-07-17 (window `29430079405` … `29111247857`) — the `--dry-run` assertion
> is kept because nothing pins it there.

Six issues, all found by checking the spec's concrete claims against the repo. **Every one of the spec's file, line, commit, and corpus-statistic claims that could be verified, verified** — `swift-ci.yml:130-143/144-154/156-159/86-88/90-92/96/100/148/159`, `AGENTS.md:94-106/105-106/119-130/153/197-213/206-213/207-209/292-297/329-333/340`, commits `5042747` and `a23e559`, "1,691 data rows from 42 distinct runs", "per-key run counts range 6 → 42", "`realistic_provider` … 232 rows from 29 runs", "all 46 committed gated budgets … reproduce byte-for-byte … at HEAD", "3.16× p95 (run `29280327104`: 231 ns vs 730)", "next-tightest 3.24× on run `29285933609`", "+5.34% above its `3×max` floor (730 vs 693)", "median-governed (8 × 91 = 728 > 3 × 231 = 693)", "`line_geometry_query|uniform_1k` p99 at 0.0% margin", "five pre-existing statistics tighter still (3.00×–3.04×)", "6th-tightest of the 92 gated statistics", and "`29285933609` — the newest run in the entire corpus". The gaps below are the residue.

### 1. Decision 6's parsing contract does not say how to find "the job" — and step names are not unique across jobs

**Spec section:** Decision 6, "Parsing contract" — *"split the job's steps on lines matching `^      - name:`"*.

**What is unclear:** which lines constitute "the job". `swift-ci.yml` has **three** jobs, and all three indent their steps identically at `      - name:`. Four step names repeat verbatim across all three (`Check out repository`, `Detect PR change scope`, `Complete docs-only PR`, `Show toolchain`), so a whole-file split makes every name-based lookup — including Decision 6's own ordering anchors — ambiguous by construction.

**Evidence:** `.github/workflows/swift-ci.yml:27,32,73,77` (host job), `:217,222,263,267` (iOS job), `:288,293,334,338` (WASM job). `grep -c '^      - name:'` over the whole file returns **30** steps against the host job's 20, and each of the four names above occurs **3** times — once per job.

**Resolution taken (confirm or correct):** the plan scopes to the host job's own region first — from the line `  host-tests-and-benchmark-gate:` to the next non-blank, non-comment line at indent ≤ 2 — and splits on `^      - name:` **within** that region. This satisfies the contract's letter, matches "the job's steps", and was verified to return exactly the host job's 20 steps. It does not change any answer for `--point-geometry-query` today (the token appears only in the host job), so this is a robustness decision, not a correctness one.

### 2. Decision 6's "carries the sibling `docs_only_pr` guard" is ambiguous, and one reading conflicts with AC3

**Spec section:** Decision 6 bullet 4 vs. Acceptance Criterion 3.

**What is unclear:** "the sibling guard" can mean (a) *equal to a sibling step's `if:`* — the shape the Slice 36 promotion's workflow check used (`cgq["if"] == cq["if"]`, `docs/superpowers/plans/2026-07-10-column-geometry-query-ci-gate-promotion.md:56`) — or (b) *equal to the literal guard expression every sibling carries*. Reading (a) makes this test's red/green state depend on the point-query gate step's `if:`, which contradicts AC3's *"It implicates no other mode in either state."*

**Evidence:** `.github/workflows/swift-ci.yml:127` (`if: steps.change-scope.outputs.docs_only_pr != 'true'`, the point-query gate) vs. the design spec's AC3.

**Resolution taken (confirm or correct):** reading (b) — the plan asserts the literal `steps.change-scope.outputs.docs_only_pr != 'true'`, so no other step can turn the test red or green. Note this also means AC3's *"implicates no other mode"* is not strictly achievable for **invariant 6**: the ordering assertion must look up the point-query gate and memory-shape steps by name, which Decision 6 mandates. The plan reads AC3 as being about *modes being asserted about*, not about ordering anchors. If that reading is wrong, invariant 6 and AC1's ordering clause need re-specifying.

### 3. `--limit 40` is not guaranteed to reach run `29426572267`, which AC5 makes mandatory

**Spec section:** §Implementation Architecture ("Harvest + re-derive", which hard-codes `--limit 40`) vs. Acceptance Criterion 5 (*"the appended rows **include run `29426572267`**"*).

**What is wrong:** `harvest-gate-corpus.sh` with no `--runs` calls `gh run list --workflow swift-ci.yml --limit "$limit"`, i.e. the **40 most recent** runs of that workflow. The corpus already carries **42** distinct runs, and every push to this slice's branch adds another. Nothing guarantees a 40-run window still reaches back to `29426572267` (merged 2026-07-15). The spec asserts the requirement and pins a limit that may not satisfy it, and says nothing about what to do if it does not.

**Evidence:** `.github/scripts/harvest-gate-corpus.sh:142-146`; corpus distinct-run count = 42; `grep -c '^29426572267' <corpus>` → 0. Unverifiable further without network, which this planning pass deliberately did not use.

**Resolution taken (confirm or correct):** Task 3 Step 2 runs `--dry-run` first and **asserts** `plan=harvest run=29426572267` appears, widening `--limit` until it does. A `--runs 29426572267` fallback is explicitly rejected in the plan: it would harvest one run and silently skip every other unharvested one, contradicting Decision 3's "re-derive every mode from the fresh harvest".

### 4. The spec does not say the corpus append and the re-derivation must be one commit — and they must be

**Spec section:** §Scope bullets 1 and 2; §Implementation Architecture shows two separate commands.

**What is under-specified:** `GateFloorTests` reads the **committed** corpus on every `swift test`, and `swift test` is a blocking CI step (`swift-ci.yml:86-88`). The spec's own Risks section records six budgets within ~5% of their `3×max` floor, one at **0.0%**. So a commit that appends rows without re-deriving in the same commit can leave the tree red — the "post-harvest `GateFloorTests` failure is `budget_stale`" case `AGENTS.md` already describes. Slice 39 landed them together (`a23e559`, *"harvest gate corpus and re-derive every budget it moves"*), but the spec never states the constraint.

**Evidence:** `Tests/ViewportBenchmarksTests/GateFloorTests.swift:17,156-191`; `AGENTS.md:323-327`; `.github/workflows/swift-ci.yml:86-88`; `git log --oneline -1 a23e559`.

**Resolution taken (confirm or correct):** Task 3 makes the append + re-derive a single commit.

### 5. The spec cites a Slice 39 post-slice review that is not in this branch or `main`

**Spec section:** §Source Context — *"following the Slice 39 post-slice review: `docs/superpowers/reviews/2026-07-15-slice-39-post-slice-review.md`"*, and §Provenance, which leans on that review's Option A and on Slice 38's P2 #2.

**What is wrong:** the file does not exist on this branch or on `main`. It exists only on the unmerged branch `slice-39-post-slice-review` (commit `dc29e14`). An implementer following the spec's own provenance pointer finds nothing; `docs/superpowers/reviews/` stops at `2026-07-12-slice-38-post-slice-review.md`.

**Evidence:** `ls docs/superpowers/reviews/` → newest is Slice 38; `git log --all --oneline --diff-filter=A -- 'docs/superpowers/reviews/*slice-39*'` → `dc29e14`; `git branch -a --contains dc29e14` → `slice-39-post-slice-review` only.

**Decision needed:** none that blocks implementation — the spec is self-sufficient on the work itself. But the slice's paper trail cites a document that is not in the tree it ships to. Either merge that review branch, or note in the spec that the review lives on an unmerged branch.

### 6. "the third guard" is true of `AGENTS.md`'s description but not of the directory

**Spec section:** §Implementation Architecture → Documentation → Package layout — *"add `WorkflowShapeTests.swift` beside `GateLogicTests.swift` / `GateFloorTests.swift` as the third guard in the `Tests/ViewportBenchmarksTests` description"*.

**What is wrong:** `Tests/ViewportBenchmarksTests/` already contains **four** files — `GateFloorTests.swift`, `GateLogicTests.swift`, `PointGeometryChecksumTests.swift`, `PointGeometryQueryOptionsTests.swift` — so the new file is the fifth. The phrasing is accurate only because `AGENTS.md:119-130` describes just the two `Gate*` files and silently omits the two Slice 39 test files.

**Evidence:** `ls Tests/ViewportBenchmarksTests/`; `AGENTS.md:119-130`.

**Resolution taken (confirm or correct):** the plan implements the spec literally — `WorkflowShapeTests.swift` is added as the third *described* guard — and does **not** fold in a fix for the pre-existing omission, since documenting Slice 39's two test files is outside this slice's scope. Flagged so it is a known omission rather than a silent one; a candidate for the Slice 40 post-slice review.
