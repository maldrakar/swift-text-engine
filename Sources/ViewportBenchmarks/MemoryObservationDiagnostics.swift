#if canImport(Darwin)
import Darwin
#elseif os(Linux)
import Glibc
#endif
import TextEngineCore

struct MemoryObservationRSSSnapshot {
    let bytes: Int
    let pageSizeBytes: Int
}

struct MemoryObservationSummary {
    let providerName: String
    let scenarioName: String
    let lineCount: Int
    let documentBytes: Int?
    let visibleLines: Int
    let bufferedLines: Int
    let geometryLines: Int
    let providerLines: Int
    let missingLines: Int
    let coreOwnedBytesModel: Int
    let providerOwnedBytes: Int
    let baselineRSS: MemoryObservationRSSSnapshot?
    let afterProviderSetupRSS: MemoryObservationRSSSnapshot?
    let afterCoreOperationRSS: MemoryObservationRSSSnapshot?
    let rssPageSizeBytes: Int?
    let rssProviderDeltaBytes: Int?
    let rssCoreOperationDeltaBytes: Int?
    let observationPasses: Bool
    let failureReason: String?
    let checksum: Int
}

func currentRSSSnapshot() -> MemoryObservationRSSSnapshot? {
#if canImport(Darwin)
    return currentDarwinRSSSnapshot()
#elseif os(Linux)
    return currentLinuxRSSSnapshot()
#else
    return nil
#endif
}

#if canImport(Darwin)
func currentDarwinRSSSnapshot() -> MemoryObservationRSSSnapshot? {
    let pageSize = Int(getpagesize())
    if pageSize <= 0 {
        return nil
    }

    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )

    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                $0,
                &count
            )
        }
    }

    guard result == KERN_SUCCESS,
          info.resident_size > 0,
          info.resident_size <= UInt64(Int.max) else {
        return nil
    }

    return MemoryObservationRSSSnapshot(
        bytes: Int(info.resident_size),
        pageSizeBytes: pageSize
    )
}
#endif

#if os(Linux)
func currentLinuxRSSSnapshot() -> MemoryObservationRSSSnapshot? {
    let pageSize = Int(sysconf(Int32(_SC_PAGESIZE)))
    guard pageSize > 0,
          let statmLine = readLinuxStatmLine(),
          let residentPages = linuxResidentPages(fromStatmLine: statmLine),
          residentPages > 0,
          residentPages <= Int.max / pageSize else {
        return nil
    }

    return MemoryObservationRSSSnapshot(
        bytes: residentPages * pageSize,
        pageSizeBytes: pageSize
    )
}

func readLinuxStatmLine() -> String? {
    guard let file = fopen("/proc/self/statm", "r") else {
        return nil
    }
    defer { fclose(file) }

    var buffer = [CChar](repeating: 0, count: 256)
    guard fgets(&buffer, Int32(buffer.count), file) != nil else {
        return nil
    }

    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

func linuxResidentPages(fromStatmLine line: String) -> Int? {
    // /proc/self/statm fields: size resident shared text lib data dt
    var fieldIndex = 0
    var currentValue = 0
    var hasDigit = false

    for byte in line.utf8 {
        if byte >= 48 && byte <= 57 {
            hasDigit = true
            let digit = Int(byte - 48)
            if currentValue > (Int.max - digit) / 10 {
                return nil
            }
            currentValue = currentValue * 10 + digit
        } else if byte == 32 || byte == 9 || byte == 10 {
            if hasDigit {
                if fieldIndex == 1 {
                    return currentValue
                }
                fieldIndex += 1
                currentValue = 0
                hasDigit = false
            }
        } else {
            return nil
        }
    }

    if hasDigit && fieldIndex == 1 {
        return currentValue
    }

    return nil
}
#endif

func memoryObservationScenarios() -> [MemoryShapeScenario] {
    memoryShapeScenarios()
}

func memoryObservationFailureSummary(
    _ scenario: MemoryShapeScenario,
    reason: String,
    baselineRSS: MemoryObservationRSSSnapshot? = nil,
    afterProviderSetupRSS: MemoryObservationRSSSnapshot? = nil,
    afterCoreOperationRSS: MemoryObservationRSSSnapshot? = nil
) -> MemoryObservationSummary {
    let rssPageSizeBytes = baselineRSS?.pageSizeBytes
        ?? afterProviderSetupRSS?.pageSizeBytes
        ?? afterCoreOperationRSS?.pageSizeBytes

    return MemoryObservationSummary(
        providerName: scenario.providerKind.outputName,
        scenarioName: scenario.name,
        lineCount: scenario.lineCount,
        documentBytes: nil,
        visibleLines: 0,
        bufferedLines: 0,
        geometryLines: 0,
        providerLines: 0,
        missingLines: 0,
        coreOwnedBytesModel: coreOwnedBytesEstimate(),
        providerOwnedBytes: 0,
        baselineRSS: baselineRSS,
        afterProviderSetupRSS: afterProviderSetupRSS,
        afterCoreOperationRSS: afterCoreOperationRSS,
        rssPageSizeBytes: rssPageSizeBytes,
        rssProviderDeltaBytes: rssDelta(afterProviderSetupRSS, baselineRSS),
        rssCoreOperationDeltaBytes: rssDelta(afterCoreOperationRSS, afterProviderSetupRSS),
        observationPasses: false,
        failureReason: reason,
        checksum: -1
    )
}

func rssDelta(
    _ later: MemoryObservationRSSSnapshot?,
    _ earlier: MemoryObservationRSSSnapshot?
) -> Int? {
    guard let later, let earlier else {
        return nil
    }

    return later.bytes - earlier.bytes
}

@inline(never)
func runMemoryObservationCoreOperation<Source: DocumentLineSource>(
    scenario: MemoryShapeScenario,
    source: Source,
    documentBytes: Int?,
    providerOwnedBytes: Int,
    baselineRSS: MemoryObservationRSSSnapshot,
    afterProviderSetupRSS: MemoryObservationRSSSnapshot,
    foldLineContent: (inout Int, Source.Line) -> Void
) -> MemoryObservationSummary {
    let scrollOffset = memoryShapeScrollOffset(
        lineCount: scenario.lineCount,
        lineHeight: scenario.lineHeight,
        viewportHeight: scenario.viewportHeight
    )
    let input = ViewportInput(
        lineCount: scenario.lineCount,
        lineHeight: scenario.lineHeight,
        scrollOffsetY: scrollOffset,
        viewportHeight: scenario.viewportHeight,
        overscanLinesBefore: scenario.overscanBefore,
        overscanLinesAfter: scenario.overscanAfter
    )
    let coreOwnedBytesModel = coreOwnedBytesEstimate()

    switch ViewportVirtualizer.compute(input) {
    case let .success(range):
        let visibleLines = range.visibleEndExclusive - range.visibleStart
        let bufferedLines = range.bufferEndExclusive - range.bufferStart
        let expectedVisibleLines = expectedMemoryShapeVisibleLines(scenario)
        let expectedBufferedLines = expectedMemoryShapeBufferedLines(scenario)
        let rangePasses = memoryShapeRangeIsOrderedAndBounded(
            range,
            lineCount: scenario.lineCount
        )
        let geometry = countGeometryLines(range: range, lineHeight: scenario.lineHeight)
        let provider = countProviderLines(
            range: range,
            source: source,
            foldLineContent: foldLineContent
        )

        let expectedProviderBytes: Int
        let providerBytesPasses: Bool
        switch scenario.providerKind {
        case .synthetic:
            expectedProviderBytes = 0
            providerBytesPasses = providerOwnedBytes == expectedProviderBytes
                && documentBytes == nil
        case .largeText:
            if let lineBytes = scenario.lineBytes {
                expectedProviderBytes = scenario.lineCount * lineBytes
            } else {
                expectedProviderBytes = -1
            }
            providerBytesPasses = providerOwnedBytes == expectedProviderBytes
                && documentBytes == expectedProviderBytes
        }

        let invariantPasses = rangePasses
            && visibleLines == expectedVisibleLines
            && bufferedLines == expectedBufferedLines
            && geometry.lineCount == expectedBufferedLines
            && provider.lineCount == expectedBufferedLines
            && provider.missingCount == 0
            && providerBytesPasses

        var checksum = 0
        checksum &+= scenario.lineCount
        checksum &+= visibleLines
        checksum &+= bufferedLines
        checksum &+= geometry.checksum
        checksum &+= provider.checksum
        checksum &+= coreOwnedBytesModel
        checksum &+= providerOwnedBytes

        var afterCoreOperationRSS: MemoryObservationRSSSnapshot?
        withExtendedLifetime(source) {
            withExtendedLifetime(range) {
                withExtendedLifetime(geometry) {
                    withExtendedLifetime(provider) {
                        withExtendedLifetime(checksum) {
                            afterCoreOperationRSS = currentRSSSnapshot()
                        }
                    }
                }
            }
        }

        guard let afterCoreOperationRSS else {
            return MemoryObservationSummary(
                providerName: scenario.providerKind.outputName,
                scenarioName: scenario.name,
                lineCount: scenario.lineCount,
                documentBytes: documentBytes,
                visibleLines: visibleLines,
                bufferedLines: bufferedLines,
                geometryLines: geometry.lineCount,
                providerLines: provider.lineCount,
                missingLines: provider.missingCount,
                coreOwnedBytesModel: coreOwnedBytesModel,
                providerOwnedBytes: providerOwnedBytes,
                baselineRSS: baselineRSS,
                afterProviderSetupRSS: afterProviderSetupRSS,
                afterCoreOperationRSS: nil,
                rssPageSizeBytes: baselineRSS.pageSizeBytes,
                rssProviderDeltaBytes: rssDelta(afterProviderSetupRSS, baselineRSS),
                rssCoreOperationDeltaBytes: nil,
                observationPasses: false,
                failureReason: "rss_unavailable",
                checksum: -1
            )
        }

        return MemoryObservationSummary(
            providerName: scenario.providerKind.outputName,
            scenarioName: scenario.name,
            lineCount: scenario.lineCount,
            documentBytes: documentBytes,
            visibleLines: visibleLines,
            bufferedLines: bufferedLines,
            geometryLines: geometry.lineCount,
            providerLines: provider.lineCount,
            missingLines: provider.missingCount,
            coreOwnedBytesModel: coreOwnedBytesModel,
            providerOwnedBytes: providerOwnedBytes,
            baselineRSS: baselineRSS,
            afterProviderSetupRSS: afterProviderSetupRSS,
            afterCoreOperationRSS: afterCoreOperationRSS,
            rssPageSizeBytes: baselineRSS.pageSizeBytes,
            rssProviderDeltaBytes: rssDelta(afterProviderSetupRSS, baselineRSS),
            rssCoreOperationDeltaBytes: rssDelta(afterCoreOperationRSS, afterProviderSetupRSS),
            observationPasses: invariantPasses,
            failureReason: invariantPasses ? nil : "invariant_failed",
            checksum: invariantPasses ? checksum : -1
        )
    case .failure:
        return memoryObservationFailureSummary(
            scenario,
            reason: "viewport_compute_failed",
            baselineRSS: baselineRSS,
            afterProviderSetupRSS: afterProviderSetupRSS
        )
    }
}

func runMemoryObservationScenario(_ scenario: MemoryShapeScenario) -> MemoryObservationSummary {
    guard let baselineRSS = currentRSSSnapshot() else {
        return memoryObservationFailureSummary(scenario, reason: "rss_unavailable")
    }

    switch scenario.providerKind {
    case .synthetic:
        let source = SyntheticLineSource(lineCount: scenario.lineCount)

        guard let afterProviderSetupRSS = currentRSSSnapshot() else {
            return memoryObservationFailureSummary(
                scenario,
                reason: "rss_unavailable",
                baselineRSS: baselineRSS
            )
        }

        return withExtendedLifetime(source) {
            runMemoryObservationCoreOperation(
                scenario: scenario,
                source: source,
                documentBytes: nil,
                providerOwnedBytes: 0,
                baselineRSS: baselineRSS,
                afterProviderSetupRSS: afterProviderSetupRSS
            ) { checksum, content in
                checksum &+= content
            }
        }
    case .largeText:
        guard let lineBytes = scenario.lineBytes else {
            return memoryObservationFailureSummary(
                scenario,
                reason: "missing_line_bytes",
                baselineRSS: baselineRSS
            )
        }

        let storage = RealisticDocumentStorage(
            lineCount: scenario.lineCount,
            lineBytes: lineBytes
        )
        let source = RealisticLineSource(storage: storage)

        guard let afterProviderSetupRSS = currentRSSSnapshot() else {
            return withExtendedLifetime(storage) {
                memoryObservationFailureSummary(
                    scenario,
                    reason: "rss_unavailable",
                    baselineRSS: baselineRSS
                )
            }
        }

        return withExtendedLifetime(storage) {
            withExtendedLifetime(source) {
                runMemoryObservationCoreOperation(
                    scenario: scenario,
                    source: source,
                    documentBytes: storage.documentBytes,
                    providerOwnedBytes: storage.documentBytes,
                    baselineRSS: baselineRSS,
                    afterProviderSetupRSS: afterProviderSetupRSS
                ) { checksum, content in
                    checksum &+= content.byteOffset
                    checksum &+= content.byteLength
                    checksum &+= content.firstByte
                    checksum &+= content.middleByte
                    checksum &+= content.lastByte
                }
            }
        }
    }
}

func formatMemoryObservationSummary(_ summary: MemoryObservationSummary) -> String {
    var output = "mode=\(BenchmarkMode.memoryObservation.outputName)"
    output += " provider=\(summary.providerName)"
    output += " scenario=\(summary.scenarioName)"
    output += " line_count=\(summary.lineCount)"
    if let documentBytes = summary.documentBytes {
        output += " document_bytes=\(documentBytes)"
    }
    output += " visible_lines=\(summary.visibleLines)"
    output += " buffered_lines=\(summary.bufferedLines)"
    output += " geometry_lines=\(summary.geometryLines)"
    output += " provider_lines=\(summary.providerLines)"
    output += " missing_lines=\(summary.missingLines)"
    output += " core_owned_bytes_model=\(summary.coreOwnedBytesModel)"
    output += " provider_owned_bytes=\(summary.providerOwnedBytes)"
    if let baselineRSS = summary.baselineRSS {
        output += " rss_baseline_bytes=\(baselineRSS.bytes)"
    }
    if let afterProviderSetupRSS = summary.afterProviderSetupRSS {
        output += " rss_after_provider_setup_bytes=\(afterProviderSetupRSS.bytes)"
    }
    if let afterCoreOperationRSS = summary.afterCoreOperationRSS {
        output += " rss_after_core_operation_bytes=\(afterCoreOperationRSS.bytes)"
    }
    if let rssPageSizeBytes = summary.rssPageSizeBytes {
        output += " rss_page_size_bytes=\(rssPageSizeBytes)"
    }
    if let rssProviderDeltaBytes = summary.rssProviderDeltaBytes {
        output += " rss_provider_delta_bytes=\(rssProviderDeltaBytes)"
    }
    if let rssCoreOperationDeltaBytes = summary.rssCoreOperationDeltaBytes {
        output += " rss_core_operation_delta_bytes=\(rssCoreOperationDeltaBytes)"
    }
    output += " observation=\(summary.observationPasses ? "pass" : "fail")"
    if let failureReason = summary.failureReason {
        output += " reason=\(failureReason)"
    }
    output += " checksum=\(summary.checksum)"
    return output
}

func runMemoryObservationDiagnostics() -> Bool {
    var passed = true

    for scenario in memoryObservationScenarios() {
        let summary = runMemoryObservationScenario(scenario)
        print(formatMemoryObservationSummary(summary))

        if !summary.observationPasses {
            passed = false
        }
    }

    return passed
}
