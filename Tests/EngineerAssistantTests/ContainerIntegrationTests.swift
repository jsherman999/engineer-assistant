import XCTest
@testable import EngineerAssistant

/// Exercises the real container engine via the app's own ProcessRunner + ContainerFileSystem.
/// Skipped by default (keeps the suite hermetic); run with EA_RUN_CONTAINER_TESTS=1 and an
/// engine installed/started.
final class ContainerIntegrationTests: XCTestCase {
    private let cname = "ea-itest"

    private func requireEngine() throws -> ContainerRuntime {
        guard ProcessInfo.processInfo.environment["EA_RUN_CONTAINER_TESTS"] != nil else {
            throw XCTSkip("Set EA_RUN_CONTAINER_TESTS=1 to run container integration tests.")
        }
        guard let rt = ContainerRuntime.detect() else { throw XCTSkip("No container engine installed.") }
        return rt
    }

    func testContainerFileSystemAgainstRealEngine() async throws {
        let rt = try requireEngine()
        _ = await ProcessRunner.run(rt.path, ["rm", "-f", cname]) // clean slate
        defer { Task { _ = await ProcessRunner.run(rt.path, ["rm", "-f", cname]) } }

        let run = await ProcessRunner.run(rt.path, ["run", "-d", "--name", cname, "docker.io/library/ubuntu:latest", "sleep", "120"])
        XCTAssertEqual(run.exit, 0, "container run failed: \(run.output)")

        let write = await ProcessRunner.run(rt.path, ["exec", cname, "sh", "-c", "echo hello-linux > /root/it.txt"])
        XCTAssertEqual(write.exit, 0, "exec write failed: \(write.output)")

        let fs = ContainerFileSystem(enginePath: rt.path, containerName: cname)
        let exists = await fs.fileExists("/root/it.txt")
        XCTAssertTrue(exists)
        let missing = await fs.fileExists("/root/nope.txt")
        XCTAssertFalse(missing)
        let contents = await fs.readFile("/root/it.txt")
        XCTAssertEqual(contents?.contains("hello-linux"), true)
    }
}
