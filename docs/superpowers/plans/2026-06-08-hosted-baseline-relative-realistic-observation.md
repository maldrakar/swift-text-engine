# Hosted Baseline-Relative Realistic Observation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a PR-only, nonblocking hosted base-vs-head realistic-provider observation that avoids absolute hosted budget failures and records enough no-op evidence to choose an initial threshold.

**Architecture:** The final workflow keeps the existing stable gates unchanged and adds a `continue-on-error: true` pull-request observation step. A head-owned shell helper creates no dependency on new code in the base SHA: the workflow checks out base and head into separate git worktrees, then the helper runs the existing ungated realistic-provider benchmark in each tree, using median-of-4 full runs per side and a predeclared interleaved order. Hosted calibration samples choose the initial threshold by `candidate_threshold = max_noop_ratio * 1.05`, capped at `1.50`.

**Tech Stack:** Swift Package Manager, Swift 6.2.1, GitHub Actions, Bash 3-compatible shell, `gh`, `rg`, `awk`, git worktrees.

---

## Source Design

Implement the approved Slice 12 design:

```text
docs/superpowers/specs/2026-06-08-hosted-baseline-relative-realistic-observation-design.md
```

Preserve these constraints:

- Do not change `TextEngineCore`.
- Do not change fixed-height viewport behavior.
- Do not change synthetic benchmark budgets.
- Do not change local realistic-provider absolute budgets.
- Do not use `--realistic-provider --gate` for hosted relative measurement.
- Do not make the relative observation blocking in Slice 12.
- Do not add automatic promotion from observational to blocking.
- Do not add branch protection, rulesets, cross-target CI, storage adapters, variable-height layout, or memory hard budgets.

## Scope Check

This plan covers one subsystem: hosted realistic-provider relative observation in GitHub Actions. It does not plan variable-height layout, repository policy, cross-target CI, or memory-budget enforcement.

## File Structure

Modify:

```text
.github/workflows/swift-ci.yml
```

Create:

```text
.github/scripts/realistic-relative-observation.sh
docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md
```

Responsibility map:

```text
.github/scripts/realistic-relative-observation.sh
  Runs existing ungated realistic-provider benchmark commands in caller-provided
  base/head source directories, parses p95/p99, computes medians and ratios,
  and prints one stable key-value observation line.

.github/workflows/swift-ci.yml
  Keeps stable gates unchanged, fetches base/head SHAs for PRs, creates isolated
  worktrees, and invokes the observation helper with continue-on-error.

docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md
  Records local checks, five hosted no-op samples, threshold calculation,
  final workflow state, final hosted observation, runtime, and non-goal checks.
```

## Task 1: Preflight And Branch Setup

**Files:**
- Read: `docs/superpowers/specs/2026-06-08-hosted-baseline-relative-realistic-observation-design.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `Sources/ViewportBenchmarks/BenchmarkSupport.swift`
- Read: `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`
- Read: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`

- [ ] **Step 1: Confirm spec requirements that drive implementation**

Run:

```bash
rg -n "ungated realistic-provider|continue-on-error: true|skipped_base_unsupported|comparison_repetitions_per_side=4|base, head, head, base, base, head, head, base|candidate_threshold = max_noop_ratio \\* 1.05|no-op-equivalent" docs/superpowers/specs/2026-06-08-hosted-baseline-relative-realistic-observation-design.md
```

Expected: output includes every searched requirement.

- [ ] **Step 2: Confirm current workflow stable gates**

Run:

```bash
sed -n '1,90p' .github/workflows/swift-ci.yml
rg -n "Run host tests|Run synthetic benchmark gate|Run memory shape diagnostic|Run RSS memory observation diagnostic|Run realistic provider|continue-on-error" .github/workflows/swift-ci.yml
```

Expected:

```text
name: Swift CI
on:
  pull_request:
  push:
    branches:
      - main
```

Expected `rg` output includes the four stable steps and does not include a realistic-provider observation step or `continue-on-error`.

- [ ] **Step 3: Confirm ungated realistic-provider output has required fields without budget/gate fields**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Expected: PASS with one `mode=realistic_provider` line containing `p95_ns=`, `p99_ns=`, `failures=0`, and `checksum=`, and no `budget_p95_ns=`, `budget_p99_ns=`, or `gate=`.

- [ ] **Step 4: Confirm local gate remains available as smoke check**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Expected: PASS with one `mode=realistic_provider` line containing `budget_p95_ns=20000`, `budget_p99_ns=50000`, and `gate=pass`.

- [ ] **Step 5: Start the implementation branch**

Run:

```bash
git status --short
git switch -c slice-12-hosted-baseline-relative-realistic-observation
git branch --show-current
```

Expected:

- `git status --short` has no output before branch creation.
- Branch name is `slice-12-hosted-baseline-relative-realistic-observation`.

## Task 2: Add The Observation Helper

**Files:**
- Create: `.github/scripts/realistic-relative-observation.sh`

- [ ] **Step 1: Create the helper script**

Create `.github/scripts/realistic-relative-observation.sh` with this exact content:

```bash
#!/usr/bin/env bash
set -uo pipefail

RUN_ORDER=("base" "head" "head" "base" "base" "head" "head" "base")

usage() {
  cat <<'EOF'
Usage:
  realistic-relative-observation.sh --base-dir DIR --head-dir DIR --base-sha SHA --head-sha SHA --threshold FLOAT
  realistic-relative-observation.sh --self-test
EOF
}

fail() {
  echo "mode=realistic_relative_observation observation=infrastructure_failure reason=$1 blocking_ready=false"
  exit 2
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "self_test=fail label=$label expected=$expected actual=$actual"
    exit 1
  fi
}

extract_field() {
  local line="$1"
  local key="$2"
  printf '%s\n' "$line" | tr ' ' '\n' | awk -F= -v key="$key" '$1 == key { print $2; found = 1 } END { if (!found) exit 1 }'
}

is_positive_integer() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]
}

join_comma() {
  local output=""
  local value
  for value in "$@"; do
    if [[ -z "$output" ]]; then
      output="$value"
    else
      output="$output,$value"
    fi
  done
  printf '%s' "$output"
}

median_values() {
  local count="$#"
  if [[ "$count" -eq 0 ]]; then
    return 1
  fi

  local sorted
  sorted="$(printf '%s\n' "$@" | sort -n)"
  if [[ $((count % 2)) -eq 1 ]]; then
    local position=$(((count + 1) / 2))
    printf '%s\n' "$sorted" | sed -n "${position}p"
  else
    local left_position=$((count / 2))
    local right_position=$((left_position + 1))
    local left
    local right
    left="$(printf '%s\n' "$sorted" | sed -n "${left_position}p")"
    right="$(printf '%s\n' "$sorted" | sed -n "${right_position}p")"
    awk -v left="$left" -v right="$right" 'BEGIN { printf "%.6f", (left + right) / 2.0 }'
  fi
}

ratio_values() {
  local numerator="$1"
  local denominator="$2"
  awk -v numerator="$numerator" -v denominator="$denominator" 'BEGIN {
    if (denominator <= 0) exit 1
    printf "%.6f", numerator / denominator
  }'
}

max_values() {
  local left="$1"
  local right="$2"
  awk -v left="$left" -v right="$right" 'BEGIN {
    if (left >= right) printf "%.6f", left
    else printf "%.6f", right
  }'
}

classify_observation() {
  local max_ratio="$1"
  local threshold="$2"
  awk -v max_ratio="$max_ratio" -v threshold="$threshold" 'BEGIN {
    if (max_ratio <= threshold) print "clean"
    else print "above_threshold"
  }'
}

validate_output_line() {
  local line="$1"
  local p95
  local p99
  p95="$(extract_field "$line" "p95_ns")" || return 1
  p99="$(extract_field "$line" "p99_ns")" || return 1
  is_positive_integer "$p95" || return 1
  is_positive_integer "$p99" || return 1
}

run_self_test() {
  local line="mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=100 p99_ns=200 failures=0 checksum=42"
  assert_equal "100" "$(extract_field "$line" "p95_ns")" "extract_p95"
  assert_equal "200" "$(extract_field "$line" "p99_ns")" "extract_p99"
  validate_output_line "$line" || {
    echo "self_test=fail label=validate_output_line"
    exit 1
  }
  assert_equal "115.000000" "$(median_values 100 130 110 120)" "median_even"
  assert_equal "110" "$(median_values 100 130 110)" "median_odd"
  assert_equal "1.250000" "$(ratio_values 125 100)" "ratio"
  assert_equal "1.300000" "$(max_values 1.200000 1.300000)" "max_ratio"
  assert_equal "clean" "$(classify_observation 1.250000 1.500000)" "classify_clean"
  assert_equal "above_threshold" "$(classify_observation 1.510000 1.500000)" "classify_above"
  echo "self_test=pass"
}

print_skip_base_unsupported() {
  local reason="$1"
  echo "mode=realistic_relative_observation base_sha=$BASE_SHA head_sha=$HEAD_SHA comparison_repetitions_per_side=4 run_order=$(join_comma "${RUN_ORDER[@]}") observation_threshold=$THRESHOLD observation=skipped_base_unsupported reason=$reason blocking_ready=false"
}

run_benchmark_once() {
  local side="$1"
  local source_dir="$2"
  local run_number="$3"
  local output_dir="$4"
  local output_file="$output_dir/${side}_${run_number}.txt"
  local line_file="$output_dir/${side}_${run_number}.line"
  local status_file="$output_dir/${side}_${run_number}.status"

  (
    cd "$source_dir" &&
      swift run -c release ViewportBenchmarks -- --realistic-provider
  ) >"$output_file" 2>&1
  local status=$?
  printf '%s' "$status" >"$status_file"

  local line
  line="$(grep 'mode=realistic_provider' "$output_file" | tail -n 1 || true)"
  printf '%s\n' "$line" >"$line_file"

  if [[ "$side" == "base" ]]; then
    if [[ "$status" -ne 0 ]]; then
      if grep -q 'unknown argument --realistic-provider' "$output_file"; then
        print_skip_base_unsupported "base_command_unknown_argument"
        exit 0
      fi
      fail "base_command_failed"
    fi
    if [[ -z "$line" ]]; then
      print_skip_base_unsupported "base_missing_realistic_provider_line"
      exit 0
    fi
    if ! validate_output_line "$line"; then
      print_skip_base_unsupported "base_missing_required_fields"
      exit 0
    fi
  else
    if [[ "$status" -ne 0 ]]; then
      fail "head_command_failed"
    fi
    if [[ -z "$line" ]]; then
      fail "head_missing_realistic_provider_line"
    fi
    if ! validate_output_line "$line"; then
      fail "head_missing_required_fields"
    fi
  fi
}

BASE_DIR=""
HEAD_DIR=""
BASE_SHA=""
HEAD_SHA=""
THRESHOLD="${REALISTIC_RELATIVE_OBSERVATION_THRESHOLD:-}"

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-dir)
      BASE_DIR="$2"
      shift 2
      ;;
    --head-dir)
      HEAD_DIR="$2"
      shift 2
      ;;
    --base-sha)
      BASE_SHA="$2"
      shift 2
      ;;
    --head-sha)
      HEAD_SHA="$2"
      shift 2
      ;;
    --threshold)
      THRESHOLD="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$BASE_DIR" || -z "$HEAD_DIR" || -z "$BASE_SHA" || -z "$HEAD_SHA" || -z "$THRESHOLD" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$BASE_DIR" ]]; then
  fail "base_dir_missing"
fi
if [[ ! -d "$HEAD_DIR" ]]; then
  fail "head_dir_missing"
fi

OUTPUT_DIR="${REALISTIC_RELATIVE_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/realistic-relative.XXXXXX")}"
mkdir -p "$OUTPUT_DIR"

BASE_P95_VALUES=()
BASE_P99_VALUES=()
HEAD_P95_VALUES=()
HEAD_P99_VALUES=()
base_run=0
head_run=0

for side in "${RUN_ORDER[@]}"; do
  if [[ "$side" == "base" ]]; then
    base_run=$((base_run + 1))
    run_benchmark_once "base" "$BASE_DIR" "$base_run" "$OUTPUT_DIR"
    line="$(cat "$OUTPUT_DIR/base_${base_run}.line")"
    BASE_P95_VALUES+=("$(extract_field "$line" "p95_ns")")
    BASE_P99_VALUES+=("$(extract_field "$line" "p99_ns")")
  else
    head_run=$((head_run + 1))
    run_benchmark_once "head" "$HEAD_DIR" "$head_run" "$OUTPUT_DIR"
    line="$(cat "$OUTPUT_DIR/head_${head_run}.line")"
    HEAD_P95_VALUES+=("$(extract_field "$line" "p95_ns")")
    HEAD_P99_VALUES+=("$(extract_field "$line" "p99_ns")")
  fi
done

if [[ "$base_run" -ne 4 || "$head_run" -ne 4 ]]; then
  fail "unexpected_repetition_count"
fi

base_median_p95="$(median_values "${BASE_P95_VALUES[@]}")" || fail "base_p95_median_failed"
head_median_p95="$(median_values "${HEAD_P95_VALUES[@]}")" || fail "head_p95_median_failed"
base_median_p99="$(median_values "${BASE_P99_VALUES[@]}")" || fail "base_p99_median_failed"
head_median_p99="$(median_values "${HEAD_P99_VALUES[@]}")" || fail "head_p99_median_failed"
p95_ratio="$(ratio_values "$head_median_p95" "$base_median_p95")" || fail "p95_ratio_failed"
p99_ratio="$(ratio_values "$head_median_p99" "$base_median_p99")" || fail "p99_ratio_failed"
max_ratio="$(max_values "$p95_ratio" "$p99_ratio")" || fail "max_ratio_failed"
observation="$(classify_observation "$max_ratio" "$THRESHOLD")"

echo "mode=realistic_relative_observation base_sha=$BASE_SHA head_sha=$HEAD_SHA comparison_repetitions_per_side=4 run_order=$(join_comma "${RUN_ORDER[@]}") base_p95_ns_values=$(join_comma "${BASE_P95_VALUES[@]}") head_p95_ns_values=$(join_comma "${HEAD_P95_VALUES[@]}") base_p99_ns_values=$(join_comma "${BASE_P99_VALUES[@]}") head_p99_ns_values=$(join_comma "${HEAD_P99_VALUES[@]}") base_median_p95_ns=$base_median_p95 head_median_p95_ns=$head_median_p95 base_median_p99_ns=$base_median_p99 head_median_p99_ns=$head_median_p99 p95_ratio=$p95_ratio p99_ratio=$p99_ratio max_ratio=$max_ratio observation_threshold=$THRESHOLD observation=$observation blocking_ready=false"
```

- [ ] **Step 2: Make the helper executable**

Run:

```bash
chmod +x .github/scripts/realistic-relative-observation.sh
git diff -- .github/scripts/realistic-relative-observation.sh
```

Expected: the script is executable and the diff shows the exact content from Step 1.

- [ ] **Step 3: Run helper self-test**

Run:

```bash
.github/scripts/realistic-relative-observation.sh --self-test
```

Expected:

```text
self_test=pass
```

- [ ] **Step 4: Verify helper does not use the absolute gate command**

Run:

```bash
rg -n -- "--realistic-provider --gate|budget_p95_ns|budget_p99_ns| gate=" .github/scripts/realistic-relative-observation.sh
```

Expected: no output and exit code `1`.

- [ ] **Step 5: Commit the helper**

Run:

```bash
git add .github/scripts/realistic-relative-observation.sh
git commit -m "ci: add realistic relative observation helper"
git status --short
```

Expected: commit succeeds and `git status --short` has no output.

## Task 3: Wire The Observational Workflow Step

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Update checkout depth**

Modify the checkout step in `.github/workflows/swift-ci.yml` to fetch full history:

```yaml
      - name: Check out repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
```

- [ ] **Step 2: Add the PR-only observational step**

Add this step after `Run RSS memory observation diagnostic`:

```yaml
      - name: Observe realistic provider relative performance
        if: github.event_name == 'pull_request'
        continue-on-error: true
        env:
          REALISTIC_RELATIVE_OBSERVATION_THRESHOLD: "1.50"
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          set -euo pipefail
          echo "observation_started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          echo "runner_image=${ImageOS:-unknown}"
          echo "cpu_model=$(sysctl -n machdep.cpu.brand_string)"
          swift --version | head -n 1
          xcodebuild -version
          uname -a

          git fetch --no-tags --prune origin '+refs/heads/*:refs/remotes/origin/*'
          git cat-file -e "${BASE_SHA}^{commit}"
          git cat-file -e "${HEAD_SHA}^{commit}"

          work_root="${RUNNER_TEMP}/realistic-relative"
          rm -rf "${work_root}"
          mkdir -p "${work_root}"
          git worktree add --detach "${work_root}/base" "${BASE_SHA}"
          git worktree add --detach "${work_root}/head" "${HEAD_SHA}"

          ./.github/scripts/realistic-relative-observation.sh \
            --base-dir "${work_root}/base" \
            --head-dir "${work_root}/head" \
            --base-sha "${BASE_SHA}" \
            --head-sha "${HEAD_SHA}" \
            --threshold "${REALISTIC_RELATIVE_OBSERVATION_THRESHOLD}"

          echo "observation_finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

This initial threshold is a sampling value. It must be replaced with the calculated threshold before final merge.

- [ ] **Step 3: Verify workflow shape**

Run:

```bash
sed -n '1,120p' .github/workflows/swift-ci.yml
rg -n "fetch-depth: 0|Observe realistic provider relative performance|continue-on-error: true|REALISTIC_RELATIVE_OBSERVATION_THRESHOLD|--realistic-provider --gate|--realistic-provider" .github/workflows/swift-ci.yml
```

Expected:

- `fetch-depth: 0` is present.
- `Observe realistic provider relative performance` is present.
- `continue-on-error: true` is present on that step.
- `REALISTIC_RELATIVE_OBSERVATION_THRESHOLD: "1.50"` is present for initial sampling.
- No workflow line runs `--realistic-provider --gate`.

- [ ] **Step 4: Run local stable verification commands**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
.github/scripts/realistic-relative-observation.sh --self-test
```

Expected:

- `swift test`: PASS.
- `swift build -c release`: PASS.
- `--gate`: PASS with three `gate=pass` lines.
- ungated `--realistic-provider`: PASS with p95/p99 and no budget/gate fields.
- gated `--realistic-provider --gate`: PASS with budget fields and `gate=pass`.
- `--memory-shape`: PASS with three `invariant=pass` lines.
- `--memory-observation`: PASS with three `observation=pass` lines.
- helper self-test: `self_test=pass`.

- [ ] **Step 5: Commit the workflow sampling step**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: observe realistic relative performance"
git status --short
```

Expected: commit succeeds and `git status --short` has no output.

## Task 4: Collect Five Hosted No-Op Samples

**Files:**
- Read: `.github/workflows/swift-ci.yml`
- Read: `.github/scripts/realistic-relative-observation.sh`

- [ ] **Step 1: Push branch and open PR**

Run:

```bash
git push -u origin slice-12-hosted-baseline-relative-realistic-observation
gh pr create \
  --title "Slice 12: hosted baseline-relative realistic observation" \
  --body "Adds nonblocking PR-only hosted base-vs-head realistic-provider observation for Slice 12."
```

Expected: PR is created targeting `main`.

- [ ] **Step 2: Wait for the first hosted run**

Run:

```bash
gh run list --workflow "Swift CI" --branch slice-12-hosted-baseline-relative-realistic-observation --event pull_request --limit 5 --json databaseId,status,conclusion,headSha,createdAt,url
```

Expected: at least one `Swift CI` pull-request run appears for this branch.

- [ ] **Step 3: Capture the first sample**

Set the run ID from Step 2:

```bash
run_id="$(gh run list --workflow "Swift CI" --branch slice-12-hosted-baseline-relative-realistic-observation --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id" --exit-status
mkdir -p /tmp/slice12-realistic-relative-samples
gh run view "$run_id" --attempt 1 --log > /tmp/slice12-realistic-relative-samples/sample-1.log
rg -n "mode=realistic_relative_observation|observation_started_at|runner_image=|cpu_model=|Swift version|Xcode|Darwin" /tmp/slice12-realistic-relative-samples/sample-1.log
```

Expected:

- `gh run watch` exits `0`. If it exits non-zero only because the observational step failed while stable gates passed, inspect logs and fix the infrastructure failure before accepting a sample.
- Log contains one `mode=realistic_relative_observation` summary.
- Summary has `comparison_repetitions_per_side=4`, p95/p99 value lists, medians, ratios, `observation_threshold=1.50`, and `blocking_ready=false`.
- Summary is not `observation=skipped_base_unsupported` for this repository because current `main` already supports the realistic-provider command.

- [ ] **Step 4: Collect four additional fresh hosted samples**

Rerun the completed workflow four times, waiting after each rerun:

```bash
for attempt in 2 3 4 5; do
  gh run rerun "$run_id"
  gh run watch "$run_id" --exit-status
  gh run view "$run_id" --attempt "$attempt" --log > "/tmp/slice12-realistic-relative-samples/sample-${attempt}.log"
  rg -n "mode=realistic_relative_observation|observation_started_at|runner_image=|cpu_model=|Swift version|Xcode|Darwin" "/tmp/slice12-realistic-relative-samples/sample-${attempt}.log"
done
```

Expected for each attempt:

- Stable gates pass.
- The observational step prints one summary line.
- Each summary has `comparison_repetitions_per_side=4`.
- Each summary uses run order `base,head,head,base,base,head,head,base`.
- Each summary exits zero or is tolerated by `continue-on-error`.

- [ ] **Step 5: Compute threshold from accepted samples**

Run:

```bash
rg "mode=realistic_relative_observation" /tmp/slice12-realistic-relative-samples/sample-*.log > /tmp/slice12-realistic-relative-samples/summaries.txt
awk '
  {
    for (i = 1; i <= NF; i++) {
      split($i, kv, "=")
      if (kv[1] == "max_ratio") {
        ratio = kv[2] + 0
        if (ratio > max_ratio) max_ratio = ratio
      }
    }
  }
  END {
    candidate = max_ratio * 1.05
    threshold = candidate
    if (threshold > 1.50) threshold = 1.50
    printf "max_noop_ratio=%.6f\ncandidate_threshold=%.6f\nobservation_threshold=%.6f\nthreshold_eligible_for_future_blocking=%s\n", max_ratio, candidate, threshold, (candidate <= 1.50 ? "true" : "false")
  }
' /tmp/slice12-realistic-relative-samples/summaries.txt | tee /tmp/slice12-realistic-relative-samples/threshold.txt
```

Expected:

- `max_noop_ratio` is present.
- `candidate_threshold` is present.
- `observation_threshold` is present.
- `threshold_eligible_for_future_blocking` is present.

- [ ] **Step 6: Reject unusable samples before proceeding**

Run:

```bash
rg -n "observation=skipped_base_unsupported|observation=infrastructure_failure|comparison_repetitions_per_side=4|run_order=base,head,head,base,base,head,head,base" /tmp/slice12-realistic-relative-samples/summaries.txt
```

Expected:

- No accepted sample has `observation=skipped_base_unsupported`.
- No accepted sample has `observation=infrastructure_failure`.
- Every accepted sample has `comparison_repetitions_per_side=4`.
- Every accepted sample has the expected run order.

If any accepted sample fails those checks, collect another fresh sample before calculating the final threshold.

## Task 5: Finalize Threshold And Verification Record

**Files:**
- Modify: `.github/workflows/swift-ci.yml`
- Create: `docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md`

- [ ] **Step 1: Update workflow threshold to the calculated value**

Read `/tmp/slice12-realistic-relative-samples/threshold.txt`, then edit `.github/workflows/swift-ci.yml` so:

```yaml
          REALISTIC_RELATIVE_OBSERVATION_THRESHOLD: "1.50"
```

becomes the exact `observation_threshold` value printed in `threshold.txt`, formatted with six decimal places, for example:

```yaml
          REALISTIC_RELATIVE_OBSERVATION_THRESHOLD: "1.234567"
```

Use that illustrative YAML value only if it exactly matches the computed `observation_threshold`.

- [ ] **Step 2: Create the verification document**

Create `docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md` with these sections and the actual command outputs captured during execution:

```markdown
# Hosted Baseline-Relative Realistic Observation Verification

Date: 2026-06-08

## Scope

Slice 12 adds a PR-only nonblocking hosted realistic-provider base-vs-head observation. The observation uses ungated `--realistic-provider` runs, median-of-4 per side, interleaved run order, and `continue-on-error: true`. Blocking remains disabled.

## Local Verification

Record exact outputs for:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
.github/scripts/realistic-relative-observation.sh --self-test
```

## Hosted No-Op Samples

For each accepted sample, record:

- run ID
- attempt
- run URL
- event
- head branch
- base SHA
- head SHA
- runner image
- CPU model
- Swift version
- Xcode version
- `uname -a`
- started timestamp
- finished timestamp
- full `mode=realistic_relative_observation` summary line

## Threshold Decision

Record the exact four lines printed by `/tmp/slice12-realistic-relative-samples/threshold.txt`, preceded by `accepted_noop_samples=5`.

## Final Workflow State

Record the `rg` output proving:

```text
fetch-depth: 0
Observe realistic provider relative performance
continue-on-error: true
```

Also record the actual `REALISTIC_RELATIVE_OBSERVATION_THRESHOLD` line from `.github/workflows/swift-ci.yml`.

Record that no hosted relative workflow command uses `--realistic-provider --gate`.

## Final Hosted PR Verification

Record the final hosted run after the threshold commit:

- run ID
- attempt
- run URL
- event
- head SHA
- conclusion
- job duration
- final observation summary line
- whether stable gates passed
- whether the observation step was nonblocking

## Non-Goal Checks

Record:

```text
git diff main -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Expected: no `TextEngineCore` changes, no benchmark budget changes, no `Package.swift` changes unless the implementation needed a documented script-test target.

## Conclusion

State that Slice 12 is observational-only, blocking remains disabled, and promotion requires a later slice after the frozen no-op-equivalent evidence rule is satisfied.
```

The committed verification document must contain real values from the commands above.

- [ ] **Step 3: Verify the verification document has no draft text**

Run:

```bash
rg -n "DRAFT_VALUE|SAMPLE_ONLY|UNRECORDED" docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md
```

Expected: no output and exit code `1`.

- [ ] **Step 4: Verify workflow threshold and nonblocking shape**

Run:

```bash
rg -n "Observe realistic provider relative performance|continue-on-error: true|REALISTIC_RELATIVE_OBSERVATION_THRESHOLD|--realistic-provider --gate|--realistic-provider" .github/workflows/swift-ci.yml
```

Expected:

- Observation step is present.
- `continue-on-error: true` is present.
- Threshold is the calculated six-decimal value.
- No workflow command uses `--realistic-provider --gate`.
- Existing stable gates are still present.

- [ ] **Step 5: Commit threshold and verification record**

Run:

```bash
git add .github/workflows/swift-ci.yml docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md
git commit -m "docs: record hosted relative observation verification"
git status --short
```

Expected: commit succeeds and `git status --short` has no output.

## Task 6: Final Slice Verification

**Files:**
- Read: `docs/superpowers/specs/2026-06-08-hosted-baseline-relative-realistic-observation-design.md`
- Read: `docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `.github/scripts/realistic-relative-observation.sh`

- [ ] **Step 1: Run final local verification**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
.github/scripts/realistic-relative-observation.sh --self-test
```

Expected: all commands pass. Ungated `--realistic-provider` output has p95/p99 and no budget/gate fields.

- [ ] **Step 2: Verify no source or budget drift**

Run:

```bash
git diff main -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
rg -n "p95BudgetNanoseconds|p99BudgetNanoseconds|20_000|50_000" Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
```

Expected:

- No diff in `Sources/TextEngineCore`.
- No diff in `Sources/ViewportBenchmarks`.
- No diff in `Tests`.
- No diff in `Package.swift`.
- Realistic-provider local budgets remain `20_000` and `50_000`.

- [ ] **Step 3: Verify hosted relative path is ungated and nonblocking**

Run:

```bash
rg -n -- "--realistic-provider --gate|continue-on-error: true|Observe realistic provider relative performance|REALISTIC_RELATIVE_OBSERVATION_THRESHOLD" .github/workflows/swift-ci.yml .github/scripts/realistic-relative-observation.sh
```

Expected:

- `continue-on-error: true` is present in workflow.
- Observation threshold is present in workflow.
- No hosted relative command uses `--realistic-provider --gate`.
- The only allowed `--realistic-provider --gate` occurrences are in docs or local verification commands, not in `.github/workflows/swift-ci.yml` or `.github/scripts/realistic-relative-observation.sh`.

- [ ] **Step 4: Wait for final hosted PR run after verification commit**

Run:

```bash
final_run_id="$(gh run list --workflow "Swift CI" --branch slice-12-hosted-baseline-relative-realistic-observation --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$final_run_id" --exit-status
gh run view "$final_run_id" --log > /tmp/slice12-final-hosted-run.log
rg -n "Run host tests|Run synthetic benchmark gate|Run memory shape diagnostic|Run RSS memory observation diagnostic|Observe realistic provider relative performance|mode=realistic_relative_observation|continue-on-error" /tmp/slice12-final-hosted-run.log
```

Expected:

- Overall hosted run succeeds.
- Stable gates ran.
- Observation step ran.
- Final observation summary has the calculated threshold.
- Observation step does not make overall CI fail.

- [ ] **Step 5: Update verification document with final hosted run if needed**

If Step 4 produced a final run not already recorded, append the run ID, run URL, head SHA, conclusion, duration, and observation summary to `docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md`, then commit:

```bash
git add docs/superpowers/verification/2026-06-08-hosted-baseline-relative-realistic-observation.md
git commit -m "docs: update hosted relative observation final run"
```

Expected: commit succeeds. If the final hosted run was already recorded in Task 5, no commit is needed.

- [ ] **Step 6: Final status check**

Run:

```bash
git status --short
git log --oneline -6
```

Expected:

- `git status --short` has no output.
- Recent commits include helper, workflow, and verification commits for Slice 12.
