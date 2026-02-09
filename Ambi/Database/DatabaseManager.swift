import Foundation
import GRDB

final class DatabaseManager {
    private let dbQueue: DatabaseQueue
    
    init() throws {
        // Get app support directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ambiDir = appSupport.appendingPathComponent("Ambi", isDirectory: true)
        
        // Create directory if needed
        try fileManager.createDirectory(at: ambiDir, withIntermediateDirectories: true)
        
        let dbPath = ambiDir.appendingPathComponent("ambi.sqlite").path
        dbQueue = try DatabaseQueue(path: dbPath)
        
        try migrator.migrate(dbQueue)
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: "sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text)
                t.column("date", .datetime).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            try db.create(table: "transcriptions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .integer)
                    .notNull()
                    .indexed()
                    .references("sessions", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("duration", .integer).notNull().defaults(to: 0)
            }
            
            // Full-text search for transcriptions
            try db.create(virtualTable: "transcriptions_fts", using: FTS5()) { t in
                t.content = "transcriptions"
                t.column("text")
            }
            
            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER transcriptions_ai AFTER INSERT ON transcriptions BEGIN
                    INSERT INTO transcriptions_fts(rowid, text) VALUES (new.id, new.text);
                END;
            """)
            
            try db.execute(sql: """
                CREATE TRIGGER transcriptions_ad AFTER DELETE ON transcriptions BEGIN
                    INSERT INTO transcriptions_fts(transcriptions_fts, rowid, text) VALUES('delete', old.id, old.text);
                END;
            """)
            
            try db.execute(sql: """
                CREATE TRIGGER transcriptions_au AFTER UPDATE ON transcriptions BEGIN
                    INSERT INTO transcriptions_fts(transcriptions_fts, rowid, text) VALUES('delete', old.id, old.text);
                    INSERT INTO transcriptions_fts(rowid, text) VALUES (new.id, new.text);
                END;
            """)
        }
        
        return migrator
    }
    
    // MARK: - Sessions
    
    func fetchAllSessions() throws -> [Session] {
        try dbQueue.read { db in
            try Session.order(Column("date").desc).fetchAll(db)
        }
    }
    
    func fetchSession(id: Int64) throws -> Session? {
        try dbQueue.read { db in
            try Session.fetchOne(db, key: id)
        }
    }
    
    func getTodaySession() throws -> Session? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        
        return try dbQueue.read { db in
            try Session
                .filter(Column("date") >= startOfDay)
                .fetchOne(db)
        }
    }
    
    func getOrCreateTodaySession() throws -> Session {
        if let existing = try getTodaySession() {
            return existing
        }
        
        var session = Session(date: Date())
        try dbQueue.write { db in
            try session.insert(db)
        }
        return session
    }
    
    func insertSession(_ session: inout Session) throws {
        try dbQueue.write { db in
            try session.insert(db)
        }
    }
    
    func updateSessionTitle(_ id: Int64, title: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sessions SET title = ?, updatedAt = ? WHERE id = ?",
                arguments: [title, Date(), id]
            )
        }
    }
    
    func deleteSession(_ id: Int64) throws {
        try dbQueue.write { db in
            _ = try Session.deleteOne(db, key: id)
        }
    }
    
    // MARK: - Transcriptions
    
    func fetchTranscriptions(forSession sessionId: Int64) throws -> [Transcription] {
        try dbQueue.read { db in
            try Transcription
                .filter(Column("sessionId") == sessionId)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }
    
    func insertTranscription(_ transcription: Transcription) throws {
        var t = transcription
        try dbQueue.write { db in
            try t.insert(db)
            
            // Update session's updatedAt
            try db.execute(
                sql: "UPDATE sessions SET updatedAt = ? WHERE id = ?",
                arguments: [Date(), transcription.sessionId]
            )
        }
    }
    
    func deleteTranscription(_ id: Int64) throws {
        try dbQueue.write { db in
            _ = try Transcription.deleteOne(db, key: id)
        }
    }
    
    // MARK: - Search
    
    func searchSessions(query: String) throws -> [Session] {
        try dbQueue.read { db in
            // Search in FTS table and join back to get sessions
            let sql = """
                SELECT DISTINCT s.*
                FROM sessions s
                INNER JOIN transcriptions t ON t.sessionId = s.id
                INNER JOIN transcriptions_fts fts ON fts.rowid = t.id
                WHERE transcriptions_fts MATCH ?
                ORDER BY s.date DESC
            """
            
            // Format query for FTS5
            let ftsQuery = query.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { "\($0)*" }
                .joined(separator: " ")
            
            return try Session.fetchAll(db, sql: sql, arguments: [ftsQuery])
        }
    }
    
    func searchTranscriptions(query: String) throws -> [Transcription] {
        try dbQueue.read { db in
            let sql = """
                SELECT t.*
                FROM transcriptions t
                INNER JOIN transcriptions_fts fts ON fts.rowid = t.id
                WHERE transcriptions_fts MATCH ?
                ORDER BY t.timestamp DESC
            """
            
            let ftsQuery = query.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { "\($0)*" }
                .joined(separator: " ")
            
            return try Transcription.fetchAll(db, sql: sql, arguments: [ftsQuery])
        }
    }
    
    // MARK: - Stats
    
    func getTotalTranscriptionCount() throws -> Int {
        try dbQueue.read { db in
            try Transcription.fetchCount(db)
        }
    }
    
    func getTotalDuration() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(duration), 0) FROM transcriptions") ?? 0
        }
    }
}
