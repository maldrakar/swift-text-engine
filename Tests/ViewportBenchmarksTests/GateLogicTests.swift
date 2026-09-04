import XCTest
@testable import ViewportBenchmarks

private func summary(
    mode: BenchmarkMode = .lineQuery,
    p95: Int64,
    p99: Int64,
    budgetP95: Int64?,
    budgetP99: Int64?,
    failures: Int = 0
) -> BenchmarkSummary {
    BenchmarkSummary(
        mode: mode,
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

    // The p95-only ceiling cannot see an inflated p99 budget, so pin it statically over
    // every gated scenario. All budgets in this repo are produced by
    // .github/scripts/derive-gate-budgets.sh from the committed corpus (see AGENTS.md
    // "## Gate budgets"), and the recipe sets budget_p99 to at least twice budget_p95 by
    // construction, so every table it produces satisfies p99 >= 2 * p95 -- and a
    // hand-edit or partial re-derivation must not quietly break the invariant that
    // GateLimits.maxHeadroomP99 = 2 * maxHeadroomP95 rests on. A failure here means the
    // offending table needs re-deriving via the recipe.
    //
    // The scenario list comes from GateFloorTests' everyGatedBudget(), which is the test
    // target's single registry of gated scenarios. This test used to carry its own copy;
    // the copies drifted (one shipped missing a table that was already gated), and a mode
    // present in only one list is silently exempt from that list's invariant.
    // GateFloorTests is the companion assertion, holding the same scenarios to the 3x floor.
    func testEveryGatedBudgetKeepsP99AtLeastTwiceP95() {
        let budgets = everyGatedBudget()
        XCTAssertFalse(budgets.isEmpty)

        for budget in budgets {
            XCTAssertGreaterThanOrEqual(
                budget.p99, 2 * budget.p95,
                "\(budget.key): p99 budget \(budget.p99) is below 2x the p95 budget \(budget.p95)")
        }
    }

    // Pin the discrete-action class so it cannot silently widen. The exhaustive switch
    // forces a new mode to classify itself; this asserts the only GATED mode choosing
    // the one-frame ceiling is bulk_structural_mutation. Non-gateable modes are out of
    // scope here by construction -- see the note on absoluteCeiling.
    func testDiscreteActionClassIsExactlyDocumented() {
        let discrete = Set(
            BenchmarkMode.allCases
                .filter { $0.isGateable && $0.absoluteCeiling == .discreteAction }
                .map(\.outputName))
        XCTAssertEqual(discrete, ["bulk_structural_mutation"])
    }

    // D-20. The NON-GATEABLE modes' AbsoluteCeiling class is pinned by nothing:
    // testDiscreteActionClassIsExactlyDocumented filters on isGateable, so these six
    // classify under a total function that no test covers. The ledger row says "five" --
    // it was written before wrapPointQuery existed. The count is therefore DERIVED from
    // allCases here rather than transcribed, so the row's stale number cannot become a
    // stale pin: adding a seventh non-gateable mode fails this test until its class is a
    // decision somebody made.
    func testNonGateableModesClassifyAsScrollFrame() {
        let nonGateable = BenchmarkMode.allCases.filter { !$0.isGateable }
        XCTAssertEqual(
            Set(nonGateable.map(\.outputName)),
            ["range_only", "memory_shape", "memory_observation",
             "wrap_compute", "wrap_row_query", "wrap_point_query"],
            "the non-gateable set changed; classify the new mode, do not widen the pin")
        for mode in nonGateable {
            XCTAssertEqual(
                mode.absoluteCeiling, .scrollFrame,
                "\(mode.outputName): inert today, but it stops being inert the moment a "
                    + "wrap mode becomes gateable at node 6")
        }
    }

    // D-21. The .scrollFrame arm was unpinned in the gateable direction: moving a gated
    // mode INTO .discreteAction reddens testDiscreteActionClassIsExactlyDocumented, but a
    // new gateable mode landing in .scrollFrame tripped nothing. Safe by default --
    // .scrollFrame is the tighter ceiling -- but the safety was an accident. Both arms are
    // now checked, and the two tests together partition the gateable set.
    func testGateableScrollFrameClassIsExactlyDocumented() {
        let scrollFrame = Set(
            BenchmarkMode.allCases
                .filter { $0.isGateable && $0.absoluteCeiling == .scrollFrame }
                .map(\.outputName))
        XCTAssertEqual(
            scrollFrame,
            ["pipeline", "realistic_provider", "variable_height", "variable_height_mutation",
             "structural_mutation", "line_query", "line_geometry_query", "column_query",
             "column_geometry_query", "point_query", "point_geometry_query"])
        let gateable = Set(BenchmarkMode.allCases.filter(\.isGateable).map(\.outputName))
        XCTAssertEqual(
            scrollFrame.union(["bulk_structural_mutation"]), gateable,
            "the two class pins must partition the gateable set, or a mode can sit in "
                + "neither and be checked by neither")
    }

    // Both ceilings are data, not logic: pin them to the frame math so neither can be
    // silently changed or accidentally corpus-derived. FIXED, never recalibrated.
    func testAbsoluteCeilingsArePinnedToTheFrameMath() {
        XCTAssertEqual(GateLimits.frameNanoseconds, 1_000_000_000 / 60)
        XCTAssertEqual(GateLimits.frameNanoseconds, 16_666_666)
        XCTAssertEqual(AbsoluteCeiling.scrollFrame.p99Nanoseconds, GateLimits.frameNanoseconds / 10)
        XCTAssertEqual(AbsoluteCeiling.scrollFrame.p99Nanoseconds, 1_666_666)
        XCTAssertEqual(AbsoluteCeiling.discreteAction.p99Nanoseconds, GateLimits.frameNanoseconds)
        XCTAssertEqual(AbsoluteCeiling.discreteAction.p99Nanoseconds, 16_666_666)
    }

    // The reason this slice exists: a scroll-frame op blows the 60 FPS frame while its
    // (legitimately re-derived, looser) regression budget still PASSES. The product gate
    // must catch it -- this is the slow drift the regression gate re-derives around.
    func testAbsoluteCeilingFiresForScrollFrameMode() {
        let obsP99 = AbsoluteCeiling.scrollFrame.p99Nanoseconds + 1  // one ns over the frame ceiling
        let s = summary(
            mode: .structuralMutation,
            p95: 100_000, p99: obsP99,
            budgetP95: 300_000, budgetP99: obsP99 + 100_000)  // regression budget passes
        XCTAssertEqual(s.gateFailureReason, .budgetAbsoluteExceeded)
    }

    // The scroll-frame ceiling must NOT reach bulk. Same latency/budget shape as the
    // scroll-frame test above; under the two-class model 1.67 ms is far below bulk's
    // own 16.67 ms ceiling, so the assertion survives while its meaning changes: not
    // "bulk has no ceiling" but "bulk is not held to the SCROLL-FRAME ceiling".
    //
    // Symbolic on purpose, where its partner uses a literal: pinned to scrollFrame it
    // is what reddens if bulk is ever dragged back onto the tenth-of-a-frame ceiling.
    func testAbsoluteCeilingDoesNotFireForBulkMode() {
        let obsP99 = AbsoluteCeiling.scrollFrame.p99Nanoseconds + 1
        let s = summary(
            mode: .bulkStructuralMutation,
            p95: 100_000, p99: obsP99,
            budgetP95: 300_000, budgetP99: obsP99 + 100_000)
        XCTAssertNil(s.gateFailureReason)
    }

    // D-8's substance: bulk gets an absolute ceiling of its own -- one whole 60 FPS
    // frame -- and blowing it is reported even though the regression budget passes.
    //
    // The literal is deliberate and must NOT become
    // `AbsoluteCeiling.discreteAction.p99Nanoseconds + 1`. Written symbolically the
    // observation would track the ceiling, so raising the ceiling would raise the
    // observation with it and this test could never fail. Its job in Decision 8's
    // bracket is exactly to fail if the ceiling rises above 16_666_667 or disappears.
    func testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling() {
        let obsP99: Int64 = 16_666_667  // one ns over one whole 60 FPS frame
        let s = summary(
            mode: .bulkStructuralMutation,
            p95: 100_000, p99: obsP99,
            budgetP95: 300_000, budgetP99: obsP99 + 100_000)  // regression budget passes
        XCTAssertEqual(s.gateFailureReason, .budgetAbsoluteExceeded)
    }

    // budget_exceeded outranks the product reason: code that broke even the regression
    // budget reports the familiar regression failure, not the product one.
    func testBudgetExceededOutranksAbsoluteCeiling() {
        let obsP99 = AbsoluteCeiling.scrollFrame.p99Nanoseconds + 1
        let s = summary(
            mode: .structuralMutation,
            p95: 100_000, p99: obsP99,
            budgetP95: 300_000, budgetP99: obsP99 - 1)  // regression budget BROKEN
        XCTAssertEqual(s.gateFailureReason, .budgetExceeded)
    }

    // The absolute check must not mask a genuinely stale budget: when observed is tiny
    // (far under the ceiling) the reason stays budget_stale even for a hot-path mode.
    func testAbsoluteCeilingDoesNotMaskStaleBudget() {
        let s = summary(
            mode: .structuralMutation,
            p95: 20, p99: 40,
            budgetP95: 60_000, budgetP99: 120_000)  // ~3000x headroom -> stale
        XCTAssertEqual(s.gateFailureReason, .budgetStale)
    }

    // Scroll-frame gate output carries the fixed ceiling and its headroom, positioned
    // after headroom_p99 and before gate=. 1666666 / 200000 = 8.33 -> "8.3x".
    func testGateOutputCarriesScrollFrameCeiling() {
        let line = formatSummary(
            summary(mode: .structuralMutation, p95: 100_000, p99: 200_000,
                    budgetP95: 300_000, budgetP99: 600_000),
            includeGate: true)
        XCTAssertTrue(line.contains(" budget_absolute_p99_ns=1666666"), line)
        XCTAssertTrue(line.contains(" headroom_absolute_p99=8.3x"), line)

        let tokens = line.split(separator: " ")
        guard let p99Index = tokens.firstIndex(where: { $0.hasPrefix("headroom_p99=") }),
              let absIndex = tokens.firstIndex(where: { $0.hasPrefix("budget_absolute_p99_ns=") }),
              let gateIndex = tokens.firstIndex(where: { $0.hasPrefix("gate=") }) else {
            XCTFail("expected headroom_p99, budget_absolute_p99_ns, and gate fields: \(line)")
            return
        }
        XCTAssertTrue(p99Index < absIndex, line)
        XCTAssertTrue(absIndex < gateIndex, line)
    }

    // Bulk publishes its own ceiling like every other gated mode. Both assertions
    // inverted from the exemption era: the line carries a NUMBER, and it carries the
    // headroom token it previously omitted. 16_666_666 / 900_000 = 18.5x.
    func testGateOutputCarriesDiscreteActionCeilingForBulk() {
        let line = formatSummary(
            summary(mode: .bulkStructuralMutation, p95: 400_000, p99: 900_000,
                    budgetP95: 2_900_000, budgetP99: 5_800_000),
            includeGate: true)
        XCTAssertTrue(line.contains(" budget_absolute_p99_ns=16666666"), line)
        XCTAssertTrue(line.contains(" headroom_absolute_p99=18.5x"), line)
        XCTAssertTrue(line.contains(" gate=pass"), line)
    }

    // Non-gate output is a separate contract and must not grow the absolute token.
    func testNonGateOutputHasNoAbsoluteToken() {
        let line = formatSummary(
            summary(mode: .structuralMutation, p95: 100_000, p99: 200_000,
                    budgetP95: 300_000, budgetP99: 600_000),
            includeGate: false)
        XCTAssertFalse(line.contains("budget_absolute_p99_ns"), line)
        XCTAssertFalse(line.contains("headroom_absolute_p99"), line)
    }
}
