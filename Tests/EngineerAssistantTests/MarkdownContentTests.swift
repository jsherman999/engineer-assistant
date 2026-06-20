import XCTest
@testable import EngineerAssistant

final class MarkdownContentTests: XCTestCase {
    func testHeadingParagraphAndFencedCodeArePreserved() {
        let md = """
        ## Routing & Dynamic Responses

        Real web servers send different content. You can check `self.path`:

        ```python
        def do_GET(self):
            if self.path == '/time':
                body = b'now'
            else:
                body = b'home'
        ```

        This is primitive routing.
        """
        let blocks = MarkdownContent.parse(md)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0], .heading(level: 2, text: "Routing & Dynamic Responses"))
        XCTAssertEqual(blocks[1], .paragraph("Real web servers send different content. You can check `self.path`:"))

        // The code block keeps its newlines and indentation (no language tag, no run-on).
        guard case .code(let code) = blocks[2] else { return XCTFail("expected code block") }
        XCTAssertFalse(code.contains("python"))
        XCTAssertTrue(code.contains("def do_GET(self):\n    if self.path == '/time':"))
        XCTAssertEqual(code.components(separatedBy: "\n").count, 5)

        XCTAssertEqual(blocks[3], .paragraph("This is primitive routing."))
    }

    func testBulletsAndTable() {
        let md = """
        Notes:
        - first
        - second

        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let blocks = MarkdownContent.parse(md)
        XCTAssertEqual(blocks[0], .paragraph("Notes:"))
        XCTAssertEqual(blocks[1], .bullets(["first", "second"]))
        XCTAssertEqual(blocks[2], .table([["A", "B"], ["1", "2"]]))
    }
}
