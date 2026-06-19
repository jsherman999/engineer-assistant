import Foundation
import CryptoKit
import Security

/// PIN gate for the instructor dashboard. PIN and a one-time recovery code are stored
/// only as salted SHA-256 hashes in the Keychain (never the plaintext).
enum InstructorAuth {
    static func isConfigured() -> Bool {
        !(Keychain.get(KeychainKeys.instructorPinHash) ?? "").isEmpty
    }

    static func isValidPIN(_ pin: String) -> Bool {
        pin.count >= 4 && pin.count <= 6 && pin.allSatisfy(\.isNumber)
    }

    /// First-time setup: stores the PIN and returns a recovery code to show the user once.
    @discardableResult
    static func setupPIN(_ pin: String) -> String {
        storePIN(pin)
        let recovery = generateRecoveryCode()
        let salt = randomSalt()
        try? Keychain.set(hash(normalize(recovery), salt: salt), for: KeychainKeys.recoveryCodeHash)
        try? Keychain.set(salt, for: KeychainKeys.recoveryCodeSalt)
        return recovery
    }

    static func verifyPIN(_ pin: String) -> Bool {
        guard let salt = Keychain.get(KeychainKeys.instructorPinSalt),
              let stored = Keychain.get(KeychainKeys.instructorPinHash) else { return false }
        return constantTimeEqual(hash(pin, salt: salt), stored)
    }

    /// Resets the PIN using the recovery code; the recovery code itself is unchanged.
    static func resetPIN(usingRecovery code: String, newPIN: String) -> Bool {
        guard isValidPIN(newPIN),
              let salt = Keychain.get(KeychainKeys.recoveryCodeSalt),
              let stored = Keychain.get(KeychainKeys.recoveryCodeHash),
              constantTimeEqual(hash(normalize(code), salt: salt), stored) else { return false }
        storePIN(newPIN)
        return true
    }

    private static func storePIN(_ pin: String) {
        let salt = randomSalt()
        try? Keychain.set(hash(pin, salt: salt), for: KeychainKeys.instructorPinHash)
        try? Keychain.set(salt, for: KeychainKeys.instructorPinSalt)
    }

    // MARK: - Crypto helpers (pure, unit-tested)

    static func hash(_ value: String, salt: String) -> String {
        var data = Data(base64Encoded: salt) ?? Data(salt.utf8)
        data.append(Data(value.utf8))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func randomSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// Crockford-ish alphabet (no 0/O/1/I) in `XXXX-XXXX-XXXX` form.
    static func generateRecoveryCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var rng = SystemRandomNumberGenerator()
        func group() -> String { String((0..<4).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] }) }
        return "\(group())-\(group())-\(group())"
    }

    static func normalize(_ code: String) -> String {
        code.uppercased().filter { $0 != "-" && !$0.isWhitespace }
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        guard ab.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }
}
