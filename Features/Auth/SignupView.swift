import Foundation
import SwiftUI

struct SignupView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var validationError: String?
    @State private var showingEmailConflict = false
    @State private var conflictAnonymousUserId: UUID?

    // Upgrade mode: When true, this is upgrading a guest account to permanent
    var isUpgrading: Bool = false

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Title - different for upgrade vs new signup
                    VStack(spacing: 8) {
                        Text(isUpgrading ? "Create Account" : "Create Account")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)

                        Text(isUpgrading ? "Keep your game progress" : "Join Mafia Manager")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 40)

                    // Stats preview when upgrading
                    if isUpgrading {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Design.Colors.successGreen)

                            Text("Your game stats will be saved to your new account")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Design.Colors.successGreen.opacity(0.15))
                        .cornerRadius(Design.Radii.small)
                        .padding(.horizontal, 32)
                    }

                    // Input Fields
                    VStack(spacing: 16) {
                        TextField("Display Name", text: Binding(
                            get: { displayName },
                            set: { displayName = String($0.prefix(50)) }
                        ))
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .padding()
                            .background(Design.Colors.surface1)
                            .foregroundColor(.white)
                            .cornerRadius(Design.Radii.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radii.card)
                                    .stroke(Design.Colors.stroke, lineWidth: 1)
                            )

                        TextField("Email", text: Binding(
                            get: { email },
                            set: { email = String($0.prefix(255)) }
                        ))
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                            .padding()
                            .background(Design.Colors.surface1)
                            .foregroundColor(.white)
                            .cornerRadius(Design.Radii.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radii.card)
                                    .stroke(Design.Colors.stroke, lineWidth: 1)
                            )

                        SecureField("Password", text: Binding(
                            get: { password },
                            set: { password = String($0.prefix(72)) }
                        ))
                            .textContentType(.newPassword)
                            .disableAutocorrection(true)
                            .padding()
                            .background(Design.Colors.surface1)
                            .foregroundColor(.white)
                            .cornerRadius(Design.Radii.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radii.card)
                                    .stroke(Design.Colors.stroke, lineWidth: 1)
                            )

                        SecureField("Confirm Password", text: Binding(
                            get: { confirmPassword },
                            set: { confirmPassword = String($0.prefix(72)) }
                        ))
                            .textContentType(.newPassword)
                            .disableAutocorrection(true)
                            .padding()
                            .background(Design.Colors.surface1)
                            .foregroundColor(.white)
                            .cornerRadius(Design.Radii.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radii.card)
                                    .stroke(Design.Colors.stroke, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 32)

                    // Validation Error
                    if let validationError = validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundColor(Design.Colors.dangerRed)
                            .padding(.horizontal, 32)
                    }

                    // Auth Error
                    if let errorMessage = authStore.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(Design.Colors.dangerRed)
                            .padding(.horizontal, 32)
                    }

                    // Sign Up Button
                    Button {
                        if validateForm() {
                            Task {
                                if isUpgrading {
                                    // Upgrade guest account to permanent
                                    let result = await authStore.linkEmailPassword(
                                        email: sanitizedEmail,
                                        password: sanitizedPassword,
                                        displayName: sanitizedDisplayName
                                    )

                                    switch result {
                                    case .success:
                                        await MainActor.run {
                                            dismiss()
                                        }
                                    case .emailAlreadyExists(let anonymousUserId):
                                        await MainActor.run {
                                            conflictAnonymousUserId = anonymousUserId
                                            showingEmailConflict = true
                                        }
                                    case .failure:
                                        // Error is displayed via authStore.errorMessage
                                        break
                                    }
                                } else {
                                    // Regular new signup
                                    let success = await authStore.signUp(
                                        email: sanitizedEmail,
                                        password: sanitizedPassword,
                                        displayName: sanitizedDisplayName
                                    )
                                    if success {
                                        await MainActor.run {
                                            dismiss()
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Create Account")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Design.Colors.actionBlue)
                        .foregroundColor(.white)
                        .cornerRadius(Design.Radii.button)
                        .shadow(color: Design.Colors.actionBlue.opacity(0.3), radius: 16, y: 8)
                    }
                    .disabled(authStore.isLoading || !isFormFilled)
                    .padding(.horizontal, 32)

                    // Password Requirements
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password must:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        HStack(spacing: 8) {
                            Image(systemName: sanitizedPassword.count >= 6 ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(sanitizedPassword.count >= 6 ? Design.Colors.successGreen : .white.opacity(0.3))
                            Text("Be at least 6 characters")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        HStack(spacing: 8) {
                            Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(passwordsMatch ? Design.Colors.successGreen : .white.opacity(0.3))
                            Text("Match confirmation")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)

                    Spacer()

                    // Back to Login (hide when upgrading since they're already "logged in" as guest)
                    if !isUpgrading {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Already have an account?")
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Sign In")
                                    .foregroundColor(Design.Colors.brandGold)
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                        }
                        .padding(.bottom, 32)
                    } else {
                        // For upgrade mode, show option to sign into existing account
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .onAppear {
            authStore.clearError()
            // Pre-fill display name from guest profile when upgrading
            if isUpgrading, let guestName = authStore.guestDisplayName, !guestName.isEmpty {
                displayName = guestName
            }
        }
        .alert("Email Already Registered", isPresented: $showingEmailConflict) {
            Button("Sign In & Merge Stats") {
                // User wants to sign into existing account and merge stats
                if let anonymousUserId = conflictAnonymousUserId {
                    Task {
                        let success = await authStore.mergeIntoExistingAccount(
                            anonymousUserId: anonymousUserId,
                            email: sanitizedEmail,
                            password: sanitizedPassword
                        )
                        if success {
                            await MainActor.run {
                                dismiss()
                            }
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This email is already associated with an account. Would you like to sign in and merge your guest stats?")
        }
    }

    private var isFormFilled: Bool {
        !sanitizedEmail.isEmpty && !sanitizedPassword.isEmpty && !sanitizedConfirmPassword.isEmpty && !sanitizedDisplayName.isEmpty
    }

    private func validateForm() -> Bool {
        validationError = nil

        guard sanitizedDisplayName.count >= 2 else {
            validationError = "Display name must be at least 2 characters"
            return false
        }

        guard sanitizedDisplayName.count <= 50 else {
            validationError = "Display name must be 50 characters or less"
            return false
        }

        guard isValidEmail(sanitizedEmail) else {
            validationError = "Please enter a valid email address"
            return false
        }

        guard sanitizedEmail.count <= 255 else {
            validationError = "Email must be 255 characters or less"
            return false
        }

        guard sanitizedPassword.count >= 6 else {
            validationError = "Password must be at least 6 characters"
            return false
        }

        guard sanitizedPassword.count <= 72 else {
            validationError = "Password must be 72 characters or less"
            return false
        }

        guard sanitizedPassword == sanitizedConfirmPassword else {
            validationError = "Passwords do not match"
            return false
        }

        return true
    }

    private var sanitizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var sanitizedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sanitizedConfirmPassword: String {
        confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sanitizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var passwordsMatch: Bool {
        !sanitizedPassword.isEmpty && sanitizedPassword == sanitizedConfirmPassword
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: email)
    }
}
