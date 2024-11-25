// 导入必要的框架
import CoreGraphics
import CoreImage
import ImageIO
import SwiftOpenAPI
import UniformTypeIdentifiers
import Vapor
import Vision

/// 图像特征处理控制器
/// 提供图像处理相关的API接口，如背景移除等功能
@available(macOS 15.0, *)
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

        // 创建图像处理处理器和请求
        let handler = VNImageRequestHandler(data: requestForm.imageFile)
        let request = VNGenerateForegroundInstanceMaskRequest()

        // 执行前景分割
        try handler.perform([request])

        // 验证结果
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty
        else {
            throw Abort(.internalServerError, reason: "未找到前景实例。")
        }

        // 生成带遮罩的图像
        let finalImage = try observation.generateMaskedImage(
            ofInstances: IndexSet(integersIn: 1 ... observation.allInstances.count),
            from: VNImageRequestHandler(data: requestForm.imageFile),
            croppedToInstancesExtent: true
        )

        // 图像格式转换
        let ciImage = CIImage(cvPixelBuffer: finalImage)
        let context = CIContext(options: nil)

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw Abort(.internalServerError, reason: "图像转换失败。")
        }

        // 创建PNG数据
        let data = NSMutableData()
        guard let imageDestination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Abort(.internalServerError, reason: "创建图像目标失败。")
        }

        // 写入图像数据
        CGImageDestinationAddImage(imageDestination, cgImage, nil)
        CGImageDestinationFinalize(imageDestination)

        // 构建响应
        let response = Response(status: .ok, body: .init(data: data as Data))
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
