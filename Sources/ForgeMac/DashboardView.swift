import SwiftUI
import ForgeCore

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "A workspace for your ambition")
                        Text("Think deeply.\nBuild boldly.").font(.system(size: 49, weight: .bold, design: .rounded))
                            .foregroundStyle(ForgeTheme.ink)
                        Text("Turn your curiosity into code, one deliberate session at a time.")
                            .font(.system(size: 14)).foregroundStyle(ForgeTheme.muted)
                    }
                    Spacer()
                    Text(Date.now.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ForgeTheme.muted).padding(.top, 4)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 14) {
                    Metric(value: "\(model.progress.completedModuleIDs.count)/\(model.curriculum?.modules.count ?? 50)", label: "MODULES REVIEWED", symbol: "checkmark.circle")
                    Metric(value: "\(model.progress.totalMinutes / 60)h \(model.progress.totalMinutes % 60)m", label: "PRACTICE LOGGED", symbol: "clock")
                    Metric(value: "\(model.progress.minutes(on: Date())) min", label: "TODAY'S PRACTICE", symbol: "sun.max")
                    Metric(value: "\(model.progress.sessions.count)", label: "STUDY SESSIONS", symbol: "square.stack")
                }
                HStack(alignment: .top, spacing: 18) {
                    ForgeCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Eyebrow(text: "Your learning world"); Spacer(); Text("10 CHAPTERS").font(.system(size: 9, design: .monospaced)).foregroundStyle(ForgeTheme.violet) }
                            LearningWorld(completed: model.progress.completedModuleIDs.count).frame(height: 230)
                            Text("From first principles to working software").font(.system(size: 17, weight: .semibold))
                            Text("Python · C++ · Git · algorithms · software engineering")
                                .font(.system(size: 12)).foregroundStyle(ForgeTheme.muted)
                            Button("Explore the learning path →") { model.destination = .curriculum }.buttonStyle(.link)
                        }
                    }
                    VStack(spacing: 18) {
                        ForgeCard(color: Color(red: 0.95, green: 0.93, blue: 0.88)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("UP NEXT").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                                Text(model.nextModule?.title ?? "Revisit and refine").font(.system(size: 23, weight: .bold, design: .rounded))
                                Text(model.nextModule?.project ?? "Choose a module and deepen your understanding with a new example.")
                                    .font(.system(size: 12)).lineSpacing(3)
                                Button("Continue learning") {
                                    if let next = model.nextModule { model.openModule(next.id) } else { model.destination = .curriculum }
                                }.buttonStyle(PrimaryButtonStyle())
                            }.foregroundStyle(ForgeTheme.background)
                        }
                        ForgeCard(color: Color(red: 0.19, green: 0.15, blue: 0.34)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Eyebrow(text: "Today's intention")
                                Text(model.progress.dailyFocus.isEmpty ? "What will you build today?" : model.progress.dailyFocus)
                                    .font(.system(size: 15, weight: .medium)).lineLimit(3)
                                Button("Open your journal →") { model.destination = .journal }.buttonStyle(.link)
                            }
                        }
                    }.frame(width: 275)
                }
                ForgeCard {
                    HStack(spacing: 18) {
                        Image(systemName: "terminal.fill").font(.system(size: 30)).foregroundStyle(ForgeTheme.red)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Put an idea to work.").font(.title3.bold())
                            Text("Open Python missions, the Git playground, project editors, and competition practice.")
                                .foregroundStyle(ForgeTheme.muted).font(.system(size: 12))
                        }
                        Spacer()
                        Button("Open labs") { model.destination = .labs }.buttonStyle(PrimaryButtonStyle())
                    }
                }
                Text("A reviewed module is a learning record. Mastery comes from solving new problems, testing your work, and explaining it.")
                    .font(.system(size: 11)).foregroundStyle(ForgeTheme.muted)
            }.padding(32).frame(maxWidth: 1280)
        }
    }
}

private struct Metric: View {
    let value: String
    let label: String
    let symbol: String
    var body: some View {
        ForgeCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(ForgeTheme.red)
                Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(ForgeTheme.muted)
            }
        }
    }
}

private struct LearningWorld: View {
    let completed: Int
    var body: some View {
        Canvas { context, size in
            let positions: [(Double, Double)] = [(0.12,0.76),(0.28,0.59),(0.47,0.74),(0.64,0.55),(0.82,0.72),(0.87,0.35),(0.69,0.19),(0.50,0.37),(0.34,0.19),(0.13,0.34)]
            let points = positions.map { CGPoint(x: size.width * $0.0, y: size.height * $0.1) }
            var route = Path()
            for (index, point) in points.enumerated() {
                if index == 0 { route.move(to: point) } else { route.addLine(to: point) }
            }
            context.stroke(route, with: .color(ForgeTheme.violet.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [4,5]))
            for (index, point) in points.enumerated() {
                let width = min(25.0, size.width / 16)
                let height = 13.0
                let top = [CGPoint(x:point.x,y:point.y-height), CGPoint(x:point.x+width,y:point.y), CGPoint(x:point.x,y:point.y+height), CGPoint(x:point.x-width,y:point.y)]
                let lower = top.map { CGPoint(x:$0.x,y:$0.y+17) }
                var left = Path(); left.addLines([top[3],top[2],lower[2],lower[3]]); left.closeSubpath()
                var right = Path(); right.addLines([top[2],top[1],lower[1],lower[2]]); right.closeSubpath()
                var tile = Path(); tile.addLines(top); tile.closeSubpath()
                let color = index <= completed / 5 ? ForgeTheme.red : ForgeTheme.violet
                context.fill(left, with: .color(color.opacity(0.2)))
                context.fill(right, with: .color(color.opacity(0.4)))
                context.fill(tile, with: .color(color.opacity(index == completed / 5 ? 1 : 0.55)))
                context.draw(Text(String(format:"%02d",index+1)).font(.system(size:9,weight:.bold,design:.monospaced)).foregroundColor(ForgeTheme.ink), at: CGPoint(x:point.x,y:point.y+39))
            }
        }.accessibilityLabel("Ten chapters in the learning path. \(completed) modules reviewed.")
    }
}
