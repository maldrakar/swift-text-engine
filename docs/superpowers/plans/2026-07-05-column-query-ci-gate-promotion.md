# Column-Query CI Gate Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the local-only `--column-query --gate` benchmark to a blocking step in the hosted `Host tests and benchmark gate` CI job, closing the Slice 33 regression-protection gap (the eighth blocking latency gate).

**Architecture:** A pure CI-governance slice. Add one blocking step to `.github/workflows/swift-ci.yml` that invokes the existing benchmark executable exactly as local verification does, positioned after the line-geometry-query gate and before the memory-shape diagnostic. Document it in `AGENTS.md` (both the architecture paragraph and the CI section), and record local + hosted evidence. No Swift source — core, providers, or benchmark — is touched.

**Tech Stack:** GitHub Actions YAML, Swift Package Manager (`ViewportBenchmarks` executable), Ruby (for the workflow-invariant assertion; ruby 3.x is present locally).

## Global Constraints

Copied verbatim from the spec (`docs/superpowers/specs/2026-07-05-column-query-ci-gate-promotion-design.md`). Every task's requirements implicitly include these:

- **No benchmark Swift source changes.** No scenario, budget, or helper edit. The PR's `git diff --name-only` must touch only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`.
- **No `TextEngineCore`, `TextEngineReferenceProviders`, or `columnAt`/`LineHorizontalMetricsSource` API changes.**
- **The column-query step must be blocking:** no `continue-on-error: true`.
- **Placement:** the step sits after `Run line geometry query benchmark gate` and before `Run memory shape diagnostic` (order: line-geometry-query → column-query → memory-shape).
- **Budgets stay in `Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift`**, never duplicated in workflow YAML.
- **Required job context names unchanged:** `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`.
- **Keep the macOS-calibrated budgets.** If the first hosted PR-head run exceeds budget, STOP and retune budgets in `ColumnQueryBenchmark.swift` per spec Decision 3 — never hide a failure with `continue-on-error` or a workflow-only threshold. `prefixsum_1m` is the watch-scenario.
- **Benchmark-unchanged integrity check:** the five per-scenario `column_query` checksums must stay byte-identical to the Slice 33 values `641440000`, `63985556480`, `639841600000`, `63985600000`, `639841560320`. A drift means the workload changed — which this slice forbids.
- **Foundation-free invariant stands:** `rg -n "Foundation" Sources/TextEngineCore` must be empty (verification only; this slice changes no Swift).
- **Branch:** `slice-34-column-query-ci-gate` (already checked out). Conventional-commit prefixes (`ci:`, `docs:`).

---

## File Structure

- `.github/workflows/swift-ci.yml` — add one `Run column query benchmark gate` step to the `host-tests-and-benchmark-gate` job (Task 1).
- `AGENTS.md` — three edits (Task 2): (a) the architecture paragraph currently ends "`--column-query` is its **local** (not-yet-CI) gate" and must now read as a blocking CI gate; (b) the CI-section host-job step sequence gains the column-query gate; (c) the CI-section "fail the job on perf regression" sentence names column-query. The local command list (line ~105) and the benchmark-flags list (lines ~117/122) already name `--column-query`; those stay unchanged.
- `docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md` — local evidence + Pending hosted section (Task 3), filled with hosted run IDs post-merge (Task 4).

---

### Task 1: Add the blocking column-query gate step to the workflow

**Files:**
- Modify: `.github/workflows/swift-ci.yml` (insert between the `Run line geometry query benchmark gate` step and the `Run memory shape diagnostic` step)
- Test: inline Ruby workflow-invariant assertion (saved to scratchpad, not a committed file)

**Interfaces:**
- Consumes: the existing `ViewportBenchmarks` executable and its `--column-query --gate` mode (shipped in Slice 33).
- Produces: a `host-tests-and-benchmark-gate` job step named exactly `Run column query benchmark gate` that runs `--column-query --gate`, is not `continue-on-error`, shares its siblings' `docs_only_pr` guard, and is ordered line-geometry-query → column-query → memory-shape. Tasks 2, 3, and 4 reference this exact step name.

- [ ] **Step 1: Write the failing workflow-invariant assertion**

Save this assertion to the scratchpad so it can be rerun verbatim before and after the change. Create `/private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/5a5eab40-5f50-4e42-9b30-bbdfd33c3a39/scratchpad/assert_column_query_gate.rb`:

```ruby
require "yaml"

wf = YAML.load_file(".github/workflows/swift-ci.yml")
jobs = wf["jobs"]
steps = jobs["host-tests-and-benchmark-gate"]["steps"]
names = steps.map { |s| s["name"] }

cq  = steps.find { |s| s["name"] == "Run column query benchmark gate" }
lgq = steps.find { |s| s["name"] == "Run line geometry query benchmark gate" }
raise "missing column-query gate step" unless cq
raise "missing line-geometry-query gate step" unless lgq
raise "gate not invoking --column-query --gate" unless cq["run"].include?("--column-query --gate")
raise "column-query gate must not be continue-on-error" if cq["continue-on-error"]
raise "column-query gate must share its siblings docs-only guard" unless cq["if"] == lgq["if"]

i_lgq = names.index("Run line geometry query benchmark gate")
i_cq  = names.index("Run column query benchmark gate")
i_mem = names.index("Run memory shape diagnostic")
raise "bad gate ordering" unless i_lgq && i_cq && i_mem && i_lgq < i_cq && i_cq < i_mem

required = ["Host tests and benchmark gate", "iOS cross-target compile", "WASM cross-target observation"]
actual = jobs.values.map { |j| j["name"] }
raise "required job context name(s) changed" unless required.all? { |n| actual.include?(n) }

puts "workflow_assertions_ok"
```

- [ ] **Step 2: Run the assertion to verify it fails**

Run: `ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/5a5eab40-5f50-4e42-9b30-bbdfd33c3a39/scratchpad/assert_column_query_gate.rb`

Expected: non-zero exit, stderr contains `missing column-query gate step` (the step does not exist yet).

- [ ] **Step 3: Add the column-query gate step to the workflow**

In `.github/workflows/swift-ci.yml`, replace this block:

```yaml
      - name: Run line geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-geometry-query --gate

      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

with:

```yaml
      - name: Run line geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-geometry-query --gate

      - name: Run column query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-query --gate

      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

- [ ] **Step 4: Run the assertion to verify it passes**

Run: `ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/5a5eab40-5f50-4e42-9b30-bbdfd33c3a39/scratchpad/assert_column_query_gate.rb`

Expected: exit 0, stdout `workflow_assertions_ok`.

- [ ] **Step 5: Confirm the exact command the workflow invokes passes locally**

Run: `swift run -c release ViewportBenchmarks -- --column-query --gate`

Expected: exit 0; five `mode=column_query` rows, every row `gate=pass`, `failures=0`, each row printing `budget_p95_ns` and `budget_p99_ns`. Scenarios: `uniform_1k`, `uniform_100k`, `uniform_1m`, `prefixsum_100k`, `prefixsum_1m`. The five deterministic checksums must match the Slice 33 record byte-for-byte: `641440000`, `63985556480`, `639841600000`, `63985600000`, `639841560320` (a drift means the benchmark workload changed, which this slice forbids).

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: promote column-query benchmark to a blocking hosted gate"
```

---

### Task 2: Document the column-query gate as blocking in AGENTS.md

**Files:**
- Modify: `AGENTS.md` (architecture paragraph at lines ~76-77; CI section `Host tests and benchmark gate` bullet at lines ~133-146)
- Test: inline `grep` assertions

**Interfaces:**
- Consumes: the step name and ordering produced by Task 1.
- Produces: documentation only; no downstream task depends on it.

- [ ] **Step 1: Write the failing documentation assertions**

Run all three checks against the current `AGENTS.md`. Check A verifies the architecture paragraph no longer calls `--column-query` a not-yet-CI gate. Check B counts occurrences of the exact `--column-query --gate` token (1 today, in the local command list; the new CI bullet makes it 2). Check C flattens newlines and squeezes spaces before matching the fail-the-job sentence (the CI bullet wraps `` `--column-query` `` and `(blocking)` across line breaks, so a single-line phrase grep would not match).

```bash
# Check A — architecture paragraph no longer marks column-query "not-yet-CI"
grep -q -- 'not-yet-CI' AGENTS.md && echo "arch STILL-LOCAL" || echo "arch OK"
# Check B — column-query gate present in the CI host-job sequence (>= 2 occurrences)
test "$(grep -c -- '--column-query --gate' AGENTS.md)" -ge 2 && echo "step-seq OK" || echo "step-seq MISSING"
# Check C — column-query named in the "fail the job on perf regression" sentence
tr '\n' ' ' < AGENTS.md | tr -s ' ' | grep -q -- 'line-geometry-query, and column-query gates \*\*fail the job on perf regression\*\*' && echo "fail-sentence OK" || echo "fail-sentence MISSING"
```

Expected: Check A prints `arch STILL-LOCAL`; Checks B and C print `MISSING`.

- [ ] **Step 2: Update the architecture paragraph**

In `AGENTS.md`, replace:

```text
`PrefixSumColumnMetrics` (reference providers); `--column-query` is its **local**
(not-yet-CI) gate.
```

with:

```text
`PrefixSumColumnMetrics` (reference providers); `--column-query` is its blocking
host-job CI gate.
```

- [ ] **Step 3: Add the column-query gate to the CI host-job step sequence**

In `AGENTS.md`, replace:

```text
  (blocking) → `--line-geometry-query --gate` (blocking) → `--memory-shape`
  → `--memory-observation` → realistic relative
```

with:

```text
  (blocking) → `--line-geometry-query --gate` (blocking)
  → `--column-query --gate` (blocking) → `--memory-shape`
  → `--memory-observation` → realistic relative
```

- [ ] **Step 4: Extend the "fail the job on perf regression" sentence**

In `AGENTS.md`, replace:

```text
  variable-height, structural-mutation, bulk-structural-mutation, line-query, and
  line-geometry-query gates **fail the job on perf regression**. Benchmark budgets
```

with:

```text
  variable-height, structural-mutation, bulk-structural-mutation, line-query,
  line-geometry-query, and column-query gates **fail the job on perf regression**.
  Benchmark budgets
```

- [ ] **Step 5: Run the assertions to verify they pass**

```bash
grep -q -- 'not-yet-CI' AGENTS.md && echo "arch STILL-LOCAL" || echo "arch OK"
test "$(grep -c -- '--column-query --gate' AGENTS.md)" -ge 2 && echo "step-seq OK" || echo "step-seq MISSING"
tr '\n' ' ' < AGENTS.md | tr -s ' ' | grep -q -- 'line-geometry-query, and column-query gates \*\*fail the job on perf regression\*\*' && echo "fail-sentence OK" || echo "fail-sentence MISSING"
```

Expected: all three print `OK`.

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document column-query gate as blocking in AGENTS.md"
```

---

### Task 3: Record local verification evidence

**Files:**
- Create: `docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md`
- Test: the recorded command outputs are themselves the evidence

**Interfaces:**
- Consumes: the Task 1 + Task 2 changes on the branch.
- Produces: a verification doc with a fully populated local-evidence section (including a per-scenario headroom table and the checksum-equality integrity check) and a clearly-marked `Pending` hosted section that Task 4 fills post-merge.

- [ ] **Step 1: Run the full local verification suite and capture outputs**

Run each command, recording exact stdout and exit status:

```bash
swift run -c release ViewportBenchmarks -- --column-query --gate
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
ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/5a5eab40-5f50-4e42-9b30-bbdfd33c3a39/scratchpad/assert_column_query_gate.rb
git diff --name-only main...HEAD
```

Expected: all gates `gate=pass`; the five `column_query` checksums match the Slice 33 record byte-for-byte (`641440000`, `63985556480`, `639841600000`, `63985600000`, `639841560320`); `swift test` reports `189 tests, 0 failures` plus the `0 tests in 0 suites` Swift Testing line; `git diff --check` empty; Foundation scan `core exit: 1` (no matches); assertion prints `workflow_assertions_ok`; `git diff --name-only` lists only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`.

- [ ] **Step 2: Build the per-scenario headroom table**

From the `--column-query --gate` output captured in Step 1, record each scenario's observed `p95_ns` / `p99_ns` and compute headroom = budget ÷ observed (using the budgets `uniform_1k` 30,000/60,000; `uniform_100k` 60,000/120,000; `uniform_1m` 120,000/240,000; `prefixsum_100k` 60,000/120,000; `prefixsum_1m` 120,000/240,000). This grounds the spec's "`prefixsum_1m` is the one to watch" and "least multiplicative headroom" in this slice's own numbers and gives any future Linux re-baseline (Option E) a recorded per-scenario baseline. (Observed timings are approximate/non-reproducible — the deterministic anchor remains the checksum set.)

- [ ] **Step 3: Write the verification document**

Create `docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md` with these sections, pasting the real captured output under each:

```markdown
# Column-Query CI Gate Promotion Verification

Date: 2026-07-05
Branch: `slice-34-column-query-ci-gate`
Local verification HEAD: `<git rev-parse --short HEAD>`

## Change Scope

`git diff --name-only main...HEAD` — only `.github/workflows/swift-ci.yml`,
`AGENTS.md`, and `docs/**`. No benchmark or core Swift source changed.

<paste git diff --name-only output>

## Workflow-Invariant Assertion

The new step exists, invokes `--column-query --gate`, is not `continue-on-error`,
shares its siblings' docs-only guard, is ordered line-geometry-query →
column-query → memory-shape, and the three required job context names are
unchanged.

<paste assertion command + `workflow_assertions_ok`>

## Column-Query Gate (local)

<paste `--column-query --gate` output: five gate=pass rows with budget fields>

### Benchmark-Unchanged Integrity Check

The five per-scenario `column_query` checksums are byte-identical to the Slice 33
values, proving the benchmark workload is unchanged:

| Scenario | Checksum | Slice 33 value | Match |
| --- | --- | --- | --- |
| uniform_1k     | <observed> | 641440000     | ✅ |
| uniform_100k   | <observed> | 63985556480   | ✅ |
| uniform_1m     | <observed> | 639841600000  | ✅ |
| prefixsum_100k | <observed> | 63985600000   | ✅ |
| prefixsum_1m   | <observed> | 639841560320  | ✅ |

### Per-Scenario Headroom (local, macOS arm64)

| Scenario | Observed p95 ns | Budget p95 ns | Headroom (budget ÷ obs) | Budget p99 ns |
| --- | ---: | ---: | ---: | ---: |
| uniform_1k     | <obs> | 30,000  | <×> | 60,000  |
| uniform_100k   | <obs> | 60,000  | <×> | 120,000 |
| uniform_1m     | <obs> | 120,000 | <×> | 240,000 |
| prefixsum_100k | <obs> | 60,000  | <×> | 120,000 |
| prefixsum_1m   | <obs> | 120,000 | <×> | 240,000 |

(Observed timings are approximate and non-reproducible; the deterministic anchor
is the checksum set above.)

## Pre-existing Gates Still Pass

<paste --line-geometry-query, --line-query, --gate, --variable-height,
--variable-height-mutation, --structural-mutation, --bulk-structural-mutation
gate outputs>

## Host Tests

<paste `swift test` summary: 189 tests, 0 failures + the 0-in-0-suites line>

## Foundation-Free Scan

<paste rg command + `core exit: 1`>

## Hosted Proof

Pending — recorded in the post-merge follow-up (Task 4) against the final stable
PR-head SHA and the merge commit, to avoid a stale-on-write hosted record.
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md
git commit -m "docs: record local verification for column-query gate promotion"
```

---

### Task 4: Record post-merge hosted proof

> **Runs after the PR is opened, green, and merged to `main`.** This is the established repo pattern (see Slices 28/32): the PR-head proof is recorded only once the final head SHA is stable, and never describes a source-bearing PR as docs-only (the detector reads the full diff, which here includes the YAML change, and rejects `.github/workflows/**` outright). Verify hosted runs at the **step** level, not just the job conclusion (a green job can hide a dead `continue-on-error` step).

**Files:**
- Modify: `docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md` (replace the `Pending` hosted section)

**Interfaces:**
- Consumes: the merged PR and its hosted Swift CI runs.
- Produces: the merged-code evidence anchor for the slice.

- [ ] **Step 1: Open the PR and confirm hosted CI is green**

```bash
gh pr create --base main --head slice-34-column-query-ci-gate \
  --title "Slice 34: promote column-query benchmark to a blocking hosted gate" \
  --body "<summary referencing the spec and the closed Slice 33 gap>"
gh pr checks --watch
```

Expected: all three required contexts succeed: `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`. The host job's `Run column query benchmark gate` step runs (not skipped, not `continue-on-error`) and prints five Linux `column_query` rows with `gate=pass`. If the column-query step fails on budget, STOP and apply spec Decision 3 (retune budgets in `ColumnQueryBenchmark.swift`, watching `prefixsum_1m`), do not widen via the workflow.

- [ ] **Step 2: Merge and capture the post-merge push run**

After merge, capture the final PR-head run ID and the post-merge `push` run ID on `main`:

```bash
gh run list --branch main --workflow "Swift CI" --limit 5
gh run view <run-id> --json databaseId,event,conclusion,headSha,jobs
```

Expected: the merge-commit `push` run concludes `success` with all three required jobs `success`, and the host job's `Run column query benchmark gate` step `success`.

- [ ] **Step 3: Fill the hosted section and record the Linux column-query rows**

Replace the `Pending` hosted section with: final PR-head run ID + the five hosted Linux `column_query` rows (the budget-fit evidence) **plus a per-scenario hosted headroom line** (observed `p95_ns`/`p99_ns` and headroom = budget ÷ observed) so the `prefixsum_1m` watch-scenario has a concrete hosted number; proof (at step level) the step is not `continue-on-error` and ran (not skipped); and the post-merge push run ID for the merge commit.

- [ ] **Step 4: Commit (and push the post-merge proof)**

```bash
git add docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md
git commit -m "docs: record slice 34 post-merge proof"
```

---

## Acceptance Criteria (from spec)

- `.github/workflows/swift-ci.yml` has a `Run column query benchmark gate` step invoking `--column-query --gate`, with no `continue-on-error: true`, positioned line-geometry-query → column-query → memory-shape.
- The three required job context names are unchanged.
- The PR `git diff --name-only` touches only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**` (no benchmark Swift edit).
- `AGENTS.md` describes the column-query benchmark as a blocking host-job gate that fails the job on perf regression, and no longer calls `--column-query` a local (not-yet-CI) gate.
- Local column-query gate passes `gate=pass` for all five scenarios; the seven pre-existing latency gates and `swift test` still pass.
- Local verification records that the five `column_query` checksums are byte-identical to the Slice 33 values (benchmark-unchanged integrity check) and a per-scenario local headroom table.
- Hosted PR-head CI runs the column-query gate step and succeeds, with the five Linux p95/p99 rows and a per-scenario hosted headroom line recorded as budget-fit evidence.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Post-Plan Next Step

After Task 4, a separate **post-slice review** (`docs/superpowers/reviews/2026-07-05-slice-34-post-slice-review.md` on a `slice-34-post-slice-review` branch) closes the slice and recommends Slice 35. Per the Slice 33 review, the horizontal axis is then a CI-protected mapping primitive, and the open capability directions are Option C (`columnGeometryAt` / caret-x, the 27→31 mirror), Option B (`pointAt(x:y:)` 2D composite, the hit-testing leap), and Option D (closed-form / native column inverse). That is a product call for the user. The review is its own lifecycle step, not a task in this plan.
