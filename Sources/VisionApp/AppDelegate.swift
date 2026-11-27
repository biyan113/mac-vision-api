import AppKit
import VisionCore

/// Vision 桌面应用（AppKit）入口
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var preferencesWindow: NSWindow?

    private var statusItem: NSStatusItem?
    /// 标题随服务状态变化的菜单项（主菜单和菜单栏图标菜单各一个）
    private var serverToggleItems: [NSMenuItem] = []
    private var serverStatusItems: [NSMenuItem] = []
    private let hotKey = GlobalHotKey()
    private var isTerminating = false
    private var isCapturing = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // 以 `swift run` 方式启动时没有 .app 包，需要手动声明为普通应用
        app.setActivationPolicy(.regular)
        app.run()
    }

    private var mainController: MainWindowController {
        if let controller = mainWindowController {
            return controller
        }
        let controller = MainWindowController()
        controller.onCaptureScreen = { [weak self] in
            self?.captureScreen(nil)
        }
        mainWindowController = controller
        return controller
    }

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 必须在创建任何 Logger 之前接管日志，服务页面才能显示运行日志
        ServerLogStore.installAsLoggingBackend()

        NSApp.mainMenu = makeMainMenu()
        updateStatusItem()
        updateGlobalHotKey()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(serverStateChanged(_:)),
            name: ServerController.stateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(globalHotKeyPressed(_:)),
            name: GlobalHotKey.pressedNotification,
            object: nil
        )
        refreshServerMenuItems()

        showMainWindow(nil)

        if Settings.startServerAtLaunch {
            ServerController.shared.start()
        }
    }

    /// 关闭窗口后应用继续运行，这样内嵌服务和全局快捷键可以留在后台
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow(nil)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        showMainWindow(nil)
        mainController.open(url)
    }

    /// 退出前先停止内嵌服务，释放端口
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ServerController.shared.state != .stopped, !isTerminating else {
            return .terminateNow
        }
        isTerminating = true
        Task {
            await ServerController.shared.stopAndWait()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - 窗口与导航

    @objc func showMainWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        mainController.showWindow(nil)
        mainController.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showBatchPage(_ sender: Any?) {
        showMainWindow(nil)
        mainController.show(.batch)
    }

    @objc func showServerPage(_ sender: Any?) {
        showMainWindow(nil)
        mainController.show(.server)
    }

    /// 「前往」菜单：菜单项的 tag 是功能的序号
    @objc func showFeature(_ sender: NSMenuItem) {
        guard let feature = VisionFeature(rawValue: sender.tag) else { return }
        showMainWindow(nil)
        mainController.show(.feature(feature))
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesWindow == nil {
            let controller = PreferencesViewController()
            controller.onMenuBarIconChanged = { [weak self] in
                self?.updateStatusItem()
            }
            controller.onGlobalHotKeyChanged = { [weak self] in
                self?.updateGlobalHotKey()
            }
            let window = NSWindow(contentViewController: controller)
            window.title = L("设置", "Settings")
            window.styleMask = [.titled, .closable]
            // 窗口由本类持有，关闭后不能被系统再释放一次
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 340))
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 主窗口动作（菜单统一经由这里转发）

    @objc func openDocument(_ sender: Any?) {
        showMainWindow(nil)
        mainController.openDocument(sender)
    }

    @objc func saveDocument(_ sender: Any?) {
        mainController.saveDocument(sender)
    }

    @objc func exportJSON(_ sender: Any?) {
        mainController.exportJSON(sender)
    }

    @objc func exportSearchablePDF(_ sender: Any?) {
        mainController.exportSearchablePDF(sender)
    }

    @objc func copyResult(_ sender: Any?) {
        mainController.copyResult(sender)
    }

    /// ⌘V：焦点在可编辑的文本框里时粘贴文本，否则把剪贴板里的图片载入主窗口
    @objc func pasteFromMenu(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSText, text.isEditable {
            text.paste(sender)
        } else {
            showMainWindow(nil)
            mainController.pasteImage(sender)
        }
    }

    // MARK: - 截屏识别

    /// 框选屏幕区域，把截图载入主窗口并识别文字
    @objc func captureScreen(_ sender: Any?) {
        guard !isCapturing else { return }
        isCapturing = true
        // 先隐藏本应用，避免窗口挡住要截取的内容
        NSApp.hide(nil)
        Task {
            let data = await ScreenCapture.captureInteractively()
            self.isCapturing = false
            NSApp.unhide(nil)
            guard let data = data else { return }
            self.showMainWindow(nil)
            self.mainController.loadCapturedImage(data)
        }
    }

    /// 框选屏幕区域，识别文字后直接放进剪贴板，不打开窗口
    @objc func captureScreenToClipboard(_ sender: Any?) {
        guard !isCapturing else { return }
        isCapturing = true
        let options = TextRecognitionOptions(
            languages: OCRLanguage.codes(at: Settings.ocrLanguageIndex),
            fast: Settings.ocrFastMode
        )
        Task {
            let data = await ScreenCapture.captureInteractively()
            self.isCapturing = false
            guard let data = data else { return }

            let result = await Background.run {
                try VisionEngine.recognizeText(imageData: data, options: options).map { $0.text }
            }
            switch result {
            case .success(let lines) where !lines.isEmpty:
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
                self.flashStatus(L("已复制 \(lines.count) 行", "Copied \(lines.count) line(s)"))
            case .success:
                NSSound.beep()
                self.flashStatus(L("没有识别到文字", "No text found"))
            case .failure:
                NSSound.beep()
                self.flashStatus(L("识别失败", "Recognition failed"))
            }
        }
    }

    @objc private func globalHotKeyPressed(_ notification: Notification) {
        captureScreenToClipboard(nil)
    }

    private func updateGlobalHotKey() {
        if Settings.usesGlobalHotKey {
            hotKey.register()
        } else {
            hotKey.unregister()
        }
    }

    /// 在菜单栏图标上短暂显示一条提示
    private func flashStatus(_ text: String) {
        guard let button = statusItem?.button else { return }
        button.title = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshServerMenuItems()
        }
    }

    // MARK: - 内嵌服务

    @objc func toggleServer(_ sender: Any?) {
        ServerController.shared.toggle()
    }

    @objc func openServerInBrowser(_ sender: Any?) {
        if ServerController.shared.isRunning, let url = ServerController.shared.baseURL {
            NSWorkspace.shared.open(url)
        } else {
            showServerPage(nil)
        }
    }

    @objc private func serverStateChanged(_ notification: Notification) {
        refreshServerMenuItems()
    }

    private func refreshServerMenuItems() {
        let controller = ServerController.shared
        let toggleTitle: String
        let canToggle: Bool
        switch controller.state {
        case .stopped:
            toggleTitle = L("启动 API 服务", "Start API Server")
            canToggle = true
        case .running:
            toggleTitle = L("停止 API 服务", "Stop API Server")
            canToggle = true
        case .starting:
            toggleTitle = L("正在启动…", "Starting…")
            canToggle = false
        case .stopping:
            toggleTitle = L("正在停止…", "Stopping…")
            canToggle = false
        }
        for item in serverToggleItems {
            item.title = toggleTitle
            item.isEnabled = canToggle
        }
        for item in serverStatusItems {
            item.title = controller.statusText
        }
        if let button = statusItem?.button {
            button.title = ""
            let symbol = controller.isRunning ? "text.viewfinder" : "viewfinder"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vision")
        }
    }

    // MARK: - 菜单栏图标

    private func updateStatusItem() {
        if Settings.showsMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.imagePosition = .imageLeading
            item.menu = makeStatusMenu()
            statusItem = item
            refreshServerMenuItems()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(makeItem(
            L("截屏识别并复制文字", "Capture Text to Clipboard") + "  " + GlobalHotKey.displayName,
            #selector(captureScreenToClipboard(_:))
        ))
        menu.addItem(makeItem(L("截屏并在窗口中识别", "Capture and Open in Window"), #selector(captureScreen(_:))))
        menu.addItem(.separator())

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        serverStatusItems.append(status)
        let toggle = makeItem("", #selector(toggleServer(_:)))
        menu.addItem(toggle)
        serverToggleItems.append(toggle)
        menu.addItem(makeItem(L("API 服务…", "API Server…"), #selector(showServerPage(_:))))
        menu.addItem(.separator())

        menu.addItem(makeItem(L("打开主窗口", "Open Main Window"), #selector(showMainWindow(_:))))
        menu.addItem(makeItem(L("批量处理…", "Batch Processing…"), #selector(showBatchPage(_:))))
        menu.addItem(makeItem(L("设置…", "Settings…"), #selector(showPreferences(_:))))
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L("退出 Vision", "Quit Vision"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        return menu
    }

    // MARK: - 主菜单

    /// 创建由本类处理的菜单项
    private func makeItem(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    /// 创建沿响应链分发的菜单项（由当前焦点所在的控件或系统处理）
    private func makeResponderItem(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(makeResponderItem(
            L("关于 Vision", "About Vision"),
            #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem(L("设置…", "Settings…"), #selector(showPreferences(_:)), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(makeResponderItem(L("隐藏 Vision", "Hide Vision"), #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(makeResponderItem(
            L("退出 Vision", "Quit Vision"),
            #selector(NSApplication.terminate(_:)),
            key: "q"
        ))
        addSubmenu(appMenu, to: mainMenu)

        let fileMenu = NSMenu(title: L("文件", "File"))
        fileMenu.addItem(makeItem(L("打开…", "Open…"), #selector(openDocument(_:)), key: "o"))
        fileMenu.addItem(makeItem(
            L("截屏识别", "Capture Screen"),
            #selector(captureScreen(_:)),
            key: "2",
            modifiers: [.command, .shift]
        ))
        fileMenu.addItem(makeItem(
            L("截屏识别并复制文字", "Capture Text to Clipboard"),
            #selector(captureScreenToClipboard(_:))
        ))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeItem(L("保存结果…", "Save Result…"), #selector(saveDocument(_:)), key: "s"))
        fileMenu.addItem(makeItem(
            L("导出 JSON…", "Export JSON…"),
            #selector(exportJSON(_:)),
            key: "e",
            modifiers: [.command, .shift]
        ))
        fileMenu.addItem(makeItem(
            L("导出可搜索 PDF…", "Export Searchable PDF…"),
            #selector(exportSearchablePDF(_:)),
            key: "p",
            modifiers: [.command, .shift]
        ))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeResponderItem(
            L("关闭窗口", "Close Window"),
            #selector(NSWindow.performClose(_:)),
            key: "w"
        ))
        addSubmenu(fileMenu, to: mainMenu)

        let editMenu = NSMenu(title: L("编辑", "Edit"))
        editMenu.addItem(makeResponderItem(L("剪切", "Cut"), #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(makeResponderItem(L("拷贝", "Copy"), #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(makeItem(
            L("拷贝全部结果", "Copy Entire Result"),
            #selector(copyResult(_:)),
            key: "c",
            modifiers: [.command, .shift]
        ))
        editMenu.addItem(makeItem(L("粘贴", "Paste"), #selector(pasteFromMenu(_:)), key: "v"))
        editMenu.addItem(makeResponderItem(L("全选", "Select All"), #selector(NSText.selectAll(_:)), key: "a"))
        addSubmenu(editMenu, to: mainMenu)

        let goMenu = NSMenu(title: L("前往", "Go"))
        for feature in VisionFeature.allCases {
            let item = makeItem(feature.title, #selector(showFeature(_:)), key: String(feature.rawValue + 1))
            item.tag = feature.rawValue
            goMenu.addItem(item)
        }
        goMenu.addItem(.separator())
        goMenu.addItem(makeItem(L("批量处理", "Batch Processing"), #selector(showBatchPage(_:)), key: "b"))
        goMenu.addItem(makeItem(
            L("API 服务", "API Server"),
            #selector(showServerPage(_:)),
            key: "l",
            modifiers: [.command, .shift]
        ))
        addSubmenu(goMenu, to: mainMenu)

        let serverMenu = NSMenu(title: L("服务", "Server"))
        serverMenu.autoenablesItems = false
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        serverMenu.addItem(status)
        serverStatusItems.append(status)
        let toggle = makeItem("", #selector(toggleServer(_:)), key: "r", modifiers: [.command, .shift])
        serverMenu.addItem(toggle)
        serverToggleItems.append(toggle)
        serverMenu.addItem(makeItem(L("打开接口文档", "Open API Docs"), #selector(openServerInBrowser(_:))))
        addSubmenu(serverMenu, to: mainMenu)

        let windowMenu = NSMenu(title: L("窗口", "Window"))
        windowMenu.addItem(makeResponderItem(
            L("最小化", "Minimize"),
            #selector(NSWindow.performMiniaturize(_:)),
            key: "m"
        ))
        windowMenu.addItem(.separator())
        windowMenu.addItem(makeItem(L("主窗口", "Main Window"), #selector(showMainWindow(_:)), key: "0"))
        addSubmenu(windowMenu, to: mainMenu)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        menu.addItem(item)
    }
}
