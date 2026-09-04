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

private func unescapedPipeCount(_ line: String) -> Int {
    var count = 0
    var previous: Character?
    for character in line {
        if character == "|", previous != "\\" { count += 1 }
        previous = character
    }
    return count
}

// Split on unescaped pipes only, dropping the empty head and tail a `| a | b |` row
// produces. `\|` inside a code span is the CORRECT escape and must not split.
private func columns(of line: String) -> [String] {
    var cells: [String] = []
    var current = ""
    var previous: Character?
    for character in line {
        if character == "|", previous != "\\" {
            cells.append(current)
            current = ""
        } else {
            current.append(character)
        }
        previous = character
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
}
