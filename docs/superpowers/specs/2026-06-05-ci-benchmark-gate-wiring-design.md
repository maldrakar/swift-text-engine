# CI Benchmark Gate Wiring Design

Date: 2026-06-05

## Status

Approved design, written for user review.

## Source Context

This design is Slice 5 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slice 1 delivered fixed-height viewport range calculation and buffered
geometry traversal. Slice 2 delivered a generic document/source provider
contract and buffered document line cursor. Slice 3 delivered a release-mode
synthetic benchmark gate for the fixed-height headless pipeline. Slice 4 added
an opt-in realistic large-text provider benchmark outside `TextEngineCore`.

The Slice 4 post-slice review identified repository-level enforcement as the
largest remaining product-brief gap. The benchmark gate exists locally:

```text
swift run -c release ViewportBenchmarks -- --gate
```

The repository still has no committed CI configuration. The remote repository is
known to be:

```text
git@github.com:arthurbanshchikov/swift-text-engine.git
```

This slice wires the existing local gate into GitHub Actions so pull requests
and pushes to `main` can fail when host tests or the synthetic performance gate
fail.

## Scope

Add one GitHub Actions workflow that runs host Swift tests and the existing
synthetic benchmark gate.

The workflow triggers are:

- `pull_request`
- `push` to `main`

The workflow uses a hosted macOS runner because `ViewportBenchmarks` is a
host-oriented executable that imports `Darwin` and uses `ContinuousClock`.

This slice does not change `TextEngineCore`, `ViewportBenchmarks`,
`Package.swift`, or test sources.

## Goals

- Make the existing synthetic benchmark gate repository-enforceable.
- Run `swift test` in CI before the benchmark gate.
- Run `swift run -c release ViewportBenchmarks -- --gate` in CI.
- Fail the workflow when tests fail or the benchmark gate exits non-zero.
- Keep workflow output simple and diagnostic by logging the active Swift,
  Xcode, and host kernel versions.
- Keep CI scope narrow so Slice 5 closes one enforcement gap without changing
  benchmark semantics.
- Record local verification of the commands and workflow configuration.

## Non-Goals

- Adding realistic-provider budgets to `--gate`.
- Running `--realistic-provider` in CI.
- Memory, allocation, or resident-memory profiling.
- Checked-in baseline comparison or percentage-based regression comparison.
- Cross-target CI for WASM, embedded WASM, iOS device, or iOS simulator.
- Storage adapters, file-backed providers, ropes, piece tables, or editor
  buffers.
- Variable-height layout.
- Text shaping, bidi, font fallback, rich text, rasterization, or UI adapters.
- Changing benchmark budgets.
- Adding a shell script wrapper around the SwiftPM commands.

## Architecture

`TextEngineCore` remains a pure headless core. `ViewportBenchmarks` remains the
single executable target that owns benchmark timing, budget comparison, output
formatting, and process-exit behavior.

Slice 5 adds only repository infrastructure:

```text
.github/workflows/swift-ci.yml
```

The workflow runs one job, `host-tests-and-benchmark-gate`, on `macos-latest`.
The job checks out the repository, prints toolchain information, runs host
tests, and then runs the existing synthetic benchmark gate.

The workflow does not parse benchmark output. The benchmark executable already
owns gate semantics and returns a non-zero exit code when any synthetic scenario
fails. CI should trust that exit code instead of duplicating budget logic in
YAML.

## Workflow Behavior

The workflow file should have this behavior:

```yaml
name: Swift CI

on:
  pull_request:
  push:
    branches:
      - main

permissions:
  contents: read

concurrency:
  group: swift-ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  host-tests-and-benchmark-gate:
    name: Host tests and benchmark gate
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

      - name: Run host tests
        run: swift test

      - name: Run synthetic benchmark gate
        run: swift run -c release ViewportBenchmarks -- --gate
```

The `pull_request` trigger makes the gate available for PR checks. The
`push`-to-`main` trigger validates the protected branch after direct pushes or
after merges. Branch protection in GitHub can then require the workflow job
before merging.

## Components

### GitHub Actions Workflow

The workflow is the only committed implementation artifact for this slice.

Responsibilities:

- select the macOS hosted runner;
- define the approved triggers;
- check out the repository;
- show toolchain and host information;
- run `swift test`;
- run the existing synthetic benchmark gate.

### Verification Record

The slice verification record should be written to:

```text
docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
```

It should record:

- the absence of pre-existing committed CI configuration before this slice;
- the known GitHub remote URL supplied for the project;
- static workflow checks for triggers, runner, timeout, and commands;
- local `swift test` output;
- local `swift run -c release ViewportBenchmarks -- --gate` output;
- the limitation that local verification does not prove the first remote
  GitHub Actions runner result.

### Remote Setup

The known remote URL is:

```text
git@github.com:arthurbanshchikov/swift-text-engine.git
```

Adding `origin` locally is a repository setup action, not a committed artifact.
If the local clone still has no remote during implementation, it is acceptable
to run:

```text
git remote add origin git@github.com:arthurbanshchikov/swift-text-engine.git
```

This command is useful before pushing, but the CI design does not depend on a
local remote being present while the workflow file is authored.

## Data Flow

CI data flow:

1. GitHub receives a pull request event or a push to `main`.
2. GitHub Actions starts the `Swift CI` workflow.
3. `actions/checkout` materializes the commit under test.
4. The toolchain step prints Swift, Xcode, and kernel information.
5. `swift test` builds and runs `TextEngineCoreTests`.
6. `swift run -c release ViewportBenchmarks -- --gate` builds the release
   benchmark executable and runs the synthetic gate.
7. If either SwiftPM command exits non-zero, the job fails.
8. If both commands exit zero, the job passes.

The benchmark gate data flow remains unchanged from Slice 3 and Slice 4. Each
scenario prints line-oriented key-value output with measured p95/p99 values,
budgets, `failures`, `gate=pass` or `gate=fail`, and checksum. The executable
returns a non-zero exit code if any scenario exceeds its budget or records
failures.

## Error Handling

The workflow relies on command exit codes:

- `swift test` fails the job on build failures or test failures.
- `swift run -c release ViewportBenchmarks -- --gate` fails the job when the
  benchmark executable exits non-zero.
- GitHub Actions marks the job failed when any step fails.

The workflow should not use `continue-on-error` for the test or gate steps.

The workflow should not parse p95/p99 fields in YAML. Budget enforcement stays
inside `ViewportBenchmarks`, where the scenario definitions and gate logic
already live together.

## Testing And Verification

Implementation should verify the workflow in four layers.

First, confirm the repository state before adding CI:

```text
rg --files -g '.github/**' -g '.gitlab-ci.yml' -g 'bitbucket-pipelines.yml' -g 'Jenkinsfile' -g '.circleci/**'
git remote -v
```

Second, statically inspect the workflow after adding it:

```text
rg --files -g '.github/**'
rg -n "pull_request|push:|branches:|main" .github/workflows/swift-ci.yml
rg -n "runs-on: macos-latest|timeout-minutes: 20" .github/workflows/swift-ci.yml
rg -n "swift --version|xcodebuild -version|swift test|swift run -c release ViewportBenchmarks -- --gate|realistic-provider|swift build --swift-sdk|xcrun swiftc" .github/workflows/swift-ci.yml
```

The workflow should include the host test and synthetic gate commands. It
should not include realistic-provider execution or cross-target compile checks.

Third, run the workflow commands locally:

```text
swift test
swift run -c release ViewportBenchmarks -- --gate
```

Fourth, after the workflow is pushed to GitHub, inspect the first remote
GitHub Actions run. Local verification proves the commands pass on the current
host. It does not prove hosted-runner toolchain compatibility or performance
variance.

## Rollout

The implementation should be committed in two small commits:

1. `ci: add swift benchmark gate workflow`
2. `docs: record ci benchmark gate verification`

After pushing to `git@github.com:arthurbanshchikov/swift-text-engine.git`, the
first GitHub Actions run should be checked before treating CI as fully
operational. If `macos-latest` exposes a Swift toolchain mismatch or benchmark
variance, that should be handled as follow-up Slice 5 feedback rather than by
expanding this design mid-slice.

## Open Risks

- `macos-latest` can move over time, so future hosted-runner toolchain changes
  may affect benchmark latency or SwiftPM behavior.
- The existing budgets are conservative absolute budgets, not calibrated to a
  specific GitHub Actions machine generation.
- GitHub branch protection must be configured outside the repository workflow
  file if PR merge blocking is required at the repository settings level.
- This slice still does not measure memory usage, realistic-provider budgets,
  cross-target CI, storage adapter behavior, or variable-height layout.
