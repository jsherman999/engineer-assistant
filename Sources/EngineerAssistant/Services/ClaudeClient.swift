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

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Anthropic API key is not set. Open Settings."
        case .httpError(let code, let body): return "Claude API error \(code): \(body)"
        case .decodingError: return "Failed to decode Claude response."
        }
    }
}

final class ClaudeClient {
    static let defaultModel = "claude-sonnet-4-6"
    static let askModeSystemPrompt = """
    You are a friendly, patient tutor for a high-school STEM student who is learning MacOS, Linux, system administration, and coding. \
    Keep answers short and concrete: prefer concise explanations with one or two examples. \
    When a command-line example is appropriate, show it in a fenced code block. \
    If the student's question would be much better served by a structured, hands-on lesson, briefly say so and suggest they switch to Course Mode at the top of the chat. \
    Be encouraging. Never invent command-line flags or behavior; if you are unsure, say so.
    """

    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func streamAskResponse(
        history: [ChatMessage],
        model: String = defaultModel
    ) -> AsyncThrowingStream<ClaudeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = Keychain.get(KeychainKeys.anthropicAPIKey), !apiKey.isEmpty else {
                        throw ClaudeError.missingAPIKey
                    }

                    let messages = history.map {
                        ClaudeMessage(role: $0.role.rawValue, content: $0.text)
                    }

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 1024,
                        "system": Self.askModeSystemPrompt,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] }
                    ]

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ClaudeError.httpError(0, "no response")
                    }

                    if http.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line + "\n" }
                        throw ClaudeError.httpError(http.statusCode, body)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !json.isEmpty, let data = json.data(using: .utf8) else { continue }
                        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let type = obj["type"] as? String, type == "content_block_delta",
                           let delta = obj["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(ClaudeStreamChunk(text: text))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
