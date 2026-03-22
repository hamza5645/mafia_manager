import SwiftUI

struct MultiplayerRoleRevealView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    let currentPlayerIndex: Int
    
    @State private var hasSeen = false
    @State private var isProcessing = false
    
    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

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

                    // Mafia teammates (if applicable) - centered horizontal pills
                    if myRole == .mafia && !multiplayerStore.mafiaTeammates.isEmpty {
                        VStack(spacing: 12) {
                            Text("Your Mafia Teammates")
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.textSecondary)

                            // HAMZA-136: Numbers are kept secret - show names only (centered pills)
                            HStack(spacing: 10) {
                                ForEach(multiplayerStore.mafiaTeammates) { teammate in
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.fill")
                                            .font(Design.Typography.caption)
                                            .accessibilityHidden(true)
                                        Text(teammate.playerName)
                                            .font(Design.Typography.body)
                                    }
                                    .foregroundStyle(Design.Colors.dangerRed)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Design.Colors.dangerRed.opacity(0.15))
                                    .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }

                } else {
                    ProgressView()
                        .tint(Design.Colors.brandGold)
                }
                }

                Spacer()

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
                    // Host sees "Start Night" button after confirming their role
                    Button {
                        forceStartNight()
                    } label: {
                        HStack {
                            Text("Start Night")
                                .fontWeight(.bold)

                            if isEveryoneReady {
                                Image(systemName: "arrow.right.circle.fill")
                            } else {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                            }
                        }
                        .font(Design.Typography.body)
                        .foregroundStyle(
                            isEveryoneReady
                                ? Design.Colors.brandGold
                                : Design.Colors.textSecondary.opacity(0.5)
                        )
                    }
                    .disabled(!isEveryoneReady)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                    .automationID("multiplayer.roleReveal.startNight")
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
        }
        .navigationBarBackButtonHidden(true)
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
    
    private var isEveryoneReady: Bool {
        // All human players (including host) must mark ready before phase can advance.
        // Bots are always ready. Host must confirm their role just like other players.
        // (See CLAUDE.md "Host with Active Roles" pattern for night phase - same applies to role reveal)
        let humanPlayers = multiplayerStore.allPlayers.filter { !$0.isBot }
        let readyHumans = humanPlayers.filter { $0.isReady }
        return readyHumans.count == humanPlayers.count
    }

    private func forceStartNight() {
        Task {
            // We can use forceStartNight() because now we control when it's called (only when ready)
            // OR we can use the normal path. But since we removed auto-advance, we need an explicit call.
            // The store method forceStartNight() calls advanceFromRoleRevealIfReady(force: true)
            // which actually bypasses the check in the store.
            // However, since we check readiness in the UI, we can use it.
            // Better yet, use a method that respects readiness or just use the existing one
            // since we guard in UI.
            try? await multiplayerStore.forceStartNight()
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

#Preview {
    NavigationStack {
        MultiplayerRoleRevealView(currentPlayerIndex: 0)
            .environmentObject(MultiplayerGameStore())
            .preferredColorScheme(.dark)
    }
}
