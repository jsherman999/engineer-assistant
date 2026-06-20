import XCTest
@testable import EngineerAssistant

/// Drives the persistence sequence behind the library/player flows end-to-end through the
/// real `File*` stores, mirroring exactly what `AppSession.deleteCourse / retakeCourse /
/// clearLessonResults / recordResult` compose. (The GUI is a thin layer over these.)
final class CourseFlowIntegrationTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeCourse() -> Course {
        let verify = VerifyCheck(type: .fileExists, value: nil, path: "hello.txt", exitCode: nil)
        let lessons = (0..<3).map { i in
            Lesson(title: "Lesson \(i)", conceptMd: "c", demos: [], practicePrompt: "p",
                   challenge: Challenge(task: "t", starterState: nil, verify: verify))
        }
        let draft = CourseDraft(title: "Flow Course", description: "d", estimatedMinutes: 10,
                                environment: .macos, prerequisites: [], lessons: lessons, finalChallenge: nil)
        return Course(id: "flow-1", subject: "flow subject", draft: draft)
    }

    func testRecordRetakeClearSummaryFlow() throws {
        let results = FileResultsStore(url: dir.appendingPathComponent("results.json"))
        let course = makeCourse()

        // recordResult: pass lessons 0 and 1.
        for idx in 0...1 {
            let a = LessonAttempt(id: UUID().uuidString, attempt: 1, lessonIdx: idx, lessonTitle: "Lesson \(idx)",
                                  passed: true, detail: "ok", command: "touch hello.txt", hintUsed: false,
                                  timestamp: Date())
            results.record(a, courseId: course.id, subject: course.subject, title: course.title, lessonCount: 3)
        }
        XCTAssertEqual(results.results(for: course.id)?.passedCount, 2, "library summary should show 2/3 passed")

        // retakeCourse: new attempt keeps history, resets the visible summary.
        let attempt = results.startNewAttempt(courseId: course.id, subject: course.subject, title: course.title, lessonCount: 3)
        XCTAssertEqual(attempt, 2)
        XCTAssertEqual(results.results(for: course.id)?.passedCount, 0, "fresh attempt shows nothing passed yet")
        XCTAssertEqual(results.results(for: course.id)?.attempts.count, 2, "prior attempt kept as history")

        // clearLessonResults: purge one lesson across attempts.
        let a = LessonAttempt(id: UUID().uuidString, attempt: 2, lessonIdx: 0, lessonTitle: "Lesson 0",
                              passed: true, detail: "ok", command: "touch hello.txt", hintUsed: true, timestamp: Date())
        results.record(a, courseId: course.id, subject: course.subject, title: course.title, lessonCount: 3)
        results.clearLesson(courseId: course.id, lessonIdx: 0)
        XCTAssertNil(results.results(for: course.id)?.latest(lessonIdx: 0, attempt: 2), "cleared lesson has no result")
        XCTAssertNil(results.results(for: course.id)?.latest(lessonIdx: 0, attempt: 1), "clear removes it from history too")
    }

    /// Mirrors AppSession.deleteCourse: course JSON + progress + results + sandbox dir all purged.
    func testDeleteCoursePurgesEverything() throws {
        let courseStore = FileCourseStore(directory: dir.appendingPathComponent("courses"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("courses"), withIntermediateDirectories: true)
        let progress = FileProgressStore(url: dir.appendingPathComponent("progress.json"))
        let results = FileResultsStore(url: dir.appendingPathComponent("results.json"))
        let course = makeCourse()

        try courseStore.save(course)
        progress.set(CourseProgress(lessonIdx: 1, completed: false), for: course.id)
        results.record(LessonAttempt(id: "x", attempt: 1, lessonIdx: 0, lessonTitle: "Lesson 0", passed: true,
                                     detail: "ok", command: "c", hintUsed: false, timestamp: Date()),
                       courseId: course.id, subject: course.subject, title: course.title, lessonCount: 3)
        let sandbox = dir.appendingPathComponent("sandboxes/\(course.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        // Preconditions.
        XCTAssertNotNil(courseStore.load(subject: course.subject))
        XCTAssertNotNil(progress.progress(for: course.id))
        XCTAssertNotNil(results.results(for: course.id))

        // deleteCourse composition.
        try courseStore.delete(course)
        progress.remove(courseId: course.id)
        results.remove(courseId: course.id)
        try FileManager.default.removeItem(at: sandbox)

        XCTAssertNil(courseStore.load(subject: course.subject), "course JSON gone")
        XCTAssertNil(progress.progress(for: course.id), "progress gone")
        XCTAssertNil(results.results(for: course.id), "results gone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.path), "sandbox dir gone")
        XCTAssertTrue(courseStore.listAll().isEmpty, "library no longer lists the course")
    }
}
