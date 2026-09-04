import Foundation
import XCTest

// The ledger is a GitHub-flavored Markdown table, and GFM does NOT protect a pipe inside
// a code span: a literal `|` splits the cell wherever it appears, so `\|` is the only
// correct spelling. Slice 55b found D-9 and D-27 rendering with 7 and 10 cells instead of
// 5 -- and D-9's STATUS column, the one the escalation rule reads, therefore read as the
// tail of a code span instead of `scheduled(slice-56)`. The rows were repaired then; what
// was missing, and is what this file supplies, is the check.
private let ledgerPath = "docs/superpowers/debt-ledger.md"
private let expectedPipesPerRow = 6      // five columns
private let headerRow = "| id | born | severity | statement | status |"
private let separatorRow = "|---|---|---|---|---|"
private let knownStatusPrefixes = [
    "open", "discharged(", "scheduled(", "deferred(", "accepted-risk",
]

// A pipe is escaped by an ODD number of immediately preceding backslashes, not by a
// one-character lookback: `\|` (one backslash) escapes, but `\\|` (two) is an escaped
// backslash followed by a REAL separator, `\\\|` (three) escapes again, and so on. A
// lookback of exactly one character cannot tell `\|` and `\\|` apart -- it calls both
// "escaped", which is a false negative on the second case. So both helpers below track
// the length of the run of backslashes immediately before each `|` and test its parity.
private func unescapedPipeCount(_ line: String) -> Int {
    var count = 0
    var backslashRun = 0
    for character in line {
        if character == "|" {
            if backslashRun % 2 == 0 { count += 1 }
            backslashRun = 0
        } else {
            backslashRun = character == "\\" ? backslashRun + 1 : 0
        }
    }
    return count
}

// Split on unescaped pipes only, dropping the empty head and tail a `| a | b |` row
// produces. `\|` inside a code span is the CORRECT escape and must not split; `\\|`
// (an escaped backslash followed by a real pipe) must. See the parity-rule comment above
// `unescapedPipeCount` -- this helper applies the identical rule and must stay in
// agreement with it, since `testEveryStatusCellStartsWithAKnownStatus` silently skips any
// row where the two disagree on column count.
private func columns(of line: String) -> [String] {
    var cells: [String] = []
    var current = ""
    var backslashRun = 0
    for character in line {
        if character == "|" {
            if backslashRun % 2 == 0 {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
            backslashRun = 0
        } else {
            current.append(character)
            backslashRun = character == "\\" ? backslashRun + 1 : 0
        }
    }
    cells.append(current)
    if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
    if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
    return cells.map { $0.trimmingCharacters(in: .whitespaces) }
}

private func tableLines() throws -> [String] {
    let url = repositoryRoot().appendingPathComponent(ledgerPath)
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.components(separatedBy: "\n").filter { $0.hasPrefix("|") }
}

final class DebtLedgerShapeTests: XCTestCase {
    // G13. Five columns per row, counted on UNESCAPED pipes so a correctly escaped `\|`
    // inside a code span passes and a raw one fails -- which is the actual defect.
    func testEveryRowHasExactlyFiveColumns() throws {
        let lines = try tableLines()
        XCTAssertFalse(lines.isEmpty, "\(ledgerPath): no table found")
        for line in lines where line.hasPrefix("| D-") {
            let pipes = unescapedPipeCount(line)
            let id = columns(of: line).first ?? "?"
            XCTAssertEqual(
                pipes, expectedPipesPerRow,
                "\(ledgerPath): row \(id) carries \(pipes) unescaped pipes, want "
                    + "\(expectedPipesPerRow) (five columns). A literal `|` inside a code "
                    + "span splits the cell in GFM — write it `\\|`. This is not cosmetic: "
                    + "a split row shifts the STATUS column, which the escalation rule reads.")
        }
    }

    // G21, half one. The table's EXTENT. A row whose id cell is mangled stops matching
    // `| D-` and would leave the checked set silently -- the same one-level-up hole the
    // workflow's whole-file `--gate` census closes for gate steps.
    func testTheTableIsHeaderSeparatorAndIdRowsOnly() throws {
        let lines = try tableLines()
        guard lines.count >= 2 else {
            return XCTFail("\(ledgerPath): table has fewer than two lines")
        }
        XCTAssertEqual(lines[0], headerRow, "\(ledgerPath): unexpected header row")
        XCTAssertEqual(lines[1], separatorRow, "\(ledgerPath): unexpected separator row")
        for (offset, line) in lines.dropFirst(2).enumerated() {
            XCTAssertTrue(
                line.hasPrefix("| D-"),
                "\(ledgerPath): table body line \(offset + 3) does not start with `| D-`: "
                    + "\(line.prefix(60))… — a row that stops matching leaves every other "
                    + "check in this file silently, which is exactly how an unchecked row hides")
        }
    }

    // G21, half two. Ids unique AND contiguous from D-1. Contiguity is what makes a
    // deleted row visible: the ledger is append-only ("append rows; never delete — flip
    // status instead"), so a gap means a row was removed rather than discharged.
    func testRowIdsAreUniqueAndContiguousFromOne() throws {
        let lines = try tableLines().filter { $0.hasPrefix("| D-") }
        var numbers: [Int] = []
        for line in lines {
            guard let id = columns(of: line).first,
                  let number = Int(id.dropFirst(2)), id.hasPrefix("D-") else {
                XCTFail("\(ledgerPath): unparseable id cell in: \(line.prefix(60))…")
                continue
            }
            numbers.append(number)
        }
        // `Array(1...numbers.count)` traps (`Range requires lowerBound <= upperBound`) when
        // `numbers` is empty, which would abort the whole `swift test` binary instead of
        // reporting one clean red -- guard it the same way the sibling test above guards its
        // own degenerate case.
        guard !numbers.isEmpty else {
            return XCTFail(
                "\(ledgerPath): no `| D-` rows found; the table is gone or its id cells no "
                    + "longer match")
        }
        XCTAssertEqual(
            numbers, Array(1...numbers.count),
            "\(ledgerPath): ids must run D-1…D-\(numbers.count) with no gaps and no "
                + "repeats. The ledger is append-only, so a gap means a row was deleted "
                + "instead of having its status flipped.")
    }

    // G13, status half. The status column is what the escalation rule reads, so its
    // vocabulary is pinned: an unparseable status is indistinguishable from `open` to a
    // human skimming, and from nothing at all to a script.
    func testEveryStatusCellStartsWithAKnownStatus() throws {
        let lines = try tableLines().filter { $0.hasPrefix("| D-") }
        for line in lines {
            let cells = columns(of: line)
            guard cells.count == 5 else { continue }   // shape is the other test's failure
            let id = cells[0]
            let status = cells[4]
            XCTAssertFalse(status.isEmpty, "\(ledgerPath): \(id) has an empty status cell")
            let known = knownStatusPrefixes.contains { status.hasPrefix($0) }
                || knownStatusPrefixes.contains { status.hasPrefix("**\($0)") }
            XCTAssertTrue(
                known,
                "\(ledgerPath): \(id)'s status starts with \(status.prefix(40))…, which is "
                    + "none of \(knownStatusPrefixes). The header of this file lists the "
                    + "legal statuses; the escalation rule reads this cell.")
        }
    }

    // Covers Finding 1 from the slice-56 Task 3 fix round: the escape rule must count the
    // RUN of backslashes immediately preceding a pipe, not just one character back. Two
    // consecutive backslashes are an escaped backslash in GFM, so the pipe that follows
    // them is a REAL separator -- a one-character lookback calls it escaped instead (a
    // false negative), which is exactly the `\\|` case below. `unescapedPipeCount` and
    // `columns(of:)` are file-private, so this test reaches them directly on synthetic
    // strings rather than through the committed ledger.
    func testEscapeParityHandlesRunsOfBackslashes() throws {
        // A raw `|` is a real separator.
        XCTAssertEqual(unescapedPipeCount("a|b"), 1)
        XCTAssertEqual(columns(of: "a|b"), ["a", "b"])

        // `\|` (one backslash, odd run) is escaped -- not a separator.
        XCTAssertEqual(unescapedPipeCount("a\\|b"), 0)
        XCTAssertEqual(columns(of: "a\\|b"), ["a\\|b"])

        // `\\|` (two backslashes, even run) is an escaped backslash followed by a REAL
        // separator. This is the case a one-character lookback gets wrong.
        XCTAssertEqual(unescapedPipeCount("a\\\\|b"), 1)
        XCTAssertEqual(columns(of: "a\\\\|b"), ["a\\\\", "b"])

        // The two helpers must agree: for a well-formed row, pipe count is column count + 1
        // (the leading/trailing pipes produce two boundary cells that get trimmed away).
        let wellFormed = "| a | b |"
        XCTAssertEqual(unescapedPipeCount(wellFormed), columns(of: wellFormed).count + 1)
    }
}
