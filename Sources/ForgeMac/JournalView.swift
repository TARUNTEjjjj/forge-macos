import SwiftUI
import ForgeCore

struct JournalView: View {
    @EnvironmentObject var model: AppModel
    @ViewState<UUID?> private var deleteSession = nil
    private var dates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
    var body: some View {
        let displayedDates = dates
        let dailyMinutes = model.progress.minutes(on: displayedDates)
        let peak = max(1, dailyMinutes.max() ?? 1)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "Make the practice visible", title: "Your practice journal", subtitle: "Choose a focus. Do the work. Record the evidence. Time logged here is your own record, separate from online lab progress.")
                ForgeCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: "Today's intention")
                        TextField("For example: implement BFS and explain why it finds shortest paths", text: $model.focusDraft).textFieldStyle(.roundedBorder)
                            .disabled(model.readOnly)
                        HStack {
                            Text("One specific outcome is enough.").font(.caption).foregroundStyle(ForgeTheme.muted)
                            Spacer()
                            Button("Save focus") { model.update { $0.dailyFocus = model.focusDraft } }.buttonStyle(PrimaryButtonStyle())
                                .disabled(model.readOnly || model.focusDraft == model.progress.dailyFocus || model.focusDraft.utf8.count > 2_000)
                        }
                    }
                }
                ForgeCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Eyebrow(text: "The last seven days")
                        HStack(alignment: .bottom, spacing: 16) {
                            ForEach(Array(displayedDates.enumerated()), id: \.element) { index, date in
                                let value = dailyMinutes[index]
                                VStack(spacing: 8) {
                                    Text("\(value)m").font(.system(size: 11, design: .monospaced)).foregroundStyle(ForgeTheme.muted)
                                    RoundedRectangle(cornerRadius: 6).fill(Calendar.current.isDateInToday(date) ? ForgeTheme.red : ForgeTheme.violet.opacity(0.55))
                                        .frame(height: max(3, Double(value) / Double(peak) * 95))
                                    Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption)
                                }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(value) minute\(value == 1 ? "" : "s")")
                            }
                        }.frame(height: 145, alignment: .bottom)
                    }
                }
                ForgeCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Record a session").font(.title3.bold())
                        HStack(spacing: 20) {
                            Stepper("\(model.sessionMinutesDraft) minute\(model.sessionMinutesDraft == 1 ? "" : "s")", value: $model.sessionMinutesDraft, in: 1...720, step: 5).frame(width: 190)
                            Picker("Lesson", selection: $model.sessionModuleIDDraft) {
                                Text("Independent practice").tag("")
                                ForEach(model.curriculum?.modules ?? []) { module in Text(module.title).tag(module.id) }
                            }
                        }
                        Text("What did you build, test, or understand better?").font(.caption).foregroundStyle(ForgeTheme.muted)
                        TextEditor(text: $model.sessionReflectionDraft).font(.system(size: 14)).frame(minHeight: 110)
                            .scrollContentBackground(.hidden).padding(10).background(ForgeTheme.background, in: RoundedRectangle(cornerRadius: 10))
                        HStack {
                            Text("\(model.sessionReflectionDraft.utf8.count)/20,000 bytes").font(.caption2).foregroundStyle(ForgeTheme.muted)
                            Spacer()
                            Button("Save study session") {
                                if model.update({ $0.sessions.append(StudySession(minutes: model.sessionMinutesDraft, reflection: model.sessionReflectionDraft.trimmingCharacters(in: .whitespacesAndNewlines), moduleID: model.sessionModuleIDDraft.isEmpty ? nil : model.sessionModuleIDDraft)) }) {
                                    model.sessionReflectionDraft = ""
                                }
                            }.buttonStyle(PrimaryButtonStyle()).disabled(model.readOnly || model.sessionReflectionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.sessionReflectionDraft.utf8.count > 20_000)
                        }
                    }.disabled(model.readOnly)
                }
                HStack { Text("Recent sessions").font(.title2.bold()); Spacer(); Button("Export backup…") { model.exportBackup() }.disabled(model.readOnly); Button("Restore backup…") { model.chooseBackup() } }
                if model.progress.sessions.isEmpty {
                    EmptyMessage(icon: "pencil.and.outline", title: "Your first session starts the story", detail: "A useful reflection names the problem, the approach you tried, and what the result taught you.")
                }
                ForEach(model.progress.sessions.sorted(by: { $0.date > $1.date })) { session in
                    ForgeCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("\(session.minutes) minute\(session.minutes == 1 ? "" : "s")", systemImage: "clock").font(.headline)
                                Spacer()
                                Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(ForgeTheme.muted)
                                Button { deleteSession = session.id } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Remove this session").disabled(model.readOnly)
                            }
                            if let id = session.moduleID, let module = model.curriculum?.modules.first(where: { $0.id == id }) {
                                Button(module.title) { model.openModule(id) }.buttonStyle(.link)
                            }
                            Text(session.reflection).lineSpacing(4).textSelection(.enabled)
                        }
                    }
                }
            }.padding(32).frame(maxWidth: 1150)
        }
        .confirmationDialog("Remove this study session?", isPresented: Binding(get: { deleteSession != nil }, set: { if !$0 { deleteSession = nil } })) {
            Button("Remove session", role: .destructive) {
                if let id = deleteSession { model.update { $0.sessions.removeAll { $0.id == id } } }
                deleteSession = nil
            }
            Button("Cancel", role: .cancel) { deleteSession = nil }
        }
    }
}
