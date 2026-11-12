import SwiftUI

/// A host phase request (Reveal Deaths, Start Voting, Continue to Night) with in-flight and
/// error state. Repeated taps are safe: the server ignores a transition that already happened.
struct HostTransitionButton: View {
    let title: String
    let action: () async throws -> Void

    @State private var isTransitioning = false
    @State private var transitionError: String?

    var body: some View {
        VStack(spacing: 12) {
            Button {
                Task { await run() }
            } label: {
                HStack {
                    if isTransitioning {
                        ProgressView()
                            .tint(Design.Colors.surface0)
                    } else {
                        Text(title)
                            .font(Design.Typography.body)
                            .fontWeight(.bold)
                    }
                }
                .foregroundStyle(Design.Colors.surface0)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Design.Colors.brandGold.opacity(isTransitioning ? Design.Opacity.strong : 1))
                .cornerRadius(Design.Radii.medium)
            }
            .disabled(isTransitioning)
            .accessibilityLabel(title)

            if let transitionError {
                Text(transitionError)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.dangerRed)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func run() async {
        guard !isTransitioning else { return }
        isTransitioning = true
        transitionError = nil
        do {
            try await action()
        } catch {
            transitionError = HostTransition.errorMessage(for: error)
        }
        isTransitioning = false
    }
}

enum HostTransition {
    /// Server answers that mean the request is no longer needed: the phase already moved on,
    /// the game ended, or another device is the host now. The subscriptions re-route the screen.
    static let silentMessages: Set<String> = [
        "The game has moved on.",
        "This game is no longer active.",
        "Only the host can do that.",
    ]

    /// The message to show under a host button, or nil when the error counts as success.
    static func errorMessage(for error: Error) -> String? {
        if let error = error as? SessionError {
            switch error {
            case .notHost, .noActiveSession: return nil
            case .invalidPhase: break
            }
        }
        if let error = error as? BackendError {
            if error.isServerMessage, silentMessages.contains(error.message) { return nil }
            // A timed-out request may still be applied, so it is not reported as a failure.
            if error.isTimeout { return error.message }
        }
        return "Failed to continue: \(error.localizedDescription)"
    }
}
