import SwiftUI

struct UnreadDotView: View {
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: max(1, size * 0.18))
            )
            .accessibilityHidden(true)
    }
}
