import Vapor
import VaporToOpenAPI

/// 当前系统上可用的能力
struct Capabilities: Content {
    var textRecognition: Bool
    var pdf: Bool
    var imageAnalysis: Bool
    var backgroundRemoval: Bool
    var aesthetics: Bool
    var documentRecognition: Bool
    var lensSmudge: Bool
    var speechTranscription: Bool
    var translation: Bool

    static var current: Capabilities {
        var caps = Capabilities(
            textRecognition: true, pdf: true, imageAnalysis: true,
            backgroundRemoval: false, aesthetics: false,
            documentRecognition: false, lensSmudge: false,
            speechTranscription: false, translation: false
        )
        if #available(macOS 14.0, *) { caps.backgroundRemoval = true }
        if #available(macOS 15.0, *) { caps.aesthetics = true }
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            caps.documentRecognition = true
            caps.lensSmudge = true
            caps.speechTranscription = true
            #if canImport(Translation)
            caps.translation = true
            #endif
        }
        #endif
        return caps
    }
}

struct ServiceInfo: Content {
    var name: String
    var version: String
    var status: String
    var docs: String
    var capabilities: Capabilities
}

struct HealthStatus: Content {
    var status: String
    var version: String
    var timestamp: String
}

/// 注册全部路由。若只想把接口挂到已有的 Vapor 应用上而不使用本库的中间件，可直接调用本函数。
public func routes(_ app: Application) throws {
    // 服务信息（若 Public/index.html 存在，根路径由静态文件中间件接管）
    app.get { _ async in
        ServiceInfo(name: "Vision API", version: version, status: "ok",
                    docs: "/Swagger/index.html", capabilities: .current)
    }
    .excludeFromOpenAPI()

    app.get("capabilities") { _ async in Capabilities.current }
        .openAPI(description: "返回当前系统版本下可用的能力。", response: .type(Capabilities.self))

    // 健康检查（不需要 API Key）
    app.get("health") { _ async in
        HealthStatus(status: "healthy", version: version,
                     timestamp: ISO8601DateFormatter().string(from: Date()))
    }
    .openAPI(description: "健康检查。", response: .type(HealthStatus.self))

    try app.register(collection: OpenAPIController())
    try app.register(collection: TextDetectionController())
    try app.register(collection: PDFController())
    try app.register(collection: VisionAnalysisController())

    // 背景移除：macOS 14.0+
    if #available(macOS 14.0, *) {
        try app.register(collection: ImageFeatureController())
    }

    // 美学评分：macOS 15.0+
    if #available(macOS 15.0, *) {
        try app.register(collection: AestheticsController())
    }

    // 文档结构识别、镜头污渍检测、语音转写、翻译：macOS 26.0+（需要 Xcode 26 / Swift 6.2 编译）
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
        try app.register(collection: DocumentController())
        try app.register(collection: SpeechController())
        #if canImport(Translation)
        try app.register(collection: TranslationController())
        #endif
    }
    #endif
}
