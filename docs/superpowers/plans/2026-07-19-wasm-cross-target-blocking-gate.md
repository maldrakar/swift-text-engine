# WASM Cross-Target Blocking Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the WASM cross-target compile a merge-blocking CI gate — provision swift.org's pinned 6.2.1 WASM SDK (checksum-verified, bounded retry) and make both `wasm` and `wasm-embedded` compiles blocking for both packages, fail-closed on any provisioning failure.

**Architecture:** Extend the existing `.github/scripts/cross-target-compile.sh` (two-kind model, `prepare`/`compile` split, `--self-test` seam). Add self-testable pure helpers for the install-arg build, per-kind blocking, and fail-closed skip→result mapping; wire them into the two runtime functions. Pin the bundle URL + checksum in the WASM job's step env. Keep the job/required-context name unchanged (the rename + ruleset update is a deferred repo-policy follow-up). A throwaway hosted "spike" run confirms provisioning + both compiles and measures the download, which decides whether `actions/cache` joins this slice.

**Tech Stack:** Bash (POSIX-ish, `set -uo pipefail`), Swift 6.2.1 toolchain (`swift:6.2.1-bookworm` container), swift.org WASM Swift SDK (`swift sdk install`), GitHub Actions, XCTest (`WorkflowShapeTests` reads the YAML off disk).

## Global Constraints

- **No Foundation in `Sources/TextEngineCore`** — `rg -n "Foundation" Sources/TextEngineCore` must be empty. (This slice touches no core source; the constraint must still hold.)
- **Swift Embedded compatible / iOS+WASM compile with no source changes** — the point of the slice; do not change engine/provider source to make WASM pass (an embedded incompatibility is a *finding*, handled separately).
- **Zero-dependency core.** No third-party packages. `actions/cache` (a GitHub Action, not a Swift package) is the only external piece, and only if the spike warrants it.
- **The pinned SDK bundle (exact, verbatim):**
  - URL: `https://download.swift.org/swift-6.2.1-release/wasm-sdk/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE_wasm.artifactbundle.tar.gz`
  - sha256: `482b9f95462b87bedfafca94a092cf9ec4496671ca13b43745097122d20f18af`
  - size: `106085411` bytes (matches `Content-Length`; one bundle installs both `swift-6.2.1_wasm` and `swift-6.2.1_wasm-embedded`).
- **Repo/CI facts:** repo `maldrakar/swift-text-engine`; WASM job id `wasm-cross-target-observation` (required context `WASM cross-target observation` — do NOT rename this slice); branch `slice-46-wasm-cross-target-blocking-gate`.
- **A gate that cannot fail is not a gate.** Provisioning failure must be fail-closed (red), never a silent skip.

---

## File Structure

- **`.github/scripts/cross-target-compile.sh`** (modify) — add pure helpers `sdk_install_display`, `wasm_kind_blocking`, `wasm_skip_result`; add non-pure `swift_sdk_install_retry`; rewire `prepare_wasm_sdk` (checksum + shared bundle + retry) and `compile_wasm_package_for_kind` (per-kind blocking + fail-closed); update header/exit comments and `run_self_test`.
- **`.github/workflows/swift-ci.yml`** (modify) — the WASM job's compile step gains the pinned URL+checksum env and an honest step name; job/context name unchanged.
- **`Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`** (modify) — refactor `hostJobSteps()` → `jobSteps(_:)`; add `wasmJobSteps()`; add one test pinning the WASM compile step's blocking shape.
- **`AGENTS.md`** (modify) — hard-constraint #4, CI/layout/commands prose (job now blocks; name-vs-reality mismatch called out + scoped to the follow-up).
- **`docs/superpowers/verification/2026-07-19-wasm-cross-target-blocking-gate.md`** (create) — recorded commands/outputs + hosted run IDs.
- **`MEMORY.md` + a Slice 46 memory file** (create, at closeout).

---

## Task 1: Checksum-passing install + bounded retry

Add the self-testable install-arg builder and a retry wrapper; wire them into `prepare_wasm_sdk` so both kinds provision from the one pinned bundle with `--checksum`.

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh`

**Interfaces:**
- Produces (pure): `sdk_install_display(url, checksum) -> "sdk install <url>[ --checksum <c>]"`.
- Produces (runtime): `swift_sdk_install_retry(url, checksum, logfile) -> 0|1`, echoing `cross_target_sdk_install_seconds=<n> attempts=<i>` on success.
- Consumes env: `CROSS_TARGET_WASM_SDK_URL`, `CROSS_TARGET_WASM_SDK_CHECKSUM`, optional `CROSS_TARGET_SDK_INSTALL_ATTEMPTS` (default 3), `CROSS_TARGET_SDK_INSTALL_BACKOFF` (default 3).

- [ ] **Step 1: Write the failing self-test for the pure arg-builder**

In `run_self_test` (before `echo "self_test=pass"`), add:

```bash
  # Task 1 — install arg builder: --checksum appended iff a checksum is supplied
  assert_equal "sdk install http://b --checksum abc123" \
    "$(sdk_install_display http://b abc123)" "install_display_with_checksum"
  assert_equal "sdk install http://b" \
    "$(sdk_install_display http://b "")" "install_display_without_checksum"
```

- [ ] **Step 2: Run the self-test to verify it fails**

Run: `./.github/scripts/cross-target-compile.sh --self-test`
Expected: FAIL — `sdk_install_display: command not found` (or a non-`self_test=pass` line).

- [ ] **Step 3: Add the pure helper**

In the "Pure helpers" region (immediately after `resolve_wasm_sdk_id_from_list` closes, before the self-test `assert_equal` definition), add:

```bash
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
```

- [ ] **Step 4: Run the self-test to verify it passes**

Run: `./.github/scripts/cross-target-compile.sh --self-test`
Expected: `self_test=pass`.

- [ ] **Step 5: Add the retry wrapper (runtime, not pure)**

In the "Compile steps (require a toolchain)" region, immediately before `prepare_wasm_sdk`, add:

```bash
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
```

- [ ] **Step 6: Rewire `prepare_wasm_sdk` to use the shared bundle + checksum + retry**

Replace the `local` line and the install branch. The `local` line becomes:

```bash
  local kind="$1" logfile="$2" sdk_id="" url checksum skip=""
```

Replace this block:

```bash
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
```

with:

```bash
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
```

- [ ] **Step 7: Run the self-test again (still green) and shellcheck-parse**

Run: `./.github/scripts/cross-target-compile.sh --self-test`
Expected: `self_test=pass`.
Run: `bash -n .github/scripts/cross-target-compile.sh`
Expected: no output (parses clean).

- [ ] **Step 8: Commit**

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "feat: checksum-verified WASM SDK install with bounded retry

Both kinds provision from one pinned swift.org bundle; --checksum is passed
when set; a bounded retry tames transient download.swift.org errors and the
install time is measured for the caching decision.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Per-kind blocking seam + fail-closed provisioning

Make WASM results blocking via a **per-kind** flag (so the embedded fallback is a config flip), and turn a provisioning skip on a blocking kind into a `fail` (fail-closed).

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh`

**Interfaces:**
- Produces (pure): `wasm_kind_blocking(kind) -> "true"|"false"` (`wasm` always true; `wasm_embedded` true unless `CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false`).
- Produces (pure): `wasm_skip_result(skip, blocking) -> ""|"fail"|"skipped"` (empty skip → proceed; skip on blocking → fail; skip on observational → skipped).
- Consumes: `count_blocking_failures` (unchanged logic) now receives WASM `fail:true` / `pass:true` pairs.

- [ ] **Step 1: Write the failing self-tests for the two pure helpers**

In `run_self_test`, add:

```bash
  # Task 2 — per-kind blocking flag (the fallback ladder is a config flip)
  assert_equal "true" "$(wasm_kind_blocking wasm)" "wasm_blocks"
  assert_equal "true" "$(wasm_kind_blocking wasm_embedded)" "embedded_blocks_by_default"
  assert_equal "false" \
    "$(CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false wasm_kind_blocking wasm_embedded)" \
    "embedded_ladder_demotes_to_observational"
  # Task 2 — fail-closed: a provisioning skip on a blocking kind is a FAIL
  assert_equal "" "$(wasm_skip_result "" true)" "no_skip_proceeds_to_compile"
  assert_equal "fail" "$(wasm_skip_result sdk_unavailable true)" "skip_on_blocking_is_fail"
  assert_equal "skipped" "$(wasm_skip_result sdk_unavailable false)" "skip_on_observational_is_skip"
  # Task 2 — WASM pairs now count toward blocking failures (a fail counts; a
  # demoted/observational embedded skip does not). Pair order is 2 packages x
  # {ios_device, ios_simulator, wasm, wasm_embedded}.
  assert_equal "1" \
    "$(count_blocking_failures pass:true pass:true fail:true pass:true pass:true pass:true pass:true pass:true)" \
    "wasm_fail_counts"
  assert_equal "0" \
    "$(count_blocking_failures pass:true pass:true pass:true skipped:false pass:true pass:true pass:true skipped:false)" \
    "wasm_embedded_demoted_not_counted"
```

- [ ] **Step 2: Run the self-test to verify it fails**

Run: `./.github/scripts/cross-target-compile.sh --self-test`
Expected: FAIL — `wasm_kind_blocking: command not found` (or a non-`self_test=pass` line).

- [ ] **Step 3: Add the two pure helpers**

In the "Pure helpers" region (next to `sdk_install_display` from Task 1), add:

```bash
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
    *) printf 'false' ;;
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
```

- [ ] **Step 4: Rewire `compile_wasm_package_for_kind`**

Replace:

```bash
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
```

with:

```bash
compile_wasm_package_for_kind() {
  local kind="$1" pkg="$2" package_target="$3" logfile="$4" sdk_id skip scratch_path result
  LAST_BLOCKING="$(wasm_kind_blocking "$kind")"
  case "$kind" in
    wasm) sdk_id="$WASM_SDK_ID_WASM"; skip="$WASM_SKIP_WASM" ;;
    wasm_embedded) sdk_id="$WASM_SDK_ID_WASM_EMBEDDED"; skip="$WASM_SKIP_WASM_EMBEDDED" ;;
  esac
  result="$(wasm_skip_result "$skip" "$LAST_BLOCKING")"
  if [[ -n "$result" ]]; then
    LAST_RESULT="$result"      # fail (blocking kind) or skipped (observational kind)
    LAST_REASON="$skip"
    return
  fi
```

(The `swift build` body below this block is unchanged.)

- [ ] **Step 5: Update the header + exit-code comments**

Replace the two WASM header lines and the exit-code line near the top of the file:

```bash
#   WASM + embedded WASM: observational, via a Swift SDK matched to the runner
#   toolchain; skipped-with-record when no matching SDK can be provisioned.
# The exit code reflects only the blocking iOS results, across both packages.
```

with:

```bash
#   WASM + embedded WASM: blocking, cross-compiled against a swift.org Swift SDK
#   pinned by URL + checksum (CROSS_TARGET_WASM_SDK_URL / _CHECKSUM) and installed
#   with a bounded retry. Provisioning is FAIL-CLOSED: a missing/failed/mismatched
#   SDK is a blocking failure, never a silent skip. Embedded can be demoted to
#   observational via CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false (the fallback ladder).
# The exit code reflects the blocking iOS AND WASM results, across both packages.
```

- [ ] **Step 6: Run the self-test to verify it passes**

Run: `./.github/scripts/cross-target-compile.sh --self-test`
Expected: `self_test=pass`.
Run: `bash -n .github/scripts/cross-target-compile.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "feat: make WASM compile blocking, per-kind, fail-closed

WASM results now count toward the exit code via a per-kind blocking flag so the
embedded fallback ladder is a config flip; a provisioning skip on a blocking
kind is a fail, not a silent pass.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Wire the pinned SDK into the WASM job

Give the WASM compile step the pinned URL+checksum env and an honest step name. Job/context name unchanged (Decision 5).

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

**Interfaces:**
- Produces: the `wasm-cross-target-observation` job's compile step now sets `CROSS_TARGET_WASM_SDK_URL` + `CROSS_TARGET_WASM_SDK_CHECKSUM` (consumed by Task 1's `prepare_wasm_sdk`).

- [ ] **Step 1: Replace the WASM compile step**

Replace:

```yaml
      - name: Observe cross-target packages for WASM
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: ./.github/scripts/cross-target-compile.sh --targets wasm
```

with:

```yaml
      - name: Compile cross-target packages for WASM
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        env:
          CROSS_TARGET_WASM_SDK_URL: https://download.swift.org/swift-6.2.1-release/wasm-sdk/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE_wasm.artifactbundle.tar.gz
          CROSS_TARGET_WASM_SDK_CHECKSUM: 482b9f95462b87bedfafca94a092cf9ec4496671ca13b43745097122d20f18af
        run: ./.github/scripts/cross-target-compile.sh --targets wasm
```

Leave the job header (`wasm-cross-target-observation` / `name: WASM cross-target observation`) and `timeout-minutes: 20` unchanged. (The spike, Task 5, decides whether to bump the timeout.)

- [ ] **Step 2: Sanity-check the YAML is well-formed via the existing reader**

The workflow has no separate linter in-repo; the `WorkflowShapeTests` reader (Task 4) will parse it. For now confirm the edit is syntactically plausible:

Run: `grep -n "Compile cross-target packages for WASM" .github/workflows/swift-ci.yml`
Expected: one match, inside the `wasm-cross-target-observation` job.
Run: `grep -n "WASM cross-target observation" .github/workflows/swift-ci.yml`
Expected: still present (job name unchanged).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: provision the pinned 6.2.1 WASM SDK in the WASM job

The WASM compile step now supplies the pinned swift.org bundle URL + sha256; the
job (and required-context) name stays 'WASM cross-target observation' -- the
rename + ruleset update is a deferred repo-policy follow-up.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Pin the WASM step's blocking shape (`WorkflowShapeTests`)

Guard against a future `continue-on-error` silently disarming the newly-blocking WASM job (the Slice-16 trap), reusing the existing YAML reader.

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`

**Interfaces:**
- Consumes: existing `parseStep`, `WorkflowStep`, `docsOnlyGuard`, `hostJobKey`.
- Produces: `jobSteps(_ jobKey: String)` (generalized from `hostJobSteps`), `wasmJobSteps()`, a `wasmJobKey` constant, and one test method.

- [ ] **Step 1: Write the failing test**

Add the `wasmJobKey` constant next to `hostJobKey` (line ~25):

```swift
private let wasmJobKey = "wasm-cross-target-observation"
```

Add this test method inside `final class WorkflowShapeTests`:

```swift
    // The WASM job is now a real blocking gate; pin its compile step's shape so a
    // future `continue-on-error` cannot silently swallow a fail-closed WASM failure
    // (the Slice 16 dead-step trap, in a different job).
    func testWasmCompileStepIsBlockingShaped() throws {
        let steps = try wasmJobSteps()
        let matches = steps.filter {
            $0.runTokens.contains("--targets") && $0.runTokens.contains("wasm")
        }
        XCTAssertEqual(
            matches.count, 1,
            "\(workflowPath): expected exactly one WASM compile step running "
                + "--targets wasm in \(wasmJobKey)")
        guard let step = matches.first else { return }
        XCTAssertNil(
            step.continueOnError,
            "\(workflowPath): the WASM compile step must not be continue-on-error — it "
                + "would swallow the fail-closed WASM gate (the Slice 16 trap)")
        XCTAssertEqual(
            step.ifCondition, docsOnlyGuard,
            "\(workflowPath): the WASM compile step must carry the docs-only guard")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter WorkflowShapeTests/testWasmCompileStepIsBlockingShaped`
Expected: FAIL to compile — `wasmJobSteps` is undefined.

- [ ] **Step 3: Generalize `hostJobSteps()` into `jobSteps(_:)` and add `wasmJobSteps()`**

Replace the `hostJobSteps()` function:

```swift
private func hostJobSteps() throws -> [WorkflowStep] {
    let url = repositoryRoot().appendingPathComponent(workflowPath)
    let text = try String(contentsOf: url, encoding: .utf8)
    let allLines = text.components(separatedBy: "\n")

    guard let jobStart = allLines.firstIndex(where: { $0.hasPrefix("  \(hostJobKey):") }) else {
        XCTFail("\(workflowPath): no job keyed \(hostJobKey)")
        return []
    }

    var jobEnd = allLines.count
    for index in (jobStart + 1)..<allLines.count {
        let line = allLines[index]
        if isBlank(line) || isComment(line) { continue }
        if indentation(of: line) <= 2 {
            jobEnd = index
            break
        }
    }

    let lines = Array(allLines[jobStart..<jobEnd])
    let starts = lines.indices.filter { lines[$0].hasPrefix("      - name:") }
    return starts.enumerated().map { order, start in
        let end = order + 1 < starts.count ? starts[order + 1] : lines.count
        return parseStep(Array(lines[start..<end]), index: order)
    }
}
```

with (rename the parameter; add two thin wrappers — all three jobs indent identically, so the same reader works for any job key):

```swift
private func jobSteps(_ jobKey: String) throws -> [WorkflowStep] {
    let url = repositoryRoot().appendingPathComponent(workflowPath)
    let text = try String(contentsOf: url, encoding: .utf8)
    let allLines = text.components(separatedBy: "\n")

    guard let jobStart = allLines.firstIndex(where: { $0.hasPrefix("  \(jobKey):") }) else {
        XCTFail("\(workflowPath): no job keyed \(jobKey)")
        return []
    }

    var jobEnd = allLines.count
    for index in (jobStart + 1)..<allLines.count {
        let line = allLines[index]
        if isBlank(line) || isComment(line) { continue }
        if indentation(of: line) <= 2 {
            jobEnd = index
            break
        }
    }

    let lines = Array(allLines[jobStart..<jobEnd])
    let starts = lines.indices.filter { lines[$0].hasPrefix("      - name:") }
    return starts.enumerated().map { order, start in
        let end = order + 1 < starts.count ? starts[order + 1] : lines.count
        return parseStep(Array(lines[start..<end]), index: order)
    }
}

private func hostJobSteps() throws -> [WorkflowStep] {
    try jobSteps(hostJobKey)
}

private func wasmJobSteps() throws -> [WorkflowStep] {
    try jobSteps(wasmJobKey)
}
```

- [ ] **Step 4: Run the new test + the whole suite**

Run: `swift test --filter WorkflowShapeTests/testWasmCompileStepIsBlockingShaped`
Expected: PASS.
Run: `swift test`
Expected: all green (existing `WorkflowShapeTests` still pass — `hostJobSteps()` behavior is unchanged).

- [ ] **Step 5: Prove the pin is live (local break → red → revert → green)**

Temporarily add `continue-on-error: true` under the WASM compile step's `if:` line in `.github/workflows/swift-ci.yml`, then:

Run: `swift test --filter WorkflowShapeTests/testWasmCompileStepIsBlockingShaped`
Expected: FAIL — "must not be continue-on-error".
Revert the edit (`git checkout .github/workflows/swift-ci.yml`), then:
Run: `swift test --filter WorkflowShapeTests/testWasmCompileStepIsBlockingShaped`
Expected: PASS. Confirm `git status --short` is empty.

- [ ] **Step 6: Commit**

```bash
git add Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
git commit -m "test: pin the WASM compile step's blocking shape

Generalize the host-job YAML reader to any job key and assert the WASM compile
step is not continue-on-error (the Slice 16 trap, now guarding a second job).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Spike — hosted provisioning, compile, and download measurement

Push the branch and read the real hosted WASM job: SDK installs with the pinned checksum, both kinds compile both packages as blocking, and record the download/install time. This is the authoritative feasibility + reliability check and it drives the caching decision (Task 6). (Local `swift build --swift-sdk` cannot substitute — the host Mac is Swift 6.2.4, and the exact-match rule needs the 6.2.1 container.)

**Files:** none (observation).

- [ ] **Step 1: Push the branch and open the PR**

```bash
git push -u origin slice-46-wasm-cross-target-blocking-gate
gh pr create -R maldrakar/swift-text-engine --fill --base main \
  --title "Slice 46: WASM cross-target compile as a blocking CI gate"
```

- [ ] **Step 2: Wait for the WASM job and read it at step level**

```bash
gh run list -R maldrakar/swift-text-engine \
  --branch slice-46-wasm-cross-target-blocking-gate --workflow swift-ci.yml \
  --limit 1 --json databaseId,status,conclusion
# then, with the databaseId:
gh run view <id> -R maldrakar/swift-text-engine --log \
  | grep -E "cross_target_swift_version|cross_target_sdk_install_seconds|cross_target_wasm_sdk_id|mode=cross_target_compile(_summary|_overall)? |result=(pass|fail|skipped)"
```

Expected (success shape):
- `cross_target_wasm_sdk_id target=wasm ... id=swift-6.2.1_wasm` and `... target=wasm_embedded ... id=swift-6.2.1_wasm-embedded`
- four `mode=cross_target_compile target=wasm... result=pass ... blocking=true` / `target=wasm_embedded... result=pass ... blocking=true` lines (core + providers)
- `mode=cross_target_compile_overall blocking_failures=0 exit=0`
- one `cross_target_sdk_install_seconds=<n>` line — **record `<n>`**.

- [ ] **Step 3: If `wasm-embedded` fails to compile — engage the fallback ladder**

If `target=wasm_embedded` shows `result=fail reason=compile_failed`, read the failure tail in the log. If it's a genuine Embedded-Swift incompatibility not fixable in this slice, set the ladder: add `CROSS_TARGET_WASM_EMBEDDED_BLOCKING: "false"` to the WASM step's `env:` (Task 3), re-push, and confirm embedded now reports `result=skipped ... blocking=false` while `wasm` stays blocking. Record the reason verbatim in the verification doc. (If it is fixable and truly WASM-only, that is a separate recorded change — do not edit engine source to force a pass without recording why.)

- [ ] **Step 4: Record the spike outcome**

Note in the verification doc (created in Task 8): the run ID, the SDK ids, the four per-target results, `exit=0`, and `cross_target_sdk_install_seconds=<n>`.

---

## Task 6: SDK caching — decide on the spike data (Decision 7)

**Files:** possibly `.github/workflows/swift-ci.yml`.

- [ ] **Step 1: Apply Decision 7's rule to the measured number**

From Task 5's `cross_target_sdk_install_seconds=<n>` (and its run-to-run variance across the spike + any re-run): if `<n>` is a non-trivial fraction of the 20-minute budget, or visibly noisy, add caching (Step 2). If small and steady (the local reference download was ~33 s for 106 MB), **skip caching** and record the number as the justification. Write the decision + number into the verification doc either way.

- [ ] **Step 2 (only if warranted): Add `actions/cache`**

First confirm the install path from the spike log (e.g. `swift sdk list` location; swift.org SDKs land under `~/.swiftpm/swift-sdks`). Then add, before the compile step in the WASM job:

```yaml
      - name: Cache WASM SDK
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        uses: actions/cache@v4
        with:
          path: /root/.swiftpm/swift-sdks
          key: wasm-sdk-6.2.1-482b9f95462b87bedfafca94a092cf9ec4496671ca13b43745097122d20f18af
```

Re-push; confirm the second run logs a cache hit and skips the download. Note: `actions/cache` inside a `container:` job can be finicky (verify `path`/`HOME`); if it misbehaves, fall back to no-cache + retry and record that finding.

- [ ] **Step 3: Commit (only if a change was made)**

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: cache the pinned WASM SDK bundle

Measured download was a meaningful share of the job budget (see verification
record); caching the version+checksum-keyed bundle removes it from the merge path.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Liveness — the gate actually fails (hosted)

Prove the two fail-closed paths redden the WASM job, then revert. Do these on the PR branch as throwaway commits (or a scratch branch), reading the hosted job. The local unit proofs already exist (Task 2 self-tests: `wasm_skip_result sdk_unavailable true == fail`, `count_blocking_failures ... fail:true == 1`); this is the end-to-end confirmation.

**Files:** temporary edits to `.github/workflows/swift-ci.yml` (reverted).

- [ ] **Step 1: Provisioning fail-closed (AC2)**

Temporarily corrupt the checksum in the WASM step's env (flip the last hex char, e.g. `…f18af` → `…f18ae`). Push. Read the WASM job:

Run: `gh run view <id> -R maldrakar/swift-text-engine --log | grep -E "sdk_install|result=fail|mode=cross_target_compile_overall"`
Expected: install fails the checksum, `target=wasm ... result=fail reason=sdk_install_failed blocking=true`, `blocking_failures>=1 exit=1`, **job conclusion `failure`**.
Revert the checksum, push, confirm the job goes green again.

- [ ] **Step 2: Compile fail-closed (AC3)**

Temporarily force a WASM compile failure without touching engine source: in `cross-target-compile.sh`, change the WASM build's `--target "$package_target"` invocation to a bogus target for a single push (e.g. append `-nonexistent` in `compile_wasm_package_for_kind`'s `swift build` line). Push. Read the job:

Expected: `target=wasm ... result=fail reason=compile_failed blocking=true`, `exit=1`, **job conclusion `failure`**.
Revert, push, confirm green. Confirm `git status --short` empty and no stray edits remain.

- [ ] **Step 3: Record both liveness cycles**

Add the two run IDs + the red/green transitions to the verification doc.

---

## Task 8: Docs + verification record

**Files:**
- Modify: `AGENTS.md`
- Create: `docs/superpowers/verification/2026-07-19-wasm-cross-target-blocking-gate.md`

- [ ] **Step 1: Update `AGENTS.md` hard constraint #4**

Change the WASM clause from "proven locally, observed in CI only when a matching SDK is available" to: **WASM + embedded WASM are blocking in CI**, cross-compiled against a swift.org 6.2.1 Swift SDK pinned by URL + checksum, fail-closed on provisioning failure; the "compiles for iOS and WASM with no source changes" invariant is retained.

- [ ] **Step 2: Update `AGENTS.md` CI / package-layout / commands prose**

- CI section: the third job now **compiles and blocks** on WASM (both kinds, both packages), not observes. Explicitly note the one wart: the job/context is still *named* `WASM cross-target observation` while it now blocks, and a follow-up repo-policy slice renames it + updates the `Main` ruleset.
- Package-layout / `cross-target-compile.sh` prose: "WASM … observational" ⇒ blocking, pinned bundle, fail-closed, per-kind (embedded demotable via `CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false`).
- Commands: note the pinned-SDK env (`CROSS_TARGET_WASM_SDK_URL` / `_CHECKSUM`) for the local WASM path.

- [ ] **Step 3: Write the verification record**

Create `docs/superpowers/verification/2026-07-19-wasm-cross-target-blocking-gate.md` with: each local command + output (`--self-test`, `swift test`, `bash -n`, the Task 4 local pin-liveness cycle), the pinned bundle facts (URL, sha256, size, the recompute command `curl -sL <url> | shasum -a 256`), the spike run ID + SDK ids + four per-target results + `cross_target_sdk_install_seconds`, the caching decision + number, both liveness run IDs (AC2/AC3 red→green), and the final all-green PR-head + post-merge push run IDs read at **step level**. Note that the `.sha256` sidecar 404s, so the checksum's provenance is the TLS download from the official host, recomputed locally (the same trust `--checksum` enforces).

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md docs/superpowers/verification/2026-07-19-wasm-cross-target-blocking-gate.md
git commit -m "docs: record WASM blocking-gate verification; update AGENTS.md #4

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Final gate — full local suite + confinement**

Run: `./.github/scripts/cross-target-compile.sh --self-test` → `self_test=pass`.
Run: `swift test` → all green.
Run: `swift build -c release` → `Build complete!`.
Run: `rg -n "Foundation" Sources/TextEngineCore ; echo exit=$?` → empty, `exit=1`.
Run: `git diff --name-only main...HEAD` → only `.github/scripts/cross-target-compile.sh`, `.github/workflows/swift-ci.yml`, `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`, `AGENTS.md`, and the three `docs/superpowers/**` slice files (spec, plan, verification). No `Sources/TextEngineCore` / `Sources/TextEngineReferenceProviders` change.

---

## Closeout (after merge — not a code task)

- Post-merge push run read at **step level**: three required jobs green; WASM job green with four `result=pass blocking=true` lines + `exit=0`; anchor AC7 in this push run (docs-only follow-up PR if needed, per repo habit).
- Add a Slice 46 memory: `MEMORY.md` line + a `slice-46-direction.md` file (status, PRs, hosted run IDs, the deferred rename+ruleset follow-up).
- Post-slice review on a `slice-46-post-slice-review` branch (do not auto-merge it).

---

## Self-Review

**Spec coverage:**
- AC1 (both kinds blocking, per-kind) → Tasks 2, 5. ✓
- AC2 (fail-closed provisioning, live) → Task 2 (unit) + Task 7 Step 1 (hosted). ✓
- AC3 (fail-closed compile, live) → Task 7 Step 2. ✓
- AC4 (version drift stays fail-closed; guard optional) → covered by existing `sdk_unresolved_after_install` behavior; no explicit guard built (Decision 2 makes it optional). Noted: not separately tasked because the fail-closed behavior is already exercised by Task 2's `wasm_skip_result`/`count_blocking_failures` tests and the whole point is that no new code is needed. ✓
- AC5 (self-test + swift test + build + Foundation scan) → Tasks 1–4 + Task 8 Step 5. ✓
- AC6 (governance minimal path; ruleset untouched) → Task 3 (name kept) + Task 8 (prose) + Closeout (follow-up). ✓
- AC7 (multi-run hosted reliability, step level) → Task 5 + Closeout. ✓
- AC8 (AGENTS.md; no engine source) → Task 8 + Task 8 Step 5 confinement. ✓
- AC9 (caching decision evidenced) → Task 6. ✓

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". The one conditional (Task 6 cache YAML) is fully written with an explicit apply/skip rule and a real key. The fallback-ladder branch (Task 5 Step 3) is a concrete env edit. ✓

**Type/name consistency:** `sdk_install_display`, `wasm_kind_blocking`, `wasm_skip_result`, `swift_sdk_install_retry`, `jobSteps`, `wasmJobSteps`, `wasmJobKey`, env names `CROSS_TARGET_WASM_SDK_URL` / `CROSS_TARGET_WASM_SDK_CHECKSUM` / `CROSS_TARGET_WASM_EMBEDDED_BLOCKING` — used identically across tasks. Pair order (2 packages × {ios_device, ios_simulator, wasm, wasm_embedded}) matches `process_package`'s append order. ✓
