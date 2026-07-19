#!/usr/bin/env bash
set -uo pipefail

# Cross-target compile helper for TextEngineCore and TextEngineReferenceProviders.
# Compiles both packages for non-host targets and prints stable key-value lines
# carrying a package= field (core | providers).
#   iOS device + simulator: blocking, through the Swift package graph (xcodebuild).
#   WASM + embedded WASM: observational, via a Swift SDK matched to the runner
#   toolchain; skipped-with-record when no matching SDK can be provisioned.
# The exit code reflects only the blocking iOS results, across both packages.

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

  # Task 1 — install arg builder: --checksum appended iff a checksum is supplied
  assert_equal "sdk install http://b --checksum abc123" \
    "$(sdk_install_display http://b abc123)" "install_display_with_checksum"
  assert_equal "sdk install http://b" \
    "$(sdk_install_display http://b "")" "install_display_without_checksum"
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

# Install a Swift SDK with a bounded retry. download.swift.org is now in the
# merge path, so a transient network error gets a few attempts before failing
# red. Echoes the measured install seconds (feeds the caching decision) on
# success. Not pure -- exercised by the hosted spike, not --self-test.
swift_sdk_install_retry() {
  local url="$1" checksum="$2" logfile="$3"
  local attempts="${CROSS_TARGET_SDK_INSTALL_ATTEMPTS:-3}"
  local backoff="${CROSS_TARGET_SDK_INSTALL_BACKOFF:-3}"
  local i=1 start end
  local -a args=(sdk install "$url")
  [[ -n "$checksum" ]] && args+=(--checksum "$checksum")
  start=$(date +%s)
  while (( i <= attempts )); do
    if swift "${args[@]}" >"$logfile" 2>&1; then
      end=$(date +%s)
      echo "cross_target_sdk_install_seconds=$((end - start)) attempts=${i}"
      return 0
    fi
    echo "warn=sdk_install_attempt_failed attempt=${i}/${attempts}" >&2
    (( i < attempts )) && sleep "$backoff"
    i=$((i + 1))
  done
  return 1
}

# Resolve (and if a URL is provided, install) the SDK for a kind once. Stores
# the resolved id and a skip reason ("" on success) in per-kind globals so both
# packages reuse the same SDK without re-installing.
prepare_wasm_sdk() {
  local kind="$1" logfile="$2" sdk_id="" url checksum skip=""
  if [[ -z "$SWIFT_VERSION" ]]; then
    skip="swift_version_unresolved"
  elif ! sdk_id="$(resolve_wasm_sdk_id "$SWIFT_VERSION" "$kind")"; then
    # Both kinds come from ONE swift.org bundle: installing it produces both the
    # _wasm and _wasm-embedded ids, so both read the shared URL + checksum. The
    # first kind installs; the second resolves the already-installed id and does
    # not re-install.
    url="${CROSS_TARGET_WASM_SDK_URL:-}"
    checksum="${CROSS_TARGET_WASM_SDK_CHECKSUM:-}"
    if [[ -z "$url" ]]; then
      skip="sdk_unavailable"
    else
      echo "cross_target_command target=${kind} cmd=\"swift $(sdk_install_display "$url" "$checksum")\""
      if ! swift_sdk_install_retry "$url" "$checksum" "${logfile}.install"; then
        skip="sdk_install_failed"
        print_log_tail "${kind}-sdk-install" "${logfile}.install"
      elif ! sdk_id="$(resolve_wasm_sdk_id "$SWIFT_VERSION" "$kind")"; then
        skip="sdk_unresolved_after_install"
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
  esac
}

# Build one package for a WASM kind using the prepared SDK. Always non-blocking.
compile_wasm_package_for_kind() {
  local kind="$1" pkg="$2" package_target="$3" logfile="$4" sdk_id skip scratch_path
  LAST_BLOCKING="false"
  case "$kind" in
    wasm) sdk_id="$WASM_SDK_ID_WASM"; skip="$WASM_SKIP_WASM" ;;
    wasm_embedded) sdk_id="$WASM_SDK_ID_WASM_EMBEDDED"; skip="$WASM_SKIP_WASM_EMBEDDED" ;;
  esac
  if [[ -n "$skip" ]]; then
    LAST_RESULT="skipped"
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
