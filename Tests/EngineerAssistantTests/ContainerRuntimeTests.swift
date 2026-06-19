import XCTest
@testable import EngineerAssistant

final class ContainerRuntimeTests: XCTestCase {
    private func makeExecutable(_ name: String, in dir: URL) {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
    }

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testLocateFindsExecutable() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        makeExecutable("podman", in: dir)
        XCTAssertEqual(ContainerRuntime.locate("podman", in: [dir.path]), dir.appendingPathComponent("podman").path)
        XCTAssertNil(ContainerRuntime.locate("docker", in: [dir.path]))
    }

    func testDetectPrefersAppleContainerThenPodmanThenDocker() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        makeExecutable("docker", in: dir)
        makeExecutable("podman", in: dir)
        // Only docker + podman present → podman wins (Apple container preferred but absent)
        XCTAssertEqual(ContainerRuntime.detect(searchPaths: [dir.path])?.engine, .podman)

        makeExecutable("container", in: dir)
        // Apple container now present → it wins
        XCTAssertEqual(ContainerRuntime.detect(searchPaths: [dir.path])?.engine, .apple)
    }

    func testDetectReturnsNilWhenNoneInstalled() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(ContainerRuntime.detect(searchPaths: [dir.path]))
    }

    func testShellSingleQuoteEscapes() {
        XCTAssertEqual(shellSingleQuote("/root/foo.txt"), "'/root/foo.txt'")
        XCTAssertEqual(shellSingleQuote("a'b"), "'a'\\''b'")
    }
}
