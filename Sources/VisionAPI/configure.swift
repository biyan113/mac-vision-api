import Vapor

/// 当前版本号
public let version = "1.0.0"

/// 配置应用程序：中间件、请求体限制与全部路由。
///
/// 作为库嵌入时：
/// ```swift
/// import VisionAPI
/// try await VisionAPI.configure(app, config: ServiceConfig(apiKey: "secret"))
/// ```
/// - Parameters:
///   - app: 要配置的应用程序实例
///   - config: 服务配置，默认从环境变量读取
public func configure(_ app: Application, config: ServiceConfig = .fromEnvironment()) async throws {
    app.serviceConfig = config

    // 请求体大小限制
    app.routes.defaultMaxBodySize = ByteCount(stringLiteral: validatedBodySize(config.maxBodySize, logger: app.logger))

    // 远程 URL 的重定向由 InputResolver 逐跳校验，这里关闭自动跟随
    app.http.client.configuration.redirectConfiguration = .disallow

    // CORS
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .init("X-API-Key")]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration), at: .beginning)

    // 静态文件（Swagger UI 与可选的 Web 界面）
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))

    // 可选的 API Key 鉴权（静态文件不受影响）
    if let apiKey = config.apiKey {
        app.middleware.use(APIKeyMiddleware(apiKey: apiKey))
        app.logger.notice("已启用 API Key 鉴权")
    }
    if config.allowLocalFiles {
        app.logger.warning("已开启本地路径读取（VISION_ALLOW_LOCAL_FILES），请勿暴露到不受信任的网络")
    }

    try routes(app)
}

private func validatedBodySize(_ value: String, logger: Logger) -> String {
    let lower = value.lowercased().replacingOccurrences(of: " ", with: "")
    let units = ["kb", "mb", "gb", "b"]
    for unit in units where lower.hasSuffix(unit) {
        let number = lower.dropLast(unit.count)
        if !number.isEmpty, number.allSatisfy(\.isNumber) {
            return lower
        }
    }
    logger.warning("无效的 VISION_MAX_BODY_SIZE: \(value)，使用默认值 50mb")
    return "50mb"
}
