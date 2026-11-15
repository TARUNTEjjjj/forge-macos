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

/// How the overview map draws one chapter.
enum ChapterStatus: String {
    case upcoming, current, complete
}

@MainActor
final class AppModel: ObservableObject {
    @Published var destination: Destination? = .home
    @Published var selectedModuleID: String?
    @Published var search = ""
    @Published private(set) var curriculum: Curriculum?
    @Published private(set) var resourceCatalog: ResourceCatalog?
    @Published private(set) var resourceCatalogError: String?
    @Published private(set) var resourceCatalogOrigin = "Bundled offline snapshot"
    @Published private(set) var isRefreshingResourceCatalog = false
    @Published private(set) var resourceCatalogRefreshNotice: String?
    @Published private(set) var resourceCatalogSavedOffline = false
    @Published private(set) var resourceCatalogLastCheckedAt: Date?
    @Published private(set) var resourceCatalogNextRefreshAt: Date?
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
    private var resourceStore: ResourceCatalogFileStore?
    private var automaticResourceRefreshEnabled: Bool
    private let resourceRefreshInterval: TimeInterval
    private let resourceNow: @MainActor () -> Date
    private let resourceSleep: @Sendable (Duration) async throws -> Void
    private let resourceLoader: @Sendable () async throws -> ResourceCatalog
    private var resourceTimerTask: Task<Void, Never>?
    private var resourceRequestTask: Task<Void, Never>?
    private var resourceRequestGeneration = 0
    nonisolated static let defaultResourceRefreshInterval: TimeInterval = 15 * 60

    init(progressURL: URL? = nil, refreshCatalogOnLaunch: Bool = true,
         resourceCatalogURL: URL? = nil,
         resourceRefreshInterval: TimeInterval = AppModel.defaultResourceRefreshInterval,
         resourceNow: @escaping @MainActor () -> Date = { Date() },
         resourceSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         resourceLoader: @escaping @Sendable () async throws -> ResourceCatalog = { try await ResourceCatalog.loadLatest() }) {
        automaticResourceRefreshEnabled = refreshCatalogOnLaunch
        self.resourceRefreshInterval = resourceRefreshInterval.isFinite && resourceRefreshInterval > 0
            ? resourceRefreshInterval : Self.defaultResourceRefreshInterval
        self.resourceNow = resourceNow
        self.resourceSleep = resourceSleep
        self.resourceLoader = resourceLoader
        do { resourceCatalog = try ResourceCatalog.loadBundled() }
        catch { resourceCatalogError = error.localizedDescription }
        do {
            let url: URL
            if let resourceCatalogURL { url = resourceCatalogURL }
            else if let progressURL {
                // Keep test stores together without touching the learner's Application Support data.
                url = progressURL.deletingLastPathComponent().appendingPathComponent("resource-catalog.json")
            } else {
                let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                url = base.appendingPathComponent("Forge", isDirectory: true).appendingPathComponent("resource-catalog.json")
            }
            let storage = ResourceCatalogFileStore(fileURL: url)
            resourceStore = storage
            if let saved = try storage.load(), resourceCatalog.map({ !saved.isOlder(than: $0) }) ?? true {
                resourceCatalog = saved
                resourceCatalogOrigin = "Saved offline snapshot"
                resourceCatalogSavedOffline = true
                resourceCatalogError = nil
            }
        } catch {
            resourceCatalogRefreshNotice = "The saved collection could not be read. Using the bundled collection until GitHub can be reached."
        }
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
        if refreshCatalogOnLaunch { refreshResourceCatalog() }
    }

    deinit {
        resourceTimerTask?.cancel()
        resourceRequestTask?.cancel()
    }

    /// Manual and automatic refreshes share one request; no overlapping downloads or retry storm.
    func refreshResourceCatalog() {
        guard !isRefreshingResourceCatalog else { return }
        resourceTimerTask?.cancel()
        resourceTimerTask = nil
        isRefreshingResourceCatalog = true
        resourceCatalogNextRefreshAt = nil
        resourceCatalogRefreshNotice = nil
        resourceRequestGeneration += 1
        let generation = resourceRequestGeneration
        let loader = resourceLoader
        resourceRequestTask = Task { [weak self] in
            let result: Result<ResourceCatalog, Error>
            do { result = .success(try await loader()) }
            catch { result = .failure(error) }
            guard !Task.isCancelled else { return }
            self?.finishResourceRefresh(result, generation: generation)
        }
    }

    /// Called by the timer, app activation, and wake. The due date survives frequent focus changes.
    func refreshResourceCatalogIfDue() {
        guard automaticResourceRefreshEnabled, !isRefreshingResourceCatalog else { return }
        let now = resourceNow()
        if let due = resourceCatalogNextRefreshAt, due > now {
            if due.timeIntervalSince(now) > resourceRefreshInterval {
                // A backward wall-clock adjustment must not postpone refresh indefinitely.
                resourceCatalogNextRefreshAt = now.addingTimeInterval(resourceRefreshInterval)
            }
            scheduleResourceRefresh()
        } else {
            refreshResourceCatalog()
        }
    }

    /// Only stop at actual shutdown; cancelling the unsaved-draft dialog must keep refresh alive.
    func stopResourceCatalogRefresh() {
        automaticResourceRefreshEnabled = false
        resourceRequestGeneration += 1
        resourceTimerTask?.cancel()
        resourceRequestTask?.cancel()
        resourceTimerTask = nil
        resourceRequestTask = nil
        isRefreshingResourceCatalog = false
        resourceCatalogNextRefreshAt = nil
    }

    private func finishResourceRefresh(_ result: Result<ResourceCatalog, Error>, generation: Int) {
        guard generation == resourceRequestGeneration else { return }
        defer {
            isRefreshingResourceCatalog = false
            resourceRequestTask = nil
            if automaticResourceRefreshEnabled {
                // Failed attempts wait the same interval, avoiding repeated offline requests on focus.
                resourceCatalogNextRefreshAt = resourceNow().addingTimeInterval(resourceRefreshInterval)
                scheduleResourceRefresh()
            }
        }
        switch result {
        case .success(let downloaded):
            resourceCatalogLastCheckedAt = resourceNow()
            if let current = resourceCatalog, downloaded.isOlder(than: current) {
                resourceCatalogRefreshNotice = "GitHub returned an older collection. Keeping the newer collection already available on this Mac."
                return
            }
            var current = downloaded
            var origin = "Downloaded GitHub snapshot"
            var savedOffline = false
            do {
                guard let resourceStore else { throw CocoaError(.fileWriteUnknown) }
                if try !resourceStore.save(downloaded) {
                    guard let newerSaved = try resourceStore.load() else { throw CocoaError(.fileReadNoSuchFile) }
                    current = newerSaved
                    origin = "Saved offline snapshot"
                }
                savedOffline = true
            } catch {
                resourceCatalogRefreshNotice = "The latest collection loaded, but could not be saved for offline use. The previous saved collection is unchanged."
            }
            resourceCatalog = current
            resourceCatalogOrigin = origin
            resourceCatalogSavedOffline = savedOffline
            resourceCatalogError = nil
        case .failure:
            resourceCatalogRefreshNotice = resourceCatalog == nil
                ? "The GitHub catalog could not be loaded. The original learning references remain available."
                : "Could not refresh from GitHub. Keeping the current collection; saved offline data is unchanged."
        }
    }

    private func scheduleResourceRefresh() {
        guard automaticResourceRefreshEnabled, let due = resourceCatalogNextRefreshAt else { return }
        resourceTimerTask?.cancel()
        let delay = min(resourceRefreshInterval, max(0, due.timeIntervalSince(resourceNow())))
        let sleep = resourceSleep
        // Do not retain AppModel across the wait, including when no windows remain visible.
        resourceTimerTask = Task { [weak self] in
            do { try await sleep(.seconds(delay)) }
            catch { return }
            guard !Task.isCancelled, let self, self.automaticResourceRefreshEnabled else { return }
            // The elapsed-time timer also works when the system's wall clock changes.
            self.refreshResourceCatalog()
        }
    }

    var nextModule: LearningModule? {
        curriculum?.modules.first { !progress.completedModuleIDs.contains($0.id) }
    }

    /// Lessons can be reviewed in any order, so each chapter's state comes from
    /// its own modules rather than from how many modules are reviewed. The
    /// current chapter is the one holding `nextModule`, matching Up Next.
    var chapterStatuses: [ChapterStatus] {
        guard let curriculum else { return [] }
        let next = nextModule?.id
        return curriculum.phases.map { phase in
            if phase.modules.contains(where: { $0.id == next }) { return .current }
            return phase.modules.allSatisfy { progress.completedModuleIDs.contains($0.id) } ? .complete : .upcoming
        }
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
