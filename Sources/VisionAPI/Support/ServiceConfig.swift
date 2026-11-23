import Vapor

/// 服务运行配置。默认值偏向安全：不允许读取本地路径，不允许访问内网 URL。
public struct ServiceConfig: Sendable {
    /// 设置后，除 `/health` 与静态文件外的所有接口都需要携带该密钥
    /// （`Authorization: Bearer <key>` 或 `X-API-Key: <key>`）。
    public var apiKey: String?

    /// 是否允许通过 `imagePath` / `pdfPath` / `audioPath` 读取服务器本地文件。
    public var allowLocalFiles: Bool

    /// 是否允许 `imageURL` 等参数访问回环地址与内网地址。
    public var allowPrivateURLs: Bool

    /// 请求体大小上限，例如 `"50mb"`。
    public var maxBodySize: String

    public init(
        apiKey: String? = nil,
        allowLocalFiles: Bool = false,
        allowPrivateURLs: Bool = false,
        maxBodySize: String = "50mb"
    ) {
        self.apiKey = apiKey
        self.allowLocalFiles = allowLocalFiles
        self.allowPrivateURLs = allowPrivateURLs
        self.maxBodySize = maxBodySize
    }

    /// 从环境变量读取配置：
    /// `VISION_API_KEY`、`VISION_ALLOW_LOCAL_FILES`、`VISION_ALLOW_PRIVATE_URLS`、`VISION_MAX_BODY_SIZE`
    public static func fromEnvironment() -> ServiceConfig {
        func flag(_ name: String) -> Bool {
            guard let value = Environment.get(name)?.lowercased() else { return false }
            return ["1", "true", "yes", "on"].contains(value)
        }
        let key = Environment.get("VISION_API_KEY").flatMap { $0.isEmpty ? nil : $0 }
        let size = Environment.get("VISION_MAX_BODY_SIZE").flatMap { $0.isEmpty ? nil : $0 }
        return ServiceConfig(
            apiKey: key,
            allowLocalFiles: flag("VISION_ALLOW_LOCAL_FILES"),
            allowPrivateURLs: flag("VISION_ALLOW_PRIVATE_URLS"),
            maxBodySize: size ?? "50mb"
        )
    }
}

extension Application {
    private struct ServiceConfigKey: StorageKey {
        typealias Value = ServiceConfig
    }

    /// 当前服务配置
    public var serviceConfig: ServiceConfig {
        get { storage[ServiceConfigKey.self] ?? ServiceConfig() }
        set { storage[ServiceConfigKey.self] = newValue }
    }
}

/// 可选的 API Key 鉴权中间件
struct APIKeyMiddleware: AsyncMiddleware {
    let apiKey: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        if request.method == .OPTIONS || request.url.path == "/health" {
            return try await next.respond(to: request)
        }

        let provided = request.headers.bearerAuthorization?.token
            ?? request.headers.first(name: "X-API-Key")

        guard let provided, constantTimeEquals(provided, apiKey) else {
            throw Abort(.unauthorized, reason: "缺少或无效的 API Key")
        }
        return try await next.respond(to: request)
    }

    private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0 ..< a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
