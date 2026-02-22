import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - Model Options  (mirrors the Whisper model list)

struct SummaryModel: Identifiable, Equatable {
    let id: String            // HuggingFace repo ID
    let displayName: String
    let size: String
    let quality: String       // star rating

    var modelConfiguration: ModelConfiguration {
        ModelConfiguration(id: id)
    }

    static let all: [SummaryModel] = [
        SummaryModel(
            id: "mlx-community/SmolLM-135M-Instruct-4bit",
            displayName: "SmolLM 135M (Fastest)",
            size: "~100 MB",
            quality: "⭐⭐"
        ),
        SummaryModel(
            id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            displayName: "Qwen 1.5B",
            size: "~900 MB",
            quality: "⭐⭐⭐"
        ),
        SummaryModel(
            id: "mlx-community/Qwen3-4B-4bit",
            displayName: "Qwen3 4B (Best)",
            size: "~2.5 GB",
            quality: "⭐⭐⭐⭐"
        ),
    ]

    static let `default` = all[0]
}

// MARK: - Load State

enum LLMLoadState: Equatable {
    case idle
    case downloading(progress: Double)
    case loading
    case ready
    case error(String)

    var isReady: Bool { self == .ready }
    var isBusy: Bool {
        switch self { case .downloading, .loading: return true; default: return false }
    }
}

// MARK: - Manager  (MainActor — drives UI, same pattern as AppState)

@MainActor
final class LocalLLMManager: ObservableObject {
    static let shared = LocalLLMManager()

    @Published var loadState: LLMLoadState = .idle
    @Published var selectedModel: SummaryModel

    private var container: ModelContainer?

    private init() {
        let savedId = UserDefaults.standard.string(forKey: "selectedSummaryModel") ?? ""
        selectedModel = SummaryModel.all.first { $0.id == savedId } ?? .default
        // Auto-load if model files are already on disk
        if isModelCached {
            Task { await self.loadModel() }
        }
    }

    /// Checks if the selected model's files exist in the MLX on-disk cache.
    private var isModelCached: Bool {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return false }
        let modelPath = cacheDir.appendingPathComponent("models/\(selectedModel.id)")
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    // MARK: - Public API

    /// Download (if needed) and load the selected model into memory.
    func loadModel() async {
        guard !loadState.isBusy else { return }
        loadState = .downloading(progress: 0)

        do {
            let config = selectedModel.modelConfiguration
            let result = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.loadState = .downloading(progress: progress.fractionCompleted)
                }
            }
            container = result
            loadState = .ready
            UserDefaults.standard.set(selectedModel.id, forKey: "selectedSummaryModel")
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    /// Switch to a different model, clearing the old one.
    func selectModel(_ model: SummaryModel) {
        guard model != selectedModel else { return }
        selectedModel = model
        container = nil
        loadState = .idle
        UserDefaults.standard.set(model.id, forKey: "selectedSummaryModel")
    }

    /// Summarizes text, chunking long transcripts and merging results.
    /// Returns nil when no model is loaded.
    func summarize(text: String, category: MeetingCategory) async -> [String]? {
        guard let container, loadState.isReady else { return nil }

        let chunkSize = 3000

        // Short text: single pass
        if text.count <= chunkSize {
            return await summarizeChunk(text, category: category, container: container)
        }

        // Long text: chunk → summarize each → merge into final bullets
        let chunks = split(text, chunkSize: chunkSize)
        var allBullets: [String] = []
        for chunk in chunks.prefix(8) {  // cap at ~24k chars / ~4000 words
            if let bullets = await summarizeChunk(chunk, category: category, container: container) {
                allBullets.append(contentsOf: bullets)
            }
        }
        guard !allBullets.isEmpty else { return nil }

        // Merge pass: condense all chunk bullets into 5 final bullets
        let rawText = allBullets
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "• ")) }
            .joined(separator: ". ")
        return await mergeBullets(rawText, category: category, container: container)
            ?? Array(allBullets.prefix(5))
    }

    // MARK: - Private helpers

    private func summarizeChunk(_ text: String, category: MeetingCategory, container: ModelContainer) async -> [String]? {
        let system = "You are a meeting notes assistant. Summarize the transcript into 3-5 concise bullet points covering key topics, decisions, and action items. Output ONLY lines starting with \"• \", nothing else."
        let user = "Transcript (\(category.rawValue)):\n\(text)\n\nBullet points:"
        return await generateBullets(system: system, user: user, container: container, maxTokens: 300)
    }

    private func mergeBullets(_ bullets: String, category: MeetingCategory, container: ModelContainer) async -> [String]? {
        let system = "You are a meeting notes assistant. Condense these bullet points into exactly 5 final bullets, removing duplicates and keeping the most important information. Output ONLY lines starting with \"• \", nothing else."
        let user = "Bullets from a \(category.rawValue):\n\(bullets)\n\nFinal 5 bullet points:"
        return await generateBullets(system: system, user: user, container: container, maxTokens: 400)
    }

    private func generateBullets(system: String, user: String, container: ModelContainer, maxTokens: Int) async -> [String]? {
        do {
            let lmInput = try await container.prepare(
                input: UserInput(chat: [.system(system), .user(user)])
            )
            var fullOutput = ""
            let params = GenerateParameters(maxTokens: maxTokens, temperature: 0.3)
            let stream = try await container.generate(input: lmInput, parameters: params)
            for await generation in stream {
                switch generation {
                case .chunk(let text): fullOutput += text
                default: break
                }
            }
            let bullets = fullOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("•") || $0.hasPrefix("-") }
                .prefix(7)
                .map { line -> String in
                    let stripped = line.drop(while: { $0 == "•" || $0 == "-" || $0 == " " })
                    return "• " + stripped
                }
            guard !bullets.isEmpty else { return nil }
            return Array(bullets)
        } catch {
            return nil
        }
    }

    private func split(_ text: String, chunkSize: Int) -> [String] {
        var chunks: [String] = []
        var remaining = text[...]
        while !remaining.isEmpty {
            if remaining.count <= chunkSize {
                chunks.append(String(remaining))
                break
            }
            let end = remaining.index(remaining.startIndex, offsetBy: chunkSize)
            // Prefer breaking at a sentence boundary
            if let dot = remaining[..<end].lastIndex(of: ".") {
                let after = remaining.index(after: dot)
                chunks.append(String(remaining[..<after]))
                remaining = remaining[after...].drop(while: { $0 == " " })
            } else if let space = remaining[..<end].lastIndex(of: " ") {
                chunks.append(String(remaining[..<space]))
                remaining = remaining[remaining.index(after: space)...]
            } else {
                chunks.append(String(remaining[..<end]))
                remaining = remaining[end...]
            }
        }
        return chunks
    }
}
