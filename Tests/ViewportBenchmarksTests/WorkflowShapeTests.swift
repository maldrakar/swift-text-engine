// Foundation is imported HERE, in the test target, purely to read the workflow file off
// disk -- the same reason GateFloorTests.swift imports it. Sources/ViewportBenchmarks
// stays Foundation-free; a test-target import cannot change that, and the XCTest runtime
// already links Foundation anyway.
import Foundation
import XCTest

// The shape these tests pin is the one the Slice 16 dead-step trap destroyed once
// already: a `continue-on-error` step swallows EVERY non-zero exit, so a gated step under
// it is budget-blind AND failure-blind. Nothing else in the repo reads swift-ci.yml, so
// without these tests each gate's blocking shape is verified exactly once, by hand, into a
// verification record: the failure mode GateFloorTests.swift was created to end.
//
// `pinnedGateSteps` is a small EXPLICIT table of the gate steps whose shape is pinned
// (currently --point-geometry-query and --realistic-provider; a gate joins by hand when it
// is promoted). It is deliberately NOT `BenchmarkMode.allCases where isGateable`: that
// quantifier is false for the `.pipeline` default mode, which has no flag at all (it runs
// as a bare `--gate`), and there is no BenchmarkMode -> flag mapping to match against --
// BenchmarkMode exposes only snake_case `outputName`, while the flags live as hand-written
// `case` labels inside BenchmarkOptions.parse. Generalizing to every CI-gated mode needs a
// `flagName` property, a named-and-justified exemption set, and a test pinning the two
// together -- a design of its own.

private let workflowPath = ".github/workflows/swift-ci.yml"
private let hostJobKey = "host-tests-and-benchmark-gate"
private let wasmJobKey = "wasm-cross-target-observation"
private let docsOnlyGuard = "steps.change-scope.outputs.docs_only_pr != 'true'"
private let memoryShapeStepName = "Run memory shape diagnostic"
private let pointGeometryFlag = "--point-geometry-query"
private let realisticFlag = "--realistic-provider"

// The exact whitespace-joined `run:` payload every gate step must carry. Pinned as a
// whole command rather than probed for tokens: a step-level token count cannot see a
// second invocation inside one `|` block scalar or a trailing `|| true`, and both
// disarm the gate.
private func gateCommand(_ flag: String) -> String {
    "swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks "
        + "-- \(flag) --gate"
}

// One row per gate step whose blocking shape is pinned, with the ordering anchors it
// must sit between. A gate joins this table by hand when it is promoted (see the header
// note above).
private struct GateStepSpec {
    let flag: String            // the mode flag whose presence identifies the step
    let stepName: String        // the exact `- name:` the step must carry
    let command: String         // the exact whitespace-joined `run:` payload
    let afterStepName: String   // the step it must sit after
    let beforeStepName: String  // the step it must sit before
}

private let pinnedGateSteps: [GateStepSpec] = [
    GateStepSpec(
        flag: pointGeometryFlag,
        stepName: "Run point geometry query benchmark gate",
        command: gateCommand(pointGeometryFlag),
        afterStepName: "Run point query benchmark gate",
        beforeStepName: memoryShapeStepName),
    GateStepSpec(
        flag: realisticFlag,
        stepName: "Run realistic provider benchmark gate",
        command: gateCommand(realisticFlag),
        afterStepName: "Run point geometry query benchmark gate",
        beforeStepName: memoryShapeStepName),
]

// Twin of `repositoryRoot()` in GateFloorTests.swift -- the same three-parent walk from
// #filePath. Duplicated rather than shared because both are file-scope `private` helpers
// in a target with no test-support file; if one moves, move the other.
private func repositoryRoot() -> URL {
    // .../Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift -> repo root
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private struct WorkflowStep {
    let name: String
    let index: Int          // position within the host job's step list
    let ifCondition: String?
    let continueOnError: String?
    let runTokens: [String]
}

private func indentation(of line: String) -> Int {
    line.prefix(while: { $0 == " " }).count
}

private func isBlank(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).isEmpty
}

private func isComment(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
}

// A step key at the fixed 8-space indent this file uses, e.g. `        if: ...`.
private func value(of key: String, in line: String) -> String? {
    let prefix = "        \(key):"
    guard line.hasPrefix(prefix) else { return nil }
    return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
}

// There is no YAML parser in reach -- the package is zero-dependency and Foundation ships
// none -- so this is a deliberately narrow reader of the one shape swift-ci.yml actually
// uses: 6-space `- name:` step headers, 8-space step keys, and a `run:` that is either
// inline or a `|` block scalar whose body is indented past the key.
//
// Comment lines are excluded everywhere, though the two `isComment` checks below earn
// their keep differently. `value(of:)` only matches an exact 8-space-anchored key prefix
// like `        continue-on-error:`, so a comment line -- 8 spaces then `#` -- can never
// satisfy that regardless of what text follows the `#`; the top-level guard at the head of
// this function's per-line loop is redundant for key detection. (If a step ever carries a
// prose comment that happens to contain "continue-on-error", it is that key-anchored
// prefix match, not comment exclusion, that keeps the prose from being misread as the key.)
// What comment exclusion DOES protect is the run-payload collection loop a few lines down:
// a `#` line indented past 8 inside a `run: |` block body would otherwise be appended as a
// spurious run TOKEN, and this file compares a step's run payload for token EQUALITY, so
// one stray token would break that check.
private func parseStep(_ block: [String], index: Int) -> WorkflowStep {
    let header = "      - name:"
    let name = String(block[0].dropFirst(header.count)).trimmingCharacters(in: .whitespaces)

    var ifCondition: String?
    var continueOnError: String?
    var runTokens: [String] = []

    for (offset, line) in block.enumerated() {
        if isComment(line) { continue }
        if let condition = value(of: "if", in: line) { ifCondition = condition }
        if let flag = value(of: "continue-on-error", in: line) { continueOnError = flag }
        if let inlineRun = value(of: "run", in: line) {
            var payload = [inlineRun]
            var cursor = offset + 1
            while cursor < block.count {
                let next = block[cursor]
                cursor += 1
                if isBlank(next) { continue }
                if indentation(of: next) <= 8 { break }   // a sibling key ends the payload
                if isComment(next) { continue }
                payload.append(next)
            }
            // Whitespace-separated TOKENS, never substrings: `--variable-height` is a
            // prefix of `--variable-height-mutation`, and `contains(_: String)` on the
            // joined payload would conflate the two.
            runTokens = payload.joined(separator: " ")
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
        }
    }

    return WorkflowStep(name: name, index: index, ifCondition: ifCondition,
                        continueOnError: continueOnError, runTokens: runTokens)
}

// Scoped to a single job's own region -- from its 2-space key to the next one. All three
// jobs indent their steps identically, and four step names (`Check out repository`,
// `Detect PR change scope`, `Complete docs-only PR`, `Show toolchain`) repeat verbatim
// across them, so a whole-file split would make every name lookup ambiguous.
private func jobSteps(_ jobKey: String) throws -> [WorkflowStep] {
    let url = repositoryRoot().appendingPathComponent(workflowPath)
    let text = try String(contentsOf: url, encoding: .utf8)
    let allLines = text.components(separatedBy: "\n")

    guard let jobStart = allLines.firstIndex(where: { $0.hasPrefix("  \(jobKey):") }) else {
        XCTFail("\(workflowPath): no job keyed \(jobKey)")
        return []
    }

    var jobEnd = allLines.count
    for index in (jobStart + 1)..<allLines.count {
        let line = allLines[index]
        if isBlank(line) || isComment(line) { continue }
        if indentation(of: line) <= 2 {
            jobEnd = index
            break
        }
    }

    let lines = Array(allLines[jobStart..<jobEnd])
    let starts = lines.indices.filter { lines[$0].hasPrefix("      - name:") }
    return starts.enumerated().map { order, start in
        let end = order + 1 < starts.count ? starts[order + 1] : lines.count
        return parseStep(Array(lines[start..<end]), index: order)
    }
}

private func hostJobSteps() throws -> [WorkflowStep] {
    try jobSteps(hostJobKey)
}

private func wasmJobSteps() throws -> [WorkflowStep] {
    try jobSteps(wasmJobKey)
}

private func stepNamed(_ name: String, in steps: [WorkflowStep]) -> WorkflowStep? {
    steps.first { $0.name == name }
}

final class WorkflowShapeTests: XCTestCase {

    // Resolve a spec's step(s) by FLAG, asserting the set is non-empty first: a test that
    // quantified over an empty set would be vacuously green the day the gate was deleted.
    private func steps(for spec: GateStepSpec, in all: [WorkflowStep]) -> [WorkflowStep] {
        let matches = all.filter { $0.runTokens.contains(spec.flag) }
        XCTAssertFalse(
            matches.isEmpty,
            "\(workflowPath): no step in \(hostJobKey) runs \(spec.flag) — the "
                + "\"\(spec.stepName)\" gate is gone")
        return matches
    }

    // Invariant 1. Exactly one step runs each pinned flag. Two steps ran a mode while its
    // budget was observational (a bare correctness run + a continue-on-error gated run);
    // one step cannot be both, and a second printing step double-weights the mode in every
    // future harvest of that run.
    func testExactlyOneStepRunsEachPinnedGate() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            let matches = steps(for: spec, in: all)
            XCTAssertEqual(
                matches.count, 1,
                "\(workflowPath): \(matches.count) steps run \(spec.flag), want exactly 1 — "
                    + "\(matches.map(\.name))")
        }
    }

    // Invariant 2. Exact command equality, not `runTokens.contains("--gate")`. Subsumes the
    // --gate check and forecloses a double invocation inside one `|` block scalar and a
    // trailing `|| true`, both of which a token probe reports as green.
    func testEachPinnedGateRunsExactlyTheExpectedCommand() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            for step in steps(for: spec, in: all) {
                XCTAssertEqual(
                    step.runTokens.joined(separator: " "), spec.command,
                    "\(step.name): run payload is not the expected single gated command.\n"
                        + "  want: \(spec.command)\n"
                        + "  got:  \(step.runTokens.joined(separator: " "))")
            }
        }
    }

    // Invariant 3. THE one that matters: continue-on-error swallows every non-zero exit, so
    // a gated step under it can fail neither on budget nor on failureCount != 0.
    func testNoPinnedGateIsContinueOnError() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            for step in steps(for: spec, in: all) {
                XCTAssertNil(
                    step.continueOnError,
                    "\(step.name): carries continue-on-error: \(step.continueOnError ?? "") — "
                        + "a continue-on-error step cannot be a gate; it swallows budget "
                        + "misses, correctness failures and crashes alike")
            }
        }
    }

    // Invariant 4. The same docs-only guard every sibling gate carries.
    func testEachPinnedGateCarriesTheDocsOnlyGuard() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            for step in steps(for: spec, in: all) {
                XCTAssertEqual(
                    step.ifCondition, docsOnlyGuard,
                    "\(step.name): does not carry the sibling docs-only guard")
            }
        }
    }

    // Invariant 5. The name is the only place a reader learns whether the step is blocking,
    // so a stale "observational" qualifier is a lie in the log of every run.
    func testEachPinnedGateIsNamedForItsSiblings() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            for step in steps(for: spec, in: all) {
                XCTAssertEqual(
                    step.name, spec.stepName,
                    "step running \(spec.flag) is named \"\(step.name)\", want "
                        + "\"\(spec.stepName)\"")
            }
        }
    }

    // Invariant 6. Every pinned gate stays contiguous, ahead of the diagnostics, in the
    // order point-query < point-geometry < realistic < memory-shape.
    func testEachPinnedGateSitsBetweenItsAnchors() throws {
        let all = try hostJobSteps()
        for spec in pinnedGateSteps {
            let matches = all.filter { $0.runTokens.contains(spec.flag) }
            XCTAssertFalse(matches.isEmpty, "no step runs \(spec.flag)")

            guard let after = stepNamed(spec.afterStepName, in: all),
                  let before = stepNamed(spec.beforeStepName, in: all) else {
                XCTFail("\(workflowPath): missing \"\(spec.afterStepName)\" or "
                    + "\"\(spec.beforeStepName)\" — the ordering anchors for \(spec.flag) "
                    + "are gone")
                continue
            }

            for step in matches {
                XCTAssertLessThan(
                    after.index, step.index,
                    "\(step.name) must sit after \"\(spec.afterStepName)\"")
                XCTAssertLessThan(
                    step.index, before.index,
                    "\(step.name) must sit before \"\(spec.beforeStepName)\"")
            }
        }
    }

    // The WASM job is now a real blocking gate; pin its compile step's shape so a
    // future `continue-on-error` cannot silently swallow a fail-closed WASM failure
    // (the Slice 16 dead-step trap, in a different job).
    func testWasmCompileStepIsBlockingShaped() throws {
        let steps = try wasmJobSteps()
        let matches = steps.filter {
            $0.runTokens.contains("--targets") && $0.runTokens.contains("wasm")
        }
        XCTAssertEqual(
            matches.count, 1,
            "\(workflowPath): expected exactly one WASM compile step running "
                + "--targets wasm in \(wasmJobKey)")
        guard let step = matches.first else { return }
        XCTAssertNil(
            step.continueOnError,
            "\(workflowPath): the WASM compile step must not be continue-on-error — it "
                + "would swallow the fail-closed WASM gate (the Slice 16 trap)")
        XCTAssertEqual(
            step.runTokens.joined(separator: " "),
            "./.github/scripts/cross-target-compile.sh --targets wasm",
            "\(workflowPath): the WASM compile step's run payload must be exactly the "
                + "cross-target script invocation — a trailing `|| true` or a second "
                + "invocation would disarm the gate (the Slice 16 trap)")
        XCTAssertEqual(
            step.ifCondition, docsOnlyGuard,
            "\(workflowPath): the WASM compile step must carry the docs-only guard")
    }
}
