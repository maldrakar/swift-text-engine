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
    // Every gated scenario table -- mutation tables included -- is now produced by the
    // recipe in .github/scripts/derive-gate-budgets.sh from the committed corpus, so this
    // ceiling never wrongly binds by construction. GateLogicTests pins the >= 2x property
    // over every recipe-derived table; GateFloorTests pins the floor over every gated
    // scenario.
    static let maxHeadroomP99: Double = 2 * maxHeadroomP95

    // The absolute PRODUCT ceiling -- a distinct axis from the regression band above.
    // The brief's success criterion is 60 FPS, "p95/p99 latency для пересчёта viewport".
    // A core frame operation must fit well within a frame, so the ceiling is 10% of a
    // 60 FPS frame, leaving the remainder for shaping/rasterization/UI outside the
    // headless core.
    //
    // FIXED: never recalibrated, never corpus-derived. A regression budget is anchored to
    // a moving median and can be legitimately re-derived looser slice by slice; this
    // ceiling is the fixed product target that catches the slow drift a regression budget
    // re-derives around. On breach the response is to fix the code/architecture, NEVER to
    // loosen the ceiling (contrast budget_stale, which says re-derive the budget). See
    // AGENTS.md "## Gate budgets".
    //
    // Applies to frame-hot-path modes only (BenchmarkMode.isFrameHotPath): bulk multi-line
    // edits are discrete, possibly multi-frame user actions and are exempt. GateLogicTests
    // pins this frame math; GateFloorTests pins that every frame-hot-path regression p99
    // budget stays under this ceiling.
    static let frameNanoseconds: Int64 = 1_000_000_000 / 60          // 16_666_666 (60 FPS)
    static let absoluteP99Nanoseconds: Int64 = frameNanoseconds / 10 // 1_666_666 (10% of a frame)
}

enum GateFailureReason: String {
    case operationFailures = "operation_failures"
    case budgetExceeded = "budget_exceeded"
    case budgetAbsoluteExceeded = "budget_absolute_exceeded"
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

    // The absolute product ceiling's headroom: fixed ceiling / observed p99. Non-optional
    // (the ceiling always exists) and reuses the zero-observed guard, so p99 == 0 yields
    // .infinity rather than trapping. Only meaningful for frame-hot-path modes; the output
    // layer emits it for those and marks the rest exempt.
    var headroomAbsoluteP99: Double {
        BenchmarkSummary.headroom(budget: GateLimits.absoluteP99Nanoseconds, observed: p99Nanoseconds)
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

        // The absolute PRODUCT ceiling, checked for frame-hot-path modes only (bulk edits
        // are discrete, possibly multi-frame actions -- exempt). It sits between
        // budgetExceeded and budgetStale on purpose: across the frame-hot-path set every
        // regression p99 budget is <= 580us < the 1.67ms ceiling (GateFloorTests pins
        // this), so exceeding the ceiling always also exceeds the regression budget and a
        // plain regression already reported budget_exceeded above. This therefore fires
        // ONLY when the regression budget passes but the frame is blown -- the slow drift a
        // re-derived regression budget cannot catch. It never masks budget_stale, which
        // needs a tiny observed (huge headroom) where this check is silent.
        if mode.isFrameHotPath, p99Nanoseconds > GateLimits.absoluteP99Nanoseconds {
            return .budgetAbsoluteExceeded
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
