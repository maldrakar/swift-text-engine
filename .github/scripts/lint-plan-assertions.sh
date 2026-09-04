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

# Resolve paths from the script's own location, not the caller's cwd: PlanLintTests
# (Task 5) invokes this script via `/usr/bin/env bash <absolute path>` with no fixed
# working directory, and an authoring tool should also work from a subdirectory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLANS_DIR="$REPO_ROOT/docs/superpowers/plans"

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
# A ``` line inside a heredoc body is content, not a fence delimiter (Ruling F5) --
# without this guard a plan whose own heredoc carries markdown fixtures (fence
# delimiters included) corrupts in_fence/in_heredoc state scanning itself.
/^```/ && !in_heredoc {
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
  # Double-quoted (not single-quoted) so $dir expands NOW, at trap-set time, into a
  # literal path baked into the trap body. A single-quoted trap defers expansion to
  # when the EXIT trap fires -- after this function has returned and its `local dir`
  # has gone out of scope -- and `set -u` then kills the script on "dir: unbound
  # variable", even though self_test=pass already printed.
  trap "rm -rf \"$dir\"" EXIT

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
