import XCTest
@testable import EngineerAssistant

final class SandboxTests: XCTestCase {
    func testProfileSubstitutesSandboxDir() {
        let profile = SandboxProfile.macOSProfile(sandboxDir: "/tmp/my-sandbox")
        XCTAssertTrue(profile.contains("(version 1)"))
        XCTAssertTrue(profile.contains("(allow default)"))
        XCTAssertTrue(profile.contains("(deny file-write*)"))
        XCTAssertTrue(profile.contains("(deny network*)"))
        XCTAssertTrue(profile.contains("(subpath \"/tmp/my-sandbox\")"))
        XCTAssertFalse(profile.contains("@SANDBOX_DIR@"))
    }

    func testWriteAllowlistOnlyContainsExpectedPaths() {
        let profile = SandboxProfile.macOSProfile(sandboxDir: "/tmp/x")
        guard let writeBlockStart = profile.range(of: "(allow file-write*"),
              let writeBlockEnd = profile.range(of: ")", range: writeBlockStart.upperBound..<profile.endIndex) else {
            return XCTFail("write block not found")
        }
        let writeRegion = String(profile[writeBlockStart.upperBound..<writeBlockEnd.upperBound])
        XCTAssertFalse(writeRegion.contains("/Users"), "user home must not be writable")
        XCTAssertFalse(writeRegion.contains("/System"), "/System must not be writable")
        XCTAssertTrue(writeRegion.contains("/tmp/x"), "sandbox dir must be writable")
    }
}
