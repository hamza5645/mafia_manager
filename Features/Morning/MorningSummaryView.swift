import SwiftUI
import AVFoundation

struct MorningSummaryView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showEndGameConfirmation = false
    @State private var wakeUpSoundPlayer: AVAudioPlayer?
    @State private var isAudioSessionConfigured = false

    private var lastNight: NightAction? { store.state.nightHistory.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let night = lastNight {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.stars.fill").foregroundStyle(Design.Colors.brandGold)
                            Text("Night \(night.nightIndex) Summary").font(.headline)
                        }
                        summaryRow(title: "Mafia", value: mafiaSummary(for: night))
                        summaryRow(title: "Killed", value: killedSummary(for: night))
                        summaryRow(title: "Police", value: policeSummary(for: night))
                        summaryRow(title: "Doctor", value: doctorSummary(for: night))
                    }
                    .cardStyle()
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .navigationTitle("Morning Summary")
        .navigationBarBackButtonHidden(true)
        .background(Design.Colors.surface0.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEndGameConfirmation = true
                } label: {
                    Text("End Game")
                        .foregroundColor(Design.Colors.dangerRed)
                }
            }
        }
        .alert("Are you sure you want to end the game?", isPresented: $showEndGameConfirmation) {
            Button("End Game", role: .destructive) {
                store.endGameEarly()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will end the current game without determining a winner.")
        }
        .onAppear {
            configureAudioSessionIfNeeded()
            playMorningWakeUpSound()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    if store.state.isGameOver {
                        store.transitionToGameOver()
                    } else {
                        // Transition to death reveal screen to show who died
                        store.transitionToDeathReveal()
                    }
                } label: {
                    Text(store.state.isGameOver ? "View Result" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .primary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Design.Colors.surface0.opacity(0.95))
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text("\(title):")
                .fontWeight(.semibold)
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(Design.Colors.textSecondary)
        }
    }
}

// Removed local GlassButtonStyle; using global CTAButtonStyle instead.

private extension MorningSummaryView {
    func mafiaSummary(for night: NightAction) -> String {
        let numbers = night.mafiaNumbers.sorted()
        let mafiaLabel = numbers.isEmpty ? "—" : numbers.map { "#\($0)" }.joined(separator: ", ")

        if let targetNumber = store.number(for: night.mafiaTargetPlayerID) {
            return "\(mafiaLabel) → #\(targetNumber)"
        }
        return mafiaLabel
    }

    func killedSummary(for night: NightAction) -> String {
        let deathNumbers = night.resultingDeaths.compactMap { store.number(for: $0) }.sorted()

        if !deathNumbers.isEmpty {
            return deathNumbers.map { "#\($0)" }.joined(separator: ", ")
        }

        // No deaths - check if doctor saved someone
        if let targetNumber = store.number(for: night.mafiaTargetPlayerID),
           night.doctorProtectedPlayerID == night.mafiaTargetPlayerID {
            return "None (Doctor saved #\(targetNumber))"
        }

        return "None"
    }

    func policeSummary(for night: NightAction) -> String {
        let policeNumbers = store.state.players.filter { $0.role == .inspector }.map { $0.number }.sorted()
        let policeLabel = policeNumbers.isEmpty ? "—" : policeNumbers.map { "#\($0)" }.joined(separator: ", ")
        if let inspectedNum = store.number(for: night.inspectorCheckedPlayerID) {
            return "\(policeLabel) → #\(inspectedNum)"
        }
        return policeLabel
    }

    func doctorSummary(for night: NightAction) -> String {
        let doctorNumbers = store.state.players.filter { $0.role == .doctor }.map { $0.number }.sorted()
        let doctorLabel = doctorNumbers.isEmpty ? "—" : doctorNumbers.map { "#\($0)" }.joined(separator: ", ")
        if let protectedNum = store.number(for: night.doctorProtectedPlayerID) {
            return "\(doctorLabel) → #\(protectedNum)"
        }
        return doctorLabel
    }

    func configureAudioSessionIfNeeded() {
        guard !isAudioSessionConfigured else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            isAudioSessionConfigured = true
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    func playMorningWakeUpSound() {
        guard let url = Bundle.main.url(forResource: "wakeup_rooster", withExtension: "wav") else {
            print("Missing morning wake-up sound file: wakeup_rooster.wav")
            return
        }

        wakeUpSoundPlayer?.stop()

        do {
            wakeUpSoundPlayer = try AVAudioPlayer(contentsOf: url)
            wakeUpSoundPlayer?.volume = 1.0
            wakeUpSoundPlayer?.prepareToPlay()
            wakeUpSoundPlayer?.play()
        } catch {
            print("Failed to play morning wake-up sound: \(error.localizedDescription)")
        }
    }
}
