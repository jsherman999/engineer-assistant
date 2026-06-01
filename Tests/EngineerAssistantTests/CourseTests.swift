import XCTest
@testable import EngineerAssistant

final class CourseTests: XCTestCase {
    func testSlugifySubject() {
        XCTAssertEqual(CourseSubject.slug(for: "teach me grep"), "teach-me-grep")
        XCTAssertEqual(CourseSubject.slug(for: "Using the macOS shell!"), "using-the-macos-shell")
        XCTAssertEqual(CourseSubject.slug(for: "  bash  basics  "), "bash-basics")
        XCTAssertEqual(CourseSubject.slug(for: "Claude Code 101: how?"), "claude-code-101-how")
    }

    func testCourseDraftRoundTrip() throws {
        let json = """
        {
          "title": "Intro to grep",
          "description": "A short course on grep.",
          "estimated_minutes": 20,
          "environment": "linux",
          "prerequisites": [],
          "lessons": [
            {
              "title": "Basics",
              "concept_md": "grep searches text.",
              "demos": [
                {"command": "grep foo file.txt", "expected_output": "foobar", "explanation": "finds matches"}
              ],
              "practice_prompt": "Try different patterns.",
              "challenge": {
                "task": "Find lines containing 'error'.",
                "verify": {"type": "exit_code", "exit_code": 0}
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let draft = try JSONDecoder().decode(CourseDraft.self, from: json)
        XCTAssertEqual(draft.title, "Intro to grep")
        XCTAssertEqual(draft.environment, .linux)
        XCTAssertEqual(draft.lessons.count, 1)
        XCTAssertEqual(draft.lessons[0].demos.first?.command, "grep foo file.txt")
        XCTAssertEqual(draft.lessons[0].challenge.verify.type, .exitCode)
        XCTAssertEqual(draft.lessons[0].challenge.verify.exitCode, 0)
    }

    func testFileCourseStoreCacheRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("courses-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileCourseStore(directory: dir)

        let draft = CourseDraft(
            title: "Intro",
            description: "Desc",
            estimatedMinutes: 10,
            environment: .macos,
            prerequisites: [],
            lessons: [
                Lesson(
                    title: "L1",
                    conceptMd: "concept",
                    demos: [Demo(command: "ls", expectedOutput: "...", explanation: "lists files")],
                    practicePrompt: "explore",
                    challenge: Challenge(task: "do it", starterState: nil, verify: VerifyCheck(type: .exitCode, value: nil, path: nil, exitCode: 0))
                )
            ],
            finalChallenge: nil
        )

        let course = Course(subject: "teach me ls", draft: draft)
        try store.save(course)

        XCTAssertNil(store.load(subject: "different subject"))
        let loaded = store.load(subject: "teach me ls")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "Intro")
        XCTAssertEqual(loaded?.subject, "teach me ls")
        XCTAssertEqual(loaded?.lessons.count, 1)

        let all = store.listAll()
        XCTAssertEqual(all.count, 1)
    }
}
