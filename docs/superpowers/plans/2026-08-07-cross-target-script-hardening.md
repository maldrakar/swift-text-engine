# Cross-Target Script Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Discharge ledger debt D-1, D-3, D-6 in `.github/scripts/cross-target-compile.sh` and D-2 in `AGENTS.md`, and make every script self-test a standing guarantee enforced by `swift test`.

**Architecture:** All behaviour changes live in one bash script and are proven by its
own `--self-test`, which gains three subshell-isolated scenarios driving the
install ladder and the asymmetric-drift path through two stub seams. A new
XCTest case drives `--self-test` for all four scripts in `.github/scripts`, so
those assertions can fail a build for the first time. A classification of every
function in the script (covered / exempt / derived-harness) is enforced by the
self-test itself.

**Tech Stack:** bash 3.2 (macOS system bash) / bash 5 (hosted container),
Swift 6.2 XCTest with `Foundation.Process`, SwiftPM.

**Spec:** [`docs/superpowers/specs/2026-08-07-cross-target-script-hardening-design.md`](../specs/2026-08-07-cross-target-script-hardening-design.md).
Decisions are cited by number throughout.

## Global Constraints

- **bash 3.2-compatible.** No `declare -A`, no `mapfile`/`readarray`, no
  `${var^^}`. `/usr/bin/env bash` is 3.2.57 on the macOS host and 5.x in the
  hosted container (spec Decision 8).
- **The script has no `set -e`** (`set -uo pipefail`, `:2`). `assert_*` ends a
  failure with `exit 1`, which inside `( … )` terminates only the subshell —
  every scenario must be invoked through `run_scenario` (Decision 5).
- **No `Sources/**` change**, no `.github/workflows/**` change, no budget /
  corpus / gate-registry change. `git diff --quiet main -- Sources/` must exit 0
  at the end (Decision 11).
- **No third-party dependency**; the core stays Foundation-free (the new Swift
  file lives in a test target, which already imports Foundation).
- **Conventional commits**, one logical step per commit: `feat:`, `test:`,
  `refactor:`, `docs:`, `ci:`.
- **Every assertion in this plan is executable and can fail** — this plan is the
  first artifact written under the Decision 10 conventions, and its own
  assertion sites are D-2's discharge evidence. Each check below prints
  `CONFIRMED …` on the expected outcome and `UNEXPECTED …` plus the captured
  output otherwise; none relies on an "expect empty" comment, and no variable is
  used in a block that does not assign it.

---

## File Structure

**Modified**

- `.github/scripts/cross-target-compile.sh` — every behaviour change and every
  new self-test case. One file, because the state model, the ladder, and the
  classification are one unit: the classification's whole job is to describe
  this file's functions.
- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` — loses its private
  `repositoryRoot()` (`:38-44`) and `runProcess` (`:52-75`); call sites unchanged.
- `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` — loses its twin
  `repositoryRoot()` (`:90-99`) and the "Twin of" comment; call sites unchanged.
- `AGENTS.md` — the four plan-assertion conventions; the line recording that the
  four script self-tests are enforced by `swift test`.
- `docs/superpowers/debt-ledger.md` — new row D-14.
- `docs/superpowers/arcs/wrap.md` — `:167` states a fact this slice falsifies.

**Created**

- `Tests/ViewportBenchmarksTests/ProcessSupport.swift` — the single home for
  `repositoryRoot()` and `runProcess`, shared by three test files.
- `Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift` — the table-driven
  enforcement case plus the discovery pin that keeps the table complete.
- `docs/superpowers/verification/2026-08-07-cross-target-script-hardening.md` —
  the evidence record.

**Task order is a dependency chain.** Task 1 builds the only construct that lets
a self-test assertion fail at all; Task 2 makes failures reach `swift test`;
Tasks 3–4 add behaviour proven through that construct; Task 5 classifies the
functions Tasks 1/3/4 introduce, so it must come last among the code tasks.

---

### Task 1: Self-test scaffolding that can actually fail

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh` (globals near `:15`,
  self-test section near `:267`, dispatcher `:704-707`)

**Interfaces:**
- Consumes: nothing.
- Produces: `run_scenario <function-name>` — runs the named function in a
  subshell and exits the script with status 1 if it fails.
  `SELF_TEST_TMP_ROOT` — a `mktemp -d` directory, created once at the top of
  `run_self_test`, removed by an `EXIT` trap in the main shell. Scenario
  functions read it directly.

- [ ] **Step 1: Add the temp root, and a deliberately failing probe wired the naive way**

In `.github/scripts/cross-target-compile.sh`, add after `SELECTED_TARGETS="all"`
(`:16`):

```bash
# Created once at the top of run_self_test; removed by an EXIT trap in the MAIN
# shell. Scenario subshells read it but must never create or delete it: a bash 3.2
# EXIT trap does not fire when a `( ... )` subshell exits, which is exactly what
# keeps the first scenario from deleting the directory the next two still need.
SELF_TEST_TMP_ROOT=""
```

Add immediately before `run_self_test() {` (`:267`):

```bash
# TEMPORARY PROBE -- deleted in Step 5. Exists only to prove the wiring can fail.
scenario_meta_mutation_probe() {
  assert_equal "expected" "actual" "meta_mutation_probe"
}
```

Insert as the first two lines inside `run_self_test() {`:

```bash
  SELF_TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cross-target-self-test.XXXXXX")"
  trap 'rm -rf "$SELF_TEST_TMP_ROOT"' EXIT
```

And insert the probe call directly above the final `echo "self_test=pass"`
(`:411`), deliberately written the naive way:

```bash
  ( scenario_meta_mutation_probe )
```

- [ ] **Step 2: Run the self-test and confirm the defect — a failed assertion is swallowed**

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if printf '%s\n' "$out" | grep -q 'self_test=fail label=meta_mutation_probe' \
  && printf '%s\n' "$out" | grep -q 'self_test=pass' \
  && [ "$rc" -eq 0 ]; then
  echo "RED CONFIRMED: assertion failed, script still exited 0 and printed self_test=pass"
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
```

Expected: `RED CONFIRMED …`. This is the defect the whole slice exists to remove,
reproduced in the construct the rest of the plan depends on.

- [ ] **Step 3: Add `run_scenario` and fix the dispatcher**

Add directly above the probe:

```bash
# Run a scenario function in a SUBSHELL so a stub override cannot leak into
# neighbouring cases -- and propagate its status, because the script runs under
# `set -uo pipefail` with no `set -e`: an `exit 1` from assert_* inside `( ... )`
# ends only the subshell. Never call a scenario bare.
run_scenario() {
  local name="$1"
  ( "$name" ) || exit 1
}
```

Replace the bare call from Step 1 with:

```bash
  run_scenario scenario_meta_mutation_probe
```

Replace the dispatcher (`:704-707`):

```bash
if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test || exit 1
  exit 0
fi
```

The trailing `exit 0` alone masked any path that *returns* non-zero instead of
exiting — the same defect class one level up.

- [ ] **Step 4: Run again and confirm the failure now propagates**

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
leftover="$(ls -d "${TMPDIR:-/tmp}"/cross-target-self-test.* 2>/dev/null | wc -l | tr -d ' ')"
if [ "$rc" -ne 0 ] \
  && printf '%s\n' "$out" | grep -q 'self_test=fail label=meta_mutation_probe' \
  && ! printf '%s\n' "$out" | grep -q 'self_test=pass' \
  && [ "$leftover" -eq 0 ]; then
  echo "GREEN CONFIRMED: rc=$rc, no self_test=pass, no temp debris"
else
  echo "UNEXPECTED rc=$rc leftover=$leftover"; printf '%s\n' "$out"
fi
```

Expected: `GREEN CONFIRMED …`. Record this output verbatim — it is the
meta-mutation evidence AC4 requires, and it also proves Decision 9's cleanup
survives a failing assertion.

- [ ] **Step 5: Delete the probe and confirm a clean pass**

Remove `scenario_meta_mutation_probe` and its `run_scenario` call.

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
leftover="$(ls -d "${TMPDIR:-/tmp}"/cross-target-self-test.* 2>/dev/null | wc -l | tr -d ' ')"
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$out" | grep -q 'self_test=pass' \
  && ! printf '%s\n' "$out" | grep -q 'self_test=fail' \
  && [ "$leftover" -eq 0 ]; then
  echo "CONFIRMED clean: rc=0, pass present, fail absent, no debris"
else
  echo "UNEXPECTED rc=$rc leftover=$leftover"; printf '%s\n' "$out"
fi
```

- [ ] **Step 6: Commit**

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "test: make cross-target self-test failures propagate (subshell status + dispatcher)"
```

---

### Task 2: `swift test` enforces every script self-test

**Files:**
- Create: `Tests/ViewportBenchmarksTests/ProcessSupport.swift`
- Create: `Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift`
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift:38-75`
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:90-99`

**Interfaces:**
- Consumes: Task 1's dispatcher (`run_self_test || exit 1`), which is what makes
  assertion 1 below able to fail.
- Produces: `func repositoryRoot() -> URL` and
  `func runProcess(_ executableURL: URL, _ arguments: [String], stdin: String) throws -> (stdout: String, stderr: String, exitCode: Int32)`,
  both internal to the `ViewportBenchmarksTests` module.

- [ ] **Step 1: Create the shared process support file**

Create `Tests/ViewportBenchmarksTests/ProcessSupport.swift`:

```swift
import Foundation

// Repository root from this file's own path:
// .../Tests/ViewportBenchmarksTests/ProcessSupport.swift -> repo root.
// Single home for the walk that GateFloorTests and WorkflowShapeTests each used to
// carry privately (the latter labelled itself a twin).
func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

// The test target's subprocess launcher. Safe here: ViewportBenchmarksTests runs only
// on the host (Linux CI + local macOS), never on iOS/WASM, which merely compile
// TextEngineCore/ReferenceProviders; nothing here reaches the Foundation-free core.
//
// Feeds `stdin`, reads stdout to EOF, then stderr, then reaps. Sequential reads are
// safe only while a driven process cannot fill a pipe buffer (~64 KiB) on the stream
// that is not being read yet. Current callers: budget derivation (a handful of run
// ids) and the script self-tests, whose worst case is a few KiB -- per-attempt log
// tails are bounded by the scripts' own TAIL_LINES, and warnings go to stderr. A
// future caller that can emit more than a pipe buffer on either stream must read both
// concurrently instead of extending this comment.
func runProcess(_ executableURL: URL, _ arguments: [String], stdin: String) throws
    -> (stdout: String, stderr: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    try stdinPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
    try stdinPipe.fileHandleForWriting.close()

    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return (String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self),
            process.terminationStatus)
}
```

- [ ] **Step 2: Delete both private copies and confirm the target still builds**

In `GateFloorTests.swift`, delete the `private func repositoryRoot()` block
(`:38-44`) and the `private func runProcess(…)` block together with its comment
(`:46-75`). In `WorkflowShapeTests.swift`, delete the "Twin of `repositoryRoot()`"
comment and the function it introduces (`:90-99`). Change no call site.

```bash
swift build --build-tests 2>&1 | tail -5
status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then echo "CONFIRMED: test target builds with one shared copy"
else echo "UNEXPECTED build status=$status"; fi
```

`${PIPESTATUS[0]}` because the build's status, not `tail`'s, is the invariant
(convention 1).

- [ ] **Step 3: Write the enforcement test**

Create `Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift`:

```swift
import Foundation
import XCTest

// Every script in .github/scripts that implements --self-test. Kept honest by
// testTableCoversEveryScriptWithASelfTest below: a new script with a self-test that is
// not enrolled here fails the build, instead of silently joining the set of checks
// that cannot fail.
private let selfTestScripts = [
    "cross-target-compile.sh",
    "derive-gate-budgets.sh",
    "harvest-gate-corpus.sh",
    "detect-docs-only-pr.sh",
]

private func scriptsDirectory() -> URL {
    repositoryRoot().appendingPathComponent(".github/scripts")
}

final class ScriptSelfTestTests: XCTestCase {
    // Three assertions per script, none redundant: the exit status catches a hard
    // failure; the pass token catches a script degenerating into a silent no-op; the
    // absence of a fail token catches an assertion whose `exit 1` was swallowed by a
    // subshell -- the defect Task 1 reproduced and fixed.
    func testEveryScriptSelfTestPasses() throws {
        XCTAssertFalse(selfTestScripts.isEmpty, "empty table would pass vacuously")
        for name in selfTestScripts {
            let scriptURL = scriptsDirectory().appendingPathComponent(name)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: scriptURL.path),
                "script not found: \(scriptURL.path)")

            let result = try runProcess(
                URL(fileURLWithPath: "/usr/bin/env"),
                ["bash", scriptURL.path, "--self-test"],
                stdin: "")
            let detail = """
                script: \(scriptURL.path)
                exit: \(result.exitCode)
                --- stdout ---
                \(result.stdout)
                --- stderr ---
                \(result.stderr)
                """

            XCTAssertEqual(result.exitCode, 0, "self-test exited non-zero\n\(detail)")
            XCTAssertTrue(
                result.stdout.contains("self_test=pass"),
                "no self_test=pass line\n\(detail)")
            XCTAssertFalse(
                result.stdout.contains("self_test=fail"),
                "a self_test=fail line survived a zero exit\n\(detail)")
        }
    }

    func testTableCoversEveryScriptWithASelfTest() throws {
        let directory = scriptsDirectory()
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var discovered: Set<String> = []
        for entry in entries where entry.hasSuffix(".sh") {
            let source = try String(
                contentsOf: directory.appendingPathComponent(entry), encoding: .utf8)
            if source.contains("--self-test") { discovered.insert(entry) }
        }
        XCTAssertFalse(discovered.isEmpty, "no script with a self-test was discovered")
        XCTAssertEqual(
            discovered, Set(selfTestScripts),
            "enroll every script that has a --self-test in selfTestScripts, or the new "
                + "one's assertions cannot fail a build")
    }
}
```

- [ ] **Step 4: Run the new tests and confirm they pass**

```bash
swift test --filter ScriptSelfTestTests 2>&1 | tail -15
status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then echo "CONFIRMED: all four script self-tests pass under swift test"
else echo "UNEXPECTED status=$status"; fi
```

- [ ] **Step 5: Mutation A — prove the swallowed-failure assertion bites**

Insert one line directly above `echo "self_test=pass"` in
`.github/scripts/cross-target-compile.sh` (exit status deliberately untouched):

```bash
  echo "self_test=fail label=injected_mutation"
```

```bash
swift test --filter ScriptSelfTestTests 2>&1 | tail -15
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then echo "RED CONFIRMED (mutation A): status=$status"
else echo "UNEXPECTED: mutation A did not redden"; fi
git checkout -- .github/scripts/cross-target-compile.sh
if git diff --quiet -- .github/scripts/cross-target-compile.sh; then echo "reverted"
else echo "UNEXPECTED: mutation A still applied"; fi
```

- [ ] **Step 6: Mutation B — prove the exit-status assertion bites**

Add `return 1` as the last line inside `run_self_test` (after
`echo "self_test=pass"`). Task 1's dispatcher turns that into `exit 1`.

```bash
swift test --filter ScriptSelfTestTests 2>&1 | tail -15
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then echo "RED CONFIRMED (mutation B): status=$status"
else echo "UNEXPECTED: mutation B did not redden"; fi
git checkout -- .github/scripts/cross-target-compile.sh
if git diff --quiet -- .github/scripts/cross-target-compile.sh; then echo "reverted"
else echo "UNEXPECTED: mutation B still applied"; fi
```

Mutation B also proves Task 1's dispatcher fix from the Swift side: before it,
a `return 1` was masked by the trailing `exit 0`.

- [ ] **Step 7: Run the full suite and commit**

```bash
swift test 2>&1 | tail -8
status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then echo "CONFIRMED: full suite green"; else echo "UNEXPECTED status=$status"; fi
```

```bash
git add Tests/ViewportBenchmarksTests/
git commit -m "test: enforce every script self-test from swift test, share process helpers"
```

---

### Task 3: Per-attempt install logs and the ladder stub seam (D-3)

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh` (`swift_sdk_install_retry`
  `:515-534`, `prepare_wasm_sdk:565-568`, self-test section)

**Interfaces:**
- Consumes: `run_scenario`, `SELF_TEST_TMP_ROOT` (Task 1).
- Produces: `attempt_logfile <logfile> <index>` → prints `<logfile>.attempt-<index>`;
  `run_swift_sdk_install <args…>` → the single toolchain call, the ladder's stub
  target; `swift_sdk_install_retry <url> <checksum> <logfile> <label>` — note the
  **fourth** parameter; `assert_file_exists <path> <label>`.

- [ ] **Step 1: Write the two failing ladder scenarios and the file assertion helper**

Add after `assert_resolver_missing` (`:259-265`):

```bash
assert_file_exists() {
  local path="$1" label="$2"
  if [[ ! -f "$path" ]]; then
    echo "self_test=fail label=$label expected=file_exists actual=missing path=$path"
    exit 1
  fi
}
```

Add before `run_self_test`:

```bash
# The ladder recovers on the third attempt. Each attempt must leave its OWN log:
# with one shared logfile the first two attempts' output is overwritten and lost.
scenario_ladder_recovers_after_two_failures() {
  local logfile="${SELF_TEST_TMP_ROOT}/recover.log"
  local counter="${SELF_TEST_TMP_ROOT}/recover.count"
  local status
  CROSS_TARGET_SDK_INSTALL_BACKOFF=0
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
  assert_equal "1" "$(printf '%s\n' "$out" | grep -c 'exhaust-attempt-2 log tail')" \
    "ladder_exhaust_attempt2_label"
}
```

Register both directly above `echo "self_test=pass"`:

```bash
  run_scenario scenario_ladder_recovers_after_two_failures
  run_scenario scenario_ladder_exhausts_and_prints_every_tail
```

- [ ] **Step 2: Run and confirm the red**

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'self_test=fail label=ladder_recover'; then
  echo "RED CONFIRMED: ladder scenarios fail before the fix"; printf '%s\n' "$out" | grep 'self_test=fail'
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
```

Expected: a `self_test=fail` line naming a `ladder_recover_*` label —
`attempt_logfile` and `run_swift_sdk_install` do not exist yet, and the ladder
writes a single shared logfile.

- [ ] **Step 3: Add the pure helper, the seam, and its direct assertion**

Add beside the other pure helpers, above the self-test section (after
`wasm_install_precheck`, `:227`):

```bash
# Per-attempt install log path. Pure: naming is self-tested rather than inlined in
# the retry loop.
attempt_logfile() {
  printf '%s.attempt-%s' "$1" "$2"
}
```

Add directly above `swift_sdk_install_retry` (`:515`):

```bash
# The one toolchain call the ladder makes. Its ONLY purpose is to be replaceable:
# --self-test overrides it inside a scenario subshell. Exempt from coverage by
# construction -- it IS the process call.
run_swift_sdk_install() {
  swift "$@"
}
```

Add to `run_self_test`, beside the other pure-helper assertions:

```bash
  assert_equal "/tmp/x.log.attempt-2" "$(attempt_logfile /tmp/x.log 2)" "attempt_logfile_path"
```

- [ ] **Step 4: Rewrite the ladder to use both**

Replace the body of `swift_sdk_install_retry` (`:515-534`) with:

```bash
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
```

In `prepare_wasm_sdk`, pass the label and drop the caller's tail (`:565-568`):

```bash
      if ! swift_sdk_install_retry "$url" "$checksum" "${logfile}.install" "${kind}-sdk-install"; then
        skip="sdk_install_failed"
        WASM_BUNDLE_FAILED_REASON="sdk_install_failed"
```

(The `print_log_tail "${kind}-sdk-install" "${logfile}.install"` line is deleted;
the global is renamed in Task 4.)

- [ ] **Step 5: Run and confirm green**

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'self_test=pass' \
  && ! printf '%s\n' "$out" | grep -q 'self_test=fail'; then
  echo "GREEN CONFIRMED: ladder scenarios pass"
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
```

- [ ] **Step 6: Commit**

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "fix: give each SDK install attempt its own log and print every tail"
```

---

### Task 4: Truthful asymmetric-drift diagnosis (D-1)

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh` (`wasm_install_precheck`
  `:220-227`, globals `:427`, `prepare_wasm_sdk:539-592`, self-test section)

**Interfaces:**
- Consumes: `run_scenario`, `SELF_TEST_TMP_ROOT` (Task 1), `run_swift_sdk_install`
  (Task 3).
- Produces: `WASM_BUNDLE_STATE` (replaces `WASM_BUNDLE_FAILED_REASON`);
  `wasm_install_precheck <url> <state>` with the fifth contract row;
  `assert_contains <needle> <haystack> <label>`.

- [ ] **Step 1: Write the failing precheck row and the end-to-end drift scenario**

Add beside the other assertion helpers:

```bash
assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if ! printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
    echo "self_test=fail label=$label expected_substring=$needle"
    printf '%s\n' "$haystack"
    exit 1
  fi
}
```

Add the fifth contract row beside the existing precheck assertions (`:387-401`):

```bash
  assert_equal "sdk_unresolved_after_install" \
    "$(wasm_install_precheck http://b bundle_installed_ok)" \
    "precheck_installed_bundle_reports_unresolved"
```

Add the scenario before `run_self_test`:

```bash
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
  out="$(prepare_wasm_sdk wasm_embedded "${SELF_TEST_TMP_ROOT}/drift-embedded.log" 2>&1)"
  assert_equal "sdk_unresolved_after_install" "$WASM_SKIP_WASM_EMBEDDED" "drift_second_kind_reason"
  assert_equal "1" "$(cat "$counter")" "drift_single_install"
  assert_contains "reason=bundle_installed_id_unresolved" "$out" "drift_message_truthful"
}
```

Register it above `echo "self_test=pass"`:

```bash
  run_scenario scenario_asymmetric_drift_reports_truth
```

- [ ] **Step 2: Run and confirm the red — the defect reproduced**

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'self_test=fail label=\(precheck_installed_bundle\|drift_\)'; then
  echo "RED CONFIRMED"; printf '%s\n' "$out" | grep 'self_test=fail'
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
```

Expected first failure: `precheck_installed_bundle_reports_unresolved`
(`expected=sdk_unresolved_after_install actual=`). Record it, then comment out
that one assertion and re-run to reach the scenario's own reds — expect
`drift_state_recorded` (`actual=` empty), and after that assertion is
temporarily commented too, `drift_second_kind_reason`
(`actual=sdk_install_failed`) with `drift_single_install` showing **4**: the
first install plus three ladder attempts against the already-installed bundle.
Restore every commented assertion before Step 3.

- [ ] **Step 3: Rename the global and record the success state**

Rename all four occurrences (`:427` declaration, and `:556`, `:567`, `:574`
inside `prepare_wasm_sdk`) from `WASM_BUNDLE_FAILED_REASON` to
`WASM_BUNDLE_STATE`, then add the success-path recording. The install branch
becomes:

```bash
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
```

- [ ] **Step 4: Add the fifth precheck row and the truthful message**

Replace `wasm_install_precheck` (`:220-227`):

```bash
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
```

Replace the short-circuit message block (`:557-562`):

```bash
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
```

Also update the doc comment above `wasm_install_precheck` (`:209-219`) to list
the new state, and the comment inside `prepare_wasm_sdk` (`:544-553`) which
still says the short-circuit exists only for definitive failures.

- [ ] **Step 5: Run and confirm green, plus the scoped rename check**

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'self_test=pass' \
  && ! printf '%s\n' "$out" | grep -q 'self_test=fail'; then
  echo "GREEN CONFIRMED: drift scenario and precheck row pass"
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
```

```bash
if grep -rq 'WASM_BUNDLE_FAILED_REASON' .github/scripts/; then
  echo "UNEXPECTED: the old global name survives in .github/scripts"
  grep -rn 'WASM_BUNDLE_FAILED_REASON' .github/scripts/
else
  echo "CONFIRMED: rename complete inside .github/scripts"
fi
```

Scoped to `.github/scripts/` deliberately: the old name legitimately survives in
11 places under `docs/` (slice 47's plan and review, and the arc line Task 6
corrects), and rewriting historical evidence is not allowed.

- [ ] **Step 6: Commit**

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "fix: report asymmetric SDK drift truthfully instead of a second failed install"
```

---

### Task 5: Pin the coverage/exemption classification (D-6)

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh` (section header `:41-43`,
  new top-level arrays, new helpers, `run_self_test`)

**Interfaces:**
- Consumes: every function introduced by Tasks 1, 3, 4.
- Produces: `SELF_TEST_COVERED` / `SELF_TEST_EXEMPT` arrays;
  `defined_functions <file>`, `is_harness_function <name>`,
  `self_test_body <file>`, `body_references_function <name> <body>`,
  `assert_function_defined <name> <defined-list> <label>`.

- [ ] **Step 1: Add the classification helpers**

Add directly above the self-test section:

```bash
# Every function defined in a script file, one name per line. Pure.
defined_functions() {
  grep -oE '^[a-z_]+\(\) \{' "$1" | sed 's/() {//'
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
```

- [ ] **Step 2: Declare the two hand-maintained sets**

Replace the section header (`:41-43`) and add the arrays:

```bash
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
```

The old `# Pure helpers (covered by --self-test, no toolchain required)` header is
replaced by the block above, so the file states the fact once.

- [ ] **Step 3: Enforce the partition and the coverage check**

Add inside `run_self_test`, directly above `echo "self_test=pass"`:

```bash
  # --- classification (D-6) ---
  local script_path defined body fn entry name classified
  script_path="${BASH_SOURCE[0]}"
  defined="$(defined_functions "$script_path")"
  body="$(self_test_body "$script_path")"

  # Direction 1: every defined function is classified.
  for fn in $defined; do
    if is_harness_function "$fn"; then continue; fi
    classified=0
    for name in "${SELF_TEST_COVERED[@]}"; do
      [[ "$name" == "$fn" ]] && classified=1
    done
    for entry in "${SELF_TEST_EXEMPT[@]}"; do
      [[ "${entry%%$'\t'*}" == "$fn" ]] && classified=1
    done
    assert_equal "1" "$classified" "classified_${fn}"
  done

  # Direction 2: no phantom names, and every exempt entry carries a justification.
  for name in "${SELF_TEST_COVERED[@]}"; do
    assert_function_defined "$name" "$defined" "covered_defined_${name}"
  done
  for entry in "${SELF_TEST_EXEMPT[@]}"; do
    assert_function_defined "${entry%%$'\t'*}" "$defined" "exempt_defined_${entry%%$'\t'*}"
    if [[ "$entry" != *$'\t'* || -z "${entry#*$'\t'}" ]]; then
      echo "self_test=fail label=exempt_justified_${entry} expected=justification actual=none"
      exit 1
    fi
  done

  # Coverage: every covered function is really referenced by the self-test's source.
  for name in "${SELF_TEST_COVERED[@]}"; do
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
```

- [ ] **Step 4: Run and confirm the classification is complete**

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'self_test=pass' \
  && ! printf '%s\n' "$out" | grep -q 'self_test=fail'; then
  echo "CONFIRMED: every function classified and every covered name referenced"
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
```

A `classified_<fn>` or `covered_but_unreferenced` failure here is the check
working: fix the arrays, not the check.

- [ ] **Step 5: Mutation 1 — an unclassified function must fail the partition**

Append to the end of the script (before the dispatcher):

```bash
dummy_unclassified() {
  :
}
```

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'self_test=fail label=classified_dummy_unclassified'; then
  echo "RED CONFIRMED (partition)"
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
git checkout -- .github/scripts/cross-target-compile.sh
if git diff --quiet -- .github/scripts/cross-target-compile.sh; then echo "reverted"; else echo "UNEXPECTED: still applied"; fi
```

- [ ] **Step 6: Mutation 2 — token matching, not substring**

Add `resolve_wasm_sdk_id` to `SELF_TEST_COVERED` and delete its `SELF_TEST_EXEMPT`
row.

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'covered_but_unreferenced fn=resolve_wasm_sdk_id'; then
  echo "RED CONFIRMED (token matching): resolve_wasm_sdk_id_from_list did not satisfy it"
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
git checkout -- .github/scripts/cross-target-compile.sh
if git diff --quiet -- .github/scripts/cross-target-compile.sh; then echo "reverted"; else echo "UNEXPECTED: still applied"; fi
```

This is the sharpest of the four mutations: `resolve_wasm_sdk_id_from_list`
appears four times in the self-test and the drift scenario *defines* a stub named
`resolve_wasm_sdk_id`. Only token matching plus definition-stripping makes it red.

- [ ] **Step 7: Mutation 3 — comments are not references**

In `run_self_test`, comment out the **bare `mark_not_requested` call** (today at
`:341`, between the `invalid_target_selection` assertion and the
`not_requested_result` one), so it reads `  # mark_not_requested`. The name then
survives inside that comment and nowhere else in the self-test's source.

Use this function, not another: `mark_not_requested` is the only covered helper
with **exactly one** reference in the self-test region (measured — the others
have 2–6, so commenting one call leaves the rest and the mutation would not
redden). Its reference is also a bare call, not part of a multi-line
`assert_equal`, so a single line carries the whole mutation.

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'covered_but_unreferenced fn=mark_not_requested'; then
  echo "RED CONFIRMED (comment stripping)"
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
git checkout -- .github/scripts/cross-target-compile.sh
if git diff --quiet -- .github/scripts/cross-target-compile.sh; then echo "reverted"; else echo "UNEXPECTED: still applied"; fi
```

- [ ] **Step 8: Mutation 4 — a phantom name must fail**

Add `ghost_helper` to `SELF_TEST_COVERED`.

```bash
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'label=covered_defined_ghost_helper'; then
  echo "RED CONFIRMED (phantom name)"
else
  echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"
fi
git checkout -- .github/scripts/cross-target-compile.sh
if git diff --quiet -- .github/scripts/cross-target-compile.sh; then echo "reverted"; else echo "UNEXPECTED: still applied"; fi
```

- [ ] **Step 9: Run the whole suite and commit**

```bash
swift test 2>&1 | tail -8
status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then echo "CONFIRMED: suite green with the classification enforced"
else echo "UNEXPECTED status=$status"; fi
```

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "test: pin the self-test coverage/exemption classification for every function"
```

---

### Task 6: Conventions, docs, and the verification record (D-2)

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/debt-ledger.md`
- Modify: `docs/superpowers/arcs/wrap.md:167`
- Create: `docs/superpowers/verification/2026-08-07-cross-target-script-hardening.md`

**Interfaces:**
- Consumes: the evidence recorded in Tasks 1–5.
- Produces: nothing code-facing.

- [ ] **Step 1: Add the four plan-assertion conventions to `AGENTS.md`**

In the `## Development workflow ("slices")` section, after the "Conventions that
matter" list, add:

```markdown
### Plan-assertion conventions (D-2)

A plan's own checks must be able to fail. Slice 47's plan carried 16 of 29
assertion sites that could not fail and 4 that could not pass; alertness is not
a control, so the rules are written down:

1. Never put a check on the left of a pipe whose right side is
   `tail`/`tee`/`jq`/`wc`/`rg` — the pipeline's status is the right side's, and a
   script's own `set -o pipefail` does not reach the invoking shell. Use
   `${PIPESTATUS[0]}`, or do not pipe.
2. Never write `echo "…=$?"` after a command whose exit status is insensitive to
   the invariant. `git diff --name-only`, `git status`, `gh pr list`, `jq`,
   `sed -i`, and every pipeline exit 0 regardless; `rg`/`grep` exit 1 on **no**
   match, so the desired outcome reads as a failure. Assert with
   `[ -z "$(…)" ]`, `git diff --quiet`, or an `if`/`else` that prints both branches.
3. A plan must not assert its own HEAD commit (committing the plan changes it),
   and must not both mandate inserting a string and assert zero occurrences of it.
4. A variable used in a command block must be assigned in that same block, or the
   block must open with `: "${VAR:?}"`. Each Bash invocation is a fresh shell:
   slice 47's `$SCRATCH` was defined in prose and used at 23 command sites, where
   `> "$SCRATCH/x.txt"` resolves to `/x.txt`.
```

- [ ] **Step 2: Record that the self-tests are now enforced**

In the `## Commands` section of `AGENTS.md`, directly under the
`cross-target-compile.sh --self-test` line, add:

```markdown
# All four scripts' --self-test are also driven by `swift test`
# (Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift), so an assertion in any
# of them can fail the build. Enroll a new self-tested script in that table.
```

- [ ] **Step 3: Add ledger row D-14 and correct the stale arc line**

Append to `docs/superpowers/debt-ledger.md`:

```markdown
| D-14 | [slice 51 spec](specs/2026-08-07-cross-target-script-hardening-design.md), Decision 8 | P3 | The coverage/exemption classification is pinned for `cross-target-compile.sh` only; `derive-gate-budgets.sh`, `harvest-gate-corpus.sh`, and `detect-docs-only-pr.sh` now have their self-tests enforced by `swift test` but carry no classification, so a new unexercised function in any of them is silent | open |
```

In `docs/superpowers/arcs/wrap.md:167`, replace the clause asserting
`WASM_BUNDLE_FAILED_REASON` "still stores failures only" with a note that slice
51 renamed it to `WASM_BUNDLE_STATE` and added the `bundle_installed_ok` state.

```bash
if grep -q 'WASM_BUNDLE_FAILED_REASON' docs/superpowers/arcs/wrap.md; then
  echo "UNEXPECTED: the arc still states the falsified fact"
  grep -n 'WASM_BUNDLE_FAILED_REASON' docs/superpowers/arcs/wrap.md
else
  echo "CONFIRMED: arc line updated"
fi
```

- [ ] **Step 4: Run the full local verification block and record it**

Create `docs/superpowers/verification/2026-08-07-cross-target-script-hardening.md`
and paste each command with its real output. Run them in one shell:

```bash
swift test 2>&1 | tail -5; test_status=${PIPESTATUS[0]}
swift build -c release 2>&1 | tail -3; build_status=${PIPESTATUS[0]}
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tail -3; gate_status=${PIPESTATUS[0]}
echo "test=$test_status build=$build_status gate=$gate_status"
```

```bash
out="$(./.github/scripts/cross-target-compile.sh --self-test)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'self_test=pass' \
  && ! printf '%s\n' "$out" | grep -q 'self_test=fail'; then echo "self-test OK"
else echo "UNEXPECTED rc=$rc"; printf '%s\n' "$out"; fi
```

```bash
if [ -z "$(rg -n 'Foundation' Sources/TextEngineCore)" ]; then echo "foundation-free OK"
else echo "UNEXPECTED: Foundation in the core"; rg -n 'Foundation' Sources/TextEngineCore; fi
if git diff --quiet main -- Sources/; then echo "sources untouched OK"
else echo "UNEXPECTED: Sources changed"; git diff --stat main -- Sources/; fi
```

```bash
./.github/scripts/cross-target-compile.sh --targets ios 2>&1 | tail -6
ios_status=${PIPESTATUS[0]}
if [ "$ios_status" -eq 0 ]; then echo "ios compile OK"; else echo "UNEXPECTED ios status=$ios_status"; fi
```

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs/
git commit -m "docs: add plan-assertion conventions, ledger D-14, and slice 51 verification record"
```

- [ ] **Step 6: Open the PR and record hosted evidence**

Push the branch and open one PR for the slice. After the PR-head run finishes,
read **step-level** logs (a green job can hide a dead step) and record in the
verification document: the three required job conclusions, the twelve
`gate=pass` lines, and — from the WASM job — exactly one
`cross_target_sdk_install_seconds=… attempts=1` line plus four
`result=pass … blocking=true` WASM lines (two kinds × two packages), which is
what proves the happy path survived the ladder rewrite (AC8). Repeat for the
post-merge `push` run.

---

## Self-Review

**Spec coverage.** Decision 1 → Task 4 Step 4; Decision 2 → Task 4 Step 3;
Decision 3 → Task 4 Step 4; Decision 4 → Task 3 Steps 3–4; Decision 5 → Task 1
Steps 3–4 and Task 3/4 scenarios; Decision 6 → Task 2; Decision 7 → Task 5
Steps 2–3; Decision 8 → Task 5 Step 1 (four rules), Steps 6–7 (their mutations),
and the bash 3.2 rule in Global Constraints + the TAB-string arrays; Decision 9 →
Task 1 Steps 1/4; Decision 10 → Task 6 Step 1; Decision 11 → Task 6 Step 4.
AC1 → Task 4 Steps 1–2; AC2 → Task 4 Steps 1–5; AC3 → Task 4 Step 4; AC4 → Task
1 Steps 2–4 and Task 3; AC5 → Task 5; AC6 → Task 2; AC7 → Task 6 Steps 1–4;
AC8 → Task 6 Step 6.

**Two deliberate deviations from the spec's prose**, both narrowing rather than
widening scope:

1. The spec expected a *named wrapper* for the `usage` check because
   `assert_command_success` runs `"$@"` and cannot take a pipeline. The plan
   inlines the check in `run_self_test` instead: that needs no new function
   **and** keeps `usage` genuinely referenced by the self-test's own source, so
   it can be classified covered rather than exempt.
2. The spec's AC2 says the pre-fix drift red shows "the counter reads 2". The
   plan records **4** (the first install plus three ladder attempts against the
   already-installed bundle, at the default `CROSS_TARGET_SDK_INSTALL_ATTEMPTS=3`).
   The symptom is the spec's; only the arithmetic was approximate, and the
   verification record carries the measured number.

**Placeholder scan.** No TBD/TODO; every step carries the literal code or the
literal command it needs.

**Four constructs were executed against the real script before this plan
shipped**, because a plan whose own mechanism is fiction is the failure mode D-2
exists to prevent:

- the `self_test_body` extraction yields 145 lines from today's `run_self_test`;
- token matching reports `resolve_wasm_sdk_id` **not** referenced while
  `resolve_wasm_sdk_id_from_list` (4 occurrences) is — so Task 5 Step 6 is a real
  red, not a hoped-for one;
- definition-stripping removes a scenario's `resolve_wasm_sdk_id() {` /
  `run_swift_sdk_install() {` stubs while keeping a genuine `prepare_wasm_sdk`
  call, which is what keeps that same mutation sharp after Task 4 adds the stubs;
- the Step 7 mutation was simulated on a copy: commenting `:341` leaves
  `mark_not_requested` unreferenced and the check reddens. The first candidate
  (`sdk_install_display`) was **rejected by measurement** — two call sites, both
  on continuation lines.

**Type/name consistency.** `run_scenario`, `SELF_TEST_TMP_ROOT`,
`attempt_logfile`, `run_swift_sdk_install`, `WASM_BUNDLE_STATE`,
`bundle_installed_ok`, `reason=bundle_installed_id_unresolved`,
`assert_file_exists`, `assert_contains`, `assert_function_defined`,
`defined_functions`, `is_harness_function`, `self_test_body`,
`body_references_function`, `repositoryRoot`, `runProcess`, `selfTestScripts` are
each spelled identically at every definition and use site. The four-argument
`swift_sdk_install_retry` is introduced in Task 3 Step 4 and its only production
call site is updated in the same step; the scenarios in Tasks 3 and 4 pass four
arguments.

**Convention self-audit (D-2's own evidence).** No check sits on the left of a
pipe: every pipeline in this plan ends in `grep -q`/`grep -c`/`tail`, and where
`tail` is last the status is read from `${PIPESTATUS[0]}`. No `echo "…=$?"` after
an insensitive command: `rg`/`grep -r` results are asserted through `if`/`else`
branches that print both outcomes, and `git diff --quiet` replaces
`git diff --stat`. No step asserts its own HEAD commit. No step both mandates
inserting a string and asserts zero occurrences of it — the two mutation steps
insert a string, assert the *test* reddens, revert, and assert the revert with
`git diff --quiet`. Every block that reads `$out`, `$rc`, `$status`, `$leftover`,
`$counter`, or `$logfile` assigns it in that same block.
