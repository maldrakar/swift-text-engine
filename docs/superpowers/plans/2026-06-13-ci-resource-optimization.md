# CI Resource Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move avoidable Swift CI work off macOS while preserving host gates, iOS blocking checks, WASM observation, Linux RSS observation, and verification evidence.

**Architecture:** Keep `TextEngineCore` untouched. Split platform-specific CI responsibilities by actual runner need: Linux Swift container for host/benchmark/WASM work, macOS only for iOS `xcodebuild`. Add target selection to the existing cross-target helper rather than creating two unrelated scripts, make benchmark executable Darwin/Glibc entry points host-conditional, and keep Linux SwiftPM artifacts out of the checked-out workspace with explicit scratch paths.

**Tech Stack:** Swift Package Manager, XCTest, Swift 6.2.1, Bash, GitHub Actions, Docker `swift:6.2.1-bookworm`, Darwin Mach RSS, Linux `/proc/self/statm`.

---

## File Structure

- Modify `.github/scripts/cross-target-compile.sh`: add `--targets all|ios|wasm`, keep default `all`, make not-requested targets explicit and nonblocking, extend self-tests, and put WASM SwiftPM build artifacts under a temporary scratch path.
- Modify `Sources/ViewportBenchmarks/main.swift`: replace the Darwin-only import and qualified `Darwin.exit` call with portable Darwin/Glibc imports and unqualified `exit`.
- Modify `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`: replace unconditional `import Darwin` with conditional Darwin/Linux imports and Linux RSS collection.
- Modify `.github/workflows/swift-ci.yml`: add docs-only path filters, move host job to Linux Swift container, split cross-target CI into macOS iOS-only and Linux WASM-only jobs.
- Modify `AGENTS.md`: update commands and CI topology documentation.
- Create `docs/superpowers/verification/2026-06-13-ci-resource-optimization.md`: record local, container, PR, and post-merge evidence or exact hosted blocker.

No changes are planned for `Sources/TextEngineCore`, `Tests/TextEngineCoreTests`, or `Package.swift`.

## Scope Check

This plan covers one slice: CI resource optimization. It intentionally does not implement variable-height mutation/indexed providers, hosted WASM promotion to blocking, branch protection, self-hosted runners, or benchmark budget retuning unless hosted Linux x86_64 evidence proves a retune is required.

### Task 1: Preflight Current State

**Files:**
- Read: `docs/superpowers/specs/2026-06-13-ci-resource-optimization-design.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `.github/scripts/cross-target-compile.sh`
- Read: `Sources/ViewportBenchmarks/main.swift`
- Read: `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`
- Read: `AGENTS.md`

- [x] **Step 1: Confirm branch and clean state**

Run:

```bash
git status --short --branch
git log --oneline --decorate -3
```

Expected:

```text
## slice-16-ci-resource-optimization
```

No modified or untracked files should be present before implementation. Do not require a specific commit SHA in the expected output, because this plan may be revised before implementation.

- [x] **Step 2: Confirm the pre-change workflow still has the known macOS-only issues**

Run:

```bash
rg -n "runs-on: macos-latest|xcodebuild -version|machdep.cpu.brand_string|run: \./\.github/scripts/cross-target-compile\.sh$" .github/workflows/swift-ci.yml
```

Expected: matches for the host job on `macos-latest`, `xcodebuild -version` in both metadata locations, `machdep.cpu.brand_string` in the PR observation step, and the unsplit cross-target helper invocation.

- [x] **Step 3: Confirm `--targets` is not implemented yet**

Run:

```bash
set +e
./.github/scripts/cross-target-compile.sh --targets wasm >/tmp/slice-16-pre-targets.out 2>&1
status=$?
set -e
cat /tmp/slice-16-pre-targets.out
echo "status=${status}"
test "$status" -eq 2
rg -n "Usage:" /tmp/slice-16-pre-targets.out
```

Expected: status `2` and usage text. This is the failing pre-change proof for the helper target-selection task.

- [x] **Step 4: Confirm Linux container availability before Linux-specific implementation**

Run:

```bash
docker info >/tmp/slice-16-docker-info.out 2>&1
cat /tmp/slice-16-docker-info.out | sed -n '1,20p'
docker run --rm swift:6.2.1-bookworm bash -lc 'swift --version && git --version && uname -m && cat /etc/os-release | sed -n "1,4p"'
```

Expected when Docker is available: Docker info exits `0`, the container prints Swift 6.2.1, Git version, Linux architecture, and Debian Bookworm OS metadata. If Docker daemon is unavailable, stop execution and report that Slice 16 implementation is blocked on required local Linux-container verification.

- [x] **Step 5: Confirm Linux build currently fails because of Darwin-only benchmark imports**

Run:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace swift:6.2.1-bookworm bash -lc 'swift build -c release --scratch-path /tmp/slice-16-linux-build-before' >/tmp/slice-16-linux-build-before.out 2>&1
status=$?
cat /tmp/slice-16-linux-build-before.out | tail -40
echo "status=${status}"
test "$status" -ne 0
rg -n "no such module 'Darwin'|cannot find.*Darwin" /tmp/slice-16-linux-build-before.out
```

Expected: nonzero status and a compile error caused by the benchmark executable importing Darwin-only APIs on Linux (`Sources/ViewportBenchmarks/main.swift` and/or `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`). This is the failing pre-change proof for the Linux benchmark portability task.

### Task 2: Add Cross-Target Helper Target Selection

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh`

- [x] **Step 1: Add failing self-test expectations for target selection**

Edit `.github/scripts/cross-target-compile.sh` inside `run_self_test()` after the existing `summary_ios_fail` assertion and before the WASM SDK resolver assertions:

```bash
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
  mark_not_requested ios_device
  assert_equal "skipped" "$LAST_RESULT" "not_requested_result"
  assert_equal "not_requested" "$LAST_REASON" "not_requested_reason"
  assert_equal "false" "$LAST_BLOCKING" "not_requested_blocking"
  assert_equal "0" "$(count_blocking_failures skipped:false)" "not_requested_not_blocking"
```

Also add these helper assertions near the existing `assert_command_success` / `assert_command_failure` helpers if they are not already present in the file:

```bash
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
```

- [x] **Step 2: Run the self-test and verify it fails**

Run:

```bash
set +e
./.github/scripts/cross-target-compile.sh --self-test >/tmp/slice-16-targets-red.out 2>&1
status=$?
set -e
cat /tmp/slice-16-targets-red.out
echo "status=${status}"
test "$status" -ne 0
```

Expected: nonzero status because `parse_target_selection`, `target_requested`, `mark_not_requested`, or `LAST_BLOCKING` is not implemented yet.

- [x] **Step 3: Implement target selection and not-requested target output**

Patch `.github/scripts/cross-target-compile.sh` with these concrete changes.

Update usage:

```bash
usage() {
  cat <<'EOF'
Usage:
  cross-target-compile.sh
  cross-target-compile.sh --targets all|ios|wasm
  cross-target-compile.sh --self-test
EOF
}
```

Add globals after `TAIL_LINES=...`:

```bash
SELECTED_TARGETS="all"
```

Add pure helpers after `build_summary()`:

```bash
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
```

Change the compile-state globals to include `LAST_BLOCKING`:

```bash
LAST_RESULT=""
LAST_REASON=""
LAST_BLOCKING=""
IOS_SCHEME_STATUS=""
```

In `compile_ios_target()`, set `LAST_BLOCKING="true"` before returning:

```bash
compile_ios_target() {
  local target_name="$1" destination="$2" logfile="$3"
  LAST_BLOCKING="true"
  echo "cross_target_command target=${target_name} cmd=\"xcodebuild build -scheme ${SCHEME} -destination '${destination}'\""
  ...
}
```

In `compile_wasm_target()`, set `LAST_BLOCKING="false"` before any return:

```bash
compile_wasm_target() {
  local kind="$1" target_name="$2" logfile="$3" sdk_id url_var url
  LAST_BLOCKING="false"
  ...
}
```

Replace the body of `main()` after the `cross_target_swift_version` echo with the complete selected-target branch, summary, and exit handling. Keep the final `build_summary` and `exit "$exit_code"` lines; dropping them would make CI lose the stable summary row and the blocking-failure exit status.

```bash
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
```

In `compile_wasm_target()`, put SwiftPM build artifacts under a temporary scratch path derived from `WORK`, not under workspace `.build`:

```bash
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
```

Replace argument parsing at the end:

```bash
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
```

- [x] **Step 4: Run helper self-test and usage checks**

Run:

```bash
./.github/scripts/cross-target-compile.sh --self-test
./.github/scripts/cross-target-compile.sh --help
set +e
./.github/scripts/cross-target-compile.sh --targets ios,wasm >/tmp/slice-16-targets-invalid.out 2>&1
status=$?
set -e
cat /tmp/slice-16-targets-invalid.out
echo "status=${status}"
test "$status" -eq 2
```

Expected: self-test prints `self_test=pass`; help shows `--targets all|ios|wasm`; invalid combined target exits `2`.

Also verify the helper contains the temporary SwiftPM scratch path for WASM builds:

```bash
rg -n -- '--scratch-path.*--swift-sdk|swiftpm-\$\{target_name\}' .github/scripts/cross-target-compile.sh
```

Expected: matches in `compile_wasm_target()`.

- [x] **Step 5: Verify `--targets wasm` does not run iOS and exits 0**

Run:

```bash
./.github/scripts/cross-target-compile.sh --targets wasm | tee /tmp/slice-16-targets-wasm.out
rg -n "target=ios_device result=skipped reason=not_requested blocking=false" /tmp/slice-16-targets-wasm.out
rg -n "target=ios_simulator result=skipped reason=not_requested blocking=false" /tmp/slice-16-targets-wasm.out
rg -n "target=wasm result=(pass|fail|skipped) reason=" /tmp/slice-16-targets-wasm.out
rg -n "target=wasm_embedded result=(pass|fail|skipped) reason=" /tmp/slice-16-targets-wasm.out
rg -n "blocking_failures=0 exit=0" /tmp/slice-16-targets-wasm.out
if rg -n "xcodebuild build" /tmp/slice-16-targets-wasm.out; then exit 1; fi
```

Expected: iOS targets are `not_requested blocking=false`, selected WASM targets are reported, summary has `exit=0`, and no `xcodebuild build` command appears.

- [x] **Step 6: Verify `--targets ios` does not run WASM**

Run:

```bash
./.github/scripts/cross-target-compile.sh --targets ios | tee /tmp/slice-16-targets-ios.out
rg -n "target=ios_device result=pass reason=none blocking=true" /tmp/slice-16-targets-ios.out
rg -n "target=ios_simulator result=pass reason=none blocking=true" /tmp/slice-16-targets-ios.out
rg -n "target=wasm result=skipped reason=not_requested blocking=false" /tmp/slice-16-targets-ios.out
rg -n "target=wasm_embedded result=skipped reason=not_requested blocking=false" /tmp/slice-16-targets-ios.out
rg -n "blocking_failures=0 exit=0" /tmp/slice-16-targets-ios.out
if rg -n "swift build --swift-sdk" /tmp/slice-16-targets-ios.out; then exit 1; fi
```

Expected: iOS targets pass and are blocking, WASM targets are `not_requested blocking=false`, summary has `exit=0`, and no WASM build command appears.

- [x] **Step 7: Commit cross-target helper changes**

Run:

```bash
git add .github/scripts/cross-target-compile.sh
git commit -m "ci: add cross-target target selection"
```

Expected: one commit containing only `.github/scripts/cross-target-compile.sh`.

### Task 3: Add Linux Benchmark And RSS Support To Memory Observation

**Files:**
- Modify: `Sources/ViewportBenchmarks/main.swift`
- Modify: `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`

- [x] **Step 1: Verify local Darwin observation still passes before editing**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-observation | tee /tmp/slice-16-memory-observation-darwin-before.out
rg -n "mode=memory_observation .* observation=pass" /tmp/slice-16-memory-observation-darwin-before.out
rg -n "rss_page_size_bytes=" /tmp/slice-16-memory-observation-darwin-before.out
```

Expected: every row has `observation=pass` and RSS fields are present.

- [x] **Step 2: Verify Linux build fails before benchmark portability fix**

Run:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace swift:6.2.1-bookworm bash -lc 'swift build -c release --scratch-path /tmp/slice-16-linux-build-rss-red' >/tmp/slice-16-linux-build-rss-red.out 2>&1
status=$?
cat /tmp/slice-16-linux-build-rss-red.out | tail -40
echo "status=${status}"
test "$status" -ne 0
rg -n "no such module 'Darwin'|cannot find.*Darwin" /tmp/slice-16-linux-build-rss-red.out
```

Expected: nonzero status from unconditional Darwin imports in the benchmark executable.

- [x] **Step 3: Implement conditional benchmark entry point and RSS collection**

In `Sources/ViewportBenchmarks/main.swift`, replace the whole file with portable imports and an unqualified `exit(exitCode)`. The `#available(macOS 13.0, *)` condition evaluates through the `*` arm on Linux, so the Linux build uses the main branch and never reaches the macOS-only fallback:

```swift
#if canImport(Darwin)
import Darwin
#elseif os(Linux)
import Glibc
#endif

if #available(macOS 13.0, *) {
    let exitCode = runProgram(arguments: Array(CommandLine.arguments.dropFirst()))
    if exitCode != 0 {
        exit(exitCode)
    }
} else {
    fatalError("ViewportBenchmarks requires macOS 13.0 or newer")
}
```

In `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`, replace the top import:

```swift
#if canImport(Darwin)
import Darwin
#elseif os(Linux)
import Glibc
#endif
import TextEngineCore
```

Replace `currentRSSSnapshot()` with host-conditional wrappers and helpers:

```swift
func currentRSSSnapshot() -> MemoryObservationRSSSnapshot? {
#if canImport(Darwin)
    return currentDarwinRSSSnapshot()
#elseif os(Linux)
    return currentLinuxRSSSnapshot()
#else
    return nil
#endif
}

#if canImport(Darwin)
func currentDarwinRSSSnapshot() -> MemoryObservationRSSSnapshot? {
    let pageSize = Int(getpagesize())
    if pageSize <= 0 {
        return nil
    }

    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )

    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                $0,
                &count
            )
        }
    }

    guard result == KERN_SUCCESS,
          info.resident_size > 0,
          info.resident_size <= UInt64(Int.max) else {
        return nil
    }

    return MemoryObservationRSSSnapshot(
        bytes: Int(info.resident_size),
        pageSizeBytes: pageSize
    )
}
#endif

#if os(Linux)
func currentLinuxRSSSnapshot() -> MemoryObservationRSSSnapshot? {
    let pageSize = Int(sysconf(Int32(_SC_PAGESIZE)))
    guard pageSize > 0,
          let statmLine = readLinuxStatmLine(),
          let residentPages = linuxResidentPages(fromStatmLine: statmLine),
          residentPages > 0,
          residentPages <= Int.max / pageSize else {
        return nil
    }

    return MemoryObservationRSSSnapshot(
        bytes: residentPages * pageSize,
        pageSizeBytes: pageSize
    )
}

func readLinuxStatmLine() -> String? {
    guard let file = fopen("/proc/self/statm", "r") else {
        return nil
    }
    defer { fclose(file) }

    var buffer = [CChar](repeating: 0, count: 256)
    guard fgets(&buffer, Int32(buffer.count), file) != nil else {
        return nil
    }

    return String(cString: buffer)
}

func linuxResidentPages(fromStatmLine line: String) -> Int? {
    var fieldIndex = 0
    var currentValue = 0
    var hasDigit = false

    for byte in line.utf8 {
        if byte >= 48 && byte <= 57 {
            hasDigit = true
            let digit = Int(byte - 48)
            if currentValue > (Int.max - digit) / 10 {
                return nil
            }
            currentValue = currentValue * 10 + digit
        } else if byte == 32 || byte == 9 || byte == 10 {
            if hasDigit {
                if fieldIndex == 1 {
                    return currentValue
                }
                fieldIndex += 1
                currentValue = 0
                hasDigit = false
            }
        } else {
            return nil
        }
    }

    if hasDigit && fieldIndex == 1 {
        return currentValue
    }

    return nil
}
#endif
```

If Swift Linux reports a type mismatch for `_SC_PAGESIZE`, adjust only the `sysconf` line to the compiler-required signature and keep the same behavior:

```swift
let pageSize = Int(sysconf(_SC_PAGESIZE))
```

- [x] **Step 4: Verify Darwin still passes**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-observation | tee /tmp/slice-16-memory-observation-darwin-after.out
rg -n "mode=memory_observation .* observation=pass" /tmp/slice-16-memory-observation-darwin-after.out
rg -n "rss_page_size_bytes=" /tmp/slice-16-memory-observation-darwin-after.out
```

Expected: every row passes and RSS fields remain present.

- [x] **Step 5: Verify Linux build and memory observation in the Swift container**

Run:

```bash
set -o pipefail
docker run --rm -v "$PWD:/workspace" -w /workspace swift:6.2.1-bookworm bash -lc '
  set -euo pipefail
  swift --version
  uname -m
  swift build -c release --scratch-path /tmp/slice-16-linux-build-rss
  swift run -c release --scratch-path /tmp/slice-16-linux-build-rss ViewportBenchmarks -- --memory-observation | tee /tmp/slice-16-linux-memory-observation.out
  grep -E "mode=memory_observation .* observation=pass" /tmp/slice-16-linux-memory-observation.out
  grep -E "rss_page_size_bytes=" /tmp/slice-16-linux-memory-observation.out
'
```

Expected: release build passes; `--memory-observation` prints passing rows with `rss_page_size_bytes`.

- [x] **Step 6: Verify source encodes Linux statm resident field, not size field**

Run:

```bash
rg -n "linuxResidentPages|fieldIndex == 1|size resident shared text lib data dt|/proc/self/statm" Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
rg -n "canImport\\(Darwin\\)|os\\(Linux\\)|import Glibc|exit\\(exitCode\\)" Sources/ViewportBenchmarks/main.swift
```

Expected: matches show the Linux parser selects field index `1`, the second field `resident`, and reads `/proc/self/statm`; `main.swift` has conditional Darwin/Glibc imports and uses unqualified `exit(exitCode)`.

- [x] **Step 7: Commit Linux RSS support**

Run:

```bash
git add Sources/ViewportBenchmarks/main.swift Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
git commit -m "feat: support linux benchmark memory observation"
```

Expected: one commit containing only `Sources/ViewportBenchmarks/main.swift` and `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`.

### Task 4: Move CI Topology To Linux Host, macOS iOS, Linux WASM

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [x] **Step 1: Add failing workflow topology scans before editing**

Run:

```bash
set +e
rg -n "container: swift:6\.2\.1-bookworm" .github/workflows/swift-ci.yml
container_status=$?
rg -n "run: \./\.github/scripts/cross-target-compile\.sh --targets ios" .github/workflows/swift-ci.yml
ios_status=$?
rg -n "run: \./\.github/scripts/cross-target-compile\.sh --targets wasm" .github/workflows/swift-ci.yml
wasm_status=$?
set -e
echo "container_status=${container_status} ios_status=${ios_status} wasm_status=${wasm_status}"
test "$container_status" -ne 0
test "$ios_status" -ne 0
test "$wasm_status" -ne 0
```

Expected: all three scans fail before workflow changes.

- [x] **Step 2: Rewrite workflow triggers and host job**

In `.github/workflows/swift-ci.yml`, replace the trigger block with:

```yaml
on:
  pull_request:
    paths-ignore:
      - "docs/**"
      - "**/*.md"
  push:
    branches:
      - main
    paths-ignore:
      - "docs/**"
      - "**/*.md"
```

Replace `host-tests-and-benchmark-gate` runner metadata with:

```yaml
  host-tests-and-benchmark-gate:
    name: Host tests and benchmark gate
    runs-on: ubuntu-latest
    container: swift:6.2.1-bookworm
    timeout-minutes: 20
```

Replace that job's `Show toolchain` step with:

```yaml
      - name: Show toolchain
        run: |
          swift --version
          git --version
          uname -a
          cat /etc/os-release
          lscpu || true
```

Replace the host job Swift commands with scratch-path variants so the Linux container does not write root-owned artifacts under workspace `.build`:

```yaml
      - name: Run host tests
        run: swift test --scratch-path /tmp/text-engine-host-build

      - name: Run synthetic benchmark gate
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate

      - name: Run variable-height benchmark gate
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height --gate

      - name: Run memory shape diagnostic
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape

      - name: Run RSS memory observation diagnostic
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-observation
```

Replace the metadata block inside `Observe realistic provider relative performance` with:

```yaml
          echo "observation_started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          echo "runner_image=${ImageOS:-unknown}"
          swift --version 2>&1 | sed -n '1p' || true
          git --version
          uname -a
          cat /etc/os-release || true
          lscpu || true
```

Before the existing `git fetch`, add Git's safe-directory marker for the checked-out workspace:

```yaml
          git config --global --add safe.directory "$GITHUB_WORKSPACE"
```

Keep the existing `git fetch`, `git worktree add`, and `realistic-relative-observation.sh` commands unchanged after that safe-directory line.

- [x] **Step 3: Split cross-target jobs**

Replace the current `cross-target-compile` job with two jobs:

```yaml
  ios-cross-target-compile:
    name: iOS cross-target compile
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

      - name: Compile TextEngineCore for iOS targets
        run: ./.github/scripts/cross-target-compile.sh --targets ios

  wasm-cross-target-observation:
    name: WASM cross-target observation
    runs-on: ubuntu-latest
    container: swift:6.2.1-bookworm
    timeout-minutes: 20

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Show toolchain
        run: |
          swift --version
          git --version
          uname -a
          cat /etc/os-release
          lscpu || true

      - name: Observe TextEngineCore for WASM targets
        run: ./.github/scripts/cross-target-compile.sh --targets wasm
```

- [x] **Step 4: Verify workflow scans**

Run:

```bash
rg -n "paths-ignore|docs/\*\*|\*\*/\*\.md" .github/workflows/swift-ci.yml
rg -n "^concurrency:|cancel-in-progress: true" .github/workflows/swift-ci.yml
rg -n "host-tests-and-benchmark-gate:|runs-on: ubuntu-latest|container: swift:6\.2\.1-bookworm|git --version|safe.directory|--scratch-path /tmp/text-engine-host-build" .github/workflows/swift-ci.yml
rg -n "ios-cross-target-compile:|run: \./\.github/scripts/cross-target-compile\.sh --targets ios" .github/workflows/swift-ci.yml
rg -n "wasm-cross-target-observation:|run: \./\.github/scripts/cross-target-compile\.sh --targets wasm" .github/workflows/swift-ci.yml
rg -n "timeout-minutes: 20" .github/workflows/swift-ci.yml
```

Expected: path filters are present, `concurrency.cancel-in-progress` remains present, host and WASM jobs use Linux Swift container, Linux jobs print Git version, the host PR observation step marks the workspace safe before Git operations, host Swift commands use `/tmp/text-engine-host-build`, iOS job invokes only `--targets ios`, WASM job invokes only `--targets wasm`, and all three jobs have `timeout-minutes: 20`.

- [x] **Step 5: Verify Linux host and PR observation contain no macOS-only commands**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
text = Path(".github/workflows/swift-ci.yml").read_text()
host = text.split("  host-tests-and-benchmark-gate:", 1)[1].split("  ios-cross-target-compile:", 1)[0]
assert "xcodebuild" not in host
assert "machdep.cpu.brand_string" not in host
assert "realistic-relative-observation.sh" in host
assert "git --version" in host
assert 'git config --global --add safe.directory "$GITHUB_WORKSPACE"' in host
assert "git worktree add" in host
assert "--scratch-path /tmp/text-engine-host-build" in host
assert "lscpu || true" in host
print("host_job_linux_metadata=pass")
PY
```

Expected: prints `host_job_linux_metadata=pass`.

- [x] **Step 6: Commit workflow topology changes**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: move host and wasm checks to linux"
```

Expected: one commit containing only `.github/workflows/swift-ci.yml`.

### Task 5: Update AGENTS.md For New CI Topology

**Files:**
- Modify: `AGENTS.md`

- [x] **Step 1: Confirm AGENTS.md still describes old CI topology**

Run:

```bash
rg -n 'Two parallel jobs on `macos-latest`|Cross-target compile|WASM \+|cross-target-compile\.sh                    # local iOS/WASM cross-compile' AGENTS.md
```

Expected: matches for the old two-macOS-job wording.

- [x] **Step 2: Update commands section**

In the command block, replace:

```text
./.github/scripts/cross-target-compile.sh                    # local iOS/WASM cross-compile
```

with:

```text
./.github/scripts/cross-target-compile.sh                    # local iOS/WASM cross-compile
./.github/scripts/cross-target-compile.sh --targets ios      # iOS-only compile path
./.github/scripts/cross-target-compile.sh --targets wasm     # WASM-only observational path
```

- [x] **Step 3: Update CI section**

Replace the current CI job list with:

```markdown
Three jobs:

- **Host tests and benchmark gate** on `ubuntu-latest` with
  `swift:6.2.1-bookworm`: `swift test` → synthetic `--gate` (blocking)
  → `--variable-height --gate` (blocking) → `--memory-shape`
  → `--memory-observation` → realistic relative observation (PR-only,
  `continue-on-error`). The synthetic and variable-height gates **fail the job
  on perf regression**. Benchmark budgets are still macOS-calibrated unless
  hosted Linux x86_64 evidence explicitly justifies a retune. SwiftPM build
  artifacts use `/tmp/text-engine-host-build`, not workspace `.build`.
- **iOS cross-target compile** on `macos-latest`: iOS device + simulator are
  **blocking**, via `./.github/scripts/cross-target-compile.sh --targets ios`.
  This is the only hosted macOS job.
- **WASM cross-target observation** on `ubuntu-latest` with
  `swift:6.2.1-bookworm`: WASM + embedded WASM run via
  `./.github/scripts/cross-target-compile.sh --targets wasm`. They remain
  **observational**: the helper compiles them when a matching Swift SDK is
  installed/provisioned, otherwise records a non-blocking skip.

Docs-only changes are ignored by Swift CI via `paths-ignore` for `docs/**` and
`**/*.md`; code, workflow, script, package, and test changes still run CI.
```

Keep the private-repo caveat unchanged.

- [x] **Step 4: Verify AGENTS.md wording**

Run:

```bash
rg -n "Three jobs|swift:6\.2\.1-bookworm|--targets ios|--targets wasm|only hosted macOS job|Docs-only changes are ignored" AGENTS.md
rg -n "/tmp/text-engine-host-build" AGENTS.md
if rg -n 'Two parallel jobs on `macos-latest`|WASM \+ embedded WASM are \*\*observational\*\*: the helper compiles them' AGENTS.md; then exit 1; fi
```

Expected: new wording is present, the host scratch path is documented, and old topology wording is absent.

- [x] **Step 5: Commit AGENTS.md update**

Run:

```bash
git add AGENTS.md
git commit -m "docs: document ci resource topology"
```

Expected: one commit containing only `AGENTS.md`.

### Task 6: Full Local And Linux-Container Verification

**Files:**
- Read: all changed files
- Capture outputs under: `/tmp/slice-16-*.out`

- [x] **Step 1: Run host verification on local macOS**

Run:

```bash
swift test | tee /tmp/slice-16-swift-test.out
swift build -c release | tee /tmp/slice-16-release-build.out
swift run -c release ViewportBenchmarks -- --gate | tee /tmp/slice-16-synthetic-gate.out
swift run -c release ViewportBenchmarks -- --variable-height --gate | tee /tmp/slice-16-variable-height-gate.out
swift run -c release ViewportBenchmarks -- --memory-shape | tee /tmp/slice-16-memory-shape.out
swift run -c release ViewportBenchmarks -- --memory-observation | tee /tmp/slice-16-memory-observation-darwin.out
```

Expected: `swift test` reports 67 XCTest tests, 0 failures; release build exits `0`; synthetic and variable gates print `gate=pass`; memory-shape rows print `invariant=pass`; memory-observation rows print `observation=pass`.

- [x] **Step 2: Run cross-target helper verification locally**

Run:

```bash
./.github/scripts/cross-target-compile.sh --self-test | tee /tmp/slice-16-cross-target-self-test.out
./.github/scripts/cross-target-compile.sh --targets ios | tee /tmp/slice-16-cross-target-ios.out
./.github/scripts/cross-target-compile.sh --targets wasm | tee /tmp/slice-16-cross-target-wasm-local.out
```

Expected: self-test prints `self_test=pass`; iOS run passes iOS device/simulator and marks WASM not requested; WASM run marks iOS not requested and exits `0`.

- [x] **Step 3: Run Linux container host verification**

Run:

```bash
set -o pipefail
docker run --rm -v "$PWD:/workspace" -w /workspace swift:6.2.1-bookworm bash -lc '
  set -uo pipefail
  overall_status=0
  swift --version
  git --version
  uname -m
  cat /etc/os-release
  swift test --scratch-path /tmp/slice-16-linux-host-build || overall_status=$?
  swift build -c release --scratch-path /tmp/slice-16-linux-host-build || overall_status=$?
  swift run -c release --scratch-path /tmp/slice-16-linux-host-build ViewportBenchmarks -- --gate
  synthetic_gate_status=$?
  swift run -c release --scratch-path /tmp/slice-16-linux-host-build ViewportBenchmarks -- --variable-height --gate
  variable_gate_status=$?
  swift run -c release --scratch-path /tmp/slice-16-linux-host-build ViewportBenchmarks -- --memory-shape || overall_status=$?
  swift run -c release --scratch-path /tmp/slice-16-linux-host-build ViewportBenchmarks -- --memory-observation || overall_status=$?
  echo "linux_synthetic_gate_status=${synthetic_gate_status}"
  echo "linux_variable_gate_status=${variable_gate_status}"
  if [[ "$synthetic_gate_status" -ne 0 || "$variable_gate_status" -ne 0 ]]; then
    overall_status=1
    echo "linux_gate_failure_recorded=true"
  else
    echo "linux_gate_failure_recorded=false"
  fi
  exit "$overall_status"
' | tee /tmp/slice-16-linux-host-verification.out
```

Expected: all commands exit `0`; both benchmark gates print `gate=pass`; memory diagnostics pass; SwiftPM artifacts stay under `/tmp/slice-16-linux-host-build`. If a gate fails, the script still runs memory-shape and memory-observation before exiting nonzero, prints the gate statuses, and preserves the full output. If gates fail only on local arm64 timing, do not retune from this local result; record the output and wait for hosted Linux x86_64 evidence.

- [x] **Step 4: Run Linux container WASM helper verification**

Run:

```bash
set -o pipefail
docker run --rm -v "$PWD:/workspace" -w /workspace swift:6.2.1-bookworm bash -lc '
  set -euo pipefail
  git --version
  ./.github/scripts/cross-target-compile.sh --self-test
  ./.github/scripts/cross-target-compile.sh --targets wasm
' | tee /tmp/slice-16-linux-wasm-helper.out
rg -n "target=ios_device result=skipped reason=not_requested blocking=false" /tmp/slice-16-linux-wasm-helper.out
rg -n "target=ios_simulator result=skipped reason=not_requested blocking=false" /tmp/slice-16-linux-wasm-helper.out
rg -n "target=wasm result=(pass|skipped) reason=" /tmp/slice-16-linux-wasm-helper.out
rg -n "target=wasm_embedded result=(pass|skipped) reason=" /tmp/slice-16-linux-wasm-helper.out
rg -n "blocking_failures=0 exit=0" /tmp/slice-16-linux-wasm-helper.out
```

Expected: self-test passes; iOS targets are `not_requested blocking=false`; WASM targets pass or skip nonblocking; summary exits `0`. If a WASM SDK is available and the helper builds, it uses the helper's temporary `--scratch-path` rather than workspace `.build`.

- [x] **Step 5: Run source and workflow scans**

Run:

```bash
if rg -n "Foundation" Sources/TextEngineCore; then exit 1; fi
rg -n "fieldIndex == 1|/proc/self/statm|size resident shared text lib data dt" Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
rg -n "canImport\\(Darwin\\)|os\\(Linux\\)|import Glibc|exit\\(exitCode\\)" Sources/ViewportBenchmarks/main.swift
rg -n -- '--scratch-path.*--swift-sdk|swiftpm-\$\{target_name\}' .github/scripts/cross-target-compile.sh
rg -n "paths-ignore|docs/\*\*|\*\*/\*\.md|container: swift:6\.2\.1-bookworm|--targets ios|--targets wasm|timeout-minutes: 20|cancel-in-progress: true|safe.directory|--scratch-path /tmp/text-engine-host-build" .github/workflows/swift-ci.yml
python3 - <<'PY'
from pathlib import Path
text = Path(".github/workflows/swift-ci.yml").read_text()
host = text.split("  host-tests-and-benchmark-gate:", 1)[1].split("  ios-cross-target-compile:", 1)[0]
assert "xcodebuild" not in host
assert "machdep.cpu.brand_string" not in host
assert "realistic-relative-observation.sh" in host
assert "git --version" in host
assert 'git config --global --add safe.directory "$GITHUB_WORKSPACE"' in host
assert "git worktree add" in host
assert "--scratch-path /tmp/text-engine-host-build" in host
print("workflow_scan=pass")
PY
rg -n "Three jobs|only hosted macOS job|Docs-only changes are ignored|--targets ios|--targets wasm|/tmp/text-engine-host-build" AGENTS.md
git diff --check
```

Expected: Foundation scan has no output; required source/workflow/helper/AGENTS markers exist; Python scan prints `workflow_scan=pass`; `git diff --check` has no output.

### Task 7: Write Verification Record And Capture Hosted Evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-13-ci-resource-optimization.md`

- [x] **Step 1: Create verification document with local evidence**

Create `docs/superpowers/verification/2026-06-13-ci-resource-optimization.md` with this structure:

```markdown
# CI Resource Optimization Verification

Date: 2026-06-13

## Scope

Slice 16 moves host tests, benchmark gates, memory diagnostics, and WASM
observation off hosted macOS. `TextEngineCore`, `Tests/TextEngineCoreTests`,
and `Package.swift` are unchanged.

## Local Verification

Add the concrete command results from `/tmp/slice-16-*.out` for:

- `swift test`
- `swift build -c release`
- `swift run -c release ViewportBenchmarks -- --gate`
- `swift run -c release ViewportBenchmarks -- --variable-height --gate`
- `swift run -c release ViewportBenchmarks -- --memory-shape`
- `swift run -c release ViewportBenchmarks -- --memory-observation`
- `./.github/scripts/cross-target-compile.sh --self-test`
- `./.github/scripts/cross-target-compile.sh --targets ios`
- `./.github/scripts/cross-target-compile.sh --targets wasm`
- Linux container host verification with `swift:6.2.1-bookworm`
- Linux container WASM helper verification with `swift:6.2.1-bookworm`
- Foundation-free scan
- `main.swift` portability scan
- cross-target helper scratch-path scan
- workflow `concurrency`, Git `safe.directory`, and host scratch-path scans
- workflow scans
- `git diff --check`

## Hosted Pull Request Evidence

Record PR number, head SHA, run IDs, job names, runner/container facts,
benchmark gate rows, iOS target rows, WASM target rows, and realistic relative
observation status.

If hosted jobs do not start, record the exact GitHub Actions annotation and do
not treat this as green hosted evidence.

## Hosted Post-Merge Evidence

Record post-merge push run ID and job results after merge to `main`, if runners
start. If billing/spending-limit still blocks runner startup, record the exact
annotation and pending evidence.

## Budget Decision

State whether budgets changed. If they did not change, state that no hosted
Linux x86_64 evidence required a retune. If hosted Linux x86_64 evidence shows
a timing failure, record the samples and the retuned budget rationale.

## Conclusion

Summarize what is proven locally, what is proven hosted, and any remaining
external blocker.
```

Before committing, convert every instruction-only bullet in this document into
the actual command, exit status, and relevant output snippet captured during
Task 6.

- [x] **Step 2: Commit verification document before PR**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
text = Path("docs/superpowers/verification/2026-06-13-ci-resource-optimization.md").read_text()
bad = [
    "Add the concrete command results",
    "instruction-only bullet",
    "UNRECORDED",
]
for marker in bad:
    if marker in text:
        raise SystemExit(f"verification_doc_marker_found={marker}")
print("verification_doc_markers=pass")
PY
git add docs/superpowers/verification/2026-06-13-ci-resource-optimization.md
git commit -m "docs: record ci resource optimization verification"
```

Expected: marker scan prints `verification_doc_markers=pass`; one docs commit.

- [x] **Step 3: Push branch and open PR**

Run:

```bash
git status --short --branch
git push -u origin slice-16-ci-resource-optimization
gh pr create \
  --title "Slice 16: CI resource optimization" \
  --body "Moves host tests and WASM observation off hosted macOS, keeps macOS for iOS only, adds Linux RSS support, and records verification evidence."
```

Expected: branch pushes successfully and `gh pr create` returns a PR URL.

- [x] **Step 4: Capture hosted PR evidence**

Run:

```bash
gh pr view --json number,headRefName,headRefOid,url
gh run list --workflow "Swift CI" --branch slice-16-ci-resource-optimization --limit 5
```

Then inspect the latest run:

```bash
gh run view <run-id> --json databaseId,headSha,conclusion,status,jobs
gh run view <run-id> --log > /tmp/slice-16-hosted-pr-run.log
```

Expected if runners start: host job runs on Linux container and passes, iOS job runs on macOS and passes, WASM job runs on Linux container and passes or skips nonblocking, realistic observation reaches `realistic-relative-observation.sh`. If runners do not start, record the exact billing/spending-limit annotation.

- [x] **Step 5: Update verification doc with hosted PR evidence**

Edit `docs/superpowers/verification/2026-06-13-ci-resource-optimization.md` with PR run facts:

- PR number and URL;
- run ID and head SHA;
- job names and conclusions;
- hosted Linux `swift --version`, `uname -m`, and container evidence from logs;
- benchmark `gate=pass` rows or exact failure;
- iOS `target=ios_device` and `target=ios_simulator` rows;
- WASM `target=wasm` and `target=wasm_embedded` rows;
- realistic observation outcome or exact setup failure;
- billing/spending-limit annotation if runners never started.

Commit:

```bash
git add docs/superpowers/verification/2026-06-13-ci-resource-optimization.md
git commit -m "docs: record ci resource optimization pr evidence"
git push
```

Expected: verification doc includes real hosted PR evidence or a precise external blocker.

### Task 8: Post-Merge Evidence Handoff

**Files:**
- Modify after merge: `docs/superpowers/verification/2026-06-13-ci-resource-optimization.md`

- [ ] **Step 1: After PR merge, sync `main`**

Run after the PR is merged:

```bash
git switch main
git pull --ff-only
git log --oneline --decorate -5
```

Expected: local `main` includes the Slice 16 merge commit.

- [ ] **Step 2: Capture post-merge push run**

Run:

```bash
gh run list --workflow "Swift CI" --branch main --limit 5
gh run view <post-merge-run-id> --json databaseId,headSha,conclusion,status,jobs
```

If logs exist:

```bash
gh run view <post-merge-run-id> --log > /tmp/slice-16-hosted-post-merge-run.log
```

Expected if runners start: post-merge host, iOS, and WASM jobs reach the same conclusions as the PR run. If runners do not start, record the exact billing/spending-limit annotation.

- [ ] **Step 3: Update verification doc with post-merge evidence**

Edit `docs/superpowers/verification/2026-06-13-ci-resource-optimization.md` and add:

- merge commit SHA;
- post-merge run ID;
- job conclusions or exact runner-start blocker;
- whether this is green hosted post-merge evidence or pending due to billing.

Commit to `main` if the verification doc changes after merge:

```bash
git add docs/superpowers/verification/2026-06-13-ci-resource-optimization.md
git commit -m "docs: record ci resource optimization post-merge run"
git push
```

Expected: verification record is on `main` and accurately distinguishes passing hosted evidence from external billing blockage.
