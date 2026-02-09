import Foundation
import WhisperKit

actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private(set) var isModelLoaded = false
    private var modelName = "large-v3-turbo"
    
    init() {}
    
    func loadModel() async {
        do {
            // Initialize WhisperKit with specified model
            whisperKit = try await WhisperKit(
                model: modelName,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true
            )
            isModelLoaded = true
            print("Whisper model loaded successfully: \(modelName)")
        } catch {
            print("Failed to load Whisper model: \(error)")
            isModelLoaded = false
        }
    }
    
    func transcribe(audioData: Data) async -> String? {
        guard let whisper = whisperKit, isModelLoaded else {
            print("Whisper not ready")
            return nil
        }
        
        // Convert Data back to [Float]
        let samples = audioData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        
        guard !samples.isEmpty else { return nil }
        
        do {
            let result = try await whisper.transcribe(
                audioArray: samples,
                decodeOptions: DecodingOptions(
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
            )
            
            // Combine all segments
            let text = result.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Filter out common false positives
            let filtered = filterTranscription(text)
            
            return filtered.isEmpty ? nil : filtered
        } catch {
            print("Transcription error: \(error)")
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
            "[SILENCE]"
        ]
        
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for fp in falsePositives {
            if lowered == fp.lowercased() {
                return ""
            }
        }
        
        // Filter very short transcriptions that are likely noise
        if text.count < 3 {
            return ""
        }
        
        return text
    }
    
    func setModel(_ name: String) async {
        guard name != modelName else { return }
        modelName = name
        isModelLoaded = false
        whisperKit = nil
        await loadModel()
    }
    
    func getAvailableModels() -> [String] {
        [
            "tiny",
            "tiny.en",
            "base",
            "base.en",
            "small",
            "small.en",
            "medium",
            "medium.en",
            "large-v2",
            "large-v3",
            "large-v3-turbo"
        ]
    }
}
