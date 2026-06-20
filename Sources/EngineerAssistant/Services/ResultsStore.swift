import Foundation

/// One recorded outcome of checking a lesson's challenge. Multiple checks of the same
/// lesson append multiple records; `attempt` separates retakes of the whole course.
struct LessonAttempt: Codable, Equatable, Identifiable {
    var id: String
    var attempt: Int
    var lessonIdx: Int
    var lessonTitle: String
    var passed: Bool
    var detail: String
    var command: String
    var hintUsed: Bool
    var timestamp: Date
}

/// Persistent, per-course gradebook the student and instructor review later. Independent of
/// the append-only event log: this is the structured source of truth for lesson results.
struct CourseResults: Codable, Equatable {
    var courseId: String
    var subject: String
    var title: String
    var lessonCount: Int
    var currentAttempt: Int
    var attempts: [LessonAttempt]

    /// Lesson indices that have at least one passing check in the given attempt.
    func passedLessons(inAttempt attempt: Int) -> Set<Int> {
        Set(attempts.filter { $0.attempt == attempt && $0.passed }.map(\.lessonIdx))
    }

    /// Lessons passed in the current attempt.
    var passedCount: Int { passedLessons(inAttempt: currentAttempt).count }

    /// Most recent check of a lesson within an attempt (latest timestamp).
    func latest(lessonIdx: Int, attempt: Int) -> LessonAttempt? {
        attempts
            .filter { $0.attempt == attempt && $0.lessonIdx == lessonIdx }
            .max { $0.timestamp < $1.timestamp }
    }
}

protocol ResultsStore {
    func results(for courseId: String) -> CourseResults?
    func all() -> [CourseResults]
    func record(_ attempt: LessonAttempt, courseId: String, subject: String, title: String, lessonCount: Int)
    /// Bumps the attempt counter for a fresh retake and returns the new attempt number.
    @discardableResult
    func startNewAttempt(courseId: String, subject: String, title: String, lessonCount: Int) -> Int
    func clearLesson(courseId: String, lessonIdx: Int)
    func remove(courseId: String)
}

/// Persists a `courseId -> CourseResults` map to a single JSON file.
struct FileResultsStore: ResultsStore {
    let url: URL

    init(url: URL = AppPaths.resultsFile) {
        self.url = url
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    private func load() -> [String: CourseResults] {
        guard let data = try? Data(contentsOf: url),
              let map = try? decoder.decode([String: CourseResults].self, from: data) else {
            return [:]
        }
        return map
    }

    private func save(_ map: [String: CourseResults]) {
        guard let data = try? encoder.encode(map) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func ensure(_ map: inout [String: CourseResults], courseId: String, subject: String, title: String, lessonCount: Int) -> CourseResults {
        if var existing = map[courseId] {
            // Keep metadata current in case the course was regenerated.
            existing.subject = subject
            existing.title = title
            existing.lessonCount = lessonCount
            map[courseId] = existing
            return existing
        }
        let fresh = CourseResults(courseId: courseId, subject: subject, title: title, lessonCount: lessonCount, currentAttempt: 1, attempts: [])
        map[courseId] = fresh
        return fresh
    }

    func results(for courseId: String) -> CourseResults? {
        load()[courseId]
    }

    func all() -> [CourseResults] {
        Array(load().values).sorted { $0.title < $1.title }
    }

    func record(_ attempt: LessonAttempt, courseId: String, subject: String, title: String, lessonCount: Int) {
        var map = load()
        var cr = ensure(&map, courseId: courseId, subject: subject, title: title, lessonCount: lessonCount)
        cr.attempts.append(attempt)
        map[courseId] = cr
        save(map)
    }

    @discardableResult
    func startNewAttempt(courseId: String, subject: String, title: String, lessonCount: Int) -> Int {
        var map = load()
        var cr = ensure(&map, courseId: courseId, subject: subject, title: title, lessonCount: lessonCount)
        cr.currentAttempt += 1
        map[courseId] = cr
        save(map)
        return cr.currentAttempt
    }

    func clearLesson(courseId: String, lessonIdx: Int) {
        var map = load()
        guard var cr = map[courseId] else { return }
        cr.attempts.removeAll { $0.lessonIdx == lessonIdx }
        map[courseId] = cr
        save(map)
    }

    func remove(courseId: String) {
        var map = load()
        map[courseId] = nil
        save(map)
    }
}
