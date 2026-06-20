import Foundation

/// Executes a narrow allowlist of read-only macOS info commands for the Ask-mode agent.
/// Blocks shell metacharacters and anything off the allowlist, so the model can answer
/// questions about this Mac (IP, OS version, disk, processes…) with real data but has no
/// write or destructive power. Commands run as the user with no privilege escalation, so
/// even an allowlisted command's write subcommands fail without root.
struct AllowlistedCommandRunner {
    struct Result { let allowed: Bool; let output: String }

    /// Read-only informational commands. Each is either a pure query or can't modify state
    /// without root (which the agent never has).
    static let allowlist: Set<String> = [
        "sw_vers", "uname", "arch", "hostname", "uptime", "date", "whoami", "id",
        "sysctl", "system_profiler", "vm_stat", "df", "ps",
        "ifconfig", "ipconfig", "netstat", "scutil"
    ]

    /// Characters that would allow chaining, redirection, substitution, or quoting tricks.
    private static let blocked = CharacterSet(charactersIn: ";|&`$><()\n\r\\\"'")

    private static let searchDirs = ["/usr/sbin", "/sbin", "/usr/bin", "/bin", "/usr/local/bin", "/opt/homebrew/bin"]

    private static let outputCap = 8000

    func run(_ command: String) async -> Result {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(allowed: false, output: "Refused: empty command.") }

        if trimmed.rangeOfCharacter(from: Self.blocked) != nil {
            return Result(allowed: false, output: "Refused: shell operators (pipes, redirection, chaining, quotes) aren't allowed. Run one simple read-only command.")
        }

        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let name = tokens.first else { return Result(allowed: false, output: "Refused: empty command.") }
        if name.contains("/") {
            return Result(allowed: false, output: "Refused: use a bare command name, not a path.")
        }
        guard Self.allowlist.contains(name) else {
            return Result(allowed: false, output: "Refused: `\(name)` is not on the read-only allowlist. Allowed: \(Self.allowlist.sorted().joined(separator: ", ")).")
        }
        guard let path = Self.locate(name) else {
            return Result(allowed: false, output: "Could not find `\(name)` on this Mac.")
        }

        let (_, output) = await ProcessRunner.run(path, Array(tokens.dropFirst()))
        let capped = output.count > Self.outputCap ? String(output.prefix(Self.outputCap)) + "\n…(truncated)" : output
        return Result(allowed: true, output: capped.isEmpty ? "(no output)" : capped)
    }

    static func locate(_ name: String) -> String? {
        for dir in searchDirs {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
