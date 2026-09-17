import Foundation

/// One yes/no question for the System One endpoint. `instructions` asks it; `whenTrue` and
/// `whenFalse` say what each answer would mean, which is what keeps the probability calibrated
/// rather than a vibe.
struct NoulQuestion {
    let id: String
    let instructions: String
    let whenTrue: String
    let whenFalse: String
}

enum TypeSafeError: Error, LocalizedError {
    case missingAPIKey
    case httpError(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "TypeSafe API key is not set."
        case .httpError(let code, let body): return "TypeSafe API error \(code): \(body)"
        case .decodingError: return "Failed to decode the TypeSafe response."
        }
    }
}

/// Minimal client for TypeSafe's System One endpoint, which serves the Jev model.
///
/// Jev is not a chat model and this is not a second `ClaudeClient`. You hand it a block of state
/// plus a set of typed questions and it answers each one with a probability — no prose, no
/// reasoning, nothing to parse. That makes a judgement usable as an ordinary function returning
/// `[question id: 0...1]`, which is all `CourseGate` wants.
///
/// Every question is asked against the same state in one request. Questions can't see one
/// another's answers, so batching them costs one round trip instead of N.
struct TypeSafeClient {
    static let model = "jev-latest"

    private let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The gate is optional: with no key stored, callers skip it rather than fail.
    static var isConfigured: Bool {
        !(Keychain.get(KeychainKeys.typeSafeAPIKey) ?? "").isEmpty
    }

    func ask(state: [String: Any], questions: [NoulQuestion]) async throws -> [String: Double] {
        guard let apiKey = Keychain.get(KeychainKeys.typeSafeAPIKey), !apiKey.isEmpty else {
            throw TypeSafeError.missingAPIKey
        }

        var questionBody: [String: Any] = [:]
        for question in questions {
            questionBody[question.id] = [
                "type": "noul",
                "instructions": question.instructions,
                "criteria": ["true": question.whenTrue, "false": question.whenFalse]
            ]
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "state": state,
            "model": Self.model,
            "questions": questionBody
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TypeSafeError.httpError(0, "no response") }
        guard http.statusCode == 200 else {
            throw TypeSafeError.httpError(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        return try Self.parse(data)
    }

    /// Pulls `answers.<id>.noul` out of a response body. Separated so it can be tested without
    /// a network round trip.
    static func parse(_ data: Data) throws -> [String: Double] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: Any] else {
            throw TypeSafeError.decodingError
        }
        var out: [String: Double] = [:]
        for (id, answer) in answers {
            if let noul = (answer as? [String: Any])?["noul"] as? Double { out[id] = noul }
        }
        return out
    }
}
