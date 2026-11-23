import CoreGraphics
import Foundation
import ImageIO
import SwiftOpenAPI
import UniformTypeIdentifiers
import Vapor
import Vision

/// 归一化矩形（0~1），原点在图像左下角
struct BoundingBox: Content {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.width)
        height = Double(rect.height)
    }
}

/// 归一化坐标点
struct Point2D: Content {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }
}

/// 带置信度的关键点
struct KeyPoint: Content {
    var x: Double
    var y: Double
    var confidence: Double
}

/// 通用图片输入（仅用于 OpenAPI 文档）
@OpenAPIDescriptable
struct VisionImageInput: Content {
    /// 上传的图像文件
    var imageFile: Data?
    /// 服务器本地图片路径（需开启 VISION_ALLOW_LOCAL_FILES）
    var imagePath: String?
    /// 远程图片 URL
    var imageURL: String?
    /// Base64 编码的图片数据（可带 data URL 前缀）
    var imageBase64: String?
}

enum VisionSupport {
    /// 执行 Vision 请求，并把框架错误转换为 422
    static func perform(_ requests: [VNRequest], on data: Data) throws {
        let handler = VNImageRequestHandler(data: data)
        do {
            try handler.perform(requests)
        } catch {
            throw Abort(.unprocessableEntity, reason: "无法处理该图片：\(error.localizedDescription)")
        }
    }

    /// 把 CGImage 编码为 PNG
    static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Abort(.internalServerError, reason: "创建图像目标失败")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Abort(.internalServerError, reason: "图像编码失败")
        }
        return data as Data
    }

    static func pngResponse(_ data: Data, filename: String) -> Response {
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.contentType = .png
        response.headers.contentDisposition = .init(.attachment, filename: filename)
        return response
    }
}
