import SwiftUI

struct IntroView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    @State private var currentPage = 0
    private let totalPages = 5

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button {
                        onSkip()
                    } label: {
                        Text("Skip")
                            .font(Design.Typography.subheadline)
                            .foregroundStyle(Design.Colors.textTertiary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .accessibilityLabel("Skip introduction")
                    .accessibilityIdentifier("intro_skip_button")
                }
                .padding(.top, 8)
                .padding(.trailing, 12)

                // Paged content
                TabView(selection: $currentPage) {
                    IntroScreen1()
                        .tag(0)
                    IntroScreen2()
                        .tag(1)
                    IntroScreen3()
                        .tag(2)
                    IntroScreen4()
                        .tag(3)
                    IntroScreen5()
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page indicator and navigation
                VStack(spacing: 24) {
                    PageIndicator(currentPage: currentPage, totalPages: totalPages)

                    navigationButtons
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentPage > 0 {
                Button {
                    withAnimation {
                        currentPage -= 1
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(Design.Typography.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .secondary))
                .accessibilityLabel("Go back to previous screen")
            }

            Button {
                if currentPage < totalPages - 1 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    onStart()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(currentPage < totalPages - 1 ? "Next" : "Get Started")
                        .font(Design.Typography.headline)
                    Image(systemName: currentPage < totalPages - 1 ? "chevron.right" : "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .accessibilityLabel(currentPage < totalPages - 1 ? "Go to next screen" : "Start game setup")
            .accessibilityIdentifier(currentPage < totalPages - 1 ? "intro_next_button" : "intro_start_button")
        }
    }
}

// MARK: - Page Indicator

private struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Design.Colors.brandGold : Design.Colors.surface2)
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(totalPages)")
    }
}

// MARK: - Screen 1: Welcome to Mafia

private struct IntroScreen1: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 20)

                // Hero icon
                VStack(spacing: 20) {
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Design.Colors.glowGold, radius: 20)
                        .accessibilityLabel("Mafia game icon")

                    VStack(spacing: 12) {
                        Text("Welcome to")
                            .font(Design.Typography.title2)
                            .foregroundStyle(Design.Colors.textSecondary)

                        Text("Mafia Manager")
                            .font(Design.Typography.largeTitle)
                            .fontWeight(.heavy)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .tracking(1)

                        Text("Your AI-powered game host")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textTertiary)
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 20) {
                    InfoCard(
                        icon: "person.3.fill",
                        title: "What is Mafia?",
                        description: "A social deduction game where citizens try to identify hidden Mafia members before it's too late.",
                        gradientColors: Design.Colors.citizenGradient
                    )

                    InfoCard(
                        icon: "moon.stars.fill",
                        title: "Two Teams Battle",
                        description: "Mafia works in darkness to eliminate citizens. Citizens use logic and voting to find the Mafia.",
                        gradientColors: Design.Colors.policeGradient
                    )

                    InfoCard(
                        icon: "brain.head.profile",
                        title: "Deception & Deduction",
                        description: "Bluff, investigate, and debate. Every choice matters. Trust no one.",
                        gradientColors: Design.Colors.mafiaGradient
                    )
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Screen 2: Your AI Host

private struct IntroScreen2: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 20)

                VStack(spacing: 16) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.actionBlue, Design.Colors.actionBlueBright],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Design.Colors.glowBlue, radius: 20)

                    Text("Your Personal Game Master")
                        .font(Design.Typography.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundStyle(Design.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Never worry about hosting again")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("What I Do For You")
                        .font(Design.Typography.title3)
                        .foregroundStyle(Design.Colors.textPrimary)
                        .padding(.top, 8)

                    FeatureRow(
                        icon: "shuffle",
                        title: "Assign Roles Secretly",
                        description: "Each player sees only their role on the device"
                    )

                    FeatureRow(
                        icon: "speaker.wave.3.fill",
                        title: "Voice Narration",
                        description: "I guide players through each phase with audio cues"
                    )

                    FeatureRow(
                        icon: "clock.badge.checkmark",
                        title: "Manage Timing",
                        description: "Wake up roles in order, track actions automatically"
                    )

                    FeatureRow(
                        icon: "doc.text.fill",
                        title: "Keep Event Logs",
                        description: "Every action is recorded so you can review after"
                    )

                    FeatureRow(
                        icon: "arrow.clockwise",
                        title: "Quick Replays",
                        description: "Restart with the same players in one tap"
                    )
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Screen 3: Night Phase

private struct IntroScreen3: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 20)

                VStack(spacing: 16) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: Design.Colors.policeGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Design.Colors.glowBlue, radius: 20)

                    Text("Night Phase")
                        .font(Design.Typography.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Roles wake up one by one")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Meet the Roles")
                        .font(Design.Typography.title3)
                        .foregroundStyle(Design.Colors.textPrimary)
                        .padding(.top, 8)

                    RoleDetailCard(
                        role: .mafia,
                        action: "Choose a citizen to eliminate",
                        goal: "Eliminate all citizens without being caught",
                        gradientColors: Design.Colors.mafiaGradient
                    )

                    RoleDetailCard(
                        role: .doctor,
                        action: "Save one player from elimination",
                        goal: "Protect citizens and survive",
                        gradientColors: Design.Colors.doctorGradient
                    )

                    RoleDetailCard(
                        role: .inspector,
                        action: "Investigate one player's role",
                        goal: "Find the Mafia and guide citizens",
                        gradientColors: Design.Colors.policeGradient
                    )

                    RoleDetailCard(
                        role: .citizen,
                        action: "Sleep (no night action)",
                        goal: "Use voting and logic to find Mafia",
                        gradientColors: Design.Colors.citizenGradient
                    )
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Screen 4: Morning & Day

private struct IntroScreen4: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 20)

                VStack(spacing: 16) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Design.Colors.glowGold, radius: 20)

                    Text("Morning & Day")
                        .font(Design.Typography.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Discover, discuss, and decide")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    PhaseCard(
                        icon: "sunrise.fill",
                        phase: "Morning",
                        description: "See if anyone was eliminated overnight. I'll announce the results and show what happened.",
                        color: Design.Colors.brandGold,
                        gradientColors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                        details: [
                            "Check who was eliminated (if anyone)",
                            "Doctor save revealed if successful",
                            "Review the event log for clues"
                        ]
                    )

                    PhaseCard(
                        icon: "sun.max.fill",
                        phase: "Day (Discussion)",
                        description: "The town debates and votes. Use your words, your logic, and your suspicions wisely.",
                        color: Design.Colors.dangerRed,
                        gradientColors: Design.Colors.mafiaGradient,
                        details: [
                            "Discuss suspicions as a group",
                            "Vote to eliminate one player",
                            "Majority vote decides who goes"
                        ]
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(Design.Colors.brandGold)
                        Text("How to Win")
                            .font(Design.Typography.headline)
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                    .padding(.top, 8)

                    WinConditionRow(
                        team: "Citizens Win",
                        condition: "Eliminate all Mafia members",
                        color: Design.Colors.successGreen
                    )

                    WinConditionRow(
                        team: "Mafia Wins",
                        condition: "Equal or outnumber the citizens",
                        color: Design.Colors.dangerRed
                    )
                }
                .cardStyle(padding: 16)

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Screen 5: Tips & Get Started

private struct IntroScreen5: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 20)

                VStack(spacing: 16) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Design.Colors.glowGold, radius: 20)

                    Text("Ready to Play?")
                        .font(Design.Typography.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Here are some pro tips")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Pro Tips")
                        .font(Design.Typography.title3)
                        .foregroundStyle(Design.Colors.textPrimary)
                        .padding(.top, 8)

                    TipCard(
                        number: 1,
                        tip: "Pass the device around during role reveal. Keep roles secret!",
                        icon: "eye.slash.fill"
                    )

                    TipCard(
                        number: 2,
                        tip: "Pay attention to who speaks and how they vote. Patterns reveal truth.",
                        icon: "chart.line.uptrend.xyaxis"
                    )

                    TipCard(
                        number: 3,
                        tip: "Use the event log after the game to see what really happened.",
                        icon: "doc.text.magnifyingglass"
                    )

                    TipCard(
                        number: 4,
                        tip: "Don't rush! Good discussion leads to better deduction.",
                        icon: "bubble.left.and.bubble.right.fill"
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Design.Colors.actionBlue)
                        Text("Best Experience")
                            .font(Design.Typography.headline)
                            .foregroundStyle(Design.Colors.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        BestPracticeRow(text: "Play with 5-12 players for balanced gameplay")
                        BestPracticeRow(text: "Use headphones for clear voice narration")
                        BestPracticeRow(text: "Sit in a circle so everyone can see each other")
                    }
                }
                .cardStyle(padding: 16)

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Supporting Components

private struct InfoCard: View {
    let icon: String
    let title: String
    let description: String
    let gradientColors: [Color]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
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
            .shadow(color: gradientColors.first?.opacity(0.4) ?? .clear, radius: 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(description)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Design.Colors.brandGold)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(description)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct RoleDetailCard: View {
    let role: Role
    let action: String
    let goal: String
    let gradientColors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(String(role.displayName.prefix(1)))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: gradientColors.first?.opacity(0.4) ?? .clear, radius: 6)

                Text(role.displayName)
                    .font(Design.Typography.title3)
                    .foregroundStyle(Design.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.textTertiary)
                        .frame(width: 20)
                    Text(action)
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.textSecondary)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "target")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.textTertiary)
                        .frame(width: 20)
                    Text(goal)
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            }
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct PhaseCard: View {
    let icon: String
    let phase: String
    let description: String
    let color: Color
    let gradientColors: [Color]
    let details: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: color.opacity(0.4), radius: 8)

                Text(phase)
                    .font(Design.Typography.title3)
                    .foregroundStyle(Design.Colors.textPrimary)
            }

            Text(description)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(color)
                            .frame(width: 16)
                        Text(detail)
                            .font(Design.Typography.footnote)
                            .foregroundStyle(Design.Colors.textTertiary)
                    }
                }
            }
        }
        .cardStyle(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

private struct WinConditionRow: View {
    let team: String
    let condition: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(team)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)
                Text(condition)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TipCard: View {
    let number: Int
    let tip: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Design.Colors.surface2)
                    .frame(width: 32, height: 32)

                Text("\(number)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.Colors.brandGold)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.brandGold)

                    Text(tip)
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.medium)
        .accessibilityElement(children: .combine)
    }
}

private struct BestPracticeRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Design.Colors.successGreen)
                .frame(width: 16)

            Text(text)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.textSecondary)
        }
    }
}

// MARK: - Preview

#Preview {
    IntroView(
        onStart: { print("Start tapped") },
        onSkip: { print("Skip tapped") }
    )
}
