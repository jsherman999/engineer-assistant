import XCTest
@testable import EngineerAssistant

final class ProgressStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString).json")
    }

    func testSetAndGetRoundTrip() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = FileProgressStore(url: url)
        XCTAssertNil(store.progress(for: "course-1"))

        store.set(CourseProgress(lessonIdx: 2, completed: false), for: "course-1")
        XCTAssertEqual(store.progress(for: "course-1"), CourseProgress(lessonIdx: 2, completed: false))
    }

    func testUpdateOverwritesAndKeepsOthers() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = FileProgressStore(url: url)
        store.set(CourseProgress(lessonIdx: 1, completed: false), for: "a")
        store.set(CourseProgress(lessonIdx: 0, completed: false), for: "b")
        store.set(CourseProgress(lessonIdx: 4, completed: true), for: "a")

        XCTAssertEqual(store.progress(for: "a"), CourseProgress(lessonIdx: 4, completed: true))
        XCTAssertEqual(store.progress(for: "b"), CourseProgress(lessonIdx: 0, completed: false))
    }

    func testPersistsAcrossInstances() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        FileProgressStore(url: url).set(CourseProgress(lessonIdx: 3, completed: false), for: "x")
        // Simulates relaunch: a fresh store reading the same file resumes at the saved lesson.
        XCTAssertEqual(FileProgressStore(url: url).progress(for: "x"), CourseProgress(lessonIdx: 3, completed: false))
    }
}
