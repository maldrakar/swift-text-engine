# CI Resource Optimization Verification

Date: 2026-06-13

## Scope

Slice 16 moves host tests, benchmark gates, memory diagnostics, and WASM
observation off hosted macOS. `TextEngineCore`, `Tests/TextEngineCoreTests`,
and `Package.swift` are unchanged.

## Local Verification

### macOS host

`swift test` -> exit 0.

Relevant output from `/tmp/slice-16-swift-test.out`:

```text
Executed 67 tests, with 0 failures (0 unexpected)
Test run with 0 tests in 0 suites passed
```

`swift build -c release` -> exit 0.

Relevant output from `/tmp/slice-16-release-build.out`:

```text
Build complete!
```

`swift run -c release ViewportBenchmarks -- --gate` -> exit 0.

Relevant output from `/tmp/slice-16-synthetic-gate.out`:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 ... p95_ns=1263 p99_ns=1337 ... gate=pass
mode=pipeline scenario=100k_lines_80_visible_overscan_5 ... p95_ns=5018 p99_ns=5181 ... gate=pass
mode=pipeline scenario=1m_lines_200_visible_overscan_50 ... p95_ns=16522 p99_ns=17283 ... gate=pass
```

`swift run -c release ViewportBenchmarks -- --variable-height --gate` -> exit 0.

Relevant output from `/tmp/slice-16-variable-height-gate.out`:

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 ... p95_ns=219 p99_ns=247 ... gate=pass
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 ... p95_ns=683 p99_ns=734 ... gate=pass
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 ... p95_ns=2158 p99_ns=2289 ... gate=pass
```

`swift run -c release ViewportBenchmarks -- --memory-shape` -> exit 0.

Relevant output from `/tmp/slice-16-memory-shape.out`:

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 ... invariant=pass
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 ... invariant=pass
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text ... invariant=pass
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 ... invariant=pass
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 ... invariant=pass
```

`swift run -c release ViewportBenchmarks -- --memory-observation` -> exit 0.

Relevant output from `/tmp/slice-16-memory-observation-darwin.out`:

```text
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 ... rss_page_size_bytes=16384 ... observation=pass
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 ... rss_page_size_bytes=16384 ... observation=pass
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text ... rss_page_size_bytes=16384 ... observation=pass
```

### Cross-target helper on macOS

`./.github/scripts/cross-target-compile.sh --self-test` -> exit 0.

```text
self_test=pass
```

`./.github/scripts/cross-target-compile.sh --targets ios` -> exit 0.

Relevant output from `/tmp/slice-16-cross-target-ios.out`:

```text
mode=cross_target_compile target=ios_device result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true
mode=cross_target_compile target=wasm result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=wasm_embedded result=skipped reason=not_requested blocking=false
mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0
```

`./.github/scripts/cross-target-compile.sh --targets wasm` -> exit 0.

Relevant output from `/tmp/slice-16-cross-target-wasm-local.out`:

```text
mode=cross_target_compile target=ios_device result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=ios_simulator result=skipped reason=not_requested blocking=false
cross_target_command target=wasm cmd="swift build --scratch-path .../swiftpm-wasm --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore"
mode=cross_target_compile target=wasm result=pass reason=none blocking=false
cross_target_command target=wasm_embedded cmd="swift build --scratch-path .../swiftpm-wasm_embedded --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore"
mode=cross_target_compile target=wasm_embedded result=pass reason=none blocking=false
mode=cross_target_compile_summary ios_device=skipped ios_simulator=skipped wasm=pass wasm_embedded=pass blocking_failures=0 exit=0
```

### Linux container host verification

Container: `swift:6.2.1-bookworm`.

Relevant environment output:

```text
Swift version 6.2.1 (swift-6.2.1-RELEASE)
Target: aarch64-unknown-linux-gnu
git version 2.39.5
aarch64
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
```

`swift build -c release --scratch-path /tmp/slice-16-linux-host-build-no-tests`
-> exit 0.

Relevant output from `/tmp/slice-16-linux-host-verification-no-tests.out`:

```text
Build complete! (1.40s)
```

`swift run -c release --scratch-path /tmp/slice-16-linux-host-build-no-tests ViewportBenchmarks -- --gate`
-> exit 0.

Relevant output:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 ... p95_ns=1226 p99_ns=1281 ... gate=pass
mode=pipeline scenario=100k_lines_80_visible_overscan_5 ... p95_ns=5058 p99_ns=5193 ... gate=pass
mode=pipeline scenario=1m_lines_200_visible_overscan_50 ... p95_ns=16615 p99_ns=17273 ... gate=pass
```

`swift run -c release --scratch-path /tmp/slice-16-linux-host-build-no-tests ViewportBenchmarks -- --variable-height --gate`
-> exit 0.

Relevant output:

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 ... p95_ns=208 p99_ns=233 ... gate=pass
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 ... p95_ns=679 p99_ns=750 ... gate=pass
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 ... p95_ns=2049 p99_ns=2099 ... gate=pass
```

`swift run -c release --scratch-path /tmp/slice-16-linux-host-build-no-tests ViewportBenchmarks -- --memory-shape`
-> exit 0.

Relevant output:

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 ... invariant=pass
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 ... invariant=pass
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text ... invariant=pass
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 ... invariant=pass
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 ... invariant=pass
```

`swift run -c release --scratch-path /tmp/slice-16-linux-host-build-no-tests ViewportBenchmarks -- --memory-observation`
-> exit 0.

Relevant output:

```text
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 ... rss_page_size_bytes=4096 ... observation=pass
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 ... rss_page_size_bytes=4096 ... observation=pass
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text ... rss_page_size_bytes=4096 ... observation=pass
```

Local Linux-container `swift test --scratch-path /tmp/slice-16-linux-host-build`
did not produce passing full-suite evidence in this aarch64 Docker environment.
Two attempts stalled after the build/test-runner startup and were terminated:

```text
/tmp/slice-16-linux-host-verification.out:
Swift version 6.2.1 (swift-6.2.1-RELEASE)
Target: aarch64-unknown-linux-gnu
git version 2.39.5
aarch64
```

Narrow repro checks:

```text
timeout 90 swift test --scratch-path /tmp/slice-16-linux-class-test --filter VariableHeightQueryCountTests
class_test_status=124

timeout 90 swift test --scratch-path /tmp/slice-16-linux-smoke-test --filter DocumentLineCursorTests
smoke_test_status=124

timeout 60 swift test --scratch-path /tmp/slice-16-linux-exact-smoke-test --filter DocumentLineCursorTests.testCursorFetchesOneLinePerBufferedIndex
exact_smoke_test_status=0
```

This is recorded as a local aarch64 Docker Swift-test-runner blocker, not as
green Linux XCTest evidence. Hosted Linux x86_64 PR evidence must resolve
whether the new CI host job passes `swift test`.

### Linux container WASM helper verification

`swift:6.2.1-bookworm` container command:
`./.github/scripts/cross-target-compile.sh --self-test` and
`./.github/scripts/cross-target-compile.sh --targets wasm` -> exit 0.

Relevant output from `/tmp/slice-16-linux-wasm-helper.out`:

```text
git version 2.39.5
self_test=pass
mode=cross_target_compile target=ios_device result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=ios_simulator result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=wasm result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile target=wasm_embedded result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile_summary ios_device=skipped ios_simulator=skipped wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0
```

### Source and workflow scans

Foundation-free scan:

```bash
if rg -n "Foundation" Sources/TextEngineCore; then exit 1; fi
```

Exit 0 with no matches.

Linux RSS source scan:

```text
Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift:
/proc/self/statm
size resident shared text lib data dt
fieldIndex == 1
```

Benchmark entry-point scan:

```text
Sources/ViewportBenchmarks/main.swift:
canImport(Darwin)
os(Linux)
import Glibc
exit(exitCode)
```

Cross-target helper scratch-path scan:

```text
local scratch_path="${WORK}/swiftpm-${target_name}"
swift build --scratch-path "$scratch_path" --swift-sdk "$sdk_id" --target "$PACKAGE_TARGET"
```

Workflow scan:

```text
paths-ignore
docs/**
**/*.md
container: swift:6.2.1-bookworm
--targets ios
--targets wasm
timeout-minutes: 20
cancel-in-progress: true
safe.directory
--scratch-path /tmp/text-engine-host-build
workflow_scan=pass
```

AGENTS.md scan:

```text
Three jobs
only hosted macOS job
Docs-only changes are ignored
--targets ios
--targets wasm
/tmp/text-engine-host-build
```

`git diff --check` -> exit 0.

## Hosted Pull Request Evidence

PR: #13, `https://github.com/arthurbanshchikov/swift-text-engine/pull/13`

Head branch: `slice-16-ci-resource-optimization`

Head SHA: `c84acfee311dcabffe1bdf1c94f924ca20b8aae6`

Swift CI run: `27470851134`

Run status from `gh run view 27470851134 --json databaseId,headSha,conclusion,status,jobs`:

```text
status=completed
conclusion=failure
headSha=c84acfee311dcabffe1bdf1c94f924ca20b8aae6
```

Jobs:

```text
iOS cross-target compile: id=81201368869 status=completed conclusion=failure steps=[]
WASM cross-target observation: id=81201368872 status=completed conclusion=failure steps=[]
Host tests and benchmark gate: id=81201368892 status=completed conclusion=failure steps=[]
```

`gh run view 27470851134 --log` -> exit 1:

```text
log not found: 81201368869
```

No hosted job steps started. Each job had the same check-run annotation from
`gh api repos/arthurbanshchikov/swift-text-engine/check-runs/<job-id>/annotations`:

```text
The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings
```

This is not green hosted PR evidence. It is an external runner-start blocker.
No hosted Linux x86_64 `swift test`, benchmark gate, iOS target, WASM target, or
realistic relative observation output is available from this run.

## Hosted Post-Merge Evidence

Pending until the PR is merged to `main`.

## Budget Decision

No benchmark budgets changed in the local implementation. Local macOS and local
Linux aarch64 benchmark gates passed with the existing budgets. Hosted Linux
x86_64 evidence is still required before using hosted timing as a retune signal.

## Conclusion

Local macOS verification passed. Local cross-target helper verification passed,
including iOS device/simulator and local WASM SDK builds. Linux container
release build, benchmark gates, memory-shape, memory-observation, and WASM
helper behavior passed. Full Linux container `swift test` remains pending due to
the local aarch64 Docker timeout described above; hosted Linux x86_64 PR
evidence is required before claiming complete hosted host-job proof.
