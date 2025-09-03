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

                HStack {
                    Button("New Game") { store.resetAll() }
                        .buttonStyle(.bordered)
                    Spacer()
                    ShareButton(text: store.exportLogText(includeNames: includeNames))
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
