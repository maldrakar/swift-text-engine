import Foundation
import XCTest

// Every script in .github/scripts that implements --self-test. Kept honest by
// testTableCoversEveryScriptWithASelfTest below: a new script with a self-test that is
// not enrolled here fails the build, instead of silently joining the set of checks
// that cannot fail.
private let selfTestScripts = [
    "cross-target-compile.sh",
    "derive-gate-budgets.sh",
    "harvest-gate-corpus.sh",
    "detect-docs-only-pr.sh",
]

private func scriptsDirectory() -> URL {
    repositoryRoot().appendingPathComponent(".github/scripts")
}

final class ScriptSelfTestTests: XCTestCase {
    // Three assertions per script, none redundant: the exit status catches a hard
    // failure; the pass token catches a script degenerating into a silent no-op; the
    // absence of a fail token catches an assertion whose `exit 1` was swallowed by a
    // subshell -- the defect Task 1 reproduced and fixed.
    func testEveryScriptSelfTestPasses() throws {
        XCTAssertFalse(selfTestScripts.isEmpty, "empty table would pass vacuously")
        for name in selfTestScripts {
            let scriptURL = scriptsDirectory().appendingPathComponent(name)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: scriptURL.path),
                "script not found: \(scriptURL.path)")

            let result = try runProcess(
                URL(fileURLWithPath: "/usr/bin/env"),
                ["bash", scriptURL.path, "--self-test"],
                stdin: "")
            let detail = """
                script: \(scriptURL.path)
                exit: \(result.exitCode)
                --- stdout ---
                \(result.stdout)
                --- stderr ---
                \(result.stderr)
                """

            XCTAssertEqual(result.exitCode, 0, "self-test exited non-zero\n\(detail)")
            XCTAssertTrue(
                result.stdout.contains("self_test=pass"),
                "no self_test=pass line\n\(detail)")
            XCTAssertFalse(
                result.stdout.contains("self_test=fail"),
                "a self_test=fail line survived a zero exit\n\(detail)")
        }
    }

    func testTableCoversEveryScriptWithASelfTest() throws {
        let directory = scriptsDirectory()
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var discovered: Set<String> = []
        for entry in entries where entry.hasSuffix(".sh") {
            let source = try String(
                contentsOf: directory.appendingPathComponent(entry), encoding: .utf8)
            if source.contains("--self-test") { discovered.insert(entry) }
        }
        XCTAssertFalse(discovered.isEmpty, "no script with a self-test was discovered")
        XCTAssertEqual(
            discovered, Set(selfTestScripts),
            "enroll every script that has a --self-test in selfTestScripts, or the new "
                + "one's assertions cannot fail a build")
    }
}
