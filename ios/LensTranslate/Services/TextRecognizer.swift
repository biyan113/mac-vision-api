import CoreVideo
import Foundation
import LensCore
import Vision

struct RecognizedWord: Identifiable, Equatable {
    let id = UUID()
    let text: String
    /// 归一化坐标，原点在左下角
    let box: CGRect

    static func == (lhs: RecognizedWord, rhs: RecognizedWord) -> Bool {
        lhs.text == rhs.text && lhs.box == rhs.box
    }
}

struct RecognizedLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let box: CGRect
    let words: [RecognizedWord]

    static func == (lhs: RecognizedLine, rhs: RecognizedLine) -> Bool {
        lhs.text == rhs.text && lhs.box == rhs.box
    }
}

enum TextRecognizer {
    /// 识别一帧画面里的文字。
    /// - Parameters:
    ///   - languages: Vision 的语言标识；为空时自动检测
    ///   - wordBoxes: 是否同时计算每个单词的位置（学词模式需要）
    static func recognize(in buffer: CVPixelBuffer, languages: [String], wordBoxes: Bool) throws -> (lines: [RecognizedLine], imageSize: CGSize) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = languages
        }

        try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request])

        let lines: [RecognizedLine] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence > 0.3 else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            var words: [RecognizedWord] = []
            if wordBoxes {
                for item in Lemmatizer.words(in: candidate.string) {
                    if let box = try? candidate.boundingBox(for: item.range)?.boundingBox {
                        words.append(RecognizedWord(text: item.word, box: box))
                    }
                }
            }
            return RecognizedLine(text: text, box: observation.boundingBox, words: words)
        }

        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        return (lines, size)
    }
}

/// 在相机队列上运行识别，把结果送回主线程
final class RecognitionPipeline {
    struct Config {
        var languages: [String] = []
        var wordBoxes = false
        var paused = false
    }

    private let lock = NSLock()
    private var storedConfig = Config()

    var config: Config {
        get { lock.lock(); defer { lock.unlock() }; return storedConfig }
        set { lock.lock(); storedConfig = newValue; lock.unlock() }
    }

    /// 在主线程上调用
    var onResult: (([RecognizedLine], CGSize) -> Void)?

    func handle(_ buffer: CVPixelBuffer) {
        let current = config
        guard !current.paused else { return }
        guard let result = try? TextRecognizer.recognize(in: buffer, languages: current.languages, wordBoxes: current.wordBoxes) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.config.paused else { return }
            self.onResult?(result.lines, result.imageSize)
        }
    }
}
