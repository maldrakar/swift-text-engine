# Bulk-Structural-Mutation CI Gate Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the `--bulk-structural-mutation` benchmark to a blocking hosted CI gate, and harden the deterministic index-mixing idiom shared by both structural-mutation benchmarks against integer-overflow crashes.

**Architecture:** Add one blocking `swift run … --bulk-structural-mutation --gate` step to the existing `Host tests and benchmark gate` job (the fifth contiguous latency gate). Separately, extract the `(sample &* multiplier) % modulus` index pattern — currently duplicated and signed-overflow-unsafe in both `BulkStructuralMutationBenchmark.swift` and the already-blocking `StructuralMutationBenchmark.swift` — into one `deterministicIndex` helper in `BenchmarkSupport.swift` that mixes in `UInt`, proven behavior-preserving by per-scenario checksum equality.

**Tech Stack:** Swift 6.0 (SwiftPM), GitHub Actions YAML, Ruby (for the local YAML workflow assertion; preinstalled on macOS and the CI image).

## Global Constraints

Copied verbatim from the spec and AGENTS.md; every task implicitly includes these:

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must be empty (exit 1). This slice touches no core source, so this stays trivially true and is re-verified at the end.
- **No `TextEngineCore` or `TextEngineReferenceProviders` (provider/algorithm) changes.** Only the three benchmark files, the workflow, AGENTS.md, and the verification doc change.
- **No benchmark scenario, budget, iteration-count, or summary-field change** in either benchmark unless a hosted run forces a retune (spec Decision 3).
- **Budgets live in `Sources/ViewportBenchmarks`, never duplicated in workflow YAML.**
- **The new gate step must not be `continue-on-error: true`.**
- **The three required job context names are unchanged:** `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`.
- **Conventional commits, one logical step per commit.** Prefixes in use: `feat:`, `test:`, `refactor:`, `docs:`, `ci:`.
- **All work on branch `slice-26-bulk-structural-mutation-ci-gate-promotion`** (already checked out; the spec is already committed there as `42ece0e` / `e35cb04`).

---

## File Structure

- `Sources/ViewportBenchmarks/BenchmarkSupport.swift` — gains the shared `deterministicIndex(sample:multiplier:modulus:)` helper, next to the existing shared helpers (`nanoseconds`, `percentile`, `deterministicScrollOffset`).
- `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift` — its two index expressions (lines 127 / 131) call the helper.
- `Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift` — its two index expressions (lines 90 / 94) call the helper.
- `.github/workflows/swift-ci.yml` — gains the blocking `Run bulk structural mutation benchmark gate` step in the host job, between the structural-mutation gate and the memory-shape diagnostic.
- `AGENTS.md` — CI section lists the bulk gate as blocking and names it in the "fail the job on perf regression" sentence.
- `docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md` — the evidence record: pre-edit checksum baseline, post-edit checksum equality, local gate sweep, and hosted-run anchors.

## Task ordering rationale

Baseline → harden → promote → document. The checksum baseline (Task 1) must be captured on the **pre-edit** tree, so it comes first. Hardening (Task 2) makes the gate crash-safe before Task 3 makes it blocking. AGENTS.md (Task 4) and the verification finalization (Task 5) follow.

---

### Task 1: Capture the pre-hardening checksum baseline

**Files:**
- Create: `docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the recorded per-scenario `checksum=` values for `bulk_structural_mutation` (5 scenarios) and `structural_mutation` (3 scenarios), used by Task 2's equality proof.

This task changes **no Swift source**. It records the deterministic checksums emitted by the two gates on the current (pre-edit) tree, so Task 2 can prove its refactor is behavior-preserving.

- [ ] **Step 1: Run the bulk gate and capture its checksum rows**

Run:
```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
```
Expected: exit `0`; five rows beginning `mode=bulk_structural_mutation … gate=pass … checksum=<N>`. Record each scenario's full line (note `formatSummary` always appends `checksum=`, even though the Slice 25 verification doc abbreviated its rows and dropped it).

- [ ] **Step 2: Run the structural gate and capture its checksum rows**

Run:
```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```
Expected: exit `0`; three rows beginning `mode=structural_mutation … gate=pass … checksum=<N>`. Record each.

- [ ] **Step 3: Write the verification doc with the baseline section**

Create `docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md` with this skeleton (fill the `checksum=` and p95/p99 values from Steps 1–2; leave hosted sections as `Pending`):

```markdown
# Bulk-Structural-Mutation CI Gate Promotion Verification

Date: 2026-06-21
Slice: 26
Branch: slice-26-bulk-structural-mutation-ci-gate-promotion

## Pre-Hardening Checksum Baseline (pre-edit tree)

Captured before the `deterministicIndex` refactor, to prove behavior preservation.

### `--bulk-structural-mutation --gate`

Command:
\`\`\`bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
\`\`\`
Exit status: `0`.

\`\`\`text
<paste the five mode=bulk_structural_mutation rows, including checksum=>
\`\`\`

### `--structural-mutation --gate`

Command:
\`\`\`bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
\`\`\`
Exit status: `0`.

\`\`\`text
<paste the three mode=structural_mutation rows, including checksum=>
\`\`\`

## Post-Hardening Checksum Equality

_Filled in Task 2._

## Local Gate Sweep

_Filled in Task 5._

## Hosted Evidence

_Filled in the post-merge follow-up (PR-head run, post-merge push run)._ Pending.
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md
git commit -m "docs: record pre-hardening checksum baseline for slice 26"
```

---

### Task 2: Add the `deterministicIndex` helper and apply it to both mutation benchmarks

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkSupport.swift` (insert after `deterministicScrollOffset`, line 21)
- Modify: `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift:127,131`
- Modify: `Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift:90,94`
- Test: the checksum-equality check is the test (no XCTest target exists for the benchmark executable; spec Non-Goal forbids adding one).

**Interfaces:**
- Consumes: the Task 1 baseline checksums.
- Produces: `func deterministicIndex(sample: Int, multiplier: UInt, modulus: Int) -> Int` in the benchmark target, used by both mutation benchmarks.

This is a behavior-preserving refactor. The "failing-first" signal is structural: before the edit, `rg` finds the unsafe signed `&*`-into-`%` index pattern; after the edit, it finds none and the checksums are unchanged.

- [ ] **Step 1: Write the failing structural check (the unsafe pattern still exists)**

Run:
```bash
rg -n "&\* (2_654_435_761|40_503)" Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift
```
Expected (pre-edit): **four** matches — bulk lines 127/131 and structural lines 90/94. This is the unsafe pattern the refactor removes; its presence is the red state.

- [ ] **Step 2: Add the helper to `BenchmarkSupport.swift`**

Insert immediately after the `deterministicScrollOffset` function (after line 21), before the `@inline(never)` on line 23:

```swift
// Deterministic, always-non-negative index in 0..<modulus. Mixing is done in
// UInt so the wrapping multiply can never produce a negative dividend that
// Swift's signed `%` would carry into a negative index (which would trip an
// `index >= 0` precondition and crash a benchmark gate). `modulus` must be > 0.
func deterministicIndex(sample: Int, multiplier: UInt, modulus: Int) -> Int {
    Int(UInt(bitPattern: sample) &* multiplier % UInt(modulus))
}
```

(`&*` and `%` share precedence and associate left, so this is `(UInt(bitPattern: sample) &* multiplier) % UInt(modulus)`. The result is in `0..<modulus ≤ 1_000_000`, so `Int(_:)` cannot trap.)

- [ ] **Step 3: Apply the helper in `BulkStructuralMutationBenchmark.swift`**

In `runBulkStructuralMutationScenario`, replace lines 127 and 131. Introduce a single `modulus` binding and use it for both indices. The surrounding lines (the `metrics.removeLines` / `metrics.insertLines` calls) stay unchanged:

Replace:
```swift
            let removeIndex = (sample &* 2_654_435_761) % (lineCount - batch + 1)
            metrics.removeLines(at: removeIndex, count: batch)
            checksum &+= metrics.lastMutationNodeVisits

            let insertIndex = (sample &* 40_503) % (lineCount - batch + 1)
```
with:
```swift
            let modulus = lineCount - batch + 1
            let removeIndex = deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: modulus)
            metrics.removeLines(at: removeIndex, count: batch)
            checksum &+= metrics.lastMutationNodeVisits

            let insertIndex = deterministicIndex(sample: sample, multiplier: 40_503, modulus: modulus)
```

- [ ] **Step 4: Apply the helper in `StructuralMutationBenchmark.swift`**

In `runStructuralMutationScenario`, replace lines 90 and 94 (modulus is `lineCount`):

Replace:
```swift
            let removeIndex = (sample &* 2_654_435_761) % lineCount
```
with:
```swift
            let removeIndex = deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: lineCount)
```

Replace:
```swift
            let insertIndex = (sample &* 40_503) % lineCount
```
with:
```swift
            let insertIndex = deterministicIndex(sample: sample, multiplier: 40_503, modulus: lineCount)
```

- [ ] **Step 5: Verify the unsafe pattern is gone (structural check now passes)**

Run:
```bash
rg -n "&\* (2_654_435_761|40_503)" Sources/ViewportBenchmarks/
```
Expected: **no matches** (exit 1). The only remaining references to those constants are inside the `deterministicIndex` call sites.

- [ ] **Step 6: Re-run both gates and prove the checksums are unchanged**

Run:
```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```
Expected: both exit `0`, all `gate=pass`, and **every per-scenario `checksum=` value is byte-identical to the Task 1 baseline** (5 bulk + 3 structural). If any checksum differs, STOP — the refactor changed behavior; debug before continuing (the index values must be identical at current parameters). p95/p99 may differ (timing noise); only `checksum=` is asserted.

- [ ] **Step 7: Record the equality in the verification doc**

Fill the "Post-Hardening Checksum Equality" section of `docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md`: paste the post-edit rows and state explicitly that all eight `checksum=` values match the baseline.

- [ ] **Step 8: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkSupport.swift \
        Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift \
        Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift \
        docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md
git commit -m "refactor: harden benchmark index mixing via shared deterministicIndex helper"
```

---

### Task 3: Wire the blocking bulk gate into CI (assertion-first)

**Files:**
- Modify: `.github/workflows/swift-ci.yml` (host job, after the structural-mutation gate step, before the memory-shape diagnostic step)
- Test: the Ruby/YAML workflow-invariant assertion below.

**Interfaces:**
- Consumes: nothing.
- Produces: a `Run bulk structural mutation benchmark gate` step in the `host-tests-and-benchmark-gate` job.

- [ ] **Step 1: Save the workflow assertion as the failing test**

This assertion checks the four invariants acceptance requires (step exists, invokes the gate, not `continue-on-error`, ordered structural → bulk → memory). Run it against the current workflow:

```bash
ruby -ryaml -e '
  wf = YAML.load_file(".github/workflows/swift-ci.yml")
  steps = wf["jobs"]["host-tests-and-benchmark-gate"]["steps"]
  names = steps.map { |s| s["name"] }
  bulk = steps.find { |s| s["name"] == "Run bulk structural mutation benchmark gate" }
  raise "missing bulk gate step" unless bulk
  raise "bulk gate not invoking --bulk-structural-mutation --gate" unless bulk["run"].include?("--bulk-structural-mutation --gate")
  raise "bulk gate must not be continue-on-error" if bulk["continue-on-error"]
  i_struct = names.index("Run structural mutation benchmark gate")
  i_bulk   = names.index("Run bulk structural mutation benchmark gate")
  i_mem    = names.index("Run memory shape diagnostic")
  raise "bad gate ordering" unless i_struct && i_bulk && i_mem && i_struct < i_bulk && i_bulk < i_mem
  puts "workflow_assertions_ok"
'
```
Expected (pre-edit): the Ruby process exits non-zero with `missing bulk gate step`. This is the red state.

- [ ] **Step 2: Add the blocking gate step to the workflow**

In `.github/workflows/swift-ci.yml`, insert this step between the `Run structural mutation benchmark gate` step and the `Run memory shape diagnostic` step (currently lines 102–108):

```yaml
      - name: Run bulk structural mutation benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --bulk-structural-mutation --gate
```

It must have **no** `continue-on-error:` line. Use spaces (the file is 6-space-indented under `steps:`); do not introduce tabs.

- [ ] **Step 3: Run the assertion again (now green)**

Run the same Ruby block from Step 1.
Expected: prints `workflow_assertions_ok`, exit `0`.

- [ ] **Step 4: Sanity-check the YAML still parses and diff is whitespace-clean**

Run:
```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"
git diff --check
```
Expected: `yaml_ok`; `git diff --check` prints nothing (no whitespace errors), exit `0`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: add blocking bulk-structural-mutation benchmark gate"
```

---

### Task 4: Update AGENTS.md CI section

**Files:**
- Modify: `AGENTS.md` (CI section, the `Host tests and benchmark gate` bullet, lines ~104 and ~106–108)

**Interfaces:**
- Consumes: nothing.
- Produces: durable guidance that the bulk gate is blocking.

- [ ] **Step 1: Add the bulk gate to the host-job step sequence**

In `AGENTS.md`, find (line ~104):
```text
  (blocking) → `--structural-mutation --gate` (blocking) → `--memory-shape`
```
Replace with:
```text
  (blocking) → `--structural-mutation --gate` (blocking)
  → `--bulk-structural-mutation --gate` (blocking) → `--memory-shape`
```

- [ ] **Step 2: Name the bulk gate in the "fail the job on perf regression" sentence**

Find (lines ~106–108):
```text
  → `--memory-observation` → realistic relative observation (PR-only,
  `continue-on-error`). The synthetic, static variable-height, mutation
  variable-height, and structural-mutation gates **fail the job on perf
  regression**. Benchmark budgets
```
Replace the gate list so it reads:
```text
  → `--memory-observation` → realistic relative observation (PR-only,
  `continue-on-error`). The synthetic, static variable-height, mutation
  variable-height, structural-mutation, and bulk-structural-mutation gates
  **fail the job on perf regression**. Benchmark budgets
```

- [ ] **Step 3: Confirm no other AGENTS.md change is needed**

Run:
```bash
rg -n "bulk-structural-mutation|bulk_structural_mutation" AGENTS.md
```
Expected: the command-list line (`--bulk-structural-mutation --gate` local gate, line ~74), the two benchmark-flags-list mentions (lines ~86 / ~90), and the two CI-section lines just edited. The command list and flags lists already include the mode from Slice 25 and need no change.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document bulk-structural-mutation as a blocking CI gate"
```

---

### Task 5: Finalize the verification record with the local sweep

**Files:**
- Modify: `docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md`

**Interfaces:**
- Consumes: the workflow assertion from Task 3.
- Produces: the complete local-evidence record (hosted sections stay `Pending` until the PR runs).

- [ ] **Step 1: Run the full local sweep and capture outputs**

Run each and record exit status + representative output:
```bash
swift test
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
git diff --check
rg -n "Foundation" Sources/TextEngineCore
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"
```
Expected: `swift test` all pass; every gate `gate=pass`; `git diff --check` empty; the Foundation scan prints nothing (exit 1); `yaml_ok`. Also re-run the Task 3 Step 1 Ruby assertion and capture `workflow_assertions_ok`.

- [ ] **Step 2: Fill the "Local Gate Sweep" section**

Record the commands, exit statuses, representative rows, and the `workflow_assertions_ok` line in the verification doc. Restate that the eight mutation checksums equal the Task 1 baseline (cross-reference the post-hardening section).

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md
git commit -m "docs: record local verification sweep for slice 26"
```

---

### Task 6: Open the PR and record hosted evidence

**Files:**
- Modify (post-merge follow-up): `docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md`

**Interfaces:**
- Consumes: the pushed branch.
- Produces: the hosted-run anchors (PR-head run + post-merge push run).

This task follows the project's evidence discipline (spec Verification Record; Slice 24/25 lessons): the PR-head proof is recorded **only in the post-merge follow-up**, against the final stable head SHA, and a source-bearing PR head is **never** described as taking the docs-only shortcut.

- [ ] **Step 1: Push the branch and open the PR**

```bash
git push -u origin slice-26-bulk-structural-mutation-ci-gate-promotion
gh pr create --base main \
  --title "Slice 26: Bulk-structural-mutation CI gate promotion" \
  --body "<summary: promote bulk gate to blocking; harden shared index helper; link spec/plan/verification>"
```

- [ ] **Step 2: Watch the required checks**

```bash
gh pr checks --watch
```
Expected: all three required jobs `success`. The host job runs the heavy path (not docs-only) and now includes `Run bulk structural mutation benchmark gate`.

- [ ] **Step 3: Confirm the hosted bulk gate ran and fits Linux budgets**

Inspect the host job's `Run bulk structural mutation benchmark gate` step log: all five `bulk_structural_mutation` rows show `gate=pass`, `budget_p95_ns`, `budget_p99_ns` (the first hosted Linux x86_64 evidence for this mode). If any scenario **fails** the budget on Linux, STOP and follow spec Decision 3: re-derive Linux-fit budgets in `BulkStructuralMutationBenchmark.swift` in this same PR; do not add `continue-on-error` or a workflow threshold.

- [ ] **Step 4: Merge, then capture the post-merge push run**

After merge to `main`, find the `push`-event Swift CI run on the merge commit and confirm all three required jobs `success` and the bulk gate step `success`. This is the merged-code anchor.

- [ ] **Step 5: Record hosted evidence in a post-merge follow-up PR**

On a fresh `slice-26-post-merge-verification` branch, fill the verification doc's "Hosted Evidence" section with: the final PR-head SHA + run ID (all three jobs `success`, heavy path, bulk step `success` with the five Linux rows), proof the bulk step is not `continue-on-error`, and the post-merge push run ID. Commit `docs: record bulk-structural-mutation gate post-merge proof` and open/merge the follow-up PR.

---

## Self-Review

**Spec coverage:**
- Workflow blocking gate step (spec Goals, Decision 1/2/4, Architecture) → Task 3.
- Budgets stay in benchmark, not YAML (spec Decision 2) → Task 3 Step 2 invokes the executable; no YAML budgets.
- Step position structural → bulk → memory (spec Decision 4, Acceptance) → Task 3 assertion enforces order.
- No `continue-on-error` (spec Goals, Decision 8) → Task 3 assertion + Step 2 instruction.
- Shared `deterministicIndex` helper applied to both mutation benchmarks (spec Decision 5, Scope) → Task 2.
- Behavior-preserving, checksum-equality proof with baseline captured in the Slice 26 record (spec Decision 5, Verification) → Task 1 (baseline) + Task 2 (equality).
- `VariableHeightBenchmark` bucket selector excluded (spec Decision 5) → not touched; Task 2 Step 5 `rg` scopes to the two constants only.
- Required context names unchanged (spec Decision 6, Acceptance) → no job added/renamed; only a step added.
- Docs-only behavior unchanged (spec Decision 7) → no detector/job-guard change.
- AGENTS.md lists the bulk gate as blocking (spec Goals, Architecture) → Task 4.
- Verification record: local minimum + workflow assertion + checksum baseline + hosted anchors (spec Verification, Acceptance) → Tasks 1, 5, 6.
- PR-head proof discipline (spec Verification; Slice 24/25 lessons) → Task 6 Step 5.
- Foundation-free core re-verified (Global Constraints) → Task 5 Step 1.

**Placeholder scan:** No TBD/TODO; every code/edit step shows exact content. The verification-doc body intentionally contains `<paste …>` capture markers — these are runtime-captured outputs, not plan placeholders.

**Type consistency:** `deterministicIndex(sample: Int, multiplier: UInt, modulus: Int) -> Int` is defined once (Task 2 Step 2) and called with the same labels/arities in Task 2 Steps 3–4 (bulk `modulus = lineCount - batch + 1`; structural `modulus = lineCount`). The literals `2_654_435_761` and `40_503` infer to `UInt` from the parameter type. Step names referenced by the Ruby assertion (`Run structural mutation benchmark gate`, `Run bulk structural mutation benchmark gate`, `Run memory shape diagnostic`) match the workflow's existing/added step names exactly.
