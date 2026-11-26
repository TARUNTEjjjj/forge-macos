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
                    Metric(value: "\(model.reviewedModuleCount)/\(model.curriculum?.modules.count ?? 50)", label: "MODULES REVIEWED", symbol: "checkmark.circle")
                    Metric(value: "\(model.progress.totalMinutes / 60)h \(model.progress.totalMinutes % 60)m", label: "PRACTICE LOGGED", symbol: "clock")
                    Metric(value: "\(model.minutes(on: [Date()]).first ?? 0) min", label: "TODAY'S PRACTICE", symbol: "sun.max")
                    Metric(value: "\(model.progress.sessions.count)", label: "STUDY SESSIONS", symbol: "square.stack")
                }
                HStack(alignment: .top, spacing: 18) {
                    ForgeCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Eyebrow(text: "Your learning world"); Spacer(); Text("10 CHAPTERS").font(.system(size: 9, design: .monospaced)).foregroundStyle(ForgeTheme.violet) }
                            LearningWorld(chapters: model.chapterStatuses, completed: model.reviewedModuleCount).frame(height: 230)
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
    let chapters: [ChapterStatus]
    let completed: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var yawOffset: Double = 0
    @ViewState private var pitchDegrees: Double = 24
    @ViewState private var isDragging = false

    private static let baseCoords: [(Double, Double, Double)] = [
        (-0.82, -0.05, 0.56), (-0.48, 0.14, 0.26), (-0.12, -0.02, 0.52),
        (0.24, 0.18, 0.18), (0.68, -0.04, 0.48), (0.78, 0.16, -0.34),
        (0.38, 0.24, -0.62), (0.02, 0.06, -0.26), (-0.36, 0.22, -0.58), (-0.76, 0.12, -0.28)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || isDragging)) { timeline in
            let elapsed = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            let autoYaw = elapsed * 0.22 + yawOffset
            let pulse = 0.5 + 0.5 * sin(elapsed * 2.4)
            let pitchRad = (reduceMotion ? 24.0 : pitchDegrees) * .pi / 180.0

            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    let scale = min(size.width, size.height) * 0.37
                    let cx = size.width * 0.5
                    let cy = size.height * 0.52
                    let cosY = cos(autoYaw)
                    let sinY = sin(autoYaw)
                    let cosP = cos(pitchRad)
                    let sinP = sin(pitchRad)

                    func project(_ p: (Double, Double, Double)) -> (pt: CGPoint, depth: Double) {
                        let rx = p.0 * cosY - p.2 * sinY
                        let rz = p.0 * sinY + p.2 * cosY
                        let ry = p.1 * cosP - rz * sinP
                        let depth = p.1 * sinP + rz * cosP + 3.2
                        let persp = 3.1 / max(0.8, depth)
                        return (CGPoint(x: cx + rx * scale * persp, y: cy - ry * scale * persp), depth)
                    }

                    // Orbital equatorial reference ring
                    var orbit = Path()
                    for step in 0...48 {
                        let ang = (Double(step) / 48.0) * 2.0 * .pi
                        let p = project((cos(ang) * 0.96, -0.14, sin(ang) * 0.72)).pt
                        if step == 0 { orbit.move(to: p) } else { orbit.addLine(to: p) }
                    }
                    context.stroke(orbit, with: .color(.white.opacity(0.09)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                    let projected = Self.baseCoords.enumerated().map { idx, coord -> (idx: Int, center: CGPoint, depth: Double, top: [CGPoint], bot: [CGPoint]) in
                        let c = project(coord)
                        let hw = 0.13, hh = 0.11
                        let tPts = [(-hw, 0.0, -hh), (hw, 0.0, -hh), (hw, 0.0, hh), (-hw, 0.0, hh)].map { d in
                            project((coord.0 + d.0, coord.1 + d.1, coord.2 + d.2)).pt
                        }
                        let bPts = [(-hw, -0.11, -hh), (hw, -0.11, -hh), (hw, -0.11, hh), (-hw, -0.11, hh)].map { d in
                            project((coord.0 + d.0, coord.1 + d.1, coord.2 + d.2)).pt
                        }
                        return (idx, c.pt, c.depth, tPts, bPts)
                    }

                    // 3D learning route spline
                    var route = Path()
                    for (idx, item) in projected.enumerated() {
                        if idx == 0 { route.move(to: item.center) } else { route.addLine(to: item.center) }
                    }
                    context.stroke(route, with: .color(ForgeTheme.violet.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [5, 5], dashPhase: reduceMotion ? 0 : -elapsed * 18))

                    // Painter-sorted 3D extruded isometric chapter prisms
                    for item in projected.sorted(by: { $0.depth > $1.depth }) {
                        let status = chapters.indices.contains(item.idx) ? chapters[item.idx] : .upcoming
                        let accent = status == .complete ? ForgeTheme.mint : (status == .current ? ForgeTheme.red : ForgeTheme.violet)

                        var front = Path()
                        front.addLines([item.top[3], item.top[2], item.bot[2], item.bot[3]])
                        front.closeSubpath()
                        var side = Path()
                        side.addLines([item.top[2], item.top[1], item.bot[1], item.bot[2]])
                        side.closeSubpath()
                        var cap = Path()
                        cap.addLines(item.top)
                        cap.closeSubpath()

                        context.fill(front, with: .color(accent.opacity(0.28)))
                        context.fill(side, with: .color(accent.opacity(0.48)))
                        context.fill(cap, with: .color(accent.opacity(status == .current ? (0.78 + 0.2 * pulse) : (status == .complete ? 0.85 : 0.56))))
                        context.stroke(cap, with: .color(.white.opacity(status == .current ? 0.85 : 0.25)), lineWidth: 1)

                        context.draw(
                            Text(String(format: "%02d", item.idx + 1))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(ForgeTheme.ink),
                            at: CGPoint(x: item.center.x, y: item.center.y + 22)
                        )
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { val in
                            isDragging = true
                            yawOffset = val.translation.width * 0.012
                            pitchDegrees = max(8.0, min(52.0, 24.0 + val.translation.height * 0.14))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .accessibilityLabel("Interactive 3D constellation of ten chapters in the learning path. \(completed) module\(completed == 1 ? "" : "s") reviewed.")

                Text(reduceMotion ? "3D STATIC" : "3D ORBIT · DRAG")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(ForgeTheme.mint)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            }
        }
    }
}
