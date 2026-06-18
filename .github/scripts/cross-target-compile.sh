#!/usr/bin/env bash
set -uo pipefail

# Cross-target compile helper for TextEngineCore (Slice 13).
# Compiles TextEngineCore for non-host targets and prints stable key-value lines.
#   iOS device + simulator: blocking, through the Swift package graph (xcodebuild).
#   WASM + embedded WASM: observational, via a Swift SDK matched to the runner
#   toolchain; skipped-with-record when no matching SDK can be provisioned.
# The exit code reflects only the blocking iOS results.

SCHEME="TextEngineCore"
PACKAGE_TARGET="TextEngineCore"
TAIL_LINES="${CROSS_TARGET_LOG_TAIL:-40}"
SELECTED_TARGETS="all"

usage() {
  cat <<'EOF'
Usage:
  cross-target-compile.sh
  cross-target-compile.sh --targets all|ios|wasm
  cross-target-compile.sh --self-test
EOF
}

# ---------------------------------------------------------------------------
# Pure helpers (covered by --self-test, no toolchain required)
# ---------------------------------------------------------------------------

# Extract the X.Y.Z version from a `swift --version` first line.
swift_version_key() {
  printf '%s\n' "$1" | sed -n 's/.*[Ss]wift version \([0-9][0-9.]*\).*/\1/p' | head -n 1
}

# Emit one stable per-target line.
emit_target_line() {
  # target result reason blocking
  echo "mode=cross_target_compile target=$1 result=$2 reason=$3 blocking=$4"
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

# Assemble the summary line.
build_summary() {
  # ios_device ios_simulator wasm wasm_embedded blocking_failures exit_code
  echo "mode=cross_target_compile_summary ios_device=$1 ios_simulator=$2 wasm=$3 wasm_embedded=$4 blocking_failures=$5 exit=$6"
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

run_self_test() {
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
  echo "self_test=pass"
}

# ---------------------------------------------------------------------------
# Compile steps (require a toolchain)
# ---------------------------------------------------------------------------

LAST_RESULT=""
LAST_REASON=""
LAST_BLOCKING=""
IOS_SCHEME_STATUS=""

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

# Resolve the package scheme once, distinguishing an xcodebuild-list infra
# failure from a genuinely missing scheme.
resolve_ios_scheme() {
  local listlog="$1"
  if ! xcodebuild -list >"$listlog" 2>&1; then
    IOS_SCHEME_STATUS="xcodebuild_list_failed"
    print_log_tail "xcodebuild-list" "$listlog"
    return
  fi
  if ! awk 'f && NF { gsub(/^[[:space:]]+/, ""); print } /Schemes:/ { f = 1 }' "$listlog" | grep -qx "$SCHEME"; then
    IOS_SCHEME_STATUS="scheme_unresolved"
    print_log_tail "xcodebuild-list" "$listlog"
    return
  fi
  IOS_SCHEME_STATUS=""
}

compile_ios_target() {
  local target_name="$1" destination="$2" logfile="$3"
  LAST_BLOCKING="true"
  echo "cross_target_command target=${target_name} cmd=\"xcodebuild build -scheme ${SCHEME} -destination '${destination}'\""
  if [[ -n "$IOS_SCHEME_STATUS" ]]; then
    LAST_RESULT="fail"
    LAST_REASON="$IOS_SCHEME_STATUS"
    return
  fi
  if xcodebuild build -scheme "$SCHEME" -destination "$destination" -derivedDataPath "$DDP" >"$logfile" 2>&1; then
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

compile_wasm_target() {
  local kind="$1" target_name="$2" logfile="$3" sdk_id url_var url
  LAST_BLOCKING="false"
  if [[ -z "$SWIFT_VERSION" ]]; then
    LAST_RESULT="skipped"
    LAST_REASON="swift_version_unresolved"
    return
  fi
  if ! sdk_id="$(resolve_wasm_sdk_id "$SWIFT_VERSION" "$kind")"; then
    if [[ "$kind" == "wasm_embedded" ]]; then
      url_var="CROSS_TARGET_WASM_EMBEDDED_SDK_URL"
    else
      url_var="CROSS_TARGET_WASM_SDK_URL"
    fi
    url="${!url_var:-}"
    if [[ -z "$url" ]]; then
      LAST_RESULT="skipped"
      LAST_REASON="sdk_unavailable"
      return
    fi
    echo "cross_target_command target=${target_name} cmd=\"swift sdk install ${url}\""
    if ! swift sdk install "$url" >"${logfile}.install" 2>&1; then
      LAST_RESULT="skipped"
      LAST_REASON="sdk_install_failed"
      print_log_tail "${target_name}-sdk-install" "${logfile}.install"
      return
    fi
    if ! sdk_id="$(resolve_wasm_sdk_id "$SWIFT_VERSION" "$kind")"; then
      LAST_RESULT="skipped"
      LAST_REASON="sdk_unresolved_after_install"
      return
    fi
  fi
  local scratch_path="${WORK}/swiftpm-${target_name}"
  echo "cross_target_wasm_sdk_id target=${target_name} id=${sdk_id}"
  echo "cross_target_command target=${target_name} cmd=\"swift build --scratch-path ${scratch_path} --swift-sdk ${sdk_id} --target ${PACKAGE_TARGET}\""
  if swift build --scratch-path "$scratch_path" --swift-sdk "$sdk_id" --target "$PACKAGE_TARGET" >"$logfile" 2>&1; then
    LAST_RESULT="pass"
    LAST_REASON="none"
  else
    LAST_RESULT="fail"
    LAST_REASON="compile_failed"
    print_log_tail "${target_name}-build" "$logfile"
  fi
}

main() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/cross-target.XXXXXX")"
  DDP="$WORK/ddp"
  SWIFT_VERSION="$(swift_version_key "$(swift --version 2>&1 | head -n 1)")"
  echo "cross_target_swift_version=${SWIFT_VERSION:-unknown}"

  if target_requested ios; then
    print_ios_toolchain_metadata
    resolve_ios_scheme "$WORK/xcodebuild-list.log"

    compile_ios_target ios_device 'generic/platform=iOS' "$WORK/ios_device.log"
    ios_device_result="$LAST_RESULT"
    ios_device_blocking="$LAST_BLOCKING"
    emit_target_line ios_device "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"

    compile_ios_target ios_simulator 'generic/platform=iOS Simulator' "$WORK/ios_simulator.log"
    ios_simulator_result="$LAST_RESULT"
    ios_simulator_blocking="$LAST_BLOCKING"
    emit_target_line ios_simulator "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"
  else
    mark_not_requested ios_device
    ios_device_result="$LAST_RESULT"
    ios_device_blocking="$LAST_BLOCKING"
    emit_target_line ios_device "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"

    mark_not_requested ios_simulator
    ios_simulator_result="$LAST_RESULT"
    ios_simulator_blocking="$LAST_BLOCKING"
    emit_target_line ios_simulator "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"
  fi

  if target_requested wasm; then
    compile_wasm_target wasm wasm "$WORK/wasm.log"
    wasm_result="$LAST_RESULT"
    wasm_blocking="$LAST_BLOCKING"
    emit_target_line wasm "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"

    compile_wasm_target wasm_embedded wasm_embedded "$WORK/wasm_embedded.log"
    wasm_embedded_result="$LAST_RESULT"
    wasm_embedded_blocking="$LAST_BLOCKING"
    emit_target_line wasm_embedded "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"
  else
    mark_not_requested wasm
    wasm_result="$LAST_RESULT"
    wasm_blocking="$LAST_BLOCKING"
    emit_target_line wasm "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"

    mark_not_requested wasm_embedded
    wasm_embedded_result="$LAST_RESULT"
    wasm_embedded_blocking="$LAST_BLOCKING"
    emit_target_line wasm_embedded "$LAST_RESULT" "$LAST_REASON" "$LAST_BLOCKING"
  fi

  local blocking_failures exit_code
  blocking_failures="$(count_blocking_failures \
    "${ios_device_result}:${ios_device_blocking}" \
    "${ios_simulator_result}:${ios_simulator_blocking}" \
    "${wasm_result}:${wasm_blocking}" \
    "${wasm_embedded_result}:${wasm_embedded_blocking}")"
  if [[ "$blocking_failures" -gt 0 ]]; then
    exit_code=1
  else
    exit_code=0
  fi
  build_summary "$ios_device_result" "$ios_simulator_result" "$wasm_result" "$wasm_embedded_result" "$blocking_failures" "$exit_code"
  exit "$exit_code"
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
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
