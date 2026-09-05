#!/usr/bin/env bash
set -uo pipefail

BASE_SHA=""
HEAD_SHA=""
GITHUB_OUTPUT_FILE=""
DOCS_ONLY_RESULT=""
DOCS_ONLY_FILE_COUNT="0"
DOCS_ONLY_NON_DOC_COUNT="0"

usage() {
  cat <<'EOF'
Usage:
  detect-docs-only-pr.sh --base SHA --head SHA [--github-output FILE]
  detect-docs-only-pr.sh --self-test
EOF
}

fail() {
  echo "mode=docs_only_pr result=infrastructure_failure reason=$1 docs_only_pr=false"
  exit 2
}

# ---------------------------------------------------------------------------
# Function classification (enforced by --self-test, see the partition check in
# run_self_test). Every function in this file is either COVERED (referenced by
# the self-test's own source), EXEMPT (named here with a reason), or harness
# (assert_* / run_self_test, derived).
# ---------------------------------------------------------------------------

SELF_TEST_COVERED=(
  is_docs_only_path
  classify_paths
  emit_classification
  defined_functions
  is_harness_function
  self_test_body
  body_references_function
)

# name<TAB>justification. Parallel-array-free and bash 3.2-safe: no declare -A.
SELF_TEST_EXEMPT=(
  "usage	prints CLI usage text; reachable only via --help and the argument-error path, never named by the self-test"
  "fail	emits the infrastructure-failure line and exits 2; reachable only via CLI argument validation and the git failure paths, never named by the self-test"
  "write_github_output	writes docs_only_pr= to GITHUB_OUTPUT_FILE; runs via emit_classification but is never named directly by the self-test"
)

# Every TOP-LEVEL function defined in a script file, one name per line. Pure.
#
# Anchored at column 0 on purpose: an INDENTED definition is a nested one (the
# --self-test scenarios below define stubs inside their own bodies) and must stay
# out of the partition. Everything else bash accepts must be seen, or the function
# escapes classification silently -- so all four spellings are matched: `name() {`,
# `name(){`, `name () {`, and both `function name {` forms. Names take the full
# identifier alphabet, not [a-z_]: a digit or a capital is not an escape hatch.
# ERE (grep -oE / sed -E) rather than BRE because BSD sed has no `\?`.
defined_functions() {
  grep -oE '^(function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*([[:space:]]*\(\))?|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\))[[:space:]]*\{' "$1" \
    | sed -E -e 's/^function[[:space:]]+//' -e 's/[[:space:]]*(\(\))?[[:space:]]*\{$//'
}

# The harness set is DERIVED, never hand-listed, so it cannot go stale.
is_harness_function() {
  case "$1" in
    assert_*|run_self_test) return 0 ;;
    *) return 1 ;;
  esac
}

# The self-test's own source: run_self_test plus every scenario_* function (they ARE
# the self-test -- they drive the ladder and the drift path). Three subtractions keep
# the coverage check from becoming a tautology:
#   * the classification arrays are top-level, hence outside this extraction, so a
#     name cannot satisfy the check by appearing in the list it is checked against;
#   * comments are stripped -- run_self_test's prose names helpers it does not call;
#   * definition lines are stripped -- defining a stub named X is not evidence that
#     the self-test exercises X.
self_test_body() {
  awk '
    /^(run_self_test|scenario_[a-z_]*)\(\) \{/ { inside = 1 }
    inside { print }
    inside && /^}/ { inside = 0 }
  ' "$1" | sed -e 's/#.*$//' -e '/^[[:space:]]*[a-z_][a-z0-9_]*() {$/d'
}

# Token match, never substring: resolve_wasm_sdk_id must not be satisfied by
# resolve_wasm_sdk_id_from_list (the repo's --variable-height lesson).
body_references_function() {
  printf '%s\n' "$2" | grep -qE "(^|[^A-Za-z0-9_])$1([^A-Za-z0-9_]|\$)"
}

assert_function_defined() {
  local fn="$1" defined="$2" label="$3"
  if ! printf '%s\n' "$defined" | grep -qx -- "$fn"; then
    echo "self_test=fail label=$label expected=defined actual=missing fn=$fn"
    exit 1
  fi
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

assert_contains() {
  local needle="$1"
  local actual="$2"
  local label="$3"
  if [[ "$actual" != *"$needle"* ]]; then
    echo "self_test=fail label=$label expected_contains=$needle actual=$actual"
    exit 1
  fi
}

assert_runtime_classification() {
  local script_path="$1"
  local label="$2"
  local base_sha="$3"
  local head_sha="$4"
  local expected_status="$5"
  local expected_output="$6"
  local expected_github_output="$7"
  local output_file output status github_output

  output_file="$(mktemp "${TMPDIR:-/tmp}/docs-only-runtime-output.XXXXXX")"
  output="$(bash "$script_path" --base "$base_sha" --head "$head_sha" --github-output "$output_file" 2>&1)"
  status=$?
  github_output="$(cat "$output_file")"
  rm -f "$output_file"

  assert_equal "$expected_status" "$status" "${label}_status"
  assert_contains "$expected_output" "$output" "${label}_output"
  assert_equal "$expected_github_output" "$github_output" "${label}_github_output"
}

assert_command_success() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "self_test=fail label=$label expected=success actual=failure"
    exit 1
  fi
}

assert_command_failure() {
  local label="$1"
  shift
  if "$@"; then
    echo "self_test=fail label=$label expected=failure actual=success"
    exit 1
  fi
}

is_docs_only_path() {
  local path="$1"
  case "$path" in
    .github/workflows/*|.github/scripts/*) return 1 ;;
    docs/*|*.md) return 0 ;;
    *) return 1 ;;
  esac
}

classify_paths() {
  local path count=0 non_doc_count=0
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    count=$((count + 1))
    if ! is_docs_only_path "$path"; then
      non_doc_count=$((non_doc_count + 1))
    fi
  done

  DOCS_ONLY_FILE_COUNT="$count"
  DOCS_ONLY_NON_DOC_COUNT="$non_doc_count"
  if [[ "$non_doc_count" -eq 0 ]]; then
    DOCS_ONLY_RESULT="docs_only"
  else
    DOCS_ONLY_RESULT="not_docs_only"
  fi
}

write_github_output() {
  local docs_only_flag="$1"
  if [[ -n "$GITHUB_OUTPUT_FILE" ]]; then
    printf 'docs_only_pr=%s\n' "$docs_only_flag" >> "$GITHUB_OUTPUT_FILE"
  fi
}

emit_classification() {
  local docs_only_flag="false"
  if [[ "$DOCS_ONLY_RESULT" == "docs_only" ]]; then
    docs_only_flag="true"
  fi
  write_github_output "$docs_only_flag"
  echo "mode=docs_only_pr result=$DOCS_ONLY_RESULT docs_only_pr=$docs_only_flag file_count=$DOCS_ONLY_FILE_COUNT non_doc_count=$DOCS_ONLY_NON_DOC_COUNT"
}

run_self_test() {
  assert_command_success "docs_dir_markdown" is_docs_only_path docs/guide.md
  assert_command_success "docs_dir_asset" is_docs_only_path docs/assets/diagram.png
  assert_command_success "root_markdown" is_docs_only_path README.md
  assert_command_success "nested_markdown" is_docs_only_path docs/superpowers/specs/design.md
  assert_command_failure "swift_source" is_docs_only_path Sources/TextEngineCore/ViewportVirtualizer.swift
  assert_command_failure "workflow_yaml" is_docs_only_path .github/workflows/swift-ci.yml
  assert_command_failure "workflow_markdown_is_policy_sensitive" is_docs_only_path .github/workflows/README.md
  assert_command_failure "helper_markdown_is_policy_sensitive" is_docs_only_path .github/scripts/README.md
  assert_command_failure "uppercase_markdown_is_not_configured_pattern" is_docs_only_path Notes.MD

  classify_paths <<'EOF'
docs/guide.md
docs/assets/diagram.png
README.md
EOF
  assert_equal "docs_only" "$DOCS_ONLY_RESULT" "classify_docs_only_result"
  assert_equal "3" "$DOCS_ONLY_FILE_COUNT" "classify_docs_only_count"
  assert_equal "0" "$DOCS_ONLY_NON_DOC_COUNT" "classify_docs_only_non_doc_count"

  classify_paths <<'EOF'
docs/guide.md
.github/workflows/swift-ci.yml
EOF
  assert_equal "not_docs_only" "$DOCS_ONLY_RESULT" "classify_mixed_result"
  assert_equal "2" "$DOCS_ONLY_FILE_COUNT" "classify_mixed_count"
  assert_equal "1" "$DOCS_ONLY_NON_DOC_COUNT" "classify_mixed_non_doc_count"

  classify_paths <<'EOF'
EOF
  assert_equal "docs_only" "$DOCS_ONLY_RESULT" "classify_empty_result"
  assert_equal "0" "$DOCS_ONLY_FILE_COUNT" "classify_empty_count"
  assert_equal "0" "$DOCS_ONLY_NON_DOC_COUNT" "classify_empty_non_doc_count"

  local script_path runtime_repo base_sha docs_head mixed_head workflow_head helper_head workflow_markdown_head helper_markdown_head missing_sha
  case "${BASH_SOURCE[0]}" in
    /*) script_path="${BASH_SOURCE[0]}" ;;
    *) script_path="$(pwd)/${BASH_SOURCE[0]}" ;;
  esac

  runtime_repo="$(mktemp -d "${TMPDIR:-/tmp}/docs-only-runtime.XXXXXX")"
  (
    cd "$runtime_repo" || exit 1
    git init -q
    git config user.name "Docs Only Test"
    git config user.email "docs-only@example.invalid"

    mkdir -p docs
    printf 'base\n' > docs/guide.md
    git add docs/guide.md
    git commit -q -m base
    base_sha="$(git rev-parse HEAD)"

    git checkout -q -B docs-only "$base_sha"
    printf 'docs\n' >> docs/guide.md
    git add docs/guide.md
    git commit -q -m docs-only
    docs_head="$(git rev-parse HEAD)"

    git checkout -q -B mixed-source "$base_sha"
    printf 'docs\n' >> docs/guide.md
    mkdir -p Sources/TextEngineCore
    printf 'source\n' > Sources/TextEngineCore/Example.swift
    git add docs/guide.md Sources/TextEngineCore/Example.swift
    git commit -q -m mixed-source
    mixed_head="$(git rev-parse HEAD)"

    git checkout -q -B workflow-change "$base_sha"
    mkdir -p .github/workflows
    printf 'name: Swift CI\n' > .github/workflows/swift-ci.yml
    git add .github/workflows/swift-ci.yml
    git commit -q -m workflow-change
    workflow_head="$(git rev-parse HEAD)"

    git checkout -q -B helper-change "$base_sha"
    mkdir -p .github/scripts
    printf '#!/usr/bin/env bash\n' > .github/scripts/detect-docs-only-pr.sh
    git add .github/scripts/detect-docs-only-pr.sh
    git commit -q -m helper-change
    helper_head="$(git rev-parse HEAD)"

    git checkout -q -B workflow-markdown-change "$base_sha"
    mkdir -p .github/workflows
    printf 'workflow docs\n' > .github/workflows/README.md
    git add .github/workflows/README.md
    git commit -q -m workflow-markdown-change
    workflow_markdown_head="$(git rev-parse HEAD)"

    git checkout -q -B helper-markdown-change "$base_sha"
    mkdir -p .github/scripts
    printf 'helper docs\n' > .github/scripts/README.md
    git add .github/scripts/README.md
    git commit -q -m helper-markdown-change
    helper_markdown_head="$(git rev-parse HEAD)"

    missing_sha="0000000000000000000000000000000000000000"

    assert_runtime_classification "$script_path" "runtime_docs_only" "$base_sha" "$docs_head" "0" "docs_only_pr=true" "docs_only_pr=true"
    assert_runtime_classification "$script_path" "runtime_mixed_source" "$base_sha" "$mixed_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_workflow_change" "$base_sha" "$workflow_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_helper_change" "$base_sha" "$helper_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_workflow_markdown_change" "$base_sha" "$workflow_markdown_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_helper_markdown_change" "$base_sha" "$helper_markdown_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_missing_base" "$missing_sha" "$docs_head" "2" "reason=base_commit_unavailable" ""
    assert_runtime_classification "$script_path" "runtime_empty_diff" "$base_sha" "$base_sha" "2" "reason=empty_diff" ""
  ) || exit 1
  rm -rf "$runtime_repo"

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/docs-only-output.XXXXXX")"
  GITHUB_OUTPUT_FILE="$output_file"
  DOCS_ONLY_RESULT="docs_only"
  DOCS_ONLY_FILE_COUNT="1"
  DOCS_ONLY_NON_DOC_COUNT="0"
  emit_classification >/dev/null
  assert_equal "docs_only_pr=true" "$(cat "$output_file")" "github_output_true"

  : > "$output_file"
  DOCS_ONLY_RESULT="not_docs_only"
  DOCS_ONLY_FILE_COUNT="1"
  DOCS_ONLY_NON_DOC_COUNT="1"
  emit_classification >/dev/null
  assert_equal "docs_only_pr=false" "$(cat "$output_file")" "github_output_false"

  rm -f "$output_file"
  local script_path defined body fn entry name classified
  script_path="${BASH_SOURCE[0]}"
  defined="$(defined_functions "$script_path")"
  body="$(self_test_body "$script_path")"

  # Direction 1: every defined function is classified.
  for fn in $defined; do
    if is_harness_function "$fn"; then continue; fi
    classified=0
    for name in "${SELF_TEST_COVERED[@]+"${SELF_TEST_COVERED[@]}"}"; do
      [[ "$name" == "$fn" ]] && classified=1
    done
    for entry in "${SELF_TEST_EXEMPT[@]+"${SELF_TEST_EXEMPT[@]}"}"; do
      [[ "${entry%%$'\t'*}" == "$fn" ]] && classified=1
    done
    assert_equal "1" "$classified" "classified_${fn}"
  done

  # Direction 2: no phantom names, and every exempt entry carries a justification.
  for name in "${SELF_TEST_COVERED[@]+"${SELF_TEST_COVERED[@]}"}"; do
    assert_function_defined "$name" "$defined" "covered_defined_${name}"
  done
  for entry in "${SELF_TEST_EXEMPT[@]+"${SELF_TEST_EXEMPT[@]}"}"; do
    assert_function_defined "${entry%%$'\t'*}" "$defined" "exempt_defined_${entry%%$'\t'*}"
    if [[ "$entry" != *$'\t'* || -z "${entry#*$'\t'}" ]]; then
      echo "self_test=fail label=exempt_justified_${entry} expected=justification actual=none"
      exit 1
    fi
  done

  # Coverage: every covered function is really referenced by the self-test's source.
  for name in "${SELF_TEST_COVERED[@]+"${SELF_TEST_COVERED[@]}"}"; do
    if ! body_references_function "$name" "$body"; then
      echo "self_test=fail label=covered_but_unreferenced fn=$name"
      exit 1
    fi
  done

  echo "self_test=pass"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      run_self_test
      exit 0
      ;;
    --base)
      [[ $# -ge 2 ]] || fail "missing_base_argument"
      BASE_SHA="$2"
      shift 2
      ;;
    --head)
      [[ $# -ge 2 ]] || fail "missing_head_argument"
      HEAD_SHA="$2"
      shift 2
      ;;
    --github-output)
      [[ $# -ge 2 ]] || fail "missing_github_output_argument"
      GITHUB_OUTPUT_FILE="$2"
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

[[ -n "$BASE_SHA" ]] || fail "missing_base_sha"
[[ -n "$HEAD_SHA" ]] || fail "missing_head_sha"

git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null || fail "base_commit_unavailable"
git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null || fail "head_commit_unavailable"

if ! changed_paths="$(git diff --name-only "${BASE_SHA}...${HEAD_SHA}" 2>/dev/null)"; then
  fail "diff_unavailable"
fi

if [[ -z "$changed_paths" ]]; then
  fail "empty_diff"
fi

classify_paths <<< "$changed_paths"
emit_classification
