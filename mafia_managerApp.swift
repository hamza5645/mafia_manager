import SwiftUI

@main
struct mafia_managerApp: App {
    @StateObject private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        NavigationStack {
            if store.state.players.isEmpty || store.isFreshSetup {
                SetupView()
            } else if store.state.isGameOver {
                GameOverView()
            } else {
                AssignmentsView()
            }
        }
    }
}

