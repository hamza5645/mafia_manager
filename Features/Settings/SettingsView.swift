import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authStore: AuthStore

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                List {
                    // Profile Section
                    Section {
                        NavigationLink {
                            ProfileView()
                                .environmentObject(authStore)
                        } label: {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Design.Colors.brandGold.opacity(0.2))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Text(authStore.userProfile?.displayName.prefix(1).uppercased() ?? "U")
                                            .font(.title3.bold())
                                            .foregroundColor(Design.Colors.brandGold)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(authStore.userProfile?.displayName ?? "User")
                                        .font(.headline)
                                        .foregroundColor(.white)

                                    Text("View Profile")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .listRowBackground(Design.Colors.surface1)

                    // Stats Section
                    Section("Statistics") {
                        NavigationLink {
                            PlayerStatsView()
                                .environmentObject(authStore)
                        } label: {
                            SettingsRow(
                                icon: "chart.bar.fill",
                                title: "Player Stats",
                                color: Design.Colors.successGreen
                            )
                        }

                        NavigationLink {
                            CustomRolesView()
                                .environmentObject(authStore)
                        } label: {
                            SettingsRow(
                                icon: "person.3.fill",
                                title: "Custom Roles",
                                color: Design.Colors.actionBlue
                            )
                        }
                    }
                    .listRowBackground(Design.Colors.surface1)

                    // About Section
                    Section("About") {
                        SettingsRow(
                            icon: "info.circle.fill",
                            title: "Version",
                            subtitle: "1.0.0",
                            color: .gray
                        )
                    }
                    .listRowBackground(Design.Colors.surface1)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(.white)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
