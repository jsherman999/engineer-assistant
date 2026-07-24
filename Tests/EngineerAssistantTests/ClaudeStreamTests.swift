import XCTest
@testable import EngineerAssistant

/// The accumulator is what makes streaming safe for the agent loop: assistant turns are echoed
/// straight back to the API, so any block it mangles or drops breaks the next request.
final class ClaudeStreamTests: XCTestCase {
    private func event(_ json: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    func testAccumulatesTextAndReportsDeltas() {
        var acc = ClaudeStreamAccumulator()
        var streamed = ""

        acc.consume(event(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)) { streamed += $0 }
        acc.consume(event(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Your IP "}}"#)) { streamed += $0 }
        acc.consume(event(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"is 10.0.0.4"}}"#)) { streamed += $0 }
        acc.consume(event(#"{"type":"content_block_stop","index":0}"#))
        acc.consume(event(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#))

        let result = acc.result
        XCTAssertEqual(result.text, "Your IP is 10.0.0.4")
        XCTAssertEqual(streamed, "Your IP is 10.0.0.4", "deltas arrive live, not only at the end")
        XCTAssertEqual(result.stopReason, "end_turn")
        XCTAssertFalse(result.wasRefused)
    }

    /// Tool inputs arrive as a stream of JSON fragments and are only valid once reassembled.
    func testAssemblesToolInputFromPartialJSON() {
        var acc = ClaudeStreamAccumulator()
        acc.consume(event(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"run_command","input":{}}}"#))
        acc.consume(event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"comm"}}"#))
        acc.consume(event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"and\": \"sw_vers\"}"}}"#))
        acc.consume(event(#"{"type":"content_block_stop","index":0}"#))
        acc.consume(event(#"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#))

        let block = acc.result.content.first
        XCTAssertEqual(block?["type"] as? String, "tool_use")
        XCTAssertEqual(block?["id"] as? String, "toolu_1")
        XCTAssertEqual((block?["input"] as? [String: Any])?["command"] as? String, "sw_vers")
        XCTAssertEqual(acc.result.stopReason, "tool_use")
    }

    /// Thinking blocks must survive verbatim — including the signature — because the agent loop
    /// sends the assistant turn back and the API rejects tampered blocks.
    func testPreservesThinkingBlocksForReplay() {
        var acc = ClaudeStreamAccumulator()
        acc.consume(event(#"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#))
        acc.consume(event(#"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"check the OS"}}"#))
        acc.consume(event(#"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc123"}}"#))
        acc.consume(event(#"{"type":"content_block_stop","index":0}"#))
        acc.consume(event(#"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#))
        acc.consume(event(#"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"macOS 26"}}"#))
        acc.consume(event(#"{"type":"content_block_stop","index":1}"#))

        let content = acc.result.content
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "thinking")
        XCTAssertEqual(content[0]["thinking"] as? String, "check the OS")
        XCTAssertEqual(content[0]["signature"] as? String, "abc123")
        XCTAssertEqual(acc.result.text, "macOS 26", "text ignores thinking blocks")
    }

    /// Blocks are keyed by index, so out-of-order events still rebuild in the right order.
    func testOrdersBlocksByIndexNotArrival() {
        var acc = ClaudeStreamAccumulator()
        acc.consume(event(#"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":"second"}}"#))
        acc.consume(event(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"first "}}"#))
        XCTAssertEqual(acc.result.text, "first second")
    }

    /// A refusal is an HTTP 200 with empty or partial content; it must not read as an answer.
    func testDetectsRefusal() {
        var acc = ClaudeStreamAccumulator()
        acc.consume(event(#"{"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}}"#))

        XCTAssertTrue(acc.result.wasRefused)
        XCTAssertEqual(acc.result.refusalCategory, "cyber")
    }

    func testIgnoresUnknownEventsAndMalformedDeltas() {
        var acc = ClaudeStreamAccumulator()
        acc.consume(event(#"{"type":"ping"}"#))
        acc.consume(event(#"{"type":"content_block_delta","index":9,"delta":{"type":"text_delta","text":"orphan"}}"#))
        acc.consume(event(#"{"type":"content_block_stop","index":9}"#))
        XCTAssertTrue(acc.result.content.isEmpty, "a delta with no matching start is dropped, not crashed on")
    }
}
