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

// The verdict values the derivation REFUSES. Classified by what happened to the
// MEASUREMENT, not by whether the gate passed: `budget_exceeded` and
// `budget_absolute_exceeded` mean the sample was SLOW -- the regression-laundering case,
// where one bad row sets a looser budget through the 3x-max term and
// testEveryCommittedBudgetReproducesFromCorpus then REQUIRES that looser budget to be
// committed. `operation_failures` means the timed path was degenerate, so the number
// measures nothing.
//
// `budget_stale` is admitted ON PURPOSE. It means the measurement was FAST enough that
// headroom breached its ceiling, and AGENTS.md's prescribed response is "re-derive from
// fresh hosted evidence" -- which requires harvesting exactly these rows. A filter that
// dropped them would instruct the operator to re-derive and simultaneously refuse to
// collect the evidence.
//
// Pinned byte-for-byte against REJECTED_VERDICTS in .github/scripts/derive-gate-budgets.sh
// by testAdmissibleRowsMatchDeriveScript -- the third cross-language pin, beside the two
// window pins. That pin covers AGREEMENT, not correctness: if both sides gain the same
// wrong entry, nothing notices.
let rejectedVerdicts: Set<String> = [
    "budget_exceeded",
    "budget_absolute_exceeded",
    "operation_failures",
]

// An EMPTY verdict is a legacy five-column row, admitted as "unknown": the committed corpus
// consists entirely of those, and the corpus is append-only, so they are never rewritten.
func isAdmissibleVerdict(_ verdict: String) -> Bool { !rejectedVerdicts.contains(verdict) }

// The verdict a corpus row carries, single-sourced across BOTH Swift readers.
//
// They are two: `admissibleCorpusRows` (the seam testAdmissibleRowsMatchDeriveScript
// drives) and `corpusExtremes` (what the floor check actually reads). They wrote this
// extraction independently and disagreed on the column-count rule -- `>= 6` against
// `== 6` -- which is the seam-versus-production divergence D-26(b) records on the shell
// side, one language over. Unreachable today (a harvest writes exactly six columns), and
// unreachable is not the same as pinned.
//
// A legacy five-column row has no verdict and reads as "" -- admitted as unknown, which
// is what the whole committed corpus depends on. A row WIDER than six is not a shape any
// harvest produces; it reads as "" here too, and `corpusExtremes` rejects it as malformed
// separately. That judgement stays there on purpose: this function answers "which verdict
// does this row carry", not "is this row well-formed".
func corpusVerdict(_ columns: [Substring]) -> String {
    columns.count == 6 ? String(columns[5]) : ""
}

// Corpus text -> the raw rows the derivation admits, header excluded, in input order.
// VERDICT FILTER ONLY -- windowing is a separate axis, pinned by the two window pins, and
// the shell seam this is compared against (`--admissible-rows`) does not window either.
// Returns the lines verbatim so the cross-language comparison is over bytes, not over a
// re-parse that could paper over a field-splitting disagreement.
func admissibleCorpusRows(from text: String) -> [String] {
    var admitted: [String] = []
    for (index, line) in text.split(separator: "\n").enumerated() {
        if index == 0 { continue }  // header
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        let verdict = corpusVerdict(columns)
        if isAdmissibleVerdict(verdict) { admitted.append(String(line)) }
    }
    return admitted
}

private struct CorpusExtremes {
    var maxP95: Int64 = 0
    var maxP99: Int64 = 0
    var sampleCount = 0
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
        // Five OR six: five is a legacy row (the committed corpus is entirely legacy), six
        // carries the verdict every harvest now writes. Requiring exactly six would redden
        // on the committed corpus itself; requiring exactly five would redden the moment a
        // harvested row lands -- which is what forced this reader to learn the column
        // BEFORE the harvester started writing it (spec Decision 6).
        guard columns.count == 5 || columns.count == 6,
              let runID = Int64(columns[0]),
              let p95 = Int64(columns[3]),
              let p99 = Int64(columns[4]) else {
            XCTFail("malformed corpus row \(index + 1): \(line)")
            continue
        }
        // The run id is recorded BEFORE the verdict filter: the window is verdict-blind
        // (spec Decision 8), exactly as the shell's `cut -f1 | sort -rnu | head` is, so a
        // run whose every row is rejected still consumes a window slot.
        runIDs.append(runID)
        let verdict = corpusVerdict(columns)
        guard isAdmissibleVerdict(verdict) else { continue }
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

// Parse derive-gate-budgets.sh stdout into key -> (p95, p99). Each scenario line is
// `<key>  n=... p95[...] p99[...] budget_p95=<int> budget_p99=<int> gov_p95=<median|max>
// margin...` (the key is %-46s-padded, so field 0 is the key with no embedded spaces, and
// the two budgets are whitespace-delimited `budget_p9x=<int>` tokens). A line missing
// either budget token is skipped:
// combined with the "every gated key must be present" assertion in the test, that turns any
// rename/removal of those output tokens into a loud missing-key failure, not a silent pass --
// so the test transitively pins the derive script's output shape as well as its arithmetic.
private func derivedBudgets(fromScriptOutput output: String) -> [String: (p95: Int64, p99: Int64)] {
    var result: [String: (p95: Int64, p99: Int64)] = [:]
    for line in output.split(separator: "\n") {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let key = fields.first else { continue }
        var p95: Int64?
        var p99: Int64?
        for field in fields {
            if field.hasPrefix("budget_p95=") {
                p95 = Int64(field.dropFirst("budget_p95=".count))
            } else if field.hasPrefix("budget_p99=") {
                p99 = Int64(field.dropFirst("budget_p99=".count))
            }
        }
        if let p95, let p99 {
            result[String(key)] = (p95: p95, p99: p99)
        }
    }
    return result
}

struct GatedBudget {
    let key: String
    let mode: BenchmarkMode
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
        budgets.append(GatedBudget(key: "\(mode.outputName)|\(name)", mode: mode, p95: p95, p99: p99))
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

    // The corpus schema's sixth column, and the back-compatibility claim, in one fixture.
    //
    // Five-column rows are LEGACY: the committed corpus consists entirely of them, and no
    // harvest produces them any more. An absent verdict means "unknown", which is admitted --
    // rejecting them would discard the whole corpus. Drill 5 mutates the reader to require
    // exactly six columns; the legacy row here is what reddens.
    //
    // The rejected rows still contribute their run ids to the WINDOW (spec Decision 8): the
    // verdict filter applies to row admission, after windowing, so neither window pin is
    // touched. Run 500 below is rejected on both its rows yet still occupies a window slot.
    func testSixColumnRowsAreReadAndFilteredByVerdict() {
        let corpus = """
        run_id\tmode\tscenario\tp95_ns\tp99_ns\tverdict
        500\tline_query\tuniform_1k\t900\t900\tbudget_exceeded
        500\tline_query\tuniform_1k\t901\t901\toperation_failures
        400\tline_query\tuniform_1k\t32\t64\tpass
        300\tline_query\tuniform_1k\t31\t62\tbudget_stale
        200\tline_query\tuniform_1k\t30\t60\tmissing_budget
        100\tline_query\tuniform_1k\t29\t58\tnone
        50\tline_query\tuniform_1k\t28\t56
        """

        // Window of 10 covers every run: what is dropped is dropped by VERDICT, not by age.
        let all = corpusExtremes(from: corpus, windowSize: 10)["line_query|uniform_1k"]
        XCTAssertEqual(all?.maxP95, 32, "a budget_exceeded row must not set the observed max")
        XCTAssertEqual(all?.maxP99, 64)
        XCTAssertEqual(all?.sampleCount, 5, "pass, budget_stale, missing_budget, none, legacy")

        // Window of 2 keeps runs {500, 400}. Run 500's rows are both rejected, so it
        // consumes a slot and contributes nothing -- the accepted cost in Decision 8.
        let windowed = corpusExtremes(from: corpus, windowSize: 2)["line_query|uniform_1k"]
        XCTAssertEqual(windowed?.maxP95, 32)
        XCTAssertEqual(windowed?.sampleCount, 1)
    }

    // The reject set itself, stated as a truth table so that adding or removing a case is a
    // deliberate edit against a list, not a silent set-literal change. Classified by what
    // happened to the MEASUREMENT, not by whether the gate passed.
    func testRejectSetIsExactlyThreeReasons() {
        XCTAssertEqual(rejectedVerdicts.count, 3)
        XCTAssertFalse(isAdmissibleVerdict("budget_exceeded"))         // slow
        XCTAssertFalse(isAdmissibleVerdict("budget_absolute_exceeded")) // slow, above the 60 FPS ceiling
        XCTAssertFalse(isAdmissibleVerdict("operation_failures"))       // degenerate timed path
        XCTAssertTrue(isAdmissibleVerdict("budget_stale"))              // FAST -- its fix NEEDS this data
        XCTAssertTrue(isAdmissibleVerdict("missing_budget"))            // valid, merely unjudgeable
        XCTAssertTrue(isAdmissibleVerdict("none"))                      // printed without --gate
        XCTAssertTrue(isAdmissibleVerdict(""))                          // legacy five-column row
    }

    // The two Swift corpus readers must admit the SAME rows.
    //
    // `admissibleCorpusRows` is the seam testAdmissibleRowsMatchDeriveScript drives across
    // languages; `corpusExtremes` is what the floor check actually reads. Nothing forced
    // them equal, and they had already drifted once on the column-count rule (`>= 6`
    // against `== 6`) -- the seam-versus-production shape D-26(b) records for the shell's
    // two awk programs, one language over. `corpusVerdict` is now their single source, and
    // this is the test that would notice a second one reappearing: without it, the
    // cross-language pin could be pinning a rule the floor check does not apply.
    //
    // One mode|scenario throughout so `sampleCount` and the row count are comparable, and a
    // window wider than the run count so nothing here is dropped by age rather than verdict.
    func testTheTwoCorpusReadersAdmitTheSameRows() {
        let corpus = """
        run_id\tmode\tscenario\tp95_ns\tp99_ns\tverdict
        908\tline_query\tuniform_1k\t20\t40\tpass
        907\tline_query\tuniform_1k\t21\t41\tbudget_exceeded
        906\tline_query\tuniform_1k\t22\t42\tbudget_absolute_exceeded
        905\tline_query\tuniform_1k\t23\t43\toperation_failures
        904\tline_query\tuniform_1k\t24\t44\tbudget_stale
        903\tline_query\tuniform_1k\t25\t45\tmissing_budget
        902\tline_query\tuniform_1k\t26\t46\tnone
        901\tline_query\tuniform_1k\t27\t47
        """

        let seamRows = admissibleCorpusRows(from: corpus)
        let production = corpusExtremes(from: corpus, windowSize: 20)["line_query|uniform_1k"]

        XCTAssertEqual(
            production?.sampleCount, seamRows.count,
            "the pinned seam and the floor reader admit different row sets -- the "
                + "cross-language pin would then be pinning a rule the floor check does "
                + "not apply")

        // Non-vacuity: neither reader admits everything, nor nothing.
        XCTAssertEqual(seamRows.count, 5, "pass, budget_stale, missing_budget, none, legacy")
    }

    // Pins the ONE documented N across languages. derive-gate-budgets.sh computes the
    // window in awk, GateFloorTests in Swift; nothing else forces them equal. The
    // asymmetric self-guard (Decision 3) catches only test-N > derive-N; this catches
    // the silent-pass direction too. Reads the bare `WINDOW=<int>` assignment by prefix.
    func testWindowConstantMatchesDeriveScript() throws {
        let scriptURL = repositoryRoot()
            .appendingPathComponent(".github/scripts/derive-gate-budgets.sh")
        let text = try String(contentsOf: scriptURL, encoding: .utf8)

        let assignment = text.split(separator: "\n").first { $0.hasPrefix("WINDOW=") }
        guard let assignment else {
            XCTFail("derive-gate-budgets.sh has no top-level `WINDOW=` assignment for the "
                + "pin test to read")
            return
        }
        let digits = assignment.dropFirst("WINDOW=".count).prefix { $0.isNumber }
        guard let scriptWindow = Int(digits) else {
            XCTFail("could not parse an integer from `\(assignment)`")
            return
        }

        XCTAssertEqual(
            scriptWindow, windowSize,
            "WINDOW=\(scriptWindow) in derive-gate-budgets.sh disagrees with windowSize="
                + "\(windowSize) in GateFloorTests.swift — the two consumers would window "
                + "the corpus differently. Update AGENTS.md's one documented N and both sites.")
    }

    // The selection-logic analog of testWindowConstantMatchesDeriveScript: that test pins
    // the window's N CONSTANT across languages; this pins the window's SELECTION LOGIC.
    // It runs the script's real window_run_ids (via the --window-run-ids seam) over a
    // fixture and asserts its chosen run-id SET equals mostRecentRunIDs -- the function the
    // floor test derives its extremes through. Set, not ordered list: the awk KEEP filter
    // and the Swift window.contains fold both use membership, so emission order never
    // reaches the derivation (the shell --self-test covers newest-first ordering separately).
    // Closes the shell half of the "both consumers agree" invariant that the constant pin,
    // GateFloorTests, and the runtime --gate all leave open (Slice 41 review P2 #1).
    func testWindowSelectionMatchesDeriveScript() throws {
        let scriptURL = repositoryRoot()
            .appendingPathComponent(".github/scripts/derive-gate-budgets.sh")

        // Discriminating fixture: 305 and 210 each contribute two rows (a run contributes
        // many rows -> must dedup); rows are physically out of chronological order (ranking
        // is by run-id value, not row position). Distinct ids: {100, 305, 210, 99, 42}.
        // window_run_ids reads only column 1; the other columns are inert here.
        let fixtureIDs: [Int64] = [100, 305, 305, 210, 99, 210, 42]
        var corpus = "run_id\tmode\tscenario\tp95_ns\tp99_ns\n"
        for id in fixtureIDs {
            corpus += "\(id)\tm\ts\t1\t2\n"
        }

        let env = URL(fileURLWithPath: "/usr/bin/env")

        // Both regimes: N < distinct count (2, 3 drop runs) and N >= distinct count (10, no-op).
        for limit in [2, 3, 10] {
            let result = try runProcess(
                env, ["bash", scriptURL.path, "--window-run-ids", "\(limit)"], stdin: corpus)

            XCTAssertEqual(
                result.exitCode, 0,
                "derive-gate-budgets.sh --window-run-ids \(limit) exited \(result.exitCode); "
                    + "stderr: \(result.stderr)")

            let shellSet = Set(result.stdout.split(separator: "\n").compactMap { Int64($0) })
            XCTAssertEqual(
                shellSet, mostRecentRunIDs(fixtureIDs, limit: limit),
                "shell window_run_ids and Swift mostRecentRunIDs disagree at N=\(limit) — the "
                    + "two corpus consumers would window differently; re-run "
                    + "`.github/scripts/derive-gate-budgets.sh --self-test`")
        }
    }

    // The THIRD cross-language pin, beside testWindowConstantMatchesDeriveScript (the
    // window's N) and testWindowSelectionMatchesDeriveScript (the window's selection).
    // Those two cross-check WHICH ROWS are in scope; this one cross-checks WHICH ROWS ARE
    // ADMITTED. The reject set now lives in awk and in Swift, and nothing but this forces
    // them equal -- a divergence would mean the budget swift test re-derives is not the
    // budget the operator re-derives from the same corpus.
    //
    // Compared as raw LINES, not as re-parsed values: a field-splitting disagreement between
    // awk's -F'\t' and Swift's split(separator: "\t") would survive a value comparison.
    func testAdmissibleRowsMatchDeriveScript() throws {
        let scriptURL = repositoryRoot()
            .appendingPathComponent(".github/scripts/derive-gate-budgets.sh")

        // One row per verdict value the corpus can carry, plus a legacy five-column row.
        // Distinct run ids so nothing here depends on the window (this seam does not window).
        let corpus = """
        run_id\tmode\tscenario\tp95_ns\tp99_ns\tverdict
        901\tline_query\tuniform_1k\t10\t20\tpass
        902\tline_query\tuniform_1k\t11\t21\tbudget_exceeded
        903\tline_query\tuniform_1k\t12\t22\tbudget_absolute_exceeded
        904\tline_query\tuniform_1k\t13\t23\toperation_failures
        905\tline_query\tuniform_1k\t14\t24\tbudget_stale
        906\tline_query\tuniform_1k\t15\t25\tmissing_budget
        907\tline_query\tuniform_1k\t16\t26\tnone
        908\tline_query\tuniform_1k\t17\t27
        """

        let env = URL(fileURLWithPath: "/usr/bin/env")
        let result = try runProcess(
            env, ["bash", scriptURL.path, "--admissible-rows"], stdin: corpus + "\n")

        XCTAssertEqual(
            result.exitCode, 0,
            "derive-gate-budgets.sh --admissible-rows exited \(result.exitCode); "
                + "stderr: \(result.stderr)")

        let shellRows = result.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(
            shellRows, admissibleCorpusRows(from: corpus),
            "shell REJECTED_VERDICTS and Swift rejectedVerdicts disagree — the two corpus "
                + "consumers would derive different budgets from the same corpus; re-run "
                + "`.github/scripts/derive-gate-budgets.sh --self-test`")

        // Non-vacuity in BOTH directions. Without these, a seam that admitted everything
        // (or nothing) would pass as long as Swift did the same thing.
        XCTAssertEqual(shellRows.count, 5, "pass, budget_stale, missing_budget, none, legacy")
        XCTAssertTrue(
            shellRows.contains { $0.hasSuffix("\tbudget_stale") },
            "budget_stale must be ADMITTED: its prescribed fix is to re-derive from it")
        XCTAssertFalse(
            shellRows.contains { $0.hasSuffix("\tbudget_exceeded") },
            "budget_exceeded must be REJECTED: it is the regression-laundering row")
    }

    // The arithmetic analog of the two window pins. Those cross-check the window SELECTION
    // (which run ids) against Swift; this cross-checks the DERIVATION ARITHMETIC (8xmedian /
    // 3xmax / round_up_2sf, plus the p99 2xbudget_p95 floor) by asserting every committed budget
    // literal byte-equals what derive-gate-budgets.sh -- "the only sanctioned source of a budget"
    // -- actually emits from the committed corpus. It closes the last within-band-looser residual
    // in the regression recipe: a budget that has drifted looser than the recipe now produces is
    // invisible to the floor test whenever the 8xmedian term governs (the floor sees only 3xmax),
    // but reddens here. Shells out rather than re-implementing the recipe, so it also transitively
    // guards the script's awk and its output format on both BSD-awk(local) and Linux-awk(CI).
    func testEveryCommittedBudgetReproducesFromCorpus() throws {
        let scriptURL = repositoryRoot()
            .appendingPathComponent(".github/scripts/derive-gate-budgets.sh")
        let corpusURL = repositoryRoot().appendingPathComponent(corpusPath)
        let env = URL(fileURLWithPath: "/usr/bin/env")

        // The script reads the corpus from its file argument, not stdin; empty stdin is inert.
        let result = try runProcess(env, ["bash", scriptURL.path, corpusURL.path], stdin: "")
        XCTAssertEqual(
            result.exitCode, 0,
            "derive-gate-budgets.sh exited \(result.exitCode); stderr: \(result.stderr)")

        let derived = derivedBudgets(fromScriptOutput: result.stdout)
        let budgets = everyGatedBudget()

        // Non-vacuity + bijective cardinality (Decision 3). Equality (not >=) also catches the
        // REVERSE drift: a scenario that entered the corpus/derivation but is not a registered
        // gated budget. Relax to `derived.count >= budgets.count` only if a non-gated
        // (e.g. observation-only) row is ever CONSCIOUSLY added to the corpus.
        XCTAssertFalse(derived.isEmpty)
        XCTAssertEqual(
            derived.count, budgets.count,
            "derive-gate-budgets.sh emitted \(derived.count) scenarios but everyGatedBudget() "
                + "registers \(budgets.count) — a corpus scenario is unregistered (or vice versa). "
                + "If a non-gated observation row was added on purpose, relax this to >=.")

        for budget in budgets {
            guard let d = derived[budget.key] else {
                XCTFail("\(budget.key): gated, but derive-gate-budgets.sh emitted no budget for it")
                continue
            }
            XCTAssertEqual(
                d.p95, budget.p95,
                "\(budget.key): committed p95 budget \(budget.p95) != \(d.p95) re-derived from the "
                    + "corpus — the literal no longer reproduces (budget_stale, not an engine "
                    + "regression). Re-derive with .github/scripts/derive-gate-budgets.sh and re-commit.")
            XCTAssertEqual(
                d.p99, budget.p99,
                "\(budget.key): committed p99 budget \(budget.p99) != \(d.p99) re-derived from the "
                    + "corpus — the literal no longer reproduces (budget_stale, not an engine "
                    + "regression). Re-derive with .github/scripts/derive-gate-budgets.sh and re-commit.")
        }
    }

    // THIS TEST IS THE PRODUCT GATE. Under it, the runtime budget_absolute_exceeded
    // branch is unreachable: a budget below its class ceiling means any p99 above the
    // ceiling is also above the budget, and budgetExceeded is evaluated first. So the
    // moment slow drift finally produces a re-derived budget at or above a class
    // ceiling, THIS is what goes red -- at swift test time, before the gate steps in
    // the same host job ever run. The runtime reason is defense-in-depth for a tree
    // where this pin has been removed or budgets were edited without running the suite.
    //
    // Read the binding scenario and its margin from the assertion, never from a number
    // written here: the next re-derivation falsifies it.
    func testEveryGatedBudgetIsUnderItsClassCeiling() {
        let budgets = everyGatedBudget()
        XCTAssertFalse(budgets.isEmpty)

        for budget in budgets {
            let ceiling = budget.mode.absoluteCeiling
            XCTAssertLessThan(
                budget.p99, ceiling.p99Nanoseconds,
                "\(budget.key): regression p99 budget \(budget.p99) is at or above its "
                    + "\(ceiling) ceiling of \(ceiling.p99Nanoseconds) ns. This test is the "
                    + "product gate and this red IS the 60 FPS ceiling firing: fix the code "
                    + "or the architecture — NEVER loosen the ceiling, and never corpus-derive "
                    + "it (contrast budget_stale, which does say re-derive). The only other "
                    + "legitimate response is moving this mode to the other AbsoluteCeiling "
                    + "class, which is a product decision needing its own argument.")
        }
    }
}
