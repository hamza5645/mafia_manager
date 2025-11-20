import SwiftUI

struct MultiplayerVotingView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @State private var selectedTargetId: UUID?
    @State private var hasSubmitted = false
    @State private var isSubmitting = false

    var dayIndex: Int {
        // Extract from current session phase data
        if case .voting(let index) = multiplayerStore.currentSession?.currentPhaseData {
            return index
        }
        return multiplayerStore.currentSession?.dayIndex ?? 0
    }

    var alivePlayers: [PublicPlayerInfo] {
        multiplayerStore.visiblePlayers.filter { $0.isAlive && $0.id != multiplayerStore.myPlayer?.id }
    }

    var isAlive: Bool {
        multiplayerStore.myPlayer?.isAlive ?? false
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            if isAlive {
                alivePlayerView
            } else {
                spectatorView
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var alivePlayerView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Day \(dayIndex + 1) Voting")
                    .font(Design.Typography.title1)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("Choose who to eliminate")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textSecondary)
            }
            .padding(.top, 40)

            // Timer (if active)
            if let timer = multiplayerStore.activeTimer {
                TimerView(timer: timer)
                    .padding(.horizontal, 20)
            }

            Spacer()

            if !hasSubmitted {
                // Voting Instructions
                VStack(spacing: 12) {
                    Text("Vote Privately")
                        .font(Design.Typography.title3)
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Your vote is secret until all players have voted")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)

                // Player Selection
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(alivePlayers) { player in
                            VoteTargetButton(
                                playerInfo: player,
                                isSelected: selectedTargetId == player.playerId
                            ) {
                                selectedTargetId = player.playerId
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                // Submit Vote Button
                if !hasSubmitted {
                    Button {
                        submitVote()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(selectedTargetId == nil ? "Abstain" : "Submit Vote")
                                    .font(Design.Typography.body)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            (selectedTargetId == nil && dayIndex > 0) 
                                ? Design.Colors.textSecondary.opacity(0.3)
                                : Design.Colors.brandGold
                        )
                        .foregroundColor(Design.Colors.surface0)
                        .cornerRadius(Design.Radii.medium)
                    }
                    .disabled(isSubmitting || (selectedTargetId == nil && dayIndex > 0))
                    .padding(.horizontal, 20)
                    .padding(.bottom, multiplayerStore.isHost ? 20 : 40)
                    
                    if selectedTargetId == nil && dayIndex > 0 {
                        Text("You must vote for someone after the first day")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.dangerRed)
                            .padding(.bottom, 8)
                    }
                }
            } else {
                // Vote Submitted Confirmation
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Design.Colors.successGreen)

                    Text("Vote Submitted")
                        .font(Design.Typography.title2)
                        .foregroundStyle(Design.Colors.textPrimary)

                    if let targetId = selectedTargetId,
                       let target = alivePlayers.first(where: { $0.playerId == targetId }) {
                        Text("You voted for \(target.playerName)")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textSecondary)
                    } else {
                        Text("You abstained from voting")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textSecondary)
                    }

                    Text("Waiting for other players...")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .padding(.top, 8)
                }
                .padding(.bottom, multiplayerStore.isHost ? 20 : 40)

                Spacer()
            }
            
            // Host Controls
            if multiplayerStore.isHost {
                Button {
                    endVoting()
                } label: {
                    HStack {
                        Text("End Voting")
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

    private var spectatorView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "eye.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(Design.Colors.textSecondary.opacity(0.5))

            Text("Spectating")
                .font(Design.Typography.title2)
                .foregroundStyle(Design.Colors.textPrimary)

            Text("You are eliminated. Wait for the vote results...")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func endVoting() {
        Task {
            try? await multiplayerStore.completeVotingPhase()
        }
    }

    private func submitVote() {
        isSubmitting = true

        Task {
            do {
                try await multiplayerStore.submitVote(
                    dayIndex: dayIndex,
                    targetPlayerId: selectedTargetId
                )

                await MainActor.run {
                    hasSubmitted = true
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    print("Failed to submit vote: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Vote Target Button

struct VoteTargetButton: View {
    let playerInfo: PublicPlayerInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Player Number Badge
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? Design.Colors.brandGold.opacity(0.2)
                                : Design.Colors.surface2
                        )
                        .frame(width: 52, height: 52)

                    if let number = playerInfo.playerNumber {
                        Text("#\(number)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(
                                isSelected
                                    ? Design.Colors.brandGold
                                    : Design.Colors.textPrimary
                            )
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(
                                isSelected
                                    ? Design.Colors.brandGold
                                    : Design.Colors.textSecondary
                            )
                    }
                }

                // Player Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(playerInfo.playerName)
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textPrimary)

                    if playerInfo.isBot {
                        Text("Bot Player")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                }

                Spacer()

                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Design.Colors.brandGold)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 28))
                        .foregroundStyle(Design.Colors.textSecondary.opacity(0.3))
                }
            }
            .padding(20)
            .background(
                isSelected
                    ? Design.Colors.brandGold.opacity(0.1)
                    : Design.Colors.surface1
            )
            .cornerRadius(Design.Radii.medium)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.medium)
                    .stroke(
                        isSelected
                            ? Design.Colors.brandGold
                            : Design.Colors.stroke.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? Design.Colors.brandGold.opacity(0.3) : .clear,
                radius: 8,
                y: 4
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    MultiplayerVotingView()
        .environmentObject(MultiplayerGameStore())
        .preferredColorScheme(.dark)
}
