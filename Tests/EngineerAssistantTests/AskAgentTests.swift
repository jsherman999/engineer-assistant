import XCTest
@testable import EngineerAssistant

final class AskAgentTests: XCTestCase {
    private let runner = AllowlistedCommandRunner()

    func testRefusesEmpty() async {
        let r = await runner.run("   ")
        XCTAssertFalse(r.allowed)
    }

    func testRefusesShellMetacharacters() async {
        for cmd in ["ifconfig | grep inet", "uname; rm -rf /", "echo $(whoami)", "df > /tmp/x", "sw_vers && id"] {
            let r = await runner.run(cmd)
            XCTAssertFalse(r.allowed, "should refuse: \(cmd)")
            XCTAssertTrue(r.output.contains("Refused"), "\(cmd) → \(r.output)")
        }
    }

    func testRefusesOffAllowlist() async {
        for cmd in ["ls -la", "rm -rf /", "curl example.com", "sudo reboot"] {
            let r = await runner.run(cmd)
            XCTAssertFalse(r.allowed, "should refuse: \(cmd)")
        }
    }

    func testRefusesAbsolutePath() async {
        let r = await runner.run("/bin/ps aux")
        XCTAssertFalse(r.allowed)
    }

    func testAllowsAndRunsReadOnlyCommand() async {
        // `uname` is on the allowlist and present on every Mac.
        let r = await runner.run("uname -a")
        XCTAssertTrue(r.allowed)
        XCTAssertFalse(r.output.isEmpty)
        XCTAssertTrue(r.output.contains("Darwin"))
    }
}
