enum BenchmarkMode {
    case pipeline
    case rangeOnly
    case realisticProvider
    case memoryShape

    var outputName: String {
        switch self {
        case .pipeline:
            return "pipeline"
        case .rangeOnly:
            return "range_only"
        case .realisticProvider:
            return "realistic_provider"
        case .memoryShape:
            return "memory_shape"
        }
    }
}

enum BenchmarkOptionParse {
    case run(BenchmarkOptions)
    case help
    case failure(String)
}

struct BenchmarkOptions {
    let mode: BenchmarkMode
    let enforceGate: Bool

    static let usage = """
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

    Options:
      --range-only          Run only viewport range recompute benchmark.
      --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
      --realistic-provider  Run large-text provider benchmark without gate enforcement.
      --memory-shape        Run deterministic core-owned memory-shape diagnostics.
      --help                Print this help.
    """

    static func parse(_ arguments: [String]) -> BenchmarkOptionParse {
        var mode = BenchmarkMode.pipeline
        var enforceGate = false

        for argument in arguments {
            switch argument {
            case "--":
                continue
            case "--help":
                return .help
            case "--range-only":
                if mode == .realisticProvider {
                    return .failure("--range-only cannot be combined with --realistic-provider")
                }
                if mode == .memoryShape {
                    return .failure("--range-only cannot be combined with --memory-shape")
                }
                mode = .rangeOnly
            case "--gate":
                enforceGate = true
            case "--realistic-provider":
                if mode == .rangeOnly {
                    return .failure("--realistic-provider cannot be combined with --range-only")
                }
                if mode == .memoryShape {
                    return .failure("--realistic-provider cannot be combined with --memory-shape")
                }
                mode = .realisticProvider
            case "--memory-shape":
                if mode == .rangeOnly {
                    return .failure("--range-only cannot be combined with --memory-shape")
                }
                if mode == .realisticProvider {
                    return .failure("--realistic-provider cannot be combined with --memory-shape")
                }
                mode = .memoryShape
            default:
                return .failure("unknown argument \(argument)")
            }
        }

        if mode == .rangeOnly && enforceGate {
            return .failure("--range-only cannot be combined with --gate")
        }
        if mode == .realisticProvider && enforceGate {
            return .failure("--realistic-provider cannot be combined with --gate")
        }
        if mode == .memoryShape && enforceGate {
            return .failure("--memory-shape cannot be combined with --gate")
        }

        return .run(BenchmarkOptions(mode: mode, enforceGate: enforceGate))
    }
}
