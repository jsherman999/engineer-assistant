import XCTest
@testable import EngineerAssistant

final class VerifierTests: XCTestCase {
    private let verifier = Verifier(claude: nil)

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("verify-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func context(exit: Int? = nil, stdout: String = "", sandbox: URL) -> VerifyContext {
        VerifyContext(lastExitCode: exit, lastStdout: stdout, sandboxDir: sandbox, transcript: "")
    }

    func testExitCodeMatch() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let check = VerifyCheck(type: .exitCode, value: nil, path: nil, exitCode: 0)
        let out = await verifier.verify(check, context: context(exit: 0, sandbox: dir))
        XCTAssertTrue(out.passed)
    }

    func testExitCodeMismatch() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let check = VerifyCheck(type: .exitCode, value: nil, path: nil, exitCode: 0)
        let out = await verifier.verify(check, context: context(exit: 1, sandbox: dir))
        XCTAssertFalse(out.passed)
    }

    func testExitCodeNoCommandRun() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let check = VerifyCheck(type: .exitCode, value: nil, path: nil, exitCode: 0)
        let out = await verifier.verify(check, context: context(exit: nil, sandbox: dir))
        XCTAssertFalse(out.passed)
    }

    func testStdoutRegexMatch() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let check = VerifyCheck(type: .stdoutRegex, value: "hel+o", path: nil, exitCode: nil)
        let out = await verifier.verify(check, context: context(stdout: "say hello there", sandbox: dir))
        XCTAssertTrue(out.passed)
    }

    func testStdoutRegexNoMatch() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let check = VerifyCheck(type: .stdoutRegex, value: "^goodbye", path: nil, exitCode: nil)
        let out = await verifier.verify(check, context: context(stdout: "hello", sandbox: dir))
        XCTAssertFalse(out.passed)
    }

    func testFileExistsTrueWithRelativePath() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("foo.txt"), atomically: true, encoding: .utf8)
        let check = VerifyCheck(type: .fileExists, value: nil, path: "foo.txt", exitCode: nil)
        let out = await verifier.verify(check, context: context(sandbox: dir))
        XCTAssertTrue(out.passed)
    }

    func testFileExistsTrueWithTildePath() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("bar.txt"), atomically: true, encoding: .utf8)
        let check = VerifyCheck(type: .fileExists, value: nil, path: "~/bar.txt", exitCode: nil)
        let out = await verifier.verify(check, context: context(sandbox: dir))
        XCTAssertTrue(out.passed)
    }

    func testFileExistsFalse() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let check = VerifyCheck(type: .fileExists, value: nil, path: "missing.txt", exitCode: nil)
        let out = await verifier.verify(check, context: context(sandbox: dir))
        XCTAssertFalse(out.passed)
    }

    func testFileContainsSubstring() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try "the quick brown fox".write(to: dir.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let check = VerifyCheck(type: .fileContains, value: "brown", path: "note.txt", exitCode: nil)
        let out = await verifier.verify(check, context: context(sandbox: dir))
        XCTAssertTrue(out.passed)
    }

    func testFileContainsMissingFile() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let check = VerifyCheck(type: .fileContains, value: "x", path: "nope.txt", exitCode: nil)
        let out = await verifier.verify(check, context: context(sandbox: dir))
        XCTAssertFalse(out.passed)
    }

    func testLLMJudgeUnavailableWithoutClient() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let check = VerifyCheck(type: .llmJudge, value: "did they do it?", path: nil, exitCode: nil)
        let out = await verifier.verify(check, context: context(sandbox: dir))
        XCTAssertFalse(out.passed)
    }
}
