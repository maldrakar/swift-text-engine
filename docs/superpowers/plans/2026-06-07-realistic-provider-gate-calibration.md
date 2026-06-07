# Realistic Provider Gate Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing realistic 100,000-line, 11.2 MB provider benchmark gateable with calibrated p95/p99 budgets, and add a CI workflow step only if hosted-runner samples support reliable enforcement.

**Architecture:** `TextEngineCore` stays unchanged. `ViewportBenchmarks` reuses the existing `BenchmarkSummary` gate machinery: `--realistic-provider --gate` becomes valid, `RealisticProviderScenario` gains p95/p99 budgets, and the realistic-provider runner prints gate fields only when enforcement is requested. GitHub Actions is edited only after hosted-runner samples from the same workflow environment show that the absolute budgets are useful and stable.

**Tech Stack:** Swift Package Manager, Swift 6.2.1, `TextEngineCore`, `ViewportBenchmarks`, GitHub Actions, `gh`, `rg`, git.

---

## Source Design

Implement the approved Slice 10 design:

```text
docs/superpowers/specs/2026-06-07-realistic-provider-gate-calibration-design.md
```

Preserve these constraints from the spec:

- Do not edit `Sources/TextEngineCore`.
- Do not edit `Tests`.
- Do not edit `Package.swift`.
- Do not add memory budgets, baseline-relative gating, storage adapters, variable-height layout, branch protection, rulesets, iOS CI, WASM CI, or embedded WASM CI.
- Do not describe a failing workflow step as a merge blocker unless repository policy is also configured to require that status check.
- Do not add `.github/workflows/swift-ci.yml` realistic-provider enforcement unless hosted-runner samples from that same workflow environment support it.

## File Structure

Modify:

```text
Sources/ViewportBenchmarks/BenchmarkModels.swift
Sources/ViewportBenchmarks/BenchmarkOptions.swift
Sources/ViewportBenchmarks/BenchmarkProgram.swift
Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
```

Conditionally modify only after hosted-runner calibration:

```text
.github/workflows/swift-ci.yml
```

Create:

```text
docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md
```

Responsibility map:

```text
BenchmarkModels.swift
  RealisticProviderScenario stores calibrated p95/p99 budgets.

BenchmarkOptions.swift
  --realistic-provider --gate becomes valid.
  Usage text no longer says realistic-provider cannot be enforced.
  Other invalid option combinations remain invalid.

BenchmarkProgram.swift
  Passes options.enforceGate into realistic-provider dispatch.

RealisticProviderBenchmark.swift
  Defines candidate realistic-provider budgets.
  Produces budget fields in BenchmarkSummary.
  Prints gate fields only when enforceGate is true.
  Returns false when gated summaries fail.

.github/workflows/swift-ci.yml
  Adds one workflow-failing realistic-provider gate step only if hosted-runner
  samples support enforcement.

Verification document
  Records local calibration samples, final budget choice, local verification,
  hosted-runner decision, workflow edit status, and non-goal checks.
```

## Budget Decision Rule

Use these initial candidate budgets:

```text
budget_p95_ns=20000
budget_p99_ns=50000
```

Continue with these budgets only if pre-implementation local calibration satisfies both conditions:

```text
max_local_p95_ns <= 10000
max_local_p99_ns <= 25000
```

If either local condition fails, stop before source edits and ask the user to revise the budget policy. Do not invent wider budgets during implementation.

Add the GitHub Actions enforcement step only if hosted-runner calibration satisfies all conditions:

```text
all_hosted_runs_exit_0
max_hosted_p95_ns <= 20000
max_hosted_p99_ns <= 50000
at_least_3_hosted_gate_samples_recorded
```

If any hosted condition fails, leave `.github/workflows/swift-ci.yml` unchanged and record CI enforcement as deferred in verification.

## Task 1: Preflight And Local Calibration

**Files:**
- Read: `docs/superpowers/specs/2026-06-07-realistic-provider-gate-calibration-design.md`
- Read: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Read: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- Read: `Sources/ViewportBenchmarks/BenchmarkModels.swift`
- Read: `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`
- Read: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Confirm the approved design contains the required constraints**

Run:

```bash
rg -n "Approved design, revised after user review|Hosted-runner calibration is mandatory|Do not add the CI step based only on local samples|baseline-relative|wall-clock cost|--realistic-provider --gate" docs/superpowers/specs/2026-06-07-realistic-provider-gate-calibration-design.md
```

Expected: output includes all six searched phrases.

- [ ] **Step 2: Confirm a clean working tree**

Run:

```bash
git status --short
git log --format=%H --grep="docs: plan realistic provider gate calibration" -n 1
```

Expected:

- `git status --short` has no output.
- `git log --format=%H --grep="docs: plan realistic provider gate calibration" -n 1` prints the plan commit hash after this plan has been committed. Use that commit as the Slice 10 base for whole-slice non-goal diff checks.

- [ ] **Step 3: Confirm current CLI rejects the target command**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Expected: command exits non-zero and output contains:

```text
error=--realistic-provider cannot be combined with --gate
```

- [ ] **Step 4: Confirm baseline host verification passes**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

Expected:

- `swift test` exits `0` with 39 XCTest tests and 0 failures.
- `swift build -c release` exits `0`.
- `--gate` prints three `mode=pipeline` lines with `gate=pass`.
- `--memory-shape` prints three `mode=memory_shape` lines with `invariant=pass`.
- `--memory-observation` prints three `mode=memory_observation` lines with `observation=pass`.

- [ ] **Step 5: Collect five local realistic-provider samples before source edits**

Run this command five separate times:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Expected for each run:

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=NUMBER p99_ns=NUMBER failures=0 checksum=756321289736960
```

Record the five `p95_ns` and `p99_ns` values in the verification document later.

- [ ] **Step 6: Apply the local budget decision rule**

Compute:

```text
max_local_p95_ns = maximum p95_ns from the five samples
max_local_p99_ns = maximum p99_ns from the five samples
```

Continue only if:

```text
max_local_p95_ns <= 10000
max_local_p99_ns <= 25000
```

Expected on the current local machine, based on previous Slice 4-9 records:

```text
max_local_p95_ns <= 10000
max_local_p99_ns <= 25000
```

If either condition fails, stop before editing source and ask the user to revise the budget policy.

## Task 2: Add Realistic Provider Gate Support

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkModels.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- Modify: `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`

- [ ] **Step 1: Add budget fields to `RealisticProviderScenario`**

Use `apply_patch`:

```diff
*** Begin Patch
*** Update File: Sources/ViewportBenchmarks/BenchmarkModels.swift
@@
 struct RealisticProviderScenario {
     let name: String
     let lineCount: Int
     let lineBytes: Int
     let lineHeight: Double
     let viewportHeight: Double
     let overscanBefore: Int
     let overscanAfter: Int
+    let p95BudgetNanoseconds: Int64
+    let p99BudgetNanoseconds: Int64
 }
*** End Patch
```

Expected: patch applies cleanly.

- [ ] **Step 2: Update CLI usage and allow `--realistic-provider --gate`**

Use `apply_patch`:

```diff
*** Begin Patch
*** Update File: Sources/ViewportBenchmarks/BenchmarkOptions.swift
@@
-      --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
-      --realistic-provider  Run large-text provider benchmark without gate enforcement.
+      --gate                Enforce p95/p99 budgets for gateable benchmark modes and exit non-zero on failure.
+      --realistic-provider  Run large-text provider benchmark. Combine with --gate to enforce calibrated budgets.
@@
-        if mode == .realisticProvider && enforceGate {
-            return .failure("--realistic-provider cannot be combined with --gate")
-        }
         if mode == .memoryShape && enforceGate {
             return .failure("--memory-shape cannot be combined with --gate")
         }
*** End Patch
```

Expected: patch applies cleanly, and no other invalid option rule changes.

- [ ] **Step 3: Pass the gate flag into realistic-provider dispatch**

Use `apply_patch`:

```diff
*** Begin Patch
*** Update File: Sources/ViewportBenchmarks/BenchmarkProgram.swift
@@
     case .pipeline, .rangeOnly:
         return runSyntheticBenchmarks(options: options)
     case .realisticProvider:
-        return runRealisticProviderBenchmarks()
+        return runRealisticProviderBenchmarks(enforceGate: options.enforceGate)
*** End Patch
```

Expected: patch applies cleanly.

- [ ] **Step 4: Add candidate budgets and gate handling to the realistic-provider runner**

Use `apply_patch`:

```diff
*** Begin Patch
*** Update File: Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
@@
             lineBytes: 112,
             lineHeight: 16.0,
             viewportHeight: 80.0 * 16.0,
             overscanBefore: 5,
-            overscanAfter: 5
+            overscanAfter: 5,
+            p95BudgetNanoseconds: 20_000,
+            p99BudgetNanoseconds: 50_000
         )
     ]
 }
@@
         p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
         p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
         checksum: checksum,
         failureCount: failureCount,
-        p95BudgetNanoseconds: nil,
-        p99BudgetNanoseconds: nil
+        p95BudgetNanoseconds: scenario.p95BudgetNanoseconds,
+        p99BudgetNanoseconds: scenario.p99BudgetNanoseconds
     )
 }
 
 @available(macOS 13.0, *)
-func runRealisticProviderBenchmarks() -> Bool {
+func runRealisticProviderBenchmarks(enforceGate: Bool) -> Bool {
     let iterations = 5_000
     let operationsPerSample = 256
     var passed = true
@@
             iterations: iterations,
             operationsPerSample: operationsPerSample
         )
-        print(formatSummary(summary, includeGate: false))
+        print(formatSummary(summary, includeGate: enforceGate))
 
-        if summary.failureCount != 0 {
+        if enforceGate && !summary.passesGate {
+            passed = false
+        } else if !enforceGate && summary.failureCount != 0 {
             passed = false
         }
     }
*** End Patch
```

Expected: patch applies cleanly.

- [ ] **Step 5: Build to catch signature or initializer mistakes**

Run:

```bash
swift build -c release
```

Expected: exits `0`.

- [ ] **Step 6: Commit source gate support**

Run:

```bash
git status --short
git diff -- Sources/ViewportBenchmarks/BenchmarkModels.swift Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
git add Sources/ViewportBenchmarks/BenchmarkModels.swift Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
git commit -m "feat: gate realistic provider benchmark"
```

Expected:

- `git status --short` shows only the four `Sources/ViewportBenchmarks` files modified.
- Diff shows no `TextEngineCore`, `Tests`, `Package.swift`, or workflow changes.
- Commit succeeds.

## Task 3: Verify Local Gate Behavior

**Files:**
- Read: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Read: `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`

- [ ] **Step 1: Verify ungated realistic-provider output stays observational**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Expected: command exits `0` and prints one line containing:

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text
failures=0
checksum=756321289736960
```

Expected: output does not contain:

```text
budget_p95_ns=
budget_p99_ns=
gate=
```

- [ ] **Step 2: Verify gated realistic-provider output passes locally**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Expected: command exits `0` and prints one line containing:

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text
budget_p95_ns=20000
budget_p99_ns=50000
gate=pass
failures=0
checksum=756321289736960
```

- [ ] **Step 3: Verify the realistic-provider gate failure path with a temporary budget override**

Use `apply_patch`:

```diff
*** Begin Patch
*** Update File: Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
@@
-            p95BudgetNanoseconds: 20_000,
-            p99BudgetNanoseconds: 50_000
+            p95BudgetNanoseconds: 1,
+            p99BudgetNanoseconds: 1
*** End Patch
```

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Expected: command exits non-zero and output contains:

```text
budget_p95_ns=1
budget_p99_ns=1
gate=fail
failures=0
```

- [ ] **Step 4: Restore calibrated budgets after the temporary failure-path check**

Use `apply_patch`:

```diff
*** Begin Patch
*** Update File: Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
@@
-            p95BudgetNanoseconds: 1,
-            p99BudgetNanoseconds: 1
+            p95BudgetNanoseconds: 20_000,
+            p99BudgetNanoseconds: 50_000
*** End Patch
```

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
git diff -- Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
```

Expected:

- `--realistic-provider --gate` exits `0` with `gate=pass`.
- `git diff -- Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift` has no output because the temporary override was restored to the committed code.

- [ ] **Step 5: Verify invalid CLI matrix after the contract change**

Run:

```bash
swift run -c release ViewportBenchmarks -- --range-only --gate
swift run -c release ViewportBenchmarks -- --range-only --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape --gate
swift run -c release ViewportBenchmarks -- --memory-observation --gate
swift run -c release ViewportBenchmarks -- --unknown
```

Expected:

- `--range-only --gate` exits non-zero with `error=--range-only cannot be combined with --gate`.
- `--range-only --realistic-provider` exits non-zero with `error=--realistic-provider cannot be combined with --range-only`.
- `--realistic-provider --memory-shape` exits non-zero with `error=--realistic-provider cannot be combined with --memory-shape`.
- `--memory-observation --realistic-provider` exits non-zero with `error=--memory-observation cannot be combined with --realistic-provider`.
- `--memory-shape --gate` exits non-zero with `error=--memory-shape cannot be combined with --gate`.
- `--memory-observation --gate` exits non-zero with `error=--memory-observation cannot be combined with --gate`.
- `--unknown` exits non-zero with `error=unknown argument --unknown`.

- [ ] **Step 6: Verify existing benchmark modes still pass**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

Expected:

- `swift test` exits `0` with 39 XCTest tests and 0 failures.
- `swift build -c release` exits `0`.
- Default benchmark prints three `mode=pipeline` lines.
- `--range-only` prints three `mode=range_only` lines.
- `--gate` prints three `mode=pipeline` lines with `gate=pass`.
- `--memory-shape` prints three `mode=memory_shape` lines with `invariant=pass`.
- `--memory-observation` prints three `mode=memory_observation` lines with `observation=pass`.

## Task 4: Hosted-Runner Calibration Decision

**Files:**
- Read: `.github/workflows/swift-ci.yml`
- Conditionally modify: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Check whether GitHub Actions sampling can be attempted**

Run:

```bash
git remote -v
gh run list --workflow "Swift CI" --limit 5
```

Expected for attempting hosted calibration:

- `git remote -v` shows a writable GitHub remote for this repository.
- `gh run list --workflow "Swift CI" --limit 5` exits `0`.

If either command fails because GitHub access, authentication, or push access is unavailable, skip to Task 5 and record CI enforcement as deferred.

- [ ] **Step 2: Add the final workflow step locally only when hosted calibration will be attempted**

Use `apply_patch`:

```diff
*** Begin Patch
*** Update File: .github/workflows/swift-ci.yml
@@
       - name: Run synthetic benchmark gate
         run: swift run -c release ViewportBenchmarks -- --gate
 
+      - name: Run realistic provider benchmark gate
+        run: swift run -c release ViewportBenchmarks -- --realistic-provider --gate
+
       - name: Run memory shape diagnostic
         run: swift run -c release ViewportBenchmarks -- --memory-shape
*** End Patch
```

Run:

```bash
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
git diff -- .github/workflows/swift-ci.yml
```

Expected:

- `rg` finds the new step.
- Diff shows only the new workflow step between synthetic gate and memory-shape diagnostic.

- [ ] **Step 3: Commit the workflow step for branch-hosted calibration**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: run realistic provider benchmark gate"
```

Expected: commit succeeds.

- [ ] **Step 4: Push the branch and collect at least three hosted samples**

Run:

```bash
git branch --show-current
git push -u origin HEAD
gh run list --workflow "Swift CI" --branch "$(git branch --show-current)" --limit 3
```

Expected:

- `git push -u origin HEAD` succeeds.
- At least one `Swift CI` run appears for the current branch.

Open each relevant run log with:

```bash
RUN_ID=123456789
gh run view "$RUN_ID" --log
```

Replace `123456789` with the numeric run id printed by `gh run list`. Record the `mode=realistic_provider` line from each hosted run. If fewer than three hosted samples are available, rerun the workflow until there are three samples:

```bash
RUN_ID=123456789
gh run rerun "$RUN_ID"
gh run watch "$RUN_ID"
gh run view "$RUN_ID" --log
```

Expected hosted sample line:

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=NUMBER p99_ns=NUMBER failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

- [ ] **Step 5: Apply the hosted-runner decision rule**

Continue with the workflow step only if all conditions are true:

```text
all_hosted_runs_exit_0
max_hosted_p95_ns <= 20000
max_hosted_p99_ns <= 50000
at_least_3_hosted_gate_samples_recorded
```

If all conditions are true, keep `.github/workflows/swift-ci.yml` and its commit.

If any condition is false, remove the workflow step:

```diff
*** Begin Patch
*** Update File: .github/workflows/swift-ci.yml
@@
-      - name: Run realistic provider benchmark gate
-        run: swift run -c release ViewportBenchmarks -- --realistic-provider --gate
-
       - name: Run memory shape diagnostic
         run: swift run -c release ViewportBenchmarks -- --memory-shape
*** End Patch
```

Then run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: defer realistic provider benchmark gate"
```

Expected: the final branch either contains the workflow step because hosted samples supported it, or contains a clear defer commit removing the step because hosted samples did not support enforcement.

## Task 5: Record Verification Evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md`

- [ ] **Step 1: Create the verification document**

Use `apply_patch` with this structure. Before committing, every sample line must contain numeric values copied from the commands executed in Tasks 1, 3, and 4.

```diff
*** Begin Patch
*** Add File: docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md
+# Realistic Provider Gate Calibration Verification
+
+Date: 2026-06-07
+
+## Scope
+
+Slice 10 makes `swift run -c release ViewportBenchmarks -- --realistic-provider --gate` valid with calibrated p95/p99 budgets for the existing 100,000-line, 11.2 MB realistic-provider benchmark.
+
+The slice does not change `TextEngineCore`, `Tests`, or `Package.swift`. It does not add memory budgets, storage adapters, variable-height layout, branch protection, rulesets, or cross-target CI.
+
+## Budget Decision
+
+Selected local gate budgets:
+
+```text
+budget_p95_ns=20000
+budget_p99_ns=50000
+```
+
+Local pre-implementation calibration samples:
+
+```text
+sample=1 p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE
+sample=2 p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE
+sample=3 p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE
+sample=4 p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE
+sample=5 p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE
+max_local_p95_ns=NUMERIC_VALUE
+max_local_p99_ns=NUMERIC_VALUE
+decision=local_gate_supported
+```
+
+## Hosted-Runner Decision
+
+Record one of these outcomes.
+
+If workflow enforcement was added:
+
+```text
+ci_enforcement=added
+reason=three hosted samples from the same Swift CI workflow environment passed within the selected budgets
+run=NUMERIC_RUN_ID p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE gate=pass
+run=NUMERIC_RUN_ID p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE gate=pass
+run=NUMERIC_RUN_ID p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE gate=pass
+```
+
+If workflow enforcement was deferred:
+
+```text
+ci_enforcement=deferred
+reason=github-access-unavailable
+```
+
+Allowed deferred reason values are `github-access-unavailable`, `hosted-samples-unavailable`, `hosted-variance-too-high`, and `hosted-budget-failure`.
+
+A failing workflow step is not described as a merge blocker here because repository policy still controls whether a status check is required before merge.
+
+## Verification Commands
+
+### Host Tests
+
+Command:
+
+```text
+swift test
+```
+
+Result: pass.
+
+### Release Build
+
+Command:
+
+```text
+swift build -c release
+```
+
+Result: pass.
+
+### Default Pipeline Benchmark
+
+Command:
+
+```text
+swift run -c release ViewportBenchmarks
+```
+
+Result: pass.
+
+### Range-Only Benchmark
+
+Command:
+
+```text
+swift run -c release ViewportBenchmarks -- --range-only
+```
+
+Result: pass.
+
+### Synthetic Benchmark Gate
+
+Command:
+
+```text
+swift run -c release ViewportBenchmarks -- --gate
+```
+
+Result: pass.
+
+### Realistic Provider Benchmark
+
+Command:
+
+```text
+swift run -c release ViewportBenchmarks -- --realistic-provider
+```
+
+Result: pass.
+
+Expected output shape:
+
+```text
+mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE failures=0 checksum=756321289736960
+```
+
+### Realistic Provider Benchmark Gate
+
+Command:
+
+```text
+swift run -c release ViewportBenchmarks -- --realistic-provider --gate
+```
+
+Result: pass.
+
+Expected output shape:
+
+```text
+mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=NUMERIC_VALUE p99_ns=NUMERIC_VALUE failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
+```
+
+### Realistic Provider Gate Failure Check
+
+Temporary budgets:
+
+```text
+budget_p95_ns=1
+budget_p99_ns=1
+```
+
+Command:
+
+```text
+swift run -c release ViewportBenchmarks -- --realistic-provider --gate
+```
+
+Result: expected non-zero exit with `gate=fail`.
+
+The temporary override was restored before final verification.
+
+### Memory-Shape Diagnostic
+
+Command:
+
+```text
+swift run -c release ViewportBenchmarks -- --memory-shape
+```
+
+Result: pass.
+
+### RSS Memory Observation Diagnostic
+
+Command:
+
+```text
+swift run -c release ViewportBenchmarks -- --memory-observation
+```
+
+Result: pass.
+
+## Invalid CLI Matrix
+
+The following commands exited non-zero with the expected `error=` messages:
+
+```text
+swift run -c release ViewportBenchmarks -- --range-only --gate
+swift run -c release ViewportBenchmarks -- --range-only --realistic-provider
+swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape
+swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
+swift run -c release ViewportBenchmarks -- --memory-shape --gate
+swift run -c release ViewportBenchmarks -- --memory-observation --gate
+swift run -c release ViewportBenchmarks -- --unknown
+```
+
+`--realistic-provider --gate` is no longer part of the invalid CLI matrix.
+
+## Workflow Wiring
+
+Record one of these outcomes.
+
+If workflow enforcement was added:
+
+```text
+Run realistic provider benchmark gate: present
+```
+
+If workflow enforcement was deferred:
+
+```text
+Run realistic provider benchmark gate: not added
+```
+
+## Non-Goal Checks
+
+Command:
+
+```text
+git diff "$(git log --format=%H --grep='docs: plan realistic provider gate calibration' -n 1)"..HEAD -- Sources/TextEngineCore Tests Package.swift
+```
+
+Result: no output.
*** End Patch
```

Expected: verification document exists. Replace every `NUMERIC_VALUE`, `NUMERIC_RUN_ID`, and deferred reason default with actual execution data before committing.

- [ ] **Step 2: Replace all symbolic verification values with actual values**

Run:

```bash
rg -n "NUMERIC_VALUE|NUMERIC_RUN_ID" docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md
```

Expected before replacement: matches for values that need actual execution data.

Edit the document with `apply_patch` until the same command exits non-zero with no output:

```bash
rg -n "NUMERIC_VALUE|NUMERIC_RUN_ID" docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md
```

Expected after replacement: no output.

- [ ] **Step 3: Verify source-boundary and workflow claims**

Run:

```bash
git diff "$(git log --format=%H --grep='docs: plan realistic provider gate calibration' -n 1)"..HEAD -- Sources/TextEngineCore Tests Package.swift
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
```

Expected:

- `git diff "$(git log --format=%H --grep='docs: plan realistic provider gate calibration' -n 1)"..HEAD -- Sources/TextEngineCore Tests Package.swift` has no output.
- If CI enforcement was added, `rg` finds the workflow step.
- If CI enforcement was deferred, `rg` may still find no workflow step; record that in verification.

- [ ] **Step 4: Commit verification evidence**

Run:

```bash
git add docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md
git commit -m "docs: record realistic provider gate verification"
```

Expected: commit succeeds.

## Task 6: Final Review And Slice Boundary Check

**Files:**
- Read: `docs/superpowers/specs/2026-06-07-realistic-provider-gate-calibration-design.md`
- Read: `docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md`
- Read: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Read: `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`
- Conditionally read: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Run final verification command matrix**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

Expected: all commands exit `0`; gated commands include `gate=pass`; diagnostics include `invariant=pass` or `observation=pass`.

- [ ] **Step 2: Confirm no accidental non-goal changes**

Run:

```bash
git diff -- Sources/TextEngineCore Tests Package.swift
git status --short
```

Expected:

- `git diff -- Sources/TextEngineCore Tests Package.swift` has no output.
- `git status --short` has no output after all intended commits.

- [ ] **Step 3: Summarize implementation outcome**

Prepare the final implementation summary with:

```text
Implemented:
- --realistic-provider --gate is valid.
- Gated realistic-provider output includes budget_p95_ns=20000, budget_p99_ns=50000, and gate=pass.
- Ungated realistic-provider output remains observational.
- Existing synthetic gate, memory-shape, and RSS observation behavior pass.

CI:
- Added realistic-provider workflow gate because hosted samples supported it.
```

If CI enforcement was deferred, use this CI section instead:

```text
CI:
- Deferred realistic-provider workflow gate because recorded verification shows the hosted-runner condition was not met.
- A failing workflow step was not described as merge-blocking; repository policy still controls required status checks.
```

Expected: final summary matches the verification document and git history.
