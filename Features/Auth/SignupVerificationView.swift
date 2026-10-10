import SwiftUI

struct SignupVerificationView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var code = ""
    @State private var resendInfoMessage: String?
    @FocusState private var codeFieldFocused: Bool

    private var shouldRetryMerge: Bool {
        authStore.hasPendingGuestMerge && !authStore.isAnonymous
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Text(shouldRetryMerge ? "Save your progress" : "Verify your email")
                        .font(Design.Typography.title1)
                        .foregroundColor(Design.Colors.textPrimary)
                        .padding(.top, 40)
                        .accessibilityAddTraits(.isHeader)

                    Text(shouldRetryMerge
                         ? "Your account is verified. Retry saving your guest progress to finish the upgrade."
                         : "Enter the 6-digit code we sent to your email to finish creating your account.")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    if !shouldRetryMerge {
                        TextField("123456", text: Binding(
                            get: { code },
                            set: { code = String($0.filter(\.isNumber).prefix(6)) }
                        ))
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .font(Design.Typography.title2)
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
                        .padding(.horizontal, 32)
                    }

                    if let resendInfoMessage {
                        Text(resendInfoMessage)
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
                            resendInfoMessage = nil
                            let success: Bool
                            if shouldRetryMerge {
                                success = await authStore.retryPendingGuestMerge()
                            } else {
                                switch await authStore.verifySignUpEmailCode(code) {
                                case .success:
                                    success = true
                                case .verificationFailed, .retryableMergeFailure:
                                    success = false
                                }
                            }
                            if success {
                                await MainActor.run { dismiss() }
                            }
                        }
                    } label: {
                        HStack {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(Design.Colors.textPrimary)
                            } else {
                                Text(shouldRetryMerge ? "Retry saving progress" : "Verify")
                                    .font(Design.Typography.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Design.Colors.actionBlue)
                        .foregroundColor(Design.Colors.textPrimary)
                        .cornerRadius(Design.Radii.card)
                    }
                    .disabled(authStore.isLoading || (!shouldRetryMerge && code.count != 6))
                    .padding(.horizontal, 32)

                    if !shouldRetryMerge {
                        Button {
                            Task {
                                authStore.clearError()
                                let sent = await authStore.resendSignUpEmailCode()
                                if sent {
                                    resendInfoMessage = "A new code has been sent."
                                }
                            }
                        } label: {
                            Text("Resend code")
                                .font(Design.Typography.subheadline)
                                .foregroundColor(Design.Colors.brandGold)
                        }
                        .disabled(authStore.isLoading)
                    }

                    Spacer()

                    Button {
                        authStore.cancelPendingSignUp()
                        dismiss()
                    } label: {
                        Text(shouldRetryMerge ? "Finish later" : "Cancel")
                            .font(Design.Typography.subheadline)
                            .foregroundColor(Design.Colors.textSecondary)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            authStore.clearError()
            codeFieldFocused = !shouldRetryMerge
        }
    }
}
