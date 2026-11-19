import SwiftUI
import ForgeCore

@main
enum ForgeLauncher {
    @MainActor static func main() {
        do {
            if CommandLine.arguments.contains("--check-resources") {
                let curriculum = try Curriculum.loadBundled()
                print("Bundled curriculum: \(curriculum.modules.count) modules, \(curriculum.totalHours) hours")
            } else if CommandLine.arguments.contains("--check-native") {
                try NativeChecks.run()
                Task { @MainActor in
                    do {
                        try await NativeChecks.runJournalSearch()
                        exit(0)
                    } catch {
                        fputs("Forge journal search check failed: \(error.localizedDescription)\n", stderr)
                        exit(1)
                    }
                }
                RunLoop.main.run()
            } else if CommandLine.arguments.contains("--check-lab-unload") {
                try LabUnloadChecks.run()
            } else if CommandLine.arguments.contains("--check-lab-unload-live") {
                // Uses the live labs site, so it needs internet and isn't part of CI.
                try LabUnloadChecks.runLive()
            } else if CommandLine.arguments.contains("--check-resource-refresh") {
                Task { @MainActor in
                    do {
                        try await NativeChecks.runResourceRefresh()
                        exit(0)
                    } catch {
                        fputs("Forge resource refresh check failed: \(error.localizedDescription)\n", stderr)
                        exit(1)
                    }
                }
                RunLoop.main.run()
            } else { ForgeApp.main() }
        } catch {
            fputs("Forge check failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

struct ForgeApp: App {
    static let windowID = "forge"
    @NSApplicationDelegateAdaptor(ForgeLifecycle.self) private var lifecycle
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Forge", id: Self.windowID) {
            ForgeWindow().environmentObject(model).preferredColorScheme(.dark)
                .frame(minWidth: 880, minHeight: 640)
                .onAppear { lifecycle.model = model }
        }
        .defaultSize(width: 1260, height: 840)
        .commands { ForgeCommands(model: model) }
    }
}

/// The File and Learn commands stay available with no Forge window open, but what they show
/// (the restore confirmation, a backup message, the chosen page) appears in a Forge window.
/// So a command opens one when there is none, instead of leaving its result unseen.
struct ForgeCommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Export Learning Backup…") { model.exportBackup(); showPendingAlert() }
                .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.readOnly)
            Button("Restore Learning Backup…") { model.chooseBackup(); showPendingAlert() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Show Recovery Copies in Finder") { model.showRecoveryCopies() }
                .disabled(model.recoveryCopies.isEmpty)
        }
        CommandMenu("Learn") {
            ForEach(Destination.allCases) { destination in
                Button(destination.rawValue) { model.destination = destination; showWindow() }
            }
        }
    }
    private func showPendingAlert() {
        if model.message != nil || model.showRestoreConfirmation { showWindow() }
    }
    private func showWindow() {
        if model.openWindows == 0 { openWindow(id: ForgeApp.windowID) }
    }
}

@MainActor
final class ForgeLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model?.refreshResourceCatalogIfDue() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Another copy of Forge may have saved progress while this one was in the background.
        model?.adoptNewerSavedProgress()
        model?.refreshResourceCatalogIfDue()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stopResourceCatalogRefresh()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard mayQuitWithNativeDrafts() else { return .terminateCancel }
        // The labs page answers asynchronously, so quitting waits for it, and for the learner
        // if it reports unsaved work. Logging out or restarting the Mac waits the same way.
        guard let labs = LabWorkspace.opened, labs.hasPage else { return .terminateNow }
        labs.confirmQuit { quit in sender.reply(toApplicationShouldTerminate: quit) }
        return .terminateLater
    }

    /// Saves the native drafts that can be saved, and asks before quitting discards the rest.
    /// False when the learner keeps working.
    private func mayQuitWithNativeDrafts() -> Bool {
        guard let model else { return true }
        let notesSaved = model.readOnly || model.flushNotes()
        let pendingJournal = model.focusDraft != model.progress.dailyFocus || !model.sessionReflectionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !notesSaved || pendingJournal else { return true }
        let alert = NSAlert()
        alert.messageText = "You have unsaved drafts"
        alert.informativeText = "Keep working to save your journal or shorten an oversized note. Quitting discards the unsaved drafts; your previously saved progress stays intact."
        alert.addButton(withTitle: "Keep working")
        alert.addButton(withTitle: "Quit without saving drafts")
        return alert.runModal() != .alertFirstButtonReturn
    }
}

struct ForgeWindow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Text("F").font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white).frame(width: 42, height: 42)
                        .background(ForgeTheme.action, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("FORGE").font(.system(size: 20, weight: .heavy)).tracking(3)
                        Text("THE LEARNING WORKSPACE").font(.system(size: 8, weight: .medium)).tracking(1)
                            .foregroundStyle(ForgeTheme.muted)
                    }
                }.padding(.horizontal, 16).padding(.top, 18)
                TextField("Find a lesson", text: $model.search).textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)
                    .onChange(of: model.search) { _, value in if !value.isEmpty { model.destination = .curriculum } }
                List(Destination.allCases, selection: $model.destination) { item in
                    Label(item.rawValue, systemImage: item.symbol).padding(.vertical, 8).tag(item)
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.readOnly ? "Restore needed" : "Saved on this Mac", systemImage: model.readOnly ? "exclamationmark.circle" : "lock.shield")
                        .foregroundStyle(model.readOnly ? ForgeTheme.red : ForgeTheme.mint)
                    Text("Your pace. Your practice.\nOne useful thing at a time.").foregroundStyle(ForgeTheme.muted).lineSpacing(4)
                    Button("Export backup…") { model.exportBackup() }.buttonStyle(.link).disabled(model.readOnly)
                }.font(.system(size: 11)).padding(20)
            }.background(ForgeTheme.panel)
                .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 270)
        } detail: {
            ZStack {
                ForgeTheme.background.ignoresSafeArea()
                switch model.destination ?? .home {
                case .home: DashboardView()
                case .curriculum: CurriculumView()
                case .labs: LabView()
                case .journal: JournalView()
                case .resources: ResourceLibraryView()
                }
            }
        }
        .tint(ForgeTheme.red)
        .alert("Forge", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .alert("Restore this backup?", isPresented: $model.showRestoreConfirmation) {
            Button("Cancel", role: .cancel) { model.backupCandidate = nil }
            Button("Restore", role: .destructive) { model.confirmRestore() }
        } message: { Text(model.restoreConfirmationText) }
        // These alerts can only appear in a Forge window, so the commands need to know if one is open.
        .onAppear { model.openWindows += 1 }
        .onDisappear { model.openWindows -= 1 }
    }
}
