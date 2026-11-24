import Foundation
import SQLite3

public struct VocabEntry: Equatable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let word: String
    public let phoneticUK: String
    public let phoneticUS: String
    public let definition: String

    public init(id: Int, word: String, phoneticUK: String, phoneticUS: String, definition: String) {
        self.id = id
        self.word = word
        self.phoneticUK = phoneticUK
        self.phoneticUS = phoneticUS
        self.definition = definition
    }

    /// 优先显示的音标
    public var phonetic: String { phoneticUK.isEmpty ? phoneticUS : phoneticUK }
}

public struct VocabBook: Equatable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let category: String
    public let name: String
    public let wordCount: Int

    public init(id: Int, category: String, name: String, wordCount: Int) {
        self.id = id
        self.category = category
        self.name = name
        self.wordCount = wordCount
    }
}

public enum VocabError: Error, LocalizedError {
    case cannotOpen(String)
    case invalidDatabase(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let message): return "无法打开词库：\(message)"
        case .invalidDatabase(let message): return "词库格式不正确：\(message)"
        }
    }
}

/// 只读访问由 `tools/vocab/build_vocab.py` 生成的词库数据库。
public final class VocabStore: @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            sqlite3_close(handle)
            throw VocabError.cannotOpen(message)
        }
        database = handle

        // 校验必需的表是否存在
        let tables = try queryStrings("SELECT name FROM sqlite_master WHERE type = 'table'")
        for required in ["words", "books", "book_words"] where !tables.contains(required) {
            sqlite3_close(handle)
            database = nil
            throw VocabError.invalidDatabase("缺少表 \(required)")
        }
    }

    deinit {
        sqlite3_close(database)
    }

    // MARK: - 查询

    public func wordCount() throws -> Int {
        try queryInt("SELECT COUNT(*) FROM words")
    }

    public func books() throws -> [VocabBook] {
        try withStatement("SELECT id, category, name, word_count FROM books ORDER BY category, name") { statement in
            var result: [VocabBook] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(VocabBook(
                    id: Int(sqlite3_column_int64(statement, 0)),
                    category: Self.text(statement, 1),
                    name: Self.text(statement, 2),
                    wordCount: Int(sqlite3_column_int64(statement, 3))
                ))
            }
            return result
        }
    }

    /// 按原样（不区分大小写）查找一个单词。`bookID` 不为空时只在该词书内查找。
    public func lookup(_ word: String, bookID: Int? = nil) throws -> VocabEntry? {
        let sql: String
        if bookID != nil {
            sql = """
            SELECT w.id, w.word, w.phonetic_uk, w.phonetic_us, w.definition
            FROM words w JOIN book_words bw ON bw.word_id = w.id
            WHERE w.word = ?1 COLLATE NOCASE AND bw.book_id = ?2 LIMIT 1
            """
        } else {
            sql = "SELECT id, word, phonetic_uk, phonetic_us, definition FROM words WHERE word = ?1 COLLATE NOCASE LIMIT 1"
        }
        return try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, word, -1, Self.transient)
            if let bookID { sqlite3_bind_int64(statement, 2, Int64(bookID)) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return VocabEntry(
                id: Int(sqlite3_column_int64(statement, 0)),
                word: Self.text(statement, 1),
                phoneticUK: Self.text(statement, 2),
                phoneticUS: Self.text(statement, 3),
                definition: Self.text(statement, 4)
            )
        }
    }

    /// 查找句子里出现的一个词：依次尝试它的各种词形还原结果。
    public func entry(matching token: String, bookID: Int? = nil) throws -> VocabEntry? {
        for candidate in Lemmatizer.candidates(for: token) {
            if let entry = try lookup(candidate, bookID: bookID) { return entry }
        }
        return nil
    }

    /// 收录该单词的词书分类（去重），按分类名排序
    public func categories(forWordID id: Int) throws -> [String] {
        let sql = """
        SELECT DISTINCT b.category FROM book_words bw JOIN books b ON b.id = bw.book_id
        WHERE bw.word_id = ?1 ORDER BY b.category
        """
        return try withStatement(sql) { statement in
            sqlite3_bind_int64(statement, 1, Int64(id))
            var result: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW { result.append(Self.text(statement, 0)) }
            return result
        }
    }

    // MARK: - 内部

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VocabError.invalidDatabase(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func queryInt(_ sql: String) throws -> Int {
        try withStatement(sql) { statement in
            sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
    }

    private func queryStrings(_ sql: String) throws -> [String] {
        try withStatement(sql) { statement in
            var result: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW { result.append(Self.text(statement, 0)) }
            return result
        }
    }
}
