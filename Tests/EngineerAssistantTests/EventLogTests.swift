import XCTest
@testable import EngineerAssistant

final class EventLogTests: XCTestCase {
    func testJSONLEventStoreRoundTrip() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = JSONLEventStore(fileURL: tmp)
        let sessionId = try await store.startSession()
        try await store.append(LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: .chatUser,
            courseId: nil,
            lessonIdx: nil,
            payload: ["text": AnyCodable("hello"), "mode": AnyCodable("ask")]
        ))
        try await store.endSession(sessionId, reason: "test")

        let data = try Data(contentsOf: tmp)
        let lines = String(data: data, encoding: .utf8)!
            .split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("session_start"))
        XCTAssertTrue(lines[1].contains("chat_user"))
        XCTAssertTrue(lines[1].contains("hello"))
        XCTAssertTrue(lines[2].contains("session_end"))
    }

    /// App termination doesn't wait for async work, so the quit path writes `session_end`
    /// synchronously. Without it every session reads "in progress" forever in the dashboard.
    func testEndSessionSynchronouslyLandsOnDisk() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = JSONLEventStore(fileURL: tmp)
        let sessionId = try await store.startSession()
        store.endSessionSynchronously(sessionId, reason: "quit")

        let text = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(text.contains("session_end"))
        XCTAssertTrue(text.contains("quit"))

        // And the reader turns that into a finished session with a real duration.
        let sessions = EventLogReader.loadSessions(from: tmp)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions.first?.endedAt, "session should be closed")
        XCTAssertNotNil(sessions.first?.duration, "dashboard shows a duration, not 'in progress'")
    }

    func testChatMessageDefaults() {
        let msg = ChatMessage(role: .user, mode: .ask, text: "hi")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.mode, .ask)
        XCTAssertEqual(msg.text, "hi")
    }
}
