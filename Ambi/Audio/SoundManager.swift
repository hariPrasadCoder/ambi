import AppKit

enum SoundEvent {
    case recordingStarted
    case recordingPaused
    case recordingResumed
    case transcriptionSaved
    case sessionCreated
}

@MainActor
class SoundManager {
    static let shared = SoundManager()

    private init() {}

    func play(_ event: SoundEvent) {
        guard isEnabled else { return }

        let soundName: String
        switch event {
        case .recordingStarted:  soundName = "Tink"
        case .recordingPaused:   soundName = "Morse"
        case .recordingResumed:  soundName = "Tink"
        case .transcriptionSaved: soundName = "Pop"
        case .sessionCreated:    soundName = "Bottle"
        }

        if let sound = NSSound(named: soundName) {
            sound.volume = 0.5
            sound.play()
        }
    }

    private var isEnabled: Bool {
        // Default true when the key hasn't been set yet
        guard UserDefaults.standard.object(forKey: "audioFeedbackEnabled") != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: "audioFeedbackEnabled")
    }
}
