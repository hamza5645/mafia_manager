import SwiftUI

@main
struct mafia_managerApp: App {
    @StateObject private var gameStore = GameStore()
    @StateObject private var authStore = AuthStore()

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
                SetupView()
            } else {
                phaseBasedView
            }
        }
        .id(gameStore.flowID)
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
        case .deathReveal:
            DeathRevealView()
        case .day:
            DayManagementView()
        case .gameOver:
            GameOverView()
        }
    }
}
