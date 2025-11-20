import SwiftUI

struct MultiplayerNightView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @State private var selectedTargetId: UUID?
    @State private var hasSubmitted = false
    @State private var isSubmitting = false

    var nightIndex: Int {
        // Extract from current session phase data
        if case .night(let index, _) = multiplayerStore.currentSession?.currentPhaseData {
            return index
        }
        return 1
    }

    var myRole: Role? {
        multiplayerStore.myRole
    }

    var alivePlayers: [PublicPlayerInfo] {
        multiplayerStore.visiblePlayers.filter { $0.isAlive && $0.id != multiplayerStore.myPlayer?.id }
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Night \(nightIndex)")
                        .font(Design.Typography.title1)
                        .foregroundStyle(Design.Colors.textPrimary)

                    if let role = myRole {
                        roleInstructionText(for: role)
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 40)

                // Timer (if active)
                if let timer = multiplayerStore.activeTimer {
                    TimerView(timer: timer)
                        .padding(.horizontal, 20)
                }

                Spacer()

                // Role-specific content
                if let role = myRole {
                    roleSpecificView(for: role)
                } else {
                    // Spectator/Dead player view
                    spectatorView
                }

                Spacer()

                // Submit Button
                if myRole != nil && myRole != .citizen && !hasSubmitted {
                    Button {
                        submitAction()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Submit Action")
                                    .font(Design.Typography.body)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            selectedTargetId == nil
                                ? Design.Colors.textSecondary.opacity(0.3)
                                : roleAccentColor(for: myRole)
                        )
                        .foregroundColor(Design.Colors.surface0)
                        .cornerRadius(Design.Radii.medium)
                    }
                    .disabled(isSubmitting || selectedTargetId == nil)
                    .padding(.horizontal, 20)
                    .padding(.bottom, multiplayerStore.isHost ? 20 : 40)
                } else if hasSubmitted {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Design.Colors.successGreen)

                        Text("Action Submitted")
                            .font(Design.Typography.title3)
                            .foregroundStyle(Design.Colors.textPrimary)

                        Text("Waiting for other players...")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                    .padding(.bottom, multiplayerStore.isHost ? 20 : 40)
                }
                
                // Host Controls
                if multiplayerStore.isHost {
                    Button {
                        advancePhase()
                    } label: {
                        HStack {
                            Text("Finish Night Phase")
                                .fontWeight(.bold)
                            
                            if multiplayerStore.isPhaseReadyToAdvance {
                                Image(systemName: "arrow.right.circle.fill")
                            } else {
                                Image(systemName: "clock.fill")
                            }
                        }
                        .font(Design.Typography.body)
                        .foregroundStyle(
                            multiplayerStore.isPhaseReadyToAdvance
                                ? Design.Colors.brandGold
                                : Design.Colors.textSecondary.opacity(0.5)
                        )
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            multiplayerStore.isPhaseReadyToAdvance
                                ? Design.Colors.brandGold.opacity(0.1)
                                : Color.clear
                        )
                        .cornerRadius(Design.Radii.medium)
                    }
                    .disabled(!multiplayerStore.isPhaseReadyToAdvance)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func advancePhase() {
        Task {
            try? await multiplayerStore.completeNightPhase()
        }
    }

    @ViewBuilder
    private func roleSpecificView(for role: Role) -> some View {
        switch role {
        case .mafia:
            mafiaView
        case .doctor:
            targetSelectionView(
                title: "Protect a Player",
                subtitle: "Choose wisely",
                players: alivePlayers
            )
        case .inspector:
            targetSelectionView(
                title: "Investigate a Player",
                subtitle: "Discover their role",
                players: alivePlayers.filter { player in
                    // Can't investigate other inspectors (if visible)
                    true // Privacy filter handles this
                }
            )
        case .citizen:
            citizenView
        }
    }

    private var mafiaView: some View {
        VStack(spacing: 20) {
            // Show mafia teammates
            if !multiplayerStore.mafiaTeammates.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Team")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textPrimary)
                        .padding(.horizontal, 20)

                    VStack(spacing: 8) {
                        ForEach(multiplayerStore.mafiaTeammates) { teammate in
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Design.Colors.dangerRed)

                                Text(teammate.playerName)
                                    .font(Design.Typography.body)
                                    .foregroundStyle(Design.Colors.textPrimary)

                                Spacer()
                            }
                            .padding(12)
                            .background(Design.Colors.dangerRed.opacity(0.1))
                            .cornerRadius(Design.Radii.small)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Target selection
            targetSelectionView(
                title: "Choose Target",
                subtitle: "Coordinate with your team",
                players: alivePlayers.filter { !$0.isBot || true } // Filter handled by visibility
            )
        }
    }

    private var citizenView: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64))
                .foregroundStyle(Design.Colors.textSecondary.opacity(0.5))

            Text("Sleep Tight")
                .font(Design.Typography.title2)
                .foregroundStyle(Design.Colors.textPrimary)

            Text("Citizens have no night action. Wait for morning...")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var spectatorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(Design.Colors.textSecondary.opacity(0.5))

            Text("Waiting...")
                .font(Design.Typography.title2)
                .foregroundStyle(Design.Colors.textPrimary)

            Text("Wait for the night phase to complete")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    @ViewBuilder
    private func targetSelectionView(
        title: String,
        subtitle: String,
        players: [PublicPlayerInfo]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Design.Typography.title3)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(subtitle)
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
            }
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(players) { player in
                        TargetPlayerButton(
                            playerInfo: player,
                            isSelected: selectedTargetId == player.playerId,
                            accentColor: roleAccentColor(for: myRole)
                        ) {
                            selectedTargetId = player.playerId
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func roleInstructionText(for role: Role) -> Text {
        switch role {
        case .mafia:
            return Text("Choose a target to eliminate")
        case .doctor:
            return Text("Choose a player to protect")
        case .inspector:
            return Text("Choose a player to investigate")
        case .citizen:
            return Text("Wait for morning")
        }
    }

    private func roleAccentColor(for role: Role?) -> Color {
        switch role {
        case .mafia:
            return Design.Colors.dangerRed
        case .doctor:
            return Design.Colors.successGreen
        case .inspector:
            return Design.Colors.actionBlue
        case .citizen, .none:
            return Design.Colors.textSecondary
        }
    }

    private func submitAction() {
        guard let role = myRole else { return }

        isSubmitting = true

        Task {
            do {
                let actionType: ActionType = switch role {
                case .mafia: .mafiaTarget
                case .doctor: .doctorProtect
                case .inspector: .inspectorCheck
                case .citizen: .vote // Won't be reached
                }

                try await multiplayerStore.submitNightAction(
                    actionType: actionType,
                    nightIndex: nightIndex,
                    targetPlayerId: selectedTargetId
                )

                await MainActor.run {
                    hasSubmitted = true
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    print("Failed to submit action: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Target Player Button

struct TargetPlayerButton: View {
    let playerInfo: PublicPlayerInfo
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Player Icon
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? accentColor.opacity(0.2)
                                : Design.Colors.surface2
                        )
                        .frame(width: 44, height: 44)

                    if let number = playerInfo.playerNumber {
                        Text("#\(number)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(
                                isSelected
                                    ? accentColor
                                    : Design.Colors.textPrimary
                            )
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundStyle(
                                isSelected
                                    ? accentColor
                                    : Design.Colors.textSecondary
                            )
                    }
                }

                // Player Name
                Text(playerInfo.playerName)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textPrimary)

                Spacer()

                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(accentColor)
                }
            }
            .padding(16)
            .background(
                isSelected
                    ? accentColor.opacity(0.1)
                    : Design.Colors.surface1
            )
            .cornerRadius(Design.Radii.medium)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.medium)
                    .stroke(
                        isSelected
                            ? accentColor
                            : Design.Colors.stroke.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Timer View

struct TimerView: View {
    let timer: PhaseTimer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 20))
                .foregroundStyle(Design.Colors.brandGold)

            VStack(alignment: .leading, spacing: 2) {
                Text("Time Remaining")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.textSecondary)

                Text(timeString(from: timer.timeRemaining))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(Design.Colors.brandGold)
            }

            Spacer()
        }
        .padding(16)
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.medium)
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    MultiplayerNightView()
        .environmentObject(MultiplayerGameStore())
        .preferredColorScheme(.dark)
}
