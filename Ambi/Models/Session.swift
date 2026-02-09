import Foundation
import GRDB

struct Session: Identifiable, Codable, FetchableRecord, PersistableRecord, Equatable, Hashable {
    var id: Int64?
    var title: String
    var date: Date
    var transcriptionCount: Int
    
    static var databaseTableName: String { "sessions" }
    
    init(id: Int64? = nil, title: String, date: Date, transcriptionCount: Int = 0) {
        self.id = id
        self.title = title
        self.date = date
        self.transcriptionCount = transcriptionCount
    }
    
    // Display helpers
    var displayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return formattedDate
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}
