# Slice 26 Post-Slice Review

Date: 2026-06-21

## Scope Reviewed

This review covers Slice 26: the **bulk-structural-mutation CI gate promotion**,
with a folded-in benchmark hardening. It adds the already-existing
`--bulk-structural-mutation --gate` benchmark path as a new **blocking** step in
the required `Host tests and benchmark gate` hosted job — the **fifth** contiguous
blocking latency gate — so a performance regression in the
`BalancedTreeLineMetrics` bulk insert/delete-range path now fails the job. It
also lands the Slice 25 review's P3 #2 hardening: the deterministic index-mixing
idiom is extracted into one `deterministicIndex(sample:multiplier:modulus:)`
helper in `BenchmarkSupport.swift` and applied to **both** the bulk benchmark and
the already-blocking structural-mutation benchmark, closing a latent
negative-index crash class in a gate that was *already* required.

This is primarily a CI/governance slice with a small, behavior-preserving
benchmark-source change. It changes no `TextEngineCore` source, no
`TextEngineReferenceProviders` provider/algorithm, no tests, no package metadata,
and no benchmark scenario, budget, iteration count, or summary field. It closes
the single regression-protection gap the Slice 25 review identified and was Slice
25's recommended Option A.

The slice was delivered through **two** PRs, both now merged:

- PR #44 (`slice-26-bulk-structural-mutation-ci-gate-promotion`), title *"Slice 26:
  Bulk-structural-mutation CI gate promotion"*, final head `6595ad1`, merged to
  `main` as `b5e4fbbae9324f594ce01a009a396bf016fd24fa` (`b5e4fbb`) at
  `2026-06-21T13:46:29Z` — the workflow step, the `deterministicIndex` helper and
  its two call sites, the `AGENTS.md` update, the spec, the plan, and the
  verification record's local sections.
- PR #45 (`slice-26-post-merge-verification`), title *"Slice 26: record
  bulk-structural-mutation gate post-merge proof"*, merged as
  `06f2b7aa3072c1459c3eea8b8c63244f0b0ae29d` (`06f2b7a`, current `main` HEAD) at
  `2026-06-21T13:55:25Z` — the docs-only follow-up that filled the hosted
  evidence (PR-head run + post-merge push run).

**Both PRs are merged at review time**, so `main`'s verification record carries
real hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-21-bulk-structural-mutation-ci-gate-promotion-design.md`
- `docs/superpowers/plans/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md`
- `docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md`
- `docs/superpowers/reviews/2026-06-21-slice-25-post-slice-review.md`
- `.github/workflows/swift-ci.yml` (host job)
- `Sources/ViewportBenchmarks/BenchmarkSupport.swift` (the new helper)
- `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift` (call sites)
- `Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift` (call sites)
- `AGENTS.md` (CI section)
- PR #44 / #45 metadata, hosted run evidence (step-level logs), merge parentage,
  and the merged Slice 26 diff

The reviewed Slice 26 range (PR #43 merge base → current `main` HEAD) is:

```text
b74fcf9..06f2b7a
```

This is confined to `.github/workflows/swift-ci.yml`, `AGENTS.md`, three files
under `Sources/ViewportBenchmarks/`, and `docs/**`. It does **not** touch
`Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders`, `Tests/**`, or
`Package.swift` — confirmed below by a fresh name-only diff.

## Product Brief Alignment

The brief requires regression benchmarks to block merge on performance
degradation (*"Регрессионные бенчмарки блокируют merge при деградации
производительности"*). Before this slice that principle held for four of the five
latency paths — synthetic pipeline, static variable-height, variable-height
mutation, and structural-mutation gates all ran blocking in hosted CI. The
**bulk** insert/delete-range path, added in Slice 25, was proven **locally only**:
the host job stayed green regardless of bulk-structural-mutation performance
because the benchmark was never invoked in the workflow.

Slice 26 closes exactly that gap. The brief's "benchmark gates block merge"
principle now holds for **all five** latency paths, including the **heaviest
workload in the entire suite** (the 1M × K=4096 bulk paste/range-delete scenario,
~0.19 ms/op locally). This also completes the project's established "functional
slice adds a local gate → promotion slice wires CI" rhythm for the **fourth**
time (variable-height → its promotion, variable-height-mutation → its promotion,
structural-mutation → Slice 24, bulk-structural-mutation → this slice).

The hardening sub-change is fully in keeping with the brief's hard constraints:
it touches only the benchmark executable target (never the Foundation-free core
or the provider), introduces no dependency, and is behavior-preserving. The core
remains untouched and the architecture invariants are intact.

## Delivered Design

Merged Slice 26 diff (`b74fcf9..06f2b7a`):

```text
 .github/workflows/swift-ci.yml                     |   4 +
 AGENTS.md                                          |   7 +-
 Sources/ViewportBenchmarks/BenchmarkSupport.swift  |   8 +
 .../BulkStructuralMutationBenchmark.swift          |   5 +-
 .../StructuralMutationBenchmark.swift              |   4 +-
 .../2026-06-21-…-ci-gate-promotion.md (verification)|  464 +++
 .../2026-06-21-…-ci-gate-promotion-design.md (spec) |  570 +++
 .../2026-06-21-…-ci-gate-promotion.md (plan)        |  321 +++
 8 files changed, 1376 insertions(+), 7 deletions(-)
```

### The workflow step (the core of the slice)

A single new step in the `host-tests-and-benchmark-gate` job, inserted between
the structural-mutation gate and the memory-shape diagnostic:

```yaml
      - name: Run bulk structural mutation benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --bulk-structural-mutation --gate
```

This is correct against every spec decision:

- **No `continue-on-error`** → it is a true blocking gate (Decision 1, one-shot
  promotion with no transient observation step). Confirmed by the Ruby
  workflow-invariant assertion below.
- **Invokes the executable-owned gate path** (`--bulk-structural-mutation --gate`),
  not a YAML-duplicated threshold → budgets stay single-sourced in
  `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift` (Decision 2).
- **Positioned after the structural-mutation gate, before memory-shape** → all
  five blocking latency gates stay contiguous and fail before lower-priority
  diagnostics (Decision 4). Verified by the assertion's
  `i_struct < i_bulk < i_mem` ordering check.
- **Same `docs_only_pr != 'true'` guard** as every adjacent gate → docs-only PRs
  still skip it via the trusted lightweight path (Decision 7).
- **No `shell: bash` override** → a single one-line command with no pipes
  (Decision 8).
- **Required context names unchanged** (`Host tests and benchmark gate`,
  `iOS cross-target compile`, `WASM cross-target observation`) → the job becomes
  stricter without a ruleset or required-context change (Decision 6).

### The `deterministicIndex` hardening (the one code change)

This is what distinguishes Slice 26 from the prior three pure-promotion slices.
The Slice 25 review's P3 #2 flagged that both mutation benchmarks compute their
remove/insert indices as `(sample &* multiplier) % modulus`. The wrapping `&*`
produces a **negative** product once `sample * multiplier` exceeds `Int.max`, and
Swift's `%` preserves the dividend's sign, so the index could go negative and trip
the providers' `index >= 0` precondition — a crash. At current loop bounds this is
**latent, not live**, which is why every gate runs clean; but once the bulk gate is
a *required* blocking check, a future bump to `iterations`/`operationsPerSample`
crossing the overflow threshold would turn a latent trap into a spurious red
required gate. And critically, the **identical trap already sat in the
already-blocking structural-mutation gate** (required since Slice 24).

The fix is the minimal, DRY one: a single helper in `BenchmarkSupport.swift`,
mixing in `UInt` so the wrapping multiply can never carry a negative dividend into
the index:

```swift
// Deterministic, always-non-negative index in 0..<modulus. Mixing is done in
// UInt so the wrapping multiply can never produce a negative dividend that
// Swift's signed `%` would carry into a negative index (which would trip an
// `index >= 0` precondition and crash a benchmark gate). `modulus` must be > 0.
func deterministicIndex(sample: Int, multiplier: UInt, modulus: Int) -> Int {
    Int(UInt(bitPattern: sample) &* multiplier % UInt(modulus))
}
```

Both call sites use it correctly (verified in the merged source):

- `BulkStructuralMutationBenchmark.swift:127–133` — a single `modulus = lineCount -
  batch + 1` binding feeds both the remove and insert index;
- `StructuralMutationBenchmark.swift:90,94` — `modulus = lineCount`.

No remaining signed `&*`-into-`%` index site exists in `Sources/ViewportBenchmarks/`
(fresh `rg` below, exit 1). The result is always in `0..<modulus ≤ 1_000_000`, so
the final `Int(_:)` narrowing cannot trap, and every scenario's modulus is
positive (bulk's smallest is `1000 − 64 + 1 = 937`; structural's smallest is
`1000`), so `UInt(modulus)` is well-defined throughout.

**The `VariableHeightBenchmark` exclusion is sound.** Spec Decision 5
deliberately leaves the bucket selector `((index &* 31) &+ 7) % 4` untouched. I
verified its result feeds a `switch bucket` statement
(`VariableHeightBenchmark.swift:51–52`), not an array subscript, so a negative
value falls through the switch's exhaustive cases rather than tripping an index
precondition — no crash class, correctly out of scope.

### `AGENTS.md` (durable guidance)

The CI section's host-job bullet now lists
`→ --bulk-structural-mutation --gate (blocking)` after the structural-mutation
gate and before `--memory-shape`, and the "fail the job on perf regression"
sentence now names the bulk-structural-mutation gate alongside the other four. The
command-list local invocation and the benchmark-flags lists already carried the
mode from Slice 25 and were correctly left unchanged. The docs-only, iOS, WASM,
ruleset, and bypass-caveat wording is unchanged.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged `main` at `06f2b7a`)

- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `rg -n "&\* (2_654_435_761|40_503)" Sources/ViewportBenchmarks/` → **no matches**,
  exit `1` (the unsafe signed-mix pattern is fully removed).
- `git diff --check b74fcf9..HEAD` → no output, exit `0`.
- `git diff --name-only b74fcf9..06f2b7a -- Sources/TextEngineCore
  Sources/TextEngineReferenceProviders Tests Package.swift` → **empty** (no core,
  provider, test, or manifest surface touched).
- Ruby workflow-invariant assertion (step exists, invokes
  `--bulk-structural-mutation --gate`, not `continue-on-error`, ordered
  `structural < bulk < memory-shape`) → `workflow_assertions_ok`, exit `0`.
- `./.github/scripts/cross-target-compile.sh --self-test` → `self_test=pass`.
- `swift test` → **107 tests, 0 failures** (plus the expected empty Swift Testing
  `0 tests in 0 suites` line). Unchanged from the Slice 25 baseline, as expected
  for a slice that adds no test and changes no provider/core behavior.
- `swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate` →
  all five scenarios `gate=pass`; **all five checksums byte-identical** to the
  recorded baseline (`82740062444`, `36564666309410`, `1317343499882000`,
  `2285022074625`, `82203678997143`).
- `swift run -c release ViewportBenchmarks -- --structural-mutation --gate` → all
  three `gate=pass`; **all three checksums byte-identical** to the baseline
  (`200106952336`, `89494497658324`, `3379593298396981`).

The eight matching checksums independently re-prove, on macOS arm64, that the
`deterministicIndex` refactor is behavior-preserving at current parameters — the
load-bearing claim of the hardening.

### Fresh local bulk-gate numbers (macOS arm64, this review)

| Scenario | p95 (ns) | Budget p95 | Headroom |
| --- | ---: | ---: | ---: |
| 1k_lines_batch_64 | 3,543 | 60,000 | ~17× |
| 100k_lines_batch_64 | 11,448 | 150,000 | ~13× |
| 1m_lines_batch_64 | 51,007 | 400,000 | ~7.8× |
| 100k_lines_batch_4096 | 65,177 | 1,500,000 | ~23× |
| 1m_lines_batch_4096 | 155,098 | 2,500,000 | ~16× |

Consistent with the Slice 25 review's recorded macOS numbers (run-to-run noise
aside); the tightest path (1M × K=64) sits ~7.8× under budget locally.

### Hosted Linux x86_64 budget-fit (the load-bearing evidence for this slice)

Decision 3 bet that the macOS-calibrated budgets would hold on hosted Linux, with
the one-shot PR-head run **being** that evidence. It held across both hosted runs.
The bulk benchmark had **never run in hosted CI** before this slice, so these are
the first hosted Linux x86_64 numbers for the mode:

| Scenario | macOS local p95 | PR-head p95 | Post-merge p95 | Budget p95 |
| --- | ---: | ---: | ---: | ---: |
| 1k_lines_batch_64 | 3,543 | 6,729 | 7,237 | 60,000 |
| 100k_lines_batch_64 | 11,448 | 19,081 | 19,972 | 150,000 |
| 1m_lines_batch_64 | 51,007 | 81,883 | 55,096 | 400,000 |
| 100k_lines_batch_4096 | 65,177 | 158,203 | 168,664 | 1,500,000 |
| 1m_lines_batch_4096 | 155,098 | 444,483 | 289,829 | 2,500,000 |

Hosted Linux is meaningfully slower and noisier than macOS arm64 (the 1M × K=4096
p95 ranged 289k→444k across the two hosted runs, vs ~155k locally), as expected.
Even so, the tightest hosted scenario (1M × K=64 at ~82k p95) sits **~4.9× under
budget**, and the heaviest absolute (1M × K=4096 at ~0.44 ms/op) is **~5.6× under
budget**; all p99 values clear their budgets comfortably. The one-shot blocking
promotion was the right call: no observe-then-block ceremony was needed and
Decision 3's "stop and re-derive Linux budgets" escape hatch was never triggered.
All five hosted checksums on both runs equal the local baseline, confirming the
bulk path — and the hardening — are deterministic across platforms.

This is the heaviest budget-fit check of the four promotions, and it is the first
where the tightest scenario (~4.9× hosted) is *below* the ~10× Slice 24 promoted
against; the spec explicitly anticipated this and leaned on Decision 3 rather than
a headroom margin. It cleared regardless.

### Hosted runs (verified at step-log level, not just job conclusion)

Both runs independently re-verified via `gh` during this review — and, per the
project's "a green job can hide a dead `continue-on-error` step" lesson, the new
gate was checked at the **step** level, not just the job conclusion:

- **PR #44 final-head run `27898840239`** (head `6595ad1`, event
  `pull_request`): all three required jobs `success`. Host job ran the **full heavy
  path** — `Complete docs-only PR` = `skipped`; `Run structural mutation benchmark
  gate` = `success`; `Run bulk structural mutation benchmark gate` = `success`.
- **Post-merge push run `27906325500`** on merge commit `b5e4fbb` (event `push`):
  all three required jobs `success`. The host job's **step 12
  `Run bulk structural mutation benchmark gate` is itself `conclusion=success`**,
  sitting between step 11 (structural) and step 13 (memory-shape), with step 5
  `Complete docs-only PR` = `skipped` and step 15 (realistic observation, PR-only)
  = `skipped`. **This is the merged-code evidence anchor for Slice 26**: the new
  gate is a real blocking step that ran on merged code and passed, not a masked
  one. Merge parentage confirms `b5e4fbb`'s second parent is `6595ad1`, so the
  proof anchors the actually-merged head.

PR #45 was a docs-only follow-up touching only the verification record, so it
legitimately took the trusted docs-only path; the workflow YAML has not changed
since `b5e4fbb`, so run `27906325500` still represents current `main`'s workflow
behavior.

## Git History

Reviewed Slice 26 commits (PR #44 → #45):

```text
42ece0e docs: add bulk-structural-mutation CI gate promotion design
e35cb04 docs: address spec review for bulk-structural-mutation CI gate promotion
fb58385 docs: add bulk-structural-mutation CI gate promotion implementation plan
ef50ad2 docs: record pre-hardening checksum baseline for slice 26
cefbe46 refactor: harden benchmark index mixing via shared deterministicIndex helper
aac41e1 ci: add blocking bulk-structural-mutation benchmark gate
006116a docs: document bulk-structural-mutation as a blocking CI gate
6595ad1 docs: record local verification sweep for slice 26
b5e4fbb Merge pull request #44 …
c507d33 docs: record bulk-structural-mutation gate post-merge proof
06f2b7a Merge pull request #45 …
```

Clean, incremental, one-logical-step-per-commit with correct conventional-commit
prefixes: `docs:` for spec/plan/guidance/verification, `refactor:` for the
behavior-preserving helper extraction, `ci:` for the workflow step. The
baseline → harden → promote → document → verify ordering matches the plan's
stated rationale exactly (the checksum baseline `ef50ad2` lands on the pre-edit
tree before the `cefbe46` refactor that the baseline proves). The two-PR split
(implementation + local proof, then post-merge proof) is the standard pattern.

## Code Review Findings

Reviewing across workflow correctness, the hardening's behavior-preservation and
scope, evidence integrity, and policy concerns:

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, the gate is blocking and proven green at step level on
merged code, the hardening is behavior-preserving (eight checksums unchanged), the
scope is clean, and Foundation/core invariants are intact.

### P2 / Production Readiness

None. Notably — and unlike Slices 24 and 25 — the verification record carries **no
evidence-accuracy defect**. See "The recurring stale-on-write defect was finally
broken" under Lessons; this is the headline process improvement of the slice.

### P3 / Minor But Valid

**1. Spec/implementation primitive-naming drift, still open (carried from Slice 25
P3 #3).** The bulk-edits spec names the join primitive `join(_:_:)` while the
implementation ships `join3`/`join2`. Slice 26's spec explicitly scoped this out
(it is a cosmetic provider-doc item unrelated to CI), so it is correctly *not* a
Slice 26 defect — but it remains an open hygiene item with no home slice yet. A
one-line cross-reference in the bulk-edits spec would retire it whenever a
provider-touching slice next opens.

No P3 changes whether the merged result is correct; #1 is pre-existing hygiene
that this slice legitimately deferred.

## Risks And Gaps

### Budgets remain macOS-derived after this slice

Promotion confirmed the macOS budgets fit hosted Linux but did not re-derive
Linux-native budgets. That matches the standing project posture for all five gates
and is acceptable. With five latency gates now on hosted Linux, the accumulated
x86_64 evidence makes a dedicated Linux budget re-baseline (Option D) viable
future work, explicitly out of scope here.

### The heaviest workload now runs in hosted CI, with real but bounded variance

This gate added the suite's heaviest benchmark workload (1M × K=4096) to hosted CI
for the first time. The hosted 1M × K=4096 p95 varied 289k→444k across two runs —
this is expected hosted-CI noise and stays ~5.6×+ under budget, but it is the
scenario worth watching if a future change tightens the bulk workload or the
budget. The step adds roughly a minute and stays within the job's timeout.

### All five latency gates are now CI-protected — and the index trap is closed in all of them

With this slice, the provider's full edit surface (single + bulk structural,
variable-height static + mutation, synthetic) is under hosted regression
protection, and the `deterministicIndex` refactor removed the latent negative-index
crash from *both* mutation gates (including the structural one that was already
required). There is no remaining CI gap forcing another governance slice.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative
observation remains PR-only `continue-on-error`; the `Main` ruleset keeps its
documented bypass-actor shape (the admin user can still bypass required checks).
None were in scope for Slice 26.

## Lessons For The Next Slice

1. **The recurring stale-on-write defect was finally broken.** Slice 24 needed a
   third correction PR (#39) and Slice 25 shipped a P2 evidence defect because both
   recorded the PR-head proof against a pre-final commit *and* (in Slice 25)
   mis-described a source-bearing PR head as taking the docs-only shortcut. Slice
   25's review item #1 prescribed the concrete fix; Slice 26 **adopted it
   verbatim**: the PR-head proof was recorded **only** in the post-merge follow-up
   (PR #45), against the stable final head `6595ad1`, and the source-bearing PR
   head was correctly described as running the full heavy path (`Complete docs-only
   PR` = `skipped`), never as docs-only. The result is a verification record with
   no accuracy defect and no correction PR — the first promotion slice to land
   clean on the first evidence pass. **Keep this convention for every
   source/workflow-touching slice.**
2. **Fold-in hardening should match the blast radius of the risk, not the slice
   that surfaced it.** The Slice 25 review found the index trap in the bulk
   benchmark, but the same trap sat in the already-required structural gate. Fixing
   only the bulk site would have been less correct and less DRY; the shared helper
   applied to both call sites was the right move, and the checksum-equality proof
   (baseline captured fresh, since Slice 25's doc had dropped the `checksum=` field)
   made the "behavior-preserving" claim auditable rather than asserted.
3. **One-shot promotion now holds even below the prior headroom margin.** Slices
   21/24 validated one-shot promotion at ~10× macOS headroom. Slice 26's tightest
   scenario cleared at ~4.9× *hosted* headroom on the first run, backed by Decision
   3's stop-and-retune fallback rather than a fat margin. One-shot is the right
   default; reserve observe-then-block only for genuinely thin-margin gates.
4. **The functional → gate-promotion cadence has now completed four full cycles.**
   The CI/governance backlog opened by functional work is fully drained again. The
   provider is free to evolve under complete regression protection — the next slice
   has no CI debt forcing its hand.

## Slice 27 Candidate Options

### Option A: Advance the next real engine capability

Move beyond vertical-only layout/virtualization math toward the next brief
capability — width/wrap-aware metrics, a horizontal axis, or position-query APIs
such as `lineAt(y:)`. Highest product value and largest scope; needs a brainstorm
+ spec to pin the increment. This is the strongest pick now that the provider's
entire edit surface is CI-protected and there is no governance debt to drain. It
is the natural successor to the Slice 25/26 "return to functional core, then close
the gate" pair.

### Option B: Promote WASM cross-target to blocking

The long-deferred (Slice 22 Option A) infra item: provision a pinned,
version-matched WASM Swift SDK in the hosted job, prove it stably green, then flip
WASM from observational to blocking for both packages. Infra-gated on stable SDK
provisioning; the only standing CI item with real coverage upside.

### Option C: Linux-native budget re-baseline

With five latency gates now on hosted Linux, re-derive Linux-native budgets from
the accumulated x86_64 evidence and retire the macOS-calibration caveat. Low
product value, useful hygiene; a clean, well-scoped CI slice. Most worthwhile if
folded into a slice that already runs the gates hosted.

### Option D: Re-express single-line structural ops over split/join

The Slice 25 spec left `insertLine`/`removeLine` untouched. They could be
re-expressed as `insertLines`/`removeLines` of size 1 to unify the structural
paths over the now-proven `split`/`join2`/`join3` framework — but only if it does
not regress the (now-blocking) `--structural-mutation` gate. Low value, internal
tidiness; would also close the P3 #1 naming-drift item as a side effect.

### Option E: Ruleset bypass policy review

Decide whether the current bypass-actor shape is acceptable long-term. A
repo-policy slice, kept separate from benchmark/provider work.

## Recommended Slice 27 Selection

Recommended Slice 27 is **Option A — advance the next real engine capability**.

The reasoning: the project has now completed four full "functional slice → gate
promotion" cycles, and with Slice 26 the provider's entire edit surface (single
and bulk structural mutation, static and mutating variable-height) runs under
blocking hosted regression protection. **There is no remaining CI/governance gap
forcing another infra slice** — the condition that drove Slices 18–22, 24, and 26.
The engine has also been heavily focused on the *vertical* axis (line offsets,
heights, structural edits); the brief's larger ambition (realistic editing of
100k+ line / >10 MB documents) needs the next dimension of capability —
width/wrap-aware metrics, a horizontal axis, or position-query APIs like
`lineAt(y:)`. That is where the product value now is, and the protected provider
is a solid base to build on.

Because Option A is a genuine new-capability increment, it should **start with a
brainstorm and spec** rather than a drive-by — the increment needs to be pinned
(which capability, how it stays Foundation-free / Embedded-compatible, and what
its equivalence oracle and benchmark look like). The A-vs-B call (new capability
vs. finally promoting WASM) is a genuine product-vs-infra decision worth surfacing
to the user; given functional momentum and zero CI debt, Option A is the
consistent next step, with Option B the strongest pick if the preference is to
close the last standing infra item instead.

## Slice 26 Review Conclusion

Slice 26 delivered the intended governance increment plus a clean fold-in: the
`--bulk-structural-mutation --gate` benchmark now runs as the fifth blocking
latency gate in the required host job, so bulk insert/delete-range regressions —
the heaviest workload in the suite — block merge, and the shared
`deterministicIndex` helper removed a latent negative-index crash from **both** the
bulk gate and the already-required structural gate. The macOS-calibrated budgets
held on hosted Linux x86_64 with ~4.9×+ headroom even at the tightest scenario,
validating the one-shot promotion despite a thinner margin than the prior three
promotions and never triggering the budget-failure escape hatch. The hardening is
behavior-preserving — eight per-scenario checksums byte-identical to a freshly
captured pre-edit baseline, re-confirmed locally in this review. The change is
correctly scoped (zero core, provider, test, or manifest surface; required
contexts, docs-only behavior, and ruleset all unchanged) and verified at the step
level on both the final PR-head run and the post-merge push run.

The review found **no P0, P1, or P2 issues** against the merged result, and — for
the first time in the four-slice promotion arc — **no evidence-accuracy defect**:
Slice 26 adopted Slice 25's stale-on-write lesson verbatim, recording the PR-head
proof only in the post-merge follow-up against the stable final head and never
mis-classifying the source-bearing PR as docs-only. The one open P3 (spec/code
primitive-naming drift) is pre-existing hygiene this slice legitimately deferred.
With all five latency gates now CI-protected and no governance debt remaining,
Slice 26 cleanly closes the CI/governance arc and hands off to a return to
new-capability functional work.
