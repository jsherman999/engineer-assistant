import Foundation

/// Executes read-only inspection commands for the Ask-mode agent.
///
/// The model can only run commands that appear here, and only in the modes allowed per command.
/// This is a *capability allowlist*, not a denylist of bad things: the agent's reach is the union
/// of what is listed, so a command nobody thought about is refused by default rather than
/// permitted by default. That is the property a denylist cannot give you — an LLM proposing
/// `python3 -c "..."`, `find / -delete`, or a base64-decoded payload defeats pattern matching,
/// but none of them are reachable if the interpreter was never granted in the first place.
///
/// Everything runs as the student, never elevated. Where a real answer needs privilege, the agent
/// is instructed to hand the student the exact command to run in the unrestricted shell beside the
/// chat — which is also the better lesson: they see the `sudo`, and they decide.
struct AllowlistedCommandRunner {
    struct Result { let allowed: Bool; let output: String }

    /// What a single allowlisted command may do. Most commands are safe in every form; the ones
    /// with a destructive or code-executing mode are narrowed to their read-only subset.
    struct Rule {
        /// Flags that turn a read-only tool into a writing or executing one.
        var deniedFlags: Set<String> = []
        /// When set, only these first-argument subcommands are permitted.
        var allowedSubcommands: Set<String>? = nil
        /// When set, the first argument must start with one of these (e.g. `networksetup -get…`).
        var allowedArgPrefixes: [String]? = nil
    }

    /// Read-only commands, grouped by what a student actually asks about.
    static let rules: [String: Rule] = {
        var r: [String: Rule] = [:]

        // Locating things — the case that prompted this: "where does kimicut live?"
        for name in ["which", "type", "whereis", "readlink", "realpath", "dirname", "basename"] {
            r[name] = Rule()
        }

        // Reading files and figuring out what they are.
        for name in ["cat", "head", "tail", "wc", "file", "strings", "stat", "column"] {
            r[name] = Rule()
        }

        // Listing and searching. `find` can delete and execute; those modes are removed.
        r["ls"] = Rule()
        r["du"] = Rule()
        r["df"] = Rule()
        r["tree"] = Rule()
        r["grep"] = Rule()
        r["find"] = Rule(deniedFlags: ["-delete", "-exec", "-execdir", "-ok", "-okdir",
                                       "-fls", "-fprint", "-fprint0", "-fprintf"])

        // Machine and OS facts.
        for name in ["sw_vers", "uname", "arch", "hostname", "uptime", "date", "whoami",
                     "id", "groups", "system_profiler", "vm_stat", "ps"] {
            r[name] = Rule()
        }
        r["sysctl"] = Rule(deniedFlags: ["-w"])          // -w sets kernel state

        // Networking.
        for name in ["ifconfig", "ipconfig", "netstat", "scutil", "arp", "dig", "host", "nslookup"] {
            r[name] = Rule()
        }
        r["ping"] = Rule()                                // bounded by ProcessRunner's timeout
        r["networksetup"] = Rule(allowedArgPrefixes: ["-list", "-get"])

        // Developer environment.
        r["git"] = Rule(allowedSubcommands: ["status", "log", "show", "diff", "branch", "remote",
                                             "config", "describe", "rev-parse", "ls-files",
                                             "shortlog", "blame", "tag", "stash"])
        r["brew"] = Rule(allowedSubcommands: ["list", "info", "config", "outdated", "deps",
                                              "--version", "--prefix", "--cellar"])
        r["npm"] = Rule(allowedSubcommands: ["list", "ls", "view", "--version", "-v"])
        r["defaults"] = Rule(allowedSubcommands: ["read", "read-type", "domains"])
        r["launchctl"] = Rule(allowedSubcommands: ["list", "print"])
        for name in ["env", "printenv", "echo", "xcode-select", "swift", "python3", "node", "ruby"] {
            // Version probes only — an interpreter with a script or -e is arbitrary code execution.
            r[name] = Rule(allowedSubcommands: ["--version", "-v", "-V", "--help", "-p", "version"])
        }

        return r
    }()

    static var allowlist: Set<String> { Set(rules.keys) }

    /// Characters that would allow chaining, redirection, substitution, or quoting tricks.
    /// Blocking these is what keeps the allowlist meaningful — with `;` or `$(…)` available, any
    /// permitted command becomes a launcher for a forbidden one.
    private static let blocked = CharacterSet(charactersIn: ";|&`$><()\n\r\\\"'")

    /// Paths whose contents should never be read aloud into a chat transcript, even though the
    /// student owns them. This one *is* a denylist, and it is fine as one: it guards against
    /// incidental leakage while answering an innocent question, not against someone determined.
    private static let sensitivePathMarkers = [
        ".ssh/", ".aws/", ".gnupg", ".env", "id_rsa", "id_ed25519", "id_ecdsa", ".netrc",
        "credentials", ".pem", ".p12", ".key", "keychain", ".git-credentials", ".npmrc",
        ".pypirc", ".docker/config.json", "secrets"
    ]

    private static let searchDirs = ["/usr/bin", "/bin", "/usr/sbin", "/sbin",
                                     "/usr/local/bin", "/opt/homebrew/bin"]

    private static let outputCap = 8000

    func run(_ command: String) async -> Result {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(allowed: false, output: "Refused: empty command.") }

        if trimmed.rangeOfCharacter(from: Self.blocked) != nil {
            return refuse("shell operators (pipes, redirection, chaining, quotes) aren't allowed. Run one simple command; call the tool again for the next step.")
        }

        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let name = tokens.first else { return Result(allowed: false, output: "Refused: empty command.") }
        if name.contains("/") {
            return refuse("use a bare command name, not a path.")
        }
        guard let rule = Self.rules[name] else {
            return refuse("`\(name)` is not available. Readable commands: \(Self.allowlist.sorted().joined(separator: ", ")).")
        }

        let args = Array(tokens.dropFirst())
        if let violation = Self.checkArguments(name: name, args: args, rule: rule) {
            return refuse(violation)
        }
        if let sensitive = Self.sensitiveArgument(in: args) {
            return refuse("`\(sensitive)` looks like it holds credentials, so it isn't readable here. If you genuinely need it, open it yourself in the shell beside the chat.")
        }
        guard let path = Self.locate(name) else {
            return Result(allowed: false, output: "Could not find `\(name)` on this Mac.")
        }

        let (exit, output) = await ProcessRunner.run(path, args)
        let capped = output.count > Self.outputCap
            ? String(output.prefix(Self.outputCap)) + "\n…(truncated)"
            : output

        // A permission failure is the signal to hand the command back to the student rather than
        // to escalate: they have a real shell open beside the chat.
        if exit != 0, capped.lowercased().contains("permission denied") || capped.lowercased().contains("operation not permitted") {
            return Result(allowed: true, output: capped + "\n(This needs privileges the tutor doesn't have. Tell the student to run it themselves — with `sudo` if appropriate — in the shell beside the chat.)")
        }
        return Result(allowed: true, output: capped.isEmpty ? "(no output)" : capped)
    }

    private func refuse(_ why: String) -> Result {
        Result(allowed: false, output: "Refused: \(why)")
    }

    /// Enforces a command's per-rule narrowing. Returns nil when the arguments are acceptable.
    static func checkArguments(name: String, args: [String], rule: Rule) -> String? {
        for arg in args where rule.deniedFlags.contains(arg) {
            return "`\(name) \(arg)` can modify or execute things, so it isn't available. Use \(name) without \(arg)."
        }
        if let allowed = rule.allowedSubcommands {
            guard let first = args.first else {
                return "`\(name)` needs one of these subcommands here: \(allowed.sorted().joined(separator: ", "))."
            }
            guard allowed.contains(first) else {
                return "`\(name) \(first)` isn't available. Allowed: \(allowed.sorted().joined(separator: ", "))."
            }
        }
        if let prefixes = rule.allowedArgPrefixes {
            guard let first = args.first, prefixes.contains(where: { first.hasPrefix($0) }) else {
                return "`\(name)` is limited to its read-only options here (\(prefixes.joined(separator: ", "))…)."
            }
        }
        return nil
    }

    /// The first argument that looks like a credential store, if any.
    static func sensitiveArgument(in args: [String]) -> String? {
        args.first { arg in
            let lower = arg.lowercased()
            return sensitivePathMarkers.contains { lower.contains($0) }
        }
    }

    static func locate(_ name: String) -> String? {
        for dir in searchDirs {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
