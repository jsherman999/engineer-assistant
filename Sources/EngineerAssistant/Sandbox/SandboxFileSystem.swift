import Foundation

/// Abstracts the file checks a challenge verifier needs, so the same `Verifier` works
/// against the macOS host sandbox directory or inside a Linux container.
protocol SandboxFileSystem: Sendable {
    func fileExists(_ path: String) async -> Bool
    func readFile(_ path: String) async -> String?
    /// Seeds a challenge's `starter_files` before the student begins. Parent directories are
    /// created; `executable` marks scripts runnable.
    func writeFile(_ path: String, content: String, executable: Bool) async
    /// Home-relative paths in the sandbox, for the live tree beside the terminal. Directories
    /// end in `/`. Dotfiles are omitted — the shell integration writes `.zshrc`/`.sandbox.sb`
    /// into the sandbox and those are ours, not the student's.
    func listTree(maxDepth: Int, limit: Int) async -> [String]
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

    func listTree(maxDepth: Int, limit: Int) async -> [String] {
        // FileManager's enumerator can't be iterated from an async context, so the walk happens
        // in a synchronous helper.
        walk(maxDepth: maxDepth, limit: limit)
    }

    private func walk(maxDepth: Int, limit: Int) -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var out: [String] = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in enumerator {
            if out.count >= limit { break }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            var relative = String(path.dropFirst(rootPath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            guard !relative.isEmpty else { continue }
            let depth = relative.split(separator: "/").count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            out.append(isDirectory ? relative + "/" : relative)
        }
        return out.sorted()
    }

    func writeFile(_ path: String, content: String, executable: Bool) async {
        // Always seed inside the sandbox, even if the course wrote an absolute path.
        let url = path.hasPrefix("/") ? (homeRelativeFallback(path) ?? resolve(path)) : resolve(path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
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

    func listTree(maxDepth: Int, limit: Int) async -> [String] {
        // Two POSIX `find` passes rather than GNU `-printf`, which BusyBox images lack:
        // directories are listed first and given a trailing slash, files listed as-is.
        // `-not -path '*/.*'` drops dotfiles the same way the macOS side does.
        let common = "-mindepth 1 -maxdepth \(maxDepth) -not -path '*/.*'"
        let script = """
        cd /root || exit 1
        find . \(common) -type d | sed 's|$|/|'
        find . \(common) ! -type d
        """
        let (exit, output) = await ProcessRunner.run(enginePath, ["exec", containerName, "sh", "-c", script])
        guard exit == 0 else { return [] }

        return output.split(separator: "\n").compactMap { raw -> String? in
            var line = String(raw)
            guard line.hasPrefix("./") else { return nil }
            line.removeFirst(2)
            return line.isEmpty ? nil : line
        }
        .sorted()
        .prefix(limit)
        .map { $0 }
    }

    func writeFile(_ path: String, content: String, executable: Bool) async {
        // Seed under /root (the container's HOME and working dir), and move the content over
        // base64 so newlines, quotes, and shell metacharacters survive the `sh -c` round-trip.
        let target = candidates(path).last ?? path
        let quoted = shellSingleQuote(target)
        let b64 = Data(content.utf8).base64EncodedString()
        var script = "mkdir -p \"$(dirname \(quoted))\" && printf '%s' \(shellSingleQuote(b64)) | base64 -d > \(quoted)"
        if executable { script += " && chmod +x \(quoted)" }
        _ = await ProcessRunner.run(enginePath, ["exec", containerName, "sh", "-c", script])
    }
}
