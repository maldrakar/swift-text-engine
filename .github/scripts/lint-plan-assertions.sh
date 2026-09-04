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
#   R2  `echo "...=$?"` whose predecessor -- the same-line segment before a ';' that leads
#       into it, or else the previous shell line -- is a command insensitive to the
#       invariant (git status, gh, jq, sed -i, or `git diff` WITHOUT --quiet/--exit-code,
#       which are exactly the status-SENSITIVE forms) or a pipeline (D-2 rule 2).
#   R3  A SCREAMING_SNAKE variable used in a fence but assigned nowhere in that same fence
#       (D-2 rule 4; slice 47's $SCRATCH resolved to /x.txt at 23 sites).
#   R4  A task section with no `**Guarantees added:**` block, or one that lists a guarantee
#       with no drill step naming it (D-35).
#   scanner  A shape the scanner itself cannot get past. Currently one case: a heredoc
#       opened inside a bash/sh fence and never terminated, which would otherwise abandon
#       the scan silently and let the rest of the file read as clean.
#
# Scope: `bash` and `sh` fences only, and HEREDOC BODIES ARE SKIPPED for every rule. A plan
# that builds a shell tool carries that tool's source -- including its own known-bad
# fixtures -- inside heredocs; without the skip, the linter could not be built by a
# compliant plan. It also keeps R3 from analysing heredoc'd Python as shell. A `<<<`
# here-string is not treated as a heredoc opener (it would otherwise silence every rule
# for the rest of the fence, reading its 2nd/3rd '<' as a real `<<`).
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
self_test_dir=""

# Removes the awk program temp file (leaked on EVERY invocation before this fix,
# including --list-exempt, which never runs awk at all) and, if a self-test ran, its
# fixture directory. One trap, set once in main, reading both as globals when it fires
# (minor 6) -- not a per-call trap baking in a literal path, which is what run_self_test
# used to need (and why its own trap body had to be double-quoted at set-time; a global
# read at fire time doesn't have that wart).
cleanup() {
  [[ -n "$awk_program_path" ]] && rm -f "$awk_program_path"
  [[ -n "$self_test_dir" ]] && rm -rf "$self_test_dir"
  return 0
}

write_awk_program() {
  awk_program_path="$(mktemp)"
  cat > "$awk_program_path" <<'AWKPROG'
BEGIN {
  split("HOME PWD TMPDIR PATH USER SHELL IFS OLDPWD RANDOM SECONDS PIPESTATUS " \
        "NF NR FS OFS ORS RS FILENAME SUBSEP", allowlist, " ")
  for (i in allowlist) allowed[allowlist[i]] = 1
  in_fence = 0; lang = ""; in_heredoc = 0; heredoc_tag = ""; heredoc_start = 0
  prev_shell = ""
  in_task = 0; task_name = ""; task_start = 0; guarantee_line = 0
}

function report(rule, line, detail) {
  printf "violation=%s file=%s line=%d detail=%s\n", rule, FILENAME, line, detail
  violations++
}

function is_insensitive_predecessor(pred) {
  if (pred ~ /^[ \t]*(git[ \t]+status|gh[ \t]|jq[ \t]|sed[ \t]+-i)/) return 1
  # git diff is insensitive UNLESS it carries --quiet/--exit-code -- those are exactly
  # the status-SENSITIVE forms (Finding 3); the other four prefixes are unchanged.
  if (pred ~ /^[ \t]*git[ \t]+diff/ && pred !~ /--quiet/ && pred !~ /--exit-code/) return 1
  if (pred ~ /\|/) return 1
  return 0
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
    # A `<<<` here-string phantom-matches this pattern too, via its 2nd/3rd '<' (minor
    # 8): the character just before the match is another '<' exactly when that
    # happened -- a real `<<`/`<<-` redirect is never preceded by a third '<'.
    if (!(RSTART > 1 && substr($0, RSTART - 1, 1) == "<")) {
      tag = substr($0, RSTART, RLENGTH)
      sub(/^<<-?[ \t]*/, "", tag); gsub(/['"]/, "", tag)
      heredoc_tag = tag; in_heredoc = 1; heredoc_start = FNR
    }
  }

  if ($0 ~ /PIPESTATUS/) {
    report("R1", FNR, \
      "PIPESTATUS is not populated under zsh, where agent command blocks run: " \
      "${PIPESTATUS[0]} expands EMPTY and [ \"\" -eq 0 ] is TRUE, so the check inverts " \
      "into a pass (D-17). Do not pipe, or wrap the pipeline in bash -c 'set -o pipefail'")
  }

  if ($0 ~ /echo[^=]*=\$\?/) {
    # The echo's real predecessor is whatever precedes it on the SAME line when the two
    # are ';'-joined (Finding 2) -- `rg -n ... ; echo "exit=$?"` is judged by `rg`, not by
    # whatever line happens to sit above it. Only fall back to the previous line when no
    # same-line ';' leads into the echo.
    pred = prev_shell
    if ($0 ~ /;/) {
      nseg = split($0, segs, ";")
      found_seg = 0
      for (si = 1; si <= nseg; si++) {
        if (segs[si] ~ /echo[^=]*=\$\?/) { found_seg = si; break }
      }
      if (found_seg > 1) pred = segs[found_seg - 1]
    }
    if (is_insensitive_predecessor(pred)) {
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
  if (in_heredoc) {
    report("scanner", heredoc_start, \
      "heredoc <<'" heredoc_tag "' opened at line " heredoc_start " was never " \
      "terminated; the scan was abandoned at that point, so everything after it in " \
      "this file went unchecked (Finding 4 -- an unterminated heredoc must not read " \
      "as a clean plan)")
  }
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
  # bash 3.2 (this project's macOS default) treats "${files[@]}" on an EMPTY array as
  # an unbound-variable error under `set -u`, unlike bash 4.4+; this form expands to
  # nothing instead of erroring when the array is empty (minor 7 -- reachable when
  # every plan under PLANS_DIR is exempt).
  for path in ${files[@]+"${files[@]}"}; do
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
  # Global (not `local dir` + its own trap): main's single `trap cleanup EXIT` removes
  # this directory when the whole script exits, reading the variable at fire time
  # (minor 6) rather than a per-call trap needing to bake in a literal path.
  self_test_dir="$(mktemp -d)"

  cat > "$self_test_dir/good.md" <<'FIXTURE'
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

  cat > "$self_test_dir/bad-r1.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
swift test 2>&1 | tail -5
echo "status=${PIPESTATUS[0]}"
```
FIXTURE

  cat > "$self_test_dir/bad-r2.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
git status
echo "clean=$?"
```
FIXTURE

  # Finding 2: the echo's real predecessor is the same-line segment before a ';', not
  # whatever line happens to sit above it.
  cat > "$self_test_dir/bad-r2-semicolon.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
git status ; echo "x=$?"
```
FIXTURE

  cat > "$self_test_dir/clean-r2-semicolon-after-pipe.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
swift test 2>&1 | tail -5
rg foo bar ; echo "x=$?"
```
FIXTURE

  # Finding 3: `git diff --quiet`/`--exit-code` are exactly the status-SENSITIVE forms,
  # so they must NOT be flagged; a plain `git diff` (e.g. --name-only) still must be.
  cat > "$self_test_dir/clean-r2-diff-quiet.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
git diff --quiet -- some/path
echo "restored=$?"
```
FIXTURE

  cat > "$self_test_dir/bad-r2-diff-name-only.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
git diff --name-only
echo "changed=$?"
```
FIXTURE

  cat > "$self_test_dir/bad-r3.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
echo hello > "$SCRATCH/out.txt"
```
FIXTURE

  # Minor 8: a `<<<` here-string must not be read as a heredoc opener -- if it is, the
  # $SOMETHING use below is silently swallowed and R3 never fires.
  cat > "$self_test_dir/bad-r3-herestring.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
grep -q foo <<<HELLO
echo "$SOMETHING"
```
FIXTURE

  # Finding 1: this is the F5 drill itself. Every heredoc in the OTHER fixtures here
  # (good.md's INNER body) carries an EVEN number of ``` lines, so the corruption a
  # pre-F5 scanner suffers cancels itself out and no existing fixture discriminates the
  # guard. This one carries an ODD count (one ``` line) inside the heredoc body, so a
  # pre-F5 scanner's fence-tracking desyncs and swallows the second fence's genuine R3
  # violation whole; a post-F5 scanner stays synced and catches it.
  cat > "$self_test_dir/bad-fence-in-heredoc.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
cat <<'EOF'
```
EOF
```

```bash
echo "$SOMETHING"
```
FIXTURE

  # Finding 4: an unterminated heredoc must not silently swallow the rest of the file --
  # it must be reported (`scanner`) and fail the run, not read as a clean plan.
  cat > "$self_test_dir/bad-unterminated-heredoc.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** none

```bash
cat <<'EOF'
some content
```
FIXTURE

  cat > "$self_test_dir/bad-r4.md" <<'FIXTURE'
### Task 1: something

**Guarantees added:** G7

- [ ] **Step 1: do it**

Nothing here breaks anything.
FIXTURE

  cat > "$self_test_dir/bad-r4-missing.md" <<'FIXTURE'
### Task 1: something

- [ ] **Step 1: do it**
FIXTURE

  local out rc
  # The good fixture must be clean -- and it is the heredoc drill: its INNER body carries
  # PIPESTATUS, `git status` + `echo "dirty=$?"`, and an unassigned-looking use, all of
  # which MUST be skipped. If the scanner ever stops skipping heredocs this goes red.
  set +e
  out="$(run_lint "$self_test_dir/good.md")"; rc=$?
  set -e
  assert_equal "0" "$rc" "good_fixture_exit"
  assert_equal "lint=pass files=1 violations=0" "$out" "good_fixture_output"

  # The two CLEAN fixtures for findings 2 and 3: a same-line ';'-joined echo whose real
  # predecessor is not status-sensitive, and a `git diff --quiet` whose --quiet is
  # exactly what makes it status-SENSITIVE -- neither may be flagged.
  set +e
  out="$(run_lint "$self_test_dir/clean-r2-semicolon-after-pipe.md")"; rc=$?
  set -e
  assert_equal "0" "$rc" "clean_r2_semicolon_after_pipe_exit"
  assert_equal "lint=pass files=1 violations=0" "$out" "clean_r2_semicolon_after_pipe_output"

  set +e
  out="$(run_lint "$self_test_dir/clean-r2-diff-quiet.md")"; rc=$?
  set -e
  assert_equal "0" "$rc" "clean_r2_diff_quiet_exit"
  assert_equal "lint=pass files=1 violations=0" "$out" "clean_r2_diff_quiet_output"

  local name expected
  for name in r1 r2 r2-semicolon r2-diff-name-only r3 r3-herestring \
              fence-in-heredoc unterminated-heredoc r4 r4-missing; do
    case "$name" in
      r1)                                 expected="R1" ;;
      r2|r2-semicolon|r2-diff-name-only)  expected="R2" ;;
      r3|r3-herestring|fence-in-heredoc)  expected="R3" ;;
      unterminated-heredoc)               expected="scanner" ;;
      *)                                  expected="R4" ;;
    esac
    set +e
    out="$(run_lint "$self_test_dir/bad-$name.md")"; rc=$?
    set -e
    assert_equal "1" "$rc" "bad_${name}_exit"
    local rules
    rules="$(echo "$out" | awk -F'violation=' '/^violation=/ { split($2, f, " "); print f[1] }' | sort -u | tr '\n' ',')"
    assert_equal "${expected}," "$rules" "bad_${name}_rule"
  done

  # Finding 5: an unrecognized flag must not fall through to the default plan scan (a
  # vacuous pass) or hang reading an open stdin -- it must reject loudly. $0 is this
  # script's own path; --bogus rejects immediately, before any recursion, and
  # </dev/null keeps a regression from hanging this test instead of failing it.
  set +e
  "$0" --bogus </dev/null >/dev/null 2>&1
  rc=$?
  set -e
  assert_equal "2" "$rc" "unknown_flag_exit"

  local exempt_count
  exempt_count="${#EXEMPT_PLANS[@]}"
  if [[ "$exempt_count" -lt 1 ]]; then
    echo "self_test=fail label=exempt_list_empty"
    exit 1
  fi

  echo "self_test=pass"
}

main() {
  trap cleanup EXIT
  case "${1:-}" in
    --self-test)
      write_awk_program
      run_self_test
      ;;
    --list-exempt)
      printf '%s\n' "${EXEMPT_PLANS[@]}"
      ;;
    -*)
      # Finding 5: an unrecognized flag must reject loudly, not fall through to the
      # default plan scan (a vacuous pass forever, on a typo'd or renamed CI flag) or
      # hand awk an open stdin to block on.
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      write_awk_program
      run_lint "$@"
      ;;
  esac
}

main "$@"
