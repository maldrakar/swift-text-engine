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
    // The budget must stay within this multiple of observed latency, or it is
    // guarding nothing. Calibrated against the fastest machine in play (local
    // macOS arm64, which runs 2-3x faster than hosted CI and so shows the highest
    // headroom): no scenario exceeds 23x there, leaving >= 2.2x of margin.
    static let maxHeadroomP95: Double = 50.0

    // The derivation formula sets budget_p99 = max(2 * budget_p95, 8 *
    // median(p99), 3 * max(p99)), so budget_p99 is >= 2x budget_p95 BY
    // CONSTRUCTION. The p99 ceiling is therefore the p95 ceiling doubled --
    // that keeps the two guards equally tight rather than making p99 the
    // binding one. Measured worst local p99 headroom today is 44.5x
    // (variable_height|1m_lines_200_visible_overscan_50), leaving 2.2x of
    // margin -- the mirror of p95's worst 25.9x against its 50x ceiling.
    static let maxHeadroomP99: Double = 100.0
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
