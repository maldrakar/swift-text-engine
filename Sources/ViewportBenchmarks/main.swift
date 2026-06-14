#if canImport(Darwin)
import Darwin
#elseif os(Linux)
import Glibc
#endif

if #available(macOS 13.0, *) {
    let exitCode = runProgram(arguments: Array(CommandLine.arguments.dropFirst()))
    if exitCode != 0 {
        exit(exitCode)
    }
} else {
    fatalError("ViewportBenchmarks requires macOS 13.0 or newer")
}
