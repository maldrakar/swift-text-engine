import Foundation
import XCTest

// The linter is an AUTHORING tool -- it is run while a plan is still being written and not
// yet committed, which is why it is a script and not only a test. This file is the other
// half: it makes running it non-optional, and it pins the exemption RATCHET.
//
// The ratchet is pinned by property, not by copying 56 filenames into Swift. Four checks,
// each closing a different way the list could rot, and jointly load-bearing -- none is
// redundant with any other:
//   - the script's own exit 0 over the whole (non-exempt) plans directory closes a SWAP
//     that displaces an exempt plan the linter would flag DIRTY: the displaced plan
//     re-enters the linted set and fails it.
//   - testNoExemptEntryIsDatedOnOrAfterTheCutoff closes the SAME kind of swap when the
//     displaced plan happens to lint CLEAN on its own -- the exit-0 check cannot see that
//     swap at all, because the newly-linted plan passes.
//   - testExemptListHasExactlyTheExpectedCount closes a bare removal with nothing swapped
//     in (and, since fix round 1, a duplicated entry masquerading as two).
//   - testEveryExemptEntryExistsOnDisk closes a phantom entry that never displaced
//     anything real.
//
// Which of the first two binds depends on the dirty/clean split of the exempt set, and
// that split is a property of the CURRENT rule set, not an invariant: it moves whenever a
// rule is added, widened, or repaired. It is therefore RE-DERIVED, never transcribed --
//
//   for f in $(.github/scripts/lint-plan-assertions.sh --list-exempt); do \
//     .github/scripts/lint-plan-assertions.sh "docs/superpowers/plans/$f" >/dev/null 2>&1 \
//       && echo clean || echo dirty; done | sort | uniq -c
//
// -- because the first version of this comment quoted a 35/21 split that the SAME BRANCH
// falsified two commits later: widening R4 to two-hash headings moved every exempt plan
// into the dirty set, and the comment went on naming 2026-08-09-wrap-row-query.md as an
// example of a clean one. Run the command; do not trust a number written here. What is
// stable, and is the reason all four checks stay, is the SHAPE: an exempt plan that lints
// dirty is closed by the exit-0 check, one that lints clean is closed by the cutoff check
// alone, and which set a given plan falls into is not fixed. At the time of writing every
// exempt plan lints dirty, so the cutoff check currently has no live inhabitant -- that is
// a fact about today's rules, not a reason to delete it.
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

// Minor 5. The cutoff check is a lexicographic string compare (`<`), not a date parse, so
// it accepts anything that sorts below "2026-09-04" -- including an undated or backdated
// name ("1999-...", "0000-...", a leading space). Since the ratchet-header comment above
// establishes this is the ONLY check standing between a swap and any exempt entry that
// lints clean, it must reject anything that is not shaped like a date before comparing it.
// Four digits, hyphen, two digits, hyphen, two digits -- nothing more, since a plan
// filename is always at least "YYYY-MM-DD-something.md".
private func isDateShaped(_ prefix: String) -> Bool {
    let chars = Array(prefix)
    guard chars.count == 10 else { return false }
    let digitPositions = [0, 1, 2, 3, 5, 6, 8, 9]
    let hyphenPositions = [4, 7]
    for index in digitPositions {
        guard let scalar = chars[index].asciiValue, scalar >= 0x30, scalar <= 0x39 else {
            return false
        }
    }
    for index in hyphenPositions where chars[index] != "-" {
        return false
    }
    return true
}

// Minor 6. Returns the first entry that appears more than once, so a duplicate-entry
// failure message can name the offender instead of just asserting a count mismatch.
private func firstDuplicate(in entries: [String]) -> String? {
    var seen = Set<String>()
    for entry in entries where !seen.insert(entry).inserted {
        return entry
    }
    return nil
}

final class PlanLintTests: XCTestCase {
    // G12, and the check that closes the swap for every exempt plan that lints dirty on
    // its own (see the file header). Every non-exempt plan must lint clean.
    func testEveryNonExemptPlanLintsClean() throws {
        let result = try runScript([])
        XCTAssertEqual(
            result.exitCode, 0,
            "\(scriptPath) reported violations. Fix the plan, not the rule.\n"
                + "--- stdout ---\n\(result.stdout)\n--- stderr ---\n\(result.stderr)")
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let lintPassLine = lines.first(where: { $0.hasPrefix("lint=pass") }) else {
            XCTFail("no lint=pass line — the linter may have degenerated into a no-op\n"
                + "\(result.stdout)")
            return
        }
        // Ruling F8, and Minor 3's follow-up fix: exit 0 + a `lint=pass` line alone is
        // satisfied by `lint=pass files=0 violations=0` -- a linter that linted NOTHING
        // would still pass both checks above. Parse the reported file count out of the
        // `lint=pass` LINE ITSELF, not out of the whole of stdout: a violation line's
        // `detail=` text could otherwise contain a " files=N " substring and be mistaken
        // for the summary. Require at least one file actually linted, without pinning an
        // exact count (that number changes the day a second non-exempt plan is written).
        guard let filesToken = lintPassLine
            .split(separator: " ")
            .first(where: { $0.hasPrefix("files=") })
        else {
            XCTFail("no files= token on the lint=pass line — cannot confirm the run "
                + "was not vacuous\n\(lintPassLine)")
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
        // Minor 6. A duplicated entry keeps this count check, the on-disk check, and the
        // cutoff check all green -- none of the three other checks can see a name listed
        // twice, only a set-vs-list count mismatch can.
        let uniqueEntries = Set(entries)
        XCTAssertEqual(
            uniqueEntries.count, entries.count,
            "the exemption list contains a duplicate entry: "
                + "\(firstDuplicate(in: entries) ?? "<unknown>"). Each plan may be exempt "
                + "at most once.")
    }

    // G12. Every exempt entry must name a plan that exists. A stale entry is an exemption
    // nobody can see the subject of.
    func testEveryExemptEntryExistsOnDisk() throws {
        let result = try runScript(["--list-exempt"])
        XCTAssertEqual(result.exitCode, 0, "--list-exempt failed: \(result.stderr)")
        let entries = result.stdout.split(separator: "\n").map(String.init)
        // Minor 4. Without this, an EMPTY --list-exempt output makes the loop below run
        // zero times and pass vacuously -- non-vacuous today only because
        // testExemptListHasExactlyTheExpectedCount happens to also run and catch the
        // shrink. This test must not depend on a sibling test to be meaningful.
        XCTAssertFalse(
            entries.isEmpty,
            "--list-exempt returned no entries — an empty list would pass this loop "
                + "vacuously")
        let directory = repositoryRoot().appendingPathComponent(plansDirectory)
        for entry in entries {
            let path = directory.appendingPathComponent(entry).path
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: path),
                "exemption names a plan that does not exist: \(entry)")
        }
    }

    // G12, the half that stops the list from growing, and (per the file header) the ONLY
    // check that closes a swap displacing an exempt plan that lints clean on its own --
    // the swap the exit-0 check cannot see, whether or not any such plan exists today. A
    // plan dated on or after the cutoff was written with the linter in place and has no
    // claim on an exemption.
    func testNoExemptEntryIsDatedOnOrAfterTheCutoff() throws {
        let result = try runScript(["--list-exempt"])
        XCTAssertEqual(result.exitCode, 0, "--list-exempt failed: \(result.stderr)")
        let entries = result.stdout.split(separator: "\n").map(String.init)
        // Minor 4, same vacuity as testEveryExemptEntryExistsOnDisk above.
        XCTAssertFalse(
            entries.isEmpty,
            "--list-exempt returned no entries — an empty list would pass this loop "
                + "vacuously")
        for entry in entries {
            let datePrefix = String(entry.prefix(10))
            // Minor 5: reject anything not shaped like a date before comparing it --
            // see isDateShaped's own comment for why this check in particular cannot
            // afford to accept an undated or backdated name.
            XCTAssertTrue(
                isDateShaped(datePrefix),
                "\(entry) does not start with a YYYY-MM-DD date — got \"\(datePrefix)\". "
                    + "The cutoff comparison only means anything against an actual date.")
            XCTAssertTrue(
                datePrefix < exemptionCutoff,
                "\(entry) is dated on or after \(exemptionCutoff), when the linter landed. "
                    + "Plans from that date on are written to the rules; the exemption set "
                    + "covers only plans written before it existed.")
        }
    }
}
