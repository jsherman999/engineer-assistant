import Foundation

/// Abstracts the file checks a challenge verifier needs, so the same `Verifier` works
/// against the macOS host sandbox directory or inside a Linux container.
protocol SandboxFileSystem: Sendable {
    func fileExists(_ path: String) async -> Bool
    func readFile(_ path: String) async -> String?
}

/// macOS sandbox: paths resolve against the per-course working directory (the shell's HOME).
struct HostSandboxFileSystem: SandboxFileSystem {
    let root: URL

    func resolve(_ path: String) -> URL {
        if path == "~" { return root }
        if path.hasPrefix("~/") { return root.appendingPathComponent(String(path.dropFirst(2))) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return root.appendingPathComponent(path)
    }

    /// Courses sometimes hardcode a guessed home like `/Users/student/notes.txt` that doesn't
    /// match this Mac's real sandbox dir. When the literal path is missing, reinterpret a
    /// generic-home absolute path as relative to the sandbox home.
    private func homeRelativeFallback(_ path: String) -> URL? {
        for prefix in ["/Users/", "/home/"] where path.hasPrefix(prefix) {
            let afterPrefix = path.dropFirst(prefix.count)
            guard let slash = afterPrefix.firstIndex(of: "/") else { return root }
            let rest = String(afterPrefix[afterPrefix.index(after: slash)...])
            return rest.isEmpty ? root : root.appendingPathComponent(rest)
        }
        return nil
    }

    func fileExists(_ path: String) async -> Bool {
        if FileManager.default.fileExists(atPath: resolve(path).path) { return true }
        if let alt = homeRelativeFallback(path) {
            return FileManager.default.fileExists(atPath: alt.path)
        }
        return false
    }

    func readFile(_ path: String) async -> String? {
        if let contents = try? String(contentsOf: resolve(path), encoding: .utf8) { return contents }
        if let alt = homeRelativeFallback(path) {
            return try? String(contentsOf: alt, encoding: .utf8)
        }
        return nil
    }
}

/// Linux sandbox: paths are checked inside the running container via `<engine> exec`. The
/// container's home and working dir are `/root`, so home-relative, `~`, and bare paths are
/// also tried under `/root` (the same robustness the macOS sandbox has).
struct ContainerFileSystem: SandboxFileSystem {
    let enginePath: String
    let containerName: String

    /// Paths to try, in order: the literal path first, then a `/root`-relative interpretation.
    private func candidates(_ path: String) -> [String] {
        if path == "~" { return ["/root"] }
        if path.hasPrefix("~/") { return ["/root/" + path.dropFirst(2)] }
        var out = [path]
        for prefix in ["/Users/", "/home/"] where path.hasPrefix(prefix) {
            let afterPrefix = path.dropFirst(prefix.count)
            if let slash = afterPrefix.firstIndex(of: "/") {
                out.append("/root/" + afterPrefix[afterPrefix.index(after: slash)...])
            } else {
                out.append("/root")
            }
        }
        if !path.hasPrefix("/") { out.append("/root/" + path) }
        return out
    }

    func fileExists(_ path: String) async -> Bool {
        for candidate in candidates(path) {
            let (exit, _) = await ProcessRunner.run(enginePath, ["exec", containerName, "sh", "-c", "test -e \(shellSingleQuote(candidate))"])
            if exit == 0 { return true }
        }
        return false
    }

    func readFile(_ path: String) async -> String? {
        for candidate in candidates(path) {
            let (exit, output) = await ProcessRunner.run(enginePath, ["exec", containerName, "sh", "-c", "cat -- \(shellSingleQuote(candidate))"])
            if exit == 0 { return output }
        }
        return nil
    }
}
