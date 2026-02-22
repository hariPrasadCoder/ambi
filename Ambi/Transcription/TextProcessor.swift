import Foundation

struct TextProcessor {
    enum ProcessingType {
        case cleanUp
        case formatAsBullets
    }

    func process(_ text: String, type: ProcessingType) -> String {
        switch type {
        case .cleanUp:      return cleanUp(text)
        case .formatAsBullets: return formatAsBullets(text)
        }
    }

    // MARK: - Clean Up

    private func cleanUp(_ text: String) -> String {
        // Collapse multiple spaces
        var result = text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Capitalize sentence starts
        result = capitalizeSentences(result)

        // Ensure ends with punctuation
        if let last = result.last, !".,!?;:".contains(last), !result.isEmpty {
            result += "."
        }
        return result
    }

    // MARK: - Bullet Points

    private func formatAsBullets(_ text: String) -> String {
        let sentences = splitIntoSentences(text)
        return sentences
            .map { "• " + $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    // MARK: - Helpers

    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let pattern = "[^.!?]+[.!?]*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        for match in matches {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let sentence = String(text[swiftRange]).trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }

    private func capitalizeSentences(_ text: String) -> String {
        let sentences = splitIntoSentences(text)
        return sentences.map { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return trimmed }
            return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        }.joined(separator: " ")
    }
}
