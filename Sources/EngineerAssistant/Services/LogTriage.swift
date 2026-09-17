import Foundation

/// What kind of trouble a log line is reporting. Matching is on *problem* wording, not on
/// topic words: an early version keyed on `thermal` and matched 1,684 copies of "thermal
/// pressure nominal", which is the machine reporting that it is fine.
enum LogCategory: String, CaseIterable, Codable {
    case failure
    case resource
    case crash
    case security

    var label: String {
        switch self {
        case .failure: return "Failure"
        case .resource: return "Resource"
        case .crash: return "Crash"
        case .security: return "Security"
        }
    }

    /// Ordered so the first match wins; security and crash are checked before the broad
    /// `failure` vocabulary, which would otherwise swallow them.
    static var matchOrder: [LogCategory] { [.security, .crash, .resource, .failure] }

    var pattern: String {
        switch self {
        case .failure:
            return #"\b(fail(s|ed|ure)?|error|denied|refused|unable to|cannot|couldn't|invalid|rejected|not (found|permitted|enough))\b"#
        case .resource:
            return #"\b(ENOSPC|ENOMEM|out of (memory|space|disk)|no (free )?space|exhausted|0 bytes|disk full|quota exceeded|thermal (pressure )?(critical|serious|heavy))\b"#
        case .crash:
            return #"\b(panic|crashed|abort(ed)?|segfault|bad address|killed|terminated unexpectedly|hung|stalled|timed out|unresponsive|watchdog)\b"#
        case .security:
            return #"\b(unauthoriz\w*|authentication (fail\w*|error)|created (local )?(user|account)|new (user|account)|added .{0,80}launch item|accepted (incoming )?connection|session opened for user|sudo:|privilege escalation|firewall blocked)\b"#
        }
    }
}

/// One distinct *kind* of problem found in a log, with how often it occurred.
///
/// The unit is deliberately the distinct problem rather than the line. A real
/// `/var/log/install.log` on this Mac matched 33,292 lines but only 152 distinct shapes — one
/// of them 21,816 times. Showing a student 33,292 lines teaches nothing; showing them 152
/// problems, each with a count, is the actual skill.
struct LogProblem: Identifiable, Equatable {
    let id: Int
    let signature: String
    /// A real line from the log, kept verbatim so the student sees the original.
    let example: String
    let occurrences: Int
    /// Line number of the most recent occurrence (1-based).
    let lastLine: Int
    let category: LogCategory
    /// Share of attention assigned by the model, 0 when Tier 1 didn't run.
    var weight: Double = 0
}

struct TriageResult: Equatable {
    let path: String
    let totalLines: Int
    /// Lines matching a problem pattern, before collapsing duplicates.
    let matchedLines: Int
    let problems: [LogProblem]
    /// True when only the tail of an oversized file was read, which makes `lastLine` a position
    /// within that tail rather than within the whole file. Shown, not hidden — a line number
    /// that doesn't match what the student sees in an editor is worse than no line number.
    var readTruncated: Bool = false
    /// True when the model ranked the problems; false means Tier 0 order (most recent first).
    let ranked: Bool
    /// The model's read on whether anything here is genuinely serious, nil when it didn't run.
    let seriousness: Double?

    var truncated: Bool { problems.count >= LogTriage.maxProblems }
}

/// Narrows a log down to the handful of things worth a person's attention.
///
/// Two stages, and the split is the whole point. Tier 0 is ordinary code — a pattern match and
/// a deduplication — and it does the volume reduction: on this Mac's real install.log it takes
/// 261,205 lines to 152 distinct problems in about two seconds, for free, offline. Tier 1 sends
/// only those 152 survivors to the model, which decides which of them actually matters.
///
/// That division is what makes the feature affordable. Sending the whole log to the model costs
/// roughly 33 tokens a line — 8.6 million for this one file — to answer a question the pattern
/// match already answers. Sending the survivors costs about 16,000.
///
/// Tier 1 earns its place by ranking in a way no counting rule can: on the real install.log it
/// put a `Bootstrap failed: 5: Input/output error` seen **once** above a warning seen **21,816**
/// times. Sorting by frequency buries exactly the line a person needed to see.
enum LogTriage {
    /// The model accepts at most 255 options in one ranking question.
    static let maxProblems = 255
    /// Only the tail of a very large log is read; recent trouble is what a person is asking about.
    static let maxBytes = 8 * 1024 * 1024

    /// Logs worth offering by name. Filtered to the ones that exist and are readable, because
    /// most of `/var/log` needs root and an unreadable entry is just a dead end.
    static let suggestedPaths = [
        "/var/log/system.log",
        "/var/log/install.log",
        "/var/log/wifi.log",
        "/var/log/fsck_apfs.log",
        "/var/log/appfirewall.log"
    ]

    static func readablePaths() -> [String] {
        suggestedPaths.filter { FileManager.default.isReadableFile(atPath: $0) }
    }

    // MARK: - Tier 0: pattern match and deduplicate (pure, no network)

    private static let compiled: [(LogCategory, NSRegularExpression)] = LogCategory.matchOrder.compactMap {
        guard let re = try? NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]) else { return nil }
        return ($0, re)
    }

    static func category(of line: String) -> LogCategory? {
        guard !line.isEmpty else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        for (category, re) in compiled where re.firstMatch(in: line, options: [], range: range) != nil {
            return category
        }
        return nil
    }

    private static let normalizers: [(NSRegularExpression, String)] = {
        let specs: [(String, String)] = [
            (#"^\w{3}\s+\d+\s[\d:]+"#, ""),                              // syslog timestamp
            (#"\d{4}-\d{2}-\d{2}[ T][\d:.,+-]+"#, ""),                    // iso timestamp
            (#"\[\d+\]"#, "[]"),                                          // pids
            (#"\b0x[0-9a-fA-F]+\b"#, "0xX"),                              // hex addresses
            (#"\b[0-9a-fA-F]{8}-[0-9a-fA-F-]{20,}\b"#, "UUID"),
            (#"/[^\s"']{4,}"#, "PATH"),
            (#"\b\d+\b"#, "N"),
            (#"\s+"#, " ")
        ]
        return specs.compactMap { pattern, template in
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (re, template)
        }
    }()

    /// Reduces a line to its shape, so the same problem reported a thousand times with different
    /// timestamps, pids and paths collapses to one entry.
    static func signature(of line: String) -> String {
        var s = line
        for (re, template) in normalizers {
            s = re.stringByReplacingMatches(in: s, options: [],
                                            range: NSRange(s.startIndex..., in: s),
                                            withTemplate: template)
        }
        return String(s.trimmingCharacters(in: .whitespaces).prefix(160))
    }

    /// Tier 0. Scans text and returns the distinct problems in it, most recent first.
    static func scan(_ text: String, path: String) -> TriageResult {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var order: [String] = []
        var counts: [String: Int] = [:]
        var examples: [String: String] = [:]
        var lastLine: [String: Int] = [:]
        var categories: [String: LogCategory] = [:]
        var matched = 0

        for (idx, line) in lines.enumerated() {
            guard let category = category(of: line) else { continue }
            matched += 1
            let key = signature(of: line)
            if counts[key] == nil {
                order.append(key)
                examples[key] = line
                categories[key] = category
            }
            counts[key, default: 0] += 1
            lastLine[key] = idx + 1
        }

        // Most recently seen first, then capped. Recency rather than frequency because the
        // thing a person is asking about is usually the thing that just happened, and a rare
        // problem is exactly what frequency ordering would hide.
        let ranked = order.sorted { (lastLine[$0] ?? 0) > (lastLine[$1] ?? 0) }.prefix(maxProblems)
        let problems = ranked.enumerated().map { idx, key in
            LogProblem(id: idx,
                       signature: key,
                       example: examples[key] ?? key,
                       occurrences: counts[key] ?? 1,
                       lastLine: lastLine[key] ?? 0,
                       category: categories[key] ?? .failure)
        }
        return TriageResult(path: path, totalLines: lines.count, matchedLines: matched,
                            problems: problems, ranked: false, seriousness: nil)
    }

    /// Reads a log from disk and runs Tier 0 over it. Only the tail of a very large file is read.
    static func scanFile(at path: String) throws -> TriageResult {
        let url = URL(fileURLWithPath: path)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
        if size > maxBytes {
            try handle.seek(toOffset: UInt64(size - maxBytes))
        }
        let data = try handle.readToEnd() ?? Data()
        var result = scan(String(decoding: data, as: UTF8.self), path: path)
        result.readTruncated = size > maxBytes
        return result
    }

    // MARK: - Tier 1: the model ranks the survivors

    static let rankQuestionID = "worst"
    static let seriousQuestionID = "serious"

    static func rankingOptions(for problems: [LogProblem]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: problems.map { ("P\($0.id)", "This problem.") })
    }

    static func rankQuestion(for problems: [LogProblem]) -> ChoiceQuestion {
        ChoiceQuestion(
            id: rankQuestionID,
            instructions: "Which of these distinct log problems most deserves a system administrator's attention? Answer with its id.",
            options: rankingOptions(for: problems)
        )
    }

    static var seriousQuestion: NoulQuestion {
        NoulQuestion(
            id: seriousQuestionID,
            instructions: "Do these log problems include anything that actually threatens this machine's health, data, or security?",
            whenTrue: "Yes, at least one is a real problem worth acting on.",
            whenFalse: "No, these are routine application-level noise that can safely be ignored."
        )
    }

    static func state(for result: TriageResult) -> [String: Any] {
        [
            "log_file": result.path,
            "machine": "a student's Mac",
            "distinct_problems": result.problems.map {
                ["id": "P\($0.id)", "times_seen": $0.occurrences, "example_line": String($0.example.prefix(200))]
            }
        ]
    }

    /// Applies the model's ranking to a Tier 0 result. Returns the input unchanged when the
    /// model is unavailable, so Tier 0 alone remains a usable feature.
    static func applyRanking(_ answers: [String: Double],
                             choiceProbabilities: [String: Double],
                             to result: TriageResult) -> TriageResult {
        guard !choiceProbabilities.isEmpty else { return result }
        var problems = result.problems
        for idx in problems.indices {
            problems[idx].weight = choiceProbabilities["P\(problems[idx].id)"] ?? 0
        }
        problems.sort {
            $0.weight != $1.weight ? $0.weight > $1.weight : $0.lastLine > $1.lastLine
        }
        return TriageResult(path: result.path, totalLines: result.totalLines,
                            matchedLines: result.matchedLines, problems: problems,
                            readTruncated: result.readTruncated,
                            ranked: true, seriousness: answers[seriousQuestionID])
    }

    /// Tier 1. Sends only the deduplicated survivors and returns the result re-ordered by what
    /// the model thinks matters.
    ///
    /// Returns the Tier 0 result untouched when there's no key, no network, or a bad response —
    /// ranking is an enhancement, and a pattern-matched, deduplicated list is already useful on
    /// its own.
    static func rank(_ result: TriageResult, client: TypeSafeClient = TypeSafeClient()) async -> TriageResult {
        guard TypeSafeClient.isConfigured, !result.problems.isEmpty else { return result }
        guard let answers = try? await client.ask(state: state(for: result),
                                                  nouls: [seriousQuestion],
                                                  choices: [rankQuestion(for: result.problems)]) else {
            return result
        }
        return applyRanking(answers.nouls,
                            choiceProbabilities: answers.choices[rankQuestionID] ?? [:],
                            to: result)
    }
}
