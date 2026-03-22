import SwiftUI

struct MultiplayerMenuView: View {
    @StateObject private var multiplayerStore = MultiplayerGameStore()
    @EnvironmentObject private var authStore: AuthStore
    @State private var showingCreateGame = false
    @State private var showingJoinGame = false
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 32) {
                // Title
                VStack(spacing: 10) {
                    Text("ONLINE MULTIPLAYER")
                        .font(Design.Typography.title1)
                        .kerning(1.2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.brandGold, Design.Colors.brandGold.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityAddTraits(.isHeader)

                    Text("Play with friends online")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.top, 60)

                Spacer()

                // Action Buttons
                VStack(spacing: 20) {
                    // Create Game Button
                    Button {
                        showingCreateGame = true
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: iconSize, weight: .semibold))
                                .foregroundStyle(Design.Colors.brandGold)

                            Text("Create Game")
                                .font(Design.Typography.title3)
                                .foregroundStyle(Design.Colors.textPrimary)

                            Text("Start a new room and invite friends")
                                .font(Design.Typography.footnote)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(Design.Colors.surface1)
                        .cornerRadius(Design.Radii.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radii.large)
                                .stroke(Design.Colors.brandGold.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .accessibilityLabel("Create online game")
                    .accessibilityHint("Start a new room and invite friends")
                    .automationID("multiplayer.menu.createGame")
                    .buttonStyle(PlainButtonStyle())

                    // Join Game Button
                    Button {
                        showingJoinGame = true
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: iconSize, weight: .semibold))
                                .foregroundStyle(Design.Colors.brandGold)

                            Text("Join Game")
                                .font(Design.Typography.title3)
                                .foregroundStyle(Design.Colors.textPrimary)

                            Text("Enter a room code to join")
                                .font(Design.Typography.footnote)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(Design.Colors.surface1)
                        .cornerRadius(Design.Radii.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radii.large)
                                .stroke(Design.Colors.brandGold.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .accessibilityLabel("Join online game")
                    .accessibilityHint("Enter a room code to join your friends")
                    .automationID("multiplayer.menu.joinGame")
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .fullScreenCover(isPresented: $showingCreateGame) {
            CreateGameView()
                .environmentObject(multiplayerStore)
                .environmentObject(authStore)
        }
        .fullScreenCover(isPresented: $showingJoinGame) {
            JoinGameView()
                .environmentObject(multiplayerStore)
                .environmentObject(authStore)
        }
        .onAppear {
            multiplayerStore.setAuthStore(authStore)
        }
    }
}

#Preview {
    MultiplayerMenuView()
        .environmentObject(AuthStore())
        .preferredColorScheme(.dark)
}
