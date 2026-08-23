import SwiftUI

struct SkeletonRow: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 16)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 12)
                .frame(width: 180)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
                .frame(height: 10)
                .frame(width: 120)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
        .shimmering(active: !reduceMotion)
    }
}

struct ShimmerModifier: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if active {
            content
                .overlay(
                    LinearGradient(gradient: Gradient(colors: [.clear, .white.opacity(0.4), .clear]),
                                   startPoint: .leading, endPoint: .trailing)
                        .offset(x: phase)
                        .mask(content)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 300
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func shimmering(active: Bool) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let actionTitle, let action {
                Button(actionTitle) {
                    SoundManager.playTap()
                    HapticsManager.lightImpact()
                    action()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
