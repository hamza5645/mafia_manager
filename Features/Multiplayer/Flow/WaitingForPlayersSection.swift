import SwiftUI

/// Host only: who the current phase still waits for (role reveal, night, voting). Opens a list
/// with an offline badge and a Remove action, so one dropped phone cannot stall the table.
struct WaitingForPlayersSection: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @State private var showingList = false

    var body: some View {
        let waiting = multiplayerStore.isHost ? multiplayerStore.waitingForPlayers : []
        VStack(spacing: 0) {
            if !waiting.isEmpty {
                summaryButton(waiting)
            }
        }
        .sheet(isPresented: $showingList) {
            WaitingForPlayersList()
                .environmentObject(multiplayerStore)
                .presentationDetents([.medium, .large])
        }
    }

    private func summaryButton(_ waiting: [SessionPlayer]) -> some View {
        let offlineCount = waiting.filter { !$0.isOnline }.count
        return Button {
            showingList = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .foregroundStyle(Design.Colors.brandGold)
                    .accessibilityHidden(true)

                Text(Self.summary(waiting))
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if offlineCount > 0 {
                    Label("\(offlineCount) offline", systemImage: "wifi.slash")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.dangerRed)
                }

                Image(systemName: "chevron.right")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Design.Colors.surface1)
            .cornerRadius(Design.Radii.medium)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .accessibilityHint("Shows who the game is waiting for and lets you remove a player")
        .automationID("multiplayer.waitingFor.open")
    }

    /// "Waiting for Alice, Bob and 2 more"
    static func summary(_ waiting: [SessionPlayer]) -> String {
        let names = waiting.map { $0.isMe ? "you" : $0.playerName }
        let shown = names.prefix(2).joined(separator: ", ")
        let rest = names.count - min(names.count, 2)
        return rest > 0 ? "Waiting for \(shown) and \(rest) more" : "Waiting for \(shown)"
    }
}

/// The sheet behind `WaitingForPlayersSection`.
private struct WaitingForPlayersList: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @Environment(\.dismiss) private var dismiss

    @State private var playerToRemove: SessionPlayer?
    @State private var removingId: UUID?
    @State private var removeError: String?

    var body: some View {
        let waiting = multiplayerStore.isHost ? multiplayerStore.waitingForPlayers : []
        NavigationStack {
            List {
                Section {
                    if waiting.isEmpty {
                        Text("Everyone is in.")
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                    ForEach(waiting) { player in
                        row(player)
                    }
                } footer: {
                    if let removeError {
                        Text(removeError)
                            .foregroundStyle(Design.Colors.dangerRed)
                    } else if let code = multiplayerStore.currentSession?.roomCode {
                        Text("A player whose app closed can rejoin with room code \(code). Remove only players who have left.")
                    }
                }
                .listRowBackground(Design.Colors.surface1)
            }
            .scrollContentBackground(.hidden)
            .background(Design.Colors.surface0)
            .navigationTitle("Waiting For")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Remove \(playerToRemove?.playerName ?? "player")?",
                isPresented: Binding(
                    get: { playerToRemove != nil },
                    set: { if !$0 { playerToRemove = nil } }
                ),
                presenting: playerToRemove
            ) { player in
                Button("Remove", role: .destructive) { remove(player) }
                Button("Cancel", role: .cancel) { }
            } message: { player in
                Text("\(player.playerName) will be removed from this game so the round can continue. They can join again after this game ends.")
            }
        }
    }

    private func row(_ player: SessionPlayer) -> some View {
        HStack(spacing: 10) {
            Text(player.isMe ? "\(player.playerName) (You)" : player.playerName)
                .font(Design.Typography.body)
                .lineLimit(1)

            if !player.isOnline {
                Label("Offline", systemImage: "wifi.slash")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.dangerRed)
            }

            Spacer(minLength: 8)

            if !player.isMe {
                if removingId == player.id {
                    ProgressView()
                } else {
                    Button("Remove", role: .destructive) {
                        playerToRemove = player
                    }
                    .font(Design.Typography.callout)
                    .buttonStyle(.borderless)
                    .disabled(removingId != nil)
                    .accessibilityLabel("Remove \(player.playerName)")
                }
            }
        }
    }

    private func remove(_ player: SessionPlayer) {
        removingId = player.id
        removeError = nil
        Task {
            do {
                try await multiplayerStore.removePlayer(withId: player.id)
            } catch let error as BackendError where error.isTimeout {
                // It may still go through, so it is not called a failure.
                removeError = error.message
            } catch {
                removeError = "Could not remove \(player.playerName): \(error.localizedDescription)"
            }
            removingId = nil
        }
    }
}
