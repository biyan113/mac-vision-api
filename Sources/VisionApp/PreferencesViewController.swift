import AppKit

/// 偏好设置。所有改动立即保存到 UserDefaults。
final class PreferencesViewController: NSViewController {
    /// 菜单栏图标开关变化时调用
    var onMenuBarIconChanged: (() -> Void)?
    /// 全局快捷键开关变化时调用
    var onGlobalHotKeyChanged: (() -> Void)?

    private let featurePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let ocrLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fastCheckbox = NSButton(
        checkboxWithTitle: L("文字识别默认使用快速模式", "Use fast mode for text recognition by default"),
        target: nil,
        action: nil
    )
    private let interfaceLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let menuBarCheckbox = NSButton(
        checkboxWithTitle: L("在菜单栏显示图标", "Show icon in the menu bar"),
        target: nil,
        action: nil
    )

    private let hotKeyCheckbox = NSButton(
        checkboxWithTitle: L(
            "启用全局快捷键 \(GlobalHotKey.displayName)：截屏识别并复制文字",
            "Enable global shortcut \(GlobalHotKey.displayName): capture, recognize and copy text"
        ),
        target: nil,
        action: nil
    )
    private let autoStartCheckbox = NSButton(
        checkboxWithTitle: L("启动应用时自动开启 API 服务", "Start the API server when the app launches"),
        target: nil,
        action: nil
    )

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 340))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        for feature in VisionFeature.allCases {
            featurePopup.addItem(withTitle: feature.title)
        }
        featurePopup.selectItem(at: Settings.defaultFeature.rawValue)

        for option in OCRLanguage.options {
            ocrLanguagePopup.addItem(withTitle: option.title)
        }
        ocrLanguagePopup.selectItem(at: Settings.ocrLanguageIndex)

        for language in InterfaceLanguage.allCases {
            interfaceLanguagePopup.addItem(withTitle: language.title)
        }
        interfaceLanguagePopup.selectItem(at: InterfaceLanguage.allCases.firstIndex(of: Settings.interfaceLanguage) ?? 0)

        fastCheckbox.state = Settings.ocrFastMode ? .on : .off
        menuBarCheckbox.state = Settings.showsMenuBarIcon ? .on : .off
        hotKeyCheckbox.state = Settings.usesGlobalHotKey ? .on : .off
        autoStartCheckbox.state = Settings.startServerAtLaunch ? .on : .off

        let controls: [NSControl] = [
            featurePopup, ocrLanguagePopup, interfaceLanguagePopup,
            fastCheckbox, menuBarCheckbox, hotKeyCheckbox, autoStartCheckbox,
        ]
        for control in controls {
            control.target = self
            control.action = #selector(settingChanged(_:))
        }

        let languageHint = NSTextField(labelWithString: L("（重启应用后生效）", "(takes effect after relaunch)"))
        languageHint.textColor = .secondaryLabelColor
        let languageRow = NSStackView(views: [interfaceLanguagePopup, languageHint])
        languageRow.orientation = .horizontal
        languageRow.spacing = 8

        let note = NSTextField(wrappingLabelWithString: L(
            "默认功能和识别语言在下次启动应用时生效，批量处理始终使用这里的识别语言。服务地址、端口和访问密钥在侧边栏的「API 服务」里设置。",
            "The default feature and recognition language apply the next time the app launches; batch processing always uses the language set here. The server address, port and API key are set under “API Server” in the sidebar."
        ))
        note.textColor = .secondaryLabelColor
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: L("默认功能", "Default feature")), featurePopup],
            [NSTextField(labelWithString: L("识别语言", "Recognition language")), ocrLanguagePopup],
            [NSGridCell.emptyContentView, fastCheckbox],
            [NSTextField(labelWithString: L("界面语言", "Interface language")), languageRow],
            [NSGridCell.emptyContentView, menuBarCheckbox],
            [NSGridCell.emptyContentView, hotKeyCheckbox],
            [NSGridCell.emptyContentView, autoStartCheckbox],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 10

        for subview in [grid, note] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            note.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            note.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            note.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            note.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 460),
        ])
    }

    @objc private func settingChanged(_ sender: Any?) {
        Settings.defaultFeature = VisionFeature(rawValue: featurePopup.indexOfSelectedItem) ?? .ocr
        Settings.ocrLanguageIndex = max(0, ocrLanguagePopup.indexOfSelectedItem)
        Settings.ocrFastMode = fastCheckbox.state == .on

        let languages = InterfaceLanguage.allCases
        let languageIndex = interfaceLanguagePopup.indexOfSelectedItem
        if languages.indices.contains(languageIndex) {
            Settings.interfaceLanguage = languages[languageIndex]
        }

        Settings.startServerAtLaunch = autoStartCheckbox.state == .on

        let usesGlobalHotKey = hotKeyCheckbox.state == .on
        if usesGlobalHotKey != Settings.usesGlobalHotKey {
            Settings.usesGlobalHotKey = usesGlobalHotKey
            onGlobalHotKeyChanged?()
        }

        let showsMenuBarIcon = menuBarCheckbox.state == .on
        if showsMenuBarIcon != Settings.showsMenuBarIcon {
            Settings.showsMenuBarIcon = showsMenuBarIcon
            onMenuBarIconChanged?()
        }
    }
}
