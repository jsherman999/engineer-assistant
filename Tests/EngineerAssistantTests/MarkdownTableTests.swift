import XCTest
@testable import EngineerAssistant

final class MarkdownTableTests: XCTestCase {
    func testParsesPipeTableWithProseAround() {
        let text = """
        Here are the launch folders:
        | Folder | What it controls |
        |--------|----------------|
        | ~/Library/LaunchAgents | Startup programs for your user |
        | /Library/LaunchDaemons | System-wide background services (run as root) |
        Use them carefully.
        """
        let blocks = MarkdownTable.split(text)
        XCTAssertEqual(blocks, [
            .text("Here are the launch folders:"),
            .table([
                ["Folder", "What it controls"],
                ["~/Library/LaunchAgents", "Startup programs for your user"],
                ["/Library/LaunchDaemons", "System-wide background services (run as root)"]
            ]),
            .text("Use them carefully.")
        ])
    }

    func testTextWithoutTableIsOneBlock() {
        let blocks = MarkdownTable.split("A pipe in prose a | b is not a table.")
        XCTAssertEqual(blocks, [.text("A pipe in prose a | b is not a table.")])
    }

    func testTableWithoutSeparatorIsNotParsed() {
        // No `|---|` separator row → treated as plain text, not a table.
        let blocks = MarkdownTable.split("| a | b |\n| c | d |")
        XCTAssertEqual(blocks, [.text("| a | b |\n| c | d |")])
    }
}
