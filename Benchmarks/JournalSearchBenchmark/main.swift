import Foundation
import ForgeCore

// Measures journal search at the supported history limit with a synthetic, deterministic
// history; it never reads or writes a learner's saved progress.
// Run with: scripts/swift-command.sh run -c release JournalSearchBenchmark

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

let curriculum = try Curriculum.loadBundled()
let modules = curriculum.modules
let titles = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0.title) })
let vocabulary = """
    implemented queue invariant graph traversal breadth depth first search shortest path heap priority
    binary tree balanced rotation hashing collision bucket dynamic programming memo table recurrence
    proof induction loop boundary off-by-one bug fixed tested edge case empty input overflow sorted
    merge partition pivot quick stable complexity linear logarithmic amortized stack frame recursion
    understood explained wrote notes practiced reviewed contest problem accepted wrong answer timeout
    café naïve résumé déjà vu Straße
    """.split(whereSeparator: \.isWhitespace).map(String.init)
var random = SeededGenerator(state: 2026_11_19)
let now = Date(timeIntervalSince1970: 1_795_000_000)
let sessions = (0..<20_000).map { _ -> StudySession in
    let words = (0..<Int.random(in: 30...90, using: &random)).map { _ in vocabulary.randomElement(using: &random)! }
    let module = Int.random(in: 0..<5, using: &random) == 0 ? nil : modules.randomElement(using: &random)!.id
    return StudySession(date: now.addingTimeInterval(-Double.random(in: 0...(3 * 365 * 86_400), using: &random)),
                        minutes: Int.random(in: 5...120, using: &random),
                        reflection: words.joined(separator: " "), moduleID: module)
}
let snapshot = ProgressSnapshot(sessions: sessions)
let bytes = sessions.reduce(0) { $0 + $1.reflection.utf8.count }
let lessonTitleWord = modules[3].title.split(separator: " ").first.map(String.init) ?? "Graphs"
let monthStart = now.addingTimeInterval(-30 * 86_400)
print("Dataset: \(sessions.count) sessions, \(bytes / sessions.count) reflection bytes on average (\(bytes / 1_000_000) MB in all), "
      + "\(modules.count) lessons + independent practice, 3 years of dates, seed 20261119")

struct Case { var name: String; var query: String; var moduleID: String? = nil; var since: Date? = nil; var before: Date? = nil }
let cases: [Case] = [
    Case(name: "empty query (all sessions)", query: ""),
    Case(name: "1 char \"q\"", query: "q"),
    Case(name: "prefix \"que\"", query: "que"),
    Case(name: "word \"queue\"", query: "queue"),
    Case(name: "two terms \"queue invariant\"", query: "queue invariant"),
    Case(name: "lesson title \"\(lessonTitleWord)\"", query: lessonTitleWord),
    Case(name: "diacritics \"cafe\"", query: "cafe"),
    Case(name: "no match \"zzzz\"", query: "zzzz"),
    Case(name: "\"queue\" + lesson filter", query: "queue", moduleID: modules[3].id),
    Case(name: "\"queue\" + last 30 days", query: "queue", since: monthStart, before: now.addingTimeInterval(86_400)),
]

func measure(_ runs: Int = 15, _ body: () -> Int) -> (median: Double, p95: Double, count: Int) {
    var times: [Double] = []
    var count = 0
    for _ in 0..<runs {
        let start = DispatchTime.now().uptimeNanoseconds
        count = body()
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
    times.sort()
    return (times[times.count / 2], times[min(times.count - 1, Int(Double(times.count) * 0.95))], count)
}
func row(_ label: String, _ result: (median: Double, p95: Double, count: Int)) {
    print(label.padding(toLength: 44, withPad: " ", startingAt: 0)
          + String(format: "median %7.2f ms   p95 %7.2f ms   %5d matches", result.median, result.p95, result.count))
}

/// The search as it was before the index (issue #9 baseline): filter every session, then sort.
func baselineSearch(_ search: SessionSearch) -> [StudySession] {
    let terms = search.terms
    return sessions.filter { session in
        if let moduleID = search.moduleID, (session.moduleID ?? "") != moduleID { return false }
        if let since = search.since, session.date < since { return false }
        if let before = search.before, session.date >= before { return false }
        let title = session.moduleID.flatMap { titles[$0] } ?? "Independent practice"
        let text = session.reflection + " " + title
        return terms.allSatisfy { text.localizedStandardContains($0) }
    }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
}
func search(_ item: Case) -> SessionSearch { SessionSearch(query: item.query, moduleID: item.moduleID, since: item.since, before: item.before) }
let typing = ["q", "qu", "que", "queu", "queue", "queue ", "queue i", "queue in", "queue inv", "queue inva", "queue invar"]

print("\nBefore: filter + sort the whole history on every search (the old synchronous per-keystroke path)")
for item in cases {
    row(item.name, measure {
        let found = baselineSearch(search(item))
        _ = found.reduce(0) { $0 + $1.minutes }
        return found.count
    })
}
row("typing \"queue invar\" (\(typing.count) searches, total)", measure(5) {
    typing.reduce(0) { $0 + baselineSearch(SessionSearch(query: $1)).count }
})

print("\nAfter: SessionSearchIndex, built once per saved progress")
var index = SessionSearchIndex(sessions: sessions, moduleTitles: titles)
row("build index (once per saved progress)", measure { index = SessionSearchIndex(sessions: sessions, moduleTitles: titles); return index.sessions.count })
for item in cases {
    let expected = baselineSearch(search(item))
    guard let found = index.matches(search(item)), found.sessions == expected, found.minutes == expected.reduce(0, { $0 + $1.minutes }) else {
        print("MISMATCH for \(item.name)"); exit(1)
    }
    row(item.name, measure { index.matches(search(item))?.sessions.count ?? -1 })
}
row("typing \"queue invar\" (\(typing.count) searches, total)", measure(5) {
    typing.reduce(0) { $0 + (index.matches(SessionSearch(query: $1))?.sessions.count ?? 0) }
})

// Typing into the journal search as the app now handles it: each keystroke records the text
// and reads the list for the applied text on the main actor; JournalSearchQuery searches in
// the background once typing pauses. Measured: main-actor time per keystroke, searches run,
// and the time from the last keystroke until the list shows its sessions.
func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1_000 + Double(d.components.attoseconds) / 1e15 }
@MainActor
func simulateTyping(interval: Duration, debounce: Duration) async -> (maxKeystroke: Double, searches: Int, latency: Double) {
    var kept: [String: SessionMatches] = [:]
    var searches = 0
    let query = JournalSearchQuery(debounce: debounce)
    let clock = ContinuousClock()
    var worst = Duration.zero
    var lastKeystroke = clock.now
    for (number, text) in typing.enumerated() {
        if number > 0 { try? await Task.sleep(until: lastKeystroke.advanced(by: interval), clock: clock) }
        lastKeystroke = clock.now
        query.type(text, isReady: { kept[$0] != nil }) { text in
            searches += 1
            guard let found = await index.matchesInBackground(SessionSearch(query: text)) else { return false }
            kept[text] = found
            return true
        }
        // The journal redraws and reads the list for the applied text.
        _ = query.applied.isEmpty ? index.sessions.count : (kept[query.applied]?.sessions.count ?? 0)
        worst = max(worst, clock.now - lastKeystroke)
    }
    await query.settle()
    let latency = clock.now - lastKeystroke
    return (ms(worst), searches, ms(latency))
}

print("\nTyping \"queue invar\" (\(typing.count) keystrokes) into the journal search, median of 7 runs")
print("Before: every keystroke searched synchronously on the main actor (see the per-search times above).")
for (interval, debounce) in [(Duration.milliseconds(80), Duration.milliseconds(100)), (.milliseconds(200), .milliseconds(100)), (.milliseconds(80), .zero)] {
    var runs: [(maxKeystroke: Double, searches: Int, latency: Double)] = []
    for _ in 0..<7 { runs.append(await simulateTyping(interval: interval, debounce: debounce)) }
    let latency = runs.map(\.latency).sorted()[runs.count / 2]
    let keystroke = runs.map(\.maxKeystroke).sorted()[runs.count / 2]
    let searches = runs.map(\.searches).sorted()[runs.count / 2]
    print(String(format: "keystroke every %.0f ms, debounce %.0f ms", ms(interval), ms(debounce)).padding(toLength: 44, withPad: " ", startingAt: 0)
          + String(format: "main actor ≤ %.3f ms/keystroke   %2d searches   last keystroke → results %.1f ms", keystroke, searches, latency))
}
