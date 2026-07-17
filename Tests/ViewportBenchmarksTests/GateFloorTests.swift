// Foundation is imported HERE, in the test target, purely to read the corpus file
// off disk. Sources/ViewportBenchmarks stays Foundation-free; a test-target import
// cannot change that, and the XCTest runtime already links Foundation anyway.
import Foundation
import XCTest
@testable import ViewportBenchmarks

// The 3x floor is the half of the band the runtime gate CANNOT check: the gate sees
// only budget vs. THIS run's latency, so it catches an inflated budget (headroom above
// the ceiling) but is blind to a budget that sits too close to the worst hosted sample.
// That blindness is what makes a blocking gate go red on a clean tree from runner noise.
// Until this test existed the floor was verified exactly once, by hand, into a table in
// the verification record -- and a corpus append or one mistyped constant could undo it
// with nothing objecting. AGENTS.md "## Gate budgets" states the band; this pins it.
private let floorFactor: Int64 = 3

private let corpusPath = "docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv"

// Trailing window: hold budgets to 3x the max over only the most-recent N distinct
// runs, not all corpus history, so an aged-out freak releases the budget it inflated.
// This N is the same value as WINDOW= in .github/scripts/derive-gate-budgets.sh and is
// pinned to it by testWindowConstantMatchesDeriveScript(); AGENTS.md documents the one N.
private let windowSize = 20

// The N most-recent run ids by value. GitHub databaseId is monotonic with run creation,
// so "largest N ids" is "most-recent N runs" -- the exact set `sort -rnu | head -N`
// produces in the derive script. Dedups first (a run contributes many rows).
func mostRecentRunIDs(_ ids: [Int64], limit: Int) -> Set<Int64> {
    Set(Set(ids).sorted(by: >).prefix(limit))
}

private struct CorpusExtremes {
    var maxP95: Int64 = 0
    var maxP99: Int64 = 0
    var sampleCount = 0
}

private func repositoryRoot() -> URL {
    // .../Tests/ViewportBenchmarksTests/GateFloorTests.swift -> repo root
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

// key -> "<mode>|<scenario>", matching the derivation script's grouping exactly.
private func loadCorpus() throws -> [String: CorpusExtremes] {
    let url = repositoryRoot().appendingPathComponent(corpusPath)
    let text = try String(contentsOf: url, encoding: .utf8)
    return corpusExtremes(from: text, windowSize: windowSize)
}

// Pure so a fixture can exercise it. Two passes: collect distinct run ids, keep the
// most-recent `windowSize`, then fold only rows in that window into the extremes --
// the identical rule .github/scripts/derive-gate-budgets.sh applies in awk.
//
// private: CorpusExtremes is a private struct, so a function returning [String:
// CorpusExtremes] cannot be more visible than private either. Its callers (loadCorpus
// and the fixture test below) are both in this file, so file-scope private reaches them.
private func corpusExtremes(from text: String, windowSize: Int) -> [String: CorpusExtremes] {
    struct Row { let runID: Int64; let key: String; let p95: Int64; let p99: Int64 }

    var rows: [Row] = []
    var runIDs: [Int64] = []
    for (index, line) in text.split(separator: "\n").enumerated() {
        if index == 0 { continue }  // header
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count == 5,
              let runID = Int64(columns[0]),
              let p95 = Int64(columns[3]),
              let p99 = Int64(columns[4]) else {
            XCTFail("malformed corpus row \(index + 1): \(line)")
            continue
        }
        runIDs.append(runID)
        rows.append(Row(runID: runID, key: "\(columns[1])|\(columns[2])", p95: p95, p99: p99))
    }

    let window = mostRecentRunIDs(runIDs, limit: windowSize)
    var extremes: [String: CorpusExtremes] = [:]
    for row in rows where window.contains(row.runID) {
        var entry = extremes[row.key] ?? CorpusExtremes()
        entry.maxP95 = max(entry.maxP95, row.p95)
        entry.maxP99 = max(entry.maxP99, row.p99)
        entry.sampleCount += 1
        extremes[row.key] = entry
    }
    return extremes
}

struct GatedBudget {
    let key: String
    let p95: Int64
    let p99: Int64
}

// Every scenario any --gate mode enforces. The mode key comes from BenchmarkMode's own
// outputName, so it cannot drift from what the benchmark prints and the corpus records.
//
// This is THE registry of gated scenarios for the whole test target, not just for the
// floor test: GateLogicTests' p99 >= 2 * p95 invariant iterates it too. Both halves of
// the band therefore see the same list, and a new gated mode is registered here once.
// It was two hand-maintained lists until they drifted — the second one shipped missing a
// table that was already gated — so do not grow a second copy.
func everyGatedBudget() -> [GatedBudget] {
    var budgets: [GatedBudget] = []
    func add(_ mode: BenchmarkMode, _ name: String, _ p95: Int64, _ p99: Int64) {
        budgets.append(GatedBudget(key: "\(mode.outputName)|\(name)", p95: p95, p99: p99))
    }

    for s in benchmarkScenarios() {
        add(.pipeline, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in realisticProviderScenarios() {
        add(.realisticProvider, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in variableHeightScenarios() {
        add(.variableHeight, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in variableHeightMutationScenarios() {
        add(.variableHeightMutation, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in structuralMutationScenarios() {
        add(.structuralMutation, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in bulkStructuralMutationScenarios() {
        add(.bulkStructuralMutation, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in lineQueryScenarios() {
        add(.lineQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in lineGeometryQueryScenarios() {
        add(.lineGeometryQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in columnQueryScenarios() {
        add(.columnQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in columnGeometryQueryScenarios() {
        add(.columnGeometryQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in pointQueryScenarios() {
        add(.pointQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in pointGeometryQueryScenarios() {
        add(.pointGeometryQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    return budgets
}

final class GateFloorTests: XCTestCase {

    // Closes the loop between the two halves of the registry. `BenchmarkMode.isGateable`
    // decides which modes `--gate` ACCEPTS; `everyGatedBudget()` is the hand-written list
    // of what the band then CHECKS. Nothing but this test makes the second track the
    // first: a new gateable mode whose `for s in ...Scenarios()` loop was never added
    // would be gate-accepting, budget-bearing, and invisible to both the 3x floor and the
    // p99 >= 2 * p95 invariant. That drift is not hypothetical -- it happened inside this
    // branch (3673a43 covered eleven tables and missed the gated twelfth; a5ff213 fixed
    // it), back when the miss could only be caught by eye.
    func testEveryGateableModeIsRegistered() {
        let registeredModes = Set(everyGatedBudget().map { $0.key.split(separator: "|")[0] })

        for mode in BenchmarkMode.allCases where mode.isGateable {
            XCTAssertTrue(
                registeredModes.contains(Substring(mode.outputName)),
                "\(mode.outputName): --gate accepts this mode, but everyGatedBudget() "
                    + "registers no scenario for it — add its scenarios loop there, or make "
                    + "BenchmarkMode.isGateable return false for it")
        }
    }

    // The converse: a mode that is NOT gateable must not smuggle budgets into the band
    // either, or the floor test would hold a scenario to hosted evidence that no gate
    // will ever read.
    func testNoUngateableModeIsRegistered() {
        let registeredModes = Set(everyGatedBudget().map { $0.key.split(separator: "|")[0] })

        for mode in BenchmarkMode.allCases where !mode.isGateable {
            XCTAssertFalse(
                registeredModes.contains(Substring(mode.outputName)),
                "\(mode.outputName): registered in everyGatedBudget(), but --gate rejects it")
        }
    }

    // A budget with no hosted evidence behind it is a hand-typed budget, whatever else
    // it is. --realistic-provider was exactly that until its samples were harvested:
    // a gated mode the corpus had never seen, whose budget nothing could re-derive.
    func testEveryGatedScenarioHasCorpusEvidence() throws {
        let corpus = try loadCorpus()
        let budgets = everyGatedBudget()
        XCTAssertFalse(budgets.isEmpty)

        for budget in budgets {
            XCTAssertNotNil(
                corpus[budget.key],
                "\(budget.key): gated, but the corpus carries no hosted sample for it — "
                    + "harvest it with .github/scripts/harvest-gate-corpus.sh and re-derive")
        }
    }

    // The floor covers BOTH statistics because the gate fails on either one. A budget
    // that clears 3x on p95 and 1.5x on p99 flakes just as reliably as the reverse.
    func testEveryGatedBudgetClearsTheFloorOnBothStatistics() throws {
        let corpus = try loadCorpus()

        for budget in everyGatedBudget() {
            guard let observed = corpus[budget.key] else {
                continue  // reported by testEveryGatedScenarioHasCorpusEvidence
            }

            XCTAssertGreaterThanOrEqual(
                budget.p95, floorFactor * observed.maxP95,
                "\(budget.key): p95 budget \(budget.p95) is below \(floorFactor)x the worst "
                    + "hosted p95 (\(observed.maxP95), n=\(observed.sampleCount)) — it will go "
                    + "red on a clean tree; re-derive with .github/scripts/derive-gate-budgets.sh")

            XCTAssertGreaterThanOrEqual(
                budget.p99, floorFactor * observed.maxP99,
                "\(budget.key): p99 budget \(budget.p99) is below \(floorFactor)x the worst "
                    + "hosted p99 (\(observed.maxP99), n=\(observed.sampleCount)) — it will go "
                    + "red on a clean tree; re-derive with .github/scripts/derive-gate-budgets.sh")
        }
    }

    func testMostRecentRunIDsKeepsTopNByValue() {
        let ids: [Int64] = [100, 305, 210, 99, 305]   // 305 duplicated: distinct-by-value
        XCTAssertEqual(mostRecentRunIDs(ids, limit: 2), Set<Int64>([305, 210]))
        // limit >= distinct count is a no-op (keep all distinct ids)
        XCTAssertEqual(mostRecentRunIDs(ids, limit: 10), Set<Int64>([100, 305, 210, 99]))
        XCTAssertEqual(mostRecentRunIDs(ids, limit: 4), Set<Int64>([100, 305, 210, 99]))
        XCTAssertTrue(mostRecentRunIDs([], limit: 5).isEmpty)
    }

    func testWindowedExtremesDropAnAgedOutFreak() {
        // Header + rows: run 500 (newest) is clean; run 100 (oldest) carries a freak.
        let corpus = """
        run_id\tmode\tscenario\tp95_ns\tp99_ns
        500\tline_query\tuniform_1k\t30\t60
        400\tline_query\tuniform_1k\t32\t64
        300\tline_query\tuniform_1k\t31\t62
        100\tline_query\tuniform_1k\t999\t999
        """
        // Window of 3 keeps {500,400,300}: the 999 freak in run 100 is aged out.
        let windowed = corpusExtremes(from: corpus, windowSize: 3)["line_query|uniform_1k"]
        XCTAssertEqual(windowed?.maxP95, 32)
        XCTAssertEqual(windowed?.maxP99, 64)
        // Window wide enough to still include run 100: the freak is (correctly) retained.
        let all = corpusExtremes(from: corpus, windowSize: 10)["line_query|uniform_1k"]
        XCTAssertEqual(all?.maxP95, 999)
        XCTAssertEqual(all?.maxP99, 999)
    }
}
