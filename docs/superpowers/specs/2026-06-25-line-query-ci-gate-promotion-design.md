# Line-Query CI Gate Promotion Design

Date: 2026-06-25

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 28 of SwiftTextEngine, following the Slice 27 post-slice review:

```text
docs/superpowers/reviews/2026-06-24-slice-27-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires regression
benchmarks to block merge when performance regresses
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
That requirement already holds for five latency gates running blocking in the
hosted `Host tests and benchmark gate` job: synthetic, static variable-height,
variable-height-mutation, structural-mutation, and bulk-structural-mutation. It
does **not** yet hold for the inverse vertical position-query path introduced in
Slice 27.

Slice 27 added the public stateless query `ViewportVirtualizer.lineAt(y:metrics:)`
— mapping a document y offset back to the logical line owning that half-open
vertical span over the existing `LineMetricsSource` abstraction — and a
local-only benchmark gate:

- `--line-query` benchmark mode (output `line_query`) over **five** scenarios:
  `uniform_1k` / `uniform_100k` / `uniform_1m` on the O(1)-offset
  `UniformLineMetrics` provider (O(log N) wall-clock), and
  `balanced_tree_100k` / `balanced_tree_1m` on the mutable
  `BalancedTreeLineMetrics` provider (the real O(log²N) path, where each
  `offset(ofLine:)` probe is itself O(log N));
- local `--line-query --gate` budgets, passing locally with very large headroom.

The Slice 27 post-slice review recommends Slice 28 as:

```text
Option A: Promote `--line-query --gate` to hosted CI
```

and lays out Options B–E (provider-native prefix search, geometry-bearing query,
horizontal/wrap-aware capability, WASM blocking) as later directions. The user
selected **Option A**, the **one-shot blocking** rollout.

### Relationship to the prior promotions (Slices 15, 21, 24, 26)

This slice is the fifth benchmark-gate promotion in the established cadence. The
prior four were Slice 15 (variable-height), Slice 21 (variable-height-mutation),
Slice 24 (structural-mutation), and Slice 26 (bulk-structural-mutation). They
split into two shapes:

- **Flip an existing hosted observation step to blocking** — Slices 15 and 21.
  Those benchmarks already ran in hosted CI as non-blocking observation steps, so
  promotion had prior hosted Linux evidence in hand.
- **Promote a benchmark that has never run in hosted CI** — Slices 24 and 26.
  There was no observation step to flip and no prior hosted Linux x86_64
  evidence; budgets were macOS-calibrated only, and the PR-head hosted run
  produced the Linux evidence.

Slice 28 is the second shape — the direct analog of Slices 24 and 26. Slice 27
kept `--line-query --gate` local-only, so the line-query benchmark has **never
run in hosted CI**: there is no observation step to flip and no prior hosted
Linux x86_64 evidence, its budgets are macOS-calibrated only, and the one-shot
PR-head run is what produces the Linux budget-fit evidence.

The one material difference from Slice 26 makes this the **lowest-risk
promotion in the series**: where the bulk gate carried the heaviest workload in
the suite at only ~6.7×–19× local headroom, the line-query benchmark is the
*cheapest* per-operation path in the suite. Its local headroom is **~325×–3000×**
(see the budget table below). So the one-shot rollout does not lean on a thin
margin — it has by far the most generous one yet, with Decision 3
(stop-and-retune on a failing hosted run) as the standing safety net.

### Current host CI shape (relevant excerpt)

```yaml
- name: Run structural mutation benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --structural-mutation --gate

- name: Run bulk structural mutation benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --bulk-structural-mutation --gate

- name: Run memory shape diagnostic
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

There is no `--line-query` step anywhere in the workflow today.

### Current line-query budgets and local evidence

The benchmark mode already carries executable-owned budgets
(`Sources/ViewportBenchmarks/LineQueryBenchmark.swift`). Recorded Slice 27 local
observation (macOS arm64); the Slice 27 review reran the gate, matched the
deterministic per-scenario checksums, and stayed passing (timing rows vary run to
run and were not bit-identical):

| Scenario | Observed p95 ns | Budget p95 ns | Headroom | Observed p99 ns | Budget p99 ns |
| --- | ---: | ---: | ---: | ---: | ---: |
| uniform_1k          | ~23    | 30,000    | ~1,300× | ~41    | 60,000    |
| uniform_100k        | ~29    | 60,000    | ~2,000× | ~47    | 120,000   |
| uniform_1m          | ~40    | 120,000   | ~3,000× | ~55    | 240,000   |
| balanced_tree_100k  | ~860   | 300,000   | ~350×   | ~998   | 600,000   |
| balanced_tree_1m    | ~1,838 | 600,000   | ~325×   | ~2,546 | 1,200,000 |

The tightest path (`balanced_tree_1m`) still sits ~325× under budget locally —
roughly 48× more headroom than the bulk gate's tightest scenario at promotion.

## Problem

The line-query path is proven locally but its **latency** is invisible to hosted
CI. Today the host job stays green regardless of `lineAt` runtime, because the
benchmark is not invoked in the workflow at all.

The hosted job already runs `swift test`, so the correctness and
algorithmic-shape guarantees are enforced: `LineAtQueryCountTests`
deterministically bounds the `offset(ofLine:)` probe count at O(log N) and proves
the clamp branches never run the binary search, and `LineAtTests` plus the
equivalence oracle cover the half-open boundary behavior. An accidental linear
scan, a clamp-branch search, or a boundary-convention change would fail those
unit tests and already block merge.

What the unit tests do **not** catch is a runtime budget/latency regression — a
constant-factor slowdown, an added allocation, or a cache-unfriendly change that
preserves query count and correctness but degrades wall-clock p95/p99. That is
the enforcement gap:

- runtime latency regressions in `ViewportVirtualizer.lineAt` — and in the
  unchanged generic variable-height core path it exercises through the inverse
  y→line query — are not blocking;
- the brief's "benchmark gates block merge" principle is not yet true for the
  inverse vertical position-query path.

With required checks, docs-only shortcut trust, and the other five latency gates
already hardened, making the line-query benchmark fail the same required host job
is the natural next governance step, and it closes the single
regression-protection gap Slice 27 opened.

## Scope

Slice 28 introduces the line-query benchmark to the hosted host-tests job as a
**blocking gate** in a single PR.

Expected implementation surface:

- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/verification/2026-06-25-line-query-ci-gate-promotion.md`

Expected paper trail:

- this design spec;
- a task-by-task plan after this spec is approved;
- a verification record with local and hosted evidence;
- a post-slice review after implementation and merge.

The slice changes only the workflow YAML and docs. It must not touch
`TextEngineCore`, `TextEngineReferenceProviders`, any benchmark Swift source
(scenarios, budgets, or helpers), or any other benchmark mode.

### No bundled hardening

Unlike Slice 26 — which folded in the P3 index-overflow hardening
(`deterministicIndex`) because the Slice 25 review flagged a latent crash class
in the promoted benchmark — the Slice 27 review found **no P0/P1/P2 and no
actionable P3 items**. The line-query benchmark builds its sample `y` values from
non-negative `sample % …` arithmetic and the existing shared
`deterministicScrollOffset` helper; it derives no array index from a wrapping
signed multiply, so it carries no analogous crash class. This slice therefore
promotes the existing benchmark **unchanged** and touches no benchmark source.

## Goals

- Add a `--line-query --gate` step to the hosted `Host tests and benchmark gate`
  job.
- Make the step blocking: no `continue-on-error: true`.
- Place the step immediately after `Run bulk structural mutation benchmark gate`
  and before `Run memory shape diagnostic`, keeping all six blocking latency
  gates contiguous and failing before lower-priority diagnostics.
- Keep benchmark budgets in `Sources/ViewportBenchmarks`, not duplicated in
  workflow YAML.
- Keep the current macOS-calibrated budgets for this promotion, and use the
  PR-head hosted run as the Linux x86_64 evidence that confirms they fit.
- Keep the three required job contexts unchanged.
- Keep trusted docs-only PR behavior unchanged.
- Update `AGENTS.md` so the CI section lists the line-query gate as blocking in
  hosted CI.
- Record local and hosted proof that line-query benchmark output includes
  `budget_p95_ns`, `budget_p99_ns`, and `gate=pass` for all five scenarios, and
  that the hosted step is not `continue-on-error`.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` changes.
- No `lineAt` / `LineMetricsSource` API changes.
- No benchmark workload redesign, scenario change, budget retune, or benchmark
  Swift edit of any kind unless the first hosted run forces a spec revisit
  (Decision 3).
- No provider-native prefix search (Slice 27 review Option B) — a future slice.
- No geometry-bearing vertical query (Option C).
- No horizontal/wrap-aware capability (Option D).
- No new benchmark mode.
- No new Swift test target or benchmark XCTest harness.
- No cross-target provider coverage expansion.
- No hosted WASM promotion (Option E).
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

Rationale: the budgets span ~325×–3000× macOS headroom — by far the most
generous of any promotion in this series. The PR-head CI run executes the step
on hosted Linux x86_64 and prints `p95_ns` / `p99_ns` / budget fields whether or
not it passes, so a single blocking step both enforces and produces the hosted
evidence. The most comparable prior promotions — Slice 24 (structural-mutation)
and Slice 26 (bulk-structural-mutation), which like this slice promoted a
never-hosted benchmark straight to blocking — went one-shot at ~6.7×–~10×
headroom and passed; with ~48× more headroom than the tightest of those, one-shot
here is the clear low-risk choice. Decision 3's stop-and-retune fallback remains
the net. This keeps the slice to one clean PR.

Rejected alternative — observe-then-block: add a non-blocking observation step
first, read the hosted numbers, then promote in a follow-up. For a benchmark
with three orders of magnitude of headroom this is pure ceremony, and the
one-shot path's failure mode (Decision 3) recovers the same evidence inside the
same PR.

### Decision 2 — Promote the existing executable gate path

The workflow should call the benchmark executable exactly as local verification
does:

```bash
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate
```

Rejected alternative: encode line-query budgets in workflow YAML. Budgets
already live with the benchmark scenarios in
`Sources/ViewportBenchmarks/LineQueryBenchmark.swift` and are printed by the
executable. A workflow budget copy would create two sources of truth.

### Decision 3 — Keep current budgets; treat a first-run hosted failure as evidence

This slice promotes the existing macOS-calibrated budgets rather than retuning
them up front. The standing budget-calibration rule asks for hosted Linux
x86_64 evidence before trusting budgets; the one-shot PR-head run **is** that
evidence, recorded in the verification doc.

If the first hosted PR-head run fails because hosted Linux behavior does not fit
the existing budgets, implementation must **stop** and update this design with
the new hosted numbers, then re-derive Linux-appropriate budgets in
`LineQueryBenchmark.swift`. It must **not** hide the failure with
`continue-on-error`, a workflow-only threshold, or a silent budget widening. The
two `balanced_tree` scenarios (the O(log²N) mutable-provider path, tightest at
~325×) are the ones to watch, though even they would have to regress by more
than two orders of magnitude to breach budget.

### Decision 4 — Keep the host job order

The line-query gate sits immediately after the bulk-structural-mutation gate:

1. `swift test`
2. synthetic benchmark gate
3. static variable-height benchmark gate
4. variable-height mutation benchmark gate
5. structural-mutation benchmark gate
6. bulk-structural-mutation benchmark gate
7. **line-query benchmark gate (new)**
8. memory-shape diagnostic
9. RSS memory observation
10. PR-only realistic relative observation

This keeps all six blocking latency gates contiguous and fails before
lower-priority diagnostics if the inverse-query path regresses.

### Decision 5 — Do not change required context names

The ruleset already requires `Host tests and benchmark gate`. Slice 28 makes
that job stricter but must not create or rename required contexts. The iOS and
WASM jobs remain unchanged.

### Decision 6 — Leave docs-only behavior unchanged

Docs-only PRs still complete the required contexts through the trusted
lightweight path and skip heavy Swift work. The line-query gate is part of the
heavy host path and runs whenever `docs_only_pr != 'true'`, matching every
adjacent gate. This slice's PR changes workflow YAML, so it is never docs-only
and is fully exercised by the heavy path in its own PR.

### Decision 7 — A one-line Swift command needs no shell override

Like the other gate steps, the line-query gate uses no pipes, `set -o pipefail`,
or shell-specific behavior. It stays a plain `run:` line and does not need
`shell: bash`. The important workflow property is the absence of
`continue-on-error: true` on this step.

## Implementation Architecture

### Workflow

Insert into the host job, between the bulk-structural-mutation gate and the
memory-shape diagnostic:

```yaml
- name: Run line query benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate
```

No other workflow step should need to move or change.

### Documentation

Update `AGENTS.md` in the CI section (the `Host tests and benchmark gate`
bullet):

- add `→ --line-query --gate (blocking)` to the host-job step sequence, after
  `--bulk-structural-mutation --gate (blocking)` and before `--memory-shape`;
- extend the "fail the job on perf regression" sentence so it also names the
  line-query gate (e.g. "synthetic, static variable-height, mutation
  variable-height, structural-mutation, bulk-structural-mutation, and line-query
  gates");
- keep memory diagnostics, RSS observation, realistic relative observation, iOS,
  WASM, docs-only shortcut, ruleset, and bypass caveat wording unchanged.

The command list already documents the local `--line-query --gate` command; that
local-invocation line stays consistent with its siblings.

### Verification Record

Create:

```text
docs/superpowers/verification/2026-06-25-line-query-ci-gate-promotion.md
```

The record should include exact commands, exit statuses, and representative
output lines.

Local verification should include at minimum:

```bash
swift run -c release ViewportBenchmarks -- --line-query --gate
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift test
git diff --check
rg -n "Foundation" Sources/TextEngineCore
```

Plus a **workflow-invariant assertion** that goes beyond a bare YAML parse —
asserting the new step exists, invokes `--line-query --gate`, is not
`continue-on-error`, and sits in the required order
(bulk-structural-mutation → line-query → memory-shape). For example:

```bash
ruby -ryaml -e '
  wf = YAML.load_file(".github/workflows/swift-ci.yml")
  steps = wf["jobs"]["host-tests-and-benchmark-gate"]["steps"]
  names = steps.map { |s| s["name"] }
  lq = steps.find { |s| s["name"] == "Run line query benchmark gate" }
  raise "missing line-query gate step" unless lq
  raise "line-query gate not invoking --line-query --gate" unless lq["run"].include?("--line-query --gate")
  raise "line-query gate must not be continue-on-error" if lq["continue-on-error"]
  i_bulk = names.index("Run bulk structural mutation benchmark gate")
  i_lq   = names.index("Run line query benchmark gate")
  i_mem  = names.index("Run memory shape diagnostic")
  raise "bad gate ordering" unless i_bulk && i_lq && i_mem && i_bulk < i_lq && i_lq < i_mem
  puts "workflow_assertions_ok"
'
```

Hosted verification should include:

- final PR-head Swift CI run ID;
- all three required jobs `success`;
- host job step `Run line query benchmark gate` `success`, with its hosted Linux
  x86_64 `line_query` rows (all five scenarios) showing `gate=pass`,
  `budget_p95_ns`, and `budget_p99_ns` (the Linux budget-fit evidence);
- proof the line-query step is not `continue-on-error`;
- post-merge push run ID for the merge commit (this slice changes workflow YAML,
  so the merge is not docs-only and will not be skipped by
  `push.paths-ignore`).

To avoid the recurring evidence defect seen in earlier slices: record the
PR-head proof only in the post-merge follow-up where the final head SHA is
stable, and never describe a source-bearing PR's head as taking the docs-only
shortcut (the detector reads the full diff, which includes the YAML change here).

## Acceptance Criteria

- `.github/workflows/swift-ci.yml` contains a `Run line query benchmark gate`
  step that invokes `--line-query --gate`.
- The line-query step has no `continue-on-error: true`.
- The step is positioned after the bulk-structural-mutation gate and before the
  memory-shape diagnostic.
- The three required job context names remain unchanged:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- No benchmark Swift source changes (no scenario, budget, or helper edit);
  `git diff --name-only` for the PR touches only `.github/workflows/swift-ci.yml`,
  `AGENTS.md`, and `docs/**`.
- `AGENTS.md` describes the line-query benchmark as a blocking host-job gate that
  fails the job on perf regression.
- Local line-query gate passes with `gate=pass` for all five scenarios; all five
  pre-existing latency gates and `swift test` still pass.
- Hosted PR-head CI runs the line-query gate step and succeeds, with recorded
  Linux p95/p99 for all five scenarios as budget-fit evidence.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Risks And Gaps

### Hosted Linux variance could exceed current budgets

The budgets have recorded macOS headroom, but hosted Linux x86_64 differs from
macOS arm64 and has never run this mode. Prior promotions saw hosted Linux up to
~1.4–1.6× slower/noisier than local; the line-query budgets' ~325×–3000×
headroom absorbs that with three orders of magnitude to spare, but it is
unproven until the PR-head run. If the promotion PR fails because the benchmark
exceeds budget, treat that as evidence and revisit this spec (Decision 3). Do not
hide the failure with `continue-on-error` or a workflow-only threshold.

### Budgets remain macOS-derived after this slice

Promotion confirms the macOS budgets fit hosted Linux but does not re-derive
Linux-native budgets. That matches the standing project posture for the other
gates (budgets macOS-calibrated unless hosted Linux evidence justifies a retune)
and is acceptable; a dedicated Linux budget re-baseline remains possible future
work.

### Balanced-tree line queries remain O(log²N)

This slice protects the current line-query path against regression; it does not
improve its asymptotics. The `balanced_tree` scenarios still exercise the
generic O(log²N) query over the mutable provider. Slice 27 review Option B
(provider-native prefix search to reach a single O(log N) tree descent) remains
the highest-value algorithmic follow-up and is explicitly out of scope here.

### Bypass actors remain

The active `Main` ruleset still has a bypass-actor shape and the admin user can
bypass it. Slice 28 does not change repository bypass policy.

### WASM remains observational

The required `WASM cross-target observation` context stays green/required but
non-blocking when matching Swift SDKs are unavailable. This slice does not alter
that documented CI contract.

## Recommended Next Step

After this spec is approved, write the Slice 28 implementation plan. The plan
should be small and TDD-style: the most meaningful failing-first check is the
workflow-invariant assertion showing there is no blocking line-query gate step
before the YAML change, and a true blocking gate (with `--line-query --gate`,
without `continue-on-error`, ordered bulk → line-query → memory-shape) after it.
Because this slice touches no benchmark source, there is no checksum-equality
proof to carry — the verification leans on the workflow assertion plus the
hosted budget-fit run.
