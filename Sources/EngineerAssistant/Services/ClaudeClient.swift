import Foundation

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeStreamChunk {
    let text: String
}

enum ClaudeError: Error, LocalizedError {
    case missingAPIKey
    case httpError(Int, String)
    case decodingError
    case noToolUseInResponse
    case invalidCourseSchema(String)
    case refused(String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Anthropic API key is not set. Open Settings."
        case .httpError(let code, let body): return "Claude API error \(code): \(body)"
        case .decodingError: return "Failed to decode Claude response."
        case .noToolUseInResponse: return "Claude did not return a course (no tool_use block)."
        case .invalidCourseSchema(let why): return "Course JSON did not match schema: \(why)"
        case .refused(let category):
            let topic = category.map { " (\($0))" } ?? ""
            return "Claude declined this request\(topic). Try rephrasing it, or pick a different subject."
        }
    }
}

final class ClaudeClient {
    static let defaultModel = "claude-opus-5"

    /// Effort trades thoroughness against latency and cost. Chat wants to feel responsive;
    /// designing a whole course is worth thinking about properly.
    enum Effort: String {
        case low, medium, high
    }
    static let askModeSystemPrompt = """
    You are a friendly, patient tutor for a high-school STEM student who is learning MacOS, Linux, system administration, and coding. \
    Keep answers short and concrete: prefer concise explanations with one or two examples. \
    When a command-line example is appropriate, show it in a fenced code block. \
    If the student's question would be much better served by a structured, hands-on lesson, briefly say so and suggest they switch to Course Mode at the top of the chat. \
    Be encouraging. Never invent command-line flags or behavior; if you are unsure, say so.
    """

    static let askAgentSystemPrompt = """
    You are a friendly, patient tutor for a high-school STEM student learning about their new Mac, plus Linux, system administration, and coding. \
    You can run read-only shell commands on THIS Mac with the run_command tool to answer questions about the actual machine — its IP address, macOS version, disk space, hardware, running processes, and network setup. \
    When a question depends on this Mac's real state, call run_command and answer with the real value; briefly show the command you used so the student learns it. \
    Use ONE simple command per call, with no pipes, redirection, or chaining (e.g. `ipconfig getifaddr en0`, `sw_vers`, `system_profiler SPHardwareDataType`). \
    Only a small allowlist of read-only commands is permitted and you can never modify the system. If a command is refused, tell the student the exact command they could run themselves in Terminal. \
    If a question doesn't need this Mac's state, just answer normally. Keep answers short and concrete.
    """

    static var runCommandTool: [String: Any] {
        [
            "name": "run_command",
            "description": "Run ONE read-only shell command on the student's Mac to answer a question about it (IP address, macOS version, disk space, CPU/RAM, processes, network interfaces). One simple command, no pipes/redirection/chaining. Only a read-only allowlist is permitted; a refused command returns an explanation.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "The single command to run, e.g. 'ipconfig getifaddr en0'."]
                ],
                "required": ["command"]
            ]
        ]
    }

    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Transport

    /// Builds a request body. Every call goes through here so model, effort, and token budget
    /// are set consistently in one place.
    private func makeBody(system: String,
                          messages: [[String: Any]],
                          maxTokens: Int,
                          effort: Effort,
                          tools: [[String: Any]]? = nil,
                          toolChoice: [String: Any]? = nil,
                          model: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
            "output_config": ["effort": effort.rawValue],
            "stream": true
        ]
        if let tools { body["tools"] = tools }
        if let toolChoice { body["tool_choice"] = toolChoice }
        return body
    }

    /// The single place a request is sent. Streaming is used everywhere: thinking is on by
    /// default on this model and counts against `max_tokens`, so the budgets here are large
    /// enough that a non-streamed request would risk an HTTP timeout.
    /// `onText` receives assistant text as it arrives, so the student sees a reply forming
    /// instead of a spinner.
    private func send(_ body: [String: Any], onText: ((String) -> Void)? = nil) async throws -> StreamedMessage {
        guard let apiKey = Keychain.get(KeychainKeys.anthropicAPIKey), !apiKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 300
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.httpError(0, "no response") }
        if http.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line + "\n" }
            throw ClaudeError.httpError(http.statusCode, errorBody)
        }

        var accumulator = ClaudeStreamAccumulator()
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !json.isEmpty, let data = json.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            accumulator.consume(event, onText: onText)
        }

        let result = accumulator.result
        // A refusal is an HTTP 200 with empty or partial content; surfacing it as an answer
        // would show the student a truncated reply with no explanation.
        if result.wasRefused { throw ClaudeError.refused(result.refusalCategory) }
        return result
    }

    /// Ask Mode agent: runs the tool-use loop, executing each requested command via `runCommand`
    /// (which the caller gates through the read-only allowlist), until Claude produces a final
    /// answer. Returns that answer's text.
    func askAgent(
        history: [ChatMessage],
        runCommand: @escaping (String) async -> String,
        onText: @escaping (String) -> Void,
        maxIterations: Int = 8,
        model: String = defaultModel
    ) async throws -> Void {
        var messages: [[String: Any]] = history.map { ["role": $0.role.rawValue, "content": $0.text] }

        for _ in 0..<maxIterations {
            let body = makeBody(
                system: Self.askAgentSystemPrompt,
                messages: messages,
                maxTokens: 8192,
                effort: .low,
                tools: [Self.runCommandTool],
                model: model
            )
            let result = try await send(body, onText: onText)
            // Echo the assistant turn back verbatim — thinking blocks included, unchanged.
            messages.append(["role": "assistant", "content": result.content])

            guard result.stopReason == "tool_use" else { return }

            var results: [[String: Any]] = []
            for block in result.content where (block["type"] as? String) == "tool_use" {
                let id = block["id"] as? String ?? ""
                let command = (block["input"] as? [String: Any])?["command"] as? String ?? ""
                let output = await runCommand(command)
                results.append(["type": "tool_result", "tool_use_id": id, "content": output])
            }
            messages.append(["role": "user", "content": results])
        }
        onText("\n\nI ran several commands but couldn't wrap up — try asking a bit more specifically.")
    }

    func streamAskResponse(
        history: [ChatMessage],
        contextPreamble: String? = nil,
        model: String = defaultModel
    ) -> AsyncThrowingStream<ClaudeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let system = Self.askModeSystemPrompt + (contextPreamble.map {
                        "\n\nThe student is currently in a lesson. Use this context when relevant:\n\($0)"
                    } ?? "")
                    let body = makeBody(
                        system: system,
                        messages: history.map { ["role": $0.role.rawValue, "content": $0.text] },
                        maxTokens: 8192,
                        effort: .low,
                        model: model
                    )
                    _ = try await send(body) { continuation.yield(ClaudeStreamChunk(text: $0)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    static let courseModeSystemPrompt = """
    You design short, hands-on lessons for a high-school STEM student learning MacOS, Linux, system administration, and coding.

    Given a subject, design a SHORT course of 3 to 5 lessons total. Every lesson must be runnable in a single shell environment.

    Pick the environment: use "macos" for topics about the macOS shell, MacOS administration, or Apple-specific tooling; use "linux" for bash, Linux sysadmin, web server topics, or anything that benefits from a sandboxed Linux container.

    For each lesson include:
    - concept_md: 100-200 word markdown explanation, with one or two short inline code examples.
    - demos: 2 to 4 real commands the student should READ before trying. expected_output should be realistic and short.
    - practice_prompt: one short paragraph inviting the student to experiment in the shell.
    - challenge: one specific task with a deterministic verify check.
    - recap_md: 2-3 markdown bullets naming what the student can now do, phrased as skills rather than a summary of the text.

    Whenever a challenge assumes the student already has something to work with — a file to edit, a script to fix, data to count — you MUST supply it in `starter_files`, because the sandbox starts empty. `starter_state` is only the prose description shown to the student; it creates nothing. Prefer challenges that start from a seeded file: repairing a broken script or investigating real data teaches more than creating a file from scratch.

    Also emit a `final_challenge`: one capstone task that combines what the lessons covered. It uses the same shape as a lesson challenge (including `starter_files`) and is offered alongside the last lesson.

    Verify types:
    - exit_code: { "type":"exit_code", "exit_code": N } -- last command's exit code equals N.
    - stdout_regex: { "type":"stdout_regex", "value": "regex" } -- last stdout matches regex.
    - file_exists: { "type":"file_exists", "path": "~/name" } -- file exists in the sandbox.
    - file_contains: { "type":"file_contains", "path":"~/name", "value":"substring" } -- file contains substring.
    - llm_judge: { "type":"llm_judge", "value":"criteria" } -- open-ended. Use sparingly.

    All file paths — in the task text, starter_state, and verify checks — MUST be relative to the student's home directory: use `~/name` or a bare `name`. NEVER use an absolute path like `/Users/...` or `/home/...`; the sandbox HOME is a fresh, empty directory whose real location varies.

    Aim for deterministic verifications (exit_code, file_exists, file_contains) wherever possible.
    Emit the course via the emit_course tool. Do not include any prose outside the tool call.
    """

    static var emitCourseToolSchema: [String: Any] {
        let verifySchema: [String: Any] = [
            "type": "object",
            "properties": [
                "type": ["type": "string", "enum": ["exit_code", "stdout_regex", "file_exists", "file_contains", "llm_judge"]],
                "value": ["type": "string"],
                "path": ["type": "string"],
                "exit_code": ["type": "integer"]
            ],
            "required": ["type"]
        ]
        let starterFileSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "Home-relative path, e.g. `~/data.txt` or `data.txt`."],
                "content": ["type": "string", "description": "Exact file contents to write."],
                "executable": ["type": "boolean", "description": "True for scripts the student runs."]
            ],
            "required": ["path", "content"]
        ]
        let challengeSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "task": ["type": "string"],
                "starter_state": ["type": "string"],
                "starter_files": ["type": "array", "items": starterFileSchema],
                "verify": verifySchema
            ],
            "required": ["task", "verify"]
        ]
        let lessonSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "concept_md": ["type": "string"],
                "demos": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "command": ["type": "string"],
                            "expected_output": ["type": "string"],
                            "explanation": ["type": "string"]
                        ],
                        "required": ["command", "expected_output", "explanation"]
                    ]
                ],
                "practice_prompt": ["type": "string"],
                "challenge": challengeSchema,
                "recap_md": ["type": "string", "description": "2-3 markdown bullets naming what the student should now be able to do."]
            ],
            "required": ["title", "concept_md", "demos", "practice_prompt", "challenge", "recap_md"]
        ]
        return [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "description": ["type": "string"],
                "estimated_minutes": ["type": "integer"],
                "environment": ["type": "string", "enum": ["macos", "linux"]],
                "prerequisites": ["type": "array", "items": ["type": "string"]],
                "lessons": ["type": "array", "items": lessonSchema, "minItems": 3, "maxItems": 5],
                "final_challenge": challengeSchema
            ],
            "required": ["title", "description", "estimated_minutes", "environment", "prerequisites", "lessons", "final_challenge"]
        ]
    }

    func generateCourse(subject: String, containerGuidance: String? = nil, model: String = defaultModel) async throws -> CourseDraft {
        let tool: [String: Any] = [
            "name": "emit_course",
            "description": "Emit a structured course design for the requested subject.",
            "input_schema": Self.emitCourseToolSchema
        ]
        let body = makeBody(
            system: Self.courseModeSystemPrompt + (containerGuidance.map { "\n\n\($0)" } ?? ""),
            messages: [["role": "user", "content": "Design a course on: \(subject)"]],
            // A 3–5 lesson course is a large tool_use payload; 4096 truncated it mid-JSON
            // (the input came back missing `lessons`). Give it ample headroom.
            maxTokens: 32000,
            effort: .high, // designing a whole course is worth thinking about properly
            tools: [tool],
            toolChoice: ["type": "tool", "name": "emit_course"],
            model: model
        )

        let result = try await send(body)
        guard let block = result.content.first(where: { ($0["type"] as? String) == "tool_use" }),
              let input = block["input"] as? [String: Any] else {
            throw ClaudeError.noToolUseInResponse
        }

        let inputData = try JSONSerialization.data(withJSONObject: input)
        do {
            return try JSONDecoder().decode(CourseDraft.self, from: inputData)
        } catch {
            // A truncated generation (hit max_tokens) yields a partial tool input that fails
            // to decode; surface that distinctly from a genuinely malformed schema.
            if result.stopReason == "max_tokens" {
                throw ClaudeError.invalidCourseSchema("the course response was cut off at the output-token limit. Try regenerating or a narrower subject.")
            }
            throw ClaudeError.invalidCourseSchema(String(describing: error))
        }
    }

    /// Grades an open-ended challenge from a shell transcript. Returns (passed, reason).
    func judge(criteria: String, transcript: String, model: String = defaultModel) async throws -> (Bool, String) {
        let system = """
        You grade a high-school student's shell exercise. Given success criteria and a transcript of \
        their session, decide whether they met the criteria. Reply with exactly one line, either \
        "PASS: <short reason>" or "FAIL: <short reason>". Be lenient about style, strict about whether \
        the goal was actually achieved.
        """
        let text = try await complete(
            system: system,
            user: "Success criteria:\n\(criteria)\n\nTranscript:\n\(transcript)",
            maxTokens: 2048,
            effort: .medium, // grading is a judgement call worth a little thought
            model: model
        )
        let passed = text.uppercased().hasPrefix("PASS")
        return (passed, text)
    }

    /// A short, contextual hint for a stuck student that nudges without revealing the answer.
    func hint(lessonTitle: String, concept: String, task: String, transcript: String, model: String = defaultModel) async throws -> String {
        let system = """
        You are a patient tutor for a high-school student stuck on a shell challenge. Give ONE short, \
        encouraging hint (1–2 sentences) that nudges them toward the next step. Do NOT give the full \
        command or the complete answer — point at the idea or the tool to try.
        """
        return try await complete(
            system: system,
            user: """
            Lesson: \(lessonTitle)
            Concept: \(concept)
            Challenge: \(task)

            What the student has done so far in the shell:
            \(transcript.isEmpty ? "(nothing yet)" : transcript)
            """,
            maxTokens: 2048,
            effort: .low,
            model: model
        )
    }

    /// One system + user turn in, trimmed text out — the shape every non-agentic helper needs.
    private func complete(system: String,
                          user: String,
                          maxTokens: Int,
                          effort: Effort,
                          model: String) async throws -> String {
        let body = makeBody(
            system: system,
            messages: [["role": "user", "content": user]],
            maxTokens: maxTokens,
            effort: effort,
            model: model
        )
        let text = try await send(body).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeError.decodingError }
        return text
    }
}
