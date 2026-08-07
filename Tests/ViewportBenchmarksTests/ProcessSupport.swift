import Foundation

// Repository root from this file's own path:
// .../Tests/ViewportBenchmarksTests/ProcessSupport.swift -> repo root.
// Single home for the walk that GateFloorTests and WorkflowShapeTests each used to
// carry privately (the latter labelled itself a twin).
func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

// The test target's subprocess launcher. Safe here: ViewportBenchmarksTests runs only
// on the host (Linux CI + local macOS), never on iOS/WASM, which merely compile
// TextEngineCore/ReferenceProviders; nothing here reaches the Foundation-free core.
//
// Feeds `stdin`, reads stdout to EOF, then stderr, then reaps. Sequential reads are
// safe only while a driven process cannot fill a pipe buffer (~64 KiB) on the stream
// that is not being read yet. Current callers: budget derivation (a handful of run
// ids) and the script self-tests, whose worst case is a few KiB -- per-attempt log
// tails are bounded by the scripts' own TAIL_LINES, and warnings go to stderr. A
// future caller that can emit more than a pipe buffer on either stream must read both
// concurrently instead of extending this comment.
func runProcess(_ executableURL: URL, _ arguments: [String], stdin: String) throws
    -> (stdout: String, stderr: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    try stdinPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
    try stdinPipe.fileHandleForWriting.close()

    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return (String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self),
            process.terminationStatus)
}
