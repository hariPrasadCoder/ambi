import Foundation
import GRDB

struct Transcription: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var sessionId: Int64
    var text: String
    var timestamp: Date
    var duration: Int // duration in seconds
    
    static let databaseTableName = "transcriptions"
    
    static let session = belongsTo(Session.self)
    
    init(id: Int64? = nil, sessionId: Int64, text: String, timestamp: Date = Date(), duration: Int = 0) {
        self.id = id
        self.sessionId = sessionId
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Transcription {
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
