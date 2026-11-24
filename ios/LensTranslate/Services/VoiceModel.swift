import AVFoundation
import Foundation
import Speech

/// 对话翻译：听一句话，转成文字，交给翻译
@MainActor
final class VoiceModel: ObservableObject {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let original: String
        /// 说话的人用的语言标识
        let languageID: String
        /// 要翻译成的语言标识
        let targetID: String
        let mine: Bool
        var spoken = false
    }

    @Published private(set) var turns: [Turn] = []
    @Published private(set) var partial = ""
    @Published private(set) var isListening = false
    /// 0~1 的音量，用来驱动波形
    @Published private(set) var level: Float = 0
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var currentTurn: (languageID: String, targetID: String, mine: Bool)?

    func markSpoken(_ id: UUID) {
        if let index = turns.firstIndex(where: { $0.id == id }) {
            turns[index].spoken = true
        }
    }

    func clear() {
        turns = []
    }

    /// 开始听写。`speaker` 是说话人的语言，`listener` 是要翻译成的语言。
    func start(speaker: LanguageOption, listener: LanguageOption, mine: Bool) async {
        guard !isListening else { return }
        errorMessage = nil

        guard await Self.requestSpeechAuthorization() else {
            errorMessage = "没有语音识别权限，请在系统设置里开启"
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "没有麦克风权限，请在系统设置里开启"
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: speaker.speechLocale)), recognizer.isAvailable else {
            errorMessage = "当前无法识别\(speaker.name)语音"
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // 支持时只在本机识别，不把录音发到服务器
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.level(of: buffer)
                DispatchQueue.main.async { self?.level = level }
            }

            engine.prepare()
            try engine.start()

            currentTurn = (speaker.id, listener.id, mine)
            partial = ""
            isListening = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal ?? false
                DispatchQueue.main.async {
                    guard let self, self.isListening else { return }
                    if let text { self.partial = text }
                    if finished || error != nil { self.stop() }
                }
            }
        } catch {
            errorMessage = "无法开始录音：\(error.localizedDescription)"
            teardown()
        }
    }

    /// 结束听写，把已识别的内容作为一句话加入对话
    func stop() {
        guard isListening else { return }
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, let turn = currentTurn {
            turns.append(Turn(original: text, languageID: turn.languageID, targetID: turn.targetID, mine: turn.mine))
        }
        teardown()
    }

    private func teardown() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        currentTurn = nil
        partial = ""
        level = 0
        isListening = false
        // 切回播放模式，译文朗读才会从扬声器正常输出
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(buffer.frameLength)
        for index in 0 ..< count {
            sum += channel[index] * channel[index]
        }
        let rms = (sum / Float(count)).squareRoot()
        // 把常见的说话音量映射到 0~1
        return min(max(rms * 12, 0), 1)
    }
}
