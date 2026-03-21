import SwiftUI
import AVFoundation

struct NightWakeUpView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedTargetID: UUID?
    @State private var showResult = false
    @State private var investigationResult: (isMafia: Bool, role: Role)?
    @State private var investigationWasBlocked = false
    @State private var showTransition = false
    @State private var showInitialSleepScreen = true
    @State private var showStartNightTransition = false
    @State private var showEndGameConfirmation = false
    @State private var wakeUpSoundPlayer: AVAudioPlayer?
    @State private var awaitingMafiaWakeCue = true
    @State private var isAudioSessionConfigured = false
    @State private var showBotActing = false
    @State private var botActingRole: Role?
    @State private var isExecutingSilently = false
    private let botService = BotDecisionService()

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            if showBotActing, let role = botActingRole {
                botActingView(for: role)
                    .transition(.opacity)
            } else if showStartNightTransition {
                TransitionBlurView()
                    .transition(.opacity)
            } else if showTransition {
                TransitionBlurView()
                    .transition(.opacity)
            } else if showInitialSleepScreen, case .nightWakeUp(.mafia) = store.state.currentPhase {
                initialSleepScreen
                    .transition(.opacity)
            } else {
                mainContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEndGameConfirmation = true
                } label: {
                    Text("End Game")
                        .foregroundColor(Design.Colors.dangerRed)
                }
            }
        }
        .alert("Are you sure you want to end the game?", isPresented: $showEndGameConfirmation) {
            Button("End Game", role: .destructive) {
                store.endGameEarly()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will end the current game without determining a winner.")
        }
        .onAppear {
            configureAudioSessionIfNeeded()
            isExecutingSilently = false

            // Show initial sleep screen when entering night for the first time
            if case .nightWakeUp(.mafia) = store.state.currentPhase {
                showInitialSleepScreen = true
                awaitingMafiaWakeCue = true
            }
            maybePlayCurrentWakeUpSound()
            checkForBotAction()

            // Check if all players of this role are bots - if so, auto-progress
            if shouldAutoExecuteForAllBots() {
                scheduleAutoContinueForAllBots()
            }
        }
        .onChange(of: store.state.currentPhase) { _, newPhase in
            isExecutingSilently = false
            if case .nightWakeUp(let role) = newPhase, role == .mafia {
                awaitingMafiaWakeCue = true
            }
            maybePlayCurrentWakeUpSound()
            checkForBotAction()

            // Check if all players of this role are bots - if so, auto-progress
            if shouldAutoExecuteForAllBots() {
                scheduleAutoContinueForAllBots()
            }
        }
        .onChange(of: store.currentNightIndex) { _, _ in
            // Reset sleep screen for each new night
            if case .nightWakeUp(.mafia) = store.state.currentPhase {
                showInitialSleepScreen = true
                awaitingMafiaWakeCue = true
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch store.state.currentPhase {
        case .nightWakeUp(let role):
            wakeUpScreen(for: role)
        case .nightAction(let role):
            actionScreen(for: role)
        case .nightTransition:
            TransitionBlurView()
        default:
            Text("Loading...")
                .foregroundColor(Design.Colors.textSecondary)
        }
    }

    // MARK: - Initial Sleep Screen

    private var initialSleepScreen: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 32) {
                // Moon icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Design.Colors.brandGold.opacity(0.3),
                                    Design.Colors.brandGold.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: Design.Colors.glowGold.opacity(0.5), radius: 20)

                    Image(systemName: "moon.stars.fill")
                        .font(Design.Typography.displayEmoji)
                        .foregroundStyle(Design.Colors.brandGold)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 16) {
                    Text("Night \(store.currentNightIndex)")
                        .font(Design.Typography.largeTitle)
                        .foregroundColor(Design.Colors.textPrimary)

                    Text("Everyone Close Your Eyes")
                        .font(Design.Typography.title2)
                        .foregroundColor(Design.Colors.textSecondary)

                    Text("Place the phone in the middle")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            // Start Night button
            Button {
                // Play haptic
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Show transition blur
                withAnimation(.easeInOut(duration: 0.3)) {
                    showStartNightTransition = true
                }

                // After 2 seconds, play sound and show mafia wake up
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // Play mafia wake-up cue
                    awaitingMafiaWakeCue = false
                    playWakeUpSound(for: .mafia)

                    withAnimation(.easeInOut(duration: 0.3)) {
                        showStartNightTransition = false
                        showInitialSleepScreen = false
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text("Everyone Ready - Start Night")
                        .font(Design.Typography.headline)
                    Image(systemName: "arrow.right.circle.fill")
                        .font(Design.Typography.title3)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .padding(.horizontal, Design.Spacing.lg)
            .accessibleButton("Everyone ready, start night", hint: "Begins the night phase")
        }
        .accessiblePhaseHeader("Night \(store.currentNightIndex)", instruction: "Everyone close your eyes. Place the phone in the middle.")
    }

    // MARK: - Wake Up Screens

    // PERF: @ViewBuilder enables view identity preservation, reduces temporary allocations
    @ViewBuilder
    private func wakeUpScreen(for role: Role) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 32) {
                // Role-specific wake up content
                Group {
                    switch role {
                    case .mafia:
                        mafiaWakeUpContent
                    case .inspector:
                        policeWakeUpContent
                    case .doctor:
                        doctorWakeUpContent
                    case .citizen:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.top, Design.Spacing.xl)
            // Leave room for the pinned button
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                // Play haptic
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Transition to action
                store.beginRoleAction(role)
            } label: {
                HStack(spacing: 12) {
                    Text("Continue")
                        .font(Design.Typography.headline)
                    Image(systemName: "arrow.right.circle.fill")
                        .font(Design.Typography.title3)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.top, Design.Spacing.md)
            .padding(.bottom, Design.Spacing.lg)
            .background(
                Design.Colors.surface0
                    .opacity(0.98)
                    .ignoresSafeArea()
            )
            .accessibleButton("Continue to \(role.displayName) action", hint: "Proceed to make your choice")
        }
    }

    private var mafiaWakeUpContent: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(Design.Colors.dangerRed.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .shadow(color: Design.Colors.glowRed, radius: 20)

                Image(systemName: "flame.fill")
                    .font(Design.Typography.displayEmoji)
                    .foregroundStyle(Design.Colors.dangerRed)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                Text("Mafia, Wake Up")
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(Design.Colors.dangerRed)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("All mafia members:")
                        .font(Design.Typography.title3)
                        .foregroundColor(Design.Colors.textSecondary)

                    // Show all mafia members
                    VStack(spacing: 12) {
                        ForEach(store.mafiaPlayers, id: \.id) { player in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Design.Colors.dangerRed.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(player.name.prefix(1).uppercased())
                                            .font(Design.Typography.subheadline)
                                            .foregroundColor(Design.Colors.dangerRed)
                                    )

                                Text(player.name)
                                    .font(Design.Typography.headline)
                                    .foregroundColor(Design.Colors.textPrimary)

                                if !player.alive {
                                    Text("(Dead)")
                                        .font(Design.Typography.caption)
                                        .foregroundColor(Design.Colors.textTertiary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Design.Colors.surface1)
                            .cornerRadius(Design.Radii.medium)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Spacing.lg)

                    Text("Discuss among yourselves and choose a target")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var policeWakeUpContent: some View {
        let inspectorPlayers = store.state.players.filter { $0.role == .inspector }
        return VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(Design.Colors.actionBlue.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .shadow(color: Design.Colors.glowBlue, radius: 20)

                Image(systemName: "eye.fill")
                    .font(Design.Typography.displayEmoji)
                    .foregroundStyle(Design.Colors.actionBlue)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                Text("Police, Wake Up")
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(Design.Colors.actionBlue)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("All police members:")
                        .font(Design.Typography.title3)
                        .foregroundColor(Design.Colors.textSecondary)

                    VStack(spacing: 12) {
                        ForEach(inspectorPlayers, id: \.id) { player in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Design.Colors.actionBlue.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(player.name.prefix(1).uppercased())
                                            .font(Design.Typography.subheadline)
                                            .foregroundColor(Design.Colors.actionBlue)
                                    )

                                Text(player.name)
                                    .font(Design.Typography.headline)
                                    .foregroundColor(Design.Colors.textPrimary)

                                if !player.alive {
                                    Text("(Dead)")
                                        .font(Design.Typography.caption)
                                        .foregroundColor(Design.Colors.textTertiary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Design.Colors.surface1)
                            .cornerRadius(Design.Radii.medium)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Spacing.lg)

                    Text("You can investigate one player to discover their role")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var doctorWakeUpContent: some View {
        let doctorPlayers = store.state.players.filter { $0.role == .doctor }
        return VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(Design.Colors.successGreen.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .shadow(color: Design.Colors.glowGreen, radius: 20)

                Image(systemName: "cross.case.fill")
                    .font(Design.Typography.displayEmoji)
                    .foregroundStyle(Design.Colors.successGreen)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                Text("Doctor, Wake Up")
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(Design.Colors.successGreen)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("All doctors:")
                        .font(Design.Typography.title3)
                        .foregroundColor(Design.Colors.textSecondary)

                    VStack(spacing: 12) {
                        ForEach(doctorPlayers, id: \.id) { player in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Design.Colors.successGreen.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(player.name.prefix(1).uppercased())
                                            .font(Design.Typography.subheadline)
                                            .foregroundColor(Design.Colors.successGreen)
                                    )

                                Text(player.name)
                                    .font(Design.Typography.headline)
                                    .foregroundColor(Design.Colors.textPrimary)

                                if !player.alive {
                                    Text("(Dead)")
                                        .font(Design.Typography.caption)
                                        .foregroundColor(Design.Colors.textTertiary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Design.Colors.surface1)
                            .cornerRadius(Design.Radii.medium)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Spacing.lg)

                    Text("You can protect one player from the Mafia's attack tonight")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Action Screens

    @ViewBuilder
    private func actionScreen(for role: Role) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                roleActionHeader(for: role)

                // Player selection
                if !showResult {
                    playerSelectionList(for: role)
                } else if investigationWasBlocked {
                    blockedInvestigationView
                } else if let result = investigationResult {
                    investigationResultView(result: result)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.top, Design.Spacing.xl)
            // Add actual bottom padding to prevent overlap with action button
            .padding(.bottom, 120)
        }
        .safeAreaInset(edge: .bottom) {
            actionButton(for: role)
        }
    }

    private func roleActionHeader(for role: Role) -> some View {
        VStack(spacing: 12) {
            Text(roleActionTitle(for: role))
                .font(Design.Typography.title2)
                .foregroundColor(Design.Colors.textPrimary)

            if !showResult {
                Text(roleActionSubtitle(for: role))
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func playerSelectionList(for role: Role) -> some View {
        let players = filteredPlayers(for: role)
        // Adaptive spacing: use smaller spacing when there are many players
        let spacing: CGFloat = players.count > 10 ? 8 : 12

        return LazyVStack(spacing: spacing) {
            ForEach(players) { player in
                PlayerSelectionRow(
                    player: player,
                    isSelected: selectedTargetID == player.id,
                    accent: roleColor(for: role)
                ) {
                    selectedTargetID = player.id

                    // Play haptic
                    let generator = UISelectionFeedbackGenerator()
                    generator.selectionChanged()
                }
            }
        }
    }

    private func investigationResultView(result: (isMafia: Bool, role: Role)) -> some View {
        VStack(spacing: 24) {
            // Result card
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(result.isMafia ? Design.Colors.dangerRed.opacity(0.2) : Design.Colors.successGreen.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .shadow(color: result.isMafia ? Design.Colors.glowRed : Design.Colors.glowGreen, radius: 20)

                    Image(systemName: result.role.symbolName)
                        .font(Design.Typography.displayEmoji)
                        .foregroundStyle(result.role.accentColor)
                        .accessibilityHidden(true)
                }

                Text(result.isMafia ? "This player is MAFIA!" : "This player is INNOCENT")
                    .font(Design.Typography.title1)
                    .foregroundColor(result.isMafia ? Design.Colors.dangerRed : Design.Colors.successGreen)
                    .multilineTextAlignment(.center)

                Text("Role: \(result.role.displayName)")
                    .font(Design.Typography.title3)
                    .foregroundColor(Design.Colors.textPrimary)

                Text("Remember this information for the day discussion")
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Design.Radii.large)
                    .fill(Design.Colors.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radii.large)
                            .stroke(result.isMafia ? Design.Colors.dangerRed.opacity(0.5) : Design.Colors.successGreen.opacity(0.5), lineWidth: 2)
                    )
            )
        }
    }

    private var blockedInvestigationView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Design.Colors.textSecondary.opacity(0.18))
                        .frame(width: 100, height: 100)

                    Image(systemName: "eye.slash.fill")
                        .font(Design.Typography.displayEmoji)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .accessibilityHidden(true)
                }

                Text("Investigation Blocked")
                    .font(Design.Typography.title1)
                    .foregroundColor(Design.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("You cannot identify another Police player.")
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .cardStyle()
        }
    }

    private func actionButton(for role: Role) -> some View {
        VStack(spacing: 0) {
            Button {
                handleActionComplete(for: role)
            } label: {
                HStack(spacing: 12) {
                    Text(buttonText(for: role))
                        .font(Design.Typography.headline)
                    Image(systemName: "checkmark.circle.fill")
                        .font(Design.Typography.title3)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .disabled(selectedTargetID == nil && !showResult)
            .accessibleButton(buttonText(for: role))
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.md)
        .background(Design.Colors.surface0.opacity(0.98))
    }

    // MARK: - Helper Methods

    private func filteredPlayers(for role: Role) -> [Player] {
        switch role {
        case .mafia:
            return store.alivePlayers.filter { $0.role != .mafia }
        case .inspector:
            return store.alivePlayers.filter { $0.role != .inspector }
        case .doctor:
            return store.alivePlayers
        case .citizen:
            return []
        }
    }

    private func roleColor(for role: Role) -> Color {
        role.accentColor
    }

    private func roleActionTitle(for role: Role) -> String {
        switch role {
        case .mafia: return "Choose Your Target"
        case .inspector: return showResult ? "Investigation Result" : "Investigate a Player"
        case .doctor: return "Protect a Player"
        case .citizen: return ""
        }
    }

    private func roleActionSubtitle(for role: Role) -> String {
        switch role {
        case .mafia: return "Select one player to eliminate tonight"
        case .inspector: return "Choose one player to investigate their role"
        case .doctor: return "Choose one player to protect from the Mafia"
        case .citizen: return ""
        }
    }

    private func buttonText(for role: Role) -> String {
        if showResult {
            return "I've Seen It - Continue"
        }

        switch role {
        case .mafia: return "Confirm Target"
        case .inspector: return "Investigate"
        case .doctor: return "Protect This Player"
        case .citizen: return "Continue"
        }
    }

    private func handleActionComplete(for role: Role) {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        switch role {
        case .mafia:
            // SECURITY FIX: Validate target is not mafia
            if let targetID = selectedTargetID,
               let target = store.player(by: targetID),
               target.role == .mafia {
                // Invalid target - show error and clear selection
                let errorGenerator = UINotificationFeedbackGenerator()
                errorGenerator.notificationOccurred(.error)

                // Clear selection
                selectedTargetID = nil
                return
            }

            // Record mafia target
            // Only use data from unresolved night (current night), not from previous resolved nights
            let currentNight = store.state.nightHistory.last
            let isCurrentNight = currentNight?.isResolved == false

            store.endNight(
                mafiaTargetID: selectedTargetID,
                inspectorCheckedID: isCurrentNight ? currentNight?.inspectorCheckedPlayerID : nil,
                doctorProtectedID: isCurrentNight ? currentNight?.doctorProtectedPlayerID : nil
            )

            // Show transition and move to next role
            withAnimation(.easeInOut(duration: 0.3)) {
                showTransition = true
            }

            // Play sound and transition after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                store.completeRoleAction()
                store.transitionToNextRole()

                withAnimation(.easeInOut(duration: 0.3)) {
                    showTransition = false
                    selectedTargetID = nil
                }
            }

        case .inspector:
            if !showResult {
                if let targetID = selectedTargetID,
                   store.player(by: targetID) != nil {
                    // Record investigation
                    // Only use data from unresolved night (current night)
                    let currentNight = store.state.nightHistory.last
                    let isCurrentNight = currentNight?.isResolved == false

                    store.endNight(
                        mafiaTargetID: isCurrentNight ? currentNight?.mafiaTargetPlayerID : nil,
                        inspectorCheckedID: selectedTargetID,
                        doctorProtectedID: isCurrentNight ? currentNight?.doctorProtectedPlayerID : nil
                    )

                    if let recordedNight = store.state.nightHistory.last,
                       let role = recordedNight.inspectorResultRole,
                       let isMafia = recordedNight.inspectorResultIsMafia {
                        investigationResult = (isMafia: isMafia, role: role)
                        investigationWasBlocked = false
                    } else {
                        investigationResult = nil
                        investigationWasBlocked = true
                    }

                    withAnimation {
                        showResult = true
                    }
                }
            } else {
                // Transition to next role
                withAnimation(.easeInOut(duration: 0.3)) {
                    showTransition = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    store.completeRoleAction()
                    store.transitionToNextRole()

                    withAnimation(.easeInOut(duration: 0.3)) {
                        showTransition = false
                        selectedTargetID = nil
                        showResult = false
                        investigationResult = nil
                        investigationWasBlocked = false
                    }
                }
            }

        case .doctor:
            // Record doctor protection
            // Only use data from unresolved night (current night)
            let currentNight = store.state.nightHistory.last
            let isCurrentNight = currentNight?.isResolved == false

            store.endNight(
                mafiaTargetID: isCurrentNight ? currentNight?.mafiaTargetPlayerID : nil,
                inspectorCheckedID: isCurrentNight ? currentNight?.inspectorCheckedPlayerID : nil,
                doctorProtectedID: selectedTargetID
            )

            // Transition to morning
            withAnimation(.easeInOut(duration: 0.3)) {
                showTransition = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                store.completeRoleAction()

                // Resolve night outcome and go to morning
                // Get the updated night record after endNight
                let updatedNight = store.state.nightHistory.last
                // Check if doctor's protection matches mafia's target
                let wasSaved = updatedNight?.mafiaTargetPlayerID == updatedNight?.doctorProtectedPlayerID
                store.resolveNightOutcome(targetWasSaved: wasSaved)
                store.transitionToMorning()

                withAnimation(.easeInOut(duration: 0.3)) {
                    showTransition = false
                    selectedTargetID = nil
                }
            }

        case .citizen:
            break
        }
    }

    private func configureAudioSessionIfNeeded() {
        guard !isAudioSessionConfigured else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            isAudioSessionConfigured = true
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    private func maybePlayCurrentWakeUpSound() {
        guard case .nightWakeUp(let role) = store.state.currentPhase else { return }

        if role == .mafia && awaitingMafiaWakeCue {
            // We're still showing the pre-night instructions, so wait for the host to start the night
            return
        }

        playWakeUpSound(for: role)
    }

    private func playWakeUpSound(for role: Role) {
        guard let fileName = wakeUpSoundFileName(for: role) else { return }
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") else {
            print("Missing wake-up sound file: \\(fileName).wav")
            return
        }

        wakeUpSoundPlayer?.stop()

        do {
            wakeUpSoundPlayer = try AVAudioPlayer(contentsOf: url)
            wakeUpSoundPlayer?.volume = 1.0
            wakeUpSoundPlayer?.prepareToPlay()
            wakeUpSoundPlayer?.play()
        } catch {
            print("Failed to play wake-up sound: \\(error.localizedDescription)")
        }
    }

    private func wakeUpSoundFileName(for role: Role) -> String? {
        switch role {
        case .mafia:
            return "mafia_gunshot"
        case .inspector:
            return "police_siren"
        case .doctor:
            return "doctor_ecg"
        case .citizen:
            return nil
        }
    }

    // MARK: - Bot Handling

    /// Checks if ALL players with the current role are bots (silent execution mode)
    private func shouldAutoExecuteForAllBots() -> Bool {
        // Check for both wake-up and action phases
        if case .nightWakeUp(let role) = store.state.currentPhase {
            return store.allBotsForRole(role)
        }
        if case .nightAction(let role) = store.state.currentPhase {
            return store.allBotsForRole(role)
        }
        return false
    }

    /// Schedules automatic progression through the UI when all role players are bots
    private func scheduleAutoContinueForAllBots() {
        guard case .nightWakeUp(let role) = store.state.currentPhase else { return }

        // Auto-click "Continue" button after a realistic delay (4-6 seconds)
        // Longer delay prevents humans from getting suspicious about short bot turns
        let delay = Double.random(in: 4.0...6.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Check if we're still in the wake-up phase for this role
            if case .nightWakeUp(let currentRole) = self.store.state.currentPhase,
               currentRole == role {
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Transition to action phase
                self.store.beginRoleAction(role)
            }
        }
    }

    /// Checks if the current role belongs to a bot and auto-executes if so
    private func checkForBotAction() {
        // Only handle action phase - auto-execute if all role players are bots
        if case .nightAction(let role) = store.state.currentPhase {
            if shouldAutoExecuteForAllBots() {
                scheduleAutoBotActionInActionPhase(for: role)
            }
        }
    }

    /// Schedules automatic bot action execution during the action phase when all role players are bots
    private func scheduleAutoBotActionInActionPhase(for role: Role) {
        // Show bot acting animation
        botActingRole = role
        withAnimation {
            showBotActing = true
        }

        Task {
            // Simulate thinking delay for realism (2-3 seconds)
            await botService.simulateThinking()

            // Execute the bot action
            await executeBotAction(for: role)

            // Hide bot animation
            await MainActor.run {
                withAnimation {
                    showBotActing = false
                }
            }
        }
    }

    /// Executes a bot's action for the given role
    private func executeBotAction(for role: Role) async {
        await MainActor.run {
            switch role {
            case .mafia:
                executeBotMafiaAction()
            case .inspector:
                executeBotInspectorAction()
            case .doctor:
                executeBotDoctorAction()
            case .citizen:
                break
            }
        }
    }

    private func executeBotMafiaAction() {
        // Find bot Mafia player(s)
        let botMafia = store.aliveMafia.filter { $0.isBot }
        guard let botMafiaPlayer = botMafia.first else { return }

        // Get bot decision
        let targetID = botService.chooseMafiaTarget(
            botPlayer: botMafiaPlayer,
            alivePlayers: store.alivePlayers,
            nightHistory: store.state.nightHistory
        )

        // Record action
        let currentNight = store.state.nightHistory.last
        let isCurrentNight = currentNight?.isResolved == false

        store.endNight(
            mafiaTargetID: targetID,
            inspectorCheckedID: isCurrentNight ? currentNight?.inspectorCheckedPlayerID : nil,
            doctorProtectedID: isCurrentNight ? currentNight?.doctorProtectedPlayerID : nil
        )

        // Transition to next role
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            store.completeRoleAction()
            store.transitionToNextRole()
        }
    }

    private func executeBotInspectorAction() {
        // Find bot Inspector
        let botInspectors = store.alivePlayers.filter { $0.role == .inspector && $0.isBot }
        guard let botInspector = botInspectors.first else { return }

        // Get bot decision
        let targetID = botService.chooseInspectorTarget(
            botPlayer: botInspector,
            alivePlayers: store.alivePlayers,
            nightHistory: store.state.nightHistory
        )

        // Record action (no need to show result to bot)
        let currentNight = store.state.nightHistory.last
        let isCurrentNight = currentNight?.isResolved == false

        store.endNight(
            mafiaTargetID: isCurrentNight ? currentNight?.mafiaTargetPlayerID : nil,
            inspectorCheckedID: targetID,
            doctorProtectedID: isCurrentNight ? currentNight?.doctorProtectedPlayerID : nil
        )

        // Transition to next role
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            store.completeRoleAction()
            store.transitionToNextRole()
        }
    }

    private func executeBotDoctorAction() {
        // Find bot Doctor
        let botDoctors = store.alivePlayers.filter { $0.role == .doctor && $0.isBot }
        guard let botDoctor = botDoctors.first else { return }

        // Get bot decision
        let targetID = botService.chooseDoctorProtection(
            botPlayer: botDoctor,
            alivePlayers: store.alivePlayers,
            nightHistory: store.state.nightHistory
        )

        // Record action
        let currentNight = store.state.nightHistory.last
        let isCurrentNight = currentNight?.isResolved == false

        store.endNight(
            mafiaTargetID: isCurrentNight ? currentNight?.mafiaTargetPlayerID : nil,
            inspectorCheckedID: isCurrentNight ? currentNight?.inspectorCheckedPlayerID : nil,
            doctorProtectedID: targetID
        )

        // Transition to next role (morning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            store.completeRoleAction()

            let updatedNight = store.state.nightHistory.last
            // Check if doctor's protection matches mafia's target
            let wasSaved = updatedNight?.mafiaTargetPlayerID == updatedNight?.doctorProtectedPlayerID
            store.resolveNightOutcome(targetWasSaved: wasSaved)
            store.transitionToMorning()
        }
    }

    /// View shown when a bot is taking their turn
    @ViewBuilder
    private func botActingView(for role: Role) -> some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 32) {
                // Bot icon with pulsing animation
                ZStack {
                    Circle()
                        .fill(role.accentColor.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .shadow(color: role.accentColor.opacity(0.5), radius: 20)

                    Image(systemName: "cpu.fill")
                        .font(Design.Typography.displayEmoji)
                        .foregroundStyle(role.accentColor)
                        .accessibilityHidden(true)
                }
                .scaleEffect(showBotActing ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: showBotActing)

                VStack(spacing: 16) {
                    Text("Bot is Deciding...")
                        .font(Design.Typography.largeTitle)
                        .foregroundStyle(role.accentColor)

                    Text(role.displayName)
                        .font(Design.Typography.title3)
                        .foregroundColor(Design.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Bot is deciding. \(role.displayName) is making their choice.")

                // Progress indicator
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(role.accentColor)
                    .scaleEffect(1.5)
            }

            Spacer()
        }
    }
}

// MARK: - Player Selection Row

private struct PlayerSelectionRow: View {
    let player: Player
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Player initial
                ZStack {
                    Circle()
                        .fill(isSelected ? accent.opacity(0.3) : Design.Colors.surface2)
                        .frame(width: 50, height: 50)

                    Text(player.name.prefix(1).uppercased())
                        .font(Design.Typography.title3)
                        .foregroundColor(isSelected ? accent : Design.Colors.textSecondary)
                }
                .accessibilityHidden(true)

                // Name
                Text(player.name)
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.textPrimary)

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Design.Typography.title2)
                        .foregroundColor(accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Design.Radii.medium)
                    .fill(isSelected ? accent.opacity(0.1) : Design.Colors.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radii.medium)
                            .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibleSelection(player.name, isSelected: isSelected, hint: isSelected ? "Currently selected target" : "Tap to select as target")
    }
}

// MARK: - Transition Blur View

private struct TransitionBlurView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Design.Colors.surface2, Design.Colors.surface1],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: "moon.stars.fill")
                        .font(Design.Typography.displayEmoji)
                        .foregroundStyle(Design.Colors.brandGold)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 12) {
                    Text("Everyone Go to Sleep")
                        .font(Design.Typography.title2)
                        .foregroundColor(Design.Colors.textPrimary)

                    Text("Waiting for next role...")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Everyone go to sleep. Waiting for next role.")
    }
}
