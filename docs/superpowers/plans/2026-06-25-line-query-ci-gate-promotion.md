# Line-Query CI Gate Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the local-only `--line-query --gate` benchmark to a blocking step in the hosted `Host tests and benchmark gate` CI job, closing the Slice 27 regression-protection gap.

**Architecture:** A pure CI-governance slice. Add one blocking step to `.github/workflows/swift-ci.yml` that invokes the existing benchmark executable exactly as local verification does, positioned after the bulk-structural-mutation gate and before the memory-shape diagnostic. Document it in `AGENTS.md`, and record local + hosted evidence. No Swift source — core, providers, or benchmark — is touched.

**Tech Stack:** GitHub Actions YAML, Swift Package Manager (`ViewportBenchmarks` executable), Ruby (for the workflow-invariant assertion; ruby 3.2 is present locally).

## Global Constraints

Copied verbatim from the spec (`docs/superpowers/specs/2026-06-25-line-query-ci-gate-promotion-design.md`). Every task's requirements implicitly include these:

- **No benchmark Swift source changes.** No scenario, budget, or helper edit. The PR's `git diff --name-only` must touch only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`.
- **No `TextEngineCore`, `TextEngineReferenceProviders`, or `lineAt`/`LineMetricsSource` API changes.**
- **The line-query step must be blocking:** no `continue-on-error: true`.
- **Placement:** the step sits after `Run bulk structural mutation benchmark gate` and before `Run memory shape diagnostic` (order: bulk → line-query → memory-shape).
- **Budgets stay in `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`**, never duplicated in workflow YAML.
- **Required job context names unchanged:** `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`.
- **Keep the macOS-calibrated budgets.** If the first hosted PR-head run exceeds budget, STOP and retune budgets in `LineQueryBenchmark.swift` per spec Decision 3 — never hide a failure with `continue-on-error` or a workflow-only threshold.
- **Foundation-free invariant stands:** `rg -n "Foundation" Sources/TextEngineCore` must be empty (verification only; this slice changes no Swift).
- **Branch:** `slice-28-line-query-ci-gate-promotion`. Conventional-commit prefixes (`ci:`, `docs:`).

---

## File Structure

- `.github/workflows/swift-ci.yml` — add one `Run line query benchmark gate` step to the `host-tests-and-benchmark-gate` job (Task 1).
- `AGENTS.md` — document the line-query gate as blocking in the CI section (Task 2).
- `docs/superpowers/verification/2026-06-25-line-query-ci-gate-promotion.md` — local evidence + Pending hosted section (Task 3), filled with hosted run IDs post-merge (Task 4).

---

### Task 1: Add the blocking line-query gate step to the workflow

**Files:**
- Modify: `.github/workflows/swift-ci.yml` (insert between the `Run bulk structural mutation benchmark gate` step and the `Run memory shape diagnostic` step)
- Test: inline Ruby workflow-invariant assertion (not a committed file)

**Interfaces:**
- Consumes: the existing `ViewportBenchmarks` executable and its `--line-query --gate` mode (shipped in Slice 27).
- Produces: a `host-tests-and-benchmark-gate` job step named exactly `Run line query benchmark gate` that runs `--line-query --gate`, is not `continue-on-error`, and is ordered bulk → line-query → memory-shape. Tasks 2 and 3 reference this exact step name.

- [ ] **Step 1: Write the failing workflow-invariant assertion**

Save this assertion to the scratchpad so it can be rerun verbatim before and after the change:

Create `/private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ff85db83-a037-4e01-8c67-32ccd2c40b6b/scratchpad/assert_line_query_gate.rb`:

```ruby
require "yaml"

wf = YAML.load_file(".github/workflows/swift-ci.yml")
steps = wf["jobs"]["host-tests-and-benchmark-gate"]["steps"]
names = steps.map { |s| s["name"] }

lq = steps.find { |s| s["name"] == "Run line query benchmark gate" }
raise "missing line-query gate step" unless lq
raise "line-query gate not invoking --line-query --gate" unless lq["run"].include?("--line-query --gate")
raise "line-query gate must not be continue-on-error" if lq["continue-on-error"]

i_bulk = names.index("Run bulk structural mutation benchmark gate")
i_lq   = names.index("Run line query benchmark gate")
i_mem  = names.index("Run memory shape diagnostic")
raise "bad gate ordering" unless i_bulk && i_lq && i_mem && i_bulk < i_lq && i_lq < i_mem

puts "workflow_assertions_ok"
```

- [ ] **Step 2: Run the assertion to verify it fails**

Run: `ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ff85db83-a037-4e01-8c67-32ccd2c40b6b/scratchpad/assert_line_query_gate.rb`

Expected: non-zero exit, stderr contains `missing line-query gate step` (the step does not exist yet).

- [ ] **Step 3: Add the line-query gate step to the workflow**

In `.github/workflows/swift-ci.yml`, replace this block:

```yaml
      - name: Run bulk structural mutation benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --bulk-structural-mutation --gate

      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

with:

```yaml
      - name: Run bulk structural mutation benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --bulk-structural-mutation --gate

      - name: Run line query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate

      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

- [ ] **Step 4: Run the assertion to verify it passes**

Run: `ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ff85db83-a037-4e01-8c67-32ccd2c40b6b/scratchpad/assert_line_query_gate.rb`

Expected: exit 0, stdout `workflow_assertions_ok`.

- [ ] **Step 5: Confirm the exact command the workflow invokes passes locally**

Run: `swift run -c release ViewportBenchmarks -- --line-query --gate`

Expected: exit 0; five `mode=line_query` rows, every row `gate=pass`, `failures=0`, each row printing `budget_p95_ns` and `budget_p99_ns`. Scenarios: `uniform_1k`, `uniform_100k`, `uniform_1m`, `balanced_tree_100k`, `balanced_tree_1m`.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: promote line-query benchmark to a blocking hosted gate"
```

---

### Task 2: Document the line-query gate as blocking in AGENTS.md

**Files:**
- Modify: `AGENTS.md` (CI section, the `Host tests and benchmark gate` bullet at lines ~105-116)
- Test: inline `grep` assertions

**Interfaces:**
- Consumes: the step name and ordering produced by Task 1.
- Produces: documentation only; no downstream task depends on it.

- [ ] **Step 1: Write the failing documentation assertions**

Run both checks against the current `AGENTS.md`. They are deliberately
wrap-robust: the CI bullet wraps `` `--line-query --gate` `` and `(blocking)`
across a line break, so a single-line phrase grep would not match. Check A counts
occurrences of the exact `--line-query --gate` token (1 today in the local
command list at line ~78; the new CI bullet makes it 2). Check B flattens
newlines and squeezes spaces before matching the fail-the-job sentence.

```bash
# Check A — line-query gate present in the CI host-job sequence (>= 2 occurrences)
test "$(grep -c -- '--line-query --gate' AGENTS.md)" -ge 2 && echo "step-seq OK" || echo "step-seq MISSING"
# Check B — line-query named in the "fail the job on perf regression" sentence
tr '\n' ' ' < AGENTS.md | tr -s ' ' | grep -q -- 'bulk-structural-mutation, and line-query gates \*\*fail the job on perf regression\*\*' && echo "fail-sentence OK" || echo "fail-sentence MISSING"
```

Expected: both print `MISSING` (the line-query gate is not yet documented as blocking).

- [ ] **Step 2: Add the line-query gate to the host-job step sequence**

In `AGENTS.md`, replace:

```text
  → `--bulk-structural-mutation --gate` (blocking) → `--memory-shape`
```

with:

```text
  → `--bulk-structural-mutation --gate` (blocking) → `--line-query --gate`
  (blocking) → `--memory-shape`
```

- [ ] **Step 3: Extend the "fail the job on perf regression" sentence**

In `AGENTS.md`, replace:

```text
  variable-height, structural-mutation, and bulk-structural-mutation gates
  **fail the job on perf regression**. Benchmark budgets
```

with:

```text
  variable-height, structural-mutation, bulk-structural-mutation, and line-query
  gates **fail the job on perf regression**. Benchmark budgets
```

- [ ] **Step 4: Run the assertions to verify they pass**

```bash
test "$(grep -c -- '--line-query --gate' AGENTS.md)" -ge 2 && echo "step-seq OK" || echo "step-seq MISSING"
tr '\n' ' ' < AGENTS.md | tr -s ' ' | grep -q -- 'bulk-structural-mutation, and line-query gates \*\*fail the job on perf regression\*\*' && echo "fail-sentence OK" || echo "fail-sentence MISSING"
```

Expected: both print `OK`.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document line-query gate as blocking in AGENTS.md CI section"
```

---

### Task 3: Record local verification evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-25-line-query-ci-gate-promotion.md`
- Test: the recorded command outputs are themselves the evidence

**Interfaces:**
- Consumes: the merged Task 1 + Task 2 changes on the branch.
- Produces: a verification doc with a fully populated local-evidence section and a clearly-marked `Pending` hosted section that Task 4 fills post-merge.

- [ ] **Step 1: Run the full local verification suite and capture outputs**

Run each command, recording exact stdout and exit status:

```bash
swift run -c release ViewportBenchmarks -- --line-query --gate
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift test
git diff --check
rg -n "Foundation" Sources/TextEngineCore; echo "core exit: $?"
ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ff85db83-a037-4e01-8c67-32ccd2c40b6b/scratchpad/assert_line_query_gate.rb
git diff --name-only main...HEAD
```

Expected: all gates `gate=pass`; `swift test` reports `124 tests, 0 failures` plus the `0 tests in 0 suites` Swift Testing line; `git diff --check` empty; Foundation scan `core exit: 1` (no matches); assertion prints `workflow_assertions_ok`; `git diff --name-only` lists only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`.

- [ ] **Step 2: Write the verification document**

Create `docs/superpowers/verification/2026-06-25-line-query-ci-gate-promotion.md` with these sections, pasting the real captured output under each:

```markdown
# Line-Query CI Gate Promotion Verification

Date: 2026-06-25
Branch: `slice-28-line-query-ci-gate-promotion`
Local verification HEAD: `<git rev-parse --short HEAD>`

## Change Scope

`git diff --name-only main...HEAD` — only `.github/workflows/swift-ci.yml`,
`AGENTS.md`, and `docs/**`. No benchmark or core Swift source changed.

<paste git diff --name-only output>

## Workflow-Invariant Assertion

The new step exists, invokes `--line-query --gate`, is not `continue-on-error`,
and is ordered bulk → line-query → memory-shape.

<paste assertion command + `workflow_assertions_ok`>

## Line-Query Gate (local)

<paste `--line-query --gate` output: five gate=pass rows with budget fields>

## Pre-existing Gates Still Pass

<paste --gate, --variable-height --gate, --variable-height-mutation --gate,
--structural-mutation --gate, --bulk-structural-mutation --gate outputs>

## Host Tests

<paste `swift test` summary: 124 tests, 0 failures + the 0-in-0-suites line>

## Foundation-Free Scan

<paste rg command + `core exit: 1`>

## Hosted Proof

Pending — recorded in the post-merge follow-up (Task 4) against the final stable
PR-head SHA and the merge commit, to avoid a stale-on-write hosted record.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/verification/2026-06-25-line-query-ci-gate-promotion.md
git commit -m "docs: record local verification for line-query gate promotion"
```

---

### Task 4: Record post-merge hosted proof

> **Runs after the PR is opened, green, and merged to `main`.** This is the established repo pattern (see Slice 27): the PR-head proof is recorded only once the final head SHA is stable, and never describes a source-bearing PR as docs-only.

**Files:**
- Modify: `docs/superpowers/verification/2026-06-25-line-query-ci-gate-promotion.md` (replace the `Pending` hosted section)

**Interfaces:**
- Consumes: the merged PR and its hosted Swift CI runs.
- Produces: the merged-code evidence anchor for the slice.

- [ ] **Step 1: Open the PR and confirm hosted CI is green**

```bash
gh pr create --base main --head slice-28-line-query-ci-gate-promotion \
  --title "Slice 28: promote line-query benchmark to a blocking hosted gate" \
  --body "<summary referencing the spec and the closed Slice 27 gap>"
gh pr checks --watch
```

Expected: all three required contexts succeed: `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`. The host job's `Run line query benchmark gate` step runs (not skipped, not `continue-on-error`) and prints five Linux `line_query` rows with `gate=pass`. If the line-query step fails on budget, STOP and apply spec Decision 3 (retune budgets in `LineQueryBenchmark.swift`), do not widen via the workflow.

- [ ] **Step 2: Merge and capture the post-merge push run**

After merge, capture the final PR-head run ID and the post-merge `push` run ID on `main`:

```bash
gh run list --branch main --workflow "Swift CI" --limit 5
gh run view <run-id> --json databaseId,event,conclusion,headSha,jobs
```

Expected: the merge-commit `push` run concludes `success` with all three required jobs `success`, and the host job's `Run line query benchmark gate` step `success`.

- [ ] **Step 3: Fill the hosted section and record the Linux line-query rows**

Replace the `Pending` hosted section with: final PR-head run ID + the five hosted Linux `line_query` rows (the budget-fit evidence), proof the step is not `continue-on-error`, and the post-merge push run ID for the merge commit.

- [ ] **Step 4: Commit (and push the post-merge proof)**

```bash
git add docs/superpowers/verification/2026-06-25-line-query-ci-gate-promotion.md
git commit -m "docs: record slice 28 post-merge proof"
```

---

## Acceptance Criteria (from spec)

- `.github/workflows/swift-ci.yml` has a `Run line query benchmark gate` step invoking `--line-query --gate`, with no `continue-on-error: true`, positioned bulk → line-query → memory-shape.
- The three required job context names are unchanged.
- The PR `git diff --name-only` touches only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**` (no benchmark Swift edit).
- `AGENTS.md` describes the line-query benchmark as a blocking host-job gate that fails the job on perf regression.
- Local line-query gate passes `gate=pass` for all five scenarios; the five pre-existing latency gates and `swift test` still pass.
- Hosted PR-head CI runs the line-query gate step and succeeds, with the five Linux p95/p99 rows recorded as budget-fit evidence.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Post-Plan Next Step

After Task 4, a separate **post-slice review** (`docs/superpowers/reviews/2026-06-25-slice-28-post-slice-review.md` on a `slice-28-post-slice-review` branch) closes the slice and recommends Slice 29 — most likely Option B (provider-native prefix search) or Option D (horizontal/wrap-aware capability). The review is its own lifecycle step, not a task in this plan.
