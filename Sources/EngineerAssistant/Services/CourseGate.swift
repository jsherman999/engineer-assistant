import Foundation

/// A challenge the student could not possibly complete, and which lesson it belongs to.
struct GateFailure: Equatable {
    /// Lesson index, or `lessons.count` for the capstone — the same numbering `ResultsStore` uses.
    let lessonIdx: Int
    let title: String
    /// How strongly the challenge presupposes a file that was never seeded (0...1).
    let score: Double
}

/// Screens a freshly generated course for challenges the student physically cannot complete.
///
/// The sandbox starts empty. A challenge that says "fix the broken script" is only solvable if
/// the course also shipped that script in `starter_files`, and Claude regularly writes the task
/// while forgetting the file. Nothing downstream catches it: the verifier just reports that the
/// file doesn't exist, the hint politely discusses a file that was never there, and the student
/// concludes they are bad at this. The whole failure is visible at generation time, so this
/// checks there — before the course is written to the cache and kept forever.
///
/// Deliberately one question per challenge. An earlier version also scored whether the verify
/// check matched the task, but on a known-good course that scored 0.35–0.69 across four
/// perfectly fine lessons — too vague to act on, and a gate that fires on good courses is worse
/// than no gate.
enum CourseGate {
    /// Above this, a challenge is treated as impossible.
    ///
    /// Measured against a real generated course and four mutations of it, each with one
    /// challenge's seeded files removed: the 20 intact challenges scored 0.08–0.23, and every
    /// one of the 4 sabotaged challenges scored 0.87–0.96. The threshold sits in that gap, set
    /// high on purpose — wrongly rejecting a good course costs a full regeneration, so the bias
    /// is toward letting a doubtful course through.
    ///
    /// The question is phrased around *presupposition* rather than solvability for a measured
    /// reason. Asking "can this be completed?" scored a sabotaged "fix `~/greet.sh`" challenge at
    /// 0.54 — the model allowed that the student could just create the file themselves, which is
    /// true and beside the point. Asking whether the task treats a file as already existing
    /// separates the same case at 0.87.
    static let presupposesMissingFileThreshold = 0.6

    /// The state Jev judges: what the challenge asks for, and what will actually be on disk.
    ///
    /// `starter_state` is deliberately excluded. It is prose that *describes* a starting point
    /// without creating anything, so including it would let a course talk its way past the very
    /// check this exists to perform.
    static func state(for draft: CourseDraft) -> [String: Any] {
        var entries: [[String: Any]] = draft.lessons.map { lesson in
            entry(title: lesson.title, challenge: lesson.challenge)
        }
        if let final = draft.finalChallenge {
            entries.append(entry(title: "Final Challenge", challenge: final))
        }
        return ["environment": draft.environment.rawValue, "challenges": entries]
    }

    private static func entry(title: String, challenge: Challenge) -> [String: Any] {
        let files = challenge.starterFiles ?? []
        return [
            "title": title,
            "task": challenge.task,
            "files_seeded_before_the_student_starts": files.isEmpty
                ? "NONE — the sandbox is completely empty"
                : files.map { ["path": $0.path, "content": String($0.content.prefix(400))] }
        ]
    }

    /// One question per challenge, each scoped to its own index so the answers come back
    /// separable. They are asked together in a single request; questions can't see one another's
    /// answers, so batching costs one round trip instead of N.
    static func questions(for draft: CourseDraft) -> [NoulQuestion] {
        let count = draft.lessons.count + (draft.finalChallenge == nil ? 0 : 1)
        return (0..<count).map { idx in
            NoulQuestion(
                id: "missing_file_\(idx)",
                instructions: """
                Look only at `challenges[\(idx)]`. Does `challenges[\(idx)].task` refer to any file \
                as though it ALREADY EXISTS — asking the student to fix, repair, edit, read, \
                search, count, or inspect it — when that exact file is NOT in this challenge's \
                seeded files?
                """,
                whenTrue: "Yes: the task treats some file as pre-existing content the student must work on, but that file was never seeded, so the student would find nothing there.",
                whenFalse: "No: every file the task treats as pre-existing is seeded, or the task only asks the student to create new files from scratch."
            )
        }
    }

    /// Turns raw answers into the failures worth blocking on.
    static func failures(from answers: [String: Double], draft: CourseDraft) -> [GateFailure] {
        let titles = draft.lessons.map(\.title) + (draft.finalChallenge == nil ? [] : ["Final Challenge"])
        return titles.indices.compactMap { idx in
            guard let score = answers["missing_file_\(idx)"],
                  score > presupposesMissingFileThreshold else { return nil }
            return GateFailure(lessonIdx: idx, title: titles[idx], score: score)
        }
    }

    /// Screens a draft. Returns the impossible challenges, or an empty list when the course is
    /// fine — and also when the gate simply isn't available.
    ///
    /// Screening is an improvement to generation, never a dependency of it: with no key stored,
    /// no network, or a bad response, this returns no failures and the course is kept exactly as
    /// it would have been before this existed.
    static func screen(_ draft: CourseDraft, client: TypeSafeClient = TypeSafeClient()) async -> [GateFailure] {
        guard TypeSafeClient.isConfigured else { return [] }
        guard let answers = try? await client.ask(state: state(for: draft), questions: questions(for: draft)) else {
            return []
        }
        return failures(from: answers, draft: draft)
    }
}
