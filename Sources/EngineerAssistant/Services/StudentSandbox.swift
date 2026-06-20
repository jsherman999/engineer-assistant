import Foundation

/// Gives each course a short, student-friendly sandbox directory:
/// `/Users/<user>/students/student<N>`. N is allocated the first time a course is opened
/// and reused on reopen, so the path stays stable (and short) instead of the long
/// Application Support / UUID path the student would otherwise see in `pwd`.
struct StudentSandbox {
    let rootDir: URL
    let mapFile: URL

    static let shared = StudentSandbox(
        rootDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("students", isDirectory: true),
        mapFile: AppPaths.appSupport.appendingPathComponent("students.json")
    )

    private func loadMap() -> [String: Int] {
        guard let data = try? Data(contentsOf: mapFile),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return map
    }

    private func saveMap(_ map: [String: Int]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: mapFile, options: .atomic)
    }

    /// The persistent student directory for a course, allocating the next number the first
    /// time the course is seen. Creates the directory on disk.
    func directory(forCourseId courseId: String) -> URL {
        var map = loadMap()
        let n: Int
        if let existing = map[courseId] {
            n = existing
        } else {
            n = (map.values.max() ?? 0) + 1
            map[courseId] = n
            saveMap(map)
        }
        let dir = rootDir.appendingPathComponent("student\(n)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes a course's student directory and its mapping (used when a course is purged).
    func remove(forCourseId courseId: String) {
        var map = loadMap()
        guard let n = map[courseId] else { return }
        let dir = rootDir.appendingPathComponent("student\(n)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        map[courseId] = nil
        saveMap(map)
    }
}
