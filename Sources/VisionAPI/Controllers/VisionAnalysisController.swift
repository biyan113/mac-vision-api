import SwiftOpenAPI
import Vapor
import Vision

/// 视觉分析控制器：分类、检测、条码、人脸关键点、姿态、显著性、矩形、地平线
struct VisionAnalysisController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("vision")

        group.post("classify", use: classifyImageRequest)
            .openAPI(
                description: "图像分类：返回置信度最高的若干类别。可用 maxResults 指定数量（默认 10）。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(ClassificationResponse.self)
            )

        group.post("detect-objects", use: detectObjectsRequest)
            .openAPI(
                description: "物体检测：检测图像中的动物（猫、狗）、人脸与人体。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(ObjectDetectionResponse.self)
            )

        group.post("scan-barcode", use: scanBarcodeRequest)
            .openAPI(
                description: "条码识别：扫描并解码图像中的条形码和二维码。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(BarcodeResponse.self)
            )

        group.post("detect-faces", use: detectFacesRequest)
            .openAPI(
                description: "人脸检测与关键点：返回人脸位置、姿态角以及眼睛、鼻子、嘴唇等关键点（坐标相对于人脸框）。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(FaceDetectionResponse.self)
            )

        group.post("detect-body-pose", use: detectBodyPoseRequest)
            .openAPI(
                description: "人体姿态估计：返回每个人的关节点坐标与置信度。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(PoseResponse.self)
            )

        group.post("detect-hand-pose", use: detectHandPoseRequest)
            .openAPI(
                description: "手部姿态估计：返回每只手的关节点坐标与左右手信息。可用 maxHands 指定最多检测数量（默认 2）。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(PoseResponse.self)
            )

        group.post("saliency", use: saliencyRequest)
            .openAPI(
                description: "显著性分析：返回图像中最吸引注意的区域。type=attention（默认）或 objectness。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(SaliencyResponse.self)
            )

        group.post("detect-rectangles", use: detectRectanglesRequest)
            .openAPI(
                description: "矩形检测：检测文档、卡片、屏幕等矩形区域并返回四个角点。可用 maxResults 指定数量（默认 10）。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(RectangleResponse.self)
            )

        group.post("detect-horizon", use: detectHorizonRequest)
            .openAPI(
                description: "地平线检测：返回图像的倾斜角度，可用于自动校正。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(HorizonResponse.self)
            )
    }

    // MARK: - 图像分类

    @Sendable func classifyImageRequest(req: Request) async throws -> ClassificationResponse {
        let imageData = try await InputResolver.image(from: req)
        let maxResults = min(max((try? req.content.get(Int.self, at: "maxResults")) ?? 10, 1), 100)

        return try await Offload.run(req) {
            let request = VNClassifyImageRequest()
            try VisionSupport.perform([request], on: imageData)

            let results = (request.results ?? [])
                .filter { $0.confidence > 0.01 }
                .prefix(maxResults)
                .map { ClassificationResult(identifier: $0.identifier, confidence: Double($0.confidence)) }

            return ClassificationResponse(classifications: Array(results))
        }
    }

    // MARK: - 物体检测

    @Sendable func detectObjectsRequest(req: Request) async throws -> ObjectDetectionResponse {
        let imageData = try await InputResolver.image(from: req)

        return try await Offload.run(req) {
            let animalRequest = VNRecognizeAnimalsRequest()
            let faceRequest = VNDetectFaceRectanglesRequest()
            let humanRequest = VNDetectHumanRectanglesRequest()

            try VisionSupport.perform([animalRequest, faceRequest, humanRequest], on: imageData)

            let animals = (animalRequest.results ?? []).map { obs in
                DetectedObject(
                    label: obs.labels.first?.identifier ?? "animal",
                    confidence: Double(obs.labels.first?.confidence ?? 0),
                    boundingBox: BoundingBox(obs.boundingBox)
                )
            }
            let faces = (faceRequest.results ?? []).map { obs in
                DetectedObject(label: "face", confidence: Double(obs.confidence), boundingBox: BoundingBox(obs.boundingBox))
            }
            let humans = (humanRequest.results ?? []).map { obs in
                DetectedObject(label: "human", confidence: Double(obs.confidence), boundingBox: BoundingBox(obs.boundingBox))
            }

            return ObjectDetectionResponse(objects: animals + faces + humans)
        }
    }

    // MARK: - 条码识别

    @Sendable func scanBarcodeRequest(req: Request) async throws -> BarcodeResponse {
        let imageData = try await InputResolver.image(from: req)

        return try await Offload.run(req) {
            let request = VNDetectBarcodesRequest()
            try VisionSupport.perform([request], on: imageData)

            let barcodes = (request.results ?? []).map { obs in
                BarcodeResult(
                    payload: obs.payloadStringValue ?? "",
                    symbology: obs.symbology.rawValue,
                    boundingBox: BoundingBox(obs.boundingBox)
                )
            }
            return BarcodeResponse(barcodes: barcodes)
        }
    }

    // MARK: - 人脸关键点

    @Sendable func detectFacesRequest(req: Request) async throws -> FaceDetectionResponse {
        let imageData = try await InputResolver.image(from: req)

        return try await Offload.run(req) {
            let request = VNDetectFaceLandmarksRequest()
            try VisionSupport.perform([request], on: imageData)

            let faces = (request.results ?? []).map { obs -> DetectedFace in
                var landmarks: [String: [Point2D]] = [:]
                if let all = obs.landmarks {
                    let regions: [(String, VNFaceLandmarkRegion2D?)] = [
                        ("faceContour", all.faceContour),
                        ("leftEye", all.leftEye),
                        ("rightEye", all.rightEye),
                        ("leftEyebrow", all.leftEyebrow),
                        ("rightEyebrow", all.rightEyebrow),
                        ("nose", all.nose),
                        ("noseCrest", all.noseCrest),
                        ("medianLine", all.medianLine),
                        ("outerLips", all.outerLips),
                        ("innerLips", all.innerLips),
                        ("leftPupil", all.leftPupil),
                        ("rightPupil", all.rightPupil),
                    ]
                    for (name, region) in regions {
                        if let region {
                            landmarks[name] = region.normalizedPoints.map { Point2D($0) }
                        }
                    }
                }
                return DetectedFace(
                    boundingBox: BoundingBox(obs.boundingBox),
                    confidence: Double(obs.confidence),
                    roll: obs.roll?.doubleValue,
                    yaw: obs.yaw?.doubleValue,
                    pitch: obs.pitch?.doubleValue,
                    landmarks: landmarks
                )
            }
            return FaceDetectionResponse(faces: faces)
        }
    }

    // MARK: - 人体姿态

    @Sendable func detectBodyPoseRequest(req: Request) async throws -> PoseResponse {
        let imageData = try await InputResolver.image(from: req)

        return try await Offload.run(req) {
            let request = VNDetectHumanBodyPoseRequest()
            try VisionSupport.perform([request], on: imageData)

            let poses = try (request.results ?? []).map { obs -> DetectedPose in
                var joints: [String: KeyPoint] = [:]
                for (name, point) in try obs.recognizedPoints(.all) where point.confidence > 0 {
                    joints[name.rawValue.rawValue] = KeyPoint(
                        x: Double(point.location.x), y: Double(point.location.y), confidence: Double(point.confidence)
                    )
                }
                return DetectedPose(confidence: Double(obs.confidence), chirality: nil, joints: joints)
            }
            return PoseResponse(poses: poses)
        }
    }

    // MARK: - 手部姿态

    @Sendable func detectHandPoseRequest(req: Request) async throws -> PoseResponse {
        let imageData = try await InputResolver.image(from: req)
        let maxHands = min(max((try? req.content.get(Int.self, at: "maxHands")) ?? 2, 1), 10)

        return try await Offload.run(req) {
            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = maxHands
            try VisionSupport.perform([request], on: imageData)

            let poses = try (request.results ?? []).map { obs -> DetectedPose in
                var joints: [String: KeyPoint] = [:]
                for (name, point) in try obs.recognizedPoints(.all) where point.confidence > 0 {
                    joints[name.rawValue.rawValue] = KeyPoint(
                        x: Double(point.location.x), y: Double(point.location.y), confidence: Double(point.confidence)
                    )
                }
                let chirality: String
                switch obs.chirality {
                case .left: chirality = "left"
                case .right: chirality = "right"
                default: chirality = "unknown"
                }
                return DetectedPose(confidence: Double(obs.confidence), chirality: chirality, joints: joints)
            }
            return PoseResponse(poses: poses)
        }
    }

    // MARK: - 显著性

    @Sendable func saliencyRequest(req: Request) async throws -> SaliencyResponse {
        let imageData = try await InputResolver.image(from: req)
        let type = ((try? req.content.get(String.self, at: "type")) ?? "attention").lowercased()
        guard type == "attention" || type == "objectness" else {
            throw Abort(.badRequest, reason: "type 只能是 attention 或 objectness")
        }

        return try await Offload.run(req) {
            let request: VNImageBasedRequest = type == "objectness"
                ? VNGenerateObjectnessBasedSaliencyImageRequest()
                : VNGenerateAttentionBasedSaliencyImageRequest()
            try VisionSupport.perform([request], on: imageData)

            let observation = request.results?.first as? VNSaliencyImageObservation
            let regions = (observation?.salientObjects ?? []).map { obj in
                SalientRegion(boundingBox: BoundingBox(obj.boundingBox), confidence: Double(obj.confidence))
            }
            return SaliencyResponse(type: type, regions: regions)
        }
    }

    // MARK: - 矩形检测

    @Sendable func detectRectanglesRequest(req: Request) async throws -> RectangleResponse {
        let imageData = try await InputResolver.image(from: req)
        let maxResults = min(max((try? req.content.get(Int.self, at: "maxResults")) ?? 10, 1), 50)

        return try await Offload.run(req) {
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = maxResults
            try VisionSupport.perform([request], on: imageData)

            let rectangles = (request.results ?? []).map { obs in
                DetectedRectangle(
                    confidence: Double(obs.confidence),
                    boundingBox: BoundingBox(obs.boundingBox),
                    topLeft: Point2D(obs.topLeft),
                    topRight: Point2D(obs.topRight),
                    bottomLeft: Point2D(obs.bottomLeft),
                    bottomRight: Point2D(obs.bottomRight)
                )
            }
            return RectangleResponse(rectangles: rectangles)
        }
    }

    // MARK: - 地平线检测

    @Sendable func detectHorizonRequest(req: Request) async throws -> HorizonResponse {
        let imageData = try await InputResolver.image(from: req)

        return try await Offload.run(req) {
            let request = VNDetectHorizonRequest()
            try VisionSupport.perform([request], on: imageData)

            guard let horizon = request.results?.first else {
                return HorizonResponse(detected: false, angleRadians: nil, angleDegrees: nil)
            }
            let radians = Double(horizon.angle)
            return HorizonResponse(detected: true, angleRadians: radians, angleDegrees: radians * 180 / .pi)
        }
    }
}

// MARK: - 响应模型

struct ClassificationResult: Content {
    var identifier: String
    var confidence: Double
}

struct ClassificationResponse: Content {
    var classifications: [ClassificationResult]
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

struct DetectedFace: Content {
    var boundingBox: BoundingBox
    var confidence: Double
    /// 姿态角（弧度）
    var roll: Double?
    var yaw: Double?
    var pitch: Double?
    /// 关键点，坐标相对于人脸框归一化
    var landmarks: [String: [Point2D]]
}

struct FaceDetectionResponse: Content {
    var faces: [DetectedFace]
}

struct DetectedPose: Content {
    var confidence: Double
    /// 仅手部姿态返回：left / right / unknown
    var chirality: String?
    /// 关节点名称 → 归一化坐标与置信度
    var joints: [String: KeyPoint]
}

struct PoseResponse: Content {
    var poses: [DetectedPose]
}

struct SalientRegion: Content {
    var boundingBox: BoundingBox
    var confidence: Double
}

struct SaliencyResponse: Content {
    var type: String
    var regions: [SalientRegion]
}

struct DetectedRectangle: Content {
    var confidence: Double
    var boundingBox: BoundingBox
    var topLeft: Point2D
    var topRight: Point2D
    var bottomLeft: Point2D
    var bottomRight: Point2D
}

struct RectangleResponse: Content {
    var rectangles: [DetectedRectangle]
}

struct HorizonResponse: Content {
    var detected: Bool
    var angleRadians: Double?
    var angleDegrees: Double?
}
