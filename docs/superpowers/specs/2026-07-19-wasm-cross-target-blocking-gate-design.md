# Slice 46 — WASM cross-target compile as a blocking CI gate

## Summary

Turn the **WASM cross-target compile** from *observational* into a **merge-blocking**
CI gate, symmetric to the already-blocking iOS job. Today `swift:6.2.1-bookworm`
ships no WASM SDK and CI provisions none, so the WASM job **never actually compiles
anything** — it records `skip=sdk_unavailable` for all four WASM results
(`{wasm, wasm-embedded} × {core, providers}`) and, because
`compile_wasm_package_for_kind` hard-codes `LAST_BLOCKING="false"`, structurally
cannot fail the job. The "proven locally, observed in CI" WASM compile has, in fact,
**never run in hosted CI**.

This slice makes it run and makes it count: pin swift.org's exact-version 6.2.1 WASM
SDK bundle (URL + sha256), provision it checksum-verified with a bounded retry, and
make **both** `wasm` (WASI) and `wasm-embedded` compile results **blocking** for both
packages. Any provisioning failure is **fail-closed** (a red gate, never a silent
skip). The job is renamed to reflect its new blocking status, and the `Main` ruleset's
required-status-check context is updated to match in the same slice.

It is a **portability slice** — the kind AGENTS.md calls out as its own category —
with **no product decision** and, absent an embedded-Swift incompatibility surfacing,
**no engine/provider source change**. The real work and the real risk is
**provisioning reliability in hosted CI**; the deliverable includes a multi-run
reliability demonstration, and a negative finding is itself a valid, documented
outcome.

## Motivation — brief alignment

The product brief's success criteria include, verbatim:

- **#6:** «Компилируется без изменений под iOS и **WASM**.»
- and the constraint list: «Ядро должно быть пригодно для компиляции под iOS и WASM
  без изменений в source code.»

iOS device + simulator are already **blocking** in CI (`ios-cross-target-compile`,
via `cross-target-compile.sh --targets ios`). Its WASM twin is the **only** success
criterion still merely *observed* — and, as shown below, not even observed: skipped.
Making WASM blocking is the highest-relevance move to the brief available right now:
it converts criterion #6 from "assert/observe" into "verify," closing the last
observational gap in the six success criteria and restoring symmetry with iOS.

Contrast with the Slice 45 review's leading candidates — harvester provenance
hardening (Option A) and a bulk-edit absolute budget (Option B). Both are worthy, but
**neither appears in the brief**: provenance-hardening is a self-imposed calibration
invariant, and the bulk-edit budget needs a product-target decision first. WASM
enforcement is in the brief, in black and white (#6), and needs no product call. That
makes it the stronger Slice 46 by brief relevance.

## Relation to the Slice 45 recommendation

The Slice 45 post-slice review recommended **Option A — harvester provenance
hardening** (decision-free, the slice's own named follow-on) with **Option B —
bulk-edit absolute budget** as the product alternative. This slice is a **deliberate
pivot to neither**, chosen for brief relevance: it is the single most brief-aligned
work item still open (criterion #6, the last observational criterion), a pure
portability slice, and — like Option A — decision-free. Provenance hardening and the
bulk-edit budget remain open and are the natural successors; this slice does not
supersede them.

## Background — current state

### The WASM job compiles nothing today

`.github/workflows/swift-ci.yml` job `wasm-cross-target-observation`
(`ubuntu-latest`, `container: swift:6.2.1-bookworm`) runs
`./.github/scripts/cross-target-compile.sh --targets wasm`. Tracing the script:

- **No SDK is present.** The base image carries no WASM SDK, so
  `resolve_wasm_sdk_id` finds nothing in `swift sdk list`.
- **No SDK is provisioned.** `prepare_wasm_sdk` then looks for an install URL in
  `CROSS_TARGET_WASM_SDK_URL` / `CROSS_TARGET_WASM_EMBEDDED_SDK_URL`. The workflow
  **sets neither**, so `skip="sdk_unavailable"` for both kinds.
- **The compile is skipped.** `compile_wasm_package_for_kind` sees the skip reason and
  returns `result=skipped reason=sdk_unavailable` — no `swift build` runs.
- **It cannot fail.** That function hard-codes `LAST_BLOCKING="false"`
  (`cross-target-compile.sh:405`), and `count_blocking_failures` tallies only
  `fail:true` pairs, so all four WASM pairs are `skipped:false` and the job's exit code
  is driven **entirely by iOS** — which `--targets wasm` doesn't run. Net: exit 0,
  always green, always skipped.
- **The install path is incomplete anyway.** Even were a URL supplied,
  `prepare_wasm_sdk` calls `swift sdk install "$url"` **without `--checksum`**
  (`cross-target-compile.sh:382`); remote-URL installs require a checksum, so that
  path would fail today.

So the required check context `WASM cross-target observation` is a **green no-op**: it
exists to satisfy the ruleset but verifies nothing.

### A 6.2.1-exact WASM SDK exists and is pinnable (feasibility confirmed)

swift.org publishes **per-patch** WASM SDK bundles at a deterministic URL. Probed this
slice:

```
swift 6.2.1 wasm-sdk -> HTTP 200
  https://download.swift.org/swift-6.2.1-release/wasm-sdk/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE_wasm.artifactbundle.tar.gz
swift 6.3.3 wasm-sdk -> HTTP 200   (control — the current release)
```

Two facts from swift.org's WASM getting-started guide + the Swift forums announcement:

1. **One bundle installs both SDKs.** Installing the bundle produces
   `swift-6.2.1_wasm` *and* `swift-6.2.1_wasm-embedded` — the experimental Embedded
   Swift variant. So a single checksum-verified `swift sdk install` provisions both
   kinds; no separate embedded-SDK hunt.
2. **Exact version match is mandatory.** "From version 6.1 onward, the Swift toolchain
   and WASM SDK versions must correspond exactly." The container is 6.2.1 and the
   bundle is 6.2.1 — satisfied — but this makes a **version-match guard** essential so
   a future container bump can't silently run a mismatched SDK.

The script already models two kinds (`wasm`, `wasm_embedded`), a `prepare`/`compile`
split, per-target result lines, and a `--self-test` seam — the right structure to
extend rather than replace.

## Design decisions

### Decision 1 — Both kinds blocking, both packages (scope)

Make `wasm` **and** `wasm-embedded` blocking, for both `core` and `providers` — four
load-bearing WASM compiles. Rationale: one bundle already provides both; both are
proven locally; and it mirrors iOS's two blocking targets (device + simulator).

**Fallback ladder (embedded flakiness).** Embedded Swift is experimental. If the
hosted spike shows `wasm-embedded` is unreliable (flaky provisioning or a genuine
compile incompatibility that isn't quickly fixable), ship **plain `wasm` blocking +
`wasm-embedded` observational** and record precisely why. A negative finding on
embedded is a valid, documented slice outcome, not a failure of the slice.

Rejected alternative — plain `wasm` only from the start: weaker, and leaves embedded
in the same never-actually-tested limbo. Since the bundle provides embedded for free,
attempting both (with the ladder) strictly dominates.

### Decision 2 — Provision from a pinned swift.org bundle, version-guarded

Pin the exact 6.2.1 bundle as an explicit, greppable pair:

- **URL:**
  `https://download.swift.org/swift-6.2.1-release/wasm-sdk/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE_wasm.artifactbundle.tar.gz`
- **Checksum:** the swift.org-published sha256, **independently recomputed** from the
  downloaded bundle during the plan's spike and committed only if the two match
  (published value = trust anchor; local recompute = integrity check). **Never
  invented**, in keeping with the repo's "pin, don't hand-wave" culture.

Both kinds share **one** bundle URL + checksum (the unified bundle). A single
provisioning installs it; the second per-kind resolve finds the already-installed
`wasm-embedded` id and does no second install.

**Version-match guard (fail-closed).** The pinned SDK version must equal the detected
`SWIFT_VERSION` (`swift --version`). If they drift — e.g. the container is bumped to
6.2.2 but the pin isn't — the job **fails closed** with a clear reason, rather than
silently skipping or silently using a mismatched SDK. (The checksum verification is a
second, independent backstop: a stale checksum against a new bundle also fails the
install.)

Where the pin lives: the workflow sets the URL + checksum via env (extending the
existing `CROSS_TARGET_WASM_SDK_URL` seam with a new `CROSS_TARGET_WASM_SDK_CHECKSUM`),
keeping the CI pin visible in the workflow; the script consumes them. The *shape* of
the checksum-passing and version-guard logic is covered by `--self-test`; the pin
*values* are verified live by the hosted run (a wrong checksum fails the install).

### Decision 3 — Add `--checksum` + a bounded retry to the install

Teach `prepare_wasm_sdk` to pass `--checksum` to `swift sdk install` when a checksum is
supplied, and wrap the install in a **bounded retry** (a few attempts with a short
backoff). download.swift.org is now in the merge path; a bounded retry tames transient
network flakiness without masking a persistent failure (which still ends red after the
retries are exhausted).

### Decision 4 — Fail-closed provisioning: a skip is not a pass

Once WASM is a gate, "couldn't provision the SDK" must be a **blocking failure**, not a
non-blocking skip. Otherwise the gate **silently disarms exactly when provisioning
breaks** — the Slice-16 dead-step trap, and the antithesis of "a gate that cannot fail
is not a gate." Concretely:

- `sdk_unavailable` (no URL/no SDK), `sdk_install_failed`, `sdk_unresolved_after_install`,
  checksum mismatch, and version-guard drift all become **`fail:true`** for the WASM
  pairs, so they drive the exit code.
- `compile_wasm_package_for_kind` stops hard-coding `LAST_BLOCKING="false"`; WASM pairs
  now enter `count_blocking_failures` as blocking.
- This matches the repo's existing "fail closed on infrastructure failure" posture
  (`detect-docs-only-pr.sh` fails closed on missing commits / diff failures).

The tradeoff — a download.swift.org outage can redden a clean tree — is mitigated by
the retry (Decision 3) and, if the hosted spike shows it's needed, SDK caching as a
**follow-up** (see Non-goals). Honest red beats silent green.

### Decision 5 — Rename the job + update the `Main` ruleset in-slice (governance)

The `Main` ruleset (id `17656807`) requires the context **`WASM cross-target
observation`**, which the job reports today. Making the script able to exit non-zero
makes that *same* context able to fail — so WASM can become blocking **without** a
ruleset change. But "observation" would then be a lie.

Recommended: **rename** the job (e.g. `WASM cross-target compile`) **and** update the
ruleset's required-status-check context to the new name via `gh api`, in the same
slice, with a verification-doc note (matching the repo's ruleset-verification habit —
see `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`). Both edits
must land together: renaming the job without updating the ruleset would leave the old
required context permanently unreported (PRs stuck) and the new context unrequired
(gate vacuous). The script's own summary/target lines and AGENTS.md prose are updated
to drop "observation."

### Decision 6 — Guard scaffolding depth (scope)

- **Extend `cross-target-compile.sh --self-test`** (pure logic, no toolchain): the
  version-match guard (match → proceed, drift → fail-closed), checksum-argument
  passing, and `count_blocking_failures` now counting WASM `fail:true` pairs. This is
  the primary standing guard.
- **Optional light `WorkflowShapeTests` pin** for the WASM *job*: assert its compile
  step is **not** `continue-on-error` and runs `--targets wasm`, analogous to the gate
  pins. Include if low-cost; the script self-test + hosted liveness are the load-bearing
  proofs.
- **Skip** any new benchmark/checksum tests — no benchmark surface changes.

## Change set

### 1. `.github/scripts/cross-target-compile.sh`
- `prepare_wasm_sdk`: pass `--checksum "$checksum"` to `swift sdk install` when a
  checksum env is set; add a **version-match guard** (pinned SDK version vs detected
  `SWIFT_VERSION`) that fails closed on drift; wrap the install in a **bounded retry**.
  Provision the shared bundle **once** and resolve both `wasm`/`wasm-embedded` ids from
  it.
- `compile_wasm_package_for_kind`: WASM results become **blocking** (`LAST_BLOCKING`
  no longer hard-`false`); provisioning skip reasons become **`fail`** (Decision 4).
- Update the header comment ("WASM ... observational; skipped-with-record" ⇒ blocking,
  fail-closed) and the `main()` exit-code comment ("reflects only the blocking iOS
  results" ⇒ iOS **and** WASM).
- Extend `run_self_test` (Decision 6).

### 2. `.github/workflows/swift-ci.yml`
- Rename job `wasm-cross-target-observation` → `wasm-cross-target-compile` (name
  `WASM cross-target compile`).
- Provide `CROSS_TARGET_WASM_SDK_URL` + `CROSS_TARGET_WASM_SDK_CHECKSUM` (the pinned
  6.2.1 bundle) to the compile step's env.
- Rename the step `Observe cross-target packages for WASM` →
  `Compile cross-target packages for WASM`; it stays **not** `continue-on-error`
  (it never was) and keeps the docs-only guard.
- Consider bumping `timeout-minutes` if the ~100 MB SDK download + two-package ×
  two-kind compile approaches 20 min (watch item).

### 3. `Main` ruleset (via `gh api`)
- Update the required-status-check contexts: `WASM cross-target observation` →
  `WASM cross-target compile`, preserving the three-context requirement, strict policy,
  and the existing bypass-actor shape. Record before/after in the verification doc.

### 4. `AGENTS.md`
- Hard constraint **#4**: WASM/embedded WASM are no longer "proven locally and observed
  in CI only when a matching SDK is available" — they are **blocking** in CI, provisioned
  from a pinned swift.org 6.2.1 bundle. Keep the "compiles for iOS and WASM with no
  source changes" invariant.
- `## Package layout` / `## CI`: the third job is now blocking WASM compile (both kinds,
  both packages), not observation; update the WASM-job description and the
  `cross-target-compile.sh` prose ("WASM ... observational" ⇒ blocking, fail-closed,
  pinned bundle).
- `## Commands`: note the pinned-SDK provisioning (URL/checksum env) for the WASM path.
- Required-check policy paragraph: the third context is now `WASM cross-target compile`.

### 5. Memory
- Add a Slice 46 direction entry to `MEMORY.md` on completion (status, PRs, hosted run
  IDs), per the slice-direction habit.

## Acceptance criteria

- **AC1** — The WASM job provisions the pinned 6.2.1 SDK (checksum-verified) and
  compiles **both** packages for **both** `wasm` and `wasm-embedded`; all four results
  are **blocking**. (Or, if the fallback ladder engages: `wasm` blocking for both
  packages, `wasm-embedded` observational, with the reason recorded.)
- **AC2 (fail-closed on provisioning)** — A provisioning failure fails the job. Proven
  **live** by corrupting the checksum → job red naming the install failure → revert →
  green; tree left byte-clean.
- **AC3 (fail-closed on compile)** — A WASM compile break fails the job. Proven **live**
  by a break → red naming the WASM compile → revert → green; tree left byte-clean.
- **AC4 (version guard)** — With the pinned SDK version ≠ detected `SWIFT_VERSION`, the
  job fails closed with a clear reason (covered by `--self-test` and, if practical,
  demonstrated).
- **AC5** — `cross-target-compile.sh --self-test` green with the extended coverage;
  `swift test` green; `swift build -c release` clean; `rg -n Foundation
  Sources/TextEngineCore` empty.
- **AC6 (governance)** — The job is renamed and the `Main` ruleset required context is
  updated to match (`gh api` before/after recorded); the ruleset still requires exactly
  the three job contexts with strict policy and unchanged bypass shape.
- **AC7 (reliability — the real bar)** — Hosted proof read at **step level** (dead-step
  rule): the WASM job green with all four WASM compiles passing across **multiple** runs
  (PR-head + post-merge push, plus at least one re-run to demonstrate the download isn't
  a one-off), evidenced by the resolved SDK id and per-target `result=pass blocking=true`
  lines with overall `exit=0`; the other two required jobs green. Anchored in the
  post-merge push run.
- **AC8** — `AGENTS.md` #4 + CI/layout/commands + the required-check paragraph updated;
  no engine/provider source changed (unless embedded surfaced a real incompatibility,
  handled as its own recorded fix).

## Non-goals / out of scope

- **SDK caching.** `actions/cache` over the artifactbundle (keyed on version + checksum)
  would cut download time and network exposure, but adds a dependency and moving parts.
  Deferred: add only if the hosted spike shows the pinned-URL download is flaky. If
  needed, the natural home is a dedicated provisioning step in the workflow (the
  "provisioning as its own step" approach set aside here).
- **iOS job, the benchmark gates, memory diagnostics** — untouched.
- **Core/provider source changes** — none expected. If `wasm-embedded` surfaces a real
  Embedded-Swift incompatibility, fixing it is a separate, recorded change (a valuable
  finding), and the fallback ladder covers shipping meanwhile.
- **Harvester / budgets / derive scripts** — unrelated to portability; untouched.

## Verification plan

1. `./.github/scripts/cross-target-compile.sh --self-test` — `self_test=pass` with the
   new version-guard / checksum / blocking-count coverage.
2. Local provision + compile (with a matching local SDK, or the pinned URL+checksum):
   both packages × both kinds compile; per-target lines show `result=pass blocking=true`;
   overall `exit=0`.
3. `swift test` green; `swift build -c release` clean; `rg -n Foundation
   Sources/TextEngineCore` empty (exit 1).
4. **Liveness — compile (AC3):** break a WASM compile → job red → revert → green;
   byte-clean tree.
5. **Liveness — provisioning (AC2):** corrupt the pinned checksum → install/job red →
   revert → green; byte-clean tree.
6. **Governance (AC6):** `gh api` the `Main` ruleset before/after the required-context
   rename; confirm three contexts, strict policy, bypass shape unchanged. Record in the
   verification doc.
7. **Hosted reliability (AC7):** PR-head run + ≥1 re-run + post-merge push run, read at
   **step level**; record run IDs, job conclusions, the four WASM per-target lines, and
   the resolved SDK id. Anchor in the push run. If embedded proves flaky, engage the
   fallback ladder and document.

## Risks & trade-offs

- **download.swift.org in the merge path** (Decision 4) — a network outage can redden a
  clean tree. Mitigated by the bounded retry; SDK caching is the documented escape hatch
  if the spike shows flakiness. Accepted: honest red > silent green.
- **Embedded Swift is experimental** — `wasm-embedded` may be less stable than plain
  `wasm` across toolchain bumps. Covered by the fallback ladder (Decision 1); a genuine
  incompatibility is a valuable finding, not a slice failure.
- **Governance coupling** (Decision 5) — the job rename and the ruleset update must land
  together or the merge gate breaks. Handled explicitly as a single coordinated step
  with before/after evidence.
- **Timeout** — SDK download + four compiles vs `timeout-minutes: 20`; watch, bump if
  needed.
- **Version drift** — a future container bump silently using a mismatched SDK is
  foreclosed by the version-match guard + checksum verification (both fail closed).

## Next step

On approval, invoke the writing-plans skill to produce a task-by-task TDD plan
(`docs/superpowers/plans/2026-07-19-wasm-cross-target-blocking-gate.md`), sequenced so
the **provisioning spike** (pin + install + compile, locally and in a throwaway hosted
run) comes first to lock the checksum and confirm both kinds compile before the blocking
flip and the ruleset rename.
