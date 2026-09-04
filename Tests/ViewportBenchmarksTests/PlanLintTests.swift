import Foundation
import XCTest

// The linter is an AUTHORING tool -- it is run while a plan is still being written and not
// yet committed, which is why it is a script and not only a test. This file is the other
// half: it makes running it non-optional, and it pins the exemption RATCHET.
//
// The ratchet is pinned by property, not by copying 56 filenames into Swift. Four checks
// that are tighter jointly than severally: the script exits 0 over the whole directory,
// the list holds exactly `expectedExemptCount` entries, every entry exists on disk, and no
// entry is dated on or after the cutoff. SWAPPING a new plan in for an old one keeps the
// count and the on-disk check green -- and is caught by the first, because the displaced
// pre-linter plan then enters the linted set and fails.
private let scriptPath = ".github/scripts/lint-plan-assertions.sh"
private let plansDirectory = "docs/superpowers/plans"
private let expectedExemptCount = 56
private let exemptionCutoff = "2026-09-04"

// NOTE (Ruling F1): runProcess(_:_:stdin:) is declared with labels in the order
// (stdout:, stderr:, exitCode:). Swift treats labelled tuples whose labels differ in
// ORDER as distinct types, so runScript's own return type must use the SAME order --
// otherwise `return try runProcess(...)` below is a compile error. Every call site
// still addresses members by name (result.exitCode, result.stdout, result.stderr), so
// nothing else about the brief's shape changes.
private func runScript(_ arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
    let script = repositoryRoot().appendingPathComponent(scriptPath)
    return try runProcess(URL(fileURLWithPath: "/usr/bin/env"),
                          ["bash", script.path] + arguments, stdin: "")
}

final class PlanLintTests: XCTestCase {
    // G12, and the check that closes the swap. Every non-exempt plan must lint clean.
    func testEveryNonExemptPlanLintsClean() throws {
        let result = try runScript([])
        XCTAssertEqual(
            result.exitCode, 0,
            "\(scriptPath) reported violations. Fix the plan, not the rule.\n"
                + "--- stdout ---\n\(result.stdout)\n--- stderr ---\n\(result.stderr)")
        XCTAssertTrue(
            result.stdout.contains("lint=pass"),
            "no lint=pass line — the linter may have degenerated into a no-op\n\(result.stdout)")
        // Ruling F8: exit 0 + "lint=pass" alone is satisfied by `lint=pass files=0
        // violations=0` -- a linter that linted NOTHING would still pass both checks
        // above. Parse the reported file count out of the lint=pass line and require
        // at least one file actually linted, without pinning an exact count (that
        // number changes the day a second non-exempt plan is written).
        guard let filesToken = result.stdout
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .first(where: { $0.hasPrefix("files=") })
        else {
            XCTFail("no files= token on the lint=pass line — cannot confirm the run "
                + "was not vacuous\n\(result.stdout)")
            return
        }
        let filesCount = Int(filesToken.dropFirst("files=".count))
        XCTAssertNotNil(filesCount, "files= token did not parse as an integer: \(filesToken)")
        XCTAssertTrue(
            (filesCount ?? 0) >= 1,
            "lint=pass reported files=0 — a zero-file run is a vacuous pass, not "
                + "evidence the linter actually checked anything\n\(result.stdout)")
    }

    // G20. The seam must READ the live array, not restate it: a seam that restated its
    // subject would make every check below prove only that the seam agrees with itself --
    // D-26's two-awk-programs residual in a new place.
    func testExemptListHasExactlyTheExpectedCount() throws {
        let result = try runScript(["--list-exempt"])
        XCTAssertEqual(result.exitCode, 0, "--list-exempt failed: \(result.stderr)")
        let entries = result.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(
            entries.count, expectedExemptCount,
            "the exemption list holds \(entries.count) entries, want \(expectedExemptCount). "
                + "It is a RATCHET: it shrinks only by a deliberate edit that also changes "
                + "this number, and it must never grow — a new plan is written to the rules.")
    }

    // G12. Every exempt entry must name a plan that exists. A stale entry is an exemption
    // nobody can see the subject of.
    func testEveryExemptEntryExistsOnDisk() throws {
        let result = try runScript(["--list-exempt"])
        let directory = repositoryRoot().appendingPathComponent(plansDirectory)
        for entry in result.stdout.split(separator: "\n").map(String.init) {
            let path = directory.appendingPathComponent(entry).path
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: path),
                "exemption names a plan that does not exist: \(entry)")
        }
    }

    // G12, the half that stops the list from growing. A plan dated on or after the cutoff
    // was written with the linter in place and has no claim on an exemption.
    func testNoExemptEntryIsDatedOnOrAfterTheCutoff() throws {
        let result = try runScript(["--list-exempt"])
        for entry in result.stdout.split(separator: "\n").map(String.init) {
            XCTAssertTrue(
                String(entry.prefix(10)) < exemptionCutoff,
                "\(entry) is dated on or after \(exemptionCutoff), when the linter landed. "
                    + "Plans from that date on are written to the rules; the exemption set "
                    + "covers only plans written before it existed.")
        }
    }
}
