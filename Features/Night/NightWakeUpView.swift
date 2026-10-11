import SwiftUI

struct NightWakeUpView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedTargetID: UUID?
    @State private var showResult = false
    @State private var investigationResult: (isMafia: Bool, role: Role)?
    @State private var investigationWasBlocked = false
    /// Role whose turn is ending behind the "go to sleep" screen; its delay runs in `.task(id: endingTurn)`.
    @State private var endingTurn: Role?
    @State private var showInitialSleepScreen = true
    @State private var showStartNightTransition = false
    @State private var showEndGameConfirmation = false
    @State private var awaitingMafiaWakeCue = true
    @State private var showBotActing = false
    @State private var botActingRole: Role?
    @State private var successHaptic = 0
    @State private var selectionHaptic = 0
    @State private var errorHaptic = 0
    private let botService = BotDecisionService()

    /// What the bots do for the current step of the night.
    enum BotAction: Equatable {
        /// Every living player of the role is a bot: press "Continue" on its wake-up screen.
        case autoContinue(Role)
        /// Every living player of the role is a bot: take the role's turn.
        case takeTurn(Role)
    }

    /// The all-bot Mafia wake-up waits behind the "Everyone Ready - Start Night" gate like a human
    /// Mafia does. Other roles are never gated, which also covers a relaunch mid-night, where the
    /// gate state starts out true (PA-14).
    static func botAction(for phase: GamePhase, sleepGateUp: Bool, allBots: (Role) -> Bool) -> BotAction? {
        switch phase {
        case .nightWakeUp(let role) where allBots(role) && (role != .mafia || !sleepGateUp):
            return .autoContinue(role)
        case .nightAction(let role) where allBots(role):
            return .takeTurn(role)
        default:
            return nil
        }
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            if showBotActing, let role = botActingRole {
                BotActingView(role: role)
                    .transition(.opacity)
            } else if showStartNightTransition || endingTurn != nil {
                GoToSleepInterstitial()
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
        .sensoryFeedback(.success, trigger: successHaptic)
        .sensoryFeedback(.selection, trigger: selectionHaptic)
        .sensoryFeedback(.error, trigger: errorHaptic)
        .onAppear {
            // Show initial sleep screen when entering night for the first time
            if case .nightWakeUp(.mafia) = store.state.currentPhase {
                showInitialSleepScreen = true
                awaitingMafiaWakeCue = true
            }
            maybePlayCurrentWakeUpSound()
        }
        .onChange(of: store.state.currentPhase) { _, newPhase in
            if case .nightWakeUp(let role) = newPhase, role == .mafia {
                awaitingMafiaWakeCue = true
            }
            maybePlayCurrentWakeUpSound()
        }
        .onChange(of: store.currentNightIndex) { _, _ in
            // Reset sleep screen for each new night
            if case .nightWakeUp(.mafia) = store.state.currentPhase {
                showInitialSleepScreen = true
                awaitingMafiaWakeCue = true
            }
        }
        // Every timed step of the night is a task owned by this view: End Game removes the view,
        // which cancels the step before it can record an action or resolve the night (PA-58).
        .task(id: showStartNightTransition) {
            // After 2 seconds, play the Mafia cue and show the Mafia wake-up screen
            guard showStartNightTransition, await pause(seconds: 2.0) else { return }
            awaitingMafiaWakeCue = false
            SoundManager.shared.playWakeUp(for: .mafia)

            withAnimation(.easeInOut(duration: 0.3)) {
                showStartNightTransition = false
                // Lowering the gate is what arms an all-bot Mafia's auto-continue (bot task below)
                showInitialSleepScreen = false
            }
        }
        .task(id: endingTurn) {
            guard let role = endingTurn, await pause(seconds: role == .doctor ? 2.0 : 3.0) else { return }
            finishTurn(role)

            withAnimation(.easeInOut(duration: 0.3)) {
                endingTurn = nil
                selectedTargetID = nil
                showResult = false
                investigationResult = nil
                investigationWasBlocked = false
            }
        }
        .task(id: BotStep(phase: store.state.currentPhase, sleepGateUp: showInitialSleepScreen)) {
            await runBotStep()
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
            GoToSleepInterstitial()
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
                .accessiblePhaseHeader(
                    "Night \(store.currentNightIndex)",
                    instruction: "Everyone close your eyes. Place the phone in the middle."
                )
            }

            Spacer()

            // Start Night button
            Button {
                successHaptic += 1
                // The night sounds are built here, not at app launch (PA-55)
                SoundManager.shared.warmUp()

                // Show the transition; `.task(id: showStartNightTransition)` continues after 2 seconds
                withAnimation(.easeInOut(duration: 0.3)) {
                    showStartNightTransition = true
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
        .readableContentWidth()
    }

    // MARK: - Wake Up Screens

    // PERF: @ViewBuilder enables view identity preservation, reduces temporary allocations
    @ViewBuilder
    private func wakeUpScreen(for role: Role) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 32) {
                // Role-specific wake up content
                if role != .citizen {
                    RoleWakeUpContent(role: role, members: store.state.players.filter { $0.role == role })
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.top, Design.Spacing.xl)
            // Leave room for the pinned button
            .padding(.bottom, 120)
            .readableContentWidth()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                successHaptic += 1

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
            .readableContentWidth()
            .background(
                Design.Colors.surface0
                    .opacity(0.98)
                    .ignoresSafeArea()
            )
            .accessibleButton("Continue to \(role.displayName) action", hint: "Proceed to make your choice")
        }
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
            .readableContentWidth()
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

        LazyVStack(spacing: spacing) {
            ForEach(players) { player in
                PlayerSelectionRow(
                    player: player,
                    isSelected: selectedTargetID == player.id,
                    accent: roleColor(for: role)
                ) {
                    selectedTargetID = player.id
                    selectionHaptic += 1
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
        .readableContentWidth()
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
        successHaptic += 1

        switch role {
        case .mafia:
            // SECURITY FIX: Validate target is not mafia
            if let targetID = selectedTargetID,
               let target = store.player(by: targetID),
               target.role == .mafia {
                // Invalid target - show error and clear selection
                errorHaptic += 1

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

            // Show transition; the next role wakes after a delay (`.task(id: endingTurn)`)
            withAnimation(.easeInOut(duration: 0.3)) {
                endingTurn = .mafia
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
                    endingTurn = .inspector
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
                endingTurn = .doctor
            }

        case .citizen:
            break
        }
    }

    /// Ends a role's turn after its action was recorded with `endNight`: wakes the next role, or,
    /// after the doctor, resolves the night (`resolveNightOutcome`) and goes to morning.
    private func finishTurn(_ role: Role) {
        store.completeRoleAction()

        if role == .doctor {
            // Get the updated night record after endNight
            let updatedNight = store.state.nightHistory.last
            // Check if doctor's protection matches mafia's target
            let wasSaved = updatedNight?.mafiaTargetPlayerID == updatedNight?.doctorProtectedPlayerID
            store.resolveNightOutcome(targetWasSaved: wasSaved)
            store.transitionToMorning()
        } else {
            store.transitionToNextRole()
        }
    }

    /// Sleeps for `seconds`; false when the task was cancelled (phase changed or view removed).
    private func pause(seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func maybePlayCurrentWakeUpSound() {
        guard case .nightWakeUp(let role) = store.state.currentPhase else { return }

        if role == .mafia && awaitingMafiaWakeCue {
            return
        }

        SoundManager.shared.playWakeUp(for: role)
    }

    // MARK: - Bot Handling

    /// Restarts the bot task whenever the phase changes or the Mafia sleep gate is lowered.
    private struct BotStep: Equatable {
        let phase: GamePhase
        let sleepGateUp: Bool
    }

    /// Drives the UI for a role whose living players are all bots. Runs in `.task(id: BotStep)`,
    /// so a phase change or End Game cancels it.
    private func runBotStep() async {
        let action = Self.botAction(
            for: store.state.currentPhase,
            sleepGateUp: showInitialSleepScreen,
            allBots: { store.allBotsForRole($0) }
        )

        switch action {
        case .autoContinue(let role):
            // Auto-click "Continue" after a realistic delay (4-6 seconds)
            // Longer delay prevents humans from getting suspicious about short bot turns
            guard await pause(seconds: Double.random(in: 4.0...6.0)) else { return }

            // Same haptic as a human's Continue tap
            successHaptic += 1
            store.beginRoleAction(role)

        case .takeTurn(let role):
            // Show bot acting animation until the turn has moved on
            botActingRole = role
            withAnimation {
                showBotActing = true
            }
            defer {
                withAnimation {
                    showBotActing = false
                }
            }

            // Simulate thinking delay for realism
            await botService.simulateThinking()
            guard !Task.isCancelled, recordBotAction(for: role) else { return }

            // Transition to next role
            guard await pause(seconds: 0.5) else { return }
            finishTurn(role)

        case nil:
            break
        }
    }

    /// Records the bot's choice for `role` with `endNight`; false when no living bot holds the role.
    private func recordBotAction(for role: Role) -> Bool {
        switch role {
        case .mafia:
            return executeBotMafiaAction()
        case .inspector:
            return executeBotInspectorAction()
        case .doctor:
            return executeBotDoctorAction()
        case .citizen:
            return false
        }
    }

    private func executeBotMafiaAction() -> Bool {
        // Find bot Mafia player(s)
        let botMafia = store.aliveMafia.filter { $0.isBot }
        guard let botMafiaPlayer = botMafia.first else { return false }

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
        return true
    }

    private func executeBotInspectorAction() -> Bool {
        // Find bot Inspector
        let botInspectors = store.alivePlayers.filter { $0.role == .inspector && $0.isBot }
        guard let botInspector = botInspectors.first else { return false }

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
        return true
    }

    private func executeBotDoctorAction() -> Bool {
        // Find bot Doctor
        let botDoctors = store.alivePlayers.filter { $0.role == .doctor && $0.isBot }
        guard let botDoctor = botDoctors.first else { return false }

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
        return true
    }
}

// MARK: - Role Wake Up Content

/// Wake-up screen for a night role: its icon, the players who hold it, and what they do tonight.
private struct RoleWakeUpContent: View {
    let role: Role
    let members: [Player]

    private var copy: (title: String, membersTitle: String, instruction: String) {
        switch role {
        case .mafia:
            return ("Mafia, Wake Up", "All mafia members:", "Discuss among yourselves and choose a target")
        case .inspector:
            return ("Police, Wake Up", "All police members:", "You can investigate one player to discover their role")
        case .doctor:
            return ("Doctor, Wake Up", "All doctors:", "You can protect one player from the Mafia's attack tonight")
        case .citizen:
            return ("", "", "")
        }
    }

    var body: some View {
        let accent = role.accentColor

        VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .shadow(color: RoleCardPalette(role: role).glowColor, radius: 20)

                Image(systemName: role.symbolName)
                    .font(Design.Typography.displayEmoji)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                Text(copy.title)
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text(copy.membersTitle)
                        .font(Design.Typography.title3)
                        .foregroundColor(Design.Colors.textSecondary)

                    // Show all members of this role
                    VStack(spacing: 12) {
                        ForEach(members) { player in
                            memberRow(for: player, accent: accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Spacing.lg)

                    Text(copy.instruction)
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

    private func memberRow(for player: Player, accent: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accent.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(player.name.prefix(1).uppercased())
                        .font(Design.Typography.subheadline)
                        .foregroundColor(accent)
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

// MARK: - Bot Acting View

/// Shown while bots take a role's turn
private struct BotActingView: View {
    let role: Role
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 32) {
                // Bot icon, pulsing for as long as this view is shown
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
                .phaseAnimator([1.0, 1.1]) { icon, scale in
                    icon.scaleEffect(reduceMotion ? 1.0 : scale)
                } animation: { _ in
                    .easeInOut(duration: 1.0)
                }

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

// MARK: - Go To Sleep Interstitial

/// Opaque "go to sleep" screen shown between roles. The role screens are removed from the view
/// tree while it shows; that removal, not this view, is what keeps them private.
private struct GoToSleepInterstitial: View {
    var body: some View {
        ZStack {
            Design.Colors.surface1
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
