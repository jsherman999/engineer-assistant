import XCTest
@testable import EngineerAssistant

final class LogTriageTests: XCTestCase {

    // MARK: - Tier 0: what counts as a problem

    func testMatchesRealProblemWording() {
        XCTAssertEqual(LogTriage.category(of: "backupd[412]: Backup failed with error: not enough free space"), .failure)
        XCTAssertEqual(LogTriage.category(of: "kernel[0]: APFS: container has 0 bytes of free space remaining"), .resource)
        XCTAssertEqual(LogTriage.category(of: "spindump[889]: process 'Xcode' stalled writing to disk"), .crash)
        XCTAssertEqual(LogTriage.category(of: "opendirectoryd[92]: created local user account 'svc_update'"), .security)
    }

    /// The failure vocabulary is broad enough to swallow the other categories, so ordering
    /// matters: a new account being created is a security event, not a generic failure.
    func testSecurityAndCrashWinOverGenericFailureWording() {
        XCTAssertEqual(LogTriage.category(of: "loginwindow: session opened for user svc_update, no error"), .security)
        XCTAssertEqual(LogTriage.category(of: "watchdog: error, process unresponsive"), .crash)
    }

    /// An early version keyed on topic words and matched 1,684 copies of "thermal pressure
    /// nominal" — the machine reporting that it is fine. Patterns must match trouble, not topic.
    func testDoesNotFlagRoutineStatusLines() {
        for line in ["powerd[17]: thermal pressure nominal",
                     "kernel[0]: IOAccel: context created",
                     "Dock[212]: registered service com.apple.dock.server",
                     "mDNSResponder[99]: network interface en0 link state changed",
                     "syspolicyd[144]: TCC access granted for kTCCServiceSystemPolicy",
                     "cloudd[303]: cache flushed 128 entries",
                     ""] {
            XCTAssertNil(LogTriage.category(of: line), "\(line) should not be flagged")
        }
    }

    // MARK: - Tier 0: collapsing repeats

    /// The same problem reported with different timestamps, pids and paths is one problem.
    func testSignatureCollapsesVariableParts() {
        let a = "Sep 15 21:56:40 macmini softwareupdated[545]: error running script at /Users/jay/a/b.js"
        let b = "Sep 16 03:11:02 macmini softwareupdated[9912]: error running script at /Users/sam/c/d.js"
        XCTAssertEqual(LogTriage.signature(of: a), LogTriage.signature(of: b))
    }

    func testSignatureKeepsGenuinelyDifferentProblemsApart() {
        let a = "Sep 15 21:56:40 macmini backupd[1]: Backup failed, not enough free space"
        let b = "Sep 15 21:56:40 macmini sharingd[1]: accepted incoming connection"
        XCTAssertNotEqual(LogTriage.signature(of: a), LogTriage.signature(of: b))
    }

    func testScanCountsOccurrencesAndKeepsOneEntryPerProblem() {
        let log = (0..<50).map { "Sep 15 10:00:0\($0 % 10) mac softwareupdated[\($0)]: Failed to get bridge device" }
            .joined(separator: "\n")
            + "\nSep 15 11:00:00 mac kernel[0]: APFS: 0 bytes of free space remaining"
        let result = LogTriage.scan(log, path: "/tmp/x.log")

        XCTAssertEqual(result.totalLines, 51)
        XCTAssertEqual(result.matchedLines, 51)
        XCTAssertEqual(result.problems.count, 2, "50 copies of one problem plus one other = 2 distinct problems")
        let bridge = result.problems.first { $0.example.contains("bridge device") }
        XCTAssertEqual(bridge?.occurrences, 50)
        XCTAssertFalse(result.ranked)
        XCTAssertNil(result.seriousness)
    }

    func testScanKeepsTheOriginalLineAsTheExample() {
        let result = LogTriage.scan("Sep 15 10:00:00 mac kernel[0]: disk full", path: "/tmp/x.log")
        XCTAssertEqual(result.problems.first?.example, "Sep 15 10:00:00 mac kernel[0]: disk full",
                       "the student should see the real line, not its normalized shape")
    }

    /// Recency, not frequency: a one-off problem is exactly what frequency ordering hides, and
    /// on the real install.log the single most important line occurred once against a rival
    /// seen 21,816 times.
    func testMostRecentProblemComesFirstBeforeRanking() {
        let log = """
        Sep 15 10:00:00 mac a[1]: error one
        Sep 15 10:00:01 mac a[1]: error one
        Sep 15 11:00:00 mac b[2]: disk full
        """
        let result = LogTriage.scan(log, path: "/tmp/x.log")
        XCTAssertEqual(result.problems.first?.category, .resource)
        XCTAssertEqual(result.problems.first?.occurrences, 1)
    }

    func testScanCapsAtTheChoiceLimit() {
        let log = (0..<400).map { "Sep 15 10:00:00 mac proc[1]: error code \($0) in module_\($0)_x" }
            .joined(separator: "\n")
        let result = LogTriage.scan(log, path: "/tmp/x.log")
        XCTAssertEqual(result.problems.count, LogTriage.maxProblems)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.matchedLines, 400, "the count reported must be the real one, not the capped one")
    }

    func testCleanLogProducesNoProblems() {
        let result = LogTriage.scan("Sep 15 10:00:00 mac powerd[1]: thermal pressure nominal", path: "/tmp/x.log")
        XCTAssertTrue(result.problems.isEmpty)
        XCTAssertEqual(result.matchedLines, 0)
    }

    // MARK: - Tier 1: applying the ranking

    func testRankingReordersByModelWeight() {
        let result = LogTriage.scan("""
        Sep 15 10:00:00 mac a[1]: error alpha
        Sep 15 10:00:01 mac b[2]: error bravo
        Sep 15 10:00:02 mac c[3]: error charlie
        """, path: "/tmp/x.log")
        XCTAssertEqual(result.problems.count, 3)

        // Give the OLDEST problem the highest weight; it must end up first.
        let oldest = result.problems.first { $0.example.contains("alpha") }!
        let ranked = LogTriage.applyRanking(
            ["serious": 0.81],
            choiceProbabilities: ["P\(oldest.id)": 0.9],
            to: result
        )
        XCTAssertTrue(ranked.ranked)
        XCTAssertEqual(ranked.seriousness, 0.81)
        XCTAssertTrue(ranked.problems.first?.example.contains("alpha") ?? false)
        XCTAssertEqual(ranked.problems.first?.weight, 0.9)
    }

    /// Ranking is an enhancement. With no answer, the Tier 0 list must survive intact — a
    /// pattern-matched, deduplicated log is useful on its own and must not be emptied.
    func testEmptyRankingLeavesTierZeroResultUntouched() {
        let result = LogTriage.scan("Sep 15 10:00:00 mac a[1]: disk full", path: "/tmp/x.log")
        let ranked = LogTriage.applyRanking([:], choiceProbabilities: [:], to: result)
        XCTAssertEqual(ranked, result)
        XCTAssertFalse(ranked.ranked)
    }

    func testProblemsMissingFromTheRankingKeepZeroWeightAndStaySorted() {
        let result = LogTriage.scan("""
        Sep 15 10:00:00 mac a[1]: error alpha
        Sep 15 10:00:01 mac b[2]: error bravo
        """, path: "/tmp/x.log")
        let first = result.problems[0]
        let ranked = LogTriage.applyRanking([:], choiceProbabilities: ["P\(first.id)": 0.7], to: result)
        XCTAssertEqual(ranked.problems.count, 2)
        XCTAssertEqual(ranked.problems.first?.id, first.id)
        XCTAssertEqual(ranked.problems.last?.weight, 0)
    }

    // MARK: - Question construction

    func testRankingOffersEveryProblemAsAnOption() {
        let result = LogTriage.scan("""
        Sep 15 10:00:00 mac a[1]: error alpha
        Sep 15 10:00:01 mac b[2]: error bravo
        """, path: "/tmp/x.log")
        let question = LogTriage.rankQuestion(for: result.problems)
        XCTAssertEqual(question.options.count, 2)
        XCTAssertEqual(Set(question.options.keys), Set(result.problems.map { "P\($0.id)" }))
    }

    /// Only the deduplicated survivors may leave the machine — never the whole log.
    func testStateSendsOnlyTheSurvivingProblemLines() throws {
        let log = (0..<200).map { "Sep 15 10:00:00 mac proc[1]: routine chatter number \($0)" }
            .joined(separator: "\n") + "\nSep 15 11:00:00 mac k[0]: disk full"
        let result = LogTriage.scan(log, path: "/tmp/x.log")
        let json = try JSONSerialization.data(withJSONObject: LogTriage.state(for: result))
        let text = String(decoding: json, as: UTF8.self)
        XCTAssertTrue(text.contains("disk full"))
        XCTAssertFalse(text.contains("routine chatter"), "non-matching lines must never be transmitted")
    }

    // MARK: - Choice parsing

    func testParsesChoiceProbabilitiesAndConfidence() throws {
        let json = Data("""
        {"model":"jev-1.13.0","answers":{
          "worst":{"type":"choice","choice":"P0","probabilities":{"P0":0.49,"P1":0.26},"confidence":0.47},
          "serious":{"type":"noul","noul":0.73}},
        "usage":{"input_tokens":16184,"output_tokens":120}}
        """.utf8)
        let answers = try TypeSafeClient.parseAnswers(json)
        XCTAssertEqual(answers.nouls["serious"], 0.73)
        XCTAssertEqual(answers.choices["worst"]?["P0"], 0.49)
        XCTAssertEqual(answers.confidence["worst"], 0.47)
    }
}
