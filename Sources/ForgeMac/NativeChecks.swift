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
        let host = NSHostingView(rootView: JournalView().environmentObject(model))
        host.frame = NSRect(x: 0, y: 0, width: 1_100, height: 900)
        host.layoutSubtreeIfNeeded()
        func focusField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.placeholderString?.hasPrefix("For example: implement BFS") == true { return field }
            return view.subviews.lazy.compactMap(focusField).first
        }
        return focusField(in: host)?.isEnabled
    }
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Forge-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let model = AppModel(progressURL: url)
        guard let catalog = model.curriculum, let lesson = catalog.modules.first else { throw Failure("Curriculum load failed") }
        try require(!model.readOnly, "Fresh store should be writable")
        model.noteDrafts[lesson.id] = "Invariant: the queue contains discovered, unprocessed vertices."
        model.destination = .journal
        model.openModule(lesson.id)
        try require(model.noteDrafts[lesson.id]?.hasPrefix("Invariant:") == true, "Navigation lost the note draft")
        try require(model.flushNotes(), "Pending note could not flush before backup")
        let reopened = AppModel(progressURL: url)
        try require(reopened.progress.notes[lesson.id] == model.noteDrafts[lesson.id], "Flushed draft did not survive restart")
        print("PASS shared draft survives navigation and restart")

        let before = try Data(contentsOf: url)
        model.noteDrafts[lesson.id] = String(repeating: "x", count: 20_001)
        try require(!model.flushNotes(), "Oversized draft unexpectedly saved")
        let after = try Data(contentsOf: url)
        try require(before == after, "Failed save altered the existing progress file")
        try require(model.noteDrafts[lesson.id]?.count == 20_001, "Failed save discarded the draft")
        print("PASS failed save retains draft and preserves disk")

        let store = ProgressFileStore(fileURL: url, allowedModuleIDs: catalog.moduleIDs)
        let restored = ProgressSnapshot(notes: [lesson.id: "Restored note"], dailyFocus: "Test the boundary")
        model.backupCandidate = try store.exportData(restored)
        model.confirmRestore()
        try require(model.noteDrafts[lesson.id] == "Restored note", "Restore left stale editor text")
        try require(model.focusDraft == "Test the boundary", "Restore left stale focus text")
        try require(model.flushNotes(), "Restored draft could not flush")
        let disk = try store.load()
        try require(disk.notes == restored.notes, "Draft flush overwrote restored notes")
        print("PASS restore replaces shared drafts before further saves")
        try require(LabBrowser.permitsFrame(URL(string: "about:srcdoc")!, isMainFrame: false), "Sandbox runner child frame was blocked")
        try require(!LabBrowser.permitsFrame(URL(string: "about:srcdoc")!, isMainFrame: true), "Top-level srcdoc was allowed")
        try require(!LabBrowser.permitsFrame(URL(string: "https://example.com/")!, isMainFrame: false), "Untrusted embedded navigation was allowed")
        try require(!LabBrowser.permitsFrame(URL(string: "javascript:alert(1)")!, isMainFrame: true), "Script navigation was allowed")
        print("PASS sandbox runner frame allowed with external navigation blocked")

        // Lessons can be reviewed in any order. The overview map must mark the
        // chapters actually reviewed, and its current chapter must hold Up Next.
        let mapURL = directory.appendingPathComponent("map/progress.json")
        let learner = AppModel(progressURL: mapURL)
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
        try requireMap(AppModel(progressURL: mapURL), [0: .complete, 1: .current, last: .complete], "Final chapter after restart")
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
        let damaged = AppModel(progressURL: damagedURL)
        try require(damaged.readOnly, "Damaged progress did not open read-only")
        try require(focusFieldEnabled(model) == true, "Writable journal focus field is missing or disabled")
        try require(focusFieldEnabled(damaged) == false, "Read-only journal focus field accepts text it cannot save")
        print("PASS read-only journal focus field refuses unsaveable text")
        print("6/6 native regression checks passed")
    }
}
