@testable import VisionAPI
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import XCTVapor

/// 用程序生成的图片和 PDF 对识别接口做端到端测试，验证 Vision / PDFKit 的真实输出。
final class RecognitionTests: XCTestCase {
    private struct ImageBody: Content {
        var imageBase64: String
        var includeLines: Bool?
        var recognitionLanguages: String?
        var maxResults: Int?
    }

    private struct PDFBody: Content {
        var pdfBase64: String
        var pageIndex: Int?
        var dpi: Double?
        var mergePages: Bool?
    }

    private func withApp(_ test: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app, config: ServiceConfig())
            try await test(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    // MARK: - 测试素材

    private func makeLine(_ text: String, size: CGFloat) -> CTLine {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private func makeCanvas(width: Int, height: Int) throws -> CGContext {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private func png(_ context: CGContext) throws -> String {
        let image = try XCTUnwrap(context.makeImage())
        return try VisionSupport.pngData(from: image).base64EncodedString()
    }

    /// 白底黑字的文字图片
    private func textImage(_ text: String) throws -> String {
        let context = try makeCanvas(width: 1200, height: 300)
        context.textPosition = CGPoint(x: 60, y: 110)
        CTLineDraw(makeLine(text, size: 96), context)
        return try png(context)
    }

    /// 带留白的二维码图片
    private func qrImage(_ message: String) throws -> String {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let code = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))

        let side = max(code.width, code.height) + 160
        let context = try makeCanvas(width: side, height: side)
        context.interpolationQuality = .none
        context.draw(code, in: CGRect(x: 80, y: 80, width: code.width, height: code.height))
        return try png(context)
    }

    /// 白底上的一个深色矩形
    private func rectangleImage() throws -> String {
        let context = try makeCanvas(width: 800, height: 600)
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.fill(CGRect(x: 200, y: 150, width: 400, height: 300))
        return try png(context)
    }

    /// 两页带文本层的 PDF
    private func pdf(pages: [String]) throws -> String {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for text in pages {
            context.beginPDFPage(nil)
            context.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(makeLine(text, size: 28), context)
            context.endPDFPage()
        }
        context.closePDF()
        return (data as Data).base64EncodedString()
    }

    // MARK: - OCR

    func testRecognizeTextReadsRenderedText() async throws {
        let image = try textImage("HELLO VISION 2026")
        try await withApp { app in
            try await app.test(.POST, "text-detection/recognize-text", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image, includeLines: true, recognitionLanguages: "en-US"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let body = try res.content.decode(recognizeTextResponse.self)
                let text = body.text.uppercased()
                XCTAssertTrue(text.contains("HELLO"), "识别结果：\(body.text)")
                XCTAssertTrue(text.contains("2026"), "识别结果：\(body.text)")

                let lines = try XCTUnwrap(body.lines)
                let first = try XCTUnwrap(lines.first)
                XCTAssertGreaterThan(first.confidence, 0.3)
                // 坐标应为归一化值
                XCTAssertTrue((0 ... 1).contains(first.boundingBox.x))
                XCTAssertTrue((0 ... 1).contains(first.boundingBox.y))
                XCTAssertGreaterThan(first.boundingBox.width, 0)
                XCTAssertLessThanOrEqual(first.boundingBox.width, 1)
            })
        }
    }

    func testRecognizeTextOmitsLinesByDefault() async throws {
        let image = try textImage("VISION")
        try await withApp { app in
            try await app.test(.POST, "text-detection/recognize-text", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let body = try res.content.decode(recognizeTextResponse.self)
                XCTAssertNil(body.lines)
            })
        }
    }

    func testRecognizeTextAcceptsShortLanguageCodes() async throws {
        // 旧版 Web 界面发送的是 zh,en 这样的简写
        let image = try textImage("HELLO VISION 2026")
        try await withApp { app in
            try await app.test(.POST, "text-detection/recognize-text", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image, recognitionLanguages: "zh,en"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok, res.body.string)
                let text = try res.content.decode(recognizeTextResponse.self).text.uppercased()
                XCTAssertTrue(text.contains("HELLO"), text)
            })
        }
    }

    func testNormalizeLanguage() {
        XCTAssertEqual(TextDetectionController.normalizeLanguage("zh"), "zh-Hans")
        XCTAssertEqual(TextDetectionController.normalizeLanguage("EN"), "en-US")
        XCTAssertEqual(TextDetectionController.normalizeLanguage("zh-Hant"), "zh-Hant")
        XCTAssertEqual(TextDetectionController.normalizeLanguage("ja-JP"), "ja-JP")
    }

    func testSupportedLanguagesIncludesEnglish() async throws {
        try await withApp { app in
            try await app.test(.GET, "text-detection/supported-languages", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let body = try res.content.decode(SupportedLanguagesResponse.self)
                XCTAssertTrue(body.languages.contains("en-US"), "\(body.languages)")
            })
        }
    }

    // MARK: - 条码

    func testScanBarcodeDecodesQRCode() async throws {
        let message = "https://example.com/vision-api"
        let image = try qrImage(message)
        try await withApp { app in
            try await app.test(.POST, "vision/scan-barcode", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let body = try res.content.decode(BarcodeResponse.self)
                XCTAssertEqual(body.barcodes.count, 1)
                XCTAssertEqual(body.barcodes.first?.payload, message)
                XCTAssertTrue(body.barcodes.first?.symbology.uppercased().contains("QR") ?? false)
            })
        }
    }

    func testScanBarcodeReturnsEmptyForPlainImage() async throws {
        let image = try rectangleImage()
        try await withApp { app in
            try await app.test(.POST, "vision/scan-barcode", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let body = try res.content.decode(BarcodeResponse.self)
                XCTAssertTrue(body.barcodes.isEmpty)
            })
        }
    }

    // MARK: - 图像分析

    func testDetectRectanglesFindsRectangle() async throws {
        let image = try rectangleImage()
        try await withApp { app in
            try await app.test(.POST, "vision/detect-rectangles", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let body = try res.content.decode(RectangleResponse.self)
                let rectangle = try XCTUnwrap(body.rectangles.first)
                // 矩形占画面宽度的一半、位于中央
                XCTAssertEqual(rectangle.boundingBox.width, 0.5, accuracy: 0.08)
                XCTAssertEqual(rectangle.boundingBox.x, 0.25, accuracy: 0.08)
            })
        }
    }

    func testAnalysisEndpointsAcceptImage() async throws {
        let image = try rectangleImage()
        try await withApp { app in
            for path in ["vision/classify", "vision/detect-objects", "vision/detect-faces",
                         "vision/detect-body-pose", "vision/detect-hand-pose", "vision/saliency",
                         "vision/detect-horizon"] {
                try await app.test(.POST, path, beforeRequest: { req in
                    try req.content.encode(ImageBody(imageBase64: image))
                }, afterResponse: { res async in
                    XCTAssertEqual(res.status, .ok, "\(path)：\(res.body.string)")
                })
            }
        }
    }

    func testDetectFacesReturnsNoneForImageWithoutFaces() async throws {
        let image = try rectangleImage()
        try await withApp { app in
            try await app.test(.POST, "vision/detect-faces", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertTrue(try res.content.decode(FaceDetectionResponse.self).faces.isEmpty)
            })
        }
    }

    // MARK: - 依赖模型的能力

    /// 白底上的一个实心圆，作为背景移除的主体
    private func subjectImage() throws -> String {
        let context = try makeCanvas(width: 800, height: 600)
        context.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 250, y: 150, width: 300, height: 300))
        return try png(context)
    }

    func testBackgroundRemovalReturnsPNGOrReportsNoSubject() async throws {
        guard Capabilities.current.backgroundRemoval else { throw XCTSkip("需要 macOS 14") }
        let image = try subjectImage()
        try await withApp { app in
            try await app.test(.POST, "image-feature/background-removal", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image))
            }, afterResponse: { res async in
                // 合成图片是否被判定为有主体取决于模型，两种结果都合法；但不应出现 5xx
                if res.status == .ok {
                    XCTAssertEqual(res.headers.contentType, .png)
                    let bytes = [UInt8](res.body.readableBytesView.prefix(8))
                    XCTAssertEqual(bytes, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
                    print("background-removal: 200，返回 PNG \(res.body.readableBytes) 字节")
                } else {
                    XCTAssertEqual(res.status, .unprocessableEntity, res.body.string)
                    print("background-removal: \(res.status.code) \(res.body.string)")
                }
            })
        }
    }

    func testAestheticsReturnsScoreInRange() async throws {
        guard Capabilities.current.aesthetics else { throw XCTSkip("需要 macOS 15") }
        let image = try subjectImage()
        try await withApp { app in
            try await app.test(.POST, "vision/aesthetics", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok, res.body.string)
                let body = try res.content.decode(AestheticsResponse.self)
                XCTAssertTrue((-1.0 ... 1.0).contains(body.overallScore), "\(body.overallScore)")
            })
        }
    }

    #if compiler(>=6.2)
    func testRecognizeDocumentReadsText() async throws {
        guard #available(macOS 26.0, *), Capabilities.current.documentRecognition else {
            throw XCTSkip("需要 macOS 26")
        }
        let image = try textImage("HELLO VISION 2026")
        try await withApp { app in
            try await app.test(.POST, "text-detection/recognize-document", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok, res.body.string)
                let body = try res.content.decode(DocumentResponse.self)
                XCTAssertTrue(body.text.uppercased().contains("HELLO"), body.text)
                XCTAssertFalse(body.paragraphs.isEmpty)
            })
        }
    }

    func testLensSmudgeReturnsConfidenceInRange() async throws {
        guard #available(macOS 26.0, *), Capabilities.current.lensSmudge else {
            throw XCTSkip("需要 macOS 26")
        }
        let image = try subjectImage()
        try await withApp { app in
            try await app.test(.POST, "vision/lens-smudge", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: image))
            }, afterResponse: { res async throws in
                // 该模型在 CI 的虚拟机上无法加载（框架内部错误，接口按约定返回 422）；真机上应返回 200
                if res.status == .unprocessableEntity {
                    throw XCTSkip("当前环境无法运行镜头污渍模型：\(res.body.string)")
                }
                XCTAssertEqual(res.status, .ok, res.body.string)
                let body = try res.content.decode(LensSmudgeResponse.self)
                XCTAssertTrue((0.0 ... 1.0).contains(body.confidence), "\(body.confidence)")
            })
        }
    }

    func testSpeechAndTranslationListingsRespond() async throws {
        guard #available(macOS 26.0, *), Capabilities.current.speechTranscription else {
            throw XCTSkip("需要 macOS 26")
        }
        try await withApp { app in
            try await app.test(.GET, "speech/supported-locales", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok, res.body.string)
                let body = try res.content.decode(SpeechLocalesResponse.self)
                // CI 的虚拟机上没有语音模型，列表可能为空；这里只验证接口本身可用
                print("speech supported: \(body.supported.count)，installed: \(body.installed)")
                XCTAssertTrue(Set(body.installed).isSubset(of: Set(body.supported)))
            })
            #if canImport(Translation)
            try await app.test(.GET, "translation/supported-languages", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok, res.body.string)
                let body = try res.content.decode(TranslationLanguagesResponse.self)
                print("translation languages: \(body.languages)")
                XCTAssertFalse(body.languages.isEmpty)
            })
            #endif
        }
    }
    #endif

    // MARK: - PDF

    func testPDFExtractText() async throws {
        let document = try pdf(pages: ["Vision PDF first page", "Vision PDF second page"])
        try await withApp { app in
            try await app.test(.POST, "pdf/extract-text", beforeRequest: { req in
                try req.content.encode(PDFBody(pdfBase64: document, mergePages: true))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let body = try res.content.decode(PDFTextResponse.self)
                XCTAssertEqual(body.totalPages, 2)
                XCTAssertEqual(body.extractedPages.count, 2)
                XCTAssertTrue(body.extractedPages[0].text.contains("first page"), body.extractedPages[0].text)
                XCTAssertTrue(body.extractedPages[1].text.contains("second page"), body.extractedPages[1].text)
                XCTAssertTrue(body.allText?.contains("second page") ?? false)
            })
        }
    }

    func testPDFRenderReturnsPNG() async throws {
        let document = try pdf(pages: ["Vision PDF first page"])
        try await withApp { app in
            try await app.test(.POST, "pdf/render", beforeRequest: { req in
                try req.content.encode(PDFBody(pdfBase64: document, pageIndex: 0, dpi: 72))
            }, afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(res.headers.contentType, .png)
                let bytes = [UInt8](res.body.readableBytesView.prefix(8))
                XCTAssertEqual(bytes, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            })
        }
    }

    func testPDFRenderRejectsOutOfRangePage() async throws {
        let document = try pdf(pages: ["Vision PDF first page"])
        try await withApp { app in
            try await app.test(.POST, "pdf/render", beforeRequest: { req in
                try req.content.encode(PDFBody(pdfBase64: document, pageIndex: 5))
            }, afterResponse: { res async in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testRenderedPDFPageCanBeRecognized() async throws {
        // 扫描件工作流：PDF 渲染成图片后再做 OCR
        let document = try pdf(pages: ["SCANNED INVOICE 4821"])
        try await withApp { app in
            var pageImage = ""
            try await app.test(.POST, "pdf/render", beforeRequest: { req in
                try req.content.encode(PDFBody(pdfBase64: document, pageIndex: 0, dpi: 200))
            }, afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
                pageImage = Data(res.body.readableBytesView).base64EncodedString()
            })
            try await app.test(.POST, "text-detection/recognize-text", beforeRequest: { req in
                try req.content.encode(ImageBody(imageBase64: pageImage, recognitionLanguages: "en-US"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let text = try res.content.decode(recognizeTextResponse.self).text.uppercased()
                XCTAssertTrue(text.contains("INVOICE"), text)
                XCTAssertTrue(text.contains("4821"), text)
            })
        }
    }
}
