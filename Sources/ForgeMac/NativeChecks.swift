import Foundation
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
        print("4/4 native regression checks passed")
    }
}
