# AGENTS.md — SwiftTextEngine

Operational guide for AI agents working in this repo. Load this every session.
It captures the durable, non-obvious facts; it does **not** restate code, file
structure, or git history (read those directly).

## What this is

A **headless** text-rendering engine core. `TextEngineCore` computes layout
geometry and virtualizes the visible viewport, staying independent of any UI
framework. The document itself lives **outside** the core, behind a
provider/source abstraction. There is no rendering, shaping, rasterization, or
UI integration here — only the layout/virtualization math.

Source of truth for intent: `docs/initial-project-brief.md` (in Russian).

## Hard constraints — never violate without explicit sign-off

These come from the brief and are enforced by CI, helper scripts, and/or
per-slice verification. Treat them as invariants, not preferences:

1. **No Foundation in `Sources/TextEngineCore`.** The Foundation-free scan
   (`rg -n "Foundation" Sources/TextEngineCore` → must be empty) is part of
   every slice's verification. The public API must not expose Foundation types.
2. **Swift Embedded compatible.** Avoid APIs that don't survive Embedded Swift.
   Anything doubtful must be flagged as needing compile verification.
3. **Zero-dependency.** No third-party packages in the core. Adding any
   dependency is a separate, explicitly-approved decision.
4. **Compiles for iOS and WASM with no source changes.** iOS device/simulator
   are blocking in CI; WASM/embedded WASM are currently proven locally and
   observed in CI only when a matching Swift SDK is available.
5. **Core-owned memory must not grow linearly with document size.** Strict
   virtualization: compute only for the visible viewport + overscan/buffer.
   `--memory-shape` asserts this invariant.

## Architecture in one paragraph

`ViewportVirtualizer.compute(...)` is **stateless** and returns a
`ViewportComputation` — `.success(VirtualRange)` or `.failure(error)` after
up-front input validation, where `VirtualRange` is the visible + buffered range.
Both paths are overloads of `ViewportVirtualizer.compute` (the variable overload
lives in `VariableViewportVirtualizer.swift` as an extension). The fixed-height
path takes a `ViewportInput`; the
variable-height path takes a `VariableViewportInput` + a `LineMetricsSource`
(provider supplies `offset(ofLine:)`, the cumulative top y). Variable compute is
**O(log N)** queries / **O(1)** core memory: its visible-start and visible-end
searches dispatch to provider-native prefix-search hooks: visible start uses
`lineIndex(containingOffset:)`, the same containing-offset hook `lineAt` uses,
and visible end uses
`firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`. A balanced-tree provider
answers each compute boundary search in one O(log N) descent, while other
providers use the generic binary-search fallback over offsets; the geometry
cursors stream per-line `LineGeometry` over the buffer range in O(buffer). The
variable path provably equals the fixed path for uniform metrics (equivalence
oracle test) — keep it that way.
`ViewportVirtualizer.lineAt(y:metrics:)` is the inverse query - y -> line - over
the same `LineMetricsSource`, O(1) core memory, using the shared
`lineIndex(containingOffset:)` provider-native hook when available and the
generic O(log N) binary-search fallback otherwise; out-of-range `y` clamps with
a `LineLocation.clamp` flag.
`ViewportVirtualizer.lineGeometryAt(y:metrics:)` is the geometry-bearing companion:
it composes over `lineAt`, returning the located line's `LineGeometry` box (top y +
height) plus the within-line `fractionInLine` and the same clamp flag, adding only a
constant number of `offset(ofLine:)` probes (O(1) core memory), so its per-provider
cost class equals `lineAt`'s.
`ViewportVirtualizer.columnAt(x:inLine:metrics:)` opens the horizontal axis: the
within-line inverse query — x -> cell — over a **separate**
`LineHorizontalMetricsSource` (provider supplies `columnCount(inLine:)` and the
cumulative `columnOffset(inLine:column:)`), O(log M) queries / O(1) core memory via
the shared `columnIndex(containingOffset:inLine:)` hook (binary-search default,
provider-overridable), cell model with half-open spans in **visual order**;
out-of-range `x` clamps with a `ColumnLocation.clamp`
(`.clampedToLeft`/`.clampedToRight`) flag and a blank line is `.empty`. `inLine` is a
precondition (the source carries no `lineCount`). Its two providers are
`UniformColumnMetrics` (in the core, beside `UniformLineMetrics`) and
`PrefixSumColumnMetrics` (reference providers); `--column-query` is its blocking
host-job CI gate.
`ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:)` is the geometry-bearing
companion to `columnAt`: it composes over `columnAt`, returning the located cell's
`ColumnGeometry` box (left `x` + advance `width`) plus the within-cell
`fractionInColumn` and the same clamp flag, adding only a constant number of
`columnOffset(inLine:column:)` probes (O(1) core memory), so its per-provider cost
class equals `columnAt`'s; caret snapping stays a caller concern.
`--column-geometry-query` is its blocking host-job CI gate.
`ViewportVirtualizer.pointAt(x:y:lineMetrics:columnMetrics:)` is the first two-axis
composite: it maps a single point to `(line, cell)` by composing `lineAt` over a
`LineMetricsSource` with `columnAt` over a `LineHorizontalMetricsSource` (vertical
runs first and feeds the located line index to the horizontal query), returning a
nested `PointQuery` — `.point(PointLocation)` carrying the located `line` plus a
`ColumnResolution` (`.cell`/`.blankLine`), `.empty` for an empty document, or
`.failure`. It adds no new search: O(log N) + O(log M) queries / O(1) core memory,
both clamp flags preserved. `--point-query --gate` is its blocking host-job CI
gate.
`ViewportVirtualizer.pointGeometryAt(x:y:lineMetrics:columnMetrics:)` is its
geometry-bearing companion: it composes `lineGeometryAt` with `columnGeometryAt`,
returning both axes' boxes, within-box fractions, and clamp flags in a nested
`PointGeometryQuery` (`.geometry(PointGeometryLocation)` carrying a
`LineGeometryLocation` plus a `ColumnGeometryResolution` — `.cell`/`.blankLine`),
adding no search and no arithmetic, only a constant number of probes (up to four on
a located cell, fewer on a blank line or a failure path), so its cost class equals
`pointAt`'s. Caret snapping stays a caller concern.
`--point-geometry-query --gate` is its blocking host-job CI gate (the eleventh).

## Package layout

- `Sources/TextEngineCore` — the library. Pure, headless, Foundation-free.
- `Sources/TextEngineReferenceProviders` — Foundation-free reference provider
  library. Reference providers live outside the core. It is a supported portable
  product: the hosted cross-target helper compiles it for iOS (blocking) and
  WASM (observational) alongside `TextEngineCore`.
- `Sources/ViewportBenchmarks` — executable. Benchmarks, gates, and diagnostics
  live here, NOT in the core.
- `Tests/TextEngineCoreTests` — XCTest only. (`swift test` also prints a
  "0 tests in 0 suites" line for the empty Swift Testing harness — not a failure.)
- `Tests/ViewportBenchmarksTests` — the benchmark target's first test target,
  holding five files.
  `GateLogicTests.swift` unit-tests the gate pass/fail logic itself (band
  boundaries, `budget_exceeded` vs `budget_stale`) against synthetic
  `BenchmarkSummary` values, independent of any hosted timing.
  `GateFloorTests.swift` is the other half: it reads the committed corpus and holds
  **every** gated scenario to `3x the windowed (most-recent N=20) max` on both
  statistics — the half of the band the runtime gate cannot check (see
  `## Gate budgets`). It also owns `everyGatedBudget()`, the **single registry** of
  gated scenarios that both halves of the band iterate. Which modes `--gate`
  accepts is the exhaustive `BenchmarkMode.isGateable` switch (never a deny-list —
  that makes a new mode gateable by default), and a test pins the two to each
  other: a gateable mode with no scenarios registered fails, and so does the
  reverse. It also carries `testWindowConstantMatchesDeriveScript`, pinning its
  `windowSize` constant to `derive-gate-budgets.sh`'s `WINDOW=` so the two windows
  cannot drift apart.
  `WorkflowShapeTests.swift` is the third guard: it reads
  `.github/workflows/swift-ci.yml` and pins the point-geometry-query gate step's
  shape — exactly one step carries the flag, its `run:` payload **equals** the
  expected gated command, it is not `continue-on-error`, it carries the docs-only
  guard, it is named `Run point geometry query benchmark gate`, and it sits
  between the point-query gate and the memory-shape diagnostic. Equality rather
  than a token probe: a step-level count cannot see a second invocation or a
  trailing `|| true` inside one step's payload, and both disarm the gate. There is
  no YAML parser in reach (the package is zero-dependency and Foundation ships
  none), so it hand-rolls a narrow reader and compares whitespace-separated
  **tokens**, never substrings — `--variable-height` is a prefix of
  `--variable-height-mutation`.
  `PointGeometryChecksumTests.swift` is the byte-identity checksum guard for
  `--point-geometry-query`: it pins the checksum to fold the full geometry (both
  boxes, both fractions), not just the indices, so a zeroed multiplier or a
  reversion to `--point-query`'s additive index-only fold cannot pass silently.
  `PointGeometryQueryOptionsTests.swift` is option-parsing coverage for the same
  flag: mode selection, `--gate` acceptance, and rejection when combined with an
  earlier mode flag.
- `Tests/TextEngineReferenceProvidersTests` — the only test target that can see both
  the core and the shipped providers, so cross-provider oracles (e.g. the
  `pointGeometryAt` 2x2 provider grid) belong here. `TextEngineCoreTests` depends on
  `TextEngineCore` alone and physically cannot reach `PrefixSum*`/`BalancedTree*`.
- `Package.swift` — `swift-tools-version: 6.0`. No `platforms:` declared, so iOS
  builds use the toolchain default deployment target.

## Commands

```bash
swift test                                                   # host unit tests
swift build -c release                                       # release build
swift run -c release ViewportBenchmarks -- --gate            # synthetic gate (blocking); expect gate=pass
swift run -c release ViewportBenchmarks -- --variable-height --gate   # variable-height blocking CI gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate   # mutate+recompute blocking CI gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate   # structural insert/delete blocking CI gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate   # bulk insert/delete-range blocking CI gate
swift run -c release ViewportBenchmarks -- --line-query --gate   # y->line position-query blocking CI gate
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate   # y->line+box+fraction blocking CI gate
swift run -c release ViewportBenchmarks -- --column-query --gate   # x->cell within-line position-query blocking CI gate
swift run -c release ViewportBenchmarks -- --column-geometry-query --gate   # x->cell+box+fraction within-line blocking CI gate
swift run -c release ViewportBenchmarks -- --point-query --gate   # (x,y)->(line,cell) 2D composite CI gate
swift run -c release ViewportBenchmarks -- --point-geometry-query --gate   # (x,y)->(line+box+fraction, cell+box+fraction) 2D geometry blocking CI gate
swift run -c release ViewportBenchmarks -- --memory-shape    # memory-shape invariant; expect invariant=pass
swift run -c release ViewportBenchmarks -- --memory-observation       # host RSS observation
swift run -c release ViewportBenchmarks -- --help            # all flags
./.github/scripts/harvest-gate-corpus.sh --limit 40 --corpus <corpus.tsv>   # hosted CI logs -> NEW corpus rows (append half)
./.github/scripts/harvest-gate-corpus.sh --self-test         # harvest selection-logic self-test (no network)
./.github/scripts/derive-gate-budgets.sh <corpus.tsv> <mode> # corpus -> budgets (re-derive half)
./.github/scripts/cross-target-compile.sh --self-test        # shell logic self-test (no toolchain)
./.github/scripts/cross-target-compile.sh                    # local iOS/WASM cross-compile
./.github/scripts/cross-target-compile.sh --targets ios      # iOS-only compile path
./.github/scripts/cross-target-compile.sh --targets wasm     # WASM-only observational path
```

Benchmark flags: `--range-only`, `--realistic-provider`, `--variable-height`,
`--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, `--column-geometry-query`, `--point-query`,
`--point-geometry-query`, `--memory-shape`,
`--memory-observation`, `--gate`. Only one mode
flag at a time. `--gate` is valid with the default pipeline, `--realistic-provider`,
`--variable-height`, `--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, `--column-geometry-query`, `--point-query`, and
`--point-geometry-query` modes; it is
**rejected** with
`--range-only`, `--memory-shape`,
`--memory-observation`.

Local WASM build (needs a matching Swift SDK installed):
`swift build --swift-sdk <id> --target TextEngineCore` for both `wasm` and
`wasm-embedded` ids from `swift sdk list`.

## CI (`.github/workflows/swift-ci.yml`)

Three jobs:

- **Host tests and benchmark gate** on `ubuntu-latest` with
  `swift:6.2.1-bookworm`: `swift test` → synthetic `--gate` (blocking)
  → `--variable-height --gate` (blocking) → `--variable-height-mutation --gate`
  (blocking) → `--structural-mutation --gate` (blocking)
  → `--bulk-structural-mutation --gate` (blocking) → `--line-query --gate`
  (blocking) → `--line-geometry-query --gate` (blocking)
  → `--column-query --gate` (blocking)
  → `--column-geometry-query --gate` (blocking) → `--point-query --gate`
  (blocking) → `--point-geometry-query --gate` (blocking) →
  `--memory-shape`
  → `--memory-observation` → realistic relative
  observation (PR-only,
  `continue-on-error`). Eleven blocking gates: synthetic, static variable-height,
  mutation variable-height, structural-mutation, bulk-structural-mutation,
  line-query, line-geometry-query, column-query, column-geometry-query,
  point-query, and point-geometry-query — all **fail the job on perf
  regression**.
  Budget calibration is not restated here — see `## Gate budgets` below. SwiftPM
  build artifacts use `/tmp/text-engine-host-build`, not workspace `.build`.
- **iOS cross-target compile** on `macos-latest`: iOS device + simulator are
  **blocking** for both `TextEngineCore` and `TextEngineReferenceProviders`, via
  `./.github/scripts/cross-target-compile.sh --targets ios`. This is the only
  hosted macOS job.
- **WASM cross-target observation** on `ubuntu-latest` with
  `swift:6.2.1-bookworm`: WASM + embedded WASM run for both `TextEngineCore` and
  `TextEngineReferenceProviders` via
  `./.github/scripts/cross-target-compile.sh --targets wasm`. They remain
  **observational**: the helper compiles them when a matching Swift SDK is
  installed/provisioned, otherwise records a non-blocking skip.

A `continue-on-error` step cannot be a gate. It swallows every non-zero exit —
budget misses, correctness failures, and crashes alike (the Slice 16 dead-step
trap). An observational benchmark step and a blocking correctness step must
therefore be separate steps until the budget itself goes blocking, at which
point one step is both.

Required-check policy: the public repository `maldrakar/swift-text-engine` has
an active default-branch ruleset named `Main` (id `17656807`) that requires the
three Swift CI job contexts for PRs targeting `main`: `Host tests and benchmark
gate`, `iOS cross-target compile`, and `WASM cross-target observation`.
Strict required-status-check policy is enabled, so PRs must be tested with the
latest base branch state.

Docs-only PRs still start Swift CI so those required job contexts are emitted,
but each required job materializes the PR base commit into
`$RUNNER_TEMP/trusted-ci` with `git worktree` and executes
`.github/scripts/detect-docs-only-pr.sh` from that trusted base tree. The
detector reads Git metadata from the PR workspace and compares the full
`BASE_SHA...HEAD_SHA` diff, but the code that decides `docs_only_pr` is not
loaded from the PR checkout. The detector rejects `.github/workflows/**` and
`.github/scripts/**` before applying the Markdown allow rule, so files in those
policy-sensitive directories are not docs-only regardless of extension. If the
full PR diff is only `docs/**` or Markdown files outside those policy-sensitive
directories, the job prints `mode=docs_only_pr ... result=success` and skips the
heavy Swift/test/compile work. Missing commits, diff failures, and empty runtime
diffs fail closed. Swift source, tests, package metadata, and all other non-doc
paths are not docs-only and must run the heavy path. Docs-only pushes to `main`
may still skip Swift CI through the `push.paths-ignore` rule because PR required
checks are the merge gate.

Bypass caveat: the ruleset preserves the existing bypass actor shape, and the
current admin user can bypass it. Required checks are configured and enforced
for normal PR flow, but bypass-capable actors can still override the ruleset.
Last verified: 2026-06-16 via `gh api`; see
`docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`.

## Gate budgets

A gate that cannot fail is not a gate. Every gated scenario's hosted headroom
(`headroom = budget / observed latency`) must stay inside a band; `--gate`
enforces the upper bound itself, failing with `gate=fail reason=budget_stale`
when it doesn't.

**The band**: floor 3x, ceilings `headroom_p95 <= 50x` and `headroom_p99 <=
100x`.

- The **floor** (3x) is what the runtime gate structurally *cannot* see: `--gate`
  compares a budget against **this** run's latency, so it catches a budget that is
  too loose but is blind to one sitting too close to the worst hosted sample — and
  that is the budget that goes red on a clean tree from runner noise alone.
  `Tests/ViewportBenchmarksTests/GateFloorTests.swift` is therefore what enforces it:
  it re-reads the corpus on every `swift test` and fails if any gated scenario's
  budget drops below `3 x max(hosted)` on **either** statistic, or if a gated
  scenario has no hosted evidence at all. The floor covers both statistics because
  the gate can fail on either one.
- The **p99 ceiling is exactly double the p95 ceiling, and is derived from it,
  not chosen independently**. The recipe guarantees `budget_p99 >= 2 *
  budget_p95` by construction, while observed p99 can equal observed p95 on a
  nanosecond-quantized clock — so any p99 ceiling below 100x would condemn
  budgets that are perfectly in-band on p95. Written as `2 * maxHeadroomP95`
  in `Sources/ViewportBenchmarks/BenchmarkModels.swift` so it cannot silently
  drift from the p95 ceiling.
- **Hosted Linux x86_64 is the calibration authority, not local macOS.**
  Hosted runs 2-3x slower (measured this slice: 2.1-2.7x), so it binds: a
  budget that holds there holds locally with room to spare, and the reverse is
  false.

**The recipe** is two committed scripts, not a table to copy — harvest fresh
hosted evidence, then re-derive from it:

```bash
# 1. append: pull hosted samples out of CI logs into the corpus.
#    --corpus makes the harvest IDEMPOTENT: it skips runs the corpus already
#    carries (before fetching their logs) and emits only new ones. Without it the
#    append re-adds every run inside the --limit window that was harvested before,
#    and a double-counted run double-weights itself in median() -- the term that
#    governs most budgets. Preview the decisions with --dry-run.
./.github/scripts/harvest-gate-corpus.sh --limit 40 \
  --corpus docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
  >> docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv

# 2. re-derive: <mode> may be spelled point-query or point_query; a mode with no
#    corpus rows is an error, not an empty success
./.github/scripts/derive-gate-budgets.sh \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv <mode>

budget_p95 = round_up_2sf(max(8 x median(hosted p95), 3 x max(hosted p95)))
budget_p99 = round_up_2sf(max(2 x budget_p95, 8 x median(p99), 3 x max(p99)))
```

**`hosted` in the recipe is a trailing window, not full corpus history.** It
means the most-recent **N=20 distinct runs, keyed on the integer run id** —
older rows still sit in the corpus but are not counted. The corpus stays
append-only/full-history; the window is applied only at read time. **Both**
consumers apply the identical window: `derive-gate-budgets.sh` and
`GateFloorTests` each hold `N=20`, pinned to one documented value by
`testWindowConstantMatchesDeriveScript` so they cannot silently drift apart.
Rationale: a `3x max` floor computed over an ever-growing append-only corpus
is a one-way ratchet — `max` can only rise, so a budget it governs could only
loosen, never tighten. The window makes it two-way: an old freak run ages out
and the budget it forced can tighten back down. What covers that freak's
*recurrence*, if it happens again, is the median-anchored floor terms (and,
on p99, the `2 x budget_p95` floor) — not the `3x`-max term, which is exactly
what just relaxed. p95 carries only the median term as backup, so it is the
thin axis to watch.

The 3x floor covers both statistics because the gate fails on either.

**A harvest re-derives every mode, not the one you came for.** Each hosted run
measures *all* the gated modes, so appending it raises `max(hosted)` — and can move
the median — for scenarios your slice never touched. Two consequences, both learned
the hard way in Slice 39:

- After harvesting, **sweep every mode** (`derive-gate-budgets.sh <corpus.tsv>` with
  no mode argument prints them all) and re-commit every budget the recipe now
  produces differently. Deriving only your own mode leaves the others silently
  *not reproducing* from the committed corpus, which breaks the "derived, never
  hand-typed" invariant for them until some unrelated slice happens to re-touch them.
- A post-harvest **`GateFloorTests` failure is `budget_stale`, not an engine
  regression**: the new samples raised a floor under an unchanged budget. Re-derive
  that scenario; do not go hunting for a slowdown in the core. (Budgets sitting
  within a few percent of their floor are normal — whenever the `3 x max` term
  governs, `round_up_2sf` lands just above it *by construction*.)

The corpus is **append-only**, and the run id is its dedup key — one run
legitimately contributes many rows (a `realistic_provider` run contributes 8), and
two of them can be byte-identical. So `sort -u` over the corpus is **not** a
substitute for `--corpus`: it would collapse two genuine repetitions that happened
to measure the same nanoseconds, and it reorders every row.

**Exactly one CI step may print a given mode's benchmark summary lines.** The
harvester reads every `p95_ns=` line in a run's log, so a second printing step
puts two rows per scenario into every future harvest of that run and
double-weights it in `median()` — the term that governs most budgets. This is a
different rule from the idempotent `--corpus` dedup above (which is about
harvesting the *same run* twice): here one run genuinely carries two rows per
scenario, and no dedup key can tell them apart.

The one time to harvest **without** `--corpus` is when the harvester learns to read
a *new line shape* (as it did for `realistic_provider`): previously-harvested runs
then hold rows the corpus never captured, so the corpus must be **rebuilt** from a
full sweep, not appended to.

`--realistic-provider` is the one gated mode CI never runs with `--gate` (the
PR-only observation step runs it bare and keeps the benchmark output in a temp
file), so its samples reach the corpus only through the
`mode=realistic_relative_observation` line, which the harvester knows how to read.
That is why it was the last budget still under the floor after the rest of the
suite had been re-derived. Every gated scenario now carries corpus rows, and
`GateFloorTests` fails if a new one ever doesn't.

**Never hand-type a budget.** Slices 27/31/33/35/37 shipped copy-pasted
"starter budgets" that ran 815x-3000x loose, and no gate could fail for five
slices as a result. Re-derive from fresh hosted evidence instead.

**When an optimization trips the ceiling, raise the budget — never the
ceiling.** A genuine speed-up (Slices 29/30 cut `lineAt` from O(log^2 N) to
O(log N)) or faster hardware will push headroom past the ceiling and turn a
gate red on a clean tree. That is the ceiling working as designed. Re-derive
that budget from fresh hosted evidence in the same PR that caused the shift.

**The two failure reasons are opposite instructions**, and the gate says
which one applies: `reason=budget_exceeded` means the code got slower — fix
the code. `reason=budget_stale` means the budget no longer reflects reality —
re-derive it.

## Development workflow ("slices")

Work ships in numbered **slices**, each a small vertical increment with a full
paper trail under `docs/superpowers/`:

- `specs/<date>-<slug>-design.md` — design/spec
- `plans/<date>-<slug>.md` — task-by-task TDD plan (checkbox steps)
- `verification/<date>-<slug>.md` — recorded commands + outputs + hosted run IDs
- `reviews/<date>-slice-N-post-slice-review.md` — post-slice review; ends by
  recommending the next slice

Lifecycle: **brainstorm → spec → plan → TDD implement → verification record →
post-slice review**. For implementing a plan, follow the superpowers
`executing-plans` / `subagent-driven-development` skills the plan references.

Conventions that matter:

- **TDD is the norm here.** Plans are written as failing-test-first steps. Don't
  skip to implementation.
- **One logical step per commit**, conventional-commit prefixes already in use:
  `feat:`, `test:`, `refactor:`, `docs:`, `ci:`.
- **Branch per slice**: `slice-N-<slug>`; one PR per slice; reviews on a
  `slice-N-post-slice-review` branch. Keep branch names matching their contents.
- **Verification is evidence, not assertion**: record the actual commands and
  outputs, and anchor proof of merged code in the post-merge `push` run, not just
  the PR run.
- Keep concerns separate: functional core work vs. CI/portability vs.
  repo-policy work each get their own slice, design, and review.

## When you change the core

Run, at minimum: `swift test`, `swift build -c release`,
`swift run -c release ViewportBenchmarks -- --gate`, the Foundation-free scan,
and (for portability-sensitive changes) the cross-target compile. Public-API or
algorithmic changes need a spec + plan + verification record, not a drive-by edit.
