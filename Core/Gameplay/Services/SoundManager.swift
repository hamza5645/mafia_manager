import AVFoundation
import Combine

enum GameSound: String, CaseIterable {
    case mafiaGunshot = "mafia_gunshot"
    case policeSiren = "police_siren"
    case doctorEcg = "doctor_ecg"
    case wakeupRooster = "wakeup_rooster"

    /// The bundled AAC file (M4A container).
    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: "m4a") }
}

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var players: [GameSound: AVAudioPlayer] = [:]
    private var hasWarmedUp = false
    private var isSessionActive = false
    private var interruptionObserver: AnyCancellable?

    private init() {
        // A call or Siri deactivates the session; re-activate it when that ends,
        // so only a real trip to the background has to reset it.
        // AVAudioSession may post off the main thread; these closures are main-actor.
        interruptionObserver = NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .compactMap { note in
                (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            }
            .sink { [weak self] type in
                self?.handleInterruption(type)
            }
    }

    // MARK: - Warm Up

    /// Preloads all sound files and prepares them for playback. Not called at
    /// launch: the solo night's Start Night warms up, and `play()` falls back to it.
    /// Guarded by `hasWarmedUp`, so calling it again costs nothing.
    func warmUp() {
        guard !hasWarmedUp else { return }
        hasWarmedUp = true

        // Mix with other audio before any player exists, so preparing one
        // never interrupts the user's music.
        ensureAudioSession()

        for sound in GameSound.allCases {
            guard let url = sound.url else {
                print("[SoundManager] Missing sound file: \(sound.rawValue).m4a")
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

    private func handleInterruption(_ type: AVAudioSession.InterruptionType) {
        switch type {
        case .began:
            isSessionActive = false
        case .ended:
            ensureAudioSession()
        @unknown default:
            isSessionActive = false
        }
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
