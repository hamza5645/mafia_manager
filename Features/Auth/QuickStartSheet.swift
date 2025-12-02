import SwiftUI

/// Bottom sheet presented when unauthenticated user tries to play online
/// Offers choice between playing as guest or signing in/creating account
struct QuickStartSheet: View {
    let onGuestSelected: () -> Void
    let onSignInSelected: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Ready to play online?")
                .font(Design.Typography.title2)
                .foregroundStyle(Design.Colors.textPrimary)
                .padding(.top, 24)

            // Options
            VStack(spacing: 16) {
                // Play as Guest - Primary CTA
                Button(action: onGuestSelected) {
                    HStack {
                        Image(systemName: "play.fill")
                            .font(Design.Typography.callout)
                            .fontWeight(.semibold)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Play as Guest")
                                .font(Design.Typography.body)
                                .fontWeight(.semibold)

                            Text("Start playing instantly")
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.surface0.opacity(0.8))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(Design.Typography.footnote)
                            .fontWeight(.semibold)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Design.Colors.surface0)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Design.Colors.brandGold)
                    .cornerRadius(Design.Radii.medium)
                }
                .accessibilityLabel("Play as Guest. Start playing instantly")

                // Sign In / Create Account - Secondary CTA
                Button(action: onSignInSelected) {
                    HStack {
                        Image(systemName: "person.fill")
                            .font(Design.Typography.callout)
                            .fontWeight(.semibold)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign In / Create Account")
                                .font(Design.Typography.body)
                                .fontWeight(.medium)

                            Text("Sync stats across devices")
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(Design.Typography.footnote)
                            .fontWeight(.medium)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Design.Colors.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Design.Colors.surface1)
                    .cornerRadius(Design.Radii.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radii.medium)
                            .stroke(Design.Colors.stroke.opacity(0.3), lineWidth: 1)
                    )
                }
                .accessibilityLabel("Sign in or create account. Sync stats across devices")
            }
            .padding(.horizontal, 20)

            // Reassurance text
            Text("Your game stats will be saved and can be linked to an account anytime.")
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Design.Colors.surface0)
    }
}

#Preview {
    QuickStartSheet(
        onGuestSelected: {},
        onSignInSelected: {}
    )
    .preferredColorScheme(.dark)
}
