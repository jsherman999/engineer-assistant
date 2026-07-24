import Foundation

/// Runs a short-lived process to completion and captures its combined output.
/// Used for container `exec` file probes and `rm -f` cleanup — not for the PTY shell.
enum ProcessRunner {
    /// Default ceiling for a single helper command. A wedged container engine or a `system_profiler`
    /// that never returns would otherwise hang the caller — and its UI — indefinitely.
    static let defaultTimeout: TimeInterval = 30

    static func run(_ launchPath: String,
                    _ args: [String],
                    environment: [String: String]? = nil,
                    timeout: TimeInterval = defaultTimeout) async -> (exit: Int32, output: String) {
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

                // Terminate on timeout, then escalate if it ignores SIGTERM. `readDataToEndOfFile`
                // below returns once the pipe closes, which killing the process guarantees.
                let timedOut = DispatchWorkItem {
                    if proc.isRunning {
                        proc.terminate()
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
                        }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timedOut)

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                timedOut.cancel()

                var output = String(decoding: data, as: UTF8.self)
                if proc.terminationReason == .uncaughtSignal {
                    output += output.isEmpty ? "" : "\n"
                    output += "(stopped after \(Int(timeout))s — the command didn't finish)"
                }
                continuation.resume(returning: (proc.terminationStatus, output))
            }
        }
    }
}

/// Single-quotes a string for safe inclusion in a `sh -c` command.
func shellSingleQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
