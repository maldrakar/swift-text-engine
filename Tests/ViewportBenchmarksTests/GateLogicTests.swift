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

    // The two failures demand opposite responses, so the gate must say which it is.
    func testSlowCodeAndStaleBudgetAreDistinguished() {
        let slow = summary(p95: 400, p99: 700, budgetP95: 330, budgetP99: 660)
        XCTAssertEqual(slow.gateFailureReason, .budgetExceeded)

        let slowOnP99Only = summary(p95: 100, p99: 700, budgetP95: 330, budgetP99: 660)
        XCTAssertEqual(slowOnP99Only.gateFailureReason, .budgetExceeded)
    }

    func testOperationFailuresOutrankBudgetChecks() {
        let s = summary(p95: 40, p99: 70, budgetP95: 330, budgetP99: 660, failures: 1)
        XCTAssertEqual(s.gateFailureReason, .operationFailures)
    }

    func testMissingBudgetFailsTheGate() {
        let s = summary(p95: 40, p99: 70, budgetP95: nil, budgetP99: nil)
        XCTAssertFalse(s.passesGate)
        XCTAssertEqual(s.gateFailureReason, .missingBudget)
        XCTAssertNil(s.headroomP95)
    }

    // A workload too cheap for the clock guards nothing. Must not divide by zero.
    func testZeroLatencyIsUnboundedHeadroomAndFails() {
        let s = summary(p95: 0, p99: 0, budgetP95: 330, budgetP99: 660)
        XCTAssertEqual(s.headroomP95, .infinity)
        XCTAssertEqual(s.gateFailureReason, .budgetStale)
    }

    func testHeadroomIsBudgetOverP95() {
        XCTAssertEqual(summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 640).headroomP95, 8.0)
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

    // Non-gate output is a separate contract and must not change.
    func testNonGateOutputIsUnchanged() {
        let line = formatSummary(
            summary(p95: 40, p99: 70, budgetP95: 320, budgetP99: 640), includeGate: false)
        XCTAssertFalse(line.contains("headroom_p95"), line)
        XCTAssertFalse(line.contains("budget_p95_ns"), line)
        XCTAssertFalse(line.contains("gate="), line)
    }

    // The p95-only ceiling cannot see an inflated p99 budget, so pin it statically
    // over the real scenario tables.
    func testEveryScenarioTableKeepsP99AtLeastTwiceP95() {
        var budgets: [(String, Int64, Int64)] = []
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

        XCTAssertFalse(budgets.isEmpty)
        for (name, p95, p99) in budgets {
            XCTAssertGreaterThanOrEqual(
                p99, 2 * p95,
                "\(name): p99 budget \(p99) is below 2x the p95 budget \(p95)")
        }
    }
}
