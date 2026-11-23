import AppKit
import UniformTypeIdentifiers

/// 按比例显示图片的视图，可叠加检测框，并可选支持拖入图片或 PDF 文件
final class ImageCanvasView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var boxes: [OverlayBox] = [] {
        didSet {
            highlightedIndex = nil
            needsDisplay = true
        }
    }

    /// 当前高亮的检测框下标
    var highlightedIndex: Int? {
        didSet { needsDisplay = true }
    }

    /// 点击检测框（或空白处，此时为 nil）时调用
    var onSelectBox: ((Int?) -> Void)?

    /// 是否在图片下方绘制棋盘格，用来表现透明区域
    var showsCheckerboard = false {
        didSet { needsDisplay = true }
    }

    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    /// 设置后视图接受拖入的图片或 PDF 文件
    var onDropFile: ((URL) -> Void)? {
        didSet {
            if onDropFile != nil {
                registerForDraggedTypes([.fileURL])
            } else {
                unregisterDraggedTypes()
            }
        }
    }

    private var isDropTarget = false {
        didSet { needsDisplay = true }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        background.fill()
        (isDropTarget ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        background.lineWidth = isDropTarget ? 2 : 1
        background.stroke()

        guard let image = image, let imageRect = fittedRect(for: image.size) else {
            drawPlaceholder()
            return
        }

        if showsCheckerboard {
            drawCheckerboard(in: imageRect)
        }
        image.draw(in: imageRect)

        for (index, box) in boxes.enumerated() {
            let rect = viewRect(for: box, in: imageRect)
            let isHighlighted = index == highlightedIndex
            let path = NSBezierPath(rect: rect)
            if isHighlighted {
                NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
                path.fill()
            }
            path.lineWidth = isHighlighted ? 2.5 : 1.5
            (isHighlighted ? NSColor.controlAccentColor : NSColor.systemRed).setStroke()
            path.stroke()

            if !box.label.isEmpty {
                drawLabel(box.label, above: rect)
            }
        }
    }

    /// 把 Vision 的归一化坐标换算到视图坐标（两者都以左下角为原点）
    private func viewRect(for box: OverlayBox, in imageRect: NSRect) -> NSRect {
        NSRect(
            x: imageRect.minX + box.rect.minX * imageRect.width,
            y: imageRect.minY + box.rect.minY * imageRect.height,
            width: box.rect.width * imageRect.width,
            height: box.rect.height * imageRect.height
        )
    }

    private func drawCheckerboard(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        NSColor.white.setFill()
        rect.fill()
        NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
        let side: CGFloat = 10
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : side)
            while x < rect.maxX {
                NSRect(x: x, y: y, width: side, height: side).fill()
                x += side * 2
            }
            y += side
            row += 1
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func fittedRect(for size: NSSize) -> NSRect? {
        let area = bounds.insetBy(dx: 12, dy: 12)
        guard size.width > 0, size.height > 0, area.width > 0, area.height > 0 else { return nil }
        let scale = min(area.width / size.width, area.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: area.midX - fitted.width / 2,
            y: area.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func drawPlaceholder() {
        guard !placeholder.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]
        let text = NSAttributedString(string: placeholder, attributes: attributes)
        let area = bounds.insetBy(dx: 16, dy: 16)
        let height = text.boundingRect(with: area.size, options: [.usesLineFragmentOrigin]).height
        text.draw(
            with: NSRect(x: area.minX, y: area.midY - height / 2, width: area.width, height: height),
            options: [.usesLineFragmentOrigin]
        )
    }

    private func drawLabel(_ label: String, above rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let size = text.size()
        var origin = NSPoint(x: rect.minX, y: rect.maxY)
        // 顶部放不下时把标签画在框内
        if origin.y + size.height + 2 > bounds.maxY {
            origin.y = rect.maxY - size.height - 2
        }
        let labelRect = NSRect(x: origin.x, y: origin.y, width: size.width + 8, height: size.height + 2)
        NSColor.systemRed.setFill()
        labelRect.fill()
        text.draw(at: NSPoint(x: labelRect.minX + 4, y: labelRect.minY + 1))
    }

    // MARK: - 点击检测框

    override func mouseDown(with event: NSEvent) {
        guard let onSelectBox = onSelectBox,
              let image = image,
              let imageRect = fittedRect(for: image.size)
        else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        // 多个框重叠时选面积最小的那个
        var selected: Int?
        var selectedArea = CGFloat.greatestFiniteMagnitude
        for (index, box) in boxes.enumerated() {
            let rect = viewRect(for: box, in: imageRect).insetBy(dx: -2, dy: -2)
            let area = rect.width * rect.height
            if rect.contains(point), area < selectedArea {
                selected = index
                selectedArea = area
            }
        }
        highlightedIndex = selected
        onSelectBox(selected)
    }

    // MARK: - 拖放

    private func droppedFileURL(from info: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier, UTType.pdf.identifier],
        ]
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard onDropFile != nil, droppedFileURL(from: sender) != nil else { return [] }
        isDropTarget = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTarget = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard let url = droppedFileURL(from: sender), let onDropFile = onDropFile else { return false }
        onDropFile(url)
        return true
    }
}
