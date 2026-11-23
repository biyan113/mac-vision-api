import AppKit
import UniformTypeIdentifiers
import VisionCore

/// 识别页面：左侧显示原图（或 PDF 页面），右侧是结果面板。
/// 功能由侧边栏选择，打开、保存等操作由窗口工具栏和菜单触发。
final class RecognitionViewController: NSViewController, NSTextViewDelegate {
    private struct PDFState {
        var data: Data
        var pageCount: Int
        var pageIndex: Int
    }

    /// 状态变化（是否有结果、是否忙碌等）后调用，窗口据此更新工具栏
    var onStateChange: (() -> Void)?

    // MARK: - 控件

    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fastCheckbox = NSButton(checkboxWithTitle: L("快速模式", "Fast"), target: nil, action: nil)
    private let redactionPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let previousPageButton = NSButton(title: "", target: nil, action: nil)
    private let nextPageButton = NSButton(title: "", target: nil, action: nil)
    private let pageLabel = NSTextField(labelWithString: "")
    private let extractTextButton = NSButton(
        title: L("提取内嵌文本", "Extract Embedded Text"), target: nil, action: nil
    )
    private let recognizeAllButton = NSButton(
        title: L("识别全部页面", "Recognize All Pages"), target: nil, action: nil
    )
    private var contextBar = NSStackView()

    private let sourceCanvas = ImageCanvasView()
    private let resultCanvas = ImageCanvasView()
    private let resultScrollView = NSTextView.scrollableTextView()
    private let resultTitleLabel = NSTextField(labelWithString: L("结果", "Result"))
    private let resultCountLabel = NSTextField(labelWithString: "")

    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let insightsPopup = NSPopUpButton(frame: .zero, pullsDown: true)

    private var panesTopWithoutContextBar: NSLayoutConstraint?
    private var panesTopWithContextBar: NSLayoutConstraint?

    private var resultTextView: NSTextView? {
        resultScrollView.documentView as? NSTextView
    }

    // MARK: - 状态

    private(set) var feature: VisionFeature = Settings.defaultFeature
    /// 当前用于识别的图片数据；打开 PDF 时为当前页渲染出的 PNG
    private var imageData: Data?
    private var pdf: PDFState?
    private(set) var documentName = ""
    private var output: AnalysisOutput?
    /// 每次开始新的后台任务时递增，用来丢弃过期的结果
    private var runToken = 0
    private(set) var isBusy = false
    private var isSyncingSelection = false

    private var currentOptions: AnalysisOptions {
        AnalysisOptions(
            text: TextRecognitionOptions(
                languages: OCRLanguage.codes(at: languagePopup.indexOfSelectedItem),
                fast: fastCheckbox.state == .on
            ),
            redaction: RedactionChoice.targets(at: redactionPopup.indexOfSelectedItem)
        )
    }

    // 供工具栏和菜单判断按钮是否可用
    var hasSource: Bool { imageData != nil }
    var hasOutput: Bool { output != nil }
    var hasJSON: Bool { output?.json != nil }

    // MARK: - 视图搭建

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 640))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureControls()
        layoutControls()
        updateControls()
        setStatus(L("打开、拖入或粘贴一张图片或 PDF", "Open, drop or paste an image or PDF"))
    }

    private func configureControls() {
        for option in OCRLanguage.options {
            languagePopup.addItem(withTitle: option.title)
        }
        languagePopup.selectItem(at: Settings.ocrLanguageIndex)
        languagePopup.target = self
        languagePopup.action = #selector(optionChanged(_:))
        fastCheckbox.state = Settings.ocrFastMode ? .on : .off
        fastCheckbox.target = self
        fastCheckbox.action = #selector(optionChanged(_:))
        for option in RedactionChoice.options {
            redactionPopup.addItem(withTitle: option.title)
        }
        redactionPopup.target = self
        redactionPopup.action = #selector(optionChanged(_:))

        previousPageButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: L("上一页", "Previous Page"))
        previousPageButton.imagePosition = .imageOnly
        previousPageButton.target = self
        previousPageButton.action = #selector(previousPage(_:))
        nextPageButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: L("下一页", "Next Page"))
        nextPageButton.imagePosition = .imageOnly
        nextPageButton.target = self
        nextPageButton.action = #selector(nextPage(_:))
        extractTextButton.target = self
        extractTextButton.action = #selector(extractPDFText(_:))
        recognizeAllButton.target = self
        recognizeAllButton.action = #selector(recognizeAllPages(_:))

        sourceCanvas.placeholder = L(
            "把图片或 PDF 拖到这里\n也可以点工具栏的打开按钮，或按 ⌘V 粘贴",
            "Drop an image or PDF here\nor use Open in the toolbar, or press ⌘V to paste"
        )
        sourceCanvas.onDropFile = { [weak self] url in
            self?.loadFile(at: url)
        }
        sourceCanvas.onSelectBox = { [weak self] index in
            self?.selectResultLine(index)
        }
        resultCanvas.placeholder = L("处理结果会显示在这里", "The result will appear here")
        resultCanvas.showsCheckerboard = true

        if let textView = resultTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = NSFont.systemFont(ofSize: 13)
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.drawsBackground = false
            textView.delegate = self
        }
        resultScrollView.borderType = .noBorder
        resultScrollView.drawsBackground = false

        resultTitleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        resultCountLabel.textColor = .secondaryLabelColor
        resultCountLabel.font = NSFont.systemFont(ofSize: 12)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        insightsPopup.controlSize = .small
        insightsPopup.target = self
        insightsPopup.action = #selector(insightChosen(_:))
        insightsPopup.isHidden = true
    }

    private func layoutControls() {
        let contextSpacer = NSView()
        contextSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        contextBar = NSStackView(views: [
            previousPageButton, pageLabel, nextPageButton, extractTextButton, recognizeAllButton,
            contextSpacer, languagePopup, fastCheckbox, redactionPopup,
        ])
        contextBar.orientation = .horizontal
        contextBar.spacing = 10

        // 结果面板：标题行、内容区、状态行
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [resultTitleLabel, headerSpacer, resultCountLabel])
        header.orientation = .horizontal

        let footer = NSStackView(views: [spinner, statusLabel, insightsPopup])
        footer.orientation = .horizontal
        footer.spacing = 6

        let resultBody = NSView()
        for subview in [resultScrollView, resultCanvas] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            resultBody.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: resultBody.topAnchor),
                subview.bottomAnchor.constraint(equalTo: resultBody.bottomAnchor),
                subview.leadingAnchor.constraint(equalTo: resultBody.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: resultBody.trailingAnchor),
            ])
        }

        let resultPanel = NSBox()
        resultPanel.boxType = .custom
        resultPanel.titlePosition = .noTitle
        resultPanel.cornerRadius = 12
        resultPanel.borderWidth = 1
        resultPanel.borderColor = .separatorColor
        resultPanel.fillColor = .controlBackgroundColor
        resultPanel.contentViewMargins = .zero
        let panelContent = NSView()
        resultPanel.contentView = panelContent
        for subview in [header, resultBody, footer] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            panelContent.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: panelContent.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: panelContent.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: panelContent.trailingAnchor, constant: -12),
            resultBody.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            resultBody.leadingAnchor.constraint(equalTo: panelContent.leadingAnchor, constant: 4),
            resultBody.trailingAnchor.constraint(equalTo: panelContent.trailingAnchor, constant: -4),
            footer.topAnchor.constraint(equalTo: resultBody.bottomAnchor, constant: 6),
            footer.leadingAnchor.constraint(equalTo: panelContent.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: panelContent.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: panelContent.bottomAnchor, constant: -10),
        ])

        for subview in [contextBar, sourceCanvas, resultPanel] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        // 上下文工具栏只在有内容时显示（PDF 翻页，或当前功能有选项），隐藏时双栏区域贴着顶部
        let withoutBar = sourceCanvas.topAnchor.constraint(equalTo: view.topAnchor, constant: 12)
        let withBar = sourceCanvas.topAnchor.constraint(equalTo: contextBar.bottomAnchor, constant: 10)
        panesTopWithoutContextBar = withoutBar
        panesTopWithContextBar = withBar

        NSLayoutConstraint.activate([
            contextBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            contextBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            contextBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            withoutBar,
            sourceCanvas.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            sourceCanvas.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            resultPanel.topAnchor.constraint(equalTo: sourceCanvas.topAnchor),
            resultPanel.bottomAnchor.constraint(equalTo: sourceCanvas.bottomAnchor),
            resultPanel.leadingAnchor.constraint(equalTo: sourceCanvas.trailingAnchor, constant: 12),
            resultPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            // 原图占大约六成宽度
            sourceCanvas.widthAnchor.constraint(equalTo: resultPanel.widthAnchor, multiplier: 1.5),
            sourceCanvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            resultPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
        contextBar.isHidden = true
    }

    // MARK: - 切换功能

    /// 由侧边栏调用：切换当前功能，已有图片时立即重新处理
    func setFeature(_ newFeature: VisionFeature) {
        guard newFeature != feature else { return }
        feature = newFeature
        output = nil
        updateControls()
        updateWindowTitle()
        if imageData != nil {
            run()
        }
    }

    // MARK: - 载入文件

    /// 载入图片或 PDF 文件
    func loadFile(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            load(data: data, name: url.lastPathComponent)
        } catch {
            setStatus(L("无法读取文件：", "Cannot read file: ") + error.localizedDescription)
        }
    }

    private func load(data: Data, name: String) {
        if PDFEngine.looksLikePDF(data) {
            loadPDF(data: data, name: name)
        } else {
            loadImage(data: data, name: name)
        }
    }

    /// 载入图片数据并立即处理
    func loadImage(data: Data, name: String) {
        guard NSImage(data: data) != nil else {
            setStatus(L("无法识别的图片格式：", "Unsupported image format: ") + name)
            return
        }
        pdf = nil
        documentName = name
        setSourceImage(data)
        updateWindowTitle()
        run()
    }

    private func loadPDF(data: Data, name: String) {
        do {
            let pageCount = try PDFEngine.pageCount(pdfData: data)
            guard pageCount > 0 else {
                setStatus(L("这个 PDF 没有页面：", "This PDF has no pages: ") + name)
                return
            }
            pdf = PDFState(data: data, pageCount: pageCount, pageIndex: 0)
            documentName = name
            showPage(0)
        } catch {
            setStatus(L("无法打开 PDF：", "Cannot open PDF: ") + error.localizedDescription)
        }
    }

    /// 渲染并显示 PDF 的指定页，然后对该页执行当前功能
    private func showPage(_ index: Int) {
        guard var state = pdf, (0..<state.pageCount).contains(index) else { return }
        state.pageIndex = index
        pdf = state
        updateWindowTitle()

        let token = beginWork(L("正在渲染第 \(index + 1) 页…", "Rendering page \(index + 1)…"))
        let pdfData = state.data
        Task { [weak self] in
            let result = await Background.run {
                try PDFEngine.renderPage(pdfData: pdfData, pageIndex: index, dpi: 150)
            }
            guard let self = self, self.runToken == token else { return }
            switch result {
            case .success(let png):
                self.setSourceImage(png)
                self.run()
            case .failure(let error):
                self.endWork(status: L("渲染失败：", "Rendering failed: ") + error.message)
            }
        }
    }

    private func setSourceImage(_ data: Data) {
        imageData = data
        sourceCanvas.image = NSImage(data: data)
        sourceCanvas.boxes = []
    }

    private func updateWindowTitle() {
        view.window?.title = documentName.isEmpty ? "Vision" : documentName
        view.window?.subtitle = feature.title
    }

    // MARK: - 工具栏与菜单动作

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            loadFile(at: url)
        }
    }

    @objc func pasteImage(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier, UTType.pdf.identifier],
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           let url = urls.first {
            loadFile(at: url)
        } else if let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation {
            loadImage(data: data, name: L("剪贴板图片", "Clipboard Image"))
        } else {
            setStatus(L("剪贴板里没有图片", "No image on the clipboard"))
        }
    }

    @objc func copyResult(_ sender: Any?) {
        guard let output = output else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let data = output.imageData {
            pasteboard.setData(data, forType: .png)
        } else {
            pasteboard.setString(output.text, forType: .string)
        }
        setStatus(L("结果已复制到剪贴板", "Result copied to the clipboard"))
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let output = output else { return }
        if let imageData = output.imageData {
            save(imageData, as: .png, fileExtension: "png")
        } else {
            save(Data(output.text.utf8), as: .plainText, fileExtension: "txt")
        }
    }

    @objc func exportJSON(_ sender: Any?) {
        guard let json = output?.json else { return }
        save(json, as: .json, fileExtension: "json")
    }

    /// 把当前图片或整份 PDF 导出为可搜索、可复制文字的 PDF
    @objc func exportSearchablePDF(_ sender: Any?) {
        guard let imageData = imageData, !isBusy else { return }
        let pdfData = pdf?.data
        let options = currentOptions.text
        let previousOutput = output
        let token = beginWork(L("正在生成可搜索 PDF…", "Creating searchable PDF…"))

        Task { [weak self] in
            let result = await Background.run { () -> Data in
                if let pdfData = pdfData {
                    return try SearchablePDF.make(pdfData: pdfData, options: options)
                }
                return try SearchablePDF.make(imageData: imageData, options: options)
            }
            guard let self = self, self.runToken == token else { return }
            // 导出不改变当前显示的结果
            self.output = previousOutput
            self.sourceCanvas.boxes = previousOutput?.boxes ?? []
            switch result {
            case .success(let data):
                self.endWork(status: L("可搜索 PDF 已生成", "Searchable PDF is ready"))
                self.save(data, as: .pdf, fileExtension: "pdf", suffix: "-searchable")
            case .failure(let error):
                self.endWork(status: L("生成失败：", "Failed: ") + error.message)
            }
        }
    }

    private func save(_ data: Data, as type: UTType, fileExtension: String, suffix: String = "-result") {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        let baseName = documentName.isEmpty
            ? "vision"
            : (documentName as NSString).deletingPathExtension
        panel.nameFieldStringValue = baseName + suffix + "." + fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            setStatus(L("已保存到 ", "Saved to ") + url.path)
        } catch {
            setStatus(L("保存失败：", "Save failed: ") + error.localizedDescription)
        }
    }

    @objc func runAnalysis(_ sender: Any?) {
        run()
    }

    @objc private func optionChanged(_ sender: Any?) {
        if imageData != nil {
            run()
        }
    }

    @objc private func previousPage(_ sender: Any?) {
        guard let state = pdf else { return }
        showPage(state.pageIndex - 1)
    }

    @objc private func nextPage(_ sender: Any?) {
        guard let state = pdf else { return }
        showPage(state.pageIndex + 1)
    }

    /// 打开或复制结果里识别出的链接、电话、日期、地址
    @objc private func insightChosen(_ sender: Any?) {
        // 下拉按钮的第 0 项是标题
        let index = insightsPopup.indexOfSelectedItem - 1
        guard let insights = output?.insights, insights.indices.contains(index) else { return }
        let insight = insights[index]
        if let string = insight.url, let url = URL(string: string) {
            NSWorkspace.shared.open(url)
            setStatus(L("已打开：", "Opened: ") + insight.value)
        } else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(insight.value, forType: .string)
            setStatus(L("已复制：", "Copied: ") + insight.value)
        }
    }

    // MARK: - 执行识别

    private func run() {
        guard let data = imageData else {
            setStatus(L("请先打开一张图片或 PDF", "Open an image or PDF first"))
            return
        }
        let feature = self.feature
        let options = currentOptions
        let started = Date()
        let token = beginWork(L("正在处理：", "Processing: ") + feature.title + "…")

        Task { [weak self] in
            let result = await Background.run {
                try Analyzer.run(feature, imageData: data, options: options)
            }
            guard let self = self, self.runToken == token else { return }
            switch result {
            case .success(let output):
                let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
                self.present(output, status: L("完成 · \(elapsed) 秒", "Done · \(elapsed)s"))
            case .failure(let error):
                self.endWork(status: L("\(feature.title)失败：", "\(feature.title) failed: ") + error.message)
            }
        }
    }

    /// 抽取 PDF 全部页面的内嵌文本（不做 OCR）
    @objc private func extractPDFText(_ sender: Any?) {
        guard let state = pdf else { return }
        let token = beginWork(L("正在提取 PDF 内嵌文本…", "Extracting embedded PDF text…"))
        let pdfData = state.data

        Task { [weak self] in
            let result = await Background.run {
                try PDFEngine.extractText(pdfData: pdfData, mergePages: true)
            }
            guard let self = self, self.runToken == token else { return }
            switch result {
            case .success(let response):
                var lines: [String] = []
                for page in response.extractedPages {
                    lines.append(RecognitionViewController.pageHeader(page.pageNumber))
                    lines.append(contentsOf: page.text.components(separatedBy: "\n"))
                    lines.append("")
                }
                let hasText = response.extractedPages.contains {
                    !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                self.present(
                    AnalysisOutput(
                        lines: hasText ? lines : [],
                        emptyMessage: L(
                            "（这个 PDF 没有内嵌文本，可能是扫描件，请使用「识别全部页面」）",
                            "(This PDF has no embedded text. It may be a scan; try “Recognize All Pages”.)"
                        ),
                        json: try? JSONEncoder().encode(response),
                        insights: TextInsights.detect(in: response.allText ?? "")
                    ),
                    status: L(
                        "已提取 \(response.extractedPages.count) 页的内嵌文本",
                        "Extracted embedded text from \(response.extractedPages.count) page(s)"
                    )
                )
            case .failure(let error):
                self.endWork(status: L("提取失败：", "Extraction failed: ") + error.message)
            }
        }
    }

    /// 对 PDF 的每一页做文字识别，适用于扫描件
    @objc private func recognizeAllPages(_ sender: Any?) {
        guard let state = pdf else { return }
        let token = beginWork("")
        let pdfData = state.data
        let pageCount = state.pageCount
        let options = currentOptions.text

        Task { [weak self] in
            var lines: [String] = []
            for index in 0..<pageCount {
                guard let controller = self, controller.runToken == token else { return }
                controller.setStatus(L(
                    "正在识别第 \(index + 1)/\(pageCount) 页…",
                    "Recognizing page \(index + 1) of \(pageCount)…"
                ))
                let result = await Background.run { () -> [String] in
                    let png = try PDFEngine.renderPage(pdfData: pdfData, pageIndex: index, dpi: 150)
                    return try VisionEngine.recognizeText(imageData: png, options: options).map { $0.text }
                }
                switch result {
                case .success(let pageLines):
                    lines.append(RecognitionViewController.pageHeader(index + 1))
                    lines.append(contentsOf: pageLines)
                    lines.append("")
                case .failure(let error):
                    guard controller.runToken == token else { return }
                    controller.endWork(status: L(
                        "第 \(index + 1) 页识别失败：",
                        "Recognition failed on page \(index + 1): "
                    ) + error.message)
                    return
                }
            }
            guard let controller = self, controller.runToken == token else { return }
            controller.present(
                AnalysisOutput(lines: lines, insights: TextInsights.detect(in: lines.joined(separator: "\n"))),
                status: L("已识别全部 \(pageCount) 页", "Recognized all \(pageCount) page(s)")
            )
        }
    }

    private static func pageHeader(_ pageNumber: Int) -> String {
        L("—— 第 \(pageNumber) 页 ——", "—— Page \(pageNumber) ——")
    }

    // MARK: - 后台任务状态

    /// 标记开始一个新的后台任务，返回用于校验结果是否过期的令牌
    private func beginWork(_ status: String) -> Int {
        runToken += 1
        isBusy = true
        output = nil
        sourceCanvas.boxes = []
        spinner.startAnimation(nil)
        setStatus(status)
        updateControls()
        return runToken
    }

    private func endWork(status: String) {
        isBusy = false
        spinner.stopAnimation(nil)
        setStatus(status)
        updateControls()
    }

    /// 显示处理结果
    private func present(_ result: AnalysisOutput, status: String) {
        output = result
        sourceCanvas.boxes = result.boxes

        isSyncingSelection = true
        if let data = result.imageData {
            resultCanvas.image = NSImage(data: data)
            resultTextView?.string = ""
        } else {
            resultCanvas.image = nil
            resultTextView?.string = result.lines.isEmpty ? result.emptyMessage : result.text
        }
        isSyncingSelection = false

        var finalStatus = status
        if feature == .redact, result.imageData != nil {
            finalStatus = result.boxes.isEmpty
                ? L("没有发现需要打码的内容", "Nothing to redact was found")
                : L("已打码 \(result.boxes.count) 处 · ", "Redacted \(result.boxes.count) region(s) · ") + status
        }
        endWork(status: finalStatus)
    }

    // MARK: - 文本行与检测框联动

    /// 点击原图上的检测框时，选中结果里对应的那一行
    private func selectResultLine(_ index: Int?) {
        guard let index = index,
              let output = output, output.linksLinesToBoxes,
              output.lines.indices.contains(index),
              let textView = resultTextView
        else { return }

        var location = 0
        for line in output.lines.prefix(index) {
            location += (line as NSString).length + 1
        }
        let range = NSRange(location: location, length: (output.lines[index] as NSString).length)
        guard NSMaxRange(range) <= (textView.string as NSString).length else { return }

        isSyncingSelection = true
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        isSyncingSelection = false
    }

    /// 在结果文本中移动光标或选择时，高亮原图上对应的检测框
    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isSyncingSelection,
              let output = output, output.linksLinesToBoxes,
              let textView = resultTextView
        else { return }

        let text = textView.string as NSString
        let location = min(textView.selectedRange().location, text.length)
        let lineIndex = text.substring(to: location).components(separatedBy: "\n").count - 1
        sourceCanvas.highlightedIndex = output.boxes.indices.contains(lineIndex) ? lineIndex : nil
    }

    // MARK: - 界面状态

    private func updateControls() {
        let isOCR = feature == .ocr
        languagePopup.isHidden = !isOCR
        fastCheckbox.isHidden = !isOCR
        redactionPopup.isHidden = feature != .redact

        // 有结果时按结果类型决定显示图片还是文本，没有结果时按当前功能决定
        let showsImage: Bool
        if let output = output {
            showsImage = output.imageData != nil
        } else {
            showsImage = feature == .backgroundRemoval || feature == .redact
        }
        resultCanvas.isHidden = !showsImage
        resultScrollView.isHidden = showsImage
        resultCanvas.showsCheckerboard = feature == .backgroundRemoval

        if let output = output, output.imageData == nil, !output.lines.isEmpty {
            resultCountLabel.stringValue = L("\(output.lines.count) 行", "\(output.lines.count) line(s)")
        } else {
            resultCountLabel.stringValue = ""
        }

        let hasPDF = pdf != nil
        for control in [previousPageButton, nextPageButton, pageLabel, extractTextButton, recognizeAllButton] as [NSView] {
            control.isHidden = !hasPDF
        }
        if let state = pdf {
            pageLabel.stringValue = L(
                "第 \(state.pageIndex + 1) / \(state.pageCount) 页",
                "Page \(state.pageIndex + 1) of \(state.pageCount)"
            )
            previousPageButton.isEnabled = !isBusy && state.pageIndex > 0
            nextPageButton.isEnabled = !isBusy && state.pageIndex < state.pageCount - 1
            extractTextButton.isEnabled = !isBusy
            recognizeAllButton.isEnabled = !isBusy
        }

        let showsContextBar = hasPDF || isOCR || feature == .redact
        if contextBar.isHidden == showsContextBar {
            // 先停用再启用，避免两条约束同时生效
            panesTopWithoutContextBar?.isActive = false
            panesTopWithContextBar?.isActive = false
            contextBar.isHidden = !showsContextBar
            (showsContextBar ? panesTopWithContextBar : panesTopWithoutContextBar)?.isActive = true
        }

        updateInsightsPopup()
        onStateChange?()
    }

    /// 结果里有链接、电话、日期或地址时，在状态行右侧提供一个下拉按钮
    private func updateInsightsPopup() {
        let insights = output?.insights ?? []
        insightsPopup.removeAllItems()
        insightsPopup.isHidden = insights.isEmpty
        guard !insights.isEmpty else { return }

        insightsPopup.addItem(withTitle: L("发现 \(insights.count) 项可操作内容", "\(insights.count) actionable item(s)"))
        for insight in insights {
            let kind: String
            switch insight.kind {
            case .link: kind = L("打开链接", "Open Link")
            case .phoneNumber: kind = L("拨打电话", "Call")
            case .date: kind = L("复制日期", "Copy Date")
            case .address: kind = L("在地图中查看", "Show in Maps")
            }
            var value = insight.value
            if value.count > 48 {
                value = String(value.prefix(48)) + "…"
            }
            insightsPopup.addItem(withTitle: kind + "：" + value)
        }
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }
}
