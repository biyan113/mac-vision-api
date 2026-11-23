import AppKit
import UniformTypeIdentifiers
import VisionCore

/// 批量处理：对多个图片或 PDF 执行同一功能，结果写入输出目录
final class BatchViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum ItemStatus {
        case pending
        case running
        case done(String)
        case failed(String)

        var text: String {
            switch self {
            case .pending: return L("等待中", "Pending")
            case .running: return L("处理中…", "Processing…")
            case .done(let summary): return "✓ " + summary
            case .failed(let message): return "✗ " + message
            }
        }
    }

    private struct Item {
        let url: URL
        var status: ItemStatus = .pending
    }

    private static let fileColumn = NSUserInterfaceItemIdentifier("file")
    private static let statusColumn = NSUserInterfaceItemIdentifier("status")

    private let featurePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let addFilesButton = NSButton(title: L("添加文件…", "Add Files…"), target: nil, action: nil)
    private let addFolderButton = NSButton(title: L("添加文件夹…", "Add Folder…"), target: nil, action: nil)
    private let clearButton = NSButton(title: L("清空列表", "Clear List"), target: nil, action: nil)
    private let tableView = NSTableView()
    private let outputLabel = NSTextField(labelWithString: "")
    private let chooseOutputButton = NSButton(title: L("选择输出目录…", "Choose Output Folder…"), target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let startButton = NSButton(title: "", target: nil, action: nil)

    private var items: [Item] = []
    private var outputDirectory: URL?
    private var isRunning = false
    private var isCancelled = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        for feature in VisionFeature.allCases {
            featurePopup.addItem(withTitle: feature.title)
        }
        featurePopup.selectItem(at: Settings.defaultFeature.rawValue)

        addFilesButton.target = self
        addFilesButton.action = #selector(addFiles(_:))
        addFolderButton.target = self
        addFolderButton.action = #selector(addFolder(_:))
        clearButton.target = self
        clearButton.action = #selector(clearList(_:))
        chooseOutputButton.target = self
        chooseOutputButton.action = #selector(chooseOutput(_:))
        startButton.target = self
        startButton.action = #selector(startOrStop(_:))

        let fileColumn = NSTableColumn(identifier: BatchViewController.fileColumn)
        fileColumn.title = L("文件", "File")
        fileColumn.width = 320
        fileColumn.isEditable = false
        let statusColumn = NSTableColumn(identifier: BatchViewController.statusColumn)
        statusColumn.title = L("状态", "Status")
        statusColumn.width = 340
        statusColumn.isEditable = false
        tableView.addTableColumn(fileColumn)
        tableView.addTableColumn(statusColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        outputLabel.lineBreakMode = .byTruncatingMiddle
        outputLabel.textColor = .secondaryLabelColor
        outputLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        outputLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let topRow = NSStackView(views: [
            NSTextField(labelWithString: L("功能", "Feature")), featurePopup, topSpacer,
            addFilesButton, addFolderButton, clearButton,
        ])
        topRow.orientation = .horizontal
        topRow.spacing = 8

        let outputRow = NSStackView(views: [
            NSTextField(labelWithString: L("输出到", "Output")), outputLabel, chooseOutputButton,
        ])
        outputRow.orientation = .horizontal
        outputRow.spacing = 8

        let bottomRow = NSStackView(views: [statusLabel, startButton])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 8

        let rows: [NSView] = [topRow, scrollView, outputRow, progressIndicator, bottomRow]
        var previous: NSView?
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
            if let previous = previous {
                row.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: 10).isActive = true
            } else {
                row.topAnchor.constraint(equalTo: view.topAnchor, constant: 16).isActive = true
            }
            previous = row
        }
        NSLayoutConstraint.activate([
            bottomRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 680),
        ])

        refresh()
    }

    // MARK: - 列表

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard items.indices.contains(row) else { return nil }
        if tableColumn?.identifier == BatchViewController.fileColumn {
            return items[row].url.lastPathComponent
        }
        return items[row].status.text
    }

    private static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    private func append(_ urls: [URL]) {
        let existing = Set(items.map { $0.url })
        for url in urls where !existing.contains(url) {
            items.append(Item(url: url))
        }
        tableView.reloadData()
        refresh()
    }

    // MARK: - 动作

    @objc private func addFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            append(panel.urls)
        }
    }

    @objc private func addFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let supported = contents
            .filter { BatchViewController.isSupported($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if supported.isEmpty {
            statusLabel.stringValue = L("这个文件夹里没有图片或 PDF", "No images or PDFs in this folder")
        } else {
            append(supported)
        }
    }

    @objc private func clearList(_ sender: Any?) {
        items.removeAll()
        tableView.reloadData()
        progressIndicator.doubleValue = 0
        refresh()
    }

    @objc private func chooseOutput(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            refresh()
        }
    }

    @objc private func startOrStop(_ sender: Any?) {
        if isRunning {
            isCancelled = true
            statusLabel.stringValue = L("正在停止，等待当前文件处理完成…", "Stopping after the current file…")
            startButton.isEnabled = false
        } else {
            start()
        }
    }

    // MARK: - 执行

    private func start() {
        guard !items.isEmpty else { return }
        guard let outputDirectory = outputDirectory else {
            statusLabel.stringValue = L("请先选择输出目录", "Choose an output folder first")
            return
        }
        let feature = VisionFeature(rawValue: featurePopup.indexOfSelectedItem) ?? .ocr
        let options = TextRecognitionOptions(
            languages: OCRLanguage.codes(at: Settings.ocrLanguageIndex),
            fast: Settings.ocrFastMode
        )

        for index in items.indices {
            items[index].status = .pending
        }
        tableView.reloadData()
        isRunning = true
        isCancelled = false
        progressIndicator.doubleValue = 0
        refresh()

        let total = items.count
        Task { [weak self] in
            var succeeded = 0
            var processed = 0
            for index in 0..<total {
                guard let controller = self, !controller.isCancelled, controller.items.indices.contains(index) else {
                    break
                }
                let url = controller.items[index].url
                controller.setStatus(.running, at: index)
                controller.statusLabel.stringValue = L(
                    "正在处理 \(index + 1)/\(total)：\(url.lastPathComponent)",
                    "Processing \(index + 1) of \(total): \(url.lastPathComponent)"
                )

                let result = await Background.run {
                    try BatchProcessor.process(
                        url: url,
                        feature: feature,
                        options: options,
                        outputDirectory: outputDirectory
                    )
                }
                switch result {
                case .success(let summary):
                    succeeded += 1
                    controller.setStatus(.done(summary), at: index)
                case .failure(let error):
                    controller.setStatus(.failed(error.message), at: index)
                }
                processed += 1
                controller.progressIndicator.doubleValue = Double(processed) / Double(total)
            }

            guard let controller = self else { return }
            controller.isRunning = false
            controller.statusLabel.stringValue = L(
                "已处理 \(processed)/\(total) 个文件，成功 \(succeeded) 个",
                "Processed \(processed) of \(total) file(s), \(succeeded) succeeded"
            )
            controller.refresh()
        }
    }

    private func setStatus(_ status: ItemStatus, at index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].status = status
        tableView.reloadData(
            forRowIndexes: IndexSet(integer: index),
            columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
        )
        tableView.scrollRowToVisible(index)
    }

    private func refresh() {
        outputLabel.stringValue = outputDirectory?.path ?? L("（未选择）", "(not selected)")
        startButton.title = isRunning ? L("停止", "Stop") : L("开始处理", "Start")
        startButton.isEnabled = isRunning || !items.isEmpty
        featurePopup.isEnabled = !isRunning
        addFilesButton.isEnabled = !isRunning
        addFolderButton.isEnabled = !isRunning
        clearButton.isEnabled = !isRunning && !items.isEmpty
        chooseOutputButton.isEnabled = !isRunning
    }
}

/// 处理单个文件并把结果写入输出目录。同步执行，应在后台线程调用。
enum BatchProcessor {
    /// - Returns: 写入的文件名摘要，用于在列表中显示
    static func process(
        url: URL,
        feature: VisionFeature,
        options: TextRecognitionOptions,
        outputDirectory: URL
    ) throws -> String {
        let data = try Data(contentsOf: url)
        let baseName = url.deletingPathExtension().lastPathComponent

        guard PDFEngine.looksLikePDF(data) else {
            let output = try Analyzer.run(feature, imageData: data, options: options)
            let destination = try write(output, feature: feature, baseName: baseName, to: outputDirectory)
            return destination.lastPathComponent
        }

        let pageCount = try PDFEngine.pageCount(pdfData: data)

        // 文字识别：所有页面合并为一个文本文件
        if feature == .ocr {
            var pages: [String] = []
            for index in 0..<pageCount {
                let png = try PDFEngine.renderPage(pdfData: data, pageIndex: index, dpi: 150)
                pages.append(try Analyzer.run(.ocr, imageData: png, options: options).text)
            }
            let destination = uniqueURL(baseName: baseName, fileExtension: "txt", in: outputDirectory)
            try Data(pages.joined(separator: "\n\n").utf8).write(to: destination, options: .atomic)
            return destination.lastPathComponent
        }

        // 其他功能：每页输出一个文件
        var written = 0
        for index in 0..<pageCount {
            let png = try PDFEngine.renderPage(pdfData: data, pageIndex: index, dpi: 150)
            let output = try Analyzer.run(feature, imageData: png, options: options)
            _ = try write(output, feature: feature, baseName: "\(baseName)-p\(index + 1)", to: outputDirectory)
            written += 1
        }
        return L("\(written) 个文件（每页一个）", "\(written) file(s), one per page")
    }

    private static func write(
        _ output: AnalysisOutput,
        feature: VisionFeature,
        baseName: String,
        to directory: URL
    ) throws -> URL {
        let data: Data
        switch feature {
        case .ocr:
            data = Data(output.text.utf8)
        case .backgroundRemoval:
            data = output.imageData ?? Data()
        case .classify, .detectObjects, .barcode:
            data = output.json ?? Data("{}".utf8)
        }
        let destination = uniqueURL(baseName: baseName, fileExtension: feature.outputExtension, in: directory)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// 生成不会覆盖已有文件的路径，重名时追加序号
    private static func uniqueURL(baseName: String, fileExtension: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(counter)")
                .appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }
}
