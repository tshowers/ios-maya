import SwiftUI

/// Ports the color tokens from `marketing-director-session.component.css`
/// (`.maya-screen` custom properties + its `prefers-color-scheme: dark`
/// override) so the native chat screen tracks the same light/dark palette
/// as the web cockpit instead of falling back to system colors.
enum MayaTheme {
    static let accent = Color(light: 0x00BFFF, dark: 0x00BFFF)
    static let background = Color(light: 0xF6F8FA, dark: 0x0D1117)
    static let surface = Color(light: 0xFFFFFF, dark: 0x131C27)
    static let text = Color(light: 0x0F172A, dark: 0xF0F6FF)
    static let muted = Color(light: 0x667085, dark: 0x9AADC1)
    static let border = Color(
        light: UIColor(red: 0xDF / 255, green: 0xE4 / 255, blue: 0xEA / 255, alpha: 1),
        dark: UIColor(red: 0, green: 191 / 255, blue: 1, alpha: 0.18)
    )
    static let userBubbleBackground = Color(
        light: UIColor(red: 0, green: 191 / 255, blue: 1, alpha: 0.10),
        dark: UIColor(red: 0, green: 191 / 255, blue: 1, alpha: 0.12)
    )
    static let userBubbleBorder = Color(
        light: UIColor(red: 0, green: 191 / 255, blue: 1, alpha: 0.20),
        dark: UIColor(red: 0, green: 191 / 255, blue: 1, alpha: 0.28)
    )
}

private extension Color {
    init(light: Int, dark: Int) {
        self.init(UIColor(
            light: UIColor(hex: light),
            dark: UIColor(hex: dark)
        ))
    }

    init(light: UIColor, dark: UIColor) {
        self.init(UIColor(light: light, dark: dark))
    }
}

private extension UIColor {
    convenience init(hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    convenience init(light: UIColor, dark: UIColor) {
        self.init { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

/// Wraps chips onto multiple lines like the web's `flex-wrap`, since
/// SwiftUI's stacks don't wrap on their own.
struct MayaFlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > width, currentRowWidth > 0 {
                totalHeight += currentRowHeight + spacing
                totalWidth = max(totalWidth, currentRowWidth)
                currentRowWidth = 0
                currentRowHeight = 0
            }
            currentRowWidth += size.width + (currentRowWidth > 0 ? spacing : 0)
            currentRowHeight = max(currentRowHeight, size.height)
        }
        totalHeight += currentRowHeight
        totalWidth = max(totalWidth, currentRowWidth)

        return CGSize(width: proposal.width ?? totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += currentRowHeight + spacing
                currentRowHeight = 0
            }
            subview.place(at: origin, proposal: .unspecified)
            origin.x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

/// The three pulsing dots next to "Maya is thinking…" (`.maya-thinking span`
/// + `@keyframes mayaPulse`).
struct MayaThinkingDots: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(MayaTheme.accent)
                    .frame(width: 7, height: 7)
                    .opacity(animate ? 1 : 0.35)
                    .scaleEffect(animate ? 1 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
