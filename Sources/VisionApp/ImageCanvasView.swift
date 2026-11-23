import AppKit
import UniformTypeIdentifiers

/// 按比例显示图片的视图，可叠加检测框，并可选支持拖入图片文件
final class ImageCanvasView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var boxes: [VisionBox] = [] {
        didSet { needsDisplay = true }
    }

    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    /// 设置后视图接受拖入的图片文件
    var onDropImage: ((URL) -> Void)? {
        didSet {
            if onDropImage != nil {
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

        image.draw(in: imageRect)

        for box in boxes {
            // Vision 的归一化坐标与 AppKit 一样以左下角为原点
            let rect = NSRect(
                x: imageRect.minX + box.rect.minX * imageRect.width,
                y: imageRect.minY + box.rect.minY * imageRect.height,
                width: box.rect.width * imageRect.width,
                height: box.rect.height * imageRect.height
            )
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1.5
            NSColor.systemRed.setStroke()
            path.stroke()

            if !box.label.isEmpty {
                drawLabel(box.label, above: rect)
            }
        }
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

    // MARK: - 拖放

    private func droppedImageURL(from info: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard onDropImage != nil, droppedImageURL(from: sender) != nil else { return [] }
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
        guard let url = droppedImageURL(from: sender), let onDropImage = onDropImage else { return false }
        onDropImage(url)
        return true
    }
}
