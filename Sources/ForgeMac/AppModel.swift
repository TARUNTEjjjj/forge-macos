import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ForgeCore

enum Destination: String, CaseIterable, Identifiable {
    case home = "Overview", curriculum = "Learning path", labs = "Interactive labs", journal = "Practice journal", resources = "Library"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .curriculum: return "map"
        case .labs: return "terminal"
        case .journal: return "book.closed"
        case .resources: return "books.vertical"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var destination: Destination? = .home
    @Published var selectedModuleID: String?
    @Published var search = ""
    @Published private(set) var curriculum: Curriculum?
    @Published private(set) var progress = ProgressSnapshot()
    @Published private(set) var readOnly = false
    @Published var message: String?
    @Published var backupCandidate: Data?
    @Published var showRestoreConfirmation = false
    @Published var noteDrafts: [String: String] = [:]
    @Published var focusDraft = ""
    @Published var sessionReflectionDraft = ""
    @Published var sessionMinutesDraft = 25
    @Published var sessionModuleIDDraft = ""
    private var store: ProgressFileStore?

    init(progressURL: URL? = nil) {
        do {
            let catalog = try Curriculum.loadBundled()
            curriculum = catalog
            let url: URL
            if let progressURL { url = progressURL }
            else {
                let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                url = base.appendingPathComponent("Forge", isDirectory: true).appendingPathComponent("progress.json")
            }
            let storage = ProgressFileStore(fileURL: url, allowedModuleIDs: Set(catalog.modules.map(\.id)))
            store = storage
            progress = try storage.load()
            noteDrafts = progress.notes
            focusDraft = progress.dailyFocus
            selectedModuleID = catalog.modules.first(where: { !progress.completedModuleIDs.contains($0.id) })?.id ?? catalog.modules.first?.id
        } catch {
            readOnly = true
            message = "Your saved data was left untouched. \(error.localizedDescription) Restore a valid Forge Mac backup to continue saving."
        }
    }

    var nextModule: LearningModule? {
        curriculum?.modules.first { !progress.completedModuleIDs.contains($0.id) }
    }

    func openModule(_ id: String) {
        selectedModuleID = id
        search = ""
        destination = .curriculum
    }

    @discardableResult
    func update(_ mutate: (inout ProgressSnapshot) -> Void) -> Bool {
        guard !readOnly, let store else { return false }
        var candidate = progress
        mutate(&candidate)
        do {
            try store.save(candidate)
            progress = candidate
            return true
        } catch {
            message = "Could not save this change. Your previous saved progress is unchanged. \(error.localizedDescription)"
            return false
        }
    }

    func markComplete(_ id: String, completed: Bool) {
        update { if completed { $0.completedModuleIDs.insert(id) } else { $0.completedModuleIDs.remove(id) } }
    }

    func exportBackup() {
        guard !readOnly, let store else { return }
        guard flushNotes() else { return }
        do {
            let bytes = try store.exportData(progress)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Forge-progress-\(Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))).json"
            panel.message = "Save your native Mac lessons, notes, focus, and study sessions. Online lab data is stored separately."
            if panel.runModal() == .OK, let url = panel.url {
                try bytes.write(to: url, options: .atomic)
            }
        } catch { message = "Could not export your backup: \(error.localizedDescription)" }
    }

    @discardableResult
    func flushNotes() -> Bool {
        guard !readOnly else { return false }
        if noteDrafts == progress.notes { return true }
        return update { $0.notes = noteDrafts }
    }

    func chooseBackup() {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Forge Mac backup. You will confirm before your current progress is replaced."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: url)
            _ = try store.importData(data)
            backupCandidate = data
            showRestoreConfirmation = true
        } catch { message = "This backup was not imported: \(error.localizedDescription)" }
    }

    func confirmRestore() {
        guard let data = backupCandidate, let store else { return }
        defer { backupCandidate = nil }
        let hadExisting = FileManager.default.fileExists(atPath: store.fileURL.path)
        do {
            progress = try store.recoverFromBackup(data)
            noteDrafts = progress.notes
            focusDraft = progress.dailyFocus
            sessionReflectionDraft = ""
            readOnly = false
            message = hadExisting ? "Backup restored. A recovery copy of your previous data was kept on this Mac." : "Backup restored."
        } catch { message = "Restore failed. Your data was left untouched. \(error.localizedDescription)" }
    }

    func openExternal(_ url: URL) {
        guard url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }
}
