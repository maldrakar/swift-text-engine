# Bulk-Structural-Mutation CI Gate Promotion Design

Date: 2026-06-21

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 26 of SwiftTextEngine, following the Slice 25 post-slice review:

```text
docs/superpowers/reviews/2026-06-21-slice-25-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires regression
benchmarks to block merge when performance regresses
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
That requirement already holds for four latency gates running blocking in the
hosted `Host tests and benchmark gate` job: synthetic, static variable-height,
variable-height-mutation, and structural-mutation. It does **not** yet hold for
the bulk insert/delete-range path introduced in Slice 25.

Slice 25 added true-bulk structural editing to the mutable provider and a
local-only benchmark gate:

- `TextEngineReferenceProviders.BalancedTreeLineMetrics` gained atomic
  `insertLines(at:heights:)` / `removeLines(at:count:)`, each O(k + log N) via
  join-based split/join primitives;
- `--bulk-structural-mutation` benchmark mode (output `bulk_structural_mutation`,
  provider `balanced_tree`) over **five** scenarios — 1k / 100k / 1M documents in
  two batch profiles, small `K=64` (typical paste/selection) and large `K=4096`
  (large paste / range delete);
- local `--bulk-structural-mutation --gate` budgets, passing locally with
  6.7×–19× headroom.

The Slice 25 post-slice review recommends Slice 26 as:

```text
Option A: Promote `--bulk-structural-mutation` to a blocking hosted gate
```

and explicitly flags the A-vs-B (promotion vs next engine capability) call as a
genuine product decision. The user selected **Option A**, the **one-shot
blocking** rollout, and folding in the **P3 #2 benchmark hardening**.

### Relationship to the prior promotion (Slice 24)

Slice 24 promoted the structural-mutation gate. This slice is its direct analog
for the bulk path and reuses Slice 24's decisions almost verbatim. The shared
starting state matters: like the structural-mutation benchmark before Slice 24,
the bulk benchmark has **never run in hosted CI**. There is no observation step
to flip and no prior hosted Linux x86_64 evidence; its budgets are
macOS-calibrated only. The PR-head hosted run is what produces that evidence.

The one material difference from Slice 24: the bulk benchmark carries the
**heaviest workload in the entire suite** — the 1M × K=4096 scenario at
~0.19 ms/op locally. That makes the hosted budget-fit check more load-bearing
than the prior three promotions. The mitigating fact is headroom: the bulk
budgets carry 6.7×–19× local headroom, larger than the ~10× Slice 24 promoted
against successfully in one shot.

### Current host CI shape (relevant excerpt)

```yaml
- name: Run variable-height mutation benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation --gate

- name: Run structural mutation benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --structural-mutation --gate

- name: Run memory shape diagnostic
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

There is no `--bulk-structural-mutation` step anywhere in the workflow today.

### Current bulk-structural-mutation budgets and local evidence

The benchmark mode already carries executable-owned budgets
(`Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift`). Recorded
Slice 25 local observation (macOS arm64), reproduced bit-identically during the
Slice 25 review:

| Scenario | Observed p95 ns | Budget p95 ns | Headroom |
| --- | ---: | ---: | ---: |
| 1k_lines_batch_64 | ~3,885 | 60,000 | ~15× |
| 100k_lines_batch_64 | ~11,817 | 150,000 | ~12.7× |
| 1m_lines_batch_64 | ~60,049 | 400,000 | ~6.7× |
| 100k_lines_batch_4096 | ~77,617 | 1,500,000 | ~19× |
| 1m_lines_batch_4096 | ~191,369 | 2,500,000 | ~13× |

The tightest path (1M × K=64) sits ~6.7× under budget locally; the heaviest
absolute workload (1M × K=4096) is ~0.19 ms/op at ~13× headroom.

## Problem

The bulk insert/delete-range path is proven locally but invisible to hosted CI.
Today the host job stays green regardless of bulk-structural-mutation
performance, because the benchmark is not invoked in the workflow at all. That
leaves an enforcement gap:

- regressions in `BalancedTreeLineMetrics` bulk insert/delete behavior — for
  example an O(k·log N) compose regression or an O(k + log²N) non-telescoping
  split — are not blocking;
- regressions in the unchanged generic variable-height core path, when exercised
  through bulk mutation + recompute, are not blocking;
- the brief's "benchmark gates block merge" principle is not yet true for the
  bulk editing path, which is the heaviest workload in the suite.

With required checks, docs-only shortcut trust, and the other four latency gates
already hardened, making the bulk-structural-mutation benchmark fail the same
required host job is the natural next governance step, and it closes the single
regression-protection gap Slice 25 opened.

## Scope

Slice 26 introduces the bulk-structural-mutation benchmark to the hosted
host-tests job as a **blocking gate** in a single PR, and folds in the one P3
benchmark-hardening fix that protects that gate against a latent crash.

Expected implementation surface:

- `.github/workflows/swift-ci.yml`
- `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift` (index-mixing
  hardening only)
- `AGENTS.md`
- `docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md`

Expected paper trail:

- this design spec;
- a task-by-task plan after this spec is approved;
- a verification record with local and hosted evidence;
- a post-slice review after implementation and merge.

The slice should not change any other Swift source. It must not touch
`TextEngineCore`, the provider/algorithm in `TextEngineReferenceProviders`,
benchmark scenarios/budgets (unless a hosted run forces a retune per Decision 3),
or any other benchmark mode.

## Goals

- Add a `--bulk-structural-mutation --gate` step to the hosted
  `Host tests and benchmark gate` job.
- Make the step blocking: no `continue-on-error: true`.
- Place the step immediately after `Run structural mutation benchmark gate` and
  before `Run memory shape diagnostic`, keeping all five blocking latency gates
  contiguous and failing before lower-priority diagnostics.
- Keep benchmark budgets in `Sources/ViewportBenchmarks`, not duplicated in
  workflow YAML.
- Keep the current macOS-calibrated budgets for this promotion, and use the
  PR-head hosted run as the Linux x86_64 evidence that confirms they fit.
- Harden the benchmark's deterministic index mixing (P3 #2 from the Slice 25
  review) so a future iteration-count bump cannot produce a negative index that
  crashes the now-blocking gate — without changing emitted output at current
  parameters.
- Keep the three required job contexts unchanged.
- Keep trusted docs-only PR behavior unchanged.
- Update `AGENTS.md` so the CI section lists the bulk-structural-mutation gate as
  blocking in hosted CI.
- Record local and hosted proof that bulk-structural-mutation benchmark output
  includes `budget_p95_ns`, `budget_p99_ns`, and `gate=pass` for all five
  scenarios, and that the hosted step is not `continue-on-error`.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` (provider/algorithm) changes.
- No `BalancedTreeLineMetrics` API changes.
- No benchmark workload redesign, scenario change, or budget retune unless the
  first hosted run forces a spec revisit (Decision 3).
- No new benchmark mode.
- No P3 #3 (spec/code primitive-naming-drift cosmetic doc) fix — out of scope.
- No new Swift test target or benchmark XCTest harness.
- No cross-target provider coverage expansion.
- No hosted WASM promotion.
- No realistic-provider observation promotion.
- No ruleset mutation.
- No new required GitHub status context.
- No workflow job rename.
- No docs-only detector change.
- No `pull_request_target` workflow.
- No bypass-actor policy change.

## Decisions

### Decision 1 — One-shot blocking gate, no transient observation step

Add the step directly as a blocking gate in one PR, rather than first landing a
`continue-on-error` observation step and flipping it later. (User-selected
rollout.)

Rationale: the budgets carry 6.7×–19× macOS headroom; the PR-head CI run
executes the step on hosted Linux x86_64 and prints `p95_ns` / `p99_ns` / budget
fields whether or not it passes, so a single blocking step both enforces and
produces the hosted evidence. Slice 24 promoted the structural-mutation gate
one-shot against a smaller ~10× headroom and passed. This keeps the slice to one
clean PR.

Rejected alternative — observe-then-block: add a non-blocking observation step
first, read the hosted numbers, then promote in a follow-up. Safer against a
surprise red gate on the heaviest 1M × K=4096 scenario, but more ceremony for a
benchmark with large headroom, and the one-shot path's failure mode (Decision 3)
recovers the same evidence inside the same PR.

### Decision 2 — Promote the existing executable gate path

The workflow should call the benchmark executable exactly as local verification
does:

```bash
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --bulk-structural-mutation --gate
```

Rejected alternative: encode bulk-structural-mutation budgets in workflow YAML.
Budgets already live with the benchmark scenarios in
`Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift` and are
printed by the executable. A workflow budget copy would create two sources of
truth.

### Decision 3 — Keep current budgets; treat a first-run hosted failure as evidence

This slice promotes the existing macOS-calibrated budgets rather than retuning
them up front. The standing budget-calibration rule asks for hosted Linux
x86_64 evidence before trusting budgets; the one-shot PR-head run **is** that
evidence, recorded in the verification doc.

If the first hosted PR-head run fails because hosted Linux behavior does not fit
the existing budgets, implementation must **stop** and update this design with
the new hosted numbers, then re-derive Linux-appropriate budgets in
`BulkStructuralMutationBenchmark.swift`. It must **not** hide the failure with
`continue-on-error`, a workflow-only threshold, or a silent budget widening. The
1M × K=64 scenario (tightest at ~6.7×) and the 1M × K=4096 scenario (heaviest
absolute) are the two to watch.

### Decision 4 — Keep the host job order

The bulk-structural-mutation gate sits immediately after the structural-mutation
gate:

1. `swift test`
2. synthetic benchmark gate
3. static variable-height benchmark gate
4. variable-height mutation benchmark gate
5. structural-mutation benchmark gate
6. **bulk-structural-mutation benchmark gate (new)**
7. memory-shape diagnostic
8. RSS memory observation
9. PR-only realistic relative observation

This keeps all five blocking latency gates contiguous and fails before
lower-priority diagnostics if the bulk path regresses.

### Decision 5 — Fold in the P3 #2 index-mixing hardening, scoped to the benchmark

The Slice 25 review's P3 #2 finding: `runBulkStructuralMutationScenario` computes

```swift
let removeIndex = (sample &* 2_654_435_761) % (lineCount - batch + 1)
let insertIndex = (sample &* 40_503) % (lineCount - batch + 1)
```

The wrapping `&*` produces a **negative** product once `sample * constant`
exceeds `Int.max`, and Swift's `%` preserves the dividend's sign, so the index
could go negative and trip the `index >= 0` precondition — a crash. At current
loop bounds (largest sample index `2000 × 256 − 1 = 511,999`, product ~1.36e15 ≪
`Int.max`) this is **latent, not live**, which is why the local gate runs clean.
But once this benchmark is a blocking required gate, a future bump to
`iterations` / `operationsPerSample` that crosses the overflow threshold would
turn a latent trap into a spurious red required gate.

Fix: do the modular mixing in `UInt`:

```swift
let modulus = lineCount - batch + 1
let removeIndex = Int(UInt(bitPattern: sample &* 2_654_435_761) % UInt(modulus))
let insertIndex = Int(UInt(bitPattern: sample &* 40_503) % UInt(modulus))
```

**Behavior-preserving at current parameters.** For the current positive products,
`UInt(bitPattern:)` reinterprets the same magnitude and unsigned `%` equals
signed `%` for a positive dividend, so `removeIndex` / `insertIndex` — and
therefore the emitted **checksums — are bit-identical** to the recorded Slice 25
runs. The change only removes the latent trap; the verification record will show
the gate checksums unchanged before and after the edit. `modulus =
lineCount - batch + 1` is positive for every scenario (`batch ≤ lineCount`
always; the smallest modulus is the `1k_lines_batch_64` case at
`1000 − 64 + 1 = 937`), so `UInt(modulus)` is well-defined for all five
scenarios.

This is a benchmark-only, non-behavioral hardening that directly serves the
slice goal (a blocking gate must not be crashable by its own index generation).
It does not touch the bulk algorithm, the provider, or the core. The P3 #3
naming-drift item is cosmetic and unrelated to CI; it stays out of scope.

### Decision 6 — Do not change required context names

The ruleset already requires `Host tests and benchmark gate`. Slice 26 makes
that job stricter but must not create or rename required contexts. The iOS and
WASM jobs remain unchanged.

### Decision 7 — Leave docs-only behavior unchanged

Docs-only PRs still complete the required contexts through the trusted
lightweight path and skip heavy Swift work. The bulk-structural-mutation gate is
part of the heavy host path and runs whenever `docs_only_pr != 'true'`, matching
every adjacent gate. This slice's PR changes workflow YAML and benchmark Swift
source, so it is never docs-only and is fully exercised by the heavy path in its
own PR.

### Decision 8 — A one-line Swift command needs no shell override

Like the other gate steps, the bulk-structural-mutation gate uses no pipes,
`set -o pipefail`, or shell-specific behavior. It stays a plain `run:` line and
does not need `shell: bash`. The important workflow property is the absence of
`continue-on-error: true` on this step.

## Implementation Architecture

### Workflow

Insert into the host job, between the structural-mutation gate and the
memory-shape diagnostic:

```yaml
- name: Run bulk structural mutation benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --bulk-structural-mutation --gate
```

No other workflow step should need to move or change.

### Benchmark hardening

In `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift`,
`runBulkStructuralMutationScenario`, replace the two signed `&*`-into-`%`
index expressions with the `UInt`-mixed form shown in Decision 5. No scenario,
budget, iteration count, or summary field changes.

### Documentation

Update `AGENTS.md` in the CI section (the `Host tests and benchmark gate`
bullet):

- add `→ --bulk-structural-mutation --gate (blocking)` to the host-job step
  sequence, after `--structural-mutation --gate (blocking)` and before
  `--memory-shape`;
- extend the "fail the job on perf regression" sentence so it also names the
  bulk-structural-mutation gate (e.g. "synthetic, static variable-height,
  mutation variable-height, structural-mutation, and bulk-structural-mutation
  gates");
- keep memory diagnostics, RSS observation, realistic relative observation, iOS,
  WASM, docs-only shortcut, ruleset, and bypass caveat wording unchanged.

The command list already documents the local `--bulk-structural-mutation --gate`
command; that local-invocation line stays consistent with its siblings.

### Verification Record

Create:

```text
docs/superpowers/verification/2026-06-21-bulk-structural-mutation-ci-gate-promotion.md
```

The record should include exact commands, exit statuses, and representative
output lines.

Local verification should include at minimum:

```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift test
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"
git diff --check
rg -n "Foundation" Sources/TextEngineCore
```

It should also record the **checksum-equality proof** for the hardening: the
`bulk_structural_mutation` checksums printed before and after the index-mixing
edit are identical for all five scenarios.

Hosted verification should include:

- final PR-head Swift CI run ID;
- all three required jobs `success`;
- host job step `Run bulk structural mutation benchmark gate` `success`, with its
  hosted Linux x86_64 `bulk_structural_mutation` rows (all five scenarios) showing
  `gate=pass`, `budget_p95_ns`, and `budget_p99_ns` (the Linux budget-fit
  evidence);
- proof the bulk-structural-mutation step is not `continue-on-error`;
- post-merge push run ID for the merge commit (this slice changes workflow YAML
  and benchmark source, so the merge is not docs-only and will not be skipped by
  `push.paths-ignore`).

To avoid the Slice 24/25 recurring evidence defect: record the PR-head proof
only in the post-merge follow-up where the final head SHA is stable, and never
describe a source-bearing PR's head as taking the docs-only shortcut (the
detector reads the full diff, which includes Swift/YAML here).

## Acceptance Criteria

- `.github/workflows/swift-ci.yml` contains a `Run bulk structural mutation
  benchmark gate` step that invokes `--bulk-structural-mutation --gate`.
- The bulk-structural-mutation step has no `continue-on-error: true`.
- The step is positioned after the structural-mutation gate and before the
  memory-shape diagnostic.
- The three required job context names remain unchanged:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- `BulkStructuralMutationBenchmark.swift` mixes `removeIndex` / `insertIndex` in
  `UInt`, and the five `bulk_structural_mutation` checksums are unchanged from the
  recorded Slice 25 values.
- `AGENTS.md` describes the bulk-structural-mutation benchmark as a blocking
  host-job gate that fails the job on perf regression.
- Local bulk-structural-mutation gate passes with `gate=pass` for all five
  scenarios; all four pre-existing latency gates and `swift test` still pass.
- Hosted PR-head CI runs the bulk-structural-mutation gate step and succeeds,
  with recorded Linux p95/p99 for all five scenarios as budget-fit evidence.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Risks And Gaps

### Hosted Linux variance could exceed current budgets

The budgets have recorded macOS headroom, but hosted Linux x86_64 differs from
macOS arm64 and has never run this mode. Slice 24 saw the structural 1M p95 range
34.6k–54.0k hosted vs ~33–39k locally, i.e. up to ~1.4–1.6× slower/noisier; the
bulk budgets' 6.7×–19× headroom comfortably absorbs that, but it is unproven
until the PR-head run. If the promotion PR fails because the benchmark exceeds
budget, treat that as evidence and revisit this spec (Decision 3). Do not hide
the failure with `continue-on-error` or a workflow-only threshold.

### Heaviest-workload-yet on hosted CI

This gate adds the heaviest benchmark workload in the suite (1M × K=4096,
~0.19 ms/op locally) to hosted CI for the first time. It is one more benchmark
mode over the same 1k/100k/1M scenarios as the adjacent gates and stays within
the job's 20-minute timeout, but it makes the budget-fit check more load-bearing
than the prior three promotions.

### Budgets remain macOS-derived after this slice

Promotion confirms the macOS budgets fit hosted Linux but does not re-derive
Linux-native budgets. That matches the standing project posture for the other
gates (budgets macOS-calibrated unless hosted Linux evidence justifies a retune)
and is acceptable; a dedicated Linux budget re-baseline remains possible future
work.

### Bypass actors remain

The active `Main` ruleset still has a bypass-actor shape and the admin user can
bypass it. Slice 26 does not change repository bypass policy.

### WASM remains observational

The required `WASM cross-target observation` context stays green/required but
non-blocking when matching Swift SDKs are unavailable. This slice does not alter
that documented CI contract.

## Recommended Next Step

After this spec is approved, write the Slice 26 implementation plan. The plan
should be small and TDD-style: the most meaningful failing-first check is a
textual workflow assertion showing there is no blocking bulk-structural-mutation
gate step before the YAML change, and a true blocking gate (with `--gate`,
without `continue-on-error`) after it; plus the checksum-equality proof framing
the index-mixing hardening as a behavior-preserving change.
