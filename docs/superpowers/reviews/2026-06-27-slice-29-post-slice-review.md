# Slice 29 Post-Slice Review

Date: 2026-06-27

## Scope Reviewed

This review covers Slice 29: **provider-native prefix search**. It optimizes the
existing inverse vertical query `ViewportVirtualizer.lineAt(y:metrics:)` so that a
mutable indexed provider can answer "which line contains this y?" in a single
O(log N) tree descent instead of the generic O(log²N) binary search over O(log N)
`offset(ofLine:)` probes. It was the Slice 28 review's recommended Option A and the
user-selected direction.

Unlike the previous five "functional slice → CI-gate promotion" pairs, this slice
is **functional and adds no new gate**: the path it optimizes was already put under
a blocking hosted gate by Slice 28 (`--line-query --gate`, with `balanced_tree_100k`
and `balanced_tree_1m` scenarios), so the win is measurable against an existing
gate and there is no governance follow-up to schedule.

The change is delivered as a defaulted protocol hook rather than a new public query:

- `LineMetricsSource` gains a defaulted lower-level requirement
  `lineIndex(containingOffset:)`. Its default is the generic binary search, so every
  existing conformer stays source-compatible and behavior-identical.
- `ViewportVirtualizer.lineAt` keeps the full Slice 27 validation/clamp ladder and
  only calls the hook for the proven in-range branch.
- `BalancedTreeLineMetrics` overrides the hook with one iterative, non-mutating,
  allocation-free descent over its existing `subtreeHeightSum`/`subtreeCount`.
- The generic monotone-search loop is extracted to a single internal helper
  (`binarySearchLineIndex`) shared by both the default hook and `compute`'s
  `firstLineTopAtOrBelow`, so the fallback `lineAt` path and `compute` cannot drift
  on the half-open boundary convention.

The slice was delivered through **two** PRs, both now merged:

- PR #53 (`slice-29-provider-native-prefix-search`), title *"Slice 29: add
  provider-native prefix search"*, final head
  `6764fa19d11244e878d20104eedcbbc43ae142db` (`6764fa1`), merged to `main` as
  `d380eb11a02887a007f61151a4f6d170fc85c573` (`d380eb1`) — the core hook, the
  provider override, the tests, the doc updates, and the verification record's local
  + PR-head sections.
- PR #54 (`slice-29-post-merge-verification`), title *"Record Slice 29 post-merge
  proof"*, merged as `e1464ce2f20ca015592834d4d5a0778f83997ca0` (`e1464ce`, current
  `main` HEAD) — the docs-only follow-up that added the merged-code push-run anchor.

**Both PRs are merged at review time**, so `main`'s verification record carries real
hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-26-provider-native-prefix-search-design.md`
- `docs/superpowers/plans/2026-06-26-provider-native-prefix-search.md`
- `docs/superpowers/verification/2026-06-26-provider-native-prefix-search.md`
- `docs/superpowers/reviews/2026-06-26-slice-28-post-slice-review.md`
- `Sources/TextEngineCore/LineMetricsSource.swift`,
  `Sources/TextEngineCore/PositionQuery.swift`,
  `Sources/TextEngineCore/VariableViewportVirtualizer.swift`
- `Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift`
- `Tests/TextEngineCoreTests/LineAtQueryCountTests.swift`,
  `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`
- `AGENTS.md`, `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`,
  `docs/superpowers/specs/2026-06-20-bulk-structural-edits-design.md`
- PR #53 / #54 metadata, hosted run evidence (step-level conclusions), merge
  parentage, and the merged Slice 29 diff

The reviewed Slice 29 range (PR #52 merge base → current `main` HEAD), excluding
this review document itself, is:

```text
b775abd..e1464ce
```

`git merge-base e1464ce b775abd` returns `b775abd`, confirming the Slice 28 review
merge is a clean ancestor and the range captures exactly the Slice 29 work.

## Product Brief Alignment

The brief requires a headless layout/virtualization core that supports stable
scrolling over 100k+ line / >10 MB documents, keeps core-owned memory from scaling
linearly with document size, stays Foundation-free and zero-dependency, and compiles
for iOS and WASM without source changes. Slice 27 added the inverse `lineAt` query;
Slice 28 put it under a blocking gate. The remaining weakness was provider-specific:
`BalancedTreeLineMetrics` could answer `offset(ofLine:)` in O(log N), but the generic
`lineAt` binary search made a balanced-tree y→line query O(log²N) wall-clock even
though the provider already stores the subtree height sums needed to answer it in one
descent.

Slice 29 closes that gap without widening the public surface. It deepens the
core/provider composition so the data structure's full capability is used, while
keeping `lineAt` as the single consumer-facing vertical query and preserving every
`LineQuery`/`LineLocation`/clamp/empty/failure semantic from Slice 27. It honors all
hard constraints: the core stays Foundation-free (both scans empty), no dependency is
added, the native descent allocates nothing and adds no core-owned memory (O(1) core
memory is preserved), and the public-protocol change is cross-target verified for iOS
(blocking) and WASM (observational).

This also marks a rhythm change worth noting: the project had run five consecutive
"functional capability adds a local gate → promotion slice wires CI" cycles. Slice 29
is a **functional capability that reuses an existing gate**, so it carries no
CI-promotion debt forward — the optimized path was already blocking-gated by Slice 28.

## Delivered Design

Merged Slice 29 diff (`b775abd..e1464ce`):

```text
 AGENTS.md                                          |   5 +-
 Sources/TextEngineCore/LineMetricsSource.swift     |  34 +
 Sources/TextEngineCore/PositionQuery.swift         |  14 +-
 Sources/TextEngineCore/VariableViewportVirtualizer.swift |  18 +-
 Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift | 35 +
 Sources/ViewportBenchmarks/LineQueryBenchmark.swift |   5 +-
 Tests/TextEngineCoreTests/LineAtQueryCountTests.swift | 71 ++
 Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift | 129 ++
 docs/.../2026-06-26-provider-native-prefix-search.md (plan)        | 860 +
 docs/.../2026-06-26-provider-native-prefix-search-design.md (spec) | 370 +
 docs/.../2026-06-26-provider-native-prefix-search.md (verification)| 218 +
 docs/.../2026-06-20-bulk-structural-edits-design.md (P3 cross-ref) |   5 +
 12 files changed, 1739 insertions(+), 25 deletions(-)
```

### The defaulted hook (the API decision, Decision 1)

`LineMetricsSource` gains a requirement declared **in the protocol body** with a
default implementation in an extension
(`Sources/TextEngineCore/LineMetricsSource.swift:22-35`):

```swift
    /// Returns the line whose half-open vertical span contains `y`.
    /// Preconditions: lineCount > 0, offset(ofLine: 0) == 0, and y finite in
    /// [0, offset(ofLine: lineCount)). Does not validate or clamp.
    func lineIndex(containingOffset y: Double) -> Int
}

extension LineMetricsSource {
    public func lineIndex(containingOffset y: Double) -> Int {
        binarySearchLineIndex(containingOffset: y, metrics: self, lineCount: lineCount)
    }
}
```

This is correct against the single most important risk in the design. Because the
requirement is declared **in the protocol body** (not only in an extension), it is a
real customization point: a generic caller constrained to `LineMetricsSource` —
which is exactly what `lineAt<Metrics: LineMetricsSource>` is — dispatches through
the witness table and reaches a conformer's override. Had the method lived only in
an extension, the generic `lineAt` would have statically bound to the default and
silently bypassed the balanced-tree override. The design avoided that footgun, and
the test `testLineAtDispatchesToNativeHookAfterValidationProbes` is a regression
guard for it.

### `lineAt` keeps semantic ownership (Decision 2)

`PositionQuery.swift` preserves the Slice 27 validation/clamp order verbatim and
changes only the in-range branch
(`Sources/TextEngineCore/PositionQuery.swift:45`):

```swift
        let index = metrics.lineIndex(containingOffset: y)
        return .line(LineLocation(lineIndex: index, clamp: .inRange))
```

The hook is reached only after the core has established every precondition it
documents: `lineCount >= 0`, finite `y`, `offset(0) == 0`, non-empty, finite
positive `totalHeight`, `y >= 0`, and `y < totalHeight`. The hook is never asked
about `y == totalHeight` (clamped to bottom first) or out-of-range `y`, so the
provider primitive can stay validation-free.

### Shared fallback helper (drift mitigation, Decision 4)

`firstLineTopAtOrBelow` keeps its `target >= totalHeight` guard (which `compute`
needs and the hook never hits) and then delegates to the same
`binarySearchLineIndex` the default hook uses
(`Sources/TextEngineCore/VariableViewportVirtualizer.swift`):

```swift
        if target >= totalHeight {
            return lineCount
        }
        return binarySearchLineIndex(containingOffset: target, metrics: metrics, lineCount: lineCount)
```

This is the structural mitigation the spec called for: the fallback `lineAt` path
and `compute`'s visible-start search now share one loop, so their half-open
convention cannot drift. `firstLineTopAtOrAbove` (visible-end, end-exclusive) is
correctly left untouched — Slice 29 does not optimize `compute`.

### Balanced-tree native descent (Decision 3)

`BalancedTreeLineMetrics.lineIndex(containingOffset:)` delegates to an internal
`lineIndexAndVisitCount` helper that does one iterative weight-keyed descent
(`Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift:69-102`):

```swift
        while current != -1 {
            visits += 1
            let node = nodes[current]
            let leftSum = nodeSum(node.left)
            if remaining < leftSum { current = node.left; continue }
            remaining -= leftSum
            let leftCount = nodeCount(node.left)
            if remaining < node.height { return (baseIndex + leftCount, visits) }
            remaining -= node.height
            baseIndex += leftCount + 1
            current = node.right
        }
```

I traced the half-open semantics: `remaining < node.height` means
`y ∈ [nodeTop, nodeTop + height)` → that line; at an exact boundary
`y == nodeTop + height`, `remaining == node.height` is **not** `< node.height`, so
the walk advances right to the next line — matching the `[offset(i), offset(i+1))`
contract and the generic binary search. The walk is non-mutating, iterative (O(1)
auxiliary space, no recursion stack), allocates nothing, reuses the existing
`nodeSum`/`nodeCount` helpers, and does not touch `lastMutationNodeVisits`. The
`internal` `lineIndexAndVisitCount` variant exposes only a visit count for white-box
tests via `@testable import` — no new public diagnostic. The trailing
`preconditionFailure` is unreachable for valid in-range `y` and is correct defensive
guarding.

### Docs and the retired carry-forward P3 (Decisions 5, 6)

- `AGENTS.md` architecture paragraph now describes `lineAt` as using "a
  provider-native prefix-search hook when available and the generic O(log N)
  binary-search fallback otherwise" — matching the shipped code.
- `LineQueryBenchmark.swift` change is **comment-only**: budgets, scenarios,
  iterations, and checksum logic are untouched (Decision 5), so the existing gate is
  reused without retuning.
- The long-carried provider-doc P3 (Slice 25 #3 → Slice 26 #1 → Slice 28 #1) is
  **retired**: a one-line note in the bulk-structural-edits design spec records that
  the shipped join helpers are named `join2`/`join3`, reconciling the older
  `join(_:_:)` wording (Decision 6). This was the correct slice to close it, since
  Slice 29 touches provider behavior and provider docs anyway.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `e1464ce`)

- `git diff --name-only b775abd..HEAD -- Sources Tests Package.swift` → confined to
  the three core files, the one provider file, the benchmark comment, and the two
  test files. No `Package.swift` change.
- `git diff --check b775abd..HEAD` → no output, exit `0` (no whitespace errors).
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `swift test` → **130 tests, 0 failures**, plus the expected empty Swift Testing
  harness line (`0 tests in 0 suites`). Up from 124 at the Slice 28 baseline — the
  six new tests landed.
- All six new test methods are present in the merged tree
  (`testDefaultLineIndexRequirementUsesLogarithmicFallback`,
  `testLineAtDispatchesToNativeHookAfterValidationProbes`,
  `testNativeLineIndexMatchesPrefixSumOracleAtBoundaries`,
  `testLineAtWithBalancedTreeMatchesPrefixSumOracle`,
  `testNativeLineIndexMatchesOracleAfterSingleAndBulkMutations`,
  `testNativeLineIndexVisitCountIsLogarithmic`).
- `swift run -c release ViewportBenchmarks -- --gate` → all three synthetic scenarios
  `gate=pass`; checksums match the record (`1319670707200`, `570448232307200`,
  `18852477646272000`).
- `swift run -c release ViewportBenchmarks -- --line-query --gate` → all five
  scenarios `gate=pass`, 0 failures; **all five checksums byte-identical** to the
  recorded baseline (`641440000`, `63985556480`, `639841600000`, `63985600000`,
  `639841547520`), confirming the native descent computes the same line indices as
  the generic search.

### The optimization payoff (the point of the slice)

The strongest evidence is structural — the oracle tests prove the native descent
equals a `PrefixSumLineMetrics` oracle across line-top/line-interior/pre-boundary
samples and after `setHeight`/`insertLine`/`removeLine`/`insertLines`/`removeLines`,
and the visit-count test proves the walk stays `≤ 4·(⌊log₂ N⌋ + 1)` across
1k/100k/1m. The timing is recorded as observation, not as proof of correctness, but
it is real and large:

| Scenario | macOS pre (Slice 28, generic) | macOS post (this review, native) | Local speedup |
| --- | ---: | ---: | ---: |
| balanced_tree_100k p95 | 770 ns   | ~102 ns | ~7.5× |
| balanced_tree_1m p95   | 1,496 ns | ~124 ns | ~12×  |

On hosted Linux x86_64 the same shape holds: the merged-code push run reports
`balanced_tree_1m` at p95 **252 ns** against a 600,000 ns budget (~2,381× under
budget), versus the generic path's ~1,778–2,456 ns hosted p95 recorded in the Slice
28 verification record — a ~7–10× hosted improvement. Uniform scenarios are
effectively unchanged, as designed: `UniformLineMetrics` intentionally inherits the
generic fallback (Decision 5) to avoid a closed-form `floor()` disagreeing with the
oracle at exact boundaries.

### Hosted runs (verified live via `gh`, at step-log level)

All runs re-verified during this review, and — per the project's "a green job can
hide a dead `continue-on-error` step" lesson — at the **step** level, not just the
job conclusion:

- **PR #53 full-code run `28236023961`** (head `0607962`, event `pull_request`):
  conclusion `success`; the host job ran the full heavy path including the line-query
  gate, with `balanced_tree_100k`/`balanced_tree_1m` reported at p95 243/252 ns,
  `gate=pass`. This is the run that exercised the optimized source under the gate.
- **PR #53 final-head run `28236592208`** (head `6764fa1`, event `pull_request`):
  conclusion `success`. `6764fa1` is a docs-only commit (it only added hosted
  evidence to the verification record), so this run correctly took the trusted
  docs-only path.
- **Post-merge push run `28264342225`** on merge commit `d380eb1` (event `push`,
  branch `main`): conclusion `success`; all three required jobs `success`
  (`83747310410` / `83747310415` / `83747310459`). The host job ran the full heavy
  path on merged code (step 5 `Complete docs-only PR` `skipped`; all six blocking
  latency gates ran; steps 12→13→14 `bulk → line query → memory shape` all
  `success`; the PR-only realistic-observation step `skipped` on the push event).
  **This is the merged-code evidence anchor for Slice 29.** All five line-query
  checksums on this run equal the local and PR-head baseline, proving the native
  descent is deterministic across local, PR-head, and merged-code runs.

Merge parentage confirmed via `git rev-list --parents`: `d380eb1`'s second parent is
the verified PR head `6764fa1`; `e1464ce` (PR #54) merges `44cb390` onto `d380eb1`.
PR #54 is docs-only (it only added the post-merge proof section), so the workflow has
not changed since `d380eb1` and run `28264342225` still represents current `main`'s
behavior.

## Git History

Reviewed Slice 29 commits (PR #53 → #54):

```text
bc95502 docs: add provider-native prefix search design
af8ab92 docs: address prefix search spec review
62bf0b5 docs: add provider-native prefix search plan
ad02e03 feat: add provider-native line index hook
2bdc39b feat: add balanced-tree native prefix search
15d3f2f docs: document provider-native line query path
0607962 docs: record provider-native prefix search verification
6764fa1 docs: add hosted provider-native prefix search evidence
d380eb1 Merge pull request #53 …
44cb390 docs: record slice 29 post-merge proof
e1464ce Merge pull request #54 …
```

Clean, TDD-shaped, one-logical-step-per-commit with correct conventional-commit
prefixes: spec → spec-correction → plan precede code; the core hook
(`ad02e03`) and the provider override (`2bdc39b`) land as separate `feat:` commits;
durable docs (`15d3f2f`) are isolated; verification (`0607962`) is separate from
implementation. The two-PR split (implementation + local/PR-head proof, then
post-merge proof) is the standard pattern.

## Code Review Findings

Reviewed across correctness, dispatch semantics, scope discipline, evidence
integrity, and the hard constraints.

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, the optimization is correct (oracle- and
visit-count-tested, byte-identical checksums), dispatch reaches the override through
the witness table (proven by test), the scope is tight, and the Foundation-free /
zero-dependency / O(1)-core-memory invariants are intact and cross-target verified.

### P2 / Production Readiness

None. The merged result is correct and proven green on merged code at step level.

### P3 / Minor But Valid

**1. The cited "PR-head" run is one docs-only commit behind PR #53's final head.**
The verification record cites full-code run `28236023961` @ `0607962` as the Swift CI
pull_request evidence, but PR #53's final head was `6764fa1` (a docs-only commit that
added the hosted evidence into the verification file). The final head did get its own
green run (`28236592208`), but as a docs-only commit that run took the trusted
docs-only path, so the doc reasonably cites the earlier full-code run that actually
exercised the gate. The record is transparent about this ("the artifact-only update
after this evidence does not change implementation files") and the merged-code push
run is the authoritative anchor, so this does not affect correctness. It is a slight
deviation from the Slice 26/28 gold standard, which recorded the PR-head proof in the
post-merge follow-up against a *stable* final head and so never referenced a
non-final head. Here the PR-head proof was instead written *inside* the source PR
(commit `6764fa1`), which inherently references the pre-evidence commit. Folding all
hosted evidence into the post-merge follow-up (as Slice 28 did) would retire this
ambiguity next time. No code or merged-behavior impact.

**2. Uniform/prefix-sum providers still inherit the generic O(log N) fallback.** This
is deliberate (Decision 5): a closed-form `floor(y / lineHeight)` override would be
O(1) but risks a one-line disagreement with the binary search at exact
`y == i·lineHeight` boundaries under floating-point division, which would break the
`LineAtEquivalenceTests` oracle. Keeping uniform on the fallback protects that
equivalence. Not a defect — a documented, well-scoped future option (a *verified*
closed-form override).

No P3 changes whether the merged result is correct.

## Risks And Gaps

### `compute` is now the last O(log²N) balanced-tree vertical consumer

Slice 29 makes the balanced-tree **`lineAt`** path a single O(log N) descent, but
`ViewportVirtualizer.compute` still resolves its visible-start through the generic
`binarySearchLineIndex` (O(log²N) over balanced-tree offsets) and its visible-end
through `firstLineTopAtOrAbove`. Decision 4 deliberately scoped `compute` out of this
slice because visible-end has end-exclusive "first top at or above" semantics that
need a *different* provider primitive than the one shipped. Since `compute` runs on
every scroll, extending the native search into it is the natural highest-value
follow-up; it is correctly deferred, not forgotten. The numbers are correct and far
under budget regardless, so this is an optimization opportunity, not a defect.

### No new gate, so the rhythm changes — and that is fine

Because Slice 29 reused `--line-query --gate` rather than adding a benchmark mode,
there is no CI-promotion slice owed. The optimized path is already blocking-gated
(Slice 28). This is the first functional slice in six that leaves **zero** governance
debt behind, so the next slice is free to be a genuine new capability with no infra
follow-up forced.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative observation
remains PR-only `continue-on-error`; budgets remain macOS-derived (now validated
against hosted Linux for six gates, with this slice clearing by ~2,381× at the
tightest scenario); the `Main` ruleset keeps its documented bypass-actor shape. None
were in scope for Slice 29.

## Lessons For The Next Slice

1. **Declare a customization-point requirement in the protocol body, not just an
   extension.** The whole slice hinges on a generic core call
   (`lineAt<Metrics: LineMetricsSource>`) reaching a conformer's override through the
   witness table. The design got this right by putting `lineIndex(containingOffset:)`
   in the protocol body with the default in an extension, and added a dispatch test
   as a regression guard. Keep this pattern for any future provider-native hook.
2. **A defaulted requirement is the right way to add an optional provider primitive
   without breaking conformers.** Existing providers inherited the fallback with zero
   source changes, the optimized provider overrode it, and the core needed no runtime
   casts or special-casing. Prefer this over a parallel opt-in protocol or a
   provider-only method.
3. **Share the loop, prove equivalence structurally.** Extracting one
   `binarySearchLineIndex` helper shared by the fallback hook and `compute`, plus an
   oracle test that pins the half-open boundary on both line-top and line-end
   samples, is what makes the optimization safe to land. Timing was recorded as
   observation only — equivalence is the proof.
4. **Fold all hosted evidence into the post-merge follow-up.** Slice 28's clean
   convention — record both the PR-head proof (against the stable final head) and the
   post-merge proof in the docs-only follow-up — avoids the "PR-head run references a
   non-final head" ambiguity that Slice 29's in-PR evidence reintroduced as P3 #1.
   Reuse Slice 28's structure for the next source/workflow-touching slice.
5. **A functional slice that reuses an existing gate leaves no governance debt.**
   When the optimized path is already CI-protected, do not invent a new benchmark
   mode just to keep the "functional → promotion" cadence; reuse the gate and let the
   next slice be a real capability increment.

## Slice 30 Candidate Options

### Option A: Extend provider-native prefix search into `compute`

Route `compute`'s visible-start through the provider hook and add a second
provider-native primitive ("first line top at or above y") for the end-exclusive
visible-end search, making the balanced-tree **scroll hot path** fully O(log N).
Highest algorithmic value: `compute` runs on every viewport recomputation and is now
the last O(log²N) balanced-tree vertical consumer. Decision 4 explicitly deferred
this, so it is the consistent next step. It touches the core `compute` contract and
adds a provider primitive, so it warrants a brainstorm + spec; the win is measurable
against the variable-height / structural gates that drive `compute` over a
balanced-tree provider.

### Option B: Verified closed-form uniform override

Give `UniformLineMetrics` (and possibly `PrefixSumLineMetrics`) an O(1)
`lineIndex(containingOffset:)` override, with a verified boundary-safe formula that
provably equals the binary search at exact `y == i·lineHeight` boundaries so the
equivalence oracle stays green. Small, clean slice; lower product value than A but it
retires the only remaining fallback-bound common provider (P3 #2).

### Option C: Geometry-bearing vertical query (Slice 27/28 carry-forward)

Add a richer query returning line index plus y/height or within-line fraction, for
tap-to-caret flows. Wider public API surface; a new method/result type, not a new
`LineQuery` case. The first real step toward consumer-facing editing affordances.

### Option D: Horizontal / wrap-aware next capability

Advance toward x/y point queries, wrapping, or visual rows — the largest product leap
toward realistic editing of 100k+ line / >10 MB documents, and the largest design
surface. Needs a fresh brainstorm + spec.

### Option E: Promote WASM cross-target to blocking

Provision a pinned, version-matched WASM Swift SDK in hosted CI and flip the WASM job
from observational to blocking for both `TextEngineCore` and
`TextEngineReferenceProviders`. The strongest standing infra item; gated on stable
SDK provisioning.

### Option F: Linux-native budget re-baseline

Re-derive Linux-native budgets from the accumulated x86_64 evidence across all six
gates and retire the macOS-calibration caveat. Low product value, useful hygiene.

## Recommended Slice 30 Selection

Recommended Slice 30 is **Option A — extend provider-native prefix search into
`compute`**.

The reasoning: Slice 29 made the balanced-tree y→line query asymptotically optimal
*through `lineAt`*, but `compute` — the most-exercised query, run on every scroll —
still pays O(log²N) for its visible-start search over a balanced-tree provider, and
its visible-end search has not been addressed at all. Decision 4 explicitly deferred
this with a clear technical reason (visible-end needs a different "first top at or
above" primitive), which makes it the consistent, already-scoped next functional
step: it finishes the exact optimization Slice 29 started, on the path that matters
most for stable scrolling of 100k+ line documents. It has clean equivalence anchors
(the existing fixed-vs-variable equivalence oracle plus a new compute-level oracle),
reuses the just-proven witness-table dispatch pattern, and its win is directly
measurable against the variable-height/structural gates that already drive `compute`
over a balanced tree — so, like Slice 29, it needs **no new gate** and leaves no
governance debt.

Because Option A changes the core `compute` contract and adds a second provider
primitive, it should **start with a brainstorm and spec** rather than a drive-by —
the increment needs the end-exclusive visible-end semantics pinned, the second
primitive's half-open/clamp contract specified, and the equivalence oracle and
benchmark deltas defined up front. The A-vs-C call (finish deepening the vertical
axis vs. open consumer-facing geometry queries toward editing) is a genuine product
decision worth surfacing to the user: Option A is the consistent algorithmic next
step now that `lineAt` is optimal, Option C is the larger product direction toward
tap-to-caret editing, and Option E remains the strongest pick if the preference is to
close the last standing infra item instead.

## Slice 29 Review Conclusion

Slice 29 delivered the intended algorithmic increment cleanly: the balanced-tree
y→line query through `ViewportVirtualizer.lineAt` is now a single O(log N) subtree-sum
descent instead of the generic O(log²N) binary search, delivered as a defaulted
`LineMetricsSource.lineIndex(containingOffset:)` hook so existing providers stay
source-compatible and `lineAt` keeps full ownership of Slice 27's validation/clamp
semantics. The witness-table dispatch is correct and test-guarded, the half-open
boundary convention is locked by an oracle and shared between the fallback and
`compute`, and the optimization is byte-identical to the generic search (all five
line-query checksums match across local, PR-head, and merged-code runs) while running
~12× faster locally and ~7–10× faster on hosted Linux at 1M lines. The carried
provider-doc P3 (`join2`/`join3` naming) is finally retired, and the change holds
every hard constraint: Foundation-free, zero-dependency, O(1) core memory, and
cross-target verified.

The review found **no P0, P1, or P2 issues** against the merged result. The two P3s
are minor: an evidence-precision nuance (the cited PR-head run is one docs-only commit
behind PR #53's final head — transparent, and the merged-code push run is the
authoritative anchor) and the deliberate decision to keep uniform providers on the
generic fallback. With the vertical `lineAt` path now asymptotically optimal and
CI-protected, and **no governance debt** left behind, Slice 29 closes the
vertical-query optimization arc for `lineAt` and hands off to a clean choice — most
naturally extending the same provider-native search into `compute`, the last
O(log²N) balanced-tree consumer and the scroll hot path.
