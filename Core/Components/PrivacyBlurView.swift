import SwiftUI

struct PrivacyBlurView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 50

    var body: some View {
        ZStack {
            // Full-screen blur
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Design.Colors.surface2,
                                    Design.Colors.surface1
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundStyle(Design.Colors.textSecondary)
                }

                // Text
                VStack(spacing: 12) {
                    Text("Passing Phone...")
                        .font(Design.Typography.title2)
                        .foregroundColor(Design.Colors.textPrimary)

                    Text("Keep your role secret")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.textSecondary)
                }
            }
        }
    }
}
