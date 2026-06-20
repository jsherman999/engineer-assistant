import XCTest
@testable import EngineerAssistant

final class AssistantTextTests: XCTestCase {
    func testFencedCodeBecomesCommandBlockWithoutLanguageTag() {
        let text = """
        To find your IP, run:
        ```bash
        ipconfig getifaddr en0
        ```
        That prints your Wi-Fi address.
        """
        let segs = AssistantText.segments(text)
        XCTAssertEqual(segs, [
            .prose("To find your IP, run:"),
            .commands(["ipconfig getifaddr en0"]),
            .prose("That prints your Wi-Fi address.")
        ])
    }

    func testDollarPrefixedLinesAreCommands() {
        let text = "Here's what I ran:\n$ sw_vers\n$ uname -a"
        XCTAssertEqual(AssistantText.segments(text), [
            .prose("Here's what I ran:"),
            .commands(["sw_vers", "uname -a"])
        ])
    }

    func testPlainProseHasNoCommandBlock() {
        let segs = AssistantText.segments("The Finder is the macOS file manager.")
        XCTAssertEqual(segs, [.prose("The Finder is the macOS file manager.")])
    }

    func testMultilineFenceGroupsIntoOneBlockAndDropsBlankLines() {
        let text = "```\nfirst\n\nsecond\n```"
        XCTAssertEqual(AssistantText.segments(text), [.commands(["first", "second"])])
    }
}
