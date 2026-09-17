import Foundation

protocol CourseStore {
    func load(subject: String) -> Course?
    func save(_ course: Course) throws
    func listAll() -> [Course]
    func delete(_ course: Course) throws
}

struct FileCourseStore: CourseStore {
    let directory: URL

    init(directory: URL = AppPaths.coursesDir) {
        self.directory = directory
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return e
    }

    private func url(forSlug slug: String) -> URL {
        directory.appendingPathComponent("\(slug).json")
    }

    func load(subject: String) -> Course? {
        let slug = CourseSubject.slug(for: subject)
        let url = url(forSlug: slug)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Course.self, from: data)
    }

    func save(_ course: Course) throws {
        let slug = CourseSubject.slug(for: course.subject)
        let data = try encoder.encode(course)
        try data.write(to: url(forSlug: slug), options: .atomic)
    }

    func listAll() -> [Course] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return items.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Course.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func delete(_ course: Course) throws {
        let slug = CourseSubject.slug(for: course.subject)
        let url = url(forSlug: slug)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

struct GenerationResult {
    let course: Course
    let wasCached: Bool
}

enum CourseGenerationError: Error, LocalizedError {
    case unsolvableChallenges([GateFailure])

    var errorDescription: String? {
        switch self {
        case .unsolvableChallenges(let failures):
            let named = failures.map { "“\($0.title)”" }.joined(separator: ", ")
            let subject = failures.count == 1 ? "\(named) asks" : "\(named) ask"
            return "\(subject) the student to work on files the course never creates, so \(failures.count == 1 ? "it" : "they") can't be completed in an empty sandbox. Regenerating didn't fix it — try rewording the subject."
        }
    }
}

final class CourseGenerator {
    private let client: ClaudeClient
    private let store: CourseStore

    init(client: ClaudeClient = ClaudeClient(), store: CourseStore = FileCourseStore()) {
        self.client = client
        self.store = store
    }

    func generate(subject: String, forceRefresh: Bool = false, containerGuidance: String? = nil) async throws -> GenerationResult {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = store.load(subject: trimmed)
        if !forceRefresh, let cached = existing {
            return GenerationResult(course: cached, wasCached: true)
        }
        let draft = try await screenedDraft(subject: trimmed, containerGuidance: containerGuidance)
        // Regenerating a subject keeps the previous course's id so the student's progress,
        // saved results, and allocated sandbox dirs stay attached instead of being orphaned
        // under an id nothing references any more.
        let course = Course(id: existing?.id ?? UUID().uuidString, subject: trimmed, draft: draft)
        try store.save(course)
        return GenerationResult(course: course, wasCached: false)
    }

    /// Generates a draft and screens it for challenges the empty sandbox can't support.
    ///
    /// A failure is usually a one-off slip rather than a property of the subject, so the first
    /// bad draft is simply thrown away and regenerated. Only a second failure is reported — at
    /// which point the subject itself is likely the problem, and caching the course would mean
    /// handing the student a lesson they cannot finish.
    private func screenedDraft(subject: String, containerGuidance: String?) async throws -> CourseDraft {
        let first = try await client.generateCourse(subject: subject, containerGuidance: containerGuidance)
        if await CourseGate.screen(first).isEmpty { return first }

        let second = try await client.generateCourse(subject: subject, containerGuidance: containerGuidance)
        let failures = await CourseGate.screen(second)
        guard failures.isEmpty else { throw CourseGenerationError.unsolvableChallenges(failures) }
        return second
    }
}
