// 导入必要的框架
import Vapor
import Vision
import SwiftOpenAPI

/// 文本检测控制器
/// 提供图像中文本识别（OCR）相关的API接口
struct TextDetectionController: RouteCollection {
    /// 配置路由
    /// - Parameter routes: 路由构建器
    /// - Throws: 路由配置过程中可能发生的错误
    func boot(routes: RoutesBuilder) throws {
        let textDetectionRoute = routes.grouped("text-detection")
        // 配置文本识别接口
        textDetectionRoute.post("recognize-text", use: recognizeTextRequest)
            .openAPI(
                description: "识别图像中的文本（OCR功能）。支持中文、英文等多种语言的识别。",
                body: .type(recognizeText.self),
                contentType: .multipart(.formData),
                response: .type(recognizeTextResponse.self)
            )
    }

    /// 处理文本识别请求
    /// - Parameter req: HTTP请求
    /// - Returns: 识别到的文本响应
    /// - Throws: 处理过程中可能发生的错误
    @Sendable func recognizeTextRequest(req: Request) async throws -> recognizeTextResponse {
        // 解码请求数据
        let imageFile = try req.content.get(Data.self, at: "imageFile")
        // 获取可选参数
        let recognitionLanguages = (try? req.content.get(String.self, at: "recognitionLanguages"))?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let recognitionLevel = try? req.content.get(Int.self, at: "recognitionLevel")

        var textString = ""

        // 创建图像处理处理器
        let requestHandler = VNImageRequestHandler(data: imageFile)
        
        /// 文本识别完成后的回调处理
        func recognizeTextHandler(request: VNRequest, error: Error?) {
            guard let observations =
                request.results as? [VNRecognizedTextObservation]
            else {
                return
            }
            // 提取识别到的文本
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            // 将所有识别到的文本用换行符连接
            textString = recognizedStrings.joined(separator: "\n")
        }

        // 创建文本识别请求
        let textRequest = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)

        // 配置识别语言
        if let languages = recognitionLanguages {
            textRequest.recognitionLanguages = languages
        } else {
            textRequest.automaticallyDetectsLanguage = true
        }

        // 配置识别精度级别
        if recognitionLevel == 1 {
            textRequest.recognitionLevel = .fast
        }

        // 执行文本识别
        do {
            try requestHandler.perform([textRequest])
        } catch {
            print("无法执行识别请求: \(error).")
            textString = "无法执行识别请求: \(error)."
        }

        return recognizeTextResponse(text: textString)
    }
}

/// OpenAPI文档用的请求模型
@OpenAPIDescriptable
struct recognizeText: Content {
    /// 上传的图像文件（支持常见图片格式如PNG、JPEG等）
    var imageFile: Data

    /// 识别语言，使用逗号分隔的ISO语言代码，例如：zh,en。不填则自动检测语言。
    var recognitionLanguages: String?

    /// 识别精度级别：0 = 精确模式（默认），1 = 快速模式
    var recognitionLevel: Int?
}

/// 文本识别响应的数据模型
struct recognizeTextResponse: Content {
    /// 识别到的文本内容
    var text: String
}
