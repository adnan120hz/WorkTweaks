import AVFoundation
import Foundation

/// Short UI sounds: a soft tap for menus and features, a soft
/// swipe for tab switches. Bundled WAVs, played through
/// AVAudioPlayer on the .ambient session — so they respect the
/// silent switch and never stop the user's music. One master
/// switch (wt.soundEffectsEnabled, on by default) lives in the
/// Sandbox tab next to the Tweaks UI choice.
enum SoundEffects {
    private static let enabledKey = "wt.soundEffectsEnabled"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static var tapPlayer: AVAudioPlayer?
    private static var swipePlayer: AVAudioPlayer?
    private static var sessionPrepared = false

    static func playTap() { play(named: "tap", player: &tapPlayer) }
    static func playSwipe() { play(named: "swipe", player: &swipePlayer) }

    private static func play(named: String, player: inout AVAudioPlayer?) {
        guard enabled else { return }
        prepareSession()
        guard let url = Bundle.main.url(forResource: named, withExtension: "wav") else {
            print("[Sound] missing bundled sound: \(named).wav")
            return
        }
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        }
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private static func prepareSession() {
        guard !sessionPrepared else { return }
        sessionPrepared = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }
}
