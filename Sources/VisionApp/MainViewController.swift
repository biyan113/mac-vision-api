import AppKit
import UniformTypeIdentifiers

/// 主界面：顶部选择功能，左侧显示原图，右侧显示结果
final class MainViewController: NSViewController {
    private enum Outcome: Sendable {
        case success(VisionOutput)
        case failure(String)
    }

    private static let languageOptions: [(title: String, codes: [String])] = [
        ("自动检测语言", []),
        ("简体中文 + 英文", ["zh-Hans", "en-US"]),
        ("繁體中文 + 英文", ["zh-Hant", "en-US"]),
        ("English", ["en-US"]),
        ("日本語", ["ja-JP"]),
        ("한국어", ["ko-KR"]),
    ]

    // MARK: - 控件

    private let featureControl = NSSegmentedControl(
        labels: VisionFeature.allCases.map { $0.title },
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fastCheckbox = NSButton(checkboxWithTitle: "快速模式", target: nil, action: nil)

    private let sourceCanvas = ImageCanvasView()
    private let resultCanvas = ImageCanvasView()
    private let resultScrollView = NSTextView.scrollableTextView()

    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "复制结果", target: nil, action: nil)
    private let saveButton = NSButton(title: "保存结果…", target: nil, action: nil)
    private let runButton = NSButton(title: "开始识别", target: nil, action: nil)

    private var resultTextView: NSTextView? {
        resultScrollView.documentView as? NSTextView
    }

    // MARK: - 状态

    private var imageData: Data?
    private var output: VisionOutput?
    /// 每次运行递增，用来丢弃过期的后台结果
    private var runToken = 0

    private var currentFeature: VisionFeature {
        VisionFeature(rawValue: featureControl.selectedSegment) ?? .ocr
    }

    // MARK: - 视图搭建

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 640))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        featureControl.selectedSegment = 0
        featureControl.target = self
        featureControl.action = #selector(featureChanged(_:))

        for option in Self.languageOptions {
            languagePopup.addItem(withTitle: option.title)
        }
        languagePopup.target = self
        languagePopup.action = #selector(optionChanged(_:))
        fastCheckbox.target = self
        fastCheckbox.action = #selector(optionChanged(_:))

        sourceCanvas.placeholder = "把图片拖到这里\n或点击「打开图片…」/ 按 ⌘V 粘贴"
        sourceCanvas.onDropImage = { [weak self] url in
            self?.loadImage(from: url)
        }
        resultCanvas.placeholder = "处理结果会显示在这里"
        resultCanvas.isHidden = true

        if let textView = resultTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.textContainerInset = NSSize(width: 8, height: 8)
        }
        resultScrollView.borderType = .bezelBorder

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let openButton = NSButton(title: "打开图片…", target: self, action: #selector(openDocument(_:)))
        let pasteButton = NSButton(title: "粘贴图片", target: self, action: #selector(pasteImage(_:)))
        copyButton.target = self
        copyButton.action = #selector(copyResult(_:))
        saveButton.target = self
        saveButton.action = #selector(saveDocument(_:))
        runButton.target = self
        runButton.action = #selector(runAnalysis(_:))
        runButton.keyEquivalent = "\r"

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let topBar = NSStackView(views: [featureControl, topSpacer, languagePopup, fastCheckbox])
        topBar.orientation = .horizontal
        topBar.spacing = 10

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
            openButton, pasteButton, spinner, statusLabel, copyButton, saveButton, runButton,
        ])
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 10

        for row in [topBar, panes, bottomBar] {
            row.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            ])
        }
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            panes.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            bottomBar.topAnchor.constraint(equalTo: panes.bottomAnchor, constant: 10),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            panes.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            sourceCanvas.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 820),
        ])

        updateControls()
        setStatus("请打开一张图片开始")
    }

    // MARK: - 载入图片

    func loadImage(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            loadImage(data: data, name: url.lastPathComponent)
        } catch {
            setStatus("无法读取文件：\(error.localizedDescription)")
        }
    }

    private func loadImage(data: Data, name: String) {
        guard let image = NSImage(data: data) else {
            setStatus("无法识别的图片格式：\(name)")
            return
        }
        imageData = data
        sourceCanvas.image = image
        view.window?.title = "Vision — \(name)"
        run()
    }

    // MARK: - 动作

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            loadImage(from: url)
        }
    }

    @objc func pasteImage(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           let url = urls.first {
            loadImage(from: url)
        } else if let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation {
            loadImage(data: data, name: "剪贴板图片")
        } else {
            setStatus("剪贴板里没有图片")
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
        setStatus("结果已复制到剪贴板")
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let output = output else { return }
        let panel = NSSavePanel()
        let data: Data
        if let imageData = output.imageData {
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "result.png"
            data = imageData
        } else {
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "result.txt"
            data = Data(output.text.utf8)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            setStatus("已保存到 \(url.path)")
        } catch {
            setStatus("保存失败：\(error.localizedDescription)")
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

    // MARK: - 执行 Vision 请求

    private func run() {
        guard let data = imageData else {
            setStatus("请先打开一张图片")
            return
        }
        let feature = currentFeature
        let languageIndex = max(0, languagePopup.indexOfSelectedItem)
        let options = OCROptions(
            languages: Self.languageOptions[languageIndex].codes,
            fast: fastCheckbox.state == .on
        )

        runToken += 1
        let token = runToken
        let started = Date()

        output = nil
        sourceCanvas.boxes = []
        spinner.startAnimation(nil)
        setStatus("正在处理：\(feature.title)…")
        updateControls()

        Task { [weak self] in
            let outcome: Outcome = await Task.detached(priority: .userInitiated) { () -> Outcome in
                do {
                    return Outcome.success(try VisionService.run(feature, imageData: data, options: options))
                } catch {
                    return Outcome.failure(error.localizedDescription)
                }
            }.value

            guard let self = self, self.runToken == token else { return }
            self.finish(outcome, feature: feature, elapsed: Date().timeIntervalSince(started))
        }
    }

    private func finish(_ outcome: Outcome, feature: VisionFeature, elapsed: TimeInterval) {
        spinner.stopAnimation(nil)
        switch outcome {
        case .success(let result):
            output = result
            sourceCanvas.boxes = result.boxes
            if let data = result.imageData {
                resultCanvas.image = NSImage(data: data)
            } else {
                resultTextView?.string = result.text.isEmpty ? "（没有识别到内容）" : result.text
            }
            setStatus(String(format: "%@完成，用时 %.2f 秒", feature.title, elapsed))
        case .failure(let message):
            output = nil
            resultCanvas.image = nil
            resultTextView?.string = ""
            setStatus("\(feature.title)失败：\(message)")
        }
        updateControls()
    }

    // MARK: - 界面状态

    private func updateControls() {
        let feature = currentFeature
        let isOCR = feature == .ocr
        languagePopup.isHidden = !isOCR
        fastCheckbox.isHidden = !isOCR

        let showsImage = feature == .backgroundRemoval
        resultCanvas.isHidden = !showsImage
        resultScrollView.isHidden = showsImage

        let hasOutput = output != nil
        copyButton.isEnabled = hasOutput
        saveButton.isEnabled = hasOutput
        runButton.isEnabled = imageData != nil
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }
}
