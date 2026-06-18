# Cross-Target Provider Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the hosted cross-target compile helper so it compiles both `TextEngineCore` and `TextEngineReferenceProviders` for iOS (blocking) and WASM (observational), mirroring the core's per-target enforcement.

**Architecture:** A single Bash helper, `.github/scripts/cross-target-compile.sh`, already compiles `TextEngineCore` per target and prints stable key-value lines. We parameterize its compile functions by package, loop over `(core, providers)` in `main()`, add a `package=` field to every output line, emit one summary line per package plus one overall aggregate line, and generalize iOS scheme resolution to check both schemes. The pure helpers are covered by `--self-test` (no toolchain); the compile orchestration is verified by a real iOS compile.

**Tech Stack:** Bash (`set -uo pipefail`, no associative arrays for portability), `xcodebuild` (iOS), `swift build --swift-sdk` (WASM), GitHub Actions YAML.

**Design reference:** `docs/superpowers/specs/2026-06-18-cross-target-provider-coverage-design.md`

---

## File Structure

- Modify: `.github/scripts/cross-target-compile.sh` — the whole change lives here (pure helpers, compile functions, `main()`, `--self-test`, header comment).
- Modify: `.github/workflows/swift-ci.yml` — rename two cross-target step names for accuracy (job `name:` contexts unchanged).
- Modify: `AGENTS.md` — package-layout note + CI section describe the two-package cross-target surface.
- Create: `docs/superpowers/verification/2026-06-18-cross-target-provider-coverage.md` — recorded commands + outputs + hosted run IDs.

The helper's responsibilities after this change:
- **Pure helpers** (self-tested): version parsing, package→scheme mapping, scheme-list membership, target-selection, WASM SDK id resolution, per-target line, per-package summary, overall summary, blocking-failure count.
- **Compile orchestration** (integration-tested): iOS scheme-list resolution, per-(target,package) iOS/WASM compiles, `main()` loop.

---

## Task 1: Rewrite `--self-test` to the new two-package contract (RED)

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh` (the `run_self_test` function)

This is the failing-test-first step. The new assertions reference pure helpers and output shapes that do not exist yet, so `--self-test` must fail.

- [ ] **Step 1: Replace the `run_self_test` body**

Replace the entire `run_self_test() { ... }` function with this version. It keeps the still-valid assertions (`swift_version_key`, target selection, `mark_not_requested`, WASM SDK resolver) and replaces the line/summary assertions with the new `package=` contract, plus new `scheme_for_package` and `scheme_in_list` assertions.

```bash
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
```

Note: the `scheme_in_list` assertions run the function in a subshell with stdin via `declare -f`, because `assert_command_success`/`assert_command_failure` run a command with arguments and `scheme_in_list` reads stdin. This keeps `scheme_in_list` itself a clean stdin filter.

- [ ] **Step 2: Run the self-test to verify it fails**

Run: `./.github/scripts/cross-target-compile.sh --self-test`
Expected: FAIL, exit status `1`. The first new assertion to fail prints a `self_test=fail label=...` line (for example `label=scheme_for_package_core` — the helper does not exist yet, so the command substitution is empty).

- [ ] **Step 3: Commit the red self-test**

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "test: assert two-package cross-target contract"
```

---

## Task 2: Implement the new pure helpers (GREEN for self-test)

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh` (pure helpers section)

- [ ] **Step 1: Replace `emit_target_line` to add the `package=` field**

Find:

```bash
# Emit one stable per-target line.
emit_target_line() {
  # target result reason blocking
  echo "mode=cross_target_compile target=$1 result=$2 reason=$3 blocking=$4"
}
```

Replace with:

```bash
# Emit one stable per-target line.
emit_target_line() {
  # target package result reason blocking
  echo "mode=cross_target_compile target=$1 package=$2 result=$3 reason=$4 blocking=$5"
}
```

- [ ] **Step 2: Add `scheme_for_package` next to `emit_target_line`**

Add this function immediately after `emit_target_line`:

```bash
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
```

- [ ] **Step 3: Replace `build_summary` with per-package and overall builders**

Find:

```bash
# Assemble the summary line.
build_summary() {
  # ios_device ios_simulator wasm wasm_embedded blocking_failures exit_code
  echo "mode=cross_target_compile_summary ios_device=$1 ios_simulator=$2 wasm=$3 wasm_embedded=$4 blocking_failures=$5 exit=$6"
}
```

Replace with:

```bash
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
```

- [ ] **Step 4: Run the self-test to verify it passes**

Run: `./.github/scripts/cross-target-compile.sh --self-test`
Expected: PASS, last line `self_test=pass`, exit status `0`.

- [ ] **Step 5: Commit the pure helpers**

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "feat: add per-package cross-target helpers"
```

---

## Task 3: Refactor the compile orchestration to loop over packages

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh` (top-level vars, state vars, iOS/WASM compile functions, `main`)

This task changes only compile orchestration; the pure helpers and `--self-test` stay green. It is verified by `bash -n`, `--self-test`, and a real iOS compile.

- [ ] **Step 1: Remove the now-unused single-package top-level vars**

Find:

```bash
SCHEME="TextEngineCore"
PACKAGE_TARGET="TextEngineCore"
TAIL_LINES="${CROSS_TARGET_LOG_TAIL:-40}"
SELECTED_TARGETS="all"
```

Replace with:

```bash
TAIL_LINES="${CROSS_TARGET_LOG_TAIL:-40}"
SELECTED_TARGETS="all"
```

- [ ] **Step 2: Replace the compile-state globals**

Find:

```bash
LAST_RESULT=""
LAST_REASON=""
LAST_BLOCKING=""
IOS_SCHEME_STATUS=""
```

Replace with:

```bash
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
```

- [ ] **Step 3: Replace `resolve_ios_scheme` with list-once + per-scheme status**

Find the whole `resolve_ios_scheme() { ... }` function:

```bash
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
```

Replace with:

```bash
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
```

- [ ] **Step 4: Replace `compile_ios_target` to take a scheme argument**

Find the whole `compile_ios_target() { ... }` function and replace it with:

```bash
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
```

- [ ] **Step 5: Replace `compile_wasm_target` with SDK-prepare + per-package build**

Find the whole `compile_wasm_target() { ... }` function and replace it with:

```bash
# Resolve (and if a URL is provided, install) the SDK for a kind once. Stores
# the resolved id and a skip reason ("" on success) in per-kind globals so both
# packages reuse the same SDK without re-installing.
prepare_wasm_sdk() {
  local kind="$1" logfile="$2" sdk_id="" url_var url skip=""
  if [[ -z "$SWIFT_VERSION" ]]; then
    skip="swift_version_unresolved"
  elif ! sdk_id="$(resolve_wasm_sdk_id "$SWIFT_VERSION" "$kind")"; then
    if [[ "$kind" == "wasm_embedded" ]]; then
      url_var="CROSS_TARGET_WASM_EMBEDDED_SDK_URL"
    else
      url_var="CROSS_TARGET_WASM_SDK_URL"
    fi
    url="${!url_var:-}"
    if [[ -z "$url" ]]; then
      skip="sdk_unavailable"
    else
      echo "cross_target_command target=${kind} cmd=\"swift sdk install ${url}\""
      if ! swift sdk install "$url" >"${logfile}.install" 2>&1; then
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
```

- [ ] **Step 6: Add `process_package` and replace `main`**

Find the whole `main() { ... }` function and replace it with `process_package` followed by the new `main`:

```bash
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
```

- [ ] **Step 7: Syntax-check and self-test**

Run: `bash -n .github/scripts/cross-target-compile.sh && ./.github/scripts/cross-target-compile.sh --self-test`
Expected: no syntax errors; last line `self_test=pass`, exit status `0`.

- [ ] **Step 8: Real iOS cross-compile (toolchain integration, macOS)**

Run: `./.github/scripts/cross-target-compile.sh --targets ios`
Expected:
- per-target lines for both packages, e.g.
  `mode=cross_target_compile target=ios_device package=core result=pass ...` and
  `... target=ios_device package=providers result=pass ...`;
- two summary lines: `... package=core ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped` and the same for `package=providers`;
- `mode=cross_target_compile_overall blocking_failures=0 exit=0`;
- exit status `0`.

If the providers scheme does not resolve, the `providers` iOS lines show `result=fail reason=scheme_unresolved` and the overall exit is `1` — investigate the SwiftPM scheme generation before continuing.

- [ ] **Step 9: Commit the orchestration refactor**

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "feat: compile reference providers in cross-target helper"
```

---

## Task 4: Rename the workflow cross-target step names

**Files:**
- Modify: `.github/workflows/swift-ci.yml:218`, `.github/workflows/swift-ci.yml:288`

The job `name:` contexts (`iOS cross-target compile`, `WASM cross-target observation`) are required and must NOT change. Only the inner step names change.

- [ ] **Step 1: Rename the iOS compile step**

Find:

```yaml
      - name: Compile TextEngineCore for iOS targets
```

Replace with:

```yaml
      - name: Compile cross-target packages for iOS
```

- [ ] **Step 2: Rename the WASM observation step**

Find:

```yaml
      - name: Observe TextEngineCore for WASM targets
```

Replace with:

```yaml
      - name: Observe cross-target packages for WASM
```

- [ ] **Step 3: Verify the required job names are untouched**

Run: `rg -n "name: iOS cross-target compile|name: WASM cross-target observation|name: Compile cross-target packages for iOS|name: Observe cross-target packages for WASM" .github/workflows/swift-ci.yml`
Expected: all four lines present — the two job contexts unchanged and the two renamed steps.

- [ ] **Step 4: Commit the workflow rename**

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: rename cross-target steps for two-package surface"
```

---

## Task 5: Update durable documentation

**Files:**
- Modify: `AGENTS.md` (package layout note + CI section)
- Modify: `.github/scripts/cross-target-compile.sh` (header comment)

- [ ] **Step 1: Update the helper's header comment**

Find:

```bash
# Cross-target compile helper for TextEngineCore (Slice 13).
# Compiles TextEngineCore for non-host targets and prints stable key-value lines.
#   iOS device + simulator: blocking, through the Swift package graph (xcodebuild).
#   WASM + embedded WASM: observational, via a Swift SDK matched to the runner
#   toolchain; skipped-with-record when no matching SDK can be provisioned.
# The exit code reflects only the blocking iOS results.
```

Replace with:

```bash
# Cross-target compile helper for TextEngineCore and TextEngineReferenceProviders.
# Compiles both packages for non-host targets and prints stable key-value lines
# carrying a package= field (core | providers).
#   iOS device + simulator: blocking, through the Swift package graph (xcodebuild).
#   WASM + embedded WASM: observational, via a Swift SDK matched to the runner
#   toolchain; skipped-with-record when no matching SDK can be provisioned.
# The exit code reflects only the blocking iOS results, across both packages.
```

- [ ] **Step 2: Update the AGENTS.md package-layout note for reference providers**

In `AGENTS.md`, find the `Sources/TextEngineReferenceProviders` bullet under "Package layout":

```
- `Sources/TextEngineReferenceProviders` — Foundation-free reference provider
  library. Reference providers live outside the core.
```

Replace with:

```
- `Sources/TextEngineReferenceProviders` — Foundation-free reference provider
  library. Reference providers live outside the core. It is a supported portable
  product: the hosted cross-target helper compiles it for iOS (blocking) and
  WASM (observational) alongside `TextEngineCore`.
```

- [ ] **Step 3: Update the AGENTS.md CI section for both cross-target jobs**

In `AGENTS.md`, find the iOS cross-target job bullet:

```
- **iOS cross-target compile** on `macos-latest`: iOS device + simulator are
  **blocking**, via `./.github/scripts/cross-target-compile.sh --targets ios`.
  This is the only hosted macOS job.
```

Replace with:

```
- **iOS cross-target compile** on `macos-latest`: iOS device + simulator are
  **blocking** for both `TextEngineCore` and `TextEngineReferenceProviders`, via
  `./.github/scripts/cross-target-compile.sh --targets ios`. This is the only
  hosted macOS job.
```

Then find the WASM cross-target job bullet:

```
- **WASM cross-target observation** on `ubuntu-latest` with
  `swift:6.2.1-bookworm`: WASM + embedded WASM run via
  `./.github/scripts/cross-target-compile.sh --targets wasm`. They remain
  **observational**: the helper compiles them when a matching Swift SDK is
  installed/provisioned, otherwise records a non-blocking skip.
```

Replace with:

```
- **WASM cross-target observation** on `ubuntu-latest` with
  `swift:6.2.1-bookworm`: WASM + embedded WASM run for both `TextEngineCore` and
  `TextEngineReferenceProviders` via
  `./.github/scripts/cross-target-compile.sh --targets wasm`. They remain
  **observational**: the helper compiles them when a matching Swift SDK is
  installed/provisioned, otherwise records a non-blocking skip.
```

- [ ] **Step 4: Re-run the self-test as a regression guard**

Run: `./.github/scripts/cross-target-compile.sh --self-test`
Expected: `self_test=pass`, exit status `0` (docs edits must not change behavior).

- [ ] **Step 5: Commit the documentation update**

```bash
git add AGENTS.md .github/scripts/cross-target-compile.sh
git commit -m "docs: document portable reference provider cross-target coverage"
```

---

## Task 6: Record the verification evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-18-cross-target-provider-coverage.md`

- [ ] **Step 1: Collect local evidence**

Run and capture the exact output of each:

```bash
./.github/scripts/cross-target-compile.sh --self-test
bash -n .github/scripts/cross-target-compile.sh && echo "syntax_ok"
./.github/scripts/cross-target-compile.sh --targets ios
rg -n "Foundation" Sources/TextEngineCore; echo "foundation_scan_exit=$?"
rg -n "name: iOS cross-target compile|name: WASM cross-target observation" .github/workflows/swift-ci.yml
```

Expected: `self_test=pass`; `syntax_ok`; iOS run shows both packages `pass` for device + simulator with `... blocking_failures=0 exit=0`; Foundation scan prints nothing with `foundation_scan_exit=1`; both required job-name contexts present.

- [ ] **Step 2: Write the verification record**

Create `docs/superpowers/verification/2026-06-18-cross-target-provider-coverage.md` capturing: the commands above with their real outputs; the red-phase `--self-test` failure from Task 1 Step 2; the iOS compile time delta versus the previous single-package run (note it in the macOS job risk row); and a placeholder section "Hosted Evidence" to be filled with the PR-head Swift CI run id and the post-merge push run id once the PR runs.

- [ ] **Step 3: Commit the verification record**

```bash
git add docs/superpowers/verification/2026-06-18-cross-target-provider-coverage.md
git commit -m "docs: record cross-target provider coverage verification"
```

---

## Verification Summary (whole slice)

After all tasks, the following must hold:
- `./.github/scripts/cross-target-compile.sh --self-test` → `self_test=pass`.
- `./.github/scripts/cross-target-compile.sh --targets ios` → both packages compile for device + simulator; `mode=cross_target_compile_overall blocking_failures=0 exit=0`.
- `./.github/scripts/cross-target-compile.sh --targets wasm` → both packages observed (skip recorded when no SDK), exit `0`.
- `rg -n "Foundation" Sources/TextEngineCore` → no matches (unchanged invariant).
- Required job contexts `iOS cross-target compile` and `WASM cross-target observation` unchanged in `.github/workflows/swift-ci.yml`.
- No changes under `Sources/**`, `Tests/**`, or `Package.swift`.
- Hosted PR-head run is green on all three required contexts (iOS job compiles both schemes blocking); post-merge push run anchors the merged-code proof. Record both run ids in the verification document.
