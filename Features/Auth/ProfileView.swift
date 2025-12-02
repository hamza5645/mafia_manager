import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var isEditingName = false
    @State private var editedDisplayName = ""
    @State private var showLogoutConfirmation = false

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        // Avatar
                        Circle()
                            .fill(Design.Colors.brandGold.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text(authStore.userProfile?.displayName.prefix(1).uppercased() ?? "U")
                                    .font(Design.Typography.largeTitle)
                                    .foregroundColor(Design.Colors.brandGold)
                            )
                            .accessibilityLabel("Profile avatar")

                        // Display Name
                        if isEditingName {
                            HStack {
                                TextField("Display Name", text: $editedDisplayName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 200)

                                Button("Save") {
                                    Task {
                                        await authStore.updateProfile(displayName: editedDisplayName)
                                        isEditingName = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Cancel") {
                                    isEditingName = false
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            HStack {
                                Text(authStore.userProfile?.displayName ?? "User")
                                    .font(Design.Typography.title1)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Button {
                                    editedDisplayName = authStore.userProfile?.displayName ?? ""
                                    isEditingName = true
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .font(Design.Typography.title2)
                                        .foregroundColor(Design.Colors.brandGold)
                                }
                                .accessibilityLabel("Edit display name")
                            }
                        }
                    }
                    .padding(.top, 40)

                    // Account Info
                    VStack(spacing: 16) {
                        ProfileCard(
                            icon: "calendar",
                            title: "Member Since",
                            value: formatDate(authStore.userProfile?.createdAt)
                        )
                    }
                    .padding(.horizontal, 24)

                    // Sign Out Button
                    Button {
                        showLogoutConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(Design.Typography.body)
                                .accessibilityHidden(true)
                            Text("Sign Out")
                                .font(Design.Typography.body)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Design.Colors.dangerRed)
                        .foregroundColor(.white)
                        .cornerRadius(Design.Radii.card)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    Spacer()
                }
            }
        }
        .confirmationDialog("Sign Out", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await authStore.signOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .onChange(of: authStore.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                dismiss()
            }
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct ProfileCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(Design.Typography.title2)
                .foregroundColor(Design.Colors.brandGold)
                .frame(width: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Design.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))

                Text(value)
                    .font(Design.Typography.body)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding()
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.card)
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.card)
                .stroke(Design.Colors.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
