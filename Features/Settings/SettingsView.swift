import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authStore: AuthStore
    @State private var showingLogin = false
    @State private var showingIntro = false
    @State private var showingUpgrade = false

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                List {
                    // Profile/Account Section
                    Section {
                        if authStore.isAuthenticated && !authStore.isAnonymous {
                            // Show profile for authenticated (non-guest) users
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
                        } else if authStore.isAnonymous {
                            // Show guest profile section with upgrade CTA
                            VStack(spacing: 16) {
                                HStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(Design.Colors.brandGold.opacity(0.2))
                                            .frame(width: 50, height: 50)

                                        Text(guestDisplayInitial)
                                            .font(.title3.bold())
                                            .foregroundColor(Design.Colors.brandGold)

                                        // Guest badge
                                        Circle()
                                            .fill(Design.Colors.surface0)
                                            .frame(width: 18, height: 18)
                                            .overlay(
                                                Image(systemName: "person.fill.questionmark")
                                                    .font(Design.Typography.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(Design.Colors.textSecondary)
                                            )
                                            .offset(x: 18, y: 18)
                                            .accessibilityLabel("Guest account")
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Guest Player")
                                            .font(.headline)
                                            .foregroundColor(.white)

                                        Text("Playing as: \(guestDisplayName)")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                .padding(.vertical, 8)

                                // Account action buttons
                                HStack(spacing: 12) {
                                    // Login button
                                    Button {
                                        showingLogin = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "person.circle")
                                                .font(Design.Typography.subheadline)
                                                .fontWeight(.semibold)
                                                .accessibilityHidden(true)

                                            Text("Login")
                                                .font(Design.Typography.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Design.Colors.surface2)
                                        .cornerRadius(Design.Radii.small)
                                    }

                                    // Create Account button
                                    Button {
                                        showingUpgrade = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "sparkles")
                                                .font(Design.Typography.subheadline)
                                                .fontWeight(.semibold)
                                                .accessibilityHidden(true)

                                            Text("Sign Up")
                                                .font(Design.Typography.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundColor(Design.Colors.surface0)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Design.Colors.brandGold)
                                        .cornerRadius(Design.Radii.small)
                                    }
                                }
                            }
                        } else {
                            // Show login button when not authenticated at all
                            Button {
                                showingLogin = true
                            } label: {
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Design.Colors.actionBlue.opacity(0.2))
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Image(systemName: "person.circle.fill")
                                                .font(.title2)
                                                .foregroundColor(Design.Colors.actionBlue)
                                        )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Login / Sign Up")
                                            .font(.headline)
                                            .foregroundColor(.white)

                                        Text("Save your stats and custom roles")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.3))
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .listRowBackground(Design.Colors.surface1)

                    // Stats Section (only show when authenticated)
                    if authStore.isAuthenticated {
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
                        }
                        .listRowBackground(Design.Colors.surface1)

                        Section("Customization") {
                            NavigationLink {
                                CustomRolesView()
                                    .environmentObject(authStore)
                            } label: {
                                SettingsRow(
                                    icon: "flame.fill",
                                    title: "Custom Roles",
                                    color: Design.Colors.dangerRed
                                )
                            }

                            NavigationLink {
                                PlayerGroupsView()
                                    .environmentObject(authStore)
                            } label: {
                                SettingsRow(
                                    icon: "person.3.fill",
                                    title: "Player Groups",
                                    color: Design.Colors.actionBlue
                                )
                            }
                        }
                        .listRowBackground(Design.Colors.surface1)
                    }

                    // Help & Tutorial Section
                    Section("Help & Tutorial") {
                        Button {
                            showingIntro = true
                        } label: {
                            SettingsRow(
                                icon: "graduationcap.fill",
                                title: "View Tutorial",
                                subtitle: "Learn how to play Mafia",
                                color: Design.Colors.brandGold
                            )
                        }
                    }
                    .listRowBackground(Design.Colors.surface1)

                    // About Section
                    Section("About") {
                        SettingsRow(
                            icon: "info.circle.fill",
                            title: "Version",
                            subtitle: "Version 5",
                            color: .gray
                        )
                    }
                    .listRowBackground(Design.Colors.surface1)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingLogin) {
                LoginView()
                    .environmentObject(authStore)
            }
            .fullScreenCover(isPresented: $showingIntro) {
                IntroView(
                    onStart: {
                        showingIntro = false
                    },
                    onSkip: {
                        showingIntro = false
                    }
                )
            }
            .sheet(isPresented: $showingUpgrade) {
                SignupView(isUpgrading: true)
                    .environmentObject(authStore)
            }
        }
    }

    // MARK: - Helper Properties

    private var guestDisplayName: String {
        authStore.guestDisplayName ?? authStore.userProfile?.displayName ?? "Guest"
    }

    private var guestDisplayInitial: String {
        String(guestDisplayName.prefix(1).uppercased())
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
                .font(Design.Typography.title3)
                .foregroundColor(color)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Typography.body)
                    .foregroundColor(.white)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Design.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle != nil ? "\(title), \(subtitle!)" : title)
    }
}
