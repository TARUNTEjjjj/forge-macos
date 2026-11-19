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

/// `AppModel`'s copies of history-sized values, for one saved progress.
private struct HistoryCache {
    var calendar: Calendar?
    /// Daily totals by the start of each requested day.
    var minutes: [[Date]: [Int]] = [:]
    /// The saved sessions, sorted once for every journal search of this progress.
    var index: SessionSearchIndex?
    /// The journal's matching sessions, by search.
    var matches: [SessionSearch: SessionMatches] = [:]
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
    @Published private(set) var progress = ProgressSnapshot() {
        didSet {
            history = HistoryCache()
            progressVersion += 1
        }
    }
    @Published private(set) var readOnly = false
    @Published var message: String?
    @Published var backupCandidate: Data?
    @Published var showRestoreConfirmation = false
    @Published var noteDrafts: [String: String] = [:]
    @Published var focusDraft = ""
    @Published var sessionReflectionDraft = ""
    @Published var sessionMinutesDraft = 25
    @Published var sessionModuleIDDraft = ""
    @Published private(set) var recoveryCopies: [URL] = []
    /// Forge windows open now. The message and restore alerts can only appear in one.
    var openWindows = 0
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
    /// Values computed from the whole session history. Every view that observes this model
    /// redraws on each keystroke in any editor, because the drafts are published here, and
    /// whenever a resource refresh publishes its state. So views read history through these
    /// copies, which are recomputed only for new progress or a new journal search.
    private var history = HistoryCache()
    /// Counts each new saved progress, so a search that finishes later can tell whether
    /// the sessions it searched are still the ones saved.
    private var progressVersion = 0
    /// How many times history-sized values were computed; native checks read it.
    private(set) var historyComputations = 0
    /// Journal searches kept at once. Each holds up to the whole history, and each search
    /// typed is a new one, so only enough for the journals on screen are kept.
    private static let keptSearches = 4

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
            recoveryCopies = storage.recoveryCopies()
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

    /// The saved sessions that match a journal search, newest first, and their total minutes,
    /// as `ProgressSnapshot.filteredSessions` finds them with this curriculum's lesson titles.
    func matchingSessions(query: String = "", moduleID: String? = nil,
                          since: Date? = nil, before: Date? = nil) -> SessionMatches {
        let search = SessionSearch(query: query, moduleID: moduleID, since: since, before: before)
        if let matches = cachedMatches(search) { return matches }
        let matches = searchIndex.matches(search) ?? SessionMatches()
        keep(matches, for: search)
        return matches
    }

    /// The matching sessions for `search` if they are already found for this saved progress.
    func cachedMatches(_ search: SessionSearch) -> SessionMatches? {
        history.matches[search]
    }

    /// Finds `search`'s sessions away from the main actor and keeps them, so the journal can
    /// then show them without searching while it draws. It reports whether they were kept: a
    /// search that finishes after saved progress changed is dropped, since its sessions are
    /// out of date. The search runs in the caller's task, so cancelling the caller (such as
    /// the journal's pending search when the learner types on) stops it and keeps nothing.
    func prepareMatches(_ search: SessionSearch) async -> Bool {
        if cachedMatches(search) != nil { return true }
        let index = searchIndex, version = progressVersion
        guard let matches = await index.matchesInBackground(search), !Task.isCancelled,
              progressVersion == version else { return false }
        keep(matches, for: search)
        return true
    }

    /// The saved sessions sorted for searching, prepared once per saved progress.
    private var searchIndex: SessionSearchIndex {
        if let index = history.index { return index }
        let titles = Dictionary(uniqueKeysWithValues: (curriculum?.modules ?? []).map { ($0.id, $0.title) })
        let index = SessionSearchIndex(sessions: progress.sessions, moduleTitles: titles)
        history.index = index
        return index
    }

    private func keep(_ matches: SessionMatches, for search: SessionSearch) {
        if history.matches[search] == nil, history.matches.count >= Self.keptSearches { history.matches.removeAll() }
        history.matches[search] = matches
        historyComputations += 1
    }

    /// Minutes practiced on each of `days`, as `ProgressSnapshot.minutes(on:calendar:)` counts them.
    func minutes(on days: [Date], calendar: Calendar = .current) -> [Int] {
        if history.calendar != calendar {
            history.calendar = calendar
            history.minutes = [:]
        }
        let key = days.map { calendar.startOfDay(for: $0) }
        if let minutes = history.minutes[key] { return minutes }
        let minutes = progress.minutes(on: key, calendar: calendar)
        history.minutes[key] = minutes
        historyComputations += 1
        return minutes
    }

    /// Reviewed lessons in this curriculum; kept IDs of renamed or retired lessons don't count.
    var reviewedModuleCount: Int {
        curriculum.map { progress.completedModuleCount(in: $0) } ?? 0
    }

    /// Promises a recovery copy only when there is a saved progress file to copy.
    var restoreConfirmationText: String {
        let keepsCopy = store.map { FileManager.default.fileExists(atPath: $0.fileURL.path) } ?? false
        return "This replaces native lesson progress, notes, focus, and study sessions."
            + (keepsCopy ? " A recovery copy of the existing file will be kept." : "")
            + (hasUnsavedDrafts ? " Unsaved drafts stay in their editors, so you can still save them." : "")
            + " Online labs are unaffected."
    }

    /// Whether an editor holds text that saved progress doesn't have yet.
    var hasUnsavedDrafts: Bool {
        !unsavedNoteModules.isEmpty || focusDraft != progress.dailyFocus
            || !sessionReflectionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func openModule(_ id: String) {
        selectedModuleID = id
        search = ""
        destination = .curriculum
    }

    @discardableResult
    func update(_ mutate: (inout ProgressSnapshot) -> Void) -> Bool {
        guard !readOnly, let store else { return false }
        do {
            // The change is applied to the newest saved progress. Another Forge window
            // or app may have saved since this one did, and its work must be kept.
            adopt(try store.save(progress, applying: mutate))
            return true
        } catch {
            message = "Could not save this change. Your previous saved progress is unchanged. \(error.localizedDescription)"
            return false
        }
    }

    /// Shows `saved` progress in place of the current one. A draft that still matches
    /// the text it was based on moves to the new text, so it can't later write stale
    /// text back. A draft the learner edited stays as typed, so it is never dropped.
    private func adopt(_ saved: ProgressSnapshot) {
        var drafts = noteDrafts
        for id in Set(progress.notes.keys).union(saved.notes.keys)
        where (drafts[id] ?? "") == (progress.notes[id] ?? "") {
            drafts[id] = saved.notes[id]
        }
        if drafts != noteDrafts { noteDrafts = drafts }
        if focusDraft == progress.dailyFocus, focusDraft != saved.dailyFocus { focusDraft = saved.dailyFocus }
        progress = saved
    }

    /// Shows progress that another copy of Forge saved after this one last loaded or saved.
    /// The app calls this whenever it becomes active, so an edit made after switching from
    /// the other copy builds on its newer text. Drafts the learner edited stay as typed.
    func adoptNewerSavedProgress() {
        guard !readOnly, let store, let newer = try? store.newerSavedProgress(), newer != progress else { return }
        adopt(newer)
    }

    func markComplete(_ id: String, completed: Bool) {
        update { if completed { $0.completedModuleIDs.insert(id) } else { $0.completedModuleIDs.remove(id) } }
    }

    func exportBackup() {
        do {
            guard let bytes = try backupData() else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Forge-progress-\(Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))).json"
            panel.message = "Save your native Mac lessons, notes, focus, and study sessions. Online lab data is stored separately."
            if panel.runModal() == .OK, let url = panel.url {
                try bytes.write(to: url, options: .atomic)
                if let omitted = backupOmissionNote { message = omitted }
            }
        } catch { message = "Could not export your backup: \(error.localizedDescription)" }
    }

    /// Saves the note drafts that can be saved, then encodes the newest saved progress
    /// for a backup. A draft that can't be saved yet, such as a note over the limit,
    /// doesn't hold back the backup; `backupOmissionNote` names it. Nil when read-only.
    func backupData() throws -> Data? {
        guard !readOnly, let store else { return nil }
        flushNotes()
        // Another Forge window or app may have saved progress since this one did.
        adoptNewerSavedProgress()
        return try store.exportData(progress)
    }

    /// Lessons whose note draft differs from saved progress, in learning-path order.
    var unsavedNoteModules: [LearningModule] {
        (curriculum?.modules ?? []).filter { module in
            noteDrafts[module.id].map { $0 != progress.notes[module.id] ?? "" } ?? false
        }
    }

    /// Names the note drafts that a backup leaves out because they aren't saved yet.
    var backupOmissionNote: String? {
        let unsaved = unsavedNoteModules
        guard !unsaved.isEmpty else { return nil }
        let titles = unsaved.map { "“\($0.title)”" }.joined(separator: ", ")
        let oversized = unsaved.contains { (noteDrafts[$0.id]?.utf8.count ?? 0) > ProgressFileStore.maximumTextBytes }
        return "Backup saved without your unsaved note draft\(unsaved.count == 1 ? "" : "s") for \(titles)."
            + (oversized ? " A note can hold up to 20,000 bytes; shorten a longer draft to save it." : "")
    }

    /// Saves every note draft that differs from saved progress and fits the note limit.
    /// A draft over the limit stays unsaved without holding back the others. Returns
    /// true when no note draft is left unsaved.
    @discardableResult
    func flushNotes() -> Bool {
        guard !readOnly else { return false }
        // Only edited drafts are written, so a flush never puts older text back over a
        // note that another Forge window saved.
        let edited = noteDrafts.filter { $0.value != progress.notes[$0.key] ?? "" }
        let fitting = edited.filter { $0.value.utf8.count <= ProgressFileStore.maximumTextBytes }
        if !fitting.isEmpty, !update({ $0.notes.merge(fitting) { _, draft in draft } }) { return false }
        return fitting.count == edited.count
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
            guard size <= ProgressFileStore.maximumBackupBytes else { throw ProgressError.oversizedBackup }
            let data = try Data(contentsOf: url)
            _ = try store.importData(data)
            backupCandidate = data
            showRestoreConfirmation = true
        } catch { message = "This backup was not imported: \(error.localizedDescription)" }
    }

    func confirmRestore() {
        guard let data = backupCandidate, let store else { return }
        defer { backupCandidate = nil }
        do {
            let restore = try store.restoreBackup(data)
            // Text the learner typed but hasn't saved isn't in the recovery copy, so it
            // stays in its editor. Every other draft follows the restored progress.
            adopt(restore.snapshot)
            readOnly = false
            recoveryCopies = store.recoveryCopies()
            if let copy = restore.recoveryCopy {
                message = "Backup restored. Your previous data was kept as “\(copy.lastPathComponent)”. To find it, choose File > Show Recovery Copies in Finder."
            } else { message = "Backup restored." }
        } catch { message = "Restore failed. Your data was left untouched. \(error.localizedDescription)" }
    }

    /// Selects the files that restores kept, which live in the app's hidden data folder.
    func showRecoveryCopies() {
        guard let store else { return }
        recoveryCopies = store.recoveryCopies()
        if !recoveryCopies.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(recoveryCopies) }
    }

    func openExternal(_ url: URL) {
        guard url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }
}
