import SwiftUI

struct MultiplayerRoleRevealView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    let currentPlayerIndex: Int
    
    @State private var hasSeen = false
    @State private var isProcessing = false
    @State private var showingEarlyStartConfirmation = false
    @State private var isStartingNight = false
    @State private var startNightError: String?
    
    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            // Scrolls when the role card, teammates and host controls don't fit.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer()

                        roleCard

                        Spacer()

                        bottomControls
                    }
                    .frame(minHeight: proxy.size.height)
                    .readableContentWidth()
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Start the night now?", isPresented: $showingEarlyStartConfirmation) {
            Button("Start Night") { startNight() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(earlyStartMessage)
        }
    }

    @ViewBuilder
    private var roleCard: some View {
        VStack(spacing: 24) {
            if let myRole = multiplayerStore.myRole,
               let myNumber = multiplayerStore.myNumber {

                // Role Icon
                ZStack {
                    Circle()
                        .fill(myRole.accentColor.opacity(0.2))
                        .frame(width: 140, height: 140)

                    Image(systemName: myRole.symbolName)
                        .font(Design.Typography.displayEmoji)
                        .foregroundStyle(myRole.accentColor)
                }
                .accessibilityHidden(true)

                // Role Name
                Text("You are")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textSecondary)

                Text(myRole.displayName.uppercased())
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(myRole.accentColor)
                    .fontWeight(.bold)

                // Number
                VStack(spacing: 8) {
                    Text("Your Number")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.textSecondary)

                    Text("\(myNumber)")
                        .font(Design.Typography.playerNumber)
                        .foregroundStyle(Design.Colors.brandGold)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(Design.Colors.surface1)
                        .cornerRadius(Design.Radii.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radii.large)
                                .stroke(Design.Colors.brandGold.opacity(0.3), lineWidth: 2)
                        )
                }

                // Role Description
                if let description = roleDescription(for: myRole) {
                    Text(description)
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 4)
                }

                // Mafia teammates (if applicable) - centered pills that wrap in large games
                let teammates = myRole == .mafia ? multiplayerStore.mafiaTeammates : []
                if !teammates.isEmpty {
                    VStack(spacing: 12) {
                        Text("Your Mafia Teammates")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textSecondary)

                        // HAMZA-136: Numbers are kept secret - show names only
                        TeammatePills(teammates: teammates)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)
                }

            } else {
                ProgressView()
                    .tint(Design.Colors.brandGold)
            }
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        // Confirm Button (all human players must confirm, including host)
        // Host must mark as seen before they can start the night phase
        if !hasSeen {
            Button {
                markAsSeen()
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("I've Seen My Role")
                            .font(Design.Typography.body)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Design.Colors.brandGold)
                .foregroundColor(Design.Colors.surface0)
                .cornerRadius(Design.Radii.medium)
            }
            .disabled(isProcessing)
            .padding(.horizontal, 20)
            .automationID("multiplayer.roleReveal.confirm")
        } else if multiplayerStore.isHost {
            hostControls
        } else {
            // Non-host players see "Waiting for others..." after confirming
            VStack(spacing: 12) {
                HStack {
                    ProgressView()
                        .tint(Design.Colors.brandGold)
                    Text("Waiting for others...")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    /// The night starts by itself once every human has confirmed; Start Night lets the host
    /// begin earlier (after a confirmation), for example when someone's phone died.
    private var hostControls: some View {
        let isReady = isEveryoneReady
        return VStack(spacing: 12) {
            WaitingForPlayersSection()

            Button {
                if isReady {
                    startNight()
                } else {
                    showingEarlyStartConfirmation = true
                }
            } label: {
                HStack {
                    if isStartingNight {
                        ProgressView()
                            .tint(Design.Colors.brandGold)
                    } else {
                        Text("Start Night")
                            .fontWeight(.bold)

                        Image(systemName: isReady ? "arrow.right.circle.fill" : "clock.fill")
                    }
                }
                .font(Design.Typography.body)
                .foregroundStyle(
                    isReady
                        ? Design.Colors.brandGold
                        : Design.Colors.textSecondary.opacity(Design.Opacity.strong)
                )
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            }
            .disabled(isStartingNight)
            .accessibilityLabel("Start Night")
            .accessibilityHint(isReady ? "Everyone has confirmed their role" : "Some players haven't confirmed their role yet")
            .automationID("multiplayer.roleReveal.startNight")

            if let startNightError {
                Text(startNightError)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.dangerRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 40)
    }
    
    private func markAsSeen() {
        hasSeen = true
        isProcessing = true
        
        Task {
            do {
                try await multiplayerStore.markRoleAsSeen()
                await MainActor.run {
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    hasSeen = false
                    isProcessing = false
                    print("Failed to mark role as seen: \(error.localizedDescription)")
                }
            }
        }
    }

    private var unconfirmedHumans: [SessionPlayer] {
        multiplayerStore.players.filter { !$0.isBot && !$0.isReady }
    }

    private var isEveryoneReady: Bool {
        // All human players (including host) must mark ready before the night starts on its own.
        // Bots are always ready.
        unconfirmedHumans.isEmpty
    }

    private var earlyStartMessage: String {
        let count = unconfirmedHumans.count
        let who = count == 1 ? "1 player hasn't" : "\(count) players haven't"
        return "\(who) confirmed their role yet. They will go straight to the night."
    }

    private func startNight() {
        guard !isStartingNight else { return }
        isStartingNight = true
        startNightError = nil
        Task {
            do {
                try await multiplayerStore.forceStartNight()
            } catch {
                startNightError = HostTransition.errorMessage(for: error)
            }
            isStartingNight = false
        }
    }
    
    private func roleDescription(for role: Role) -> String? {
        switch role {
        case .mafia:
            return "Work with your teammates to eliminate citizens at night. Stay hidden during the day."
        case .doctor:
            return "Each night, choose one player to protect from the Mafia's attack."
        case .inspector:
            return "Each night, investigate one player to learn if they are Mafia or not."
        case .citizen:
            return "Use your voice during the day to help identify and vote out the Mafia."
        }
    }
}

/// Mafia teammates as pills: one centered row when they fit, otherwise a wrapping grid, so long
/// names in 15-19 player games never break mid-word.
private struct TeammatePills: View {
    let teammates: [PublicPlayerInfo]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                pills
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                pills
            }
        }
    }

    private var pills: some View {
        ForEach(teammates) { teammate in
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(Design.Typography.caption)
                    .accessibilityHidden(true)
                Text(teammate.playerName)
                    .font(Design.Typography.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Design.Colors.dangerRed)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Design.Colors.dangerRed.opacity(0.15))
            .cornerRadius(20)
        }
    }
}

#Preview {
    NavigationStack {
        MultiplayerRoleRevealView(currentPlayerIndex: 0)
            .environmentObject(MultiplayerGameStore())
            .preferredColorScheme(.dark)
    }
}
