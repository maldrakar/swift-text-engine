# Slice 56 — Artifact-Shape Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make six repository artifacts whose shape nothing verifies verifiable — all twelve blocking gate steps, plan documents, the debt ledger — and rewrite the one convention that recommends an idiom which inverts a failed assertion into a pass.

**Architecture:** Three new guards and one rewritten convention. A `flagName` property turns `BenchmarkMode` into the registry the workflow pin needs, so `pinnedGateSteps` grows from two hand-written rows to all twelve, checked against `isGateable` as a bijection and against the file as a total order. A new bash linter (`lint-plan-assertions.sh`) checks the syntactic half of the plan-assertion conventions and is run both standalone while authoring and from `swift test`; a Swift test pins its exemption ratchet. A Swift test pins the ledger's table shape. Nothing measured moves.

**Tech Stack:** Swift 6.0 (`swift-tools-version`), XCTest, bash (`#!/usr/bin/env bash`), awk, GitHub Actions.

**Spec:** [`docs/superpowers/specs/2026-09-04-artifact-shape-enforcement-design.md`](../specs/2026-09-04-artifact-shape-enforcement-design.md)

## Global Constraints

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must stay empty. This slice touches no core source, but the scan is part of every verification.
- **Zero third-party dependencies.** No YAML parser, no Markdown parser, no test framework beyond XCTest. Every reader in this slice is hand-rolled and narrow, matching `WorkflowShapeTests`' existing reader.
- **Nothing measured moves.** The 46 gated scenario checksums must be byte-identical; no `p95BudgetNanoseconds` / `p99BudgetNanoseconds` literal changes; `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` is untouched; the three required-check job names are unchanged.
- **Scratch directory.** Every command block that needs scratch space assigns `SCRATCH` **in that same block**. Each Bash invocation is a fresh shell.
- **This plan's own assertions obey the conventions this slice writes.** No `${PIPESTATUS[0]}` in any command block (agent shells here are zsh, where it expands empty and `[ "" -eq 0 ]` evaluates **true**, inverting a failed check into a pass). Assert with `if ! cmd > /dev/null 2>&1; then … else … fi`, with `[ -z "$(…)" ]`, or by redirecting to a file and reading `$?` on the next line. Never `echo "…=$?"` after `git diff --name-only`, `git status`, `gh`, `jq`, `sed -i`, or a pipeline.
- **This plan is the first non-exempt plan.** Task 4's exemption list holds exactly the 56 plans that existed before it. From Task 5 onward, `swift test` lints *this file*, so every task's own structure must satisfy R4.

## File Structure

**Created:**

- `.github/scripts/lint-plan-assertions.sh` — the plan linter. Owns the four rules, the fence/heredoc scanner, and the single exemption array. Has `--self-test` (its own known-bad fixtures) and `--list-exempt` (the seam the Swift ratchet reads).
- `Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift` — the `flagName` ↔ `BenchmarkOptions.parse` round trip.
- `Tests/ViewportBenchmarksTests/DebtLedgerShapeTests.swift` — the ledger's table shape.
- `Tests/ViewportBenchmarksTests/PlanLintTests.swift` — runs the linter over the repository; pins the exemption ratchet.

**Modified:**

- `Sources/ViewportBenchmarks/BenchmarkOptions.swift` — add `BenchmarkMode.flagName`.
- `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` — `pinnedGateSteps` becomes twelve rows keyed by mode; identification switches from flag token to payload equality; four new invariants.
- `Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift` — enroll the new script.
- `.github/workflows/swift-ci.yml` — add the lint step.
- `AGENTS.md` — rewrite D-2 rule 1; add the guarantee-inventory convention; add three record-writing lines; list the new script.
- `docs/superpowers/debt-ledger.md` — discharge rows; append new ones.

---

### Task 1: `flagName`, pinned to `parse`

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (add a property after `isGateable`, which ends at line 98)
- Test: `Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift` (create)

**Interfaces:**
- Consumes: `BenchmarkMode` (enum, `CaseIterable`), `BenchmarkMode.isGateable`, `BenchmarkOptions.parse(_ arguments: [String]) -> BenchmarkOptionParse`, whose cases are `.run(BenchmarkOptions)`, `.failure(String)`, `.help`.
- Produces: `BenchmarkMode.flagName: String?` — the CLI flag that selects the mode, `nil` for `.pipeline`. Task 2 reads it to build every expected gate command.

**Guarantees added:** G16, G17

- [ ] **Step 1: Write the failing test**

Create `Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift`:

```swift
import XCTest
@testable import ViewportBenchmarks

final class BenchmarkModeFlagNameTests: XCTestCase {
    // G16. flagName is the THIRD copy of every flag spelling (parse's case labels are the
    // first, swift-ci.yml's payloads the second). This pins copy three to copy one, in the
    // direction that matters: a flagName nobody can parse would make WorkflowShapeTests
    // demand a CI command the binary rejects, and the workflow pin alone cannot see that.
    func testEveryFlagNameRoundTripsThroughParse() {
        for mode in BenchmarkMode.allCases {
            guard let flag = mode.flagName else { continue }
            guard case let .run(options) = BenchmarkOptions.parse(["--", flag]) else {
                XCTFail("\(mode.outputName): parse rejected its own flagName \(flag)")
                continue
            }
            XCTAssertEqual(
                options.mode.outputName, mode.outputName,
                "\(flag) parsed to \(options.mode.outputName), want \(mode.outputName)")
        }
    }

    // G16, gate half. Every gateable mode's flag must also survive beside --gate, which is
    // the exact argument vector each CI step runs.
    func testEveryGateableFlagNameAcceptsTheGateFlag() {
        for mode in BenchmarkMode.allCases where mode.isGateable {
            guard let flag = mode.flagName else { continue }
            guard case let .run(options) = BenchmarkOptions.parse(["--", flag, "--gate"]) else {
                XCTFail("\(mode.outputName): parse rejected \(flag) --gate")
                continue
            }
            XCTAssertTrue(options.enforceGate, "\(flag) --gate did not enable the gate")
            XCTAssertEqual(options.mode.outputName, mode.outputName)
        }
    }

    // G17. `.pipeline`'s nil is a CLAIM about the CLI, not a comment: the default mode has
    // no flag, so a bare `-- --gate` must select it. Without this, `nil` could mean
    // "unspecified" and nothing would notice.
    func testPipelineHasNoFlagAndIsSelectedByABareGate() {
        XCTAssertNil(BenchmarkMode.pipeline.flagName)
        guard case let .run(options) = BenchmarkOptions.parse(["--", "--gate"]) else {
            return XCTFail("a bare -- --gate must select the default pipeline mode")
        }
        XCTAssertEqual(options.mode.outputName, "pipeline")
        XCTAssertTrue(options.enforceGate)
    }

    // Every mode except the default carries a flag. Stated as a test rather than trusted to
    // the switch: a future mode whose author returns nil "for now" would silently leave the
    // workflow pin unable to name its step.
    func testOnlyThePipelineModeLacksAFlagName() {
        let flagless = BenchmarkMode.allCases.filter { $0.flagName == nil }
        XCTAssertEqual(
            flagless.map(\.outputName), ["pipeline"],
            "only the default mode may have no flag; got \(flagless.map(\.outputName))")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
swift test --filter BenchmarkModeFlagNameTests 2>&1 | tail -20
```

Expected: compilation failure, `value of type 'BenchmarkMode' has no member 'flagName'`.

- [ ] **Step 3: Implement `flagName`**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, immediately after the closing brace of `isGateable`, insert:

```swift
    // The CLI flag that selects this mode, or nil for the default mode, which has no flag
    // at all and runs as a bare `--gate`. EXHAUSTIVE, never a deny-list -- the same
    // discipline as isGateable and absoluteCeiling: a `default` here hands the next mode a
    // flag spelling nobody chose, or hides it from the workflow pin that reads this
    // property.
    //
    // This is the THIRD copy of every flag spelling: BenchmarkOptions.parse's case labels
    // are the first, swift-ci.yml's step payloads the second. It is PINNED in both
    // directions rather than deleted -- BenchmarkModeFlagNameTests pins it to parse,
    // WorkflowShapeTests pins it to the workflow. Deriving parse's cases from this property
    // would delete the copy instead of pinning it and is the better fix; it rewrites every
    // per-flag "cannot be combined with another mode" message and its tests, which is
    // option-parsing surgery a slice whose fingerprint is "nothing measured moves" does not
    // do. See the debt ledger.
    var flagName: String? {
        switch self {
        case .pipeline:
            return nil
        case .rangeOnly:
            return "--range-only"
        case .realisticProvider:
            return "--realistic-provider"
        case .variableHeight:
            return "--variable-height"
        case .variableHeightMutation:
            return "--variable-height-mutation"
        case .structuralMutation:
            return "--structural-mutation"
        case .bulkStructuralMutation:
            return "--bulk-structural-mutation"
        case .lineQuery:
            return "--line-query"
        case .lineGeometryQuery:
            return "--line-geometry-query"
        case .columnQuery:
            return "--column-query"
        case .columnGeometryQuery:
            return "--column-geometry-query"
        case .pointQuery:
            return "--point-query"
        case .pointGeometryQuery:
            return "--point-geometry-query"
        case .memoryShape:
            return "--memory-shape"
        case .memoryObservation:
            return "--memory-observation"
        case .wrapCompute:
            return "--wrap-compute"
        case .wrapRowQuery:
            return "--wrap-row-query"
        case .wrapPointQuery:
            return "--wrap-point-query"
        }
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
swift test --filter BenchmarkModeFlagNameTests 2>&1 | tail -5
```

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Drill G16 — a `flagName` `parse` does not accept must redden**

Temporarily change `.lineQuery`'s return to `"--line-queries"`, run, then revert:

```bash
sed -i '' 's/return "--line-query"$/return "--line-queries"/' Sources/ViewportBenchmarks/BenchmarkOptions.swift
swift test --filter BenchmarkModeFlagNameTests > /tmp/slice56-drill-q.txt 2>&1
if grep -q "parse rejected its own flagName --line-queries" /tmp/slice56-drill-q.txt; then
  echo "drill_q=red_as_expected"
else
  echo "drill_q=DID_NOT_REDDEN — the round trip does not bind"
fi
sed -i '' 's/return "--line-queries"$/return "--line-query"/' Sources/ViewportBenchmarks/BenchmarkOptions.swift
```

Expected: `drill_q=red_as_expected`. Record the failure text in the verification record.

- [ ] **Step 6: Drill G17 — giving `.pipeline` a flag must redden**

```bash
sed -i '' 's/^        case .pipeline:\n            return nil/X/' Sources/ViewportBenchmarks/BenchmarkOptions.swift
```

That multi-line form does not work with `sed`; edit by hand instead: change `.pipeline`'s `return nil` to `return "--pipeline"`, then:

```bash
swift test --filter BenchmarkModeFlagNameTests > /tmp/slice56-drill-r.txt 2>&1
if grep -q "only the default mode may have no flag" /tmp/slice56-drill-r.txt; then
  echo "drill_r=red_as_expected"
else
  echo "drill_r=DID_NOT_REDDEN"
fi
```

Expected: `drill_r=red_as_expected`, from `testOnlyThePipelineModeLacksAFlagName` and from `testEveryFlagNameRoundTripsThroughParse` (parse has no `--pipeline` case). Revert the edit by hand and re-run to confirm green.

- [ ] **Step 7: Verify the whole suite and commit**

```bash
swift test > /tmp/slice56-t1-suite.txt 2>&1
tail -3 /tmp/slice56-t1-suite.txt
git add Sources/ViewportBenchmarks/BenchmarkOptions.swift Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift
git commit -m "feat: BenchmarkMode.flagName, pinned to BenchmarkOptions.parse

The workflow shape pin needs a mode -> flag mapping and there was none;
BenchmarkMode exposed only snake_case outputName while the flags lived as
case labels inside parse. Exhaustive switch, nil for the default mode, and a
round-trip test so the new copy is pinned rather than merely added."
```

Expected: the suite's failure count is 0 and its test count is the Task 0 baseline + 4.

---

### Task 2: the gate-step pin, generalized to twelve

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` (the constants block at lines 1–89 and the test class)

**Interfaces:**
- Consumes: `BenchmarkMode.flagName` (Task 1), `BenchmarkMode.isGateable`, and this file's existing readers `hostJobSteps()`, `jobSteps(_:)`, `stepNamed(_:in:)`, `WorkflowStep`, `docsOnlyGuard`, `workflowPath`, `repositoryRoot()`.
- Produces: nothing consumed by later tasks; Task 5 adds one more test to the same file.

**Guarantees added:** G1, G2, G3, G4, G5, G6, G7, G18, G19

- [ ] **Step 1: Replace the table and its helpers**

In `WorkflowShapeTests.swift`, delete the header comment block above `private let workflowPath` that begins "// `pinnedGateSteps` is a small EXPLICIT table" (it describes the design this task removes), delete `private let pointGeometryFlag`, `private let realisticFlag`, the `gateCommand` function, the `GateStepSpec` struct and the `pinnedGateSteps` array, and put in their place:

```swift
// The exact whitespace-joined `run:` payload every gate step must carry. Takes an
// OPTIONAL flag so the default mode -- which has no flag and runs as a bare `--gate` --
// is this same helper with a nil, not a second literal that could drift.
private func gateCommand(_ flag: String?) -> String {
    let head = "swift run -c release --scratch-path /tmp/text-engine-host-build "
        + "ViewportBenchmarks --"
    guard let flag else { return head + " --gate" }
    return head + " \(flag) --gate"
}

// One row per GATEABLE mode, in the order the host job runs them. Two things this table
// is NOT: it is not a hand-picked subset (testPinnedGateStepsCoverExactlyTheGateableModes
// pins it to BenchmarkMode.isGateable in both directions), and it is not keyed by flag
// (the default mode's flag IS `--gate`, which all twelve steps carry, so a flag-token
// probe cannot identify it -- identification is by exact payload equality, which is also
// strictly stronger: a token probe cannot see a second invocation inside one `|` block
// scalar, or a trailing `|| true`).
private struct GateStepSpec {
    let mode: BenchmarkMode     // the gateable mode this step runs
    let stepName: String        // the exact `- name:` the step must carry

    var command: String { gateCommand(mode.flagName) }
}

private let pinnedGateSteps: [GateStepSpec] = [
    GateStepSpec(mode: .pipeline, stepName: "Run synthetic benchmark gate"),
    GateStepSpec(mode: .variableHeight, stepName: "Run variable-height benchmark gate"),
    GateStepSpec(mode: .variableHeightMutation,
                 stepName: "Run variable-height mutation benchmark gate"),
    GateStepSpec(mode: .structuralMutation,
                 stepName: "Run structural mutation benchmark gate"),
    GateStepSpec(mode: .bulkStructuralMutation,
                 stepName: "Run bulk structural mutation benchmark gate"),
    GateStepSpec(mode: .lineQuery, stepName: "Run line query benchmark gate"),
    GateStepSpec(mode: .lineGeometryQuery,
                 stepName: "Run line geometry query benchmark gate"),
    GateStepSpec(mode: .columnQuery, stepName: "Run column query benchmark gate"),
    GateStepSpec(mode: .columnGeometryQuery,
                 stepName: "Run column geometry query benchmark gate"),
    GateStepSpec(mode: .pointQuery, stepName: "Run point query benchmark gate"),
    GateStepSpec(mode: .pointGeometryQuery,
                 stepName: "Run point geometry query benchmark gate"),
    GateStepSpec(mode: .realisticProvider,
                 stepName: "Run realistic provider benchmark gate"),
]

// The gate block's boundaries. A total order pins the twelve against each other but not
// against the file: all twelve could migrate past the diagnostics together and stay in
// order. Two anchors, not the twenty-four the per-row before/after pairs cost.
private let gateBlockAfterStepName = "Run host tests"
private let gateBlockBeforeStepName = "Run memory shape diagnostic"
```

- [ ] **Step 2: Rewrite the resolver and add the new invariants**

Inside `final class WorkflowShapeTests`, replace the private `steps(for:in:)` helper with a payload-keyed one, and replace the six existing `testEach…`/`testExactlyOne…` bodies' resolution calls. The full replacement for the helper:

```swift
    // Resolve a spec's step by exact PAYLOAD, not by flag. `.pipeline`'s flag is `--gate`,
    // which every gate step carries, so a flag probe is false by construction for that row;
    // payload equality is uniform across all twelve and strictly stronger. Asserts the set
    // is non-empty first: a test quantified over an empty set is vacuously green the day
    // the gate is deleted.
    private func steps(for spec: GateStepSpec, in all: [WorkflowStep]) -> [WorkflowStep] {
        let matches = all.filter { $0.runTokens.joined(separator: " ") == spec.command }
        XCTAssertFalse(
            matches.isEmpty,
            "\(workflowPath): no step in \(hostJobKey) runs exactly `\(spec.command)` — the "
                + "\"\(spec.stepName)\" gate is gone, renamed, or had its payload edited")
        return matches
    }
```

Then append these four tests to the class:

```swift
    // Invariant 7 (new). The table is the gateable set, in both directions. A gateable mode
    // with no pinned step is a blocking budget nothing pins; a pinned step whose mode is not
    // gateable is a row that can never match. Same construction as GateFloorTests' pin of
    // everyGatedBudget() to isGateable.
    func testPinnedGateStepsCoverExactlyTheGateableModes() {
        let pinned = pinnedGateSteps.map(\.mode.outputName).sorted()
        let gateable = BenchmarkMode.allCases.filter(\.isGateable).map(\.outputName).sorted()
        XCTAssertEqual(
            pinned, gateable,
            "pinnedGateSteps and BenchmarkMode.isGateable disagree. Every gateable mode "
                + "needs a pinned CI step, and every pinned step needs a gateable mode.\n"
                + "  pinned:   \(pinned)\n  gateable: \(gateable)")
        XCTAssertEqual(
            pinned.count, Set(pinned).count,
            "a mode appears twice in pinnedGateSteps: \(pinned)")
    }

    // Invariant 8 (new). The twelve run in the declared order. Order is part of the shape:
    // the synthetic gate first and the realistic provider last is how a reader of a hosted
    // log knows which budget a `gate=fail` belongs to before scrolling.
    func testGateStepsAppearInTheDeclaredOrder() throws {
        let all = try hostJobSteps()
        var previous = -1
        for spec in pinnedGateSteps {
            guard let step = steps(for: spec, in: all).first else { continue }
            XCTAssertLessThan(
                previous, step.index,
                "\(spec.stepName) sits out of the declared gate order (index \(step.index) "
                    + "after index \(previous)); pinnedGateSteps declares the order the host "
                    + "job must run them in")
            previous = step.index
        }
    }

    // Invariant 9 (new). The block's boundaries, which the total order does not pin: all
    // twelve could migrate past the diagnostics together and stay in order.
    func testGateBlockSitsBetweenItsBoundaryAnchors() throws {
        let all = try hostJobSteps()
        guard let after = stepNamed(gateBlockAfterStepName, in: all),
              let before = stepNamed(gateBlockBeforeStepName, in: all) else {
            XCTFail("\(workflowPath): missing \"\(gateBlockAfterStepName)\" or "
                + "\"\(gateBlockBeforeStepName)\" — the gate block's boundary anchors are gone")
            return
        }
        for spec in pinnedGateSteps {
            for step in steps(for: spec, in: all) {
                XCTAssertLessThan(
                    after.index, step.index,
                    "\(step.name) must sit after \"\(gateBlockAfterStepName)\"")
                XCTAssertLessThan(
                    step.index, before.index,
                    "\(step.name) must sit before \"\(gateBlockBeforeStepName)\"")
            }
        }
    }

    // Invariant 10 (new). THE one-level-up check: a per-step pin cannot see a step it does
    // not know about. Every `--gate` token in the WHOLE FILE must belong to a pinned step,
    // so a thirteenth gate -- in this job or in either cross-target job, where the narrower
    // host-job-scoped count would not have looked -- cannot ship unpinned.
    func testEveryGateInvocationInTheWorkflowIsPinned() throws {
        let url = repositoryRoot().appendingPathComponent(workflowPath)
        let text = try String(contentsOf: url, encoding: .utf8)
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        let gateTokens = tokens.filter { $0 == "--gate" }
        XCTAssertEqual(
            gateTokens.count, pinnedGateSteps.count,
            "\(workflowPath) carries \(gateTokens.count) `--gate` tokens but "
                + "\(pinnedGateSteps.count) steps are pinned. Every gate invocation anywhere "
                + "in this workflow must be a pinned step: an unpinned one can carry "
                + "`|| true` or continue-on-error and no test would see it.")
    }
```

- [ ] **Step 3: Run the file's tests**

```bash
swift test --filter WorkflowShapeTests 2>&1 | tail -5
```

Expected: `Executed 10 tests, with 0 failures` (six existing + four new).

- [ ] **Step 4: Drill G3 — all twelve at once**

The load-bearing drill. Disarm **every** gate step in one edit and assert exactly twelve distinct failures: a per-row loop that catches one row catches all of them, but only the simultaneous form proves no row is silently unbound.

```bash
SCRATCH=/tmp/slice56-drill-c
mkdir -p "$SCRATCH"
cp .github/workflows/swift-ci.yml "$SCRATCH/swift-ci.yml.bak"
sed -i '' 's/\(ViewportBenchmarks -- .*--gate\)$/\1 || true/' .github/workflows/swift-ci.yml
swift test --filter WorkflowShapeTests > "$SCRATCH/drill-c.txt" 2>&1
grep -c "no step in host-tests-and-benchmark-gate runs exactly" "$SCRATCH/drill-c.txt"
cp "$SCRATCH/swift-ci.yml.bak" .github/workflows/swift-ci.yml
if git diff --quiet -- .github/workflows/swift-ci.yml; then
  echo "workflow_restored=yes"
else
  echo "workflow_restored=NO — restore it before continuing"
fi
```

Expected: the `grep -c` prints **12**, and `workflow_restored=yes`. Record both numbers.

- [ ] **Step 5: Drill G3 attribution (c2), G4, G5, G6, G7 — one edit each**

Each of these follows the same shape: back up the workflow, make one edit, run `swift test --filter WorkflowShapeTests`, record the failing test name and message, restore, confirm `git diff --quiet` succeeds. Make the edits by hand, one at a time:

| Drill | Edit | Expected red |
|---|---|---|
| (c2) | append ` \|\| true` to the `--line-query` step's `run:` only | `testEachPinnedGateRunsExactlyTheExpectedCommand`, naming the line-query command |
| (d) | duplicate the `--point-query` gate step, renaming the copy `Run spare gate` | `testEveryGateInvocationInTheWorkflowIsPinned` (13 vs 12) |
| (e) | swap the `--column-query` and `--point-query` steps | `testGateStepsAppearInTheDeclaredOrder` |
| (f) | delete the `if:` line from the `--structural-mutation` step | `testEachPinnedGateCarriesTheDocsOnlyGuard` |
| (g) | add `continue-on-error: true` to the synthetic gate step | `testNoPinnedGateIsContinueOnError` |
| (t), drill for G19 | add a `--gate` step to the **WASM** job | `testEveryGateInvocationInTheWorkflowIsPinned` (13 vs 12) — the widened scope; the old host-job-only count would have stayed green |

After each, verify restoration:

```bash
if git diff --quiet -- .github/workflows/swift-ci.yml; then echo "restored=yes"; else echo "restored=NO"; fi
```

- [ ] **Step 6: Drill G1, G2, G18 — the table's own invariants**

| Drill | Edit | Expected red |
|---|---|---|
| (a) | delete the `.columnQuery` row from `pinnedGateSteps` | `testPinnedGateStepsCoverExactlyTheGateableModes` |
| (b) | add a `.wrapRowQuery` row to `pinnedGateSteps` | `testPinnedGateStepsCoverExactlyTheGateableModes` (and the payload resolver, since no such step exists) |
| (s) | move all twelve gate steps below `Run memory shape diagnostic`, order preserved | `testGateBlockSitsBetweenItsBoundaryAnchors` — while `testGateStepsAppearInTheDeclaredOrder` stays green, which is the point of keeping two anchors |

Record for (s) that the order test stayed green: that asymmetry is the evidence the anchors are not redundant with the total order.

- [ ] **Step 7: Verify the whole suite and commit**

```bash
swift test > /tmp/slice56-t2-suite.txt 2>&1
tail -3 /tmp/slice56-t2-suite.txt
git status --short
git add Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
git commit -m "test: pin the shape of all twelve gate steps, not two

pinnedGateSteps grows from a hand-written pair to one row per gateable mode,
checked against BenchmarkMode.isGateable in both directions. Identification
moves from flag token to exact payload equality -- the default mode's flag IS
--gate, which every gate step carries, so a token probe cannot name it, and
payload equality also forecloses a second invocation inside one block scalar.
Twelve before/after pairs collapse into one declared total order plus two
boundary anchors, and a whole-file --gate census closes the one-level-up hole:
a thirteenth gate step, in any job, is now unpinnable."
```

Expected: failure count 0; the suite's test count is Task 1's total + 4.

---

### Task 3: the debt ledger's table shape

**Files:**
- Create: `Tests/ViewportBenchmarksTests/DebtLedgerShapeTests.swift`
- Reads: `docs/superpowers/debt-ledger.md` (41 table lines as of 2026-09-04: header, separator, 39 rows)

**Interfaces:**
- Consumes: `repositoryRoot()` from `Tests/ViewportBenchmarksTests/ProcessSupport.swift`.
- Produces: nothing consumed by later tasks.

**Guarantees added:** G13, G21

- [ ] **Step 1: Write the failing test**

Create `Tests/ViewportBenchmarksTests/DebtLedgerShapeTests.swift`:

```swift
import Foundation
import XCTest

// The ledger is a GitHub-flavored Markdown table, and GFM does NOT protect a pipe inside
// a code span: a literal `|` splits the cell wherever it appears, so `\|` is the only
// correct spelling. Slice 55b found D-9 and D-27 rendering with 7 and 10 cells instead of
// 5 -- and D-9's STATUS column, the one the escalation rule reads, therefore read as the
// tail of a code span instead of `scheduled(slice-56)`. The rows were repaired then; what
// was missing, and is what this file supplies, is the check.
private let ledgerPath = "docs/superpowers/debt-ledger.md"
private let expectedPipesPerRow = 6      // five columns
private let headerRow = "| id | born | severity | statement | status |"
private let separatorRow = "|---|---|---|---|---|"
private let knownStatusPrefixes = [
    "open", "discharged(", "scheduled(", "deferred(", "accepted-risk",
]

private func unescapedPipeCount(_ line: String) -> Int {
    var count = 0
    var previous: Character?
    for character in line {
        if character == "|", previous != "\\" { count += 1 }
        previous = character
    }
    return count
}

// Split on unescaped pipes only, dropping the empty head and tail a `| a | b |` row
// produces. `\|` inside a code span is the CORRECT escape and must not split.
private func columns(of line: String) -> [String] {
    var cells: [String] = []
    var current = ""
    var previous: Character?
    for character in line {
        if character == "|", previous != "\\" {
            cells.append(current)
            current = ""
        } else {
            current.append(character)
        }
        previous = character
    }
    cells.append(current)
    if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
    if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
    return cells.map { $0.trimmingCharacters(in: .whitespaces) }
}

private func tableLines() throws -> [String] {
    let url = repositoryRoot().appendingPathComponent(ledgerPath)
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.components(separatedBy: "\n").filter { $0.hasPrefix("|") }
}

final class DebtLedgerShapeTests: XCTestCase {
    // G13. Five columns per row, counted on UNESCAPED pipes so a correctly escaped `\|`
    // inside a code span passes and a raw one fails -- which is the actual defect.
    func testEveryRowHasExactlyFiveColumns() throws {
        let lines = try tableLines()
        XCTAssertFalse(lines.isEmpty, "\(ledgerPath): no table found")
        for line in lines where line.hasPrefix("| D-") {
            let pipes = unescapedPipeCount(line)
            let id = columns(of: line).first ?? "?"
            XCTAssertEqual(
                pipes, expectedPipesPerRow,
                "\(ledgerPath): row \(id) carries \(pipes) unescaped pipes, want "
                    + "\(expectedPipesPerRow) (five columns). A literal `|` inside a code "
                    + "span splits the cell in GFM — write it `\\|`. This is not cosmetic: "
                    + "a split row shifts the STATUS column, which the escalation rule reads.")
        }
    }

    // G21, half one. The table's EXTENT. A row whose id cell is mangled stops matching
    // `| D-` and would leave the checked set silently -- the same one-level-up hole the
    // workflow's whole-file `--gate` census closes for gate steps.
    func testTheTableIsHeaderSeparatorAndIdRowsOnly() throws {
        let lines = try tableLines()
        guard lines.count >= 2 else {
            return XCTFail("\(ledgerPath): table has fewer than two lines")
        }
        XCTAssertEqual(lines[0], headerRow, "\(ledgerPath): unexpected header row")
        XCTAssertEqual(lines[1], separatorRow, "\(ledgerPath): unexpected separator row")
        for (offset, line) in lines.dropFirst(2).enumerated() {
            XCTAssertTrue(
                line.hasPrefix("| D-"),
                "\(ledgerPath): table body line \(offset + 3) does not start with `| D-`: "
                    + "\(line.prefix(60))… — a row that stops matching leaves every other "
                    + "check in this file silently, which is exactly how an unchecked row hides")
        }
    }

    // G21, half two. Ids unique AND contiguous from D-1. Contiguity is what makes a
    // deleted row visible: the ledger is append-only ("append rows; never delete — flip
    // status instead"), so a gap means a row was removed rather than discharged.
    func testRowIdsAreUniqueAndContiguousFromOne() throws {
        let lines = try tableLines().filter { $0.hasPrefix("| D-") }
        var numbers: [Int] = []
        for line in lines {
            guard let id = columns(of: line).first,
                  let number = Int(id.dropFirst(2)), id.hasPrefix("D-") else {
                XCTFail("\(ledgerPath): unparseable id cell in: \(line.prefix(60))…")
                continue
            }
            numbers.append(number)
        }
        XCTAssertEqual(
            numbers, Array(1...numbers.count),
            "\(ledgerPath): ids must run D-1…D-\(numbers.count) with no gaps and no "
                + "repeats. The ledger is append-only, so a gap means a row was deleted "
                + "instead of having its status flipped.")
    }

    // G13, status half. The status column is what the escalation rule reads, so its
    // vocabulary is pinned: an unparseable status is indistinguishable from `open` to a
    // human skimming, and from nothing at all to a script.
    func testEveryStatusCellStartsWithAKnownStatus() throws {
        let lines = try tableLines().filter { $0.hasPrefix("| D-") }
        for line in lines {
            let cells = columns(of: line)
            guard cells.count == 5 else { continue }   // shape is the other test's failure
            let id = cells[0]
            let status = cells[4]
            XCTAssertFalse(status.isEmpty, "\(ledgerPath): \(id) has an empty status cell")
            let known = knownStatusPrefixes.contains { status.hasPrefix($0) }
                || knownStatusPrefixes.contains { status.hasPrefix("**\($0)") }
            XCTAssertTrue(
                known,
                "\(ledgerPath): \(id)'s status starts with \(status.prefix(40))…, which is "
                    + "none of \(knownStatusPrefixes). The header of this file lists the "
                    + "legal statuses; the escalation rule reads this cell.")
        }
    }
}
```

- [ ] **Step 2: Run it — it must pass on the committed ledger**

```bash
swift test --filter DebtLedgerShapeTests 2>&1 | tail -5
```

Expected: `Executed 4 tests, with 0 failures`. This guard is a **ratchet over a clean artifact**: measured 2026-09-04 the ledger has 39 rows, ids `D-1`…`D-39` contiguous, all carrying exactly six unescaped pipes. A red here means the ledger was broken between then and now, not that the test is wrong.

- [ ] **Step 3: Drill G13 — a raw pipe in a code span must redden**

```bash
SCRATCH=/tmp/slice56-drill-n
mkdir -p "$SCRATCH"
cp docs/superpowers/debt-ledger.md "$SCRATCH/ledger.bak"
sed -i '' 's/gov_p95=median\\|max/gov_p95=median|max/' docs/superpowers/debt-ledger.md
swift test --filter DebtLedgerShapeTests > "$SCRATCH/drill-n.txt" 2>&1
if grep -q "unescaped pipes, want 6" "$SCRATCH/drill-n.txt"; then
  echo "drill_n=red_as_expected"
else
  echo "drill_n=DID_NOT_REDDEN"
fi
cp "$SCRATCH/ledger.bak" docs/superpowers/debt-ledger.md
if git diff --quiet -- docs/superpowers/debt-ledger.md; then echo "ledger_restored=yes"; else echo "ledger_restored=NO"; fi
```

Expected: `drill_n=red_as_expected` naming D-9, and `ledger_restored=yes`.

- [ ] **Step 4: Drill G21 — a deleted row and a mangled id**

Two hand edits, each reverted before the next:

| Drill | Edit | Expected red |
|---|---|---|
| (v) | delete the `| D-20 |` row | `testRowIdsAreUniqueAndContiguousFromOne` — the list jumps 19 → 21 |
| (w) | change one row's id cell from `| D-30 |` to `| X-30 |` | `testTheTableIsHeaderSeparatorAndIdRowsOnly` — and note in the record that `testEveryRowHasExactlyFiveColumns` stays **green**, since that row no longer matches `| D-`. That asymmetry is why the extent check exists |

After each: `if git diff --quiet -- docs/superpowers/debt-ledger.md; then echo "restored=yes"; else echo "restored=NO"; fi`

- [ ] **Step 5: Commit**

```bash
swift test > /tmp/slice56-t3-suite.txt 2>&1
tail -3 /tmp/slice56-t3-suite.txt
git add Tests/ViewportBenchmarksTests/DebtLedgerShapeTests.swift
git commit -m "test: pin the debt ledger's table shape

GFM does not protect a pipe inside a code span, and slice 55b found two rows
split by one -- including D-9's status cell, which is the column the escalation
rule reads. Pins five columns counted on unescaped pipes, id uniqueness and
contiguity, the status vocabulary, and the table's extent, so a row with a
mangled id cannot leave the checked set silently."
```

Expected: failure count 0; test count is Task 2's total + 4.

---

### Task 4: the plan linter

**Files:**
- Create: `.github/scripts/lint-plan-assertions.sh`
- Modify: `Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift` (the `selfTestScripts` array, lines 8–13)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the CLI Task 5 wires up — `lint-plan-assertions.sh [--self-test] [--list-exempt] [<path>…]`, exit 0 clean / 1 on violations, one `violation=<rule> file=<path> line=<n> detail=<text>` line per finding and a final `lint=pass files=<n> violations=0` or `lint=fail files=<n> violations=<m>`.

**Guarantees added:** G8, G9, G10, G11, G15

- [ ] **Step 1: Write the script**

```bash
cat > .github/scripts/lint-plan-assertions.sh <<'SCRIPT'
#!/usr/bin/env bash
# Lint a plan document's own assertions against the conventions in AGENTS.md
# "Plan-assertion conventions (D-2)", plus the guarantee-inventory convention (D-35).
#
# A plan's checks must be able to fail. Slice 47's plan carried 16 of 29 assertion sites
# that could not fail; slice 55a's carried four more AFTER an explicit self-audit in its
# own preamble. Prose plus attention did not hold, so the SHAPE-detectable half is
# mechanized here. The semantic half -- does a drill actually drill? -- is not, and cannot
# be; see AGENTS.md.
#
# Usage: ./.github/scripts/lint-plan-assertions.sh [<plan.md> ...]   (default: every
#          non-exempt plan under docs/superpowers/plans)
# Usage: ./.github/scripts/lint-plan-assertions.sh --self-test
# Usage: ./.github/scripts/lint-plan-assertions.sh --list-exempt
#
# Rules:
#   R1  PIPESTATUS inside a bash/sh fence. Agent command blocks run under zsh, which does
#       not populate PIPESTATUS; `${PIPESTATUS[0]}` expands EMPTY and `[ "" -eq 0 ]` is
#       true, so the assertion inverts into a pass (D-17).
#   R2  `echo "...=$?"` whose previous shell line is a command insensitive to the invariant
#       (git diff, git status, gh, jq, sed -i) or a pipeline (D-2 rule 2).
#   R3  A SCREAMING_SNAKE variable used in a fence but assigned nowhere in that same fence
#       (D-2 rule 4; slice 47's $SCRATCH resolved to /x.txt at 23 sites).
#   R4  A task section with no `**Guarantees added:**` block, or one that lists a guarantee
#       with no drill step naming it (D-35).
#
# Scope: `bash` and `sh` fences only, and HEREDOC BODIES ARE SKIPPED for every rule. A plan
# that builds a shell tool carries that tool's source -- including its own known-bad
# fixtures -- inside heredocs; without the skip, the linter could not be built by a
# compliant plan. It also keeps R3 from analysing heredoc'd Python as shell.
set -euo pipefail

PLANS_DIR="docs/superpowers/plans"

# Plans written before this linter existed. ONE array, printed verbatim by --list-exempt:
# a seam that RESTATED its subject would make PlanLintTests' ratchet prove only that the
# seam agrees with itself -- D-26's two-awk-programs residual in a new place. The list
# shrinks only by deliberate edit and is not expected to reach zero: a historical plan is
# evidence, and rewriting one to satisfy a rule written later would falsify the record.
EXEMPT_PLANS=(
  "2026-05-31-document-source-provider-contract.md"
  "2026-05-31-headless-fixed-height-viewport-virtualization.md"
  "2026-06-03-headless-pipeline-benchmark-regression-gate.md"
  "2026-06-04-realistic-provider-benchmark.md"
  "2026-06-05-ci-benchmark-gate-wiring.md"
  "2026-06-06-core-owned-memory-shape.md"
  "2026-06-06-github-main-ruleset.md"
  "2026-06-06-viewport-benchmarks-decomposition.md"
  "2026-06-07-realistic-provider-gate-calibration.md"
  "2026-06-07-rss-memory-observation.md"
  "2026-06-08-hosted-baseline-relative-realistic-observation.md"
  "2026-06-08-hosted-realistic-provider-gate-ci.md"
  "2026-06-09-cross-target-textenginecore-ci.md"
  "2026-06-11-variable-height-layout-foundation.md"
  "2026-06-12-variable-height-ci-gate-promotion.md"
  "2026-06-13-ci-resource-optimization.md"
  "2026-06-14-variable-height-mutation.md"
  "2026-06-16-swift-ci-required-checks.md"
  "2026-06-16-trusted-docs-only-gate.md"
  "2026-06-17-policy-sensitive-markdown-path-hardening.md"
  "2026-06-18-cross-target-provider-coverage.md"
  "2026-06-18-variable-height-mutation-ci-gate-promotion.md"
  "2026-06-20-bulk-structural-edits.md"
  "2026-06-20-dynamic-line-insert-delete.md"
  "2026-06-20-structural-mutation-ci-gate-promotion.md"
  "2026-06-21-bulk-structural-mutation-ci-gate-promotion.md"
  "2026-06-21-vertical-position-query.md"
  "2026-06-25-line-query-ci-gate-promotion.md"
  "2026-06-26-provider-native-prefix-search.md"
  "2026-06-27-compute-native-prefix-search.md"
  "2026-06-29-geometry-bearing-vertical-query.md"
  "2026-07-03-line-geometry-query-ci-gate-promotion.md"
  "2026-07-04-horizontal-position-query.md"
  "2026-07-05-column-query-ci-gate-promotion.md"
  "2026-07-07-horizontal-geometry-query.md"
  "2026-07-10-column-geometry-query-ci-gate-promotion.md"
  "2026-07-10-point-query.md"
  "2026-07-12-gate-budget-recalibration.md"
  "2026-07-13-point-geometry-query.md"
  "2026-07-16-point-geometry-query-ci-gate-promotion.md"
  "2026-07-17-gate-budget-ratchet-repair.md"
  "2026-07-18-absolute-product-budget.md"
  "2026-07-18-shell-window-selection-guard.md"
  "2026-07-19-budget-reproduction-standing-test.md"
  "2026-07-19-realistic-provider-ci-gate-promotion.md"
  "2026-07-19-wasm-cross-target-blocking-gate.md"
  "2026-07-20-wasm-required-check-rename.md"
  "2026-07-21-outer-loop-codification.md"
  "2026-07-22-visual-row-model.md"
  "2026-07-24-wrap-viewport-compute.md"
  "2026-08-07-cross-target-script-hardening.md"
  "2026-08-08-gate-recalibration-and-bulk-ceiling.md"
  "2026-08-09-wrap-row-query.md"
  "2026-08-23-calibration-chain-hardening.md"
  "2026-08-28-wrap-point-query-trap-repairs.md"
  "2026-09-03-wrap-point-query.md"
)

awk_program_path=""

write_awk_program() {
  awk_program_path="$(mktemp)"
  cat > "$awk_program_path" <<'AWKPROG'
BEGIN {
  split("HOME PWD TMPDIR PATH USER SHELL IFS OLDPWD RANDOM SECONDS PIPESTATUS " \
        "NF NR FS OFS ORS RS FILENAME SUBSEP", allowlist, " ")
  for (i in allowlist) allowed[allowlist[i]] = 1
  in_fence = 0; lang = ""; in_heredoc = 0; heredoc_tag = ""; prev_shell = ""
  in_task = 0; task_name = ""; task_start = 0; guarantee_line = 0
}

function report(rule, line, detail) {
  printf "violation=%s file=%s line=%d detail=%s\n", rule, FILENAME, line, detail
  violations++
}

function close_fence(   name) {
  for (name in used) {
    if (!(name in assigned) && !(name in allowed) && name !~ /^(GITHUB|RUNNER|BASH)_/) {
      report("R3", used[name], \
        "$" name " is used in this fence but assigned nowhere in it; each command block " \
        "is a fresh shell, so it expands empty (D-2 rule 4)")
    }
  }
  delete used; delete assigned
}

# ---- fence tracking -------------------------------------------------------------
/^```/ {
  if (in_fence) { if (shell_fence) close_fence(); in_fence = 0; shell_fence = 0; in_heredoc = 0 }
  else {
    in_fence = 1
    lang = $0; sub(/^```/, "", lang); sub(/[^A-Za-z0-9].*$/, "", lang)
    shell_fence = (lang == "bash" || lang == "sh")
    prev_shell = ""
  }
  next
}

# ---- task-section tracking (R4 operates OUTSIDE fences) -------------------------
!in_fence && /^### Task [0-9]+:/ {
  if (in_task) check_task()
  in_task = 1; task_name = $0; task_start = FNR; guarantee_line = 0
  delete listed; delete drilled
  next
}
!in_fence && in_task && /^\*\*Guarantees added:\*\*/ {
  guarantee_line = FNR
  n = split($0, tok, /[^A-Za-z0-9]+/)
  for (i = 1; i <= n; i++) if (tok[i] ~ /^G[0-9]+$/) listed[tok[i]] = 1
  next
}
in_task && /[Dd]rill/ {
  n = split($0, tok, /[^A-Za-z0-9]+/)
  for (i = 1; i <= n; i++) if (tok[i] ~ /^G[0-9]+$/) drilled[tok[i]] = 1
}

function check_task(   g) {
  if (guarantee_line == 0) {
    report("R4", task_start, \
      "task section has no `**Guarantees added:**` block; a task that adds a standing " \
      "guarantee and never names it is how a pin ships undrilled (D-35)")
    return
  }
  for (g in listed) {
    if (!(g in drilled)) {
      report("R4", guarantee_line, \
        "guarantee " g " is listed but no step in this task mentions a drill for it")
    }
  }
}

# ---- shell rules ---------------------------------------------------------------
{
  if (!in_fence || !shell_fence) next

  if (in_heredoc) {
    t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
    if (t == heredoc_tag) in_heredoc = 0
    next
  }
  if (match($0, /<<-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) {
    tag = substr($0, RSTART, RLENGTH)
    sub(/^<<-?[ \t]*/, "", tag); gsub(/['"]/, "", tag)
    heredoc_tag = tag; in_heredoc = 1
  }

  if ($0 ~ /PIPESTATUS/) {
    report("R1", FNR, \
      "PIPESTATUS is not populated under zsh, where agent command blocks run: " \
      "${PIPESTATUS[0]} expands EMPTY and [ \"\" -eq 0 ] is TRUE, so the check inverts " \
      "into a pass (D-17). Do not pipe, or wrap the pipeline in bash -c 'set -o pipefail'")
  }

  if ($0 ~ /echo[^=]*=\$\?/) {
    if (prev_shell ~ /^[ \t]*(git[ \t]+diff|git[ \t]+status|gh[ \t]|jq[ \t]|sed[ \t]+-i)/ \
        || prev_shell ~ /\|/) {
      report("R2", FNR, \
        "echo \"...=$?\" after a command whose exit status is insensitive to the " \
        "invariant; it exits 0 either way (D-2 rule 2). Assert with [ -z \"$(...)\" ], " \
        "git diff --quiet, or an if/else printing both branches")
    }
  }

  if (match($0, /^[ \t]*(export[ \t]+|local[ \t]+)?[A-Z][A-Z0-9_]*=/)) {
    a = substr($0, RSTART, RLENGTH); sub(/=$/, "", a)
    sub(/^[ \t]*(export[ \t]+|local[ \t]+)?/, "", a); assigned[a] = 1
  }
  if (match($0, /for[ \t]+[A-Z][A-Z0-9_]*[ \t]+in/)) {
    a = substr($0, RSTART, RLENGTH); sub(/^for[ \t]+/, "", a); sub(/[ \t]+in$/, "", a)
    assigned[a] = 1
  }
  if (match($0, /read[ \t]+(-r[ \t]+)?[A-Z][A-Z0-9_]*/)) {
    a = substr($0, RSTART, RLENGTH); sub(/^read[ \t]+(-r[ \t]+)?/, "", a); assigned[a] = 1
  }
  if (match($0, /:[ \t]+"\$\{[A-Z][A-Z0-9_]*:\?\}"/)) {
    a = substr($0, RSTART, RLENGTH); gsub(/[^A-Z0-9_]/, "", a); assigned[a] = 1
  }

  rest = $0
  while (match(rest, /\$\{?[A-Z][A-Z0-9_]*/)) {
    name = substr(rest, RSTART, RLENGTH); sub(/^\$\{?/, "", name)
    if (!(name in used)) used[name] = FNR
    rest = substr(rest, RSTART + RLENGTH)
  }

  if ($0 !~ /^[ \t]*$/) prev_shell = $0
}

END {
  if (in_fence && shell_fence) close_fence()
  if (in_task) check_task()
  exit 0
}
AWKPROG
}

lint_file() {
  : "${1:?lint_file needs a path}"
  awk -v violations=0 -f "$awk_program_path" "$1"
}

run_lint() {
  local files=("$@") total=0 count=0 output
  if [[ ${#files[@]} -eq 0 ]]; then
    local base
    for path in "$PLANS_DIR"/*.md; do
      base="$(basename "$path")"
      local skip=0 entry
      for entry in "${EXEMPT_PLANS[@]}"; do
        if [[ "$entry" == "$base" ]]; then skip=1; break; fi
      done
      if [[ $skip -eq 0 ]]; then files+=("$path"); fi
    done
  fi
  for path in "${files[@]}"; do
    count=$((count + 1))
    output="$(lint_file "$path")"
    if [[ -n "$output" ]]; then
      echo "$output"
      total=$((total + $(echo "$output" | grep -c '^violation=')))
    fi
  done
  if [[ $total -gt 0 ]]; then
    echo "lint=fail files=$count violations=$total"
    return 1
  fi
  echo "lint=pass files=$count violations=0"
  return 0
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
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' EXIT

  cat > "$dir/good.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** G1

- [ ] **Step 1: do it**

```bash
SCRATCH=/tmp/x
echo "$SCRATCH"
cat > "$SCRATCH/inner.sh" <<'INNER'
status=${PIPESTATUS[0]}
git status
echo "dirty=$?"
INNER
```

- [ ] **Step 2: Drill G1**

Break it and confirm the red.
FIXTURE

  cat > "$dir/bad-r1.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
swift test 2>&1 | tail -5
echo "status=${PIPESTATUS[0]}"
```
FIXTURE

  cat > "$dir/bad-r2.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
git status
echo "clean=$?"
```
FIXTURE

  cat > "$dir/bad-r3.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
echo hello > "$SCRATCH/out.txt"
```
FIXTURE

  cat > "$dir/bad-r4.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** G7

- [ ] **Step 1: do it**

Nothing here breaks anything.
FIXTURE

  cat > "$dir/bad-r4-missing.md" <<'FIXTURE'
### Task 1: something

- [ ] **Step 1: do it**
FIXTURE

  local out rc
  # The good fixture must be clean -- and it is the heredoc drill: its INNER body carries
  # PIPESTATUS, `git status` + `echo "dirty=$?"`, and an unassigned-looking use, all of
  # which MUST be skipped. If the scanner ever stops skipping heredocs this goes red.
  set +e
  out="$(run_lint "$dir/good.md")"; rc=$?
  set -e
  assert_equal "0" "$rc" "good_fixture_exit"
  assert_equal "lint=pass files=1 violations=0" "$out" "good_fixture_output"

  local name expected
  for name in r1 r2 r3 r4 r4-missing; do
    case "$name" in
      r1) expected="R1" ;;
      r2) expected="R2" ;;
      r3) expected="R3" ;;
      *)  expected="R4" ;;
    esac
    set +e
    out="$(run_lint "$dir/bad-$name.md")"; rc=$?
    set -e
    assert_equal "1" "$rc" "bad_${name}_exit"
    local rules
    rules="$(echo "$out" | awk -F'violation=' '/^violation=/ { split($2, f, " "); print f[1] }' | sort -u | tr '\n' ',')"
    assert_equal "${expected}," "$rules" "bad_${name}_rule"
  done

  local exempt_count
  exempt_count="${#EXEMPT_PLANS[@]}"
  if [[ "$exempt_count" -lt 1 ]]; then
    echo "self_test=fail label=exempt_list_empty"
    exit 1
  fi

  echo "self_test=pass"
}

main() {
  write_awk_program
  case "${1:-}" in
    --self-test)
      run_self_test
      ;;
    --list-exempt)
      printf '%s\n' "${EXEMPT_PLANS[@]}"
      ;;
    *)
      run_lint "$@"
      ;;
  esac
}

main "$@"
SCRIPT
chmod +x .github/scripts/lint-plan-assertions.sh
```

- [ ] **Step 2: Run the self-test — it must pass**

```bash
./.github/scripts/lint-plan-assertions.sh --self-test
```

Expected: `self_test=pass`. If any `self_test=fail label=…` line appears, fix the script before continuing; the label names which fixture disagreed.

- [ ] **Step 3: Run the linter over the repository**

```bash
./.github/scripts/lint-plan-assertions.sh
```

Expected: `lint=pass files=1 violations=0` — one file, because every plan except this one is exempt. If this plan itself violates a rule, **fix the plan**, not the rule.

- [ ] **Step 4: Enroll the script in the self-test table**

In `Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift`, add one entry to `selfTestScripts`:

```swift
private let selfTestScripts = [
    "cross-target-compile.sh",
    "derive-gate-budgets.sh",
    "harvest-gate-corpus.sh",
    "detect-docs-only-pr.sh",
    "lint-plan-assertions.sh",
]
```

- [ ] **Step 5: Run the enrollment tests**

```bash
swift test --filter ScriptSelfTestTests 2>&1 | tail -5
```

Expected: `Executed 2 tests, with 0 failures`. `testTableCoversEveryScriptWithASelfTest` discovers scripts containing `--self-test` and compares the set to the table, so an unenrolled script reddens on its own.

- [ ] **Step 6: Drill G8, G9, G10, G11 — each rule, one at a time**

The self-test already drives all four rules against known-bad fixtures, and its `assert_equal` on the rule name is what makes each a drill rather than an assertion. Prove the harness itself can fail: neutralize one rule **by hand** in `.github/scripts/lint-plan-assertions.sh`, run the self-test, restore.

The edits are by hand rather than scripted on purpose — a `sed` that rewrites the R1 branch has to spell the banned token in a shell block, which is a violation of the very rule being drilled, and the linter would refuse this plan.

| Drill | Neutralize | Expected red |
|---|---|---|
| (h), drill for G8 | change the R1 branch's condition to `if (0)` | `self_test=fail label=bad_r1_exit` |
| (i), drill for G9 | change the R2 branch's condition to `if (0)` | `self_test=fail label=bad_r2_exit` |
| (j), drill for G10 | make `close_fence` return before its loop | `self_test=fail label=bad_r3_exit` |
| (k), drill for G11 | make `check_task` return immediately | `self_test=fail label=bad_r4_exit` and `label=bad_r4-missing_exit` |

Back up first and verify restoration after each:

```bash
SCRATCH=/tmp/slice56-drill-rules
mkdir -p "$SCRATCH"
cp .github/scripts/lint-plan-assertions.sh "$SCRATCH/lint.bak"
echo "backup_taken=$?"
```

then, after each hand edit:

```bash
./.github/scripts/lint-plan-assertions.sh --self-test > /tmp/slice56-drill-rule.txt 2>&1 || true
grep 'self_test=' /tmp/slice56-drill-rule.txt
cp /tmp/slice56-drill-rules/lint.bak .github/scripts/lint-plan-assertions.sh
if git diff --quiet -- .github/scripts/lint-plan-assertions.sh; then echo "restored=yes"; else echo "restored=NO"; fi
```

Expected each time: a `self_test=fail label=…` line naming the fixture whose rule was neutralized, then `restored=yes`. Record all four labels.

- [ ] **Step 7: Drill G15 — an unenrolled script must redden**

```bash
SCRATCH=/tmp/slice56-drill-p
mkdir -p "$SCRATCH"
cp Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift "$SCRATCH/enroll.bak"
sed -i '' '/"lint-plan-assertions.sh",/d' Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift
swift test --filter ScriptSelfTestTests > "$SCRATCH/drill-p.txt" 2>&1
if grep -q "enroll every script that has a --self-test" "$SCRATCH/drill-p.txt"; then
  echo "drill_p=red_as_expected"
else
  echo "drill_p=DID_NOT_REDDEN"
fi
cp "$SCRATCH/enroll.bak" Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift
```

Expected: `drill_p=red_as_expected`.

- [ ] **Step 8: Verify the whole suite and commit**

```bash
swift test > /tmp/slice56-t4-suite.txt 2>&1
tail -3 /tmp/slice56-t4-suite.txt
git add .github/scripts/lint-plan-assertions.sh Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift
git commit -m "feat: lint-plan-assertions.sh — the shape-detectable half of D-2

Four rules: the zsh pipe-status idiom in a shell fence (D-17, which inverts a
failed check into a pass), echo \"...=\$?\" after a status-insensitive command
(D-2 rule 2), a SCREAMING_SNAKE variable used in a fence and assigned nowhere
in it (D-2 rule 4), and a task listing a guarantee with no drill naming it
(D-35). Heredoc bodies are skipped for every rule -- a plan that builds a
shell tool carries that tool's fixtures inside them. Enrolled in
ScriptSelfTestTests so its own assertions can fail a build."
```

Expected: failure count 0; test count unchanged from Task 3 (this task adds no test function, only a table entry).

---

### Task 5: the ratchet pin and the CI step

**Files:**
- Create: `Tests/ViewportBenchmarksTests/PlanLintTests.swift`
- Modify: `.github/workflows/swift-ci.yml` (host job, after the `Detect PR change scope` step)
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` (one new test)

**Interfaces:**
- Consumes: `lint-plan-assertions.sh` and its `--list-exempt` seam (Task 4); `runProcess(_:_:stdin:)` and `repositoryRoot()` from `ProcessSupport.swift`; `hostJobSteps()`, `stepNamed(_:in:)`, `docsOnlyGuard`, `workflowPath` from `WorkflowShapeTests.swift`.
- Produces: nothing consumed by later tasks.

**Guarantees added:** G12, G14, G20

- [ ] **Step 1: Write the failing test**

Create `Tests/ViewportBenchmarksTests/PlanLintTests.swift`:

```swift
import Foundation
import XCTest

// The linter is an AUTHORING tool -- it is run while a plan is still being written and not
// yet committed, which is why it is a script and not only a test. This file is the other
// half: it makes running it non-optional, and it pins the exemption RATCHET.
//
// The ratchet is pinned by property, not by copying 56 filenames into Swift. Four checks
// that are tighter jointly than severally: the script exits 0 over the whole directory,
// the list holds exactly `expectedExemptCount` entries, every entry exists on disk, and no
// entry is dated on or after the cutoff. SWAPPING a new plan in for an old one keeps the
// count and the on-disk check green -- and is caught by the first, because the displaced
// pre-linter plan then enters the linted set and fails.
private let scriptPath = ".github/scripts/lint-plan-assertions.sh"
private let plansDirectory = "docs/superpowers/plans"
private let expectedExemptCount = 56
private let exemptionCutoff = "2026-09-04"

private func runScript(_ arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
    let script = repositoryRoot().appendingPathComponent(scriptPath)
    return try runProcess(URL(fileURLWithPath: "/usr/bin/env"),
                          ["bash", script.path] + arguments, stdin: "")
}

final class PlanLintTests: XCTestCase {
    // G12, and the check that closes the swap. Every non-exempt plan must lint clean.
    func testEveryNonExemptPlanLintsClean() throws {
        let result = try runScript([])
        XCTAssertEqual(
            result.exitCode, 0,
            "\(scriptPath) reported violations. Fix the plan, not the rule.\n"
                + "--- stdout ---\n\(result.stdout)\n--- stderr ---\n\(result.stderr)")
        XCTAssertTrue(
            result.stdout.contains("lint=pass"),
            "no lint=pass line — the linter may have degenerated into a no-op\n\(result.stdout)")
    }

    // G20. The seam must READ the live array, not restate it: a seam that restated its
    // subject would make every check below prove only that the seam agrees with itself --
    // D-26's two-awk-programs residual in a new place.
    func testExemptListHasExactlyTheExpectedCount() throws {
        let result = try runScript(["--list-exempt"])
        XCTAssertEqual(result.exitCode, 0, "--list-exempt failed: \(result.stderr)")
        let entries = result.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(
            entries.count, expectedExemptCount,
            "the exemption list holds \(entries.count) entries, want \(expectedExemptCount). "
                + "It is a RATCHET: it shrinks only by a deliberate edit that also changes "
                + "this number, and it must never grow — a new plan is written to the rules.")
    }

    // G12. Every exempt entry must name a plan that exists. A stale entry is an exemption
    // nobody can see the subject of.
    func testEveryExemptEntryExistsOnDisk() throws {
        let result = try runScript(["--list-exempt"])
        let directory = repositoryRoot().appendingPathComponent(plansDirectory)
        for entry in result.stdout.split(separator: "\n").map(String.init) {
            let path = directory.appendingPathComponent(entry).path
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: path),
                "exemption names a plan that does not exist: \(entry)")
        }
    }

    // G12, the half that stops the list from growing. A plan dated on or after the cutoff
    // was written with the linter in place and has no claim on an exemption.
    func testNoExemptEntryIsDatedOnOrAfterTheCutoff() throws {
        let result = try runScript(["--list-exempt"])
        for entry in result.stdout.split(separator: "\n").map(String.init) {
            XCTAssertTrue(
                String(entry.prefix(10)) < exemptionCutoff,
                "\(entry) is dated on or after \(exemptionCutoff), when the linter landed. "
                    + "Plans from that date on are written to the rules; the exemption set "
                    + "covers only plans written before it existed.")
        }
    }
}
```

- [ ] **Step 2: Run it**

```bash
swift test --filter PlanLintTests 2>&1 | tail -5
```

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 3: Add the CI step**

In `.github/workflows/swift-ci.yml`, in the host job, insert between the `Detect PR change scope` step and the `Complete docs-only PR` step:

```yaml
      # Deliberately NOT guarded by docs_only_pr. A plan is docs/**, so a plan-carrying PR
      # is detected as docs-only and skips `swift test` -- the linter would be loud locally
      # and absent in CI for exactly the PRs that carry plans. This step runs the bash
      # script directly (no Swift build, ~1s), so running it always is free. Its shape,
      # including the absence of the guard, is pinned in WorkflowShapeTests: an edit that
      # adds a guard here has to show up as a diff to that test.
      - name: Lint plan assertions
        run: ./.github/scripts/lint-plan-assertions.sh
```

- [ ] **Step 4: Pin the step's shape**

Append to `WorkflowShapeTests`:

```swift
    // Invariant 11 (new). The plan linter's CI step. Pinned for the usual reasons -- exact
    // payload, no continue-on-error -- and for one unusual one: the ABSENCE of the
    // docs-only guard is deliberate and must stay deliberate. A plan is docs/**, so adding
    // the guard here would silently switch the linter off for precisely the PRs it exists
    // to check, and every other test in this file would stay green.
    func testPlanLintStepIsBlockingAndUnguarded() throws {
        let all = try hostJobSteps()
        let expected = "./.github/scripts/lint-plan-assertions.sh"
        let matches = all.filter { $0.runTokens.joined(separator: " ") == expected }
        XCTAssertEqual(
            matches.count, 1,
            "\(workflowPath): want exactly one step whose run payload is `\(expected)`, "
                + "found \(matches.count)")
        guard let step = matches.first else { return }
        XCTAssertEqual(step.name, "Lint plan assertions")
        XCTAssertNil(
            step.continueOnError,
            "\(step.name): a continue-on-error step cannot be a check")
        XCTAssertNil(
            step.ifCondition,
            "\(step.name): must NOT carry the docs-only guard (it carries "
                + "\(step.ifCondition ?? "")). A plan is docs/**, so a plan-carrying PR is "
                + "docs-only; guarding this step switches the linter off for exactly the "
                + "PRs it exists to check. If you are adding a guard on purpose, change "
                + "this test in the same commit so the decision is reviewed.")
        guard let docsOnlyStep = stepNamed("Complete docs-only PR", in: all) else {
            return XCTFail("\(workflowPath): missing the `Complete docs-only PR` step")
        }
        XCTAssertLessThan(
            step.index, docsOnlyStep.index,
            "\(step.name) must run before the docs-only completion step, so a plan-only PR "
                + "is linted before the job short-circuits")
    }
```

- [ ] **Step 5: Run the workflow tests**

```bash
swift test --filter WorkflowShapeTests 2>&1 | tail -5
```

Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 6: Drill G14 — guarding the lint step must redden**

```bash
SCRATCH=/tmp/slice56-drill-o
mkdir -p "$SCRATCH"
cp .github/workflows/swift-ci.yml "$SCRATCH/swift-ci.yml.bak"
sed -i '' "s|^      - name: Lint plan assertions|      - name: Lint plan assertions\n        if: steps.change-scope.outputs.docs_only_pr != 'true'|" .github/workflows/swift-ci.yml
swift test --filter WorkflowShapeTests > "$SCRATCH/drill-o.txt" 2>&1
if grep -q "must NOT carry the docs-only guard" "$SCRATCH/drill-o.txt"; then
  echo "drill_o=red_as_expected"
else
  echo "drill_o=DID_NOT_REDDEN — the guard-absence pin does not bind"
fi
cp "$SCRATCH/swift-ci.yml.bak" .github/workflows/swift-ci.yml
if git diff --quiet -- .github/workflows/swift-ci.yml; then echo "workflow_restored=yes"; else echo "workflow_restored=NO"; fi
```

Expected: `drill_o=red_as_expected` and `workflow_restored=yes`.

- [ ] **Step 7: Drill G12 and G20 — the ratchet and the seam**

| Drill | Edit | Expected red |
|---|---|---|
| (l) | add `"2026-09-04-artifact-shape-enforcement.md"` to `EXEMPT_PLANS` | `testExemptListHasExactlyTheExpectedCount` (57 vs 56) **and** `testNoExemptEntryIsDatedOnOrAfterTheCutoff` — two independent reds, which is the point of having both |
| (m) | add `"2026-01-01-nonexistent.md"` to `EXEMPT_PLANS` | `testEveryExemptEntryExistsOnDisk` |
| (u) | delete one entry from `EXEMPT_PLANS` (say the 2026-06-13 one) | `testExemptListHasExactlyTheExpectedCount` (55 vs 56) **and** `testEveryNonExemptPlanLintsClean`, because the displaced plan now enters the linted set. Record both: the second is the check that closes the swap |

After each: restore the script and confirm `git diff --quiet -- .github/scripts/lint-plan-assertions.sh` succeeds.

- [ ] **Step 8: Verify the whole suite and commit**

```bash
swift test > /tmp/slice56-t5-suite.txt 2>&1
tail -3 /tmp/slice56-t5-suite.txt
./.github/scripts/lint-plan-assertions.sh
git add Tests/ViewportBenchmarksTests/PlanLintTests.swift Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift .github/workflows/swift-ci.yml
git commit -m "ci: run the plan linter, and pin its exemption ratchet

PlanLintTests runs the script over the repository and pins the exemption set
by property rather than by copying 56 filenames into Swift: exact count, every
entry on disk, nothing dated on or after the cutoff, and the script's own exit
0 -- which is what closes the swap the first three leave open. The CI step is
deliberately unguarded by docs_only_pr, because a plan IS docs/** and the
guarded form would switch the linter off for exactly the PRs it checks; the
absence of the guard is itself pinned."
```

Expected: failure count 0; `lint=pass files=1 violations=0`; test count is Task 4's total + 5.

---

### Task 6: the conventions, and the ledger

**Files:**
- Modify: `AGENTS.md` (the `Conventions that matter` list around line 779; `### Plan-assertion conventions (D-2)` at lines 793–813; the `## Commands` block)
- Modify: `docs/superpowers/debt-ledger.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

**Guarantees added:** none — this task writes prose and ledger rows; the guards that enforce them shipped in Tasks 1–5.

- [ ] **Step 1: Rewrite D-2 rule 1**

In `AGENTS.md`, replace rule 1 of `### Plan-assertion conventions (D-2)` with:

```markdown
1. Never put a check on the left of a pipe whose right side is
   `tail`/`tee`/`jq`/`wc`/`rg` — the pipeline's status is the right side's, and a
   script's own `set -o pipefail` does not reach the invoking shell. **Do not reach
   for `${PIPESTATUS[0]}`**: agent command blocks here run under **zsh**, which does
   not populate that array at all (it spells it `pipestatus` and indexes from 1), so
   the expansion is **empty** and `[ "" -eq 0 ]` evaluates **true** — the assertion
   inverts into a pass, which is the exact defect this section exists to prevent.
   In order of preference: **do not pipe** —
   `if ! cmd > /dev/null 2>&1; then echo "check=fail"; else echo "check=pass"; fi`;
   when both the output and the status are wanted, redirect to a file first
   (`cmd > out.txt 2>&1; status=$?`) and read the file afterwards; when a pipeline is
   genuinely unavoidable, wrap the whole of it — `bash -c 'set -o pipefail; …'` — and
   test that `bash -c`'s own status. The ban is addressed to plans and verification
   records, not to scripts: all five `.github/scripts/*.sh` are bash with a shebang,
   and none uses `PIPESTATUS`. `.github/scripts/lint-plan-assertions.sh` enforces
   this rule mechanically (R1) for every non-exempt plan.
```

- [ ] **Step 2: Add the guarantee-inventory convention**

Append as rule 5 in the same section:

```markdown
5. **Every task enumerates the standing guarantees it adds, and carries a drill for
   each.** The per-task inventory is the AUTHORITY; a spec's drill list is a lower
   bound, never a closed set. The mechanism this exists for: TDD writes a test
   red-first when the test *specifies* behaviour, but a cost pin, a probe-count bound,
   or a fixture that must separate two indices **measures** the implementation instead
   — so it is written green from birth and nothing forces the question "can this pin
   fail?" at the moment it is written. Slice 55b shipped four such guarantees undrilled
   and caught them in two later passes; slice 55b's own record then cited the spec's
   closed list as authority for not drilling a fifth. `lint-plan-assertions.sh` checks
   the structure (R4) — that each task names its guarantees and that each named
   guarantee has a step mentioning a drill for it. It cannot check that a drill drills;
   that half is yours.
```

- [ ] **Step 3: Add the three record-writing lines**

In `AGENTS.md`'s `Conventions that matter` list, extend the `Verification is evidence` bullet with:

```markdown
- **A record cannot carry facts about its own branch.** The commit that records a
  fact changes it: slice 55b's record stated its own commit count wrong twice and
  called a hosted run "the current HEAD", false two commits later. So (a) the
  post-merge proof lands on a separate `slice-N-hosted-proof` branch — the practice
  in slices 54, 55a and 55b — and (b) a self-referential fact is phrased
  **re-checkably**: a per-head "commit → run id" table rather than a bare run id,
  "nineteen by SHA plus this one" rather than a count that the next commit falsifies.
```

- [ ] **Step 4: Register the script in the Commands block**

In `AGENTS.md`'s `## Commands` fence, beside the four existing script lines, add:

```markdown
./.github/scripts/lint-plan-assertions.sh                     # lint every non-exempt plan (D-2/D-17/D-35 shape rules)
./.github/scripts/lint-plan-assertions.sh --self-test         # linter self-test (no repository read)
```

and update the sentence that reads "All four scripts' `--self-test` are also driven by `swift test`" to say **five**.

- [ ] **Step 5: Update the ledger**

Five rows change status and two are appended. Discharge links point at the **verification record**, not this plan: a plan is a promise, a record is evidence.

| Row | New status | Note |
|---|---|---|
| D-27 | `discharged(...)` | all twelve pinned; whole-file `--gate` census closes the one-level-up hole |
| D-39 | `discharged(...)` | `DebtLedgerShapeTests`, ratchet over a clean artifact |
| D-37 | `discharged(...)` | three lines in `AGENTS.md` |
| D-17 | `discharged(...)` | rule 1 rewritten **and** mechanized as R1 |
| D-9 | `scheduled(node-6)` | rehomed at the slice-56 brainstorm, 2026-09-04: it is calibration arithmetic and node 6 is the next `harvest → derive` event, where its read-set already lives |

**D-34 and D-35 are AMENDED IN PLACE, not discharged** — the D-9/D-15 precedent. Append to each statement rather than rewriting it:

- D-34: "**Shape half discharged by slice 56** (`lint-plan-assertions.sh` R1–R3, run from `swift test` and from an unguarded CI step). The **semantic half stays open**: none of the four defects this row measured is shape-detectable — a regex that could not match, a check inverted under an ordering the plan permits, a count not scoped to its job, and a Python loop that never rebinds its variable. What the linter answers is D-17 and D-2 rule 4, and slice 56's spec §2.1 says so rather than claiming the row."
- D-35: "**Structural half discharged by slice 56** (R4: every task names its guarantees; every named guarantee needs a step mentioning a drill). **R4 buys a prompt, not a proof** — a task satisfies it with an empty inventory, or with a drill step that names a drill it does not perform. The question is now asked at authoring time, which is what this row measured as missing; whether the answer is honest stays a reader's job."

Append two rows:

- **D-40** (P3): "Three assertion classes stay unmechanized by `lint-plan-assertions.sh`: D-2 rule 1 (a check on the left of a pipe) and rule 3 (a plan asserting its own HEAD) need semantics rather than shape, and plan-supplied **analysis code** — slice 55a's `predict.py`, whose checks sat inside a loop that never rebound its scenario variable — is a class D-2's four shell-shaped rules do not name at all. Named at the slice-56 spec (D56-7) rather than left as an unmentioned gap."
- **D-41** (P3): "`BenchmarkMode.flagName` is a **pinned** third copy of every flag spelling, not a deleted one (`BenchmarkOptions.parse`'s case labels are the first, `swift-ci.yml`'s payloads the second). Having `parse` derive its cases from `flagName` would delete the copy instead of pinning it and is strictly better; it rewrites every per-flag \"cannot be combined with another mode\" message and its tests, which slice 56 declined as option-parsing surgery inside a slice whose fingerprint is \"nothing measured moves\"."

- [ ] **Step 6: Verify the ledger still satisfies its own guard**

```bash
swift test --filter DebtLedgerShapeTests 2>&1 | tail -5
```

Expected: `Executed 4 tests, with 0 failures`, now over 41 rows with ids `D-1`…`D-41`. If `testRowIdsAreUniqueAndContiguousFromOne` fails, the two new rows were numbered wrong.

- [ ] **Step 7: Commit**

```bash
swift test > /tmp/slice56-t6-suite.txt 2>&1
tail -3 /tmp/slice56-t6-suite.txt
git add AGENTS.md docs/superpowers/debt-ledger.md
git commit -m "docs: rewrite D-2 rule 1, add the guarantee-inventory convention, settle the ledger

Rule 1 recommended the zsh pipe-status array by name -- an idiom that expands
empty under this repo's zsh, where [ \"\" -eq 0 ] is true, so the rule written
to prevent un-failable assertions produced one. Replaced with three
shell-agnostic idioms in preference order. Adds the per-task guarantee
inventory as rule 5, and the record-writing convention D-37 asked for.

Ledger: D-27, D-39, D-37 and D-17 discharged; D-9 rehomed to node 6; D-34 and
D-35 amended in place, since slice 56 ships their shape half and not their
semantic half; D-40 and D-41 appended."
```

---

### Task 7: verification record and hosted proof

**Files:**
- Create: `docs/superpowers/verification/2026-09-04-artifact-shape-enforcement.md`
- Later, on a separate `slice-56-hosted-proof` branch: the post-merge evidence section

**Interfaces:**
- Consumes: every drill output recorded in Tasks 1–6.
- Produces: the evidence the post-slice review reads.

**Guarantees added:** none — this task records evidence; it adds no guarantee of its own.

- [ ] **Step 1: Record the invariant fingerprint**

```bash
SCRATCH=/tmp/slice56-fingerprint
mkdir -p "$SCRATCH"
swift build -c release > "$SCRATCH/build.txt" 2>&1
echo "build_exit=$?"
if [ -z "$(rg -n "Foundation" Sources/TextEngineCore)" ]; then
  echo "foundation_scan=empty"
else
  echo "foundation_scan=NON_EMPTY"
fi
for MODE in --gate --variable-height --variable-height-mutation --structural-mutation --bulk-structural-mutation --line-query --line-geometry-query --column-query --column-geometry-query --point-query --point-geometry-query --realistic-provider; do
  swift run -c release ViewportBenchmarks -- "$MODE" --gate >> "$SCRATCH/gates.txt" 2>&1 || true
done
grep -c 'gate=pass' "$SCRATCH/gates.txt"
```

Expected: `build_exit=0`, `foundation_scan=empty`, and 46 `gate=pass` lines. Extract the 46 checksums into the record and diff them against slice 55b's — they must be byte-identical.

- [ ] **Step 2: Record the test-count delta**

The fingerprint is a **pair with a delta**, not the phrase "grows only by the new tests", which names no number and cannot be falsified:

```bash
git stash list > /dev/null
BASELINE=$(git show f9ffe58:Package.swift > /dev/null 2>&1 && echo "slice-55b-merge")
echo "baseline_ref=$BASELINE"
swift test > /tmp/slice56-final-suite.txt 2>&1
tail -3 /tmp/slice56-final-suite.txt
```

Record: the slice-55b test count (from that slice's record), this slice's count, the delta, and the enumeration of new test functions — 4 (Task 1) + 4 (Task 2) + 4 (Task 3) + 4 + 1 (Task 5) = 17. If the delta and the enumeration disagree, one of them is wrong; find out which before writing the record.

- [ ] **Step 3: Write the record**

Create `docs/superpowers/verification/2026-09-04-artifact-shape-enforcement.md` with, at minimum: the spec and plan links; per-task command transcripts; **every drill (a)–(w) with its recorded red text**; the 46-checksum diff; the test-count pair and delta; the linter's `lint=pass` line; and a section reserved for the hosted runs. Facts about this branch are phrased re-checkably per the convention Task 6 writes — a per-head "commit → run id" table, not "the current HEAD".

- [ ] **Step 4: Open the PR and read both hosted runs at STEP level**

A green job can hide a dead step. Read the step logs, not the job conclusion: confirm the twelve gates print `gate=pass`, the new `Lint plan assertions` step prints `lint=pass`, and the host job's `swift test` line reports 0 failures.

```bash
gh pr create --fill --base main
gh run list --limit 5
```

- [ ] **Step 5: Record the post-merge proof on a separate branch**

After merge, on `slice-56-hosted-proof`: record the post-merge `push` run id, its step-level readings, and the per-head table. A separate branch because a record cannot carry facts about its own branch — the convention this slice writes down (D-37).

---

## Plan self-review

**1. Spec coverage.** AC1–AC2 → Task 1. AC3–AC6 → Task 2. AC7–AC8 → Task 4. AC9–AC10 → Tasks 4 and 5. AC11–AC12 → Task 6. AC13 → Task 3. AC14 → Task 5. AC15 → every task's **Guarantees added** block plus the drill steps. AC16 → Task 7 Steps 1–2. AC17 → Task 7 Steps 4–5. Guarantees G1–G21 are claimed by Tasks 1–5 and drilled there; G3 carries the simultaneous form (c) plus the attribution form (c2), as the spec requires.

**2. Placeholder scan.** No "TBD", no "TODO", no "similar to Task N". Every code step carries its code in full. Task 1 Step 6 explicitly says the multi-line `sed` form does **not** work and to edit by hand — that is a warning, not a placeholder.

**3. Assertion audit (D-2, as this slice rewrites it).** No `${PIPESTATUS[0]}` in any command block. Every check either uses `if ! … ; then … else … fi`, `[ -z "$(…)" ]`, `git diff --quiet`, or a `grep -q` inside an `if` that prints both branches. `SCRATCH` is assigned in **every** block that uses it. `swift test` output is redirected to a file and read with `tail`/`grep` rather than piped into a check. Task 4 Step 3's expected output (`files=1`) is a number that changes if the exemption list is wrong, so it can fail.

**3a. The rule's sharp edge, found by running it against this plan.** An emulation of R1–R4 over this document found four violations, all real: one guarantee listed without a drill naming it, one `sed` that had to spell the banned token to neutralize it, and **two commit-message bodies that quoted the token while explaining the rule**. The first three are plan defects and are fixed. The fourth is the rule being strict where prose has entered a shell fence: R1 bans the token in a `bash`/`sh` fence, and a `git commit -m "…"` body sits inside one. Not exempted — an exemption would need quote-aware parsing, and the cost of writing around it is one word ("the zsh pipe-status idiom"). Recorded here rather than discovered by the next author.

**4. Type consistency.** `flagName` is `String?` in Task 1 and consumed as `String?` by `gateCommand(_:)` in Task 2. `GateStepSpec` carries `mode` and `stepName` and derives `command`; every later reference uses `spec.command`, not a stored literal. `runScript` in Task 5 returns the same `(exitCode, stdout, stderr)` tuple `runProcess` produces in `ProcessSupport.swift`.

**5. Ordering.** Task 2 needs Task 1's `flagName`. Task 5 needs Task 4's script and seam. Task 6's ledger edit must come after Task 3, or `DebtLedgerShapeTests` would be written against a ledger the same slice then changes. Task 7 is last by construction.
