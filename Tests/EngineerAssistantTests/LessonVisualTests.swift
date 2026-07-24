import XCTest
@testable import EngineerAssistant

final class PermissionGridTests: XCTestCase {
    func testParsesSymbolicMode() {
        XCTAssertEqual(PermissionGridView.parse("rwxr-xr--"),
                       [true, true, true, true, false, true, true, false, false])
    }

    /// `ls -l` output carries a leading file-type character the grid must ignore.
    func testParsesLsStyleModeWithTypeCharacter() {
        XCTAssertEqual(PermissionGridView.parse("-rwxr-xr--"), PermissionGridView.parse("rwxr-xr--"))
        XCTAssertEqual(PermissionGridView.parse("drwx------"),
                       [true, true, true, false, false, false, false, false, false])
    }

    func testParsesOctalMode() {
        XCTAssertEqual(PermissionGridView.parse("754"), PermissionGridView.parse("rwxr-xr--"))
        XCTAssertEqual(PermissionGridView.parse("644"), PermissionGridView.parse("rw-r--r--"))
        XCTAssertEqual(PermissionGridView.parse("777"), Array(repeating: true, count: 9))
        XCTAssertEqual(PermissionGridView.parse("000"), Array(repeating: false, count: 9))
    }

    /// A malformed mode from a generated course must render as an empty grid, not crash.
    func testMalformedModeIsAllUnset() {
        XCTAssertEqual(PermissionGridView.parse("nonsense"), Array(repeating: false, count: 9))
        XCTAssertEqual(PermissionGridView.parse(""), Array(repeating: false, count: 9))
    }
}

final class LessonVisualDecodingTests: XCTestCase {
    /// Courses cached before visuals existed must still load — the field is optional and the
    /// player just renders no diagram.
    func testLessonWithoutVisualOrPartsStillDecodes() throws {
        let json = """
        {
          "title": "Old lesson",
          "concept_md": "text",
          "demos": [{"command": "ls", "expected_output": "a b", "explanation": "lists"}],
          "practice_prompt": "try it",
          "challenge": {"task": "do it", "verify": {"type": "exit_code", "exit_code": 0}}
        }
        """
        let lesson = try JSONDecoder().decode(Lesson.self, from: Data(json.utf8))
        XCTAssertNil(lesson.visual)
        XCTAssertNil(lesson.recapMd)
        XCTAssertNil(lesson.demos.first?.parts)
        XCTAssertNil(lesson.challenge.starterFiles)
    }

    func testDecodesEveryVisualKind() throws {
        let json = """
        [
          {"type": "tree", "items": ["src/", "src/main.c"]},
          {"type": "pipeline", "stages": [{"command": "cat f", "output": "1\\n2"}, {"command": "wc -l", "output": "2"}]},
          {"type": "permissions", "mode": "rwxr-xr--", "path": "run.sh"},
          {"type": "flow", "items": ["browser", "resolver", "server"]}
        ]
        """
        let visuals = try JSONDecoder().decode([LessonVisual].self, from: Data(json.utf8))
        XCTAssertEqual(visuals.map(\.type), ["tree", "pipeline", "permissions", "flow"])
        XCTAssertEqual(visuals[0].items?.count, 2)
        XCTAssertEqual(visuals[1].stages?.last?.output, "2")
        XCTAssertEqual(visuals[2].mode, "rwxr-xr--")
        XCTAssertEqual(visuals[3].items?.first, "browser")
    }

    func testDecodesStarterFilesAndCommandParts() throws {
        let json = """
        {
          "task": "fix the script",
          "starter_state": "a broken greet.sh exists",
          "starter_files": [{"path": "greet.sh", "content": "#!/bin/sh\\necho hi", "executable": true}],
          "verify": {"type": "exit_code", "exit_code": 0}
        }
        """
        let challenge = try JSONDecoder().decode(Challenge.self, from: Data(json.utf8))
        XCTAssertEqual(challenge.starterFiles?.count, 1)
        XCTAssertEqual(challenge.starterFiles?.first?.path, "greet.sh")
        XCTAssertEqual(challenge.starterFiles?.first?.executable, true)

        let demo = try JSONDecoder().decode(Demo.self, from: Data("""
        {"command": "tar -xzf a.tgz", "expected_output": "", "explanation": "extract",
         "parts": [{"token": "-xzf", "meaning": "extract, gzip, from file"}]}
        """.utf8))
        XCTAssertEqual(demo.parts?.first?.token, "-xzf")
    }
}
