import AVFoundation

enum GameSound: String, CaseIterable {
    case mafiaGunshot = "mafia_gunshot"
    case policeSiren = "police_siren"
    case doctorEcg = "doctor_ecg"
    case wakeupRooster = "wakeup_rooster"
}

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var players: [GameSound: AVAudioPlayer] = [:]
    private var hasWarmedUp = false
    private var isSessionActive = false

    private init() {}

    // MARK: - Warm Up

    /// Preloads all sound files and prepares them for playback.
    /// Guarded by `hasWarmedUp` — safe to call multiple times.
    func warmUp() {
        guard !hasWarmedUp else { return }
        hasWarmedUp = true

        for sound in GameSound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else {
                print("[SoundManager] Missing sound file: \(sound.rawValue).wav")
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[sound] = player
            } catch {
                print("[SoundManager] Failed to preload \(sound.rawValue): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Audio Session

    /// Ensures the audio session is active. Early-returns if already configured.
    /// Re-activates after backgrounding deactivates the session.
    private func ensureAudioSession() {
        let session = AVAudioSession.sharedInstance()

        if isSessionActive && session.category == .playback {
            return
        }

        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            isSessionActive = true
        } catch {
            print("[SoundManager] Failed to configure audio session: \(error.localizedDescription)")
            isSessionActive = false
        }
    }

    /// Called when the app enters background to track session state.
    func handleBackgrounding() {
        isSessionActive = false
    }

    // MARK: - Playback

    func play(_ sound: GameSound, volume: Float = 1.0) {
        ensureAudioSession()
        warmUp()

        guard let player = players[sound] else {
            print("[SoundManager] No player for \(sound.rawValue)")
            return
        }

        if player.isPlaying {
            player.stop()
        }

        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    func stop(_ sound: GameSound) {
        players[sound]?.stop()
    }

    func stopAll() {
        for player in players.values where player.isPlaying {
            player.stop()
        }
    }

    // MARK: - Role Convenience

    static func sound(for role: Role) -> GameSound? {
        switch role {
        case .mafia:     return .mafiaGunshot
        case .inspector: return .policeSiren
        case .doctor:    return .doctorEcg
        case .citizen:   return nil
        }
    }

    func playWakeUp(for role: Role) {
        stopAll()
        guard let sound = Self.sound(for: role) else { return }
        play(sound)
    }
}
