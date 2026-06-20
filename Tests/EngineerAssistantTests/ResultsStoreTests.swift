import XCTest
@testable import EngineerAssistant

final class ResultsStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("results-\(UUID().uuidString).json")
    }

    private func attempt(_ idx: Int, attempt: Int = 1, passed: Bool, at t: TimeInterval = 0) -> LessonAttempt {
        LessonAttempt(id: UUID().uuidString, attempt: attempt, lessonIdx: idx, lessonTitle: "L\(idx)",
                      passed: passed, detail: "d", command: "c", hintUsed: false, timestamp: Date(timeIntervalSince1970: t))
    }

    func testRecordAndSummarize() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = FileResultsStore(url: url)
        XCTAssertNil(store.results(for: "c1"))

        store.record(attempt(0, passed: false, at: 1), courseId: "c1", subject: "s", title: "t", lessonCount: 3)
        store.record(attempt(0, passed: true, at: 2), courseId: "c1", subject: "s", title: "t", lessonCount: 3)
        store.record(attempt(1, passed: true, at: 3), courseId: "c1", subject: "s", title: "t", lessonCount: 3)

        let r = store.results(for: "c1")!
        XCTAssertEqual(r.currentAttempt, 1)
        XCTAssertEqual(r.passedCount, 2)                       // lessons 0 and 1 passed
        XCTAssertTrue(r.latest(lessonIdx: 0, attempt: 1)!.passed) // latest of lesson 0 is the pass
    }

    func testNewAttemptKeepsHistoryAndResetsSummary() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = FileResultsStore(url: url)
        store.record(attempt(0, passed: true, at: 1), courseId: "c1", subject: "s", title: "t", lessonCount: 2)

        let n = store.startNewAttempt(courseId: "c1", subject: "s", title: "t", lessonCount: 2)
        XCTAssertEqual(n, 2)

        let r = store.results(for: "c1")!
        XCTAssertEqual(r.attempts.count, 1)        // history preserved
        XCTAssertEqual(r.passedCount, 0)           // nothing passed in attempt 2 yet
    }

    func testClearLessonAndRemoveCourse() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = FileResultsStore(url: url)
        store.record(attempt(0, passed: true, at: 1), courseId: "c1", subject: "s", title: "t", lessonCount: 2)
        store.record(attempt(1, passed: true, at: 2), courseId: "c1", subject: "s", title: "t", lessonCount: 2)

        store.clearLesson(courseId: "c1", lessonIdx: 0)
        XCTAssertEqual(store.results(for: "c1")!.passedCount, 1)
        XCTAssertNil(store.results(for: "c1")!.latest(lessonIdx: 0, attempt: 1))

        store.remove(courseId: "c1")
        XCTAssertNil(store.results(for: "c1"))
    }
}
