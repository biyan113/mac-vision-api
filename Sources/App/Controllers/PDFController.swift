// 导入必要的框架
import CoreGraphics
import Foundation
import PDFKit
import SwiftOpenAPI
import UniformTypeIdentifiers
import Vapor

/// PDF处理控制器
/// 提供PDF处理相关的API接口，如渲染为位图、文本抽取等功能
struct PDFController: RouteCollection {
    /// 配置路由
    /// - Parameter routes: 路由构建器
    /// - Throws: 路由配置过程中可能发生的错误
    func boot(routes: RoutesBuilder) throws {
        let pdfRoute = routes.grouped("pdf")
        
        // 配置PDF渲染为位图接口
        pdfRoute.post("render", use: renderPDFRequest)
        
        // 配置PDF文本抽取接口
        pdfRoute.post("extract-text", use: extractTextRequest)
    }
    
    /// PDF渲染为位图请求处理
    /// - Parameter req: HTTP请求
    /// - Returns: 渲染后的图片数据
    /// - Throws: 处理过程中可能发生的错误
    @Sendable
    func renderPDFRequest(req: Request) async throws -> Response {
        // 添加调试日志
        req.logger.info("PDF渲染请求开始")
        req.logger.info("Content-Type: \(req.headers.contentType?.description ?? "未知")")
        req.logger.info("Content-Length: \(req.headers.first(name: .contentLength) ?? "未知")")
        
        let data = try await req.content.decode(PDFRenderRequest.self)
        req.logger.info("请求解析成功")
        
        // 获取PDF数据
        let pdfData = try await getPDFData(from: data, req: req)
        req.logger.info("PDF数据获取成功，大小: \(pdfData.count) bytes")
        
        // 创建PDF文档
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            throw Abort(.badRequest, reason: "无效的PDF文件格式")
        }
        
        // 验证页面索引
        let pageCount = pdfDocument.pageCount
        let pageIndex = data.pageIndex ?? 0
        
        guard pageIndex >= 0 && pageIndex < pageCount else {
            throw Abort(.badRequest, reason: "页面索引超出范围，PDF共有\(pageCount)页")
        }
        
        // 获取指定页面
        guard let page = pdfDocument.page(at: pageIndex) else {
            throw Abort(.badRequest, reason: "无法获取第\(pageIndex + 1)页")
        }
        
        // 设置渲染参数
        let dpi = data.dpi ?? 150.0
        let scale = dpi / 72.0 // PDF默认72 DPI
        
        // 获取页面边界
        let mediaBox = page.bounds(for: .mediaBox)
        let renderSize = CGSize(
            width: mediaBox.width * scale,
            height: mediaBox.height * scale
        )
        
        // 创建位图上下文
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw Abort(.internalServerError, reason: "无法创建渲染上下文")
        }
        
        // 设置背景色为白色
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        context.fill(CGRect(origin: .zero, size: renderSize))
        
        // 缩放上下文以匹配DPI
        context.scaleBy(x: scale, y: scale)
        
        // 渲染PDF页面
        page.draw(with: .mediaBox, to: context)
        
        // 创建CGImage
        guard let cgImage = context.makeImage() else {
            throw Abort(.internalServerError, reason: "渲染失败")
        }
        
        // 转换为PNG数据
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw Abort(.internalServerError, reason: "无法创建图像目标")
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Abort(.internalServerError, reason: "图像编码失败")
        }
        
        // 返回PNG响应
        let response = Response(status: .ok)
        response.headers.contentType = .png
        response.headers.add(name: .contentDisposition, value: "attachment; filename=\"page_\(pageIndex + 1).png\"")
        response.body = .init(data: mutableData as Data)
        
        return response
    }
    
    /// PDF文本抽取请求处理
    /// - Parameter req: HTTP请求
    /// - Returns: 抽取的文本内容
    /// - Throws: 处理过程中可能发生的错误
    @Sendable
    func extractTextRequest(req: Request) async throws -> PDFTextResponse {
        let data = try await req.content.decode(PDFTextRequest.self)
        
        // 获取PDF数据
        let pdfData = try await getPDFData(from: data, req: req)
        
        // 创建PDF文档
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            throw Abort(.badRequest, reason: "无效的PDF文件格式")
        }
        
        let pageCount = pdfDocument.pageCount
        var extractedPages: [PDFPageText] = []
        
        // 确定要处理的页面范围
        let startPage = data.startPage ?? 0
        let endPage = data.endPage ?? (pageCount - 1)
        
        guard startPage >= 0 && startPage < pageCount else {
            throw Abort(.badRequest, reason: "起始页面索引超出范围")
        }
        
        guard endPage >= startPage && endPage < pageCount else {
            throw Abort(.badRequest, reason: "结束页面索引无效")
        }
        
        // 逐页抽取文本
        for pageIndex in startPage...endPage {
            guard let page = pdfDocument.page(at: pageIndex) else {
                continue
            }
            
            let pageText = page.string ?? ""
            extractedPages.append(PDFPageText(
                pageNumber: pageIndex + 1,
                text: pageText
            ))
        }
        
        // 如果需要合并所有页面文本
        let allText = data.mergePages == true ? 
            extractedPages.map { $0.text }.joined(separator: "\n\n") : nil
        
        return PDFTextResponse(
            totalPages: pageCount,
            extractedPages: extractedPages,
            allText: allText
        )
    }
    
    /// 从请求中获取PDF数据
    /// - Parameters:
    ///   - data: 请求数据
    ///   - req: HTTP请求
    /// - Returns: PDF数据
    /// - Throws: 处理过程中可能发生的错误
    private func getPDFData(from data: PDFDataSource, req: Request) async throws -> Data {
        // 优先级：文件上传 > 本地路径 > 远程URL > Base64
        
        if let file = data.pdfFile {
            let pdfData = Data(buffer: file.data)
            // 检查文件数据是否为空
            guard !pdfData.isEmpty else {
                throw Abort(.badRequest, reason: "上传的PDF文件为空")
            }
            return pdfData
        }
        
        if let filePath = data.pdfPath, !filePath.isEmpty {
            let url = URL(fileURLWithPath: filePath)
            return try Data(contentsOf: url)
        }
        
        if let urlString = data.pdfURL, !urlString.isEmpty {
            guard let url = URL(string: urlString) else {
                throw Abort(.badRequest, reason: "无效的URL格式")
            }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
        
        if let base64String = data.pdfBase64, !base64String.isEmpty {
            // 处理data URL格式
            let cleanBase64: String
            if base64String.hasPrefix("data:") {
                guard let commaIndex = base64String.firstIndex(of: ",") else {
                    throw Abort(.badRequest, reason: "无效的Base64 data URL格式")
                }
                cleanBase64 = String(base64String[base64String.index(after: commaIndex)...])
            } else {
                cleanBase64 = base64String
            }
            
            guard let data = Data(base64Encoded: cleanBase64) else {
                throw Abort(.badRequest, reason: "无效的Base64编码")
            }
            return data
        }
        
        throw Abort(.badRequest, reason: "请提供PDF文件、本地路径、远程URL或Base64编码数据其中之一")
    }
}

// MARK: - 请求和响应模型

/// PDF数据源协议
protocol PDFDataSource {
    var pdfFile: File? { get }
    var pdfPath: String? { get }
    var pdfURL: String? { get }
    var pdfBase64: String? { get }
}

/// PDF渲染请求
struct PDFRenderRequest: Content, PDFDataSource {
    let pdfFile: File?
    let pdfPath: String?
    let pdfURL: String?
    let pdfBase64: String?
    let pageIndex: Int? // 页面索引，从0开始
    let dpi: Double? // 输出DPI，默认150
}

/// PDF文本抽取请求
struct PDFTextRequest: Content, PDFDataSource {
    let pdfFile: File?
    let pdfPath: String?
    let pdfURL: String?
    let pdfBase64: String?
    let startPage: Int? // 起始页面，从0开始
    let endPage: Int? // 结束页面
    let mergePages: Bool? // 是否合并所有页面文本
}

/// PDF页面文本
struct PDFPageText: Content {
    let pageNumber: Int
    let text: String
}

/// PDF文本抽取响应
struct PDFTextResponse: Content {
    let totalPages: Int
    let extractedPages: [PDFPageText]
    let allText: String?
}
