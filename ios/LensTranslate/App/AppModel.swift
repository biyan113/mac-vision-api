import Foundation
import LensCore
import SwiftUI

/// 应用级状态：语言设置、词库和生词本
@MainActor
final class AppModel: ObservableObject {
    /// 源语言标识；空字符串表示自动检测
    @Published var sourceLanguageID: String { didSet { defaults.set(sourceLanguageID, forKey: Keys.source) } }
    @Published var targetLanguageID: String { didSet { defaults.set(targetLanguageID, forKey: Keys.target) } }
    @Published var autoSpeak: Bool { didSet { defaults.set(autoSpeak, forKey: Keys.autoSpeak) } }
    /// 学词模式高亮哪本词书；0 表示词库里的全部单词
    @Published var selectedBookID: Int { didSet { defaults.set(selectedBookID, forKey: Keys.book) } }

    @Published private(set) var vocab: VocabStore?
    @Published private(set) var books: [VocabBook] = []
    @Published private(set) var vocabWordCount = 0
    @Published private(set) var savedWords: [SavedWord] = []
    @Published var message: String?

    private let defaults = UserDefaults.standard
    private let wordbook: WordbookStore

    private enum Keys {
        static let source = "sourceLanguage"
        static let target = "targetLanguage"
        static let autoSpeak = "autoSpeak"
        static let book = "selectedBook"
    }

    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static var vocabURL: URL { supportDirectory.appendingPathComponent("vocab.sqlite") }

    init() {
        sourceLanguageID = defaults.string(forKey: Keys.source) ?? "en"
        targetLanguageID = defaults.string(forKey: Keys.target) ?? "zh-Hans"
        autoSpeak = defaults.object(forKey: Keys.autoSpeak) as? Bool ?? true
        selectedBookID = defaults.integer(forKey: Keys.book)
        wordbook = WordbookStore(fileURL: Self.supportDirectory.appendingPathComponent("wordbook.json"))
        savedWords = wordbook.words
        loadVocab()
    }

    // MARK: - 语言

    var sourceLanguage: LanguageOption? { LanguageOption.option(for: sourceLanguageID) }
    var targetLanguage: LanguageOption { LanguageOption.option(for: targetLanguageID) ?? LanguageOption.all[0] }
    var sourceName: String { sourceLanguage?.name ?? "自动检测" }

    func swapLanguages() {
        guard let source = sourceLanguage else { return }
        let target = targetLanguage
        sourceLanguageID = target.id
        targetLanguageID = source.id
    }

    // MARK: - 词库

    var selectedBook: VocabBook? { books.first { $0.id == selectedBookID } }

    private func loadVocab() {
        // 先找用户导入的词库，再找随 App 打包的
        let candidates = [Self.vocabURL.path, Bundle.main.path(forResource: "vocab", ofType: "sqlite")].compactMap { $0 }
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            do {
                let store = try VocabStore(path: path)
                vocab = store
                books = try store.books()
                vocabWordCount = try store.wordCount()
                if selectedBookID != 0, !books.contains(where: { $0.id == selectedBookID }) {
                    selectedBookID = 0
                }
                return
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// 导入用 tools/vocab/build_vocab.py 生成的词库文件
    func importVocab(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            // 先校验再替换，避免坏文件覆盖掉可用的词库
            _ = try VocabStore(path: url.path)
            let destination = Self.vocabURL
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            vocab = nil
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            loadVocab()
            message = "词库已导入，共 \(vocabWordCount) 个词条"
        } catch {
            message = error.localizedDescription
            loadVocab()
        }
    }

    // MARK: - 生词本

    func isSaved(_ word: String) -> Bool {
        savedWords.contains { $0.id == word.lowercased() }
    }

    func toggleSaved(_ entry: VocabEntry, sentence: String, source: SavedWord.Source) {
        do {
            if wordbook.contains(entry.word) {
                try wordbook.remove(entry.word)
            } else {
                try wordbook.add(SavedWord(
                    word: entry.word, phonetic: entry.phonetic, definition: entry.definition,
                    sentence: sentence, source: source
                ))
            }
            savedWords = wordbook.words
        } catch {
            message = error.localizedDescription
        }
    }

    func removeSaved(_ word: String) {
        do {
            try wordbook.remove(word)
            savedWords = wordbook.words
        } catch {
            message = error.localizedDescription
        }
    }

    func ankiExport() -> String { wordbook.ankiExport() }
}
