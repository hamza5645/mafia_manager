import SwiftUI

struct IntroView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    @State private var currentPage = 0
    private let totalPages = 5

    var body: some View {
        GeometryReader { geometry in
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

                    // Custom paging view using offset
                    HStack(spacing: 0) {
                        IntroScreen1()
                            .frame(width: geometry.size.width)

                        IntroScreen2()
                            .frame(width: geometry.size.width)

                        IntroScreen3()
                            .frame(width: geometry.size.width)

                        IntroScreen4()
                            .frame(width: geometry.size.width)

                        IntroScreen5()
                            .frame(width: geometry.size.width)
                    }
                    .offset(x: -CGFloat(currentPage) * geometry.size.width)
                    .frame(width: geometry.size.width, height: geometry.size.height - 200, alignment: .leading)
                    .clipped()
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                let threshold: CGFloat = 50
                                if value.translation.width < -threshold && currentPage < totalPages - 1 {
                                    withAnimation {
                                        currentPage += 1
                                    }
                                } else if value.translation.width > threshold && currentPage > 0 {
                                    withAnimation {
                                        currentPage -= 1
                                    }
                                }
                            }
                    )

                    // Page indicator and navigation
                    VStack(spacing: 20) {
                        PageIndicator(currentPage: currentPage, totalPages: totalPages)

                        navigationButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .background(Design.Colors.surface0)
                }
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
        .frame(height: 56)
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer().frame(height: 20)

                // Hero
                VStack(spacing: 18) {
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Design.Colors.glowGold, radius: 20)

                    VStack(spacing: 8) {
                        Text("Welcome to")
                            .font(Design.Typography.title3)
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

                        Text("Your game host")
                            .font(Design.Typography.callout)
                            .foregroundStyle(Design.Colors.textTertiary)
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    InfoCard(
                        icon: "person.3.fill",
                        title: "What is Mafia?",
                        description: "A social deduction game where citizens identify hidden Mafia members.",
                        color: Design.Colors.actionBlue
                    )

                    InfoCard(
                        icon: "moon.stars.fill",
                        title: "Two Teams Battle",
                        description: "Mafia eliminates citizens at night. Citizens vote to find Mafia by day.",
                        color: Design.Colors.dangerRed
                    )

                    InfoCard(
                        icon: "brain.head.profile",
                        title: "Deception & Deduction",
                        description: "Bluff, investigate, debate. Every choice matters. Trust no one.",
                        color: Design.Colors.brandGold
                    )
                }

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Screen 2: Your AI Host

private struct IntroScreen2: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer().frame(height: 20)

                VStack(spacing: 14) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.actionBlue, Design.Colors.actionBlueBright],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Design.Colors.glowBlue, radius: 20)

                    Text("Your Game Master")
                        .font(Design.Typography.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundStyle(Design.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Never worry about hosting again")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text("What I Do For You")
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.brandGold)

                    FeatureRow(icon: "shuffle", title: "Assign roles secretly")
                    FeatureRow(icon: "speaker.wave.3.fill", title: "Voice narration for each phase")
                    FeatureRow(icon: "clock.badge.checkmark", title: "Manage timing automatically")
                    FeatureRow(icon: "doc.text.fill", title: "Keep detailed event logs")
                    FeatureRow(icon: "arrow.clockwise", title: "Quick replay with same players")
                }
                .cardStyle(padding: 16)

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Screen 3: Game Flow Timeline

private struct IntroScreen3: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer().frame(height: 20)

                VStack(spacing: 14) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Design.Colors.glowGold, radius: 20)

                    Text("Game Flow")
                        .font(Design.Typography.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("The cycle repeats until someone wins")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.textTertiary)
                }

                VStack(spacing: 0) {
                    TimelinePhase(
                        number: 1,
                        icon: "moon.stars.fill",
                        phase: "Night Phase",
                        description: "Roles wake up secretly and take actions",
                        color: Design.Colors.actionBlue
                    )

                    TimelineArrow()

                    TimelinePhase(
                        number: 2,
                        icon: "sunrise.fill",
                        phase: "Morning Phase",
                        description: "Reveal who was eliminated and any saves",
                        color: Design.Colors.brandGold
                    )

                    TimelineArrow()

                    TimelinePhase(
                        number: 3,
                        icon: "sun.max.fill",
                        phase: "Day Phase",
                        description: "Town discusses and votes to eliminate suspect",
                        color: Design.Colors.dangerRed
                    )
                }

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Screen 4: Night Phase Details

private struct IntroScreen4: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer().frame(height: 20)

                VStack(spacing: 14) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 60))
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

                    Text("Roles wake up in order")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.textTertiary)
                }

                VStack(spacing: 12) {
                    RoleRow(role: .mafia, action: "Choose a target to eliminate", order: 1)
                    RoleRow(role: .inspector, action: "Investigate one player's role", order: 2)
                    RoleRow(role: .doctor, action: "Save one player from death", order: 3)
                    RoleRow(role: .citizen, action: "Sleep peacefully (no action)", order: nil)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(Design.Colors.brandGold)
                        Text("Win Conditions")
                            .font(Design.Typography.headline)
                            .foregroundStyle(Design.Colors.textPrimary)
                    }

                    WinRow(team: "Citizens Win", condition: "Eliminate all Mafia", color: Design.Colors.successGreen)
                    WinRow(team: "Mafia Wins", condition: "Equal or outnumber citizens", color: Design.Colors.dangerRed)
                }
                .cardStyle(padding: 14)

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Screen 5: Tips & Get Started

private struct IntroScreen5: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer().frame(height: 20)

                VStack(spacing: 14) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 60))
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
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.textTertiary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Pro Tips")
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.brandGold)

                    TipRow(number: 1, tip: "Pass device during role reveal. Keep roles secret!")
                    TipRow(number: 2, tip: "Pay attention to voting patterns and behavior")
                    TipRow(number: 3, tip: "Review event log after game to see what happened")
                    TipRow(number: 4, tip: "Don't rush! Good discussion = better deduction")
                }
                .cardStyle(padding: 16)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Design.Colors.successGreen)
                        Text("Best Experience")
                            .font(Design.Typography.headline)
                            .foregroundStyle(Design.Colors.textPrimary)
                    }

                    BestPracticeRow(text: "5-12 players for balanced gameplay")
                    BestPracticeRow(text: "Sit in a circle to see everyone")
                }
                .cardStyle(padding: 14)

                Spacer().frame(height: 20)
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
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)

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
        .padding(16)
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.medium)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Design.Colors.brandGold)
                .frame(width: 24)

            Text(title)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.textPrimary)
        }
    }
}

private struct RoleRow: View {
    let role: Role
    let action: String
    let order: Int?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(roleColor)
                    .frame(width: 36, height: 36)

                if let order = order {
                    Text("\(order)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Text(String(role.displayName.prefix(1)))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(role.displayName)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(action)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        }
        .padding(12)
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.medium)
    }

    private var roleColor: Color {
        switch role {
        case .mafia: return Design.Colors.dangerRed
        case .doctor: return Design.Colors.successGreen
        case .inspector: return Design.Colors.actionBlue
        case .citizen: return Design.Colors.textTertiary
        }
    }
}

private struct PhaseCard: View {
    let icon: String
    let phase: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(phase)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(description)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.medium)
    }
}

private struct WinRow: View {
    let team: String
    let condition: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(team)
                    .font(Design.Typography.subheadline)
                    .foregroundStyle(Design.Colors.textPrimary)
                Text(condition)
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        }
    }
}

private struct TipRow: View {
    let number: Int
    let tip: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Design.Colors.brandGold)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Design.Colors.surface2)
                )

            Text(tip)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

private struct TimelinePhase: View {
    let number: Int
    let icon: String
    let phase: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 48, height: 48)

                VStack(spacing: 2) {
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(phase)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(description)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)

            Spacer()
        }
    }
}

private struct TimelineArrow: View {
    var body: some View {
        HStack {
            Rectangle()
                .fill(Design.Colors.surface2)
                .frame(width: 2, height: 24)
                .padding(.leading, 23)

            Spacer()
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
