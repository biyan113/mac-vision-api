// 导入必要的框架
import Vapor

/// 配置应用程序的所有路由
/// - Parameter app: 要配置路由的应用程序实例
/// - Throws: 路由配置过程中可能发生的错误
func routes(_ app: Application) throws {
    // 设置请求体的最大大小为20MB
    // 这对于处理大型图片文件很有必要
    app.routes.defaultMaxBodySize = "20mb"

    // 配置根路由
    // 访问根路径时重定向到Swagger文档页面
    app.get { req async in
        req.redirect(to: "/Swagger/index.html")
    }

    // 注册文本检测控制器
    // 提供OCR相关的API端点
    try app.register(collection: TextDetectionController())
    
    // 注册图像特征控制器
    // 仅在macOS 15.0及以上版本可用
    if #available(macOS 15.0, *) {
        try app.register(collection: ImageFeatureController())
    } else {
        // 在较早版本上不提供此功能
    }
    
    // 注册OpenAPI（Swagger）控制器
    // 提供API文档服务
    try app.register(collection: OpenAPIController())
}
