import SwiftUI

struct IntroView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(title: "How It Works", icon: "clock.fill")
                    timelineCards
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(title: "Meet the Roles", icon: "person.3.fill")
                    roleCards
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(title: "Auto-Host Perks", icon: "sparkles")
                    perksCard
                }

                ctaButtons

                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .background(Design.Colors.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack {
            // Gradient background with glassmorphism
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(Design.Colors.surface1)

                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Design.Colors.brandGold.opacity(0.25),
                                Design.Colors.actionBlue.opacity(0.15),
                                .clear,
                                Design.Colors.dangerRed.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Shimmer effect
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            }

            VStack(spacing: 12) {
                Image(systemName: "theatermasks.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: Design.Colors.glowGold, radius: 16)
                    .accessibilityLabel("Mafia Manager icon")

                Text("Meet Your Mafia Manager")
                    .font(Design.Typography.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Design.Colors.textPrimary, Design.Colors.textSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .multilineTextAlignment(.center)

                Text("Your AI host for seamless Mafia gameplay")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Design.Colors.brandGold.opacity(0.5),
                            Design.Colors.actionBlue.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .shadow(color: Design.Colors.glowGold.opacity(0.3), radius: 20, y: 4)
        .shadow(color: Design.Shadows.large.color, radius: Design.Shadows.large.radius, x: Design.Shadows.large.x, y: Design.Shadows.large.y)
    }

    // MARK: - Timeline Cards

    private var timelineCards: some View {
        VStack(spacing: 12) {
            TimelineCard(
                icon: "moon.stars.fill",
                title: "Night",
                description: "Roles wake up one by one. Mafia chooses, Doctor protects, Police investigates.",
                color: Design.Colors.actionBlue,
                gradientColors: Design.Colors.policeGradient
            )

            TimelineCard(
                icon: "sunrise.fill",
                title: "Morning",
                description: "Discover if anyone was eliminated. Review what happened overnight.",
                color: Design.Colors.brandGold,
                gradientColors: [Design.Colors.brandGold, Design.Colors.brandGoldBright]
            )

            TimelineCard(
                icon: "sun.max.fill",
                title: "Day",
                description: "Town discusses and votes to eliminate a suspect. Strategy matters.",
                color: Design.Colors.dangerRed,
                gradientColors: Design.Colors.mafiaGradient
            )
        }
    }

    // MARK: - Role Cards

    private var roleCards: some View {
        VStack(spacing: 12) {
            RoleCard(
                role: .mafia,
                description: "Eliminate citizens at night without being caught.",
                gradientColors: Design.Colors.mafiaGradient
            )

            RoleCard(
                role: .doctor,
                description: "Save one player each night from elimination.",
                gradientColors: Design.Colors.doctorGradient
            )

            RoleCard(
                role: .inspector,
                description: "Investigate one player each night to learn their role.",
                gradientColors: Design.Colors.policeGradient
            )

            RoleCard(
                role: .citizen,
                description: "Use logic and voting power to find the Mafia.",
                gradientColors: Design.Colors.citizenGradient
            )
        }
    }

    // MARK: - Perks Card

    private var perksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PerkRow(icon: "speaker.wave.3.fill", text: "Voice narration guides each phase")
            PerkRow(icon: "doc.text.fill", text: "Automatic event logs track everything")
            PerkRow(icon: "arrow.clockwise", text: "Quick restart with same players")
        }
        .cardStyle(padding: 20)
    }

    // MARK: - CTA Buttons

    private var ctaButtons: some View {
        VStack(spacing: 16) {
            Button {
                onStart()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Start Setup")
                        .font(Design.Typography.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .accessibilityLabel("Start game setup")
            .accessibilityIdentifier("intro_start_button")

            Button {
                onSkip()
            } label: {
                Text("Skip, I know the rules")
                    .font(Design.Typography.subheadline)
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .accessibilityLabel("Skip introduction")
            .accessibilityIdentifier("intro_skip_button")
        }
        .padding(.top, 8)
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Design.Colors.brandGold)

            Text(title)
                .font(Design.Typography.title3)
                .foregroundStyle(Design.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Timeline Card

private struct TimelineCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let gradientColors: [Color]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: color.opacity(0.4), radius: 8)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(description)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle(padding: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

// MARK: - Role Card

private struct RoleCard: View {
    let role: Role
    let description: String
    let gradientColors: [Color]

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Role badge
            Text(String(role.displayName.prefix(1)))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    Circle()
                        .stroke(gradientColors.first?.opacity(0.5) ?? .clear, lineWidth: 2)
                )
                .shadow(color: gradientColors.first?.opacity(0.4) ?? .clear, radius: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(role.displayName)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(description)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.displayName): \(description)")
    }
}

// MARK: - Perk Row

private struct PerkRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Design.Colors.brandGold)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(text)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    IntroView(
        onStart: { print("Start tapped") },
        onSkip: { print("Skip tapped") }
    )
}
