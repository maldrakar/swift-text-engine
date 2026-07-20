# Slice 47 — Rename the WASM required check, and pin the name to the ruleset

## Summary

Rename the CI job and its required-status-check context
`WASM cross-target observation` → `WASM cross-target compile`, updating the
`Main` ruleset in the same slice, so a required check that **blocks merges**
stops describing itself as advisory. Add a standing test that pins each of the
three job `name:` fields to the exact required-check context string, so the next
rename cannot silently drift from the ruleset. Fold in the five P3 residuals
Slice 46 left in the files this slice already reopens.

This is Slice 46's own named follow-up (its review's P2 #5), and the only open
item whose cost grows with delay.

## Motivation — brief alignment

The brief's six success criteria are, as of Slice 46, all met with no
observational holdouts. This slice adds no engine capability and moves no
budget; it repairs a governance signal.

The defect is one of description, not behavior: WASM cross-compilation genuinely
blocks (four `result=pass blocking=true` lines per run, across two kinds and two
packages), but the required check announcing that fact is named "observation".
Anyone reading a PR's check list, or the ruleset, concludes WASM is advisory when
it is load-bearing. That is precisely the class of confusion Slice 46 was created
to eliminate — it discovered that a step everyone believed was "observed" had run
**zero times** — and leaving the wrong name in place re-seeds the same
misunderstanding one layer up, in the place a human actually looks.

The cost is not static. Every subsequent doc, review, and memory entry accretes
around the wrong name, and the fix is order-sensitive: the rename and the ruleset
update must be sequenced deliberately or PRs wedge on a context nobody reports.
That sequencing is cheapest to manage now, while the slice is fresh and no
unrelated PRs are in flight.

## Background — current state

### In the workflow, three sites carry the stale name; only one is the contract

`.github/workflows/swift-ci.yml` holds the name in three places:

| Site | Line | Is it the required-check context? |
|---|---|---|
| job key `wasm-cross-target-observation` | 216 | No — internal id, no `needs:` references it |
| `name: WASM cross-target observation` | 217 | **Yes** — this string *is* the context |
| `Complete docs-only PR` echo `job=wasm-cross-target-observation` | 271 | No — log text |

Only line 217 is coupled to repository configuration. The other two are safe to
change unilaterally, and leaving them stale would re-seed the same rot the slice
exists to remove.

### The full site list is seven, and the obvious search finds four of them

Enumerating the stale name exposed two ways a search can lie, both worth
recording because AC1 depends on getting this right:

- **`rg` skips hidden directories by default**, so a plain
  `rg 'WASM cross-target observation' .` never looks inside `.github/` — it
  silently misses the workflow, which is the entire subject of the slice. Needs
  `--hidden`.
- **One occurrence is wrapped across a line break** (`AGENTS.md:273-274`, inside
  the "Known wart" block), so a line-oriented search misses it even with
  `--hidden`. Needs multiline (`-U`) with a `\s+` join.

The honest full set is **seven sites in three files**:

| File | Lines |
|---|---|
| `.github/workflows/swift-ci.yml` | 216, 217, 271 |
| `AGENTS.md` | 261, 273–274 (wrapped), 288 |
| `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` | 26 |

A search that reports "clean" while structurally unable to see the file being
changed is the same failure shape as a `continue-on-error` gate. AC1 therefore
pins the *command*, not just the expectation.

### The ruleset requires the old string, verified live

`gh api repos/maldrakar/swift-text-engine/rulesets/17656807` on `be763dc`
returns ruleset `Main` requiring exactly three contexts:

```
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

Strict required-status-check policy is enabled. The bypass-actor shape from
`docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md` is
unchanged and must survive this slice untouched.

### Nothing pins the job name to the ruleset

`WorkflowShapeTests` pins gate-step shape, `continue-on-error`, docs-only guards,
step ordering, the WASM step's `env:` dict, and the container↔SDK version
relationship. It does **not** pin any job's `name:`. So the exact hazard this
slice is paying down — a `name:` edited without a matching ruleset update — is
today invisible to `swift test`, for all three required contexts, not just WASM.

## Design decisions

### Decision 1 — Sequence: drop the old context, rename, re-add the new one

The context is the job's `name:` field; the ruleset lives outside the
repository. The two therefore **cannot** land atomically, and the naive order in
either direction wedges every open PR on a context no run will ever report.

Chosen sequence:

1. Record `gh api` snapshot (**before**).
2. Open the rename PR. It **wedges** — expected, and recorded as evidence.
3. Remove `WASM cross-target observation` from the ruleset's required contexts
   (two remain). Record snapshot (**intermediate**). The PR unblocks.
4. Read the PR's checks at step level; merge.
5. Confirm the post-merge `push` run green at step level.
6. Add `WASM cross-target compile` to the required contexts. Record snapshot
   (**after**).
7. Prove enforcement with the docs-only verification PR: the new context must
   appear as required in its check list.

The window in which WASM is not *required* spans steps 3–6 — minutes, under our
own control, and the job keeps running and stays visible throughout. Critically,
step 2 makes the new context **report at least once before we require it**, so
we never require a string we have not observed GitHub emit.

**Rejected — merge the rename via admin bypass.** Fewer ruleset mutations, but
the one PR that changes CI would merge without its required check satisfied, and
between that merge and the ruleset edit *any other* PR wedges on the now-orphaned
context. The repository's own verification record already flags bypass as a
caveat; using it to avoid a five-minute sequencing problem inverts the culture.

**Rejected — a temporary bridge job named with the old context.** Never wedges
and never weakens, but the bridge is a green no-op job: literally the Slice 16
dead-step trap, in the same workflow Slice 46 just finished clearing of exactly
that shape. Also three PRs instead of one.

### Decision 2 — Open the PR *before* dropping the context, to prove the wedge

Dropping the context first would make the whole operation smooth and prove
nothing. Opening first costs one deliberately-blocked PR and converts the
review's *assertion* that this rename is order-sensitive into a recorded
observation: a check list showing `Expected — Waiting for status to be reported`
against a context no job emits. That artifact is the strongest possible argument
for the standing pin added in Decision 3, and it belongs in the verification
record.

### Decision 3 — Pin all three job names, not just WASM's

Add one test method holding an explicit job-key → expected-`name:` table for all
three jobs, asserting equality, with a comment naming ruleset `Main`
(id `17656807`) and stating the invariant: *this string is the required-check
context; changing it requires a ruleset update in the same change.*

Scope is all three because the hazard is not WASM-specific — `Host tests and
benchmark gate` and `iOS cross-target compile` are required contexts under
exactly the same coupling, and after this slice nobody will think about job
renames again for many slices. The seam already exists:
`jobLevelValue(of:jobKey:)`, built in Slice 46 to read `container:`, reads
`name:` unchanged. This is the same cross-pinning move as
`testWindowConstantMatchesDeriveScript` and
`testWasmContainerVersionMatchesPinnedSdkURL`.

The pin cannot reach the ruleset (no network in `swift test`), so it does not
verify the two strings *match*; it makes the workflow half **loud**. A rename now
fails the build with a message naming the ruleset, which is the point at which a
human can act.

One method with a table, not three methods — matching the `pinnedGateSteps`
style already in this file, and avoiding the literal duplication Slice 45's
review flagged as its P3 #7.

### Decision 4 — `wasm_kind_blocking`'s unknown-kind default hard-errors

Slice 46's review (P3 #3) flagged the `*)` branch returning `false`: fail-open
inside a fail-closed design. Unreachable today, but a third kind added later
would silently default to observational.

Return an error rather than `true`. An unknown kind reaching this function is a
typo or a half-finished edit, not a new platform — `true` would mask it as a
working blocking kind, while a hard error names it. This matches the fail-closed
posture without inventing behavior for input that should not exist.

### Decision 5 — The drift path short-circuits with its *own* reason

`prepare_wasm_sdk` runs per kind. Slice 46's `4dd7111` fixed the
install-failure path to record `WASM_BUNDLE_INSTALL_FAILED` once and
short-circuit the second kind. The sibling `sdk_unresolved_after_install` path
(install succeeded, resolve failed — the version-drift scenario) was not folded
in, so the second kind re-runs a full retry ladder against an
already-installed SDK and reports `sdk_install_failed` — a *different* reason
than the first kind's, reading as two unrelated faults.

Record the bundle outcome once, and have the second kind short-circuit with the
**same** reason the first kind produced. Always fail-closed either way; this is
diagnostics plus ~6s of wasted backoff.

### Decision 6 — Extract the short-circuit decision into a pure helper

The short-circuit lives inside the impure `prepare_wasm_sdk`, so the
repository's "pure helpers + `--self-test`" pattern does not cover it; Slice 46
verified it by live local run with a bogus URL instead. Extract the decision
(given recorded bundle state and kind → proceed / short-circuit with reason) into
a pure helper and add `--self-test` cases. Closes P3 #4 and makes Decision 5
testable without a network.

### Decision 7 — De-rot both frozen `580 µs` sites by removing the number

`Sources/ViewportBenchmarks/BenchmarkModels.swift:145` and `AGENTS.md:365` quote
a measured value frozen three slices ago. Do **not** refresh the number —
replace the quote with a pointer to `GateFloorTests` and the corpus, which is
where the live value is computed. A comment quoting a benchmark number is
falsified by the next re-derivation; this repository has now carried that
falsehood for three consecutive slices, which is the argument for removing the
quote rather than updating it.

This is the only `Sources/` edit in the slice and it is comment-only: gate
checksums stay byte-identical.

## Change set

### 1. `.github/workflows/swift-ci.yml`

Three lines: job key, `name:`, and the docs-only echo's `job=` value.

### 2. `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`

- `wasmJobKey` constant → `wasm-cross-target-compile`.
- New `testJobNamesMatchRequiredCheckContexts` — table of three job keys →
  expected `name:` strings, exact equality, comment naming ruleset `Main`
  (`17656807`) and the invariant.

Suite: 314 → 315.

### 3. `.github/scripts/cross-target-compile.sh`

- `wasm_kind_blocking` `*)` → hard error (Decision 4).
- Bundle-outcome recording extended to the `sdk_unresolved_after_install` path;
  second kind short-circuits with the same reason (Decision 5).
- New pure helper for the short-circuit decision (Decision 6).
- `run_self_test` extended to cover all three.

### 4. `AGENTS.md`

- CI job description: new name; **delete** the "Known wart" block.
- Required-check policy paragraph: new context string; fresh `Last verified`
  line pointing at this slice's verification record.
- Commands block: caveat that bare `--targets wasm` exits 1 without the env pin
  and a version-matching installed SDK (P3 #6).
- Line 365: remove the frozen `580 µs` quote (Decision 7).

### 5. `Sources/ViewportBenchmarks/BenchmarkModels.swift`

Line 145 comment only (Decision 7).

### 6. `docs/superpowers/verification/2026-07-20-wasm-required-check-rename.md`

Modeled on `2026-06-16-swift-ci-required-checks.md`: three `gh api` ruleset
snapshots (before / intermediate / after) with a full diff asserting that
**exactly one context string changed** and that bypass actors and strict policy
are untouched; the wedged-PR artifact from Decision 2; both hosted runs at step
level; the pin's break→red→revert→green cycle.

### 7. Memory

Update the Slice 46 entry (deferred wart discharged) and add a Slice 47 entry.

## Acceptance criteria

- **AC1** — All seven stale-name sites updated. Verified with a search that can
  actually see them — `--hidden` (else `.github/` is skipped) and `-U` (else the
  wrapped `AGENTS.md:273-274` occurrence is missed):

  ```bash
  rg -n --hidden -U 'wasm-cross-target-observation|WASM cross-target\s+observation' \
    --glob '!docs/**' --glob '!.git/**' .
  ```

  Expected: empty, `exit=1`. Historical slice docs under `docs/` keep the old
  name deliberately — they are records of when it was true.
- **AC2** — `testJobNamesMatchRequiredCheckContexts` exists, covers all three
  jobs, and is **live**: editing any one `name:` reddens exactly that test, with
  a message naming the ruleset; revert restores green; tree byte-clean.
- **AC3** — The wedge is recorded: the rename PR's check list, before the ruleset
  edit, shows the old context unreported.
- **AC4** — Three `gh api` ruleset snapshots recorded. The before→after diff
  changes exactly one context string; bypass actors and
  `strict_required_status_checks_policy` byte-identical.
- **AC5** — The rename PR merges with all three required checks green, read at
  **step** level.
- **AC6** — Post-merge `push` run green at step level: three jobs, four WASM
  pairs `blocking=true`, 46 `gate=pass`, 315/0.
- **AC7** — The new context is proven *enforced*: the docs-only verification PR's
  check list shows `WASM cross-target compile` as required and reported.
- **AC8** — `--self-test` still `self_test=pass` with the new cases; the P3 #2
  short-circuit is now covered by it rather than by live run alone.
- **AC9** — Confinement: `git diff` over `Sources/TextEngineCore`,
  `Sources/TextEngineReferenceProviders`, every budget literal, the corpus TSV,
  `derive-gate-budgets.sh`, and `harvest-gate-corpus.sh` is **empty**. Gate
  checksums byte-identical (45).
- **AC10** — Foundation-free scan over `Sources/TextEngineCore` empty, `exit=1`.

## Non-goals / out of scope

- Any engine, provider, budget, corpus, or calibration-script change.
- Harvester provenance hardening (Slice 46 P2 #3) — the standing next
  recommendation, deliberately its own slice.
- Bulk-edit absolute budget (P2 #1) — needs a product decision.
- Renaming the *step* `Compile cross-target packages for WASM` — already correct.
- Any change to bypass-actor configuration.

## Verification plan

Local, on the branch: `swift test` (315/0), `swift build -c release`,
`./.github/scripts/cross-target-compile.sh --self-test`, `bash -n` on the
script, the Foundation-free scan, the confinement diff, and the AC2
break→red→revert→green cycle.

Hosted: the rename PR run and the post-merge `push` run, both read at step
level per this repository's standing rule that a green job conclusion proves
nothing.

Governance: three `gh api` snapshots, each recorded verbatim. Both ruleset
mutations are outward-facing and irreversible-in-effect for anyone with an open
PR, so each is presented as an exact command and executed only on explicit
confirmation.

## Risks & trade-offs

- **The unrequired window (steps 3–6).** WASM is not a required check for the
  duration. It still runs and stays visible, the window is minutes, and it is
  the cost of the only sequence that needs neither bypass nor a fake green job.
- **A deliberately wedged PR.** Step 2 blocks our own PR on purpose. Bounded,
  reversible by step 3, and it produces AC3's evidence.
- **`gh api` replaces ruleset structure wholesale.** A careless PATCH could drop
  bypass actors or strict policy. Mitigated by AC4's full before/after diff,
  which asserts what did *not* change as explicitly as what did.
- **The name pin does not verify the ruleset.** It makes the workflow half loud,
  not the pair consistent. Stated in the test comment so it is not mistaken for
  a stronger guarantee.

## Next step

Slice 48 = harvester provenance hardening (Slice 46 P2 #3) — the highest-
consequence open item, and the only unverified link in the calibration chain now
sitting under twelve blocking budgets.
