# Absolute Product Budget Design

Slice 43. Date: 2026-07-18.

## Status

Design. Supersedes no prior spec. Delivers the **brief success criterion the whole
gate suite has never satisfied** — turning "60 FPS" into a measurable headless
budget — recorded as an explicit gap by the **Slice 38 spec** ("The product
budget", floated there as Option C) and named the recommended **Option A** by the
**Slice 42 post-slice review**. Selected by an authorized user decision for Slice 43.

## Source Context

Every gate budget in the suite is a **regression** budget: derived by
`.github/scripts/derive-gate-budgets.sh` from the scenario's own hosted median (with
a `3× max` floor and 50×/100× headroom ceilings), re-derived from fresh evidence
each time the corpus grows. Slices 41–42 finished hardening that machinery — the
windowed floor is two-way, and both consumers (Swift + shell) agree on window
selection across all three axes of "both consumers agree."

But a regression budget is anchored to a **moving median**, and the brief asks for a
second, distinct thing (`docs/initial-project-brief.md:21`):

> В дизайн-спецификации нужно превратить "60 FPS" в измеримый headless budget:
> например p95/p99 latency для пересчёта viewport.

No check in the suite ever consults the frame. The Slice 38 spec recorded the
consequence plainly: *"if the engine becomes 2× slower and the budgets are
re-derived against the new medians, every gate stays green and no check ever
consults the frame."* This slice adds that check.

## Problem

A median-anchored regression gate has one structural blind spot: **slow drift it
re-derives around.** Each individual slice can legitimately re-derive a budget a few
percent looser against fresh hosted evidence; over many slices the engine can drift
arbitrarily far from the product target while every gate stays green, because the
target it is measured against moved with it. The regression gate answers "did *this*
change make the code slower than *recent* code?" It structurally cannot answer "is
the engine still fast enough for the *product*?"

The precondition for closing this is now met: with the upward ratchet stopped (Slice
41) and the derivation tooling hardened (Slice 42), a fixed absolute ceiling composes
cleanly with the median-governed floor instead of fighting a moving median.

## Scope

A single **absolute product ceiling**, folded into the existing gate as one more
failure condition on every **frame-hot-path** gated run (Decision 2 scopes which runs).

**In scope:**

- `Sources/ViewportBenchmarks/BenchmarkModels.swift` — two `GateLimits` constants
  (`frameNanoseconds`, `absoluteP99Nanoseconds`), a new `GateFailureReason` case
  (`budgetAbsoluteExceeded`), the `BenchmarkSummary.headroomAbsoluteP99` property, and
  the mode-gated check inside `BenchmarkSummary.gateFailureReason`.
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift` — the `BenchmarkMode.isFrameHotPath`
  classifier (exhaustive switch beside `isGateable`; `false` only for
  `.bulkStructuralMutation`).
- `Sources/ViewportBenchmarks/BenchmarkSupport.swift` — two additive tokens on the
  `includeGate` output line (`budget_absolute_p99_ns=`, `headroom_absolute_p99=`) for
  frame-hot-path modes; a visible `budget_absolute_p99_ns=exempt` marker for bulk.
- `Tests/ViewportBenchmarksTests/GateLogicTests.swift` — unit coverage of the new
  reason, its precedence, non-masking of `budget_stale`, the derivation pin, that the
  check fires only for frame-hot-path modes, and the exclusion-set pin
  (`isFrameHotPath` is `false` for exactly `{bulk_structural_mutation}` among gated modes).
- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` — one new standing invariant:
  every **frame-hot-path** gated scenario's regression p99 budget sits under the
  absolute ceiling (bulk scenarios are excluded, matching the runtime check).
- `AGENTS.md` — the `## Gate budgets` documentation of the new ceiling and its
  frame-hot-path scope.
- The spec, plan, and verification record for the slice.

**Out of scope (byte-identity guards):**

- `Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders` — no engine or
  provider change; the Foundation-free scan stays empty.
- No new benchmark **mode**, no new CI step, no `.github/workflows/swift-ci.yml`
  change — so `WorkflowShapeTests` is untouched.
- No change to `bulk_structural_mutation`'s existing regression gate — it stays gated
  on its own median-derived budget; it is only exempted from the *absolute* ceiling.
- No corpus change; **no regression-budget change — all 45 gate checksums
  byte-identical** to the Slice 42 baseline.
- `.github/scripts/derive-gate-budgets.sh` untouched — the absolute budget is
  deliberately **not** corpus-derived.

## Goals

- Add a fixed per-operation ceiling anchored to the 60 FPS frame that **never
  recalibrates**, catching the one drift a regression budget structurally cannot.
- Make it **blocking from day one** on every frame-hot-path `--gate` run, with zero new
  CI steps — the brief's «блокируют merge» applied to the product target.
- Keep it non-flaky on a clean tree: the ceiling sits far above today's worst hosted
  p99, outside hosted run-to-run noise.
- Pin the ceiling to the frame math so it cannot be silently changed or accidentally
  recalibrated from the corpus.

## Non-Goals

- No per-scenario or tiered absolute budget: a single uniform ceiling over the
  frame-hot-path set, with bulk excluded wholesale rather than tiered (see Decision 2).
  No absolute p95 ceiling (see Decision 3).
- No change to how regression budgets are derived, floored, or ceiled.
- No product FPS target beyond the brief's 60 (16.7 ms frame).
- No harvesting/corpus interaction — the absolute budget has no corpus relationship.

## Brief Alignment

- **Foundation-free core** — no core file changed; the ceiling lives entirely in the
  benchmark target, which is not the shipped core.
- **Swift Embedded / iOS+WASM** — no engine surface touched; both cross-target jobs
  unaffected.
- **Zero-dependency** — one integer constant and one comparison; nothing added.
- **Memory / virtualization invariants** — untouched.
- **«Регрессионные бенчмарки блокируют merge при деградации»** — strengthened: the
  suite now blocks on both *relative* regression (existing) and *absolute* product
  degradation (new).
- **«превратить "60 FPS" в измеримый headless budget»** — this is the criterion the
  slice delivers, and at the brief's own granularity: the example is «p95/p99 latency
  для *пересчёта viewport*» — a *frame* operation. The fixed p99 ceiling is therefore
  applied to the frame-hot-path set (viewport compute, incremental recompute, queries)
  and deliberately not to discrete bulk edits, which the brief's «60 FPS» / «scroll
  performance» criterion does not govern.

## Decisions

### Decision 1 — The absolute budget is a distinct axis, not a tighter regression budget

The regression gate asks "slower than recent code?"; the absolute gate asks "still
fast enough for the frame?" These are orthogonal. The absolute ceiling therefore has
**no staleness concept** — being far under it is success, not staleness (unlike a
regression budget, where huge headroom means the budget is stale). It is a fixed
product floor; only *exceeding* it fails.

### Decision 2 — One uniform ceiling over frame-hot-path operations; bulk batch edits excluded

The brief's «60 FPS» is a guarantee about the **scroll/keystroke frame** —
«p95/p99 latency для пересчёта viewport». So the absolute ceiling applies to operations
that run *inside* a frame: viewport compute (`pipeline`, `realistic_provider`,
`variable_height`), the incremental recompute after a single edit
(`variable_height_mutation`, `structural_mutation`), and every position/geometry query.
These are all O(log N) / O(buffer) / O(k + log N), none grows with document size, and —
crucially — the slowest of them, `structural_mutation`, tops out at **~58 µs** hosted
p99 (full corpus), comfortably inside a frame.

**Bulk multi-line edits are NOT frame-hot-path and are excluded.**
`bulk_structural_mutation` inserts/removes thousands of lines in one operation (a large
paste or range delete). It is a *discrete user action* that may legitimately span more
than one frame — it is not on the 60 FPS scroll path. Its hosted p99 reaches **~570 µs**
and its median-derived regression budgets are **3 ms / 5.8 ms**, both *above* a
10 %-frame ceiling. Holding a 4096-line paste to 10 % of a scroll frame is a category
error, and doing so would either force the ceiling up to ~35 % of a frame (destroying
the "fits well within a frame" statement for every fast op) or make the new product
gate flake red on ordinary runner noise (its worst hosted p99 is only ~2.9× under a
10 % ceiling, against ~2.7× runner spread). So bulk stays gated on its own regression
budget and is exempt from the absolute ceiling.

**The classification is a mechanism, not a comment.** `BenchmarkMode.isFrameHotPath` is
an **exhaustive switch** (never a deny-list — the same discipline as `isGateable`),
returning `false` for exactly `bulk_structural_mutation` among gated modes. A new mode
must classify itself, so it can neither silently inherit the ceiling nor silently escape
it. A `GateLogicTests` pin asserts the excluded set is exactly
`{bulk_structural_mutation}`, so widening the exemption is a conscious, reviewed change.

Within the frame-hot-path set a *single* ceiling — not tiers, not per-scenario — is the
minimal honest expression of "a core frame operation fits well within a frame": one
documented number, one derivation, one pinning test. The regression gate still provides
the fine-grained per-scenario tracking; the absolute gate is the coarse product backstop
for the frame path.

### Decision 3 — Ceiling = 10% of the frame, checked against p99 only

```
frameNanoseconds       = 1_000_000_000 / 60   = 16_666_666   (60 FPS)
absoluteP99Nanoseconds = frameNanoseconds / 10 = 1_666_666    (10% of a frame)
```

**Why 10%.** A core frame operation must complete in ≤ 10% of a 60 FPS frame, leaving
the frame's remainder for shaping, rasterization, and UI outside the headless core.
Against the frame-hot-path set (bulk excluded, Decision 2) this gives the slowest op,
`structural_mutation` at ~58 µs hosted p99, **~28× headroom**, and the fast queries
(~0.2–0.7 µs) **~2,400–8,000×**. Non-flakiness is not the binding constraint here — 28×
sits an order of magnitude above the ~2.7× hosted run-to-run spread (Slice 38 evidence),
so the absolute gate cannot redden a clean tree. The binding constraint is instead the
*other* side: the ceiling must stay **above** the slowest frame-hot-path regression
*budget*, so the AC3 invariant (Decision 5) holds. The largest such budget is
`structural_mutation|1m` at 580 µs, which the 1.67 ms ceiling clears by **2.87×** — the
tightest margin in the design and the effective lower bound on the 10% fraction.

**Why p99 only.** The ceiling is uniform and `p95 ≤ p99`, so a passing p99 implies a
passing p95. One comparison covers both; a separate p95 ceiling would be redundant.
The tail (p99) is the right product guarantee — "even the worst-case frame fits."

### Decision 4 — Fold into the existing gate; new reason `budget_absolute_exceeded`

The check is one condition inside `BenchmarkSummary.gateFailureReason`, guarded by
`mode.isFrameHotPath`, evaluated on every existing `--gate` run. The ten frame-hot-path
gate steps enforce the product ceiling for free — no new mode, no new CI step, no
workflow-YAML change; `--bulk-structural-mutation` keeps only its regression check. This
is the "composes cleanly with the median floor" shape the Slice 42 review names.

Ordering inside `gateFailureReason` (unchanged prefix, new mode-gated line inserted):

```
missingBudget          (no regression budget present)
operationFailures      (correctness)
budgetExceeded         (regression: observed > regression budget)          -- code got slower
budgetAbsoluteExceeded (product: frame-hot-path & observed p99 > ceiling)   -- NEW
budgetStale            (regression budget too loose)
```

**Why this order is the semantic:**

- **After `budgetExceeded`:** across the frame-hot-path set every regression p99 budget
  is ≤ 580 µs (`structural_mutation|1m`), so exceeding the 1.67 ms ceiling always also
  exceeds the regression budget — a plain regression reports the familiar
  `budget_exceeded`. `budget_absolute_exceeded` therefore fires **only** when the
  regression budget *passes* but the frame is blown — precisely the "slow drift the
  regression budget was re-derived around" case it exists to catch. (This clean
  implication is exactly what excluding bulk buys: bulk's 3–5.8 ms budgets sit *above*
  the ceiling, so had they stayed in the checked set the absolute reason would have
  fired on ordinary noise, not on drift — see Decision 2.)
- **Before `budgetStale`:** a genuine product failure is reported as such, not masked
  as a stale budget. It never masks legitimate staleness in return, because staleness
  fires only when *observed* is tiny (huge headroom), where the absolute check is
  silent (tiny observed is far under the ceiling).

The three reasons carry three opposite instructions:
`budget_exceeded` → fix the code (regression); `budget_stale` → re-derive the budget;
`budget_absolute_exceeded` → the engine genuinely exceeds the product frame — fix the
code/architecture, **never loosen** (the ceiling cannot be re-derived).

### Decision 5 — A standing invariant ties the two gates together

`GateFloorTests` gains one invariant: **every FRAME-HOT-PATH gated scenario's committed
regression p99 budget < `absoluteP99Nanoseconds`.** (It filters `everyGatedBudget()` by
`isFrameHotPath`, so bulk is excluded here exactly as in the runtime check — the two
must agree.) This does three things at once:

1. Guarantees the absolute gate never flakes on a clean tree — a regression p99 budget
   is ≥ `3× max(hosted)`, so if the *budget* sits under the ceiling then `max(hosted)`
   sits under it with even more room (observed is smaller than its own budget). The
   binding scenario is `structural_mutation|1m` (budget 580 µs, 2.87× under the ceiling;
   observed ~58 µs, ~28× under).
2. Keeps the ordering honest — regression is the tight inner gate, absolute the loose
   outer one; the invariant proves the inner is always inside the outer *for the checked
   set*, which is what makes Decision 4's `budget_exceeded`-before-`budget_absolute`
   implication hold.
3. Validates the 10% fraction against real budgets — if any future frame-hot-path
   scenario's regression budget crosses 10% of a frame, this test forces a conscious
   decision (raise the fraction, reclassify the op as not-frame-hot-path, or recognize
   it is too slow for the product) instead of a silent conflict. This is precisely the
   check that would have caught the original `bulk_structural_mutation` collision.

## Implementation Architecture

### `BenchmarkModels.swift`

- `GateLimits.frameNanoseconds` and `GateLimits.absoluteP99Nanoseconds` as
  expression-form constants (Decision 3), with a comment stating they are FIXED and
  never recalibrated.
- `GateFailureReason.budgetAbsoluteExceeded = "budget_absolute_exceeded"`.
- `BenchmarkSummary.headroomAbsoluteP99` — `absoluteP99Nanoseconds / observed p99`,
  reusing the zero-observed guard (mirrors `headroomP95`/`headroomP99`).
- One mode-gated line in `gateFailureReason` (Decision 4 ordering): after the
  `budgetExceeded` return, `if mode.isFrameHotPath, p99Nanoseconds >
  GateLimits.absoluteP99Nanoseconds { return .budgetAbsoluteExceeded }`.

### `BenchmarkOptions.swift`

`BenchmarkMode.isFrameHotPath` — an exhaustive `switch` beside `isGateable`, returning
`false` only for `.bulkStructuralMutation` (Decision 2), with a comment explaining bulk
is a discrete multi-frame user action, not a scroll-frame operation.

### `BenchmarkSupport.swift`

In the `includeGate` block only, after the existing headroom tokens and before `gate=`:
for a frame-hot-path mode append
`budget_absolute_p99_ns=\(GateLimits.absoluteP99Nanoseconds)` and
`headroom_absolute_p99=\(formatHeadroom(absolute / observed p99))`; for a non-hot-path
mode (bulk) append `budget_absolute_p99_ns=exempt` instead — a visible marker rather
than a silent omission, so a reader can see the ceiling was deliberately not applied
(the repo's "no silent caps" discipline). Every existing token is preserved in place;
the additions are keyed, so the harvester (which reads keyed tokens) is unaffected.

### `GateLimits` derivation pin + exclusion pin — `GateLogicTests.swift`

Data-not-logic constants pinned to the frame math (Decision 3), independent of any
hosted timing. Plus the exclusion pin: `Set(BenchmarkMode.allCases.filter { $0.isGateable
&& !$0.isFrameHotPath }.map(\.outputName)) == ["bulk_structural_mutation"]`, so the
exemption cannot silently widen.

### The standing invariant — `GateFloorTests.swift`

One test iterating `everyGatedBudget()` (the single registry), **filtered to
`isFrameHotPath` modes**, asserting `b.p99 < GateLimits.absoluteP99Nanoseconds` for
every frame-hot-path gated scenario (Decision 5). Bulk scenarios are skipped, so the
invariant matches the runtime check exactly.

### Documentation — `AGENTS.md`

`## Gate budgets` gains: the frame derivation and 10% fraction; that the absolute
ceiling applies to **frame-hot-path** operations only and `bulk_structural_mutation` is
exempt (a discrete multi-frame user action, not a scroll-frame op); that the ceiling is
FIXED and never re-derived (distinct from the regression recipe); the
`frame-hot-path regression p99 budget < absolute ceiling` invariant; and
`budget_absolute_exceeded` added to the "failure reasons are opposite instructions" set.

### Verification record

`docs/superpowers/verification/2026-07-18-absolute-product-budget.md` — recorded
commands and outputs (`swift test`, `swift build -c release`, every frame-hot-path
`--gate` mode showing `gate=pass` with the new `budget_absolute_p99_ns=1666666` +
`headroom_absolute_p99=` tokens, `--bulk-structural-mutation` showing
`budget_absolute_p99_ns=exempt`, the Foundation-free scan, the 45-checksum
byte-identity table vs the Slice 42 baseline), plus a **guard-is-live** demonstration:
temporarily lower `absoluteP99Nanoseconds` below a frame-hot-path scenario's observed
p99, show `gate=fail reason=budget_absolute_exceeded`, revert. Hosted run IDs anchored
in the post-merge `push` run.

## Testing Strategy

TDD, failing-test-first per the plan. Unit tests only — no hosted timing dependency.

- **`GateLogicTests`:**
  - `budget_absolute_exceeded` fires when a **frame-hot-path** mode's observed p99 >
    ceiling and the regression budget passes (regression budget set large enough to pass).
  - a **non-hot-path** (bulk) summary with observed p99 > ceiling but regression budget
    passing reports `nil`, **not** `budget_absolute_exceeded` — the mode-gate works.
  - passes (`nil`) just under the ceiling with a non-stale regression budget.
  - precedence: observed exceeding both the regression budget and the ceiling reports
    `budget_exceeded`, not `budget_absolute_exceeded`.
  - non-masking: a tiny-observed, loose regression budget still reports `budget_stale`.
  - derivation pin: `absoluteP99Nanoseconds == frameNanoseconds / 10` and
    `frameNanoseconds == 1_000_000_000 / 60`.
  - exclusion pin: `{gated modes with isFrameHotPath == false}` equals
    `{bulk_structural_mutation}`.
- **`GateFloorTests`:** the new `regression p99 < absolute ceiling` invariant over
  `everyGatedBudget()` **filtered to `isFrameHotPath`**.
- **Regression guard:** existing `GateLogicTests`/`GateFloorTests` stay green
  unchanged (their synthetic observed values are sub-ceiling, so the new check is
  transparent to them).
- **Full suite + every `--gate` mode** green locally; 45 checksums byte-identical.

## Acceptance Criteria

1. `GateLimits.absoluteP99Nanoseconds == 1_666_666`, derived as `frameNanoseconds /
   10` with `frameNanoseconds == 1_000_000_000 / 60`, and pinned by a test.
2. `budget_absolute_exceeded` fires exactly when a frame-hot-path mode's observed p99
   exceeds the ceiling and the regression budget passes; a non-hot-path (bulk) summary
   in the same state does **not** fire it; `budget_exceeded` retains precedence;
   `budget_stale` is not masked. All covered by `GateLogicTests`.
3. `BenchmarkMode.isFrameHotPath` is `false` for exactly `{bulk_structural_mutation}`
   among gated modes, pinned by a `GateLogicTests` test.
4. Every frame-hot-path gated scenario's regression p99 budget is under the absolute
   ceiling, pinned by a `GateFloorTests` invariant over the `isFrameHotPath`-filtered
   `everyGatedBudget()`.
5. Every frame-hot-path `--gate` mode prints `budget_absolute_p99_ns=1666666` and
   reports `gate=pass` on the clean tree; `--bulk-structural-mutation` prints
   `budget_absolute_p99_ns=exempt` and still reports `gate=pass`.
6. Guard-is-live: a temporarily-lowered ceiling yields `gate=fail
   reason=budget_absolute_exceeded` on a frame-hot-path scenario; reverts clean.
7. `rg -n Foundation Sources/TextEngineCore` empty; no `TextEngineCore` /
   `TextEngineReferenceProviders` / corpus / regression-budget / workflow-YAML
   change; all 45 gate checksums byte-identical to the Slice 42 baseline.
8. Hosted CI green across all three required jobs and all eleven blocking gate steps
   at step level, on both the PR-head and post-merge `push` runs.

## Risks And Gaps

### The 10% fraction is a judgment call, not a derivation

10% of a frame is a defensible engineering choice, not a value the brief dictates
(the brief names only 60 FPS). Its effective lower bound is set by the slowest
frame-hot-path regression budget — `structural_mutation|1m` at 580 µs, which 1.67 ms
clears by 2.87×; a fraction below ~6% would collide with it and trip the Decision 5
invariant. The `GateFloorTests` invariant keeps the fraction honest against real
budgets, and the constant is a one-line change if a future slice argues for a different
fraction — but changing it is a conscious product decision, recorded, never a silent
recalibration.

### The absolute gate is loose for fast operations by design

Even the slowest frame-hot-path op (`structural_mutation`, ~58 µs) sits ~28× under the
ceiling, and the fast queries ~2,400–8,000×, so the absolute gate effectively never
bites for them — the regression gate would catch any drift long first. This is
intentional (Decision 2): the absolute gate is a *coarse* backstop whose value is to
catch cumulative, re-derived-around drift toward the frame, not fine per-scenario
regressions. A query drifting 500× is still within product tolerance (well under a
frame) even though the regression gate would have caught it.

### Bulk edits are outside the absolute gate — a deliberate residual

`bulk_structural_mutation` is exempt from the ceiling (Decision 2), so *slow drift in
bulk-edit latency* is caught only by its median-anchored regression budget — the very
blind spot this slice closes for the frame path, left open for bulk. This is the correct
scope (a multi-line paste is not a scroll frame), but it is a real, recorded gap: if the
product later needs a bulk-edit latency guarantee it wants its own absolute budget
anchored to a bulk-appropriate target (e.g. "a 4096-line paste in ≤ N frames"), not the
60 FPS scroll frame. Recorded, not silently dropped.

### Arithmetic residual carried from Slice 42 (P2 #1) is untouched

The within-band-looser *regression* arithmetic residual (a standing
"reproduce-every-literal" test) is a separate tooling-completion slice and is not in
scope here. This slice adds a product axis; it does not close the regression-recipe
residual.

### Standing items unchanged

WASM observational; realistic-provider observation PR-only `continue-on-error`; the
harvester's run-id-only provenance gap (Slice 42 P2 #4); the `Main` ruleset's
documented bypass-actor shape.

## Recommended Next Step

Slice 44 candidate: the arithmetic "reproduce every committed literal" standing test
(Slice 42 P2 #1) — the tooling-completion analog that closes the last within-band
residual in the regression recipe; or harvester provenance hardening (Slice 42 P2 #4);
or a bulk-edit absolute budget anchored to a bulk-appropriate target (the residual this
slice records under Risks). The functional-core query surface (line/column/point,
position + geometry) and the frame-path gate machinery are both now feature-complete for
the current axes.
