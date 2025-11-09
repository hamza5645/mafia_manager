import SwiftUI

struct IntroView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Text("Welcome to Mafia Manager")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)
                Text("Set up your players, reveal roles, and manage day/night phases with ease.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onStart) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background((Color("ActionBlue", bundle: .main)).opacity(0.9))
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityIdentifier("intro_get_started")

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(Color.accentColor)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                        )
                }
                .accessibilityIdentifier("intro_skip")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Group {
                #if canImport(Design)
                Design.Colors.surface0
                #else
                Color.primary.opacity(0.05)
                #endif
            }
            .ignoresSafeArea()
        )
        .tint(Color.accentColor)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    IntroView(onStart: {}, onSkip: {})
}
