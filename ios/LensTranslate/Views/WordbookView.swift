import LensCore
import SwiftUI

/// 生词本
struct WordbookView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var speaker: Speaker

    var body: some View {
        NavigationStack {
            Group {
                if app.savedWords.isEmpty {
                    ContentUnavailableView(
                        "还没有生词",
                        systemImage: "book.closed",
                        description: Text("在学词模式里对准英文，点加号把单词收进来。")
                    )
                } else {
                    List {
                        Section {
                            ForEach(app.savedWords) { word in
                                row(for: word)
                            }
                            .onDelete { offsets in
                                for index in offsets { app.removeSaved(app.savedWords[index].word) }
                            }
                        } footer: {
                            Text("词库数据来自 English Vocabulary Vault，CC BY-NC-SA 4.0")
                        }
                    }
                }
            }
            .navigationTitle("生词本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: app.ankiExport(), preview: SharePreview("生词本（Anki 格式）")) {
                        Label("导出到 Anki", systemImage: "square.and.arrow.up")
                    }
                    .disabled(app.savedWords.isEmpty)
                }
            }
        }
    }

    private func row(for word: SavedWord) -> some View {
        Button {
            speaker.speak(word.word, locale: "en-US")
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(word.word).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        Text(word.phonetic).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                    Text(word.definition.replacingOccurrences(of: "\n", with: "  "))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(word.source == .camera ? "镜头" : "对话")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
        }
        .accessibilityHint("轻点朗读")
    }
}
