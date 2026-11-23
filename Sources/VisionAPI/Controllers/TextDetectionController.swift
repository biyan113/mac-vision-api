import SwiftOpenAPI
import Vapor
import Vision

/// 文本检测控制器
/// 提供图像中文本识别（OCR）相关的 API 接口
struct TextDetectionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("text-detection")

        group.post("recognize-text", use: recognizeTextRequest)
            .openAPI(
                description: "识别图像中的文本（OCR）。支持中文、英文等多种语言；includeLines=true 时返回每行文本的位置与置信度。",
                body: .type(recognizeText.self),
                contentType: .multipart(.formData),
                response: .type(recognizeTextResponse.self)
            )

        group.get("supported-languages", use: supportedLanguagesRequest)
            .openAPI(
                description: "返回 OCR 支持的语言代码。可用 recognitionLevel 查询参数指定 0（精确）或 1（快速）。",
                response: .type(SupportedLanguagesResponse.self)
            )
    }

    @Sendable func recognizeTextRequest(req: Request) async throws -> recognizeTextResponse {
        let imageData = try await InputResolver.image(from: req)

        var languages = (try? req.content.get(String.self, at: "recognitionLanguages"))?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 只指定中文时自动补上英文，便于识别中英文混排
        if let list = languages, list.count == 1, list[0].hasPrefix("zh") {
            languages = [list[0], "en-US"]
        }

        let fast = (try? req.content.get(Int.self, at: "recognitionLevel")) == 1
        let includeLines = (try? req.content.get(Bool.self, at: "includeLines")) ?? false

        return try await Offload.run(req) { [languages] in
            let request = VNRecognizeTextRequest()
            if let languages, !languages.isEmpty {
                request.recognitionLanguages = languages
            } else {
                request.automaticallyDetectsLanguage = true
            }
            if fast {
                request.recognitionLevel = .fast
            }

            try VisionSupport.perform([request], on: imageData)

            let lines: [RecognizedLine] = (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedLine(
                    text: candidate.string,
                    confidence: Double(candidate.confidence),
                    boundingBox: BoundingBox(observation.boundingBox)
                )
            }

            return recognizeTextResponse(
                text: lines.map(\.text).joined(separator: "\n"),
                lines: includeLines ? lines : nil
            )
        }
    }

    @Sendable func supportedLanguagesRequest(req: Request) async throws -> SupportedLanguagesResponse {
        let fast = (try? req.query.get(Int.self, at: "recognitionLevel")) == 1
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        let languages = try request.supportedRecognitionLanguages()
        return SupportedLanguagesResponse(languages: languages)
    }
}

/// OCR 请求模型（仅用于 OpenAPI 文档）
@OpenAPIDescriptable
struct recognizeText: Content {
    /// 上传的图像文件（支持常见图片格式如PNG、JPEG等）
    var imageFile: Data?

    /// 服务器本地图片路径（需开启 VISION_ALLOW_LOCAL_FILES）
    var imagePath: String?

    /// 远程图片URL
    var imageURL: String?

    /// Base64编码的图片数据
    var imageBase64: String?

    /// 识别语言，使用逗号分隔的语言代码，例如 zh-Hans,en-US。不填则自动检测语言。
    var recognitionLanguages: String?

    /// 识别精度级别：0 = 精确模式（默认），1 = 快速模式
    var recognitionLevel: Int?

    /// 是否返回每行文本的位置与置信度，默认 false
    var includeLines: Bool?
}

/// 一行识别结果
struct RecognizedLine: Content {
    var text: String
    var confidence: Double
    /// 归一化坐标，原点在左下角
    var boundingBox: BoundingBox
}

/// 文本识别响应
struct recognizeTextResponse: Content {
    /// 识别到的全部文本，按行以换行符连接
    var text: String
    /// 每行文本的详细信息（includeLines=true 时返回）
    var lines: [RecognizedLine]?
}

struct SupportedLanguagesResponse: Content {
    var languages: [String]
}
