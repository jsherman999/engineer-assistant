import XCTest
@testable import EngineerAssistant

final class CourseGateTests: XCTestCase {

    // MARK: - Fixtures

    private func challenge(task: String, files: [StarterFile]? = nil, starterState: String? = nil) -> Challenge {
        Challenge(task: task, starterState: starterState, starterFiles: files,
                  verify: VerifyCheck(type: .fileExists, value: nil, path: "~/out.txt", exitCode: nil))
    }

    private func lesson(_ title: String, _ challenge: Challenge) -> Lesson {
        Lesson(title: title, conceptMd: "concept", demos: [], practicePrompt: "practice",
               challenge: challenge, recapMd: nil, visual: nil)
    }

    private func draft(lessons: [Lesson], final: Challenge? = nil) -> CourseDraft {
        CourseDraft(title: "T", description: "D", estimatedMinutes: 20, environment: .macos,
                    prerequisites: [], lessons: lessons, finalChallenge: final)
    }

    // MARK: - State

    func testStateListsSeededFilesPerChallenge() throws {
        let d = draft(lessons: [
            lesson("Seeded", challenge(task: "Fix it", files: [StarterFile(path: "~/a.sh", content: "echo", executable: true)])),
            lesson("Empty", challenge(task: "Make something"))
        ])
        let state = CourseGate.state(for: d)
        let challenges = try XCTUnwrap(state["challenges"] as? [[String: Any]])
        XCTAssertEqual(challenges.count, 2)

        let seeded = try XCTUnwrap(challenges[0]["files_seeded_before_the_student_starts"] as? [[String: String]])
        XCTAssertEqual(seeded.first?["path"], "~/a.sh")
        // A challenge with no starter files must say so in words the model can act on, not
        // silently omit the key.
        XCTAssertEqual(challenges[1]["files_seeded_before_the_student_starts"] as? String,
                       "NONE — the sandbox is completely empty")
    }

    /// `starter_state` describes a starting point without creating anything. Feeding it to the
    /// gate would let a course talk its way past the exact check this exists to perform.
    func testStateExcludesStarterStateProse() throws {
        let d = draft(lessons: [
            lesson("Lies", challenge(task: "Count lines in ~/data.txt",
                                     starterState: "A file ~/data.txt with 40 lines already exists."))
        ])
        let json = try JSONSerialization.data(withJSONObject: CourseGate.state(for: d))
        let text = String(decoding: json, as: UTF8.self)
        XCTAssertFalse(text.contains("already exists"), "starter_state prose must not reach the gate")
        XCTAssertTrue(text.contains("Count lines"), "the task itself should reach the gate")
    }

    func testStateIncludesFinalChallenge() throws {
        let d = draft(lessons: [lesson("One", challenge(task: "A"))], final: challenge(task: "Capstone"))
        let challenges = try XCTUnwrap(CourseGate.state(for: d)["challenges"] as? [[String: Any]])
        XCTAssertEqual(challenges.count, 2)
        XCTAssertEqual(challenges[1]["title"] as? String, "Final Challenge")
    }

    // MARK: - Questions

    func testOneQuestionPerChallengeIncludingCapstone() {
        let d = draft(lessons: [lesson("A", challenge(task: "a")), lesson("B", challenge(task: "b"))],
                      final: challenge(task: "c"))
        let ids = CourseGate.questions(for: d).map(\.id)
        XCTAssertEqual(ids, ["missing_file_0", "missing_file_1", "missing_file_2"])
    }

    func testQuestionsOmitCapstoneWhenAbsent() {
        let d = draft(lessons: [lesson("A", challenge(task: "a"))])
        XCTAssertEqual(CourseGate.questions(for: d).map(\.id), ["missing_file_0"])
    }

    func testEachQuestionScopesItselfToItsOwnIndex() {
        let d = draft(lessons: [lesson("A", challenge(task: "a")), lesson("B", challenge(task: "b"))])
        let questions = CourseGate.questions(for: d)
        XCTAssertTrue(questions[0].instructions.contains("challenges[0]"))
        XCTAssertTrue(questions[1].instructions.contains("challenges[1]"))
        XCTAssertFalse(questions[1].instructions.contains("challenges[0]"))
    }

    // MARK: - Threshold

    func testFlagsOnlyChallengesAboveThreshold() {
        let d = draft(lessons: [lesson("Fine", challenge(task: "a")),
                                lesson("Impossible", challenge(task: "b")),
                                lesson("Fine too", challenge(task: "c"))])
        // These are measured scores: a real course with one challenge's seeded files removed.
        let failures = CourseGate.failures(from: ["missing_file_0": 0.11, "missing_file_1": 0.96, "missing_file_2": 0.14],
                                           draft: d)
        XCTAssertEqual(failures.map(\.lessonIdx), [1])
        XCTAssertEqual(failures.first?.title, "Impossible")
    }

    /// Wrongly rejecting a good course costs a full regeneration, so anything not clearly
    /// impossible is let through. The measured bands are 0.08-0.23 clean, 0.87-0.96 defective;
    /// nothing real lands near the threshold, so the margin is what is being asserted here.
    func testDoesNotFlagMerelyUncertainScores() {
        let d = draft(lessons: [lesson("Doubtful", challenge(task: "a"))])
        XCTAssertTrue(CourseGate.failures(from: ["missing_file_0": 0.59], draft: d).isEmpty)
        XCTAssertFalse(CourseGate.failures(from: ["missing_file_0": 0.61], draft: d).isEmpty)
    }

    /// The worst measured clean score and the best measured defective score must both land on
    /// the right side of the threshold. This is the regression test for the phrasing: an earlier
    /// wording scored a sabotaged "fix ~/greet.sh" challenge at 0.54 and let it straight through.
    func testMeasuredBandsFallOnTheCorrectSideOfTheThreshold() {
        let d = draft(lessons: [lesson("A", challenge(task: "a"))])
        XCTAssertTrue(CourseGate.failures(from: ["missing_file_0": 0.23], draft: d).isEmpty,
                      "worst observed score on an intact challenge must pass")
        XCTAssertFalse(CourseGate.failures(from: ["missing_file_0": 0.87], draft: d).isEmpty,
                       "best observed score on a sabotaged challenge must be blocked")
    }

    /// A missing answer must not read as a failure — the gate degrades to "fine", never to
    /// blocking a course it failed to score.
    func testMissingAnswersAreNotFailures() {
        let d = draft(lessons: [lesson("A", challenge(task: "a")), lesson("B", challenge(task: "b"))])
        XCTAssertTrue(CourseGate.failures(from: [:], draft: d).isEmpty)
        XCTAssertEqual(CourseGate.failures(from: ["missing_file_1": 0.95], draft: d).map(\.lessonIdx), [1])
    }

    func testCapstoneFailureIsIndexedPastTheLessons() {
        let d = draft(lessons: [lesson("A", challenge(task: "a"))], final: challenge(task: "capstone"))
        let failures = CourseGate.failures(from: ["missing_file_0": 0.12, "missing_file_1": 0.91], draft: d)
        XCTAssertEqual(failures.map(\.lessonIdx), [1])
        XCTAssertEqual(failures.first?.title, "Final Challenge")
    }

    // MARK: - Response parsing

    func testParsesNoulAnswers() throws {
        let json = Data("""
        {"model":"jev-1.13.0","answers":{"missing_file_0":{"type":"noul","noul":0.11},
        "missing_file_1":{"type":"noul","noul":0.96}},"usage":{"input_tokens":1905,"output_tokens":104}}
        """.utf8)
        let answers = try TypeSafeClient.parse(json)
        XCTAssertEqual(answers["missing_file_0"], 0.11)
        XCTAssertEqual(answers["missing_file_1"], 0.96)
    }

    func testParseThrowsOnMalformedBody() {
        XCTAssertThrowsError(try TypeSafeClient.parse(Data("{\"oops\":true}".utf8)))
    }

    // MARK: - Error message

    func testErrorNamesTheOffendingChallenges() throws {
        let error = CourseGenerationError.unsolvableChallenges([
            GateFailure(lessonIdx: 2, title: "Your first bash script", score: 0.87)
        ])
        let text = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(text.contains("Your first bash script"), "the student should see which lesson broke")
    }
}
