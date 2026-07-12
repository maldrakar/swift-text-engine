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
    // headroom is too LOOSE (`budget_stale`) as well as when it is exceeded. The
    // band, the 3x floor, and the rule that an optimization raises the BUDGET and
    // never the ceiling all live in AGENTS.md "## Gate budgets".
    //
    // The ceiling must clear what the FASTEST machine in play reports: budgets are
    // derived from hosted Linux x86_64, but local macOS arm64 runs 2-3x faster and
    // therefore shows the same budget's highest headroom. A ceiling below that would
    // condemn budgets correctly calibrated for the machine they were derived on.
    //
    // No "worst observed is X.Yx" figure appears here on purpose: headroom is
    // budget / observed, so every re-derivation moves it without touching this file.
    // Run the gate modes and read `headroom_p95=` to see today's worst.
    static let maxHeadroomP95: Double = 50.0

    // Doubled, not chosen independently, and computed from maxHeadroomP95 so the two
    // cannot silently drift apart.
    //
    // Why 2x is the right coupling -- structural, not measured: the recipe in
    // .github/scripts/derive-gate-budgets.sh sets budget_p99 to at least twice
    // budget_p95, so a recipe-derived p99 budget clears 2x BY CONSTRUCTION. Yet
    // observed p99 can EQUAL observed p95 -- these operations are sub-microsecond and
    // the clock is ns-quantized, so both quantiles routinely land on the same tick. A
    // scenario can therefore show ~2x its p95 headroom on p99 while sitting perfectly
    // in-band on p95, and any tighter p99 ceiling would condemn budgets the recipe
    // itself produced.
    //
    // The mutation tables predate the recipe and keep their pre-slice-38 budgets, whose
    // p99 sits at or below 2x their p95 -- so for them this ceiling is slack and never
    // wrongly binds. GateLogicTests pins the >= 2x property over the recipe-derived
    // tables only; GateFloorTests pins the floor over every gated scenario.
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

    // A workload too cheap for the clock measures 0 ns, which makes headroom unbounded
    // rather than undefined -- and `.infinity` is above every ceiling, so the gate fails.
    // That is the right answer: a scenario measuring zero guards nothing.
    private static func headroom(budget: Int64, observed: Int64) -> Double {
        observed <= 0 ? .infinity : Double(budget) / Double(observed)
    }

    var headroomP95: Double? {
        p95BudgetNanoseconds.map { BenchmarkSummary.headroom(budget: $0, observed: p95Nanoseconds) }
    }

    var headroomP99: Double? {
        p99BudgetNanoseconds.map { BenchmarkSummary.headroom(budget: $0, observed: p99Nanoseconds) }
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

        let p95 = BenchmarkSummary.headroom(budget: p95BudgetNanoseconds, observed: p95Nanoseconds)
        let p99 = BenchmarkSummary.headroom(budget: p99BudgetNanoseconds, observed: p99Nanoseconds)
        if p95 > GateLimits.maxHeadroomP95 || p99 > GateLimits.maxHeadroomP99 {
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
