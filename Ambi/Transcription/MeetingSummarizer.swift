import Foundation

// MARK: - Summarization Mode

enum SummarizationMode: String, CaseIterable, Identifiable {
    case localLLM = "Local AI"
    var id: String { rawValue }
}

// MARK: - Actor

actor MeetingSummarizer {

    // MARK: - Cache

    private static let cacheKey   = "meetingSummaryCache"
    private static let cacheLimit  = 100
    private var mem: [String: [String]] = [:]

    init() {
        if let stored = UserDefaults.standard.dictionary(forKey: Self.cacheKey)
            as? [String: [String]] {
            mem = stored
        }
    }

    // MARK: - Public API

    func summarize(meeting: Meeting, mode: SummarizationMode) async -> [String] {
        let key = cacheKey(for: meeting)
        if let cached = mem[key] { return cached }
        if let bullets = await generate(text: meeting.fullText, category: meeting.category, mode: mode) {
            persist(bullets, key: key)
            return bullets
        }
        // Model not ready — don't cache so the next attempt hits the LLM
        return ["• Model is loading, please wait a moment and tap Regenerate."]
    }

    func regenerate(meeting: Meeting, mode: SummarizationMode) async -> [String] {
        mem.removeValue(forKey: cacheKey(for: meeting))
        return await summarize(meeting: meeting, mode: mode)
    }

    private func cacheKey(for meeting: Meeting) -> String {
        "\(meeting.id)-\(meeting.transcriptions.count)"
    }

    // MARK: - Generation

    private func generate(text: String, category: MeetingCategory, mode: SummarizationMode) async -> [String]? {
        return await LocalLLMManager.shared.summarize(text: text, category: category)
    }

    // MARK: - Cache

    private func persist(_ bullets: [String], key: String) {
        mem[key] = bullets
        if mem.count > Self.cacheLimit {
            let over = mem.count - Self.cacheLimit
            mem.keys.prefix(over).forEach { mem.removeValue(forKey: $0) }
        }
        UserDefaults.standard.set(mem, forKey: Self.cacheKey)
    }
}
