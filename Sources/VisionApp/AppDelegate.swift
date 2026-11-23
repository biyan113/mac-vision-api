import AppKit

/// Vision 图形界面（AppKit）入口
/// 直接调用 Vision 框架，不依赖 HTTP 服务
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let mainViewController = MainViewController()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // 以 `swift run` 方式启动时没有 .app 包，需要手动声明为普通应用
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        let window = NSWindow(contentViewController: mainViewController)
        window.title = "Vision"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1000, height: 640))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            mainViewController.loadImage(from: url)
        }
    }

    // MARK: - 菜单

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "关于 Vision",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Vision", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Vision", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: mainMenu)

        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(
            withTitle: "打开图片…",
            action: #selector(MainViewController.openDocument(_:)),
            keyEquivalent: "o"
        )
        fileMenu.addItem(
            withTitle: "保存结果…",
            action: #selector(MainViewController.saveDocument(_:)),
            keyEquivalent: "s"
        )
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(fileMenu, to: mainMenu)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let copyResultItem = editMenu.addItem(
            withTitle: "拷贝全部结果",
            action: #selector(MainViewController.copyResult(_:)),
            keyEquivalent: "c"
        )
        copyResultItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(
            withTitle: "粘贴图片",
            action: #selector(MainViewController.pasteImage(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu, to: mainMenu)

        return mainMenu
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        menu.addItem(item)
    }
}
