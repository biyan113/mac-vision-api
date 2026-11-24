import CoreGraphics
import SQLite3
import XCTest
@testable import LensCore

final class LensCoreTests: XCTestCase {
    // MARK: - 坐标换算

    func testViewRectFlipsVerticalAxis() {
        // 图像与视图同尺寸：左下角的归一化矩形应落在视图底部
        let rect = PreviewGeometry.viewRect(
            forNormalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.25),
            imageSize: CGSize(width: 400, height: 800),
            viewSize: CGSize(width: 400, height: 800)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 600, width: 200, height: 200))
    }

    func testViewRectAccountsForAspectFillCrop() {
        // 1000x1000 的图像填满 500x1000 的视图：放大 1 倍，左右各裁掉 250
        let rect = PreviewGeometry.viewRect(
            forNormalized: CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1),
            imageSize: CGSize(width: 1000, height: 1000),
            viewSize: CGSize(width: 500, height: 1000)
        )
        XCTAssertEqual(rect.minX, 250, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 400, accuracy: 0.001)
        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.height, 100, accuracy: 0.001)
    }

    func testViewRectHandlesEmptySizes() {
        XCTAssertEqual(PreviewGeometry.viewRect(forNormalized: .zero, imageSize: .zero, viewSize: .zero), .zero)
    }

    func testDistanceFromCenter() {
        let size = CGSize(width: 200, height: 200)
        XCTAssertEqual(PreviewGeometry.distanceFromCenter(CGRect(x: 90, y: 90, width: 20, height: 20), in: size), 0, accuracy: 0.001)
        XCTAssertEqual(PreviewGeometry.distanceFromCenter(CGRect(x: 130, y: 60, width: 0, height: 0), in: size), 50, accuracy: 0.001)
    }

    // MARK: - 词形还原

    func testLemmatizerCandidates() {
        XCTAssertEqual(Lemmatizer.candidates(for: "Passengers").first, "passengers")
        XCTAssertTrue(Lemmatizer.candidates(for: "Passengers").contains("passenger"))
        XCTAssertTrue(Lemmatizer.candidates(for: "studies").contains("study"))
        XCTAssertTrue(Lemmatizer.candidates(for: "boxes").contains("box"))
        XCTAssertTrue(Lemmatizer.candidates(for: "making").contains("make"))
        XCTAssertTrue(Lemmatizer.candidates(for: "running").contains("run"))
        XCTAssertTrue(Lemmatizer.candidates(for: "retained").contains("retain"))
        XCTAssertTrue(Lemmatizer.candidates(for: "declared").contains("declare"))
        XCTAssertTrue(Lemmatizer.candidates(for: "stopped").contains("stop"))
        XCTAssertTrue(Lemmatizer.candidates(for: "airline's").contains("airline"))
        XCTAssertTrue(Lemmatizer.candidates(for: "quickly").contains("quick"))
        XCTAssertTrue(Lemmatizer.candidates(for: "\"departure.\"").contains("departure"))
    }

    func testLemmatizerIgnoresNonWords() {
        XCTAssertEqual(Lemmatizer.candidates(for: "8.50"), [])
        XCTAssertEqual(Lemmatizer.candidates(for: ""), [])
        // 不把 ss 结尾当复数
        XCTAssertFalse(Lemmatizer.candidates(for: "pass").contains("pas"))
    }

    func testWordsInText() {
        let text = "Passengers must retain their boarding pass until 10:30."
        let words = Lemmatizer.words(in: text)
        XCTAssertEqual(words.map(\.word), ["Passengers", "must", "retain", "their", "boarding", "pass", "until"])
        XCTAssertEqual(String(text[words[2].range]), "retain")
    }

    // MARK: - 词库

    private func makeDatabase() throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("lenscore-\(UUID().uuidString).sqlite").path
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TABLE words (id INTEGER PRIMARY KEY, word TEXT NOT NULL UNIQUE COLLATE NOCASE,
            phonetic_uk TEXT NOT NULL DEFAULT '', phonetic_us TEXT NOT NULL DEFAULT '', definition TEXT NOT NULL DEFAULT '');
        CREATE TABLE books (id INTEGER PRIMARY KEY, category TEXT NOT NULL, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, word_count INTEGER NOT NULL);
        CREATE TABLE book_words (book_id INTEGER NOT NULL, word_id INTEGER NOT NULL, PRIMARY KEY (book_id, word_id)) WITHOUT ROWID;
        INSERT INTO words VALUES (1, 'retain', '[rɪˈteɪn]', '[rɪˈteɪn]', 'vt. 保持；雇；记住');
        INSERT INTO words VALUES (2, 'departure', '[dɪˈpɑːtʃə(r)]', '[dɪˈpɑːrtʃər]', 'n. 离开；出发；违背');
        INSERT INTO words VALUES (3, 'passenger', '', '[ˈpæsɪndʒər]', 'n. 旅客；乘客');
        INSERT INTO books VALUES (1, '雅思', '雅思词汇', '7.雅思/a.xlsx', 2);
        INSERT INTO books VALUES (2, '四级', '四级词汇', '3.四级/b.xlsx', 2);
        INSERT INTO book_words VALUES (1, 1), (1, 2), (2, 1), (2, 3);
        """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        return path
    }

    func testVocabLookup() throws {
        let store = try VocabStore(path: try makeDatabase())
        XCTAssertEqual(try store.wordCount(), 3)

        let entry = try XCTUnwrap(try store.lookup("Retain"))
        XCTAssertEqual(entry.word, "retain")
        XCTAssertEqual(entry.definition, "vt. 保持；雇；记住")
        XCTAssertEqual(entry.phonetic, "[rɪˈteɪn]")

        XCTAssertNil(try store.lookup("unknown"))
        // 英式音标为空时回退到美式
        XCTAssertEqual(try store.lookup("passenger")?.phonetic, "[ˈpæsɪndʒər]")
    }

    func testVocabLookupWithinBook() throws {
        let store = try VocabStore(path: try makeDatabase())
        XCTAssertNotNil(try store.lookup("departure", bookID: 1))
        XCTAssertNil(try store.lookup("departure", bookID: 2))
        XCTAssertNil(try store.lookup("passenger", bookID: 1))
    }

    func testVocabEntryMatchingInflectedForms() throws {
        let store = try VocabStore(path: try makeDatabase())
        XCTAssertEqual(try store.entry(matching: "Passengers")?.word, "passenger")
        XCTAssertEqual(try store.entry(matching: "retained")?.word, "retain")
        XCTAssertEqual(try store.entry(matching: "departures,")?.word, "departure")
        XCTAssertNil(try store.entry(matching: "Passengers", bookID: 1))
        XCTAssertNil(try store.entry(matching: "the"))
    }

    func testVocabBooksAndCategories() throws {
        let store = try VocabStore(path: try makeDatabase())
        let books = try store.books()
        XCTAssertEqual(books.map(\.name), ["四级词汇", "雅思词汇"])
        XCTAssertEqual(books.first?.wordCount, 2)
        XCTAssertEqual(try store.categories(forWordID: 1), ["四级", "雅思"])
        XCTAssertEqual(try store.categories(forWordID: 2), ["雅思"])
    }

    func testVocabRejectsInvalidDatabase() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("lenscore-empty-\(UUID().uuidString).sqlite").path
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE other (id INTEGER)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        XCTAssertThrowsError(try VocabStore(path: path))
        XCTAssertThrowsError(try VocabStore(path: "/nonexistent/dir/vocab.sqlite"))
    }

    // MARK: - 生词本

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wordbook-\(UUID().uuidString)")
            .appendingPathComponent("wordbook.json")
    }

    func testWordbookAddRemoveAndPersist() throws {
        let url = temporaryFile()
        let store = WordbookStore(fileURL: url)
        XCTAssertTrue(store.words.isEmpty)

        let first = SavedWord(word: "retain", phonetic: "[rɪˈteɪn]", definition: "vt. 保持", sentence: "Passengers must retain their boarding pass.", source: .camera)
        XCTAssertTrue(try store.add(first))
        XCTAssertFalse(try store.add(SavedWord(word: "Retain", phonetic: "", definition: "", sentence: "", source: .voice)))
        XCTAssertTrue(try store.add(SavedWord(word: "luggage", phonetic: "", definition: "n. 行李", sentence: "", source: .voice)))

        XCTAssertEqual(store.words.map(\.word), ["luggage", "retain"])
        XCTAssertTrue(store.contains("RETAIN"))

        // 重新加载后内容一致
        let reloaded = WordbookStore(fileURL: url)
        XCTAssertEqual(reloaded.words.map(\.word), ["luggage", "retain"])
        XCTAssertEqual(reloaded.words.last?.source, .camera)

        try reloaded.remove("Luggage")
        XCTAssertEqual(WordbookStore(fileURL: url).words.map(\.word), ["retain"])
    }

    func testAnkiExport() throws {
        let store = WordbookStore(fileURL: temporaryFile())
        try store.add(SavedWord(word: "accord", phonetic: "[əˈkɔːd]", definition: "n. 符合\nvt. 使一致", sentence: "in\taccord", source: .camera))
        XCTAssertEqual(store.ankiExport(), "accord\t[əˈkɔːd]\tn. 符合<br>vt. 使一致\tin accord")
    }
}
