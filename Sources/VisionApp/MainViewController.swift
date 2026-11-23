import AppKit
import UniformTypeIdentifiers
import VisionCore

/// 主界面：顶部选择功能，左侧显示原图（或 PDF 页面），右侧显示结果
final class MainViewController: NSViewController, NSTextViewDelegate {
    private struct PDFState {
        var data: Data
        var pageCount: Int
        var pageIndex: Int
    }

    // MARK: - 控件

    private let featureControl = NSSegmentedControl(
        labels: VisionFeature.allCases.map { $0.title },
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fastCheckbox = NSButton(checkboxWithTitle: L("快速模式", "Fast"), target: nil, action: nil)

    private let previousPageButton = NSButton(title: "◀", target: nil, action: nil)
    private let nextPageButton = NSButton(title: "▶", target: nil, action: nil)
    private let pageLabel = NSTextField(labelWithString: "")
    private let extractTextButton = NSButton(
        title: L("提取内嵌文本", "Extract Embedded Text"), target: nil, action: nil
    )
    private let recognizeAllButton = NSButton(
        title: L("识别全部页面", "Recognize All Pages"), target: nil, action: nil
    )
    private var pdfBar = NSStackView()

    private let sourceCanvas = ImageCanvasView()
    private let resultCanvas = ImageCanvasView()
    private let resultScrollView = NSTextView.scrollableTextView()

    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: L("复制结果", "Copy"), target: nil, action: nil)
    private let jsonButton = NSButton(title: L("导出 JSON…", "Export JSON…"), target: nil, action: nil)
    private let saveButton = NSButton(title: L("保存结果…", "Save…"), target: nil, action: nil)
    private let runButton = NSButton(title: L("开始识别", "Run"), target: nil, action: nil)

    private var panesTopWithoutPDFBar: NSLayoutConstraint?
    private var panesTopWithPDFBar: NSLayoutConstraint?

    private var resultTextView: NSTextView? {
        resultScrollView.documentView as? NSTextView
    }

    // MARK: - 状态

    /// 当前用于识别的图片数据；打开 PDF 时为当前页渲染出的 PNG
    private var imageData: Data?
    private var pdf: PDFState?
    private var documentName = ""
    private var output: AnalysisOutput?
    /// 每次开始新的后台任务时递增，用来丢弃过期的结果
    private var runToken = 0
    private var isBusy = false
    private var isSyncingSelection = false

    private var currentFeature: VisionFeature {
        VisionFeature(rawValue: featureControl.selectedSegment) ?? .ocr
    }

    private var currentOptions: TextRecognitionOptions {
        TextRecognitionOptions(
            languages: OCRLanguage.codes(at: languagePopup.indexOfSelectedItem),
            fast: fastCheckbox.state == .on
        )
    }

    // MARK: - 视图搭建

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1080, height: 680))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureControls()
        layoutControls()
        updateControls()
        setStatus(L("请打开一张图片或 PDF 开始", "Open an image or PDF to begin"))
    }

    private func configureControls() {
        featureControl.selectedSegment = Settings.defaultFeature.rawValue
        featureControl.target = self
        featureControl.action = #selector(featureChanged(_:))

        for option in OCRLanguage.options {
            languagePopup.addItem(withTitle: option.title)
        }
        languagePopup.selectItem(at: Settings.ocrLanguageIndex)
        languagePopup.target = self
        languagePopup.action = #selector(optionChanged(_:))
        fastCheckbox.state = Settings.ocrFastMode ? .on : .off
        fastCheckbox.target = self
        fastCheckbox.action = #selector(optionChanged(_:))

        previousPageButton.target = self
        previousPageButton.action = #selector(previousPage(_:))
        nextPageButton.target = self
        nextPageButton.action = #selector(nextPage(_:))
        extractTextButton.target = self
        extractTextButton.action = #selector(extractPDFText(_:))
        recognizeAllButton.target = self
        recognizeAllButton.action = #selector(recognizeAllPages(_:))

        sourceCanvas.placeholder = L(
            "把图片或 PDF 拖到这里\n或点击「打开…」/ 按 ⌘V 粘贴",
            "Drop an image or PDF here\nor click “Open…” / press ⌘V to paste"
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
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.delegate = self
        }
        resultScrollView.borderType = .bezelBorder

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        copyButton.target = self
        copyButton.action = #selector(copyResult(_:))
        jsonButton.target = self
        jsonButton.action = #selector(exportJSON(_:))
        saveButton.target = self
        saveButton.action = #selector(saveDocument(_:))
        runButton.target = self
        runButton.action = #selector(runAnalysis(_:))
        runButton.keyEquivalent = "\r"
    }

    private func layoutControls() {
        let openButton = NSButton(title: L("打开…", "Open…"), target: self, action: #selector(openDocument(_:)))
        let pasteButton = NSButton(title: L("粘贴", "Paste"), target: self, action: #selector(pasteImage(_:)))
        let captureButton = NSButton(
            title: L("截屏识别", "Capture Screen"), target: self, action: #selector(captureScreen(_:))
        )

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let topBar = NSStackView(views: [featureControl, topSpacer, languagePopup, fastCheckbox])
        topBar.orientation = .horizontal
        topBar.spacing = 10

        let pdfSpacer = NSView()
        pdfSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        pdfBar = NSStackView(views: [
            previousPageButton, pageLabel, nextPageButton, extractTextButton, recognizeAllButton, pdfSpacer,
        ])
        pdfBar.orientation = .horizontal
        pdfBar.spacing = 10

        let resultContainer = NSView()
        for subview in [resultScrollView, resultCanvas] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            resultContainer.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: resultContainer.topAnchor),
                subview.bottomAnchor.constraint(equalTo: resultContainer.bottomAnchor),
                subview.leadingAnchor.constraint(equalTo: resultContainer.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: resultContainer.trailingAnchor),
            ])
        }

        let panes = NSStackView(views: [sourceCanvas, resultContainer])
        panes.orientation = .horizontal
        panes.distribution = .fillEqually
        panes.spacing = 12

        let bottomBar = NSStackView(views: [
            openButton, pasteButton, captureButton, spinner, statusLabel,
            copyButton, jsonButton, saveButton, runButton,
        ])
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 10

        for row in [topBar, pdfBar, panes, bottomBar] {
            row.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            ])
        }

        // PDF 工具栏只在打开 PDF 时显示，隐藏时双栏区域直接贴着顶部工具栏
        let withoutPDFBar = panes.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10)
        let withPDFBar = panes.topAnchor.constraint(equalTo: pdfBar.bottomAnchor, constant: 10)
        panesTopWithoutPDFBar = withoutPDFBar
        panesTopWithPDFBar = withPDFBar

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            pdfBar.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            withoutPDFBar,
            bottomBar.topAnchor.constraint(equalTo: panes.bottomAnchor, constant: 10),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            panes.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            sourceCanvas.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 940),
        ])
        pdfBar.isHidden = true
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

    private func loadImage(data: Data, name: String) {
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
        var title = "Vision"
        if !documentName.isEmpty {
            title += " — " + documentName
        }
        view.window?.title = title
    }

    // MARK: - 菜单与按钮动作

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

    /// 框选屏幕区域并对截图做文字识别
    @objc func captureScreen(_ sender: Any?) {
        // 先隐藏本应用，避免窗口挡住要截取的内容
        NSApp.hide(nil)
        Task { [weak self] in
            let data = await ScreenCapture.captureInteractively()
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            guard let self = self else { return }
            self.view.window?.makeKeyAndOrderFront(nil)
            guard let data = data else {
                self.setStatus(L("已取消截屏", "Screen capture cancelled"))
                return
            }
            self.featureControl.selectedSegment = VisionFeature.ocr.rawValue
            self.loadImage(data: data, name: L("屏幕截图", "Screenshot"))
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

    private func save(_ data: Data, as type: UTType, fileExtension: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        let baseName = documentName.isEmpty
            ? "result"
            : (documentName as NSString).deletingPathExtension
        panel.nameFieldStringValue = baseName + "-result." + fileExtension
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

    @objc private func featureChanged(_ sender: Any?) {
        updateControls()
        if imageData != nil {
            run()
        }
    }

    @objc private func optionChanged(_ sender: Any?) {
        if imageData != nil, currentFeature == .ocr {
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

    // MARK: - 执行识别

    private func run() {
        guard let data = imageData else {
            setStatus(L("请先打开一张图片或 PDF", "Open an image or PDF first"))
            return
        }
        let feature = currentFeature
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
                self.present(output, status: L(
                    "\(feature.title)完成，用时 \(elapsed) 秒",
                    "\(feature.title) finished in \(elapsed)s"
                ))
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
                    lines.append(MainViewController.pageHeader(page.pageNumber))
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
                        json: try? JSONEncoder().encode(response)
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
        let options = currentOptions

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
                    lines.append(MainViewController.pageHeader(index + 1))
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
                AnalysisOutput(lines: lines),
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

        endWork(status: status)
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
        let feature = currentFeature
        let isOCR = feature == .ocr
        languagePopup.isHidden = !isOCR
        fastCheckbox.isHidden = !isOCR

        // 有结果时按结果类型决定显示图片还是文本，没有结果时按当前功能决定
        let showsImage: Bool
        if let output = output {
            showsImage = output.imageData != nil
        } else {
            showsImage = feature == .backgroundRemoval
        }
        resultCanvas.isHidden = !showsImage
        resultScrollView.isHidden = showsImage

        let hasPDF = pdf != nil
        if pdfBar.isHidden == hasPDF {
            // 先停用再启用，避免两条约束同时生效
            panesTopWithoutPDFBar?.isActive = false
            panesTopWithPDFBar?.isActive = false
            pdfBar.isHidden = !hasPDF
            (hasPDF ? panesTopWithPDFBar : panesTopWithoutPDFBar)?.isActive = true
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

        copyButton.isEnabled = output != nil
        saveButton.isEnabled = output != nil
        jsonButton.isEnabled = output?.json != nil
        runButton.isEnabled = imageData != nil && !isBusy
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }
}
