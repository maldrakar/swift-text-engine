@available(macOS 13.0, *)
func runBenchmarks(options: BenchmarkOptions) -> Bool {
    switch options.mode {
    case .pipeline, .rangeOnly:
        return runSyntheticBenchmarks(options: options)
    case .realisticProvider:
        return runRealisticProviderBenchmarks(enforceGate: options.enforceGate)
    case .variableHeight:
        return runVariableHeightBenchmarks(enforceGate: options.enforceGate)
    case .variableHeightMutation:
        return runVariableHeightMutationBenchmarks(enforceGate: options.enforceGate)
    case .structuralMutation:
        return runStructuralMutationBenchmarks(enforceGate: options.enforceGate)
    case .bulkStructuralMutation:
        return runBulkStructuralMutationBenchmarks(enforceGate: options.enforceGate)
    case .lineQuery:
        return runLineQueryBenchmarks(enforceGate: options.enforceGate)
    case .lineGeometryQuery:
        return runLineGeometryQueryBenchmarks(enforceGate: options.enforceGate)
    case .columnQuery:
        return runColumnQueryBenchmarks(enforceGate: options.enforceGate)
    case .columnGeometryQuery:
        return runColumnGeometryQueryBenchmarks(enforceGate: options.enforceGate)
    case .pointQuery:
        return runPointQueryBenchmarks(enforceGate: options.enforceGate)
    case .pointGeometryQuery:
        return runPointGeometryQueryBenchmarks(enforceGate: options.enforceGate)
    case .memoryShape:
        return runMemoryShapeDiagnostics()
    case .memoryObservation:
        return runMemoryObservationDiagnostics()
    }
}

@available(macOS 13.0, *)
func runProgram(arguments: [String]) -> Int32 {
    switch BenchmarkOptions.parse(arguments) {
    case let .run(options):
        return runBenchmarks(options: options) ? 0 : 1
    case .help:
        print(BenchmarkOptions.usage)
        return 0
    case let .failure(message):
        print("error=\(message)")
        print(BenchmarkOptions.usage)
        return 1
    }
}
