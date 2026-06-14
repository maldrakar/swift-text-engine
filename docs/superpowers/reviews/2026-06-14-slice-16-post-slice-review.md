# Slice 16 Post-Slice Review

Date: 2026-06-14

## Scope Reviewed

This review covers Slice 16: CI resource optimization — moving avoidable Swift CI
work off hosted macOS onto a Linux Swift container while keeping iOS blocking,
WASM observational, and the full verification-evidence trail. Merged through
PR #13 (`slice-16-ci-resource-optimization`) into `main` as merge commit
`7030f8698d812b084929452b8016bf59c1992494`
(`Merge pull request #13 from maldrakar/slice-16-ci-resource-optimization`).

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-13-ci-resource-optimization-design.md`
- `docs/superpowers/plans/2026-06-13-ci-resource-optimization.md`
- `docs/superpowers/verification/2026-06-13-ci-resource-optimization.md`
- `docs/superpowers/reviews/2026-06-13-slice-15-post-slice-review.md` (the
  predecessor review that recommended this slice as its Option A)
- `AGENTS.md` / `CLAUDE.md` as current repository conventions
- PR #13 metadata, hosted pull-request CI runs, merge commit, and the post-merge
  push run on `main`
- Slice 16 source/CI/guide diff (`381a889..65ce4f0`, non-doc files)
- Merged benchmark sources `Sources/ViewportBenchmarks/main.swift` and
  `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`
- Fresh local host tests, release build, synthetic gate, variable-height gate,
  memory-shape diagnostic, RSS memory observation, cross-target helper self-test,
  Foundation-free scan, and `git diff --check`

This is an infrastructure/CI slice. It changes CI topology and the benchmark
executable's host portability. It deliberately does not touch `TextEngineCore`,
`Tests/TextEngineCoreTests`, `Package.swift`, or any public API.

## Product Brief Alignment

Slice 16 changes only CI and the benchmark executable, so every hard constraint
holds by construction:

- `TextEngineCore` is untouched: it stays headless, Foundation-free,
  zero-dependency, and Embedded/cross-target compatible. The Foundation-free scan
  is clean.
- The Linux RSS support and portable entry point live in
  `Sources/ViewportBenchmarks`, the executable that the package layout already
  designates for diagnostics and reference providers — not in the core.
- iOS device + simulator stay **blocking** on the only hosted macOS job; WASM and
  embedded WASM stay **observational**. The "compiles for iOS and WASM with no
  source changes" contract is preserved and now exercised from two split jobs.

The slice does not change budgets (see Budget Decision), promote hosted WASM to
blocking, add variable-height mutation structure, or alter the core.

## Delivered Design

Merged non-doc diff (`381a889..65ce4f0`):

```text
 .github/scripts/cross-target-compile.sh                 | 143 ++++++++++++---
 .github/workflows/swift-ci.yml                          |  58 +++++--
 AGENTS.md                                               |  31 ++-
 Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift | 84 ++++++++
 Sources/ViewportBenchmarks/main.swift                   |   6 +-
 5 files changed, 281 insertions(+), 41 deletions(-)
```

Three implementation commits — `eef951c` (cross-target target selection),
`39503cb` (Linux benchmark memory observation), `08bdd28` (move host + WASM
checks to Linux) — plus `7c616c2` (AGENTS.md topology) and the design/plan/
verification docs.

### Cross-Target Helper Target Selection (Decision 1)

`.github/scripts/cross-target-compile.sh` gains `--targets all|ios|wasm`
(default `all`), pure `parse_target_selection` / `target_requested` /
`mark_not_requested` helpers, and a `LAST_BLOCKING` per-target flag so
not-requested targets emit `result=skipped reason=not_requested blocking=false`
and never count as blocking failures. WASM SwiftPM artifacts now build under a
`${WORK}/swiftpm-${target_name}` scratch path instead of workspace `.build`. The
self-test was extended with selection assertions and passes (`self_test=pass`).
This lets the iOS job run only iOS and the WASM job run only WASM from one shared
script, preserving the iOS-blocking / WASM-nonblocking contract.

### Linux Benchmark Portability (Decision 2)

`main.swift` replaces the Darwin-only import + qualified `Darwin.exit` with
`#if canImport(Darwin) / #elseif os(Linux) import Glibc` and an unqualified
`exit`. The `#available(macOS 13.0, *)` check resolves through the `*` arm on
Linux, so Linux uses the main branch and never hits the macOS-only `fatalError`.

`MemoryObservationDiagnostics.swift` keeps the Darwin Mach RSS path and adds a
Linux path: `currentLinuxRSSSnapshot()` reads `/proc/self/statm`, parses the
**second** field (`resident`, field index 1) via a digit-by-digit
overflow-checked scan in `linuxResidentPages(fromStatmLine:)`, and multiplies by
`sysconf(_SC_PAGESIZE)`. `readLinuxStatmLine()` reads the line and decodes the
non-NUL `CChar` prefix as UTF-8 (avoiding `String(cString:)`). This is the field
the brief's memory invariant needs, and the result is correct on hosted Linux
(`rss_page_size_bytes=4096`, all rows `observation=pass`).

### CI Topology Move (Decision 3)

`.github/workflows/swift-ci.yml`:

- Host job → `runs-on: ubuntu-latest` + `container: swift:6.2.1-bookworm`, the
  1x Linux billing rate. Swift commands use `--scratch-path
  /tmp/text-engine-host-build` so the container does not write root-owned
  artifacts into the checked-out workspace; the PR-only realistic observation
  step marks the workspace `safe.directory` before Git operations.
- Cross-target split into `ios-cross-target-compile` (`macos-latest`,
  `--targets ios`, the only hosted macOS job) and `wasm-cross-target-observation`
  (`ubuntu-latest` + Swift container, `--targets wasm`).
- `paths-ignore: ['docs/**', '**/*.md']` on `pull_request` and `push` to skip
  docs-only triggers; `concurrency.cancel-in-progress` retained; all three jobs
  `timeout-minutes: 20`.

`AGENTS.md` is updated to describe the three-job topology, the host scratch path,
and the docs-only skip semantics, keeping the per-session source of truth current
(`CLAUDE.md` imports it).

## Verification Evidence Reviewed

Fresh local verification on 2026-06-14 against the merged content
(`/tmp/slice-16-review-verify.out`):

- `swift test` → pass, **67 XCTest tests, 0 failures** (the Swift Testing harness
  separately prints `0 tests in 0 suites`, expected for this XCTest-only package).
- `swift build -c release` → `Build complete!`.
- `--gate` → three `mode=pipeline` rows, each `failures=0 gate=pass` (1M
  `p95_ns=17058 p99_ns=17984` against `100000`/`200000`).
- `--variable-height --gate` → three `mode=variable_height` rows, each
  `gate=pass` (1M `p95_ns=2176 p99_ns=2309` against `250000`/`500000`).
- `--memory-shape` → every row `invariant=pass` (synthetic/large-text
  `core_owned_bytes=74`, variable-uniform `core_owned_bytes=90`).
- `--memory-observation` → all three rows `observation=pass`,
  `rss_page_size_bytes=16384` (Apple-silicon page size; the Linux path is proven
  hosted below).
- `cross-target-compile.sh --self-test` → `self_test=pass`.
- `rg "Foundation" Sources/TextEngineCore` → no output (core stays
  Foundation-free).
- `git diff --check` → no output.

### Hosted Evidence

Hosted CI was the entire point of the slice, and it is now green — both the
pull-request head and the merge commit:

- **PR run `27493957434`, head `0d0f0ca`** → `success` on all three jobs. Host
  job on hosted Linux `x86_64-unknown-linux-gnu` (`swift:6.2.1-bookworm`):
  `swift test` = `Executed 67 tests, with 0 failures` in 0.212s; synthetic gate
  `gate=pass` ×3; variable-height gate `gate=pass` ×3; memory-shape
  `invariant=pass`; memory-observation `observation=pass` with
  `rss_page_size_bytes=4096` (the Linux `/proc/self/statm` path). iOS job on
  macOS: `ios_device`/`ios_simulator` `result=pass blocking=true`. WASM job on
  Linux: `wasm`/`wasm_embedded` `result=skipped reason=sdk_unavailable`
  (observational). The PR-only realistic observation step **did not run its
  script** — see the P2 finding below; it failed at line 1 under the container
  shell and was masked green by `continue-on-error`.
- **Post-merge push run `27494701290`, merge commit `7030f86`** → `success` on
  all three jobs, same shape (`swift test` 67/0 in 0.213s, all gates `gate=pass`,
  iOS blocking pass, WASM observational). This is the merged-code anchor.

**This resolves the predecessor review's largest open item.** The Slice 15 review
recorded that no hosted post-merge evidence could be produced because the GitHub
Actions account spending limit/billing was exhausted. Slice 16's post-merge push
run is green hosted evidence on `main` — the first since `27430943082` predating
the Slice 15 merge.

**It also resolves the long-standing local `swift test` question.** The Slice 16
verification record had a deep root-cause investigation showing the full-suite
`swift test` hang in local Docker Desktop (both arches) was a VM artifact, not a
core/test defect, but could not prove it locally. Hosted Linux x86_64 now runs
`swift test` to 67/0 in ~0.2s, confirming the hang was environmental. See
[[docker-swift-test-hang]].

## Budget Decision Reviewed

No benchmark budgets changed, and the Slice 15 risk that "macOS-calibrated
nanosecond budgets may not transfer to a Linux runner" is **resolved by
evidence**: hosted Linux x86_64 is slower in absolute ns than local macOS (worst
case synthetic 1M `p95_ns≈34k` hosted vs `≈17k` local) but still well under
budget — ~34% of the `100000` p95 budget, ~18% of the `200000` p99 budget. The
gates pass with comfortable margin on the new runner; no retune was required. The
second Slice 15 risk (`--memory-observation` is host-specific) is resolved by the
added Linux RSS path, confirmed `observation=pass` hosted with the Linux 4096
page size.

## Git History

Reviewed commit range on `origin/main`:

```text
8b4e0d2 docs: design ci resource optimization
d994252 docs: plan ci resource optimization
6bc946d docs: revise ci optimization plan per validation
eef951c ci: add cross-target target selection
39503cb feat: support linux benchmark memory observation
08bdd28 ci: move host and wasm checks to linux
7c616c2 docs: document ci resource topology
e33e912 docs: record ci resource optimization verification
507ece0 docs: record ci resource optimization pr evidence
7ef1464 docs: record ci resource optimization rerun blocker
d6859db docs: complete ci resource optimization scan evidence
f6aecb1 docs: scope docs-only CI skip and record swift-test hang root cause
0d0f0ca docs: mark slice 16 plan steps complete
65ce4f0 docs: record green hosted pr evidence
7030f86 Merge pull request #13 from maldrakar/slice-16-ci-resource-optimization
4aa42c6 docs: record ci resource optimization post-merge run
```

One logical change per commit, conventional prefixes. Three code commits
(`eef951c`, `39503cb`, `08bdd28`) plus the AGENTS.md topology doc, surrounded by
spec/plan/verification docs.

**Out-of-band history note (not a code defect):** between the original
implementation and merge, the branch history was rewritten by the maintainer
(all SHAs changed; the pre-rewrite SHAs `c84acfe`/`bf149d3`/`04c5676` referenced
in early verification commits no longer exist), and the account was renamed, so
the canonical owner is now `maldrakar/swift-text-engine`. The verification record
was updated to the post-rewrite SHAs and the green runs. The post-merge
verification commit (`4aa42c6`) was pushed directly to `main` with admin bypass
because the new `main` ruleset forbids non-PR updates (see Risks).

## Code Review Findings

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None.

### P2 / Production Readiness

#### P2 - Slice 16 silently broke the PR-only realistic observation on Linux

`swift-ci.yml` runs the `Observe realistic provider relative performance` step
with `run: |` beginning `set -euo pipefail` and no `shell:` override. On the old
`macos-latest` host job the default shell was bash, so this worked. Slice 16
moved the host job into the `swift:6.2.1-bookworm` container, where GitHub runs
`run` steps under `sh`; `sh` rejects `set -o pipefail`. Confirmed in the hosted
logs (PR run `27493957434` and PR-head run `27494604926`):

```text
/__w/_temp/<id>.sh: 1: set: Illegal option -o pipefail
##[error]Process completed with exit code 2
```

The step therefore dies at line 1 and **never reaches
`realistic-relative-observation.sh`** — no base/head worktrees, no relative
ratio, no observation output. Because the step is `continue-on-error: true`, the
job stays green, so `gh run view --json jobs` reports `success` and the breakage
is invisible at the job level. This review initially misread the `threshold`
env echo in the `##[group]Run` block as script output and wrongly recorded the
step as having succeeded; corrected above.

Severity P2, not higher: the step is PR-only, observational, and
non-blocking by design, so it does not affect the core, the blocking gates, or
merge safety. But a silently-dead observation masked by a green check is a real
regression introduced by this slice.

**Fixed in PR #15** (merged to `main` as `081c6e4`): added `shell: bash` to that
step (the Debian container ships bash; it was the only step in the workflow using
`set -o pipefail`, the other multi-line `run: |` steps are sh-safe). Verified by
hosted run `27497860966`, where the step ran under
`bash --noprofile --norc -e -o pipefail {0}`, prepared the base/head worktrees,
and executed `realistic-relative-observation.sh`:
`p95_ratio=1.012507 p99_ratio=1.045687 max_ratio=1.045687
observation_threshold=1.221556 observation=clean` — no `Illegal option` line.

### P3 / Minor But Valid

#### P3 - `main.swift` macOS-version fallback is dead on Linux

`main.swift` guards `runProgram` behind `#available(macOS 13.0, *)` with a
`fatalError` else-branch. On Linux the `*` availability arm is always taken, so
the `fatalError` is unreachable there, and on macOS the deployment target makes
it effectively unreachable too. This is harmless and matches the approved plan;
if a future slice revisits the entry point, the guard could be simplified. No
action required for Slice 16.

#### Observation - `readLinuxStatmLine` improved over the plan

The merged `readLinuxStatmLine()` decodes the non-NUL `CChar` prefix as UTF-8
rather than the plan's `String(cString:)`. This is a safe improvement (no
dependence on NUL termination of the parsed slice), correctly recorded here as an
observation, not a finding.

## Risks And Gaps

### Green CI Does Not Gate Merges; `main` Ruleset Has No Required Checks (New)

A `main` branch ruleset (id `17656807`, "Main", created 2026-06-14, enforcement
active) now exists: it enforces a pull-request flow (`required_approving_review_count: 0`),
forbids direct non-fast-forward updates, allows merge/squash/rebase, and grants
the Admin repository role an **always** bypass. It has **no `required_status_checks`
rule.** Consequence: a green Swift CI run does not block merge, and a red one does
not either — PR #13 was merged, and the post-merge doc pushed, via admin bypass
while `mergeStateStatus` was `BLOCKED`. This is the long-running "repository policy
cannot require the check" gap from earlier slices, now half-closed (PR flow is
enforced) but not finished (CI is still advisory). Adding a `required_status_checks`
rule for the three jobs is the natural repo-policy follow-up. See
[[slice-16-direction]] and the ruleset design spec referenced in `AGENTS.md`.

### AGENTS.md Branch-Protection Caveat Is Now Stale (New)

`AGENTS.md` still states "this is a private repo without branch protection /
required checks ... Last verified: 2026-06-12." Both clauses are now false: the
repo is **public** and `main` is under an **active ruleset**. The caveat's
conclusion (a red check does not block merge) is still true today only because the
ruleset has no required checks. This factual correction is repo-policy work; per
the repo's "separate concerns / separate slices" rule it is flagged here for the
follow-up policy slice rather than fixed inside this review branch.

### Billing Root Cause Was Account-Level, Not Repo Visibility (Resolved, Recorded)

The trigger for this slice was the Actions billing wall. During verification the
root cause was localized: the block was an **account-level failed payment**, and
making the repository **public did not bypass it** — Linux minutes are free on
public repos, but a delinquent account suspends Actions account-wide, and macOS
runners are never free. CI only went green after the maintainer cleared the
account payment. The slice's 1x-Linux move still materially cuts future macOS
spend (the dominant ~1550 quota-minute host job moves to ~155 at 1x), so the
optimization stands on its own merits independent of the billing event.

### Realistic Observation Step Was Dead On Linux (Fixed in PR #15)

The P2 finding above. The PR-only relative-performance observation produced no
data from the moment the host job moved to the container until the fix, and the
green job status hid it. **Resolved in PR #15** (`shell: bash`, merged as
`081c6e4`, verified by run `27497860966` emitting `observation=clean`). The
verification record
(`docs/superpowers/verification/2026-06-13-ci-resource-optimization.md`) carried
the same incorrect "reached script / success" wording and was corrected in the
same PR. Earlier Slice 16-era runs (before `081c6e4`) still have no realistic
observation data and should be read as absent, not passing.

### WASM Hosted CI Still Skips

Unchanged and by design: hosted WASM/embedded WASM remain `skipped
reason=sdk_unavailable` (observational, nonblocking) because no matching Swift
SDK is provisioned on the container. Both build locally on Swift 6.2.1. Promoting
these to real hosted compiles remains optional follow-up work.

### Benchmark Budgets Remain macOS-Derived (Low)

Budgets are unchanged and validated to pass on hosted Linux x86_64 with wide
margin, but they are still macOS-calibrated numbers. A future slice may retune to
Linux-native baselines; not required while margins are this wide.

## Lessons For The Next Slice

1. The project's hosted verification workflow is healthy again: green PR and
   post-merge runs, host/benchmark/memory work on a 1x Linux container, iOS
   blocking on macOS, WASM observational. CI cost per run is down ~10x on the
   dominant job.
2. The remaining CI-governance gap is policy, not pipeline: CI is green but does
   not gate merges, and `AGENTS.md` describes a repo state (private, no ruleset)
   that no longer exists.
3. Three consecutive slices (14 variable-height foundation, 15 CI gate, 16 CI
   optimization) have been infrastructure/safety work. Functional capability
   (variable-height mutation / indexed providers) has been deferred since Slice 14.

## Slice 17 Candidate Options

### Option A: Variable-Height Mutation / Indexed Provider (Recommended)

The strongest functional-value follow-up, deferred since Slice 14: a reference
indexed metrics provider whose single-line height change is a localized
O(log N) update (e.g. a Fenwick/cumulative-height index), with tests proving
cheap re-layout while `TextEngineCore` stays stateless and O(1)-core-memory. CI
is now green and gating-capable infrastructure is in place, so this is the right
time to resume functional work, and the hosted evidence trail is healthy enough to
support it.

### Option B: Repository Policy — Require CI Checks + Correct AGENTS.md

Add a `required_status_checks` rule to the `main` ruleset so the three green Swift
CI jobs actually gate merges, and correct the stale `AGENTS.md` branch-protection
caveat to describe the public repo + active ruleset. Low effort, high governance
value, and it finally closes the "policy cannot require the check" gap that has
recurred since Slice 6. Smaller than a functional slice; could even be folded into
the start of Option A as a short repo-policy pre-step.

### Option C: arm64 Linux Runners

Move the Linux jobs to GitHub's arm64 Linux runners (now available for this repo;
cheaper than x64) for a further CI cost cut. Requires re-baselining benchmark
budgets on arm64 (a different absolute-timing profile), so it carries the retune
work Option A's runner move avoided. Lower priority while x64 margins are wide.
See [[arm64-linux-runner-option]].

### Option D: Complete WASM Hosted CI

Provision a container Swift toolchain with matching WASM SDKs to turn the hosted
`sdk_unavailable` skips into real compiles, making WASM blocking. Independent of
the above; lower priority.

## Recommended Slice 17 Selection

Recommended: **Option A, variable-height mutation / indexed provider.** CI is
healthy and the project has spent three slices on infrastructure; functional value
is the right next investment, and it has been queued since Slice 14. Pair it with
a short **Option B** repo-policy pre-step (require the now-green checks and fix the
stale `AGENTS.md` caveat) if the maintainer wants merges actually gated by CI
before more functional code lands — that pairing is cheap and closes the
governance gap that this slice surfaced.

Choose Option B alone if the priority is locking down merge governance now; choose
Option C only if further CI-cost reduction outranks functional progress and the
arm64 budget re-baseline is acceptable.

The realistic-observation `shell: bash` fix (P2) was already shipped ahead of
Slice 17 in PR #15 (merged as `081c6e4`), so the only governance/cleanup work
still carried into Slice 17 is Option B (require checks + correct the AGENTS.md
caveat).

## Slice 16 Review Conclusion

Slice 16 cleanly delivers its goal: host tests, both benchmark gates, memory
diagnostics, and WASM observation move to a 1x Linux Swift container; iOS stays
blocking on the only hosted macOS job; docs-only changes skip CI; and the
benchmark executable gained a correct Linux RSS path without touching
`TextEngineCore`. It fully implements the approved design and plan, makes no core
change, and is green across fresh local verification, the hosted PR run, and — the
anchor — the hosted post-merge push run on `main`.

It resolves the three items the Slice 15 review left open: the billing-blocked
post-merge evidence gap, the unproven Linux `swift test`, and the two Linux
migration risks (budget transfer and host-specific RSS). It also introduced one
regression caught in this review: **P2 — the PR-only realistic observation step
silently stopped running on the Linux container** (`set -o pipefail` under `sh`,
masked by `continue-on-error`). That P2 was fixed in PR #15 (`shell: bash`,
merged as `081c6e4`, verified `observation=clean`). There is also one P3 (dead
macOS fallback in `main.swift`) and an observation.

The material remaining gaps are policy, not code: the new `main` ruleset does not
yet require the green checks, and the `AGENTS.md` branch-protection caveat is
stale. Count Slice 16 as complete for CI resource optimization with green hosted
PR and post-merge evidence. Do not count it as merge-gating CI policy, variable-
height mutation, hosted WASM closure, or a budget retune; those remain follow-up
work, with variable-height mutation the recommended next slice.
