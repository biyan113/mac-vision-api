import LensCore
import SwiftUI
import Translation

struct RootView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case translate
        case learn
        case voice

        var id: String { rawValue }
        var title: String {
            switch self {
            case .translate: return "翻译"
            case .learn: return "学词"
            case .voice: return "对话"
            }
        }
    }

    @EnvironmentObject private var app: AppModel
    @StateObject private var camera = CameraController()
    @StateObject private var live = LiveTextModel()
    @StateObject private var bridge = TranslationBridge()
    @StateObject private var speaker = Speaker()
    @StateObject private var voice = VoiceModel()

    @State private var mode: Mode = .translate
    @State private var showOriginal = false
    @State private var showSettings = false
    @State private var showWordbook = false
    @State private var cardEntry: Highlight?
    @State private var viewSize: CGSize = .zero
    @State private var configuration: TranslationSession.Configuration?
    @State private var configuredPair = ""

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            if mode == .voice {
                VoiceView(voice: voice, bridge: bridge, speaker: speaker)
                    .transition(.opacity)
            } else {
                cameraLayer
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                topBar
                if mode != .voice { statusChip }
                Spacer()
                if mode == .translate { translateCard }
                if mode == .learn { learnCard }
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .translationTask(configuration) { session in
            await bridge.serve(session)
        }
        .task {
            camera.onFrame = { [pipeline = live.pipeline] buffer in pipeline.handle(buffer) }
            applyMode()
            await camera.start()
        }
        .onChange(of: mode) { _, _ in applyMode() }
        .onChange(of: app.sourceLanguageID) { _, _ in languagesChanged() }
        .onChange(of: app.targetLanguageID) { _, _ in languagesChanged() }
        .onChange(of: app.selectedBookID) { _, _ in applyMode() }
        .onChange(of: app.vocabWordCount) { _, _ in applyMode() }
        .onChange(of: live.lines) { _, lines in
            if mode == .translate { bridge.request(lines.map(\.text)) }
        }
        .onChange(of: voice.turns) { _, turns in
            guard let last = turns.last else { return }
            setTranslation(sourceID: last.languageID, targetID: last.targetID)
            bridge.request([last.original])
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showWordbook) { WordbookView(speaker: speaker) }
        .sheet(item: $cardEntry) { highlight in
            WordCardView(entry: highlight.entry, sentence: highlight.sentence, speaker: speaker)
                .presentationDetents([.large])
        }
        .alert("提示", isPresented: Binding(get: { app.message != nil }, set: { if !$0 { app.message = nil } })) {
            Button("好") { app.message = nil }
        } message: {
            Text(app.message ?? "")
        }
    }

    // MARK: - 相机

    private var cameraLayer: some View {
        GeometryReader { proxy in
            ZStack {
                switch camera.status {
                case .denied:
                    notice("没有相机权限", detail: "请在“设置 → 译镜”里允许使用相机。")
                case .unavailable:
                    notice("无法使用相机", detail: "这台设备上没有可用的后置相机。")
                default:
                    CameraPreview(session: camera.session)
                    if !live.frozen { ScanLine() }
                    if mode == .translate {
                        TranslationOverlay(live: live, bridge: bridge, showOriginal: showOriginal)
                    } else {
                        LearnOverlay(live: live, focusedID: focusedHighlight?.entry.id)
                    }
                }
            }
            .onAppear { viewSize = proxy.size }
            .onChange(of: proxy.size) { _, size in viewSize = size }
        }
        .ignoresSafeArea()
    }

    private func notice(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.title3.bold())
            Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - 顶部

    private var topBar: some View {
        HStack(spacing: 10) {
            if mode == .voice {
                CircleIconButton(systemName: "trash", label: "清空对话") { voice.clear() }
            } else {
                CircleIconButton(systemName: camera.torchOn ? "bolt.fill" : "bolt.slash", label: "闪光灯", filled: camera.torchOn) {
                    camera.toggleTorch()
                }
            }

            Spacer(minLength: 0)

            Button { showSettings = true } label: {
                HStack(spacing: 10) {
                    if mode == .learn {
                        Image(systemName: "book.closed").foregroundStyle(Theme.accent)
                        Text(app.selectedBook?.name ?? "全部词书").lineLimit(1)
                    } else {
                        Text(app.sourceName)
                        Image(systemName: mode == .voice ? "arrow.left.arrow.right" : "arrow.right")
                            .foregroundStyle(Theme.accent)
                        Text(app.targetLanguage.name)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glass(cornerRadius: 22)
            }
            .accessibilityLabel("语言与设置")

            Spacer(minLength: 0)

            Button { showWordbook = true } label: {
                Text("\(app.savedWords.count)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Theme.accent, in: Capsule())
                    .contentTransition(.numericText())
            }
            .accessibilityLabel("生词本，已收集 \(app.savedWords.count) 个")
        }
        .padding(.top, 4)
    }

    private var statusChip: some View {
        HStack(spacing: 8) {
            Circle().fill(live.frozen ? Color.orange : Theme.accent).frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 12))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .glass(cornerRadius: 14)
        .animation(.default, value: statusText)
    }

    private var statusText: String {
        if live.frozen { return "画面已定格" }
        switch mode {
        case .translate: return live.lines.isEmpty ? "对准文字开始翻译" : "本机实时翻译 · 已识别 \(live.lines.count) 处"
        case .learn:
            if app.vocab == nil { return "尚未导入词库" }
            return live.highlights.isEmpty ? "对准英文寻找词书单词" : "本画面有 \(live.highlights.count) 个词书单词"
        case .voice: return ""
        }
    }

    // MARK: - 底部卡片

    private var focusedLine: RecognizedLine? {
        Focus.nearestLine(in: live, viewSize: viewSize)
    }

    private var focusedHighlight: Highlight? {
        Focus.nearestHighlight(in: live, viewSize: viewSize)
    }

    @ViewBuilder
    private var translateCard: some View {
        if let line = focusedLine {
            let translated = bridge.translation(for: line.text)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    Text(translated ?? "翻译中…")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(translated == nil ? Theme.secondaryText : .white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                CircleIconButton(systemName: "speaker.wave.2.fill", label: "朗读译文", filled: true, size: 48) {
                    if let translated { speaker.speak(translated, locale: app.targetLanguage.speechLocale) }
                }
                .disabled(translated == nil)
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .glass(cornerRadius: 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let error = bridge.lastError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity)
                .glass(cornerRadius: 20)
        }
    }

    @ViewBuilder
    private var learnCard: some View {
        if app.vocab == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("学词模式需要词库").font(.headline)
                Text("在设置里导入用仓库脚本生成的 vocab.sqlite 后，镜头里出现的词书单词会被标出来。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Button("打开设置") { showSettings = true }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Theme.onAccent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: 24)
        } else if let highlight = focusedHighlight {
            let saved = app.isSaved(highlight.entry.word)
            HStack(spacing: 10) {
                Button { cardEntry = highlight } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(highlight.entry.word).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                            Text(highlight.entry.phonetic).font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                        }
                        Text(highlight.entry.definition.replacingOccurrences(of: "\n", with: "  "))
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityHint("查看单词卡")

                CircleIconButton(systemName: "speaker.wave.2", label: "朗读 \(highlight.entry.word)", size: 48) {
                    speaker.speak(highlight.entry.word, locale: "en-US")
                }
                CircleIconButton(systemName: saved ? "checkmark" : "plus", label: saved ? "已加入生词本" : "加入生词本", filled: !saved, size: 48) {
                    withAnimation(Theme.spring) {
                        app.toggleSaved(highlight.entry, sentence: highlight.sentence, source: .camera)
                    }
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .glass(cornerRadius: 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - 控制区

    private var controls: some View {
        HStack {
            ModeSwitcher(mode: $mode)
            Spacer(minLength: 8)
            if mode != .voice {
                Button {
                    withAnimation(Theme.spring) { live.frozen.toggle() }
                } label: {
                    Circle()
                        .fill(live.frozen ? Color.orange : Theme.accent)
                        .padding(4)
                        .frame(width: 60, height: 60)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                        .overlay {
                            if live.frozen {
                                Image(systemName: "play.fill").foregroundStyle(.black)
                            }
                        }
                }
                .accessibilityLabel(live.frozen ? "继续识别" : "定格画面")
            }
            if mode == .translate {
                Spacer(minLength: 8)
                Button(showOriginal ? "看译文" : "看原文") {
                    showOriginal.toggle()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(showOriginal ? Color.black : Color.white)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(showOriginal ? Color.white : Color.white.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(cornerRadius: 40)
    }

    // MARK: - 状态同步

    private func applyMode() {
        switch mode {
        case .translate:
            live.configure(languages: app.sourceLanguage?.visionLanguages ?? [], resolver: nil)
            live.setActive(true)
            setTranslation(sourceID: app.sourceLanguageID, targetID: app.targetLanguageID)
            Task { await camera.start() }
        case .learn:
            let vocab = app.vocab
            let bookID = app.selectedBookID == 0 ? nil : app.selectedBookID
            live.configure(languages: ["en-US"]) { token in
                guard let vocab else { return nil }
                return try? vocab.entry(matching: token, bookID: bookID)
            }
            live.setActive(true)
            Task { await camera.start() }
        case .voice:
            live.setActive(false)
            camera.stop()
        }
    }

    private func languagesChanged() {
        bridge.reset()
        applyMode()
    }

    /// 切换翻译方向。只有语言对变化时才重建系统的翻译会话。
    private func setTranslation(sourceID: String, targetID: String) {
        let pair = "\(sourceID)>\(targetID)"
        guard pair != configuredPair else { return }
        configuredPair = pair
        let source = sourceID.isEmpty ? nil : Locale.Language(identifier: sourceID)
        configuration = TranslationSession.Configuration(source: source, target: Locale.Language(identifier: targetID))
    }
}
