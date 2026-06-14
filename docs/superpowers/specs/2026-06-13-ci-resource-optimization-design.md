# CI Resource Optimization Design

Date: 2026-06-13

## Status

Approved direction, written for user review.

## Source Context

This is Slice 16 of SwiftTextEngine. Slice 15 promoted the variable-height
benchmark to a blocking CI gate and consolidated memory-shape diagnostics. Its
post-slice review found no core/source defects, but it exposed a new process
blocker: GitHub Actions runs stopped before executing any steps because the
account hit the spending limit / billing wall. The review traced the cost shape
to two facts:

- all CI jobs currently run on `macos-latest`;
- GitHub-hosted macOS minutes count at a much higher quota rate than Linux.

The current workflow has two macOS jobs:

- `host-tests-and-benchmark-gate`, which runs host tests, synthetic and
  variable-height benchmark gates, memory diagnostics, and the PR-only
  realistic relative observation;
- `cross-target-compile`, which runs one helper that currently bundles iOS
  device, iOS simulator, WASM, and embedded WASM checks.

Only the iOS device/simulator checks require Xcode/macOS. Host tests,
benchmark gates, memory diagnostics, and WASM Swift SDK probes do not.

`main` was clean before this spec. A fresh local `swift test` baseline on
2026-06-13 passed with 67 XCTest tests, 0 failures, plus the expected empty
Swift Testing harness line. Docker manifest checks confirmed that the official
Swift Debian images `swift:6.0-bookworm`, `swift:6.1-bookworm`,
`swift:6.2-bookworm`, `swift:6.1.2-bookworm`, and `swift:6.2.1-bookworm` are
available at design time. `swift:6.2.1-bookworm` is selected as a stable
patch-level Linux CI baseline aligned with the locally verified Swift 6.2.1
toolchain; it is not a new minimum-toolchain policy for the package.

Local Linux-container checks on Apple Silicon are useful compile/runtime smoke
tests, but they are not the same timing environment as the standard hosted
`ubuntu-latest` runner targeted by this slice. Budget calibration must treat
hosted Linux x86_64 evidence as the timing source of truth.

## Scope

Reduce GitHub-hosted macOS consumption while preserving the CI evidence shape
that matters for the product brief.

The selected topology is:

- Linux hosted runner for host tests, benchmark gates, deterministic memory
  diagnostics, RSS memory observation, and realistic relative observation;
- macOS hosted runner only for blocking iOS device/simulator compile checks;
- Linux hosted runner for observational WASM and embedded-WASM compile probes.

This slice is an infrastructure and benchmark-executable portability slice. It
does not change `TextEngineCore` behavior, public API, `Package.swift`, or
benchmark budgets unless hosted Linux x86_64 gate evidence proves a retune is
needed.

## Goals

- Move `host-tests-and-benchmark-gate` from `macos-latest` to
  `ubuntu-latest` with the official Debian Swift container
  `swift:6.2.1-bookworm`.
- Keep the host job sequence equivalent:
  `swift test` -> synthetic `--gate` -> variable-height `--gate` ->
  `--memory-shape` -> `--memory-observation` -> PR-only realistic relative
  observation.
- Preserve both blocking benchmark gates on the Linux runner. If current
  nanosecond budgets fail on hosted Linux x86_64, re-baseline and retune from
  hosted Linux x86_64 evidence only; do not copy macOS timing assumptions and do
  not retune from local arm64 Linux-container timing.
- Make `--memory-observation` compile and run on Linux by adding a
  benchmark-target Linux RSS source. The core remains Foundation-free and
  untouched.
- Keep macOS CI limited to iOS device and iOS simulator compilation.
- Move WASM and embedded-WASM probes out of the macOS job. They should run on a
  Linux Swift container and remain observational: compile when a matching SDK is
  available/provisioned, otherwise print a nonblocking skip.
- Add docs-only CI skipping so changes under `docs/**` and Markdown-only changes
  do not spend runner minutes.
- Preserve the existing workflow concurrency behavior with
  `cancel-in-progress: true`.
- Update `AGENTS.md` so future sessions see the new runner topology and do not
  describe WASM as part of the macOS cross-target job.
- Record local and hosted evidence in the Slice 16 verification document,
  including any remaining GitHub billing/spending-limit blocker.

## Non-Goals

Slice 16 does not:

- change `Sources/TextEngineCore`;
- add Foundation or third-party dependencies to `TextEngineCore`;
- change the fixed-height or variable-height public API;
- add variable-height mutation, indexed metrics providers, ropes, piece tables,
  editor buffers, shaping, rendering, or UI integration;
- promote WASM or embedded-WASM checks to blocking;
- solve GitHub branch protection / required-check limitations;
- set up a self-hosted runner;
- restore the user's GitHub billing quota;
- turn RSS deltas into hard memory budgets;
- change realistic relative observation from nonblocking to blocking.

## Selected Approach

Split the current macOS-heavy workflow by actual platform requirement.

### Host Job On Linux

`host-tests-and-benchmark-gate` should run on:

```yaml
runs-on: ubuntu-latest
container: swift:6.2.1-bookworm
```

The job should keep checkout depth `0`, because the PR-only realistic relative
observation uses base/head commits and worktrees. The macOS-specific metadata in
the job must be replaced with Linux-compatible metadata:

- `swift --version`;
- `uname -a`;
- `/etc/os-release`;
- CPU information from `lscpu` when available.

The job must keep the current `timeout-minutes: 20` unless implementation
evidence shows it is too short for the split jobs.

The job must not call `xcodebuild` or macOS-only `sysctl` keys. This applies to
both the top-level `Show toolchain` step and the PR-only
`Observe realistic provider relative performance` step. The current observation
step has macOS-only metadata under `set -euo pipefail`:

```bash
echo "cpu_model=$(sysctl -n machdep.cpu.brand_string)"
xcodebuild -version
```

On Linux, the command substitution would fail before the benchmark comparison
runs. Slice 16 must remove `xcodebuild -version` from that step and replace the
CPU probe with guarded Linux-compatible metadata, such as `lscpu` or
`/proc/cpuinfo` with `|| true`, so the nonblocking observation still executes
and records benchmark output instead of silently dying in setup.

The benchmark gate commands remain:

```bash
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

The current budgets are expected to have large enough margins, but they are
macOS-calibrated. Implementation must run the gates on the selected Linux
environment and record the evidence. Retuning nanosecond budgets is allowed
only from hosted Linux x86_64 evidence. Local Apple Silicon Linux-container
results may prove that the gates pass with margin, but they are not a valid
source for new budgets. If hosted runs are still billing-blocked, keep the
existing macOS-calibrated budgets and document the evidence gap instead of
retuning from local arm64 Linux data.

### Linux RSS Source For `--memory-observation`

`MemoryObservationDiagnostics.swift` currently imports `Darwin` and reads
resident size with Mach `task_info`. That cannot compile on Linux.

The diagnostic should become host-conditional:

- Darwin path keeps the existing Mach RSS implementation.
- Linux path uses `Glibc` and `/proc/self/statm`. The parser must read the
  second whitespace-delimited field, `resident`, from the Linux format
  `size resident shared text lib data dt`, then multiply by the runtime page
  size from `sysconf(_SC_PAGESIZE)`.
- Unsupported hosts return `nil` so the existing `rss_unavailable` failure
  path remains explicit.

This stays in `Sources/ViewportBenchmarks`. It must not add Foundation to
`Sources/TextEngineCore`, and it does not need to add Foundation to the
benchmark target either. A C stdio / Glibc implementation is enough for the
small `/proc/self/statm` parser.

The output schema should remain compatible:

```text
mode=memory_observation ... rss_page_size_bytes=<n> observation=pass
```

Linux will usually report a different page size than Apple Silicon macOS. That
is expected and should be recorded as runner evidence, not treated as a
regression. Linux `statm` resident pages include shared pages and are not
semantically identical to Mach `resident_size`; the diagnostic remains an
observational RSS signal, not a cross-platform byte-for-byte memory oracle.

### Cross-Target Jobs

The current `.github/scripts/cross-target-compile.sh` helper runs all
cross-target probes in one invocation. Slice 16 should preserve the default
local behavior, but add target selection for CI:

```bash
./.github/scripts/cross-target-compile.sh --targets ios
./.github/scripts/cross-target-compile.sh --targets wasm
```

Default invocation without `--targets` remains equivalent to `--targets all` so
existing local documentation and verification commands keep working.

The helper must update `usage()` and argument parsing. Today every argument
other than `--self-test` and `--help` exits through usage with status `2`, so
`--targets` must be parsed before the current "any remaining argument is an
error" branch.

The macOS job becomes iOS-only:

- job name: `iOS cross-target compile`;
- runner: `macos-latest`;
- timeout: `timeout-minutes: 20`, matching the current cross-target job unless
  evidence shows the split job needs a different value;
- command: `./.github/scripts/cross-target-compile.sh --targets ios`;
- iOS device and iOS simulator remain blocking;
- no WASM command is executed on macOS.

The WASM job becomes Linux-only:

- job name: `WASM cross-target observation`;
- runner: `ubuntu-latest`;
- container: `swift:6.2.1-bookworm`;
- timeout: `timeout-minutes: 20`, matching the current cross-target job unless
  evidence shows the split job needs a different value;
- command: `./.github/scripts/cross-target-compile.sh --targets wasm`;
- WASM and embedded-WASM remain observational and nonblocking;
- if a matching SDK is unavailable, the job records `result=skipped` with a
  stable reason instead of failing the workflow.

The helper output must make selected vs. not-requested targets explicit enough
for verification to prove that macOS did not run WASM. For example, unselected
targets may emit `result=skipped reason=not_requested`, while selected targets
keep the existing `pass`, `fail`, or `skipped` meanings.

`not_requested` targets must always be emitted with `blocking=false` and must
not contribute to `blocking_failures`; otherwise the Linux WASM job would fail
only because its iOS targets were intentionally not selected.

The helper self-test must cover target selection parsing and summary behavior.

### Docs-Only Skip

Add path filtering to the workflow:

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

This intentionally skips CI for documentation-only commits, including
Markdown-only guide updates. If a change includes workflow YAML, Swift sources,
scripts, package metadata, or tests, CI still runs. This directly addresses the
Slice 15 review finding that docs-only commits consumed macOS minutes.

The existing `concurrency` block should stay in place:

```yaml
concurrency:
  group: swift-ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## Rejected Alternatives

### Keep WASM In The macOS Cross-Target Job

Rejected. WASM does not require Xcode. The only reason it currently runs in the
macOS job is historical coupling inside one helper invocation. Keeping that
coupling would preserve unnecessary macOS work and contradict the Slice 16 goal
that macOS should be reserved for iOS.

### Move Host Job To Linux But Leave RSS On macOS

Rejected. This would avoid the Linux RSS implementation, but it would keep an
extra macOS job for an observational diagnostic. The diagnostic is benchmark
target code, not core code, and a small Linux `/proc/self/statm` path is a
better tradeoff than preserving macOS spend.

### YAML-Only Docs Skip

Rejected as too small for the current blocker. It would stop future docs-only
minutes, but the dominant `host-tests-and-benchmark-gate` job would still run on
macOS whenever any code, script, or workflow file changes.

### Self-Hosted Runner

Deferred. A self-hosted Mac could remove GitHub-hosted macOS usage entirely, but
it is a larger operational slice. This slice keeps the hosted-runner model and
removes avoidable macOS work first.

## Risks And Mitigations

### Linux Timing May Differ From macOS Timing

The synthetic and variable-height gates use nanosecond budgets. The current
budgets were proven on local macOS and hosted macOS. Linux container timing may
have a different profile.

Mitigation: run both gates in the selected Linux environment before claiming the
slice complete. Keep budgets if they pass with clear margin. Retune only with
recorded hosted Linux x86_64 evidence, and document why the new budget still
catches real regressions. If hosted runners are billing-blocked, do not retune;
record the missing hosted timing evidence.

### Hosted Runners May Still Be Billing-Blocked

The GitHub account limit may still prevent hosted jobs from starting.

Mitigation: local Linux-container and local macOS verification still prove the
implementation mechanically. Hosted evidence must record the exact run IDs and
annotations. A billing-blocked run is not green hosted evidence.

### WASM May Still Skip Hosted

The Swift Debian container may not have matching WASM SDKs installed by default.
The helper already treats missing matching SDKs as nonblocking.

Mitigation: run WASM probes on Linux and record `pass`, `fail`, or `skipped`
there. Do not spend macOS minutes on a check that may skip.

### Docs-Only PRs Will Have No CI Status

Path filtering means docs-only PRs and pushes will not run the workflow.

Mitigation: this is intentional quota control. The repository already cannot
require checks in the private Free setup, and docs-only changes do not need host
tests or iOS compiles. Changes that include `.github/**`, scripts, Swift source,
tests, or package metadata still trigger CI.

### Container Tag Drift

Major/minor Docker tags can move over time.

Mitigation: use the patch-level `swift:6.2.1-bookworm` tag selected for this
slice. The verification document should record `swift --version` from the Linux
host job so future updates can be deliberate.

## Verification Requirements

Local verification before PR:

- `swift test`
- `swift build -c release`
- `swift run -c release ViewportBenchmarks -- --gate`
- `swift run -c release ViewportBenchmarks -- --variable-height --gate`
- `swift run -c release ViewportBenchmarks -- --memory-shape`
- `swift run -c release ViewportBenchmarks -- --memory-observation`
- `rg -n "Foundation" Sources/TextEngineCore` with no matches
- `./.github/scripts/cross-target-compile.sh --self-test`
- `./.github/scripts/cross-target-compile.sh --targets ios`
- `./.github/scripts/cross-target-compile.sh --targets wasm`
- Linux container run using `swift:6.2.1-bookworm` for at least:
  `swift test`, release build, both benchmark gates, memory-shape, and
  memory-observation
- Linux container run using `swift:6.2.1-bookworm` for
  `./.github/scripts/cross-target-compile.sh --targets wasm`, proving the Linux
  WASM job mechanics and expected nonblocking `pass` or `skipped` output with
  exit `0`
- workflow scans proving:
  - host job uses `ubuntu-latest` + `swift:6.2.1-bookworm`;
  - macOS job invokes only `--targets ios`;
  - WASM job runs on Linux and invokes only `--targets wasm`;
  - `paths-ignore` is present for pull requests and pushes;
  - old macOS-only metadata commands are gone from the Linux job;
  - the PR-only realistic relative observation step has no `xcodebuild` call,
    no unguarded macOS-only `sysctl`, and still runs
    `realistic-relative-observation.sh`;
  - split jobs keep `timeout-minutes: 20` unless verification records a reason
    for a different timeout.
- helper-output scans proving:
  - `--targets ios` emits selected iOS targets as blocking and unselected WASM
    targets as `blocking=false reason=not_requested`;
  - `--targets wasm` emits selected WASM targets as nonblocking and unselected
    iOS targets as `blocking=false reason=not_requested`;
  - `--targets wasm` exits `0` when WASM SDKs are unavailable and both WASM
    targets are skipped for `sdk_unavailable`.
- PR realistic-relative observation evidence proving `git worktree add` works
  inside the Linux container and does not fail because of checkout ownership or
  missing Git support.
- `git diff --check`

Hosted verification:

- PR run evidence for the Linux host job, iOS macOS job, and Linux WASM
  observation job, if GitHub runners start.
- Post-merge push run evidence on `main`, if GitHub runners start.
- If runners do not start, record the exact billing/spending-limit annotation
  and do not treat it as a passing hosted run.

## Completion Criteria

Slice 16 is complete when:

- avoidable macOS work has been removed from the workflow;
- host tests and benchmark gates run on Linux;
- macOS CI runs only blocking iOS device/simulator checks;
- WASM probes run outside macOS and remain observational;
- Linux RSS observation works or fails explicitly through the existing
  `rss_unavailable` path on unsupported hosts;
- docs-only changes no longer trigger Swift CI;
- `AGENTS.md` accurately describes the new CI topology;
- verification evidence is recorded under `docs/superpowers/verification/`;
- any hosted-runner billing blocker is documented with exact run IDs and
  annotations.
