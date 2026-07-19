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

### Task 4's pin-liveness cycle (cited, not re-run)

The `WorkflowShapeTests.testWasmCompileStepIsBlockingShaped` break -> red ->
revert -> green cycle (injecting `continue-on-error: true` under the WASM
compile step, confirming the new test fails by name with the exact
`continueOnError` assertion message, reverting, and confirming a byte-clean
`git diff` on the workflow file) was already performed and recorded during
Task 4. See
`/Users/aabanschikov/swift-text-engine/.superpowers/sdd/task-4-report.md`,
"Step 5: liveness proof (local break -> red -> revert -> green)", for the full
transcript. Not reproduced here to avoid re-editing a committed workflow file
as part of a docs-only task.

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
- **AC5** (self-test + swift test + build + Foundation scan) — all green
  locally, transcripts above.
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
