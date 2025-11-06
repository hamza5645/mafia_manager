import SwiftUI
import UIKit

struct GameOverView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var hasSynced = false

    var body: some View {
        let logText = store.exportLogText(includeNames: true)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                winnerBanner

                VStack(alignment: .leading, spacing: 12) {
                    Text("Event Log")
                        .font(Design.Typography.title3)
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text(logText)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .cardStyle(padding: 18)

                buttonRow(logText: logText)

                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .navigationTitle("Game Over")
        .task {
            // Sync stats to cloud when game is over (only once)
            if !hasSynced {
                await store.syncPlayerStatsToCloud()
                hasSynced = true
            }
        }
    }

    private var winnerBanner: some View {
        let isMafiaWin = store.state.winner == .mafia
        let winColor = isMafiaWin ? Design.Colors.dangerRed : Design.Colors.brandGold
        let glowColor = isMafiaWin ? Design.Colors.glowRed : Design.Colors.glowGold

        return ZStack {
            // Enhanced gradient background with glassmorphism
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(Design.Colors.surface1)

                // Animated gradient overlay
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                winColor.opacity(0.3),
                                winColor.opacity(0.15),
                                .clear,
                                winColor.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Shimmer effect
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.1), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            }

            VStack(spacing: 14) {
                Text("GAME OVER")
                    .font(Design.Typography.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Design.Colors.textTertiary)
                    .tracking(2)

                // Enhanced win title with gradient
                let title = isMafiaWin ? "MAFIA WIN!" : "CITIZENS WIN!"
                Text(title)
                    .font(Design.Typography.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundStyle(
                        LinearGradient(
                            colors: isMafiaWin ?
                                [Design.Colors.dangerRed, Design.Colors.dangerRedBright] :
                                [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: glowColor, radius: 16, y: 0)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .tracking(2)

                // Enhanced winner chip
                HStack(spacing: 10) {
                    if isMafiaWin {
                        Chip(text: "MAFIA", style: .filled(Design.Colors.dangerRed), icon: "flame.fill")
                    } else {
                        Chip(text: "CITIZENS", style: .filled(Design.Colors.successGreen), icon: "checkmark.seal.fill")
                    }
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)

            // Enhanced confetti overlay
            ConfettiOverlay(winColor: winColor)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            winColor.opacity(0.7),
                            winColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .shadow(color: glowColor.opacity(0.4), radius: 20, y: 4)
        .shadow(color: Design.Shadows.large.color, radius: Design.Shadows.large.radius, x: Design.Shadows.large.x, y: Design.Shadows.large.y)
    }

    private func buttonRow(logText: String) -> some View {
        let mafiaWon = store.state.winner == .mafia
        return VStack(spacing: Design.Spacing.md) {
            Button {
                store.resetAll()
                DispatchQueue.main.async {
                    dismiss()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: mafiaWon ? "flame.fill" : "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Play Again")
                        .font(Design.Typography.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: mafiaWon ? .danger : .primary))

            ShareButton(text: logText)
                .buttonStyle(CTAButtonStyle(kind: .secondary))
        }
    }
}

private struct ShareButton: View {
    let text: String
    @State private var present = false

    var body: some View {
        Button {
            present = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                Text("Share Event Log")
                    .font(Design.Typography.headline)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $present) {
            ActivityView(activityItems: [text])
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Enhanced celebratory confetti using Canvas
private struct ConfettiOverlay: View {
    let winColor: Color
    @State private var t: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let count = 40
            let colors: [Color] = [
                winColor,
                Design.Colors.brandGold,
                Design.Colors.brandGoldBright,
                .white,
                Design.Colors.actionBlue
            ]

            for i in 0..<count {
                let colorIndex = i % colors.count
                let shading = GraphicsContext.Shading.color(colors[colorIndex])

                // Create varied horizontal positions
                let xBase = (CGFloat(i) / CGFloat(count)) * size.width
                let xOffset = sin(t * 1.5 + CGFloat(i) * 0.5) * 30

                // Create wave motion with varied amplitudes
                let amplitude = (CGFloat(i % 3) + 1) * 0.15
                let yBase = (sin(t + CGFloat(i) * 0.4) * amplitude + 0.5) * size.height
                let yOffset = cos(t * 0.8 + CGFloat(i) * 0.3) * 20

                let x = xBase + xOffset
                let y = yBase + yOffset

                // Varied sizes
                let width = CGFloat([3, 4, 5, 6][i % 4])
                let height = CGFloat([8, 10, 12, 14][i % 4])

                let rect = CGRect(
                    x: x - width / 2,
                    y: y - height / 2,
                    width: width,
                    height: height
                )

                // Draw rotated confetti pieces
                var rotatedCtx = ctx
                rotatedCtx.translateBy(x: x, y: y)
                rotatedCtx.rotate(by: Angle(degrees: Double(t * 50 + CGFloat(i) * 20)))
                rotatedCtx.translateBy(x: -x, y: -y)

                rotatedCtx.fill(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: shading
                )
            }
        }
        .opacity(0.7)
        .onAppear {
            withAnimation(
                .linear(duration: 3.5)
                    .repeatForever(autoreverses: false)
            ) {
                t = .pi * 2
            }
        }
    }
}
