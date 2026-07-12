struct BenchmarkScenario {
    let name: String
    let lineCount: Int
    let lineHeight: Double
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

struct RealisticProviderScenario {
    let name: String
    let lineCount: Int
    let lineBytes: Int
    let lineHeight: Double
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

enum GateLimits {
    // A budget far above observed latency guards nothing, so the gate fails when
    // headroom is too LOOSE as well as when it is exceeded.
    //
    // This ceiling is calibrated against the FASTEST machine in play. Budgets are
    // derived from hosted Linux x86_64 samples, but local macOS arm64 runs 2-3x
    // faster, so the same budget shows its highest headroom locally. A ceiling has
    // to clear what the fastest machine reports, or it would condemn budgets that
    // are correctly calibrated for the machine they were derived on. That reasoning
    // fixes the ceiling's role; it does not depend on any particular measurement.
    //
    // Deliberately NO "worst observed is X.Yx" figure here. Headroom is
    // budget / observed, so every budget re-derivation moves it without touching
    // this file -- which is exactly how the previous version of this comment came
    // to state numbers that were no longer true. To find today's worst, run the ten
    // gate modes and read the headroom_p95= field; recorded measurements live in
    // docs/superpowers/verification/2026-07-12-gate-budget-recalibration.md.
    static let maxHeadroomP95: Double = 50.0

    // Exactly twice the p95 ceiling, and computed from it so that tightening the
    // p95 ceiling cannot silently decouple the two.
    //
    // Why 2x is the right coupling -- structural, not measured: the derivation
    // recipe (.github/scripts/derive-gate-budgets.sh) sets
    //   budget_p99 = max(2 * budget_p95, 8 * median(p99), 3 * max(p99))
    // so a recipe-derived budget_p99 is >= 2 * budget_p95 BY CONSTRUCTION. Yet
    // observed p99 can EQUAL observed p95: these operations are sub-microsecond and
    // the clock is ns-quantized, so both quantiles routinely land on the same tick.
    // A scenario can therefore show ~2x its p95 headroom on p99 while being
    // perfectly in-band on p95. Any p99 ceiling tighter than 2 * maxHeadroomP95
    // would condemn budgets the recipe itself produced.
    //
    // Scope of the >= 2x guarantee: it holds for budgets the recipe produced. The
    // mutation tables predate the recipe and were left alone because they were
    // already correctly calibrated; their p99 budgets sit below 2x their p95, so
    // for them this ceiling is slack and never wrongly binds. GateLogicTests
    // asserts the >= 2x property over exactly the recipe-derived tables.
    //
    // Observed p99 headroom is even less quotable than p95: on the fastest scenarios
    // p99 is effectively a single tail sample and swings by more than 1.5x between
    // runs of an UNCHANGED binary. Re-measure it; never trust a number written here.
    static let maxHeadroomP99: Double = 2 * maxHeadroomP95
}

enum GateFailureReason: String {
    case operationFailures = "operation_failures"
    case budgetExceeded = "budget_exceeded"
    case budgetStale = "budget_stale"
    case missingBudget = "missing_budget"
}

struct BenchmarkSummary {
    let mode: BenchmarkMode
    let providerName: String?
    let scenarioName: String
    let iterations: Int
    let operationsPerSample: Int
    let lineCount: Int?
    let documentBytes: Int?
    let lineBytes: Int?
    let p95Nanoseconds: Int64
    let p99Nanoseconds: Int64
    let checksum: Int
    let failureCount: Int
    let p95BudgetNanoseconds: Int64?
    let p99BudgetNanoseconds: Int64?

    var headroomP95: Double? {
        guard let p95BudgetNanoseconds else {
            return nil
        }
        if p95Nanoseconds <= 0 {
            return .infinity
        }
        return Double(p95BudgetNanoseconds) / Double(p95Nanoseconds)
    }

    var headroomP99: Double? {
        guard let p99BudgetNanoseconds else {
            return nil
        }
        if p99Nanoseconds <= 0 {
            return .infinity
        }
        return Double(p99BudgetNanoseconds) / Double(p99Nanoseconds)
    }

    // A gate that cannot fail is not a gate. `budgetStale` is what makes an
    // inflated budget a build error rather than a silent no-op: the two causes
    // demand opposite responses (fix the code vs. re-derive the budget), so the
    // gate reports which one it is.
    var gateFailureReason: GateFailureReason? {
        guard let p95BudgetNanoseconds, let p99BudgetNanoseconds else {
            return .missingBudget
        }
        if failureCount != 0 {
            return .operationFailures
        }
        if p95Nanoseconds > p95BudgetNanoseconds || p99Nanoseconds > p99BudgetNanoseconds {
            return .budgetExceeded
        }
        if let headroomP95, headroomP95 > GateLimits.maxHeadroomP95 {
            return .budgetStale
        }
        if let headroomP99, headroomP99 > GateLimits.maxHeadroomP99 {
            return .budgetStale
        }
        return nil
    }

    var passesGate: Bool {
        gateFailureReason == nil
    }
}

struct BenchmarkOperationResult {
    let checksum: Int
    let failureCount: Int
}
