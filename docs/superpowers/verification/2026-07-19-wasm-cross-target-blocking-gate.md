# Slice 46 verification — WASM cross-target compile promoted to a blocking CI gate

Branch `slice-46-wasm-cross-target-blocking-gate`, HEAD `3457a8e`, PR #105
(open at the time of this record). Task commits on top of `main` (merge-base
`ffc932b`):

- `398cb67` — feat: checksum-verified WASM SDK install with bounded retry
- `e9c2b97` — feat: make WASM compile blocking, per-kind, fail-closed
- `285f76d` — docs: correct the WASM compile helper's blocking contract comment
- `546b2fb` — ci: provision the pinned 6.2.1 WASM SDK in the WASM job
- `3457a8e` — test: pin the WASM compile step's blocking shape

This record's own commit (Task 8) adds `AGENTS.md`'s WASM-related prose
updates plus this file.

**Verification is evidence, not assertion.** Everything under "Local checks"
below is raw command output captured directly by this task, run against the
current tree. Everything under "Hosted evidence" is transcribed verbatim from
the run IDs and log lines supplied for this task — no value there was invented,
rounded, or embellished.

---

## Pinned WASM SDK bundle

- **URL**: `https://download.swift.org/swift-6.2.1-release/wasm-sdk/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE_wasm.artifactbundle.tar.gz`
- **sha256**: `482b9f95462b87bedfafca94a092cf9ec4496671ca13b43745097122d20f18af`
- **size**: `106085411` bytes (matches the download's `Content-Length`)
- **Recompute command**: `curl -sL <url> | shasum -a 256`
- **One bundle, two SDK ids**: installing it once provisions both
  `swift-6.2.1-RELEASE_wasm` and `swift-6.2.1-RELEASE_wasm-embedded` — the
  plan's prose had guessed `swift-6.2.1_wasm` *without* the `-RELEASE`
  component; the real ids carry it, and the workflow/script use the real ids.
- **Provenance**: the `.sha256` sidecar next to the bundle 404s, so there is no
  second swift.org-hosted file to diff the checksum against. The checksum's
  provenance is therefore the TLS download from the official `download.swift.org`
  host, recomputed locally with `shasum -a 256` — exactly the same trust
  `swift sdk install --checksum <sha>` itself enforces at install time (it
  downloads over TLS and rejects a mismatch). Liveness run `29701333581` below
  independently reconfirms this sha256 is correct: Swift computed the *real*
  checksum of the (unmodified) bundle bytes and printed it verbatim while
  rejecting a deliberately corrupted pin.

## Local checks

| Command | Result |
| --- | --- |
| `./.github/scripts/cross-target-compile.sh --self-test` | `self_test=pass`, exit 0 |
| `bash -n .github/scripts/cross-target-compile.sh` | exit 0, no output (syntax OK) |
| `swift build -c release` | `Build complete! (1.57s)` |
| `swift test` | `Executed 312 tests, with 0 failures (0 unexpected)` |
| `rg -n "Foundation" Sources/TextEngineCore ; echo exit=$?` | empty output, `exit=1` |
| `git diff --name-only main...HEAD` (pre-Task-8-commit) | 5 files, all within the expected confined set |

### Full command transcripts

```
$ ./.github/scripts/cross-target-compile.sh --self-test
self_test=pass
```

```
$ bash -n .github/scripts/cross-target-compile.sh
$ echo "EXIT=$?"
EXIT=0
```

```
$ swift build -c release
[0/1] Planning build
Building for production...
[0/3] Write sources
[1/3] Write swift-version-58A378E29CF047B.txt
[3/4] Compiling ViewportBenchmarks BenchmarkModels.swift
Build complete! (1.57s)
```

```
$ swift test 2>&1 | tail -6
Test Suite 'WorkflowShapeTests' passed at 2026-07-19 23:11:48.118.
	 Executed 7 tests, with 0 failures (0 unexpected) in 0.004 (0.005) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-07-19 23:11:48.119.
	 Executed 312 tests, with 0 failures (0 unexpected) in 4.244 (4.266) seconds
Test Suite 'All tests' passed at 2026-07-19 23:11:48.119.
	 Executed 312 tests, with 0 failures (0 unexpected) in 4.244 (4.267) seconds
```

312/0, including all 7 `WorkflowShapeTests` methods — the pre-existing 6
host-job invariants plus Task 4's new `testWasmCompileStepIsBlockingShaped`
(up from 311/6 before Slice 46's Task 4 commit).

```
$ rg -n "Foundation" Sources/TextEngineCore ; echo exit=$?
exit=1
```

Empty match set, `exit=1` — the Foundation-free invariant holds; the WASM
provisioning/compile change touched only `.github/scripts/**`,
`.github/workflows/**`, and one test file, never `Sources/TextEngineCore`.

```
$ git diff --name-only main...HEAD
.github/scripts/cross-target-compile.sh
.github/workflows/swift-ci.yml
Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
docs/superpowers/plans/2026-07-19-wasm-cross-target-blocking-gate.md
docs/superpowers/specs/2026-07-19-wasm-cross-target-blocking-gate-design.md
```

Run **before** this task's own commit lands (which is why `AGENTS.md` and this
verification file are correctly absent above). After that commit the diff
gains exactly two more paths — `AGENTS.md` and
`docs/superpowers/verification/2026-07-19-wasm-cross-target-blocking-gate.md`
— for the expected final set of 7: the compile script, the workflow, the
workflow-shape test, the three slice docs (spec, plan, this verification
record), and `AGENTS.md`. No `Sources/TextEngineCore` or
`Sources/TextEngineReferenceProviders` change anywhere in the branch.

### Workflow-shape pin liveness cycle (break -> red -> revert -> green)

This same break -> red -> revert -> green cycle was first performed and
recorded during Task 4. Because that record lived under the gitignored
`.superpowers/sdd/` scratch path, it would never exist in a clone of this
repo — so this task re-ran the cycle from scratch, against the current tree,
and captures the real output inline below instead of citing that path.

**Step 1 — confirm green on the unmodified workflow:**

```
$ swift test --filter WorkflowShapeTests/testWasmCompileStepIsBlockingShaped
Building for debugging...
[0/4] Write swift-version-58A378E29CF047B.txt
Build complete! (0.10s)
Test Suite 'Selected tests' started at 2026-07-19 23:20:14.003.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-07-19 23:20:14.004.
Test Suite 'WorkflowShapeTests' started at 2026-07-19 23:20:14.004.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testWasmCompileStepIsBlockingShaped]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testWasmCompileStepIsBlockingShaped]' passed (0.001 seconds).
Test Suite 'WorkflowShapeTests' passed at 2026-07-19 23:20:14.005.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
```

**Step 2 — inject `continue-on-error: true` under the WASM compile step's
`if:` line** (`.github/workflows/swift-ci.yml`):

```diff
       - name: Compile cross-target packages for WASM
         if: steps.change-scope.outputs.docs_only_pr != 'true'
+        continue-on-error: true
         env:
           CROSS_TARGET_WASM_SDK_URL: https://download.swift.org/swift-6.2.1-release/wasm-sdk/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE_wasm.artifactbundle.tar.gz
           CROSS_TARGET_WASM_SDK_CHECKSUM: 482b9f95462b87bedfafca94a092cf9ec4496671ca13b43745097122d20f18af
```

**Step 3 — re-run the same filtered test; it must fail by name, with the
exact `continueOnError` assertion message:**

```
$ swift test --filter WorkflowShapeTests/testWasmCompileStepIsBlockingShaped
Building for debugging...
[0/4] Write swift-version-58A378E29CF047B.txt
Build complete! (0.07s)
Test Suite 'Selected tests' started at 2026-07-19 23:20:30.970.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-07-19 23:20:30.971.
Test Suite 'WorkflowShapeTests' started at 2026-07-19 23:20:30.971.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testWasmCompileStepIsBlockingShaped]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:326: error: -[ViewportBenchmarksTests.WorkflowShapeTests testWasmCompileStepIsBlockingShaped] : XCTAssertNil failed: "true" - .github/workflows/swift-ci.yml: the WASM compile step must not be continue-on-error — it would swallow the fail-closed WASM gate (the Slice 16 trap)
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testWasmCompileStepIsBlockingShaped]' failed (0.007 seconds).
Test Suite 'WorkflowShapeTests' failed at 2026-07-19 23:20:30.978.
	 Executed 1 test, with 1 failure (0 unexpected) in 0.007 (0.007) seconds
```

The failure fires on exactly the injected line (`WorkflowShapeTests.swift:326`,
the `XCTAssertNil(step.continueOnError, ...)` assertion) and names the test
(`testWasmCompileStepIsBlockingShaped`) and the reason (`must not be
continue-on-error — it would swallow the fail-closed WASM gate`) — proof the
pin is live, not vacuously passing.

**Step 4 — revert:**

```
$ git checkout .github/workflows/swift-ci.yml
Updated 1 path from the index
$ git diff .github/workflows/swift-ci.yml
$ echo "DIFF_EMPTY=$?"
DIFF_EMPTY=0
```

**Step 5 — re-run the filtered test again; confirm green:**

```
$ swift test --filter WorkflowShapeTests/testWasmCompileStepIsBlockingShaped
Building for debugging...
[0/4] Write swift-version-58A378E29CF047B.txt
Build complete! (0.07s)
Test Suite 'Selected tests' started at 2026-07-19 23:20:43.660.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-07-19 23:20:43.660.
Test Suite 'WorkflowShapeTests' started at 2026-07-19 23:20:43.660.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testWasmCompileStepIsBlockingShaped]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testWasmCompileStepIsBlockingShaped]' passed (0.001 seconds).
Test Suite 'WorkflowShapeTests' passed at 2026-07-19 23:20:43.661.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
```

**Step 6 — confirm the probe left no residue:**

```
$ git status --short
$ echo "EXIT=$?"
EXIT=0
```

Empty output — the working tree is byte-clean after the cycle; the temporary
`continue-on-error: true` edit never reached a commit.

---

## Hosted evidence

All run IDs below are read at **step level** (`gh run view <id> --log`), not
by job conclusion alone — a `continue-on-error` step can conclude its job
green while the step itself failed (the Slice 16 dead-step trap), so job
status alone is never proof.

### Spike run (Task 5) — SDK resolution + first blocking pass

**Run `29701110835`**, commit `3457a8e`, event `pull_request`. All 3 required
jobs green.

- `cross_target_swift_version=6.2.1`
- `cross_target_sdk_install_seconds=5 attempts=1`
- SDK ids resolved: `swift-6.2.1-RELEASE_wasm` and
  `swift-6.2.1-RELEASE_wasm-embedded` (the real ids, carrying `-RELEASE` —
  see the "Pinned WASM SDK bundle" note above)
- Four blocking passes, all `result=pass reason=none blocking=true`:
  - `target=wasm package=core`
  - `target=wasm_embedded package=core`
  - `target=wasm package=providers`
  - `target=wasm_embedded package=providers`
- `mode=cross_target_compile_overall blocking_failures=0 exit=0`
- WASM job step wall-clock: ~17s (19:42:34 -> 19:42:51 UTC)
- **Task 5 Step 3 (the embedded-kind fallback ladder, demoting
  `wasm_embedded` to observational via `CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false`)
  was not needed** — `wasm_embedded` compiled clean as a blocking pass on the
  first hosted attempt, for both packages. The fallback path exists in the
  script and remains available for a future SDK regression, but nothing
  exercised it this slice.

### Caching decision (Task 6) — SKIP CACHING

**Decision: skip caching the SDK install; no workflow change, no commit.**

Justification: install time measured 5s / 5s / 6s across three separate
hosted runs (spike `29701110835`, AC3 liveness `29701547123`, final green
`29701773264`) — a single attempt every time, no retries, no visible noise.
Against the job's 20-minute (`timeout-minutes: 20` = 1200s) budget that is
~0.4-0.5% of the budget. Decision 7's rule ("if small and steady, skip
caching and record the number as the justification") applies directly — there
is no meaningful time to buy back by adding `actions/cache` complexity around
a ~106 MB download that already completes in single-digit seconds. The plan's
own local reference point (~33s for the 106 MB bundle) was a pessimistic
upper bound; hosted was faster still.

### Liveness AC2 — provisioning fail-closed

**Run `29701333581`**, throwaway commit `d732bf3` (pinned checksum's last
character flipped: `...f18af` -> `...f18ae`, in `swift-ci.yml`'s
`CROSS_TARGET_WASM_SDK_CHECKSUM`).

- Job conclusion: **failure**. WASM job red; "Host tests and benchmark gate"
  and "iOS cross-target compile" both stayed green — the corrupted pin only
  affects the WASM job's own SDK provisioning, confirming the fault is
  correctly scoped.
- Bounded retry genuinely retried, not a single-shot failure:
  `warn=sdk_install_attempt_failed attempt=1/3`, then `attempt=2/3`, then
  `attempt=3/3`, all failing against the same bad checksum (as expected — a
  wrong pin fails deterministically on every attempt, so the retry ladder
  exhausts and the step fails closed rather than hanging or silently
  skipping).
- `Error: Computed archive checksum '482b9f95462b87bedfafca94a092cf9ec4496671ca13b43745097122d20f18af'` —
  Swift's own SDK installer computed the *real* checksum of the downloaded
  bytes and reported it while rejecting the corrupted pin. This both proves
  `--checksum` is genuinely enforced (a mismatched pin cannot silently pass)
  and independently re-confirms the pinned sha256 recorded above is correct
  (it is exactly the value Swift computed).
- Four `result=fail reason=sdk_install_failed blocking=true` lines (one per
  target/package pair — the SDK never installed, so every blocking pass that
  depends on it fails the same way); `blocking_failures=4 exit=1`.

### Liveness AC3 — compile fail-closed

**Run `29701547123`**, throwaway commit `388678f` (checksum restored to the
correct value; `--target "$package_target"` changed to
`--target "${package_target}-nonexistent"` in the compile invocation).

- Job conclusion: **failure**. WASM job red; host + iOS jobs both green.
- `cross_target_sdk_install_seconds=5 attempts=1` — the SDK installed cleanly
  on the first attempt, which doubles as independent proof that the AC2
  checksum corruption was fully reverted (a bad checksum would have failed
  provisioning here too, and it didn't).
- Four `result=fail reason=compile_failed blocking=true` lines (the SDK is
  fine; the target string itself is bogus, so every compile invocation fails
  at the `swift build --swift-sdk <id> --target <bogus>` step);
  `blocking_failures=4 exit=1`.

### Revert + final green

The two throwaway commits (`d732bf3`, `388678f`) were dropped via
`git reset --hard 3457a8e` followed by `git push --force-with-lease` — they
are throwaway by design (the plan calls them that); their run logs remain
viewable on GitHub for the record above, but they are not part of branch
history. Post-revert local verification confirmed: working tree clean, the
pinned-checksum string appears exactly once via `grep`, no `nonexistent`
token anywhere in the compile script, and the real
`--target "$package_target"` invocation restored byte-for-byte.

**Final green run on the merge candidate — run `29701773264`**, commit
`3457a8e` (the current branch HEAD), event `pull_request`. **All 3 required
jobs `success`.**

- `cross_target_sdk_install_seconds=6 attempts=1`
- Four `result=pass` lines (all target/package pairs), `blocking_failures=0 exit=0`

### Post-merge push run

**`<PENDING>`** — PR #105 is not yet merged as of this record. Per this
repo's established pattern (see e.g. Slice 45's
`docs/superpowers/verification/2026-07-19-realistic-provider-ci-gate-promotion.md`,
"Hosted CI — Discharged (AC7)"), the post-merge `push` run to `main` will be
read at step level and this section will be filled in by a docs-only
follow-up PR after merge. No run ID is fabricated here.

---

## Summary against the spec's acceptance criteria touched by this task

- **AC1** (both kinds blocking, per-kind) — confirmed hosted: four
  `result=pass blocking=true` lines on both the spike run and the final green
  run, covering `{wasm, wasm_embedded} x {core, providers}`.
- **AC2** (fail-closed provisioning, live) — confirmed hosted: run
  `29701333581`, job failure, bounded retry exhausted, real checksum reported
  and mismatch rejected.
- **AC3** (fail-closed compile, live) — confirmed hosted: run `29701547123`,
  job failure, four `reason=compile_failed` lines.
- **AC4** (version drift stays fail-closed) — needed no new code: the
  resolve-by-detected-version path's fail-closed behavior (yielding
  `sdk_unresolved_after_install` on a mismatch) is already covered by the
  existing `wasm_skip_result`/`count_blocking_failures` self-tests exercised
  by `./.github/scripts/cross-target-compile.sh --self-test` above; the
  optional explicit `version_mismatch` guard was not built (spec allows this).
- **AC5** (self-test + swift test + build + Foundation scan) — all green
  locally, transcripts above.
- **AC6** (governance — minimal path, ruleset unchanged) — confirmed via
  `gh api`:

  ```
  $ gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{name, id, required_checks: [.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context]}'
  {"id":17656807,"name":"Main","required_checks":["Host tests and benchmark gate","iOS cross-target compile","WASM cross-target observation"]}
  ```

  The `Main` ruleset (id `17656807`) still requires exactly the same three
  contexts — `Host tests and benchmark gate`, `iOS cross-target compile`, and
  `WASM cross-target observation` — as recorded in
  `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`. This
  slice did not touch the ruleset or rename the WASM job/context, so the
  `WASM cross-target observation` context name survives intact even though the
  job it names is now blocking; the rename + ruleset update stays a deferred
  follow-up per the spec's non-goals.
- **AC7** (multi-run hosted reliability, step level) — three independent
  hosted runs (`29701110835`, `29701547123`, `29701773264`) all show
  `cross_target_sdk_install_seconds` in the 5-6s range with `attempts=1`; the
  post-merge push run remains `<PENDING>` per above.
- **AC8** (AGENTS.md updated; no engine source touched) — see the `AGENTS.md`
  diff in this same commit; `Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders` are untouched on the whole branch
  (confirmed by `git diff --name-only main...HEAD` above).
- **AC9** (caching decision evidenced) — see "Caching decision (Task 6)"
  above: skip, with the three measured install times as justification.
