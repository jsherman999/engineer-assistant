import XCTest
@testable import EngineerAssistant

final class AskAgentTests: XCTestCase {
    private let runner = AllowlistedCommandRunner()

    // MARK: - The invariants that make the allowlist mean anything

    func testRefusesEmpty() async {
        let r = await runner.run("   ")
        XCTAssertFalse(r.allowed)
    }

    /// With `;` or `$(…)` available, any permitted command becomes a launcher for a forbidden
    /// one — so operator blocking is what the whole allowlist rests on.
    func testRefusesShellMetacharacters() async {
        for cmd in ["ifconfig | grep inet", "uname; rm -rf /", "echo $(whoami)", "df > /tmp/x",
                    "sw_vers && id", "cat `which ls`", "ls 'my file'"] {
            let r = await runner.run(cmd)
            XCTAssertFalse(r.allowed, "should refuse: \(cmd)")
            XCTAssertTrue(r.output.contains("Refused"), "\(cmd) → \(r.output)")
        }
    }

    func testRefusesOffAllowlist() async {
        for cmd in ["rm -rf /", "curl example.com", "sudo reboot", "chmod 777 /etc",
                    "dd if=/dev/zero of=/dev/disk2", "nc -l 8080", "sed -i s/a/b/ f.txt",
                    "awk BEGIN{system(\"id\")}", "open -a Calculator", "mkfs.ext4 /dev/sda"] {
            let r = await runner.run(cmd)
            XCTAssertFalse(r.allowed, "should refuse: \(cmd)")
        }
    }

    func testRefusesAbsolutePath() async {
        let r = await runner.run("/bin/ps aux")
        XCTAssertFalse(r.allowed)
    }

    /// An interpreter with a script or -e is arbitrary code execution wearing an allowlisted name.
    func testInterpretersAreLimitedToVersionProbes() async {
        for cmd in ["python3 -c import os", "ruby -e puts", "node --eval 1+1",
                    "python3 script.py", "swift file.swift"] {
            let r = await runner.run(cmd)
            XCTAssertFalse(r.allowed, "should refuse: \(cmd)")
        }
        let version = await runner.run("python3 --version")
        XCTAssertTrue(version.allowed, "a version probe is fine")
    }

    // MARK: - The reported bug

    /// "Where does kimicut live?" was refused because `which` wasn't allowlisted.
    func testLocatingAProgramWorks() async {
        let r = await runner.run("which ls")
        XCTAssertTrue(r.allowed, "which should be available: \(r.output)")
        XCTAssertTrue(r.output.contains("/ls"), r.output)
    }

    /// The follow-up half: locate it, then read it.
    func testReadingAFileWorks() async {
        let r = await runner.run("head -n 2 /etc/hosts")
        XCTAssertTrue(r.allowed, r.output)
        XCTAssertFalse(r.output.isEmpty)
    }

    func testCommonInspectionCommandsAreAvailable() async {
        for cmd in ["ls -la /tmp", "file /etc/hosts", "stat /etc/hosts", "wc -l /etc/hosts",
                    "grep -c . /etc/hosts", "type ls", "basename /usr/bin/env"] {
            let r = await runner.run(cmd)
            XCTAssertTrue(r.allowed, "should allow \(cmd): \(r.output)")
        }
    }

    func testAllowsAndRunsReadOnlyCommand() async {
        let r = await runner.run("uname -a")
        XCTAssertTrue(r.allowed)
        XCTAssertTrue(r.output.contains("Darwin"))
    }

    // MARK: - Per-command narrowing

    /// `find` is read-only right up until `-delete` or `-exec`.
    func testFindCannotDeleteOrExecute() {
        let rule = AllowlistedCommandRunner.rules["find"]!
        for flag in ["-delete", "-exec", "-execdir", "-ok", "-fprintf"] {
            XCTAssertNotNil(
                AllowlistedCommandRunner.checkArguments(name: "find", args: [".", flag, "rm"], rule: rule),
                "find \(flag) must be refused"
            )
        }
        XCTAssertNil(
            AllowlistedCommandRunner.checkArguments(name: "find", args: [".", "-name", "*.txt"], rule: rule),
            "an ordinary find should pass"
        )
    }

    func testGitIsLimitedToReadSubcommands() async {
        for cmd in ["git push", "git commit -m x", "git reset --hard", "git clean -fd"] {
            let r = await runner.run(cmd)
            XCTAssertFalse(r.allowed, "should refuse: \(cmd)")
        }
        let rule = AllowlistedCommandRunner.rules["git"]!
        XCTAssertNil(AllowlistedCommandRunner.checkArguments(name: "git", args: ["status"], rule: rule))
        XCTAssertNil(AllowlistedCommandRunner.checkArguments(name: "git", args: ["log", "--oneline"], rule: rule))
    }

    func testDefaultsCannotWriteAndSysctlCannotSet() async {
        let write = await runner.run("defaults write com.apple.finder x 1")
        XCTAssertFalse(write.allowed)
        let rule = AllowlistedCommandRunner.rules["sysctl"]!
        XCTAssertNotNil(AllowlistedCommandRunner.checkArguments(name: "sysctl", args: ["-w", "kern.maxfiles=100"], rule: rule))
        XCTAssertNil(AllowlistedCommandRunner.checkArguments(name: "sysctl", args: ["-n", "hw.ncpu"], rule: rule))
    }

    func testNetworksetupIsLimitedToReadOptions() {
        let rule = AllowlistedCommandRunner.rules["networksetup"]!
        XCTAssertNil(AllowlistedCommandRunner.checkArguments(name: "networksetup", args: ["-listallhardwareports"], rule: rule))
        XCTAssertNotNil(AllowlistedCommandRunner.checkArguments(name: "networksetup", args: ["-setdnsservers", "Wi-Fi", "1.1.1.1"], rule: rule))
    }

    // MARK: - Credential guard

    /// The student owns these files, but their contents must not be read aloud into a chat
    /// transcript while answering an unrelated question.
    func testRefusesToReadCredentialFiles() async {
        for cmd in ["cat /Users/me/.ssh/id_rsa", "head ~/.aws/credentials", "cat .env",
                    "cat /Users/me/certs/server.pem", "grep token ~/.npmrc"] {
            let r = await runner.run(cmd)
            XCTAssertFalse(r.allowed, "should refuse: \(cmd)")
            XCTAssertTrue(r.output.contains("credentials"), r.output)
        }
    }

    func testOrdinaryDotfilesAreStillReadable() {
        XCTAssertNil(AllowlistedCommandRunner.sensitiveArgument(in: ["~/.zshrc"]))
        XCTAssertNil(AllowlistedCommandRunner.sensitiveArgument(in: ["/etc/hosts"]))
        XCTAssertNotNil(AllowlistedCommandRunner.sensitiveArgument(in: ["~/.ssh/config"]))
    }

    // MARK: - Escalation path

    /// The agent never elevates. A privilege failure should tell it to hand the command to the
    /// student, who has a real shell open beside the chat.
    func testPermissionFailureSuggestsHandingItToTheStudent() async {
        // Readable only by root on macOS.
        let r = await runner.run("cat /var/db/dslocal/nodes/Default/users/root.plist")
        XCTAssertTrue(r.allowed, "the command itself is permitted; it just fails")
        XCTAssertTrue(r.output.contains("run it themselves"), r.output)
    }
}
