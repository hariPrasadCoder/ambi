import AppIntents

// MARK: - Shortcuts Provider

struct AmbiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseRecordingIntent(),
            phrases: ["Pause \(.applicationName) recording"],
            shortTitle: "Pause Recording",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: ResumeRecordingIntent(),
            phrases: ["Resume \(.applicationName) recording"],
            shortTitle: "Resume Recording",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: StartNewSessionIntent(),
            phrases: ["Start new \(.applicationName) session"],
            shortTitle: "New Session",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: GetTodaysTranscriptionsIntent(),
            phrases: ["Get today's \(.applicationName) transcriptions"],
            shortTitle: "Today's Transcriptions",
            systemImageName: "text.bubble"
        )
    }
}

// MARK: - Pause Recording

struct PauseRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Ambi Recording"
    static var description = IntentDescription("Pauses the active Ambi recording session.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.pauseRecording()
        return .result()
    }
}

// MARK: - Resume Recording

struct ResumeRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Ambi Recording"
    static var description = IntentDescription("Resumes a paused Ambi recording session.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.resumeRecording()
        return .result()
    }
}

// MARK: - Start New Session

struct StartNewSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start New Ambi Session"
    static var description = IntentDescription("Starts a new Ambi recording session.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.startNewSession()
        return .result()
    }
}

// MARK: - Get Today's Transcriptions

struct GetTodaysTranscriptionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today's Ambi Transcriptions"
    static var description = IntentDescription("Returns the first 5 transcriptions from today's session.")

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let transcriptions = Array(AppState.shared.transcriptions.prefix(5))
        let text = transcriptions.isEmpty
            ? "No transcriptions recorded today."
            : transcriptions.map { $0.text }.joined(separator: "\n\n")
        return .result(dialog: "\(text)")
    }
}
