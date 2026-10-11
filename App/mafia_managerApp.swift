import SwiftUI

// MARK: - App Lifecycle Notification Names

extension Notification.Name {
    /// Posted when the app becomes active after a real trip to the background
    static let appDidBecomeActive = Notification.Name("appDidBecomeActive")

    /// Posted when the app enters the background (not for `.inactive` overlays)
    static let appWillEnterBackground = Notification.Name("appWillEnterBackground")
}

/// Unit tests get a bare host app: no Clerk, Convex, session restore or
/// solo save file. Keyed only on the variable XCTest sets, never on a build flag.
@main
enum AppLauncher {
    static func main() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            TestHostApp.main()
        } else {
            mafia_managerApp.main()
        }
    }
}

struct TestHostApp: App {
    var body: some Scene {
        WindowGroup { Color.clear }
    }
}

struct mafia_managerApp: App {
    @StateObject private var gameStore = GameStore()
    @StateObject private var authStore = AuthStore()
    @Environment(\.scenePhase) private var scenePhase
    /// `.active` always follows `.inactive`, so only this tells a real return
    /// from the background from a Control Center or app-switcher glance.
    @State private var wasBackgrounded = false

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
                .task(priority: .utility) {
                    await BackendCompatibility.shared.checkOnce()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .inactive:
                        // A kill from the app switcher may never deliver .background.
                        try? Persistence.shared.saveImmediately(gameStore.state)
                    case .background:
                        try? Persistence.shared.saveImmediately(gameStore.state)
                        // Reset audio session flag so it re-activates on return
                        SoundManager.shared.handleBackgrounding()
                        wasBackgrounded = true
                        // Notify multiplayer services to pause (save battery)
                        NotificationCenter.default.post(name: .appWillEnterBackground, object: nil)
                    case .active:
                        guard wasBackgrounded else { break }
                        wasBackgrounded = false
                        // Notify multiplayer services to reconnect
                        NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
                        // No-op once a launch check succeeded; retries one that failed offline.
                        Task { await BackendCompatibility.shared.checkOnce() }
                    @unknown default:
                        break
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var gameStore: GameStore
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false
    /// The persistence error the player already dismissed, so it shows once.
    @State private var dismissedPersistenceError: String?

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
        .alert("Saved Game", isPresented: persistenceAlertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(gameStore.persistenceError ?? "")
        }
    }

    private var persistenceAlertIsPresented: Binding<Bool> {
        Binding(
            get: { gameStore.persistenceError.map { $0 != dismissedPersistenceError } ?? false },
            set: { if !$0 { dismissedPersistenceError = gameStore.persistenceError } }
        )
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
