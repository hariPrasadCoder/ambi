import Foundation
import GRDB

struct Transcription: Identifiable, Codable, FetchableRecord, PersistableRecord, Equatable {
    var id: Int64?
    var sessionId: Int64
    var text: String
    var timestamp: Date
    var duration: Int
    var sourceApp: String?
    
    static var databaseTableName: String { "transcriptions" }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
