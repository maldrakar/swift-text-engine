enum BenchmarkMode {
    case pipeline
    case rangeOnly
    case realisticProvider
    case variableHeight
    case variableHeightMutation
    case structuralMutation
    case bulkStructuralMutation
    case lineQuery
    case lineGeometryQuery
    case columnQuery
    case columnGeometryQuery
    case pointQuery
    case pointGeometryQuery
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
        case .variableHeightMutation:
            return "variable_height_mutation"
        case .structuralMutation:
            return "structural_mutation"
        case .bulkStructuralMutation:
            return "bulk_structural_mutation"
        case .lineQuery:
            return "line_query"
        case .lineGeometryQuery:
            return "line_geometry_query"
        case .columnQuery:
            return "column_query"
        case .columnGeometryQuery:
            return "column_geometry_query"
        case .pointQuery:
            return "point_query"
        case .pointGeometryQuery:
            return "point_geometry_query"
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
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--variable-height] [--variable-height-mutation] [--structural-mutation] [--bulk-structural-mutation] [--line-query] [--line-geometry-query] [--column-query] [--column-geometry-query] [--point-query] [--point-geometry-query] [--memory-shape] [--memory-observation] [--help]

    Options:
      --range-only          Run only viewport range recompute benchmark.
      --gate                Enforce p95/p99 budgets for gateable benchmark modes and exit non-zero on failure.
      --realistic-provider  Run large-text provider benchmark. Combine with --gate to enforce calibrated budgets.
      --variable-height     Run variable-height compute+geometry benchmark. Combine with --gate to enforce budgets.
      --variable-height-mutation  Run mutate+recompute benchmark (Fenwick provider). Combine with --gate to enforce budgets.
      --structural-mutation  Run insert/delete+recompute benchmark (balanced-tree provider). Combine with --gate to enforce budgets.
      --bulk-structural-mutation  Run bulk insert/delete-range+recompute benchmark (balanced-tree provider). Combine with --gate to enforce budgets.
      --line-query          Run y->line position-query benchmark. Combine with --gate to enforce budgets.
      --line-geometry-query Run y->line+box+fraction geometry query benchmark. Combine with --gate to enforce budgets.
      --column-query        Run x->cell within-line position-query benchmark. Combine with --gate to enforce budgets.
      --column-geometry-query  Run x->cell+box+fraction within-line geometry query benchmark. Combine with --gate to enforce budgets.
      --point-query         Run (x,y)->(line,cell) 2D composite position-query benchmark. Combine with --gate to enforce budgets.
      --point-geometry-query  Run (x,y)->(line+box+fraction, cell+box+fraction) 2D geometry query benchmark. Combine with --gate to enforce budgets.
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
            case "--variable-height-mutation":
                if mode != .pipeline {
                    return .failure("--variable-height-mutation cannot be combined with another mode")
                }
                mode = .variableHeightMutation
            case "--structural-mutation":
                if mode != .pipeline {
                    return .failure("--structural-mutation cannot be combined with another mode")
                }
                mode = .structuralMutation
            case "--bulk-structural-mutation":
                if mode != .pipeline {
                    return .failure("--bulk-structural-mutation cannot be combined with another mode")
                }
                mode = .bulkStructuralMutation
            case "--line-query":
                if mode != .pipeline {
                    return .failure("--line-query cannot be combined with another mode")
                }
                mode = .lineQuery
            case "--line-geometry-query":
                if mode != .pipeline {
                    return .failure("--line-geometry-query cannot be combined with another mode")
                }
                mode = .lineGeometryQuery
            case "--column-query":
                if mode != .pipeline {
                    return .failure("--column-query cannot be combined with another mode")
                }
                mode = .columnQuery
            case "--column-geometry-query":
                if mode != .pipeline {
                    return .failure("--column-geometry-query cannot be combined with another mode")
                }
                mode = .columnGeometryQuery
            case "--point-query":
                if mode != .pipeline {
                    return .failure("--point-query cannot be combined with another mode")
                }
                mode = .pointQuery
            case "--point-geometry-query":
                if mode != .pipeline {
                    return .failure("--point-geometry-query cannot be combined with another mode")
                }
                mode = .pointGeometryQuery
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
