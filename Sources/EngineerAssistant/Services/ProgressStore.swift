import Foundation

struct CourseProgress: Codable, Equatable {
    var lessonIdx: Int
    var completed: Bool
}

protocol ProgressStore {
    func progress(for courseId: String) -> CourseProgress?
    func set(_ progress: CourseProgress, for courseId: String)
    func remove(courseId: String)
}

/// Persists per-course progress to a single JSON map so a course resumes at the same
/// lesson after the app is quit and relaunched.
struct FileProgressStore: ProgressStore {
    let url: URL

    init(url: URL = AppPaths.progressFile) {
        self.url = url
    }

    private func load() -> [String: CourseProgress] {
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: CourseProgress].self, from: data) else {
            return [:]
        }
        return map
    }

    func progress(for courseId: String) -> CourseProgress? {
        load()[courseId]
    }

    func set(_ progress: CourseProgress, for courseId: String) {
        var map = load()
        map[courseId] = progress
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func remove(courseId: String) {
        var map = load()
        map[courseId] = nil
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
