import SwiftUI

struct OfflineBanner: View {
    var isOffline: Bool
    var lastFetched: Date?

    var body: some View {
        if isOffline {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                Text("Offline · Showing cached content")
                    .font(.caption.weight(.medium))
                if let date = lastFetched {
                    Text("· Updated \(date.timeAgoDisplay())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.9))
            .clipShape(Capsule())
            .padding(.top, 8)
            .accessibilityLabel("Offline, showing cached content")
        }
    }
}
