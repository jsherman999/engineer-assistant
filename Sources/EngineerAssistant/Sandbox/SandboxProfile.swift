import Foundation

enum SandboxProfile {
    static func macOSProfile(sandboxDir: String) -> String {
        return """
        (version 1)
        (allow default)

        ;; Block all writes by default, then re-allow only inside the sandbox
        ;; and a few necessary device/temp paths the shell needs to function.
        (deny file-write*)
        (allow file-write*
          (subpath "\(sandboxDir)")
          (subpath "/private/tmp")
          (subpath "/private/var/folders")
          (literal "/dev/null")
          (literal "/dev/tty")
          (literal "/dev/stdin")
          (literal "/dev/stdout")
          (literal "/dev/stderr")
          (literal "/dev/dtracehelper"))

        ;; No network at all (DNS, sockets, etc.).
        (deny network*)
        """
    }
}
