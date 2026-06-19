# Slice 22 Post-Slice Review

Date: 2026-06-19

## Scope Reviewed

This review covers Slice 22: extending the hosted cross-target compile helper
from one package (`TextEngineCore`) to two packages (`TextEngineCore` and
`TextEngineReferenceProviders`), treating the reference providers as a supported
portable product. iOS device + simulator are blocking for both packages; WASM +
embedded WASM remain observational for both.

The slice was delivered through:

- PR #31 (`slice-22-cross-target-provider-coverage`), merged to `main` as
  `c0e16819cadc625ac71e551f5fae12e188882385`
  (`Merge pull request #31 from maldrakar/slice-22-cross-target-provider-coverage`).

A follow-up evidence PR is still open at review time:

- PR #32 (`slice-22-post-merge-verification`), **OPEN**, head
  `986799692c3ca8eeb5e0c12beace36ffddd80739`. It fills the hosted-evidence
  placeholders left in the merged verification record. See the P3 finding below.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-18-cross-target-provider-coverage-design.md`
- `docs/superpowers/plans/2026-06-18-cross-target-provider-coverage.md`
- `docs/superpowers/verification/2026-06-18-cross-target-provider-coverage.md`
- `docs/superpowers/reviews/2026-06-18-slice-21-post-slice-review.md`
- `.github/scripts/cross-target-compile.sh`
- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- PR #31 / PR #32 metadata, hosted run evidence (including step-level logs), and
  the merged Slice 22 diff

The reviewed Slice 22 range is:

```text
76fdc1c26d93b450993b80e48c0956075a32be67..c0e16819cadc625ac71e551f5fae12e188882385
```

This is a CI/portability slice. It deliberately leaves `Sources/**`,
`Tests/**`, `Package.swift`, benchmark workloads, benchmark budgets, required
status context names, the docs-only detector, and ruleset settings unchanged.
The only `.github/workflows/swift-ci.yml` edits are two inner step renames; the
required job `name:` contexts are byte-for-byte unchanged.

## Product Brief Alignment

The brief requires the engine to compile for iOS and WASM with no source
changes. Before this slice that requirement was enforced in hosted CI for
`TextEngineCore` only. `TextEngineReferenceProviders` — the example consumers
follow when writing their own provider against the public provider API — was
Foundation-free with local WASM proof from Slice 17, but the hosted helper never
compiled it.

Slice 22 closes the product-boundary decision the Slice 21 review flagged as its
Option A: the reference providers are a **supported portable product**, and the
same hosted helper that proves the core's portability now proves theirs.
Compiling the reference provider cross-target is direct evidence that the public
provider API is portable across the full shipping surface, not just the core in
isolation.

The change does not alter the headless engine, the provider API, layout math,
benchmark scenarios, or budgets. It changes enforcement: a provider change that
breaks the iOS build now fails the required `iOS cross-target compile` job.

## Delivered Design

Merged Slice 22 diff (`76fdc1c..c0e1681`):

```text
 .github/scripts/cross-target-compile.sh            | 332 +++++----
 .github/workflows/swift-ci.yml                     |   4 +-
 AGENTS.md                                          |  12 +-
 .../2026-06-18-cross-target-provider-coverage.md   | 750 +++++++++++++++++++++
 ...-06-18-cross-target-provider-coverage-design.md | 228 +++++++
 .../2026-06-18-cross-target-provider-coverage.md   | 220 ++++++
 6 files changed, 1426 insertions(+), 120 deletions(-)
```

### Helper Generalization

The whole behavior change lives in `.github/scripts/cross-target-compile.sh`,
following the approved Approach 1 (parameterize by package; loop over the two
packages in `main()` rather than duplicating verbose per-target blocks):

- New pure helpers, all self-tested: `scheme_for_package` (package → scheme /
  build-target name), `scheme_in_list` (clean stdin filter over the
  `xcodebuild -list` "Schemes:" block), `build_package_summary`, and
  `build_overall_summary`. `emit_target_line` gained a `package=` field;
  `count_blocking_failures` is unchanged and now counts iOS failures across both
  packages.
- iOS scheme resolution is captured once (`resolve_ios_scheme_list`) and reused
  per scheme (`ios_scheme_status`), which keeps an `xcodebuild -list` infra
  failure (`xcodebuild_list_failed`) distinct from a genuinely missing provider
  scheme (`scheme_unresolved`).
- WASM SDK resolution/install happens once per kind (`prepare_wasm_sdk`) and is
  reused across both packages (`compile_wasm_package_for_kind`), so adding the
  provider target does not re-install the SDK.
- `process_package` runs every requested target for one package, appends its
  `result:blocking` pairs to `PAIRS`, emits per-target lines, and prints the
  package summary; `main()` iterates `core` then `providers` and aggregates.

### Output And Exit-Code Contract

Per-target lines now carry `package=`, the summary is one line per package, and a
new overall aggregate line closes the run, exactly as specified:

```text
mode=cross_target_compile target=ios_device package=core result=pass reason=none blocking=true
mode=cross_target_compile target=ios_device package=providers result=pass reason=none blocking=true
mode=cross_target_compile_summary package=core ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

The exit-code invariants are preserved: `--targets wasm` always exits `0` (WASM
is never blocking for either package); `--targets ios` exits `1` on any iOS
compile failure, now including a provider iOS failure. No downstream consumer
parses these lines — the workflow relies only on the exit code — so the line
reshape is safe.

### Workflow And Docs

The two inner cross-target step names were renamed for accuracy
(`Compile cross-target packages for iOS`,
`Observe cross-target packages for WASM`); the required job `name:` contexts
(`iOS cross-target compile`, `WASM cross-target observation`) and the `Main`
ruleset are unchanged. `AGENTS.md` (package-layout note + CI section) and the
helper header comment now describe the two-package surface. Notably, the Slice
22 spec is correctly marked `Approved design direction` from the start — the
Slice 21 P3 lesson about draft-status drift was applied.

## Verification Evidence Reviewed

Fresh local checks during this review (merged `main` at `c0e1681`):

- `git diff --check 76fdc1c..c0e1681` -> no output, exit status `0`.
- `git diff --name-only 76fdc1c..c0e1681 -- Sources Tests Package.swift` -> no
  output (no functional surface touched).
- `rg -n "Foundation" Sources/TextEngineCore` -> no matches, exit status `1`.
- `./.github/scripts/cross-target-compile.sh --self-test` -> `self_test=pass`,
  exit status `0`.
- `bash -n .github/scripts/cross-target-compile.sh` -> `syntax_ok`.
- Required job contexts and renamed steps both present in
  `.github/workflows/swift-ci.yml` (lines 153, 218, 223, 288).

The red phase is recorded honestly: the verification doc captures
`scheme_for_package: command not found` / `self_test=fail` against the
pre-implementation helper at `969cd55`, the expected failing-test-first result.

Hosted evidence checked at the step-log level (not just job conclusion), per the
standing "verify CI step logs, not job conclusion" lesson:

- **PR #31 head run `27785976502`** (head `65526a9`): all three required jobs
  `success`.
- **Post-merge push run `27838480583`** on merge commit `c0e1681`: all three
  required jobs `success`. The `iOS cross-target compile` step log shows
  `package=core` and `package=providers` both `result=pass` on `ios_device` and
  `ios_simulator`, with `mode=cross_target_compile_overall blocking_failures=0
  exit=0`. The `WASM cross-target observation` step log shows both packages on
  both WASM kinds as `result=skipped reason=sdk_unavailable blocking=false` —
  the expected non-blocking SDK skip on the hosted container.

Hosted macOS timing risk (the slice's main risk) resolved as predicted: PR #32's
record reports the PR-head `iOS cross-target compile` at `42s` versus the prior
single-package `0m36s` baseline (~`+6s` for the second iOS scheme across device
and simulator), and the post-merge run at `33s`. The providers build is
incremental on the already-built core, so the delta is modest.

## Git History

Reviewed Slice 22 commits (PR #31):

```text
5aa361b docs: add cross-target provider coverage spec
0c393b5 docs: add cross-target provider coverage plan
969cd55 test: assert two-package cross-target contract
b207dfd feat: add per-package cross-target helpers
fbe6d37 feat: compile reference providers in cross-target helper
866131c ci: rename cross-target steps for two-package surface
a3336cc docs: document portable reference provider cross-target coverage
65526a9 docs: record cross-target provider coverage verification
c0e1681 Merge pull request #31 from maldrakar/slice-22-cross-target-provider-coverage
```

The history is textbook TDD for this repo: a red self-test commit, a green
pure-helpers commit, the orchestration refactor, the workflow rename, durable
docs, and the verification record — one logical step per commit with correct
conventional-commit prefixes.

## Code Review Findings

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None.

### P2 / Production Readiness

None.

### P3 / Minor But Valid

#### P3 - Merged verification record still carries `<pending>` hosted placeholders

The verification doc merged via PR #31
(`docs/superpowers/verification/2026-06-18-cross-target-provider-coverage.md`)
still says, in `main`:

```text
| Current two-package hosted timing | PR-head Swift CI run. | Pending: fill after PR run. |
...
pr_head_run_id=<pending>
post_merge_push_run_id=<pending>
```

The real run IDs, durations, step-log excerpts, and the resolved timing-risk row
live only in **PR #32 (`slice-22-post-merge-verification`), which is still
open**. Until PR #32 merges, the durable Slice 22 verification record in `main`
understates the proof that actually exists.

Impact: this is a paper-trail completeness issue, not a CI/runtime defect. The
hosted behavior is fully proven — this review confirmed both required cross-target
jobs green on the merge commit at the step-log level — but a future agent reading
only `main` would see unfilled placeholders. This is the same PR-split pattern as
Slice 21 (PR #28 behavior + PR #29 evidence); there, the evidence PR was merged
before the post-slice review was written.

Suggested fix: merge PR #32 so the merged-code verification record matches the
hosted evidence, then this review's hosted citations and PR #32 agree.

Reviewing across architecture, simplification, QA, and security concerns
surfaced no other production-relevant findings. The helper is correct and
idiomatic for this
codebase: pure logic is self-tested with no toolchain, the `xcodebuild -list` and
WASM SDK resolutions each run once and are reused per package, and the
infra-failure-vs-missing-scheme distinction is preserved per scheme.

## Risks And Gaps

### Post-Merge Evidence PR Still Open

PR #32 must merge to complete the Slice 22 paper trail (P3 above). It is green on
all three required contexts and contains only the verification-doc evidence fill;
no behavior change.

### WASM Remains Observational For Both Packages

Adding the provider target to the WASM path is real coverage, but the hosted
runner still records `skipped reason=sdk_unavailable` because no version-matched
WASM Swift SDK is provisioned. Real WASM compilation of both packages is proven
locally (recorded in the verification doc) and remains observational in hosted
CI. This is unchanged, documented behavior — and Slice 22 deliberately wired the
provider target into the WASM path so it flips to blocking *together with* the
core when a future provisioning slice lands.

### Helper `process_package` Repetition

`process_package` contains four near-identical target blocks (the design
accepted this for readability over a data-driven loop). It is correct and
self-tested at the pure-helper layer; if a fifth target or a third package ever
appears, a small table-driven refactor would prevent drift. Not a defect today.

### Bypass Actors Remain

The active `Main` ruleset still has the previously documented bypass actor shape;
bypass-capable actors can override required checks. Slice 22 did not touch repo
policy.

### Realistic Provider Relative Observation Still Non-Blocking

The PR-only realistic provider relative observation step still uses
`continue-on-error: true`. Out of scope for Slice 22; unchanged.

## Lessons For The Next Slice

1. The two-package cross-target helper is the template for any future portable
   product: parameterize the compile functions by package and loop in `main()`
   rather than duplicating per-target blocks. The pure/orchestration split keeps
   `--self-test` toolchain-free.
2. The provider target is now wired into both the iOS (blocking) and WASM
   (observational) paths. A future WASM-blocking slice flips both packages at
   once — there is no remaining per-package wiring to do for WASM.
3. Continue separating PR-head heavy-path evidence from post-merge push evidence.
   But land the post-merge evidence PR before writing the post-slice review, so
   the merged verification record never sits with `<pending>` placeholders (see
   P3). Slice 21 did this correctly; Slice 22's evidence PR is still open.
4. With reference-provider portability now enforced, the remaining gaps split
   cleanly into (a) CI-infra portability hardening (WASM blocking), (b) CI
   observation promotion (realistic provider), (c) repo policy (bypass actors),
   and (d) functional core — which has not advanced since Slice 17.

## Slice 23 Candidate Options

### Option A: Promote WASM Cross-Target To Blocking

Reliably provision a pinned, version-matched WASM Swift SDK in the hosted job
(install via `CROSS_TARGET_WASM_SDK_URL` or a container image that bundles it),
prove it is stably green, then flip WASM from observational to blocking for both
`TextEngineCore` and `TextEngineReferenceProviders`. Slice 22 already wired the
provider into the WASM path, so this is the natural close-out of the portability
loop. Risk: a flaky SDK download would turn an infra hiccup into a blocking
failure, so the slice must prove stable provisioning before flipping.

### Option B: Dynamic Line Insert/Delete Provider Design

Design line-count mutation (insert/delete) for the reference providers. The
current Fenwick array shape supports height mutation cheaply but not mid-document
insert/delete. This is the largest **functional** increment and the first to
advance the engine itself since Slice 17. Larger scope; needs its own spec, plan,
and equivalence/virtualization verification.

### Option C: Realistic Provider Observation Promotion Or Recalibration

Review whether the PR-only realistic provider relative observation has enough
hosted Linux evidence to drop `continue-on-error` or tighten its budget. Keep it
separate from the mutation gates because it uses a relative baseline.

### Option D: Ruleset Bypass Policy Review

Decide whether the current bypass actor shape is acceptable long-term. A
repository-policy slice, kept separate from benchmark/provider/portability work.

## Recommended Slice 23 Selection

First, **merge PR #32** to complete the Slice 22 verification record (the P3
above). It is a green, evidence-only PR; merging it makes `main`'s paper trail
match the hosted proof this review confirmed.

After that, recommended Slice 23 is **Option B: Dynamic Line Insert/Delete
Provider Design**. The reasoning: Slices 16 and 18–22 have been a sustained,
healthy run of CI / portability / governance hardening, and Slice 22 leaves the
portability story in a clean state (iOS blocking for both packages; WASM
observationally wired for both, ready to flip). The brief's portability
invariants are now well-defended. The one dimension that has *not* moved since
Slice 17 is the functional engine, and line-count mutation is the next real
capability gap — and a genuine design problem, since the Fenwick structure does
not cheaply support mid-document insert/delete. Returning to functional core work
now rebalances the project and produces the highest product value.

**Option A (WASM blocking)** is the strongest alternative and the obvious
portability follow-on; defer it only because it is infra-gated (stable SDK
provisioning) and lower marginal product value than advancing the engine. If the
preference is to keep closing CI/portability loops before adding functionality,
take Option A instead — Slice 22 has already done the wiring it depends on.

## Slice 22 Review Conclusion

Slice 22 delivered the intended portability change. The hosted cross-target
helper now compiles both `TextEngineCore` and `TextEngineReferenceProviders`;
iOS device + simulator are blocking for both packages and WASM observes both;
the required job contexts and the `Main` ruleset are unchanged; and no
functional, test, or package-manifest surface was touched. PR-head and
post-merge push runs prove both packages compile blocking-green on the merge
commit at the step-log level, and the macOS timing delta is the predicted modest
`~+6s`.

The review found no P0, P1, or P2 issues. One P3 paper-trail issue remains: the
merged verification record still carries `<pending>` hosted placeholders because
the evidence PR #32 has not been merged. Merge PR #32 before treating the Slice
22 verification record as complete.
