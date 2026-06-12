# Variable-Height CI Gate Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the variable-height benchmark to a blocking hosted CI gate and consolidate variable-height memory-shape diagnostics into the common summary path.

**Architecture:** `TextEngineCore` stays unchanged. `ViewportBenchmarks` keeps ownership of benchmark gates and diagnostics: `MemoryShapeDiagnostics.swift` returns one `MemoryShapeSummary` model for fixed, large-text, and variable-uniform rows, while `.github/workflows/swift-ci.yml` runs the existing `--variable-height --gate` mode as a blocking step. Verification records local gates, normalized memory-shape output, cross-target compile, and hosted PR/post-merge evidence.

**Tech Stack:** Swift 6.0 package, `ViewportBenchmarks` executable, GitHub Actions, ripgrep, GitHub CLI. Spec: `docs/superpowers/specs/2026-06-12-variable-height-ci-gate-promotion-design.md`.

---

## Scope Check

This plan implements the approved Slice 15 design:

```text
docs/superpowers/specs/2026-06-12-variable-height-ci-gate-promotion-design.md
```

This slice covers one subsystem area: benchmark and CI evidence for the already
merged variable-height layout path.

This plan does not change:

- `Sources/TextEngineCore`
- `Tests/TextEngineCoreTests`
- `Package.swift`
- variable-height public API
- benchmark budgets
- hosted WASM behavior
- repository branch-protection or ruleset settings

## File Structure

- Modify `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`: delete the
  variable-only summary and formatter, return `MemoryShapeSummary` from
  `runVariableMemoryShapeScenario(lineCount:)`, preserve
  `variableCoreOwnedBytesEstimate()`, and keep the cross-variable
  `coreOwnedBytes` consistency check.
- Modify `.github/workflows/swift-ci.yml`: promote the variable-height benchmark
  step from observation-only to blocking `--gate`.
- Modify `AGENTS.md`: update the CI paragraph so the durable repository guide
  describes `--variable-height --gate` as a blocking step.
- Create `docs/superpowers/verification/2026-06-12-variable-height-ci-gate-promotion.md`:
  record local verification, memory-shape output, workflow scan, hosted PR run,
  and post-merge push run.
- Leave `TextEngineCore` and package manifest files untouched.

## Task 1: Preflight Current State

**Files:**
- Read: `docs/superpowers/specs/2026-06-12-variable-height-ci-gate-promotion-design.md`
- Read: `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`

- [ ] **Step 1: Confirm the approved spec is present**

Run:

```bash
rg -n "Variable-Height CI Gate Promotion Design|variableCoreOwnedBytesEstimate|cross-variable|Run variable-height benchmark gate" docs/superpowers/specs/2026-06-12-variable-height-ci-gate-promotion-design.md
```

Expected: command exits `0`; output includes all four patterns.

- [ ] **Step 2: Confirm the current memory-shape diagnostic still has the duplicate variable path**

Run:

```bash
rg -n "VariableMemoryShapeSummary|formatVariableMemoryShapeSummary|referenceVariableCoreOwnedBytes|variableCoreOwnedBytesEstimate" Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
```

Expected: command exits `0`; output includes `VariableMemoryShapeSummary`,
`formatVariableMemoryShapeSummary`, `referenceVariableCoreOwnedBytes`, and
`variableCoreOwnedBytesEstimate`.

- [ ] **Step 3: Confirm the current variable memory-shape output is not normalized yet**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape | rg "provider=variable_uniform.*visible_lines="
```

Expected: command exits `1` with no output, because current `variable_uniform`
rows do not yet include `visible_lines`.

- [ ] **Step 4: Confirm the current workflow is observation-only**

Run:

```bash
sed -n '24,40p' .github/workflows/swift-ci.yml
```

Expected output includes:

```yaml
      - name: Run variable-height benchmark observation
        continue-on-error: true
        run: swift run -c release ViewportBenchmarks -- --variable-height
```

Run:

```bash
rg -n "swift run -c release ViewportBenchmarks -- --variable-height --gate" .github/workflows/swift-ci.yml
```

Expected: command exits `1` with no output.

- [ ] **Step 5: Confirm the durable CI guide still describes observation-only variable-height CI**

Run:

```bash
sed -n '88,98p' AGENTS.md
```

Expected output includes:

```text
`--variable-height` (observation only, `continue-on-error`)
The synthetic gate **fails the job on perf regression**.
```

---

## Task 2: Consolidate Memory-Shape Summaries

**Files:**
- Modify: `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`

- [ ] **Step 1: Apply the diagnostics consolidation patch**

Use `apply_patch` with this patch:

```diff
*** Begin Patch
*** Update File: Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
@@
 func variableCoreOwnedBytesEstimate() -> Int {
     MemoryLayout<VirtualRange>.size
         + MemoryLayout<VariableLineGeometryCursor<UniformLineMetrics>>.size
         + MemoryLayout<Int>.size * 2
 }
-struct VariableMemoryShapeSummary {
-    let scenarioName: String
-    let lineCount: Int
-    let bufferedLines: Int
-    let geometryLines: Int
-    let coreOwnedBytes: Int
-    let traversalPasses: Bool
-    let checksum: Int
-}
+let variableUniformMemoryShapeProviderName = "variable_uniform"
@@
-func runVariableMemoryShapeScenario(lineCount: Int) -> VariableMemoryShapeSummary {
+func runVariableMemoryShapeScenario(lineCount: Int) -> MemoryShapeSummary {
@@
-        return VariableMemoryShapeSummary(
+        return MemoryShapeSummary(
+            providerName: variableUniformMemoryShapeProviderName,
             scenarioName: scenarioName,
             lineCount: lineCount,
+            documentBytes: nil,
+            visibleLines: visibleLines,
             bufferedLines: bufferedLines,
             geometryLines: geometryLines,
+            providerLines: bufferedLines,
+            missingLines: 0,
             coreOwnedBytes: coreOwnedBytes,
-            traversalPasses: rangePasses
+            providerOwnedBytes: 0,
+            benchmarkOwnedBytes: 0,
+            baseInvariantPasses: rangePasses
                 && visibleLines == expectedVisibleLines
                 && bufferedLines == expectedBufferedLines
                 && geometryLines == bufferedLines,
             checksum: checksum
         )
     case .failure:
-        return VariableMemoryShapeSummary(
+        return MemoryShapeSummary(
+            providerName: variableUniformMemoryShapeProviderName,
             scenarioName: scenarioName,
             lineCount: lineCount,
+            documentBytes: nil,
+            visibleLines: 0,
             bufferedLines: 0,
             geometryLines: 0,
+            providerLines: 0,
+            missingLines: 0,
             coreOwnedBytes: coreOwnedBytes,
-            traversalPasses: false,
+            providerOwnedBytes: 0,
+            benchmarkOwnedBytes: 0,
+            baseInvariantPasses: false,
             checksum: -1
         )
     }
 }
-
-func formatVariableMemoryShapeSummary(_ summary: VariableMemoryShapeSummary, invariantPasses: Bool) -> String {
-    var output = "mode=\(BenchmarkMode.memoryShape.outputName)"
-    output += " provider=variable_uniform"
-    output += " scenario=\(summary.scenarioName)"
-    output += " line_count=\(summary.lineCount)"
-    output += " buffered_lines=\(summary.bufferedLines)"
-    output += " geometry_lines=\(summary.geometryLines)"
-    output += " core_owned_bytes=\(summary.coreOwnedBytes)"
-    output += " invariant=\(invariantPasses ? "pass" : "fail")"
-    output += " checksum=\(summary.checksum)"
-    return output
-}
 func runMemoryShapeDiagnostics() -> Bool {
-    let summaries = memoryShapeScenarios().map(runMemoryShapeScenario)
+    let fixedSummaries = memoryShapeScenarios().map(runMemoryShapeScenario)
+    let variableSummaries = [100_000, 1_000_000].map(runVariableMemoryShapeScenario)
+    let summaries = fixedSummaries + variableSummaries
     let syntheticCoreOwnedBytes = summaries
         .filter { $0.providerName == MemoryShapeProviderKind.synthetic.outputName }
         .map(\.coreOwnedBytes)
-    let comparisonCoreOwnedBytes = syntheticCoreOwnedBytes.first
+    let variableCoreOwnedBytes = summaries
+        .filter { $0.providerName == variableUniformMemoryShapeProviderName }
+        .map(\.coreOwnedBytes)
+    let comparisonCoreOwnedBytes = syntheticCoreOwnedBytes.first
+    let comparisonVariableCoreOwnedBytes = variableCoreOwnedBytes.first
     var passed = true
     for summary in summaries {
         let comparisonPasses: Bool
         if summary.providerName == MemoryShapeProviderKind.synthetic.outputName,
            let comparisonCoreOwnedBytes {
             comparisonPasses = summary.coreOwnedBytes == comparisonCoreOwnedBytes
+        } else if summary.providerName == variableUniformMemoryShapeProviderName,
+                  let comparisonVariableCoreOwnedBytes {
+            comparisonPasses = summary.coreOwnedBytes == comparisonVariableCoreOwnedBytes
         } else {
             comparisonPasses = true
         }
@@
-    let variableSummaries = [100_000, 1_000_000].map(runVariableMemoryShapeScenario)
-    let referenceVariableCoreOwnedBytes = variableSummaries.first?.coreOwnedBytes
-    for summary in variableSummaries {
-        let coreBytesMatches = summary.coreOwnedBytes == referenceVariableCoreOwnedBytes
-        let invariantPasses = summary.traversalPasses && coreBytesMatches
-        print(formatVariableMemoryShapeSummary(summary, invariantPasses: invariantPasses))
-
-        if !invariantPasses {
-            passed = false
-        }
-    }
-
     return passed
 }
*** End Patch
```

- [ ] **Step 2: Verify the duplicate variable-only types are gone**

Run:

```bash
rg -n "VariableMemoryShapeSummary|formatVariableMemoryShapeSummary|referenceVariableCoreOwnedBytes|traversalPasses" Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
```

Expected: command exits `1` with no output.

- [ ] **Step 3: Verify the required variable-specific memory estimate and cross-row comparison remain**

Run:

```bash
rg -n "variableCoreOwnedBytesEstimate\\(\\)|comparisonVariableCoreOwnedBytes|variableUniformMemoryShapeProviderName" Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
```

Expected: command exits `0`; output includes all three names.

- [ ] **Step 4: Run the memory-shape diagnostic and capture output**

Run:

```bash
set -o pipefail
swift run -c release ViewportBenchmarks -- --memory-shape | tee /private/tmp/slice-15-memory-shape.out
```

Expected: command exits `0`; every printed row ends with `invariant=pass` before
the checksum field.

- [ ] **Step 5: Verify normalized `variable_uniform` output**

Run:

```bash
rg "provider=variable_uniform.*visible_lines=.*buffered_lines=.*touched_lines=.*geometry_lines=.*provider_lines=.*missing_lines=0.*core_owned_bytes=.*provider_owned_bytes=0.*benchmark_owned_bytes=0.*invariant=pass" /private/tmp/slice-15-memory-shape.out
```

Expected: command exits `0` and prints exactly two `provider=variable_uniform`
lines.

- [ ] **Step 6: Run host tests after the diagnostic refactor**

Run:

```bash
swift test
```

Expected: command exits `0`; XCTest reports `0 failures`.

- [ ] **Step 7: Commit the diagnostics consolidation**

```bash
git add Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
git commit -m "refactor: consolidate memory-shape summaries"
```

---

## Task 3: Promote Variable-Height Benchmark In CI

**Files:**
- Modify: `.github/workflows/swift-ci.yml`
- Modify: `AGENTS.md`

- [ ] **Step 1: Apply the workflow promotion patch**

Use `apply_patch` with this patch:

```diff
*** Begin Patch
*** Update File: .github/workflows/swift-ci.yml
@@
-      - name: Run variable-height benchmark observation
-        continue-on-error: true
-        run: swift run -c release ViewportBenchmarks -- --variable-height
+      - name: Run variable-height benchmark gate
+        run: swift run -c release ViewportBenchmarks -- --variable-height --gate
*** End Patch
```

- [ ] **Step 2: Verify the workflow step is now blocking**

Run:

```bash
sed -n '24,40p' .github/workflows/swift-ci.yml
```

Expected output includes:

```yaml
      - name: Run variable-height benchmark gate
        run: swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Expected output does not include `continue-on-error: true` in the variable-height
step.

- [ ] **Step 3: Verify the old observation-only command is gone**

Run:

```bash
rg -n "Run variable-height benchmark observation|swift run -c release ViewportBenchmarks -- --variable-height$" .github/workflows/swift-ci.yml
```

Expected: command exits `1` with no output.

- [ ] **Step 4: Run the promoted gate locally**

Run:

```bash
set -o pipefail
swift run -c release ViewportBenchmarks -- --variable-height --gate | tee /private/tmp/slice-15-variable-height-gate.out
```

Expected: command exits `0`; output contains three `mode=variable_height` rows,
each with `failures=0` and `gate=pass`.

- [ ] **Step 5: Update the durable CI guide**

Use `apply_patch` with this patch:

```diff
*** Begin Patch
*** Update File: AGENTS.md
@@
-  → `--variable-height` (observation only, `continue-on-error`) → `--memory-shape`
+  → `--variable-height --gate` (blocking) → `--memory-shape`
@@
-  `continue-on-error`). The synthetic gate **fails the job on perf regression**.
+  `continue-on-error`). The synthetic and variable-height gates **fail the job
+  on perf regression**.
*** End Patch
```

- [ ] **Step 6: Verify the durable CI guide**

Run:

```bash
sed -n '88,98p' AGENTS.md
```

Expected output includes:

```text
`--variable-height --gate` (blocking)
The synthetic and variable-height gates **fail the job
on perf regression**.
```

Expected output does not describe the variable-height step as observation-only.

- [ ] **Step 7: Commit the workflow and guide promotion**

```bash
git add .github/workflows/swift-ci.yml AGENTS.md
git commit -m "ci: promote variable-height benchmark gate"
```

---

## Task 4: Full Local Verification

**Files:** none.

Run the full verification set from the approved spec. Capture command output for
Task 5.

- [ ] **Step 1: Host tests**

Run:

```bash
set -o pipefail
swift test 2>&1 | tee /private/tmp/slice-15-swift-test.out
```

Expected: command exits `0`; XCTest reports `0 failures`.

- [ ] **Step 2: Release build**

Run:

```bash
set -o pipefail
swift build -c release 2>&1 | tee /private/tmp/slice-15-release-build.out
```

Expected: command exits `0`; build completes successfully.

- [ ] **Step 3: Synthetic benchmark gate**

Run:

```bash
set -o pipefail
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tee /private/tmp/slice-15-synthetic-gate.out
```

Expected: command exits `0`; output contains three `mode=pipeline` rows, each
with `failures=0` and `gate=pass`.

- [ ] **Step 4: Variable-height benchmark gate**

Run:

```bash
set -o pipefail
swift run -c release ViewportBenchmarks -- --variable-height --gate 2>&1 | tee /private/tmp/slice-15-variable-height-gate-final.out
```

Expected: command exits `0`; output contains three `mode=variable_height` rows,
each with `failures=0` and `gate=pass`.

- [ ] **Step 5: Memory-shape diagnostic**

Run:

```bash
set -o pipefail
swift run -c release ViewportBenchmarks -- --memory-shape 2>&1 | tee /private/tmp/slice-15-memory-shape-final.out
```

Expected: command exits `0`; all rows have `invariant=pass`, including two
normalized `provider=variable_uniform` rows with `visible_lines`,
`touched_lines`, `provider_lines`, `missing_lines=0`,
`provider_owned_bytes=0`, and `benchmark_owned_bytes=0`.

- [ ] **Step 6: RSS memory observation**

Run:

```bash
set -o pipefail
swift run -c release ViewportBenchmarks -- --memory-observation 2>&1 | tee /private/tmp/slice-15-memory-observation.out
```

Expected: command exits `0`; output contains three `mode=memory_observation`
rows, each with `observation=pass`.

- [ ] **Step 7: Foundation-free core scan**

Run:

```bash
rg -n "Foundation" Sources/TextEngineCore > /private/tmp/slice-15-foundation-scan.out 2>&1
FOUNDATION_STATUS=$?
cat /private/tmp/slice-15-foundation-scan.out
test "$FOUNDATION_STATUS" -eq 1
```

Expected: command exits `0` after confirming `rg` returned `1` for no matches.
The captured file is empty.

- [ ] **Step 8: Cross-target helper self-test**

Run:

```bash
set -o pipefail
./.github/scripts/cross-target-compile.sh --self-test 2>&1 | tee /private/tmp/slice-15-cross-target-self-test.out
```

Expected: command exits `0`; output includes `self_test=pass`.

- [ ] **Step 9: Cross-target compile**

Run:

```bash
set -o pipefail
./.github/scripts/cross-target-compile.sh 2>&1 | tee /private/tmp/slice-15-cross-target-compile.out
```

Expected: command exits `0`; output includes
`target=ios_device result=pass`, `target=ios_simulator result=pass`, and
`blocking_failures=0 exit=0`. WASM and embedded WASM may either pass or skip
according to the helper's existing SDK-availability contract.

- [ ] **Step 10: Durable CI guide scan**

Run:

```bash
set -o pipefail
rg -n -- "--variable-height --gate|synthetic and variable-height gates" AGENTS.md 2>&1 | tee /private/tmp/slice-15-agents-ci-guide.out
```

Expected: command exits `0`; output includes both the blocking
`--variable-height --gate` step and the sentence that synthetic and
variable-height gates fail the job on perf regression.

- [ ] **Step 11: Whitespace diff check**

Run:

```bash
set -o pipefail
git diff --check 2>&1 | tee /private/tmp/slice-15-diff-check.out
```

Expected: command exits `0` with no output.

---

## Task 5: Verification Document And Hosted Evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-12-variable-height-ci-gate-promotion.md`

- [ ] **Step 1: Write the verification document with local evidence**

Create `docs/superpowers/verification/2026-06-12-variable-height-ci-gate-promotion.md`.
Use this exact section order, and paste the real Task 4 outputs from the
captured `/private/tmp/slice-15-*.out` files:

````markdown
# Variable-Height CI Gate Promotion Verification

Date: 2026-06-12

## Scope

This verification covers Slice 15 on branch `slice-15-variable-height-ci-gate`.
It verifies that variable-height benchmark enforcement is promoted to a blocking
Swift CI gate, and that variable-height memory-shape diagnostics use the common
`MemoryShapeSummary` output path while preserving the variable core-owned byte
estimate and cross-variable consistency check.

## Local Verification

Record the command and real output for each Task 4 step:

- `swift test`
- `swift build -c release`
- `swift run -c release ViewportBenchmarks -- --gate`
- `swift run -c release ViewportBenchmarks -- --variable-height --gate`
- `swift run -c release ViewportBenchmarks -- --memory-shape`
- `swift run -c release ViewportBenchmarks -- --memory-observation`
- `rg -n "Foundation" Sources/TextEngineCore`
- `./.github/scripts/cross-target-compile.sh --self-test`
- `./.github/scripts/cross-target-compile.sh`
- `rg -n -- "--variable-height --gate|synthetic and variable-height gates" AGENTS.md`
- `git diff --check`

## Workflow Scan

Record the final `.github/workflows/swift-ci.yml` variable-height step and show
that it runs:

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

without `continue-on-error: true`.

## Hosted PR Run

After opening the PR, record the PR number, head SHA, Swift CI run id, run
conclusion, job conclusions, and the hosted `mode=variable_height` lines showing
`gate=pass`.

## Post-Merge Push Run

After merging, record the merge commit SHA, Swift CI push run id, run
conclusion, job conclusions, and the hosted `mode=variable_height` lines showing
`gate=pass` on `main`.

## Conclusion

Slice 15 meets the approved design when local verification passes, the hosted PR
run passes with the variable-height benchmark as a blocking gate, and the
post-merge push run on `main` passes with the same blocking gate.
````

- [ ] **Step 2: Commit the local verification document**

```bash
git add docs/superpowers/verification/2026-06-12-variable-height-ci-gate-promotion.md
git commit -m "docs: record variable-height ci gate verification"
```

- [ ] **Step 3: Push the branch and open the PR**

Run:

```bash
git push -u origin slice-15-variable-height-ci-gate
```

Open a PR from `slice-15-variable-height-ci-gate` to `main`. Confirm the PR
description references:

```text
docs/superpowers/specs/2026-06-12-variable-height-ci-gate-promotion-design.md
docs/superpowers/plans/2026-06-12-variable-height-ci-gate-promotion.md
docs/superpowers/verification/2026-06-12-variable-height-ci-gate-promotion.md
```

- [ ] **Step 4: Capture hosted PR run evidence**

Find the latest Swift CI pull-request run for the branch:

```bash
gh run list --branch slice-15-variable-height-ci-gate --workflow "Swift CI" --limit 5 --json databaseId,status,conclusion,event,headSha,createdAt,displayTitle
```

After the run completes with `conclusion=success`, capture variable-height gate
lines:

```bash
set -o pipefail
RUN_ID=$(gh run list --branch slice-15-variable-height-ci-gate --workflow "Swift CI" --limit 5 --json databaseId,event,conclusion --jq '.[] | select(.event == "pull_request" and .conclusion == "success") | .databaseId' | head -n 1)
gh run view "$RUN_ID" --log | rg "mode=variable_height"
```

Expected: three hosted `mode=variable_height` rows, each with `gate=pass`.

Update the `Hosted PR Run` section with the real PR number, head SHA, run id,
run conclusion, job conclusions, and variable-height gate output.

- [ ] **Step 5: Commit hosted PR evidence**

```bash
git add docs/superpowers/verification/2026-06-12-variable-height-ci-gate-promotion.md
git commit -m "docs: record variable-height ci gate pr run"
git push
```

- [ ] **Step 6: Capture post-merge push run evidence**

After the PR merges, update local `main` and find the Swift CI push run on the
merge commit:

```bash
git fetch origin main
MERGE_SHA=$(git rev-parse origin/main)
gh run list --branch main --workflow "Swift CI" --limit 10 --json databaseId,status,conclusion,event,headSha,createdAt,displayTitle
```

Select the `push` run whose `headSha` equals `MERGE_SHA`. After it completes
with `conclusion=success`, capture variable-height gate lines:

```bash
set -o pipefail
RUN_ID=$(gh run list --branch main --workflow "Swift CI" --limit 10 --json databaseId,event,headSha,conclusion --jq ".[] | select(.event == \"push\" and .headSha == \"$MERGE_SHA\" and .conclusion == \"success\") | .databaseId" | head -n 1)
gh run view "$RUN_ID" --log | rg "mode=variable_height"
```

Expected: three hosted `mode=variable_height` rows, each with `gate=pass`, from
the post-merge push run on `main`.

- [ ] **Step 7: Commit post-merge evidence**

Update the `Post-Merge Push Run` section with the merge commit SHA, run id,
run conclusion, job conclusions, and variable-height gate output, then commit:

```bash
git add docs/superpowers/verification/2026-06-12-variable-height-ci-gate-promotion.md
git commit -m "docs: record variable-height ci gate post-merge run"
```

---

## Self-Review Checklist

Before implementation starts, verify this plan against the approved spec:

- [ ] Diagnostics consolidation preserves `variableCoreOwnedBytesEstimate()`.
- [ ] Diagnostics consolidation maps variable `traversalPasses` to
  `baseInvariantPasses`.
- [ ] Diagnostics consolidation keeps cross-variable `coreOwnedBytes`
  comparison outside per-row `baseInvariantPasses`.
- [ ] Workflow promotion removes `continue-on-error` from the variable-height
  step and adds `--gate`.
- [ ] `AGENTS.md` describes `--variable-height --gate` as blocking and no longer
  calls it observation-only.
- [ ] Local verification includes host tests, release build, synthetic gate,
  variable-height gate, memory-shape, memory-observation, Foundation-free scan,
  cross-target self-test, full cross-target compile, AGENTS CI-guide scan, and
  `git diff --check`.
- [ ] Hosted verification records PR and post-merge push runs.
