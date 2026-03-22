import SwiftUI

struct MultiplayerVotingView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @State private var selectedTargetId: UUID?
    @State private var hasSubmitted = false
    @State private var isSubmitting = false
    @State private var votingError: String?

    var dayIndex: Int {
        // Extract from current session phase data
        if case .voting(let index) = multiplayerStore.currentSession?.currentPhaseData {
            return index
        }
        return multiplayerStore.currentSession?.dayIndex ?? 0
    }

    // HAMZA-94: Sort players by humans first
    // Note: Mafia CAN vote on teammates during day (to maintain cover)
    // Only night targeting restricts Mafia from targeting teammates
    var alivePlayers: [PublicPlayerInfo] {
        return multiplayerStore.visiblePlayers
            .filter { $0.isAlive && $0.playerId != multiplayerStore.myPlayer?.playerId }
            .sortedHumansFirst()
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
                // HAMZA-141: Reduced spacing for better display with many players
                // PERF: LazyVStack defers rendering until visible
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(alivePlayers, id: \.id) { player in
                            VoteTargetButton(
                                playerInfo: player,
                                isSelected: selectedTargetId == player.playerId
                            ) {
                                selectedTargetId = player.playerId
                                // For host: submit vote silently without showing confirmation
                                // Pass target explicitly to avoid race condition with state update
                                if multiplayerStore.isHost && !hasSubmitted {
                                    submitVote(explicitTarget: player.playerId, showConfirmation: false)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                // Submit Vote Button (only for non-host players)
                if !hasSubmitted && !multiplayerStore.isHost {
                    Button {
                        submitVote()
                    } label: {
                        Text("Submit Vote")
                            .font(Design.Typography.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                selectedTargetId == nil
                                    ? Design.Colors.textSecondary.opacity(Design.Opacity.disabled)
                                    : Design.Colors.brandGold
                            )
                            .foregroundColor(Design.Colors.surface0)
                            .cornerRadius(Design.Radii.medium)
                    }
                    .disabled(isSubmitting || selectedTargetId == nil)
                    .padding(.horizontal, 20)
                    .padding(.bottom, multiplayerStore.isHost ? 20 : 40)
                    .automationID("multiplayer.voting.submitVote")

                    if selectedTargetId == nil {
                        Text("Select a player to vote for")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.textSecondary)
                            .padding(.bottom, 8)
                    }
                }
            } else {
                // Vote Submitted Confirmation
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Design.Typography.displayEmoji)
                        .foregroundStyle(Design.Colors.successGreen)
                        .accessibilityHidden(true)

                    Text("Vote Submitted")
                        .font(Design.Typography.title2)
                        .foregroundStyle(Design.Colors.textPrimary)

                    if let targetId = selectedTargetId,
                       let target = alivePlayers.first(where: { $0.playerId == targetId }) {
                        Text("You voted for \(target.playerName)")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textSecondary)
                    }

                    Text("Waiting for other players...")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .padding(.top, 8)
                }
                .padding(.bottom, 16)
            }

            // Error Display
            if let error = votingError {
                Text(error)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.dangerRed)
                    .padding(.horizontal, 20)
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
                            : Design.Colors.textSecondary.opacity(Design.Opacity.medium)
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
                .automationID("multiplayer.voting.endVoting")
            }
        }
    }

    private var spectatorView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "eye.slash.fill")
                .font(Design.Typography.displayEmoji)
                .foregroundStyle(Design.Colors.textSecondary.opacity(Design.Opacity.medium))
                .accessibilityHidden(true)

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
        votingError = nil
        Task {
            do {
                if let session = multiplayerStore.currentSession,
                   case .voting(let dayIndex) = session.currentPhaseData {
                    try await multiplayerStore.showVotingResults(dayIndex: dayIndex)
                }
            } catch {
                await MainActor.run {
                    votingError = "Bot voting failed. Please try again."
                }
                print("❌ Failed to show voting results: \(error.localizedDescription)")
            }
        }
    }

    private func submitVote(explicitTarget: UUID? = nil, showConfirmation: Bool = true) {
        isSubmitting = true
        votingError = nil

        // Use explicit target if provided (avoids race condition), otherwise use state
        let targetToSubmit = explicitTarget ?? selectedTargetId

        Task {
            do {
                try await multiplayerStore.submitVote(
                    dayIndex: dayIndex,
                    targetPlayerId: targetToSubmit
                )

                // Auto-mark non-host humans as ready after submitting a vote
                if let me = multiplayerStore.myPlayer, me.isAlive, !multiplayerStore.isHost {
                    try? await multiplayerStore.setReadyStatus(true)
                }

                await MainActor.run {
                    // Only show confirmation screen if requested (non-host players)
                    if showConfirmation {
                        hasSubmitted = true
                    }
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    votingError = "Failed to submit vote. Tap to retry."
                }
                print("Failed to submit vote: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Vote Target Button
// HAMZA-141: Made more compact for better display with many players

struct VoteTargetButton: View {
    let playerInfo: PublicPlayerInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Player Icon (HAMZA-136: Numbers are kept secret)
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? Design.Colors.brandGold.opacity(0.2)
                                : Design.Colors.surface2
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "person.fill")
                        .font(Design.Typography.subheadline)
                        .foregroundStyle(
                            isSelected
                                ? Design.Colors.brandGold
                                : Design.Colors.textSecondary
                        )
                }
                .accessibilityHidden(true)

                // Player Name
                Text(playerInfo.playerName)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textPrimary)

                Spacer()

                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Design.Typography.title2)
                        .foregroundStyle(Design.Colors.brandGold)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "circle")
                        .font(Design.Typography.title2)
                        .foregroundStyle(Design.Colors.textSecondary.opacity(0.3))
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
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
            // PERF: Fixed radius, animate opacity only for GPU efficiency
            .shadow(
                color: Design.Colors.brandGold.opacity(isSelected ? 0.3 : 0),
                radius: 6,
                y: 3
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    MultiplayerVotingView()
        .environmentObject(MultiplayerGameStore())
        .preferredColorScheme(.dark)
}
