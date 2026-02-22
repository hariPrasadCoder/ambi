import Foundation

// MARK: - Meeting Category

enum MeetingCategory: String, CaseIterable {
    case videoMeeting  = "Video Meeting"
    case codingSession = "Coding Session"
    case research      = "Research"
    case session       = "Session"

    var sfSymbol: String {
        switch self {
        case .videoMeeting:  return "video.fill"
        case .codingSession: return "curlybraces"
        case .research:      return "globe"
        case .session:       return "waveform"
        }
    }

    static func from(sourceApp: String?) -> MeetingCategory {
        guard let app = sourceApp?.lowercased() else { return .session }
        if ["zoom", "teams", "meet", "webex", "skype", "facetime"]
            .contains(where: { app.contains($0) }) { return .videoMeeting }
        if ["xcode", "cursor", "code", "terminal", "iterm", "vim"]
            .contains(where: { app.contains($0) }) { return .codingSession }
        if ["safari", "chrome", "firefox", "arc", "brave"]
            .contains(where: { app.contains($0) }) { return .research }
        return .session
    }
}

// MARK: - Meeting

struct Meeting: Identifiable {
    let id: String               // first transcription's id, stringified
    let transcriptions: [Transcription]
    let category: MeetingCategory
    let startTime: Date
    let endTime: Date

    var title: String { category.rawValue }

    var durationSeconds: Int {
        transcriptions.reduce(0) { $0 + $1.duration }
    }

    var formattedDuration: String {
        let t = durationSeconds
        let h = t / 3600; let m = (t % 3600) / 60; let s = t % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    var dominantApp: String? {
        let apps = transcriptions.compactMap(\.sourceApp)
        guard !apps.isEmpty else { return nil }
        return apps.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key
    }

    var fullText: String {
        transcriptions.map(\.text).joined(separator: " ")
    }
}
