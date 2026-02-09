import SwiftUI
import AppKit

@main
struct AmbiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    appState.startNewSession()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isRecording ? "mic.fill" : "mic.slash.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start recording on launch
        Task {
            await AppState.shared.initialize()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up
        AppState.shared.cleanup()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar when window is closed
        return false
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var currentTranscription = ""
    @Published var sessions: [Session] = []
    @Published var selectedSession: Session?
    @Published var showSettings = false
    @Published var isModelLoaded = false
    @Published var isLoading = true
    @Published var searchQuery = ""
    
    private var audioRecorder: AudioRecorder?
    private var transcriptionEngine: TranscriptionEngine?
    private var databaseManager: DatabaseManager?
    
    private init() {}
    
    func initialize() async {
        isLoading = true
        
        // Initialize database
        databaseManager = try? DatabaseManager()
        
        // Load sessions
        if let db = databaseManager {
            sessions = (try? db.fetchAllSessions()) ?? []
        }
        
        // Initialize transcription engine
        transcriptionEngine = TranscriptionEngine()
        await transcriptionEngine?.loadModel()
        if let engine = transcriptionEngine {
            isModelLoaded = await engine.isModelLoaded
        }
        
        // Initialize audio recorder with callbacks
        let recorder = AudioRecorder { [weak self] audioData in
            Task { @MainActor in
                await self?.processAudio(audioData)
            }
        }
        
        recorder.onRecordingStarted = { [weak self] in
            Task { @MainActor in
                self?.isRecording = true
                self?.isPaused = false
                print("AppState: Recording started")
            }
        }
        
        recorder.onPermissionDenied = { [weak self] in
            Task { @MainActor in
                self?.isRecording = false
                print("AppState: Microphone permission denied")
            }
        }
        
        audioRecorder = recorder
        
        // Start recording (will check permission first)
        recorder.startRecording()
        
        isLoading = false
    }
    
    func startRecording() {
        guard !isRecording else { return }
        audioRecorder?.startRecording()
        // isRecording will be set by the onRecordingStarted callback
    }
    
    func pauseRecording() {
        audioRecorder?.pauseRecording()
        isPaused = true
    }
    
    func resumeRecording() {
        audioRecorder?.resumeRecording()
        isPaused = false
    }
    
    func stopRecording() {
        audioRecorder?.stopRecording()
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
        // Finalize current session and start a new one
        Task {
            await finalizeCurrentSession()
            audioRecorder?.startNewSession()
        }
    }
    
    private func processAudio(_ audioData: Data) async {
        guard let engine = transcriptionEngine else { return }
        let modelLoaded = await engine.isModelLoaded
        guard modelLoaded else { return }
        
        if let text = await engine.transcribe(audioData: audioData), !text.isEmpty {
            currentTranscription = text
            
            // Save to database
            await saveTranscription(text)
        }
    }
    
    private func saveTranscription(_ text: String) async {
        guard let db = databaseManager else { return }
        
        do {
            // Get or create today's session
            let session = try db.getOrCreateTodaySession()
            
            // Create transcription entry
            let transcription = Transcription(
                id: nil,
                sessionId: session.id!,
                text: text,
                timestamp: Date(),
                duration: 30 // approximate duration in seconds
            )
            
            try db.insertTranscription(transcription)
            
            // Refresh sessions
            sessions = try db.fetchAllSessions()
            
            // Update selected session if it's today's
            if selectedSession?.id == session.id {
                selectedSession = try db.fetchSession(id: session.id!)
            }
        } catch {
            print("Failed to save transcription: \(error)")
        }
    }
    
    private func finalizeCurrentSession() async {
        // Generate title for current session based on content
        guard let db = databaseManager,
              let session = try? db.getTodaySession(),
              session.title == nil || session.title?.isEmpty == true else { return }
        
        let transcriptions = (try? db.fetchTranscriptions(forSession: session.id!)) ?? []
        let allText = transcriptions.map { $0.text }.joined(separator: " ")
        
        if !allText.isEmpty {
            // Simple title generation - first meaningful sentence or phrase
            let title = generateTitle(from: allText)
            try? db.updateSessionTitle(session.id!, title: title)
        }
    }
    
    private func generateTitle(from text: String) -> String {
        // Extract first meaningful sentence (up to 50 chars)
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        if let first = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            if first.count <= 50 {
                return first
            }
            return String(first.prefix(47)) + "..."
        }
        return "Untitled Session"
    }
    
    func deleteSession(_ session: Session) {
        guard let db = databaseManager, let id = session.id else { return }
        try? db.deleteSession(id)
        sessions.removeAll { $0.id == id }
        if selectedSession?.id == id {
            selectedSession = nil
        }
    }
    
    func searchTranscriptions() -> [Session] {
        guard !searchQuery.isEmpty, let db = databaseManager else { return sessions }
        return (try? db.searchSessions(query: searchQuery)) ?? []
    }
    
    func cleanup() {
        stopRecording()
        Task {
            await finalizeCurrentSession()
        }
    }
}
