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

final class CourseGenerator {
    private let client: ClaudeClient
    private let store: CourseStore

    init(client: ClaudeClient = ClaudeClient(), store: CourseStore = FileCourseStore()) {
        self.client = client
        self.store = store
    }

    func generate(subject: String, forceRefresh: Bool = false, containerGuidance: String? = nil) async throws -> GenerationResult {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !forceRefresh, let cached = store.load(subject: trimmed) {
            return GenerationResult(course: cached, wasCached: true)
        }
        let draft = try await client.generateCourse(subject: trimmed, containerGuidance: containerGuidance)
        let course = Course(subject: trimmed, draft: draft)
        try store.save(course)
        return GenerationResult(course: course, wasCached: false)
    }
}
