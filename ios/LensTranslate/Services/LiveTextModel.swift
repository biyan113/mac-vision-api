import CoreGraphics
import Foundation
import LensCore

/// 学词模式里被高亮的一个单词
struct Highlight: Identifiable, Equatable {
    let id = UUID()
    let entry: VocabEntry
    /// 归一化坐标，原点在左下角
    let box: CGRect
    /// 所在的那一行文字
    let sentence: String

    static func == (lhs: Highlight, rhs: Highlight) -> Bool {
        lhs.entry == rhs.entry && lhs.box == rhs.box
    }
}

/// 相机画面上实时识别出的文字
@MainActor
final class LiveTextModel: ObservableObject {
    @Published private(set) var lines: [RecognizedLine] = []
    @Published private(set) var highlights: [Highlight] = []
    @Published private(set) var imageSize: CGSize = .zero
    @Published var frozen = false { didSet { syncConfig() } }

    let pipeline = RecognitionPipeline()

    private var languages: [String] = []
    private var wordBoxes = false
    private var active = true
    private var resolver: ((String) -> VocabEntry?)?
    private var resolved: [String: VocabEntry?] = [:]

    init() {
        pipeline.onResult = { [weak self] lines, size in
            self?.update(lines: lines, imageSize: size)
        }
    }

    /// 切换识别方式。`resolver` 不为空时进入学词模式：只高亮它能查到的单词。
    func configure(languages: [String], resolver: ((String) -> VocabEntry?)?) {
        self.languages = languages
        self.wordBoxes = resolver != nil
        self.resolver = resolver
        resolved = [:]
        lines = []
        highlights = []
        syncConfig()
    }

    func setActive(_ active: Bool) {
        self.active = active
        if !active {
            lines = []
            highlights = []
        }
        syncConfig()
    }

    private func syncConfig() {
        pipeline.config = RecognitionPipeline.Config(languages: languages, wordBoxes: wordBoxes, paused: frozen || !active)
    }

    private func update(lines: [RecognizedLine], imageSize: CGSize) {
        self.imageSize = imageSize
        self.lines = lines

        guard let resolver else {
            highlights = []
            return
        }
        var found: [Highlight] = []
        var seen: Set<Int> = []
        for line in lines {
            for word in line.words {
                let key = word.text.lowercased()
                let entry: VocabEntry?
                if let cached = resolved[key] {
                    entry = cached
                } else {
                    entry = resolver(word.text)
                    resolved[key] = entry
                }
                // 同一个词在画面里出现多次时只标一次
                if let entry, seen.insert(entry.id).inserted {
                    found.append(Highlight(entry: entry, box: word.box, sentence: line.text))
                }
            }
        }
        highlights = found
    }
}
