# Cross-Target CI For TextEngineCore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a separate, parallel GitHub Actions job that compiles `TextEngineCore` for iOS device/simulator (blocking, via the Swift package graph) and for WASM/embedded WASM (observational, via a Swift SDK matched to the runner toolchain), before variable-height layout changes the public core API.

**Architecture:** The existing `Host tests and benchmark gate` job is untouched. A new `cross-target-compile` job on `macos-latest` runs a repo-owned helper, `.github/scripts/cross-target-compile.sh`, that emits one stable key-value line per target plus a summary line. iOS is built through the package graph with `xcodebuild` (no non-graph fallback); WASM is best-effort and skipped-with-record when no matching SDK can be provisioned. The helper exit code reflects only the blocking iOS results.

**Tech Stack:** Swift Package Manager, Swift 6.x, GitHub Actions, `xcodebuild`, `swift sdk`, Bash 3.2-compatible shell, `gh`, `rg`, `awk`, `sed`.

---

## Source Design

Implement the approved Slice 13 design:

```text
docs/superpowers/specs/2026-06-09-cross-target-textenginecore-ci-design.md
```

Preserve these constraints:

- Do not change `Sources/TextEngineCore`, `Sources/ViewportBenchmarks`, `Tests`, or `Package.swift` (including no `platforms:` declaration).
- Do not change the existing `Host tests and benchmark gate` job, its steps, or budgets.
- Do not change the Slice 12 realistic relative observation or its threshold.
- iOS compile checks go through the Swift package graph; there is no non-graph fallback.
- WASM and embedded-WASM checks are observational and never fail the job in Slice 13.
- Do not add repository rulesets, branch protection, required status checks, storage adapters, variable-height layout, or memory budgets.

## Branch Note

All Slice 13 work continues on the existing branch `slice-12-post-slice-review`, which already holds the Slice 12 review, the Slice 13 spec, and this plan. Do not create a new branch.

## File Structure

Create:

```text
.github/scripts/cross-target-compile.sh
docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md
```

Modify:

```text
.github/workflows/swift-ci.yml
```

Responsibility map:

```text
.github/scripts/cross-target-compile.sh
  Compiles TextEngineCore for iOS (blocking, package graph) and WASM/embedded
  WASM (observational, runner-matched SDK). Prints one stable per-target line
  plus a summary line. Exit code from blocking iOS results only. Has --self-test.

.github/workflows/swift-ci.yml
  Keeps the existing job unchanged. Adds a parallel cross-target-compile job
  that runs on pull_request and push to main and invokes the helper.

docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md
  Records local checks, the verified runner iOS command and selected Xcode, the
  WASM provisioning outcome, per-target lines, summary, job duration, the
  post-merge push run, and source-boundary checks.
```

## Task 1: Preflight

**Files:**
- Read: `docs/superpowers/specs/2026-06-09-cross-target-textenginecore-ci-design.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `Package.swift`

- [ ] **Step 1: Confirm spec requirements that drive implementation**

Run:

```bash
rg -n "package graph mechanism is mandatory|There is no fallback|observational|skipped_base|continue-on-error|matched to the runner|generic/platform=iOS" docs/superpowers/specs/2026-06-09-cross-target-textenginecore-ci-design.md
```

Expected: matches for the mandatory package-graph statement, observational WASM, and the iOS destinations.

- [ ] **Step 2: Confirm the package scheme name exists**

Run:

```bash
xcodebuild -list
```

Expected: output lists a `TextEngineCore` scheme (alongside `SwiftTextEngine-Package` and `ViewportBenchmarks`).

- [ ] **Step 3: Re-confirm the package-graph iOS build works locally**

Run:

```bash
xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS' -derivedDataPath /tmp/ct-preflight-device > /tmp/ct-preflight-device.log 2>&1
echo "device_exit=$?"
tail -2 /tmp/ct-preflight-device.log
xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ct-preflight-sim > /tmp/ct-preflight-sim.log 2>&1
echo "simulator_exit=$?"
tail -2 /tmp/ct-preflight-sim.log
```

Expected: `device_exit=0` and `simulator_exit=0`, and each log tail ends with `** BUILD SUCCEEDED **`. (The exit code is captured directly rather than through a pipe, so a build failure is not masked by `tail`.)

- [ ] **Step 4: Confirm branch and clean tree**

Run:

```bash
git branch --show-current
git status --short
```

Expected: branch is `slice-12-post-slice-review` and `git status --short` has no output.

## Task 2: Add The Cross-Target Compile Helper

**Files:**
- Create: `.github/scripts/cross-target-compile.sh`

- [ ] **Step 1: Create the helper script**

Create `.github/scripts/cross-target-compile.sh` with this exact content:

```bash
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

usage() {
  cat <<'EOF'
Usage:
  cross-target-compile.sh
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
  assert_equal "6.1.2" \
    "$(swift_version_key 'Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)')" \
    "swift_version_key_apple"
  assert_equal "6.2.1" \
    "$(swift_version_key 'Swift version 6.2.1 (swift-6.2.1-RELEASE)')" \
    "swift_version_key_oss"
  assert_equal "0" "$(count_blocking_failures pass:true pass:true skipped:false)" "no_blocking_failures"
  assert_equal "1" "$(count_blocking_failures fail:true pass:false fail:false skipped:false)" "one_blocking_failure"
  assert_equal "2" "$(count_blocking_failures fail:true fail:true)" "two_blocking_failures"
  assert_equal "mode=cross_target_compile target=ios_device result=pass reason=none blocking=true" \
    "$(emit_target_line ios_device pass none true)" "emit_line"
  assert_equal "mode=cross_target_compile target=wasm result=skipped reason=sdk_unavailable blocking=false" \
    "$(emit_target_line wasm skipped sdk_unavailable false)" "emit_skip_line"
  assert_equal "mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0" \
    "$(build_summary pass pass skipped skipped 0 0)" "summary_clean"
  assert_equal "mode=cross_target_compile_summary ios_device=fail ios_simulator=pass wasm=fail wasm_embedded=skipped blocking_failures=1 exit=1" \
    "$(build_summary fail pass fail skipped 1 1)" "summary_ios_fail"
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
  echo "cross_target_wasm_sdk_id target=${target_name} id=${sdk_id}"
  echo "cross_target_command target=${target_name} cmd=\"swift build --swift-sdk ${sdk_id} --target ${PACKAGE_TARGET}\""
  if swift build --swift-sdk "$sdk_id" --target "$PACKAGE_TARGET" >"$logfile" 2>&1; then
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

  print_ios_toolchain_metadata
  resolve_ios_scheme "$WORK/xcodebuild-list.log"

  compile_ios_target ios_device 'generic/platform=iOS' "$WORK/ios_device.log"
  ios_device_result="$LAST_RESULT"
  emit_target_line ios_device "$LAST_RESULT" "$LAST_REASON" true

  compile_ios_target ios_simulator 'generic/platform=iOS Simulator' "$WORK/ios_simulator.log"
  ios_simulator_result="$LAST_RESULT"
  emit_target_line ios_simulator "$LAST_RESULT" "$LAST_REASON" true

  compile_wasm_target wasm wasm "$WORK/wasm.log"
  wasm_result="$LAST_RESULT"
  emit_target_line wasm "$LAST_RESULT" "$LAST_REASON" false

  compile_wasm_target wasm_embedded wasm_embedded "$WORK/wasm_embedded.log"
  wasm_embedded_result="$LAST_RESULT"
  emit_target_line wasm_embedded "$LAST_RESULT" "$LAST_REASON" false

  local blocking_failures exit_code
  blocking_failures="$(count_blocking_failures \
    "${ios_device_result}:true" \
    "${ios_simulator_result}:true" \
    "${wasm_result}:false" \
    "${wasm_embedded_result}:false")"
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
if [[ $# -gt 0 ]]; then
  usage
  exit 2
fi
main
```

- [ ] **Step 2: Make the helper executable**

Run:

```bash
chmod +x .github/scripts/cross-target-compile.sh
```

Expected: no output.

- [ ] **Step 3: Run the helper self-test**

Run:

```bash
.github/scripts/cross-target-compile.sh --self-test
```

Expected:

```text
self_test=pass
```

- [ ] **Step 4: Verify the helper does not use a non-graph iOS fallback**

Run:

```bash
rg -n "xcrun swiftc|emit-module|-Xswiftc" .github/scripts/cross-target-compile.sh; echo "exit=$?"
```

Expected: no output and `exit=1`. The iOS path is package-graph only.

- [ ] **Step 5: Commit the helper**

Run:

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "ci: add cross-target compile helper"
git status --short
```

Expected: commit succeeds and `git status --short` has no output.

## Task 3: Wire The Cross-Target Compile Job

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Add the parallel job**

Append this job to `.github/workflows/swift-ci.yml` under `jobs:`, after the existing `host-tests-and-benchmark-gate` job (sibling indentation, two spaces):

```yaml
  cross-target-compile:
    name: Cross-target compile
    runs-on: macos-latest
    timeout-minutes: 20

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Show toolchain
        run: |
          echo "developer_dir=${DEVELOPER_DIR:-unset}"
          xcode-select -p
          ls -d /Applications/Xcode*.app || true
          swift --version
          xcodebuild -version
          uname -a

      - name: Compile TextEngineCore for non-host targets
        run: ./.github/scripts/cross-target-compile.sh
```

If a later run shows the default-selected Xcode mis-resolves the package scheme or destinations (see Task 4 Step 3), add a job-level `env:` block so both `Show toolchain` and the helper see the same toolchain, and do not use `sudo xcode-select` (it mutates global runner state):

```yaml
  cross-target-compile:
    name: Cross-target compile
    runs-on: macos-latest
    timeout-minutes: 20
    env:
      DEVELOPER_DIR: /Applications/Xcode_16.4.app/Contents/Developer
```

Use the exact Xcode path discovered from the `ls -d /Applications/Xcode*.app` output; the value above is illustrative.

- [ ] **Step 2: Verify the workflow shape**

Run:

```bash
rg -n "host-tests-and-benchmark-gate|cross-target-compile|Cross-target compile|Compile TextEngineCore for non-host targets" .github/workflows/swift-ci.yml
git diff -- .github/workflows/swift-ci.yml | rg -n "^\+.*continue-on-error"; echo "added_continue_on_error_exit=$?"
```

Expected:

- both job ids `host-tests-and-benchmark-gate` and `cross-target-compile` are present;
- the new job name `Cross-target compile` is present;
- the helper-invoking step is present;
- `added_continue_on_error_exit=1` — the diff adds no `continue-on-error` line. (A plain `rg` for `continue-on-error` would also match the pre-existing line on the realistic-observation step, so the diff check is used to confirm none was *added*.)

- [ ] **Step 3: Validate the YAML parses and exposes both jobs**

Run (uses PyYAML if present, otherwise falls back to a structural grep so it never hard-fails on a missing module):

```bash
if python3 -c "import yaml" 2>/dev/null; then
  python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/swift-ci.yml')); print(sorted(d['jobs'].keys()))"
else
  echo "pyyaml_absent_falling_back_to_grep"
  rg -n "^  (host-tests-and-benchmark-gate|cross-target-compile):" .github/workflows/swift-ci.yml
fi
```

Expected: either

```text
['cross-target-compile', 'host-tests-and-benchmark-gate']
```

or the two job keys at two-space indentation:

```text
  host-tests-and-benchmark-gate:
  cross-target-compile:
```

- [ ] **Step 4: Run local stable verification**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
.github/scripts/cross-target-compile.sh --self-test
```

Expected:

- `swift test`: PASS, 39 tests, 0 failures.
- `swift build -c release`: PASS.
- `--gate`: three `gate=pass` lines.
- `--memory-shape`: three `invariant=pass` lines.
- `--memory-observation`: three `observation=pass` lines.
- helper self-test: `self_test=pass`.

- [ ] **Step 5: Commit the workflow job**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: add cross-target compile job"
git status --short
```

Expected: commit succeeds and `git status --short` has no output.

## Task 4: Collect Hosted Evidence And Discover Runner Commands

**Files:**
- Read: `.github/workflows/swift-ci.yml`
- Read: `.github/scripts/cross-target-compile.sh`

- [ ] **Step 1: Push the branch and ensure a PR exists**

Run:

```bash
git push -u origin slice-12-post-slice-review
gh pr list --head slice-12-post-slice-review --json number,url --jq '.'
```

If no PR is listed, create one:

```bash
gh pr create \
  --title "Slice 13: cross-target CI for TextEngineCore (+ Slice 12 review)" \
  --body "Adds a parallel cross-target compile job: blocking iOS (package graph) and observational WASM. Also includes the Slice 12 post-slice review and the Slice 13 spec/plan."
```

Expected: a PR targeting `main` exists for this branch.

- [ ] **Step 2: Watch the first hosted run and capture the cross-target output**

Run:

```bash
head_sha="$(git rev-parse HEAD)"
run_id="$(gh run list --workflow "Swift CI" --branch slice-12-post-slice-review --event pull_request --limit 20 --json databaseId,headSha --jq ".[] | select(.headSha == \"${head_sha}\") | .databaseId" | head -n 1)"
test -n "$run_id" || { echo "no_run_for_head=${head_sha} (wait for CI to start, then retry)"; exit 1; }
gh run watch "$run_id"
mkdir -p /tmp/slice13-cross-target
gh run view "$run_id" --log > /tmp/slice13-cross-target/run-1.log
rg -n "Cross-target compile|cross_target_swift_version|cross_target_xcode|cross_target_iphoneos|cross_target_command|cross_target_wasm_sdk_id|mode=cross_target_compile|xcodebuild -version|Swift version|Darwin" /tmp/slice13-cross-target/run-1.log
```

Selecting by `headSha` rather than the latest run avoids capturing a stale run after a push or rerun.

Expected:

- the `host-tests-and-benchmark-gate` job still passes;
- the `cross-target-compile` job ran;
- four `mode=cross_target_compile target=...` lines and one `mode=cross_target_compile_summary` line are present.

- [ ] **Step 3: Confirm or repair the blocking iOS result on the runner**

Inspect the iOS lines in `/tmp/slice13-cross-target/run-1.log`.

Use the helper's metadata lines (`cross_target_developer_dir`, `cross_target_xcode_select_path`, `cross_target_xcodebuild_version`, `cross_target_iphoneos_sdk_*`) and the `cross_target_command` lines, which now appear directly in the hosted log.

- If `target=ios_device` and `target=ios_simulator` both show `result=pass`, the blocking iOS contract holds. Record the `cross_target_xcodebuild_version` and `cross_target_iphoneos_sdk_path` from the log.
- If either iOS target shows `result=fail` with `reason=xcodebuild_list_failed`, `reason=scheme_unresolved`, or `reason=destination_unavailable`, the runner's default Xcode mis-resolves the package scheme or destination (the helper prints the `xcodebuild-list`/build log tail to disambiguate). Stay inside the package graph: select a known-good installed Xcode via a job-level `DEVELOPER_DIR` env (preferred over `sudo xcode-select`, which mutates global runner state). Read the available Xcodes from the `ls -d /Applications/Xcode*.app` line in `Show toolchain`, then set, for example:

```yaml
  cross-target-compile:
    name: Cross-target compile
    runs-on: macos-latest
    timeout-minutes: 20
    env:
      DEVELOPER_DIR: /Applications/Xcode_16.4.app/Contents/Developer
```

Because `DEVELOPER_DIR` is job-level, both `Show toolchain` and the helper metadata then report the same selected toolchain. Use the exact discovered path. Do not switch to a non-graph compile.

- If repaired, commit:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: pin runner Xcode via DEVELOPER_DIR for cross-target iOS build"
git push
```

Then re-run Step 2 (re-resolving the run id by `headSha`) until both iOS targets pass.

- [ ] **Step 4: Record the WASM provisioning outcome and attempt a real WASM compile**

Inspect the WASM lines.

- If `target=wasm` / `target=wasm_embedded` show `result=skipped reason=sdk_unavailable`, the runner has no preinstalled matching SDK and no install URL is configured. Discover whether a matching Swift SDK for WebAssembly exists for the runner's Swift version (recorded as `cross_target_swift_version=`). On a scratch run or local probe with the same Swift version, try the swift.org WebAssembly SDK for that exact version, for example:

```bash
swift sdk install <discovered-webassembly-sdk-url-for-runner-swift-version>
swift sdk list
```

  - If a working install URL is found, set it for the job by adding `env:` to the helper step (both variables; embedded may share the same bundle or need a second URL):

```yaml
      - name: Compile TextEngineCore for non-host targets
        env:
          CROSS_TARGET_WASM_SDK_URL: "<discovered-url>"
          CROSS_TARGET_WASM_EMBEDDED_SDK_URL: "<discovered-url-or-same>"
        run: ./.github/scripts/cross-target-compile.sh
```

  Then commit, push, and re-run Step 2.

  - If no compatible WASM SDK can be provisioned for the runner's Swift version, leave the result as `skipped` with its reason. This is an acceptable Slice 13 outcome (WASM is observational). Record the attempted discovery and why it was skipped.

- Whatever the outcome (`pass`, `fail`, or `skipped`), the `cross-target-compile` job must not fail because of WASM: confirm the job conclusion is driven only by the iOS results.

- [ ] **Step 5: Capture the accepted hosted run metadata**

Run, using the final accepted `run_id`:

```bash
gh run view "$run_id" --json databaseId,headSha,event,status,conclusion,url --jq '.'
gh run view "$run_id" --json jobs --jq '.jobs[] | "\(.name): \(.startedAt) -> \(.completedAt) conclusion=\(.conclusion)"'
```

Expected: overall run conclusion `success`; both jobs recorded with start/finish timestamps (for job duration).

## Task 5: Finalize The Verification Record

**Files:**
- Create: `docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md`

- [ ] **Step 1: Create the verification document**

Create `docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md` with these sections, filled with the real captured outputs:

```markdown
# Cross-Target CI For TextEngineCore Verification

Date: 2026-06-09

## Scope

Slice 13 adds a separate parallel `cross-target-compile` job. iOS device and
simulator are blocking, package-graph (`xcodebuild`) compile checks; WASM and
embedded WASM are observational checks using a Swift SDK matched to the runner
toolchain, skipped-with-record when no matching SDK can be provisioned.

## Local Verification

Record exact outputs for:

- `swift test`
- `swift build -c release`
- `swift run -c release ViewportBenchmarks -- --gate`
- `swift run -c release ViewportBenchmarks -- --memory-shape`
- `swift run -c release ViewportBenchmarks -- --memory-observation`
- `.github/scripts/cross-target-compile.sh --self-test`
- `xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS'` (tail)
- `xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator'` (tail)

## Hosted Run

Record:

- run ID, attempt, run URL, event, head SHA, conclusion
- runner image, CPU model, `swift --version`, `xcodebuild -version`, `uname -a`
- the selected Xcode used for the iOS build and the resolved iOS SDK
- the exact selected iOS compile commands and their results
- whether the runner-matched WASM and embedded-WASM SDKs were provisioned, the
  resolved SDK ids if any, and each compile result or skip reason
- the four `mode=cross_target_compile` per-target lines and the
  `mode=cross_target_compile_summary` line
- the `cross-target-compile` job duration and timeout headroom
- confirmation that the existing `host-tests-and-benchmark-gate` job is unchanged
  and still passed

## Post-Merge Push Run

Pending until Task 7 (recorded after the PR is merged to `main`). This section is
intentionally left as `Pending` for pre-merge completion; Task 7 replaces it with
the merge-commit push run: run ID, URL, head SHA, conclusion, and the
cross-target summary line.

## Non-Goal Checks

Record:

```text
git diff main -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Expected: no output.

## Conclusion

State that Slice 13 delivers a blocking iOS package-graph compile proof and an
observational WASM probe, that WASM remains observational, and that promotion of
WASM to blocking is left to a later slice.
```

- [ ] **Step 2: Fill the document with real values**

Populate every section **except Post-Merge Push Run** from `/tmp/slice13-cross-target/*.log`, the local command outputs, and the Task 4 run metadata. Replace every instruction line with actual captured text. Leave the Post-Merge Push Run section as its `Pending until Task 7` marker — that run does not exist until the PR is merged, and Task 7 fills it.

- [ ] **Step 3: Verify the document has no placeholder text**

Run:

```bash
rg -n "TODO|TBD|<discovered|<run|exact outputs for|Record:" docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md; echo "exit=$?"
```

Expected: no output and `exit=1`. The `Pending until Task 7` text in the Post-Merge Push Run section is intentional and is not matched by this scan, so it is not a placeholder violation.

- [ ] **Step 4: Commit the verification record**

Run:

```bash
git add docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md
git commit -m "docs: record cross-target ci verification"
git push
git status --short
```

Expected: commit and push succeed; `git status --short` has no output.

## Task 6: Final Pre-Merge Slice Verification

This task is the pre-merge completion gate. Slice 13 is "pre-merge ready" when Tasks 1-6 pass. The post-merge push run is intentionally **not** part of this gate — it lives in Task 7 and runs only after the PR is merged, so an executor never blocks here on a step that cannot complete before merge.

**Files:**
- Read: `docs/superpowers/specs/2026-06-09-cross-target-textenginecore-ci-design.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `.github/scripts/cross-target-compile.sh`

- [ ] **Step 1: Run final local verification**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
.github/scripts/cross-target-compile.sh --self-test
```

Expected: all pass.

- [ ] **Step 2: Verify no source, test, or manifest drift**

Run:

```bash
git diff main -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Expected: no output.

- [ ] **Step 3: Verify the iOS path stays package-graph-only and the existing job is unchanged**

Run:

```bash
rg -n "xcrun swiftc|emit-module|-Xswiftc" .github/scripts/cross-target-compile.sh; echo "helper_nongraph_exit=$?"

# Structurally confirm the existing host job block is byte-identical to main, so
# only a sibling cross-target-compile job was added. This catches command, env,
# timeout, or continue-on-error changes inside the host job, not just added step
# names. Trailing blank lines are trimmed so the inter-job blank does not differ.
extract_host_job() {
  awk '
    /^  [A-Za-z0-9_-]+:/ {
      if ($0 ~ /^  host-tests-and-benchmark-gate:/) { inblock = 1 }
      else if (inblock) { exit }
    }
    inblock { print }
  ' | awk 'NF { last = NR } { line[NR] = $0 } END { for (i = 1; i <= last; i++) print line[i] }'
}
git show main:.github/workflows/swift-ci.yml | extract_host_job > /tmp/host-job-main.txt
extract_host_job < .github/workflows/swift-ci.yml > /tmp/host-job-head.txt
diff -u /tmp/host-job-main.txt /tmp/host-job-head.txt; echo "host_job_diff_exit=$?"
```

Expected:

- `helper_nongraph_exit=1` (no non-graph iOS compile in the helper);
- `host_job_diff_exit=0` (the `host-tests-and-benchmark-gate` job block is identical to `main`; only the sibling `cross-target-compile` job was added).

- [ ] **Step 4: Confirm the final hosted run for the current head**

Run:

```bash
final_head_sha="$(git rev-parse HEAD)"
final_run_id="$(gh run list --workflow "Swift CI" --branch slice-12-post-slice-review --event pull_request --limit 20 --json databaseId,headSha --jq ".[] | select(.headSha == \"${final_head_sha}\") | .databaseId" | head -n 1)"
test -n "$final_run_id" || { echo "no_run_for_head=${final_head_sha} (wait for CI to start, then retry)"; exit 1; }
gh run watch "$final_run_id"
gh run view "$final_run_id" --log > /tmp/slice13-final.log
rg -n "mode=cross_target_compile target=ios_device|mode=cross_target_compile target=ios_simulator|mode=cross_target_compile_summary" /tmp/slice13-final.log
```

Expected: both iOS targets `result=pass`; the summary line has `blocking_failures=0 exit=0`.

- [ ] **Step 5: Final status check**

Run:

```bash
git status --short
git log --oneline -6
```

Expected:

- `git status --short` has no output;
- recent commits include the helper, workflow job, and verification commits for Slice 13.

- [ ] **Step 6: Confirm pre-merge readiness**

Confirm Tasks 1-6 are complete: helper self-test passes, the workflow job is wired, the hosted PR run shows both iOS targets `result=pass` and a `blocking_failures=0 exit=0` summary, the WASM outcome (compiled or skipped-with-reason) is recorded, the existing job is unchanged, and the verification document is committed and pushed (except its Post-Merge section). At this point Slice 13 is ready to merge.

## Task 7: Post-Merge Follow-Up

> **Not part of pre-merge completion.** Run this only after the PR is merged to `main`. Do not block Slice 13 completion or hang waiting on it before merge.

**Files:**
- Modify: `docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md`

- [ ] **Step 1: Capture and record the post-merge push run**

After the PR is merged to `main`, capture the `push` run for the merge commit and fill the verification document's "Post-Merge Push Run" section:

```bash
merge_sha="$(git rev-parse origin/main)"
push_run_id="$(gh run list --workflow "Swift CI" --branch main --event push --limit 20 --json databaseId,headSha --jq ".[] | select(.headSha == \"${merge_sha}\") | .databaseId" | head -n 1)"
test -n "$push_run_id" || { echo "no_push_run_for_merge=${merge_sha} (wait for CI to start, then retry)"; exit 1; }
gh run watch "$push_run_id"
gh run view "$push_run_id" --json headSha,conclusion,url --jq '.'
gh run view "$push_run_id" --log | rg -n "mode=cross_target_compile_summary"
```

Expected: the push run on the merge commit concludes `success` and prints the cross-target summary line. (On `push`, the cross-target job runs; the realistic-observation step in the other job is skipped, as it is PR-only.)

- [ ] **Step 2: Commit the post-merge record**

```bash
git add docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md
git commit -m "docs: record cross-target ci post-merge run"
git push
```

Expected: commit and push succeed. (If `main` is protected against direct pushes, record this on a short follow-up branch/PR instead.)
