import XCTest
@testable import EngineerAssistant

final class ReviewPlannerTests: XCTestCase {
    private func course(id: String, title: String, lessons: Int) -> Course {
        let verify = VerifyCheck(type: .exitCode, value: nil, path: nil, exitCode: 0)
        let lessonList = (0..<lessons).map { i in
            Lesson(title: "Lesson \(i)", conceptMd: "c", demos: [], practicePrompt: "p",
                   challenge: Challenge(task: "t", starterState: nil, starterFiles: nil, verify: verify),
                   recapMd: nil, visual: nil)
        }
        let draft = CourseDraft(title: title, description: "d", estimatedMinutes: 10,
                                environment: .macos, prerequisites: [], lessons: lessonList,
                                finalChallenge: nil)
        return Course(id: id, subject: title, draft: draft)
    }

    private func attempt(lesson: Int, passed: Bool, hint: Bool = false, daysAgo: Int, attempt: Int = 1) -> LessonAttempt {
        LessonAttempt(id: UUID().uuidString, attempt: attempt, lessonIdx: lesson,
                      lessonTitle: "Lesson \(lesson)", passed: passed, detail: "d", command: "c",
                      hintUsed: hint,
                      timestamp: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!)
    }

    private func results(_ attempts: [LessonAttempt], lessonCount: Int = 3) -> CourseResults {
        CourseResults(courseId: "c1", subject: "s", title: "Course", lessonCount: lessonCount,
                      currentAttempt: 1, attempts: attempts)
    }

    // MARK: - Intervals

    func testFailedLessonComesBackTheNextDay() {
        let (days, reason) = ReviewPlanner.schedule(for: [attempt(lesson: 0, passed: false, daysAgo: 0)])
        XCTAssertEqual(days, ReviewPlanner.struggledInterval)
        XCTAssertEqual(reason, .struggled)
    }

    func testHintedPassWaitsLongerThanAFailButLessThanACleanPass() {
        let (days, reason) = ReviewPlanner.schedule(for: [attempt(lesson: 0, passed: true, hint: true, daysAgo: 0)])
        XCTAssertEqual(days, ReviewPlanner.hintedInterval)
        XCTAssertEqual(reason, .neededHint)
        XCTAssertGreaterThan(days, ReviewPlanner.struggledInterval)
        XCTAssertLessThan(days, ReviewPlanner.cleanPassIntervals[0])
    }

    /// The point of spacing: each clean pass in a row pushes the next review further out.
    func testConsecutiveCleanPassesStretchTheInterval() {
        var history: [LessonAttempt] = []
        var previous = 0
        for round in 0..<ReviewPlanner.cleanPassIntervals.count {
            history.append(attempt(lesson: 0, passed: true, daysAgo: 100 - round))
            let (days, reason) = ReviewPlanner.schedule(for: history)
            XCTAssertEqual(reason, .spacedInterval)
            XCTAssertGreaterThan(days, previous, "interval should grow with each clean pass")
            previous = days
        }
    }

    /// One slip resets the schedule — that lesson isn't learned yet.
    func testFailureAfterStreakResetsToTomorrow() {
        let history = [
            attempt(lesson: 0, passed: true, daysAgo: 30),
            attempt(lesson: 0, passed: true, daysAgo: 20),
            attempt(lesson: 0, passed: false, daysAgo: 1)
        ]
        XCTAssertEqual(ReviewPlanner.schedule(for: history).days, ReviewPlanner.struggledInterval)
    }

    // MARK: - Due selection

    func testOnlyDueLessonsAreReturned() {
        let c = course(id: "c1", title: "Course", lessons: 3)
        let due = ReviewPlanner.dueItems(
            in: [results([
                attempt(lesson: 0, passed: false, daysAgo: 5),   // due: failed, 1-day interval
                attempt(lesson: 1, passed: true, daysAgo: 0)     // not due: passed today
            ])],
            courses: [c]
        )
        XCTAssertEqual(due.map(\.lessonIdx), [0])
    }

    func testLessonsNeverAttemptedAreNotSurfaced() {
        let c = course(id: "c1", title: "Course", lessons: 3)
        let due = ReviewPlanner.dueItems(in: [results([])], courses: [c])
        XCTAssertTrue(due.isEmpty, "review is for revisiting, not for starting")
    }

    /// Weakest first: what they failed matters more than what has merely gone stale.
    func testStruggledLessonsSortAheadOfStaleOnes() {
        let c = course(id: "c1", title: "Course", lessons: 3)
        let due = ReviewPlanner.dueItems(
            in: [results([
                attempt(lesson: 0, passed: true, daysAgo: 90),        // stale clean pass
                attempt(lesson: 1, passed: true, hint: true, daysAgo: 10), // hinted
                attempt(lesson: 2, passed: false, daysAgo: 3)         // struggled
            ])],
            courses: [c]
        )
        XCTAssertEqual(due.map(\.lessonIdx), [2, 1, 0])
        XCTAssertEqual(due.map(\.reason), [.struggled, .neededHint, .spacedInterval])
    }

    /// A lesson passed before a retake is still learned; history spans attempts.
    func testHistorySpansAttempts() {
        let c = course(id: "c1", title: "Course", lessons: 1)
        let due = ReviewPlanner.dueItems(
            in: [CourseResults(courseId: "c1", subject: "s", title: "Course", lessonCount: 1,
                               currentAttempt: 2,
                               attempts: [attempt(lesson: 0, passed: true, daysAgo: 1, attempt: 1)])],
            courses: [c]
        )
        XCTAssertTrue(due.isEmpty, "a clean pass yesterday isn't due yet, even across a retake")
    }

    func testResultsForDeletedCourseAreIgnored() {
        let due = ReviewPlanner.dueItems(
            in: [results([attempt(lesson: 0, passed: false, daysAgo: 30)])],
            courses: []
        )
        XCTAssertTrue(due.isEmpty)
    }
}
