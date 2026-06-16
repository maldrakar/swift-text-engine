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
run_id=27650996068
pr=20
head_sha=a553f1e66f42aa8f347487e7e364e23a5bdb748f
jobs=[{"conclusion":"success","name":"WASM cross-target observation","status":"completed"},{"conclusion":"success","name":"iOS cross-target compile","status":"completed"},{"conclusion":"success","name":"Host tests and benchmark gate","status":"completed"}]
heavy_path_lines=WASM cross-target observation	Observe TextEngineCore for WASM targets	﻿2026-06-16T22:01:42.0415301Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets wasm;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:01:42.0415846Z ^[[36;1m./.github/scripts/cross-target-compile.sh --targets wasm^[[0m;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:01:42.0416321Z shell: sh -e {0};WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:01:42.0416541Z ##[endgroup];WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:01:42.1672634Z cross_target_swift_version=6.2.1;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:01:42.1673538Z mode=cross_target_compile target=ios_device result=skipped reason=not_requested blocking=false;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:01:42.1674444Z mode=cross_target_compile target=ios_simulator result=skipped reason=not_requested blocking=false;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:01:42.3324247Z mode=cross_target_compile target=wasm result=skipped reason=sdk_unavailable blocking=false;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:01:42.4921130Z mode=cross_target_compile target=wasm_embedded result=skipped reason=sdk_unavailable blocking=false;WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-16T22:01:42.4927523Z mode=cross_target_compile_summary ios_device=skipped ios_simulator=skipped wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0;iOS cross-target compile	Compile TextEngineCore for iOS targets	﻿2026-06-16T22:02:35.0067150Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets ios;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:35.0067560Z ^[[36;1m./.github/scripts/cross-target-compile.sh --targets ios^[[0m;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:35.0094200Z shell: /bin/bash -e {0};iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:35.0094380Z ##[endgroup];iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:35.2209450Z cross_target_swift_version=6.1.2;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:35.2209930Z cross_target_developer_dir=unset;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:35.2240960Z cross_target_xcode_select_path=/Applications/Xcode_16.4.app/Contents/Developer;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:35.2614780Z cross_target_xcodebuild_version=Xcode 16.4;Build version 16F6;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:35.9393290Z cross_target_iphoneos_sdk_path=/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.5.sdk;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:36.2769690Z cross_target_iphoneos_sdk_version=18.5;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:36.9375800Z cross_target_iphonesimulator_sdk_path=/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator18.5.sdk;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:37.2705530Z cross_target_iphonesimulator_sdk_version=18.5;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:47.3211430Z cross_target_command target=ios_device cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS'";iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:51.4797120Z mode=cross_target_compile target=ios_device result=pass reason=none blocking=true;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:51.4821640Z cross_target_command target=ios_simulator cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator'";iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:54.6026400Z mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:54.6029360Z mode=cross_target_compile target=wasm result=skipped reason=not_requested blocking=false;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:54.6034810Z mode=cross_target_compile target=wasm_embedded result=skipped reason=not_requested blocking=false;iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-16T22:02:54.6087270Z mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0;Host tests and benchmark gate	Run host tests	﻿2026-06-16T22:01:43.2704492Z ##[group]Run swift test --scratch-path /tmp/text-engine-host-build;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:43.2705012Z ^[[36;1mswift test --scratch-path /tmp/text-engine-host-build^[[0m;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:43.2705462Z shell: sh -e {0};Host tests and benchmark gate	Run host tests	2026-06-16T22:01:43.2705681Z ##[endgroup];Host tests and benchmark gate	Run host tests	2026-06-16T22:01:43.8322720Z Building for debugging...;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:43.8385481Z [0/21] Write sources;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:43.8916388Z [5/21] Write swift-version-24593BA9C3E375BF.txt;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.6774973Z [7/28] Compiling TextEngineCore LineGeometryCursor.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.6776237Z [8/28] Compiling TextEngineCore LineMetricsSource.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.6777547Z [9/28] Emitting module TextEngineCore;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.6778315Z [10/28] Compiling TextEngineCore DocumentLineCursor.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.6779212Z [11/28] Compiling TextEngineCore DocumentLineTypes.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.6779967Z [12/28] Compiling TextEngineCore VariableLineGeometryCursor.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.6780759Z [13/28] Compiling TextEngineCore VariableViewportVirtualizer.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.8822833Z [14/30] Compiling TextEngineCore ViewportTypes.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.8823347Z [15/30] Compiling TextEngineCore ViewportVirtualizer.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:46.9550158Z [16/34] Wrapping AST for TextEngineCore for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:47.0083888Z [18/46] Emitting module TextEngineReferenceProviders;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:47.0857860Z [19/46] Compiling TextEngineReferenceProviders PrefixSumLineMetrics.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:47.1283738Z [20/46] Compiling TextEngineReferenceProviders FenwickLineMetrics.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:47.2054475Z [21/47] Wrapping AST for TextEngineReferenceProviders for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:48.8760911Z [23/59] Emitting module TextEngineCoreTests;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7028573Z [24/62] Compiling ViewportBenchmarks RealisticProviderBenchmark.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7030195Z [25/62] Compiling ViewportBenchmarks SyntheticBenchmarks.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7031447Z [26/62] Compiling ViewportBenchmarks VariableHeightBenchmark.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7037741Z [27/62] Compiling ViewportBenchmarks BenchmarkSupport.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7038641Z [28/62] Compiling ViewportBenchmarks MemoryObservationDiagnostics.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7039576Z [29/62] Compiling ViewportBenchmarks MemoryShapeDiagnostics.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7140310Z [30/64] Emitting module ViewportBenchmarks;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7146302Z [31/64] Compiling ViewportBenchmarks BenchmarkModels.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7147987Z [32/64] Compiling ViewportBenchmarks BenchmarkOptions.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:49.7149315Z [33/64] Compiling ViewportBenchmarks BenchmarkProgram.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:50.3584698Z [34/64] Compiling ViewportBenchmarks VariableHeightMutationBenchmark.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:50.3591442Z [35/64] Compiling ViewportBenchmarks main.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:50.5278132Z [36/65] Wrapping AST for ViewportBenchmarks for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:50.5284478Z [37/65] Write Objects.LinkFileList;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:50.8072328Z [38/65] Linking ViewportBenchmarks;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:50.9035459Z [40/65] Compiling TextEngineCoreTests ViewportOverscanInvariantTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:50.9037351Z [41/65] Compiling TextEngineCoreTests ViewportRangeTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:50.9038733Z [42/65] Compiling TextEngineCoreTests ViewportValidationTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:51.0334280Z [46/65] Compiling TextEngineReferenceProvidersTests FenwickLineMetricsTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:51.0351929Z [47/65] Emitting module TextEngineReferenceProvidersTests;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:51.1155794Z [56/67] Wrapping AST for TextEngineReferenceProvidersTests for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:51.1391272Z [58/67] /tmp/text-engine-host-build/x86_64-unknown-linux-gnu/debug/SwiftTextEnginePackageDiscoveredTests.derived/all-discovered-tests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:51.1417243Z [59/67] Write sources;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:51.1655378Z [60/67] Wrapping AST for TextEngineCoreTests for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:52.6918914Z [62/71] Compiling SwiftTextEnginePackageDiscoveredTests TextEngineReferenceProvidersTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:52.6920524Z [63/71] Compiling SwiftTextEnginePackageDiscoveredTests TextEngineCoreTests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:52.6922671Z [64/71] Compiling SwiftTextEnginePackageDiscoveredTests all-discovered-tests.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:52.6923771Z [65/71] Emitting module SwiftTextEnginePackageDiscoveredTests;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:52.7281868Z [66/72] /tmp/text-engine-host-build/x86_64-unknown-linux-gnu/debug/SwiftTextEnginePackageTests.derived/runner.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:52.7288553Z [67/72] Write sources;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:52.7672906Z [68/72] Wrapping AST for SwiftTextEnginePackageDiscoveredTests for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:55.5661476Z [70/74] Emitting module SwiftTextEnginePackageTests;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:55.5662234Z [71/74] Compiling SwiftTextEnginePackageTests runner.swift;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:55.6359249Z [72/75] Wrapping AST for SwiftTextEnginePackageTests for debugging;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:55.6359982Z [73/75] Write Objects.LinkFileList;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:55.7637508Z [74/75] Linking SwiftTextEnginePackageTests.xctest;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:55.7661619Z Build complete! (11.99s);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1886922Z Test Suite 'All tests' started at 2026-06-16 22:01:55.775;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1887676Z Test Suite 'debug.xctest' started at 2026-06-16 22:01:55.776;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1888441Z Test Suite 'FenwickLineMetricsTests' started at 2026-06-16 22:01:55.776;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1889883Z Test Case 'FenwickLineMetricsTests.testMutationKeepsOffsetsEqualToFreshOracle' started at 2026-06-16 22:01:55.776;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1891331Z Test Case 'FenwickLineMetricsTests.testMutationKeepsOffsetsEqualToFreshOracle' passed (0.001 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1892990Z Test Case 'FenwickLineMetricsTests.testOffsetMatchesPrefixSumOracleOnBuild' started at 2026-06-16 22:01:55.777;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1894471Z Test Case 'FenwickLineMetricsTests.testOffsetMatchesPrefixSumOracleOnBuild' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1895718Z Test Case 'FenwickLineMetricsTests.testOffsetsStrictlyIncreasingAfterMutation' started at 2026-06-16 22:01:55.777;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1897153Z Test Case 'FenwickLineMetricsTests.testOffsetsStrictlyIncreasingAfterMutation' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1898448Z Test Case 'FenwickLineMetricsTests.testPrefixQueryWalkBoundIsLogarithmic' started at 2026-06-16 22:01:55.778;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1899815Z Test Case 'FenwickLineMetricsTests.testPrefixQueryWalkBoundIsLogarithmic' passed (0.143 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1901097Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationMatchesFreshOracle' started at 2026-06-16 22:01:55.921;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1902661Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationMatchesFreshOracle' passed (0.002 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1904386Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationUsesLogarithmicCoreQueries' started at 2026-06-16 22:01:55.923;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1905319Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationUsesLogarithmicCoreQueries' passed (0.077 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1906174Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountExactForKnownSmallCases' started at 2026-06-16 22:01:56.000;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1907216Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountExactForKnownSmallCases' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1908381Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountIsLogarithmicAcrossSizes' started at 2026-06-16 22:01:56.000;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1909212Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountIsLogarithmicAcrossSizes' passed (0.085 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1909849Z Test Suite 'FenwickLineMetricsTests' passed at 2026-06-16 22:01:56.086;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1910326Z 	 Executed 8 tests, with 0 failures (0 unexpected) in 0.31 (0.31) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1910800Z Test Suite 'DocumentLineCursorTests' started at 2026-06-16 22:01:56.086;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1911456Z Test Case 'DocumentLineCursorTests.testCursorFetchesOneLinePerBufferedIndex' started at 2026-06-16 22:01:56.086;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1912249Z Test Case 'DocumentLineCursorTests.testCursorFetchesOneLinePerBufferedIndex' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1913656Z Test Case 'DocumentLineCursorTests.testCursorReportsMissingIndexesWithoutClampingRange' started at 2026-06-16 22:01:56.086;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1915182Z Test Case 'DocumentLineCursorTests.testCursorReportsMissingIndexesWithoutClampingRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1916887Z Test Case 'DocumentLineCursorTests.testCursorYieldsBufferedRangeLinesInOrder' started at 2026-06-16 22:01:56.086;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1918393Z Test Case 'DocumentLineCursorTests.testCursorYieldsBufferedRangeLinesInOrder' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1920109Z Test Case 'DocumentLineCursorTests.testCursorYieldsNothingForEmptyRangeAndDoesNotFetch' started at 2026-06-16 22:01:56.086;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1921879Z Test Case 'DocumentLineCursorTests.testCursorYieldsNothingForEmptyRangeAndDoesNotFetch' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1923487Z Test Case 'DocumentLineCursorTests.testGeneratedRangesFetchOnlyBufferedIndexes' started at 2026-06-16 22:01:56.087;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1924814Z Test Case 'DocumentLineCursorTests.testGeneratedRangesFetchOnlyBufferedIndexes' passed (0.101 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1926443Z Test Case 'DocumentLineCursorTests.testViewportComputationDoesNotFetchProviderLines' started at 2026-06-16 22:01:56.187;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1928127Z Test Case 'DocumentLineCursorTests.testViewportComputationDoesNotFetchProviderLines' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1929332Z Test Suite 'DocumentLineCursorTests' passed at 2026-06-16 22:01:56.188;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1930185Z 	 Executed 6 tests, with 0 failures (0 unexpected) in 0.102 (0.102) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1931034Z Test Suite 'DocumentLineValueTests' started at 2026-06-16 22:01:56.188;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1932254Z Test Case 'DocumentLineValueTests.testDocumentLineCursorElementEquatableWhenPayloadIsEquatable' started at 2026-06-16 22:01:56.188;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1934016Z Test Case 'DocumentLineValueTests.testDocumentLineCursorElementEquatableWhenPayloadIsEquatable' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1935546Z Test Case 'DocumentLineValueTests.testDocumentLineEquatableWhenPayloadIsEquatable' started at 2026-06-16 22:01:56.188;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1937056Z Test Case 'DocumentLineValueTests.testDocumentLineEquatableWhenPayloadIsEquatable' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1938350Z Test Case 'DocumentLineValueTests.testDocumentLineFetchEquatableWhenPayloadIsEquatable' started at 2026-06-16 22:01:56.188;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1940150Z Test Case 'DocumentLineValueTests.testDocumentLineFetchEquatableWhenPayloadIsEquatable' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1941752Z Test Case 'DocumentLineValueTests.testDocumentLineStoresIndexAndContent' started at 2026-06-16 22:01:56.188;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1943134Z Test Case 'DocumentLineValueTests.testDocumentLineStoresIndexAndContent' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1944200Z Test Suite 'DocumentLineValueTests' passed at 2026-06-16 22:01:56.188;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1945024Z 	 Executed 4 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1945902Z Test Suite 'LineGeometryCursorTests' started at 2026-06-16 22:01:56.188;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1947166Z Test Case 'LineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' started at 2026-06-16 22:01:56.188;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1948158Z Test Case 'LineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1948910Z Test Case 'LineGeometryCursorTests.testCursorYieldsOnlyBufferedLines' started at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1949630Z Test Case 'LineGeometryCursorTests.testCursorYieldsOnlyBufferedLines' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1950212Z Test Suite 'LineGeometryCursorTests' passed at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1950660Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1951102Z Test Suite 'LineMetricsSourceTests' started at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1951710Z Test Case 'LineMetricsSourceTests.testUniformLineMetricsOffsetIsLinear' started at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1952556Z Test Case 'LineMetricsSourceTests.testUniformLineMetricsOffsetIsLinear' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1953128Z Test Suite 'LineMetricsSourceTests' passed at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1953556Z 	 Executed 1 test, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1954017Z Test Suite 'VariableHeightQueryCountTests' started at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1955016Z Test Case 'VariableHeightQueryCountTests.testComputeClampAtDocumentEndDoesNotSearchMidDocumentOffsets' started at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1956866Z Test Case 'VariableHeightQueryCountTests.testComputeClampAtDocumentEndDoesNotSearchMidDocumentOffsets' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1958408Z Test Case 'VariableHeightQueryCountTests.testComputeEmptyDocumentQueriesOnlyFirstOffset' started at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1959687Z Test Case 'VariableHeightQueryCountTests.testComputeEmptyDocumentQueriesOnlyFirstOffset' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1961030Z Test Case 'VariableHeightQueryCountTests.testComputeSingleLineStaysBounded' started at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1962254Z Test Case 'VariableHeightQueryCountTests.testComputeSingleLineStaysBounded' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1963611Z Test Case 'VariableHeightQueryCountTests.testComputeUsesLogarithmicQueriesAtOneMillionLines' started at 2026-06-16 22:01:56.189;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1965135Z Test Case 'VariableHeightQueryCountTests.testComputeUsesLogarithmicQueriesAtOneMillionLines' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1966870Z Test Case 'VariableHeightQueryCountTests.testEmptyGeometryCursorDoesNotSeedOffsetQuery' started at 2026-06-16 22:01:56.190;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1968573Z Test Case 'VariableHeightQueryCountTests.testEmptyGeometryCursorDoesNotSeedOffsetQuery' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1970396Z Test Case 'VariableHeightQueryCountTests.testNonEmptyGeometryCursorQueriesSeedPlusOnePerBufferedLine' started at 2026-06-16 22:01:56.190;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1972306Z Test Case 'VariableHeightQueryCountTests.testNonEmptyGeometryCursorQueriesSeedPlusOnePerBufferedLine' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1973280Z Test Suite 'VariableHeightQueryCountTests' passed at 2026-06-16 22:01:56.190;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1974131Z 	 Executed 6 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1974876Z Test Suite 'VariableLineGeometryCursorTests' started at 2026-06-16 22:01:56.190;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1975987Z Test Case 'VariableLineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' started at 2026-06-16 22:01:56.190;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1977759Z Test Case 'VariableLineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1978889Z Test Case 'VariableLineGeometryCursorTests.testCursorYieldsBufferedLineGeometry' started at 2026-06-16 22:01:56.190;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1979981Z Test Case 'VariableLineGeometryCursorTests.testCursorYieldsBufferedLineGeometry' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1980893Z Test Suite 'VariableLineGeometryCursorTests' passed at 2026-06-16 22:01:56.190;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1981666Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1982156Z Test Suite 'VariableUniformEquivalenceTests' started at 2026-06-16 22:01:56.190;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1982925Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedAcrossRepresentableHeights' started at 2026-06-16 22:01:56.190;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1984226Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedAcrossRepresentableHeights' passed (0.001 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1985750Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedForIntMaxClamp' started at 2026-06-16 22:01:56.191;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1987322Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedForIntMaxClamp' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1988418Z Test Suite 'VariableUniformEquivalenceTests' passed at 2026-06-16 22:01:56.192;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1989451Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1990285Z Test Suite 'VariableViewportComputeTests' started at 2026-06-16 22:01:56.192;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1991453Z Test Case 'VariableViewportComputeTests.testEmptyDocumentReturnsEmptyRange' started at 2026-06-16 22:01:56.192;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1992893Z Test Case 'VariableViewportComputeTests.testEmptyDocumentReturnsEmptyRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1994404Z Test Case 'VariableViewportComputeTests.testEmptyDocumentStillValidatesFirstOffset' started at 2026-06-16 22:01:56.192;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1995936Z Test Case 'VariableViewportComputeTests.testEmptyDocumentStillValidatesFirstOffset' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1996986Z Test Case 'VariableViewportComputeTests.testNegativeLineCountFails' started at 2026-06-16 22:01:56.192;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1997695Z Test Case 'VariableViewportComputeTests.testNegativeLineCountFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1998389Z Test Case 'VariableViewportComputeTests.testNegativeOverscanFails' started at 2026-06-16 22:01:56.192;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1999066Z Test Case 'VariableViewportComputeTests.testNegativeOverscanFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.1999781Z Test Case 'VariableViewportComputeTests.testNegativeViewportHeightFails' started at 2026-06-16 22:01:56.192;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2000527Z Test Case 'VariableViewportComputeTests.testNegativeViewportHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2001412Z Test Case 'VariableViewportComputeTests.testNonFiniteScrollOffsetFails' started at 2026-06-16 22:01:56.192;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2002225Z Test Case 'VariableViewportComputeTests.testNonFiniteScrollOffsetFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2002957Z Test Case 'VariableViewportComputeTests.testNonFiniteTotalHeightFails' started at 2026-06-16 22:01:56.192;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2003679Z Test Case 'VariableViewportComputeTests.testNonFiniteTotalHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2004428Z Test Case 'VariableViewportComputeTests.testNonFiniteViewportHeightFails' started at 2026-06-16 22:01:56.193;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2005202Z Test Case 'VariableViewportComputeTests.testNonFiniteViewportHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2005963Z Test Case 'VariableViewportComputeTests.testNonPositiveTotalHeightFails' started at 2026-06-16 22:01:56.193;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2006942Z Test Case 'VariableViewportComputeTests.testNonPositiveTotalHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2007672Z Test Case 'VariableViewportComputeTests.testNonUniformVisibleRange' started at 2026-06-16 22:01:56.193;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2008369Z Test Case 'VariableViewportComputeTests.testNonUniformVisibleRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2009059Z Test Case 'VariableViewportComputeTests.testNonUniformWithOverscan' started at 2026-06-16 22:01:56.193;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2009741Z Test Case 'VariableViewportComputeTests.testNonUniformWithOverscan' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2010432Z Test Case 'VariableViewportComputeTests.testNonZeroFirstOffsetFails' started at 2026-06-16 22:01:56.193;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2011128Z Test Case 'VariableViewportComputeTests.testNonZeroFirstOffsetFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2012135Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportAtDocumentEndClampsToLineCount' started at 2026-06-16 22:01:56.193;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2013099Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportAtDocumentEndClampsToLineCount' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2014009Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportExactLineTopIsEmpty' started at 2026-06-16 22:01:56.193;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2014888Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportExactLineTopIsEmpty' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2015749Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportMidLineKeepsCrossedLine' started at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2016893Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportMidLineKeepsCrossedLine' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2017706Z Test Suite 'VariableViewportComputeTests' passed at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2018195Z 	 Executed 15 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2018698Z Test Suite 'VariableViewportInputValueTests' started at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2019395Z Test Case 'VariableViewportInputValueTests.testInvalidLineMetricsErrorIsDistinct' started at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2020227Z Test Case 'VariableViewportInputValueTests.testInvalidLineMetricsErrorIsDistinct' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2021056Z Test Case 'VariableViewportInputValueTests.testVariableViewportInputStoresFields' started at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2021878Z Test Case 'VariableViewportInputValueTests.testVariableViewportInputStoresFields' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2022531Z Test Suite 'VariableViewportInputValueTests' passed at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2023022Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2023464Z Test Suite 'ViewportInputValueTests' started at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2024185Z Test Case 'ViewportInputValueTests.testLineGeometryStoresIndexAndDimensions' started at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2024974Z Test Case 'ViewportInputValueTests.testLineGeometryStoresIndexAndDimensions' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2025716Z Test Case 'ViewportInputValueTests.testViewportInputStoresAllFields' started at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2026413Z Test Case 'ViewportInputValueTests.testViewportInputStoresAllFields' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2027323Z Test Case 'ViewportInputValueTests.testVirtualRangeReportsEmpty' started at 2026-06-16 22:01:56.194;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2027984Z Test Case 'ViewportInputValueTests.testVirtualRangeReportsEmpty' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2028532Z Test Suite 'ViewportInputValueTests' passed at 2026-06-16 22:01:56.195;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2028970Z 	 Executed 3 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2029440Z Test Suite 'ViewportOverscanInvariantTests' started at 2026-06-16 22:01:56.195;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2030098Z Test Case 'ViewportOverscanInvariantTests.testGeneratedInputsStayInBounds' started at 2026-06-16 22:01:56.195;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2030862Z Test Case 'ViewportOverscanInvariantTests.testGeneratedInputsStayInBounds' passed (0.001 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2031713Z Test Case 'ViewportOverscanInvariantTests.testOverscanBeforeClampsToZeroWithIntegerMath' started at 2026-06-16 22:01:56.195;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2032622Z Test Case 'ViewportOverscanInvariantTests.testOverscanBeforeClampsToZeroWithIntegerMath' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2033461Z Test Case 'ViewportOverscanInvariantTests.testOverscanClampsAtTopAndBottom' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2034227Z Test Case 'ViewportOverscanInvariantTests.testOverscanClampsAtTopAndBottom' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2034996Z Test Case 'ViewportOverscanInvariantTests.testOverscanExpandsBufferedRange' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2035893Z Test Case 'ViewportOverscanInvariantTests.testOverscanExpandsBufferedRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2036937Z Test Case 'ViewportOverscanInvariantTests.testOverscanPreservesPrecisionNearIntMax' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2037796Z Test Case 'ViewportOverscanInvariantTests.testOverscanPreservesPrecisionNearIntMax' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2038576Z Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2039254Z 	 Executed 5 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2039838Z Test Suite 'ViewportRangeTests' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2040509Z Test Case 'ViewportRangeTests.testFiniteExtremeOffsetClampsIndexBeforeIntConversion' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2041525Z Test Case 'ViewportRangeTests.testFiniteExtremeOffsetClampsIndexBeforeIntConversion' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2042416Z Test Case 'ViewportRangeTests.testFractionalLineHeightEndBoundaryDoesNotIncludeNextLine' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2043328Z Test Case 'ViewportRangeTests.testFractionalLineHeightEndBoundaryDoesNotIncludeNextLine' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2044210Z Test Case 'ViewportRangeTests.testFractionalLineHeightStartBoundaryBeginsAtExactLine' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2045079Z Test Case 'ViewportRangeTests.testFractionalLineHeightStartBoundaryBeginsAtExactLine' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2045964Z Test Case 'ViewportRangeTests.testFractionalLineHeightSublineOffsetIncludesPartialLines' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2047113Z Test Case 'ViewportRangeTests.testFractionalLineHeightSublineOffsetIncludesPartialLines' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2047982Z Test Case 'ViewportRangeTests.testLargeEndPartialLineDoesNotSnapDownToBoundary' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2048798Z Test Case 'ViewportRangeTests.testLargeEndPartialLineDoesNotSnapDownToBoundary' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2049599Z Test Case 'ViewportRangeTests.testLargeFractionalOffsetDoesNotSnapToBoundary' started at 2026-06-16 22:01:56.196;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2050402Z Test Case 'ViewportRangeTests.testLargeFractionalOffsetDoesNotSnapToBoundary' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2125868Z Test Case 'ViewportRangeTests.testLargeStartPartialLineDoesNotSnapUpToBoundary' started at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2127308Z Test Case 'ViewportRangeTests.testLargeStartPartialLineDoesNotSnapUpToBoundary' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2128094Z Test Case 'ViewportRangeTests.testNegativeScrollOffsetClampsToTop' started at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2128809Z Test Case 'ViewportRangeTests.testNegativeScrollOffsetClampsToTop' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2129565Z Test Case 'ViewportRangeTests.testSublineOffsetUsesFloorForStartAndCeilForEnd' started at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2130372Z Test Case 'ViewportRangeTests.testSublineOffsetUsesFloorForStartAndCeilForEnd' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2131190Z Test Case 'ViewportRangeTests.testViewportLargerThanDocumentReturnsWholeDocument' started at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2132029Z Test Case 'ViewportRangeTests.testViewportLargerThanDocumentReturnsWholeDocument' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2132854Z Test Case 'ViewportRangeTests.testZeroHeightViewportProducesEmptyRangeAtOffset' started at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2133686Z Test Case 'ViewportRangeTests.testZeroHeightViewportProducesEmptyRangeAtOffset' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2134284Z Test Suite 'ViewportRangeTests' passed at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2134737Z 	 Executed 11 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2135207Z Test Suite 'ViewportValidationTests' started at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2135997Z Test Case 'ViewportValidationTests.testEmptyDocumentReturnsEmptyRange' started at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2137123Z Test Case 'ViewportValidationTests.testEmptyDocumentReturnsEmptyRange' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2137833Z Test Case 'ViewportValidationTests.testNegativeLineCountFails' started at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2138475Z Test Case 'ViewportValidationTests.testNegativeLineCountFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2139112Z Test Case 'ViewportValidationTests.testNegativeOverscanFails' started at 2026-06-16 22:01:56.197;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2139741Z Test Case 'ViewportValidationTests.testNegativeOverscanFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2140403Z Test Case 'ViewportValidationTests.testNegativeViewportHeightFails' started at 2026-06-16 22:01:56.198;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2141312Z Test Case 'ViewportValidationTests.testNegativeViewportHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2141987Z Test Case 'ViewportValidationTests.testNonFiniteLineHeightFails' started at 2026-06-16 22:01:56.198;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2142650Z Test Case 'ViewportValidationTests.testNonFiniteLineHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2143315Z Test Case 'ViewportValidationTests.testNonFiniteScrollOffsetYFails' started at 2026-06-16 22:01:56.198;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2143993Z Test Case 'ViewportValidationTests.testNonFiniteScrollOffsetYFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2144688Z Test Case 'ViewportValidationTests.testNonFiniteViewportHeightFails' started at 2026-06-16 22:01:56.198;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2145379Z Test Case 'ViewportValidationTests.testNonFiniteViewportHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2146065Z Test Case 'ViewportValidationTests.testNonPositiveLineHeightFails' started at 2026-06-16 22:01:56.198;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2147084Z Test Case 'ViewportValidationTests.testNonPositiveLineHeightFails' passed (0.0 seconds);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2147653Z Test Suite 'ViewportValidationTests' passed at 2026-06-16 22:01:56.198;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2148119Z 	 Executed 8 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2148543Z Test Suite 'debug.xctest' passed at 2026-06-16 22:01:56.198;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2148952Z 	 Executed 75 tests, with 0 failures (0 unexpected) in 0.421 (0.421) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2149371Z Test Suite 'All tests' passed at 2026-06-16 22:01:56.198;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2149767Z 	 Executed 75 tests, with 0 failures (0 unexpected) in 0.421 (0.421) seconds;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2150348Z ◇ Test run started.;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2150665Z ↳ Testing Library Version: 6.2.1 (c9d57c83568b06d);Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2151035Z ↳ Target Platform: x86_64-unknown-linux-gnu;Host tests and benchmark gate	Run host tests	2026-06-16T22:01:56.2151500Z ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.;Host tests and benchmark gate	Run synthetic benchmark gate	﻿2026-06-16T22:01:56.2233266Z ##[group]Run swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:01:56.2234189Z ^[[36;1mswift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate^[[0m;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:01:56.2234790Z shell: sh -e {0};Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:01:56.2234995Z ##[endgroup];Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:01:56.7504045Z Building for production...;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:01:56.7533304Z [0/6] Write sources;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:01:56.8069442Z [3/6] Write swift-version-24593BA9C3E375BF.txt;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:01:57.3008208Z [5/7] Compiling TextEngineCore DocumentLineCursor.swift;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:01:57.5690712Z [6/8] Compiling TextEngineReferenceProviders FenwickLineMetrics.swift;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:02:00.8333160Z [7/9] Compiling ViewportBenchmarks BenchmarkModels.swift;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:02:00.8376799Z [7/9] Write Objects.LinkFileList;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:02:00.9286195Z [8/9] Linking ViewportBenchmarks;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:02:00.9308423Z Build of product 'ViewportBenchmarks' complete! (4.22s);Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:03:59.3798215Z mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=2475 p99_ns=2680 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:03:59.3803353Z mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=10369 p99_ns=10735 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200;Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-16T22:03:59.3806127Z mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=33739 p99_ns=34438 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000;
```

The PR-head run is intentionally non-doc and must not take the docs-only shortcut.

## Post-Merge Push Proof

Post-merge push proof is not available before the branch is merged to `main`
and the default-branch push Swift CI run completes.

Expected proof after merge: the post-merge `push` run records the trusted gate
changes on `main` and confirms the required Swift CI job topology still emits
the expected contexts.

## Hosted Docs-Only PR Proof

Hosted docs-only PR proof is not available before a docs-only PR run completes
with the trusted base detector path.

Expected proof after push/PR: a docs-only PR run prints
`mode=docs_only_pr ... result=success`, executes the detector from the trusted
base worktree, and emits the same required job contexts without running the
heavy Swift/test/compile work.
