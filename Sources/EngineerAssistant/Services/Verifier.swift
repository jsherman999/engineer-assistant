import Foundation

struct VerifyContext {
    let lastExitCode: Int?
    let lastStdout: String
    let sandboxDir: URL
    let transcript: String
}

struct VerifyOutcome: Equatable {
    let passed: Bool
    let detail: String
}

/// Runs a challenge's verify check. Deterministic checks first; `llm_judge` only when
/// the schema asks for it and a Claude client is available.
struct Verifier {
    let claude: ClaudeClient?

    func verify(_ check: VerifyCheck, context: VerifyContext) async -> VerifyOutcome {
        switch check.type {
        case .exitCode:
            let want = check.exitCode ?? 0
            guard let got = context.lastExitCode else {
                return .init(passed: false, detail: "No command has been run yet.")
            }
            return got == want
                ? .init(passed: true, detail: "Last command exited \(got), as required.")
                : .init(passed: false, detail: "Last command exited \(got); expected \(want).")

        case .stdoutRegex:
            let pattern = check.value ?? ""
            return Self.regexMatches(pattern, context.lastStdout)
                ? .init(passed: true, detail: "Output matched /\(pattern)/.")
                : .init(passed: false, detail: "The last command's output did not match /\(pattern)/.")

        case .fileExists:
            guard let path = check.path else {
                return .init(passed: false, detail: "Challenge is missing a path to check.")
            }
            let url = Self.resolve(path, sandbox: context.sandboxDir)
            return FileManager.default.fileExists(atPath: url.path)
                ? .init(passed: true, detail: "Found \(path).")
                : .init(passed: false, detail: "\(path) does not exist yet.")

        case .fileContains:
            guard let path = check.path else {
                return .init(passed: false, detail: "Challenge is missing a path to check.")
            }
            let url = Self.resolve(path, sandbox: context.sandboxDir)
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                return .init(passed: false, detail: "Could not read \(path).")
            }
            let needle = check.value ?? ""
            let hit = contents.contains(needle) || Self.regexMatches(needle, contents)
            return hit
                ? .init(passed: true, detail: "\(path) contains the expected content.")
                : .init(passed: false, detail: "\(path) does not contain \"\(needle)\" yet.")

        case .llmJudge:
            guard let claude else {
                return .init(passed: false, detail: "LLM judging is unavailable (no API key).")
            }
            let criteria = check.value ?? ""
            do {
                let (passed, reason) = try await claude.judge(criteria: criteria, transcript: context.transcript)
                return .init(passed: passed, detail: reason)
            } catch {
                return .init(passed: false, detail: "Judge failed: \(error.localizedDescription)")
            }
        }
    }

    static func resolve(_ path: String, sandbox: URL) -> URL {
        if path == "~" { return sandbox }
        if path.hasPrefix("~/") { return sandbox.appendingPathComponent(String(path.dropFirst(2))) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return sandbox.appendingPathComponent(path)
    }

    static func regexMatches(_ pattern: String, _ text: String) -> Bool {
        guard !pattern.isEmpty, let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, options: [], range: range) != nil
    }
}
