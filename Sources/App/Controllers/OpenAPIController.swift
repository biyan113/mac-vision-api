// 导入必要的框架
import Foundation
import Vapor
import VaporToOpenAPI

/// OpenAPI文档控制器
/// 负责生成和提供API文档
struct OpenAPIController: RouteCollection {

    // MARK: Internal

    /// 配置路由
    /// - Parameter routes: 路由构建器
    /// - Throws: 路由配置过程中可能发生的错误
    func boot(routes: RoutesBuilder) throws {

        // 生成并提供OpenAPI文档的JSON端点
        routes.get("Swagger", "swagger.json") { req in
            req.application.routes.openAPI(
                info: InfoObject(
                    title: "Vision Restful API - OpenAPI",
                    version: Version(0, 0, 1)
                )
            )
        }
        .excludeFromOpenAPI()

        // 配置Stoplight文档查看器
        routes.stoplightDocumentation(
            "stoplight",
            openAPIPath: "/swagger/swagger.json"
        )
    }
}
