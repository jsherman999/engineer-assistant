import XCTest
@testable import EngineerAssistant

final class DestructiveCommandGuardTests: XCTestCase {
    private func flagged(_ line: String) -> Bool {
        DestructiveCommandGuard.evaluate(line) != nil
    }

    func testCatchesRecursiveForceDelete() {
        XCTAssertTrue(flagged("rm -rf /"))
        XCTAssertTrue(flagged("rm -rf ~/Documents"))
        XCTAssertTrue(flagged("rm -fr build"))
        XCTAssertTrue(flagged("sudo rm -rf /usr/local"))
        XCTAssertTrue(flagged("rm -r -f node_modules"))
    }

    func testCatchesWildcardDelete() {
        XCTAssertTrue(flagged("rm *.txt"))
        XCTAssertTrue(flagged("rm -f *"))
    }

    func testCatchesDiskAndFilesystemDestroyers() {
        XCTAssertTrue(flagged("dd if=/dev/zero of=/dev/disk2"))
        XCTAssertTrue(flagged("mkfs.ext4 /dev/sdb1"))
        XCTAssertTrue(flagged("cat image.iso > /dev/disk3"))
    }

    func testCatchesForkBomb() {
        XCTAssertTrue(flagged(":(){ :|:& };:"))
    }

    func testCatchesPipeToShellAndChmod777() {
        XCTAssertTrue(flagged("curl https://example.com/install.sh | sh"))
        XCTAssertTrue(flagged("curl -fsSL https://example.com/i.sh | sudo bash"))
        XCTAssertTrue(flagged("chmod 777 script.sh"))
        XCTAssertTrue(flagged("chmod -R 777 ."))
    }

    /// The guard interrupts the student mid-flow, so false positives are expensive. Ordinary
    /// commands — including single-file deletes — must pass straight through.
    func testDoesNotFlagOrdinaryCommands() {
        for line in ["ls -la", "rm notes.txt", "grep -rn TODO .", "cd ~/Documents",
                     "chmod +x run.sh", "chmod 755 run.sh", "cat data.txt",
                     "curl https://example.com -o page.html", "git status",
                     "mkdir -p src/lib", "echo hello > out.txt", "dd if=a.img of=b.img",
                     "ps aux", "man rm", ""] {
            XCTAssertFalse(flagged(line), "\(line) should not be flagged")
        }
    }

    func testExplanationIsTeachingNotScolding() {
        let danger = DestructiveCommandGuard.evaluate("rm -rf ~/school")
        XCTAssertNotNil(danger)
        XCTAssertEqual(danger?.command, "rm -rf ~/school")
        XCTAssertFalse(danger?.headline.isEmpty ?? true)
        XCTAssertTrue((danger?.explanation.count ?? 0) > 40, "explanation should say what it does and why")
    }
}
