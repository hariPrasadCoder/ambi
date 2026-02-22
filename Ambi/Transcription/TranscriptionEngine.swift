import Foundation
import WhisperKit

actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private(set) var isModelLoaded = false
    private var currentModelName = ""
    private(set) var loadError: String?
    private var personalDictionary: [String: String] = [:]

    init() {}

    func updateDictionary(_ map: [String: String]) {
        personalDictionary = map
    }

    private func applyPersonalDictionary(_ text: String) -> String {
        guard !personalDictionary.isEmpty else { return text }
        var result = text
        for (original, replacement) in personalDictionary {
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: original))\\b",
                options: .caseInsensitive
            ) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }
    
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
        progressCallback?(0.0, "Checking model...")

        do {
            // Step 1: Download model with real progress reporting (0% → 85%)
            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { progress in
                    let fraction = min(progress.fractionCompleted, 1.0)
                    progressCallback?(fraction * 0.85, "Downloading model... \(Int(fraction * 100))%")
                }
            )

            // Step 2: Load model from the downloaded folder (85% → 95%)
            progressCallback?(0.87, "Loading model...")
            whisperKit = try await WhisperKit(
                modelFolder: modelFolder.path,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: false
            )

            // Step 3: Prewarm for faster first transcription (95% → 100%)
            progressCallback?(0.95, "Warming up model...")
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
            guard !filtered.isEmpty else { return nil }

            return applyPersonalDictionary(filtered)
        } catch {
            print("TranscriptionEngine: Transcription error: \(error)")
            return nil
        }
    }
    
    private func filterTranscription(_ text: String) -> String {
        // Whisper hallucinations that appear on silence/noise — exact-match only
        let hallucinations: Set<String> = [
            "thank you.",
            "thanks for watching.",
            "subscribe to my channel.",
            "like and subscribe.",
            "see you in the next video.",
            "thank you for watching.",
            "[music]",
            "(music)",
            "♪",
            "...",
            "[blank_audio]",
            "[silence]",
            "(silence)",
            "[ silence ]",
            "[ Silence ]",
        ]

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        // Drop exact hallucination matches
        if hallucinations.contains(lowered) {
            return ""
        }

        // Drop anything that is purely punctuation or whitespace
        let meaningful = trimmed.filter { $0.isLetter || $0.isNumber }
        if meaningful.count < 2 {
            return ""
        }

        return trimmed
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
