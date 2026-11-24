import Foundation

/// 生词本里的一条记录
public struct SavedWord: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case camera
        case voice
    }

    public var word: String
    public var phonetic: String
    public var definition: String
    /// 遇到它时的原句
    public var sentence: String
    public var source: Source
    public var addedAt: Date

    public var id: String { word.lowercased() }

    public init(word: String, phonetic: String, definition: String, sentence: String, source: Source, addedAt: Date = Date()) {
        self.word = word
        self.phonetic = phonetic
        self.definition = definition
        self.sentence = sentence
        self.source = source
        self.addedAt = addedAt
    }
}

/// 生词本：保存在一个 JSON 文件里，按加入时间倒序排列。
public final class WordbookStore {
    public private(set) var words: [SavedWord] = []
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            words = (try? decoder.decode([SavedWord].self, from: data)) ?? []
        }
    }

    public func contains(_ word: String) -> Bool {
        let key = word.lowercased()
        return words.contains { $0.id == key }
    }

    /// 加入一个单词。已存在时不重复添加，返回 false。
    @discardableResult
    public func add(_ entry: SavedWord) throws -> Bool {
        guard !contains(entry.word) else { return false }
        words.insert(entry, at: 0)
        try save()
        return true
    }

    public func remove(_ word: String) throws {
        let key = word.lowercased()
        words.removeAll { $0.id == key }
        try save()
    }

    /// 导出为 Anki 可直接导入的制表符分隔文本：单词、音标、释义、例句
    public func ankiExport() -> String {
        func field(_ value: String) -> String {
            value.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "<br>")
        }
        return words
            .map { [$0.word, $0.phonetic, $0.definition, $0.sentence].map(field).joined(separator: "\t") }
            .joined(separator: "\n")
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(words).write(to: fileURL, options: .atomic)
    }
}
