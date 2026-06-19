# Cross-Target Provider Coverage Design

Date: 2026-06-18

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 22 of SwiftTextEngine, following the Slice 21 post-slice review:

```text
docs/superpowers/reviews/2026-06-18-slice-21-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires the engine to
compile for iOS and WASM with no source changes. That requirement is currently
enforced for `TextEngineCore` only:

- the hosted cross-target helper `./.github/scripts/cross-target-compile.sh`
  compiles `TextEngineCore` for iOS (device + simulator, blocking) and WASM
  (wasm + embedded wasm, observational);
- the required job contexts are `iOS cross-target compile` and
  `WASM cross-target observation`.

`TextEngineReferenceProviders` is a separate library product that is
Foundation-free, depends only on `TextEngineCore`, and already has local WASM
proof from Slice 17. The hosted helper does **not** compile it. The Slice 21
post-slice review flagged this as an open product-boundary decision
(its `Option A`).

This slice closes that decision: `TextEngineReferenceProviders` is treated as a
**supported portable product**, and the hosted cross-target helper is extended
to compile it for the same targets as the core, mirroring the core's
per-target enforcement model.

## Decision

`TextEngineReferenceProviders` is a supported portable product. Its portability
is proven by the same hosted cross-target helper that proves the core's
portability. The reference providers are the example consumers follow when they
write their own provider against the public provider API; proving the reference
provider cross-compiles is direct evidence that the public provider API is
portable across the full shipping surface.

## Enforcement Model

The provider target mirrors the core's existing per-target enforcement:

| Platform target | core | providers | blocking |
| --- | --- | --- | --- |
| iOS device | scheme `TextEngineCore` | scheme `TextEngineReferenceProviders` | yes |
| iOS simulator | scheme `TextEngineCore` | scheme `TextEngineReferenceProviders` | yes |
| WASM | `--target TextEngineCore` | `--target TextEngineReferenceProviders` | no (observational) |
| embedded WASM | `--target TextEngineCore` | `--target TextEngineReferenceProviders` | no (observational) |

- iOS device + simulator provider compiles are **blocking**: a provider change
  that breaks iOS now fails the required `iOS cross-target compile` job.
- WASM + embedded WASM provider compiles are **observational**: they compile
  when a matching Swift SDK is provisioned, otherwise they record a
  non-blocking skip, exactly like the core WASM path.

### Why WASM Stays Observational Here

WASM remains observational for the same reason the core's WASM path is
observational, and that reason is unchanged by this slice:

- the hosted WASM job runs in the `swift:6.2.1-bookworm` container and invokes
  the helper with no `CROSS_TARGET_WASM_SDK_URL` and no SDK install step, so no
  version-matched WASM Swift SDK is present;
- the helper therefore records `skipped reason=sdk_unavailable` (non-blocking)
  on the hosted runner, and real WASM compilation is proven locally where a
  matching SDK is installed.

Making WASM blocking would fail the job on SDK-unavailable — an infrastructure
reason, not a portability regression. Reliably provisioning a pinned,
version-matched WASM SDK in CI and then promoting WASM to blocking is a separate
CI-provisioning concern that applies equally to the core and is explicitly out
of scope here (see Future Work).

Adding the provider target to the WASM observation path is still worthwhile: it
is nearly free (one additional `swift build --target` invocation) and it gives a
real **local** WASM proof of the providers through the standard helper. When the
future WASM-blocking slice lands, the provider target is already wired into the
WASM path and flips to blocking together with the core.

## Helper Changes

The change is confined to `./.github/scripts/cross-target-compile.sh`.

### Compiled Surface

For each platform target the helper compiles both packages, `core`
(`TextEngineCore`) and `providers` (`TextEngineReferenceProviders`):

- iOS uses `xcodebuild build -scheme <scheme>` per package scheme;
- WASM uses `swift build --swift-sdk <id> --target <target>` per package target.

This follows the approved Approach 1: the compile functions are parameterized by
package, and `main()` iterates over the two packages within each platform step,
rather than duplicating the verbose per-target blocks.

### Output Contract

Per-target lines gain a `package=` field:

```text
mode=cross_target_compile target=ios_device package=core result=pass reason=none blocking=true
mode=cross_target_compile target=ios_device package=providers result=pass reason=none blocking=true
```

The summary becomes one line per package plus one overall aggregate line:

```text
mode=cross_target_compile_summary package=core ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

No downstream consumer parses these lines (verified: the workflow invokes the
helper through `--targets ios` / `--targets wasm` and relies only on the exit
code), so the line shape can change freely. The lines remain stable key-value
text for the verification record and human log reading.

### Exit Code Semantics

`blocking_failures` counts iOS failures across **both** packages. The existing
invariants are preserved:

- `--targets wasm` always exits `0` (iOS is not requested, so it is never
  blocking; WASM stays observational for both packages);
- `--targets ios` exits `1` on any iOS compile failure, including a provider
  iOS compile failure.

### iOS Scheme Resolution

`xcodebuild -list` is run once. A pure helper `scheme_in_list` checks whether a
required scheme is present in the captured list. A missing
`TextEngineReferenceProviders` scheme is attributed to the providers package
(`reason=scheme_unresolved`), not to the core; an `xcodebuild -list`
infrastructure failure is still reported distinctly, as today. Both
`TextEngineCore` and `TextEngineReferenceProviders` are SwiftPM library
products, so both appear as schemes.

## Testing Strategy

The helper's pure logic is covered by `--self-test`, which needs no toolchain.
This slice is implemented test-first:

1. **Red:** extend `--self-test` with assertions for the new pure helpers — the
   per-package summary builder, the overall aggregate line builder,
   `scheme_in_list` (found and missing), and `count_blocking_failures` with a
   provider iOS failure. These fail against the current single-package helper
   shapes.
2. **Green:** implement the parameterized compile functions, the per-package and
   overall output, and the generalized scheme resolution until `--self-test`
   passes.

Toolchain-dependent verification, recorded as evidence rather than asserted:

- `./.github/scripts/cross-target-compile.sh --self-test` -> `self_test=pass`.
- `./.github/scripts/cross-target-compile.sh --targets ios` locally on macOS ->
  both `core` and `providers` schemes compile for device and simulator;
  `mode=cross_target_compile_overall ... exit=0`.
- `./.github/scripts/cross-target-compile.sh --targets wasm` locally when a
  matching Swift SDK is installed -> both packages compile (observational);
  otherwise a recorded `skipped reason=sdk_unavailable`.
- `rg -n "Foundation" Sources/TextEngineCore` -> no matches (unchanged; run as a
  standing invariant).

Hosted evidence:

- PR-head Swift CI run: `iOS cross-target compile` compiles both schemes
  blocking-green; `WASM cross-target observation` observes both packages; the
  three required contexts remain present.
- Post-merge push run on the merge commit, anchoring the merged-code proof.

## Documentation Changes

- `AGENTS.md`: update the package-layout note and the CI section to state that
  the iOS job compiles both `TextEngineCore` and `TextEngineReferenceProviders`
  (blocking), and the WASM job observes both packages. The user-facing commands
  (`--targets ios`, `--targets wasm`) do not change.
- The header comment of `cross-target-compile.sh` is updated to describe the
  two-package surface.
- `.github/workflows/swift-ci.yml`: the two cross-target step names that still
  reference the core only — `Compile TextEngineCore for iOS targets` and
  `Observe TextEngineCore for WASM targets` — are updated for accuracy now that
  both packages are compiled (for example, `Compile cross-target packages for
  iOS` and `Observe cross-target packages for WASM`). The job `name:` contexts
  are not changed.
- Past review and verification documents are not edited.

## Out Of Scope

- No changes to `Sources/**`, `Tests/**`, `Package.swift`, benchmark workloads,
  or benchmark budgets.
- No structural change to `.github/workflows/swift-ci.yml`: the helper is
  invoked identically, and the required job `name:` contexts
  (`iOS cross-target compile`, `WASM cross-target observation`) and the `Main`
  ruleset stay byte-for-byte unchanged. The only workflow edit is renaming the
  two cross-target step names for accuracy (see Documentation Changes); step
  names are internal to the job and do not affect required-context matching.
- No change to the docs-only detector or the trusted-base execution model.
  Because this slice edits `.github/scripts/**`, the PR is correctly classified
  as not docs-only and takes the full heavy CI path — which is required for the
  real iOS compile evidence.

## Future Work

- **Promote WASM cross-target to blocking.** A separate CI-provisioning slice:
  reliably provision a pinned, version-matched WASM Swift SDK in the hosted job
  (install step via `CROSS_TARGET_WASM_SDK_URL` or a container image that
  bundles the SDK), prove it is stably green on the hosted runner, and then flip
  WASM from observational to blocking for both `TextEngineCore` and
  `TextEngineReferenceProviders`. This is a different concern from the
  provider-coverage decision and applies equally to the core.

## Risks

- The only hosted macOS job gains a second iOS scheme build per destination. The
  providers build is incremental on top of the already-built core, so the time
  increase is expected to be modest; the actual delta is recorded in the
  verification document.
- Provider compilation under embedded WASM is expected to succeed
  (Foundation-free, local WASM proof from Slice 17), but it remains
  observational on the hosted runner until the future WASM-blocking slice.
