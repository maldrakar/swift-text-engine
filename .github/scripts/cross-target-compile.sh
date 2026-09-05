#!/usr/bin/env bash
set -uo pipefail

# Cross-target compile helper for TextEngineCore and TextEngineReferenceProviders.
# Compiles both packages for non-host targets and prints stable key-value lines
# carrying a package= field (core | providers).
#   iOS device + simulator: blocking, through the Swift package graph (xcodebuild).
#   WASM + embedded WASM: blocking, cross-compiled against a swift.org Swift SDK
#   pinned by URL + checksum (CROSS_TARGET_WASM_SDK_URL / _CHECKSUM) and installed
#   with a bounded retry. Provisioning is FAIL-CLOSED: a missing/failed/mismatched
#   SDK is a blocking failure, never a silent skip. Embedded can be demoted to
#   observational via CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false (the fallback ladder).
# The exit code reflects the blocking iOS AND WASM results, across both packages.

TAIL_LINES="${CROSS_TARGET_LOG_TAIL:-40}"
SELECTED_TARGETS="all"

# Created once at the top of run_self_test; removed by an EXIT trap in the MAIN
# shell. Scenario subshells read it but must never create or delete it: a bash 3.2
# EXIT trap does not fire when a `( ... )` subshell exits, which is exactly what
# keeps the first scenario from deleting the directory the next two still need.
SELF_TEST_TMP_ROOT=""

usage() {
  cat <<'EOF'
Usage:
  cross-target-compile.sh
  cross-target-compile.sh --targets all|ios|wasm
  cross-target-compile.sh --self-test

Environment:
  CROSS_TARGET_WASM_SDK_URL          Pinned Swift SDK bundle to install for the
  CROSS_TARGET_WASM_SDK_CHECKSUM     WASM/embedded-WASM targets. Without a URL
                                      set (and no already-installed matching
                                      SDK), the WASM targets now FAIL rather
                                      than skip.
  CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false
                                      Demote embedded WASM to observational
                                      (default: blocking).
  CROSS_TARGET_SDK_INSTALL_ATTEMPTS  Bounded retry attempts for the SDK
                                      install (default 3).
  CROSS_TARGET_SDK_INSTALL_BACKOFF   Seconds between install attempts
                                      (default 3).
EOF
}

# ---------------------------------------------------------------------------
# Function classification (enforced by --self-test, see the partition and coverage
# checks in run_self_test). Every function in this file is either COVERED (named in
# the self-test's own source), EXEMPT (named here with a reason), or harness
# (assert_* / run_self_test, derived). "Covered" means REFERENCED by the self-test,
# not "executed": print_log_tail really runs during the ladder scenarios yet is exempt,
# because only swift_sdk_install_retry names it.
# ---------------------------------------------------------------------------

SELF_TEST_COVERED=(
  usage
  swift_version_key
  emit_target_line
  scheme_for_package
  scheme_in_list
  count_blocking_failures
  build_package_summary
  build_overall_summary
  parse_target_selection
  target_requested
  mark_not_requested
  resolve_wasm_sdk_id_from_list
  sdk_install_display
  wasm_kind_blocking
  wasm_skip_result
  wasm_install_precheck
  attempt_logfile
  run_scenario
  defined_functions
  is_harness_function
  self_test_body
  body_references_function
  swift_sdk_install_retry
  prepare_wasm_sdk
  scenario_ladder_recovers_after_two_failures
  scenario_ladder_exhausts_and_prints_every_tail
  scenario_asymmetric_drift_reports_truth
)

# name<TAB>justification. Parallel-array-free and bash 3.2-safe: no declare -A.
SELF_TEST_EXEMPT=(
  "print_log_tail	prints a file tail; runs via the ladder but is never named by the self-test"
  "print_ios_toolchain_metadata	shells out to xcode-select/xcrun"
  "resolve_ios_scheme_list	runs xcodebuild -list"
  "ios_scheme_status	reads the xcodebuild -list log captured by resolve_ios_scheme_list"
  "compile_ios_target	runs xcodebuild"
  "resolve_wasm_sdk_id	runs swift sdk list; the drift scenario's stub target"
  "run_swift_sdk_install	the toolchain call itself; the ladder's stub target"
  "compile_wasm_package_for_kind	runs swift build against an installed SDK"
  "process_package	orchestration over the compile steps"
  "main	top-level orchestration and exit code"
)

# Extract the X.Y.Z version from a `swift --version` first line.
swift_version_key() {
  printf '%s\n' "$1" | sed -n 's/.*[Ss]wift version \([0-9][0-9.]*\).*/\1/p' | head -n 1
}

# Emit one stable per-target line.
emit_target_line() {
  # target package result reason blocking
  echo "mode=cross_target_compile target=$1 package=$2 result=$3 reason=$4 blocking=$5"
}

# Map a package key to its SwiftPM scheme / build-target name. Pure.
scheme_for_package() {
  case "$1" in
    core) printf 'TextEngineCore' ;;
    providers) printf 'TextEngineReferenceProviders' ;;
    *) return 1 ;;
  esac
}

# Return success if SCHEME ($1) appears under the "Schemes:" block of an
# `xcodebuild -list` output read on stdin. Pure.
scheme_in_list() {
  local scheme="$1"
  awk 'f && NF { gsub(/^[[:space:]]+/, ""); print } /Schemes:/ { f = 1 }' | grep -qx "$scheme"
}

# Count blocking failures from "result:blocking" pairs.
count_blocking_failures() {
  local n=0 pair result blocking
  for pair in "$@"; do
    result="${pair%%:*}"
    blocking="${pair##*:}"
    if [[ "$result" == "fail" && "$blocking" == "true" ]]; then
      n=$((n + 1))
    fi
  done
  printf '%s' "$n"
}

# Assemble one per-package summary line.
build_package_summary() {
  # package ios_device ios_simulator wasm wasm_embedded
  echo "mode=cross_target_compile_summary package=$1 ios_device=$2 ios_simulator=$3 wasm=$4 wasm_embedded=$5"
}

# Assemble the overall aggregate line.
build_overall_summary() {
  # blocking_failures exit_code
  echo "mode=cross_target_compile_overall blocking_failures=$1 exit=$2"
}

parse_target_selection() {
  case "$1" in
    all|ios|wasm)
      SELECTED_TARGETS="$1"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

target_requested() {
  local group="$1"
  case "$SELECTED_TARGETS" in
    all) return 0 ;;
    ios) [[ "$group" == "ios" ]] ;;
    wasm) [[ "$group" == "wasm" ]] ;;
    *) return 1 ;;
  esac
}

mark_not_requested() {
  LAST_RESULT="skipped"
  LAST_REASON="not_requested"
  LAST_BLOCKING="false"
}

# Resolve a Swift SDK id from `swift sdk list` text on stdin, matching the
# version and target kind ("wasm" or "wasm_embedded"). Pure: covered by
# --self-test. SDK ids contain no spaces, so lines containing spaces (headers or
# other noise) are skipped.
resolve_wasm_sdk_id_from_list() {
  local version="$1" kind="$2" line trimmed
  [[ -z "$version" ]] && return 1
  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$trimmed" ]] && continue
    case "$trimmed" in *" "*) continue ;; esac
    case "$kind" in
      wasm_embedded)
        if [[ "$trimmed" == *"$version"* && "$trimmed" == *wasm* && "$trimmed" == *embedded* ]]; then
          printf '%s' "$trimmed"
          return 0
        fi
        ;;
      wasm)
        if [[ "$trimmed" == *"$version"* && "$trimmed" == *wasm* && "$trimmed" != *embedded* ]]; then
          printf '%s' "$trimmed"
          return 0
        fi
        ;;
    esac
  done
  return 1
}

# Pure: the `swift sdk install` argument string, with --checksum appended iff a
# checksum is supplied. Covered by --self-test. (url/checksum contain no spaces.)
sdk_install_display() {
  local url="$1" checksum="$2"
  if [[ -n "$checksum" ]]; then
    printf 'sdk install %s --checksum %s' "$url" "$checksum"
  else
    printf 'sdk install %s' "$url"
  fi
}

# Pure: is this WASM kind blocking? `wasm` always is; `wasm_embedded` blocks by
# default but can be demoted to observational via env (Decision 1's fallback
# ladder -- a one-flag flip, not new code). Covered by --self-test.
wasm_kind_blocking() {
  case "$1" in
    wasm) printf 'true' ;;
    wasm_embedded)
      if [[ "${CROSS_TARGET_WASM_EMBEDDED_BLOCKING:-true}" == "false" ]]; then
        printf 'false'
      else
        printf 'true'
      fi
      ;;
    *)
      # Fail CLOSED. Returning a non-zero exit instead would be WORSE than the `false`
      # this replaces: the sole caller is `LAST_BLOCKING="$(wasm_kind_blocking "$kind")"`
      # and this script has no `set -e`, so the error is swallowed and LAST_BLOCKING
      # becomes "" -- which wasm_skip_result reads as non-blocking and
      # count_blocking_failures never counts. `false` at least PRINTS blocking=false in
      # the target line; "" prints an empty field and is equally uncounted. The hard
      # exit for an unknown kind lives at the dispatch sites below, where it is not
      # inside a command substitution and can actually propagate.
      echo "warn=unknown_wasm_kind fn=wasm_kind_blocking kind=$1 defaulting=blocking" >&2
      printf 'true'
      ;;
  esac
}

# Pure: given a provisioning skip reason (may be empty) and the kind's blocking
# flag, the per-target result. Empty reason => "" (caller proceeds to compile).
# Non-empty on a blocking kind => "fail" (fail-closed: a gate that cannot fail is
# not a gate). Non-empty on an observational kind => "skipped". Covered by
# --self-test.
wasm_skip_result() {
  local skip="$1" blocking="$2"
  if [[ -z "$skip" ]]; then
    printf ''
  elif [[ "$blocking" == "true" ]]; then
    printf 'fail'
  else
    printf 'skipped'
  fi
}

# Decide what prepare_wasm_sdk should do for a kind BEFORE touching the network.
# Prints one of:
#   ""                              -> proceed to a real install attempt
#   "sdk_unavailable"                -> no URL configured; nothing to install
#   "sdk_unresolved_after_install"   -> the bundle IS installed (recorded_state ==
#                                       bundle_installed_ok) but this kind's id still
#                                       did not resolve; reinstalling cannot help
#   "<recorded state>"               -> the shared bundle already failed definitively;
#                                       short-circuit with the SAME reason the first
#                                       kind reported
#
# Both WASM kinds come from ONE swift.org bundle and prepare_wasm_sdk runs per kind.
# Once that bundle has definitively failed -- whether the install failed or it installed
# but yielded no resolvable id -- the second kind must not burn a second bounded-retry
# ladder against it, and must report the same reason, so the log reads as one fault. A
# bundle that installed SUCCESSFULLY is also recorded (WASM_BUNDLE_STATE=bundle_installed_ok)
# so an asymmetric-drift second kind reports the truth instead of re-running the ladder
# and claiming a fabricated install failure.
wasm_install_precheck() {
  local url="$1" recorded_state="$2"
  if [[ -z "$url" ]]; then
    printf 'sdk_unavailable'
  elif [[ "$recorded_state" == "bundle_installed_ok" ]]; then
    # The bundle IS installed and this kind's id still did not resolve. Reinstalling
    # cannot help and would report the wrong reason: the state describes the BUNDLE,
    # this return value describes the KIND.
    printf 'sdk_unresolved_after_install'
  elif [[ -n "$recorded_state" ]]; then
    printf '%s' "$recorded_state"
  fi
}

# Per-attempt install log path. Pure: naming is self-tested rather than inlined in
# the retry loop.
attempt_logfile() {
  printf '%s.attempt-%s' "$1" "$2"
}

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

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

assert_equal() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "self_test=fail label=$label expected=$expected actual=$actual"
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

assert_resolver_missing() {
  local list="$1" version="$2" kind="$3" label="$4"
  if printf '%s\n' "$list" | resolve_wasm_sdk_id_from_list "$version" "$kind" >/dev/null; then
    echo "self_test=fail label=$label expected=missing actual=found"
    exit 1
  fi
}

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if ! printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
    echo "self_test=fail label=$label expected_substring=$needle"
    printf '%s\n' "$haystack"
    exit 1
  fi
}

assert_file_exists() {
  local path="$1" label="$2"
  if [[ ! -f "$path" ]]; then
    echo "self_test=fail label=$label expected=file_exists actual=missing path=$path"
    exit 1
  fi
}

# Run a scenario function in a SUBSHELL so a stub override cannot leak into
# neighbouring cases -- and propagate its status, because the script runs under
# `set -uo pipefail` with no `set -e`: an `exit 1` from assert_* inside `( ... )`
# ends only the subshell. Never call a scenario bare.
run_scenario() {
  local name="$1"
  ( "$name" ) || exit 1
}

# The ladder recovers on the third attempt. Each attempt must leave its OWN log:
# with one shared logfile the first two attempts' output is overwritten and lost.
scenario_ladder_recovers_after_two_failures() {
  local logfile="${SELF_TEST_TMP_ROOT}/recover.log"
  local counter="${SELF_TEST_TMP_ROOT}/recover.count"
  local status
  CROSS_TARGET_SDK_INSTALL_BACKOFF=0
  # Pinned, not inherited: this scenario's stub recovers on attempt 3, so an
  # ambient CROSS_TARGET_SDK_INSTALL_ATTEMPTS (e.g. a developer's shell export set
  # to 2) would exhaust the ladder before recovery and fail this scenario for a
  # reason that has nothing to do with the code under test. A hermetic scenario
  # must not read values it does not set itself.
  CROSS_TARGET_SDK_INSTALL_ATTEMPTS=3
  printf '0' > "$counter"
  run_swift_sdk_install() {
    local n
    n=$(( $(cat "$counter") + 1 ))
    printf '%s' "$n" > "$counter"
    echo "stub attempt ${n}"
    [[ "$n" -ge 3 ]]
  }
  swift_sdk_install_retry http://example.invalid/b.artifactbundle "" "$logfile" recover >/dev/null
  status=$?
  assert_equal "0" "$status" "ladder_recover_status"
  assert_equal "3" "$(cat "$counter")" "ladder_recover_attempts"
  assert_file_exists "$(attempt_logfile "$logfile" 1)" "ladder_recover_attempt1_log"
  assert_file_exists "$(attempt_logfile "$logfile" 2)" "ladder_recover_attempt2_log"
  assert_equal "stub attempt 1" "$(cat "$(attempt_logfile "$logfile" 1)")" \
    "ladder_recover_attempt1_content"
  assert_equal "stub attempt 3" "$(cat "$(attempt_logfile "$logfile" 3)")" \
    "ladder_recover_attempt3_content"
}

# Every attempt fails: the ladder returns 1 and prints one labelled tail PER ATTEMPT,
# so a hosted failure shows all three, not just the last.
scenario_ladder_exhausts_and_prints_every_tail() {
  local logfile="${SELF_TEST_TMP_ROOT}/exhaust.log"
  local counter="${SELF_TEST_TMP_ROOT}/exhaust.count"
  local out status
  CROSS_TARGET_SDK_INSTALL_BACKOFF=0
  # Pinned, not inherited: this scenario asserts exactly 3 exhausted attempts, so
  # an ambient CROSS_TARGET_SDK_INSTALL_ATTEMPTS must not be allowed to change that
  # count out from under the assertion. A hermetic scenario must not read values
  # it does not set itself.
  CROSS_TARGET_SDK_INSTALL_ATTEMPTS=3
  printf '0' > "$counter"
  run_swift_sdk_install() {
    local n
    n=$(( $(cat "$counter") + 1 ))
    printf '%s' "$n" > "$counter"
    echo "stub failure ${n}"
    return 1
  }
  out="$(swift_sdk_install_retry http://example.invalid/b.artifactbundle "" "$logfile" exhaust 2>/dev/null)"
  status=$?
  assert_equal "1" "$status" "ladder_exhaust_status"
  assert_equal "3" "$(cat "$counter")" "ladder_exhaust_attempts"
  assert_equal "3" "$(printf '%s\n' "$out" | grep -c 'log tail (last')" \
    "ladder_exhaust_tail_count"
  # NOTE (brief deviation, see task-3-report.md): print_log_tail emits a MATCHING
  # pair of banner lines -- "<label> log tail (last N lines)" and "end <label> log
  # tail" -- so an un-anchored 'exhaust-attempt-2 log tail' matches BOTH lines
  # (actual=2), never 1. Anchored on the same '(last' suffix the sibling
  # assertion above already uses, so it counts the start banner only.
  assert_equal "1" "$(printf '%s\n' "$out" | grep -c 'exhaust-attempt-2 log tail (last')" \
    "ladder_exhaust_attempt2_label"
}

# The D-1 defect, end to end. The bundle installs for kind `wasm` and then provides
# only that kind's id; `wasm_embedded` must report the truth WITHOUT a second install.
# The install stub fails on any call after the first, exactly as a real
# `swift sdk install` does against an already-installed bundle.
scenario_asymmetric_drift_reports_truth() {
  local counter="${SELF_TEST_TMP_ROOT}/drift.count"
  local out
  CROSS_TARGET_SDK_INSTALL_BACKOFF=0
  CROSS_TARGET_WASM_SDK_URL="http://example.invalid/b.artifactbundle"
  CROSS_TARGET_WASM_SDK_CHECKSUM="deadbeef"
  SWIFT_VERSION="6.2.1"
  WASM_BUNDLE_STATE=""
  printf '0' > "$counter"
  resolve_wasm_sdk_id() {
    # Nothing resolves before an install; afterwards the bundle yields the
    # non-embedded id only -- asymmetric drift.
    [[ "$(cat "$counter")" -ge 1 ]] || return 1
    [[ "$2" == "wasm" ]] || return 1
    printf 'swift-6.2.1-RELEASE_wasm'
  }
  run_swift_sdk_install() {
    local n
    n=$(( $(cat "$counter") + 1 ))
    printf '%s' "$n" > "$counter"
    echo "stub install ${n}"
    [[ "$n" -eq 1 ]]
  }
  prepare_wasm_sdk wasm "${SELF_TEST_TMP_ROOT}/drift-wasm.log" >/dev/null 2>&1
  assert_equal "" "$WASM_SKIP_WASM" "drift_first_kind_succeeds"
  assert_equal "bundle_installed_ok" "$WASM_BUNDLE_STATE" "drift_state_recorded"
  # NOTE (Task 4 deviation from the brief's literal `out="$(prepare_wasm_sdk ... 2>&1)"`):
  # command substitution forks a subshell, so prepare_wasm_sdk's global-variable side
  # effect (WASM_SKIP_WASM_EMBEDDED, set below) would never reach this scope and the
  # very next assertion could never pass. Capture via a temp file instead so the call
  # runs in THIS shell and both the global var and the printed diagnostic survive.
  prepare_wasm_sdk wasm_embedded "${SELF_TEST_TMP_ROOT}/drift-embedded.log" \
    > "${SELF_TEST_TMP_ROOT}/drift-embedded.out" 2>&1
  out="$(cat "${SELF_TEST_TMP_ROOT}/drift-embedded.out")"
  assert_equal "sdk_unresolved_after_install" "$WASM_SKIP_WASM_EMBEDDED" "drift_second_kind_reason"
  assert_equal "1" "$(cat "$counter")" "drift_single_install"
  assert_contains "reason=bundle_installed_id_unresolved" "$out" "drift_message_truthful"
}

run_self_test() {
  # Fail CLOSED if mktemp itself fails: under `set -uo pipefail` (no `set -e`) an
  # unchecked `mktemp -d` failure leaves SELF_TEST_TMP_ROOT="". On macOS that still
  # fails safely later (writes to "/" are denied), but in a root-run container (e.g.
  # hosted CI) an empty root resolves to the filesystem root and every scenario
  # silently writes stray files there while still reporting self_test=pass -- a
  # check that cannot fail is not a check. The `|| SELF_TEST_TMP_ROOT=""` is
  # load-bearing: without it, `set -u`-adjacent strictness aside, a failing command
  # substitution's own exit status would otherwise not gate anything, since this
  # script runs without `set -e`.
  SELF_TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cross-target-self-test.XXXXXX")" || SELF_TEST_TMP_ROOT=""
  [[ -d "$SELF_TEST_TMP_ROOT" ]] || { echo "self_test=fail label=tmp_root_unavailable"; exit 1; }
  trap 'rm -rf "$SELF_TEST_TMP_ROOT"' EXIT

  local clean_list="swift-6.1.2-RELEASE_wasm
swift-6.1.2-RELEASE_wasm-embedded"
  local noisy_list="Installed Swift SDKs:
  swift-6.1.2-RELEASE_wasm
  swift-6.1.2-RELEASE_wasm-embedded
  6.0.3-RELEASE-ubuntu24.04_aarch64
some descriptive header with spaces"
  local scheme_list="Information about workspace \"SwiftTextEngine\":
    Schemes:
        TextEngineCore
        TextEngineReferenceProviders
        ViewportBenchmarks"
  assert_equal "6.1.2" \
    "$(swift_version_key 'Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)')" \
    "swift_version_key_apple"
  assert_equal "6.2.1" \
    "$(swift_version_key 'Swift version 6.2.1 (swift-6.2.1-RELEASE)')" \
    "swift_version_key_oss"

  # package -> scheme/target name mapping
  assert_equal "TextEngineCore" "$(scheme_for_package core)" "scheme_for_package_core"
  assert_equal "TextEngineReferenceProviders" "$(scheme_for_package providers)" "scheme_for_package_providers"
  assert_command_failure "scheme_for_package_unknown" scheme_for_package bogus

  # scheme membership in an xcodebuild -list block (stdin filter -> yes/no)
  assert_equal "yes" \
    "$(printf '%s\n' "$scheme_list" | scheme_in_list TextEngineCore && echo yes || echo no)" \
    "scheme_in_list_core"
  assert_equal "yes" \
    "$(printf '%s\n' "$scheme_list" | scheme_in_list TextEngineReferenceProviders && echo yes || echo no)" \
    "scheme_in_list_providers"
  assert_equal "no" \
    "$(printf '%s\n' "$scheme_list" | scheme_in_list NopeScheme && echo yes || echo no)" \
    "scheme_in_list_missing"

  # blocking-failure count over the full two-package pair set
  assert_equal "0" \
    "$(count_blocking_failures pass:true pass:true skipped:false skipped:false pass:true pass:true skipped:false skipped:false)" \
    "two_package_clean"
  assert_equal "1" \
    "$(count_blocking_failures pass:true pass:true skipped:false skipped:false fail:true pass:true skipped:false skipped:false)" \
    "two_package_providers_ios_fail"
  assert_equal "2" \
    "$(count_blocking_failures fail:true pass:true skipped:false skipped:false fail:true pass:true skipped:false skipped:false)" \
    "two_package_both_ios_device_fail"

  # per-target lines now carry package=
  assert_equal "mode=cross_target_compile target=ios_device package=core result=pass reason=none blocking=true" \
    "$(emit_target_line ios_device core pass none true)" "emit_line"
  assert_equal "mode=cross_target_compile target=wasm package=providers result=skipped reason=sdk_unavailable blocking=false" \
    "$(emit_target_line wasm providers skipped sdk_unavailable false)" "emit_skip_line"

  # per-package summary + overall aggregate
  assert_equal "mode=cross_target_compile_summary package=core ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped" \
    "$(build_package_summary core pass pass skipped skipped)" "summary_core"
  assert_equal "mode=cross_target_compile_summary package=providers ios_device=fail ios_simulator=pass wasm=skipped wasm_embedded=skipped" \
    "$(build_package_summary providers fail pass skipped skipped)" "summary_providers_fail"
  assert_equal "mode=cross_target_compile_overall blocking_failures=0 exit=0" \
    "$(build_overall_summary 0 0)" "overall_clean"
  assert_equal "mode=cross_target_compile_overall blocking_failures=1 exit=1" \
    "$(build_overall_summary 1 1)" "overall_fail"

  SELECTED_TARGETS="all"
  parse_target_selection all
  assert_command_success "all_selects_ios" target_requested ios
  assert_command_success "all_selects_wasm" target_requested wasm
  parse_target_selection ios
  assert_command_success "ios_selects_ios" target_requested ios
  assert_command_failure "ios_skips_wasm" target_requested wasm
  parse_target_selection wasm
  assert_command_failure "wasm_skips_ios" target_requested ios
  assert_command_success "wasm_selects_wasm" target_requested wasm
  assert_command_failure "invalid_target_selection" parse_target_selection ios,wasm
  mark_not_requested
  assert_equal "skipped" "$LAST_RESULT" "not_requested_result"
  assert_equal "not_requested" "$LAST_REASON" "not_requested_reason"
  assert_equal "false" "$LAST_BLOCKING" "not_requested_blocking"
  assert_equal "0" "$(count_blocking_failures skipped:false)" "not_requested_not_blocking"
  assert_equal "swift-6.1.2-RELEASE_wasm" \
    "$(printf '%s\n' "$clean_list" | resolve_wasm_sdk_id_from_list 6.1.2 wasm)" "resolve_clean_wasm"
  assert_equal "swift-6.1.2-RELEASE_wasm-embedded" \
    "$(printf '%s\n' "$clean_list" | resolve_wasm_sdk_id_from_list 6.1.2 wasm_embedded)" "resolve_clean_embedded"
  assert_equal "swift-6.1.2-RELEASE_wasm" \
    "$(printf '%s\n' "$noisy_list" | resolve_wasm_sdk_id_from_list 6.1.2 wasm)" "resolve_noisy_wasm"
  assert_equal "swift-6.1.2-RELEASE_wasm-embedded" \
    "$(printf '%s\n' "$noisy_list" | resolve_wasm_sdk_id_from_list 6.1.2 wasm_embedded)" "resolve_noisy_embedded"
  assert_resolver_missing "$clean_list" 9.9.9 wasm "resolve_missing_version"
  assert_resolver_missing "$clean_list" 6.1.2 wasm_embedded_typo "resolve_missing_kind"
  assert_resolver_missing "$clean_list" "" wasm "resolve_empty_version"

  # Task 1 — install arg builder: --checksum appended iff a checksum is supplied
  assert_equal "sdk install http://b --checksum abc123" \
    "$(sdk_install_display http://b abc123)" "install_display_with_checksum"
  assert_equal "sdk install http://b" \
    "$(sdk_install_display http://b "")" "install_display_without_checksum"

  # Task 2 — per-kind blocking flag (the fallback ladder is a config flip)
  assert_equal "true" "$(wasm_kind_blocking wasm)" "wasm_blocks"
  # Pinned to the default explicitly, not inherited: an ambient
  # CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false in the caller's shell would otherwise
  # flip this assertion's expected outcome for a reason unrelated to the code
  # under test. A hermetic scenario must not read values it does not set itself.
  assert_equal "true" \
    "$(CROSS_TARGET_WASM_EMBEDDED_BLOCKING=true wasm_kind_blocking wasm_embedded)" \
    "embedded_blocks_by_default"
  assert_equal "false" \
    "$(CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false wasm_kind_blocking wasm_embedded)" \
    "embedded_ladder_demotes_to_observational"
  # Slice 47 (P3 #3) — an unknown kind must fail CLOSED. wasm_kind_blocking returns a
  # VALUE, not a non-zero exit, because its sole caller,
  # LAST_BLOCKING="$(wasm_kind_blocking "$kind")", runs under no `set -e`: an erroring
  # helper there would leave LAST_BLOCKING="" -- read as non-blocking by
  # wasm_skip_result and never counted by count_blocking_failures, quieter than the bug
  # it replaces. assert_equal runs none of this itself: `$(...)` expands at the call
  # site before assert_equal is ever invoked, so it only compares two already-resolved
  # strings and can't see an exit status -- a helper that errors while still printing
  # "true" would pass here unnoticed.
  assert_equal "true" "$(wasm_kind_blocking bogus_kind 2>/dev/null)" "unknown_kind_blocks"
  # Task 2 — fail-closed: a provisioning skip on a blocking kind is a FAIL
  assert_equal "" "$(wasm_skip_result "" true)" "no_skip_proceeds_to_compile"
  assert_equal "fail" "$(wasm_skip_result sdk_unavailable true)" "skip_on_blocking_is_fail"
  assert_equal "skipped" "$(wasm_skip_result sdk_unavailable false)" "skip_on_observational_is_skip"
  # Slice 47 (P3 #2, #4) — the shared-bundle precheck, now a PURE helper so the
  # short-circuit is reachable from --self-test at all. Slice 46 could only exercise it
  # by a live run with a bogus URL.
  assert_equal "sdk_unavailable" "$(wasm_install_precheck "" "")" "precheck_no_url"
  assert_equal "" "$(wasm_install_precheck http://b "")" "precheck_proceeds"
  assert_equal "sdk_install_failed" \
    "$(wasm_install_precheck http://b sdk_install_failed)" \
    "precheck_short_circuits_install_failure"
  # The P3 #2 fix proper: the DRIFT path short-circuits with ITS OWN reason. Before
  # this, the second kind re-ran the whole ladder and could report a different reason
  # than the first, reading as two unrelated faults instead of one.
  assert_equal "sdk_unresolved_after_install" \
    "$(wasm_install_precheck http://b sdk_unresolved_after_install)" \
    "precheck_short_circuits_drift_with_same_reason"
  # No URL wins over a recorded failure: with nothing configured to install, the
  # actionable reason is the missing configuration.
  assert_equal "sdk_unavailable" \
    "$(wasm_install_precheck "" sdk_install_failed)" "precheck_no_url_precedence"
  assert_equal "sdk_unresolved_after_install" \
    "$(wasm_install_precheck http://b bundle_installed_ok)" \
    "precheck_installed_bundle_reports_unresolved"
  # Task 3 — per-attempt install log naming
  assert_equal "/tmp/x.log.attempt-2" "$(attempt_logfile /tmp/x.log 2)" "attempt_logfile_path"
  # Task 2 — WASM pairs now count toward blocking failures (a fail counts; a
  # demoted/observational embedded skip does not). Pair order is 2 packages x
  # {ios_device, ios_simulator, wasm, wasm_embedded}.
  assert_equal "1" \
    "$(count_blocking_failures pass:true pass:true fail:true pass:true pass:true pass:true pass:true pass:true)" \
    "wasm_fail_counts"
  assert_equal "0" \
    "$(count_blocking_failures pass:true pass:true pass:true skipped:false pass:true pass:true pass:true skipped:false)" \
    "wasm_embedded_demoted_not_counted"

  run_scenario scenario_ladder_recovers_after_two_failures
  run_scenario scenario_ladder_exhausts_and_prints_every_tail
  run_scenario scenario_asymmetric_drift_reports_truth

  # --- classification (D-6) ---
  # The partition is only as strong as the detector underneath it: a declaration form
  # defined_functions cannot see is a function that escapes classification silently,
  # with self_test=pass. Pin every form bash accepts at top level, and pin the
  # exclusion of INDENTED definitions -- the scenario stubs above are nested function
  # definitions that must stay invisible to the partition. Built with printf, not a
  # heredoc, because a column-0 `}` inside run_self_test would terminate
  # self_test_body's extraction early and silently truncate the coverage check.
  local fixture="${SELF_TEST_TMP_ROOT}/decl-forms.sh"
  printf '%s\n' \
    'plain_form() {' '  :' '}' \
    'nospace_form(){' '  :' '}' \
    'spaced_form ()  {' '  :' '}' \
    'digit_form2() {' '  :' '}' \
    'Upper_Form() {' '  :' '}' \
    'function keyword_form {' '  :' '}' \
    'function keyword_paren_form() {' '  :' '}' \
    'outer_form() {' '  indented_stub_form() {' '    :' '  }' '}' \
    > "$fixture"
  assert_equal \
    "plain_form nospace_form spaced_form digit_form2 Upper_Form keyword_form keyword_paren_form outer_form" \
    "$(defined_functions "$fixture" | tr '\n' ' ' | sed 's/ *$//')" \
    "defined_functions_sees_every_declaration_form"

  local script_path defined body fn entry name classified
  script_path="${BASH_SOURCE[0]}"
  defined="$(defined_functions "$script_path")"
  body="$(self_test_body "$script_path")"

  # Direction 1: every defined function is classified.
  for fn in $defined; do
    if is_harness_function "$fn"; then continue; fi
    classified=0
    for name in ${SELF_TEST_COVERED[@]+"${SELF_TEST_COVERED[@]}"}; do
      [[ "$name" == "$fn" ]] && classified=1
    done
    for entry in ${SELF_TEST_EXEMPT[@]+"${SELF_TEST_EXEMPT[@]}"}; do
      [[ "${entry%%$'\t'*}" == "$fn" ]] && classified=1
    done
    assert_equal "1" "$classified" "classified_${fn}"
  done

  # Direction 2: no phantom names, and every exempt entry carries a justification.
  for name in ${SELF_TEST_COVERED[@]+"${SELF_TEST_COVERED[@]}"}; do
    assert_function_defined "$name" "$defined" "covered_defined_${name}"
  done
  for entry in ${SELF_TEST_EXEMPT[@]+"${SELF_TEST_EXEMPT[@]}"}; do
    assert_function_defined "${entry%%$'\t'*}" "$defined" "exempt_defined_${entry%%$'\t'*}"
    if [[ "$entry" != *$'\t'* || -z "${entry#*$'\t'}" ]]; then
      echo "self_test=fail label=exempt_justified_${entry} expected=justification actual=none"
      exit 1
    fi
  done

  # Coverage: every covered function is really referenced by the self-test's source.
  for name in ${SELF_TEST_COVERED[@]+"${SELF_TEST_COVERED[@]}"}; do
    if ! body_references_function "$name" "$body"; then
      echo "self_test=fail label=covered_but_unreferenced fn=$name"
      exit 1
    fi
  done

  # usage must keep documenting the flag this whole mechanism hangs on. The check is
  # the RIGHT side of the pipe, so the pipeline's status is the check's status.
  if ! usage | grep -q -- '--self-test'; then
    echo "self_test=fail label=usage_documents_self_test expected=documented actual=missing"
    exit 1
  fi

  echo "self_test=pass"
}

# ---------------------------------------------------------------------------
# Compile steps (require a toolchain)
# ---------------------------------------------------------------------------

LAST_RESULT=""
LAST_REASON=""
LAST_BLOCKING=""
IOS_LIST_LOG=""
IOS_LIST_OK=""
WASM_SDK_ID_WASM=""
WASM_SKIP_WASM=""
WASM_SDK_ID_WASM_EMBEDDED=""
WASM_SKIP_WASM_EMBEDDED=""
WASM_BUNDLE_STATE=""
PAIRS=()

# Print the tail of a log file with clear delimiters, so failures are visible in
# the hosted CI log and usable for the verification record.
print_log_tail() {
  local label="$1" file="$2"
  echo "----- ${label} log tail (last ${TAIL_LINES} lines) -----"
  tail -n "$TAIL_LINES" "$file" 2>/dev/null || true
  echo "----- end ${label} log tail -----"
}

# Print iOS toolchain metadata so the hosted log carries the verification facts
# (selected Xcode, resolved SDKs). Reflects DEVELOPER_DIR if the job set it.
print_ios_toolchain_metadata() {
  echo "cross_target_developer_dir=${DEVELOPER_DIR:-unset}"
  echo "cross_target_xcode_select_path=$(xcode-select -p 2>/dev/null || echo unknown)"
  echo "cross_target_xcodebuild_version=$(xcodebuild -version 2>/dev/null | tr '\n' ';' | sed 's/;$//')"
  echo "cross_target_iphoneos_sdk_path=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo unknown)"
  echo "cross_target_iphoneos_sdk_version=$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo unknown)"
  echo "cross_target_iphonesimulator_sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || echo unknown)"
  echo "cross_target_iphonesimulator_sdk_version=$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || echo unknown)"
}

# Capture `xcodebuild -list` once; record whether it succeeded so per-scheme
# status can be derived without re-running it.
resolve_ios_scheme_list() {
  local listlog="$1"
  IOS_LIST_LOG="$listlog"
  if xcodebuild -list >"$listlog" 2>&1; then
    IOS_LIST_OK="true"
  else
    IOS_LIST_OK="false"
    print_log_tail "xcodebuild-list" "$listlog"
  fi
}

# Per-scheme status string: "" when resolvable, otherwise a failure reason.
# An xcodebuild-list infra failure is distinct from a missing scheme.
ios_scheme_status() {
  local scheme="$1"
  if [[ "$IOS_LIST_OK" != "true" ]]; then
    printf 'xcodebuild_list_failed'
    return
  fi
  if scheme_in_list "$scheme" <"$IOS_LIST_LOG"; then
    printf ''
  else
    printf 'scheme_unresolved'
  fi
}

compile_ios_target() {
  local target_name="$1" scheme="$2" destination="$3" logfile="$4" scheme_status
  LAST_BLOCKING="true"
  scheme_status="$(ios_scheme_status "$scheme")"
  echo "cross_target_command target=${target_name} scheme=${scheme} cmd=\"xcodebuild build -scheme ${scheme} -destination '${destination}'\""
  if [[ -n "$scheme_status" ]]; then
    LAST_RESULT="fail"
    LAST_REASON="$scheme_status"
    return
  fi
  if xcodebuild build -scheme "$scheme" -destination "$destination" -derivedDataPath "$DDP" >"$logfile" 2>&1; then
    LAST_RESULT="pass"
    LAST_REASON="none"
  else
    if grep -q "Unable to find a destination matching" "$logfile"; then
      LAST_REASON="destination_unavailable"
    else
      LAST_REASON="compile_failed"
    fi
    LAST_RESULT="fail"
    print_log_tail "${target_name}-build" "$logfile"
  fi
}

# Runtime wrapper: resolve an installed SDK id from live `swift sdk list` output,
# delegating the parsing to the self-tested pure function.
resolve_wasm_sdk_id() {
  local version="$1" kind="$2" list
  list="$(swift sdk list 2>/dev/null || true)"
  printf '%s\n' "$list" | resolve_wasm_sdk_id_from_list "$version" "$kind"
}

# The one toolchain call the ladder makes. Its ONLY purpose is to be replaceable:
# --self-test overrides it inside a scenario subshell. Exempt from coverage by
# construction -- it IS the process call.
run_swift_sdk_install() {
  swift "$@"
}

# Install a Swift SDK with a bounded retry. download.swift.org is now in the
# merge path, so a transient network error gets a few attempts before failing
# red. Echoes the measured install seconds (feeds the caching decision) on
# success. Not pure -- the toolchain call itself is stubbed via
# run_swift_sdk_install; the retry/backoff/logging logic IS exercised by
# --self-test.
swift_sdk_install_retry() {
  local url="$1" checksum="$2" logfile="$3" label="$4"
  local attempts="${CROSS_TARGET_SDK_INSTALL_ATTEMPTS:-3}"
  local backoff="${CROSS_TARGET_SDK_INSTALL_BACKOFF:-3}"
  local i=1 j=1 start end attempt_log
  local -a args=(sdk install "$url")
  [[ -n "$checksum" ]] && args+=(--checksum "$checksum")
  start=$(date +%s)
  while (( i <= attempts )); do
    attempt_log="$(attempt_logfile "$logfile" "$i")"
    if run_swift_sdk_install "${args[@]}" >"$attempt_log" 2>&1; then
      end=$(date +%s)
      echo "cross_target_sdk_install_seconds=$((end - start)) attempts=${i}"
      return 0
    fi
    echo "warn=sdk_install_attempt_failed attempt=${i}/${attempts}" >&2
    (( i < attempts )) && sleep "$backoff"
    i=$((i + 1))
  done
  # The ladder owns its own diagnostics: the caller cannot know how many attempts ran.
  while (( j < i )); do
    print_log_tail "${label}-attempt-${j}" "$(attempt_logfile "$logfile" "$j")"
    j=$((j + 1))
  done
  return 1
}

# Resolve (and if a URL is provided, install) the SDK for a kind once. Stores
# the resolved id and a skip reason ("" on success) in per-kind globals so both
# packages reuse the same SDK without re-installing.
prepare_wasm_sdk() {
  local kind="$1" logfile="$2" sdk_id="" url checksum skip="" precheck
  if [[ -z "$SWIFT_VERSION" ]]; then
    skip="swift_version_unresolved"
  elif ! sdk_id="$(resolve_wasm_sdk_id "$SWIFT_VERSION" "$kind")"; then
    # Both kinds come from ONE swift.org bundle: installing it produces both the
    # _wasm and _wasm-embedded ids, so both read the shared URL + checksum.
    # Happy path: the first kind installs; the second kind's resolve above
    # already succeeds (the bundle now provides its id too), so this branch is
    # never entered for it and no second install happens.
    # Drift path: the bundle installs successfully but yields only ONE kind's id.
    # WASM_BUNDLE_STATE (set below) records bundle_installed_ok even on success, so
    # the second kind's precheck reports the truth (sdk_unresolved_after_install)
    # WITHOUT a second install attempt against an already-installed bundle.
    # Failure path: once the shared bundle fails definitively -- install failure OR
    # installed-but-unresolvable -- WASM_BUNDLE_STATE (set below) short-
    # circuits the second kind to the SAME reason via wasm_install_precheck, instead
    # of burning a second full bounded-retry ladder against a host that just failed
    # the first one.
    url="${CROSS_TARGET_WASM_SDK_URL:-}"
    checksum="${CROSS_TARGET_WASM_SDK_CHECKSUM:-}"
    precheck="$(wasm_install_precheck "$url" "$WASM_BUNDLE_STATE")"
    if [[ -n "$precheck" ]]; then
      skip="$precheck"
      if [[ "$WASM_BUNDLE_STATE" == "bundle_installed_ok" ]]; then
        echo "cross_target_sdk_install_skipped target=${kind}" \
          "reason=bundle_installed_id_unresolved prior_state=${WASM_BUNDLE_STATE}"
      elif [[ "$precheck" != "sdk_unavailable" ]]; then
        echo "cross_target_sdk_install_skipped target=${kind}" \
          "reason=bundle_already_failed prior_reason=${precheck}"
      fi
    else
      echo "cross_target_command target=${kind} cmd=\"swift $(sdk_install_display "$url" "$checksum")\""
      if ! swift_sdk_install_retry "$url" "$checksum" "${logfile}.install" "${kind}-sdk-install"; then
        skip="sdk_install_failed"
        WASM_BUNDLE_STATE="sdk_install_failed"
      elif ! sdk_id="$(resolve_wasm_sdk_id "$SWIFT_VERSION" "$kind")"; then
        skip="sdk_unresolved_after_install"
        # Slice 47 (P3 #2): record THIS reason too. Slice 46 recorded only the
        # install failure, so the drift path let the second kind re-run a full
        # ladder against an already-installed SDK and report a different reason.
        WASM_BUNDLE_STATE="sdk_unresolved_after_install"
      else
        # Slice 51 (D-1): record SUCCESS as well. Without this the second kind sees an
        # empty state, reinstalls a bundle that is already present, and reports the
        # install failure instead of the truth.
        WASM_BUNDLE_STATE="bundle_installed_ok"
      fi
    fi
  fi
  case "$kind" in
    wasm)
      WASM_SDK_ID_WASM="${sdk_id:-}"
      WASM_SKIP_WASM="$skip"
      ;;
    wasm_embedded)
      WASM_SDK_ID_WASM_EMBEDDED="${sdk_id:-}"
      WASM_SKIP_WASM_EMBEDDED="$skip"
      ;;
    *)
      echo "error=unknown_wasm_kind fn=prepare_wasm_sdk kind=${kind}" >&2
      exit 1
      ;;
  esac
}

# Build one package for a WASM kind using the prepared SDK, with blocking
# status per-kind: wasm always blocks, wasm_embedded blocks by default but is
# demotable via CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false.
compile_wasm_package_for_kind() {
  local kind="$1" pkg="$2" package_target="$3" logfile="$4" sdk_id skip scratch_path result
  LAST_BLOCKING="$(wasm_kind_blocking "$kind")"
  case "$kind" in
    wasm) sdk_id="$WASM_SDK_ID_WASM"; skip="$WASM_SKIP_WASM" ;;
    wasm_embedded) sdk_id="$WASM_SDK_ID_WASM_EMBEDDED"; skip="$WASM_SKIP_WASM_EMBEDDED" ;;
    *)
      echo "error=unknown_wasm_kind fn=compile_wasm_package_for_kind kind=${kind}" >&2
      exit 1
      ;;
  esac
  result="$(wasm_skip_result "$skip" "$LAST_BLOCKING")"
  if [[ -n "$result" ]]; then
    LAST_RESULT="$result"      # fail (blocking kind) or skipped (observational kind)
    LAST_REASON="$skip"
    return
  fi
  scratch_path="${WORK}/swiftpm-${kind}-${pkg}"
  echo "cross_target_wasm_sdk_id target=${kind} package=${pkg} id=${sdk_id}"
  echo "cross_target_command target=${kind} package=${pkg} cmd=\"swift build --scratch-path ${scratch_path} --swift-sdk ${sdk_id} --target ${package_target}\""
  if swift build --scratch-path "$scratch_path" --swift-sdk "$sdk_id" --target "$package_target" >"$logfile" 2>&1; then
    LAST_RESULT="pass"
    LAST_REASON="none"
  else
    LAST_RESULT="fail"
    LAST_REASON="compile_failed"
    print_log_tail "${kind}-${pkg}-build" "$logfile"
  fi
}

# Compile every requested target for one package, append blocking pairs to
# PAIRS, emit per-target lines, and print the package summary line.
process_package() {
  local pkg="$1" scheme
  scheme="$(scheme_for_package "$pkg")"
  local ios_device_r ios_simulator_r wasm_r wasm_embedded_r

  if target_requested ios; then
    compile_ios_target ios_device "$scheme" 'generic/platform=iOS' "$WORK/ios_device_${pkg}.log"
  else
    mark_not_requested
  fi
  ios_device_r="$LAST_RESULT"
  PAIRS+=("${LAST_RESULT}:${LAST_BLOCKING}")
  emit_target_line ios_device "$pkg" "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"

  if target_requested ios; then
    compile_ios_target ios_simulator "$scheme" 'generic/platform=iOS Simulator' "$WORK/ios_simulator_${pkg}.log"
  else
    mark_not_requested
  fi
  ios_simulator_r="$LAST_RESULT"
  PAIRS+=("${LAST_RESULT}:${LAST_BLOCKING}")
  emit_target_line ios_simulator "$pkg" "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"

  if target_requested wasm; then
    compile_wasm_package_for_kind wasm "$pkg" "$scheme" "$WORK/wasm_${pkg}.log"
  else
    mark_not_requested
  fi
  wasm_r="$LAST_RESULT"
  PAIRS+=("${LAST_RESULT}:${LAST_BLOCKING}")
  emit_target_line wasm "$pkg" "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"

  if target_requested wasm; then
    compile_wasm_package_for_kind wasm_embedded "$pkg" "$scheme" "$WORK/wasm_embedded_${pkg}.log"
  else
    mark_not_requested
  fi
  wasm_embedded_r="$LAST_RESULT"
  PAIRS+=("${LAST_RESULT}:${LAST_BLOCKING}")
  emit_target_line wasm_embedded "$pkg" "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"

  build_package_summary "$pkg" "$ios_device_r" "$ios_simulator_r" "$wasm_r" "$wasm_embedded_r"
}

main() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/cross-target.XXXXXX")"
  DDP="$WORK/ddp"
  SWIFT_VERSION="$(swift_version_key "$(swift --version 2>&1 | head -n 1)")"
  echo "cross_target_swift_version=${SWIFT_VERSION:-unknown}"

  if target_requested ios; then
    print_ios_toolchain_metadata
    resolve_ios_scheme_list "$WORK/xcodebuild-list.log"
  fi
  if target_requested wasm; then
    prepare_wasm_sdk wasm "$WORK/wasm.sdk"
    prepare_wasm_sdk wasm_embedded "$WORK/wasm_embedded.sdk"
  fi

  local pkg
  for pkg in core providers; do
    process_package "$pkg"
  done

  local blocking_failures exit_code
  blocking_failures="$(count_blocking_failures "${PAIRS[@]}")"
  if [[ "$blocking_failures" -gt 0 ]]; then
    exit_code=1
  else
    exit_code=0
  fi
  build_overall_summary "$blocking_failures" "$exit_code"
  exit "$exit_code"
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test || exit 1
  exit 0
fi
if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--targets" ]]; then
  if [[ $# -ne 2 ]] || ! parse_target_selection "$2"; then
    usage
    exit 2
  fi
  shift 2
fi
if [[ $# -gt 0 ]]; then
  usage
  exit 2
fi
main
