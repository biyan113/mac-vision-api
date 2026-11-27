import AppKit

/// 侧边栏里可以前往的页面
enum Destination: Equatable {
    case feature(VisionFeature)
    case batch
    case server

    var title: String {
        switch self {
        case .feature(let feature): return feature.title
        case .batch: return L("批量处理", "Batch Processing")
        case .server: return L("API 服务", "API Server")
        }
    }

    var symbolName: String {
        switch self {
        case .feature(let feature): return feature.symbolName
        case .batch: return "square.stack.3d.up"
        case .server: return "server.rack"
        }
    }
}

/// 侧边栏：识别功能和工具的导航列表
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Row {
        case header(String)
        case destination(Destination)
    }

    /// 选中某一项时调用
    var onSelect: ((Destination) -> Void)?

    private let tableView = NSTableView()
    private let rows: [Row] = {
        var rows: [Row] = [.header(L("识别", "Recognize"))]
        rows += VisionFeature.allCases.map { .destination(.feature($0)) }
        rows += [.header(L("工具", "Tools")), .destination(.batch), .destination(.server)]
        return rows
    }()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 210, height: 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.isEditable = false
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = 30
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        tableView.reloadData()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(serverStateChanged(_:)),
            name: ServerController.stateDidChangeNotification,
            object: nil
        )
    }

    /// 选中指定页面对应的行（不触发 onSelect）
    func select(_ destination: Destination) {
        guard let index = rows.firstIndex(where: { row in
            if case .destination(let candidate) = row { return candidate == destination }
            return false
        }) else { return }
        isUpdatingSelection = true
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        isUpdatingSelection = false
    }

    private var isUpdatingSelection = false

    // MARK: - 列表

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .destination = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label

        switch rows[row] {
        case .header(let title):
            label.stringValue = title
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])

        case .destination(let destination):
            var title = destination.title
            if destination == .server, ServerController.shared.isRunning {
                title += L(" · 运行中", " · Running")
            }
            label.stringValue = title
            label.font = NSFont.systemFont(ofSize: 13)

            let imageView = NSImageView()
            imageView.image = NSImage(systemSymbolName: destination.symbolName, accessibilityDescription: nil)
            imageView.contentTintColor = .controlAccentColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 20),
                label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection, tableView.selectedRow >= 0 else { return }
        if case .destination(let destination) = rows[tableView.selectedRow] {
            onSelect?(destination)
        }
    }

    /// 服务启动或停止后刷新“API 服务”一行的文字
    @objc private func serverStateChanged(_ notification: Notification) {
        guard let index = rows.firstIndex(where: { row in
            if case .destination(.server) = row { return true }
            return false
        }) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
    }
}
