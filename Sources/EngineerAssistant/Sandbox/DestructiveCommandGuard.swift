import Foundation

/// A command the student is about to run that can't be undone, together with the explanation
/// shown before it executes. This is a teaching moment first and a safety net second: the
/// student is told what the command would do and then chooses.
struct DangerousCommand: Identifiable, Equatable {
    let id = UUID()
    let command: String
    let headline: String
    let explanation: String
}

/// Matches shell lines that destroy data or wedge the machine. Ask mode runs an unsandboxed
/// shell in the student's real home, so this is the only thing standing between a typo and a
/// lost Documents folder.
enum DestructiveCommandGuard {
    private struct Rule {
        let pattern: String
        let headline: String
        let explanation: String
    }

    /// `rm` needs flag parsing rather than a regex: the dangerous case is the *combination* of
    /// recursive and force, which can arrive as `-rf`, `-fr`, or `-r -f` in any order.
    private static func recursiveForceDelete(_ line: String) -> DangerousCommand? {
        let tokens = line.split(separator: " ").map(String.init)
        guard tokens.contains(where: { $0 == "rm" }) else { return nil }
        let shortFlags = tokens
            .filter { $0.hasPrefix("-") && !$0.hasPrefix("--") }
            .flatMap { $0.dropFirst() }
        guard shortFlags.contains(where: { $0 == "r" || $0 == "R" }), shortFlags.contains("f") else { return nil }
        return DangerousCommand(
            command: line,
            headline: "This deletes a whole directory tree, permanently.",
            explanation: "`rm -rf` removes a folder and everything inside it without asking and without a Trash. There is no undo. Check the path very carefully — a stray space (`rm -rf / home/me`) deletes far more than you meant."
        )
    }

    private static let rules: [Rule] = [
        Rule(pattern: #"\brm\s+.*[*?]"#,
             headline: "This deletes every file matching a wildcard.",
             explanation: "The shell expands `*` before `rm` ever sees it, so `rm *.txt` becomes `rm a.txt b.txt c.txt`. Run `ls` with the same pattern first to see exactly what will be removed."),
        Rule(pattern: #"\bdd\b.*\bof=/dev/"#,
             headline: "This writes raw bytes straight onto a device.",
             explanation: "`dd of=/dev/...` bypasses the filesystem and overwrites a disk directly. Aimed at the wrong device it destroys a drive's contents instantly — this is why it's nicknamed 'disk destroyer'."),
        Rule(pattern: #":\(\)\s*\{.*\|.*&.*\}\s*;?\s*:"#,
             headline: "This is a fork bomb.",
             explanation: "This defines a function that calls itself twice forever. Each copy spawns two more until the machine runs out of processes and stops responding. It's a classic demonstration of why resource limits exist."),
        Rule(pattern: #"\bmkfs(\.[a-z0-9]+)?\b"#,
             headline: "This formats a filesystem.",
             explanation: "`mkfs` creates a brand-new empty filesystem on a device, erasing whatever was there. It's how you prepare a fresh disk — never how you fix a full one."),
        Rule(pattern: #"\bchmod\s+(-[a-zA-Z]+\s+)*777\b"#,
             headline: "This makes files writable by everyone.",
             explanation: "`777` grants read, write, and execute to every user on the machine. It makes permission errors disappear by removing the protection entirely. Fix the owner or the specific bit you need instead — usually `chmod +x` or `chown`."),
        Rule(pattern: #"\bcurl\b[^|]*\|\s*(sudo\s+)?(ba)?sh\b"#,
             headline: "This runs code from the internet without reading it.",
             explanation: "`curl … | sh` downloads a script and executes it immediately, with your permissions. You never see what it does. Download it to a file, read it, then run it."),
        Rule(pattern: #">\s*/dev/(sd|disk|nvme)"#,
             headline: "This redirects output onto a raw disk device.",
             explanation: "Redirecting into `/dev/disk…` overwrites the drive's raw bytes, not a file on it. The filesystem on that device will be corrupted."),
    ]

    /// Returns the matching danger for a command line, or nil when it's ordinary.
    static func evaluate(_ line: String) -> DangerousCommand? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let danger = recursiveForceDelete(trimmed) { return danger }
        for rule in rules {
            guard let re = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if re.firstMatch(in: trimmed, options: [], range: range) != nil {
                return DangerousCommand(command: trimmed, headline: rule.headline, explanation: rule.explanation)
            }
        }
        return nil
    }
}
