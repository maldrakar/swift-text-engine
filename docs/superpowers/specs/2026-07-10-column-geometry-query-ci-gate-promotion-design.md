# Column-Geometry-Query CI Gate Promotion Design

Date: 2026-07-10

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 36 of SwiftTextEngine, following the Slice 35 post-slice review:

```text
docs/superpowers/reviews/2026-07-10-slice-35-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires regression
benchmarks to block merge when performance regresses
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
That requirement already holds for **eight** latency gates running blocking in
the hosted `Host tests and benchmark gate` job: synthetic, static
variable-height, variable-height-mutation, structural-mutation,
bulk-structural-mutation, line-query, line-geometry-query, and column-query. It
does **not** yet hold for the horizontal within-line **geometry** query path
introduced in Slice 35.

Slice 35 added the public stateless query
`ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:) -> ColumnGeometryQuery`
— the geometry-bearing companion to Slice 33's `columnAt`, which composes over
`columnAt` (validation / located index / clamp) and reads two
`columnOffset(inLine:column:)` probes to return the located cell's
`ColumnGeometry` box (index, left `x`, advance width), the within-cell
`fractionInColumn`, and `columnAt`'s clamp flag — the exact horizontal mirror of
Slice 31's vertical `lineGeometryAt`. Like every functional capability slice, it
shipped a **local-only** benchmark gate:

- `--column-geometry-query` benchmark mode (output `column_geometry_query`) over
  **five** scenarios: `uniform_1k` / `uniform_100k` / `uniform_1m` on the
  `UniformColumnMetrics` provider (in the core; O(1) `columnOffset`, but its
  located-cell search still uses the generic O(log M) binary-search fallback —
  no native `columnIndex` override — so the overall uniform query is O(log M),
  not O(1), until a future closed-form override, Slice 35 review Option D), and
  `prefixsum_100k` / `prefixsum_1m` on the `PrefixSumColumnMetrics` reference
  provider (the realistic proportional-advance path, O(1) `columnOffset` from a
  per-line prefix-sum array held outside the core-memory invariant, located cell
  via the same generic binary-search default);
- a local `--column-geometry-query --gate` with budgets deliberately identical
  to the `--column-query` / `--line-geometry-query` shape, passing locally with
  very large headroom (~1,580×–5,710×, per the Slice 35 verification).

The Slice 35 post-slice review recommends Slice 36 as:

```text
Option A: Promote --column-geometry-query --gate to a blocking hosted CI gate
```

and lays out Options B/D/E (`pointAt(x:y:)` 2D composite — now unblocked with
both axes geometry-bearing; horizontal native / closed-form column inverse; WASM
blocking / Linux budget re-baseline) as later directions. The user selected
**Option A**, the **one-shot blocking** rollout, to retire the CI-promotion debt
Slice 35 re-opened before any follow-on builds against the horizontal geometry
latency contract.

### Relationship to the prior promotions (Slices 15, 21, 24, 26, 28, 32, 34)

This slice is the **eighth** benchmark-gate promotion in the established cadence.
The prior seven were Slice 15 (variable-height), Slice 21
(variable-height-mutation), Slice 24 (structural-mutation), Slice 26
(bulk-structural-mutation), Slice 28 (line-query), Slice 32 (line-geometry-query),
and Slice 34 (column-query). They split into two shapes:

- **Flip an existing hosted observation step to blocking** — Slices 15 and 21.
  Those benchmarks already ran in hosted CI as non-blocking observation steps, so
  promotion had prior hosted Linux evidence in hand.
- **Promote a benchmark that has never run in hosted CI** — Slices 24, 26, 28,
  32, and 34. There was no observation step to flip and no prior hosted Linux
  x86_64 evidence; budgets were macOS-calibrated only, and the PR-head hosted run
  produced the Linux evidence.

Slice 36 is the second shape — the direct analog of Slices 24, 26, 28, 32, and
34, and the **exact horizontal twin of Slice 32** (which promoted the vertical
`line-geometry-query` gate). Slice 35 kept `--column-geometry-query --gate`
local-only, so the column-geometry-query benchmark has **never run in hosted CI**:
there is no observation step to flip and no prior hosted Linux x86_64 evidence,
its budgets are macOS-calibrated only, and the one-shot PR-head run is what
produces the Linux budget-fit evidence.

Like Slices 28, 32, and 34, this is a **very low-risk** promotion.
`columnGeometryAt` composes over the already-hosted-gated `columnAt` plus two O(1)
`columnOffset` probes, and the `--column-geometry-query` benchmark reuses the
`--column-query` / `--line-geometry-query` budget shape verbatim; its local
headroom is generous — ~1,580×–5,710× (the Slice 35 verification's per-scenario
figures). The one-shot rollout does not lean on a thin margin, and Decision 3
(stop-and-retune on a failing hosted run) is the standing safety net.

### Current host CI shape (relevant excerpt)

```yaml
- name: Run column query benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-query --gate

- name: Run memory shape diagnostic
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

There is no `--column-geometry-query` step anywhere in the workflow today.

### Current column-geometry-query budgets and local evidence

The benchmark mode already carries executable-owned budgets
(`Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift`), deliberately
identical to the `--column-query` / `--line-query` / `--line-geometry-query`
budgets. The Slice 35 verification and review both reran the gate on the merged
tree, matched the deterministic per-scenario checksums byte-for-byte, and stayed
passing. The budgets are:

| Scenario | Provider | Budget p95 ns | Budget p99 ns |
| --- | --- | ---: | ---: |
| uniform_1k     | `UniformColumnMetrics` (core)      | 30,000  | 60,000  |
| uniform_100k   | `UniformColumnMetrics` (core)      | 60,000  | 120,000 |
| uniform_1m     | `UniformColumnMetrics` (core)      | 120,000 | 240,000 |
| prefixsum_100k | `PrefixSumColumnMetrics` (reference) | 60,000  | 120,000 |
| prefixsum_1m   | `PrefixSumColumnMetrics` (reference) | 120,000 | 240,000 |

Recorded Slice 35 local observation (macOS arm64) with **per-scenario** headroom
(budget p95 ÷ observed p95):

| Scenario | Observed p95 ns | Headroom | Checksum |
| --- | ---: | ---: | ---: |
| uniform_1k     | 16 | ~1,875× | `160641440000` |
| uniform_100k   | 20 | ~3,000× | `267505512960` |
| uniform_1m     | 21 | ~5,714× | `799841600000` |
| prefixsum_100k | 38 | ~1,579× | `223985600000` |
| prefixsum_1m   | 51 | ~2,353× | `839521520640` |

The observed p95/p99 timings are **approximate and non-reproducible** — timing
varies run to run and is not bit-identical; the deterministic paper-trail anchor
is the per-scenario checksum set plus the executable-printed `budget_p95_ns` /
`budget_p99_ns`, not timing rows. The five deterministic per-scenario checksums
recorded in the Slice 35 verification (and reproduced in that slice's review) are
`160641440000`, `267505512960`, `799841600000`, `223985600000`, `839521520640`.

## Problem

The column-geometry-query path is proven locally but its **latency** is invisible
to hosted CI. Today the host job stays green regardless of `columnGeometryAt`
runtime, because the benchmark is not invoked in the workflow at all.

The hosted job already runs `swift test`, so the correctness and
algorithmic-shape guarantees are enforced: `ColumnGeometryAtTests` covers the
half-open boundary, clamp, `.empty`, and the structural uniform oracle;
`ColumnGeometryAtQueryCountTests` deterministically bounds the `columnOffset`
probe count and proves the query dispatches to the native `columnIndex` search
then takes exactly two ordered geometry probes (the event-log test pins the exact
`[.offset(0,0), .offset(0,count), .native(0,x), .offset(0,i), .offset(0,i+1)]`
dispatch order and proves the blank / clamp / non-finite paths never search); and
`ColumnGeometryAtEquivalenceTests` checks `PrefixSumColumnMetrics` against its own
`columnOffset`-derived box + fraction. An accidental linear scan, a lost native
dispatch, a boundary/clamp change, or a wrong fraction would fail those unit tests
and already block merge.

What the unit tests do **not** catch is a runtime budget/latency regression — a
constant-factor slowdown, an added allocation, or a cache-unfriendly change that
preserves query count and correctness but degrades wall-clock p95/p99. That is
the enforcement gap:

- runtime latency regressions in `ViewportVirtualizer.columnGeometryAt` — and in
  the `columnAt` index dispatch and provider `columnOffset` probes it composes
  over — are not blocking;
- the brief's "benchmark gates block merge" principle is not yet true for the
  horizontal within-line geometry query path.

With required checks, docs-only shortcut trust, and the other eight latency gates
already hardened, making the column-geometry-query benchmark fail the same
required host job is the natural next governance step, and it closes the single
regression-protection gap Slice 35 opened (its CI-promotion debt).

## Scope

Slice 36 introduces the column-geometry-query benchmark to the hosted host-tests
job as a **blocking gate** in a single PR.

Expected implementation surface:

- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/verification/2026-07-10-column-geometry-query-ci-gate-promotion.md`

Expected paper trail:

- this design spec;
- a task-by-task plan after this spec is approved;
- a verification record with local and hosted evidence;
- a post-slice review after implementation and merge.

The slice changes only the workflow YAML and docs. It must not touch
`TextEngineCore`, `TextEngineReferenceProviders`, any benchmark Swift source
(scenarios, budgets, or helpers), or any other benchmark mode.

### No bundled hardening

Like Slices 28, 32, and 34 — and unlike Slice 26, which folded in the
`deterministicIndex` overflow hardening the Slice 25 review had flagged — the
Slice 35 review found **no P0/P1/P2 and no actionable P3 items** in the promoted
benchmark. `ColumnGeometryQueryBenchmark.swift` is modeled on
`ColumnQueryBenchmark.swift`: it builds its sample `x` values from the shared
`deterministicScrollOffset` helper — whose `(sample * 37) % 1_000` is a plain,
bounded signed multiply returning a `Double` offset, never an array index — and
does **not** call the overflow-hardened `deterministicIndex`. It therefore
derives no array index from a wrapping signed multiply and carries no analogous
crash class. This slice promotes the existing benchmark **unchanged** and touches
no benchmark source.

The one open provider-doc-hygiene P3 carried since Slice 25 (the bulk-edits spec
names the join primitive `join(_:_:)` while the implementation ships
`join3`/`join2`) is unrelated to this slice; Slice 36 touches no provider source
or the bulk-edits spec, so it is correctly **not** this slice's home and stays a
tracked open item.

## Goals

- Add a `--column-geometry-query --gate` step to the hosted `Host tests and
  benchmark gate` job.
- Make the step blocking: no `continue-on-error: true`.
- Place the step immediately after `Run column query benchmark gate` and before
  `Run memory shape diagnostic`, keeping all **nine** blocking latency gates
  contiguous and failing before lower-priority diagnostics.
- Keep benchmark budgets in `Sources/ViewportBenchmarks`, not duplicated in
  workflow YAML.
- Keep the current macOS-calibrated budgets for this promotion, and use the
  PR-head hosted run as the Linux x86_64 evidence that confirms they fit.
- Keep the three required job contexts unchanged.
- Keep trusted docs-only PR behavior unchanged.
- Update `AGENTS.md` so the CI section lists the column-geometry-query gate as
  blocking in hosted CI (the ninth blocking latency gate) and the architecture
  paragraph no longer calls `--column-geometry-query` a local (not-yet-CI) gate.
- Record local and hosted proof that column-geometry-query benchmark output
  includes `budget_p95_ns`, `budget_p99_ns`, and `gate=pass` for all five
  scenarios, and that the hosted step is not `continue-on-error`.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` changes.
- No `columnGeometryAt` / `columnAt` / `LineHorizontalMetricsSource` API changes.
- No benchmark workload redesign, scenario change, budget retune, or benchmark
  Swift edit of any kind unless the first hosted run forces a spec revisit
  (Decision 3).
- No provider-native / closed-form column inverse (Slice 35 review Option D) — a
  future slice.
- No 2D `pointAt(x:y:)` composite (Option B).
- No provider-native one-walk `(index, left, right)` geometry hook (the
  constant-factor probe trim) — a future slice.
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

Rationale: the budgets carry ~1,580×–5,710× macOS per-scenario headroom — a
margin comparable to its structural twin `--line-geometry-query` at its Slice 32
promotion (~1,900×–5,400×) and to the `--column-query` sibling at Slice 34, and
over two orders of magnitude above the tightest gate the series has promoted (the
bulk gate at ~6.7×). The PR-head CI run executes the step on hosted Linux x86_64
and prints `p95_ns` / `p99_ns` / budget fields whether or not it passes, so a
single blocking step both enforces and produces the hosted evidence. The most
comparable prior promotions — Slices 24, 26, 28, 32, and 34, which like this
slice promoted a never-hosted benchmark straight to blocking — all went one-shot
and passed; Slice 32 (this slice's structural twin) did so at comparable headroom.
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
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-geometry-query --gate
```

Rejected alternative: encode column-geometry-query budgets in workflow YAML.
Budgets already live with the benchmark scenarios in
`Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift` and are printed by
the executable. A workflow budget copy would create two sources of truth.

### Decision 3 — Keep current budgets; treat a first-run hosted failure as evidence

This slice promotes the existing macOS-calibrated budgets rather than retuning
them up front. The standing budget-calibration rule asks for hosted Linux x86_64
evidence before trusting budgets; the one-shot PR-head run **is** that evidence,
recorded in the verification doc.

If the first hosted PR-head run fails because hosted Linux behavior does not fit
the existing budgets, implementation must **stop** and update this design with the
new hosted numbers, then re-derive Linux-appropriate budgets in
`ColumnGeometryQueryBenchmark.swift`. It must **not** hide the failure with
`continue-on-error`, a workflow-only threshold, or a silent budget widening.

Two scenarios are worth watching, and Slice 35's per-scenario table lets this spec
name them precisely rather than by narrative:

- **`prefixsum_100k` holds the least multiplicative headroom** (~1,579×) — a
  purely-multiplicative hosted-Linux slowdown would breach budget here first.
- **`prefixsum_1m` carries the largest absolute latency** (51 ns p95) and is the
  realistic proportional-advance path at the largest cell count (1,000,000), so a
  hosted-Linux constant-factor slowdown that scales with cell count would surface
  there.

Even the tighter of the two would have to regress by three orders of magnitude to
breach budget. The verification record must tabulate per-scenario observed p95 and
headroom (budget p95 ÷ observed p95) for all five scenarios, both locally and on
the hosted PR-head run, so both watch scenarios are grounded in numbers and any
future Linux re-baseline (Option E) starts from a recorded per-scenario baseline.

### Decision 4 — Keep the host job order

The column-geometry-query gate sits immediately after the column-query gate:

1. `swift test`
2. synthetic benchmark gate
3. static variable-height benchmark gate
4. variable-height mutation benchmark gate
5. structural-mutation benchmark gate
6. bulk-structural-mutation benchmark gate
7. line-query benchmark gate
8. line-geometry-query benchmark gate
9. column-query benchmark gate
10. **column-geometry-query benchmark gate (new)**
11. memory-shape diagnostic
12. RSS memory observation
13. PR-only realistic relative observation

This keeps all nine blocking latency gates contiguous and fails before
lower-priority diagnostics if the horizontal geometry query path regresses.
Placing it directly after the `--column-query` gate also buys differential
diagnosis: because `columnGeometryAt` composes over `columnAt`, a **column-query
pass with a column-geometry-query fail** localizes the regression to
`columnGeometryAt`'s own delta — its two `columnOffset` geometry probes and the
`fractionInColumn` arithmetic — rather than to the shared `columnAt` index
dispatch, and a **both-fail** points at the shared `columnAt` / provider path.

### Decision 5 — Do not change required context names

The ruleset already requires `Host tests and benchmark gate`. Slice 36 makes that
job stricter but must not create or rename required contexts. The iOS and WASM
jobs remain unchanged.

### Decision 6 — Leave docs-only behavior unchanged

Docs-only PRs still complete the required contexts through the trusted
lightweight path and skip heavy Swift work. The column-geometry-query gate is part
of the heavy host path and runs whenever `docs_only_pr != 'true'`, matching every
adjacent gate. This slice's PR changes workflow YAML — and the docs-only detector
explicitly rejects `.github/workflows/**` before applying the Markdown allow rule
— so this PR is never docs-only and is fully exercised by the heavy path in its
own PR.

### Decision 7 — A one-line Swift command needs no shell override

Like the other gate steps, the column-geometry-query gate uses no pipes, `set -o
pipefail`, or shell-specific behavior. It stays a plain `run:` line and does not
need `shell: bash`. The important workflow property is the absence of
`continue-on-error: true` on this step.

## Implementation Architecture

### Workflow

Insert into the host job, between the column-query gate and the memory-shape
diagnostic:

```yaml
- name: Run column geometry query benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-geometry-query --gate
```

No other workflow step should need to move or change.

### Documentation

Update `AGENTS.md` in two places:

- **Architecture paragraph** — the `columnGeometryAt` description currently ends
  "… `--column-geometry-query --gate` is **local (not-yet-CI)**." Change that to
  describe `--column-geometry-query` as its blocking host-job gate (dropping
  "local (not-yet-CI)"), matching how the adjacent `columnAt` sentence already
  reads ("`--column-query` is its blocking host-job CI gate").
- **CI section** (the `Host tests and benchmark gate` bullet):
  - add `→ --column-geometry-query --gate (blocking)` to the host-job step
    sequence, after `--column-query --gate (blocking)` and before `--memory-shape`;
  - extend the "fail the job on perf regression" sentence so it also names the
    column-geometry-query gate (e.g. "… line-geometry-query, column-query, and
    column-geometry-query gates");
  - keep memory diagnostics, RSS observation, realistic relative observation, iOS,
    WASM, docs-only shortcut, ruleset, and bypass caveat wording unchanged.

The command list already documents the local `--column-geometry-query --gate`
command; that local-invocation line stays consistent with its siblings.

### Verification Record

Create:

```text
docs/superpowers/verification/2026-07-10-column-geometry-query-ci-gate-promotion.md
```

The record should include exact commands, exit statuses, and representative
output lines.

Local verification should include at minimum:

```bash
swift run -c release ViewportBenchmarks -- --column-geometry-query --gate
swift run -c release ViewportBenchmarks -- --column-query --gate
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

Because this slice's central Non-Goal is *no benchmark source change*, the local
`--column-geometry-query --gate` run is also the cheapest possible proof of that
Non-Goal: record that all five per-scenario `column_geometry_query` checksums are
**byte-identical** to the values Slice 35 established (`160641440000`,
`267505512960`, `799841600000`, `223985600000`, `839521520640`). A checksum drift
would mean the benchmark workload changed — which this slice forbids — so the
equality is a free integrity check even though no *new* checksum is being
established. Capture the observed per-scenario p95/p99 as well, so the headroom
this spec cites is grounded in this slice's own numbers, not only carried from the
Slice 35 record.

Plus a **workflow-invariant assertion** that goes beyond a bare YAML parse —
asserting the new step exists, invokes `--column-geometry-query --gate`, is not
`continue-on-error`, carries the same `docs_only_pr` guard as its sibling gates
(Decision 6), sits in the required order (column-query → column-geometry-query →
memory-shape), and that the three required job context names are unchanged
(Decision 5). For example:

```bash
ruby -ryaml -e '
  wf = YAML.load_file(".github/workflows/swift-ci.yml")
  jobs = wf["jobs"]
  steps = jobs["host-tests-and-benchmark-gate"]["steps"]
  names = steps.map { |s| s["name"] }
  cgq = steps.find { |s| s["name"] == "Run column geometry query benchmark gate" }
  cq  = steps.find { |s| s["name"] == "Run column query benchmark gate" }
  raise "missing column-geometry-query gate step" unless cgq
  raise "missing column-query gate step" unless cq
  raise "gate not invoking --column-geometry-query --gate" unless cgq["run"].include?("--column-geometry-query --gate")
  raise "column-geometry-query gate must not be continue-on-error" if cgq["continue-on-error"]
  raise "column-geometry-query gate must share its siblings docs-only guard" unless cgq["if"] == cq["if"]
  i_cq  = names.index("Run column query benchmark gate")
  i_cgq = names.index("Run column geometry query benchmark gate")
  i_mem = names.index("Run memory shape diagnostic")
  raise "bad gate ordering" unless i_cq && i_cgq && i_mem && i_cq < i_cgq && i_cgq < i_mem
  required = ["Host tests and benchmark gate", "iOS cross-target compile", "WASM cross-target observation"]
  actual = jobs.values.map { |j| j["name"] }
  raise "required job context name(s) changed" unless required.all? { |n| actual.include?(n) }
  puts "workflow_assertions_ok"
'
```

Hosted verification should include:

- final PR-head Swift CI run ID;
- all three required jobs `success`;
- host job step `Run column geometry query benchmark gate` `success`, with its
  hosted Linux x86_64 `column_geometry_query` rows (all five scenarios) showing
  `gate=pass`, `budget_p95_ns`, and `budget_p99_ns` (the Linux budget-fit
  evidence);
- a per-scenario hosted headroom line for all five scenarios (observed `p95_ns` /
  `p99_ns` and headroom = budget ÷ observed), so the Linux budget-fit is recorded
  quantitatively and both watch scenarios (`prefixsum_100k` least multiplicative
  headroom, `prefixsum_1m` largest absolute latency — Decision 3) have concrete
  hosted numbers;
- proof the column-geometry-query step is not `continue-on-error`;
- post-merge push run ID for the merge commit (this slice changes workflow YAML,
  so the merge is not docs-only and will not be skipped by `push.paths-ignore`).

To avoid the recurring evidence defect seen in earlier slices: record the PR-head
proof only in the post-merge follow-up where the final head SHA is stable, and
never describe a source-bearing PR's head as taking the docs-only shortcut (the
detector reads the full diff, which includes the YAML change here, and rejects
`.github/workflows/**` outright). Verify hosted runs at the **step** level, not
just the job conclusion (a green job can hide a dead `continue-on-error` step).

## Acceptance Criteria

- `.github/workflows/swift-ci.yml` contains a `Run column geometry query benchmark
  gate` step that invokes `--column-geometry-query --gate`.
- The column-geometry-query step has no `continue-on-error: true`.
- The step is positioned after the column-query gate and before the memory-shape
  diagnostic.
- The three required job context names remain unchanged:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- No benchmark Swift source changes (no scenario, budget, or helper edit);
  `git diff --name-only` for the PR touches only `.github/workflows/swift-ci.yml`,
  `AGENTS.md`, and `docs/**`.
- `AGENTS.md` describes the column-geometry-query benchmark as a blocking host-job
  gate that fails the job on perf regression, and no longer calls
  `--column-geometry-query` a local (not-yet-CI) gate.
- Local column-geometry-query gate passes with `gate=pass` for all five
  scenarios; all eight pre-existing latency gates and `swift test` still pass.
- Hosted PR-head CI runs the column-geometry-query gate step and succeeds, with
  recorded Linux p95/p99 and per-scenario headroom (budget ÷ observed) for all
  five scenarios as budget-fit evidence.
- Local verification records that the five per-scenario `column_geometry_query`
  checksums are byte-identical to the Slice 35 values, proving the benchmark
  workload is unchanged.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Risks And Gaps

### Hosted Linux variance could exceed current budgets

The budgets have recorded macOS headroom, but hosted Linux x86_64 differs from
macOS arm64 and has never run this mode. Prior promotions saw hosted Linux up to
~1.4–1.6× slower/noisier than local; the column-geometry-query budgets'
~1,580×–5,710× headroom absorbs that with three orders of magnitude to spare, but
it is unproven until the PR-head run. If the promotion PR fails because the
benchmark exceeds budget, treat that as evidence and revisit this spec (Decision
3). Do not hide the failure with `continue-on-error` or a workflow-only threshold.

### Budgets remain macOS-derived after this slice

Promotion confirms the macOS budgets fit hosted Linux but does not re-derive
Linux-native budgets. That matches the standing project posture for the other
gates (budgets macOS-calibrated unless hosted Linux evidence justifies a retune)
and is acceptable; a dedicated Linux budget re-baseline remains possible future
work (Option E).

### Column-geometry queries carry inherited fallback costs

This slice protects the current column-geometry-query path against regression; it
does not improve its asymptotics. `columnGeometryAt` composes over `columnAt`, and
both shipped providers rely on the generic `binarySearchColumnIndex` default, so
the uniform case pays an O(log M) search where an exact closed form would be O(1),
and prefix-sum pays O(log M) — the horizontal analog of the vertical
fallback-bound providers (Slice 35 review Option D). The two extra `columnOffset`
geometry probes are a constant factor a provider-native one-walk hook could trim.
Those are constant-factor / inherited costs, explicitly out of scope here.

### Bypass actors remain

The active `Main` ruleset still has a bypass-actor shape and the admin user can
bypass it. Slice 36 does not change repository bypass policy.

### WASM remains observational

The required `WASM cross-target observation` context stays green/required but
non-blocking when matching Swift SDKs are unavailable. This slice does not alter
that documented CI contract.

## Recommended Next Step

After this spec is approved, write the Slice 36 implementation plan. The plan
should be small and TDD-style: the most meaningful failing-first check is the
workflow-invariant assertion showing there is no blocking column-geometry-query
gate step before the YAML change, and a true blocking gate (with
`--column-geometry-query --gate`, without `continue-on-error`, ordered
column-query → column-geometry-query → memory-shape) after it. Because this slice
touches no benchmark source, there is no *new* checksum to establish — but the
verification should still confirm the five per-scenario checksums are
byte-identical to the Slice 35 values as a free "benchmark unchanged" integrity
check, and otherwise leans on the workflow assertion plus the hosted per-scenario
budget-fit run.

After Slice 36 closes this functional → promotion pair, **both** axes are
CI-protected and geometry-bearing, and the project reaches the crossroads the
Slice 35 review surfaced: the newly-unblocked 2D `pointAt(x:y:)` hit-test (Option
B, the natural lean given the user's sustained steer toward editing affordances),
the horizontal native / closed-form column inverse (Option D), or standing infra
(Option E) — a product call for the Slice 37 direction, kept in its own slice per
the project's functional-vs-CI separation convention.
