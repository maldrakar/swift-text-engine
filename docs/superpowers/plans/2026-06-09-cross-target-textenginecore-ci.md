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
xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS' -derivedDataPath /tmp/ct-preflight-device 2>&1 | tail -2
xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ct-preflight-sim 2>&1 | tail -2
```

Expected: each ends with `** BUILD SUCCEEDED **`.

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

# Resolve an installed Swift SDK id matching the version and target kind.
# kind is "wasm" or "wasm_embedded".
resolve_wasm_sdk_id() {
  local version="$1" kind="$2" line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$kind" in
      wasm_embedded)
        if [[ "$line" == *"$version"* && "$line" == *wasm* && "$line" == *embedded* ]]; then
          printf '%s' "$line"
          return 0
        fi
        ;;
      wasm)
        if [[ "$line" == *"$version"* && "$line" == *wasm* && "$line" != *embedded* ]]; then
          printf '%s' "$line"
          return 0
        fi
        ;;
    esac
  done < <(swift sdk list 2>/dev/null)
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

run_self_test() {
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
  echo "self_test=pass"
}

# ---------------------------------------------------------------------------
# Compile steps (require a toolchain)
# ---------------------------------------------------------------------------

LAST_RESULT=""
LAST_REASON=""

ios_scheme_available() {
  xcodebuild -list 2>/dev/null \
    | awk 'f && NF { gsub(/^[[:space:]]+/, ""); print } /Schemes:/ { f = 1 }' \
    | grep -qx "$SCHEME"
}

compile_ios_target() {
  local destination="$1" logfile="$2"
  if ! ios_scheme_available; then
    LAST_RESULT="fail"
    LAST_REASON="scheme_unresolved"
    return
  fi
  if xcodebuild build -scheme "$SCHEME" -destination "$destination" -derivedDataPath "$DDP" >"$logfile" 2>&1; then
    LAST_RESULT="pass"
    LAST_REASON="none"
  else
    LAST_RESULT="fail"
    LAST_REASON="compile_failed"
  fi
}

compile_wasm_target() {
  local kind="$1" logfile="$2" sdk_id url_var url
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
    if ! swift sdk install "$url" >"${logfile}.install" 2>&1; then
      LAST_RESULT="skipped"
      LAST_REASON="sdk_install_failed"
      return
    fi
    if ! sdk_id="$(resolve_wasm_sdk_id "$SWIFT_VERSION" "$kind")"; then
      LAST_RESULT="skipped"
      LAST_REASON="sdk_unresolved_after_install"
      return
    fi
  fi
  if swift build --swift-sdk "$sdk_id" --target "$PACKAGE_TARGET" >"$logfile" 2>&1; then
    LAST_RESULT="pass"
    LAST_REASON="none"
  else
    LAST_RESULT="fail"
    LAST_REASON="compile_failed"
  fi
}

main() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/cross-target.XXXXXX")"
  DDP="$WORK/ddp"
  SWIFT_VERSION="$(swift_version_key "$(swift --version 2>&1 | head -n 1)")"
  echo "cross_target_swift_version=${SWIFT_VERSION:-unknown}"

  compile_ios_target 'generic/platform=iOS' "$WORK/ios_device.log"
  ios_device_result="$LAST_RESULT"
  emit_target_line ios_device "$LAST_RESULT" "$LAST_REASON" true

  compile_ios_target 'generic/platform=iOS Simulator' "$WORK/ios_simulator.log"
  ios_simulator_result="$LAST_RESULT"
  emit_target_line ios_simulator "$LAST_RESULT" "$LAST_REASON" true

  compile_wasm_target wasm "$WORK/wasm.log"
  wasm_result="$LAST_RESULT"
  emit_target_line wasm "$LAST_RESULT" "$LAST_REASON" false

  compile_wasm_target wasm_embedded "$WORK/wasm_embedded.log"
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
          swift --version
          xcodebuild -version
          uname -a

      - name: Compile TextEngineCore for non-host targets
        run: ./.github/scripts/cross-target-compile.sh
```

- [ ] **Step 2: Verify the workflow shape**

Run:

```bash
rg -n "host-tests-and-benchmark-gate|cross-target-compile|Cross-target compile|Compile TextEngineCore for non-host targets|continue-on-error" .github/workflows/swift-ci.yml
```

Expected:

- both job ids `host-tests-and-benchmark-gate` and `cross-target-compile` are present;
- the new job name `Cross-target compile` is present;
- the helper-invoking step is present;
- no `continue-on-error` is introduced in the existing job.

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
run_id="$(gh run list --workflow "Swift CI" --branch slice-12-post-slice-review --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id"
mkdir -p /tmp/slice13-cross-target
gh run view "$run_id" --log > /tmp/slice13-cross-target/run-1.log
rg -n "Cross-target compile|cross_target_swift_version|mode=cross_target_compile|xcodebuild -version|Swift version|Darwin" /tmp/slice13-cross-target/run-1.log
```

Expected:

- the `host-tests-and-benchmark-gate` job still passes;
- the `cross-target-compile` job ran;
- four `mode=cross_target_compile target=...` lines and one `mode=cross_target_compile_summary` line are present.

- [ ] **Step 3: Confirm or repair the blocking iOS result on the runner**

Inspect the iOS lines in `/tmp/slice13-cross-target/run-1.log`.

- If `target=ios_device` and `target=ios_simulator` both show `result=pass`, the blocking iOS contract holds. Record the runner `xcodebuild -version` and resolved SDK from the log.
- If either iOS target shows `result=fail reason=scheme_unresolved` or a destination error, the runner's default Xcode mis-resolves the package scheme. Stay inside the package graph: add a step before the helper that selects a known-good installed Xcode and record which one worked, for example:

```yaml
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.4.app
```

Discover the available Xcodes on the runner first with `ls -d /Applications/Xcode*.app` (printed by adding it to the `Show toolchain` step), choose one whose `xcodebuild` builds the package-graph iOS destinations, and record the selection. Do not switch to a non-graph compile.

- If repaired, commit:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: select runner Xcode for cross-target iOS build"
git push
```

Then re-run Step 2 with the new run id until both iOS targets pass.

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

Record the `push` run on `main` after merge: run ID, URL, head SHA, conclusion,
and the cross-target summary line.

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

Populate every section from `/tmp/slice13-cross-target/*.log`, the local command outputs, and the Task 4 run metadata. Replace every instruction line with actual captured text.

- [ ] **Step 3: Verify the document has no placeholder text**

Run:

```bash
rg -n "TODO|TBD|<discovered|<run|exact outputs for|Record:" docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md; echo "exit=$?"
```

Expected: no output and `exit=1`.

- [ ] **Step 4: Commit the verification record**

Run:

```bash
git add docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md
git commit -m "docs: record cross-target ci verification"
git push
git status --short
```

Expected: commit and push succeed; `git status --short` has no output.

## Task 6: Final Slice Verification

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
git diff main -- .github/workflows/swift-ci.yml | rg -n "^\+" | rg -n "Run host tests|Run synthetic benchmark gate|Run memory shape diagnostic|Run RSS memory observation diagnostic|Observe realistic provider relative performance"; echo "existing_steps_touched_exit=$?"
```

Expected:

- `helper_nongraph_exit=1` (no non-graph iOS compile in the helper);
- `existing_steps_touched_exit=1` (the diff adds no lines to the existing job's steps).

- [ ] **Step 4: Confirm the final hosted run for the current head**

Run:

```bash
final_head_sha="$(git rev-parse HEAD)"
final_run_id="$(gh run list --workflow "Swift CI" --branch slice-12-post-slice-review --event pull_request --limit 20 --json databaseId,headSha --jq ".[] | select(.headSha == \"${final_head_sha}\") | .databaseId" | head -n 1)"
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

- [ ] **Step 6: Record the post-merge push run**

After the PR is merged to `main`, capture the `push` run and append it to the verification document if not already recorded:

```bash
push_run_id="$(gh run list --workflow "Swift CI" --branch main --event push --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run view "$push_run_id" --json headSha,conclusion,url --jq '.'
gh run view "$push_run_id" --log | rg -n "mode=cross_target_compile_summary"
```

Expected: the push run on the merge commit concludes `success` and prints the cross-target summary line. If newly recorded, commit with `docs: record cross-target ci post-merge run` and push.
