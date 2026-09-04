import XCTest
@testable import ViewportBenchmarks

final class BenchmarkModeFlagNameTests: XCTestCase {
    // G16. flagName is the THIRD copy of every flag spelling (parse's case labels are the
    // first, swift-ci.yml's payloads the second). This pins copy three to copy one, in the
    // direction that matters: a flagName nobody can parse would make WorkflowShapeTests
    // demand a CI command the binary rejects, and the workflow pin alone cannot see that.
    func testEveryFlagNameRoundTripsThroughParse() {
        for mode in BenchmarkMode.allCases {
            guard let flag = mode.flagName else { continue }
            guard case let .run(options) = BenchmarkOptions.parse(["--", flag]) else {
                XCTFail("\(mode.outputName): parse rejected its own flagName \(flag)")
                continue
            }
            XCTAssertEqual(
                options.mode.outputName, mode.outputName,
                "\(flag) parsed to \(options.mode.outputName), want \(mode.outputName)")
        }
    }

    // G16, gate half. Every gateable mode's flag must also survive beside --gate, which is
    // the exact argument vector each CI step runs.
    func testEveryGateableFlagNameAcceptsTheGateFlag() {
        for mode in BenchmarkMode.allCases where mode.isGateable {
            guard let flag = mode.flagName else { continue }
            guard case let .run(options) = BenchmarkOptions.parse(["--", flag, "--gate"]) else {
                XCTFail("\(mode.outputName): parse rejected \(flag) --gate")
                continue
            }
            XCTAssertTrue(options.enforceGate, "\(flag) --gate did not enable the gate")
            XCTAssertEqual(options.mode.outputName, mode.outputName)
        }
    }

    // G17. `.pipeline`'s nil is a CLAIM about the CLI, not a comment: the default mode has
    // no flag, so a bare `-- --gate` must select it. Without this, `nil` could mean
    // "unspecified" and nothing would notice.
    func testPipelineHasNoFlagAndIsSelectedByABareGate() {
        XCTAssertNil(BenchmarkMode.pipeline.flagName)
        guard case let .run(options) = BenchmarkOptions.parse(["--", "--gate"]) else {
            return XCTFail("a bare -- --gate must select the default pipeline mode")
        }
        XCTAssertEqual(options.mode.outputName, "pipeline")
        XCTAssertTrue(options.enforceGate)
    }

    // Every mode except the default carries a flag. Stated as a test rather than trusted to
    // the switch: a future mode whose author returns nil "for now" would silently leave the
    // workflow pin unable to name its step.
    func testOnlyThePipelineModeLacksAFlagName() {
        let flagless = BenchmarkMode.allCases.filter { $0.flagName == nil }
        XCTAssertEqual(
            flagless.map(\.outputName), ["pipeline"],
            "only the default mode may have no flag; got \(flagless.map(\.outputName))")
    }
}
