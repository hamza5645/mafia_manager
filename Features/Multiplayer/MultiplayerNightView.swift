import SwiftUI
import UIKit

struct MultiplayerNightView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @State private var selectedTargetId: UUID?
    @State private var hasSubmitted = false
    @State private var isSubmitting = false
    @State private var autoReadyApplied = false
    @State private var inspectorResult: String? // Stores the investigation result
    @State private var isRecording = false // Phase 1 in progress
    @State private var submitError: String? // Error message for failed submissions

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

    // HAMZA-94: Sort players by humans first
    var alivePlayers: [PublicPlayerInfo] {
        multiplayerStore.visiblePlayers
            .filter { $0.isAlive && $0.id != multiplayerStore.myPlayer?.id }
            .sortedHumansFirst()
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Night \(nightIndex + 1)")
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

                Spacer()

                // Role-specific content
                if let role = myRole {
                    roleSpecificView(for: role)
                } else {
                    // Spectator/Dead player view
                    spectatorView
                }

                Spacer()

                // Submit Button (all players with active roles) - HAMZA-95: Improved UI/UX
                if myRole != nil && myRole != .citizen && !hasSubmitted {
                    Button {
                        submitAction()
                    } label: {
                        HStack(spacing: 10) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(Design.Colors.surface0)
                                Text("Submitting...")
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("Submit Action")
                            }
                        }
                        .font(Design.Typography.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            isSubmitting
                                ? roleAccentColor(for: myRole).opacity(0.7)
                                : (selectedTargetId == nil
                                    ? Design.Colors.textSecondary.opacity(0.3)
                                    : roleAccentColor(for: myRole))
                        )
                        .foregroundColor(Design.Colors.surface0)
                        .cornerRadius(Design.Radii.medium)
                    }
                    .disabled(isSubmitting || selectedTargetId == nil)
                    .padding(.horizontal, 20)

                    // Show error message if submission failed
                    if let error = submitError {
                        Text(error)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.dangerRed)
                            .padding(.horizontal, 20)
                    }

                    Spacer().frame(height: multiplayerStore.isHost ? 8 : 40)
                } else if hasSubmitted || myRole == .citizen {
                    // Ready indicator for all players - HAMZA-95: Improved with action summary
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Design.Colors.successGreen)

                        Text(myRole == .citizen ? "Ready to Continue" : "Action Submitted")
                            .font(Design.Typography.title3)
                            .foregroundStyle(Design.Colors.textPrimary)

                        // Show action summary for active roles
                        if myRole != .citizen,
                           let targetId = selectedTargetId,
                           let targetPlayer = multiplayerStore.visiblePlayers.first(where: { $0.playerId == targetId }) {
                            HStack(spacing: 6) {
                                Image(systemName: actionVerb(for: myRole).icon)
                                    .foregroundStyle(roleAccentColor(for: myRole))
                                Text("\(actionVerb(for: myRole).text) \(targetPlayer.playerName)")
                                    .font(Design.Typography.body)
                                    .foregroundStyle(Design.Colors.textSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(roleAccentColor(for: myRole).opacity(0.1))
                            .cornerRadius(Design.Radii.small)
                        }

                        if !multiplayerStore.isHost {
                            Text("Waiting for other players...")
                                .font(Design.Typography.footnote)
                                .foregroundStyle(Design.Colors.textSecondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, multiplayerStore.isHost ? 8 : 40)
                }
                
                // Host Controls
                if multiplayerStore.isHost {
                    Button {
                        recordNightActionsPhase()
                    } label: {
                        HStack {
                            if isRecording {
                                ProgressView()
                                    .tint(Design.Colors.brandGold)
                                Text("Recording Actions...")
                            } else {
                                Text("Finish Night Phase")
                                    .fontWeight(.bold)

                                if multiplayerStore.isPhaseReadyToAdvance {
                                    Image(systemName: "arrow.right.circle.fill")
                                } else {
                                    Image(systemName: "clock.fill")
                                }
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
                    .disabled(!multiplayerStore.isPhaseReadyToAdvance || isRecording)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await autoReadyIfPassive()
        }
        .onChange(of: myRole) { _, _ in
            Task { await autoReadyIfPassive() }
        }
        .onChange(of: multiplayerStore.myPlayer?.isReady) { _, _ in
            Task { await autoReadyIfPassive() }
        }
    }

    // MARK: - Two-Phase Resolution

    /// Phase 1: Record night actions without applying deaths
    private func recordNightActionsPhase() {
        isRecording = true

        Task {
            do {
                // Call the new two-phase method: Phase 1
                try await multiplayerStore.recordNightActions(nightIndex: nightIndex)

                // Auto-determine if target was saved
                let targetWasSaved = determineIfTargetWasSaved()

                // Phase 2: Immediately resolve outcome without showing results sheet
                try await multiplayerStore.resolveNightOutcome(
                    nightIndex: nightIndex,
                    targetWasSaved: targetWasSaved
                )

                await MainActor.run {
                    isRecording = false
                }
            } catch {
                await MainActor.run {
                    isRecording = false
                    print("Failed to complete night phase: \(error.localizedDescription)")
                }
            }
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
            if let result = inspectorResult {
                // Show investigation result
                inspectorResultView(role: result)
            } else {
                targetSelectionView(
                    title: "Investigate a Player",
                    subtitle: "Discover their role",
                    players: alivePlayers.filter { player in
                        // Can't investigate other inspectors (if visible)
                        true // Privacy filter handles this
                    }
                )
            }
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

            // Target selection - mafia can target any non-mafia alive player
            targetSelectionView(
                title: "Choose Target",
                subtitle: "Coordinate with your team",
                players: alivePlayers // Visibility rules already filter appropriately
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

    private func inspectorResultView(role: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Design.Colors.successGreen)

            Text("Investigation Complete")
                .font(Design.Typography.title2)
                .foregroundStyle(Design.Colors.textPrimary)

            // Show who was investigated
            if let targetId = selectedTargetId,
               let targetPlayer = multiplayerStore.visiblePlayers.first(where: { $0.playerId == targetId }) {
                Text("You investigated \(targetPlayer.playerName)")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textSecondary)
            }

            // Show the actual role with appropriate color
            VStack(spacing: 8) {
                Text("Their Role:")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textSecondary)

                Text(roleDisplayName(for: role))
                    .font(Design.Typography.title1)
                    .fontWeight(.bold)
                    .foregroundStyle(roleColor(for: role))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(roleColor(for: role).opacity(0.1))
                    .cornerRadius(Design.Radii.medium)
            }

            Text("Wait for other players to finish...")
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.textSecondary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
    }

    private func roleDisplayName(for roleString: String) -> String {
        switch roleString.lowercased() {
        case "mafia":
            return "Mafia"
        case "not_mafia":
            return "Not Mafia"
        case "doctor":
            return "Doctor"
        case "inspector":
            return "Inspector"
        case "citizen":
            return "Citizen"
        case "blocked":
            return "Blocked"
        default:
            return roleString.capitalized
        }
    }

    private func roleColor(for roleString: String) -> Color {
        switch roleString.lowercased() {
        case "mafia":
            return Design.Colors.dangerRed
        case "not_mafia":
            return Design.Colors.successGreen
        case "doctor":
            return Design.Colors.successGreen
        case "inspector":
            return Design.Colors.actionBlue
        case "citizen":
            return Design.Colors.brandGold
        case "blocked":
            return Design.Colors.textSecondary
        default:
            return Design.Colors.textSecondary
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
                // HAMZA-141: Reduced spacing for better display with many players
                VStack(spacing: 8) {
                    ForEach(players) { player in
                        TargetPlayerButton(
                            playerInfo: player,
                            isSelected: selectedTargetId == player.playerId,
                            accentColor: roleAccentColor(for: myRole)
                        ) {
                            // Prevent target changes while submitting
                            guard !isSubmitting else { return }
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

    // HAMZA-95: Action verb for summary display
    private func actionVerb(for role: Role?) -> (text: String, icon: String) {
        switch role {
        case .mafia:
            return ("Targeting", "target")
        case .doctor:
            return ("Protecting", "heart.fill")
        case .inspector:
            return ("Investigating", "magnifyingglass")
        case .citizen, .none:
            return ("", "person.fill")
        }
    }

    private func submitAction() {
        guard let role = myRole else { return }

        isSubmitting = true
        submitError = nil // Clear any previous error

        Task {
            do {
                let actionType: ActionType = switch role {
                case .mafia: .mafiaTarget
                case .doctor: .doctorProtect
                case .inspector: .inspectorCheck
                case .citizen: .vote // Won't be reached
                }

                let result = try await multiplayerStore.submitNightAction(
                    actionType: actionType,
                    nightIndex: nightIndex,
                    targetPlayerId: selectedTargetId
                )

                // Auto-mark ready after successful submission
                try await multiplayerStore.setReadyStatus(true)

                await MainActor.run {
                    // Store inspector result if available
                    if role == .inspector, let result = result {
                        inspectorResult = result
                    }
                    hasSubmitted = true
                    isSubmitting = false

                    // HAMZA-95: Haptic feedback on successful submission
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }

                // HAMZA-145: Host auto-ends night phase after submitting (except inspector who needs to see result first)
                if multiplayerStore.isHost && role != .inspector {
                    // Small delay to ensure state updates propagate before checking readiness
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

                    let canAutoAdvance = await MainActor.run {
                        multiplayerStore.isPhaseReadyToAdvance && !isRecording
                    }

                    if canAutoAdvance {
                        await MainActor.run {
                            recordNightActionsPhase()
                        }
                    } else {
                        print("⏳ [MultiplayerNightView] Skipping auto-advance; waiting for other players/actions")
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submitError = "Failed to submit action. Tap to retry."
                    print("Failed to submit action: \(error.localizedDescription)")
                }
            }
        }
    }

    private func autoReadyIfPassive() async {
        // Citizens have no night action; auto-mark ready for non-host humans
        guard !autoReadyApplied else { return }
        guard let role = myRole, role == .citizen else { return }
        guard let me = multiplayerStore.myPlayer, me.isAlive, !multiplayerStore.isHost else { return }

        if me.isReady == false {
            try? await multiplayerStore.setReadyStatus(true)
        }

        await MainActor.run {
            hasSubmitted = true
            autoReadyApplied = true
        }
    }

    private func determineIfTargetWasSaved() -> Bool {
        guard let session = multiplayerStore.currentSession,
              let nightRecord = session.nightHistory.first(where: { $0.nightIndex == nightIndex }),
              let mafiaTargetId = nightRecord.mafiaTargetId,
              let doctorProtectedId = nightRecord.doctorProtectedId else {
            return false
        }

        return mafiaTargetId == doctorProtectedId
    }
}

// MARK: - Target Player Button
// HAMZA-141: Made more compact for better display with many players

struct TargetPlayerButton: View {
    let playerInfo: PublicPlayerInfo
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Player Icon (HAMZA-136: Numbers are kept secret - show person icon instead)
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? accentColor.opacity(0.2)
                                : Design.Colors.surface2
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            isSelected
                                ? accentColor
                                : Design.Colors.textSecondary
                        )
                }

                // Player Name
                Text(playerInfo.playerName)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textPrimary)

                Spacer()

                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(accentColor)
                }
            }
            .padding(12)
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

#Preview {
    MultiplayerNightView()
        .environmentObject(MultiplayerGameStore())
        .preferredColorScheme(.dark)
}
