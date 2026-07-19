# Realistic-provider CI-gate promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the realistic 100k-line / 10 MB viewport-compute benchmark to the **12th merge-blocking CI gate** by wiring `--realistic-provider --gate` into `swift-ci.yml`, replacing the PR-only `continue-on-error` base-vs-head relative observation.

**Architecture:** Zero engine-behavior change — `runRealisticProviderBenchmarks(enforceGate:)` already honours `--gate`. The work is: (1) add a blocking gate step + delete the observation step + delete its now-orphaned script, driven test-first by generalizing `WorkflowShapeTests` to a two-entry `pinnedGateSteps` table; (2) retire the narrative-rot comments that go false once the gate runs (a source comment + four `AGENTS.md` passages); (3) record local verification with a break→red→revert→green liveness proof. Hosted proof (AC7) is discharged post-merge in the PR + push runs.

**Tech Stack:** Swift 6.0 (SwiftPM), XCTest, GitHub Actions YAML, bash. No third-party dependencies. The workflow-shape test hand-rolls a narrow YAML reader (no YAML parser — the package is zero-dependency).

## Global Constraints

Copied from the spec; every task's requirements implicitly include these:

- **No Foundation in `Sources/TextEngineCore`.** This slice does not touch the core; `rg -n Foundation Sources/TextEngineCore` must stay empty (exit 1). The one Swift file touched (`Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`) is comment-only and is not in the core.
- **Zero new dependencies.** No package added; the workflow reader stays hand-rolled.
- **One mode flag per benchmark invocation**; `--gate` is valid with `--realistic-provider` (already true — `BenchmarkMode.isGateable` includes `.realisticProvider`).
- **Budgets are derived, never hand-typed.** No budget literal changes this slice; the committed realistic budget (p95 97_000 ns / p99 200_000 ns) is already `GateFloorTests`-enforced and reproduces from the corpus.
- **Exactly one CI step may print a given mode's benchmark summary lines** (harvest-double-count rule) — the reason the observation step is *removed*, not kept.
- Commit messages end with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer. One logical change per commit; conventional-commit prefixes (`ci:`, `docs:`).

**Branch:** `slice-45-realistic-provider-ci-gate-promotion` (already created; the design + spec-refinement commits are on it).

---

### Task 1: Wire and pin the realistic-provider gate

Test-first: generalize `WorkflowShapeTests` to a two-entry table so the new realistic entry is **red** (no such workflow step yet), then add the workflow step to turn it **green**, in one commit. Removing the observation step and deleting its script land in the same commit (they orphan together).

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` (constants block, test class body, two comment blocks)
- Modify: `.github/workflows/swift-ci.yml` (add realistic gate step; delete observation step)
- Delete: `.github/scripts/realistic-relative-observation.sh`

**Interfaces:**
- Consumes: the existing file-scope helpers in `WorkflowShapeTests.swift` — `workflowPath`, `hostJobKey`, `hostJobSteps() throws -> [WorkflowStep]`, `stepNamed(_:in:) -> WorkflowStep?`, `parseStep`, and the `WorkflowStep` struct — all unchanged by this task.
- Produces: a file-scope `struct GateStepSpec { flag, stepName, command, afterStepName, beforeStepName }`, a `func gateCommand(_ flag: String) -> String`, and `let pinnedGateSteps: [GateStepSpec]` with two entries; six `test…EachPinnedGate…` methods iterating that table.

- [ ] **Step 1: Replace the constants block (introduce the table).**

In `WorkflowShapeTests.swift`, replace the constants that currently span from `private let pointGeometryFlag = …` (line 31) through the end of the `pointGeometryCommand` definition (line 49) — i.e. everything from line 31 to line 49 inclusive, which also contains `pointQueryStepName`, `memoryShapeStepName`, `docsOnlyGuard`, and the `// The step's exact shape IS the invariant…` comment — with:

```swift
private let docsOnlyGuard = "steps.change-scope.outputs.docs_only_pr != 'true'"
private let memoryShapeStepName = "Run memory shape diagnostic"
private let pointGeometryFlag = "--point-geometry-query"
private let realisticFlag = "--realistic-provider"

// The exact whitespace-joined `run:` payload every gate step must carry. Pinned as a
// whole command rather than probed for tokens: a step-level token count cannot see a
// second invocation inside one `|` block scalar or a trailing `|| true`, and both
// disarm the gate.
private func gateCommand(_ flag: String) -> String {
    "swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks "
        + "-- \(flag) --gate"
}

// One row per gate step whose blocking shape is pinned, with the ordering anchors it
// must sit between. A gate joins this table by hand when it is promoted (see the header
// note above).
private struct GateStepSpec {
    let flag: String            // the mode flag whose presence identifies the step
    let stepName: String        // the exact `- name:` the step must carry
    let command: String         // the exact whitespace-joined `run:` payload
    let afterStepName: String   // the step it must sit after
    let beforeStepName: String  // the step it must sit before
}

private let pinnedGateSteps: [GateStepSpec] = [
    GateStepSpec(
        flag: pointGeometryFlag,
        stepName: "Run point geometry query benchmark gate",
        command: gateCommand(pointGeometryFlag),
        afterStepName: "Run point query benchmark gate",
        beforeStepName: memoryShapeStepName),
    GateStepSpec(
        flag: realisticFlag,
        stepName: "Run realistic provider benchmark gate",
        command: gateCommand(realisticFlag),
        afterStepName: "Run point geometry query benchmark gate",
        beforeStepName: memoryShapeStepName),
]
```

Note: `workflowPath` (line 29) and `hostJobKey` (line 30) stay above this block, untouched.

- [ ] **Step 2: Replace the test-class body (iterate the table).**

Replace the entire `final class WorkflowShapeTests: XCTestCase { … }` (lines 179–277) with:

```swift
final class WorkflowShapeTests: XCTestCase {

    // Resolve a spec's step(s) by FLAG, asserting the set is non-empty first: a test that
    // quantified over an empty set would be vacuously green the day the gate was deleted.
    private func steps(for spec: GateStepSpec, in all: [WorkflowStep]) -> [WorkflowStep] {
        let matches = all.filter { $0.runTokens.contains(spec.flag) }
        XCTAssertFalse(
            matches.isEmpty,
            "\(workflowPath): no step in \(hostJobKey) runs \(spec.flag) — the "
                + "\"\(spec.stepName)\" gate is gone")
        return matches
    }

    // Invariant 1. Exactly one step runs each pinned flag. Two steps ran a mode while its
    // budget was observational (a bare correctness run + a continue-on-error gated run);
    // one step cannot be both, and a second printing step double-weights the mode in every
    // future harvest of that run.
    func testExactlyOneStepRunsEachPinnedGate() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            let matches = steps(for: spec, in: all)
            XCTAssertEqual(
                matches.count, 1,
                "\(workflowPath): \(matches.count) steps run \(spec.flag), want exactly 1 — "
                    + "\(matches.map(\.name))")
        }
    }

    // Invariant 2. Exact command equality, not `runTokens.contains("--gate")`. Subsumes the
    // --gate check and forecloses a double invocation inside one `|` block scalar and a
    // trailing `|| true`, both of which a token probe reports as green.
    func testEachPinnedGateRunsExactlyTheExpectedCommand() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            for step in steps(for: spec, in: all) {
                XCTAssertEqual(
                    step.runTokens.joined(separator: " "), spec.command,
                    "\(step.name): run payload is not the expected single gated command.\n"
                        + "  want: \(spec.command)\n"
                        + "  got:  \(step.runTokens.joined(separator: " "))")
            }
        }
    }

    // Invariant 3. THE one that matters: continue-on-error swallows every non-zero exit, so
    // a gated step under it can fail neither on budget nor on failureCount != 0.
    func testNoPinnedGateIsContinueOnError() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            for step in steps(for: spec, in: all) {
                XCTAssertNil(
                    step.continueOnError,
                    "\(step.name): carries continue-on-error: \(step.continueOnError ?? "") — "
                        + "a continue-on-error step cannot be a gate; it swallows budget "
                        + "misses, correctness failures and crashes alike")
            }
        }
    }

    // Invariant 4. The same docs-only guard every sibling gate carries.
    func testEachPinnedGateCarriesTheDocsOnlyGuard() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            for step in steps(for: spec, in: all) {
                XCTAssertEqual(
                    step.ifCondition, docsOnlyGuard,
                    "\(step.name): does not carry the sibling docs-only guard")
            }
        }
    }

    // Invariant 5. The name is the only place a reader learns whether the step is blocking,
    // so a stale "observational" qualifier is a lie in the log of every run.
    func testEachPinnedGateIsNamedForItsSiblings() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            for step in steps(for: spec, in: all) {
                XCTAssertEqual(
                    step.name, spec.stepName,
                    "step running \(spec.flag) is named \"\(step.name)\", want "
                        + "\"\(spec.stepName)\"")
            }
        }
    }

    // Invariant 6. Every pinned gate stays contiguous, ahead of the diagnostics, in the
    // order point-query < point-geometry < realistic < memory-shape.
    func testEachPinnedGateSitsBetweenItsAnchors() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            let matches = all.filter { $0.runTokens.contains(spec.flag) }
            XCTAssertFalse(matches.isEmpty, "no step runs \(spec.flag)")

            guard let after = stepNamed(spec.afterStepName, in: all),
                  let before = stepNamed(spec.beforeStepName, in: all) else {
                XCTFail("\(workflowPath): missing \"\(spec.afterStepName)\" or "
                    + "\"\(spec.beforeStepName)\" — the ordering anchors for \(spec.flag) "
                    + "are gone")
                continue
            }

            for step in matches {
                XCTAssertLessThan(
                    after.index, step.index,
                    "\(step.name) must sit after \"\(spec.afterStepName)\"")
                XCTAssertLessThan(
                    step.index, before.index,
                    "\(step.name) must sit before \"\(spec.beforeStepName)\"")
            }
        }
    }
}
```

- [ ] **Step 3: Rewrite the two now-false comments in the same file.**

3a. Replace the header comment block (lines 8–27, from `// The shape this pins is the one the Slice 16 dead-step trap…` through `// …a design of its own.`) with:

```swift
// The shape these tests pin is the one the Slice 16 dead-step trap destroyed once
// already: a `continue-on-error` step swallows EVERY non-zero exit, so a gated step under
// it is budget-blind AND failure-blind. Nothing else in the repo reads swift-ci.yml, so
// without these tests each gate's blocking shape is verified exactly once, by hand, into a
// verification record: the failure mode GateFloorTests.swift was created to end.
//
// `pinnedGateSteps` is a small EXPLICIT table of the gate steps whose shape is pinned
// (currently --point-geometry-query and --realistic-provider; a gate joins by hand when it
// is promoted). It is deliberately NOT `BenchmarkMode.allCases where isGateable`: that
// quantifier is false for the `.pipeline` default mode, which has no flag at all (it runs
// as a bare `--gate`), and there is no BenchmarkMode -> flag mapping to match against --
// BenchmarkMode exposes only snake_case `outputName`, while the flags live as hand-written
// `case` labels inside BenchmarkOptions.parse. Generalizing to every CI-gated mode needs a
// `flagName` property, a named-and-justified exemption set, and a test pinning the two
// together -- a design of its own.
```

3b. In the `parseStep` comment, replace the sentence that cites the deleted observation step. Find:

```swift
// this function's per-line loop is redundant for key detection. swift-ci.yml:145-148 is a
// still-present, concrete example of exactly that kind of text: a comment on the PR-only
// realistic-provider observation step whose last line reads "...the step is
// continue-on-error." in prose -- and it is the key-anchored prefix match, not comment
// exclusion, that keeps it from being misread as the key there.
```

Replace with:

```swift
// this function's per-line loop is redundant for key detection. (If a step ever carries a
// prose comment that happens to contain "continue-on-error", it is that key-anchored
// prefix match, not comment exclusion, that keeps the prose from being misread as the key.)
```

- [ ] **Step 4: Run the workflow-shape tests to verify the realistic entry is RED.**

Run: `swift test --filter WorkflowShapeTests`
Expected: **FAIL**. The `--realistic-provider` entry has no matching workflow step yet, so every invariant fails for it (e.g. `testExactlyOneStepRunsEachPinnedGate` → `no step in host-tests-and-benchmark-gate runs --realistic-provider — the "Run realistic provider benchmark gate" gate is gone`). The `--point-geometry-query` entry still passes. This RED confirms the table drives the workflow edit.

- [ ] **Step 5: Add the realistic gate step to the workflow.**

In `.github/workflows/swift-ci.yml`, find:

```yaml
      - name: Run point geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate

      - name: Run memory shape diagnostic
```

Replace with:

```yaml
      - name: Run point geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate

      - name: Run realistic provider benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --realistic-provider --gate

      - name: Run memory shape diagnostic
```

- [ ] **Step 6: Delete the observation step and its script.**

6a. In `.github/workflows/swift-ci.yml`, delete the entire step `- name: Observe realistic provider relative performance` — from its `- name:` line (currently 142) through the last line of its `run:` block, `          echo "observation_finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"` (currently 182) — **plus** the single blank line immediately before it, so that the host job's last remaining step becomes `Run RSS memory observation diagnostic`, followed by exactly one blank line before `  ios-cross-target-compile:`.

Verify the removal:
```bash
grep -n "Observe realistic provider\|realistic-relative-observation\|REALISTIC_RELATIVE_OBSERVATION\|observation_finished_at" .github/workflows/swift-ci.yml
```
Expected: **no output** (all gone).

Verify the tail is well-formed (memory-observation step, one blank, next job):
```bash
grep -n "Run RSS memory observation diagnostic\|ios-cross-target-compile:" .github/workflows/swift-ci.yml
```
Expected: the RSS step line, then the `ios-cross-target-compile:` job line a few lines later.

6b. Delete the orphaned script:
```bash
git rm .github/scripts/realistic-relative-observation.sh
```

- [ ] **Step 7: Run tests + the gate to verify GREEN.**

Run: `swift test --filter WorkflowShapeTests`
Expected: **PASS** (both entries).

Run: `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`
Expected: one summary line ending `gate=pass`, carrying `budget_absolute_p99_ns=1666666` (frame-hot-path). Example shape:
`mode=realistic_provider … scenario=100k_lines_10mb_text … budget_p95_ns=97000 budget_p99_ns=200000 … budget_absolute_p99_ns=1666666 … gate=pass checksum=…`

- [ ] **Step 8: Commit.**

```bash
git add Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift .github/workflows/swift-ci.yml
git rm --cached .github/scripts/realistic-relative-observation.sh 2>/dev/null || true
git commit -m "$(cat <<'EOF'
ci: promote realistic-provider to the 12th blocking gate

Wire `--realistic-provider --gate` into swift-ci.yml as a blocking step
(runs on PR and push), replacing the PR-only continue-on-error base-vs-head
relative observation. Pin the new gate in WorkflowShapeTests by generalizing
it to a two-entry `pinnedGateSteps` table {point-geometry, realistic} and
delete the now-orphaned realistic-relative-observation.sh. Enforces the
brief's #1 success criterion (stable scroll on 100k+/10MB docs) as a
merge-blocking regression gate. Zero engine behavior change: the mode already
honours --gate.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

Note: the `git rm` in Step 6b already staged the deletion; the `git add` above stages the two modified files. The `git rm --cached … || true` line is a harmless no-op safety net if the deletion was un-staged.

---

### Task 2: Retire the narrative-rot comments (source comment + AGENTS.md)

No test drives a comment. This task rewrites the passages that describe the *old* observation-only route, which go false the moment Task 1 merges. **Intentional non-edit:** the `## Gate budgets` "a realistic_provider run contributes 8" mentions describe the harvester's shape-2 branch, which is *retained* this slice (it still harvests pre-Slice-45 run logs in retention); those lines stay, as part of the deferred shape-2 cleanup noted in the spec's Non-goals.

**Files:**
- Modify: `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift` (comment above `realisticProviderScenarios()`)
- Modify: `AGENTS.md` (four passages)

**Interfaces:**
- Consumes: nothing from Task 1 at the code level (comment/doc only). Depends on Task 1 having landed the workflow change so the new comments describe the merged reality.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Rewrite the source comment (value-free — point at the workflow/harvester, embed no number).**

In `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`, find the block (currently lines 88–95):

```swift
// This mode's samples reach the corpus by a different route than every other gate's.
// It is the one gated mode CI never runs with --gate: the PR-only observation step runs
// it bare and keeps the raw benchmark output in a temp file, so no `p95_ns=` line for
// this mode ever reaches the hosted log. Its per-repetition values ride inside the
// `mode=realistic_relative_observation` line instead, and
// .github/scripts/harvest-gate-corpus.sh reads them from there. That is why this mode
// was missing from the first corpus, and why its budget was the last one in the suite
// still sitting under the 3x floor after everything else had been re-derived.
```

Replace with:

```swift
// This mode is gated in CI like every other: `--realistic-provider --gate` runs as a
// blocking step (see .github/workflows/swift-ci.yml), so its
// `mode=realistic_provider ... p95_ns=... p99_ns=...` summary line reaches the hosted log
// and .github/scripts/harvest-gate-corpus.sh reads it as the standard shape. Before
// Slice 45 this mode was observation-only: its samples arrived via a
// `mode=realistic_relative_observation` line that a now-removed relative-observation step
// printed, which is why it was the last budget in the suite still under the 3x floor after
// everything else had been re-derived. Those historical rows remain in the corpus
// (append-only).
```

Note: the preceding four lines (83–86, "Budgets derived from hosted Linux x86_64 … Do not hand-edit — re-derive.") stay untouched — they are still true.

- [ ] **Step 2: AGENTS.md — add the realistic gate to the Commands list.**

Find:
```
swift run -c release ViewportBenchmarks -- --point-geometry-query --gate   # (x,y)->(line+box+fraction, cell+box+fraction) 2D geometry blocking CI gate
swift run -c release ViewportBenchmarks -- --memory-shape    # memory-shape invariant; expect invariant=pass
```
Replace with:
```
swift run -c release ViewportBenchmarks -- --point-geometry-query --gate   # (x,y)->(line+box+fraction, cell+box+fraction) 2D geometry blocking CI gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate   # realistic 100k/10MB scroll compute blocking CI gate
swift run -c release ViewportBenchmarks -- --memory-shape    # memory-shape invariant; expect invariant=pass
```

- [ ] **Step 3: AGENTS.md — update the CI pipeline chain and gate count (eleven → twelve).**

Find:
```
  (blocking) → `--point-geometry-query --gate` (blocking) →
  `--memory-shape`
  → `--memory-observation` → realistic relative
  observation (PR-only,
  `continue-on-error`). Eleven blocking gates: synthetic, static variable-height,
  mutation variable-height, structural-mutation, bulk-structural-mutation,
  line-query, line-geometry-query, column-query, column-geometry-query,
  point-query, and point-geometry-query — all **fail the job on perf
```
Replace with:
```
  (blocking) → `--point-geometry-query --gate` (blocking)
  → `--realistic-provider --gate` (blocking) →
  `--memory-shape`
  → `--memory-observation`. Twelve blocking gates: synthetic, static variable-height,
  mutation variable-height, structural-mutation, bulk-structural-mutation,
  line-query, line-geometry-query, column-query, column-geometry-query,
  point-query, point-geometry-query, and realistic-provider — all **fail the job on perf
```

- [ ] **Step 4: AGENTS.md — rewrite the Gate budgets realistic paragraph.**

Find:
```
`--realistic-provider` is the one gated mode CI never runs with `--gate` (the
PR-only observation step runs it bare and keeps the benchmark output in a temp
file), so its samples reach the corpus only through the
`mode=realistic_relative_observation` line, which the harvester knows how to read.
That is why it was the last budget still under the floor after the rest of the
suite had been re-derived. Every gated scenario now carries corpus rows, and
`GateFloorTests` fails if a new one ever doesn't.
```
Replace with:
```
`--realistic-provider` runs as a blocking `--gate` step like every other gated mode
(Slice 45), so its `p95_ns=`/`p99_ns=` summary line reaches the hosted log and the
harvester reads it as the standard shape. Before Slice 45 it was the one gated mode CI
never ran with `--gate`: a PR-only relative-observation step printed its samples inside a
`mode=realistic_relative_observation` line instead, which is why it was the last budget
still under the floor after the rest of the suite had been re-derived. Those historical
shape-2 rows remain in the corpus (append-only); the harvester still reads that line so
pre-Slice-45 run logs still in retention harvest correctly, and that branch retires once
they age out. Every gated scenario carries corpus rows, and `GateFloorTests` fails if a
new one ever doesn't.
```

- [ ] **Step 5: AGENTS.md — update the Package layout WorkflowShapeTests description.**

Find:
```
  `.github/workflows/swift-ci.yml` and pins the point-geometry-query gate step's
  shape — exactly one step carries the flag, its `run:` payload **equals** the
  expected gated command, it is not `continue-on-error`, it carries the docs-only
  guard, it is named `Run point geometry query benchmark gate`, and it sits
  between the point-query gate and the memory-shape diagnostic. Equality rather
```
Replace with:
```
  `.github/workflows/swift-ci.yml` and pins each promoted gate step's shape from a
  small explicit `pinnedGateSteps` table (currently the point-geometry-query and
  realistic-provider gates) — for each: exactly one step carries the flag, its `run:`
  payload **equals** the expected gated command, it is not `continue-on-error`, it
  carries the docs-only guard, it is named for its siblings, and it sits between its
  ordering anchors (the tail order is point-query < point-geometry < realistic <
  memory-shape). Equality rather
```

- [ ] **Step 6: Sanity-build and grep for residual false narrative.**

Run: `swift build -c release`
Expected: `Build complete!` (comment-only change; no behavior).

Run:
```bash
grep -rn "one gated mode CI never runs\|never run with \`--gate\`\|Eleven blocking gates\|realistic relative observation" AGENTS.md Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
```
Expected: **no output** — every soon-false narrative site is rewritten.

- [ ] **Step 7: Commit.**

```bash
git add Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift AGENTS.md
git commit -m "$(cat <<'EOF'
docs: retire the realistic observation-only narrative

Rewrite the corpus-route comment above realisticProviderScenarios() and four
AGENTS.md passages (Commands list, CI gate chain + count, Gate budgets
paragraph, Package layout WorkflowShapeTests) to describe the standard
shape-1 gate route Slice 45 introduces. Comment/doc only — no code, budget,
or behavior change. The harvester's shape-2 branch and its "contributes 8"
mentions stay (retained for pre-Slice-45 run logs in retention).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Local verification record + liveness proof

Record the actual verification commands and outputs, prove the new gate's `WorkflowShapeTests` pin is *live* (break → red → revert → green), and confirm the diff is confined. Hosted proof (AC7) is discharged post-merge in the PR + push runs and appended to this record then.

**Files:**
- Create: `docs/superpowers/verification/2026-07-19-realistic-provider-ci-gate-promotion.md`

**Interfaces:**
- Consumes: the merged state of Tasks 1–2 on the slice branch.
- Produces: the verification record (evidence artifact; nothing consumes it in code).

- [ ] **Step 1: Run the full local verification suite and capture outputs.**

```bash
swift build -c release
swift test 2>&1 | tail -5                                   # expect "0 failures"; record the exact test count
swift run -c release ViewportBenchmarks -- --realistic-provider --gate   # expect gate=pass, budget_absolute_p99_ns=1666666
swift run -c release ViewportBenchmarks -- --gate 2>&1 | grep -c "gate=pass"   # synthetic gates still pass
rg -n Foundation Sources/TextEngineCore ; echo "exit=$?"    # expect empty, exit=1
```
Record each command's output verbatim in the doc.

- [ ] **Step 2: Prove the new gate's WorkflowShapeTests pin is live (break → red → revert → green).**

```bash
# Disarm the realistic gate the way the pin is meant to catch: make it continue-on-error.
cp .github/workflows/swift-ci.yml /tmp/swift-ci.yml.bak
perl -0pi -e 's/(      - name: Run realistic provider benchmark gate\n        if: steps.change-scope.outputs.docs_only_pr != .true.\n)/$1        continue-on-error: true\n/' .github/workflows/swift-ci.yml
swift test --filter WorkflowShapeTests 2>&1 | tail -20      # expect FAIL naming the realistic step (testNoPinnedGateIsContinueOnError)
cp /tmp/swift-ci.yml.bak .github/workflows/swift-ci.yml     # revert
swift test --filter WorkflowShapeTests 2>&1 | tail -3       # expect PASS
git status --short                                          # expect empty — tree byte-clean, no stray file
```
Record the RED failure message, the restored PASS, and the clean `git status`.

- [ ] **Step 3: Confirm the diff is confined to the expected paths.**

```bash
git diff --name-only main...HEAD
```
Expected exactly: `AGENTS.md`, `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`, `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`, `.github/workflows/swift-ci.yml`, the deleted `.github/scripts/realistic-relative-observation.sh`, and the three slice docs (`docs/superpowers/specs/…-design.md`, `docs/superpowers/plans/…`, `docs/superpowers/verification/…`). No `Sources/TextEngineCore`, no provider, no budget literal, no corpus, no `derive-gate-budgets.sh`.

- [ ] **Step 4: Write the verification record.**

Create `docs/superpowers/verification/2026-07-19-realistic-provider-ci-gate-promotion.md` with sections: **Summary**, **Local checks** (a table of command → result from Steps 1–3), **Guard-is-live** (the break→red→revert→green transcript), **Diff confinement** (the `--name-only` output), and a **Hosted CI — Pending** section listing AC7 (three required jobs green; 12 blocking gate steps present + passing at *step level* on both the PR-head and post-merge push runs; realistic `gate=pass`; host tests green) with placeholders for the two run IDs, to be filled after CI.

- [ ] **Step 5: Commit.**

```bash
git add docs/superpowers/verification/2026-07-19-realistic-provider-ci-gate-promotion.md
git commit -m "$(cat <<'EOF'
docs: record slice 45 local verification

Local build/test/gate outputs, the WorkflowShapeTests break->red->revert->green
liveness proof for the new realistic gate, and diff confinement. Hosted AC7
proof pending; discharged post-merge in the PR + push runs.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:
- Change set §1 (workflow: add gate + remove observation) → Task 1 Steps 5–6. §2 (WorkflowShapeTests table + false-comment fixes) → Task 1 Steps 1–3. §3 (delete script) → Task 1 Step 6b. §4 (AGENTS.md ×4) → Task 2 Steps 2–5. §5 (RealisticProviderBenchmark.swift comment) → Task 2 Step 1.
- AC1 (blocking, non-continue-on-error, docs-only guard, PR+push) → Task 1 Steps 5, 7 + WorkflowShapeTests invariants 3–4. AC2 (observation gone, script deleted) → Task 1 Step 6 + Task 3 Step 3. AC3 (12 gates contiguous) → invariant 6. AC4 (pin live) → Task 3 Step 2. AC5 (test/build/Foundation) → Task 3 Step 1. AC6 (gate=pass + diff confined) → Task 1 Step 7 + Task 3 Steps 1, 3. AC7 (hosted) → Task 3 Step 4 (Pending section; discharged post-merge).
- Decision 4 transitional-window wrinkle: no code action (documented behavior) — correctly no task.

**2. Placeholder scan** — no "TBD"/"handle edge cases"/"similar to Task N"; every code/doc step carries its full old→new text. The only deferred item (AC7 hosted run IDs) is explicitly post-merge, not a plan placeholder.

**3. Type consistency** — `GateStepSpec` fields (`flag`, `stepName`, `command`, `afterStepName`, `beforeStepName`) defined in Task 1 Step 1 are used identically in Step 2's six methods; `gateCommand(_:)`, `pinnedGateSteps`, `realisticFlag`, `memoryShapeStepName`, and the reused `hostJobSteps()`/`stepNamed(_:in:)`/`WorkflowStep` names all match. The workflow step name `Run realistic provider benchmark gate` and flag `--realistic-provider` are spelled identically across the test table, the workflow YAML, and the AGENTS.md passages.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-19-realistic-provider-ci-gate-promotion.md`.
