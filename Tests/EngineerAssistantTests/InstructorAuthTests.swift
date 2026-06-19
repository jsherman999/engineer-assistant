import XCTest
@testable import EngineerAssistant

final class InstructorAuthTests: XCTestCase {
    func testValidPIN() {
        XCTAssertTrue(InstructorAuth.isValidPIN("1234"))
        XCTAssertTrue(InstructorAuth.isValidPIN("123456"))
        XCTAssertFalse(InstructorAuth.isValidPIN("123"))     // too short
        XCTAssertFalse(InstructorAuth.isValidPIN("1234567")) // too long
        XCTAssertFalse(InstructorAuth.isValidPIN("12a4"))    // non-digit
    }

    func testHashIsSaltedAndDeterministic() {
        let salt = InstructorAuth.randomSalt()
        let a = InstructorAuth.hash("1234", salt: salt)
        let b = InstructorAuth.hash("1234", salt: salt)
        XCTAssertEqual(a, b, "same pin+salt hashes identically")
        XCTAssertNotEqual(a, InstructorAuth.hash("1234", salt: InstructorAuth.randomSalt()), "different salt → different hash")
        XCTAssertNotEqual(a, InstructorAuth.hash("9999", salt: salt), "different pin → different hash")
        XCTAssertEqual(a.count, 64, "SHA-256 hex is 64 chars")
    }

    func testConstantTimeEqual() {
        XCTAssertTrue(InstructorAuth.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(InstructorAuth.constantTimeEqual("abc", "abd"))
        XCTAssertFalse(InstructorAuth.constantTimeEqual("abc", "abcd"))
    }

    func testRecoveryCodeFormat() {
        let code = InstructorAuth.generateRecoveryCode()
        let parts = code.split(separator: "-")
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(parts.allSatisfy { $0.count == 4 })
        XCTAssertFalse(code.contains("0"), "ambiguous chars excluded")
        XCTAssertFalse(code.contains("O"))
    }

    func testNormalizeRecovery() {
        XCTAssertEqual(InstructorAuth.normalize("ab2c-9xqp-rb4n"), "AB2C9XQPRB4N")
        XCTAssertEqual(InstructorAuth.normalize(" AB2C 9XQP "), "AB2C9XQP")
    }
}
