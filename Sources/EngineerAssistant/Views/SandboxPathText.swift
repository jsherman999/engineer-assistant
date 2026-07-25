import Foundation

/// Rewrites the placeholder home directories a generated course invents (`/Users/student`,
/// `/home/user`) into the path the student's sandbox actually uses.
///
/// A course is written before its workspace exists, so the model has to guess a home path — and
/// it guesses something plausible but wrong. That was harmless when demo output was just read;
/// it stopped being harmless once the output became a prediction target. A student who predicts
/// `pwd`, reveals `/Users/student`, then runs it and sees `/Users/jay/students/student1` has been
/// taught that the lesson and their machine disagree.
///
/// Substitution happens at render time rather than at generation time for two reasons: the real
/// path isn't known until the workspace is allocated, and doing it here also corrects every
/// course already sitting in the cache.
enum SandboxPathText {
    /// Matches an absolute home-shaped prefix: `/Users/<name>` or `/home/<name>`.
    private static let genericHome = try? NSRegularExpression(
        pattern: #"/(?:Users|home)/[A-Za-z0-9._-]+"#
    )

    /// Replaces guessed home prefixes in `text` with `sandboxHome`.
    ///
    /// Occurrences that already name the real sandbox are left alone — without that check,
    /// rewriting a correct `/Users/jay/students/student1` would match its own `/Users/jay`
    /// prefix and double it.
    static func rewrite(_ text: String, sandboxHome: String) -> String {
        guard let genericHome, !sandboxHome.isEmpty, !text.isEmpty else { return text }
        let ns = text as NSString
        let matches = genericHome.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var out = text
        // Back to front, so earlier ranges stay valid as we splice.
        for match in matches.reversed() {
            let tail = ns.substring(from: match.range.location)
            if tail.hasPrefix(sandboxHome) { continue } // already correct
            guard let range = Range(match.range, in: out) else { continue }
            out.replaceSubrange(range, with: sandboxHome)
        }
        return out
    }
}
