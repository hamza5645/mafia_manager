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
                        Text("Mafia Manager")
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
        .onChange(of: authStore.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                dismiss()
            }
        }
    }
}

struct PasswordResetView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var showSuccess = false

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Reset Password")
                    .font(Design.Typography.title1)
                    .foregroundColor(Design.Colors.textPrimary)
                    .padding(.top, 40)
                    .accessibilityAddTraits(.isHeader)

                Text("Enter your email address and we'll send you a link to reset your password")
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

                if showSuccess {
                    Text("Check your email for a password reset link")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.successGreen)
                        .padding(.horizontal, 32)
                } else if let errorMessage = authStore.errorMessage {
                    Text(errorMessage)
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.dangerRed)
                        .padding(.horizontal, 32)
                        .accessibilityLabel("Error: \(errorMessage)")
                }

                Button {
                    Task {
                        showSuccess = false
                        let success = await authStore.resetPassword(email: sanitizedResetEmail)
                        if success {
                            showSuccess = true
                            // Auto-dismiss after showing success message
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                dismiss()
                            }
                        }
                    }
                } label: {
                    HStack {
                        if authStore.isLoading {
                            ProgressView()
                                .tint(Design.Colors.textPrimary)
                        } else {
                            Text("Send Reset Link")
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
    }

    private var sanitizedResetEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
