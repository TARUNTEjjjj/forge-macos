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
            } else { ForgeApp.main() }
        } catch {
            fputs("Forge check failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

struct ForgeApp: App {
    @NSApplicationDelegateAdaptor(ForgeLifecycle.self) private var lifecycle
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Forge") {
            ForgeWindow().environmentObject(model).preferredColorScheme(.dark)
                .frame(minWidth: 880, minHeight: 640)
                .onAppear { lifecycle.model = model }
        }
        .defaultSize(width: 1260, height: 840)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Export Learning Backup…") { model.exportBackup() }
                    .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.readOnly)
                Button("Restore Learning Backup…") { model.chooseBackup() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Learn") {
                ForEach(Destination.allCases) { destination in
                    Button(destination.rawValue) { model.destination = destination }
                }
            }
        }
    }
}

@MainActor
final class ForgeLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        let notesSaved = model.readOnly || model.flushNotes()
        let pendingJournal = model.focusDraft != model.progress.dailyFocus || !model.sessionReflectionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !notesSaved || pendingJournal else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "You have unsaved drafts"
        alert.informativeText = "Keep working to save your journal or shorten an oversized note. Quitting discards the unsaved drafts; your previously saved progress stays intact."
        alert.addButton(withTitle: "Keep working")
        alert.addButton(withTitle: "Quit without saving drafts")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
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
        } message: { Text("This replaces native lesson progress, notes, focus, and study sessions. A recovery copy of the existing file will be kept. Online labs are unaffected.") }
    }
}
