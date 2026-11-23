import SwiftOpenAPI
// 导入必要的框架
import Vapor
import VisionCore

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
        let imageData = try await ImageInput.decode(from: req)

        // 获取可选参数
        var recognitionLanguages = (try? req.content.get(String.self, at: "recognitionLanguages"))?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // 智能语言处理：如果只指定了中文，自动添加英文支持以处理混合内容
        if let languages = recognitionLanguages, languages.count == 1 {
            let lang = languages[0]
            if lang.hasPrefix("zh") || lang == "zh" {
                // 中文用户通常会接触到英文文本，自动添加英文支持
                recognitionLanguages = [lang, "en-US"]
            }
        }

        let recognitionLevel = try? req.content.get(Int.self, at: "recognitionLevel")

        // 语言列表为空时由 Vision 自动检测语言
        let options = TextRecognitionOptions(
            languages: (recognitionLanguages ?? []).filter { !$0.isEmpty },
            fast: recognitionLevel == 1
        )

        // 执行文本识别
        let textString: String
        do {
            textString = try VisionEngine.recognizeText(imageData: imageData, options: options)
                .map { $0.text }
                .joined(separator: "\n")
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
    var imageFile: Data?

    /// 本地图片文件路径
    var imagePath: String?

    /// 远程图片URL
    var imageURL: String?

    /// Base64编码的图片数据
    var imageBase64: String?

    /// 识别语言，使用逗号分隔的语言代码。
    /// 常用值：
    /// - zh-Hans: 简体中文
    /// - zh-Hant: 繁体中文
    /// - en-US: 英文
    /// - ja: 日语
    /// - ko: 韩语
    ///
    /// 多语言混合识别：zh-Hans,en-US（可同时识别中英文）
    /// 不填则自动检测语言（推荐用于不确定文本语言的情况）
    var recognitionLanguages: String?

    /// 识别精度级别：0 = 精确模式（默认），1 = 快速模式
    var recognitionLevel: Int?
}

/// 文本识别响应的数据模型
struct recognizeTextResponse: Content {
    /// 识别到的文本内容
    var text: String
}
