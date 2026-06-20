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

        ;; Network is allowed (via allow default) so teaching tools that fetch data —
        ;; brew info/search, curl, git, dig — work. The student still can't modify the real
        ;; system: writes stay confined to the sandbox dir, so e.g. `brew install` (which writes
        ;; to /opt/homebrew) is still blocked.
        """
    }
}
