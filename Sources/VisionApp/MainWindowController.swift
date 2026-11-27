import AppKit

/// 承载各个页面的容器：同一时间只显示一个页面
final class PageContainerViewController: NSViewController {
    private let pages: [NSViewController]

    init(pages: [NSViewController]) {
        self.pages = pages
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 880, height: 680))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        for page in pages {
            addChild(page)
            page.view.translatesAutoresizingMaskIntoConstraints = false
            page.view.isHidden = true
            view.addSubview(page.view)
            NSLayoutConstraint.activate([
                // 窗口内容延伸到工具栏下方，页面从安全区域的顶部开始排
                page.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                page.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                page.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                page.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
    }

    func show(_ page: NSViewController) {
        _ = view
        for candidate in pages {
            candidate.view.isHidden = candidate !== page
        }
    }
}

/// 主窗口：左侧是侧边栏，右侧是当前页面，顶部是统一工具栏
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private enum Item {
        static let open = NSToolbarItem.Identifier("open")
        static let paste = NSToolbarItem.Identifier("paste")
        static let capture = NSToolbarItem.Identifier("capture")
        static let copy = NSToolbarItem.Identifier("copy")
        static let json = NSToolbarItem.Identifier("json")
        static let searchablePDF = NSToolbarItem.Identifier("searchablePDF")
        static let save = NSToolbarItem.Identifier("save")
        static let run = NSToolbarItem.Identifier("run")
    }

    let recognition: RecognitionViewController
    private let batch: BatchViewController
    private let server: ServerViewController
    private let sidebar: SidebarViewController
    private let container: PageContainerViewController
    private var toolbarItems: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private(set) var destination: Destination = .feature(Settings.defaultFeature)

    /// 点击工具栏的截屏按钮时调用
    var onCaptureScreen: (() -> Void)?

    init() {
        // 在调用 super.init 之前只能使用局部变量
        let recognition = RecognitionViewController()
        let batch = BatchViewController()
        let server = ServerViewController()
        let sidebar = SidebarViewController()
        let container = PageContainerViewController(pages: [recognition, batch, server])
        self.recognition = recognition
        self.batch = batch
        self.server = server
        self.sidebar = sidebar
        self.container = container

        let splitViewController = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 190
        sidebarItem.maximumThickness = 280
        splitViewController.addSplitViewItem(sidebarItem)
        let contentItem = NSSplitViewItem(viewController: container)
        contentItem.minimumThickness = 620
        splitViewController.addSplitViewItem(contentItem)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1140, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Vision"
        // 窗口由本控制器持有，关闭后不能被系统再释放一次
        window.isReleasedWhenClosed = false
        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 1140, height: 720))
        window.toolbarStyle = .unified
        window.center()

        super.init(window: window)

        let toolbar = NSToolbar(identifier: "VisionMainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        sidebar.onSelect = { [weak self] destination in
            self?.show(destination, updatingSidebar: false)
        }
        recognition.onStateChange = { [weak self] in
            self?.updateToolbar()
        }
        show(destination, updatingSidebar: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - 页面切换

    func show(_ destination: Destination) {
        show(destination, updatingSidebar: true)
    }

    private func show(_ destination: Destination, updatingSidebar: Bool) {
        self.destination = destination
        if updatingSidebar {
            _ = sidebar.view
            sidebar.select(destination)
        }
        switch destination {
        case .feature(let feature):
            container.show(recognition)
            recognition.setFeature(feature)
            window?.title = recognition.documentName.isEmpty ? "Vision" : recognition.documentName
            window?.subtitle = feature.title
        case .batch:
            container.show(batch)
            window?.title = destination.title
            window?.subtitle = ""
        case .server:
            container.show(server)
            window?.title = destination.title
            window?.subtitle = ""
        }
        updateToolbar()
    }

    // MARK: - 工具栏

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            Item.open, Item.paste, Item.capture,
            .flexibleSpace,
            Item.copy, Item.json, Item.searchablePDF, Item.save,
            .space,
            Item.run,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item: NSToolbarItem
        switch itemIdentifier {
        case Item.open:
            item = makeItem(itemIdentifier, L("打开…", "Open…"), "folder", #selector(openDocument(_:)))
        case Item.paste:
            item = makeItem(itemIdentifier, L("粘贴图片", "Paste Image"), "doc.on.clipboard", #selector(pasteImage(_:)))
        case Item.capture:
            item = makeItem(itemIdentifier, L("截屏识别", "Capture Screen"), "camera.viewfinder", #selector(captureScreen(_:)))
        case Item.copy:
            item = makeItem(itemIdentifier, L("复制结果", "Copy Result"), "doc.on.doc", #selector(copyResult(_:)))
        case Item.json:
            item = makeItem(itemIdentifier, L("导出 JSON…", "Export JSON…"), "curlybraces", #selector(exportJSON(_:)))
        case Item.searchablePDF:
            item = makeItem(
                itemIdentifier,
                L("导出可搜索 PDF…", "Export Searchable PDF…"),
                "doc.text.magnifyingglass",
                #selector(exportSearchablePDF(_:))
            )
        case Item.save:
            item = makeItem(itemIdentifier, L("保存结果…", "Save Result…"), "square.and.arrow.down", #selector(saveDocument(_:)))
        case Item.run:
            item = makeItem(itemIdentifier, L("识别", "Run"), "play.fill", #selector(runAnalysis(_:)))
        default:
            return nil
        }
        toolbarItems[itemIdentifier] = item
        updateToolbar()
        return item
    }

    private func makeItem(
        _ identifier: NSToolbarItem.Identifier,
        _ label: String,
        _ symbolName: String,
        _ action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        // 可用状态由 updateToolbar 手动维护
        item.autovalidates = false
        return item
    }

    /// 按当前页面和识别状态更新工具栏按钮是否可用
    private func updateToolbar() {
        var onRecognitionPage = false
        if case .feature = destination {
            onRecognitionPage = true
        }
        let idle = onRecognitionPage && !recognition.isBusy
        toolbarItems[Item.open]?.isEnabled = onRecognitionPage
        toolbarItems[Item.paste]?.isEnabled = onRecognitionPage
        toolbarItems[Item.capture]?.isEnabled = true
        toolbarItems[Item.copy]?.isEnabled = onRecognitionPage && recognition.hasOutput
        toolbarItems[Item.json]?.isEnabled = onRecognitionPage && recognition.hasJSON
        toolbarItems[Item.searchablePDF]?.isEnabled = idle && recognition.hasSource
        toolbarItems[Item.save]?.isEnabled = onRecognitionPage && recognition.hasOutput
        toolbarItems[Item.run]?.isEnabled = idle && recognition.hasSource
    }

    // MARK: - 动作（工具栏和菜单共用）

    /// 需要在识别页面上执行的动作：不在识别页面时先切回去
    private func showRecognitionPage() {
        if case .feature = destination { return }
        show(.feature(recognition.feature))
    }

    @objc func openDocument(_ sender: Any?) {
        showRecognitionPage()
        recognition.openDocument(sender)
    }

    @objc func pasteImage(_ sender: Any?) {
        showRecognitionPage()
        recognition.pasteImage(sender)
    }

    @objc func captureScreen(_ sender: Any?) {
        onCaptureScreen?()
    }

    @objc func copyResult(_ sender: Any?) {
        recognition.copyResult(sender)
    }

    @objc func exportJSON(_ sender: Any?) {
        recognition.exportJSON(sender)
    }

    @objc func exportSearchablePDF(_ sender: Any?) {
        recognition.exportSearchablePDF(sender)
    }

    @objc func saveDocument(_ sender: Any?) {
        recognition.saveDocument(sender)
    }

    @objc func runAnalysis(_ sender: Any?) {
        recognition.runAnalysis(sender)
    }

    /// 载入文件并切到识别页面
    func open(_ url: URL) {
        showRecognitionPage()
        recognition.loadFile(at: url)
    }

    /// 载入截图并切到文字识别
    func loadCapturedImage(_ data: Data) {
        show(.feature(.ocr))
        recognition.loadImage(data: data, name: L("屏幕截图", "Screenshot"))
    }
}
