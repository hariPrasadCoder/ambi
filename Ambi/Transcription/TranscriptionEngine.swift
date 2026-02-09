import Foundation
import WhisperKit

actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private(set) var isModelLoaded = false
    private var currentModelName = ""
    
    init() {}
    
    func loadModel(named modelName: String = "base.en", progressCallback: ((Double) -> Void)? = nil) async {
        // Don't reload if same model
        if modelName == currentModelName && isModelLoaded {
            return
        }
        
        currentModelName = modelName
        isModelLoaded = false
        whisperKit = nil
        
        print("TranscriptionEngine: Loading model \(modelName)...")
        
        do {
            // WhisperKit will download the model if needed
            let config = WhisperKitConfig(
                model: modelName,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true
            )
            
            whisperKit = try await WhisperKit(config)
            
            isModelLoaded = true
            print("TranscriptionEngine: Model \(modelName) loaded successfully")
        } catch {
            print("TranscriptionEngine: Failed to load model: \(error)")
            isModelLoaded = false
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
            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: "en",
                temperatureFallbackCount: 3,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                suppressBlank: true
            )
            
            let result = try await whisper.transcribe(
                audioArray: samples,
                decodeOptions: options
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
            ("medium.en", "Medium English", "~1.5 GB"),
            ("medium", "Medium (Multilingual)", "~1.5 GB"),
            ("large-v3-turbo", "Large v3 Turbo", "~1.5 GB"),
            ("large-v3", "Large v3", "~3 GB")
        ]
    }
}

// WhisperKit config helper
struct WhisperKitConfig {
    let model: String
    let verbose: Bool
    let logLevel: Logging.LogLevel
    let prewarm: Bool
    let load: Bool
    let download: Bool
}

extension WhisperKit {
    convenience init(_ config: WhisperKitConfig) async throws {
        try await self.init(
            model: config.model,
            verbose: config.verbose,
            logLevel: config.logLevel,
            prewarm: config.prewarm,
            load: config.load,
            download: config.download
        )
    }
}
