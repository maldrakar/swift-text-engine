# Column-Query CI Gate Promotion Design

Date: 2026-07-05

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 34 of SwiftTextEngine, following the Slice 33 post-slice review:

```text
docs/superpowers/reviews/2026-07-04-slice-33-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires regression
benchmarks to block merge when performance regresses
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
That requirement already holds for seven latency gates running blocking in the
hosted `Host tests and benchmark gate` job: synthetic, static variable-height,
variable-height-mutation, structural-mutation, bulk-structural-mutation,
line-query, and line-geometry-query. It does **not** yet hold for the horizontal
within-line position-query path introduced in Slice 33.

Slice 33 opened the engine's horizontal axis with the public stateless query
`ViewportVirtualizer.columnAt(x:inLine:metrics:) -> ColumnQuery` — the inverse
query `x -> cell` within a single line, over a new standalone
`LineHorizontalMetricsSource` provider abstraction, the faithful line-by-line
mirror of Slice 27's vertical `lineAt(y:metrics:)` — and a local-only benchmark
gate:

- `--column-query` benchmark mode (output `column_query`) over **five**
  scenarios: `uniform_1k` / `uniform_100k` / `uniform_1m` on the
  `UniformColumnMetrics` provider (in the core; O(1) `columnOffset`, but its
  located-cell search still uses the generic O(log M) binary-search fallback —
  `UniformColumnMetrics` has no native `columnIndex` override — so the overall
  uniform query is O(log M), not O(1), until a future closed-form override,
  Slice 33 review Option D), and `prefixsum_100k` / `prefixsum_1m` on the
  `PrefixSumColumnMetrics` reference provider (the realistic
  proportional-advance path, O(1) `columnOffset` from a per-line prefix-sum array
  held outside the core-memory invariant, located cell via the same generic
  binary-search default);
- local `--column-query --gate` budgets, passing locally with very large
  headroom (~1000×–5000×, per the Slice 33 review).

The Slice 33 post-slice review recommends Slice 34 as:

```text
Option A: `--column-query` CI-gate promotion (rhythm-consistent, debt-closing)
```

and lays out Options B–E (`pointAt` 2D composite, `columnGeometryAt` / caret-x,
closed-form / native column inverse, WASM blocking / Linux budget re-baseline) as
later directions. The user selected **Option A**, the **one-shot blocking**
rollout.

### Relationship to the prior promotions (Slices 15, 21, 24, 26, 28, 32)

This slice is the seventh benchmark-gate promotion in the established cadence. The
prior six were Slice 15 (variable-height), Slice 21 (variable-height-mutation),
Slice 24 (structural-mutation), Slice 26 (bulk-structural-mutation), Slice 28
(line-query), and Slice 32 (line-geometry-query). They split into two shapes:

- **Flip an existing hosted observation step to blocking** — Slices 15 and 21.
  Those benchmarks already ran in hosted CI as non-blocking observation steps, so
  promotion had prior hosted Linux evidence in hand.
- **Promote a benchmark that has never run in hosted CI** — Slices 24, 26, 28,
  and 32. There was no observation step to flip and no prior hosted Linux x86_64
  evidence; budgets were macOS-calibrated only, and the PR-head hosted run
  produced the Linux evidence.

Slice 34 is the second shape — the direct analog of Slices 24, 26, 28, and 32.
Slice 33 kept `--column-query --gate` local-only, so the column-query benchmark
has **never run in hosted CI**: there is no observation step to flip and no prior
hosted Linux x86_64 evidence, its budgets are macOS-calibrated only, and the
one-shot PR-head run is what produces the Linux budget-fit evidence.

Like Slices 28 and 32, this is a **very low-risk** promotion. `columnAt` is a
line-by-line structural mirror of the battle-tested `lineAt`, and the
`--column-query` benchmark reuses the `--line-query` budget shape verbatim; its
local headroom is generous — ~1000×–5000× (the Slice 33 review's figure). The
one-shot rollout does not lean on a thin margin, and Decision 3
(stop-and-retune on a failing hosted run) is the standing safety net.

### Current host CI shape (relevant excerpt)

```yaml
- name: Run line geometry query benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-geometry-query --gate

- name: Run memory shape diagnostic
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

There is no `--column-query` step anywhere in the workflow today.

### Current column-query budgets and local evidence

The benchmark mode already carries executable-owned budgets
(`Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift`), deliberately identical
to the `--line-query` / `--line-geometry-query` budgets. The Slice 33 review reran
the gate on the merged tree, matched the deterministic per-scenario checksums
byte-for-byte, and stayed passing. The budgets are:

| Scenario | Provider | Budget p95 ns | Budget p99 ns |
| --- | --- | ---: | ---: |
| uniform_1k     | `UniformColumnMetrics` (core)      | 30,000  | 60,000  |
| uniform_100k   | `UniformColumnMetrics` (core)      | 60,000  | 120,000 |
| uniform_1m     | `UniformColumnMetrics` (core)      | 120,000 | 240,000 |
| prefixsum_100k | `PrefixSumColumnMetrics` (reference) | 60,000  | 120,000 |
| prefixsum_1m   | `PrefixSumColumnMetrics` (reference) | 120,000 | 240,000 |

Recorded Slice 33 local observation (macOS arm64) put every scenario ~1000×–5000×
under budget. The observed p95/p99 timings are **approximate and
non-reproducible** — timing varies run to run and is not bit-identical; the
deterministic paper-trail anchor is the per-scenario checksum set plus the
executable-printed `budget_p95_ns` / `budget_p99_ns`, not timing rows. The
deterministic per-scenario checksums recorded in the Slice 33 verification (and
reproduced in that slice's review) are `641440000`, `63985556480`,
`639841600000`, `63985600000`, `639841560320`.

## Problem

The column-query path is proven locally but its **latency** is invisible to
hosted CI. Today the host job stays green regardless of `columnAt` runtime,
because the benchmark is not invoked in the workflow at all.

The hosted job already runs `swift test`, so the correctness and
algorithmic-shape guarantees are enforced: `ColumnAtQueryCountTests`
deterministically bounds the `columnOffset` probe count and proves the query
dispatches to the native `columnIndex` search then never takes a linear scan
(the event-log test pins the exact dispatch order and proves the blank / clamp /
non-finite paths never search), `ColumnAtTests` covers the half-open boundary,
clamp, and `.empty` behavior, and `ColumnAtEquivalenceTests` checks
`UniformColumnMetrics` against an independent closed-form oracle. An accidental
linear scan, a lost native dispatch, or a boundary/clamp change would fail those
unit tests and already block merge.

What the unit tests do **not** catch is a runtime budget/latency regression — a
constant-factor slowdown, an added allocation, or a cache-unfriendly change that
preserves query count and correctness but degrades wall-clock p95/p99. That is
the enforcement gap:

- runtime latency regressions in `ViewportVirtualizer.columnAt` — and in the
  provider `columnOffset` / `columnIndex` paths it queries — are not blocking;
- the brief's "benchmark gates block merge" principle is not yet true for the
  horizontal within-line position-query path.

With required checks, docs-only shortcut trust, and the other seven latency gates
already hardened, making the column-query benchmark fail the same required host
job is the natural next governance step, and it closes the single
regression-protection gap Slice 33 opened (debt (a) in the Slice 33 review).

## Scope

Slice 34 introduces the column-query benchmark to the hosted host-tests job as a
**blocking gate** in a single PR.

Expected implementation surface:

- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md`

Expected paper trail:

- this design spec;
- a task-by-task plan after this spec is approved;
- a verification record with local and hosted evidence;
- a post-slice review after implementation and merge.

The slice changes only the workflow YAML and docs. It must not touch
`TextEngineCore`, `TextEngineReferenceProviders`, any benchmark Swift source
(scenarios, budgets, or helpers), or any other benchmark mode.

### No bundled hardening

Like Slices 28 and 32 — and unlike Slice 26, which folded in the
`deterministicIndex` overflow hardening the Slice 25 review had flagged — the
Slice 33 review found **no P0/P1/P2 and no actionable P3 items** in the promoted
benchmark. The column-query benchmark builds its sample `x` values from
non-negative `sample % 8` / `sample % 1_000` arithmetic (`sample` is always
`>= 0`) and the existing shared `deterministicScrollOffset` helper — whose
`(sample * 37) % 1_000` is a plain, bounded signed multiply that returns a
`Double` offset, never an array index — and it does **not** call the
overflow-hardened `deterministicIndex`. The single wrapping multiply in the file
(`variableAdvances`' `index &* 31`) is bounded (`index <= 1_000_000`, so
`<= 31_000_000`, no wrap) and feeds a `% 4` bucket `switch`, never an array index.
So the benchmark derives no array index from a wrapping signed multiply and
carries no analogous crash class. This slice therefore promotes the existing
benchmark **unchanged** and touches no benchmark source.

## Goals

- Add a `--column-query --gate` step to the hosted `Host tests and benchmark
  gate` job.
- Make the step blocking: no `continue-on-error: true`.
- Place the step immediately after `Run line geometry query benchmark gate` and
  before `Run memory shape diagnostic`, keeping all eight blocking latency gates
  contiguous and failing before lower-priority diagnostics.
- Keep benchmark budgets in `Sources/ViewportBenchmarks`, not duplicated in
  workflow YAML.
- Keep the current macOS-calibrated budgets for this promotion, and use the
  PR-head hosted run as the Linux x86_64 evidence that confirms they fit.
- Keep the three required job contexts unchanged.
- Keep trusted docs-only PR behavior unchanged.
- Update `AGENTS.md` so the CI section lists the column-query gate as blocking in
  hosted CI (the eighth blocking latency gate) and the architecture paragraph no
  longer calls `--column-query` a local (not-yet-CI) gate.
- Record local and hosted proof that column-query benchmark output includes
  `budget_p95_ns`, `budget_p99_ns`, and `gate=pass` for all five scenarios, and
  that the hosted step is not `continue-on-error`.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` changes.
- No `columnAt` / `LineHorizontalMetricsSource` API changes.
- No benchmark workload redesign, scenario change, budget retune, or benchmark
  Swift edit of any kind unless the first hosted run forces a spec revisit
  (Decision 3).
- No provider-native / closed-form column inverse (Slice 33 review Option D) — a
  future slice.
- No horizontal geometry / caret-x `columnGeometryAt` (Option C).
- No 2D `pointAt(x:y:)` composite (Option B).
- No new benchmark mode.
- No new Swift test target or benchmark XCTest harness.
- No cross-target provider coverage expansion.
- No hosted WASM promotion or Linux budget re-baseline (Option E).
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

Rationale: the budgets span ~1000×–5000× macOS headroom — a margin
comparable-to-wider than the `--line-query` / `--line-geometry-query` siblings
carried at their Slice 28 / 32 promotions (line-query was ~325×–3000×, tighter at
the low end; line-geometry-query ~1900×–5400×), and over two orders of magnitude
above the tightest gate the series has promoted (the bulk gate at ~6.7×). The PR-head CI run executes the
step on hosted Linux x86_64 and prints `p95_ns` / `p99_ns` / budget fields whether
or not it passes, so a single blocking step both enforces and produces the hosted
evidence. The most comparable prior promotions — Slices 24, 26, 28, and 32, which
like this slice promoted a never-hosted benchmark straight to blocking — all went
one-shot and passed; Slice 32 (the immediate predecessor and this slice's
structural twin) did so at even more generous headroom than the tighter bulk gate.
Decision 3's stop-and-retune fallback remains the net. This keeps the slice to one
clean PR.

Rejected alternative — observe-then-block: add a non-blocking observation step
first, read the hosted numbers, then promote in a follow-up. For a benchmark with
three orders of magnitude of headroom this is pure ceremony, and the one-shot
path's failure mode (Decision 3) recovers the same evidence inside the same PR.

### Decision 2 — Promote the existing executable gate path

The workflow should call the benchmark executable exactly as local verification
does:

```bash
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-query --gate
```

Rejected alternative: encode column-query budgets in workflow YAML. Budgets
already live with the benchmark scenarios in
`Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift` and are printed by the
executable. A workflow budget copy would create two sources of truth.

### Decision 3 — Keep current budgets; treat a first-run hosted failure as evidence

This slice promotes the existing macOS-calibrated budgets rather than retuning
them up front. The standing budget-calibration rule asks for hosted Linux x86_64
evidence before trusting budgets; the one-shot PR-head run **is** that evidence,
recorded in the verification doc.

If the first hosted PR-head run fails because hosted Linux behavior does not fit
the existing budgets, implementation must **stop** and update this design with the
new hosted numbers, then re-derive Linux-appropriate budgets in
`ColumnQueryBenchmark.swift`. It must **not** hide the failure with
`continue-on-error`, a workflow-only threshold, or a silent budget widening. The
`prefixsum_1m` scenario is the one to watch — not because it holds the least
multiplicative headroom, but because it is the realistic proportional-advance path
at the largest cell count (1,000,000), so a hosted-Linux constant-factor slowdown
would surface there first. Even so, given the ~1000×–5000× local headroom it would
have to regress by three orders of magnitude to breach budget.

Unlike the Slice 32 twin, this spec carries only the aggregate ~1000×–5000× range
(the Slice 33 review's figure), not a per-scenario headroom table, so it cannot
yet name which scenario holds the *least* headroom versus which carries the
largest absolute latency. The verification record must close that gap: tabulate
per-scenario observed p95 and headroom (p95 budget ÷ observed p95) for all five
scenarios, both locally and on the hosted PR-head run, so "`prefixsum_1m` is the
one to watch" and "least multiplicative headroom" are grounded in numbers rather
than narrative — and so any future Linux re-baseline (Option E) starts from a
recorded per-scenario baseline.

### Decision 4 — Keep the host job order

The column-query gate sits immediately after the line-geometry-query gate:

1. `swift test`
2. synthetic benchmark gate
3. static variable-height benchmark gate
4. variable-height mutation benchmark gate
5. structural-mutation benchmark gate
6. bulk-structural-mutation benchmark gate
7. line-query benchmark gate
8. line-geometry-query benchmark gate
9. **column-query benchmark gate (new)**
10. memory-shape diagnostic
11. RSS memory observation
12. PR-only realistic relative observation

This keeps all eight blocking latency gates contiguous and fails before
lower-priority diagnostics if the horizontal position-query path regresses.
Placing it directly after the vertical gates also buys differential diagnosis: a
line-query / line-geometry-query **pass** with a column-query **fail** localizes
the regression to the horizontal axis (`columnAt`, `columnOffset`, `columnIndex`)
rather than to any shared vertical path.

### Decision 5 — Do not change required context names

The ruleset already requires `Host tests and benchmark gate`. Slice 34 makes that
job stricter but must not create or rename required contexts. The iOS and WASM
jobs remain unchanged.

### Decision 6 — Leave docs-only behavior unchanged

Docs-only PRs still complete the required contexts through the trusted
lightweight path and skip heavy Swift work. The column-query gate is part of the
heavy host path and runs whenever `docs_only_pr != 'true'`, matching every
adjacent gate. This slice's PR changes workflow YAML — and the docs-only detector
explicitly rejects `.github/workflows/**` before applying the Markdown allow rule
— so this PR is never docs-only and is fully exercised by the heavy path in its
own PR.

### Decision 7 — A one-line Swift command needs no shell override

Like the other gate steps, the column-query gate uses no pipes, `set -o
pipefail`, or shell-specific behavior. It stays a plain `run:` line and does not
need `shell: bash`. The important workflow property is the absence of
`continue-on-error: true` on this step.

## Implementation Architecture

### Workflow

Insert into the host job, between the line-geometry-query gate and the
memory-shape diagnostic:

```yaml
- name: Run column query benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-query --gate
```

No other workflow step should need to move or change.

### Documentation

Update `AGENTS.md` in two places:

- **Architecture paragraph** — the `columnAt` description currently ends
  "… `--column-query` is its **local** (not-yet-CI) gate." Change that to describe
  `--column-query` as its blocking host-job gate (dropping "local (not-yet-CI)").
- **CI section** (the `Host tests and benchmark gate` bullet):
  - add `→ --column-query --gate (blocking)` to the host-job step sequence, after
    `--line-geometry-query --gate (blocking)` and before `--memory-shape`;
  - extend the "fail the job on perf regression" sentence so it also names the
    column-query gate (e.g. "… line-query, line-geometry-query, and column-query
    gates");
  - keep memory diagnostics, RSS observation, realistic relative observation, iOS,
    WASM, docs-only shortcut, ruleset, and bypass caveat wording unchanged.

The command list already documents the local `--column-query --gate` command; that
local-invocation line stays consistent with its siblings.

### Verification Record

Create:

```text
docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md
```

The record should include exact commands, exit statuses, and representative
output lines.

Local verification should include at minimum:

```bash
swift run -c release ViewportBenchmarks -- --column-query --gate
swift run -c release ViewportBenchmarks -- --line-query --gate
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
swift test
git diff --check
rg -n "Foundation" Sources/TextEngineCore
```

Because this slice's central Non-Goal is *no benchmark source change*, the local
`--column-query --gate` run is also the cheapest possible proof of that Non-Goal:
record that all five per-scenario `column_query` checksums are **byte-identical**
to the values Slice 33 established (`641440000`, `63985556480`, `639841600000`,
`63985600000`, `639841560320`). A checksum drift would mean the benchmark
workload changed — which this slice forbids — so the equality is a free integrity
check even though no *new* checksum is being established. Capture the observed
per-scenario p95/p99 as well, so the headroom this spec cites (below) is
grounded in this slice's own numbers, not only carried from the Slice 33 record.

Plus a **workflow-invariant assertion** that goes beyond a bare YAML parse —
asserting the new step exists, invokes `--column-query --gate`, is not
`continue-on-error`, carries the same `docs_only_pr` guard as its sibling gates
(Decision 6), sits in the required order (line-geometry-query → column-query →
memory-shape), and that the three required job context names are unchanged
(Decision 5). For example:

```bash
ruby -ryaml -e '
  wf = YAML.load_file(".github/workflows/swift-ci.yml")
  jobs = wf["jobs"]
  steps = jobs["host-tests-and-benchmark-gate"]["steps"]
  names = steps.map { |s| s["name"] }
  cq  = steps.find { |s| s["name"] == "Run column query benchmark gate" }
  lgq = steps.find { |s| s["name"] == "Run line geometry query benchmark gate" }
  raise "missing column-query gate step" unless cq
  raise "missing line-geometry-query gate step" unless lgq
  raise "gate not invoking --column-query --gate" unless cq["run"].include?("--column-query --gate")
  raise "column-query gate must not be continue-on-error" if cq["continue-on-error"]
  raise "column-query gate must share its siblings docs-only guard" unless cq["if"] == lgq["if"]
  i_lgq = names.index("Run line geometry query benchmark gate")
  i_cq  = names.index("Run column query benchmark gate")
  i_mem = names.index("Run memory shape diagnostic")
  raise "bad gate ordering" unless i_lgq && i_cq && i_mem && i_lgq < i_cq && i_cq < i_mem
  required = ["Host tests and benchmark gate", "iOS cross-target compile", "WASM cross-target observation"]
  actual = jobs.values.map { |j| j["name"] }
  raise "required job context name(s) changed" unless required.all? { |n| actual.include?(n) }
  puts "workflow_assertions_ok"
'
```

Hosted verification should include:

- final PR-head Swift CI run ID;
- all three required jobs `success`;
- host job step `Run column query benchmark gate` `success`, with its hosted Linux
  x86_64 `column_query` rows (all five scenarios) showing `gate=pass`,
  `budget_p95_ns`, and `budget_p99_ns` (the Linux budget-fit evidence);
- a per-scenario hosted headroom line for all five scenarios (observed `p95_ns` /
  `p99_ns` and headroom = budget ÷ observed), so the Linux budget-fit is recorded
  quantitatively and the `prefixsum_1m` watch-scenario (Decision 3) has a concrete
  hosted number;
- proof the column-query step is not `continue-on-error`;
- post-merge push run ID for the merge commit (this slice changes workflow YAML,
  so the merge is not docs-only and will not be skipped by `push.paths-ignore`).

To avoid the recurring evidence defect seen in earlier slices: record the PR-head
proof only in the post-merge follow-up where the final head SHA is stable, and
never describe a source-bearing PR's head as taking the docs-only shortcut (the
detector reads the full diff, which includes the YAML change here, and rejects
`.github/workflows/**` outright). Verify hosted runs at the **step** level, not
just the job conclusion (a green job can hide a dead `continue-on-error` step).

## Acceptance Criteria

- `.github/workflows/swift-ci.yml` contains a `Run column query benchmark gate`
  step that invokes `--column-query --gate`.
- The column-query step has no `continue-on-error: true`.
- The step is positioned after the line-geometry-query gate and before the
  memory-shape diagnostic.
- The three required job context names remain unchanged:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- No benchmark Swift source changes (no scenario, budget, or helper edit);
  `git diff --name-only` for the PR touches only `.github/workflows/swift-ci.yml`,
  `AGENTS.md`, and `docs/**`.
- `AGENTS.md` describes the column-query benchmark as a blocking host-job gate
  that fails the job on perf regression, and no longer calls `--column-query` a
  local (not-yet-CI) gate.
- Local column-query gate passes with `gate=pass` for all five scenarios; all
  seven pre-existing latency gates and `swift test` still pass.
- Hosted PR-head CI runs the column-query gate step and succeeds, with recorded
  Linux p95/p99 and per-scenario headroom (budget ÷ observed) for all five
  scenarios as budget-fit evidence.
- Local verification records that the five per-scenario `column_query` checksums
  are byte-identical to the Slice 33 values, proving the benchmark workload is
  unchanged.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Risks And Gaps

### Hosted Linux variance could exceed current budgets

The budgets have recorded macOS headroom, but hosted Linux x86_64 differs from
macOS arm64 and has never run this mode. Prior promotions saw hosted Linux up to
~1.4–1.6× slower/noisier than local; the column-query budgets' ~1000×–5000×
headroom absorbs that with three orders of magnitude to spare, but it is unproven
until the PR-head run. If the promotion PR fails because the benchmark exceeds
budget, treat that as evidence and revisit this spec (Decision 3). Do not hide the
failure with `continue-on-error` or a workflow-only threshold.

### Budgets remain macOS-derived after this slice

Promotion confirms the macOS budgets fit hosted Linux but does not re-derive
Linux-native budgets. That matches the standing project posture for the other
gates (budgets macOS-calibrated unless hosted Linux evidence justifies a retune)
and is acceptable; a dedicated Linux budget re-baseline remains possible future
work (Option E).

### Column queries carry inherited fallback costs

This slice protects the current column-query path against regression; it does not
improve its asymptotics. Both shipped providers rely on the generic
`binarySearchColumnIndex` default, so the uniform case pays an O(log M) search
where an exact closed form would be O(1), and prefix-sum pays O(log M) where a
native descent would too — the horizontal analog of the vertical fallback-bound
providers (Slice 33 review Option D / P3 #1). Those are constant-factor / inherited
costs, explicitly out of scope here.

### Bypass actors remain

The active `Main` ruleset still has a bypass-actor shape and the admin user can
bypass it. Slice 34 does not change repository bypass policy.

### WASM remains observational

The required `WASM cross-target observation` context stays green/required but
non-blocking when matching Swift SDKs are unavailable. This slice does not alter
that documented CI contract.

## Recommended Next Step

After this spec is approved, write the Slice 34 implementation plan. The plan
should be small and TDD-style: the most meaningful failing-first check is the
workflow-invariant assertion showing there is no blocking column-query gate step
before the YAML change, and a true blocking gate (with `--column-query --gate`,
without `continue-on-error`, ordered line-geometry-query → column-query →
memory-shape) after it. Because this slice touches no benchmark source, there is
no *new* checksum to establish — but the verification should still confirm the
five per-scenario checksums are byte-identical to the Slice 33 values as a free
"benchmark unchanged" integrity check, and otherwise leans on the workflow
assertion plus the hosted per-scenario budget-fit run.
