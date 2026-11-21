import Foundation
import Vapor
import VaporToOpenAPI

/// OpenAPI 文档控制器
/// Swagger UI 静态文件位于 `Public/Swagger/`，它读取同目录下的 `swagger.json`。
struct OpenAPIController: RouteCollection {
    private static var openAPIVersion: Version {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return Version(1, 0, 0) }
        return Version(parts[0], parts[1], parts[2])
    }

    func boot(routes: RoutesBuilder) throws {
        routes.get("Swagger", "swagger.json") { req in
            req.application.routes.openAPI(
                info: InfoObject(
                    title: "Vision API",
                    version: Self.openAPIVersion
                )
            )
        }
        .excludeFromOpenAPI()

        // 便捷入口
        routes.get("docs") { req in
            req.redirect(to: "/Swagger/index.html")
        }
        .excludeFromOpenAPI()
    }
}
