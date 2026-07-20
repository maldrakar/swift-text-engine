# Slice 47 — WASM required-check rename — verification record

Evidence, not assertion. Every command below was run; outputs are transcribed verbatim
or summarised with the actual numbers observed. Where a plan command could not work as
written, the deviation is recorded rather than silently "passed".

- **Spec:** `docs/superpowers/specs/2026-07-20-wasm-required-check-rename-design.md`
- **Plan:** `docs/superpowers/plans/2026-07-20-wasm-required-check-rename.md`
- **Branch:** `slice-47-wasm-required-check-rename`
- **Merge base:** `be763dc`
- **Implementation HEAD:** `38ac4e4`
- **PR:** [#108](https://github.com/maldrakar/swift-text-engine/pull/108)
- **Ruleset:** `Main`, id `17656807`, repo `maldrakar/swift-text-engine`

## Commit trail

| Commit | Subject |
|---|---|
| `87265d5` | test: pin job names to their required-check contexts, and rename WASM's |
| `c8c66b1` | ci: rename the WASM job key and its docs-only echo |
| `9925b9a` | docs: retire the WASM 'observation' name from AGENTS.md |
| `77ba95c` | fix: fail closed on an unknown WASM kind |
| `dbaf2a8` | fix: short-circuit the SDK drift path with its own reason |
| `88e7694` | docs: stop quoting a frozen 580us, and caveat the bare wasm command |
| `38ac4e4` | docs: correct comment mechanics and drift-path reason literal in cross-target-compile.sh |

## Task 1 — pre-change baseline (measured, not recalled)

The remembered "45 checksums" predates Slice 45's twelfth gate, so the baseline was
measured before the first edit:

```
gh pr list --state open        -> EMPTY  (Decision 1's zero-blast-radius precondition holds)
checksum_lines                 -> 46
gate=pass / gate=fail          -> 46 / 0
swift test                     -> Executed 314 tests, with 0 failures
```

**46**, not 45, is the number every later comparison uses.

## AC9 — confinement and checksum byte-identity

Confinement diff (`git diff be763dc..HEAD --name-only` over `Sources/TextEngineCore`,
`Sources/TextEngineReferenceProviders`, the corpus TSV, `derive-gate-budgets.sh`,
`harvest-gate-corpus.sh`): **empty**.

Checksums after all edits: **46 triples, byte-identical to baseline**; 46 `gate=pass`, 0 `gate=fail`.

### Deviation from the plan's AC9 command — recorded, not hidden

The plan's Task 8 Step 3 extracts with:

```
rg -o 'scenario=\S+ .*checksum=\S+'
```

That regex captures the **entire** benchmark line, including `p95_ns=` and `p99_ns=` —
timings that vary on every run. Its `diff` therefore can never be empty, and the check
as written is unpassable; it would have to be waved through to "pass".

The invariant that actually matters is the checksum, so the comparison used here drops
the timings and compares `(mode, scenario, checksum)` triples:

```
awk '/^mode=/{m=$1} /scenario=/{...print m, s, c}' raw.txt | sort
diff baseline-triples.txt after-triples.txt   -> empty
baseline_triples=46   after_triples=46
```

The independent whole-branch reviewer arrived at the same method (rebuilding `be763dc`
in a scratch worktree and diffing all 46 mode/scenario/checksum triples), which
corroborates both the method and the result.

## AC2 — the new pin is live and self-servicing

`testJobNamesMatchRequiredCheckContexts` was broken deliberately by reverting only the
WASM job's `name:` in `.github/workflows/swift-ci.yml`:

```
/Users/.../WorkflowShapeTests.swift:499: error: -[ViewportBenchmarksTests.WorkflowShapeTests
testJobNamesMatchRequiredCheckContexts] : XCTAssertEqual failed:
("WASM cross-target observation") is not equal to ("WASM cross-target compile") -
.github/workflows/swift-ci.yml: job wasm-cross-target-compile is named "WASM cross-target
observation", but ruleset Main (id 17656807) on maldrakar/swift-text-engine requires the
status-check context "WASM cross-target compile". GitHub matches required checks by this
exact string, and the ruleset lives outside this repository -- so renaming a job without
updating the ruleset wedges every open PR on a context nothing reports. Change BOTH, in
the same slice: this table, and the ruleset via
  gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --method PUT --input <edited.json>
...
Executed 10 tests, with 1 failure (0 unexpected)
```

- **Exactly one** failing method — the host and iOS rows stayed green, so the table's other
  two contexts genuinely match the workflow.
- Message contains `17656807` and the full runnable `gh api ... --method PUT` command, so a
  reader who trips it can service the half `swift test` cannot reach. AC2 requires the
  message be self-servicing, not merely to mention the ruleset.

Reverted (`git checkout .github/workflows/swift-ci.yml`) → `Executed 10 tests, with 0
failures`; `git status --short` empty (tree byte-clean).

**What this pin cannot do**, stated plainly because overclaiming here would be the defect:
`swift test` has no network. Renaming the job *and* the table together, while forgetting the
ruleset, still passes. The pin makes the repository half loud; it does not prove the pair
agrees.

## Local verification at HEAD `38ac4e4`

```
swift test                                  -> Executed 315 tests, with 0 failures
swift build -c release                      -> Build complete!
cross-target-compile.sh --self-test         -> self_test=pass
bash -n cross-target-compile.sh             -> syntax ok
rg -n "Foundation" Sources/TextEngineCore   -> empty, foundation_scan_exit=1
```

Suite went 314 → 315: one new test (`testJobNamesMatchRequiredCheckContexts`).

## AC8 — `--self-test` covers the new shell cases

New assertions, all reachable without network:

- `unknown_kind_blocks` — an unknown kind must yield `true` (fail closed).
- `precheck_no_url`, `precheck_proceeds`, `precheck_short_circuits_install_failure`,
  `precheck_short_circuits_drift_with_same_reason`, `precheck_no_url_precedence`.

The drift short-circuit was previously reachable *only* by a live network run; making
`wasm_install_precheck` pure is what brings it under `--self-test`.

### Live fail-closed proof (Task 6 Step 9)

```
CROSS_TARGET_WASM_SDK_URL=https://example.invalid/nope.tar.gz \
CROSS_TARGET_WASM_SDK_CHECKSUM=deadbeef \
CROSS_TARGET_SDK_INSTALL_ATTEMPTS=2 CROSS_TARGET_SDK_INSTALL_BACKOFF=1 \
  ./.github/scripts/cross-target-compile.sh --targets wasm
```

- exactly **2** `warn=sdk_install_attempt_failed` lines (**one** ladder, not two)
- `cross_target_sdk_install_skipped target=wasm_embedded reason=bundle_already_failed prior_reason=sdk_install_failed`
- 4 × `blocking=true` failures, `SCRIPT_EXIT=1`

Exit status was captured directly, **not** after a `| tail` pipe — a pipe reports the last
element's status and would have masked the script's own exit code.

The whole-branch reviewer additionally exercised the **SDK-drift** path live by stubbing
`swift` on `PATH` (version 6.2.1, `sdk install` succeeds, `sdk list` empty) — a path Slice 46
never exercised. Result: one install, both kinds reporting the **same**
`sdk_unresolved_after_install`, `blocking_failures=4 exit=1`. That is the P3 #2 fix proven
live rather than only at unit level.

## AC1 — stale-name sweep, with one sanctioned exception

```
rg -n --hidden -U 'wasm-cross-target-observation|WASM cross-target\s+observation' \
  --glob '!docs/**' --glob '!.git/**' .
```

Result: **one** hit — `AGENTS.md:316`.

**AC1 as written expected zero.** It cannot be met as written, because the plan's own Task 4
Step 4 mandates inserting prose that quotes the old name to narrate the rename:

> The WASM context was renamed from `WASM cross-target observation` in Slice 47;

The implementing agent changed neither the prose nor the grep and escalated the
contradiction. **Human ruling: accept the single historical hit.** AC1 therefore reads:
*one sanctioned historical mention, no stale uses.* The mention is past-tense narration,
not a live reference; historical slice docs under `docs/` keep the old name for the same
reason and are excluded deliberately.

`.github/` and `Tests/` are clean. `grep -n "needs:"` over the workflow returns nothing, so
no job depended on the renamed job key.

## AC4 — ruleset "before" snapshot

```
gh api repos/maldrakar/swift-text-engine/rulesets/17656807
```

```
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation          <- old name still required
strict_required_status_checks_policy = true
bypass_actors = [{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]
```

`strict_required_status_checks_policy` and `bypass_actors` are recorded here so the
after-snapshot can be asserted byte-identical on both.

## AC3 — the deliberate wedge (observed, not asserted)

PR #108 opened at head `38ac4e4`, with `gh pr list --state open` re-confirmed empty
immediately beforehand.

```
iOS cross-target compile        SUCCESS   pass
WASM cross-target compile       SUCCESS   pass
Host tests and benchmark gate   SUCCESS   pass

mergeStateStatus=BLOCKED  mergeable=MERGEABLE
```

All three jobs **reported and passed**, including the newly-named
`WASM cross-target compile` — and the PR is still **BLOCKED**, because ruleset `Main`
requires `WASM cross-target observation`, which no run will ever report.

This is the order-sensitivity Slice 46's review flagged, deliberately observed rather than
argued. It is also what makes the sequence safe: GitHub has now *seen* the new context
reported on this PR before the ruleset is changed to require it.

### Step-level evidence — PR run `29750898846` (head `38ac4e4`)

Read at step level, not job conclusion (a green job can hide a dead `continue-on-error`
step — the Slice 16 trap).

```
status=completed conclusion=success head_sha=38ac4e4
gate=pass  46        gate=fail  0
Executed 315 tests, with 0 failures
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

Four WASM `blocking=true` passes (two kinds × two packages):

```
target=wasm          package=core       result=pass reason=none blocking=true
target=wasm          package=providers  result=pass reason=none blocking=true
target=wasm_embedded package=core       result=pass reason=none blocking=true
target=wasm_embedded package=providers  result=pass reason=none blocking=true
```

plus four iOS `blocking=true` passes. Embedded WASM passed on its own merit — no engine or
provider source change was made this slice.

## AC coverage

| AC | Status | Where |
|---|---|---|
| AC1 seven sites, `--hidden -U` | ✅ *with one sanctioned historical mention* | above |
| AC2 pin live, self-servicing message | ✅ | above |
| AC3 wedge recorded | ✅ | above |
| AC4 three snapshots, one-string diff | before-snapshot ✅; intermediate/after `<PENDING Task 9>` | above |
| AC5 merge, read at step level | `<PENDING Task 9>` | — |
| AC6 post-merge push run | `<PENDING Task 9>` | — |
| AC7 enforcement, PR opened after re-add | `<PENDING Task 10>` | — |
| AC8 `--self-test` covers new cases | ✅ | above |
| AC9 confinement + checksum baseline | ✅ *via corrected extractor* | above |
| AC10 Foundation scan | ✅ | above |
| Precondition: no open PRs | ✅ measured twice | above |

Pending items are marked `<PENDING>` rather than pre-filled. They are discharged in the
follow-up commit after the ruleset sequence completes.
