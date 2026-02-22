import SwiftUI
import AppKit
import ServiceManagement

@main
struct AmbiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appTermination) {
                Button("Quit Ambi") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            CommandGroup(after: .appInfo) {
                Button("Settings...") {
                    SettingsWindowManager.shared.open(appState: AppState.shared)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.isRecording
                      ? (appState.isPaused ? "mic.slash.fill" : "mic.fill")
                      : "mic.slash.fill")
                    .symbolRenderingMode(.monochrome)

                if appState.isRecording && !appState.isPaused {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register UserDefaults defaults so toggles start enabled
        UserDefaults.standard.register(defaults: [
            "audioFeedbackEnabled": true,
            "showFloatingIndicator": true,
            "audioSource": "microphone"
        ])
        AmbiShortcuts.updateAppShortcutParameters()
        Task {
            await AppState.shared.initialize()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.cleanup()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

// MARK: - Content View (handles onboarding vs main)

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            if appState.needsOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.needsOnboarding)
    }
}

// MARK: - Audio Source

enum AudioSource: String, CaseIterable {
    case microphone  = "microphone"
    case systemAudio = "systemAudio"
    case both        = "both"

    var displayName: String {
        switch self {
        case .microphone:  return "Microphone"
        case .systemAudio: return "System Audio"
        case .both:        return "Mic + System"
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    // Recording state
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var currentTranscription = ""
    @Published var liveTranscript = "" // Real-time display
    
    // Data
    @Published var sessions: [Session] = []
    @Published var selectedSession: Session?
    @Published var transcriptions: [Transcription] = []
    
    // UI state
    @Published var showSettings = false
    @Published var isLoading = true
    @Published var loadingMessage = "Starting Ambi..."
    @Published var searchQuery = ""
    
    // Model state
    @Published var isModelLoaded = false
    @Published var isDownloadingModel = false
    @Published var modelDownloadProgress: Double = 0
    @Published var selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "base.en"
    
    // Onboarding
    @Published var needsOnboarding: Bool
    @Published var hasMicrophonePermission = false

    // New feature state
    @Published var dictionaryEntries: [DictionaryEntry] = []
    @Published var currentAudioLevel: Float = 0

    // System audio
    private var systemAudioRecorder: SystemAudioRecorder?
    @Published var hasSystemAudioPermission = false

    var audioSource: AudioSource {
        AudioSource(rawValue: UserDefaults.standard.string(forKey: "audioSource") ?? "microphone") ?? .microphone
    }

    // Components
    private var audioRecorder: AudioRecorder?
    private var transcriptionEngine: TranscriptionEngine?
    private var databaseManager: DatabaseManager?
    private var dayChangeObserver: NSObjectProtocol?

    private init() {
        needsOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
    
    func initialize() async {
        isLoading = true
        loadingMessage = "Initializing database..."
        
        // Initialize database
        databaseManager = try? DatabaseManager()
        
        // Load sessions and pre-select today's if it exists
        if let db = databaseManager {
            sessions = (try? db.fetchAllSessions()) ?? []
            let todaySession = sessions.first(where: { Calendar.current.isDateInToday($0.date) })
            let sessionToSelect = todaySession ?? sessions.first
            if let session = sessionToSelect {
                selectedSession = session
                transcriptions = (try? db.fetchTranscriptions(forSession: session.id!)) ?? []
            }
        }
        
        // Check permissions
        hasMicrophonePermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        
        if !needsOnboarding {
            await startServices()
        }
        
        isLoading = false
    }
    
    func startServices() async {
        loadingMessage = "Loading transcription model..."
        isLoading = true
        
        // Initialize transcription engine
        transcriptionEngine = TranscriptionEngine()
        
        isDownloadingModel = true
        await transcriptionEngine?.loadModel(named: selectedModel) { progress, message in
            Task { @MainActor in
                self.modelDownloadProgress = progress
                self.loadingMessage = message
            }
        }
        isDownloadingModel = false
        
        if let engine = transcriptionEngine {
            isModelLoaded = await engine.isModelLoaded
            if !isModelLoaded {
                if let error = await engine.loadError {
                    loadingMessage = "Error: \(error)"
                }
            }
        }
        
        // Initialize audio recorder (with persisted interval setting)
        let interval = UserDefaults.standard.double(forKey: "transcriptionInterval")
        let recorder = AudioRecorder(processingInterval: interval > 0 ? interval : 30) { [weak self] audioData in
            Task { @MainActor in
                await self?.processAudio(audioData)
            }
        }

        recorder.onAudioLevelChanged = { [weak self] level in
            Task { @MainActor in self?.currentAudioLevel = level }
        }

        recorder.onRecordingStarted = { [weak self] in
            Task { @MainActor in
                self?.isRecording = true
                self?.isPaused = false
                SoundManager.shared.play(.recordingStarted)
            }
        }

        recorder.onPermissionDenied = { [weak self] in
            Task { @MainActor in
                self?.isRecording = false
                self?.hasMicrophonePermission = false
            }
        }

        audioRecorder = recorder

        // Initialize system audio recorder (uses same callback pipeline)
        let sysRecorder = SystemAudioRecorder()
        sysRecorder.processingInterval = interval > 0 ? interval : 30
        sysRecorder.transcriptionCallback = { [weak self] audioData in
            Task { @MainActor in
                await self?.processAudio(audioData)
            }
        }
        sysRecorder.onAudioLevelChanged = { [weak self] level in
            Task { @MainActor in self?.currentAudioLevel = level }
        }
        systemAudioRecorder = sysRecorder
        hasSystemAudioPermission = SystemAudioRecorder.hasPermission()

        isLoading = false

        // Load personal dictionary into engine
        refreshDictionaryInEngine()
        
        // Auto-start recording
        startRecording()

        // Eagerly create today's session so it appears in the sidebar immediately,
        // even before the first transcription is saved.
        if let db = databaseManager,
           let todaySession = try? db.getOrCreateTodaySession() {
            sessions = (try? db.fetchAllSessions()) ?? []
            selectedSession = todaySession
            transcriptions = (try? db.fetchTranscriptions(forSession: todaySession.id!)) ?? []
        }

        // Watch for midnight day change to open a new session automatically
        setupDayChangeObserver()
    }

    private func setupDayChangeObserver() {
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDayChange()
            }
        }
    }

    private func handleDayChange() {
        guard let db = databaseManager else { return }
        do {
            let newSession = try db.getOrCreateTodaySession()
            sessions = (try? db.fetchAllSessions()) ?? []
            selectedSession = newSession
            transcriptions = []
            liveTranscript = ""
            currentTranscription = ""
            SoundManager.shared.play(.sessionCreated)
        } catch {
            print("Failed to create session for new day: \(error)")
        }
    }
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        needsOnboarding = false
        // Auto-register for launch at login so Ambi is always ready
        try? SMAppService.mainApp.register()
        Task {
            await startServices()
        }
    }
    
    func checkSystemAudioPermission() {
        hasSystemAudioPermission = SystemAudioRecorder.hasPermission()
    }

    func requestSystemAudioPermission() async -> Bool {
        let granted = await Task.detached { SystemAudioRecorder.requestPermission() }.value
        hasSystemAudioPermission = granted
        return granted
    }

    func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    self.hasMicrophonePermission = granted
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    func startRecording() {
        guard !isRecording, isModelLoaded else { return }
        let source = audioSource
        if source == .microphone || source == .both {
            audioRecorder?.startRecording()
        }
        if source == .systemAudio || source == .both {
            Task {
                do {
                    try await systemAudioRecorder?.start()
                    // For system-audio-only, audioRecorder won't fire onRecordingStarted
                    if source == .systemAudio {
                        isRecording = true
                        isPaused = false
                        SoundManager.shared.play(.recordingStarted)
                    }
                } catch {
                    print("SystemAudioRecorder start failed: \(error)")
                }
            }
        }
    }
    
    func pauseRecording() {
        audioRecorder?.pauseRecording()
        systemAudioRecorder?.pause()
        isPaused = true
        SoundManager.shared.play(.recordingPaused)

        // Show accumulated transcript immediately
        if !liveTranscript.isEmpty {
            currentTranscription = liveTranscript
        }
    }

    func resumeRecording() {
        audioRecorder?.resumeRecording()
        systemAudioRecorder?.resume()
        isPaused = false
        liveTranscript = ""
        SoundManager.shared.play(.recordingResumed)
    }

    func stopRecording() {
        audioRecorder?.stopRecording()
        Task { await systemAudioRecorder?.stop() }
        isRecording = false
    }
    
    func toggleRecording() {
        if isPaused {
            resumeRecording()
        } else if isRecording {
            pauseRecording()
        } else {
            startRecording()
        }
    }
    
    func startNewSession() {
        Task {
            audioRecorder?.startNewSession()
            systemAudioRecorder?.startNewSession()
            liveTranscript = ""
            currentTranscription = ""
            
            // Refresh sessions
            if let db = databaseManager {
                sessions = (try? db.fetchAllSessions()) ?? []
            }
        }
    }
    
    private func processAudio(_ audioData: Data) async {
        guard let engine = transcriptionEngine else { return }
        let modelLoaded = await engine.isModelLoaded
        guard modelLoaded else { return }
        
        if let text = await engine.transcribe(audioData: audioData), !text.isEmpty {
            // Update live transcript
            if liveTranscript.isEmpty {
                liveTranscript = text
            } else {
                liveTranscript += " " + text
            }
            
            currentTranscription = text
            
            // Save to database
            await saveTranscription(text)
        }
    }
    
    private func saveTranscription(_ text: String) async {
        guard let db = databaseManager else { return }

        do {
            let session = try db.getOrCreateTodaySession()
            let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName

            let transcription = Transcription(
                id: nil,
                sessionId: session.id!,
                text: text,
                timestamp: Date(),
                duration: 30,
                sourceApp: frontmostApp
            )

            try db.insertTranscription(transcription)
            SoundManager.shared.play(.transcriptionSaved)

            // Refresh data
            sessions = try db.fetchAllSessions()

            if selectedSession?.id == session.id {
                transcriptions = try db.fetchTranscriptions(forSession: session.id!)
                selectedSession = try db.fetchSession(id: session.id!)
            }
        } catch {
            print("Failed to save transcription: \(error)")
        }
    }
    
    func selectSession(_ session: Session) {
        selectedSession = session
        if let db = databaseManager, let id = session.id {
            transcriptions = (try? db.fetchTranscriptions(forSession: id)) ?? []
        }
    }
    
    func deleteSession(_ session: Session) {
        guard let db = databaseManager, let id = session.id else { return }
        try? db.deleteSession(id)
        sessions.removeAll { $0.id == id }
        if selectedSession?.id == id {
            selectedSession = sessions.first
            if let first = selectedSession {
                transcriptions = (try? db.fetchTranscriptions(forSession: first.id!)) ?? []
            } else {
                transcriptions = []
            }
        }
    }
    
    func changeModel(to modelName: String) {
        guard modelName != selectedModel else { return }
        selectedModel = modelName
        UserDefaults.standard.set(modelName, forKey: "selectedModel")
        
        Task {
            isModelLoaded = false
            isDownloadingModel = true
            loadingMessage = "Switching model..."
            await transcriptionEngine?.loadModel(named: modelName) { progress, message in
                Task { @MainActor in
                    self.modelDownloadProgress = progress
                    self.loadingMessage = message
                }
            }
            isDownloadingModel = false
            if let engine = transcriptionEngine {
                isModelLoaded = await engine.isModelLoaded
            }
        }
    }
    
    func searchTranscriptions() -> [Session] {
        guard !searchQuery.isEmpty, let db = databaseManager else { return sessions }
        return (try? db.searchSessions(query: searchQuery)) ?? []
    }
    
    // MARK: - Dictionary Management

    func addDictionaryEntry(original: String, replacement: String) {
        guard let db = databaseManager, !original.isEmpty, !replacement.isEmpty else { return }
        let entry = DictionaryEntry(
            id: nil,
            original: original.lowercased().trimmingCharacters(in: .whitespaces),
            replacement: replacement.trimmingCharacters(in: .whitespaces),
            createdAt: Date()
        )
        try? db.insertDictionaryEntry(entry)
        dictionaryEntries = (try? db.fetchDictionaryEntries()) ?? []
        refreshDictionaryInEngine()
    }

    func removeDictionaryEntry(_ entry: DictionaryEntry) {
        guard let db = databaseManager, let id = entry.id else { return }
        try? db.deleteDictionaryEntry(id)
        dictionaryEntries = (try? db.fetchDictionaryEntries()) ?? []
        refreshDictionaryInEngine()
    }

    private func refreshDictionaryInEngine() {
        guard let db = databaseManager, let engine = transcriptionEngine else { return }
        dictionaryEntries = (try? db.fetchDictionaryEntries()) ?? []
        let map = (try? db.fetchDictionaryMap()) ?? [:]
        Task {
            await engine.updateDictionary(map)
        }
    }

    func cleanup() {
        stopRecording()
        if let observer = dayChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

import AVFoundation
