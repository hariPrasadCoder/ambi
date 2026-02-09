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
            var t = transcription
            try t.insert(db)
            
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
}
