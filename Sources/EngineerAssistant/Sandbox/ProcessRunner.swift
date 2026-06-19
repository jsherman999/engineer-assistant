import Foundation

/// Runs a short-lived process to completion and captures its combined output.
/// Used for container `exec` file probes and `rm -f` cleanup — not for the PTY shell.
enum ProcessRunner {
    static func run(_ launchPath: String, _ args: [String], environment: [String: String]? = nil) async -> (exit: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: launchPath)
                proc.arguments = args
                if let environment { proc.environment = environment }
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: (-1, error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                continuation.resume(returning: (proc.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}

/// Single-quotes a string for safe inclusion in a `sh -c` command.
func shellSingleQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
