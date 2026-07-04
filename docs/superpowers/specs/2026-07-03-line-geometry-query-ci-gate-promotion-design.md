# Line-Geometry-Query CI Gate Promotion Design

Date: 2026-07-03

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 32 of SwiftTextEngine, following the Slice 31 post-slice review:

```text
docs/superpowers/reviews/2026-07-02-slice-31-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires regression
benchmarks to block merge when performance regresses
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
That requirement already holds for six latency gates running blocking in the
hosted `Host tests and benchmark gate` job: synthetic, static variable-height,
variable-height-mutation, structural-mutation, bulk-structural-mutation, and
line-query. It does **not** yet hold for the geometry-bearing vertical
position-query path introduced in Slice 31.

Slice 31 added the public stateless query
`ViewportVirtualizer.lineGeometryAt(y:metrics:)` — the geometry-bearing companion
to Slice 27's `lineAt`, mapping a document `y` offset back to the located line's
`LineGeometry` box (index, top `y`, height), the within-line `fractionInLine`, and
the same clamp flag, composed over `lineAt` plus two `offset(ofLine:)` probes — and
a local-only benchmark gate:

- `--line-geometry-query` benchmark mode (output `line_geometry_query`) over
  **five** scenarios: `uniform_1k` / `uniform_100k` / `uniform_1m` on the
  O(1)-offset `UniformLineMetrics` provider (its `offset(ofLine:)` is O(1), but its
  located-index search still uses the generic O(log N) binary-search fallback —
  `UniformLineMetrics` has no native `lineIndex` override — so the overall uniform
  query is O(log N), not O(1), until a future closed-form override, Slice 31 review
  Option D), and `balanced_tree_100k` /
  `balanced_tree_1m` on the mutable `BalancedTreeLineMetrics` provider (the
  realistic O(log N)-offset path, where each `offset(ofLine:)` probe is itself
  O(log N) and the located index uses the Slice 29 native descent);
- local `--line-geometry-query --gate` budgets, passing locally with very large
  headroom.

The Slice 31 post-slice review recommends Slice 32 as:

```text
Option A: Promote `--line-geometry-query --gate` to a blocking hosted CI gate
```

and lays out Options B–E (provider-native geometry descent, horizontal/point/wrap
capability, uniform closed-form override, WASM blocking / Linux budget re-baseline)
as later directions. The user selected **Option A**, the **one-shot blocking**
rollout.

### Relationship to the prior promotions (Slices 15, 21, 24, 26, 28)

This slice is the sixth benchmark-gate promotion in the established cadence. The
prior five were Slice 15 (variable-height), Slice 21 (variable-height-mutation),
Slice 24 (structural-mutation), Slice 26 (bulk-structural-mutation), and Slice 28
(line-query). They split into two shapes:

- **Flip an existing hosted observation step to blocking** — Slices 15 and 21.
  Those benchmarks already ran in hosted CI as non-blocking observation steps, so
  promotion had prior hosted Linux evidence in hand.
- **Promote a benchmark that has never run in hosted CI** — Slices 24, 26, and 28.
  There was no observation step to flip and no prior hosted Linux x86_64 evidence;
  budgets were macOS-calibrated only, and the PR-head hosted run produced the
  Linux evidence.

Slice 32 is the second shape — the direct analog of Slices 24, 26, and 28. Slice
31 kept `--line-geometry-query --gate` local-only, so the line-geometry-query
benchmark has **never run in hosted CI**: there is no observation step to flip and
no prior hosted Linux x86_64 evidence, its budgets are macOS-calibrated only, and
the one-shot PR-head run is what produces the Linux budget-fit evidence.

Like Slice 28, this is a **very low-risk** promotion. The line-geometry-query
benchmark composes over `lineAt` (the line-query path just hardened in Slice 28)
plus a constant two `offset(ofLine:)` probes, so its per-operation cost class is
`lineAt`'s and its local headroom is generous — **~1900×–5400×** (see the budget
table below). That headroom is in fact *wider* than line-query's was at its Slice 28
promotion (~325×–3000×), especially on the balanced-tree end: Slices 29/30 turned
balanced-tree `lineAt` into a single native O(log N) descent, so the balanced-tree
scenarios now run at ~133–191 ns (vs the ~860–1838 ns Slice 28 measured on the old
O(log²N) generic path). The one-shot rollout does not lean on a thin margin, and
Decision 3 (stop-and-retune on a failing hosted run) is the standing safety net.

### Current host CI shape (relevant excerpt)

```yaml
- name: Run line query benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate

- name: Run memory shape diagnostic
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

There is no `--line-geometry-query` step anywhere in the workflow today.

### Current line-geometry-query budgets and local evidence

The benchmark mode already carries executable-owned budgets
(`Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift`), deliberately
identical to the `--line-query` budgets. Recorded Slice 31 local observation
(macOS arm64); the Slice 31 review reran the gate, matched the deterministic
per-scenario checksums byte-for-byte, and stayed passing. The observed p95/p99
columns below are **approximate and non-reproducible** — timing varies run to run and
was not bit-identical; the deterministic paper-trail anchor is the per-scenario
checksum set (below) plus the executable-printed `budget_p95_ns`/`budget_p99_ns`, not
these timing rows:

| Scenario | Observed p95 ns | Budget p95 ns | Headroom | Budget p99 ns |
| --- | ---: | ---: | ---: | ---: |
| uniform_1k          | ~16  | 30,000    | ~1,900× | 60,000    |
| uniform_100k        | ~19  | 60,000    | ~3,200× | 120,000   |
| uniform_1m          | ~22  | 120,000   | ~5,400× | 240,000   |
| balanced_tree_100k  | ~133 | 300,000   | ~2,250× | 600,000   |
| balanced_tree_1m    | ~191 | 600,000   | ~3,140× | 1,200,000 |

Every scenario sits well over ~1,900× under budget locally — *wider* than the
line-query gate's headroom at its Slice 28 promotion (~325×–3000×; the balanced-tree
end is now O(log N) native, not the O(log²N) Slice 28 measured), and over two orders
of magnitude more headroom than the tightest gate the series has promoted (the bulk
gate at ~6.7× in Slice 26). The deterministic
per-scenario checksums recorded in the Slice 31 verification are `160641440000`,
`267505512960`, `799841600000`, `223985600000`, `852321495040`.

## Problem

The line-geometry-query path is proven locally but its **latency** is invisible to
hosted CI. Today the host job stays green regardless of `lineGeometryAt` runtime,
because the benchmark is not invoked in the workflow at all.

The hosted job already runs `swift test`, so the correctness and
algorithmic-shape guarantees are enforced: `LineGeometryAtQueryCountTests`
deterministically bounds the `offset(ofLine:)` probe count and proves the composed
query dispatches to `lineAt`'s native index search then takes exactly two ordered
geometry probes (never a linear scan or redundant re-search), and
`LineGeometryAtTests` plus the balanced-tree equivalence oracle cover the
half-open boundary and fraction behavior across a scroll sweep and after
mutations. An accidental linear scan, a lost native dispatch, or a boundary/fraction
change would fail those unit tests and already block merge.

What the unit tests do **not** catch is a runtime budget/latency regression — a
constant-factor slowdown, an added allocation, or a cache-unfriendly change that
preserves query count and correctness but degrades wall-clock p95/p99. That is
the enforcement gap:

- runtime latency regressions in `ViewportVirtualizer.lineGeometryAt` — and in the
  `lineAt` core path it composes over — are not blocking;
- the brief's "benchmark gates block merge" principle is not yet true for the
  geometry-bearing vertical position-query path.

With required checks, docs-only shortcut trust, and the other six latency gates
already hardened, making the line-geometry-query benchmark fail the same required
host job is the natural next governance step, and it closes the single
regression-protection gap Slice 31 opened.

## Scope

Slice 32 introduces the line-geometry-query benchmark to the hosted host-tests job
as a **blocking gate** in a single PR.

Expected implementation surface:

- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md`

Expected paper trail:

- this design spec;
- a task-by-task plan after this spec is approved;
- a verification record with local and hosted evidence;
- a post-slice review after implementation and merge.

The slice changes only the workflow YAML and docs. It must not touch
`TextEngineCore`, `TextEngineReferenceProviders`, any benchmark Swift source
(scenarios, budgets, or helpers), or any other benchmark mode.

### No bundled hardening

Like Slice 28 — and unlike Slice 26, which folded in the `deterministicIndex`
overflow hardening the Slice 25 review had flagged — the Slice 31 review found
**no P0/P1/P2 and no actionable P3 items** in the promoted benchmark. The
line-geometry-query benchmark builds its sample `y` values from non-negative
`sample % …` arithmetic and the existing shared `deterministicScrollOffset`
helper; it derives no array index from a wrapping signed multiply, so it carries no
analogous crash class. This slice therefore promotes the existing benchmark
**unchanged** and touches no benchmark source.

## Goals

- Add a `--line-geometry-query --gate` step to the hosted `Host tests and
  benchmark gate` job.
- Make the step blocking: no `continue-on-error: true`.
- Place the step immediately after `Run line query benchmark gate` and before `Run
  memory shape diagnostic`, keeping all seven blocking latency gates contiguous and
  failing before lower-priority diagnostics.
- Keep benchmark budgets in `Sources/ViewportBenchmarks`, not duplicated in
  workflow YAML.
- Keep the current macOS-calibrated budgets for this promotion, and use the
  PR-head hosted run as the Linux x86_64 evidence that confirms they fit.
- Keep the three required job contexts unchanged.
- Keep trusted docs-only PR behavior unchanged.
- Update `AGENTS.md` so the CI section lists the line-geometry-query gate as
  blocking in hosted CI (the seventh blocking latency gate).
- Record local and hosted proof that line-geometry-query benchmark output includes
  `budget_p95_ns`, `budget_p99_ns`, and `gate=pass` for all five scenarios, and
  that the hosted step is not `continue-on-error`.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` changes.
- No `lineGeometryAt` / `lineAt` / `LineMetricsSource` API changes.
- No benchmark workload redesign, scenario change, budget retune, or benchmark
  Swift edit of any kind unless the first hosted run forces a spec revisit
  (Decision 3).
- No provider-native geometry-bearing descent (Slice 31 review Option B) — a future
  slice.
- No horizontal / point / wrap-aware capability (Option C).
- No verified closed-form uniform override (Option D).
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

Rationale: the budgets span ~1,900×–5,400× macOS headroom — *wider* than the
line-query gate at its Slice 28 promotion and over two orders of magnitude above
the tightest gate the series has promoted (the bulk gate at ~6.7×). The PR-head CI
run executes the step on hosted Linux
x86_64 and prints `p95_ns` / `p99_ns` / budget fields whether or not it passes, so
a single blocking step both enforces and produces the hosted evidence. The most
comparable prior promotions — Slice 24, Slice 26, and Slice 28, which like this
slice promoted a never-hosted benchmark straight to blocking — all went one-shot
and passed; Slice 28 (the immediate predecessor and this slice's structural twin)
did so at even more generous headroom than the tighter bulk gate. Decision 3's
stop-and-retune fallback remains the net. This keeps the slice to one clean PR.

Rejected alternative — observe-then-block: add a non-blocking observation step
first, read the hosted numbers, then promote in a follow-up. For a benchmark with
three orders of magnitude of headroom this is pure ceremony, and the one-shot
path's failure mode (Decision 3) recovers the same evidence inside the same PR.

### Decision 2 — Promote the existing executable gate path

The workflow should call the benchmark executable exactly as local verification
does:

```bash
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-geometry-query --gate
```

Rejected alternative: encode line-geometry-query budgets in workflow YAML. Budgets
already live with the benchmark scenarios in
`Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift` and are printed by
the executable. A workflow budget copy would create two sources of truth.

### Decision 3 — Keep current budgets; treat a first-run hosted failure as evidence

This slice promotes the existing macOS-calibrated budgets rather than retuning
them up front. The standing budget-calibration rule asks for hosted Linux x86_64
evidence before trusting budgets; the one-shot PR-head run **is** that evidence,
recorded in the verification doc.

If the first hosted PR-head run fails because hosted Linux behavior does not fit
the existing budgets, implementation must **stop** and update this design with the
new hosted numbers, then re-derive Linux-appropriate budgets in
`LineGeometryQueryBenchmark.swift`. It must **not** hide the failure with
`continue-on-error`, a workflow-only threshold, or a silent budget widening. The
two `balanced_tree` scenarios are the ones to watch — not because they hold the
least multiplicative headroom (that is `uniform_1k` at ~1,900×), but because they
are the realistic O(log N)-offset path with the largest absolute latency
(~133–191 ns vs uniform's ~16–22 ns), where a hosted-Linux constant-factor slowdown
would surface first. Even so, the tighter balanced-tree scenario (~2,250×) would
have to regress by more than three orders of magnitude to breach budget.

### Decision 4 — Keep the host job order

The line-geometry-query gate sits immediately after the line-query gate:

1. `swift test`
2. synthetic benchmark gate
3. static variable-height benchmark gate
4. variable-height mutation benchmark gate
5. structural-mutation benchmark gate
6. bulk-structural-mutation benchmark gate
7. line-query benchmark gate
8. **line-geometry-query benchmark gate (new)**
9. memory-shape diagnostic
10. RSS memory observation
11. PR-only realistic relative observation

This keeps all seven blocking latency gates contiguous and fails before
lower-priority diagnostics if the geometry-bearing query path regresses. Placing it
directly after the line-query gate also buys differential diagnosis: because
`lineGeometryAt` composes over `lineAt`, a line-query **pass** with a
line-geometry-query **fail** localizes the regression to the geometry delta — the two
`offset(ofLine:)` probes, the box construction, and the fraction arithmetic — rather
than to `lineAt` itself.

### Decision 5 — Do not change required context names

The ruleset already requires `Host tests and benchmark gate`. Slice 32 makes that
job stricter but must not create or rename required contexts. The iOS and WASM
jobs remain unchanged.

### Decision 6 — Leave docs-only behavior unchanged

Docs-only PRs still complete the required contexts through the trusted lightweight
path and skip heavy Swift work. The line-geometry-query gate is part of the heavy
host path and runs whenever `docs_only_pr != 'true'`, matching every adjacent
gate. This slice's PR changes workflow YAML, so it is never docs-only and is fully
exercised by the heavy path in its own PR.

### Decision 7 — A one-line Swift command needs no shell override

Like the other gate steps, the line-geometry-query gate uses no pipes, `set -o
pipefail`, or shell-specific behavior. It stays a plain `run:` line and does not
need `shell: bash`. The important workflow property is the absence of
`continue-on-error: true` on this step.

## Implementation Architecture

### Workflow

Insert into the host job, between the line-query gate and the memory-shape
diagnostic:

```yaml
- name: Run line geometry query benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-geometry-query --gate
```

No other workflow step should need to move or change.

### Documentation

Update `AGENTS.md` in the CI section (the `Host tests and benchmark gate`
bullet):

- add `→ --line-geometry-query --gate (blocking)` to the host-job step sequence,
  after `--line-query --gate (blocking)` and before `--memory-shape`;
- extend the "fail the job on perf regression" sentence so it also names the
  line-geometry-query gate (e.g. "… bulk-structural-mutation, line-query, and
  line-geometry-query gates");
- keep memory diagnostics, RSS observation, realistic relative observation, iOS,
  WASM, docs-only shortcut, ruleset, and bypass caveat wording unchanged.

The command list already documents the local `--line-geometry-query --gate`
command; that local-invocation line stays consistent with its siblings.

### Verification Record

Create:

```text
docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md
```

The record should include exact commands, exit statuses, and representative
output lines.

Local verification should include at minimum:

```bash
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
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
asserting the new step exists, invokes `--line-geometry-query --gate`, is not
`continue-on-error`, carries the same `docs_only_pr` guard as its sibling gates
(Decision 6), sits in the required order (line-query → line-geometry-query →
memory-shape), and that the three required job context names are unchanged
(Decision 5). For example:

```bash
ruby -ryaml -e '
  wf = YAML.load_file(".github/workflows/swift-ci.yml")
  jobs = wf["jobs"]
  steps = jobs["host-tests-and-benchmark-gate"]["steps"]
  names = steps.map { |s| s["name"] }
  lgq = steps.find { |s| s["name"] == "Run line geometry query benchmark gate" }
  lq  = steps.find { |s| s["name"] == "Run line query benchmark gate" }
  raise "missing line-geometry-query gate step" unless lgq
  raise "missing line-query gate step" unless lq
  raise "gate not invoking --line-geometry-query --gate" unless lgq["run"].include?("--line-geometry-query --gate")
  raise "line-geometry-query gate must not be continue-on-error" if lgq["continue-on-error"]
  raise "line-geometry-query gate must share its siblings docs-only guard" unless lgq["if"] == lq["if"]
  i_lq  = names.index("Run line query benchmark gate")
  i_lgq = names.index("Run line geometry query benchmark gate")
  i_mem = names.index("Run memory shape diagnostic")
  raise "bad gate ordering" unless i_lq && i_lgq && i_mem && i_lq < i_lgq && i_lgq < i_mem
  required = ["Host tests and benchmark gate", "iOS cross-target compile", "WASM cross-target observation"]
  actual = jobs.values.map { |j| j["name"] }
  raise "required job context name(s) changed" unless required.all? { |n| actual.include?(n) }
  puts "workflow_assertions_ok"
'
```

Hosted verification should include:

- final PR-head Swift CI run ID;
- all three required jobs `success`;
- host job step `Run line geometry query benchmark gate` `success`, with its
  hosted Linux x86_64 `line_geometry_query` rows (all five scenarios) showing
  `gate=pass`, `budget_p95_ns`, and `budget_p99_ns` (the Linux budget-fit
  evidence);
- proof the line-geometry-query step is not `continue-on-error`;
- post-merge push run ID for the merge commit (this slice changes workflow YAML,
  so the merge is not docs-only and will not be skipped by `push.paths-ignore`).

To avoid the recurring evidence defect seen in earlier slices: record the PR-head
proof only in the post-merge follow-up where the final head SHA is stable, and
never describe a source-bearing PR's head as taking the docs-only shortcut (the
detector reads the full diff, which includes the YAML change here). Verify hosted
runs at the **step** level, not just the job conclusion (a green job can hide a
dead `continue-on-error` step).

## Acceptance Criteria

- `.github/workflows/swift-ci.yml` contains a `Run line geometry query benchmark
  gate` step that invokes `--line-geometry-query --gate`.
- The line-geometry-query step has no `continue-on-error: true`.
- The step is positioned after the line-query gate and before the memory-shape
  diagnostic.
- The three required job context names remain unchanged:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- No benchmark Swift source changes (no scenario, budget, or helper edit);
  `git diff --name-only` for the PR touches only `.github/workflows/swift-ci.yml`,
  `AGENTS.md`, and `docs/**`.
- `AGENTS.md` describes the line-geometry-query benchmark as a blocking host-job
  gate that fails the job on perf regression.
- Local line-geometry-query gate passes with `gate=pass` for all five scenarios;
  all six pre-existing latency gates and `swift test` still pass.
- Hosted PR-head CI runs the line-geometry-query gate step and succeeds, with
  recorded Linux p95/p99 for all five scenarios as budget-fit evidence.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Risks And Gaps

### Hosted Linux variance could exceed current budgets

The budgets have recorded macOS headroom, but hosted Linux x86_64 differs from
macOS arm64 and has never run this mode. Prior promotions saw hosted Linux up to
~1.4–1.6× slower/noisier than local; the line-geometry-query budgets' ~1,900×–5,400×
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

### Balanced-tree line-geometry queries carry inherited costs

This slice protects the current line-geometry-query path against regression; it
does not improve its asymptotics. `lineGeometryAt` composes over `lineAt` plus two
`offset(ofLine:)` probes, so the balanced-tree scenarios pay ~5 O(log N) descents
where a provider-native one-walk `(index, top, bottom)` hook would fold them to ~2
(Slice 31 review Option B), and `FenwickLineMetrics` (not exercised by this
benchmark) stays O(log²N). Those are constant-factor / inherited costs, explicitly
out of scope here.

### Bypass actors remain

The active `Main` ruleset still has a bypass-actor shape and the admin user can
bypass it. Slice 32 does not change repository bypass policy.

### WASM remains observational

The required `WASM cross-target observation` context stays green/required but
non-blocking when matching Swift SDKs are unavailable. This slice does not alter
that documented CI contract.

## Recommended Next Step

After this spec is approved, write the Slice 32 implementation plan. The plan
should be small and TDD-style: the most meaningful failing-first check is the
workflow-invariant assertion showing there is no blocking line-geometry-query gate
step before the YAML change, and a true blocking gate (with `--line-geometry-query
--gate`, without `continue-on-error`, ordered line-query → line-geometry-query →
memory-shape) after it. Because this slice touches no benchmark source, there is no
checksum-equality proof to carry — the verification leans on the workflow assertion
plus the hosted budget-fit run.
