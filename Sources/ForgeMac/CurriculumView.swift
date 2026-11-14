import SwiftUI
import AppKit
import ForgeCore

struct CurriculumView: View {
    @EnvironmentObject var model: AppModel
    private func matches(_ module: LearningModule) -> Bool {
        model.search.isEmpty || (module.title + " " + module.task + " " + module.id).localizedCaseInsensitiveContains(model.search)
    }
    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Eyebrow(text: "Your learning path")
                    Text("Small steps.\nDeep understanding.").font(.system(size: 23, weight: .bold, design: .rounded))
                    if let curriculum = model.curriculum {
                        ForEach(Array(curriculum.phases.enumerated()), id: \.element.id) { index, phase in
                            let modules = phase.modules.filter(matches)
                            if !modules.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(format:"%02d",index+1) + "  " + phase.title.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(ForgeTheme.violet)
                                    ForEach(modules) { module in
                                        Button { model.selectedModuleID = module.id } label: {
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: model.progress.completedModuleIDs.contains(module.id) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(model.progress.completedModuleIDs.contains(module.id) ? ForgeTheme.mint : ForgeTheme.muted)
                                                Text(module.title).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.leading)
                                                Spacer(minLength: 0)
                                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                                .background(model.selectedModuleID == module.id ? ForgeTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if curriculum.modules.filter(matches).isEmpty {
                            Text("No matching lessons. Try Python, Git, or a shorter search.").foregroundStyle(ForgeTheme.muted)
                        }
                    }
                }.padding(22)
            }.frame(minWidth: 245, idealWidth: 270, maxWidth: 320).background(ForgeTheme.panel.opacity(0.5))
            if let module = model.curriculum?.modules.first(where: { $0.id == model.selectedModuleID }) {
                LessonReader(module: module).id(module.id).frame(minWidth: 360)
            } else {
                EmptyMessage(icon: "book", title: "Choose a lesson", detail: "Read a concept, build something small, and record what you learned.")
            }
        }
    }
}

private struct LessonReader: View {
    @EnvironmentObject var model: AppModel
    let module: LearningModule
    private var note: String { model.noteDrafts[module.id] ?? model.progress.notes[module.id] ?? "" }
    private var noteDirty: Bool { note != (model.progress.notes[module.id] ?? "") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "\(module.id) · \(module.hours) hours suggested practice", title: module.title, subtitle: module.project)
                HStack {
                    Label("Available offline", systemImage: "arrow.down.circle").font(.caption).foregroundStyle(ForgeTheme.mint)
                    Spacer()
                    Toggle("Reviewed", isOn: Binding(get: { model.progress.completedModuleIDs.contains(module.id) }, set: { model.markComplete(module.id, completed: $0) }))
                        .toggleStyle(.switch).disabled(model.readOnly)
                }
                ForEach(Array(module.lessons.enumerated()), id: \.offset) { index, lesson in
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Concept \(index + 1)")
                        Text(lesson).font(.system(size: 15)).lineSpacing(7).textSelection(.enabled)
                    }
                }
                ForEach(Array(module.codeExamples.enumerated()), id: \.offset) { _, example in
                    ForgeCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Eyebrow(text: example.language); Spacer(); Button("Copy code") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(example.code, forType: .string) }.buttonStyle(.link) }
                            ScrollView(.horizontal) { Text(example.code).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false) }
                            Text(example.explanation).font(.caption).foregroundStyle(ForgeTheme.muted).lineSpacing(4)
                        }
                    }
                }
                ForgeCard(color: ForgeTheme.action.opacity(0.16)) {
                    VStack(alignment: .leading, spacing: 15) {
                        Eyebrow(text: "Build it")
                        Text(module.task).font(.system(size: 15, weight: .medium)).lineSpacing(5)
                        Divider()
                        ForEach(module.successCriteria, id: \.self) { criterion in
                            Label(criterion, systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(ForgeTheme.muted)
                        }
                    }
                }
                if !module.resources.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Go to the source")
                        ForEach(module.resources, id: \.url) { resource in
                            Button { model.openExternal(resource.url) } label: { Label(resource.title, systemImage: "arrow.up.right") }.buttonStyle(.link)
                        }
                    }
                }
                ForgeCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Eyebrow(text: "Your understanding"); Spacer(); Text(note.utf8.count > 20_000 ? "Shorten this draft to save" : (noteDirty ? "Unsaved draft" : "Saved locally")).font(.caption).foregroundStyle(ForgeTheme.muted) }
                        Text("Explain the idea in your own words. What did you test? What surprised you?").font(.caption).foregroundStyle(ForgeTheme.muted)
                        TextEditor(text: Binding(get: { note }, set: { model.noteDrafts[module.id] = $0 })).font(.system(size: 14)).frame(minHeight: 140).scrollContentBackground(.hidden)
                            .padding(8).background(ForgeTheme.background, in: RoundedRectangle(cornerRadius: 8)).disabled(model.readOnly)
                        HStack {
                            Text("\(note.utf8.count)/20,000 bytes").font(.caption2).foregroundStyle(ForgeTheme.muted)
                            Spacer()
                            Button("Save note") { saveNote() }.buttonStyle(PrimaryButtonStyle()).disabled(!noteDirty || model.readOnly || note.utf8.count > 20_000)
                        }
                    }
                }
            }.padding(30).frame(maxWidth: 900, alignment: .leading)
        }
        .onDisappear { if noteDirty && note.utf8.count <= 20_000 { saveNote() } }
        .task(id: note) {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, noteDirty, note.utf8.count <= 20_000 else { return }
            saveNote()
        }
    }
    private func saveNote() {
        model.update { $0.notes[module.id] = note }
    }
}

struct ResourceLibraryView: View {
    @EnvironmentObject var model: AppModel
    @ViewState<String> private var query = ""
    @ViewState<String> private var catalogCategory = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "Keep good references close", title: "The library", subtitle: "Official documentation and original problem judges. Work through the lessons, then go deeper at the source.")
                TextField("Search resources and problems", text: $query).textFieldStyle(.roundedBorder)
                if let catalog = model.resourceCatalog {
                    Text("Open-source discovery").font(.title2.bold())
                    Text(model.resourceCatalogOrigin + " · collected " + (catalog.fetchedAt ?? "date unavailable"))
                        .font(.caption).foregroundStyle(ForgeTheme.muted)
                    if catalog.status == "seed" {
                        Text("Curated starting points. Live popularity has not been checked.").font(.caption).foregroundStyle(ForgeTheme.muted)
                    } else if catalog.hasStaleMetadata {
                        Text("Some metadata is older than 24 hours or its last refresh was incomplete.").font(.caption).foregroundStyle(ForgeTheme.muted)
                    }
                    Text("Explore relevant GitHub projects. Stars describe popularity; the source and license remain with each project. The app checks the latest public catalog on launch and keeps an offline fallback.")
                        .font(.callout).foregroundStyle(ForgeTheme.muted)
                    HStack {
                        Button(model.isRefreshingResourceCatalog ? "Refreshing…" : "Refresh resources") { model.refreshResourceCatalog() }
                            .disabled(model.isRefreshingResourceCatalog)
                        if model.isRefreshingResourceCatalog { ProgressView().controlSize(.small) }
                    }
                    if let notice = model.resourceCatalogRefreshNotice {
                        Text(notice).font(.caption).foregroundStyle(ForgeTheme.muted)
                    }
                    Picker("Resource category", selection: $catalogCategory) {
                        Text("All categories").tag("")
                        ForEach(catalog.categories) { category in Text(category.title).tag(category.id) }
                    }.pickerStyle(.menu)
                    let matches = catalog.matching(query, category: catalogCategory)
                    if matches.isEmpty { Text("No GitHub resources match this search.").foregroundStyle(ForgeTheme.muted) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], alignment: .leading, spacing: 14) {
                        ForEach(matches) { resource in
                            ForgeCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Eyebrow(text: resource.category)
                                    Text(resource.fullName).font(.system(size: 17, weight: .semibold))
                                    Text(resource.description).font(.system(size: 12)).foregroundStyle(ForgeTheme.muted).lineLimit(4)
                                    Text((resource.stars.map { "\($0.formatted()) stars" } ?? "Stars unverified") + " · " + (resource.license ?? "License unreported"))
                                        .font(.caption).foregroundStyle(ForgeTheme.muted)
                                    if resource.isStale() { Text("Previous snapshot · check the source for current details").font(.caption).foregroundStyle(ForgeTheme.muted) }
                                    Button("Open on GitHub ↗") { model.openExternal(resource.url) }.buttonStyle(.link)
                                }.frame(minHeight: 160, alignment: .top)
                            }
                        }
                    }
                } else if let error = model.resourceCatalogError {
                    Text(error).font(.callout).foregroundStyle(ForgeTheme.muted)
                }
                Text("Official learning references").font(.title2.bold())
                if let curriculum = model.curriculum {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], alignment: .leading, spacing: 14) {
                        ForEach(curriculum.resources.filter { query.isEmpty || ($0.title + " " + $0.topic).localizedCaseInsensitiveContains(query) }) { resource in
                            ForgeCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Eyebrow(text: resource.topic)
                                    Text(resource.title).font(.system(size: 17, weight: .semibold))
                                    Text(resource.description).font(.system(size: 12)).foregroundStyle(ForgeTheme.muted).lineLimit(4)
                                    Button("Open \(resource.provider) ↗") { model.openExternal(resource.url) }.buttonStyle(.link)
                                }.frame(minHeight: 140, alignment: .top)
                            }
                        }
                    }
                    Text("Competition practice").font(.title2.bold())
                    Text("Read the statement and submit your own solution on the original platform. Difficulty labels are curriculum guidance.").foregroundStyle(ForgeTheme.muted)
                    ForEach(curriculum.problems.filter { query.isEmpty || ($0.title + " " + $0.topic + " " + $0.platform).localizedCaseInsensitiveContains(query) }) { problem in
                        Button { model.openExternal(problem.url) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) { Text(problem.title).font(.headline); Text(problem.topic).font(.caption).foregroundStyle(ForgeTheme.muted) }
                                Spacer(); Text(problem.platform + " · " + problem.difficulty).font(.caption).foregroundStyle(ForgeTheme.violet); Image(systemName: "arrow.up.right")
                            }.padding(18).background(ForgeTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(32).frame(maxWidth: 1200)
        }
        .onChange(of: model.resourceCatalog?.categories.map(\.id) ?? []) { _, categories in
            if !catalogCategory.isEmpty && !categories.contains(catalogCategory) { catalogCategory = "" }
        }
    }
}
