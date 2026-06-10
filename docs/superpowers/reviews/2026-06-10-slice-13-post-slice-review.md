# Slice 13 Post-Slice Review

Date: 2026-06-10

## Scope Reviewed

This review covers Slice 13: cross-target CI for `TextEngineCore` (the Option B
recommendation from the Slice 12 review).

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/reviews/2026-06-09-slice-12-post-slice-review.md`
- `docs/superpowers/specs/2026-06-09-cross-target-textenginecore-ci-design.md`
- `docs/superpowers/plans/2026-06-09-cross-target-textenginecore-ci.md`
- `docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md`
- `.github/workflows/swift-ci.yml`
- `.github/scripts/cross-target-compile.sh`
- `docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md` (for the
  still-active branch-protection blocker)
- PR #7 metadata, the hosted pull-request run, and the post-merge push run
- local git commit history for Slice 13
- fresh local host tests, release build, synthetic gate, memory-shape
  diagnostic, RSS memory-observation diagnostic, cross-target helper self-test,
  the non-graph iOS guard, the host-job-unchanged structural check, and the
  non-goal diff check

No `AGENTS.md`, `CLAUDE.md`, or top-level `README.md` project-conventions file
is present in the repository, so review uses the product brief, existing slice
documents, and universal review heuristics.

## Product Brief Alignment

The product brief requires `TextEngineCore` to compile for iOS and WASM without
source changes, and lists that portability as a success criterion. Since Slice 1
that criterion has been proven only on the maintainer's local machine. The Slice
11 and Slice 12 reviews both recommended landing cross-target CI before the next
public core API change (variable-height layout), so the variable-height work
could rely on continuous portability proof rather than local-only checks.

Slice 13 directly advances the iOS half of that criterion:

- It adds a separate, parallel `Cross-target compile` GitHub Actions job that
  compiles `TextEngineCore` for iOS device (`generic/platform=iOS`) and iOS
  simulator (`generic/platform=iOS Simulator`) through the Swift package graph
  with `xcodebuild`.
- Both iOS targets are blocking: the helper's exit code is driven only by the
  iOS results, so an iOS compile regression fails the job.
- The job runs on both `pull_request` and `push` to `main`, because it compiles
  the current tree and needs no base/head pair.
- It keeps the existing `Host tests and benchmark gate` job content unchanged, so
  the stable gates and the Slice 12 realistic relative observation are untouched.

Slice 13 deliberately delivers only a partial cross-target guarantee. The WASM
half is added as a best-effort, observational probe and, on the hosted runner,
was **skipped** rather than compiled (see Risks). Slice 13 intentionally does not
yet prove or enforce:

- continuous CI proof that `TextEngineCore` compiles for WASM or embedded WASM;
- a blocking WASM or embedded-WASM compile check;
- automatic promotion of the WASM probe from observational to blocking;
- repository settings that require any `Swift CI` check before `main` changes;
- a per-target build matrix;
- variable-height layout, localized invalidation, storage adapters, shaping,
  rasterization, or UI-framework integration;
- RSS, heap, malloc, allocation-count, or peak-memory hard budgets;
- any `TextEngineCore`, `ViewportBenchmarks`, `Tests`, or `Package.swift`
  source change (including a `platforms:` declaration).

Those remain out of scope for Slice 13.

## Delivered Design

Slice 13 is an infrastructure and verification slice. It made no
`TextEngineCore`, `ViewportBenchmarks`, `Tests`, or `Package.swift` changes. The
merged diff from the prior `main` head (`7c32928`) to the merge commit
(`6e205ae`) is:

```text
 .github/scripts/cross-target-compile.sh            |  317 +++++++
 .github/workflows/swift-ci.yml                     |   21 +
 ...09-cross-target-textenginecore-ci.md (verify)   |  959 ++++++++++++++++++
 .../2026-06-09-slice-12-post-slice-review.md       |  538 +++++++++++
 ...cross-target-textenginecore-ci-design.md        |  361 +++++++
 ...09-cross-target-textenginecore-ci.md (plan)     |  277 ++++++
 6 files changed, 2473 insertions(+)
```

(The Slice 12 post-slice review document rode in on the same PR; see Git History
and Risks.) The implementation matches the approved plan exactly.

### Helper

`.github/scripts/cross-target-compile.sh` compiles `TextEngineCore` for the four
non-host targets and prints one stable key-value line per target plus a summary
line. Notable design points:

- iOS device and simulator are built through the package graph
  (`xcodebuild build -scheme TextEngineCore -destination 'generic/platform=...'`),
  scheme-scoped so the `ViewportBenchmarks` executable is not built. There is no
  non-graph fallback: a guard confirms the helper contains no `xcrun swiftc`,
  `emit-module`, or `-Xswiftc` iOS path.
- The iOS path resolves the scheme through `xcodebuild -list` and distinguishes a
  genuine compile failure (`reason=compile_failed`) from an unresolved-scheme or
  list-failure infrastructure problem (`reason=scheme_unresolved`,
  `reason=xcodebuild_list_failed`) and a missing destination
  (`reason=destination_unavailable`). All of those make the blocking iOS target
  `result=fail` and fail the job.
- WASM and embedded WASM resolve a Swift SDK matched to the runner's own Swift
  version (parsed from `swift --version`), via `swift sdk list` and an optional
  `swift sdk install` from a configurable URL. When no matching SDK can be
  provisioned, they report `result=skipped reason=sdk_unavailable blocking=false`
  and contribute nothing to the exit code.
- Per-target line shape:
  `mode=cross_target_compile target=<...> result=<pass|fail|skipped> reason=<...> blocking=<true|false>`,
  followed by a `mode=cross_target_compile_summary ... blocking_failures=<n> exit=<0|1>` line.
- `--self-test` exercises the toolchain-independent logic (version parsing,
  result classification, blocking-failure counting, summary assembly, and the
  SDK-id resolver against clean and noisy `swift sdk list` text) without any
  toolchain. It keeps the testable-shell discipline established by the Slice 12
  observation helper.
- `set -uo pipefail` without `set -e` is intentional: the helper owns its own
  exit code so a non-iOS failure never aborts the run.

### Workflow

`.github/workflows/swift-ci.yml` keeps `host-tests-and-benchmark-gate` unchanged
and adds a sibling `cross-target-compile` job on `macos-latest` with
`timeout-minutes: 20`. The job checks out the repo, echoes the toolchain
(`developer_dir`, `xcode-select -p`, available Xcodes, `swift --version`,
`xcodebuild -version`, `uname -a`), and runs the helper. The two jobs run in
parallel, so the cross-target job does not extend the existing job's wall-clock.
The default-selected runner Xcode resolved the package scheme without needing a
`DEVELOPER_DIR` pin, so the documented pin contingency was not required.

PR #7 merged on 2026-06-09T21:16:21Z with merge commit `6e205ae`.

## Verification Evidence Reviewed

The Slice 13 verification document records passing local checks, the hosted PR
run (`27227780370` at head `5b157e9`), the toolchain and SDK metadata, the four
per-target lines and the summary, job timings, the WASM provisioning discovery,
and the post-merge push run.

Fresh local verification for this review on 2026-06-10 (Swift 6.2.1,
`arm64-apple-macosx`):

```text
swift test
```

Result: pass, 39 XCTest tests, 0 failures. (The Swift Testing harness reports
`0 tests in 0 suites` separately because this package has only XCTest tests;
this is not a regression.)

```text
swift build -c release
```

Result: pass.

```text
swift run -c release ViewportBenchmarks -- --gate
```

Result: pass (three `gate=pass` lines).

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 ... p95_ns=1225 p99_ns=1320 ... budget_p95_ns=20000 budget_p99_ns=50000 gate=pass
mode=pipeline scenario=100k_lines_80_visible_overscan_5 ... p95_ns=4994 p99_ns=5210 ... budget_p95_ns=50000 budget_p99_ns=100000 gate=pass
mode=pipeline scenario=1m_lines_200_visible_overscan_50 ... p95_ns=16596 p99_ns=17511 ... budget_p95_ns=100000 budget_p99_ns=200000 gate=pass
```

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass (three `invariant=pass` lines).

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Result: pass (three `observation=pass` lines).

```text
.github/scripts/cross-target-compile.sh --self-test
```

Result: `self_test=pass`.

Structural and non-goal checks:

```text
rg -n "xcrun swiftc|emit-module|-Xswiftc" .github/scripts/cross-target-compile.sh
```

Result: no output, exit code `1`. The iOS path is package-graph only.

```text
git diff 7c32928 HEAD -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Result: no output. No core, benchmark-code, test, or manifest changes across the
slice.

Host-job-unchanged structural check (extracting the
`host-tests-and-benchmark-gate` job content from `7c32928` and from the current
tree, excluding the separator blank line before the new sibling job, and diffing
them): identical (`host_job_nonblank_diff_exit=0`). Only the sibling
`cross-target-compile` job was added.

GitHub Actions metadata independently rechecked during this review via `gh`:

- PR #7 (`slice-12-post-slice-review` -> `main`) is `MERGED`, merge commit
  `6e205ae`.
- The recorded hosted PR run `27227780370` at head `5b157e9` concluded
  `success`. Runner: `macos-15-arm64`, `Apple M1 (Virtual)`, Swift 6.1.2, Xcode
  16.4, iPhoneOS/iPhoneSimulator 18.5 SDK. Cross-target job duration ~36s
  against a 20m timeout. iOS device and simulator `result=pass blocking=true`;
  WASM and embedded WASM `result=skipped reason=sdk_unavailable blocking=false`;
  summary `blocking_failures=0 exit=0`.
- The post-merge push run `27236364855` at the merge commit `6e205ae` concluded
  `success`, with both `Host tests and benchmark gate` and `Cross-target
  compile` jobs green. Its cross-target lines were re-fetched and match the
  verification record exactly: both iOS targets `pass`, both WASM targets
  `skipped`, summary `blocking_failures=0 exit=0`. On `push` the realistic
  relative observation step is correctly skipped (it is `pull_request`-only).

The verification document is accurate and, unlike the Slice 11 and Slice 12
records, does not lag the merged head: it explicitly notes that every commit
after the verified `5b157e9` is documentation-only
(`git diff 5b157e9..HEAD -- .github/` is empty), and it anchors proof of the
merged code in the post-merge push run.

## Git History

The Slice 13 planning and implementation sequence on the
`slice-12-post-slice-review` branch is:

```text
45f9aed docs: add slice 12 post-slice review
3666bff docs: design cross-target ci for TextEngineCore
5792ce3 docs: harden cross-target ci design after review
07fa749 docs: resolve iOS path contradiction in cross-target ci design
ec73dd4 docs: plan cross-target ci for TextEngineCore
a2cf10b docs: harden cross-target ci plan after review
73adaaa docs: refine cross-target ci plan after second review
a83cc2f ci: add cross-target compile helper
9af776d ci: add cross-target compile job
5b157e9 docs: record cross-target ci verification
485bab4 docs: update cross-target ci final run evidence
2eb863d docs: clarify cross-target ci verification head-sha coverage and wasm promotion note
6e205ae Merge pull request #7 from arthurbanshchikov/slice-12-post-slice-review
6ee4d94 docs: record cross-target ci post-merge run
```

The design -> (two hardening passes) -> contradiction-resolution -> plan -> (two
plan-hardening passes) -> implement helper -> implement job -> verify ordering is
clean and shows an unusually thorough pre-implementation review cycle for an
infrastructure slice. The trailing documentation commits refine the verification
record, and the post-merge commit (`6ee4d94`) records the push run, which is the
expected shape for capturing hosted evidence on the merge commit.

## Code Review Findings

No confirmed P0/P1/P2/P3 code findings were found for Slice 13.

The implementation matches the approved design:

- iOS device and simulator compile through the package graph; no non-graph
  fallback exists in the helper;
- the helper exit code reflects only the blocking iOS results;
- WASM and embedded WASM are observational, runner-toolchain-matched, and never
  fail the job;
- the helper distinguishes compile failures from scheme/list/destination
  infrastructure failures and from SDK-unavailable skips;
- `--self-test` covers the toolchain-independent logic and passes;
- the existing `host-tests-and-benchmark-gate` job content is unchanged from the
  prior `main`;
- Swift source, tests, package manifest, and benchmark budgets are untouched.

## Risks And Gaps

### WASM Portability Is Still Not Proven In CI

This is the headline gap. The brief's success criterion is "compiles without
source changes under iOS *and* WASM." Slice 13 makes the iOS half continuous in
CI, but on the hosted runner both WASM targets were **skipped**, not compiled:
the runner ran Swift 6.1.2, and no matching public WASM SDK exists for that exact
version (swift.org WASM SDKs start at 6.2; SwiftWasm publishes `6.1-RELEASE` but
not `6.1.2-RELEASE`; the exact-version probe returned HTTP 404). WASM portability
is therefore still proven only locally (Swift 6.2.1, both `wasm` and
`wasm-embedded` package-graph builds pass), exactly as it was before Slice 13.
The CI probe is in place and will begin compiling WASM automatically once a
matching SDK is provisionable, but today it produces a skip, not proof.

### WASM CI Completion Has An Engineering Path, Unlike Branch Protection

The WASM skip is caused by the runner's *default* Swift toolchain (6.1.2) having
no matching public WASM SDK. This is not a hard external block in the same sense
as the repository-ruleset blocker: pinning a known-good Swift toolchain on the
runner (for example via a setup-swift action, `swiftly`, or a container with
Swift 6.2.x) would make the matching swift.org WASM SDK provisionable and flip
the skip to a real compile. So WASM CI is a bounded engineering task gated by a
toolchain-pinning decision, not a paid-plan/visibility constraint. Alternatively,
waiting for the `macos-latest` image to ship Swift 6.2+ would unblock it
passively. The distinction matters for the Slice 14 choice below.

### Blocking iOS Check Still Cannot Gate `main` Merges

The iOS targets are "blocking" in that they fail the job, but a failing job only
blocks a merge if repository policy requires the check. Slice 6 documented that
GitHub rulesets and branch protection are unavailable for this private
repository:

```text
Upgrade to GitHub Pro or make this repository public to enable this feature.
```

That blocker is unchanged. Until the repository becomes public or moves to a plan
with rulesets/branch protection, the blocking iOS check (like the stable
synthetic gate) blocks the *check status*, not the *merge*.

### iOS Deployment Target Is The Toolchain Default

Because `Package.swift` declares no `platforms:`, the iOS compile uses whatever
baseline deployment target the runner toolchain selects. The build succeeds, but
the slice proves "compiles for some iOS deployment target the toolchain picked,"
not "compiles for a chosen minimum iOS." If a minimum-iOS contract becomes
relevant (for example for the UI integration layer), declaring `platforms:`
becomes an explicit decision, as the design already flagged.

### Slice/Branch/PR Bundling Reduces Traceability

Slice 13's implementation landed on a branch named `slice-12-post-slice-review`,
and PR #7 bundled the Slice 12 post-slice review document together with the Slice
13 spec, plan, implementation, and verification. The work is correct and the PR
title acknowledged both, but the branch name no longer matches its contents and a
reader must cross-reference dates and file names to see where Slice 12 ends and
Slice 13 begins. This is a documentation-traceability note, not a defect; keeping
the next slice's review on a clearly named branch (this review is on
`slice-13-post-slice-review`) restores the convention.

### Single Sequential Job Rather Than A Matrix

The four targets compile sequentially in one job. The design considered and
deferred a per-target matrix. This is fine for the first cross-target slice but
means a per-leg green/red status is not yet visible at a glance; a later slice may
split into a matrix if per-target status becomes valuable.

### Variable-Height Layout Remains The Largest Deferred Capability

The fixed-height proof envelope (synthetic gate, realistic-provider observation,
memory-shape invariant, RSS observation) plus continuous iOS cross-target CI is
now in place. Variable-height line indexing and localized invalidation remain the
largest unbuilt functional capability and the clearest remaining product value.
It needs public API and invalidation design and must not be mixed with CI,
portability, or policy work.

## Lessons For Slice 14

1. Cross-target CI is now half-complete: iOS is continuous and blocking, WASM is
   a CI probe that currently skips on the runner's default Swift 6.1.2. Slice 14
   must decide explicitly whether to finish WASM CI first or accept local-only
   WASM proof during the next functional slice.

2. The WASM gap is an engineering choice, not a hard external block. Pinning
   Swift 6.2.x on the runner (setup-swift / `swiftly` / container) would
   provision the matching swift.org WASM SDK and flip the skip to a compile.
   Track the `macos-latest` runner image's default Swift version; when it reaches
   6.2+, the probe should activate without a toolchain pin.

3. The fixed-height proof envelope plus continuous iOS CI is the de-risking floor
   for the variable-height pivot. iOS is the higher-impact host portability
   target and it is now continuous; WASM portability remains proven locally on
   6.2.1.

4. Keep variable-height layout design separate from CI, portability, and
   repository-policy work. Each needs its own design and review.

5. Continue anchoring verification proof in the post-merge push run on the merged
   head, as Slice 13 did. This avoided the one-commit-lag documentation issue
   flagged in the Slice 11 and Slice 12 reviews.

## Slice 14 Candidate Options

### Option A: Variable-Height Layout Foundation

Start the next major core capability: variable-height line indexing and localized
invalidation.

Suggested scope:

- Define the smallest height-index or measurement-cache boundary.
- Preserve the current fixed-height fast path and public behavior.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests for height changes.
- Re-run host, iOS (now continuous in CI), and local WASM/embedded WASM
  verification for the public core API or portability-sensitive source changes.
- Keep WASM CI promotion, branch protection, storage adapters, and memory-budget
  enforcement out of scope.

This is the strongest functional-value candidate. It is the deliberate pivot from
proof closure to functional expansion and carries the most public-API and
invalidation design risk. Slice 13 de-risked its iOS portability surface.

### Option B: Complete WASM Cross-Target CI

Convert the WASM probe from skipped to a real, runner-matched compile, optionally
toward blocking.

Suggested scope:

- Pin a known-good Swift toolchain on the runner (for example via a setup-swift
  action, `swiftly`, or a container) whose version has a matching swift.org WASM
  SDK, or wait for the `macos-latest` image to ship Swift 6.2+.
- Provision the matching `wasm` and `wasm-embedded` SDKs and compile
  `TextEngineCore` against them in CI.
- Keep the checks observational at first; promote to blocking only after hosted
  evidence shows provisioning and compile are reliable across runs.
- Do not change public core API in the same slice.

This finishes the brief's iOS-*and*-WASM portability-in-CI criterion and fully
de-risks the portability surface before the variable-height public-API change. It
is bounded and low-risk to the core, but it spends a slice on infrastructure
rather than functional value, and part of the path (waiting for the runner image)
is wall-clock-bound unless the toolchain is pinned.

### Option C: Storage Adapter / Provider Expansion

Exercise the proven provider contract with a non-synthetic storage shape (for
example a memory-mapped file, rope, or piece table) behind the existing
provider/source abstraction.

Suggested scope:

- Add one storage adapter, prove the core stays provider-agnostic, and prove
  core-owned memory stays bounded.
- Reuse the memory-shape and realistic-provider diagnostics for the new adapter.
- Keep variable-height layout and CI enforcement out of scope.

This adds functional breadth, but the provider contract is already proven, so it
is less urgent than variable-height layout.

### Option D: Memory Hard-Budget Or Allocator Signal

Extend the memory-proof thread from observation toward a stable budget.

Suggested scope:

- Investigate a focused malloc, peak-RSS, or allocation-count signal for the host
  executable that is stable enough for a threshold.
- Keep any new output observational unless stability is demonstrated.
- Do not change realistic-provider budgets or core layout behavior.

This continues the memory thread but is lower priority than functional expansion
or finishing portability CI.

### Option E: Independent No-Op Evidence Expansion And Threshold Recalibration

Continue the Slice 12 baseline-relative thread without enforcing it, by replacing
the five correlated reruns with independent samples and recalibrating the
threshold with real headroom.

Suggested scope:

- Collect no-op-equivalent samples from separate hosted run IDs across different
  days and runner allocations.
- Recompute the threshold with the real distribution and explicit headroom.
- Keep the step nonblocking; track progress toward the frozen 10-sample
  promotion bar.

This is honest progress toward future relative-gate blocking, but it is
wall-clock-heavy, low-code, and still gated downstream by the branch-protection
blocker.

### Not A Slice 14 Candidate: Repository Required Status Check

Requiring `Swift CI` for `main` remains externally blocked for this private
repository (Slice 6: "Upgrade to GitHub Pro or make this repository public"). It
should not be a Slice 14 engineering target until the repository becomes public
or moves to a plan with rulesets/branch protection. This applies equally to
making the iOS cross-target check actually gate merges and to promoting the
relative gate to blocking.

## Recommended Slice 14 Selection

Recommended: Option A, variable-height layout foundation.

Reasoning:

- The fixed-height proof envelope is complete, and Slice 13 added continuous iOS
  cross-target CI, which is the higher-impact host portability target. The Slice
  11 and Slice 12 lesson — land cross-target CI before the next public core API
  change — is now substantially satisfied for the platform that matters most for
  the eventual UI integration.
- Variable-height layout is the largest deferred functional capability and the
  clearest remaining product value. The highest engineering value now is
  functional expansion, not more infrastructure.
- The remaining WASM CI gap is real but is best handled opportunistically: it is
  partly wall-clock-bound (waiting for the runner image to reach Swift 6.2+) and,
  if pursued actively, is a self-contained infrastructure task that does not need
  to precede functional work. Local WASM proof on Swift 6.2.1 stays green during
  the variable-height work, so portability is not unverified, only not-yet-in-CI.

Choose Option B instead if the project wants the brief's iOS-and-WASM
portability-in-CI criterion fully closed before any public-API change and is
willing to pin a runner toolchain to provision a matching WASM SDK now; Option B
is small and would complete the cross-target story Slice 13 started. Choose
Option C, D, or E only if storage breadth, a memory budget, or continued
relative-gate evidence is explicitly more valuable right now than the next core
capability.

If Option A is selected, sequence it as: brainstorm the height-index/measurement
boundary, then a dedicated design and plan, keeping WASM CI, branch protection,
storage adapters, and memory budgets out of scope.

## Slice 13 Review Conclusion

Slice 13 cleanly completes its approved scope. It lands a separate, parallel
cross-target compile job, makes iOS device and simulator package-graph compiles
continuous and blocking in CI, adds a runner-toolchain-matched WASM probe that
correctly skips-with-record when no matching SDK exists, keeps the existing host
job content unchanged, and leaves all core source, tests, and the manifest
untouched. Local and hosted evidence (including the post-merge push run on the
merge commit) confirm both iOS targets pass and the WASM skip is nonblocking.

The slice should be counted as continuous iOS portability proof plus an honest,
evidence-backed deferral of WASM portability proof — not as a complete
iOS-and-WASM cross-target guarantee, which still depends on a matching WASM SDK
for the runner toolchain.

Slice 14 should usually pivot to functional expansion via variable-height layout
foundation, unless the project explicitly chooses to first finish WASM
cross-target CI, add a storage adapter, extend the memory signal, or keep
widening relative-gate evidence.
