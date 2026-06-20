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

    func testIncrementsPerCourseAndReuses() {
        let a = sut.directory(forCourseId: "course-a")
        let b = sut.directory(forCourseId: "course-b")
        XCTAssertEqual(a.lastPathComponent, "student1")
        XCTAssertEqual(b.lastPathComponent, "student2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))

        // Reopening the same course reuses its number, not a new one.
        XCTAssertEqual(sut.directory(forCourseId: "course-a").lastPathComponent, "student1")
        XCTAssertEqual(sut.directory(forCourseId: "course-c").lastPathComponent, "student3")
    }

    func testMappingPersistsAcrossInstances() {
        _ = sut.directory(forCourseId: "course-a")
        let fresh = StudentSandbox(rootDir: dir.appendingPathComponent("students"),
                                   mapFile: dir.appendingPathComponent("students.json"))
        XCTAssertEqual(fresh.directory(forCourseId: "course-a").lastPathComponent, "student1")
    }

    func testRemoveDeletesDirAndFreesMapping() {
        let a = sut.directory(forCourseId: "course-a")
        sut.remove(forCourseId: "course-a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        // After removal the next allocation continues from the highest remaining number.
        XCTAssertEqual(sut.directory(forCourseId: "course-b").lastPathComponent, "student1")
    }
}
