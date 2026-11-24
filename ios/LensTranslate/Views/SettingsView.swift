import LensCore
import SwiftUI
import UniformTypeIdentifiers

/// 语言、朗读和词库设置
struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("翻译语言") {
                    Picker("从", selection: $app.sourceLanguageID) {
                        Text("自动检测").tag("")
                        ForEach(LanguageOption.all) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    Picker("译为", selection: $app.targetLanguageID) {
                        ForEach(LanguageOption.all) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    Button("交换语言") {
                        withAnimation(Theme.spring) { app.swapLanguages() }
                    }
                    .disabled(app.sourceLanguage == nil)
                }

                Section {
                    Toggle("自动朗读译文", isOn: $app.autoSpeak)
                } footer: {
                    Text("对话模式里，译文出来后自动读给对方听。")
                }

                Section {
                    if app.vocab == nil {
                        Text("尚未导入词库")
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        LabeledContent("词条", value: "\(app.vocabWordCount)")
                        NavigationLink {
                            BookPickerView()
                        } label: {
                            LabeledContent("高亮的词书", value: app.selectedBook?.name ?? "全部词书")
                        }
                    }
                    Button(app.vocab == nil ? "导入词库文件" : "更换词库文件") {
                        importing = true
                    }
                } header: {
                    Text("学词模式")
                } footer: {
                    Text("词库文件由仓库里的 tools/vocab/build_vocab.py 生成。数据来自 English Vocabulary Vault，采用 CC BY-NC-SA 4.0 许可，仅限非商业使用。")
                }

                Section {
                    Label("文字识别、语音识别和翻译都在这台 iPhone 上完成，画面和录音不会上传。", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .database]) { result in
                if case .success(let url) = result {
                    app.importVocab(from: url)
                }
            }
        }
    }
}

/// 选择学词模式要高亮的词书
struct BookPickerView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var grouped: [(category: String, books: [VocabBook])] {
        let filtered = query.isEmpty ? app.books : app.books.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query)
        }
        return Dictionary(grouping: filtered, by: \.category)
            .map { (category: $0.key, books: $0.value) }
            .sorted { $0.category < $1.category }
    }

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    row(title: "全部词书", detail: "\(app.vocabWordCount) 词", selected: app.selectedBookID == 0) {
                        app.selectedBookID = 0
                    }
                }
            }
            ForEach(grouped, id: \.category) { group in
                Section(group.category) {
                    ForEach(group.books) { book in
                        row(title: book.name, detail: "\(book.wordCount) 词", selected: app.selectedBookID == book.id) {
                            app.selectedBookID = book.id
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索词书")
        .navigationTitle("词书")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.white)
                    Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
