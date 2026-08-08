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
    // Every mode is held to one of two ceilings derived from this frame constant; which
    // one is AbsoluteCeiling, chosen per mode by BenchmarkMode.absoluteCeiling. There is
    // no exemption.
    //
    // FIXED: never recalibrated, never corpus-derived. A regression budget is anchored to
    // a moving median and can be legitimately re-derived looser slice by slice; these
    // ceilings are the fixed product targets that catch the slow drift a regression budget
    // re-derives around. On breach the response is to fix the code/architecture, NEVER to
    // loosen the ceiling (contrast budget_stale, which says re-derive the budget). See
    // AGENTS.md "## Gate budgets".
    static let frameNanoseconds: Int64 = 1_000_000_000 / 60          // 16_666_666 (60 FPS)
}

// Which absolute PRODUCT ceiling a mode is held to. Two classes, total by
// construction: an exhaustive switch on BenchmarkMode forces a newly added mode to
// classify itself, so it can neither silently inherit a ceiling nor silently escape
// one. There is no exempt case -- a branch with no inhabitants is the same defect as
// a gate that cannot fail.
//
// FIXED, both of them: never recalibrated, never corpus-derived. On breach the
// response is to fix the code/architecture, NEVER to loosen the ceiling (contrast
// budget_stale, which says re-derive the budget).
enum AbsoluteCeiling: Equatable {
    // A scroll frame must not drop, so every participant is rationed and the headless
    // core's ration is a tenth: the other 90% belongs to shaping, rasterization, and
    // UI outside it.
    case scrollFrame

    // A discrete action -- a bulk multi-line paste or range delete -- is one the user
    // has already accepted a perceptible pause for, so it MAY cost a dropped frame.
    // The core's budget for the action it triggered is that whole frame's worth of
    // work. Note this is NOT "the core may consume 100% of a live frame": the frame in
    // question is one the product has agreed to drop.
    case discreteAction

    var p99Nanoseconds: Int64 {
        switch self {
        case .scrollFrame:
            return GateLimits.frameNanoseconds / 10   // 1_666_666
        case .discreteAction:
            return GateLimits.frameNanoseconds        // 16_666_666
        }
    }
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

    // The absolute product ceiling's headroom: this mode's class ceiling / observed p99.
    // Non-optional (every mode has a ceiling) and reuses the zero-observed guard, so
    // p99 == 0 yields .infinity rather than trapping. Meaningful for every mode, and the
    // output layer emits a number for every gated one -- the two classes differ in the
    // ceiling divided, not in whether it exists.
    var headroomAbsoluteP99: Double {
        BenchmarkSummary.headroom(
            budget: mode.absoluteCeiling.p99Nanoseconds, observed: p99Nanoseconds)
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

        // The absolute PRODUCT ceiling, per class (AbsoluteCeiling). Position between
        // budgetExceeded and budgetStale is deliberate but, on a healthy tree,
        // unobservable: GateFloorTests pins every gated budget UNDER its class ceiling,
        // so any p99 above a ceiling is also above that mode's regression budget and the
        // branch above already returned budgetExceeded. This branch therefore has no
        // reachable inhabitant while that pin holds -- which is the design, not an
        // oversight. It is defense-in-depth for a tree where the pin has been removed or
        // budgets edited without running the suite; the product target itself is enforced
        // by testEveryGatedBudgetIsUnderItsClassCeiling, at swift test time. Do not go
        // looking for a hosted budget_absolute_exceeded: the pin fires first, by design.
        //
        // The ordering still matters for that degraded tree: inverted, a blown frame
        // would be reported as a stale budget. It never masks budgetStale, which needs a
        // tiny observed (huge headroom) where this check is silent.
        if p99Nanoseconds > mode.absoluteCeiling.p99Nanoseconds {
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
