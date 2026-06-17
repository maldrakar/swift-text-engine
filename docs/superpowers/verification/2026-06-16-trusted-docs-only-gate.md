# Trusted Docs-Only Gate Verification

Date: 2026-06-16

## Summary

Slice 19 makes the Swift CI docs-only shortcut run the classifier from the PR
base commit trusted worktree instead of PR-owned helper code. It also tightens
the detector so empty real runtime diffs fail closed.

No Swift source, tests, benchmark code, benchmark budgets, package metadata,
required job contexts, ruleset requirements, or bypass actors changed.

## Local State

Command:

```bash
git status --short --branch > /private/tmp/slice-19-git-status.txt
cat /private/tmp/slice-19-git-status.txt
```

Exit status: 0

Output:

```text
## slice-19-trusted-docs-only-gate...origin/slice-19-trusted-docs-only-gate [ahead 4]
?? docs/superpowers/plans/2026-06-16-trusted-docs-only-gate.md
```

The untracked plan file is pre-existing and intentionally not part of this
verification task.

## Detector Checks

Task 1 red proof for empty runtime diffs before the detector change:

Command:

```bash
base_sha="$(git rev-parse HEAD)"
./.github/scripts/detect-docs-only-pr.sh \
  --base "$base_sha" \
  --head "$base_sha" \
  > /private/tmp/slice-19-empty-runtime-before.out 2>&1
cat /private/tmp/slice-19-empty-runtime-before.out
```

Exit status: 0, from Task 1 report

Output:

```text
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=0 non_doc_count=0
```

This showed that empty real runtime diffs were incorrectly classified as
docs-only before the fix.

Task 2 red detector self-test:

Command:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test \
  > /private/tmp/slice-19-detector-red.out 2>&1
cat /private/tmp/slice-19-detector-red.out
```

Exit status: 1, expected red test

Output:

```text
self_test=fail label=runtime_empty_diff_status expected=2 actual=0
```

Task 2 green runtime behavior after the detector change:

Command:

```bash
base_sha="$(git rev-parse HEAD)"
set +e
./.github/scripts/detect-docs-only-pr.sh \
  --base "$base_sha" \
  --head "$base_sha" \
  > /private/tmp/slice-19-empty-runtime-after.out 2>&1
empty_runtime_status=$?
set -e
cat /private/tmp/slice-19-empty-runtime-after.out
echo "empty_runtime_status=${empty_runtime_status}"
test "$empty_runtime_status" -eq 2
```

Detector exit status: 2; verification command exit status: 0, from Task 2 report

Output:

```text
mode=docs_only_pr result=infrastructure_failure reason=empty_diff docs_only_pr=false
```

Final detector self-test:

Command:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-19-detector-self-test.out 2>&1
cat /private/tmp/slice-19-detector-self-test.out
```

Exit status: 0

Output:

```text
self_test=pass
```

Syntax check:

Command:

```bash
bash -n .github/scripts/detect-docs-only-pr.sh > /private/tmp/slice-19-detector-bash-n.out 2>&1
```

Exit status: 0

Output: none; `/private/tmp/slice-19-detector-bash-n.out` is empty.

## Workflow Shape Checks

Task 3 red shape proof before the workflow change:

Command:

```bash
/private/tmp/slice-19-workflow-shape-check.sh \
  > /private/tmp/slice-19-workflow-shape-red.out 2>&1
cat /private/tmp/slice-19-workflow-shape-red.out
```

Exit status: 1, expected red test

Output:

```text
pull_request_paths_ignore=absent
push_paths_ignore=present
required_job_names=present
trusted_worktree_add_count=
```

Supplemental red-proof note:

Command:

```bash
parent_commit="dd5d996f5107b8d73efd0fb8514546bae15fd369^"
git show "${parent_commit}:.github/workflows/swift-ci.yml" \
  > /private/tmp/slice-19-parent-swift-ci.yml
{
  echo "parent_workflow=/private/tmp/slice-19-parent-swift-ci.yml"
  echo "parent_commit=${parent_commit}"
  echo "parent_trusted_worktree_matches=$(rg -c 'git worktree add --detach \"\\$trusted_ci_dir\" \"\\$BASE_SHA\"' /private/tmp/slice-19-parent-swift-ci.yml || true)"
  echo "parent_pr_workspace_detector_matches=$(rg -c '^\\s+\\./\\.github/scripts/detect-docs-only-pr\\.sh --base \"\\$BASE_SHA\" --head \"\\$HEAD_SHA\" --github-output \"\\$GITHUB_OUTPUT\"' /private/tmp/slice-19-parent-swift-ci.yml || true)"
  echo "note=original exact checker failed red before edits, but printed trusted_worktree_add_count= due to local rg -c no-match behavior rather than trusted_worktree_add_count=0"
  echo "conclusion=evidence_only_issue_not_workflow_implementation_issue"
} > /private/tmp/slice-19-workflow-shape-red-supplement.txt
cat /private/tmp/slice-19-workflow-shape-red-supplement.txt
```

Output:

```text
parent_workflow=/private/tmp/slice-19-parent-swift-ci.yml
parent_commit=dd5d996f5107b8d73efd0fb8514546bae15fd369^
parent_trusted_worktree_matches=0
parent_pr_workspace_detector_matches=3
note=original exact checker failed red before edits, but printed trusted_worktree_add_count= due to local rg -c no-match behavior rather than trusted_worktree_add_count=0
conclusion=evidence_only_issue_not_workflow_implementation_issue
```

Final green workflow shape check:

Command:

```bash
/private/tmp/slice-19-workflow-shape-check.sh > /private/tmp/slice-19-workflow-shape-green.out 2>&1
cat /private/tmp/slice-19-workflow-shape-green.out
```

Exit status: 0

Output:

```text
pull_request_paths_ignore=absent
push_paths_ignore=present
required_job_names=present
trusted_worktree_add_count=3
trusted_detector_path_count=3
trusted_detector_invocation_count=3
pr_workspace_detector_invocation=absent
pull_request_target=absent
workflow_shape=pass
```

The required job contexts remain:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

## Documentation Checks

Task 4 red documentation proof:

Command:

```bash
rg -n "trusted-ci|trusted base tree|BASE_SHA\\.\\.\\.HEAD_SHA|empty runtime diffs|\\.github/workflows/\\*\\*|\\.github/scripts/\\*\\*" AGENTS.md \
  > /private/tmp/slice-19-agents-before.out
cat /private/tmp/slice-19-agents-before.out
```

Exit status: 1, from Task 4 report

Output: none; `/private/tmp/slice-19-agents-before.out` is empty.

The red check confirmed the prior repo guidance did not yet document the trusted
base worktree docs-only behavior.

Final green documentation proof:

Command:

```bash
rg -n "trusted-ci|trusted base tree|BASE_SHA\\.\\.\\.HEAD_SHA|empty runtime diffs|\\.github/workflows/\\*\\*|\\.github/scripts/\\*\\*" AGENTS.md \
  > /private/tmp/slice-19-agents-after.out
cat /private/tmp/slice-19-agents-after.out
```

Exit status: 0

Output:

```text
122:`$RUNNER_TEMP/trusted-ci` with `git worktree` and executes
123:`.github/scripts/detect-docs-only-pr.sh` from that trusted base tree. The
125:`BASE_SHA...HEAD_SHA` diff, but the code that decides `docs_only_pr` is not
128:Swift/test/compile work. Missing commits, diff failures, and empty runtime diffs
129:fail closed. PR-owned workflow/helper changes under `.github/workflows/**` or
130:`.github/scripts/**`, Swift source, tests, package metadata, and all other
```

## Ruleset Readback

The first sandboxed network attempt failed with:

```text
error connecting to api.github.com
check your internet connection or https://githubstatus.com
```

The same readback was rerun with network escalation and passed.

Command:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 \
  --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' \
  > /private/tmp/slice-19-ruleset-final-local.json

jq -e '
  .id == 17656807
  and .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and ([.rules[] | select(.type == "required_status_checks")] | length == 1)
  and ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy) == true
' /private/tmp/slice-19-ruleset-final-local.json
```

Exit status: 0

Output:

```text
true
```

Relevant readback summary:

```text
id=17656807
name=Main
target=branch
enforcement=active
strict_required_status_checks_policy=true
required_status_checks:
- Host tests and benchmark gate
- iOS cross-target compile
- WASM cross-target observation
bypass_actor_count=1
```

## Scope Proof

Final local check command:

```bash
git status --short --branch > /private/tmp/slice-19-git-status.txt
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-19-detector-self-test.out 2>&1
bash -n .github/scripts/detect-docs-only-pr.sh > /private/tmp/slice-19-detector-bash-n.out 2>&1
/private/tmp/slice-19-workflow-shape-check.sh > /private/tmp/slice-19-workflow-shape-green.out 2>&1
git diff --check > /private/tmp/slice-19-diff-check.out 2>&1
set +e
rg -n "Foundation" Sources/TextEngineCore > /private/tmp/slice-19-foundation-scan.out 2>&1
foundation_status=$?
git diff --name-only main...HEAD -- Sources Tests Package.swift > /private/tmp/slice-19-source-scope.out 2>&1
source_scope_status=$?
set -e
cat /private/tmp/slice-19-git-status.txt
cat /private/tmp/slice-19-detector-self-test.out
cat /private/tmp/slice-19-detector-bash-n.out
cat /private/tmp/slice-19-workflow-shape-green.out
cat /private/tmp/slice-19-diff-check.out
cat /private/tmp/slice-19-foundation-scan.out
echo "foundation_status=${foundation_status}"
cat /private/tmp/slice-19-source-scope.out
echo "source_scope_status=${source_scope_status}"
test "$foundation_status" -eq 1
test "$source_scope_status" -eq 0
test ! -s /private/tmp/slice-19-source-scope.out
```

Exit status: 0

Output:

```text
## slice-19-trusted-docs-only-gate...origin/slice-19-trusted-docs-only-gate [ahead 4]
?? docs/superpowers/plans/2026-06-16-trusted-docs-only-gate.md
self_test=pass
pull_request_paths_ignore=absent
push_paths_ignore=present
required_job_names=present
trusted_worktree_add_count=3
trusted_detector_path_count=3
trusted_detector_invocation_count=3
pr_workspace_detector_invocation=absent
pull_request_target=absent
workflow_shape=pass
foundation_status=1
source_scope_status=0
```

Additional empty-output proof:

```text
/private/tmp/slice-19-detector-bash-n.out: 0 bytes
/private/tmp/slice-19-diff-check.out: 0 bytes
/private/tmp/slice-19-foundation-scan.out: 0 bytes
/private/tmp/slice-19-source-scope.out: 0 bytes
```

No Swift source, tests, or package metadata are in the `main...HEAD` source
scope diff:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift
```

Exit status: 0

Output: none.

## Hosted PR-Head Heavy Proof

Command:

```bash
run_id="$(cat /private/tmp/slice-19-pr-run-id.txt)"
gh run view "$run_id" --json jobs --jq '[.jobs[] | {name,status,conclusion}]'
gh run view "$run_id" --log
```

Exit status: `0`.

Evidence:

```text
run_id=27651372140
pr=20
head_sha=26aa3e604180fea768a65a63e541221028c6467c
jobs=[{"conclusion":"success","name":"WASM cross-target observation","status":"completed"},{"conclusion":"success","name":"Host tests and benchmark gate","status":"completed"},{"conclusion":"success","name":"iOS cross-target compile","status":"completed"}]
heavy_path_lines=WASM cross-target observation	Observe TextEngineCore for WASM targets	﻿2026-06-16T22:09:11.0862181Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets wasm;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:09:11.0862739Z ^[[36;1m./.github/scripts/cross-target-compile.sh --targets wasm^[[0m;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:09:11.0863226Z shell: sh -e {0};WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:09:11.0863444Z ##[endgroup];WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:09:11.2011916Z cross_target_swift_version=6.2.1;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:09:11.2013350Z mode=cross_target_compile target=ios_device result=skipped reason=not_requested blocking=false;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:09:11.2015482Z mode=cross_target_compile target=ios_simulator result=skipped reason=not_requested blocking=false;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:09:11.3527977Z mode=cross_target_compile target=wasm result=skipped reason=sdk_unavailable blocking=false;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:09:11.4975765Z mode=cross_target_compile target=wasm_embedded result=skipped reason=sdk_unavailable blocking=false;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:09:11.4983555Z mode=cross_target_compile_summary ios_device=skipped ios_simulator=skipped wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0;Host tests and benchmark gate	Run host tests	﻿2026-06-16T22:09:06.1314419Z ##[group]Run swift test --scratch-path /tmp/text-engine-host-build;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:06.1314921Z ^[[36;1mswift test --scratch-path /tmp/text-engine-host-build^[[0m;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:06.1315360Z shell: sh -e {0};Host tests and benchmark gate	Run host tests	2026-06-16T22:09:06.1315567Z ##[endgroup];Host tests and benchmark gate	Run host tests	2026-06-16T22:09:06.6968223Z Building for debugging...;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:06.7027301Z [0/21] Write sources;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:06.7563276Z [5/21] Write swift-version-24593BA9C3E375BF.txt;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.5494122Z [7/28] Compiling TextEngineCore VariableLineGeometryCursor.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.5495406Z [8/28] Compiling TextEngineCore VariableViewportVirtualizer.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.7528663Z [9/30] Compiling TextEngineCore ViewportTypes.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.7529683Z [10/30] Compiling TextEngineCore ViewportVirtualizer.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.8222689Z [11/30] Emitting module TextEngineCore;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.8223351Z [12/30] Compiling TextEngineCore DocumentLineCursor.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.8223773Z [13/30] Compiling TextEngineCore DocumentLineTypes.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.8224256Z [14/30] Compiling TextEngineCore LineGeometryCursor.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.8224616Z [15/30] Compiling TextEngineCore LineMetricsSource.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:09.8983586Z [16/34] Wrapping AST for TextEngineCore for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:10.0125441Z [18/46] Compiling TextEngineReferenceProviders PrefixSumLineMetrics.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:10.0892563Z [19/46] Compiling TextEngineReferenceProviders FenwickLineMetrics.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:10.0913060Z [20/46] Emitting module TextEngineReferenceProviders;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:10.1678521Z [21/47] Wrapping AST for TextEngineReferenceProviders for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:10.3954993Z [23/59] Emitting module ViewportBenchmarks;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:11.6629285Z [24/61] Compiling ViewportBenchmarks VariableHeightMutationBenchmark.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:11.6639864Z [25/61] Compiling ViewportBenchmarks main.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:11.6754897Z [26/61] Compiling ViewportBenchmarks BenchmarkSupport.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:11.6760405Z [27/61] Compiling ViewportBenchmarks MemoryObservationDiagnostics.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:11.6766120Z [28/61] Compiling ViewportBenchmarks MemoryShapeDiagnostics.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:12.5535521Z [29/61] Compiling ViewportBenchmarks BenchmarkModels.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:12.5576609Z [30/61] Compiling ViewportBenchmarks BenchmarkOptions.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:12.5584498Z [31/61] Compiling ViewportBenchmarks BenchmarkProgram.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:12.5591967Z [32/61] Compiling ViewportBenchmarks RealisticProviderBenchmark.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:12.5599235Z [33/61] Compiling ViewportBenchmarks SyntheticBenchmarks.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:12.5606363Z [34/61] Compiling ViewportBenchmarks VariableHeightBenchmark.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:12.6596952Z [35/62] Wrapping AST for ViewportBenchmarks for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:12.6609715Z [36/62] Write Objects.LinkFileList;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:12.8203059Z [37/62] Linking ViewportBenchmarks;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.5014506Z [43/65] Emitting module TextEngineCoreTests;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.5195956Z [51/65] Compiling TextEngineReferenceProvidersTests FenwickLineMetricsTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.5223914Z [52/65] Emitting module TextEngineReferenceProvidersTests;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.5913648Z [53/66] Wrapping AST for TextEngineReferenceProvidersTests for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.7709849Z [55/66] Compiling TextEngineCoreTests ViewportOverscanInvariantTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.7710819Z [56/66] Compiling TextEngineCoreTests ViewportRangeTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.7711835Z [57/66] Compiling TextEngineCoreTests ViewportValidationTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.8084742Z [58/67] /tmp/text-engine-host-build/x86_64-unknown-linux-gnu/debug/SwiftTextEnginePackageDiscoveredTests.derived/all-discovered-tests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.8086363Z [59/67] Write sources;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:13.8362245Z [60/67] Wrapping AST for TextEngineCoreTests for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:15.1906487Z [62/71] Compiling SwiftTextEnginePackageDiscoveredTests TextEngineReferenceProvidersTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:15.1908186Z [63/71] Emitting module SwiftTextEnginePackageDiscoveredTests;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:15.1909612Z [64/71] Compiling SwiftTextEnginePackageDiscoveredTests all-discovered-tests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:15.1910822Z [65/71] Compiling SwiftTextEnginePackageDiscoveredTests TextEngineCoreTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:15.2254856Z [66/72] /tmp/text-engine-host-build/x86_64-unknown-linux-gnu/debug/SwiftTextEnginePackageTests.derived/runner.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:15.2257465Z [67/72] Write sources;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:15.2547614Z [68/72] Wrapping AST for SwiftTextEnginePackageDiscoveredTests for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.0239439Z [70/74] Emitting module SwiftTextEnginePackageTests;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.0240042Z [71/74] Compiling SwiftTextEnginePackageTests runner.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.0892967Z [72/75] Wrapping AST for SwiftTextEnginePackageTests for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.0895455Z [73/75] Write Objects.LinkFileList;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2202737Z [74/75] Linking SwiftTextEnginePackageTests.xctest;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2242925Z Build complete! (11.58s);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2346463Z Test Suite 'All tests' started at 2026-06-16 22:09:18.230;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2347140Z Test Suite 'debug.xctest' started at 2026-06-16 22:09:18.231;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2347674Z Test Suite 'DocumentLineCursorTests' started at 2026-06-16 22:09:18.231;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2348453Z Test Case 'DocumentLineCursorTests.testCursorFetchesOneLinePerBufferedIndex' started at 2026-06-16 22:09:18.231;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2349405Z Test Case 'DocumentLineCursorTests.testCursorFetchesOneLinePerBufferedIndex' passed (0.001 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2350438Z Test Case 'DocumentLineCursorTests.testCursorReportsMissingIndexesWithoutClampingRange' started at 2026-06-16 22:09:18.232;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2352453Z Test Case 'DocumentLineCursorTests.testCursorReportsMissingIndexesWithoutClampingRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2354327Z Test Case 'DocumentLineCursorTests.testCursorYieldsBufferedRangeLinesInOrder' started at 2026-06-16 22:09:18.232;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2356027Z Test Case 'DocumentLineCursorTests.testCursorYieldsBufferedRangeLinesInOrder' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2357384Z Test Case 'DocumentLineCursorTests.testCursorYieldsNothingForEmptyRangeAndDoesNotFetch' started at 2026-06-16 22:09:18.233;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2358468Z Test Case 'DocumentLineCursorTests.testCursorYieldsNothingForEmptyRangeAndDoesNotFetch' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2359356Z Test Case 'DocumentLineCursorTests.testGeneratedRangesFetchOnlyBufferedIndexes' started at 2026-06-16 22:09:18.233;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2360322Z Test Case 'DocumentLineCursorTests.testGeneratedRangesFetchOnlyBufferedIndexes' passed (0.001 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2361184Z Test Case 'DocumentLineCursorTests.testViewportComputationDoesNotFetchProviderLines' started at 2026-06-16 22:09:18.233;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2362375Z Test Case 'DocumentLineCursorTests.testViewportComputationDoesNotFetchProviderLines' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2363043Z Test Suite 'DocumentLineCursorTests' passed at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2363531Z 	 Executed 6 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2364257Z Test Suite 'DocumentLineValueTests' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2364993Z Test Case 'DocumentLineValueTests.testDocumentLineCursorElementEquatableWhenPayloadIsEquatable' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2365991Z Test Case 'DocumentLineValueTests.testDocumentLineCursorElementEquatableWhenPayloadIsEquatable' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2366898Z Test Case 'DocumentLineValueTests.testDocumentLineEquatableWhenPayloadIsEquatable' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2367743Z Test Case 'DocumentLineValueTests.testDocumentLineEquatableWhenPayloadIsEquatable' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2368610Z Test Case 'DocumentLineValueTests.testDocumentLineFetchEquatableWhenPayloadIsEquatable' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2369496Z Test Case 'DocumentLineValueTests.testDocumentLineFetchEquatableWhenPayloadIsEquatable' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2370465Z Test Case 'DocumentLineValueTests.testDocumentLineStoresIndexAndContent' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2371206Z Test Case 'DocumentLineValueTests.testDocumentLineStoresIndexAndContent' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2372537Z Test Suite 'DocumentLineValueTests' passed at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2373212Z 	 Executed 4 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2373691Z Test Suite 'LineGeometryCursorTests' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2374412Z Test Case 'LineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2375243Z Test Case 'LineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2376210Z Test Case 'LineGeometryCursorTests.testCursorYieldsOnlyBufferedLines' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2377101Z Test Case 'LineGeometryCursorTests.testCursorYieldsOnlyBufferedLines' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2377838Z Test Suite 'LineGeometryCursorTests' passed at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2378285Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2378850Z Test Suite 'LineMetricsSourceTests' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2379466Z Test Case 'LineMetricsSourceTests.testUniformLineMetricsOffsetIsLinear' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2380343Z Test Case 'LineMetricsSourceTests.testUniformLineMetricsOffsetIsLinear' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2381023Z Test Suite 'LineMetricsSourceTests' passed at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2382058Z 	 Executed 1 test, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2383363Z Test Suite 'VariableHeightQueryCountTests' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2384994Z Test Case 'VariableHeightQueryCountTests.testComputeClampAtDocumentEndDoesNotSearchMidDocumentOffsets' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2387013Z Test Case 'VariableHeightQueryCountTests.testComputeClampAtDocumentEndDoesNotSearchMidDocumentOffsets' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2388496Z Test Case 'VariableHeightQueryCountTests.testComputeEmptyDocumentQueriesOnlyFirstOffset' started at 2026-06-16 22:09:18.234;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2389784Z Test Case 'VariableHeightQueryCountTests.testComputeEmptyDocumentQueriesOnlyFirstOffset' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2390803Z Test Case 'VariableHeightQueryCountTests.testComputeSingleLineStaysBounded' started at 2026-06-16 22:09:18.235;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2391882Z Test Case 'VariableHeightQueryCountTests.testComputeSingleLineStaysBounded' passed (0.001 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2392989Z Test Case 'VariableHeightQueryCountTests.testComputeUsesLogarithmicQueriesAtOneMillionLines' started at 2026-06-16 22:09:18.235;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2394149Z Test Case 'VariableHeightQueryCountTests.testComputeUsesLogarithmicQueriesAtOneMillionLines' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2395576Z Test Case 'VariableHeightQueryCountTests.testEmptyGeometryCursorDoesNotSeedOffsetQuery' started at 2026-06-16 22:09:18.235;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2396703Z Test Case 'VariableHeightQueryCountTests.testEmptyGeometryCursorDoesNotSeedOffsetQuery' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2397881Z Test Case 'VariableHeightQueryCountTests.testNonEmptyGeometryCursorQueriesSeedPlusOnePerBufferedLine' started at 2026-06-16 22:09:18.236;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2399138Z Test Case 'VariableHeightQueryCountTests.testNonEmptyGeometryCursorQueriesSeedPlusOnePerBufferedLine' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2399901Z Test Suite 'VariableHeightQueryCountTests' passed at 2026-06-16 22:09:18.236;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2400393Z 	 Executed 6 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2400882Z Test Suite 'VariableLineGeometryCursorTests' started at 2026-06-16 22:09:18.236;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2401931Z Test Case 'VariableLineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' started at 2026-06-16 22:09:18.236;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2402803Z Test Case 'VariableLineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2403640Z Test Case 'VariableLineGeometryCursorTests.testCursorYieldsBufferedLineGeometry' started at 2026-06-16 22:09:18.236;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2404458Z Test Case 'VariableLineGeometryCursorTests.testCursorYieldsBufferedLineGeometry' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2405106Z Test Suite 'VariableLineGeometryCursorTests' passed at 2026-06-16 22:09:18.236;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2405604Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2406081Z Test Suite 'VariableUniformEquivalenceTests' started at 2026-06-16 22:09:18.236;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2406803Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedAcrossRepresentableHeights' started at 2026-06-16 22:09:18.236;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2407690Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedAcrossRepresentableHeights' passed (0.001 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2408515Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedForIntMaxClamp' started at 2026-06-16 22:09:18.237;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2409480Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedForIntMaxClamp' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2410137Z Test Suite 'VariableUniformEquivalenceTests' passed at 2026-06-16 22:09:18.237;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2410827Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2411664Z Test Suite 'VariableViewportComputeTests' started at 2026-06-16 22:09:18.237;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2412962Z Test Case 'VariableViewportComputeTests.testEmptyDocumentReturnsEmptyRange' started at 2026-06-16 22:09:18.237;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2414407Z Test Case 'VariableViewportComputeTests.testEmptyDocumentReturnsEmptyRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2415951Z Test Case 'VariableViewportComputeTests.testEmptyDocumentStillValidatesFirstOffset' started at 2026-06-16 22:09:18.238;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2417448Z Test Case 'VariableViewportComputeTests.testEmptyDocumentStillValidatesFirstOffset' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2418221Z Test Case 'VariableViewportComputeTests.testNegativeLineCountFails' started at 2026-06-16 22:09:18.238;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2418902Z Test Case 'VariableViewportComputeTests.testNegativeLineCountFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2419586Z Test Case 'VariableViewportComputeTests.testNegativeOverscanFails' started at 2026-06-16 22:09:18.238;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2420257Z Test Case 'VariableViewportComputeTests.testNegativeOverscanFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2420955Z Test Case 'VariableViewportComputeTests.testNegativeViewportHeightFails' started at 2026-06-16 22:09:18.238;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2421842Z Test Case 'VariableViewportComputeTests.testNegativeViewportHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2422600Z Test Case 'VariableViewportComputeTests.testNonFiniteScrollOffsetFails' started at 2026-06-16 22:09:18.238;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2423487Z Test Case 'VariableViewportComputeTests.testNonFiniteScrollOffsetFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2424222Z Test Case 'VariableViewportComputeTests.testNonFiniteTotalHeightFails' started at 2026-06-16 22:09:18.238;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2424927Z Test Case 'VariableViewportComputeTests.testNonFiniteTotalHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2425657Z Test Case 'VariableViewportComputeTests.testNonFiniteViewportHeightFails' started at 2026-06-16 22:09:18.238;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2426398Z Test Case 'VariableViewportComputeTests.testNonFiniteViewportHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2427123Z Test Case 'VariableViewportComputeTests.testNonPositiveTotalHeightFails' started at 2026-06-16 22:09:18.238;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2427860Z Test Case 'VariableViewportComputeTests.testNonPositiveTotalHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2428674Z Test Case 'VariableViewportComputeTests.testNonUniformVisibleRange' started at 2026-06-16 22:09:18.238;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2429363Z Test Case 'VariableViewportComputeTests.testNonUniformVisibleRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2430036Z Test Case 'VariableViewportComputeTests.testNonUniformWithOverscan' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2430704Z Test Case 'VariableViewportComputeTests.testNonUniformWithOverscan' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2431620Z Test Case 'VariableViewportComputeTests.testNonZeroFirstOffsetFails' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2432369Z Test Case 'VariableViewportComputeTests.testNonZeroFirstOffsetFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2433838Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportAtDocumentEndClampsToLineCount' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2435713Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportAtDocumentEndClampsToLineCount' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2437382Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportExactLineTopIsEmpty' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2438549Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportExactLineTopIsEmpty' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2439417Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportMidLineKeepsCrossedLine' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2440289Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportMidLineKeepsCrossedLine' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2440959Z Test Suite 'VariableViewportComputeTests' passed at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2441574Z 	 Executed 15 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2442074Z Test Suite 'VariableViewportInputValueTests' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2442760Z Test Case 'VariableViewportInputValueTests.testInvalidLineMetricsErrorIsDistinct' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2443582Z Test Case 'VariableViewportInputValueTests.testInvalidLineMetricsErrorIsDistinct' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2444407Z Test Case 'VariableViewportInputValueTests.testVariableViewportInputStoresFields' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2445213Z Test Case 'VariableViewportInputValueTests.testVariableViewportInputStoresFields' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2445857Z Test Suite 'VariableViewportInputValueTests' passed at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2446333Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2446766Z Test Suite 'ViewportInputValueTests' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2447381Z Test Case 'ViewportInputValueTests.testLineGeometryStoresIndexAndDimensions' started at 2026-06-16 22:09:18.239;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2448144Z Test Case 'ViewportInputValueTests.testLineGeometryStoresIndexAndDimensions' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2448869Z Test Case 'ViewportInputValueTests.testViewportInputStoresAllFields' started at 2026-06-16 22:09:18.240;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2449736Z Test Case 'ViewportInputValueTests.testViewportInputStoresAllFields' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2450399Z Test Case 'ViewportInputValueTests.testVirtualRangeReportsEmpty' started at 2026-06-16 22:09:18.240;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2451056Z Test Case 'ViewportInputValueTests.testVirtualRangeReportsEmpty' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2451705Z Test Suite 'ViewportInputValueTests' passed at 2026-06-16 22:09:18.240;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2452135Z 	 Executed 3 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2452595Z Test Suite 'ViewportOverscanInvariantTests' started at 2026-06-16 22:09:18.240;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2453240Z Test Case 'ViewportOverscanInvariantTests.testGeneratedInputsStayInBounds' started at 2026-06-16 22:09:18.240;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2454103Z Test Case 'ViewportOverscanInvariantTests.testGeneratedInputsStayInBounds' passed (0.001 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2454931Z Test Case 'ViewportOverscanInvariantTests.testOverscanBeforeClampsToZeroWithIntegerMath' started at 2026-06-16 22:09:18.241;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2455833Z Test Case 'ViewportOverscanInvariantTests.testOverscanBeforeClampsToZeroWithIntegerMath' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2456729Z Test Case 'ViewportOverscanInvariantTests.testOverscanClampsAtTopAndBottom' started at 2026-06-16 22:09:18.241;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2457503Z Test Case 'ViewportOverscanInvariantTests.testOverscanClampsAtTopAndBottom' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2458256Z Test Case 'ViewportOverscanInvariantTests.testOverscanExpandsBufferedRange' started at 2026-06-16 22:09:18.241;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2459000Z Test Case 'ViewportOverscanInvariantTests.testOverscanExpandsBufferedRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2459797Z Test Case 'ViewportOverscanInvariantTests.testOverscanPreservesPrecisionNearIntMax' started at 2026-06-16 22:09:18.241;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2460645Z Test Case 'ViewportOverscanInvariantTests.testOverscanPreservesPrecisionNearIntMax' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2461299Z Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-16 22:09:18.241;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2461914Z 	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2462350Z Test Suite 'ViewportRangeTests' started at 2026-06-16 22:09:18.241;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2463011Z Test Case 'ViewportRangeTests.testFiniteExtremeOffsetClampsIndexBeforeIntConversion' started at 2026-06-16 22:09:18.241;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2463873Z Test Case 'ViewportRangeTests.testFiniteExtremeOffsetClampsIndexBeforeIntConversion' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2464742Z Test Case 'ViewportRangeTests.testFractionalLineHeightEndBoundaryDoesNotIncludeNextLine' started at 2026-06-16 22:09:18.242;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2465627Z Test Case 'ViewportRangeTests.testFractionalLineHeightEndBoundaryDoesNotIncludeNextLine' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2466512Z Test Case 'ViewportRangeTests.testFractionalLineHeightStartBoundaryBeginsAtExactLine' started at 2026-06-16 22:09:18.242;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2467372Z Test Case 'ViewportRangeTests.testFractionalLineHeightStartBoundaryBeginsAtExactLine' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2468243Z Test Case 'ViewportRangeTests.testFractionalLineHeightSublineOffsetIncludesPartialLines' started at 2026-06-16 22:09:18.242;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2469126Z Test Case 'ViewportRangeTests.testFractionalLineHeightSublineOffsetIncludesPartialLines' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2469965Z Test Case 'ViewportRangeTests.testLargeEndPartialLineDoesNotSnapDownToBoundary' started at 2026-06-16 22:09:18.242;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2470764Z Test Case 'ViewportRangeTests.testLargeEndPartialLineDoesNotSnapDownToBoundary' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2471706Z Test Case 'ViewportRangeTests.testLargeFractionalOffsetDoesNotSnapToBoundary' started at 2026-06-16 22:09:18.242;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2472487Z Test Case 'ViewportRangeTests.testLargeFractionalOffsetDoesNotSnapToBoundary' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2473284Z Test Case 'ViewportRangeTests.testLargeStartPartialLineDoesNotSnapUpToBoundary' started at 2026-06-16 22:09:18.242;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2474203Z Test Case 'ViewportRangeTests.testLargeStartPartialLineDoesNotSnapUpToBoundary' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2474940Z Test Case 'ViewportRangeTests.testNegativeScrollOffsetClampsToTop' started at 2026-06-16 22:09:18.242;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2475611Z Test Case 'ViewportRangeTests.testNegativeScrollOffsetClampsToTop' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2476337Z Test Case 'ViewportRangeTests.testSublineOffsetUsesFloorForStartAndCeilForEnd' started at 2026-06-16 22:09:18.242;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2477120Z Test Case 'ViewportRangeTests.testSublineOffsetUsesFloorForStartAndCeilForEnd' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2477920Z Test Case 'ViewportRangeTests.testViewportLargerThanDocumentReturnsWholeDocument' started at 2026-06-16 22:09:18.242;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2478839Z Test Case 'ViewportRangeTests.testViewportLargerThanDocumentReturnsWholeDocument' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2479656Z Test Case 'ViewportRangeTests.testZeroHeightViewportProducesEmptyRangeAtOffset' started at 2026-06-16 22:09:18.243;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2480487Z Test Case 'ViewportRangeTests.testZeroHeightViewportProducesEmptyRangeAtOffset' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2481085Z Test Suite 'ViewportRangeTests' passed at 2026-06-16 22:09:18.243;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2481643Z 	 Executed 11 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2482106Z Test Suite 'ViewportValidationTests' started at 2026-06-16 22:09:18.243;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2482706Z Test Case 'ViewportValidationTests.testEmptyDocumentReturnsEmptyRange' started at 2026-06-16 22:09:18.243;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2483413Z Test Case 'ViewportValidationTests.testEmptyDocumentReturnsEmptyRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2484084Z Test Case 'ViewportValidationTests.testNegativeLineCountFails' started at 2026-06-16 22:09:18.243;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2484712Z Test Case 'ViewportValidationTests.testNegativeLineCountFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2485339Z Test Case 'ViewportValidationTests.testNegativeOverscanFails' started at 2026-06-16 22:09:18.243;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2485962Z Test Case 'ViewportValidationTests.testNegativeOverscanFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.2486612Z Test Case 'ViewportValidationTests.testNegativeViewportHeightFails' started at 2026-06-16 22:09:18.243;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6724146Z Test Case 'ViewportValidationTests.testNegativeViewportHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6725174Z Test Case 'ViewportValidationTests.testNonFiniteLineHeightFails' started at 2026-06-16 22:09:18.243;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6725939Z Test Case 'ViewportValidationTests.testNonFiniteLineHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6726700Z Test Case 'ViewportValidationTests.testNonFiniteScrollOffsetYFails' started at 2026-06-16 22:09:18.243;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6727486Z Test Case 'ViewportValidationTests.testNonFiniteScrollOffsetYFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6728260Z Test Case 'ViewportValidationTests.testNonFiniteViewportHeightFails' started at 2026-06-16 22:09:18.244;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6729028Z Test Case 'ViewportValidationTests.testNonFiniteViewportHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6729775Z Test Case 'ViewportValidationTests.testNonPositiveLineHeightFails' started at 2026-06-16 22:09:18.244;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6730515Z Test Case 'ViewportValidationTests.testNonPositiveLineHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6731104Z Test Suite 'ViewportValidationTests' passed at 2026-06-16 22:09:18.244;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6731919Z 	 Executed 8 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6732436Z Test Suite 'FenwickLineMetricsTests' started at 2026-06-16 22:09:18.244;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6733157Z Test Case 'FenwickLineMetricsTests.testMutationKeepsOffsetsEqualToFreshOracle' started at 2026-06-16 22:09:18.244;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6734049Z Test Case 'FenwickLineMetricsTests.testMutationKeepsOffsetsEqualToFreshOracle' passed (0.001 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6735628Z Test Case 'FenwickLineMetricsTests.testOffsetMatchesPrefixSumOracleOnBuild' started at 2026-06-16 22:09:18.244;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6736413Z Test Case 'FenwickLineMetricsTests.testOffsetMatchesPrefixSumOracleOnBuild' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6737210Z Test Case 'FenwickLineMetricsTests.testOffsetsStrictlyIncreasingAfterMutation' started at 2026-06-16 22:09:18.245;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6738034Z Test Case 'FenwickLineMetricsTests.testOffsetsStrictlyIncreasingAfterMutation' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6738811Z Test Case 'FenwickLineMetricsTests.testPrefixQueryWalkBoundIsLogarithmic' started at 2026-06-16 22:09:18.245;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6739561Z Test Case 'FenwickLineMetricsTests.testPrefixQueryWalkBoundIsLogarithmic' passed (0.147 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6740475Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationMatchesFreshOracle' started at 2026-06-16 22:09:18.392;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6741839Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationMatchesFreshOracle' passed (0.102 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6742739Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationUsesLogarithmicCoreQueries' started at 2026-06-16 22:09:18.494;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6743626Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationUsesLogarithmicCoreQueries' passed (0.077 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6744468Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountExactForKnownSmallCases' started at 2026-06-16 22:09:18.572;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6745278Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountExactForKnownSmallCases' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6746080Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountIsLogarithmicAcrossSizes' started at 2026-06-16 22:09:18.572;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6746911Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountIsLogarithmicAcrossSizes' passed (0.086 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6747547Z Test Suite 'FenwickLineMetricsTests' passed at 2026-06-16 22:09:18.658;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6748011Z 	 Executed 8 tests, with 0 failures (0 unexpected) in 0.414 (0.414) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6748455Z Test Suite 'debug.xctest' passed at 2026-06-16 22:09:18.658;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6748870Z 	 Executed 75 tests, with 0 failures (0 unexpected) in 0.425 (0.425) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6749273Z Test Suite 'All tests' passed at 2026-06-16 22:09:18.658;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6749657Z 	 Executed 75 tests, with 0 failures (0 unexpected) in 0.425 (0.425) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6750234Z ◇ Test run started.;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6750559Z ↳ Testing Library Version: 6.2.1 (c9d57c83568b06d);Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6750935Z ↳ Target Platform: x86_64-unknown-linux-gnu;Host tests and benchmark gate	Run host tests	2026-06-16T22:09:18.6751343Z ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.;Host tests and benchmark gate	Run synthetic benchmark gate	﻿2026-06-16T22:09:18.6831215Z ##[group]Run swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:18.6832691Z ^[[36;1mswift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate^[[0m;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:18.6833372Z shell: sh -e {0};Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:18.6833588Z ##[endgroup];Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:19.2236571Z Building for production...;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:19.2268857Z [0/6] Write sources;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:19.2793262Z [3/6] Write swift-version-24593BA9C3E375BF.txt;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:19.7764543Z [5/7] Compiling TextEngineCore DocumentLineCursor.swift;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:20.0487245Z [6/8] Compiling TextEngineReferenceProviders FenwickLineMetrics.swift;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:23.2529238Z [7/9] Compiling ViewportBenchmarks BenchmarkModels.swift;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:23.2575349Z [7/9] Write Objects.LinkFileList;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:23.3547514Z [8/9] Linking ViewportBenchmarks;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:09:23.3569169Z Build of product 'ViewportBenchmarks' complete! (4.17s);Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:11:22.5547820Z mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=2519 p99_ns=3056 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:11:22.5554805Z mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=10442 p99_ns=10845 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:11:22.5557020Z mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=33992 p99_ns=35026 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000;iOS cross-target compile	Compile TextEngineCore for iOS targets	﻿2026-06-16T22:08:35.0207330Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets ios;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:35.0207810Z ^[[36;1m./.github/scripts/cross-target-compile.sh --targets ios^[[0m;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:35.0238460Z shell: /bin/bash -e {0};iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:35.0238700Z ##[endgroup];iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:35.2488200Z cross_target_swift_version=6.1.2;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:35.2488920Z cross_target_developer_dir=unset;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:35.2523520Z cross_target_xcode_select_path=/Applications/Xcode_16.4.app/Contents/Developer;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:35.2961430Z cross_target_xcodebuild_version=Xcode 16.4;Build version 16F6;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:36.0734250Z cross_target_iphoneos_sdk_path=/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.5.sdk;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:36.4449740Z cross_target_iphoneos_sdk_version=18.5;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:37.1427690Z cross_target_iphonesimulator_sdk_path=/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator18.5.sdk;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:37.4988670Z cross_target_iphonesimulator_sdk_version=18.5;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:49.9820140Z cross_target_command target=ios_device cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS'";iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:56.3912720Z mode=cross_target_compile target=ios_device result=pass reason=none blocking=true;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:08:56.3924370Z cross_target_command target=ios_simulator cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator'";iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:09:00.7722980Z mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:09:00.7724130Z mode=cross_target_compile target=wasm result=skipped reason=not_requested blocking=false;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:09:00.7725690Z mode=cross_target_compile target=wasm_embedded result=skipped reason=not_requested blocking=false;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:09:00.7746030Z mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0;
```

Committing this refreshed evidence may trigger another PR-head run; the final merged-code anchor remains the post-merge push proof.

The PR-head run is intentionally non-doc and must not take the docs-only shortcut.

## Post-Merge Push Proof

PR #20 was merged to `main` with merge commit
`f84651f2d1d5e664d8d420607448d8756a278b5a`.

Command:

```bash
merge_sha="f84651f2d1d5e664d8d420607448d8756a278b5a"
gh run list --workflow "Swift CI" --branch main --limit 10 \
  --json databaseId,headSha,status,conclusion,url \
  > /private/tmp/slice-19-main-runs.json
cat /private/tmp/slice-19-main-runs.json
jq -r --arg sha "$merge_sha" \
  '.[] | select(.headSha == $sha) | .databaseId' \
  /private/tmp/slice-19-main-runs.json \
  | sed -n '1p' \
  > /private/tmp/slice-19-main-run-id.txt
cat /private/tmp/slice-19-main-run-id.txt
test -s /private/tmp/slice-19-main-run-id.txt
main_run_id="$(cat /private/tmp/slice-19-main-run-id.txt)"
gh run view "$main_run_id" --json jobs \
  --jq '[.jobs[] | {name,status,conclusion}]' \
  > /private/tmp/slice-19-main-jobs.json
cat /private/tmp/slice-19-main-jobs.json
jq -e '
  ([.[].name] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and all(.[]; .status == "completed" and .conclusion == "success")
' /private/tmp/slice-19-main-jobs.json
```

Exit status: 0

Run evidence:

```text
run_id=27652542887
url=https://github.com/maldrakar/swift-text-engine/actions/runs/27652542887
head_sha=f84651f2d1d5e664d8d420607448d8756a278b5a
jobs=[{"conclusion":"success","name":"iOS cross-target compile","status":"completed"},{"conclusion":"success","name":"Host tests and benchmark gate","status":"completed"},{"conclusion":"success","name":"WASM cross-target observation","status":"completed"}]
```

The post-merge `push` run records the trusted gate changes on `main` and
confirms the required Swift CI job topology still emits the expected contexts.

Final ruleset readback after merge:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 \
  --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' \
  > /private/tmp/slice-19-ruleset-post-merge.json
jq -e '
  .id == 17656807
  and .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and ([.rules[] | select(.type == "required_status_checks")] | length == 1)
  and ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy) == true
' /private/tmp/slice-19-ruleset-post-merge.json
```

Exit status: 0

Ruleset summary:

```text
id=17656807
name=Main
target=branch
enforcement=active
strict_required_status_checks_policy=true
required_status_checks:
- Host tests and benchmark gate
- iOS cross-target compile
- WASM cross-target observation
```

## Hosted Docs-Only PR Proof

Docs-only proof PR: #21
`https://github.com/maldrakar/swift-text-engine/pull/21`

Proof branch/head:

```text
branch=slice-19-docs-only-proof
head_sha=105d7562eb488649fb6f4bfa7af2a62180bd7a14
```

The proof commit changed only:

```text
docs/superpowers/verification/2026-06-16-trusted-docs-only-gate-docs-only-proof.md
```

Command:

```bash
gh pr view 21 --json number,url,headRefName,headRefOid \
  > /private/tmp/slice-19-docs-proof-pr.json
cat /private/tmp/slice-19-docs-proof-pr.json
proof_head_sha="$(jq -r '.headRefOid' /private/tmp/slice-19-docs-proof-pr.json)"
gh run list --workflow "Swift CI" --branch slice-19-docs-only-proof --limit 10 \
  --json databaseId,headSha,status,conclusion,url \
  > /private/tmp/slice-19-docs-proof-runs.json
cat /private/tmp/slice-19-docs-proof-runs.json
jq -r --arg sha "$proof_head_sha" \
  '.[] | select(.headSha == $sha) | .databaseId' \
  /private/tmp/slice-19-docs-proof-runs.json \
  | sed -n '1p' \
  > /private/tmp/slice-19-docs-proof-run-id.txt
cat /private/tmp/slice-19-docs-proof-run-id.txt
test -s /private/tmp/slice-19-docs-proof-run-id.txt
proof_run_id="$(cat /private/tmp/slice-19-docs-proof-run-id.txt)"
gh run view "$proof_run_id" --json jobs \
  --jq '[.jobs[] | {name,status,conclusion}]' \
  > /private/tmp/slice-19-docs-proof-jobs.json
cat /private/tmp/slice-19-docs-proof-jobs.json
jq -e '
  ([.[].name] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and all(.[]; .status == "completed" and .conclusion == "success")
' /private/tmp/slice-19-docs-proof-jobs.json
gh run view "$proof_run_id" --log \
  > /private/tmp/slice-19-docs-proof-run.log
rg -n "mode=docs_only_pr job=host-tests-and-benchmark-gate result=success|mode=docs_only_pr job=ios-cross-target-compile result=success|mode=docs_only_pr job=wasm-cross-target-observation result=success" \
  /private/tmp/slice-19-docs-proof-run.log
set +e
rg -n "Run host tests|Run synthetic benchmark gate|Compile TextEngineCore for iOS targets|Observe TextEngineCore for WASM targets" \
  /private/tmp/slice-19-docs-proof-run.log \
  > /private/tmp/slice-19-docs-proof-heavy-lines.txt
heavy_status=$?
set -e
cat /private/tmp/slice-19-docs-proof-heavy-lines.txt
echo "heavy_status=${heavy_status}"
test "$heavy_status" -eq 1
```

Exit status: 0

Run evidence:

```text
run_id=27652778010
url=https://github.com/maldrakar/swift-text-engine/actions/runs/27652778010
head_sha=105d7562eb488649fb6f4bfa7af2a62180bd7a14
jobs=[{"conclusion":"success","name":"Host tests and benchmark gate","status":"completed"},{"conclusion":"success","name":"iOS cross-target compile","status":"completed"},{"conclusion":"success","name":"WASM cross-target observation","status":"completed"}]
```

Docs-only success log lines:

```text
242:Host tests and benchmark gate	Complete docs-only PR	2026-06-16T22:39:02.3131870Z mode=docs_only_pr job=host-tests-and-benchmark-gate result=success
436:iOS cross-target compile	Complete docs-only PR	2026-06-16T22:38:35.7013380Z mode=docs_only_pr job=ios-cross-target-compile result=success
694:WASM cross-target observation	Complete docs-only PR	2026-06-16T22:39:04.2162676Z mode=docs_only_pr job=wasm-cross-target-observation result=success
```

Heavy Swift/test/compile proof:

```text
/private/tmp/slice-19-docs-proof-heavy-lines.txt: 0 bytes
heavy_status=1
```

The docs-only PR run printed all three `mode=docs_only_pr ... result=success`
markers, emitted the same required job contexts, and did not run the heavy
Swift/test/compile steps.
