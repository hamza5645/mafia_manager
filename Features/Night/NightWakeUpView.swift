import SwiftUI
import AVFoundation

struct NightWakeUpView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedTargetID: UUID?
    @State private var showResult = false
    @State private var investigationResult: (isMafia: Bool, role: Role)?
    @State private var showTransition = false
    @State private var showInitialSleepScreen = true
    @State private var showStartNightTransition = false
    @State private var showEndGameConfirmation = false
    @State private var wakeUpSoundPlayer: AVAudioPlayer?
    @State private var awaitingMafiaWakeCue = true
    @State private var isAudioSessionConfigured = false

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            if showStartNightTransition {
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
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(Design.Colors.brandGold)
                }

                VStack(spacing: 16) {
                    Text("Night \(store.currentNightIndex)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
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
                        .font(.system(size: 20, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .padding(.horizontal, Design.Spacing.lg)
        }
    }

    // MARK: - Wake Up Screens

    private func wakeUpScreen(for role: Role) -> some View {
        VStack(spacing: 40) {
            Spacer()

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

            Spacer()

            // Continue button
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
                        .font(.system(size: 20, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .padding(.horizontal, Design.Spacing.lg)
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
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(Design.Colors.dangerRed)
            }

            VStack(spacing: 16) {
                Text("Mafia, Wake Up")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.Colors.dangerRed)

                Text("All mafia members:")
                    .font(Design.Typography.title3)
                    .foregroundColor(Design.Colors.textSecondary)

                // Show all mafia members
                VStack(spacing: 12) {
                    ForEach(store.mafiaPlayers) { player in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Design.Colors.dangerRed.opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(player.name.prefix(1).uppercased())
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
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
                        .background(Design.Colors.surface1)
                        .cornerRadius(Design.Radii.medium)
                    }
                }
                .padding(.horizontal, Design.Spacing.lg)

                Text("Discuss among yourselves and choose a target")
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var policeWakeUpContent: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(Design.Colors.actionBlue.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .shadow(color: Design.Colors.glowBlue, radius: 20)

                Image(systemName: "eye.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(Design.Colors.actionBlue)
            }

            VStack(spacing: 16) {
                Text("Police, Wake Up")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.Colors.actionBlue)

                Text("You are the Police")
                    .font(Design.Typography.title2)
                    .foregroundColor(Design.Colors.textPrimary)

                Text("You can investigate one player to discover their role")
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var doctorWakeUpContent: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(Design.Colors.successGreen.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .shadow(color: Design.Colors.glowGreen, radius: 20)

                Image(systemName: "cross.case.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(Design.Colors.successGreen)
            }

            VStack(spacing: 16) {
                Text("Doctor, Wake Up")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.Colors.successGreen)

                Text("You are the Doctor")
                    .font(Design.Typography.title2)
                    .foregroundColor(Design.Colors.textPrimary)

                Text("You can protect one player from the Mafia's attack tonight")
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Action Screens

    private func actionScreen(for role: Role) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                roleActionHeader(for: role)

                // Player selection
                if !showResult {
                    playerSelectionList(for: role)
                } else if let result = investigationResult {
                    investigationResultView(result: result)
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.top, Design.Spacing.xl)
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

    private func playerSelectionList(for role: Role) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredPlayers(for: role)) { player in
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
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(result.role.accentColor)
                }

                Text(result.isMafia ? "This player is MAFIA!" : "This player is INNOCENT")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
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

    private func actionButton(for role: Role) -> some View {
        VStack(spacing: 0) {
            Button {
                handleActionComplete(for: role)
            } label: {
                HStack(spacing: 12) {
                    Text(buttonText(for: role))
                        .font(Design.Typography.headline)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .disabled(selectedTargetID == nil && !showResult)
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
                // Show investigation result
                if let targetID = selectedTargetID,
                   let target = store.player(by: targetID) {
                    investigationResult = (isMafia: target.role == .mafia, role: target.role)

                    // Record investigation
                    // Only use data from unresolved night (current night)
                    let currentNight = store.state.nightHistory.last
                    let isCurrentNight = currentNight?.isResolved == false

                    store.endNight(
                        mafiaTargetID: isCurrentNight ? currentNight?.mafiaTargetPlayerID : nil,
                        inspectorCheckedID: selectedTargetID,
                        doctorProtectedID: isCurrentNight ? currentNight?.doctorProtectedPlayerID : nil
                    )

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
                let wasSaved = updatedNight?.mafiaTargetPlayerID == selectedTargetID
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
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? accent : Design.Colors.textSecondary)
                }

                // Name
                Text(player.name)
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.textPrimary)

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(accent)
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
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(Design.Colors.brandGold)
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
    }
}
