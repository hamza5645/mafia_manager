import SwiftUI

struct GameModeSelectionView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var selectedMode: GameMode?
    @State private var showingAuth = false
    @State private var showingSettings = false
    @State private var showingGuestNameInput = false

    enum GameMode: Hashable {
        case local
        case online
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Design.Colors.surface0.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Title
                        VStack(spacing: 10) {
                            Text("MAFIA MANAGER")
                                .font(Design.Typography.largeTitle)
                                .kerning(1.5)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Design.Colors.glowGold, radius: 10, y: 2)

                            Text("Choose your game mode")
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        .padding(.top, 40)

                        // Game Mode Cards
                        VStack(spacing: 20) {
                            // Local Game Card
                            GameModeCard(
                                title: "Local Game",
                                subtitle: "Pass & Play",
                                description: "Play on one device. Pass the phone around to reveal roles and take turns.",
                                icon: "iphone",
                                accentColor: Design.Colors.brandGold,
                                isSelected: selectedMode == .local
                            ) {
                                selectedMode = .local
                            }

                            // Online Multiplayer Card
                            GameModeCard(
                                title: "Online Game",
                                subtitle: "Multiplayer",
                                description: "Each player uses their own phone. Create or join a room to play together.",
                                icon: "person.3.fill",
                                accentColor: Design.Colors.brandGold,
                                isSelected: selectedMode == .online,
                                isLocked: false  // Guests can play too!
                            ) {
                                if authStore.isAuthenticated {
                                    selectedMode = .online
                                } else {
                                    // Show guest name input for unauthenticated users
                                    showingGuestNameInput = true
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Continue Button
                        if selectedMode != nil {
                            NavigationLink(value: selectedMode!) {
                                Text("Continue")
                                    .font(Design.Typography.body)
                                    .foregroundColor(Design.Colors.surface0)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        selectedMode == .local
                                            ? Design.Colors.brandGold
                                            : Design.Colors.brandGold
                                    )
                                    .cornerRadius(Design.Radii.medium)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        }

                        Spacer(minLength: 60)
                    }
                }
            }
            .navigationDestination(for: GameMode.self) { mode in
                switch mode {
                case .local:
                    SetupView()
                case .online:
                    MultiplayerMenuView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Design.Colors.brandGold)
                    }
                }
            }
            .sheet(isPresented: $showingAuth) {
                LoginView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingGuestNameInput) {
                GuestNameInputView(
                    onSuccess: {
                        showingGuestNameInput = false
                        selectedMode = .online
                    },
                    onCancel: {
                        showingGuestNameInput = false
                    }
                )
            }
        }
    }
}

// MARK: - Game Mode Card

struct GameModeCard: View {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let accentColor: Color
    let isSelected: Bool
    var isLocked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 56, height: 56)

                        Image(systemName: icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }

                    Spacer()

                    // Lock indicator
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    // Title and subtitle
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(Design.Typography.title2)
                            .foregroundStyle(Design.Colors.textPrimary)

                        Text(subtitle)
                            .font(Design.Typography.caption)
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accentColor.opacity(0.15))
                            .cornerRadius(Design.Radii.small)
                    }

                    Text(description)
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(20)
            .background(Design.Colors.surface1)
            .cornerRadius(Design.Radii.large)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.large)
                    .stroke(
                        isSelected ? accentColor : Design.Colors.stroke.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? accentColor.opacity(0.3) : .clear,
                radius: 12,
                y: 4
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    GameModeSelectionView()
        .environmentObject(GameStore())
        .environmentObject(AuthStore())
        .preferredColorScheme(.dark)
}
