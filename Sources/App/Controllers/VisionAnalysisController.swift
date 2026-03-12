import SwiftOpenAPI
import Vapor
import Vision

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
        let imageData = try decodeImageInput(req: req)
        let handler = VNImageRequestHandler(data: imageData)
        let request = VNClassifyImageRequest()

        try handler.perform([request])

        let results = (request.results ?? [])
            .filter { $0.confidence > 0.01 }
            .prefix(10)
            .map { ClassificationResult(identifier: $0.identifier, confidence: Double($0.confidence)) }

        return ClassificationResponse(classifications: Array(results))
    }

    // MARK: - Object Detection

    @Sendable func detectObjectsRequest(req: Request) async throws -> ObjectDetectionResponse {
        let imageData = try decodeImageInput(req: req)
        let handler = VNImageRequestHandler(data: imageData)

        // 物体识别
        let recognizeRequest = VNRecognizeAnimalsRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()

        try handler.perform([recognizeRequest, faceRequest, humanRequest])

        let animals = (recognizeRequest.results ?? []).map { obs in
            DetectedObject(
                label: obs.labels.first?.identifier ?? "animal",
                confidence: Double(obs.labels.first?.confidence ?? 0),
                boundingBox: boundingBoxDict(obs.boundingBox)
            )
        }

        let faces = (faceRequest.results ?? []).map { obs in
            DetectedObject(
                label: "face",
                confidence: Double(obs.confidence),
                boundingBox: boundingBoxDict(obs.boundingBox)
            )
        }

        let humans = (humanRequest.results ?? []).map { obs in
            DetectedObject(
                label: "human",
                confidence: Double(obs.confidence),
                boundingBox: boundingBoxDict(obs.boundingBox)
            )
        }

        return ObjectDetectionResponse(objects: animals + faces + humans)
    }

    // MARK: - Barcode Recognition

    @Sendable func scanBarcodeRequest(req: Request) async throws -> BarcodeResponse {
        let imageData = try decodeImageInput(req: req)
        let handler = VNImageRequestHandler(data: imageData)
        let request = VNDetectBarcodesRequest()

        try handler.perform([request])

        let barcodes = (request.results ?? []).map { obs in
            BarcodeResult(
                payload: obs.payloadStringValue ?? "",
                symbology: obs.symbology.rawValue,
                boundingBox: boundingBoxDict(obs.boundingBox)
            )
        }

        return BarcodeResponse(barcodes: barcodes)
    }

    // MARK: - Helpers

    private func decodeImageInput(req: Request) throws -> Data {
        if let imageFile = try? req.content.get(Data.self, at: "imageFile") {
            return imageFile
        } else if let imagePath = try? req.content.get(String.self, at: "imagePath"),
                  let data = FileManager.default.contents(atPath: imagePath) {
            return data
        } else if let imageURL = try? req.content.get(String.self, at: "imageURL") {
            let response = try req.application.client.get(URI(string: imageURL)).wait()
            guard let body = response.body else {
                throw Abort(.badRequest, reason: "无法从 URL 获取图片数据")
            }
            return Data(buffer: body)
        } else if let base64 = try? req.content.get(String.self, at: "imageBase64"),
                  let data = Data(base64Encoded: base64.components(separatedBy: ",").last ?? base64) {
            return data
        }
        throw Abort(.badRequest, reason: "请提供 imageFile、imagePath、imageURL 或 imageBase64 之一")
    }

    private func boundingBoxDict(_ rect: CGRect) -> BoundingBox {
        BoundingBox(x: Double(rect.origin.x), y: Double(rect.origin.y),
                    width: Double(rect.width), height: Double(rect.height))
    }
}

// MARK: - Request / Response Models

@OpenAPIDescriptable
struct VisionImageInput: Content {
    var imageFile: Data?
    var imagePath: String?
    var imageURL: String?
    var imageBase64: String?
}

struct ClassificationResult: Content {
    var identifier: String
    var confidence: Double
}

struct ClassificationResponse: Content {
    var classifications: [ClassificationResult]
}

struct BoundingBox: Content {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct DetectedObject: Content {
    var label: String
    var confidence: Double
    var boundingBox: BoundingBox
}

struct ObjectDetectionResponse: Content {
    var objects: [DetectedObject]
}

struct BarcodeResult: Content {
    var payload: String
    var symbology: String
    var boundingBox: BoundingBox
}

struct BarcodeResponse: Content {
    var barcodes: [BarcodeResult]
}
