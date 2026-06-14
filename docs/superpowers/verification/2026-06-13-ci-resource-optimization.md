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

#### Follow-up root cause (2026-06-13)

A deeper investigation localized the hang and ruled out core/test defects:

- `swift build` and `swift build --build-tests` succeed in `swift:6.2.1-bookworm`.
- Each test passes individually. Run alone,
  `DocumentLineCursorTests/testCursorReportsMissingIndexesWithoutClampingRange`
  exits `0`. Invoking the `*.xctest` binary directly shows the prior test passing
  and this one starting, then blocking.
- The full suite / a whole class in one xctest process hangs at the transition
  *between* sequential tests: `swift-test` sits in `rt_sigsuspend`, the
  `*.xctest` worker sits in `poll`, 0% CPU, no further output. No `Test Case`
  line is ever flushed via `swift test` (stdout is block-buffered).
- The same hang reproduces under x86_64 (`docker run --platform linux/amd64`,
  Rosetta): build succeeds, `swift test` times out (`124`) with zero `Test Case`
  lines.

On Apple Silicon both the aarch64-native and the x86_64-emulated containers share
the one Docker Desktop Linux VM kernel (aarch64), so the guest CPU arch does not
change the outcome. The hang is therefore an environment artifact of the local
Docker Desktop Linux VM — not the guest arch, not `TextEngineCore`, and not the
tests (which pass on macOS and individually on Linux). The same
`swift:6.2.1-bookworm` image runs `swift test` across the ecosystem on hosted
x86_64 GitHub Actions, so the new Linux host job is expected to pass there. This
cannot be proven from this Mac: every local Linux path goes through the
confounding Docker Desktop VM. Hosted x86_64 evidence (for example, by
temporarily making the repo public for free Actions minutes) remains the only way
to close this gap.

#### Hosted resolution (2026-06-14)

Resolved. After the account billing block was cleared, hosted Linux x86_64
GitHub Actions ran the new host job and `swift test` completed normally:

```text
Target Platform: x86_64-unknown-linux-gnu
Executed 67 tests, with 0 failures (0 unexpected) in 0.212 (0.212) seconds
```

(Run `27493957434`, head `0d0f0ca`, container `swift:6.2.1-bookworm`,
`Target: x86_64-unknown-linux-gnu`.) This confirms the full-suite hang was an
artifact of the local Docker Desktop Linux VM, not `TextEngineCore` or the
tests: the same image and suite pass on hosted x86_64 in ~0.2s.

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

Linux RSS source scan command -> exit 0:

```bash
rg -n "fieldIndex == 1|/proc/self/statm|size resident shared text lib data dt" Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
```

Relevant output:

```text
Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift:
/proc/self/statm
size resident shared text lib data dt
fieldIndex == 1
```

Benchmark entry-point scan command -> exit 0:

```bash
rg -n "canImport\\(Darwin\\)|os\\(Linux\\)|import Glibc|exit\\(exitCode\\)" Sources/ViewportBenchmarks/main.swift
```

Relevant output:

```text
Sources/ViewportBenchmarks/main.swift:
canImport(Darwin)
os(Linux)
import Glibc
exit(exitCode)
```

Cross-target helper scratch-path scan command -> exit 0:

```bash
rg -n -- '--scratch-path.*--swift-sdk|swiftpm-\$\{target_name\}' .github/scripts/cross-target-compile.sh
```

Relevant output:

```text
local scratch_path="${WORK}/swiftpm-${target_name}"
swift build --scratch-path "$scratch_path" --swift-sdk "$sdk_id" --target "$PACKAGE_TARGET"
```

Workflow scan commands -> exit 0:

```bash
rg -n "paths-ignore|docs/\\*\\*|\\*\\*/\\*\\.md|container: swift:6\\.2\\.1-bookworm|--targets ios|--targets wasm|timeout-minutes: 20|cancel-in-progress: true|safe.directory|--scratch-path /tmp/text-engine-host-build" .github/workflows/swift-ci.yml
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
```

Relevant output:

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

AGENTS.md scan command -> exit 0:

```bash
rg -n "Three jobs|only hosted macOS job|Docs-only changes are ignored|--targets ios|--targets wasm|/tmp/text-engine-host-build" AGENTS.md
```

Relevant output:

```text
Three jobs
only hosted macOS job
Docs-only changes are ignored
--targets ios
--targets wasm
/tmp/text-engine-host-build
```

`git diff --check` -> exit 0.

## Docs-Only Skip Behavior (Observed)

`paths-ignore` on `pull_request` is evaluated against the whole PR diff, not the
latest pushed commit. PR #13 carries code/workflow/script changes, so the four
docs-only commits pushed to it (`c84acfe`, `bf149d3`, `8d96dde`, `e70e20a`, each
touching only this verification record) each still triggered Swift CI (runs
`27470851134`, `27470877668`, `27470904394`, `27471010859`). The `paths-ignore`
skip therefore applies only to fully docs-only PRs and docs-only pushes to `main`
(for example, a post-slice review committed directly to `main`); it does not skip
docs-only commits appended to a PR that also changes code. This is a GitHub
`pull_request` filter semantic, not a workflow defect, and is reflected in the
corrected `AGENTS.md` CI note.

## Hosted Pull Request Evidence

### Earlier billing-blocked attempts (historical)

The first hosted attempts (PR #13, pre-rewrite head SHAs `c84acfe`, `bf149d3`,
runs `27470851134`, `27470877668`) all completed as `failure` before any job
step started. Every job carried the same check-run annotation:

```text
The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings
```

The blocker was an **account-level failed payment**, not repository visibility
or a per-repo limit: making the repository public did not bypass it (the next
run on the rewritten head, `27493957434` at `0d0f0ca`, first reproduced the same
annotation). macOS runners are never free, and free public-repo Linux minutes
are still suspended while an account payment is delinquent. After the account
payment was cleared, the same runs went green (below). The branch history was
also rewritten and the account renamed, so the canonical owner is now
`maldrakar/swift-text-engine` and the pre-rewrite SHAs no longer exist.

### Green hosted evidence

PR: #13, `https://github.com/maldrakar/swift-text-engine/pull/13`

Head branch: `slice-16-ci-resource-optimization`

Head SHA: `0d0f0ca1e0e70cf6ca0a8264424509db07376757`

Swift CI run: `27493957434` (re-run after the billing block was cleared) ->
`status=completed conclusion=success`.

Jobs (`gh run view 27493957434 --json ...`):

```text
Host tests and benchmark gate: conclusion=success
iOS cross-target compile:      conclusion=success
WASM cross-target observation: conclusion=success
```

Host job toolchain (hosted Linux x86_64, `swift:6.2.1-bookworm`):

```text
Swift version 6.2.1 (swift-6.2.1-RELEASE)
Target: x86_64-unknown-linux-gnu
Architecture: x86_64
```

`swift test`:

```text
Executed 67 tests, with 0 failures (0 unexpected) in 0.212 (0.212) seconds
```

Synthetic benchmark gate (all `gate=pass`, all under budget):

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0   p95_ns=2531  p99_ns=2648  budget_p95_ns=20000  budget_p99_ns=50000  gate=pass
mode=pipeline scenario=100k_lines_80_visible_overscan_5 p95_ns=10524 p99_ns=10963 budget_p95_ns=50000  budget_p99_ns=100000 gate=pass
mode=pipeline scenario=1m_lines_200_visible_overscan_50 p95_ns=34245 p99_ns=35082 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass
```

Variable-height benchmark gate (all `gate=pass`):

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0   p95_ns=499  p99_ns=514  gate=pass
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 p95_ns=1757 p99_ns=1860 gate=pass
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 p95_ns=5843 p99_ns=6001 gate=pass
```

Memory-shape (`invariant=pass` for all five rows) and memory-observation
(`observation=pass` for all three rows, `rss_page_size_bytes=4096`, i.e. the
Linux `/proc/self/statm` RSS path) both passed on the Linux host.

**Correction (2026-06-14):** an earlier version of this record stated the PR-only
`Observe realistic provider relative performance` step "reached
`realistic-relative-observation.sh` ... and completed success." That was wrong.
In the container the step runs under `sh`, and its `set -euo pipefail` first line
is a bashism, so the step exits at line 1 and never runs the script:

```text
/__w/_temp/<id>.sh: 1: set: Illegal option -o pipefail
##[error]Process completed with exit code 2
```

`continue-on-error: true` keeps the job green, which is why the job-level
conclusion is `success` while the observation produced no data. This regression
(Slice 16 moved the host job from `macos-latest`, where the default shell is
bash, to the container) is fixed by adding `shell: bash` to the step; the
realistic relative observation must be treated as **absent** on every earlier
Slice 16-era run rather than passing. The threshold `1.221556` seen in those logs
is only the env value echoed in the step's `##[group]Run` header, not script
output.

**Fix verified (PR #15, run `27497860966`, head `e89cdb0`):** with `shell: bash`
the step runs under `bash --noprofile --norc -e -o pipefail {0}`, prepares the
base/head worktrees, and actually executes `realistic-relative-observation.sh`:

```text
mode=realistic_relative_observation base_sha=4aa42c6 head_sha=e89cdb0 \
  base_median_p95_ns=12992.5 head_median_p95_ns=13155.0 \
  p95_ratio=1.012507 p99_ratio=1.045687 max_ratio=1.045687 \
  observation_threshold=1.221556 observation=clean blocking_ready=false
```

No `Illegal option -o pipefail` line appears, and the step emits real relative
ratios (`max_ratio≈1.05` under the `1.221556` threshold, `observation=clean`).

iOS job (hosted macOS):

```text
mode=cross_target_compile target=ios_device    result=pass    reason=none          blocking=true
mode=cross_target_compile target=ios_simulator result=pass    reason=none          blocking=true
mode=cross_target_compile target=wasm          result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=wasm_embedded result=skipped reason=not_requested blocking=false
```

WASM observation job (hosted Linux x86_64; observational, nonblocking):

```text
mode=cross_target_compile target=ios_device    result=skipped reason=not_requested  blocking=false
mode=cross_target_compile target=ios_simulator result=skipped reason=not_requested  blocking=false
mode=cross_target_compile target=wasm          result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile target=wasm_embedded result=skipped reason=sdk_unavailable blocking=false
```

This is green hosted PR evidence on the canonical head `0d0f0ca`: the Linux host
job runs `swift test` + both blocking gates + memory diagnostics, the macOS job
blocks only on iOS, and the Linux WASM job is observational. The verification
doc commit that records this evidence moves the branch head, so the merged-code
anchor is the post-merge `push` run on `main` recorded below.

## Hosted Post-Merge Evidence

PR #13 was merged to `main` via merge commit
`7030f8698d812b084929452b8016bf59c1992494`
(`Merge pull request #13 from maldrakar/slice-16-ci-resource-optimization`). The
merge required admin bypass because the `main` ruleset (created 2026-06-14)
enforces a pull-request flow; the ruleset has no required status checks, so the
green PR run was advisory, and this post-merge `push` run is the merged-code
anchor.

Post-merge Swift CI `push` run: `27494701290`, head
`7030f8698d812b084929452b8016bf59c1992494` -> `status=completed
conclusion=success`.

Jobs:

```text
Host tests and benchmark gate: conclusion=success
iOS cross-target compile:      conclusion=success
WASM cross-target observation: conclusion=success
```

Host job (hosted Linux x86_64, `Target: x86_64-unknown-linux-gnu`):

```text
Executed 67 tests, with 0 failures (0 unexpected) in 0.213 (0.213) seconds
mode=pipeline scenario=1k_lines_20_visible_overscan_0   p95_ns=2493  p99_ns=2712  gate=pass
mode=pipeline scenario=100k_lines_80_visible_overscan_5 p95_ns=10406 p99_ns=10627 gate=pass
mode=pipeline scenario=1m_lines_200_visible_overscan_50 p95_ns=34026 p99_ns=34761 gate=pass
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0   p95_ns=503  p99_ns=681  gate=pass
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 p95_ns=1730 p99_ns=1830 gate=pass
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 p95_ns=5436 p99_ns=5541 gate=pass
```

iOS job (hosted macOS): `target=ios_device result=pass blocking=true`,
`target=ios_simulator result=pass blocking=true`. WASM job (hosted Linux
x86_64): `target=wasm result=skipped reason=sdk_unavailable` and
`target=wasm_embedded result=skipped reason=sdk_unavailable` (observational,
nonblocking).

This is green hosted post-merge evidence on `main`: the same three-job topology
that passed on the PR head passes on the merge commit.

## Budget Decision

No benchmark budgets changed. Hosted Linux x86_64 timing is now available
(run `27493957434`) and every gate row stayed comfortably under budget — the
worst case is the synthetic `1m_lines_200_visible_overscan_50` scenario at
`p95_ns=34245` / `p99_ns=35082` against a `100000` / `200000` budget (~34% / 18%
of budget). No hosted Linux x86_64 evidence required a retune.

## Conclusion

Local macOS verification passed. Local cross-target helper verification passed,
including iOS device/simulator and local WASM SDK builds. Linux container
release build, benchmark gates, memory-shape, memory-observation, and WASM
helper behavior passed. The previously-pending full-suite `swift test` question
is resolved: hosted Linux x86_64 (run `27493957434`, head `0d0f0ca`) ran
`swift test` to `Executed 67 tests, with 0 failures` in ~0.2s, confirming the
local aarch64 Docker hang was an environment artifact. Hosted PR evidence is
green across all three jobs. Post-merge `push` evidence on `main` is recorded
below once the PR is merged.
