import LensCore
import SwiftUI

/// 单词卡：音标、释义、所在词书，以及遇到它的那句话
struct WordCardView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: VocabEntry
    let sentence: String
    @ObservedObject var speaker: Speaker

    @State private var categories: [String] = []

    private var saved: Bool { app.isSaved(entry.word) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(entry.word)
                            .font(.system(size: 48, weight: .bold))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)

                        HStack(spacing: 10) {
                            if !entry.phoneticUK.isEmpty { phoneticButton("英", entry.phoneticUK, locale: "en-GB") }
                            if !entry.phoneticUS.isEmpty { phoneticButton("美", entry.phoneticUS, locale: "en-US") }
                            if entry.phoneticUK.isEmpty, entry.phoneticUS.isEmpty { phoneticButton("读", "朗读", locale: "en-US") }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(entry.definition.split(separator: "\n").map(String.init), id: \.self) { line in
                                Text(line).font(.system(size: 18, weight: .medium))
                            }
                            if entry.definition.isEmpty {
                                Text("词库里没有这个词的释义").foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    if !categories.isEmpty {
                        section("收录于词书") {
                            FlowLayout(spacing: 8) {
                                ForEach(categories, id: \.self) { category in
                                    Text(category)
                                        .font(.system(size: 13))
                                        .padding(.horizontal, 14)
                                        .frame(height: 32)
                                        .background(Theme.surfaceRaised, in: Capsule())
                                }
                            }
                        }
                    }

                    if !sentence.isEmpty {
                        section("你遇到它的句子") {
                            Text(highlightedSentence)
                                .font(.system(size: 17))
                                .lineSpacing(5)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.ground)
            .safeAreaInset(edge: .bottom) {
                Button {
                    withAnimation(Theme.spring) { app.toggleSaved(entry, sentence: sentence, source: .camera) }
                } label: {
                    Text(saved ? "已加入生词本" : "加入生词本")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(saved ? Theme.accent : Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(saved ? Theme.surfaceRaised : Theme.accent, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            categories = (try? app.vocab?.categories(forWordID: entry.id)) ?? []
        }
    }

    private var highlightedSentence: AttributedString {
        var text = AttributedString(sentence)
        // 标出句子里对应这个单词的词形
        for item in Lemmatizer.words(in: sentence) where Lemmatizer.candidates(for: item.word).contains(entry.word.lowercased()) {
            if let lower = AttributedString.Index(item.range.lowerBound, within: text),
               let upper = AttributedString.Index(item.range.upperBound, within: text) {
                text[lower ..< upper].foregroundColor = Theme.onAccent
                text[lower ..< upper].backgroundColor = Theme.accent
                text[lower ..< upper].font = .system(size: 17, weight: .bold)
            }
        }
        return text
    }

    private func phoneticButton(_ label: String, _ phonetic: String, locale: String) -> some View {
        Button {
            speaker.speak(entry.word, locale: locale)
        } label: {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                Text(phonetic).font(.system(size: 15)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "speaker.wave.2").foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        }
        .accessibilityLabel("\(label)式发音")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondaryText)
            content()
        }
    }
}

/// 自动换行的横向排列
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, width: width)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews: subviews, width: bounds.width)
        for (index, origin) in arrangement.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return (origins, maxWidth, y + rowHeight)
    }
}
