import AVFoundation
import Observation

/// Spielt Alarmtöne zum Vorhören in den Einstellungen ab.
@Observable
final class SoundPreviewPlayer: NSObject, AVAudioPlayerDelegate {

    static let shared = SoundPreviewPlayer()

    private var player: AVAudioPlayer?

    /// Der gerade abgespielte Ton, `nil` wenn nichts läuft.
    private(set) var playingSound: AlarmSound?

    func toggle(_ sound: AlarmSound, volume: Double) {
        if playingSound == sound {
            stop()
        } else {
            play(sound, volume: volume)
        }
    }

    func play(_ sound: AlarmSound, volume: Double) {
        stop()
        guard let fileName = sound.fileName,
              let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            // Der iOS-Standardton liegt nicht im Bundle – kurzer System-Hinweiston.
            AudioServicesPlaySystemSound(1005)
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = Float(volume)
            p.delegate = self
            p.play()
            player = p
            playingSound = sound
        } catch {
            print("[PegelWatch] Sound-Vorschau fehlgeschlagen: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingSound = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.playingSound = nil
        }
    }
}
