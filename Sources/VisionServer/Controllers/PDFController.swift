// 导入必要的框架
import Foundation
import SwiftOpenAPI
import Vapor
import VisionCore

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
        
        // 渲染指定页面（默认第一页、150 DPI）
        let pageIndex = data.pageIndex ?? 0
        let pngData: Data
        do {
            pngData = try PDFEngine.renderPage(pdfData: pdfData, pageIndex: pageIndex, dpi: data.dpi ?? 150.0)
        } catch {
            throw httpError(from: error)
        }

        // 返回PNG响应
        let response = Response(status: .ok)
        response.headers.contentType = .png
        response.headers.add(name: .contentDisposition, value: "attachment; filename=\"page_\(pageIndex + 1).png\"")
        response.body = .init(data: pngData)
        
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
        
        // 抽取内嵌文本
        do {
            return try PDFEngine.extractText(
                pdfData: pdfData,
                startPage: data.startPage,
                endPage: data.endPage,
                mergePages: data.mergePages == true
            )
        } catch {
            throw httpError(from: error)
        }
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

// 响应模型 PDFPageText、PDFTextResponse 定义在 VisionCore 中
