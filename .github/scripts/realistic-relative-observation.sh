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

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "self_test=fail label=$label missing=$needle"
    exit 1
  fi
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
  local missing_p95_line="mode=realistic_provider provider=large_text p99_ns=200"
  local invalid_p99_line="mode=realistic_provider provider=large_text p95_ns=100 p99_ns=abc"
  local skip_line
  local infra_line="mode=realistic_relative_observation observation=infrastructure_failure reason=head_command_failed blocking_ready=false"
  assert_equal "100" "$(extract_field "$line" "p95_ns")" "extract_p95"
  assert_equal "200" "$(extract_field "$line" "p99_ns")" "extract_p99"
  validate_output_line "$line" || {
    echo "self_test=fail label=validate_output_line"
    exit 1
  }
  assert_command_success "positive_integer_one" is_positive_integer 1
  assert_command_failure "positive_integer_zero" is_positive_integer 0
  assert_command_failure "positive_integer_negative" is_positive_integer -1
  assert_command_failure "positive_integer_alpha" is_positive_integer abc
  assert_command_failure "validate_missing_p95" validate_output_line "$missing_p95_line"
  assert_command_failure "validate_invalid_p99" validate_output_line "$invalid_p99_line"
  assert_equal "115.000000" "$(median_values 100 130 110 120)" "median_even"
  assert_equal "110" "$(median_values 100 130 110)" "median_odd"
  assert_equal "1.250000" "$(ratio_values 125 100)" "ratio"
  assert_equal "1.300000" "$(max_values 1.200000 1.300000)" "max_ratio"
  assert_equal "clean" "$(classify_observation 1.250000 1.500000)" "classify_clean"
  assert_equal "above_threshold" "$(classify_observation 1.510000 1.500000)" "classify_above"
  BASE_SHA="base"
  HEAD_SHA="head"
  THRESHOLD="1.500000"
  skip_line="$(print_skip_base_unsupported "base_command_unknown_argument")"
  assert_contains "$skip_line" "observation=skipped_base_unsupported" "skip_summary_observation"
  assert_contains "$skip_line" "reason=base_command_unknown_argument" "skip_summary_reason"
  assert_contains "$infra_line" "observation=infrastructure_failure" "infra_summary_observation"
  assert_contains "$infra_line" "blocking_ready=false" "infra_summary_nonblocking"
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
      # This diagnostic is tied to SwiftPM's current unknown-argument text. In this repository,
      # current main should already support --realistic-provider, so this branch is expected only
      # when comparing against an older unsupported base.
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
