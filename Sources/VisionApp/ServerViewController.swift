import AppKit

/// 内嵌 API 服务面板：启动与停止、地址设置、运行日志
final class ServerViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: "")
    private let hostField = NSTextField(string: "")
    private let portField = NSTextField(string: "")
    private let apiKeyField = NSSecureTextField(string: "")
    private let toggleButton = NSButton(title: "", target: nil, action: nil)
    private let openButton = NSButton(title: L("打开接口文档", "Open API Docs"), target: nil, action: nil)
    private let autoStartCheckbox = NSButton(
        checkboxWithTitle: L("启动应用时自动开启服务", "Start the server when the app launches"),
        target: nil,
        action: nil
    )
    private let logScrollView = NSTextView.scrollableTextView()

    private var logTextView: NSTextView? {
        logScrollView.documentView as? NSTextView
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 640))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        hostField.stringValue = Settings.serverHostname
        hostField.placeholderString = "127.0.0.1"
        portField.stringValue = String(Settings.serverPort)
        portField.placeholderString = "8080"
        apiKeyField.stringValue = Settings.serverAPIKey
        apiKeyField.placeholderString = L("留空则不需要密钥", "Leave empty for no key")

        toggleButton.target = self
        toggleButton.action = #selector(toggleServer(_:))
        openButton.target = self
        openButton.action = #selector(openInBrowser(_:))
        autoStartCheckbox.state = Settings.startServerAtLaunch ? .on : .off
        autoStartCheckbox.target = self
        autoStartCheckbox.action = #selector(autoStartChanged(_:))

        if let textView = logTextView {
            textView.isEditable = false
            textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.textContainerInset = NSSize(width: 6, height: 6)
            textView.string = ServerLogStore.shared.lines.map { $0 + "\n" }.joined()
        }
        logScrollView.borderType = .bezelBorder

        let hostLabel = NSTextField(labelWithString: L("监听地址", "Host"))
        let portLabel = NSTextField(labelWithString: L("端口", "Port"))
        let addressSpacer = NSView()
        addressSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let addressRow = NSStackView(views: [
            hostLabel, hostField, portLabel, portField, addressSpacer, toggleButton, openButton,
        ])
        addressRow.orientation = .horizontal
        addressRow.spacing = 8

        let keyLabel = NSTextField(labelWithString: L("访问密钥", "API Key"))
        let keySpacer = NSView()
        keySpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let keyRow = NSStackView(views: [keyLabel, apiKeyField, keySpacer])
        keyRow.orientation = .horizontal
        keyRow.spacing = 8

        let hint = NSTextField(wrappingLabelWithString: L(
            "监听 127.0.0.1 时只有本机可以访问；改为 0.0.0.0 后同一网络内的其他设备也能访问，此时建议设置访问密钥。设置后，请求需要携带 Authorization: Bearer <密钥> 或 X-API-Key: <密钥>。",
            "With 127.0.0.1 only this Mac can connect. With 0.0.0.0 other devices on your network can connect too, so set an API key. Requests must then send Authorization: Bearer <key> or X-API-Key: <key>."
        ))
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        let logLabel = NSTextField(labelWithString: L("运行日志", "Log"))
        let clearButton = NSButton(title: L("清空日志", "Clear Log"), target: self, action: #selector(clearLog(_:)))
        let logSpacer = NSView()
        logSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let logRow = NSStackView(views: [logLabel, logSpacer, clearButton])
        logRow.orientation = .horizontal

        let rows: [NSView] = [statusLabel, addressRow, keyRow, hint, autoStartCheckbox, logRow, logScrollView]
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
            logScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            logScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            hostField.widthAnchor.constraint(equalToConstant: 130),
            portField.widthAnchor.constraint(equalToConstant: 70),
            apiKeyField.widthAnchor.constraint(equalToConstant: 260),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(serverStateChanged(_:)),
            name: ServerController.stateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(logAppended(_:)),
            name: ServerLogStore.didAppendNotification,
            object: nil
        )
        refresh()
    }

    // MARK: - 动作

    @objc private func toggleServer(_ sender: Any?) {
        let controller = ServerController.shared
        if controller.state == .stopped {
            guard saveAddress() else { return }
        }
        controller.toggle()
    }

    /// 校验并保存地址设置，端口无效时返回 false
    private func saveAddress() -> Bool {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let port = Int(portField.stringValue.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(port)
        else {
            statusLabel.stringValue = L("端口必须是 1 到 65535 之间的数字", "The port must be a number from 1 to 65535")
            return false
        }
        Settings.serverHostname = host
        Settings.serverPort = port
        Settings.serverAPIKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        hostField.stringValue = Settings.serverHostname
        return true
    }

    @objc private func openInBrowser(_ sender: Any?) {
        if let url = ServerController.shared.baseURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func autoStartChanged(_ sender: Any?) {
        Settings.startServerAtLaunch = autoStartCheckbox.state == .on
    }

    @objc private func clearLog(_ sender: Any?) {
        ServerLogStore.shared.clear()
        logTextView?.string = ""
    }

    // MARK: - 通知

    @objc private func serverStateChanged(_ notification: Notification) {
        refresh()
    }

    @objc private func logAppended(_ notification: Notification) {
        guard let line = notification.userInfo?["line"] as? String,
              let textView = logTextView,
              let storage = textView.textStorage
        else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        storage.append(NSAttributedString(string: line + "\n", attributes: attributes))
        textView.scrollToEndOfDocument(nil)
    }

    private func refresh() {
        let controller = ServerController.shared
        statusLabel.stringValue = controller.statusText

        let isStopped = controller.state == .stopped
        hostField.isEnabled = isStopped
        portField.isEnabled = isStopped
        apiKeyField.isEnabled = isStopped
        openButton.isEnabled = controller.isRunning

        switch controller.state {
        case .stopped:
            toggleButton.title = L("启动服务", "Start Server")
            toggleButton.isEnabled = true
        case .running:
            toggleButton.title = L("停止服务", "Stop Server")
            toggleButton.isEnabled = true
        case .starting, .stopping:
            toggleButton.isEnabled = false
        }
    }
}
