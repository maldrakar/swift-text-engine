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
packages, via a **per-kind** blocking flag so the embedded fallback stays a config
flip. Any provisioning failure is **fail-closed** (a red gate, never a silent skip).
WASM becomes blocking under the **existing** required-context name, with **no `Main`
ruleset change** this slice (per AGENTS.md's "repo-policy work gets its own slice"); the
cosmetic job rename + matching ruleset update is a deferred repo-policy follow-up. SDK
caching is not pre-deferred: the spike measures the download and Decision 7 decides,
from that data, whether it belongs in this slice.

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
   bundle is 6.2.1 — satisfied. A future container bump that outran the pin would run a
   mismatched SDK, but that case is *already* fail-closed by existing code (Decision 2);
   an explicit `version_mismatch` reason is an optional diagnostic, not a new safety.

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

**The ladder must be a config flip, not new code.** For that, blocking-ness has to be
**per-kind**: a single `LAST_BLOCKING` flip arms both kinds at once, which would force
writing per-kind branching *at the moment we least want to* (mid-slice, having just
found embedded flaky). So the change-set (§1) introduces a **per-kind blocking seam**
up front — `wasm` and `wasm-embedded` each carry their own blocking flag — and
engaging the ladder is then flipping the embedded flag to non-blocking, nothing more.

Rejected alternative — plain `wasm` only from the start: weaker, and leaves embedded
in the same never-actually-tested limbo. Since the bundle provides embedded for free,
attempting both (with the ladder) strictly dominates.

### Decision 2 — Provision from a pinned swift.org bundle (drift already fail-closed)

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

**Version drift is already fail-closed; an explicit guard is a diagnostic nicety, not
the safety.** Under Decision 4, a mismatched pin is *already* caught by existing code:
`resolve_wasm_sdk_id` matches installed SDK ids against the **detected**
`SWIFT_VERSION` substring, so a 6.2.2 container with a pinned-6.2.1 bundle installs
`swift-6.2.1_wasm`, then the post-install resolve for "6.2.2" finds nothing →
`sdk_unresolved_after_install` → red. (Checksum verification is a second independent
backstop: a stale checksum against a new bundle fails the install outright.) So an
explicit `version_mismatch` guard is **optional**, worth adding only for a clearer
reason string than `sdk_unresolved_after_install` — *not* because drift would otherwise
slip through. If added, its "pinned version" is parsed from the pinned URL
(`swift-6.2.1-RELEASE`); if the cost isn't trivial, rely on the existing backstop and
skip it. Downgraded from "essential" to "nice-to-have" accordingly (see AC4).

Where the pin lives: the workflow sets the URL + checksum via env (extending the
existing `CROSS_TARGET_WASM_SDK_URL` seam with a new `CROSS_TARGET_WASM_SDK_CHECKSUM`),
keeping the CI pin visible in the workflow; the script consumes them. The *shape* of
the checksum-passing logic (and the optional guard, if built) is covered by
`--self-test`; the pin *values* are verified live by the hosted run (a wrong checksum
fails the install).

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
  checksum mismatch (and, if the optional guard is built, `version_mismatch`) all become
  **`fail:true`** for the WASM pairs, so they drive the exit code.
- Blocking-ness becomes **per-kind** (Decision 1): `compile_wasm_package_for_kind` no
  longer hard-codes `LAST_BLOCKING="false"` — each kind's blocking flag defaults to
  `true`, and both packages' WASM pairs now enter `count_blocking_failures` as blocking.
- This matches the repo's existing "fail closed on infrastructure failure" posture
  (`detect-docs-only-pr.sh` fails closed on missing commits / diff failures).

The tradeoff — a download.swift.org outage can redden a clean tree — is mitigated by
the retry (Decision 3) and, potentially, by SDK caching, which is **not** deferred by
default but **decided on spike data** (Decision 7). Honest red beats silent green.

### Decision 5 — Make WASM blocking under the existing context; defer the rename (governance)

The `Main` ruleset (id `17656807`) requires the context **`WASM cross-target
observation`**, which the job reports today. Making the script able to exit non-zero
makes that *same* context able to fail — so WASM becomes blocking **with no ruleset
change at all**, keeping the context name stable and the merge gate intact.

**Chosen: the minimal path — do not rename or touch the ruleset in this slice.**
AGENTS.md is explicit: "repo-policy work … get their own slice." Renaming the job is a
required-status-check (repo-policy) change, and coupling it here would (a) violate that
separation, (b) take on a real ordering hazard — the rename and the `gh api` ruleset
update must land together, or the old required context goes permanently unreported
(PRs stuck) while the new one is unrequired (gate vacuous), and (c) add `gh api`
governance work to an otherwise pure CI/portability slice. The only cost of deferring
is that the job name `WASM cross-target observation` is momentarily a misnomer for a
now-blocking job — cheap for one slice, and cheaper still given the recorded fact that
the current admin can **bypass** the ruleset anyway, so enforcement on our own merges
is already partly nominal.

The cosmetic rename (`WASM cross-target observation` → `WASM cross-target compile`) plus
the matching ruleset required-context update is scoped as a **separate tiny repo-policy
follow-up**, done together with a verification-doc note (matching the repo's
ruleset-verification habit — see
`docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`). This slice
still de-rots the *script's* own "observational" comments and the AGENTS.md prose about
what the WASM job *does* (it now compiles and blocks); it leaves the *job/context name*
alone.

Rejected alternative — rename + ruleset update in-slice: honest naming immediately, but
it re-couples repo-policy into a portability slice and takes the land-together ordering
hazard. Not worth it for a one-slice naming cosmetic.

### Decision 6 — Guard scaffolding depth (scope)

- **Extend `cross-target-compile.sh --self-test`** (pure logic, no toolchain):
  checksum-argument passing, `count_blocking_failures` now counting WASM `fail:true`
  pairs, and the per-kind blocking seam (embedded flag off → embedded skip is
  non-blocking, `wasm` fail still blocks). Plus, **if** the optional
  `version_mismatch` reason is built (Decision 2), its match→proceed / drift→fail case.
  This is the primary standing guard.
- **Optional light `WorkflowShapeTests` pin** for the WASM *job*: assert its compile
  step is **not** `continue-on-error` and runs `--targets wasm`, analogous to the gate
  pins. Include if low-cost; the script self-test + hosted liveness are the load-bearing
  proofs.
- **Skip** any new benchmark/checksum tests — no benchmark surface changes.

### Decision 7 — SDK caching: decided on spike data, not deferred by default

Caching the artifactbundle is the **direct** mitigation for this slice's own stated
risk #1 (download.swift.org in the merge path) and for the timeout risk — and its cache
key is already deterministic (Swift version + checksum), on a single job with a high
hit-rate. So it is **not** relegated to a "someday if flaky" follow-up. Instead:

- The provisioning spike **measures** the SDK download time and its run-to-run variance
  (it downloads anyway).
- **Decision rule:** if the download is a non-trivial fraction of the 20-min budget, or
  visibly noisy across the spike's repeated runs, **pull `actions/cache` into this
  slice**. If it's small and steady, ship without cache and note the measured numbers so
  the decision is evidenced, not assumed.
- **Honest caveat:** `actions/cache` inside a `container:` job is occasionally finicky
  (cache paths, `HOME`, `tar` availability). Hence "decide on the data," not "enable
  blindly" — but the default posture is *toward* caching, because it attacks the risk we
  flagged, not away from it.

Rejected heavier alternative — a **custom container image** with the 6.2.1 WASM SDK
prebaked: this removes the download from the merge path entirely and is the most robust
option. Rejected for this slice because it is materially heavier — a container registry
dependency, an image build/publish pipeline to own, and the SDK version now bound to an
image rebuild (a toolchain bump means rebuilding and re-pushing the image, versus
editing one pinned URL+checksum). Pinned-bundle + (spike-decided) cache gets most of the
robustness at a fraction of the moving parts. Revisit only if caching proves unworkable
in-container.

## Change set

### 1. `.github/scripts/cross-target-compile.sh`
- `prepare_wasm_sdk`: pass `--checksum "$checksum"` to `swift sdk install` when a
  checksum env is set; wrap the install in a **bounded retry**. Provision the shared
  bundle **once** and resolve both `wasm`/`wasm-embedded` ids from it. *(Optional per
  Decision 2:* an explicit `version_mismatch` reason parsed from the pinned URL, for a
  clearer diagnostic than the already-fail-closed `sdk_unresolved_after_install`.*)*
- `compile_wasm_package_for_kind`: WASM results become **blocking**, via a **per-kind
  blocking flag** (Decision 1) — each kind defaults to blocking, so engaging the
  embedded fallback is flipping one flag, not writing branching. `LAST_BLOCKING` is no
  longer hard-`false`; provisioning skip reasons become **`fail`** (Decision 4).
- Update the header comment ("WASM ... observational; skipped-with-record" ⇒ blocking,
  fail-closed, pinned bundle) and the `main()` exit-code comment ("reflects only the
  blocking iOS results" ⇒ iOS **and** WASM).
- Extend `run_self_test` (Decision 6).

### 2. `.github/workflows/swift-ci.yml`
- **Keep** the job id/name `wasm-cross-target-observation` / `WASM cross-target
  observation` (Decision 5 — the *job name is the required context*, so no ruleset
  churn). The *step* may be renamed for honesty (`Observe …` → `Compile …`) — a step
  name is **not** a required context, so this is free; it stays **not**
  `continue-on-error` (it never was) and keeps the docs-only guard.
- Provide `CROSS_TARGET_WASM_SDK_URL` + `CROSS_TARGET_WASM_SDK_CHECKSUM` (the pinned
  6.2.1 bundle) to the compile step's env.
- **Spike-decided (Decision 7):** if the measured download warrants it, add
  `actions/cache` over the artifactbundle (keyed on Swift version + checksum). Only if
  the spike data says so.
- Consider bumping `timeout-minutes` if the ~100 MB SDK download + two-package ×
  two-kind compile approaches 20 min (watch item; caching also relieves this).

### 3. `AGENTS.md`
- Hard constraint **#4**: WASM/embedded WASM are no longer "proven locally and observed
  in CI only when a matching SDK is available" — they are **blocking** in CI, provisioned
  from a pinned swift.org 6.2.1 bundle. Keep the "compiles for iOS and WASM with no
  source changes" invariant.
- `## Package layout` / `## CI`: describe what the WASM job now **does** — blocking WASM
  compile (both kinds, both packages), provisioned from the pinned bundle, fail-closed —
  and de-rot the `cross-target-compile.sh` prose ("WASM ... observational" ⇒ blocking).
  **Leave the job/context *name* (`WASM cross-target observation`) as-is**; the
  name-vs-reality mismatch is called out and scoped to the follow-up (below), not fixed
  here.
- `## Commands`: note the pinned-SDK provisioning (URL/checksum env) for the WASM path.
- Required-check policy paragraph: the third context name is unchanged this slice; add a
  one-line note that a follow-up renames it to `WASM cross-target compile`.

### 4. Memory
- Add a Slice 46 direction entry to `MEMORY.md` on completion (status, PRs, hosted run
  IDs), per the slice-direction habit.

### 5. Deferred to a follow-up slice (repo-policy) — NOT in this slice
- Rename the job/context `WASM cross-target observation` → `WASM cross-target compile`
  **and** update the `Main` ruleset's required-status-check context to match (via
  `gh api`), landed together to avoid the ordering hazard, with a before/after
  verification-doc note. Its own tiny repo-policy slice (Decision 5).

## Acceptance criteria

- **AC1** — The WASM job provisions the pinned 6.2.1 SDK (checksum-verified) and
  compiles **both** packages for **both** `wasm` and `wasm-embedded`; all four results
  are **blocking**, via a **per-kind** blocking flag (so the ladder is a config flip).
  (Or, if the fallback ladder engages: `wasm` blocking for both packages,
  `wasm-embedded` flag flipped to non-blocking/observational, with the reason recorded.)
- **AC2 (fail-closed on provisioning)** — A provisioning failure fails the job. Proven
  **live** by corrupting the checksum → job red naming the install failure → revert →
  green; tree left byte-clean.
- **AC3 (fail-closed on compile)** — A WASM compile break fails the job. Proven **live**
  by a break → red naming the WASM compile → revert → green; tree left byte-clean.
- **AC4 (version drift stays fail-closed)** — With the pinned SDK version ≠ detected
  `SWIFT_VERSION`, the job fails closed (the existing resolve-by-detected-version path
  yields `sdk_unresolved_after_install`, or — *if built* — the optional `version_mismatch`
  reason). Covered by `--self-test`. The explicit guard is a diagnostic nicety, not the
  safety (Decision 2), so its presence is optional; the fail-closed *behavior* is required.
- **AC5** — `cross-target-compile.sh --self-test` green with the extended coverage
  (per-kind blocking seam, checksum passing, blocking-count); `swift test` green;
  `swift build -c release` clean; `rg -n Foundation Sources/TextEngineCore` empty.
- **AC6 (governance — minimal path)** — The job stays named `WASM cross-target
  observation`; the `Main` ruleset is **untouched** this slice (Decision 5), so the three
  required contexts, strict policy, and bypass shape are all unchanged; the rename +
  ruleset update is recorded as a deferred repo-policy follow-up.
- **AC7 (reliability — the real bar)** — Hosted proof read at **step level** (dead-step
  rule): the WASM job green with all four WASM compiles passing across **multiple** runs
  (PR-head + post-merge push, plus at least one re-run to demonstrate the download isn't
  a one-off), evidenced by the resolved SDK id and per-target `result=pass blocking=true`
  lines with overall `exit=0`; the other two required jobs green. Anchored in the
  post-merge push run.
- **AC8** — `AGENTS.md` #4 + CI/layout/commands updated to describe the now-blocking,
  pinned-bundle WASM job (job/context *name* left unchanged, with a note pointing at the
  rename follow-up); no engine/provider source changed (unless embedded surfaced a real
  incompatibility, handled as its own recorded fix).
- **AC9 (caching decision evidenced)** — The spike's measured SDK download time/variance
  is recorded, and the in-slice caching decision (added vs. not) follows Decision 7's
  rule from that data — not left as an unexamined default.

## Non-goals / out of scope

- **Job/context rename + `Main` ruleset update.** Deferred to its own tiny repo-policy
  follow-up slice (Decision 5), landed together to avoid the ordering hazard, with a
  before/after verification-doc note. This slice makes WASM blocking under the *existing*
  context name.
- **SDK caching is NOT a blanket non-goal** — it is in-scope-if-warranted, decided on the
  spike's measured download data (Decision 7 / AC9). Only a *custom prebaked container
  image* is out of scope (rejected alternative in Decision 7).
- **iOS job, the benchmark gates, memory diagnostics** — untouched.
- **Core/provider source changes** — none expected. If `wasm-embedded` surfaces a real
  Embedded-Swift incompatibility, fixing it is a separate, recorded change (a valuable
  finding), and the fallback ladder covers shipping meanwhile.
- **Harvester / budgets / derive scripts** — unrelated to portability; untouched.

## Verification plan

0. **Spike first:** pin the URL, download the bundle, recompute + cross-check the sha256,
   install with `--checksum`, compile both packages × both kinds locally, **and measure
   the download time/variance** (feeds Decision 7 / AC9). This locks the checksum and
   confirms feasibility before any blocking flip.
1. `./.github/scripts/cross-target-compile.sh --self-test` — `self_test=pass` with the
   extended coverage (per-kind blocking seam, checksum passing, blocking-count; optional
   `version_mismatch`).
2. Local provision + compile (with a matching local SDK, or the pinned URL+checksum):
   both packages × both kinds compile; per-target lines show `result=pass blocking=true`;
   overall `exit=0`.
3. `swift test` green; `swift build -c release` clean; `rg -n Foundation
   Sources/TextEngineCore` empty (exit 1).
4. **Liveness — compile (AC3):** break a WASM compile → job red → revert → green;
   byte-clean tree.
5. **Liveness — provisioning (AC2):** corrupt the pinned checksum → install/job red →
   revert → green; byte-clean tree.
6. **Governance (AC6):** confirm via `gh api` that the `Main` ruleset is **unchanged**
   (still three contexts including `WASM cross-target observation`, strict policy, bypass
   shape) — this slice does not touch it. Record the rename+ruleset follow-up as a
   separate item.
7. **Hosted reliability (AC7):** PR-head run + ≥1 re-run + post-merge push run, read at
   **step level**; record run IDs, job conclusions, the four WASM per-target lines, and
   the resolved SDK id. Anchor in the push run. If embedded proves flaky, engage the
   fallback ladder and document.
8. **Caching decision (AC9):** record the measured download numbers from step 0 and the
   resulting in-slice caching decision (added vs. not) per Decision 7's rule.

## Risks & trade-offs

- **download.swift.org in the merge path** (Decision 4) — a network outage can redden a
  clean tree. Mitigated by the bounded retry and, per Decision 7, by spike-decided SDK
  caching. Accepted: honest red > silent green.
- **Embedded Swift is experimental** — `wasm-embedded` may be less stable than plain
  `wasm` across toolchain bumps. Covered by the per-kind fallback ladder (Decision 1); a
  genuine incompatibility is a valuable finding, not a slice failure.
- **Governance deferral** (Decision 5) — this slice leaves a job named "…observation"
  that actually blocks. Accepted as a one-slice cosmetic misnomer (called out in AGENTS.md
  prose) rather than coupling the rename + ruleset `gh api` update — with its land-together
  ordering hazard — into a portability slice. The rename is its own follow-up.
- **Timeout** — SDK download + four compiles vs `timeout-minutes: 20`; watch, bump if
  needed (caching also relieves this).
- **Version drift** — a future container bump silently using a mismatched SDK is already
  foreclosed by the existing resolve-by-detected-version path (→ `sdk_unresolved_after_install`,
  now red under fail-closed) plus checksum verification; the optional `version_mismatch`
  guard only improves the reason string (Decision 2).

## Next step

On approval, invoke the writing-plans skill to produce a task-by-task TDD plan
(`docs/superpowers/plans/2026-07-19-wasm-cross-target-blocking-gate.md`), sequenced so
the **provisioning spike** (pin + install + compile, locally and in a throwaway hosted
run, *plus the download-time measurement*) comes first — to lock the checksum, confirm
both kinds compile, and feed the caching decision — before the blocking flip.
