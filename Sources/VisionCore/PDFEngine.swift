import CoreGraphics
import Foundation
import PDFKit

/// 对 PDFKit 的封装：页面渲染与内嵌文本抽取
public enum PDFEngine {
    /// 判断数据是否像一个 PDF 文件（以 "%PDF" 开头）
    public static func looksLikePDF(_ data: Data) -> Bool {
        data.prefix(4) == Data("%PDF".utf8)
    }

    /// PDF 的总页数
    public static func pageCount(pdfData: Data) throws -> Int {
        guard let document = PDFDocument(data: pdfData) else {
            throw VisionCoreError.invalidPDF
        }
        return document.pageCount
    }

    /// 把指定页渲染为 PNG
    /// - Parameters:
    ///   - pageIndex: 页面索引，从 0 开始
    ///   - dpi: 输出分辨率，PDF 的原始分辨率为 72
    public static func renderPage(pdfData: Data, pageIndex: Int = 0, dpi: Double = 150) throws -> Data {
        guard let document = PDFDocument(data: pdfData) else {
            throw VisionCoreError.invalidPDF
        }

        let pageCount = document.pageCount
        guard pageIndex >= 0, pageIndex < pageCount else {
            throw VisionCoreError.pageOutOfRange(pageCount: pageCount)
        }
        guard let page = document.page(at: pageIndex) else {
            throw VisionCoreError.pageUnavailable(pageNumber: pageIndex + 1)
        }

        let scale = CGFloat(dpi / 72.0)
        let mediaBox = page.bounds(for: .mediaBox)
        let renderSize = CGSize(width: mediaBox.width * scale, height: mediaBox.height * scale)

        guard let context = CGContext(
            data: nil,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisionCoreError.imageConversionFailed("无法创建渲染上下文")
        }

        // 白色背景
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        context.fill(CGRect(origin: .zero, size: renderSize))

        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let image = context.makeImage() else {
            throw VisionCoreError.imageConversionFailed("渲染失败")
        }
        return try ImageCoding.pngData(from: image)
    }

    /// 抽取 PDF 内嵌的文本（不做 OCR）
    /// - Parameters:
    ///   - startPage: 起始页索引，从 0 开始，默认第一页
    ///   - endPage: 结束页索引（包含），默认最后一页
    ///   - mergePages: 是否在 `allText` 中给出合并后的全文
    public static func extractText(
        pdfData: Data,
        startPage: Int? = nil,
        endPage: Int? = nil,
        mergePages: Bool = false
    ) throws -> PDFTextResponse {
        guard let document = PDFDocument(data: pdfData) else {
            throw VisionCoreError.invalidPDF
        }

        let pageCount = document.pageCount
        let start = startPage ?? 0
        let end = endPage ?? (pageCount - 1)

        guard start >= 0, start < pageCount else {
            throw VisionCoreError.invalidPageRange("起始页面索引超出范围")
        }
        guard end >= start, end < pageCount else {
            throw VisionCoreError.invalidPageRange("结束页面索引无效")
        }

        var pages: [PDFPageText] = []
        for index in start...end {
            guard let page = document.page(at: index) else { continue }
            pages.append(PDFPageText(pageNumber: index + 1, text: page.string ?? ""))
        }

        let allText = mergePages ? pages.map { $0.text }.joined(separator: "\n\n") : nil
        return PDFTextResponse(totalPages: pageCount, extractedPages: pages, allText: allText)
    }
}
