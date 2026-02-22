import Foundation
import GRDB

struct DictionaryEntry: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var original: String   // stored lowercased
    var replacement: String
    var createdAt: Date

    static var databaseTableName: String { "dictionary_entries" }
}
