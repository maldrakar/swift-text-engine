# Policy-Sensitive Markdown Path Hardening Verification

Date: 2026-06-17

## Scope

Slice 20 hardens `.github/scripts/detect-docs-only-pr.sh` so Markdown files
under `.github/workflows/**` and `.github/scripts/**` are classified as non-doc
before the generic Markdown allow rule. The slice also clarifies `AGENTS.md`.

No Swift source, tests, package metadata, workflow topology, job names,
benchmark modes, benchmark budgets, or ruleset settings are intentionally
changed.

## Local Red Evidence

### Baseline Detector Self-Test

Command:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-self-test-before.out 2>&1
```

Output:

```text
self_test=pass
```

Status: `0`

### Pre-Change Runtime Policy-Sensitive Markdown Bug

Captured state: before Task 3 classifier fix, from the branch state before
commit `e9f5b8954cdf33a0b454ef728ca254e2bbccc26a`.

Command:

```bash
bash -lc '
set -euo pipefail
repo_root="$PWD"
repo=$(mktemp -d /private/tmp/slice-20-policy-md-before.XXXXXX)
cleanup() { rm -rf "$repo"; }
trap cleanup EXIT
script="$repo/detect-docs-only-pr-before-e9f5b895.sh"
git -C "$repo_root" show e9f5b8954cdf33a0b454ef728ca254e2bbccc26a^:.github/scripts/detect-docs-only-pr.sh > "$script"
chmod +x "$script"
cd "$repo"
git init -q
git config user.name "Slice 20 Test"
git config user.email "slice20@example.invalid"
mkdir -p docs
printf "base\n" > docs/base.md
git add docs/base.md
git commit -q -m base
base_sha=$(git rev-parse HEAD)
git checkout -q -B policy-md "$base_sha"
mkdir -p .github/workflows .github/scripts
printf "workflow docs\n" > .github/workflows/README.md
printf "script docs\n" > .github/scripts/README.md
git add .github/workflows/README.md .github/scripts/README.md
git commit -q -m policy-md
head_sha=$(git rev-parse HEAD)
set +e
output=$(bash "$script" --base "$base_sha" --head "$head_sha" 2>&1)
status=$?
set -e
printf "detector_status=%s\n%s\n" "$status" "$output"
' > /private/tmp/slice-20-policy-md-before.out 2>&1
cat /private/tmp/slice-20-policy-md-before.out
rg -n "detector_status=0" /private/tmp/slice-20-policy-md-before.out
rg -n "result=docs_only docs_only_pr=true file_count=2 non_doc_count=0" /private/tmp/slice-20-policy-md-before.out
```

Output:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

Status: `0`

### Runtime Self-Test Red

Captured state: intermediate uncommitted TDD state after Task 2 runtime test
additions and before Task 3 deny-first classifier fix. Running this command
against current `HEAD` is expected to produce green output, not this red proof.

Command:

```bash
bash -lc '
set +e
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-runtime-red.out 2>&1
status=$?
set -e
cat /private/tmp/slice-20-runtime-red.out
echo "runtime_red_status=${status}"
test "$status" -eq 1
rg -n "self_test=fail label=runtime_workflow_markdown_change_output" /private/tmp/slice-20-runtime-red.out
rg -n "expected_contains=docs_only_pr=false" /private/tmp/slice-20-runtime-red.out
rg -n "docs_only_pr=true" /private/tmp/slice-20-runtime-red.out
'
```

Output:

```text
self_test=fail label=runtime_workflow_markdown_change_output expected_contains=docs_only_pr=false actual=mode=docs_only_pr result=docs_only docs_only_pr=true file_count=1 non_doc_count=0
runtime_red_status=1
```

Reviewed red substrings:

```text
self_test=fail label=runtime_workflow_markdown_change_output
expected_contains=docs_only_pr=false
docs_only_pr=true
```

Detector self-test status: `1`

Verification wrapper status: `0`

### Direct Path Self-Test Red

Captured state: intermediate uncommitted TDD state after adding direct path
assertions and before applying the deny-first classifier fix. Running this
command against current `HEAD` is expected to produce green output, not this red
proof.

Command:

```bash
bash -lc '
set +e
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-direct-red.out 2>&1
status=$?
set -e
cat /private/tmp/slice-20-direct-red.out
echo "direct_red_status=${status}"
test "$status" -eq 1
rg -n "self_test=fail label=workflow_markdown_is_policy_sensitive expected=failure actual=success" /private/tmp/slice-20-direct-red.out
'
```

Output:

```text
self_test=fail label=workflow_markdown_is_policy_sensitive expected=failure actual=success
direct_red_status=1
```

Detector self-test status: `1`

Verification wrapper status: `0`

## Local Green Evidence

### Detector Self-Test

Command:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-final-self-test.out 2>&1
echo "$?" > /private/tmp/slice-20-final-self-test.status
```

Output:

```text
self_test=pass
```

Status: `0`

### Bash Syntax

Command:

```bash
bash -n .github/scripts/detect-docs-only-pr.sh > /private/tmp/slice-20-final-bash-n.out 2>&1
echo "$?" > /private/tmp/slice-20-final-bash-n.status
```

Output:

```text
```

Status: `0`

### Policy-Sensitive Markdown Runtime Classification

Command:

```bash
bash -lc '
set -euo pipefail
repo=$(mktemp -d /private/tmp/slice-20-policy-md-after.XXXXXX)
cleanup() { rm -rf "$repo"; }
trap cleanup EXIT
script="$PWD/.github/scripts/detect-docs-only-pr.sh"
cd "$repo"
git init -q
git config user.name "Slice 20 Test"
git config user.email "slice20@example.invalid"
mkdir -p docs
printf "base\n" > docs/base.md
git add docs/base.md
git commit -q -m base
base_sha=$(git rev-parse HEAD)
git checkout -q -B policy-md "$base_sha"
mkdir -p .github/workflows .github/scripts
printf "workflow docs\n" > .github/workflows/README.md
printf "script docs\n" > .github/scripts/README.md
git add .github/workflows/README.md .github/scripts/README.md
git commit -q -m policy-md
head_sha=$(git rev-parse HEAD)
set +e
output=$(bash "$script" --base "$base_sha" --head "$head_sha" 2>&1)
status=$?
set -e
printf "detector_status=%s\n%s\n" "$status" "$output"
' > /private/tmp/slice-20-policy-md-after.out 2>&1
cat /private/tmp/slice-20-policy-md-after.out
rg -n "detector_status=0" /private/tmp/slice-20-policy-md-after.out
rg -n "result=not_docs_only docs_only_pr=false file_count=2 non_doc_count=2" /private/tmp/slice-20-policy-md-after.out
```

Output:

```text
detector_status=0
mode=docs_only_pr result=not_docs_only docs_only_pr=false file_count=2 non_doc_count=2
```

Status: `0`

### True Docs-Only Runtime Classification

Command:

```bash
bash -lc '
set -euo pipefail
repo=$(mktemp -d /private/tmp/slice-20-docs-md-after.XXXXXX)
cleanup() { rm -rf "$repo"; }
trap cleanup EXIT
script="$PWD/.github/scripts/detect-docs-only-pr.sh"
cd "$repo"
git init -q
git config user.name "Slice 20 Test"
git config user.email "slice20@example.invalid"
mkdir -p docs
printf "base\n" > docs/base.md
git add docs/base.md
git commit -q -m base
base_sha=$(git rev-parse HEAD)
git checkout -q -B docs-only "$base_sha"
printf "root docs\n" > README.md
mkdir -p docs/assets
printf "diagram\n" > docs/assets/diagram.png
git add README.md docs/assets/diagram.png
git commit -q -m docs-only
head_sha=$(git rev-parse HEAD)
set +e
output=$(bash "$script" --base "$base_sha" --head "$head_sha" 2>&1)
status=$?
set -e
printf "detector_status=%s\n%s\n" "$status" "$output"
' > /private/tmp/slice-20-docs-md-after.out 2>&1
cat /private/tmp/slice-20-docs-md-after.out
rg -n "detector_status=0" /private/tmp/slice-20-docs-md-after.out
rg -n "result=docs_only docs_only_pr=true file_count=2 non_doc_count=0" /private/tmp/slice-20-docs-md-after.out
```

Output:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

Status: `0`

### Workflow Shape

Command:

```bash
bash -lc '
set -euo pipefail
workflow=".github/workflows/swift-ci.yml"
pull_request_lines=$(rg -c "^  pull_request:" "$workflow")
push_paths_ignore_lines=$(rg -c "paths-ignore:" "$workflow")
trusted_detector_count=$(rg -c '\''trusted_detector="\$\{trusted_ci_dir\}/\.github/scripts/detect-docs-only-pr\.sh"'\'' "$workflow")
trusted_invoke_count=$(rg -c '\''bash "\$trusted_detector" --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"'\'' "$workflow")
host_job_name_count=$(rg -c "name: Host tests and benchmark gate" "$workflow")
ios_job_name_count=$(rg -c "name: iOS cross-target compile" "$workflow")
wasm_job_name_count=$(rg -c "name: WASM cross-target observation" "$workflow")
if rg '\''^\s+\./\.github/scripts/detect-docs-only-pr\.sh --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"'\'' "$workflow" >/tmp/slice-20-pr-owned-detector-lines.out 2>&1; then
  pr_owned_detector_count=$(wc -l < /tmp/slice-20-pr-owned-detector-lines.out)
else
  pr_owned_detector_count=0
fi
printf "pull_request_lines=%s\n" "$pull_request_lines"
printf "push_paths_ignore_lines=%s\n" "$push_paths_ignore_lines"
printf "trusted_detector_count=%s\n" "$trusted_detector_count"
printf "trusted_invoke_count=%s\n" "$trusted_invoke_count"
printf "host_job_name_count=%s\n" "$host_job_name_count"
printf "ios_job_name_count=%s\n" "$ios_job_name_count"
printf "wasm_job_name_count=%s\n" "$wasm_job_name_count"
printf "pr_owned_detector_count=%s\n" "$pr_owned_detector_count"
test "$pull_request_lines" -eq 1
test "$push_paths_ignore_lines" -eq 1
test "$trusted_detector_count" -eq 3
test "$trusted_invoke_count" -eq 3
test "$host_job_name_count" -eq 1
test "$ios_job_name_count" -eq 1
test "$wasm_job_name_count" -eq 1
test "$pr_owned_detector_count" -eq 0
' > /private/tmp/slice-20-workflow-shape.out 2>&1
echo "$?" > /private/tmp/slice-20-workflow-shape.status
```

Output:

```text
pull_request_lines=1
push_paths_ignore_lines=1
trusted_detector_count=3
trusted_invoke_count=3
host_job_name_count=1
ios_job_name_count=1
wasm_job_name_count=1
pr_owned_detector_count=0
```

Status: `0`

### Foundation-Free Core Scan

Command:

```bash
rg -n "Foundation" Sources/TextEngineCore > /private/tmp/slice-20-foundation-scan.out 2>&1
echo "$?" > /private/tmp/slice-20-foundation-scan.status
```

Output:

```text
```

Status: `1` (`rg` found no matches)

### Swift Source And Package Scope

Command:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift > /private/tmp/slice-20-source-scope-after.out
echo "$?" > /private/tmp/slice-20-source-scope-after.status
```

Output:

```text
```

Status: `0`

### Diff Whitespace

Command:

```bash
git diff --check main...HEAD > /private/tmp/slice-20-diff-check.out 2>&1
echo "$?" > /private/tmp/slice-20-diff-check.status
```

Output:

```text
```

Status: `0`

## Hosted Evidence

### PR-Head Heavy Path

PR: #23
Head SHA: `2bbbe091f4b62104158cfa9b0b2ab31a0c389d0b`
Run: `27703279446`

Run summary:

```text
Swift CI
pull_request
completed
success
2bbbe091f4b62104158cfa9b0b2ab31a0c389d0b
WASM cross-target observation=success
iOS cross-target compile=success
Host tests and benchmark gate=success
```

Heavy path markers found in hosted logs:

```text
WASM cross-target observation	Observe TextEngineCore for WASM targets	﻿2026-06-17T16:16:37.0705322Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets wasm
WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T16:16:37.0705882Z ^[[36;1m./.github/scripts/cross-target-compile.sh --targets wasm^[[0m
WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T16:16:37.0706345Z shell: sh -e {0}
WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T16:16:37.0706556Z ##[endgroup]
WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T16:16:37.1884597Z cross_target_swift_version=6.2.1
WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T16:16:37.1887437Z mode=cross_target_compile target=ios_device result=skipped reason=not_requested blocking=false
WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T16:16:37.1889449Z mode=cross_target_compile target=ios_simulator result=skipped reason=not_requested blocking=false
WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T16:16:37.3449094Z mode=cross_target_compile target=wasm result=skipped reason=sdk_unavailable blocking=false
WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T16:16:37.4977415Z mode=cross_target_compile target=wasm_embedded result=skipped reason=sdk_unavailable blocking=false
WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T16:16:37.4982927Z mode=cross_target_compile_summary ios_device=skipped ios_simulator=skipped wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0
iOS cross-target compile	Compile TextEngineCore for iOS targets	﻿2026-06-17T16:16:07.7122360Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets ios
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:07.7122920Z ^[[36;1m./.github/scripts/cross-target-compile.sh --targets ios^[[0m
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:07.7161150Z shell: /bin/bash -e {0}
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:07.7161500Z ##[endgroup]
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:08.1218170Z cross_target_swift_version=6.1.2
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:08.1218790Z cross_target_developer_dir=unset
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:08.1291680Z cross_target_xcode_select_path=/Applications/Xcode_16.4.app/Contents/Developer
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:08.1920600Z cross_target_xcodebuild_version=Xcode 16.4;Build version 16F6
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:09.4211170Z cross_target_iphoneos_sdk_path=/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.5.sdk
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:10.0094840Z cross_target_iphoneos_sdk_version=18.5
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:11.1083790Z cross_target_iphonesimulator_sdk_path=/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator18.5.sdk
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:11.6439040Z cross_target_iphonesimulator_sdk_version=18.5
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:32.1654650Z cross_target_command target=ios_device cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS'"
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:41.2707130Z mode=cross_target_compile target=ios_device result=pass reason=none blocking=true
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:41.2741270Z cross_target_command target=ios_simulator cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator'"
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:49.5574580Z mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:49.5635790Z mode=cross_target_compile target=wasm result=skipped reason=not_requested blocking=false
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:49.5639150Z mode=cross_target_compile target=wasm_embedded result=skipped reason=not_requested blocking=false
iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T16:16:49.5647570Z mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0
Host tests and benchmark gate	Run host tests	﻿2026-06-17T16:16:30.7117431Z ##[group]Run swift test --scratch-path /tmp/text-engine-host-build
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:30.7117921Z ^[[36;1mswift test --scratch-path /tmp/text-engine-host-build^[[0m
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:30.7118356Z shell: sh -e {0}
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:30.7118565Z ##[endgroup]
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:31.3173268Z Building for debugging...
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:31.3228667Z [0/21] Write sources
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:31.3831194Z [5/21] Write swift-version-24593BA9C3E375BF.txt
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.0556455Z [7/28] Compiling TextEngineCore VariableLineGeometryCursor.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.0557626Z [8/28] Compiling TextEngineCore VariableViewportVirtualizer.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.0867729Z [9/30] Emitting module TextEngineCore
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.0868372Z [10/30] Compiling TextEngineCore DocumentLineCursor.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.0868935Z [11/30] Compiling TextEngineCore DocumentLineTypes.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.0869533Z [12/30] Compiling TextEngineCore LineGeometryCursor.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.0870076Z [13/30] Compiling TextEngineCore LineMetricsSource.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.2586473Z [14/30] Compiling TextEngineCore ViewportTypes.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.2586995Z [15/30] Compiling TextEngineCore ViewportVirtualizer.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.3244910Z [16/31] Wrapping AST for TextEngineCore for debugging
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.4586689Z [18/46] Compiling TextEngineReferenceProviders PrefixSumLineMetrics.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.5381388Z [19/46] Emitting module TextEngineReferenceProviders
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.5382307Z [20/46] Compiling TextEngineReferenceProviders FenwickLineMetrics.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.6136875Z [21/47] Wrapping AST for TextEngineReferenceProviders for debugging
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:34.8313440Z [23/59] Emitting module ViewportBenchmarks
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:35.9640635Z [24/61] Compiling ViewportBenchmarks VariableHeightMutationBenchmark.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:35.9644071Z [25/61] Compiling ViewportBenchmarks main.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:35.9763448Z [26/61] Compiling ViewportBenchmarks BenchmarkSupport.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:35.9765870Z [27/61] Compiling ViewportBenchmarks MemoryObservationDiagnostics.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:35.9796412Z [28/61] Compiling ViewportBenchmarks MemoryShapeDiagnostics.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:36.6947054Z [29/61] Compiling ViewportBenchmarks BenchmarkModels.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:36.6986010Z [30/61] Compiling ViewportBenchmarks BenchmarkOptions.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:36.6987206Z [31/61] Compiling ViewportBenchmarks BenchmarkProgram.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:36.6988631Z [32/61] Compiling ViewportBenchmarks RealisticProviderBenchmark.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:36.6989437Z [33/61] Compiling ViewportBenchmarks SyntheticBenchmarks.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:36.6990065Z [34/61] Compiling ViewportBenchmarks VariableHeightBenchmark.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:36.8911748Z [35/62] Wrapping AST for ViewportBenchmarks for debugging
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:36.8934210Z [36/62] Write Objects.LinkFileList
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.1939356Z [37/62] Linking ViewportBenchmarks
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.5631640Z [46/65] Emitting module TextEngineCoreTests
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.5787806Z [51/65] Compiling TextEngineReferenceProvidersTests FenwickLineMetricsTests.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.5789667Z [52/65] Emitting module TextEngineReferenceProvidersTests
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.6487090Z [53/66] Wrapping AST for TextEngineReferenceProvidersTests for debugging
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.8073910Z [55/66] Compiling TextEngineCoreTests ViewportOverscanInvariantTests.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.8074766Z [56/66] Compiling TextEngineCoreTests ViewportRangeTests.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.8075418Z [57/66] Compiling TextEngineCoreTests ViewportValidationTests.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.8467605Z [58/67] /tmp/text-engine-host-build/x86_64-unknown-linux-gnu/debug/SwiftTextEnginePackageDiscoveredTests.derived/all-discovered-tests.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.8468730Z [59/67] Write sources
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:37.8790803Z [60/67] Wrapping AST for TextEngineCoreTests for debugging
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:39.1406693Z [62/71] Compiling SwiftTextEnginePackageDiscoveredTests TextEngineReferenceProvidersTests.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:39.1408913Z [63/71] Compiling SwiftTextEnginePackageDiscoveredTests all-discovered-tests.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:39.1410059Z [64/71] Compiling SwiftTextEnginePackageDiscoveredTests TextEngineCoreTests.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:39.1410877Z [65/71] Emitting module SwiftTextEnginePackageDiscoveredTests
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:39.1787029Z [66/72] /tmp/text-engine-host-build/x86_64-unknown-linux-gnu/debug/SwiftTextEnginePackageTests.derived/runner.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:39.1788130Z [67/72] Write sources
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:39.2111038Z [68/72] Wrapping AST for SwiftTextEnginePackageDiscoveredTests for debugging
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:41.8332953Z [70/74] Emitting module SwiftTextEnginePackageTests
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:41.8333715Z [71/74] Compiling SwiftTextEnginePackageTests runner.swift
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:41.9067776Z [72/75] Wrapping AST for SwiftTextEnginePackageTests for debugging
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:41.9070738Z [73/75] Write Objects.LinkFileList
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.0499940Z [74/75] Linking SwiftTextEnginePackageTests.xctest
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.0517765Z Build complete! (10.79s)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5801019Z Test Suite 'All tests' started at 2026-06-17 16:16:42.061
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5801921Z Test Suite 'debug.xctest' started at 2026-06-17 16:16:42.062
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5802831Z Test Suite 'FenwickLineMetricsTests' started at 2026-06-17 16:16:42.062
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5804256Z Test Case 'FenwickLineMetricsTests.testMutationKeepsOffsetsEqualToFreshOracle' started at 2026-06-17 16:16:42.062
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5828898Z Test Case 'FenwickLineMetricsTests.testMutationKeepsOffsetsEqualToFreshOracle' passed (0.001 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5830064Z Test Case 'FenwickLineMetricsTests.testOffsetMatchesPrefixSumOracleOnBuild' started at 2026-06-17 16:16:42.064
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5831193Z Test Case 'FenwickLineMetricsTests.testOffsetMatchesPrefixSumOracleOnBuild' passed (0.101 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5832440Z Test Case 'FenwickLineMetricsTests.testOffsetsStrictlyIncreasingAfterMutation' started at 2026-06-17 16:16:42.164
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5833924Z Test Case 'FenwickLineMetricsTests.testOffsetsStrictlyIncreasingAfterMutation' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5835139Z Test Case 'FenwickLineMetricsTests.testPrefixQueryWalkBoundIsLogarithmic' started at 2026-06-17 16:16:42.165
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5836127Z Test Case 'FenwickLineMetricsTests.testPrefixQueryWalkBoundIsLogarithmic' passed (0.14 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5836886Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationMatchesFreshOracle' started at 2026-06-17 16:16:42.305
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5837668Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationMatchesFreshOracle' passed (0.002 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5838487Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationUsesLogarithmicCoreQueries' started at 2026-06-17 16:16:42.307
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5839341Z Test Case 'FenwickLineMetricsTests.testReLayoutAfterMutationUsesLogarithmicCoreQueries' passed (0.081 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5840587Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountExactForKnownSmallCases' started at 2026-06-17 16:16:42.388
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5841379Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountExactForKnownSmallCases' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5842158Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountIsLogarithmicAcrossSizes' started at 2026-06-17 16:16:42.388
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5842935Z Test Case 'FenwickLineMetricsTests.testUpdateWriteCountIsLogarithmicAcrossSizes' passed (0.089 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5843804Z Test Suite 'FenwickLineMetricsTests' passed at 2026-06-17 16:16:42.477
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5844293Z 	 Executed 8 tests, with 0 failures (0 unexpected) in 0.415 (0.415) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5844770Z Test Suite 'DocumentLineCursorTests' started at 2026-06-17 16:16:42.477
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5845401Z Test Case 'DocumentLineCursorTests.testCursorFetchesOneLinePerBufferedIndex' started at 2026-06-17 16:16:42.477
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5846436Z Test Case 'DocumentLineCursorTests.testCursorFetchesOneLinePerBufferedIndex' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5847489Z Test Case 'DocumentLineCursorTests.testCursorReportsMissingIndexesWithoutClampingRange' started at 2026-06-17 16:16:42.478
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5848352Z Test Case 'DocumentLineCursorTests.testCursorReportsMissingIndexesWithoutClampingRange' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5849163Z Test Case 'DocumentLineCursorTests.testCursorYieldsBufferedRangeLinesInOrder' started at 2026-06-17 16:16:42.478
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5849910Z Test Case 'DocumentLineCursorTests.testCursorYieldsBufferedRangeLinesInOrder' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5850705Z Test Case 'DocumentLineCursorTests.testCursorYieldsNothingForEmptyRangeAndDoesNotFetch' started at 2026-06-17 16:16:42.478
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5851542Z Test Case 'DocumentLineCursorTests.testCursorYieldsNothingForEmptyRangeAndDoesNotFetch' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5852354Z Test Case 'DocumentLineCursorTests.testGeneratedRangesFetchOnlyBufferedIndexes' started at 2026-06-17 16:16:42.478
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5853131Z Test Case 'DocumentLineCursorTests.testGeneratedRangesFetchOnlyBufferedIndexes' passed (0.001 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5854117Z Test Case 'DocumentLineCursorTests.testViewportComputationDoesNotFetchProviderLines' started at 2026-06-17 16:16:42.479
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5854946Z Test Case 'DocumentLineCursorTests.testViewportComputationDoesNotFetchProviderLines' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5855568Z Test Suite 'DocumentLineCursorTests' passed at 2026-06-17 16:16:42.479
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5856014Z 	 Executed 6 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5856453Z Test Suite 'DocumentLineValueTests' started at 2026-06-17 16:16:42.479
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5857144Z Test Case 'DocumentLineValueTests.testDocumentLineCursorElementEquatableWhenPayloadIsEquatable' started at 2026-06-17 16:16:42.479
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5858082Z Test Case 'DocumentLineValueTests.testDocumentLineCursorElementEquatableWhenPayloadIsEquatable' passed (0.1 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.5858944Z Test Case 'DocumentLineValueTests.testDocumentLineEquatableWhenPayloadIsEquatable' started at 2026-06-17 16:16:42.579
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6820710Z Test Case 'DocumentLineValueTests.testDocumentLineEquatableWhenPayloadIsEquatable' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6822017Z Test Case 'DocumentLineValueTests.testDocumentLineFetchEquatableWhenPayloadIsEquatable' started at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6822932Z Test Case 'DocumentLineValueTests.testDocumentLineFetchEquatableWhenPayloadIsEquatable' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6824026Z Test Case 'DocumentLineValueTests.testDocumentLineStoresIndexAndContent' started at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6824778Z Test Case 'DocumentLineValueTests.testDocumentLineStoresIndexAndContent' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6825748Z Test Suite 'DocumentLineValueTests' passed at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6826228Z 	 Executed 4 tests, with 0 failures (0 unexpected) in 0.101 (0.101) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6826717Z Test Suite 'LineGeometryCursorTests' started at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6827362Z Test Case 'LineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' started at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6828256Z Test Case 'LineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6829256Z Test Case 'LineGeometryCursorTests.testCursorYieldsOnlyBufferedLines' started at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6830384Z Test Case 'LineGeometryCursorTests.testCursorYieldsOnlyBufferedLines' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6831359Z Test Suite 'LineGeometryCursorTests' passed at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6831961Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6832650Z Test Suite 'LineMetricsSourceTests' started at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6833829Z Test Case 'LineMetricsSourceTests.testUniformLineMetricsOffsetIsLinear' started at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6835166Z Test Case 'LineMetricsSourceTests.testUniformLineMetricsOffsetIsLinear' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6836076Z Test Suite 'LineMetricsSourceTests' passed at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6836679Z 	 Executed 1 test, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6837306Z Test Suite 'VariableHeightQueryCountTests' started at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6838468Z Test Case 'VariableHeightQueryCountTests.testComputeClampAtDocumentEndDoesNotSearchMidDocumentOffsets' started at 2026-06-17 16:16:42.580
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6840000Z Test Case 'VariableHeightQueryCountTests.testComputeClampAtDocumentEndDoesNotSearchMidDocumentOffsets' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6841454Z Test Case 'VariableHeightQueryCountTests.testComputeEmptyDocumentQueriesOnlyFirstOffset' started at 2026-06-17 16:16:42.581
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6842856Z Test Case 'VariableHeightQueryCountTests.testComputeEmptyDocumentQueriesOnlyFirstOffset' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6844389Z Test Case 'VariableHeightQueryCountTests.testComputeSingleLineStaysBounded' started at 2026-06-17 16:16:42.581
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6845644Z Test Case 'VariableHeightQueryCountTests.testComputeSingleLineStaysBounded' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6847048Z Test Case 'VariableHeightQueryCountTests.testComputeUsesLogarithmicQueriesAtOneMillionLines' started at 2026-06-17 16:16:42.581
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6848565Z Test Case 'VariableHeightQueryCountTests.testComputeUsesLogarithmicQueriesAtOneMillionLines' passed (0.1 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6850165Z Test Case 'VariableHeightQueryCountTests.testEmptyGeometryCursorDoesNotSeedOffsetQuery' started at 2026-06-17 16:16:42.681
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6851706Z Test Case 'VariableHeightQueryCountTests.testEmptyGeometryCursorDoesNotSeedOffsetQuery' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6853417Z Test Case 'VariableHeightQueryCountTests.testNonEmptyGeometryCursorQueriesSeedPlusOnePerBufferedLine' started at 2026-06-17 16:16:42.681
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6855409Z Test Case 'VariableHeightQueryCountTests.testNonEmptyGeometryCursorQueriesSeedPlusOnePerBufferedLine' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6856696Z Test Suite 'VariableHeightQueryCountTests' passed at 2026-06-17 16:16:42.681
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6857464Z 	 Executed 6 tests, with 0 failures (0 unexpected) in 0.101 (0.101) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6858323Z Test Suite 'VariableLineGeometryCursorTests' started at 2026-06-17 16:16:42.681
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6859490Z Test Case 'VariableLineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' started at 2026-06-17 16:16:42.681
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6860951Z Test Case 'VariableLineGeometryCursorTests.testCursorForEmptyRangeYieldsNoGeometry' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6862402Z Test Case 'VariableLineGeometryCursorTests.testCursorYieldsBufferedLineGeometry' started at 2026-06-17 16:16:42.682
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6864235Z Test Case 'VariableLineGeometryCursorTests.testCursorYieldsBufferedLineGeometry' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6865273Z Test Suite 'VariableLineGeometryCursorTests' passed at 2026-06-17 16:16:42.682
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6866106Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6866891Z Test Suite 'VariableUniformEquivalenceTests' started at 2026-06-17 16:16:42.682
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6868028Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedAcrossRepresentableHeights' started at 2026-06-17 16:16:42.682
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6868912Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedAcrossRepresentableHeights' passed (0.001 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6869717Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedForIntMaxClamp' started at 2026-06-17 16:16:42.683
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6870439Z Test Case 'VariableUniformEquivalenceTests.testMatchesFixedForIntMaxClamp' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6871055Z Test Suite 'VariableUniformEquivalenceTests' passed at 2026-06-17 16:16:42.683
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6871744Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6872208Z Test Suite 'VariableViewportComputeTests' started at 2026-06-17 16:16:42.683
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6872852Z Test Case 'VariableViewportComputeTests.testEmptyDocumentReturnsEmptyRange' started at 2026-06-17 16:16:42.683
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6873848Z Test Case 'VariableViewportComputeTests.testEmptyDocumentReturnsEmptyRange' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6874775Z Test Case 'VariableViewportComputeTests.testEmptyDocumentStillValidatesFirstOffset' started at 2026-06-17 16:16:42.683
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6875990Z Test Case 'VariableViewportComputeTests.testEmptyDocumentStillValidatesFirstOffset' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6877163Z Test Case 'VariableViewportComputeTests.testNegativeLineCountFails' started at 2026-06-17 16:16:42.683
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6878298Z Test Case 'VariableViewportComputeTests.testNegativeLineCountFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6879467Z Test Case 'VariableViewportComputeTests.testNegativeOverscanFails' started at 2026-06-17 16:16:42.683
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6880451Z Test Case 'VariableViewportComputeTests.testNegativeOverscanFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6881686Z Test Case 'VariableViewportComputeTests.testNegativeViewportHeightFails' started at 2026-06-17 16:16:42.684
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6882883Z Test Case 'VariableViewportComputeTests.testNegativeViewportHeightFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6884196Z Test Case 'VariableViewportComputeTests.testNonFiniteScrollOffsetFails' started at 2026-06-17 16:16:42.684
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6885403Z Test Case 'VariableViewportComputeTests.testNonFiniteScrollOffsetFails' passed (0.001 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6886355Z Test Case 'VariableViewportComputeTests.testNonFiniteTotalHeightFails' started at 2026-06-17 16:16:42.685
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6887539Z Test Case 'VariableViewportComputeTests.testNonFiniteTotalHeightFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6888740Z Test Case 'VariableViewportComputeTests.testNonFiniteViewportHeightFails' started at 2026-06-17 16:16:42.685
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6889935Z Test Case 'VariableViewportComputeTests.testNonFiniteViewportHeightFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6891119Z Test Case 'VariableViewportComputeTests.testNonPositiveTotalHeightFails' started at 2026-06-17 16:16:42.685
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6892299Z Test Case 'VariableViewportComputeTests.testNonPositiveTotalHeightFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6893295Z Test Case 'VariableViewportComputeTests.testNonUniformVisibleRange' started at 2026-06-17 16:16:42.685
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6894384Z Test Case 'VariableViewportComputeTests.testNonUniformVisibleRange' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6895523Z Test Case 'VariableViewportComputeTests.testNonUniformWithOverscan' started at 2026-06-17 16:16:42.685
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6896924Z Test Case 'VariableViewportComputeTests.testNonUniformWithOverscan' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6897876Z Test Case 'VariableViewportComputeTests.testNonZeroFirstOffsetFails' started at 2026-06-17 16:16:42.685
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6898554Z Test Case 'VariableViewportComputeTests.testNonZeroFirstOffsetFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6899352Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportAtDocumentEndClampsToLineCount' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6900278Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportAtDocumentEndClampsToLineCount' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6901139Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportExactLineTopIsEmpty' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6901940Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportExactLineTopIsEmpty' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6902784Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportMidLineKeepsCrossedLine' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6903900Z Test Case 'VariableViewportComputeTests.testZeroHeightViewportMidLineKeepsCrossedLine' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6905003Z Test Suite 'VariableViewportComputeTests' passed at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6905482Z 	 Executed 15 tests, with 0 failures (0 unexpected) in 0.003 (0.003) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6905974Z Test Suite 'VariableViewportInputValueTests' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6906673Z Test Case 'VariableViewportInputValueTests.testInvalidLineMetricsErrorIsDistinct' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6907474Z Test Case 'VariableViewportInputValueTests.testInvalidLineMetricsErrorIsDistinct' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6908266Z Test Case 'VariableViewportInputValueTests.testVariableViewportInputStoresFields' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6909056Z Test Case 'VariableViewportInputValueTests.testVariableViewportInputStoresFields' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6909675Z Test Suite 'VariableViewportInputValueTests' passed at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6910158Z 	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6910591Z Test Suite 'ViewportInputValueTests' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6911192Z Test Case 'ViewportInputValueTests.testLineGeometryStoresIndexAndDimensions' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6911942Z Test Case 'ViewportInputValueTests.testLineGeometryStoresIndexAndDimensions' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6912648Z Test Case 'ViewportInputValueTests.testViewportInputStoresAllFields' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6913318Z Test Case 'ViewportInputValueTests.testViewportInputStoresAllFields' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6914123Z Test Case 'ViewportInputValueTests.testVirtualRangeReportsEmpty' started at 2026-06-17 16:16:42.686
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6914779Z Test Case 'ViewportInputValueTests.testVirtualRangeReportsEmpty' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6915302Z Test Suite 'ViewportInputValueTests' passed at 2026-06-17 16:16:42.687
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6915735Z 	 Executed 3 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6916202Z Test Suite 'ViewportOverscanInvariantTests' started at 2026-06-17 16:16:42.687
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6916835Z Test Case 'ViewportOverscanInvariantTests.testGeneratedInputsStayInBounds' started at 2026-06-17 16:16:42.687
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6917563Z Test Case 'ViewportOverscanInvariantTests.testGeneratedInputsStayInBounds' passed (0.001 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6918363Z Test Case 'ViewportOverscanInvariantTests.testOverscanBeforeClampsToZeroWithIntegerMath' started at 2026-06-17 16:16:42.687
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6919227Z Test Case 'ViewportOverscanInvariantTests.testOverscanBeforeClampsToZeroWithIntegerMath' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6920219Z Test Case 'ViewportOverscanInvariantTests.testOverscanClampsAtTopAndBottom' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6920958Z Test Case 'ViewportOverscanInvariantTests.testOverscanClampsAtTopAndBottom' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6921706Z Test Case 'ViewportOverscanInvariantTests.testOverscanExpandsBufferedRange' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6922425Z Test Case 'ViewportOverscanInvariantTests.testOverscanExpandsBufferedRange' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6923206Z Test Case 'ViewportOverscanInvariantTests.testOverscanPreservesPrecisionNearIntMax' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6924126Z Test Case 'ViewportOverscanInvariantTests.testOverscanPreservesPrecisionNearIntMax' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6924770Z Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6925237Z 	 Executed 5 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6925674Z Test Suite 'ViewportRangeTests' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6926305Z Test Case 'ViewportRangeTests.testFiniteExtremeOffsetClampsIndexBeforeIntConversion' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6927277Z Test Case 'ViewportRangeTests.testFiniteExtremeOffsetClampsIndexBeforeIntConversion' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6928123Z Test Case 'ViewportRangeTests.testFractionalLineHeightEndBoundaryDoesNotIncludeNextLine' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6928989Z Test Case 'ViewportRangeTests.testFractionalLineHeightEndBoundaryDoesNotIncludeNextLine' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6929842Z Test Case 'ViewportRangeTests.testFractionalLineHeightStartBoundaryBeginsAtExactLine' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6930670Z Test Case 'ViewportRangeTests.testFractionalLineHeightStartBoundaryBeginsAtExactLine' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6931509Z Test Case 'ViewportRangeTests.testFractionalLineHeightSublineOffsetIncludesPartialLines' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6932362Z Test Case 'ViewportRangeTests.testFractionalLineHeightSublineOffsetIncludesPartialLines' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6933179Z Test Case 'ViewportRangeTests.testLargeEndPartialLineDoesNotSnapDownToBoundary' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6934051Z Test Case 'ViewportRangeTests.testLargeEndPartialLineDoesNotSnapDownToBoundary' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6934817Z Test Case 'ViewportRangeTests.testLargeFractionalOffsetDoesNotSnapToBoundary' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.6935563Z Test Case 'ViewportRangeTests.testLargeFractionalOffsetDoesNotSnapToBoundary' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8066670Z Test Case 'ViewportRangeTests.testLargeStartPartialLineDoesNotSnapUpToBoundary' started at 2026-06-17 16:16:42.688
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8068291Z Test Case 'ViewportRangeTests.testLargeStartPartialLineDoesNotSnapUpToBoundary' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8069817Z Test Case 'ViewportRangeTests.testNegativeScrollOffsetClampsToTop' started at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8071085Z Test Case 'ViewportRangeTests.testNegativeScrollOffsetClampsToTop' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8072360Z Test Case 'ViewportRangeTests.testSublineOffsetUsesFloorForStartAndCeilForEnd' started at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8073893Z Test Case 'ViewportRangeTests.testSublineOffsetUsesFloorForStartAndCeilForEnd' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8075362Z Test Case 'ViewportRangeTests.testViewportLargerThanDocumentReturnsWholeDocument' started at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8076861Z Test Case 'ViewportRangeTests.testViewportLargerThanDocumentReturnsWholeDocument' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8078314Z Test Case 'ViewportRangeTests.testZeroHeightViewportProducesEmptyRangeAtOffset' started at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8079800Z Test Case 'ViewportRangeTests.testZeroHeightViewportProducesEmptyRangeAtOffset' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8081399Z Test Suite 'ViewportRangeTests' passed at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8082395Z 	 Executed 11 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8083251Z Test Suite 'ViewportValidationTests' started at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8084639Z Test Case 'ViewportValidationTests.testEmptyDocumentReturnsEmptyRange' started at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8085817Z Test Case 'ViewportValidationTests.testEmptyDocumentReturnsEmptyRange' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8086914Z Test Case 'ViewportValidationTests.testNegativeLineCountFails' started at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8087951Z Test Case 'ViewportValidationTests.testNegativeLineCountFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8088983Z Test Case 'ViewportValidationTests.testNegativeOverscanFails' started at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8090022Z Test Case 'ViewportValidationTests.testNegativeOverscanFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8091105Z Test Case 'ViewportValidationTests.testNegativeViewportHeightFails' started at 2026-06-17 16:16:42.689
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8092564Z Test Case 'ViewportValidationTests.testNegativeViewportHeightFails' passed (0.1 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8094123Z Test Case 'ViewportValidationTests.testNonFiniteLineHeightFails' started at 2026-06-17 16:16:42.790
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8095263Z Test Case 'ViewportValidationTests.testNonFiniteLineHeightFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8096342Z Test Case 'ViewportValidationTests.testNonFiniteScrollOffsetYFails' started at 2026-06-17 16:16:42.790
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8097488Z Test Case 'ViewportValidationTests.testNonFiniteScrollOffsetYFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8098681Z Test Case 'ViewportValidationTests.testNonFiniteViewportHeightFails' started at 2026-06-17 16:16:42.790
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8099848Z Test Case 'ViewportValidationTests.testNonFiniteViewportHeightFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8101013Z Test Case 'ViewportValidationTests.testNonPositiveLineHeightFails' started at 2026-06-17 16:16:42.790
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8102175Z Test Case 'ViewportValidationTests.testNonPositiveLineHeightFails' passed (0.0 seconds)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8103084Z Test Suite 'ViewportValidationTests' passed at 2026-06-17 16:16:42.790
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8104035Z 	 Executed 8 tests, with 0 failures (0 unexpected) in 0.101 (0.101) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8104741Z Test Suite 'debug.xctest' passed at 2026-06-17 16:16:42.790
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8105428Z 	 Executed 75 tests, with 0 failures (0 unexpected) in 0.727 (0.727) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8106085Z Test Suite 'All tests' passed at 2026-06-17 16:16:42.790
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8106711Z 	 Executed 75 tests, with 0 failures (0 unexpected) in 0.727 (0.727) seconds
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8107638Z ◇ Test run started.
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8108140Z ↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8108773Z ↳ Target Platform: x86_64-unknown-linux-gnu
Host tests and benchmark gate	Run host tests	2026-06-17T16:16:42.8109459Z ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
Host tests and benchmark gate	Run synthetic benchmark gate	﻿2026-06-17T16:16:42.8187637Z ##[group]Run swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:42.8188398Z ^[[36;1mswift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate^[[0m
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:42.8188975Z shell: sh -e {0}
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:42.8189189Z ##[endgroup]
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:43.3941611Z Building for production...
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:43.3994236Z [0/6] Write sources
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:43.4564541Z [3/6] Write swift-version-24593BA9C3E375BF.txt
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:43.9502609Z [5/7] Compiling TextEngineCore DocumentLineCursor.swift
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:44.2205400Z [6/8] Compiling TextEngineReferenceProviders FenwickLineMetrics.swift
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:47.2578032Z [7/9] Compiling ViewportBenchmarks BenchmarkModels.swift
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:47.2625118Z [7/9] Write Objects.LinkFileList
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:47.3664251Z [8/9] Linking ViewportBenchmarks
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:16:47.3683079Z Build of product 'ViewportBenchmarks' complete! (4.02s)
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:18:57.3392387Z mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=2747 p99_ns=2904 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:18:57.3394802Z mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=11368 p99_ns=12060 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T16:18:57.3397045Z mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=37013 p99_ns=37726 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
Host tests and benchmark gate	Run variable-height benchmark gate	﻿2026-06-17T16:18:57.3471889Z ##[group]Run swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height --gate
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:18:57.3472773Z ^[[36;1mswift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height --gate^[[0m
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:18:57.3473440Z shell: sh -e {0}
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:18:57.3473908Z ##[endgroup]
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:18:57.9370093Z [0/1] Planning build
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:18:57.9454619Z Building for production...
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:18:58.0063411Z [0/2] Write swift-version-24593BA9C3E375BF.txt
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:18:58.0083284Z Build of product 'ViewportBenchmarks' complete! (0.12s)
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:19:07.6059408Z mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=488 p99_ns=722 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:19:07.6061116Z mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1690 p99_ns=1805 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-17T16:19:07.6064522Z mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5499 p99_ns=5754 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

Docs-only shortcut marker search:

```text
docs_only_shortcut_status=1
```

### PR-Head Evidence Recursion Boundary

PR: #23
Head SHA: `09a6af8c325769385961115b3c22c1952e21f827`
Run: `27703735830`

Run summary:

```text
Swift CI
pull_request
completed
success
09a6af8c325769385961115b3c22c1952e21f827
Host tests and benchmark gate=success
iOS cross-target compile=success
WASM cross-target observation=success
```

Heavy path markers found in hosted logs:

```text
303:Host tests and benchmark gate	Run host tests	﻿2026-06-17T16:24:23.7764678Z ##[group]Run swift test --scratch-path /tmp/text-engine-host-build
564:Host tests and benchmark gate	Run synthetic benchmark gate	﻿2026-06-17T16:24:37.0851779Z ##[group]Run swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate
580:Host tests and benchmark gate	Run variable-height benchmark gate	﻿2026-06-17T16:26:41.8586438Z ##[group]Run swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height --gate
953:iOS cross-target compile	Compile TextEngineCore for iOS targets	﻿2026-06-17T16:23:50.8422320Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets ios
1293:WASM cross-target observation	Observe TextEngineCore for WASM targets	﻿2026-06-17T16:24:21.0575276Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets wasm
```

Docs-only shortcut marker search:

```text
docs_only_shortcut_status=1
```

Note: committing hosted evidence changes the PR head and retriggers Swift CI.
Do not chase another verification-file update for that evidence-only commit;
Task 7 will anchor final merged-code proof in the post-merge `push` run.

### Post-Merge Required-Check Proof

Merged PR: #23
Merge SHA: `ba4a77c1a8733e1996313df7552ab1b8437aafc0`
Post-merge run: `27705132073`

Command:

```bash
merge_sha="$(git rev-parse HEAD)"
run_id="$(gh run list --workflow "Swift CI" --branch main --limit 20 --json databaseId,headSha,event,status,conclusion --jq '[.[] | select(.headSha == "'"$merge_sha"'" and .event == "push")][0].databaseId')"
echo "post_merge_run_id=${run_id}"
gh run view "$run_id" --json name,event,status,conclusion,headSha,jobs > /private/tmp/slice-20-post-merge-run.json
jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-20-post-merge-run.json
```

Output:

```text
post_merge_run_id=27705132073
Swift CI
push
completed
success
ba4a77c1a8733e1996313df7552ab1b8437aafc0
Host tests and benchmark gate=success
iOS cross-target compile=success
WASM cross-target observation=success
```

Status: `0`

### Live Ruleset Readback

Command:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{
  id,
  name,
  target,
  enforcement,
  conditions,
  bypass_actors,
  required_status_checks: ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]),
  strict_required_status_checks_policy: (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy)
}' > /private/tmp/slice-20-ruleset-readback.json
cat /private/tmp/slice-20-ruleset-readback.json
jq -e '
  .id == 17656807
  and .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and (.required_status_checks | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and .strict_required_status_checks_policy == true
' /private/tmp/slice-20-ruleset-readback.json
```

Output:

```json
{
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ],
  "conditions": {
    "ref_name": {
      "exclude": [],
      "include": [
        "~DEFAULT_BRANCH"
      ]
    }
  },
  "enforcement": "active",
  "id": 17656807,
  "name": "Main",
  "required_status_checks": [
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ],
  "strict_required_status_checks_policy": true,
  "target": "branch"
}
true
```

Status: `0`

### Policy-Sensitive Markdown Proof PR

PR: #25, <https://github.com/maldrakar/swift-text-engine/pull/25>
Head SHA: `79a1b410895cee9d9b8887d27a9de97db176fca2`
Run: `27706101669`

Run summary:

```text
Swift CI
pull_request
completed
success
79a1b410895cee9d9b8887d27a9de97db176fca2
Host tests and benchmark gate=success
WASM cross-target observation=success
iOS cross-target compile=success
```

Heavy path markers found in hosted logs:

```text
306:Host tests and benchmark gate	Run host tests	2026-06-17T17:04:52.0430575Z ##[group]Run swift test --scratch-path /tmp/text-engine-host-build
567:Host tests and benchmark gate	Run synthetic benchmark gate	2026-06-17T17:05:04.7648448Z ##[group]Run swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate
1058:WASM cross-target observation	Observe TextEngineCore for WASM targets	2026-06-17T17:04:58.5573531Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets wasm
1298:iOS cross-target compile	Compile TextEngineCore for iOS targets	2026-06-17T17:04:25.6579560Z ##[group]Run ./.github/scripts/cross-target-compile.sh --targets ios
```

Docs-only shortcut marker search:

```text
policy_sensitive_docs_only_shortcut_status=1
```

Proof PR disposition: closed unmerged at `2026-06-17T17:15:20Z`
(`mergedAt=null`).

### True Docs-Only Proof PR

PR: #26, <https://github.com/maldrakar/swift-text-engine/pull/26>
Head SHA: `4a720e6ab0f04f4dac1537b2be99280b0ef169ab`
Run: `27706623092`

Run summary:

```text
Swift CI
pull_request
completed
success
4a720e6ab0f04f4dac1537b2be99280b0ef169ab
Host tests and benchmark gate=success
WASM cross-target observation=success
iOS cross-target compile=success
```

Docs-only shortcut markers found in hosted logs:

```text
246:Host tests and benchmark gate	Complete docs-only PR	2026-06-17T17:14:05.8342788Z mode=docs_only_pr job=host-tests-and-benchmark-gate result=success
517:WASM cross-target observation	Complete docs-only PR	2026-06-17T17:14:03.3768240Z mode=docs_only_pr job=wasm-cross-target-observation result=success
716:iOS cross-target compile	Complete docs-only PR	2026-06-17T17:13:36.2450950Z mode=docs_only_pr job=ios-cross-target-compile result=success
```

Heavy marker search:

```text
docs_only_heavy_marker_status=1
```

Proof PR disposition: closed unmerged at `2026-06-17T17:15:35Z`
(`mergedAt=null`).
