// 导入必要的框架
import SwiftOpenAPI
import Vapor
import VisionCore

/// 图像特征处理控制器
/// 提供图像处理相关的API接口，如背景移除等功能
@available(macOS 14.0, *)
struct ImageFeatureController: RouteCollection {
    /// 配置路由
    /// - Parameter routes: 路由构建器
    /// - Throws: 路由配置过程中可能发生的错误
    func boot(routes: RoutesBuilder) throws {
        let imageFeatureRoute = routes.grouped("image-feature")
        // 配置背景移除接口
        imageFeatureRoute.post("background-removal", use: backgroundRemovalRequest)
            .openAPI(
                description: "移除图像背景。",
                body: .type(backgroundRemoval.self),
                contentType: .multipart(.formData),
                response: .type(Data.self),
                responseContentType: MediaType("image", "png")
            )
    }

    /// 处理背景移除请求
    /// - Parameter req: HTTP请求
    /// - Returns: 处理后的图像响应
    /// - Throws: 处理过程中可能发生的错误
    @Sendable func backgroundRemovalRequest(req: Request) async throws -> Response {
        // 解码请求数据
        let requestForm = try req.content.decode(backgroundRemoval.self)

        // 执行前景分割并生成透明背景的 PNG
        let data: Data
        do {
            data = try VisionEngine.removeBackground(imageData: requestForm.imageFile)
        } catch {
            throw httpError(from: error)
        }

        // 构建响应
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.contentType = .png
        response.headers.contentDisposition = .init(.attachment, filename: "image.png")
        return response
    }
}

/// 背景移除请求的数据模型
@OpenAPIDescriptable
struct backgroundRemoval: Content {
    /// 图像文件数据
    var imageFile: Data
}
