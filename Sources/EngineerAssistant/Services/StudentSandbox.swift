import Foundation

/// Gives each course open a fresh, student-friendly sandbox directory:
/// `/Users/<user>/students/student<N>`. N comes from a global counter that increments on
/// every open and is never reused, so the path stays short instead of the long
/// Application Support / UUID path the student would otherwise see in `pwd`.
///
/// Each course's allocated dirs are tracked so purging a course removes all of them.
struct StudentSandbox {
    let rootDir: URL
    let mapFile: URL

    static let shared = StudentSandbox(
        rootDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("students", isDirectory: true),
        mapFile: AppPaths.appSupport.appendingPathComponent("students.json")
    )

    private struct State: Codable {
        var counter: Int = 0
        var byCourse: [String: [Int]] = [:]
    }

    private func load() -> State {
        guard let data = try? Data(contentsOf: mapFile),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    private func save(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: mapFile, options: .atomic)
    }

    /// Allocates and creates a brand-new student directory for this open of the course.
    func directory(forCourseId courseId: String) -> URL {
        var state = load()
        state.counter += 1
        let n = state.counter
        state.byCourse[courseId, default: []].append(n)
        save(state)
        let dir = rootDir.appendingPathComponent("student\(n)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A single stable scratch directory for Ask mode. Not numbered — it persists across the
    /// session so the student keeps one workspace while experimenting alongside the chat.
    func askDirectory() -> URL {
        let dir = rootDir.appendingPathComponent("ask", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes every student directory this course has allocated and forgets them (used when
    /// a course is purged). The global counter is left untouched so numbers keep climbing.
    func remove(forCourseId courseId: String) {
        var state = load()
        for n in state.byCourse[courseId] ?? [] {
            try? FileManager.default.removeItem(at: rootDir.appendingPathComponent("student\(n)", isDirectory: true))
        }
        state.byCourse[courseId] = nil
        save(state)
    }
}
