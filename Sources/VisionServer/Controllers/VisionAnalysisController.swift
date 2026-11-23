import SwiftOpenAPI
import Vapor
import VisionCore

struct VisionAnalysisController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let visionRoute = routes.grouped("vision")

        visionRoute.post("classify", use: classifyImageRequest)
            .openAPI(
                description: "图像分类：使用 Vision 框架对图像内容进行分类识别。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(ClassificationResponse.self)
            )

        visionRoute.post("detect-objects", use: detectObjectsRequest)
            .openAPI(
                description: "物体检测：检测图像中的物体和人脸特征。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(ObjectDetectionResponse.self)
            )

        visionRoute.post("scan-barcode", use: scanBarcodeRequest)
            .openAPI(
                description: "条码识别：扫描并解码图像中的条形码和二维码。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(BarcodeResponse.self)
            )
    }

    // MARK: - Image Classification

    @Sendable func classifyImageRequest(req: Request) async throws -> ClassificationResponse {
        let imageData = try await ImageInput.decode(from: req)
        return ClassificationResponse(classifications: try VisionEngine.classify(imageData: imageData))
    }

    // MARK: - Object Detection

    @Sendable func detectObjectsRequest(req: Request) async throws -> ObjectDetectionResponse {
        let imageData = try await ImageInput.decode(from: req)
        return ObjectDetectionResponse(objects: try VisionEngine.detectObjects(imageData: imageData))
    }

    // MARK: - Barcode Recognition

    @Sendable func scanBarcodeRequest(req: Request) async throws -> BarcodeResponse {
        let imageData = try await ImageInput.decode(from: req)
        return BarcodeResponse(barcodes: try VisionEngine.scanBarcodes(imageData: imageData))
    }
}

// MARK: - Request Models
// 响应模型定义在 VisionCore 中（ClassificationResponse、ObjectDetectionResponse、BarcodeResponse）

@OpenAPIDescriptable
struct VisionImageInput: Content {
    var imageFile: Data?
    var imagePath: String?
    var imageURL: String?
    var imageBase64: String?
}
