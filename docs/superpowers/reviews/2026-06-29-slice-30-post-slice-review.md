# Slice 30 Post-Slice Review

Date: 2026-06-29

## Scope Reviewed

This review covers Slice 30: **compute-native prefix search**. It extends the
provider-native prefix-search hooks Slice 29 introduced for
`ViewportVirtualizer.lineAt` into `ViewportVirtualizer.compute(_:metrics:)` — the
variable-height viewport query that runs on every scroll. Over a
`BalancedTreeLineMetrics` provider, both of `compute`'s monotone boundary searches
are now a single O(log N) subtree-sum descent instead of the generic O(log²N)
binary search over O(log N) `offset(ofLine:)` probes. It was the Slice 29 review's
recommended Option A (and that review's explicitly-deferred Decision 4), and the
user-selected direction.

Like Slice 29, this slice is **functional and adds no new gate**: the paths it
optimizes are already under blocking hosted gates — `--structural-mutation --gate`
and `--bulk-structural-mutation --gate` drive `compute` over a balanced-tree
provider — so the win is measurable against existing gates and there is no
governance follow-up to schedule.

The change follows the exact Slice 29 shape — a defaulted protocol requirement
plus a provider override — applied to the second (end-exclusive) boundary:

- `LineMetricsSource` gains a second defaulted requirement
  `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`, declared **in the protocol
  body** so the generic `compute` reaches a conformer override through the witness
  table. Its default is the generic narrowed binary search, so every existing
  conformer stays source-compatible and behavior-identical.
- `compute`'s visible-start search is rerouted through the **existing** Slice 29
  hook `lineIndex(containingOffset:)`; its visible-end search through the new hook,
  with the `lowerBound` (= visible start) narrowing hint preserved and forwarded.
- The end-exclusive binary-search loop is extracted to one internal helper
  (`firstLineIndexAtOrAbove`) shared by the default hook and `compute`'s
  `firstLineTopAtOrAbove` wrapper, so the fallback path and `compute` cannot drift
  on the `>=` boundary convention — mirroring the Slice 29 `binarySearchLineIndex`
  extraction.
- `BalancedTreeLineMetrics` overrides the new hook with one iterative,
  non-mutating, allocation-free descent over its existing `subtreeHeightSum` /
  `subtreeCount`, with the boundary rule flipped to end-exclusive.

The slice was delivered through **two** PRs, both now merged:

- PR #56 (`slice-30-compute-native-prefix-search`), title *"Slice 30:
  compute-native prefix search"*, final head
  `5c142b67fe53f494872534d3097fed004cb4c313` (`5c142b6`), merged to `main` as
  `fac19d6cdd81569b0a66a14ac108751b917e63cb` (`fac19d6`) by `maldrakar` at
  2026-06-29T12:26:59Z — the core hook, the visible-start/visible-end rerouting,
  the provider override, the tests, the doc updates, and the verification record's
  local + PR-head + hosted sections.
- PR #57 (`slice-30-post-merge-verification`), title *"Record Slice 30 post-merge
  proof"*, merged as `c31c4775184988eeca99c2be0e2cbd3422cb5a7d` (`c31c477`,
  current `main` HEAD) by `maldrakar` at 2026-06-29T13:07:04Z — the docs-only
  follow-up (`9e4ad02`) that replaced the verification record's `Pending`
  post-merge anchor with the real merged-code push run.

**Both PRs are merged at review time**, so `main`'s verification record carries
real hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-27-compute-native-prefix-search-design.md`
- `docs/superpowers/plans/2026-06-27-compute-native-prefix-search.md`
- `docs/superpowers/verification/2026-06-27-compute-native-prefix-search.md`
- `docs/superpowers/reviews/2026-06-27-slice-29-post-slice-review.md`
- `Sources/TextEngineCore/LineMetricsSource.swift`,
  `Sources/TextEngineCore/VariableViewportVirtualizer.swift`
- `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- `Tests/TextEngineCoreTests/ComputeNativePrefixSearchTests.swift`,
  `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`
- `AGENTS.md`, `.gitignore`
- PR #56 / #57 metadata, hosted run evidence (step-level conclusions), merge
  parentage, and the merged Slice 30 diff

The reviewed Slice 30 range (PR #55 merge base → current `main` HEAD), excluding
this review document itself, is:

```text
a98d29a..c31c477
```

`git merge-base a98d29a c31c477` returns `a98d29a`, confirming the Slice 29 review
merge (PR #55, `a98d29a`) is a clean ancestor and the range captures exactly the
Slice 30 work.

## Product Brief Alignment

The brief requires a headless layout/virtualization core that supports stable
scrolling over 100k+ line / >10 MB documents, keeps core-owned memory from scaling
linearly with document size, stays Foundation-free and zero-dependency, and
compiles for iOS and WASM without source changes, with regression benchmarks
blocking merge on degradation.

Slice 29 made the balanced-tree **`lineAt`** path a single O(log N) descent but
explicitly left `compute` on O(log²N) (its Decision 4: the visible-end search has
end-exclusive "first top at or above" semantics needing a different provider
primitive). `compute` is the *most-exercised* query — it runs on every viewport
recomputation — so it was the highest-value remaining vertical optimization.

Slice 30 closes that gap without widening the consumer-facing surface:
`compute`'s public signature and the `ViewportComputation` / `VirtualRange` /
clamp / `isAtTop` / `isAtBottom` / empty / failure semantics are all unchanged. It
deepens the core/provider composition so the data structure's full capability is
used on the scroll hot path. It honors every hard constraint: the core stays
Foundation-free (both scans empty), no dependency is added, the native descent
allocates nothing and adds no core-owned memory (O(1) core memory preserved), and
the public-protocol change is cross-target verified for iOS (blocking) and WASM
(observational).

With this slice, **both** vertical queries (`lineAt` and `compute`) are now
asymptotically optimal over a balanced-tree provider. The vertical-axis
optimization arc that ran Slice 27 (add `lineAt`) → Slice 28 (gate it) → Slice 29
(`lineAt` native) → Slice 30 (`compute` native) is complete.

This is the **second** consecutive functional slice that reuses existing gates
rather than adding one, so — like Slice 29 — it carries **no CI-promotion debt**
forward: the optimized paths are already blocking-gated by the
structural/bulk-structural mutation gates.

## Delivered Design

Merged Slice 30 diff (`a98d29a..c31c477`):

```text
 .gitignore                                          |   1 +
 AGENTS.md                                           |  21 +-
 Sources/TextEngineCore/LineMetricsSource.swift      |  45 +
 Sources/TextEngineCore/VariableViewportVirtualizer.swift | 20 +-
 Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift | 42 +
 Tests/TextEngineCoreTests/ComputeNativePrefixSearchTests.swift | 147 ++
 Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift | 162 ++
 docs/.../2026-06-27-compute-native-prefix-search.md (plan)        | 708 +
 docs/.../2026-06-27-compute-native-prefix-search-design.md (spec) | 462 +
 docs/.../2026-06-27-compute-native-prefix-search.md (verification)| 378 +
 10 files changed, 1961 insertions(+), 25 deletions(-)
```

### The second defaulted hook (the API decision, Decision 2)

`LineMetricsSource` gains a requirement declared **in the protocol body** with a
default in an extension (`Sources/TextEngineCore/LineMetricsSource.swift`):

```swift
    func firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int
}

extension LineMetricsSource {
    public func firstLineIndex(withOffsetAtOrAbove y: Double, startingAtLine lowerBound: Int) -> Int {
        firstLineIndexAtOrAbove(offset: y, metrics: self, lowerBound: lowerBound, lineCount: lineCount)
    }
}
```

This applies the load-bearing Slice 29 lesson correctly: because the requirement
is in the protocol body, the generic `compute<Metrics: LineMetricsSource>`
dispatches through the witness table and reaches a conformer's override. Declaring
it only in an extension would have statically bound `compute` to the default and
silently bypassed the balanced-tree override. The dispatch test
`testComputeDispatchesBothBoundarySearchesToNativeHooks` is the regression guard
for exactly that.

The `lowerBound` parameter is documented precisely as a correctness-preserving
**optimization hint**: the true answer is provably `>= lowerBound`
(`offset(ofLine: lowerBound) <= y` by precondition), so an override may ignore it
and still return the same index. Fallback providers narrow their binary search to
`[lowerBound, lineCount]`; the balanced-tree override ignores it.

### `compute` keeps semantic ownership; only the search engine changed (Decisions 1, 6)

`VariableViewportVirtualizer.swift` is unchanged except that the two private
edge-guard wrappers now delegate to the dispatched hooks instead of open-coding
binary search. Visible-start (`firstLineTopAtOrBelow`) keeps its
`target >= totalHeight -> lineCount` guard and then calls
`metrics.lineIndex(containingOffset: target)` (the Slice 29 hook); visible-end
(`firstLineTopAtOrAbove`) keeps its `target >= totalHeight -> lineCount` guard and
its `lowerBound` parameter, then calls
`metrics.firstLineIndex(withOffsetAtOrAbove: target, startingAtLine: lowerBound)`.
`compute`'s validation ladder, clamp, and buffered-range assembly are untouched.
The hooks are reached only after `compute` has established every documented
precondition, so the provider primitives can stay validation-free.

### Shared end-exclusive helper (drift mitigation, Decision 3)

The visible-end binary-search loop is lifted verbatim into one internal free
function `firstLineIndexAtOrAbove(offset:metrics:lowerBound:lineCount:)`, used by
**both** the default hook and `compute`'s wrapper, so the fallback `compute` path
and the default hook share a single `>=` boundary convention and cannot drift.
This is the structural mitigation the spec called for, mirroring Slice 29's
`binarySearchLineIndex`.

Critically, the design **preserved** the `lowerBound` narrowing (correcting a
first-draft proposal to drop it). Dropping it would have widened the fallback
visible-end search from `[visibleStart, lineCount-1]` back to `[0, lineCount-1]`,
costing up to O(log N) extra `offset(ofLine:)` probes at deep scroll — and for
`FenwickLineMetrics`, whose `offset(ofLine:)` is itself O(log N), that is up to
O(log²N) extra work per `compute` on the **blocking** `--variable-height-mutation
--gate`. Preserving the hint keeps every fallback provider at its exact current
probe count (zero gate regression). This was the right call and the verification
sweep guards it (`--variable-height --gate` for `PrefixSumLineMetrics`,
`--variable-height-mutation --gate` for `FenwickLineMetrics`).

### Balanced-tree end-exclusive native descent (Decision 4)

`BalancedTreeLineMetrics.firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`
delegates to an internal `firstLineIndexAndVisitCount` helper that does one
iterative descent
(`Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`):

```swift
        while current != -1 {
            visits += 1
            let node = nodes[current]
            let leftSum = nodeSum(node.left)
            let leftCount = nodeCount(node.left)
            let nodeTop = baseOffset + leftSum
            if y < nodeTop { current = node.left; continue }
            if y == nodeTop { return (baseIndex + leftCount, visits) }
            let nodeBottom = baseOffset + (leftSum + node.height)
            if y <= nodeBottom { return (baseIndex + leftCount + 1, visits) }
            baseOffset = nodeBottom
            baseIndex += leftCount + 1
            current = node.right
        }
```

I traced the end-exclusive semantics, including the subtle case where the descent
goes left (`y < nodeTop`) but no line in the left subtree qualifies: at the
rightmost node of that left subtree, `nodeBottom` equals the parent's `nodeTop`, so
the `y <= nodeBottom -> baseIndex + leftCount + 1` rule returns the parent's
in-order successor index — which is the correct global answer. The walk needs no
explicit best-candidate tracking because the end-exclusive successor rule supplies
it. The override accepts and **ignores** `lowerBound` (its descent is already a
single root-to-line O(log N) walk whose result is provably `>= lowerBound`). It is
non-mutating, iterative (O(1) auxiliary space, no recursion), allocates nothing,
reuses `nodeSum` / `nodeCount`, does not touch `lastMutationNodeVisits`, and the
trailing `preconditionFailure` is unreachable for valid in-range `y`. The internal
`...AndVisitCount` variant exposes a visit count for white-box tests only (via
`@testable import`) — no new public diagnostic.

The most important detail: the boundary check compares `y` to **absolute**
`nodeTop` / `nodeBottom` accumulated in the same shape as `offset(ofLine:)`, rather
than testing a subtractive `remaining` for zero. The mid-slice fix commit
`c470dad` ("fix: preserve exact balanced-tree prefix boundaries") is the evidence
this matters: the first draft used the subtractive-`remaining` pattern (parallel to
Slice 29's `lineIndexAndVisitCount`), and a fractional-exact-top test caught that
it could disagree with `offset(ofLine:)` at exact fractional line tops under
floating-point accumulation. The rewrite to absolute comparisons made the native
path bit-consistent with `offset(ofLine:)` — exactly what Decision 4 prescribes.
TDD did its job here.

### Docs (Decision in Documentation Updates)

`AGENTS.md`'s architecture paragraph now describes variable `compute` as
dispatching visible-start through `lineIndex(containingOffset:)` and visible-end
through `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`, with a balanced-tree
provider answering each compute boundary search in one O(log N) descent and other
providers using the generic binary-search fallback — matching the shipped code. The
`.gitignore` change (`.DS_Store`) is incidental macOS hygiene, consistent with the
earlier `aa3b755` chore.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `c31c477`)

- `git diff --stat a98d29a..c31c477 -- Sources Tests Package.swift` → confined to
  the two core files, the one provider file, and the two test files. No
  `Package.swift` change.
- `git diff --check a98d29a..c31c477` → no output, exit `0` (no whitespace errors).
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `swift test` → **140 tests, 0 failures**, plus the expected empty Swift Testing
  harness line (`0 tests in 0 suites`). Up from 130 at the Slice 29 baseline — the
  ten new tests landed (4 core: `testDefaultFirstLineIndexAtOrAboveReturnsSmallestIndexAtOrAbove`,
  `testDefaultFirstLineIndexAtOrAboveUsesLogarithmicFallback`,
  `testFirstLineIndexAtOrAboveHintNarrowsSearch`,
  `testComputeDispatchesBothBoundarySearchesToNativeHooks`; 6 provider:
  `testNativeFirstLineIndexAtOrAboveMatchesOracleAtBoundaries`,
  `testNativeFirstLineIndexAtOrAbovePreservesFractionalExactLineTops`,
  `testNativeFirstLineIndexAtOrAboveIgnoresHintButHonorsIt`,
  `testNativeFirstLineIndexAtOrAboveMatchesOracleAfterMutations`,
  `testComputeOverBalancedTreeMatchesPrefixSumOracleAcrossScrollSweep`,
  `testNativeFirstLineIndexAtOrAboveVisitCountIsLogarithmic`).
- `swift run -c release ViewportBenchmarks -- --gate` → all three synthetic
  scenarios `gate=pass`; checksums match the record (`1319670707200`,
  `570448232307200`, `18852477646272000`).
- `swift run -c release ViewportBenchmarks -- --structural-mutation --gate` → all
  three balanced-tree `compute` scenarios `gate=pass`, 0 failures; checksums
  byte-identical to the record (`200106952336`, `89494497658324`,
  `3379593298396981`), confirming the native descent computes the same boundaries
  as the generic search.
- `swift run -c release ViewportBenchmarks -- --line-query --gate` → all five
  scenarios `gate=pass`; all five checksums byte-identical to the record
  (`641440000`, `63985556480`, `639841600000`, `63985600000`, `639841547520`),
  confirming `lineAt` is unaffected (no behavior change to the Slice 29 path).

### The optimization payoff (the point of the slice)

The strongest evidence is structural. The compute-equivalence oracle
(`testComputeOverBalancedTreeMatchesPrefixSumOracleAcrossScrollSweep`) proves
`compute` over `BalancedTreeLineMetrics` returns the same `VirtualRange`,
`isAtTop`, and `isAtBottom` as `compute` over a `PrefixSumLineMetrics` oracle built
from the same heights across a scroll sweep (top, bottom, interior, exact line-top
and line-end boundaries, fractional offsets) and viewport heights. The
reference-provider oracle tests pin the native end-exclusive search against a
prefix-sum oracle at boundaries, after `setHeight`/`insertLine`/`removeLine`/
`insertLines`/`removeLines`, and at fractional exact line tops; the visit-count test
proves the walk stays logarithmic across 1k/100k/1m. Byte-identical
structural/bulk/line-query checksums (local and hosted) are the operational
confirmation.

Timing is recorded as a one-off observation, not as proof of correctness. The
verification record's before/after (baseline `a98d29a` vs after `74bcee4`) on the
two balanced-tree-driving gates:

| Gate / scenario | Baseline p95/p99 ns | After p95/p99 ns |
| --- | ---: | ---: |
| structural 1k | 1847 / 2314 | 894 / 984 |
| structural 100k | 8068 / 8629 | 5012 / 5108 |
| structural 1m | 33365 / 35483 | 22324 / 24052 |
| bulk 1k batch_64 | 3495 / 3669 | 2567 / 2646 |
| bulk 100k batch_64 | 12005 / 13252 | 7778 / 7890 |
| bulk 1m batch_64 | 51647 / 55823 | 34507 / 37141 |
| bulk 100k batch_4096 | 67679 / 72966 | 58945 / 59739 |
| bulk 1m batch_4096 | 181744 / 195343 | 122596 / 129361 |

These gates combine mutation **and** recompute, so they do not isolate the
`compute` speedup — the design (Decision 5) explicitly accepts this and does not add
an isolating benchmark mode. The improvement is real and consistent across sizes,
and well within budget headroom (the largest, 1m batch_4096, lands at 122,596 ns
against a 2,500,000 ns budget — ~20× under). All structural and bulk checksum
comparisons were clean (`diff -u` empty, exit 0), confirming identical results.

### Hosted runs (verified live via `gh`, at step-log level)

Re-verified during this review at the **step** level, not just the job
conclusion, per the project's "a green job can hide a dead `continue-on-error`
step" lesson:

- **PR #56 full-code run `28334474924`** (head `aa3b755`, event `pull_request`):
  conclusion `success`; recorded in the verification doc. The host job ran the full
  heavy path including all six blocking latency gates; step 5 `Complete docs-only
  PR` `skipped` (correctly not docs-only).
- **PR #56 final-head run `28371455301`** (head `5c142b6`, event `pull_request`):
  conclusion `success`, and host job `84049951985` **ran the full heavy path** —
  step 5 `Complete docs-only PR` `skipped`, then all six gates (steps 8→13) and the
  PR-only realistic-observation step (step 16) `success`. Although `5c142b6` by
  itself only records hosted evidence (docs), the docs-only detector evaluates the
  full `BASE_SHA...HEAD_SHA` PR diff — which carries the Swift source — so the PR is
  correctly classified **not** docs-only and the final head gets a full heavy-path
  run. This makes `28371455301` a heavy-path PR-head proof on the exact merged
  source, not a docs-only caveat (the Slice 29 lesson holds again).
- **Post-merge push run `28371924603`** on merge commit `fac19d6` (event `push`,
  branch `main`): conclusion `success`; all three required jobs `success`. Host job
  `84051567581` ran the full heavy path on merged code — step 5 `Complete docs-only
  PR` `skipped`; all six blocking latency gates (steps 8→13) ran and passed; step 16
  `Observe realistic provider relative performance` correctly `skipped` on the
  `push` event (it is the PR-only `continue-on-error` observation), versus `success`
  on the PR-head run. iOS job `84051567607` compiled `TextEngineCore` and
  `TextEngineReferenceProviders` for device + simulator; WASM job `84051567603`
  observed WASM + embedded WASM. **This is the merged-code evidence anchor for
  Slice 30.**

Merge parentage confirmed via `git rev-list --parents`: `fac19d6`'s second parent
is the verified PR head `5c142b6`; `c31c477` (PR #57) merges `9e4ad02` onto
`fac19d6`. PR #57 is docs-only (it only replaced the verification record's
`Pending` post-merge anchor with run `28371924603`), so the workflow has not
changed since `fac19d6` and run `28371924603` still represents current `main`'s
behavior. The cross-target self-test (`self_test=pass`) and the full local iOS
device/simulator + WASM/embedded-WASM compile (`blocking_failures=0 exit=0`) are
recorded in the verification doc against the public-protocol change.

## Git History

Reviewed Slice 30 commits (PR #56 → #57):

```text
2edfa26 docs: add compute-native prefix search design
257cbb3 docs: add compute-native prefix search plan
a45f1be feat: add end-exclusive line-index prefix-search hook
cade053 feat: route compute searches through provider hooks
9c4af92 feat: add balanced-tree end-exclusive native descent
c470dad fix: preserve exact balanced-tree prefix boundaries
69f7236 test: prove balanced-tree compute equals prefix-sum oracle
b3421c4 docs: document compute provider-native prefix search
74bcee4 docs: clarify shared prefix-search hooks
351cf3e docs: record compute-native prefix search verification
d80edf0 docs: tighten compute-native verification evidence
22cc38a docs: align compute-native prefix search plan
aa3b755 chore: ignore macOS metadata files
5c142b6 docs: record compute-native prefix search hosted evidence
fac19d6 Merge pull request #56 …
9e4ad02 docs: record slice 30 post-merge proof
c31c477 Merge pull request #57 …
```

Clean, one-logical-step-per-commit with correct conventional-commit prefixes:
spec → plan precede code; the core hook (`a45f1be`), the `compute` rerouting
(`cade053`), and the provider override (`9c4af92`) land as separate `feat:`
commits; the boundary correction is an honest `fix:` (`c470dad`) with its failing
test; the compute-equivalence oracle is a separate `test:` (`69f7236`); durable
docs (`b3421c4`, `74bcee4`) are isolated; verification (`351cf3e`, `d80edf0`) is
separate from implementation. The two-PR split (implementation + local/PR-head +
hosted proof, then post-merge proof) is the standard pattern.

## Code Review Findings

Reviewed across correctness, dispatch semantics, scope discipline, evidence
integrity, and the hard constraints.

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, the optimization is correct (compute-equivalence-oracle
and visit-count tested, byte-identical structural/bulk/line-query checksums),
both boundary searches dispatch to the overrides through the witness table (proven
by `testComputeDispatchesBothBoundarySearchesToNativeHooks`), the `lowerBound` hint
is provably result-preserving (and tested by `...IgnoresHintButHonorsIt`), the
scope is tight, and the Foundation-free / zero-dependency / O(1)-core-memory
invariants are intact and cross-target verified.

### P2 / Production Readiness

None. The merged result is correct and proven green on merged code at step level
(`28371924603`).

### P3 / Minor But Valid

**1. Uniform/prefix-sum providers still inherit the generic O(log N) fallback for
both hooks.** Carried forward from Slice 29 (its P3 #1) — deliberate (Non-Goals):
a closed-form `floor(y / lineHeight)` override would be O(1) but risks a one-line
disagreement with the binary search at exact `y == i·lineHeight` boundaries under
floating-point division, which would break the `LineAtEquivalenceTests` /
compute-equivalence oracles. Keeping uniform on the fallback protects that
equivalence. Not a defect — a documented, well-scoped future option (Option B
below: a *verified* closed-form override).

**2. The compute-equivalence oracle test lives in the reference-provider test
target, not the core test target.** The Slice 30 design's "Core Tests" section
listed the compute-equivalence oracle, but it shipped in
`Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`
(`testComputeOverBalancedTreeMatchesPrefixSumOracleAcrossScrollSweep`). This is
actually the **correct** placement — the test needs both `BalancedTreeLineMetrics`
and `PrefixSumLineMetrics`, which are reference providers — so the only issue is a
spec/placement wording mismatch, not a coverage gap. No action needed; noted for
accuracy.

No P3 changes whether the merged result is correct.

## Risks And Gaps

### The vertical-axis optimization arc is now complete

After Slice 30, both `lineAt` and `compute` are single O(log N) descents over a
balanced-tree provider. There is no remaining O(log²N) balanced-tree vertical
consumer. This means the natural "finish the optimization Slice N started" thread
that drove Slices 29 and 30 has run out: the next slice is no longer an obvious
algorithmic continuation. That is a healthy place to be — the project should now
weigh a genuinely new capability (geometry-bearing queries, horizontal/wrap) or a
standing infra item, rather than more vertical-axis tuning.

### No new gate, so no governance debt — for the second slice running

Because Slice 30 reused the structural/bulk/variable-height gates, no CI-promotion
slice is owed. This is the second consecutive functional slice (after Slice 29) to
leave **zero** governance debt. The flip side: the `compute` speedup is not
isolated by any single gate (Decision 5), so a future `compute`-only regression in
the native descent that stayed within the combined mutation+recompute budget could
go unnoticed. The compute-equivalence oracle guards *correctness*; only the
combined gates guard *latency*. This is an accepted trade, not a defect.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative
observation remains PR-only `continue-on-error`; budgets remain macOS-derived (now
validated against hosted Linux across all six gates); the `Main` ruleset keeps its
documented bypass-actor shape. None were in scope for Slice 30.

## Lessons For The Next Slice

1. **The Slice 29 defaulted-hook pattern generalized cleanly to a second
   primitive.** Declaring `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` in
   the protocol body (default in an extension), overriding it in the provider, and
   guarding dispatch with a witness-table test reproduced the Slice 29 result with
   no surprises. This is now a proven, repeatable recipe for adding an optional
   provider-native primitive: protocol-body requirement + default + provider
   override + dispatch test.
2. **Compare against absolute accumulated values, not subtractive remainders, when
   a native walk must agree with a prefix-sum at exact boundaries.** The `fix:`
   commit `c470dad` is the lesson in miniature: the subtractive-`remaining` first
   draft (copied from Slice 29's working `lineIndex` walk) drifted from
   `offset(ofLine:)` at exact fractional line tops; rewriting to compare `y` against
   absolute `nodeTop`/`nodeBottom` (accumulated in the same shape as
   `offset(ofLine:)`) restored bit-consistency. A fractional-exact-top oracle test
   caught it — write that test first for any future native boundary walk.
3. **Don't drop a deliberately-introduced optimization hint without checking what
   gate protects it.** The first design draft proposed dropping `lowerBound` on the
   premise the loss was "at most one comparison." It was actually up to O(log N)
   extra probes at deep scroll — up to O(log²N) for `FenwickLineMetrics` on its
   blocking gate. Preserving it as a result-preserving hint kept fallbacks at their
   exact probe count. Trace an optimization back to the gate that guards it before
   removing it.
4. **A second functional slice can also reuse existing gates and leave no
   governance debt.** When the optimized path is already CI-protected by mutation
   gates that exercise it, reuse them; do not invent a benchmark mode just to keep
   a cadence. (Caveat from Risks: combined gates do not *isolate* the new path's
   latency — accept that consciously.)
5. **A docs/evidence tail commit on a source-bearing PR still runs the full heavy
   path.** PR #56 ended on `5c142b6` (records hosted evidence) yet its final-head
   run `28371455301` executed every gate, because the docs-only detector compares
   the whole PR diff. The final-head run of a source-bearing PR is a valid heavy
   PR-head proof regardless of the last commit's contents.

## Slice 31 Candidate Options

With the vertical-axis optimization arc complete, the remaining candidates are
genuinely new capability or standing infra — not algorithmic continuations.

### Option A: Geometry-bearing vertical query (Slice 27/28/C carry-forward)

Add a richer vertical query returning line index **plus** the line's y/height or a
within-line fraction, for tap-to-caret flows. Builds directly on the now-optimal
`lineAt` (it can reuse the native descent and additionally surface `offset(ofLine:)`
/ height already on the path). Wider public API surface: a new method and result
type, not a new `LineQuery` case. This is the first real step toward
consumer-facing editing affordances and the most natural functional next step now
that both vertical queries are asymptotically optimal. Warrants a brainstorm +
spec.

### Option B: Verified closed-form uniform override

Give `UniformLineMetrics` (and possibly `PrefixSumLineMetrics`) O(1) overrides for
**both** native hooks (`lineIndex(containingOffset:)` and
`firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`), with a verified
boundary-safe formula that provably equals the binary search at exact
`y == i·lineHeight` boundaries so the equivalence oracles stay green. Small, clean
slice; retires the last fallback-bound common provider (P3 #1, carried from Slice
29). Lower product value than A.

### Option C: Horizontal / wrap-aware next capability

Advance toward x/y point queries, wrapping, or visual rows — the largest product
leap toward realistic editing of 100k+ line / >10 MB documents, and the largest
design surface. Needs a fresh brainstorm + spec.

### Option D: Promote WASM cross-target to blocking

Provision a pinned, version-matched WASM Swift SDK in hosted CI and flip the WASM
job from observational to blocking for both `TextEngineCore` and
`TextEngineReferenceProviders`. The strongest standing infra item; gated on stable
SDK provisioning.

### Option E: Linux-native budget re-baseline

Re-derive Linux-native budgets from the accumulated x86_64 evidence across all six
gates and retire the macOS-calibration caveat. Low product value, useful hygiene.

## Recommended Slice 31 Selection

Recommended Slice 31 is **Option A — geometry-bearing vertical query**, with the
A-vs-C product call surfaced to the user.

The reasoning: Slices 27→30 closed the vertical-query *performance* arc — both
`lineAt` and `compute` are now O(log N) over a balanced tree, and there is no
remaining algorithmic continuation to chase. The project is at a natural pivot from
*optimization* to *capability*. Option A is the smallest, most consistent step
across that pivot: it extends the just-optimized `lineAt` from "which line?" to
"which line, and where within it?", which is the primitive tap-to-caret and
selection need, and it can reuse the native descent and the height data already on
the path. It needs a brainstorm + spec (new public method and result type, plus a
clamp/within-line-fraction contract), but it has clean equivalence anchors and does
not touch the core `compute` contract.

The genuine product decision worth surfacing to the user is **A vs. C**: Option A
deepens the vertical axis toward editing affordances (smaller, consistent, builds
on what just shipped), while Option C opens the horizontal/wrap axis (the larger
product leap, much larger design surface). Option D remains the strongest pick if
the preference is to close the last standing infra item (WASM blocking) before
adding capability, and Option B is the right small slice if the goal is to retire
the carried uniform-provider P3 first.

## Slice 30 Review Conclusion

Slice 30 delivered the intended algorithmic increment cleanly: `compute` over a
`BalancedTreeLineMetrics` provider now resolves both its visible-start and
visible-end boundary searches as single O(log N) subtree-sum descents instead of
the generic O(log²N) binary search, delivered as a second defaulted
`LineMetricsSource.firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` hook (with
visible-start rerouted through the existing Slice 29 hook) so existing providers
stay source-compatible and `compute` keeps its full public contract. The
witness-table dispatch for both boundaries is correct and test-guarded, the
end-exclusive boundary convention is locked by a compute-equivalence oracle and
shared between the fallback and `compute` via one extracted helper, the
`lowerBound` narrowing was correctly preserved (protecting the
`--variable-height-mutation` gate), and the native descent is byte-identical to the
generic search (all structural/bulk/line-query checksums match across local,
PR-head, and merged-code runs).

The review found **no P0, P1, or P2 issues** and **no evidence-accuracy defect**
against the merged result: PR #56's final head `5c142b6` has its own full
heavy-path green run (`28371455301`), and the merged-code push run `28371924603` is
the authoritative anchor, verified green at step level. The mid-slice `fix:`
(`c470dad`) is a healthy TDD signal, not a defect — a fractional-exact-top test
caught a floating-point boundary drift and the absolute-comparison rewrite fixed it.
The two P3s are minor and carried/cosmetic (uniform fallback; oracle test target
placement). Every hard constraint holds: Foundation-free, zero-dependency, O(1)
core memory, and cross-target verified.

With both `lineAt` and `compute` now asymptotically optimal and CI-protected, and
**no governance debt** left behind for the second slice running, Slice 30 closes
the vertical-query optimization arc entirely and hands off to a pivot point —
most naturally a geometry-bearing vertical query (Option A) as the first step
toward consumer-facing editing, with the larger A-vs-C product direction worth a
decision from the user.
