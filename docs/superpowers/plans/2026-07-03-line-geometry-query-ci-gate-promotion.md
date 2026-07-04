# Line-Geometry-Query CI Gate Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the local-only `--line-geometry-query --gate` benchmark to a blocking step in the hosted `Host tests and benchmark gate` CI job, closing the Slice 31 regression-protection gap (the seventh blocking latency gate).

**Architecture:** A pure CI-governance slice. Add one blocking step to `.github/workflows/swift-ci.yml` that invokes the existing benchmark executable exactly as local verification does, positioned after the line-query gate and before the memory-shape diagnostic. Document it in `AGENTS.md`, and record local + hosted evidence. No Swift source — core, providers, or benchmark — is touched.

**Tech Stack:** GitHub Actions YAML, Swift Package Manager (`ViewportBenchmarks` executable), Ruby (for the workflow-invariant assertion; ruby 3.x is present locally).

## Global Constraints

Copied verbatim from the spec (`docs/superpowers/specs/2026-07-03-line-geometry-query-ci-gate-promotion-design.md`). Every task's requirements implicitly include these:

- **No benchmark Swift source changes.** No scenario, budget, or helper edit. The PR's `git diff --name-only` must touch only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`.
- **No `TextEngineCore`, `TextEngineReferenceProviders`, or `lineGeometryAt`/`lineAt`/`LineMetricsSource` API changes.**
- **The line-geometry-query step must be blocking:** no `continue-on-error: true`.
- **Placement:** the step sits after `Run line query benchmark gate` and before `Run memory shape diagnostic` (order: line-query → line-geometry-query → memory-shape).
- **Budgets stay in `Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift`**, never duplicated in workflow YAML.
- **Required job context names unchanged:** `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`.
- **Keep the macOS-calibrated budgets.** If the first hosted PR-head run exceeds budget, STOP and retune budgets in `LineGeometryQueryBenchmark.swift` per spec Decision 3 — never hide a failure with `continue-on-error` or a workflow-only threshold.
- **Foundation-free invariant stands:** `rg -n "Foundation" Sources/TextEngineCore` must be empty (verification only; this slice changes no Swift).
- **Branch:** `slice-32-line-geometry-query-ci-gate-promotion` (already checked out). Conventional-commit prefixes (`ci:`, `docs:`).

---

## File Structure

- `.github/workflows/swift-ci.yml` — add one `Run line geometry query benchmark gate` step to the `host-tests-and-benchmark-gate` job (Task 1).
- `AGENTS.md` — document the line-geometry-query gate as blocking in the CI section (Task 2). The local command list (line ~92) and the benchmark-flags list (lines ~104/108) already name `--line-geometry-query`; only the **CI section** bullet needs editing.
- `docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md` — local evidence + Pending hosted section (Task 3), filled with hosted run IDs post-merge (Task 4).

---

### Task 1: Add the blocking line-geometry-query gate step to the workflow

**Files:**
- Modify: `.github/workflows/swift-ci.yml` (insert between the `Run line query benchmark gate` step and the `Run memory shape diagnostic` step)
- Test: inline Ruby workflow-invariant assertion (saved to scratchpad, not a committed file)

**Interfaces:**
- Consumes: the existing `ViewportBenchmarks` executable and its `--line-geometry-query --gate` mode (shipped in Slice 31).
- Produces: a `host-tests-and-benchmark-gate` job step named exactly `Run line geometry query benchmark gate` that runs `--line-geometry-query --gate`, is not `continue-on-error`, shares its siblings' `docs_only_pr` guard, and is ordered line-query → line-geometry-query → memory-shape. Tasks 2, 3, and 4 reference this exact step name.

- [ ] **Step 1: Write the failing workflow-invariant assertion**

Save this assertion to the scratchpad so it can be rerun verbatim before and after the change. Create `/private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ec0340fe-af0f-4134-bbba-e6bc467fc71e/scratchpad/assert_line_geometry_query_gate.rb`:

```ruby
require "yaml"

wf = YAML.load_file(".github/workflows/swift-ci.yml")
jobs = wf["jobs"]
steps = jobs["host-tests-and-benchmark-gate"]["steps"]
names = steps.map { |s| s["name"] }

lgq = steps.find { |s| s["name"] == "Run line geometry query benchmark gate" }
lq  = steps.find { |s| s["name"] == "Run line query benchmark gate" }
raise "missing line-geometry-query gate step" unless lgq
raise "missing line-query gate step" unless lq
raise "gate not invoking --line-geometry-query --gate" unless lgq["run"].include?("--line-geometry-query --gate")
raise "line-geometry-query gate must not be continue-on-error" if lgq["continue-on-error"]
raise "line-geometry-query gate must share its siblings docs-only guard" unless lgq["if"] == lq["if"]

i_lq  = names.index("Run line query benchmark gate")
i_lgq = names.index("Run line geometry query benchmark gate")
i_mem = names.index("Run memory shape diagnostic")
raise "bad gate ordering" unless i_lq && i_lgq && i_mem && i_lq < i_lgq && i_lgq < i_mem

required = ["Host tests and benchmark gate", "iOS cross-target compile", "WASM cross-target observation"]
actual = jobs.values.map { |j| j["name"] }
raise "required job context name(s) changed" unless required.all? { |n| actual.include?(n) }

puts "workflow_assertions_ok"
```

- [ ] **Step 2: Run the assertion to verify it fails**

Run: `ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ec0340fe-af0f-4134-bbba-e6bc467fc71e/scratchpad/assert_line_geometry_query_gate.rb`

Expected: non-zero exit, stderr contains `missing line-geometry-query gate step` (the step does not exist yet).

- [ ] **Step 3: Add the line-geometry-query gate step to the workflow**

In `.github/workflows/swift-ci.yml`, replace this block:

```yaml
      - name: Run line query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate

      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

with:

```yaml
      - name: Run line query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate

      - name: Run line geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-geometry-query --gate

      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

- [ ] **Step 4: Run the assertion to verify it passes**

Run: `ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ec0340fe-af0f-4134-bbba-e6bc467fc71e/scratchpad/assert_line_geometry_query_gate.rb`

Expected: exit 0, stdout `workflow_assertions_ok`.

- [ ] **Step 5: Confirm the exact command the workflow invokes passes locally**

Run: `swift run -c release ViewportBenchmarks -- --line-geometry-query --gate`

Expected: exit 0; five `mode=line_geometry_query` rows, every row `gate=pass`, `failures=0`, each row printing `budget_p95_ns` and `budget_p99_ns`. Scenarios: `uniform_1k`, `uniform_100k`, `uniform_1m`, `balanced_tree_100k`, `balanced_tree_1m`. The five deterministic checksums should match the Slice 31 record: `160641440000`, `267505512960`, `799841600000`, `223985600000`, `852321495040`.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: promote line-geometry-query benchmark to a blocking hosted gate"
```

---

### Task 2: Document the line-geometry-query gate as blocking in AGENTS.md

**Files:**
- Modify: `AGENTS.md` (CI section, the `Host tests and benchmark gate` bullet at lines ~119-131)
- Test: inline `grep` assertions

**Interfaces:**
- Consumes: the step name and ordering produced by Task 1.
- Produces: documentation only; no downstream task depends on it.

- [ ] **Step 1: Write the failing documentation assertions**

Run both checks against the current `AGENTS.md`. They are deliberately wrap-robust: the CI bullet wraps `` `--line-geometry-query --gate` `` and `(blocking)` across a line break, so a single-line phrase grep would not match. Check A counts occurrences of the exact `--line-geometry-query --gate` token (1 today, in the local command list at line ~92; the new CI bullet makes it 2). Check B flattens newlines and squeezes spaces before matching the fail-the-job sentence.

```bash
# Check A — line-geometry-query gate present in the CI host-job sequence (>= 2 occurrences)
test "$(grep -c -- '--line-geometry-query --gate' AGENTS.md)" -ge 2 && echo "step-seq OK" || echo "step-seq MISSING"
# Check B — line-geometry-query named in the "fail the job on perf regression" sentence
tr '\n' ' ' < AGENTS.md | tr -s ' ' | grep -q -- 'line-query, and line-geometry-query gates \*\*fail the job on perf regression\*\*' && echo "fail-sentence OK" || echo "fail-sentence MISSING"
```

Expected: both print `MISSING` (the line-geometry-query gate is not yet documented as blocking).

- [ ] **Step 2: Add the line-geometry-query gate to the host-job step sequence**

In `AGENTS.md`, replace:

```text
  → `--bulk-structural-mutation --gate` (blocking) → `--line-query --gate`
  (blocking) → `--memory-shape` → `--memory-observation` → realistic relative
```

with:

```text
  → `--bulk-structural-mutation --gate` (blocking) → `--line-query --gate`
  (blocking) → `--line-geometry-query --gate` (blocking) → `--memory-shape`
  → `--memory-observation` → realistic relative
```

- [ ] **Step 3: Extend the "fail the job on perf regression" sentence**

In `AGENTS.md`, replace:

```text
  variable-height, structural-mutation, bulk-structural-mutation, and line-query
  gates **fail the job on perf regression**. Benchmark budgets
```

with:

```text
  variable-height, structural-mutation, bulk-structural-mutation, line-query, and
  line-geometry-query gates **fail the job on perf regression**. Benchmark budgets
```

- [ ] **Step 4: Run the assertions to verify they pass**

```bash
test "$(grep -c -- '--line-geometry-query --gate' AGENTS.md)" -ge 2 && echo "step-seq OK" || echo "step-seq MISSING"
tr '\n' ' ' < AGENTS.md | tr -s ' ' | grep -q -- 'line-query, and line-geometry-query gates \*\*fail the job on perf regression\*\*' && echo "fail-sentence OK" || echo "fail-sentence MISSING"
```

Expected: both print `OK`.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document line-geometry-query gate as blocking in AGENTS.md CI section"
```

---

### Task 3: Record local verification evidence

**Files:**
- Create: `docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md`
- Test: the recorded command outputs are themselves the evidence

**Interfaces:**
- Consumes: the Task 1 + Task 2 changes on the branch.
- Produces: a verification doc with a fully populated local-evidence section and a clearly-marked `Pending` hosted section that Task 4 fills post-merge.

- [ ] **Step 1: Run the full local verification suite and capture outputs**

Run each command, recording exact stdout and exit status:

```bash
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
swift run -c release ViewportBenchmarks -- --line-query --gate
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift test
git diff --check
rg -n "Foundation" Sources/TextEngineCore; echo "core exit: $?"
ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ec0340fe-af0f-4134-bbba-e6bc467fc71e/scratchpad/assert_line_geometry_query_gate.rb
git diff --name-only main...HEAD
```

Expected: all gates `gate=pass`; `swift test` reports `160 tests, 0 failures` plus the `0 tests in 0 suites` Swift Testing line; `git diff --check` empty; Foundation scan `core exit: 1` (no matches); assertion prints `workflow_assertions_ok`; `git diff --name-only` lists only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`.

- [ ] **Step 2: Write the verification document**

Create `docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md` with these sections, pasting the real captured output under each:

```markdown
# Line-Geometry-Query CI Gate Promotion Verification

Date: 2026-07-03
Branch: `slice-32-line-geometry-query-ci-gate-promotion`
Local verification HEAD: `<git rev-parse --short HEAD>`

## Change Scope

`git diff --name-only main...HEAD` — only `.github/workflows/swift-ci.yml`,
`AGENTS.md`, and `docs/**`. No benchmark or core Swift source changed.

<paste git diff --name-only output>

## Workflow-Invariant Assertion

The new step exists, invokes `--line-geometry-query --gate`, is not
`continue-on-error`, shares its siblings' docs-only guard, is ordered
line-query → line-geometry-query → memory-shape, and the three required job
context names are unchanged.

<paste assertion command + `workflow_assertions_ok`>

## Line-Geometry-Query Gate (local)

<paste `--line-geometry-query --gate` output: five gate=pass rows with budget
fields; note the five deterministic checksums match the Slice 31 record>

## Pre-existing Gates Still Pass

<paste --line-query, --gate, --variable-height, --variable-height-mutation,
--structural-mutation, --bulk-structural-mutation gate outputs>

## Host Tests

<paste `swift test` summary: 160 tests, 0 failures + the 0-in-0-suites line>

## Foundation-Free Scan

<paste rg command + `core exit: 1`>

## Hosted Proof

Pending — recorded in the post-merge follow-up (Task 4) against the final stable
PR-head SHA and the merge commit, to avoid a stale-on-write hosted record.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md
git commit -m "docs: record local verification for line-geometry-query gate promotion"
```

---

### Task 4: Record post-merge hosted proof

> **Runs after the PR is opened, green, and merged to `main`.** This is the established repo pattern (see Slices 28/31): the PR-head proof is recorded only once the final head SHA is stable, and never describes a source-bearing PR as docs-only. Verify hosted runs at the **step** level, not just the job conclusion (a green job can hide a dead `continue-on-error` step).

**Files:**
- Modify: `docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md` (replace the `Pending` hosted section)

**Interfaces:**
- Consumes: the merged PR and its hosted Swift CI runs.
- Produces: the merged-code evidence anchor for the slice.

- [ ] **Step 1: Open the PR and confirm hosted CI is green**

```bash
gh pr create --base main --head slice-32-line-geometry-query-ci-gate-promotion \
  --title "Slice 32: promote line-geometry-query benchmark to a blocking hosted gate" \
  --body "<summary referencing the spec and the closed Slice 31 gap>"
gh pr checks --watch
```

Expected: all three required contexts succeed: `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`. The host job's `Run line geometry query benchmark gate` step runs (not skipped, not `continue-on-error`) and prints five Linux `line_geometry_query` rows with `gate=pass`. If the line-geometry-query step fails on budget, STOP and apply spec Decision 3 (retune budgets in `LineGeometryQueryBenchmark.swift`), do not widen via the workflow.

- [ ] **Step 2: Merge and capture the post-merge push run**

After merge, capture the final PR-head run ID and the post-merge `push` run ID on `main`:

```bash
gh run list --branch main --workflow "Swift CI" --limit 5
gh run view <run-id> --json databaseId,event,conclusion,headSha,jobs
```

Expected: the merge-commit `push` run concludes `success` with all three required jobs `success`, and the host job's `Run line geometry query benchmark gate` step `success`.

- [ ] **Step 3: Fill the hosted section and record the Linux line-geometry-query rows**

Replace the `Pending` hosted section with: final PR-head run ID + the five hosted Linux `line_geometry_query` rows (the budget-fit evidence), proof (at step level) the step is not `continue-on-error` and ran (not skipped), and the post-merge push run ID for the merge commit.

- [ ] **Step 4: Commit (and push the post-merge proof)**

```bash
git add docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md
git commit -m "docs: record slice 32 post-merge proof"
```

---

## Acceptance Criteria (from spec)

- `.github/workflows/swift-ci.yml` has a `Run line geometry query benchmark gate` step invoking `--line-geometry-query --gate`, with no `continue-on-error: true`, positioned line-query → line-geometry-query → memory-shape.
- The three required job context names are unchanged.
- The PR `git diff --name-only` touches only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**` (no benchmark Swift edit).
- `AGENTS.md` describes the line-geometry-query benchmark as a blocking host-job gate that fails the job on perf regression.
- Local line-geometry-query gate passes `gate=pass` for all five scenarios; the six pre-existing latency gates and `swift test` still pass.
- Hosted PR-head CI runs the line-geometry-query gate step and succeeds, with the five Linux p95/p99 rows recorded as budget-fit evidence.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Post-Plan Next Step

After Task 4, a separate **post-slice review** (`docs/superpowers/reviews/2026-07-03-slice-32-post-slice-review.md` on a `slice-32-post-slice-review` branch) closes the slice and recommends Slice 33. Per the Slice 31 review, the project is then back at the capability-vs-infra crossroads: Option B (provider-native geometry-bearing descent, now that its gate is blocking), Option C (horizontal/point/wrap capability building on `LineGeometryLocation`), or Option E (WASM-blocking / Linux budget re-baseline). That is a product call for the user. The review is its own lifecycle step, not a task in this plan.
