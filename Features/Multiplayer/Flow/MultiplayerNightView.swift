import SwiftUI

struct MultiplayerNightView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    /// From the router; a new night gets a new view (`.id(nightIndex)`), so local state starts fresh.
    let nightIndex: Int

    @State private var selectedTargetId: UUID?
    @State private var hasSubmitted = false
    @State private var isSubmitting = false
    @State private var inspectorResult: String? // Stores the investigation result
    @State private var isRecording = false // Phase 1 in progress
    @State private var showingCompletionError = false
    @State private var completionError: String?
    /// A finish request that ran out of time; shown inline because it may still go through.
    @State private var completionNotice: String?
    @State private var submitError: String? // Error message for failed submissions
    @State private var submitFeedback = 0 // Success haptic trigger

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            // Until my seat arrives (e.g. right after re-entering a running game) this is loading,
            // not "You are eliminated".
            if let me = multiplayerStore.myPlayer {
                content(me: me)
            } else {
                ProgressView()
                    .tint(Design.Colors.brandGold)
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Could Not Finish Night", isPresented: $showingCompletionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(completionError ?? "Please try again.")
        }
        .task {
            restoreSubmittedAction()
            autoFinishNightIfReady()
        }
        .onChange(of: multiplayerStore.myNightAction?.id) { _, _ in
            restoreSubmittedAction()
        }
        .onChange(of: multiplayerStore.isPhaseReadyToAdvance) { _, _ in
            autoFinishNightIfReady()
        }
        .sensoryFeedback(.success, trigger: multiplayerStore.isPhaseReadyToAdvance) { wasReady, isReady in
            multiplayerStore.isHost && !wasReady && isReady
        }
        .sensoryFeedback(.success, trigger: submitFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: selectedTargetId) { _, newTarget in
            newTarget != nil && !hasSubmitted
        }
    }

    @ViewBuilder
    private func content(me: SessionPlayer) -> some View {
        let role = me.role
        let isAlive = me.isAlive
        let isHost = multiplayerStore.isHost
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Text("Night \(nightIndex + 1)")
                    .font(Design.Typography.title1)
                    .foregroundStyle(Design.Colors.textPrimary)

                // Only show role instructions for alive players
                if isAlive, let role {
                    roleInstructionText(for: role)
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 24)

            Spacer()

            // Role-specific content - dead players see spectator view
            Group {
                if isAlive {
                    if let role {
                        roleSpecificView(for: role, me: me)
                    } else {
                        spectatorView
                    }
                } else {
                    eliminatedSpectatorView
                }
            }
            .layoutPriority(1)

            Spacer()

            // Submit Button (all players with active roles) - HAMZA-95: Improved UI/UX
            if isAlive && role != nil && role != .citizen && !hasSubmitted {
                submitButton(role: role)

                // Show error message if submission failed
                if let error = submitError {
                    Text(error)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.dangerRed)
                        .padding(.horizontal, 20)
                }

                Spacer().frame(height: isHost ? 8 : 40)
            } else if isAlive && (hasSubmitted || role == .citizen) {
                readyIndicator(role: role, isHost: isHost)
            }

            // Host Controls
            if isHost {
                WaitingForPlayersSection()

                hostFinishButton(autoFinishes: autoFinishes(role: role, isAlive: isAlive))
            }
        }
        .readableContentWidth()
    }

    private func submitButton(role: Role?) -> some View {
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
                    ? roleAccentColor(for: role).opacity(Design.Opacity.strong)
                    : (selectedTargetId == nil
                        ? Design.Colors.textSecondary.opacity(Design.Opacity.disabled)
                        : roleAccentColor(for: role))
            )
            .foregroundColor(Design.Colors.surface0)
            .cornerRadius(Design.Radii.medium)
        }
        .disabled(isSubmitting || selectedTargetId == nil)
        .padding(.horizontal, 20)
        .automationID("multiplayer.night.submitAction")
    }

    // Ready indicator for alive players only - HAMZA-95: Improved with action summary
    private func readyIndicator(role: Role?, isHost: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(Design.Typography.displayEmoji)
                .foregroundStyle(Design.Colors.successGreen)
                .accessibilityHidden(true)

            Text(role == .citizen ? "Ready for Morning" : "Action Submitted")
                .font(Design.Typography.title3)
                .foregroundStyle(Design.Colors.textPrimary)

            // Show action summary for active roles
            if role != .citizen,
               let targetId = selectedTargetId,
               let targetPlayer = multiplayerStore.players.first(where: { $0.playerId == targetId }) {
                HStack(spacing: 6) {
                    Image(systemName: actionVerb(for: role).icon)
                        .foregroundStyle(roleAccentColor(for: role))
                    Text("\(actionVerb(for: role).text) \(targetPlayer.playerName)")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(roleAccentColor(for: role).opacity(0.1))
                .cornerRadius(Design.Radii.small)
            }

            if !isHost {
                Text("Waiting for other players...")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, isHost ? 8 : 24)
    }

    private func hostFinishButton(autoFinishes: Bool) -> some View {
        let isReady = multiplayerStore.isPhaseReadyToAdvance
        return VStack(spacing: 6) {
            Button {
                finishNight()
            } label: {
                HStack {
                    if isRecording {
                        ProgressView()
                            .tint(Design.Colors.brandGold)
                        Text("Recording Actions...")
                    } else {
                        Text("Finish Night Phase")
                            .fontWeight(.bold)

                        if isReady {
                            Image(systemName: "arrow.right.circle.fill")
                        } else {
                            Image(systemName: "clock.fill")
                        }
                    }
                }
                .font(Design.Typography.body)
                .foregroundStyle(
                    isReady
                        ? Design.Colors.brandGold
                        : Design.Colors.textSecondary.opacity(Design.Opacity.medium)
                )
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    isReady
                        ? Design.Colors.brandGold.opacity(0.1)
                        : Color.clear
                )
                .cornerRadius(Design.Radii.medium)
            }
            .disabled(!isReady || isRecording)
            .automationID("multiplayer.night.finishPhase")

            // The one manual case left: an inspector host reads their result first.
            if isReady && !autoFinishes && !isRecording {
                Text("Everyone has acted. Finish the night when you're ready.")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            if let completionNotice, !isRecording {
                Text(completionNotice)
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: - Finish Night

    /// The server records and resolves the night in one call (`night:finishNight`).
    private func finishNight() {
        isRecording = true
        completionNotice = nil

        Task {
            do {
                try await multiplayerStore.completeNightPhase()

                await MainActor.run {
                    isRecording = false
                }
            } catch let error as BackendError where error.isTimeout {
                // Finishing a round is idempotent on the server; a retry is safe.
                isRecording = false
                completionNotice = error.message
            } catch {
                await MainActor.run {
                    isRecording = false
                    completionError = error.localizedDescription
                    showingCompletionError = true
                }
            }
        }
    }

    @ViewBuilder
    private func roleSpecificView(for role: Role, me: SessionPlayer) -> some View {
        // Derived once per render; the filters compare against `me` instead of rescanning the roster.
        let alive = multiplayerStore.visiblePlayers.filter(\.isAlive)
        switch role {
        case .mafia:
            let teammates = multiplayerStore.mafiaTeammates
            let teammateIds = Set(teammates.map(\.playerId))
            // Mafia cannot target their teammates
            mafiaView(
                teammates: teammates,
                targets: alive
                    .filter { $0.playerId != me.playerId && !teammateIds.contains($0.playerId) }
                    .sortedHumansFirst()
            )
        case .doctor:
            // Doctor can protect themselves, so include self in the list
            targetSelectionView(
                title: "Protect a Player",
                subtitle: "You can protect yourself",
                players: alive.sortedHumansFirst(),
                role: role
            )
        case .inspector:
            if let result = inspectorResult {
                // Show investigation result
                inspectorResultView(role: result)
            } else {
                let inspectorIds = Set(multiplayerStore.players.filter { $0.role == .inspector }.map(\.playerId))
                targetSelectionView(
                    title: "Investigate a Player",
                    subtitle: "Find out whether they are Mafia",
                    players: alive
                        .filter { $0.playerId != me.playerId && !inspectorIds.contains($0.playerId) }
                        .sortedHumansFirst(),
                    role: role
                )
            }
        case .citizen:
            citizenView
        }
    }

    private func mafiaView(teammates: [PublicPlayerInfo], targets: [PublicPlayerInfo]) -> some View {
        VStack(spacing: 12) {
            // Show mafia teammates as pill-shaped chips
            if !teammates.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Team")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textPrimary)
                        .padding(.horizontal, 20)

                    // Horizontal pill layout
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(teammates) { teammate in
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
                        .padding(.horizontal, 20)
                    }
                }
            }

            // Target selection - mafia can target any non-mafia alive player
            targetSelectionView(
                title: "Choose Target",
                subtitle: "Coordinate with your team",
                players: targets,
                role: .mafia
            )
        }
    }

    private var citizenView: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(Design.Typography.displayEmoji)
                .foregroundStyle(Design.Colors.textSecondary.opacity(0.5))
                .accessibilityHidden(true)

            Text("Sleep Tight")
                .font(Design.Typography.title2)
                .foregroundStyle(Design.Colors.textPrimary)

            Text(multiplayerStore.isHost
                 ? "Citizens have no night action. Morning starts on its own once everyone has acted."
                 : "Citizens have no night action. Wait for morning...")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var spectatorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash.fill")
                .font(Design.Typography.displayEmoji)
                .foregroundStyle(Design.Colors.textSecondary.opacity(0.5))
                .accessibilityHidden(true)

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

    private var eliminatedSpectatorView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "eye.slash.fill")
                .font(Design.Typography.displayEmoji)
                .foregroundStyle(Design.Colors.textSecondary.opacity(Design.Opacity.medium))
                .accessibilityHidden(true)

            Text("Spectating")
                .font(Design.Typography.title2)
                .foregroundStyle(Design.Colors.textPrimary)

            Text("You are eliminated. Watch the night unfold...")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func inspectorResultView(role: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(Design.Typography.displayEmoji)
                .foregroundStyle(resultColor(for: role))
                .accessibilityHidden(true)

            Text("Investigation Complete")
                .font(Design.Typography.title2)
                .foregroundStyle(Design.Colors.textPrimary)

            // Show who was investigated
            if let targetId = selectedTargetId,
               let targetPlayer = multiplayerStore.players.first(where: { $0.playerId == targetId }) {
                Text("You investigated \(targetPlayer.playerName)")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textSecondary)
            }

            // Show the actual role with appropriate color
            VStack(spacing: 8) {
                Text("Result:")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textSecondary)

                Text(resultDisplayName(for: role))
                    .font(Design.Typography.title1)
                    .fontWeight(.bold)
                    .foregroundStyle(resultColor(for: role))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(resultColor(for: role).opacity(0.1))
                    .cornerRadius(Design.Radii.medium)
            }

            Text(resultDescription(for: role))
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.textSecondary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
    }

    private func resultDisplayName(for roleString: String) -> String {
        switch normalizedInspectorResult(roleString) {
        case "mafia":
            return "Mafia"
        case "not_mafia":
            return "Not Mafia"
        case "blocked":
            return "Blocked"
        default:
            return roleString.capitalized
        }
    }

    private func resultColor(for roleString: String) -> Color {
        switch normalizedInspectorResult(roleString) {
        case "mafia":
            return Design.Colors.dangerRed
        case "not_mafia":
            return Design.Colors.successGreen
        case "blocked":
            return Design.Colors.textSecondary
        default:
            return Design.Colors.textSecondary
        }
    }

    private func resultDescription(for roleString: String) -> String {
        switch normalizedInspectorResult(roleString) {
        case "mafia":
            return "That player is part of the Mafia."
        case "not_mafia":
            return "That player is not Mafia."
        case "blocked":
            return "Your investigation returned no actionable information."
        default:
            return "Wait for other players to finish..."
        }
    }

    private func normalizedInspectorResult(_ roleString: String) -> String {
        switch roleString.lowercased() {
        case "mafia":
            return "mafia"
        case "doctor", "citizen", "not_mafia":
            return "not_mafia"
        case "inspector", "blocked":
            return "blocked"
        default:
            return roleString.lowercased()
        }
    }

    // HAMZA-142: adaptive grid for player selection (3 columns on iPhone, more on iPad)
    @ViewBuilder
    private func targetSelectionView(
        title: String,
        subtitle: String,
        players: [PublicPlayerInfo],
        role: Role
    ) -> some View {
        // HAMZA-FIX: Get action type for vote count lookup
        let actionType: ActionType? = {
            switch role {
            case .mafia: return .mafiaTarget
            case .doctor: return .doctorProtect
            case .inspector: return .inspectorCheck
            case .citizen: return nil
            }
        }()

        // Get tentative vote counts for real-time preview (shows immediately on tap)
        let voteCounts = actionType.flatMap { multiplayerStore.tentativeVoteCounts[$0] } ?? [:]
        let accentColor = roleAccentColor(for: role)

        VStack(alignment: .leading, spacing: 16) {
            // Header
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
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 180), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(players) { player in
                        TargetGridCell(
                            name: player.playerName,
                            isSelected: selectedTargetId == player.playerId,
                            accentColor: accentColor,
                            voteCount: voteCounts[player.playerId] ?? 0
                        ) {
                            // Disable selection after submission; an unchanged pick is not re-sent.
                            guard !isSubmitting && !hasSubmitted, selectedTargetId != player.playerId else { return }
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                selectedTargetId = player.playerId
                            }

                            // Broadcast tentative selection immediately on tap
                            if let actionType {
                                Task {
                                    await multiplayerStore.broadcastTentativeSelection(
                                        actionType: actionType,
                                        targetPlayerId: player.playerId,
                                        phaseIndex: nightIndex
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .opacity(hasSubmitted ? 0.6 : 1.0) // Dim grid after submission
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
        guard let me = multiplayerStore.myPlayer, me.isAlive, let role = me.role else { return }

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

                // Store inspector result if available
                if role == .inspector, let result {
                    inspectorResult = result
                }
                hasSubmitted = true
                isSubmitting = false
                submitFeedback += 1 // HAMZA-95: haptic on successful submission
                autoFinishNightIfReady()
            } catch {
                isSubmitting = false
                // A timed-out request may still arrive, so it is not called a failure.
                if let error = error as? BackendError, error.isTimeout {
                    submitError = error.message
                } else {
                    submitError = "Failed to submit action. Tap to retry."
                }
                print("Failed to submit action: \(error.localizedDescription)")
            }
        }
    }

    /// Whether this host's night ends on its own once every action is in (HAMZA-145). Citizens
    /// and eliminated hosts have nothing to submit; an alive inspector reads the result first.
    private func autoFinishes(role: Role?, isAlive: Bool) -> Bool {
        guard multiplayerStore.isHost else { return false }
        if isAlive && role == .inspector { return false }
        return hasSubmitted || role == .citizen || !isAlive
    }

    private func autoFinishNightIfReady() {
        guard let me = multiplayerStore.myPlayer,
              autoFinishes(role: me.role, isAlive: me.isAlive),
              multiplayerStore.isPhaseReadyToAdvance, !isRecording else { return }
        finishNight()
    }

    /// After a relaunch, show the action already submitted this round (including the inspector result).
    private func restoreSubmittedAction() {
        guard let action = multiplayerStore.myNightAction else { return }
        hasSubmitted = true
        selectedTargetId = action.targetPlayerId
        if let result = action.actionData?.inspectorResult {
            inspectorResult = result
        }
    }
}

// MARK: - Target Grid Cell
// HAMZA-142: Grid cell for player selection with proper text sizes

struct TargetGridCell: View {
    let name: String
    let isSelected: Bool
    let accentColor: Color
    let voteCount: Int  // HAMZA-FIX: Vote count for real-time coordination display
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Icon with vote count badge
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? accentColor.opacity(0.2) : Design.Colors.surface2)
                            .frame(width: 48, height: 48)
                        Image(systemName: "person.fill")
                            .font(Design.Typography.title3)
                            .foregroundStyle(isSelected ? accentColor : Design.Colors.textSecondary)
                    }
                    .accessibilityHidden(true)

                    // Vote count badge - only show if > 0
                    if voteCount > 0 {
                        Text("\(voteCount)")
                            .font(Design.Typography.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Design.Colors.surface0)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(accentColor)
                            )
                            .offset(x: 4, y: -4)
                            .accessibilityLabel("\(voteCount) votes")
                    }
                }

                // Name
                Text(name)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: Design.Radii.medium)
                    .fill(isSelected ? accentColor.opacity(0.1) : Design.Colors.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.medium)
                    .stroke(isSelected ? accentColor : Design.Colors.stroke.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legacy Target Player Button (kept for backward compatibility)
// HAMZA-141: Made more compact for better display with many players
// Use CompactTargetCell for grid layouts

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
                        .font(Design.Typography.body)
                        .foregroundStyle(
                            isSelected
                                ? accentColor
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
                        .font(Design.Typography.title3)
                        .foregroundStyle(accentColor)
                        .accessibilityHidden(true)
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
    MultiplayerNightView(nightIndex: 0)
        .environmentObject(MultiplayerGameStore())
        .preferredColorScheme(.dark)
}
