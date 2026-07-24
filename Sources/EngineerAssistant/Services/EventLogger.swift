import Foundation

/// Typed façade over the append-only event log.
///
/// Every one of these was previously an inline method on `AppSession`, which meant a third of
/// that type was payload-dictionary construction. Keeping them here means the event vocabulary
/// — the thing the instructor dashboard reads — is defined in one place, next to `EventType`,
/// instead of being spread through session logic.
///
/// Writes are best-effort: a failure to record must never interrupt the student's lesson.
struct EventLogger {
    let store: EventStore

    private func append(_ type: EventType,
                        sessionId: String,
                        courseId: String? = nil,
                        lessonIdx: Int? = nil,
                        payload: [String: AnyCodable]) async {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: type,
            courseId: courseId,
            lessonIdx: lessonIdx,
            payload: payload
        )
        try? await store.append(event)
    }

    // MARK: - Chat

    func chat(_ type: EventType,
              mode: ChatMode,
              text: String,
              sessionId: String,
              courseId: String?,
              lessonIdx: Int? = nil) async {
        await append(type, sessionId: sessionId, courseId: courseId, lessonIdx: lessonIdx,
                     payload: ["text": AnyCodable(text), "mode": AnyCodable(mode.rawValue)])
    }

    func agentCommand(command: String, output: String, allowed: Bool, sessionId: String) async {
        await append(.agentCommand, sessionId: sessionId,
                     payload: ["command": AnyCodable(command),
                               "output": AnyCodable(output),
                               "allowed": AnyCodable(allowed)])
    }

    // MARK: - Course lifecycle

    func courseGenerated(course: Course, wasCached: Bool, sessionId: String) async {
        await append(.courseGenerated, sessionId: sessionId, courseId: course.id,
                     payload: ["subject": AnyCodable(course.subject),
                               "title": AnyCodable(course.title),
                               "environment": AnyCodable(course.environment.rawValue),
                               "lesson_count": AnyCodable(course.lessons.count),
                               "was_cached": AnyCodable(wasCached)])
    }

    func lessonStart(course: Course, idx: Int, sessionId: String) async {
        guard idx < course.lessons.count else { return }
        await append(.lessonStart, sessionId: sessionId, courseId: course.id, lessonIdx: idx,
                     payload: ["lesson_title": AnyCodable(course.lessons[idx].title)])
    }

    func lessonComplete(course: Course, idx: Int, finished: Bool, sessionId: String) async {
        guard idx < course.lessons.count else { return }
        await append(.lessonComplete, sessionId: sessionId, courseId: course.id, lessonIdx: idx,
                     payload: ["lesson_title": AnyCodable(course.lessons[idx].title),
                               "finished": AnyCodable(finished)])
    }

    // MARK: - Challenges

    func challengeAttempt(course: Course, idx: Int, command: String, sessionId: String) async {
        await append(.challengeAttempt, sessionId: sessionId, courseId: course.id, lessonIdx: idx,
                     payload: ["command": AnyCodable(command)])
    }

    func challengeResult(passed: Bool,
                         course: Course,
                         idx: Int,
                         verify: VerifyCheck,
                         detail: String,
                         sessionId: String) async {
        // Pass and fail use different payload keys so an export reads naturally either way.
        let detailKey = passed ? "evidence" : "reason"
        await append(passed ? .challengePass : .challengeFail,
                     sessionId: sessionId, courseId: course.id, lessonIdx: idx,
                     payload: ["verify_type": AnyCodable(verify.type.rawValue),
                               detailKey: AnyCodable(detail)])
    }

    func hintUsed(course: Course, idx: Int, text: String, sessionId: String) async {
        await append(.hintUsed, sessionId: sessionId, courseId: course.id, lessonIdx: idx,
                     payload: ["hint_text": AnyCodable(text)])
    }

    /// The student's own account of why their solution worked. Worth recording separately from
    /// pass/fail: it is the clearest signal an instructor gets of whether they actually understood.
    func explainBack(course: Course, idx: Int, answer: String, feedback: String, sessionId: String) async {
        await append(.explainBack, sessionId: sessionId, courseId: course.id, lessonIdx: idx,
                     payload: ["answer": AnyCodable(answer), "feedback": AnyCodable(feedback)])
    }

    func skipUsed(course: Course, idx: Int, panel: String, sessionId: String) async {
        await append(.skipUsed, sessionId: sessionId, courseId: course.id, lessonIdx: idx,
                     payload: ["from_panel": AnyCodable(panel)])
    }
}
