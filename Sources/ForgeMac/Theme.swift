import SwiftUI

// Select the property wrapper explicitly so Command Line Tools do not require
// the newer Xcode-only SwiftUI State macro plugin.
typealias ViewState<Value> = SwiftUI.State<Value>

enum ForgeTheme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let panel = Color(red: 0.067, green: 0.094, blue: 0.16)
    static let raised = Color(red: 0.095, green: 0.13, blue: 0.21)
    static let red = Color(red: 1, green: 0.39, blue: 0.47)
    static let action = Color(red: 0.78, green: 0.10, blue: 0.22)
    static let violet = Color(red: 0.67, green: 0.61, blue: 1)
    static let ink = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let muted = Color(red: 0.68, green: 0.73, blue: 0.82)
    static let mint = Color(red: 0.57, green: 0.87, blue: 0.81)
}

struct ForgeCard<Content: View>: View {
    var color: Color = ForgeTheme.panel
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.07)))
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(2).foregroundStyle(ForgeTheme.muted)
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: eyebrow)
            Text(title).font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(ForgeTheme.ink)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(ForgeTheme.muted).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    /// A custom style isn't dimmed for `.disabled` automatically. Without this, a save that
    /// can't run yet looks exactly like one that can, and clicking it silently does nothing.
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 11)
            .foregroundStyle(.white)
            .background(ForgeTheme.action.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct EmptyMessage: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(ForgeTheme.violet)
            Text(title).font(.title3.bold())
            Text(detail).foregroundStyle(ForgeTheme.muted).multilineTextAlignment(.center).frame(maxWidth: 450)
        }.frame(maxWidth: .infinity).padding(42)
    }
}
