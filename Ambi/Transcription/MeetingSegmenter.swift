import Foundation

enum MeetingSegmenter {

    private static let hardGap: TimeInterval = 30 * 60  // 30 min always splits
    private static let softGap: TimeInterval =  5 * 60  // 5 min + app change splits

    /// Groups transcriptions into logical meetings using gap + app-change heuristics.
    /// Returns meetings ordered newest-first.
    static func segment(_ transcriptions: [Transcription]) -> [Meeting] {
        guard !transcriptions.isEmpty else { return [] }

        let sorted = transcriptions.sorted { $0.timestamp < $1.timestamp }
        var groups: [[Transcription]] = []
        var current: [Transcription] = [sorted[0]]

        for i in 1 ..< sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let gap  = curr.timestamp.timeIntervalSince(prev.timestamp)

            let splits: Bool
            if gap > hardGap {
                splits = true
            } else if gap > softGap {
                // Medium gap — only split if the foreground app changed
                splits = appChanged(prev.sourceApp, curr.sourceApp)
            } else {
                splits = false
            }

            if splits {
                groups.append(current)
                current = [curr]
            } else {
                current.append(curr)
            }
        }
        groups.append(current)

        return groups.compactMap(makeMeeting).reversed()  // newest first
    }

    // MARK: - Helpers

    private static func appChanged(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil):         return false
        case (nil, _), (_, nil): return true
        default:                 return a != b
        }
    }

    private static func makeMeeting(from group: [Transcription]) -> Meeting? {
        guard let first = group.first, let last = group.last else { return nil }
        let dominant = group.compactMap(\.sourceApp)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key
        let category = MeetingCategory.from(sourceApp: dominant)
        let meetingId = first.id.map { String($0) } ?? UUID().uuidString
        return Meeting(
            id: meetingId,
            transcriptions: group,
            category: category,
            startTime: first.timestamp,
            endTime: last.timestamp.addingTimeInterval(TimeInterval(last.duration))
        )
    }
}
