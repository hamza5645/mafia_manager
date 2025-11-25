import SwiftUI

/// View for entering a display name when signing in as a guest
struct GuestNameInputView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var displayName = ""
    @State private var isSubmitting = false
    @FocusState private var isNameFieldFocused: Bool

    let onSuccess: () -> Void
    let onCancel: () -> Void

    private var isValidName: Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 50 && !InputValidator.isReservedBotName(trimmed)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0.ignoresSafeArea()

                VStack(spacing: 32) {
                    // Title and description
                    VStack(spacing: 12) {
                        Text("What should we call you?")
                            .font(Design.Typography.title2)
                            .foregroundStyle(Design.Colors.textPrimary)

                        Text("This is how you'll appear to other players in multiplayer games.")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // Name input field
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Enter your name", text: $displayName)
                            .textFieldStyle(.plain)
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Design.Colors.surface1)
                            .cornerRadius(Design.Radii.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radii.medium)
                                    .stroke(
                                        isNameFieldFocused ? Design.Colors.brandGold : Design.Colors.stroke.opacity(0.3),
                                        lineWidth: isNameFieldFocused ? 2 : 1
                                    )
                            )
                            .focused($isNameFieldFocused)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                if isValidName {
                                    Task { await submitGuestSignIn() }
                                }
                            }

                        // Validation hint
                        if !displayName.isEmpty && !isValidName {
                            Text(validationHint)
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.dangerRed)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Error message
                    if let error = authStore.errorMessage {
                        Text(error)
                            .font(Design.Typography.footnote)
                            .foregroundStyle(Design.Colors.dangerRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer()

                    // Start Playing button
                    Button {
                        Task { await submitGuestSignIn() }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Design.Colors.surface0))
                                    .scaleEffect(0.9)
                            } else {
                                Text("Start Playing")
                                    .font(Design.Typography.body)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(Design.Colors.surface0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isValidName ? Design.Colors.brandGold : Design.Colors.brandGold.opacity(0.4))
                        .cornerRadius(Design.Radii.medium)
                    }
                    .disabled(!isValidName || isSubmitting)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            .onAppear {
                isNameFieldFocused = true
            }
        }
    }

    private var validationHint: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            return "Name must be at least 2 characters"
        } else if trimmed.count > 50 {
            return "Name must be 50 characters or less"
        } else if InputValidator.isReservedBotName(trimmed) {
            return "This name is reserved. Please choose another."
        }
        return ""
    }

    private func submitGuestSignIn() async {
        guard isValidName else { return }

        isSubmitting = true
        authStore.clearError()

        let success = await authStore.signInAsGuest(displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines))

        isSubmitting = false

        if success {
            onSuccess()
        }
    }
}

#Preview {
    GuestNameInputView(
        onSuccess: {},
        onCancel: {}
    )
    .environmentObject(AuthStore())
    .preferredColorScheme(.dark)
}
