// Foundation is imported HERE, in the test target, purely to read the workflow file off
// disk -- the same reason GateFloorTests.swift imports it. Sources/ViewportBenchmarks
// stays Foundation-free; a test-target import cannot change that, and the XCTest runtime
// already links Foundation anyway.
import Foundation
import XCTest

// The shape this pins is the one the Slice 16 dead-step trap destroyed once already: a
// `continue-on-error` step swallows EVERY non-zero exit, so a gated step under it is
// budget-blind AND failure-blind. Slice 39 worked around that with two steps -- a bare
// correctness run plus an observational gated run -- and Slice 40 collapsed them into one
// blocking step. Nothing else in the repo reads swift-ci.yml, so without this test the
// collapse is verified exactly once, by hand, into a verification record: the failure mode
// GateFloorTests.swift was created to end.
//
// Scoped to --point-geometry-query on purpose, and NOT to `BenchmarkMode.allCases where
// isGateable`. That quantifier is false today for 3 of the 12 gateable modes, so a test
// written against it would be red for reasons unrelated to this slice -- and `swift test`
// is a blocking CI step, so it would fail the required job:
//   * .pipeline has no flag at all; it is the default mode, run as a bare `--gate`.
//   * .realisticProvider is deliberately never run with `--gate` in CI (AGENTS.md,
//     "## Gate budgets"): its step is PR-only and continue-on-error.
//   * there is no BenchmarkMode -> flag mapping to match against; BenchmarkMode exposes
//     only snake_case `outputName`, while the flags live as hand-written `case` labels
//     inside BenchmarkOptions.parse.
// Generalizing to every CI-gated mode needs a `flagName` property, a named-and-justified
// exemption set, and a test pinning the two together -- a design of its own.

private let workflowPath = ".github/workflows/swift-ci.yml"
private let hostJobKey = "host-tests-and-benchmark-gate"
private let pointGeometryFlag = "--point-geometry-query"
private let pointGeometryStepName = "Run point geometry query benchmark gate"
private let pointQueryStepName = "Run point query benchmark gate"
private let memoryShapeStepName = "Run memory shape diagnostic"
private let docsOnlyGuard = "steps.change-scope.outputs.docs_only_pr != 'true'"

// The step's exact shape IS the invariant, so the test pins the whole command rather than
// probing it for tokens. A step-level token count cannot see inside one step's payload,
// where both remaining ways to disarm the gate live: a `|` block scalar invoking the
// benchmark twice (one step, two runs -- double-weighting the mode in every future harvest
// of that run), and a trailing `|| true`, which is continue-on-error by another spelling
// and sails past a check that only reads the flag key.
//
// This deliberately couples the test to swift-ci.yml's text: changing the scratch path or
// the flag order is then a two-line edit with a test naming the mismatch, which is the
// intended behavior here.
private let pointGeometryCommand =
    "swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks "
        + "-- --point-geometry-query --gate"

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
// this function's per-line loop is redundant for key detection. swift-ci.yml:145-148 is a
// still-present, concrete example of exactly that kind of text: a comment on the PR-only
// realistic-provider observation step whose last line reads "...the step is
// continue-on-error." in prose -- and it is the key-anchored prefix match, not comment
// exclusion, that keeps it from being misread as the key there.
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

// Scoped to the host job's own region -- from its 2-space key to the next one. All three
// jobs indent their steps identically, and four step names (`Check out repository`,
// `Detect PR change scope`, `Complete docs-only PR`, `Show toolchain`) repeat verbatim
// across them, so a whole-file split would make every name lookup ambiguous.
private func hostJobSteps() throws -> [WorkflowStep] {
    let url = repositoryRoot().appendingPathComponent(workflowPath)
    let text = try String(contentsOf: url, encoding: .utf8)
    let allLines = text.components(separatedBy: "\n")

    guard let jobStart = allLines.firstIndex(where: { $0.hasPrefix("  \(hostJobKey):") }) else {
        XCTFail("\(workflowPath): no job keyed \(hostJobKey)")
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

private func stepNamed(_ name: String, in steps: [WorkflowStep]) -> WorkflowStep? {
    steps.first { $0.name == name }
}

final class WorkflowShapeTests: XCTestCase {

    // Every test resolves the point-geometry steps by FLAG, not by name, and asserts the
    // set is non-empty first. A test that quantified over an empty set would be vacuously
    // green the day someone deleted the gate outright.
    private func pointGeometrySteps() throws -> [WorkflowStep] {
        let matches = try hostJobSteps().filter { $0.runTokens.contains(pointGeometryFlag) }
        XCTAssertFalse(
            matches.isEmpty,
            "\(workflowPath): no step in \(hostJobKey) runs \(pointGeometryFlag) — the "
                + "eleventh blocking gate is gone")
        return matches
    }

    // Invariant 1. Two steps ran this mode while its budget was observational: a bare
    // correctness run and a continue-on-error gated run. One step cannot be both, so the
    // split was correct scaffolding -- and it had to end as one step, not one and a half.
    // A second printing step also puts two rows per scenario into every future harvest of
    // that run and double-weights it in median().
    func testExactlyOneStepRunsThePointGeometryQueryBenchmark() throws {
        let matches = try pointGeometrySteps()
        XCTAssertEqual(
            matches.count, 1,
            "\(workflowPath): \(matches.count) steps run \(pointGeometryFlag), want exactly "
                + "1 — \(matches.map(\.name))")
    }

    // Invariant 2. Exact equality, not `runTokens.contains("--gate")`. Subsumes the --gate
    // check and additionally forecloses a double invocation inside one `|` block scalar and
    // a trailing `|| true`, both of which a token probe reports as green. It does NOT
    // subsume invariant 1: this constrains the matched step, not the existence of a second
    // one, so the two are complementary.
    func testThePointGeometryStepRunsExactlyTheExpectedCommand() throws {
        for step in try pointGeometrySteps() {
            XCTAssertEqual(
                step.runTokens.joined(separator: " "), pointGeometryCommand,
                "\(step.name): run payload is not the expected single gated command.\n"
                    + "  want: \(pointGeometryCommand)\n"
                    + "  got:  \(step.runTokens.joined(separator: " "))")
        }
    }

    // Invariant 3. THE one that matters: continue-on-error swallows every non-zero exit,
    // so a gated step under it can fail neither on budget nor on failureCount != 0.
    func testThePointGeometryStepIsNotContinueOnError() throws {
        for step in try pointGeometrySteps() {
            XCTAssertNil(
                step.continueOnError,
                "\(step.name): carries continue-on-error: \(step.continueOnError ?? "") — a "
                    + "continue-on-error step cannot be a gate; it swallows budget misses, "
                    + "correctness failures and crashes alike")
        }
    }

    // Invariant 4. The same docs-only guard every sibling gate carries, asserted as the
    // literal expression so no other step's shape can turn this test red or green.
    func testThePointGeometryStepCarriesTheDocsOnlyGuard() throws {
        for step in try pointGeometrySteps() {
            XCTAssertEqual(
                step.ifCondition, docsOnlyGuard,
                "\(step.name): does not carry the sibling docs-only guard")
        }
    }

    // Invariant 5. The name is the only place a reader learns whether the step is blocking,
    // so a stale "observational"/"until Slice 40" qualifier is a lie in the log of every run.
    func testThePointGeometryStepIsNamedForItsSiblings() throws {
        for step in try pointGeometrySteps() {
            XCTAssertEqual(
                step.name, pointGeometryStepName,
                "step running \(pointGeometryFlag) is named \"\(step.name)\", want "
                    + "\"\(pointGeometryStepName)\"")
        }
    }

    // Invariant 6. All eleven blocking latency gates stay contiguous, ahead of the
    // diagnostics.
    func testThePointGeometryStepSitsBetweenThePointQueryGateAndTheMemoryShapeDiagnostic() throws {
        let steps = try hostJobSteps()
        let matches = steps.filter { $0.runTokens.contains(pointGeometryFlag) }
        XCTAssertFalse(matches.isEmpty)

        guard let pointQuery = stepNamed(pointQueryStepName, in: steps),
              let memoryShape = stepNamed(memoryShapeStepName, in: steps) else {
            XCTFail("\(workflowPath): missing \"\(pointQueryStepName)\" or "
                + "\"\(memoryShapeStepName)\" — the ordering anchors are gone")
            return
        }

        for step in matches {
            XCTAssertLessThan(
                pointQuery.index, step.index,
                "\(step.name) must sit after \"\(pointQueryStepName)\"")
            XCTAssertLessThan(
                step.index, memoryShape.index,
                "\(step.name) must sit before \"\(memoryShapeStepName)\"")
        }
    }
}
