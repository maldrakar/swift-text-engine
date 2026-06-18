# Cross-Target Provider Coverage Verification

Date: 2026-06-18

## Scope

Slice 22 extends the cross-target helper from one package
(`TextEngineCore`) to two packages (`TextEngineCore` and
`TextEngineReferenceProviders`). iOS device and simulator builds are blocking
for both packages. WASM and embedded WASM remain observational for both
packages.

This slice changes only the helper, workflow labels, durable docs, and slice
paper trail. It does not change `Sources/**`, `Tests/**`, or `Package.swift`.

Changed files from the slice base (`76fdc1c..HEAD`):

```text
.github/scripts/cross-target-compile.sh
.github/workflows/swift-ci.yml
AGENTS.md
docs/superpowers/plans/2026-06-18-cross-target-provider-coverage.md
docs/superpowers/specs/2026-06-18-cross-target-provider-coverage-design.md
docs/superpowers/verification/2026-06-18-cross-target-provider-coverage.md
```

## Red Phase

Command:

```text
git show 969cd55:.github/scripts/cross-target-compile.sh | bash -s -- --self-test
```

Output:

```text
bash: line 175: scheme_for_package: command not found
self_test=fail label=scheme_for_package_core expected=TextEngineCore actual=
exit status 1
```

Exit status: `1`.

This is the expected failing-test-first result from
`969cd55 test: assert two-package cross-target contract`.

## Local Verification

Command:

```text
./.github/scripts/cross-target-compile.sh --self-test
```

Output:

```text
self_test=pass
```

Exit status: `0`.

Command:

```text
bash -n .github/scripts/cross-target-compile.sh && echo "syntax_ok"
```

Output:

```text
syntax_ok
```

Exit status: `0`.

Command:

```text
./.github/scripts/cross-target-compile.sh --targets ios
```

Output:

```text
cross_target_swift_version=6.2.1
cross_target_developer_dir=unset
cross_target_xcode_select_path=/Applications/Xcode_26_3.app/Contents/Developer
cross_target_xcodebuild_version=Xcode 26.3;Build version 17C529
cross_target_iphoneos_sdk_path=/Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk
cross_target_iphoneos_sdk_version=26.2
cross_target_iphonesimulator_sdk_path=/Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk
cross_target_iphonesimulator_sdk_version=26.2
cross_target_command target=ios_device scheme=TextEngineCore cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS'"
mode=cross_target_compile target=ios_device package=core result=pass reason=none blocking=true
cross_target_command target=ios_simulator scheme=TextEngineCore cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator'"
mode=cross_target_compile target=ios_simulator package=core result=pass reason=none blocking=true
mode=cross_target_compile target=wasm package=core result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=wasm_embedded package=core result=skipped reason=not_requested blocking=false
mode=cross_target_compile_summary package=core ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
cross_target_command target=ios_device scheme=TextEngineReferenceProviders cmd="xcodebuild build -scheme TextEngineReferenceProviders -destination 'generic/platform=iOS'"
mode=cross_target_compile target=ios_device package=providers result=pass reason=none blocking=true
cross_target_command target=ios_simulator scheme=TextEngineReferenceProviders cmd="xcodebuild build -scheme TextEngineReferenceProviders -destination 'generic/platform=iOS Simulator'"
mode=cross_target_compile target=ios_simulator package=providers result=pass reason=none blocking=true
mode=cross_target_compile target=wasm package=providers result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=wasm_embedded package=providers result=skipped reason=not_requested blocking=false
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

Exit status: `0`.

Command:

```text
./.github/scripts/cross-target-compile.sh --targets wasm
```

Output:

```text
cross_target_swift_version=6.2.1
mode=cross_target_compile target=ios_device package=core result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=ios_simulator package=core result=skipped reason=not_requested blocking=false
cross_target_wasm_sdk_id target=wasm package=core id=swift-6.2.1-RELEASE_wasm
cross_target_command target=wasm package=core cmd="swift build --scratch-path /var/folders/ng/7t8z1bp57j19rdccwc5ht83r0000gn/T//cross-target.3IQafK/swiftpm-wasm-core --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore"
mode=cross_target_compile target=wasm package=core result=pass reason=none blocking=false
cross_target_wasm_sdk_id target=wasm_embedded package=core id=swift-6.2.1-RELEASE_wasm-embedded
cross_target_command target=wasm_embedded package=core cmd="swift build --scratch-path /var/folders/ng/7t8z1bp57j19rdccwc5ht83r0000gn/T//cross-target.3IQafK/swiftpm-wasm_embedded-core --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore"
mode=cross_target_compile target=wasm_embedded package=core result=pass reason=none blocking=false
mode=cross_target_compile_summary package=core ios_device=skipped ios_simulator=skipped wasm=pass wasm_embedded=pass
mode=cross_target_compile target=ios_device package=providers result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=ios_simulator package=providers result=skipped reason=not_requested blocking=false
cross_target_wasm_sdk_id target=wasm package=providers id=swift-6.2.1-RELEASE_wasm
cross_target_command target=wasm package=providers cmd="swift build --scratch-path /var/folders/ng/7t8z1bp57j19rdccwc5ht83r0000gn/T//cross-target.3IQafK/swiftpm-wasm-providers --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineReferenceProviders"
mode=cross_target_compile target=wasm package=providers result=pass reason=none blocking=false
cross_target_wasm_sdk_id target=wasm_embedded package=providers id=swift-6.2.1-RELEASE_wasm-embedded
cross_target_command target=wasm_embedded package=providers cmd="swift build --scratch-path /var/folders/ng/7t8z1bp57j19rdccwc5ht83r0000gn/T//cross-target.3IQafK/swiftpm-wasm_embedded-providers --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineReferenceProviders"
mode=cross_target_compile target=wasm_embedded package=providers result=pass reason=none blocking=false
mode=cross_target_compile_summary package=providers ios_device=skipped ios_simulator=skipped wasm=pass wasm_embedded=pass
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

Exit status: `0`.

Command:

```text
rg -n "Foundation" Sources/TextEngineCore; echo "foundation_scan_exit=$?"
```

Output:

```text
foundation_scan_exit=1
```

Exit status: `0`.

Command:

```text
rg -n "name: iOS cross-target compile|name: WASM cross-target observation" .github/workflows/swift-ci.yml
```

Output:

```text
153:    name: iOS cross-target compile
223:    name: WASM cross-target observation
```

Exit status: `0`.

## macOS Job Timing Risk

| Signal | Evidence | Result |
| --- | --- | --- |
| Previous single-package hosted macOS timing | `docs/superpowers/verification/2026-06-09-cross-target-textenginecore-ci.md` records the Slice 13 hosted cross-target job as `0m36s` for `TextEngineCore` only. | Baseline only; hosted image and helper shape differ from this slice. |
| Current two-package local timing | The final successful local helper run above completed in the harness in about 5 seconds on Xcode 26.3 after warm caches. | Local-only observation; not comparable to hosted macOS timing. |
| Attempted local old-vs-new timing | Extracting the pre-slice helper to `/private/tmp` and running it with `/usr/bin/time -p` failed before compilation with `xcodebuild_list_failed` / CoreSimulator service errors. A concurrent timing attempt also failed for the same reason. | Invalid comparison, not used as evidence. |
| Current two-package hosted timing | PR-head Swift CI run. | Pending: fill after PR run. |

Hosted macOS timing delta is therefore pending hosted PR evidence. The
correct comparison is the future PR-head `iOS cross-target compile` job against
the previous hosted single-package `0m36s` baseline.

## Hosted Evidence

To be filled after the branch is pushed and CI runs:

```text
pr_number=<pending>
pr_head_run_id=<pending>
pr_head_run_url=<pending>
pr_head_sha=<pending>
required_context_host=Host tests and benchmark gate:<pending>
required_context_ios=iOS cross-target compile:<pending>
required_context_wasm=WASM cross-target observation:<pending>
```

Post-merge proof to be filled after merging:

```text
post_merge_push_run_id=<pending>
post_merge_push_run_url=<pending>
merge_sha=<pending>
```

Expected hosted signals:

- `iOS cross-target compile` emits package-qualified pass lines for
  `TextEngineCore` and `TextEngineReferenceProviders` on iOS device and
  simulator, with `mode=cross_target_compile_overall blocking_failures=0 exit=0`.
- `WASM cross-target observation` emits package-qualified WASM lines for both
  packages; the hosted runner may record `result=skipped reason=sdk_unavailable`
  when no matching Swift SDK is installed.
- Required job contexts remain `Host tests and benchmark gate`,
  `iOS cross-target compile`, and `WASM cross-target observation`.
