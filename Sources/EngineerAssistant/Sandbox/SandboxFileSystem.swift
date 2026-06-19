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

    func fileExists(_ path: String) async -> Bool {
        FileManager.default.fileExists(atPath: resolve(path).path)
    }

    func readFile(_ path: String) async -> String? {
        try? String(contentsOf: resolve(path), encoding: .utf8)
    }
}

/// Linux sandbox: paths are checked inside the running container via `<engine> exec`.
struct ContainerFileSystem: SandboxFileSystem {
    let enginePath: String
    let containerName: String

    func fileExists(_ path: String) async -> Bool {
        let (exit, _) = await ProcessRunner.run(enginePath, ["exec", containerName, "sh", "-c", "test -e \(shellSingleQuote(path))"])
        return exit == 0
    }

    func readFile(_ path: String) async -> String? {
        let (exit, output) = await ProcessRunner.run(enginePath, ["exec", containerName, "sh", "-c", "cat -- \(shellSingleQuote(path))"])
        return exit == 0 ? output : nil
    }
}
