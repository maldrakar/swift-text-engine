# CI Benchmark Gate Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub Actions CI that runs host Swift tests and the existing synthetic benchmark gate on pull requests and pushes to `main`.

**Architecture:** Add one narrow workflow at `.github/workflows/swift-ci.yml`. The workflow uses a hosted macOS runner, logs toolchain information, runs `swift test`, then runs `swift run -c release ViewportBenchmarks -- --gate`; benchmark gate semantics remain inside `ViewportBenchmarks`.

**Tech Stack:** GitHub Actions, macOS hosted runner, Swift Package Manager, `TextEngineCore`, `ViewportBenchmarks`, ripgrep.

---

## Scope Check

This plan implements the approved Slice 5 design:

```text
docs/superpowers/specs/2026-06-05-ci-benchmark-gate-wiring-design.md
```

The slice covers one subsystem: repository-level GitHub Actions wiring for the
existing synthetic benchmark gate.

This plan does not change:

- `TextEngineCore`
- `ViewportBenchmarks`
- `Package.swift`
- `Tests/TextEngineCoreTests`
- benchmark budgets
- realistic-provider behavior
- cross-target compile checks
- GitHub branch protection settings

The remote repository supplied for this project is:

```text
git@github.com:arthurbanshchikov/swift-text-engine.git
```

Local remote configuration is not a committed artifact for this slice.

## File Structure

- Create `.github/workflows/swift-ci.yml`: GitHub Actions workflow for host
  tests and the synthetic benchmark gate.
- Create `docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md`:
  verification record for local command output and static workflow checks.
- Leave `Package.swift` unchanged.
- Leave `Sources/TextEngineCore/*.swift` unchanged.
- Leave `Sources/ViewportBenchmarks/main.swift` unchanged.
- Leave `Tests/TextEngineCoreTests/*.swift` unchanged.

## Task 1: Preflight Current Repository State

**Files:**
- Read: `docs/superpowers/specs/2026-06-05-ci-benchmark-gate-wiring-design.md`
- Read: `docs/superpowers/reviews/2026-06-05-slice-4-post-slice-review.md`
- Read: `Package.swift`
- Read: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Confirm the approved design is present**

Run:

```bash
sed -n '1,260p' docs/superpowers/specs/2026-06-05-ci-benchmark-gate-wiring-design.md
```

Expected: command exits `0`; output includes:

```text
# CI Benchmark Gate Wiring Design
swift run -c release ViewportBenchmarks -- --gate
git@github.com:arthurbanshchikov/swift-text-engine.git
pull_request
`push` to `main`
```

- [ ] **Step 2: Confirm there is no committed CI configuration yet**

Run:

```bash
rg --files -g '.github/**' -g '.gitlab-ci.yml' -g 'bitbucket-pipelines.yml' -g 'Jenkinsfile' -g '.circleci/**'
```

Expected: command exits `1` with no output.

- [ ] **Step 3: Check local remote configuration**

Run:

```bash
git remote -v
```

Expected in the current local clone: command exits `0` with no output.

If the command prints a remote, it is acceptable only when the URL is:

```text
git@github.com:arthurbanshchikov/swift-text-engine.git
```

If the command prints a different repository URL, stop and ask the user before
continuing.

- [ ] **Step 4: Run host tests before adding CI and capture output**

Run:

```bash
set -o pipefail
swift test 2>&1 | tee /private/tmp/ci-benchmark-gate-swift-test.out
```

Expected: command exits `0`; output includes `Test Suite` and `0 failures`.

- [ ] **Step 5: Run the synthetic benchmark gate before adding CI and capture output**

Run:

```bash
set -o pipefail
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tee /private/tmp/ci-benchmark-gate-synthetic-gate.out
```

Expected: command exits `0`; output includes three `mode=pipeline` lines, each
with `failures=0` and `gate=pass`.

## Task 2: Add GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Create the workflow file**

Use `apply_patch` with this patch:

```diff
*** Begin Patch
*** Add File: .github/workflows/swift-ci.yml
+name: Swift CI
+
+on:
+  pull_request:
+  push:
+    branches:
+      - main
+
+permissions:
+  contents: read
+
+concurrency:
+  group: swift-ci-${{ github.workflow }}-${{ github.ref }}
+  cancel-in-progress: true
+
+jobs:
+  host-tests-and-benchmark-gate:
+    name: Host tests and benchmark gate
+    runs-on: macos-latest
+    timeout-minutes: 20
+
+    steps:
+      - name: Check out repository
+        uses: actions/checkout@v4
+
+      - name: Show toolchain
+        run: |
+          swift --version
+          xcodebuild -version
+          uname -a
+
+      - name: Run host tests
+        run: swift test
+
+      - name: Run synthetic benchmark gate
+        run: swift run -c release ViewportBenchmarks -- --gate
*** End Patch
```

Expected: `.github/workflows/swift-ci.yml` exists with the exact workflow
content above.

- [ ] **Step 2: Confirm the workflow file is discoverable**

Run:

```bash
rg --files -g '.github/**'
```

Expected output:

```text
.github/workflows/swift-ci.yml
```

- [ ] **Step 3: Confirm workflow triggers**

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

- [ ] **Step 4: Confirm runner and timeout**

Run:

```bash
rg -n "runs-on: macos-latest|timeout-minutes: 20" .github/workflows/swift-ci.yml
```

Expected output includes:

```text
runs-on: macos-latest
timeout-minutes: 20
```

- [ ] **Step 5: Confirm intended commands are present**

Run:

```bash
rg -n "swift --version|xcodebuild -version|uname -a|swift test|swift run -c release ViewportBenchmarks -- --gate" .github/workflows/swift-ci.yml
```

Expected output includes:

```text
swift --version
xcodebuild -version
uname -a
swift test
swift run -c release ViewportBenchmarks -- --gate
```

- [ ] **Step 6: Confirm out-of-scope commands are absent**

Run:

```bash
rg -n "realistic-provider|swift build --swift-sdk|xcrun swiftc" .github/workflows/swift-ci.yml
```

Expected: command exits `1` with no output.

- [ ] **Step 7: Run host tests after adding the workflow**

Run:

```bash
set -o pipefail
swift test 2>&1 | tee /private/tmp/ci-benchmark-gate-swift-test-after-workflow.out
```

Expected: command exits `0`; output includes `Test Suite` and `0 failures`.

- [ ] **Step 8: Run the synthetic benchmark gate after adding the workflow**

Run:

```bash
set -o pipefail
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tee /private/tmp/ci-benchmark-gate-synthetic-gate-after-workflow.out
```

Expected: command exits `0`; output includes three `mode=pipeline` lines, each
with `failures=0` and `gate=pass`.

- [ ] **Step 9: Commit the workflow**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: add swift benchmark gate workflow"
```

Expected: commit succeeds and records only `.github/workflows/swift-ci.yml`.

## Task 3: Record Slice Verification

**Files:**
- Create: `docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md`

- [ ] **Step 1: Create the verification record from captured output**

Run:

```bash
ruby - <<'RUBY'
test_output = File.read("/private/tmp/ci-benchmark-gate-swift-test-after-workflow.out").rstrip
gate_output = File.read("/private/tmp/ci-benchmark-gate-synthetic-gate-after-workflow.out").rstrip

content = <<~MARKDOWN
  # CI Benchmark Gate Wiring Verification

  Date: 2026-06-05

  ## Scope

  Slice 5 wires the existing synthetic benchmark gate into GitHub Actions.

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

  The known GitHub remote supplied for this repository is:

  ```text
  git@github.com:arthurbanshchikov/swift-text-engine.git
  ```

  ## Commands

  - `rg --files -g '.github/**' -g '.gitlab-ci.yml' -g 'bitbucket-pipelines.yml' -g 'Jenkinsfile' -g '.circleci/**'`: no committed CI configuration before this slice
  - `git remote -v`: no configured local remote before this slice in the current clone
  - `rg --files -g '.github/**'`: pass
  - `rg -n "pull_request|push:|branches:|main" .github/workflows/swift-ci.yml`: pass
  - `rg -n "runs-on: macos-latest|timeout-minutes: 20" .github/workflows/swift-ci.yml`: pass
  - `rg -n "swift --version|xcodebuild -version|uname -a|swift test|swift run -c release ViewportBenchmarks -- --gate" .github/workflows/swift-ci.yml`: pass
  - `rg -n "realistic-provider|swift build --swift-sdk|xcrun swiftc" .github/workflows/swift-ci.yml`: no matches
  - `swift test`: pass
  - `swift run -c release ViewportBenchmarks -- --gate`: pass

  ## Workflow Commands

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

  ## Non-Goals Confirmed

  This slice does not add realistic-provider budgets, run `--realistic-provider`
  in CI, add memory profiling, add baseline comparison, add cross-target CI,
  change benchmark budgets, add storage adapters, or start variable-height
  layout work. It also does not configure GitHub branch protection settings.

  ## Remote Runner Follow-Up

  Local verification proves the workflow commands pass on the current host. The
  first GitHub Actions run after pushing to
  `git@github.com:arthurbanshchikov/swift-text-engine.git` should be checked
  before treating CI as fully operational. Hosted-runner toolchain differences
  or performance variance should be handled in a follow-up slice or review-backed
  adjustment.
MARKDOWN

File.write("docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md", content)
RUBY
```

Expected: command exits `0` and writes the verification record.

- [ ] **Step 2: Scan the verification record for incomplete markers**

Run:

```bash
rg -n "TB[D]|TO[D]O|FIXM[E]|PLACEHOLD[E]R|X[X]X" docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
```

Expected: command exits `1` with no output.

- [ ] **Step 3: Confirm the verification record names the workflow, gate, and scope boundaries**

Run:

```bash
rg -n ".github/workflows/swift-ci.yml|swift run -c release ViewportBenchmarks -- --gate|gate=pass|git@github.com:arthurbanshchikov/swift-text-engine.git|realistic-provider budgets|cross-target CI" docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
```

Expected output includes matches for:

```text
.github/workflows/swift-ci.yml
swift run -c release ViewportBenchmarks -- --gate
gate=pass
git@github.com:arthurbanshchikov/swift-text-engine.git
realistic-provider budgets
cross-target CI
```

- [ ] **Step 4: Commit the verification record**

Run:

```bash
git add docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
git commit -m "docs: record ci benchmark gate verification"
```

Expected: commit succeeds and records only the verification document.

## Task 4: Final Slice Check

**Files:**
- Read: `.github/workflows/swift-ci.yml`
- Read: `docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md`
- Read: `Package.swift`
- Read: `Sources/TextEngineCore`
- Read: `Sources/ViewportBenchmarks/main.swift`
- Read: `Tests/TextEngineCoreTests`

- [ ] **Step 1: Confirm source code was not changed by the slice**

Run:

```bash
git diff HEAD~2..HEAD -- Package.swift Sources Tests
```

Expected: no diff output.

- [ ] **Step 2: Confirm CI and verification are the only implementation changes**

Run:

```bash
git diff HEAD~2..HEAD --stat
```

Expected output mentions only:

```text
.github/workflows/swift-ci.yml
docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
```

- [ ] **Step 3: Re-run host tests after both implementation commits**

Run:

```bash
swift test
```

Expected: command exits `0`; all `TextEngineCoreTests` pass.

- [ ] **Step 4: Re-run the synthetic benchmark gate after both implementation commits**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Expected: command exits `0`; output includes three `mode=pipeline` lines, each
with `failures=0` and `gate=pass`.

- [ ] **Step 5: Confirm final repository status**

Run:

```bash
git status --short
```

Expected: no output.

## Execution Notes

This implementation cannot prove the first remote GitHub Actions execution
until the workflow is pushed to GitHub. After pushing to
`git@github.com:arthurbanshchikov/swift-text-engine.git`, inspect the first
workflow run before treating CI as fully operational.

If the hosted runner's Swift toolchain or benchmark variance fails the gate,
record that as Slice 5 feedback and address it in a review-backed follow-up.
Configure GitHub branch protection outside this repository if PR merge blocking
must require the new `Swift CI` workflow job.
