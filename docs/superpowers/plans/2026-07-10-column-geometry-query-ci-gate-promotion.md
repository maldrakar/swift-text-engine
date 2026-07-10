# Column-Geometry-Query CI Gate Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the local-only `--column-geometry-query --gate` benchmark to a blocking hosted CI step — the 9th blocking latency gate — retiring the CI-promotion debt Slice 35 re-opened.

**Architecture:** Pure CI + docs slice. Add one blocking `run:` step to the `host-tests-and-benchmark-gate` job in `.github/workflows/swift-ci.yml`, placed between the existing column-query gate and the memory-shape diagnostic. Update `AGENTS.md` to reflect the new gate, and record local + hosted evidence. No Swift, Core, provider, or benchmark-source change of any kind — the benchmark executable and its budgets already exist from Slice 35 and are promoted unchanged.

**Tech Stack:** GitHub Actions workflow YAML; SwiftPM `ViewportBenchmarks` executable (already built); Ruby 3.2 for the workflow-invariant assertion; ripgrep for doc assertions.

## Global Constraints

Copied verbatim from the spec — every task's requirements implicitly include these:

- **No `TextEngineCore` changes.** No `TextEngineReferenceProviders` changes.
- **No benchmark Swift source changes** (no scenario, budget, or helper edit). `git diff --name-only` for the whole PR must touch only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`.
- **No `columnGeometryAt` / `columnAt` / `LineHorizontalMetricsSource` API changes.**
- The new gate step must be **blocking**: no `continue-on-error: true`.
- The step is positioned **after** `Run column query benchmark gate` and **before** `Run memory shape diagnostic`, keeping all nine blocking latency gates contiguous.
- Budgets stay in `Sources/ViewportBenchmarks`, not duplicated in workflow YAML.
- The three required job context names remain unchanged: `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`.
- Trusted docs-only PR behavior unchanged; the new step carries the same `if: steps.change-scope.outputs.docs_only_pr != 'true'` guard as its sibling gates.
- **No bundled hardening** (Slice 35 review found no P0/P1/P2/actionable-P3 in the promoted benchmark); promote it unchanged.
- The five `column_geometry_query` per-scenario checksums must stay byte-identical to the Slice 35 values: `160641440000`, `267505512960`, `799841600000`, `223985600000`, `839521520640`. A drift means the workload changed (forbidden).
- **Foundation-free:** `rg -n "Foundation" Sources/TextEngineCore` must stay empty (unaffected — no Swift touched, but verified as a standing invariant).
- **Decision 3 (stop-and-retune):** if the first hosted PR-head run fails on budget, STOP, update the spec with the hosted numbers, re-derive Linux budgets in `ColumnGeometryQueryBenchmark.swift`. Do NOT hide a failure with `continue-on-error`, a workflow-only threshold, or a silent budget widening.

---

### Task 1: Add the blocking column-geometry-query gate to the workflow

**Files:**
- Modify: `.github/workflows/swift-ci.yml` (insert one step in the `host-tests-and-benchmark-gate` job, after the `Run column query benchmark gate` step at ~line 118–120, before `Run memory shape diagnostic` at ~line 122)
- Test (not committed): a Ruby workflow-invariant assertion run from the repo root

**Interfaces:**
- Consumes: the existing `--column-geometry-query --gate` executable path shipped in Slice 35 (`Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift`), invoked exactly as the sibling gates are.
- Produces: a workflow whose `host-tests-and-benchmark-gate` job contains a `Run column geometry query benchmark gate` step, blocking, ordered column-query → column-geometry-query → memory-shape. Later tasks/verification reference this exact step name.

- [ ] **Step 1: Write the failing workflow-invariant assertion**

Save this as a scratch file (do NOT commit it) at `/private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/8584f5da-aff8-474c-8368-f2126684568a/scratchpad/wf_assert.rb`:

```ruby
require "yaml"
wf = YAML.load_file(".github/workflows/swift-ci.yml")
jobs = wf["jobs"]
steps = jobs["host-tests-and-benchmark-gate"]["steps"]
names = steps.map { |s| s["name"] }
cgq = steps.find { |s| s["name"] == "Run column geometry query benchmark gate" }
cq  = steps.find { |s| s["name"] == "Run column query benchmark gate" }
raise "missing column-geometry-query gate step" unless cgq
raise "missing column-query gate step" unless cq
raise "gate not invoking --column-geometry-query --gate" unless cgq["run"].include?("--column-geometry-query --gate")
raise "column-geometry-query gate must not be continue-on-error" if cgq["continue-on-error"]
raise "column-geometry-query gate must share its siblings docs-only guard" unless cgq["if"] == cq["if"]
i_cq  = names.index("Run column query benchmark gate")
i_cgq = names.index("Run column geometry query benchmark gate")
i_mem = names.index("Run memory shape diagnostic")
raise "bad gate ordering" unless i_cq && i_cgq && i_mem && i_cq < i_cgq && i_cgq < i_mem
required = ["Host tests and benchmark gate", "iOS cross-target compile", "WASM cross-target observation"]
actual = jobs.values.map { |j| j["name"] }
raise "required job context name(s) changed" unless required.all? { |n| actual.include?(n) }
puts "workflow_assertions_ok"
```

- [ ] **Step 2: Run the assertion to verify it fails (gate not yet present)**

Run: `cd /Users/aabanschikov/swift-text-engine && ruby "$SCRATCH/wf_assert.rb"` (substitute the scratchpad path above for `$SCRATCH`).
Expected: exits non-zero with `missing column-geometry-query gate step (RuntimeError)`.

- [ ] **Step 3: Insert the gate step in the workflow**

In `.github/workflows/swift-ci.yml`, find the existing column-query gate step:

```yaml
      - name: Run column query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-query --gate

      - name: Run memory shape diagnostic
```

Insert the new step between them, so the region becomes:

```yaml
      - name: Run column query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-query --gate

      - name: Run column geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-geometry-query --gate

      - name: Run memory shape diagnostic
```

Match the surrounding indentation exactly (6-space step indent, matching the sibling gates). Do not move or alter any other step.

- [ ] **Step 4: Run the assertion to verify it passes**

Run: `cd /Users/aabanschikov/swift-text-engine && ruby "$SCRATCH/wf_assert.rb"`
Expected: prints `workflow_assertions_ok`, exit 0.

- [ ] **Step 5: Confirm the local gate passes and the benchmark workload is unchanged**

Run the promoted gate locally and confirm all five scenarios pass with the exact Slice 35 checksums:

```bash
cd /Users/aabanschikov/swift-text-engine
swift run -c release ViewportBenchmarks -- --column-geometry-query --gate
```

Expected: five `mode=column_geometry_query … gate=pass` lines, `failures=0`, and the five checksums **byte-identical** to `160641440000` (uniform_1k), `267505512960` (uniform_100k), `799841600000` (uniform_1m), `223985600000` (prefixsum_100k), `839521520640` (prefixsum_1m). Any checksum drift means the benchmark workload changed — STOP, because this slice forbids benchmark-source edits.

Confirm no Swift/benchmark source moved:

```bash
git diff --name-only
```

Expected: only `.github/workflows/swift-ci.yml`.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add .github/workflows/swift-ci.yml
git commit -m "$(cat <<'EOF'
ci: add blocking column-geometry-query benchmark gate

Promote --column-geometry-query --gate to the 9th blocking hosted latency
gate, after the column-query gate and before the memory-shape diagnostic.
Blocking (no continue-on-error); shares the docs-only guard. Benchmark
source and budgets unchanged (Slice 35 checksums byte-identical).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Update AGENTS.md for the promoted gate

**Files:**
- Modify: `AGENTS.md` (architecture paragraph, ~line 83–84; CI section, ~line 149 and ~line 154)
- Test (not committed): ripgrep assertions over `AGENTS.md`

**Interfaces:**
- Consumes: the step added in Task 1 (the doc now describes a gate that exists in the workflow).
- Produces: `AGENTS.md` where `--column-geometry-query` is described as a blocking host-job gate (not "local (not-yet-CI)"), listed in the blocking-gate sequence and the "fail the job on perf regression" sentence.

- [ ] **Step 1: Assert the current ("before") doc state**

Run:

```bash
cd /Users/aabanschikov/swift-text-engine
rg -n "column-geometry-query --gate\` is \*\*local \(not-yet-CI\)\*\*" AGENTS.md
```

Expected: one match (the architecture sentence still calls the gate local). This is the state Task 2 changes.

- [ ] **Step 2: Edit the architecture paragraph**

Replace the sentence ending the `columnGeometryAt` architecture description. Old text:

```text
class equals `columnAt`'s; caret snapping stays a caller concern. Its
`--column-geometry-query --gate` is **local (not-yet-CI)**.
```

New text:

```text
class equals `columnAt`'s; caret snapping stays a caller concern.
`--column-geometry-query` is its blocking host-job CI gate.
```

(This mirrors how the adjacent `columnAt` sentence reads: "`--column-query` is its blocking host-job CI gate.")

- [ ] **Step 3: Edit the CI section — blocking-gate sequence**

In the `Host tests and benchmark gate` bullet, old text:

```text
  → `--column-query --gate` (blocking) → `--memory-shape`
```

New text:

```text
  → `--column-query --gate` (blocking)
  → `--column-geometry-query --gate` (blocking) → `--memory-shape`
```

- [ ] **Step 4: Edit the CI section — "fail the job on perf regression" sentence**

Old text:

```text
  variable-height, structural-mutation, bulk-structural-mutation, line-query,
  line-geometry-query, and column-query gates **fail the job on perf regression**.
```

New text:

```text
  variable-height, structural-mutation, bulk-structural-mutation, line-query,
  line-geometry-query, column-query, and column-geometry-query gates **fail the
  job on perf regression**.
```

- [ ] **Step 5: Assert the new ("after") doc state**

Run:

```bash
cd /Users/aabanschikov/swift-text-engine
# The "local (not-yet-CI)" claim for column-geometry-query is gone:
rg -n "column-geometry-query --gate\` is \*\*local" AGENTS.md && echo "STILL LOCAL — FAIL" || echo "local-claim removed OK"
# The blocking sequence now lists the new gate:
rg -n "column-geometry-query --gate\` \(blocking\)" AGENTS.md
# The fail-the-job sentence now names it:
rg -n "column-query, and column-geometry-query gates" AGENTS.md
```

Expected: `local-claim removed OK`; one match for the blocking-sequence line; one match for the fail-the-job sentence.

- [ ] **Step 6: Confirm scope and commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git diff --name-only   # expect only AGENTS.md
git add AGENTS.md
git commit -m "$(cat <<'EOF'
docs: list column-geometry-query as the 9th blocking CI gate

Drop the "local (not-yet-CI)" note in the architecture paragraph and add
--column-geometry-query --gate to the blocking-gate sequence and the
"fail the job on perf regression" sentence in the CI section.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Record local verification (hosted proof left Pending)

**Files:**
- Create: `docs/superpowers/verification/2026-07-10-column-geometry-query-ci-gate-promotion.md`

**Interfaces:**
- Consumes: the workflow step (Task 1) and doc changes (Task 2).
- Produces: a verification record with a local-evidence section, a workflow-assertion section, and an explicit `## Hosted Proof — Pending` placeholder to be filled by the post-merge follow-up PR (clean-evidence convention: never record PR-head run IDs against a still-moving head).

- [ ] **Step 1: Run the full local evidence suite and capture output**

```bash
cd /Users/aabanschikov/swift-text-engine
swift run -c release ViewportBenchmarks -- --column-geometry-query --gate
swift run -c release ViewportBenchmarks -- --column-query --gate
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
swift run -c release ViewportBenchmarks -- --line-query --gate
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift test 2>&1 | tail -5
git diff --check
rg -n "Foundation" Sources/TextEngineCore ; echo "rg-exit=$?"
ruby "$SCRATCH/wf_assert.rb"
```

Expected: every gate `gate=pass` with `failures=0`; the five `column_geometry_query` checksums byte-identical to the Slice 35 values; `swift test` all pass (213 tests + the empty Swift Testing harness line); `git diff --check` clean; `rg … Foundation` no matches (`rg-exit=1`); `workflow_assertions_ok`.

- [ ] **Step 2: Write the verification record**

Create `docs/superpowers/verification/2026-07-10-column-geometry-query-ci-gate-promotion.md` capturing, with exact commands and representative output lines:

- **Local gate evidence** — the five `column_geometry_query` rows (with `gate=pass`, `budget_p95_ns`, `budget_p99_ns`) and a per-scenario headroom table (observed p95, budget p95, headroom = budget ÷ observed) for all five scenarios; state that the five checksums are byte-identical to the Slice 35 values (the free "benchmark unchanged" integrity check).
- **All eight pre-existing gates + `swift test`** passing (checksums unmoved), `git diff --check` clean, `Foundation` scan empty.
- **Workflow-invariant assertion** output (`workflow_assertions_ok`) and what it proves (step exists, invokes `--column-geometry-query --gate`, not `continue-on-error`, shares the docs-only guard, ordered column-query → column-geometry-query → memory-shape, required contexts unchanged).
- **Scope proof** — `git diff --name-only 95b735e..HEAD` touches only `.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`.
- A final section literally titled `## Hosted Proof — Pending` stating the PR-head and post-merge push run IDs will be recorded in the post-merge follow-up PR once the final head SHA is stable (per Decision 3 / the clean-evidence convention). Name the two watch scenarios (`prefixsum_100k` least multiplicative headroom, `prefixsum_1m` largest absolute latency) as the ones to confirm on hosted Linux.

- [ ] **Step 3: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add docs/superpowers/verification/2026-07-10-column-geometry-query-ci-gate-promotion.md
git commit -m "$(cat <<'EOF'
docs: record column-geometry-query CI gate local verification

Local evidence for the 9th blocking gate: --column-geometry-query --gate
passes all five scenarios with Slice 35 checksums byte-identical, all eight
pre-existing gates + swift test green, workflow-invariant assertion ok.
Hosted proof left as an explicit Pending placeholder for the post-merge
follow-up.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Open the PR, confirm hosted green, record hosted proof post-merge

This task is the hosted-evidence half; it is not a code change but the verification handoff. Follow the project's finishing-a-development-branch flow.

- [ ] **Step 1: Commit the plan and push the branch**

```bash
cd /Users/aabanschikov/swift-text-engine
git add docs/superpowers/plans/2026-07-10-column-geometry-query-ci-gate-promotion.md
git commit -m "docs: add slice 36 column-geometry-query CI gate promotion plan

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push -u origin slice-36-column-geometry-query-ci-gate-promotion
```

- [ ] **Step 2: Open the PR**

Open a PR titled *"Slice 36: promote column-geometry-query to a blocking CI gate"* against `main`, body summarizing: 9th blocking latency gate, one-shot, pure CI + docs, benchmark source unchanged (Slice 35 checksums byte-identical). Because this PR touches `.github/workflows/**`, it is never docs-only and runs the full heavy host path.

- [ ] **Step 3: Confirm the hosted PR-head run at STEP level**

Wait for the Swift CI run on the PR head. Verify (via `gh run view --log` / step conclusions, not just the job conclusion — a green job can hide a dead `continue-on-error` step):

- all three required jobs `success`;
- host job step `Run column geometry query benchmark gate` = `success`, with its hosted Linux x86_64 `column_geometry_query` rows for all five scenarios showing `gate=pass`, `budget_p95_ns`, `budget_p99_ns`;
- record per-scenario hosted p95/p99 + headroom (budget ÷ observed), especially for `prefixsum_100k` (least multiplicative headroom) and `prefixsum_1m` (largest absolute latency);
- the step is not `continue-on-error`.

**If the hosted gate step fails on budget:** STOP and apply Decision 3 (revisit the spec with hosted numbers; re-derive Linux budgets in `ColumnGeometryQueryBenchmark.swift`). Do not widen silently or add `continue-on-error`.

- [ ] **Step 4: Merge, then record hosted proof in a post-merge follow-up**

After merge, capture the **post-merge push run** on the merge commit (event `push`, branch `main`) at step level — all three required jobs `success`, the new gate step `success`, the realistic-observation step correctly `skipped` on push. Then open a small docs-only follow-up PR that fills the verification doc's `## Hosted Proof — Pending` section with the real PR-head run ID and the post-merge push run ID (this follow-up is genuinely docs-only — it touches only the verification Markdown — so it legitimately takes the trusted docs-only path). This split keeps the evidence convention: PR-head/merge run IDs are recorded only once the head SHA is stable.

---

## Self-Review

**1. Spec coverage.** Every spec section maps to a task:
- Workflow gate step (spec §Implementation Architecture → Workflow, Decisions 1/2/4/7) → Task 1.
- AGENTS.md two-place update (spec §Documentation) → Task 2.
- Verification record with local evidence + checksum-identity + workflow assertion + Pending hosted (spec §Verification Record, Decision 3, Acceptance Criteria) → Task 3.
- Hosted PR-head + post-merge proof, Decision 3 stop-and-retune, evidence convention → Task 4.
- Non-Goals / No-bundled-hardening / Global Constraints → enforced by the `git diff --name-only` scope checks in Tasks 1–3 and the Global Constraints block.
- Required-context-unchanged (Decision 5) and docs-only-unchanged (Decision 6) → asserted by the Ruby workflow check (Task 1) and the shared `if:` guard.

**2. Placeholder scan.** No "TBD"/"handle edge cases"/"similar to Task N". The one intentional literal placeholder is the verification doc's `## Hosted Proof — Pending` section — that is a required convention (clean evidence), not a plan gap; Task 4 fills it. `$SCRATCH` is a named substitution with its absolute value given in Task 1 Step 1.

**3. Type/name consistency.** The step name `Run column geometry query benchmark gate` is identical across Task 1 (YAML), the Task 1 Ruby assertion, and Task 3/4 verification. The flag `--column-geometry-query --gate` is identical everywhere. The five checksums are identical across the Global Constraints, Task 1 Step 5, and Task 3 Step 1. Ordering claim (column-query → column-geometry-query → memory-shape) is consistent between the YAML edit and the Ruby assertion.
