import Foundation

/// A fully accumulated streamed response: the content blocks in order, plus why it stopped.
struct StreamedMessage {
    let content: [[String: Any]]
    let stopReason: String?
    let stopDetails: [String: Any]?

    /// Concatenated text blocks — what the student reads.
    var text: String {
        content.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined()
    }

    /// Safety classifiers declined the request. `content` is empty (declined before any output)
    /// or partial (declined mid-stream); either way it must not be shown as a real answer.
    var wasRefused: Bool { stopReason == "refusal" }

    var refusalCategory: String? { stopDetails?["category"] as? String }
}

/// Rebuilds whole content blocks from a `/v1/messages` SSE stream.
///
/// Blocks are accumulated by merging deltas into the dictionary that arrived with
/// `content_block_start`, so every block type round-trips without the accumulator needing to
/// know about it. That matters for the tool-use loop: thinking blocks have to be echoed back
/// to the API byte-identical, and a hand-written per-type accumulator silently drops the
/// fields it wasn't taught about.
struct ClaudeStreamAccumulator {
    private var blocks: [Int: [String: Any]] = [:]
    private var partialJSON: [Int: String] = [:]
    private(set) var stopReason: String?
    private(set) var stopDetails: [String: Any]?

    mutating func consume(_ event: [String: Any], onText: ((String) -> Void)? = nil) {
        guard let type = event["type"] as? String else { return }
        switch type {
        case "content_block_start":
            guard let index = event["index"] as? Int else { return }
            blocks[index] = event["content_block"] as? [String: Any] ?? [:]
            partialJSON[index] = ""

        case "content_block_delta":
            guard let index = event["index"] as? Int,
                  let delta = event["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return }
            switch deltaType {
            case "text_delta":
                let chunk = delta["text"] as? String ?? ""
                append(chunk, toKey: "text", at: index)
                onText?(chunk)
            case "thinking_delta":
                append(delta["thinking"] as? String ?? "", toKey: "thinking", at: index)
            case "signature_delta":
                append(delta["signature"] as? String ?? "", toKey: "signature", at: index)
            case "input_json_delta":
                partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
            default:
                break
            }

        case "content_block_stop":
            guard let index = event["index"] as? Int else { return }
            // Tool inputs stream as JSON text; parse once the block is complete.
            if let json = partialJSON[index], !json.isEmpty,
               let data = json.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                blocks[index]?["input"] = parsed
            }

        case "message_delta":
            if let delta = event["delta"] as? [String: Any] {
                stopReason = delta["stop_reason"] as? String ?? stopReason
                stopDetails = delta["stop_details"] as? [String: Any] ?? stopDetails
            }

        case "message_start":
            if let message = event["message"] as? [String: Any] {
                stopReason = message["stop_reason"] as? String ?? stopReason
            }

        default:
            break
        }
    }

    private mutating func append(_ chunk: String, toKey key: String, at index: Int) {
        guard !chunk.isEmpty else { return }
        let existing = blocks[index]?[key] as? String ?? ""
        blocks[index]?[key] = existing + chunk
    }

    var result: StreamedMessage {
        let ordered = blocks.keys.sorted().compactMap { blocks[$0] }
        return StreamedMessage(content: ordered, stopReason: stopReason, stopDetails: stopDetails)
    }
}
