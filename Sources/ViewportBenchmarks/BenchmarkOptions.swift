enum BenchmarkMode {
    case pipeline
    case rangeOnly
    case realisticProvider
    case variableHeight
    case memoryShape
    case memoryObservation

    var outputName: String {
        switch self {
        case .pipeline:
            return "pipeline"
        case .rangeOnly:
            return "range_only"
        case .realisticProvider:
            return "realistic_provider"
        case .variableHeight:
            return "variable_height"
        case .memoryShape:
            return "memory_shape"
        case .memoryObservation:
            return "memory_observation"
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
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--variable-height] [--memory-shape] [--memory-observation] [--help]

    Options:
      --range-only          Run only viewport range recompute benchmark.
      --gate                Enforce p95/p99 budgets for gateable benchmark modes and exit non-zero on failure.
      --realistic-provider  Run large-text provider benchmark. Combine with --gate to enforce calibrated budgets.
      --variable-height     Run variable-height compute+geometry benchmark. Combine with --gate to enforce budgets.
      --memory-shape        Run deterministic core-owned memory-shape diagnostics.
      --memory-observation  Run host RSS observation diagnostics.
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
                if mode != .pipeline {
                    return .failure("--range-only cannot be combined with another mode")
                }
                mode = .rangeOnly
            case "--gate":
                enforceGate = true
            case "--realistic-provider":
                if mode != .pipeline {
                    return .failure("--realistic-provider cannot be combined with another mode")
                }
                mode = .realisticProvider
            case "--variable-height":
                if mode != .pipeline {
                    return .failure("--variable-height cannot be combined with another mode")
                }
                mode = .variableHeight
            case "--memory-shape":
                if mode != .pipeline {
                    return .failure("--memory-shape cannot be combined with another mode")
                }
                mode = .memoryShape
            case "--memory-observation":
                if mode != .pipeline {
                    return .failure("--memory-observation cannot be combined with another mode")
                }
                mode = .memoryObservation
            default:
                return .failure("unknown argument \(argument)")
            }
        }

        if enforceGate && (mode == .rangeOnly || mode == .memoryShape || mode == .memoryObservation) {
            return .failure("--gate cannot be combined with \(mode.outputName) mode")
        }

        return .run(BenchmarkOptions(mode: mode, enforceGate: enforceGate))
    }
}
