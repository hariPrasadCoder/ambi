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

    static let `default` = all[1]  // Qwen 1.5B
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
    private var unloadTask: Task<Void, Never>?

    private init() {
        let savedId = UserDefaults.standard.string(forKey: "selectedSummaryModel") ?? ""
        // Migrate: SmolLM (old default) → Qwen 1.5B
        let smolLMId = SummaryModel.all[0].id
        let resolvedId = savedId == smolLMId ? SummaryModel.default.id : savedId
        selectedModel = SummaryModel.all.first { $0.id == resolvedId } ?? .default
        if resolvedId != savedId {
            UserDefaults.standard.set(selectedModel.id, forKey: "selectedSummaryModel")
        }
    }

    // MARK: - Public API

    /// Download (if needed) and load the selected model into memory.
    func loadModel() async {
        guard !loadState.isBusy else { return }
        loadState = .downloading(progress: 0)
        do {
            let result = try await LLMModelFactory.shared.loadContainer(
                configuration: selectedModel.modelConfiguration
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
        unloadTask?.cancel()
        selectedModel = model
        container = nil
        loadState = .idle
        UserDefaults.standard.set(model.id, forKey: "selectedSummaryModel")
    }

    /// Loads model on demand, summarizes, then schedules unload after 30 s of inactivity.
    func summarize(text: String, category: MeetingCategory) async -> [String]? {
        // Cancel any pending unload — we need the model to stay alive
        unloadTask?.cancel()
        unloadTask = nil

        // Load from disk if not already in memory
        if !loadState.isReady {
            await loadModel()
            guard loadState.isReady else { return nil }
        }
        guard let container else { return nil }

        let result = await runSummarization(text: text, category: category, container: container)

        // Free RAM 30 s after the last summarization call
        scheduleUnload()
        return result
    }

    // MARK: - Unload

    private func scheduleUnload() {
        unloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            self?.container = nil
            self?.loadState = .idle
        }
    }

    // MARK: - Chunked summarization

    private func runSummarization(text: String, category: MeetingCategory, container: ModelContainer) async -> [String]? {
        let chunkSize = 3000
        if text.count <= chunkSize {
            return await summarizeChunk(text, category: category, container: container)
        }
        let chunks = split(text, chunkSize: chunkSize)
        var allBullets: [String] = []
        for chunk in chunks.prefix(8) {
            if let bullets = await summarizeChunk(chunk, category: category, container: container) {
                allBullets.append(contentsOf: bullets)
            }
        }
        guard !allBullets.isEmpty else { return nil }
        let rawText = allBullets
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "• ")) }
            .joined(separator: ". ")
        return await mergeBullets(rawText, category: category, container: container)
            ?? Array(allBullets.prefix(5))
    }

    // MARK: - Private helpers

    private func summarizeChunk(_ text: String, category: MeetingCategory, container: ModelContainer) async -> [String]? {
        let system = """
        You are a note-taker for a \(category.rawValue.lowercased()). \
        The transcript is from a voice recording of one or more people in conversation. \
        Write 3-5 concise bullet points capturing what was discussed, decided, or needs follow-up. \
        Rules: write in active voice ("Discussed X", "Decided to Y", "Need to Z"), \
        be specific and direct, no repetition, never write "The user said" or refer to people in third person. \
        Output ONLY bullet lines starting with "• ", nothing else.
        """
        let user = "Transcript:\n\(text)\n\nMeeting notes:"
        return await generateBullets(system: system, user: user, container: container, maxTokens: 350)
    }

    private func mergeBullets(_ bullets: String, category: MeetingCategory, container: ModelContainer) async -> [String]? {
        let system = """
        Condense these meeting notes into 5 final bullet points. \
        Remove duplicates and near-duplicates. Keep the most specific and actionable points. \
        Use active voice. Output ONLY bullet lines starting with "• ", nothing else.
        """
        let user = "Notes to condense:\n\(bullets)\n\nFinal 5 bullet points:"
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
