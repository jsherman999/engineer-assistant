import XCTest
@testable import EngineerAssistant

final class StudentSandboxTests: XCTestCase {
    private var dir: URL!
    private var sut: StudentSandbox!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("students-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sut = StudentSandbox(rootDir: dir.appendingPathComponent("students"),
                             mapFile: dir.appendingPathComponent("students.json"))
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A course keeps its workspace across sittings. Allocating a fresh one on every open
    /// silently made multi-session work impossible — quit and reopen and your files were gone.
    func testCourseKeepsItsWorkspaceAcrossOpens() {
        let a1 = sut.directory(forCourseId: "course-a")
        let a2 = sut.directory(forCourseId: "course-a")   // reopening the SAME course
        let b1 = sut.directory(forCourseId: "course-b")

        XCTAssertEqual(a1.lastPathComponent, "student1")
        XCTAssertEqual(a2.lastPathComponent, "student1", "same course, same workspace")
        XCTAssertEqual(b1.lastPathComponent, "student2", "a different course gets its own")
        XCTAssertTrue(FileManager.default.fileExists(atPath: a1.path))
    }

    func testWorkFilesSurviveReopeningACourse() throws {
        let first = sut.directory(forCourseId: "course-a")
        let note = first.appendingPathComponent("progress.txt")
        try "half done".write(to: note, atomically: true, encoding: .utf8)

        let reopened = sut.directory(forCourseId: "course-a")
        XCTAssertEqual(try String(contentsOf: reopened.appendingPathComponent("progress.txt"), encoding: .utf8),
                       "half done")
    }

    /// A retake needs a clean slate, or the challenges are already solved.
    func testAllocateFreshGivesARetakeAnEmptyWorkspace() throws {
        let first = sut.directory(forCourseId: "course-a")
        try "solved".write(to: first.appendingPathComponent("answer.txt"), atomically: true, encoding: .utf8)

        let retake = sut.allocateFresh(forCourseId: "course-a")
        XCTAssertNotEqual(retake.lastPathComponent, first.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retake.appendingPathComponent("answer.txt").path))
        // And subsequent opens follow the retake, not the original.
        XCTAssertEqual(sut.directory(forCourseId: "course-a").lastPathComponent, retake.lastPathComponent)
    }

    func testCounterPersistsAcrossInstances() {
        _ = sut.directory(forCourseId: "course-a")        // student1
        let fresh = StudentSandbox(rootDir: dir.appendingPathComponent("students"),
                                   mapFile: dir.appendingPathComponent("students.json"))
        // Counter keeps climbing across app restarts — never resets/collides.
        XCTAssertEqual(fresh.directory(forCourseId: "course-b").lastPathComponent, "student2")
    }

    func testRemoveDeletesAllCourseDirsAndKeepsCounterClimbing() {
        let a1 = sut.directory(forCourseId: "course-a")        // student1
        let a2 = sut.allocateFresh(forCourseId: "course-a")    // student2 (a retake)
        let b1 = sut.directory(forCourseId: "course-b")        // student3

        sut.remove(forCourseId: "course-a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: a1.path), "all of course-a's dirs removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: a2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b1.path), "other course untouched")

        // Counter does not reuse freed numbers.
        XCTAssertEqual(sut.directory(forCourseId: "course-c").lastPathComponent, "student4")
    }
}
