import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authStore: AuthStore
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
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(Design.Colors.brandGold)

                        Text("Sign in to continue")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 60)

                    // Input Fields
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
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
                            .textContentType(.password)
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

                    // Error Message
                    if let errorMessage = authStore.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(Design.Colors.dangerRed)
                            .padding(.horizontal, 32)
                    }

                    // Sign In Button
                    Button {
                        Task {
                            await authStore.signIn(email: email, password: password)
                        }
                    } label: {
                        HStack {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Design.Colors.actionBlue)
                        .foregroundColor(.white)
                        .cornerRadius(Design.Radii.card)
                        .shadow(color: Design.Colors.actionBlue.opacity(0.3), radius: 16, y: 8)
                    }
                    .disabled(authStore.isLoading || email.isEmpty || password.isEmpty)
                    .padding(.horizontal, 32)

                    // Forgot Password
                    Button {
                        showPasswordReset = true
                    } label: {
                        Text("Forgot Password?")
                            .font(.subheadline)
                            .foregroundColor(Design.Colors.brandGold)
                    }

                    Spacer()

                    // Sign Up Link
                    Button {
                        showSignup = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .foregroundColor(.white.opacity(0.7))
                            Text("Sign Up")
                                .foregroundColor(Design.Colors.brandGold)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                    }
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
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .padding(.top, 40)

                Text("Enter your email address and we'll send you a link to reset your password")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(Design.Colors.surface1)
                    .foregroundColor(.white)
                    .cornerRadius(Design.Radii.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radii.card)
                            .stroke(Design.Colors.stroke, lineWidth: 1)
                    )
                    .padding(.horizontal, 32)

                if showSuccess {
                    Text("Check your email for a password reset link")
                        .font(.caption)
                        .foregroundColor(Design.Colors.successGreen)
                        .padding(.horizontal, 32)
                }

                Button {
                    Task {
                        await authStore.resetPassword(email: email)
                        showSuccess = true
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        dismiss()
                    }
                } label: {
                    HStack {
                        if authStore.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Send Reset Link")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Design.Colors.actionBlue)
                    .foregroundColor(.white)
                    .cornerRadius(Design.Radii.card)
                }
                .disabled(authStore.isLoading || email.isEmpty)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}
