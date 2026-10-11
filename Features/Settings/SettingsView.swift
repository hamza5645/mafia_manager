import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authStore: AuthStore
    @State private var showingLogin = false
    @State private var showingIntro = false
    @State private var showingUpgrade = false
    @State private var showingClearGuestConfirmation = false
    @State private var guestMergeError: String?
    @State private var showingDiscardGuestConfirmation = false

    // Split into sections so no single expression is slow to type-check (PA-73).
    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                List {
                    // Profile/Account Section
                    Section {
                        if authStore.isAuthenticated && !authStore.isAnonymous {
                            accountRows
                        } else if authStore.isAnonymous {
                            guestRows
                        } else {
                            signedOutRow
                        }
                    }
                    .listRowBackground(Design.Colors.surface1)

                    // Stats Section (only show when authenticated)
                    if authStore.isAuthenticated {
                        librarySections
                    }

                    helpSection

                    aboutSection
                }
                .scrollContentBackground(.hidden)
                .readableContentWidth()
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
            .confirmationDialog(
                "Clear Guest Data",
                isPresented: $showingClearGuestConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Guest Data", role: .destructive) {
                    Task { await authStore.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This signs you out and removes your guest data from this device, so you can't get this guest's progress back. To keep your stats, sign up first.")
            }
            .confirmationDialog(
                "Discard Guest Progress",
                isPresented: $showingDiscardGuestConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Guest Progress", role: .destructive) {
                    authStore.discardPendingGuestProgress()
                    guestMergeError = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your account keeps its own stats. This guest's stats, custom roles and player groups won't be added to it, and this device forgets the guest, so you can't get them back.")
            }
        }
    }

    // MARK: - Sections

    // Show profile for authenticated (non-guest) users
    @ViewBuilder
    private var accountRows: some View {
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
                            .font(Design.Typography.title3)
                            .foregroundColor(Design.Colors.brandGold)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(authStore.userProfile?.displayName ?? "User")
                        .font(Design.Typography.headline)
                        .foregroundColor(Design.Colors.textPrimary)

                    Text("View Profile")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.textSecondary)
                }
            }
            .padding(.vertical, 8)
        }

        if authStore.hasPendingGuestMerge {
            pendingMergeRow
        }
    }

    private var pendingMergeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Guest progress hasn't been saved to your account yet.")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.textSecondary)
                Spacer()
                Button("Retry") {
                    Task { guestMergeError = await authStore.retryGuestMerge() }
                }
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.brandGold)
                .buttonStyle(.plain)
            }
            if let guestMergeError {
                Text(guestMergeError)
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.dangerRed)
            }
            // A seat in the same room under both identities blocks the merge
            // on every retry; let the player give up the guest's progress.
            if authStore.guestMergeHasSeatConflict {
                Button("Discard Guest Progress", role: .destructive) {
                    showingDiscardGuestConfirmation = true
                }
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.dangerRed)
                .buttonStyle(.plain)
            }
        }
    }

    // Show guest profile section with upgrade CTA
    private var guestRows: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Design.Colors.brandGold.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Text(guestDisplayInitial)
                        .font(Design.Typography.title3)
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
                        .font(Design.Typography.headline)
                        .foregroundColor(Design.Colors.textPrimary)

                    Text("Playing as: \(guestDisplayName)")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.textSecondary)
                }
            }
            .padding(.vertical, 8)

            guestAccountButtons

            // Clear Guest Data button
            Button {
                showingClearGuestConfirmation = true
            } label: {
                Text("Clear Guest Data")
                    .font(Design.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Design.Colors.dangerRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .accessibilityHint("Sign out of your guest session and remove guest data from this device")
        }
    }

    // Account action buttons
    private var guestAccountButtons: some View {
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
                .foregroundColor(Design.Colors.textPrimary)
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
        .buttonStyle(.plain)
    }

    // Show login button when not authenticated at all
    private var signedOutRow: some View {
        Button {
            showingLogin = true
        } label: {
            HStack(spacing: 16) {
                Circle()
                    .fill(Design.Colors.actionBlue.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.circle.fill")
                            .font(Design.Typography.title2)
                            .foregroundColor(Design.Colors.actionBlue)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Login / Sign Up")
                        .font(Design.Typography.headline)
                        .foregroundColor(Design.Colors.textPrimary)

                    Text("Save your stats and custom roles")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.textTertiary)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var librarySections: some View {
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
    private var helpSection: some View {
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
    }

    // About Section
    private var aboutSection: some View {
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
                    .foregroundColor(Design.Colors.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle != nil ? "\(title), \(subtitle!)" : title)
    }
}
