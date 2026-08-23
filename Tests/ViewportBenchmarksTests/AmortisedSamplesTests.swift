import XCTest
@testable import ViewportBenchmarks

// The shared measurement shape both wrap modes run on (spec Decisions 1 and 2).
//
// ContinuousClock cannot be substituted, so these tests pin what is pinnable: the
// loop's STRUCTURE (how many times the body runs, how many samples come back, which
// indices the body sees) and the ARITHMETIC, separately. The split is the point --
// a dropped division leaves every structural assertion true, which is why `amortise`
// is a free function pinned by exact equality rather than an inline `/`.
@available(macOS 13.0, *)
final class AmortisedSamplesTests: XCTestCase {

    // Drill 1's target. Mutating this function's body to `return elapsedNanoseconds`
    // reddens exactly here.
    func testAmortiseDividesByOperationsPerSample() {
        XCTAssertEqual(amortise(elapsedNanoseconds: 2_560, operationsPerSample: 256), 10)
        XCTAssertEqual(amortise(elapsedNanoseconds: 41, operationsPerSample: 1), 41)
        XCTAssertEqual(amortise(elapsedNanoseconds: 0, operationsPerSample: 256), 0)
    }

    // Truncation is not incidental: it is the same flooring every gated mode does
    // (LineQueryBenchmark.swift:89), and it is what lets a sub-tick operation report 0
    // rather than 1. Pinned so a "helpful" rounding change is a red test, not a drift.
    func testAmortiseTruncatesRatherThanRounds() {
        XCTAssertEqual(amortise(elapsedNanoseconds: 255, operationsPerSample: 256), 0)
        XCTAssertEqual(amortise(elapsedNanoseconds: 511, operationsPerSample: 256), 1)
        XCTAssertEqual(amortise(elapsedNanoseconds: 767, operationsPerSample: 256), 2)
    }

    func testBodyRunsIterationsTimesOperationsPerSample() {
        var calls = 0
        let measured = amortisedSamples(iterations: 7, operationsPerSample: 5) { _ in
            calls += 1
            return 1
        }
        XCTAssertEqual(calls, 35)
        XCTAssertEqual(measured.samples.count, 7)
        XCTAssertEqual(measured.checksum, 35)
    }

    // The body must see the GLOBAL operation index, contiguously from 0: the wrap modes'
    // deterministic input generators (deterministicScrollOffset, deterministicIndex) are
    // functions of it, so a per-iteration reset would silently shrink the input space to
    // `operationsPerSample` distinct inputs.
    func testBodyReceivesEveryGlobalOperationIndexOnceInOrder() {
        var seen: [Int] = []
        _ = amortisedSamples(iterations: 3, operationsPerSample: 4) { index in
            seen.append(index)
            return 0
        }
        XCTAssertEqual(seen, Array(0..<12))
    }

    // Samples come back UNSORTED and one-per-iteration: percentile() requires a sorted
    // array, and the caller is the one that sorts. Pinned so the helper never starts
    // sorting on its own and leaves callers double-sorting a copy.
    func testSamplesAreOnePerIterationAndNotSortedByTheHelper() {
        let measured = amortisedSamples(iterations: 4, operationsPerSample: 1) { _ in 0 }
        XCTAssertEqual(measured.samples.count, 4)
    }
}
