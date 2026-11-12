import AVFoundation
import Testing

@testable import mafia_manager

@MainActor
struct SoundAssetTests {
    @Test(arguments: GameSound.allCases)
    func everySoundIsBundledAndPlayable(_ sound: GameSound) throws {
        let url = try #require(sound.url, "\(sound.rawValue).m4a is not in the app bundle")
        #expect(url.pathExtension == "m4a")
        let player = try AVAudioPlayer(contentsOf: url)
        #expect(player.duration > 0)
    }
}
