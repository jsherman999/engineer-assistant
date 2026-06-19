import XCTest
@testable import EngineerAssistant

final class ShellTeeParserTests: XCTestCase {
    private let soh = "\u{01}"

    private func bytes(_ s: String) -> ArraySlice<UInt8> { Array(s.utf8)[...] }
    private func str(_ b: [UInt8]) -> String { String(decoding: b, as: UTF8.self) }

    func testPlainOutputPassesThrough() {
        var p = ShellTeeParser()
        let out = p.consume(bytes("hello world\n"))
        XCTAssertEqual(str(out.display), "hello world\n")
        XCTAssertTrue(out.events.isEmpty)
    }

    func testCommandStartAndFinishCaptured() {
        var p = ShellTeeParser()
        // preexec marker, then output, then precmd marker
        let stream = "\(soh)EAC:ls\(soh)foo.txt\n\(soh)EAX:0\(soh)"
        let out = p.consume(bytes(stream))
        XCTAssertEqual(str(out.display), "foo.txt\n")
        XCTAssertEqual(out.events, [
            .started(command: "ls"),
            .finished(exitCode: 0, output: "foo.txt\n")
        ])
    }

    func testOutputBeforeStartIsDiscardedFromCommandStdout() {
        var p = ShellTeeParser()
        // prompt + echoed command render, but should not count as command stdout
        let stream = "~ % grep x f\n\(soh)EAC:grep x f\(soh)match\n\(soh)EAX:0\(soh)"
        let out = p.consume(bytes(stream))
        XCTAssertEqual(str(out.display), "~ % grep x f\nmatch\n")
        let finished = out.events.compactMap { event -> (Int, String)? in
            if case let .finished(code, output) = event { return (code, output) }
            return nil
        }
        XCTAssertEqual(finished.count, 1)
        XCTAssertEqual(finished[0].1, "match\n") // prompt/echo excluded
    }

    func testNonZeroExitCode() {
        var p = ShellTeeParser()
        let out = p.consume(bytes("\(soh)EAC:false\(soh)\(soh)EAX:1\(soh)"))
        XCTAssertEqual(out.events, [
            .started(command: "false"),
            .finished(exitCode: 1, output: "")
        ])
        XCTAssertEqual(str(out.display), "")
    }

    func testMarkerSplitAcrossChunks() {
        var p = ShellTeeParser()
        let first = p.consume(bytes("out\n\(soh)EAX:"))
        XCTAssertEqual(str(first.display), "out\n")
        XCTAssertTrue(first.events.isEmpty)
        let second = p.consume(bytes("42\(soh)"))
        XCTAssertEqual(second.events, [.finished(exitCode: 42, output: "out\n")])
        XCTAssertEqual(str(second.display), "")
    }

    func testCommandTextSplitAcrossChunks() {
        var p = ShellTeeParser()
        let first = p.consume(bytes("\(soh)EAC:git sta"))
        XCTAssertTrue(first.events.isEmpty)
        let second = p.consume(bytes("tus\(soh)"))
        XCTAssertEqual(second.events, [.started(command: "git status")])
    }

    func testStraySOHTreatedAsLiteral() {
        var p = ShellTeeParser()
        let out = p.consume(bytes("a\(soh)b\n"))
        XCTAssertEqual(str(out.display), "a\(soh)b\n")
        XCTAssertTrue(out.events.isEmpty)
    }

    func testStdoutAccumulatesAcrossChunks() {
        var p = ShellTeeParser()
        _ = p.consume(bytes("\(soh)EAC:cat\(soh)line1\n"))
        let out = p.consume(bytes("line2\n\(soh)EAX:0\(soh)"))
        XCTAssertEqual(out.events, [.finished(exitCode: 0, output: "line1\nline2\n")])
    }
}
