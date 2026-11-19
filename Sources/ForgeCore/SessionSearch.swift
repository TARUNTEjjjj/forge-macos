import Foundation
import os

/// The journal's history list for one search: the matching sessions, newest first,
/// and the minutes they add up to.
public struct SessionMatches: Equatable, Sendable {
    public var sessions: [StudySession]
    public var minutes: Int

    public init(sessions: [StudySession] = [], minutes: Int = 0) {
        self.sessions = sessions
        self.minutes = minutes
    }
}

/// One journal search: words to find in a reflection or its lesson title, an optional
/// lesson ("" is independent practice), and half-open date bounds.
public struct SessionSearch: Hashable, Sendable {
    public var query: String
    public var moduleID: String?
    public var since: Date?
    public var before: Date?

    public init(query: String = "", moduleID: String? = nil, since: Date? = nil, before: Date? = nil) {
        self.query = query
        self.moduleID = moduleID
        self.since = since
        self.before = before
    }

    /// The words every match must contain. Searches with the same words find the same sessions.
    public var terms: [String] { query.split(whereSeparator: \.isWhitespace).map(String.init) }
}

/// Saved sessions prepared once for searching: sorted newest first, with each session's
/// lesson title looked up once. A search then only matches text, so typing never re-sorts
/// the history, and lesson titles are matched once per title instead of once per session.
/// Matching is the same as `ProgressSnapshot.filteredSessions`: every word must appear,
/// ignoring case and diacritics, in the reflection or the lesson title.
public struct SessionSearchIndex: Sendable {
    /// Every session, newest first; equal dates are ordered by ID so the order is stable.
    public let sessions: [StudySession]
    /// Each session's title, as an index into `titles`.
    private let titleSlots: [Int]
    private let titles: [String]
    private let lessonIDs: [String]
    private let totalMinutes: Int

    public init(sessions: [StudySession], moduleTitles: [String: String] = [:]) {
        // Sorting positions instead of sessions avoids moving every session's strings around.
        let order = sessions.indices.sorted { a, b in
            let left = sessions[a], right = sessions[b]
            return left.date == right.date ? left.id.uuidString < right.id.uuidString : left.date > right.date
        }
        let sorted = order.map { sessions[$0] }
        var slotByTitle: [String: Int] = [:]
        var titles: [String] = []
        self.titleSlots = sorted.map { session in
            let title = session.moduleID.flatMap { moduleTitles[$0] } ?? "Independent practice"
            if let slot = slotByTitle[title] { return slot }
            titles.append(title)
            slotByTitle[title] = titles.count - 1
            return titles.count - 1
        }
        self.sessions = sorted
        self.titles = titles
        self.lessonIDs = sorted.map { $0.moduleID ?? "" }
        self.totalMinutes = sorted.reduce(0) { $0 + $1.minutes }
    }

    /// The sessions that match `search`, or nil when `isCancelled` reports true first.
    /// Long histories are matched on several cores, and cancellation is checked between
    /// blocks of sessions, so an abandoned search stops early.
    public func matches(_ search: SessionSearch, isCancelled: @Sendable () -> Bool = { false }) -> SessionMatches? {
        let terms = search.terms
        let range = dateRange(since: search.since, before: search.before)
        if terms.isEmpty, search.moduleID == nil {
            if range == sessions.indices { return SessionMatches(sessions: sessions, minutes: totalMinutes) }
            let found = Array(sessions[range])
            return SessionMatches(sessions: found, minutes: found.reduce(0) { $0 + $1.minutes })
        }
        // `localizedStandardContains` with the current locale, fixed for this search: the
        // auto-updating current locale serializes concurrent searches, a fixed copy doesn't.
        let locale = Locale(identifier: Locale.current.identifier)
        @Sendable func contains(_ text: String, _ term: String) -> Bool {
            text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
        }
        // Whether each word is in each lesson title, found once per title.
        let titleHas = terms.map { term in titles.map { contains($0, term) } }
        let moduleID = search.moduleID
        @Sendable func isMatch(_ index: Int) -> Bool {
            if let moduleID, lessonIDs[index] != moduleID { return false }
            let slot = titleSlots[index]
            for (word, term) in terms.enumerated() where !titleHas[word][slot] {
                if !contains(sessions[index].reflection, term) { return false }
            }
            return true
        }

        let blockSize = 512
        let blocks = (range.count + blockSize - 1) / blockSize
        var found: [[Int]] = Array(repeating: [], count: blocks)
        let stopped = OSAllocatedUnfairLock(initialState: false)
        // Only text matching is worth spreading over cores; a lesson filter alone is cheap.
        let parallel = !terms.isEmpty && blocks > 1
        found.withUnsafeMutableBufferPointer { results in
            let results = UnsafeSendable(results)
            @Sendable func work(_ block: Int) {
                if stopped.withLock({ $0 }) { return }
                if isCancelled() { stopped.withLock { $0 = true }; return }
                let start = range.lowerBound + block * blockSize
                results.value[block] = (start..<min(start + blockSize, range.upperBound)).filter(isMatch)
            }
            if parallel { DispatchQueue.concurrentPerform(iterations: blocks) { work($0) } }
            else { (0..<blocks).forEach(work) }
        }
        if stopped.withLock({ $0 }) || isCancelled() { return nil }
        var minutes = 0
        let matched = found.flatMap { $0 }.map { index -> StudySession in
            minutes += sessions[index].minutes
            return sessions[index]
        }
        return SessionMatches(sessions: matched, minutes: minutes)
    }

    /// `matches(_:)` away from the caller's actor. Cancelling the calling task stops the
    /// search, and a cancelled search returns nil instead of a partial list.
    public func matchesInBackground(_ search: SessionSearch) async -> SessionMatches? {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        let index = self
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                index.matches(search) { cancelled.withLock { $0 } }
            }.value
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    /// Positions of the sessions dated within `since..<before`; the history is newest first.
    private func dateRange(since: Date?, before: Date?) -> Range<Int> {
        // The first position dated before `date`; every later session is older still.
        func firstOlder(than date: Date) -> Int {
            var low = 0, high = sessions.count
            while low < high {
                let middle = (low + high) / 2
                if sessions[middle].date < date { high = middle } else { low = middle + 1 }
            }
            return low
        }
        let start = before.map(firstOlder) ?? 0
        let end = since.map(firstOlder) ?? sessions.count
        return start..<max(start, end)
    }
}

/// Lets concurrent blocks write their own, separate elements of one buffer.
private struct UnsafeSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
