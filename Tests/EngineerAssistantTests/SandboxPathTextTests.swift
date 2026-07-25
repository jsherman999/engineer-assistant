import XCTest
@testable import EngineerAssistant

/// A course invents a home path before its workspace exists. Once demo output became something
/// the student predicts against, a wrong path stopped being cosmetic — so these cover the
/// rewrite that reconciles the two.
final class SandboxPathTextTests: XCTestCase {
    private let home = "/Users/jay/students/student1"

    func testRewritesInventedMacHome() {
        XCTAssertEqual(SandboxPathText.rewrite("/Users/student", sandboxHome: home), home)
        XCTAssertEqual(SandboxPathText.rewrite("/Users/student/fruit.txt", sandboxHome: home),
                       "\(home)/fruit.txt")
    }

    func testRewritesInventedLinuxHome() {
        XCTAssertEqual(SandboxPathText.rewrite("/home/student/data.csv", sandboxHome: "/root"),
                       "/root/data.csv")
    }

    /// The reported case: `pwd` revealed /Users/student while the sandbox printed something else.
    func testRewritesEmbeddedOutput() {
        XCTAssertEqual(
            SandboxPathText.rewrite("       3 /Users/student/fruit.txt", sandboxHome: home),
            "       3 \(home)/fruit.txt"
        )
    }

    func testRewritesEveryOccurrence() {
        let text = "cp /Users/student/a.txt /Users/student/backup/a.txt"
        XCTAssertEqual(SandboxPathText.rewrite(text, sandboxHome: home),
                       "cp \(home)/a.txt \(home)/backup/a.txt")
    }

    /// The sandbox path contains its own `/Users/<name>` prefix. Rewriting it again would double
    /// the tail — this is the case a naive find-and-replace gets wrong.
    func testDoesNotDoubleAnAlreadyCorrectPath() {
        XCTAssertEqual(SandboxPathText.rewrite(home, sandboxHome: home), home)
        XCTAssertEqual(SandboxPathText.rewrite("\(home)/notes.txt", sandboxHome: home),
                       "\(home)/notes.txt")
        XCTAssertEqual(SandboxPathText.rewrite("cd \(home) && ls", sandboxHome: home),
                       "cd \(home) && ls")
    }

    func testMixedCorrectAndInventedPaths() {
        XCTAssertEqual(
            SandboxPathText.rewrite("mv /Users/student/a.txt \(home)/b.txt", sandboxHome: home),
            "mv \(home)/a.txt \(home)/b.txt"
        )
    }

    /// Tilde paths are already correct and must survive untouched, as must system paths.
    func testLeavesTildeAndSystemPathsAlone() {
        for text in ["~/notes.txt", "cat ~/.zshrc", "ls /usr/local/bin", "/etc/hosts",
                     "grep x /var/log/system.log", "echo hello", ""] {
            XCTAssertEqual(SandboxPathText.rewrite(text, sandboxHome: home), text,
                           "\(text) should be untouched")
        }
    }

    func testNoOpWithoutASandboxHome() {
        XCTAssertEqual(SandboxPathText.rewrite("/Users/student", sandboxHome: ""), "/Users/student")
    }
}
