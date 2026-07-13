# Slice 39 — `pointGeometryAt` — Verification Record

Branch: `slice-39-point-geometry-query` · PR: [#84](https://github.com/maldrakar/swift-text-engine/pull/84)
Plan: `docs/superpowers/plans/2026-07-13-point-geometry-query.md`
Spec: `docs/superpowers/specs/2026-07-13-point-geometry-query-design.md`

> **Status: IN PROGRESS.** Sections marked *pending* are filled as the evidence lands.
> This file is committed early on purpose: budgets here may only be **derived** from hosted
> Linux CI samples of this PR's own runs, and each push to the PR mints one such run. The
> record is therefore both the evidence trail and the vehicle that produces the evidence.

---

## 1. Pre-registered prediction (recorded BEFORE the evidence was complete)

The design's Decision 6 predicts that each `point_geometry_query` scenario's median p95 will sit
**above** its `point_query` counterpart (it does strictly more work — four extra constant probes)
and **within roughly 30 %** of it (it adds no search and no new arithmetic, so it must not cost a
different *class*). A prediction that is only reported when it succeeds is not a prediction, so it
is written down here, ahead of the full six-run harvest, and §7 reports the outcome either way.

Baseline — today's committed `point_query` medians (n=6), from
`./.github/scripts/derive-gate-budgets.sh <corpus> point-query`:

| scenario | `point_query` med p95 | predicted `point_geometry_query` med p95 band (+0 %…+30 %) |
|---|---|---|
| uniform_100k | 87 | 87 – 113 |
| uniform_1m | 83 | 83 – 108 |
| prefixsum_100k | 110 | 110 – 143 |
| prefixsum_1m | 124 | 124 – 161 |

**Falsification rule, fixed in advance:** a scenario landing far outside the band (say 2×) is a
*code* finding — a lost specialization, a re-probe, an allocation — and must be investigated, not
budgeted around.

First hosted data point (run `29279467574`, n=1, single sample vs. a 6-run median, so indicative
only — the real test is §7 at n≥6):

| scenario | p95_ns | p99_ns | vs. `point_query` med p95 |
|---|---|---|---|
| uniform_100k | 118 | 153 | +36 % |
| uniform_1m | 109 | 133 | +31 % |
| prefixsum_100k | 145 | 176 | +32 % |
| prefixsum_1m | 159 | 218 | +28 % |

Sitting at the band's edge, not beyond it, and nowhere near 2×.

---

## 2. Cross-target compile — `./.github/scripts/cross-target-compile.sh`

Run locally on macOS (arm64), 2026-07-13. Exit code **0**. A matching WASM Swift SDK was
installed, so the observational targets compiled rather than recording a skip.

```
mode=cross_target_compile_summary package=core      ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass
```

All eight compiles pass: iOS device + iOS simulator (**blocking**) and WASM + embedded WASM
(observational), for both `TextEngineCore` and `TextEngineReferenceProviders`. The new core file
`Sources/TextEngineCore/PointGeometryQuery.swift` therefore survives Embedded Swift with no source
changes, as the hard constraint requires.

---

## 3. Hosted run ledger

Budgets are derived from these runs and no others. The harvest dedup key is the **run id**, so a
workflow *re-run* contributes nothing — six runs means six distinct pushes.

| # | run id | head | note |
|---|---|---|---|
| 1 | `29279467574` | `dbb6538` | Task 4: the observational CI step's first run. Four `mode=point_geometry_query` lines confirmed at step level. |
| 2 | `29280327104` | `56cfb49` | Verification-record skeleton + pre-registered prediction. Green. |
| 3 | *pending* | | this commit (§4 local evidence) |
| 4 | *pending* | | |
| 5 | *pending* | | |
| 6 | *pending* | | |

---

## 4. Local test suite, release build, Foundation scan

```
$ swift test
	 Executed 274 tests, with 0 failures (0 unexpected) in 2.311 (2.323) seconds
```

274 XCTest tests, **0 failures**. (`swift test` also prints a "0 tests in 0 suites" line for the
empty Swift Testing harness — the documented harmless artifact, not a failure.) The count rose
267 → 271 → 274 across Tasks 1–3: 16 hardcoded-expectation tests, the parity oracles and the
probe-count pin, and the three benchmark-options tests.

```
$ swift build -c release
Build complete!
```

```
$ rg -n "Foundation" Sources/TextEngineCore
$ echo $?
1
```

Empty — exit 1, no matches. The core stays **Foundation-free**, as the hard constraint requires.
The new core file `Sources/TextEngineCore/PointGeometryQuery.swift` imports nothing at all: it is a
pure `extension ViewportVirtualizer`, stdlib-only.

## 5. All eleven benchmark modes' gate output — *pending*

## 6. Harvest + derivation (corpus diff, verbatim `derive-gate-budgets.sh` output) — *pending*

## 7. Spread table + the Decision 6 prediction outcome — *pending*

Per scenario: `max/median` on both statistics, and **which term set the budget** — the median term
(`8 × median`) or the `3 × max` floor. Any floor-governed budget is a budget set by *one sample*,
and this record is the only place that fact is visible before the append-only corpus freezes it.

## 8. The absolute check (observed hosted p99 vs. the 1 µs product line) — *pending*

An observation, **not** a gate. The brief's "turn 60 FPS into a measurable headless budget" is
recorded nowhere else in the project. Note in advance that the derived *regression* budgets already
exceed 1 µs on p99 for `point_query`, so the two thresholds are different objects: a future
absolute-budget slice must reconcile them rather than assume they agree.

## 9. Hosted PR-head run, and the post-merge `push` run — *pending*

Proof of merged code is anchored in the post-merge `push` run, not only the PR run.

---

## Notes carried from the task reviews

- The three parity oracles are **not** equal in strength, and this record must not imply they are.
  Oracle 1 (vs. `pointAt`) is fully independent: `pointAt` is a separately-written function, so a
  wrong 2D ordering or a mis-threaded line index diverges from it. Oracles 2 and 3 pin the
  composition's **wiring** (a swapped `x`/`y`, a stale value, an off-by-one `inLine`) but *not* the
  1D geometry arithmetic — they recompute the same 1D function with the test's own known-good
  arguments, so a bug inside `lineGeometryAt`'s math would reproduce on both sides of the assertion
  and never fail there. That arithmetic is covered by Slices 31/35's own suites, correctly out of
  scope here.
- The probe-count pin cannot be fooled by the binary search: the counting wrappers instrument the
  search probes too, but those cancel exactly in the `pointAt`-vs-`pointGeometryAt` difference
  (identical deterministic calls), leaving only the +2 / +2 box probes.
