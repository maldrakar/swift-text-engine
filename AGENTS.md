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
both clamp flags preserved. Its `--point-query --gate` is **local (not-yet-CI)**.

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
- `Package.swift` — `swift-tools-version: 6.0`. No `platforms:` declared, so iOS
  builds use the toolchain default deployment target.

## Commands

```bash
swift test                                                   # host unit tests
swift build -c release                                       # release build
swift run -c release ViewportBenchmarks -- --gate            # synthetic gate (blocking); expect gate=pass
swift run -c release ViewportBenchmarks -- --variable-height --gate   # variable-height local gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate   # mutate+recompute local gate
swift run -c release ViewportBenchmarks -- --structural-mutation --gate   # structural insert/delete local gate
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate   # bulk insert/delete-range local gate
swift run -c release ViewportBenchmarks -- --line-query --gate   # y->line position-query local gate
swift run -c release ViewportBenchmarks -- --line-geometry-query --gate   # y->line+box+fraction local gate
swift run -c release ViewportBenchmarks -- --column-query --gate   # x->cell within-line position-query local gate
swift run -c release ViewportBenchmarks -- --column-geometry-query --gate   # x->cell+box+fraction within-line local gate
swift run -c release ViewportBenchmarks -- --point-query --gate   # (x,y)->(line,cell) 2D composite local gate
swift run -c release ViewportBenchmarks -- --memory-shape    # memory-shape invariant; expect invariant=pass
swift run -c release ViewportBenchmarks -- --memory-observation       # host RSS observation
swift run -c release ViewportBenchmarks -- --help            # all flags
./.github/scripts/cross-target-compile.sh --self-test        # shell logic self-test (no toolchain)
./.github/scripts/cross-target-compile.sh                    # local iOS/WASM cross-compile
./.github/scripts/cross-target-compile.sh --targets ios      # iOS-only compile path
./.github/scripts/cross-target-compile.sh --targets wasm     # WASM-only observational path
```

Benchmark flags: `--range-only`, `--realistic-provider`, `--variable-height`,
`--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, `--column-geometry-query`, `--point-query`, `--memory-shape`,
`--memory-observation`, `--gate`. Only one mode
flag at a time. `--gate` is valid with the default pipeline, `--realistic-provider`,
`--variable-height`, `--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, `--column-geometry-query`, and `--point-query` modes; it is
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
  → `--column-geometry-query --gate` (blocking) → `--memory-shape`
  → `--memory-observation` → realistic relative
  observation (PR-only,
  `continue-on-error`). The synthetic, static variable-height, mutation
  variable-height, structural-mutation, bulk-structural-mutation, line-query,
  line-geometry-query, column-query, and column-geometry-query gates **fail the
  job on perf regression**.
  Benchmark budgets
  are still macOS-calibrated unless hosted Linux x86_64 evidence explicitly
  justifies a retune. SwiftPM build artifacts use `/tmp/text-engine-host-build`,
  not workspace `.build`.
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

- The **floor** (3x) is a derivation input, not a live gate check — a budget
  set below 3x of max-observed latency will eventually go red on a clean tree
  from runner noise alone. It covers both statistics, because the gate can
  fail on either one.
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

**The recipe** is a committed script, not a table to copy:

```bash
./.github/scripts/derive-gate-budgets.sh \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv <mode>

budget_p95 = round_up_2sf(max(8 x median(hosted p95), 3 x max(hosted p95)))
budget_p99 = round_up_2sf(max(2 x budget_p95, 8 x median(p99), 3 x max(p99)))
```

The 3x floor covers both statistics because the gate fails on either.

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
