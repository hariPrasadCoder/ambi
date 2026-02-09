import Foundation
import GRDB

struct Session: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var title: String?
    var date: Date
    var createdAt: Date
    var updatedAt: Date
    
    static let databaseTableName = "sessions"
    
    static let transcriptions = hasMany(Transcription.self)
    
    var transcriptionsRequest: QueryInterfaceRequest<Transcription> {
        request(for: Session.transcriptions)
    }
    
    init(id: Int64? = nil, title: String? = nil, date: Date = Date(), createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Session {
    var displayTitle: String {
        title ?? formattedDate
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
