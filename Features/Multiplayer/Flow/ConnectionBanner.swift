import SwiftUI

/// A subscription or sign-in problem shown above the multiplayer game screens.
struct ConnectionBanner: View {
    let message: String
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .accessibilityHidden(true)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .fontWeight(.bold)
                    .foregroundStyle(Design.Colors.brandGold)
            }
        }
        .font(Design.Typography.footnote)
        .foregroundStyle(Design.Colors.textPrimary)
        .padding(12)
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.medium)
        .padding(.horizontal, 16)
    }
}
