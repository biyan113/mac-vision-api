// 导入必要的框架
import Vapor

/// 配置应用程序
/// - Parameter app: 要配置的应用程序实例
/// - Throws: 配置过程中可能发生的错误
public func configure(_ app: Application) async throws {
    // 配置请求体大小限制
    app.routes.defaultMaxBodySize = "100mb"
    
    // 配置multipart解析限制
    app.http.server.configuration.requestDecompression = .enabled(limit: .size(100 * 1024 * 1024))
    
    // 配置CORS中间件
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration), at: .beginning)
    
    // 配置静态文件中间件
    // 用于提供public目录下的静态文件服务，默认文件为index.html
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))
    
    // 注册所有路由配置
    // 这里会调用routes.swift中定义的路由设置
    try routes(app)
}
