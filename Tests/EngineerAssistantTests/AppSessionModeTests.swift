import XCTest
@testable import EngineerAssistant

@MainActor
final class AppSessionModeTests: XCTestCase {
    func testAskAndCourseKeepSeparateTranscripts() {
        let session = AppSession()

        session.messages = [ChatMessage(role: .user, mode: .ask, text: "ask-1")]

        // Toggle to Course → a fresh, empty screen (Ask transcript stashed).
        session.currentMode = .course
        XCTAssertTrue(session.messages.isEmpty)

        session.messages = [ChatMessage(role: .user, mode: .course, text: "course-1")]

        // Toggle back to Ask → Ask transcript restored, not the course one.
        session.currentMode = .ask
        XCTAssertEqual(session.messages.map(\.text), ["ask-1"])

        // Toggle to Course again → its progress is preserved.
        session.currentMode = .course
        XCTAssertEqual(session.messages.map(\.text), ["course-1"])
    }
}
