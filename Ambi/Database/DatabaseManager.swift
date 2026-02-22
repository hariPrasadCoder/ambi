import Foundation
import GRDB

class DatabaseManager {
    private let dbQueue: DatabaseQueue
    
    init() throws {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupportURL.appendingPathComponent("Ambi", isDirectory: true)
        
        // Create directory if needed
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        let dbPath = appDirectory.appendingPathComponent("ambi.db").path
        dbQueue = try DatabaseQueue(path: dbPath)
        
        try migrator.migrate(dbQueue)
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            // Sessions table
            try db.create(table: "sessions", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("transcriptionCount", .integer).notNull().defaults(to: 0)
            }
            
            // Transcriptions table
            try db.create(table: "transcriptions", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .integer).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("duration", .integer).notNull()
            }
            
            // Indexes for faster queries
            try db.create(index: "idx_transcriptions_session", on: "transcriptions", columns: ["sessionId"])
            try db.create(index: "idx_sessions_date", on: "sessions", columns: ["date"])
        }
        
        migrator.registerMigration("v2_fts") { db in
            // Full-text search for transcriptions
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS transcriptions_fts
                USING fts5(text, content='transcriptions', content_rowid='id')
            """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS transcriptions_ai AFTER INSERT ON transcriptions BEGIN
                    INSERT INTO transcriptions_fts(rowid, text) VALUES (new.id, new.text);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS transcriptions_ad AFTER DELETE ON transcriptions BEGIN
                    INSERT INTO transcriptions_fts(transcriptions_fts, rowid, text) VALUES('delete', old.id, old.text);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS transcriptions_au AFTER UPDATE ON transcriptions BEGIN
                    INSERT INTO transcriptions_fts(transcriptions_fts, rowid, text) VALUES('delete', old.id, old.text);
                    INSERT INTO transcriptions_fts(rowid, text) VALUES (new.id, new.text);
                END
            """)
        }

        migrator.registerMigration("v3_source_app") { db in
            try db.alter(table: "transcriptions") { t in
                t.add(column: "sourceApp", .text)
            }
        }

        migrator.registerMigration("v4_dictionary") { db in
            try db.create(table: "dictionary_entries", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("original", .text).notNull().unique()
                t.column("replacement", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        return migrator
    }
    
    // MARK: - Session Operations
    
    func getOrCreateTodaySession() throws -> Session {
        try dbQueue.write { db in
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
            
            if let existing = try Session
                .filter(Column("date") >= today && Column("date") < tomorrow)
                .fetchOne(db) {
                return existing
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            
            var session = Session(
                title: formatter.string(from: Date()),
                date: Date(),
                transcriptionCount: 0
            )

            try session.insert(db)
            // Fetch the session back to get the auto-generated ID
            let id = db.lastInsertedRowID
            session.id = id
            return session
        }
    }
    
    func fetchSession(id: Int64) throws -> Session? {
        try dbQueue.read { db in
            try Session.fetchOne(db, key: id)
        }
    }
    
    func fetchAllSessions() throws -> [Session] {
        try dbQueue.read { db in
            try Session.order(Column("date").desc).fetchAll(db)
        }
    }
    
    func deleteSession(_ id: Int64) throws {
        try dbQueue.write { db in
            _ = try Session.deleteOne(db, key: id)
        }
    }
    
    func updateSessionTranscriptionCount(_ sessionId: Int64) throws {
        try dbQueue.write { db in
            let count = try Transcription
                .filter(Column("sessionId") == sessionId)
                .fetchCount(db)
            
            try db.execute(
                sql: "UPDATE sessions SET transcriptionCount = ? WHERE id = ?",
                arguments: [count, sessionId]
            )
        }
    }
    
    func searchSessions(query: String) throws -> [Session] {
        try dbQueue.read { db in
            // Find session IDs that have matching transcriptions
            let sessionIds = try Int64.fetchAll(db, sql: """
                SELECT DISTINCT t.sessionId 
                FROM transcriptions t
                JOIN transcriptions_fts fts ON t.id = fts.rowid
                WHERE transcriptions_fts MATCH ?
            """, arguments: [query + "*"])
            
            return try Session
                .filter(sessionIds.contains(Column("id")))
                .order(Column("date").desc)
                .fetchAll(db)
        }
    }
    
    // MARK: - Transcription Operations
    
    func insertTranscription(_ transcription: Transcription) throws {
        try dbQueue.write { db in
            try transcription.insert(db)
            
            // Update session count
            let count = try Transcription
                .filter(Column("sessionId") == transcription.sessionId)
                .fetchCount(db)
            
            try db.execute(
                sql: "UPDATE sessions SET transcriptionCount = ? WHERE id = ?",
                arguments: [count, transcription.sessionId]
            )
        }
    }
    
    func fetchTranscriptions(forSession sessionId: Int64) throws -> [Transcription] {
        try dbQueue.read { db in
            try Transcription
                .filter(Column("sessionId") == sessionId)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }
    
    func getTotalTranscriptionCount() throws -> Int {
        try dbQueue.read { db in
            try Transcription.fetchCount(db)
        }
    }
    
    func searchTranscriptions(query: String) throws -> [Transcription] {
        try dbQueue.read { db in
            try Transcription.fetchAll(db, sql: """
                SELECT t.*
                FROM transcriptions t
                JOIN transcriptions_fts fts ON t.id = fts.rowid
                WHERE transcriptions_fts MATCH ?
                ORDER BY t.timestamp DESC
            """, arguments: [query + "*"])
        }
    }

    // MARK: - Dictionary Operations

    func fetchDictionaryEntries() throws -> [DictionaryEntry] {
        try dbQueue.read { db in
            try DictionaryEntry.order(Column("createdAt").asc).fetchAll(db)
        }
    }

    func insertDictionaryEntry(_ entry: DictionaryEntry) throws {
        try dbQueue.write { db in
            try entry.insert(db)
        }
    }

    func deleteDictionaryEntry(_ id: Int64) throws {
        try dbQueue.write { db in
            _ = try DictionaryEntry.deleteOne(db, key: id)
        }
    }

    func fetchDictionaryMap() throws -> [String: String] {
        try dbQueue.read { db in
            let entries = try DictionaryEntry.fetchAll(db)
            return Dictionary(uniqueKeysWithValues: entries.map { ($0.original, $0.replacement) })
        }
    }

    // MARK: - Metrics Queries

    func fetchWordCountByDay(lastDays: Int) throws -> [(date: String, words: Int)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT substr(timestamp, 1, 10) as date,
                       SUM(LENGTH(text) - LENGTH(REPLACE(text, ' ', '')) + 1) as words
                FROM transcriptions
                WHERE substr(timestamp, 1, 10) >= date('now', '-\(lastDays - 1) days')
                GROUP BY date
                ORDER BY date
            """)
            return rows.compactMap { row in
                guard let date = row["date"] as String?,
                      let words = row["words"] as Int? else { return nil }
                return (date: date, words: words)
            }
        }
    }

    func fetchWordCountByHour() throws -> [Int: Int] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT CAST(substr(timestamp, 12, 2) AS INTEGER) as hour,
                       SUM(LENGTH(text) - LENGTH(REPLACE(text, ' ', '')) + 1) as words
                FROM transcriptions
                GROUP BY hour
            """)
            var result: [Int: Int] = [:]
            for row in rows {
                if let hour = row["hour"] as Int?,
                   let words = row["words"] as Int? {
                    result[hour] = words
                }
            }
            return result
        }
    }

    func fetchSessionDatesWithContent() throws -> [Date] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT substr(s.date, 1, 10) as session_date
                FROM sessions s
                JOIN transcriptions t ON s.id = t.sessionId
                ORDER BY session_date DESC
            """)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return rows.compactMap { row in
                guard let dateStr = row["session_date"] as String? else { return nil }
                return formatter.date(from: dateStr)
            }
        }
    }

    func fetchTotalWordCount() throws -> Int {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT SUM(LENGTH(text) - LENGTH(REPLACE(text, ' ', '')) + 1) as total
                FROM transcriptions
            """)
            return row?["total"] as Int? ?? 0
        }
    }
}
