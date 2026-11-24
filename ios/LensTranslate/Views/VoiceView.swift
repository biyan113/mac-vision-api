import SwiftUI

/// 对话翻译：两个人各按各的麦克风说话
struct VoiceView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var voice: VoiceModel
    @ObservedObject var bridge: TranslationBridge
    @ObservedObject var speaker: Speaker

    @State private var activeMine: Bool?

    /// 对方的语言：源语言设为自动检测时按英语处理
    private var theirs: LanguageOption { app.sourceLanguage ?? LanguageOption.option(for: "en")! }
    private var mine: LanguageOption { app.targetLanguage }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 64)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if voice.turns.isEmpty, !voice.isListening {
                            placeholder
                        }
                        ForEach(voice.turns) { turn in
                            bubble(for: turn).id(turn.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if voice.isListening {
                            liveBubble.id("live")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .animation(Theme.spring, value: voice.turns)
                }
                .onChange(of: voice.turns) { _, turns in
                    if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: voice.partial) { _, _ in
                    if voice.isListening { proxy.scrollTo("live", anchor: .bottom) }
                }
            }

            VStack(spacing: 14) {
                Waveform(level: voice.level, active: voice.isListening)
                Text(statusText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)

                HStack(spacing: 28) {
                    micButton(label: theirs.name, isMine: false)
                    micButton(label: mine.name, isMine: true)
                }
            }
            .padding(.bottom, 92)
        }
        .onChange(of: bridge.translations) { _, _ in speakPending() }
        .onChange(of: voice.isListening) { _, listening in
            if !listening { activeMine = nil }
        }
        .onDisappear {
            voice.stop()
            speaker.stop()
        }
    }

    private var statusText: String {
        if let error = voice.errorMessage { return error }
        guard voice.isListening, let activeMine else { return "轻点一方的麦克风按钮开始说话" }
        return "正在聆听 · \(activeMine ? mine.name : theirs.name)"
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(Theme.secondaryText)
            Text("两个人轮流说话，译文会显示并朗读出来")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
    }

    private func bubble(for turn: VoiceModel.Turn) -> some View {
        let translated = bridge.translation(for: turn.original)
        return VStack(alignment: .leading, spacing: 4) {
            Text(turn.original)
                .font(.system(size: 13))
                .foregroundStyle(turn.mine ? Theme.onAccent.opacity(0.75) : Theme.secondaryText)
            Text(translated ?? "翻译中…")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(turn.mine ? Theme.onAccent : .white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(turn.mine ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 300, alignment: turn.mine ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: turn.mine ? .trailing : .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if let translated, let target = LanguageOption.option(for: turn.targetID) {
                speaker.speak(translated, locale: target.speechLocale)
            }
        }
        .accessibilityHint("轻点朗读译文")
    }

    private var liveBubble: some View {
        let isMine = activeMine ?? true
        return Text(voice.partial.isEmpty ? "…" : voice.partial)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private func micButton(label: String, isMine: Bool) -> some View {
        let active = voice.isListening && activeMine == isMine
        return VStack(spacing: 8) {
            Button {
                toggle(isMine: isMine)
            } label: {
                Image(systemName: active ? "stop.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isMine ? Theme.onAccent : .white)
                    .frame(width: 72, height: 72)
                    .background(isMine ? Theme.accent : Theme.surfaceRaised, in: Circle())
                    .pulseRing(active: active)
            }
            .disabled(voice.isListening && !active)
            .opacity(voice.isListening && !active ? 0.4 : 1)
            .accessibilityLabel(active ? "停止" : "说\(label)")

            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
        }
    }

    private func toggle(isMine: Bool) {
        if voice.isListening {
            voice.stop()
            return
        }
        speaker.stop()
        activeMine = isMine
        Task {
            await voice.start(speaker: isMine ? mine : theirs, listener: isMine ? theirs : mine, mine: isMine)
            if !voice.isListening { activeMine = nil }
        }
    }

    /// 译文到达后自动朗读还没读过的句子
    private func speakPending() {
        for turn in voice.turns where !turn.spoken {
            guard let translated = bridge.translation(for: turn.original) else { continue }
            voice.markSpoken(turn.id)
            if app.autoSpeak, let target = LanguageOption.option(for: turn.targetID) {
                speaker.speak(translated, locale: target.speechLocale)
            }
        }
    }
}
