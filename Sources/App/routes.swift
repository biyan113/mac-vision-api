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
    // 访问根路径时返回简单的健康检查响应
    app.get { req async in
        return ["status": "ok", "message": "Vision API is running"]
    }
    
    // 健康检查端点
    app.get("health") { req async in
        return ["status": "healthy", "timestamp": "\(Date())"]
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
    
}
