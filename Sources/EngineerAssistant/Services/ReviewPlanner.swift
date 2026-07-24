import Foundation

/// A lesson the student should revisit, and why.
struct ReviewItem: Identifiable, Equatable {
    var id: String { "\(courseId)#\(lessonIdx)" }
    let courseId: String
    let courseTitle: String
    let lessonIdx: Int
    let lessonTitle: String
    let lastSeen: Date
    let reason: Reason

    enum Reason: Equatable {
        case struggled       // last attempt failed
        case neededHint      // passed, but with a hint
        case spacedInterval  // passed cleanly; due on the schedule

        var label: String {
            switch self {
            case .struggled: return "didn't pass last time"
            case .neededHint: return "needed a hint"
            case .spacedInterval: return "time for a refresh"
            }
        }
    }

    var daysSinceLastSeen: Int {
        Calendar.current.dateComponents([.day], from: lastSeen, to: Date()).day ?? 0
    }
}

/// Decides which lessons are due for review.
///
/// The gradebook already records, per lesson, whether the student passed, whether they needed a
/// hint, and when — which is everything a spacing schedule needs. Rather than adding a separate
/// review database, the schedule is derived from that history: a lesson they struggled with comes
/// back tomorrow, one they needed a hint for in a few days, and one they passed cleanly gets
/// progressively longer gaps. Reviewing a lesson records a new attempt, which feeds the next
/// interval, so the loop sustains itself.
enum ReviewPlanner {
    /// Days to wait after a clean pass, indexed by how many times in a row they've passed it.
    static let cleanPassIntervals = [3, 7, 21, 60]
    static let struggledInterval = 1
    /// Between the two: they got there, but not unaided.
    static let hintedInterval = 2

    static func dueItems(in results: [CourseResults], courses: [Course], now: Date = Date()) -> [ReviewItem] {
        let titles = Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [ReviewItem] = []

        for result in results {
            guard let course = titles[result.courseId] else { continue }
            for lessonIdx in course.lessons.indices {
                // Look across every attempt: a lesson passed two retakes ago is still learned.
                let history = result.attempts
                    .filter { $0.lessonIdx == lessonIdx }
                    .sorted { $0.timestamp < $1.timestamp }
                guard let latest = history.last else { continue }

                let (interval, reason) = schedule(for: history)
                let due = Calendar.current.date(byAdding: .day, value: interval, to: latest.timestamp) ?? latest.timestamp
                guard due <= now else { continue }

                items.append(ReviewItem(
                    courseId: course.id,
                    courseTitle: course.title,
                    lessonIdx: lessonIdx,
                    lessonTitle: course.lessons[lessonIdx].title,
                    lastSeen: latest.timestamp,
                    reason: reason
                ))
            }
        }

        // Weakest first: what they failed matters more than what's merely gone stale.
        return items.sorted { lhs, rhs in
            if lhs.reason != rhs.reason { return priority(lhs.reason) < priority(rhs.reason) }
            return lhs.lastSeen < rhs.lastSeen
        }
    }

    private static func priority(_ reason: ReviewItem.Reason) -> Int {
        switch reason {
        case .struggled: return 0
        case .neededHint: return 1
        case .spacedInterval: return 2
        }
    }

    /// How long to wait before showing this lesson again, based on how it went.
    static func schedule(for history: [LessonAttempt]) -> (days: Int, reason: ReviewItem.Reason) {
        guard let latest = history.last else { return (struggledInterval, .struggled) }
        if !latest.passed { return (struggledInterval, .struggled) }
        if latest.hintUsed { return (hintedInterval, .neededHint) }

        // Consecutive clean passes stretch the gap.
        var streak = 0
        for attempt in history.reversed() {
            guard attempt.passed, !attempt.hintUsed else { break }
            streak += 1
        }
        let index = min(max(streak - 1, 0), cleanPassIntervals.count - 1)
        return (cleanPassIntervals[index], .spacedInterval)
    }
}
