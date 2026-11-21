import CoreGraphics
import Foundation
import PDFKit
import SwiftOpenAPI
import Vapor

/// PDF 处理控制器：渲染为位图、文本抽取
struct PDFController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("pdf")

        group.post("render", use: renderPDFRequest)
            .openAPI(
                description: "把 PDF 的某一页渲染为 PNG。pageIndex 从 0 开始，dpi 范围 36~600（默认 150）。",
                body: .type(PDFRenderRequest.self),
                contentType: .multipart(.formData),
                response: .type(Data.self),
                responseContentType: MediaType("image", "png")
            )

        group.post("extract-text", use: extractTextRequest)
            .openAPI(
                description: "抽取 PDF 的文本层。startPage / endPage 从 0 开始；mergePages=true 时额外返回合并文本。",
                body: .type(PDFTextRequest.self),
                contentType: .multipart(.formData),
                response: .type(PDFTextResponse.self)
            )
    }

    @Sendable
    func renderPDFRequest(req: Request) async throws -> Response {
        let pdfData = try await InputResolver.resolve(from: req, prefix: "pdf", label: "PDF").data
        let pageIndex = (try? req.content.get(Int.self, at: "pageIndex")) ?? 0
        let dpi = min(max((try? req.content.get(Double.self, at: "dpi")) ?? 150, 36), 600)

        let png = try await Offload.run(req) {
            guard let document = PDFDocument(data: pdfData) else {
                throw Abort(.badRequest, reason: "无效的PDF文件格式")
            }
            guard pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) else {
                throw Abort(.badRequest, reason: "页面索引超出范围，PDF共有\(document.pageCount)页")
            }

            let scale = dpi / 72.0 // PDF 默认 72 DPI
            let mediaBox = page.bounds(for: .mediaBox)
            let width = Int((mediaBox.width * scale).rounded())
            let height = Int((mediaBox.height * scale).rounded())
            guard width > 0, height > 0 else {
                throw Abort(.badRequest, reason: "页面尺寸无效")
            }

            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw Abort(.internalServerError, reason: "无法创建渲染上下文")
            }

            // 白色背景
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)

            guard let image = context.makeImage() else {
                throw Abort(.internalServerError, reason: "渲染失败")
            }
            return try VisionSupport.pngData(from: image)
        }

        return VisionSupport.pngResponse(png, filename: "page_\(pageIndex + 1).png")
    }

    @Sendable
    func extractTextRequest(req: Request) async throws -> PDFTextResponse {
        let pdfData = try await InputResolver.resolve(from: req, prefix: "pdf", label: "PDF").data
        let requestedStart = try? req.content.get(Int.self, at: "startPage")
        let requestedEnd = try? req.content.get(Int.self, at: "endPage")
        let mergePages = (try? req.content.get(Bool.self, at: "mergePages")) ?? false

        return try await Offload.run(req) {
            guard let document = PDFDocument(data: pdfData) else {
                throw Abort(.badRequest, reason: "无效的PDF文件格式")
            }

            let pageCount = document.pageCount
            guard pageCount > 0 else {
                return PDFTextResponse(totalPages: 0, extractedPages: [], allText: mergePages ? "" : nil)
            }

            let startPage = requestedStart ?? 0
            let endPage = requestedEnd ?? (pageCount - 1)

            guard startPage >= 0, startPage < pageCount else {
                throw Abort(.badRequest, reason: "起始页面索引超出范围")
            }
            guard endPage >= startPage, endPage < pageCount else {
                throw Abort(.badRequest, reason: "结束页面索引无效")
            }

            var pages: [PDFPageText] = []
            for index in startPage ... endPage {
                guard let page = document.page(at: index) else { continue }
                pages.append(PDFPageText(pageNumber: index + 1, text: page.string ?? ""))
            }

            return PDFTextResponse(
                totalPages: pageCount,
                extractedPages: pages,
                allText: mergePages ? pages.map(\.text).joined(separator: "\n\n") : nil
            )
        }
    }
}

// MARK: - 请求和响应模型

/// PDF 渲染请求（仅用于 OpenAPI 文档）
@OpenAPIDescriptable
struct PDFRenderRequest: Content {
    /// 上传的 PDF 文件
    var pdfFile: Data?
    /// 服务器本地 PDF 路径（需开启 VISION_ALLOW_LOCAL_FILES）
    var pdfPath: String?
    /// 远程 PDF URL
    var pdfURL: String?
    /// Base64 编码的 PDF 数据
    var pdfBase64: String?
    /// 页面索引，从 0 开始
    var pageIndex: Int?
    /// 输出 DPI，默认 150
    var dpi: Double?
}

/// PDF 文本抽取请求（仅用于 OpenAPI 文档）
@OpenAPIDescriptable
struct PDFTextRequest: Content {
    /// 上传的 PDF 文件
    var pdfFile: Data?
    /// 服务器本地 PDF 路径（需开启 VISION_ALLOW_LOCAL_FILES）
    var pdfPath: String?
    /// 远程 PDF URL
    var pdfURL: String?
    /// Base64 编码的 PDF 数据
    var pdfBase64: String?
    /// 起始页面，从 0 开始
    var startPage: Int?
    /// 结束页面
    var endPage: Int?
    /// 是否合并所有页面文本
    var mergePages: Bool?
}

struct PDFPageText: Content {
    var pageNumber: Int
    var text: String
}

struct PDFTextResponse: Content {
    var totalPages: Int
    var extractedPages: [PDFPageText]
    var allText: String?
}
