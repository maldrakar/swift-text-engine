# CI Benchmark Gate Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add repository CI wiring that runs host Swift tests and the existing synthetic release benchmark gate on pull requests and pushes to `main`.

**Architecture:** Use a single GitHub Actions workflow because the repository currently has no CI configuration and no remote metadata naming another provider. The workflow stays narrow: it runs `swift test` and `swift run -c release ViewportBenchmarks -- --gate` on a hosted macOS runner, logs the active toolchain, and does not add realistic-provider budgets, memory profiling, cross-target CI, or baseline comparison.

**Tech Stack:** GitHub Actions, hosted macOS runner, Swift Package Manager, `TextEngineCore`, `ViewportBenchmarks`.

---

## Scope Check

This plan implements the Slice 5 choice recorded in:

- `docs/superpowers/reviews/2026-06-05-slice-4-post-slice-review.md`

Slice 5 covers one subsystem: CI wiring for the existing synthetic benchmark
gate. It does not change `TextEngineCore`, `ViewportBenchmarks`, tests,
benchmark budgets, realistic-provider behavior, memory measurement, storage
adapter design, variable-height layout, or cross-target compile checks.

The repository currently has no CI files and no configured git remote. This
plan therefore chooses GitHub Actions explicitly as the CI provider for this
slice. If the repository is later hosted somewhere else, replace this plan with
the equivalent provider-specific workflow before implementation.

## File Structure

- Create `.github/workflows/swift-ci.yml`: GitHub Actions workflow for host
  tests and the synthetic benchmark gate.
- Create `docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md`:
  verification record for local workflow-command validation and static workflow
  checks.
- Leave `Package.swift` unchanged.
- Leave `Sources/TextEngineCore/*.swift` unchanged.
- Leave `Sources/ViewportBenchmarks/main.swift` unchanged.
- Leave `Tests/TextEngineCoreTests/*.swift` unchanged.

## Task 1: Preflight Current CI And Local Gate State

**Files:**
- Read: repository root
- Read: `docs/superpowers/reviews/2026-06-05-slice-4-post-slice-review.md`
- Read: `Package.swift`
- Read: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Confirm there is no existing CI configuration**

Run:

```bash
rg --files -g '.github/**' -g '.gitlab-ci.yml' -g 'bitbucket-pipelines.yml' -g 'Jenkinsfile' -g '.circleci/**'
```

Expected: command exits `1` with no output.

- [ ] **Step 2: Confirm no git remote names a different CI provider**

Run:

```bash
git remote -v
```

Expected: command exits `0`. In the current repository state there is no output.

- [ ] **Step 3: Run host tests before adding CI**

Run:

```bash
swift test
```

Expected: command exits `0`; all `TextEngineCoreTests` pass. The current suite
has 39 XCTest tests.

- [ ] **Step 4: Run the synthetic benchmark gate before adding CI**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Expected: command exits `0`; every benchmark output line includes
`failures=0` and `gate=pass`.

## Task 2: Add GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Create `.github/workflows/swift-ci.yml`**

Create the file with exactly this content:

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

- [ ] **Step 2: Confirm the workflow file is discoverable**

Run:

```bash
rg --files -g '.github/**'
```

Expected output:

```text
.github/workflows/swift-ci.yml
```

- [ ] **Step 3: Confirm the workflow includes the required CI triggers**

Run:

```bash
rg -n "pull_request|push:|branches:|main" .github/workflows/swift-ci.yml
```

Expected output includes one match for each of:

```text
pull_request:
push:
branches:
main
```

- [ ] **Step 4: Confirm the workflow uses the host macOS runner**

Run:

```bash
rg -n "runs-on: macos-latest|timeout-minutes: 20" .github/workflows/swift-ci.yml
```

Expected output includes:

```text
runs-on: macos-latest
timeout-minutes: 20
```

- [ ] **Step 5: Confirm the workflow runs only the intended commands**

Run:

```bash
rg -n "swift --version|xcodebuild -version|swift test|swift run -c release ViewportBenchmarks -- --gate|realistic-provider|swift build --swift-sdk|xcrun swiftc" .github/workflows/swift-ci.yml
```

Expected output includes:

```text
swift --version
xcodebuild -version
swift test
swift run -c release ViewportBenchmarks -- --gate
```

Expected output does not include matches for:

```text
realistic-provider
swift build --swift-sdk
xcrun swiftc
```

- [ ] **Step 6: Run the workflow's host test command locally**

Run:

```bash
set -o pipefail
swift test 2>&1 | tee /private/tmp/ci-benchmark-gate-swift-test.out
```

Expected: command exits `0`; all `TextEngineCoreTests` pass.

- [ ] **Step 7: Run the workflow's synthetic benchmark gate command locally**

Run:

```bash
set -o pipefail
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tee /private/tmp/ci-benchmark-gate-synthetic-gate.out
```

Expected: command exits `0`; every benchmark output line includes
`failures=0` and `gate=pass`.

- [ ] **Step 8: Commit the workflow**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: add swift benchmark gate workflow"
```

Expected: commit succeeds.

## Task 3: Record Slice Verification

**Files:**
- Create: `docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md`

- [ ] **Step 1: Create the verification record**

Create `docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md`
after running the commands in Tasks 1 and 2. Generate the file from the captured
local command output:

```bash
ruby - <<'RUBY'
test_output = File.read("/private/tmp/ci-benchmark-gate-swift-test.out").rstrip
gate_output = File.read("/private/tmp/ci-benchmark-gate-synthetic-gate.out").rstrip

content = <<~MARKDOWN
  # CI Benchmark Gate Wiring Verification

  Date: 2026-06-05

  ## Commands

  - `rg --files -g '.github/**' -g '.gitlab-ci.yml' -g 'bitbucket-pipelines.yml' -g 'Jenkinsfile' -g '.circleci/**'`: no pre-existing CI configuration before this slice
  - `git remote -v`: no configured remote before this slice
  - `rg --files -g '.github/**'`: pass
  - `rg -n "pull_request|push:|branches:|main" .github/workflows/swift-ci.yml`: pass
  - `rg -n "runs-on: macos-latest|timeout-minutes: 20" .github/workflows/swift-ci.yml`: pass
  - `rg -n "swift --version|xcodebuild -version|swift test|swift run -c release ViewportBenchmarks -- --gate|realistic-provider|swift build --swift-sdk|xcrun swiftc" .github/workflows/swift-ci.yml`: pass
  - `swift test`: pass
  - `swift run -c release ViewportBenchmarks -- --gate`: pass

  ## Workflow

  Created:

  ```text
  .github/workflows/swift-ci.yml
  ```

  The workflow runs on:

  ```text
  pull_request
  push to main
  ```

  The workflow job uses:

  ```text
  runs-on: macos-latest
  timeout-minutes: 20
  ```

  The workflow commands are:

  ```text
  swift --version
  xcodebuild -version
  uname -a
  swift test
  swift run -c release ViewportBenchmarks -- --gate
  ```

  ## Host Test Output

  `swift test`:

  ```text
  #{test_output}
  ```

  ## Synthetic Benchmark Gate Output

  `swift run -c release ViewportBenchmarks -- --gate`:

  ```text
  #{gate_output}
  ```

  ## Scope

  This slice wires the existing synthetic benchmark gate into GitHub Actions. It
  does not add realistic-provider budgets, memory profiling, cross-target CI
  checks, baseline comparison, storage adapters, or variable-height layout.

  The first remote GitHub Actions run after pushing this workflow should be checked
  before treating CI as fully operational. Local verification proves the commands
  used by the workflow pass on the current host; the remote runner may expose
  toolchain or performance variance that requires a follow-up adjustment.
MARKDOWN

File.write("docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md", content)
RUBY
```

Expected: command exits `0` and writes the verification record.

Run:

```bash
rg -n "PAST[E]|TB[D]|FIXM[E]" docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
```

Expected: command exits `1` with no matches.

- [ ] **Step 2: Confirm the verification record names the workflow and gate**

Run:

```bash
rg -n ".github/workflows/swift-ci.yml|swift run -c release ViewportBenchmarks -- --gate|gate=pass|realistic-provider budgets|cross-target CI" docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
```

Expected output includes matches for:

```text
.github/workflows/swift-ci.yml
swift run -c release ViewportBenchmarks -- --gate
gate=pass
realistic-provider budgets
cross-target CI
```

- [ ] **Step 3: Commit the verification record**

Run:

```bash
git add docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
git commit -m "docs: record ci benchmark gate verification"
```

Expected: commit succeeds.

## Task 4: Final Slice Check

**Files:**
- Read: `.github/workflows/swift-ci.yml`
- Read: `docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md`
- Read: `Package.swift`
- Read: `Sources/TextEngineCore`
- Read: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Confirm source code was not changed**

Run:

```bash
git diff HEAD~2..HEAD -- Package.swift Sources Tests
```

Expected: no diff output.

- [ ] **Step 2: Confirm CI and verification are the only slice changes**

Run:

```bash
git diff HEAD~2..HEAD --stat
```

Expected output mentions only:

```text
.github/workflows/swift-ci.yml
docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
```

- [ ] **Step 3: Re-run host tests after both commits**

Run:

```bash
swift test
```

Expected: command exits `0`; all `TextEngineCoreTests` pass.

- [ ] **Step 4: Re-run the synthetic benchmark gate after both commits**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Expected: command exits `0`; every benchmark output line includes
`failures=0` and `gate=pass`.

- [ ] **Step 5: Confirm final repository status**

Run:

```bash
git status --short
```

Expected: no output.

## Execution Notes

This plan intentionally cannot prove the first remote GitHub Actions execution,
because the repository currently has no configured remote. After pushing to a
GitHub repository, inspect the first workflow run. If the hosted runner's Swift
toolchain or benchmark variance fails the gate, treat that as Slice 5 feedback
and adjust the workflow or budgets in a separate review-backed follow-up.
