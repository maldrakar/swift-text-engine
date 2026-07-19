# Slice 45 verification — `--realistic-provider` promoted to the twelfth blocking CI gate

Branch `slice-45-realistic-provider-ci-gate-promotion`, merge-base with `main`
`88a4bcd`. Task commits on top: `9630bfb` (workflow: wire `--realistic-provider
--gate` in as a blocking step, generalize `WorkflowShapeTests` to a two-entry
`pinnedGateSteps` table `{point-geometry, realistic}`, delete the orphaned
`.github/scripts/realistic-relative-observation.sh`), `c229bb7` (narrative-rot
comment fixes: the `realisticProviderScenarios()` source comment + four
`AGENTS.md` passages, rewritten to describe the standard shape-1 gate route
instead of the retired PR-only observation route). This record's own commit is
Task 3.

**Verification is evidence, not assertion.** Everything below is raw command
output captured directly by this task, run against the current tree
(`c229bb7`).

> **Hosted proof filled post-merge.** The `## Hosted CI — Pending` section below
> is completed by a docs-only follow-up once this branch merges, citing the
> PR-head run and the post-merge `push` run.

---

## Local checks

| Command | Result |
| --- | --- |
| `swift build -c release` | `Build complete! (0.07s)` (cached, no source changes since last release build on this tree) |
| `swift test 2>&1 \| tail -5` | `Executed 311 tests, with 0 failures (0 unexpected) in 4.177 (4.199) seconds` |
| `swift run -c release ViewportBenchmarks -- --realistic-provider --gate` | single scenario `100k_lines_10mb_text`, `gate=pass`, `budget_absolute_p99_ns=1666666` |
| `swift run -c release ViewportBenchmarks -- --gate 2>&1 \| grep -c "gate=pass"` | `3` (all three synthetic pipeline scenarios) |
| `rg -n Foundation Sources/TextEngineCore ; echo "exit=$?"` | empty output, `exit=1` |
| `swift test --filter WorkflowShapeTests` (break state) | RED — `testNoPinnedGateIsContinueOnError` fails, naming the realistic step |
| `swift test --filter WorkflowShapeTests` (revert state) | GREEN — `Executed 6 tests, with 0 failures (0 unexpected)` |
| `git status --short` (post-revert) | empty — tree byte-clean |
| `git diff --name-only main...HEAD` | 7 files, all within the expected confined set |

### Full command transcripts

```
$ swift build -c release
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build complete! (0.07s)
```

```
$ swift test 2>&1 | tail -5
	 Executed 311 tests, with 0 failures (0 unexpected) in 4.177 (4.199) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

```
$ swift run -c release ViewportBenchmarks -- --realistic-provider --gate
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5382 p99_ns=5611 failures=0 budget_p95_ns=97000 budget_p99_ns=200000 headroom_p95=18.0x headroom_p99=35.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=297.0x gate=pass checksum=756321289736960
```

`gate=pass` and `budget_absolute_p99_ns=1666666`, exactly as the brief
expects — this is the fixed 60-FPS/10% ceiling (`1_000_000_000 / 60 / 10`)
described in `AGENTS.md`'s absolute-ceiling paragraph, unrelated to the
regression-band budget columns.

```
$ swift run -c release ViewportBenchmarks -- --gate 2>&1 | grep -c "gate=pass"
3
```

Full output behind that count (three synthetic pipeline scenarios, all pass):

```
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1267 p99_ns=1323 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=16.6x headroom_p99=31.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1259.8x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5119 p99_ns=5308 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=16.4x headroom_p99=32.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=314.0x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17069 p99_ns=17577 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=16.4x headroom_p99=31.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=94.8x gate=pass checksum=18852477646272000
```

```
$ rg -n Foundation Sources/TextEngineCore ; echo "exit=$?"
exit=1
```

Empty match set, `exit=1` — the Foundation-free invariant holds.

## Guard-is-live (break → red → revert → green)

The point of this proof: `WorkflowShapeTests.testNoPinnedGateIsContinueOnError`
must be a genuine failing-first anchor for the new realistic gate step, not a
tautology. Disarm the step the same way a future regression could (adding
`continue-on-error: true`), confirm the test catches it by name, then confirm a
clean revert restores green with zero residue.

```
$ cp .github/workflows/swift-ci.yml /tmp/swift-ci.yml.bak
$ perl -0pi -e 's/(      - name: Run realistic provider benchmark gate\n        if: steps.change-scope.outputs.docs_only_pr != .true.\n)/$1        continue-on-error: true\n/' .github/workflows/swift-ci.yml
$ diff /tmp/swift-ci.yml.bak .github/workflows/swift-ci.yml
135a136
>         continue-on-error: true
```

Exactly one line injected, immediately after the realistic gate step's `if:`
guard — the shape `WorkflowShapeTests` is meant to catch.

### RED

```
$ swift test --filter WorkflowShapeTests 2>&1 | tail -20
Test Suite 'Selected tests' started at 2026-07-19 18:09:57.625.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-07-19 18:09:57.626.
Test Suite 'WorkflowShapeTests' started at 2026-07-19 18:09:57.626.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateCarriesTheDocsOnlyGuard]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateCarriesTheDocsOnlyGuard]' passed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateIsNamedForItsSiblings]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateIsNamedForItsSiblings]' passed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateRunsExactlyTheExpectedCommand]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateRunsExactlyTheExpectedCommand]' passed (0.000 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateSitsBetweenItsAnchors]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateSitsBetweenItsAnchors]' passed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testExactlyOneStepRunsEachPinnedGate]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testExactlyOneStepRunsEachPinnedGate]' passed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testNoPinnedGateIsContinueOnError]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:242: error: -[ViewportBenchmarksTests.WorkflowShapeTests testNoPinnedGateIsContinueOnError] : XCTAssertNil failed: "true" - Run realistic provider benchmark gate: carries continue-on-error: true — a continue-on-error step cannot be a gate; it swallows budget misses, correctness failures and crashes alike
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testNoPinnedGateIsContinueOnError]' failed (0.079 seconds).
Test Suite 'WorkflowShapeTests' failed at 2026-07-19 18:09:57.708.
	 Executed 6 tests, with 1 failure (0 unexpected) in 0.082 (0.082) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' failed at 2026-07-19 18:09:57.708.
	 Executed 6 tests, with 1 failure (0 unexpected) in 0.082 (0.082) seconds
Test Suite 'Selected tests' failed at 2026-07-19 18:09:57.708.
	 Executed 6 tests, with 1 failure (0 unexpected) in 0.082 (0.083) seconds
```

5 of 6 test methods pass (`testEachPinnedGateCarriesTheDocsOnlyGuard`,
`testEachPinnedGateIsNamedForItsSiblings`,
`testEachPinnedGateRunsExactlyTheExpectedCommand`,
`testEachPinnedGateSitsBetweenItsAnchors`, `testExactlyOneStepRunsEachPinnedGate`
— none of them concerned with `continue-on-error`, so the injected line does not
touch what they check), and exactly one fails —
`testNoPinnedGateIsContinueOnError` — naming the realistic step by its exact
step name (`Run realistic provider benchmark gate`) in the assertion message.
This is the anchor the brief asked to prove live.

### Revert

```
$ cp /tmp/swift-ci.yml.bak .github/workflows/swift-ci.yml
$ diff /tmp/swift-ci.yml.bak .github/workflows/swift-ci.yml && echo "REVERT-DIFF-EMPTY"
REVERT-DIFF-EMPTY
```

### GREEN

```
$ swift test --filter WorkflowShapeTests 2>&1 | tail -10
Test Suite 'WorkflowShapeTests' passed at 2026-07-19 18:10:08.203.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.003 (0.004) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-07-19 18:10:08.203.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.003 (0.004) seconds
Test Suite 'Selected tests' passed at 2026-07-19 18:10:08.203.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.003 (0.004) seconds
```

### Tree byte-clean after revert

```
$ git status --short
$
```

Empty output — no stray file, no residual diff, from the `cp`/`perl`/`cp`
round trip.

## Diff confinement

```
$ git diff --name-only main...HEAD
.github/scripts/realistic-relative-observation.sh
.github/workflows/swift-ci.yml
AGENTS.md
Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
docs/superpowers/plans/2026-07-19-realistic-provider-ci-gate-promotion.md
docs/superpowers/specs/2026-07-19-realistic-provider-ci-gate-promotion-design.md
```

Run **before** this task's own commit lands, so the not-yet-created
verification doc you are reading is correctly absent from this listing; once
Step 5 commits it, the diff gains exactly one more path —
`docs/superpowers/verification/2026-07-19-realistic-provider-ci-gate-promotion.md`
— completing the expected set of eight paths: `AGENTS.md`,
`Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`,
`Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`,
`.github/workflows/swift-ci.yml`, the deleted
`.github/scripts/realistic-relative-observation.sh`, and the three slice docs
(spec, plan, this verification record).

No `Sources/TextEngineCore`, no `Sources/TextEngineReferenceProviders`, no
provider file, no budget literal, no corpus TSV, no
`derive-gate-budgets.sh` — this slice is a pure CI-wiring + narrative-comment
change, zero engine/budget behavior touched, consistent with `9630bfb`'s commit
message ("Zero engine behavior change: the mode already honours --gate") and
`c229bb7`'s ("Comment/doc only — no code, budget, or behavior change").

## Hosted CI — Pending

AC7 not yet discharged — filled in by a docs-only follow-up once this branch
merges. Required (per `AGENTS.md`'s required-check policy and the standing
"read step logs, not job conclusion" rule — a `continue-on-error` step can
conclude its job green while the step itself failed, the Slice 16 dead-step
trap):

- All three required job contexts green on both runs: `Host tests and
  benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`.
- All twelve blocking gate steps present (not skipped) and passing at **step
  level** on both the PR-head run and the post-merge `push` run: synthetic,
  variable-height, variable-height-mutation, structural-mutation,
  bulk-structural-mutation, line-query, line-geometry-query, column-query,
  column-geometry-query, point-query, point-geometry-query, and — new this
  slice — **realistic-provider**.
- The realistic-provider step specifically reports `gate=pass` (not merely
  "step succeeded") at step level.
- `swift test` green (host tests step) on both runs.

PR-head run: `<PENDING — fill after PR opens and CI completes>`
Post-merge `push` run: `<PENDING — fill after merge>`

Both to be confirmed via `gh run view <id> --log` (or equivalent), reading step
logs directly rather than trusting job conclusion, per this project's standing
verification discipline.
