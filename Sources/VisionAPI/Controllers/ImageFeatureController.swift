import CoreGraphics
import CoreImage
import SwiftOpenAPI
import Vapor
import Vision

/// 图像特征处理控制器：背景移除
@available(macOS 14.0, *)
struct ImageFeatureController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("image-feature")
        group.post("background-removal", use: backgroundRemovalRequest)
            .openAPI(
                description: "移除图像背景，返回透明背景的 PNG。crop=false 时保留原始画布尺寸。",
                body: .type(backgroundRemoval.self),
                contentType: .multipart(.formData),
                response: .type(Data.self),
                responseContentType: MediaType("image", "png")
            )
    }

    @Sendable func backgroundRemovalRequest(req: Request) async throws -> Response {
        let imageData = try await InputResolver.image(from: req)
        let crop = (try? req.content.get(Bool.self, at: "crop")) ?? true

        let png = try await Offload.run(req) {
            let handler = VNImageRequestHandler(data: imageData)
            let request = VNGenerateForegroundInstanceMaskRequest()

            do {
                try handler.perform([request])
            } catch {
                throw Abort(.unprocessableEntity, reason: "无法处理该图片：\(error.localizedDescription)")
            }

            guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                throw Abort(.unprocessableEntity, reason: "未在图片中找到前景主体")
            }

            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: crop
            )

            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = CIContext(options: nil).createCGImage(ciImage, from: ciImage.extent) else {
                throw Abort(.internalServerError, reason: "图像转换失败")
            }
            return try VisionSupport.pngData(from: cgImage)
        }

        return VisionSupport.pngResponse(png, filename: "image.png")
    }
}

/// 背景移除请求模型（仅用于 OpenAPI 文档）
@OpenAPIDescriptable
struct backgroundRemoval: Content {
    /// 上传的图像文件
    var imageFile: Data?
    /// 服务器本地图片路径（需开启 VISION_ALLOW_LOCAL_FILES）
    var imagePath: String?
    /// 远程图片 URL
    var imageURL: String?
    /// Base64 编码的图片数据
    var imageBase64: String?
    /// 是否裁剪到主体范围，默认 true
    var crop: Bool?
}

/// 图像美学评分：macOS 15.0+
@available(macOS 15.0, *)
struct AestheticsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.grouped("vision").post("aesthetics", use: aestheticsRequest)
            .openAPI(
                description: "图像美学评分：overallScore 范围 -1~1，isUtility 表示截图、票据等工具类图片。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(AestheticsResponse.self)
            )
    }

    @Sendable func aestheticsRequest(req: Request) async throws -> AestheticsResponse {
        let imageData = try await InputResolver.image(from: req)
        return try await Offload.run(req) {
            let request = VNCalculateImageAestheticsScoresRequest()
            try VisionSupport.perform([request], on: imageData)
            guard let result = request.results?.first else {
                throw Abort(.unprocessableEntity, reason: "无法计算该图片的美学评分")
            }
            return AestheticsResponse(overallScore: Double(result.overallScore), isUtility: result.isUtility)
        }
    }
}

struct AestheticsResponse: Content {
    var overallScore: Double
    var isUtility: Bool
}
