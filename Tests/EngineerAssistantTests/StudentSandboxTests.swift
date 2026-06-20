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

    func testNewNumberOnEveryOpen() {
        let a1 = sut.directory(forCourseId: "course-a")
        let a2 = sut.directory(forCourseId: "course-a")   // reopening the SAME course → new dir
        let b1 = sut.directory(forCourseId: "course-b")
        XCTAssertEqual(a1.lastPathComponent, "student1")
        XCTAssertEqual(a2.lastPathComponent, "student2")
        XCTAssertEqual(b1.lastPathComponent, "student3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: a1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a2.path))
    }

    func testCounterPersistsAcrossInstances() {
        _ = sut.directory(forCourseId: "course-a")        // student1
        let fresh = StudentSandbox(rootDir: dir.appendingPathComponent("students"),
                                   mapFile: dir.appendingPathComponent("students.json"))
        // Counter keeps climbing across app restarts — never resets/collides.
        XCTAssertEqual(fresh.directory(forCourseId: "course-b").lastPathComponent, "student2")
    }

    func testRemoveDeletesAllCourseDirsAndKeepsCounterClimbing() {
        let a1 = sut.directory(forCourseId: "course-a")    // student1
        let a2 = sut.directory(forCourseId: "course-a")    // student2
        let b1 = sut.directory(forCourseId: "course-b")    // student3

        sut.remove(forCourseId: "course-a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: a1.path), "all of course-a's dirs removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: a2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b1.path), "other course untouched")

        // Counter does not reuse freed numbers.
        XCTAssertEqual(sut.directory(forCourseId: "course-c").lastPathComponent, "student4")
    }
}
