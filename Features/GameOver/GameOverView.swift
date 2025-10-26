import SwiftUI
import UIKit

struct GameOverView: View {
    @EnvironmentObject private var store: GameStore
    @State private var includeNames = false
    @State private var showingShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                winnerBanner

                Toggle("Include names in log", isOn: $includeNames)
                    .toggleStyle(.switch)

                VStack(alignment: .leading) {
                    Text("Event Log").font(.headline)
                    Text(store.exportLogText(includeNames: includeNames))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .cardStyle()

                HStack(spacing: 12) {
                    ShareButton(text: store.exportLogText(includeNames: includeNames))
                        .buttonStyle(CTAButtonStyle(kind: .primary))
                    Button("Play Again") { store.resetAll() }
                        .buttonStyle(CTAButtonStyle(kind: .secondary))
                }
            }
            .padding()
        }
        .navigationTitle("Game Over")
    }

    private var winnerBanner: some View {
        let winnerText: String = store.state.winner == .mafia ? "Mafia" : "Citizens"
        return ZStack {
            // Celebratory gradient background
            LinearGradient(
                colors: [Design.Colors.brandGold.opacity(0.25), .clear, Design.Colors.brandGold.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .background(Design.Colors.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 10) {
                Text("GAME OVER")
                    .font(.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)

                // Citizens / Mafia Win title
                let title = (store.state.winner == .mafia) ? "MAFIA WIN!" : "CITIZENS WIN!"
                Text(title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Design.Colors.brandGold)
                    .kerning(1)

                HStack(spacing: 10) {
                    if store.state.winner == .mafia {
                        Chip(text: "MAFIA", style: .filled(Design.Colors.dangerRed))
                        Image(systemName: "flame.fill").foregroundStyle(Design.Colors.dangerRed)
                    } else {
                        Chip(text: "CITIZENS", style: .filled(Design.Colors.brandGold))
                        Image(systemName: "person.3.fill").foregroundStyle(Design.Colors.brandGold)
                    }
                }
            }
            .padding(20)

            // Simple confetti sparkle overlay
            ConfettiOverlay()
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Design.Colors.stroke, lineWidth: 1)
        )
    }
}

private struct ShareButton: View {
    let text: String
    @State private var present = false
    var body: some View {
        Button {
            present = true
        } label: {
            Label("Share Log", systemImage: "square.and.arrow.up")
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

// Simple celebratory sparkles using Canvas
private struct ConfettiOverlay: View {
    @State private var t: CGFloat = 0
    var body: some View {
        Canvas { ctx, size in
            let count = 22
            for i in 0..<count {
                var g = GraphicsContext.Shading.color(i % 2 == 0 ? Design.Colors.brandGold : .white)
                let x = CGFloat(i) / CGFloat(count) * size.width
                let y = (sin(t + CGFloat(i)) * 0.3 + 0.5) * size.height
                let rect = CGRect(x: x, y: y, width: 4, height: 10)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: g)
            }
        }
        .opacity(0.6)
        .onAppear { withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: true)) { t = .pi * 2 } }
    }
}
