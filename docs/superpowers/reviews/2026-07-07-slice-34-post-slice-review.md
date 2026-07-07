# Slice 34 Post-Slice Review

Date: 2026-07-07

## Scope Reviewed

This review covers Slice 34: the **column-query CI gate promotion**. It wires the
already-existing `--column-query --gate` benchmark path (shipped **local-only** in
Slice 33) into the required `Host tests and benchmark gate` hosted job as a new
**blocking** step — the **eighth** contiguous blocking latency gate, and the
**first** for the engine's horizontal axis — so a runtime regression in the
within-line inverse position-query path
(`ViewportVirtualizer.columnAt(x:inLine:metrics:)`) now fails the job. It was the
Slice 33 review's recommended **Option A** and the user-selected one-shot blocking
rollout.

This is a pure CI/governance slice, and the direct structural twin of Slice 32
(line-geometry-query) and Slice 28 (line-query). Like both — and unlike Slice 26,
which folded in the `deterministicIndex` overflow hardening the Slice 25 review had
flagged — the Slice 33 review found **no P0/P1/P2 and no actionable P3** in the
promoted benchmark, so Slice 34 promotes it **unchanged**. It changes no
`TextEngineCore` source, no `TextEngineReferenceProviders` provider/algorithm, no
benchmark Swift source (no scenario, budget, helper, or mode edit), no tests, and
no package metadata. It closes the single regression-protection gap the Slice 33
review identified (debt (a) — the local-only column gate).

The slice was delivered through **two** PRs, both now merged:

- PR #68 (`slice-34-column-query-ci-gate`), title *"Slice 34: promote column-query
  benchmark to a blocking hosted gate"*, final head
  `e55dfc0b91de30d986434e2025945573a4108106` (`e55dfc0`), merged to `main` as
  `2281f005dd306b877709dab86dae09516cb934ff` (`2281f00`) by `maldrakar` at
  2026-07-06T19:59:42Z — the workflow step, the `AGENTS.md` update, the spec, the
  plan, and the verification record's local sections (with the hosted section left
  as an explicit `Pending` placeholder).
- PR #69 (`slice-34-post-merge-verification`), title *"Slice 34: record post-merge
  hosted proof for column-query gate"*, merged as
  `0c674ea0c0072ee5a33da7d50c910ff3cee29064` (`0c674ea`, current `main` HEAD) by
  `maldrakar` at 2026-07-07T13:28:56Z — the docs-only follow-up (`eee58ce`) that
  filled the verification record's `Hosted Proof` section with the real PR-head and
  merged-code push runs.

**Both PRs are merged at review time**, so `main`'s verification record carries
real hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-07-05-column-query-ci-gate-promotion-design.md`
- `docs/superpowers/plans/2026-07-05-column-query-ci-gate-promotion.md`
- `docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md`
- `docs/superpowers/reviews/2026-07-04-slice-33-post-slice-review.md`
- `.github/workflows/swift-ci.yml` (host job)
- `AGENTS.md` (architecture paragraph + CI section)
- PR #68 / #69 metadata, hosted run evidence (step-level conclusions), merge
  parentage, and the merged Slice 34 diff

The reviewed Slice 34 range (PR #67 review merge → current `main` HEAD), excluding
this review document itself, is:

```text
9b954c5..0c674ea
```

`git merge-base 9b954c5 0c674ea` returns `9b954c5`, confirming the Slice 33 review
merge (PR #67, `9b954c5`) is a clean ancestor and the range captures exactly the
Slice 34 work. Merge parentage confirmed via `git rev-list --parents`: `2281f00`
(PR #68)'s parents are the base `9b954c5` and the verified PR head `e55dfc0`;
`0c674ea` (PR #69) merges the post-merge-proof commit `eee58ce` onto `2281f00`. A
fresh name-only diff confirms the range is confined to
`.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**` — it does **not**
touch `Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders`,
`Sources/ViewportBenchmarks`, `Tests/**`, or `Package.swift`
(`git diff --name-only 9b954c5..0c674ea -- Sources Tests Package.swift` is empty).

## Product Brief Alignment

The brief requires regression benchmarks to block merge on performance degradation
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
Before this slice that principle held for seven of the engine's eight measured
latency paths — synthetic pipeline, static variable-height, variable-height
mutation, structural-mutation, bulk-structural-mutation, line-query, and
line-geometry-query gates all ran blocking in hosted CI. The **horizontal**
within-line position-query path, opened in Slice 33, was proven **locally only**:
the host job stayed green regardless of `columnAt` runtime because the benchmark
was never invoked in the workflow.

Slice 34 closes exactly that gap, and it is the **first hosted regression
protection the horizontal axis has ever had** — every prior gate measured a
vertical or structural path. The hosted job already runs `swift test`, so the
*correctness and algorithmic-shape* guarantees were already enforced
(`ColumnAtQueryCountTests` bounds the `columnOffset` probe count and proves the
query dispatches to the native `columnIndex` search then never takes a linear scan,
with an event-log test pinning the exact dispatch order and proving the
blank/clamp/non-finite paths never search; `ColumnAtTests` covers the half-open
boundary, clamp, and `.empty` behavior; `ColumnAtEquivalenceTests` checks
`UniformColumnMetrics` against an independent closed-form oracle). What the unit
tests do **not** catch is a *runtime budget/latency* regression — a constant-factor
slowdown, an added allocation, or a cache-unfriendly change that preserves query
count and correctness but degrades wall-clock p95/p99. That was the enforcement
gap, and it is now closed: the brief's "benchmark gates block merge" principle now
holds for **all eight** latency paths, across **both** axes.

This also completes the project's established "functional slice adds a local gate →
promotion slice wires CI" rhythm for the **seventh** time (variable-height → Slice
15, variable-height-mutation → Slice 21, structural-mutation → Slice 24,
bulk-structural-mutation → Slice 26, line-query → Slice 28, line-geometry-query →
Slice 32, column-query → this slice). The change is fully in keeping with the
brief's hard constraints: it touches only workflow YAML and docs, introduces no
dependency, and leaves the Foundation-free core and all architecture invariants
untouched.

## Delivered Design

Merged Slice 34 diff (`9b954c5..0c674ea`):

```text
 .github/workflows/swift-ci.yml                     |   4 +
 AGENTS.md                                          |  12 +-
 .../2026-07-05-…-ci-gate-promotion.md (verification)| 410 ++++++++++++++++
 .../2026-07-05-…-ci-gate-promotion-design.md (spec) | 560 +++++++++++++++++++
 .../2026-07-05-…-ci-gate-promotion.md (plan)        | 247 +++++++++++
 5 files changed, 1228 insertions(+), 5 deletions(-)
```

### The workflow step (the core of the slice)

A single new step in the `host-tests-and-benchmark-gate` job, inserted between the
line-geometry-query gate and the memory-shape diagnostic
(`.github/workflows/swift-ci.yml:118`):

```yaml
      - name: Run column query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-query --gate
```

This is correct against every spec decision:

- **No `continue-on-error`** → it is a true blocking gate (Decision 1, one-shot
  promotion with no transient observation step). Confirmed by the fresh Ruby
  workflow-invariant assertion below and by step-level hosted evidence.
- **Invokes the executable-owned gate path** (`--column-query --gate`), not a
  YAML-duplicated threshold → budgets stay single-sourced in
  `Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift` (Decision 2).
- **Positioned after the line-geometry-query gate, before memory-shape** → all
  eight blocking latency gates stay contiguous and fail before lower-priority
  diagnostics (Decision 4). Verified by the assertion's `line-geometry-query <
  column-query < memory-shape` ordering check (hosted steps 14 → 15 → 16). This
  ordering also buys differential diagnosis: because `columnAt` is on a **separate
  axis** from the vertical queries, a line-query / line-geometry-query **pass** with
  a column-query **fail** localizes the regression to the horizontal path
  (`columnAt`, `columnOffset`, `columnIndex`) rather than to any shared vertical
  path.
- **Same `docs_only_pr != 'true'` guard** as every adjacent gate → docs-only PRs
  still skip it via the trusted lightweight path (Decision 6).
- **No `shell: bash` override** → a single one-line command with no pipes
  (Decision 7).
- **Required context names unchanged** (`Host tests and benchmark gate`,
  `iOS cross-target compile`, `WASM cross-target observation`) → the job becomes
  stricter without a ruleset or required-context change (Decision 5).

### No bundled hardening (the clean distinction from Slice 26)

This is what makes Slice 34 a *pure* promotion, like Slice 28 and Slice 32 and
simpler than Slice 26. The Slice 33 review found no actionable defect in the
column-query benchmark, and the benchmark builds its sample `x` values from
non-negative `sample % 8` / `sample % 1_000` arithmetic and the shared
`deterministicScrollOffset` helper — whose `(sample * 37) % 1_000` is a bounded
signed multiply returning a `Double` offset, never an array index. Its single
wrapping multiply (`variableAdvances`' `index &* 31`) is bounded
(`index <= 1_000_000`, so `<= 31_000_000`, no wrap) and feeds a `% 4` bucket
`switch`, never an array index. So the benchmark derives no array index from a
wrapping signed multiply and carries no analog of the `deterministicIndex` crash
class. The spec ("No bundled hardening") correctly scoped any code change out, and
the merged diff confirms it: **zero** lines of Swift changed. A fresh
`git diff --name-only 9b954c5..0c674ea -- Sources Tests Package.swift` is empty.

### `AGENTS.md` (durable guidance)

Two edits, both matching the spec's Documentation section:

- **Architecture paragraph** — the `columnAt` description previously ended
  "… `--column-query` is its **local** (not-yet-CI) gate." It now reads
  "`--column-query` is its blocking host-job CI gate" (`AGENTS.md:76`), retiring the
  local-only caveat now that the gate is hosted-blocking.
- **CI section** — the host-job bullet now lists `→ --column-query --gate
  (blocking)` after the line-geometry-query gate and before `--memory-shape`
  (`AGENTS.md:138`), and the "fail the job on perf regression" sentence now names
  the column-query gate alongside the other seven (`AGENTS.md:141-142`).

The command-list local invocation and the benchmark-flags lists already carried the
`--column-query` mode from Slice 33 and were correctly left unchanged. The
docs-only, iOS, WASM, ruleset, and bypass-caveat wording is unchanged. The
architecture paragraph's substantive description of `columnAt` (added in Slice 33)
is otherwise untouched, as it should be — Slice 34 changes the *governance* of the
path, not the path.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `0c674ea`)

- `git diff --name-only 9b954c5..0c674ea -- Sources Tests Package.swift` → **empty**
  (no core, provider, benchmark, test, or manifest surface touched).
- `git diff --check 9b954c5..0c674ea` → no output, exit `0` (no whitespace errors).
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- Ruby workflow-invariant assertion (step exists, invokes `--column-query --gate`,
  not `continue-on-error`, shares its siblings' docs-only guard, ordered
  `line-geometry-query < column-query < memory-shape`, three required job contexts
  unchanged) → `workflow_assertions_ok`, exit `0`.
- `swift build -c release` → `Build complete!` (exit 0).
- `swift test` → **189 tests, 0 failures**, plus the expected empty Swift Testing
  harness line (`0 tests in 0 suites`). Unchanged from the Slice 33 baseline, as
  expected for a slice that adds no test and changes no behavior.
- `swift run -c release ViewportBenchmarks -- --column-query --gate` → all five
  scenarios `gate=pass`, 0 failures; **all five checksums byte-identical** to the
  recorded baseline (`641440000`, `63985556480`, `639841600000`, `63985600000`,
  `639841560320`).
- `swift run -c release ViewportBenchmarks -- --line-query --gate` and
  `--line-geometry-query --gate` → all five scenarios each `gate=pass`; all
  checksums byte-identical to the record — confirming this slice touched no shared
  search/provider path.
- `swift run -c release ViewportBenchmarks -- --gate` → all three synthetic
  scenarios `gate=pass`; checksums match the record (`1319670707200`,
  `570448232307200`, `18852477646272000`).

### Fresh local column-query numbers (macOS arm64, this review)

| Scenario | p95 (ns) | Budget p95 | Headroom |
| --- | ---: | ---: | ---: |
| uniform_1k     | 16 | 30,000  | ~1,875× |
| uniform_100k   | 19 | 60,000  | ~3,158× |
| uniform_1m     | 25 | 120,000 | ~4,800× |
| prefixsum_100k | 42 | 60,000  | ~1,429× |
| prefixsum_1m   | 51 | 120,000 | ~2,353× |

Consistent with the Slice 33 review's recorded macOS numbers (run-to-run noise
aside); the timing rows are non-reproducible, but the five deterministic checksums
are byte-identical to the record, and every scenario sits well over ~1,400× under
budget locally.

### Hosted Linux x86_64 budget-fit (the load-bearing evidence for this slice)

Decision 3 bet that the macOS-calibrated budgets would hold on hosted Linux, with
the one-shot PR-head run **being** that evidence. The column-query benchmark had
**never run in hosted CI** before this slice (Slice 33 kept it local-only), so these
are the first hosted Linux x86_64 numbers for the mode (from PR-head run
`28818762407`, head `e55dfc0`):

| Scenario | macOS local p95 | PR-head p95 | Post-merge p95 | Budget p95 | Hosted headroom |
| --- | ---: | ---: | ---: | ---: | ---: |
| uniform_1k     | 16 | 26 | 24 | 30,000  | ~1,154× |
| uniform_100k   | 19 | 38 | 35 | 60,000  | ~1,579× |
| uniform_1m     | 25 | 44 | 40 | 120,000 | ~2,727× |
| prefixsum_100k | 42 | 55 | 57 | 60,000  | ~1,091× |
| prefixsum_1m   | 51 | 63 | 79 | 120,000 | ~1,905× |

Hosted Linux is slower than macOS arm64, exactly as in prior promotions, but far
less dramatically than the balanced-tree scenarios of the vertical gates — the
column providers do no tree descent. The `prefixsum_1m` **watch scenario** (spec
Decision 3 — the realistic proportional-advance path at the largest cell count)
clears its p95 budget by ~1,905× on the PR-head run; the numerically **tightest**
hosted headroom is `prefixsum_100k` at ~1,091×, still over a thousand-fold under
budget. This makes Slice 34 the **most generous promotion of the entire series**:
where Slice 26 (bulk) cleared its tightest hosted scenario at ~4.9×, Slice 28
(line-query) at ~244×, and Slice 32 (line-geometry-query) at ~815×, Slice 34's
tightest hosted scenario clears at ~1,091×. Decision 3's "stop and re-derive Linux
budgets" escape hatch was nowhere near triggered — the one-shot blocking promotion
was unambiguously the right call. All five checksums on both hosted runs equal the
local baseline, confirming the column query is deterministic across platforms.

### Hosted runs (verified live via `gh`, at step-log level not just job conclusion)

Both runs re-verified via `gh` during this review — and, per the project's "a green
job can hide a dead `continue-on-error` step" lesson, the new gate was checked at
the **step** level, not just the job conclusion:

- **PR #68 final-head run `28818762407`** (head `e55dfc0`, event `pull_request`):
  conclusion `success`; all three required jobs `success` (`Host tests and benchmark
  gate`, `iOS cross-target compile`, `WASM cross-target observation`). In the host
  job, step 5 `Complete docs-only PR` = `skipped` (correctly **not** docs-only — the
  PR changes workflow YAML, which the detector rejects before the Markdown allow
  rule), step 13 `Run line query benchmark gate` = `success`, step 14 `Run line
  geometry query benchmark gate` = `success`, **step 15 `Run column query benchmark
  gate` = `success`** (ran, not skipped, not `continue-on-error`), step 16 `Run
  memory shape diagnostic` = `success`, and step 18 `Observe realistic provider
  relative performance` ran `success` on the PR event.
- **Post-merge push run `28819411144`** on merge commit `2281f00` (event `push`,
  branch `main`): conclusion `success`; all three required jobs `success`. The host
  job again shows step 5 `Complete docs-only PR` `skipped`, steps 13–16 all
  `success` including **step 15 `Run column query benchmark gate` = `success`**, and
  step 18 realistic-provider observation correctly `skipped` on the `push` event (it
  is the PR-only `continue-on-error` observation). **This is the merged-code
  evidence anchor for Slice 34**: the new gate is a real blocking step that ran on
  merged code and passed, not a masked one. Merge parentage confirms `2281f00`'s
  second parent is `e55dfc0`, so the proof anchors the actually-merged head.

PR #69 was a docs-only follow-up touching only the verification record, so it
legitimately took the trusted docs-only path; the workflow YAML has not changed
since `2281f00`, so run `28819411144` still represents current `main`'s workflow
behavior.

## Git History

Reviewed Slice 34 commits (PR #68 → #69):

```text
fe0fcee docs: add column-query CI gate promotion design
8786041 docs: refine column-query CI gate promotion spec
09bfa77 docs: add column-query CI gate promotion implementation plan
30f0ac2 ci: promote column-query benchmark to a blocking hosted gate
9dc717f docs: document column-query gate as blocking in AGENTS.md
e55dfc0 docs: record local verification for column-query gate promotion
2281f00 Merge pull request #68 …
eee58ce docs: record slice 34 post-merge proof
0c674ea Merge pull request #69 …
```

Clean, incremental, one-logical-step-per-commit with correct conventional-commit
prefixes: `docs:` for spec/plan/guidance/verification, `ci:` for the single
workflow step. The spec took two rounds (`fe0fcee` add → `8786041` refine) before
the plan, the workflow change is isolated in its own `ci:` commit (`30f0ac2`), the
`AGENTS.md` doc update is separate (`9dc717f`), and local verification (`e55dfc0`)
is separate from implementation. The PR head is `e55dfc0`, exactly the head the
PR-head run `28818762407` tested — no post-head drift. The two-PR split
(implementation + local proof, then post-merge proof) is the standard pattern.

## Code Review Findings

Reviewing across workflow correctness, scope discipline, evidence integrity, and
policy concerns:

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, the gate is blocking and proven green at step level on
merged code, the scope is clean (zero Swift), and Foundation/core invariants are
intact.

### P2 / Production Readiness

None. The verification record carries **no evidence-accuracy defect**: at PR #68's
head (`e55dfc0`), the `Hosted Proof` section was an explicit
`Pending — recorded in the post-merge follow-up (Task 4) against the final stable
[head]` placeholder — no stale-on-write run IDs against a still-moving head — and
the real hosted run IDs (`28818762407`, `28819411144`) were added only in the
post-merge follow-up (PR #69, `eee58ce`, +61 lines to that one file) once the final
head was stable. The source-bearing PR #68 was never described as taking the
docs-only shortcut (the record explicitly notes it is *not* docs-only because it
changes workflow YAML). Decision 3's requested per-scenario headroom table is
present for all five scenarios both locally and hosted, closing the one narrative
gap the spec flagged in the Slice 32 twin.

### P3 / Minor But Valid

**1. Spec/implementation primitive-naming drift, still open (carried from Slice 25
P3 #3 / Slice 26 P3 #1 / Slice 28 P3 #1 / Slice 32 P3 #1).** The bulk-edits spec
names the join primitive `join(_:_:)` while the implementation ships `join3`/`join2`.
This is a provider-doc hygiene item unrelated to CI; Slice 34 touches no provider
source or spec, so it is correctly **not** a Slice 34 defect — but it remains an
open item with no home slice yet. A one-line cross-reference in the bulk-edits spec
would retire it whenever a provider-touching slice next opens.

No P3 changes whether the merged result is correct; #1 is pre-existing hygiene this
slice legitimately deferred.

## Risks And Gaps

### Both axes' mapping gates are now CI-protected — no governance debt remains

With this slice, all eight latency paths run under blocking hosted regression
protection: synthetic; static + mutating variable-height; single + bulk structural
mutation; the vertical position-query pair (`lineAt` since Slice 28,
`lineGeometryAt` since Slice 32); and now the horizontal within-line mapping query
(`columnAt`). There is **no remaining CI gap** forcing another governance slice; the
functional → gate-promotion cadence has drained for the seventh time. As after Slice
32, the next slice has no CI debt forcing its hand and is free to be a genuine
capability increment.

### The horizontal axis is CI-protected but not yet asymptotically optimal or geometry-bearing

Unlike the vertical axis at the Slice 32 handoff — which was *both* CI-protected
*and* asymptotically optimal on the balanced tree (Slices 29/30) *and*
geometry-bearing (`lineGeometryAt`, Slice 31) — the horizontal axis at this handoff
has only its **mapping** query, and that query is **fallback-bound**: both shipped
providers (`UniformColumnMetrics`, `PrefixSumColumnMetrics`) rely on the generic
`binarySearchColumnIndex` default, so the uniform case pays an O(log M) search where
an exact closed form would be O(1). This slice protects the current path against
regression; it does not improve its asymptotics, and there is no horizontal geometry
query (`columnGeometryAt`) or 2D composite (`pointAt`) yet. Those are the horizontal
axis's open capability distance — now measurable against this gate's `uniform_*` /
`prefixsum_*` scenarios, which is precisely what makes Options C/D/B (below) the
natural, gate-backed follow-ups.

### Budgets remain macOS-derived after this slice

Promotion confirmed the macOS budgets fit hosted Linux but did not re-derive
Linux-native budgets. That matches the standing project posture for all eight gates
and is acceptable. With eight latency gates now on hosted Linux, the accumulated
x86_64 evidence makes a dedicated Linux budget re-baseline viable future work
(Option E), explicitly out of scope here.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative observation
remains PR-only `continue-on-error`; the `Main` ruleset keeps its documented
bypass-actor shape (the admin user can still bypass required checks). None were in
scope for Slice 34.

## Lessons For The Next Slice

1. **The clean-evidence convention held again.** The recurring stale-on-write
   evidence defect (recording PR-head proof against a still-moving head, or
   mis-classifying a source-bearing PR as docs-only) stayed absent: Slice 34 left an
   explicit `Pending` placeholder in PR #68, recorded the hosted proof only in the
   post-merge follow-up (PR #69) against the stable final head `e55dfc0`, and
   explicitly flagged PR #68 as *not* docs-only. This is now the proven default for
   every source/workflow-touching slice — keep it.
2. **A pure promotion should stay pure.** Slice 26 correctly folded in a hardening
   because the prior review found a real latent crash class; Slices 28, 32, and now
   34 correctly did **not**, because their prior reviews found none. The spec
   explicitly justified zero Swift changes and the merged diff proves it. Resist
   bundling drive-by edits into a governance slice absent an evidence-backed reason.
3. **One-shot promotion is the right default across the entire headroom range.** The
   seven promotions now span ~4.9× (Slice 26, hosted) to ~1,091× (this slice,
   hosted) tightest-scenario headroom, and one-shot blocking succeeded at both
   extremes with Decision 3's stop-and-retune as the standing net. Reserve
   observe-then-block only for a genuinely thin-margin gate, not as default ceremony.
4. **Ground the watch-scenario claim in a per-scenario table.** The Slice 32 review
   noted its spec carried only an aggregate headroom range; Slice 34's spec
   (Decision 3) explicitly required the verification record to tabulate per-scenario
   observed p95 and headroom locally and hosted, and it did — so "`prefixsum_1m` is
   the one to watch" and "`prefixsum_100k` holds the least multiplicative headroom"
   are grounded in numbers, and any future Linux re-baseline starts from a recorded
   per-scenario baseline. Carry this table-first discipline into the next promotion.
5. **The functional → gate-promotion cadence has now completed seven full cycles,
   across both axes.** The CI/governance backlog opened by functional work is fully
   drained again. The engine is free to advance under complete regression protection
   — the next slice should be a genuine capability or infra choice, not more
   governance.

## Slice 35 Candidate Options

With Slice 34 the horizontal mapping query is now **CI-protected** (matching the
vertical axis since Slice 28), and there is **no governance debt** forcing the next
slice — the situation mirrors the Slice 32 debt-free handoff rather than the Slice
33 debt-reopening one. The difference from Slice 32 is that the *horizontal* axis
still has real capability distance ahead of it (it is fallback-bound and has no
geometry query), so the capability options are richer than they were then. The live
options (carried and re-anchored from the Slice 33 review):

### Option C: `columnGeometryAt` / caret-x (the tight 27→31 mirror)

The horizontal analog of Slice 31's `lineGeometryAt`: return the located cell's box
(left `x` + advance width) plus a within-cell fraction / caret `x`, composed over
`columnAt` with a constant number of extra `columnOffset` probes. Retires the
Slice 33 Decision 6 deferred sub-cell position. Smaller and lower-risk than B, the
exact 27→31 mirror, and a natural precursor to B. Its measuring gate
(`--column-query`, on the same providers) is, as of this slice, hosted-blocking, so
the composed geometry query would be built and measured on a CI-protected base.

### Option B: `pointAt(x:y:)` 2D composite (the product leap)

Compose the vertical (`lineAt` / `lineGeometryAt`) and horizontal (`columnAt`)
mapping primitives into a single point → (line, cell) hit-test over both metrics
sources. This is the biggest step toward realistic click-to-caret / selection on
large documents. Largest design surface; needs a fresh brainstorm + spec (how the
two independent sources compose, the combined result/clamp shape). Reads more
cleanly *after* C establishes horizontal geometry.

### Option D: closed-form / native column inverse (carried P3 / fallback-bound)

O(1) / native-descent overrides of `columnIndex` for `UniformColumnMetrics` and
`PrefixSumColumnMetrics`, boundary-safe against the equivalence oracle — the
horizontal mirror of the vertical Slices 29/30 native-descent work. Retires the
horizontal fallback-bound-provider item and is now directly measurable against this
slice's hosted `--column-query` gate. Small, clean; lower product value than C/B.

### Option E: standing infra (WASM blocking / Linux budget re-baseline)

Promote WASM cross-target from observational to blocking (gated on stable SDK
provisioning), or re-derive Linux-native budgets from the now eight-gate-deep
accumulated x86_64 evidence and retire the macOS-calibration caveat. Standing
hygiene; independent of the capability arc.

## Recommended Slice 35 Selection

**This is a genuine product call for the user, not a forced move.** Like Slice 32 —
and unlike Slices 28/33/34, each of which retired a specific CI-promotion debt —
Slice 34 leaves **no debt outstanding**, so Slice 35 is a direction choice among the
tight horizontal-geometry mirror (C), the larger 2D leap (B), the horizontal
native-descent cleanup (D), or standing infra (E).

My recommendation is to **surface the C-vs-B-vs-D product call to the user** and,
absent a stated preference, lean **Option C — `columnGeometryAt` / caret-x**. The
reasoning: the user has twice steered toward the horizontal capability direction
(Slice 32 review → Slice 33 `columnAt`, then Slice 33 review → this axis's gate),
and the vertical axis's proven sequence was *mapping → gate → geometry* (`lineAt`
Slice 27 → gate Slice 28 → `lineGeometryAt` Slice 31). Slice 34 just put the
horizontal axis at the exact point the vertical axis was after Slice 28, so the
rhythm-consistent next capability is the horizontal `lineGeometryAt` mirror — caret
geometry — which every real editor needs for cursor placement and which composes
directly toward `pointAt` (B). It is small, low-risk, and gate-backed by this very
slice.

Option B is the larger, higher-value leap but wants C's horizontal geometry
underneath it first (and a fresh brainstorm for how the two independent sources
compose), so it sequences naturally *after* C. Option D is the pick if the
preference is to retire the fallback-bound horizontal providers while the reasoning
is fresh — now cleanly measurable against this slice's gate — though it carries
lower product value than C. Option E is the pick if the preference is to close the
last standing infra item while the eight-gate hosted evidence is fresh. Whichever is
chosen, keep functional/capability work and CI/infra work in separate slices, per
the project's standing convention.

## Slice 34 Review Conclusion

Slice 34 delivered the intended governance increment cleanly: the `--column-query
--gate` benchmark now runs as the **eighth** blocking latency gate — and the
**first for the horizontal axis** — in the required host job, so runtime regressions
in `ViewportVirtualizer.columnAt` (the within-line inverse position-query introduced
in Slice 33) block merge, sitting contiguously after the line-geometry-query gate
and before the memory-shape diagnostic. The macOS-calibrated budgets held on hosted
Linux x86_64 with the **most generous margin of the series** (~1,091× under budget
at the tightest hosted scenario, versus Slice 32's ~815× and Slice 28's ~244×),
decisively validating the one-shot promotion and never approaching Decision 3's
escape hatch. The change is correctly scoped — **zero Swift changed** (no core,
provider, benchmark, test, or manifest surface; required contexts, docs-only
behavior, and ruleset all unchanged) — and verified at the step level on both the
final PR-head run (`28818762407`, head `e55dfc0`) and the post-merge push run
(`28819411144`, merge commit `2281f00`), with all five checksums byte-identical
across local, PR-head, and merged-code runs.

The review found **no P0, P1, or P2 issues** against the merged result, and **no
evidence-accuracy defect**: Slice 34 left an explicit `Pending` placeholder in the
source-bearing PR, recorded the PR-head proof only in the post-merge follow-up
against the stable final head, and delivered the per-scenario headroom table
Decision 3 required. The one open P3 (spec/code primitive-naming drift) is
pre-existing hygiene this slice legitimately deferred. With all eight latency gates
now CI-protected across both axes and **no governance debt remaining**, Slice 34
gives the horizontal axis its first hosted regression protection and hands off to a
genuine product call — Option C (`columnGeometryAt` caret-x, the tight 27→31 mirror,
now gate-backed), Option B (the `pointAt` 2D hit-test leap), Option D (horizontal
native-descent cleanup), or Option E (WASM-blocking / Linux budget re-baseline) —
for the user to direct.
