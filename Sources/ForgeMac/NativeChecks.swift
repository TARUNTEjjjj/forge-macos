import AppKit
import Foundation
import SwiftUI
import ForgeCore

/// Headless regressions for the shared editor state; no user data is touched.
@MainActor
enum NativeChecks {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw Failure(message) }
    }
    /// Lays out the journal without a window and reports whether its focus
    /// field accepts input, or nil when the field is missing.
    static func focusFieldEnabled(_ model: AppModel) -> Bool? {
        focusField(in: host(JournalView(), for: model))?.isEnabled
    }
    /// Lays out a screen without a window, as a Forge window shows it.
    static func host(_ screen: some View, for model: AppModel) -> NSView {
        let host = NSHostingView(rootView: screen.environmentObject(model))
        host.frame = NSRect(x: 0, y: 0, width: 1_100, height: 900)
        host.layoutSubtreeIfNeeded()
        return host
    }
    /// The journal's focus field, or nil when it is missing.
    static func focusField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.placeholderString?.hasPrefix("For example: implement BFS") == true { return field }
        return view.subviews.lazy.compactMap(focusField).first
    }
    /// The pixels of a primary-style button, as the app draws it in dark mode.
    static func primaryButtonPixels(disabled: Bool) -> Data? {
        let button = Button("Save study session") {}.buttonStyle(PrimaryButtonStyle()).disabled(disabled)
        return ImageRenderer(content: button.environment(\.colorScheme, .dark)).cgImage?.dataProvider?.data as Data?
    }
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Forge-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let model = AppModel(progressURL: url, refreshCatalogOnLaunch: false)
        guard let catalog = model.curriculum, let lesson = catalog.modules.first else { throw Failure("Curriculum load failed") }
        try require(!model.readOnly, "Fresh store should be writable")
        model.noteDrafts[lesson.id] = "Invariant: the queue contains discovered, unprocessed vertices."
        model.destination = .journal
        model.openModule(lesson.id)
        try require(model.noteDrafts[lesson.id]?.hasPrefix("Invariant:") == true, "Navigation lost the note draft")
        try require(model.flushNotes(), "Pending note could not flush before backup")
        let reopened = AppModel(progressURL: url, refreshCatalogOnLaunch: false)
        try require(reopened.progress.notes[lesson.id] == model.noteDrafts[lesson.id], "Flushed draft did not survive restart")
        print("PASS shared draft survives navigation and restart")

        let before = try Data(contentsOf: url)
        model.noteDrafts[lesson.id] = String(repeating: "x", count: 20_001)
        try require(!model.flushNotes(), "Oversized draft unexpectedly saved")
        let after = try Data(contentsOf: url)
        try require(before == after, "Failed save altered the existing progress file")
        try require(model.noteDrafts[lesson.id]?.count == 20_001, "Failed save discarded the draft")
        print("PASS failed save retains draft and preserves disk")

        // One note over the limit must not block a backup of saved progress or hold back
        // the other drafts, and the learner is told which lesson's draft was left out.
        let store = ProgressFileStore(fileURL: url, allowedModuleIDs: catalog.moduleIDs)
        let other = catalog.modules[1]
        model.noteDrafts[other.id] = "Saved with the backup"
        guard let backup = try model.backupData() else { throw Failure("An oversized draft blocked the backup") }
        try require(model.message == nil, "An oversized draft raised a save error")
        let backedUp = try store.importData(backup)
        try require(backedUp == model.progress && backedUp.notes[other.id] == "Saved with the backup", "Backup left out saved progress")
        try require(model.noteDrafts[lesson.id]?.count == 20_001, "Backup discarded the oversized draft")
        try require(model.backupOmissionNote?.contains("“\(lesson.title)”") == true && model.backupOmissionNote?.contains(other.title) == false,
                    "Backup did not name the unsaved draft")
        print("PASS an oversized note draft doesn't block a backup of saved progress")

        // Restore keeps text the learner hasn't saved, which the recovery copy can't
        // hold, and moves every other draft to the restored progress so that no later
        // save writes stale text over it.
        model.sessionReflectionDraft = "Unsaved reflection"
        try require(model.restoreConfirmationText.contains("Unsaved drafts stay"), "Restore didn't say unsaved drafts are kept")
        let restored = ProgressSnapshot(notes: [lesson.id: "Restored note", other.id: "Restored second note"], dailyFocus: "Test the boundary")
        model.backupCandidate = try store.exportData(restored)
        model.confirmRestore()
        try require(model.noteDrafts[other.id] == "Restored second note", "Restore left stale editor text")
        try require(model.focusDraft == "Test the boundary", "Restore left stale focus text")
        try require(model.noteDrafts[lesson.id]?.count == 20_001 && model.sessionReflectionDraft == "Unsaved reflection",
                    "Restore discarded unsaved drafts")
        model.focusDraft = "Unsaved focus"
        model.backupCandidate = try store.exportData(restored)
        model.confirmRestore()
        try require(model.focusDraft == "Unsaved focus", "Restore discarded an unsaved focus")
        try require(!model.flushNotes(), "Oversized draft unexpectedly saved")
        let disk = try store.load()
        try require(disk.notes == restored.notes, "Draft flush overwrote restored notes")
        model.noteDrafts[lesson.id] = "Restored note"
        model.focusDraft = "Test the boundary"
        model.sessionReflectionDraft = ""
        print("PASS restore keeps unsaved drafts and replaces the others before further saves")
        try require(LabBrowser.permitsFrame(URL(string: "about:srcdoc")!, isMainFrame: false), "Sandbox runner child frame was blocked")
        try require(!LabBrowser.permitsFrame(URL(string: "about:srcdoc")!, isMainFrame: true), "Top-level srcdoc was allowed")
        try require(!LabBrowser.permitsFrame(URL(string: "https://example.com/")!, isMainFrame: false), "Untrusted embedded navigation was allowed")
        try require(!LabBrowser.permitsFrame(URL(string: "javascript:alert(1)")!, isMainFrame: true), "Script navigation was allowed")
        print("PASS sandbox runner frame allowed with external navigation blocked")

        // The lab page keeps some work only in memory, such as a running focus timer. Opening
        // the section already showing must not reload it, and a link meant for a new window
        // must not replace it. A page that stopped or never loaded must still load.
        let shown = URL(string: "\(LabBrowser.home)#git")!
        try require(!LabBrowser.needsLoad(shown, shown: shown, pageIsBroken: false), "Opening the section already showing reloaded the lab page")
        try require(LabBrowser.needsLoad(URL(string: "\(LabBrowser.home)#practice")!, shown: shown, pageIsBroken: false), "Another lab section did not open")
        try require(LabBrowser.needsLoad(shown, shown: shown, pageIsBroken: true), "A stopped lab page was not loaded again")
        try require(LabBrowser.needsLoad(shown, shown: nil, pageIsBroken: false), "A lab page that didn't load was not retried")
        try require(LabBrowser.opensInBrowser(newWindow: URL(string: "\(LabBrowser.home)curriculum-guide.html")!), "A new-window link to the labs site replaced the lab page")
        try require(LabBrowser.opensInBrowser(newWindow: URL(string: "https://docs.python.org/3/")!), "A new-window link to another site stayed in the app")
        try require(!LabBrowser.opensInBrowser(newWindow: URL(string: "javascript:alert(1)")!), "A script new-window request was opened")
        print("PASS labs keep the page that is showing")

        // WebKit stops a load with "Frame load interrupted" (WebKitErrorDomain 102) when the
        // app turns the response into a download or opens a redirect in the browser. Neither
        // is a failure, so neither may raise "Forge labs could not load".
        try require(!LabBrowser.reportsFailure(NSError(domain: "WebKitErrorDomain", code: 102)), "A download or browser redirect was reported as a failed load")
        try require(!LabBrowser.reportsFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)), "A cancelled load was reported as a failure")
        try require(LabBrowser.reportsFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)), "An offline load was not reported")
        try require(LabBrowser.reportsFailure(NSError(domain: "WebKitErrorDomain", code: 101)), "A page WebKit can't show was not reported")
        print("PASS labs report only loads that failed")

        let fresh = AppModel(progressURL: directory.appendingPathComponent("fresh/progress.json"), refreshCatalogOnLaunch: false)
        try require(!fresh.restoreConfirmationText.contains("recovery copy"), "Restore promised a copy with nothing to copy")
        fresh.backupCandidate = try store.exportData(restored)
        fresh.confirmRestore()
        try require(fresh.message == "Backup restored." && fresh.recoveryCopies.isEmpty, "Restore without saved data reported a copy")
        try require(model.restoreConfirmationText.contains("recovery copy"), "Restore over saved data did not promise a copy")
        let replaced = try Data(contentsOf: url)
        let earlierCopies = Set(model.recoveryCopies)
        model.backupCandidate = try store.exportData(ProgressSnapshot(dailyFocus: "Older backup"))
        model.confirmRestore()
        let newCopies = Set(model.recoveryCopies).subtracting(earlierCopies)
        guard newCopies.count == 1, let copy = newCopies.first else { throw Failure("Restore did not list its recovery copy") }
        try require(model.message?.contains(copy.lastPathComponent) == true, "Restore message did not name its recovery copy")
        let copied = try Data(contentsOf: copy)
        try require(copied == replaced, "Recovery copy does not hold the replaced progress")
        print("PASS restore names its recovery copy and promises one only when it is made")

        let otherURL = directory.appendingPathComponent("other-version/progress.json")
        try FileManager.default.createDirectory(at: otherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {"version": 1, "completedModuleIDs": ["\(lesson.id)", "retired-lesson"], "notes": {"retired-lesson": "Still mine"},
         "dailyFocus": "", "streakGoal": 30, "sessions": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
         "date": "2026-11-01T10:00:00Z", "minutes": 25, "reflection": "Old lesson", "moduleID": "retired-lesson", "tags": ["bfs"]}]}
        """.utf8).write(to: otherURL)
        let upgraded = AppModel(progressURL: otherURL, refreshCatalogOnLaunch: false)
        try require(!upgraded.readOnly, "Progress naming a retired lesson opened read-only")
        try require(upgraded.reviewedModuleCount == 1, "A retired lesson counted as reviewed")
        upgraded.markComplete(catalog.modules[1].id, completed: true)
        let kept = AppModel(progressURL: otherURL, refreshCatalogOnLaunch: false).progress
        try require(kept.completedModuleIDs == [lesson.id, catalog.modules[1].id, "retired-lesson"], "Saving lost a retired lesson")
        try require(kept.notes["retired-lesson"] == "Still mine" && kept.sessions.first?.moduleID == "retired-lesson", "Saving lost retired lesson data")
        let written = try String(contentsOf: otherURL, encoding: .utf8)
        try require(written.contains("\"streakGoal\"") && written.contains("\"tags\""), "Saving dropped fields from another Forge version")
        print("PASS progress from another curriculum or Forge version stays writable and intact")

        // Two Forge windows or copies of the app can share one progress file. A window
        // that loaded older progress must add its changes to what the other saved, and
        // must not write its older drafts back over newer notes.
        let sharedURL = directory.appendingPathComponent("two-windows/progress.json")
        let first = AppModel(progressURL: sharedURL, refreshCatalogOnLaunch: false)
        first.noteDrafts[lesson.id] = "First note"
        try require(first.flushNotes(), "First window could not save its note")
        let behind = AppModel(progressURL: sharedURL, refreshCatalogOnLaunch: false)
        first.noteDrafts[lesson.id] = "Newer note"
        try require(first.flushNotes() && first.update { $0.sessions.append(StudySession(minutes: 90, reflection: "BFS proof")) },
                    "First window could not save newer work")
        behind.noteDrafts[other.id] = "Typed in the window that fell behind"
        try require(behind.flushNotes(), "The window that fell behind could not save its note")
        behind.markComplete(other.id, completed: true)
        let relaunched = AppModel(progressURL: sharedURL, refreshCatalogOnLaunch: false).progress
        try require(relaunched.sessions.map(\.reflection) == ["BFS proof"] && relaunched.completedModuleIDs == [other.id]
                    && relaunched.notes == [lesson.id: "Newer note", other.id: "Typed in the window that fell behind"],
                    "A window with older progress erased newer work")
        try require(behind.message == nil && behind.progress == relaunched && behind.noteDrafts[lesson.id] == "Newer note",
                    "The window that fell behind kept showing older progress")
        try require(first.update { $0.sessions.append(StudySession(minutes: 30, reflection: "Graph quiz")) }, "First window could not save again")
        guard let behindBackup = try behind.backupData() else { throw Failure("Backup was blocked") }
        let behindSessions = try store.importData(behindBackup).sessions
        try require(behindSessions.count == 2, "A backup from the window that fell behind left out newer work")
        print("PASS a window with older progress adds its changes to newer saved progress")

        // A copy that fell behind shows the other copy's newer note and focus as soon as the
        // learner switches to it, so an edit there builds on that text instead of replacing it.
        let switchURL = directory.appendingPathComponent("switching/progress.json")
        let copyA = AppModel(progressURL: switchURL, refreshCatalogOnLaunch: false)
        copyA.noteDrafts[lesson.id] = "First version"
        try require(copyA.flushNotes(), "The first copy could not save its note")
        let copyB = AppModel(progressURL: switchURL, refreshCatalogOnLaunch: false)
        copyA.noteDrafts[lesson.id] = "Rewritten in the other copy"
        copyA.focusDraft = "Focus saved in the other copy"
        try require(copyA.flushNotes() && copyA.update { $0.dailyFocus = copyA.focusDraft }, "The first copy could not save newer text")
        copyB.noteDrafts[other.id] = "Unsaved text typed in this copy"
        let lifecycle = ForgeLifecycle()
        lifecycle.model = copyB
        lifecycle.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        try require(copyB.noteDrafts[lesson.id] == "Rewritten in the other copy" && copyB.focusDraft == "Focus saved in the other copy",
                    "A copy that fell behind kept showing older text after the learner switched to it")
        try require(copyB.noteDrafts[other.id] == "Unsaved text typed in this copy" && copyB.message == nil,
                    "Switching to a copy discarded its unsaved text")
        copyB.noteDrafts[lesson.id]? += "\nOne line typed in this copy"
        try require(copyB.flushNotes(), "The copy that fell behind could not save its notes")
        let switched = AppModel(progressURL: switchURL, refreshCatalogOnLaunch: false).progress
        try require(switched.notes == [lesson.id: "Rewritten in the other copy\nOne line typed in this copy", other.id: "Unsaved text typed in this copy"]
                    && switched.dailyFocus == "Focus saved in the other copy",
                    "An edit in a copy that fell behind replaced the other copy's newer text")
        print("PASS a copy that fell behind shows newer saved progress when the learner switches to it")

        // Lessons can be reviewed in any order. The overview map must mark the
        // chapters actually reviewed, and its current chapter must hold Up Next.
        let mapURL = directory.appendingPathComponent("map/progress.json")
        let learner = AppModel(progressURL: mapURL, refreshCatalogOnLaunch: false)
        let chapters = catalog.phases, last = chapters.count - 1
        func requireMap(_ model: AppModel, _ marked: [Int: ChapterStatus], _ situation: String) throws {
            var expected = Array(repeating: ChapterStatus.upcoming, count: chapters.count)
            for (index, status) in marked { expected[index] = status }
            let upNext = model.nextModule.flatMap { next in chapters.firstIndex { $0.modules.contains { $0.id == next.id } } }
            try require(model.chapterStatuses == expected, "\(situation): map drew \(model.chapterStatuses.map(\.rawValue))")
            try require(model.chapterStatuses.firstIndex(of: .current) == upNext, "\(situation): current chapter is not the Up Next chapter")
        }
        try requireMap(learner, [0: .current], "Fresh start")
        chapters[0].modules.forEach { learner.markComplete($0.id, completed: true) }
        try requireMap(learner, [0: .complete, 1: .current], "Chapter 1 reviewed")
        chapters[last].modules.forEach { learner.markComplete($0.id, completed: true) }
        try requireMap(learner, [0: .complete, 1: .current, last: .complete], "Final chapter reviewed early")
        try requireMap(AppModel(progressURL: mapURL, refreshCatalogOnLaunch: false), [0: .complete, 1: .current, last: .complete], "Final chapter after restart")
        learner.markComplete(chapters[0].modules[0].id, completed: false)
        try requireMap(learner, [0: .current, last: .complete], "First lesson reopened")
        catalog.modules.forEach { learner.markComplete($0.id, completed: true) }
        try require(learner.chapterStatuses == Array(repeating: .complete, count: chapters.count) && learner.nextModule == nil, "Finished path still shows a current chapter")
        print("PASS overview map shows the chapters actually reviewed")

        // A damaged progress file opens read-only, so the journal's focus field
        // must refuse text that can never be saved, like the other editors.
        let damagedURL = directory.appendingPathComponent("damaged/progress.json")
        try FileManager.default.createDirectory(at: damagedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"version\":1".utf8).write(to: damagedURL)
        let damaged = AppModel(progressURL: damagedURL, refreshCatalogOnLaunch: false)
        try require(damaged.readOnly, "Damaged progress did not open read-only")
        try require(focusFieldEnabled(model) == true, "Writable journal focus field is missing or disabled")
        try require(focusFieldEnabled(damaged) == false, "Read-only journal focus field accepts text it cannot save")
        print("PASS read-only journal focus field refuses unsaveable text")

        // Save buttons stay disabled until their text can be saved, such as a session with
        // no reflection yet. A disabled one must not look like the bright red button that saves.
        guard let enabledButton = primaryButtonPixels(disabled: false), let disabledButton = primaryButtonPixels(disabled: true)
        else { throw Failure("Could not draw a primary button") }
        try require(enabledButton != disabledButton, "A disabled save button looks the same as one that saves")
        print("PASS disabled save buttons look disabled")

        // Session lengths step by 5 minutes down to a 1-minute floor, which is off that grid,
        // so a press up from it must land on 5 again, not on 6, 11, 16 and so on.
        var minutes = 25, lengths: [Int] = []
        while let shorter = JournalView.sessionMinutes(after: minutes, longer: false) { minutes = shorter; lengths.append(minutes) }
        try require(lengths == [20, 15, 10, 5, 1], "Shortening a 25-minute session gave \(lengths)")
        lengths = []
        while lengths.count < 6, let longer = JournalView.sessionMinutes(after: minutes, longer: true) { minutes = longer; lengths.append(minutes) }
        try require(lengths == [5, 10, 15, 20, 25, 30], "Lengthening a 1-minute session gave \(lengths)")
        try require(JournalView.sessionMinutes(after: 26, longer: true) == 30 && JournalView.sessionMinutes(after: 26, longer: false) == 25,
                    "An off-step session length didn't return to the 5-minute steps")
        try require(JournalView.sessionMinutes(after: 715, longer: true) == 720 && JournalView.sessionMinutes(after: 720, longer: true) == nil,
                    "Session length passed the 720-minute limit")
        print("PASS session lengths stay on 5-minute steps")

        // Every keystroke in a journal editor redraws the journal, and an overview in another
        // window, so the redraws must reuse the daily totals and the matching sessions, which
        // only new saved progress or another search replaces.
        let journalURL = directory.appendingPathComponent("journal/progress.json")
        let now = Date()
        let older = StudySession(date: now.addingTimeInterval(-3 * 86_400), minutes: 40, reflection: "Earlier", moduleID: other.id)
        let newer = StudySession(date: now, minutes: 25, reflection: "Today")
        try ProgressFileStore(fileURL: journalURL, allowedModuleIDs: catalog.moduleIDs).save(ProgressSnapshot(sessions: [newer, older]))
        let journal = AppModel(progressURL: journalURL, refreshCatalogOnLaunch: false)
        let journalView = host(JournalView(), for: journal)
        let journalComputed = journal.historyComputations
        try require(journalComputed >= 2, "The journal doesn't read its matching sessions and daily totals from the model")
        let overview = host(DashboardView(), for: journal)
        let computed = journal.historyComputations
        try require(computed > journalComputed, "The overview doesn't read today's practice from the model")
        guard let typed = focusField(in: journalView) else { throw Failure("Journal focus field is missing") }
        for text in ["B", "BF", "BFS"] {
            journal.focusDraft = text
            journal.sessionReflectionDraft += text
            // The field shows the draft once the journal has redrawn, as the app's run loop would.
            for _ in 0..<50 where typed.stringValue != text {
                journalView.layoutSubtreeIfNeeded()
                if typed.stringValue != text { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            }
            overview.layoutSubtreeIfNeeded()
            try require(typed.stringValue == text, "The journal didn't redraw for typed text")
        }
        try require(journal.historyComputations == computed, "Typing in the journal recomputed the whole history")
        // Saved dates keep whole seconds, so sessions are compared by ID.
        func found(query: String = "", moduleID: String? = nil, since: Date? = nil, before: Date? = nil) -> [UUID] {
            journal.matchingSessions(query: query, moduleID: moduleID, since: since, before: before).sessions.map(\.id)
        }
        // With no search typed, the journal lists every session, newest first.
        let all = [newer.id, older.id]
        try require(found() == all && journal.matchingSessions().minutes == 65, "Recent sessions are not newest first")
        try require(journal.historyComputations == computed, "The journal's own search was computed again")
        // Another search is another list, found as the store finds it: by reflection text, by
        // the title of the session's lesson, by lesson, and by date. Each is asked for while the
        // journal's own search is kept, so no search may be answered with another's sessions.
        let titles = Dictionary(uniqueKeysWithValues: catalog.modules.map { ($0.id, $0.title) })
        let today = Calendar.current.startOfDay(for: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
        try require(found(query: "earlier") == [older.id] && journal.matchingSessions(query: "earlier").minutes == 40,
                    "A search by reflection found other sessions")
        try require(journal.historyComputations == computed + 1, "A search was not computed once and then reused")
        try require(found() == all && found(query: other.title) == [older.id], "A search by lesson title missed its session")
        try require(found() == all && found(moduleID: "") == [newer.id] && found() == all && found(moduleID: other.id) == [older.id],
                    "The lesson filter showed another lesson's sessions")
        try require(found() == all && found(since: today, before: tomorrow) == [newer.id]
                    && journal.matchingSessions(since: today, before: tomorrow).minutes == 25, "The date range showed sessions outside it")
        // More searches than the model keeps at once still give each search its own sessions.
        for query in ["a", "b", "c", "d", "e", "f"] {
            try require(found() == all && journal.matchingSessions(query: query).sessions == journal.progress.filteredSessions(query: query, moduleTitles: titles),
                        "A search for “\(query)” showed another search's sessions")
        }
        try require(found() == all && found(query: "earlier") == [older.id], "An earlier search came back with other sessions")
        try require(journal.update { $0.sessions.append(StudySession(date: now.addingTimeInterval(60), minutes: 5, reflection: "Later")) },
                    "Journal could not save a session")
        try require(journal.matchingSessions().sessions.map(\.reflection) == ["Later", "Today", "Earlier"] && journal.matchingSessions().minutes == 70,
                    "Recent sessions missed a new session")
        try require(found(query: "earlier") == [older.id] && journal.matchingSessions(query: "later").minutes == 5, "A search missed a new session")
        let week = (-6...0).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }
        try require(journal.minutes(on: week) == journal.progress.minutes(on: week) && journal.minutes(on: [now]) == journal.progress.minutes(on: [now]),
                    "Daily totals missed a new session")
        print("PASS journal typing reuses history totals that new sessions replace")
        print("16/16 native regression checks passed")
    }
}

// Explicit continuations let these checks advance a refresh without waiting for a
// real timer or making a network request. The loader deliberately ignores task
// cancellation so a late response exercises the model's cancellation guard.
private actor ResourceRefreshLoader {
    private(set) var requestCount = 0
    private(set) var deliveredCount = 0
    private var pending: [Int: CheckedContinuation<ResourceCatalog, Error>] = [:]

    func load() async throws -> ResourceCatalog {
        requestCount += 1
        let request = requestCount
        let result: ResourceCatalog = try await withCheckedThrowingContinuation { pending[request] = $0 }
        deliveredCount += 1
        return result
    }

    func succeed(_ catalog: ResourceCatalog, request: Int) {
        pending.removeValue(forKey: request)?.resume(returning: catalog)
    }

    func fail(request: Int) { pending.removeValue(forKey: request)?.resume(throwing: URLError(.notConnectedToInternet)) }
    func cancelAll() {
        let outstanding = pending.values
        pending.removeAll()
        for continuation in outstanding { continuation.resume(throwing: CancellationError()) }
    }
}

private actor ResourceRefreshSleeper {
    private var pending: [(UUID, CheckedContinuation<Void, Error>)] = []
    private(set) var durations: [Duration] = []
    var pendingCount: Int { pending.count }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        durations.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { pending.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func wakeNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().1.resume()
    }

    private func cancel(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.0 == id }) else { return }
        pending.remove(at: index).1.resume(throwing: CancellationError())
    }

    func cancelAll() {
        let outstanding = pending
        pending.removeAll()
        for (_, continuation) in outstanding { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
private final class ResourceRefreshFixture {
    var now = Date(timeIntervalSince1970: 2_000_000_000)
    let loader = ResourceRefreshLoader()
    let sleeper = ResourceRefreshSleeper()
    let directory: URL
    var catalogURL: URL { directory.appendingPathComponent("catalog.json") }
    var progressURL: URL { directory.appendingPathComponent("progress.json") }
    private var models: [AppModel] = []

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Forge-resource-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func model(automatic: Bool = true, catalogURL: URL? = nil,
               interval: TimeInterval = 900, realSleep: Bool = false) -> AppModel {
        let loader = self.loader, sleeper = self.sleeper
        let model = AppModel(
            progressURL: progressURL, refreshCatalogOnLaunch: automatic,
            resourceCatalogURL: catalogURL ?? self.catalogURL, resourceRefreshInterval: interval,
            resourceNow: { [unowned self] in self.now },
            resourceSleep: { duration in
                if realSleep { try await Task.sleep(for: duration) }
                else { try await sleeper.sleep(duration) }
            },
            resourceLoader: { try await loader.load() }
        )
        models.append(model)
        return model
    }

    func close() {
        models.forEach { $0.stopResourceCatalogRefresh() }
        let loader = self.loader, sleeper = self.sleeper
        Task { await loader.cancelAll(); await sleeper.cancelAll() }
        try? FileManager.default.removeItem(at: directory)
    }
}

extension NativeChecks {
    private static func resourceSnapshot(_ title: String, day: Int) throws -> ResourceCatalog {
        let bundle = try ResourceCatalog.loadBundled()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bundle)) as! [String: Any]
        object["title"] = title
        object["fetchedAt"] = String(format: "2030-01-%02dT00:00:00Z", day)
        return try ResourceCatalog.decode(JSONSerialization.data(withJSONObject: object))
    }

    private static func eventually(_ message: String, _ predicate: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await predicate()) {
            if ContinuousClock.now >= deadline { throw Failure(message) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    static func runResourceRefresh() async throws {
        try await checkAutomaticResourceRefresh()
        try await checkOfflineResourceRestart()
        try await checkCorruptResourceCache()
        try await checkResourceSaveFailure()
        try await checkResourceCancellation()
        try await checkOlderResourceResponse()
        try await checkNewerResourceSavedDuringDownload()
        try await checkResourceRetry()
        try await checkResourceClockAdjustment()
        try await checkRealResourceTimer()
        print("10/10 native resource refresh checks passed")
    }

    private static func checkAutomaticResourceRefresh() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        try await eventually("Launch did not request the catalog") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("First download", day: 2), request: 1)
        try await eventually("Launch refresh did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "First download", "Launch response was not displayed")
        try require(model.resourceCatalogSavedOffline, "A downloaded catalog was not saved offline")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Successful check time is missing")
        try require(model.resourceCatalogNextRefreshAt == fixture.now.addingTimeInterval(900), "Next automatic check has the wrong deadline")
        try await eventually("No automatic refresh timer was armed") { await fixture.sleeper.pendingCount == 1 }
        let originalDeadline = model.resourceCatalogNextRefreshAt
        fixture.now.addTimeInterval(450)
        model.refreshResourceCatalogIfDue()
        try await eventually("Activation did not preserve a remaining timer") {
            let durations = await fixture.sleeper.durations
            let pending = await fixture.sleeper.pendingCount
            return durations.count == 2 && durations.last == .seconds(450) && pending == 1
        }
        let requestsBeforeDue = await fixture.loader.requestCount
        try require(requestsBeforeDue == 1 && model.resourceCatalogNextRefreshAt == originalDeadline, "Activation downloaded early or reset the refresh deadline")
        fixture.now.addTimeInterval(450)
        await fixture.sleeper.wakeNext()
        try await eventually("The timer did not refresh without a manual action") { await fixture.loader.requestCount == 2 }
        model.refreshResourceCatalog()
        model.refreshResourceCatalogIfDue()
        for _ in 0..<10 { await Task.yield() }
        let requests = await fixture.loader.requestCount
        try require(requests == 2, "Overlapping manual and due requests started duplicate downloads")
        await fixture.loader.succeed(try resourceSnapshot("Automatic update", day: 3), request: 2)
        try await eventually("Automatic refresh did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "Automatic update", "Automatic update was not displayed")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Automatic check did not advance its timestamp")
        print("PASS launch and periodic refresh run automatically; manual/due requests coalesce")
    }

    private static func checkOfflineResourceRestart() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let downloaded = try resourceSnapshot("Saved before restart", day: 5)
        _ = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).save(downloaded)
        let before = try Data(contentsOf: fixture.catalogURL)
        let model = fixture.model()
        try require(model.resourceCatalog?.title == downloaded.title, "Restart did not immediately open the latest saved catalog")
        try require(model.resourceCatalogSavedOffline, "Restart did not identify its saved offline snapshot")
        try await eventually("Restart did not try a refresh") { await fixture.loader.requestCount == 1 }
        await fixture.loader.fail(request: 1)
        try await eventually("Offline refresh did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == downloaded.title, "Network failure discarded the saved snapshot")
        try require(model.resourceCatalogRefreshNotice != nil, "Offline fallback did not explain the refresh failure")
        try require(model.resourceCatalogLastCheckedAt == nil, "Failed request claimed a successful metadata check")
        try require(!model.readOnly && model.message == nil, "Resource failure affected the learning progress store")
        let after = try Data(contentsOf: fixture.catalogURL)
        try require(before == after, "Offline startup changed the valid cache")
        print("PASS restart opens the last saved catalog and preserves it when offline")
    }

    private static func checkCorruptResourceCache() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let corrupt = Data("{broken catalog".utf8)
        try corrupt.write(to: fixture.catalogURL)
        let model = fixture.model(automatic: false)
        try require(model.resourceCatalog != nil, "Corrupt cache hid the bundled library")
        try require(model.resourceCatalogOrigin.localizedCaseInsensitiveContains("bundled"), "Corrupt cache was represented as a usable saved catalog")
        try require(!model.resourceCatalogSavedOffline, "Corrupt cache was reported as saved offline data")
        try require(model.resourceCatalogRefreshNotice != nil, "Corrupt cache did not produce a recovery notice")
        try require(!model.readOnly && model.message == nil, "Corrupt resource cache disabled progress saving")
        let preserved = try Data(contentsOf: fixture.catalogURL)
        try require(preserved == corrupt, "Opening the app changed a corrupt cache before a verified replacement")
        model.refreshResourceCatalog()
        try await eventually("Manual recovery did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Recovered catalog", day: 6), request: 1)
        try await eventually("Manual recovery did not complete") { !model.isRefreshingResourceCatalog }
        let repaired = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).load()
        try require(repaired?.title == "Recovered catalog" && model.resourceCatalogSavedOffline, "Verified response did not repair the corrupt cache")
        try require(model.resourceCatalogRefreshNotice == nil, "Successful recovery left a stale warning")
        print("PASS corrupt cache falls back honestly and a verified refresh repairs it")
    }

    private static func checkResourceSaveFailure() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let blockedParent = fixture.directory.appendingPathComponent("not-a-directory")
        try Data("keep me".utf8).write(to: blockedParent)
        let blockedURL = blockedParent.appendingPathComponent("catalog.json")
        let model = fixture.model(automatic: false, catalogURL: blockedURL)
        try require(model.update { $0.dailyFocus = "Progress remains independent" }, "Could not write isolated test progress")
        let progressBefore = try Data(contentsOf: fixture.progressURL)
        model.refreshResourceCatalog()
        try await eventually("Save-failure refresh did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Session only", day: 7), request: 1)
        try await eventually("Save-failure refresh did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "Session only", "Disk failure discarded usable downloaded data")
        try require(!model.resourceCatalogSavedOffline, "Disk failure incorrectly promised offline availability")
        try require(model.resourceCatalogRefreshNotice != nil, "Disk failure was not disclosed")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Valid download lost its successful-check timestamp")
        let progressAfter = try Data(contentsOf: fixture.progressURL)
        let blockerAfter = try Data(contentsOf: blockedParent)
        try require(progressBefore == progressAfter && blockerAfter == Data("keep me".utf8), "Cache save failure changed unrelated disk data")
        print("PASS failed cache save keeps session data and reports that it is not saved offline")
    }

    private static func checkResourceCancellation() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        let originalTitle = model.resourceCatalog?.title
        try await eventually("Cancelable request did not start") { await fixture.loader.requestCount == 1 }
        model.stopResourceCatalogRefresh()
        try require(!model.isRefreshingResourceCatalog && model.resourceCatalogNextRefreshAt == nil, "Stopping refresh did not clear its active state and timer")
        model.refreshResourceCatalog()
        try await eventually("New manual refresh did not start after cancellation") { await fixture.loader.requestCount == 2 }
        await fixture.loader.succeed(try resourceSnapshot("Canceled late response", day: 9), request: 1)
        try await eventually("Canceled loader did not deliver its test response") { await fixture.loader.deliveredCount == 1 }
        for _ in 0..<10 { await Task.yield() }
        try require(model.resourceCatalog?.title == originalTitle, "Canceled response changed the displayed catalog")
        try require(model.isRefreshingResourceCatalog, "Canceled response cleared a newer in-flight refresh")
        try require(!FileManager.default.fileExists(atPath: fixture.catalogURL.path), "Canceled response was persisted")
        await fixture.loader.succeed(try resourceSnapshot("New manual response", day: 10), request: 2)
        try await eventually("New request did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "New manual response", "Current response was lost after canceling an earlier request")
        let persisted = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).load()
        try require(persisted?.title == "New manual response", "Late canceled response replaced the offline snapshot")
        try require(model.resourceCatalogNextRefreshAt == nil, "Manual refresh restarted a stopped automatic timer")
        print("PASS cancellation rejects late delivery without disturbing a newer manual request")
    }

    private static func checkOlderResourceResponse() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        _ = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).save(resourceSnapshot("Newest saved catalog", day: 15))
        let before = try Data(contentsOf: fixture.catalogURL)
        let model = fixture.model()
        try await eventually("Older-response check did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Older CDN response", day: 14), request: 1)
        try await eventually("Older-response check did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "Newest saved catalog", "Older CDN data replaced a newer local snapshot")
        try require(model.resourceCatalogSavedOffline, "Rejecting an older response lost offline availability")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Validated older response did not record its check time")
        let after = try Data(contentsOf: fixture.catalogURL)
        try require(before == after, "Older CDN data overwrote the newer disk cache")
        print("PASS older CDN response preserves the newer displayed and saved snapshot")
    }

    private static func checkResourceRetry() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        try await eventually("Initial retry fixture request did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Before network outage", day: 20), request: 1)
        try await eventually("First retry fixture response did not finish") { !model.isRefreshingResourceCatalog }
        try await eventually("First periodic timer did not arm") { await fixture.sleeper.pendingCount == 1 }
        let saved = try Data(contentsOf: fixture.catalogURL)
        fixture.now.addTimeInterval(900)
        await fixture.sleeper.wakeNext()
        try await eventually("Periodic outage request did not start") { await fixture.loader.requestCount == 2 }
        await fixture.loader.fail(request: 2)
        try await eventually("Failed periodic request did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalogRefreshNotice != nil && model.resourceCatalogSavedOffline, "Outage did not preserve and explain the saved fallback")
        try require(model.resourceCatalogNextRefreshAt == fixture.now.addingTimeInterval(900), "Outage did not schedule a bounded retry")
        let unchanged = try Data(contentsOf: fixture.catalogURL)
        try require(saved == unchanged, "Failed periodic fetch altered the cache")
        try await eventually("Retry timer was not armed after failure") { await fixture.sleeper.pendingCount == 1 }
        fixture.now.addTimeInterval(900)
        await fixture.sleeper.wakeNext()
        try await eventually("Retry did not run automatically") { await fixture.loader.requestCount == 3 }
        await fixture.loader.succeed(try resourceSnapshot("After automatic recovery", day: 21), request: 3)
        try await eventually("Automatic recovery did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "After automatic recovery" && model.resourceCatalogRefreshNotice == nil, "Automatic recovery retained stale content or warning")
        model.stopResourceCatalogRefresh()
        try await eventually("Stopping refresh left a periodic sleeper alive") { await fixture.sleeper.pendingCount == 0 }
        print("PASS periodic failure keeps offline data and automatically retries successfully")
    }

    private static func checkNewerResourceSavedDuringDownload() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        try await eventually("Concurrent-save fixture request did not start") { await fixture.loader.requestCount == 1 }
        // Another app instance writes newer data while this model still has its bundle.
        _ = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).save(resourceSnapshot("Saved by another instance", day: 27))
        let before = try Data(contentsOf: fixture.catalogURL)
        await fixture.loader.succeed(try resourceSnapshot("In-flight older download", day: 26), request: 1)
        try await eventually("Concurrent-save response did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "Saved by another instance", "Concurrent newer disk data did not replace the in-flight response")
        try require(model.resourceCatalogSavedOffline && model.resourceCatalogOrigin.localizedCaseInsensitiveContains("saved"), "Concurrent newer catalog was not identified as saved offline data")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Concurrent disk recovery lost its successful check time")
        let after = try Data(contentsOf: fixture.catalogURL)
        try require(before == after, "In-flight download overwrote a newer concurrent cache save")
        print("PASS newer catalog saved during a download wins on disk and in the displayed library")
    }

    private static func checkResourceClockAdjustment() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        try await eventually("Clock-adjustment fixture did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Before clock change", day: 22), request: 1)
        try await eventually("Clock-adjustment response did not finish") { !model.isRefreshingResourceCatalog }
        try await eventually("Clock-adjustment timer was not armed") { await fixture.sleeper.pendingCount == 1 }
        fixture.now.addTimeInterval(-3600)
        model.refreshResourceCatalogIfDue()
        try require(model.resourceCatalogNextRefreshAt == fixture.now.addingTimeInterval(900), "Backward clock change postponed the next refresh by more than one interval")
        try await eventually("Clock-adjustment timer was not replaced") {
            let durations = await fixture.sleeper.durations
            let pending = await fixture.sleeper.pendingCount
            return durations.count == 2 && pending == 1
        }
        // The monotonic timer elapsed even though the wall clock has not caught up.
        await fixture.sleeper.wakeNext()
        try await eventually("Elapsed timer was suppressed by a backward wall clock") { await fixture.loader.requestCount == 2 }
        model.stopResourceCatalogRefresh()
        print("PASS backward clock changes cannot postpone or suppress an elapsed refresh timer")
    }

    private static func checkRealResourceTimer() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model(interval: 0.1, realSleep: true)
        try await eventually("Real-timer launch request did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Before real timer", day: 23), request: 1)
        // No manual refresh, fake-clock advance, or continuation wake occurs here.
        try await eventually("Real Task.sleep timer did not start an automatic refresh") { await fixture.loader.requestCount == 2 }
        await fixture.loader.succeed(try resourceSnapshot("After real timer", day: 24), request: 2)
        try await eventually("Real-timer response did not finish") { !model.isRefreshingResourceCatalog }
        model.stopResourceCatalogRefresh()
        try require(model.resourceCatalog?.title == "After real timer", "Real timer did not display its downloaded update")
        let fakeSleeps = await fixture.sleeper.durations
        try require(fakeSleeps.isEmpty, "Real-timer check accidentally used the fake sleeper")
        print("PASS real elapsed-time scheduler refreshes automatically while the model is alive")
    }
}
