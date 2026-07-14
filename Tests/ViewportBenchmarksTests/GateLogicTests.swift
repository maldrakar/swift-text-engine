import XCTest
@testable import ViewportBenchmarks

private func summary(
    p95: Int64,
    p99: Int64,
    budgetP95: Int64?,
    budgetP99: Int64?,
    failures: Int = 0
) -> BenchmarkSummary {
    BenchmarkSummary(
        mode: .lineQuery,
        providerName: "uniform",
        scenarioName: "test",
        iterations: 1,
        operationsPerSample: 1,
        lineCount: 1_000,
        documentBytes: nil,
        lineBytes: nil,
        p95Nanoseconds: p95,
        p99Nanoseconds: p99,
        checksum: 0,
        failureCount: failures,
        p95BudgetNanoseconds: budgetP95,
        p99BudgetNanoseconds: budgetP99
    )
}

final class GateLogicTests: XCTestCase {

    // The bug this slice exists to repair: a budget so far above reality that no
    // regression can trip it. Latency is inside budget and nothing failed, yet the
    // gate must reject it -- the budget, not the code, is broken.
    func testInflatedBudgetFailsTheGate() {
        let s = summary(p95: 20, p99: 40, budgetP95: 60_000, budgetP99: 120_000)
        XCTAssertFalse(s.passesGate)
        XCTAssertEqual(s.gateFailureReason, .budgetStale)
    }

    func testBudgetInsideTheBandPassesTheGate() {
        let s = summary(p95: 40, p99: 70, budgetP95: 330, budgetP99: 660)
        XCTAssertTrue(s.passesGate)
        XCTAssertNil(s.gateFailureReason)
    }

    // Exactly at the ceiling is still in band; a hair past it is not.
    func testCeilingBoundaryIsInclusive() {
        let atCeiling = summary(p95: 10, p99: 20, budgetP95: 500, budgetP99: 1_000)
        XCTAssertEqual(atCeiling.headroomP95, 50.0)
        XCTAssertTrue(atCeiling.passesGate)

        let pastCeiling = summary(p95: 10, p99: 20, budgetP95: 501, budgetP99: 1_000)
        XCTAssertFalse(pastCeiling.passesGate)
        XCTAssertEqual(pastCeiling.gateFailureReason, .budgetStale)
    }

    // Same boundary, mirrored on the p99 ceiling (100.0x). p95 is kept safely
    // in-band here so only the p99 ceiling is under test.
    func testP99CeilingBoundaryIsInclusive() {
        let atCeiling = summary(p95: 10, p99: 20, budgetP95: 100, budgetP99: 2_000)
        XCTAssertEqual(atCeiling.headroomP99, 100.0)
        XCTAssertTrue(atCeiling.passesGate)

        let pastCeiling = summary(p95: 10, p99: 20, budgetP95: 100, budgetP99: 2_001)
        XCTAssertFalse(pastCeiling.passesGate)
        XCTAssertEqual(pastCeiling.gateFailureReason, .budgetStale)
    }

    // The two failures demand opposite responses, so the gate must say which it is.
    func testSlowCodeAndStaleBudgetAreDistinguished() {
        let slow = summary(p95: 400, p99: 700, budgetP95: 330, budgetP99: 660)
        XCTAssertEqual(slow.gateFailureReason, .budgetExceeded)

        let slowOnP99Only = summary(p95: 100, p99: 700, budgetP95: 330, budgetP99: 660)
        XCTAssertEqual(slowOnP99Only.gateFailureReason, .budgetExceeded)
    }

    // Budgets here are deliberately stale (would fail on their own with
    // .budgetStale), so this actually proves operationFailures outranks the
    // budget checks rather than just being the only failing branch available.
    func testOperationFailuresOutrankBudgetChecks() {
        let s = summary(p95: 20, p99: 40, budgetP95: 60_000, budgetP99: 120_000, failures: 1)
        XCTAssertEqual(s.gateFailureReason, .operationFailures)
    }

    func testMissingBudgetFailsTheGate() {
        let s = summary(p95: 40, p99: 70, budgetP95: nil, budgetP99: nil)
        XCTAssertFalse(s.passesGate)
        XCTAssertEqual(s.gateFailureReason, .missingBudget)
        XCTAssertNil(s.headroomP95)
        XCTAssertNil(s.headroomP99)
    }

    // A workload too cheap for the clock guards nothing. Must not divide by zero.
    func testZeroLatencyIsUnboundedHeadroomAndFails() {
        let s = summary(p95: 0, p99: 0, budgetP95: 330, budgetP99: 660)
        XCTAssertEqual(s.headroomP95, .infinity)
        XCTAssertEqual(s.headroomP99, .infinity)
        XCTAssertEqual(s.gateFailureReason, .budgetStale)
    }

    func testHeadroomIsBudgetOverP95() {
        XCTAssertEqual(summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 640).headroomP95, 8.0)
    }

    // headroomP99 mirrors headroomP95 exactly: budget_p99 / p99.
    func testHeadroomIsBudgetOverP99() {
        XCTAssertEqual(summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 700).headroomP99, 10.0)
    }

    // headroomP99 is nil independently of headroomP95's own presence -- a p95
    // budget alone must not make headroomP99 non-nil.
    func testHeadroomP99IsNilWithNoP99Budget() {
        let s = summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: nil)
        XCTAssertNotNil(s.headroomP95)
        XCTAssertNil(s.headroomP99)
    }

    // This is the exact hole the review found: the p95-only ceiling cannot see
    // an inflated p99 budget, so a pure-tail regression (p99 blows up while p95
    // stays steady behind an honest, in-band p95 budget) would previously pass
    // the gate. With the p99 ceiling in place it must now fail as budget_stale.
    func testInflatedP99BudgetFailsTheGateEvenWithHonestP95Budget() {
        let s = summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 1_000_000_000)
        XCTAssertLessThanOrEqual(s.headroomP95 ?? .infinity, GateLimits.maxHeadroomP95)
        XCTAssertFalse(s.passesGate)
        XCTAssertEqual(s.gateFailureReason, .budgetStale)
    }

    func testGateOutputCarriesHeadroomAndReason() {
        let passing = formatSummary(
            summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 640), includeGate: true)
        XCTAssertTrue(passing.contains(" headroom_p95=8.0x"), passing)
        XCTAssertTrue(passing.contains(" gate=pass"), passing)
        XCTAssertFalse(passing.contains(" reason="), passing)

        let stale = formatSummary(
            summary(p95: 20, p99: 40, budgetP95: 60_000, budgetP99: 120_000), includeGate: true)
        XCTAssertTrue(stale.contains(" gate=fail"), stale)
        XCTAssertTrue(stale.contains(" reason=budget_stale"), stale)
    }

    // headroom_p99 rides alongside headroom_p95 in gate output, immediately
    // after it and before gate=. No Foundation-only String API here (split /
    // hasPrefix are stdlib) since Sources/ViewportBenchmarks must stay
    // Foundation-free and this pins the field order without needing it.
    func testGateOutputCarriesHeadroomP99() {
        let passing = formatSummary(
            summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 700), includeGate: true)
        XCTAssertTrue(passing.contains(" headroom_p99=10.0x"), passing)

        let tokens = passing.split(separator: " ")
        guard let p95Index = tokens.firstIndex(where: { $0.hasPrefix("headroom_p95=") }),
              let p99Index = tokens.firstIndex(where: { $0.hasPrefix("headroom_p99=") }),
              let gateIndex = tokens.firstIndex(where: { $0.hasPrefix("gate=") }) else {
            XCTFail("expected headroom_p95, headroom_p99, and gate fields: \(passing)")
            return
        }
        XCTAssertTrue(p95Index < p99Index, passing)
        XCTAssertTrue(p99Index < gateIndex, passing)
    }

    // Non-gate output is a separate contract and must not change.
    func testNonGateOutputIsUnchanged() {
        let line = formatSummary(
            summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 640), includeGate: false)
        XCTAssertFalse(line.contains("headroom_p95"), line)
        XCTAssertFalse(line.contains("headroom_p99"), line)
        XCTAssertFalse(line.contains("budget_p95_ns"), line)
        XCTAssertFalse(line.contains("gate="), line)
    }

    // The formatHeadroom function guards !headroom.isFinite to return "inf" rather
    // than trapping. This test pins that guard with an actual gate-output scenario.
    func testZeroLatencyFormattingDoesNotTrap() {
        let s = summary(p95: 0, p99: 0, budgetP95: 330, budgetP99: 660)
        let output = formatSummary(s, includeGate: true)
        XCTAssertTrue(output.contains(" headroom_p95=inf"), output)
        XCTAssertTrue(output.contains(" gate=fail"), output)
        XCTAssertTrue(output.contains(" reason=budget_stale"), output)
    }

    // The p95-only ceiling cannot see an inflated p99 budget, so pin it statically
    // over every gated scenario table. All budgets in this repo are produced by
    // .github/scripts/derive-gate-budgets.sh from the committed corpus (see AGENTS.md
    // "## Gate budgets"), and the recipe sets budget_p99 to at least twice budget_p95 by
    // construction, so every table it produces satisfies p99 >= 2 * p95 -- and a
    // hand-edit or partial re-derivation must not quietly break the invariant that
    // GateLimits.maxHeadroomP99 = 2 * maxHeadroomP95 rests on. Do not narrow this list to
    // make a failure disappear; re-derive the offending table via the recipe instead.
    // GateFloorTests is the companion assertion that holds every gated scenario to the
    // 3x floor.
    //
    // (variableHeightScenarios() is the STATIC variable-height table, distinct from
    // variableHeightMutationScenarios() below despite the similar name.)
    func testEveryRecipeDerivedScenarioTableKeepsP99AtLeastTwiceP95() {
        var budgets: [(String, Int64, Int64)] = []
        for s in benchmarkScenarios() {
            budgets.append(("pipeline|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in realisticProviderScenarios() {
            budgets.append(("realistic_provider|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in lineQueryScenarios() {
            budgets.append(("line_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in lineGeometryQueryScenarios() {
            budgets.append(("line_geometry_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in columnQueryScenarios() {
            budgets.append(("column_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in columnGeometryQueryScenarios() {
            budgets.append(("column_geometry_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in pointQueryScenarios() {
            budgets.append(("point_query|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in variableHeightScenarios() {
            budgets.append(("variable_height|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in structuralMutationScenarios() {
            budgets.append(("structural_mutation|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in variableHeightMutationScenarios() {
            budgets.append(("variable_height_mutation|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in bulkStructuralMutationScenarios() {
            budgets.append(("bulk_structural_mutation|\(s.name)", s.p95BudgetNanoseconds, s.p99BudgetNanoseconds))
        }
        for s in pointGeometryQueryScenarios() {
            guard let p95 = s.p95BudgetNanoseconds, let p99 = s.p99BudgetNanoseconds else {
                XCTFail("point_geometry_query|\(s.name) is gated but carries no budget — "
                        + "derive it with .github/scripts/derive-gate-budgets.sh")
                continue
            }
            budgets.append(("point_geometry_query|\(s.name)", p95, p99))
        }

        XCTAssertFalse(budgets.isEmpty)
        for (name, p95, p99) in budgets {
            XCTAssertGreaterThanOrEqual(
                p99, 2 * p95,
                "\(name): p99 budget \(p99) is below 2x the p95 budget \(p95)")
        }
    }
}
