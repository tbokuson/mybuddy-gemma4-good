import SwiftUI

// MARK: - FlowLayout（タグ等の折り返し表示用）

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, position) in arrange(proposal: proposal, subviews: subviews).positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}

// MARK: - Theme

enum QuietNativeTheme {
    static let accent = Color(red: 233 / 255, green: 130 / 255, blue: 39 / 255)
    static let accentSoft = Color(red: 1.0, green: 240 / 255, blue: 226 / 255)
    static let background = Color(red: 246 / 255, green: 240 / 255, blue: 232 / 255)
    static let backgroundWarm = Color(red: 255 / 255, green: 248 / 255, blue: 241 / 255)
    static let surface = Color(red: 1.0, green: 249 / 255, blue: 244 / 255)
    static let surfaceAlt = Color(red: 243 / 255, green: 236 / 255, blue: 228 / 255)
    static let primaryText = Color(red: 49 / 255, green: 39 / 255, blue: 31 / 255)
    static let secondaryText = Color(red: 115 / 255, green: 102 / 255, blue: 91 / 255)
    static let line = Color(red: 229 / 255, green: 212 / 255, blue: 195 / 255)

    static let pageGradient = LinearGradient(
        colors: [
            backgroundWarm,
            background
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 248 / 255, blue: 238 / 255),
            Color(red: 250 / 255, green: 237 / 255, blue: 220 / 255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let tabBarClearance: CGFloat = 92
}

extension View {
    func quietNativeCard(
        cornerRadius: CGFloat = 26,
        fill: Color = QuietNativeTheme.surface,
        stroke: Color = QuietNativeTheme.line
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 18, y: 8)
    }

    func quietNativeGlass(cornerRadius: CGFloat = 28) -> some View {
        background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 20, y: 10)
    }

    func quietNativeTabBarClearance(extra: CGFloat = 0) -> some View {
        safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: QuietNativeTheme.tabBarClearance + extra)
                .allowsHitTesting(false)
        }
    }
}
