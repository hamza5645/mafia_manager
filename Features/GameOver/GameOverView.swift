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

                GroupBox("Event Log") {
                    Text(store.exportLogText(includeNames: includeNames))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button("New Game") { store.resetAll() }
                        .buttonStyle(GlassButtonStyle())
                    Spacer()
                    ShareButton(text: store.exportLogText(includeNames: includeNames))
                        .buttonStyle(GlassButtonStyle())
                }
            }
            .padding()
        }
        .navigationTitle("Game Over")
    }

    private var winnerBanner: some View {
        let winnerText: String = {
            if store.state.winner == .mafia { return "Mafia" }
            else { return "Villagers" }
        }()
        return HStack {
            Image(systemName: store.state.winner == .mafia ? "flame.fill" : "sun.max.fill")
                .foregroundStyle(store.state.winner == .mafia ? .red : .yellow)
            Text("Winner: \(winnerText)")
                .font(.largeTitle).bold()
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
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

// MARK: - Local glass style
private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6)
                    .blendMode(.plusLighter)
                    .opacity(configuration.isPressed ? 0.35 : 1)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.12 : 0.2), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}
