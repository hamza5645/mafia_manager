import SwiftUI

// MARK: - App Lifecycle Notification Names

extension Notification.Name {
    /// Posted when the app becomes active (returns from background)
    static let appDidBecomeActive = Notification.Name("appDidBecomeActive")

    /// Posted when the app is about to enter background
    static let appWillEnterBackground = Notification.Name("appWillEnterBackground")
}

@main
struct mafia_managerApp: App {
    @StateObject private var gameStore = GameStore()
    @StateObject private var authStore = AuthStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Setup the connection between stores
        // Note: This happens before @StateObject initialization completes,
        // so we'll set it in onAppear instead
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gameStore)
                .environmentObject(authStore)
                .tint(Design.Colors.actionBlue)
                .preferredColorScheme(.dark)
                .onAppear {
                    gameStore.setAuthStore(authStore)
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .background, .inactive:
                        // Save game state immediately
                        try? Persistence.shared.saveImmediately(gameStore.state)
                        // Notify multiplayer services to pause (save battery)
                        NotificationCenter.default.post(name: .appWillEnterBackground, object: nil)
                    case .active:
                        // Notify multiplayer services to reconnect
                        NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
                    @unknown default:
                        break
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var gameStore: GameStore
    @EnvironmentObject private var authStore: AuthStore
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false

    var body: some View {
        NavigationStack {
            if !hasSeenIntro {
                IntroView(
                    onStart: {
                        hasSeenIntro = true
                    },
                    onSkip: {
                        hasSeenIntro = true
                    }
                )
            } else if gameStore.state.players.isEmpty || gameStore.isFreshSetup {
                GameModeSelectionView()
            } else {
                phaseBasedView
            }
        }
        .id(gameStore.flowID)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        ))
        .animation(.easeInOut(duration: 0.3), value: gameStore.flowID)
        .background(Design.Colors.surface0.ignoresSafeArea())
    }

    @ViewBuilder
    private var phaseBasedView: some View {
        switch gameStore.state.currentPhase {
        case .roleReveal:
            RoleRevealView()
        case .nightWakeUp, .nightAction, .nightTransition:
            NightWakeUpView()
        case .morning:
            MorningSummaryView()
        case .deathReveal, .voteDeathReveal:
            DeathRevealView()
        case .botVotingReveal:
            BotVotingRevealView()
        case .votingIndividual(let currentPlayerIndex):
            VotingView(currentPlayerIndex: currentPlayerIndex)
        case .votingResults:
            VoteResultsView()
        case .gameOver:
            GameOverView()
        }
    }
}
