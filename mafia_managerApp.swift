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

    var body: some View {
        Group {
            if authStore.isAuthenticated {
                AuthenticatedRootView()
            } else {
                LoginView()
            }
        }
    }
}

struct AuthenticatedRootView: View {
    @EnvironmentObject private var gameStore: GameStore

    var body: some View {
        NavigationStack {
            if gameStore.state.players.isEmpty || gameStore.isFreshSetup {
                SetupView()
            } else if gameStore.state.isGameOver {
                GameOverView()
            } else {
                AssignmentsView()
            }
        }
        .id(gameStore.flowID)
        .background(Design.Colors.surface0.ignoresSafeArea())
    }
}
