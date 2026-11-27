import AppKit
import CoreImage
import XCTest
@testable import VisionCore

/// 测试用的图片和 PDF 都在运行时生成，不依赖仓库里的样例文件
final class VisionCoreTests: XCTestCase {
    // MARK: - 生成测试素材

    /// 在白底上绘制一行黑色文字，返回 PNG 数据
    private func makeTextImage(_ text: String) throws -> Data {
        let width = 900
        let height = 240
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(text, at: CGPoint(x: 40, y: 90), fontSize: 72, in: context)

        let image = try XCTUnwrap(context.makeImage())
        return try ImageCoding.pngData(from: image)
    }

    /// 生成只有一页、包含一行文字的 PDF
    private func makeTextPDF(_ text: String) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        draw(text, at: CGPoint(x: 72, y: 600), fontSize: 36, in: context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func draw(_ text: String, at point: CGPoint, fontSize: CGFloat, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }

    /// 生成内容为指定字符串的二维码 PNG
    private func makeQRCode(_ payload: String) throws -> Data {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(filter.outputImage)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let image = try XCTUnwrap(CIContext().createCGImage(scaled, from: scaled.extent))
        return try ImageCoding.pngData(from: image)
    }

    // MARK: - 模型

    func testBoundingBoxRoundTrip() {
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let box = BoundingBox(rect)
        XCTAssertEqual(box.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(box.height, 0.4, accuracy: 1e-9)
        XCTAssertEqual(box.cgRect.width, rect.width, accuracy: 1e-9)
    }

    func testResponseJSONKeys() throws {
        let response = BarcodeResponse(barcodes: [
            BarcodeResult(payload: "abc", symbology: "VNBarcodeSymbologyQR", boundingBox: BoundingBox(.zero)),
        ])
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(response), encoding: .utf8))
        XCTAssertTrue(json.contains("\"barcodes\""))
        XCTAssertTrue(json.contains("\"payload\""))
        XCTAssertTrue(json.contains("\"symbology\""))
        XCTAssertTrue(json.contains("\"boundingBox\""))
    }

    // MARK: - Vision

    func testInvalidImageDataThrows() {
        let garbage = Data("not an image".utf8)
        XCTAssertThrowsError(try VisionEngine.recognizeText(imageData: garbage))
        XCTAssertThrowsError(try VisionEngine.scanBarcodes(imageData: garbage))
    }

    func testRecognizeText() throws {
        let image = try makeTextImage("HELLO VISION")
        let lines = try VisionEngine.recognizeText(
            imageData: image,
            options: TextRecognitionOptions(languages: ["en-US"])
        )
        let text = lines.map { $0.text }.joined(separator: " ").uppercased()
        XCTAssertTrue(text.contains("HELLO"), "识别结果：\(text)")
    }

    func testScanQRCode() throws {
        let image = try makeQRCode("https://example.com/vision")
        let barcodes = try VisionEngine.scanBarcodes(imageData: image)
        XCTAssertEqual(barcodes.first?.payload, "https://example.com/vision")
    }

    // MARK: - 新增工具

    func testTextInsights() {
        let insights = TextInsights.detect(in: "官网 https://example.com/vision 电话 010-12345678")
        XCTAssertTrue(insights.contains { $0.kind == .link && ($0.url ?? "").contains("example.com") })
    }

    func testRedactionProducesPNG() throws {
        let image = try makeQRCode("https://example.com/vision")
        let result = try Redactor.redact(imageData: image, targets: .barcodes)
        XCTAssertEqual(Array(result.pngData.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertFalse(result.regions.isEmpty)
        // 打码后二维码应当无法再被识别
        XCTAssertTrue(try VisionEngine.scanBarcodes(imageData: result.pngData).isEmpty)
    }

    func testRedactionWithoutTargetsKeepsImage() throws {
        let result = try Redactor.redact(imageData: try makeTextImage("HELLO"), targets: [])
        XCTAssertTrue(result.regions.isEmpty)
        XCTAssertEqual(Array(result.pngData.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testSearchablePDFContainsRecognizedText() throws {
        let image = try makeTextImage("HELLO VISION")
        let pdf = try SearchablePDF.make(imageData: image, options: TextRecognitionOptions(languages: ["en-US"]))
        XCTAssertTrue(PDFEngine.looksLikePDF(pdf))
        XCTAssertEqual(try PDFEngine.pageCount(pdfData: pdf), 1)
        let text = try PDFEngine.extractText(pdfData: pdf, mergePages: true).allText ?? ""
        XCTAssertTrue(text.uppercased().contains("HELLO"), "PDF 文本层：\(text)")
    }

    // MARK: - PDF

    func testPDFDetection() throws {
        XCTAssertTrue(PDFEngine.looksLikePDF(try makeTextPDF("x")))
        XCTAssertFalse(PDFEngine.looksLikePDF(Data("plain".utf8)))
    }

    func testPDFPageCountAndText() throws {
        let pdf = try makeTextPDF("Hello PDF")
        XCTAssertEqual(try PDFEngine.pageCount(pdfData: pdf), 1)

        let result = try PDFEngine.extractText(pdfData: pdf, mergePages: true)
        XCTAssertEqual(result.totalPages, 1)
        XCTAssertEqual(result.extractedPages.count, 1)
        XCTAssertTrue((result.allText ?? "").contains("Hello"))
    }

    func testPDFRenderProducesPNG() throws {
        let png = try PDFEngine.renderPage(pdfData: try makeTextPDF("Hello PDF"), pageIndex: 0, dpi: 72)
        // PNG 文件头
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testPDFErrors() throws {
        XCTAssertThrowsError(try PDFEngine.pageCount(pdfData: Data("nope".utf8)))

        let pdf = try makeTextPDF("Hello PDF")
        XCTAssertThrowsError(try PDFEngine.renderPage(pdfData: pdf, pageIndex: 5)) { error in
            XCTAssertEqual((error as? VisionCoreError)?.isInputError, true)
        }
        XCTAssertThrowsError(try PDFEngine.extractText(pdfData: pdf, startPage: 3))
    }
}
