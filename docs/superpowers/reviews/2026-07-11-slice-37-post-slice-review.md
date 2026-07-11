# Slice 37 Post-Slice Review

Date: 2026-07-11

## Scope Reviewed

This review covers Slice 37: **`pointAt(x:y:)` — the 2D composite position query**.
It adds `ViewportVirtualizer.pointAt(x:y:lineMetrics:columnMetrics:)`, the engine's
**first two-axis primitive**, mapping a single point to `(line, cell)` by composing
the vertical `lineAt` over a `LineMetricsSource` with the horizontal `columnAt` over
a `LineHorizontalMetricsSource`. It is the Slice 36 review's recommended **Option B**
("the product leap, now fully unblocked") and the user-selected direction, scoped by
the user to the **position-only** form — the geometry-bearing `pointGeometryAt`
companion was explicitly deferred — with a **nested** result shape.

Slice 37 is a **functional/capability slice**, the first since Slice 35. It is pure
composition: it adds **no new search code, no new metrics protocol, no new provider,
and no new `ViewportValidationError` case**. Every inverse search stays in the two
already-shipped, already-hosted-gated 1D queries; `pointAt` only orders them and
assembles their results. Following the project's established functional → promotion
rhythm, its `--point-query --gate` is **local-only** this slice; CI promotion is the
deferred follow-up.

The slice was delivered through **two** PRs, both now merged:

- **PR #77** (`slice-37-point-query`), title *"Slice 37: pointAt(x:y:) 2D composite
  position query"*, verified head `033e7309f235e72a7af8155e4a63772b8640ca16`
  (`033e730`), merged to `main` as `ba51a33b5fae5d98c322306976d03845700b0dc8`
  (`ba51a33`) by `maldrakar` at 2026-07-11T11:09:25Z — the core query, the three
  result types, the full test suite, the benchmark mode + local gate, `AGENTS.md`,
  and the design/plan/verification docs, with the verification record's hosted
  section left as an explicit `## Hosted Proof — Pending` placeholder.
- **PR #78** (`slice-37-post-merge-hosted-proof`), title *"Slice 37 follow-up: record
  point-query hosted proof"*, verified head `d46d25bc7ff464da67c96425bbec3813a2dfe89a`
  (`d46d25b`), merged as `fc1e4b982c57ae2b379a038a998b52dc0dcb3acf` (`fc1e4b9`,
  current `main` HEAD) by `maldrakar` at 2026-07-11T18:31:53Z — a **genuinely
  docs-only** follow-up (only the verification Markdown) filling in the real PR-head
  and post-merge run IDs.

**Both PRs are merged at review time**, so `main`'s verification record carries real
hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-07-10-point-query-design.md`
- `docs/superpowers/plans/2026-07-10-point-query.md`
- `docs/superpowers/verification/2026-07-10-point-query.md`
- `docs/superpowers/reviews/2026-07-10-slice-36-post-slice-review.md` (which set this
  slice's direction), plus the 1D precedents (Slices 33/35 reviews)
- `Sources/TextEngineCore/PointQuery.swift`, `Sources/TextEngineCore/ViewportTypes.swift`
- `Sources/ViewportBenchmarks/PointQueryBenchmark.swift` and its three wiring files
- All four new test files; the 1D queries this slice composes (`PositionQuery.swift`,
  `HorizontalPositionQuery.swift`) and the providers it drives
- PR #77 / #78 metadata, hosted run evidence at **step level**, merge parentage, and
  the merged Slice 37 diff

The reviewed Slice 37 range (Slice 36 review merge → current `main` HEAD), excluding
this review document itself, is:

```text
e3a7a28..fc1e4b9
```

`git merge-base --is-ancestor e3a7a28 fc1e4b9` confirms the Slice 36 review merge
(PR #76, `e3a7a28`) is a clean ancestor, so the range captures exactly the Slice 37
work. Merge parentage confirmed via `git rev-list --parents`: `ba51a33` (PR #77)'s
parents are the base `e3a7a28` and the verified PR head `033e730`
(`ba51a33^2 == 033e730`); `fc1e4b9` (PR #78) merges the post-merge-proof commit
`d46d25b` onto `ba51a33` (`fc1e4b9^2 == d46d25b`). A fresh name-only diff confirms
the range touches **no** `.github/**` path — the workflow is untouched, so the new
gate is provably local-only, exactly as the spec's Decision 6 requires.

## Product Brief Alignment

The brief wants a headless layout/virtualization core supporting realistic editing of
100k+ line / >10 MB documents, Foundation-free, Embedded-compatible, with core-owned
memory sub-linear in document size and the document behind a provider abstraction.

Slice 37 delivers the primitive every real consumer of such an engine ultimately
needs: **hit-testing a point**. A pointer lands at `(x, y)`; the engine must answer
*which line, and which cell within it*. Before this slice both halves existed but
nothing composed them, so every click-to-caret / selection consumer had to re-derive
three subtle rules itself — the ordering dependency (`columnAt` needs an `inLine` that
only `lineAt` can produce), the failure precedence (a vertical failure must
short-circuit), and the blank-line seam (a located line with zero cells is neither an
empty document nor a normal cell hit). Left to callers, these diverge. The core now
owns the one correct composition, once.

Every hard constraint holds and was re-verified: **Foundation-free** (both scans
empty), **zero-dependency**, **Embedded-compatible** (the new types are non-indirect
value structs/enums over `Int`/`Double` — no existentials, strings, or reflection),
**O(1) core memory** (`pointAt` allocates nothing beyond the returned value structs
and delegates all searching), and **iOS/WASM-portable** (the hosted iOS compile step
ran and passed on merged code). The cost is exactly the sum of the two 1D envelopes:
O(log N) + O(log M) queries, adding **no search of its own**.

## Delivered Design

Merged Slice 37 diff (`e3a7a28..fc1e4b9`):

```text
 AGENTS.md                                          |   14 +-
 Sources/TextEngineCore/PointQuery.swift            |   50 +
 Sources/TextEngineCore/ViewportTypes.swift         |   23 +
 Sources/ViewportBenchmarks/BenchmarkOptions.swift  |   11 +-
 Sources/ViewportBenchmarks/BenchmarkProgram.swift  |    2 +
 Sources/ViewportBenchmarks/PointQueryBenchmark.swift |  176 ++++
 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift |    2 +
 Tests/TextEngineCoreTests/PointAtDispatchTests.swift |   68 ++
 Tests/TextEngineCoreTests/PointAtEquivalenceTests.swift |  87 ++
 Tests/TextEngineCoreTests/PointAtTests.swift       |  173 ++++
 Tests/TextEngineReferenceProvidersTests/PointAtReferenceProviderTests.swift | 45 +
 (plus design, plan, verification docs under docs/superpowers/**)
```

The **entire core change is 73 lines**: a 20-line method and three small types. That
ratio — 73 core lines against 373 test lines — is the correct shape for a composition
slice.

### The query (Decisions 1, 3, 5)

`Sources/TextEngineCore/PointQuery.swift` is an `extension ViewportVirtualizer`
holding a two-level switch that is **character-for-character the spec's Decision 3
code block**:

```swift
switch lineAt(y: y, metrics: lineMetrics) {
case let .failure(error): return .failure(error)   // vertical short-circuits
case .empty:              return .empty            // empty document
case let .line(lineLocation):
    switch columnAt(x: x, inLine: lineLocation.lineIndex, metrics: columnMetrics) {
    case let .failure(error): return .failure(error)
    case .empty:              return .point(PointLocation(line: lineLocation, column: .blankLine))
    case let .column(c):      return .point(PointLocation(line: lineLocation, column: .cell(c)))
    }
}
```

Every property the spec claims is forced by this structure rather than asserted:

- **Vertical runs first and wins ties.** The horizontal query is parameterized by a
  line index only the vertical query can produce, so a vertical failure short-circuits
  and `columnAt` is never called. This is not a preference — it is the only definable
  behavior.
- **The shared error type composes with no mapping.** Both 1D queries return
  `ViewportValidationError`, so either axis's error passes through unchanged. The enum
  is genuinely untouched (I diffed it: `ViewportTypes.swift` gains only the three new
  types, no new case).
- **Both clamps survive verbatim.** `line.clamp` and the cell's `clamp` are
  independent fields on independent structs, so a both-axes-clamped point records both
  with no combined-clamp type.
- **Validation precedes each axis's zero-count short-circuit.** I traced both 1D
  ladders (`PositionQuery.swift`, `HorizontalPositionQuery.swift`): `count < 0` →
  `!isFinite` → O(1) contract probe → zero-count branch. So a non-finite `y` beats
  `.empty` and a non-finite `x` beats `.blankLine` — while an empty document still
  returns `.empty` even for `x = NaN`, because the vertical query short-circuits before
  `x` is ever examined. The doc comment now states exactly this (see Pre-Merge
  Corrections below).

### The result shape (Decision 2)

`PointQuery` (`.point` / `.empty` / `.failure`) nests a `PointLocation` (always a real
`LineLocation` + a `ColumnResolution`), and `ColumnResolution` is `.cell(ColumnLocation)`
or `.blankLine`. Three judgments here are worth endorsing explicitly:

- **`.point` always carries a line**, so a caller that only wants the line (gutter,
  line highlight) reads `p.line` without branching on blank-ness.
- **`.blankLine` is a named case, not `nil`** — matching the codebase's explicit-enum
  convention, and deliberately *not* colliding with the top-level `.empty` (empty
  *document*), which a nested `.empty` would have muddled.
- **`ColumnResolution` never carries `.failure`.** A horizontal failure surfaces at the
  top level, so the nested type has exactly the two states reachable after a horizontal
  success-or-empty — a caller pattern-matching it need not consider an impossible case.
  Nesting the whole `ColumnQuery` would have leaked an unreachable `.failure`.

I probed this shape for an evolution trap and found none: a future `pointGeometryAt`
composes cleanly as a parallel `PointGeometryLocation(line: LineGeometryLocation,
column: ColumnGeometryResolution)` without appending any case to `PointQuery`.

### Tests (373 lines, +19 tests: 213 → 232)

- **`PointAtTests` (11)** — one hardcoded-expectation test per Decision 4 row, plus
  vertical-clamp-only, horizontal-clamp-only, both-axes-clamped, vertical-failure
  short-circuit, horizontal-failure surfacing, and failure precedence. These are the
  independent pinning.
- **`PointAtEquivalenceTests` (3)** — the composition-parity oracle over an 81-cell
  `(x, y)` grid (each axis: below, at 0, mid, boundary, at/above end, **plus `NaN`,
  `±inf`**) across uniform, non-uniform-with-a-blank-line, and empty-document sources.
  The non-finite × empty-document / blank-line cells are what lock in the
  validation-ordering contract.
- **`PointAtDispatchTests` (3)** — an event-log horizontal source proving the
  horizontal source is **never touched** on the vertical `.failure` and `.empty` paths,
  and that on the `.line` path every horizontal call carries `inLine ==` the
  vertically-located `lineIndex`.
- **`PointAtReferenceProviderTests` (2)** — drives the composite over
  `PrefixSumLineMetrics` × `PrefixSumColumnMetrics`, correctly placed in the
  reference-provider test target so the core test target keeps its `TextEngineCore`-only
  dependency.

### Benchmark + local gate (Decision 6)

`PointQueryBenchmark.swift` adds four scenarios (`uniform_100k`/`_1m`,
`prefixsum_100k`/`_1m`) varying only the **vertical** provider, with
`UniformColumnMetrics` held constant horizontally. That constraint is real, not
laziness: `pointAt` feeds the located line index into `columnAt`, so the horizontal
source must define cells for *every* line — and `PrefixSumColumnMetrics` stores per-line
prefix sums, making a 1M-line × 256-cell pairing O(N·M) storage. `--gate` became valid
for `--point-query` automatically because the parser's rejection is a denylist, exactly
as the spec predicted; no parser edit was needed.

`AGENTS.md` gains the architecture paragraph, the command entry, and the flag lists —
and correctly labels the gate **"local (not-yet-CI)"**.

### Pre-merge corrections (a process highlight)

A pre-merge review caught **three descriptions that overclaimed**, all corrected before
merge, and I re-verified each against the code rather than the commit message:

1. The `PointQuery.swift` doc comment implied a non-finite coordinate is checked before
   *either* axis's zero-count short-circuit. False for the empty document + `x = NaN`
   case. **The code was right; the comment was wrong**, and now states the real contract.
2. The benchmark claimed its uniform scenarios cover an "O(1) native-arithmetic vertical
   path". Genuinely false — neither `UniformLineMetrics` nor `UniformColumnMetrics`
   overrides its inverse hook, so **all four scenarios take the generic binary-search
   fallback on both axes**. I confirmed the absence of both overrides. This correction
   matters: the follow-up promotion slice would otherwise have reasoned about gate
   coverage from a false premise.
3. The spec asked the workload to exercise "at least one blank line", which its own
   `UniformColumnMetrics` choice makes unreachable. Now stated explicitly, with the
   reasoning recorded (a blank line short-circuits `columnAt` *early*, so including one
   would only *lower* measured latency).

Catching a doc that overclaims relative to correct code — and fixing the doc rather than
"fixing" the code — is exactly the right instinct.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `fc1e4b9`)

- `git diff --name-only e3a7a28..fc1e4b9 -- .github` → **empty**. The gate is provably
  local-only; the workflow is untouched.
- `git diff --check e3a7a28..fc1e4b9` → no output, exit `0`.
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
  `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `swift build -c release` → `Build complete!`
- `swift test` → **232 tests, 0 failures** (+19 over the Slice 36 baseline of 213,
  matching the plan's expected delta exactly), plus the expected empty Swift Testing
  harness line.
- **All ten gates re-run locally, all `gate=pass`, `failures=0`.** The **36 checksums
  across the nine pre-existing gates are byte-identical** to the Slice 36 baseline, and
  the **four `--point-query` checksums** (`64166237440`, `640022280960`, `64166280960`,
  `640022228480`) reproduce the verification record exactly. This is the strict-additivity
  proof: `pointAt` moved no existing search or provider path.
- `--memory-shape` → `invariant=pass` on all five scenarios, `core_owned_bytes`
  byte-identical per provider (74/74/74/90/90).
- `./.github/scripts/cross-target-compile.sh --self-test` → `self_test=pass`.

### Hosted runs (verified live via `gh`, at step-log level, not job conclusion)

Per the project's standing "a green job can hide a dead `continue-on-error` step" lesson,
both runs were checked at the **step** level:

- **PR #77 final-head run `29150235152`** (head `033e730`, event `pull_request`):
  conclusion `success`; all three required jobs `success`.
- **Post-merge push run `29150501304`** on merge commit `ba51a33` (event `push`, branch
  `main`): conclusion `success`; all three required jobs `success`. **This is the
  merged-code evidence anchor for Slice 37.** Step-level: step 5 `Complete docs-only PR`
  = `skipped` (correct — the merge carries Swift, so the heavy path runs); step 7 `Run
  host tests` = `success` with **`Executed 232 tests, with 0 failures`** on merged code;
  steps 8–16 (**all nine blocking latency gates**) = `success`; steps 17–18 (memory
  diagnostics) = `success`; step 19 (realistic observation) = `skipped`, correct on a
  `push` event. In the other two required jobs, the substantive steps genuinely **ran**:
  `Compile cross-target packages for iOS` = `success` (not skipped) and `Observe
  cross-target packages for WASM` = `success` — so the new public API's iOS portability
  is proven on merged code.

Two independent cross-checks I ran against the raw push-run log:

- **`grep -c "mode=point_query"` over the full hosted log returns `0`.** The new gate is
  genuinely absent from hosted CI — Decision 6's local-only scope is a verified fact, not
  an assertion. (`gate=fail` count is also `0`.)
- Every hosted query-gate checksum is **byte-identical** to the local table, so Slice 37
  moved no measured path on hosted Linux x86_64 either.

Merge parentage confirms `ba51a33^2 == 033e730` — the proof anchors the actually-merged
head. PR #78 was a genuinely docs-only follow-up, so it legitimately took the trusted
docs-only path, and the workflow has not changed since `ba51a33`.

## Git History

Seventeen non-merge commits across the two PRs, with correct conventional-commit
prefixes and clean one-logical-step-per-commit discipline:

```text
75a82de docs: add 2D point-query design
9f9da4d docs: refine 2D point-query design
cdd68b0 docs: use line-agnostic horizontal provider in point benchmark
12fa848 docs: add slice 37 2D point-query implementation plan
ea5c0da feat: add pointAt 2D composite position query
990e43d test: pin pointAt failure precedence and horizontal-dispatch contract
02a5c16 test: add pointAt composition-parity oracle
d6bcf5a test: exercise pointAt over prefix-sum reference providers
af17089 feat: add --point-query benchmark mode with local gate
c8b26d7 docs: describe pointAt 2D composite and its local point-query gate
85472c0 docs: record 2D point-query local verification
25832de docs: note pointAt same-document precondition on both metrics sources
35bc4b3 docs: correct pointAt validation-ordering doc comment
bf896ca docs: correct point-query gate coverage description
1a8d52e test: pin pointAt invalid-metrics failure pass-through
033e730 docs: record slice 37 post-review corrections   ← PR #77 head (ba51a33)
d46d25b docs: fill point-query slice 37 hosted proof     ← PR #78 head (fc1e4b9)
```

Spec → plan precede all code. The `feat: add pointAt` commit ships its unit tests
alongside the implementation, which is the **established house pattern** (Slice 35's
`feat: add columnGeometryAt` commit carried its 178-line `ColumnGeometryAtTests` the
same way), not a deviation — though it does mean the TDD red state is not preserved as a
distinct commit. The PR head is `033e730`, exactly the head run `29150235152` tested — no
post-head drift. The two-PR split (implementation + local proof, then docs-only
post-merge proof) is the standard pattern.

## Code Review Findings

Reviewed across composition correctness, spec fidelity, test coverage, the hard
constraints, API evolution, and benchmark integrity. An independent adversarial pass was
run over the merged diff, and every finding below was re-verified against the source
before being recorded.

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. I could not construct any input where `pointAt`'s result differs from
`(lineAt, columnAt)` composed per the spec's Decision 4 table. Clamp propagation is
lossless on both axes including the both-clamped case; failure precedence is correct and
structurally forced; the blank-line seam is handled; the hard constraints hold.

### P2 / Production Readiness

**1. The new `--point-query` gate is inert as a regression detector (~3,700×–4,100×
headroom) — and it mints four *new* budgets at that inflated scale.**
`Sources/ViewportBenchmarks/PointQueryBenchmark.swift:28-40`. Measured this review:
`uniform_100k` p95 = **32 ns** against a **120,000 ns** budget; `prefixsum_1m` p95 =
**70 ns** against **240,000 ns**. Concretely: replacing the O(log M)
`binarySearchColumnIndex` with a **linear scan over all 256 cells** (~hundreds of ns
added) would still report `gate=pass` with two orders of magnitude to spare. The gate
therefore guards the composite's *correctness-under-load* and determinism (via checksum
+ `failures=0`), but **not** its latency in any practical sense.

This is the already-known, user-acknowledged gate-budget-calibration debt (the same
2,400×–7,000× looseness affects every query gate), so it is **not a new class of
problem** and not a Slice 37 defect in isolation. It is recorded here as **P2** for one
specific reason: **the natural follow-up slice is promoting `--point-query` to the tenth
blocking hosted gate, and promoting it as-is would enshrine an inert gate in required
CI** — spending a CI step and a governance slice on a check that cannot fail. The
sequencing implication is spelled out under Recommended Slice 38 Selection.

**2. `pointAt` is the first API where the *core* hands an unbounded index to a source it
cannot bound-check — and mismatched sources trap rather than returning `.failure`.**
`Sources/TextEngineCore/PointQuery.swift:40` feeds `lineLocation.lineIndex` into
`columnAt(inLine:)`. `LineHorizontalMetricsSource` deliberately carries no line count
(Slice 33 Decision 1), so nothing can validate that the two sources describe the same
document. Concrete failure:

```swift
let v = UniformLineMetrics(lineCount: 10, lineHeight: 16.0)
let h = PrefixSumColumnMetrics(advancesPerLine: [[8.0]])   // horizontal knows 1 line
ViewportVirtualizer.pointAt(x: 0, y: 50, lineMetrics: v, columnMetrics: h)
```

→ `columnAt(inLine: 3)` → `PrefixSumColumnMetrics.columnCount(inLine:)` → `prefix[3]` →
**Swift array out-of-bounds trap** (I confirmed the provider indexes `prefix[line]`
directly), *not* a `.failure`. A consumer with lazily-materialized horizontal metrics —
only the visible lines, which is a natural design for a large document — crashes on any
click that clamps below the materialized region.

In fairness, this is **documented**, in both the spec's Risks section and the method's
`- Precondition:` doc comment, and it is the same contract-trusting posture the 1D
`columnAt` already takes (a caller passing a bad `inLine` traps identically). So the
merged code is correct against its stated contract, and this is **not** a defect to fix
retroactively. What changed is *who chooses the index*: in the 1D API the caller picked
`inLine` and owned the precondition; in the composite the **core** picks it, so the
precondition is now violable by a caller who never touches an index at all. There is no
test pinning the behavior, no defense in depth, and no protocol affordance to make the
mismatch detectable. This deserves an explicit decision (accept / add an optional
`lineCount` hook / debug-only assertion) in the `pointGeometryAt` slice, which will
inherit the identical seam.

### P3 / Minor But Valid

**1. The single most common real-world hit-test is untested: a vertical clamp landing on
a blank line.** Every blank-line test uses an in-range `y` (`PointAtTests.swift:45`,
`PointAtReferenceProviderTests.swift:38`, and the oracle's blank line 2, whose span is
never reached by a clamped `y`). So "the document ends with a trailing blank line and the
user clicks in the empty area below it" — expected
`.point(line: L(last, .clampedToBottom), column: .blankLine)` — is pinned by **no test**.
The behavior is correct by construction (I traced it), but a regression would go
unnoticed. One assertion fixes it.

**2. The 2D benchmark samples a 1-D diagonal.** `PointQueryBenchmark.swift:106-107`
derives *both* coordinates from the same `deterministicScrollOffset(sample:)`, whose
fraction is `((sample * 37) % 1000) / 1000`. So in every in-range sample
`x / width == y / totalHeight` **exactly**, and there are only **1,000 distinct `(x, y)`
pairs**, each replayed ~1,280× across the 1.28M operations — a tiny, fully-cached working
set with a perfectly predictable branch pattern. It measures a correlated diagonal
through the document, not the 2D space. Decorrelating the axes (e.g. offsetting the
sample for `x`) would cost one line and make the composite's cache behavior honest. This
is genuinely new to Slice 37 — it is the first benchmark deriving *two* coordinates from
the shared helper.

**3. The composition-parity oracle is a verbatim copy of the implementation.**
`PointAtEquivalenceTests.swift:23-32` is the same two-level switch as
`PointQuery.swift:34-47`. It is a rigorous **change-detector** for `pointAt`'s body, but
it is not an independent proof of the composition rules — it would pass if implementation
and oracle were wrong in the same way. The real independent pinning lives in
`PointAtTests`' hardcoded expectations, which is good and sufficient. Calibration note,
not a defect; but the spec's framing of the oracle as "load-bearing" slightly oversells
what it can catch.

**4. The dispatch test asserts less than the spec promised.** The spec's Testing Strategy
promises an "ordered event log … asserting order and `inLine` threading";
`PointAtDispatchTests.swift:57-66` asserts that every event carries the located line and
that `columnIndex` is called exactly once, but never asserts the *order* of the
horizontal calls. It also only exercises an in-range `y`, so it never directly proves a
*clamped* line index is threaded (the oracle covers that indirectly).

**5. The gate's checksum folds both axes additively.** `PointQueryBenchmark.swift:49-64`
accumulates `lineIndex + lineClamp + columnIndex + cellClamp` into one scalar, so a
regression that **swapped the two axes' indices** would produce a byte-identical checksum.
The unit tests would catch such a bug, so impact is low — but the checksum is the
"workload unchanged" integrity anchor the promotion slice will lean on, and it is weaker
than it looks.

**6. No point scenario measures a non-uniform horizontal metric.** The
"by necessity, not laziness" argument for `UniformColumnMetrics` is sound about
`PrefixSumColumnMetrics` (O(N·M) storage), but a *line-agnostic variable-advance* source —
one shared prefix array, ignoring `line` — would be O(M) memory, trivial to define in the
benchmark target, and would exercise the realistic proportional-advance search under the
composite. The claim is slightly stronger than the evidence supports.

**7. Carried / standing items, unchanged and correctly out of scope.** Budgets remain
macOS-calibrated (Option E); both horizontal providers remain fallback-bound with no
native `columnIndex` descent (Option D); the new public types are not `Sendable`,
consistent with every existing public type in the codebase.

**A correction to this review series: the long-carried `join(_:_:)` P3 is retired and
should stop being carried.** Reviews from Slice 25 through Slice 36 each forwarded a P3
noting that the bulk-edits spec names the join primitive `join(_:_:)` while the code ships
`join3`/`join2`. That drift **no longer exists**: the spec
(`docs/superpowers/specs/2026-06-20-bulk-structural-edits-design.md:91-93`) already carries
a "Shipped naming note (Slice 29)" reconciling the two. It was retired six slices ago and
has been copied forward by inertia since. Dropped here deliberately.

No P3 changes whether the merged result is correct.

## Risks And Gaps

### The functional → promotion pair is open again (expected, by design)

Slice 37 is a capability slice, so — like Slices 31, 33, and 35 before it — it **hands off
with CI-promotion debt**: a tenth measurable path (`--point-query`) now exists and is
gated **only locally**. This is the established rhythm, not an oversight. But see P2 #1:
unlike the four prior promotions, this one should **not** be executed mechanically,
because the budget it would promote cannot fail.

### The two-source precondition is now a core-supplied index

Per P2 #2. Documented and consistent with the 1D contract, but the composite is where a
source-pairing mistake stops being a caller's indexing bug and becomes a crash on an
ordinary click. The `pointGeometryAt` slice inherits this seam verbatim and should settle
it explicitly.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider observation remains
PR-only `continue-on-error`; the `Main` ruleset keeps its documented bypass-actor shape.
None were in scope, and the workflow was not touched at all this slice.

## Lessons For The Next Slice

1. **Composition slices should be mostly tests, and this one was.** 73 core lines against
   373 test lines. When the implementation is forced by the type structure (the vertical
   short-circuit is the *only* definable behavior), the engineering risk moves entirely
   into the contract's edges — non-finite coordinates, the blank-line seam, clamp
   propagation, dispatch ordering — which is exactly where the tests went.
2. **Fix the doc, not the code, when the doc overclaims.** All three pre-merge corrections
   were documentation defects against correct code. The benchmark's false "native
   arithmetic path" claim is the instructive one: left uncorrected, the *promotion* slice
   would have reasoned about gate coverage from a premise that was simply untrue. Cheap to
   fix now; expensive to discover downstream.
3. **A passing gate is not a guarding gate.** Slice 37's gate passes with ~4,000× headroom;
   a linear-scan regression would sail through it. Before promoting a gate to blocking CI,
   ask what regression it would actually *catch* — otherwise the promotion buys a green
   checkmark, not protection.
4. **Watch for shared-helper correlation when a benchmark grows an axis.**
   `deterministicScrollOffset(sample:)` was correct for every 1D gate; reusing it for both
   coordinates silently collapsed the 2D workload onto a diagonal with 1,000 distinct
   points. The first multi-axis consumer of a single-axis helper deserves a second look.
5. **The clean-evidence convention held for the eleventh source-touching slice.** Explicit
   `Pending` placeholder in PR #77, real run IDs filled only in the genuinely docs-only
   post-merge follow-up (PR #78) against the stable head. Keep it.

## Slice 38 Candidate Options

### Option A: promote `--point-query` to the tenth blocking hosted gate

The mechanical next step in the functional → promotion rhythm (Slices 28/32/34/36),
zero-Swift, one workflow step. **But per P2 #1 the budget it would promote cannot fail** —
a 256-cell linear scan passes it. Promoting as-is spends a slice and a permanent CI step
on an inert check. It should either be **preceded by** or **folded into** Option C.

### Option C: gate-budget re-calibration (the user has already committed to this)

Re-derive tight, meaningful p95/p99 budgets for the query gates (`--line-query`,
`--line-geometry-query`, `--column-query`, `--column-geometry-query`, `--point-query`),
which currently run 2,400×–7,000× looser than observed latency and therefore cannot catch
constant-factor regressions — the exact class of regression a latency gate exists to catch.
The user identified this on 2026-07-11 and decided it warrants a dedicated slice. It is now
**directly blocking the value of Option A**, and it retires debt across *all five* query
gates at once, not just the new one.

### Option B: `pointGeometryAt(x:y:)` — the geometry-bearing 2D composite

Compose `lineGeometryAt` ∘ `columnGeometryAt` into a 2D result carrying each axis's box +
fraction + clamp: the primitive a click-to-caret / caret-snapping consumer ultimately wants,
and the explicit deferral from this slice's own scoping. Design surface is modest (the shape
is already proven parallel), and it would be the natural place to settle the P2 #2
source-pairing precondition. The highest *product* value of the three.

### Option D / E: horizontal native descent; standing infra

Native `columnIndex` overrides for the two horizontal providers (retiring the fallback-bound
item), or WASM-blocking / Linux budget re-baseline. Both remain valid and both are
independent of the point arc.

## Recommended Slice 38 Selection

Recommended Slice 38 is a **product call to surface to the user**, leaning **Option C — the
gate-budget re-calibration** — with **Option B (`pointGeometryAt`)** as the strong product
alternative.

The reasoning: normally this slice would hand off to a mechanical promotion (Option A), and
that is what the four prior functional slices did. **This time the promotion is the wrong
first move.** The `--point-query` gate passes with ~4,000× headroom; promoting it would add a
required CI step that no realistic regression can trip. The user has *already* decided the
budget-calibration work deserves a dedicated slice, and doing it next means the subsequent
promotion promotes a gate that actually guards something — and it simultaneously repairs the
four *already-blocking* query gates that today are equally inert. That ordering (C, then A,
possibly folded together) converts a governance formality into real protection.

If the user would rather keep the product arc moving, **Option B is the right alternative**:
it completes the 2D story with the geometry the caret actually needs, and it is the natural
home for the P2 #2 precondition decision. Option A alone is the one thing I would *not*
recommend next, and if it is chosen anyway it should carry the recalibrated budgets with it.

Whichever is selected, keep functional/capability work and CI/infra work in separate slices,
per the project's standing convention.

## Slice 37 Review Conclusion

Slice 37 delivered its capability increment cleanly. `pointAt(x:y:lineMetrics:columnMetrics:)`
is the engine's first two-axis primitive, and it is exactly what a composite should be: 20
lines of core logic that add **no search, no protocol, no provider, and no error case**, whose
every semantic property — vertical-first ordering, failure short-circuit, independent clamp
preservation, the blank-line seam, validation-before-zero-count on both axes — is *forced* by
the composition rather than asserted, and is then pinned by 373 lines of tests including an
81-cell parity oracle that crosses both axes with `NaN` and `±inf`. The nested
`PointQuery` / `PointLocation` / `ColumnResolution` shape is well-judged and leaves a clean
path for the deferred geometry companion.

The review found **no P0 and no P1**: I could not construct an input where the composite
diverges from its specified table. Strict additivity is **proven, not claimed** — all 36
checksums across the nine pre-existing gates are byte-identical locally *and* in the hosted
push-run log, and the test count moved exactly +19 (213 → 232). Every hard constraint holds
and was re-verified: Foundation-free (both scans empty), zero-dependency, Embedded-safe types,
O(1) core memory, iOS-portable (the hosted iOS compile step genuinely ran on merged code).
Hosted proof is anchored on the merged code at step level (push run `29150501304`, merge
`ba51a33`, whose second parent is the tested head `033e730`), and `grep -c "mode=point_query"`
over that log returns **0** — confirming the gate's local-only scope as a verified fact rather
than an assertion. Three pre-merge overclaims were caught and corrected in the docs, with the
code left correctly alone.

The two **P2**s are both forward-looking rather than retroactive: the new gate passes with
~4,000× headroom and so cannot catch the constant-factor regressions a latency gate exists to
catch (already-known, user-acknowledged debt — but now directly bearing on the promotion that
would naturally come next), and the composite is the first API where the **core** supplies an
`inLine` to a horizontal source that cannot bound-check it, so a mismatched source pairing
traps instead of returning `.failure` (documented as a precondition, but untested and worth an
explicit decision in the next 2D slice). The six P3s are minor and specific — chiefly an
untested clamped-onto-blank-line hit-test and a benchmark that collapses its 2D workload onto a
diagonal.

Slice 37 hands off with the expected, by-design CI-promotion debt — but with a twist worth
naming: **the usual next move, promoting the gate, would promote a gate that cannot fail.**
That makes Slice 38 a genuine decision rather than a formality: recalibrate the query-gate
budgets first (Option C, the lean, already user-endorsed) so the promotion is worth making, or
carry the product arc forward with the geometry-bearing `pointGeometryAt` (Option B).
</content>
