import SwiftUI
import AppKit

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
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    appState.startNewSession()
                }
                .keyboardShortcut("n", modifiers: .command)
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
            HStack(spacing: 4) {
                Image(systemName: appState.isRecording ? (appState.isPaused ? "mic.slash.fill" : "mic.fill") : "mic.slash")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(appState.isRecording && !appState.isPaused ? .red : .secondary)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
    
    // Components
    private var audioRecorder: AudioRecorder?
    private var transcriptionEngine: TranscriptionEngine?
    private var databaseManager: DatabaseManager?
    
    private init() {
        needsOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
    
    func initialize() async {
        isLoading = true
        loadingMessage = "Initializing database..."
        
        // Initialize database
        databaseManager = try? DatabaseManager()
        
        // Load sessions
        if let db = databaseManager {
            sessions = (try? db.fetchAllSessions()) ?? []
            if let first = sessions.first {
                selectedSession = first
                transcriptions = (try? db.fetchTranscriptions(forSession: first.id!)) ?? []
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
        await transcriptionEngine?.loadModel(named: selectedModel) { progress in
            Task { @MainActor in
                self.modelDownloadProgress = progress
            }
        }
        isDownloadingModel = false
        
        if let engine = transcriptionEngine {
            isModelLoaded = await engine.isModelLoaded
        }
        
        // Initialize audio recorder
        let recorder = AudioRecorder { [weak self] audioData in
            Task { @MainActor in
                await self?.processAudio(audioData)
            }
        }
        
        recorder.onRecordingStarted = { [weak self] in
            Task { @MainActor in
                self?.isRecording = true
                self?.isPaused = false
            }
        }
        
        recorder.onPermissionDenied = { [weak self] in
            Task { @MainActor in
                self?.isRecording = false
                self?.hasMicrophonePermission = false
            }
        }
        
        audioRecorder = recorder
        isLoading = false
        
        // Auto-start recording
        startRecording()
    }
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        needsOnboarding = false
        Task {
            await startServices()
        }
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
        audioRecorder?.startRecording()
    }
    
    func pauseRecording() {
        audioRecorder?.pauseRecording()
        isPaused = true
        
        // Show accumulated transcript immediately
        if !liveTranscript.isEmpty {
            currentTranscription = liveTranscript
        }
    }
    
    func resumeRecording() {
        audioRecorder?.resumeRecording()
        isPaused = false
        liveTranscript = ""
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
        Task {
            audioRecorder?.startNewSession()
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
            
            let transcription = Transcription(
                id: nil,
                sessionId: session.id!,
                text: text,
                timestamp: Date(),
                duration: 30
            )
            
            try db.insertTranscription(transcription)
            
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
            await transcriptionEngine?.loadModel(named: modelName) { progress in
                Task { @MainActor in
                    self.modelDownloadProgress = progress
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
    
    func cleanup() {
        stopRecording()
    }
}

import AVFoundation
