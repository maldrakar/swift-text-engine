import XCTest
@testable import ViewportBenchmarks

final class MemoryShapeComparisonTests: XCTestCase {
    private func contribution(
        _ name: String, buffered: Int = 90, streamed: Int = 90, touched: Int? = 90
    ) -> MemoryShapeWindowContribution {
        MemoryShapeWindowContribution(
            scenarioName: name, bufferedWindow: buffered,
            streamedElements: streamed, touchedElements: touched)
    }

    private func wrapSummary(
        _ name: String, lineCount: Int, widthLabel: String,
        compute: Int = 2, drain: Int = 100, row: Int = 20, point: Int = 40,
        buffered: Int = 90, streamed: Int = 90, providerBytes: Int? = nil
    ) -> WrapMemoryShapeSummary {
        WrapMemoryShapeSummary(
            scenarioName: name, lineCount: lineCount, widthLabel: widthLabel,
            totalRows: lineCount, visibleRows: 80, bufferedRows: buffered,
            streamedRows: streamed, pointRowInLine: 3, pointClamp: "none",
            computeProbes: compute, drainProbes: drain, rowQueryProbes: row,
            pointQueryProbes: point, coreOwnedBytes: 64,
            providerOwnedBytes: providerBytes ?? ((lineCount + 1) * 8),
            rangeIsOrderedAndBounded: true, baseInvariantPasses: true, checksum: 1)
    }

    /// The six real scenarios' shape, all healthy: 10x the lines, a handful more probes.
    private func healthyWrapSet() -> [WrapMemoryShapeSummary] {
        [
            wrapSummary("100k_lines_width_inf", lineCount: 100_000, widthLabel: "inf", drain: 271, row: 20, point: 31),
            wrapSummary("100k_lines_width_40", lineCount: 100_000, widthLabel: "40", drain: 190, row: 20, point: 60),
            wrapSummary("100k_lines_width_10", lineCount: 100_000, widthLabel: "10", drain: 150, row: 20, point: 95),
            wrapSummary("1m_lines_width_inf", lineCount: 1_000_000, widthLabel: "inf", drain: 274, row: 23, point: 34),
            wrapSummary("1m_lines_width_40", lineCount: 1_000_000, widthLabel: "40", drain: 193, row: 23, point: 63),
            wrapSummary("1m_lines_width_10", lineCount: 1_000_000, widthLabel: "10", drain: 153, row: 23, point: 98),
        ]
    }

    func testAHealthySetHasNoFailures() {
        XCTAssertEqual(memoryShapeComparisonFailures((1...11).map { contribution("s\($0)") }), [])
        XCTAssertEqual(wrapMemoryShapeCrossScenarioFailures(healthyWrapSet()), [])
    }

    // G7. The mode-wide window equality, and specifically on `large_text` -- the one
    // scenario the old per-group byte comparison matched NEITHER branch of, so it fell to
    // `else { comparisonPasses = true }` and was not compared at all.
    func testAWrongWindowFailsOnAnyScenarioIncludingLargeText() {
        var contributions = (1...10).map { contribution("s\($0)") }
        contributions.insert(contribution("100k_lines_10mb_text", buffered: 89), at: 2)
        XCTAssertEqual(memoryShapeComparisonFailures(contributions), ["100k_lines_10mb_text"])
    }

    // G17. The baseline is DECLARED, not first-of-group. Corrupting the first element must
    // name the first element -- under a first-of-group comparison it would instead redden
    // the other ten and leave the guilty one green, which is the second defect of the
    // idiom that produced `x == x`.
    func testCorruptingTheFirstContributionNamesTheFirstContribution() {
        var contributions = (1...11).map { contribution("s\($0)") }
        contributions[0] = contribution("s1", streamed: 91)
        XCTAssertEqual(memoryShapeComparisonFailures(contributions), ["s1"])
    }

    // G18, comparison half. A wrap scenario reports no `touchedElements`; the five
    // non-wrap ones must, and a nil there must not be silently treated as a pass for a
    // scenario that HAS the traversal.
    func testTouchedElementsIsCheckedWhereItExists() {
        XCTAssertEqual(memoryShapeComparisonFailures([contribution("variable_1m", touched: 89)]), ["variable_1m"])
        XCTAssertEqual(memoryShapeComparisonFailures([contribution("wrap", touched: nil)]), [])
    }

    // G2. Flatness, against the declared constant. `compute(_:layout:)` probes the layout
    // twice whatever the document size or wrap width does, because its boundary searches
    // run over UniformLineMetrics and touch the layout not at all.
    func testANonFlatComputeProbeCountFailsTheOffendingScenario() {
        var set = healthyWrapSet()
        set[4] = wrapSummary("1m_lines_width_40", lineCount: 1_000_000, widthLabel: "40", compute: 3)
        XCTAssertEqual(wrapMemoryShapeCrossScenarioFailures(set), ["1m_lines_width_40"])

        // The FIRST scenario must be able to fail too. Under a first-of-group baseline it
        // is the one element that never is (it is compared to itself), so this is the case
        // that separates the declared-constant comparison from that idiom -- drill (l).
        var first = healthyWrapSet()
        first[0] = wrapSummary(
            "100k_lines_width_inf", lineCount: 100_000, widthLabel: "inf",
            compute: 3, drain: 271, row: 20, point: 31)
        XCTAssertEqual(
            wrapMemoryShapeCrossScenarioFailures(first), ["100k_lines_width_inf"],
            "the FIRST scenario must be able to fail; under a first-of-group baseline it "
                + "is the one element that never is")
    }

    // G3. The shape bound. A linear term would show as roughly 10x -- hundreds of
    // thousands of probes -- so a delta of 33 is already far outside the handful of
    // binary-search levels the 10x jump really costs, and both scenarios of the pair are
    // named because the invariant is relational.
    func testAProbeDeltaAboveTheBoundFailsBothScenariosOfThePair() {
        var set = healthyWrapSet()
        set[3] = wrapSummary("1m_lines_width_inf", lineCount: 1_000_000, widthLabel: "inf", drain: 271 + 33)
        XCTAssertEqual(
            wrapMemoryShapeCrossScenarioFailures(set),
            ["100k_lines_width_inf", "1m_lines_width_inf"])
    }

    // G4. The buffered window is width-independent: rowHeight and viewportHeight are the
    // same in every scenario, so the visible window is 80 rows and the buffer 90 whatever
    // the wrap width does to the row count.
    func testAWidthDependentBufferFails() {
        var set = healthyWrapSet()
        // The mutation carries its OWN width's healthy drain/row/point values, so only the
        // clause under test (buffered/streamed) can name this scenario. At the
        // constructor's default drain: 100, the width-10 drain delta against 1m (153) would
        // be 53 -- above the shape bound on its own -- and the pair check would name the
        // scenario whether or not the buffered/streamed clause exists.
        set[2] = wrapSummary(
            "100k_lines_width_10", lineCount: 100_000, widthLabel: "10",
            drain: 150, row: 20, point: 95, buffered: 100, streamed: 100)
        XCTAssertTrue(wrapMemoryShapeCrossScenarioFailures(set).contains("100k_lines_width_10"))
    }

    // G6. The walk is a WIDTH term and the counter tracks it: at a fixed size the narrow
    // width must cost more point-query probes than the infinite one. If it does not, the
    // within-line walk is not being counted, and every "the walk is bounded" reading in
    // the record rests on a number that never moves.
    //
    // Ruling A: mutate set[0] (100k width-inf), not set[2] (100k width-10), to `point: 95`,
    // keeping its healthy drain: 271, row: 20. Mutating set[2] to `point: 31` at the
    // constructor's default `drain: 100` would also drop that width's drain delta to
    // 153 - 100 = 53, breaching the <= 32 shape bound and returning three names instead of
    // two.
    func testTheWalkMustCostSomething() {
        var set = healthyWrapSet()
        set[0] = wrapSummary("100k_lines_width_inf", lineCount: 100_000, widthLabel: "inf", drain: 271, row: 20, point: 95)
        XCTAssertEqual(
            wrapMemoryShapeCrossScenarioFailures(set),
            ["100k_lines_width_10", "100k_lines_width_inf"])
    }

    // G16, cross half. The prefix sum has one entry per LOGICAL line, so at a fixed size
    // the provider's footprint does not move with the width -- and across the 10x size
    // jump it does.
    func testProviderBytesAreASizeTermAndNotAWidthTerm() {
        var set = healthyWrapSet()
        set[1] = wrapSummary(
            "100k_lines_width_40", lineCount: 100_000, widthLabel: "40", providerBytes: 1_600_016)
        let failures = wrapMemoryShapeCrossScenarioFailures(set)
        XCTAssertTrue(failures.contains("100k_lines_width_40"))
        XCTAssertTrue(failures.contains("100k_lines_width_inf"))
    }

    // G18, measurement half. `touched_lines` on the variable path used to be
    // `providerLines: bufferedLines` -- the buffered window written twice. This drives the
    // real scenario at unit scale and asserts the counted value.
    func testTheVariablePathCountsTheLinesItTouches() {
        let summary = runVariableMemoryShapeScenario(lineCount: 1_000)
        XCTAssertEqual(summary.bufferedLines, 90)
        XCTAssertEqual(summary.geometryLines, 90)
        XCTAssertEqual(summary.providerLines, 90, "counted, not assigned")
    }
}
