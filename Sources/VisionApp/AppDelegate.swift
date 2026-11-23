import AppKit
import VisionServer

/// Vision 图形界面（AppKit）入口
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mainViewController = MainViewController()
    private var mainWindow: NSWindow?
    private var batchWindow: NSWindow?
    private var serverWindow: NSWindow?
    private var preferencesWindow: NSWindow?

    private var statusItem: NSStatusItem?
    /// 标题随服务状态变化的菜单项（主菜单和菜单栏图标菜单各一个）
    private var serverToggleItems: [NSMenuItem] = []
    private var serverStatusItems: [NSMenuItem] = []
    private var isTerminating = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // 以 `swift run` 方式启动时没有 .app 包，需要手动声明为普通应用
        app.setActivationPolicy(.regular)
        app.run()
    }

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 必须在创建任何 Logger 之前接管日志，服务面板才能显示运行日志
        ServerLogStore.installAsLoggingBackend()

        NSApp.mainMenu = makeMainMenu()
        updateStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(serverStateChanged(_:)),
            name: ServerController.stateDidChangeNotification,
            object: nil
        )
        refreshServerMenuItems()

        showMainWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if Settings.startServerAtLaunch {
            ServerController.shared.start()
        }
    }

    /// 关闭所有窗口后应用继续运行，这样内嵌服务可以留在后台
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
        mainViewController.loadFile(at: url)
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

    // MARK: - 窗口

    private func makeWindow(title: String, contentViewController: NSViewController, size: NSSize) -> NSWindow {
        let window = NSWindow(contentViewController: contentViewController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // 窗口由本类持有，关闭后不能被系统再释放一次
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        return window
    }

    @objc func showMainWindow(_ sender: Any?) {
        if mainWindow == nil {
            mainWindow = makeWindow(
                title: "Vision",
                contentViewController: mainViewController,
                size: NSSize(width: 1080, height: 680)
            )
        }
        present(mainWindow)
    }

    @objc func showBatchWindow(_ sender: Any?) {
        if batchWindow == nil {
            batchWindow = makeWindow(
                title: L("批量处理", "Batch Processing"),
                contentViewController: BatchViewController(),
                size: NSSize(width: 720, height: 480)
            )
        }
        present(batchWindow)
    }

    @objc func showServerWindow(_ sender: Any?) {
        if serverWindow == nil {
            serverWindow = makeWindow(
                title: L("API 服务", "API Server"),
                contentViewController: ServerViewController(),
                size: NSSize(width: 640, height: 440)
            )
        }
        present(serverWindow)
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesWindow == nil {
            let controller = PreferencesViewController()
            controller.onMenuBarIconChanged = { [weak self] in
                self?.updateStatusItem()
            }
            let window = makeWindow(
                title: L("偏好设置", "Settings"),
                contentViewController: controller,
                size: NSSize(width: 480, height: 260)
            )
            window.styleMask = [.titled, .closable]
            preferencesWindow = window
        }
        present(preferencesWindow)
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 动作

    @objc func captureScreen(_ sender: Any?) {
        showMainWindow(nil)
        mainViewController.captureScreen(sender)
    }

    /// ⌘V：焦点在可编辑的文本框里时粘贴文本，否则把剪贴板里的图片载入主窗口
    @objc func pasteFromMenu(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSText, text.isEditable {
            text.paste(sender)
        } else {
            showMainWindow(nil)
            mainViewController.pasteImage(sender)
        }
    }

    @objc func toggleServer(_ sender: Any?) {
        ServerController.shared.toggle()
    }

    @objc func openServerInBrowser(_ sender: Any?) {
        if ServerController.shared.isRunning, let url = ServerController.shared.baseURL {
            NSWorkspace.shared.open(url)
        } else {
            showServerWindow(nil)
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
        statusItem?.button?.title = controller.isRunning ? "Vision ●" : "Vision"
    }

    // MARK: - 菜单栏图标

    private func updateStatusItem() {
        if Settings.showsMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "Vision"
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

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        serverStatusItems.append(status)

        let toggle = makeItem("", #selector(toggleServer(_:)))
        menu.addItem(toggle)
        serverToggleItems.append(toggle)
        menu.addItem(makeItem(L("API 服务面板…", "API Server Panel…"), #selector(showServerWindow(_:))))
        menu.addItem(.separator())
        menu.addItem(makeItem(L("打开主窗口", "Open Main Window"), #selector(showMainWindow(_:))))
        menu.addItem(makeItem(L("截屏识别文字", "Capture Screen Text"), #selector(captureScreen(_:))))
        menu.addItem(makeItem(L("批量处理…", "Batch Processing…"), #selector(showBatchWindow(_:))))
        menu.addItem(.separator())
        menu.addItem(makeItem(L("偏好设置…", "Settings…"), #selector(showPreferences(_:))))
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

    /// 创建沿响应链分发的菜单项（由主窗口或系统处理）
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
        appMenu.addItem(makeItem(L("偏好设置…", "Settings…"), #selector(showPreferences(_:)), key: ","))
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
        fileMenu.addItem(makeResponderItem(
            L("打开…", "Open…"),
            #selector(MainViewController.openDocument(_:)),
            key: "o"
        ))
        fileMenu.addItem(makeItem(
            L("截屏识别文字", "Capture Screen Text"),
            #selector(captureScreen(_:)),
            key: "2",
            modifiers: [.command, .shift]
        ))
        fileMenu.addItem(makeItem(L("批量处理…", "Batch Processing…"), #selector(showBatchWindow(_:)), key: "b"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeResponderItem(
            L("保存结果…", "Save Result…"),
            #selector(MainViewController.saveDocument(_:)),
            key: "s"
        ))
        fileMenu.addItem(makeResponderItem(
            L("导出 JSON…", "Export JSON…"),
            #selector(MainViewController.exportJSON(_:)),
            key: "e",
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
        editMenu.addItem(makeResponderItem(
            L("拷贝全部结果", "Copy Entire Result"),
            #selector(MainViewController.copyResult(_:)),
            key: "c",
            modifiers: [.command, .shift]
        ))
        editMenu.addItem(makeItem(L("粘贴", "Paste"), #selector(pasteFromMenu(_:)), key: "v"))
        editMenu.addItem(makeResponderItem(L("全选", "Select All"), #selector(NSText.selectAll(_:)), key: "a"))
        addSubmenu(editMenu, to: mainMenu)

        let serverMenu = NSMenu(title: L("服务", "Server"))
        serverMenu.autoenablesItems = false
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        serverMenu.addItem(status)
        serverStatusItems.append(status)
        let toggle = makeItem("", #selector(toggleServer(_:)), key: "r", modifiers: [.command, .shift])
        serverMenu.addItem(toggle)
        serverToggleItems.append(toggle)
        serverMenu.addItem(makeItem(L("在浏览器中打开", "Open in Browser"), #selector(openServerInBrowser(_:))))
        serverMenu.addItem(.separator())
        serverMenu.addItem(makeItem(
            L("API 服务面板…", "API Server Panel…"),
            #selector(showServerWindow(_:)),
            key: "l",
            modifiers: [.command, .shift]
        ))
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
