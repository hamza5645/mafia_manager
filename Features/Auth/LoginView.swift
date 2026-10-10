import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var showSignup = false
    @State private var showPasswordReset = false

    var body: some View {
        ZStack {
            // Background
            Design.Colors.surface0
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Title
                    VStack(spacing: 8) {
                        Text("Mafia")
                            .font(Design.Typography.largeTitle)
                            .foregroundColor(Design.Colors.brandGold)
                            .accessibilityAddTraits(.isHeader)

                        Text("Sign in to continue")
                            .font(Design.Typography.subheadline)
                            .foregroundColor(Design.Colors.textSecondary)
                    }
                    .padding(.top, 60)

                    // Input Fields
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                            .padding()
                            .background(Design.Colors.surface1)
                            .foregroundColor(Design.Colors.textPrimary)
                            .cornerRadius(Design.Radii.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radii.card)
                                    .stroke(Design.Colors.stroke, lineWidth: 1)
                            )

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .disableAutocorrection(true)
                            .padding()
                            .background(Design.Colors.surface1)
                            .foregroundColor(Design.Colors.textPrimary)
                            .cornerRadius(Design.Radii.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radii.card)
                                    .stroke(Design.Colors.stroke, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 32)

                    // Error Message
                    if let errorMessage = authStore.errorMessage {
                        Text(errorMessage)
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.dangerRed)
                            .padding(.horizontal, 32)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }

                    // Sign In Button
                    Button {
                        Task {
                            await authStore.signIn(email: sanitizedEmail, password: sanitizedPassword)
                        }
                    } label: {
                        HStack {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(Design.Colors.textPrimary)
                            } else {
                                Text("Sign In")
                                    .font(Design.Typography.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Design.Colors.actionBlue)
                        .foregroundColor(Design.Colors.textPrimary)
                        .cornerRadius(Design.Radii.card)
                        .shadow(color: Design.Colors.glowBlue, radius: Design.Shadows.large.radius, y: Design.Shadows.large.y)
                    }
                    .disabled(authStore.isLoading || sanitizedEmail.isEmpty || sanitizedPassword.isEmpty)
                    .padding(.horizontal, 32)

                    // Forgot Password
                    Button {
                        showPasswordReset = true
                    } label: {
                        Text("Forgot Password?")
                            .font(Design.Typography.subheadline)
                            .foregroundColor(Design.Colors.brandGold)
                    }
                    .accessibilityLabel("Forgot password")

                    Spacer()

                    Text("Played before the update? Sign up with the same email to restore your stats.")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Sign Up Link
                    Button {
                        showSignup = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .foregroundColor(Design.Colors.textSecondary)
                            Text("Sign Up")
                                .foregroundColor(Design.Colors.brandGold)
                                .fontWeight(.semibold)
                        }
                        .font(Design.Typography.subheadline)
                    }
                    .accessibilityLabel("Create account")
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showSignup) {
            SignupView()
                .environmentObject(authStore)
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView()
                .environmentObject(authStore)
        }
        .onAppear {
            authStore.clearError()
        }
        .onChange(of: authStore.authenticatedAccountId) { _, accountId in
            if accountId != nil {
                dismiss()
            }
        }
    }
}

struct PasswordResetView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var showCompletionStep = false

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Reset Password")
                        .font(Design.Typography.title1)
                        .foregroundColor(Design.Colors.textPrimary)
                        .padding(.top, 40)
                        .accessibilityAddTraits(.isHeader)

                    Text("Enter your email address and we'll send you a code to reset your password")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(Design.Colors.surface1)
                        .foregroundColor(Design.Colors.textPrimary)
                        .cornerRadius(Design.Radii.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radii.card)
                                .stroke(Design.Colors.stroke, lineWidth: 1)
                        )
                        .padding(.horizontal, 32)

                    if let errorMessage = authStore.errorMessage {
                        Text(errorMessage)
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.dangerRed)
                            .padding(.horizontal, 32)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }

                    Button {
                        Task {
                            let success = await authStore.startPasswordReset(email: sanitizedResetEmail)
                            if success {
                                await MainActor.run {
                                    showCompletionStep = true
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(Design.Colors.textPrimary)
                            } else {
                                Text("Send Reset Code")
                                    .font(Design.Typography.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Design.Colors.actionBlue)
                        .foregroundColor(Design.Colors.textPrimary)
                        .cornerRadius(Design.Radii.card)
                    }
                    .disabled(authStore.isLoading || sanitizedResetEmail.isEmpty)
                    .padding(.horizontal, 32)

                    Spacer()
                }
            }
            .navigationDestination(isPresented: $showCompletionStep) {
                PasswordResetCompleteView()
                    .environmentObject(authStore)
            }
        }
        .onAppear {
            authStore.clearError()
        }
        .onChange(of: authStore.authenticatedAccountId) { _, accountId in
            if accountId != nil {
                dismiss()
            }
        }
    }

    private var sanitizedResetEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct PasswordResetCompleteView: View {
    @EnvironmentObject var authStore: AuthStore
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var validationError: String?
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Text("Set new password")
                        .font(Design.Typography.title1)
                        .foregroundColor(Design.Colors.textPrimary)
                        .padding(.top, 24)
                        .accessibilityAddTraits(.isHeader)

                    Text("Enter the 6-digit code we sent to your email and choose a new password.")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    VStack(spacing: 16) {
                        TextField("Verification code", text: Binding(
                            get: { code },
                            set: { code = String($0.filter(\.isNumber).prefix(6)) }
                        ))
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Design.Colors.surface1)
                        .foregroundColor(Design.Colors.textPrimary)
                        .cornerRadius(Design.Radii.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radii.card)
                                .stroke(Design.Colors.stroke, lineWidth: 1)
                        )
                        .focused($codeFieldFocused)

                        SecureField("New password", text: Binding(
                            get: { newPassword },
                            set: { newPassword = String($0.prefix(72)) }
                        ))
                        .textContentType(.newPassword)
                        .padding()
                        .background(Design.Colors.surface1)
                        .foregroundColor(Design.Colors.textPrimary)
                        .cornerRadius(Design.Radii.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radii.card)
                                .stroke(Design.Colors.stroke, lineWidth: 1)
                        )

                        SecureField("Confirm new password", text: Binding(
                            get: { confirmPassword },
                            set: { confirmPassword = String($0.prefix(72)) }
                        ))
                        .textContentType(.newPassword)
                        .padding()
                        .background(Design.Colors.surface1)
                        .foregroundColor(Design.Colors.textPrimary)
                        .cornerRadius(Design.Radii.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radii.card)
                                .stroke(Design.Colors.stroke, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 32)

                    if let validationError {
                        Text(validationError)
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.dangerRed)
                            .padding(.horizontal, 32)
                    } else if let errorMessage = authStore.errorMessage {
                        Text(errorMessage)
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.dangerRed)
                            .padding(.horizontal, 32)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }

                    Button {
                        guard validate() else { return }
                        Task {
                            await authStore.confirmPasswordReset(code: code, newPassword: trimmedNewPassword)
                            // On success, the parent reset stack auto-dismisses when account identity becomes available.
                        }
                    } label: {
                        HStack {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(Design.Colors.textPrimary)
                            } else {
                                Text("Set New Password")
                                    .font(Design.Typography.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Design.Colors.actionBlue)
                        .foregroundColor(Design.Colors.textPrimary)
                        .cornerRadius(Design.Radii.card)
                    }
                    .disabled(authStore.isLoading || !isFormFilled)
                    .padding(.horizontal, 32)

                    Spacer()
                }
            }
        }
        .onAppear {
            authStore.clearError()
            codeFieldFocused = true
        }
    }

    private var isFormFilled: Bool {
        code.count == 6 && trimmedNewPassword.count >= AuthStore.minimumPasswordLength && passwordsMatch
    }

    private var trimmedNewPassword: String {
        newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var passwordsMatch: Bool {
        trimmedNewPassword == confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate() -> Bool {
        validationError = nil
        guard code.count == 6 else {
            validationError = "Enter the 6-digit code"
            return false
        }
        guard trimmedNewPassword.count >= AuthStore.minimumPasswordLength else {
            validationError = "Password must be at least \(AuthStore.minimumPasswordLength) characters"
            return false
        }
        guard passwordsMatch else {
            validationError = "Passwords do not match"
            return false
        }
        return true
    }
}

extension LoginView {
    private var sanitizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var sanitizedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
