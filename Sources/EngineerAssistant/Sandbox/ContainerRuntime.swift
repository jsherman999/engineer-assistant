import Foundation

/// A detected container engine used to run Linux courses. The three supported engines
/// share a near-identical CLI (`run`/`exec`/`-it`/`-e`/`-w`/`--name`/`--rm`/`rm -f`),
/// so the only per-engine differences are detection priority and the readiness hint.
struct ContainerRuntime: Equatable {
    enum Engine: String, CaseIterable {
        case apple = "container" // Apple's native tool, best on macOS 26+ Apple Silicon
        case podman
        case docker

        var displayName: String {
            switch self {
            case .apple: return "Apple container"
            case .podman: return "Podman"
            case .docker: return "Docker"
            }
        }

        /// What to tell the user to run if the engine's service isn't up.
        var readinessHint: String {
            switch self {
            case .apple: return "container system start"
            case .podman: return "podman machine start"
            case .docker: return "open Docker Desktop"
            }
        }
    }

    let engine: Engine
    let path: String

    var displayName: String { engine.displayName }

    /// Detects an installed engine, preferring Apple `container`, then Podman, then Docker.
    static func detect(searchPaths: [String] = defaultSearchPaths) -> ContainerRuntime? {
        for engine in Engine.allCases {
            if let path = locate(engine.rawValue, in: searchPaths) {
                return ContainerRuntime(engine: engine, path: path)
            }
        }
        return nil
    }

    static func locate(_ tool: String, in dirs: [String]) -> String? {
        let fm = FileManager.default
        for dir in dirs {
            let candidate = (dir as NSString).appendingPathComponent(tool)
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static var defaultSearchPaths: [String] {
        var dirs: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs += path.split(separator: ":").map(String.init)
        }
        dirs += ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
        return dirs
    }
}
