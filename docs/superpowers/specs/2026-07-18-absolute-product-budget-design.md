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
failure condition on every gated run.

**In scope:**

- `Sources/ViewportBenchmarks/BenchmarkModels.swift` — two `GateLimits` constants
  (`frameNanoseconds`, `absoluteP99Nanoseconds`), a new `GateFailureReason` case
  (`budgetAbsoluteExceeded`), and the check inside `BenchmarkSummary.gateFailureReason`.
- `Sources/ViewportBenchmarks/BenchmarkSupport.swift` — two additive tokens on the
  `includeGate` output line (`budget_absolute_p99_ns=`, `headroom_absolute_p99=`).
- `Tests/ViewportBenchmarksTests/GateLogicTests.swift` — unit coverage of the new
  reason, its precedence, non-masking of `budget_stale`, and the derivation pin.
- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` — one new standing invariant:
  every gated scenario's regression p99 budget sits under the absolute ceiling.
- `AGENTS.md` — the `## Gate budgets` documentation of the new ceiling.
- The spec, plan, and verification record for the slice.

**Out of scope (byte-identity guards):**

- `Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders` — no engine or
  provider change; the Foundation-free scan stays empty.
- No new benchmark **mode**, no new CI step, no `.github/workflows/swift-ci.yml`
  change — so `WorkflowShapeTests` is untouched.
- No corpus change; **no regression-budget change — all 45 gate checksums
  byte-identical** to the Slice 42 baseline.
- `.github/scripts/derive-gate-budgets.sh` untouched — the absolute budget is
  deliberately **not** corpus-derived.

## Goals

- Add a fixed per-operation ceiling anchored to the 60 FPS frame that **never
  recalibrates**, catching the one drift a regression budget structurally cannot.
- Make it **blocking from day one** on every existing `--gate` run, with zero new CI
  steps — the brief's «блокируют merge» applied to the product target.
- Keep it non-flaky on a clean tree: the ceiling sits far above today's worst hosted
  p99, outside hosted run-to-run noise.
- Pin the ceiling to the frame math so it cannot be silently changed or accidentally
  recalibrated from the corpus.

## Non-Goals

- No per-scenario or tiered absolute budget (a single uniform ceiling was chosen —
  see Decision 2). No absolute p95 ceiling (see Decision 3).
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
  slice delivers. The brief's own example ("p95/p99 latency для пересчёта viewport")
  is realized as a fixed p99 ceiling per gated operation.

## Decisions

### Decision 1 — The absolute budget is a distinct axis, not a tighter regression budget

The regression gate asks "slower than recent code?"; the absolute gate asks "still
fast enough for the frame?" These are orthogonal. The absolute ceiling therefore has
**no staleness concept** — being far under it is success, not staleness (unlike a
regression budget, where huge headroom means the budget is stale). It is a fixed
product floor; only *exceeding* it fails.

### Decision 2 — One uniform ceiling, not tiers or per-scenario

Every gated operation is O(log N) / O(buffer) / O(k + log N) — none grows with
document size, and all sit between ~100 ns (queries) and ~190 µs (the slowest
structural mutation) on hosted Linux. A single ceiling anchored to the frame is the
minimal honest expression of "a core operation fits well within a frame": one
documented number, one derivation, one pinning test, nothing to keep from drifting
per-scenario. Tiers or a per-scenario table would add maintenance surface for a
product statement that is genuinely uniform ("fits the frame"). The regression gate
already provides the fine-grained, per-scenario tracking; the absolute gate is the
coarse product backstop.

### Decision 3 — Ceiling = 10% of the frame, checked against p99 only

```
frameNanoseconds       = 1_000_000_000 / 60   = 16_666_666   (60 FPS)
absoluteP99Nanoseconds = frameNanoseconds / 10 = 1_666_666    (10% of a frame)
```

**Why 10%.** A core operation must complete in ≤ 10% of a 60 FPS frame, leaving the
frame's remainder for shaping, rasterization, and UI outside the headless core. This
gives the slowest op today (~190 µs) ~8× headroom and the fast queries (~1 µs)
~1600×. The 8× on the slowest op is the binding number: hosted run-to-run p95 varies
up to ~2.7× on an unchanged binary (Slice 38 evidence), so ~8× leaves ~3× margin
over noise — non-flaky on a clean tree, yet a real product backstop that fires on
cumulative re-derived drift.

**Why p99 only.** The ceiling is uniform and `p95 ≤ p99`, so a passing p99 implies a
passing p95. One comparison covers both; a separate p95 ceiling would be redundant.
The tail (p99) is the right product guarantee — "even the worst-case frame fits."

### Decision 4 — Fold into the existing gate; new reason `budget_absolute_exceeded`

The check is one condition inside `BenchmarkSummary.gateFailureReason`, evaluated on
every existing `--gate` run. All eleven current gate steps enforce the product ceiling
for free — no new mode, no new CI step, no workflow-YAML change. This is the
"composes cleanly with the median floor" shape the Slice 42 review names.

Ordering inside `gateFailureReason` (unchanged prefix, new line inserted):

```
missingBudget          (no regression budget present)
operationFailures      (correctness)
budgetExceeded         (regression: observed > regression budget)   -- code got slower
budgetAbsoluteExceeded (product:  observed p99 > absolute ceiling)  -- NEW
budgetStale            (regression budget too loose)
```

**Why this order is the semantic:**

- **After `budgetExceeded`:** exceeding 1.67 ms always also exceeds the ≤580 µs
  regression budget, so a plain regression reports the familiar `budget_exceeded`.
  `budget_absolute_exceeded` therefore fires **only** when the regression budget
  *passes* but the frame is blown — precisely the "slow drift the regression budget
  was re-derived around" case it exists to catch.
- **Before `budgetStale`:** a genuine product failure is reported as such, not masked
  as a stale budget. It never masks legitimate staleness in return, because staleness
  fires only when *observed* is tiny (huge headroom), where the absolute check is
  silent (tiny observed is far under the ceiling).

The three reasons carry three opposite instructions:
`budget_exceeded` → fix the code (regression); `budget_stale` → re-derive the budget;
`budget_absolute_exceeded` → the engine genuinely exceeds the product frame — fix the
code/architecture, **never loosen** (the ceiling cannot be re-derived).

### Decision 5 — A standing invariant ties the two gates together

`GateFloorTests` gains one invariant: **every gated scenario's committed regression
p99 budget < `absoluteP99Nanoseconds`.** This does three things at once:

1. Guarantees the absolute gate never flakes on a clean tree — a regression p99
   budget is ≥ `3× max(hosted)`, so if it sits under the ceiling then `max(hosted)`
   sits under the ceiling with ~3× to spare.
2. Keeps the ordering honest — regression is the tight inner gate, absolute the loose
   outer one; the invariant proves the inner is always inside the outer.
3. Validates the 10% fraction against real budgets — if any future scenario's
   regression budget crosses 10% of a frame, this test forces a conscious decision
   (raise the fraction, or recognize the op is too slow for the product) instead of a
   silent conflict.

## Implementation Architecture

### `BenchmarkModels.swift`

- `GateLimits.frameNanoseconds` and `GateLimits.absoluteP99Nanoseconds` as
  expression-form constants (Decision 3), with a comment stating they are FIXED and
  never recalibrated.
- `GateFailureReason.budgetAbsoluteExceeded = "budget_absolute_exceeded"`.
- One line in `gateFailureReason` (Decision 4 ordering): after the `budgetExceeded`
  return, `if p99Nanoseconds > GateLimits.absoluteP99Nanoseconds { return
  .budgetAbsoluteExceeded }`.

### `BenchmarkSupport.swift`

In the `includeGate` block only, after the existing headroom tokens and before
`gate=`, append `budget_absolute_p99_ns=\(GateLimits.absoluteP99Nanoseconds)` and
`headroom_absolute_p99=\(formatHeadroom(Double(absolute)/Double(observed p99)))`.
Every existing token is preserved in place; the additions are keyed, so the harvester
(which reads keyed tokens) is unaffected.

### `GateLimits` derivation pin — `GateLogicTests.swift`

Data-not-logic constants pinned to the frame math (Decision 3), independent of any
hosted timing.

### The standing invariant — `GateFloorTests.swift`

One test iterating `everyGatedBudget()` (the single registry) asserting
`b.p99 < GateLimits.absoluteP99Nanoseconds` for every gated scenario (Decision 5).

### Documentation — `AGENTS.md`

`## Gate budgets` gains: the frame derivation and 10% fraction; that the absolute
ceiling is FIXED and never re-derived (distinct from the regression recipe); the
`regression p99 budget < absolute ceiling` invariant; and `budget_absolute_exceeded`
added to the "failure reasons are opposite instructions" set.

### Verification record

`docs/superpowers/verification/2026-07-18-absolute-product-budget.md` — recorded
commands and outputs (`swift test`, `swift build -c release`, every `--gate` mode
showing `gate=pass` with the new `budget_absolute_p99_ns=` token, the Foundation-free
scan, the 45-checksum byte-identity table vs the Slice 42 baseline), plus a
**guard-is-live** demonstration: temporarily lower `absoluteP99Nanoseconds` below a
scenario's observed p99, show `gate=fail reason=budget_absolute_exceeded`, revert.
Hosted run IDs anchored in the post-merge `push` run.

## Testing Strategy

TDD, failing-test-first per the plan. Unit tests only — no hosted timing dependency.

- **`GateLogicTests`:**
  - `budget_absolute_exceeded` fires when observed p99 > ceiling and the regression
    budget passes (regression budget set large enough to pass).
  - passes (`nil`) just under the ceiling with a non-stale regression budget.
  - precedence: observed exceeding both the regression budget and the ceiling reports
    `budget_exceeded`, not `budget_absolute_exceeded`.
  - non-masking: a tiny-observed, loose regression budget still reports
    `budget_stale`.
  - derivation pin: `absoluteP99Nanoseconds == frameNanoseconds / 10` and
    `frameNanoseconds == 1_000_000_000 / 60`.
- **`GateFloorTests`:** the new `regression p99 < absolute ceiling` invariant over
  `everyGatedBudget()`.
- **Regression guard:** existing `GateLogicTests`/`GateFloorTests` stay green
  unchanged (their synthetic observed values are sub-ceiling, so the new check is
  transparent to them).
- **Full suite + every `--gate` mode** green locally; 45 checksums byte-identical.

## Acceptance Criteria

1. `GateLimits.absoluteP99Nanoseconds == 1_666_666`, derived as `frameNanoseconds /
   10` with `frameNanoseconds == 1_000_000_000 / 60`, and pinned by a test.
2. `budget_absolute_exceeded` fires exactly when observed p99 exceeds the ceiling and
   the regression budget passes; `budget_exceeded` retains precedence; `budget_stale`
   is not masked. All covered by `GateLogicTests`.
3. Every gated scenario's regression p99 budget is under the absolute ceiling, pinned
   by a `GateFloorTests` invariant over `everyGatedBudget()`.
4. Every `--gate` mode prints `budget_absolute_p99_ns=1666666` and reports
   `gate=pass` on the clean tree.
5. Guard-is-live: a temporarily-lowered ceiling yields `gate=fail
   reason=budget_absolute_exceeded`; reverts clean.
6. `rg -n Foundation Sources/TextEngineCore` empty; no `TextEngineCore` /
   `TextEngineReferenceProviders` / corpus / regression-budget / workflow-YAML
   change; all 45 gate checksums byte-identical to the Slice 42 baseline.
7. Hosted CI green across all three required jobs and all eleven blocking gate steps
   at step level, on both the PR-head and post-merge `push` runs.

## Risks And Gaps

### The 10% fraction is a judgment call, not a derivation

10% of a frame is a defensible engineering choice, not a value the brief dictates
(the brief names only 60 FPS). The `GateFloorTests` invariant (Decision 5) keeps it
honest against real budgets, and the constant is a one-line change if a future slice
argues for a different fraction — but changing it is a conscious product decision,
recorded, never a silent recalibration.

### The absolute gate is loose for fast queries by design

Queries sit ~1600× under the ceiling, so the absolute gate effectively never bites
for them — the regression gate would catch any query drift long first. This is
intentional (Decision 2): the absolute gate's value concentrates on the slowest ops,
which are closest to the frame. A query drifting 500× is still within product
tolerance (~3% of a frame) even though the regression gate would have caught it.

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
residual in the regression recipe; or harvester provenance hardening (Slice 42 P2 #4).
The functional-core query surface (line/column/point, position + geometry) and the
gate machinery are both now feature-complete for the current axes.
