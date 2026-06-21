# Slice 25 Post-Slice Review

Date: 2026-06-21

## Scope Reviewed

This review covers Slice 25: **bulk / range structural edits**. It is a
functional-core slice that adds true-bulk `insertLines(at:heights:)` and
`removeLines(at:count:)` to `BalancedTreeLineMetrics` (the Slice 23
size-balanced order-statistics BST and the only structural-mutation provider),
each implemented in **O(k + log N)** via join-based split/join primitives rather
than the O(k·log N) compose-the-single-line-ops wrapper. It proves them with an
array oracle, a bulk-equals-compose oracle, a tree-height invariant, a strict
visit-count bound, an arena-slot-reuse test, a mixed bulk/single equivalence
oracle, and a re-layout composition test against the stateless core; and it adds
a **local** `--bulk-structural-mutation` benchmark gate. This was the user's
Slice 23/24 Option A pick, with the **true-bulk** algorithm chosen over the
compose-only wrapper.

The slice was delivered through **two** PRs, both now merged:

- PR #41 (`slice-25-bulk-structural-edits`), title *"Slice 25: Bulk structural
  edits"*, final head `2f738cd`, merged to `main` as
  `0db88f5876fa25f76822afb8ffaf60bfbef85042` at `2026-06-21T06:43:28Z` — the
  implementation, tests, benchmark, `AGENTS.md` update, spec, plan, and
  verification record (with PR-head proof).
- PR #42 (`slice-25-post-merge-verification`), title *"Slice 25: record bulk
  structural edits post-merge proof"*, head `a3687e2`, merged as
  `4b9bc10a95f7a4f2f7816cc46f90cfc6e4d2e76b` (current `main` HEAD) at
  `2026-06-21T06:53:25Z` — the docs-only follow-up that filled the post-merge
  push proof.

**Both PRs are merged at review time**, so `main`'s verification record carries
real hosted run IDs rather than `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-20-bulk-structural-edits-design.md`
- `docs/superpowers/plans/2026-06-20-bulk-structural-edits.md`
- `docs/superpowers/verification/2026-06-20-bulk-structural-edits.md`
- `docs/superpowers/reviews/2026-06-20-slice-24-post-slice-review.md`
- `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift` (bulk
  additions)
- `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`
  (bulk tests)
- `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift`,
  `BenchmarkOptions.swift`, `BenchmarkProgram.swift`, `SyntheticBenchmarks.swift`
- `AGENTS.md` (commands + flags)
- PR #41 / #42 metadata, hosted run evidence (step-level logs), merge parentage,
  and the merged Slice 25 diff

The reviewed Slice 25 range (PR #40 merge base → current `main` HEAD) is:

```text
cb12fd92e7b6…  ..  4b9bc10a95f7…
```

The implementation itself lands in PR #41 (`cb12fd9..2f738cd`). The diff is
deliberately confined to `Sources/TextEngineReferenceProviders`,
`Sources/ViewportBenchmarks`, `Tests/TextEngineReferenceProvidersTests`,
`AGENTS.md`, and `docs/**`. It does **not** touch `Sources/TextEngineCore`,
`Package.swift`, `.github/**`, `FenwickLineMetrics`, or `PrefixSumLineMetrics` —
confirmed below by a fresh name-only diff.

## Product Brief Alignment

The brief requires stable performance on 100k+ line / >10 MB documents and bans
frame hitches under realistic editing. Before this slice, the only structural
edits on the mutable provider were **single-line**; a multi-line paste or
range-delete had to loop them at O(k·log N) — e.g. a 4,096-line paste into a 1M
document was ~4,096 × the single-op cost. Slice 25 adds an **atomic, batched**
insert/delete-range API at O(k + log N): the inserted run is built as a balanced
subtree in O(k) and spliced with O(log N) tree restructuring, so a large paste or
range delete is now cheap and the stateless core re-layouts over the result with
unchanged O(log N) query behavior.

Crucially, `TextEngineCore` is **completely unchanged** — confirmed by an empty
`git diff --name-only cb12fd9..2f738cd -- Sources/TextEngineCore`. The bulk edit
is a pure provider capability; the core stays stateless and generic over
`LineMetricsSource`, and the re-layout composition test proves the core composes
correctly with the bulk-mutated provider without a core change. This is exactly
the architecture invariant the brief and AGENTS.md require.

This slice also re-opens the established cadence: a **functional** slice that adds
a **local** gate, with the **CI promotion** deliberately deferred to a follow-on
slice (named Slice 26 in the spec's Non-Goals), mirroring the
variable-height → promotion, vh-mutation → promotion, and
structural-mutation → promotion (Slice 24) rhythm.

## Delivered Design

Merged Slice 25 diff (`cb12fd9..2f738cd`):

```text
 AGENTS.md                                          |  13 +-
 .../BalancedTreeLineMetrics.swift                  | 160 ++++
 Sources/ViewportBenchmarks/BenchmarkOptions.swift  |  11 +-
 Sources/ViewportBenchmarks/BenchmarkProgram.swift  |   2 +
 .../BulkStructuralMutationBenchmark.swift          | 187 ++++
 .../ViewportBenchmarks/SyntheticBenchmarks.swift   |   2 +
 .../BalancedTreeLineMetricsTests.swift             | 289 +++++++
 .../plans/2026-06-20-bulk-structural-edits.md      | 948 +++++++++++++++++++++
 .../2026-06-20-bulk-structural-edits-design.md     | 435 ++++++++++
 9 files changed, 2041 insertions(+), 6 deletions(-)
```

### The bulk algorithm (the core of the slice)

The two public methods are thin, validate-then-mutate wrappers over five private
primitives:

- `buildBalancedRun(heights)` — a perfectly balanced subtree from `k` heights in
  O(k), recursive midpoint split, **allocating every node through
  `allocateNode`** so it consumes recycled `freeList` slots first. This is the
  load-bearing choice the spec called out: reusing `init`'s `freeList`-bypassing
  `buildBalanced` would have leaked the slots `removeLines` recycles and let the
  arena grow unbounded under churn. The implementation correctly uses the
  allocation-aware builder.
- `split(t, at:)` — recursive position-split that recombines off-path subtrees
  with `join3` as the recursion unwinds.
- `join3(L, m, R)` — the one balancing primitive: a weight-aware 3-way join with
  a known junction node `m`, using `canRoot` to decide where to graft and the
  existing `maintain` to restore local balance on the way up.
- `join2(L, R)` — derived: detaches the min of `R` as the junction and calls
  `join3`.
- `detachMin(t)` — **non-recycling** leftmost-node extractor (distinct from the
  deletion-path `removeMin`, which recycles to `freeList`); supplies the junction
  node for `join2` so no node is freed/allocated during a join.
- `recycleSubtree(t)` — **iterative (explicit stack)** push of every removed node
  slot onto `freeList`. The iterative form is the right call: it avoids recursion
  depth blowing up on a large range delete.

Then `insertLines = buildBalancedRun + split + join2∘join2` and
`removeLines = split + split + recycleSubtree + join2`. Both validate **all**
preconditions before any mutation (atomic), short-circuit the empty batch to a
zero-visit no-op, and record node visits in the existing `lastMutationNodeVisits`.

The integer-overflow-safe precondition shape the spec specified is implemented
correctly: `removeLines` is written as `count <= lineCount - index`, **not**
`index + count <= lineCount`, so an adversarial near-`Int.max` input cannot trap
on overflow before the intended precondition message fires.

The two new white-box diagnostics (`arenaNodeCount`, `freeSlotCount`) are
correctly `internal` (reached via `@testable import`, not public API) and expose
only slot bookkeeping, never tree shape.

### Tests (10 new behaviors, TDD failing-first)

All ten Component-Design test behaviors landed:
array-oracle correctness for insert and remove at head/tail/interior across
k ∈ {1, 8, 5000}; bulk-equals-loop-of-single-ops; empty-batch / insert-into-empty
/ remove-to-empty edges; strictly-increasing offsets; the **tree-height
invariant** after 200- and 300-step bulk churn (`treeHeight ≤ 3·(⌊log₂N⌋+1)`) —
the direct balance gate the spec flagged as the primary risk; the **strict
visit-count bound** `visits ≤ k + 12·(⌊log₂N⌋+1)` *and* `visits < k·(⌊log₂N⌋+1)`
on N = 1k/100k/1M (which fails for an O(k·log N) compose or O(k+log²N)
non-telescoping split); the **arena-slot-reuse** test (arena does not grow across
10 equal-size remove/insert cycles); the mixed bulk/single 1,500-step
equivalence oracle; and the re-layout composition test (bulk edit → core
`compute` + `geometry` equals a fresh `PrefixSumLineMetrics`, with a counting
wrapper asserting the core still issues O(log N) offset queries).

### Benchmark mode

`--bulk-structural-mutation` (output name `bulk_structural_mutation`,
`balanced_tree` provider) runs **five** scenarios over 1k/100k/1M docs in two
batch profiles — small `K=64` (typical paste/selection) and large `K=4096` (large
paste / range delete), the profile that motivates the whole slice. Each measured
operation pins `lineCount` constant by pairing a `removeLines(K)` with an
`insertLines(K)` at deterministic positions, then runs `compute` + a full geometry
traversal; a running checksum consumes `lastMutationNodeVisits`, the range, and
the geometry to defeat dead-code elimination. `--gate` is valid with the mode,
mutually exclusive with other modes, and the budgets are tight enough that a
regression to compose-level cost would blow them by ~50× (the large-paste claim
has teeth). The mode is correctly wired into `BenchmarkOptions`/`BenchmarkProgram`
and `SyntheticBenchmarks` only gained the exhaustive `.bulkStructuralMutation`
precondition branch.

### `AGENTS.md` (durable guidance)

The Commands block gains the `--bulk-structural-mutation --gate` local-gate line;
the benchmark-flags note and the `--gate` validity list both add the new mode.
The CI section is untouched — correct, since this slice deliberately does **not**
wire the gate into CI.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged `main` at `4b9bc10`)

- `swift test` → **107 tests, 0 failures** (the `BalancedTreeLineMetricsTests`
  suite is now 32 tests, up from 13; plus the expected empty Swift Testing
  `0 tests in 0 suites` line). Up from the Slice 24 90-test baseline, consistent
  with 10 new bulk behaviors and their parametrized cases.
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `git diff --check cb12fd9..HEAD` → no output, exit `0`.
- `git diff --name-only cb12fd9..2f738cd -- Sources/TextEngineCore Package.swift .github`
  → **empty** (no core, manifest, workflow, or script surface touched).
- `./.github/scripts/cross-target-compile.sh --self-test` → `self_test=pass`.
- `swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate`
  → all five scenarios `gate=pass`, with comfortable headroom (table below). The
  emitted checksums are bit-identical to the recorded runs, confirming the bulk
  path is deterministic.

### Fresh local bulk-gate numbers (macOS arm64, this review)

| Scenario | p95 (ns) | Budget p95 | Headroom |
| --- | ---: | ---: | ---: |
| 1k_lines_batch_64 | 3,885 | 60,000 | ~15× |
| 100k_lines_batch_64 | 11,817 | 150,000 | ~12.7× |
| 1m_lines_batch_64 | 60,049 | 400,000 | ~6.7× |
| 100k_lines_batch_4096 | 77,617 | 1,500,000 | ~19× |
| 1m_lines_batch_4096 | 191,369 | 2,500,000 | ~13× |

Even the tightest path (1M, K=64) sits ~6.7× under budget locally. The
heaviest absolute workload (1M, K=4096) is ~0.19 ms/op — proving cheap bulk
re-layout on the largest document.

### Hosted runs

- **PR #41 implementation run `27895095147`** (head `ebb8424`): all three required
  jobs `success` — the run recorded in the verification doc.
- **PR #41 final-head run `27895264320`** (head `2f738cd`, the actual merged
  head): all three required jobs `success`, and the host job ran the **full heavy
  path** (step 5 `Complete docs-only PR` = `skipped`; steps 7–14 ran host tests +
  all four blocking latency gates + memory/RSS diagnostics + the PR-only realistic
  observation). See the PR-head-proof wrinkle below.
- **Post-merge push run `27896284202`** on merge commit `0db88f5` (event `push`):
  all three required jobs `success`. Step-level conclusions for the host job:
  steps 7–13 (`Run host tests` → `Run RSS memory observation diagnostic`) all
  `success`, step 5 (`Complete docs-only PR`) and step 14 (realistic observation,
  PR-only) `skipped`. **This is the merged-code evidence anchor for Slice 25.**

Consistent with the slice's Non-Goals, the new `--bulk-structural-mutation` gate
is **not** wired into CI — the post-merge host job runs the four pre-existing
blocking gates, not the bulk gate. Hosted regression protection for the bulk path
is deferred to Slice 26.

### The PR-head proof wrinkle (this slice's one notable defect)

PR #41 carries Swift source, so its full base→head diff is **never** docs-only;
every push to it runs the heavy path. The verification doc's "Hosted PR-Head
Proof" section records the proof against head `ebb8424` / run `27895095147`. But
committing that very proof doc produced a **new** head `2f738cd` (the actual
merged head) and a fresh CI run `27895264320`. So:

1. The recorded PR-head SHA (`ebb8424`) is **stale-on-write** — it is the commit
   *before* the doc that records it, and is not the merged head. This is the same
   stale-on-write hazard the Slice 24 review documented (it cost Slice 24 a third
   correction PR, #39).
2. The doc additionally states the final head "received the required contexts
   through the trusted docs-only shortcut (`mergeStateStatus=CLEAN`)." This is
   **factually wrong**: run `27895264320` on `2f738cd` ran the full heavy path
   (verified at step level above — `Complete docs-only PR` was `skipped`, and the
   benchmark gates and host tests all ran). The docs-only detector compares the
   *full* PR diff, which includes Swift source, so PR #41 could never take the
   shortcut. The author appears to have conflated "this commit only edits docs"
   with "the PR's docs-only detector will shortcut," which AGENTS.md explicitly
   distinguishes.

This does **not** undermine the merged-code proof: the post-merge push run
`27896284202` on `0db88f5` is the correct, heavy-path, merged-code anchor and is
recorded accurately. The defect is confined to the verification doc's PR-head
subsection — a stale anchor SHA plus an inaccurate explanatory sentence — and is
tracked as the P2 finding below.

## Git History

Reviewed Slice 25 commits (PR #41 → #42):

```text
f2789b5 docs: add bulk structural edits design
44f7c26 docs: address spec review for bulk structural edits
082df56 docs: add bulk structural edits implementation plan
e5fc080 feat: add O(k + log N) bulk insertLines to BalancedTreeLineMetrics
2d085ac feat: add O(k + log N) bulk removeLines with slot recycling
d80e955 test: cover mixed bulk/single edits and bulk re-layout composition
c7a4bf4 feat: add --bulk-structural-mutation benchmark with local gate
6e780d5 docs: document --bulk-structural-mutation gate command
ebb8424 docs: record bulk structural edits verification
2f738cd docs: record PR-head proof for bulk structural edits
0db88f5 Merge pull request #41 …
a3687e2 docs: record bulk structural edits post-merge proof
4b9bc10 Merge pull request #42 …
```

Clean, incremental, one-logical-step-per-commit with correct conventional-commit
prefixes: `docs:` for spec/plan/guidance/verification, `feat:` for the two bulk
ops and the benchmark, `test:` for the integration tests. The spec→plan→implement
→benchmark→doc→verify→post-merge ordering matches the established slice lifecycle.
The two-PR split (implementation+PR-head proof, then post-merge proof) is the
standard pattern; unlike Slice 24 it did not need a third correction PR — though
the PR-head proof it carries has the accuracy defect noted above.

## Code Review Findings

Reviewing across algorithm correctness, balance preservation, scope discipline,
evidence integrity, and benchmark robustness:

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, fully tested (107 green, including the balance and
strict-visit-bound gates), Foundation-free, correctly scoped, and the core is
untouched.

### P2 / Production Readiness

**1. The merged verification record's PR-head proof is stale and mis-described.**
As detailed above, the "Hosted PR-Head Proof" section anchors `ebb8424` /
`27895095147`, but the actual merged head is `2f738cd` / run `27895264320`, and
the doc wrongly claims the final head took the docs-only shortcut when it in fact
ran the full heavy path. The merged-code anchor (post-merge run `27896284202`) is
correct, so the *code* is properly proven — but `main` now carries an inaccurate
evidence statement. **Fix applied in this PR:** the verification doc's PR-head
subsection gains a clearly-marked correction that re-anchors the proof to the true
merged head `2f738cd` / run `27895264320` (verified heavy-path at step level) and
strikes the incorrect "docs-only shortcut" claim, while retaining the still-valid
`ebb8424` / `27895095147` block for that earlier commit. After this correction
`main`'s record is accurate.

### P3 / Minor But Valid

**2. Benchmark index arithmetic can underflow to a negative index at larger
sample counts.** `runBulkStructuralMutationScenario` computes
`removeIndex = (sample &* 2_654_435_761) % (lineCount - batch + 1)` (and the
analogous `insertIndex` with `40_503`). The wrapping multiply `&*` will produce a
**negative** product once `sample * constant` exceeds `Int.max`, and Swift's `%`
preserves the dividend's sign, so `removeIndex` could go negative and trip the
`index >= 0` precondition (a crash). At the current parameters this is **latent,
not live**: the largest sample index is `2000 × 256 − 1 = 511,999`, giving a
product of ~1.36e15 ≪ `Int.max` (~9.2e18), so all five scenarios stay positive —
which is why the gate runs clean. But the safety margin is implicit in the loop
bounds; a future bump to `iterations`/`operationsPerSample` could silently cross
the overflow threshold. Cheap hardening: do the mixing in `UInt`
(`Int(UInt(bitPattern: sample &* constant) % UInt(modulus))`). Non-blocking;
benchmark-only.

**3. Spec/implementation primitive-naming drift (cosmetic).** The spec names the
join primitive `join(_:_:)`; the implementation ships `join3` (the weight-aware
junction join) and `join2` (the detachMin-derived 2-way join). The split is
faithful and arguably clearer than the spec's single-`join` sketch, but the
vocabulary differs. A one-line note in the spec or a doc-comment cross-reference
would keep the design doc and code in sync for the next reader. No behavioral
impact.

None of P2/P3 changes whether the merged result is correct; #1 is an evidence
accuracy fix and #2/#3 are hardening/hygiene.

## Risks And Gaps

### Bulk path has no CI regression protection yet

The `--bulk-structural-mutation` gate is **local-only** this slice (by design —
Non-Goals). The provider just gained a new hot path (the heaviest benchmark
workload in the suite, 1M × K=4096) with no hosted gate guarding it. This is the
single open gap and is exactly what Slice 26 is teed up to close. Until then, a
bulk-path perf regression would not fail CI.

### Budgets are macOS-calibrated, untested on hosted Linux

The five bulk budgets were set from macOS arm64 observations plus headroom, like
every other gate before its promotion. Hosted Linux is historically slower and
noisier (Slice 24 saw the structural 1M p95 range 34.6k–54.0k vs ~33–39k locally).
The bulk budgets carry 6.7×–19× local headroom, so they are very likely to fit
Linux, but that is unproven until Slice 26 runs them hosted. The 1M × K=64 path
(tightest at ~6.7×) is the one to watch.

### Join-induced balance is proven, not assumed — but only to host depth

The spec's primary risk (grafting a whole subtree during `join` is outside SBT's
single-step amortized model) is directly mitigated by the tree-height invariant
tests after 200/300-step churn, which pass at `≤ 3·(⌊log₂N⌋+1)`. The documented
spine-rebuild fallback was never needed. Solid. The new code is Foundation-free
and Embedded-style (arrays + `Int`/`Double`, no ARC), and rides the existing iOS
(blocking) / WASM (observational) cross-target coverage for
`TextEngineReferenceProviders` — but, as with the rest of the provider, it is not
independently Embedded-proven this slice.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative
observation remains PR-only `continue-on-error`; the `Main` ruleset keeps its
documented bypass-actor shape. None were in scope for Slice 25.

## Lessons For The Next Slice

1. **The Slice 24 stale-on-write hazard recurred — and was not caught this time.**
   Slice 24's review explicitly warned that a verification commit moves its own
   PR head, and recommended either recording the PR-head proof only after the
   final content commit or splitting it into the post-merge PR. Slice 25 still
   recorded the proof against the pre-final commit *and* added an incorrect
   "docs-only shortcut" explanation. **Adopt the convention concretely:** for any
   PR, record the PR-head proof only in the post-merge follow-up PR (where the
   final head SHA is known and stable), and never describe a source-bearing PR's
   head as taking the docs-only path — the detector reads the full diff. This
   removes both the stale-SHA churn and the misclassification in one move.
2. **The true-bulk split/join bet paid off with margin.** The O(k + log N) claim
   is enforced by a strict visit-count bound (not prose), balance is enforced by a
   height invariant after churn, and both hold with the tree never needing the
   spine-rebuild fallback. The join-based framework is now a proven tool in this
   provider; future range operations (e.g. range `setHeight`, move/cut-paste) can
   reuse `split`/`join2`/`join3` directly.
3. **The functional → promotion cadence has a fresh open gate.** Just as Slice 23
   left the structural-mutation gate local until Slice 24 promoted it, Slice 25
   leaves the bulk gate local. The analogous precondition now applies: promote the
   bulk gate before the next bulk-path functional change.
4. **Benchmark index mixing should use unsigned arithmetic.** The `&*`-into-`%`
   pattern is a latent negative-index trap; standardize on `UInt` mixing for
   deterministic index generation in benchmarks so a future iteration-count bump
   can't crash the gate.

## Slice 26 Candidate Options

### Option A: Promote `--bulk-structural-mutation` to a blocking hosted gate

The explicitly teed-up cadence pick (named in this slice's Non-Goals as Slice 26).
Wire `--bulk-structural-mutation --gate` into the required `Host tests and
benchmark gate` job as a fifth blocking latency gate, with Linux-fit budgets
derived from a one-shot (or observe-then-block) hosted run. Closes the single open
regression-protection gap, is low-risk/high-readiness, and completes the
functional → promotion rhythm a fourth time. Confined to
`.github/workflows/swift-ci.yml` + `AGENTS.md` + docs (and possibly a budget
retune in `BulkStructuralMutationBenchmark.swift` if Linux forces it). The heaviest
workload yet (1M × K=4096) makes the hosted-fit check more load-bearing than the
prior three promotions — observe-then-block may be the safer call here rather than
one-shot.

### Option B: Advance the next real engine capability

Move beyond vertical-only layout toward the next brief capability — width/wrap-aware
metrics, a horizontal axis, or position-query APIs such as `lineAt(y:)`. Highest
product value, largest scope; needs a brainstorm + spec to pin the increment. The
strongest pick if the goal is product momentum over rounding out the provider's
edit API.

### Option C: Promote WASM cross-target to blocking

The long-deferred (Slice 22 Option A) infra item: provision a pinned,
version-matched WASM Swift SDK in the hosted job, prove it stably green, then flip
WASM from observational to blocking for both packages. Infra-gated on stable SDK
provisioning.

### Option D: Linux-native budget re-baseline

With four (soon five) latency gates on hosted Linux, re-derive Linux-native
budgets from accumulated x86_64 evidence and retire the macOS-calibration caveat.
Low product value, useful hygiene; cleanest if folded into Option A's hosted run.

### Option E: Re-express single-line ops over split/join

The spec left `insertLine`/`removeLine` untouched. They could be re-expressed as
`insertLines`/`removeLines` of size 1 to unify the structural paths, but only if it
does not regress the `--structural-mutation` gate. Low value, internal tidiness.

## Recommended Slice 26 Selection

Recommended Slice 26 is **Option A — promote the `--bulk-structural-mutation`
gate to a blocking hosted gate**.

The reasoning: Slice 25 deliberately shipped the bulk path with **local-only**
regression protection, exactly as Slice 23 shipped the structural-mutation gate
before Slice 24 promoted it. That is the one open gap from this slice, the spec
itself names the promotion as Slice 26, and the project's "functional slice adds a
local gate → promotion slice wires CI" cadence is the established way to close it.
It is low-risk and high-readiness — the only real unknown is whether the
macOS-calibrated budgets fit hosted Linux, and the 6.7×–19× local headroom makes
that very likely (with observe-then-block as the safe path for the heaviest 1M ×
K=4096 scenario). Promoting now keeps the provider's full edit surface under CI
regression protection before any further bulk-path functional change.

If the preference is instead product momentum over closing the gate, **Option B
(next engine capability)** is the higher-ceiling alternative — but it leaves the
bulk path unguarded in CI and needs its own brainstorm + spec. Given the user has
favored functional work recently and the cadence is mid-cycle, Option A is the
consistent next step; the A-vs-B call is a genuine product decision worth
surfacing to the user.

Separately, the **P2 verification-record correction** (re-anchor the PR-head
proof to `2f738cd` / `27895264320` and remove the "docs-only shortcut" claim) is
applied in this same post-slice-review PR, so `main`'s evidence record is accurate
once this PR merges.

## Slice 25 Review Conclusion

Slice 25 delivered its intended functional increment: `BalancedTreeLineMetrics`
gained atomic, O(k + log N) bulk `insertLines`/`removeLines` built on a clean
join-based split/join framework, with arena slots recycled across churn so the
arena does not grow. The win is **enforced, not asserted** — a strict visit-count
bound catches an O(k·log N) or O(k+log²N) regression, a tree-height invariant
catches a balance failure after heavy churn, oracle and bulk-equals-compose tests
catch any correctness drift, and a re-layout test proves the stateless core
composes with the bulk-mutated provider with unchanged O(log N) query behavior and
**zero core change**. The slice is correctly scoped (no core, manifest, CI, or
script surface), Foundation-free, and the new local bulk gate passes with
6.7×–19× headroom on the largest documents in the suite.

The review found **no P0 or P1 issues**. The one P2 is an evidence-accuracy
defect in the merged verification record — a stale-on-write PR-head SHA plus an
incorrect "docs-only shortcut" claim (the final head actually ran the full heavy
path, run `27895264320`); the merged-code anchor (post-merge run `27896284202`)
is correct, so the code itself is fully proven, and this review records the true
final-head run. Two P3 items (a latent negative-index trap in benchmark index
mixing, and spec/code primitive-naming drift) are hardening/hygiene. With the bulk
path now in place but only locally gated, Slice 25 hands off cleanly to its
teed-up promotion slice — Slice 26, wiring `--bulk-structural-mutation` into the
blocking hosted gate with Linux-fit budgets.
