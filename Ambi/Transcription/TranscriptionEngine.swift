import Foundation
import WhisperKit

actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private(set) var isModelLoaded = false
    private var currentModelName = ""
    private(set) var loadError: String?
    
    init() {}
    
    func loadModel(named modelName: String = "base.en", progressCallback: ((Double, String) -> Void)? = nil) async {
        // Don't reload if same model
        if modelName == currentModelName && isModelLoaded {
            return
        }
        
        currentModelName = modelName
        isModelLoaded = false
        loadError = nil
        whisperKit = nil
        
        print("TranscriptionEngine: Loading model \(modelName)...")
        progressCallback?(0.1, "Checking model...")
        
        do {
            // Use verbose mode to see what's happening
            progressCallback?(0.2, "Downloading model (this may take a few minutes)...")
            
            // Initialize WhisperKit with the model
            // This will download if needed
            whisperKit = try await WhisperKit(
                model: modelName,
                verbose: true,
                logLevel: .debug,
                prewarm: false,  // Don't prewarm initially
                load: true,
                download: true
            )
            
            progressCallback?(0.8, "Warming up model...")
            
            // Prewarm after loading
            try await whisperKit?.prewarmModels()
            
            isModelLoaded = true
            loadError = nil
            progressCallback?(1.0, "Ready!")
            print("TranscriptionEngine: Model \(modelName) loaded successfully")
            
        } catch {
            let errorMsg = "Failed to load model: \(error.localizedDescription)"
            print("TranscriptionEngine: \(errorMsg)")
            loadError = errorMsg
            isModelLoaded = false
            progressCallback?(0, errorMsg)
        }
    }
    
    func transcribe(audioData: Data) async -> String? {
        guard let whisper = whisperKit, isModelLoaded else {
            print("TranscriptionEngine: Whisper not ready")
            return nil
        }
        
        // Convert Data back to [Float]
        let samples = audioData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        
        guard !samples.isEmpty else { return nil }
        
        do {
            let result = try await whisper.transcribe(
                audioArray: samples
            )
            
            // Combine all segments
            let text = result.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Filter out common false positives
            let filtered = filterTranscription(text)
            
            return filtered.isEmpty ? nil : filtered
        } catch {
            print("TranscriptionEngine: Transcription error: \(error)")
            return nil
        }
    }
    
    private func filterTranscription(_ text: String) -> String {
        // Common whisper hallucinations on silence
        let falsePositives = [
            "Thank you.",
            "Thanks for watching.",
            "Subscribe to my channel.",
            "Like and subscribe.",
            "See you in the next video.",
            "Bye.",
            "Thank you for watching.",
            "[Music]",
            "(music)",
            "♪",
            "...",
            "[BLANK_AUDIO]",
            "[SILENCE]",
            "you",
            "You",
            "I'm sorry.",
            "Thanks.",
            "Okay.",
            "OK.",
            "Uh",
            "Um"
        ]
        
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for fp in falsePositives {
            if lowered == fp.lowercased() {
                return ""
            }
        }
        
        // Filter very short transcriptions
        if text.count < 5 {
            return ""
        }
        
        return text
    }
    
    func getAvailableModels() -> [(id: String, name: String, size: String)] {
        [
            ("tiny.en", "Tiny English", "~75 MB"),
            ("tiny", "Tiny (Multilingual)", "~75 MB"),
            ("base.en", "Base English", "~140 MB"),
            ("base", "Base (Multilingual)", "~140 MB"),
            ("small.en", "Small English", "~460 MB"),
            ("small", "Small (Multilingual)", "~460 MB"),
            ("large-v3-turbo", "Large v3 Turbo", "~1.5 GB")
        ]
    }
}
