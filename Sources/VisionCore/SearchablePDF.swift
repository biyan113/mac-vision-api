import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// 生成“可搜索 PDF”：页面上是原图，上面叠一层看不见的识别文字，可以搜索和复制
public enum SearchablePDF {
    /// 由一张图片生成单页的可搜索 PDF
    public static func make(
        imageData: Data,
        options: TextRecognitionOptions = TextRecognitionOptions()
    ) throws -> Data {
        // 按 144 像素/英寸换算页面尺寸
        try compose(pages: [(imageData, 0.5)], options: options)
    }

    /// 对 PDF（通常是扫描件）的每一页做文字识别，生成可搜索的新 PDF
    public static func make(
        pdfData: Data,
        dpi: Double = 200,
        options: TextRecognitionOptions = TextRecognitionOptions()
    ) throws -> Data {
        let pageCount = try PDFEngine.pageCount(pdfData: pdfData)
        var pages: [(Data, CGFloat)] = []
        for index in 0..<pageCount {
            let png = try PDFEngine.renderPage(pdfData: pdfData, pageIndex: index, dpi: dpi)
            pages.append((png, CGFloat(72.0 / dpi)))
        }
        return try compose(pages: pages, options: options)
    }

    /// - Parameter pages: 每页的图片数据，以及“每像素对应多少个 PDF 点”
    private static func compose(pages: [(Data, CGFloat)], options: TextRecognitionOptions) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw VisionCoreError.imageConversionFailed("无法创建 PDF")
        }

        let imageContext = CIContext(options: nil)
        for (data, pointsPerPixel) in pages {
            // 摆正拍摄方向，使图像与 Vision 返回的坐标一致
            guard let ciImage = CIImage(data: data, options: [.applyOrientationProperty: true]),
                  let image = imageContext.createCGImage(ciImage, from: ciImage.extent)
            else {
                throw VisionCoreError.imageConversionFailed("无法解码图片")
            }
            let lines = try VisionEngine.recognizeText(imageData: data, options: options)

            var pageBox = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(image.width) * pointsPerPixel,
                height: CGFloat(image.height) * pointsPerPixel
            )
            context.beginPage(mediaBox: &pageBox)
            context.draw(image, in: pageBox)
            context.setTextDrawingMode(.invisible)
            for line in lines {
                drawInvisibleText(line, pageBox: pageBox, context: context)
            }
            context.endPage()
        }
        context.closePDF()
        return output as Data
    }

    /// 把一行文字不可见地画在它的识别框里，并横向拉伸到与框同宽
    private static func drawInvisibleText(_ line: RecognizedTextLine, pageBox: CGRect, context: CGContext) {
        let box = line.boundingBox.cgRect
        let rect = CGRect(
            x: box.minX * pageBox.width,
            y: box.minY * pageBox.height,
            width: box.width * pageBox.width,
            height: box.height * pageBox.height
        )
        guard rect.width > 1, rect.height > 1, !line.text.isEmpty else { return }

        let font = CTFontCreateWithName("Helvetica" as CFString, max(rect.height * 0.8, 1), nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]
        let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: attributes))
        let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        guard width > 0 else { return }

        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY + rect.height * 0.2)
        context.scaleBy(x: rect.width / width, y: 1)
        context.textPosition = .zero
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }
}
