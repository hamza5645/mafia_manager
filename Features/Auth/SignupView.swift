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
    @State private var showSuccessAlert = false

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Title
                    VStack(spacing: 8) {
                        Text("Create Account")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)

                        Text("Join Mafia Manager")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 40)

                    // Input Fields
                    VStack(spacing: 16) {
                        TextField("Display Name", text: $displayName)
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

                        TextField("Email", text: $email)
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

                        SecureField("Password", text: $password)
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

                        SecureField("Confirm Password", text: $confirmPassword)
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
                                let success = await authStore.signUp(email: sanitizedEmail, password: sanitizedPassword, displayName: sanitizedDisplayName)
                                if success {
                                    // Signup successful
                                    if authStore.isAuthenticated {
                                        // Auto-confirmed, logged in immediately
                                        dismiss()
                                    } else {
                                        // Email confirmation required
                                        showSuccessAlert = true
                                    }
                                }
                                // If not success, error will be shown in errorMessage
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

                    // Back to Login
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
                }
            }
        }
        .onAppear {
            authStore.clearError()
        }
        .alert("Account Created!", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Please check your email to verify your account before signing in.")
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

        guard isValidEmail(sanitizedEmail) else {
            validationError = "Please enter a valid email address"
            return false
        }

        guard sanitizedPassword.count >= 6 else {
            validationError = "Password must be at least 6 characters"
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
