import Foundation

enum SandboxProfile {
    static func macOSProfile(sandboxDir: String) -> String {
        return """
        (version 1)
        (allow default)

        ;; Block all writes by default, then re-allow inside the sandbox, the necessary
        ;; device/temp paths the shell needs, and the Homebrew prefix so `brew install` works.
        ;; (/opt/homebrew is the REAL shared Homebrew — installs here persist on the host.)
        (deny file-write*)
        (allow file-write*
          (subpath "\(sandboxDir)")
          (subpath "/opt/homebrew")
          (subpath "/private/tmp")
          (subpath "/private/var/folders")
          (literal "/dev/null")
          (literal "/dev/tty")
          (literal "/dev/stdin")
          (literal "/dev/stdout")
          (literal "/dev/stderr")
          (literal "/dev/dtracehelper"))

        ;; Network is allowed (via allow default) so brew/curl/git/dns work. The rest of the
        ;; system (home, /System, /usr) stays write-protected — only the sandbox dir, temp,
        ;; and the Homebrew prefix are writable.
        """
    }
}
